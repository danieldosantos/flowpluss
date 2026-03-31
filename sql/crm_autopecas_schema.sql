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
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
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
  preco_unitario numeric(14,2) NOT NULL DEFAULT 0,
  localizacao text,
  ativo boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
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
  pago_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_pedido_fechado_precisa_pago
    CHECK (status <> 'fechado' OR pago_em IS NOT NULL)
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

CREATE INDEX IF NOT EXISTS idx_leads_status_created_at ON leads(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_atendimentos_status_created_at ON atendimentos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_status_created_at ON pedidos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_pagamento ON pedidos(status, pago_em DESC);
CREATE INDEX IF NOT EXISTS idx_estoque_qtd ON estoque(quantidade_disponivel);
CREATE INDEX IF NOT EXISTS idx_status_log_entidade_evento ON status_log(entidade, entidade_id, data_evento DESC);

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

DROP TRIGGER IF EXISTS trg_pedidos_updated_at ON pedidos;
CREATE TRIGGER trg_pedidos_updated_at
BEFORE UPDATE ON pedidos
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_vendedores_updated_at ON vendedores;
CREATE TRIGGER trg_vendedores_updated_at
BEFORE UPDATE ON vendedores
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_leads_status_log ON leads;
CREATE TRIGGER trg_leads_status_log
AFTER INSERT OR UPDATE ON leads
FOR EACH ROW
EXECUTE FUNCTION log_status_change();

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

COMMIT;
