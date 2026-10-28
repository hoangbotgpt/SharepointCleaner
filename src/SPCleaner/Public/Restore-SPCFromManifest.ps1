function Restore-SPCFromManifest {
    <#
    .SYNOPSIS
    Khôi phục từ Recycle Bin các file có trong một file manifest CSV (cột SiteUrl, FileRef).

    .DESCRIPTION
    Chỉ khôi phục được file đã xoá bằng chế độ Recycle Bin và còn trong thời hạn lưu (93 ngày).
    Version đã xoá cần khôi phục thủ công trong Recycle Bin của site.

    .EXAMPLE
    Restore-SPCFromManifest -ManifestPath .\reports\20261028-101500-stale-manifest.csv -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$ManifestPath
    )
    Assert-SPCConnected
    $rows = @(Import-Csv -LiteralPath $ManifestPath | Where-Object { $_.SiteUrl -and $_.FileRef })
    if ($rows.Count -eq 0) { throw "Manifest '$ManifestPath' không có dòng nào với cột SiteUrl và FileRef." }

    foreach ($siteGroup in ($rows | Group-Object -Property SiteUrl)) {
        $siteUrl = $siteGroup.Name
        $conn = Get-SPCSiteConnection -SiteUrl $siteUrl
        $pending = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $siteGroup.Group) { [void]$pending.Add($row.FileRef) }

        $binItems = @(Get-PnPRecycleBinItem -Connection $conn -ErrorAction Stop | Where-Object { "$($_.ItemType)" -eq 'File' })
        foreach ($binItem in $binItems) {
            $ref = '/' + "$($binItem.DirName)".Trim('/') + '/' + $binItem.LeafName
            if (-not $pending.Contains($ref)) { continue }
            [void]$pending.Remove($ref)
            if (-not $PSCmdlet.ShouldProcess($ref, 'Khôi phục từ Recycle Bin')) { continue }
            try {
                Restore-PnPRecycleBinItem -Identity $binItem.Id -Force -Connection $conn -ErrorAction Stop
                Write-SPCLog -Action RestoreFile -SiteUrl $siteUrl -Target $ref -Result Success
                [pscustomobject]@{ SiteUrl = $siteUrl; FileRef = $ref; Status = 'Restored'; Message = $null }
            } catch {
                Write-SPCLog -Level Warning -Action RestoreFile -SiteUrl $siteUrl -Target $ref -Result Failed -Message $_.Exception.Message
                [pscustomobject]@{ SiteUrl = $siteUrl; FileRef = $ref; Status = 'Failed'; Message = $_.Exception.Message }
            }
        }
        foreach ($missing in $pending) {
            [pscustomobject]@{ SiteUrl = $siteUrl; FileRef = $missing; Status = 'NotInRecycleBin'; Message = 'Không tìm thấy trong Recycle Bin' }
        }
    }
}
