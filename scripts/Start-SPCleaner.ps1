#Requires -Version 7.4
<#
.SYNOPSIS
Menu tương tác giúp admin dọn dẹp dung lượng SharePoint Online.

.EXAMPLE
pwsh ./scripts/Start-SPCleaner.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\SPCleaner\SPCleaner.psd1') -Force

$state = @{
    Connection   = $null
    Sites        = @()
    SiteUrl      = $null
    VersionFiles = @()
    StaleFiles   = @()
}

#region UI helpers
function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Write-Note([string]$Text, [string]$Color = 'Gray') {
    Write-Host "  $Text" -ForegroundColor $Color
}

function Read-PositiveNumber {
    param([string]$Prompt, [double]$Default = 0, [switch]$Integer, [switch]$AllowZero)
    $hasDefault = $PSBoundParameters.ContainsKey('Default')
    $hint = if ($hasDefault) { " [mặc định $Default]" } else { '' }
    while ($true) {
        $raw = (Read-Host "$Prompt$hint").Trim()
        if (-not $raw -and $hasDefault) { return $Default }
        $value = 0.0
        $ok = [double]::TryParse($raw.Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)
        if ($ok -and ($value -gt 0 -or ($AllowZero -and $value -eq 0)) -and (-not $Integer -or $value -eq [math]::Floor($value))) {
            if ($Integer) { return [int]$value } else { return $value }
        }
        Write-Note 'Giá trị không hợp lệ.' Yellow
    }
}

function Read-PastDate {
    param([string]$Prompt, [switch]$Optional)
    $formats = [string[]]@('dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd')
    while ($true) {
        $raw = (Read-Host "$Prompt (dd/MM/yyyy hoặc yyyy-MM-dd$(if ($Optional) { ', Enter để bỏ qua' }))").Trim()
        if (-not $raw -and $Optional) { return $null }
        $date = [datetime]::MinValue
        if ([datetime]::TryParseExact($raw, $formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$date)) {
            if ($date -lt (Get-Date).Date) { return $date }
            Write-Note 'Ngày phải ở quá khứ.' Yellow
        } else {
            Write-Note 'Sai định dạng ngày.' Yellow
        }
    }
}

function Read-YesNo([string]$Prompt, [bool]$Default = $false) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $raw = (Read-Host "$Prompt $hint").Trim()
    if (-not $raw) { return $Default }
    $raw -match '^(y|yes|c|co|có)$'
}

function Read-Choice([string]$Prompt, [string[]]$Allowed) {
    while ($true) {
        $raw = (Read-Host $Prompt).Trim()
        if ($raw -in $Allowed) { return $raw }
        Write-Note "Chọn một trong: $($Allowed -join ', ')" Yellow
    }
}

function Format-Size([double]$Bytes) {
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) { $Bytes /= 1024; $i++ }
    '{0:N2} {1}' -f $Bytes, $units[$i]
}

function Show-Table {
    param([object[]]$Items, [object[]]$Property, [int]$Limit = 30)
    if (-not $Items -or $Items.Count -eq 0) { Write-Note 'Không có kết quả.' Yellow; return }
    $i = 0
    $rows = $Items | Select-Object -First $Limit | ForEach-Object {
        $i++
        $_ | Select-Object -Property (@(@{ Name = '#'; Expression = { $i } }) + $Property)
    }
    $rows | Format-Table -AutoSize -Wrap | Out-Host
    if ($Items.Count -gt $Limit) { Write-Note "… chỉ hiển thị $Limit/$($Items.Count) dòng. Xuất CSV để xem đầy đủ." }
}

function Show-Summary([object[]]$Items, [string]$SizeProperty = 'SizeBytes', [string]$Label = 'file') {
    $total = ($Items | Measure-Object -Property $SizeProperty -Sum).Sum
    Write-Host ("  Tổng: {0} {1}, {2}" -f $Items.Count, $Label, (Format-Size $total)) -ForegroundColor Green
}

function Invoke-OptionalExport([object[]]$Items, [string]$Name) {
    if ($Items.Count -gt 0 -and (Read-YesNo 'Xuất kết quả ra CSV?')) {
        $Items | Export-SPCReport -Name $Name -NoPassThru
    }
}

