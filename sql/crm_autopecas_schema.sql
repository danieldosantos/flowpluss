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

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_venda_tipo') THEN
    CREATE TYPE pos_venda_tipo AS ENUM (
      'garantia',
      'devolucao_troca',
      'recall',
      'manutencao',
      'recompra'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pos_venda_status') THEN
    CREATE TYPE pos_venda_status AS ENUM (
      'aberto',
      'em_analise',
      'aprovado',
      'rejeitado',
      'em_execucao',
      'concluido',
      'cancelado'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'documento_fiscal_tipo') THEN
    CREATE TYPE documento_fiscal_tipo AS ENUM ('nfe', 'nfce', 'nfse', 'cte');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'documento_fiscal_status') THEN
    CREATE TYPE documento_fiscal_status AS ENUM (
      'rascunho',
      'pendente_emissao',
      'emitido',
      'autorizado',
      'denegado',
      'cancelado',
      'inutilizado',
      'erro'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'titulo_tipo') THEN
    CREATE TYPE titulo_tipo AS ENUM ('receber', 'pagar');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'titulo_status') THEN
    CREATE TYPE titulo_status AS ENUM ('aberto', 'parcial', 'pago', 'vencido', 'cancelado');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS empresas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo text NOT NULL UNIQUE,
  nome text NOT NULL,
  documento text,
  ativa boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS filiais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  codigo text NOT NULL,
  nome text NOT NULL,
  cidade text,
  estado text,
  ativa boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uk_filiais_empresa_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uk_filiais_id_empresa UNIQUE (id, empresa_id)
);

CREATE TABLE IF NOT EXISTS leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  filial_id uuid NOT NULL,
  nome text,
  empresa text,
  telefone text NOT NULL UNIQUE,
  tipo_cliente text NOT NULL DEFAULT 'varejo',
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
  CONSTRAINT ck_leads_tipo_cliente_valido
    CHECK (tipo_cliente IN ('varejo', 'atacado', 'frota', 'oficina', 'seguradora', 'distribuidor')),
  CONSTRAINT ck_leads_motivo_perda_obrigatorio
    CHECK (
      (status = 'perdido_nao_convertido' AND motivo_perda IS NOT NULL)
      OR (status <> 'perdido_nao_convertido' AND motivo_perda IS NULL)
    ),
  CONSTRAINT fk_leads_empresa FOREIGN KEY (empresa_id) REFERENCES empresas(id),
  CONSTRAINT fk_leads_filial_empresa FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id)
);

CREATE TABLE IF NOT EXISTS vendedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  telefone text NOT NULL UNIQUE,
  ativo boolean NOT NULL,
  pix_chave_tipo text NOT NULL DEFAULT 'cpf',
  pix_chave_valor text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_vendedores_pix_tipo_valido
    CHECK (pix_chave_tipo IN ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria')),
  CONSTRAINT ck_vendedores_pix_chave_preenchida
    CHECK (length(trim(pix_chave_valor)) >= 3)
);

CREATE TABLE IF NOT EXISTS atendimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  filial_id uuid NOT NULL,
  lead_id uuid NOT NULL REFERENCES leads(id),
  vendedor_id uuid REFERENCES vendedores(id),
  status crm_status NOT NULL DEFAULT 'aguardando_transferencia_humano',
  etapa_entrada_em timestamptz NOT NULL DEFAULT now(),
  ultimo_retorno_em timestamptz NOT NULL DEFAULT now(),
  canal text NOT NULL DEFAULT 'whatsapp',
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fk_atendimentos_empresa FOREIGN KEY (empresa_id) REFERENCES empresas(id),
  CONSTRAINT fk_atendimentos_filial_empresa FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id)
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

CREATE TABLE IF NOT EXISTS veiculos_catalogo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  marca text NOT NULL,
  modelo text NOT NULL,
  versao text,
  ano_inicio integer NOT NULL,
  ano_fim integer,
  motor text,
  codigo_motor text,
  combustivel text,
  chassi_inicio text,
  chassi_fim text,
  observacoes text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_veiculos_catalogo_ano_inicio_valido CHECK (ano_inicio BETWEEN 1950 AND 2100),
  CONSTRAINT ck_veiculos_catalogo_ano_fim_valido CHECK (ano_fim IS NULL OR ano_fim BETWEEN 1950 AND 2100),
  CONSTRAINT ck_veiculos_catalogo_faixa_anos_valida CHECK (ano_fim IS NULL OR ano_fim >= ano_inicio),
  CONSTRAINT ck_veiculos_catalogo_chassi_faixa_valida CHECK (
    chassi_inicio IS NULL
    OR chassi_fim IS NULL
    OR chassi_fim >= chassi_inicio
  )
);

CREATE TABLE IF NOT EXISTS estoque_aplicacoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku text NOT NULL REFERENCES estoque(sku) ON DELETE CASCADE,
  veiculo_id uuid NOT NULL REFERENCES veiculos_catalogo(id) ON DELETE CASCADE,
  tipo_aplicacao text,
  lado text,
  posicao text,
  codigo_oem text,
  observacao_tecnica text,
  requer_confirmacao_chassi boolean NOT NULL DEFAULT false,
  prioridade smallint NOT NULL DEFAULT 1,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_estoque_aplicacoes_prioridade_valida CHECK (prioridade BETWEEN 1 AND 10),
  CONSTRAINT uk_estoque_aplicacoes UNIQUE (sku, veiculo_id, tipo_aplicacao, lado, posicao, codigo_oem)
);

CREATE TABLE IF NOT EXISTS pedidos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  filial_id uuid NOT NULL,
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
    CHECK (status <> 'fechado' OR pago_em IS NOT NULL),
  CONSTRAINT fk_pedidos_empresa FOREIGN KEY (empresa_id) REFERENCES empresas(id),
  CONSTRAINT fk_pedidos_filial_empresa FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id)
);

CREATE TABLE IF NOT EXISTS fiscal_documentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  atendimento_id uuid REFERENCES atendimentos(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES leads(id) ON DELETE SET NULL,
  tipo documento_fiscal_tipo NOT NULL,
  status documento_fiscal_status NOT NULL DEFAULT 'rascunho',
  numero text,
  serie text,
  chave_acesso text UNIQUE,
  protocolo_autorizacao text,
  ambiente text NOT NULL DEFAULT 'homologacao' CHECK (ambiente IN ('homologacao', 'producao')),
  emissor_cnpj text,
  destinatario_doc text,
  valor_produtos numeric(14,2) NOT NULL DEFAULT 0,
  valor_desconto numeric(14,2) NOT NULL DEFAULT 0,
  valor_frete numeric(14,2) NOT NULL DEFAULT 0,
  valor_total numeric(14,2) NOT NULL DEFAULT 0,
  xml_url text,
  pdf_url text,
  payload_envio jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload_retorno jsonb NOT NULL DEFAULT '{}'::jsonb,
  emitido_em timestamptz,
  autorizado_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_fiscal_documentos_valores_nao_negativos CHECK (
    valor_produtos >= 0
    AND valor_desconto >= 0
    AND valor_frete >= 0
    AND valor_total >= 0
  )
);

CREATE TABLE IF NOT EXISTS fiscal_documento_itens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id uuid NOT NULL REFERENCES fiscal_documentos(id) ON DELETE CASCADE,
  sku text,
  descricao text NOT NULL,
  ncm text,
  cfop text,
  cst text,
  unidade text NOT NULL DEFAULT 'UN',
  quantidade numeric(14,4) NOT NULL DEFAULT 0,
  valor_unitario numeric(14,4) NOT NULL DEFAULT 0,
  valor_total numeric(14,2) NOT NULL DEFAULT 0,
  aliquota_icms numeric(6,2),
  aliquota_pis numeric(6,2),
  aliquota_cofins numeric(6,2),
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_fiscal_itens_qtd_positiva CHECK (quantidade >= 0),
  CONSTRAINT ck_fiscal_itens_valores_nao_negativos CHECK (
    valor_unitario >= 0
    AND valor_total >= 0
  )
);

CREATE TABLE IF NOT EXISTS fiscal_eventos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id uuid NOT NULL REFERENCES fiscal_documentos(id) ON DELETE CASCADE,
  evento text NOT NULL,
  status documento_fiscal_status NOT NULL,
  protocolo text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  criado_por text NOT NULL DEFAULT 'system',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS titulos_financeiros (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo titulo_tipo NOT NULL,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES leads(id) ON DELETE SET NULL,
  documento_fiscal_id uuid REFERENCES fiscal_documentos(id) ON DELETE SET NULL,
  descricao text NOT NULL,
  categoria text,
  centro_custo text,
  valor_original numeric(14,2) NOT NULL DEFAULT 0,
  valor_aberto numeric(14,2) NOT NULL DEFAULT 0,
  valor_pago numeric(14,2) NOT NULL DEFAULT 0,
  status titulo_status NOT NULL DEFAULT 'aberto',
  forma_pagamento text,
  competencia date,
  vencimento_em timestamptz NOT NULL,
  pago_em timestamptz,
  referencia_externa text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_titulos_valores_nao_negativos CHECK (
    valor_original >= 0
    AND valor_aberto >= 0
    AND valor_pago >= 0
  )
);

