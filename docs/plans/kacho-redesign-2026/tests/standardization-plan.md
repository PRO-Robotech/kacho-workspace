# Kachō — план стандартизации тестового harness + закрытия newman-пробелов

> Нормативный эталон — [`common-test-schema.md`](./common-test-schema.md). Аудит 7 сервисов
> (`geo · iam · vpc · compute · nlb · registry · storage`). Этот план **разводит два трека**:
>
> - **Harness-трек (СЕЙЧАС, API-agnostic, НЕ throwaway):** layout, shared-хелперы, gen/validate/run,
>   fixture-изоляция, runId, integration-структура. Переживает редизайн API без изменений.
> - **Case-трек (В redesign-инкременте каждого модуля, throwaway против старого API):** переписывание
>   `cases/<resource>.py` под НОВЫЙ API строгим TDD (RED до прод). `geo`-newman baseline — целиком в GEO-1.
>
> Развязка: API редизайнится (пересборка-2026) → содержимое кейсов трогать сейчас бессмысленно.
> Harness API-agnostic → стандартизируем немедленно, и все переписанные кейсы садятся на готовый общий каркас.

---

## 1. Сводная таблица: сервис × соответствие канону

| Сервис | newman cases | ресурсов | Coverage-вердикт | Главный дрейф от канона | Priority |
|---|---:|---:|---|---|---|
| **vpc** | 255 (~996 прогон.) | 7 (+AddressPool) | **reference-grade** — эталон, из него извлечена схема | почти нет: `setup.sh` op.error-guard = WARN-only (не hard-fail); RESULTS known-failing может устареть | **LOW** |
| **iam** | 366 | 13 | **полно** (richest suite, референс покрытия) | нет `validate-cases.py` (только `gen.py --validate` + чужой `coverage.py`); docs = только RESULTS; нет `retry_until_present`/`assert_unscoped_rejected`/`assert_absent_id_rejected`/`assert_transcode_error`; нет корневого README/serial | **MEDIUM** |
| **vpc**→ | — | — | — | — | — |
| **compute** | 469 | 5 | **полно** для реализованной поверхности | нет `assert_absent_id_rejected`/`assert_transcode_error` → хардкод `[400,404]` ложно падает на authz-first 403; нет standalone `validate-cases.py`; нет `serial-collections.txt`; `run.sh --jobs` игнорируется; op.error-guard задокументирован но не энфорсится | **MEDIUM** |
| **nlb** | 357 | 4 | **полно** (comprehensive) | нет `retry_until_absent` (11 leak-guard без mirror-retry) / `assert_transcode_error`; нет README / REQUIREMENTS.md / serial-collections.txt; нет `internal-*.py` под 2 Internal*-сервиса; RESULTS никогда не зелёный (стенд не поднимался) | **MEDIUM** |
| **registry** | 57 | 4 | **полно по public control-plane, тонко в целом** | `gen.py` = **copy-paste из nlb** (docstring/collection-name/OP-regex `^(nlb\|tgr\|lst)` неверны); нет `retry_until_*`/`assert_unscoped_rejected`/`assert_absent_id_rejected`/`ensure_`/`assert_transcode_error`; нет `internal-*.py` (InternalRegistryService не выведен на public → ban #6 не тестируется); docs неполны; `testing.Short()` в 1/15 integration; single shared project (нет cross) | **MEDIUM** |
| **storage** | 69 | 3 (Volume/Snapshot/DiskType) | **полно для существующих**; Image ещё не существует (pre-redesign) | нет `retry_until_present`/`retry_until_absent`/`assert_unscoped_rejected`/`assert_absent_id_rejected`/`assert_transcode_error`; ни одного `ensure_`-хелпера; docs = только CASES-INDEX+RESULTS (4 отсутствуют); нет serial; `testing.Short()` только в `volume_integration_test.go`; RESULTS не прогнан | **MEDIUM** |
| **geo** | **0** | 2 (Region/Zone) | **NONE** — только `README.md`-скелет, 0 реальных `cases/*.py`. Integration-слой при этом FULL/canon | весь `tests/newman/` отсутствует (нет `cases/collections/environments/scripts/docs/out`, нет `gen/validate/run`); baseline **отложен в GEO-1** (TDD против нового API), трекер `kacho-geo#10` | **HIGH** (но deferred → GEO-1) |

**Дрейфят от канона: 7 из 7.** vpc — минимально (эталон + 2 хвоста); geo — тотально (harness отсутствует);
остальные 5 — частичный harness-дрейф (хелперы + docs + validate-gate). Integration-слой у всех сервисов
(кроме case-only geo-newman) — **сильный или превосходит канон** по concurrent-race покрытию.

### Где главные пробелы (сквозные классы, повторяются у ≥4 сервисов)

1. **Helper-parity drift** (6/7): missing helpers per-service, потому что каждый `gen.py` держит **свою копию**
   namespace → drift неизбежен (registry — прямой copy-paste из nlb с неверными дефолтами). Отсутствуют чаще всего:
   `assert_absent_id_rejected`, `assert_unscoped_rejected`, `assert_transcode_error`, `retry_until_present`,
   `retry_until_absent`. **Последствие:** хардкод-негативы `[400,404]` ложно падают на корректном gateway
   authz-first `403`; EC read-your-writes и revoke-contamination окна не закрыты детерминированно.
2. **Layout/docs неполны** (6/7): нет корневого README, отсутствует часть `docs/{TAXONOMY,TEST-PLAN,
   PRODUCT-REQUIREMENTS,REQUIREMENTS}.md`, нет `serial-collections.txt`.
3. **`validate-cases.py` как standalone MANDATORY-гейт отсутствует** (iam/compute и др. полагаются на
   `gen.py --validate` или неэквивалентный `coverage.py`) — dup-id + CASES-INDEX-покрытие не гейтится формально.
4. **Anti-phantom op.error-guard в `setup.sh` не энфорсится** (vpc WARN-only; iam/compute/storage — извлекают
   `metadata.<res>Id` без `assert !result.error`). Фантом-id может утечь в downstream FGA-биндинги (§2.5 канона).
5. **`internal-*.py` отсутствует** там, где есть Internal*-сервисы (nlb: Announce/Lifecycle; registry: GC/Stats) →
   ban #6 surface (Internal-RPC на public → 404) не проверяется декларативными кейсами.
6. **`testing.Short()`-skip не в каждом integration-файле** (registry 1/15, storage 1/N) → `make -C services/{registry,storage} test-short`
   не пропустит → долгий прогон (нарушение §5.1).

---

## 2. Harness-фиксы, которые делаем СЕЙЧАС (API-agnostic, НЕ throwaway)

Всё ниже переживает редизайн API без изменений — это каркас, на который сядут переписанные кейсы.

### H0 — Центральный сдвиг: shared helper-namespace вместо per-service копий *(корень пробела #1)*

**Проблема:** канон говорит «каждый `gen.py` несёт идентичный набор хелперов» — но именно ручная копия
породила drift (registry скопировал nlb целиком, compute/storage/nlb недосут подмножества). Parity через
copy-paste недостижим.

**Фикс:** извлечь helper-namespace в **единый shared-источник** (`tests/newman-lib/helpers.py` или
`deploy/scripts/newman_helpers.py`), который каждый `gen.py` **импортирует**, а не копирует. Параметризовать
per-service дефолты (OP-envelope regex, baseUrl-vars) конфигом, не форком кода. Итог: parity **структурный**,
добавление хелпера — в одном месте для всех 7. Один раз пишем полный канон-набор (§2 схемы):
`assert_status/grpc_code/operation_envelope/field_violation/transcode_error`, `save_from_response`,
`poll_operation_until_done`, `assert_unscoped_rejected`, `assert_absent_id_rejected`,
`retry_until_authorized/present/absent`, `ensure_<resource>` (с op.error-guard). **Effort: L** (workspace/deploy-уровень, разово).

> Это разблокирует H1 для всех сервисов: «добавить недостающий хелпер» превращается в «переключить сервис
> на shared-lib + удалить локальную копию».

### H1 — Helper-parity по сервисам (после H0 — просто переключение на shared-lib + чистка форка)

| Сервис | Действие | Effort |
|---|---|---|
| vpc | switch на shared-lib, удалить локальные копии (эталонные — сверить сигнатуры при извлечении) | S |
| iam | switch + добить `retry_until_present`/`assert_unscoped_rejected`/`assert_absent_id_rejected`/`assert_transcode_error` (приходят из lib) | S |
| compute | switch + `assert_absent_id_rejected`/`assert_transcode_error`; **ретрофит хардкод-негативов** `[400,404]`→`assert_absent_id_rejected` (disk/image/snapshot/instance) — **это правка cases, но замена вызова, не переписывание тела** → допустимо в harness-треке как механический sweep | M |
| nlb | switch + `retry_until_absent`/`assert_transcode_error`; **вплести `retry_until_absent` в 11 leak-guard** (механически) | S |
| registry | switch (**устраняет nlb copy-paste drift разом**: docstring/collection-name/OP-regex); приходят все `retry_until_*`/`assert_*`/`ensure_` | M |
| storage | switch + `retry_until_present/absent`/`assert_unscoped_rejected`/`assert_absent_id_rejected`/`assert_transcode_error`/`ensure_` | M |

### H2 — Layout / docs scaffold (чистый файловый каркас, API-agnostic)

| Сервис | Что добавить | Effort |
|---|---|---|
| iam | корневой `README.md`; `docs/{TAXONOMY,TEST-PLAN,CASES-INDEX,PRODUCT-REQUIREMENTS,REQUIREMENTS}.md`; `serial-collections.txt` (пустой + комментарий — нет pool-contention) | M |
| compute | `serial-collections.txt` (external-VIP/contended); docs уже полны | S |
| nlb | `README.md`; `docs/REQUIREMENTS.md`; `serial-collections.txt` (external-VIP/INTERNAL-subnet вместо blanket `--jobs 1`) | S |
| registry | `README.md`; `docs/{TAXONOMY,PRODUCT-REQUIREMENTS,REQUIREMENTS}.md`; `serial-collections.txt` (или явная пометка «нет contention») | S |
| storage | `docs/{TAXONOMY,TEST-PLAN,PRODUCT-REQUIREMENTS,REQUIREMENTS}.md`; `serial-collections.txt` (attach/internal-pool contention) | S |
| vpc | — (полный layout, эталон) | — |

> Наполнение `docs/*` конкретными REQ-* и CASES-INDEX-паттернами частично зависит от нового API → **скелет
> и структуру ставим сейчас** (это гейт для `validate-cases`), а нормативное содержание REQ дозаполняется
> в case-треке каждого модуля. TAXONOMY (классы CRUD/VAL/NEG/BVA/IDM/CONC/CONF + naming) — API-agnostic, пишем полностью.

### H3 — `validate-cases.py` как MANDATORY standalone-гейт + gen/run

| Сервис | Действие | Effort |
|---|---|---|
| iam | вынести standalone `scripts/validate-cases.py` (dup-id среди 366 + CASES-INDEX-покрытие); убрать зависимость от `coverage.py` как «гейта» | M |
| compute | вынести standalone `validate-cases.py` (сейчас только `gen.py --validate`); **починить `run.sh --jobs`** (флаг consume-and-ignore → реальный fan-out одного сервиса, канон §4.2) | M |
| registry/storage/nlb | подтвердить standalone `validate-cases.py` присутствует и на общей заготовке (shared можно вынести в lib аналогично H0) | S каждый |

> `validate-cases.py` — pure-Python, без сети, API-agnostic (работает над id-строками и CASES-INDEX). Идеальный
> кандидат в shared-lib рядом с helpers (H0).

### H4 — Fixture-изоляция + anti-phantom op.error-guard в `authz-fixtures/setup.sh` *(корень пробела #4)*

| Действие | Сервисы | Effort |
|---|---|---|
| Превратить op.error-guard в **hard-fail** ПЕРЕД `metadata.<res>Id` в `ensure_account`/`ensure_project`/… (сейчас WARN-only или отсутствует) | vpc(S), iam(S), compute(S), storage(S) | S×4 |
| Per-suite изоляция: **свой account + home/cross project**, таргетный патч `existingProjectId`/`existingProjectCrossId` | registry (сейчас single shared project, нет cross → добавить cross) | M |
| Зарегистрировать сервис как изолированную suite в `setup.sh` Phase B + `newman-parallel.sh` fan-out | geo (в GEO-1), подтвердить остальные | S |

> Структура изоляции (account + home/cross, паттерн патча env) — API-agnostic. Конкретные seed-ресурсы
> (network/subnet для nlb и т.п.) переживают редизайн как топология; правятся точечно если ресурс переименован.

### H5 — Integration-структура (harness-конвенции, не сами race-тесты)

| Действие | Сервисы | Effort |
|---|---|---|
| `if testing.Short(){t.Skip()}` **первым стейтментом в КАЖДОМ** `*integration_test.go` (§5.1) | registry (1/15→15/15), storage (1/N→все) | S каждый |
| Подтвердить testcontainers `postgres:16-alpine` + реальные goose-миграции (`migrations.FS`) во всех harness'ах | все | — (уже есть) |

> **Сами недостающие concurrent-race тесты** (compute: UNIQUE(name)-duplicate-create + disk-attach CAS;
> registry: xmin-OCC на repository_config если нужен) — **привязаны к конкретным DB-инвариантам, которые
> редизайн перестраивает** → пишутся в case/redesign-треке модуля (см. §3), НЕ сейчас. Здесь — только
> harness-конвенция `testing.Short()`, которая API-agnostic.

### H6 — runId / cleanup дисциплина (проверка присутствия, API-agnostic механизм)

| Действие | Сервисы | Effort |
|---|---|---|
| Подтвердить `{{runId}}` 10-char на всех UNIQUE(name)-фикстур-ресурсах + `PRE_GLOBAL` zone-resolve | vpc (1 файл-исключение — проверить observability.py), остальные | S |
| Preclean-revoke **ретраит DELETE на 403** до успеха (не fire-forget) | все, где есть grant-teardown | S |
| Shared-CIDR/pool широкая run-random энтропия обоих октетов (не `hash%N`) | подтвердить vpc/nlb паттерн, перенести в shared seed-lib | S |

---

## 3. Что откладывается в redesign-инкременты (throwaway против старого API)

Всё ниже переписывается/создаётся ВНУТРИ redesign-инкремента соответствующего модуля, TDD против **нового** API
(RED-кейс до прод-фикса, §7 канона). Делать сейчас = throwaway.

| Отложенное | Куда | Трекер |
|---|---|---|
| **Переписывание `cases/<resource>.py`** (тела public-RPC кейсов: happy/VAL/NEG/BVA/CONF/IDM/CONC) под новый API | В redesign-инкремент каждого модуля (iam/vpc/compute/nlb/registry/storage) | per-module KAC |
| **geo newman baseline целиком** (13 README-кейсов: Region/Zone Get+List happy+negative, InternalRegion/Zone CRUD, ADMIN-NOT-ON-PUBLIC, OP-GET/CANCEL BOLA) + scaffold всего `tests/newman/` клоном vpc-harness | **GEO-1 redesign** | `kacho-geo#10` |
| **`internal-*.py` кейсы** (Internal*-surface + 404-на-public): nlb Announce/Lifecycle, registry GC/Stats | redesign-инкремент nlb / registry (RPC-поверхность фиксируется редизайном) | per-module |
| **Недостающие concurrent-race integration-тесты** против финальных DB-инвариантов: compute UNIQUE(name)-duplicate-create + disk-attach CAS (disk-attach уже мигрировал в storage — писать в storage-инкременте); registry xmin-OCC repository_config (проверить нужность) | redesign-инкремент модуля-владельца инварианта | per-module |
| **Наполнение `docs/{PRODUCT-REQUIREMENTS,CASES-INDEX}.md` нормативным содержанием** (REQ-* и паттерны кейсов) | вместе с case-переписыванием модуля | per-module |
| **RESULTS.md → green baseline против живого стенда** + секция «Known failing — product bugs» | после case-переписывания модуля (кейсы стабильны) — nlb/storage/geo сейчас env-blocked/не прогнаны | per-module |

> **Граница трека (правило разведения):** harness-трек трогает *каркас* (файлы scripts/docs-скелет/setup.sh/
> helper-lib/integration-конвенции) — переживает редизайн. Case-трек трогает *содержание* (`cases/*.py` тела,
> REQ-*, race-тесты против конкретных таблиц) — throwaway. Механическая замена **вызова** хелпера
> (`oneOf[400,404]`→`assert_absent_id_rejected`) — harness (H1), т.к. не зависит от нового API. Переписывание
> **тела** кейса под новые поля/RPC — case-трек.

---

## 4. Порядок и quick-wins

### Порядок (harness-трек, до/параллельно redesign-инкрементам)

```
H0  shared helper-lib + validate-cases в shared        ← РАЗБЛОКИРУЕТ всё остальное (делать ПЕРВЫМ)
 │
 ├─ H1  switch каждого сервиса на shared-lib + чистка форка (registry drift исчезает разом)
 ├─ H3  standalone validate-cases гейт + run.sh --jobs fix (compute)
 │
 ├─ H2  layout/docs scaffold (скелеты — параллельно, независимо)
 ├─ H4  setup.sh op.error hard-fail + registry cross-project изоляция
 ├─ H5  testing.Short() sweep (registry/storage)
 └─ H6  runId/cleanup/entropy подтверждение
        ↓
   [далее] case-трек внутри redesign-инкремента каждого модуля (§3); geo-newman в GEO-1
```

**H0 — критический путь и первый шаг:** пока helper-namespace копируется per-service, любой H1-фикс надо делать
7 раз и он снова разъедется. Извлечение в shared-lib превращает 6 наборов «missing helpers» в один патч +
6 механических switch'ей, и структурно закрывает registry copy-paste drift.

### Quick-wins (высокий эффект / низкий effort — можно закрыть сразу)

1. **op.error-guard hard-fail в `setup.sh`** (vpc/iam/compute/storage, S×4) — закрывает anti-phantom §2.5,
   первопричину каскадных флейков («phantom-id → downstream FGA против несуществующего project»). Наибольший
   ROI: убирает целый класс «блуждающих» e2e-флейков.
2. **`testing.Short()` sweep** (registry 1/15→15, storage) — S, чистая конвенция, ускоряет `make -C services/{registry,storage} test-short`.
3. **registry gen.py drift** — устраняется **бесплатно** switch'ем на shared-lib (H0/H1): docstring/collection-name/
   OP-regex перестают быть форком.
4. **`serial-collections.txt`** для nlb/compute/storage (S) — вернуть parallel fan-out uncontended-коллекциям
   вместо blanket `--jobs 1` (nlb) → быстрее wall-time.
5. **layout scaffold-скелеты** (README + docs-заглушки, S–M) — механически, разблокирует `validate-cases`-гейт.

---

## Вердикт

- **Дрейфят от канона: 7 / 7 сервисов.** Эталон — **vpc** (LOW, из него извлечена схема, 2 мелких хвоста).
  **geo** — тотальный дрейф (newman-harness отсутствует, 0 кейсов), но осознанно отложен в **GEO-1** (`kacho-geo#10`);
  integration-слой geo при этом уже canon-полный. Остальные 5 (iam/compute/nlb/registry/storage) — **MEDIUM**,
  частичный harness-дрейф.
- **Главные пробелы (сквозные):** (1) helper-parity drift из-за per-service **копий** namespace (registry —
  прямой copy-paste из nlb); (2) неполный layout/docs + отсутствие standalone `validate-cases`-гейта;
  (3) anti-phantom op.error-guard в `setup.sh` = WARN-only/отсутствует → каскадные флейки; (4) `internal-*.py`
  и `testing.Short()`-конвенция недособраны. Integration concurrent-race покрытие — **сильное у всех** (не пробел).
- **Что делать первым:** **H0 — извлечь helper-namespace + `validate-cases` в единый shared-lib** (импорт, не
  копия). Это критический путь: превращает 6 наборов «missing helpers» и registry-drift в один патч + механические
  switch'и, и делает parity структурным. Сразу за ним — **quick-win: op.error-guard hard-fail в `setup.sh`**
  (убирает первопричину phantom-каскадов). Всё содержательное переписывание кейсов и geo-baseline — **в
  redesign-инкрементах модулей** (TDD против нового API), НЕ в harness-треке.

**Путь плана:** `/home/dk/Documents/03.07.2026/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/docs/plans/kacho-redesign-2026/tests/standardization-plan.md`
