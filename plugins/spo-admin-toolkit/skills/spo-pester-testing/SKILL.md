---
name: spo-pester-testing
description: Viết unit test Pester 5 cho module SPCleaner mà không cần tenant thật, bằng cách mock các cmdlet PnP.PowerShell và Exchange Online; kèm lint PSScriptAnalyzer. Dùng khi viết/sửa file tests/*.Tests.ps1, khi thêm function mới, hoặc khi được yêu cầu "test", "kiểm thử", "Pester", "mock", "ScriptAnalyzer".
---

# Test module SPCleaner

## Cài đặt (pwsh 7.4+)
```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser
```
Windows có sẵn Pester 3.4 – **không tương thích** cú pháp Pester 5; luôn `Import-Module Pester -MinimumVersion 5.5`.

## Khung test
```powershell
BeforeAll {
    # Stub để mock được ngay cả khi máy chưa cài PnP.PowerShell
    foreach ($c in 'Connect-PnPOnline','Get-PnPTenantSite','Get-PnPList','Get-PnPListItem',
                   'Get-PnPFileVersion','Remove-PnPFileVersion','Remove-PnPFile','Invoke-PnPGraphMethod',
                   'Search-UnifiedAuditLog') {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { New-Item "function:global:$c" -Value { } | Out-Null }
    }
    Import-Module "$PSScriptRoot/../src/SPCleaner/SPCleaner.psd1" -Force
}

Describe 'Get-SPCLargeSite' {
    BeforeEach {
        InModuleScope SPCleaner { $script:SPCAdminConnection = [pscustomobject]@{ Url = 'https://contoso-admin.sharepoint.com' } }
        Mock -ModuleName SPCleaner Get-PnPTenantSite {
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/a'; StorageUsageCurrent = 3072; StorageQuota = 10240 }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/b'; StorageUsageCurrent = 512;  StorageQuota = 10240 }
        }
    }
    It 'chỉ trả về site lớn hơn ngưỡng (GB)' {
        $r = Get-SPCLargeSite -MinSizeGB 2
        $r.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/a'
        $r.UsedGB  | Should -Be 3
    }
}
```

## Test bắt buộc cho function xoá
```powershell
It 'không xoá gì khi -WhatIf' {
    Mock -ModuleName SPCleaner Remove-PnPFile { }
    [pscustomobject]@{ SiteUrl = $site; FileRef = '/sites/a/Shared Documents/x.docx' } | Remove-SPCStaleFile -WhatIf
    Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 0
}
It 'mặc định dùng Recycle Bin' {
    Mock -ModuleName SPCleaner Remove-PnPFile { }
    $obj | Remove-SPCStaleFile -Confirm:$false
    Should -Invoke -ModuleName SPCleaner Remove-PnPFile -Times 1 -ParameterFilter { $Recycle -eq $true }
}
It 'không bao giờ xoá version hiện tại / giữ đúng KeepLatest' { ... }
It 'OlderThanVersion so sánh theo [version] chứ không theo chuỗi ("10.0" > "9.0")' { ... }
It 'tiếp tục lô khi 1 file lỗi và ghi log Failed' { ... }
```

## Test dữ liệu cho file trùng / stale
- Trùng: 2 file cùng tên khác hoa thường + cùng size → 1 nhóm; cùng tên khác size → không trùng; size 0 → bỏ qua.
- Stale: `Modified` cũ nhưng audit log có `FileAccessed` sau ngưỡng → **không** stale.
- Version: thư viện không bật minor version và label `3.0` với ngưỡng 5 → không gọi `Get-PnPFileVersion` (`Should -Invoke -Times 0`).

## Chạy
```powershell
Invoke-Pester -Path ./tests -Output Detailed
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings PSGallery -Severity Warning,Error
```
