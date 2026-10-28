function Get-SPCLargeFile {
    <#
    .SYNOPSIS
    (2) Liệt kê các file có dung lượng lớn hơn ngưỡng (MB) trong site.

    .DESCRIPTION
    SizeBytes là dung lượng version hiện tại; TotalSizeBytes (nếu tenant trả về) gồm cả các version cũ.

    .EXAMPLE
    Get-SPCLargeFile -SiteUrl https://contoso.sharepoint.com/sites/hr -MinSizeMB 500 -Top 100
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory)]
        [ValidateRange(0.001, 10485760)]
        [double]$MinSizeMB,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Top = 0,

        [string[]]$Library,

        [switch]$IncludeSystemLibraries,

        [switch]$Refresh
    )
    process {
        $minBytes = $MinSizeMB * 1MB
        $result = Get-SPCFileInventory -SiteUrl $SiteUrl -Library $Library -IncludeSystemLibraries:$IncludeSystemLibraries -Refresh:$Refresh |
            Where-Object { $_.SizeBytes -ge $minBytes } |
            Sort-Object -Property SizeBytes -Descending
        if ($Top -gt 0) { $result | Select-Object -First $Top } else { $result }
    }
}
