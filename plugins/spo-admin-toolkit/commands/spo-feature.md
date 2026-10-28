---
description: Thêm hoặc sửa một chức năng của SPCleaner (function + menu + test) theo đúng quy ước
argument-hint: "<mô tả chức năng, ví dụ: liệt kê file > 500MB trong site>"
---

Yêu cầu chức năng: $ARGUMENTS

1. Xác định chức năng thuộc nhóm nào (1 site lớn · 2 file lớn · 3 file trùng · 4 nhiều version · 5 xoá version · 6 file lâu không truy cập · 7 xoá file đó · hoặc mới) và đọc skill tương ứng của plugin spo-admin-toolkit, luôn kèm `spo-project-conventions`.
2. Nếu chức năng có xoá/sửa dữ liệu: bắt buộc đọc và tuân thủ `spo-safe-delete`.
3. Viết/sửa function trong `src/SPCleaner/Public` (và Private nếu cần), cập nhật `FunctionsToExport` trong manifest.
4. Thêm mục vào menu `scripts/Start-SPCleaner.ps1` với validate input.
5. Thêm test Pester theo `spo-pester-testing`; chạy test + ScriptAnalyzer nếu có `pwsh`.
6. Cập nhật README (mục chức năng + ví dụ).
7. Tóm tắt: file đã sửa, cách dùng, giới hạn đã biết.
