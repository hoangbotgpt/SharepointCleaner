function Get-SPCVersionHistory {
    <#
    .SYNOPSIS
    Returns the historical versions of a file (never the current one), newest first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileRef,
        $Connection
    )
    $raw = Invoke-SPCWithRetry { Get-PnPFileVersion -Url $FileRef -Connection $Connection -ErrorAction Stop }
    @($raw) |
        Where-Object { $_ -and -not (Get-SPCPropertyValue -InputObject $_ -Name 'IsCurrentVersion') } |
        ForEach-Object {
            $length = Get-SPCPropertyValue -InputObject $_ -Name 'Length'
            if ($null -eq $length) { $length = Get-SPCPropertyValue -InputObject $_ -Name 'Size' }
            [pscustomobject]@{
                VersionLabel = [string]$_.VersionLabel
                Version      = ConvertTo-SPCVersion $_.VersionLabel
                Id           = [int]$_.ID
                Created      = ConvertTo-SPCLocalTime (Get-SPCPropertyValue -InputObject $_ -Name 'Created')
                SizeBytes    = ConvertTo-SPCInt64 $length
            }
        } |
        Sort-Object -Property @{ Expression = { if ($_.Version) { $_.Version } else { [version]'0.0' } } }, Id -Descending
}
