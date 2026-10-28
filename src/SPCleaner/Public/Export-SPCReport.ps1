function Export-SPCReport {
    <#
    .SYNOPSIS
    Ghi kết quả ra reports/<yyyyMMdd-HHmmss>-<Name>.csv (và/hoặc .html), đồng thời chuyển tiếp object ra pipeline.

    .DESCRIPTION
    CSV được ghi từng dòng ngay khi nhận (UTF-8 có BOM để Excel hiển thị đúng tiếng Việt), ngày theo ISO-8601
    để có thể Import-Csv rồi pipe vào Remove-SPC* mà không lệ thuộc định dạng ngày của máy.

    .EXAMPLE
    Get-SPCLargeFile -SiteUrl $site -MinSizeMB 100 | Export-SPCReport -Name large-files -Format Both
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidatePattern('^[\w.-]+$')]
        [string]$Name,

        [ValidateSet('Csv', 'Html', 'Both')]
        [string]$Format = 'Csv',

        [string]$Folder = $script:SPCReportFolder,

        [switch]$NoPassThru
    )
    begin {
        if (-not (Test-Path -LiteralPath $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        $basePath = Join-Path $Folder ('{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), $Name)
        $csvPath = "$basePath.csv"
        $htmlRows = [System.Collections.Generic.List[object]]::new()
        $count = 0
    }
    process {
        $row = ConvertTo-SPCExportRow -InputObject $InputObject
        $count++
        if ($Format -ne 'Html') {
            $row | Export-Csv -LiteralPath $csvPath -Append -Force -NoTypeInformation -Encoding utf8BOM -WhatIf:$false -Confirm:$false
        }
        if ($Format -ne 'Csv') { $htmlRows.Add($row) }
        if (-not $NoPassThru) { $InputObject }
    }
    end {
        if ($count -eq 0) {
            Write-Information 'Không có dữ liệu để xuất báo cáo.' -InformationAction Continue
            return
        }
        if ($Format -ne 'Csv') {
            $style = '<style>body{font-family:Segoe UI,Arial,sans-serif;font-size:13px;margin:16px}' +
                'table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:4px 8px;text-align:left}' +
                'th{background:#0f6cbd;color:#fff;position:sticky;top:0}tr:nth-child(even){background:#f5f5f5}</style>'
            $htmlRows | ConvertTo-Html -Title $Name -Head $style -PreContent "<h2>$Name – $count dòng – $(Get-Date -Format 'yyyy-MM-dd HH:mm')</h2>" |
                Set-Content -LiteralPath "$basePath.html" -Encoding utf8BOM -WhatIf:$false -Confirm:$false
        }
        $written = @(if ($Format -ne 'Html') { $csvPath }; if ($Format -ne 'Csv') { "$basePath.html" })
        Write-Information ("Đã xuất báo cáo ($count dòng): " + ($written -join ', ')) -InformationAction Continue
    }
}
