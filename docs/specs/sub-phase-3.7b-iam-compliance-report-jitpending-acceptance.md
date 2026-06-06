# Sub-phase 3.7b — IAM Compliance Report + JitPending Approval Flow (KAC-127 / YT KAC-123) — Acceptance

> **Status**: APPROVED — `acceptance-reviewer` 2026-05-21 (30 GWT, spec coverage 100%, traceability confirmed, запреты #1-#11 соблюдены; 4 non-blocking замечания учесть в плане/impl).
> **Date**: 2026-05-21
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Predecessor acceptance**: `sub-phase-3.7-iam-jit-breakglass-reviews-gdpr-acceptance.md` — Phase 7 base (JIT/PIM + Break-glass + Access Reviews + GDPR). **Этот документ — addendum (`3.7b`)** под две фичи, которые были помечены в Phase 7 base как known-gaps без service-layer foundation и осознанно deferred.
> **Audit / S3 patterns**: `sub-phase-3.9-iam-audit-pipeline-acceptance.md` — S3 bucket layout (§2.5/§2.7), HSM-signed manifest (§P9-D9), Merkle batch chain (§P9-D11), GDPR pseudonymization в audit (§P9-D26).
> **Compliance mappings**: `sub-phase-3.12-iam-conformance-pentest-chaos-acceptance.md` — SOC 2 Type II control map (§2.2), ISO 27001:2022 Annex A, NIST CSF 2.0, GDPR Art. 17/32/33 (`docs/security/*-mapping.md`).
> **Phase position**: завершающий addendum Phase 7 под KAC-127; обе фичи закрывают известные gaps из `obsidian/kacho/KAC/KAC-127.md`.

---

## 0. Преамбула — зачем отдельный `3.7b`

Phase 7 base (`sub-phase-3.7-…`) реализован: JIT eligibility CRUD + ActivateJIT, Break-glass 2-person workflow, Access Reviews quarterly, GDPR erasure pipeline, `corelib/notify` (commit `kacho-iam a6caf51` + Phase 7 gRPC handlers `97705dc`). При реализации **два пункта** остались без service-layer foundation и были задокументированы как known-gaps в `obsidian/kacho/KAC/KAC-127.md`:

1. **`ComplianceReportService.GenerateAccessReport`** — RPC не имеет use-case на service-слое вообще. Phase 7 base ввёл governance-данные (AccessBindings, JIT activations, Break-glass usage, Access Review outcomes, GDPR erasure requests), но не агрегатор, который собирает их в единый подписанный compliance-отчёт для аудитора.

2. **`ApproveJITActivation` / JitPending flow** — `JITService.ApproveJIT` (`kacho-iam/internal/service/phase7_jit_service.go:343`) — explicit stub `return errors.New("ApproveJIT: bind to AccessBinding repo...")`. Phase 7 base описал сценарии `7-17…7-21` (JIT с approval), но `JitPending` aggregate и approval use-case реально не реализованы — handler возвращает stub-ошибку.

Обе фичи были корректно deferred: на момент Phase 7 base ещё не было устойчивого service-layer foundation (compliance-агрегатор требует, чтобы все источники Phase 7 уже писали свои таблицы; JitPending approval требует завершённого `ActivateJIT` happy-path). Сейчас foundation есть → `3.7b` закрывает оба gap'а до начала кодирования (запрет #1).

**Этот документ покрывает РОВНО эти 2 фичи.** Break-glass, Access Reviews, GDPR erasure pipeline, `corelib/notify`, audit drainer, CAEP push — НЕ в scope `3.7b` (реализованы в Phase 7 base / Phase 8 / Phase 9 соответственно). Расширение scope запрещено.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать «yandex» | в proto / коде / комментариях / env-names / report-templates / vault — не упоминается; YC-стилистика error-text сохраняется (`"<Resource> %s not found"`, `"Illegal argument <thing>"`) |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx для `access_bindings_jit_pending` и `compliance_reports`; S3-доступ — AWS SDK v2 (`aws-sdk-go-v2/service/s3`), без ORM |
| **Запрет #4** — НЕ каскад через границу сервиса | Compliance report агрегирует **только** данные `kacho_iam` schema; per-resource AccessBinding scope ссылается на vpc/compute ресурсы по id-строке (denormalised mirror, не cascade); JitPending → AccessBinding mint — same-DB |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 7 base миграции (`0011..0014`, `0021`) не изменяются; `3.7b` вводит **новую** миграцию `0022_kac127_phase7b_compliance_jitpending.sql` (таблицы `compliance_reports`, `access_bindings_jit_pending` если ещё не создана в base, доп. indexes) |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `ComplianceReportService` — **public** RPC (аудитор / account-admin self-service, scope-ограничен FGA Check), регистрируется на public mux **с** acr=3 step-up gate; `JitPendingService` — **public** (approver self-service), public mux, acr=3 gate на Approve/Deny. Никаких internal-only RPC в `3.7b` |
| **Запрет #7** — НЕ broker | report generation — background-job-driven (Operation + worker), in-process; S3 upload — прямой HTTP SDK; нет Kafka/NATS |
| **Запрет #8** — DB-per-service | `compliance_reports` и `access_bindings_jit_pending` — внутри `kacho_iam` schema; S3 bucket `kacho-compliance-reports` — external object store (не БД), доступ через SDK |
| **Запрет #9** — async-only мутации | `GenerateAccessReport` → `Operation` (async — сборка может занять секунды-минуты на больших scope); `ApproveJITActivation` / `DenyJITActivation` → `Operation`; sync-read остаётся sync (`GetComplianceReport`, `ListComplianceReports`, `GetJitPending`, `ListJitPending`) |
| **Запрет #10** — within-service refs на DB-уровне | **критично для JitPending**: state-машина `PENDING → APPROVED / DENIED / TIMEOUT_EXPIRED` реализуется **атомарным conditional UPDATE с CAS-условием** `WHERE id=$1 AND decision IS NULL` + проверка RETURNING-кардинальности; `compliance_reports.status` (`PENDING → RUNNING → COMPLETED / FAILED`) — то же; mint AccessBinding из JitPending — partial UNIQUE на `(user_id, role_id, resource_type, resource_id) WHERE status='ACTIVE'` (как `7-16`); никакого software check-then-act |
| **Запрет #11** — тесты в том же PR | каждый PR `3.7b`: kacho-proto — `buf lint` + `buf breaking`; kacho-iam — integration-tests testcontainers Postgres (compliance report aggregation; JitPending approve/deny CAS race; double-approve race; report для пустого scope; large-scope pagination) + S3 — recorded/minio backend; newman cases — happy + negative per RPC; запрещены формулировки «follow-up» / «out of scope» без trackable KAC-тикета |

---

## 2. Глоссарий / доменная модель `3.7b` (нормативно)

### 2.1 `ComplianceReport` — новая сущность

Конфиг/артефакт-ресурс «сгенерированный подписанный compliance-отчёт за период по scope». Таблица `compliance_reports` (создаётся миграцией `0022`):

- `id TEXT PRIMARY KEY` — prefix `cmr_`.
- `scope_type TEXT NOT NULL CHECK (scope_type IN ('account','project','organization'))`.
- `scope_id TEXT NOT NULL` — id Account / Project / Organization (denormalised mirror; не FK на cross-domain, но Account/Project — same-DB `kacho_iam` → FK `REFERENCES` где применимо).
- `range_start TIMESTAMPTZ NOT NULL`, `range_end TIMESTAMPTZ NOT NULL` — отчётный период; `CHECK (range_end > range_start)`.
- `status TEXT NOT NULL CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED'))` DEFAULT `'PENDING'`.
- `format TEXT NOT NULL CHECK (format IN ('CSV','PDF')) DEFAULT 'CSV'`.
- `s3_uri TEXT` — nullable до COMPLETED; `s3://kacho-compliance-reports/<scope_type>/<scope_id>/<yyyy>/<report_id>.<csv|pdf>`.
- `s3_manifest_uri TEXT` — nullable до COMPLETED; `<s3_uri>.manifest.signed` (HSM-signed manifest по образцу §P9-D9 audit-pipeline; ECDSA P-384, kid `compliance-signer-v1`).
- `report_sha256 TEXT` — nullable до COMPLETED; SHA-256 артефакта (в manifest и в response).
- `row_counts JSONB NOT NULL DEFAULT '{}'` — счётчики секций отчёта `{access_bindings, jit_activations, break_glass_usages, access_review_outcomes, gdpr_erasure_requests}`.
- `failure_reason TEXT` — nullable; populated если `status='FAILED'`.
- `requested_by TEXT REFERENCES users(id) NOT NULL`.
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `completed_at TIMESTAMPTZ` (nullable).
- **DB-уровень инварианты**: `CHECK (range_end > range_start)`; `CHECK (status <> 'COMPLETED' OR (s3_uri IS NOT NULL AND report_sha256 IS NOT NULL))`; `CHECK (status <> 'FAILED' OR failure_reason IS NOT NULL)`.
- **Lifecycle**: `PENDING` (row inserted, Operation возвращён) → `RUNNING` (worker подхватил, CAS UPDATE) → `COMPLETED` (артефакт в S3, manifest подписан) **или** `FAILED` (worker записал `failure_reason`). Immutable после терминального статуса (артефакт — write-once).

### 2.2 `JitPending` — новая сущность (закрывает stub `phase7_jit_service.go:343`)

JIT activation request, требующий approval (когда `JITEligibility.approval_required=true`). Таблица `access_bindings_jit_pending` (Phase 7 base §6.3 ссылался на неё в сценариях `7-17…7-21`, но реально не реализована — создаётся/финализируется миграцией `0022`):

- `id TEXT PRIMARY KEY` — prefix `jp_`.
- `eligibility_id TEXT REFERENCES access_bindings_jit_eligibility(id) ON DELETE CASCADE NOT NULL`.
- `requested_by TEXT REFERENCES users(id) NOT NULL` — субъект-активатор (всегда = `eligibility.user_id`).
- `approver_user_id TEXT REFERENCES users(id) NOT NULL` — копия `eligibility.approver_user_id` на момент создания (immutable snapshot).
- `duration_seconds INT NOT NULL CHECK (duration_seconds BETWEEN 60 AND 28800)` — запрошенная длительность, уже валидирована против `eligibility.max_duration`.
- `justification TEXT NOT NULL CHECK (length(justification) >= 1)`.
- `operation_id TEXT NOT NULL` — id `Operation`, возвращённого вызывающему `ActivateJIT`; worker по approve/deny finaliz'ит именно его.
- `decision TEXT CHECK (decision IN ('approved','denied','timeout_expired'))` — nullable пока PENDING.
- `decided_by TEXT REFERENCES users(id)` — nullable; populated на approve/deny (NULL для timeout).
- `decided_at TIMESTAMPTZ` — nullable.
- `decision_reason TEXT` — nullable; required на `denied`.
- `materialized_binding_id TEXT REFERENCES access_bindings(id)` — nullable; set при approve → id заминченного AccessBinding.
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `expires_at TIMESTAMPTZ NOT NULL` — `created_at + interval '24 hours'` (approval-окно).
- **Производное status** (не колонка — выводится): `PENDING` если `decision IS NULL`; иначе терминал по `decision`.
- **DB-уровень инварианты**: `CHECK (decision <> 'denied' OR decision_reason IS NOT NULL)`; `CHECK (decision <> 'approved' OR materialized_binding_id IS NOT NULL)`; `CHECK ((decision IS NULL) = (decided_at IS NULL AND materialized_binding_id IS NULL))` (PENDING ⟺ нет решения); partial UNIQUE `(eligibility_id) WHERE decision IS NULL` (одна PENDING-заявка per eligibility — повторный `ActivateJIT` не плодит дубль).
- **State-машина** (атомарный CAS, запрет #10): `UPDATE access_bindings_jit_pending SET decision=$2, decided_by=$3, decided_at=now(), … WHERE id=$1 AND decision IS NULL RETURNING id` — 0 rows → `ErrFailedPrecondition` (уже решена / double-approve / approve-после-timeout).

### 2.3 Связь с существующими Phase 7 base сущностями

- `JITEligibility` (Phase 7 base §2.1) — `3.7b` **читает** её при `ActivateJIT(approval_required=true)`, не меняет схему.
- `AccessBinding` — `3.7b` минтит row при `ApproveJITActivation` (как Phase 7 base `7-08`/`7-18`): `status='ACTIVE'`, `condition_id='cnd_jit_window'`, `expires_at = now + duration_seconds`, `jit_eligibility_id` заполнен. Атомарно с `fga_outbox` + `caep_outbox` + `audit_outbox` rows в одной транзакции.
- `audit_outbox` — `3.7b` пишет события: `iam.jit.activation_requested`, `iam.jit.activation_approved`, `iam.jit.activation_denied`, `iam.jit.activation_timeout`, `iam.compliance.report_requested`, `iam.compliance.report_completed`, `iam.compliance.report_failed`. Drainer (Phase 9) их consume'ит — `3.7b` тестит только «row appeared с правильным event-type».
- `corelib/notify` (Phase 7 base) — `3.7b` **переиспользует** для Slack DM / email approver'у (фича 2). Не вводит новый notify-канал.

### 2.4 RPC-поверхность `3.7b` (нормативно)

Proto-пакет `kacho.cloud.iam.v1` (фактический layout `kacho-proto/proto/kacho/cloud/iam/v1/`; additive only — `buf breaking` зелёный).

**`ComplianceReportService`** (public mux):

| RPC | Тип | Sync/Async | Step-up |
|---|---|---|---|
| `GenerateAccessReport(GenerateAccessReportRequest) → operation.Operation` | мутация | async | acr=3 required |
| `GetComplianceReport(GetComplianceReportRequest) → ComplianceReport` | read | sync | acr=2 OK |
| `ListComplianceReports(ListComplianceReportsRequest) → ListComplianceReportsResponse` | read | sync | acr=2 OK |
| `GetReportDownloadUrl(GetReportDownloadUrlRequest) → ReportDownloadUrlResponse` | read | sync | acr=3 required (presigned-URL — sensitive) |

REST mapping: `POST /iam/v1/complianceReports:generateAccessReport`, `GET /iam/v1/complianceReports/{report_id}`, `GET /iam/v1/complianceReports`, `POST /iam/v1/complianceReports/{report_id}:getDownloadUrl`.

**`JitPendingService`** (public mux):

| RPC | Тип | Sync/Async | Step-up |
|---|---|---|---|
| `ApproveJITActivation(ApproveJITActivationRequest) → operation.Operation` | мутация | async | acr=3 required |
| `DenyJITActivation(DenyJITActivationRequest) → operation.Operation` | мутация | async | acr=3 required |
| `GetJitPending(GetJitPendingRequest) → JitPending` | read | sync | acr=2 OK |
| `ListJitPending(ListJitPendingRequest) → ListJitPendingResponse` | read | sync | acr=2 OK |

REST mapping: `POST /iam/v1/jitPending/{request_id}:approve`, `POST /iam/v1/jitPending/{request_id}:deny`, `GET /iam/v1/jitPending/{request_id}`, `GET /iam/v1/jitPending`.

> `ActivateJIT` (Phase 7 base `AccessBindingService.ActivateJIT`) **не меняет proto-сигнатуру** — `3.7b` лишь заменяет stub-поведение для случая `approval_required=true`: вместо немедленного mint он создаёт `JitPending` row и оставляет `Operation` в `done=false` до решения approver'а. Это поведенческое (не proto-breaking) изменение, отражённое сценариями ниже.

---

## 3. Acceptance-сценарии

> Каждый сценарий имеет уникальный **ID** `7b-NN` — для трассировки к integration / newman cases. Negative-сценарии содержат ожидаемый gRPC-код из таблицы `02-data-model-and-conventions.md §14`. Все мутирующие RPC возвращают `Operation` (запрет #9).

### 3.1 Фича 1 — `ComplianceReportService.GenerateAccessReport`

#### Сценарий 7b-01: GenerateAccessReport — happy path (account scope)

**ID**: `7b-01`

**Given** Account `acc_alpha` существует, у него 2 Project'а с в сумме 14 активными `access_bindings`
**And** за период `[2026-01-01, 2026-04-01)` произошло: 6 JIT activations, 1 Break-glass usage (ACTIVE→EXPIRED), 9 Access Review outcomes (7 confirm / 2 revoke), 2 GDPR erasure requests
**And** caller `usr_auditor` имеет fresh acr=3 token и FGA-permission `iam.complianceReports.create` на `account:acc_alpha`
**And** S3 bucket `kacho-compliance-reports` доступен

**When** `usr_auditor` calls `ComplianceReportService/GenerateAccessReport` через REST `POST /iam/v1/complianceReports:generateAccessReport` body:
  - scope_type = "account"
  - scope_id = "acc_alpha"
  - range_start = "2026-01-01T00:00:00Z"
  - range_end = "2026-04-01T00:00:00Z"
  - format = "CSV"

**Then** response = `Operation { id: op_xxx, done: false }` HTTP 200
**And** в `compliance_reports` появляется row `{ id: cmr_xxx, scope_type: account, scope_id: acc_alpha, status: PENDING, requested_by: usr_auditor }`
**And** в `audit_outbox` появляется event `iam.compliance.report_requested` (actor=usr_auditor, target=cmr_xxx, outcome=success)
**And** background-worker подхватывает row → CAS UPDATE `status='RUNNING'`
**And** worker агрегирует 5 секций и формирует CSV-артефакт; uploads в `s3://kacho-compliance-reports/account/acc_alpha/2026/cmr_xxx.csv`
**And** worker формирует `cmr_xxx.csv.manifest.signed` — HSM-signed (ECDSA P-384, kid `compliance-signer-v1`) с `report_sha256`, `row_counts`, `range`, `generated_at`
**And** worker CAS UPDATE `status='COMPLETED'`, `s3_uri`, `s3_manifest_uri`, `report_sha256`, `row_counts = {access_bindings:14, jit_activations:6, break_glass_usages:1, access_review_outcomes:9, gdpr_erasure_requests:2}`, `completed_at=now`
**And** клиент polls `OperationService.Get(op_xxx)` → eventually `done=true`, `response = ComplianceReport { id: cmr_xxx, status: COMPLETED, row_counts: {...}, report_sha256: "<hex>" }`
**And** в `audit_outbox` появляется event `iam.compliance.report_completed`

#### Сценарий 7b-02: GenerateAccessReport — report content correctness

**ID**: `7b-02`

**Given** условия `7b-01`, отчёт `cmr_xxx` в статусе COMPLETED

**When** integration-test скачивает артефакт из S3 и парсит CSV

**Then** артефакт содержит 5 именованных секций (заголовок-строки `# SECTION: access_bindings` и т.д.):
  - `access_bindings` — 14 строк: `binding_id, subject_id, role_id, resource_type, resource_id, status, created_at, expires_at, condition_id`;
  - `jit_activations` — 6 строк: `pending_id_or_binding_id, eligibility_id, requested_by, approver_user_id, duration_seconds, decision, decided_at`;
  - `break_glass_usages` — 1 строка: `grant_id, subject_user_id, incident_id, requested_by, approved_by_a, approved_by_b, status, requested_at, expires_at`;
  - `access_review_outcomes` — 9 строк: `review_id, item_id, binding_id, reviewer_id, decision, decided_at`;
  - `gdpr_erasure_requests` — 2 строки: `request_id, requested_for, requested_by, status, requested_at, cool_off_until`.
**And** в отчёте отсутствуют инфра-чувствительные поля (placement / underlay / SID-схема — раздел «Инфра-чувствительные данные» workspace `CLAUDE.md`)
**And** SHA-256 скачанного файла == `cmr_xxx.report_sha256`
**And** manifest-signature валидируется публичным ключом `compliance-signer-v1`

#### Сценарий 7b-03: GenerateAccessReport — PDF format

**ID**: `7b-03`

**Given** условия `7b-01`, caller acr=3

**When** caller передаёт `format = "PDF"`

**Then** response = `Operation { done: false }`
**And** worker формирует PDF-артефакт (те же 5 секций, табличный layout); `s3_uri` оканчивается `.pdf`
**And** `report_sha256` соответствует PDF-байтам; manifest подписан
**And** `Operation.response.format = PDF`

#### Сценарий 7b-04: GenerateAccessReport — project scope

**ID**: `7b-04`

**Given** Project `prj_beta` принадлежит Account `acc_alpha`, caller acr=3 с permission `iam.complianceReports.create` на `project:prj_beta`

**When** caller вызывает `GenerateAccessReport` с `scope_type="project"`, `scope_id="prj_beta"`

**Then** отчёт агрегирует только bindings/activations/reviews **в пределах** `prj_beta` (bindings других проектов account'а — НЕ включены)
**And** `s3_uri` = `s3://kacho-compliance-reports/project/prj_beta/2026/cmr_yyy.csv`
**And** status COMPLETED

#### Сценарий 7b-05: GenerateAccessReport — invalid scope_type

**ID**: `7b-05`

**Given** caller acr=3

**When** caller передаёт `scope_type = "folder"` (не из enum `{account,project,organization}`)

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "Illegal argument scope_type: must be one of [account, project, organization]" }`
**And** нет row в `compliance_reports`
**And** нет audit-event `report_requested`

#### Сценарий 7b-06: GenerateAccessReport — scope_id not found

**ID**: `7b-06`

**Given** caller acr=3, `scope_type="account"`, `scope_id="acc_does_not_exist"`

**When** caller вызывает `GenerateAccessReport`

**Then** response = HTTP 404 `NOT_FOUND`, body `{ message: "Account acc_does_not_exist not found" }`
**And** нет row в `compliance_reports`

#### Сценарий 7b-07: GenerateAccessReport — caller lacks permission

**ID**: `7b-07`

**Given** `usr_eve` имеет acr=3, но **нет** FGA-permission `iam.complianceReports.create` на `account:acc_alpha`

**When** `usr_eve` вызывает `GenerateAccessReport` на `acc_alpha`

**Then** response = HTTP 403 `PERMISSION_DENIED`, body `{ message: "permission denied: iam.complianceReports.create on account:acc_alpha" }`
**And** нет row в `compliance_reports`
**And** в `audit_outbox` event `iam.compliance.report_denied` (outcome=failure, reason=permission_denied)

#### Сценарий 7b-08: GenerateAccessReport — без step-up returns Unauthenticated

**ID**: `7b-08`

**Given** `usr_auditor` имеет only acr=2 token (нет re-Passkey)

**When** `usr_auditor` вызывает `GenerateAccessReport`

**Then** response = HTTP 401 `UNAUTHENTICATED`, body `{ code: 16, message: "step-up required", details: [{ "@type": "type.googleapis.com/google.rpc.ErrorInfo", reason: "STEP_UP_REQUIRED", metadata: { required_acr: "3", current_acr: "2" } }] }`
**And** нет row в `compliance_reports`

#### Сценарий 7b-09: GenerateAccessReport — range_end before range_start

**ID**: `7b-09`

**Given** caller acr=3

**When** caller передаёт `range_start = "2026-04-01T00:00:00Z"`, `range_end = "2026-01-01T00:00:00Z"`

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "Illegal argument range: range_end must be after range_start" }`
**And** нет row (DB CHECK `range_end > range_start` — defense-in-depth, но service отбивает раньше)

#### Сценарий 7b-10: GenerateAccessReport — empty scope (no governance data)

**ID**: `7b-10`

**Given** Account `acc_empty` существует, имеет 0 access_bindings, 0 JIT/Break-glass/Review/GDPR событий за период
**And** caller acr=3 с permission

**When** caller вызывает `GenerateAccessReport` на `acc_empty`

**Then** Operation **успешно** завершается `done=true`, `status=COMPLETED` (НЕ ошибка — пустой отчёт валиден)
**And** артефакт содержит 5 секций, каждая с заголовком и **0 data-строк**
**And** `row_counts = {access_bindings:0, jit_activations:0, break_glass_usages:0, access_review_outcomes:0, gdpr_erasure_requests:0}`
**And** `report_sha256` и manifest присутствуют (пустой отчёт всё равно подписан)

#### Сценарий 7b-11: GenerateAccessReport — time-range boundary (inclusive start, exclusive end)

**ID**: `7b-11`

**Given** Account `acc_alpha`, JIT-activation A с `decided_at = 2026-01-01T00:00:00.000Z` (ровно `range_start`), activation B с `decided_at = 2026-04-01T00:00:00.000Z` (ровно `range_end`)

**When** caller вызывает `GenerateAccessReport` с `range=[2026-01-01T00:00:00Z, 2026-04-01T00:00:00Z)`

**Then** activation A **включена** в отчёт (`>= range_start`)
**And** activation B **исключена** (`< range_end` — end exclusive)
**And** граничная семантика `[start, end)` явно документирована в proto-комментарии и в CSV-header (`# RANGE: [start, end)`)

#### Сценарий 7b-12: GenerateAccessReport — S3 unavailable → FAILED, not stuck

**ID**: `7b-12`

**Given** caller acr=3, отчёт начат, worker сформировал артефакт в памяти
**And** S3 endpoint возвращает 503 на все retry-попытки (3 retries + exp backoff)

**When** worker пытается upload

**Then** worker CAS UPDATE `compliance_reports.status='FAILED'`, `failure_reason="s3 upload failed after 3 retries: ServiceUnavailable"`
**And** `Operation op_xxx` finaliz'ится `done=true`, `result.error = { code: UNAVAILABLE, message: "report artifact upload failed" }`
**And** в `audit_outbox` event `iam.compliance.report_failed`
**And** Operation **не** остаётся вечно `done=false` (no stuck-state)
**And** клиент может повторно вызвать `GenerateAccessReport` (новый `cmr_` row — failed row не блокирует partial UNIQUE, т.к. UNIQUE только на in-flight; см. `7b-14`)

#### Сценарий 7b-13: GenerateAccessReport — large scope pagination (streaming aggregation)

**ID**: `7b-13`

**Given** Account `acc_huge` с 25 000 активными access_bindings и 8 000 JIT activations за период

**When** caller вызывает `GenerateAccessReport`

**Then** worker агрегирует секции **постранично** (`LIMIT/OFFSET` или keyset-pagination, batch 1000 строк) — не загружает все 33k+ строк в память разом
**And** worker стримит CSV-строки в S3 multipart upload (не буферизует весь файл в RAM)
**And** Operation eventually `done=true`, `status=COMPLETED`, `row_counts.access_bindings=25000`
**And** integration-test замеряет: peak RSS worker'а остаётся ограниченным (не растёт линейно с числом строк) — assert через bounded-memory проверку

#### Сценарий 7b-14: GenerateAccessReport — concurrent duplicate request for same scope+range

**ID**: `7b-14`

**Given** Account `acc_alpha`, нет in-flight отчёта для `(acc_alpha, range_X)`

**When** два concurrent `GenerateAccessReport` с идентичными `(scope_type, scope_id, range_start, range_end)` запускаются одновременно

**Then** оба запроса допустимы — отчёт идемпотентен по содержанию, но **не** дедуплицируется (audit-отчёты могут запрашиваться повторно намеренно): создаются 2 `compliance_reports` rows с разными `cmr_` id, оба доходят до COMPLETED
**And** integration-test (testcontainers) подтверждает: 2 row, 2 distinct S3 objects, нет deadlock / нет partial-write corruption
**And** *(дизайн-решение явное)* — повторная генерация одного и того же scope+range **разрешена** by-design (auditor может перезапросить); дедупликация НЕ требуется

#### Сценарий 7b-15: GetReportDownloadUrl — presigned URL issued

**ID**: `7b-15`

**Given** отчёт `cmr_xxx` COMPLETED, caller acr=3 с permission `iam.complianceReports.get` на scope

**When** caller вызывает `ComplianceReportService/GetReportDownloadUrl` с `report_id=cmr_xxx`

**Then** response = `ReportDownloadUrlResponse { download_url: "https://...", manifest_url: "https://...", expires_at: now+900s }`
**And** `download_url` — S3 presigned GET, TTL 15 минут
**And** в `audit_outbox` event `iam.compliance.report_downloaded` (actor, target=cmr_xxx)

#### Сценарий 7b-16: GetReportDownloadUrl — report not COMPLETED

**ID**: `7b-16`

**Given** отчёт `cmr_yyy` в статусе `RUNNING`

**When** caller вызывает `GetReportDownloadUrl` с `report_id=cmr_yyy`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "compliance report is not COMPLETED (current status: RUNNING)" }`
**And** download_url не выдан

#### Сценарий 7b-17: GetComplianceReport / ListComplianceReports

**ID**: `7b-17`

**Given** Account `acc_alpha` имеет 3 отчёта (2 COMPLETED, 1 FAILED), caller acr=2 с permission `iam.complianceReports.list`

**When** caller вызывает `ListComplianceReports` с `parent_scope="account/acc_alpha"`, опц. `filter="status=COMPLETED"`, `page_size=10`

**Then** response = `ListComplianceReportsResponse { reports: [2 COMPLETED rows], next_page_token: "" }`
**And** `GetComplianceReport(cmr_xxx)` возвращает полную `ComplianceReport` (sync, acr=2 достаточно)
**And** `GetComplianceReport("cmr_nonexistent")` → HTTP 404 `NOT_FOUND` `{ message: "ComplianceReport cmr_nonexistent not found" }`

### 3.2 Фича 2 — `ApproveJITActivation` / JitPending flow

#### Сценарий 7b-20: ActivateJIT с approval_required → JitPending created (closes stub)

**ID**: `7b-20`

**Given** eligibility `jeg_zzz` с `approval_required=true`, `approver_user_id=usr_lead_dana`, `user_id=usr_bob_dev`, `max_duration=3600s`
**And** `usr_bob_dev` имеет fresh acr=3 token

**When** `usr_bob_dev` calls `AccessBindingService/ActivateJIT` (`eligibility_id=jeg_zzz`, `duration_seconds=3600`, `justification="Investigating INC-456"`)

**Then** response = `Operation { id: op_jit, done: false }` HTTP 200
**And** в `access_bindings_jit_pending` появляется row `{ id: jp_xxx, eligibility_id: jeg_zzz, requested_by: usr_bob_dev, approver_user_id: usr_lead_dana, duration_seconds: 3600, operation_id: op_jit, decision: NULL, expires_at: now+24h }`
**And** **нет** row в `access_bindings` (grant ещё не материализован)
**And** Operation `op_jit` остаётся `done=false` до решения approver'а
**And** в `audit_outbox` event `iam.jit.activation_requested` (actor=usr_bob_dev, target=jp_xxx)
**And** через `corelib/notify` Slack DM отправляется `usr_lead_dana`: «Bob requested admin role for 1h. [Approve][Deny] <link>»; email — копия
**And** *(закрывает stub `phase7_jit_service.go:343`)* — handler больше НЕ возвращает `errors.New("ApproveJIT: bind to AccessBinding repo...")`

#### Сценарий 7b-21: ApproveJITActivation — happy path (grant materializes)

**ID**: `7b-21`

**Given** pending `jp_xxx` существует (`decision=NULL`), создан `7b-20`
**And** approver `usr_lead_dana` имеет fresh acr=3 token и FGA-permission на approve (`iam.jitPending.approve` на scope eligibility)

**When** `usr_lead_dana` calls `JitPendingService/ApproveJITActivation` через REST `POST /iam/v1/jitPending/jp_xxx:approve`

**Then** response = `Operation { id: op_approve, done: false }`, eventually `done=true`
**And** атомарной транзакцией: CAS `UPDATE access_bindings_jit_pending SET decision='approved', decided_by=usr_lead_dana, decided_at=now, materialized_binding_id=acb_new WHERE id=jp_xxx AND decision IS NULL RETURNING id` — 1 row
**And** в той же транзакции INSERT `access_bindings { id: acb_new, status: ACTIVE, subject_id: usr_bob_dev, role_id: <eligibility.role_id>, resource_type, resource_id, condition_id: cnd_jit_window, expires_at: now+3600s, jit_eligibility_id: jeg_zzz }`
**And** в той же транзакции INSERT `fga_outbox` (Write tuple `…#admin@user:usr_bob_dev[jit_window(activated_at=<now>, ttl_seconds=3600)]`) + `caep_outbox` (`token_claims_change` для usr_bob_dev) + `audit_outbox` (`iam.jit.activation_approved`)
**And** **original** Operation `op_jit` (от Bob's `ActivateJIT`) finaliz'ится `done=true`, `response = AccessBinding { id: acb_new, status: ACTIVE, … }`
**And** Slack thread reply «✅ Approved by Dana» + email подтверждение Bob'у

#### Сценарий 7b-22: DenyJITActivation — pending denied, no grant

**ID**: `7b-22`

**Given** pending `jp_xxx` (`decision=NULL`), approver `usr_lead_dana` acr=3

**When** `usr_lead_dana` calls `JitPendingService/DenyJITActivation` (`request_id=jp_xxx`, `reason="out of business hours"`)

**Then** CAS `UPDATE … SET decision='denied', decided_by=usr_lead_dana, decided_at=now, decision_reason='out of business hours' WHERE id=jp_xxx AND decision IS NULL RETURNING id` — 1 row
**And** **нет** row в `access_bindings`, нет `fga_outbox` Write tuple
**And** original Operation `op_jit` finaliz'ится `done=true`, `result.error = { code: PERMISSION_DENIED, message: "JIT activation denied: out of business hours" }`
**And** в `audit_outbox` event `iam.jit.activation_denied`
**And** Slack thread reply «❌ Denied by Dana» + email уведомление Bob'у

#### Сценарий 7b-23: ApproveJITActivation — approver == requester (self-approve deny)

**ID**: `7b-23`

**Given** eligibility `jeg_self` имеет `user_id=usr_bob_dev` **и** `approver_user_id=usr_bob_dev` (misconfig — один и тот же человек)
**And** `usr_bob_dev` вызвал `ActivateJIT` → создан pending `jp_self` с `requested_by=approver_user_id=usr_bob_dev`

**When** `usr_bob_dev` своим же acr=3 токеном calls `ApproveJITActivation(request_id=jp_self)`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "approver cannot approve own JIT activation request" }`
**And** проверка `decided_by != requested_by` выполняется **в service-слое до CAS** и продублирована DB CHECK `CHECK (decided_by IS NULL OR decided_by <> requested_by)` (defense-in-depth, запрет #10)
**And** `jp_self` остаётся `decision=NULL` (eventually expires через `jit_pending_expirer` job 24h — `7b-27`)
**And** audit event `iam.jit.activation_self_approve_denied`

#### Сценарий 7b-24: ApproveJITActivation — caller is not the designated approver

**ID**: `7b-24`

**Given** pending `jp_xxx` с `approver_user_id=usr_lead_dana`
**And** `usr_other_lead` (acr=3) — тоже team-lead, но НЕ designated approver этой заявки

**When** `usr_other_lead` calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** response = HTTP 403 `PERMISSION_DENIED`, body `{ message: "caller is not the designated approver for this JIT activation request" }`
**And** `jp_xxx` остаётся `decision=NULL`
**And** audit event `iam.jit.activation_approve_denied` (reason=not_designated_approver)

#### Сценарий 7b-25: ApproveJITActivation — double-approve (already decided)

**ID**: `7b-25`

**Given** pending `jp_xxx` уже `decision='approved'` (approved в `7b-21`)

**When** `usr_lead_dana` повторно calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "JIT activation request already decided (decision: approved)" }`
**And** CAS UPDATE возвращает 0 rows → `ErrFailedPrecondition`
**And** **нет** второго `access_bindings` row, нет второго `fga_outbox` Write
**And** идемпотентность: повторный approve не плодит дубль grant'а

#### Сценарий 7b-26: ApproveJITActivation — concurrent dual approve (DB-level race)

**ID**: `7b-26`

**Given** pending `jp_xxx` (`decision=NULL`)

**When** два concurrent `ApproveJITActivation(request_id=jp_xxx)` от `usr_lead_dana` запускаются одновременно (UI double-click)

**Then** ровно **одна** транзакция выигрывает CAS `WHERE id=jp_xxx AND decision IS NULL` (1 row RETURNING) → минтит AccessBinding; другая получает 0 rows → HTTP 412 `FAILED_PRECONDITION`
**And** в БД ровно **1** `access_bindings` row, ровно 1 `fga_outbox` Write tuple
**And** integration-test (testcontainers) запускает 10 concurrent goroutines → asserts exactly 1 succeeds, 9 `FAILED_PRECONDITION`
**And** partial UNIQUE `(eligibility_id) WHERE decision IS NULL` + partial UNIQUE на `access_bindings (user_id, role_id, resource_type, resource_id) WHERE status='ACTIVE'` — second safety-net (никакого software check-then-act)

#### Сценарий 7b-27: JitPending — timeout expire (24h approval window)

**ID**: `7b-27`

**Given** pending `jp_xxx` создан 25h назад, `decision=NULL`, `expires_at` уже в прошлом

**When** background job `jit_pending_expirer` (60s tick) сканирует `WHERE decision IS NULL AND expires_at < now()` (`FOR UPDATE SKIP LOCKED`)

**Then** CAS `UPDATE … SET decision='timeout_expired', decided_at=now WHERE id=jp_xxx AND decision IS NULL RETURNING id` — 1 row (`decided_by` остаётся NULL — нет человека-решателя)
**And** original Operation `op_jit` finaliz'ится `done=true`, `result.error = { code: DEADLINE_EXCEEDED, message: "JIT activation approval timed out" }`
**And** **нет** `access_bindings` row
**And** в `audit_outbox` event `iam.jit.activation_timeout`
**And** Slack/email уведомление requester'у «request timed out»

#### Сценарий 7b-28: ApproveJITActivation — after timeout (too late)

**ID**: `7b-28`

**Given** pending `jp_xxx` уже `decision='timeout_expired'` (expired в `7b-27`)

**When** `usr_lead_dana` (опоздал) calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "JIT activation request already decided (decision: timeout_expired)" }`
**And** CAS возвращает 0 rows → нет grant
**And** approver видит подсказку «request expired — ask the user to re-activate»

#### Сценарий 7b-29: ApproveJITActivation — without step-up returns Unauthenticated

**ID**: `7b-29`

**Given** pending `jp_xxx`, approver `usr_lead_dana` имеет only acr=2 token

**When** `usr_lead_dana` calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** response = HTTP 401 `UNAUTHENTICATED`, body `{ code: 16, message: "step-up required", details: [{ reason: "STEP_UP_REQUIRED", metadata: { required_acr: "3", current_acr: "2" } }] }`
**And** `jp_xxx` остаётся `decision=NULL`

#### Сценарий 7b-30: ApproveJITActivation — eligibility disabled between request and approval

**ID**: `7b-30`

**Given** pending `jp_xxx` создан, затем admin выставил `jeg_zzz.enabled=false` (eligibility отключена пока заявка ждала)

**When** `usr_lead_dana` (acr=3) calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "JIT eligibility is disabled" }`
**And** **нет** `access_bindings` row (re-validation eligibility-state на approve-time, не только на request-time)
**And** `jp_xxx` переводится в `decision='denied'`, `decision_reason="eligibility disabled during approval window"` (CAS), original Operation finaliz'ится с error `FAILED_PRECONDITION`
**And** audit event `iam.jit.activation_denied` (reason=eligibility_disabled)

#### Сценарий 7b-31: ApproveJITActivation — duplicate ACTIVE binding appeared meanwhile

**ID**: `7b-31`

**Given** pending `jp_xxx` для scope `(usr_bob_dev, role_vpc_admin, vpc_network:net_yyy)`
**And** пока заявка ждала, `usr_bob_dev` получил ACTIVE binding на тот же scope другим путём (например, второй eligibility без approval — `7b` не запрещает)

**When** `usr_lead_dana` calls `ApproveJITActivation(request_id=jp_xxx)`

**Then** mint INSERT `access_bindings` упирается в partial UNIQUE `(user_id, role_id, resource_type, resource_id) WHERE status='ACTIVE'` → SQLSTATE `23505`
**And** service маппит `23505` → HTTP 409 `ALREADY_EXISTS`, body `{ message: "active binding already exists for this scope" }`
**And** CAS на `jit_pending` НЕ коммитится (вся транзакция rollback) → `jp_xxx` остаётся `decision=NULL`, approver может retry после того как существующий binding истечёт, либо явно deny
**And** integration-test покрывает этот race (testcontainers)

#### Сценарий 7b-32: GetJitPending / ListJitPending

**ID**: `7b-32`

**Given** approver `usr_lead_dana` имеет 4 заявки, где он designated approver (2 PENDING, 1 approved, 1 timeout_expired); caller acr=2

**When** `usr_lead_dana` calls `ListJitPending` с `filter="approver_user_id=me AND status=PENDING"`, `page_size=20`

**Then** response = `ListJitPendingResponse { pending: [2 PENDING rows], next_page_token: "" }`
**And** `GetJitPending("jp_xxx")` возвращает полный `JitPending` (sync, acr=2 OK)
**And** `GetJitPending("jp_nonexistent")` → HTTP 404 `NOT_FOUND` `{ message: "JitPending jp_nonexistent not found" }`
**And** requester `usr_bob_dev` тоже может `ListJitPending` со `filter="requested_by=me"` — видит свои заявки и их статус

#### Сценарий 7b-33: ActivateJIT with approval — duplicate pending for same eligibility

**ID**: `7b-33`

**Given** eligibility `jeg_zzz` (`approval_required=true`), уже есть PENDING `jp_xxx` для неё (создан `7b-20`)

**When** `usr_bob_dev` повторно calls `ActivateJIT(eligibility_id=jeg_zzz)`

**Then** второй INSERT в `access_bindings_jit_pending` упирается в partial UNIQUE `(eligibility_id) WHERE decision IS NULL` → SQLSTATE `23505`
**And** service маппит → HTTP 409 `ALREADY_EXISTS`, body `{ message: "pending JIT activation request already exists", details: [{ resource_id: "jp_xxx" }] }`
**And** в БД ровно 1 PENDING row для `jeg_zzz`
**And** после того как `jp_xxx` решён (approved/denied/timeout) — повторный `ActivateJIT` снова допустим (partial UNIQUE снимается, т.к. `decision` уже не NULL)

---

## 4. Traceability — связь с предшествующими acceptance / spec

| `3.7b` сценарий / артефакт | Источник в Phase 7 base / audit / compliance specs |
|---|---|
| `7b-20…7b-22` (JitPending create / approve / deny) | Phase 7 base §6.3 сценарии `7-17`, `7-18`, `7-19` — описаны, но `JitPendingService` / use-case реально не реализованы (stub `phase7_jit_service.go:343`) → `3.7b` финализирует |
| `7b-23` (self-approve deny) | Phase 7 base `7-20` (approver self-denial) — `3.7b` доводит до DB CHECK + service-проверки |
| `7b-27`, `7b-28` (timeout) | Phase 7 base `7-21` (JIT pending timeout expire) — `3.7b` определяет 24h-окно и job `jit_pending_expirer` |
| `7b-21`, `7b-31` (mint AccessBinding atomic) | Phase 7 base `7-08` / `7-16` — happy-path ActivateJIT + duplicate-ACTIVE partial UNIQUE; `3.7b` переиспользует ту же атомарность и race-protection |
| `7b-26` (concurrent approve CAS race) | запрет #10 workspace `CLAUDE.md` §«Within-service refs» — атомарный CAS + RETURNING-кардинальность; Phase 7 base `7-31` (break-glass concurrent dual-approve) — тот же паттерн |
| `7b-01…7b-04` (report sections: AccessBindings / JIT / Break-glass / Reviews / GDPR) | Phase 7 base §0 п.1-6 — источники governance-данных; `3.7b` агрегирует все 5 |
| `7b-01`, `7b-02` (HSM-signed manifest, ECDSA P-384, Merkle-style) | `sub-phase-3.9-…` §P9-D9 (HSM PKCS#11 ECDSA P-384), §2.7 (S3 bucket layout + `.manifest.signed` format) — `3.7b` переиспользует подход для `kacho-compliance-reports` bucket |
| `7b-12` (S3 fail → FAILED) | `sub-phase-3.9-…` §2.5 failure-modes (HSM/S3 unavailable → graceful degrade) — `3.7b` применяет fail-with-status, не stuck |
| `7b-02` (отчёт без инфра-полей) | workspace `CLAUDE.md` §«Инфра-чувствительные данные» — placement / underlay / SID-поля не попадают в публичный compliance-отчёт |
| Compliance report как артефакт для аудита | `sub-phase-3.12-…` §2.2 — SOC 2 Type II / ISO 27001:2022 Annex A / GDPR Art. 17/32/33 control mappings; access-report — evidence для control «periodic access review & attestation» |
| `7b-08`, `7b-29` (step-up acr=3) | Phase 7 base §1 запрет #6-row — step-up acr=3 на ActivateJIT и privileged-mutations; `sub-phase-3.2-…` step-up flow |

---

## 5. Definition of Done (`3.7b`)

### Functional

- [ ] **`ComplianceReportService`** — `GenerateAccessReport` (async, Operation), `GetComplianceReport`, `ListComplianceReports`, `GetReportDownloadUrl` реализованы; public mux; step-up acr=3 на `GenerateAccessReport` и `GetReportDownloadUrl`.
- [ ] **Report aggregation** — worker собирает 5 секций (access_bindings, jit_activations, break_glass_usages, access_review_outcomes, gdpr_erasure_requests) за `[range_start, range_end)`; постраничная агрегация + streaming S3 multipart upload для больших scope.
- [ ] **Report artifact** — CSV и PDF форматы; артефакт + `.manifest.signed` (HSM ECDSA P-384, kid `compliance-signer-v1`, SHA-256) в bucket `kacho-compliance-reports`; layout `s3://kacho-compliance-reports/<scope_type>/<scope_id>/<yyyy>/<report_id>.<ext>`.
- [ ] **Report status machine** — `PENDING → RUNNING → COMPLETED/FAILED` через атомарный CAS UPDATE; S3-failure → `FAILED` + `failure_reason`, Operation finaliz'ится с error (no stuck-state).
- [ ] **Empty scope** — пустой отчёт валиден (`row_counts` всё нулевые, всё равно подписан).
- [ ] **`GetReportDownloadUrl`** — S3 presigned GET URL, TTL 15 min; `FAILED_PRECONDITION` если report не COMPLETED.
- [ ] **`ApproveJITActivation` / `DenyJITActivation`** — public RPC реализованы (закрывают stub `phase7_jit_service.go:343`); async Operation; step-up acr=3.
- [ ] **JitPending aggregate** — `ActivateJIT` при `eligibility.approval_required=true` создаёт `access_bindings_jit_pending` row вместо немедленного mint; Operation остаётся `done=false` до решения.
- [ ] **JitPending approve** — атомарная транзакция: CAS UPDATE pending → INSERT `access_bindings` (ACTIVE, jit_window) → `fga_outbox` + `caep_outbox` + `audit_outbox`; original Operation finaliz'ится с AccessBinding.
- [ ] **JitPending deny / timeout** — deny → Operation finaliz'ится `PERMISSION_DENIED`; `jit_pending_expirer` job (60s) → 24h-таймаут → `DEADLINE_EXCEEDED`.
- [ ] **Self-approve / not-designated-approver** — service-проверка + DB CHECK `decided_by <> requested_by`; non-designated approver → `PERMISSION_DENIED`.
- [ ] **`GetJitPending` / `ListJitPending`** — sync read; filter по `approver_user_id` / `requested_by` / `status`.

### Tests / CI (per запрет #11)

- [ ] **kacho-proto** — `buf lint` зелёный, `buf breaking` зелёный (additive only — `ComplianceReportService`, `JitPendingService` — новые сервисы; `ActivateJIT` сигнатура не меняется).
- [ ] **kacho-iam integration tests** (testcontainers Postgres):
  - compliance report happy-path (account + project scope) — агрегация 5 секций, row_counts корректны;
  - report для пустого scope — 0-row секции, отчёт COMPLETED;
  - report time-range boundary `[start, end)` — inclusive start / exclusive end;
  - report large-scope pagination — 25k+ bindings, bounded-memory assert;
  - report S3-unavailable → `FAILED` + Operation error (no stuck);
  - JitPending approve happy-path — atomic mint + outbox rows;
  - JitPending **concurrent dual-approve race** (10 goroutines → exactly 1 succeeds, 9 `FAILED_PRECONDITION`);
  - JitPending double-approve / approve-after-timeout / approve-after-deny → `FAILED_PRECONDITION`;
  - JitPending self-approve → `FAILED_PRECONDITION` (DB CHECK enforced);
  - JitPending duplicate-pending per eligibility → `ALREADY_EXISTS` (partial UNIQUE `23505`);
  - JitPending approve when eligibility disabled meanwhile → `FAILED_PRECONDITION`;
  - JitPending approve when duplicate ACTIVE binding appeared → `ALREADY_EXISTS` (`23505`), full rollback.
- [ ] **S3 backend в тестах** — recorded backend или MinIO testcontainer (no real S3 calls в CI); HSM-sign — software-stub key для тестов, prod — PKCS#11.
- [ ] **Newman cases** (`tests/newman/cases/iam_compliance_report_*.py`, `iam_jit_pending_*.py` → `gen.py`, run в `make e2e-test`):
  - compliance: generate happy (CSV) / generate invalid scope_type `INVALID_ARGUMENT` / scope not-found `NOT_FOUND` / no permission `PERMISSION_DENIED` / no step-up `UNAUTHENTICATED` / get download URL / get not-completed `FAILED_PRECONDITION`;
  - jit-pending: activate-with-approval creates pending / approve happy / deny / double-approve `FAILED_PRECONDITION` / self-approve `FAILED_PRECONDITION` / non-designated approver `PERMISSION_DENIED` / duplicate pending `ALREADY_EXISTS` / no step-up `UNAUTHENTICATED`.
- [ ] **CI** — `make test-integration && make e2e-test` зелёный.

### Operational

- [ ] **Background jobs** registered в kacho-iam composition root: `compliance_report_worker` (подхватывает `PENDING` reports), `jit_pending_expirer` (60s tick, 24h-таймаут).
- [ ] **Job idempotency** — multi-replica safe (`SELECT FOR UPDATE SKIP LOCKED` + advisory lock per job-name); compliance-worker S3-upload идемпотентен (object key = `report_id`, deterministic).
- [ ] **S3 bucket** `kacho-compliance-reports` provisioned в kacho-deploy (versioning ON, object-lock опц., lifecycle — отчёты хранятся ≥ 7 лет per compliance retention).
- [ ] **HSM key** `compliance-signer-v1` (ECDSA P-384) provisioned (или software-key с явной пометкой для non-prod).
- [ ] **Runbook** `docs/runbooks/compliance-report.md` — как сгенерировать отчёт, как верифицировать manifest-signature, retention policy.

### Security / Compliance

- [ ] **Step-up acr=3 enforced** на `GenerateAccessReport`, `GetReportDownloadUrl`, `ApproveJITActivation`, `DenyJITActivation`; sync read (`Get*`/`List*`) — acr=2 OK.
- [ ] **FGA-permission gate** — `GenerateAccessReport` требует `iam.complianceReports.create` на scope; `ApproveJITActivation` требует caller == designated `approver_user_id`.
- [ ] **DB CHECK** — `compliance_reports` (range / completed-has-uri / failed-has-reason); `access_bindings_jit_pending` (`decided_by <> requested_by`, denied-has-reason, approved-has-binding, PENDING ⟺ no-decision).
- [ ] **No infra-sensitive data в отчёте** — placement / underlay / SID-поля отсутствуют (workspace `CLAUDE.md` §«Инфра-чувствительные данные»).
- [ ] **Report artifact integrity** — SHA-256 + HSM-signed manifest; presigned URL TTL ≤ 15 min.
- [ ] **No secrets in code / Helm** — S3 credentials, HSM PKCS#11 PIN — через Sealed Secrets / External Secrets.
- [ ] **Audit** — `iam.compliance.report_{requested,completed,failed,downloaded,denied}`, `iam.jit.activation_{requested,approved,denied,timeout,self_approve_denied,approve_denied}` rows в `audit_outbox`; `audit_retention_until` ≥ 7 лет.

### Code Quality (no tech debt)

- [ ] Clean Architecture: `domain/` (self-validating `ComplianceReport`, `JitPending` types), `service/` (use-cases + ports `ComplianceReportRepo` / `JitPendingRepo` / `ReportArtifactStore` / `ReportSigner`), `repo/` (pgx adapter), `clients/` (S3 + HSM adapter), `handler/` (тонкий transport).
- [ ] sqlc + handwritten pgx; S3 — `aws-sdk-go-v2`; no ORM (запрет #3).
- [ ] Миграция `0022_kac127_phase7b_compliance_jitpending.sql` — **новая** (не редактирует `0011..0021`, запрет #5).
- [ ] No "yandex" mentions (запрет #2).
- [ ] Stub `phase7_jit_service.go:343` (`errors.New("ApproveJIT: bind to AccessBinding repo...")`) **удалён** — заменён рабочим use-case.

### Documentation

- [ ] **This document** approved by `acceptance-reviewer`.
- [ ] **YouTrack subtask(s)** под `3.7b` созданы, привязаны к KAC-123 эпику + к этому acceptance, добавлены в текущий спринт.
- [ ] **Vault updates**:
  - `obsidian/kacho/resources/iam-compliance-report.md` (новый, 1-3KB);
  - `obsidian/kacho/resources/iam-jit-pending.md` (новый, 1-3KB);
  - `obsidian/kacho/rpc/iam-compliance-report-service.md` (новый — method table, REST mapping);
  - `obsidian/kacho/rpc/iam-jit-pending-service.md` (новый);
  - `obsidian/kacho/edges/iam-to-s3-compliance-reports.md` (новый — S3 bucket, HSM-sign);
  - `obsidian/kacho/KAC/KAC-127.md` (`3.7b` закрывает 2 known-gaps — обновить статус gaps + PR-list).
- [ ] **API reference** в `kacho-proto` proto-файлах — godoc на оба сервиса, явно документирована граница диапазона `[range_start, range_end)`.

### Cross-Repo PR Chain (топологический порядок merge)

```
1. kacho-proto      ← ComplianceReportService + JitPendingService protobufs (additive)
   PR #1              Tests: buf lint + buf breaking + golden generated Go stubs
                      Reviewer: proto-api-reviewer

2. kacho-iam        ← domain + service + repo + clients (S3/HSM) + jobs + handlers
   PR #2              + migration 0022 (compliance_reports, access_bindings_jit_pending, indexes)
                      + удаление stub phase7_jit_service.go:343
                      Tests: integration (testcontainers + MinIO) + race-tests + newman
                      Reviewers: rpc-implementer, db-architect-reviewer, go-style-reviewer
                      Merge → after PR #1

3. kacho-api-gateway ← mux: ComplianceReportService + JitPendingService на public mux
   PR #3              Tests: api-gateway integration (step-up gate, REST mapping)
                      Reviewer: api-gateway-registrar
                      Merge → after PR #2

4. kacho-deploy     ← S3 bucket kacho-compliance-reports + HSM compliance-signer-v1 +
   PR #4              CronJob templates (compliance_report_worker, jit_pending_expirer)
                      Tests: helm template golden
                      Merge → after PR #3

5. kacho-workspace  ← vault entries (§ DoD «Vault updates») + KAC-127.md gap-closure
   PR #5
```

---

## 6. Out of scope `3.7b` (явно — НЕ расширять)

- **Break-glass workflow, Access Reviews quarterly, GDPR erasure pipeline, `corelib/notify`** — реализованы в Phase 7 base (`sub-phase-3.7-…`). `3.7b` лишь **читает** их данные (для compliance-отчёта) и **переиспользует** `corelib/notify` (для JitPending Slack/email). Никаких изменений в их схеме/поведении.
- **CAEP push drainer / webhook delivery** — Phase 8. `3.7b` кладёт `caep_outbox` rows при mint AccessBinding, но не consume'ит их.
- **Audit pipeline (Kafka + ClickHouse + S3 cold + SIEM)** — Phase 9. `3.7b` пишет `audit_outbox` rows; drainer — Phase 9. Compliance-report bucket `kacho-compliance-reports` — **отдельный** от audit-cold `kacho-audit-cold` bucket.
- **Compliance control-mapping документы** (`docs/security/soc2-control-mapping.md` и т.п.) — Phase 12. `3.7b` производит **технический артефакт** (access-report), не сам control-mapping.
- **Scheduled / recurring report generation** (авто-генерация отчёта каждый квартал) — НЕ в scope; `3.7b` — только on-demand `GenerateAccessReport`. Recurring — возможный future enhancement (GitHub issue, не `3.7b`).
- **Report диффы / трендовый анализ между периодами** — НЕ в scope.
- **Multi-person approval для JIT** — by-design 1 approver достаточно (в отличие от break-glass 2-person). Расширение до N-approver — НЕ `3.7b`.

---

> **Self-review** (выполнен автором перед передачей `acceptance-reviewer`):
> - *Placeholders*: нет `TBD` / `TODO` / `???` — все поля, payload'ы, коды конкретны.
> - *Contradictions*: `7b-14` (повторная генерация разрешена) vs `7b-33` (duplicate pending запрещён) — НЕ противоречие: разные сущности (отчёт идемпотентен по содержанию и может перезапрашиваться; pending — in-flight заявка, дубль не нужен). Явно отмечено в `7b-14`.
> - *Ambiguity*: граница диапазона `[range_start, range_end)` — явно зафиксирована (`7b-11`), inclusive start / exclusive end; 24h JitPending timeout — явно (`7b-27`); presigned URL TTL 15 min — явно.
> - *Scope*: ровно 2 фичи (`ComplianceReportService.GenerateAccessReport`, `ApproveJITActivation`/JitPending); §6 фиксирует out-of-scope. Break-glass / Access Reviews / GDPR / CAEP / audit-pipeline / compliance-mappings НЕ трогаются.
> - *Negative coverage*: invalid scope (`7b-05`), unauthorized requester (`7b-07`/`7b-24`), approver==requester (`7b-23`), пустой scope (`7b-10`), double-approve (`7b-25`/`7b-28`), S3 unavailable (`7b-12`), concurrent race (`7b-14`/`7b-26`), large pagination (`7b-13`) — все требуемые покрыты.
> - *Traceability*: §4 связывает каждый блок с Phase 7 base / 3.9 / 3.12.
> - *DoD*: §5 включает integration testcontainers + newman per запрет #11.
