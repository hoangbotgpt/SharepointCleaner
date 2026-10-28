function Get-SPCLargeSite {
    <#
    .SYNOPSIS
    (1) Liệt kê các site có dung lượng sử dụng lớn hơn ngưỡng (GB).

    .DESCRIPTION
    Dùng StorageUsageCurrent của Get-PnPTenantSite (gồm version, recycle bin, preservation hold library).
    Số liệu do SharePoint cập nhật định kỳ, có thể trễ 24–48 giờ.

    .EXAMPLE
    Get-SPCLargeSite -MinSizeGB 50 | Export-SPCReport -Name large-sites
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0.001, 10000000)]
        [double]$MinSizeGB,

        [switch]$IncludeOneDrive,

        [switch]$IncludeSystemSites,

        [string]$UrlFilter
    )
    Assert-SPCConnected

    $systemTemplates = 'SRCHCEN#0', 'SPSMSITEHOST#0', 'APPCATALOG#0', 'REDIRECTSITE#0', 'POINTPUBLISHINGHUB#0',
        'POINTPUBLISHINGTOPIC#0', 'POINTPUBLISHINGPERSONAL#0', 'EDISC#0', 'TENANTADMIN#0'
    $params = @{ Connection = $script:SPCAdminConnection; ErrorAction = 'Stop' }
    if ($IncludeOneDrive) { $params.IncludeOneDriveSites = $true }

    $minMB = $MinSizeGB * 1024
    Get-PnPTenantSite @params |
        Where-Object { [double]$_.StorageUsageCurrent -ge $minMB } |
        Where-Object { $IncludeSystemSites -or $_.Template -notin $systemTemplates } |
        Where-Object { -not $UrlFilter -or $_.Url -like $UrlFilter } |
        Sort-Object -Property { [double]$_.StorageUsageCurrent } -Descending |
        ForEach-Object {
            $quota = [double]$_.StorageQuota
            [pscustomobject]@{
                SiteUrl             = $_.Url
                Title               = $_.Title
                Template            = $_.Template
                UsedGB              = [math]::Round($_.StorageUsageCurrent / 1024, 2)
                QuotaGB             = [math]::Round($quota / 1024, 2)
                PercentUsed         = if ($quota -gt 0) { [math]::Round(100 * $_.StorageUsageCurrent / $quota, 1) } else { $null }
                Owner               = $_.Owner
                LastContentModified = $_.LastContentModifiedDate
                LockState           = $_.LockState
            }
        }
}
