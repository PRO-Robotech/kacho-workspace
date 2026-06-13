# Implementation Plan — CIL0: Network vrf_id alloc + Internal Get

> Источник: APPROVED `docs/specs/sub-phase-CIL0-network-vrf-id-internal-acceptance.md`
> Дата: 2026-06-13 · Статус: ready-to-implement (блокеры окружения — см. §Блокеры)
> Кросс-репо порядок (build-граф): `kacho-proto` → `kacho-vpc` → `kacho-api-gateway`

## Резюме

Network получает неизменный, уникальный на всю БД `vrf_id` (bigint, аллокация
sequence на Create). Новый internal-only `InternalNetworkService.GetNetwork` отдаёт
`Network` + `vrf_id`. Public-поверхность Network не меняется (анти-цель).

---

## Шаг 1 — kacho-proto (ветка `KAC-<N>`)

Файл: `proto/kacho/cloud/vpc/v1/internal_network_service.proto`

- Добавить RPC в `service InternalNetworkService` (authz-блок копией `SetDefaultSecurityGroupId`,
  `permission="vpc.networks.get_internal"`, `required_relation="system_admin"`,
  `scope_extractor{object_type:"cluster", from_request_field:"*"}`, `required_acr_min="2"`):
  ```
  rpc GetNetwork(GetInternalNetworkRequest) returns (GetInternalNetworkResponse);
  ```
- Добавить messages (импортировать `network.proto` для `Network`):
  ```
  message GetInternalNetworkRequest  { string network_id = 1; }
  message GetInternalNetworkResponse { Network network = 1; uint32 vrf_id = 2; }
  ```
- **НЕ трогать** `network.proto` (`Network` message).
- `buf lint` + `buf breaking` (additive RPC/message — non-breaking) → regen `gen/go`.

**Verify:** `buf lint`, `buf breaking --against '.git#branch=main'`, `buf generate`.

## Шаг 2 — kacho-vpc (ветка `KAC-<N>`)

### 2a. Миграция (новый файл — ban #5, НЕ править applied)
`internal/migrations/0007_network_vrf_id.sql` (goose):
```sql
-- +goose Up
CREATE SEQUENCE kacho_vpc.networks_vrf_id_seq AS bigint
  START 1 MINVALUE 1 MAXVALUE 4294967295 NO CYCLE;
ALTER TABLE networks
  ADD COLUMN vrf_id bigint NOT NULL DEFAULT nextval('kacho_vpc.networks_vrf_id_seq');
ALTER TABLE networks
  ADD CONSTRAINT networks_vrf_id_key   UNIQUE (vrf_id),
  ADD CONSTRAINT networks_vrf_id_range CHECK  (vrf_id BETWEEN 1 AND 4294967295);
-- +goose Down
ALTER TABLE networks DROP COLUMN vrf_id;
DROP SEQUENCE kacho_vpc.networks_vrf_id_seq;
```
(`DEFAULT nextval` volatile → бэкфилл существующих строк уникальными значениями автоматически,
покрывает CIL0-13. Аллокация атомарна на INSERT — ban #10, без app-side check-then-act.)
→ ревью `db-architect-reviewer` после реализации (финальное решение по типу/диапазону).

### 2b. Domain
`internal/domain/...network` — добавить поле `VRFID uint32` в entity Network (read-проекция).

### 2c. Repo (`internal/repo/kacho/pg/network.go` + `helpers`)
- `vrf_id` **не** добавляется в INSERT-список (`Insert`, строка ~221) — БД аллоцирует через DEFAULT.
- Новый read-метод `GetWithVRF(ctx, id) (Network, vrfID uint32, err error)` ЛИБО расширить
  scan существующего `Get` доп. колонкой через internal-specific cols-набор (НЕ менять
  `helpers.NetworkCols`, чтобы public-path не тянул vrf_id). Рекомендация: отдельная
  константа `helpers.NetworkInternalCols` (= NetworkCols + `, vrf_id`) + метод `GetInternal`.
- malformed id → `corevalidate.ResourceID` first-statement (CIL0-10).

### 2d. Use-case (`internal/apps/kacho/services/networkinternal`)
- Метод `GetNetwork(ctx, id) (*domain.Network, uint32, error)`:
  malformed → InvalidArgument `"invalid net id '<X>'"`; not-found (repo ErrNoRows) →
  NotFound `"Network <X> not found"`.
- Аллокация vrf_id — целиком на DB (sequence); use-case на Create НЕ участвует (поле OUTPUT).

### 2e. Handler (`internal/handler/internal_network_handler.go`)
- Метод `GetNetwork` рядом с `SetDefaultSecurityGroupId`; маппит → `GetInternalNetworkResponse`;
  ошибки через `internalMapErr` (no-leak pgx). vrf_id из use-case в `resp.VrfId`.
- Public `network` handler/usecase — **не трогать** (CIL0-07/08).

### 2f. Тесты (TDD RED→GREEN, тот же PR)
- integration (`internal/repo/.../network_vrf_id_integration_test.go`, testcontainers):
  `TestNetwork_CIL0_02_VrfIdUniqueUnderConcurrency` (20 goroutines Create → 20 distinct),
  `..._05_NoReuseMonotonic`, `..._13_BackfillUniqueVrfId`, `..._03_StableAcrossUpdate`.
- unit (usecase, mock-repo): not-found/malformed (CIL0-09/10).

## Шаг 3 — kacho-api-gateway (ветка `KAC-<N>`)

- `internal/restmux/mux.go`: зарегистрировать `GetNetwork` ТОЛЬКО в internal-блок
  (`vpcInternalAddr`), как `InternalNetworkService`/`InternalAddressPoolService` (CIL0-12).
  **Никогда** в public mux (`vpcAddr`). Ответственный — `api-gateway-registrar`.
- newman-кейсы (`tests/newman/cases/`): cil0_06/07/08/09/10/11 (см. traceability acceptance).

## Финальная верификация (перед merge каждого PR)
`go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter`
(vrf_id не должен пролезть в List-фильтр) + newman зелёные.

## Trail (после merge)
- vault: `resources/cilium-kachovpc.md` (vrf_id authority — уже), `rpc/vpc-internal-network-service.md`
  (+ GetNetwork), `resources/vpc-network.md` (+ vrf_id поле, internal-only), KAC-trail.

---

## Блокеры окружения (почему код не написан в этой сессии)

| Блокер | Нужно для | Как снять |
|---|---|---|
| `buf` MISSING | regen proto-stubs (шаг 1) — без них Go не компилируется | `brew install bufbuild/buf/buf` |
| `docker` NOT running | testcontainers integration (CIL0-02/05/13 — критичный race) | запустить Docker Desktop |
| `gh` не залогинен | PR в 3 репо | `gh auth login` |
| YouTrack нет токена | KAC-номер (ban #1 pre-APPROVAL gate) | токен / orchestrator присваивает |

`sqlc` MISSING — **НЕ блокер**: network-repo handwritten pgx (`helpers.NetworkCols`), не sqlc.
`go`/`golangci-lint` — есть.
