BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Get-SPCStaleFile' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCSiteConnection { $null }
        Mock -ModuleName SPCleaner Get-SPCFileInventory {
            New-TestFile 'old.docx' -Modified (Get-Date).AddDays(-400)
            New-TestFile 'old-but-read.docx' -Modified (Get-Date).AddDays(-400)
            New-TestFile 'recent.docx' -Modified (Get-Date).AddDays(-5)
        }
    }

    It 'Modified: trả về file sửa lần cuối trước ngày nhập' {
        $since = (Get-Date).AddDays(-30)
        $result = @(Get-SPCStaleFile -SiteUrl $TestSite -NotAccessedSince $since)
        $result.FileName | Should -Be @('old.docx', 'old-but-read.docx')
        $result[0].AccessSource | Should -Be 'Modified'
        $result[0].StaleThreshold | Should -Be $since
    }

    It 'từ chối ngày trong tương lai' {
        { Get-SPCStaleFile -SiteUrl $TestSite -NotAccessedSince (Get-Date).AddDays(1) } | Should -Throw '*quá khứ*'
    }

    It 'AuditLog: file có truy cập sau ngưỡng không bị coi là stale' {
        Mock -ModuleName SPCleaner Get-SPCAuditLastAccess {
            @{ '/sites/a/shared documents/old-but-read.docx' = (Get-Date).AddDays(-3) }
        }
        $result = @(Get-SPCStaleFile -SiteUrl $TestSite -NotAccessedSince (Get-Date).AddDays(-30) -AccessSource AuditLog)
        $result.FileName | Should -Be 'old.docx'
        $result.AccessSource | Should -Be 'AuditLog'
    }

    It 'AuditLog: ngưỡng cũ hơn thời gian lưu audit → cảnh báo và đánh dấu partial' {
        Mock -ModuleName SPCleaner Get-SPCAuditLastAccess { @{} }
        $result = @(Get-SPCStaleFile -SiteUrl $TestSite -NotAccessedSince (Get-Date).AddDays(-300) -AccessSource AuditLog -WarningVariable warn -WarningAction SilentlyContinue)
        $result[0].AccessSource | Should -Be 'AuditLog-partial'
        $warn | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName SPCleaner Get-SPCAuditLastAccess -ParameterFilter { $StartDate -ge (Get-Date).Date.AddDays(-180) }
    }
}

Describe 'Get-SPCAuditLastAccess' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Search-UnifiedAuditLog {
            foreach ($r in @(
                    @{ SiteUrl = 'https://contoso.sharepoint.com/sites/a/'; ObjectId = 'https://contoso.sharepoint.com/sites/a/Shared Documents/x.docx'; CreationTime = '2026-01-01T10:00:00' }
                    @{ SiteUrl = 'https://contoso.sharepoint.com/sites/a/'; ObjectId = 'https://contoso.sharepoint.com/sites/a/Shared%20Documents/x.docx'; CreationTime = '2026-01-02T10:00:00' }
                    @{ SiteUrl = 'https://contoso.sharepoint.com/sites/other/'; ObjectId = 'https://contoso.sharepoint.com/sites/other/Shared Documents/y.docx'; CreationTime = '2026-01-03T10:00:00' }
                )) { [pscustomobject]@{ AuditData = ($r | ConvertTo-Json) } }
        }
    }

    It 'lấy thời điểm truy cập mới nhất theo đường dẫn, chỉ của site được chọn' {
        $map = InModuleScope SPCleaner {
            Get-SPCAuditLastAccess -SiteUrl 'https://contoso.sharepoint.com/sites/a' -StartDate (Get-Date).AddDays(-3)
        }
        $map.Keys | Should -Be '/sites/a/shared documents/x.docx'
        $expected = [datetime]::SpecifyKind([datetime]'2026-01-02T10:00:00', 'Utc').ToLocalTime()
        $map['/sites/a/shared documents/x.docx'] | Should -Be $expected
    }
}

Describe 'Remove-SPCStaleFile' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCSiteConnection { $null }
        $script:fieldValues = @{ Modified = (Get-Date).AddDays(-400); CheckoutUser = $null; _ComplianceTag = ''; File_x0020_Size = '2048' }
        Mock -ModuleName SPCleaner Get-PnPFile { [pscustomobject]@{ FieldValues = $script:fieldValues } }
        Mock -ModuleName SPCleaner Remove-PnPFile { }
        $script:target = [pscustomobject]@{
            SiteUrl = $TestSite; FileRef = '/sites/a/Shared Documents/old.docx'; SizeBytes = 2048; StaleThreshold = (Get-Date).AddDays(-30)
        }
    }

    It '-WhatIf không xoá gì' {
        ($script:target | Remove-SPCStaleFile -WhatIf).Status | Should -Be 'WhatIf'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 0
    }

    It 'mặc định chuyển vào Recycle Bin' {
        ($script:target | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'Recycled'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 1 -Exactly -ParameterFilter { $Recycle -eq $true -and $ServerRelativeUrl -eq '/sites/a/Shared Documents/old.docx' }
    }

    It '-Permanent không truyền -Recycle' {
        ($script:target | Remove-SPCStaleFile -Permanent -Confirm:$false).Status | Should -Be 'Deleted'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 0 -ParameterFilter { $Recycle -eq $true }
    }

    It 'bỏ qua file đã được sửa sau ngưỡng (kiểm tra lại trước khi xoá)' {
        $script:fieldValues.Modified = (Get-Date).AddDays(-1)
        ($script:target | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 0
    }

    It 'bỏ qua file có retention label hoặc đang check-out' {
        $script:fieldValues._ComplianceTag = 'Keep 7 years'
        ($script:target | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'Skipped'
        $script:fieldValues._ComplianceTag = ''
        $script:fieldValues.CheckoutUser = [pscustomobject]@{ Email = 'x@contoso.com' }
        ($script:target | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 0
    }

    It 'file không còn tồn tại → NotFound' {
        Mock -ModuleName SPCleaner Get-PnPFile { throw 'File Not Found.' }
        ($script:target | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'NotFound'
    }

    It 'dừng khi vượt -MaxItems' {
        { @($script:target, $script:target) | Remove-SPCStaleFile -MaxItems 1 -Confirm:$false } | Should -Throw '*MaxItems*'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 1 -Exactly
    }

    It 'nhận lại được manifest CSV (ngày ISO) qua Import-Csv' {
        $script:target | Export-SPCReport -Name manifest -NoPassThru -InformationAction SilentlyContinue
        $csv = Get-ChildItem (Join-Path $TestDrive 'reports') -Filter '*-manifest.csv' | Select-Object -First 1
        $script:fieldValues.Modified = (Get-Date).AddDays(-10)   # sửa sau ngưỡng (-30 ngày) → phải bị bỏ qua
        (Import-Csv $csv.FullName | Remove-SPCStaleFile -Confirm:$false).Status | Should -Be 'Skipped'
    }
}
