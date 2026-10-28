---
name: spo-safe-delete
description: Quy tắc an toàn bắt buộc cho mọi thao tác xoá trên SharePoint Online (xoá file, xoá version) - dry-run, ShouldProcess/WhatIf, manifest CSV, xác nhận nhiều bước, Recycle Bin, audit log hành động, xử lý retention/hold và khôi phục. Dùng mỗi khi viết hoặc review bất kỳ function Remove-* nào, menu xoá, hoặc code gọi Remove-PnPFile / Remove-PnPFileVersion / Clear-PnPRecycleBinItem. Triggers - "xoá", "delete", "remove", "WhatIf", "dry run", "recycle bin", "khôi phục", "restore".
---

# An toàn khi xoá – checklist bắt buộc

## 1. Chữ ký function
- `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]` → mặc định PowerShell sẽ hỏi xác nhận; `-WhatIf` chạy thử; `-Confirm:$false` chỉ dùng trong menu sau khi admin đã xác nhận ở bước 4.
- Mỗi lệnh xoá thực sự nằm **bên trong** `if ($PSCmdlet.ShouldProcess($target, $action))`.
- Nhận input từ pipeline (`ValueFromPipelineByPropertyName`) với `SiteUrl` + `FileRef` – không tự tìm kiếm rồi xoá trong cùng 1 function.

## 2. Mặc định an toàn
- Xoá file: `Remove-PnPFile -Recycle` (vào Recycle Bin cấp 1, giữ 93 ngày tổng cộng). Xoá vĩnh viễn chỉ khi `-Permanent` được truyền rõ ràng.
- Xoá version: `Remove-PnPFileVersion -Recycle`. ⚠️ Cả `Remove-PnPFile` và `Remove-PnPFileVersion` **mặc định xoá vĩnh viễn** nếu thiếu `-Recycle` (đã kiểm chứng trên PnP.PowerShell 3.4.1). Không dùng `-All`.
- Truyền `-Identity` của version bằng ID kiểu `[int]` (FileVersionPipeBind có ctor Int32/String), `-List` bằng `$list.Id` (Guid).
- **Không bao giờ** gọi `Clear-PnPRecycleBinItem`, `Clear-PnPTenantRecycleBinItem`, `Remove-PnPTenantSite`, `Remove-PnPList` trong project này.
- Không bao giờ xoá trong `Preservation Hold Library`, thư viện hệ thống, hay site có `LockState` khác `Unlock`.
- Giới hạn an toàn: `-MaxItems` (mặc định 1000) – vượt quá thì dừng và yêu cầu admin chạy lại với giá trị lớn hơn.

## 3. Quy trình trong menu (Start-SPCleaner.ps1)
1. Quét → hiển thị kết quả (bảng + tổng số file, tổng dung lượng).
2. Xuất **manifest** `reports/<timestamp>-<action>-manifest.csv` (toàn bộ danh sách sẽ xoá). Manifest dùng được để khôi phục/đối chiếu.
3. Chạy `-WhatIf` → in tóm tắt.
4. Hỏi xác nhận: admin phải gõ chính xác `XOA` (hoặc `DELETE`). Với `-Permanent` hoặc batch delete job: xác nhận lần 2 bằng cách gõ số lượng file.
5. Chạy thật với `-Confirm:$false`, có `Write-Progress`.
6. In tóm tắt: thành công / thất bại / bỏ qua, dung lượng ước tính giải phóng, đường dẫn log.

## 4. Log hành động (Write-SPCLog)
- Ghi CSV append `logs/<yyyyMMdd>-actions.csv` với cột: `Timestamp, User, Action, SiteUrl, Target, Detail, SizeBytes, Result, Message, WhatIf`.
- Ghi cả khi `-WhatIf` (cột `WhatIf=True`) để có dấu vết.
- `User` = tài khoản đã kết nối: Interactive → `(Get-PnPWeb -Includes CurrentUser -Connection $conn).CurrentUser.Email` (lấy 1 lần, cache); app-only → `app:<ClientId>`.

## 5. Lỗi phải xử lý (không để dừng cả lô)
| Tình huống | Xử lý |
|---|---|
| File có retention label / eDiscovery hold | Bắt lỗi, `Result=Skipped`, Message nêu lý do |
| File đang check-out | Bỏ qua trước khi gọi API |
| File đã bị xoá/di chuyển sau khi quét | `Result=NotFound`, tiếp tục |
| 429/503 throttling | PnP tự retry; nếu vẫn lỗi sau N lần → dừng lô, in vị trí để chạy tiếp |
| Access denied | Log, tiếp tục; tổng kết cuối liệt kê site/thư viện thiếu quyền |

## 6. Khôi phục
Cung cấp hướng dẫn (và tuỳ chọn function `Restore-SPCFromManifest`):
```powershell
$manifest = Import-Csv .\reports\...-manifest.csv
$bin = Get-PnPRecycleBinItem -Connection $conn -RowLimit 5000
$bin | Where-Object { ("/" + $_.DirName + "/" + $_.LeafName) -in $manifest.FileRef } |
    Restore-PnPRecycleBinItem -Force -Connection $conn
```

## 7. Review trước khi merge
Mọi thay đổi đụng tới `Remove-*` phải được agent **spo-safety-reviewer** review (command `/spo-review`).
