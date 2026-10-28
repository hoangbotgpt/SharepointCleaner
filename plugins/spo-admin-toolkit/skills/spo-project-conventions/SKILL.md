---
name: spo-project-conventions
description: Kiến trúc, cấu trúc thư mục, quy ước đặt tên, schema output và chuẩn code PowerShell của project SharepointCleaner (module SPCleaner dùng PnP.PowerShell). Dùng khi scaffold project, thêm function mới, viết menu tương tác, xuất báo cáo CSV/HTML, hoặc bất kỳ khi nào viết/sửa file .ps1/.psm1/.psd1 trong project này. Triggers - "thêm chức năng", "tạo function", "scaffold", "module structure", "menu", "report", "PowerShell SharePoint".
---

# SharepointCleaner – quy ước project

## Môi trường bắt buộc
- **PowerShell 7.4+** (`pwsh`). PnP.PowerShell 2.x/3.x KHÔNG chạy trên Windows PowerShell 5.1.
- Module: `PnP.PowerShell` (bắt buộc), `ExchangeOnlineManagement` (chỉ khi dùng audit log cho chức năng "file lâu không truy cập"), `Pester` 5.x, `PSScriptAnalyzer` (dev).
- Script chạy trực tiếp (`scripts/`, `tools/`) bắt đầu bằng `#Requires -Version 7.4`. Module **không** khai báo `RequiredModules`/`#Requires -Modules PnP.PowerShell` (để import và test được nhanh); `Connect-SPCTenant` tự kiểm tra PnP.PowerShell đã cài.

## Cấu trúc thư mục
```
SharepointCleaner/
├─ src/SPCleaner/
│  ├─ SPCleaner.psd1            # manifest, FunctionsToExport liệt kê rõ ràng
│  ├─ SPCleaner.psm1            # dot-source Private/*.ps1 rồi Public/*.ps1
│  ├─ Public/                   # 1 function / 1 file, tên file = tên function
│  │  ├─ Connect-SPCTenant.ps1
│  │  ├─ Get-SPCLargeSite.ps1            # (1) site > X GB
│  │  ├─ Get-SPCLargeFile.ps1            # (2) file > X MB trong site
│  │  ├─ Get-SPCDuplicateFile.ps1        # (3) file trùng tên + dung lượng
│  │  ├─ Get-SPCFileByVersionCount.ps1 # (4) file có > N version
│  │  ├─ Remove-SPCOldFileVersion.ps1    # (5) xoá version cũ hơn version chọn
│  │  ├─ Get-SPCStaleFile.ps1            # (6) file truy cập lần cuối trước ngày X
│  │  ├─ Remove-SPCStaleFile.ps1         # (7) xoá các file đó
│  │  └─ Export-SPCReport.ps1
│  └─ Private/
│     ├─ Get-SPCSiteConnection.ps1  # cache connection theo SiteUrl
│     ├─ Get-SPCFileInventory.ps1   # quét toàn bộ file của site (dùng chung cho 2,3,4,6)
│     ├─ Write-SPCLog.ps1
│     ├─ Invoke-SPCWithRetry.ps1
│     └─ Format-SPCSize.ps1
├─ scripts/Start-SPCleaner.ps1   # menu tương tác cho admin
├─ config/settings.example.json  # ClientId, Tenant, AdminUrl, Thumbprint... (KHÔNG commit settings.json thật)
├─ tests/*.Tests.ps1             # Pester 5, mock toàn bộ cmdlet PnP
├─ reports/   logs/              # output, nằm trong .gitignore
└─ README.md
```

## Quy ước đặt tên
- Prefix danh từ **`SPC`** (SharePoint Cleaner): `Get-SPCLargeSite`. KHÔNG dùng prefix `SPO` vì trùng với cmdlet của `Microsoft.Online.SharePoint.PowerShell` (`Get-SPOSite`...).
- Chỉ dùng approved verbs (`Get-Verb`). Function đọc = `Get-`, function xoá = `Remove-`.
- Tham số đơn vị rõ ràng: `-MinSizeGB`, `-MinSizeMB`, `-MinVersionCount`, `-NotAccessedSince [datetime]`.

## Khung function chuẩn
```powershell
function Get-SPCLargeFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidatePattern('^https://[\w-]+\.sharepoint\.com/')]
        [string]$SiteUrl,

        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)]
        [double]$MinSizeMB,

        [switch]$IncludeSystemLibraries
    )
    begin   { $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl }
    process {
        Get-SPCFileInventory -SiteUrl $SiteUrl -Connection $conn -IncludeSystemLibraries:$IncludeSystemLibraries |
            Where-Object SizeBytes -ge ($MinSizeMB * 1MB) |
            Sort-Object SizeBytes -Descending
    }
}
```
- Function `Remove-*` luôn có `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]` – xem skill **spo-safe-delete**.
- Không dùng `Write-Host` trong module (chỉ trong `scripts/Start-SPCleaner.ps1`). Dùng `Write-Verbose`, `Write-Progress`, `Write-Warning`, và `Write-SPCLog`.
- Luôn truyền `-Connection $conn` vào cmdlet PnP; không phụ thuộc connection "hiện tại" ngầm định.

