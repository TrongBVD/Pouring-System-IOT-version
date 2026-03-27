CREATE DATABASE SmartWaterAuditDB;
GO
USE SmartWaterAuditDB;
GO
CREATE TABLE Users (
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    username NVARCHAR(50) NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    status NVARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME2(7) CONSTRAINT df_users_created_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT ck_users_status_values 
        CHECK (status IN ('ACTIVE', 'DISABLED', 'LOCKED'))
);

CREATE TABLE Roles (
    role_id INT IDENTITY PRIMARY KEY,
    role_name NVARCHAR(30)  NOT NULL,
    CONSTRAINT uq_roles_role_name UNIQUE (role_name)
);

CREATE TABLE UserRole (
    user_id INT NOT NULL,
    role_id INT NOT NULL,

    assigned_at DATETIME2(7) NOT NULL CONSTRAINT df_user_role_assigned_at DEFAULT SYSUTCDATETIME(),
    assigned_by_user_id INT NOT NULL,
    revoked_at DATETIME2(7) NULL,

    CONSTRAINT pk_user_role
        PRIMARY KEY (user_id, role_id, assigned_at),

    CONSTRAINT fk_userrole_user
        FOREIGN KEY (user_id)
        REFERENCES Users(user_id),

    CONSTRAINT fk_userrole_role
        FOREIGN KEY (role_id)
        REFERENCES Roles(role_id),

    CONSTRAINT fk_userrole_assigned_by
        FOREIGN KEY (assigned_by_user_id)
        REFERENCES Users(user_id)
);

CREATE UNIQUE INDEX ux_userrole_active
ON UserRole (user_id, role_id)
WHERE revoked_at IS NULL;


