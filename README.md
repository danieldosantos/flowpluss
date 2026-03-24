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
- passa a registrar trilha de auditoria persistente em JSON Lines para login do editor, bloqueios por rate limit, rejeições de assinatura do webhook e eventos de auditoria do próprio Node-RED.

## Limitações que continuam válidas

- esta stack ainda é pensada para **ambiente local / rede confiável**, porque Node-RED e Evolution seguem publicados apenas em `127.0.0.1`;
- se o editor do Node-RED for exposto por proxy reverso, túnel, VPN com publicação externa, `portproxy` ou bind fora de loopback, haverá risco de brute force e enumeração de credenciais, então o rate limit de login passa a ser obrigatório como defesa adicional, não substituta de isolamento de rede;
- não foi adicionado login federado, OAuth, refresh token ou JWT de usuário final, porque o sistema atual é predominantemente **server-to-server/local**;
- o token legado na URL continua existindo **somente** na borda Evolution -> gateway, por limitação prática do modo de integração atual. A autenticação efetiva do Node-RED agora é por assinatura HMAC.
- o gateway também aceita token por `x-webhook-token` ou `Authorization: Bearer`, reduzindo dependência operacional de segredo em query string quando o emissor suportar cabeçalhos.

## Variáveis novas

Copie `.envexemplo` para `.env` e preencha especialmente:

