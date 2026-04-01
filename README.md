# flowpluss

Guia completo para subir a stack **sem erros** (Node-RED + Evolution API + Redis + PostgreSQL + webhook-gateway).

## 🚀 Setup automatizado (do zero)

Para subir o projeto do zero com um comando, use:

```bash
AUTO_YES=1 ./scripts/setup_do_zero.sh
```

### Opções úteis

- **Reset total de dados locais (volumes Docker):**

```bash
AUTO_YES=1 RESET_VOLUMES=1 ./scripts/setup_do_zero.sh
```

- **Modo interativo (confirma antes de apagar volumes):**

```bash
./scripts/setup_do_zero.sh
```

O script automatiza:
1. validação de `docker`/`docker compose`;
2. criação do `.env` a partir de `.envexemplo` (se não existir);
3. validação das variáveis essenciais no `.env`;
4. `docker compose down` (ou `down -v` com reset);
5. `docker compose up -d --build`;
6. checagem de disponibilidade do Node-RED e Evolution API.

---

## 1) O que este projeto sobe

Serviços do `docker-compose.yml`:

- `postgres` (PostgreSQL 15)
- `redis` (Redis 7)
- `evolution-api` (Evolution API v2.3.6)
- `node-red` (inicia sem flow pré-carregado)
- `webhook-gateway` (ponte de autenticação entre Evolution e Node-RED)

Portas publicadas no host (somente localhost):

- Node-RED: `127.0.0.1:1880`
- Evolution API: `127.0.0.1:8080`

---

## 1.1) Flow pronto para importação

O Node-RED sobe com `/data/flows.json` em branco (sem flow pré-definido).  
Este repositório inclui uma cópia pronta para importação em:

- `flows/whatsapp_secure_pro_corrigido.json`

Esse arquivo já está ajustado para este projeto (Docker service `evolution-api`, endpoint `/evolution/webhook`, uso de `MISTRAL_API_KEY` e `EVOLUTION_API_KEY`) e aceita configuração por ambiente de:

- `EVOLUTION_INSTANCE`
- `BOT_NUMBER`


## 1.2) CRM Autopeças (bot + humano + PIX + dashboard)

Também foi adicionado um pacote completo de implantação do CRM Autopeças:

- Flow Node-RED completo: `flows/crm_autopecas_full_flow.json`
- Blueprint funcional: `flows/crm_autopecas_dashboard_blueprint.md`
- Guia de implantação: `flows/crm_autopecas_implantacao.md`
- Schema SQL: `sql/crm_autopecas_schema.sql`

O schema já contempla o bloco de **pós-venda e retenção** (alta prioridade), com:
- gestão de garantia/devolução/recall/manutenção/recompra;
- agenda de manutenção periódica por cliente/frota;
- segmentação de retenção para campanhas de recompra.

Também contempla o bloco **Omnichannel e marketing de base** (prioridade 5), com:
- visão integrada de canais por lead (WhatsApp, telefone, email, redes sociais, chat e SMS);
- campanhas segmentadas por público/segmento;
- automação de reativação de carteira inativa com fila de execuções por canal preferencial.

Também contempla o bloco **Fiscal/ERP** (alta prioridade), com:
- documentos fiscais de NFe/NFCe (status, eventos, XML/PDF e chave de acesso);
- contas a receber/pagar com visão de inadimplência além do PIX operacional;
- fila de integração ERP e lançamentos contábeis para sincronização assíncrona.

Fluxo recomendado:
1. Aplicar o SQL no PostgreSQL.
2. Importar o flow completo no Node-RED.
3. Ajustar credenciais de nós Postgres e gateway PIX.
4. Executar testes E2E de webhook, proposta, PIX, pagamento e fechamento.

### 1.3) Pipeline de deploy/versionamento (sem import manual)

Para reduzir operação manual em ambiente de escala, o projeto agora inclui dois scripts:

