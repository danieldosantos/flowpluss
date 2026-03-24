-- Revisão de persistência/retenção na base da Evolution (PostgreSQL)
-- Uso:
--   docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/postgres_privacy_review.sql
-- ou copie este arquivo para dentro do container e execute com psql.

\echo '1) Tabelas do schema publico e volume (estimado)'
SELECT
  n.nspname AS schema,
  c.relname AS table_name,
  c.reltuples::bigint AS estimated_rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname = 'public'
ORDER BY estimated_rows DESC, table_name;

\echo '2) Colunas que potencialmente carregam dados pessoais'
SELECT
  table_schema,
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    lower(column_name) LIKE '%phone%'
    OR lower(column_name) LIKE '%number%'
    OR lower(column_name) LIKE '%name%'
    OR lower(column_name) LIKE '%email%'
    OR lower(column_name) LIKE '%document%'
    OR lower(column_name) LIKE '%message%'
    OR lower(column_name) LIKE '%body%'
    OR lower(column_name) LIKE '%text%'
    OR lower(column_name) LIKE '%avatar%'
    OR lower(column_name) LIKE '%profile%'
    OR lower(column_name) LIKE '%pushname%'
    OR lower(column_name) LIKE '%jid%'
    OR lower(column_name) LIKE '%remote%'
  )
ORDER BY table_name, column_name;

\echo '3) Colunas de data para checar janelas de retenção'
SELECT
  table_schema,
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    lower(column_name) IN ('created_at', 'updated_at', 'timestamp')
    OR lower(column_name) LIKE '%date%'
    OR lower(column_name) LIKE '%time%'
  )
ORDER BY table_name, column_name;
