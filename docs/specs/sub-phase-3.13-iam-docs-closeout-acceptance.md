# Sub-phase 3.13 — IAM Vault docs + public docs + runbooks + epic KAC-127 closeout (KAC-127 / Phase 13) — Acceptance

> **Статус:** DRAFT
> **Дата:** 2026-05-19
> **Эпик:** [EPIC] KAC-127 IAM production-ready next-gen (YT KAC-123)
> **Phase:** 13 of 13 (last phase; см. `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` §«Phase 13»)
> **Дизайн:** `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §17 (Definition of Done) + §13.5 (Documentation deliverables)
> **Plan tasks:** 13.1 (Vault updates 30+ files), 13.2 (KAC-127 trail closeout), 13.3 (Public docs at docs.kacho.cloud), 13.4 (YT closeout + sprint cleanup + worktree cleanup)
> **Depends on (hard):** Phase 1–12 — ВСЕ предыдущие sub-phases должны быть **merged + tests green + acceptance docs APPROVED**. Phase 13 — финальная фаза, она НЕ стартует пока хоть один из subtask 1.x–12.x не в `Done`.
> **Production edition.** Никаких deferred, никаких TODO/follow-up. Vault — самодостаточные узкие 1-3KB файлы, kepano-style frontmatter обязателен, wikilinks валидны. Public docs — три namespace (user/admin/dev) live на `docs.kacho.cloud`. Runbooks — все 11 категорий, tabletop-tested, кросс-ссылаются из Grafana annotations.
> **Acceptance reviewer gate:** запрещено стартовать кодинг/правки vault Phase 13 до APPROVED этого документа (workspace CLAUDE.md §«Запреты» #1).

---

## 0. Преамбула — место этой sub-итерации в эпике

KAC-127 строит production-grade IAM (Account/Project + AuthN passkey/DPoP + ReBAC OpenFGA + WIF + SCIM/SAML + JIT/Break-glass + Audit/CAEP + SPIFFE mesh + multi-region + conformance) в **13 фаз**. Phase 13 — закрывающая, **не вводит ни одной строки production-кода**. Её единственная ответственность — превратить накопленные за фазы 1–12 артефакты в audit-trail, потребляемый:

1. **Будущими инженерами Kachō** — через Obsidian vault: при работе с любым iam-ресурсом / RPC / package / cross-service edge должен находиться единственный narrow 1-3KB файл с FK contract / methods table / runtime protocol / KAC-trail. Без этого следующая итерация будет грузить 50KB README и тратить токены впустую (workspace CLAUDE.md §«Obsidian vault — обязательный context-источник и trail»).
2. **Внешними потребителями API** — через публичный `docs.kacho.cloud/` сайт: user-facing (signup/MFA/SA/Federation/Role/JIT/Audit query), admin-facing (Org SSO config/SCIM token rotation/Break-glass/Compliance reports), developer-facing (OIDC Federation snippets для GitHub Actions / AWS IRSA / GCP WIF / GitLab CI).
3. **Operations on-call инженерами** — через runbook-библиотеку `docs/runbooks/iam/` (break-glass, key-rotation, regional-failover, gdpr-erasure, audit-pipeline-incident, caep-backlog, fga-tuple-drift-reconciliation, jwks-rotation-overdue, cert-renewal-failed, kratos-flow-broken, hydra-token-error). Каждый runbook **обязан** быть tabletop-tested (паника off-hours прогнана в стейджинге) и линкован из Grafana alert annotations + AlertManager receivers.
4. **Compliance auditor'ами** (SOC 2 Type II, ISO 27001:2022 Annex A, GDPR Art. 32, FedRAMP Moderate) — через security.txt, responsible disclosure docs, и единый changelog на закрытие эпика.

После Phase 13 эпик KAC-127 закрывается (`YT KAC-123 → Done`), 13 subtasks помечены `Done`, 10 git worktrees из `kacho-workspace-KAC-127/`-структуры удалены (workspace вернётся к обычному состоянию).

**Что НЕ входит в Phase 13** (out of scope — уже сделано в более ранних фазах):
| Что | Где сделано |
|---|---|
| Сам vault-файл `KAC/KAC-127.md` (создание) | Phase 0 (тикетинг); Phase 13 только финализирует поля `status=done`, `closed=<date>`, `prs=[...]` |
| Спеки фаз 3.1–3.12 (`sub-phase-3.1..3.12-iam-*.md`) | Каждая phase делает свой acceptance doc — этот phase его НЕ переписывает |
| Helm charts / Kubernetes manifests / CI/CD config | Phase 11 (production deployment) — Phase 13 только linkует |
| Conformance suite / pentest report / chaos report | Phase 12 — Phase 13 только linkует с public docs |
| Сами integration/newman/k6 тесты | Phase 1–12 + Phase 12 (conformance) — Phase 13 их не пишет |

---

## 1. Связь с регламентом и запретами (нормативно)

| Запрет / правило | Применение в Phase 13 |
|---|---|
| **Запрет #1** — Нет кодирования до APPROVED acceptance-документа | Этот документ — gate; задачи 13.1–13.4 (vault edits + public docs writing + runbooks + YT closeout) заблокированы до APPROVED |
| **Запрет #2** — НЕ упоминать «yandex» в коде/именах/env | Соблюдаем; vault tags / public docs / runbooks именуют peers «Okta / Azure AD / Google Workspace / GitHub Actions / AWS / GCP / GitLab CI» — нейтральные вендоры. YC-стилистика error/regex/timestamp остаётся в API-docs как стиль, но без слова «yandex» |
| **Запрет #3** — НЕ ORM | N/A — Phase 13 без кода |
| **Запрет #4** — НЕ cross-service cascade delete | Vault документирует уже принятые архитектурные решения (Phase 1: audit-row сохраняется 7y по compliance даже при GDPR erasure — pseudonymize PII в Kafka producer side, см. Phase 9 §6.15). Phase 13 НЕ меняет поведение, только описывает |
| **Запрет #5** — НЕ редактировать применённую миграцию | N/A — Phase 13 без миграций |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | Vault `rpc/iam-internal-*.md` файлы **обязаны** иметь frontmatter `visibility: internal` (отдельная enum, не путать с `public`); public docs на `docs.kacho.cloud/iam/` (user-facing) НИКОГДА не документируют InternalCluster/InternalBreakGlass/InternalJITEligibility/InternalRole/InternalSIEM RPC. Они уходят **только** в `admin/iam/` namespace, который TLS-protected + IP-allowlisted на edge (CloudFront / NGINX) |
| **Запрет #7** — НЕ broker, пока in-process справляется | N/A — Phase 13 без кода. Vault edges `iam-to-kafka-audit.md` / `iam-to-clickhouse-audit.md` фиксируют, что Kafka разрешён в Phase 9 by D-18 (audit broker — единственное снятое исключение) |
| **Запрет #8** — DB-per-service | Соблюдаем; vault не описывает «общую БД» — каждый ресурс vault-файла имеет поле `owner_table` указывающее на конкретный `kacho_iam.<table>` (либо ClickHouse cluster для downstream-views, как `audit_events_ch.events`) |
| **Запрет #9** — Все мутации возвращают Operation | N/A — Phase 13 без RPC |
| **Запрет #10** — Within-service refs — DB-уровень обязателен | N/A — Phase 13 без миграций. Vault `resources/iam-*.md` файлы документируют FK contracts уже принятые в Phase 1 (`0013` migration); Phase 13 проверяет что в каждом файле есть секция «FK contract» с актуальными REFERENCES |
| **Запрет #11** — Не мёрджить новый RPC без тестов в том же PR | N/A — Phase 13 без RPC. Из Phase 13 PRs мёрджится **только** vault/docs/runbooks; ни одного `.go`/`.proto`/`.sql` файла в diff'е PR Phase 13 быть НЕ ДОЛЖНО (см. DoD §7) |

**Карта владельцев доменов** (regulation §«Кросс-доменные ссылки на ресурсы»):

- Vault-документация — owner = `kacho-workspace` (репо). Никаких vault-файлов в `project/kacho-iam/` или других сервисных репо — vault единый, centralized.
- Public docs (`docs.kacho.cloud/`) — owner = `kacho-workspace` (генерируется из `docs/site/` workspace-репо).
- Runbooks (`docs/runbooks/iam/`) — owner = `kacho-workspace`; копии могут быть синкнуты в `kacho-deploy/runbooks/iam/` как deployment-bundle, но source of truth — workspace.

---

## 2. Глоссарий / доменная модель Phase 13 (нормативно)

### 2.1 Vault entity coverage matrix (нормативно — ЧТО должно быть в vault после Phase 13)

| Категория | Файл (relative `obsidian/kacho/`) | Источник (фаза) | Новый/изменяемый |
|---|---|---|---|
| `resources/iam-account.md` | Phase 1 | изменяется (frontmatter aliases, FK contract update) |
| `resources/iam-project.md` | Phase 1 | изменяется |
| `resources/iam-user.md` | Phase 1 | изменяется |
| `resources/iam-service-account.md` | Phase 1 | изменяется |
| `resources/iam-group.md` | Phase 1 | изменяется |
| `resources/iam-role.md` | Phase 1, Phase 3 | изменяется (добавить FGA tuple mapping) |
| `resources/iam-access-binding.md` | Phase 1, Phase 3 | изменяется (добавить condition FK) |
| `resources/iam-cluster.md` | Phase 1 (cluster-admin/break-glass) | **создаётся** |
| `resources/iam-organization.md` | Phase 1, Phase 6 (SSO) | **создаётся** |
| `resources/iam-federation-trust-policy.md` | Phase 5 (WIF) | **создаётся** |
| `resources/iam-access-binding-condition.md` | Phase 3 (FGA conditions) | **создаётся** |
| `resources/iam-jit-eligibility.md` | Phase 7 (JIT/PIM) | **создаётся** |
| `resources/iam-caep-subscriber.md` | Phase 8 (CAEP push) | **создаётся** |
| `resources/iam-access-review.md` | Phase 7 (access reviews) | **создаётся** |
| `resources/iam-access-review-item.md` | Phase 7 | **создаётся** |
| `resources/iam-gdpr-erasure-request.md` | Phase 7 (GDPR Art.17) | **создаётся** |
| `resources/iam-session-revocation.md` | Phase 2 (DPoP token revocation) | **создаётся** |
| `resources/iam-oidc-jwks-key.md` | Phase 2 (JWKS rotation) | **создаётся** |
| `resources/iam-audit-signing-batch.md` | Phase 9 (HSM Merkle batches) | **создаётся** |
| `resources/iam-scim-user-mapping.md` | Phase 6 (SCIM) | **создаётся** |
| `resources/iam-cluster-break-glass-grant.md` | Phase 7 | **создаётся** |
| `resources/iam-cluster-admin-grant.md` | Phase 1 | **создаётся** |
| `resources/iam-service-account-oauth-client.md` | Phase 2 (OAuth client SA flow) | **создаётся** |
| **Totals resources/** | **14 new + 9 modified = 23 files** | | |
| `rpc/iam-account-service.md` | Phase 1 | изменяется |
| `rpc/iam-project-service.md` | Phase 1 | изменяется |
| `rpc/iam-user-service.md` | Phase 1, Phase 2 | изменяется (signup/MFA) |
| `rpc/iam-service-account-service.md` | Phase 1, Phase 2 | изменяется |
| `rpc/iam-role-service.md` | Phase 3 (predefined+custom roles) | изменяется |
| `rpc/iam-access-binding-service.md` | Phase 3 | изменяется |
| `rpc/iam-organization-service.md` | Phase 6 (SSO config) | **создаётся** |
| `rpc/iam-federation-service.md` | Phase 5 (WIF policies) | **создаётся** |
| `rpc/iam-internal-cluster-service.md` | Phase 1 | **создаётся** |
| `rpc/iam-internal-role-service.md` | Phase 3 (admin role mgmt) | **создаётся** |
| `rpc/iam-internal-break-glass-service.md` | Phase 7 | **создаётся** |
| `rpc/iam-internal-jit-eligibility-service.md` | Phase 7 | **создаётся** |
| `rpc/iam-caep-subscriber-service.md` | Phase 8 | **создаётся** |
| `rpc/iam-access-review-service.md` | Phase 7 | **создаётся** |
| `rpc/iam-gdpr-erasure-service.md` | Phase 7 | **создаётся** |
| `rpc/iam-scim-v2-service.md` | Phase 6 (SCIM v2 inbound) | **создаётся** |
| `rpc/iam-saml-service.md` | Phase 6 (SAML SP via jackson) | **создаётся** |
| `rpc/iam-internal-siem-service.md` | Phase 9 (SIEM subscribers admin) | **создаётся** |
| **Totals rpc/** | **12 new + 6 modified = 18 files** | | |
| `edges/iam-to-hydra-admin.md` | Phase 2 (Ory Hydra OAuth) | **создаётся** |
| `edges/iam-to-kratos-admin.md` | Phase 2 (Ory Kratos identity flows) | **создаётся** |
| `edges/iam-to-opa.md` | Phase 3 (OPA policy decision) | **создаётся** |
| `edges/iam-to-jackson-saml.md` | Phase 6 (BoxyHQ Jackson SAML SP) | **создаётся** |
| `edges/iam-to-scim-okta.md` | Phase 6 | **создаётся** |
| `edges/iam-to-scim-azure.md` | Phase 6 | **создаётся** |
| `edges/iam-to-scim-google.md` | Phase 6 | **создаётся** |
| `edges/iam-to-spire.md` | Phase 10 (SPIFFE/SPIRE attestation) | **создаётся** |
| `edges/iam-to-cilium-mesh.md` | Phase 10 (Cilium service mesh mTLS) | **создаётся** |
| `edges/iam-to-kafka-audit.md` | Phase 9 (audit Kafka topic) | **создаётся** |
| `edges/iam-to-clickhouse-audit.md` | Phase 9 | **создаётся** |
| `edges/iam-to-s3-audit.md` | Phase 9 (S3 cold + manifests) | **создаётся** |
| `edges/iam-to-hsm.md` | Phase 9 (PKCS#11 signing) | **создаётся** |
| `edges/iam-to-siem-datadog.md` | Phase 9 | **создаётся** |
| `edges/iam-to-siem-splunk.md` | Phase 9 | **создаётся** |
| `edges/iam-to-caep-subscriber-webhook.md` | Phase 8 | **создаётся** |
| **Totals edges/** | **16 new = 16 files** | | |
| `packages/corelib-authz.md` | Phase 3 (Check + Expand helpers) | изменяется (extend) |
| `packages/corelib-audit.md` | Phase 1, Phase 9 (audit emit + CADF) | **создаётся** |
| `packages/corelib-notify.md` | Phase 8 (CAEP outbox emit) | **создаётся** |
| `packages/corelib-clients-hydra.md` | Phase 2 | **создаётся** |
| `packages/corelib-clients-kratos.md` | Phase 2 | **создаётся** |
| `packages/corelib-clients-jackson.md` | Phase 6 | **создаётся** |
| `packages/corelib-clients-spire.md` | Phase 10 | **создаётся** |
| `packages/iam-apps-jit.md` | Phase 7 | **создаётся** |
| `packages/iam-apps-caep.md` | Phase 8 | **создаётся** |
| `packages/iam-apps-scim.md` | Phase 6 | **создаётся** |
| `packages/iam-apps-saml.md` | Phase 6 | **создаётся** |
| `packages/iam-apps-federation.md` | Phase 5 | **создаётся** |
| `packages/iam-apps-gdpr.md` | Phase 7 | **создаётся** |
| `packages/iam-apps-audit.md` | Phase 9 (drainer + verifier + SIEM forwarder) | **создаётся** |
| `packages/iam-apps-jwks.md` | Phase 2 | **создаётся** |
| **Totals packages/** | **14 new + 1 modified = 15 files** | | |
| `KAC/KAC-127.md` | already exists | **финализируется** |
| **GRAND TOTAL** | **56 new + 16 modified + 1 finalized = 73 vault files touched** | | |

> [!important] Файлы из таблицы выше — нормативный минимум. **Phase 13 НЕ имеет права** мёрджить PR без хотя бы одного из 73 файлов в diff'е. Если какой-то ресурс/RPC появился в фазах 1-12 *неучтённым* (например, мини-таблица в миграции которая не светилась в acceptance) — Phase 13 обязана **дополнительно** создать vault-запись для неё (см. workspace CLAUDE.md §«Vault — Когда ОБЯЗАТЕЛЬНО обновлять vault»).

### 2.2 Frontmatter discipline (kepano-style; нормативно)

Vault уже использует kepano-style frontmatter (см. `obsidian/kacho/CLAUDE.md`). Phase 13 обязана выдержать на каждом из 73 файлов:

- **Все категории**: `title`, `category`, `tags` — обязательны.
- **resources/**: `domain` (= `iam`), `id_prefix` (`acc-`, `prj-`, `usr-`, `sa-`, `grp-`, `role-`, `bind-`, `cluster-`, `org-`, `ftp-`, `cond-`, `jit-`, `caep-`, `rev-`, `revi-`, `erase-`, `revoc-`, `jwks-`, `bat-`, `scim-`, `cbg-`, `cag-`, `saoc-`), `owner_table` (точное имя `kacho_iam.<table>` либо `clickhouse.audit_events_ch.<table>`), `folder_level` (= `account` / `project` / `cluster` / `organization` — какой scope ресурса), `status` (= `stable` после merge phase 1–12), `related_rpc[]` (массив wikilink-имён `rpc/iam-*-service`), `related_packages[]`.
- **rpc/**: `proto_file` (точный path `kacho-proto/proto/kacho/cloud/iam/v1/<file>.proto`), `backend` (= `kacho-iam`), `backend_port` (= `9090` для public, `9091` для internal), `visibility` (`public` / `internal` — НЕ путать с TLS-listener-классификацией; `internal` => только cluster-internal listener, нельзя на `api.kacho.cloud:443`), `domain` (= `iam`), `related_resource`, `methods_count`, `async_methods` (массив имён мутирующих RPC), `status`.
- **packages/**: `repo` (= `kacho-corelib` / `kacho-iam`), `layer` (= `domain` / `service` / `repo` / `clients` / `handler` / `apps` — Clean Architecture).
- **edges/**: `caller_repo` (= `kacho-iam` для всех 16), `callee_repo` (= `ory-hydra`, `ory-kratos`, `openpolicyagent`, `boxyhq-jackson`, `okta-scim`, `azure-scim`, `google-scim`, `spire`, `cilium-mesh`, `kafka-audit-cluster`, `clickhouse-audit-cluster`, `s3-audit-bucket`, `hsm-cluster`, `datadog-siem`, `splunk-siem`, `tenant-webhook`), `sync_async` (= `sync` для admin-API / `async` для outbox-drain), `protocol` (= `gRPC` / `REST` / `Kafka producer` / `S3 SDK` / `PKCS#11` / `OIDC` / `HTTP webhook` / `SCIM v2 HTTP`), `status` (= `stable`), `related_tickets[]` (= `[KAC-127]` minimum).
- **KAC/KAC-127.md**: `status: done`, `closed: 2026-<date>`, `prs: [<все 13+ PR URLs смерженных в эпике>]`, `tags: [..., closed]`.

