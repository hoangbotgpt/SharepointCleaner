function Get-SPCSiteConnection {
    <#
    .SYNOPSIS
    Returns a cached PnP connection for a site, opening it on first use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl
    )
    Assert-SPCConnected
    $key = $SiteUrl.TrimEnd('/').ToLowerInvariant()
    if (-not $script:SPCConnections.ContainsKey($key)) {
        $script:SPCConnections[$key] = Connect-SPCSite -Url $SiteUrl.TrimEnd('/')
    }
    $script:SPCConnections[$key]
}