function Confirm-Deletion {
    param([int]$Count, [double]$Bytes, [string]$What, [switch]$Permanent)
    Write-Host ''
    Write-Host "  Sắp xoá $Count $What ($(Format-Size $Bytes))." -ForegroundColor Yellow
    if ($Permanent) {
        Write-Host '  CHẾ ĐỘ XOÁ VĨNH VIỄN – KHÔNG THỂ KHÔI PHỤC TỪ RECYCLE BIN.' -ForegroundColor Red
    } else {
        Write-Note 'Dữ liệu sẽ vào Recycle Bin của site (khôi phục được trong 93 ngày).'
    }
    if ((Read-Host '  Gõ XOA để xác nhận') -cne 'XOA') { Write-Note 'Đã huỷ.' Yellow; return $false }
    if ($Permanent -and (Read-Host "  Xác nhận lần 2 – gõ số lượng ($Count)") -ne "$Count") { Write-Note 'Đã huỷ.' Yellow; return $false }
    $true
}

function Assert-Site {
    if (-not $state.SiteUrl) { Select-Site }
    if (-not $state.SiteUrl) { throw 'Chưa chọn site.' }
    Write-Note "Site: $($state.SiteUrl)"
}
#endregion

#region Actions
function Connect-Tenant {
    Write-Title 'Kết nối tenant'
    $params = @{}
    if ($ConfigPath) { $params.ConfigPath = $ConfigPath }
    $state.Connection = Connect-SPCTenant @params
    Write-Note "Đã kết nối $($state.Connection.AdminUrl) với tài khoản $($state.Connection.User)" Green
}

function Select-Site {
    Write-Title 'Chọn site'
    if ($state.Sites.Count -gt 0) {
        Show-Table -Items $state.Sites -Property SiteUrl, UsedGB, PercentUsed -Limit 50
        $raw = (Read-Host 'Nhập số thứ tự trong danh sách hoặc URL site').Trim()
    } else {
        $raw = (Read-Host 'Nhập URL site (https://<tenant>.sharepoint.com/sites/...)').Trim()
    }
    $index = 0
    if ([int]::TryParse($raw, [ref]$index) -and $index -ge 1 -and $index -le $state.Sites.Count) {
        $url = $state.Sites[$index - 1].SiteUrl
    } elseif ($raw -match '^https://[\w-]+(-my)?\.sharepoint\.com(/|$)') {
        $url = $raw.TrimEnd('/')
    } else {
        Write-Note 'Lựa chọn không hợp lệ.' Yellow
        return
    }
    if ($url -ne $state.SiteUrl) {
        $state.SiteUrl = $url
        $state.VersionFiles = @()
        $state.StaleFiles = @()
    }
    Write-Note "Đã chọn: $url" Green
}

function Invoke-LargeSite {
    Write-Title '1. Site có dung lượng lớn'
    $min = Read-PositiveNumber 'Ngưỡng dung lượng (GB)' -Default 25
    $oneDrive = Read-YesNo 'Bao gồm OneDrive cá nhân?'
    $state.Sites = @(Get-SPCLargeSite -MinSizeGB $min -IncludeOneDrive:$oneDrive)
    Show-Table -Items $state.Sites -Property SiteUrl, Title, UsedGB, QuotaGB, PercentUsed, LockState -Limit 50
    Write-Note "Tìm thấy $($state.Sites.Count) site. Số liệu dung lượng có thể trễ 24–48 giờ."
    Invoke-OptionalExport $state.Sites 'large-sites'
    if ($state.Sites.Count -gt 0 -and (Read-YesNo 'Chọn một site để làm việc tiếp?' $true)) { Select-Site }
}

function Invoke-LargeFile {
    Write-Title '2. File dung lượng lớn'
    Assert-Site
    $min = Read-PositiveNumber 'Ngưỡng dung lượng file (MB)' -Default 100
    $top = Read-PositiveNumber 'Số file tối đa hiển thị (0 = tất cả)' -Default 0 -Integer -AllowZero
    $files = @(Get-SPCLargeFile -SiteUrl $state.SiteUrl -MinSizeMB $min -Top $top)
    Show-Table -Items $files -Property FileName, SizeMB, TotalSizeMB, VersionLabel, Modified, Library
    Show-Summary $files
    Invoke-OptionalExport $files 'large-files'
}

