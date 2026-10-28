---
description: Review an toàn cho code xoá dữ liệu SharePoint (Remove-*, menu xoá) bằng agent spo-safety-reviewer
argument-hint: "[đường dẫn file hoặc để trống để review toàn bộ src và scripts]"
---

Dùng agent `spo-safety-reviewer` để review phạm vi: $ARGUMENTS (nếu trống thì review toàn bộ `src/` và `scripts/`).

Yêu cầu agent đối chiếu với checklist trong skill `spo-safe-delete` và trả về danh sách vấn đề theo mức độ (Nghiêm trọng / Cao / Trung bình / Thấp), mỗi vấn đề có file:dòng, kịch bản gây hại cụ thể và cách sửa. Sau khi nhận kết quả, tóm tắt cho tôi và hỏi tôi có muốn sửa ngay không.
