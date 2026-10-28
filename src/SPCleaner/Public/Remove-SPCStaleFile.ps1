function Remove-SPCStaleFile {
    <#
    .SYNOPSIS
    (7) Xoá các file tìm được bởi Get-SPCStaleFile (mặc định chuyển vào Recycle Bin).

    .DESCRIPTION
    Trước khi xoá, mỗi file được kiểm tra lại trên SharePoint: bỏ qua nếu không còn tồn tại, đang check-out,
    có retention label, hoặc đã được sửa sau ngưỡng (StaleThreshold / -NotAccessedSince).
    Chỉ xoá vĩnh viễn khi truyền -Permanent. Luôn chạy thử với -WhatIf trước.

    .EXAMPLE
    Get-SPCStaleFile -SiteUrl $site -NotAccessedSince '2023-01-01' | Remove-SPCStaleFile -WhatIf

    .EXAMPLE
    Import-Csv .\reports\20261028-101500-stale-manifest.csv | Remove-SPCStaleFile -MaxItems 5000
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^/')]
        [string]$FileRef,

        [Parameter(ValueFromPipelineByPropertyName)]
        $SizeBytes,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('StaleThreshold')]
        $NotAccessedSince,

        [switch]$Permanent,

        [ValidateRange(1, 10000000)]
        [int]$MaxItems = 1000
    )
    begin {
        Assert-SPCConnected
        $processed = 0
        $isWhatIf = [bool]$WhatIfPreference
        $mode = if ($Permanent) { 'XOÁ VĨNH VIỄN file' } else { 'Chuyển file vào Recycle Bin' }
        $touchedSites = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    process {
        $processed++
        if ($processed -gt $MaxItems) {
            throw "Đã vượt giới hạn -MaxItems $MaxItems. Dừng để an toàn; chạy lại với -MaxItems lớn hơn nếu chắc chắn."
        }
        $threshold = ConvertTo-SPCNullableDate $NotAccessedSince
        $size = ConvertTo-SPCInt64 $SizeBytes
        $result = [ordered]@{ SiteUrl = $SiteUrl; FileRef = $FileRef; Status = $null; SizeBytes = $size; Message = $null }
        $finish = {
            param($Status, $Message, [switch]$Warn)
            $result.Status = $Status
            $result.Message = $Message
            $level = if ($Warn) { 'Warning' } else { 'Info' }
            Write-SPCLog -Level $level -Action DeleteFile -SiteUrl $SiteUrl -Target $FileRef -Detail $mode -SizeBytes $size `
                -Result $Status -Message $Message -WhatIfMode:($Status -eq 'WhatIf')
            [pscustomobject]$result
        }

        if (Test-SPCProtectedPath -FileRef $FileRef) {
            return & $finish 'Skipped' 'File nằm trong thư viện được bảo vệ (Preservation Hold Library).'
        }

        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        try {
            $item = Invoke-SPCWithRetry { Get-PnPFile -Url $FileRef -AsListItem -Connection $conn -ErrorAction Stop }
        } catch {
            if ($_.Exception.Message -match 'not found|does not exist|404|không tồn tại') {
                return & $finish 'NotFound' 'File không còn tồn tại (đã bị xoá hoặc di chuyển).'
            }
            return & $finish 'Failed' $_.Exception.Message -Warn
        }
        if (-not $item) { return & $finish 'NotFound' 'File không còn tồn tại (đã bị xoá hoặc di chuyển).' }

        $fv = $item.FieldValues
        $checkout = Get-SPCUserEmail $fv['CheckoutUser']
        if ($checkout) { return & $finish 'Skipped' "File đang được check-out bởi $checkout" }
        $label = [string]$fv['_ComplianceTag']
        if ($label) { return & $finish 'Skipped' "File có retention label '$label'" }
        $modified = ConvertTo-SPCLocalTime $fv['Modified']
        if ($threshold -and $modified -and $modified -ge $threshold) {
            return & $finish 'Skipped' ('File đã được sửa lúc {0:yyyy-MM-dd HH:mm}, sau ngưỡng {1:yyyy-MM-dd}' -f $modified, $threshold)
        }
        if ($null -eq $size) { $result.SizeBytes = $size = ConvertTo-SPCInt64 $fv['File_x0020_Size'] }

        if ($PSCmdlet.ShouldProcess("$FileRef ($(Format-SPCSize $size))", $mode)) {
            $removeParams = @{ ServerRelativeUrl = $FileRef; Force = $true; Connection = $conn; ErrorAction = 'Stop' }
            if (-not $Permanent) { $removeParams.Recycle = $true }
            try {
                Invoke-SPCWithRetry { Remove-PnPFile @removeParams }
                [void]$touchedSites.Add($SiteUrl)
                $status = if ($Permanent) { 'Deleted' } else { 'Recycled' }
                return & $finish $status $null
            } catch {
                return & $finish 'Failed' $_.Exception.Message -Warn
            }
        } elseif ($isWhatIf) {
            return & $finish 'WhatIf' $null
        }
        & $finish 'Declined' 'Người dùng không xác nhận'
    }
    end {
        foreach ($site in $touchedSites) { Clear-SPCInventoryCache -SiteUrl $site }
    }
}
