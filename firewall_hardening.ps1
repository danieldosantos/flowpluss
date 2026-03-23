$ErrorActionPreference = 'Stop'

$rules = @(
  @{ DisplayName = 'Block remote Node-RED 1880'; Port = 1880 },
  @{ DisplayName = 'Block remote Evolution 8080'; Port = 8080 }
)

foreach ($rule in $rules) {
  Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

  New-NetFirewallRule `
    -DisplayName $rule.DisplayName `
    -Direction Inbound `
    -Profile Any `
    -Action Block `
    -Protocol TCP `
    -LocalPort $rule.Port | Out-Null

  Write-Host "[OK] Regra aplicada: $($rule.DisplayName)"
}

Write-Host ''
Write-Host 'Firewall hardening aplicado. Confira com:'
Write-Host 'Get-NetFirewallRule -DisplayName "Block remote Node-RED 1880","Block remote Evolution 8080"'
