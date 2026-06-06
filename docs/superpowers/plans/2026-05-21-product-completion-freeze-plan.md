# Kachō — Product Completion & Freeze Plan

> **Назначение.** Полный перечень того, что нужно сделать, чтобы считать продукт
> **завершённым** («законсервированным»): всё, что может потребоваться — реализовано,
> всё работает, **каждый RPC покрыт newman-тестами** (happy + negative), весь CI зелёный.
>
> Это **full-scope** вариант (в отличие от lean-v1 в `2026-05-21-production-launch-plan.md`).
> «Законсервировать» = довести до feature-complete + полного тест-покрытия, затем
> перевести в режим maintenance-only.
>
> **Методология (обязательно):** CLAUDE.md §Запреты #11 — **test-first**. На каждый RPC
> сначала пишется падающий newman-кейс (RED), потом код (GREEN). Никакой RPC не считается
> готовым без своего newman-кейса.

---

## Часть 0 — Definition of «законсервировано»

Продукт считается завершённым, когда **одновременно**:
1. Нет ни одного stub / `Unimplemented` / disabled-by-config куска на surface.
2. Каждая находка ревью (55) — закрыта (fix) либо осознанно `wontfix` с обоснованием.
3. **Каждый публичный и Internal RPC каждого сервиса** имеет newman-кейс: ≥1 happy + ≥1 negative.
4. Все newman-сюиты генерируются `gen.py`, гоняются `run.sh`, зелёные в CI (`newman-e2e`).
5. Integration-тесты (testcontainers) на все DB-инварианты и authz-критичные пути.
6. Весь CI зелёный: build / lint / gosec / trivy / govulncheck / integration / newman-e2e.
7. Инфраструктура развёрнута и работает (OpenFGA, drainer, Postgres, gateway authz).
8. Документация (CLAUDE.md / vault / спеки) отражает фактическое состояние.

---

## Часть 1 — Полный inventory работ (всё незавершённое → завершить)

### Блок A — AuthZ-ядро (44 IAM-находки)