## Schema object output (thống nhất để pipe Get-* → Remove-*)
Mọi function trả về file phải xuất `[pscustomobject]` có các property sau (thiếu thì để `$null`):

| Property | Kiểu | Ghi chú |
|---|---|---|
| `SiteUrl` | string | URL site gốc |
| `Library` | string | Title thư viện |
| `FileName` | string | `FileLeafRef` |
| `FileRef` | string | server-relative URL (`/sites/x/Shared Documents/a.docx`) – khoá chính để xoá |
| `UniqueId` | guid | |
| `SizeBytes` | int64 | `File_x0020_Size` |
| `TotalSizeBytes` | int64 | `SMTotalSize` (gồm version) nếu lấy được |
| `SizeMB` | double | làm tròn 2 số |
| `VersionLabel` | string | `_UIVersionString` |
| `VersionCount` | int | chỉ có ở function version |
| `Modified` | datetime | |
| `ModifiedBy` | string | email |
| `LastAccessed` | datetime | chỉ có ở function stale |
| `AccessSource` | string | `Modified` / `AuditLog` / `Analytics` |

Tham số của `Remove-*` nhận `SiteUrl` và `FileRef` qua `ValueFromPipelineByPropertyName`, nên admin có thể:
```powershell
Get-SPCStaleFile -SiteUrl $u -NotAccessedSince '2024-01-01' | Export-SPCReport -Name stale |
    Remove-SPCStaleFile -WhatIf
```
Và cũng nhận lại từ CSV: `Import-Csv .\reports\stale.csv | Remove-SPCStaleFile`.

## Báo cáo
- `Export-SPCReport -Name <tên> [-Format Csv|Html|Both]` ghi vào `reports/<yyyyMMdd-HHmmss>-<tên>.csv`, dùng `-Encoding utf8BOM` để Excel đọc đúng tiếng Việt, và **pass-through** object ra pipeline.
- Dung lượng hiển thị qua `Format-SPCSize` (B/KB/MB/GB/TB).

## Menu tương tác (`scripts/Start-SPCleaner.ps1`)
- Menu đánh số 1–7 tương ứng 7 chức năng, cùng mục Kết nối / Thoát.
- Nhập liệu được validate (số > 0, ngày theo `dd/MM/yyyy` hoặc `yyyy-MM-dd`, URL site). Cho chọn site từ kết quả chức năng (1) bằng `Out-ConsoleGridView` nếu có module `Microsoft.PowerShell.ConsoleGuiTools`, nếu không thì chọn theo số thứ tự.
- Mọi thao tác xoá trong menu: chạy **dry-run (-WhatIf) trước** → hiện tổng số file/dung lượng → xuất CSV manifest → bắt admin gõ `XOA` (hoặc `DELETE`) để xác nhận → mới chạy thật.
- Thông báo cho admin bằng tiếng Việt; tên biến/function/comment code bằng tiếng Anh.

## Hiệu năng
- Quét site lớn: `Get-PnPListItem -PageSize 2000` và chỉ yêu cầu field cần thiết (`-Fields`). Xem skill **spo-file-inventory**.
- Cache inventory theo site trong phiên (`$script:InventoryCache[$SiteUrl]`) để chức năng 2/3/4/6 không quét lại; có `-Refresh` để xoá cache.
- PnP tự retry khi bị throttling (HTTP 429/503 theo `Retry-After`); với Graph/Audit tự gọi qua `Invoke-SPCWithRetry`.

## Kiểm tra chất lượng
- `Invoke-ScriptAnalyzer -Path src -Recurse -Settings PSGallery` không có lỗi Error/Warning.
- `Invoke-Pester -Path tests` pass. Xem skill **spo-pester-testing**.
- Chạy gộp cả hai: `pwsh ./tools/Invoke-Checks.ps1` (thêm `-FixEncoding` để tự thêm UTF-8 BOM).
- Khi đọc thuộc tính có thể chưa load của object CSOM, dùng `Get-SPCPropertyValue` (kiểm tra `PSObject.Properties` trước). Không dùng `try { $obj.Length }`: PowerShell trả `1` cho mọi object đơn lẻ không có `Length`.
