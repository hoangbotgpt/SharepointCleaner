function Get-SPCAuditLastAccess {
    <#
    .SYNOPSIS
    Reads the Purview unified audit log and returns @{ '<server-relative path lower-case>' = <last access, local time> }
    for files of one site. Requires ExchangeOnlineManagement and the View-Only Audit Logs role.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][datetime]$StartDate,
        [datetime]$EndDate = (Get-Date),
        [ValidateRange(1, 90)][int]$WindowDays = 7
    )

    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            throw 'Cần module ExchangeOnlineManagement để đọc audit log: Install-Module ExchangeOnlineManagement -Scope CurrentUser'
        }
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    }

    $operations = 'FileAccessed', 'FileAccessedExtended', 'FileDownloaded', 'FilePreviewed',
        'FileModified', 'FileModifiedExtended', 'FileSyncDownloadedFull'
    $extra = @{}
    if ((Get-Command Search-UnifiedAuditLog).Parameters.ContainsKey('SiteIds')) {
        try {
            $siteId = (Get-PnPSite -Includes Id -Connection (Get-SPCSiteConnection -SiteUrl $SiteUrl) -ErrorAction Stop).Id
            if ($siteId) { $extra.SiteIds = [string]$siteId }
        } catch {
            Write-Verbose "Không lấy được Site Id, lọc audit log theo SiteUrl: $($_.Exception.Message)"
        }
    }

    $site = $SiteUrl.TrimEnd('/')
    $map = @{}
    $windowStart = $StartDate
    while ($windowStart -lt $EndDate) {
        $windowEnd = $windowStart.AddDays($WindowDays)
        if ($windowEnd -gt $EndDate) { $windowEnd = $EndDate }
        Write-Progress -Activity 'Đọc audit log' -Status ('{0:yyyy-MM-dd} → {1:yyyy-MM-dd}' -f $windowStart, $windowEnd)
        $sessionId = [guid]::NewGuid().ToString()
        while ($true) {
            $page = @(Invoke-SPCWithRetry {
                    Search-UnifiedAuditLog -StartDate $windowStart -EndDate $windowEnd -RecordType SharePointFileOperation `
                        -Operations $operations -SessionId $sessionId -SessionCommand ReturnLargeSet -ResultSize 5000 @extra -ErrorAction Stop
                })
            if ($page.Count -eq 0) { break }
            foreach ($record in $page) {
                $data = $record.AuditData | ConvertFrom-Json
                if (-not $data.ObjectId -or "$($data.SiteUrl)".TrimEnd('/') -ne $site) { continue }
                try {
                    $key = [uri]::UnescapeDataString(([uri]$data.ObjectId).AbsolutePath).ToLowerInvariant()
                    $time = [datetime]::SpecifyKind([datetime]$data.CreationTime, [DateTimeKind]::Utc).ToLocalTime()
                } catch { continue }
                if (-not $map.ContainsKey($key) -or $map[$key] -lt $time) { $map[$key] = $time }
            }
            $last = $page[-1]
            if ($last.ResultCount -ge 50000) {
                Write-Warning ('Khoảng {0:yyyy-MM-dd}→{1:yyyy-MM-dd} có ≥ 50.000 bản ghi, kết quả có thể thiếu. Hãy giảm -WindowDays.' -f $windowStart, $windowEnd)
            }
            if ($null -eq $last.ResultIndex -or $last.ResultIndex -lt 0 -or $last.ResultIndex -ge $last.ResultCount) { break }
        }
        $windowStart = $windowEnd
    }
    Write-Progress -Activity 'Đọc audit log' -Completed
    $map
}
