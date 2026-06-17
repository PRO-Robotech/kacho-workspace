---
title: "[EPIC] kacho-geo: extract Geography (Region/Zone) into a leaf-service"
ticket_id: EPIC-geo
status: in-progress
type: epic
repos:
  - kacho-proto
  - kacho-geo
  - kacho-compute
  - kacho-vpc
  - kacho-nlb
  - kacho-api-gateway
  - kacho-deploy
  - kacho-workspace
prs:
  - "PRO-Robotech/kacho-workspace#83 (S8)"
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-
opened: 2026-06-17
tags:
  - kac
  - epic
  - kacho-geo
  - kacho-compute
  - architecture
  - geography
---

# [EPIC] kacho-geo: extract Geography (Region/Zone) into a leaf-service

**Status**: in-progress
**Type**: epic
**GitHub epic**: [PRO-Robotech/kacho-workspace#82](https://github.com/PRO-Robotech/kacho-workspace/issues/82)
**YouTrack**: KAC-<N> (присвоить)
**Acceptance** (APPROVED): `docs/specs/sub-phase-6.0-kacho-geo-extraction-acceptance.md` (25 G-W-T, 8 стадий).

## Что и зачем

Region/Zone жили в `kacho-compute` (`compute.v1`, схема `kacho_compute`), что делало compute
зависимостью трёх consumer'ов **исключительно ради geography**. Решение владельца: Region/Zone —
platform topology (leaf-primitive, как IAM), а не compute-абстракция. Эпик выделяет Geography в
новый **leaf-сервис `kacho-geo`** (домен `kacho.cloud.geo.v1`, схема `kacho_geo`), переключает
compute/vpc/nlb/api-gateway на него и удаляет geography из `compute.v1`.

Результат — ацикличный граф `all → geo`, `geo → iam` (leaf, как iam). Ложные «ради geography»
рёбра `vpc→compute (zone)` и `nlb→compute (region)` исчезают.

Cutover: **expand → migrate → switch → contract** (geo.v1 additive → данные мигрированы 1-в-1 с
сохранением id → consumer'ы переключены → удаление geography из compute.v1 последним, breaking).

## Декомпозиция (по build-графу)

- **S1** kacho-proto — домен `geo.v1` (Region/Zone + 4 сервиса); additive (`buf breaking` зелёный).
- **S2** kacho-geo — clean-arch leaf-скелет + схема `kacho_geo` + RPC + mTLS internal + per-RPC authz + geo_outbox.
- **S3** data-migration — `regions`/`zones` из `kacho_compute` → `kacho_geo`, id+created_at сохранены (dev+fe3455).
- **S4** consumers — compute/vpc/nlb на geo-client; fail-closed Unavailable; ложные рёбра удалены.
- **S5** kacho-api-gateway — REST `/geo/v1/*`; permission_catalog → geo FQN; Internal* на internal mux.
- **S6** kacho-deploy — sub-chart kacho-geo + pg-geo + migration-job + mTLS (SEC-F) + values.
- **S7** kacho-proto (финал) — удалить geography из `compute.v1` (breaking, ПОСЛЕ перевода consumer'ов).
- **S8** kacho-workspace — docs/specs + vault + polyrepo build-graph + owner-map + bootstrap/sync (PR [#83](https://github.com/PRO-Robotech/kacho-workspace/pull/83)).

## Затронутые сущности vault

- [[../resources/geo-region]] · [[../resources/geo-zone]] (новые)
- [[../rpc/geo-region-service]] · [[../rpc/geo-zone-service]] (новые)
- [[../packages/proto-geo]] · [[../packages/geo-domain]] (новые); [[../packages/proto-compute]] (geography вынесена); [[../packages/vpc-clients]] (geo_client); [[../packages/nlb-clients-compute]] (region удалён)
- Новые edges: [[../edges/vpc-to-geo-zone-validate]] · [[../edges/compute-to-geo-zone-validate]] · [[../edges/nlb-to-geo-region-validate]] · [[../edges/geo-to-iam-check]]
- Superseded edges: [[../edges/vpc-to-compute-zone-validate]] · [[../edges/nlb-to-compute-region-validation]]
- Owner-map `data-integrity.md` §5: Geography → `kacho-geo`. build-graph `polyrepo.md`: geo — leaf.

## Definition of Done

> [!important] Проставляй `[x]` сразу по факту.

- [x] S8 (workspace): owner-map + build-graph + edges + bootstrap.sh + sync-tooling.sh + vault + docs/specs обновлены
- [ ] S1–S7 в `main` (proto / kacho-geo / migration / consumers / api-gateway / deploy / contract)
- [ ] data-migration валидирована на dev + fe3455 (id+created_at сохранены)
- [ ] integration + newman зелёные во всех затронутых репо
- [ ] geo internal-листенер: mTLS + per-RPC authz-Check (security-инвариант)
- [ ] эпик-тикет переведён в Done со всеми артефактами

## Связанные тикеты

- GitHub [PRO-Robotech/kacho-workspace#82](https://github.com/PRO-Robotech/kacho-workspace/issues/82) (эпик)
- [[KAC-15]] (исходный перенос Geography vpc → compute — теперь надстраивается)

#kac #epic #kacho-geo #geography