CREATE TABLE IF NOT EXISTS lancamentos_contabeis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo_id uuid REFERENCES titulos_financeiros(id) ON DELETE SET NULL,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  tipo titulo_tipo NOT NULL,
  conta_debito text NOT NULL,
  conta_credito text NOT NULL,
  historico text NOT NULL,
  valor numeric(14,2) NOT NULL,
  competencia date NOT NULL DEFAULT current_date,
  origem text NOT NULL DEFAULT 'crm_autopecas',
  referencia_externa text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_lancamentos_valor_positivo CHECK (valor > 0)
);

CREATE TABLE IF NOT EXISTS erp_integracoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entidade text NOT NULL CHECK (entidade IN ('pedido', 'fiscal_documento', 'titulo_financeiro', 'lancamento_contabil')),
  entidade_id uuid NOT NULL,
  operacao text NOT NULL CHECK (operacao IN ('upsert', 'cancelar', 'baixar')),
  status text NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'enviado', 'confirmado', 'erro', 'descartado')),
  tentativas integer NOT NULL DEFAULT 0,
  ultima_tentativa_em timestamptz,
  proxima_tentativa_em timestamptz,
  erro_ultima_tentativa text,
  payload_envio jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload_retorno jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
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
  entidade text NOT NULL CHECK (entidade IN ('pedidos', 'estoque', 'politica_preco', 'margem_minima')),
  entidade_id uuid NOT NULL,
  campo text NOT NULL,
  valor_anterior text,
  valor_novo text,
  alterado_por text NOT NULL DEFAULT 'system',
  data_evento timestamptz NOT NULL DEFAULT now(),
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb
);



CREATE TABLE IF NOT EXISTS perfis_comerciais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL UNIQUE,
  descricao text,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS politicas_margem (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  perfil_comercial_id uuid REFERENCES perfis_comerciais(id) ON DELETE CASCADE,
  vendedor_id uuid REFERENCES vendedores(id) ON DELETE CASCADE,
  margem_minima_percentual numeric(5,2) NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  inicio_vigencia timestamptz NOT NULL DEFAULT now(),
  fim_vigencia timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_politicas_margem_faixa_valida
    CHECK (margem_minima_percentual >= 0 AND margem_minima_percentual <= 100),
  CONSTRAINT ck_politicas_margem_periodo_valido
    CHECK (fim_vigencia IS NULL OR fim_vigencia >= inicio_vigencia),
  CONSTRAINT ck_politicas_margem_escopo_obrigatorio
    CHECK (perfil_comercial_id IS NOT NULL OR vendedor_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS campanhas_comerciais (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  descricao text,
  ativa boolean NOT NULL DEFAULT true,
  inicio_em timestamptz NOT NULL DEFAULT now(),
  fim_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_campanhas_comerciais_periodo_valido
    CHECK (fim_em IS NULL OR fim_em >= inicio_em)
);

CREATE TABLE IF NOT EXISTS politicas_preco (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  sku text REFERENCES estoque(sku) ON DELETE CASCADE,
  tipo_cliente text,
  perfil_comercial_id uuid REFERENCES perfis_comerciais(id) ON DELETE SET NULL,
  campanha_comercial_id uuid REFERENCES campanhas_comerciais(id) ON DELETE SET NULL,
  quantidade_minima numeric(14,3) NOT NULL DEFAULT 0,
  quantidade_maxima numeric(14,3),
  desconto_percentual numeric(5,2) NOT NULL DEFAULT 0,
  desconto_maximo_percentual numeric(5,2) NOT NULL DEFAULT 100,
  multiplicador_preco numeric(8,4) NOT NULL DEFAULT 1.0000,
  prioridade integer NOT NULL DEFAULT 100,
  ativo boolean NOT NULL DEFAULT true,
  inicio_vigencia timestamptz NOT NULL DEFAULT now(),
  fim_vigencia timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_politicas_preco_tipo_cliente_valido CHECK (
    tipo_cliente IS NULL
    OR tipo_cliente IN ('varejo', 'atacado', 'frota', 'oficina', 'seguradora', 'distribuidor')
  ),
  CONSTRAINT ck_politicas_preco_faixa_qtd_valida
    CHECK (quantidade_minima >= 0 AND (quantidade_maxima IS NULL OR quantidade_maxima >= quantidade_minima)),
  CONSTRAINT ck_politicas_preco_desconto_valido
    CHECK (
      desconto_percentual >= 0
      AND desconto_percentual <= 100
      AND desconto_maximo_percentual >= 0
      AND desconto_maximo_percentual <= 100
      AND desconto_percentual <= desconto_maximo_percentual
    ),
  CONSTRAINT ck_politicas_preco_multiplicador_valido CHECK (multiplicador_preco > 0),
  CONSTRAINT ck_politicas_preco_periodo_valido
    CHECK (fim_vigencia IS NULL OR fim_vigencia >= inicio_vigencia)
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

CREATE TABLE IF NOT EXISTS metas_vendedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendedor_id uuid NOT NULL REFERENCES vendedores(id) ON DELETE CASCADE,
  competencia date NOT NULL,
  meta_receita numeric(14,2) NOT NULL DEFAULT 0,
  meta_pedidos integer NOT NULL DEFAULT 0,
  meta_atendimentos integer NOT NULL DEFAULT 0,
  meta_conversao_percentual numeric(5,2) NOT NULL DEFAULT 0,
  meta_margem_percentual numeric(5,2) NOT NULL DEFAULT 0,
  percentual_comissao_base numeric(5,2) NOT NULL DEFAULT 0,
  bonus_superacao_percentual numeric(5,2) NOT NULL DEFAULT 0,
  ativo boolean NOT NULL DEFAULT true,
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uk_metas_vendedores_competencia UNIQUE (vendedor_id, competencia),
  CONSTRAINT ck_metas_vendedores_faixas CHECK (
    meta_receita >= 0
    AND meta_pedidos >= 0
    AND meta_atendimentos >= 0
    AND meta_conversao_percentual BETWEEN 0 AND 100
    AND meta_margem_percentual BETWEEN 0 AND 100
    AND percentual_comissao_base BETWEEN 0 AND 100
    AND bonus_superacao_percentual BETWEEN 0 AND 100
  )
);

CREATE TABLE IF NOT EXISTS comissoes_vendedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendedor_id uuid NOT NULL REFERENCES vendedores(id) ON DELETE CASCADE,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  competencia date NOT NULL,
  status text NOT NULL DEFAULT 'pendente',
  base_calculo numeric(14,2) NOT NULL DEFAULT 0,
  margem_apurada_percentual numeric(7,2) NOT NULL DEFAULT 0,
  percentual_comissao numeric(5,2) NOT NULL DEFAULT 0,
  valor_comissao numeric(14,2) NOT NULL DEFAULT 0,
  regra_aplicada text,
  pago_em timestamptz,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uk_comissao_por_pedido UNIQUE (pedido_id),
  CONSTRAINT ck_comissoes_vendedores_status CHECK (status IN ('pendente', 'aprovada', 'paga', 'cancelada')),
  CONSTRAINT ck_comissoes_vendedores_valores CHECK (
    base_calculo >= 0
    AND percentual_comissao BETWEEN 0 AND 100
    AND valor_comissao >= 0
  )
);

CREATE TABLE IF NOT EXISTS ativos_cliente (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  descricao_ativo text NOT NULL,
  placa text,
  chassi text,
  modelo text,
  ano_modelo integer,
  quilometragem_atual integer,
  periodicidade_manutencao_dias integer NOT NULL DEFAULT 180,
  ultima_manutencao_em timestamptz,
  proxima_manutencao_em timestamptz,
  ativo boolean NOT NULL DEFAULT true,
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_ativos_cliente_periodicidade_positiva CHECK (periodicidade_manutencao_dias > 0),
  CONSTRAINT ck_ativos_cliente_ano_valido CHECK (ano_modelo IS NULL OR ano_modelo BETWEEN 1950 AND 2100),
  CONSTRAINT ck_ativos_cliente_km_nao_negativa CHECK (quilometragem_atual IS NULL OR quilometragem_atual >= 0)
);

CREATE TABLE IF NOT EXISTS pos_venda_casos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  atendimento_id uuid REFERENCES atendimentos(id) ON DELETE SET NULL,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  ativo_cliente_id uuid REFERENCES ativos_cliente(id) ON DELETE SET NULL,
  tipo pos_venda_tipo NOT NULL,
  status pos_venda_status NOT NULL DEFAULT 'aberto',
  motivo text,
  descricao text NOT NULL,
  prioridade smallint NOT NULL DEFAULT 3,
  data_solicitacao timestamptz NOT NULL DEFAULT now(),
  prazo_sla_em timestamptz,
  concluido_em timestamptz,
  custo_estimado numeric(14,2),
  custo_real numeric(14,2),
  resolucao text,
  responsavel text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_pos_venda_prioridade_valida CHECK (prioridade BETWEEN 1 AND 5),
  CONSTRAINT ck_pos_venda_custos_nao_negativos CHECK (
    (custo_estimado IS NULL OR custo_estimado >= 0)
    AND (custo_real IS NULL OR custo_real >= 0)
  )
);

