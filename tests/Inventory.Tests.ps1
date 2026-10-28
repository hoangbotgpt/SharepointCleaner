BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    function New-TestList([string]$Title, [string]$Folder, [int]$Template = 101, [bool]$Hidden = $false, [int]$Count = 3) {
        [pscustomobject]@{
            Id = [guid]::NewGuid(); Title = $Title; BaseTemplate = $Template; Hidden = $Hidden; ItemCount = $Count
            EnableMinorVersions = $false
            RootFolder = [pscustomobject]@{ Name = $Folder; ServerRelativeUrl = "/sites/a/$Folder" }
        }
    }
    function New-TestItem([string]$Name, [int]$FsObjType = 0, [string]$Size = '2048') {
        [pscustomobject]@{
            Id          = 7
            FieldValues = @{
                FileLeafRef      = $Name
                FileRef          = "/sites/a/Shared Documents/$Name"
                File_x0020_Size  = $Size
                SMTotalSize      = [pscustomobject]@{ LookupId = 4096; LookupValue = '4096' }
                _UIVersionString = '3.0'
                Modified         = [datetime]::SpecifyKind([datetime]'2024-01-15T08:00:00', 'Utc')
                Editor           = [pscustomobject]@{ Email = 'editor@contoso.com'; LookupValue = 'Editor' }
                FSObjType        = $FsObjType
                UniqueId         = [guid]::NewGuid()
                CheckoutUser     = $null
                _ComplianceTag   = ''
            }
        }
    }
}

Describe 'Get-SPCFileInventory' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCSiteConnection { $null }
        Mock -ModuleName SPCleaner Get-PnPList {
            New-TestList 'Documents' 'Shared Documents'
            New-TestList 'Site Assets' 'SiteAssets'
            New-TestList 'Preservation Hold Library' 'PreservationHoldLibrary' -Hidden $true
            New-TestList 'Tasks' 'Tasks' -Template 107
            New-TestList 'Empty' 'Empty' -Count 0
        }
        Mock -ModuleName SPCleaner Get-PnPListItem {
            New-TestItem 'a.docx'
            New-TestItem 'Folder' -FsObjType 1
            New-TestItem 'b.pdf' -Size '10485760'
        }
    }

    It 'chỉ quét document library của người dùng, bỏ qua thư mục' {
        $result = InModuleScope SPCleaner { @(Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a') }
        $result.Count | Should -Be 2
        $result.FileName | Should -Be @('a.docx', 'b.pdf')
        Should -Invoke -ModuleName SPCleaner Get-PnPListItem -Times 1 -Exactly
    }

    It 'chuyển đổi field sang đúng kiểu' {
        $file = InModuleScope SPCleaner { Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a' | Select-Object -Last 1 }
        $file.SizeBytes | Should -BeOfType [int64]
        $file.SizeBytes | Should -Be 10485760
        $file.SizeMB | Should -Be 10
        $file.TotalSizeBytes | Should -Be 4096
        $file.ModifiedBy | Should -Be 'editor@contoso.com'
        $file.Modified.Kind | Should -Be 'Local'
        $file.LibraryUrl | Should -Be '/sites/a/Shared Documents'
        $file.MinorVersionsEnabled | Should -BeFalse
    }

    It 'IncludeSystemLibraries thêm thư viện hệ thống nhưng không bao giờ quét Preservation Hold Library' {
        InModuleScope SPCleaner { Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a' -IncludeSystemLibraries } | Out-Null
        Should -Invoke -ModuleName SPCleaner Get-PnPListItem -Times 2 -Exactly
    }

    It 'dùng cache trong phiên, -Refresh quét lại' {
        InModuleScope SPCleaner {
            Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a' | Out-Null
            Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a/' | Out-Null
        }
        Should -Invoke -ModuleName SPCleaner Get-PnPList -Times 1 -Exactly
        InModuleScope SPCleaner { Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a' -Refresh } | Out-Null
        Should -Invoke -ModuleName SPCleaner Get-PnPList -Times 2 -Exactly
    }

    It 'lỗi ở một thư viện không làm dừng cả site' {
        Mock -ModuleName SPCleaner Get-PnPListItem { throw 'Access denied' }
        $result = InModuleScope SPCleaner { @(Get-SPCFileInventory -SiteUrl 'https://contoso.sharepoint.com/sites/a' -WarningAction SilentlyContinue) }
        $result.Count | Should -Be 0
        Join-Path $TestDrive 'logs' | Get-ChildItem | Get-Content -Raw | Should -Match 'Access denied'
    }
}
