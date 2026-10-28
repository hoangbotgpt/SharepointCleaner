function Get-SPCDriveMap {
    <#
    .SYNOPSIS
    Maps library server-relative URL (lower-case) to its Microsoft Graph drive id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        $Connection
    )
    $uri = [uri]$SiteUrl.TrimEnd('/')
    $path = $uri.AbsolutePath.TrimEnd('/')
    $siteRequest = if ($path) { "v1.0/sites/$($uri.Host):$path" } else { "v1.0/sites/$($uri.Host)" }
    $graphSite = Invoke-SPCWithRetry { Invoke-PnPGraphMethod -Url $siteRequest -Method Get -Connection $Connection -ErrorAction Stop }
    $drives = Invoke-SPCWithRetry { Invoke-PnPGraphMethod -Url "v1.0/sites/$($graphSite.id)/drives?`$select=id,webUrl" -Method Get -Connection $Connection -ErrorAction Stop }
    $map = @{}
    foreach ($drive in @($drives.value)) {
        $key = [uri]::UnescapeDataString(([uri]$drive.webUrl).AbsolutePath).TrimEnd('/').ToLowerInvariant()
        $map[$key] = $drive.id
    }
    $map
}

function Get-SPCAnalyticsLastAccess {
    <#
    .SYNOPSIS
    Uses Graph item analytics (getActivitiesByInterval) to find the end of the latest interval with access activity.
    Returns $null when there is no activity or no data.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$File,
        [Parameter(Mandatory)][datetime]$Since,
        [Parameter(Mandatory)][hashtable]$DriveMap,
        $Connection
    )
    $libraryUrl = "$($File.LibraryUrl)".TrimEnd('/')
    $driveId = $DriveMap[$libraryUrl.ToLowerInvariant()]
    if (-not $driveId -or -not $libraryUrl) {
        Write-SPCLog -Level Warning -Action Analytics -SiteUrl $File.SiteUrl -Target $File.FileRef -Result Skipped -Message 'Không tìm thấy drive Graph của thư viện.'
        return $null
    }
    $relative = $File.FileRef.Substring($libraryUrl.Length).TrimStart('/')
    $encoded = ($relative -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'

    $now = Get-Date
    $days = ($now - $Since).TotalDays
    $interval = if ($days -le 60) { 'day' } elseif ($days -le 365) { 'week' } else { 'month' }
    $start = $Since.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $end = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $url = "v1.0/drives/$driveId/root:/${encoded}:/getActivitiesByInterval(startDateTime='$start',endDateTime='$end',interval='$interval')"

    try {
        $response = Invoke-SPCWithRetry { Invoke-PnPGraphMethod -Url $url -Method Get -Connection $Connection -ErrorAction Stop }
    } catch {
        Write-SPCLog -Level Warning -Action Analytics -SiteUrl $File.SiteUrl -Target $File.FileRef -Result Failed -Message $_.Exception.Message
        return $null
    }
    $hit = @($response.value) |
        Where-Object { $_.access -and [int]$_.access.actionCount -gt 0 } |
        Sort-Object -Property { [datetime]$_.startDateTime } -Descending |
        Select-Object -First 1
    if ($hit) { ConvertTo-SPCLocalTime ([datetime]$hit.endDateTime) }
}
