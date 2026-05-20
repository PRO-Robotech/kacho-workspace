# Sub-phase 3.9 — IAM Audit Pipeline (Kafka + ClickHouse + S3+Glacier + HSM + Merkle + SIEM) (KAC-127 / Phase 9) — Acceptance

> **Статус:** DRAFT
> **Дата:** 2026-05-19
> **Эпик:** [EPIC] KAC-127 IAM production-ready next-gen
> **Phase:** 9 of 12 (см. `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md`)
> **Дизайн:** `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §9 (Audit pipeline full production) + D-18 + §13.5 observability
> **Plan tasks:** 9.1–9.12
> **Депенденси:** Phase 1 (`audit_outbox` + `audit_signing_batches` миграция `0013_kac127_audit_caep_pipeline.sql` уже применена и зелёная). Phase 8 (`caep_outbox`) — параллельная фаза, делит drainer-паттерн.
> **Прод-edition.** User feedback round 2: strict backward-compat не требуется — выкатываем чистую production-форму с самого начала.
> **Acceptance reviewer gate:** запрещено стартовать кодирование Phase 9 до APPROVED этого документа (§«Запреты» #1 workspace CLAUDE.md).

---

## 0. Преамбула — место этой sub-итерации в эпике

KAC-127 строит production-grade IAM (Account/Project + AuthN + AuthZ + WIF + SCIM/SAML + JIT/Break-glass + Audit/CAEP) в 12 фаз. Phase 9 — **last-mile compliance-критичная фаза** для SOC 2 Type II / ISO 27001:2022 / GDPR / FedRAMP Moderate: превращает уже-собранные в `audit_outbox` (Phase 1 + Phase 3-7 mutation handlers) события в полноценный audit pipeline с:

1. **Realtime streaming** в Kafka KRaft (3 brokers, ack=all, idempotent producer) для downstream consumer'ов.
2. **Hot OLAP-аналитика** в ClickHouse cluster (2 shards × 2 replicas, Replicated MergeTree, 90d retention) — для UI «Activity» / forensic queries / detection-rule input.
3. **Cold long-term** на S3 + Glacier (7-10y retention) с HSM-signed batch manifests (PKCS#11) и Merkle-chain (`previous_batch_hash → batch_hash`) для tamper-evidence.
4. **Independent verifier service** — daily cron walks Merkle chain, verifies HSM signatures, alerts on integrity violation.
5. **SIEM forwarders** — per-tenant subscription, Datadog HEC / Splunk HEC / Elastic webhook, signed bearer auth.
6. **Detection rules library** — 8 production-grade rules (brute force, impossible travel, mass deletion, out-of-hours admin, privilege escalation, audit signature failure, break-glass usage, FGA tuple drift).

После Phase 9 audit-обязательства SOC 2 CC7.2 (anomaly detection) + ISO 27001 A.12 (Operational) + GDPR Art. 32 (Security) + FedRAMP AU-2/AU-9 (audit & log protection) удовлетворены. Acceptance этого документа закрывает task 9.1 plan'а; задачи 9.2–9.12 не стартуют до APPROVED.

**Что НЕ входит в Phase 9** (out of scope — следующие фазы):

| Что | Где |
|---|---|
| Phase 10 — SPIFFE mTLS to Kafka cluster + ClickHouse + HSM | `sub-phase-3.10-iam-spiffe-mesh-acceptance.md` |
| Phase 11 — Multi-region MirrorMaker (cross-region audit replication) | `sub-phase-3.11-iam-multi-region-acceptance.md` |
| Phase 12 — CAEP push pipeline production (включая Federated CAEP) | `sub-phase-3.12-iam-caep-production-acceptance.md` |
| Phase 8 — каркас audit_drainer / caep_drainer (in-process, без Kafka) | `sub-phase-3.8-iam-caep-pipeline-acceptance.md` — параллельная |

---

## 1. Связь с регламентом и запретами (нормативно)

| Запрет / правило | Применение в Phase 9 |
|---|---|
| **Запрет #1** — Нет кодирования до APPROVED acceptance-документа | Этот документ — gate; задачи 9.2–9.12 заблокированы до APPROVED |
| **Запрет #2** — НЕ упоминать «yandex» в коде/именах/env | Соблюдаем; Kafka/ClickHouse/S3-ресурсы именуются `kacho-audit-*` |
| **Запрет #3** — НЕ ORM (только sqlc + handwritten pgx) | `audit_outbox` reader / `audit_signing_batches` writer — handwritten pgx с `FOR UPDATE SKIP LOCKED`; никаких gorm/ent |
| **Запрет #4** — НЕ cross-service cascade delete | Audit log — append-only; cascade не применим. GDPR erasure pseudonymize PII в Kafka producer side, но audit row сохраняется 7y (compliance > erasure per GDPR Art. 17(3)(b)) — см. §6.15 |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 1 `0013` уже применена; Phase 9 пишет **новые** миграции (`0021..0023`) если нужны admin-RPC таблицы (SIEM subscribers, verifier state) |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | Admin RPC для SIEM subscribers (`InternalSIEMService.{Create,List,Update,Delete,TestDelivery,DisableOnFailure}`) — только на internal-port 9091 + REST mux api-gateway (cluster-internal listener); никогда на `api.kacho.local:443` |
| **Запрет #7** — НЕ broker, пока in-process справляется | **ЯВНО РАЗРЕШЕНО для Phase 9** по design D-18: Kafka audit-topic — обязательная часть production audit pipeline (3 broker'а KRaft, ack=all, idempotent producer). In-process LISTEN/NOTIFY уже доказал свою недостаточность для downstream-fan-out (ClickHouse + S3 + SIEM одновременно) → Kafka — единственный sustainable broker. Этот запрет **снят** для audit-topic решением D-18 |
| **Запрет #8** — DB-per-service | Сохраняется: ClickHouse — **отдельная** OLAP-БД (вне Postgres сервисов), не «единая БД». Postgres `audit_outbox` живёт только в `kacho_iam`. Kafka — не БД (event streaming) |
| **Запрет #9** — Все мутации возвращают Operation (async) | Admin RPC SIEM subscribers — это IAM admin-операции (CRUD); в Phase 9 они возвращают **sync** объект (как Account/Project) — это admin-resource, не tenant resource; consistent с конвенцией Phase 1 cluster-admin RPC |
| **Запрет #10** — Within-service refs — DB-уровень обязателен | `audit_signing_batches.previous_batch_hash` ссылается на `batch_hash` предыдущей row → FK `REFERENCES audit_signing_batches(batch_hash)` + DB-level `CHECK (batch_seq = lag(batch_seq) over (...) + 1)` (либо materialized). SIEM subscriber CRUD — atomic CAS на failure_count при disable-on-failure |
| **Запрет #11** — Не мёрджить новый RPC без тестов в том же PR | Каждый из задач 9.2–9.9 PR обязан содержать integration + newman; Definition of Done (§7) перечисляет коммитментный матрикс |

**Карта владельцев доменов** (regulation §«Кросс-доменные ссылки на ресурсы»):
- Audit-event ownership = **`kacho-iam`** (origination); Kafka producer пишет в общий topic. ClickHouse / S3 / SIEM — downstream consumers.
- `account_id` / `project_id` в audit-event — denormalised mirror (audit pipeline никогда не валидирует против `kacho-iam` post-mortem — даже после удаления Account audit row сохраняется 7y по compliance).
- **SIEM subscribers** — новый ресурс в `kacho-iam` (table `siem_subscribers`); admin-only через `InternalSIEMService` (запрет #6).

---

## 2. Глоссарий / доменная модель Phase 9 (нормативно)

### 2.1 Сущности, использующиеся в Phase 9 (от Phase 1, read-only входы)

| Сущность | Таблица | Создана в | Роль в Phase 9 |
|---|---|---|---|
| Audit event (outbox row) | `audit_outbox` (Postgres `kacho_iam`) | Phase 1 миграция `0013` | Источник истины: source of all audit events. Drainer читает + помечает |
| Audit signing batch | `audit_signing_batches` | Phase 1 миграция `0013` | Каждая S3-выкладка добавляет row: `(batch_id, batch_seq, batch_hash, previous_batch_hash, signature, signed_at, s3_uri)`. Merkle chain |

**Колонки `audit_outbox`** (нормативно, от Phase 1):
- `id` TEXT PRIMARY KEY (ULID, prefix `evt_`)
- `event_type` TEXT NOT NULL (CADF: `iam.access_binding.created`, ...)
- `tenant_account_id` TEXT NULL (denorm)
- `tenant_org_id` TEXT NULL (denorm)
- `event_payload` JSONB NOT NULL (CADF event body, §2.3 ниже)
- `status` TEXT CHECK (`status IN ('pending','in_flight','delivered','failed_terminal')`) DEFAULT `'pending'`
- `attempts` INT DEFAULT 0
- `next_attempt_at` TIMESTAMPTZ DEFAULT `now()`
- `created_at` TIMESTAMPTZ DEFAULT `now()`
- `delivered_at` TIMESTAMPTZ NULL
- Trigger `audit_outbox_notify_trigger` AFTER INSERT → `pg_notify('audit_event', row.id)` (Phase 1 §6.11.2)

**Колонки `audit_signing_batches`** (нормативно, от Phase 1):
- `batch_id` TEXT PRIMARY KEY (`bat_<ulid>`)
- `batch_seq` BIGINT NOT NULL UNIQUE (monotonic, `nextval('audit_batch_seq')`)
- `batch_hash` TEXT NOT NULL UNIQUE (`sha256:<hex>`)
- `previous_batch_hash` TEXT NULL REFERENCES `audit_signing_batches(batch_hash)` ON DELETE RESTRICT (NULL только для batch_seq=1)
- `merkle_root` TEXT NOT NULL (hex, root over event ids in batch)
- `event_count` INT NOT NULL CHECK (`event_count > 0`)
- `event_id_min` TEXT NOT NULL (oldest event in batch)
- `event_id_max` TEXT NOT NULL (newest event in batch)
- `window_started_at` TIMESTAMPTZ NOT NULL
- `window_ended_at` TIMESTAMPTZ NOT NULL CHECK (`window_ended_at > window_started_at`)
- `signature` BYTEA NOT NULL (PKCS#11 ECDSA P-384 signature over batch_hash)
- `signing_key_id` TEXT NOT NULL (HSM key kid; FK to `hsm_keys` если присутствует)
- `s3_uri` TEXT NOT NULL UNIQUE (`s3://kacho-audit-cold/<tenant_or_shared>/<yyyy>/<mm>/<dd>/<hh>/<batch_id>.jsonl.gz`)
- `s3_manifest_uri` TEXT NOT NULL UNIQUE (`<s3_uri>.manifest.signed`)
- `verifier_status` TEXT CHECK (`verifier_status IN ('not_verified','verified_ok','verified_broken','verifier_alerted')`) DEFAULT `'not_verified'`
- `verified_at` TIMESTAMPTZ NULL
- `verifier_alert_id` TEXT NULL (PagerDuty incident_key if alerted)
- `signed_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`
- `created_at` TIMESTAMPTZ NOT NULL DEFAULT `now()`

### 2.2 Сущности, **создаваемые** в Phase 9

| Сущность | Таблица | Где | Роль |
|---|---|---|---|
| SIEM subscriber | `siem_subscribers` | `kacho_iam` (мигр. `0021`) | per-tenant SIEM webhook (Datadog/Splunk/Elastic) с signing_kid, expected_audience, event_types filter |
| Audit drainer cursor | `audit_drainer_state` | `kacho_iam` (мигр. `0022`) | one row per drainer pod (drainer_id, last_seen_event_id, last_heartbeat_at) — for recovery |
| Verifier run history | `audit_verifier_runs` | `kacho_iam` (мигр. `0023`) | (run_id, run_started_at, run_ended_at, batches_walked, anomalies_found, status) |

### 2.3 CADF event schema (нормативно, формируется service-handler'ами в Phase 3-7 и пишется в `audit_outbox.event_payload`)

```json
{
  "event_id":   "evt_01h2n4z9...",
  "timestamp":  "2026-05-19T14:23:00.123Z",
  "event_type": "iam.access_binding.created",
  "tenant":     {"organization_id":"org_x", "account_id":"acc_y"},
  "actor": {
    "type":"user", "id":"usr_alice", "email":"alice@example.com",
    "session_id":"sess_xxx", "token_jti":"jti_xxx",
    "ip":"10.0.0.5", "user_agent":"kacho-cli/0.5.0",
    "acr":"2", "amr":["webauthn"],
    "device_attestation":"attested"
  },
  "target": {
    "type":"access_binding", "id":"acb_yyy",
    "parent":{"type":"project","id":"prj_x"}
  },
  "action":  "create",
  "outcome": "success",
  "request": {"method":"POST","path":"/iam/v1/access_bindings:upsert","request_id":"req_zzz"},
  "response":{"status_code":200,"operation_id":"op_aaa"},
  "diff":{"before":null,"after":{"...":"..."}},
  "risk_signals":{"impossible_travel":false,"anomaly_score":0.02},
  "metadata":{
    "trace_id":"<otel>","service":"kacho-iam","region":"eu-central-1",
    "cluster":"prod-1","cell":"shard-3"
  }
}
```

> CADF (Cloud Auditing Data Federation, DMTF) compatible — это даёт outbound совместимость для SOC2 / ISO27001 auditors, плюс готовый mapping в Datadog Security Monitoring / Splunk Enterprise Security.

### 2.4 Resource id prefixes (новые)

