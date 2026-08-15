# Implementation plan — nlb/vpc placement-coherence (GAP-1/2/3)

> Acceptance: **✅ APPROVED** — `docs/specs/sub-phase-nlb-vpc-zone-coherence-acceptance.md` (16 сценариев `ZC-*`).
> Норма: `.claude/rules/data-integrity.md §Placement-coherence`.
> Тип: **fix / hardening**, **backend-only** — proto и схема БД НЕ меняются.
> Тикет: `KAC-<N>` (batch-fix сессии) — завести до кода; ветка `KAC-<N>` в kacho-nlb и kacho-vpc.
> Репо независимы (оба — consumer-валидация на request-path); PR можно параллельно.

## Инвариант (что чиним)
Все три дыры — **cross-service peer-validate на request-path**, fail-closed `UNAVAILABLE` (не DB-FK через границу, ban #4/#8). Anycast/REGIONAL — исключён из зональной проверки by construction.

---

## Stage 1 — kacho-nlb (GAP-1 + GAP-2)

Файлы: `internal/apps/kacho/api/loadbalancer/create.go` (+ `peer_errors.go`, `internal/clients/subnet_client.go`), тесты `create_test.go`, newman `tests/newman/cases/`.

### GAP-1 — ZONAL dualstack same-zone
- **RED first**: `create_test.go` — ZONAL LB, v4-subnet зоны `Z1` + v6-subnet зоны `Z2` → `InvalidArgument`, message `"dualstack load balancer families must resolve to the same zone"` (Q1-дефолт, зеркалит sibling `create.go:192` `"...same network"`). Happy: обе в `Z1` → ok. REGIONAL LB (anycast) → проверка пропущена. Single-family → нет сравнения.
- **GREEN**: в `resolveSources` (`create.go:180-194`), рядом с существующей same-network-проверкой, добавить same-zone для `PlacementZonal`: обе резолвнутые подсети → `sn.ZoneID` должны совпасть. Использует уже читаемый `subnet_client.go:129 ZoneID`.

### GAP-2 — region-coherence (VIP subnet/address ↔ lb.region_id)
- **RED first**: caller-supplied `subnet_id` из чужого региона (ZONAL-subnet зоны ∈ R2, либо REGIONAL-subnet R2) при `lb.region_id=R1` → `InvalidArgument "load balancer VIP must be in the same region"` (descriptive). Linked `address_id` из чужого региона → generic `"Illegal argument addressId"` (анти-oracle, зеркалит `resolveLinkedAddress` create.go:239/253/256). Happy: тот же регион.
- **GREEN**:
  1. `subnet_client.go:38` — **заполнить `RegionID`** в projection (сейчас «adapter оставляет пустым»): для ZONAL — регион зоны (через zone→region, geo), для REGIONAL — `subnet.region_id`.
  2. В `resolveOneSource`/`resolveLinkedAddress` — assert `subnetRegion == lb.RegionID` (subnet_id → descriptive; address_id → generic). Fail-closed при недоступности geo/vpc.

## Stage 2 — kacho-vpc (GAP-3)

Файлы: `internal/apps/kacho/api/address/{create.go,iface.go,handler.go}` (+ порт `ZoneRegistry`), `cmd/<vpc>/main.go` (wiring), `internal/clients/geo_client.go` (reuse), тесты, newman.

### GAP-3 — external Address.zone_id geo-validation
- **RED first**: `Address.Create` external (v4/v6) с несуществующим `zone_id` → `InvalidArgument "unknown zone id '<X>'"` (verbatim-зеркало `subnet/helpers.go:197 validateZoneID`). Happy: known zone → ok. **Anycast**: external из global-пула, `zone_id=''` → **освобождён** (в отличие от Subnet). Internal: зона наследуется от subnet (не проверяем zone напрямую).
- **GREEN**:
  1. Определить **локальный `ZoneRegistry`-порт** в address-usecase (как в `subnet/iface.go:70` / addresspool) + impl через существующий `clients/geo_client.go` (`geo.v1.ZoneService.Get`).
  2. Wiring в composition-root `cmd/` (address-usecase получает zoneReg).
  3. В `address/create.go` (external-ветка, где `ExternalSpec.ZoneID` сохраняется, ~:351/:381): при непустом `zone_id` → `zoneReg.Get` → на `ErrNotFound` → `InvalidArgument "unknown zone id '<X>'"`; fail-closed `UNAVAILABLE`. Пустой zone (anycast/global) → пропустить.

## Cross-cutting (Группа X acceptance)
- Fail-closed `UNAVAILABLE` при недоступности geo/vpc на любом precheck — покрыть в обоих stage.
- TOCTOU (subnet удалён между precheck и async-аллокацией) — детерминизм через async-worker + существующий `compensateCreate` (`create.go:510`); incoherent-LB никогда не персистится. **НЕ** within-service DB-CAS-гонка (cross-service).

---

## Тесты / верификация (ban #12)
- **RED → GREEN** по каждому сценарию; behaviour-level assert **точных строк** (не только код).
- integration (testcontainers) + **newman** (black-box через api-gateway) в том же PR, per-repo.
- `-race` для concurrency (ZC-X.2).
- Перед merge: `go test ./... -race` + `golangci-lint run` + `govulncheck` + newman зелёные, per-repo.

## Отдельно (НЕ в этом PR)
- **GitHub Issue `tech-debt`**: apiconv-дрейф — `subnet.validateZoneID` отдаёт `InvalidArgument` на `"unknown zone id '%s'"`, а `addresspool/create.go:87` — `FailedPrecondition` на идентичный текст. Унификация — отдельный тикет (pre-existing, вне scope). GAP-3 сознательно зеркалит **subnet** (`InvalidArgument`).

## Trail (после merge)
- `polyrepo.md`: рёбер новых нет (все три — усиление существующих nlb→vpc/geo, vpc→geo). Обновить `edges/`-vault (nlb-to-vpc, nlb-to-geo, +новое vpc→geo для Address) + `KAC/KAC-<N>.md` (status, PR-URL, «затронутые сущности»).
