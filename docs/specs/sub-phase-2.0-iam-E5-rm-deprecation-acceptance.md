# Sub-phase 2.0 — IAM E5: kacho-resource-manager full deprecation + cleanup — Acceptance

> **Status**: DRAFT v2 — awaiting acceptance-reviewer (round 2)
> **Date**: 2026-05-17 (v1) / 2026-05-17 (v2)
> **YouTrack**: [KAC-110](https://prorobotech.youtrack.cloud/issue/KAC-110) — child of epic [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104)
> **Parent overview**: [[sub-phase-2.0-iam-overview-acceptance]]
> **Sibling predecessors (must-merge-before-E5)**:
> - [[sub-phase-2.0-iam-E1-folder-to-project-migration-acceptance]] — [KAC-106] — peer-services migrated to `project_id`, никто не зовёт `FolderClient`
> - [[sub-phase-2.0-iam-E4-signup-flow-ui-acceptance]] — [KAC-109] — UI больше не использует Org/Cloud/Folder pages
> **Blocks**: ничего (последний sub-эпик KAC-104; после E5 эпик закрывается)
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`)
> **Затронутые репо**: `kacho-proto`, `kacho-api-gateway`, `kacho-deploy`, `kacho-workspace` (docs + vault), `kacho-resource-manager` (archive). Verification-only (без code changes): `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`, `kacho-ui`.

---

## 0. Преамбула — что эта sub-итерация

E5 — **финальное удаление `kacho-resource-manager`** из платформы Kachō. После E1 backend-сервисы
(vpc/compute/loadbalancer) больше не зовут `FolderClient` (мигрировали на `ProjectClient` →
`kacho-iam`). После E4 UI больше не показывает Org/Cloud/Folder pages (заменены IAM Accounts /
Projects). RM остаётся «жив-но-неиспользуем» — pod крутится, но входящего трафика нет, БД
наполнена только seed default-folder. Цель E5 — превратить «не используется» в «не существует»:

| Слой / артефакт                                              | Было (после E4)                                                                 | Становится (после E5)                                                                                                             |
|--------------------------------------------------------------|---------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| Helm umbrella chart `kacho-deploy`                           | `dependencies[name=resource-manager]`, `dependencies[alias=pg-resource-manager]`| оба removed; `make dev-up` поднимает стенд без RM pod'а и без RM Postgres                                                       |
| Postgres database `kacho_resource_manager`                   | существует; содержит seed `folders.default`                                     | dropped (через `migrator down --all` ИЛИ `DROP DATABASE` — см. D-3)                                                              |
| Proto package `kacho.cloud.resourcemanager.v1`               | `proto/kacho/cloud/resourcemanager/v1/*.proto` + `gen/go/.../resourcemanager/`  | оба удалены целиком (5 `.proto` + `gen/go/.../resourcemanager/v1/` директория)                                                  |
| Proto package `kacho.cloud.organizationmanager.v1`           | `proto/kacho/cloud/organizationmanager/v1/*.proto` + `gen/go/...`               | оба удалены целиком (3 `.proto` + `gen/go/.../organizationmanager/v1/`)                                                          |
| Proto package `kacho.cloud.access.*` (legacy)                | `proto/kacho/cloud/access/*.proto` + `gen/go/kacho/cloud/access/` (помечены `deprecated` в E0) | удалены целиком — в том же kacho-proto PR-1, что и resourcemanager/organizationmanager (см. D-5)                |
| api-gateway REST mux (`kacho-api-gateway`)                   | `rmAddr` / `rmInternalAddr` registrations: Cloud/Folder/Organization handlers  | все три RegisterXxxServiceHandlerFromEndpoint удалены; `import rmpb / orgpb` удалён; `addrs["resourcemanager"]` not consumed   |
| api-gateway ID-prefix allowlist                              | префиксы `b1g` (organization), `b1c` (cloud), `b1f` (folder) → `resourcemanager`| три префикса удалены из routing table; запросы `/<prefix>/...` → 404 default mux                                                |
| GitHub repo `PRO-Robotech/kacho-resource-manager`            | active (последние commits — E1 deprecation markers)                             | archived (`gh repo archive` или Settings → Archive); read-only, no new issues/PRs accepted                                       |
| Workspace docs (`docs/specs/00-overview-and-scope.md`, `01-architecture-and-services.md`, `04-roadmap-and-phasing.md`) | RM упомянут как «retired service, replaced by kacho-iam» | RM удалён из таблиц сервисов целиком ИЛИ перенесён в раздел "Retired services" с явной ссылкой на эпик KAC-104                  |
| Workspace `CLAUDE.md` §«Структура репозиториев»              | строка `kacho-resource-manager` присутствует                                    | строка удалена; в §«Кросс-репо зависимости» edges to/from RM удалены                                                             |
| Obsidian vault (`obsidian/kacho/`)                           | `resources/rm-*.md`, `rpc/rm-*.md`, `edges/*-to-rm-*.md`, `packages/rm-*.md` — live | переменсены в `obsidian/kacho/_archive/rm/`; README.md / INDEX.md / architecture.md обновлены без RM entries                     |
| Per-service Go imports / configs                             | потенциальные остатки `KACHO_*_RM__*` env, `FolderClient`, `clients/folder_client.go` | grep-clean: ни одного упоминания `kacho-resource-manager` / `resourcemanager` / `FolderService` / `OrganizationService` / `CloudService` / `FolderClient` в product-code (исключение — `_archive/`) |

**E5 НЕ включает** (вынесено явно):

- **Data migration `organizations`+`clouds`+`folders` → `accounts`+`projects`.** На момент E5 в dev
  ничего ценного нет (заведомо чистый стенд после `make dev-down -v && make dev-up`); в staging /
  prod-инсталляций Kachō ещё нет. Если в будущем появятся — отдельная sub-phase ИЛИ runbook
  (out of scope для acceptance).
- **Backup / snapshot БД `kacho_resource_manager` перед drop.** В dev — нет (PVC уничтожается с
  `make dev-down -v`); в staging — manual runbook (см. D-3 §«Open Questions»).
- **`Gone 410` REST-handler для устаревших путей `/resource-manager/v1/*`.** Сначала рассматривался
  как часть E5 (см. stub §2.1), но **отвергнут** в этом v1 — см. Decision D-1 «full removal vs
  Gone-handler»: дешевле и чище удалить routes полностью; запрос → стандартный 404 default REST mux'а
  api-gateway.
- **`kacho-yc-shim`** совместимости для удалённых RM RPC — out of scope для всей фазы 2.0
  (overview §9).
- **Backfill `Operation.principal_*` для исторических Operation rows.** RM-генерируемые
  operations не имели principal (был stub `'system'` per E1); новые — уже имеют (per E4).
  Backfill — out of scope.
- ~~**Удаление proto `kacho.cloud.access.*`**~~ — **включено** в E5 v2 (см. D-5). Они мигрируют в
  `kacho.cloud.iam.v1.access_binding.proto` в E0 и помечаются `option deprecated`; в E5 PR-1
  (kacho-proto) — удаляются вместе с resourcemanager/organizationmanager пакетами и
  `gen/go/kacho/cloud/access/`.

После E5 проект попадает в финальное состояние «Kachō полностью на IAM-модели Account/Project,
никакого `kacho-resource-manager` нигде нет». Эпик KAC-104 закрывается.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент / запрет                                                  | Где соблюдаем                                                                                                                                                            |
|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Запрет #1** — кодирование только после APPROVED acceptance         | данный документ — gate; статус выше `DRAFT v1`                                                                                                                            |
| **Запрет #2** — НЕ упоминать "yandex"                               | в новых artefacts / docs / vault / commit-messages — не упоминается                                                                                                       |
| **Запрет #4** — НЕ каскад через границу сервиса                     | удаление RM **не** триггерит каскадное удаление в vpc/compute/lb; они уже на `project_id` после E1, ссылок на RM нет; БД RM дропается изолированно                       |
| **Запрет #5** — НЕ редактировать применённую миграцию               | новой DB-миграции в E5 нет (drop database — операционный шаг, не sql-миграция); E1-миграции в vpc/compute/lb НЕ откатываются (они правильные)                            |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint              | удаление `rmAddr` / `rmInternalAddr` registrations из api-gateway — оба listeners (public + internal) очищаются от RM-routes                                              |
| **Запрет #8** — DB-per-service                                      | drop `kacho_resource_manager` — изолированная БД, ничего не каскадирует; vpc/compute/lb базы не затрагиваются                                                             |
| **Запрет #11** — тесты в том же PR                                  | каждый E5-PR содержит regression-тест на отсутствие удалённого: api-gateway PR — `mux_test.go` проверяет 404 на `/resource-manager/v1/*`; kacho-proto PR — `buf lint` зелёный без RM/OM packages |
| **§«Документооборот»** workspace `CLAUDE.md`                        | KAC-110 — branch `KAC-110` в каждом из 4 затронутых репо; PR'ы → comment в YT тикет; epic KAC-104 closeout — финальный комментарий с ссылками на 6 sub-эпиков             |
| **§«Obsidian vault — обязательный context-источник и trail»**       | rm-* entries → `_archive/rm/`; edges/* убраны; KAC-110.md создан/обновлён                                                                                                 |
| **YC-стилистика — да, структура — по делу**                         | удаление RM — не «отход от YC-стиля», это **структурное** решение (Kachō не нужен Org→Cloud→Folder, нужен Account→Project); стиль ошибок других сервисов не затрагивается  |

---

## 2. Decision Log — фундаментальные решения, зафиксированные до GWT

Все 4 решения ниже резолвят open questions из stub'а §6 и являются нормативными для всех 15+
сценариев. Реализация, расходящаяся с любым из них, — нарушение acceptance.

### Decision D-1 — Full removal proto + deployment + БД, без `Gone 410` REST-handler

**Выбор**: **full removal**. Routes `/resource-manager/v1/*`, `/organization-manager/v1/*` удаляются
из api-gateway полностью; запросы на них получают стандартный 404 default mux'а — не специальный
`Gone 410` со ссылкой на migration docs.

**Альтернатива (stub §2.1 предлагал)**: оставить statically-configured `Gone 410` handler со
JSON-телом `{"code":410, "message":"resource manager deprecated; use /iam/v1/accounts and /iam/v1/projects", "details":[{"link":"https://docs.kacho.io/migration/iam"}]}`. Идея — graceful
degradation для старых клиентов.

**Обоснование выбора full removal**:

1. **Pre-1.0 контракт**. Kachō ещё не объявил stable public API; нет external SLA-bound клиентов;
   единственные потребители — `kacho-ui` (под нашим контролем, мигрирован в E4) и
   `tests/newman/*` (под нашим контролем, мигрирован в E1). Никто не страдает от 404.
2. **YAGNI**. `Gone 410` — extra code в api-gateway (registry static handler + JSON-fixture +
   regression test); чистка через 6 месяцев (open question stub §6.4) — отдельная задача.
   Удалить routes сразу — однократно и не возвращаться.
3. **Diagnosability**. 404 от api-gateway включает request-path в response → клиент сразу
   видит «`/resource-manager/v1/folders` not registered» — это явный сигнал «эта поверхность
   удалена», ничем не хуже custom-401-style сообщения. Если кто-то жалуется в support — ссылка
   на migration docs даётся вручную, не через JSON-payload.
4. **Кратность маршрутов**. Удаление 3 sub-routes (Cloud, Folder, Organization) и 2 ID-prefix
   групп — тривиальная git-diff; добавление `Gone 410`-handler — три extra registrations +
   тест на каждый. Net code change: full removal ~10 LOC меньше, чем Gone-handler.
5. **kacho-resource-manager deprecation strategy уже была "не coexistance"** (overview §5
   решение #11): «выключение полностью, не coexistance». `Gone 410` — частичный compromise
   "выключили сервис но REST-paths кое-как живут"; это противоречит уже-resolved решению.

**Следствия**:
- В `kacho-api-gateway/internal/restmux/mux.go` удаляются строки 75 (`import rmpb`), 76 (`import orgpb`),
  202-203 (`rmAddr := addrs["resourcemanager"]`), 217-235 (блок `if rmAddr != "" { ... }` целиком).
- В `mux_test.go` test-case `path: "/resource-manager/v1/folders/f-1"` (строка 137) удаляется
  ИЛИ заменяется на `expectStatus: 404` regression-test.
- ID-prefix routing table (`internal/restmux/prefix_routing.go` если есть, либо встроено в `mux.go`)
  — префиксы `b1g`/`b1c`/`b1f` (если есть) удаляются.
- Cluster default mux api-gateway возвращает standard `404 Not Found` HTML/text без JSON-payload —
  это existing-behavior, ничего не меняется.

### Decision D-2 — Full proto cleanup в этом эпике, без deprecated-marker-phase

**Выбор**: удалить `proto/kacho/cloud/resourcemanager/v1/` и `proto/kacho/cloud/organizationmanager/v1/`
**полностью** в E5 (5 + 3 = 8 `.proto` файлов) + соответствующие `gen/go/.../v1/` директории.
Никаких `option deprecated = true;` промежуточных шагов.

**Альтернатива (overview §6 решение #2 ранее зафиксировал «deprecated marker сейчас, удаление в
Phase 3»)**: оставить proto и gen/go помеченными `deprecated`, удалить в Phase 3 (semver major
bump).

**Обоснование выбора full removal сейчас**:

1. **`deprecated` уже отработан**. После E1 (KAC-106) proto'ы помечены `option deprecated = true;`
   на каждом message + service (overview §5 предполагал это; E1-acceptance D-1 verifyint). Между
   E1-merge и E5-merge proto существует в `deprecated`-state; ни один консумер его не использует
   (E1 верифицирует). Дополнительная фаза `deprecated` уже была — она прошла.
2. **Нет downstream-консумеров за пределами `PRO-Robotech/kacho-*`**. Все importers `gen/go/...`
   проверяются grep-ом перед удалением (см. §«Pre-conditions checklist» ниже). Если grep clean —
   удаление безопасно.
3. **`buf breaking` будет красным на этом PR** — это **желаемое** поведение (явный signal
   "structural break"); merger пропускает с `--breaking-skip` ONLY для proto'ов, помеченных
   `deprecated` в предыдущем PR (специально для этого случая). В `kacho-proto/buf.yaml`
   добавляется временный exception `breaking: { except: [PACKAGE_NO_DELETE] }` для пакетов
   `kacho.cloud.resourcemanager.v1` + `kacho.cloud.organizationmanager.v1` на ОДИН CI-run;
   после merge — exception removed.
4. **gen/go удалять сразу — обязательно**. Если оставить `gen/go/.../resourcemanager/` — оно
   попадёт в `go build ./...` всех importers (через transitive build); кто-то может случайно
   импортировать. Лучше удалить — `go build` сразу падает с "package not found" → явный signal.
5. **Phase 3** — не определена ни по сроку, ни по содержанию; «отложим на Phase 3» = «никогда
   не сделаем». Гигиенически правильно — удалить сейчас, пока есть momentum.

**Следствия**:
- `kacho-proto/proto/kacho/cloud/resourcemanager/v1/` — `rm -rf`; 5 `.proto` файлов исчезают.
- `kacho-proto/proto/kacho/cloud/organizationmanager/v1/` — `rm -rf`; 3 `.proto` файла исчезают.
- `kacho-proto/gen/go/kacho/cloud/resourcemanager/v1/` — `rm -rf` (генерация перепрогоняется
  `make proto-gen` — должна быть no-op, поскольку source-protos удалены).
- `kacho-proto/gen/go/kacho/cloud/organizationmanager/v1/` — `rm -rf`.
- `buf lint` после удаления — зелёный (нет orphan deps).
- `buf breaking` — добавляется временный exception в `buf.yaml`:
  ```yaml
  breaking:
    use:
      - WIRE_JSON
    except:
      - PACKAGE_NO_DELETE  # E5 KAC-110: removing kacho.cloud.{resourcemanager,organizationmanager}.v1
  ```
  После merge — exception убирается в follow-up PR.

### Decision D-3 — БД drop через `DROP DATABASE` (не через `migrator down --all`)

**Выбор**: `kacho_resource_manager` Postgres-БД дропается **прямой SQL-командой**
`DROP DATABASE kacho_resource_manager;` от superuser-роли (`postgres` или admin'а cluster'а).
Не через `kacho-migrator down --all` (`kacho-resource-manager/cmd/migrator/main.go down --all`).

**Альтернатива A**: `migrator down --all` — пройти все вниз-миграции в обратном порядке
(`0008_xyz.down.sql` → ... → `0001_initial.down.sql`), оставить БД пустой; затем `DROP DATABASE`.

**Обоснование выбора прямого DROP**:

1. **Идемпотентность**. `DROP DATABASE IF EXISTS kacho_resource_manager` — single statement,
   atomic, повторяется тривиально. `migrator down --all` требует чтобы все down-миграции
   присутствовали и были валидны; если хоть одна down-миграция падает (например, sequence
   removal) — процедура застревает на полпути.
2. **Time**. `DROP DATABASE` — секунды. `migrator down --all` через ~8 миграций — десятки
   секунд + потенциальные edge-cases.
3. **БД будет уничтожена в любом случае**. Если цель — освободить storage, нет смысла
   аккуратно сворачивать схему вниз-миграциями; DROP делает то же самое без процедурных
   шагов.
4. **PVC** удаляется через helm uninstall (см. D-4 ниже) — Postgres-pod вместе с PVC
   исчезает; даже если БД остаётся внутри, контейнер дропается. Тем не менее, ЯВНО дропаем БД
   перед helm uninstall — это **гарантия**, что никакая reconnect-логика не оживит зомби-данные.
5. **Runbook**: PR с removal helm chart (kacho-deploy) включает в `runbook.md` (`docs/operations/e5-rm-uninstall.md`) шаги для prod:
   ```bash
   # 1a. Backup dump внутри pod'а (prod-only; в dev — skip):
   kubectl exec -n kacho pg-resource-manager-0 -- pg_dump -U kacho_resource_manager \
     kacho_resource_manager > /tmp/rm-backup.sql

   # 1b. Вытащить backup НАРУЖУ pod'а в persistent storage (B4 fix —
   # /tmp/ в pod'е уничтожается с pod'ом при helm uninstall):
   kubectl cp pg-resource-manager-0:/tmp/rm-backup.sql ./rm-backup-$(date +%F).sql -n kacho
   # Verify файл локально:
   ls -lh ./rm-backup-$(date +%F).sql   # должен быть non-empty

   # 2. Drop database (idempotent):
   kubectl exec -n kacho pg-resource-manager-0 -- psql -U postgres -c \
     "DROP DATABASE IF EXISTS kacho_resource_manager;"

   # 3. helm uninstall (см. D-4):
   helm upgrade kacho ./helm/umbrella -n kacho -f values.dev.yaml  # без RM/pg-RM deps
   ```
   **Backup retention policy** — out of scope для pre-1.0 (defer; prod policy будет определена
   ближе к 1.0 release когда появится first prod tenant).

**Следствия**:
- В dev — `make dev-down -v` уничтожает PVC; БД исчезает с диском.
- В staging / prod (если бы) — manual runbook (выше).
- `kacho-resource-manager/cmd/migrator/main.go` — НЕ обязан иметь рабочие down-миграции для E5
  (т.к. не используется); если есть — оставлены as-is (репо архивируется, не правится).

### Decision D-4 — Workspace CLAUDE.md: full removal RM-row, не strikethrough

**Выбор**: в workspace `CLAUDE.md` §«Структура репозиториев» **удалить целиком** строку
`kacho-resource-manager` из таблицы сервисов. Не помечать ~~strikethrough~~ + "archived,
replaced by kacho-iam".

**Альтернатива**: оставить строку как ~~`kacho-resource-manager`~~ — `**Retired** (KAC-104),
replaced by [kacho-iam]` для исторической памяти.

**Обоснование full removal**:

1. **CLAUDE.md — operating document, не журнал**. Он читается агентами каждый раз при запуске;
   strikethrough-row занимает context-budget и потенциально путает (агент может попытаться
   "восстановить deprecated сервис"). Гигиена: что не существует — нет в таблице.
2. **История остаётся в git**. `git log` + commit-message E5-PR'а («docs(workspace): remove
   kacho-resource-manager row, deprecated по KAC-104») — достаточная trail. Кому надо понять
   "что было раньше" — пройдёт по эпику в YouTrack KAC-104 ИЛИ по vault `KAC/KAC-104.md`.
3. **Vault `_archive/rm/`** — отдельный канал исторической памяти; vault трекает архив, CLAUDE.md
   трекает current state.
4. **Однотипность с другим resolved-эпиком**. KAC-15 (geography move vpc → compute) — таблица
   обновлена аналогично: `Region`/`Zone` упомянуты как «owned by kacho-compute», старая kacho-vpc
   row не оставлена в "deprecated" виде.

**Следствия**:
- Строка `| `kacho-resource-manager` | Organization / Cloud / Folder |` — удалена из таблицы.
- В §«Кросс-репо зависимости» — диаграмма обновлена, edges `* → kacho-resource-manager` удалены.
- В §«Кросс-доменные ссылки» §5 «карта владельцев доменов» — строка
  `Organization / Cloud / Folder → kacho-resource-manager` либо удалена целиком, либо заменена
  на `Account / Project → kacho-iam` (если ещё не было обновлено в E4).
- В разделе «Не путать с feature-acceptance-флоу» / других местах — все упоминания
  `kacho-resource-manager` / `Folder` / `Cloud` / `Organization` (как ресурсов RM) — заменены
  на Account/Project или удалены.
- **GWT-14 strict**: `grep -c "kacho-resource-manager" CLAUDE.md` → **строго 0** (не «<=2»).
  Любое упоминание = блокер; перенос в `_archive/`-context idiom не допускается в CLAUDE.md
  (только в vault `_archive/rm/`).

### Decision D-5 — `kacho.cloud.access.*` legacy proto cleanup в E5 PR-1

**Выбор**: удалить proto `kacho.cloud.access.*` (legacy messages без `service` блока) **в том же
kacho-proto PR-1, что и resourcemanager / organizationmanager** — `proto/kacho/cloud/access/*.proto`
+ `gen/go/kacho/cloud/access/` целиком. Это resolves OQ-1 (resolved).

**Альтернатива** (v1 предлагал defer): оставить `kacho.cloud.access.*` как `deprecated` ещё на одну
фазу, удалить позже отдельным PR.

**Обоснование cleanup сейчас**:

1. **`kacho.cloud.access.*` уже мигрирован в E0**. Содержимое перенесено в
   `kacho.cloud.iam.v1.access_binding.proto`; legacy package помечен `option deprecated = true`
   в E0. Между E0-merge и E5 — он живёт как `deprecated`-скелет.
2. **Принцип консистентности**. PR-1 уже удаляет 2 deprecated-пакета (resourcemanager +
   organizationmanager); добавить третий (access) — однотипная гигиеническая правка, не
   увеличивает review-surface существенно.
3. **Один cleanup-cycle лучше двух**. «Отложим access на потом» = «забудем»; resourcemanager
   уже доказал, что defer не работает (overview §6 решение #2 предполагал deprecated в одной
   фазе, full removal в Phase 3 — но Phase 3 не определён). Лучше закрыть всё legacy сейчас.
4. **PACKAGE_NO_DELETE exception всё равно нужен** (см. D-2 / D-6) — добавить третий пакет в
   exception-list — однострочное изменение в `buf.yaml`. Net code change — минимальный.

**Следствия**:
- `kacho-proto/proto/kacho/cloud/access/` — `rm -rf` (целиком).
- `kacho-proto/gen/go/kacho/cloud/access/` — `rm -rf`.
- `kacho-proto/buf.yaml` exception list — третий пакет:
  ```yaml
  breaking:
    use:
      - WIRE_JSON
    except:
      - PACKAGE_NO_DELETE  # E5 KAC-110: removing kacho.cloud.{resourcemanager,organizationmanager,access}.*
  ```
- Verification grep (новый pre-condition #9 в §5): `grep -rln "kacho.cloud.access\|access/v1" project/kacho-{vpc,compute,loadbalancer,iam,api-gateway,ui}/` → пусто. Если что-то импортирует
  legacy `access.*` — блок E5 до cleanup-PR в найденный сервис.

### Decision D-6 — Post-merge cleanup `PACKAGE_NO_DELETE` exception

**Выбор**: временный exception `PACKAGE_NO_DELETE` в `buf.yaml` (см. D-2 / D-5) **обязательно
убирается follow-up PR'ом в kacho-proto сразу после merge основного PR-1**. Это часть DoD эпика —
**DoD-9** (см. §7).

**Альтернатива A** (предпочтительнее, если есть CI-инфра): использовать CI env-flag — например,
`buf breaking --against ... --error-format=json | jq '.[] | select(.id != "PACKAGE_NO_DELETE")'`
ИЛИ `BUF_BREAKING_IGNORE_PACKAGES=kacho.cloud.resourcemanager.v1,kacho.cloud.organizationmanager.v1,kacho.cloud.access` ENV-flag в CI workflow YAML — exception применяется **только** к этому конкретному CI-run'у, не leak'ает в `buf.yaml` `main`-ветки. Если CI tooling это поддерживает — предпочесть; иначе fall back на временный exception в `buf.yaml` + follow-up cleanup PR.

**Обоснование**: stale exception в `main` рискует превратиться в **постоянную дыру** в breaking
detection. После закрытия KAC-110 exception теряет смысл (deleted packages не вернутся, никаких
будущих PACKAGE_NO_DELETE мы по ним не получим), но останется в `buf.yaml` — следующее
осознанное удаление пакета пройдёт незамеченно ⇒ regression.

**Следствия**:
- **DoD-9** добавлен в §7: «Post-merge cleanup PR в kacho-proto убирает PACKAGE_NO_DELETE
  exception из `buf.yaml`; `buf breaking --against '.git#branch=main'` зелёный без exception».
- **GWT-17** добавлен в §6: проверка, что exception removed.
- Если предпочли CI env-flag вариант (А): `buf.yaml` `main`-ветки **никогда** не содержит
  exception; в `.github/workflows/*.yml` для PR-1 — один-time env-flag, который удаляется в
  следующем PR.
- Tracking: создать tracking-issue в `PRO-Robotech/kacho-proto` (`tech-debt` label) на cleanup;
  ссылка — в KAC-110 closeout comment.

### Decision D-7 — CHANGELOG entries: per-эпик + closeout summary

**Выбор**: в `docs/specs/04-roadmap-and-phasing.md` — **отдельный CHANGELOG entry на каждый
E1…E5 sub-эпик** (5 entries) **плюс** один итоговый closeout summary на KAC-104 в epic-comment
YouTrack. Это resolves OQ-4 (resolved).

**Альтернатива** (v1 предлагал): объединить в один entry «KAC-104 — IAM (includes RM
deprecation E5) — closed».

**Обоснование per-эпик entries**:

1. **Trail granularity**. Каждый из E1…E5 — отдельный merge-set с собственным набором PR'ов
   (по 4 PR на E1, по 5 PR на E5 и т.д.); отдельный entry даёт точный pointer на «когда что
   произошло».
2. **Эпик-уровневая сводка — отдельный канал**. KAC-104 closeout summary в YouTrack-comment'е —
   это про *эпик целиком* (links на 6 sub-эпиков, итоговая архитектурная разница, retrospective);
   CHANGELOG в `04-roadmap-and-phasing.md` — про *технические артефакты* (которые PR'ы попали
   в `main`).
3. **Не дублирует, дополняет**. CHANGELOG-entries в roadmap — короткие («KAC-110 — RM
   deprecation — merged YYYY-MM-DD, 5 PR'ов»); YouTrack epic-comment — длинный (что было,
   что стало, что осталось как tech-debt).

**Следствия**:
- В `docs/specs/04-roadmap-and-phasing.md` Phase 2.0 — 5 CHANGELOG entries (по одному на
  E1…E5), плюс заключительная строка «KAC-104 — Phase 2.0 (IAM) — fully closed YYYY-MM-DD».
- KAC-104 в YouTrack — финальный comment-summary со ссылками на 6 sub-эпиков (KAC-105 = E0,
  KAC-106 = E1, KAC-107 = E2, KAC-108 = E3, KAC-109 = E4, KAC-110 = E5) + ссылками на vault
  `KAC/KAC-104.md`.
- OQ-4 удаляется (resolved).

### Decision D-8 — Никакого release/tag в kacho-resource-manager pre-archive

**Выбор**: **НЕ создавать** финальный release / git-tag в `PRO-Robotech/kacho-resource-manager`
перед archive. Final commit с README banner — достаточно. Это resolves OQ-5 (resolved).

**Альтернатива** (v1 предлагал в OQ): открыть `v1.0.0-final` release с RELEASE.md +
release-binary.

**Обоснование**:

1. **Нет stable release pipeline**. Kachō в pre-1.0; ни один из sibling-репо не публикует
   versioned releases (только rolling `main` + per-commit Docker tag); `kacho-resource-manager`
   — не исключение. Открыть финальный release ради archive — out-of-pattern.
2. **`gh repo archive` + final commit с banner** — стандартный flow для retired-сервисов в
   GitHub; tag не добавляет ценности.
3. **`git log` — достаточный trail**. История commits + commit-message последнего commit'а
   («docs(README): archive banner, retired by KAC-104 / KAC-110») — единственная нужная
   точка для исторической памяти.
4. **YAGNI**. Release требует RELEASE.md / changelog / binary upload / verification — этой
   работы нет в DoD; если никто это не зарядил — не зачем добавлять.

**Следствия**:
- В §4.5 (kacho-resource-manager archive flow) — никаких `gh release create` / git-tag steps.
- OQ-5 удаляется (resolved).

---

## 3. Target architecture — до и после E5

### 3.1 До E5 (состояние после E4-merge)

```
                    ┌─────────────────────────────┐
                    │       kacho-api-gateway     │
                    │  - routes /vpc/v1/*         │
                    │  - routes /compute/v1/*     │
                    │  - routes /loadbalancer/v1/*│
                    │  - routes /iam/v1/*         │
                    │  - routes /resource-manager/v1/* ─────┐    ← E5 removes this
                    │  - routes /organization-manager/v1/* ─┤    ← E5 removes this
                    │  - imports rmpb, orgpb               │
                    └──────┬───────────────────────────────┘
                           │
        ┌──────────────────┼────────────────────┬──────────────────┐
        ▼                  ▼                    ▼                  ▼
  ┌──────────┐      ┌─────────────┐      ┌──────────────┐    ┌────────────────────┐
  │kacho-iam │      │  kacho-vpc  │      │kacho-compute │    │kacho-resource-     │
  │          │      │             │      │              │    │manager (live but   │
  │ Account  │      │ Network/    │      │ Instance/    │    │ unused — peers     │
  │ Project  │      │ Subnet/...  │      │ Disk/...     │    │ migrated to iam    │
  │ User/SA  │      │             │      │              │    │ in E1)             │
  │ Group    │      │ ProjectClient│     │ ProjectClient│    │ Organization/      │
  │ Role     │      │ → iam       │      │ → iam        │    │ Cloud/Folder       │
  │ AccessBnd│      │             │      │              │    │                    │
  └──────────┘      └─────────────┘      └──────────────┘    └────────────────────┘
                                                                       │
                                                                       ▼
                                                            ┌──────────────────┐
                                                            │ pg-resource-     │
                                                            │ manager (Postgres│
                                                            │ + PVC; data:     │
                                                            │ seed default     │
                                                            │ folder/cloud/org)│
                                                            └──────────────────┘
```

### 3.2 После E5 (target state)

```
                    ┌─────────────────────────────┐
                    │       kacho-api-gateway     │
                    │  - routes /vpc/v1/*         │
                    │  - routes /compute/v1/*     │
                    │  - routes /loadbalancer/v1/*│
                    │  - routes /iam/v1/*         │
                    │  (no rmpb/orgpb imports)    │
                    └──────┬──────────────────────┘
                           │
        ┌──────────────────┼────────────────────┐
        ▼                  ▼                    ▼
  ┌──────────┐      ┌─────────────┐      ┌──────────────┐
  │kacho-iam │      │  kacho-vpc  │      │kacho-compute │
  │          │      │             │      │              │
  │ Account  │      │ Network/... │      │ Instance/... │
  │ Project  │      │             │      │              │
  │ User/SA  │      │ ProjectClient│     │ ProjectClient│
  │ Group    │      │ → iam       │      │ → iam        │
  │ Role     │      │             │      │              │
  │ AccessBnd│      └─────────────┘      └──────────────┘
  └──────────┘
       ▲
       │ (kacho-resource-manager pod removed;
       │  pg-resource-manager Postgres removed;
       │  kacho_resource_manager database dropped;
       │  proto/kacho/cloud/resourcemanager/ and
       │  organizationmanager/ removed from kacho-proto;
       │  GitHub repo archived)
```

### 3.3 Что точно НЕ меняется в E5

- `kacho-iam` — никаких изменений (CRUD Account/Project уже есть с E0).
- `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` — никакого кода не меняется (E1 уже снёс
  FolderClient); E5 — verification grep-only.
- `kacho-corelib` — никаких изменений.
- БД `kacho_iam`, `kacho_vpc`, `kacho_compute`, `kacho_loadbalancer` — никаких миграций.
- proto-стабы `kacho.cloud.iam.v1`, `vpc.v1`, `compute.v1`, `loadbalancer.v1`, `operation.v1`,
  `common.v1` — без изменений.
- `kacho-ui` — никаких изменений в E5 (E4 уже снёс Org/Cloud/Folder pages); E5 — verification
  grep-only.

---

## 4. Декомпозиция работ — по репозиториям

### 4.1 kacho-proto

| Файл / директория                                                | Действие           |
|------------------------------------------------------------------|--------------------|
| `proto/kacho/cloud/resourcemanager/v1/cloud.proto`               | `rm`               |
| `proto/kacho/cloud/resourcemanager/v1/cloud_service.proto`       | `rm`               |
| `proto/kacho/cloud/resourcemanager/v1/folder.proto`              | `rm`               |
| `proto/kacho/cloud/resourcemanager/v1/folder_service.proto`      | `rm`               |
| `proto/kacho/cloud/resourcemanager/v1/package_options.proto`     | `rm`               |
| `proto/kacho/cloud/resourcemanager/v1/` (directory)              | `rmdir`            |
| `proto/kacho/cloud/resourcemanager/` (directory, если пустая)    | `rmdir`            |
| `proto/kacho/cloud/organizationmanager/v1/organization.proto`            | `rm`               |
| `proto/kacho/cloud/organizationmanager/v1/organization_service.proto`    | `rm`               |
| `proto/kacho/cloud/organizationmanager/v1/package_options.proto`         | `rm`               |
| `proto/kacho/cloud/organizationmanager/v1/` (directory)                  | `rmdir`            |
| `proto/kacho/cloud/organizationmanager/` (directory, если пустая)        | `rmdir`            |
| `gen/go/kacho/cloud/resourcemanager/v1/` (directory)             | `rm -rf`           |
| `gen/go/kacho/cloud/organizationmanager/v1/` (directory)         | `rm -rf`           |
| `proto/kacho/cloud/access/` (directory, D-5)                     | `rm -rf` (все `.proto` files целиком; `kacho.cloud.access.*` legacy, помечены `deprecated` в E0)              |
| `gen/go/kacho/cloud/access/` (directory, D-5)                    | `rm -rf`           |
| `buf.yaml`                                                       | временный exception (см. D-2 + D-5: 3 пакета в list); **либо** CI env-flag вариант (предпочтительнее, см. D-6) — exception **не попадает** в `buf.yaml` `main`-ветки; после merge — exception removed follow-up PR'ом per D-6 |
| `buf.gen.yaml`                                                   | проверить — может содержать explicit per-package config; если есть для resourcemanager/organizationmanager/access — удалить |
| `Makefile`                                                       | `make proto-gen` после удаления должен быть зелёный (no-op) |

**Acceptance per kacho-proto PR**:
- [ ] `make proto-gen` runs без ошибок (нет orphan-references).
- [ ] `git diff --stat` показывает удаление 8 + N `.proto` + ~16-20 + M `.pb.go` / `.pb.gw.go` файлов в gen/ (где N+M — `kacho.cloud.access.*` per D-5).
- [ ] `buf lint` зелёный.
- [ ] `buf breaking --against '.git#branch=main'` падает с `PACKAGE_NO_DELETE` для **трёх** пакетов
  (resourcemanager, organizationmanager, access);
  это **ожидаемо** и pass'ится через **либо** временный exception в `buf.yaml` (D-2 + D-5)
  **либо** CI env-flag (D-6, предпочтительнее — exception не попадает в `main`-ветку `buf.yaml`).
- [ ] commit-message: `proto(kacho-proto): remove resourcemanager + organizationmanager + access packages (KAC-110, E5)`.
- [ ] Follow-up tracking-issue в `PRO-Robotech/kacho-proto` создан на cleanup PACKAGE_NO_DELETE exception (D-6).

### 4.2 kacho-api-gateway

| Файл                                                | Действие                                                                                                                                                     |
|-----------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `internal/restmux/mux.go`                           | удалить `import rmpb`, `import orgpb`; удалить `rmAddr := addrs["resourcemanager"]`; удалить `if rmAddr != "" { ... }` блок целиком (Cloud, Folder, Organization handlers) |
| `internal/restmux/mux.go` (комментарий на строке 41-42) | удалить упоминания `resourcemanager.v1: Cloud, Folder` и `organizationmanager.v1: Organization` из header-comment                                      |
| `internal/restmux/mux.go` (строки 148-149)          | удалить упоминания `"resourcemanager" → resource-manager.kacho.svc.cluster.local:9090` из comment'ов                                                          |
| `internal/restmux/prefix_routing.go` (если есть)    | удалить prefix-routing entries для `b1g` (organization), `b1c` (cloud), `b1f` (folder) — если они там зарегистрированы; verify через `grep -n "b1g\|b1c\|b1f"` |
| `internal/restmux/mux_test.go`                      | test-case `path: "/resource-manager/v1/folders/f-1"` (строка 137) либо удалить, либо заменить на assertion `expectStatus: 404` (см. GWT-09)                  |
| `internal/restmux/mux_test.go`                      | добавить новые test-cases: `/resource-manager/v1/*`, `/organization-manager/v1/*`, `/clouds/*`, `/folders/*` → ожидают `404 Not Found` (GWT-09, GWT-10)       |
| `internal/config/config.go` (если есть)             | удалить `resourcemanager` из списка backend-addrs ENV-vars (`KACHO_GW_RESOURCEMANAGER__ADDR` и т.п.)                                                          |
| `helm/values.yaml` / `helm/values.dev.yaml` (если api-gateway sub-chart имеет) | удалить ссылку на `resourcemanager` backend address                                                                              |

**Acceptance per kacho-api-gateway PR**:
- [ ] `go build ./...` зелёный после удаления imports.
- [ ] `go test ./internal/restmux/...` зелёный; новый regression-test проверяет 404 на устаревших путях.
- [ ] `grep -rn "resourcemanager\|organizationmanager\|rmpb\|orgpb\|FolderService\|OrganizationService\|CloudService" internal/` — пусто.
- [ ] PR-описание: `Closes KAC-110` (один из четырёх PR в этом эпике; по PR на репо).

### 4.3 kacho-deploy

| Файл                                                | Действие                                                                                                                                                     |
|-----------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `helm/umbrella/Chart.yaml` (строка 35-37)           | удалить `- name: resource-manager\n  version: 0.1.0\n  repository: file://../../../kacho-resource-manager/deploy` блок целиком                              |
| `helm/umbrella/Chart.yaml` (строка 10)              | удалить `- name: postgresql\n  version: 12.x.x\n  repository: https://charts.bitnami.com/bitnami\n  alias: pg-resource-manager\n  condition: pg-resource-manager.enabled` блок |
| `helm/umbrella/values.dev.yaml` (строка 33-36)      | удалить `pg-resource-manager:` block целиком (postgres credentials, image config)                                                                            |
| `helm/umbrella/values.dev.yaml`                     | удалить любые ссылки `resource-manager: {...}` (image, env, replicas)                                                                                        |
| `helm/umbrella/values.prod.yaml` (если есть)        | то же, что values.dev.yaml                                                                                                                                   |
| `helm/umbrella/templates/_helpers.tpl` (если есть)  | проверить, нет ли helper'ов, ссылающихся на `resource-manager` / `pg-resource-manager`                                                                        |
| `Makefile`                                          | удалить `make psql SVC=rm` / `make logs-svc SVC=rm` / `make reload-svc SVC=rm` shortcuts (если присутствуют — `grep -n "resource-manager\|SVC=rm"` Makefile)  |
| `scripts/` (если содержит RM-specific scripts)      | удалить (или mv в `_archive/`); `grep -rn "resource-manager" scripts/`                                                                                       |
| `docs/operations/e5-rm-uninstall.md` (новый)        | создать **runbook**: pre-conditions, шаги drop database (D-3 пример выше), helm uninstall, verification grep, prod-specific backup section; **обязательно** включить explicit backup-path step `kubectl cp pg-resource-manager-0:/tmp/rm-backup.sql ./rm-backup-$(date +%F).sql` после `pg_dump` (B4 fix — backup в /tmp/ внутри pod'а ≠ persistent backup; нужно вытащить наружу до helm uninstall) |
| `e2e/` (если содержит RM-specific e2e tests)        | удалить test cases (`grep -rn "resource-manager\|/folders\|/clouds\|/organizations" e2e/`)                                                                   |

**Acceptance per kacho-deploy PR**:
- [ ] `make dev-down -v && make dev-up` — стенд поднимается **без** `kacho-resource-manager-*` и `pg-resource-manager-*` pods; `kubectl get pods -n kacho` не содержит RM (GWT-05).
- [ ] Никаких failed init-containers / CrashLoopBackOff (GWT-06).
- [ ] Existing newman e2e suite (`tests/newman/cases/*`) — зелёный; ничего не сломалось от удаления RM.
- [ ] `docs/operations/e5-rm-uninstall.md` присутствует.
- [ ] commit-message: `chore(deploy): remove kacho-resource-manager + pg-resource-manager from umbrella chart (KAC-110, E5)`.

### 4.4 kacho-workspace (docs + vault + CLAUDE.md)

| Файл / директория                                                | Действие                                                                                                                                                     |
|------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `CLAUDE.md` §«Структура репозиториев» (таблица)                  | удалить строку `\| `kacho-resource-manager` \| Organization / Cloud / Folder \|` (D-4)                                                                       |
| `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения»       | удалить edges/упоминания `kacho-resource-manager` из ASCII-диаграммы; обновить runtime cross-domain edges section (`* → kacho-resource-manager` → `* → kacho-iam`) |
| `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы» §5 «карта владельцев» | удалить `Organization / Cloud / Folder → kacho-resource-manager`; убедиться что `Account / Project → kacho-iam` присутствует (вероятно, добавлен в E0/E1) |
| `CLAUDE.md` §«Запреты» #6                                        | проверить, есть ли упоминания `kacho-resource-manager` в примерах — обновить                                                                                  |
| `docs/specs/00-overview-and-scope.md`                            | удалить (или перенести в «Retired services» раздел) упоминания Organization/Cloud/Folder/kacho-resource-manager как активного сервиса                          |
| `docs/specs/01-architecture-and-services.md`                     | таблица сервисов — RM либо удалён, либо в разделе «Retired (history)»; ASCII-диаграмма сервисов без RM                                                         |
| `docs/specs/02-data-model-and-conventions.md`                    | если упоминается `Folder` как owner-scope — заменить на `Project`; `Organization`/`Cloud` — удалить                                                            |
| `docs/specs/03-deployment-and-operations.md`                     | удалить упоминания `make psql SVC=rm`, RM-specific dev-setup steps                                                                                            |
| `docs/specs/04-roadmap-and-phasing.md`                           | Phase 2.0 → status `done`; добавить итоговый CHANGELOG entry: `KAC-104 — IAM (Account/Project + Zitadel + OpenFGA) — closed`                                  |
| `docs/specs/sub-phase-2.0-iam-overview-acceptance.md`            | (если ещё в DRAFT) пометить status → APPROVED + closed; иначе — не трогать (уже approved)                                                                     |
| `obsidian/kacho/_archive/` (новая директория, если не было)      | `mkdir _archive/rm/`                                                                                                                                          |
| `obsidian/kacho/resources/rm-*.md`                               | `mv` → `obsidian/kacho/_archive/rm/resources/`                                                                                                                |
| `obsidian/kacho/rpc/rm-*.md`                                     | `mv` → `obsidian/kacho/_archive/rm/rpc/`                                                                                                                      |
| `obsidian/kacho/edges/*-to-rm-*.md`, `obsidian/kacho/edges/rm-to-*.md` | `mv` → `obsidian/kacho/_archive/rm/edges/`                                                                                                              |
| `obsidian/kacho/packages/rm-*.md`                                | `mv` → `obsidian/kacho/_archive/rm/packages/`                                                                                                                 |
| `obsidian/kacho/architecture.md` (если есть)                     | удалить RM из диаграммы / описания                                                                                                                            |
| `obsidian/kacho/README.md`                                       | удалить упоминания `resources/rm-*`, `rpc/rm-*` из links; убрать RM из «активные сервисы»                                                                     |
| `obsidian/kacho/INDEX.md`                                        | удалить алфавитные entries `rm-cloud`, `rm-folder`, `rm-organization`, `rm-folder-service`, etc.                                                               |
| `obsidian/kacho/KAC/KAC-104.md`                                  | финализировать: `Status: done`; добавить ссылки на все PR-ы из E5; summary итогов эпика                                                                       |
| `obsidian/kacho/KAC/KAC-110.md`                                  | создать/обновить: status `done` после merge всех 4 PR'ов; добавить ссылки на PR                                                                               |
| `obsidian/kacho/_archive/rm/README.md` (новый)                   | короткая summary: «kacho-resource-manager retired in KAC-104 / KAC-110 (2026-05-XX). Replaced by kacho-iam Account+Project. Vault entries below — historical reference only.» |
| `bootstrap.sh` (I5 fix)                                          | удалить `kacho-resource-manager` из списка clone-targets; после E5 — `./bootstrap.sh` не клонирует RM; локальный клон у разработчиков остаётся as-is (gitignored, не enforced) |
| `sync-all.sh` (I5 fix, если есть)                                | то же: удалить RM из update-loop                                                                                                                                              |

**Acceptance per kacho-workspace PR**:
- [ ] `grep -rn "kacho-resource-manager\|FolderService\|OrganizationService\|CloudService\|FolderClient" CLAUDE.md docs/specs/00-overview-and-scope.md docs/specs/01-architecture-and-services.md docs/specs/02-data-model-and-conventions.md docs/specs/03-deployment-and-operations.md docs/specs/04-roadmap-and-phasing.md` — пусто (или только в Retired/CHANGELOG sections с явным `historical` ярлыком).
- [ ] `ls obsidian/kacho/resources/ | grep -i "rm-"` — пусто (всё в `_archive/rm/`).
- [ ] `ls obsidian/kacho/edges/ | grep -i "rm"` — пусто.
- [ ] `obsidian/kacho/KAC/KAC-104.md` имеет `Status: done` + summary эпика.
- [ ] `obsidian/kacho/KAC/KAC-110.md` имеет `Status: done` + PR-список.
- [ ] commit-message: `docs(workspace): retire kacho-resource-manager — full removal from architecture (KAC-110, KAC-104 closeout)`.

### 4.5 kacho-resource-manager — GitHub repo archive

| Действие                                                         | Команда                                                                                                                              |
|------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| Закрыть все open issues с шаблонным комментарием                 | `gh issue list -R PRO-Robotech/kacho-resource-manager --state open --json number,title -q '.[].number' \| xargs -I{} gh issue close {} -R PRO-Robotech/kacho-resource-manager -c "Closed as wontfix: service retired in KAC-104/KAC-110 (2026-05-XX). See https://prorobotech.youtrack.cloud/issue/KAC-104"` |
| Закрыть все open PRs                                             | `gh pr list -R PRO-Robotech/kacho-resource-manager --state open --json number -q '.[].number' \| xargs -I{} gh pr close {} -R PRO-Robotech/kacho-resource-manager -c "Closed: service retired in KAC-104/KAC-110"` |
| Финальный commit в `main` ветку с README обновлением             | `README.md` → добавить banner `> ⚠️ **ARCHIVED**: kacho-resource-manager has been retired (KAC-104 / KAC-110, 2026-05-XX). Replaced by [kacho-iam](https://github.com/PRO-Robotech/kacho-iam) Account+Project resources. Архивные данные / vault: [obsidian/kacho/_archive/rm/](https://github.com/PRO-Robotech/kacho-workspace/tree/main/obsidian/kacho/_archive/rm).` |
| Archive repository                                               | `gh repo archive PRO-Robotech/kacho-resource-manager --yes` (либо UI: Settings → General → Archive this repository)                  |
| Verify                                                           | `gh repo view PRO-Robotech/kacho-resource-manager --json isArchived` → `{"isArchived":true}`                                          |
| Delete все `KAC-*` feature branches на remote (post-merge)       | `gh api repos/PRO-Robotech/kacho-resource-manager/branches --paginate -q '.[].name' \| grep "^KAC-" \| xargs -I{} gh api -X DELETE repos/PRO-Robotech/kacho-resource-manager/git/refs/heads/{}` (workspace `CLAUDE.md` §«git-флоу» требование) |

**Acceptance per archive step (no PR — operational)**:
- [ ] `gh repo view PRO-Robotech/kacho-resource-manager --json isArchived` → `true` (GWT-13).
- [ ] README в repo'е содержит archive-banner.
- [ ] Все open issues / PRs закрыты.
- [ ] Local `bootstrap.sh` / `sync-all.sh` (если они есть в workspace) — обновлены (если перечисляют sibling repos explicitly): убрать `kacho-resource-manager` из списка clone-targets. Если не упоминают — ничего.

### 4.6 Verification-only репо (без code changes)

| Репо                  | Verification команда                                                                                                                                     |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `kacho-vpc`           | `grep -rn "kacho-resource-manager\|resourcemanager\|FolderService\|OrganizationService\|CloudService\|FolderClient" project/kacho-vpc/{cmd,internal,migrations}` → пусто |
| `kacho-compute`       | то же; `grep -rn "rmpb\|orgpb"` → пусто                                                                                                                   |
| `kacho-loadbalancer`  | то же                                                                                                                                                    |
| `kacho-ui`            | `grep -rn "resource-manager\|folder\|cloud\|organization" src/` — должны быть только UI-strings типа «Project» (mappable; не RM-related), либо в `_archive/` |
| `kacho-iam`           | sanity: `kacho-iam` не импортирует `rmpb` / `orgpb` (по дизайну — он *заменяет* RM)                                                                       |
| `kacho-corelib`       | sanity: corelib не зависит от RM (по дизайну)                                                                                                            |

**Acceptance verification-only**:
- [ ] Все grep'ы зелёные (пустые); если что-то найдено — это backlog для пред-E5 cleanup-PR
  в соответствующем сервисе (но E1 должен был это всё сделать; если не сделал — block E5).

---

## 5. Pre-conditions checklist (что должно быть готово до старта работ E5)

Каждый пункт ниже — gate; невыполнение блокирует E5-cycle. Verify по списку до открытия первого PR.

| # | Pre-condition                                                                                                                                                          | Verification команда                                                                                                                                                              |
|---|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | **E1 (KAC-106) acceptance APPROVED + E1 code merged во все 4 затронутых репо** — **двойной gate** (I10 fix: APPROVED-документ ≠ merged-код)                            | (a) `obsidian/kacho/specs/sub-phase-2.0-iam-E1-*.md` Status: `APPROVED`; (b) `for r in kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway; do gh pr list -R PRO-Robotech/$r --state merged --search "KAC-106"; done` — все 4 non-empty |
| 2 | **E4 (KAC-109) acceptance APPROVED + E4 code merged**, UI больше не имеет Org/Cloud/Folder pages — двойной gate                                                        | (a) `obsidian/kacho/specs/sub-phase-2.0-iam-E4-*.md` Status: `APPROVED`; (b) `gh pr list -R PRO-Robotech/kacho-ui --state merged --search "KAC-109"` non-empty; manual smoke: `/organizations`, `/clouds`, `/folders` URLs → 404 либо редирект на IAM pages |
| 3 | **grep-clean** — peer-сервисы не зовут RM                                                                                                                              | `grep -rln "kacho-resource-manager\|FolderClient\|FolderService\|OrganizationService\|CloudService\|rmpb\|orgpb" project/kacho-{vpc,compute,loadbalancer,ui}/` → пусто           |
| 4 | **RM-traffic-counter = 0**: kacho-resource-manager не получает входящих gRPC > 1 час на dev стенде                                                                     | `kubectl logs -n kacho deploy/kacho-resource-manager --since=1h \| grep -c "rpc /yandex" ` → `0` (или соответствующий metric)                                                    |
| 5 | **Backup БД** (если в staging / prod есть данные)                                                                                                                       | manual: `kubectl exec pg-resource-manager-0 -- pg_dump ...` **+ `kubectl cp ... ./rm-backup-*.sql` НАРУЖУ pod'а** (B4 fix); в dev — пропускается                                  |
| 6 | **kacho-iam.AccountService / ProjectService — production-ready**: имеет default Account + default Project (`acc_default`, `prj_default`), reachable от api-gateway      | `curl https://api.kacho.local/iam/v1/accounts` → `200` + JSON с `acc_default`; `curl /iam/v1/projects?accountId=acc_default` → `200` + JSON с `prj_default`                       |
| 7 | **Open questions §10 resolved** (только Q-2 остаётся в v2 — backup-flag для dev)                                                                                       | manual checklist в bottom of this document; перед старт E5 — единственный OQ (Q-2) должен быть answered либо явно scoped-out                                                       |
| 8 | **`kacho-resource-manager` локально в `project/` ещё существует** (для последнего archive-flow и runbook-testing)                                                       | `ls project/kacho-resource-manager` non-empty; нельзя ускоренно удалить локальный клон до завершения archive-step                                                                  |
| 9 | **grep-clean для `kacho.cloud.access.*` legacy** (D-5) — никто не импортирует legacy access-package                                                                     | `grep -rln "kacho.cloud.access\|cloud/access/v1" project/kacho-{vpc,compute,loadbalancer,iam,api-gateway,ui}/` → пусто; если что-то найдено — cleanup-PR ДО E5 PR-1                |

---

## 6. GWT — сценарии (минимум 15, компактные)

### 6.0 Convention для GWT в этом документе

Все сценарии — **shell-based smoke / verification**, не traditional API GWT (т.к. цель эпика —
*удаление*, а не *новое поведение*). Каждый сценарий имеет:
- **ID**: `E5.GWT-NN` (где NN = 01..15+).
- **Given** — pre-condition / окружение.
- **When** — конкретная команда / действие.
- **Then** — ожидаемый результат (exit-code, output, отсутствие резерва).

### Сценарий E5.GWT-01 — Pre-condition: E1 merged во всех 4 репо

**Given** запущен `gh` CLI с access к `PRO-Robotech/kacho-*`.

**When** оператор запускает:
```bash
for repo in kacho-vpc kacho-compute kacho-loadbalancer kacho-api-gateway; do
  gh pr list -R PRO-Robotech/$repo --state merged --search "KAC-106" --json number,title \
    | jq '.[0].number'
done
```

**Then** каждая команда возвращает **non-null** PR number (1+ merged PR с KAC-106 в каждом из 4 репо).
**And** если хоть один — `null`, E5 блокируется до завершения E1.

### Сценарий E5.GWT-02 — Pre-condition: E4 merged + UI без Org/Cloud/Folder pages

**Given** dev-стенд работает с E1+E4 changes; UI развёрнут на `http://ui.kacho.local`.

**When** оператор открывает в браузере:
- `http://ui.kacho.local/organizations`
- `http://ui.kacho.local/clouds`
- `http://ui.kacho.local/folders`

**Then** каждый URL возвращает либо `404 Not Found` page, либо redirect на `/iam/accounts` / `/iam/projects`.
**And** **никакого** old Organization/Cloud/Folder UI rendering (с list/CRUD кнопками).

### Сценарий E5.GWT-03 — Pre-condition: grep-clean на peer-сервисах

**Given** локально склонированы все `project/kacho-*` репо в актуальном `main`.

**When** оператор запускает:
```bash
grep -rln "kacho-resource-manager\|resourcemanager\|FolderClient\|FolderService\|OrganizationService\|CloudService\|rmpb\|orgpb" \
  project/kacho-vpc/{cmd,internal,migrations} \
  project/kacho-compute/{cmd,internal,migrations} \
  project/kacho-loadbalancer/{cmd,internal,migrations} \
  project/kacho-ui/src
```

**Then** output **пустой** (exit-code 1 от `grep` = nothing matched).
**And** если что-то найдено — это блокер; нужен дополнительный cleanup-PR в найденный сервис ДО открытия E5-PR'ов.

### Сценарий E5.GWT-04 — Helm chart: removal RM-зависимостей passes `helm template`

**Given** PR в `kacho-deploy` с удалёнными `resource-manager` и `pg-resource-manager` deps из `Chart.yaml` + `values.dev.yaml`.

**When** CI запускает:
```bash
cd helm/umbrella
helm dependency update
helm template kacho . -f values.dev.yaml > /tmp/manifest.yaml
```

**Then** оба шага exit-code 0 (no errors).
**And** `grep -c "kind: Deployment.*kacho-resource-manager\|kind: StatefulSet.*pg-resource-manager" /tmp/manifest.yaml` → `0`.
**And** `grep -c "kind: Deployment.*kacho-iam" /tmp/manifest.yaml` → `>= 1` (sanity: IAM ещё там).

### Сценарий E5.GWT-05 — `make dev-up` стенд без RM pod

**Given** локальный kind-cluster (или эквивалент); `make dev-down -v` выполнен; PR'ы E5 merged в kacho-deploy.

**When** оператор запускает:
```bash
cd project/kacho-deploy
make dev-up
sleep 60  # wait for pods to settle
kubectl get pods -n kacho -o name | sort
```

**Then** output **не содержит** `pod/kacho-resource-manager-*` и `pod/pg-resource-manager-*`.
**And** output **содержит** `pod/kacho-iam-*`, `pod/kacho-vpc-*`, `pod/kacho-compute-*`, `pod/kacho-loadbalancer-*`, `pod/kacho-api-gateway-*`.

### Сценарий E5.GWT-06 — Никаких CrashLoop / failed init-containers

**Given** стенд поднят (см. GWT-05).

**When** оператор запускает:
```bash
kubectl get pods -n kacho -o json | jq -r '.items[] | select(.status.phase != "Running" or any(.status.containerStatuses[]?; .ready == false)) | .metadata.name'
```

**Then** output **пустой** (все pods Running + ready).
**And** dependent: вся остальная функциональность (IAM CRUD, VPC CRUD, Compute CRUD) — operational (smoke verifyable далее).

### Сценарий E5.GWT-07 — kacho-proto: `buf lint` зелёный после удаления

**Given** PR в `kacho-proto` с удалёнными `proto/kacho/cloud/resourcemanager/` и `proto/kacho/cloud/organizationmanager/` directories + `gen/go/` cleanup + временный `buf.yaml` exception (D-2).

**When** CI запускает:
```bash
cd project/kacho-proto
buf lint
echo $?
```

**Then** exit-code `0`.
**And** `buf breaking --against '.git#branch=main'` exit-code = 0 (passes благодаря exception в `buf.yaml`).

### Сценарий E5.GWT-08 — kacho-proto: `gen/go/` cleanup verified

**Given** PR из GWT-07 merged.

**When** оператор запускает:
```bash
ls project/kacho-proto/gen/go/kacho/cloud/ | sort
```

**Then** output **не содержит** `resourcemanager` и `organizationmanager` директорий.
**And** output **содержит**: `access`, `api`, `common`, `compute`, `iam`, `loadbalancer`, `operation`, `reference`, `vpc` (никаких deletions помимо двух RM-related).

### Сценарий E5.GWT-09 — api-gateway: REST `/resource-manager/v1/*` → 404

**Given** стенд поднят (GWT-05); api-gateway PR из E5 merged.

**When** оператор запускает:
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://api.kacho.local/resource-manager/v1/folders
curl -s -o /dev/null -w "%{http_code}\n" http://api.kacho.local/resource-manager/v1/folders/f-1
curl -s -o /dev/null -w "%{http_code}\n" http://api.kacho.local/resource-manager/v1/clouds
curl -s -o /dev/null -w "%{http_code}\n" http://api.kacho.local/organization-manager/v1/organizations
```

**Then** каждый запрос возвращает `404` (NOT 410 — см. Decision D-1 — `Gone` отвергнут).
**And** response-body — стандартное 404 (что отдаёт gin / chi / grpc-gateway default mux); не custom JSON.

### Сценарий E5.GWT-10 — api-gateway: mux_test.go regression — 404 на устаревших путях

**Given** PR в `kacho-api-gateway` с новыми test-cases в `internal/restmux/mux_test.go` (см. §4.2).

**When** CI запускает:
```bash
cd project/kacho-api-gateway
go test ./internal/restmux/... -v -run TestRemovedResourceManagerRoutes
```

**Then** test passes (exit-code 0).
**And** test-output показывает: `PASS: TestRemovedResourceManagerRoutes/resource_manager_folders_returns_404`,
`PASS: .../organization_manager_organizations_returns_404`, etc.

### Сценарий E5.GWT-11 — БД drop: `kacho_resource_manager` больше не существует после `make dev-down -v`

**Given** стенд поднят (GWT-05); `pg-resource-manager` НЕ был развёрнут (per E5 helm changes).

**When** оператор запускает:
```bash
cd project/kacho-deploy
make dev-down -v   # -v удаляет PVC
sleep 5
kubectl get pvc -n kacho | grep -c "pg-resource-manager"
```

**Then** output `0`.
**And** в новом `make dev-up` — RM не создаётся (GWT-05 повторяемо).

### Сценарий E5.GWT-12 — БД drop runbook (**manual prod-runbook validation, не CI**) — B3 fix

**Scope clarification** (B3 fix): этот сценарий — **manual operational validation**, проводится
**отдельно** от CI E5 merge cycle, **только когда** prod-flavored инсталляция Kachō появится.
В CI E5 этот сценарий **скипается** (нет prod stenда). Существует ЛИБО как manual runbook-test
на pre-prod stenде, ЛИБО как future-acceptance для первой prod-инсталляции — НЕ блокер E5 merge.

**Given (prod-only)** admin поднимает локальный helm-стенд **без E5 PR** (через `git checkout
main^` ИЛИ separate branch) — состояние «до E5», где `pg-resource-manager` ещё существует;
runbook `docs/operations/e5-rm-uninstall.md` следует пошагово.

**When** оператор выполняет шаги runbook:
```bash
# Step 1a — backup dump внутри pod'а
kubectl exec -n kacho pg-resource-manager-0 -- pg_dump -U kacho_resource_manager \
  kacho_resource_manager > /tmp/rm-backup.sql

# Step 1b — вытащить backup НАРУЖУ pod'а (B4 fix)
kubectl cp pg-resource-manager-0:/tmp/rm-backup.sql ./rm-backup-$(date +%F).sql -n kacho
ls -lh ./rm-backup-$(date +%F).sql

# Step 2 — drop database
kubectl exec -n kacho pg-resource-manager-0 -- psql -U postgres -c \
  "DROP DATABASE IF EXISTS kacho_resource_manager;"

# Step 3 — verify
kubectl exec -n kacho pg-resource-manager-0 -- psql -U postgres -lqt | cut -d \| -f 1 | grep -c kacho_resource_manager
```

**Then** Step 1a — exit-code 0; backup-файл non-empty внутри pod'а.
**And** Step 1b — exit-code 0; **локальный** файл `./rm-backup-YYYY-MM-DD.sql` non-empty (B4 fix —
backup persistent после pod-destruction).
**And** Step 2 — exit-code 0; output `DROP DATABASE`.
**And** Step 3 — output `0` (БД больше нет).
**And** никаких orphan-connections (`SELECT count(*) FROM pg_stat_activity WHERE datname = 'kacho_resource_manager'` → `0`; уже не существует — query тоже зелёный с `0`).

**Status в DoD**: GWT-12 — **не блокирует** E5 DoD; помечается как «future / on-prod-install»
verification; CI E5 merge не требует прохождения GWT-12.

### Сценарий E5.GWT-13 — GitHub repo `kacho-resource-manager` archived

**Given** оператор имеет admin-access к `PRO-Robotech` org.

**When** оператор запускает:
```bash
gh repo archive PRO-Robotech/kacho-resource-manager --yes
gh repo view PRO-Robotech/kacho-resource-manager --json isArchived
```

**Then** `archive` команда exit-code 0.
**And** `view --json isArchived` output `{"isArchived":true}`.
**And** попытка `gh pr create` против archived repo возвращает error: `Repository is archived`.

### Сценарий E5.GWT-14 — Workspace CLAUDE.md: RM-row удалена (**strict 0 mentions**, I8 fix)

**Given** PR в `kacho-workspace` с CLAUDE.md changes.

**When** оператор запускает:
```bash
grep -c "kacho-resource-manager" kacho-workspace/CLAUDE.md
```

**Then** output **строго `0`** (I8 fix — никаких `<=2` исключений; D-4 «full removal» означает
буквально 0 mentions в живом CLAUDE.md; историческая память — только в vault `_archive/rm/`,
не в CLAUDE.md).
**And** `grep -n "Organization / Cloud / Folder" kacho-workspace/CLAUDE.md` — пусто (карта владельцев чистая).
**And** `grep -c "FolderClient\|FolderService\|OrganizationService\|CloudService\|rmpb\|orgpb" kacho-workspace/CLAUDE.md` → `0` (никаких RM-specific терминов в живом регламенте).

### Сценарий E5.GWT-15 — Vault: edges/* clean от RM

**Given** PR в `kacho-workspace` с vault changes (move в `_archive/rm/`).

**When** оператор запускает:
```bash
ls obsidian/kacho/edges/ | grep -i "rm\|resource-manager" || echo "CLEAN"
ls obsidian/kacho/resources/ | grep -i "^rm-" || echo "CLEAN"
ls obsidian/kacho/rpc/ | grep -i "^rm-" || echo "CLEAN"
ls obsidian/kacho/packages/ | grep -i "^rm-" || echo "CLEAN"
ls obsidian/kacho/_archive/rm/ 2>/dev/null | wc -l
```

**Then** первые 4 команды выводят `CLEAN` (нет matches).
**And** `_archive/rm/` существует и содержит non-zero количество файлов (всё перенесено).

### Сценарий E5.GWT-16 — End-to-end smoke: IAM Account/Project CRUD работает без RM

**Given** стенд поднят без RM (GWT-05); `acc_default` / `prj_default` существуют (GWT-precondition #6).

**When** оператор запускает full E2E newman suite:
```bash
cd project/kacho-deploy
make e2e-test
```

**Then** все newman-cases — зелёные (exit-code 0).
**And** specifically: `iam_account_crud`, `iam_project_crud`, `vpc_network_crud_uses_projectid`,
`compute_instance_crud_uses_projectid` — все pass.
**And** **никаких** newman cases на `/resource-manager/v1/folders` / `/clouds` / `/organizations`
(если есть — они удалены в E1 / E5 в рамках newman cleanup).

### Сценарий E5.GWT-17 — Post-merge: PACKAGE_NO_DELETE exception removed (B2 fix, D-6)

**Given** основной kacho-proto PR-1 (с удалением 3 пакетов) merged в `main`; follow-up cleanup PR
открыт (либо в рамках того же closeout, либо отдельный PR).

**When** оператор запускает:
```bash
cd project/kacho-proto
grep -c "PACKAGE_NO_DELETE" buf.yaml
```

**Then** output **`0`** (exception removed из `buf.yaml` `main`-ветки).
**And** `buf breaking --against '.git#branch=main'` зелёный без exception (нет deleted packages
в diff после cleanup-PR; `main` уже в target state).
**And** альтернативно (если выбран CI env-flag вариант per D-6): `buf.yaml` `main`-ветки **никогда**
не содержал exception — `grep -c "PACKAGE_NO_DELETE"` всегда `0`, и `.github/workflows/*.yml`
не содержит residual `BUF_BREAKING_IGNORE_PACKAGES` env-var.

**Status в DoD**: GWT-17 — **обязательный** компонент DoD-9 (см. §7); KAC-110 не закрывается
в YouTrack до прохождения GWT-17.

---

## 7. Definition of Done

Эпик E5 закрыт когда **все** 9 пунктов ниже зелёные.

### Functional DoD

- [ ] **DoD-1** — `make dev-down -v && make dev-up` поднимает стенд **без** `kacho-resource-manager-*` и `pg-resource-manager-*` pods (GWT-05, GWT-06).
- [ ] **DoD-2** — `gh repo view PRO-Robotech/kacho-resource-manager --json isArchived` → `true` (GWT-13).
- [ ] **DoD-3** — proto-домены `resourcemanager`, `organizationmanager` **и `access`** удалены из kacho-proto (включая `gen/go/`); `buf lint` зелёный; downstream сервисы build OK (GWT-07, GWT-08; B1 / D-5 fix — access добавлен).
- [ ] **DoD-4** — `kacho-api-gateway` не маршрутизирует RM-endpoints; regression test проверяет 404 на `/resource-manager/v1/*`, `/organization-manager/v1/*` (GWT-09, GWT-10).
- [ ] **DoD-5** — БД `kacho_resource_manager` дропнута; PVC `pg-resource-manager` удалён; нет orphan connections (GWT-11; GWT-12 — manual prod-runbook validation, не блокер CI per B3 fix).

### Documentation / artefacts DoD

- [ ] **DoD-6** — workspace `CLAUDE.md` обновлён: RM удалён из таблицы сервисов, edges очищены; **`grep -c "kacho-resource-manager" CLAUDE.md` строго `0`** (GWT-14, I8 fix).
- [ ] **DoD-7** — vault обновлён: `rm-*` entries в `_archive/rm/`; README / INDEX / architecture без RM; `KAC/KAC-110.md` + `KAC/KAC-104.md` финализированы (GWT-15).
- [ ] **DoD-8** — grep clean в peer-сервисах: ни одного упоминания `FolderClient` / `FolderService` / `OrganizationService` / `CloudService` / `rmpb` / `orgpb` в `project/kacho-{vpc,compute,loadbalancer,ui}/` (GWT-03).
- [ ] **DoD-9** — **Post-merge cleanup**: `PACKAGE_NO_DELETE` exception removed из `kacho-proto/buf.yaml` follow-up PR'ом (D-6); `grep -c "PACKAGE_NO_DELETE" buf.yaml` → `0` ИЛИ exception никогда не попал в `main`-ветку (вариант с CI env-flag, D-6) (GWT-17, B2 fix).

### Process DoD (workspace `CLAUDE.md` §«Документооборот»)

- [ ] Все 4 затронутых репо имеют merged PR с `Closes KAC-110` в body.
- [ ] Все feature-ветки `KAC-110` в каждом из 4 репо удалены (push origin --delete + локально).
- [ ] KAC-110 → `Done` в YouTrack; в comment — ссылки на 4 PR.
- [ ] KAC-104 (parent epic) → `Done` в YouTrack; в comment — **closeout summary** с ссылками на 6 sub-эпиков (KAC-105…KAC-110) (D-7, I6 fix).
- [ ] **Per-эпик** CHANGELOG entries в `docs/specs/04-roadmap-and-phasing.md`: отдельная строка на каждый E1…E5 (5 entries) **плюс** заключительная «KAC-104 — Phase 2.0 (IAM) — fully closed YYYY-MM-DD» (D-7).

---

## 8. Cross-repo PR-chain (порядок merge)

Строгий топологический порядок (нарушение блокирует следующий шаг). **Reorder в v2 (I9 fix)**:
archive-step перенесён **в конец**, после workspace-PR, потому что README banner в архивном репо
ссылается на `obsidian/kacho/_archive/rm/` URL в workspace — этот URL появляется только после
merge'а workspace-PR.

```
1. kacho-proto             — remove resourcemanager + organizationmanager + access packages + gen/go/
                             (PR-1; merges first, isolated, all downstream re-gen happens here;
                             D-5 add: access cleanup in same PR)

2. kacho-api-gateway       — remove rmpb/orgpb imports + REST registrations + mux_test regression
                             (PR-2; needs PR-1 merged first to drop the gen/go/ imports without
                             stale references; alternatively can land same-time with replace../
                             pointing to PR-1 branch — but easier: serialize after PR-1)

3. kacho-deploy            — remove resource-manager + pg-resource-manager from umbrella Chart.yaml
                             and values.dev.yaml; Makefile cleanup; e2e cleanup; runbook added
                             (PR-3; independent of PR-1/PR-2 — helm chart doesn't import Go code,
                             so can land in parallel, but logically AFTER PR-2 to avoid "helm
                             deletes pod, but api-gateway still tries to dial it" intermediate state)

4. kacho-workspace         — docs/specs updates + CLAUDE.md cleanup + vault _archive/rm/ + KAC-110.md
                             + KAC-104.md finalize + bootstrap.sh/sync-all.sh обновлены (больше не
                             клонируют RM; локальный клон gitignored) per I5 fix
                             (PR-4 в v2; was PR-5 in v1 — moved up; references merged PRs from
                             steps 1-3; **обязательно мёрджится ДО step 5**, поскольку README banner
                             в archive-repo ссылается на `obsidian/kacho/_archive/rm/` URL, который
                             появляется только после merge'а этого PR)

5. kacho-resource-manager  — final README banner (с **рабочим** URL на `_archive/rm/` в merged
                             workspace) + archive via gh CLI / Settings UI
                             (operational step; happens AFTER PR-1/2/3/4 merged и dev-up verified;
                             I9 reorder fix — без merged workspace-PR README-banner-URL был бы битый)

6. **Follow-up cleanup PR** (D-6 / DoD-9) — kacho-proto: убрать `PACKAGE_NO_DELETE` exception
                             из `buf.yaml` (если вариант с временным exception — см. D-6); либо
                             верифицировать что CI env-flag вариант не оставил residual в workflow
                             yaml. Merge сразу после step 5.
```

**Per workspace `CLAUDE.md` §«Кросс-репо зависимости» — runtime edges**: после E5 удалены edges:
- `kacho-vpc → kacho-resource-manager` (уже удалён в E1)
- `kacho-compute → kacho-resource-manager` (уже удалён в E1)
- `kacho-loadbalancer → kacho-resource-manager` (уже удалён в E1)
- `kacho-api-gateway → kacho-resource-manager` (удаляется ЗДЕСЬ в E5 PR-2)
- `kacho-ui → kacho-resource-manager` (уже удалён в E4 — UI больше не fetch'ит)

После E5 — РОВНО ноль runtime-edges к RM; репо архивирован; БД отсутствует.

---

## 9. Risks

| # | Risk                                                                                       | Mitigation                                                                                                                                                |
|---|--------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| R-1 | **Latent FolderClient в peer-сервисе** обнаруживается после E5 merge → стенд падает   | Pre-condition #3 (GWT-03) — grep-clean на peer-сервисах ДО E5; если grep не пустой → блок E5 до cleanup-PR в найденный сервис                              |
| R-2 | **`buf breaking` exception утечёт в `main` permanently** → теряем breaking-detection для будущих изменений | follow-up PR в `kacho-proto` сразу после E5 merge: убрать `PACKAGE_NO_DELETE` exception из `buf.yaml`; добавить в KAC-110 acceptance чек-лист       |
| R-3 | **БД не дропнута в prod-инсталляции** (если она появится в будущем) — orphan PVC, занимает storage | Runbook (`docs/operations/e5-rm-uninstall.md`) явно требует Step 2 (`DROP DATABASE`) ДО `helm uninstall`; nightly retention-job (если есть) уничтожает orphan PVC через 30 дней |
| R-4 | **GitHub repo не архивирован** — кто-то открывает PR в архивный sibling                    | GWT-13 — verification `isArchived: true`; README banner с warning; недели спустя — `gh repo view` re-check                                                |
| R-5 | **Stale CLAUDE.md memory у запущенных Claude Code sessions** — агенты помнят RM             | После CLAUDE.md merge — оператор перезапускает свои сессии (CLAUDE.md загружается at boot); workspace `CLAUDE.md` явно говорит «memory обнуляется» в новой сессии |
| R-6 | **Old documentation links** в внешних чатах / Slack / Notion ссылаются на `obsidian/kacho/resources/rm-folder.md` — теперь 404 | `_archive/rm/` сохраняет файлы с тем же именем (`obsidian/kacho/_archive/rm/resources/rm-folder.md`); ссылки требуют ручной правки, но контент доступен |
| R-7 | **Hidden imports**: какой-то integration-тест в `tests/newman/` ещё использует `/resource-manager/v1/folders` | Pre-condition #3 включает grep на `tests/newman/`; newman cases — под E5 cleanup в kacho-deploy PR-3                                                       |

---

## 10. Open Questions (resolve до approve этого acceptance reviewer'ом)

Ниже — открытые вопросы, требующие ответа ДО APPROVED-статуса. После resolve — answer переносится
в Decision Log §2 (новые D-N) или в §9 Risks как accepted mitigation.

**v2 status**: 4 из 6 v1 OQ резолвлены — перенесены в Decision Log (D-5..D-8) или объединены
(Q-3+Q-6); 1 OQ остался (Q-2).

| # | Question | Default / proposed answer | Resolution |
|---|----------|---------------------------|------------|
| ~~Q-1~~ | ~~`kacho.cloud.access.*` cleanup~~ | **RESOLVED v2** → перенесено в **D-5** (cleanup в E5 PR-1) | **RESOLVED v2** (B1 fix) |
| Q-2 | **Backup БД `kacho_resource_manager` на dev — нужен ли?** | **Нет** (dev — ephemeral; PVC уничтожается `make dev-down -v`); `pg_dump`-команда + `kubectl cp` в runbook — только для prod-flavored инсталляции (см. D-3, B4 fix) | requires reviewer confirm |
| ~~Q-3~~ | ~~Локальный `project/kacho-resource-manager/` после archive~~ | **RESOLVED v2** → объединено с Q-6 в **I5**: `bootstrap.sh` обновлён в E5 PR-4 (workspace) — больше не clone'ит RM; локальный клон gitignored, остаётся у разработчиков as-is (workspace не enforce'ит local state). | **RESOLVED v2** (I5 fix) |
| ~~Q-4~~ | ~~CHANGELOG entry combine vs split~~ | **RESOLVED v2** → перенесено в **D-7**: отдельная CHANGELOG entry per E1…E5 (5 entries) + closeout summary в KAC-104 epic comment в YouTrack | **RESOLVED v2** (I6 fix) |
| ~~Q-5~~ | ~~release/tag pre-archive~~ | **RESOLVED v2** → перенесено в **D-8**: нет release/tag pre-archive (no stable release pipeline pre-1.0) | **RESOLVED v2** (I7 fix) |
| ~~Q-6~~ | ~~Кто удаляет локальный clone RM~~ | **RESOLVED v2** → объединено с Q-3 в **I5** (см. выше) | **RESOLVED v2** (I5 fix) |

---

## 11. Changelog

| Version | Date       | Author                | Changes                                                                                                                                                  |
|---------|------------|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| DRAFT v1 | 2026-05-17 | `acceptance-author`   | Expanded from stub (§stub was 221 lines); added Decision Log (4 decisions), target architecture (before/after), per-repo decomposition (5 repos), 16 GWT scenarios, DoD checklist (8 items), cross-repo PR-chain, risks (7), open questions (6); status DRAFT v1 — awaiting acceptance-reviewer |
| DRAFT v2 | 2026-05-17 | `acceptance-author`   | **Round 1 reviewer fixes**: 4 blockers + 6 important. See `## Changelog v2` section below.                                                                |

---

## Changelog v2

Round 1 reviewer вернул 4 blocker (B1-B4) + 6 important (I5-I10); все resolved в v2.

### Blockers (4)

- **B1 — OQ-1 `kacho.cloud.access.*` legacy proto cleanup**: добавлен **Decision D-5**
  «Удалить proto `kacho.cloud.access.*` в E5 в том же kacho-proto PR-1 + `gen/go/kacho/cloud/access/`».
  OQ-1 удалён (RESOLVED). §0 преамбула обновлена — `access` перенесён из «E5 НЕ включает» в
  таблицу «Слой / артефакт → было / становится». §4.1 (kacho-proto decomposition) — добавлены
  `proto/kacho/cloud/access/` + `gen/go/kacho/cloud/access/` rows. §5 pre-conditions — добавлен
  pre-condition #9 (grep-clean на `kacho.cloud.access` в всех сервисах). Acceptance per
  kacho-proto PR — обновлён commit-message для трёх пакетов.

- **B2 — `buf` PACKAGE_NO_DELETE exception leak в `main`**: добавлен **DoD-9** «Post-merge
  cleanup: PACKAGE_NO_DELETE exception removed from `buf.yaml` (follow-up PR) ИЛИ exception
  никогда не попал в `main` (CI env-flag вариант)». Добавлен **сценарий E5.GWT-17** «Post-merge:
  PACKAGE_NO_DELETE exception removed». Добавлен **Decision D-6** «Post-merge cleanup
  PACKAGE_NO_DELETE exception» с описанием двух вариантов:
  (а) временный exception в `buf.yaml` + follow-up cleanup PR (fallback);
  (б) CI env-flag в workflow yaml (`BUF_BREAKING_IGNORE_PACKAGES=...` per-PR) — **предпочтительнее**,
  exception не попадает в `main`. §8 cross-repo PR-chain — добавлен step 6 «follow-up cleanup PR».
  R-2 risk — обновлён ссылкой на D-6.

- **B3 — GWT-12 prod-flavor**: переформулирован как **manual prod-runbook validation, не CI E5
  blocker**. Given: «(prod-only) admin поднимает локальный helm-стенд **без E5 PR** (через
  `git checkout main^`), выполняет runbook». Явно scope-out из CI — GWT-12 не блокирует CI E5
  merge; верифицируется отдельно когда prod-инсталляция появится. DoD-5 обновлён: GWT-11 — CI
  blocker; GWT-12 — manual prod-style verification.

- **B4 — D-3 backup-path не покрывал извлечение наружу**: в runbook D-3 и runbook
  `docs/operations/e5-rm-uninstall.md` (§4.3) добавлен явный шаг
  `kubectl cp pg-resource-manager-0:/tmp/rm-backup.sql ./rm-backup-$(date +%F).sql -n kacho`
  **после** `pg_dump` — backup в /tmp/ внутри pod'а уничтожается с pod'ом при helm uninstall.
  Добавлено указание «Backup retention policy — out of scope pre-1.0, prod policy defer» (B4 ack).
  GWT-12 (manual) — обновлён с новым step 1b verify. Pre-condition #5 в §5 — добавлено `+ kubectl cp`.

### Important (6)

- **I5** — merge Q-3 + Q-6 в одно решение: **`bootstrap.sh` обновлён в E5 PR-4 (workspace) —
  больше не клонирует RM; локальный клон gitignored, остаётся у разработчиков as-is**. §4.4
  (workspace decomposition) — добавлены rows для `bootstrap.sh` + `sync-all.sh` (если есть).
  Q-3 и Q-6 удалены из §10 (объединены, RESOLVED).

- **I6** — Q-4 CHANGELOG strategy: **отдельная CHANGELOG entry per E1…E5 (5 entries) +
  closeout summary в KAC-104 epic comment в YouTrack**. Перенесено в **Decision D-7**. Q-4
  удалён из §10 (RESOLVED). Process DoD §7 обновлён — упоминание per-эпик entries + closeout.

- **I7** — Q-5 release/tag pre-archive: **нет release/tag pre-archive (нет stable release
  pipeline pre-1.0)**. Перенесено в **Decision D-8**. Q-5 удалён из §10 (RESOLVED).

- **I8** — D-4 «full removal» vs GWT-14 `<=2 mentions`: исправлено на **строго 0 mentions** в
  CLAUDE.md. GWT-14 обновлён: `grep -c "kacho-resource-manager" CLAUDE.md` → строго `0`. D-4
  «Следствия» обновлены — добавлена строка «GWT-14 strict 0». DoD-6 обновлён аналогично.

- **I9** — §8 reorder: **archive (step 4 v1) перенесён в step 5 v2, после workspace PR (step 4
  v2)**. Причина: README banner в archive-repo ссылается на `obsidian/kacho/_archive/rm/` URL в
  workspace — этот URL появляется только после merge'а workspace-PR. §8 cross-repo PR-chain
  полностью переписан под v2-порядок (1: proto, 2: api-gateway, 3: deploy, 4: workspace,
  5: archive RM, 6: follow-up cleanup). §12 «После approve» — implementation order обновлён.

- **I10** — Pre-conditions §5 #1 и #2: **двойной gate «E1 acceptance APPROVED + E1 code merged
  во всех 4 репо»** (то же для E4). Verification обновлена: (a) APPROVED-статус в
  acceptance-документе; (b) `gh pr list --state merged --search KAC-106` non-empty для каждого
  из 4 затронутых репо.

### Open Questions — v2 status

- Q-1, Q-3, Q-4, Q-5, Q-6 — RESOLVED (см. выше; перенесены в D-5..D-8 или объединены в I5).
- Q-2 — остаётся (единственный open question v2): backup БД на dev — нужен ли? Default answer:
  **нет** (dev — ephemeral; `pg_dump`+`kubectl cp` — только для prod runbook). Requires reviewer
  confirm.

### Файлы acceptance-документа — diff scope v1 → v2

- §«Status» — `DRAFT v1` → `DRAFT v2`.
- §0 преамбула — `access` переcъехал в таблицу артефактов; «E5 НЕ включает» обновлён.
- §2 Decision Log — добавлены **D-5, D-6, D-7, D-8** (было D-1..D-4).
- §4.1 kacho-proto — `access` rows + acceptance updated.
- §4.3 kacho-deploy — runbook step `kubectl cp` явно прописан.
- §4.4 kacho-workspace — `bootstrap.sh`/`sync-all.sh` rows.
- §5 Pre-conditions — #1 + #2 двойной gate; #9 access grep-clean.
- §6 GWT — GWT-12 переформулирован (manual prod-runbook); GWT-14 strict 0; **GWT-17 новый**.
- §7 DoD — **DoD-9 новый**; DoD-3 обновлён (access); DoD-5 split (GWT-11 CI / GWT-12 manual);
  DoD-6 strict 0; Process DoD — per-эпик CHANGELOG.
- §8 Cross-repo PR-chain — полный reorder; добавлен step 6 follow-up.
- §10 Open Questions — 5 из 6 RESOLVED.
- §11 Changelog — добавлена строка DRAFT v2.
- §12 — implementation order обновлён под v2-порядок.

---

## 12. После approve этого документа

1. `superpowers:writing-plans` — превратить decomposition (§4) в task-list для каждого затронутого репо (5 PR-ов суммарно).
2. `acceptance-reviewer` — APPROVED required перед стартом кода (gate per запрет #1).
3. **Параллельно**: создать KAC-110-subtasks по одному на каждый репо (4 backend repos + 1 workspace).
4. **Implementation order** — строгий per §8 (v2 reorder, I9 fix): kacho-proto → kacho-api-gateway → kacho-deploy → **kacho-workspace** → kacho-resource-manager archive → follow-up PACKAGE_NO_DELETE cleanup (D-6).
5. **После всех 5 PR merged** + archive: KAC-110 → `Done` в YouTrack с ссылками на все PR в comment.
6. **После KAC-110 → Done**: KAC-104 parent epic → `Done` с финальной сводкой эпика в comment (D-7 — closeout summary + per-эпик CHANGELOG entries).
7. **Cleanup-PR** (post-E5, DoD-9): убрать `PACKAGE_NO_DELETE` exception из `kacho-proto/buf.yaml` (см. R-2 / D-6); GWT-17 verification зелёный.

После шага 6 — sub-phase 2.0 (Kachō IAM) полностью закрыта; платформа Kachō — на IAM-модели
Account/Project, `kacho-resource-manager` retired окончательно.
