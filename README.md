# flowpluss

Stack local para automação WhatsApp com Evolution API, Node-RED, Redis e PostgreSQL.

## Endurecimento de autenticação aplicado

A revisão desta versão removeu a confiança direta do Node-RED em um token de query string e introduziu uma camada formal de autenticação entre serviços:

- **Node-RED admin** continua exigindo autenticação por credenciais, com senha armazenada em hash bcrypt.
- **Evolution API** continua protegida por `AUTHENTICATION_API_KEY`.
- **Webhook Evolution -> Node-RED** agora passa por um **gateway interno**:
  - a Evolution entrega o evento no `webhook-gateway` com o token legado da URL;
  - o gateway valida o token com comparação em tempo constante;
  - o gateway recalcula um resumo canônico do payload e assina a requisição com **HMAC SHA-256 + timestamp**;
  - o Node-RED aceita apenas webhooks com assinatura válida e dentro da janela de tempo configurada.
- **Rotação de segredo**: o gateway e o Node-RED aceitam segredo atual e segredo anterior para facilitar rollout sem downtime.

## O que isso resolve

- reduz a dependência de `query string` dentro da aplicação principal;
- adiciona autenticação máquina-a-máquina com proteção contra replay;
- permite rotação controlada de segredo (`*_PREVIOUS`);
- limita CORS do `httpNode` para origens explícitas;
- endurece o cookie do admin com `httpOnly` e `sameSite=strict`.

## Limitações que continuam válidas

- esta stack ainda é pensada para **ambiente local / rede confiável**, porque Node-RED e Evolution seguem publicados apenas em `127.0.0.1`;
- não foi adicionado login federado, OAuth, refresh token ou JWT de usuário final, porque o sistema atual é predominantemente **server-to-server/local**;
- o token legado na URL continua existindo **somente** na borda Evolution -> gateway, por limitação prática do modo de integração atual. A autenticação efetiva do Node-RED agora é por assinatura HMAC.

## Variáveis novas

Copie `.envexemplo` para `.env` e preencha especialmente:

- `WEBHOOK_SECRET`
- `WEBHOOK_HMAC_SECRET`
- `WEBHOOK_SECRET_PREVIOUS` (opcional, durante rotação)
- `WEBHOOK_HMAC_SECRET_PREVIOUS` (opcional, durante rotação)
- `WEBHOOK_SIGNATURE_MAX_AGE_MS`
- `NODE_RED_ALLOWED_ORIGINS`

## Subida

```bash
docker compose down -v
docker compose up -d --build
```

## Acesso local

- Node-RED: http://127.0.0.1:1880
- Evolution: http://127.0.0.1:8080