CREATE TABLE IF NOT EXISTS manutencoes_agendadas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ativo_cliente_id uuid NOT NULL REFERENCES ativos_cliente(id) ON DELETE CASCADE,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  pos_venda_caso_id uuid REFERENCES pos_venda_casos(id) ON DELETE SET NULL,
  tipo_servico text NOT NULL DEFAULT 'manutencao_periodica',
  agendado_para timestamptz NOT NULL,
  executado_em timestamptz,
  status pos_venda_status NOT NULL DEFAULT 'aberto',
  canal_notificacao text NOT NULL DEFAULT 'whatsapp',
  observacoes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS campanhas_retencao (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  objetivo text NOT NULL,
  canal text NOT NULL DEFAULT 'whatsapp',
  criterio_sql text,
  template_mensagem text NOT NULL,
  ativa boolean NOT NULL DEFAULT true,
  inicio_em timestamptz NOT NULL DEFAULT now(),
  fim_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_campanhas_periodo_valido CHECK (fim_em IS NULL OR fim_em >= inicio_em)
);

CREATE TABLE IF NOT EXISTS campanhas_retencao_execucoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campanha_id uuid NOT NULL REFERENCES campanhas_retencao(id) ON DELETE CASCADE,
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  pedido_id uuid REFERENCES pedidos(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pendente',
  enviado_em timestamptz,
  resposta_em timestamptz,
  converteu_em_pedido boolean NOT NULL DEFAULT false,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_campanhas_exec_status_valido CHECK (status IN ('pendente', 'enviado', 'respondido', 'erro', 'cancelado')),
  CONSTRAINT uk_campanha_lead_execucao UNIQUE (campanha_id, lead_id)
);

CREATE TABLE IF NOT EXISTS lead_canais_contato (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  canal text NOT NULL,
  identificador text NOT NULL,
  principal boolean NOT NULL DEFAULT false,
  opt_in_marketing boolean NOT NULL DEFAULT true,
  ativo boolean NOT NULL DEFAULT true,
  ultima_interacao_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_lead_canais_canal_valido CHECK (canal IN ('whatsapp', 'telefone', 'email', 'instagram', 'facebook', 'telegram', 'site_chat', 'sms')),
  CONSTRAINT uk_lead_canais_identificador UNIQUE (canal, identificador)
);

