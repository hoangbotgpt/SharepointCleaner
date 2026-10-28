---
name: spo-stale-files
description: Liệt kê các file SharePoint Online có lần truy cập (hoặc sửa đổi) cuối cùng trước ngày admin nhập, và xoá các file đó. Giải thích các nguồn dữ liệu "last accessed" (Modified, Unified Audit Log, Graph item analytics) và giới hạn của từng nguồn. Dùng khi viết Get-SPCStaleFile, Remove-SPCStaleFile, chức năng 6 và 7 của menu. Triggers - "file lâu không dùng", "last accessed", "ngày truy cập", "stale files", "FileAccessed", "audit log", "xoá file cũ".
---

# Chức năng 6 & 7 – File lâu không truy cập

## Sự thật quan trọng (phải nói rõ với admin)
SharePoint Online **không lưu trường "Last Accessed" cho từng file** như NTFS. Không có field list nào cho biết ngày mở file gần nhất. Vì vậy hỗ trợ 3 nguồn qua tham số `-AccessSource`:

| AccessSource | Dữ liệu | Ưu | Nhược |
|---|---|---|---|
| `Modified` (mặc định) | Field `Modified` trong inventory | Nhanh, không cần quyền thêm | Chỉ là ngày **sửa**, file được đọc thường xuyên vẫn bị coi là "cũ" |
| `AuditLog` | Purview Unified Audit Log: `FileAccessed`, `FileDownloaded`, `FilePreviewed`, `FileModified`, `FileSyncDownloadedFull` | Gần đúng nghĩa "truy cập" nhất | Chỉ lưu **180 ngày** (Audit Standard; Premium lâu hơn), cần quyền *View-Only Audit Logs*, truy vấn chậm, giới hạn 50.000 bản ghi/phiên |
| `Analytics` | Graph `driveItem/getActivitiesByInterval` | Không cần quyền audit | Dữ liệu analytics có thời gian lưu giới hạn, chỉ cho biết theo khoảng (ngày/tuần/tháng), gọi API cho từng file nên chậm |

Quy tắc kết luận "stale" khi dùng AuditLog/Analytics: file bị coi là stale khi **`Modified` < ngày nhập VÀ không có sự kiện truy cập nào sau ngày nhập**. Nếu ngày nhập nằm ngoài cửa sổ lưu trữ (ví dụ cũ hơn 180 ngày với AuditLog) → `Write-Warning` và chỉ dùng được phần dữ liệu có sẵn; ghi `AccessSource` = `Modified+AuditLog(partial)`.

## Get-SPCStaleFile – khung
```powershell
function Get-SPCStaleFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][datetime]$NotAccessedSince,
        [ValidateSet('Modified','AuditLog','Analytics')][string]$AccessSource = 'Modified',
        [string[]]$Library,
        [switch]$Refresh
    )
    if ($NotAccessedSince -gt (Get-Date)) { throw 'Ngày nhập phải ở quá khứ.' }

    $candidates = Get-SPCFileInventory -SiteUrl $SiteUrl -Refresh:$Refresh |
        Where-Object { $_.Modified -lt $NotAccessedSince -and (-not $Library -or $_.Library -in $Library) }

    $lastAccess = switch ($AccessSource) {
        'Modified'  { @{} }
        'AuditLog'  { Get-SPCAuditLastAccess -SiteUrl $SiteUrl -Since $NotAccessedSince }   # hashtable FileRef(lower) -> datetime
        'Analytics' { $null }   # tra từng file bên dưới
    }

    foreach ($f in $candidates) {
        $accessed = switch ($AccessSource) {
            'Modified'  { $f.Modified }
            'AuditLog'  { $lastAccess[$f.FileRef.ToLowerInvariant()] }
            'Analytics' { Get-SPCAnalyticsLastAccess -File $f -Since $NotAccessedSince }
        }
        $effective = @($f.Modified, $accessed) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        if ($effective -lt $NotAccessedSince) {
            $f | Add-Member -NotePropertyMembers @{ LastAccessed = $effective; AccessSource = $AccessSource } -PassThru -Force
        }
    }
}
```

