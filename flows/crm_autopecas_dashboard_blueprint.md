# CRM Autopeças — Blueprint de Flow (Bot + Humano + Dashboard + PIX)

Este documento descreve um flow completo para Node-RED com visão de CRM, estoque, vendas e cobrança PIX no próprio chat.

## 1) Objetivo

Implementar um CRM de atendimento para autopeças com:

- Triagem automática por bot (captura de lead).
- Transferência para vendedor especialista.
- Gestão de pedido com conferência de itens.
- Geração de PIX e recibo no chat.
- Status ponta a ponta (lead até venda fechada).
- Dashboards operacionais e gerenciais.
- Visão integrada de estoque no atendimento.
- Pós-venda e retenção com recompra, garantia, troca/devolução, recall e manutenção periódica por cliente/frota.

---

## 2) Entidades e campos (persistência)

## 2.1 `leads`

- `id` (uuid)
- `nome`
- `empresa`
- `telefone`
- `estado`
- `cidade`
- `itens_interesse` (json)
- `origem` (whatsapp/bot)
- `status`
- `created_at`
- `updated_at`

## 2.2 `atendimentos`

- `id` (uuid)
- `lead_id` (fk)
- `vendedor_id` (fk)
- `status`
- `canal` (whatsapp)
- `observacoes`
- `created_at`
- `updated_at`

## 2.3 `pedidos`

- `id` (uuid)
- `atendimento_id` (fk)
- `cliente_nome`
- `cliente_empresa`
- `itens` (json)
- `subtotal`
- `frete`
- `descontos`
- `total`
- `status`
- `pix_txid`
- `pix_copia_cola`
- `pago_em`
- `created_at`
- `updated_at`

## 2.4 `vendedores`

- `id` (uuid)
- `nome`
- `telefone`
- `ativo` (bool)
- `pix_chave_tipo` (cpf)
- `pix_chave_valor` (`02445780012`)
- `created_at`
- `updated_at`

> Regra: mesmo havendo cadastro por vendedor, a chave PIX usada na cobrança é a chave oficial da empresa `02445780012`.

## 2.5 `estoque`

- `id` (uuid)
- `sku`
- `descricao`
- `categoria`
- `quantidade_disponivel`
- `preco_unitario`
- `localizacao`
- `ativo`
- `updated_at`

## 2.6 `recibos`

- `id` (uuid)
- `pedido_id` (fk)
- `tipo` (provisorio/definitivo)
- `arquivo_url`
- `gerado_em`

## 2.7 `ativos_cliente` (cliente/frota)

- `id` (uuid)
- `lead_id` (fk)
- `descricao_ativo`
- `placa`
- `modelo`
- `ano_modelo`
- `quilometragem_atual`
- `periodicidade_manutencao_dias`
- `ultima_manutencao_em`
- `proxima_manutencao_em`
- `ativo`
- `updated_at`

## 2.8 `pos_venda_casos`

- `id` (uuid)
- `lead_id` (fk)
- `atendimento_id` (fk opcional)
- `pedido_id` (fk opcional)
- `ativo_cliente_id` (fk opcional)
- `tipo` (`garantia`, `devolucao_troca`, `recall`, `manutencao`, `recompra`)
- `status` (`aberto`, `em_analise`, `aprovado`, `rejeitado`, `em_execucao`, `concluido`, `cancelado`)
- `prioridade` (1-5)
- `prazo_sla_em`
- `concluido_em`
- `resolucao`

## 2.9 `manutencoes_agendadas`

- `id` (uuid)
- `ativo_cliente_id` (fk)
- `pedido_id` (fk opcional)
- `pos_venda_caso_id` (fk opcional)
- `tipo_servico`
- `agendado_para`
- `executado_em`
- `status`
- `canal_notificacao`

## 2.10 `campanhas_retencao` e `campanhas_retencao_execucoes`

- Campanhas para recompra/reativação com janela de vigência.
- Execuções por cliente com status de envio, resposta e conversão em pedido.

---

