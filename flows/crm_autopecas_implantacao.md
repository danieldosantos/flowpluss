# CRM Autopeças — Implantação no projeto

Este projeto agora inclui os artefatos necessários para implantar o blueprint completo:

## Arquivos adicionados

- `sql/crm_autopecas_schema.sql`: schema completo com tabelas, índices, constraints e auditoria automática em `status_log`.
- `flows/crm_autopecas_full_flow.json`: flow Node-RED importável com os blocos principais de bot, humano, PIX/recibo e dashboard.

## Cobertura do checklist

- [x] Criar tabelas (`leads`, `atendimentos`, `pedidos`, `vendedores`, `estoque`, `recibos`, `status_log`).
- [x] Montar fluxo de triagem bot.
- [x] Montar fluxo de atendimento humano.
- [x] Integrar etapa de geração PIX e callback (via HTTP para gateway PIX).
- [x] Implementar geração de recibo provisório e mensagem de recibo definitivo.
- [x] Criar dashboards operacionais (aba de Operação com KPIs).
- [x] Publicar base para alertas/métricas via `status_log` e consultas SQL.

## Como aplicar

> Exemplo abaixo considerando sua stack já em execução (containers `node-red` e `evolution-postgres` saudáveis).

1. Aplicar schema:

   ```bash
   psql -h 127.0.0.1 -U flowpluss -d flowpluss -f sql/crm_autopecas_schema.sql
   ```

   Se você não tiver `psql` instalado no host, rode direto no container PostgreSQL:

   ```bash
   docker exec -i evolution-postgres psql -U flowpluss -d flowpluss < sql/crm_autopecas_schema.sql
   ```

   Validar se as tabelas foram criadas:

   ```bash
   docker exec -it evolution-postgres psql -U flowpluss -d flowpluss -c "\dt"
   ```

2. Importar flow no Node-RED:
   - Menu > Import > `flows/crm_autopecas_full_flow.json`.
   - Ajustar nós `postgres`/`http request` conforme credenciais do ambiente.
   - Deploy.

   Checklist rápido de configuração dos nós:
   - Nó `postgres`: host `evolution-postgres` (se Node-RED estiver na mesma rede Docker) ou `127.0.0.1` com porta publicada.
   - Banco: `flowpluss`; usuário: `flowpluss`; senha: definida no seu ambiente.
   - Nós `http request` de cobrança/callback: URL base do gateway PIX do seu ambiente.
   - Salvar credenciais no Node-RED e fazer **Deploy Full**.

3. Validar ponta a ponta:
   - Simular entrada de webhook bot.
   - Confirmar criação de lead e roteamento humano.
   - Confirmar geração de PIX e atualização de status.
   - Simular callback de pagamento.

   Exemplo mínimo para validar webhook (ajuste endpoint/token do seu flow):

   ```bash
   curl -X POST "http://127.0.0.1:1880/evolution/webhook" \
     -H "Content-Type: application/json" \
     -d '{
       "telefone": "5511999999999",
       "mensagem": "Preciso de pastilha de freio para Corolla 2020"
     }'
   ```

   Consultas SQL úteis para conferir processamento:

   ```sql
   -- Leads recentes
   SELECT id, telefone, status, created_at
   FROM leads
   ORDER BY created_at DESC
   LIMIT 10;

   -- Pedidos recentes e status de pagamento
   SELECT id, atendimento_id, status, total, pago_em, updated_at
   FROM pedidos
   ORDER BY updated_at DESC
   LIMIT 10;

   -- Auditoria de mudanças de status
   SELECT entidade, entidade_id, de_status, para_status, data_evento
   FROM status_log
   ORDER BY data_evento DESC
   LIMIT 20;
   ```

4. Se algo falhar, diagnóstico rápido:
   - `docker logs --tail 200 node-red`
   - `docker logs --tail 200 evolution-postgres`
   - Conferir se o flow está usando os mesmos nomes de host da rede Docker.
   - Reimportar o flow e fazer novo deploy.

## Observações de negócio implementadas

- A chave PIX oficial (`02445780012`) é fixada no schema de vendedores e usada no fluxo de cobrança.
- Pedido fechado exige pagamento (`ck_pedido_fechado_precisa_pago`).
- Mudanças de status são auditadas automaticamente por trigger (`log_status_change`).
- Pipeline comercial profissional em `pipeline_etapas` com probabilidade padrão por estágio e SLA por etapa.
- Motivo de perda obrigatório no lead perdido (`perdido_preco`, `sem_estoque`, `sem_retorno`, `comprou_concorrente`).
- Alertas para gerente disponíveis na view `vw_alertas_gerente` (`lead_parado`, `pedido_sem_retorno`, `pagamento_pendente`).


## Fluxo único + menu principal (novo)

O arquivo `flows/crm_autopecas_full_flow.json` foi consolidado em **um único flow tab** no editor Node-RED:

- `CRM Autopeças - Fluxo Unificado`

Além disso, no Dashboard (`/ui`) existe uma aba de navegação **Menu CRM** com atalhos para as demais telas.

### URLs das telas

Considerando Node-RED em `http://127.0.0.1:1880`:

- Home do dashboard: `http://127.0.0.1:1880/ui`
- Menu principal: `http://127.0.0.1:1880/ui/#!/0`
- Operação: `http://127.0.0.1:1880/ui/#!/1`
- Vendas: `http://127.0.0.1:1880/ui/#!/2`
- Financeiro PIX: `http://127.0.0.1:1880/ui/#!/3`
- Clientes & Estoque: `http://127.0.0.1:1880/ui/#!/4`

> Observação: o índice (`#!/0`, `#!/1`...) pode variar se você já tiver outras abas no Dashboard. Se variar, abra `/ui` e navegue pelo menu lateral.


## Gate obrigatório antes de liberar para o comercial

> **Prioridade 1 (“fazer vender sem quebrar”)**: somente liberar operação após executar e passar no E2E completo:

```bash
./tests/run_e2e_lead_to_fechamento.sh
```

Cadeia validada no teste: **lead → atendimento → pedido → PIX → pagamento → fechamento**.
