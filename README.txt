STACK PRO SEGURA - WHATSAPP + MISTRAL + EVOLUTION

O que já vem configurado:
- Node-RED acessível só em 127.0.0.1:1880
- Evolution acessível só em 127.0.0.1:8080
- Docs/manager da Evolution desabilitados
- Autenticação obrigatória no editor do Node-RED
- credentialSecret no Node-RED
- Evolution protegida por AUTHENTICATION_API_KEY
- Gateway interno para webhook
- Assinatura HMAC SHA-256 + timestamp entre gateway e Node-RED
- Janela anti-replay configurável para webhook
- Suporte a rotação de segredo atual/anterior
- Memória do bot persistida no Redis
- Mensagens do WhatsApp persistidas pela Evolution no PostgreSQL
- Anti-flood
- Anti-duplicidade
- Fallback humano
- Sem exposição de Redis/Postgres no host

PASSOS
1. Extraia para C:\whatsapp_secure_pro_stack
2. Edite o arquivo .env
3. Preencha:
   - EVOLUTION_API_KEY
   - MISTRAL_API_KEY
   - NODE_RED_ADMIN_PASSWORD
   - WEBHOOK_SECRET
   - WEBHOOK_HMAC_SECRET
4. No terminal dentro da pasta:
   docker compose down -v
   docker compose up -d --build

ACESSO LOCAL
- Node-RED: http://127.0.0.1:1880
- Evolution: http://127.0.0.1:8080

RECOMENDAÇÕES EXTRAS
- Ative BitLocker no Windows para criptografia em repouso
- Rode firewall_hardening.ps1 como administrador
- Use rotação com WEBHOOK_SECRET_PREVIOUS e WEBHOOK_HMAC_SECRET_PREVIOUS
- Troque as chaves expostas anteriormente
