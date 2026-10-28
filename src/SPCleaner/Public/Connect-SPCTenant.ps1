function Connect-SPCTenant {
    <#
    .SYNOPSIS
    Kết nối tới SharePoint admin center và lưu cấu hình xác thực cho các site sau này.

    .DESCRIPTION
    Đọc config/settings.json (mặc định) hoặc nhận tham số trực tiếp. Cần một Entra ID app đã đăng ký
    (Register-PnPEntraIDAppForInteractiveLogin hoặc Register-PnPEntraIDApp).

    .EXAMPLE
    Connect-SPCTenant

    .EXAMPLE
    Connect-SPCTenant -TenantName contoso -ClientId 11111111-2222-3333-4444-555555555555
    #>
    [CmdletBinding(DefaultParameterSetName = 'Config')]
    param(
        [Parameter(ParameterSetName = 'Config')]
        [string]$ConfigPath = (Join-Path $script:SPCRoot 'config/settings.json'),

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [ValidatePattern('^[a-zA-Z0-9-]+$')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'Direct')]
        [guid]$ClientId,

        [Parameter(ParameterSetName = 'Direct')]
        [ValidateSet('Interactive', 'Certificate')]
        [string]$AuthMode = 'Interactive',

        [Parameter(ParameterSetName = 'Direct')]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'Direct')]
        [string]$CertificatePath,

        [securestring]$CertificatePassword
    )

    if (-not (Get-Command Connect-PnPOnline -ErrorAction SilentlyContinue)) {
        throw 'Chưa cài PnP.PowerShell. Chạy: Install-Module PnP.PowerShell -Scope CurrentUser'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Config') {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "Không tìm thấy file cấu hình '$ConfigPath'. Hãy copy config/settings.example.json thành config/settings.json và điền thông tin."
        }
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } else {
        $cfg = [pscustomobject]@{
            TenantName            = $TenantName
            Tenant                = "$TenantName.onmicrosoft.com"
            ClientId              = [string]$ClientId
            AuthMode              = $AuthMode
            CertificateThumbprint = $CertificateThumbprint
            CertificatePath       = $CertificatePath
        }
    }

    foreach ($required in 'TenantName', 'ClientId') {
        if (-not $cfg.$required) { throw "Thiếu '$required' trong cấu hình." }
    }
    if ($cfg.ClientId -eq '00000000-0000-0000-0000-000000000000') {
        throw 'ClientId vẫn là giá trị mẫu. Hãy đăng ký Entra ID app và điền ClientId thật.'
    }
    foreach ($default in @{ AuthMode = 'Interactive' }, @{ Tenant = "$($cfg.TenantName).onmicrosoft.com" }) {
        $name = @($default.Keys)[0]
        if (-not $cfg.PSObject.Properties[$name] -or -not $cfg.$name) {
            $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $default[$name] -Force
        }
    }

    $script:SPCConfig = $cfg
    $script:SPCCertificatePassword = $CertificatePassword
    $script:SPCConnections = @{}
    $script:SPCInventoryCache = @{}
    if ($cfg.PSObject.Properties['ReportFolder'] -and $cfg.ReportFolder) { $script:SPCReportFolder = Resolve-SPCPath $cfg.ReportFolder }
    if ($cfg.PSObject.Properties['LogFolder'] -and $cfg.LogFolder) { $script:SPCLogFolder = Resolve-SPCPath $cfg.LogFolder }

    $adminUrl = "https://$($cfg.TenantName)-admin.sharepoint.com"
    try {
        $script:SPCAdminConnection = Connect-SPCSite -Url $adminUrl
    } catch {
        $script:SPCConfig = $null
        throw "Không kết nối được $adminUrl : $($_.Exception.Message)"
    }

    $script:SPCUser = if ($cfg.AuthMode -eq 'Certificate') {
        "app:$($cfg.ClientId)"
    } else {
        try {
            $user = (Get-PnPWeb -Includes CurrentUser -Connection $script:SPCAdminConnection -ErrorAction Stop).CurrentUser
            if ($user.Email) { $user.Email } else { $user.LoginName }
        } catch { 'unknown' }
    }

    Write-SPCLog -Action Connect -SiteUrl $adminUrl -Result Success -Detail $cfg.AuthMode
    [pscustomobject]@{
        TenantName = $cfg.TenantName
        AdminUrl   = $adminUrl
        AuthMode   = $cfg.AuthMode
        User       = $script:SPCUser
    }
}