CREATE TABLE Device (
    device_id INT IDENTITY(1,1) PRIMARY KEY,
    location NVARCHAR(100),
    model NVARCHAR(50),
    firmware_ver NVARCHAR(20),
    status NVARCHAR(20) NOT NULL,
    installed_at DATETIME2(7) CONSTRAINT df_device_installed_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT ck_device_status_values 
        CHECK (status IN ('ACTIVE', 'OFFLINE', 'MAINTENANCE', 'ERROR'))
);
CREATE TABLE PourProfile (
    profile_id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(50) NOT NULL,
    target_ml INT NOT NULL,
    tolerance_ml INT NOT NULL,
    max_duration_s INT NOT NULL,
    max_flow_rate DECIMAL(6,2) NOT NULL,

    CONSTRAINT uq_pourprofile_name 
        UNIQUE (name),

    CONSTRAINT ck_pourprofile_target_positive 
        CHECK (target_ml > 0),

    CONSTRAINT ck_pourprofile_tolerance_positive 
        CHECK (tolerance_ml >= 0), 

    CONSTRAINT ck_pourprofile_duration_positive 
        CHECK (max_duration_s > 0),

    CONSTRAINT ck_pourprofile_flow_rate_positive 
        CHECK (max_flow_rate > 0)
);
CREATE TABLE SensorType (
    sensor_type_id INT IDENTITY(1,1) PRIMARY KEY,
    sensor_name NVARCHAR(30) NOT NULL, 
    unit NVARCHAR(10) NOT NULL, 

    CONSTRAINT uq_sensortype_name UNIQUE (sensor_name)
);
CREATE TABLE Calibration (
    calib_id INT IDENTITY PRIMARY KEY,

    device_id INT NOT NULL,
    sensor_type_id INT NOT NULL,

    factor DECIMAL(10,6) NOT NULL,
    offset DECIMAL(10,6) NOT NULL,

    created_by INT NOT NULL,
    valid_from DATETIME2(7) NOT NULL CONSTRAINT df_calib_valid_from DEFAULT SYSUTCDATETIME(),
    valid_to DATETIME2(7) NULL,
    CONSTRAINT ck_calib_timeline 
        CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT fk_calib_device
        FOREIGN KEY (device_id) REFERENCES Device(device_id),

    CONSTRAINT fk_calib_sensor
        FOREIGN KEY (sensor_type_id) REFERENCES SensorType(sensor_type_id),

    CONSTRAINT fk_calib_user
        FOREIGN KEY (created_by) REFERENCES Users(user_id),
    CONSTRAINT uq_calib_version
        UNIQUE (device_id, sensor_type_id, valid_from)
);
CREATE UNIQUE INDEX ux_calib_active
ON Calibration(device_id, sensor_type_id)
WHERE valid_to IS NULL;
CREATE TABLE PourSession (
    session_id INT IDENTITY PRIMARY KEY,
    device_id INT NOT NULL,
    upload_id NVARCHAR(30) NOT NULL,
    user_id INT NOT NULL CONSTRAINT df_ps_user DEFAULT 1,
    profile_id INT NOT NULL,

    target_ml INT NOT NULL,
    actual_ml DECIMAL(8,3) NOT NULL,
    duration_s DECIMAL(8,3) NOT NULL,
    cup_present BIT NOT NULL,
    start_reason NVARCHAR(20) NOT NULL
        CONSTRAINT df_ps_start_reason DEFAULT 'REMOTE_APP',
    -- Outcome label (WHAT happened)
    result_code NVARCHAR(20) NOT NULL,

    -- Provenance / control information (HOW it ended)
    stop_reason NVARCHAR(20) NOT NULL
        CONSTRAINT df_ps_stop_reason DEFAULT 'AUTO_PROFILE',

    started_at DATETIME2(7) NOT NULL,
    ended_at   DATETIME2(7) NOT NULL,
    time_source NVARCHAR(16) NOT NULL
        CONSTRAINT df_ps_time_source DEFAULT 'DEVICE_UTC',

    /* =======================
       Foreign keys
       ======================= */
    CONSTRAINT fk_ps_device 
        FOREIGN KEY (device_id) REFERENCES Device(device_id),

    CONSTRAINT fk_ps_user 
        FOREIGN KEY (user_id) REFERENCES Users(user_id),

    CONSTRAINT fk_ps_profile 
        FOREIGN KEY (profile_id) REFERENCES PourProfile(profile_id),

    CONSTRAINT uq_ps_session_device UNIQUE (session_id, device_id),
    CONSTRAINT uq_ps_device_upload UNIQUE(device_id, upload_id),

    /* =======================
       Physical sanity checks
       ======================= */
    CONSTRAINT ck_ps_actual_positive 
        CHECK (actual_ml >= 0),

    CONSTRAINT ck_ps_duration_positive 
        CHECK (duration_s > 0),

    CONSTRAINT ck_ps_time_order 
        CHECK (ended_at > started_at),
    CONSTRAINT ck_ps_start_reason
        CHECK (start_reason IN ('REMOTE_APP','MANUAL_BUTTON')),
    /* =======================
       Outcome classification
       ======================= */
    CONSTRAINT ck_ps_result_code 
        CHECK (result_code IN (
            'SUCCESS',
            'UNDER_POUR',
            'OVER_POUR',
            'NO_CUP',
            'TIMEOUT',
            'ERROR'
        )),

    /* =======================
       Stop provenance
       ======================= */
    CONSTRAINT ck_ps_stop_reason
        CHECK (stop_reason IN (
            'AUTO_PROFILE',     -- normal autonomous completion
            'MANUAL_BUTTON',    -- user manually stopped
            'TIMEOUT_FAILSAFE', -- safety timeout
            'ERROR_ABORT'       -- error-triggered stop
            
        )),
    CONSTRAINT ck_ps_time_source
        CHECK (time_source IN ('DEVICE_UTC','SERVER_INGEST'))
);
CREATE TABLE PourSessionMeta (
    session_id INT PRIMARY KEY,
    -- ML governance (minimal + sufficient)
    ml_eligible BIT NOT NULL CONSTRAINT df_psm_ml_eligible DEFAULT 1,
    ml_exclusion_reason NVARCHAR(60) NULL,

    -- Optional: if later a Technician/Admin adjudicates outcome label
    curated_result_code NVARCHAR(20) NULL,
    curated_by_user_id INT NULL,
    curated_at DATETIME2(7) NULL,
    curated_note NVARCHAR(250) NULL,
    CONSTRAINT fk_psm_session
        FOREIGN KEY (session_id) REFERENCES PourSession(session_id),

    CONSTRAINT fk_psm_curator
        FOREIGN KEY (curated_by_user_id) REFERENCES Users(user_id),

    CONSTRAINT ck_psm_curated_result_code
        CHECK (
            curated_result_code IS NULL OR curated_result_code IN (
                'SUCCESS',
                'UNDER_POUR',
                'OVER_POUR',
                'NO_CUP',
                'TIMEOUT',
                'ERROR'
            )
        )       
);
CREATE TABLE dbo.PourSessionCalibration (
    session_id     INT NOT NULL,
    sensor_type_id INT NOT NULL,
    calib_id       INT NOT NULL,
    runtime_offset_raw BIGINT NULL,
    CONSTRAINT PK_PourSessionCalibration PRIMARY KEY(session_id, sensor_type_id),
    CONSTRAINT FK_PSC_Session FOREIGN KEY(session_id) REFERENCES dbo.PourSession(session_id),
    CONSTRAINT FK_PSC_SensorType FOREIGN KEY(sensor_type_id) REFERENCES dbo.SensorType(sensor_type_id),
    CONSTRAINT FK_PSC_Calibration FOREIGN KEY(calib_id) REFERENCES dbo.Calibration(calib_id)
);
CREATE TABLE Alert (
    alert_id INT IDENTITY(1,1) PRIMARY KEY,

    device_id INT NOT NULL,
    session_id INT NULL,

    alert_type NVARCHAR(30) NOT NULL,
    risk_score DECIMAL(5,4) NOT NULL,

    status NVARCHAR(20) NOT NULL CONSTRAINT df_alert_status DEFAULT 'OPEN',

    created_at DATETIME2(7) NOT NULL CONSTRAINT df_alert_created_at DEFAULT SYSUTCDATETIME(),
    resolved_at DATETIME2(7) NULL,

    assigned_to INT NULL,

    CONSTRAINT fk_alert_device
        FOREIGN KEY (device_id)
        REFERENCES Device(device_id),

    CONSTRAINT fk_alert_session
        FOREIGN KEY (session_id)
        REFERENCES PourSession(session_id),

    CONSTRAINT fk_alert_assigned_to
        FOREIGN KEY (assigned_to)
        REFERENCES Users(user_id),

    CONSTRAINT ck_alert_type
        CHECK (alert_type IN (
            'OVERPOUR',
            'FLOW_SPIKE',
            'CUP_MISSING',
            'ML_ANOMALY',
            'CALIBRATION_EXPIRED'
        )),

    CONSTRAINT ck_alert_risk_score
        CHECK (risk_score >= 0 AND risk_score <= 1),

    CONSTRAINT ck_alert_status
        CHECK (status IN (
            'OPEN',
            'ACKNOWLEDGED',
            'IN_PROGRESS',
            'RESOLVED',
            'DISMISSED'
        )),

    CONSTRAINT ck_alert_resolved_consistency
        CHECK (
            (status IN ('RESOLVED', 'DISMISSED') AND resolved_at IS NOT NULL)
            OR
            (status NOT IN ('RESOLVED', 'DISMISSED') AND resolved_at IS NULL)
        )
);
CREATE TABLE SensorLog (
    log_id BIGINT IDENTITY PRIMARY KEY,

    device_id INT NOT NULL,
    session_id INT NULL,
    sensor_type_id INT NOT NULL,

    measured_value DECIMAL(12,4) NOT NULL,
    recorded_at DATETIME2(7) NOT NULL,
    ingested_at DATETIME2(7) NOT NULL
    CONSTRAINT df_sensorlog_ingested_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_sensorlog_device
        FOREIGN KEY (device_id)
        REFERENCES Device(device_id),
    CONSTRAINT fk_sensorlog_sensortype
        FOREIGN KEY (sensor_type_id)
        REFERENCES SensorType(sensor_type_id),
    CONSTRAINT fk_sensorlog_session_device
        FOREIGN KEY (session_id, device_id)
        REFERENCES PourSession(session_id, device_id)
);
CREATE TABLE SensorLogMeta (
    log_id BIGINT NOT NULL,

    -- Derived / processed value
    filtered_value DECIMAL(12,4) NULL,

    -- Observation-quality flags
    is_outlier BIT NOT NULL
        CONSTRAINT df_slm_is_outlier DEFAULT 0,

    interference_flag BIT NOT NULL
        CONSTRAINT df_slm_interference_flag DEFAULT 0,

    -- Downstream usability
    usable_for_ml BIT NOT NULL
        CONSTRAINT df_slm_usable_for_ml DEFAULT 1,

    usable_for_alerting BIT NOT NULL
        CONSTRAINT df_slm_usable_for_alerting DEFAULT 1,

    -- Optional quality score
    quality_score DECIMAL(5,4) NULL,

    -- Optional reference / cross-sensor comparison
    reference_type NVARCHAR(20) NULL,
    reference_value DECIMAL(12,4) NULL,
    consistency_error DECIMAL(12,4) NULL,

    -- Optional compact note
    meta_note NVARCHAR(200) NULL,

    generated_at DATETIME2(7) NOT NULL
        CONSTRAINT df_slm_generated_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT pk_sensorlogmeta
        PRIMARY KEY (log_id),

    CONSTRAINT fk_slm_log
        FOREIGN KEY (log_id)
        REFERENCES SensorLog(log_id),

    CONSTRAINT ck_slm_quality_score
        CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),

    CONSTRAINT ck_slm_consistency_error
        CHECK (consistency_error IS NULL OR consistency_error >= 0),

    CONSTRAINT ck_slm_reference_type
        CHECK (
            reference_type IS NULL OR reference_type IN (
                'LOADCELL_DELTA',
                'NONE'
            )
        ),

    CONSTRAINT ck_slm_reference_usage
        CHECK (
            (reference_type IS NULL AND reference_value IS NULL)
            OR
            (reference_type = 'NONE' AND reference_value IS NULL)
            OR
            (reference_type IS NOT NULL AND reference_type <> 'NONE' AND reference_value IS NOT NULL)
        )
);
CREATE TABLE AlertEvidence (
    evidence_id INT IDENTITY PRIMARY KEY,
    alert_id INT NOT NULL,
    evidence_type NVARCHAR(20) NOT NULL,   
    sensor_log_id BIGINT NULL,
    summary_text NVARCHAR(512) NOT NULL,

    CONSTRAINT fk_alertevidence_alert
        FOREIGN KEY (alert_id)
        REFERENCES Alert(alert_id),

    CONSTRAINT fk_alertevidence_sensorlog
        FOREIGN KEY (sensor_log_id)
        REFERENCES SensorLog(log_id),

    CONSTRAINT ck_alertevidence_type
        CHECK (evidence_type IN ('SENSOR', 'RULE', 'AUDIT', 'SYSTEM')),

    CONSTRAINT ck_alertevidence_sensor_usage
        CHECK (
            (evidence_type = 'SENSOR' AND sensor_log_id IS NOT NULL)
            OR
            (evidence_type <> 'SENSOR' AND sensor_log_id IS NULL)
        )
);

