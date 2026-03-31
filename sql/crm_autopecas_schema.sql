BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'crm_status') THEN
    CREATE TYPE crm_status AS ENUM (
      'novo_lead',
      'triagem_bot',
      'dados_incompletos',
      'lead_qualificado_bot',
      'aguardando_transferencia_humano',
      'transferido_vendedor',
      'em_atendimento_humano',
      'levantamento_concluido',
      'consulta_estoque_realizada',
      'proposta_enviada',
      'negociacao',
      'pedido_criado',
      'conferencia_itens',
      'pix_gerado',
      'aguardando_pagamento',
      'pagamento_confirmado',
      'recibo_disponivel',
      'venda_fechada',
      'atendimento_finalizado',
      'perdido_nao_convertido'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pedido_status') THEN
    CREATE TYPE pedido_status AS ENUM (
      'rascunho',
      'aguardando_conferencia',
      'aguardando_pagamento',
      'pago',
      'fechado',
      'cancelado'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'recibo_tipo') THEN
    CREATE TYPE recibo_tipo AS ENUM ('provisorio', 'definitivo');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'motivo_perda') THEN
    CREATE TYPE motivo_perda AS ENUM (
      'perdido_preco',
      'sem_estoque',
      'sem_retorno',
      'comprou_concorrente'
    );
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text,
  empresa text,
  telefone text NOT NULL UNIQUE,
  estado text,
  cidade text,
  itens_interesse jsonb NOT NULL DEFAULT '[]'::jsonb,
  origem text NOT NULL DEFAULT 'whatsapp',
  status crm_status NOT NULL DEFAULT 'novo_lead',
  probabilidade_fechamento numeric(5,2) NOT NULL DEFAULT 10.00,
  etapa_pipeline text NOT NULL DEFAULT 'novo_lead',
  etapa_entrada_em timestamptz NOT NULL DEFAULT now(),
  ultimo_retorno_em timestamptz NOT NULL DEFAULT now(),
  motivo_perda motivo_perda,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_leads_probabilidade_valida
    CHECK (probabilidade_fechamento >= 0 AND probabilidade_fechamento <= 100),
  CONSTRAINT ck_leads_motivo_perda_obrigatorio
    CHECK (
      (status = 'perdido_nao_convertido' AND motivo_perda IS NOT NULL)
      OR (status <> 'perdido_nao_convertido' AND motivo_perda IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS vendedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  telefone text NOT NULL UNIQUE,
  ativo boolean NOT NULL,
  pix_chave_tipo text NOT NULL DEFAULT 'cpf',
  pix_chave_valor text NOT NULL DEFAULT '02445780012',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendedores_pix_oficial
    CHECK (pix_chave_tipo = 'cpf' AND pix_chave_valor = '02445780012')
);

CREATE TABLE IF NOT EXISTS atendimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES leads(id),
  vendedor_id uuid REFERENCES vendedores(id),
  status crm_status NOT NULL DEFAULT 'aguardando_transferencia_humano',
  etapa_entrada_em timestamptz NOT NULL DEFAULT now(),
  ultimo_retorno_em timestamptz NOT NULL DEFAULT now(),
  canal text NOT NULL DEFAULT 'whatsapp',
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS estoque (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku text NOT NULL UNIQUE,
  descricao text NOT NULL,
  categoria text,
  quantidade_disponivel integer NOT NULL DEFAULT 0,
  estoque_minimo integer NOT NULL DEFAULT 0,
  preco_unitario numeric(14,2) NOT NULL DEFAULT 0,
  localizacao text,
  ativo boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_estoque_quantidade_nao_negativa CHECK (quantidade_disponivel >= 0),
  CONSTRAINT ck_estoque_minimo_nao_negativo CHECK (estoque_minimo >= 0)
);

CREATE TABLE IF NOT EXISTS estoque_equivalencias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku_origem text NOT NULL REFERENCES estoque(sku) ON DELETE CASCADE,
  sku_equivalente text NOT NULL REFERENCES estoque(sku) ON DELETE CASCADE,
  prioridade smallint NOT NULL DEFAULT 1,
  observacao text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_estoque_equivalencias_skus_distintos CHECK (sku_origem <> sku_equivalente),
  CONSTRAINT uk_estoque_equivalencias UNIQUE (sku_origem, sku_equivalente)
);

