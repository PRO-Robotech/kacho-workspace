---
title: geo baseline НЕ засеян на greenfield stand — deploy-flow gap
category: kac
tags: [kacho-geo, kacho-deploy, kac, fix, migrations]
ticket_id: TBD
status: in-progress
type: fix
repos: [kacho-geo, kacho-deploy]
opened: 2026-07-24
---

# geo baseline (ru-central1 + zones) НЕ засеян на greenfield — deploy-gap

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Статус `in-progress` **подтверждён**, а не унаследован: предмет проверен по дереву
> и жив. Записка осталась открытой не потому, что её забыли закрыть.
>
> **in-progress.** **Предмет жив — перепроверено по дереву, и это единственная записка ряда, оставшаяся открытой.** Миграции geo (`0001`–`0004`) по-прежнему **не содержат ни одного `INSERT`**, то есть базовый каталог размещения на чистом стенде не появляется. Задание переноса данных это честно проговаривает в собственной шапке и указывает, откуда базовый набор берётся на чистом стенде, — **но названного им производителя в дереве нет**: поиск по имени даёт только эти два упоминания в самом комментарии. То есть у комментария сегодня нет предмета, и это второй дефект поверх первого. Закрывать — вместе с владельцем geo и стенда; здесь зафиксирован факт, а не решение.

> [!important] Root всех compute/nlb create-fail'ов на свежем стенде
> Fresh dev-up → geo catalog **пуст** → **все compute/nlb creates фейлят
> "Zone not found"** (peer-validate `geo.v1.ZoneService.Get` fail-closed) → нет
> ресурсов → GET/List 404. Домены выглядят «сломанными», а причина — пустой geo.

## Механизм gap'а
- geo goose-миграции `0001-0004` создают схему `kacho_geo.{regions,zones}`, но
  **baseline-INSERT (ru-central1 + zones a/b/d) НЕТ** (проверено: `regions=0`,
  `zones=0` при `goose version 4 applied`).
- `charts/kacho-geo/templates/geo-data-migration-job.yaml` (S3-migration) **копирует
  regions/zones из `kacho_compute`** (pre-cutover) — но на **greenfield** compute пуст
  → job = no-op (ON CONFLICT DO NOTHING на несуществующих строках) → geo остаётся пуст.
- Итог: greenfield stand (kind/CI/fresh-dev-up) не имеет geo baseline **by construction**.
  Data-migration job рассчитан на живой compute с данными, не на greenfield.

## Fix (применён вручную; нужен permanent)
Seed через **geo Internal admin RPC** (`POST /geo/v1/internal/regions` + `/zones` на
**:18081** internal-mux, `internal=True`), auth **`jwtBootstrap`** (system_admin@cluster
из `/tmp/matrix.json`). Скрипт `/tmp/geo-seed.sh` (баг: постил на :18080 public — RPC на
**:18081**). Ручной seed: region ru-central1 + zones a/b/c/d status UP → 200 → catalog=4 zones.
**Подтверждено:** после seed disk create `op.error=NONE`, GET **200 за 13ms/1-try**;
disk collection **60 fails→2** (2 = оригинальный list-includes EC, не geo).

**Permanent fix (рекомендация):** greenfield geo baseline-seed — либо (a) goose-миграция
geo с baseline-INSERT (idempotent, `ON CONFLICT DO NOTHING`), либо (b) `dev-up` шаг
seed-geo (admin-RPC) как часть стенда, либо (c) data-migration-job с greenfield-fallback
(seed baseline если compute пуст). Каноничный zone-набор: **a,b,d** (baseline) — c/d добавляются
admin'ом; проверь что suite-env ожидает (compute existingZoneId=ru-central1-a).

## Связь: red-herring предупреждение
Пустой geo → creates фейлят с `op.error` (на `done:true` Operation), но **если не
проверять `op.error`** и извлекать resource-id из metadata → выглядит как «create
succeeded → GET 404» → ложный диагноз «mirror/throughput materialization lag». 1.5ч
investigation ушло в throughput-призрак. **ВСЕГДА проверяй `op.error` ПЕРЕД metadata**
([[ec-under-load-measure-throughput]] + testing.md «op.error перед metadata»). throughput
inversion (drainer 0.5/s) был отдельный **stress-pollution артефакт** (14k-member binding),
не normal-load — см. [[fga-register-throughput-inversion]].

