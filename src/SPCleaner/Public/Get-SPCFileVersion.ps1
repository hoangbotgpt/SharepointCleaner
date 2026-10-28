function Get-SPCFileVersion {
    <#
    .SYNOPSIS
    Hiển thị các version lịch sử của một file (không gồm version hiện tại), mới nhất trước.
    Dùng để admin chọn mốc version cho Remove-SPCOldFileVersion -OlderThanVersion.

    .EXAMPLE
    Get-SPCFileVersion -SiteUrl https://contoso.sharepoint.com/sites/hr -FileRef '/sites/hr/Shared Documents/plan.xlsx'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^/')]
        [string]$FileRef
    )
    process {
        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        Get-SPCVersionHistory -FileRef $FileRef -Connection $conn | ForEach-Object {
            [pscustomobject]@{
                SiteUrl      = $SiteUrl
                FileRef      = $FileRef
                VersionLabel = $_.VersionLabel
                Id           = $_.Id
                Created      = $_.Created
                SizeBytes    = $_.SizeBytes
                SizeMB       = if ($null -ne $_.SizeBytes) { [math]::Round($_.SizeBytes / 1MB, 2) } else { $null }
            }
        }
    }
}
