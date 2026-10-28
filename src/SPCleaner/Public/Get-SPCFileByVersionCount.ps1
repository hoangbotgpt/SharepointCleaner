function Get-SPCFileByVersionCount {
    <#
    .SYNOPSIS
    (4) Liệt kê các file có số version (tính cả version hiện tại) lớn hơn N.

    .DESCRIPTION
    Với thư viện không bật minor version, số version không thể vượt quá số major của version hiện tại,
    nên các file đó được loại ngay mà không cần gọi API lấy version.

    .EXAMPLE
    Get-SPCFileByVersionCount -SiteUrl https://contoso.sharepoint.com/sites/hr -MinVersionCount 100
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory)]
        [ValidateRange(1, 50000)]
        [int]$MinVersionCount,

        [string[]]$Library,

        [switch]$IncludeSystemLibraries,

        [switch]$Refresh
    )
    process {
        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        $candidates = @(Get-SPCFileInventory -SiteUrl $SiteUrl -Library $Library -IncludeSystemLibraries:$IncludeSystemLibraries -Refresh:$Refresh |
                Where-Object {
                    $current = ConvertTo-SPCVersion $_.VersionLabel
                    $_.MinorVersionsEnabled -or $null -eq $current -or $current.Major -gt $MinVersionCount
                })

        $index = 0
        foreach ($file in $candidates) {
            $index++
            Write-Progress -Activity 'Đếm version' -Status $file.FileRef -PercentComplete (100 * ($index - 1) / $candidates.Count)
            try {
                $history = @(Get-SPCVersionHistory -FileRef $file.FileRef -Connection $conn)
            } catch {
                Write-SPCLog -Level Warning -Action ReadVersions -SiteUrl $SiteUrl -Target $file.FileRef -Result Failed -Message $_.Exception.Message
                continue
            }
            $count = $history.Count + 1
            if ($count -le $MinVersionCount) { continue }

            $historyBytes = [int64](($history | Measure-Object -Property SizeBytes -Sum).Sum)
            $copy = Copy-SPCObject $file
            $copy | Add-Member -NotePropertyMembers ([ordered]@{
                    VersionCount      = $count
                    OldestVersion     = ($history | Select-Object -Last 1).VersionLabel
                    VersionsSizeBytes = $historyBytes
                    VersionsSizeMB    = [math]::Round($historyBytes / 1MB, 2)
                    AvailableVersions = @($history.VersionLabel)
                }) -Force
            $copy
        }
        Write-Progress -Activity 'Đếm version' -Completed
    }
}