- `scripts/deploy_crm_autopecas.sh`: aplica schema + faz deploy full do flow via API Admin do Node-RED.
- `scripts/export_crm_autopecas_flow.sh`: exporta o flow ativo do Node-RED para `flows/crm_autopecas_full_flow.json` para versionamento no Git.

Fluxo recomendado de operação contínua:

```bash
# 1) Deploy automatizado da versão do repositório
./scripts/deploy_crm_autopecas.sh

# 2) Após ajustes em produção/homologação, exporte para versionar
./scripts/export_crm_autopecas_flow.sh
git add flows/crm_autopecas_full_flow.json
git commit -m "chore(flow): versiona atualização do CRM Autopeças"
```

Variáveis úteis para customizar o deploy automatizado:

- `NODE_RED_URL` (default: `http://127.0.0.1:1880`)
- `POSTGRES_CONTAINER` (default: `evolution-postgres`)
- `POSTGRES_DB_NAME` / `POSTGRES_DB_USER`
- `CRM_POSTGRES_HOST` / `CRM_POSTGRES_PORT` / `CRM_POSTGRES_DB`
- `CRM_PIX_GATEWAY_URL`

Teste obrigatório para liberar time comercial:

```bash
./tests/run_e2e_lead_to_fechamento.sh
```

## 2) Pré-requisitos (obrigatório)

Antes de qualquer comando, confirme:

1. Docker e Docker Compose instalados e funcionando.
2. Portas locais `1880` e `8080` livres.
3. Você está no diretório do projeto (`/workspace/flowpluss`).

Comandos de validação:

```bash
docker --version
docker compose version
```

---

## 3) Configuração do arquivo `.env` (passo mais importante)

### 3.1 Criar `.env`

```bash
cp .envexemplo .env
```

### 3.2 Editar `.env`

Preencha **obrigatoriamente** com valores reais (não deixe placeholders):

- `EVOLUTION_API_KEY`
- `MISTRAL_API_KEY`
- `NODE_RED_ADMIN_PASSWORD`
- `WEBHOOK_SECRET`
- `WEBHOOK_HMAC_SECRET`
- `NODE_RED_CREDENTIAL_SECRET`
- `NODE_RED_COOKIE_SECRET`

> Se qualquer um desses ficar com valor de exemplo (`troque-por-...`), a inicialização pode falhar ou ficar insegura.

### 3.3 Exemplo de segredos fortes (Linux/macOS/Git Bash)

```bash
openssl rand -hex 32
```

Gere e use valores diferentes para cada variável de segredo.

---

## 4) Subida limpa (recomendada para primeira execução)

```bash
docker compose down -v
docker compose up -d --build
```

Depois confira status:

```bash
docker compose ps
```

Esperado: todos os serviços em estado `Up` (ou `healthy` quando houver healthcheck).

---

## 5) Checklist pós-subida (para garantir que está tudo ok)

### 5.1 Testar endpoints locais

```bash
curl -I http://127.0.0.1:1880
curl -I http://127.0.0.1:8080
```

### 5.2 Verificar logs se algo não subir

```bash
docker compose logs --tail=200 node-red
docker compose logs --tail=200 evolution-api
docker compose logs --tail=200 webhook-gateway
docker compose logs --tail=200 postgres
docker compose logs --tail=200 redis
```

### 5.3 Confirmar autenticação do Node-RED carregada

```bash
docker compose exec node-red sh -lc 'cat /data/security/node-red-admin-auth.json'
```

### 5.4 Confirmar trilha de auditoria

```bash
docker compose exec node-red sh -lc 'tail -n 20 /data/logs/node-red-audit.jsonl'
```

---

## 6) Acesso da aplicação

- Node-RED: http://127.0.0.1:1880
- Evolution API: http://127.0.0.1:8080
- Dashboard Node-RED: http://127.0.0.1:1880/ui