CREATE TABLE IF NOT EXISTS segmentos_marketing (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL UNIQUE,
  descricao text,
  criterio_sql text NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS campanhas_marketing (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  objetivo text NOT NULL,
  segmento_id uuid REFERENCES segmentos_marketing(id) ON DELETE SET NULL,
  canal text NOT NULL,
  template_mensagem text NOT NULL,
  prioridade smallint NOT NULL DEFAULT 3,
  ativa boolean NOT NULL DEFAULT true,
  inicio_em timestamptz NOT NULL DEFAULT now(),
  fim_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_campanhas_marketing_canal_valido CHECK (canal IN ('whatsapp', 'telefone', 'email', 'instagram', 'facebook', 'telegram', 'site_chat', 'sms')),
  CONSTRAINT ck_campanhas_marketing_prioridade_valida CHECK (prioridade BETWEEN 1 AND 5),
  CONSTRAINT ck_campanhas_marketing_periodo_valido CHECK (fim_em IS NULL OR fim_em >= inicio_em)
);

CREATE TABLE IF NOT EXISTS campanhas_marketing_execucoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campanha_id uuid NOT NULL REFERENCES campanhas_marketing(id) ON DELETE CASCADE,
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  lead_canal_id uuid REFERENCES lead_canais_contato(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pendente',
  enviado_em timestamptz,
  resposta_em timestamptz,
  converteu_em_pedido boolean NOT NULL DEFAULT false,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_campanhas_mkt_exec_status_valido CHECK (status IN ('pendente', 'enviado', 'respondido', 'erro', 'cancelado')),
  CONSTRAINT uk_campanha_marketing_lead UNIQUE (campanha_id, lead_id)
);

CREATE TABLE IF NOT EXISTS automacoes_reativacao (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL UNIQUE,
  dias_inatividade integer NOT NULL DEFAULT 60,
  campanha_id uuid REFERENCES campanhas_marketing(id) ON DELETE SET NULL,
  canal_preferencial text NOT NULL DEFAULT 'whatsapp',
  limite_diario integer NOT NULL DEFAULT 200,
  ativa boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_automacoes_reativacao_dias_validos CHECK (dias_inatividade >= 15),
  CONSTRAINT ck_automacoes_reativacao_limite_valido CHECK (limite_diario > 0),
  CONSTRAINT ck_automacoes_reativacao_canal_valido CHECK (canal_preferencial IN ('whatsapp', 'telefone', 'email', 'instagram', 'facebook', 'telegram', 'site_chat', 'sms'))
);

ALTER TABLE IF EXISTS leads ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE IF EXISTS leads ADD COLUMN IF NOT EXISTS filial_id uuid;
ALTER TABLE IF EXISTS atendimentos ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE IF EXISTS atendimentos ADD COLUMN IF NOT EXISTS filial_id uuid;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS empresa_id uuid;
ALTER TABLE IF EXISTS pedidos ADD COLUMN IF NOT EXISTS filial_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_leads_empresa'
      AND conrelid = 'leads'::regclass
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT fk_leads_empresa
      FOREIGN KEY (empresa_id) REFERENCES empresas(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_leads_filial_empresa'
      AND conrelid = 'leads'::regclass
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT fk_leads_filial_empresa
      FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_atendimentos_empresa'
      AND conrelid = 'atendimentos'::regclass
  ) THEN
    ALTER TABLE atendimentos
      ADD CONSTRAINT fk_atendimentos_empresa
      FOREIGN KEY (empresa_id) REFERENCES empresas(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_atendimentos_filial_empresa'
      AND conrelid = 'atendimentos'::regclass
  ) THEN
    ALTER TABLE atendimentos
      ADD CONSTRAINT fk_atendimentos_filial_empresa
      FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_pedidos_empresa'
      AND conrelid = 'pedidos'::regclass
  ) THEN
    ALTER TABLE pedidos
      ADD CONSTRAINT fk_pedidos_empresa
      FOREIGN KEY (empresa_id) REFERENCES empresas(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_pedidos_filial_empresa'
      AND conrelid = 'pedidos'::regclass
  ) THEN
    ALTER TABLE pedidos
      ADD CONSTRAINT fk_pedidos_filial_empresa
      FOREIGN KEY (filial_id, empresa_id) REFERENCES filiais(id, empresa_id);
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_leads_status_created_at ON leads(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_filiais_empresa_ativa ON filiais(empresa_id, ativa);
CREATE INDEX IF NOT EXISTS idx_leads_empresa_filial_status ON leads(empresa_id, filial_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_atendimentos_status_created_at ON atendimentos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_atendimentos_empresa_filial_status ON atendimentos(empresa_id, filial_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_status_created_at ON pedidos(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_filial_status ON pedidos(empresa_id, filial_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pedidos_pagamento ON pedidos(status, pago_em DESC);
CREATE INDEX IF NOT EXISTS idx_estoque_qtd ON estoque(quantidade_disponivel);
CREATE INDEX IF NOT EXISTS idx_estoque_equivalencias_origem ON estoque_equivalencias(sku_origem, ativo, prioridade);
CREATE INDEX IF NOT EXISTS idx_veiculos_catalogo_lookup ON veiculos_catalogo(marca, modelo, ano_inicio, ano_fim, ativo);
CREATE INDEX IF NOT EXISTS idx_veiculos_catalogo_motor ON veiculos_catalogo(modelo, motor, codigo_motor, ativo);
CREATE INDEX IF NOT EXISTS idx_veiculos_catalogo_chassi ON veiculos_catalogo(chassi_inicio, chassi_fim) WHERE chassi_inicio IS NOT NULL OR chassi_fim IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_estoque_aplicacoes_sku ON estoque_aplicacoes(sku, ativo, prioridade);
CREATE INDEX IF NOT EXISTS idx_estoque_aplicacoes_veiculo ON estoque_aplicacoes(veiculo_id, ativo, prioridade);
CREATE INDEX IF NOT EXISTS idx_estoque_reservas_lookup ON estoque_reservas(pedido_id, status, sku);
CREATE INDEX IF NOT EXISTS idx_status_log_entidade_evento ON status_log(entidade, entidade_id, data_evento DESC);
CREATE INDEX IF NOT EXISTS idx_conciliacoes_pix_txid ON conciliacoes_pix(pix_txid, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conciliacoes_pix_status ON conciliacoes_pix(status_conciliacao, pago_em DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_comercial_busca ON auditoria_comercial(entidade, entidade_id, data_evento DESC);
CREATE INDEX IF NOT EXISTS idx_politicas_preco_lookup ON politicas_preco(ativo, prioridade, tipo_cliente, sku);
CREATE INDEX IF NOT EXISTS idx_politicas_preco_vigencia ON politicas_preco(inicio_vigencia, fim_vigencia);
CREATE INDEX IF NOT EXISTS idx_politicas_margem_lookup ON politicas_margem(ativo, vendedor_id, perfil_comercial_id, inicio_vigencia, fim_vigencia);
CREATE INDEX IF NOT EXISTS idx_campanhas_comerciais_ativas ON campanhas_comerciais(ativa, inicio_em, fim_em);
CREATE INDEX IF NOT EXISTS idx_regua_cobranca_status_agenda ON regua_cobranca(status, agendado_para);
CREATE INDEX IF NOT EXISTS idx_pipeline_etapas_lookup ON pipeline_etapas(entidade, etapa, ativo);
CREATE INDEX IF NOT EXISTS idx_metas_vendedores_competencia ON metas_vendedores(competencia DESC, vendedor_id, ativo);
CREATE INDEX IF NOT EXISTS idx_comissoes_vendedores_competencia ON comissoes_vendedores(competencia DESC, vendedor_id, status);
CREATE INDEX IF NOT EXISTS idx_leads_sla_monitoria ON leads(status, etapa_entrada_em, ultimo_retorno_em);
CREATE INDEX IF NOT EXISTS idx_pedidos_sla_monitoria ON pedidos(status, etapa_entrada_em, ultimo_retorno_em);
CREATE INDEX IF NOT EXISTS idx_atendimentos_sla_monitoria ON atendimentos(status, etapa_entrada_em, ultimo_retorno_em);
CREATE INDEX IF NOT EXISTS idx_ativos_cliente_lead ON ativos_cliente(lead_id, ativo, proxima_manutencao_em);
CREATE INDEX IF NOT EXISTS idx_pos_venda_casos_lookup ON pos_venda_casos(status, tipo, data_solicitacao DESC);
CREATE INDEX IF NOT EXISTS idx_pos_venda_casos_relacoes ON pos_venda_casos(lead_id, pedido_id, atendimento_id);
CREATE INDEX IF NOT EXISTS idx_manutencoes_agendadas_status ON manutencoes_agendadas(status, agendado_para);
CREATE INDEX IF NOT EXISTS idx_campanhas_retencao_ativas ON campanhas_retencao(ativa, inicio_em, fim_em);
CREATE INDEX IF NOT EXISTS idx_campanhas_exec_lookup ON campanhas_retencao_execucoes(campanha_id, status, enviado_em DESC);
CREATE INDEX IF NOT EXISTS idx_lead_canais_lookup ON lead_canais_contato(lead_id, canal, ativo, principal);
CREATE INDEX IF NOT EXISTS idx_lead_canais_optin ON lead_canais_contato(canal, opt_in_marketing, ativo);
CREATE INDEX IF NOT EXISTS idx_segmentos_marketing_ativos ON segmentos_marketing(ativo, nome);
CREATE INDEX IF NOT EXISTS idx_campanhas_marketing_ativas ON campanhas_marketing(ativa, canal, inicio_em, fim_em);
CREATE INDEX IF NOT EXISTS idx_campanhas_marketing_exec ON campanhas_marketing_execucoes(campanha_id, status, enviado_em DESC);
CREATE INDEX IF NOT EXISTS idx_automacoes_reativacao_ativas ON automacoes_reativacao(ativa, canal_preferencial, dias_inatividade);
CREATE INDEX IF NOT EXISTS idx_fiscal_documentos_status_tipo ON fiscal_documentos(status, tipo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fiscal_documentos_pedido ON fiscal_documentos(pedido_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fiscal_eventos_documento ON fiscal_eventos(documento_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_titulos_financeiros_status_vencimento ON titulos_financeiros(status, tipo, vencimento_em);
CREATE INDEX IF NOT EXISTS idx_titulos_financeiros_pedido ON titulos_financeiros(pedido_id, tipo, status);
CREATE UNIQUE INDEX IF NOT EXISTS uk_titulo_receber_por_pedido ON titulos_financeiros(tipo, pedido_id) WHERE tipo = 'receber';
CREATE INDEX IF NOT EXISTS idx_lancamentos_contabeis_competencia ON lancamentos_contabeis(competencia, tipo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_erp_integracoes_fila ON erp_integracoes(status, proxima_tentativa_em, created_at);

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



CREATE OR REPLACE FUNCTION resolver_politica_preco(
  p_sku text,
  p_tipo_cliente text,
  p_quantidade numeric,
  p_campanha_comercial_id uuid DEFAULT NULL
)
RETURNS politicas_preco AS $$
DECLARE
  v_policy politicas_preco%ROWTYPE;
BEGIN
  SELECT pp.*
    INTO v_policy
  FROM politicas_preco pp
  LEFT JOIN campanhas_comerciais cc
    ON cc.id = pp.campanha_comercial_id
  WHERE pp.ativo = true
    AND (pp.sku IS NULL OR pp.sku = p_sku)
    AND (pp.tipo_cliente IS NULL OR pp.tipo_cliente = p_tipo_cliente)
    AND COALESCE(p_quantidade, 0) >= pp.quantidade_minima
    AND (pp.quantidade_maxima IS NULL OR COALESCE(p_quantidade, 0) <= pp.quantidade_maxima)
    AND now() >= pp.inicio_vigencia
    AND (pp.fim_vigencia IS NULL OR now() <= pp.fim_vigencia)
    AND (
      pp.campanha_comercial_id IS NULL
      OR (
        pp.campanha_comercial_id = p_campanha_comercial_id
        AND cc.ativa = true
        AND now() >= cc.inicio_em
        AND (cc.fim_em IS NULL OR now() <= cc.fim_em)
      )
    )
  ORDER BY pp.prioridade ASC, pp.quantidade_minima DESC, pp.created_at DESC
  LIMIT 1;

  RETURN v_policy;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION validar_precificacao_pedido()
RETURNS trigger AS $$
DECLARE
  v_tipo_cliente text;
  v_perfil_id uuid;
  v_campanha_id uuid;
  v_margem_minima numeric(5,2) := 0;
  v_receita_bruta numeric(14,2) := 0;
  v_desconto_total numeric(14,2) := 0;
  v_preco_tabela_total numeric(14,2) := 0;
  v_margem_apurada numeric(8,2) := 0;
  v_item jsonb;
  v_sku text;
  v_qtd numeric;
  v_preco_unit numeric(14,2);
  v_desconto_item numeric(14,2);
  v_preco_tabela numeric(14,2);
  v_policy politicas_preco%ROWTYPE;
BEGIN
  SELECT l.tipo_cliente, pc.id
    INTO v_tipo_cliente, v_perfil_id
  FROM atendimentos a
  JOIN leads l ON l.id = a.lead_id
  LEFT JOIN perfis_comerciais pc
    ON pc.nome = a.canal
   AND pc.ativo = true
  WHERE a.id = NEW.atendimento_id;

  IF NEW.itens IS NULL OR jsonb_typeof(NEW.itens) <> 'array' THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('cancelado', 'fechado') THEN
    RETURN NEW;
  END IF;

  IF NEW.pix_txid IS NOT NULL THEN
    SELECT id INTO v_campanha_id
    FROM campanhas_comerciais
    WHERE nome = NEW.pix_txid
      AND ativa = true
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  SELECT pm.margem_minima_percentual
    INTO v_margem_minima
  FROM politicas_margem pm
  WHERE pm.ativo = true
    AND (pm.vendedor_id IS NULL OR pm.vendedor_id = (
      SELECT a.vendedor_id FROM atendimentos a WHERE a.id = NEW.atendimento_id
    ))
    AND (pm.perfil_comercial_id IS NULL OR pm.perfil_comercial_id = v_perfil_id)
    AND now() >= pm.inicio_vigencia
    AND (pm.fim_vigencia IS NULL OR now() <= pm.fim_vigencia)
  ORDER BY
    CASE WHEN pm.vendedor_id IS NOT NULL THEN 0 ELSE 1 END,
    CASE WHEN pm.perfil_comercial_id IS NOT NULL THEN 0 ELSE 1 END,
    pm.created_at DESC
  LIMIT 1;

  v_margem_minima := COALESCE(v_margem_minima, 0);

  FOR v_item IN SELECT * FROM jsonb_array_elements(NEW.itens)
  LOOP
    v_sku := COALESCE(v_item->>'sku', v_item->>'codigo', v_item->>'item');
    v_qtd := COALESCE((v_item->>'quantidade')::numeric, (v_item->>'qtd')::numeric, 0);
    v_preco_unit := COALESCE((v_item->>'preco_unitario')::numeric, (v_item->>'preco')::numeric, 0);
    v_desconto_item := COALESCE((v_item->>'desconto')::numeric, (v_item->>'valor_desconto')::numeric, 0);

    SELECT e.preco_unitario INTO v_preco_tabela
    FROM estoque e
    WHERE e.sku = v_sku;

    v_preco_tabela := COALESCE(v_preco_tabela, v_preco_unit);
    v_policy := resolver_politica_preco(v_sku, v_tipo_cliente, v_qtd, v_campanha_id);

    IF v_policy.id IS NOT NULL THEN
      IF v_desconto_item > round((COALESCE(v_qtd, 0) * COALESCE(v_preco_tabela, 0)) * (v_policy.desconto_maximo_percentual / 100.0), 2) THEN
        RAISE EXCEPTION 'Desconto excede política comercial para SKU % (max: %%%)', v_sku, v_policy.desconto_maximo_percentual;
      END IF;

      INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
      VALUES (
        'politica_preco',
        NEW.id,
        'regra_aplicada',
        NULL,
        v_policy.nome,
        COALESCE(current_setting('app.user', true), 'system'),
        jsonb_build_object('sku', v_sku, 'quantidade', v_qtd, 'tipo_cliente', v_tipo_cliente, 'politica_id', v_policy.id)
      );
    END IF;

    v_preco_tabela_total := v_preco_tabela_total + (COALESCE(v_qtd, 0) * COALESCE(v_preco_tabela, 0));
    v_receita_bruta := v_receita_bruta + (COALESCE(v_qtd, 0) * COALESCE(v_preco_unit, 0));
    v_desconto_total := v_desconto_total + COALESCE(v_desconto_item, 0);
  END LOOP;

  IF v_preco_tabela_total > 0 THEN
    v_margem_apurada := round((((v_receita_bruta - v_desconto_total) - v_preco_tabela_total) / v_preco_tabela_total) * 100.0, 2);
  END IF;

  IF v_margem_apurada < v_margem_minima THEN
    INSERT INTO auditoria_comercial(entidade, entidade_id, campo, valor_anterior, valor_novo, alterado_por, detalhes)
    VALUES (
      'margem_minima',
      NEW.id,
      'reprovacao_margem',
      v_margem_apurada::text,
      v_margem_minima::text,
      COALESCE(current_setting('app.user', true), 'system'),
      jsonb_build_object('subtotal', NEW.subtotal, 'descontos', NEW.descontos, 'total', NEW.total)
    );
    RAISE EXCEPTION 'Margem mínima não atendida. Apurada: %%%, mínima exigida: %%%', v_margem_apurada, v_margem_minima;
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

CREATE OR REPLACE FUNCTION gerar_manutencao_periodica(
  p_ativo_cliente_id uuid,
  p_origem_pedido_id uuid DEFAULT NULL,
  p_base timestamptz DEFAULT now()
)
RETURNS uuid AS $$
DECLARE
  v_ativo ativos_cliente%ROWTYPE;
  v_agendamento_id uuid;
  v_data_base timestamptz;
BEGIN
  SELECT *
    INTO v_ativo
  FROM ativos_cliente
  WHERE id = p_ativo_cliente_id
    AND ativo = true;

  IF v_ativo.id IS NULL THEN
    RAISE EXCEPTION 'Ativo % inexistente ou inativo', p_ativo_cliente_id;
  END IF;

  v_data_base := COALESCE(v_ativo.ultima_manutencao_em, p_base, now());

  INSERT INTO manutencoes_agendadas (
    ativo_cliente_id, pedido_id, tipo_servico, agendado_para, status, canal_notificacao
  )
  VALUES (
    v_ativo.id,
    p_origem_pedido_id,
    'manutencao_periodica',
    v_data_base + make_interval(days => v_ativo.periodicidade_manutencao_dias),
    'aberto',
    'whatsapp'
  )
  RETURNING id INTO v_agendamento_id;

  UPDATE ativos_cliente
  SET proxima_manutencao_em = (
        SELECT agendado_para
        FROM manutencoes_agendadas
        WHERE id = v_agendamento_id
      ),
      updated_at = now()
  WHERE id = v_ativo.id;

  RETURN v_agendamento_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION registrar_evento_fiscal(
  p_documento_id uuid,
  p_evento text,
  p_status documento_fiscal_status,
  p_protocolo text DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid AS $$
DECLARE
  v_evento_id uuid;
BEGIN
  INSERT INTO fiscal_eventos (documento_id, evento, status, protocolo, payload, criado_por)
  VALUES (
    p_documento_id,
    p_evento,
    p_status,
    p_protocolo,
    COALESCE(p_payload, '{}'::jsonb),
    COALESCE(current_setting('app.user', true), 'system')
  )
  RETURNING id INTO v_evento_id;

  UPDATE fiscal_documentos
  SET status = p_status,
      protocolo_autorizacao = COALESCE(p_protocolo, protocolo_autorizacao),
      autorizado_em = CASE WHEN p_status = 'autorizado' THEN now() ELSE autorizado_em END,
      updated_at = now()
  WHERE id = p_documento_id;

  RETURN v_evento_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_titulo_receber_pedido(p_pedido_id uuid)
RETURNS uuid AS $$
DECLARE
  v_pedido pedidos%ROWTYPE;
  v_atendimento atendimentos%ROWTYPE;
  v_titulo_id uuid;
  v_status titulo_status;
  v_valor_aberto numeric(14,2);
  v_valor_pago numeric(14,2);
BEGIN
  SELECT *
    INTO v_pedido
  FROM pedidos
  WHERE id = p_pedido_id;

  IF v_pedido.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT *
    INTO v_atendimento
  FROM atendimentos
  WHERE id = v_pedido.atendimento_id;

  v_status := CASE
    WHEN v_pedido.status IN ('pago', 'fechado') THEN 'pago'::titulo_status
    WHEN v_pedido.status = 'cancelado' THEN 'cancelado'::titulo_status
    WHEN v_pedido.status = 'aguardando_pagamento' AND v_pedido.etapa_entrada_em < now() - interval '1 day' THEN 'vencido'::titulo_status
    ELSE 'aberto'::titulo_status
  END;

  v_valor_pago := CASE WHEN v_status = 'pago' THEN COALESCE(v_pedido.total, 0) ELSE 0 END;
  v_valor_aberto := GREATEST(COALESCE(v_pedido.total, 0) - v_valor_pago, 0);

  INSERT INTO titulos_financeiros (
    tipo, pedido_id, lead_id, descricao, categoria, centro_custo,
    valor_original, valor_aberto, valor_pago, status, forma_pagamento,
    competencia, vencimento_em, pago_em, referencia_externa, metadata
  )
  VALUES (
    'receber',
    v_pedido.id,
    v_atendimento.lead_id,
    'Contas a receber do pedido ' || v_pedido.id::text,
    'venda_autopecas',
    'comercial',
    COALESCE(v_pedido.total, 0),
    v_valor_aberto,
    v_valor_pago,
    v_status,
    CASE WHEN v_pedido.pix_txid IS NOT NULL THEN 'pix' ELSE NULL END,
    current_date,
    COALESCE(v_pedido.etapa_entrada_em, v_pedido.created_at, now()) + interval '1 day',
    CASE WHEN v_status = 'pago' THEN COALESCE(v_pedido.pago_em, now()) ELSE NULL END,
    COALESCE(v_pedido.pix_txid, v_pedido.id::text),
    jsonb_build_object('origem', 'pedido', 'pedido_status', v_pedido.status::text)
  )
  ON CONFLICT (tipo, pedido_id) WHERE (tipo = 'receber')
  DO UPDATE
  SET valor_original = EXCLUDED.valor_original,
      valor_aberto = EXCLUDED.valor_aberto,
      valor_pago = EXCLUDED.valor_pago,
      status = EXCLUDED.status,
      forma_pagamento = EXCLUDED.forma_pagamento,
      vencimento_em = EXCLUDED.vencimento_em,
      pago_em = EXCLUDED.pago_em,
      referencia_externa = EXCLUDED.referencia_externa,
      metadata = EXCLUDED.metadata,
      updated_at = now()
  RETURNING id INTO v_titulo_id;

  RETURN v_titulo_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_sync_titulo_receber_pedido()
RETURNS trigger AS $$
DECLARE
  v_titulo_id uuid;
BEGIN
  v_titulo_id := sync_titulo_receber_pedido(NEW.id);

  INSERT INTO erp_integracoes (entidade, entidade_id, operacao, status, payload_envio)
  VALUES (
    'titulo_financeiro',
    v_titulo_id,
    CASE WHEN NEW.status = 'cancelado' THEN 'cancelar' ELSE 'upsert' END,
    'pendente',
    jsonb_build_object('pedido_id', NEW.id, 'pedido_status', NEW.status::text)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_enfileirar_documento_fiscal_erp()
RETURNS trigger AS $$
BEGIN
  INSERT INTO erp_integracoes (entidade, entidade_id, operacao, status, payload_envio)
  VALUES (
    'fiscal_documento',
    NEW.id,
    CASE WHEN NEW.status = 'cancelado' THEN 'cancelar' ELSE 'upsert' END,
    'pendente',
    jsonb_build_object('tipo', NEW.tipo::text, 'status', NEW.status::text, 'pedido_id', NEW.pedido_id)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION buscar_aplicacoes_veiculares(
  p_marca text,
  p_modelo text,
  p_ano integer,
  p_motor text DEFAULT NULL,
  p_chassi text DEFAULT NULL
)
RETURNS TABLE (
  sku text,
  descricao text,
  categoria text,
  marca text,
  modelo text,
  versao text,
  ano_inicio integer,
  ano_fim integer,
  motor text,
  codigo_motor text,
  tipo_aplicacao text,
  lado text,
  posicao text,
  codigo_oem text,
  observacao_tecnica text,
  requer_confirmacao_chassi boolean,
  prioridade smallint
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.sku,
    e.descricao,
    e.categoria,
    v.marca,
    v.modelo,
    v.versao,
    v.ano_inicio,
    v.ano_fim,
    v.motor,
    v.codigo_motor,
    a.tipo_aplicacao,
    a.lado,
    a.posicao,
    a.codigo_oem,
    a.observacao_tecnica,
    a.requer_confirmacao_chassi,
    a.prioridade
  FROM estoque_aplicacoes a
  JOIN estoque e
    ON e.sku = a.sku
   AND e.ativo = true
  JOIN veiculos_catalogo v
    ON v.id = a.veiculo_id
   AND v.ativo = true
  WHERE a.ativo = true
    AND lower(v.marca) = lower(trim(p_marca))
    AND lower(v.modelo) = lower(trim(p_modelo))
    AND p_ano BETWEEN v.ano_inicio AND COALESCE(v.ano_fim, v.ano_inicio)
    AND (
      NULLIF(trim(p_motor), '') IS NULL
      OR NULLIF(trim(v.motor), '') IS NULL
      OR lower(v.motor) = lower(trim(p_motor))
      OR (NULLIF(trim(v.codigo_motor), '') IS NOT NULL AND lower(v.codigo_motor) = lower(trim(p_motor)))
    )
    AND (
      NULLIF(trim(p_chassi), '') IS NULL
      OR (
        NULLIF(trim(v.chassi_inicio), '') IS NULL
        AND NULLIF(trim(v.chassi_fim), '') IS NULL
      )
      OR (
        NULLIF(trim(v.chassi_inicio), '') IS NOT NULL
        AND NULLIF(trim(v.chassi_fim), '') IS NOT NULL
        AND upper(trim(p_chassi)) BETWEEN upper(trim(v.chassi_inicio)) AND upper(trim(v.chassi_fim))
      )
      OR (
        NULLIF(trim(v.chassi_inicio), '') IS NOT NULL
        AND NULLIF(trim(v.chassi_fim), '') IS NULL
        AND upper(trim(p_chassi)) >= upper(trim(v.chassi_inicio))
      )
      OR (
        NULLIF(trim(v.chassi_inicio), '') IS NULL
        AND NULLIF(trim(v.chassi_fim), '') IS NOT NULL
        AND upper(trim(p_chassi)) <= upper(trim(v.chassi_fim))
      )
    )
  ORDER BY a.prioridade ASC, e.sku;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE VIEW vw_desempenho_vendedores AS
WITH atendimentos_mes AS (
  SELECT
    a.vendedor_id,
    date_trunc('month', a.created_at)::date AS competencia,
    COUNT(*) AS atendimentos_total,
    COUNT(*) FILTER (WHERE a.status IN ('atendimento_finalizado', 'venda_fechada')) AS atendimentos_finalizados
  FROM atendimentos a
  WHERE a.vendedor_id IS NOT NULL
  GROUP BY a.vendedor_id, date_trunc('month', a.created_at)::date
),
pedidos_mes AS (
  SELECT
    a.vendedor_id,
    date_trunc('month', p.created_at)::date AS competencia,
    COUNT(*) FILTER (WHERE p.status IN ('pago', 'fechado')) AS pedidos_convertidos,
    COALESCE(SUM(p.total) FILTER (WHERE p.status IN ('pago', 'fechado')), 0)::numeric(14,2) AS receita_total,
    COALESCE(AVG(NULLIF(p.total, 0)) FILTER (WHERE p.status IN ('pago', 'fechado')), 0)::numeric(14,2) AS ticket_medio,
    COALESCE(
      AVG(
        CASE
          WHEN itens.valor_bruto > 0 THEN round(((itens.valor_bruto - itens.custo_estimado) / itens.valor_bruto) * 100.0, 2)
          ELSE NULL
        END
      ) FILTER (WHERE p.status IN ('pago', 'fechado')),
      0
    )::numeric(7,2) AS margem_media_percentual
  FROM pedidos p
  JOIN atendimentos a ON a.id = p.atendimento_id
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(SUM((item ->> 'preco_unitario')::numeric * COALESCE((item ->> 'quantidade')::numeric, 1)), 0) AS valor_bruto,
      COALESCE(SUM(COALESCE((item ->> 'custo_unitario')::numeric, 0) * COALESCE((item ->> 'quantidade')::numeric, 1)), 0) AS custo_estimado
    FROM jsonb_array_elements(COALESCE(p.itens, '[]'::jsonb)) item
  ) itens ON true
  WHERE a.vendedor_id IS NOT NULL
  GROUP BY a.vendedor_id, date_trunc('month', p.created_at)::date
),
competencias AS (
  SELECT vendedor_id, competencia FROM atendimentos_mes
  UNION
  SELECT vendedor_id, competencia FROM pedidos_mes
  UNION
  SELECT vendedor_id, competencia FROM metas_vendedores
)
SELECT
  v.id AS vendedor_id,
  v.nome AS vendedor_nome,
  c.competencia,
  COALESCE(am.atendimentos_total, 0) AS atendimentos_total,
  COALESCE(am.atendimentos_finalizados, 0) AS atendimentos_finalizados,
  COALESCE(pm.pedidos_convertidos, 0) AS pedidos_convertidos,
  COALESCE(pm.receita_total, 0)::numeric(14,2) AS receita_total,
  COALESCE(pm.ticket_medio, 0)::numeric(14,2) AS ticket_medio,
  COALESCE(pm.margem_media_percentual, 0)::numeric(7,2) AS margem_media_percentual,
  CASE
    WHEN COALESCE(am.atendimentos_total, 0) = 0 THEN 0
    ELSE round((COALESCE(pm.pedidos_convertidos, 0)::numeric / am.atendimentos_total::numeric) * 100.0, 2)
  END::numeric(7,2) AS taxa_conversao_percentual,
  mv.meta_receita,
  mv.meta_pedidos,
  mv.meta_atendimentos,
  mv.meta_conversao_percentual,
  mv.meta_margem_percentual,
  mv.percentual_comissao_base,
  mv.bonus_superacao_percentual,
  CASE
    WHEN COALESCE(mv.meta_receita, 0) = 0 THEN NULL
    ELSE round((COALESCE(pm.receita_total, 0) / mv.meta_receita) * 100.0, 2)
  END::numeric(7,2) AS atingimento_receita_percentual,
  CASE
    WHEN COALESCE(mv.meta_pedidos, 0) = 0 THEN NULL
    ELSE round((COALESCE(pm.pedidos_convertidos, 0)::numeric / mv.meta_pedidos::numeric) * 100.0, 2)
  END::numeric(7,2) AS atingimento_pedidos_percentual,
  CASE
    WHEN COALESCE(mv.meta_atendimentos, 0) = 0 THEN NULL
    ELSE round((COALESCE(am.atendimentos_total, 0)::numeric / mv.meta_atendimentos::numeric) * 100.0, 2)
  END::numeric(7,2) AS atingimento_atendimentos_percentual
FROM vendedores v
JOIN competencias c ON c.vendedor_id = v.id
LEFT JOIN atendimentos_mes am ON am.vendedor_id = v.id AND am.competencia = c.competencia
LEFT JOIN pedidos_mes pm ON pm.vendedor_id = v.id AND pm.competencia = c.competencia
LEFT JOIN metas_vendedores mv
  ON mv.vendedor_id = v.id
 AND mv.competencia = c.competencia
WHERE v.ativo = true;

CREATE OR REPLACE VIEW vw_ranking_vendedores AS
SELECT
  d.*,
  DENSE_RANK() OVER (PARTITION BY d.competencia ORDER BY d.taxa_conversao_percentual DESC, d.receita_total DESC) AS ranking_conversao,
  DENSE_RANK() OVER (PARTITION BY d.competencia ORDER BY d.margem_media_percentual DESC, d.receita_total DESC) AS ranking_margem,
  DENSE_RANK() OVER (PARTITION BY d.competencia ORDER BY d.receita_total DESC, d.pedidos_convertidos DESC) AS ranking_faturamento
FROM vw_desempenho_vendedores d;

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

CREATE OR REPLACE VIEW vw_catalogo_aplicacao_tecnica AS
SELECT
  a.id AS aplicacao_id,
  a.sku,
  e.descricao AS sku_descricao,
  e.categoria AS sku_categoria,
  v.id AS veiculo_id,
  v.marca,
  v.modelo,
  v.versao,
  v.ano_inicio,
  v.ano_fim,
  v.motor,
  v.codigo_motor,
  v.combustivel,
  v.chassi_inicio,
  v.chassi_fim,
  a.tipo_aplicacao,
  a.lado,
  a.posicao,
  a.codigo_oem,
  a.observacao_tecnica,
  a.requer_confirmacao_chassi,
  a.prioridade,
  a.ativo AS aplicacao_ativa,
  v.ativo AS veiculo_ativo,
  e.ativo AS sku_ativo
FROM estoque_aplicacoes a
JOIN estoque e
  ON e.sku = a.sku
JOIN veiculos_catalogo v
  ON v.id = a.veiculo_id;

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

CREATE OR REPLACE VIEW vw_pos_venda_operacao AS
SELECT
  pvc.id AS caso_id,
  pvc.tipo,
  pvc.status,
  pvc.prioridade,
  pvc.lead_id,
  l.nome AS cliente_nome,
  l.telefone AS cliente_telefone,
  pvc.pedido_id,
  pvc.atendimento_id,
  pvc.data_solicitacao,
  pvc.prazo_sla_em,
  pvc.concluido_em,
  EXTRACT(EPOCH FROM (now() - pvc.data_solicitacao)) / 3600.0 AS horas_em_aberto,
  CASE
    WHEN pvc.status IN ('concluido', 'cancelado', 'rejeitado') THEN 'encerrado'
    WHEN pvc.prazo_sla_em IS NOT NULL AND pvc.prazo_sla_em < now() THEN 'sla_estourado'
    ELSE 'dentro_sla'
  END AS indicador_sla
FROM pos_venda_casos pvc
JOIN leads l
  ON l.id = pvc.lead_id;

CREATE OR REPLACE VIEW vw_retencao_clientes AS
WITH pedidos_cliente AS (
  SELECT
    a.lead_id,
    COUNT(*) FILTER (WHERE p.status IN ('pago', 'fechado'))::integer AS total_pedidos_pago_fechado,
    COALESCE(SUM(CASE WHEN p.status IN ('pago', 'fechado') THEN p.total ELSE 0 END), 0)::numeric(14,2) AS receita_total,
    MAX(p.pago_em) AS ultimo_pagamento_em
  FROM pedidos p
  JOIN atendimentos a
    ON a.id = p.atendimento_id
  GROUP BY a.lead_id
),
retencao AS (
  SELECT
    pc.lead_id,
    pc.total_pedidos_pago_fechado,
    pc.receita_total,
    pc.ultimo_pagamento_em,
    COUNT(*) FILTER (
      WHERE p.status IN ('pago', 'fechado')
        AND p.pago_em >= now() - interval '365 days'
    )::integer AS pedidos_ultimos_365d
  FROM pedidos_cliente pc
  LEFT JOIN atendimentos a
    ON a.lead_id = pc.lead_id
  LEFT JOIN pedidos p
    ON p.atendimento_id = a.id
  GROUP BY pc.lead_id, pc.total_pedidos_pago_fechado, pc.receita_total, pc.ultimo_pagamento_em
)
SELECT
  l.id AS lead_id,
  l.nome,
  l.telefone,
  r.total_pedidos_pago_fechado,
  r.pedidos_ultimos_365d,
  r.receita_total,
  r.ultimo_pagamento_em,
  CASE
    WHEN r.pedidos_ultimos_365d >= 3 THEN 'alta_recorrencia'
    WHEN r.pedidos_ultimos_365d >= 1 THEN 'recorrente'
    WHEN r.total_pedidos_pago_fechado >= 1 THEN 'reativacao'
    ELSE 'sem_historico'
  END AS segmento_retencao
FROM leads l
LEFT JOIN retencao r
  ON r.lead_id = l.id;

CREATE OR REPLACE VIEW vw_financeiro_titulos_abertos AS
SELECT
  tf.id AS titulo_id,
  tf.tipo,
  tf.status,
  tf.pedido_id,
  tf.lead_id,
  tf.descricao,
  tf.valor_original,
  tf.valor_aberto,
  tf.valor_pago,
  tf.vencimento_em,
  EXTRACT(EPOCH FROM (now() - tf.vencimento_em)) / 86400.0 AS dias_em_atraso,
  CASE
    WHEN tf.status = 'pago' THEN 'liquidado'
    WHEN tf.status = 'cancelado' THEN 'cancelado'
    WHEN tf.vencimento_em < now() THEN 'vencido'
    WHEN tf.vencimento_em < now() + interval '24 hours' THEN 'vence_hoje'
    ELSE 'a_vencer'
  END AS situacao_financeira
FROM titulos_financeiros tf
WHERE tf.tipo = 'receber';

CREATE OR REPLACE VIEW vw_fiscal_documentos_pendentes AS
SELECT
  fd.id AS documento_id,
  fd.tipo,
  fd.status,
  fd.pedido_id,
  fd.numero,
  fd.serie,
  fd.chave_acesso,
  fd.valor_total,
  fd.emitido_em,
  fd.autorizado_em,
  ei.status AS status_integracao_erp,
  ei.tentativas,
  ei.erro_ultima_tentativa,
  CASE
    WHEN fd.status IN ('erro', 'denegado') THEN 'acao_imediata'
    WHEN fd.status IN ('rascunho', 'pendente_emissao') THEN 'emitir'
    WHEN fd.status = 'emitido' AND (fd.autorizado_em IS NULL) THEN 'aguardando_autorizacao'
    WHEN fd.status = 'autorizado' AND (ei.status IS NULL OR ei.status IN ('pendente', 'erro')) THEN 'sincronizar_erp'
    ELSE 'ok'
  END AS acao_recomendada
FROM fiscal_documentos fd
LEFT JOIN LATERAL (
  SELECT e.status, e.tentativas, e.erro_ultima_tentativa
  FROM erp_integracoes e
  WHERE e.entidade = 'fiscal_documento'
    AND e.entidade_id = fd.id
  ORDER BY e.created_at DESC
  LIMIT 1
) ei ON true;

CREATE OR REPLACE VIEW vw_carteira_inativa AS
SELECT
  l.id AS lead_id,
  l.nome,
  l.telefone,
  l.origem,
  l.status,
  GREATEST(
    COALESCE(l.ultimo_retorno_em, l.updated_at, l.created_at),
    COALESCE(a.ultimo_atendimento_em, l.created_at),
    COALESCE(p.ultimo_pedido_em, l.created_at)
  ) AS ultima_interacao_em,
  EXTRACT(
    day FROM now() - GREATEST(
      COALESCE(l.ultimo_retorno_em, l.updated_at, l.created_at),
      COALESCE(a.ultimo_atendimento_em, l.created_at),
      COALESCE(p.ultimo_pedido_em, l.created_at)
    )
  )::integer AS dias_sem_interacao,
  COALESCE(canais.canais_ativos, 0) AS canais_ativos,
  COALESCE(canais.canal_preferencial, 'whatsapp') AS canal_preferencial
FROM leads l
LEFT JOIN LATERAL (
  SELECT MAX(a.updated_at) AS ultimo_atendimento_em
  FROM atendimentos a
  WHERE a.lead_id = l.id
) a ON true
LEFT JOIN LATERAL (
  SELECT MAX(p.updated_at) AS ultimo_pedido_em
  FROM pedidos p
  JOIN atendimentos at ON at.id = p.atendimento_id
  WHERE at.lead_id = l.id
) p ON true
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE c.ativo) AS canais_ativos,
    (ARRAY_AGG(c.canal ORDER BY c.principal DESC, c.updated_at DESC))[1] AS canal_preferencial
  FROM lead_canais_contato c
  WHERE c.lead_id = l.id
    AND c.ativo = true
    AND c.opt_in_marketing = true
) canais ON true;

CREATE OR REPLACE FUNCTION enfileirar_reativacao_carteira_inativa(
  p_dias_sem_interacao integer DEFAULT 60,
  p_canal text DEFAULT 'whatsapp',
  p_limite integer DEFAULT 200
)
RETURNS integer AS $$
DECLARE
  v_campanha_id uuid;
  v_qtd integer := 0;
BEGIN
  SELECT id
  INTO v_campanha_id
  FROM campanhas_marketing
  WHERE ativa = true
    AND canal = p_canal
    AND objetivo ILIKE '%reativa%'
    AND (inicio_em IS NULL OR inicio_em <= now())
    AND (fim_em IS NULL OR fim_em >= now())
  ORDER BY prioridade ASC, created_at DESC
  LIMIT 1;

  IF v_campanha_id IS NULL THEN
    RETURN 0;
  END IF;

  WITH elegiveis AS (
    SELECT ci.lead_id
    FROM vw_carteira_inativa ci
    WHERE ci.dias_sem_interacao >= p_dias_sem_interacao
      AND ci.canal_preferencial = p_canal
    ORDER BY ci.dias_sem_interacao DESC, ci.lead_id
    LIMIT GREATEST(p_limite, 1)
  )
  INSERT INTO campanhas_marketing_execucoes (campanha_id, lead_id, lead_canal_id, status, detalhes)
  SELECT
    v_campanha_id,
    e.lead_id,
    c.id,
    'pendente',
    jsonb_build_object(
      'origem', 'automacao_reativacao',
      'dias_sem_interacao', ci.dias_sem_interacao,
      'canal_preferencial', ci.canal_preferencial
    )
  FROM elegiveis e
  JOIN vw_carteira_inativa ci ON ci.lead_id = e.lead_id
  LEFT JOIN LATERAL (
    SELECT c2.id
    FROM lead_canais_contato c2
    WHERE c2.lead_id = e.lead_id
      AND c2.canal = p_canal
      AND c2.ativo = true
      AND c2.opt_in_marketing = true
    ORDER BY c2.principal DESC, c2.updated_at DESC
    LIMIT 1
  ) c ON true
  ON CONFLICT (campanha_id, lead_id) DO NOTHING;

  GET DIAGNOSTICS v_qtd = ROW_COUNT;
  RETURN v_qtd;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_leads_updated_at ON leads;
CREATE TRIGGER trg_leads_updated_at
BEFORE UPDATE ON leads
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_empresas_updated_at ON empresas;
CREATE TRIGGER trg_empresas_updated_at
BEFORE UPDATE ON empresas
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_filiais_updated_at ON filiais;
CREATE TRIGGER trg_filiais_updated_at
BEFORE UPDATE ON filiais
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

DROP TRIGGER IF EXISTS trg_pedidos_validar_precificacao ON pedidos;
CREATE TRIGGER trg_pedidos_validar_precificacao
BEFORE INSERT OR UPDATE OF itens, subtotal, descontos, total, status ON pedidos
FOR EACH ROW
EXECUTE FUNCTION validar_precificacao_pedido();

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

DROP TRIGGER IF EXISTS trg_veiculos_catalogo_updated_at ON veiculos_catalogo;
CREATE TRIGGER trg_veiculos_catalogo_updated_at
BEFORE UPDATE ON veiculos_catalogo
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_estoque_aplicacoes_updated_at ON estoque_aplicacoes;
CREATE TRIGGER trg_estoque_aplicacoes_updated_at
BEFORE UPDATE ON estoque_aplicacoes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_estoque_reservas_updated_at ON estoque_reservas;
CREATE TRIGGER trg_estoque_reservas_updated_at
BEFORE UPDATE ON estoque_reservas
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_ativos_cliente_updated_at ON ativos_cliente;
CREATE TRIGGER trg_ativos_cliente_updated_at
BEFORE UPDATE ON ativos_cliente
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_pos_venda_casos_updated_at ON pos_venda_casos;
CREATE TRIGGER trg_pos_venda_casos_updated_at
BEFORE UPDATE ON pos_venda_casos
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_manutencoes_agendadas_updated_at ON manutencoes_agendadas;
CREATE TRIGGER trg_manutencoes_agendadas_updated_at
BEFORE UPDATE ON manutencoes_agendadas
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_campanhas_retencao_updated_at ON campanhas_retencao;
CREATE TRIGGER trg_campanhas_retencao_updated_at
BEFORE UPDATE ON campanhas_retencao
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_campanhas_retencao_execucoes_updated_at ON campanhas_retencao_execucoes;
CREATE TRIGGER trg_campanhas_retencao_execucoes_updated_at
BEFORE UPDATE ON campanhas_retencao_execucoes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_lead_canais_contato_updated_at ON lead_canais_contato;
CREATE TRIGGER trg_lead_canais_contato_updated_at
BEFORE UPDATE ON lead_canais_contato
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_segmentos_marketing_updated_at ON segmentos_marketing;
CREATE TRIGGER trg_segmentos_marketing_updated_at
BEFORE UPDATE ON segmentos_marketing
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_campanhas_marketing_updated_at ON campanhas_marketing;
CREATE TRIGGER trg_campanhas_marketing_updated_at
BEFORE UPDATE ON campanhas_marketing
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_campanhas_marketing_execucoes_updated_at ON campanhas_marketing_execucoes;
CREATE TRIGGER trg_campanhas_marketing_execucoes_updated_at
BEFORE UPDATE ON campanhas_marketing_execucoes
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_automacoes_reativacao_updated_at ON automacoes_reativacao;
CREATE TRIGGER trg_automacoes_reativacao_updated_at
BEFORE UPDATE ON automacoes_reativacao
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_perfis_comerciais_updated_at ON perfis_comerciais;
CREATE TRIGGER trg_perfis_comerciais_updated_at
BEFORE UPDATE ON perfis_comerciais
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_politicas_margem_updated_at ON politicas_margem;
CREATE TRIGGER trg_politicas_margem_updated_at
BEFORE UPDATE ON politicas_margem
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_campanhas_comerciais_updated_at ON campanhas_comerciais;
CREATE TRIGGER trg_campanhas_comerciais_updated_at
BEFORE UPDATE ON campanhas_comerciais
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_metas_vendedores_updated_at ON metas_vendedores;
CREATE TRIGGER trg_metas_vendedores_updated_at
BEFORE UPDATE ON metas_vendedores
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_comissoes_vendedores_updated_at ON comissoes_vendedores;
CREATE TRIGGER trg_comissoes_vendedores_updated_at
BEFORE UPDATE ON comissoes_vendedores
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_politicas_preco_updated_at ON politicas_preco;
CREATE TRIGGER trg_politicas_preco_updated_at
BEFORE UPDATE ON politicas_preco
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_fiscal_documentos_updated_at ON fiscal_documentos;
CREATE TRIGGER trg_fiscal_documentos_updated_at
BEFORE UPDATE ON fiscal_documentos
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_fiscal_documento_itens_updated_at ON fiscal_documento_itens;
CREATE TRIGGER trg_fiscal_documento_itens_updated_at
BEFORE UPDATE ON fiscal_documento_itens
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_titulos_financeiros_updated_at ON titulos_financeiros;
CREATE TRIGGER trg_titulos_financeiros_updated_at
BEFORE UPDATE ON titulos_financeiros
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_erp_integracoes_updated_at ON erp_integracoes;
CREATE TRIGGER trg_erp_integracoes_updated_at
BEFORE UPDATE ON erp_integracoes
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

DROP TRIGGER IF EXISTS trg_pedidos_sync_titulo_receber ON pedidos;
CREATE TRIGGER trg_pedidos_sync_titulo_receber
AFTER INSERT OR UPDATE OF status, total, pago_em, etapa_entrada_em, pix_txid ON pedidos
FOR EACH ROW
EXECUTE FUNCTION trg_sync_titulo_receber_pedido();

DROP TRIGGER IF EXISTS trg_fiscal_documentos_enfileirar_erp ON fiscal_documentos;
CREATE TRIGGER trg_fiscal_documentos_enfileirar_erp
AFTER INSERT OR UPDATE OF status, numero, serie, chave_acesso, autorizado_em ON fiscal_documentos
FOR EACH ROW
EXECUTE FUNCTION trg_enfileirar_documento_fiscal_erp();

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

INSERT INTO perfis_comerciais (nome, descricao)
VALUES
  ('whatsapp', 'Perfil comercial padrão para atendimento via WhatsApp'),
  ('inside_sales', 'Perfil comercial para equipe interna de televendas')
ON CONFLICT (nome) DO UPDATE
SET descricao = EXCLUDED.descricao,
    ativo = true,
    updated_at = now();

COMMIT;
