# Module state (reset by Connect-SPCTenant)
$script:SPCRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:SPCConfig = $null
$script:SPCCertificatePassword = $null
$script:SPCAdminConnection = $null
$script:SPCConnections = @{}
$script:SPCInventoryCache = @{}
$script:SPCUser = $null
$script:SPCLogFolder = Join-Path $script:SPCRoot 'logs'
$script:SPCReportFolder = Join-Path $script:SPCRoot 'reports'

# Libraries skipped unless -IncludeSystemLibraries (matched on RootFolder.Name, which is not localized)
$script:SPCSystemLibraryFolders = @(
    'SiteAssets', 'SitePages', 'Style Library', 'FormServerTemplates', '_catalogs',
    'SiteCollectionDocuments', 'SiteCollectionImages', 'Pages', 'Images'
)
# Never scanned, never touched
$script:SPCProtectedLibraryFolders = @('PreservationHoldLibrary')

$script:SPCSiteUrlPattern = '^https://[\w-]+(-my)?\.sharepoint\.com(/|$)'

foreach ($folder in 'Private', 'Public') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1').BaseName
