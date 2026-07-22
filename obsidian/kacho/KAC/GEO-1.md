---
title: "GEO-1 — Region/Zone redesign (two-projection, sync Operation)"
ticket_id: GEO-1
status: in-progress
type: feature
repos:
  - kacho-geo
prs: []
yt_url: ""
opened: 2026-07-20
closed: ""
tags:
  - kac
  - feature
  - kacho-geo
  - geo
---

# GEO-1 — Region/Zone redesign

**Status**: in-progress (core owner-side landed; gateway/newman/UI follow-on).
**Repo**: `project/kacho` (монорепо), ветка `redesign/geo-region-zone`.
**Acceptance**: `docs/specs/sub-phase-GEO-1-region-zone-redesign-acceptance.md` (APPROVED, 39
сценариев GEO-1-01..39).
**Design**: `docs/plans/kacho-redesign-2026/module-geo.md`.

## Что и зачем

Приводит owner-side Region/Zone к целевому tenant-facing дизайну: публичная поверхность —
чистая read-discovery оси размещения с единственным actionable-сигналом `openForPlacement°`;
сырой `status` (UP/DOWN) + весь `infra°` уходят в **two-projection** (`Internal*` :9091,
read+write через РАЗНЫЕ messages). Fresh ресурс поднимается **DOWN** (fail-safe), тихий no-op —
громкий через `warnings°` в geo-owned `Create*Metadata`. Admin-мутации возвращают
**синхронно-завершённый `Operation{done:true}`** (config-INSERT, без саги). `id` — human slug
(THE ONE carve-out), coupling `zone.id == regionId+"-"+suffix`. Global `UNIQUE(name)`; `name` required.

## Реализовано (этот проход — ядро по build-графу)

- **proto**: two-projection messages `Region`/`Zone` (lean) + `InternalRegion`/`InternalZone`
  (full); shared `GeoStatus` + `PlacementBlockedReason` enums; `RegionInfra`/`ZoneInfra`;
  `GetInternal` RPCs; `Create*Metadata.warnings`; region_id убран из `UpdateZoneRequest`
  (immutable); FieldMask на Update; List filters `region_id`/`open_for_placement`. Public Zone
  теряет `status` (намеренный breaking, reserved 3).
- **migration 0004**: status+infra колонки, fail-safe `DEFAULT 'DOWN'`, required `UNIQUE(name)`,
  tightened `status CHECK(UP/DOWN)`.
- **repo/use-case/handler/protoconv**: sync `done:true` (syncop helper), fresh-DOWN (UP-коэрсинг
  удалён), warnings°, coupling/countryCode/name валидаторы, immutable-mask, region-status JOIN
  для derived `openForPlacement°`, `openZoneCount°` rollup, GetInternal, two-projection мапперы.

## Follow-on (НЕ в этом проходе)

- **gateway-регистрация** (`api-gateway-registrar`): internal mux `/geo/v1/internal/…`, 4 read-RPC
  project-scope EXEMPT (снять `required_relation`+`scope_extractor`), permission-catalog regen
  byte-identical, documented-exception в `security.md`.
- **newman** (shared harness), **UI**, **GEO-2** (one-shot zoneSpecs + validateOnly), **GEO-CORELIB**
  (`corevalidate.GeoSlug` + `GEO_COORDINATE` kind), **consumer-side placement-edges**.
- **MERGE-GATE [PHASE-0-GATED]**: within-service create absent-parent остаётся FK-`FAILED_PRECONDITION`;
  by-lane NOT_FOUND + reason-token приземляются только после Phase-0 governance change-set в
  `api-conventions.md`. Не мёржить GEO-1 до этого.

## Затронутые сущности vault

[[resources/geo-region]] · [[resources/geo-zone]] · [[rpc/geo-region-service]] ·
[[rpc/geo-zone-service]] · [[KAC/EPIC-geo-extraction]]

## DoD-чеклист (core)

- [x] proto buf lint зелёный; gen обновлён; public Zone status-drop = намеренный breaking.
- [x] migration 0004 (не редактирует applied 0001-0003).
- [x] repo/use-case/handler/protoconv two-projection + sync done:true + fresh-DOWN.
- [x] integration (testcontainers): UNIQUE(name) concurrent-race, two-projection, fresh-DOWN,
      cross-region openForPlacement, openZoneCount rollup, infra round-trip.
- [x] unit: domain derivations/validators, use-case sync/warnings/immutable, protoconv field-absence.
- [x] `go build ./...`, `go test -race`, `golangci-lint` зелёные (geo).
- [ ] gateway/newman/UI/security.md-exception — follow-on.

#kac #feature #kacho-geo #geo
