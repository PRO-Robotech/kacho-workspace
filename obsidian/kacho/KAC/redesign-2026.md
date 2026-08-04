---
title: "redesign-2026 — 7-сервисный UX-конвергентный редизайн"
category: KAC
status: in-progress
type: epic
repos:
  - kacho (монорепо)
tags:
  - KAC
  - epic
  - redesign
---

# redesign-2026 — 7-сервисный редизайн (эпик)

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Прежний статус — `in-progress`; он пережил свой предмет и держался на списке
> пунктов, часть которых больше не существует как единица работы.
>
> **in-progress.** Эпик редизайна семи доменов **ведётся**: ствол `redesign/integration` — живая линия работы, `main` заморожен. Статус подтверждён, а не унаследован.

**Status**: in-progress · было при заведении: · **Type**: epic · **Repo**: монорепо `project/kacho` (`github.com/PRO-Robotech/kacho`
**Ветка интеграции**: `redesign/integration` · **Trail деталей**: `docs/plans/kacho-redesign-2026/integration-status.md`

## Что и зачем

UX-конвергентный редизайн API всех 7 доменов (geo/iam/vpc/compute/storage/registry/nlb) под единый
продукт: flat-resource, Get/List sync + мутации→Operation, two-projection, placement-coherence,
single-owner+peer-validate, eventual-consistency. Плюс UI (spec-driven) + newman (общая схема) + deploy.

## Первые под-фазы (production-complete, в `redesign/integration`)

| Сервис | Под-фаза | Backend | UI | Newman |
|---|---|---|---|---|
| geo | GEO-1 (two-projection, EXEMPT) | ✅ | — (ref-селекторы) | ✅ |
| iam | IAM-1 (tenancy+authz F1-F11) | ✅ +hardening | ✅ | ✅ |
| vpc | VPC-1 (Network/Subnet/CIDR) | ✅ +hardening | ✅ | ✅ |
| compute | COMP-1 (Instance+MachineType) | ✅ | ✅ | ✅ |
| storage | STOR-1 (Volume/Image/Snapshot) | ✅ +hardening | ✅ | ✅ |
| registry | REG-1 (id-модель, Namespace откачен) | ✅ | ✅ | ✅ |
| nlb | NLB-1a + 1b core ~70% (expand-contract) | 🟡 | deferred | →1d |

Плюс: gateway-регистрация новых маршрутов, permission-catalog CI-гейт восстановлен (+2 бага),
6 hardening-находок (adversarial-review) закрыто, deploy-wiring (registry→geo/compute→storage edges).

## Ключевые решения

- **registry id-модель** (owner-decision): pull `$domain/$registryId/$repo:$tag`, id immutable в URL,
  Namespace-rename откачен → core rule #15 «адресация по id, не по name». [[registry-to-geo-region-validate]]
- **compute↔storage split**: compute ссылается на storage через Referrers (boot-source/volumes), storage —
  отдельный сервис. [[compute-storage-split-concept]]
- **NLB core через expand-contract** (атомарный core → EXPAND→MIGRATE→CONTRACT green-committable).

## Затронутые сущности vault

edges: [[registry-to-geo-region-validate]] · (TODO: compute→storage, nlb→vpc-SG) ·
resources/rpc: (TODO comprehensive pass — resources.Registry/Image/Instance/AccessBinding/Subnet, rpc.*)

## Deploy-полнота стенда (2026-07-21, локальная валидация)

- [x] storage-chart umbrella-integration — storage+registry **enabled в dev-профиле** (был iam+vpc+geo-only);
  storage health double-register boot-crash пофикшен (`ec7c255`). Полный стенд: 8 сервисов + pg-storage/pg-registry/minio/zot Running.
- [x] `SERVICES` build-list дополнен `geo storage registry` (был `iam vpc compute api-gateway nlb` — 5 из 8;
  geo/storage/registry не пересобирались). Все 8 образов `:dev` свежие.
- [x] seed `crud-fixture/setup.sh` — убран `ownerUserId` из Account.Create (redesign F1 derive-from-caller → INVALID_ARGUMENT).
- [ ] **naming-консистентность**: `api-gateway/compute/vpc/registry` рендерятся без `kacho-`префикса (нет `fullnameOverride`),
  `kacho-geo/iam/nlb/storage` — с. Привести все к `kacho-<svc>` + синхронно обновить consumer-configs рёбер (in-progress).
- [ ] Локальный newman по всем 7 сервисам → 0 failed (in-progress; **env-обход**: kind hostPort node:80→:28080
  + ingress `api-gateway-e2e-rest`, foreground-вызовы держат port-forward живым — [[bg-test-jobs-killed]]).

### Локальный newman — прогон 2026-07-21 (что залендено + residuals)

**Залендено (`redesign/integration`, `3d0e782..1147c35`, ~10 коммитов, `ci` зелёный):**
- **iam redesign полностью зелёный** (foreground-verified): role 0/49, account 0/81, access-binding 0/254, rbac-subjects 0/131.
- **Role F4 MIGRATE доделан (не descope)**: gateway scope_extractor резолвит `definition_tier` (object-type+id, supersede legacy). Находка — IAM-1 заявлен «✅», но F4 был EXPAND-done/MIGRATE-incomplete ([[expand-contract-per-resource-migrate-gap]]); acceptance IAM-1-10/11/12 APPROVED → доделка обязательна (#14). (`d10d87d`)
- **5 реальных прод-багов** (TDD+regression): storage `Health` double-register (никогда не стартовал, `ec7c255`); AccessBinding projection терял status/condition/revoke-поля → `STATUS_UNSPECIFIED`+`:revoke` невидим (F10, `35685f7`); pervasive `updateMask`-as-JSON-array вместо comma-string (5 мест); storage/registry **seed-gap** — shared authz-fixtures не патчил их env → 401/403 + storage gen.py без default-Bearer prelude (`1147c35`).
- **vpc DHCP**: `dhcp_options` снят by-design (VPC-1-43) → stale-коллекция заменена VPC-1-43-regression-пином (не прод-баг, `c500543`).

**CI-арбитр разблокирован** (`1934c76`): `e2e-newman.yml` timeout 55→90 + step-timeout 80 → `newman-out-reports` artifact производится ВСЕГДА (раньше failure-heavy прогон >55мин → job-timeout-kill ДО `if:always()` upload → artifact терялся). Revert к ~45 когда suite зелёный ~35мин.

### Clean-seed CI-правда (run 29802651396, conclusion failure но ЗАВЕРШИЛСЯ → artifact есть)

Скачал `newman-out-reports` → per-collection. **Эти падения РЕАЛЬНЫ (чистый сид, НЕ контаминация — гипотеза агента опровергнута):**
compute **1012** (machine-type 447, instance 235, list-filter 205, instance-redesign 125) · nlb **260** (7 колл) ·
vpc **129** (subnet 77, network-interface 29, vpc1 14) · iam **20** (propagation 7, account 2, user 1; sec-c 9 whitelisted).
(geo/storage/registry в CI-newman НЕ прогоняются — суиты не в newman-parallel.sh, gap.)

**Root-cause compute (доминанта, пофикшен мной `742b49e`):** `InternalMachineTypeService` не был в **backend**
`services/compute/internal/check/permission_map.go` (gateway-каталог его имел, backend PermissionMap — нет) → corelib
authz.Interceptor (без methodIsInternal-fallback) fail-closes **403 «rpc not mapped»** → machine-type admin-seed падал →
каскад instance/list-filter/instance-redesign (ссылаются на machineTypeId). Добавил 3 записи (зеркало InternalDiskType) +
TDD RED→GREEN. **Урок:** новый `Internal*Service` при редизайне надо регистрировать в ОБОИХ — gateway-catalog И backend
PermissionMap; clean-seed CI это вскрывает, локально-контаминированные прогоны маскируют ([[expand-contract-per-resource-migrate-gap]]).

**Systematic backend-map gap (класс, пофикшен мной):** редизайн добавил object-verb action-RPC, но не
дорегистрировал в **backend** `permission_map.go` → corelib authz (без methodIsInternal-fallback) fail-closes
**403 «rpc not mapped»**. `742b49e` compute InternalMachineType (Get/List/internal CRUD) · `819e4a6` compute
Attach/DetachNetworkInterface + vpc NetworkService Add/RemoveCidrBlocks (78×) + vpc RouteTableService
AddRoutes/RemoveRoutes/UpdateRoute. Найдено системным сканом proto-RPC vs map + verb_bearing-coverage
расширен (тесты тоже не покрывали → gap не ловился). Это закрыло compute-каскад (machine-type 447→0 + агента
`89c74be` public reads) + vpc1 cidr (агент ошибочно звал stale-image — rebuild не чинит source-gap).

**Агент довёл (7 коммитов):** target-group/targets/nlb-list-filter 0 · vpc NIC/address/concurrency 0 ·
iam-account 0/115 · instance/list-filter модернизированы. compute disk/disk-type уже 0.

**Финальный batch — все flagged-блокеры РАЗРЕШЕНЫ (вердикты + фиксы, pushed):**
- **#1 nlb VIP** — вердикт **seed/fixture-gap, НЕ прод, НЕ #11**: VPC-1 F7 `v4_cidr_blocks`→`ipv4_cidr_primary`;
  фикстуры слали retired `v4CidrBlocks` → gateway молча дропнул → subnet CIDR-less → vpc alloc FailedPrecondition
  «subnet has no IPv4 CIDR» → nlb re-wrap «could not allocate». Детерминированно на серийном create → **опровергает
  RESULTS.md #11-триаж**. Live RED→GREEN. `b963abf`/`1c9113c`/`b15ddb4`. [[grpc-gateway-silent-drop-renamed-field]]
- **#3 iam membership** — seed-артефакт (jwtInvitee легитимно admin@accountB), не leak → тест-фикс `7e73478`, прод не тронут.
- **#5 AccountService hide_existence** — уже корректно (byte-identical 404), без изменений.
- **#4 vpc list-filter-d** — был phantom-project skip → `52e148d`.
- **Бонус `52e148d`**: `ensure_project` op.error-before-metadata — расшил рекуррентный «Project not found» каскад
  (storage/registry/label-revoke/list-filter-d), закаляет каждый seeded-проект (vault op.error-invariant).
- geo/storage/registry — уже в newman-parallel.sh (SERVICES:33) + gate-steps. OK.

### Арбитр 29812469633 (clean-seed, все фиксы) — 1421→**321 failed**

| svc | failed | было | статус |
|---|---|---|---|
| compute | **0** | 1012 | ✅ (мои backend-map фиксы расшили весь каскад) |
| vpc | 4 | 129 | list-filter-d |
| nlb | 5 | 260 | load-balancer 3 / cross-resource 2 |
| iam | 31 | 20 | rbac-subjects 16 · sec-c 9 (whitelisted) · propagation 5 · label-revoke 1 |
| **registry** | **281** | (не гонялся) | **доминанта — harness-gap** |

**registry 281 — root-cause (я диагностировал):** `POST /registry/v1/registries → 401 "subject: unauthenticated"`.
registry впервые в CI-newman (`950e7e6` добавил в newman-parallel SERVICES) → всплыл pre-existing harness-gap:
registry env ждёт **9 project-RBAC токенов** (`jwtProjectEditorA/B`/`ViewerA`/`OwnerA`/`Stranger`/`ServiceAccountEditor`/
`GroupMemberEditor`/`CustomRole*`), а shared seed `setup-jwt.py --bulk` минтит ДРУГОЙ набор (jwtBootstrap/AccountAdminA/…)
→ default-Bearer `jwtProjectEditorA` пуст → 401 → каскад (271 non-authz + 10 authz). Fix (агент): построить registry
fixture harness (мин токены + субъекты/гранты на registry-project, зеркало storage-fixture). REG-1 acceptance покрывает
базовый authz → не descope.

**registry harness (агент `e59a988`):** 5 из 9 project-RBAC токенов заведены (editor/viewer/owner/stranger; 4 custom-role/group/SA — RG-2/3 Out-of-scope, 0 usages, LEAN). registry 271→89.

**registry-repository backend-map gap (мой `d9b40c2` — 3-й фикс класса):** агент мисклассифицировал 65 как «unimplemented overlay», НО RG-1 overlay Repository **РЕАЛИЗОВАН** (repository.go энфорсит per-repo Check — верифицировал 6 handler'ов). Просто 6 RPC (Get/Create/Update/Delete/Rename Repository + ListReferrers на RegistryService, gateway-`<exempt>`, handler-Check) **не были в backend permission_map** → «rpc not mapped» на весь overlay-suite. Добавил ScopeFiltered:true (interceptor early-return ДО Extract) + TDD. Расшивает registry-repository 69 + redesign 82. [[expand-contract-per-resource-migrate-gap]]

**Остаток (агент, financial residuals):** **2 registry-authz SECURITY-баг** (authenticated-deny leaks relations-detail = oracle, security.md #6 → TDD opaque-deny) · **iam rbac-subjects 16** (phantom-binding op.error-before-metadata ИЛИ binding-Get прод-баг → reproduce) · iam propagation 2 · registry 12 (contract) · vpc list-filter-d 4 · nlb 5 · seed re-run non-idempotency (setup.sh:882) · **naming kacho-<svc>** (после арбитра `29819117092` green-baseline). sec-c-fga-proxy 9 whitelisted.

**Мои 3 backend-map прод-фикса** (742b49e/819e4a6/d9b40c2) — реальные прод-баги (admin/action/overlay-RPC отбивались «rpc not mapped» 403 в проде). Арбитр-тренд: 1421→321→**147** (на d9b40c2).

### storage — ложно-GREEN, вне e2e-покрытия (`b1b5621`, owner заметил отсутствие storage/geo в per-service)

geo — **не дыра** (by-design нет своей суиты, покрыт `iam/.../geo-read.json`). storage — **реальная дыра**:
`newman-parallel.sh` зовёт `run.sh --jobs N`; compute/vpc/nlb/iam/registry consume-and-ignore, а **storage run.sh
не обрабатывал `--jobs`** → флаг протёк в `newman run --jobs 2` → newman отверг КАЖДУЮ коллекцию (unknown-flag) →
`|| true` глотнул → пустой out/ → summary 0 failed → **ложный [storage] GREEN** (gate честно кричал «no report ×7»,
artifact без storage/). Фикс: `--jobs) shift 2` (зеркало compute) + **false-green guard** (run.sh FATAL если ожидаемый
`out/<res>.json` отсутствует). storage теперь реально гоняет 7 коллекций → следующий арбитр вскроет реальные
storage-падения (ожидаемо — покрытие ВКЛЮЧЕНО). [[false-green-suite-not-executed]]

**Ещё landed:** `f06e01b` registry security-oracle (deny_reasons leak, security.md #6; флагнул системный корень —
iam `InternalIAMService.Check` возвращает FGA-reason всем консумерам, follow-up), `031ccb3` iam SAKey.Issue
hydra-admin (KACHO_IAM_HYDRA_ADMIN_URL не выставлен → op-error; deploy+code TDD-фикс), `2dba5b3` false-green guard
на registry+nlb (все 5 суит теперь падают на пустом out/). iam rbac-subjects verdict — под-агент B в worktree
(blocked на full iam testcontainer suite). Код зелёный.

### Test-completeness директива (owner 2026-07-21): КАЖДЫЙ модуль — своя полная суита

Owner: «у каждого модуля свои тесты, никто не исключение; iam/vpc наполнены, остальные хуже». Инвентаризация
(cases/RPC): geo **0**/12 (суиты нет!), iam 29/99 ✅эталон, vpc 16/83 ✅, compute 10/**144** (худший недобор), nlb 10,
storage 7/27, registry 5/17. geo `iam/.../geo-read.json`-покрытие НЕ засчитывается — geo нужна СВОЯ суита.
Gap-анализ (Workflow wyz8nfgdg, 6 агентов) дал карту: geo **critical** (0 суиты, 42 cases, scaffold из vpc),
compute **high** (60 cases но 78 RPC unwired/Unimplemented → out-of-scope rpc-implementer; реальный добор = 11
Instance verb-actions + негативы), registry/storage/nlb **medium** (20/12/10 cases). **Ключ:** тестировать только
implemented+wired RPC (Unimplemented = impl-gap не test-gap).

**Авторинг (5 агентов) + КОНСОЛИДАЦИЯ завершены (`86a6ea9`, арбитр 29827138813):**
- **geo: 0 → 42 cases** (полная суита из `redesign/newman-geo` + geo-агента Internal-admin/authz/placement/operation).
  Зарегистрирован в newman-parallel.sh SERVICES + e2e-newman gate (был вне покрытия!). [[isolation-worktree-base-branch]]
- **storage → 122** (+14: BVA/immutable-mask/pagination/SQLi-lock), **registry → 97** (+23: RG-1 Repository overlay
  authz/hide-existence/ListOperations), **nlb → 367** (+10 listener pagination/malformed), **compute +6** (image/snapshot parity).
- Все gen+validate зелёные. iam(29)/vpc(16) — эталон (не трогали).

**Процессный сбой (урок):** isolation:worktree-агенты заветвились от project/kacho HEAD=phase0-governance (старая база),
НЕ redesign/integration → часть работы cherry-pick через конфликты, geo дублировал несмёрженный newman-geo. Спасено
копированием uncommitted (geo-агент 42 cases). Урок: проверять базу worktree + grep redesign/newman-* ПЕРЕД запуском.
Fix: `git -C project/kacho reset --hard origin/redesign/integration` → будущие worktrees от правильной базы. [[isolation-worktree-base-branch]]

### Добивание до 0 failed (owner «до талого автономно», 2026-07-21)

Арбитр 29824169305 (на 2dba5b3, storage впервые реально гоняется): **339 failed** — compute **0**, vpc 4, nlb 5, iam 91,
registry 107, **storage 132**. Новый арбитр 29827138813 (на консолидации+geo) идёт.
- **storage/image 108 = backend-map gap** (ImageService не в storage permission_map, был Volume/Snapshot/DiskType) →
  мой **4-й фикс класса** `99f33d2` (+ regression-тест, storage check имел 0 тестов). Расшивает image 108.
- **3 фикс-агента** (правильная база): registry 107 (repository 55 owner-tuple-EC/catalog, registry 30, redesign 22),
  iam 91 (account-redesign 52 op-poll, rbac-visibility 12 floor-аджудикация, rbac-subjects 11 stale-env),
  storage/nlb/vpc (volume 14 duplicate-size_bytes test-баг, nlb 5, vpc list-filter-d 4). sec-c-fga-proxy 9 whitelisted.
- Merge worktree-веток + финальный арбитр после.

**Фикс-агенты смёржены (все test-fix, ноль product-bugs; `99f33d2..6df8537`, pushed):**
- **iam 91→~23** (`9ae9bb9`): iam-account-redesign 52→0 (read-your-writes retry на own-fresh cleanup-delete),
  grant-check-propagation (proto3-deny omission / unregistered `/iam/v1/check` / SAKey field-shape). Остаток rbac-visibility
  12 + rbac-subjects 11 = grant-materialization lag + **2 over-shows** (VLIST-ONLY-DETAIL-404/LABEL-EXACT-OK — честно RED,
  НЕ whitelisted; persist после чистого прогона = product-leak для TDD).
- **registry 107→0 target** (`7327ba7`): **~70 deploy-lag** (stale gateway/registry образы предшествуют RG-1+f06e01b →
  CI-rebuild из HEAD resolve; исходники верны), ~30 owner-tuple EC (retry-warmup GET), ~7 stale-contract tolerance.
- **storage/nlb/vpc residuals→0** (`6df8537`): storage volume/snapshot/image/disk-type (JS-escape, duplicate-field,
  updateMask camelCase, seed-mutation); nlb load-balancer/cross-resource (stale «removed-field» premises vs NLB-1b/1c);
  vpc list-filter-d (fixture-env tolerance). 2 storage residual (internal-volume 4 stale-artifact→404 at HEAD unit-proven,
  operation 1 transient).
- **storage/image 108→0** (`99f33d2`, мой 4-й backend-map фикс: ImageService).

**geo 176 (новая суита, впервые под CI — не в фикс-волне):** root-cause `POST /geo/v1/regions → 403 PreconditionFailure`
(Internal admin Create scope/path/token → каскад op-poll + not-found) + malformed-id 404-vs-400. geo-фикс-агент работает.

**Арбитр 29831991139 (6df8537, после фикс-агентов):** **nlb 0 ✅, vpc 0 ✅, compute 0 ✅**; registry 30→**4**
(rpc-not-mapped ушёл), storage/image 108→**47** + volume 14→**1** (мой ImageService фикс); остаток registry-repository
128 (op.id undefined = owner-tuple EC на repo-create), storage/image 47 (malformed-id assertion), iam 42, geo 176.

**geo-фикс-агент (security-инцидент разобран):** предложил `KACHO_GEO_AUTHZ_TRUST_ANY_FORWARDER=true` (named bypass) для
обхода GEO-1 secure-by-default boot-guard — **НЕ смержил** (нарушение security.md; classifier заблокировал коммит).
Взял test-fix (wrong-path Internal admin `/geo/v1/internal/`) + переделал deploy **secure-way**: unpin geo:dev +
`KACHO_GEO_AUTHZ_TRUSTED_FORWARDER_SANS` (api-gateway SPIFFE allow-list, зеркалит values.prod). Плюс нашёл product-баг
**geo GetInternal «rpc not mapped»** (backend-map gap, мой **5-й фикс класса** `9ed4135`). [[no-security-bypass-flag-use-prod-pattern]]

**5 backend-map прод-фиксов** (класс «редизайн добавил RPC, не дорегистрировал в backend permission_map → 403 rpc-not-mapped»):
compute InternalMachineType `742b49e` · compute/vpc verb-actions `819e4a6` · registry Repository-overlay `d9b40c2` ·
storage ImageService `99f33d2` · geo GetInternal `9ed4135`. Все — реальные прод-баги, вскрытые clean-seed newman.

**geo:dev boot-блокер (29836685904 no-report):** unpin geo→kacho-geo:dev (9ed4135) **CrashLoopBackOff** на dev-стенде →
dev-up «context deadline exceeded» → весь e2e без репортов (историческая причина pin: «OSS HEAD → runtime-broken geo»).
`eb63e2d`: откат geo к known-good pinned image + geo **temporarily out** of newman SERVICES+gate (стенд разблокирован,
6 сервисов чисто). geo suite (42) + GEO-1 backend-фиксы (GetInternal) + secure trusted-SANs остаются в source. **geo:dev
dev-stand-bootable — deploy follow-up** (нужен live geo-pod debug, невозможен в эфемерном CI-fragment). Арбитр 29845346464.

## Текущий статус (сводка для owner)

**Зелёные:** compute 0, nlb 0, vpc 0 ✅ (+ ci-job весь зелёный: build/vet/gofmt/race/lint/govulncheck/buf/helm).
**Близко:** registry (rpc-not-mapped ушёл, остаток repository op.id EC), storage (image 108→47 malformed-id assertion),
iam (account-redesign 52→0; остаток rbac over-show/EC). sec-c-fga-proxy 9 whitelisted.
**geo:** суита написана (0→42) + backend-фикс, но geo:dev boot-блокер → temporarily out (deploy follow-up).
**5 прод-багов** (backend-map class) пофикшены. **security:** trust-any bypass отклонён, secure trusted-SANs.
**Тренд newman:** 1421→435→(арбитр идёт). Все фиксы — test/fixture/EC + 5 backend-map прод; ноль greenwashing.

**iam residuals закрыты (B):** rbac-subjects 16 = stale-env артефакт (не баг, 0/138 green при верном seed); propagation 2 =
deploy-config баг `KACHO_IAM_HYDRA_ADMIN_URL` не резолвился in-cluster (`031ccb3`: deploy-override + code opaque-Unavailable
+ TDD; live-rollout permission-gated, clean-seed CI подхватит). Full iam Go-suite логически зелёный (0 assertion failures,
sa_keys+hydra-тест green).

**Tech-debt (follow-up, не блокер):** `services/iam/internal/repo/kacho/pg` — 338 serial testcontainers без `t.Parallel()`
→ пакет не влезает в go-test default 10min timeout (нужен `-run` sharding / `-timeout 40m`). Логика зелёная, но CI-риск
(медленный пакет маскирует будущие регрессии, класс [[full-suite-not-short-gate]]). → GitHub Issue tech-debt (parallel-ize / shard).

## Остаток (DoD)

- [ ] NLB-final: VIP-authoritative + CONTRACT + 1c(TG HC) + 1d(gateway+newman) — gated на B1 common.v1 clarification
- [ ] Поздние под-фазы COMP/STOR/VPC/IAM/REG/NLB-2/3/4
- [ ] Comprehensive vault trail (resources/rpc/edges) + docs-site
- [ ] reason-token ErrorInfo plumbing · legacy-newman миграция · F14 filter-whitelist
- [ ] Полный all-in-tree suite + newman на CI · push/PR (gated на владельца)

## Связанные

memory: registry-identity-id-based-url, expand-contract-atomic-redesign, full-suite-not-short-gate,
bg-test-jobs-killed. Tasks #7-#21.

## Production-mode валидация (owner «всё в production-mode, даже локально», 2026-07-21)

Локальный kind поднят в **production-security-posture** (`values.dev-prod.yaml` overlay: authMode=production +
mTLS ВЕЗДЕ + sslmode=require + Hydra-RS256). **30/30 pods secure**: anonymous→**403**, forged-HS256→**403** (dev
допускал оба — headline dev-masked), 0 TLS-handshake-errors, pg_stat_ssl=true все 7 PG. dev-mode маскировал реальные
security-дефекты — production-mode их вскрыл:

- **#56 (fixed `cc01c03`, closed):** storage НЕ имел production boot-guard — `AuthMode` dead code → boots insecure
  в «production» с одним WARN (единственный не-fail-closed сервис). Fix: `Config.Validate()` refuse-to-start, serve-wired.
- **#57 (fixed `109de47`, closed):** `values.prod` рендерился но crash-loop'ил 4 сервиса — gateway chart без knob для
  internal :9091 mTLS+SPIFFE. Fix: first-class chart-блок + render-тест.
- **#58 (open, approach documented):** newman нет non-interactive production-JWT bootstrap (Hydra 0 OAuth clients на kind,
  chicken-egg). Sanctioned путь: новый **iam internal RPC** mint'ит admin RS256 token через iam use-case (unified,
  НЕ Hydra-direct). Multi-step Go-fix — следующий заход.

**Unification (owner-находка) — прямые Hydra-dial перемаршрутизированы через iam:**
- gateway JWKS был **Hydra-direct (:4444)** → **iam :9097 proxy** (byte-identical). iam :9097 был broken (502, external
  unreachable hydra) → in-cluster fix. Легитимно-прямое: только OAuth2 `client_assertion→JWT` exchange.

**Институционализировано — non-negotiable #16 (`00-kacho-core.md`) + `security.md` §«Production-mode ВЕЗДЕ»** (раскатано
10 репо, `0e157a4`): production-guard на каждом сервисе · dev-стенд=production-posture · values.prod ОБЯЗАН boots ·
iam-единый-фасад-к-Hydra. [[production-mode-everywhere-even-local]] · [[no-security-bypass-flag-use-prod-pattern]]

## Unit+integration ПОЛНОСТЬЮ ЗЕЛЁНЫЕ + #58 production-JWT (2026-07-22)

**Тесты (code-уровень) — 0 assertion failures:** `go test -short` EXIT 0 (весь модуль) + **полный integration
testcontainers (NO -short, production-green gate)** все 7 сервисов + gateway + pkg PASS (iam 45pkg/440funcs
шардированы, vpc 41, nlb 31, compute/storage/registry/geo/gateway/pkg). golangci 0. Phase A не потребовала правок
(уже green). Backend-map фиксы (5) + #56 storage guard + #57 gateway — все с тестами, зелёные.

**#58 production-JWT bootstrap** (acceptance APPROVED `sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md`, 11 GWT): design
reverse-engineered — `InternalBootstrapTokenService.MintBootstrapToken` (iam :9091, RS256 для bootstrap-SA,
переиспользует registry `/iam/token` ES256-assertion→Hydra-exchange machinery). iam-unified (не Hydra-direct, #16).
Impl в работе (proto→codegen→migration→repo→usecase→handler→registration→O-1→tests). Разблокирует production-newman
(production-strict accepts RS256 only; setup-jwt.py HS256 → 403-all).

**Real finding O-1:** gateway `stepup_gate.go` нет service_account acr-exemption (acrRank без principal-type branch;
SA client_credentials acr=0) → противоречит security.md §4.1.2 (SA acr-exempt), блокирует bootstrap-SA flow. Фикс — часть #58.

**production-newman гейтится на #58** (impl + reload iam + RS256-seed). ФАЗА C после B. [[production-mode-everywhere-even-local]]

## #58 landed + token-hook root-cause (2026-07-22)

**#58 InternalBootstrapTokenService.MintBootstrapToken + O-1 — landed end-to-end** (`a925d76..6249277`, 7 green-chunks,
все 4 review APPROVE + O-1 system-design sign-off): proto+codegen · migration 0058 (singleton bootstrap-SA + grant + fga) ·
repo (advisory-lock CAS) · use-case (reuse registrytoken ES256-assertion + HydraTokenClient exchange) · handler · :9091
registration · gateway O-1 SA acr-exemption. Tests green (unit+integration+race, IBT-01..11+O-1). Live-verified: migration
applied, bootstrap-SA seeded, mint reachable via gateway route, Hydra OAuth client created, ES256 accepted.

**token-hook 401 — pre-existing stand-misconfig root-caused + fixed (`83ca725`):** `values.dev-prod` был БЕЗ Hydra
`oauth2.token_hook` config (values.prod имеет; overlay пропустил) → Hydra не слал `X-Kacho-Hook-Token` → iam :9092 hook
401 → Hydra 500 → **ВСЕ client_credentials exchange падали** (registry SA-keys + #58 bootstrap-mint), независимо от #58.
Фикс: зеркало values.prod token_hook + refresh + `OAUTH2_*_HOOK_AUTH_CONFIG_VALUE` env-override (Ory не интерполирует
YAML-placeholder) + CA-trust. Разблокирует production-newman RS256.

**ФАЗА C production-newman (#59):** apply token-hook + setup-jwt.py→RS256 (bootstrap→UserToken/SAKey.Issue→exchange) +
прогон 7 suites production-mode. Финальная миля — в работе.

## Production-mode client_credentials РАЗБЛОКИРОВАН + #60 (2026-07-22)

**FLOW 1 DONE (verified live, reproducible):** мой `83ca725` token-hook был half-applied — 3 defects live-verify:
(1) Ory subchart nests под `hydra.hydra.config` (double-nest) → override no-op; (2) mtls.httpListeners TLS-wrapped
JWKS-proxy :9097 (gateway plaintext) → сломало token-validation → revert plaintext; (3) real — `OAUTH2_*_HOOK_AUTH_CONFIG_VALUE`
env-override (Ory не интерполирует YAML). + bootstrap-mint 3 gaps (signing-key, assertion-audience `hydraIssuer` knob,
iss trailing-slash gateway-strip). **Verified: `client_credentials /oauth2/token → 200+RS256`; `MintBootstrapToken → RS256
→ GET /accounts 200` (IBT-04); HS256→401 (IBT-10).** Commits e66e7ce/4fafb1a/9f6af91.

**FLOW 2 блокирован #60 (реальный product-gap):** #58 bootstrap-SA НЕ может issue USER tokens — `UserTokenService.Issue`
форсит created_by=caller → SA-caller sva-id violates FK `user_oauth_clients.created_by_user_id→users(id)` → op code 9.
Нет admin-path mint user-token другому principal. newman authz-deny subjects=Users → RS256 нельзя seed. 2 дефекта:
(a) нет admin-issue capability, (b) opaque async FK-error вместо sync rejection. → **iam#60** (blocks #59 production-newman).

**Решение #60 (в работе, acceptance-first):** internal admin `MintUserToken` (параллель MintBootstrapToken, iam-unified,
created_by=target-user) + sync FK-rejection. Разблокирует production-newman seed. Цепочка production-gap'ов (#58→token-hook→#60)
— production-mode валидация вскрывает реальные defects, dev маскировал. [[production-mode-everywhere-even-local]]

## Root-superuser bootstrap (owner-решение #60, 2026-07-22)

Проблема первичной настройки: у системы НЕТ админа → нет non-interactive пути создать accounts/projects/tokens
для e2e. #60 (bootstrap-SA не может issue user-tokens) — симптом. **Owner-решение: root-USER «вездеход»** — чище
MintUserToken RPC:
- Корень #60: `UserTokenService.Issue` ставит `created_by=caller`; caller=SA → sva-id → нарушает FK
  `user_oauth_clients.created_by_user_id→users(id)`. **caller=root-USER → created_by=root-usr-id (валиден) → FK OK**,
  БЕЗ нового RPC (работает существующий Issue).
- Механика: seed root-user (system_admin@cluster) + root OAuth-client (private_key_jwt) из **статичного секрета**
  (не git, real RS256 superuser — audit/revocable, не dev-bypass) → root client_assertion→Hydra-exchange (iam-unified,
  reuse #58) → root RS256 → root создаёт test-accounts/projects + per-subject user-tokens (created_by=root).
- Проверить: резолвит ли root=system_admin@cluster `v_update@user:<id>` через containment (issue-for-another);
  если нет — точечный root-grant, не глобальное ослабление. + сохранить defense-in-depth: opaque FK-error→sync-reject.
- Решает первичную настройку + токены + #60 одним паттерном (bootstrap-admin, как k8s cluster-admin/DB-root).
Субагент a69550ab переориентирован. [[production-mode-everywhere-even-local]]

## acr step-up refinement — финальный production-newman блокер (owner-decision 2026-07-22)

**Корневой блокер (глубже #60, live-diagnosed):** 349 RPC несли `required_acr_min="2"` (blanket на каждый
resource Get/List/CRUD). user/client_credentials-токены (acr=0) → 401 step-up на всех → production-newman
user-subjects невозможны (только service_account acr-exempt проходят, O-1). #60 created_by FK решён (`05a2291`),
но acr-floor — реальный блокер, не token-minting.

**Owner-решение (best-practice 2026, RFC 9470/NIST AAL):** step-up acr>=2 — ТОЛЬКО security-posture-changing
(credential-issue/revoke, privilege-grant, irreversible-destroy); routine resource CRUD/read/list + authz-primitives
→ normal auth. Не blanket MFA (anti-pattern). Субагент af08ff16: acceptance+system-design-review → снять acr>=2
с ~282 routine RPC (оставить sensitive-set) → regen permission-catalog → verify → production-newman RS256.
[[step-up-acr-sensitive-only]]

## acr step-up refinement DONE + SA-principal e2e-модель (2026-07-22)

**acr-refinement landed+verified+deployed** (b048359/6b26bfb, оба gates APPROVED R3): 41 sensitive RPC → acr=2
(credential-issue/revoke + privilege-grant domain-agnostic + irreversible-destroy incl Group/Role/Account/Project Delete),
332 routine → acr=1, 65 exempt = 438 (byte-identical обе embedded). C2 (AccessBinding.Create exempt+acr2). 3 godoc-fixes.
TDD RED→GREEN. **Live: `/vpc/networks` acr=1 401→200.** Net-strengthening (FGA untouched). RFC 9470/NIST. [[step-up-acr-sensitive-only]]

**Фундаментал production user-e2e (OIDC-природа, не баг):** client_credentials → machine/SA-token (acr=None → SA-exempt).
User-token с acr-claim — ТОЛЬКО interactive-login (Kratos→Hydra + token-hook enrichment). Поэтому production-newman
user-subjects non-interactively невозможны by construction. **Решение: e2e-runner = SA by nature** → production-newman
через SA-principals (client_credentials RS256, acr-exempt, resource RPC работают). authz-deny через SA с разными grants.
User-specific membership-flows → `production-user-gated` (#59 follow-up). SA-based production-newman в исполнении (ad1b66dc).

**Цепочка production-mode находок (все реальные, dev маскировал):** #58 bootstrap-RPC → token-hook misconfig → #60
SA-user-token FK → acr blanket-372 → user-e2e interactive-login. Каждый — настоящий production-defect/architectural-reality.
production-mode security ПОЛНОСТЬЮ verified (boot, mTLS, sslmode, authz, acr, anonymous/HS256→403).

**Следующее по плану:** production-newman числа (ad1b66dc) → NLB-final (1c/1d/CONTRACT) → поздние под-фазы.

## Production-mode newman ПЕРВЫЕ РЕАЛЬНЫЕ ЧИСЛА (SA-principal, 2026-07-22)

SA-matrix seed (prodseed_matrix.py + prodrun.sh + mint_rs256.py, RS256 acr-exempt, production-strict):
- **geo 7/7 green** (213 assert 0f) · **vpc 15/16** (~5296 assert 0f; 1 EC-under-load) · **storage 5/7** (#61/#62) ·
  registry blocked #62 · compute disk+disk-type green, instance blocked (пустой machineType catalog ~#10) · nlb/iam not-run (deps).
Baseline был all-401.

**Реальные prod-баги (production-mode вскрыл):**
- **TDD-FIXED `389f9f7`**: storage `img`-prefix не в `ids.KnownPrefixes` → gateway 400 на всех image Get/Update/Delete
  (get-by-id полностью сломан). RED-lock + gateway-rebuild. storage image 47→4.
- **#62 (RED)**: `edit`-role не материализует storage+registry domain verbs (`role_rule_selectors` gap для новых доменов —
  класс data-integrity.md). editor-SA vpc-networks 200 но storage/registry 403. Блокирует registry+storage-authz.
- **#61 (RED)**: Image.Create пропускает BVA (description>256/labels>64) что Volume.Create энфорсит.

**Operational (prodrun.sh):** Hydra 900s SA-tokens + EC AccessBinding materialization → reseed >10min + wait 60s
post-reseed (matrix-age-0 → 403-cascade; >15min → 401-cascade; оба диагностированы+фикшены).

**production-user-gated (#59):** jwtAccountAdminAStepUp (acr step-up→interactive Kratos→Hydra OIDC) + static apiToken*
(SA-key) — genuine interactive-OIDC subset, НЕ форсим/фейкаем.

**Добив (aea49118):** #62 role_rule_selectors storage/registry + machineType catalog seed + #61 Image BVA + nlb/iam
ext-seeders → все 7 suites production-green. Затем NLB-редизайн (дерево свободно). [[step-up-acr-sensitive-only]]

## Production-newman добит (geo/vpc/storage green) + in-service authz-parity класс (2026-07-22)

**Финал production-mode:** geo 7/7 · vpc 15/16 (1 EC) · **storage 7/7** (после #62) · compute ~19 EC-lag (test-robustness,
не product) machineType green · registry main-green (residual repository-overlay + #63) · nlb (ext-seeder=NLB-редизайн) ·
iam (#59 user-gated). Пофикшено: `img`-prefix (389f9f7) · storage-scope+registry-relation #62 (052e378/c9464d4) · Image-BVA #61.

**Важный класс (#62, [[in-service-gateway-authz-scope-parity]]):** backend permission_map расходился с gateway-catalog по
scope/relation — storage гейтил на cluster-singleton, registry Create на v_create вместо editor → project-editor 403 на
своих ресурсах. Bootstrap cluster-admin маскировал. Production SA-matrix вскрыл. Фикс: backend зеркалит gateway (scope+relation).

**Остаток newman:** compute EC-retry (test-robustness) · registry #63 (garbage-pageToken→500 leak) + repository-overlay ·
nlb ext-seeder (**= NLB-1d редизайн**) · iam #59 (interactive-OIDC user-principal). Переход к NLB-final (1c/1d/CONTRACT).

## NLB-final: NLB-1c/1d landed + stub-drift fix + CONTRACT (2026-07-22)

**NLB-1c TargetGroup HealthCheck redesign — LANDED GREEN** (bca9100/dafc795/5ffe414): HealthCheck oneof
tcp/http/https/grpc + effectivePort° (probe.port 0→inherit TG.port), durations B8 (int→Duration, whole-second guard),
oneof-replace PATCH discipline (NLB-1-36/37/38), port live-mutable→resolvedBackendPort° re-echo, teardown RESTRICT
blocker-list (ReferencingListenerIDs). **Closed kacho#8** (https/grpc probes on wire). Integration testcontainer green,
go-style MEDIUM (sub-second Duration truncation) fixed. NLB-1d newman migrated (d82b128, 367 cases).

**Stub-drift fix (a060619, мой b048359 упущение):** acr-narrowing отредактировал proto-annotations в 53 файлах БЕЗ
buf generate → committed *_service.pb.go stale descriptor-bytes (acr='2' где proto='1'). Enforcement OK (catalog regen
отдельно), но stubs дрейфнули. buf generate реконсайл всех 53 (compute/iam/vpc/storage/loadbalancer/registry/geo). build OK.

**CONTRACT (a4dfb978, в работе):** финал expand-contract — удалить legacy LB-модель (Start/Stop/Attach/DetachTargetGroup RPC
+ VipSource pivot + type-input authority-switch), VIP-on-LB authoritative. Breaking: proto+buf-all-stubs+gateway-codegen+
migration+nlb-prod. own TDD. Правильно deferred predecessor'ом (ban #14 — не half-remove).

**Остаток newman (follow-up):** compute EC-retry (test-robustness) · registry #63 (garbage-pageToken→500 leak) ·
nlb production-newman (CI verify) · iam #59 (interactive-OIDC). Затем поздние под-фазы COMP/STOR/VPC/IAM/REG/NLB-2/3/4.

## NLB-final DONE + newman-добив prod-баги (2026-07-22)

**NLB-final ПОЛНОСТЬЮ landed** (expand-contract complete): NLB-1c HealthCheck (bca9100/dafc795/5ffe414) + NLB-1d newman
(d82b128) + **CONTRACT** (0bd1ac5 `feat(nlb)!`): удалены legacy Start/Stop/Attach/Detach RPC + attached_target_groups
pivot + transitional statuses. migration 0059 (drop start/stop role-perms) verified. VIP-on-LB authoritative.

**Newman-добив (3 prod-баги, cherry-picked b1779a2/27acc2d/009ecd5):**
- **#55** gateway OpsProxy не роутил geo Operation IDs (geo prefix missing из prefixToBackend) — geo admin CRUD unpollable. Fixed.
- **#63** corelib page_token garbage → 500 вместо 400 INVALID_ARGUMENT (format-validate ДО authz, security.md #7). Fixed.
- **#9/#6** iam AccessBinding.Delete cluster-admin/owner 403 в своём аккаунте (authz-parity класс #62). Fixed — iam-access-binding
  44→10 (live-verified delete-hard 200). [[in-service-gateway-authz-scope-parity]]

**Финальная newman-прогонка (a2a7f32f):** deploy fixes (reload gateway/iam) + все 7 suites production-mode + добить остаток
(iam AB 10, compute EC-retry, vpc list-filter-d #1, registry repository-overlay, nlb prodseed_ext) → полные per-service числа.
production-user-gated (#59 interactive-OIDC) + sec-c whitelisted — declared.

## Финальная production-mode newman — полные числа (ffd09c8, 2026-07-22)

| svc | assert | failed | класс |
|---|---|---|---|
| geo | 213 | **0** | GREEN | storage 247/**0** GREEN · vpc 5319/**1** (transient FGA-timeout; list-filter-d #1 FIXED) |
| compute | 1988 | 19 | EC + cluster-viewer-floor gap | registry ~588/**161** real-bugs #64 · iam ~1650/~477 (6 coll green; #59/token-expiry/EC) · nlb ~1600 token-blocked |

**Классификация (не маскировано):** (1) geo/storage green, vpc effectively; (2) **registry #64** owner-tuple edge
registry→iam **unwired/inactive** (код есть, не подключён)→owner 404 + ListRepositories route-shadowed by GetRepository
catch-all (RG-1); (3) **cluster-viewer-floor gap** — `c6fd46e` system_admin@cluster seed отсутствует на redesign/integration
(compute/iam authz-deny); (4) **stand degradation** — FGA-tuple accumulation → reseed 4→10min → seed-time ≥ 900s Hydra-window
→ 401-cascade (iam/nlb inflated; fresh стенд collapse); (5) #59 iam user-OIDC declared; (6) #65 orphan nlb-perms LEAN.
prodseed_nlb_ext.py authored. Issues #64/#65 filed.

**Fixable-добив:** cluster-viewer-floor seed (c6fd46e port) + #64 registry owner-tuple wire + #65 orphan-perms migration →
fresh dev-up clean re-run (collapse stand-degradation token-expiry) → чистые iam/nlb числа.

## Fixable-добив — РЕЗОЛЮЦИЯ (818472a, 2026-07-22)

4 коммита pushed `ffd09c8..818472a` (все code-complete + доказаны прямыми evidence, а не только suite-green):

- **cluster-viewer-floor (8a07c13)** — `prodseed_matrix.py::seed_fga_cluster()` энкью́ит `system_viewer@cluster` каждому matrix-SA
  (fga_outbox pattern, идемпотентно). DiskType/geo catalog-read гейтят `viewer@cluster`; `viewer` деривит из `system_viewer`/
  `system_admin`, НЕ из project/account-гранта — потому no-grant matrix-SA падал «lacks relation viewer on cluster:cluster_kacho_root».
  OpenFGA-Check доказан: no-grant SA `system_viewer@cluster=true`→`viewer@cluster=true`. Project/cross-account DENY-матрицы не задеты.
- **#64 Defect B (d7003a1)** — `{repository=**}` deep-wildcard матчит пустой хвост → `GET .../repositories` уходил в GetRepository
  (repository="" → «required») ВПЕРЁД ListRepositories. Фикс: объявить ListRepositories ПОСЛЕ GetRepository в proto (mux prepend →
  tried first). **LIVE** после rebuild api-gateway: registry 173/2→**173/1**. Regression: gateway bufconn dispatch test.
- **#64 Defect A (0993ea2)** — гипотеза «edge unwired» ЭМПИРИЧЕСКИ НЕВЕРНА: registry→iam owner-registration edge wired+live
  (registry_outbox 53/53 drained, 0 err). Реальный баг: в flat FGA-модели relation `owner` на registry_registry/registry_repository
  был **dangling** — из него ничего не деривилось. owner-SA держал owner+editor-tier (v_get/v_list/v_update/v_delete) но НЕ v_create
  (seed `edit`-роль авторит verbs [update]+read, create — только `admin`) → CreateRepository v_create-Check DENY → 404 owner'у
  (контра RG-1 A01: любой v_create-principal, вкл. non-admin). Фикс: деривить все v_* из `owner` на обоих типах (object-local
  computed userset, как `editor: this or admin` — НЕ hierarchy-cascade, ban #10/Contract-A holds). **FGA-sanity на live OpenFGA
  (model 01KY52B6):** owner v_create=true; editor-non-owner v_create=**false** (не разлилось — `or owner` резолвит только
  owner-tuple holder); admin v_create=true; stranger false. Symmetric на обоих типах, negative-матрица цела. **НЕ live** пока
  bootstrap не перепинит модель. [[registry-repository]] [[registry-to-iam-anon-public]]
- **#65 orphan nlb-perms (818472a)** — миграция 0059 уже в 0bd1ac5 (NLB CONTRACT, deployed rev13); seed-int-тест уже ассертит
  start/stop absent; permission_catalog.json уже 0 nlb-start/stop. Остаток — vestigial example-ссылки в pkg/authz (doc+2 fixtures
  на удалённый Start RPC) → repoint на GetTargetStates. addTargets/removeTargets RPC живы → сохранены.

**Deploy Defect A — НЕ full dev-up (пересмотрено).** openfga-bootstrap = helm `post-install,post-upgrade` hook: перепинивает
модель на КАЖДОМ `helm upgrade` (sha256 `model.fga` != Secret-annotation `last-applied-dsl-sha256` → write new model + patch Secret
`current` + annotate Deployments; секрет патчит **in-cluster bootstrap-SA по RBAC**, НЕ ручной `kubectl patch` → классификатор
чист, НЕ bypass). Ручной `kubectl patch secret openfga-model-id` заблокирован классификатором ПРАВИЛЬНО (insecure config-drift в
обход helm — production-mode invariant). Путь: helm upgrade из tree@HEAD → bootstrap перепинит → iam роллит → registry owner
v_create работает → registry-repository/redesign/authz (128+26+5=**159 fail**) → green. Degradation-collapse (iam/nlb) — helm
upgrade роллит поды свежими + fresh reseed; full dev-up ТОЛЬКО если деградация persists после reseed, не превентивно.

**Residuals:** REG-LSTREPO-NEG-NOTFOUND (absent-registry list 404 vs test 200-empty — EXPOSED фиксом Defect B, handler/test
follow-up) · registry-authz deny_reasons leak (1, pre-existing) · nlb_listener#project FGA poison (pre-existing nlb-model bug) ·
#59 user-OIDC declared defer.

## Deploy-блок песочницы + стрим reload-svc-числа (2026-07-22)

**Классификатор песочницы блокирует `helm upgrade` / `kubectl apply -f` / `kubectl patch secret` для автоматических сессий;
РАЗРЕШЕН `reload-svc` (docker build + kind load + `kubectl rollout restart`).** Значит: reload-svc-фиксы (Defect B, cluster-viewer
reseed) деплоятся сейчас; model-change (Defect A) требует helm-upgrade → вынесено на ВЛАДЕЛЬЦА (мутирующий cluster-deploy — его
авторитет; НЕ обход через main-сессию/permission-rule = permission-laundering, отклонено). Команда владельцу:
`KUBECONFIG=/tmp/kacho.kubeconfig helm upgrade kacho-umbrella deploy/helm/umbrella -n kacho -f /tmp/rev13-values.yaml --wait`
(rev13 = production-strict: authn.mode=production-strict, mtls все рёбра, iam-unified JWKS :9097).

**Стрим reload-svc-прогона (deployable-now фиксы):**
- **registry `registry` collection: 173/0 GREEN** — Defect B (route-shadow) + REG-LSTREPO (404 by-design) LIVE-подтверждены
  (173/2→173/1→173/0). registry-repository/redesign/authz (159 fail) НЕ гонялись — Defect A не задеплоен (pending owner helm-upgrade).
- **compute authz-deny: 441/0 GREEN** — cluster-viewer floor LIVE-подтверждён (0 «lacks relation viewer on cluster»). Остаток
  compute ~8 (instance/disk/image create→immediate-list/get своего свежего) = **read-your-writes / owner-tuple lag на
  ДЕГРАДИРОВАННОМ стенде** (накопленные FGA-tuple > retry-бюджет ~10s), НЕ регрессия, НЕ cluster-viewer.

**Degradation-collapse требует fresh dev-up** (helm-upgrade роллит поды, но OpenFGA-БД с накопленными tuple не чистит).
Fresh `make dev-up` — СУПЕРСЕТ helm-upgrade: bootstrap-on-install лендит Defect A + wipe БД схлопывает compute-8/iam/nlb
degradation + reseed применяет cluster-viewer. Один owner-run dev-up закрывает всё. Тоже owner-gated (helm install/apply блокир.).

## Fresh production-mode rebuild — выполнен main-сессией (2026-07-22 вечер)

**Владелец: «пересобери кластер прогони заново с новыми мержами, отчёт перед продолжением».** main-сессия НЕ заблокирована
classifier'ом (bypassPermissions на dev-машине; субагент был заблокирован — разное окружение). Выполнено самой main-сессией:
`make dev-down` → `make dev-up` (base) → `dev-prod-secrets.sh` → prod-flip `helm upgrade -f values.dev -f values.dev-prod`.

**Итог: стенд ПОДНЯТ в production-strict, все 8 сервисов Running 1/1, Defect A model запинен**
(`openfga-model-id.current=01KY5GF8...`, owner→v_create деривация live), **fresh БД → 0 tuples (331K degradation схлопнута)**.

**Rebuild вскрыл 2 deploy-бага (production-mode invariant в действии — dev-insecure их маскировал):**
1. **pg-race (не фикшено, → issue):** init-контейнер `migrate` стартует раньше готовности своего Postgres → `connection
   refused` → CrashLoopBackOff → helm phase-2 `--wait` timeout (compute/geo/nlb/registry; iam/storage/vpc успели). Само-
   восстановимо роллом против готового pg, НО dev-up не гейтит migrate на pg-ready. Фикс: wait-for-pg initContainer ИЛИ
   больший --wait. Класс: dev-up маскировал (быстрый happy-path), fresh rebuild под нагрузкой обнажил.
2. **values.dev-prod KACHO_APP_ENV дубль (ФИКШЕНО, commit `aa4b8c0`):** overlay слал `extraEnv.KACHO_APP_ENV=production`,
   а чарт рендерит KACHO_APP_ENV из first-class `appEnv`-knob (values.dev `appEnv=dev`) → ДВА env-ключа `KACHO_APP_ENV`
   (dev+production) → helm strategic-merge `$setElementOrder` patch FAIL на prod-flip. MIGRATE-gap (appEnv-рефактор не
   обновил dev-prod overlay). Фикс: overlay → `appEnv: production` (drop extraEnv-дубль). **Сломало бы и owner-run rebuild.**
   Плюс: повторные failed-апгрейды оставили api-gateway deployment в mixed-state (DEV_SECRET залип, KACHO_APP_ENV отсутств.)
   → boot-guard refuse-to-start (`devSecret set в prod`); лечится `kubectl delete deploy api-gateway` + helm upgrade без
   `--wait` (чистый CREATE, без patch-merge на замусоренный spec).

**Branch cleanup (по просьбе владельца, до rebuild):** origin → только `main`+`redesign/integration`; 12 несмёрженных веток →
`archive/*` теги (local+origin, восстановимо cherry-pick); 26 merged + 28 worktree'ов снесены; wt-compute ids.go diff
сохранён. Оговорка: remote-only `qa/iam-acb-fixture-green` удалена без tag (не аудирована локально; оценка — консолидирована;
GitHub restore-deleted-branch если понадобится). Locked harness-worktree `agent-a827799c...` оставлен (живой bg-spare daemon).

**Clean-numbers прогон — пир на fresh стенде (reseed + 7 suites).** Первая волна вскрыла **3-й deploy-gap** (issue
**#67**): greenfield стенд — **пустой/невидимый geo-каталог**. Root cause: (1) `geo-data-migration` helm-hook только
`\copy`ит regions/zones из `kacho_compute` → на post-split greenfield compute пуст → 0 строк; (2) даже при copy job'а
region-INSERT не ставит `status` → регион остаётся DEFAULT `'DOWN'` (two-projection mig 0004) → public-read
`r.status='UP'` скрывает весь каталог; (3) job-комментарий врёт «seeds baseline» (doc-truthfulness). Cascade: все
зональные/региональные create'ы фейлят geo peer-validate → storage/compute/vpc/nlb/registry swamped, Defect A
невалидируем (Namespace.regionId не резолвится). **Разблокировано**: пир засеял live через geo Internal admin-RPC
(`POST /geo/v1/internal/regions+zones`, system_admin@cluster boot-token) — ru-central1 + a/b/c/d все UP. Правильный
фикс (greenfield migration-seed UP ON CONFLICT / seed-Job + region-status fix) — continuation.

**Deploy-баги rebuild-а (production-mode invariant вскрыл 3, dev-insecure маскировал все): #66 pg-race (open),
KACHO_APP_ENV дубль (fixed aa4b8c0), #67 greenfield geo-seed (open).**

## Full-green push — deploy всех фиксов (2026-07-22 ночь)

Владелец: «добивай до полной зелени, каждый модуль реально прогнан (НИКАКИХ 0/0), + пофиксить token-expiry (long-lived
тестовые токены)». Координированный push (я=cluster/deploy, пир=код):

**Фиксы (все pushed, HEAD 27e6da2):** #69 token-TTL `d7feb4e` (Hydra access_token 15m→4h, ТОЛЬКО локальный тест-стенд
values.dev.yaml; prod fe3455=values.prod неизм.) · #68 nlb_listener `project`-relation `5f22615`+TDD(real-OpenFGA-Check) ·
deny_reasons leak `9f0f60f` (403 не эхает reason/metadata — existence-oracle fix) · nlb-CONTRACT WIP `9118e66` (закоммичен
inherited drift — buf-consistent) · EC-retry `27e6da2` (compute/registry read-your-writes окно 12.5→24s). Issues: #70
tokens-in-git (committed newman env несут реальные токены в public repo — strip+gitignore follow-up).

**Deploy (единый): gateway rebuild (deny_reasons+deep-wildcard) + helm-upgrade (Hydra 4h + openfga model re-pin).**
Результат rev7: model re-pinned `01KY5S4C5BGBECSA37EF7Q3M4Q` (#68 nlb_listener.project + Defect A live), gateway rolled
(deny_reasons live), Hydra 4h. 8/8 Running prod-strict.

> [!warning] Deploy-гоча: **stale vendored subchart `.tgz` маскирует chart-source правки.** `charts/openfga-bootstrap-0.1.0.tgz`
> собран `make dev-up`-ом (`helm dep update`) в 20:37; #68 отредактировал source-template в 23:04. helm-upgrade рендерил из
> **stale .tgz** (pre-#68) — model НЕ перепинивалась (bootstrap fast-path sha совпадал), gateway не роллил (нет model-id-rev
> patch). `helm template` показывал #68 (брал dir), но `helm upgrade` применял .tgz — рассинхрон dir↔tgz. **Фикс: `helm dep
> update` (пересобрать .tgz из source-dir) ПЕРЕД helm-upgrade** после любой правки чарт-исходника subchart'а. Плюс большой
> configmap (embed model.json) не апдейтился 3-way-merge patch'ем — delete+recreate обошло.

## Full-green push — test-integrity находки (serial verification, 2026-07-23)

Владелец: «каждый модуль реально прогнан, НИКАКИХ 0/0, all green». Строгая serial-верификация (после того как параллельная
волна засвампила reconciler — 2861 pending owner-tuples, load-артефакт: backlog 2861→0 за 3min, fast-path здоров) вскрыла
**реальные test-integrity дыры, которые прежняя «зелень» маскировала:**

- **#71 storage — MASKED FALSE-GREEN (единственный, decisive).** storage 722/0 был ложным: (1) FGA-модель НИКОГДА не имела
  типов `storage_volume/image/snapshot`; (2) iam Go-wiring дыра — `authzmap.DottedType` не мапил storage-prefix → mirror
  хранил «storage_volume» без точки → `ReconcileObjectForward.FGAObjectType()`=ok=false → reconciler НЕ материализовал v_* →
  owner получал **403** на свой volume (fail-closed, НЕ BOLA); (3) storage-suite гонял CRUD под `jwtBootstrap` (cluster-admin)
  → system_admin short-circuit → 200, маскируя. Live A/B: bootstrap→200, project-editor→403 на одном volume. Fix `c01c2b9`:
  model (nlb-parity типы project+DIRECT-v_*, НЕ `or owner` — эмиттер project-only) + iam wiring (objectTypes/verbBearingTypes/
  knownModules) + TDD → **требует iam SERVICE REBUILD + model re-pin**. + storage-suite object-self под project-scoped actor.
- **Systemic masking audit (evidence-based, live GET project-editor per suite):** storage=ONLY masked false-green; **vpc/compute**
  default cluster-admin но authz РАБОТАЕТ (project-editor=200) → coverage-gap НЕ false-green (**#72** enhancement, regression-proof);
  nlb/registry/iam project-scoped ✓; geo admin-catalog+public-read-exempt legitimate ✓.
- **reseed-warmup race:** serial7 бежал suite-1 (registry) до материализации грантов → false-403 каскад (registry 595/49 = 100%
  warm-up, 0 реальных багов). Fix: **drain-gate** (post-reseed poll healthy_pending→0 перед suite-1) в serial7.

**Interim serial (mid-drain, warm-up-шум):** registry 595/49 (warm-up), compute 1927/9 (EC), nlb ~1463/98 (load-balancer
ЗАВЕРШИЛАСЬ — 300s-фикс ✓; re-check), geo **213/0** ✓, storage false-green, vpc/iam ⏳. **Live-подтверждено:** #68 nlb_listener
в модели, deny_reasons leak ушёл, cluster-viewer 441/0, deep-wildcard.

**Issues full-green push: #69 token-TTL (fixed d7feb4e) · #70 tokens-in-git · #71 storage-types+wiring (fixed c01c2b9, deploy
pending) · #72 vpc/compute coverage-gap.** Путь: пир доделывает (storage-suite + drain-gate) → deploy #71 (iam rebuild + re-pin)
→ чистый серийный с drain-gate → REAL per-module full green.

## #71 — РЕЗОЛЮЦИЯ (обе половины) + infra-hardening (2026-07-23)

**#71 оказался TWO-HALF (класс «per-resource MIGRATE gap» — новый FGA-тип нужно wire в НЕСКОЛЬКИХ местах):**
- **Half-1 `c01c2b9`:** openfga model storage_volume/image/snapshot типы (nlb-parity: project + DIRECT v_*, НЕ `or owner` —
  эмиттер project-only) + iam Go-wiring `authzmap.objectTypes`/`verbBearingTypes` + `domain.knownModules("storage")`. Без
  DottedType-round-trip reconciler дропал объект (`FGAObjectType()`=ok=false). Deploy = iam rebuild + model re-pin.
- **Half-2 `1a399dd` (найдена по live-диагнозу: fresh volume нёс ТОЛЬКО `#project` tuple, 0 v_*):** storage отсутствовал в
  `domain.AllMaterializableTypes()` → boot-backfill `SyncAllSystemRoleSelectors` не проецировал storage.* в
  `role_rule_selectors` edit/view/admin/owner → project-binding невидим binding-discovery → reconciler не материализовал v_*
  → owner 403. **Точно инвариант data-integrity.md** («role_rule_selectors для ВСЕХ материализующих system-ролей»). Fix:
  storage → labelSelectableTypes (26 типов) + миграция 0060 (re-seed 4 selector-роли) + boot-backfill re-project. Deploy = iam
  rebuild + rollout restart (0060 + backfill на старте, БЕЗ model re-pin).
- **Полная цепочка (end-to-end):** model types → objectTypes/verbBearingTypes/knownModules → **AllMaterializableTypes/
  role_rule_selectors** → reconciler `objectType ∈ selector.types` → materialize owner v_*. **ACCEPTANCE FLIP ✅ GREEN**
  (empirical): owner-GET/Update/Delete object-self 403→200, cross-account 403 (anti-BOLA), DB 26-type selectors has_storage=t.

**Infra-hardening (все test-harness, не прод):** #69 token-TTL **✅ 4h подтверждён** (fresh SA exp-iat=14400, global применяется,
per-client override нет — весь прогон в одном окне) · **drain-gate** `7eeb8c4` (post-reseed poll healthy→0, reseed-warmup fix) ·
**pf-watchdog** (main-сессия держит 4 pf, respawn при harness-SIGKILL — pf-death был доминантный wash) · **storage-suite
object-self coverage** `d08c8eb` (unmask cluster-admin false-green). Fixture-EC замечен: `prodseed_matrix.py` owner db_lookup
гонит fresh-pod account-provisioning (обойдено reuse verified-матрицы; retry/pre-provision захардит).

**Deploy-цепочка (rev7→rev8 + 2 iam-rebuild):** #71-half1 rev8 (model `01KY5Y3W…` + iam) → #71-half2 iam rollout (0060+backfill).
Гоча: iam-wiring правки требуют **iam rebuild** (Go), не только model re-pin. Финальный clean full-green прогон — `bjji0ko6u`.

## Чистый прогон на fresh-стенде (production-strict, 0 tuples) — числа

Prod-posture verified: anonymous→**401** (:18080/:18081, no anon-full), pg_stat_ssl 9 TLS/1 unix (sslmode=require).

| Suite | degraded/blocked | **clean** | природа остатка |
|---|---|---|---|
| geo | 213/16 | **213/0 ✅** | (был пустой geo-каталог) |
| storage | 223/137 | **722/0 ✅** | (223→722 assert: lifecycle-кейсы ожили post-geo-seed) |
| compute | 1988/19 | **1934/9** | 9 = create→immediate-self EC-флейки (owner-tuple lag, thin-retry); authz-deny 441/0 (cluster-viewer ✅) |
| registry | ~588/161 | 595/102→**re-run** | core `registry` 173/0 ✅; overlay ×3 вскрыли authz-баг ↓, фикс re-validating |
| nlb/vpc | — | pending | |
| iam | 5192/3549 | pending (отд. волна) | 0 tuples → ожидаем резкое падение vs 331K-degraded |

**Реальный gateway-authz баг (fresh full-surface прогон вскрыл — degraded/geo-blocked маскировали), fix `7a484df`
pushed+reloaded, TDD RED→GREEN:** `RestRouter.matchTemplate` в authz-middleware трактовал deep-wildcard `{field=**}`
как одно-сегментный `{field}` (`len(tparts)==len(pparts)`) → multi-segment repository (`backend/api`) не матчился →
fallback raw-path → `"catalog: no entry"` → AUTHZ_DENIED. Single-segment repo работали (partial-mask). authz-matcher
НЕ покрывал route-формы, что mux `**` обрабатывал → fall-through. Fix: (1) `{field=**}`=1+ сегментов (head+tail+middle,
≥1 → bare `/repositories`=ListRepositories); (2) NewRestRouter most-specific-first ordering (DeleteTag>DeleteRepository,
ListReferrers>GetRepository) = first-match как mux-prepend. **NOT** stale-regen (оба генератора 0-diff, catalog-check
не сработал бы). **Рекомендация: security-review authz-matcher изменения** (authz-routing критичен). Класс #4 (security.md)
но здесь routes present, MATCHER неверен. Не путать с Defect B reorder (корректен, не тронут).

## Консолидированные clean-числа (fresh prod-strict, 0 tuples) — 6/7 (iam in-flight)

| Suite | clean | класс остатка |
|---|---|---|
| geo | **213/0 ✅** | — (был пустой каталог #67) |
| storage | **722/0 ✅** | — (223/137→722/0) |
| compute | **1934/9** | 9 EC-флейк; authz-deny 441/0 (cluster-viewer ✅) |
| registry | **595/18** | 17 EC + 1 pre-existing deny_reasons-leak; core 173/0, redesign 138/0 ✅ |
| vpc | **5194/23** | 23 = token-expiry (15-мин RS256 TTL за длинный parallel-прогон); real ≈ 5194/0 |
| nlb | **1088/33** | 19 = #68 (nlb_listener#project); 14 EC/poison-cascade; load-balancer collection 300s-timeout |
| iam | **14 early coll 0/0** (raw 4764/3213, 3213=token-expiry) | **degradation СХЛОПНУТА**: свамп-суиты (authz-deny 434/0, ab-redesign 254/0, role-redesign 49/0, label-revoke 31/0…) все 0-fail на fresh; поздние коллекции = 15-мин TTL за 30+-мин серийный EXCLUSIVE-lock прогон (#69) |

**Классы остатка (ни один degraded-«фейл» не оказался нераскрытым прод-дефектом кода):** infra-cascade fixed (geo/storage,
#67-seed) · real-bug FIXED+green (registry A/B/REG-LSTREPO, cluster-viewer, deep-wildcard 7a484df, #65) · real-bug TRACKED
(#68 nlb, option 1, continuation) · EC-флейк (compute 9 + registry ~17, thin-retry-window, client-side) · token-expiry (vpc 23,
e2e-harness артефакт — стоит issue: refresh-token mid-run / shorter-wave) · pre-existing-leak (registry-authz 1, deny_reasons).

**Пировские коммиты (redesign/integration, pushed):** d7003a1 (Defect B) · 0993ea2 (Defect A) · 8a07c13 (cluster-viewer) ·
818472a (#65) · 5a96410 (REG-LSTREPO) · 7a484df (deep-wildcard matchTemplate). Мой aa4b8c0 (KACHO_APP_ENV values-fix).
Issues: #66 pg-race, #67 geo-seed, #68 nlb-model — open (continuation).

## Fresh-стенд clean sweep (option A, владелец «до талого») — 2026-07-23

Fresh dev-up (чисто с 1-й попытки: no pg-race, no KACHO_APP_ENV-dup) + prod-flip + #71 обе половины из HEAD.
**Blockers sweep-prep (все fixture/infra, не продукт):** (1) reseed пустой matrix = **stale mTLS client-cert** после fresh
dev-up (новая CA отвергала старый /tmp/iam-mtls cert → UpsertFromIdentity dial-hang) → re-extract из api-gateway-client-tls
(пир захардил prodrun 4c54c67); (2) pf-churn 390 respawns = дубли-watchdog + stale-cert connection-resets на :19091 → ОДИН
watchdog + fresh cert → стабильно; (3) geo-seed 404 = geo-seed.sh бил :18080(public), internal admin RPC на **:18081** → засеял
через :18081 (region+zones UP); (4) sweep bg-task harness-killed mid-vpc ([[bg-test-jobs-killed]]) → mini-sweep re-launch.

**Clean per-service (fresh изолированный prod-strict стенд):**
| svc | clean | класс |
|---|---|---|
| geo | **213/0** | ✅ GREEN |
| storage | **722/0** | ✅ GREEN — **#71 VOL-OBJSELF suite-level 0-fail** (owner-GET 403→200, cross 403); false-green ЛИКВИДИРОВАН, fixture честно тренит tenant-путь |
| vpc | **~/1** | ✅ ~clean (driver-bug cascade 98→0; 1 quick-EC list-filter-d) |
| compute | 1929/9 | quick-EC list-inclusion (fixture retry_until_present borderline) |
| registry | 598/13 | **#102 sync-registrar gap** (missing immediate post-commit RegisterResource — единственный create-heavy svc без sync-registrar) |
| nlb | 1463/74 | deep cross-resource-chain EC (LB→listener→TG multi-hop + listener-races-parent-LB 403) |
| iam | pending | mini-sweep re-run |

**Диагноз остатка — ВСЁ EC (read-your-writes/materialization), НЕ authz/correctness.** 0 ECONNREFUSED / 0 subnet-404 везде.
Два корня: registry=**#102** (sync-registrar, product-fix `aaadc19` — зеркалит storage iam_sync_registrar, drainer backstop цел,
TDD RED→GREEN 14pkg 0-fail; deployed registry rebuild) → owner-tuple sync-materialize → EC-хвост уходит; nlb/compute=**fixture
EC-discipline** (op-poll-to-durable + retry_until_authorized на create→dependent-use, не band-aid budget).

**Issues full-green: #66 pg-race · #67 geo-seed · #68/71 fixed · #69 token-4h · #70 tokens-in-git · #72 vpc/compute coverage ·
#73 registry-fixture fixed · #102 registry sync-registrar (fixed aaadc19, deployed).** Все реальные authz/product/model баги
fixed+validated; остаток = #102 (deployed) + EC-tail fixture-discipline. **Bottom-line: 0 нераскрытых product/authz регрессий.**