## 3) Status oficiais do CRM

## 3.1 Status de lead e atendimento

1. `novo_lead`
2. `triagem_bot`
3. `dados_incompletos`
4. `lead_qualificado_bot`
5. `aguardando_transferencia_humano`
6. `transferido_vendedor`
7. `em_atendimento_humano`
8. `levantamento_concluido`
9. `consulta_estoque_realizada`
10. `proposta_enviada`
11. `negociacao`
12. `pedido_criado`
13. `conferencia_itens`
14. `pix_gerado`
15. `aguardando_pagamento`
16. `pagamento_confirmado`
17. `recibo_disponivel`
18. `venda_fechada`
19. `atendimento_finalizado`
20. `perdido_nao_convertido`

## 3.2 Status de pedido

- `rascunho`
- `aguardando_conferencia`
- `aguardando_pagamento`
- `pago`
- `fechado`
- `cancelado`

---

## 4) Fluxo A — Bot (pré-atendimento)

## 4.1 Sequência de nodes

1. **Webhook Entrada WhatsApp** (`http in` / webhook Evolution)
2. **Valida Assinatura** (`function` / gateway HMAC)
3. **Normaliza Mensagem** (`function`)
4. **Identifica Lead Existente** (`postgres` select)
5. **Coleta Nome** (`switch` + `template`)
6. **Coleta Empresa**
7. **Coleta Itens de Interesse**
8. **Coleta Estado/Cidade**
9. **Valida Dados Mínimos** (`function`)
10. **Salva/Atualiza Lead** (`postgres upsert`)
11. **Muda Status para `lead_qualificado_bot`**
12. **Roteia para fila humana** (`link out` / fila)
13. **Notifica cliente no chat** (mensagem: “seu atendimento foi encaminhado”)

## 4.2 Regras

- Sem nome + item: manter `dados_incompletos`.
- Com dados mínimos completos: seguir para humano.

---

## 5) Fluxo B — Atendimento humano + vendas

## 5.1 Sequência de nodes

1. **Recebe Lead Qualificado** (`link in`)
2. **Distribui para vendedor ativo** (`function` round-robin)
3. **Atualiza `transferido_vendedor`**
4. **Abre atendimento** (`atendimentos`)
5. **Consulta estoque em tempo real** (`postgres` select em `estoque`)
6. **Monta proposta** (`template`)
7. **Registra proposta enviada** (`status: proposta_enviada`)
8. **Cria pedido** (`pedidos.status = aguardando_conferencia`)
9. **Confirmação de itens no chat** (`quick reply`: Confirmar / Ajustar)
10. **Se Ajustar**: volta para proposta.
11. **Se Confirmar**: gera PIX e recibo provisório.

---

## 6) Fluxo C — PIX + recibo no chat

## 6.1 Regra principal

Após cliente confirmar itens, o flow deve:

1. Gerar cobrança PIX com chave `02445780012`.
2. Gerar `pix_copia_cola` e opcional QR.
3. Enviar no chat o PIX + resumo do pedido.
4. Gerar recibo provisório (PDF/HTML).
5. Atualizar status para `aguardando_pagamento`.

## 6.2 Sequência de nodes

1. **Trigger confirmação de itens**
2. **Valida total do pedido**
3. **Node Gerar PIX** (API banco/gateway PIX)
4. **Persistir dados do PIX** (`pix_txid`, `pix_copia_cola`)
5. **Gerar Recibo Provisório** (`template` + serviço PDF)
6. **Enviar mensagem no WhatsApp** com:
   - resumo
   - código PIX copia e cola
   - instrução de pagamento
7. **Set status `pix_gerado`**
8. **Set status `aguardando_pagamento`**

## 6.3 Confirmação de pagamento

1. **Webhook de confirmação PIX** (callback do provedor)
2. **Valida TXID e valor**
3. **Atualiza pedido para `pago`**
4. **Set status `pagamento_confirmado`**
5. **Gerar recibo definitivo**
6. **Publicar link de download do recibo no chat**
7. **Set status `recibo_disponivel`**
8. **Habilitar ação do vendedor “Fechar venda”**
9. **Ao fechar: `venda_fechada` + `atendimento_finalizado`**