### 6.1) URLs das telas do CRM Autopeças (menu principal + telas)

Após importar `flows/crm_autopecas_full_flow.json`, o CRM fica em **um único flow tab** e o Dashboard ganha um **Menu CRM** com links para as telas:

- Menu principal: `http://127.0.0.1:1880/ui/#!/0`
- Operação: `http://127.0.0.1:1880/ui/#!/1`
- Vendas: `http://127.0.0.1:1880/ui/#!/2`
- Financeiro PIX: `http://127.0.0.1:1880/ui/#!/3`
- Clientes & Estoque: `http://127.0.0.1:1880/ui/#!/4`

> Se você já possui outras abas de dashboard, a numeração pode mudar. Nesse caso, entre em `http://127.0.0.1:1880/ui` e use o menu lateral.

---

## 7) Erros comuns e correção rápida

### Erro: `exec /usr/src/node-red/entrypoint.sh: no such file or directory`

Causa comum:
- Imagem do Node-RED buildada com cache antigo e/ou script com final de linha Windows (`CRLF`), o que quebra a execução do entrypoint no Linux.

Correção:
1. Rebuild sem cache e recriação do serviço:

```bash
docker compose build --no-cache node-red
docker compose up -d --force-recreate node-red
```

2. Valide se o entrypoint existe e está executável:

```bash
docker compose run --rm --entrypoint sh node-red -lc 'ls -l /usr/src/node-red/entrypoint.sh && head -n 1 /usr/src/node-red/entrypoint.sh'
```

3. Se ainda falhar, remova o container e suba novamente:

```bash
docker compose rm -sf node-red
docker compose up -d --build node-red
```

### Erro: Node-RED não inicia por senha inválida

Causa comum:
- `NODE_RED_ADMIN_PASSWORD` fraca, vazia, placeholder ou contendo o usuário.

Correção:
1. Ajuste a senha no `.env`.
2. Rode novamente:

```bash
docker compose up -d --build node-red
```

### Erro: gateway falha com segredo ausente

Causa comum:
- `WEBHOOK_SECRET` e/ou `WEBHOOK_HMAC_SECRET` não definidos.

Correção:
1. Corrija `.env`.
2. Recrie serviços:

```bash
docker compose up -d --build webhook-gateway evolution-api node-red
```

### Erro: falha de conexão com PostgreSQL/Redis

Correção:

```bash
docker compose ps
docker compose logs --tail=200 postgres redis
```

Se necessário, faça subida limpa novamente:

```bash
docker compose down -v
docker compose up -d --build
```

---

## 8) Operação segura recomendada

1. Não exponha esse ambiente diretamente na internet.
2. Mantenha o bind em `127.0.0.1`.
3. Rode periodicamente (Windows host):
   - `firewall_hardening.ps1`
   - `audit_external_access.ps1`
4. Faça rotação periódica de:
   - `NODE_RED_ADMIN_PASSWORD`
   - `NODE_RED_CREDENTIAL_SECRET`
   - `NODE_RED_COOKIE_SECRET`
   - `WEBHOOK_SECRET` / `WEBHOOK_SECRET_PREVIOUS`
   - `WEBHOOK_HMAC_SECRET` / `WEBHOOK_HMAC_SECRET_PREVIOUS`

---

## 9) Comandos úteis de manutenção

### Reiniciar tudo

```bash
docker compose restart
```

### Derrubar sem apagar volumes

```bash
docker compose down
```

### Derrubar apagando dados (reset total)

```bash
docker compose down -v
```

### Ver uso de recursos

```bash
docker stats
```

---

## 10) Resumo rápido (copiar e executar)

```bash
cp .envexemplo .env
# edite o .env e troque todos os "troque-por-..."
docker compose down -v
docker compose up -d --build
docker compose ps
```

Se `docker compose ps` mostrar tudo `Up`, abra:

- http://127.0.0.1:1880
- http://127.0.0.1:8080
