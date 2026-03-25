# flowpluss

Guia completo para subir a stack **sem erros** (Node-RED + Evolution API + Redis + PostgreSQL + webhook-gateway).

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

---

## 7) Erros comuns e correção rápida

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