---

## 7) Dashboards (nodes de dashboard)

## 7.1 Aba: Operação

- **Card**: Atendimentos hoje
- **Card**: Em atendimento humano
- **Card**: Aguardando pagamento
- **Tabela**: fila de atendimentos por status
- **Tabela**: atendimentos por vendedor

## 7.2 Aba: Pedidos e Vendas

- **Card**: Pedidos criados
- **Card**: Pedidos fechados (vendas)
- **Card**: Valor vendido hoje/mês
- **Gráfico linha**: vendas por período
- **Gráfico funil**: proposta → pedido → pago → fechado

## 7.3 Aba: Clientes

- **Tabela ranking**: principais clientes (qtd pedidos)
- **Tabela ranking**: principais clientes (valor comprado)
- **Card**: taxa de conversão geral

## 7.4 Aba: Estoque

- **Tabela**: itens e saldo disponível
- **Card**: itens com estoque baixo
- **Gráfico barras**: itens mais procurados
- **Alerta**: ruptura de estoque para item solicitado em atendimento

## 7.5 Aba: Financeiro PIX

- **Card**: cobranças PIX emitidas
- **Card**: pagamentos confirmados
- **Card**: pendências de pagamento
- **Tabela**: pedidos em `aguardando_pagamento`

## 7.6 Aba: Pós-venda & Retenção

- **Card**: casos pós-venda abertos
- **Card**: SLA estourado por tipo de caso
- **Tabela**: fila de garantia/troca/recall/manutenção por prioridade
- **Tabela**: ativos com manutenção vencendo ou atrasada
- **Card**: clientes em risco de churn (sem recompra)
- **Funil**: campanha enviada → respondeu → recompra

---

## 8) Regras de negócio críticas

- Pedido só pode ser **fechado** após `pagamento_confirmado`.
- Ao gerar PIX, atendimento obrigatoriamente vai para `aguardando_pagamento`.
- Recibo definitivo só é liberado após confirmação do pagamento.
- Estoque deve ser consultado antes de enviar proposta final.
- Toda transição de status deve ser auditada (`status_log`).
- Caso de pós-venda com prazo vencido entra em alerta de SLA.
- Cliente com histórico e sem recompra deve entrar em campanha de retenção.

---

## 9) Eventos e automações recomendadas

- Lembrete automático de pagamento (30 min / 2 h / 24 h).
- Reatribuição automática se vendedor ficar inativo por SLA.
- Alerta para gerente quando houver muitos pedidos pendentes de pagamento.
- Geração automática da próxima manutenção periódica por ativo/frota.
- Régua de retenção para clientes sem recompra em janelas configuráveis (30/60/120 dias).

---

## 10) Mensagens-padrão no chat

## 10.1 Confirmação de itens

"Perfeito! Confirme por favor os itens, quantidades e valores. Após sua confirmação, envio o PIX para pagamento."

## 10.2 PIX gerado

"Pedido confirmado ✅\nTotal: R$ {{total}}\nPIX (copia e cola): {{pix_copia_cola}}\nAssim que o pagamento for confirmado, envio o recibo para download aqui no chat."

## 10.3 Pagamento confirmado

"Pagamento confirmado ✅\nSeu recibo já está disponível para download: {{recibo_url}}\nObrigado!"

---

## 11) Checklist de implementação

- [ ] Criar tabelas (`leads`, `atendimentos`, `pedidos`, `vendedores`, `estoque`, `recibos`, `status_log`).
- [ ] Montar fluxo de triagem bot.
- [ ] Montar fluxo de atendimento humano.
- [ ] Integrar provedor PIX para geração + callback.
- [ ] Implementar gerador de recibo provisório e definitivo.
- [ ] Criar dashboards por aba.
- [ ] Publicar alertas e métricas de SLA.
- [ ] Criar módulo de pós-venda (`ativos_cliente`, `pos_venda_casos`, `manutencoes_agendadas`).
- [ ] Criar módulo de retenção/recompra (`campanhas_retencao`, `campanhas_retencao_execucoes`).