function Invoke-DuplicateFile {
    Write-Title '3. File trùng tên và dung lượng'
    Assert-Site
    $files = @(Get-SPCDuplicateFile -SiteUrl $state.SiteUrl)
    $groups = @($files | Group-Object DuplicateGroup)
    Show-Table -Items $files -Property DuplicateGroup, FileName, SizeMB, Modified, IsOldestCopy, FileRef -Limit 40
    $wasted = ($groups | ForEach-Object { $_.Group[0].WastedBytes } | Measure-Object -Sum).Sum
    Write-Host ("  {0} nhóm trùng, {1} file, lãng phí ước tính {2}" -f $groups.Count, $files.Count, (Format-Size $wasted)) -ForegroundColor Green
    Invoke-OptionalExport $files 'duplicate-files'
}

function Invoke-VersionCount {
    Write-Title '4. File có nhiều version'
    Assert-Site
    $min = Read-PositiveNumber 'Liệt kê file có số version lớn hơn' -Default 50 -Integer
    $state.VersionFiles = @(Get-SPCFileByVersionCount -SiteUrl $state.SiteUrl -MinVersionCount $min)
    Show-Table -Items $state.VersionFiles -Property FileName, VersionCount, VersionLabel, OldestVersion, VersionsSizeMB, Library
    Show-Summary $state.VersionFiles -SizeProperty VersionsSizeBytes -Label 'file (dung lượng các version cũ)'
    Invoke-OptionalExport $state.VersionFiles 'version-files'
}

function Invoke-VersionCleanup {
    Write-Title '5. Xoá version cũ'
    Assert-Site
    if ($state.VersionFiles.Count -eq 0) {
        Write-Note 'Chưa có danh sách file nhiều version, chạy chức năng 4 trước.' Yellow
        Invoke-VersionCount
        if ($state.VersionFiles.Count -eq 0) { return }
    }
    Write-Host '  a) Giữ lại K version mới nhất cho TẤT CẢ file trong danh sách'
    Write-Host '  b) Chọn 1 file, xem danh sách version và xoá các version cũ hơn version được chọn'
    Write-Host '  c) Xoá các version có số hiệu nhỏ hơn X (ví dụ 10.0) cho TẤT CẢ file trong danh sách'
    $mode = Read-Choice 'Chọn chế độ (a/b/c)' 'a', 'b', 'c'

    $targets = $state.VersionFiles
    $params = @{}
    switch ($mode) {
        'a' { $params.KeepLatest = Read-PositiveNumber 'Số version giữ lại (tính cả version hiện tại)' -Default 10 -Integer }
        'b' {
            Show-Table -Items $targets -Property FileName, VersionCount, VersionLabel, FileRef -Limit 100
            $n = Read-PositiveNumber 'Số thứ tự file' -Integer
            if ($n -gt $targets.Count) { Write-Note 'Số thứ tự không hợp lệ.' Yellow; return }
            $targets = @($targets[$n - 1])
            $versions = @(Get-SPCFileVersion -SiteUrl $targets[0].SiteUrl -FileRef $targets[0].FileRef)
            if ($versions.Count -eq 0) { Write-Note 'File này không có version lịch sử.' Yellow; return }
            Show-Table -Items $versions -Property VersionLabel, Created, SizeMB -Limit 500
            $labels = @($versions.VersionLabel)
            $label = Read-Choice 'Nhập số hiệu version mốc (các version CŨ HƠN sẽ bị xoá, version mốc được giữ)' $labels
            $params.OlderThanVersion = [version]$label
        }
        'c' {
            while (-not $params.ContainsKey('OlderThanVersion')) {
                $raw = (Read-Host 'Xoá các version nhỏ hơn (ví dụ 10.0)').Trim()
                $parsed = $null
                if ([version]::TryParse($raw, [ref]$parsed)) { $params.OlderThanVersion = $parsed } else { Write-Note 'Sai định dạng (x.y).' Yellow }
            }
        }
    }
    $olderThanDate = Read-PastDate 'Chỉ xoá version tạo trước ngày' -Optional
    if ($olderThanDate) { $params.OlderThanDate = $olderThanDate }
    $permanent = Read-YesNo 'Xoá VĨNH VIỄN (không qua Recycle Bin)?'
    $params.Permanent = $permanent
    $params.MaxFiles = [math]::Max($targets.Count, 1)

    Write-Note 'Chạy thử (WhatIf)…'
    $preview = @($targets | Remove-SPCOldFileVersion @params -WhatIf)
    $planned = @($preview | Where-Object { $_.VersionCount -gt 0 })
    $versionTotal = ($planned | Measure-Object -Property VersionCount -Sum).Sum
    $bytesTotal = ($planned | Measure-Object -Property Bytes -Sum).Sum
    $skipped = @($preview | Where-Object Status -eq 'Skipped')
    if ($skipped.Count) { Write-Note "$($skipped.Count) file bị bỏ qua (check-out / thư viện bảo vệ)." Yellow }
    if (-not $versionTotal) { Write-Note 'Không có version nào cần xoá.' Yellow; return }

    $planned | Export-SPCReport -Name 'version-cleanup-manifest' -NoPassThru
    if (-not (Confirm-Deletion -Count $versionTotal -Bytes $bytesTotal -What "version của $($planned.Count) file" -Permanent:$permanent)) { return }

    $results = @($targets | Remove-SPCOldFileVersion @params -Confirm:$false)
    $results | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
    $done = ($results | Measure-Object -Property VersionCount -Sum).Sum
    $freed = ($results | Measure-Object -Property Bytes -Sum).Sum
    Write-Host ("  Đã xử lý {0} version, giải phóng ước tính {1}. Dung lượng site cập nhật sau 24–48 giờ (và sau khi Recycle Bin được dọn)." -f $done, (Format-Size $freed)) -ForegroundColor Green
    $results | Export-SPCReport -Name 'version-cleanup-result' -NoPassThru
    $state.VersionFiles = @()
}

