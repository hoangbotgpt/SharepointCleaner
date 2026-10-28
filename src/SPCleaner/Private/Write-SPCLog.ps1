function Write-SPCLog {
    <#
    .SYNOPSIS
    Appends one row to logs/<yyyyMMdd>-actions.csv. Also written for -WhatIf runs (WhatIf=True).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info',
        [string]$Action = 'Log',
        [string]$SiteUrl,
        [string]$Target,
        [string]$Detail,
        [Nullable[int64]]$SizeBytes,
        [string]$Result,
        [string]$Message,
        [switch]$WhatIfMode
    )

    $text = (@($Action, $Target, $Result, $Message) | Where-Object { $_ }) -join ' | '
    if ($Level -eq 'Info') { Write-Verbose $text } else { Write-Warning $text }

    try {
        if (-not (Test-Path -LiteralPath $script:SPCLogFolder)) {
            New-Item -ItemType Directory -Path $script:SPCLogFolder -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        $file = Join-Path $script:SPCLogFolder ('{0:yyyyMMdd}-actions.csv' -f (Get-Date))
        [pscustomobject][ordered]@{
            Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
            User      = $script:SPCUser
            Level     = $Level
            Action    = $Action
            SiteUrl   = $SiteUrl
            Target    = $Target
            Detail    = $Detail
            SizeBytes = $SizeBytes
            Result    = $Result
            Message   = $Message
            WhatIf    = [bool]$WhatIfMode
        } | Export-Csv -LiteralPath $file -Append -NoTypeInformation -Encoding utf8BOM -WhatIf:$false -Confirm:$false
    } catch {
        Write-Warning "Không ghi được log: $($_.Exception.Message)"
    }
}