---

## 12) Implantação de cada item (passo a passo prático)

> Ordem recomendada: banco de dados -> cadastros base -> bot -> humano -> PIX -> recibo -> dashboards -> alertas.

## 12.1 Item: Criar tabelas e estrutura de dados

### Ações

1. Criar script SQL inicial com todas as tabelas.
2. Criar índices para consulta rápida por status e datas.
3. Criar tabela de auditoria de transição (`status_log`).

### SQL base (resumo)

- `leads(id, telefone unique, status, created_at, updated_at)`
- `atendimentos(id, lead_id, vendedor_id, status, created_at)`
- `pedidos(id, atendimento_id, status, total, pix_txid, pago_em)`
- `vendedores(id, nome, ativo, pix_chave_tipo, pix_chave_valor)`
- `estoque(id, sku unique, quantidade_disponivel, preco_unitario)`
- `recibos(id, pedido_id, tipo, arquivo_url, gerado_em)`
- `status_log(id, entidade, entidade_id, de_status, para_status, usuario, data_evento)`

### Critérios de aceite

- Inserir, consultar e atualizar registros de todas as tabelas.
- Toda mudança de status gera linha em `status_log`.

## 12.2 Item: Cadastro de vendedores (com chave PIX da empresa)

### Ações

1. Criar formulário no dashboard para cadastrar vendedor.
2. Campos obrigatórios: nome, telefone, ativo.
3. Preencher automaticamente:
   - `pix_chave_tipo = cpf`
   - `pix_chave_valor = 02445780012`

### Regra

- Não permitir salvar vendedor sem status `ativo` definido.
- Não permitir troca da chave PIX oficial via painel de vendedor.

### Critérios de aceite

- Vendedor cadastrado aparece na fila de distribuição.
- Chave PIX da empresa aplicada em todas as cobranças.

## 12.3 Item: Cadastro e visão de estoque

### Ações

1. Criar formulário CRUD de estoque (SKU, descrição, saldo, preço).
2. Criar consulta por texto (SKU/descrição) para uso no atendimento.
3. Criar alerta de estoque baixo (ex.: saldo < 5).

### Critérios de aceite

- Vendedor consegue consultar item durante o chat.
- Itens indisponíveis geram aviso antes da proposta.

## 12.4 Item: Fluxo de triagem do bot

### Ações

1. Configurar webhook de entrada WhatsApp.
2. Validar assinatura/HMAC.
3. Salvar contexto de conversa por telefone.
4. Perguntar sequencialmente:
   - Nome
   - Empresa
   - Itens desejados
   - Estado e cidade
5. Marcar `dados_incompletos` quando faltar dado essencial.
6. Ao completar, definir `lead_qualificado_bot`.

### Critérios de aceite

- Lead novo é criado automaticamente.
- Todos os campos mínimos são coletados antes da transferência.

## 12.5 Item: Transferência para atendimento humano

### Ações

1. Enviar lead para fila humana (`link out`).
2. Aplicar roteamento de vendedor (round-robin ou menor fila).
3. Criar `atendimento` com status `transferido_vendedor`.
4. Notificar cliente: “vendedor especialista irá continuar”.

### Critérios de aceite

- Cada lead qualificado fica com um vendedor responsável.
- Cliente recebe confirmação da transferência no chat.

## 12.6 Item: Negociação e criação de pedido

### Ações

1. Vendedor consulta estoque no fluxo.
2. Vendedor monta proposta com itens e total.
3. Cliente aprova itens no chat.
4. Sistema cria pedido em `aguardando_conferencia`.

### Critérios de aceite

- Pedido só nasce após proposta enviada.
- Histórico de alterações de item fica registrado.

## 12.7 Item: Geração de PIX no chat

### Ações

