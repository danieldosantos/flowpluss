$ErrorActionPreference = 'Stop'

function Write-Check {
  param(
    [ValidateSet('PASS', 'FAIL', 'WARN')]
    [string]$Status,
    [string]$Message
  )

  $prefix = switch ($Status) {
    'PASS' { '[PASS]' }
    'FAIL' { '[FAIL]' }
    'WARN' { '[WARN]' }
  }

  Write-Host "$prefix $Message"
}

function Test-LoopbackBinding {
  param([int[]]$Ports)

  $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in $Ports }

  if (-not $listeners) {
    Write-Check WARN 'Nenhum listener encontrado nas portas 1880/8080 neste host.'
    return $true
  }

  $ok = $true
  foreach ($listener in $listeners) {
    $address = [string]$listener.LocalAddress
    $port = [int]$listener.LocalPort
    $allowed = @('127.0.0.1', '::1')

    if ($address -in $allowed) {
      Write-Check PASS "Porta $port ouvindo somente em loopback ($address)."
      continue
    }

    $ok = $false
    Write-Check FAIL "Porta $port ouvindo em $address. Isso permite acesso fora do host."
  }

  return $ok
}

function Test-FirewallRules {
  $expectedNames = @(
    'Block remote Node-RED 1880',
    'Block remote Evolution 8080'
  )

  $ok = $true
  foreach ($name in $expectedNames) {
    $rule = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if (-not $rule) {
      $ok = $false
      Write-Check FAIL "Regra de firewall ausente: $name"
      continue
    }

    $enabled = ($rule | Select-Object -First 1).Enabled
    if ($enabled -ne 'True') {
      $ok = $false
      Write-Check FAIL "Regra de firewall desabilitada: $name"
      continue
    }

    Write-Check PASS "Regra de firewall presente e habilitada: $name"
  }

  return $ok
}

function Test-PortProxy {
  $output = netsh interface portproxy show all
  $matches = $output | Select-String -Pattern '(^|\s)(1880|8080)\s'

  if ($matches) {
    Write-Check FAIL 'Existe portproxy do Windows envolvendo 1880/8080. Revise a publicação externa abaixo:'
    $matches | ForEach-Object { Write-Host $_.Line }
    return $false
  }

  Write-Check PASS 'Nenhum portproxy do Windows encontrado para 1880/8080.'
  return $true
}

function Show-DockerPorts {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Check WARN 'Docker não encontrado no PATH; não foi possível inspecionar containers publicados.'
    return
  }

  Write-Host ''
  Write-Host 'Containers e portas publicadas:'
  docker ps --format 'table {{.Names}}\t{{.Ports}}'
}

if (-not $IsWindows) {
  Write-Check WARN 'Este script foi feito para o host Windows descrito no README. Rode as verificações equivalentes no host real.'
  exit 0
}

Write-Host 'Auditoria de exposição externa do host Windows'
Write-Host '============================================='
Write-Host ''

$bindingOk = Test-LoopbackBinding -Ports @(1880, 8080)
$firewallOk = Test-FirewallRules
$portProxyOk = Test-PortProxy
Show-DockerPorts

Write-Host ''
Write-Host 'Checklist manual adicional:'
Write-Host '- confirmar que nao existe proxy reverso (IIS, Nginx, Caddy, Traefik) publicando 1880/8080;'
Write-Host '- confirmar que nao existe tunel/VPN/publicacao externa (Cloudflare Tunnel, Tailscale Funnel, ngrok, port-forward do roteador);'
Write-Host '- confirmar que o teste foi feito no host final, nao apenas na maquina de desenvolvimento.'
Write-Host ''

if ($bindingOk -and $firewallOk -and $portProxyOk) {
  Write-Check PASS 'Nenhum indicio local de exposicao externa direta foi encontrado.'
  exit 0
}

Write-Check FAIL 'Foram encontrados pontos que precisam de revisao antes de considerar o acesso realmente restrito ao host local.'
exit 1