CREATE TABLE AlertReason (
    reason_id INT IDENTITY(1,1) PRIMARY KEY,
    alert_id INT NOT NULL,

    feature_name NVARCHAR(50) NOT NULL,
    contribution DECIMAL(6,4) NOT NULL,
    importance_rank INT NOT NULL,

    created_at DATETIME2(7) NOT NULL CONSTRAINT df_alertreason_created_at DEFAULT SYSUTCDATETIME(),
    
    CONSTRAINT fk_alertreason_alert
        FOREIGN KEY (alert_id)
        REFERENCES Alert(alert_id),

    CONSTRAINT ck_alertreason_contribution_range
        CHECK (contribution >= 0 AND contribution <= 1),

    CONSTRAINT ck_alertreason_rank_positive
        CHECK (importance_rank > 0),
        CONSTRAINT uq_alertreason_unique_feature
    UNIQUE (alert_id, feature_name)
);

CREATE TABLE AuditLog (
    audit_id INT IDENTITY(1,1) PRIMARY KEY, 

    actor_user_id INT NOT NULL,
    actor_role_name NVARCHAR(30) NOT NULL, 
    
    action NVARCHAR(50) NOT NULL, 
    object_type NVARCHAR(50) NOT NULL, 
    object_id INT NOT NULL,            
    
    diff_json NVARCHAR(MAX),        
    
    timestamp DATETIME2(7) NOT NULL 
        CONSTRAINT df_auditlog_timestamp DEFAULT SYSUTCDATETIME(),

    CONSTRAINT fk_auditlog_user 
        FOREIGN KEY (actor_user_id) REFERENCES Users(user_id)
);

