# Dot-sourced from BeforeAll in every *.Tests.ps1.
# Real PnP.PowerShell is required (no tenant needed): Pester mocks keep the real parameter types,
# so tests catch wrong argument types (e.g. -List must be Guid/String/List).

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
    throw 'Tests cần PnP.PowerShell: Install-Module PnP.PowerShell -Scope CurrentUser'
}
Import-Module PnP.PowerShell

# Exchange Online cmdlets only exist after Connect-ExchangeOnline: provide stubs with matching parameters.
if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
    function global:Search-UnifiedAuditLog {
        [CmdletBinding()]
        param([datetime]$StartDate, [datetime]$EndDate, [string]$RecordType, [string[]]$Operations,
            [string]$SessionId, [string]$SessionCommand, [int]$ResultSize)
    }
}
if (-not (Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
    function global:Connect-ExchangeOnline { [CmdletBinding()] param([switch]$ShowBanner) }
}

Import-Module (Join-Path $PSScriptRoot '..\src\SPCleaner\SPCleaner.psd1') -Force

$script:TestSite = 'https://contoso.sharepoint.com/sites/a'

function Initialize-SPCTestState {
    param([Parameter(Mandatory)][string]$Root)
    InModuleScope SPCleaner -Parameters @{ Root = $Root } {
        param($Root)
        $script:SPCConfig = [pscustomobject]@{ TenantName = 'contoso'; ClientId = 'test'; AuthMode = 'Interactive' }
        $script:SPCAdminConnection = $null
        $script:SPCConnections = @{}
        $script:SPCInventoryCache = @{}
        $script:SPCLogFolder = Join-Path $Root 'logs'
        $script:SPCReportFolder = Join-Path $Root 'reports'
        $script:SPCUser = 'tester@contoso.com'
    }
}

function New-TestFile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int64]$SizeBytes = 1MB,
        [string]$Folder = '/sites/a/Shared Documents',
        [string]$VersionLabel = '1.0',
        [bool]$MinorVersionsEnabled = $false,
        [datetime]$Modified = (Get-Date).AddDays(-10),
        [string]$CheckedOutTo
    )
    [pscustomobject]@{
        SiteUrl              = $script:TestSite
        Library              = 'Documents'
        LibraryUrl           = '/sites/a/Shared Documents'
        FileName             = $Name
        FileRef              = "$Folder/$Name"
        UniqueId             = [guid]::NewGuid()
        ItemId               = 1
        SizeBytes            = $SizeBytes
        SizeMB               = [math]::Round($SizeBytes / 1MB, 2)
        TotalSizeBytes       = $null
        TotalSizeMB          = $null
        VersionLabel         = $VersionLabel
        MinorVersionsEnabled = $MinorVersionsEnabled
        Modified             = $Modified
        ModifiedBy           = 'user@contoso.com'
        CheckedOutTo         = $CheckedOutTo
        RetentionLabel       = ''
    }
}

function New-TestVersion {
    param([Parameter(Mandatory)][string]$Label, [int64]$Size = 1MB, [datetime]$Created = (Get-Date).AddDays(-30))
    $v = [version]$Label
    [pscustomobject]@{ VersionLabel = $Label; ID = $v.Major * 512 + $v.Minor; Created = $Created; Size = $Size; IsCurrentVersion = $false }
}