> [!tip] Inline `#tag`-строка в конце файла — обязательно sync с `tags:` (kepano best practice). Если frontmatter говорит `tags: [iam, resource, rebac]`, то нижняя строка = `#iam #resource #rebac`.

### 2.3 Public documentation namespace topology

`docs.kacho.cloud/` — публичный документ-сайт. Phase 13 разворачивает его в **трёх namespace** (каждое со своим URL prefix, TLS-конфиг, IP-allowlist):

| Namespace | URL prefix | Audience | TLS / IP-allowlist | Built from |
|---|---|---|---|---|
| User | `https://docs.kacho.cloud/iam/` | Tenants (signup, MFA, SA, Federation, Role mgmt, JIT request, Audit query) | Public TLS (Let's Encrypt), open to internet | `docs/site/iam/` (workspace) |
| Admin | `https://docs.kacho.cloud/admin/iam/` | Cluster-admins, organization-admins (Org SSO config, SCIM token rotation, Break-glass invocation, Compliance reports download) | Public TLS + IP-allowlist via CloudFront (corp VPN ranges + on-call WAF rule) + Cloudflare Access ZeroTrust auth | `docs/site/admin/iam/` |
| Developer | `https://docs.kacho.cloud/dev/iam/` | CI/CD engineers (Federation OIDC setup snippets — GitHub Actions, AWS IRSA, GCP Workload Identity, GitLab CI) | Public TLS, open to internet | `docs/site/dev/iam/` |

**Site generator:** **Hugo** (статический сайт; D-13.1). Альтернатива Astro отвергнута — Hugo проще: одна Go-бинарь, нет Node-toolchain в CI, theme `hugo-book` или `docsy` ready-made.

**Deployment:** Hugo генерирует static HTML → S3 bucket `kacho-docs-site-prod` → CloudFront distribution `docs.kacho.cloud` (TLS + WAF + edge auth). Deploy через `kacho-deploy/ci/deploy-docs.sh` (Phase 11 wiring).

**Cross-namespace links:** разрешены, но Admin-pages НИКОГДА не embed iframe в User-pages (information disclosure) — только через explicit `<a href="https://docs.kacho.cloud/admin/iam/...">` (выглядит как обычный link, прерывается auth-gate'ом CloudFront).

### 2.4 Runbook taxonomy (нормативно)

`docs/runbooks/iam/` — operations on-call playbooks. **11 файлов**, каждый в фиксированном template (purpose / preconditions / step-by-step / verification / rollback / escalation contacts / postmortem template). Сводный индекс — `docs/runbooks/iam/README.md`. Каждый runbook **обязан** иметь:

- Frontmatter `severity: P1 / P2 / P3` (P1 = customer-impacting, P2 = degraded, P3 = preventive).
- Frontmatter `tabletop_test_date: <YYYY-MM-DD>` — Phase 13 проводит tabletop тест каждого runbook **до** APPROVED Phase 13 acceptance: на стейджинге симулируется trigger condition, on-call инженер прогоняет runbook по шагам, фиксирует пробелы. Tabletop-тест без trigger condition НЕ засчитывается.
- Frontmatter `grafana_alert_links: [...]` — список alert UIDs из Grafana, в annotations которых `runbook_url: https://docs.kacho.cloud/admin/iam/runbooks/<this>`. AlertManager `receiver` config обязан вставлять `{{ .Annotations.runbook_url }}` в Slack/PagerDuty payload.
- Section `Verification` со списком grpcurl / kubectl / SQL команд, которые **независимо** подтверждают что incident разрешён (а не «оператор уверен, что прошло»).
- Section `Rollback` со step-by-step rollback (нет — обоснование «no rollback path; forward-only fix»).
- Section `Postmortem` со ссылкой на template из `docs/postmortems/templates/iam-incident.md`.

| Runbook | Severity | Trigger | Tabletop scope |
|---|---|---|---|
| `break-glass.md` | P1 | Production выход в lockout, обычный admin-flow недоступен (Hydra/Kratos down) | Симулировать Hydra-down → admin вытаскивает HSM-keyholder; verify cluster-break-glass-grant создан + audit-event записан + alarm в SIEM |
| `key-rotation.md` | P2 | Plаново-квартальная JWKS rotation; rolling new kid через jwks endpoint | Симулировать ротацию в staging; verify все clients принимают new kid в течение grace window (24h overlap) |
| `regional-failover.md` | P1 | Primary region degradation (audit Kafka cluster unreachable, IAM Postgres replica lag > 60s) | Симулировать chaos kill primary region; verify MirrorMaker догоняет, secondary region serves authn/authz with degraded write (read-only mode) |
| `gdpr-erasure.md` | P3 | GDPR Art.17 request от Data Subject (через UI или admin email) | Создать тестового User в staging, прогнать GDPRErasureService.Create + 30-day grace + erase; verify PII удалена из User/audit_events_ch (pseudonymized), но `audit_outbox` original rows сохранены 7y |
| `audit-pipeline-incident.md` | P1 | `audit_outbox.status='failed_terminal'` rate > 0 OR drainer lag > 10min OR Kafka producer ack failed | Симулировать Kafka broker outage (1/3 brokers down); verify producer retry с idempotent prod, no dup events, lag recovered after broker restart |
| `caep-backlog.md` | P2 | `caep_outbox.next_attempt_at < now() - 1h` rows > 1000 OR subscriber repeated 5xx | Симулировать subscriber webhook 500; verify exponential backoff up to disable_on_failure threshold; verify Spec.AlertSubscriber sent to admin |
| `fga-tuple-drift-reconciliation.md` | P2 | Detection rule «FGA tuple drift» в Phase 9 fires (OpenFGA model вышла из sync с `iam.access_bindings`) | Симулировать drift через manual OpenFGA write API; verify drift detected within 15min; verify reconciler re-syncs |
| `jwks-rotation-overdue.md` | P3 | `iam.oidc_jwks_keys.rotated_at < now() - 90d` | Симулировать аномалию (frozen `last_rotation`); verify alert fires; verify runbook manual `key-rotation.md` invocation works |
| `cert-renewal-failed.md` | P2 | cert-manager renewal failed for `api.kacho.cloud` / `docs.kacho.cloud` / `*.iam.kacho.cloud` | Симулировать ACME challenge fail; verify fallback ACME provider (ZeroSSL) kicks in; verify alarm in PagerDuty |
| `kratos-flow-broken.md` | P1 | Kratos identity flow returning 5xx OR signup-rate < 50% baseline | Симулировать Kratos config-corruption; verify rollback к previous helm release works in < 10min |
| `hydra-token-error.md` | P1 | Hydra token endpoint error rate > 5% OR DPoP nonce mismatch rate > 1% | Симулировать DPoP nonce desync; verify nonce-cache cleanup runbook works |

> [!important] **Tabletop testing — gating**: ни один runbook не считается merged-ready пока в его frontmatter не выставлен `tabletop_test_date: <YYYY-MM-DD>` + commit message со ссылкой на staging incident-report `docs/postmortems/staging/iam-tabletop-<runbook>-<date>.md`. Не пропускать.

### 2.5 security.txt + Responsible disclosure (нормативно)

Phase 13 публикует на `https://kacho.cloud/.well-known/security.txt` (RFC 9116):

```
Contact: mailto:security@kacho.cloud
Contact: https://kacho.cloud/security/vulnerability-disclosure
Expires: 2027-05-19T00:00:00.000Z
Encryption: https://kacho.cloud/.well-known/pgp-key.txt
Acknowledgments: https://kacho.cloud/security/hall-of-fame
Preferred-Languages: en, ru
Canonical: https://kacho.cloud/.well-known/security.txt
Policy: https://kacho.cloud/security/responsible-disclosure
Hiring: https://kacho.cloud/jobs
```

И responsible-disclosure policy на `https://kacho.cloud/security/responsible-disclosure` (Markdown в `docs/site/security/responsible-disclosure.md`):

- Safe Harbor язык (no legal action against ethical researchers).
- Scope: production endpoints `*.kacho.cloud`, mobile/desktop apps, public APIs.
- Out of scope: 3rd-party services (Datadog/Splunk/CloudFront), social engineering, physical attacks, DoS.
- SLA: acknowledgment within 24h, triage within 5 business days, fix timeline per severity (Critical 7d, High 30d, Medium 90d, Low 180d).
- Reward structure: Hall-of-Fame + bug bounty platform integration (HackerOne signup post-GA, см. Phase 12).
- PGP key: `kacho.cloud/.well-known/pgp-key.txt` (single-purpose `security@kacho.cloud` key, не reused).

---

## 3. Decision Log (Phase 13 explicit decisions)

> Все решения зафиксированы здесь. После APPROVED — становятся базовыми для эпика.

### P13-D1: Vault files strictly 1-3KB (no exceptions)

**Decision:** Каждый файл в `obsidian/kacho/` после Phase 13 — **strict** ≤ 3KB raw bytes. Файл > 3KB ломает workspace CLAUDE.md §«Vault — Цель — minimum context» (load 1-2 narrow files, not 50KB README).

**Rationale:** уже измерено в Phase 1-12: загрузка vault-узкого 1-3KB файла = ~1.5K context tokens; загрузка 50KB CLAUDE.md per-repo = ~30K context tokens. Превышение 3KB = регрессия в budgeting tokens / снижение качества decisions у следующего инженера.

**Enforcement:** GitHub Action `vault-size-check.yaml` в `kacho-workspace` репо проверяет `find obsidian/kacho -name '*.md' -size +3k`. Если хотя бы один файл > 3KB — PR red, не мёрджится. Action добавляется как часть Phase 13 (task 13.1.5 ниже).

### P13-D2: kepano-style frontmatter mandatory (no exceptions)

**Decision:** Каждый vault-файл имеет YAML frontmatter в kepano-style (см. §2.2). Файл без frontmatter — invalid, vault Bases (kepano-native database views) его не индексируют.

**Rationale:** vault уже использует [[KAC/all-tickets|KAC tickets]] Base (фильтрует по `category: kac`, `status: in-progress | test | done`). Файл без `category` invisible в Base = invisible в onboarding. То же для resources/rpc/packages/edges Bases.

**Enforcement:** GitHub Action `vault-frontmatter-lint.yaml` (Python script проверяет YAML parsable + обязательные поля per-category из §2.2). Task 13.1.5.

### P13-D3: Public docs at docs.kacho.cloud — Hugo static site (NOT Astro)

**Decision:** Site generator = **Hugo** (Go binary, no Node toolchain).

**Rationale:** Hugo:
1. Один Go binary, доставляется в CI как `hugo` image (no `npm install` step, no `node_modules` 1GB).
2. Поддерживает frontmatter + shortcodes + multilingual (Phase 13 ships en + ru — см. responsible disclosure preferred-languages).
3. Theme `docsy` (Google-origin, used by Kubernetes docs) или `hugo-book` — out-of-box CSS, нет custom JS вкладывать.
4. Astro был рассмотрен — отвергнут из-за Node-toolchain (kacho-ui уже Vite, добавлять второй JS-toolchain в kacho-deploy CI ради docs — overhead).

**Site code path:** `kacho-workspace/docs/site/` (Hugo source tree); built artifacts → S3 → CloudFront (см. §2.3).

### P13-D4: Three namespaces (user / admin / dev) — strict TLS separation

**Decision:** `docs.kacho.cloud/iam/` (user), `docs.kacho.cloud/admin/iam/` (admin), `docs.kacho.cloud/dev/iam/` (dev). Admin-namespace IP-allowlisted (CloudFront WAF rule + Cloudflare Access ZeroTrust SSO).

**Rationale:** запрет #6 (`Internal.*` методы НЕ на external) частично распространяется на их *документирование*: внешний tenant НЕ должен видеть, что существуют `InternalCluster*` / `InternalBreakGlass*` методы — даже если он не может их вызвать. Защита от reconnaissance.

**Enforcement:** CloudFront distribution config (Terraform in `kacho-deploy/terraform/docs-site/`) добавляет WAF web ACL rule `block_non_corp_to_admin` который return 403 на `/admin/*` если source IP не в corp ranges OR auth header не подтверждён Cloudflare Access ZeroTrust.

### P13-D5: Runbooks at docs/runbooks/iam/, source of truth in workspace

**Decision:** Runbook-файлы живут в `kacho-workspace/docs/runbooks/iam/<runbook>.md`. Read-only копии могут быть синкнуты в `kacho-deploy/runbooks/iam/` deployment-bundle (для on-call portability — `runbook_url` Grafana annotation указывает на synced copy в случае workspace-repo недоступности).

**Rationale:** runbook — workspace-уровень (cross-service, on-call инструмент), не deploy-уровень (Helm config). Sync into deploy bundle — opt-in, через `kacho-deploy/scripts/sync-runbooks.sh`, не блокирует APPROVED.

### P13-D6: Runbooks tabletop-tested — non-negotiable

**Decision:** Каждый из 11 runbooks (§2.4) обязан иметь `tabletop_test_date: <YYYY-MM-DD>` в frontmatter и ссылку на staging incident-report до APPROVED Phase 13. Untested runbook = unmerged.

**Rationale:** untested runbook в production-incident — gun-in-locker без проверки. Phase 12 (chaos engineering) уже сделала chaos-runs; Phase 13 проверяет **runbook usability** на этих chaos-events. Без этого SLA «P1 mean-time-to-recovery < 30min» — fiction.

**Enforcement:** Phase 13 task 13.3.6 (separate task) — провести 11 tabletop sessions в staging. Каждая session = 30-60min, на каждый runbook, с фиксацией пробелов; пробелы fix'ятся в runbook до APPROVED.

### P13-D7: YT KAC-123 → Done только когда все 13 subtasks Done

**Decision:** YT epic KAC-123 переходит в `Done` строго в момент когда последний subtask 1-13 (acceptance + impl + tests + vault + docs) — `Done`. Не раньше.

**Rationale:** workspace CLAUDE.md «Документооборот: YouTrack `KAC` + git-флоу»: «При завершении задачи — таск в `Done` + в комментарий приложить ВСЕ требуемые артефакты». Эпик закрывается только когда все decomposition'ы закрыты.

**Enforcement:** Phase 13 task 13.4 содержит pre-flight check: `mcp__youtrack__get_issue` всех subtask KAC-128..KAC-140 (или какие там номера будут после Phase 0); если хоть один не `Done` → блокирует переход эпика.

### P13-D8: Worktree cleanup — все 10 repos после merge final PRs

**Decision:** После merge всех Phase 13 PRs (kacho-workspace + любые residual в других репо), ветка `KAC-127` удаляется во всех 10 затронутых репо (proto, corelib, iam, vpc, compute, loadbalancer, api-gateway, deploy, ui, test, workspace). Worktrees в `kacho-workspace-KAC-127/`-структуре уничтожаются через `git worktree remove`.

**Rationale:** workspace CLAUDE.md «git-флоу под задачу»: «После merge PR в `main` и перевода тикета в `Done` — удалить ветку. Это **обязательно**: открытые ветки от закрытых тикетов засоряют репо». Эпик-ветка может оставаться пока хоть один subtask открыт — но Phase 13 = последний subtask. После него — cleanup.

**Enforcement:** Phase 13 task 13.4.4 — bash script `cleanup-worktrees-KAC-127.sh` (написать в workspace) который:
1. Verify все `gh pr list --state open --search "KAC-127"` = пусто во всех 10 репо.
2. `git worktree remove kacho-workspace-KAC-127` (per repo if applicable).
3. `git push origin --delete KAC-127` (per repo).
4. `git branch -D KAC-127` локально (per repo).
5. Удалить директорию `kacho-workspace-KAC-127/` если она standalone worktree.

### P13-D9: Inline tag-string sync с frontmatter `tags:` (kepano discipline)

**Decision:** Каждый vault-файл оканчивается одной строкой `#tag1 #tag2 #tag3`, эта строка **точно** соответствует frontmatter `tags: [tag1, tag2, tag3]`. Не больше, не меньше.

**Rationale:** kepano best practice (vault уже частично соблюдает). Двойной источник = single source-of-truth для grep / Bases / search. Если inline drift'ит от frontmatter — Bases фильтрует одно, full-text search другое, инженер потерян.

**Enforcement:** GitHub Action `vault-tag-sync-check.yaml` (Python script парсит YAML frontmatter `tags`, ищет последнюю line `#tag #tag` в файле, diff'ит). Task 13.1.5.

### P13-D10: No code, no proto, no SQL in Phase 13 PRs

**Decision:** Phase 13 PRs (в kacho-workspace; никакие другие репо НЕ затрагиваются Phase 13 — только workspace и `docs.kacho.cloud` если он отдельным репо, но он в workspace) могут содержать **только** изменения в:
- `obsidian/kacho/**/*.md`
- `obsidian/kacho/**/*.base`
- `obsidian/kacho/architecture.canvas`
- `obsidian/kacho/CLAUDE.md` (только если discipline files добавляются — example: vault-size-check workflow gets added)
- `docs/site/**` (Hugo source)
- `docs/runbooks/iam/**` + `docs/runbooks/README.md`
- `docs/postmortems/staging/iam-tabletop-*-<date>.md` (tabletop reports)
- `.github/workflows/vault-*.yaml` (vault enforcement actions)
- `kacho-deploy/terraform/docs-site/**` (CloudFront/S3 IaC for docs.kacho.cloud) — может быть в отдельном PR в `kacho-deploy` репо, но это разрешено как deployment-of-Phase-13, не code-changes
- `kacho-deploy/scripts/sync-runbooks.sh` (opt-in runbook sync)

Запрещено в diff'е Phase 13 PR:
- `.go`, `.proto`, `.sql` файлы (кроме `kacho-deploy/scripts/sync-runbooks.sh` если он bash)
- Любые миграции `kacho-iam/internal/repo/migrations/*.sql`
- `*.tf` outside `docs-site/` scope

**Rationale:** Phase 13 — **documentation phase**. Любой code-change = либо out-of-scope (должен быть в Phase 1-12 PR), либо bug-fix (должен быть в отдельном KAC-ticket batch-fix). Не миксовать.

**Enforcement:** PR description Phase 13 PR обязан включать чек-лист `- [ ] No .go/.proto/.sql diff (verified by reviewer)`. PR-reviewer (`acceptance-reviewer` agent) cross-checks через `gh pr diff --name-only` filter.

---

## 4. Architecture — documentation site topology

```
+--------------------------------------------------------+
|   docs.kacho.cloud  (CloudFront distribution)          |
|                                                        |
|  +-------------+  +---------------+  +----------------+|
|  |  /iam/      |  |  /admin/iam/  |  |  /dev/iam/     ||
|  |  (user)     |  |  (admin)      |  |  (developer)   ||
|  |  Public TLS |  |  WAF + ZeroTrust|  |  Public TLS  ||
|  |             |  |  IP-allowlist  |  |               ||
|  +-------------+  +---------------+  +----------------+|
|        ^              ^                     ^         |
|        |              |                     |         |
|        +------ Origin: S3 kacho-docs-site-prod -------+|
|                          ^                             |
|        Hugo static build artifacts uploaded via         |
|        kacho-deploy/ci/deploy-docs.sh on merge to main |
+--------------------------------------------------------+
                          ^
                          | Hugo build
                          |
+--------------------------------------------------------+
|       kacho-workspace/docs/site/ (Hugo source)         |
|                                                        |
|       iam/ (user)                                      |
|       admin/iam/ (admin; rendered same but path-gated) |
|       dev/iam/ (developer)                             |
|       security/ (.well-known/security.txt source +     |
|                   responsible-disclosure.md)           |
+--------------------------------------------------------+

+--------------------------------------------------------+
|   kacho-workspace/docs/runbooks/iam/ (11 runbooks)     |
|   ↓ sync (opt-in)                                      |
|   kacho-deploy/runbooks/iam/ (deployment bundle)       |
+--------------------------------------------------------+

+--------------------------------------------------------+
|   kacho-workspace/obsidian/kacho/ (vault, 73 files)    |
|   - resources/iam-*.md  (23 files)                     |
|   - rpc/iam-*.md  (18 files)                           |
|   - edges/iam-to-*.md  (16 files)                      |
|   - packages/{corelib,iam}-apps-*.md  (15 files)       |
|   - KAC/KAC-127.md  (finalized)                        |
+--------------------------------------------------------+
```

**Build pipeline:**
1. Phase 13 PR merged → main.
2. `kacho-deploy/ci/deploy-docs.sh` triggered (GitHub Action).
3. Hugo runs in `docs/site/` → `public/`.
4. AWS S3 sync `public/` → `s3://kacho-docs-site-prod/`.
5. CloudFront invalidation `/`-pattern (paid CloudFront API call).
6. Verify via curl `https://docs.kacho.cloud/iam/` returns 200 with new content within 5min.

---

## 5. Декомпозиция (tasks 13.1–13.4 detailed)

### 5.1 Task 13.1 — Vault updates (30+ files, total 73)

Подзадачи (могут параллелиться):

| Subtask | Файлы | Responsible | Effort |
|---|---|---|---|
| 13.1.1 — resources/ создание/update | 23 файла из §2.1 первая секция | `claude` agent | 4-6 hours |
| 13.1.2 — rpc/ создание/update | 18 файлов | `claude` agent | 3-5 hours |
| 13.1.3 — edges/ создание | 16 файлов | `claude` agent | 3-4 hours |
| 13.1.4 — packages/ создание/update | 15 файлов | `claude` agent | 3-4 hours |
| 13.1.5 — vault enforcement actions | `.github/workflows/vault-size-check.yaml` + `vault-frontmatter-lint.yaml` + `vault-tag-sync-check.yaml` (3 Python-based GH Actions) | `claude` agent | 2-3 hours |
| 13.1.6 — Bases update | `obsidian/kacho/resources/all-resources.base` + `rpc/all-services.base` + `packages/all-packages.base` + `KAC/all-tickets.base` (add iam-* to filters) | `claude` agent | 1-2 hours |
| 13.1.7 — `architecture.canvas` update | Добавить cards для kacho-iam, kacho-ory-hydra/kratos/jackson, kafka-audit, clickhouse, hsm, spire; edges для 16 новых cross-service | `claude` agent | 2-3 hours |

> [!example] Format каждого нового resource file (≤ 3KB)
>
> ```markdown
> ---
> title: "iam-jit-eligibility"
> aliases: [JIT Eligibility, JIT Policy]
> category: resource
> domain: iam
> id_prefix: jit-
> owner_table: kacho_iam.jit_eligibilities
> folder_level: project
> status: stable
> related_rpc: [iam-internal-jit-eligibility-service]
> related_packages: [iam-apps-jit, corelib-authz]
> tags: [iam, resource, jit-pim, rebac]
> ---
>
> # iam-jit-eligibility
>
> > [!note] Кратко
> > JIT/PIM policy: «User X eligible to claim Role Y on Project Z, max duration D, requires Approval Mode M».
>
> ## Поля (обязательные)
>
> | Поле | Тип | FK / Constraint | Описание |
> |---|---|---|---|
> | `id` | TEXT PK | ULID `jit-<26ch>` | Surrogate |
> | `project_id` | TEXT | FK kacho_iam.projects(id) ON DELETE CASCADE | Scope |
> | `principal_user_id` | TEXT NULL | FK iam.users(id) ON DELETE CASCADE | User OR group |
> | `principal_group_id` | TEXT NULL | FK iam.groups(id) ON DELETE CASCADE | (XOR through CHECK) |
> | `role_id` | TEXT | FK iam.roles(id) ON DELETE RESTRICT | Eligible role |
> | `max_duration_seconds` | INT | CHECK > 0 AND <= 28800 (8h cap) | Per-claim max |
> | `approval_mode` | TEXT | CHECK IN ('auto','reviewer','peer') | |
> | `created_at` | TIMESTAMPTZ | default now() | |
>
> XOR через `CHECK ((principal_user_id IS NULL) <> (principal_group_id IS NULL))`.
>
> ## Lifecycle
>
> Stable. Создаётся через `InternalJITEligibilityService.Create` (admin-only). Удаляется аналогично.
>
> ## Связанное
>
> - RPC: [[rpc/iam-internal-jit-eligibility-service]]
> - Package: [[packages/iam-apps-jit]]
> - Edge: ни одного cross-service (JIT — fully in-process kacho-iam).
> - Ticket: [[KAC/KAC-127]] Phase 7.
>
> #iam #resource #jit-pim #rebac
> ```

### 5.2 Task 13.2 — KAC-127 trail finalization

**Файл:** `obsidian/kacho/KAC/KAC-127.md`

**Изменения:**
- Frontmatter: `status: done`, `closed: <YYYY-MM-DD текущий>`, `prs: [...полный список всех 13+ PR URLs во всех 10 затронутых репо...]`, `tags: [..., closed]`.
- Body: добавить секцию `## Closeout`:
  - 2-3 предложения резюме (что построено: 14 new iam-* ресурсов, 12 new RPC services, 16 cross-service edges, full audit pipeline + SPIFFE mesh + multi-region + conformance).
  - Mark ВСЕ DoD checkboxes (см. §7 DoD ниже): integration tests / newman / k6 / conformance suite / chaos / pentest / external deploy `api.kacho.cloud` / `docs.kacho.cloud` / 11 runbooks tabletop-tested / vault 73 files / public docs 3 namespaces — все галки.
  - Link to сводный changelog `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md#changelog` (если применимо).

### 5.3 Task 13.3 — Public documentation at docs.kacho.cloud

Подзадачи:

| Subtask | Файлы / артефакты | Effort |
|---|---|---|
| 13.3.1 — Hugo site scaffold | `docs/site/{config.yaml,layouts/,static/,assets/}` + theme `docsy` import | 3-4 hours |
| 13.3.2 — /iam/ user-facing pages (10+ pages: signup, MFA passkey setup, ServiceAccount creation, Federation OIDC quickstart, Role management, Custom roles, JIT claim flow, Audit query, Sessions, Account deletion/GDPR) | `docs/site/iam/*.md` | 8-12 hours |
| 13.3.3 — /admin/iam/ admin-facing pages (8+ pages: Org SSO config — Okta walkthrough / Azure AD walkthrough / Google Workspace walkthrough, SCIM token rotation, Break-glass invocation, Compliance reports download, Audit log forensic query, Detection rules custom rules) | `docs/site/admin/iam/*.md` | 8-12 hours |
| 13.3.4 — /dev/iam/ developer pages (6+ pages: Federation OIDC overview, GitHub Actions snippet, AWS IRSA snippet, GCP Workload Identity snippet, GitLab CI snippet, CLI authentication) | `docs/site/dev/iam/*.md` | 6-8 hours |
| 13.3.5 — security.txt + responsible disclosure | `docs/site/static/.well-known/security.txt` + `docs/site/security/responsible-disclosure.md` + `docs/site/security/vulnerability-disclosure.md` + `docs/site/static/.well-known/pgp-key.txt` | 2-3 hours |
| 13.3.6 — Runbooks tabletop testing (11 sessions, в staging) | 11 sessions × 30-60min + `docs/postmortems/staging/iam-tabletop-<runbook>-<YYYY-MM-DD>.md` × 11 | 12-16 hours |
| 13.3.7 — IaC for CloudFront/S3 docs-site | `kacho-deploy/terraform/docs-site/{main,cloudfront,s3,waf,acm}.tf` + WAF rule `block_non_corp_to_admin` + ACM cert | 4-6 hours |
| 13.3.8 — deploy-docs.sh CI integration | `kacho-deploy/ci/deploy-docs.sh` + GitHub Action `.github/workflows/deploy-docs.yaml` в `kacho-workspace` репо | 2-3 hours |

### 5.4 Task 13.4 — YT closeout + sprint cleanup + worktrees cleanup

| Subtask | Описание | Effort |
|---|---|---|
| 13.4.1 — Pre-flight check всех KAC-127 subtasks | Через `mcp__youtrack__get_issue` поднять список subtasks KAC-127 (3.1–3.12 + 3.13 = 13 штук) + verify ВСЕ в `Done`; если нет — блок | 30min |
| 13.4.2 — YT KAC-123 status → Done | `mcp__youtrack__update_issue_state` + добавить `comment` с финальной сводкой и линком на closeout vault note | 15min |
| 13.4.3 — Sprint cleanup (Первый спринт, id `186-22` если ещё актуальный) | Verify KAC-127+subtasks all в Done в спринте; если нужно — закрыть спринт через UI (sprint completion is manual в YT) | 30min |
| 13.4.4 — Worktrees + branches cleanup script | `kacho-workspace/scripts/cleanup-worktrees-KAC-127.sh` (см. §3 P13-D8) + run | 1-2 hours |

---

## 6. Given-When-Then сценарии (нормативные acceptance criteria)

> Каждый сценарий имеет ID `13.X.Y`. Acceptance reviewer проверяет покрытие.

### 6.1 Vault narrow files (file-size + frontmatter discipline)

#### Сценарий 13.1.1: Vault file size strictly ≤ 3KB

**Given** Phase 13 PR в `kacho-workspace` репо содержит изменения в `obsidian/kacho/`.

**When** GitHub Action `vault-size-check.yaml` запускается на pull-request event.

**Then** Action выполняет `find obsidian/kacho -name '*.md' -size +3k -print` и возвращает exit 0 (нет файлов > 3KB).

**And** при попытке create vault-file > 3KB (тестовый случай: 5KB файл искусственно добавлен) Action возвращает exit 1, blocks PR merge с message `vault-size-check: <path> exceeds 3KB limit (5120 bytes); split into narrower files`.

**And** Action runtime ≤ 30s (быстрый файловый check на ~73 files).

#### Сценарий 13.1.2: kepano frontmatter полностью валиден для всех vault-файлов

**Given** Phase 13 PR содержит 73 vault-файлов из §2.1.

**When** GitHub Action `vault-frontmatter-lint.yaml` (Python script использует `pyyaml` для парсинга frontmatter `---...---` блока) запускается.

**Then** Action проверяет:
- Каждый файл начинается с `---\n` (YAML frontmatter delimiter).
- `yaml.safe_load(frontmatter)` парсится без exception (валидный YAML).
- Обязательные поля для category present: для `resources/iam-*.md` — `title`, `category=resource`, `domain=iam`, `id_prefix`, `owner_table`, `folder_level`, `status`, `related_rpc`, `related_packages`, `tags`. Аналогично для rpc/packages/edges/KAC per §2.2.
- `tags` — массив strings, не string. Все теги — из канонического списка (`obsidian/kacho/CLAUDE.md` §«Канонические теги»).

**And** Action returns exit 0 если все 73 файла проходят; exit 1 если хоть один fail (с конкретным error per-file).

#### Сценарий 13.1.3: inline `#tag`-string synced с frontmatter `tags:`

**Given** vault-файл `obsidian/kacho/resources/iam-jit-eligibility.md` с frontmatter `tags: [iam, resource, jit-pim, rebac]`.

**When** GitHub Action `vault-tag-sync-check.yaml` парсит файл:
- frontmatter `tags` array = `['iam', 'resource', 'jit-pim', 'rebac']`.
- последняя non-empty line файла парсится regex `^(#\w[\w-]*\s*)+$` → `inline_tags = ['iam', 'resource', 'jit-pim', 'rebac']`.

**Then** Action verifies `set(frontmatter_tags) == set(inline_tags)` (порядок не важен, multiset как set ок т.к. нет duplicates).

**And** при искусственном drift (frontmatter `tags: [iam, resource]` но inline `#iam #resource #stale-tag`) Action returns exit 1 с message `<path>: inline tag string drift from frontmatter tags`.

#### Сценарий 13.1.4: Wikilinks валидны (target существует)

**Given** vault-файл `resources/iam-access-binding.md` содержит wikilink `[[rpc/iam-access-binding-service]]`.

**When** Phase 13 task 13.1.5 запускает `vault-wikilink-check.yaml` (4-я enforcement action; Python script ищет regex `\[\[([^\]|]+)(?:\|[^\]]+)?\]\]` через все `.md` файлы).

**Then** для каждого wikilink target проверяется существование файла `obsidian/kacho/<target>.md`.

**And** broken-link → exit 1 с message `<source>: wikilink target <target>.md not found`.

**And** разрешённые исключения: ссылки на `[[KAC/KAC-127]]` где `KAC-127.md` создан в `obsidian/kacho/KAC/`.

### 6.2 Vault resources/ — все 23 iam-* ресурсов покрыты

#### Сценарий 13.2.1: Все 14 новых iam-* resources созданы

**Given** Phase 1–12 ввели 14 новых iam-* ресурсов из §2.1 (iam-cluster, iam-organization, iam-federation-trust-policy, iam-access-binding-condition, iam-jit-eligibility, iam-caep-subscriber, iam-access-review, iam-access-review-item, iam-gdpr-erasure-request, iam-session-revocation, iam-oidc-jwks-key, iam-audit-signing-batch, iam-scim-user-mapping, iam-cluster-break-glass-grant, iam-cluster-admin-grant, iam-service-account-oauth-client).

**When** reviewer проверяет `ls obsidian/kacho/resources/iam-*.md` после Phase 13 task 13.1.1 merge.

**Then** все 14 файлов присутствуют (либо больше — допускается, если в Phase 1-12 появились дополнительные unreported ресурсы — workspace CLAUDE.md «Если затрагиваешь поведение, которого нет в vault — НЕ молчи. Создай новую узкую запись»).

**And** каждый файл содержит секцию `## Поля (обязательные)` с table `(поле, тип, FK/Constraint, описание)`.

**And** каждое FK-constraint в table проверяется против actual schema в `project/kacho-iam/internal/repo/migrations/*.sql` (Phase 1 migration `0013_kac127_iam_foundation.sql` + Phase 2-12 incremental migrations). Mismatch → reviewer reject.

#### Сценарий 13.2.2: Все 9 modified iam-* resources обновлены

**Given** Phase 1 ввёл базовые ресурсы `iam-account.md`, `iam-project.md`, `iam-user.md`, `iam-service-account.md`, `iam-group.md`, `iam-role.md`, `iam-access-binding.md` (7 файлов уже есть в `obsidian/kacho/resources/`); Phase 3 расширил Role с FGA tuple mapping; Phase 3 расширил AccessBinding с condition FK; и т.д.

**When** reviewer diff'ит `obsidian/kacho/resources/iam-{account,project,user,service-account,group,role,access-binding}.md` между Phase 1 baseline и Phase 13 final.

**Then** в каждом из 7+2 модифицированных файлов отражены изменения Phase 3-12:
- `iam-role.md` секция «FGA tuple mapping» (mapping `iam.role.<predefined>` → openfga tuples `user:user_id#assignee@project:project_id#role_<name>`).
- `iam-access-binding.md` секция «Condition FK» (поле `condition_id` REFERENCES `iam.access_binding_conditions(id)`).
- `iam-user.md` секция «MFA passkey» (`webauthn_credentials` JSONB column).
- `iam-service-account.md` секция «OAuth client SA flow» (OAuth client SA can be created with private_key_jwt).
- `iam-group.md` секция «SCIM provisioning» (`scim_external_id` column from Phase 6).
- `iam-account.md`, `iam-project.md` — секция «Audit emission» (мутации emit'ят audit events Phase 1+9).

#### Сценарий 13.2.3: FK contracts актуальны (cross-checked vs migrations)

**Given** Phase 1 migration `0013_kac127_iam_foundation.sql` + Phase 6 migration `0017_kac127_scim_organization.sql` + другие incremental migrations в `project/kacho-iam/internal/repo/migrations/`.

**When** reviewer для каждого `obsidian/kacho/resources/iam-*.md` парсит секцию «Поля (обязательные)» table → extract все `FK <table>(id) ON DELETE <action>` строки.

**Then** все FK constraints совпадают с actual SQL DDL в migrations (через `grep -A 100 'CREATE TABLE iam.<table>' *.sql` extract'нуть `REFERENCES` clauses).

**And** хотя бы для 5 рандомных vault-resources reviewer manually compares в SQL.

#### Сценарий 13.2.4: ID prefix actual

**Given** vault `resources/iam-jit-eligibility.md` frontmatter `id_prefix: jit-`.

**When** reviewer проверяет actual ID generation в `project/kacho-iam/internal/service/jit.go` (или соответствующий use-case file).

**Then** code использует `ids.NewWithPrefix("jit-")` (corelib `ids` package). Mismatch → reject.

**And** prefix table из §2.1 нормативна; reviewer compares каждый из 14 new files.

#### Сценарий 13.2.5: `owner_table` точное имя

**Given** vault `resources/iam-audit-signing-batch.md` frontmatter `owner_table: kacho_iam.audit_signing_batches`.

**When** reviewer проверяет actual schema in Phase 1 migration.

**Then** table `audit_signing_batches` существует в schema `iam` (a.k.a. `kacho_iam` per workspace naming).

**And** для resources с downstream-views (например, audit-events sent to ClickHouse — `audit_events_ch` materialized in CH cluster) `owner_table` указывает на canonical Postgres source `kacho_iam.audit_outbox`, не на CH downstream view (which is denormalised mirror).

### 6.3 Vault rpc/ — все 18 iam-* services покрыты

#### Сценарий 13.3.1: Все 12 новых RPC services созданы

**Given** Phase 1-12 ввели 12 новых RPC services из §2.1 (organization-service, federation-service, internal-cluster-service, internal-role-service, internal-break-glass-service, internal-jit-eligibility-service, caep-subscriber-service, access-review-service, gdpr-erasure-service, scim-v2-service, saml-service, internal-siem-service).

**When** reviewer проверяет `ls obsidian/kacho/rpc/iam-*.md`.

**Then** все 12 файлов присутствуют.

**And** для каждого: frontmatter `proto_file` точно совпадает с actual path в `kacho-proto/proto/kacho/cloud/iam/v1/*.proto`.

**And** `methods_count` равен количеству rpc-методов в `.proto`-файле (verify `grep -c '^\s*rpc ' <proto_file>`).

#### Сценарий 13.3.2: REST mapping актуальный

**Given** vault `rpc/iam-organization-service.md` секция «REST mapping» содержит table `(rpc, http_method, http_path, body_arg)`.

**When** reviewer cross-checks vs actual annotations в `.proto`-файле и api-gateway routes в `kacho-api-gateway/internal/restmux/iam.go`.

**Then** все REST routes совпадают.

**And** internal services (`visibility: internal` в frontmatter) проверяются что они зарегистрированы **только** в `iamInternalAddr` блоке (внутренний listener), не в `iamPublicAddr` (workspace CLAUDE.md «Запреты» #6).

#### Сценарий 13.3.3: Async methods правильно классифицированы

**Given** vault `rpc/iam-organization-service.md` frontmatter `async_methods: [Create, Update, Delete]` (мутации).

**When** reviewer cross-checks `.proto`-файл.

**Then** все методы из `async_methods` возвращают `kacho.cloud.operation.v1.Operation` (workspace CLAUDE.md «Запреты» #9 — все мутации async).

**And** read methods (`Get`, `List`) НЕ в `async_methods` (они sync).

**And** internal admin-методы (например, `InternalSIEMService.Create`) — согласно их acceptance docs Phase 9 §6.18, могут быть sync (admin-resource convention) — `async_methods: []` для таких; reviewer cross-checks по phase 9 acceptance что это согласовано.

#### Сценарий 13.3.4: `visibility: internal` корректно для admin services

**Given** vault `rpc/iam-internal-cluster-service.md`, `rpc/iam-internal-break-glass-service.md`, etc. (6 internal services).

**When** reviewer проверяет каждый файл.

**Then** `visibility: internal` в frontmatter.

**And** в body файла секция «Listener» = `cluster-internal (port 9091)` (НЕ external).

**And** в body файла warning callout: `> [!warning] Не публиковать на external TLS endpoint (api.kacho.cloud:443). Workspace CLAUDE.md §«Запреты» #6.`

### 6.4 Vault edges/ — все 16 cross-service edges документированы

#### Сценарий 13.4.1: Все 16 edges созданы

**Given** Phase 2-10 ввели 16 cross-service edges из §2.1 (`iam-to-hydra-admin`, `iam-to-kratos-admin`, `iam-to-opa`, `iam-to-jackson-saml`, `iam-to-scim-okta`, `iam-to-scim-azure`, `iam-to-scim-google`, `iam-to-spire`, `iam-to-cilium-mesh`, `iam-to-kafka-audit`, `iam-to-clickhouse-audit`, `iam-to-s3-audit`, `iam-to-hsm`, `iam-to-siem-datadog`, `iam-to-siem-splunk`, `iam-to-caep-subscriber-webhook`).

**When** reviewer проверяет `ls obsidian/kacho/edges/iam-to-*.md`.

**Then** все 16 файлов присутствуют.

#### Сценарий 13.4.2: Frontmatter protocol/sync_async корректный

**Given** vault `edges/iam-to-kafka-audit.md` frontmatter `protocol: Kafka producer (KRaft, ack=all, idempotent)`, `sync_async: async` (drain-based).

**When** reviewer cross-checks vs Phase 9 acceptance doc §6 (audit pipeline production).

**Then** значения совпадают.

**And** для всех 16 edges reviewer аналогично проверяет (sample-check 5 случайных).

#### Сценарий 13.4.3: «History» секция содержит KAC-trail

**Given** vault `edges/iam-to-jackson-saml.md` секция «History» содержит запись `- 2026-XX-XX: introduced in Phase 6 (KAC-127 sub-phase 3.6); SAML SP via BoxyHQ Jackson`.

**When** reviewer проверяет каждое из 16 edges.

**Then** секция «History» присутствует с минимум одной строкой указывающей на phase introduction (KAC-127 sub-phase 3.X).

**And** если edge изменялся в более поздних phases (например, Phase 10 SPIFFE добавил mTLS to Kafka) — соответствующая запись `- 2026-XX-XX: Phase 10 (KAC-127 sub-phase 3.10) — mTLS via SPIFFE` присутствует.

#### Сценарий 13.4.4: Error handling документирован для async edges

**Given** vault `edges/iam-to-caep-subscriber-webhook.md` секция «Error handling».

**When** reviewer проверяет наличие.

**Then** секция содержит explicit статус-кодовое поведение:
- `2xx → mark delivered`.
- `4xx (кроме 408/429) → mark failed_terminal; alert subscriber via Email`.
- `5xx / 408 / 429 → exponential backoff (2^n), max 24 attempts; on threshold → disable_on_failure`.
- `Idempotency-Key header передаётся; subscriber обязан дедуплицировать`.

**And** для всех 16 edges error-handling section присутствует.

### 6.5 Vault packages/ — все 15 packages документированы

#### Сценарий 13.5.1: Все 14 новых package файлов созданы

**Given** Phase 1-12 ввели 14 новых packages из §2.1.

**When** reviewer проверяет `ls obsidian/kacho/packages/{corelib,iam}-*.md`.

**Then** все 14 файлов присутствуют + 1 модифицированный (`corelib-authz`).

**And** для каждого frontmatter `repo` и `layer` корректные.

#### Сценарий 13.5.2: Exported API table актуальна

**Given** vault `packages/iam-apps-jit.md` секция «Exported types/functions» — table.

**When** reviewer cross-checks vs `project/kacho-iam/internal/apps/jit/*.go` (или соответствующий path по Clean Architecture).

**Then** все exported types/functions в table присутствуют в коде; ни одного stale entry.

**And** для 5 random packages reviewer manual checks.

#### Сценарий 13.5.3: Imports / imported-by актуальны

**Given** vault `packages/corelib-audit.md` секция «Imports» + «Imported by» (cross-package dependency).

**When** reviewer `grep -rn "kacho-corelib/audit" project/` подтверждает каждый imported-by repo.

**Then** список совпадает.

**And** Imports — точные external packages (`github.com/google/uuid`, `cloud.google.com/go/pubsub` — если применимо) — также подтверждается grep'ом imports в `project/kacho-corelib/audit/*.go`.

### 6.6 Public docs (docs.kacho.cloud)

#### Сценарий 13.6.1: Hugo site builds without errors

**Given** Phase 13 task 13.3 завершён; `docs/site/` структура полная.

**When** разработчик в локальной среде запускает `cd docs/site && hugo --minify --baseURL https://docs.kacho.cloud/`.

**Then** Hugo build returns exit 0.

**And** `public/` директория содержит сгенерированный static HTML (≥ 30 страниц, по count'у per-namespace).

**And** Hugo НЕ выдаёт warnings типа `WARN: broken shortcode`, `WARN: ref not found`.

#### Сценарий 13.6.2: Все 3 namespaces смонтированы в URL routing

**Given** Hugo build завершён.

**When** разработчик запускает `hugo server -D` и curl'ит:
- `curl -fsS http://localhost:1313/iam/` → HTTP 200, contains `<title>Kachō IAM | Get Started</title>` (или похожий).
- `curl -fsS http://localhost:1313/admin/iam/` → HTTP 200, contains `<title>Kachō IAM | Admin Operations</title>`.
- `curl -fsS http://localhost:1313/dev/iam/` → HTTP 200, contains `<title>Kachō IAM | Developer Guide</title>`.

**Then** все три namespaces serve.

#### Сценарий 13.6.3: User-facing snippets working (signup flow end-to-end сверочный)

**Given** `docs/site/iam/signup.md` страница с пошаговой инструкцией Account creation через UI.

**When** QA engineer следует инструкции **дословно** в production-like staging.

**Then** новый Account создан + verification email получен + первичный Project существует.

**And** instructions не содержат отсутствующих steps (например, не пропущена «и нажмите кнопку 'Verify'»).

#### Сценарий 13.6.4: Admin namespace TLS-protected + IP-allowlisted

**Given** CloudFront distribution `docs.kacho.cloud` deployed via `kacho-deploy/terraform/docs-site/`.

**When** non-corp IP (домашний адрес инженера, не в WAF allowlist) делает `curl -fsS https://docs.kacho.cloud/admin/iam/`.

**Then** HTTP 403 Forbidden от CloudFront WAF (response header `X-Amz-Cf-Pop: ...` подтверждает edge-block).

**And** тот же curl с corp-VPN IP (или с Cloudflare Access cookie) → HTTP 200 + admin page рендерится.

**And** `curl -fsS https://docs.kacho.cloud/iam/` (user namespace) с non-corp IP → HTTP 200 (public).

#### Сценарий 13.6.5: security.txt живой и валидный

**Given** Phase 13 task 13.3.5 опубликовал `security.txt`.

**When** curl `https://kacho.cloud/.well-known/security.txt`.

**Then** HTTP 200 + Content-Type `text/plain`.

**And** содержит ВСЕ обязательные RFC 9116 поля: `Contact:`, `Expires:` (UTC ISO 8601, > 1 year в будущее), `Canonical:` (self-URL).

**And** инструмент `securitytxt-cli validate https://kacho.cloud/.well-known/security.txt` returns exit 0.

#### Сценарий 13.6.6: Developer OIDC snippets копи-пастят и работают

**Given** `docs/site/dev/iam/github-actions-oidc.md` содержит снippet:
```yaml
- uses: actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::...:role/kacho-federation-github
    audience: https://api.kacho.cloud
```

**When** QA engineer создаёт тестовый GitHub Actions workflow и копирует snippet 1-to-1.

**Then** workflow получает Kachō Federation token (через IAM Federation OIDC trust policy созданную в Phase 5).

**And** аналогичные snippets для AWS IRSA / GCP WIF / GitLab CI работают как описано (или explicit `> [!note] Test status: end-to-end не verified в staging — only design-level`).

### 6.7 Runbooks (11 categories)

#### Сценарий 13.7.1: Все 11 runbooks present

**Given** Phase 13 task 13.3.6 завершён.

**When** `ls docs/runbooks/iam/*.md` (excluding README.md).

**Then** ровно 11 файлов (или больше, если возникли incremental runbooks; minimum 11).

**And** `docs/runbooks/iam/README.md` содержит index — таблицу всех 11 со ссылками + severity + tabletop_test_date.

#### Сценарий 13.7.2: Каждый runbook tabletop-tested

**Given** vault frontmatter каждого runbook содержит `tabletop_test_date: <YYYY-MM-DD>` + body содержит link на `docs/postmortems/staging/iam-tabletop-<runbook>-<date>.md`.

**When** reviewer проверяет:
1. `tabletop_test_date` ≤ APPROVED date - 7 дней (чтобы свежее).
2. Linked staging-report существует и содержит секции «Trigger reproduction», «Steps run», «Time-to-recovery», «Gaps found», «Runbook fixes applied».

**Then** все 11 runbooks pass.

**And** если хоть один runbook без свежего tabletop — Phase 13 reject.

#### Сценарий 13.7.3: Grafana alert annotations linked

**Given** vault frontmatter каждого runbook содержит `grafana_alert_links: [<alert-uid-1>, ...]`.

**When** reviewer выгружает Grafana alert config (через `grafana-export.sh` или API) и грепает `runbook_url`-annotation.

**Then** для каждого alert указанного в `grafana_alert_links` actual annotation `runbook_url: https://docs.kacho.cloud/admin/iam/runbooks/<runbook-name>` присутствует.

**And** AlertManager `receiver` config (`kacho-deploy/helm/alertmanager/values.yaml`) использует `{{ .Annotations.runbook_url }}` в Slack/PagerDuty templates.

#### Сценарий 13.7.4: Runbook рендерится в `/admin/iam/runbooks/` namespace

**Given** Hugo сайт собран.

**When** `curl -fsS https://docs.kacho.cloud/admin/iam/runbooks/break-glass.html` (с corp-VPN или Cloudflare Access auth).

**Then** HTTP 200, страница рендерится с навигацией к остальным 10 runbooks.

**And** все ссылки внутри страницы (например, на security.txt, postmortem template) — кликабельны и не broken.

### 6.8 KAC-127 trail (closeout)

#### Сценарий 13.8.1: KAC-127.md финальный state корректный

**Given** Phase 13 task 13.2 завершён.

**When** reviewer проверяет `obsidian/kacho/KAC/KAC-127.md` frontmatter.

**Then**:
- `status: done`.
- `closed: <YYYY-MM-DD>` ≤ APPROVED date (заполняется в день closeout).
- `prs: [...]` содержит **минимум 13 PR URLs** (по одному minimum на каждый sub-phase; реально больше — multiple PRs per phase due to multi-repo work).
- `tags: [...., closed]` — добавлен `closed`.

#### Сценарий 13.8.2: PR URLs все смерженные в main

**Given** `prs:` массив в KAC-127.md frontmatter.

**When** для каждого PR URL `gh pr view <url> --json state,mergedAt` запрашивается.

**Then** все PRs имеют `state: MERGED` + `mergedAt` non-null.

**And** ни одного `OPEN` или `CLOSED` (non-merged) PR в списке.

#### Сценарий 13.8.3: DoD checkboxes все mark

**Given** body `KAC-127.md` содержит секцию «## Acceptance / Definition of Done» с checklist'ом из §7 текущего документа.

**When** reviewer проверяет.

**Then** все checkboxes `[x]` (mark'нуты).

**And** ни одного `[ ]` (unmark'нутого) — иначе значит DoD не выполнен и Phase 13 не должна closeout'иться.

### 6.9 YT closure

#### Сценарий 13.9.1: YT KAC-123 → Done только когда все subtasks Done

**Given** Phase 13 task 13.4.1 запускает pre-flight check.

**When** через `mcp__youtrack__search_with_filter` запрашиваются все subtasks parent=KAC-123 (либо `KAC-127` — vault label; real YT id = `KAC-123`).

**Then** **ВСЕ** subtasks возвращают `state: Done`.

**And** если хоть один subtask `In Progress` / `Test` — Phase 13 task 13.4.2 БЛОКИРУЕТСЯ (нельзя закрывать эпик).

#### Сценарий 13.9.2: YT KAC-123 переходит в Done с финальным комментарием

**Given** все 13 subtasks Done.

**When** Phase 13 task 13.4.2 запускает `mcp__youtrack__update_issue_state KAC-123 Done` + `mcp__youtrack__add_comment KAC-123 "<final summary с линком на vault KAC-127.md>"`.

**Then** YT KAC-123 показывает `state: Done`.

**And** последний комментарий — финальная сводка с PR-URLs списком + ссылкой на `docs/specs/sub-phase-3.13-iam-docs-closeout-acceptance.md`.

### 6.10 Worktrees cleanup

#### Сценарий 13.10.1: Pre-cleanup verification (нет open PRs с KAC-127)

**Given** Phase 13 task 13.4.4 запускает cleanup-script.

**When** для каждого из 10 затронутых репо: `gh pr list --state open --search "KAC-127"` запрашивается.

**Then** результат — пустой список (нет открытых PRs).

**And** если хоть один open PR — script abort'ит с message `PR <url> still open in <repo>; cannot cleanup branch yet`.

#### Сценарий 13.10.2: Worktrees + branches удалены post-merge

**Given** все KAC-127 PRs merged + script `cleanup-worktrees-KAC-127.sh` запущен.

**When** для каждого из 10 репо:
- `git worktree list` НЕ показывает `kacho-workspace-KAC-127`.
- `git push origin --delete KAC-127` returns 0 (или 422 «already deleted»).
- `git branch -D KAC-127` returns 0.

**Then** скрипт finishes exit 0 (allows 422 «already deleted» как success).

**And** `git worktree list` в workspace показывает только main worktree.

**And** workspace cwd back to standard `/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/` (не `kacho-workspace-KAC-127/`).

---

## 7. Definition of Done (Phase 13 final closeout)

> [!important] Все пункты ниже должны быть `[x]` чтобы Phase 13 acceptance reviewer выставил APPROVED + YT KAC-123 → Done. Этот же чек-лист дублируется в `obsidian/kacho/KAC/KAC-127.md` body.

### 7.1 Vault (73 files touched)

- [ ] **resources/iam-*.md** — 14 new + 9 modified, ВСЕ файлы ≤ 3KB, frontmatter kepano-compliant, FK contracts актуальны vs migrations, ID prefix actual, `owner_table` точное имя.
- [ ] **rpc/iam-*.md** — 12 new + 6 modified, frontmatter `proto_file` actual, `methods_count` correct, REST mapping актуальный, `visibility` internal vs public корректно, `async_methods` per workspace CLAUDE.md «Запреты» #9.
- [ ] **edges/iam-to-*.md** — 16 new, frontmatter protocol/sync_async actual, «History» с KAC-trail, «Error handling» секция для async.
- [ ] **packages/{corelib,iam}-*.md** — 14 new + 1 modified, exported API actual vs code, imports/imported-by accurate.
- [ ] **Bases updated** (`all-resources.base`, `all-services.base`, `all-packages.base`, `all-tickets.base`) — фильтры включают новые iam-* entries.
- [ ] **architecture.canvas** — добавлены cards: kacho-iam (расширенный из baseline), ory-hydra, ory-kratos, boxyhq-jackson, openpolicyagent, spire, kafka-audit, clickhouse-audit, hsm-cluster, datadog-siem, splunk-siem; edges 16 новых cross-service.
- [ ] **Vault enforcement actions** in `.github/workflows/`: `vault-size-check.yaml`, `vault-frontmatter-lint.yaml`, `vault-tag-sync-check.yaml`, `vault-wikilink-check.yaml` — все 4 зелёные на main.

### 7.2 KAC-127 trail (final)

- [ ] `obsidian/kacho/KAC/KAC-127.md` frontmatter `status: done`, `closed: <date>`, `prs: [13+ URLs]`, `tags: [..., closed]`.
- [ ] Body содержит секцию «## Closeout» с резюме + DoD checkboxes все mark.
- [ ] PR URLs все verified `state: MERGED` через `gh pr view`.

### 7.3 Public documentation (docs.kacho.cloud)

- [ ] Hugo site builds без errors/warnings (`hugo --minify --baseURL https://docs.kacho.cloud/`).
- [ ] `/iam/` namespace — минимум 10 user-facing pages, HTTP 200 public.
- [ ] `/admin/iam/` namespace — минимум 8 admin pages, TLS + WAF + ZeroTrust auth working (non-corp IP → 403; corp/auth → 200).
- [ ] `/dev/iam/` namespace — минимум 6 dev pages, OIDC snippets verified working для GitHub Actions / AWS IRSA / GCP WIF / GitLab CI.
- [ ] `https://kacho.cloud/.well-known/security.txt` HTTP 200, RFC 9116 valid.
- [ ] `https://kacho.cloud/security/responsible-disclosure` HTTP 200, Safe Harbor язык present.
- [ ] CloudFront distribution `docs.kacho.cloud` deployed via `kacho-deploy/terraform/docs-site/`.
- [ ] CI integration: GitHub Action `deploy-docs.yaml` triggers Hugo build + S3 sync + CloudFront invalidation on workspace `main` push.

### 7.4 Runbooks

- [ ] `docs/runbooks/iam/` содержит 11 runbooks (break-glass, key-rotation, regional-failover, gdpr-erasure, audit-pipeline-incident, caep-backlog, fga-tuple-drift-reconciliation, jwks-rotation-overdue, cert-renewal-failed, kratos-flow-broken, hydra-token-error).
- [ ] `docs/runbooks/iam/README.md` — index с severity + tabletop_test_date table.
- [ ] **Каждый из 11 runbooks tabletop-tested** в staging — соответствующий `docs/postmortems/staging/iam-tabletop-<runbook>-<date>.md` существует.
- [ ] Все 11 frontmatter `tabletop_test_date` ≤ APPROVED date - 7d.
- [ ] Grafana alert annotations `runbook_url` linked для каждого runbook (verified через `grafana-export.sh`).
- [ ] AlertManager templates используют `{{ .Annotations.runbook_url }}` в Slack/PagerDuty payload.
- [ ] Runbooks рендерятся в `/admin/iam/runbooks/` namespace, доступны через `docs.kacho.cloud/admin/iam/runbooks/<name>.html`.

### 7.5 YT closeout + worktree cleanup

- [ ] Pre-flight verified: все subtasks KAC-127 (3.1–3.13) в YT в `Done`.
- [ ] YT KAC-123 переведён в `Done` + финальный комментарий с PR-list + vault link.
- [ ] Sprint (Первый спринт, или актуальный) — closed либо проверено что KAC-127 entries `Done` в нём.
- [ ] Cleanup-script запущен: все KAC-127 branches удалены в 10 репо (proto/corelib/iam/vpc/compute/loadbalancer/api-gateway/deploy/ui/test/workspace).
- [ ] Worktrees `kacho-workspace-KAC-127/`-структуры удалены (`git worktree remove` returned 0).
- [ ] Workspace cwd standard.

### 7.6 No code в Phase 13 PRs (P13-D10 enforcement)

- [ ] PR diff (`gh pr diff --name-only`) для каждого Phase 13 PR содержит **только**:
  - `obsidian/kacho/**` или
  - `docs/site/**` или
  - `docs/runbooks/**` или
  - `docs/postmortems/staging/**` или
  - `.github/workflows/vault-*.yaml` или
  - `kacho-deploy/terraform/docs-site/**` (если включён в Phase 13 PR; иначе отдельный deploy-PR) или
  - `kacho-deploy/scripts/sync-runbooks.sh` или
  - `kacho-deploy/ci/deploy-docs.sh`.
- [ ] **Ни одного** `.go` / `.proto` / `.sql` файла в diff.
- [ ] Reviewer (`acceptance-reviewer` agent) verified этот checklist.

---

## 8. Cross-repo PR-chain

Phase 13 — preliminary documentation phase. Затронутые репо:

| Репо | PRs | Содержимое | Branch |
|---|---|---|---|
| `kacho-workspace` | 1-2 main PRs | obsidian/kacho/ (vault 73 files), docs/site/ (Hugo source), docs/runbooks/iam/ (11), docs/postmortems/staging/iam-tabletop-*.md (11), .github/workflows/vault-*.yaml, .github/workflows/deploy-docs.yaml, scripts/cleanup-worktrees-KAC-127.sh | `KAC-127` |
| `kacho-deploy` | 1 PR (optional, может быть merged в составе workspace PR если monorepo-friendly) | terraform/docs-site/{main,cloudfront,s3,waf,acm}.tf, ci/deploy-docs.sh, scripts/sync-runbooks.sh, runbooks/iam/ (synced copies — optional) | `KAC-127` |

**Порядок merge:**
1. `kacho-deploy` PR — IaC + CI deploy-docs script (так как docs.kacho.cloud distribution должен существовать до того, как deploy-docs CI Action запустится).
2. `kacho-workspace` PR (main) — vault + Hugo source + runbooks + postmortems + vault enforcement actions + deploy-docs Action.
3. Сразу после merge workspace `main` → deploy-docs Action triggers → Hugo builds → S3 sync → CloudFront invalidation → live within 10min.
4. После manual verify что live (curl HTTP 200 на все 3 namespaces) → `cleanup-worktrees-KAC-127.sh` запускается → branches deleted.
5. YT KAC-123 → Done.

> [!note] Никакие PRs в `kacho-proto`, `kacho-corelib`, `kacho-iam`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`, `kacho-api-gateway`, `kacho-ui`, `kacho-test` от Phase 13 НЕ открываются. Если такой PR появился в Phase 13 — это нарушение P13-D10, reviewer reject.

---

## 9. Out of scope (этой Phase 13, явно)

Чтобы не было путаницы — что НЕ делает Phase 13:

| Артефакт | Где должно быть |
|---|---|
| Production deployment manifests (`kacho-deploy/helm/*`) | Phase 11 |
| Conformance tests / pentest report / fuzz harness | Phase 12 |
| SPIFFE mesh runtime config | Phase 10 |
| Multi-region mirrormaker config | Phase 11 |
| Public docs о non-IAM сервисах (compute / vpc / loadbalancer) | Out of scope KAC-127 целиком; future epic |
| Marketing landing pages (kacho.cloud root) | Out of scope KAC-127 — отдельный marketing-эпик |
| Russian translation `/iam/` namespace | `Preferred-Languages: en, ru` в security.txt не означает что ВСЕ docs переведены; только security.txt + responsible-disclosure ru. Полный i18n — future epic |
| Bug bounty platform integration (HackerOne signup) | Post-GA, отдельный security-эпик |
| FedRAMP ATO formal submission | Future epic после Phase 12 conformance |
| SOC 2 Type II formal auditor engagement | Pre-engagement consultation сделано в Phase 12; formal audit — future |

---

## 10. Open Questions (resolved before APPROVED)

Все вопросы которые могли затормозить Phase 13 — закрыты:

| Вопрос | Решение |
|---|---|
| Hugo vs Astro? | **Hugo** (P13-D3) |
| Hugo theme? | `docsy` (Google-origin, used by Kubernetes docs) — production-ready, no custom CSS overhead |
| Admin namespace auth? | Cloudflare Access ZeroTrust (SSO via existing corp Okta) + WAF IP-allowlist (defense-in-depth) |
| security.txt где хостится? | `https://kacho.cloud/.well-known/security.txt` (root domain, не на docs subdomain) — RFC 9116 compliance |
| Runbook source-of-truth: workspace или deploy? | **workspace** (P13-D5); deploy copies — opt-in sync |
| Tabletop в staging или prod? | **Staging** (никогда не prod) — P13-D6; staging должен быть production-like (Phase 11 spec'ит staging cluster) |
| Включать deploy-docs в Phase 13 PR или отдельный deploy-эпик? | Phase 13 PR scope (P13-D10 explicit allows kacho-deploy/terraform/docs-site/ и ci/deploy-docs.sh) |
| Что если Phase 1-12 PRs продолжают merge'ить ПОСЛЕ Phase 13 acceptance APPROVED? | Phase 13 acceptance APPROVED — gate на START Phase 13 work; реальный CLOSEOUT (`status: done`, YT Done) — после ВСЕ subtasks Done (P13-D7). Если новый Phase X PR смержен после Phase 13 work-start (но до closeout) — vault обновляется incrementally; этот же KAC-127.md PRs список обновляется до finalization. |
| Что если runbook tabletop вскрыл gaps требующие code-fix? | Code-fix НЕ в Phase 13 (P13-D10); открывается **новый KAC-ticket** (`bug` / `tech-debt`), линкуется к KAC-127 как follow-up; runbook fix'ится; tabletop повторяется до зелёного. Если gap critical и блокирует production — phase 13 acceptance hold'ится до closure. |
| ToFn делать `vault-wikilink-check.yaml` как 4-й vault Action? | **Да**, добавляем (явно в task 13.1.5). 3 enforcement actions из P13-D1/D2/D9 не покрывают wikilink validity — это 4-я. |

---

> [!important] APPROVED gate
> До APPROVED от `acceptance-reviewer` Phase 13 НЕ стартует. После APPROVED — задачи 13.1–13.4 параллельные (vault + public docs + runbook tabletop), затем последовательно 13.4.1 → 13.4.2 → 13.4.3 → 13.4.4 (pre-flight → YT Done → sprint cleanup → worktree cleanup).

#sub-phase-3-13 #iam #docs #vault #runbooks #closeout #kac-127