CREATE TABLE HashChain (
    anchor_id INT IDENTITY(1,1) PRIMARY KEY,
    audit_id INT NOT NULL, 
    prev_hash CHAR(64) NULL, 
    row_hash CHAR(64) NOT NULL,
    chain_hash CHAR(64) NOT NULL,

    created_at DATETIME2(7) NOT NULL 
        CONSTRAINT df_hashchain_created_at DEFAULT SYSUTCDATETIME(),

    CONSTRAINT uq_hashchain_audit UNIQUE (audit_id),
    CONSTRAINT fk_hashchain_audit 
        FOREIGN KEY (audit_id) REFERENCES AuditLog(audit_id)
);
CREATE TABLE Permissions (
    permission_id INT IDENTITY(1,1) PRIMARY KEY,
    
    module NVARCHAR(50) NOT NULL,
    
    action NVARCHAR(10) NOT NULL,

    CONSTRAINT ck_permissions_action 
        CHECK (action IN ('READ', 'WRITE')),
    CONSTRAINT uq_permissions_module_action 
        UNIQUE (module, action)
);
CREATE TABLE RolePerm (
    role_id INT NOT NULL,
    permission_id INT NOT NULL,
    granted_at DATETIME2(7) NOT NULL CONSTRAINT df_rp_granted_at DEFAULT SYSUTCDATETIME(),
    granted_by_user_id INT NOT NULL,


    CONSTRAINT pk_role_perm 
        PRIMARY KEY (role_id, permission_id),

    CONSTRAINT fk_rp_role 
        FOREIGN KEY (role_id) REFERENCES Roles(role_id),
    CONSTRAINT fk_rp_permission 
        FOREIGN KEY (permission_id) REFERENCES Permissions(permission_id),
    CONSTRAINT fk_rp_granted_by 
        FOREIGN KEY (granted_by_user_id) REFERENCES Users(user_id)
);

