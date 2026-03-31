BEGIN;

DO $$
DECLARE
  v_lead_id uuid;
  v_vendedor_id uuid;
  v_atendimento_id uuid;
  v_pedido_id uuid;
  v_txid text := 'e2e-txid-' || substring(md5(clock_timestamp()::text) from 1 for 12);
BEGIN
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

  INSERT INTO pedidos (atendimento_id, total, status)
  VALUES (v_atendimento_id, 150.75, 'rascunho')
  RETURNING id INTO v_pedido_id;

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

  UPDATE pedidos
  SET status = 'fechado',
      updated_at = now()
  WHERE id = v_pedido_id;

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
END $$;

ROLLBACK;
