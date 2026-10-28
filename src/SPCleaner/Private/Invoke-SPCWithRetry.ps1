function Invoke-SPCWithRetry {
    <#
    .SYNOPSIS
    Runs a script block, retrying with exponential back-off on throttling / transient errors.
    PnP cmdlets already honour Retry-After; this covers Graph, audit log and repeated failures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][scriptblock]$ScriptBlock,
        [ValidateRange(1, 20)][int]$MaxRetries = 5,
        [ValidateRange(0, 600)][int]$BaseDelaySeconds = 5
    )
    for ($attempt = 1; ; $attempt++) {
        try {
            return & $ScriptBlock
        } catch {
            $message = $_.Exception.Message
            $transient = $message -match '\b(429|503|504)\b|throttl|Too many requests|temporarily unavailable|server is busy'
            if (-not $transient -or $attempt -ge $MaxRetries) { throw }
            $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)
            Write-Verbose "Bị giới hạn tốc độ (throttling), thử lại sau $delay giây (lần $attempt/$MaxRetries)."
            Start-Sleep -Seconds $delay
        }
    }
}