| Prefix | Resource | Длина |
|---|---|---|
| `evt_` | audit event | 4 + 26-ULID |
| `bat_` | audit signing batch | 4 + 26-ULID |
| `sub_` | siem subscriber | 4 + 26-ULID |
| `vrn_` | verifier run | 4 + 26-ULID |

### 2.5 Kafka topic naming convention (нормативно)

| Topic | Partition strategy | Compression | Replication | Retention | Notes |
|---|---|---|---|---|---|
| `kacho-audit-events.shared` | hash(`tenant_account_id`) % 64 partitions | zstd | RF=3 (min.insync.replicas=2) | 7d | default для standard tenants |
| `kacho-audit-events.tenant.<account_id>` | hash(`event_id`) % 16 partitions | zstd | RF=3 (min.insync.replicas=2) | 7d | per-tenant изоляция (high-volume tenants только; opt-in admin flag) |

**Producer config** (нормативно):
- `acks=all` (durability guarantee)
- `enable.idempotence=true` (exactly-once semantics в пределах producer session)
- `compression.type=zstd`
- `max.in.flight.requests.per.connection=5` (with idempotence allows reorder-safe)
- `linger.ms=20`, `batch.size=131072` (128KiB)
- `transactional.id=audit-drainer-<pod>-<incarnation>` (idempotent + transactional повтором при retry)

### 2.6 ClickHouse schema (нормативно)

```sql
-- on cluster '2x2'
CREATE TABLE audit_events_local ON CLUSTER '2x2' (
    event_id            String,
    event_type          LowCardinality(String),
    timestamp           DateTime64(3, 'UTC'),
    tenant_account_id   String,
    tenant_org_id       String,
    actor_id            String,
    actor_type          LowCardinality(String),
    actor_ip            String,
    target_id           String,
    target_type         LowCardinality(String),
    action              LowCardinality(String),
    outcome             LowCardinality(String),
    request_id          String,
    operation_id        String,
    payload             String,                          -- full JSON for forensic
    ingested_at         DateTime64(3, 'UTC') DEFAULT now64()
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/audit_events_local', '{replica}')
PARTITION BY (tenant_account_id, toDate(timestamp))
ORDER BY (tenant_account_id, timestamp, event_id)
TTL toDate(timestamp) + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

CREATE TABLE audit_events ON CLUSTER '2x2' AS audit_events_local
    ENGINE = Distributed('2x2', currentDatabase(), audit_events_local, sipHash64(tenant_account_id));
```

**Retention:** 90d hot (per partition TTL DELETE). После 90d events живут **только** в S3+Glacier — это by-design (regulatory forensic available via cold-restore SLA, non-realtime).

### 2.7 S3 bucket layout (нормативно)

```
s3://kacho-audit-cold/
├── shared/                                         # standard tenants
│   └── 2026/05/19/14/                              # year/month/day/hour
│       ├── bat_01h2n4z9.jsonl.gz                   # compressed event lines
│       └── bat_01h2n4z9.manifest.signed            # HSM signature + Merkle metadata
└── tenant/
    └── acc_high_volume_xxx/                        # per-tenant изоляция (opt-in)
        └── 2026/05/19/14/
            ├── bat_01h2n4za.jsonl.gz
            └── bat_01h2n4za.manifest.signed
```

**Lifecycle policy** (S3 bucket configuration):
| Age | Storage Class | Cost (USD/GB/mo, eu-central-1 ref) |
|---|---|---|
| 0–30d | Standard | $0.023 |
| 30d–1y | Standard-IA | $0.0125 |
| 1y–10y | Glacier Deep Archive | $0.00099 |
| 10y+ | (delete via lifecycle rule) | — |

**Manifest format** (`bat_<id>.manifest.signed`):
```json
{
  "version": 1,
  "batch_id": "bat_01h2n4z9...",
  "batch_seq": 12345,
  "merkle_root": "sha256:<hex>",
  "batch_hash": "sha256:<hex>",
  "previous_batch_hash": "sha256:<hex>",
  "event_count": 873,
  "event_id_min": "evt_01h...",
  "event_id_max": "evt_01h...",
  "window_started_at": "2026-05-19T14:00:00Z",
  "window_ended_at":   "2026-05-19T14:05:00Z",
  "s3_uri": "s3://kacho-audit-cold/shared/2026/05/19/14/bat_01h2n4z9.jsonl.gz",
  "compression": "gzip",
  "content_sha256": "<gz blob sha256>",
  "signing_key_id": "hsm-audit-v1",
  "signing_algorithm": "ECDSA-P384-SHA384",
  "signature": "<base64 PKCS#11 raw signature>"
}
```

### 2.8 HSM signing contract (нормативно)

| Parameter | Value |
|---|---|
| Vendor | AWS CloudHSM (production); SoftHSM (dev/CI) |
| PKCS#11 library | `libCloudHSM_PKCS11.so` (prod) / `libsofthsm2.so` (dev) |
| Key alg | ECDSA secp384r1 (P-384) — FIPS 140-2 Level 3 acceptable |
| Key kid | `hsm-audit-v1` (rotation → `hsm-audit-v2`, dual-sign window 7d) |
| Sign-input | `SHA384(batch_hash || previous_batch_hash || merkle_root || event_count || window_started_at || window_ended_at)` |
| Per-batch latency budget | p99 ≤ 500ms (HSM call) |
| Failure mode | HSM unavailable → drainer pauses S3 writer, but Kafka/ClickHouse continue (graceful degrade). PagerDuty Critical alert |

### 2.9 SIEM webhook protocol (нормативно)

| Provider | Endpoint format | Auth | Payload |
|---|---|---|---|
| Datadog HEC | `https://http-intake.logs.datadoghq.com/api/v2/logs` | `DD-API-KEY: <token>` header | JSON array of CADF events; max 5MB/req or 1000 events |
| Splunk HEC | `https://<splunk>:8088/services/collector` | `Authorization: Splunk <token>` | `{"event": <CADF>, "sourcetype":"kacho:iam:audit"}` lines (one per event) |
| Elastic webhook | `https://<elastic>:9200/_bulk` | `Authorization: Bearer <token>` (or API key) | `_bulk` format: alternating index header + event |
| Generic webhook | `<configured-url>` | `Authorization: Bearer <SET-style JWT>` (signed by kacho-iam kid; aud=expected_audience) | JSON array of CADF events |

**Per-subscriber bearer** (generic webhook):
- JWT signed by `kacho-iam` private key (Phase 1 `oidc_jwks_keys` reused, kid prefixed `audit-signer-`).
- Claims: `iss=https://iam.kacho.cloud`, `aud=<expected_audience>`, `iat`, `exp=iat+5min`, `jti=<ULID>`, `kacho.subscriber_id=<sub_xxx>`, `kacho.event_count=<n>`.
- Subscriber verifies via JWKS at `https://iam.kacho.cloud/.well-known/jwks.json`.

**Failure handling:**
- `4xx (non-429)` → `failure_count++`; ≥5 → `enabled=false`, admin alert; events keep flowing in Kafka but не дублируются в этот SIEM.
- `5xx / 429 / timeout` → exponential backoff `[1s, 5s, 30s, 5min, 1h, 6h, 24h]`, max 8 attempts per event; затем `failed_terminal`.
- Per-subscriber rate-limit: 100 events/sec (Datadog default; configurable per row).

### 2.10 Detection rules library (нормативно)

| # | Rule ID | Window | Threshold | Severity | Action |
|---|---|---|---|---|---|
| 1 | `brute_force_signin` | 5min | >10 failed signins per (`actor_ip`, `tenant_account_id`) | High | Block IP via WAF + PagerDuty P2 |
| 2 | `impossible_travel` | 2h | 2+ successful signins from 2 different countries, same `actor_id` | High | Force step-up MFA + PagerDuty P3 |
| 3 | `mass_deletion` | 5min | >100 `iam.*.deleted` or `vpc.*.deleted` or `compute.*.deleted` per `actor_id` | Critical | Auto-revoke session + PagerDuty P1 |
| 4 | `out_of_hours_admin` | per-event | `actor_id` is admin AND timestamp outside tenant `business_hours` (configurable) | Medium | Slack notification + audit-log review queue |
| 5 | `privilege_escalation_sa` | per-event | ServiceAccount created an `access_binding` with `role.scope > actor.scope` | Critical | PagerDuty P1 + auto-revoke binding |
| 6 | `audit_signature_failure` | per-verifier-run | Any `audit_signing_batches.verifier_status='verified_broken'` | Critical | PagerDuty P0 (audit-tamper) — wakes CISO |
| 7 | `break_glass_usage` | per-event | Any event with `actor.acr=4` or `event_type` starts with `iam.break_glass.` | Critical | PagerDuty P1 + Slack #security-alerts + email security@kacho.cloud |
| 8 | `fga_tuple_drift` | hourly | Reconciliation found Postgres `access_bindings.status=ACTIVE` row without corresponding OpenFGA tuple OR vice-versa | Medium | Auto-repair via reconciler + Slack notification |

> Rules 1-5, 7, 8 — реализуются как SIEM-native (Datadog Workflows / Splunk SPL / Elastic Watcher) where each subscriber has these auto-provisioned. Rule 6 — реализуется **в нашем audit_verifier service** (HSM verification — нельзя делегировать SIEM-у).

---

## 3. Decision Log (final per phase — no deferred)

> Подсветка к D-18 из дизайн-документа: «Audit pipeline = full, не lazy». Все решения ниже — final;
> ни одно не помечено deferred. После APPROVED это становится контрактом Phase 9.

### P9-D1: CADF event schema (Cloud Auditing Data Federation, DMTF)

**Решение:** CADF v1.0.0 совместимый JSON schema, как описано в §2.3.

**Обоснование:** DMTF-стандарт, прямой mapping в Datadog Security / Splunk ES / IBM QRadar; SOC2-auditor-friendly; OpenTelemetry-совместимое поле `metadata.trace_id` для cross-system tracing.

**Альтернативы отвергнуты:** plain JSON (no standard, vendor lock-in каждый раз); ECS (Elastic Common Schema — vendor-narrow); OCSF (новый, ещё не широко принят 2026).

### P9-D2: Kafka KRaft mode, не Zookeeper

**Решение:** 3 broker'а в KRaft mode (Kafka 3.7+); Strimzi Operator для deploy в kacho-deploy.

**Обоснование:** Zookeeper deprecated since Kafka 3.5; KRaft проще оперировать (один control-plane), меньше moving parts; Strimzi Operator official-supported.

**Альтернативы отвергнуты:** RabbitMQ (no native streaming semantics), NATS JetStream (acks-семантика слабее, ecosystem меньше), Redpanda (вендорlocked single-vendor).

### P9-D3: Kafka durability — ack=all + idempotent producer + min.insync.replicas=2

**Решение:** Producer config — §2.5; broker config — `min.insync.replicas=2`, `unclean.leader.election.enable=false`.

**Обоснование:** Audit-log loss = compliance violation. Latency cost (~5-15ms per ack) приемлем: Phase 9 не на критическом hot-path Service mutation — drainer работает async (best-effort визибельность 1-2s).

### P9-D4: Kafka retention 7d (не больше)

**Решение:** `retention.ms=604800000` (7d) per topic.

**Обоснование:** Kafka — буфер для consumer'ов (ClickHouse, S3, SIEM); long-term storage — S3+Glacier (cheaper, immutable). 7d = comfortable replay window if один из consumer'ов сломался — успеваем починить и replay. Длиннее = размер Kafka storage непропорционально дорог.

### P9-D5: ClickHouse cluster 2 shards × 2 replicas (Altinity Operator)

**Решение:** 2×2 ClickHouse via Altinity Operator (production-tested K8s operator); ReplicatedMergeTree; Distributed table для query.

**Обоснование:** 2 shards = horizontal scale (sharding по `sipHash64(tenant_account_id)` обеспечивает изоляцию и параллелизм query); 2 replicas = HA (failure tolerance 1 node per shard). Altinity Operator — единственный production-grade K8s operator для ClickHouse, used by major SaaS.

**Альтернативы отвергнуты:** ClickHouse Cloud (SaaS lock-in, data residency issues for EU customers); single-node CH (no HA — audit downtime = compliance gap); Bitnami operator (community-only, stale).

### P9-D6: ClickHouse 90d hot retention (TTL DELETE на partition)

**Решение:** `TTL toDate(timestamp) + INTERVAL 90 DAY DELETE` per partition.

**Обоснование:** 90d — типичное «hot OLAP» окно для forensic queries (SOC2-incident response 30d window comfortably covered + 60d extra). После 90d events живут в S3 (restore via cold-path — out-of-band tool, не realtime).

### P9-D7: S3 5-min window batching

**Решение:** S3 batch writer группирует events в 5-минутные окна (`window_started_at..window_ended_at`); один S3 object per window per tenant-or-shared.

**Обоснование:** Balance — слишком мелкие batches → миллионы S3 objects (cost; Glacier per-request fees); слишком крупные → integrity blast-radius при tamper-detection (один batch broken = ~5min events suspect). 5min = эмпирически хорошее значение (used by Cloudflare R2 audit, AWS CloudTrail).

### P9-D8: S3 lifecycle policy — Standard 30d → IA 1y → Glacier Deep Archive 10y → delete

**Решение:** §2.7 таблица. 10y retention перекрывает SOC 2 (1y), ISO 27001 (3y), FedRAMP (3-7y depending), GDPR business records (6y EU), US-IRS (7y financial).

**Обоснование:** Glacier Deep Archive — cheapest tier с гарантией durability 99.999999999% (11 nines); retrieval SLA 12h Standard / 48h Bulk — приемлемо для post-incident forensic (не для realtime).