- `WEBHOOK_SECRET`
- `WEBHOOK_HMAC_SECRET`
- `WEBHOOK_SECRET_PREVIOUS` (opcional, durante rotação)
- `WEBHOOK_SECRETS_CSV` (opcional, lista separada por vírgula para múltiplos emissores)
- `WEBHOOK_HMAC_SECRET_PREVIOUS` (opcional, durante rotação)
- `WEBHOOK_SIGNATURE_MAX_AGE_MS`
- `NODE_RED_ALLOWED_ORIGINS`
- `NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS`
- `NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS`
- `NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS`
- `NODE_RED_CONTEXT_STORAGE` (`redis` por padrão; use `memory` só para troubleshooting local)
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`, `REDIS_PASSWORD` (opcional) e `NODE_RED_REDIS_PREFIX`
- `NODE_RED_ADMIN_PASSWORD_MIN_LENGTH`
- `NODE_RED_ADMIN_PASSWORD_ROTATION_DAYS`

## Revisão do processo de senha do admin do Node-RED

A stack passa a falhar na inicialização se houver dúvida operacional sobre a senha efetiva do editor do Node-RED:

- `NODE_RED_ADMIN_PASSWORD` agora é **obrigatória** e não aceita fallback inseguro nem valores-placeholder como `troque-por-uma-senha-unica-e-forte`.
- o hash bcrypt continua sendo gerado no boot, mas a entrada agora é validada antes de gerar `/data/settings.js`.
- `NODE_RED_CREDENTIAL_SECRET` e `NODE_RED_COOKIE_SECRET` também precisam sair de placeholder, para reduzir risco de reaproveitar segredos fracos no mesmo ambiente.
- a política mínima fica explícita por variável de ambiente: `NODE_RED_ADMIN_PASSWORD_MIN_LENGTH` (padrão `12`) e `NODE_RED_ADMIN_PASSWORD_ROTATION_DAYS` (padrão `90`).
- o container grava um arquivo operacional em `/data/security/node-red-admin-auth.json` com usuário, política aplicada e um **fingerprint HMAC truncado** da senha efetiva. Isso permite confirmar qual senha está valendo sem registrar a senha em claro.

### Como confirmar qual senha está valendo de fato

1. confira o valor atual de `NODE_RED_ADMIN_PASSWORD` no `.env` do host;
2. após subir a stack, compare com o fingerprint registrado:

```bash
docker compose exec node-red sh -lc 'cat /data/security/node-red-admin-auth.json'
```

3. se houver suspeita sobre histórico/local anterior, trate como incidente e rode rotação conjunta de:
   - `NODE_RED_ADMIN_PASSWORD`
   - `NODE_RED_CREDENTIAL_SECRET`
   - `NODE_RED_COOKIE_SECRET`
   - `WEBHOOK_SECRET` / `WEBHOOK_SECRET_PREVIOUS`
   - `WEBHOOK_HMAC_SECRET` / `WEBHOOK_HMAC_SECRET_PREVIOUS`

### Política operacional recomendada

- manter a senha do admin fora de README, tickets, chats e histórico de shell;
- registrar o responsável atual pela senha e a data da última rotação;
- rotacionar no máximo a cada `90` dias, ou imediatamente após troca de operador / suspeita de exposição;
- revisar cópias antigas de `.env`, exports de terminal, backups locais e qualquer pasta usada antes da recomendação de “trocar chaves expostas anteriormente”.


## Rate limit de login do Node-RED

O repositório já tinha **anti-flood de mensagens** e **controle de fila da IA**, mas esses mecanismos não protegiam autenticação.

Agora o endpoint de login do editor (`POST /auth/token`) recebe um rate limit dedicado com estas regras padrão:

- **janela**: `15` minutos (`NODE_RED_LOGIN_RATE_LIMIT_WINDOW_MS=900000`);
- **máximo de tentativas por IP + usuário**: `5` (`NODE_RED_LOGIN_RATE_LIMIT_MAX_ATTEMPTS=5`);
- **bloqueio temporário**: `30` minutos (`NODE_RED_LOGIN_RATE_LIMIT_BLOCK_MS=1800000`).

Quando o limite é atingido, o Node-RED responde `429 Too Many Requests` com `Retry-After`. Isso reduz a suscetibilidade do editor a brute force caso o ambiente seja exposto além do loopback.

## Auditoria de acesso do Node-RED

A configuração do Node-RED agora deixa de depender só de `logging.console.level = "info"` e de *debug nodes* para troubleshooting. A stack passa a ter uma **trilha persistente de auditoria** em `NODE_RED_AUDIT_LOG_DIR/NODE_RED_AUDIT_LOG_FILE` (padrão: `/data/logs/node-red-audit.jsonl`), dentro do volume `nodered_data`.

O arquivo registra em formato JSON Lines:

- eventos de auditoria emitidos pelo próprio Node-RED quando `logging.console.audit` está habilitado;
- `admin.login.success`, `admin.login.failure` e `admin.login.blocked`, com IP, usuário e status HTTP;
- `webhook.signature.rejected`, para tentativas rejeitadas no endpoint `/evolution/webhook`.

Isso cobre o ponto fraco visível no repositório: agora existe evidência persistente de **quem tentou acessar**, **quando** e **com qual resultado** nos pontos críticos de autenticação expostos aqui.

### O que continua pendente de governança

Esta mudança melhora bastante a trilha local, mas não substitui controles operacionais fora do repositório:

- **retenção**: o volume Docker preserva os logs entre reinícios do container, mas a política de rotação/expurgo ainda deve ser definida no host;
- **correlação**: se vocês precisarem investigação centralizada, o próximo passo é enviar esse JSONL para SIEM, Loki, ELK, Splunk ou coletor equivalente;
- **incidentes**: os *debug nodes* continuam úteis para troubleshooting de fluxo, mas não devem ser tratados como auditoria formal;
- **acesso ao host**: ainda vale revisar quem consegue ler o volume `nodered_data`, porque ele passa a conter evidência de acesso.

### Variáveis novas de auditoria

- `NODE_RED_AUDIT_LOG_DIR` (padrão: `/data/logs`)
- `NODE_RED_AUDIT_LOG_FILE` (padrão: `node-red-audit.jsonl`)

Exemplo de inspeção local após subir a stack:

```bash
docker compose exec node-red sh -lc 'tail -n 20 /data/logs/node-red-audit.jsonl'
```

## Consistência documentação x implementação (contexto Redis)

Esta revisão fecha a lacuna entre o que o projeto prometia e o que o container realmente gerava em `/data/settings.js`:

- o `contextStorage` do Node-RED agora é gerado com **Redis por padrão** (`NODE_RED_CONTEXT_STORAGE=redis`);
- o modo Redis usa o módulo já instalado no Dockerfile (`node-red-contrib-context-redis`) e parâmetros explícitos de conexão/prefixo;
- o modo `memory` continua disponível apenas como fallback operacional.

Com isso, a afirmação de “memória do bot persistida no Redis” deixa de depender de configuração implícita/incompleta e passa a ser verificável por variável de ambiente e pelo arquivo de metadata do boot.

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
