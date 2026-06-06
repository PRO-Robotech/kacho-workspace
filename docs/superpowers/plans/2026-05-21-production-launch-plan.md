# Kachō — Production Launch Plan

> **Назначение.** Полный план «что нужно сделать, чтобы запустить приклад в проде».
> Составлен 2026-05-21 после ревью KAC-127 (эпик закрылся как «production-ready»,
> но ревью на 55 находок + проверка стенда показали — это переоценка).
>
> **Связанные документы:**
> - `2026-05-21-iam-authz-review-remediation-plan.md` — детальный план по 44 IAM-находкам (= WS-1 здесь).
> - `obsidian/kacho/KAC/KAC-127.md` § «Known gaps» — не-IAM пробелы.

---

## Часть 0 — Честный baseline (где мы сейчас)

| Область | Состояние |
|---|---|
| Control-plane CRUD (Account/Project/VPC/Compute) | ✅ работает |
| ReBAC authz-энфорс (OpenFGA) | ❌ функционально не готов: гранты не энфорсятся, revoke не отзывает, custom-роли схлопываются |
| OpenFGA на стенде `5.35.93.58` | ❌ не развёрнут → authz fails-closed (code 14/7), VPC endpoints не отвечают |
| `fga_outbox` drainer | ❌ не существует — bootstrap-grant в FGA не применяется |
| Enterprise (SAML/SCIM/JIT/break-glass/CAEP/GDPR/audit-pipeline) | ⚠️ заглушки либо недостижимы (не подключены к gateway) |
| `kacho-loadbalancer` | ❌ baseline-сервиса нет вообще |
| newman iam CRUD-сюита | ❌ мертва (gen.py не генерирует `iam-*.py`) |
| Deploy (Postgres/Hydra/Kratos/secrets/TLS) | ⚠️ dev-стенд есть; prod-конфигурация (HA, секреты, сертификаты) — нет |
| Observability / runbooks / DR | ⚠️ частично (KAC-127 заявил, реально не верифицировано) |

---

## Часть 1 — Решение по scope prod-v1 (DECISION NEEDED)

KAC-127 пытался сделать «всё сразу» (13 фаз) и надорвался. Для реального запуска нужно
**сузить v1** до того, что можно довести до рабочего и безопасного состояния.

### Рекомендуемый prod-v1 scope (lean)

**В v1 ВХОДИТ:**
- IAM: Account / Project / User / ServiceAccount / Group / Role / AccessBinding + **рабочий ReBAC-энфорс** (OpenFGA + OPA-overlay).
- VPC: Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint / NetworkInterface.
- Compute: Instance / Disk / Image / Snapshot + Geography (Region/Zone).
- api-gateway (REST+gRPC), Operations (LRO).
- AuthN: ORY Kratos + Hydra (passkey/OIDC) — базовый flow.
- Деплой: kind/k8s + Postgres-per-service + observability + бэкапы.

**ОТЛОЖЕНО в post-v1 (descope из v1):**
- `kacho-loadbalancer` (NLB/TargetGroup) — сервис не существует.
- SAML bridge, SCIM 2.0 — enterprise SSO.
- JIT/PIM, break-glass, Access Reviews, GDPR erasure pipeline.
- CAEP push pipeline.
- Full audit pipeline (Kafka + ClickHouse + S3 + HSM + Merkle + SIEM).
- SPIFFE/SPIRE + Cilium mesh.
- Multi-region active-active.

**Обоснование:** v1 = «рабочий, безопасный control-plane». Enterprise/compliance-фичи
(SSO/JIT/audit-pipeline) — это отдельные большие объёмы, каждый со своей инфраструктурой;
их «полуготовое» состояние сейчас активно вредит (заглушки, недостижимые RPC).

> **DECISION-1:** утвердить lean-scope ИЛИ указать, что из отложенного обязательно в v1.
> **DECISION-2:** descope-фичи (Часть 3, WS-3) — **удалить** код или **спрятать за feature-flag**
> (off + не регистрировать на endpoint)? Рекомендация — feature-flag (код сохраняется для post-v1).

---

## Часть 2 — Workstreams (что нужно сделать)

### WS-1 — AuthZ корректность (БЛОКЕР №1)

