// File: service/ChainVerificationService.java
package service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.temporal.ChronoField;
import java.util.List;
import utils.SecurityUtils;
import model.AuditChainRow;

public class ChainVerificationService {

    private static final String ZERO_HASH = "0000000000000000000000000000000000000000000000000000000000000000";

    // SQL style 126 (DATETIME2(7)): yyyy-MM-dd'T'HH:mm:ss.1234567
    private static final DateTimeFormatter TS_FMT = new DateTimeFormatterBuilder()
            .appendPattern("yyyy-MM-dd'T'HH:mm:ss")
            .appendFraction(ChronoField.NANO_OF_SECOND, 0, 7, true)
            .toFormatter();

    // HÀM MỚI: QUÉT VÀ GẮN NHÃN CHO TẤT CẢ CÁC DÒNG (Không dùng return fail() nữa)
    public void verifyAndAnnotateChain(List<AuditChainRow> chain) {
        String prevUsed = ZERO_HASH;
        boolean isChainBroken = false;

        for (int i = 0; i < chain.size(); i++) {
            AuditChainRow row = chain.get(i);

            // Nếu mắt xích trước đó đã đứt, toàn bộ các mắt xích sau đều bị lỗi (Hiệu ứng Domino)
            if (isChainBroken) {
                row.setValid(false);
                row.setTamperReason("CHAIN_BROKEN_PRIOR");
                continue; // Chuyển sang dòng tiếp theo luôn
            }

            try {
                // 1. Format lại Timestamp chuẩn 100ns của SQL Server
                LocalDateTime ldt = row.getAuditTimestampUtc();
                int truncatedNanos = (ldt.getNano() / 100) * 100;
                ldt = ldt.withNano(truncatedNanos);
                String ts = TS_FMT.format(ldt);

                // 2. Tạo Canonical Row Text
                String diff = (row.getDiffJson() == null) ? "<NULL>" : row.getDiffJson();
                String rowText = "audit_id=" + row.getAuditId() + "|"
                        + "timestamp_utc=" + ts + "|"
                        + "actor_user_id=" + row.getActorUserId() + "|"
                        + "actor_role=" + (row.getActorRoleName() == null ? "" : row.getActorRoleName()) + "|"
                        + "action=" + row.getAction() + "|"
                        + "object_type=" + row.getObjectType() + "|"
                        + "object_id=" + row.getObjectId() + "|"
                        + "diff=" + diff;

                // 3. Recompute & check Row Hash
                String expectedRowHash = SecurityUtils.sha256HexUtf16LE(rowText);
                if (!expectedRowHash.equals(row.getRowHash())) {
                    row.setValid(false);
                    row.setTamperReason("ROW_HASH_MISMATCH");
                    isChainBroken = true;
                    continue;
                }

                // 4. Kiểm tra liên kết chuỗi (Prev Hash)
                if (i == 0) {
                    if (row.getPrevHash() != null) {
                        row.setValid(false);
                        row.setTamperReason("PREV_HASH_LINK_MISMATCH (Genesis must have NULL prev)");
                        isChainBroken = true;
                        continue;
                    }
                    prevUsed = ZERO_HASH;
                } else {
                    AuditChainRow prevRow = chain.get(i - 1);
                    if (row.getPrevHash() == null || !row.getPrevHash().equals(prevRow.getChainHash())) {
                        row.setValid(false);
                        row.setTamperReason("PREV_HASH_LINK_MISMATCH");
                        isChainBroken = true;
                        continue;
                    }
                    prevUsed = prevRow.getChainHash();
                }

                // 5. Recompute & check Chain Hash
                String chainInput = prevUsed + "|" + expectedRowHash;
                String expectedChainHash = SecurityUtils.sha256HexUtf16LE(chainInput);
                if (!expectedChainHash.equals(row.getChainHash())) {
                    row.setValid(false);
                    row.setTamperReason("CHAIN_HASH_MISMATCH");
                    isChainBroken = true;
                    continue;
                }

                // NẾU VƯỢT QUA MỌI CỬA ẢI -> HỢP LỆ
                row.setValid(true);
                row.setTamperReason("VALID");

            } catch (Exception e) {
                row.setValid(false);
                row.setTamperReason("VERIFICATION_ERROR");
                isChainBroken = true;
            }
        }
    }
}