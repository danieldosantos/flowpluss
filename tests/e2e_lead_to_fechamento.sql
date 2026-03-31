BEGIN;

DO $$
DECLARE
  v_lead_id uuid;
  v_vendedor_id uuid;
  v_atendimento_id uuid;
  v_pedido_id uuid;
  v_lead_perdido_id uuid;
  v_alertas integer;
  v_reserva_qtd integer;
  v_curva_sku text;
  v_alerta_ruptura integer;
  v_titulo_receber_id uuid;
  v_documento_fiscal_id uuid;
  v_fiscal_pendente integer;
  v_veiculo_id uuid;
  v_aplicacao_count integer;
  v_aplicacao_por_chassi integer;
  v_txid text := 'e2e-txid-' || substring(md5(clock_timestamp()::text) from 1 for 12);
BEGIN
  INSERT INTO estoque (sku, descricao, categoria, quantidade_disponivel, estoque_minimo, preco_unitario, ativo)
  VALUES
    ('E2E-001', 'Pastilha de Freio E2E', 'freio', 10, 3, 75.00, true),
    ('E2E-002', 'Pastilha de Freio Equivalente E2E', 'freio', 8, 2, 72.00, true),
    ('E2E-003', 'Filtro de Óleo E2E', 'motor', 0, 4, 25.00, true)
  ON CONFLICT (sku) DO UPDATE
    SET descricao = EXCLUDED.descricao,
        categoria = EXCLUDED.categoria,
        quantidade_disponivel = EXCLUDED.quantidade_disponivel,
        estoque_minimo = EXCLUDED.estoque_minimo,
        preco_unitario = EXCLUDED.preco_unitario,
        ativo = true,
        updated_at = now();

  INSERT INTO estoque_equivalencias (sku_origem, sku_equivalente, prioridade, ativo)
  VALUES ('E2E-001', 'E2E-002', 1, true)
  ON CONFLICT (sku_origem, sku_equivalente) DO UPDATE
    SET prioridade = EXCLUDED.prioridade,
        ativo = true,
        updated_at = now();

  INSERT INTO veiculos_catalogo (
    marca,
    modelo,
    versao,
    ano_inicio,
    ano_fim,
    motor,
    codigo_motor,
    combustivel,
    chassi_inicio,
    chassi_fim,
    ativo
  )
  VALUES (
    'Volkswagen',
    'Gol',
    '1.6 MSI',
    2020,
    2023,
    '1.6',
    'CWVA',
    'flex',
    '9BWAA45U0LT000001',
    '9BWAA45U0PT999999',
    true
  )
  RETURNING id INTO v_veiculo_id;

  INSERT INTO estoque_aplicacoes (
    sku,
    veiculo_id,
    tipo_aplicacao,
    lado,
    posicao,
    codigo_oem,
    observacao_tecnica,
    requer_confirmacao_chassi,
    prioridade,
    ativo
  )
  VALUES (
    'E2E-001',
    v_veiculo_id,
    'freio',
    'dianteiro',
    'eixo_1',
    'VW-1J0698151',
    'Aplicar em conjunto completo por eixo.',
    true,
    1,
    true
  );

  INSERT INTO leads (telefone, nome, itens_interesse, status)
  VALUES ('5511999999999', 'Lead E2E', '[{"sku":"E2E-001","qtd":2}]'::jsonb, 'lead_qualificado_bot')
  RETURNING id INTO v_lead_id;

  INSERT INTO vendedores (nome, telefone, ativo)
  VALUES ('Vendedor E2E', '5511888888888', true)
  ON CONFLICT (telefone) DO UPDATE SET ativo = EXCLUDED.ativo
  RETURNING id INTO v_vendedor_id;

  INSERT INTO atendimentos (lead_id, vendedor_id, status, canal, observacoes)
  VALUES (v_lead_id, v_vendedor_id, 'em_atendimento_humano', 'whatsapp', 'Teste E2E obrigatório')
  RETURNING id INTO v_atendimento_id;

  INSERT INTO pedidos (atendimento_id, itens, subtotal, total, status)
  VALUES (
    v_atendimento_id,
    '[{"sku":"E2E-001","qtd":2,"preco_unitario":75.00}]'::jsonb,
    150.00,
    150.00,
    'rascunho'
  )
  RETURNING id INTO v_pedido_id;

  SELECT quantidade
    INTO v_reserva_qtd
  FROM estoque_reservas
  WHERE pedido_id = v_pedido_id
    AND sku = 'E2E-001'
    AND status = 'ativa';

  IF COALESCE(v_reserva_qtd, 0) <> 2 THEN
    RAISE EXCEPTION 'E2E CRM falhou: reserva de estoque não criada ao montar proposta';
  END IF;

  UPDATE pedidos
  SET pix_txid = v_txid,
      pix_copia_cola = '000201...E2E',
      status = 'aguardando_pagamento',
      updated_at = now()
  WHERE id = v_pedido_id;

  UPDATE pedidos
  SET status = 'pago',
      pago_em = now(),
      updated_at = now()
  WHERE id = v_pedido_id;

  IF NOT EXISTS (
    SELECT 1
    FROM estoque_reservas
    WHERE pedido_id = v_pedido_id
      AND sku = 'E2E-001'
      AND status = 'consumida'
  ) THEN
    RAISE EXCEPTION 'E2E CRM falhou: reserva não foi consumida após pagamento';
  END IF;

  UPDATE pedidos
  SET status = 'fechado',
      updated_at = now()
  WHERE id = v_pedido_id;

  SELECT id
    INTO v_titulo_receber_id
  FROM titulos_financeiros
  WHERE pedido_id = v_pedido_id
    AND tipo = 'receber'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_titulo_receber_id IS NULL THEN
    RAISE EXCEPTION 'E2E CRM falhou: título financeiro de contas a receber não foi criado';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM titulos_financeiros
    WHERE id = v_titulo_receber_id
      AND status = 'pago'
      AND valor_aberto = 0
  ) THEN
    RAISE EXCEPTION 'E2E CRM falhou: título financeiro não foi conciliado após fechamento/pagamento';
  END IF;

  INSERT INTO fiscal_documentos (
    pedido_id,
    atendimento_id,
    lead_id,
    tipo,
    status,
    numero,
    serie,
    valor_produtos,
    valor_total,
    emitido_em
  )
  VALUES (
    v_pedido_id,
    v_atendimento_id,
    v_lead_id,
    'nfe',
    'emitido',
    '1001',
    '1',
    150.00,
    150.00,
    now()
  )
  RETURNING id INTO v_documento_fiscal_id;

  PERFORM registrar_evento_fiscal(
    v_documento_fiscal_id,
    'autorizacao_sucesso',
    'autorizado',
    'PROTOCOLO-E2E',
    '{"status":"ok"}'::jsonb
  );

  INSERT INTO leads (telefone, nome, status, motivo_perda, ultimo_retorno_em)
  VALUES (
    '5511777777777',
    'Lead Perdido E2E',
    'perdido_nao_convertido',
    'comprou_concorrente',
    now() - interval '3 hours'
  )
  RETURNING id INTO v_lead_perdido_id;

  IF NOT EXISTS (
    SELECT 1
    FROM pedidos
    WHERE id = v_pedido_id
      AND status = 'fechado'
      AND pago_em IS NOT NULL
      AND pix_txid = v_txid
  ) THEN
    RAISE EXCEPTION 'E2E CRM falhou: pedido não chegou em fechado com pagamento confirmado';
  END IF;

  BEGIN
    INSERT INTO leads (telefone, nome, status)
    VALUES ('5511666666666', 'Lead sem motivo', 'perdido_nao_convertido');
    RAISE EXCEPTION 'E2E CRM falhou: era esperado erro de motivo_perda obrigatório';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  UPDATE pedidos
  SET status = 'aguardando_pagamento',
      etapa_entrada_em = now() - interval '3 hours',
      ultimo_retorno_em = now() - interval '3 hours',
      updated_at = now()
  WHERE id = v_pedido_id;

  SELECT count(*)
    INTO v_alertas
  FROM vw_alertas_gerente
  WHERE referencia_id = v_pedido_id
    AND tipo_alerta IN ('pedido_sem_retorno', 'pagamento_pendente');

  IF v_alertas < 1 THEN
    RAISE EXCEPTION 'E2E CRM falhou: vw_alertas_gerente não sinalizou pedido pendente';
  END IF;

  SELECT curva_abc
    INTO v_curva_sku
  FROM vw_curva_abc_giro_sku
  WHERE sku = 'E2E-001';

  IF v_curva_sku IS NULL THEN
    RAISE EXCEPTION 'E2E CRM falhou: curva ABC/giro por SKU não retornou dados';
  END IF;

  INSERT INTO leads (telefone, nome, itens_interesse, status, motivo_perda)
  VALUES (
    '5511555555555',
    'Lead sem estoque E2E',
    '[{"sku":"E2E-003","qtd":1}]'::jsonb,
    'perdido_nao_convertido',
    'sem_estoque'
  );

  SELECT count(*)
    INTO v_alerta_ruptura
  FROM vw_alerta_ruptura_estoque
  WHERE sku = 'E2E-003'
    AND severidade IN ('ruptura', 'risco_ruptura');

  IF v_alerta_ruptura < 1 THEN
    RAISE EXCEPTION 'E2E CRM falhou: alerta de ruptura com impacto não retornou para SKU sem estoque';
  END IF;

  SELECT count(*)
    INTO v_aplicacao_count
  FROM buscar_aplicacoes_veiculares('Volkswagen', 'Gol', 2021, '1.6', NULL)
  WHERE sku = 'E2E-001';

  IF v_aplicacao_count < 1 THEN
    RAISE EXCEPTION 'E2E CRM falhou: busca de aplicação veicular por marca/modelo/ano/motor não retornou SKU compatível';
  END IF;

  SELECT count(*)
    INTO v_aplicacao_por_chassi
  FROM buscar_aplicacoes_veiculares(
    'Volkswagen',
    'Gol',
    2021,
    'CWVA',
    '9BWAA45U0MT123456'
  )
  WHERE sku = 'E2E-001';

  IF v_aplicacao_por_chassi < 1 THEN
    RAISE EXCEPTION 'E2E CRM falhou: busca de aplicação veicular por chassi/código motor não retornou SKU compatível';
  END IF;

  SELECT count(*)
    INTO v_fiscal_pendente
  FROM vw_fiscal_documentos_pendentes
  WHERE documento_id = v_documento_fiscal_id
    AND acao_recomendada IN ('sincronizar_erp', 'ok');

  IF v_fiscal_pendente < 1 THEN
    RAISE EXCEPTION 'E2E CRM falhou: monitor fiscal não retornou documento autorizado';
  END IF;
END $$;

ROLLBACK;
