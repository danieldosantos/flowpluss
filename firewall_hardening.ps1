# Execute no PowerShell como Administrador
New-NetFirewallRule -DisplayName "Block remote Node-RED 1880" -Direction Inbound -LocalPort 1880 -Protocol TCP -Action Block
New-NetFirewallRule -DisplayName "Block remote Evolution 8080" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Block
