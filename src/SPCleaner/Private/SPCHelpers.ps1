# Small pure helpers shared across the module.

function Format-SPCSize {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(ValueFromPipeline)][Nullable[double]]$Bytes)
    process {
        if ($null -eq $Bytes) { return '' }
        $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
        $value = [double]$Bytes
        $i = 0
        while ([math]::Abs($value) -ge 1024 -and $i -lt $units.Count - 1) { $value /= 1024; $i++ }
        '{0:N2} {1}' -f $value, $units[$i]
    }
}

function ConvertTo-SPCLocalTime {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    $date = [datetime]$Value
    if ($date.Kind -eq [DateTimeKind]::Utc) { $date.ToLocalTime() } else { $date }
}

function ConvertTo-SPCNullableDate {
    <# Accepts a datetime, an ISO-8601 string (as written by Export-SPCReport) or empty. #>
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value }
    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeLocal
    if ([datetime]::TryParse("$Value", [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    throw "Không đọc được ngày '$Value'. Dùng định dạng yyyy-MM-dd hoặc yyyy-MM-ddTHH:mm:ss."
}

function ConvertTo-SPCVersion {
    <# Parses a SharePoint version label ("3.0", "2.5"). Returns $null when it cannot be parsed. #>
    [CmdletBinding()]
    param([string]$Label)
    $parsed = $null
    if ($Label -and [version]::TryParse($Label, [ref]$parsed)) { return $parsed }
    $null
}

function Get-SPCUserEmail {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    foreach ($name in 'Email', 'LookupValue') {
        $prop = $Value.PSObject.Properties[$name]
        if ($prop -and $prop.Value) { return [string]$prop.Value }
    }
    $null
}

function Get-SPCPropertyValue {
    <# Reads a property that may not be loaded on a CSOM object without throwing. #>
    [CmdletBinding()]
    param($InputObject, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    # Check the member exists first: PowerShell's intrinsic .Length/.Count would otherwise return 1 for any scalar.
    $property = $InputObject.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    try { $property.Value } catch { $null }
}

function ConvertTo-SPCInt64 {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    $lookupId = Get-SPCPropertyValue -InputObject $Value -Name 'LookupId'
    if ($null -ne $lookupId) { $Value = $lookupId }
    $parsed = [int64]0
    if ([int64]::TryParse("$Value", [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $parsed }
    $null
}

function ConvertTo-SPCExportRow {
    <# Flattens an object for CSV: ISO-8601 dates (culture independent), arrays joined with ';'. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    $row = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $value = $prop.Value
        $row[$prop.Name] = if ($value -is [datetime]) {
            $value.ToString('yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            ($value | ForEach-Object { "$_" }) -join ';'
        } else {
            $value
        }
    }
    [pscustomobject]$row
}

function Copy-SPCObject {
    <# Shallow copy so callers can add members without mutating the inventory cache. #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)]$InputObject)
    process { $InputObject | Select-Object -Property * }
}

function Clear-SPCInventoryCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SiteUrl)
    $prefix = $SiteUrl.TrimEnd('/').ToLowerInvariant() + '|'
    foreach ($key in @($script:SPCInventoryCache.Keys)) {
        if ($key.StartsWith($prefix)) { $script:SPCInventoryCache.Remove($key) }
    }
}

function Test-SPCProtectedPath {
    <# True when the server-relative path is inside a library that must never be modified. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$FileRef)
    foreach ($folder in $script:SPCProtectedLibraryFolders) {
        if ($FileRef -match "/$([regex]::Escape($folder))/") { return $true }
    }
    $false
}

function Resolve-SPCPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    [IO.Path]::GetFullPath((Join-Path $script:SPCRoot $Path))
}
