USE SmartWaterAuditDB;
GO
CREATE OR ALTER PROCEDURE dbo.Audit_Append
    @actor_user_id INT,
    @actor_role_name NVARCHAR(30),
    @action NVARCHAR(50),
    @object_type NVARCHAR(50),
    @object_id INT,
    @diff_json NVARCHAR(MAX) = NULL,
    @audit_id INT OUTPUT,
    @chain_hash CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @prev_hash CHAR(64) = NULL;
    DECLARE @row_text NVARCHAR(MAX);
    DECLARE @row_hash CHAR(64);
    DECLARE @timestamp_utc DATETIME2(7);

    DECLARE @zero_hash CHAR(64) = REPLICATE('0', 64);

    DECLARE @ins TABLE (audit_id INT, timestamp_utc DATETIME2(7));

    BEGIN TRY
        --------------------------------------------------------------------
        -- Transaction ownership:
        -- If caller already started a transaction, we participate in it.
        -- Otherwise, we start and commit our own.
        --------------------------------------------------------------------
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        --------------------------------------------------------------------
        -- 1) Insert AuditLog and capture the DB-generated UTC timestamp
        --------------------------------------------------------------------
        INSERT INTO dbo.AuditLog (
            actor_user_id, actor_role_name, action, object_type, object_id, diff_json
        )
        OUTPUT inserted.audit_id, inserted.[timestamp]
        INTO @ins(audit_id, timestamp_utc)
        VALUES (
            @actor_user_id, @actor_role_name, @action, @object_type, @object_id, @diff_json
        );

        SELECT TOP (1)
            @audit_id = audit_id,
            @timestamp_utc = timestamp_utc
        FROM @ins;

        --------------------------------------------------------------------
        -- 2) Read previous chain tip with locks to prevent forks
        --------------------------------------------------------------------
        SELECT TOP (1) @prev_hash = chain_hash
        FROM dbo.HashChain WITH (UPDLOCK, HOLDLOCK)
        ORDER BY anchor_id DESC;

        --------------------------------------------------------------------
        -- 3) Canonical row representation (stable ordering, explicit NULLs)
        --------------------------------------------------------------------
        SET @row_text = CONCAT(
            'audit_id=', @audit_id, '|',
            'timestamp_utc=', CONVERT(NVARCHAR(33), @timestamp_utc, 126), '|',
            'actor_user_id=', @actor_user_id, '|',
            'actor_role=', @actor_role_name, '|',
            'action=', @action, '|',
            'object_type=', @object_type, '|',
            'object_id=', @object_id, '|',
            'diff=', COALESCE(@diff_json, '<NULL>')
        );

        --------------------------------------------------------------------
        -- 4) row_hash = SHA256( UTF-16LE bytes of NVARCHAR row_text )
        --------------------------------------------------------------------
        SET @row_hash = CONVERT(CHAR(64),
            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @row_text)),
        2);

        --------------------------------------------------------------------
        -- 5) chain_hash = SHA256( prev_or_zero | row_hash )
        --------------------------------------------------------------------
        DECLARE @chain_input NVARCHAR(MAX) =
            CONCAT(COALESCE(@prev_hash, @zero_hash), '|', @row_hash);

        SET @chain_hash = CONVERT(CHAR(64),
            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @chain_input)),
        2);

        --------------------------------------------------------------------
        -- 6) Persist chain link (1-to-1 with AuditLog via UNIQUE(audit_id))
        --------------------------------------------------------------------
        INSERT INTO dbo.HashChain (audit_id, prev_hash, row_hash, chain_hash)
        VALUES (@audit_id, @prev_hash, @row_hash, @chain_hash);

        --------------------------------------------------------------------
        -- Commit only if we started the transaction
        --------------------------------------------------------------------
        IF @started_tran = 1
            COMMIT;
    END TRY
    BEGIN CATCH
        --------------------------------------------------------------------
        -- Rollback only if we started it.
        -- If caller owns the transaction, let caller decide rollback/commit.
        --------------------------------------------------------------------
        IF @started_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK;

        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Role_Assign
    @target_user_id          INT,
    @role_name               NVARCHAR(30),
    @assigned_by_user_id     INT,
    @assigned_by_role_name   NVARCHAR(30),
    @audit_action NVARCHAR(80) = N'ASSIGN_ROLE'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @started_tran BIT = 0;

    DECLARE @role_id     INT;
    DECLARE @audit_id    INT;
    DECLARE @chain_hash  CHAR(64);
    DECLARE @diff        NVARCHAR(MAX);
    DECLARE @rn NVARCHAR(30) = UPPER(LTRIM(RTRIM(@role_name)));

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END
        SELECT @role_id = r.role_id
        FROM dbo.Roles r
        WHERE r.role_name = @rn;

        IF @role_id IS NULL
            THROW 50001, 'Role not found.', 1;

        -- Ensure not already active
        IF EXISTS (
            SELECT 1
            FROM dbo.UserRole ur
            WHERE ur.user_id = @target_user_id
              AND ur.role_id = @role_id
              AND ur.revoked_at IS NULL
        )
            THROW 50005, 'Role already assigned (active).', 1;

        INSERT INTO dbo.UserRole (user_id, role_id, assigned_by_user_id)
        VALUES (@target_user_id, @role_id, @assigned_by_user_id);

        SELECT @diff =
        (
            SELECT
                @target_user_id AS target_user_id,
                @rn      AS role
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @assigned_by_user_id,
            @actor_role_name = @assigned_by_role_name,
            @action          = @audit_action,
            @object_type     = N'UserRole',
            @object_id       = @target_user_id,
            @diff_json       = @diff,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
        COMMIT;    
    END TRY
    BEGIN CATCH
        IF @started_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Role_Revoke
    @target_user_id          INT,
    @role_name               NVARCHAR(30),
    @revoked_by_user_id      INT,
    @revoked_by_role_name    NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @role_id INT;
    DECLARE @audit_id INT;
    DECLARE @chain_hash CHAR(64);
    DECLARE @diff NVARCHAR(MAX);
    DECLARE @normalized_role NVARCHAR(30);

    BEGIN TRY
        BEGIN TRAN;

        /* 0) Normalize inputs */
        SET @normalized_role = UPPER(LTRIM(RTRIM(@role_name)));

        /* 1) Policy guard: prevent ADMIN role revocation (simple governance rule) */
        IF @normalized_role = N'ADMIN'
            THROW 54001, 'Revoking ADMIN role is not permitted by policy.', 1;

        /* 2) Resolve role */
        SELECT @role_id = r.role_id
        FROM dbo.Roles AS r
        WHERE r.role_name = @normalized_role;

        IF @role_id IS NULL
            THROW 50002, 'Role not found.', 1;

        /* 3) Identify the latest active assignment row */
        DECLARE @assigned_at DATETIME2(7);

        SELECT TOP (1) @assigned_at = ur.assigned_at
        FROM dbo.UserRole AS ur
        WHERE ur.user_id = @target_user_id
          AND ur.role_id = @role_id
          AND ur.revoked_at IS NULL
        ORDER BY ur.assigned_at DESC;

        IF @assigned_at IS NULL
            THROW 50003, 'Active role assignment not found.', 1;

        /* 4) Revoke that exact row (race-safe) */
        UPDATE dbo.UserRole
        SET revoked_at = SYSUTCDATETIME()
        WHERE user_id = @target_user_id
          AND role_id = @role_id
          AND assigned_at = @assigned_at
          AND revoked_at IS NULL;

        IF @@ROWCOUNT = 0
            THROW 50003, 'Active role assignment not found.', 1;

        /* 5) Build diff_json safely */
        SELECT @diff =
        (
            SELECT
                @target_user_id     AS target_user_id,
                @normalized_role    AS role
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        /* 6) Append audit */
        EXEC dbo.Audit_Append
            @actor_user_id   = @revoked_by_user_id,
            @actor_role_name = @revoked_by_role_name,
            @action          = N'REVOKE_ROLE',
            @object_type     = N'UserRole',
            @object_id       = @target_user_id,
            @diff_json       = @diff,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.User_UpdateStatus
    @target_user_id        INT,
    @new_status            NVARCHAR(20),
    @changed_by_user_id    INT,
    @changed_by_role_name  NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @audit_id INT, @chain_hash CHAR(64);
    DECLARE @old_status NVARCHAR(20);
    DECLARE @normalized_status NVARCHAR(20);
    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRAN;

        /* -----------------------------
           0) Normalize input
           ----------------------------- */
        SET @normalized_status = UPPER(LTRIM(RTRIM(@new_status)));

        /* -----------------------------
           1) Load current status + validate target exists
           ----------------------------- */
        SELECT @old_status = u.status
        FROM dbo.Users u
        WHERE u.user_id = @target_user_id;

        IF @old_status IS NULL
            THROW 53001, 'Target user not found.', 1;

        /* -----------------------------
           2) Block changes for ADMIN targets (active admin role)
           ----------------------------- */
        IF EXISTS (
            SELECT 1
            FROM dbo.UserRole ur
            JOIN dbo.Roles r ON r.role_id = ur.role_id
            WHERE ur.user_id = @target_user_id
              AND ur.revoked_at IS NULL
              AND r.role_name = 'ADMIN'
        )
            THROW 53002, 'Cannot change status for an ADMIN account.', 1;

        /* -----------------------------
           3) No-op guard (optional but clean)
           ----------------------------- */
        IF @old_status = @normalized_status
            THROW 53003, 'User already has the requested status.', 1;

        /* -----------------------------
           4) Update
           - CHECK constraint on Users.status enforces allowed values
           ----------------------------- */
        UPDATE dbo.Users
        SET status = @normalized_status
        WHERE user_id = @target_user_id;

        IF @@ROWCOUNT <> 1
            THROW 53004, 'Status update failed unexpectedly.', 1;

        /* -----------------------------
           5) Audit + hash chain
           ----------------------------- */
        SELECT @diff_json =
        (
            SELECT
                @target_user_id      AS target_user_id,
                @old_status          AS old_status,
                @normalized_status   AS new_status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @changed_by_user_id,
            @actor_role_name = @changed_by_role_name,
            @action          = N'CHANGE_USER_STATUS',
            @object_type     = N'Users',
            @object_id       = @target_user_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.User_Create
    @username             NVARCHAR(50),
    @password_hash        NVARCHAR(255),
    @status               NVARCHAR(20) = NULL,     -- NULL => let DB default apply
    @created_by_user_id   INT,
    @created_by_role_name NVARCHAR(30),
    @new_user_id          INT OUTPUT,
    @audit_action NVARCHAR(80) = N'CREATE_USER'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @started_tran BIT = 0;
    DECLARE @audit_id   INT;
    DECLARE @chain_hash CHAR(64);
    DECLARE @diff_json  NVARCHAR(MAX);

    DECLARE @u NVARCHAR(50) = LTRIM(RTRIM(@username));

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END
        -- Insert + capture identity and effective status
        DECLARE @ins TABLE (user_id INT, status NVARCHAR(20));

        IF @status IS NULL
        BEGIN
            INSERT INTO dbo.Users (username, password_hash)
            OUTPUT inserted.user_id, inserted.status INTO @ins(user_id, status)
            VALUES (@u, @password_hash);
        END
        ELSE
        BEGIN
            INSERT INTO dbo.Users (username, password_hash, status)
            OUTPUT inserted.user_id, inserted.status INTO @ins(user_id, status)
            VALUES (@u, @password_hash, @status);
        END

        DECLARE @effective_status NVARCHAR(20);

        SELECT TOP (1)
            @new_user_id = user_id,
            @effective_status = status
        FROM @ins;

        -- Build audit diff (do NOT include password_hash)
        SELECT @diff_json =
        (
            SELECT
                @new_user_id        AS new_user_id,
                @u                  AS username,
                @effective_status   AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- Audit append in the same transaction (atomic with user creation)
        EXEC dbo.Audit_Append
            @actor_user_id   = @created_by_user_id,
            @actor_role_name = @created_by_role_name,
            @action          = @audit_action,
            @object_type     = N'Users',
            @object_id       = @new_user_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
        COMMIT;
    END TRY
    BEGIN CATCH
        DECLARE @err INT = ERROR_NUMBER();

        IF @started_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK;

        -- Unique username violation
        IF @err IN (2601, 2627)
            THROW 50011, 'Username already exists.', 1;

        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.RolePerm_Grant_Batch
    @role_name            NVARCHAR(30),
    @perm_list_json       NVARCHAR(MAX),   -- JSON array: [{"module":"X","action":"READ"}, ...]
    @granted_by_user_id   INT,
    @granted_by_role_name NVARCHAR(30),
    @audit_action         NVARCHAR(80) = N'GRANT_ROLEPERM_BULK'  -- e.g., BOOTSTRAP_SEED_ROLEPERM_TECHNICIAN
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @r NVARCHAR(50) = UPPER(LTRIM(RTRIM(@role_name)));
    DECLARE @role_id INT;

    DECLARE @audit_id INT, @chain_hash CHAR(64);
    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRAN;

        /* 1) Resolve role_id */
        SELECT @role_id = r.role_id
        FROM dbo.Roles r
        WHERE r.role_name = @r;

        IF @role_id IS NULL
            THROW 50101, 'Role not found.', 1;

        /* 2) Parse JSON perm list into a table variable (normalize identifiers) */
        DECLARE @wanted TABLE (
            module NVARCHAR(50) NOT NULL,
            action NVARCHAR(10) NOT NULL,
            PRIMARY KEY (module, action)
        );

        INSERT INTO @wanted(module, action)
        SELECT
            UPPER(LTRIM(RTRIM(j.[module]))) AS module,
            UPPER(LTRIM(RTRIM(j.[action]))) AS action
        FROM OPENJSON(@perm_list_json)
        WITH (
            [module] NVARCHAR(50) '$.module',
            [action] NVARCHAR(10) '$.action'
        ) AS j;

        /* 3) Insert missing RolePerm rows (idempotent) */
        DECLARE @inserted TABLE (permission_id INT);

        INSERT INTO dbo.RolePerm (role_id, permission_id, granted_by_user_id)
        OUTPUT inserted.permission_id INTO @inserted(permission_id)
        SELECT
            @role_id,
            p.permission_id,
            @granted_by_user_id
        FROM @wanted w
        JOIN dbo.Permissions p
          ON p.module = w.module
         AND p.action = w.action
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.RolePerm rp
            WHERE rp.role_id = @role_id
              AND rp.permission_id = p.permission_id
        );

        DECLARE @inserted_count INT = (SELECT COUNT(*) FROM @inserted);


        SELECT @diff_json =
        (
            SELECT
                @r AS role,
                @granted_by_user_id AS granted_by_user_id,
                @inserted_count AS inserted_count,
                JSON_QUERY(@perm_list_json) AS requested_permissions
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        /* 5) Audit as a single semantic event */
        EXEC dbo.Audit_Append
            @actor_user_id   = @granted_by_user_id,
            @actor_role_name = @granted_by_role_name,
            @action          = @audit_action,
            @object_type     = N'RolePerm',
            @object_id       = @role_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Alert_Create
    @session_id       INT,
    @ml_risk_score    FLOAT = NULL,
    @reason_json      NVARCHAR(MAX) = NULL,
    @actor_user_id    INT,
    @actor_role_name  NVARCHAR(30),
    @new_alert_id     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @device_id INT,
        @profile_id INT,
        @target_ml INT,
        @actual_ml DECIMAL(8,3),
        @cup_present BIT,
        @result_code NVARCHAR(20),
        @stop_reason NVARCHAR(20),
        @start_reason NVARCHAR(20),
        @time_source NVARCHAR(16),
        @started_at DATETIME2(7),
        @ended_at DATETIME2(7);

    DECLARE
        @tolerance_ml INT,
        @max_flow_rate DECIMAL(8,3),
        @max_duration_s INT;

    DECLARE
        @derived_peak_flow DECIMAL(8,3) = 0,
        @expired_calib_id INT = NULL,
        @expired_sensor_type_id INT = NULL,
        @expired_valid_to DATETIME2(7) = NULL;

    DECLARE
        @alert_type NVARCHAR(30) = NULL,
        @risk_score FLOAT = NULL,
        @rule_summary NVARCHAR(512) = NULL,
        @sensor_log_id BIGINT = NULL;

    DECLARE
        @audit_id INT,
        @chain_hash CHAR(64),
        @diff_json NVARCHAR(MAX);

    DECLARE @started_tran BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        /* 1) Load session */
        SELECT
            @device_id    = ps.device_id,
            @profile_id   = ps.profile_id,
            @target_ml    = ps.target_ml,
            @actual_ml    = ps.actual_ml,
            @cup_present  = ps.cup_present,
            @result_code  = ps.result_code,
            @stop_reason  = ps.stop_reason,
            @start_reason = ps.start_reason,
            @time_source  = ps.time_source,
            @started_at   = ps.started_at,
            @ended_at     = ps.ended_at
        FROM dbo.PourSession AS ps
        WHERE ps.session_id = @session_id;

        IF @device_id IS NULL
            THROW 52001, 'Session not found.', 1;

        /* 2) Load profile thresholds */
        SELECT
            @tolerance_ml   = pp.tolerance_ml,
            @max_flow_rate  = CAST(pp.max_flow_rate AS DECIMAL(8,3)),
            @max_duration_s = pp.max_duration_s
        FROM dbo.PourProfile AS pp
        WHERE pp.profile_id = @profile_id;

        IF @tolerance_ml IS NULL
            THROW 52002, 'PourProfile not found for session.', 1;

        /* 3) Derive peak flow from session FLOW logs
              Prefer filtered_value when usable; otherwise use measured_value */
        ;WITH FlowCandidates AS (
            SELECT
                sl.log_id,
                sl.recorded_at,
                CAST(
                    CASE
                        WHEN slm.log_id IS NOT NULL
                         AND slm.usable_for_alerting = 1
                         AND slm.is_outlier = 0
                         AND slm.filtered_value IS NOT NULL
                            THEN slm.filtered_value

                        WHEN slm.log_id IS NULL
                            THEN sl.measured_value

                        WHEN slm.usable_for_alerting = 1
                         AND slm.is_outlier = 0
                            THEN sl.measured_value

                        ELSE NULL
                    END
                    AS DECIMAL(12,4)
                ) AS flow_value_ml_s
            FROM dbo.SensorLog AS sl
            INNER JOIN dbo.SensorType AS st
                ON st.sensor_type_id = sl.sensor_type_id
            LEFT JOIN dbo.SensorLogMeta AS slm
                ON slm.log_id = sl.log_id
            WHERE sl.session_id = @session_id
              AND sl.device_id  = @device_id
              AND st.sensor_name = N'FLOW'
        )
        SELECT
            @derived_peak_flow =
                CAST(COALESCE(MAX(fc.flow_value_ml_s), 0) AS DECIMAL(8,3))
        FROM FlowCandidates AS fc;

        /* 4) Check whether any calibration linked to this session is expired
              at or before session end */
        SELECT TOP (1)
            @expired_calib_id = c.calib_id,
            @expired_sensor_type_id = psc.sensor_type_id,
            @expired_valid_to = c.valid_to
        FROM dbo.PourSessionCalibration AS psc
        INNER JOIN dbo.Calibration AS c
            ON c.calib_id = psc.calib_id
        WHERE psc.session_id = @session_id
          AND c.valid_to IS NOT NULL
          AND @started_at >= c.valid_to
        ORDER BY c.valid_to ASC, psc.sensor_type_id ASC;

        /* 5) Decide alert type (priority order) */
        IF (@result_code = N'NO_CUP' OR @cup_present = 0)
        BEGIN
            SET @alert_type = N'CUP_MISSING';
            SET @risk_score = 0.80;
            SET @rule_summary = N'Cup missing detected (result_code=NO_CUP or cup_present=0).';
        END
        ELSE IF (
            @result_code = N'OVER_POUR'
            OR CONVERT(FLOAT, @actual_ml) > CONVERT(FLOAT, @target_ml + @tolerance_ml)
        )
        BEGIN
            DECLARE @over_by_ml FLOAT =
                CONVERT(FLOAT, @actual_ml) - CONVERT(FLOAT, @target_ml + @tolerance_ml);

            DECLARE @tol_over FLOAT = NULLIF(CONVERT(FLOAT, @tolerance_ml), 0);

            SET @alert_type = N'OVERPOUR';

            SET @risk_score =
                CASE
                    WHEN @over_by_ml <= 0 THEN 0.50
                    WHEN @tol_over IS NULL THEN 1.0
                    WHEN @over_by_ml / @tol_over > 1.0 THEN 1.0
                    ELSE @over_by_ml / @tol_over
                END;

            SET @rule_summary = N'Overpour condition met: actual_ml exceeds target_ml + tolerance_ml.';
        END
        ELSE IF (
            @max_flow_rate IS NOT NULL
            AND CONVERT(FLOAT, @derived_peak_flow) > CONVERT(FLOAT, @max_flow_rate)
        )
        BEGIN
            DECLARE @peak_excess FLOAT =
                CONVERT(FLOAT, @derived_peak_flow) - CONVERT(FLOAT, @max_flow_rate);

            DECLARE @maxf FLOAT = NULLIF(CONVERT(FLOAT, @max_flow_rate), 0);

            SET @alert_type = N'FLOW_SPIKE';

            SET @risk_score =
                CASE
                    WHEN @peak_excess <= 0 THEN 0.50
                    WHEN @maxf IS NULL THEN 1.0
                    WHEN @peak_excess / @maxf > 1.0 THEN 1.0
                    ELSE @peak_excess / @maxf
                END;

            SET @rule_summary =
                CONCAT(
                    N'Flow spike detected: derived peak flow ',
                    CONVERT(NVARCHAR(40), @derived_peak_flow),
                    N' exceeds profile max_flow_rate ',
                    CONVERT(NVARCHAR(40), @max_flow_rate),
                    N'.'
                );
        END
        ELSE IF (@expired_calib_id IS NOT NULL)
        BEGIN
            SET @alert_type = N'CALIBRATION_EXPIRED';
            SET @risk_score = 0.60;
            SET @rule_summary =
                CONCAT(
                    N'Calibration expired for sensor_type_id=',
                    CONVERT(NVARCHAR(20), @expired_sensor_type_id),
                    N' (calib_id=',
                    CONVERT(NVARCHAR(20), @expired_calib_id),
                    N', valid_to=',
                    CONVERT(NVARCHAR(40), @expired_valid_to, 126),
                    N').'
                );
        END
        ELSE IF (@ml_risk_score IS NOT NULL AND @ml_risk_score >= 0.80)
        BEGIN
            SET @alert_type = N'ML_ANOMALY';
            SET @risk_score =
                CASE
                    WHEN @ml_risk_score > 1.0 THEN 1.0
                    WHEN @ml_risk_score < 0.0 THEN 0.0
                    ELSE @ml_risk_score
                END;
            SET @rule_summary = N'ML drift score exceeded threshold.';
        END

        /* No alert => exit cleanly */
        IF @alert_type IS NULL
        BEGIN
            SET @new_alert_id = NULL;
            IF @started_tran = 1 COMMIT;
            RETURN;
        END

        /* 6) Select representative sensor evidence (optional) */
        IF @alert_type = N'FLOW_SPIKE'
        BEGIN
            ;WITH FlowCandidates AS (
                SELECT
                    sl.log_id,
                    sl.recorded_at,
                    CAST(
                        CASE
                            WHEN slm.log_id IS NOT NULL
                             AND slm.usable_for_alerting = 1
                             AND slm.is_outlier = 0
                             AND slm.filtered_value IS NOT NULL
                                THEN slm.filtered_value

                            WHEN slm.log_id IS NULL
                                THEN sl.measured_value

                            WHEN slm.usable_for_alerting = 1
                             AND slm.is_outlier = 0
                                THEN sl.measured_value

                            ELSE NULL
                        END
                        AS DECIMAL(12,4)
                    ) AS flow_value_ml_s
                FROM dbo.SensorLog AS sl
                INNER JOIN dbo.SensorType AS st
                    ON st.sensor_type_id = sl.sensor_type_id
                LEFT JOIN dbo.SensorLogMeta AS slm
                    ON slm.log_id = sl.log_id
                WHERE sl.session_id = @session_id
                  AND sl.device_id  = @device_id
                  AND st.sensor_name = N'FLOW'
            )
            SELECT TOP (1)
                @sensor_log_id = fc.log_id
            FROM FlowCandidates AS fc
            WHERE fc.flow_value_ml_s IS NOT NULL
            ORDER BY fc.flow_value_ml_s DESC, fc.recorded_at DESC, fc.log_id DESC;
        END
        ELSE IF @alert_type = N'CUP_MISSING'
        BEGIN
            SELECT TOP (1)
                @sensor_log_id = sl.log_id
            FROM dbo.SensorLog AS sl
            WHERE sl.session_id = @session_id
              AND sl.device_id  = @device_id
            ORDER BY sl.recorded_at DESC, sl.log_id DESC;
        END

        /* 7) Insert Alert */
        DECLARE @ins_alert TABLE (alert_id INT);

        INSERT INTO dbo.Alert (
            device_id,
            session_id,
            alert_type,
            risk_score
        )
        OUTPUT inserted.alert_id INTO @ins_alert(alert_id)
        VALUES (
            @device_id,
            @session_id,
            @alert_type,
            @risk_score
        );

        SELECT @new_alert_id = alert_id
        FROM @ins_alert;

        /* 8) Insert AlertEvidence */
        INSERT INTO dbo.AlertEvidence (
            alert_id,
            evidence_type,
            sensor_log_id,
            summary_text
        )
        VALUES (
            @new_alert_id,
            N'RULE',
            NULL,
            @rule_summary
        );

        IF @ml_risk_score IS NOT NULL
        BEGIN
            INSERT INTO dbo.AlertEvidence (
                alert_id,
                evidence_type,
                sensor_log_id,
                summary_text
            )
            VALUES (
                @new_alert_id,
                N'SYSTEM',
                NULL,
                CONCAT(
                    N'ML risk score provided by application: ',
                    CONVERT(NVARCHAR(40), @ml_risk_score)
                )
            );
        END

        IF @sensor_log_id IS NOT NULL
        BEGIN
            INSERT INTO dbo.AlertEvidence (
                alert_id,
                evidence_type,
                sensor_log_id,
                summary_text
            )
            VALUES (
                @new_alert_id,
                N'SENSOR',
                @sensor_log_id,
                N'Representative sensor sample linked to alert.'
            );
        END

        /* 9) Optional AlertReason */
        IF @reason_json IS NOT NULL AND ISJSON(@reason_json) = 1
        BEGIN
            INSERT INTO dbo.AlertReason (
                alert_id,
                feature_name,
                contribution,
                importance_rank
            )
            SELECT
                @new_alert_id,
                j.feature_name,
                j.contribution,
                j.importance_rank
            FROM OPENJSON(@reason_json)
            WITH (
                feature_name    NVARCHAR(50) '$.feature_name',
                contribution    DECIMAL(6,4) '$.contribution',
                importance_rank INT          '$.importance_rank'
            ) AS j;
        END

        /* 10) Audit */
        SELECT @diff_json =
        (
            SELECT
                @new_alert_id         AS alert_id,
                @device_id            AS device_id,
                @session_id           AS session_id,
                @alert_type           AS alert_type,
                @risk_score           AS risk_score,
                @rule_summary         AS rule_summary,
                @sensor_log_id        AS representative_sensor_log_id,
                @ml_risk_score        AS ml_risk_score,
                @derived_peak_flow    AS derived_peak_flow,
                @expired_calib_id     AS expired_calib_id,
                @expired_sensor_type_id AS expired_sensor_type_id,
                @start_reason         AS session_start_reason,
                @stop_reason          AS session_stop_reason,
                @time_source          AS session_time_source
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'ALERT_CREATED',
            @object_type     = N'Alert',
            @object_id       = @new_alert_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
            COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
            ROLLBACK;
        THROW;
    END CATCH
END;
GO  
CREATE OR ALTER PROCEDURE dbo.Alert_Resolve_Maintenance
    @alert_id                INT,
    @device_id               INT,
    @ticket_type             NVARCHAR(20),
    @action_code             NVARCHAR(30),

    @ticket_note             NVARCHAR(255) = NULL,
    @log_note                NVARCHAR(500) = NULL,

    @actor_user_id           INT,
    @actor_role_name         NVARCHAR(30),
    @evidence_id             INT = NULL,

    @new_ticket_id           INT OUTPUT,
    @new_maintenance_log_id  INT OUTPUT,
    @audit_id                INT OUTPUT,
    @chain_hash              CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;
    DECLARE @now DATETIME2(7) = SYSUTCDATETIME();

    DECLARE
        @old_status       NVARCHAR(20),
        @old_assigned_to  INT,
        @old_resolved_at  DATETIME2(7),
        @alert_type       NVARCHAR(30),
        @risk_score       DECIMAL(5,4),
        @session_id       INT,
        @diff_json        NVARCHAR(MAX);

    BEGIN TRY
        SET @ticket_type      = UPPER(LTRIM(RTRIM(@ticket_type)));
        SET @action_code      = UPPER(LTRIM(RTRIM(@action_code)));
        SET @actor_role_name  = UPPER(LTRIM(RTRIM(@actor_role_name)));

        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        SELECT
            @old_status      = a.status,
            @old_assigned_to = a.assigned_to,
            @old_resolved_at = a.resolved_at,
            @alert_type      = a.alert_type,
            @risk_score      = a.risk_score,
            @session_id      = a.session_id
        FROM dbo.Alert a WITH (UPDLOCK, HOLDLOCK)
        WHERE a.alert_id = @alert_id
          AND a.device_id = @device_id;

        IF @old_status IS NULL
            THROW 54001, 'Alert not found for the specified alert_id and device_id.', 1;

        IF @old_status IN (N'RESOLVED', N'DISMISSED')
            THROW 54002, 'Alert is already in a terminal state and cannot be resolved again.', 1;

        IF @evidence_id IS NOT NULL
           AND NOT EXISTS (
                SELECT 1
                FROM dbo.AlertEvidence ae
                WHERE ae.evidence_id = @evidence_id
                  AND ae.alert_id = @alert_id
           )
            THROW 54003, 'evidence_id does not belong to the specified alert.', 1;

        UPDATE dbo.Alert
        SET
            status      = N'RESOLVED',
            resolved_at = @now,
            assigned_to = @actor_user_id
        WHERE alert_id = @alert_id
          AND device_id = @device_id;

        DECLARE @ins_ticket TABLE (
            ticket_id INT NOT NULL PRIMARY KEY
        );

        INSERT INTO dbo.MaintenanceTicket (
            device_id,
            ticket_type,
            note,
            status,
            opened_at,
            closed_at
        )
        OUTPUT inserted.ticket_id
        INTO @ins_ticket(ticket_id)
        VALUES (
            @device_id,
            @ticket_type,
            @ticket_note,
            N'CLOSED',
            @now,
            @now
        );

        SELECT @new_ticket_id = ticket_id
        FROM @ins_ticket;

        DECLARE @ins_log TABLE (
            maintenance_log_id INT NOT NULL PRIMARY KEY
        );

        INSERT INTO dbo.MaintenanceLog (
            ticket_id,
            technician_id,
            action_code,
            note,
            evidence_id
        )
        OUTPUT inserted.maintenance_log_id
        INTO @ins_log(maintenance_log_id)
        VALUES (
            @new_ticket_id,
            @actor_user_id,
            @action_code,
            @log_note,
            @evidence_id
        );

        SELECT @new_maintenance_log_id = maintenance_log_id
        FROM @ins_log;

        SELECT @diff_json =
        (
            SELECT
                @alert_id               AS alert_id,
                @device_id              AS device_id,
                @session_id             AS session_id,
                @alert_type             AS alert_type,
                @risk_score             AS risk_score,

                @old_status             AS old_status,
                N'RESOLVED'             AS new_status,
                @old_assigned_to        AS old_assigned_to,
                @actor_user_id          AS new_assigned_to,
                @old_resolved_at        AS old_resolved_at,
                @now                    AS new_resolved_at,

                @new_ticket_id          AS ticket_id,
                @ticket_type            AS ticket_type,
                @ticket_note            AS ticket_note,

                @new_maintenance_log_id AS maintenance_log_id,
                @action_code            AS action_code,
                @log_note               AS log_note,
                @evidence_id            AS evidence_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'ALERT_RESOLVED_WITH_MAINTENANCE',
            @object_type     = N'Alert',
            @object_id       = @alert_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
            COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.SensorType_Resolve_Batch
    @telemetry_json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF @telemetry_json IS NULL OR ISJSON(@telemetry_json) <> 1
        THROW 54010, 'telemetry_json must be a valid JSON array.', 1;

    DECLARE @mapped TABLE (
        sensor_name     NVARCHAR(30) NOT NULL,
        sensor_type_id  INT NULL,
        measured_value  FLOAT NULL,
        t_offset_ms     INT NULL
    );

    INSERT INTO @mapped(sensor_name, sensor_type_id, measured_value, t_offset_ms)
    SELECT
        r.sensor_name,
        st.sensor_type_id,
        r.measured_value,
        r.t_offset_ms
    FROM (
        SELECT
            UPPER(LTRIM(RTRIM(j.sensor_name))) AS sensor_name,
            j.measured_value AS measured_value,
            j.t_offset_ms AS t_offset_ms
        FROM OPENJSON(@telemetry_json)
        WITH (
            sensor_name     NVARCHAR(30) '$.sensor_name',
            measured_value  FLOAT        '$.value',
            t_offset_ms     INT          '$.t_offset_ms'
        ) AS j
    ) AS r
    LEFT JOIN dbo.SensorType st
      ON st.sensor_name = r.sensor_name;

    IF EXISTS (SELECT 1 FROM @mapped WHERE sensor_type_id IS NULL)
        THROW 54011, 'Unknown sensor_name found in telemetry_json.', 1;

    IF EXISTS (SELECT 1 FROM @mapped WHERE measured_value IS NULL OR t_offset_ms IS NULL)
        THROW 54012, 'Invalid telemetry row: value or t_offset_ms is missing/invalid.', 1;

    SELECT
        sensor_type_id,
        measured_value,
        t_offset_ms
    FROM @mapped
    ORDER BY t_offset_ms ASC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.SensorLog_Health_Ingest
    @device_id        INT,
    @health_json      NVARCHAR(MAX),   -- JSON array of health rows

    @actor_user_id    INT = 2,
    @actor_role_name  NVARCHAR(30) = N'SYSTEM',

    @audit_id         INT OUTPUT,
    @chain_hash       CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @health_json IS NULL OR ISJSON(@health_json) <> 1
        THROW 54020, 'health_json must be a valid JSON array.', 1;

    DECLARE
        @now                DATETIME2(7) = SYSUTCDATETIME(),
        @diff_json          NVARCHAR(MAX),
        @input_row_count    INT = 0,
        @inserted_log_count INT = 0,
        @inserted_meta_count INT = 0,
        @sensor_summary_json NVARCHAR(MAX) = N'[]';

    BEGIN TRY
        SET @actor_role_name = UPPER(LTRIM(RTRIM(@actor_role_name)));

        BEGIN TRAN;

        DECLARE @mapped TABLE (
            array_index          INT            NOT NULL PRIMARY KEY,
            sensor_name          NVARCHAR(30)   NOT NULL,
            sensor_type_id       INT            NULL,
            measured_value       DECIMAL(12,4)  NULL,

            filtered_value       DECIMAL(12,4)  NULL,
            is_outlier           BIT            NULL,
            interference_flag    BIT            NULL,
            usable_for_ml        BIT            NULL,
            usable_for_alerting  BIT            NULL,
            quality_score        DECIMAL(5,4)   NULL,
            reference_type       NVARCHAR(20)   NULL,
            reference_value      DECIMAL(12,4)  NULL,
            consistency_error    DECIMAL(12,4)  NULL,
            meta_note            NVARCHAR(200)  NULL
        );

        INSERT INTO @mapped (
            array_index,
            sensor_name,
            sensor_type_id,
            measured_value,
            filtered_value,
            is_outlier,
            interference_flag,
            usable_for_ml,
            usable_for_alerting,
            quality_score,
            reference_type,
            reference_value,
            consistency_error,
            meta_note
        )
        SELECT
            CONVERT(INT, j.[key]) AS array_index,
            r.sensor_name,
            st.sensor_type_id,
            r.measured_value,
            r.filtered_value,
            r.is_outlier,
            r.interference_flag,
            r.usable_for_ml,
            r.usable_for_alerting,
            r.quality_score,
            r.reference_type,
            r.reference_value,
            r.consistency_error,
            r.meta_note
        FROM OPENJSON(@health_json) j
        CROSS APPLY (
            SELECT
                UPPER(LTRIM(RTRIM(JSON_VALUE(j.value, '$.sensor_name')))) AS sensor_name,
                TRY_CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.value')) AS measured_value,
                TRY_CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.filtered_value')) AS filtered_value,

                CASE
                    WHEN JSON_VALUE(j.value, '$.is_outlier') IS NULL THEN NULL
                    WHEN UPPER(JSON_VALUE(j.value, '$.is_outlier')) IN ('1', 'TRUE') THEN CONVERT(BIT, 1)
                    WHEN UPPER(JSON_VALUE(j.value, '$.is_outlier')) IN ('0', 'FALSE') THEN CONVERT(BIT, 0)
                    ELSE NULL
                END AS is_outlier,

                CASE
                    WHEN JSON_VALUE(j.value, '$.interference_flag') IS NULL THEN NULL
                    WHEN UPPER(JSON_VALUE(j.value, '$.interference_flag')) IN ('1', 'TRUE') THEN CONVERT(BIT, 1)
                    WHEN UPPER(JSON_VALUE(j.value, '$.interference_flag')) IN ('0', 'FALSE') THEN CONVERT(BIT, 0)
                    ELSE NULL
                END AS interference_flag,

                CASE
                    WHEN JSON_VALUE(j.value, '$.usable_for_ml') IS NULL THEN NULL
                    WHEN UPPER(JSON_VALUE(j.value, '$.usable_for_ml')) IN ('1', 'TRUE') THEN CONVERT(BIT, 1)
                    WHEN UPPER(JSON_VALUE(j.value, '$.usable_for_ml')) IN ('0', 'FALSE') THEN CONVERT(BIT, 0)
                    ELSE NULL
                END AS usable_for_ml,

                CASE
                    WHEN JSON_VALUE(j.value, '$.usable_for_alerting') IS NULL THEN NULL
                    WHEN UPPER(JSON_VALUE(j.value, '$.usable_for_alerting')) IN ('1', 'TRUE') THEN CONVERT(BIT, 1)
                    WHEN UPPER(JSON_VALUE(j.value, '$.usable_for_alerting')) IN ('0', 'FALSE') THEN CONVERT(BIT, 0)
                    ELSE NULL
                END AS usable_for_alerting,

                TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(j.value, '$.quality_score')) AS quality_score,
                UPPER(CONVERT(NVARCHAR(20), JSON_VALUE(j.value, '$.reference_type'))) AS reference_type,
                TRY_CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.reference_value')) AS reference_value,
                TRY_CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.consistency_error')) AS consistency_error,
                CONVERT(NVARCHAR(200), JSON_VALUE(j.value, '$.meta_note')) AS meta_note
        ) r
        LEFT JOIN dbo.SensorType st
          ON st.sensor_name = r.sensor_name;

        SELECT @input_row_count = COUNT(*)
        FROM @mapped;

        IF EXISTS (SELECT 1 FROM @mapped WHERE sensor_name IS NULL OR sensor_name = N'')
            THROW 54021, 'health_json contains blank or missing sensor_name.', 1;

        IF EXISTS (SELECT 1 FROM @mapped WHERE sensor_type_id IS NULL)
            THROW 54022, 'Unknown sensor_name found in health_json.', 1;

        IF EXISTS (SELECT 1 FROM @mapped WHERE measured_value IS NULL)
            THROW 54023, 'health_json contains invalid or missing value.', 1;

        DECLARE @log_map TABLE (
            array_index INT NOT NULL PRIMARY KEY,
            log_id      BIGINT NOT NULL
        );

        MERGE dbo.SensorLog AS tgt
        USING (
            SELECT
                m.array_index,
                m.sensor_type_id,
                m.measured_value
            FROM @mapped m
        ) AS src
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (
                device_id,
                session_id,
                sensor_type_id,
                measured_value,
                recorded_at
            )
            VALUES (
                @device_id,
                NULL,
                src.sensor_type_id,
                src.measured_value,
                @now
            )
        OUTPUT
            src.array_index,
            inserted.log_id
        INTO @log_map(array_index, log_id);

        SELECT @inserted_log_count = COUNT(*)
        FROM @log_map;

        IF @inserted_log_count <> @input_row_count
            THROW 54024, 'Health SensorLog insert count mismatch.', 1;

        INSERT INTO dbo.SensorLogMeta (
            log_id,
            filtered_value,
            is_outlier,
            interference_flag,
            usable_for_ml,
            usable_for_alerting,
            quality_score,
            reference_type,
            reference_value,
            consistency_error,
            meta_note
        )
        SELECT
            lm.log_id,
            m.filtered_value,
            ISNULL(m.is_outlier, 0),
            ISNULL(m.interference_flag, 0),
            ISNULL(m.usable_for_ml, 1),
            ISNULL(m.usable_for_alerting, 1),
            m.quality_score,
            m.reference_type,
            m.reference_value,
            m.consistency_error,
            m.meta_note
        FROM @mapped m
        JOIN @log_map lm
          ON lm.array_index = m.array_index;

        SET @inserted_meta_count = @@ROWCOUNT;

        SELECT @sensor_summary_json =
        (
            SELECT
                m.sensor_name,
                m.sensor_type_id,
                m.measured_value,
                m.filtered_value,
                ISNULL(m.is_outlier, 0)          AS is_outlier,
                ISNULL(m.interference_flag, 0)   AS interference_flag,
                ISNULL(m.usable_for_ml, 1)       AS usable_for_ml,
                ISNULL(m.usable_for_alerting, 1) AS usable_for_alerting,
                m.quality_score,
                m.reference_type,
                m.reference_value,
                m.consistency_error,
                m.meta_note
            FROM @mapped m
            ORDER BY m.array_index
            FOR JSON PATH
        );

        SELECT @diff_json =
        (
            SELECT
                @device_id             AS device_id,
                @now                   AS recorded_at_utc,
                @input_row_count       AS health_input_rows,
                @inserted_log_count    AS sensorlog_rows_inserted,
                @inserted_meta_count   AS sensorlogmeta_rows_inserted,
                JSON_QUERY(@sensor_summary_json) AS sensors
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'INGEST_SENSOR_HEALTH_BATCH',
            @object_type     = N'Device',
            @object_id       = @device_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Device_Create
    @location        NVARCHAR(100) = NULL,
    @model           NVARCHAR(50)  = NULL,
    @firmware_ver    NVARCHAR(20)  = NULL,
    @status          NVARCHAR(20)  = N'ACTIVE',

    -- audit context
    @actor_user_id   INT,
    @actor_role_name NVARCHAR(30),

    -- optional explanation
    @reason          NVARCHAR(200) = NULL,

    -- outputs
    @new_device_id   INT OUTPUT,
    @audit_id        INT OUTPUT,
    @chain_hash      CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @s NVARCHAR(20) = UPPER(LTRIM(RTRIM(@status)));
    DECLARE @loc NVARCHAR(100) = NULLIF(LTRIM(RTRIM(@location)), N'');
    DECLARE @m   NVARCHAR(50)  = NULLIF(LTRIM(RTRIM(@model)), N'');
    DECLARE @fw  NVARCHAR(20)  = NULLIF(LTRIM(RTRIM(@firmware_ver)), N'');

    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY

        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        -- Insert (installed_at uses default)
        DECLARE @ins TABLE (device_id INT);

        INSERT INTO dbo.Device (location, model, firmware_ver, status)
        OUTPUT inserted.device_id INTO @ins(device_id)
        VALUES (@loc, @m, @fw, @s);

        SELECT @new_device_id = device_id FROM @ins;

        -- Audit diff (do not assume installed_at value; DB sets it)
        SELECT @diff_json =
        (
            SELECT
                @new_device_id AS device_id,
                @loc           AS location,
                @m             AS model,
                @fw            AS firmware_ver,
                @s             AS status,
                @reason        AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'DEVICE_CREATED',
            @object_type     = N'Device',
            @object_id       = @new_device_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;


        IF @started_tran = 1
            COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Device_UpdateStatus_User
    @device_id       INT,
    @new_status      NVARCHAR(20),       -- only ACTIVE / MAINTENANCE
    @actor_user_id   INT,
    @actor_role_name NVARCHAR(30),
    @reason          NVARCHAR(200) = NULL,
    @audit_id    INT OUTPUT,
    @chain_hash  CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @status NVARCHAR(20) = UPPER(LTRIM(RTRIM(@new_status)));
    DECLARE @old_status NVARCHAR(20);

    DECLARE  @diff_json NVARCHAR(MAX);

    BEGIN TRY
        
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        /* Lock device row + read old status */
        SELECT @old_status = d.status
        FROM dbo.Device d WITH (UPDLOCK, ROWLOCK)
        WHERE d.device_id = @device_id;

        IF @old_status IS NULL
            THROW 55102, 'Device not found.', 1;

        /* No-op if unchanged */
        IF @old_status = @status
        BEGIN
            IF @started_tran = 1
            BEGIN
                COMMIT;
            END
            RETURN;
        END

        /* Update */
        UPDATE dbo.Device
        SET status = @status
        WHERE device_id = @device_id;

        /* Audit */
        SELECT @diff_json =
        (
            SELECT
                @device_id  AS device_id,
                @old_status AS old_status,
                @status     AS new_status,
                @reason     AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'DEVICE_STATUS_CHANGED_USER',
            @object_type     = N'Device',
            @object_id       = @device_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
        BEGIN
            COMMIT;
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
        BEGIN
            ROLLBACK;
        END
        ;THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Device_UpdateStatus_System
    @device_id       INT,
    @new_status      NVARCHAR(20),     -- only OFFLINE / ERROR
    @reason          NVARCHAR(200) = NULL,

    -- enforce SYSTEM actor
    @actor_user_id   INT = 2,
    @actor_role_name NVARCHAR(30) = N'SYSTEM',
    @audit_id    INT OUTPUT,
    @chain_hash  CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @status NVARCHAR(20) = UPPER(LTRIM(RTRIM(@new_status)));
    DECLARE @old_status NVARCHAR(20);

    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY
       
        /* Transaction ownership */
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        /* Lock device row + read old status */
        SELECT @old_status = d.status
        FROM dbo.Device d WITH (UPDLOCK, ROWLOCK)
        WHERE d.device_id = @device_id;

        IF @old_status IS NULL
            THROW 55203, 'Device not found.', 1;

        /* No-op if unchanged */
        IF @old_status = @status
        BEGIN
            IF @started_tran = 1
            BEGIN
                COMMIT;
            END
            RETURN;
        END

        /* Update */
        UPDATE dbo.Device
        SET status = @status
        WHERE device_id = @device_id;

        /* Audit */
        SELECT @diff_json =
        (
            SELECT
                @device_id  AS device_id,
                @old_status AS old_status,
                @status     AS new_status,
                @reason     AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = 2,
            @actor_role_name = N'SYSTEM',
            @action          = N'DEVICE_STATUS_CHANGED_SYSTEM',
            @object_type     = N'Device',
            @object_id       = @device_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
        BEGIN
            COMMIT;
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
        BEGIN
            ROLLBACK;
        END
        ;THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.PourProfile_Create
    @name           NVARCHAR(50),
    @target_ml      INT,
    @tolerance_ml   INT,
    @max_duration_s INT,
    @max_flow_rate  DECIMAL(6,2),

    @actor_user_id   INT,
    @actor_role_name NVARCHAR(30),
    @reason          NVARCHAR(200) = NULL,

    @new_profile_id  INT OUTPUT,
    @audit_id        INT OUTPUT,
    @chain_hash      CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @n NVARCHAR(50) = NULLIF(UPPER(LTRIM(RTRIM(@name))), N'');
    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY
        IF @n IS NULL
            THROW 57101, 'Profile name is required.', 1;

        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        DECLARE @ins TABLE(profile_id INT);

        INSERT INTO dbo.PourProfile (name, target_ml, tolerance_ml, max_duration_s, max_flow_rate)
        OUTPUT inserted.profile_id INTO @ins(profile_id)
        VALUES (@n, @target_ml, @tolerance_ml, @max_duration_s, @max_flow_rate);

        SELECT @new_profile_id = profile_id FROM @ins;

        SELECT @diff_json =
        (
            SELECT
                @new_profile_id AS profile_id,
                @n              AS name,
                @target_ml      AS target_ml,
                @tolerance_ml   AS tolerance_ml,
                @max_duration_s AS max_duration_s,
                @max_flow_rate  AS max_flow_rate,
                @reason         AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'POURPROFILE_CREATED',
            @object_type     = N'PourProfile',
            @object_id       = @new_profile_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.Calibration_Create
    @device_id       INT,
    @sensor_type_id  INT,
    @factor          DECIMAL(10,6),
    @offset          DECIMAL(10,6),

    -- actor / provenance
    @created_by      INT,                 -- who performs calibration (FK Users)
    @actor_role_name NVARCHAR(30),        -- snapshot for audit
    @reason          NVARCHAR(200) = NULL,

    -- outputs / receipt
    @new_calib_id    INT OUTPUT,
    @audit_id        INT OUTPUT,
    @chain_hash      CHAR(64) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started_tran BIT = 0;

    DECLARE @now DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @old_calib_id INT = NULL;
    DECLARE @old_valid_from DATETIME2(7) = NULL;

    DECLARE @diff_json NVARCHAR(MAX);

    BEGIN TRY

        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        /* 1) Close any active calibration for this device+sensor (valid_to IS NULL)
              Use locks to prevent two writers creating two "active" rows concurrently.
        */
        SELECT TOP (1)
            @old_calib_id = c.calib_id,
            @old_valid_from = c.valid_from
        FROM dbo.Calibration c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.device_id = @device_id
          AND c.sensor_type_id = @sensor_type_id
          AND c.valid_to IS NULL
        ORDER BY c.valid_from DESC;

        IF @old_calib_id IS NOT NULL
        BEGIN
            UPDATE dbo.Calibration
            SET valid_to = @now
            WHERE calib_id = @old_calib_id;
        END

        /* 2) Insert new calibration as the active one (valid_to NULL)
              Make valid_from explicit = @now so the version key is deterministic.
        */
        DECLARE @ins TABLE (calib_id INT);

        INSERT INTO dbo.Calibration
            (device_id, sensor_type_id, factor, offset, created_by, valid_from, valid_to)
        OUTPUT inserted.calib_id INTO @ins(calib_id)
        VALUES
            (@device_id, @sensor_type_id, @factor, @offset, @created_by, @now, NULL);

        SELECT @new_calib_id = calib_id FROM @ins;

        /* 3) Audit (one semantic event: close old + create new) */
        SELECT @diff_json =
        (
            SELECT
                @device_id      AS device_id,
                @sensor_type_id AS sensor_type_id,
                @old_calib_id   AS closed_calib_id,
                @old_valid_from AS closed_valid_from,
                @now            AS closed_valid_to_and_new_valid_from,
                @new_calib_id   AS new_calib_id,
                @factor         AS new_factor,
                @offset         AS new_offset,
                @created_by     AS created_by_user_id,
                @reason         AS reason
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @created_by,
            @actor_role_name = @actor_role_name,
            @action          = N'CALIBRATION_UPDATED_NEW_VERSION',
            @object_type     = N'Calibration',
            @object_id       = @new_calib_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1
            COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 AND @started_tran = 1
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.PourSession_Ingest_Batch
    @device_id            INT,
    @upload_id            NVARCHAR(30),
    @user_id              INT = 1,
    @profile_id           INT,

    @target_ml            INT,
    @actual_ml            DECIMAL(8,3),
    @duration_s           DECIMAL(8,3),
    @cup_present          BIT,

    @result_code          NVARCHAR(20),
    @stop_reason          NVARCHAR(20),

    @started_at           DATETIME2(7) = NULL,
    @ended_at             DATETIME2(7) = NULL,

    @start_reason         NVARCHAR(20) = N'REMOTE_APP',

    @telemetry_json       NVARCHAR(MAX),   -- JSON array: [{sensor_type_id, value, t_offset_ms, ...}, ...]
    @loadcell_offset_raw  BIGINT = NULL,   -- runtime tare/raw offset from ESP32 for LOADCELL only

    @ml_eligible          BIT = 1,
    @ml_exclusion_reason  NVARCHAR(60) = NULL,

    /* ===== ML outputs from app (Weka) ===== */
    @ml_risk_score        FLOAT = NULL,
    @ml_reason_json       NVARCHAR(MAX) = NULL,

    @actor_user_id        INT = 2,
    @actor_role_name      NVARCHAR(30) = N'SYSTEM',

    @new_session_id       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @audit_id              INT,
        @chain_hash            CHAR(64),
        @diff_json             NVARCHAR(MAX),
        @time_source           NVARCHAR(16) = N'DEVICE_UTC',
        @telemetry_in_count    INT = 0,
        @telemetry_ins_count   INT = 0,
        @telemetry_meta_count  INT = 0,
        @calib_sensor_count    INT = 0,
        @calib_insert_count    INT = 0,
        @dur_ms                BIGINT,
        @alert_id              INT,
        @resolved_calib_json   NVARCHAR(MAX) = N'[]',
        @loadcell_sensor_type_id INT = NULL;

    BEGIN TRY
        /* =========================
           Normalize textual inputs
           ========================= */
        SET @upload_id       = UPPER(LTRIM(RTRIM(@upload_id)));
        SET @start_reason    = UPPER(LTRIM(RTRIM(@start_reason)));
        SET @stop_reason     = UPPER(LTRIM(RTRIM(@stop_reason)));
        SET @result_code     = UPPER(LTRIM(RTRIM(@result_code)));
        SET @actor_role_name = UPPER(LTRIM(RTRIM(@actor_role_name)));

        IF @upload_id IS NULL OR @upload_id = N''
            THROW 53001, 'upload_id is required for idempotent ingestion.', 1;

        BEGIN TRAN;

        /* =========================
           Timestamp policy
           ========================= */
        SET @dur_ms = CONVERT(BIGINT, ROUND(CONVERT(FLOAT, @duration_s) * 1000.0, 0));

        IF @started_at IS NULL OR @ended_at IS NULL
        BEGIN
            SET @time_source = N'SERVER_INGEST';
            SET @ended_at   = SYSUTCDATETIME();
            SET @started_at = DATEADD(MILLISECOND, -@dur_ms, @ended_at);
        END
        ELSE
        BEGIN
            SET @time_source = N'DEVICE_UTC';
        END

        /* =========================
           Resolve LOADCELL sensor_type_id
           ========================= */
        SELECT @loadcell_sensor_type_id = st.sensor_type_id
        FROM dbo.SensorType st
        WHERE UPPER(LTRIM(RTRIM(st.sensor_name))) = N'LOADCELL';

        /* =========================
           Insert PourSession
           Idempotency point:
           UNIQUE(device_id, upload_id)
           ========================= */
        DECLARE @ins_session TABLE (
            session_id INT NOT NULL PRIMARY KEY
        );

        BEGIN TRY
            INSERT INTO dbo.PourSession (
                device_id,
                upload_id,
                user_id,
                profile_id,
                target_ml,
                actual_ml,
                duration_s,
                cup_present,
                start_reason,
                result_code,
                stop_reason,
                started_at,
                ended_at,
                time_source
            )
            OUTPUT inserted.session_id
            INTO @ins_session(session_id)
            VALUES (
                @device_id,
                @upload_id,
                @user_id,
                @profile_id,
                @target_ml,
                @actual_ml,
                @duration_s,
                @cup_present,
                @start_reason,
                @result_code,
                @stop_reason,
                @started_at,
                @ended_at,
                @time_source
            );

            SELECT @new_session_id = session_id
            FROM @ins_session;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() IN (2601, 2627)
            BEGIN
                IF XACT_STATE() <> 0
                    ROLLBACK;

                SELECT @new_session_id = ps.session_id
                FROM dbo.PourSession ps
                WHERE ps.device_id = @device_id
                  AND ps.upload_id = @upload_id;

                IF @new_session_id IS NULL
                    THROW 53003, 'Duplicate upload detected but existing session not found.', 1;

                RETURN;
            END

            ;THROW;
        END CATCH;

        /* =========================
           Insert PourSessionMeta
           ========================= */
        INSERT INTO dbo.PourSessionMeta (
            session_id,
            ml_eligible,
            ml_exclusion_reason
        )
        VALUES (
            @new_session_id,
            @ml_eligible,
            @ml_exclusion_reason
        );

        /* =========================
           Telemetry parsing
           ========================= */
        IF @telemetry_json IS NOT NULL
        BEGIN
            IF ISJSON(@telemetry_json) <> 1
                THROW 53030, 'telemetry_json is not valid JSON.', 1;

            SELECT @telemetry_in_count = COUNT(*)
            FROM OPENJSON(@telemetry_json);

            IF @telemetry_in_count > 0
            BEGIN
                DECLARE @telemetry TABLE (
                    array_index          INT            NOT NULL PRIMARY KEY,
                    sensor_type_id       INT            NOT NULL,
                    measured_value       DECIMAL(12,4)  NOT NULL,
                    t_offset_ms          INT            NOT NULL,

                    filtered_value       DECIMAL(12,4)  NULL,
                    is_outlier           BIT            NULL,
                    interference_flag    BIT            NULL,
                    usable_for_ml        BIT            NULL,
                    usable_for_alerting  BIT            NULL,
                    quality_score        DECIMAL(5,4)   NULL,
                    reference_type       NVARCHAR(20)   NULL,
                    reference_value      DECIMAL(12,4)  NULL,
                    consistency_error    DECIMAL(12,4)  NULL,
                    meta_note            NVARCHAR(200)  NULL
                );

                INSERT INTO @telemetry (
                    array_index,
                    sensor_type_id,
                    measured_value,
                    t_offset_ms,
                    filtered_value,
                    is_outlier,
                    interference_flag,
                    usable_for_ml,
                    usable_for_alerting,
                    quality_score,
                    reference_type,
                    reference_value,
                    consistency_error,
                    meta_note
                )
                SELECT
                    CONVERT(INT, j.[key]) AS array_index,
                    CONVERT(INT, JSON_VALUE(j.value, '$.sensor_type_id')) AS sensor_type_id,
                    CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.value')) AS measured_value,
                    CONVERT(INT, JSON_VALUE(j.value, '$.t_offset_ms')) AS t_offset_ms,

                    CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.filtered_value')) AS filtered_value,
                    CONVERT(BIT, JSON_VALUE(j.value, '$.is_outlier')) AS is_outlier,
                    CONVERT(BIT, JSON_VALUE(j.value, '$.interference_flag')) AS interference_flag,
                    CONVERT(BIT, JSON_VALUE(j.value, '$.usable_for_ml')) AS usable_for_ml,
                    CONVERT(BIT, JSON_VALUE(j.value, '$.usable_for_alerting')) AS usable_for_alerting,
                    CONVERT(DECIMAL(5,4), JSON_VALUE(j.value, '$.quality_score')) AS quality_score,
                    UPPER(CONVERT(NVARCHAR(20), JSON_VALUE(j.value, '$.reference_type'))) AS reference_type,
                    CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.reference_value')) AS reference_value,
                    CONVERT(DECIMAL(12,4), JSON_VALUE(j.value, '$.consistency_error')) AS consistency_error,
                    CONVERT(NVARCHAR(200), JSON_VALUE(j.value, '$.meta_note')) AS meta_note
                FROM OPENJSON(@telemetry_json) j;

                /* =========================
                   Distinct sensor types in session
                   ========================= */
                DECLARE @session_sensor_types TABLE (
                    sensor_type_id INT NOT NULL PRIMARY KEY
                );

                INSERT INTO @session_sensor_types(sensor_type_id)
                SELECT DISTINCT t.sensor_type_id
                FROM @telemetry t;

                SELECT @calib_sensor_count = COUNT(*)
                FROM @session_sensor_types;

                /* Validate sensor_type_id exists */
                IF EXISTS (
                    SELECT 1
                    FROM @session_sensor_types sst
                    LEFT JOIN dbo.SensorType st
                        ON st.sensor_type_id = sst.sensor_type_id
                    WHERE st.sensor_type_id IS NULL
                )
                    THROW 53032, 'Telemetry contains unknown sensor_type_id.', 1;

                /* =========================
                   Resolve active calibration
                   Must resolve exactly 1 row per used sensor_type_id
                   ========================= */
                DECLARE @calib_candidates TABLE (
                    sensor_type_id   INT NOT NULL,
                    calib_id         INT NOT NULL,
                    candidate_count  INT NOT NULL,
                    rn               INT NOT NULL,
                    PRIMARY KEY(sensor_type_id, calib_id)
                );

                INSERT INTO @calib_candidates (
                    sensor_type_id,
                    calib_id,
                    candidate_count,
                    rn
                )
                SELECT
                    q.sensor_type_id,
                    q.calib_id,
                    q.candidate_count,
                    q.rn
                FROM (
                    SELECT
                        sst.sensor_type_id,
                        c.calib_id,
                        COUNT(*) OVER (PARTITION BY sst.sensor_type_id) AS candidate_count,
                        ROW_NUMBER() OVER (
                            PARTITION BY sst.sensor_type_id
                            ORDER BY c.valid_from DESC, c.calib_id DESC
                        ) AS rn
                    FROM @session_sensor_types sst
                    JOIN dbo.Calibration c
                        ON c.device_id = @device_id
                       AND c.sensor_type_id = sst.sensor_type_id
                       AND c.valid_from <= @started_at
                       AND (c.valid_to IS NULL OR @started_at < c.valid_to)
                ) q;

                IF EXISTS (
                    SELECT 1
                    FROM @session_sensor_types sst
                    LEFT JOIN (
                        SELECT
                            sensor_type_id,
                            MAX(candidate_count) AS candidate_count
                        FROM @calib_candidates
                        GROUP BY sensor_type_id
                    ) cc
                        ON cc.sensor_type_id = sst.sensor_type_id
                    WHERE ISNULL(cc.candidate_count, 0) <> 1
                )
                    THROW 53033, 'Could not resolve exactly one active calibration for every telemetry sensor_type_id.', 1;

                /* =========================
                   Insert session calibration provenance
                   LOADCELL gets runtime_offset_raw
                   Others remain NULL
                   ========================= */
                INSERT INTO dbo.PourSessionCalibration (
                    session_id,
                    sensor_type_id,
                    calib_id,
                    runtime_offset_raw
                )
                SELECT
                    @new_session_id,
                    cc.sensor_type_id,
                    cc.calib_id,
                    CASE
                        WHEN cc.sensor_type_id = @loadcell_sensor_type_id THEN @loadcell_offset_raw
                        ELSE NULL
                    END AS runtime_offset_raw
                FROM @calib_candidates cc
                WHERE cc.rn = 1;

                SET @calib_insert_count = @@ROWCOUNT;

                IF @calib_insert_count <> @calib_sensor_count
                    THROW 53034, 'Calibration insert count mismatch.', 1;

                /* =========================
                   Insert SensorLog
                   NOTE:
                   If your real SensorLog column is [value]
                   instead of [measured_value], rename it here.
                   ========================= */
                DECLARE @log_map TABLE (
                    array_index INT NOT NULL PRIMARY KEY,
                    log_id      BIGINT NOT NULL
                );

                MERGE dbo.SensorLog AS tgt
                USING (
                    SELECT
                        t.array_index,
                        t.sensor_type_id,
                        t.measured_value,
                        t.t_offset_ms
                    FROM @telemetry t
                ) AS src
                ON 1 = 0
                WHEN NOT MATCHED THEN
                    INSERT (
                        device_id,
                        session_id,
                        sensor_type_id,
                        measured_value,
                        recorded_at
                    )
                    VALUES (
                        @device_id,
                        @new_session_id,
                        src.sensor_type_id,
                        src.measured_value,
                        DATEADD(MILLISECOND, src.t_offset_ms, @started_at)
                    )
                OUTPUT
                    src.array_index,
                    inserted.log_id
                INTO @log_map(array_index, log_id);

                SELECT @telemetry_ins_count = COUNT(*)
                FROM @log_map;

                IF @telemetry_ins_count <> @telemetry_in_count
                    THROW 53031, 'Telemetry insert count mismatch.', 1;

                /* =========================
                   Insert SensorLogMeta
                   ========================= */
                INSERT INTO dbo.SensorLogMeta (
                    log_id,
                    filtered_value,
                    is_outlier,
                    interference_flag,
                    usable_for_ml,
                    usable_for_alerting,
                    quality_score,
                    reference_type,
                    reference_value,
                    consistency_error,
                    meta_note
                )
                SELECT
                    m.log_id,
                    t.filtered_value,
                    ISNULL(t.is_outlier, 0),
                    ISNULL(t.interference_flag, 0),
                    ISNULL(t.usable_for_ml, 1),
                    ISNULL(t.usable_for_alerting, 1),
                    t.quality_score,
                    t.reference_type,
                    t.reference_value,
                    t.consistency_error,
                    t.meta_note
                FROM @telemetry t
                JOIN @log_map m
                    ON m.array_index = t.array_index;

                SET @telemetry_meta_count = @@ROWCOUNT;

                /* JSON snapshot for audit provenance */
                SELECT @resolved_calib_json =
                (
                    SELECT
                        psc.sensor_type_id,
                        psc.calib_id,
                        psc.runtime_offset_raw
                    FROM dbo.PourSessionCalibration psc
                    WHERE psc.session_id = @new_session_id
                    ORDER BY psc.sensor_type_id
                    FOR JSON PATH
                );
            END
        END

        /* =========================
           ML reason JSON validation
           ========================= */
        IF @ml_reason_json IS NOT NULL AND ISJSON(@ml_reason_json) <> 1
            THROW 53040, 'ml_reason_json is not valid JSON.', 1;

        /* =========================
           Audit
           ========================= */
        SELECT @diff_json =
        (
            SELECT
                @new_session_id       AS session_id,
                @device_id            AS device_id,
                @upload_id            AS upload_id,
                @user_id              AS user_id,
                @profile_id           AS profile_id,

                @start_reason         AS start_reason,
                @stop_reason          AS stop_reason,
                @result_code          AS result_code,

                @time_source          AS time_source,
                @started_at           AS started_at,
                @ended_at             AS ended_at,

                @target_ml            AS target_ml,
                @actual_ml            AS actual_ml,
                @duration_s           AS duration_s,
                @cup_present          AS cup_present,

                @loadcell_offset_raw  AS loadcell_offset_raw,

                @ml_eligible          AS ml_eligible,
                @ml_exclusion_reason  AS ml_exclusion_reason,

                @ml_risk_score        AS ml_risk_score,
                CASE
                    WHEN @ml_reason_json IS NULL THEN 0
                    ELSE (SELECT COUNT(*) FROM OPENJSON(@ml_reason_json))
                END                   AS ml_reason_count,

                @telemetry_in_count   AS telemetry_input_rows,
                @telemetry_ins_count  AS telemetry_inserted_rows,
                @telemetry_meta_count AS telemetry_meta_rows,

                @calib_sensor_count   AS calibration_sensor_type_count,
                @calib_insert_count   AS calibration_inserted_rows,
                JSON_QUERY(@resolved_calib_json) AS session_calibrations
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'INGEST_POUR_SESSION_BATCH',
            @object_type     = N'PourSession',
            @object_id       = @new_session_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        /* =========================
           Alert hook
           ========================= */
        EXEC dbo.Alert_Create
            @session_id      = @new_session_id,
            @ml_risk_score   = @ml_risk_score,
            @reason_json     = @ml_reason_json,
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @new_alert_id    = @alert_id OUTPUT;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.PourSessionMeta_Update
    @session_id            INT,

    @ml_eligible           BIT = NULL,
    @ml_exclusion_reason   NVARCHAR(60) = NULL,

    @curated_result_code   NVARCHAR(20) = NULL,
    @curated_note          NVARCHAR(512) = NULL,

    @actor_user_id         INT,
    @actor_role_name       NVARCHAR(30),
    @rows_affected         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @started_tran  BIT = 0,
        @audit_id      INT,
        @chain_hash    CHAR(64),
        @diff_json     NVARCHAR(MAX);

    BEGIN TRY
        /* Join ambient transaction if present */
        IF @@TRANCOUNT = 0
        BEGIN
            SET @started_tran = 1;
            BEGIN TRAN;
        END

        /* Apply patch semantics: only update fields that are provided */
        UPDATE pm
        SET
            ml_eligible =
                COALESCE(@ml_eligible, pm.ml_eligible),

            ml_exclusion_reason =
                CASE
                    WHEN @ml_eligible = 1 THEN NULL
                    WHEN @ml_exclusion_reason IS NOT NULL THEN @ml_exclusion_reason
                    ELSE pm.ml_exclusion_reason
                END,

            curated_result_code =
                COALESCE(@curated_result_code, pm.curated_result_code),

            curated_note =
                COALESCE(@curated_note, pm.curated_note),

            curated_by_user_id =
                CASE
                    WHEN @curated_result_code IS NOT NULL OR @curated_note IS NOT NULL
                         OR @ml_eligible IS NOT NULL OR @ml_exclusion_reason IS NOT NULL
                    THEN @actor_user_id
                    ELSE pm.curated_by_user_id
                END,

            curated_at =
                CASE
                    WHEN @curated_result_code IS NOT NULL OR @curated_note IS NOT NULL
                         OR @ml_eligible IS NOT NULL OR @ml_exclusion_reason IS NOT NULL
                    THEN SYSUTCDATETIME()
                    ELSE pm.curated_at
                END
        FROM dbo.PourSessionMeta pm
        WHERE pm.session_id = @session_id;

        SET @rows_affected = @@ROWCOUNT;

        /* Build audit diff (patch request + actor attribution) */
        SELECT @diff_json =
        (
            SELECT
                @session_id          AS session_id,
                @ml_eligible         AS ml_eligible,
                @ml_exclusion_reason AS ml_exclusion_reason,
                @curated_result_code AS curated_result_code,
                @curated_note        AS curated_note
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = @actor_user_id,
            @actor_role_name = @actor_role_name,
            @action          = N'POUR_CURATE_UPDATE',
            @object_type     = N'PourSessionMeta',
            @object_id       = @session_id,
            @diff_json       = @diff_json,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        IF @started_tran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF @started_tran = 1 AND XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.PourSession_ListByUserId
    @session_id INT,
    @actor_user_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM dbo.PourSession_Analysis
    WHERE session_id = @session_id
      AND user_id = @actor_user_id;
END;
GO
CREATE OR ALTER PROCEDURE dbo.PourSession_ListAll
    @date_from DATETIME2(7) = NULL,
    @date_to   DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.*,
        u.username,

        -- PourSessionMeta (all fields)
        pm.ml_eligible,
        pm.ml_exclusion_reason,
        pm.curated_result_code,
        pm.curated_by_user_id,
        pm.curated_at,
        pm.curated_note

    FROM dbo.PourSession_Analysis s
    JOIN dbo.Users u
      ON u.user_id = s.user_id
    LEFT JOIN dbo.PourSessionMeta pm
      ON pm.session_id = s.session_id
    WHERE (@date_from IS NULL OR s.started_at >= @date_from)
      AND (@date_to   IS NULL OR s.started_at <  @date_to)
    ORDER BY s.started_at DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Bootstrap_Init
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @audit_id INT, @chain_hash CHAR(64);
    DECLARE @admin_id INT;
    DECLARE @new_device_id INT;
    DECLARE @new_profile_id INT;
    DECLARE @new_calib_id INT;
    BEGIN TRY
        BEGIN TRAN;

        /* ===== Run-once sentinel guard (no tracking table) ===== */
        IF EXISTS (SELECT 1 FROM dbo.Users WHERE user_id = 2 AND username = N'SYSTEM')
            THROW 50150, 'Bootstrap already applied (SYSTEM user exists).', 1;

        /* =========================================================
           1) Deterministic actors: anonymous=1, SYSTEM=2
           ========================================================= */
        SET IDENTITY_INSERT dbo.Users ON;

        INSERT INTO dbo.Users (user_id, username, password_hash, status)
        VALUES
            (1, N'anonymous',
             CONVERT(NVARCHAR(255), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'ANONYMOUS_DISABLED')), 2),
             N'ACTIVE'),
            (2, N'SYSTEM',
             CONVERT(NVARCHAR(255), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'SYSTEM_DISABLED')), 2),
             N'ACTIVE');

        SET IDENTITY_INSERT dbo.Users OFF;

        DECLARE @actors_diff NVARCHAR(MAX) =
        (
            SELECT 1 AS anonymous_id, 2 AS system_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.Audit_Append
            @actor_user_id   = 2,
            @actor_role_name = N'SYSTEM',
            @action          = N'BOOTSTRAP_CREATE_SYSTEM_ACTORS',
            @object_type     = N'Users',
            @object_id       = 0,
            @diff_json       = @actors_diff,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        /* =========================================================
           2) Seed Roles (non-idempotent insert)
           ========================================================= */
        INSERT INTO dbo.Roles(role_name)
        VALUES (N'ADMIN'), (N'OPERATOR'), (N'TECHNICIAN'), (N'AUDITOR'), (N'GUEST');
        DECLARE @roles_diff NVARCHAR(MAX) =
        (
                SELECT role_name
                FROM (VALUES (N'ADMIN'), (N'OPERATOR'), (N'TECHNICIAN'), (N'AUDITOR'), (N'GUEST')) v(role_name)
                ORDER BY role_name
                FOR JSON PATH
        );
        EXEC dbo.Audit_Append 
            @actor_user_id   = 2,
            @actor_role_name = N'SYSTEM',
            @action          = N'BOOTSTRAP_SEED_ROLES',
            @object_type     = N'Roles',
            @object_id       = 0,
            @diff_json       = @roles_diff,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        /* =========================================================
           3) Create admin user via User_Create (BOOTSTRAP action)
           ========================================================= */
        DECLARE @admin_pw_hash NVARCHAR(255) =
        CONVERT(NVARCHAR(255),
            CONVERT(VARCHAR(64),
                    HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), N'admin123')),
                    2));
        EXEC dbo.User_Create
            @username             = N'admin',
            @password_hash        = @admin_pw_hash,
            @status               = N'ACTIVE',
            @created_by_user_id   = 2,
            @created_by_role_name = N'SYSTEM',
            @new_user_id          = @admin_id OUTPUT,
            @audit_action         = N'BOOTSTRAP_CREATE_ADMIN_USER';

        /* =========================================================
           4) Seed Permissions (non-idempotent insert)
           ========================================================= */
        INSERT INTO dbo.Permissions(module, action)
        VALUES
            (N'USER',N'READ'),(N'USER',N'WRITE'),
            (N'ROLE',N'READ'),(N'ROLE',N'WRITE'),
            (N'DEVICE',N'READ'),(N'DEVICE',N'WRITE'),
            (N'POUR_PROFILE',N'READ'),(N'POUR_PROFILE',N'WRITE'),
            (N'POUR_SESSION',N'READ'),(N'POUR_SESSION',N'WRITE'),
            (N'POUR_HISTORY',N'READ'),
            (N'POUR_CURATE', N'READ'),
            (N'POUR_CURATE', N'WRITE'),
            (N'ALERT',N'READ'),(N'ALERT',N'WRITE'),
            (N'ALERT_EVIDENCE',N'READ'),(N'ALERT_EVIDENCE',N'WRITE'),
            (N'ALERT_REASON',N'READ'),
            (N'MAINTENANCE',N'READ'),(N'MAINTENANCE',N'WRITE'),
            (N'CALIBRATION',N'READ'),(N'CALIBRATION',N'WRITE'),
            (N'AUDIT',N'READ'),
            (N'HASHCHAIN',N'READ'),
            (N'SENSOR_LOG', N'READ');
        DECLARE @perms_diff NVARCHAR(MAX) =
            (
                SELECT module, action
                FROM dbo.Permissions
                ORDER BY module, action
                FOR JSON PATH
            );
        EXEC dbo.Audit_Append
            @actor_user_id   = 2,
            @actor_role_name = N'SYSTEM',
            @action          = N'BOOTSTRAP_SEED_PERMISSIONS',
            @object_type     = N'Permissions',
            @object_id       = 0,
            @diff_json       = @perms_diff,
            @audit_id        = @audit_id OUTPUT,
            @chain_hash      = @chain_hash OUTPUT;

        /* =========================================================
           5) Seed RolePerm via sp_RolePerm_Grant_Batch (BOOTSTRAP actions)
           ========================================================= */

        DECLARE @admin_perms_json NVARCHAR(MAX) =
        (
            SELECT module, action
            FROM dbo.Permissions
            ORDER BY module, action
            FOR JSON PATH
        );

        EXEC dbo.RolePerm_Grant_Batch
            @role_name = N'ADMIN',
            @perm_list_json = @admin_perms_json,
            @granted_by_user_id = 2,
            @granted_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_SEED_ROLEPERM_ADMIN';

        DECLARE @tech_perms_json NVARCHAR(MAX) =
        (
            SELECT module, action
            FROM dbo.Permissions
            WHERE (module = N'DEVICE' AND action IN (N'READ',N'WRITE'))
               OR (module = N'CALIBRATION' AND action IN (N'READ',N'WRITE'))
               OR (module = N'MAINTENANCE' AND action IN (N'READ',N'WRITE'))
               OR (module = N'ALERT' AND action IN (N'READ',N'WRITE'))
               OR (module = N'ALERT_EVIDENCE' AND action IN (N'READ',N'WRITE'))
               OR (module = N'POUR_CURATE' AND action IN (N'READ',N'WRITE'))
               OR (module = N'ALERT_REASON' AND action = N'READ')
               OR (module = N'POUR_PROFILE' AND action = N'READ')
               OR (module = N'POUR_HISTORY' AND action = N'READ')
               OR (module = N'SENSOR_LOG' AND action = N'READ')
            ORDER BY module, action
            FOR JSON PATH
        );

        EXEC dbo.RolePerm_Grant_Batch
            @role_name = N'TECHNICIAN',
            @perm_list_json = @tech_perms_json,
            @granted_by_user_id = 2,
            @granted_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_SEED_ROLEPERM_TECHNICIAN';

        DECLARE @op_perms_json NVARCHAR(MAX) =
        (
            SELECT module, action
            FROM dbo.Permissions
            WHERE (module = N'POUR_SESSION' AND action IN (N'READ',N'WRITE'))
               OR (module = N'POUR_PROFILE' AND action = N'READ')
               OR (module = N'DEVICE' AND action = N'READ')
               OR (module = N'ALERT' AND action = N'READ')
            ORDER BY module, action
            FOR JSON PATH
        );

        EXEC dbo.RolePerm_Grant_Batch
            @role_name = N'OPERATOR',
            @perm_list_json = @op_perms_json,
            @granted_by_user_id = 2,
            @granted_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_SEED_ROLEPERM_OPERATOR';

        DECLARE @auditor_perms_json NVARCHAR(MAX) =
        (
            SELECT module, action
            FROM dbo.Permissions
            WHERE (module = N'POUR_SESSION' AND action = N'READ')
               OR (module = N'POUR_HISTORY' AND action = N'READ')
               OR (module = N'POUR_CURATE' AND action = N'READ')
               OR (module = N'ALERT' AND action = N'READ')
               OR (module = N'ALERT_REASON' AND action = N'READ')
               OR (module = N'ALERT_EVIDENCE' AND action = N'READ')
               OR (module = N'AUDIT' AND action = N'READ')
               OR (module = N'HASHCHAIN' AND action = N'READ')
               OR (module = N'SENSOR_LOG' AND action = N'READ')

            ORDER BY module, action
            FOR JSON PATH
        );

        EXEC dbo.RolePerm_Grant_Batch
            @role_name = N'AUDITOR',
            @perm_list_json = @auditor_perms_json,
            @granted_by_user_id = 2,
            @granted_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_SEED_ROLEPERM_AUDITOR';

        DECLARE @guest_perms_json NVARCHAR(MAX) =
        (
            SELECT module, action
            FROM dbo.Permissions
            WHERE (module = N'DEVICE' AND action = N'READ')
               OR (module = N'POUR_PROFILE' AND action = N'READ')
               OR (module = N'POUR_SESSION' AND action = N'WRITE')
            ORDER BY module, action
            FOR JSON PATH
        );

        EXEC dbo.RolePerm_Grant_Batch
            @role_name = N'GUEST',
            @perm_list_json = @guest_perms_json,
            @granted_by_user_id = 2,
            @granted_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_SEED_ROLEPERM_GUEST';

        /* =========================================================
           6) Assign roles (via proc, audited)
           ========================================================= */
        EXEC dbo.Role_Assign
            @target_user_id = 1,
            @role_name = N'GUEST',
            @assigned_by_user_id = 2,
            @assigned_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_ASSIGN_ROLE_ANONYMOUS_GUEST';

        EXEC dbo.Role_Assign
            @target_user_id = @admin_id,
            @role_name = N'ADMIN',
            @assigned_by_user_id = 2,
            @assigned_by_role_name = N'SYSTEM',
            @audit_action = N'BOOTSTRAP_ASSIGN_ROLE_ADMIN_ADMIN';
        /* =========================================================
   Seed SensorType (insert missing)
   ========================================================= */

        

        INSERT INTO dbo.SensorType(sensor_name, unit) VALUES
        (N'ULTRASONIC', N'CM'),    -- HC-SR04 distance (cup presence / distance)
        (N'FLOW',       N'ML_S'),  -- flow rate (or pulses -> converted to ml/s in firmware/app)
        (N'LOADCELL',   N'G');     -- grams (1 ml water ≈ 1 g)
        -- Build diff_json (deterministic ordering)
        DECLARE @sensortypes_diff NVARCHAR(MAX) =
        (
        SELECT sensor_name, unit
        FROM dbo.SensorType
        ORDER BY sensor_name
        FOR JSON PATH
        );

        -- Audit append
        EXEC dbo.Audit_Append
        @actor_user_id   = 2,
        @actor_role_name = N'SYSTEM',
        @action          = N'BOOTSTRAP_SEED_SENSOR_TYPES',
        @object_type     = N'SensorType',
        @object_id       = 0,
        @diff_json       = @sensortypes_diff,
        @audit_id        = @audit_id OUTPUT,
        @chain_hash      = @chain_hash OUTPUT;
        
        EXEC dbo.Device_Create
        @location      = N'Main Lobby',
        @model         = N'ESP32-SmartPour',
        @firmware_ver  = N'1.0.0',
        @status        = N'ACTIVE',

        @actor_user_id   = 2,
        @actor_role_name = N'SYSTEM',
        @reason          = N'Bootstrap test device',

        @new_device_id   = @new_device_id OUTPUT,
        @audit_id        = @audit_id OUTPUT,
        @chain_hash      = @chain_hash OUTPUT;
        
        DECLARE
    @sensor_type_id INT;
    
SELECT @sensor_type_id = sensor_type_id
FROM dbo.SensorType
WHERE sensor_name = N'LOADCELL';
        EXEC dbo.Calibration_Create
    @device_id       = @new_device_id,
    @sensor_type_id  = @sensor_type_id,
    @factor          = 1,
    @offset          = 0,
    @created_by      = 2,                 -- SYSTEM
    @actor_role_name = N'SYSTEM',
    @reason          = N'Initial seed calibration',
    @new_calib_id    = @new_calib_id OUTPUT,
    @audit_id        = @audit_id OUTPUT,
    @chain_hash      = @chain_hash OUTPUT;

    SELECT @sensor_type_id = sensor_type_id
FROM dbo.SensorType
WHERE sensor_name = N'ULTRASONIC';
EXEC dbo.Calibration_Create
    @device_id       = @new_device_id,
    @sensor_type_id  = @sensor_type_id,
    @factor          = 1,
    @offset          = 0,
    @created_by      = 2,                 -- SYSTEM
    @actor_role_name = N'SYSTEM',
    @reason          = N'Initial seed calibration',
    @new_calib_id    = @new_calib_id OUTPUT,
    @audit_id        = @audit_id OUTPUT,
    @chain_hash      = @chain_hash OUTPUT;

    SELECT @sensor_type_id = st.sensor_type_id
FROM dbo.SensorType AS st
WHERE st.sensor_name = N'FLOW';

EXEC dbo.Calibration_Create
    @device_id       = @new_device_id,
    @sensor_type_id  = @sensor_type_id,
    @factor          = 100,
    @offset          = 0,
    @created_by      = 2,                 -- SYSTEM
    @actor_role_name = N'SYSTEM',
    @reason          = N'Initial seed calibration',
    @new_calib_id    = @new_calib_id OUTPUT,
    @audit_id        = @audit_id OUTPUT,
    @chain_hash      = @chain_hash OUTPUT;


        EXEC dbo.PourProfile_Create
        @name = N'DEFAULT_360',
        @target_ml = 360,
        @tolerance_ml = 15,
        @max_duration_s = 30,
        @max_flow_rate = 65,
        @actor_user_id = 2,
        @actor_role_name = N'SYSTEM',
        @reason = N'Bootstrap default profile',
        @new_profile_id = @new_profile_id OUTPUT,
        @audit_id = @audit_id OUTPUT,
        @chain_hash = @chain_hash OUTPUT;

        

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER VIEW dbo.PourSession_Analysis
AS
WITH FlowLogs AS (
    SELECT
        sl.session_id,
        sl.device_id,
        sl.log_id,
        sl.recorded_at,
        CAST(
            CASE
                WHEN slm.log_id IS NOT NULL
                 AND slm.usable_for_alerting = 1
                 AND slm.is_outlier = 0
                 AND slm.filtered_value IS NOT NULL
                    THEN slm.filtered_value

                WHEN slm.log_id IS NULL
                    THEN sl.measured_value

                WHEN slm.usable_for_alerting = 1
                 AND slm.is_outlier = 0
                    THEN sl.measured_value

                ELSE NULL
            END
            AS DECIMAL(12,4)
        ) AS flow_value_ml_s
    FROM dbo.SensorLog AS sl
    INNER JOIN dbo.SensorType AS st
        ON st.sensor_type_id = sl.sensor_type_id
    LEFT JOIN dbo.SensorLogMeta AS slm
        ON slm.log_id = sl.log_id
    WHERE st.sensor_name = N'FLOW'
),
FlowAgg AS (
    SELECT
        fl.session_id,
        CAST(COALESCE(MAX(fl.flow_value_ml_s), 0) AS DECIMAL(8,3)) AS derived_peak_flow
    FROM FlowLogs AS fl
    GROUP BY fl.session_id
)
SELECT
    ps.session_id,
    ps.device_id,
    ps.upload_id,
    ps.user_id,
    ps.profile_id,

    ps.target_ml,
    ps.actual_ml,
    ps.duration_s,

    CAST(COALESCE(fa.derived_peak_flow, 0) AS DECIMAL(8,3)) AS peak_flow,

    CAST(
        COALESCE(
            CONVERT(FLOAT, ps.actual_ml) / NULLIF(CONVERT(FLOAT, ps.duration_s), 0.0),
            0.0
        )
        AS DECIMAL(8,3)
    ) AS avg_flow,

    ps.cup_present,
    ps.start_reason,
    ps.result_code,
    ps.stop_reason,
    ps.started_at,
    ps.ended_at,
    ps.time_source
FROM dbo.PourSession AS ps
LEFT JOIN FlowAgg AS fa
    ON fa.session_id = ps.session_id;
GO
CREATE INDEX IX_SensorLog_DeviceTime
ON dbo.SensorLog(device_id, recorded_at);
CREATE INDEX IX_SensorLog_SessionTime
ON dbo.SensorLog(session_id, recorded_at)
WHERE session_id IS NOT NULL;
CREATE INDEX IX_SensorLog_SessionDeviceTime
ON dbo.SensorLog(session_id, device_id, recorded_at);
go
EXEC Bootstrap_Init
go