CREATE TABLE MaintenanceTicket (
    ticket_id INT IDENTITY(1,1) PRIMARY KEY,
    device_id INT NOT NULL,
    
    ticket_type NVARCHAR(20) NOT NULL, 
    
    note NVARCHAR(255),
    
    status NVARCHAR(20) NOT NULL CONSTRAINT df_mt_status DEFAULT 'OPEN',
    
    opened_at DATETIME2(7) NOT NULL CONSTRAINT df_mt_opened_at DEFAULT SYSUTCDATETIME(),
    closed_at DATETIME2(7) NULL,
  

    CONSTRAINT fk_maintenanceticket_device 
        FOREIGN KEY (device_id) REFERENCES Device(device_id),

    CONSTRAINT ck_maintenanceticket_type 
        CHECK (ticket_type IN ('CLEAN', 'FILTER', 'VALVE')),

    CONSTRAINT ck_maintenanceticket_status 
        CHECK (status IN ('OPEN', 'IN_PROGRESS', 'CLOSED')),

    CONSTRAINT ck_maintenanceticket_dates 
        CHECK (closed_at IS NULL OR closed_at >= opened_at)
);
CREATE TABLE MaintenanceLog (
    maintenance_log_id INT IDENTITY(1,1) PRIMARY KEY,

    ticket_id INT NOT NULL,
    technician_id INT NOT NULL,

    action_code NVARCHAR(30) NOT NULL,
    note NVARCHAR(500) NULL,

    evidence_id INT NULL,

    created_at DATETIME2(7) NOT NULL
        CONSTRAINT DF_MaintenanceLog_created_at DEFAULT SYSUTCDATETIME(),


    CONSTRAINT FK_MaintenanceLog_Ticket
        FOREIGN KEY (ticket_id)
        REFERENCES MaintenanceTicket(ticket_id),

    CONSTRAINT FK_MaintenanceLog_Technician
        FOREIGN KEY (technician_id)
        REFERENCES Users(user_id),

    CONSTRAINT FK_MaintenanceLog_Evidence
        FOREIGN KEY (evidence_id)
        REFERENCES AlertEvidence(evidence_id),

    CONSTRAINT CK_MaintenanceLog_ActionCode
        CHECK (action_code IN (
            'INSPECTED',
            'CLEANED',
            'FILTER_REPLACED',
            'VALVE_ADJUSTED',
            'VALVE_REPLACED',
            'RECALIBRATED',
            'TEST_POUR',
            'NO_ISSUE_FOUND',
            'ESCALATED'
        ))
);





