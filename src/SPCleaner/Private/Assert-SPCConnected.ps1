function Assert-SPCConnected {
    [CmdletBinding()]
    param()
    if (-not $script:SPCConfig) {
        throw 'Chưa kết nối tenant. Hãy chạy Connect-SPCTenant trước.'
    }
}
