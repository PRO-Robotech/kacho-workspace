# Sub-phase CIL0 — Network vrf_id allocation + Internal Get — Acceptance

> Статус: APPROVED (round 2 — устранены out-of-scope/traceability/roadmap-pivot замечания round 1)
> Дата: 2026-06-13
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1) — ✅ APPROVED, см. §«Acceptance Review» внизу
> Трек: **CIL** (Cilium SRv6 L3VPN data-plane realization) — control-plane prerequisite

### Привязка к тикету (ban #1 + git-youtrack — обязательна ДО APPROVED-for-code)

> [!important] Pre-APPROVAL gate
> Док НЕ может быть APPROVED-for-code, пока поля ниже не заполнены **реальным** KAC-номером
> (не плейсхолдером). Заведение тикета + KAC-trail — последний шаг перед снятием gate,
> не часть acceptance-текста. Эпик не требуется (один feature-тикет — решение заказчика).

| Поле | Значение |
|---|---|
| Subtask (этот док) | `KAC-<N>` `CIL0 — Network vrf_id alloc + InternalNetworkService.GetNetwork` |
| Ветка `kacho-proto` | `KAC-<N>` |
| Ветка `kacho-vpc` | `KAC-<N>` |
| Ветка `kacho-api-gateway` | `KAC-<N>` (регистрация только internal mux) |
| Правка vault | `obsidian/kacho/edges/vpc-operator-to-cilium-realization.md` + `KAC/KAC-<N>.md` |
| YouTrack | `https://prorobotech.youtrack.cloud/issue/KAC-<N>` |

> [!note] Решение data-plane (зафиксировано 2026-06-13)
> Заказчик: **Cilium SRv6 VRF вытесняет kube-ovn+Multus** как канон data-plane.
> Предыдущий OP-трек ([[sub-phase-OP1-kachosubnet-crd-acceptance]], kube-ovn+Multus)
> **заморожен/депрекатится**. Этот трек (CIL, Cilium SRv6, без Multus) — новый канон;
> `vrf_id` для него обязателен. См. `obsidian/kacho/edges/vpc-operator-to-cilium-realization.md`.

## Обзор

VPC Kachō (`Network`) реализуется на data-plane Cilium через нативный SRv6 L3VPN: каждому
`Network` соответствует SRv6 **VRF**, идентифицируемый целочисленным `VRF_ID` (`uint32` в
датаплейне). Этот sub-phase добавляет в control-plane `kacho-vpc`: (1) аллокацию
уникального на всю БД, неизменного `vrf_id` при `Network.Create`; (2) новый
**internal-only** RPC чтения, отдающий `vrf_id`. `vrf_id` — числовой инфра-идентификатор,
поэтому по `security.md` он живёт **исключительно** на cluster-internal API (:9091) и
никогда не появляется на public-поверхности `Network`.

Нормативные конвенции (не дублируются здесь — ссылки): форма/ошибки/update_mask —
`.claude/rules/api-conventions.md`; within-service уникальность на DB-уровне —
`.claude/rules/data-integrity.md`; Internal-vs-public + инфра-данные —
`.claude/rules/security.md`.

**proto-локации (по recon):**
- `kacho/cloud/vpc/v1/internal_network_service.proto` — новый `rpc GetNetwork`
  (`InternalNetworkService`, рядом с `SetDefaultSecurityGroupId`; тот же authz-блок:
  `permission`, `required_relation=system_admin`, `scope_extractor` object_type `cluster`,
  `required_acr_min=2`).
- Новые messages: `GetInternalNetworkRequest { string network_id = 1; }`,
  `GetInternalNetworkResponse { Network network = 1; uint32 vrf_id = 2; }`.
- `network.proto` (`Network`) — **НЕ меняется**: `vrf_id` туда не добавляется.

---

## S1 — Аллокация vrf_id при Network.Create

