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
- [x] Prioridade 1 de pós-venda e retenção: módulo de recompra, garantia, devolução/troca, recall e manutenção periódica por cliente/frota.
- [x] Prioridade 3 de estoque: reserva automática ao montar proposta, cross-reference de equivalentes, curva ABC/giro por SKU e alerta de ruptura com impacto em vendas perdidas.
- [x] Catálogo técnico de aplicação veicular: relacionamento por marca/modelo/ano/motor/chassi com compatibilidade por SKU.
- [x] Prioridade 4 de financeiro/compliance: conciliação PIX automática com tolerância, régua de cobrança para inadimplência e trilha de auditoria expandida de preço/desconto/status.
- [x] Prioridade 2 fiscal/ERP: NFe/NFCe com trilha de eventos fiscais, contas a receber/pagar, lançamentos contábeis e fila de integração assíncrona com ERP.
- [x] Prioridade 5 omnichannel e marketing de base: visão integrada de canais, campanhas segmentadas e automações de reativação da carteira inativa.
- [x] Prioridade 6 gestão comercial: metas por vendedor, comissionamento, produtividade mensal e ranking por conversão/margem.

## Como aplicar

> Exemplo abaixo considerando sua stack já em execução (containers `node-red` e `evolution-postgres` saudáveis).

### Opção A (recomendada): deploy automatizado e versionável

1. Execute o deploy ponta a ponta (schema + flow via API Admin do Node-RED):

   ```bash
   ./scripts/deploy_crm_autopecas.sh
   ```

   O script:
   - aplica `sql/crm_autopecas_schema.sql` no PostgreSQL;
   - atualiza parâmetros de infraestrutura no flow (`crm_postgres_config` e URL de PIX);
   - faz deploy full no Node-RED sem passo de import manual;
   - gera trilha de auditoria em `.artifacts/last_crm_deploy.json`.

2. Para versionar alterações feitas no editor Node-RED:

   ```bash
   ./scripts/export_crm_autopecas_flow.sh
   git add flows/crm_autopecas_full_flow.json
   git commit -m "chore(flow): versiona atualização CRM Autopeças"
   ```

3. Variáveis de ambiente opcionais para múltiplos ambientes:
   - `NODE_RED_URL`
   - `POSTGRES_CONTAINER`, `POSTGRES_DB_NAME`, `POSTGRES_DB_USER`
   - `CRM_POSTGRES_HOST`, `CRM_POSTGRES_PORT`, `CRM_POSTGRES_DB`
   - `CRM_PIX_GATEWAY_URL`

### Opção B: processo manual (legado / MVP)

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

- A chave PIX é configurável por vendedor/pedido/atendimento e pode usar fallback por ambiente (`PIX_CHAVE_PADRAO`) para suportar múltiplos CNPJs, filiais e contas de recebimento.
- Pedido fechado exige pagamento (`ck_pedido_fechado_precisa_pago`).
- Mudanças de status são auditadas automaticamente por trigger (`log_status_change`).
- Trilhas de compliance financeiras:
  - `conciliar_pix_automatico(...)` registra conciliações em `conciliacoes_pix` e marca pedido como `pago` quando a diferença está dentro da tolerância.
  - `regua_cobranca` agenda automaticamente as etapas D+0, D+1, D+3, D+7 e escalonamento humano (D+10) para pedidos em `aguardando_pagamento`.
  - `vw_inadimplencia_pedidos` classifica risco (`risco_baixo`, `risco_moderado`, `inadimplente`) e mostra etapa de cobrança mais recente.
- Bloco fiscal/ERP de escala:
  - `fiscal_documentos`, `fiscal_documento_itens` e `fiscal_eventos` para ciclo de emissão/autorização de NFe/NFCe.
  - `titulos_financeiros` para contas a receber/pagar desvinculadas do fluxo apenas PIX.
  - `lancamentos_contabeis` para exportar partidas débito/crédito por competência.
  - `erp_integracoes` como fila resiliente (`pendente`/`enviado`/`confirmado`/`erro`) para integração com ERP externo.
  - `vw_fiscal_documentos_pendentes` e `vw_financeiro_titulos_abertos` para operação diária fiscal/financeira.
- Auditoria comercial expandida em `auditoria_comercial` para rastrear **quem alterou**:
  - `pedidos.status`
  - `pedidos.descontos`
  - `pedidos.subtotal`/`pedidos.total`
  - `estoque.preco_unitario`
- Pipeline comercial profissional em `pipeline_etapas` com probabilidade padrão por estágio e SLA por etapa.
- Gestão de time comercial com:
  - `metas_vendedores` para metas mensais por vendedor (receita, pedidos, atendimentos, conversão e margem), incluindo percentual base de comissão e bônus de superação.
  - `comissoes_vendedores` para lançamentos e pagamento de comissão por pedido/competência com trilha de status (`pendente` → `aprovada` → `paga`).
  - `vw_desempenho_vendedores` para produtividade mensal consolidada (atendimentos, pedidos convertidos, ticket, conversão, margem média e atingimento de metas).
  - `vw_ranking_vendedores` com ranking mensal por **conversão**, **margem** e **faturamento** para gestão de performance.
- Omnichannel e marketing de base implementados com:
  - `lead_canais_contato` para consolidar WhatsApp, telefone, email, redes sociais, site chat e SMS por cliente com opt-in.
  - `segmentos_marketing`, `campanhas_marketing` e `campanhas_marketing_execucoes` para segmentação e disparos por canal.
  - `automacoes_reativacao` + função `enfileirar_reativacao_carteira_inativa(...)` para reativar clientes sem interação.
  - `vw_carteira_inativa` para priorização por dias sem contato e canal preferencial.
- Motivo de perda obrigatório no lead perdido (`perdido_preco`, `sem_estoque`, `sem_retorno`, `comprou_concorrente`).
- Alertas para gerente disponíveis na view `vw_alertas_gerente` (`lead_parado`, `pedido_sem_retorno`, `pagamento_pendente`).
- Pós-venda/retensão implementados com:
  - `ativos_cliente` para rastrear veículos/frota por cliente e periodicidade.
  - `pos_venda_casos` para abrir e operar garantia, devolução/troca, recall, manutenção e recompra.
  - `manutencoes_agendadas` + função `gerar_manutencao_periodica(...)` para agenda recorrente.
  - `campanhas_retencao` e `campanhas_retencao_execucoes` para régua de recompra/reativação.
  - `vw_pos_venda_operacao` para gestão de fila e SLA.
  - `vw_retencao_clientes` para segmentação (`alta_recorrencia`, `recorrente`, `reativacao`, `sem_historico`).
- Inteligência de estoque disponível nas views:
  - `vw_estoque_disponibilidade` (livre x reservado por SKU).
  - `vw_sugestoes_equivalentes` (cross-reference para sugestão de item equivalente).
  - `vw_curva_abc_giro_sku` (classificação ABC + giro mensal estimado por SKU).
  - `vw_alerta_ruptura_estoque` (ruptura/risco com estimativa de receita perdida).
- Catálogo e aplicação técnica de peças:
  - `veiculos_catalogo` mantém granularidade técnica de aplicação (`marca/modelo/versão/ano/motor/código motor/chassi`).
  - `estoque_aplicacoes` relaciona SKU às aplicações por veículo com metadados técnicos (`lado`, `posição`, `código_oem`, observações e prioridade).
  - `buscar_aplicacoes_veiculares(...)` retorna peças compatíveis com filtros de marca, modelo, ano, motor e chassi.
  - `vw_catalogo_aplicacao_tecnica` entrega visão consolidada SKU + aplicação para consultas operacionais.


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
