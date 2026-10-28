# PostToolUse hook: after Claude writes/edits a PowerShell file, flag forbidden
# destructive cmdlets and run PSScriptAnalyzer (if installed).
# Exit 2 + stderr => feedback is shown to Claude so it can fix the file.
# Runs on Windows PowerShell 5.1 and pwsh 7.

$ErrorActionPreference = 'Stop'
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    exit 0
}

$path = $payload.tool_input.file_path
if (-not $path -or $path -notmatch '\.(ps1|psm1|psd1)$' -or -not (Test-Path -LiteralPath $path)) { exit 0 }
# Don't lint the plugin's own tooling
if ($path -match '[\\/]plugins[\\/]spo-admin-toolkit[\\/]') { exit 0 }

$problems = New-Object System.Collections.Generic.List[string]
$lines = @(Get-Content -LiteralPath $path)

$forbidden = @(
    'Clear-PnPRecycleBinItem', 'Clear-PnPTenantRecycleBinItem', 'Remove-PnPTenantSite',
    'Remove-PnPList', 'Remove-SPOSite', 'Remove-SPODeletedSite'
)
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s*#') { continue }
    foreach ($cmd in $forbidden) {
        if ($line -match "\b$([regex]::Escape($cmd))\b") {
            $problems.Add("${path}:$($i + 1): cmdlet bị cấm theo skill spo-safe-delete: $cmd")
        }
    }
    if ($line -match '\bRemove-PnPFileVersion\b.*\s-All\b') {
        $problems.Add("${path}:$($i + 1): Remove-PnPFileVersion -All bị cấm (xoá toàn bộ version).")
    }
}

$content = $lines -join "`n"
if ($content -match '\bfunction\s+Remove-SPC\w+' -and $content -notmatch 'SupportsShouldProcess') {
    $problems.Add("${path}: function Remove-SPC* thiếu [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')].")
}

if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    Import-Module PSScriptAnalyzer
    $results = Invoke-ScriptAnalyzer -Path $path -Severity Warning, Error -ExcludeRule PSAvoidUsingWriteHost
    foreach ($r in $results) {
        $problems.Add("${path}:$($r.Line): [$($r.Severity)] $($r.RuleName): $($r.Message)")
    }
}

if ($problems.Count -gt 0) {
    [Console]::Error.WriteLine("Kiểm tra sau khi sửa file phát hiện vấn đề:`n" + ($problems -join "`n"))
    exit 2
}
exit 0
