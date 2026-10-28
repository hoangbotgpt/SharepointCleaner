function Get-SPCStaleFile {
    <#
    .SYNOPSIS
    (6) Liệt kê các file có lần truy cập cuối trước ngày chỉ định.

    .DESCRIPTION
    SharePoint Online KHÔNG lưu "ngày truy cập cuối" cho từng file. Nguồn dữ liệu (-AccessSource):
      Modified  (mặc định) – ngày sửa cuối; nhanh nhưng file chỉ được đọc vẫn bị coi là cũ.
      AuditLog  – Purview audit log (FileAccessed/Downloaded/Previewed/Modified…). Chỉ lưu ~180 ngày
                  (Audit Standard), cần ExchangeOnlineManagement + quyền View-Only Audit Logs.
      Analytics – Graph item analytics (getActivitiesByInterval). Gọi API cho từng file, dữ liệu có thời hạn.
    File bị coi là "stale" khi Modified < ngày nhập VÀ không có truy cập nào sau ngày đó theo nguồn đã chọn.

    .EXAMPLE
    Get-SPCStaleFile -SiteUrl $site -NotAccessedSince '2024-01-01' | Export-SPCReport -Name stale
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory)]
        [datetime]$NotAccessedSince,

        [ValidateSet('Modified', 'AuditLog', 'Analytics')]
        [string]$AccessSource = 'Modified',

        [ValidateRange(1, 3650)]
        [int]$AuditRetentionDays = 180,

        [string[]]$Library,

        [switch]$IncludeSystemLibraries,

        [switch]$Refresh
    )
    begin {
        if ($NotAccessedSince -ge (Get-Date)) { throw 'Ngày nhập phải ở quá khứ.' }
    }
    process {
        $candidates = @(Get-SPCFileInventory -SiteUrl $SiteUrl -Library $Library -IncludeSystemLibraries:$IncludeSystemLibraries -Refresh:$Refresh |
                Where-Object { $_.Modified -and $_.Modified -lt $NotAccessedSince })
        if ($candidates.Count -eq 0) { return }

        $sourceLabel = $AccessSource
        $auditMap = $null
        $driveMap = $null
        $conn = $null
        switch ($AccessSource) {
            'AuditLog' {
                $auditStart = $NotAccessedSince
                $earliest = (Get-Date).Date.AddDays(-$AuditRetentionDays)
                if ($auditStart -lt $earliest) {
                    Write-Warning (("Audit log chỉ lưu khoảng $AuditRetentionDays ngày. Chỉ kiểm tra truy cập từ {0:yyyy-MM-dd}; " +
                            'truy cập trước mốc này không được tính (kết quả đánh dấu AuditLog-partial).') -f $earliest)
                    $auditStart = $earliest
                    $sourceLabel = 'AuditLog-partial'
                }
                $auditMap = Get-SPCAuditLastAccess -SiteUrl $SiteUrl -StartDate $auditStart
            }
            'Analytics' {
                Write-Warning "Analytics gọi Graph cho từng file ($($candidates.Count) file) – có thể chạy lâu."
                $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
                $driveMap = Get-SPCDriveMap -SiteUrl $SiteUrl -Connection $conn
            }
        }

        $index = 0
        foreach ($file in $candidates) {
            $index++
            $accessed = switch ($AccessSource) {
                'Modified' { $null }
                'AuditLog' { $auditMap[$file.FileRef.ToLowerInvariant()] }
                'Analytics' {
                    Write-Progress -Activity 'Đọc analytics' -Status $file.FileRef -PercentComplete (100 * ($index - 1) / $candidates.Count)
                    Get-SPCAnalyticsLastAccess -File $file -Since $NotAccessedSince -DriveMap $driveMap -Connection $conn
                }
            }
            $effective = @($file.Modified, $accessed) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
            if ($effective -lt $NotAccessedSince) {
                $copy = Copy-SPCObject $file
                $copy | Add-Member -NotePropertyMembers ([ordered]@{
                        LastAccessed   = $effective
                        AccessSource   = $sourceLabel
                        StaleThreshold = $NotAccessedSince
                    }) -Force
                $copy
            }
        }
        if ($AccessSource -eq 'Analytics') { Write-Progress -Activity 'Đọc analytics' -Completed }
    }
}
