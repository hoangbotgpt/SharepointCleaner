# SharepointCleaner

Bộ công cụ PowerShell (module **SPCleaner**, dựa trên [PnP.PowerShell](https://pnp.github.io/powershell/)) giúp admin tìm và dọn dẹp dữ liệu chiếm dung lượng trên SharePoint Online.

| # | Chức năng | Lệnh |
|---|---|---|
| 1 | Liệt kê site có dung lượng lớn hơn X GB | `Get-SPCLargeSite` |
| 2 | Liệt kê file lớn hơn X MB trong site | `Get-SPCLargeFile` |
| 3 | Liệt kê file trùng tên **và** trùng dung lượng trong site | `Get-SPCDuplicateFile` |
| 4 | Liệt kê file có nhiều hơn N version | `Get-SPCFileByVersionCount` |
| 5 | Xoá các version cũ hơn version được chọn / chỉ giữ K version mới nhất | `Remove-SPCOldFileVersion` |
| 6 | Liệt kê file không được truy cập kể từ ngày X | `Get-SPCStaleFile` |
| 7 | Xoá các file tìm được ở bước 6 | `Remove-SPCStaleFile` |
| – | Xem version của một file · Khôi phục từ manifest · Xuất báo cáo | `Get-SPCFileVersion` · `Restore-SPCFromManifest` · `Export-SPCReport` |

## Yêu cầu
- **PowerShell 7.4+** (`winget install Microsoft.PowerShell`). PnP.PowerShell không chạy trên Windows PowerShell 5.1.
- `Install-Module PnP.PowerShell -Scope CurrentUser`
- Tuỳ chọn, cho chức năng 6 với audit log: `Install-Module ExchangeOnlineManagement -Scope CurrentUser` và quyền **View-Only Audit Logs**.
- Tài khoản **SharePoint Administrator** (chế độ Interactive) hoặc app-only có certificate.

## Cài đặt
1. Đăng ký Entra ID app (từ 09/2024 bắt buộc mỗi tenant tự đăng ký):
   ```powershell
   Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'SharepointCleaner' -Tenant contoso.onmicrosoft.com -Interactive
   ```
   Chạy tự động / quét toàn tenant thì dùng app-only với certificate:
   ```powershell
   Register-PnPEntraIDApp -ApplicationName 'SharepointCleaner-AppOnly' -Tenant contoso.onmicrosoft.com `
       -OutPath .\certs -SharePointApplicationPermissions 'Sites.FullControl.All' -GraphApplicationPermissions 'Sites.Read.All' -Interactive
   ```
2. Copy `config/settings.example.json` thành `config/settings.json` và điền `TenantName`, `ClientId` (và `AuthMode: "Certificate"` + `CertificateThumbprint` nếu dùng app-only). File này đã nằm trong `.gitignore`.

## Sử dụng
### Menu tương tác
```powershell
pwsh ./scripts/Start-SPCleaner.ps1
```
Thao tác xoá trong menu luôn đi theo thứ tự: **chạy thử (WhatIf) → xuất manifest CSV → gõ `XOA` để xác nhận → xoá**. Mặc định đưa vào **Recycle Bin**; xoá vĩnh viễn phải chọn riêng và xác nhận lần 2.

### Dùng như module
```powershell
Import-Module ./src/SPCleaner/SPCleaner.psd1
Connect-SPCTenant

Get-SPCLargeSite -MinSizeGB 50 | Export-SPCReport -Name large-sites -Format Both
$site = 'https://contoso.sharepoint.com/sites/hr'

Get-SPCLargeFile      -SiteUrl $site -MinSizeMB 500 -Top 50
Get-SPCDuplicateFile  -SiteUrl $site | Export-SPCReport -Name duplicates

# Version: xem trước rồi mới xoá
$files = Get-SPCFileByVersionCount -SiteUrl $site -MinVersionCount 100
$files | Remove-SPCOldFileVersion -KeepLatest 20 -WhatIf
$files | Remove-SPCOldFileVersion -KeepLatest 20 -MaxFiles $files.Count

# Xoá các version cũ hơn 15.0 của một file
Get-SPCFileVersion -SiteUrl $site -FileRef '/sites/hr/Shared Documents/plan.xlsx'
Remove-SPCOldFileVersion -SiteUrl $site -FileRef '/sites/hr/Shared Documents/plan.xlsx' -OlderThanVersion 15.0

# File lâu không truy cập: xuất manifest trước, xoá sau, khôi phục nếu cần
Get-SPCStaleFile -SiteUrl $site -NotAccessedSince '2023-01-01' | Export-SPCReport -Name stale-manifest | Remove-SPCStaleFile -WhatIf
Import-Csv ./reports/<timestamp>-stale-manifest.csv | Remove-SPCStaleFile -MaxItems 5000
Restore-SPCFromManifest -ManifestPath ./reports/<timestamp>-stale-manifest.csv
```

## Lưu ý quan trọng
- **"Ngày truy cập cuối"**: SharePoint Online không lưu trường này cho từng file. `Get-SPCStaleFile -AccessSource` có 3 lựa chọn:
  - `Modified` (mặc định) – ngày sửa cuối; file chỉ được đọc vẫn bị coi là "cũ".
  - `AuditLog` – Purview audit log; chính xác hơn nhưng chỉ lưu ~180 ngày (Audit Standard). Ngưỡng cũ hơn → kết quả `AuditLog-partial`.
  - `Analytics` – Microsoft Graph item analytics; gọi API cho từng file nên chậm.
- Dung lượng site (`StorageUsageCurrent`) do SharePoint cập nhật trễ 24–48 giờ, và chỉ giảm sau khi Recycle Bin được dọn (tự động sau 93 ngày hoặc admin tự dọn).
- Trước khi xoá, mỗi file được kiểm tra lại: bỏ qua nếu đang check-out, có retention label, đã bị sửa sau ngưỡng, hoặc nằm trong Preservation Hold Library.
- Mọi thao tác (kể cả chạy thử) được ghi vào `logs/<yyyyMMdd>-actions.csv`.
- Giới hạn an toàn: mặc định tối đa 1000 file mỗi lần chạy (`-MaxFiles` / `-MaxItems`).
- Version quy mô rất lớn: cân nhắc `New-PnPSiteFileVersionBatchDeleteJob` (xoá phía server, **vĩnh viễn**) và cấu hình version history limits để tránh tái phát.

## Phát triển
```powershell
pwsh ./tools/Invoke-Checks.ps1            # BOM + PSScriptAnalyzer + Pester
pwsh ./tools/Invoke-Checks.ps1 -FixEncoding
```
Test cần PnP.PowerShell và Pester 5.5+ nhưng không cần kết nối tenant (toàn bộ cmdlet PnP được mock).

Project kèm plugin Claude Code `spo-admin-toolkit` (thư mục `plugins/`), gồm skills, commands (`/spo-feature`, `/spo-review`, `/spo-scaffold`) và hook kiểm tra code.
