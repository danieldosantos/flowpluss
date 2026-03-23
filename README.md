# flowpluss

Stack local para automação WhatsApp com Evolution API, Node-RED, Redis e PostgreSQL.

## Endurecimento de autenticação aplicado

A revisão desta versão removeu a confiança direta do Node-RED em um token de query string e introduziu uma camada formal de autenticação entre serviços:

- **Node-RED admin** continua exigindo autenticação por credenciais, com senha armazenada em hash bcrypt.
- **Login do editor do Node-RED** agora também tem rate limit próprio por IP + usuário no endpoint `/auth/token`, com janela, contador de tentativas e bloqueio temporário configuráveis.
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
- adiciona mitigação de brute force no login do editor do Node-RED;
- endurece o cookie do admin com `httpOnly` e `sameSite=strict`.

## Limitações que continuam válidas

- esta stack ainda é pensada para **ambiente local / rede confiável**, porque Node-RED e Evolution seguem publicados apenas em `127.0.0.1`;
- se o editor do Node-RED for exposto por proxy reverso, túnel, VPN com publicação externa, `portproxy` ou bind fora de loopback, haverá risco de brute force e enumeração de credenciais, então o rate limit de login passa a ser obrigatório como defesa adicional, não substituta de isolamento de rede;
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
- `NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS`
- `NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS`
- `NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS`


## Rate limit de login do Node-RED

O repositório já tinha **anti-flood de mensagens** e **controle de fila da IA**, mas esses mecanismos não protegiam autenticação.

Agora o endpoint de login do editor (`POST /auth/token`) recebe um rate limit dedicado com estas regras padrão:

- **janela**: `15` minutos (`NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS=900000`);
- **máximo de tentativas por IP + usuário**: `5` (`NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS=5`);
- **bloqueio temporário**: `30` minutos (`NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS=1800000`).

Quando o limite é atingido, o Node-RED responde `429 Too Many Requests` com `Retry-After`. Isso reduz a suscetibilidade do editor a brute force caso o ambiente seja exposto além do loopback.

## Subida

```bash
docker compose down -v
docker compose up -d --build
```

## Acesso local

- Node-RED: http://127.0.0.1:1880
- Evolution: http://127.0.0.1:8080

## Revisão do bloqueio de acesso externo

O bind em `127.0.0.1` no `docker-compose.yml` reduz a superfície de exposição, mas **não é evidência suficiente sozinho** de que o serviço está inacessível externamente no host final. A validação correta para este projeto é:

1. **Confirmar o cenário operacional real**: este repositório presume **host Windows local**. Se estiver rodando em VPS, VM, WSL com encaminhamento, servidor com proxy reverso, VPN com funnel/exit node ou qualquer publicação externa, o risco muda.
2. **Confirmar o bind efetivo no host**: as portas publicadas precisam continuar restritas a `127.0.0.1:1880` e `127.0.0.1:8080`.
3. **Confirmar controles fora do Docker**: verificar se o firewall do Windows foi aplicado e se não há `portproxy`, proxy reverso, túnel, NAT/port-forward do roteador ou publicação externa burlando o bind local.
4. **Auditar no host final**: a checagem deve ser feita na máquina onde a stack realmente roda, não apenas no ambiente de desenvolvimento.

### Como validar no Windows

1. Suba a stack normalmente.
2. Rode `firewall_hardening.ps1` como Administrador para garantir as regras de bloqueio remoto.
3. Rode `audit_external_access.ps1` no **host final** para validar:
   - listeners em `1880` e `8080`;
   - presença das regras de firewall;
   - ausência de `netsh interface portproxy`;
   - portas publicadas pelos containers Docker.

Se o script acusar bind fora de loopback, ausência de firewall ou `portproxy`, trate isso como **falha de exposição**. Mesmo com tudo verde, ainda é necessário revisar manualmente proxy reverso, VPN/túnel e port-forward do roteador, porque isso depende da topologia real do ambiente.