## Broader pattern: greenfield-seed-completeness (несколько prerequisites, не только geo)

Валидация всех доменов на чистом стенде вскрыла: **greenfield-стенд не сеет НЕСКОЛЬКО
fixture-prerequisites** (не только geo) — все тот же класс:
- **geo baseline** — FIXED (`ec245e9`, prodseed `_seed_geo_catalog`). Разблокировал creates.
- **AddressPool EXTERNAL** (`deploy/scripts/seed-nlb-fixtures.sh`) — НЕ адаптирован под prodseed
  (требует project из dev-mode setup.sh: `FATAL cannot resolve projectId`). Блокирует vpc
  address/internal-pool (~217 fails) + nlb external-VIP. **Fix: seed AddressPool как prodseed-
  prerequisite** (Internal admin :18081 POST /vpc/v1/addressPools, EXTERNAL_PUBLIC/zonal/
  is_default, jwtBootstrap + matrix projA1) — аналог geo-seed.
- **prodseed_vpc_ext.py HANGS** (~100s timeout, silent) — re-mint bootstrap ИЛИ op-poll виснет;
  блокирует vpc list-filter-d (6). Отдельный debug.
- **prodseed_nlb_ext VIP** — nlb suite нужен полный re-seed (out of scope текущего ext).

**Cores ЗЕЛЁНЫЕ** на чистом стенде (после geo-seed): vpc network/subnet(1119)/SG(707)/
route-table(481)/NIC(366)/authz-deny(705)/gateway = **0**; compute core (60→2/9); registry
(8→4); nlb region-validation ✅. Все failures = либо grant-materialization EC (compute/registry),
либо greenfield-seed-completeness (AddressPool/vpc-ext) — НЕ product-регрессии.

## Затронутые сущности vault
- [[fe3455-production-deploy]] (deploy-стек) · [[fga-register-throughput-inversion]] (red-herring)
- geo Region/Zone owner (peer-validate consumers: compute/nlb/vpc/registry)

## Validated end-to-end (fresh prodseed, clean stand) 2026-07-24
- **geo + AddressPool seeds committed** (`ec245e9` geo, `a9471d7` pool). Fresh `prodseed_matrix.py`
  авто-сеет оба (geo 4 zones + EXTERNAL pool isDefault) + matrix (43 keys) в одном прогоне rc=0.
- **vpc: address 449/0, internal-pool 225/0** (было 224 fails → **0** после pool-seed+fresh-tokens);
  core green (network/subnet 1119/SG 707/route-table 481/NIC 366/authz-deny 705/gateway = 0).
- **compute** 60→2 (disk) / ~9 list-includes EC · **registry** 8→4 repo-create EC · **nlb** mostly-green
  (target-group 3, load-balancer 1, authz-deny 2 residuals).
- **Оставшиеся fixture-infra followups (не product-регрессии):**
  - **ext-seed hang** (vpc-ext/nlb-ext): `import prodseed_matrix` re-runs весь matrix с НОВЫМ RID
    (time-based) → создаёт новых users → slow >90s timeout. Fix: guard matrix-seed под
    `if __name__=="__main__"` (ext-seeds юзают только pm-хелперы + re-mint boot, не module-seed).
    Блокирует vpc list-filter-d (6) + часть nlb-ext.
  - **grant-materialization EC** (compute list-includes ~9, registry repo-create ~4) — known EC tail.
  - **token TTL**: jwtBootstrap 1h, SA-matrix RS256 ~4h — reseed перед прогоном (prodseed минтит fresh).

## CI-flow port (2026-07-24) — geo-seed в setup.sh, НЕ только prodseed (критично!)

> [!important] prodseed-only фикс НЕ покрывал CI
> CI e2e-newman сеет через `newman-parallel.sh → tests/authz-fixtures/setup.sh` (dev-mode
> HS256), **НЕ через prodseed_matrix.py** (мой production-strict local flow). geo-seed в
> prodseed (ec245e9) до CI не доезжал → CI унаследовал бы тот же geo-gap. setup.sh лишь
> задавал `existingZoneId=ru-central1-a` как env-default, но zone НЕ создавал.

