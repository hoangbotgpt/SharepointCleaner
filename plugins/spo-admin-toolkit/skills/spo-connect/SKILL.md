---
name: spo-connect
description: Cách cài đặt PnP.PowerShell, đăng ký Entra ID app, xác thực (interactive / certificate app-only) và quản lý connection tới SharePoint admin center và từng site. Dùng khi viết Connect-SPCTenant, Get-SPCSiteConnection, file config, hoặc khi gặp lỗi đăng nhập/AADSTS/403 Access denied. Triggers - "connect", "đăng nhập", "xác thực", "ClientId", "app registration", "certificate", "Connect-PnPOnline".
---

# Kết nối SharePoint Online bằng PnP.PowerShell

## Cài đặt
```powershell
# Trong pwsh 7.4+
Install-Module PnP.PowerShell -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser   # chỉ khi cần audit log
```

## Đăng ký Entra ID app (bắt buộc từ 09/2024)
App multi-tenant "PnP Management Shell" đã bị gỡ, mỗi tenant phải tự đăng ký app.

**Interactive (admin chạy tay)** – delegated permission:
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'SharepointCleaner' `
    -Tenant contoso.onmicrosoft.com -Interactive
```
Quyền delegated tối thiểu: SharePoint `AllSites.FullControl`; Graph `Sites.Read.All` (nếu dùng analytics). Tài khoản chạy phải là **SharePoint Administrator** (hoặc Global Admin) để đọc `Get-PnPTenantSite`. Lưu ý: admin role KHÔNG tự cho quyền đọc nội dung mọi site khi dùng delegated – nếu bị 403 ở site nào đó, cần thêm admin vào Site Collection Admin hoặc dùng app-only.

**App-only (chạy định kỳ / quét toàn tenant)** – khuyến nghị cho xoá hàng loạt:
```powershell
Register-PnPEntraIDApp -ApplicationName 'SharepointCleaner-AppOnly' -Tenant contoso.onmicrosoft.com `
    -OutPath .\certs -SharePointApplicationPermissions 'Sites.FullControl.All' `
    -GraphApplicationPermissions 'Sites.Read.All' -Interactive
```
App-only với SharePoint **bắt buộc dùng certificate** (client secret không dùng được cho SharePoint REST/CSOM).

## Config (`config/settings.json`, không commit)
```json
{
  "TenantName": "contoso",
  "Tenant": "contoso.onmicrosoft.com",
  "ClientId": "00000000-0000-0000-0000-000000000000",
  "AuthMode": "Interactive",
  "CertificateThumbprint": "",
  "CertificatePath": "",
  "ReportFolder": "reports",
  "LogFolder": "logs"
}
```
`AdminUrl` suy ra: `https://$TenantName-admin.sharepoint.com`.

## Connect-SPCTenant – mẫu
```powershell
function Connect-SPCTenant {
    [CmdletBinding()]
    param([string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\..\config\settings.json'))

    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $script:SPCConfig = $cfg
    $script:SPCConnections = @{}
    $adminUrl = "https://$($cfg.TenantName)-admin.sharepoint.com"

    $script:SPCAdminConnection = New-SPCConnection -Url $adminUrl
    Write-Verbose "Connected to $adminUrl"
}

function New-SPCConnection {   # Private
    param([Parameter(Mandatory)][string]$Url)
    $cfg = $script:SPCConfig
    $common = @{ Url = $Url; ClientId = $cfg.ClientId; ReturnConnection = $true }
    switch ($cfg.AuthMode) {
        'Interactive' { Connect-PnPOnline @common -Interactive }
        'Certificate' { Connect-PnPOnline @common -Tenant $cfg.Tenant -Thumbprint $cfg.CertificateThumbprint }
        default       { throw "AuthMode không hợp lệ: $($cfg.AuthMode)" }
    }
}
```

## Get-SPCSiteConnection – cache theo site
```powershell
function Get-SPCSiteConnection {
    param([Parameter(Mandatory)][string]$SiteUrl)
    if (-not $script:SPCConfig) { throw 'Chưa kết nối. Hãy chạy Connect-SPCTenant trước.' }
    $key = $SiteUrl.TrimEnd('/').ToLowerInvariant()
    if (-not $script:SPCConnections.ContainsKey($key)) {
        $script:SPCConnections[$key] = New-SPCConnection -Url $SiteUrl
    }
    $script:SPCConnections[$key]
}
```
- Với Interactive, token được cache nên mở connection site mới thường không hỏi lại đăng nhập.
- Luôn dùng `-ReturnConnection` và truyền `-Connection` – tránh lỗi "đang chạy nhầm site".

## Lỗi hay gặp
| Lỗi | Nguyên nhân / Cách xử lý |
|---|---|
| `AADSTS700016` / app not found | Sai ClientId hoặc chưa admin consent |
| `403 Forbidden` trên 1 site | Delegated: user không có quyền site → thêm Site Collection Admin (`Set-PnPTenantSite -Owners`) hoặc dùng app-only |
| `Unsupported app only token` | Dùng client secret thay vì certificate |
| `The term 'Connect-PnPOnline' is not recognized` | Đang chạy Windows PowerShell 5.1 → chuyển sang `pwsh` |