CREATE TABLE IF NOT EXISTS pedidos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atendimento_id uuid NOT NULL REFERENCES atendimentos(id),
  cliente_nome text,
  cliente_empresa text,
  itens jsonb NOT NULL DEFAULT '[]'::jsonb,
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  frete numeric(14,2) NOT NULL DEFAULT 0,
  descontos numeric(14,2) NOT NULL DEFAULT 0,
  total numeric(14,2) NOT NULL DEFAULT 0,
  status pedido_status NOT NULL DEFAULT 'rascunho',
  pix_txid text,
  pix_copia_cola text,
  etapa_entrada_em timestamptz NOT NULL DEFAULT now(),
  ultimo_retorno_em timestamptz NOT NULL DEFAULT now(),
  pago_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_pedido_fechado_precisa_pago
    CHECK (status <> 'fechado' OR pago_em IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS conciliacoes_pix (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  pix_txid text NOT NULL,
  valor_cobrado numeric(14,2) NOT NULL,
  valor_pago numeric(14,2) NOT NULL,
  tolerancia_abs numeric(14,2) NOT NULL DEFAULT 0.50,
  diferenca_valor numeric(14,2) NOT NULL,
  status_conciliacao text NOT NULL DEFAULT 'pendente',
  pago_em timestamptz NOT NULL DEFAULT now(),
  payload_gateway jsonb NOT NULL DEFAULT '{}'::jsonb,
  conciliado_por text NOT NULL DEFAULT 'system',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_conciliacoes_pix_status_valido
    CHECK (status_conciliacao IN ('conciliado', 'divergente', 'pendente')),
  CONSTRAINT ck_conciliacoes_pix_valores_nao_negativos
    CHECK (valor_cobrado >= 0 AND valor_pago >= 0 AND tolerancia_abs >= 0)
);

CREATE TABLE IF NOT EXISTS estoque_reservas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  sku text NOT NULL REFERENCES estoque(sku),
  quantidade integer NOT NULL,
  status text NOT NULL DEFAULT 'ativa',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_estoque_reservas_qtd_positiva CHECK (quantidade > 0),
  CONSTRAINT ck_estoque_reservas_status_valido CHECK (status IN ('ativa', 'consumida', 'liberada')),
  CONSTRAINT uk_estoque_reserva_item UNIQUE (pedido_id, sku)
);

