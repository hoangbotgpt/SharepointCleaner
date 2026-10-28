function Connect-SPCSite {
    <#
    .SYNOPSIS
    Opens a PnP connection to one site URL using the auth settings from Connect-SPCTenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url
    )
    Assert-SPCConnected
    $cfg = $script:SPCConfig
    $params = @{
        Url              = $Url
        ClientId         = $cfg.ClientId
        ReturnConnection = $true
        ErrorAction      = 'Stop'
    }
    switch ($cfg.AuthMode) {
        'Interactive' { $params.Interactive = $true }
        'Certificate' {
            $params.Tenant = $cfg.Tenant
            if ($cfg.CertificateThumbprint) {
                $params.Thumbprint = $cfg.CertificateThumbprint
            } elseif ($cfg.CertificatePath) {
                $params.CertificatePath = $cfg.CertificatePath
                if ($script:SPCCertificatePassword) { $params.CertificatePassword = $script:SPCCertificatePassword }
            } else {
                throw 'AuthMode Certificate cần CertificateThumbprint hoặc CertificatePath trong cấu hình.'
            }
        }
        default { throw "AuthMode không hợp lệ: '$($cfg.AuthMode)'. Dùng 'Interactive' hoặc 'Certificate'." }
    }
    Connect-PnPOnline @params
}
