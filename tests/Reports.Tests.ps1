BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Get-SPCLargeSite' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-PnPTenantSite {
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/small'; Template = 'STS#3'; StorageUsageCurrent = 512; StorageQuota = 10240 }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/big'; Template = 'GROUP#0'; StorageUsageCurrent = 5120; StorageQuota = 10240 }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/bigger'; Template = 'STS#3'; StorageUsageCurrent = 8192; StorageQuota = 0 }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/search'; Template = 'SRCHCEN#0'; StorageUsageCurrent = 9999; StorageQuota = 10240 }
        }
    }

    It 'trả về site lớn hơn ngưỡng GB, sắp xếp giảm dần, bỏ site hệ thống' {
        $result = @(Get-SPCLargeSite -MinSizeGB 2)
        $result.SiteUrl | Should -Be @('https://contoso.sharepoint.com/sites/bigger', 'https://contoso.sharepoint.com/sites/big')
        $result[1].UsedGB | Should -Be 5
        $result[1].PercentUsed | Should -Be 50
        $result[0].PercentUsed | Should -BeNullOrEmpty
    }

    It 'truyền IncludeOneDriveSites khi được yêu cầu' {
        Get-SPCLargeSite -MinSizeGB 1 -IncludeOneDrive | Out-Null
        Should -Invoke -ModuleName SPCleaner Get-PnPTenantSite -ParameterFilter { $IncludeOneDriveSites } -Times 1 -Exactly
    }

    It 'báo lỗi khi chưa kết nối' {
        InModuleScope SPCleaner { $script:SPCConfig = $null }
        { Get-SPCLargeSite -MinSizeGB 1 } | Should -Throw '*Connect-SPCTenant*'
    }
}

Describe 'Get-SPCLargeFile' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCFileInventory {
            New-TestFile 'small.txt' -SizeBytes 1MB
            New-TestFile 'big.iso' -SizeBytes 800MB
            New-TestFile 'medium.mp4' -SizeBytes 150MB
        }
    }

    It 'lọc theo ngưỡng MB và sắp xếp giảm dần' {
        $result = @(Get-SPCLargeFile -SiteUrl $TestSite -MinSizeMB 100)
        $result.FileName | Should -Be @('big.iso', 'medium.mp4')
    }

    It 'giới hạn số dòng bằng -Top' {
        @(Get-SPCLargeFile -SiteUrl $TestSite -MinSizeMB 0.5 -Top 1).FileName | Should -Be 'big.iso'
    }

    It 'từ chối URL không phải SharePoint Online' {
        { Get-SPCLargeFile -SiteUrl 'https://example.com/sites/a' -MinSizeMB 1 } | Should -Throw
    }
}

Describe 'Get-SPCDuplicateFile' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        $script:inventory = @(
            New-TestFile 'Report.docx' -SizeBytes 100KB -Folder '/sites/a/Shared Documents/x' -Modified '2024-05-01'
            New-TestFile 'REPORT.DOCX' -SizeBytes 100KB -Folder '/sites/a/Shared Documents/y' -Modified '2023-01-01'
            New-TestFile 'Report.docx' -SizeBytes 200KB -Folder '/sites/a/Shared Documents/z'
            New-TestFile 'empty.txt' -SizeBytes 0 -Folder '/sites/a/Shared Documents/p'
            New-TestFile 'empty.txt' -SizeBytes 0 -Folder '/sites/a/Shared Documents/q'
        )
        Mock -ModuleName SPCleaner Get-SPCFileInventory { $script:inventory }
    }

    It 'nhóm theo tên (không phân biệt hoa thường) VÀ dung lượng, bỏ file 0 byte' {
        $result = @(Get-SPCDuplicateFile -SiteUrl $TestSite)
        $result.Count | Should -Be 2
        ($result.DuplicateGroup | Sort-Object -Unique) | Should -Be 1
        $result.FileRef | Should -Not -Contain '/sites/a/Shared Documents/z/Report.docx'
    }

    It 'đánh dấu bản cũ nhất và tính dung lượng lãng phí' {
        $result = @(Get-SPCDuplicateFile -SiteUrl $TestSite)
        ($result | Where-Object IsOldestCopy).FileRef | Should -Be '/sites/a/Shared Documents/y/REPORT.DOCX'
        $result[0].WastedBytes | Should -Be 100KB
    }

    It 'không sửa object trong cache inventory' {
        Get-SPCDuplicateFile -SiteUrl $TestSite | Out-Null
        $script:inventory[0].PSObject.Properties['DuplicateGroup'] | Should -BeNullOrEmpty
    }
}

Describe 'Export-SPCReport' {
    BeforeEach { Initialize-SPCTestState -Root $TestDrive }

    It 'ghi CSV với ngày ISO-8601, mảng nối bằng ";" và chuyển tiếp object' {
        $obj = [pscustomobject]@{ FileRef = '/sites/a/x.docx'; Modified = [datetime]'2024-03-05T14:30:00'; Labels = @('1.0', '2.0') }
        $passed = @($obj | Export-SPCReport -Name 'unit' -InformationAction SilentlyContinue)
        $passed.Count | Should -Be 1
        $csv = Get-ChildItem (Join-Path $TestDrive 'reports') -Filter '*-unit.csv' | Select-Object -First 1
        $row = Import-Csv $csv.FullName
        $row.Modified | Should -Be '2024-03-05T14:30:00'
        $row.Labels | Should -Be '1.0;2.0'
    }

    It 'không tạo file khi không có dữ liệu' {
        @() | Export-SPCReport -Name 'empty' -InformationAction SilentlyContinue
        Get-ChildItem (Join-Path $TestDrive 'reports') -Filter '*-empty.*' | Should -BeNullOrEmpty
    }
}
