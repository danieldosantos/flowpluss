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

1. Aplicar schema:

   ```bash
   psql -h 127.0.0.1 -U flowpluss -d flowpluss -f sql/crm_autopecas_schema.sql
   ```

2. Importar flow no Node-RED:
   - Menu > Import > `flows/crm_autopecas_full_flow.json`.
   - Ajustar nós `postgres`/`http request` conforme credenciais do ambiente.
   - Deploy.

3. Validar ponta a ponta:
   - Simular entrada de webhook bot.
   - Confirmar criação de lead e roteamento humano.
   - Confirmar geração de PIX e atualização de status.
   - Simular callback de pagamento.

## Observações de negócio implementadas

- A chave PIX oficial (`02445780012`) é fixada no schema de vendedores e usada no fluxo de cobrança.
- Pedido fechado exige pagamento (`ck_pedido_fechado_precisa_pago`).
- Mudanças de status são auditadas automaticamente por trigger (`log_status_change`).
