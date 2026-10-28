---
name: spo-file-inventory
description: Quét toàn bộ file trong các document library của một site SharePoint Online một cách hiệu quả (paging, field tối thiểu, cache), rồi dùng để liệt kê file dung lượng lớn và file trùng (cùng tên và cùng dung lượng). Dùng khi viết Get-SPCFileInventory, Get-SPCLargeFile, Get-SPCDuplicateFile, chức năng 2 và 3 của menu. Triggers - "file lớn", "large files", "file trùng", "duplicate", "Get-PnPListItem", "quét site", "inventory".
---

# Inventory file của site (nền tảng cho chức năng 2, 3, 4, 6)

## Chọn thư viện
```powershell
$lists = Get-PnPList -Connection $conn -Includes RootFolder.ServerRelativeUrl, EnableMinorVersions |
    Where-Object { $_.BaseTemplate -eq 101 -and ($IncludeSystemLibraries -or -not $_.Hidden) -and $_.ItemCount -gt 0 }
```
- `BaseTemplate 101` = Document Library. Mặc định bỏ qua thư viện ẩn (gồm `Preservation Hold Library`) – **không bao giờ xoá trong Preservation Hold Library**.
- Mặc định loại thêm các thư viện hệ thống không ẩn: `Form Templates`, `Style Library`, `Site Assets`, `Site Pages` (trừ khi `-IncludeSystemLibraries`).

## Lấy item hiệu quả
```powershell
$fields = 'FileLeafRef','FileRef','File_x0020_Size','SMTotalSize','_UIVersionString',
          'Modified','Editor','FSObjType','UniqueId','_CheckinComment','CheckoutUser'

Get-PnPListItem -List $list -PageSize 2000 -Fields $fields -Connection $conn |
    Where-Object { $_.FieldValues.FSObjType -eq 0 } |      # 0 = file, 1 = folder
    ForEach-Object {
        $fv = $_.FieldValues
        $size = [int64]$fv.File_x0020_Size
        [pscustomobject]@{
            SiteUrl        = $SiteUrl
            Library        = $list.Title
            FileName       = $fv.FileLeafRef
            FileRef        = $fv.FileRef
            UniqueId       = $fv.UniqueId
            SizeBytes      = $size
            TotalSizeBytes = if ($fv.SMTotalSize) { [int64]$fv.SMTotalSize.LookupId } else { $null }
            SizeMB         = [math]::Round($size / 1MB, 2)
            VersionLabel   = $fv._UIVersionString
            Modified       = [datetime]$fv.Modified
            ModifiedBy     = $fv.Editor.Email
            CheckedOutTo   = $fv.CheckoutUser.Email
            MinorVersions  = $list.EnableMinorVersions
        }
    }
```
Ghi chú kỹ thuật:
- `-PageSize 2000` tránh lỗi **List View Threshold (5000)**; không dùng CAML `<Where>` trên field không index cho list lớn.
- `File_x0020_Size` trả về dạng string → cast `[int64]`.
- `SMTotalSize` là lookup field (giá trị nằm trong `.LookupId`) = tổng dung lượng file **bao gồm các version**. Nếu tenant trả null thì để `$null`, không fail. Hãy kiểm chứng trên tenant thật một lần khi phát triển.
- Hiển thị `Write-Progress` theo thư viện và số item đã quét.
- Cache: `$script:InventoryCache[$SiteUrl] = $result`; tham số `-Refresh` để quét lại.

## Chức năng 2 – File dung lượng lớn
```powershell
Get-SPCFileInventory -SiteUrl $SiteUrl |
    Where-Object SizeBytes -ge ($MinSizeMB * 1MB) |
    Sort-Object SizeBytes -Descending |
    Select-Object -First $Top     # $Top mặc định 0 = không giới hạn
```
Gợi ý thêm cột `VersionsOverheadMB = (TotalSizeBytes - SizeBytes)/1MB` – giúp admin thấy file nào tốn chỗ vì version (liên kết với chức năng 4–5).

## Chức năng 3 – File trùng tên VÀ dung lượng
Định nghĩa theo yêu cầu: **cùng `FileName` (không phân biệt hoa thường) và cùng `SizeBytes` chính xác**, nằm ở vị trí khác nhau trong site.
```powershell
$inventory = Get-SPCFileInventory -SiteUrl $SiteUrl
$groupId = 0
$inventory |
    Where-Object SizeBytes -gt 0 |
    Group-Object -Property { $_.FileName.ToLowerInvariant() }, SizeBytes |
    Where-Object Count -gt 1 |
    Sort-Object { $_.Group[0].SizeBytes * ($_.Count - 1) } -Descending |
    ForEach-Object {
        $groupId++
        $sorted = $_.Group | Sort-Object Modified     # bản cũ nhất đứng đầu
        $i = 0
        foreach ($f in $sorted) {
            $f | Add-Member -NotePropertyMembers @{
                DuplicateGroup = $groupId
                DuplicateCount = $_.Count
                IsOldestCopy   = ($i -eq 0)
                WastedMB       = [math]::Round($f.SizeBytes * ($_.Count - 1) / 1MB, 2)
            } -PassThru -Force
            $i++
        }
    }
```
- Output phẳng (mỗi dòng 1 file, có `DuplicateGroup`) để Excel lọc dễ.
- Tóm tắt cuối: số nhóm trùng, tổng dung lượng lãng phí = Σ size × (count − 1).
- Tuỳ chọn `-CompareHash`: tải và so SHA256 chỉ trong từng nhóm ứng viên để chắc chắn nội dung giống nhau (chậm; mặc định tắt). Không tự động xoá file trùng – chức năng này chỉ liệt kê.

## Hiệu năng & giới hạn
- Site > 500k file: cảnh báo thời gian chạy, khuyến nghị app-only và chạy ngoài giờ.
- Lỗi throttling: PnP tự retry; nếu vẫn lỗi, log thư viện bị lỗi và tiếp tục thư viện khác (không dừng cả site).