function Invoke-StaleFile {
    Write-Title '6. File lâu không được truy cập'
    Assert-Site
    $since = Read-PastDate 'Liệt kê file không được truy cập kể từ ngày'
    Write-Host '  Nguồn dữ liệu "truy cập" (SharePoint không lưu ngày truy cập cuối cho từng file):'
    Write-Host '   1) Modified  – ngày sửa cuối (nhanh, mặc định)'
    Write-Host '   2) AuditLog  – Purview audit log, chính xác hơn nhưng chỉ ~180 ngày, cần quyền audit + ExchangeOnlineManagement'
    Write-Host '   3) Analytics – Microsoft Graph item analytics, chậm với site nhiều file'
    $source = @{ '1' = 'Modified'; '2' = 'AuditLog'; '3' = 'Analytics'; '' = 'Modified' }[(Read-Choice 'Chọn (1/2/3, Enter = 1)' '1', '2', '3', '')]
    $state.StaleFiles = @(Get-SPCStaleFile -SiteUrl $state.SiteUrl -NotAccessedSince $since -AccessSource $source)
    Show-Table -Items $state.StaleFiles -Property FileName, SizeMB, Modified, LastAccessed, AccessSource, Library
    Show-Summary $state.StaleFiles
    Invoke-OptionalExport $state.StaleFiles 'stale-files'
}