**Fix (commit `b489346`, pushed redesign/integration):**
- `setup.sh` — `api_internal()` (:18081 mux) + block **5d `seed_geo_baseline`**: POST
  `/geo/v1/internal/{regions,zones}` (system_admin@cluster=JWT_BOOTSTRAP, готов после block 5b),
  GET-confirm durability, идемпотентно (AlreadyExists толерируется), ДО zone-dependent block 11/12/13.
- `newman-parallel.sh` — прокидывает `INTERNAL_BASE_URL` (:8081 mux, уже port-forwarded) в setup.sh.
- `seed-nlb-fixtures.sh` — репойнт zone/region резолва `/compute/v1/zones`→`/geo/v1/zones` (compute
  дропнул zones в редизайне; stale-путь молча маскировал gap).
- `geo-data-migration-job.yaml` — doc-truthfulness: комментарий ложно заявлял «миграция сеет baseline».
Валидировано: geo Internal POST/GET-confirm path против живого стенда (region durable, 4 zones);
все 3 скрипта bash -n clean.

> [!success] CI-verify PASSED (run 30063062957, 2026-07-24)
> e2e-newman на redesign/integration: **vpc/compute/nlb/geo гейты ЗЕЛЁНЫЕ** (+ dev-up, coverage,
> proto-coverage). geo-seed в setup.sh отработал → zone-dependent creates прошли (раньше все
> фейлили "Zone not found"). Доказывает фикс end-to-end в CI dev-mode, не только локально.
> Осталось red (хвост редизайна, НЕ geo-related): iam ~50 (EC create→Get 404 + test-infra
> api.kacho.local ENOTFOUND ×8 + test-design RBACSG-plain404 ×7 + возможный channel-leak ×4),
> storage 1 кейс (VOL-OBJSELF broken objself-token, 74 assert; остальное storage 0-fail),
> registry 4 (repo-create EC). Триаж — ci-red-triage workflow.

> [!warning] Rule #16 gap (flagged, НЕ фикшу mid-marathon): CI-стенд = **dev-mode** (values.dev:
> authMode=dev, HS256, sslmode=disable), НЕ production-mode. Правило #16 требует production-mode
> ВЕЗДЕ (вкл. CI). Флип CI→production-strict (values.dev-prod + prodseed RS256) — крупная отдельная
> задача (унифицировала бы два seed-flow в один). Задокументировано как известный долг; не dangling-issue.

## Status
- [x] root: greenfield geo baseline не засеян (deploy-gap) · [x] ручной seed → compute 60→2
- [x] **permanent fix — local prodseed (owner-choice: newman-пререквизит, НЕ миграция)**: `prodseed_matrix.py`
  `_seed_geo_catalog()` сеет region ru-central1 + zones a/b/c/d via geo Internal admin RPC
  (:18081, jwtBootstrap) сразу после bootstrap-mint, идемпотентно. Commit `ec245e9`, pushed.
  Валидировано: delete geo catalog (count=0) → prodseed авто-пересеял 4 zones.
- [x] **permanent fix — CI setup.sh port** (`b489346`): geo-seed в CI seed-путь (см. «CI-flow port» выше).
- [x] **ext-seed guard** (`2c709b7`): prodseed module-seed под `if __name__=="__main__"` — import
  ext-seeds 4мин→1.2s (не re-runs matrix); разблокировал vpc list-filter-d + nlb-ext.
- [x] nlb geo-unblock подтверждён (TG create прошёл region-validation после geo-seed;
      spot-check "health_check required" = дошёл до field-validation). registry аналогично.
- [ ] full nlb/registry suite validation (нужен полный re-seed; harness-constrained ~40мин)
- [x] residual ~9 compute list-includes = **marginal read-your-writes EC flake** (не product-баг):
      single-create probe list-includes=true @65ms (материализация fast); НЕ cache (TTL 1s хуже:
      6 fails +transients); при ~30 disks per-binding O(N) read быстрый (30 rows). 2/325 disk=0.6%,
      2 specific steps (lst-includes-lst15, list-filtered-lst4) occasional >retry — known EC tail,
      bounded-retry обычно покрывает. Не marathon-end-fixable; focused-followup если критично.

#kacho-geo #kacho-deploy #kac #fix #migrations
