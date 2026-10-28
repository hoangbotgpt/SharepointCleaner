# SharepointCleaner

Bộ công cụ PowerShell (module `SPCleaner`, dựa trên PnP.PowerShell) giúp admin quản lý dung lượng SharePoint Online.

## Chức năng
1. Liệt kê site có dung lượng > X GB
2. Liệt kê file dung lượng lớn > X MB trong site đã chọn
3. Liệt kê file trùng tên **và** trùng dung lượng trong site
4. Liệt kê file có số version > N
5. Xoá các version cũ hơn version admin chọn (hoặc chỉ giữ K version mới nhất) cho các file tìm được
6. Liệt kê file có ngày truy cập cuối trước ngày X
7. Xoá các file tìm được ở bước 6

## Quy tắc làm việc
- Luôn dùng các skill của plugin `spo-admin-toolkit` (thư mục `plugins/spo-admin-toolkit`): `spo-project-conventions` cho mọi code, cộng thêm skill riêng của từng chức năng.
- Code chạy trên **PowerShell 7.4+** (`pwsh`). Máy dev hiện chỉ có Windows PowerShell 5.1 → cần cài PowerShell 7 trước khi chạy/test module.
- Mọi thao tác xoá phải tuân thủ `spo-safe-delete` và được review bằng `/spo-review` trước khi coi là xong.
- Không bao giờ chạy lệnh xoá thật lên tenant từ Claude; chỉ chạy test với mock hoặc `-WhatIf`.
- Giao tiếp với admin (menu, thông báo, README) bằng tiếng Việt; code, tên biến, comment bằng tiếng Anh.
- File `.ps1` chứa tiếng Việt phải lưu dạng **UTF-8 có BOM** để Windows PowerShell 5.1 đọc đúng.