CREATE TABLE IF NOT EXISTS recibos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid NOT NULL REFERENCES pedidos(id),
  tipo recibo_tipo NOT NULL,
  arquivo_url text NOT NULL,
  gerado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS status_log (
  id bigserial PRIMARY KEY,
  entidade text NOT NULL,
  entidade_id uuid NOT NULL,
  de_status text,
  para_status text NOT NULL,
  usuario text NOT NULL DEFAULT 'system',
  data_evento timestamptz NOT NULL DEFAULT now(),
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS auditoria_comercial (
  id bigserial PRIMARY KEY,
  entidade text NOT NULL CHECK (entidade IN ('pedidos', 'estoque')),
  entidade_id uuid NOT NULL,
  campo text NOT NULL,
  valor_anterior text,
  valor_novo text,
  alterado_por text NOT NULL DEFAULT 'system',
  data_evento timestamptz NOT NULL DEFAULT now(),
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS regua_cobranca (
  id bigserial PRIMARY KEY,
  pedido_id uuid NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  etapa smallint NOT NULL,
  canal text NOT NULL DEFAULT 'whatsapp',
  template text NOT NULL,
  agendado_para timestamptz NOT NULL,
  executado_em timestamptz,
  status text NOT NULL DEFAULT 'pendente',
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_regua_cobranca_etapa_valida CHECK (etapa BETWEEN 1 AND 5),
  CONSTRAINT ck_regua_cobranca_status_valido CHECK (status IN ('pendente', 'enviado', 'cancelado', 'erro')),
  CONSTRAINT uk_regua_cobranca_etapa UNIQUE (pedido_id, etapa)
);

CREATE TABLE IF NOT EXISTS pipeline_etapas (
  id bigserial PRIMARY KEY,
  entidade text NOT NULL CHECK (entidade IN ('leads', 'atendimentos', 'pedidos')),
  etapa text NOT NULL,
  probabilidade_padrao numeric(5,2) NOT NULL DEFAULT 0,
  sla_minutos integer NOT NULL,
  alerta_gerente boolean NOT NULL DEFAULT true,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uk_pipeline_etapas UNIQUE (entidade, etapa),
  CONSTRAINT ck_pipeline_probabilidade_valida CHECK (
    probabilidade_padrao >= 0 AND probabilidade_padrao <= 100
  ),
  CONSTRAINT ck_pipeline_sla_positivo CHECK (sla_minutos > 0)
);

CREATE INDEX IF NOT EXISTS idx_leads_status_created_at ON leads(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_atendimentos_status_created_at ON atendimentos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_status_created_at ON pedidos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_pagamento ON pedidos(status, pago_em DESC);
CREATE INDEX IF NOT EXISTS idx_estoque_qtd ON estoque(quantidade_disponivel);
CREATE INDEX IF NOT EXISTS idx_estoque_equivalencias_origem ON estoque_equivalencias(sku_origem, ativo, prioridade);
CREATE INDEX IF NOT EXISTS idx_estoque_reservas_lookup ON estoque_reservas(pedido_id, status, sku);
CREATE INDEX IF NOT EXISTS idx_status_log_entidade_evento ON status_log(entidade, entidade_id, data_evento DESC);
CREATE INDEX IF NOT EXISTS idx_conciliacoes_pix_txid ON conciliacoes_pix(pix_txid, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conciliacoes_pix_status ON conciliacoes_pix(status_conciliacao, pago_em DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_comercial_busca ON auditoria_comercial(entidade, entidade_id, data_evento DESC);
CREATE INDEX IF NOT EXISTS idx_regua_cobranca_status_agenda ON regua_cobranca(status, agendado_para);
CREATE INDEX IF NOT EXISTS idx_pipeline_etapas_lookup ON pipeline_etapas(entidade, etapa, ativo);
CREATE INDEX IF NOT EXISTS idx_leads_sla_monitoria ON leads(status, etapa_entrada_em, ultimo_retorno_em);
CREATE INDEX IF NOT EXISTS idx_pedidos_sla_monitoria ON pedidos(status, etapa_entrada_em, ultimo_retorno_em);
CREATE INDEX IF NOT EXISTS idx_atendimentos_sla_monitoria ON atendimentos(status, etapa_entrada_em, ultimo_retorno_em);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_status_change()
RETURNS trigger AS $$
DECLARE
  old_status text;
  new_status text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    old_status := NULL;
    new_status := NEW.status::text;
  ELSE
    old_status := OLD.status::text;
    new_status := NEW.status::text;
  END IF;

  IF old_status IS DISTINCT FROM new_status THEN
    INSERT INTO status_log(entidade, entidade_id, de_status, para_status, usuario, detalhes)
    VALUES (
      TG_TABLE_NAME,
      NEW.id,
      old_status,
      new_status,
      COALESCE(current_setting('app.user', true), 'system'),
      jsonb_build_object('trigger_op', TG_OP)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_auditoria_comercial()
RETURNS trigger AS $$
DECLARE
  v_usuario text := COALESCE(current_setting('app.user', true), 'system');
BEGIN
  IF TG_TABLE_NAME = 'pedidos' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES ('pedidos', NEW.id, 'status', OLD.status::text, NEW.status::text, v_usuario, jsonb_build_object('trigger_op', TG_OP));
    END IF;

    IF NEW.descontos IS DISTINCT FROM OLD.descontos THEN
      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES ('pedidos', NEW.id, 'descontos', OLD.descontos::text, NEW.descontos::text, v_usuario, jsonb_build_object('trigger_op', TG_OP));
    END IF;

    IF NEW.subtotal IS DISTINCT FROM OLD.subtotal THEN
      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES ('pedidos', NEW.id, 'subtotal', OLD.subtotal::text, NEW.subtotal::text, v_usuario, jsonb_build_object('trigger_op', TG_OP));
    END IF;

    IF NEW.total IS DISTINCT FROM OLD.total THEN
      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES ('pedidos', NEW.id, 'total', OLD.total::text, NEW.total::text, v_usuario, jsonb_build_object('trigger_op', TG_OP));
    END IF;
  ELSIF TG_TABLE_NAME = 'estoque' THEN
    IF NEW.preco_unitario IS DISTINCT FROM OLD.preco_unitario THEN
      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES ('estoque', NEW.id, 'preco_unitario', OLD.preco_unitario::text, NEW.preco_unitario::text, v_usuario, jsonb_build_object('sku', NEW.sku, 'trigger_op', TG_OP));
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION touch_stage_dates()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.etapa_entrada_em := COALESCE(NEW.etapa_entrada_em, now());
    NEW.ultimo_retorno_em := COALESCE(NEW.ultimo_retorno_em, now());
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.etapa_entrada_em := now();
  END IF;

  IF NEW.updated_at IS DISTINCT FROM OLD.updated_at THEN
    NEW.ultimo_retorno_em := now();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW vw_alertas_gerente AS
WITH cfg AS (
  SELECT entidade, etapa, sla_minutos
  FROM pipeline_etapas
  WHERE ativo = true
    AND alerta_gerente = true
),
lead_parado AS (
  SELECT
    'lead_parado'::text AS tipo_alerta,
    l.id AS referencia_id,
    l.status::text AS etapa,
    l.ultimo_retorno_em AS referencia_tempo,
    EXTRACT(EPOCH FROM (now() - l.ultimo_retorno_em)) / 60.0 AS minutos_em_aberto
  FROM leads l
  JOIN cfg c
    ON c.entidade = 'leads'
   AND c.etapa = l.status::text
  WHERE l.status <> 'perdido_nao_convertido'
    AND l.ultimo_retorno_em < now() - make_interval(mins => c.sla_minutos)
),
pedido_sem_retorno AS (
  SELECT
    'pedido_sem_retorno'::text AS tipo_alerta,
    p.id AS referencia_id,
    p.status::text AS etapa,
    p.ultimo_retorno_em AS referencia_tempo,
    EXTRACT(EPOCH FROM (now() - p.ultimo_retorno_em)) / 60.0 AS minutos_em_aberto
  FROM pedidos p
  JOIN cfg c
    ON c.entidade = 'pedidos'
   AND c.etapa = p.status::text
  WHERE p.status IN ('rascunho', 'aguardando_conferencia', 'aguardando_pagamento')
    AND p.ultimo_retorno_em < now() - make_interval(mins => c.sla_minutos)
),
pagamento_pendente AS (
  SELECT
    'pagamento_pendente'::text AS tipo_alerta,
    p.id AS referencia_id,
    p.status::text AS etapa,
    p.etapa_entrada_em AS referencia_tempo,
    EXTRACT(EPOCH FROM (now() - p.etapa_entrada_em)) / 60.0 AS minutos_em_aberto
  FROM pedidos p
  JOIN cfg c
    ON c.entidade = 'pedidos'
   AND c.etapa = p.status::text
  WHERE p.status = 'aguardando_pagamento'
    AND p.etapa_entrada_em < now() - make_interval(mins => c.sla_minutos)
)
SELECT * FROM lead_parado
UNION ALL
SELECT * FROM pedido_sem_retorno
UNION ALL
SELECT * FROM pagamento_pendente;

CREATE OR REPLACE FUNCTION refresh_reservas_pedido(p_pedido_id uuid)
RETURNS void AS $$
DECLARE
  v_status pedido_status;
BEGIN
  SELECT status
    INTO v_status
  FROM pedidos
  WHERE id = p_pedido_id;

  IF v_status IS NULL THEN
    RETURN;
  END IF;

  IF v_status IN ('rascunho', 'aguardando_conferencia', 'aguardando_pagamento') THEN
    WITH itens AS (
      SELECT
        p.id AS pedido_id,
        trim(i.sku) AS sku,
        GREATEST(COALESCE(i.qtd, 0), 0)::integer AS quantidade
      FROM pedidos p
      CROSS JOIN LATERAL jsonb_to_recordset(COALESCE(p.itens, '[]'::jsonb))
        AS i(sku text, qtd numeric)
      WHERE p.id = p_pedido_id
        AND NULLIF(trim(i.sku), '') IS NOT NULL
        AND COALESCE(i.qtd, 0) > 0
    )
    INSERT INTO estoque_reservas (pedido_id, sku, quantidade, status)
    SELECT pedido_id, sku, quantidade, 'ativa'
    FROM itens
    ON CONFLICT (pedido_id, sku) DO UPDATE
      SET quantidade = EXCLUDED.quantidade,
          status = 'ativa',
          updated_at = now();

    UPDATE estoque_reservas r
    SET status = 'liberada',
        updated_at = now()
    WHERE r.pedido_id = p_pedido_id
      AND r.status = 'ativa'
      AND NOT EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(
               COALESCE((SELECT itens FROM pedidos WHERE id = p_pedido_id), '[]'::jsonb)
             ) AS i(sku text, qtd numeric)
        WHERE trim(i.sku) = r.sku
          AND COALESCE(i.qtd, 0) > 0
      );
  ELSIF v_status = 'pago' THEN
    UPDATE estoque_reservas
    SET status = 'consumida',
        updated_at = now()
    WHERE pedido_id = p_pedido_id
      AND status = 'ativa';
  ELSE
    UPDATE estoque_reservas
    SET status = 'liberada',
        updated_at = now()
    WHERE pedido_id = p_pedido_id
      AND status = 'ativa';
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_refresh_reservas_pedido()
RETURNS trigger AS $$
BEGIN
  PERFORM refresh_reservas_pedido(NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gerar_regua_cobranca_padrao(p_pedido_id uuid, p_base timestamptz)
RETURNS void AS $$
BEGIN
  INSERT INTO regua_cobranca (pedido_id, etapa, canal, template, agendado_para, status)
  VALUES
    (p_pedido_id, 1, 'whatsapp', 'cobranca_d0', COALESCE(p_base, now()), 'pendente'),
    (p_pedido_id, 2, 'whatsapp', 'cobranca_d1', COALESCE(p_base, now()) + interval '1 day', 'pendente'),
    (p_pedido_id, 3, 'whatsapp', 'cobranca_d3', COALESCE(p_base, now()) + interval '3 days', 'pendente'),
    (p_pedido_id, 4, 'whatsapp', 'cobranca_d7', COALESCE(p_base, now()) + interval '7 days', 'pendente'),
    (p_pedido_id, 5, 'humano', 'escalonamento_financeiro', COALESCE(p_base, now()) + interval '10 days', 'pendente')
  ON CONFLICT (pedido_id, etapa) DO UPDATE
  SET agendado_para = EXCLUDED.agendado_para,
      template = EXCLUDED.template,
      canal = EXCLUDED.canal,
      status = CASE
        WHEN regua_cobranca.status IN ('enviado', 'cancelado') THEN regua_cobranca.status
        ELSE 'pendente'
      END,
      updated_at = now();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_sync_regua_cobranca()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'aguardando_pagamento' THEN
    PERFORM gerar_regua_cobranca_padrao(NEW.id, NEW.etapa_entrada_em);
  ELSE
    UPDATE regua_cobranca
    SET status = 'cancelado',
        updated_at = now()
    WHERE pedido_id = NEW.id
      AND status = 'pendente';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION conciliar_pix_automatico(
  p_pix_txid text,
  p_valor_pago numeric,
  p_pago_em timestamptz DEFAULT now(),
  p_tolerancia_abs numeric DEFAULT 0.50,
  p_payload_gateway jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid AS $$
DECLARE
  v_pedido pedidos%ROWTYPE;
  v_diff numeric(14,2);
  v_status text;
  v_conciliacao_id uuid;
  v_usuario text := COALESCE(current_setting('app.user', true), 'system');
BEGIN
  SELECT *
    INTO v_pedido
  FROM pedidos
  WHERE pix_txid = p_pix_txid
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_pedido.id IS NULL THEN
    RAISE EXCEPTION 'Nenhum pedido encontrado para txid %', p_pix_txid;
  END IF;

  v_diff := round(abs(COALESCE(v_pedido.total, 0) - COALESCE(p_valor_pago, 0)), 2);
  v_status := CASE WHEN v_diff <= COALESCE(p_tolerancia_abs, 0.50) THEN 'conciliado' ELSE 'divergente' END;

  INSERT INTO conciliacoes_pix (
    pedido_id, pix_txid, valor_cobrado, valor_pago, tolerancia_abs, diferenca_valor,
    status_conciliacao, pago_em, payload_gateway, conciliado_por
  )
  VALUES (
    v_pedido.id, p_pix_txid, COALESCE(v_pedido.total, 0), COALESCE(p_valor_pago, 0), COALESCE(p_tolerancia_abs, 0.50), v_diff,
    v_status, COALESCE(p_pago_em, now()), COALESCE(p_payload_gateway, '{}'::jsonb), v_usuario
  )
  RETURNING id INTO v_conciliacao_id;

  IF v_status = 'conciliado' THEN
    UPDATE pedidos
    SET status = 'pago',
        pago_em = COALESCE(p_pago_em, now()),
        ultimo_retorno_em = now(),
        updated_at = now()
    WHERE id = v_pedido.id
      AND status IN ('aguardando_pagamento', 'aguardando_conferencia', 'rascunho');
  END IF;

  RETURN v_conciliacao_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW vw_estoque_disponibilidade AS
SELECT
  e.sku,
  e.descricao,
  e.categoria,
  e.quantidade_disponivel,
  COALESCE(SUM(CASE WHEN r.status = 'ativa' THEN r.quantidade ELSE 0 END), 0)::integer AS quantidade_reservada,
  GREATEST(
    e.quantidade_disponivel - COALESCE(SUM(CASE WHEN r.status = 'ativa' THEN r.quantidade ELSE 0 END), 0)::integer,
    0
  ) AS quantidade_livre,
  e.estoque_minimo,
  e.preco_unitario,
  e.localizacao,
  e.ativo,
  e.updated_at
FROM estoque e
LEFT JOIN estoque_reservas r
  ON r.sku = e.sku
GROUP BY
  e.sku, e.descricao, e.categoria, e.quantidade_disponivel, e.estoque_minimo,
  e.preco_unitario, e.localizacao, e.ativo, e.updated_at;

CREATE OR REPLACE VIEW vw_sugestoes_equivalentes AS
WITH base AS (
  SELECT
    d.sku AS sku_origem,
    d.quantidade_livre,
    d.preco_unitario
  FROM vw_estoque_disponibilidade d
)
SELECT
  eq.sku_origem,
  eq.sku_equivalente,
  est_eq.descricao AS descricao_equivalente,
  est_eq.categoria AS categoria_equivalente,
  eq.prioridade,
  eq.observacao,
  disp_eq.quantidade_livre AS estoque_livre_equivalente,
  est_eq.preco_unitario AS preco_equivalente,
  CASE
    WHEN base.preco_unitario > 0 THEN round(((est_eq.preco_unitario - base.preco_unitario) / base.preco_unitario) * 100, 2)
    ELSE NULL
  END AS variacao_preco_percentual
FROM estoque_equivalencias eq
JOIN estoque est_eq
  ON est_eq.sku = eq.sku_equivalente
LEFT JOIN vw_estoque_disponibilidade disp_eq
  ON disp_eq.sku = eq.sku_equivalente
LEFT JOIN base
  ON base.sku_origem = eq.sku_origem
WHERE eq.ativo = true
  AND est_eq.ativo = true;

CREATE OR REPLACE VIEW vw_curva_abc_giro_sku AS
WITH vendas AS (
  SELECT
    trim(i.sku) AS sku,
    SUM(GREATEST(COALESCE(i.qtd, 0), 0))::numeric AS qtd_vendida_90d,
    SUM(GREATEST(COALESCE(i.qtd, 0), 0) * GREATEST(COALESCE(i.preco_unitario, 0), 0))::numeric AS receita_90d
  FROM pedidos p
  CROSS JOIN LATERAL jsonb_to_recordset(COALESCE(p.itens, '[]'::jsonb))
    AS i(sku text, qtd numeric, preco_unitario numeric)
  WHERE p.status IN ('pago', 'fechado')
    AND p.pago_em >= now() - interval '90 days'
    AND NULLIF(trim(i.sku), '') IS NOT NULL
  GROUP BY trim(i.sku)
),
combinado AS (
  SELECT
    e.sku,
    e.descricao,
    e.categoria,
    COALESCE(v.qtd_vendida_90d, 0) AS qtd_vendida_90d,
    COALESCE(v.receita_90d, 0) AS receita_90d,
    e.quantidade_disponivel,
    COALESCE(v.qtd_vendida_90d, 0) / 3.0 AS giro_mensal_estimado
  FROM estoque e
  LEFT JOIN vendas v ON v.sku = e.sku
  WHERE e.ativo = true
),
ranqueado AS (
  SELECT
    c.*,
    SUM(c.receita_90d) OVER () AS receita_total,
    SUM(c.receita_90d) OVER (ORDER BY c.receita_90d DESC, c.sku) AS receita_acumulada
  FROM combinado c
)
SELECT
  r.sku,
  r.descricao,
  r.categoria,
  r.qtd_vendida_90d,
  r.receita_90d,
  round(r.giro_mensal_estimado, 2) AS giro_mensal_estimado,
  r.quantidade_disponivel,
  CASE
    WHEN r.receita_total <= 0 THEN 'C'
    WHEN r.receita_acumulada / r.receita_total <= 0.80 THEN 'A'
    WHEN r.receita_acumulada / r.receita_total <= 0.95 THEN 'B'
    ELSE 'C'
  END AS curva_abc,
  CASE
    WHEN r.giro_mensal_estimado <= 0 THEN NULL
    ELSE round(r.quantidade_disponivel / r.giro_mensal_estimado, 2)
  END AS cobertura_meses_estimada
FROM ranqueado r;

CREATE OR REPLACE VIEW vw_alerta_ruptura_estoque AS
WITH demanda AS (
  SELECT
    sku,
    qtd_vendida_90d / 3.0 AS demanda_mensal_estimada,
    receita_90d / 3.0 AS receita_mensal_estimada
  FROM vw_curva_abc_giro_sku
),
impacto_sem_estoque AS (
  SELECT
    l.id AS lead_id,
    i->>'sku' AS sku,
    COALESCE((i->>'qtd')::numeric, 0) AS qtd_solicitada
  FROM leads l
  CROSS JOIN LATERAL jsonb_array_elements(COALESCE(l.itens_interesse, '[]'::jsonb)) AS i
  WHERE l.created_at >= now() - interval '30 days'
    AND l.status = 'perdido_nao_convertido'
    AND l.motivo_perda = 'sem_estoque'
    AND NULLIF(trim(i->>'sku'), '') IS NOT NULL
)
SELECT
  d.sku,
  e.descricao,
  e.categoria,
  e.quantidade_disponivel,
  e.estoque_minimo,
  round(COALESCE(dm.demanda_mensal_estimada, 0), 2) AS demanda_mensal_estimada,
  round(COALESCE(dm.receita_mensal_estimada, 0), 2) AS receita_mensal_estimada,
  COUNT(DISTINCT isq.lead_id)::integer AS leads_perdidos_sem_estoque_30d,
  round(COALESCE(SUM(isq.qtd_solicitada), 0), 2) AS qtd_perdida_30d,
  round(COALESCE(SUM(isq.qtd_solicitada * e.preco_unitario), 0), 2) AS receita_perdida_30d,
  CASE
    WHEN d.quantidade_livre <= 0 THEN 'ruptura'
    WHEN d.quantidade_livre < GREATEST(e.estoque_minimo, COALESCE(dm.demanda_mensal_estimada, 0)) THEN 'risco_ruptura'
    ELSE 'ok'
  END AS severidade
FROM vw_estoque_disponibilidade d
JOIN estoque e
  ON e.sku = d.sku
LEFT JOIN demanda dm
  ON dm.sku = d.sku
LEFT JOIN impacto_sem_estoque isq
  ON isq.sku = d.sku
WHERE e.ativo = true
GROUP BY
  d.sku, e.descricao, e.categoria, e.quantidade_disponivel, e.estoque_minimo,
  d.quantidade_livre, dm.demanda_mensal_estimada, dm.receita_mensal_estimada
HAVING d.quantidade_livre <= 0
   OR d.quantidade_livre < GREATEST(e.estoque_minimo, COALESCE(dm.demanda_mensal_estimada, 0));

CREATE OR REPLACE VIEW vw_inadimplencia_pedidos AS
WITH ult_cobranca AS (
  SELECT DISTINCT ON (r.pedido_id)
    r.pedido_id,
    r.etapa,
    r.status AS status_cobranca,
    r.agendado_para,
    r.executado_em
  FROM regua_cobranca r
  ORDER BY r.pedido_id, r.etapa DESC
)
SELECT
  p.id AS pedido_id,
  p.atendimento_id,
  p.status,
  p.total,
  p.etapa_entrada_em AS inicio_espera_pagamento,
  EXTRACT(EPOCH FROM (now() - p.etapa_entrada_em)) / 3600.0 AS horas_em_aberto,
  COALESCE(uc.etapa, 0) AS ultima_etapa_cobranca,
  uc.status_cobranca,
  uc.agendado_para AS proxima_acao_cobranca_em,
  CASE
    WHEN p.status <> 'aguardando_pagamento' THEN 'adimplente'
    WHEN now() - p.etapa_entrada_em < interval '24 hours' THEN 'risco_baixo'
    WHEN now() - p.etapa_entrada_em < interval '72 hours' THEN 'risco_moderado'
    ELSE 'inadimplente'
  END AS nivel_inadimplencia
FROM pedidos p
LEFT JOIN ult_cobranca uc
  ON uc.pedido_id = p.id
WHERE p.status IN ('aguardando_pagamento', 'pago', 'fechado');

DROP TRIGGER IF EXISTS trg_leads_updated_at ON leads;
CREATE TRIGGER trg_leads_updated_at
BEFORE UPDATE ON leads
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_atendimentos_updated_at ON atendimentos;
CREATE TRIGGER trg_atendimentos_updated_at
BEFORE UPDATE ON atendimentos
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_atendimentos_stage_dates ON atendimentos;
CREATE TRIGGER trg_atendimentos_stage_dates
BEFORE INSERT OR UPDATE ON atendimentos
FOR EACH ROW
EXECUTE FUNCTION touch_stage_dates();

DROP TRIGGER IF EXISTS trg_pedidos_updated_at ON pedidos;
CREATE TRIGGER trg_pedidos_updated_at
BEFORE UPDATE ON pedidos
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_pedidos_stage_dates ON pedidos;
CREATE TRIGGER trg_pedidos_stage_dates
BEFORE INSERT OR UPDATE ON pedidos
FOR EACH ROW
EXECUTE FUNCTION touch_stage_dates();

DROP TRIGGER IF EXISTS trg_vendedores_updated_at ON vendedores;
CREATE TRIGGER trg_vendedores_updated_at
BEFORE UPDATE ON vendedores
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_estoque_updated_at ON estoque;
CREATE TRIGGER trg_estoque_updated_at
BEFORE UPDATE ON estoque
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_estoque_auditoria_comercial ON estoque;
CREATE TRIGGER trg_estoque_auditoria_comercial
AFTER UPDATE OF preco_unitario ON estoque
FOR EACH ROW
EXECUTE FUNCTION log_auditoria_comercial();

DROP TRIGGER IF EXISTS trg_estoque_equivalencias_updated_at ON estoque_equivalencias;
CREATE TRIGGER trg_estoque_equivalencias_updated_at
BEFORE UPDATE ON estoque_equivalencias
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_estoque_reservas_updated_at ON estoque_reservas;
CREATE TRIGGER trg_estoque_reservas_updated_at
BEFORE UPDATE ON estoque_reservas
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_leads_status_log ON leads;
CREATE TRIGGER trg_leads_status_log
AFTER INSERT OR UPDATE ON leads
FOR EACH ROW
EXECUTE FUNCTION log_status_change();

DROP TRIGGER IF EXISTS trg_leads_stage_dates ON leads;
CREATE TRIGGER trg_leads_stage_dates
BEFORE INSERT OR UPDATE ON leads
FOR EACH ROW
EXECUTE FUNCTION touch_stage_dates();

DROP TRIGGER IF EXISTS trg_atendimentos_status_log ON atendimentos;
CREATE TRIGGER trg_atendimentos_status_log
AFTER INSERT OR UPDATE ON atendimentos
FOR EACH ROW
EXECUTE FUNCTION log_status_change();

DROP TRIGGER IF EXISTS trg_pedidos_status_log ON pedidos;
CREATE TRIGGER trg_pedidos_status_log
AFTER INSERT OR UPDATE ON pedidos
FOR EACH ROW
EXECUTE FUNCTION log_status_change();

DROP TRIGGER IF EXISTS trg_pedidos_auditoria_comercial ON pedidos;
CREATE TRIGGER trg_pedidos_auditoria_comercial
AFTER UPDATE OF status, subtotal, descontos, total ON pedidos
FOR EACH ROW
EXECUTE FUNCTION log_auditoria_comercial();

DROP TRIGGER IF EXISTS trg_pedidos_refresh_reservas ON pedidos;
CREATE TRIGGER trg_pedidos_refresh_reservas
AFTER INSERT OR UPDATE OF itens, status ON pedidos
FOR EACH ROW
EXECUTE FUNCTION trg_refresh_reservas_pedido();

DROP TRIGGER IF EXISTS trg_pedidos_sync_regua_cobranca ON pedidos;
CREATE TRIGGER trg_pedidos_sync_regua_cobranca
AFTER INSERT OR UPDATE OF status, etapa_entrada_em ON pedidos
FOR EACH ROW
EXECUTE FUNCTION trg_sync_regua_cobranca();

INSERT INTO pipeline_etapas (entidade, etapa, probabilidade_padrao, sla_minutos, alerta_gerente)
VALUES
  ('leads', 'novo_lead', 10, 15, true),
  ('leads', 'lead_qualificado_bot', 25, 30, true),
  ('leads', 'transferido_vendedor', 40, 30, true),
  ('leads', 'em_atendimento_humano', 55, 45, true),
  ('leads', 'proposta_enviada', 70, 60, true),
  ('leads', 'negociacao', 80, 90, true),
  ('leads', 'pedido_criado', 90, 60, true),
  ('leads', 'venda_fechada', 100, 1440, false),
  ('pedidos', 'rascunho', 60, 30, true),
  ('pedidos', 'aguardando_conferencia', 75, 30, true),
  ('pedidos', 'aguardando_pagamento', 85, 120, true),
  ('pedidos', 'pago', 95, 60, false),
  ('pedidos', 'fechado', 100, 1440, false)
ON CONFLICT (entidade, etapa) DO UPDATE
SET probabilidade_padrao = EXCLUDED.probabilidade_padrao,
    sla_minutos = EXCLUDED.sla_minutos,
    alerta_gerente = EXCLUDED.alerta_gerente,
    ativo = true,
    updated_at = now();

COMMIT;