### CIL0-01 (happy: vrf_id аллоцирован)
- **Given** seed-проект
- **When** `POST /vpc/v1/networks {"projectId":"<seed>","name":"net-vrf-01"}` → poll `OperationService.Get(id)` до `done`
- **Then** Operation `done && !error`; затем `InternalNetworkService.GetNetwork {"networkId":"<id>"}` → `vrf_id >= 1` (никогда `0`), `network.id == <id>`.

### CIL0-02 (concurrency: уникальность на всю БД)
- **Given** seed-проект
- **When** **N=20** параллельных `POST /vpc/v1/networks` с разными `name` (одновременно)
- **Then** все Operation `done && !error`; множество `vrf_id` всех 20 сетей (через `InternalNetworkService.GetNetwork`) состоит из **20 различных** значений (ни одного дубля). Уникальность гарантируется на DB-уровне (`data-integrity.md`, ban #10), не software check-then-act.

### CIL0-03 (immutability: vrf_id стабилен)
- **Given** Network `<id>` с `vrf_id = V` (из CIL0-01)
- **When** `PATCH /vpc/v1/networks/<id>` меняет `name`/`description`/`labels` (любой mutable-набор) → poll
- **Then** Operation done; повторный `InternalNetworkService.GetNetwork` → тот же `vrf_id == V`.

### CIL0-04 (immutability: vrf_id не принимается во вход)
- **Given** seed-проект
- **When** `PATCH /vpc/v1/networks/<id>` с `updateMask=vrfId`
- **Then** `INVALID_ARGUMENT` (unknown поле — `vrfId` отсутствует в known-set `Network`; `corevalidate.UpdateMask`). `vrf_id` нельзя задать или изменить через любой клиентский путь.

### CIL0-05 (no-reuse: монотонность после delete)
- **Given** Network `A` (`vrf_id = Va`), затем `A` удалён (`DELETE /vpc/v1/networks/<A>` → done)
- **When** создаётся Network `B` (`POST …`) → poll
- **Then** `vrf_id(B) != Va` (не переиспользуется), `vrf_id(B) > Va` (монотонно).

---

## S2 — Internal read + запрет утечки на public

### CIL0-06 (internal happy)
- **Given** Network `<id>` с `vrf_id = V`
- **When** `InternalNetworkService.GetNetwork {"networkId":"<id>"}` (cluster-internal :9091)
- **Then** `OK`; `network` — полная публичная проекция (`id`, `projectId`, `createdAt`, `name`, …, `default_security_group_id`); `vrf_id == V`.

### CIL0-07 (public no-leak: Get)
- **Given** Network `<id>` с аллоцированным `vrf_id`
- **When** public `GET /vpc/v1/networks/<id>`
- **Then** `OK`; ответ-JSON **не содержит** ключа `vrfId` и никакого числового VRF-поля (поля нет в `Network` message). Засветка инфра-идентификатора на external запрещена (`security.md`, ban #6).

### CIL0-08 (public no-leak: List)
- **Given** ≥2 Network с `vrf_id`
- **When** public `GET /vpc/v1/networks?projectId=<seed>`
- **Then** `OK`; ни один элемент `networks[]` не содержит `vrfId`.

### CIL0-09 (internal not-found)
- **Given** well-formed, но несуществующий `enp`-id `<X>`
- **When** `InternalNetworkService.GetNetwork {"networkId":"<X>"}`
- **Then** `NOT_FOUND` `"Network <X> not found"`.

### CIL0-10 (internal malformed id)
- **Given** —
- **When** `InternalNetworkService.GetNetwork {"networkId":"garbage"}`
- **Then** `INVALID_ARGUMENT` `"invalid network id 'garbage'"` (первым стейтментом RPC, `corevalidate.ResourceID`, parity с public `NetworkService.Get`).

### CIL0-11 (authz gate)
- **Given** caller без `system_admin` / `acr < 2`
- **When** `InternalNetworkService.GetNetwork {"networkId":"<id>"}`
- **Then** `PERMISSION_DENIED` (тот же gate, что `SetDefaultSecurityGroupId`: `required_relation=system_admin`, `required_acr_min=2`).

### CIL0-12 (internal-only routing)
- **Given** api-gateway с public TLS edge и cluster-internal mux
- **When** `GetNetwork` запрашивается через external TLS endpoint
- **Then** метод недоступен на external (не зарегистрирован на public mux); доступен только через internal mux (`vpcInternalAddr`). Регистрация — `api-gateway-registrar`, internal-блок.

---

## S3 — Backfill существующих Network

### CIL0-13 (миграция: все существующие получают vrf_id)
- **Given** Network'и, созданные ДО миграции (без `vrf_id`)
- **When** применена миграция, добавляющая `vrf_id`
- **Then** для каждого существующего Network `InternalNetworkService.GetNetwork` → `vrf_id >= 1`; все значения по БД **различны** (нет NULL, нет дублей). (Verifiable integration-тестом на pre-seeded строках.)

---

## Что НЕ входит (out-of-scope, отложено)

- **SRv6 датаплейн / VRF-map population** (Cilium-сторона) — отдельный трек CIL1+
  (`kacho-vpc-cilium` модуль). Здесь только control-plane аллокация + чтение vrf_id.
- **Subnet/SG/RouteTable/NIC → Cilium** — фазы CIL2…CIL6.
- **mesh-global согласование vrf_id** между кластерами (сейчас уникальность в одной БД
  `kacho-vpc`; БД одна на сервис, mesh-консистентность достигается тем, что vrf_id —
  атрибут control-plane Network, единого для всех кластеров).
- **`InternalNetworkService.List`** с vrf_id — не нужен этой фазе (только `GetNetwork`).
- **Изменение public `Network`** — явно запрещено (анти-цель, проверяется CIL0-07/08).

> [!note] Roadmap-pivot (трек не в 04-roadmap §3)
> CIL — новый трек, появившийся из решения заказчика «Cilium вытесняет kube-ovn»
> (2026-06-13). На момент написания `docs/specs/04-roadmap-and-phasing.md` его не
> содержит. **Follow-up (вне scope этого дока):** обновить 04-roadmap — добавить фазу
> CIL и пометить OP (kube-ovn) deprecated. Это стратегический pivot, решённый заказчиком
> (acceptance-reviewer §7), а не расхождение со спекой.

## Traceability (сценарий → тест)

| Сценарий | Integration (`internal/repo/*_test.go`) | Newman (`tests/newman/cases/*.py`) |
|---|---|---|
| CIL0-01 | `TestNetwork_CIL0_01_VrfIdAllocatedOnCreate` | `cil0_01_create_internal_get_vrfid` (internal) |
| CIL0-02 | `TestNetwork_CIL0_02_VrfIdUniqueUnderConcurrency` (goroutines) | — (race — integration-only) |
| CIL0-03 | `TestNetwork_CIL0_03_VrfIdStableAcrossUpdate` | `cil0_03_vrfid_stable_after_update` |
| CIL0-04 | — | `cil0_04_update_mask_vrfid_invalid` (negative) |
| CIL0-05 | `TestNetwork_CIL0_05_VrfIdNoReuseMonotonic` | — |
| CIL0-06 | `TestNetwork_CIL0_06_InternalGetReturnsVrfId` | `cil0_06_internal_get_happy` |
| CIL0-07/08 | — | `cil0_07_public_get_no_vrfid` / `cil0_08_public_list_no_vrfid` (negative) |
| CIL0-09 | — | `cil0_09_internal_get_notfound` (negative) |
| CIL0-10 | — | `cil0_10_internal_get_malformed_id` (negative) |
| CIL0-11 | — | `cil0_11_internal_get_authz_denied` (negative) |
| CIL0-12 | — | проверка маршрутизации: метод доступен на internal mux, отсутствует на public (api-gateway e2e) |
| CIL0-13 | `TestNetwork_CIL0_13_BackfillUniqueVrfId` (pre-seed) | — |

## DoD (по стадиям; `.claude/rules/testing.md`)

**Общий (TDD red→green в том же PR):**
- `kacho-proto`: новый RPC + messages; `buf lint`/`buf breaking` зелёные; regen `gen/go`.
- `kacho-vpc`: миграция (новый файл — НЕ правка baseline, ban #5); аллокация на DB-уровне
  (уникальность + диапазон + immutable; механизм — забота `db-architect-reviewer`/implementer,
  здесь только наблюдаемое поведение); handler `InternalNetworkService.GetNetwork`.
- `kacho-api-gateway`: регистрация `GetNetwork` **только** на internal mux (`api-gateway-registrar`).

**Тесты (обязательны, тот же PR):**
- integration (testcontainers): **CIL0-02 concurrent-Create → distinct vrf_id** (критичный
  race-сценарий, ban #10); CIL0-05 no-reuse; CIL0-13 backfill-uniqueness; CIL0-03 immutability.
- newman через **internal** порт: happy (CIL0-01/06) + negative (CIL0-09/10); public no-leak
  (CIL0-07/08) через public порт.

**Trail:** vault `edges/vpc-operator-to-cilium-realization.md` (уже отражает дизайн) +
`resources/cilium-kachovpc.md` (vrf_id authority) + KAC-trail `KAC/KAC-<N>.md`.

---

## Координация (agent lifecycle)

DRAFT → `acceptance-reviewer` (coverage / traceability / scope) → итерации до `✅ APPROVED`.
После APPROVED: присвоить KAC + ветки → `integration-tester` (RED по CIL0-NN) →
`rpc-implementer` (proto→vpc→api-gateway) → `proto-api-reviewer` + `db-architect-reviewer`.
Финальный smoke — заказчик. **Развилка kube-ovn vs Cilium разрешена: Cilium SRv6 (см. note).**

---

## Acceptance Review: sub-phase CIL0 — Network vrf_id alloc + Internal Get

**✅ APPROVED.** Можно начинать planning + implementation.

**Покрытие spec:** трек CIL отсутствует в 04-roadmap (новый pivot, решён заказчиком) —
зафиксировано как follow-up на обновление roadmap; контракт самодостаточен.
**Сценарии:** 13 (positive: 4 — CIL0-01/03/05/06; negative: 7 — CIL0-04/07/08/09/10/11/12;
concurrency: CIL0-02; migration/backfill: CIL0-13).
**Формат:** Given-When-Then, уникальные ID CIL0-NN, конкретные payload + gRPC-коды.
**Traceability:** таблица сценарий↔тест (integration + newman) добавлена.

**Round 1 → 2 (устранено):**
1. **[SCOPE]** Добавлен раздел «Что НЕ входит».
2. **[TRACEABILITY]** Добавлена таблица сценарий→`Test...`/newman-кейс.
3. **[SCOPE/ROADMAP]** Зафиксирован roadmap-pivot + follow-up на 04-roadmap.

**Дефолты, зафиксированные на review:**
- Q: тип/диапазон vrf_id в БД → `bigint`, `1..4294967295`, `0` reserved (механизм — sequence;
  финальное решение колонки за `db-architect-reviewer` на этапе миграции).
- Q: mesh-уникальность → достаточно БД-уникальности (Network — единый control-plane объект
  для всех кластеров; vrf_id его атрибут).

**Замечания (non-blocking):**
- CIL0-12 (internal-not-on-external) проверяется api-gateway e2e — убедиться, что
  `api-gateway-registrar` ставит метод только в `vpcInternalAddr`-блок.

**Следующий шаг:** `writing-plans` → `docs/plans/sub-phase-CIL0-network-vrf-id-plan.md`.
