---
description: Scaffold toàn bộ project SharepointCleaner (module SPCleaner, menu, config, tests, README)
argument-hint: "[tên tenant, ví dụ: contoso]"
---

Hãy scaffold project SharepointCleaner trong thư mục hiện tại. Tenant (nếu có): $ARGUMENTS

Làm theo đúng các skill của plugin spo-admin-toolkit:
1. Đọc skill `spo-project-conventions` và tạo đúng cấu trúc thư mục, manifest `SPCleaner.psd1` (FunctionsToExport liệt kê rõ), `SPCleaner.psm1` (dot-source Private rồi Public).
2. Tạo `config/settings.example.json` theo skill `spo-connect`, thêm `config/settings.json`, `reports/`, `logs/`, `certs/` vào `.gitignore`.
3. Implement các function Private (connection cache, inventory, log, retry, format size) và 8 function Public cho 7 chức năng, theo các skill `spo-site-storage`, `spo-file-inventory`, `spo-version-cleanup`, `spo-stale-files`, `spo-safe-delete`.
4. Tạo `scripts/Start-SPCleaner.ps1` – menu tiếng Việt, đánh số 1–7, quy trình xoá nhiều bước như trong `spo-safe-delete`.
5. Tạo test Pester 5 theo `spo-pester-testing` – tối thiểu 1 file test cho mỗi function Public, bắt buộc có test `-WhatIf` cho các hàm Remove-*.
6. Viết `README.md` tiếng Việt: yêu cầu (pwsh 7.4+, PnP.PowerShell), đăng ký app, cấu hình, cách chạy menu, ví dụ pipeline, giới hạn của "ngày truy cập".
7. Nếu có `pwsh` trên máy: chạy PSScriptAnalyzer và Pester, sửa lỗi cho tới khi sạch. Nếu không có, nói rõ là chưa chạy được.
8. Cuối cùng chạy agent `spo-safety-reviewer` trên các function Remove-* và tóm tắt kết quả.