44 подтверждённые IAM-находки, 5 чанков — детально в
`2026-05-21-iam-authz-review-remediation-plan.md`. Для v1 обязательны:
- **Chunk 1** — DB/FGA desync (#8/#16/#47/#48/#50/#51/#52) — P0. *(в работе: #8/#13 — PR kacho-iam#17)*
- **Chunk 2** — in-service authz + identity-spoofing (#9/#12/#13/#35/#36/#37/#39/#43/#53) — P0/P1.
- **Chunk 3** — gateway wiring + единый permission-каталог (#19/#28-34/#38/#44/#45/#49) — P1.
  *(объём сокращается: Phase 7/7b сервисы — descope, в каталог их не вносим, а гасим — см. WS-3).*
- **Chunk 4** — spec-drift KAC-119/121 (#1/#3/#4/#5/#6/#7/#14/#15/#27/#46/#55) — P1/P2.
- **Chunk 5** — для v1 берём только: #25 (ReloadModel), #23 (CheckRelation context). Остальное (#21/#40/#41/#42) — federation/SAML/SCIM/CAEP — descope.

### WS-2 — AuthZ инфраструктура (БЛОКЕР №2)

Без этого WS-1 не на чем работает:
- **WS-2.1** — развернуть **OpenFGA** на каждом целевом кластере (prod — HA: ≥2 реплики + Postgres-backend). Store + authorization-model bootstrap-job, идемпотентный.
- **WS-2.2** — построить **`fga_outbox` drainer** (его нет): worker на corelib `outbox`-паттерне, `LISTEN kacho_iam_fga_outbox`, применяет pending-rows к OpenFGA Write/Delete, idempotent (409=ok). Без него bootstrap-grant и любые outbox-маршрутизируемые tuple'ы не доезжают.
- **WS-2.3** — **authz-cache invalidation на revoke**: `AccessBinding.Delete` (и JIT/break-glass revoke) обязаны эмитить `subject_change_outbox` (op `binding_delete`) → gateway сбрасывает authz-кэш. Сейчас revoke удаляет FGA-tuple, но кэш gateway отдаёт устаревший ALLOW (подтверждено CI-прогоном `26220429877`).
- **WS-2.4** — **включить authz-middleware** api-gateway на всех стендах, **fail-closed** (сейчас на dev выключен — `deploy#42`; на проде fail-open недопустим).
- **WS-2.5** — **principal propagation** сервис→сервис через gateway (`vpc#104` — vpc видит `user:bootstrap` для всех cross-service вызовов).
- **WS-2.6** — OPA sidecar: bundle-server + подписанные bundle'ы, либо — если OPA-overlay не нужен в v1 — явно зафиксировать «FGA-only», убрать OPA из критического пути.

### WS-3 — Descope-cleanup (убрать «полуготовое»)

Per DECISION-2. Для каждой отложенной фичи:
- **WS-3.1** — IAM: SAML/SCIM/JIT/AccessReview/ComplianceReport/JitPending/GdprErasure/BreakGlass/CAEP — не регистрировать на gRPC/REST endpoint (ни public, ни internal) ИЛИ за feature-flag `off`. Их proto-stubs могут оставаться, сервис-код — за флагом.
- **WS-3.2** — заглушки на surface убрать: `InternalIAM.ListPermissions` (#49 — либо реализовать, т.к. нужен admin-UI, либо снять с регистрации), `RunRegoTest`/`ReloadModel` — internal-only diagnostics, оставить но починить (#25/#26).
- **WS-3.3** — audit-pipeline: для v1 — минимальный durable audit (outbox в Postgres + структурный лог), без Kafka/ClickHouse/HSM/Merkle. Зафиксировать как «v1 audit = append-only Postgres + log shipping».
- **WS-3.4** — обновить `CLAUDE.md` / vault / спеки: отложенные домены пометить «deferred, post-v1» (loadbalancer-refs из `CLAUDE.md` уже убраны 2026-05-21).

### WS-4 — Тесты и CI

- **WS-4.1** — конвертировать `tests/newman/cases/iam-*.py` из мёртвого `dict`-формата в `Case`/`Step` (gen.py их генерирует) + добавить в `run.sh`; либо перенести покрытие в authz-suite. Сейчас вся iam CRUD-newman не гоняется.
- **WS-4.2** — integration-покрытие (testcontainers) на все authz-критичные пути WS-1 (concurrent-race на CAS/grant/revoke).
- **WS-4.3** — `newman-e2e` gate зелёный на kind-стенде (authz-deny / authz-sa-apitoken + новые flow-кейсы grant→revoke).
- **WS-4.4** — соблюдать **test-first** (CLAUDE.md §Запреты #11): падающий тест до кода.
- **WS-4.5** — нагрузочное (k6): authz Check p95, List p95, sustained RPS — базовые SLO для v1.

### WS-5 — Деплой и эксплуатация

- **WS-5.1** — prod k8s-кластер: sizing, namespaces, RBAC.
- **WS-5.2** — Postgres-per-service (kacho_iam / kacho_vpc / kacho_compute): managed-инстанс или HA-StatefulSet; **бэкапы + PITR**; goose-миграции через `cmd/migrator` Job.
- **WS-5.3** — ORY Hydra + Kratos: prod-конфиг (не dev-секреты), JWKS-ротация, OAuth2.1 (DPoP/PKCE).
- **WS-5.4** — секреты: внешний secret-manager / sealed-secrets; **никаких** секретов в ConfigMap; убрать dev-JWT-secret; DB-пароли через `secretKeyRef`.
- **WS-5.5** — TLS: external endpoint `api.<domain>` с реальным сертификатом (cert-manager + Let's Encrypt либо корпоративный CA); ingress; gRPC + REST.
- **WS-5.6** — helm umbrella: resource requests/limits, readiness/liveness probes, PodDisruptionBudget; HPA — починить metrics (CI показал `FailedGetResourceMetric` — нет metrics-server) либо убрать HPA из v1.
- **WS-5.7** — image registry `docker.io/prorobotech/<svc>`, теги, signed images (опц.).
- **WS-5.8** — CI/CD pipeline: build → test → newman-e2e gate → deploy.

### WS-6 — Observability

- **WS-6.1** — метрики: VictoriaMetrics — RED-метрики на каждый сервис, authz Check latency/deny-rate, Operation-latency.
- **WS-6.2** — логи: VictoriaLogs — структурный slog, корреляция по operation/trace-id.
- **WS-6.3** — трейсинг: VictoriaTraces / OpenTelemetry — cross-service (gateway→iam→vpc).
- **WS-6.4** — алерты (AlertManager): authz-service-unavailable, error-rate, DB-pool, Operation-stuck, cert-expiry.
- **WS-6.5** — дашборды + runbooks на основные инцидент-классы (authz down, DB down, OpenFGA down, миграция).

### WS-7 — Security hardening

- **WS-7.1** — authz fail-closed везде (WS-2.4); проверить, что недоступность OpenFGA → deny, не allow.
- **WS-7.2** — Internal-vs-external: `Internal*`-сервисы НЕ на external TLS endpoint (CLAUDE.md §6); проверить gateway-конфиг.
- **WS-7.3** — инфра-чувствительные данные не на публичном API (CLAUDE.md §«Инфра-чувствительные»): placement, underlay, SID-схема — internal-only.
- **WS-7.4** — anti-anonymous interceptor покрывает все мутации (#43).
- **WS-7.5** — NetworkPolicy: `grpc-internal` (9091) ограничен cluster-internal источниками (#20).
- **WS-7.6** — rate limiting на external endpoint; request size limits.
- **WS-7.7** — `trivy`/`gosec`/`govulncheck` — zero High/Critical; SBOM.

### WS-8 — External / user-action

- **WS-8.1** — покупка/делегирование домена + DNS.
- **WS-8.2** — TLS-сертификат (или корпоративный CA).
- **WS-8.3** — prod k8s-кластер (провайдер / on-prem) + sizing.
- **WS-8.4** — backup/restore drill (восстановление Postgres из бэкапа — реально проверить).
- **WS-8.5** — внешний pentest до GA (рекомендуется).
- **WS-8.6** — HSM / SOC2 / ISO — **только если** audit-pipeline и compliance возвращаются в scope (для lean-v1 — НЕ нужно).

---

## Часть 3 — Последовательность и вехи

| Веха | Содержание | Workstreams | Definition |
|---|---|---|---|
| **M0** | Решения по scope | DECISION-1, DECISION-2 | scope зафиксирован |
| **M1** | AuthZ работает на стенде | WS-2.1–2.5 + WS-1 Chunk 1-2 | grant→allow, revoke→deny энфорсятся end-to-end на kind |
| **M2** | AuthZ-матрица полная | WS-1 Chunk 3-4 + WS-4.1–4.3 | newman authz-suite + iam CRUD-suite зелёные; access-matrix реально проверяет переходы |
| **M3** | Scope зачищен + hardening | WS-3 + WS-7 | нет недостижимых/полуготовых RPC на endpoint; security-чеклист пройден |
| **M4** | Prod-инфра | WS-5 + WS-6 | стенд в prod-кластере: HA Postgres, секреты, TLS, observability, бэкапы |
| **M5** | Pre-GA | WS-8 + WS-4.5 | домен/сертификат, pentest, DR-drill, нагрузочное SLO |
| **GA** | Запуск | — | DoD (Часть 4) выполнен |

**Критический путь:** M1 (WS-2 + WS-1 Chunk 1-2) — без него ничего не имеет смысла.
WS-2.1 (развернуть OpenFGA) — можно делать **прямо сейчас**, параллельно WS-1.

---

## Часть 4 — Definition of Done для prod-v1

**Функционально:**
- [ ] Все v1-ресурсы (IAM/VPC/Compute) — CRUD через api-gateway, REST+gRPC.
- [ ] ReBAC-энфорс: grant→allow, revoke→deny, custom-роль даёт ровно свои permissions, JIT/break-glass — descoped или работают.
- [ ] anonymous → deny на всех мутациях и authz-gated read.
- [ ] Operations (LRO) — все мутации async, поллинг работает.

**Тесты/CI:**
- [ ] newman authz-suite + iam CRUD-suite зелёные в CI (`newman-e2e` gate).
- [ ] integration-тесты на authz-критичные пути, concurrent-race покрыт.
- [ ] test-first соблюдён (RED→GREEN в каждом PR).
- [ ] trivy/gosec/govulncheck — zero High/Critical.

**Инфраструктура:**
- [ ] OpenFGA HA развёрнут, store/model bootstrap идемпотентен.
- [ ] `fga_outbox` drainer работает; authz-cache инвалидируется на revoke.
- [ ] Postgres-per-service: бэкапы + PITR, restore-drill пройден.
- [ ] Секреты — во внешнем secret-manager, не в ConfigMap.
- [ ] TLS на external endpoint, авто-renew.
- [ ] Observability: метрики/логи/трейсы/алерты/дашборды/runbooks.

**Security:**
- [ ] authz fail-closed; OpenFGA down → deny.
- [ ] Internal*-сервисы не на external endpoint; инфра-данные не на публичном API.
- [ ] NetworkPolicy; rate limiting.
- [ ] (рекомендуется) внешний pentest пройден.

**Документация:**
- [ ] `CLAUDE.md` / vault / спеки отражают реальный v1-scope (descope помечен).
- [ ] runbooks на инцидент-классы.

---

## Часть 5 — Открытые вопросы / решения

| # | Вопрос | Рекомендация |
|---|---|---|
| DECISION-1 | lean-v1 scope vs включить что-то из отложенного | lean-v1 |
| DECISION-2 | descope-фичи: удалить код или feature-flag | feature-flag (off + снять с регистрации) |
| DECISION-3 | OPA-overlay в v1 или FGA-only | FGA-only для v1, OPA — post-v1 |
| DECISION-4 | prod-кластер: провайдер / on-prem | нужен ввод пользователя |
| DECISION-5 | v1 audit: Postgres-outbox+log vs полный pipeline | Postgres-outbox+log |
| DECISION-6 | HA Postgres: managed vs StatefulSet | зависит от инфра-выбора (DECISION-4) |

---

## Примечание по методологии

Per CLAUDE.md §Запреты #11 (test-first) и memory `feedback-acceptance-tests-only-not-code`:
каждый workstream исполняется чанками, **тест пишется первым** (RED), затем код (GREEN).
Production-код не генерируется массово автономно — по чанку, с верификацией в CI.