Детально — `2026-05-21-iam-authz-review-remediation-plan.md`, 5 чанков. **Все** должны быть закрыты:
- Chunk 1 — DB/FGA desync (#8/16/47/48/50/51/52).
- Chunk 2 — in-service authz + identity-spoofing (#9/12/13/35/36/37/39/43/53).
- Chunk 3 — gateway wiring + единый permission-каталог (#19/28-34/38/44/45/49).
- Chunk 4 — spec-drift KAC-119/121 (#1/3/4/5/6/7/14/15/27/46/55).
- Chunk 5 — federation/SSO/authz internals (#20/21/23/25/26/40/41/42).

### Блок B — Enterprise-фичи: довести до рабочего состояния (НЕ descope)

Для full-scope каждая фича Phase 6-9 KAC-127 — реализована, подключена, работает:
- **B.1 SAML bridge** — ACS с проверкой подписи assertion (#40); wired `OnSAMLAssertion`; SP-init/IdP-init flow.
- **B.2 SCIM 2.0** — Basic-auth включён (#41); Users/Groups provisioning; маппинг.
- **B.3 JIT/PIM** — `ActivateJIT` proto-RPC (#32); auto/pending-approve пишут FGA-grant (#50/51); eligibility CRUD.
- **B.4 Break-glass** — 2-person approve пишет `cluster_admin_grants` + FGA (#52).
- **B.5 Access Reviews** — reviewer из principal (#35); recertification flow.
- **B.6 ComplianceReport** — authz + scope-provider (#37); report-generation.
- **B.7 GDPR erasure** — Article-17 pipeline.
- **B.8 CAEP push** — SET с проверкой подписи (#42); drainer + subscriber.
- **B.9 Audit pipeline** — (DECISION-AUDIT 2026-05-21) **VictoriaLogs + vector.dev**. Аудит-события пишутся в `audit_outbox` (Postgres, durable-гарантия) + структурным slog; `vector.dev`-агент (DaemonSet/sidecar) подхватывает и шлёт в **VictoriaLogs** (хранение + LogsQL-запрос). **Без** Kafka / ClickHouse / S3-ObjectLock / HSM / Merkle / SIEM-форвардеров — HSM-закупка больше не нужна.
- **B.10 SPIFFE/SPIRE + Cilium mesh** — ✅ **в скоупе** (DECISION-MESH 2026-05-21): SPIRE Server (HA) + SPIRE Agent (DaemonSet) + Cilium ServiceMesh + CiliumNetworkPolicy + mTLS по SPIFFE-SVID.

Каждая фича B.x: подключить к gateway (catalog + restmux + route-table), убрать stub-поведение, newman-покрытие.

### Блок C — Недостающие домены / RPC

- **C.1 `kacho-loadbalancer`** — ❌ **вне скоупа продукта** (DECISION-LB 2026-05-21). Домен NLB/TargetGroup НЕ строится. Ссылки убраны из `CLAUDE.md`; в vault/спеках/roadmap пометить «out of product scope». Это не пробел — осознанное решение.
- **C.2 Compute Internal admin** — `InternalInstance` / `InternalDisk` Lists — proto не существует, дописать. (`Hypervisor` из этого блока удалён в KAC-36/79/80 вместе с kube-ovn-эпохи data-plane-моделью.)

### Блок D — Инфраструктура authz

- D.1 OpenFGA развёрнут (HA) на всех целевых кластерах + bootstrap store/model.
- D.2 `fga_outbox` drainer построен (его нет — bootstrap-grant не применяется).
- D.3 authz-cache invalidation на revoke (`subject_change_outbox`).
- D.4 gateway authz-middleware включён, fail-closed.
- D.5 principal propagation сервис→сервис (`vpc#104`).
- D.6 OPA sidecar + подписанные bundle'ы.

### Блок E — Устранить заглушки

- `InternalIAM.ListPermissions` (#49) — реализовать.
- `RunRegoTest` (#26), `ReloadModel` (#25) — починить.
- Любой `codes.Unimplemented` / fake-ответ — найти grep'ом по всем сервисам, устранить.

### Блок F — API-токены (новая фича, реализовать)

**Текущее состояние:** `SAKeyService` покрывает только SA OAuth-клиентов (модель 5).
Статический long-lived **API-token** для программного доступа (модель 6 в
`authz-sa-apitoken.py`) — **не реализован**: на стенде он лишь симулируется
HS256-mint'ом JWT по `sub`. Реального ресурса/RPC/authn-пути нет.

Реализовать как полноценную фичу:

- **F.1 proto** — `ApiTokenService` (Create / Get / List / Revoke) + ресурс `ApiToken`
  (id-prefix `apt`, `subject_type`/`subject_id`, `name`, `scope`/`role_id`,
  `created_at`, `expires_at`, `last_used_at`, `status` PENDING/ACTIVE/REVOKED).
  Мутации → `operation.Operation`. Внутренний `InternalApiTokenService.Resolve`
  для authn-резолва на gateway (internal-port 9091, не на external).
- **F.2 domain + migration** — таблица `api_tokens` в `kacho_iam`; хранить **только
  hash** токена (argon2id / sha256), НИКОГДА не plaintext; FK на subject; partial-UNIQUE
  на hash; CHECK на `expires_at > created_at`; revoke — CAS-переход.
- **F.3 usecase** — `Create` генерирует токен `kat_<random-32+>`, возвращает plaintext
  **один раз** в `Operation.response` (паттерн SAKey one-shot secret), в БД — hash.
  `Revoke` — atomic CAS → REVOKED. `List`/`Get` — без секрета. `created_by` — из
  authenticated principal (не из тела — анти-spoofing, как #53).
- **F.4 authn (api-gateway)** — gateway принимает `Authorization: Bearer kat_…`,
  hash-резолв через `InternalApiTokenService.Resolve` → principal (user/SA) + scope;
  **expiry и revocation проверяются на КАЖДОМ запросе** — revoked/expired/unknown → 401
  `UNAUTHENTICATED` (не 403). Закрывает гэп из KAC-127 round-3 (revoked-token → должен быть 401).
- **F.5 authz scope** — **DECISION-APITOKEN:** токен (a) наследует все права subject'а,
  либо (b) несёт собственный ограниченный scope (role_id/permissions ⊆ subject). Рекомендация —
  (b) least-privilege: токен может быть уже прав subject'а, но не шире.
- **F.6 `last_used_at`** — обновлять throttled (для аудита/cleanup), не на каждый запрос.
- **F.7 lifecycle** — TTL-expiry worker (переводит просроченные в REVOKED); revoke всех
  токенов при удалении subject (FK CASCADE либо worker).
- **F.8 newman** — `ApiTokenService` Create/Get/List/Revoke happy+negative; authn-кейсы:
  valid→allow, revoked→401, expired→401, malformed→401. **Заменить симуляцию** в
  `authz-sa-apitoken.py` на реальный issue/revoke-flow.

---

## Часть 2 — Полное newman-покрытие (ядро «консервации»)

**Принцип:** каждый RPC каждого сервиса → newman-кейс (≥1 happy + ≥1 negative:
NotFound/FailedPrecondition/InvalidArgument/PermissionDenied по семантике). Плюс
authz-матрица (grant→allow / revoke→deny) на каждый authz-gated RPC.

### Шаг 2.0 — Починить newman-инфраструктуру

- Конвертировать **все** `tests/newman/cases/iam-*.py` из мёртвого `dict`-формата в
  `Case`/`Step` (сейчас `gen.py` SKIP'ает их — iam CRUD newman **никогда не гонялась**).
- Завести фикстуру-seed для CRUD-сюит (аналог `authz-fixtures/setup.sh`).
- Добавить все сюиты в `run.sh` (сейчас гоняются только `authz-deny`/`authz-sa-apitoken`).
- `newman-e2e.yml` гоняет полный набор, gate зелёный.

### Шаг 2.1 — Матрица покрытия (составить точный список из `kacho-proto`)

Для каждого сервиса — перечислить RPC из `.proto`, сверить с newman-кейсами, закрыть пробелы:

| Домен / сервис | RPC-группы | Текущее newman | Нужно |
|---|---|---|---|
| **IAM core** — Account/Project/User/ServiceAccount/Group/Role/AccessBinding | Create/Get/List/Update/Delete (+ Move, Invite, ListBy*) | `iam-*.py` — **мертвы** (dict) | конвертировать + happy/negative на каждый RPC |
| **IAM Operations** | Get/List/Cancel | частично | anonymous-deny, own/foreign |
| **IAM Internal** — InternalUser / InternalIAM | UpsertFromIdentity / Check / ListPermissions / LookupSubject | `iam-internal-only-check.py` | дополнить |
| **IAM AuthZ** — Authorize / InternalAuthorize / Conditions | Check/BatchCheck/ListObjects/ListSubjects/Expand / WriteTuples/ReadTuples/ReloadModel/RunRegoTest / Conditions CRUD+Evaluate | нет | написать |
| **IAM Federation** — FederationExchange / TrustPolicy / SAKey | Exchange / TrustPolicy CRUD / SAKey Issue/List/Revoke | `authz-sa-apitoken.py` частично | дополнить |
| **IAM API-токены** — ApiTokenService / InternalApiTokenService (Блок F) | Create/Get/List/Revoke / Resolve | нет (модель 6 симулируется) | написать + authn-кейсы valid/revoked/expired/malformed |
| **IAM Phase 7/7b** — JITEligibility / AccessReview / ComplianceReport / JitPending / GdprErasure / InternalBreakGlass | CRUD + Approve/Deny/Activate/Generate | `iam-jit-pending.py` / `iam-compliance-report.py` — dict (мертвы) | конвертировать + полное покрытие |
| **IAM SSO** — SCIM 2.0 / SAML SP | SCIM Users/Groups REST / SAML ACS | нет | написать (REST-уровень) |
| **IAM CAEP** — CAEPSubscriber / ingress | CRUD / SET-ingress | нет | написать |
| **VPC** — Network/Subnet/SecurityGroup/RouteTable/Address/Gateway/PrivateEndpoint/NetworkInterface (+ Internal*, AddressPool) | CRUD + domain-actions | частично (vpc newman в `kacho-vpc`) | аудит + закрыть пробелы |
| **Compute** — Instance/Disk/Image/Snapshot/Region/Zone/DiskType (+ Internal*) | CRUD + Start/Stop/Restart | частично | аудит + закрыть пробелы |
| **Geography** — Region/Zone | Get/List (+ Internal admin mutate) | частично | дополнить |

> Точный список RPC — извлечь скриптом из `kacho-proto/proto/**/*.proto` (`grep 'rpc '`),
> построить чек-лист «RPC → newman-case-id», добиться 100%.

### Шаг 2.2 — Классы кейсов на каждый RPC

- **happy** — успешный путь (mutation → Operation done → Get подтверждает).
- **negative** — NotFound / FailedPrecondition / InvalidArgument / AlreadyExists по семантике.
- **authz** — для authz-gated: grant→allow, revoke→deny, anonymous→deny, чужой scope→deny.
- **BVA/VAL** — границы полей (name/labels/description/pageSize), как в `gen.py` блоках.
- **idempotency** — где есть (AccessBinding.Create, UpsertFromIdentity).
- **security** — injection-пробы (есть `security_injection_block`).

### Шаг 2.3 — Authz-матрица (полная)

Расширить `authz-deny.py` / `authz-sa-apitoken.py`: каждый authz-gated RPC × 6 субъектов
(ANON/NOB/PA1/AAA/AAB/INV) + flow-кейсы grant→revoke (как `AUTHZ-REVOKE-ENFORCED`).

---

## Часть 3 — CI / верификация (всё зелёное)

- Build + `go vet` + unit — зелёные во всех репо.
- golangci-lint (strict), gosec (zero waivers), trivy/grype/govulncheck — zero High/Critical.
- Integration (testcontainers) — все DB-инварианты + concurrent-race.
- `newman-e2e` — полный набор сюит, gate падает на любом failed-assertion.
- k6 — базовые SLO (authz Check / List p95, sustained RPS).
- Кросс-репо: `buf lint` / `buf breaking` зелёные; sibling-ref'ы → `main`.

---

## Часть 4 — Freeze checklist (когда можно консервировать)

- [ ] 0 stub / `Unimplemented` / disabled-by-config на surface (grep подтверждает).
- [ ] Все 55 находок — закрыты или `wontfix` с обоснованием в `docs/architecture/`.
- [ ] Все Enterprise-фичи (Блок B) — подключены к gateway, работают, имеют newman.
- [ ] Блок F: API-токены реализованы (resource + RPC + authn-путь на gateway + newman); симуляция в тестах заменена реальным flow.
- [ ] Блок C: Compute Internal admin Lists готовы (loadbalancer — вне скоупа, зафиксировано).
- [ ] AuthZ-инфра (Блок D) развёрнута и работает.
- [ ] **100% newman-покрытие**: чек-лист «RPC → newman-case» закрыт полностью; матрица сверена с `kacho-proto`.
- [ ] Все newman-сюиты в `run.sh`, генерируются `gen.py`, зелёные в CI.
- [ ] Integration-покрытие ≥80% на новом коде.
- [ ] Весь CI зелёный во всех 9 репо.
- [ ] Инфра развёрнута: OpenFGA HA, drainer, Postgres+бэкапы, gateway authz fail-closed, TLS.
- [ ] Observability: метрики/логи/трейсы/алерты/дашборды/runbooks.
- [ ] Документация синхронизирована (CLAUDE.md / vault / спеки / KAC-trail).
- [ ] (рекомендуется) внешний pentest пройден.

После выполнения — продукт переводится в **maintenance-only**: только security-fix и
регресс-фиксы, новых фич нет.

---

## Часть 5 — Последовательность

1. **Фаза I — newman-инфра + матрица** (Шаг 2.0 + 2.1): починить `gen.py`-совместимость,
   построить полный чек-лист RPC→case. Без этого нельзя измерить «покрыто».
2. **Фаза II — AuthZ-ядро + инфра** (Блок A + D): критический путь, как в launch-плане M1-M2.
3. **Фаза III — Enterprise completion** (Блок B + Блок F): SAML/SCIM/JIT/break-glass/CAEP/audit + **API-токены** — по одной фиче, test-first.
4. **Фаза IV — недостающие RPC** (Блок C): Compute Internal admin Lists (loadbalancer — вне скоупа).
5. **Фаза V — добор newman до 100%** (Часть 2): закрыть каждый пробел чек-листа.
6. **Фаза VI — CI зелёный + инфра + observability** (Часть 3 + launch-план WS-5/6/7).
7. **Фаза VII — freeze**: пройти чек-лист Части 4, перевести в maintenance.

Каждая фаза — чанками, **тест первым** (RED→GREEN), верификация в CI.

---

## Часть 6 — Решения (приняты 2026-05-21)

| # | Вопрос | Решение |
|---|---|---|
| DECISION-LB | `kacho-loadbalancer` строить или вне продукта | ✅ **вне скоупа** — домен NLB/TargetGroup не строится |
| DECISION-AUDIT | audit-pipeline — полный или минимум | ✅ **VictoriaLogs + vector.dev** — `audit_outbox` (Postgres durable) → vector.dev → VictoriaLogs; без Kafka/ClickHouse/HSM/Merkle; HSM не нужен |
| DECISION-MESH | SPIFFE/SPIRE + Cilium mesh | ✅ **в скоупе** — SPIRE HA + Cilium ServiceMesh + mTLS по SVID |
| DECISION-SCALE | объём newman | ✅ **полное покрытие функционала** — каждый RPC happy+negative+authz; «без этого продукту нельзя доверять» |

> **Важно про оценку трудозатрат.** Полный объём: 44 authz-находки + доведение 9 enterprise-фич
> (B.1-B.8 + B.10 mesh) + audit на VictoriaLogs/vector + Compute Internal Lists + **полное**
> newman-покрытие (сотни кейсов) + инфра + observability. Это **многомесячный** объём
> (KAC-127 пытался сделать «за раз» и выдал нерабочее).
> Реалистичный путь — Фаза I-II сначала (рабочее authz-ядро + измеримое покрытие), дальше
> итеративно фазы III-VII. Lean-v1 (`production-launch-plan.md`) — это срез Фаз I-II + деплой
> (быстрый «работающий продукт»), полная «консервация» достраивается над ним.