1. Após confirmação de itens, chamar provedor PIX.
2. Informar valor total e descrição do pedido.
3. Salvar `pix_txid` e `pix_copia_cola`.
4. Enviar mensagem no chat com resumo + PIX.
5. Atualizar status para `aguardando_pagamento`.

### Critérios de aceite

- PIX chega no chat no mesmo atendimento.
- Sem PIX gerado, não avançar para fechamento.

## 12.8 Item: Recibo provisório e recibo definitivo

### Ações

1. Gerar recibo provisório no momento da cobrança.
2. Ouvir webhook de confirmação de pagamento.
3. Validar TXID e valor.
4. Gerar recibo definitivo (PDF) com status pago.
5. Enviar link de download no chat.

### Critérios de aceite

- Cliente consegue baixar recibo definitivo após pagamento confirmado.
- Recibo provisório e definitivo ficam vinculados ao pedido.

## 12.9 Item: Fechamento da venda pelo vendedor

### Ações

1. Após `pagamento_confirmado`, liberar botão `Fechar venda`.
2. Ao clicar:
   - pedido -> `fechado`
   - atendimento -> `atendimento_finalizado`
   - status CRM -> `venda_fechada`
3. Gravar auditoria da operação.

### Critérios de aceite

- Não é possível fechar venda sem pagamento confirmado.
- Métricas de faturamento atualizam imediatamente no dashboard.

## 12.10 Item: Dashboard de operação

### Ações

1. Criar cards de volume diário.
2. Criar tabela de fila por status.
3. Criar visão por vendedor (em atendimento, finalizados, conversão).

### Critérios de aceite

- Time operacional acompanha gargalos em tempo real.

## 12.11 Item: Dashboard de pedidos e faturamento

### Ações

1. Card pedidos criados.
2. Card pedidos fechados.
3. Card valor vendido (dia/mês).
4. Gráfico de evolução diária.
5. Funil comercial de conversão.

### Critérios de aceite

- Números batem com dados em `pedidos`.

## 12.12 Item: Dashboard de clientes e estoque

### Ações

1. Ranking de principais clientes por volume/valor.
2. Itens mais procurados.
3. Itens com estoque crítico.
4. Alerta de ruptura no momento da negociação.

### Critérios de aceite

- Comercial e estoque trabalham com a mesma base de dados.

## 12.13 Item: Alertas e automações

### Ações

1. Lembretes automáticos de pagamento (30min, 2h, 24h).
2. Alerta para gerente quando pedidos pendentes > limite.
3. Reatribuição automática se SLA de primeiro retorno estourar.

### Critérios de aceite

- Redução de pedidos em aberto sem retorno.

## 12.14 Item: Segurança e conformidade

### Ações

1. Validar assinatura dos webhooks.
2. Mascarar CPF em telas públicas (exibir parcial).
3. Registrar logs de acesso e alteração de status.
4. Limitar ações críticas (fechar venda, estorno) por perfil.

### Critérios de aceite

- Auditoria completa de eventos críticos.
- Sem endpoint de webhook aberto sem validação.

---

## 13) Plano de execução em 7 dias (sugestão)

- **Dia 1:** banco + tabelas + status_log.
- **Dia 2:** cadastros de vendedor e estoque.
- **Dia 3:** fluxo de bot e qualificação de lead.
- **Dia 4:** fluxo humano + proposta + criação de pedido.
- **Dia 5:** integração PIX + aguardando pagamento.
- **Dia 6:** confirmação pagamento + recibo definitivo + fechar venda.
- **Dia 7:** dashboards, alertas e validação final E2E.

---

## 14) Critério de pronto (Definition of Done)

- Lead entra via bot e chega ao vendedor com dados completos.
- Pedido é conferido e PIX enviado no próprio chat.
- Atendimento muda para `aguardando_pagamento` após gerar cobrança.
- Após pagamento, recibo definitivo fica disponível para download.
- Vendedor fecha a venda e dashboards refletem os indicadores em tempo real.