## Audit log (Private: Get-SPCAuditLastAccess)
```powershell
Connect-ExchangeOnline -ShowBanner:$false          # 1 lần/phiên, cần quyền audit
$session = [guid]::NewGuid().ToString()
$ops = 'FileAccessed','FileDownloaded','FilePreviewed','FileModified','FileSyncDownloadedFull','FileAccessedExtended'
$map = @{}
do {
    $page = Search-UnifiedAuditLog -StartDate $Since -EndDate (Get-Date) -RecordType SharePointFileOperation `
        -Operations $ops -SessionId $session -SessionCommand ReturnLargeSet -ResultSize 5000
    foreach ($r in $page) {
        $d = $r.AuditData | ConvertFrom-Json
        if (-not $d.SiteUrl -or -not $d.SiteUrl.TrimEnd('/').Equals($SiteUrl.TrimEnd('/'), 'OrdinalIgnoreCase')) { continue }
        $key = ([uri]$d.ObjectId).AbsolutePath.ToLowerInvariant()  # -> server-relative path, khớp FileRef
        $key = [uri]::UnescapeDataString($key)
        $t = [datetime]$d.CreationTime
        if (-not $map.ContainsKey($key) -or $map[$key] -lt $t) { $map[$key] = $t }
    }
} while ($page.Count -eq 5000)
$map
```
- Giới hạn khung thời gian: `$Since` không được cũ hơn `(Get-Date).AddDays(-180)` (cắt về mốc này + cảnh báo).
- Có thể thu hẹp bằng `-SiteIds <siteGuid>` nếu module hỗ trợ (`(Get-Command Search-UnifiedAuditLog).Parameters.ContainsKey('SiteIds')`).
- Truy vấn khoảng thời gian dài nên chia nhỏ theo tuần để không chạm giới hạn 50.000 bản ghi.

## Graph analytics (Private: Get-SPCAnalyticsLastAccess)
```powershell
$start = $Since.ToString('yyyy-MM-dd'); $end = (Get-Date).ToString('yyyy-MM-dd')
$url = "v1.0/sites/$siteId/drive/items/$itemId/getActivitiesByInterval(startDateTime='$start',endDateTime='$end',interval='week')"
$res = Invoke-PnPGraphMethod -Url $url -Method Get -Connection $conn
($res.value | Where-Object { $_.access.actionCount -gt 0 } | Sort-Object startDateTime -Descending |
    Select-Object -First 1).endDateTime
```
- Cần drive item id: `Invoke-PnPGraphMethod -Url "v1.0/sites/$siteId/drives"` để map Library → driveId, rồi lấy item theo path `drives/$driveId/root:/<relative-path>`.
- Gọi theo lô (Graph `$batch`, tối đa 20 request) để tăng tốc; xử lý 429 bằng `Invoke-SPCWithRetry`.

## Remove-SPCStaleFile (chức năng 7)
```powershell
function Remove-SPCStaleFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$SiteUrl,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$FileRef,
        [Parameter(ValueFromPipelineByPropertyName)][int64]$SizeBytes,
        [switch]$Permanent
    )
    process {
        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        $mode = if ($Permanent) { 'XOÁ VĨNH VIỄN' } else { 'Chuyển vào Recycle Bin' }
        if ($PSCmdlet.ShouldProcess($FileRef, $mode)) {
            try {
                $p = @{ ServerRelativeUrl = $FileRef; Force = $true; Connection = $conn; ErrorAction = 'Stop' }
                if (-not $Permanent) { $p.Recycle = $true }
                Remove-PnPFile @p
                Write-SPCLog -Action DeleteFile -Target $FileRef -SizeBytes $SizeBytes -Result Success -Detail $mode
            } catch {
                Write-SPCLog -Action DeleteFile -Target $FileRef -Result Failed -Message $_.Exception.Message
            }
        }
    }
}
```
- Trước khi xoá: kiểm tra lại `Modified` của file (có thể đã thay đổi sau khi quét) – nếu `Modified` mới hơn ngày ngưỡng thì **bỏ qua**.
- Bỏ qua file đang check-out, file có retention label (`_ComplianceTag` khác rỗng) – log lý do.
- Toàn bộ quy trình xác nhận/manifest/log theo skill **spo-safe-delete**.
