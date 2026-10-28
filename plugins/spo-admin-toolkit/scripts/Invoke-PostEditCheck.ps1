# PostToolUse hook: after Claude writes/edits a PowerShell file:
#  1. adds a UTF-8 BOM when the file has non-ASCII text (Windows PowerShell 5.1 needs it),
#  2. flags forbidden destructive cmdlets and Remove-SPC* functions without ShouldProcess,
#  3. runs PSScriptAnalyzer (via pwsh when available).
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

# 1. Ensure BOM for non-ASCII content
$bytes = [IO.File]::ReadAllBytes($path)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
if (-not $hasBom -and ($bytes | Where-Object { $_ -gt 0x7F } | Select-Object -First 1)) {
    $text = (New-Object Text.UTF8Encoding $false).GetString($bytes)
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $true))
}

$problems = New-Object System.Collections.Generic.List[string]
$lines = @([IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8))

# 2. Forbidden cmdlets
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

# 3. PSScriptAnalyzer
$escaped = $path.Replace("'", "''")
$analyzerScript = "if (Get-Module -ListAvailable PSScriptAnalyzer) { Invoke-ScriptAnalyzer -Path '$escaped' -Settings PSGallery -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost | ForEach-Object { '{0}|{1}|{2}|{3}' -f `$_.Line, `$_.Severity, `$_.RuleName, `$_.Message } }"
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
$findings = if ($pwsh) {
    & $pwsh.Source -NoProfile -NonInteractive -Command $analyzerScript
} else {
    Invoke-Expression $analyzerScript
}
foreach ($f in $findings) {
    $parts = "$f" -split '\|', 4
    if ($parts.Count -eq 4) { $problems.Add("${path}:$($parts[0]): [$($parts[1])] $($parts[2]): $($parts[3])") }
}

if ($problems.Count -gt 0) {
    [Console]::Error.WriteLine("Kiểm tra sau khi sửa file phát hiện vấn đề:`n" + ($problems -join "`n"))
    exit 2
}
exit 0
