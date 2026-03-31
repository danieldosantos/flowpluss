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

---

## 8) Regras de negócio críticas

- Pedido só pode ser **fechado** após `pagamento_confirmado`.
- Ao gerar PIX, atendimento obrigatoriamente vai para `aguardando_pagamento`.
- Recibo definitivo só é liberado após confirmação do pagamento.
- Estoque deve ser consultado antes de enviar proposta final.
- Toda transição de status deve ser auditada (`status_log`).

---

## 9) Eventos e automações recomendadas

- Lembrete automático de pagamento (30 min / 2 h / 24 h).
- Reatribuição automática se vendedor ficar inativo por SLA.
- Alerta para gerente quando houver muitos pedidos pendentes de pagamento.

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