### P9-D9: HSM-signed batch manifests via PKCS#11 (ECDSA P-384)

**Решение:** Каждый S3 batch имеет companion `.manifest.signed` подписанный HSM-ключом (kid `hsm-audit-v1`); ECDSA secp384r1 — FIPS 140-2 Level 3 algorithm.

**Обоснование:** HSM-rooted trust — auditor accept'ит как «cryptographic tamper-evidence»; PKCS#11 — vendor-neutral (AWS CloudHSM, GCP Cloud HSM, Azure Dedicated HSM, on-prem Luna все support). P-384 (ECDSA) > P-256 для long-term storage (10y) — 192-bit security level safer против quantum attack timeline.

**Альтернативы отвергнуты:** RSA-4096 (signature size 512B vs ECDSA-P384 96B → S3 overhead для 10M batches значителен); Ed25519 (не FIPS-approved в FIPS 140-2; в 140-3 будет, но 2026 ещё не везде); software signing с key in K8s Secret (zero auditor acceptance).

### P9-D10: SoftHSM dev fallback

**Решение:** В dev/CI environments вместо CloudHSM — SoftHSM2 (open-source PKCS#11). Тот же код, разный `module=<path>`; ключи генерятся ephemeral per CI run.

**Обоснование:** CI cannot afford CloudHSM (~$1.5/hour per HSM × 24×7). SoftHSM API-compatible — переключение env-only.

### P9-D11: Merkle chain — `previous_batch_hash → batch_hash`

**Решение:** Каждый batch включает в manifest `previous_batch_hash` (= `batch_hash` предыдущего batch по `batch_seq`). Genesis batch (batch_seq=1) имеет `previous_batch_hash=NULL`. Chain forms hash-linked sequence.

**Обоснование:** Tamper-evidence — modify любой batch ⇒ его `batch_hash` меняется ⇒ next batch's `previous_batch_hash` mismatch ⇒ verifier detects + alerts. Equivalent к Bitcoin блокчейну (без proof-of-work — мы не нуждаемся в distributed consensus, single-writer HSM-signed достаточно).

### P9-D12: Merkle root over events внутри batch (sha256 binary tree)

**Решение:** Внутри batch — Merkle tree поверх `event_id`s (lexicographically sorted); root в manifest как `merkle_root`. Standard sha256 binary tree (duplicate last leaf if odd count, RFC 6962 style).

**Обоснование:** Позволяет partial-batch proof — если auditor хочет верифицировать только один event, не нужно скачивать весь batch (download proof path, не full batch). Standard approach.

### P9-D13: Independent verifier — daily cron, separate K8s pod, ReadOnly creds

**Решение:** `audit-verifier` deployment — отдельный pod (не часть `kacho-iam`); запускается раз в день (CronJob `0 2 * * *` UTC); HSM read-only key access (verify-only role); Postgres read-only credentials к `audit_signing_batches`.

**Обоснование:** Separation of duties — verifier compromise ≠ audit forge ability (verifier не может писать ни в HSM, ни в Postgres). Daily — баланс между timely detection (worst-case 24h to detect tamper) и operational cost (HSM verify call per batch ~50ms, 288 batches/day = 14s of HSM time).

### P9-D14: Verifier alert на integrity violation → PagerDuty P0

**Решение:** Если verifier обнаруживает (a) missing batch (gap in `batch_seq`), (b) broken chain (`previous_batch_hash` != actual prev `batch_hash`), (c) HSM signature mismatch — PagerDuty P0 incident `incident_key = audit-tamper-<batch_id>` + Slack #security-critical + email security@kacho.cloud + CISO mobile SMS.

**Обоснование:** Audit-log tamper = potential APT / insider attack — wake-up-everybody event (P0). False-positive rate должен быть extremely low — все 3 проверки deterministic + HSM-based, no probabilistic.

### P9-D15: SIEM forwarders — per-tenant subscription, opt-in

**Решение:** Tenants подписываются на свои audit-events через `InternalSIEMService.CreateSubscriber` (admin-RPC, account_admin role required). Один tenant может иметь N subscribers (Datadog + Splunk одновременно).

**Обоснование:** Compliance — некоторые tenants обязаны hold audit-логи в собственном SIEM (HIPAA, FedRAMP); мы не можем silently broadcast. Opt-in модель + per-tenant config = explicit consent.

### P9-D16: SIEM webhook signed JWT bearer (kacho-iam kid)

**Решение:** Generic webhook subscriber receives JWT (sigend by kacho-iam private key), claims §2.9; subscriber verifies via JWKS endpoint; replay protection via `jti` + 5min `exp`.

**Обоснование:** Datadog/Splunk HEC — static API key (vendor-required, can't change); generic webhook — JWT даёт integrity (subscriber знает source = kacho-iam, не impersonation).

### P9-D17: SIEM auto-disable on 5 consecutive failures

**Решение:** `failure_count` counter incremented on 4xx (non-429); ≥5 → `enabled=false` + admin alert (Slack + email to tenant admin). Subscriber может re-enable вручную через RPC после fix.

**Обоснование:** Защита от cascade-attack (SIEM offline → kacho-iam retry queue растёт → memory pressure → service degradation). Cut-off — feature, не баг.

### P9-D18: Per-tenant Kafka topic — opt-in для high-volume tenants

**Решение:** Default — shared topic `kacho-audit-events.shared` (64 partitions, hash(account_id)). High-volume tenants (>10k events/sec sustained — определяется ops-team) могут получить dedicated topic `kacho-audit-events.tenant.<account_id>` через `InternalAdminAuditService.PromoteTenantTopic` (cluster-admin only).

**Обоснование:** Shared topic — efficient для majority (low-volume). Dedicated topic — protection from noisy-neighbor + better SIEM filtering (subscriber подписывается на topic не на content). Opt-in — не overprovision Kafka brokers по умолчанию.

### P9-D19: AFTER INSERT trigger → `pg_notify('audit_event')` wakes drainer

**Решение:** Phase 1 `0013` уже создаёт trigger `audit_outbox_notify_trigger`. Phase 9 drainer слушает `LISTEN audit_event` на dedicated pgx connection + fallback polling `SELECT ... WHERE status='pending' AND next_attempt_at <= now() FOR UPDATE SKIP LOCKED LIMIT 1000` every 1s.

**Обоснование:** NOTIFY — sub-50ms wake-up (vs 1s polling); poll — fallback if NOTIFY pipe lost (connection drop, missed events during pod restart). Both — defense in depth.

### P9-D20: Drainer concurrent workers через `FOR UPDATE SKIP LOCKED`

**Решение:** N=4 worker goroutines per drainer pod; каждая делает `SELECT ... FOR UPDATE SKIP LOCKED LIMIT 250`; локальный batch → Kafka producer.send → on success `UPDATE status='delivered', delivered_at=now()`; on Kafka error → backoff schedule (`next_attempt_at=now() + retry_after`).

**Обоснование:** SKIP LOCKED — proven pattern (corelib/outbox/, kacho-vpc, KAC-15 reconciler); каждая worker никогда не конфликтует с другими (Postgres row lock granularity). N=4 даёт ~10k events/sec sustainable throughput per pod; HPA scales pods 1..10 по lag-metric.

### P9-D21: Idempotent Kafka producer ⇒ exactly-once при drainer crash

**Решение:** `enable.idempotence=true` + `transactional.id=audit-drainer-<pod_id>-<incarnation>` (incarnation incremented at startup). Producer.beginTransaction → send batch → commit. На crash — Kafka aborts in-flight tx → next pod incarnation produces без duplicate.

**Обоснование:** Exactly-once delivery — strict requirement для audit-log (no duplicate event_id в ClickHouse, no double-billing claims). Kafka idempotent producer + transactional API дают exactly-once в пределах consumer-group seen.

### P9-D22: ClickHouse consumer — Kafka Engine, не custom consumer

**Решение:** ClickHouse `Kafka` engine table + MaterializedView → `audit_events_local`. Auto-managed offset, no separate consumer code.

**Обоснование:** Production-tested by ClickHouse team; меньше moving parts; MV idempotency через event_id deduplication при INSERT — handled by ReplacingMergeTree (если нужен) или application-level retry-safe.

### P9-D23: ClickHouse batch INSERT 1000 events / 5s flush

**Решение:** Kafka engine batch settings — `max_block_size=1000`, `kafka_flush_interval_ms=5000`.

**Обоснование:** ClickHouse hates small inserts (one-row insert = one part = compaction storm). 1000-row batch — золотая середина (latency ~5s, throughput 200k events/sec sustained).

### P9-D24: S3 writer separate consumer group

**Решение:** S3 batch writer — отдельный consumer group `kacho-audit-s3-writer`, читает Kafka, group'ит по `tenant + 5min window`, генерит batch, signs via HSM, uploads.

**Обоснование:** Otdelenie от ClickHouse — failure isolation (S3 writer down ≠ ClickHouse писать перестаёт). Consumer group offset commit ONLY после successful S3 upload + HSM sign + audit_signing_batches INSERT → at-least-once с idempotency на S3 (object key = batch_id, deterministic).

### P9-D25: SIEM forwarders — Kafka consumer group per subscriber

**Решение:** Каждый SIEM subscriber = отдельный Kafka consumer group `kacho-audit-siem-<subscriber_id>`. Filter по event_types в-memory (subscriber может subscribe только на subset event types).

**Обоснование:** Per-subscriber consumer group → independent offset → один subscriber stuck не блокирует других. Filter в-memory — Kafka не имеет broker-side filtering (no expensive transformations).

### P9-D26: Drainer cursor checkpointing for recovery

**Решение:** `audit_drainer_state` table — каждый pod heartbeats `(drainer_id, last_seen_event_id, last_heartbeat_at)` every 5s. На startup pod reads own previous row (если есть) — resume from `last_seen_event_id+`. Stale pods (last_heartbeat_at > 30s ago) — другие pods НЕ берут их work (FOR UPDATE SKIP LOCKED уже гарантирует no double-pick).

**Обоснование:** Pod restart recovery — без потери events. `FOR UPDATE SKIP LOCKED` на самом `audit_outbox` — primary mechanism (status='pending' rows availaible после lock release on crash); `audit_drainer_state` — для observability + Grafana lag metric.

### P9-D27: Verifier walks ALL batches, not just new ones

**Решение:** Daily cron — full walk `SELECT * FROM audit_signing_batches ORDER BY batch_seq ASC`. Verify each batch's signature + Merkle root + chain link. ~10k batches за месяц × 50ms HSM verify = 8min — приемлемо daily.

**Обоснование:** Tamper можно сделать post-hoc на старом batch (если attacker compromise'нул S3 retention period). Full walk catches это; incremental (только new batches) — пропустил бы.

### P9-D28: HSM key rotation — dual-sign 7d window

**Решение:** Старый key kid `hsm-audit-v1` остаётся active 7d параллельно с новым `hsm-audit-v2`; новые batches sign'аются `v2`, но verifier accept'ит оба. После 7d — `v1` retired (signature verify-only, не sign).

**Обоснование:** Smooth rotation без downtime; verifier may verify old batches signed with `v1` ad infinitum (key retention).

### P9-D29: PII pseudonymization в Kafka producer side для GDPR erasure

**Решение:** GDPR Article 17(3)(b) — audit retained для legal claims (compliance > erasure). Но в новые events для erased users — actor.email → `gdpr-erased-<hash>`, actor.ip → `null`, payload.diff stripped of PII. Pseudonymization применяется **в drainer Phase 9**, читая `users.status=ERASED` mirror (eventual consistency 30d cool-off — Phase 7 GDPR).

**Обоснование:** Pre-erasure события — не trogaem (compliance retention). Post-erasure events — pseudonymize (правом на стирание уважается partially).

### P9-D30: Grafana dashboards для audit visibility

**Решение:** Phase 9 ships 4 Grafana dashboards в kacho-deploy:
1. **Audit pipeline overview** — queue depth, drainer lag, throughput per topic, ClickHouse ingestion rate, S3 batch write rate, SIEM forwarder rate.
2. **Audit detection rules** — fire rate per rule, top tenants by rule hits, time series.
3. **Audit integrity** — verifier daily run status, signature failures, chain breaks, HSM latency.
4. **SIEM subscribers** — per-subscriber delivery rate, failure rate, auto-disable events.

---

## 4. Target architecture

### 4.1 Data flow (нормативно)

```
[Service mutation handler (Phase 3-7)]
    │ BEGIN TX
    │   INSERT into <domain table> ...
    │   INSERT into audit_outbox (event_payload=CADF)
    │ COMMIT
    │
    ▼ trigger AFTER INSERT → NOTIFY 'audit_event'
[audit_drainer (kacho-iam worker, N pods, 4 goroutines each)]
    │ LISTEN audit_event + fallback 1s poll
    │ FOR UPDATE SKIP LOCKED LIMIT 250
    │ filter+pseudonymize (P9-D29)
    │ Kafka producer.beginTransaction → sendBatch → commit (ack=all idempotent)
    │ UPDATE audit_outbox SET status='delivered', delivered_at=now()
    │ heartbeat audit_drainer_state every 5s
    │
    ▼
[Kafka audit-topic (3 brokers KRaft, RF=3, min.isr=2, zstd, 7d retention)]
    │   topics: kacho-audit-events.shared (default)
    │           kacho-audit-events.tenant.<account_id> (opt-in high-volume)
    │
    ├─→ [ClickHouse Kafka engine (consumer group: kacho-audit-clickhouse)]
    │   - max_block_size=1000, kafka_flush_interval_ms=5000
    │   - MV → ReplicatedMergeTree audit_events_local on 2x2 cluster
    │   - PARTITION BY (tenant_account_id, day); ORDER BY (tenant, ts, event_id)
    │   - TTL 90d DELETE; Distributed table audit_events for queries
    │   - Query latency p95 ≤ 60s for forensic queries
    │
    ├─→ [S3 batch writer (kacho-iam worker, consumer group: kacho-audit-s3-writer)]
    │   - 5-min windows per (tenant_or_shared, window_start)
    │   - sort events by event_id, JSONL.gz
    │   - HSM PKCS#11 sign batch_hash (sha256 over jsonl-gz blob) + Merkle root
    │   - INSERT audit_signing_batches (atomic with S3 upload via 2PC-pattern: S3 first, then DB row; on DB fail → S3 cleanup)
    │   - S3 upload <batch_id>.jsonl.gz + <batch_id>.manifest.signed
    │   - S3 lifecycle policy: Standard 30d → IA 1y → Glacier 10y
    │   - Kafka commit offset ONLY after both S3 + DB success
    │
    ├─→ [SIEM forwarders (kacho-iam workers, per subscriber consumer group: kacho-audit-siem-<sub_id>)]
    │   - One CG per subscriber (independent offset)
    │   - In-memory filter by event_types[]
    │   - Build JWT bearer (kacho-iam kid, 5min exp, jti)
    │   - POST Datadog HEC / Splunk HEC / Elastic _bulk / generic webhook
    │   - failure_count++ on 4xx; auto-disable ≥5; exp backoff on 5xx/429
    │
    └─→ [Independent verifier (daily CronJob 0 2 * * *)]
        - Separate K8s pod, ReadOnly Postgres + HSM verify-only
        - Walk all audit_signing_batches ORDER BY batch_seq
        - Verify HSM signature on each manifest
        - Verify Merkle chain (previous_batch_hash == prev.batch_hash)
        - Verify event Merkle root by downloading sample of S3 batches (every 100th — full; rest — manifest-only)
        - UPDATE audit_signing_batches.verifier_status
        - Alert on integrity violation → PagerDuty P0 + Slack #security-critical + CISO SMS
        - INSERT audit_verifier_runs row
```

### 4.2 Component placement

```
kacho-corelib/
└── audit/
    ├── event.go              # CADF schema (P9-D1)
    ├── outbox.go             # outbox enqueue helper (shared with caep)
    ├── hsmsigner.go          # PKCS#11 wrapper (CloudHSM / SoftHSM via env)
    ├── merkle.go             # Merkle tree (RFC 6962 style)
    ├── pseudonymize.go       # GDPR pseudonymize helper (P9-D29)
    └── audit_test.go

kacho-iam/
├── internal/
│   ├── audit/
│   │   ├── drainer.go        # task 9.2 — Kafka producer worker
│   │   ├── clickhouse_ingestor.go  # task 9.5 — alternative if Kafka engine insufficient
│   │   ├── s3writer.go       # task 9.6 — 5min window batching + HSM sign + S3 upload
│   │   ├── verifier.go       # task 9.7 — daily integrity walk
│   │   └── siem_forwarder.go # task 9.8 — per-subscriber consumer group
│   ├── service/
│   │   └── siem.go           # InternalSIEMService CRUD use-cases (task 9.8)
│   ├── handler/
│   │   └── internal_siem.go  # gRPC handler (internal-port 9091)
│   ├── repo/
│   │   ├── audit_outbox.go   # extended for drainer reads (SKIP LOCKED)
│   │   ├── audit_batches.go  # INSERT after S3 upload
│   │   ├── siem_subscribers.go  # CRUD (CAS for failure_count++)
│   │   └── *_integration_test.go
│   └── migrations/
│       ├── 0021_siem_subscribers.sql
│       ├── 0022_audit_drainer_state.sql
│       └── 0023_audit_verifier_runs.sql

kacho-proto/
└── proto/kacho/cloud/iam/v1/
    └── internal_siem_service.proto   # SIEMSubscriber + CRUD + TestDelivery

kacho-deploy/
├── kafka/
│   └── strimzi-kafka.yaml             # Strimzi Operator + Kafka KRaft 3 brokers (task 9.3)
├── clickhouse/
│   └── altinity-clickhouse.yaml       # Altinity Operator + 2x2 cluster (task 9.4)
├── hsm/
│   └── cloudhsm-provisioning.tf       # Terraform: AWS CloudHSM cluster + PKCS#11 client (task 9.11)
├── audit-verifier/
│   └── cronjob.yaml                   # CronJob with ReadOnly creds
├── s3-buckets/
│   └── kacho-audit-cold.tf            # S3 bucket + lifecycle policy + Glacier
└── grafana/dashboards/
    ├── audit-pipeline-overview.json
    ├── audit-detection-rules.json
    ├── audit-integrity.json
    └── siem-subscribers.json
```

### 4.3 Concurrency / failure-modes

| Failure | Behavior |
|---|---|
| Drainer pod crash | Postgres row locks release → other drainer pods pick up via SKIP LOCKED; no event loss |
| Kafka broker down | min.isr=2 ensures producer continues if 1 of 3 brokers down; if 2 down → producer errors → drainer retry with backoff |
| ClickHouse shard down | Kafka engine consumer group continues on remaining replica (RF=2 per shard); queries degrade |
| S3 unavailable | Batch writer pauses Kafka offset commit; Kafka retention 7d covers outage; on recovery — catches up |
| HSM unavailable | S3 writer pauses (cannot sign); PagerDuty Critical; Kafka/ClickHouse continue |
| SIEM endpoint 4xx repeated | Auto-disable subscriber after 5 failures; tenant admin alerted |
| Verifier finds tamper | PagerDuty P0; subsequent batches continue (forensic snapshot preserved) |

---

## 5. Декомпозиция по компонентам (что строится в каком PR)

### 5.1 kacho-proto (PR #1, task 9.2 prerequisite)

- **Файлы:**
  - `proto/kacho/cloud/iam/v1/internal_siem_service.proto` — `SIEMSubscriber` message + `InternalSIEMService` (Create/Get/List/Update/Delete/TestDelivery/EnableSubscriber/DisableSubscriber).
- **Сообщения:**
  - `SIEMSubscriber {id, account_id, provider [DATADOG_HEC|SPLUNK_HEC|ELASTIC_BULK|GENERIC_WEBHOOK], endpoint_url, secret_ref, expected_audience, event_types[], enabled, failure_count, last_success_at, last_failure_at, last_failure_reason, created_at, updated_at}`.
- **DoD:** `buf lint`, `buf breaking` зелёные; gen/go/... commit'ится в kacho-proto; vault `rpc/iam-internal-siem-service.md` создан.

### 5.2 kacho-corelib (PR #2, task 9.2)

- **Файлы:**
  - `audit/event.go` — CADF Event struct + Marshal/Unmarshal helpers.
  - `audit/outbox.go` — `EnqueueEvent(tx pgx.Tx, ev Event) error` — used by mutation handlers (kacho-iam Phase 3-7).
  - `audit/hsmsigner.go` — `HSMSigner interface { Sign(data []byte) ([]byte, error); Verify(data, sig []byte) error }`; impl `pkcs11HSMSigner` via `github.com/ThalesIgnite/crypto11`.
  - `audit/merkle.go` — `BuildMerkleTree(leaves [][]byte) (root []byte, proofs map[string][][]byte)`; RFC 6962 binary tree, sha256.
  - `audit/pseudonymize.go` — `PseudonymizeForErasedUser(ev *Event, erasedUserIDs map[string]bool)`.
- **DoD:** `go test ./audit/... -race -count=10` зелёный; SoftHSM-based tests в CI.

### 5.3 kacho-iam (PR #3, tasks 9.2 + 9.5 + 9.6 + 9.7 + 9.8 + 9.9)

- **Миграции:**
  - `internal/migrations/0021_kac127_siem_subscribers.sql`.
  - `internal/migrations/0022_kac127_audit_drainer_state.sql`.
  - `internal/migrations/0023_kac127_audit_verifier_runs.sql`.
- **Use-cases (service/):**
  - `SIEMService.Create/Get/List/Update/Delete/TestDelivery/EnableSubscriber/DisableSubscriber`.
- **Handlers:**
  - `handler/internal_siem.go` — gRPC InternalSIEMService impl (internal-port 9091).
- **Workers (internal/audit/):**
  - `drainer.go` — `Run(ctx) error`; goroutine pool size N=4; SKIP LOCKED batching; Kafka producer.
  - `s3writer.go` — Kafka consumer group `kacho-audit-s3-writer`; 5-min window batching; HSM sign; S3 upload; `audit_signing_batches` INSERT.
  - `verifier.go` — `Run(ctx) (*VerifierRunResult, error)`; CronJob entry.
  - `siem_forwarder.go` — one goroutine per subscriber; Kafka consumer group; webhook POST.
  - `detection_rules.go` — rule 6 (audit signature failure) — local detection; rules 1-5, 7, 8 — SIEM-native (we provide SPL/Datadog config templates in kacho-deploy).
- **Tests:**
  - `internal/repo/audit_outbox_drainer_integration_test.go` — SKIP LOCKED concurrency; recovery.
  - `internal/repo/audit_signing_batches_integration_test.go` — Merkle chain enforcement.
  - `internal/repo/siem_subscribers_integration_test.go` — CAS на failure_count.
  - `internal/audit/drainer_test.go` — Kafka testcontainer + Postgres.
  - `internal/audit/s3writer_test.go` — MinIO testcontainer + SoftHSM.
  - `internal/audit/verifier_test.go` — Merkle chain tamper detection.
  - `internal/audit/siem_forwarder_test.go` — httptest webhook stub.
- **DoD:** unit + integration зелёные; `make test` зелёный; vault `resources/iam-siem-subscriber.md` + `packages/iam-audit.md` created.

### 5.4 kacho-deploy (PR #4, tasks 9.3 + 9.4 + 9.6 + 9.10 + 9.11)

- **Kafka:** `kafka/strimzi-kafka.yaml` — Strimzi Operator + 3-broker KRaft cluster + topics auto-create via `KafkaTopic` CRDs.
- **ClickHouse:** `clickhouse/altinity-clickhouse.yaml` — Altinity Operator + `ClickHouseInstallation` 2 shards × 2 replicas + table `audit_events_local` (via init-container ddl).
- **S3 bucket:** `s3-buckets/kacho-audit-cold.tf` — Terraform: bucket + lifecycle policy (Standard 30d → IA → Glacier 10y) + bucket policy (read by kacho-iam IAM role, no public).
- **HSM (task 9.11):** `hsm/cloudhsm-provisioning.tf` — Terraform: AWS CloudHSM cluster + ENI + security group + PKCS#11 client configmap + ECDSA P-384 key generated via `key_mgmt_util` initContainer.
- **Dev fallback:** `hsm/softhsm-dev.yaml` — K8s Deployment of SoftHSM + key generation Job; mounted into kacho-iam pods via secret.
- **Audit verifier CronJob:** `audit-verifier/cronjob.yaml` — schedule `0 2 * * *`; image `kacho-iam:latest` with command `kacho-iam audit-verify`; resources cpu=1, mem=2Gi; ReadOnly PG creds + HSM verify-only role.
- **Grafana dashboards (task 9.10):** 4 JSON files в `grafana/dashboards/`; provisioned via grafana-operator ConfigMap.
- **PagerDuty integration:** `pagerduty/audit-tamper-service.json` — PD service config with escalation policy.
- **DoD:** `make dev-up` deploys all components; integration smoke tests (audit event → Kafka → ClickHouse → S3) зелёный.

### 5.5 kacho-api-gateway (PR #5, task 9.8)

- **Registration:**
  - `InternalSIEMService` зарегистрирован на internal mux only (port 9091; `/iam/v1/siemSubscribers/...`); НЕ на public mux (запрет #6).
- **DoD:** newman tests passing для admin CRUD.

### 5.6 kacho-workspace (PR #6, task 9.12)

- **Docs:**
  - This file APPROVED.
  - `obsidian/kacho/KAC/KAC-127.md` — обновлён ссылками на Phase 9 PR'ы.
  - `obsidian/kacho/resources/iam-siem-subscriber.md` — new.
  - `obsidian/kacho/packages/iam-audit.md` — new.
  - `obsidian/kacho/edges/iam-to-kafka-audit-pipeline.md` — new (cross-service edge: kacho-iam → Kafka brokers).
  - `obsidian/kacho/edges/iam-to-clickhouse-audit-storage.md` — new.
  - `obsidian/kacho/edges/iam-to-s3-audit-cold-storage.md` — new.
  - `obsidian/kacho/edges/iam-to-hsm-pkcs11-signing.md` — new.
  - `obsidian/kacho/edges/iam-to-siem-webhook-delivery.md` — new.
  - `obsidian/kacho/rpc/iam-internal-siem-service.md` — new.
- **DoD:** YouTrack KAC-127 epic linked with all Phase 9 subtasks; sprint comments.

### 5.7 Newman regression suite

- `tests/newman/cases/9.x_audit_pipeline.py` — generates Postman collection covering:
  - SIEM subscriber CRUD happy + negative.
  - TestDelivery → verify webhook received signed JWT.
  - Audit event end-to-end (mutation → Kafka → ClickHouse query within 60s).
  - Verifier dry-run via admin RPC `InternalAdminAuditService.RunVerifierNow` (debug-only).

### 5.8 PR-chain order (топологическая сортировка)

1. **PR #1** — kacho-proto (SIEMSubscriber message + InternalSIEMService).
2. **PR #2** — kacho-corelib (`audit/` package — CADF + HSM signer + Merkle + pseudonymize).
3. **PR #3** — kacho-iam (migrations 0021-0023 + workers + handlers + tests).
4. **PR #4** — kacho-deploy (Kafka + ClickHouse + S3 + HSM provisioning + CronJob + Grafana).
5. **PR #5** — kacho-api-gateway (InternalSIEMService registration).
6. **PR #6** — kacho-workspace (docs + vault).

Цепочка GitHub-deps: каждый последующий PR использует `Blocked by PRO-Robotech/<prev>#<N>` в теле.

---

## 6. Given-When-Then сценарии (нормативные acceptance-тесты)

> **Конвенции** (см. Phase 1 / Phase 7 acceptance-doc):
> - Каждый сценарий пронумерован `9.<rubric>.<seq>`.
> - **Given** — pre-state.
> - **When** — действие.
> - **Then** — observable outcome (с измеримыми утверждениями).
> - Где применимо — приводится payload фрагмент.

### 6.1 audit_outbox atomic enqueue (Phase 1 invariants reused, Phase 9 verifies still hold)

#### Scenario 9.1.1 — Mutation + outbox INSERT в одной TX → both visible after COMMIT

**Given** Phase 9 integration test (testcontainers Postgres + applied migrations 0001..0023).
**And** test-helper создаёт User `usr_alice`, Account `acc_xxx`.
**When** обработчик мутации (имитирующий kacho-iam Phase 3 access_binding handler):
```go
err := db.WithTx(ctx, func(tx pgx.Tx) error {
    // 1) domain mutation
    if _, err := tx.Exec(ctx, "INSERT INTO access_bindings (id, account_id, ...) VALUES ($1, $2, ...)",
        "acb_p9_01", "acc_xxx"); err != nil { return err }
    // 2) audit outbox enqueue via corelib
    return audit.EnqueueEvent(ctx, tx, audit.Event{
        ID: "evt_p9_01_01h...",
        EventType: "iam.access_binding.created",
        Tenant: audit.Tenant{AccountID: "acc_xxx"},
        Actor: audit.Actor{Type: "user", ID: "usr_alice"},
        Target: audit.Target{Type: "access_binding", ID: "acb_p9_01"},
        Action: "create", Outcome: "success",
    })
})
```

**Then** `err == nil`.
**And** `SELECT COUNT(*) FROM access_bindings WHERE id='acb_p9_01'` = 1.
**And** `SELECT COUNT(*) FROM audit_outbox WHERE id='evt_p9_01_01h...'` = 1, `status='pending'`.
**And** `event_payload->>'event_type' = 'iam.access_binding.created'`.
**And** `event_payload->'actor'->>'id' = 'usr_alice'`.

#### Scenario 9.1.2 — Rollback в mutation handler → ни одной row не остаётся

**Given** тот же setup.
**When** в TX выполнен INSERT access_binding + EnqueueEvent, затем симулируется ошибка (third statement returns error), defer Rollback срабатывает.
**Then** `SELECT COUNT(*) FROM access_bindings WHERE id='acb_p9_rb'` = 0.
**And** `SELECT COUNT(*) FROM audit_outbox WHERE id='evt_p9_rb_...'` = 0.
**And** в Kafka **никаких** сообщений с event_id = `evt_p9_rb_...` (drainer не видит rolled-back event).

#### Scenario 9.1.3 — Trigger AFTER INSERT срабатывает с NOTIFY 'audit_event'

**Given** на отдельном connection установлен `LISTEN audit_event`.
**When** в другом connection BEGIN; INSERT audit_outbox row `evt_p9_listen_01`; COMMIT.
**Then** listener получает NOTIFY payload в течение 50ms.
**And** payload содержит `event_id='evt_p9_listen_01'` (либо minimum row.id).

#### Scenario 9.1.4 — ROLLBACK НЕ триггерит NOTIFY

**Given** `LISTEN audit_event` на conn A.
**When** на conn B: BEGIN; INSERT audit_outbox; ROLLBACK.
**Then** listener получает 0 NOTIFY за 2s (PostgreSQL NOTIFY semantics: only AFTER COMMIT trigger emits).

---

### 6.2 audit_drainer (Kafka producer)

#### Scenario 9.2.1 — Drainer reads pending events via SKIP LOCKED

**Given** Postgres testcontainer + Kafka testcontainer (Bitnami Kafka KRaft); migrations applied.
**And** в `audit_outbox` 1000 rows status='pending', `next_attempt_at <= now()`.
**And** drainer pod (1 экз, 4 goroutines) запущен с config: `KAFKA_BROKERS=...`, `BATCH_SIZE=250`.
**When** drainer работает 30s.
**Then** все 1000 rows перешли в `status='delivered'`, `delivered_at IS NOT NULL`.
**And** в Kafka topic `kacho-audit-events.shared` ровно **1000** messages (no duplicates).
**And** offset committed для consumer group `kacho-audit-drainer-test`.
**And** drainer latency p95 ≤ 200ms (between `audit_outbox.created_at` и Kafka offset commit time).

#### Scenario 9.2.2 — Batch send 1000 events с ack=all

**Given** Kafka brokers up (3 экз), `min.insync.replicas=2`.
**And** producer config — `acks=all`, `enable.idempotence=true`, `transactional.id=audit-drainer-test-1`.
**When** drainer отправляет batch из 1000 events (один Kafka commit).
**Then** все 1000 messages присутствуют на disk у leader + 1 follower (min.isr=2 enforced).
**And** при kill -9 leader-broker (одного из 3) — все 1000 events остаются consumable (replication работает).

#### Scenario 9.2.3 — Idempotent producer prevents duplicate on retry

**Given** Drainer pod 1 отправил batch, получил Kafka response timeout, retry.
**When** drainer retry сразу же.
**Then** Kafka deduplicates на broker side через `producer_id + sequence_number` → в topic ровно **N** messages, не 2N.
**And** test reads Kafka topic via consumer.assignPartitions; verifies каждый event_id уникален.

#### Scenario 9.2.4 — Partition strategy: hash by tenant_account_id

**Given** topic `kacho-audit-events.shared` с 64 partitions.
**And** 1000 events с 5 различными `tenant_account_id`s (acc_a..acc_e).
**When** drainer отправляет все 1000.
**Then** все events с одинаковым `tenant_account_id` лежат в одном partition (verify via consumer.position per partition).
**And** распределение по partitions — hash-based, не concentrated в один partition.

#### Scenario 9.2.5 — Drainer recovery: pod restart resumes without loss

**Given** drainer pod 1 обработал 500 events of 1000 batch, затем kill -9.
**And** 500 events в Kafka, 500 ещё `status='pending'`.
**When** drainer pod 2 startup.
**Then** pod 2 видит 500 unprocessed (status='pending') через `FOR UPDATE SKIP LOCKED` (rows из pod 1 уже unlocked после crash).
**And** pod 2 завершает все 500 → ClickHouse total = 1000 events.
**And** **никаких** duplicate event_id в Kafka topic.

#### Scenario 9.2.6 — Drainer concurrent SKIP LOCKED — no double-pick

**Given** 2 drainer pods (4 goroutines each = 8 workers concurrent).
**And** 10000 events в audit_outbox status='pending'.
**When** 8 workers concurrently `SELECT ... FOR UPDATE SKIP LOCKED LIMIT 250`.
**Then** через 60s все 10000 events delivered.
**And** **каждый** event_id появился в Kafka ровно 1 раз (Kafka topic consumer assert).
**And** **никаких** Postgres deadlocks (deadlock_count metric = 0).

#### Scenario 9.2.7 — Drainer back-pressure: Kafka unavailable → retry with backoff

**Given** Kafka brokers down (network partition).
**When** drainer пытается send batch.
**Then** producer возвращает `kafka.UnknownTopicOrPartition` / connection error → drainer marks batch `audit_outbox.next_attempt_at = now() + backoff` (initial 1s, exp doubling до 60s max).
**And** events остаются `status='pending'` (НЕ marked 'delivered').
**And** через 5min Kafka brokers recover → drainer resumes → все events catch up.

---

### 6.3 ClickHouse consumer (Kafka engine + MaterializedView)

#### Scenario 9.3.1 — ClickHouse ingestion batch 1000 events / 5s flush

**Given** ClickHouse 2x2 cluster + Kafka topic `kacho-audit-events.shared` с 5000 events.
**And** Kafka engine table `audit_events_kafka_buffer` + MV → `audit_events_local`.
**When** ждём 10s после Kafka events appeared.
**Then** `SELECT count() FROM audit_events` (Distributed view) = 5000.
**And** все события partitioned по `(tenant_account_id, day)` корректно (verify через `SELECT name FROM system.parts WHERE table = 'audit_events_local'`).
**And** `system.replication_queue` empty (no replication lag).

#### Scenario 9.3.2 — Replicated MergeTree partition: per-tenant-per-day

**Given** events с 3 tenants × 3 days = 9 partitions expected.
**When** ingestion завершён.
**Then** `SELECT count(DISTINCT partition) FROM system.parts WHERE table='audit_events_local'` = 9.
**And** каждая partition name = `(tenant_account_id, day)`.

#### Scenario 9.3.3 — 90d retention TTL drops old partition

**Given** test event inserted с `timestamp = now() - INTERVAL '95 DAY'`.
**And** TTL `toDate(timestamp) + INTERVAL 90 DAY DELETE`.
**When** ClickHouse merge cycle runs (`OPTIMIZE TABLE audit_events_local FINAL` or natural).
**Then** event row no longer present (`SELECT count() WHERE event_id=test_id` = 0).
**And** S3 cold storage НЕ затронут (verify S3 object still exists).

#### Scenario 9.3.4 — Query latency p95 ≤ 60s для forensic query

**Given** ClickHouse содержит 90d × 100k events/day per tenant = 9M events per tenant.
**When** forensic query: `SELECT * FROM audit_events WHERE tenant_account_id='acc_xxx' AND event_type='iam.session.failed_signin' AND timestamp BETWEEN now() - 24h AND now()`.
**Then** query completes within 60s p95 (5 запусков, p95 from times).
**And** result returned correctly (count matches expected).

#### Scenario 9.3.5 — ClickHouse shard down — query degrades but works

**Given** 2x2 cluster, shard 1 replica 1 down (kill pod).
**When** Distributed query `SELECT count() FROM audit_events`.
**Then** query succeeds (RF=2 ensures shard 1 replica 2 alive).
**And** ClickHouse logs показывают fallback to replica 2.

#### Scenario 9.3.6 — ClickHouse ingestion idempotency: replay same Kafka offset

**Given** drainer crash посередине batch; Kafka consumer group offset rewound.
**When** ClickHouse Kafka engine re-reads same offset.
**Then** `audit_events` table содержит каждый event_id ровно 1 раз (assert через `SELECT count(DISTINCT event_id) FROM audit_events`).

> **Implementation note**: ReplacingMergeTree поверх audit_events_local + dedup by event_id, либо application-level через ClickHouse INSERT IGNORE-style query. Решение выбрать в task 9.5 implementation; результирующее поведение должно соответствовать этому сценарию.

---

### 6.4 S3 batch writer + HSM signing

#### Scenario 9.4.1 — 5-min window batching

**Given** S3 writer consumer group running; Kafka topic с 873 events spanning `[14:00:00, 14:04:59]`.
**And** S3 testcontainer (MinIO).
**When** S3 writer накапливает events за окно `[14:00, 14:05]`, генерит batch.
**Then** в S3 bucket `kacho-audit-cold/shared/2026/05/19/14/` появляется ровно 1 object pair:
- `bat_<ulid>.jsonl.gz` (compressed JSONL of 873 events sorted by event_id).
- `bat_<ulid>.manifest.signed` (JSON manifest §2.7).

**And** `audit_signing_batches` table содержит row с `batch_seq = prev+1`, `event_count=873`, `event_id_min` / `event_id_max` correct.
**And** S3 object content_sha256 = `manifest.content_sha256`.

#### Scenario 9.4.2 — JSONL.gz compression ratio

**Given** 1000 CADF events (~1KB each = ~1MB raw).
**When** S3 writer compresses to `bat_<id>.jsonl.gz`.
**Then** compressed size ≤ 200KB (5:1 ratio for JSON typical; assert размер file via S3 ListObjects).

#### Scenario 9.4.3 — HSM signs batch manifest

**Given** SoftHSM в CI с key kid `hsm-audit-v1` (ECDSA P-384 generated).
**And** batch with `batch_hash=sha256(jsonl-gz-blob)`, `previous_batch_hash=<prev>`, `merkle_root=<root>`.
**When** S3 writer calls `hsm.Sign(SHA384(batch_hash || previous_batch_hash || merkle_root || event_count || window_started_at || window_ended_at))`.
**Then** signature returned, 96 bytes (ECDSA-P384 raw).
**And** `audit_signing_batches.signature` column saved with bytea = signature.
**And** `manifest.signed` JSON field `signature` = base64 of bytea.
**And** `hsm.Verify(...)` с тем же data + signature + public key returns nil.

#### Scenario 9.4.4 — HSM unavailable → S3 writer pauses

**Given** SoftHSM stopped (or CloudHSM ENI down).
**When** S3 writer calls Sign.
**Then** error returned `hsm: connection refused`.
**And** S3 writer НЕ commits Kafka offset (events remain replay-able).
**And** PagerDuty alert `audit-hsm-unavailable` fired (Critical).
**And** Kafka topic retention (7d) buffers events until HSM recovers.

#### Scenario 9.4.5 — S3 upload atomic with audit_signing_batches INSERT

**Given** S3 writer готов upload batch.
**When** sequence:
1. S3 PUT `bat_<id>.jsonl.gz`.
2. S3 PUT `bat_<id>.manifest.signed`.
3. Postgres INSERT `audit_signing_batches` row.

Случай: шаг 3 fails (DB connection lost).
**Then** Pipeline должен retry от step 1 (idempotent — same batch_id deterministic from window+tenant). На retry — S3 PUT overrwrites existing (S3 idempotent on object key); DB INSERT eventually succeeds.

> **Alternative implementation**: 2PC-style — first INSERT DB row `status='uploading'`, then S3 upload, then UPDATE `status='uploaded'`; on crash recovery — scan rows `status='uploading'` and verify S3 state, complete or rollback. Task 9.6 выбирает один из подходов; сценарий проверяет результирующий invariant (no orphan DB row without S3, no orphan S3 without DB).

#### Scenario 9.4.6 — S3 lifecycle policy moves to Glacier after 1y

**Given** S3 object `bat_<id>` uploaded `now - 366d`.
**And** lifecycle policy: Standard 30d → IA 1y → Glacier Deep Archive 10y.
**When** S3 lifecycle scheduler runs daily.
**Then** object's storage class = `DEEP_ARCHIVE` (verify via S3 HEAD object response header `x-amz-storage-class`).
**And** retrieval requires `RestoreObject` API call (12h Standard / 48h Bulk SLA).

---

### 6.5 HSM signing contract

#### Scenario 9.5.1 — PKCS#11 sign via session

**Given** SoftHSM2 initialized; slot 0 with key kid `hsm-audit-v1` (ECDSA P-384).
**When** corelib `hsmsigner.Sign(data=randomBytes(32))`.
**Then** returns signature 96 bytes (DER-decoded raw form: r||s, 48 bytes each).

#### Scenario 9.5.2 — Signature stored in audit_signing_batches.signature (bytea)

**Given** test creates batch with signature.
**When** SELECT signature FROM audit_signing_batches WHERE batch_id=<id>.
**Then** column type `bytea`, length 96.
**And** `signature_format = 'ECDSA-P384-RAW'` (or via separate column if needed) — assert via dec/enc roundtrip.

#### Scenario 9.5.3 — Verify with HSM public key

**Given** verifier service has read-only HSM session.
**And** batch row with stored signature.
**When** `hsmsigner.Verify(data, signature, kid='hsm-audit-v1')`.
**Then** returns nil (verification success).

#### Scenario 9.5.4 — Tamper detection: modified signature → verify fails

**Given** batch row; copy signature.
**When** flip 1 bit в signature, then Verify.
**Then** returns error `crypto/ecdsa: verification failed`.

#### Scenario 9.5.5 — HSM key rotation (dual-sign window 7d)

**Given** new kid `hsm-audit-v2` generated; both `v1` and `v2` active.
**When** new batch signed with `v2`.
**Then** `audit_signing_batches.signing_key_id = 'hsm-audit-v2'`.
**And** verifier accepts both v1 and v2 batches (loop through known kids).
**And** after 7d — orchestration disables `v1` sign (Sign returns error), но Verify works ad infinitum.

---

### 6.6 Merkle chain integrity

#### Scenario 9.6.1 — Batch N references batch N-1 hash

**Given** batches `batch_seq=1, 2, 3` created sequentially.
**When** SELECT * FROM audit_signing_batches ORDER BY batch_seq.
**Then** batch_seq=1 has `previous_batch_hash=NULL` (genesis).
**And** batch_seq=2 has `previous_batch_hash = batch_seq=1.batch_hash`.
**And** batch_seq=3 has `previous_batch_hash = batch_seq=2.batch_hash`.
**And** FK constraint `previous_batch_hash REFERENCES audit_signing_batches(batch_hash)` enforced (verify: attempt INSERT batch_seq=4 with random previous_batch_hash → 23503 FK violation).

#### Scenario 9.6.2 — Break chain → verifier detects

**Given** batches 1..10 валидно chained.
**When** attacker (simulated) UPDATE audit_signing_batches SET batch_hash='tampered' WHERE batch_seq=5 (bypassing app-layer — direct SQL).
**And** Verifier daily run executes.
**Then** verifier обнаруживает: batch_seq=6 has `previous_batch_hash` ≠ batch_seq=5.batch_hash.
**And** verifier UPDATE audit_signing_batches SET verifier_status='verified_broken' WHERE batch_seq IN (5, 6).
**And** PagerDuty P0 incident fired с `incident_key=audit-tamper-batch-5`.
**And** Slack message в #security-critical с batch_id + tampered fields.

#### Scenario 9.6.3 — Missing batch → verifier alerts

**Given** batches `batch_seq=1, 2, 4, 5` (skipped 3 — simulating attacker delete).
**When** Verifier run.
**Then** verifier detects gap: `batch_seq=4.previous_batch_hash` references batch_hash that doesn't exist в DB (FK уже catches это — INSERT would 23503, но direct DELETE bypass'ит FK validation для existing batch_seq=4).

> **Important**: Phase 1 миграция `0013` создаёт FK `previous_batch_hash REFERENCES audit_signing_batches(batch_hash) ON DELETE RESTRICT`. Поэтому attacker DELETE WHERE batch_seq=3 — fails (RESTRICT blocks because batch_seq=4 references it).

**And** even если attacker bypasses FK (e.g., via TRUNCATE CASCADE or direct file edit), verifier independent walk detects missing seq:
```sql
SELECT batch_seq, lag(batch_seq) OVER (ORDER BY batch_seq) AS prev
FROM audit_signing_batches
WHERE batch_seq - lag(batch_seq) OVER (ORDER BY batch_seq) != 1;
```
Returns row(s) — verifier alerts PagerDuty P0.

#### Scenario 9.6.4 — Signature mismatch → verifier alerts

**Given** batch row valid, но signature bytea modified directly via SQL UPDATE.
**When** Verifier run.
**Then** `hsm.Verify(data, mutated_signature, kid)` returns `verification failed`.
**And** verifier UPDATE `verifier_status='verified_broken'`, fires PagerDuty P0.
**And** `audit_verifier_runs.anomalies_found++`.

#### Scenario 9.6.5 — Verifier walks ALL batches (not just new ones)

**Given** 1000 batches in DB (~3.5 days of 5-min batches).
**When** Verifier runs.
**Then** verifier walks all 1000 (not only those с `verifier_status='not_verified'`).
**And** runtime budget ≤ 15 minutes (1000 × 50ms HSM verify + 1000 × 5ms DB read).
**And** `audit_verifier_runs.batches_walked=1000`.

---

### 6.7 Independent verifier service

#### Scenario 9.7.1 — Daily CronJob runs at 02:00 UTC

**Given** K8s CronJob `audit-verifier` with schedule `0 2 * * *`, timezone UTC.
**When** wall clock reaches 02:00:00.
**Then** K8s creates Job; pod startup.
**And** pod completes (exit code 0) typically within 15min.
**And** new row in `audit_verifier_runs`: `(run_id, run_started_at, run_ended_at, batches_walked, anomalies_found=0, status='success')`.

#### Scenario 9.7.2 — Verifier with HSM read-only credentials

**Given** verifier pod mounted PKCS#11 config with HSM user role `verify-only` (no Sign permission).
**When** verifier attempts `hsm.Sign(...)` (simulating compromised verifier).
**Then** PKCS#11 returns `CKR_USER_NOT_LOGGED_IN` or `CKR_KEY_FUNCTION_NOT_PERMITTED`.
**And** test asserts verifier code НЕ contains Sign() calls (static-analysis check).

#### Scenario 9.7.3 — Verifier detects tampering and alerts via PagerDuty

**Given** test setup includes tampered batch (Scenario 9.6.2).
**When** verifier Run().
**Then** PagerDuty API mock receives `POST /incidents` с:
- `service_key = <kacho-audit-tamper-service>`
- `event_action = trigger`
- `severity = critical`
- `summary = "Audit log tampering detected: batch bat_<id>"`
- `dedup_key = audit-tamper-batch-<seq>`.

**And** Slack webhook mock receives `POST <slack-url>` с message в #security-critical.
**And** email mock receives email к security@kacho.cloud.

#### Scenario 9.7.4 — Verifier idempotency: repeat run без новых alerts

**Given** tampering was already detected on day-1 verifier run (PD incident created, dedup_key set).
**When** day-2 verifier run finds same batch still tampered.
**Then** PD dedup_key matches → incident NOT re-fired (PD itself dedupes via dedup_key).
**And** `audit_verifier_runs.anomalies_found = 1` (still counts the issue).
**And** verifier logs "tamper still present, alert suppressed via dedup_key".

---

### 6.8 SIEM webhook delivery

#### Scenario 9.8.1 — Per-tenant subscription (account_admin creates Datadog subscriber)

**Given** account_admin authenticated с tenant `acc_xxx`.
**When** RPC `InternalSIEMService.CreateSubscriber`:
```json
{
  "account_id": "acc_xxx",
  "provider": "DATADOG_HEC",
  "endpoint_url": "https://http-intake.logs.datadoghq.com/api/v2/logs",
  "secret_ref": "k8s://kacho-iam-secrets/datadog-acc-xxx-api-key",
  "event_types": ["iam.access_binding.created", "iam.access_binding.deleted", "iam.session.failed_signin"],
  "enabled": true
}
```
**Then** Response: `SIEMSubscriber{id="sub_01h...", account_id="acc_xxx", ...}`.
**And** Postgres row in `siem_subscribers` table.
**And** kacho-iam SIEM forwarder spawns new goroutine + consumer group `kacho-audit-siem-sub_01h...`.

#### Scenario 9.8.2 — Datadog HEC delivery

**Given** subscriber `sub_dd_01` provider=`DATADOG_HEC`; httptest mock на `endpoint_url`.
**And** Kafka topic has 100 events matching `event_types` filter.
**When** SIEM forwarder reads events, builds Datadog payload.
**Then** mock receives `POST /api/v2/logs` с:
- Header `DD-API-KEY: <token from secret_ref>`.
- Body: JSON array of CADF events (max 1000 per request or 5MB).

**And** mock returns 202 Accepted.
**And** forwarder marks Kafka offset committed (no event_outbox-style table; per Kafka offset).
**And** `siem_subscribers.last_success_at = now()`.

#### Scenario 9.8.3 — Splunk HEC delivery

**Given** subscriber `sub_sp_01` provider=`SPLUNK_HEC`.
**When** events delivered.
**Then** mock receives POST с `Authorization: Splunk <token>` header.
**And** body lines: `{"event": <CADF>, "sourcetype":"kacho:iam:audit"}\n{"event":...}\n...`.

#### Scenario 9.8.4 — Elastic _bulk delivery

**Given** subscriber `sub_el_01` provider=`ELASTIC_BULK`.
**When** events delivered.
**Then** mock receives `POST /_bulk` с alternating index header / event lines.
**And** Authorization header `Bearer <token>`.

#### Scenario 9.8.5 — Generic webhook with signed JWT bearer

**Given** subscriber `sub_gw_01` provider=`GENERIC_WEBHOOK`, `expected_audience="https://customer.example.com/siem"`.
**When** events delivered.
**Then** mock receives POST с `Authorization: Bearer <JWT>`.
**And** JWT decoded — claims:
- `iss="https://iam.kacho.cloud"`
- `aud="https://customer.example.com/siem"`
- `exp = iat + 300s`
- `jti = ULID`
- `kacho.subscriber_id = "sub_gw_01"`
- `kacho.event_count = <n>`.

**And** JWT signature verifies против kacho-iam JWKS endpoint (kid `audit-signer-v1`).

#### Scenario 9.8.6 — Subscriber 4xx failure_count++ → auto-disable at 5

**Given** subscriber `sub_fail_01`, `failure_count=4`.
**And** httptest mock returns 401 Unauthorized.
**When** forwarder POST fails.
**Then** Postgres atomic CAS UPDATE:
```sql
UPDATE siem_subscribers
   SET failure_count = failure_count + 1,
       last_failure_at = now(),
       last_failure_reason = '401: Unauthorized',
       enabled = CASE WHEN failure_count + 1 >= 5 THEN false ELSE enabled END
 WHERE id = 'sub_fail_01'
RETURNING failure_count, enabled;
```

Result: `failure_count=5, enabled=false`.
**And** Slack notification sent to tenant admin (`SubscriberDisabled` event).
**And** consumer group for `sub_fail_01` stops gracefully (offset retained for re-enable).

#### Scenario 9.8.7 — Subscriber 5xx → exponential backoff retry

**Given** subscriber receives 503 Service Unavailable.
**When** forwarder retries.
**Then** retry schedule applied: 1s, 5s, 30s, 5min, 1h, 6h, 24h (7 attempts).
**And** events NOT marked delivered until success or terminal failure.
**And** Kafka consumer.commit() NOT called (events remain replay-able).

---

### 6.9 Detection rules library

#### Scenario 9.9.1 — Rule 1: brute force (>10 failed signins / IP / 5min)

**Given** ClickHouse + Datadog SIEM with Phase 9 detection rules deployed.
**And** 11 events `event_type='iam.session.failed_signin'` from `actor.ip=10.0.0.5` within 4min window.
**When** Datadog Workflow `kacho-rule-brute-force` evaluates.
**Then** rule fires; PagerDuty P2 incident `audit-brute-force-10.0.0.5`.
**And** Cloudflare WAF rule auto-added to block IP for 1h (via Datadog → CF integration).
**And** Datadog Security Signal logged.

> **Implementation note**: Detection rules deployed as code (Terraform для Datadog Workflows, SPL для Splunk, Watcher для Elastic). kacho-deploy ships rule templates; tenant admin может customise thresholds.

#### Scenario 9.9.2 — Rule 2: impossible travel (2 countries within 2h)

**Given** events:
- `evt_a`: `actor.id=usr_bob`, `actor.ip=192.0.2.1` (US), timestamp `t`.
- `evt_b`: `actor.id=usr_bob`, `actor.ip=203.0.113.5` (Russia), timestamp `t + 90min`.

GeoIP service returns countries US / RU respectively.
**When** rule `kacho-rule-impossible-travel` evaluates.
**Then** rule fires; PagerDuty P3.
**And** kacho-iam receives CAEP signal `session.revoke` for usr_bob (via CAEP receiver Phase 12 — for now, manual workflow).
**And** next signin для usr_bob requires step-up MFA acr=3.

#### Scenario 9.9.3 — Rule 3: mass deletion (>100 deletes / principal / 5min)

**Given** 101 events `event_type LIKE '%.deleted'`, same `actor.id=usr_evil`, within 4min.
**When** rule evaluates.
**Then** PagerDuty P1 (Critical); auto-revoke session via CAEP; Slack #security-critical.
**And** `usr_evil` session blocked.

#### Scenario 9.9.4 — Rule 4: out-of-hours admin

**Given** tenant config: `business_hours={"timezone":"Europe/Berlin","start":"09:00","end":"18:00","days":["MON","TUE","WED","THU","FRI"]}`.
**And** event with `actor.role=admin`, `timestamp=2026-05-19T03:00:00Z` (5am Berlin, Tue night-into-Wed — outside hours).
**When** rule evaluates.
**Then** Medium severity signal; Slack notification (no auto-revoke); event added to weekly review queue.

#### Scenario 9.9.5 — Rule 5: privilege escalation (SA creates role > SA scope)

**Given** ServiceAccount `sa_p9_test` имеет scope=Project `prj_x`.
**And** event `iam.role.created` actor=`sa_p9_test`, target role `permissions=["iam.account.admin"]` (account-scope перейдён).
**When** rule evaluates.
**Then** PagerDuty P1 Critical.
**And** auto-revoke binding (delete created role).
**And** Slack #security-critical с full event payload.

#### Scenario 9.9.6 — Rule 6: audit signature verification failure (P0)

> Already covered in Scenario 9.7.3 — verifier service detects + alerts; no separate SIEM rule needed (verifier is authoritative).

#### Scenario 9.9.7 — Rule 7: break-glass usage (P1 Critical)

**Given** Phase 7 break-glass grant ACTIVE (Phase 7 doc §6.5).
**And** event `event_type='iam.break_glass.activated'` или `actor.acr=4`.
**When** rule fires.
**Then** PagerDuty P1.
**And** Slack #security-alerts.
**And** email security@kacho.cloud.

#### Scenario 9.9.8 — Rule 8: FGA tuple drift

**Given** FGA tuple reconciler (Phase 3) runs hourly.
**And** reconciler finds `access_bindings.status=ACTIVE` row WITHOUT corresponding OpenFGA tuple.
**When** reconciler emits event `iam.fga.tuple_drift_detected`.
**Then** SIEM rule fires; Medium severity.
**And** reconciler auto-repairs (re-writes tuple).
**And** Slack notification with details.

---

### 6.10 Drainer recovery & resilience

#### Scenario 9.10.1 — Drainer pod restart → resume from last_processed offset

**Given** drainer pod 1 has heartbeat `audit_drainer_state.last_seen_event_id='evt_p9_500'`.
**When** pod 1 killed; pod 2 starts.
**Then** pod 2 reads own previous row from `audit_drainer_state` (matches `drainer_id`).
**And** continues with `FOR UPDATE SKIP LOCKED WHERE id > 'evt_p9_500' AND status='pending'`.
**And** all subsequent events processed without loss.

#### Scenario 9.10.2 — No event loss during rolling restart

**Given** 3 drainer pods, ongoing throughput 1000 events/sec.
**When** K8s rolling update: pod 1 terminated → new pod 1' starts → pod 2 terminated → ... .
**Then** zero events with `status='pending' AND created_at < (rollout_start - 60s) AND delivered_at IS NULL` after rollout completes.
**And** Kafka topic event count = expected total.
**And** zero duplicate event_ids.

#### Scenario 9.10.3 — Drainer state cleanup on terminated pod

**Given** old drainer pod terminated 60min ago; row in `audit_drainer_state` with stale `last_heartbeat_at`.
**When** garbage collector cron runs (every 5min).
**Then** stale rows deleted (older than 30min).
**And** `audit_drainer_state` size bounded (≤ N alive pods).

#### Scenario 9.10.4 — Heartbeat metric exposed for Grafana

**Given** Prometheus metrics endpoint `:9100/metrics` на drainer pod.
**When** scraping.
**Then** metric `kacho_audit_drainer_last_heartbeat_seconds{drainer_id="..."}` shows seconds since last heartbeat.
**And** metric `kacho_audit_drainer_lag_events` shows count of `audit_outbox WHERE status='pending'`.

---

### 6.11 Per-tenant topic isolation

#### Scenario 9.11.1 — High-volume tenant gets dedicated topic

**Given** tenant `acc_high_xxx` подаёт RPC `InternalAdminAuditService.PromoteTenantTopic` (cluster-admin).
**When** RPC processed.
**Then** Kafka topic `kacho-audit-events.tenant.acc_high_xxx` created via Strimzi `KafkaTopic` CRD (16 partitions, RF=3, zstd, 7d retention).
**And** drainer reads `siem_subscribers.tenant_topic` mapping и routes events for `tenant_account_id='acc_high_xxx'` to dedicated topic.
**And** standard tenants continue using shared topic.

#### Scenario 9.11.2 — Standard tenant uses shared topic

**Given** tenant `acc_low_xxx` без promotion.
**When** events from this tenant produced.
**Then** all events appear in `kacho-audit-events.shared`.
**And** partition selected via `hash(tenant_account_id) % 64`.

#### Scenario 9.11.3 — Demotion from dedicated → shared (cleanup)

**Given** dedicated topic existed; admin decides to demote (tenant left high-volume tier).
**When** RPC `DemoteTenantTopic`.
**Then** drainer config updated; new events routed to shared.
**And** dedicated topic retained 7d (existing events drainable до retention TTL).
**And** after 7d Strimzi `KafkaTopic` CRD deleted; broker storage reclaimed.

---

### 6.12 Audit retention lifecycle (S3 → Glacier → delete 10y)

#### Scenario 9.12.1 — Standard 30d → Standard-IA transition

**Given** S3 object uploaded 31d ago.
**When** S3 lifecycle scheduler runs.
**Then** `aws s3api head-object --bucket kacho-audit-cold --key <key>` returns `StorageClass=STANDARD_IA`.

#### Scenario 9.12.2 — Standard-IA 1y → Glacier Deep Archive transition

**Given** S3 object uploaded 366d ago, currently `STANDARD_IA`.
**When** lifecycle runs.
**Then** `StorageClass=DEEP_ARCHIVE`.

#### Scenario 9.12.3 — Glacier 10y → permanent delete

**Given** S3 object uploaded 10y + 1d ago.
**When** lifecycle runs.
**Then** object deleted.
**And** `audit_signing_batches` row retained (Postgres) — verifier walks chain only до earliest extant batch.
**And** `verifier_status='retired'` set automatically by lifecycle housekeeper job.

#### Scenario 9.12.4 — Glacier retrieval via RestoreObject (Bulk tier acceptance)

**Given** S3 object in `DEEP_ARCHIVE`, forensic incident requires.
**When** ops-team executes `aws s3api restore-object --bucket ... --key ... --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'`.
**Then** restoration begins; ETA 48h (Bulk tier).
**And** after restore — object accessible как `STANDARD` for 7 days, then reverts.
**And** verifier dry-run script может re-verify integrity through Glacier-restored objects.

---

### 6.13 SIEM admin RPC (Internal)

#### Scenario 9.13.1 — Subscriber CRUD happy path (account_admin)

**Given** authenticated account_admin `usr_admin@acc_xxx`.
**When** RPC sequence:
- `CreateSubscriber(account_id="acc_xxx", provider=DATADOG_HEC, ...)` → returns `sub_id_1`.
- `GetSubscriber(id="sub_id_1")` → returns row.
- `ListSubscribers(account_id="acc_xxx")` → returns 1 row.
- `UpdateSubscriber(id="sub_id_1", event_types=[...changed])` → returns updated row.
- `DeleteSubscriber(id="sub_id_1")` → returns Empty.

**Then** все RPCs success.
**And** соответствующие Postgres state correct в каждой stage.
**And** consumer group для удалённого subscriber stopped + Kafka offsets deleted (cleanup).

#### Scenario 9.13.2 — Subscriber CRUD by non-admin → PermissionDenied

**Given** authenticated user без `iam.siem.admin` permission.
**When** `CreateSubscriber`.
**Then** gRPC `PermissionDenied: caller lacks 'iam.siem.admin' permission on account acc_xxx`.

#### Scenario 9.13.3 — TestDelivery RPC sends synthetic event

**Given** subscriber `sub_test_01` configured.
**And** httptest mock на endpoint_url.
**When** RPC `TestDelivery(subscriber_id="sub_test_01")`.
**Then** synthetic event `event_type='kacho.test.synthetic'`, `event_id='evt_test_<ulid>'` sent immediately (not via Kafka, direct call).
**And** mock receives event with `metadata.synthetic=true` flag.
**And** RPC returns `TestDeliveryResult{success=true, latency_ms=<n>, response_code=202}`.

#### Scenario 9.13.4 — Subscriber secret_ref rotation

**Given** subscriber's K8s secret `datadog-acc-xxx-api-key` updated с new value.
**When** forwarder next poll-cycle (every 60s reads secret).
**Then** new value picked up, subsequent posts use new API key.
**And** old value no longer leaks (compare expected header with both old и new — only new used).

#### Scenario 9.13.5 — Subscriber Internal RPC NOT exposed on public TLS endpoint (запрет #6)

**Given** api-gateway has internal mux (port 9091) и public TLS mux (api.kacho.local:443).
**When** external client (без internal access) calls `POST https://api.kacho.local:443/iam/v1/siemSubscribers`.
**Then** HTTP 404 (route not registered on public mux).
**And** access via `https://<internal-lb>:9091/iam/v1/siemSubscribers` works (with admin auth).

---

### 6.14 Grafana visibility & metrics

#### Scenario 9.14.1 — Audit pipeline overview dashboard exposes 6 key metrics

**Given** kacho-deploy provisions Grafana с dashboard `audit-pipeline-overview`.
**When** user opens dashboard.
**Then** panels present:
1. **Queue depth** — `kacho_audit_outbox_pending_count` gauge (gauge from Postgres exporter).
2. **Drainer lag** — histogram of `(now() - audit_outbox.created_at)` for pending rows.
3. **Throughput per topic** — `rate(kacho_kafka_produce_total[5m])` per topic.
4. **ClickHouse ingestion rate** — `rate(clickhouse_inserts_total[5m])` per shard.
5. **S3 batch write rate** — `rate(kacho_audit_s3_writes_total[5m])` + p99 latency.
6. **SIEM forwarder rate** — `rate(kacho_audit_siem_deliveries_total[5m])` per subscriber.

#### Scenario 9.14.2 — Detection rules dashboard shows fire-rate per rule

**Given** dashboard `audit-detection-rules`.
**When** opens.
**Then** time series chart `rate(kacho_audit_detection_rule_fires_total{rule_id}[1h])` for all 8 rules.
**And** top-tenants-by-rule-hits bar chart.

#### Scenario 9.14.3 — Integrity dashboard shows verifier status

**Given** dashboard `audit-integrity`.
**When** opens.
**Then** panel: latest verifier run status (success/failed); batches walked; anomalies found.
**And** time series: HSM call latency p50/p95/p99.
**And** chain break count (should always be 0).

---

### 6.15 GDPR retention compliance

#### Scenario 9.15.1 — Erased user PII pseudonymized в Kafka producer side

**Given** user `usr_erased_01` requested GDPR erasure (Phase 7 cool-off 30d completed).
**And** `users.status='ERASED'`, `users.email='gdpr-erased-<hash>@deleted.invalid'`.
**When** post-erasure event generated с `actor.id='usr_erased_01'` (e.g., delayed job using old token).
**Then** drainer reads `users.status='ERASED'` mirror cache.
**And** event pseudonymized:
- `actor.email = 'gdpr-erased-<hash>@deleted.invalid'`
- `actor.ip = null`
- `payload.diff.before` / `payload.diff.after` — PII fields (`name`, `email`, `phone`) replaced with `null`.

**And** pseudonymized event sent to Kafka.

#### Scenario 9.15.2 — Pre-erasure events retained 7y (compliance > erasure)

**Given** user erased today; old events in audit_outbox / Kafka / ClickHouse / S3 from before erasure date.
**When** user invokes "delete all my audit data".
**Then** request rejected per GDPR Art. 17(3)(b) (legal claims defence).
**And** vault `KAC-127.md` references compliance map (design §9.4 — SOC 2 / ISO 27001 / GDPR Art. 17(3)(b)).
**And** UI shows tenant admin: "Audit retention 7 years per regulatory requirements; pre-erasure events anonymized post-erasure when accessed."

#### Scenario 9.15.3 — Audit event for erasure request itself

**Given** GDPR erasure pipeline completes for `usr_erased_01`.
**When** Phase 7 erasure handler completes.
**Then** event `event_type='iam.user.erased'`, actor=`usr_erased_01`, target=`usr_erased_01` (the user erasing themselves).
**And** этот event сам по себе содержит pre-erasure metadata (email, account_id) — compliance audit trail of when erasure happened.
**And** event retained 7y (never pseudonymized — pseudo would defeat audit purpose).

---

## 7. Definition of Done (Phase 9)

**Code & infrastructure:**
- [ ] Migrations `0021_kac127_siem_subscribers.sql`, `0022_kac127_audit_drainer_state.sql`, `0023_kac127_audit_verifier_runs.sql` applied; integration test on testcontainer Postgres зелёный.
- [ ] kacho-corelib `audit/` package: 100% test coverage of `Sign/Verify/Merkle/Pseudonymize`; SoftHSM-based tests in CI.
- [ ] kacho-iam workers (`drainer.go`, `s3writer.go`, `verifier.go`, `siem_forwarder.go`) implemented; unit + integration зелёные.
- [ ] Strimzi Kafka Operator deployed в kacho-deploy; 3 brokers up; KRaft mode; topics auto-create via CRD.
- [ ] Altinity ClickHouse Operator deployed; 2x2 cluster; `audit_events_local` Replicated MergeTree + Distributed `audit_events`; ingestion verified.
- [ ] S3 bucket `kacho-audit-cold` provisioned via Terraform; lifecycle policy (30d → 1y IA → 10y Glacier → delete) applied.
- [ ] AWS CloudHSM cluster provisioned (production); SoftHSM dev fallback в kacho-deploy `dev-up`.
- [ ] PKCS#11 ECDSA P-384 key `hsm-audit-v1` generated; first batch signed end-to-end.
- [ ] Audit verifier CronJob deployed; daily run scheduled; first successful run logged.
- [ ] kacho-api-gateway `InternalSIEMService` registered on internal mux only (port 9091); NOT on public TLS endpoint (запрет #6).

**Tests:**
- [ ] Integration tests зелёные (testcontainers Postgres + Kafka + MinIO + SoftHSM): drainer concurrent SKIP LOCKED; S3 batch HSM sign roundtrip; verifier tamper detection.
- [ ] End-to-end test (kacho-deploy `make e2e-test-phase-9`): mutation in kacho-iam → audit_outbox → Kafka → ClickHouse (queryable within 60s) + S3 (object + manifest present + HSM-signed) + SIEM webhook (httptest receiver verifies).
- [ ] Newman cases `9.x_audit_pipeline.py` zелёный: SIEM CRUD; TestDelivery; subscriber 4xx auto-disable; subscriber 5xx exp backoff.
- [ ] Chaos test (manual): kill 1 of 3 Kafka brokers — audit pipeline продолжает работать, no event loss.
- [ ] Chaos test (manual): kill HSM connection — S3 writer pauses gracefully, PagerDuty Critical fires, recovers on HSM restore.

**Documentation & vault:**
- [ ] APPROVED от `acceptance-reviewer` на этот doc.
- [ ] Vault updated: `KAC/KAC-127.md` (Phase 9 PR-список), `resources/iam-siem-subscriber.md`, `packages/iam-audit.md`, `edges/iam-to-kafka-audit-pipeline.md`, `edges/iam-to-clickhouse-audit-storage.md`, `edges/iam-to-s3-audit-cold-storage.md`, `edges/iam-to-hsm-pkcs11-signing.md`, `edges/iam-to-siem-webhook-delivery.md`, `rpc/iam-internal-siem-service.md`.
- [ ] Runbook: `docs/runbooks/audit-tamper-detected.md` (PagerDuty P0 response).
- [ ] Runbook: `docs/runbooks/audit-hsm-unavailable.md` (PagerDuty Critical response).
- [ ] Runbook: `docs/runbooks/audit-siem-disable.md` (subscriber auto-disabled response).

**YouTrack:**
- [ ] All Phase 9 subtasks (tasks 9.1–9.12) closed in YouTrack KAC-127 epic.
- [ ] Each subtask comment'ом приложил PR-link(s).

**Compliance:**
- [ ] Compliance map (design §9.4) обновлён в `docs/compliance/soc2-iso27001-fedramp-gdpr-map.md` с pointer'ами на Phase 9 PR / runbooks.

---

## 8. Cross-repo PR-chain

| Order | Repo | Branch | Title | Depends on |
|---|---|---|---|---|
| 1 | `kacho-proto` | KAC-127 | `[KAC-127] feat(iam): add InternalSIEMService proto + gen` | — |
| 2 | `kacho-corelib` | KAC-127 | `[KAC-127] feat(audit): add CADF event, HSM signer (PKCS#11), Merkle tree, pseudonymize` | PR #1 |
| 3 | `kacho-iam` | KAC-127 | `[KAC-127] feat(audit): drainer, s3writer, verifier, siem_forwarder + migrations 0021..0023` | PR #1, #2 |
| 4 | `kacho-deploy` | KAC-127 | `[KAC-127] feat(audit): Strimzi Kafka + Altinity ClickHouse + S3+Glacier + CloudHSM + CronJob verifier + Grafana dashboards` | PR #3 |
| 5 | `kacho-api-gateway` | KAC-127 | `[KAC-127] feat(audit): register InternalSIEMService on internal mux` | PR #1, #3 |
| 6 | `kacho-workspace` | KAC-127 | `[KAC-127] docs(audit): Phase 9 acceptance + vault + runbooks + compliance map` | PR #2..#5 |

Каждый PR имеет `Closes KAC-127` либо `Relates to KAC-127`; subtasks для Phase 9 (9.2..9.12) ссылаются на конкретный PR.

---

## 9. Out of scope (Phase 10+)

| Что | Где |
|---|---|
| SPIFFE-issued mTLS certs для Kafka brokers / ClickHouse / HSM client / SIEM webhook clients | **Phase 10** — `sub-phase-3.10-iam-spiffe-mesh-acceptance.md` |
| Multi-region MirrorMaker (cross-region Kafka replication для audit-events) | **Phase 11** — `sub-phase-3.11-iam-multi-region-acceptance.md` |
| CAEP push pipeline production (kacho-iam → tenant CAEP receiver с SET JWT signing) | **Phase 12** — `sub-phase-3.12-iam-caep-production-acceptance.md` (Phase 8 строит каркас) |
| ClickHouse downsampling / aggregation для long-term low-cardinality summaries | Phase 11+ optimization (not blocker for compliance) |
| Audit-event schema versioning (future migrations of CADF schema) | Phase 11+ (forward-compat plan documented in Phase 9 §2.3 but no migration tooling) |
| WORM-mode S3 (Object Lock + Compliance retention period) — текущая ID-based tamper-evidence enough for SOC2; WORM nice-to-have для FedRAMP High | Phase 11+ |
| Cross-tenant analytic queries (admin overview) | Phase 11+ (privacy-impacting; needs separate consent design) |

---

## 10. Open Questions — resolved

### Q1: Why Kafka (запрет #7 says no broker)?

**Resolution (D-18):** Design explicitly grants exception for audit pipeline because:
- In-process LISTEN/NOTIFY доказал свою недостаточность для downstream multi-fan-out (ClickHouse + S3 + N SIEM-subscribers одновременно требуют independent retry/offset/buffering).
- 7-day Kafka retention — primary buffer for slow consumer recovery (S3 outage / SIEM endpoint down).
- Industry standard for audit pipelines (Cloudflare, Stripe, GitHub, GitLab use Kafka).
- Запрет #7 — про **«пока in-process справляется»**. Здесь в-process **не** справляется → broker уместен.

**This single exception** does NOT open the door to broker introduction в других подсистемах (compute, vpc, nlb) — see запрет #7 wording.

### Q2: Why ClickHouse vs Postgres TSDB / TimescaleDB / Elasticsearch?

**Resolution:** 
- **TimescaleDB** — PG-based, OK для time-series, но column-store + compression worse than CH; per-tenant partition overhead; nyc-shaped product offering.
- **Elasticsearch** — index size 4-5× CH for same data; license restrictions; auditor-friendliness lower.
- **ClickHouse** — purpose-built OLAP; 10:1 compression ratio typical for JSON audit; query patterns (full-table-scan + tenant filter) match exactly CH strengths.
- Altinity Operator — proven production K8s deploy.

### Q3: Why ECDSA P-384, not Ed25519 / RSA-4096?

**Resolution:**
- **RSA-4096** — signature size (512B vs 96B for ECDSA-P384) blows up S3 manifest storage cost over 10y × 10M batches.
- **Ed25519** — not yet FIPS 140-2 approved (only 140-3, not всё ещё ratified universally в 2026).
- **ECDSA P-384** — FIPS 140-2 Level 3 approved, supported by AWS CloudHSM / GCP Cloud HSM / Azure HSM / Luna; 192-bit security level (vs 128 for P-256) — safer для 10y retention horizon under quantum-threat speculation.

### Q4: Why daily verifier, not realtime?

**Resolution:**
- Verifier needs to walk ALL batches (incremental only walks new — misses post-hoc tamper).
- Full walk costs ~15min (10k batches × HSM verify). Realtime impractical.
- 24h max-detection-window — accepted by SOC2 (anomaly detection не требует sub-second SLA).
- Если organization wants faster — add hourly hot-spot check on N latest batches (config option, default off).

### Q5: HSM cost — $1.5/hour × 24/7 = ~$13k/year/HSM. Acceptable?

**Resolution:**
- Production HSM cluster 2 instances HA = ~$26k/year.
- Cost of audit-compromise (SOC2 violation, breach disclosure, lost contracts) >> $26k.
- Industry-standard for compliance-sensitive workloads.
- Dev/CI cost zero (SoftHSM).

### Q6: SIEM subscriber proliferation — what if a tenant adds 100 subscribers?

**Resolution:**
- Per-account limit `max_siem_subscribers=10` (configurable; default sane).
- Beyond limit → InvalidArgument при Create.
- Operational cost (consumer group memory) bounded.

### Q7: GDPR — can we erase audit events on user request?

**Resolution:** **No** per GDPR Article 17(3)(b) — audit retention for legal claims defence is a legitimate interest, overrides erasure right.
- Pre-erasure events retained 7y, NOT pseudonymized post-erasure (would defeat audit integrity — actor identity in audit is the evidence).
- Post-erasure events (rare — delayed jobs, etc.) ARE pseudonymized in drainer (P9-D29).
- UI clearly communicates: "Audit retention 7y per regulatory requirements."

### Q8: What if HSM key compromise?

**Resolution:**
- Rotate via P9-D28 (7d dual-sign window).
- Verifier alert if signature mismatch (compromised key would still sign valid manifests, BUT verifier walks old batches with old key — past forgery detectable through chain break IF attacker tries to alter past).
- Subsequent batches sign with new key — chain continues.
- Worst case: 7d window during which forgery could happen — accepted risk (HSM compromise itself = P0 corp incident; audit pipeline integrity is one of many concerns).

### Q9: ClickHouse storage cost — 90d × 100M events/day × 1KB?

**Resolution:**
- 90d × 100M events × 1KB = 9TB raw.
- ClickHouse 10:1 compression → 900GB hot storage.
- 2 shards × 2 replicas = 4 copies = 3.6TB.
- AWS gp3 EBS 3.6TB = ~$300/mo. Acceptable.

### Q10: What about tenant queryability of own audit events?

**Resolution:** **Phase 11** (out of scope here). For Phase 9, audit events queryable only via:
- Tenant SIEM (subscriber subscribed).
- Admin support workflow (audit-restore via internal tool).
- No direct tenant API to ClickHouse / S3.

---

## 11. Acceptance review checklist (для `acceptance-reviewer`)

При review этого документа `acceptance-reviewer` ОБЯЗАН проверить:

- [ ] **Coverage** — все 12 plan-tasks (9.1..9.12) представлены в §5 декомпозиции + §6 сценариях.
- [ ] **Completeness** — каждая critical path имеет happy + negative scenario.
- [ ] **Traceability** — каждый GWT scenario ссылается на конкретное design-D# / план-task #.
- [ ] **Scope** — out-of-scope §9 — clear and complete.
- [ ] **Compliance** — запреты #1..#11 проверены, all применимые pojaśnione.
- [ ] **Cross-repo PR-chain** — порядок соответствует build-graph (proto → corelib → service → deploy → gateway → docs).
- [ ] **Vault entries** plan'нируются для каждого нового resource / package / edge / rpc.
- [ ] **Tests-in-PR commitment** — integration + newman per запрет #11.
- [ ] **DoD** — measurable, actionable, no vague "should work".
- [ ] **Naming** — "kacho-*" / `kacho.cloud.iam.v1` consistent; никакого "yandex" (запрет #2).
- [ ] **Internal vs public** — admin RPC на internal mux (запрет #6); инфра-чувствительные данные не leak'нут.
- [ ] **Within-service DB-level invariants** — `audit_signing_batches` chain enforced via FK; `siem_subscribers.failure_count++` via atomic CAS (запрет #10).
- [ ] **Operations-async contract** — admin RPC SIEM subscribers — sync OK (admin resource, not tenant resource).
- [ ] **GDPR pseudonymize** — pre-erasure retention 7y vs post-erasure pseudonymize рассмотрены.

---

**End of Phase 9 acceptance document.**

> После APPROVED `acceptance-reviewer` — статус документа меняется на APPROVED, можно стартовать `superpowers:writing-plans` → `integration-tester` (тесты по сценариям) → workers + handlers implementations (tasks 9.2–9.12).
