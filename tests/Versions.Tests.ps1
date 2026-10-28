BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}

Describe 'Get-SPCFileByVersionCount' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCSiteConnection { $null }
        Mock -ModuleName SPCleaner Get-SPCFileInventory {
            New-TestFile 'few.docx' -VersionLabel '3.0'
            New-TestFile 'many.docx' -VersionLabel '120.0'
            New-TestFile 'minor.docx' -VersionLabel '2.5' -MinorVersionsEnabled $true
        }
        Mock -ModuleName SPCleaner Get-PnPFileVersion {
            $count = if ($Url -like '*many.docx') { 119 } else { 2 }
            1..$count | ForEach-Object { New-TestVersion "$_.0" }
        }
    }

    It 'trả về file có số version (gồm version hiện tại) lớn hơn N' {
        $result = @(Get-SPCFileByVersionCount -SiteUrl $TestSite -MinVersionCount 5)
        $result.FileName | Should -Be 'many.docx'
        $result.VersionCount | Should -Be 120
        $result.OldestVersion | Should -Be '1.0'
        $result.VersionsSizeBytes | Should -Be (119 * 1MB)
    }

    It 'không gọi API version cho file chắc chắn ít version (không bật minor version)' {
        Get-SPCFileByVersionCount -SiteUrl $TestSite -MinVersionCount 5 | Out-Null
        Should -Invoke -ModuleName SPCleaner Get-PnPFileVersion -ParameterFilter { $Url -like '*few.docx' } -Times 0 -Exactly
        Should -Invoke -ModuleName SPCleaner Get-PnPFileVersion -ParameterFilter { $Url -like '*minor.docx' } -Times 1 -Exactly
    }
}

Describe 'Remove-SPCOldFileVersion' {
    BeforeEach {
        Initialize-SPCTestState -Root $TestDrive
        Mock -ModuleName SPCleaner Get-SPCSiteConnection { $null }
        # Unsorted on purpose; current version (11.0) is not part of the history.
        Mock -ModuleName SPCleaner Get-PnPFileVersion {
            '3.0', '10.0', '1.0', '9.0', '2.0', '4.0', '5.0', '6.0', '7.0', '8.0' | ForEach-Object {
                New-TestVersion $_ -Created ([datetime]'2024-01-01').AddDays([int]([version]$_).Major)
            }
        }
        Mock -ModuleName SPCleaner Remove-PnPFileVersion { }
        $script:file = [pscustomobject]@{ SiteUrl = $TestSite; FileRef = '/sites/a/Shared Documents/plan.xlsx'; CheckedOutTo = $null }
    }

    It 'KeepLatest giữ đúng K version tính cả version hiện tại' {
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 3 -Confirm:$false
        $r.Status | Should -Be 'Recycled'
        $r.VersionCount | Should -Be 8
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 8 -Exactly
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 0 -ParameterFilter { $Identity.Id -in (10 * 512), (9 * 512) }
    }

    It 'OlderThanVersion so sánh theo số hiệu version, không theo chuỗi (10.0 > 9.0)' {
        $r = $script:file | Remove-SPCOldFileVersion -OlderThanVersion '9.0' -Confirm:$false
        $r.VersionCount | Should -Be 8
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 0 -ParameterFilter { $Identity.Id -eq (10 * 512) }
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 1 -ParameterFilter { $Identity.Id -eq (8 * 512) }
    }

    It 'mặc định luôn truyền -Recycle' {
        $script:file | Remove-SPCOldFileVersion -KeepLatest 9 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 2 -Exactly -ParameterFilter { $Recycle -eq $true }
    }

    It '-Permanent không truyền -Recycle' {
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 9 -Permanent -Confirm:$false
        $r.Status | Should -Be 'Deleted'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 0 -ParameterFilter { $Recycle -eq $true }
    }

    It '-WhatIf không xoá gì nhưng báo cáo số version sẽ xoá' {
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 3 -WhatIf
        $r.Status | Should -Be 'WhatIf'
        $r.VersionCount | Should -Be 8
        $r.Bytes | Should -Be (8 * 1MB)
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 0
        Join-Path $TestDrive 'logs' | Get-ChildItem | Import-Csv | Where-Object WhatIf -eq 'True' | Should -HaveCount 8
    }

    It 'OlderThanDate chỉ xoá version tạo trước ngày chỉ định' {
        # versions n.0 were created on 2024-01-(1+n): only 1.0 (Jan 2) and 2.0 (Jan 3) are before Jan 4
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 1 -OlderThanDate '2024-01-04' -Confirm:$false
        $r.VersionCount | Should -Be 2
    }

    It 'bỏ qua file đang check-out mà không gọi API' {
        $script:file.CheckedOutTo = 'someone@contoso.com'
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 1 -Confirm:$false
        $r.Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName SPCleaner Get-PnPFileVersion -Times 0
    }

    It 'bỏ qua Preservation Hold Library' {
        $script:file.FileRef = '/sites/a/PreservationHoldLibrary/plan.xlsx'
        ($script:file | Remove-SPCOldFileVersion -KeepLatest 1 -Confirm:$false).Status | Should -Be 'Skipped'
        Should -Invoke -ModuleName SPCleaner Remove-PnPFileVersion -Times 0
    }

    It 'lỗi một version không dừng các version còn lại' {
        Mock -ModuleName SPCleaner Remove-PnPFileVersion { throw 'Locked by retention policy' } -ParameterFilter { $Identity.Id -eq 512 }
        $r = $script:file | Remove-SPCOldFileVersion -KeepLatest 3 -Confirm:$false -WarningAction SilentlyContinue
        $r.Status | Should -Be 'Partial'
        $r.VersionsFailed | Should -Be 1
        $r.VersionCount | Should -Be 7
    }

    It 'dừng khi vượt -MaxFiles' {
        $files = 1..3 | ForEach-Object { [pscustomobject]@{ SiteUrl = $TestSite; FileRef = "/sites/a/Shared Documents/f$_.docx" } }
        { $files | Remove-SPCOldFileVersion -KeepLatest 5 -MaxFiles 2 -Confirm:$false } | Should -Throw '*MaxFiles*'
    }
}
