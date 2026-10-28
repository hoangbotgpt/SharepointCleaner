---
name: spo-site-storage
description: Liệt kê các site SharePoint Online (và tuỳ chọn OneDrive) có dung lượng sử dụng lớn hơn ngưỡng admin nhập, kèm quota và % sử dụng. Dùng khi viết Get-SPCLargeSite hoặc chức năng số 1 của menu. Triggers - "site dung lượng lớn", "site storage", "StorageUsageCurrent", "Get-PnPTenantSite", "quota".
---

# Chức năng 1 – Site có dung lượng lớn hơn X

## Nguồn dữ liệu
`Get-PnPTenantSite` (cần connection tới **admin center**) trả về:
- `StorageUsageCurrent` – dung lượng đang dùng, đơn vị **MB** (gồm cả version, recycle bin cấp 1 & 2, preservation hold library).
- `StorageQuota` – quota, đơn vị MB.
- Số liệu được SharePoint cập nhật định kỳ, **có thể trễ tới 24–48 giờ** – ghi chú điều này trong output/help.

## Mẫu implement
```powershell
function Get-SPCLargeSite {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][ValidateRange(0.001, 1000000)]
        [double]$MinSizeGB,
        [switch]$IncludeOneDrive,
        [string]$UrlFilter        # ví dụ '*project*'
    )
    $admin = $script:SPCAdminConnection
    if (-not $admin) { throw 'Chưa kết nối. Hãy chạy Connect-SPCTenant trước.' }

    $params = @{ Connection = $admin }
    if ($IncludeOneDrive) { $params.IncludeOneDriveSites = $true }

    $minMB = $MinSizeGB * 1024
    Get-PnPTenantSite @params |
        Where-Object { $_.StorageUsageCurrent -ge $minMB } |
        Where-Object { -not $UrlFilter -or $_.Url -like $UrlFilter } |
        Sort-Object StorageUsageCurrent -Descending |
        ForEach-Object {
            [pscustomobject]@{
                SiteUrl       = $_.Url
                Title         = $_.Title
                Template      = $_.Template
                UsedGB        = [math]::Round($_.StorageUsageCurrent / 1024, 2)
                QuotaGB       = [math]::Round($_.StorageQuota / 1024, 2)
                PercentUsed   = if ($_.StorageQuota) { [math]::Round(100 * $_.StorageUsageCurrent / $_.StorageQuota, 1) } else { $null }
                Owner         = $_.Owner
                LastContentModified = $_.LastContentModifiedDate
                LockState     = $_.LockState
            }
        }
}
```

## Lưu ý
- Loại trừ site hệ thống nếu cần: template `SRCHCEN#0`, `SPSMSITEHOST#0`, `APPCATALOG#0`, `REDIRECTSITE#0`, `POINTPUBLISHINGTOPIC#0`.
- Đơn vị nhập vào là GB (admin dễ hình dung); hiển thị cả GB và % quota.
- Tổng dung lượng tenant để đối chiếu: `Get-PnPTenant | Select StorageQuota, StorageQuotaAllocated` hoặc Admin Center > Settings.
- Site bị `LockState = NoAccess/ReadOnly` → cảnh báo, các chức năng xoá sẽ thất bại trên site đó.
- Kết quả của chức năng này là nguồn để admin **chọn site** cho chức năng 2–7 (menu hiển thị danh sách đánh số).