function Invoke-StaleCleanup {
    Write-Title '7. Xoá file lâu không được truy cập'
    Assert-Site
    if ($state.StaleFiles.Count -eq 0) {
        Write-Note 'Chưa có danh sách file, chạy chức năng 6 trước.' Yellow
        Invoke-StaleFile
        if ($state.StaleFiles.Count -eq 0) { return }
    }
    $targets = $state.StaleFiles
    Show-Summary $targets
    $permanent = Read-YesNo 'Xoá VĨNH VIỄN (không qua Recycle Bin)?'

    Write-Note 'Chạy thử (WhatIf) – kiểm tra lại từng file trên SharePoint…'
    $preview = @($targets | Remove-SPCStaleFile -Permanent:$permanent -MaxItems $targets.Count -WhatIf)
    $preview | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
    $planned = @($preview | Where-Object Status -eq 'WhatIf')
    if ($planned.Count -eq 0) { Write-Note 'Không còn file nào đủ điều kiện xoá.' Yellow; return }
    $plannedRefs = [System.Collections.Generic.HashSet[string]]::new([string[]]$planned.FileRef, [StringComparer]::OrdinalIgnoreCase)
    $toDelete = @($targets | Where-Object { $plannedRefs.Contains($_.FileRef) })

    $toDelete | Export-SPCReport -Name 'stale-delete-manifest' -NoPassThru
    $bytes = ($toDelete | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not (Confirm-Deletion -Count $toDelete.Count -Bytes $bytes -What 'file' -Permanent:$permanent)) { return }

    $results = @($toDelete | Remove-SPCStaleFile -Permanent:$permanent -MaxItems $toDelete.Count -Confirm:$false)
    $results | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
    $freed = ($results | Where-Object Status -in 'Recycled', 'Deleted' | Measure-Object -Property SizeBytes -Sum).Sum
    Write-Host "  Đã xoá, giải phóng ước tính $(Format-Size $freed). Khôi phục bằng mục R (manifest stale-delete-manifest)." -ForegroundColor Green
    $results | Export-SPCReport -Name 'stale-delete-result' -NoPassThru
    $state.StaleFiles = @()
}

function Invoke-Restore {
    Write-Title 'R. Khôi phục từ manifest'
    $path = (Read-Host 'Đường dẫn file manifest CSV').Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Note 'Không tìm thấy file.' Yellow; return }
    if (-not (Read-YesNo 'Khôi phục các file trong manifest từ Recycle Bin?')) { return }
    $results = @(Restore-SPCFromManifest -ManifestPath $path -Confirm:$false)
    $results | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
}
#endregion

function Show-Menu {
    Write-Host ''
    Write-Host '╔══════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host '║          SHAREPOINT CLEANER – Menu chính          ║' -ForegroundColor DarkCyan
    Write-Host '╚══════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
    $who = if ($state.Connection) { "$($state.Connection.TenantName) ($($state.Connection.User))" } else { 'CHƯA KẾT NỐI' }
    Write-Note "Tenant: $who"
    Write-Note "Site:   $(if ($state.SiteUrl) { $state.SiteUrl } else { '(chưa chọn)' })"
    Write-Host ''
    Write-Host '  C. Kết nối tenant            S. Chọn site'
    Write-Host '  1. Site có dung lượng lớn hơn X GB'
    Write-Host '  2. File dung lượng lớn hơn X MB trong site'
    Write-Host '  3. File trùng tên và dung lượng trong site'
    Write-Host '  4. File có nhiều hơn N version'
    Write-Host '  5. Xoá version cũ cho các file ở mục 4'
    Write-Host '  6. File không được truy cập kể từ ngày X'
    Write-Host '  7. Xoá các file ở mục 6'
    Write-Host '  R. Khôi phục từ manifest     0. Thoát'
}

try { Connect-Tenant } catch { Write-Note "Kết nối thất bại: $($_.Exception.Message)" Red }

while ($true) {
    Show-Menu
    $choice = (Read-Host 'Chọn').Trim().ToUpperInvariant()
    if ($choice -eq '0') { break }
    try {
        if ($choice -ne 'C' -and -not $state.Connection) { throw 'Hãy kết nối tenant trước (mục C).' }
        switch ($choice) {
            'C' { Connect-Tenant }
            'S' { Select-Site }
            '1' { Invoke-LargeSite }
            '2' { Invoke-LargeFile }
            '3' { Invoke-DuplicateFile }
            '4' { Invoke-VersionCount }
            '5' { Invoke-VersionCleanup }
            '6' { Invoke-StaleFile }
            '7' { Invoke-StaleCleanup }
            'R' { Invoke-Restore }
            default { Write-Note 'Lựa chọn không hợp lệ.' Yellow }
        }
    } catch {
        Write-Note "Lỗi: $($_.Exception.Message)" Red
    }
}
