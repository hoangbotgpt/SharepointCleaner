@{
    RootModule           = 'SPCleaner.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'ea022cb3-9815-4ea1-a066-9437d405e808'
    Author               = 'Nguyen Le Hoang'
    Copyright            = '(c) Nguyen Le Hoang. All rights reserved.'
    Description          = 'SharePoint Online storage cleanup tools built on PnP.PowerShell: large sites, large and duplicate files, version cleanup and stale file removal.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Connect-SPCTenant'
        'Get-SPCLargeSite'
        'Get-SPCLargeFile'
        'Get-SPCDuplicateFile'
        'Get-SPCFileByVersionCount'
        'Get-SPCFileVersion'
        'Remove-SPCOldFileVersion'
        'Get-SPCStaleFile'
        'Remove-SPCStaleFile'
        'Restore-SPCFromManifest'
        'Export-SPCReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('SharePoint', 'SharePointOnline', 'PnP', 'M365', 'Storage', 'Cleanup')
            ProjectUri = 'https://github.com/hoangbotgpt/SharepointCleaner'
        }
    }
}
