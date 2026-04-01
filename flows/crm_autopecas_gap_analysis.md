# Gap analysis — CRM Autopeças para cenário real de grande rede

## Escopo analisado
- Stack de execução (`docker-compose.yml`), gateway de webhook/PIX mock, schema SQL, fluxo Node-RED e testes E2E atuais.
- Objetivo: identificar o que ainda falta para operar com robustez de **grande autopeças** (multi-filial, alto volume, compliance e integração corporativa).

## Diagnóstico executivo
O projeto já cobre bem o **fluxo comercial base** (lead → atendimento → pedido → PIX → fechamento), com entidades de pós-venda, fiscal/ERP, retenção e indicadores.

Porém, para um cenário real de grande porte, ainda faltam capacidades de produção em quatro frentes:
1. **Confiabilidade e escala operacional** (HA, filas, retentativas, idempotência ponta a ponta).
2. **Governança e segurança corporativa** (RBAC no domínio CRM, segregação por filial/empresa no acesso e LGPD operacional).
3. **Integrações enterprise reais** (PSP/PIX real, fiscal real, ERP bidirecional robusto com reconciliação).
4. **Observabilidade/SRE e governança de mudanças** (SLO, monitoramento ativo, migrações versionadas e DR).

## O que já está sólido
- Modelo de dados rico para comercial/estoque/fiscal/retention (inclui empresas/filiais, pipeline, fiscal, cobrança, marketing e pós-venda).
- Trilhas de auditoria e funções de apoio para status/conciliação.
- Teste E2E cobrindo cadeia principal comercial e validações relevantes de negócio.
- Deploy automatizado do flow + schema para reduzir operação manual.

## Lacunas para “cenário real grande autopeças”

### 1) Escala e alta disponibilidade
**Gap**
- Arquitetura atual é single-instance em pontos críticos (Node-RED único, gateway único, sem orquestrador e sem réplica declarada).
- Contexto de execução do Node-RED está em memória, limitando resiliência em restart/failover.

**Impacto real**
- Risco de indisponibilidade operacional (atendimento parado) e perda de estado em incidentes/redeploy.

**Necessário**
- Executar serviços críticos em modo HA (mínimo active-passive; ideal active-active com roteamento).
- Externalizar estado sensível do runtime e padronizar sessão/locking distribuído.
- Estratégia de DR: RPO/RTO definidos, restore testado e runbook.

### 2) PIX e pagamentos ainda em modo mock
**Gap**
- Endpoint de cobrança PIX no gateway gera TXID e payload sintético localmente (sem PSP/banco real).

**Impacto real**
- Não atende operação financeira de produção, conciliação bancária oficial nem SLA de recebimento real.

**Necessário**
- Integração homologada com PSP (BACEN-compliant), webhook autenticado do provedor e idempotência por `txid/e2eId`.
- Conciliação com extrato real + tratamento de devolução/estorno, chargeback e divergências.

### 3) Segurança corporativa e segregação de acesso
**Gap**
- Não há camada explícita de RBAC/ABAC no domínio CRM (papéis, permissões por perfil, escopo por empresa/filial).
- Falta trilha de LGPD operacional (base legal por finalidade, anonimização/expurgo, retenção e DSR).

**Impacto real**
- Risco de acesso indevido entre filiais/equipes e não conformidade com auditoria interna/LGPD.

**Necessário**
- Implementar matriz de permissões por função (vendedor, gerente, financeiro, fiscal, admin).
- Enforcement por empresa/filial nos endpoints e consultas.
- Política de retenção, anonimização e trilhas de consentimento para dados pessoais.

### 4) Confiabilidade de integração e mensageria
**Gap**
- Fluxo centrado em HTTP síncrono para eventos críticos; ausência explícita de fila dedicada/outbox/inbox transacional no código de automação.

**Impacto real**
- Em picos e falhas intermitentes, aumenta chance de perda/duplicidade de evento e inconsistência entre CRM, fiscal e ERP.

**Necessário**
- Padronizar processamento assíncrono com fila (DLQ, retentativas exponenciais, circuit breaker).
- Idempotência por chave natural de evento + deduplicação persistente.
- Contratos de integração versionados e testes de contrato.

### 5) Governança de banco e ciclo de mudanças
**Gap**
- Schema monolítico aplicado direto por script; falta trilha explícita de migrações incrementais versionadas com rollback forward-only controlado.

**Impacto real**
- Maior risco em releases frequentes e dificuldade para auditoria de mudança em produção multiambiente.

**Necessário**
- Adotar ferramenta de migração (Flyway/Liquibase ou equivalente), baseline + histórico por ambiente.
- Pipeline CI/CD com validação automática de migração, lint SQL e smoke pós-deploy.

### 6) Observabilidade/SRE
**Gap**
- Não há evidência de stack de métricas/tracing/alerta com SLO (latência webhook, backlog de integração, erro por etapa, tempo de atendimento).

**Impacto real**
- Operação reativa; incidentes percebidos pelo time comercial antes do time técnico.

**Necessário**
- Instrumentação com métricas de negócio + técnicas, logs estruturados, tracing distribuído.
- Painéis operacionais e alertas com severidade (N1/N2/N3) e on-call.

### 7) Cobertura de testes para produção
**Gap**
- E2E atual valida bem regras SQL e fluxo principal, mas não cobre carga, caos, concorrência alta, recuperação de falhas e testes de segurança.

**Impacto real**
- Pode “passar no laboratório” e falhar sob volume real (campanhas, múltiplas filiais, picos de WhatsApp).

**Necessário**
- Testes de carga (p95/p99), soak test, concorrência de reservas de estoque e testes de resiliência.
- Testes de segurança (authz, assinatura, replay attack, rate limit, segredo rotacionado).

## Prioridades recomendadas (90 dias)

### Fase 1 (0–30 dias) — bloqueadores de produção
1. Substituir PIX mock por PSP real homologado.
2. Implementar idempotência de eventos e retentativa com fila + DLQ para webhook/callbacks.
3. Definir RBAC mínimo e segregação por empresa/filial nos acessos críticos.
4. Criar monitoramento básico com alertas (indisponibilidade, erro > X%, fila parada).

### Fase 2 (31–60 dias) — robustez operacional
1. Migrações versionadas e pipeline de deploy com validações automáticas.
2. Plano de backup/restore testado (RPO/RTO) e exercícios de desastre.
3. Hardening de segurança (rate limit, rotação de segredo assistida, políticas de retenção LGPD).

### Fase 3 (61–90 dias) — escala e excelência
1. HA dos componentes críticos e estratégia de failover documentada.
2. Observabilidade avançada (tracing + SLO por jornada comercial).
3. Testes contínuos de carga/caos e revisão de capacidade por filial/campanha.

## Checklist mínimo de go-live (grande autopeças)
- [ ] PIX em provedor real com conciliação bancária diária automatizada.
- [ ] RBAC + segregação por empresa/filial validada por testes.
- [ ] Fila de integração com DLQ, replay seguro e idempotência.
- [ ] Runbooks de incidente + on-call + SLO publicados.
- [ ] Backup/restore testado em ambiente de DR.
- [ ] Teste de carga aprovado para pico esperado de mensagens/pedidos.
- [ ] Processo de migração de schema versionado em CI/CD.
