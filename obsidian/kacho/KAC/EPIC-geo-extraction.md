---
title: "[EPIC] kacho-geo: extract Geography (Region/Zone) into a leaf-service"
ticket_id: EPIC-geo
status: done
type: epic
repos:
  - kacho-proto
  - kacho-geo
  - kacho-compute
  - kacho-vpc
  - kacho-nlb
  - kacho-api-gateway
  - kacho-deploy
  - kacho-ui
  - kacho-workspace
prs:
  - "PRO-Robotech/kacho-proto#58 (S1 geo.v1 add)"
  - "PRO-Robotech/kacho-geo#1 (S2 leaf-service) + #2 (ci docker push)"
  - "PRO-Robotech/kacho-compute#54 (S4 geo-client) + #56 (S7 remove serving)"
  - "PRO-Robotech/kacho-vpc#155 (S4 geo-client) + #156 (geo dial-host fix) + #157 (e2e geo build)"
  - "PRO-Robotech/kacho-nlb#29 (S4 geo-client) + #30 (deploy edge) + #31 (e2e geo build)"
  - "PRO-Robotech/kacho-compute#55 (deploy geo edge)"
  - "PRO-Robotech/kacho-api-gateway#81 (S5 geo routes) + #82 (S7 remove compute geo routes)"
  - "PRO-Robotech/kacho-deploy#95 (S6 sub-chart+S3 migration) + #96 (cutover values+e2e fixes) + #97 (S7 disable data-migration)"
  - "PRO-Robotech/kacho-ui#78 (W8 /geo/v1/* switch)"
  - "PRO-Robotech/kacho-workspace#83 (S8 docs/vault/owner-map/bootstrap)"
  - "PRO-Robotech/kacho-proto#59 (S7 remove compute.v1 Region/Zone, breaking)"
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-
opened: 2026-06-17
closed: 2026-06-17
tags:
  - kac
  - epic
  - kacho-geo
  - kacho-compute
  - architecture
  - geography
---

# [EPIC] kacho-geo: extract Geography (Region/Zone) into a leaf-service

**Status**: done (2026-06-17 — all stages S1–S8 merged; live cutover on fe3455 verified; fresh-kind newman e2e green)
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
- **S7** (финал, breaking, 4 репо, usage-first→proto-last) — compute serving removal ([compute#56](https://github.com/PRO-Robotech/kacho-compute/pull/56), +миграция 0011 drop) + gateway routes removal ([api-gateway#82](https://github.com/PRO-Robotech/kacho-api-gateway/pull/82)) + deploy disable obsolete data-migration job ([deploy#97](https://github.com/PRO-Robotech/kacho-deploy/pull/97)) + proto removal ([proto#59](https://github.com/PRO-Robotech/kacho-proto/pull/59), buf breaking continue-on-error). DiskType/Instance в compute.v1 сохранены.
- **S8** kacho-workspace — docs/specs + vault + polyrepo build-graph + owner-map + bootstrap/sync (PR [#83](https://github.com/PRO-Robotech/kacho-workspace/pull/83); поймал+починил bats fixture-регрессию 10→11 репо).
- **W8** kacho-ui — Region/Zone селекторы + admin → `/geo/v1/*` (7 call-sites, nginx/vite proxy) ([ui#78](https://github.com/PRO-Robotech/kacho-ui/pull/78)); образ задеплоен на fe3455.

## Cutover (live, fe3455) + находки

Живой стенд fe3455 переведён `helm upgrade` (rev8): kacho-geo + pg-geo подняты, vpc/compute/nlb подключены к geo по mTLS (`peer connected … kacho-geo:9090 mtls:true`), api-gateway маршрутизирует `/geo/v1/*` (проба 401 AUTHN_REQUIRED с fqn `geo.v1.ZoneService/List`), UI на geo-образе. user→geo authz работает на том же `viewer@cluster:cluster_kacho_root` floor, что и прежний compute (geo сам шлёт required_relation в Check).

Findings во время cutover (все исправлены):
1. **consumer→geo deploy-edge не был проброшен** S4-кодом — vpc dial-host bug (`geo.*`→`kacho-geo.*`, не в cert-SAN), compute без geo env-блока, nlb без geo вовсе → 3 PR (vpc#156/compute#55/nlb#30) + deploy#96 (`mtls.edges.geo=true`).
2. **geo sub-chart рендерил cert-manager Certificate при mtls-off** (kind e2e) → helm install падал → e2e fix (`--set kacho-geo.mtls.enable=false`, deploy#96).
3. **per-repo newman-e2e не собирал `kacho-geo:dev`** (deploy#95 добавил sub-chart, build-матрицы не обновили) → стек не вставал → geo build добавлен в e2e всех 6 репо (deploy#96 + vpc#157/nlb#31/iam#157).
4. **data-migration job** читает `kacho_compute.regions` — после S7-drop устарел → отключён (deploy#97); толерантен к отсутствию source (нет pipefail).
5. compute authz-deny newman floor 200→180 после удаления Region/Zone кейсов.
6. **api-gateway→geo дозвон сломан** (post-cutover, нашёл пользователь: 503 `code 14 no children`): gateway звонил по `geo.kacho.svc.cluster.local` (NXDOMAIN — svc называется `kacho-geo`!) + не был включён gateway→geo mTLS-edge. Проявлялось ТОЛЬКО на аутентифицированном запросе (unauth режется authz-интерсептором ДО backend-дозвона — поэтому unauth-smoke не ловил, ложное «готово»). Фикс: host→`kacho-geo.*` + `MTLS_GEO_ENABLE=true` ([api-gateway#83](https://github.com/PRO-Robotech/kacho-api-gateway/pull/83) + [deploy#99](https://github.com/PRO-Robotech/kacho-deploy/pull/99)). Test-gap закрыт: аутентиф. geo newman-suite `geo-read` ([iam#158](https://github.com/PRO-Robotech/kacho-iam/pull/158)). **Урок**: svc `kacho-<x>` (iam/nlb/geo) vs `<x>` (vpc/compute) — geo-дефолт ошибочно скопирован с no-prefix паттерна; всегда проверять аутентифицированный путь, не только unauth-smoke.

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
- [x] S1–S7 в `main` (proto / kacho-geo / migration / consumers / api-gateway / deploy / contract)
- [x] data-migration валидирована на dev + fe3455 (id+created_at сохранены; на greenfield — geo seed baseline)
- [x] integration + newman зелёные (fresh-kind umbrella e2e PASS после geo-build fix)
- [x] geo internal+public листенеры: mTLS + per-RPC authz-Check (security-инвариант)
- [x] live cutover на fe3455 (rev8): geo serving, consumers mTLS→geo, gateway `/geo/v1/*`, UI на geo
- [ ] (опц.) live-redeploy compute post-S7 образом (убрать неиспользуемый geo-serving со стенда)
- [ ] эпик-тикет в YouTrack переведён в Done (KAC-номер не присвоен; трекинг через GitHub #82)

## Связанные тикеты

- GitHub [PRO-Robotech/kacho-workspace#82](https://github.com/PRO-Robotech/kacho-workspace/issues/82) (эпик)
- [[KAC-15]] (исходный перенос Geography vpc → compute — теперь надстраивается)

#kac #epic #kacho-geo #geography
