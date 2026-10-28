function Remove-SPCOldFileVersion {
    <#
    .SYNOPSIS
    (5) Xoá các version cũ của file: cũ hơn một version cụ thể, hoặc chỉ giữ lại K version mới nhất.

    .DESCRIPTION
    Không bao giờ xoá version hiện tại. Mặc định version bị xoá được đưa vào Recycle Bin (-Recycle);
    chỉ xoá vĩnh viễn khi truyền -Permanent. Luôn chạy thử với -WhatIf trước.
    File đang check-out được bỏ qua. Mỗi file trả về một object kết quả.

    .PARAMETER OlderThanVersion
    Xoá mọi version có số hiệu nhỏ hơn giá trị này (ví dụ 5.0 → xoá 1.0 … 4.x, giữ 5.0 trở lên).

    .PARAMETER KeepLatest
    Số version giữ lại cho mỗi file, TÍNH CẢ version hiện tại (KeepLatest 1 = chỉ giữ version hiện tại).

    .PARAMETER OlderThanDate
    Chỉ xoá những version (trong số đã chọn) được tạo trước ngày này.

    .PARAMETER MaxFiles
    Giới hạn an toàn số file xử lý trong một lần chạy.

    .EXAMPLE
    Get-SPCFileByVersionCount -SiteUrl $site -MinVersionCount 100 | Remove-SPCOldFileVersion -KeepLatest 20 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'KeepLatest')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^https://[\w-]+(-my)?\.sharepoint\.com(/|$)')]
        [string]$SiteUrl,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^/')]
        [string]$FileRef,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$CheckedOutTo,

        [Parameter(Mandatory, ParameterSetName = 'OlderThanVersion')]
        [version]$OlderThanVersion,

        [Parameter(Mandatory, ParameterSetName = 'KeepLatest')]
        [ValidateRange(1, 50000)]
        [int]$KeepLatest,

        [datetime]$OlderThanDate,

        [switch]$Permanent,

        [ValidateRange(1, 10000000)]
        [int]$MaxFiles = 1000
    )
    begin {
        Assert-SPCConnected
        $processed = 0
        $isWhatIf = [bool]$WhatIfPreference
        $mode = if ($Permanent) { 'XOÁ VĨNH VIỄN version' } else { 'Chuyển version vào Recycle Bin' }
        $touchedSites = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    process {
        $processed++
        if ($processed -gt $MaxFiles) {
            throw "Đã vượt giới hạn -MaxFiles $MaxFiles. Dừng để an toàn; chạy lại với -MaxFiles lớn hơn nếu chắc chắn."
        }
        $result = [ordered]@{
            SiteUrl        = $SiteUrl
            FileRef        = $FileRef
            Status         = $null
            VersionCount   = 0
            VersionsFailed = 0
            Bytes          = [int64]0
            VersionLabels  = @()
            Message        = $null
        }

        $skipReason = if (Test-SPCProtectedPath -FileRef $FileRef) { 'File nằm trong thư viện được bảo vệ (Preservation Hold Library).' }
        elseif ($CheckedOutTo) { "File đang được check-out bởi $CheckedOutTo" }
        if ($skipReason) {
            $result.Status = 'Skipped'
            $result.Message = $skipReason
            Write-SPCLog -Action DeleteVersion -SiteUrl $SiteUrl -Target $FileRef -Result Skipped -Message $result.Message -WhatIfMode:$isWhatIf
            return [pscustomobject]$result
        }

        $conn = Get-SPCSiteConnection -SiteUrl $SiteUrl
        try {
            $history = @(Get-SPCVersionHistory -FileRef $FileRef -Connection $conn)
        } catch {
            $result.Status = 'Failed'
            $result.Message = $_.Exception.Message
            Write-SPCLog -Level Warning -Action DeleteVersion -SiteUrl $SiteUrl -Target $FileRef -Result Failed -Message $result.Message
            return [pscustomobject]$result
        }

        # Versions with an unparseable label are never deleted.
        $valid = @($history | Where-Object { $null -ne $_.Version })
        $toDelete = switch ($PSCmdlet.ParameterSetName) {
            'OlderThanVersion' { $valid | Where-Object { $_.Version -lt $OlderThanVersion } }
            'KeepLatest' { $valid | Select-Object -Skip ($KeepLatest - 1) }
        }
        if ($PSBoundParameters.ContainsKey('OlderThanDate')) {
            $toDelete = $toDelete | Where-Object { $_.Created -and $_.Created -lt $OlderThanDate }
        }
        $toDelete = @($toDelete)
        if ($toDelete.Count -eq 0) {
            $result.Status = 'NothingToDelete'
            return [pscustomobject]$result
        }

        $declined = 0
        foreach ($version in $toDelete) {
            $target = '{0} (v{1}, {2})' -f $FileRef, $version.VersionLabel, (Format-SPCSize $version.SizeBytes)
            if ($PSCmdlet.ShouldProcess($target, $mode)) {
                $removeParams = @{
                    Url         = $FileRef
                    Identity    = [int]$version.Id
                    Force       = $true
                    Connection  = $conn
                    ErrorAction = 'Stop'
                }
                if (-not $Permanent) { $removeParams.Recycle = $true }
                try {
                    Invoke-SPCWithRetry { Remove-PnPFileVersion @removeParams }
                    $result.VersionCount++
                    $result.Bytes += [int64]$version.SizeBytes
                    $result.VersionLabels += $version.VersionLabel
                    [void]$touchedSites.Add($SiteUrl)
                    Write-SPCLog -Action DeleteVersion -SiteUrl $SiteUrl -Target $FileRef -Detail "v$($version.VersionLabel); $mode" -SizeBytes $version.SizeBytes -Result Success
                } catch {
                    $result.VersionsFailed++
                    Write-SPCLog -Level Warning -Action DeleteVersion -SiteUrl $SiteUrl -Target $FileRef -Detail "v$($version.VersionLabel)" -Result Failed -Message $_.Exception.Message
                }
            } elseif ($isWhatIf) {
                $result.VersionCount++
                $result.Bytes += [int64]$version.SizeBytes
                $result.VersionLabels += $version.VersionLabel
                Write-SPCLog -Action DeleteVersion -SiteUrl $SiteUrl -Target $FileRef -Detail "v$($version.VersionLabel); $mode" -SizeBytes $version.SizeBytes -Result WhatIf -WhatIfMode
            } else {
                $declined++
            }
        }

        $result.Status = if ($isWhatIf) { 'WhatIf' }
        elseif ($result.VersionsFailed -gt 0 -and $result.VersionCount -gt 0) { 'Partial' }
        elseif ($result.VersionsFailed -gt 0) { 'Failed' }
        elseif ($result.VersionCount -gt 0) { if ($Permanent) { 'Deleted' } else { 'Recycled' } }
        else { 'Declined' }
        if ($declined -gt 0) { $result.Message = "Người dùng bỏ qua $declined version" }
        [pscustomobject]$result
    }
    end {
        foreach ($site in $touchedSites) { Clear-SPCInventoryCache -SiteUrl $site }
    }
}
