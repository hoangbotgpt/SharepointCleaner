function Get-SPCDuplicateFile {
    <#
    .SYNOPSIS
    (3) Liệt kê các file trùng tên (không phân biệt hoa thường) VÀ trùng dung lượng trong site.

    .DESCRIPTION
    Mỗi dòng là một file, có DuplicateGroup để nhóm. Bản cũ nhất trong nhóm có IsOldestCopy = True.
    WastedBytes của nhóm = dung lượng × (số bản − 1). Chức năng này chỉ liệt kê, không xoá.

    .EXAMPLE
    Get-SPCDuplicateFile -SiteUrl https://contoso.sharepoint.com/sites/hr | Export-SPCReport -Name duplicates
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [ValidateRange(0, 10485760)]
        [double]$MinSizeMB = 0,

        [string[]]$Library,

        [switch]$IncludeSystemLibraries,

        [switch]$Refresh
    )
    process {
        $minBytes = [math]::Max($MinSizeMB * 1MB, 1)
        $groups = Get-SPCFileInventory -SiteUrl $SiteUrl -Library $Library -IncludeSystemLibraries:$IncludeSystemLibraries -Refresh:$Refresh |
            Where-Object { $_.SizeBytes -ge $minBytes } |
            Group-Object -Property { $_.FileName.ToLowerInvariant() }, SizeBytes |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object -Property { $_.Group[0].SizeBytes * ($_.Count - 1) } -Descending

        $groupId = 0
        foreach ($group in $groups) {
            $groupId++
            $wasted = [int64]$group.Group[0].SizeBytes * ($group.Count - 1)
            $first = $true
            foreach ($file in ($group.Group | Sort-Object -Property Modified)) {
                $copy = Copy-SPCObject $file
                $copy | Add-Member -NotePropertyMembers ([ordered]@{
                        DuplicateGroup = $groupId
                        DuplicateCount = $group.Count
                        IsOldestCopy   = $first
                        WastedBytes    = $wasted
                        WastedMB       = [math]::Round($wasted / 1MB, 2)
                    }) -Force
                $first = $false
                $copy
            }
        }
    }
}
