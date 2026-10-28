---
name: spo-version-cleanup
description: Liệt kê file có số version lớn hơn N và xoá các version cũ hơn version admin chọn (hoặc chỉ giữ lại K version mới nhất) trên SharePoint Online. Dùng khi viết Get-SPCFileByVersionCount, Remove-SPCOldFileVersion, chức năng 4 và 5 của menu. Triggers - "version", "nhiều phiên bản", "xoá version cũ", "Get-PnPFileVersion", "Remove-PnPFileVersion", "version history", "batch delete version".
---

# Chức năng 4 & 5 – Version

## Khái niệm cần nắm
- `Get-PnPFileVersion -Url <FileRef>` trả về **các version lịch sử** (không gồm version hiện tại). Tổng số version = `history.Count + 1`.
- Mỗi version có `VersionLabel` ("3.0", "2.5"), `ID` (= major*512 + minor), `Created`, `CreatedBy`, `Size`, `IsCurrentVersion`.
- So sánh label bằng `[version]$label` (System.Version parse được "2.5"). KHÔNG so chuỗi.
- **Không bao giờ xoá version hiện tại**. Không thao tác file đang check-out (`CheckedOutTo` khác rỗng) – bỏ qua và log.

## Chức năng 4 – File có > N version
Tối ưu: tránh gọi `Get-PnPFileVersion` cho từng file.
- Nếu thư viện **không bật minor version**, số version ≤ số major trong `_UIVersionString` → bỏ qua ngay những file có `[version]$VersionLabel).Major -le $MinVersionCount`.
- Chỉ những file còn lại mới gọi API lấy version để đếm chính xác.
```powershell
function Get-SPCFileByVersionCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][ValidateRange(1, 50000)][int]$MinVersionCount,
        [switch]$Refresh
    )
    $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
    $candidates = Get-SPCFileInventory -SiteUrl $SiteUrl -Refresh:$Refresh | Where-Object {
        $_.MinorVersions -or ([version]$_.VersionLabel).Major -gt $MinVersionCount
    }
    $n = 0
    foreach ($f in $candidates) {
        $n++
        Write-Progress -Activity 'Đếm version' -Status $f.FileRef -PercentComplete (100 * $n / @($candidates).Count)
        try {
            $history = @(Get-PnPFileVersion -Url $f.FileRef -Connection $conn -ErrorAction Stop)
        } catch { Write-SPCLog -Level Warning -Message "Không đọc được version: $($f.FileRef) - $_"; continue }
        $count = $history.Count + 1
        if ($count -gt $MinVersionCount) {
            $f | Add-Member -NotePropertyMembers @{
                VersionCount       = $count
                OldestVersion      = ($history | Sort-Object { [version]$_.VersionLabel } | Select-Object -First 1).VersionLabel
                VersionsSizeMB     = [math]::Round((($history | Measure-Object Size -Sum).Sum) / 1MB, 2)
                AvailableVersions  = ($history.VersionLabel -join ';')
            } -PassThru -Force
        }
    }
}
```

## Chức năng 5 – Xoá version cũ hơn version admin chọn
Hai chế độ (ParameterSet, bắt buộc chọn một):
1. `-OlderThanVersion '5.0'` – xoá mọi version có label **nhỏ hơn** 5.0 (giữ 5.0 trở lên). Phù hợp khi admin chọn 1 file cụ thể và trỏ vào 1 version trong danh sách.
2. `-KeepLatest 10` – với mỗi file giữ lại 10 version mới nhất (tính cả version hiện tại), xoá phần còn lại. Phù hợp khi áp dụng hàng loạt cho nhiều file đã tìm ở chức năng 4 (vì label mỗi file khác nhau).

Tuỳ chọn bổ sung: `-OlderThanDate` – chỉ xoá version tạo trước ngày X (kết hợp với 1 trong 2 chế độ trên).

```powershell
function Remove-SPCOldFileVersion {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Keep')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$SiteUrl,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$FileRef,
        [Parameter(Mandatory, ParameterSetName = 'Label')][version]$OlderThanVersion,
        [Parameter(Mandatory, ParameterSetName = 'Keep')][ValidateRange(1, 50000)][int]$KeepLatest,
        [datetime]$OlderThanDate
    )
    process {
        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        $history = @(Get-PnPFileVersion -Url $FileRef -Connection $conn) |
            Sort-Object { [version]$_.VersionLabel } -Descending      # mới → cũ

        $toDelete = switch ($PSCmdlet.ParameterSetName) {
            'Label' { $history | Where-Object { [version]$_.VersionLabel -lt $OlderThanVersion } }
            'Keep'  { $history | Select-Object -Skip ([math]::Max($KeepLatest - 1, 0)) }  # -1 vì current không nằm trong history
        }
        if ($OlderThanDate) { $toDelete = $toDelete | Where-Object Created -lt $OlderThanDate }

        foreach ($v in $toDelete) {
            if ($PSCmdlet.ShouldProcess("$FileRef v$($v.VersionLabel) ($([math]::Round($v.Size/1MB,2)) MB)", 'Xoá version')) {
                try {
                    # -Identity nhận Int32 (ID version) hoặc String; dùng ID cho chắc chắn. -Recycle là BẮT BUỘC.
                    Remove-PnPFileVersion -Url $FileRef -Identity ([int]$v.ID) -Recycle -Force -Connection $conn -ErrorAction Stop
                    Write-SPCLog -Action DeleteVersion -Target $FileRef -Detail $v.VersionLabel -SizeBytes $v.Size -Result Success
                } catch {
                    Write-SPCLog -Action DeleteVersion -Target $FileRef -Detail $v.VersionLabel -Result Failed -Message $_.Exception.Message
                }
            }
        }
    }
}
```
- ⚠️ `Remove-PnPFileVersion` (PnP.PowerShell 3.x) **mặc định XOÁ VĨNH VIỄN**; chỉ vào Recycle Bin khi truyền switch `-Recycle`. Luôn truyền `-Recycle`, chỉ bỏ khi admin bật `-Permanent` rõ ràng – xem skill **spo-safe-delete**.
- Tương tự `Remove-PnPFile` mặc định xoá vĩnh viễn, phải truyền `-Recycle`.
- Nếu file có retention label/hold, xoá version có thể bị từ chối → log Failed, tiếp tục.
- Sau khi xoá, dung lượng site (`StorageUsageCurrent`) chỉ giảm khi recycle bin được dọn và sau chu kỳ cập nhật (24–48h). Nói rõ cho admin.

## Phương án quy mô lớn (toàn site/thư viện)
Khi số file rất lớn, thay vì xoá từng version, đề xuất admin dùng job phía server (kiểm tra cmdlet tồn tại bằng `Get-Command` trước khi dùng, vì tuỳ phiên bản module):
- `New-PnPSiteFileVersionBatchDeleteJob` / `New-SPOSiteFileVersionBatchDeleteJob -Identity <site> -DeleteBeforeDays 365` hoặc `-MajorVersionLimit 50 -MajorWithMinorVersionsLimit 10`.
- Theo dõi: `Get-SPOSiteFileVersionBatchDeleteJobProgress`.
- Ngăn tái phát: Version history limits ở cấp tenant/site/thư viện (`Set-PnPTenant -EnableAutoExpirationVersionTrim`, `Set-PnPList -MajorVersions`).
Các job này **xoá vĩnh viễn, không qua Recycle Bin** → bắt buộc xác nhận 2 lần trong menu.
