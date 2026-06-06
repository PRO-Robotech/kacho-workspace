# Kachō — Workspace CLAUDE.md

Этот файл загружается Claude Code при работе из самого `kacho-workspace/`
и **из любой подпапки `kacho-workspace/project/<repo>/`** благодаря
parent-walkup discovery (см. §«Структура репозиториев»).

## Что это за проект

Kachō — облачная управляющая платформа: домены Organization/Cloud/Folder, VPC (Network/Subnet/SecurityGroup/RouteTable/Address/Gateway/PrivateEndpoint), Compute (Instance/Disk/Image/…). **Все сервисы — control-plane only.**

> **YC-стилистика — да, структура методов 1-в-1 — нет.** Раньше цель была — *побайтовое*
> соответствие Yandex Cloud API (структура RPC, состав полей, текст ошибок до запятой, regex'ы,
> behavioural quirks). Сейчас правило мягче:
>
> - **Стилистика остаётся YC-подобной** — это база, выработанная годами и удобная пользователю
>   YC-CLI / тех, кто привык к YC. Сохраняем:
>     - именование (camelCase JSON, `<resource>Id`/`folderId`/`labels`/`createdAt`, async
>       `Operation` envelope на каждой мутации, REST-paths `/<service>/v1/<resource>` и
>       suffix-actions через `:verb`),
>     - error-format (`{code, message, details:[]}` + google.rpc.Status, gRPC-коды
>       INVALID_ARGUMENT / NOT_FOUND / FAILED_PRECONDITION / ALREADY_EXISTS),
>     - тон сообщений (`"<Resource> %s not found"`, `"<field> is immutable after <Resource>.Create"`,
>       `"Illegal argument <thing>"`, `"network is not empty"` и т.п. — YC-style формулировки),
>     - timestamp truncate до секунд, `update_mask` discipline (известные поля → mutate,
>       незнакомые → InvalidArgument, immutable → InvalidArgument, отсутствие mask → full-PATCH
>       с silent-ignore immutable).
> - **Структура методов / состав ресурсов — НЕ копируем 1-в-1.** API проектируем в чистой,
>   удобной форме, где можем расходиться с YC по делу:
>     - NetworkInterface как отдельный first-class ресурс AWS-ENI-стиля (в YC NIC встроена в
>       Instance), AddressPool как kacho-only admin-ресурс, и т.п.;
>     - Internal-проекции ресурсов с инфра-полями отдельно от публичных (в YC такого нет);
>     - oneof-семантика и replace-флаги, которые удобнее (KAC-71 AddressPool split v4/v6).
> - **`kacho-yc-shim`** — отдельный поздний слой, если потребуется CLI-compat. Не constraint на
>   нынешний дизайн.
> - **Следствия для агентов и доков**:
>     - где написано «verbatim YC / нельзя расходиться с YC / сломает parity» —
>       читать как «следуй YC по тону и форме сообщений, но *структурное* расхождение —
>       норма, если оно осознанное и задокументировано»;
>     - `vpc-yc-parity-auditor` / `proto-api-reviewer` в части parity-структуры — на паузе;
>     - parity по форме (regex/error-text/timestamp/update_mask) — **остаётся** и
>       проверяется как часть стиля.
> - **Остаётся в силе** (запреты): §«Запреты» #2 («НЕ упоминать `yandex`» — гигиена),
>   Internal-vs-external разделение (#6), flat-resources+Operations контракт,
>   acceptance-workflow (#1).

Полная спека: `kacho-workspace/docs/specs/00-overview-and-scope.md` и далее (раздел про YC-parity
там тоже читать через эту врезку — «стиль остаётся, структура — по делу»).

## Naming convention (обязательно)

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** |
| Технические идентификаторы (ASCII) | `kacho` |
| Proto package | `kacho.cloud.<domain>.v1` |
| Имена репо | `kacho-<part>` (с дефисом) |
| Postgres database / schema | `kacho_<domain>` (с подчёркиванием) |
| Env-переменные | `KACHO_<DOMAIN>_<NAME>` |

## Структура репозиториев (polyrepo)

Workspace — корневой репо. Все sibling-репо клонируются в `./project/`
скриптом `bootstrap.sh`. `project/` под gitignore — каждое sibling-репо
имеет собственный `.git/` и публикуется отдельно.

```
kacho-workspace/             ← корневой git-репо (этот файл — здесь)
├── CLAUDE.md                ← общие правила (видны из project/* через parent-walkup)
├── .claude/agents/          ← project-level субагенты — видны из всех project/*
├── docs/                    ← specs, plans, qa
└── project/                 ← gitignore'd
    ├── kacho-proto/         ← собственный git
    ├── kacho-corelib/       ← собственный git
    ├── kacho-vpc/           ← собственный git
    └── ...
```

**Discovery субагентов:** Claude Code при запуске из
`project/kacho-vpc/` поднимается вверх по дереву и находит
`kacho-workspace/.claude/agents/` — поэтому общие 13 агентов
автоматически доступны во всех sibling-репо без дублирования.
Service-specific агенты живут в `project/<repo>/.claude/agents/`
рядом с кодом (override workspace-копию при совпадении имён).

| Репо | Роль |
|---|---|
| `kacho-workspace` | корень: CLAUDE.md, общие агенты, спеки, bootstrap-скрипты |
| **`kacho-proto`** | **единая центральная директория для всех `.proto`-определений Kachō** (от всех бекендов, всех доменов). Структура: `proto/kacho/cloud/<domain>/v1/*.proto`. Сгенерированные Go-stubs commit-ятся в `gen/go/...`. Импорт сервисов: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1` |
| `kacho-corelib` | переиспользуемые Go-пакеты (см. ниже) |
| `kacho-api-gateway` | edge: gRPC-proxy + grpc-gateway REST |
| ~~`kacho-resource-manager`~~ | **Упразднён в KAC-124 (E5 sub-phase 2.0).** Organization / Cloud / Folder заменены на **Account / Project** в `kacho-iam`. Backend, Postgres-инстанс, proto-пакеты `kacho.cloud.resourcemanager.v1` / `organizationmanager.v1` удалены полностью. |
| `kacho-iam` | Account / Project / User / ServiceAccount / Group / Role / AccessBinding (заменил resource-manager + organizationmanager) |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint |
| ~~`kacho-vpc-controllers`~~ | **Упразднён в Phase 2.** IPAM (allocate external/internal IP) inline в `kacho-vpc/internal/service/address.go` (request-path); default-SG creation inline в `network.go::doCreate` при `KACHO_VPC_DEFAULT_SG_INLINE=true` (default). |
| `kacho-vpc-implement` | data-plane sibling к kacho-vpc — spec-only, вне build-графа, control-plane его не касается. NIC — first-class публичный ресурс `kacho-vpc` (control-plane-only). Прежняя control-plane-привязка data-plane (Hypervisor-ресурс, vpn_id, NIC-dataplane-проекция) **удалена в KAC-36/79/80**. |
| `kacho-compute` | Instance / Disk / Image / Snapshot |
| `kacho-deploy` | dev-стенд (Postgres + ingress) + e2e-сценарии |
| `kacho-ui` | Vite + React SPA для control plane |
| `kacho-test` | сводный e2e/regression стенд |
| `kacho-yc-shim` | adapter-слой (если нужен для миграции данных/совместимости) |

**Куда складывать новый `.proto`:** ВСЕГДА в `kacho-proto/proto/kacho/cloud/<domain>/v1/`. Сервисные репо НЕ содержат `.proto`-файлов — только Go-импорт сгенерированных stubs из `kacho-proto`. Это упрощает breaking-change detection (один `buf breaking` на всё), синхронизацию версий между сервисами и подключение клиентских SDK.

## Кросс-репо зависимости и порядок выполнения

Polyrepo связан `replace`-директивами в `go.mod` и `COPY ../kacho-*` в Dockerfile'ах.
Чтобы понять **кто от кого зависит** и **в каком порядке делать / мёржить** работу,
размазанную по нескольким репо:

**Граф build-зависимостей** (источник истины — `replace github.com/PRO-Robotech/...` в `*/go.mod`):

```
kacho-proto              ← ни от чего внутри проекта не зависит (центр всех .proto + gen/)
  └─ kacho-corelib       ← replace ../kacho-proto
       ├─ kacho-iam                ┐ (KAC-124: заменил kacho-resource-manager)
       ├─ kacho-vpc                │ каждый сервис: replace ../kacho-corelib + ../kacho-proto.
       ├─ kacho-compute            │ Между собой сервисы НЕ зависят (DB-per-service, общение
       └─ kacho-api-gateway       ┘ только по API) → внутри слоя порядок не важен.
                                     (api-gateway импортирует proto-stubs всех доменов, что проксирует)
kacho-deploy             ← не Go-зависимость; Dockerfile'ы сервисов делают COPY ../kacho-* ,
                            а kacho-deploy/Makefile собирает образы с build-context = parent dir →
                            зависит от исходников всех сервисов + corelib + proto
kacho-ui / kacho-test    ← зависят от REST api-gateway в runtime (не build)
kacho-workspace          ← docs/specs/agents; зависит от всего, от него — ничто
kacho-vpc-implement      ← data-plane sibling kacho-vpc, spec-only, вне build-графа (control-plane его не касается).
                           NIC — first-class публичный ресурс kacho-vpc (control-plane-only); прежняя
                           control-plane-привязка (Hypervisor/vpn_id/NIC-dataplane-проекция) удалена в KAC-36/79/80.
```

Проверить актуальность графа:
`grep -rn "replace github.com/PRO-Robotech" project/*/go.mod` + `grep -rln "COPY \.\./kacho" project/*/Dockerfile`.

**Runtime cross-domain edges** (gRPC service→service вызовы — НЕ build-зависимости, `replace ../` от
них не меняется; см. §«Кросс-доменные ссылки на ресурсы»):
- `kacho-vpc → kacho-compute` — валидация `zone_id` (`compute.v1.ZoneService.Get`), т.к. Geography
  (Region/Zone) — домен kacho-compute (эпик `KAC-15`; раньше было наоборот: `kacho-compute → kacho-vpc`
  proxy зон — **это ребро удалено**).
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup), IPAM-аллокация эфемерных Address (`AddressService` / `InternalAddressService`).
- ~~`* → kacho-resource-manager` — `FolderService.Get`~~ (**KAC-124 удалён**; заменён на `* → kacho-iam.ProjectService.Get` ниже).
- `* → kacho-iam` — `ProjectService.Get` (project existence + account lookup); leaf-owner, обратно не зовёт. Также `InternalIAMService.Check` (Keto-based authz) — для per-RPC authorization-gate в vpc/compute.
Циклы запрещены (см. регламент): A↔B быть не должно.

> Почему `replace ../` а не versioned-модули: осознанный выбор для polyrepo-dev-в-одном-дереве
> (`bootstrap.sh` клонирует siblings в `project/`, локальный gitignored `go.work` из
> `go.work.example`). Переход на versioned modules — workspace-wide migration под релизную фазу,
> не делается раньше (это `wontfix` пока проект не релизится).

**Порядок выполнения / merge для кросс-репо фичи** — топологическая сортировка графа:

1. `kacho-proto` — новые `.proto` + регенерация `gen/` (commit-ится), `buf lint`/`breaking` зелёные.
2. `kacho-corelib` — если меняются общие пакеты (`ids`/`operations`/`db`/...).
3. Сервис(ы) — `kacho-vpc` / `kacho-iam` / `kacho-compute` / ... — в любом порядке между собой (KAC-124: resource-manager упразднён).
4. `kacho-api-gateway` — регистрация новых RPC (public mux / internal mux).
5. `kacho-deploy` — helm/compose tweaks под новый функционал.
6. `kacho-workspace` — docs/specs.

Пока вышестоящие изменения не в `main` своих репо, нижестоящий CI **временно пиннит siblings
к feature-веткам** — `ref:`-строки в `.github/workflows/ci.yaml` (там же комментарий-напоминание).
После merge'а зависимостей `ref:`-строки убираются (или → `ref: main`). Закрывается граф снизу вверх.

**Tracking кросс-репо эпика:** завести **tracking-issue в `kacho-workspace`** (метка `epic`) с
task-list'ом ссылок на per-repo issue/PR **в порядке зависимостей**; каждый зависимый issue/PR в
теле помечает `Blocked by PRO-Robotech/<repo>#<n>`. Так из одного места видно, что чем заблокировано
и что мёржить дальше.

## Чистая архитектура (Clean Architecture)

Каждый сервис организован по слоям Clean Architecture (Uncle Bob). **Строгое dependency rule:**

```
handler ─┐
         ├─→ service ─→ domain
repo ────┤              ↑
clients ─┘              │
                  (только структуры)
```

Структура `internal/`:
- `domain/` — entities (чистый Go-тип, импортирует ТОЛЬКО stdlib и `kacho-proto`)
- `service/` — use-cases (бизнес-логика); определяет port-интерфейсы (`<Resource>Repo`, `<Peer>Client`); импортирует ТОЛЬКО `domain`
- `repo/` — adapter: реализует port-интерфейсы из service, импортирует pgx + domain
- `clients/` — adapter: реализует port-интерфейсы из service, импортирует grpc-stubs + domain
- `handler/` — тонкий transport-слой: parse-request → service.Foo() → format-response. **Никакой бизнес-логики.**
- `cmd/<svc>/main.go` — **единственное** место wiring (composition root)

**Запрещено:**
- `domain/` или `service/` импортируют `pgx`, grpc-stubs, sqlc-types — это утечка adapter в use-case
- Бизнес-логика в `handler/` (валидация полей, ветвления по domain-state, расчёты)
- Глобальные синглтоны (`var globalPool`, `init()`-side-effects) вне `cmd/`

Тесты следуют слоям: unit-тесты `service/` через mock port-интерфейсов; integration-тесты через testcontainers; e2e через api-gateway. Если service-тест требует Postgres — это сигнал об утечке adapter в use-case.

## Git / коммиты

- Коммиты — Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `ci:`, `refactor:`).
- Подпись коммитов — git-config-имя (`user.name` / `user.email` репозитория).
- **НЕ добавлять** `Co-Authored-By: Claude ...` или похожие attribution-trailers — это локальный проект, не open-source с многоавторством.
- Не использовать `--no-verify` для скипа pre-commit hooks без явной просьбы.
- **НЕ пушить в `main` напрямую и не `--force`.** Работа — через ветку = номер тикета (см. ниже) → PR.
- **Все sibling-репо имеют свой `git@github.com:PRO-Robotech/<repo>.git`** (включая `kacho-vpc-implement`); `gh` CLI авторизован (push по ssh). `project/` под gitignore в workspace — у каждого sibling собственный `.git/`.

## Документооборот: YouTrack `KAC` + git-флоу (обязательно)

**Трекер задач — YouTrack-проект `KAC`** на `https://prorobotech.youtrack.cloud/` (доска `agiles/183-12`). Доступ — через MCP `mcp__youtrack__*` ИЛИ напрямую REST `…/api/...` с perm-токеном (если MCP смотрит не на тот инстанс — проверь, что проект `KAC` (id `0-5`) виден; в `prorobotech.youtrack.cloud` так).

- **Эпик** (большая задача) — issue с `[EPIC]` в summary (в проекте `KAC` нет поля `Type`, поэтому «Epic» обозначается так + Subtask-иерархией). Эпик подробно описан: цель, решения, декомпозиция, кросс-репо порядок, Definition of Done.
- **Декомпозиция** — subtasks, залинкованные к эпику через link-type **«Subtask»** (от эпика к ребёнку — `parent for`; от ребёнка к эпику — `subtask of`). Команда: `POST /api/commands {"query":"subtask of KAC-<epic>","issues":[{"idReadable":"KAC-<child>"},…]}`. Каждый subtask **описан** (что сделать, DoD, какой репо, какой артефакт приложить) и блокирующие зависимости перечислены в тексте («Blocked by [CP-RM N]»).
- **Спринт** — каждый созданный issue (эпик и subtasks) **добавляется в текущий спринт** доски `kacho` (агайл `183-12`): `POST /api/commands {"query":"Board kacho <название-спринта>","issues":[{"idReadable":"KAC-N"},…]}`. Текущий спринт — см. `GET /api/agiles/183-12?fields=currentSprint(id,name),sprints(...)` (на 2026-05: «Первый спринт», id `186-22`). **Не забывать** добавлять новые таски в нужный спринт.
- **Роль исполнителя** — поле `агент` (enum, bundle `151-9`): значения = имена субагентов проекта (`acceptance-author`, `acceptance-reviewer`, `system-design-reviewer`, `proto-sync`, `rpc-implementer`, `migration-writer`, `db-architect-reviewer`, `go-style-reviewer`, `api-gateway-registrar`, `srv6-encoding-specialist`, `tenant-isolation-auditor`, `network-security-auditor`, `integration-tester`, `qa-test-engineer`, …; добавлять новые в bundle по мере надобности). Дублируется строкой `**Роль:** <agent>` в описании.
- **Доска / States** (`KAC`): `To do` → `In Progress` → `Test` (готово, ждёт ревью/проверки) → `Done`. Берёшь задачу из беклога (по мере поступления) → переводишь в `In Progress` → работаешь → в `Test` (если нужно ревью) → после ревью/проверки в `Done`. По ходу — комментарии (что сделано, какие решения). **При завершении задачи — таск в `Done` + в комментарий приложить ВСЕ требуемые артефакты** (ссылка на PR, лог прогона тестов, ссылки на сопутствующие изменения в других репо, и т.п.).
- **Гейт**: кодинг любого таска, затрагивающего сервис вне `kacho-vpc-implement`, начинается только после **APPROVED** acceptance-дока соответствующей под-фазы (acceptance-reviewer; см. «Запреты» #1). Таски-acceptance-доки и таски-APPROVE — отдельные subtasks.

**Когда заводить тикет (фича vs фикс) — решается В НАЧАЛЕ запроса, до кодинга/именования веток:**
- **Фича** (новый ресурс / новый API / новый раздел UI / кросс-репо поведенческое изменение) → **тикет СНАЧАЛА**, дальше ветка = `KAC-<N>` в каждом затронутом репо, PR'ы ссылаются на него (`relates`/`Closes KAC-N`), ссылки на PR — комментарием в тикет, тикет гоняется To do→In Progress→Test (CI зелёный / выкачено)→Done. Если ~3+ репо или крупно — **эпик** + Subtask'и + всё в текущий спринт.
- **Фиксы / мелкие UX-правки** → НЕ заводить тикет на каждый. Либо подшить в подходящий открытый тикет, либо завести **ОДИН batch-тикет на рабочую сессию** («VPC/UI bugfix+UX batch — YYYY-MM-DD»): перечень фиксов в описании, PR(ы) комментарием, → Done при merge+деплое. Один мелкий фикс в одиночку — всё равно этот же batch-тикет (дёшево).
- **Тривия** (опечатка, однострочник, чисто docs/коммент) → без тикета, достаточно коммита (или GitHub-issue, если «надо сделать, но ещё не сделано»).
- Не пропускать тикеты задним числом: если существенный кусок проскочил без тикета — завести ретроспективно (чтобы YouTrack был честным); тривию не бэкфиллить.

**git-флоу под задачу:**
- **Ветка = номер тикета**: `git checkout -b KAC-<N>` от `main` (или дефолтной ветки репо). Один тикет может затрагивать несколько репо — ветка `KAC-<N>` создаётся в **каждом** затронутом репо (порядок коммитов/мёржа — по графу зависимостей, см. «Кросс-репо зависимости»).
- Сделал работу → `git push -u origin KAC-<N>` → `gh pr create --title "[KAC-<N>] <summary>" --body "<что и зачем; Closes/relates KAC-<N>>"` → **ссылку на PR кладёшь комментарием в тикет YouTrack** (по одной на каждый затронутый репо). PR ревьюится ролью-ревьюером из описания таска.
- Коммиты — Conventional Commits, в теле — `KAC-<N>` (и `Closes KAC-<N>` в PR-теле финального коммита для репо).
- **После merge PR в `main` и перевода тикета в `Done` — удалить ветку**: `git push origin --delete KAC-<N>` на remote + `git branch -D KAC-<N>` локально (либо `gh pr merge --delete-branch` сразу при merge — он делает обе операции). Это **обязательно**: открытые ветки от закрытых тикетов засоряют репо и `git branch -a`, путают будущих исполнителей. Если ветка живёт в нескольких репо — удалить во всех. Исключение: ветка нужна для последующей зависимой работы (тогда оставляем до закрытия зависимой задачи). Эпик-ветка может оставаться, пока хоть один subtask открыт.
- Эпик **`KAC-2`** (kube-ovn-эпохи data-plane control-plane model: NetworkInterface вариант А + data-plane-привязка NIC/Network/Hypervisor) — **superseded**: data-plane control-plane-слой (Hypervisor-ресурс, vpn_id, NIC-dataplane-проекция) удалён в KAC-36/79/80. Публичный first-class NIC-ресурс kacho-vpc сохранён.

## Баги, задачи, tech-debt

> **Основной трекер — YouTrack `KAC`** (см. выше): эпики, фичи, доска, декомпозиция, артефакты. Раздел ниже — про мелкие per-repo баги/tech-debt в коде, которые удобнее держать как GitHub Issues рядом с кодом; крупная и кросс-репо работа — в YouTrack.

## Баги, задачи, tech-debt — GitHub Issues (не `TODO.md`)

Все найденные баги, доп-задачи, tech-debt, observability-gaps заводятся как **GitHub
Issues в том репо, где они живут** (баг в kacho-vpc → issue в `PRO-Robotech/kacho-vpc`;
общий / кросс-репо — в `PRO-Robotech/kacho-workspace`). **`TODO.md` в репо упразднён** —
где остался, это stub со ссылкой на Issues. Источник истины «что надо сделать» — **открытые
issues**, не файлы в репо.

- **Метки** (общий набор; создавать в репо `gh label create` по мере надобности):
  `bug`, `tech-debt`, `enhancement` — тип; `blocked` + `blocked:kacho-dns` / `blocked:kacho-iam`
  и т.п. — заблокировано ещё-не-реализованным сервисом (в теле issue — «при каких условиях
  браться»); `epic` — tracking-issue кросс-репо работы; `wontfix` — осознанно не делаем (с обоснованием в теле).
- **Кросс-репо зависимость** — в теле issue `Blocked by PRO-Robotech/<repo>#<n>` (GitHub рендерит
  cross-repo ссылку и её статус); порядок — см. «Кросс-репо зависимости и порядок выполнения».
- **Найдено в тестах** (newman / k6 / integration / unit) — заводится issue (`bug` / `tech-debt`);
  в тест-кейсе допустима короткая аннотация `# verifies <...>` (можно со ссылкой на issue), но не
  дублирование описания.
- **Не баг** (осознанное by-design-поведение): структурное расхождение с YC — не повод
  заводить issue (структура методов 1-в-1 не цель); расхождение со **стилем** YC (text,
  regex, error-format, timestamp-precision, update_mask discipline) — повод обсудить.
  Документировать осознанные by-design отклонения — в `docs/architecture/` соответствующего
  сервиса (раздел/файл «известные расхождения»).
- **Не путать** с feature-acceptance-флоу: новая фича по-прежнему требует APPROVED Given-When-Then
  в `docs/specs/sub-phase-X.Y-<topic>-acceptance.md` (см. «Запреты» §1) — Issues для багов/tech-debt/мелких задач.

## Принцип переиспользования через `kacho-corelib`

**Всё, что может быть вынесено в общий компонент для переиспользования в нескольких сервисах — выносится в `kacho-corelib/<package>/`.**

В `kacho-corelib` живут:

- `ids/`, `errors/`, `config/`, `observability/`, `db/` (pgx pool + transactor), `grpcsrv/` (server bootstrap), `grpcclient/` (client factory) — sub-phase 0.1.
- `outbox/`, `selector/` — sub-phase 0.2 (Watch pattern был в `watch/`, удалён в 1.0).
- `operations/` — sub-phase 1.0: Operations table (long-running async ops) + Worker (перевод done=false→true) + Repo. Используется всеми сервисами для возврата `Operation` из мутаций.
- `retry/`, `shutdown/`, `backoff/` — gRPC retry + graceful shutdown helpers.
- `migrations/common/` — общие миграции (`operations` table, `operations_sequence`); синхронизируются в каждое сервисное репо через `make sync-migrations`.
- `audit/` — `AuditLogger` (no-op в текущей фазе, скелет под AAA).

**Перед написанием новой утилиты в сервисном репо** — проверь, есть ли уже подходящий пакет в `kacho-corelib`. Если нет, но логика **будет нужна 2+ сервисам** — оформляй сразу в `kacho-corelib`, не дублируй per-service.

**Исключение:** бизнес-логика конкретного домена (Compute reconciler, VPC ref-validation) живёт в сервисном репо. В corelib — только горизонтальные cross-cutting concerns.

## Запреты (обязательно соблюдать)

1. **НЕ начинать кодирование** до **APPROVED** acceptance-документа Given-When-Then в `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`. Approve выставляет агент `acceptance-reviewer` (а НЕ заказчик — он проверяет только итоговый smoke). См. `04-roadmap-and-phasing.md` §2.
2. **НЕ упоминать «yandex»** в handwritten-коде, README, комментариях, env-name, именах функций.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая миграция.
6. **`Internal.*` методы НЕ публиковать на external endpoint** (TLS-listener `api.kacho.local:443`, advertised endpoint для `yc` CLI / external клиентов). Они могут быть зарегистрированы через api-gateway REST mux и доступны на cluster-internal listener (для UI, admin-tooling, port-forward). Текущие зарегистрированные Internal admin-ресурсы (kacho-only): `AddressPool` под `/vpc/v1/addressPools` (kacho-vpc); `Region`, `Zone` под `/compute/v1/regions`, `/compute/v1/zones` (kacho-compute — перенесены из kacho-vpc, эпик `KAC-15`; до его merge'а ещё `/vpc/v1/regions`, `/vpc/v1/zones`). См. `kacho-vpc/CLAUDE.md` §16, `kacho-compute/CLAUDE.md` §«Geography».

   **Admin-UI правило**: любой новый RPC, нужный admin-UI и не существующий в YC API —
   добавлять **только в `Internal*` сервис** на internal-port (9091), регистрировать через
   тот же `vpcInternalAddr` блок в `kacho-api-gateway/internal/restmux/mux.go`. Не расширять
   публичные сервисы для admin-нужд — это засветит admin-функции на external TLS endpoint.
   (Структурное расхождение с YC — норма, но Internal-vs-external разделение остаётся
   неприкосновенным, см. «Что это за проект» — YC-стилистика остаётся, структура — по делу.)
7. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process реализация справляется.
8. **НЕ создавать новые единые БД** — только database-per-service.
9. **НЕ возвращать ресурс синхронно из мутирующих RPC.** Все мутации (`Create/Update/Delete/Start/Stop/Restart`) возвращают `Operation` (long-running async). Клиент поллит `OperationService.Get(id)` до `done=true`. См. ниже «API contract — flat resources + Operations».
10. **НЕ полагаться на софтварные refcheck / mutex / check-then-act для within-service ссылок и инвариантов** (TOCTOU-баги, как NIC-attach race 2026-05-14). Внутри одной БД сервиса каждая ссылочная зависимость и каждый инвариант **обязан** быть зафиксирован на DB-уровне: FK (`REFERENCES`), `UNIQUE` / partial `UNIQUE WHERE …`, `EXCLUDE`, `CHECK`, либо conditional `UPDATE … WHERE <invariant>` (CAS) + проверка `RETURNING`-кардинальности. Service-слой только маппит SQLSTATE на gRPC code (`23503`→FailedPrecondition, `23505`→AlreadyExists/FailedPrecondition, `23514`→InvalidArgument). Cross-service ссылки (через границу сервиса / DB) — это **исключение** (database-per-service запрещает cross-DB FK): для них остаётся software-validation через peer-API в worker'е по регламенту §«Кросс-доменные ссылки на ресурсы». См. §«Within-service refs — DB-уровень обязателен» ниже.
11. **НИКАКОГО ТЕХ. ДОЛГА / НИКАКИХ TODO НА ПОТОМ (корневое правило).** Любой TODO / follow-up / "будет в следующем PR" / `TODO(KAC-N): implement later` стаб / `XXX` / `FIXME` — **запрещён**. Появилось в процессе → закрываем сразу в том же PR. Не приемлемо «закоммитить с TODO comment'ом и трэкать тикетом» — либо delivery scope сужается, чтобы можно было fully finalize, либо расширяется, чтобы включить весь dependency closure. **Различие**: out-of-scope features (boundary, e.g. `GlobalLoadBalancer` reserved slot + plan doc) — OK, это явная разметка not-in-MVP; **тех. долг (должно работать, но недоделано)** — НЕ OK. Reviewer обязан reject PR с любым свежим TODO/FIXME в diff. (Написано 2026-05-24, KAC-141.)
12. **Test-first (строгий TDD) — ОБЯЗАТЕЛЬНО — и НЕ мёрджить новый RPC / новое proto-поле / новый ресурс / багфикс без тестов в том же PR.**

    **Сначала тест, потом код.** Падающий тест (RED) пишется и **прогоняется ДО** кода фикса/фичи — подтверждается, что он падает по нужной причине (фича/фикс отсутствует, не опечатка). Затем пишется код, доводящий тест до GREEN. Это касается **всех** уровней — Go unit/integration **И newman-кейсов**, не только Go-тестов. **Newman-кейс или integration-тест, написанный уже после кода фикса, — нарушение требования, даже если он зелёный.** Для чанка из нескольких находок/изменений: написать ВСЕ падающие тесты чанка первыми → прогнать → увидеть RED по всем → затем чинить, переводя в GREEN по одному. В PR-описании / отчёте явно показывать пару «RED (до фикса) → GREEN (после)»; заявлять о готовности без неё запрещено.

    Каждый PR с новым RPC, новым полем в существующем сообщении, новым oneof case или новой публичной функцией сервиса обязан содержать **в том же PR**:
    - **Integration-тест** (`internal/repo/*integration_test.go`) — testcontainers Postgres, покрывает SQL-сторону (включая concurrent-race-сценарии для CAS/UNIQUE/EXCLUDE инвариантов).
    - **Newman-кейс** (`tests/newman/cases/*.py` → `gen.py`) — black-box проверка через api-gateway, минимум 1 happy-path + 1 negative (NotFound / FailedPrecondition / InvalidArgument в зависимости от семантики).

    Формулировки `«newman/integration-tests — out of scope этого PR»`, `«follow-up»`, `«TBD»` **запрещены** как обоснование отсутствия тестов в PR-описании или commit-message. Единственно допустимое исключение: PR явно ссылается на **уже открытый** KAC-тикет под эти конкретные тесты (`Tests-followup: KAC-N`), и тикет создан и привязан к тому же эпику ДО merge. Чек-лист в DoD каждого acceptance-документа уже содержит «integration tests + newman cases зелёные» — при review подтверждать наличие.

    Reviewer/agent при ревью PR обязан reject'нуть PR без тестов (или без явной ссылки на trakable follow-up) и попросить дополнить — раньше merge. Оставлять «`Out of scope: newman cases — оставляю для follow-up`» в commit-message как было в KAC-60 — больше не приемлемо. Закрытие эпика без полного test-покрытия — нарушение DoD.

13. **Test-only PR'ы — НЕ ЧИНИМ ПРИКЛАД и НИ ОДНОГО TODO/SKIP/FIXME (даже в комментарии теста).** Когда задача — «дописать тесты под уже существующий функционал / выявить пробелы» (Newman regression coverage, integration backfill), правила:
    - **Прикладной код НЕ трогаем.** PR содержит только изменения `tests/`, `docs/`, обновление `cases/*.py` / `gen.py` output и сопутствующие doc-обновления (`CASES-INDEX.md`/`TEST-PLAN.md`/`PRODUCT-REQUIREMENTS.md`/`RESULTS.md`). Любой `internal/`/`cmd/`/`migrations/`/`*.go`-фикс выносится в **отдельный** PR с собственным KAC.
    - **TODO / FIXME / `pm.test.skip` / закомментированный assertion / «работает до фикса бага X» — запрещены в тестах** так же строго, как в проде (пункт #11). Тест с открытым TODO — это техдолг ⇒ нарушение.
    - **TDD-red против реального бага продукта (тест корректен, но GREEN потребует фикса прода)** — это **finding**, не tech debt: (a) **сразу** заводим GitHub Issue в репо продукта (метка `bug` + `verified-by:test`); (b) в кейсе ставим `# verifies <issue-url>` (но **без** «TODO/skip-until»); (c) кейс ОСТАЁТСЯ красным до фикса прода — это допустимое исключение из «100% pass rate» с явной декларацией в `RESULTS.md` под заголовком «Known failing tests — product bugs» + KAC-trail. После фикса прода — кейс зеленеет, finding закрывается. Прецедент — `SG-DEL-NEG-NIC-ATTACHED` (TDD-red blocked by `KAC-52`).
    - **Если в процессе test-only работы появляется соблазн «правильный кейс невозможен без правки прода»** — STOP, читаем правила: или сужаем кейс (формулируем то, что Newman может проверить уже сейчас), или открываем finding-issue и оставляем TDD-red, или откладываем кейс **с записью в `kacho-vpc/CLAUDE.md` §«Test backlog» + ссылкой на acceptance-доку**. Не «забудем», не «вернёмся позже» в комменте теста.
    - **Reviewer обязан reject'нуть test-only PR с:** изменениями в product-коде (выносить отдельным PR с своим KAC); любыми TODO/FIXME/skip в diff; кейсом без `verifies` / `index:` тега если он наследует существующий паттерн.

    (Написано 2026-05-24, KAC «VPC Newman 100% coverage» эпик; уточнение к §11 + §12 в контексте test-coverage спринтов.)

## Obsidian vault — обязательный context-источник и trail (НЕ упускать)

> **Hooks enforcement**: `.claude/hooks/vault-reminder.sh` (UserPromptSubmit) выводит правила перед каждым prompt'ом; `.claude/hooks/vault-stop-check.sh` (Stop) проверяет активные KAC-тикеты + соотношение code-changes vs vault-changes за последний час + open PR'ы с KAC-номерами. Hooks определены в `.claude/settings.json` workspace-scope.


**Vault**: `kacho-workspace/obsidian/kacho/` (127+ файлов: README + INDEX + `resources/` + `rpc/` + `packages/` + `edges/` + per-repo README + architecture). Самодостаточные узкие записки 1-3KB. **Источник истины** для cross-repo связей, ресурсной модели, RPC-контрактов и runtime-graph'а.

**Как читать (MCP-сервер `obsidian` уже подключён в `~/.claude.json`):**
- В разговоре доступны tools `mcp__obsidian_list_files_in_vault`, `mcp__obsidian_get_note`, `mcp__obsidian_search_notes`.
- Fallback (если MCP недоступен): прямой `Read` от файлов в `obsidian/kacho/`.

### Когда ОБЯЗАТЕЛЬНО читать vault — **до** написания кода

| Триггер | Что прочитать |
|---|---|
| Работа над любым ресурсом `<X>` (Network / Subnet / Address / RT / SG / Gateway / PE / NIC / AddressPool / Organization / Cloud / Folder) | `resources/<repo>-<X>.md` — FK contract, lifecycle, gotchas, ID prefix |
| Добавляем / меняем RPC | `rpc/<repo>-<service>.md` — список методов, REST mapping, sync/async |
| Меняем пакет `<repo>/<pkg>` | `packages/<repo>-<pkg>.md` — exported API, imports, imported-by |
| Cross-service interaction (vpc↔rm, vpc↔compute, api-gw↔backend) | `edges/<caller>-to-<callee>-<purpose>.md` — protocol, sync/async, error handling, history |
| Не уверен с чего начать | `INDEX.md` (алфавитный) либо `README.md` (категориальный) |

> **Цель — minimum context**: загрузить ОДИН-ДВА узких файла (1-3KB), а не 50KB per-repo README. Если требуется > 3 vault-файлов, остановись и переосмысли scope задачи.

### Когда ОБЯЗАТЕЛЬНО обновлять vault — **после** работы

| Триггер | Что обновить / создать |
|---|---|
| Изменилась структура ресурса (новое поле / status enum / FK / immutable rules) | `resources/<repo>-<X>.md` — обновить таблицу полей, FK contract, lifecycle |
| Добавлен / изменён / удалён RPC | `rpc/<repo>-<service>.md` — обновить method table, REST mapping |
| Изменился exported API пакета (новый тип, новая функция, новый интерфейс) | `packages/<repo>-<pkg>.md` — обновить exported types/functions, imports, imported-by |
| Изменилось cross-service runtime поведение (новый peer-вызов, изменение sync→async, removal) | `edges/<caller>-to-<callee>-<purpose>.md` — обновить + добавить запись в "History" с KAC-номером |
| Новая миграция, схема rename, новый CHECK constraint | соответствующий `resources/<X>.md` + `packages/<repo>-<pkg>.md` |
| Известная gotcha / расхождение от skill evgeniy / known-divergence от YC | соответствующий `resources/<X>.md` § "Gotchas" |
| Работа по KAC-тикету затронула architecture | `KAC/KAC-<N>.md` (см. ниже) + ссылка на изменённый `resources/` / `rpc/` / `packages/` / `edges/` |

> **Если затрагиваешь поведение, которого нет в vault** — НЕ молчи. **Создай новую узкую запись** в соответствующей категории (1-3KB) либо допиши в существующую. Vault должен оставаться **полным** trail'ом изменений.

### KAC-тикеты — обязательный trail в vault

Каждый KAC-тикет (фича / batch fix / эпик) обязан иметь заметку в vault:

**Path**: `obsidian/kacho/KAC/KAC-<N>.md` (создай папку `KAC/` если её нет).

**Формат** (≤ 3KB):

```markdown
# KAC-<N>: <summary>

**Status**: in-progress | test | done | wontfix
**Type**: feature | fix | refactor | docs | epic
**Repos**: kacho-vpc, kacho-deploy   (или один)
**PRs**: PRO-Robotech/kacho-vpc#74, ...   (по мере merge)
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-<N>

## Что и зачем

1-2 абзаца: проблема + решение.

## Затронутые сущности vault

- [[../resources/vpc-network]] — добавлен default-SG inline
- [[../packages/vpc-apps-kacho-api-network]] — CreateDefaultSGUseCase
- [[../edges/vpc-to-rm-folder-exists]] — removed sync precheck
- [[../rpc/vpc-network-service]] — sync `NotFound` → async

## Acceptance / Definition of Done

- [ ] integration tests зелёные
- [ ] newman E2E зелёный
- [ ] vault записи обновлены (resources / rpc / packages / edges)
- [ ] PR merged в main

## Связанные тикеты

- [[KAC-93]] (предусловие)
- [[KAC-95]] (follow-up)

#kac #epic|fix|feature
```

**Когда создавать `KAC-<N>.md`**:
- При **первом** упоминании тикета в работе (даже если только обсуждаем).
- При создании ветки `git checkout -b KAC-<N>`.
- Если работа без тикета (тривия) — заметка НЕ нужна.

**Когда обновлять**:
- После каждого merge'а PR — добавить PR-URL и обновить acceptance чек-лист.
- После перевода тикета в `Test`/`Done` в YT — синхронизировать `Status:` в заметке.
- При changes scope / новые блокеры / cross-repo ссылки — обновить body.

### Чек-лист на каждое начало работы (НЕ упускать)

1. Прочитать релевантный `resources/<X>.md` или `rpc/<service>.md` (1 файл, 1-3KB).
2. Если KAC-тикет известен — открыть `KAC/KAC-<N>.md` (создать если нет).
3. Прочитать связанные `edges/` если работа cross-service.
4. Прочитать связанные `packages/` если меняешь internal API.

### Чек-лист на каждое окончание работы (НЕ упускать)

1. Обновить vault-записи которых коснулись изменения (resources/rpc/packages/edges).
2. Создать новые узкие записи если появились **новые** сущности/связи.
3. Обновить `KAC/KAC-<N>.md` — добавить PR-URL, отметить пункты в acceptance чек-листе.
4. Если затронут architecture-level (cross-repo) — обновить `architecture.md`.

### Запреты

- **НЕ** загружать `kacho-vpc/CLAUDE.md` (большой контекст) если хватает 1-2 файлов из vault.
- **НЕ** оставлять stale-данные в vault (если факт устарел — fix entry сразу же).
- **НЕ** дублировать содержимое vault в коде / комментариях / commit-messages.
- **НЕ** забывать `KAC/KAC-<N>.md` для каждого тикета — это primary trail работы.
- **НЕ** записывать секреты (токены, пароли) в vault — он git-committed.

---

## API contract — flat resources + Operations (с фазы 1.0)

**Каждый ресурс — плоский message** с domain-полями на верхнем уровне:
```protobuf
message Instance {
  string id = 1;
  string folder_id = 2;
  google.protobuf.Timestamp created_at = 3;
  string name = 4;
  string description = 5;
  map<string,string> labels = 6;
  string zone_id = 7;
  Status status = 10;       // enum, не nested message
  // ...domain-specific fields плоско
}
```

**Service шаблон:**
```protobuf
service InstanceService {
  rpc Get(GetInstanceRequest) returns (Instance);                  // sync read
  rpc List(ListInstancesRequest) returns (ListInstancesResponse);  // sync read
  rpc Create(CreateInstanceRequest) returns (operation.Operation); // async
  rpc Update(UpdateInstanceRequest) returns (operation.Operation); // async
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation); // async
}
```

**Operation message** в `kacho.cloud.operation.v1`:
```protobuf
message Operation {
  string id = 1;
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  bool done = 6;
  google.protobuf.Any metadata = 7;     // {instance_id} для CreateInstanceMetadata
  oneof result {
    google.rpc.Status error = 8;
    google.protobuf.Any response = 9;   // Instance
  }
}
```

**Что выкинуто (deprecated с 1.0):**
- Watch RPC — больше не существует. Клиент использует List-polling 2-5 сек или Operations.Get(id) для in-flight задач.
- `kacho-corelib/watch/` package — удалён.
- gRPC server-streaming через grpc-gateway / WebSocket для Watch — выкинут.

## Инфра-чувствительные данные — ТОЛЬКО во внутреннем API (обязательно)

**Любая информация, раскрытие которой компрометирует инфраструктурный слой (помогает
картировать/таргетировать/атаковать физику и data-plane), живёт ИСКЛЮЧИТЕЛЬНО в `Internal*`-API
(internal-port 9091 / cluster-internal listener) — НИКОГДА не на публичной gRPC/REST-поверхности.**

К «инфра-чувствительному» относится (не исчерпывающе):
- **placement / физика**: на каком физическом хосте лежит NI/инстанс; инвентарь и состояние/ёмкость хостов — internal-only.
- **underlay / транспорт**: внутренние транспортные/маршрутные идентификаторы хостов, carrier-адреса, туннельные эндпоинты, id routing-таблиц/VRF.
- **wiring**: имена host-интерфейсов, netns'ов, gateway-anchor'ы (`169.254.x.y`), id контейнеров на хостах, статусы программирования ядра.
- **числовой инфра-идентификатор** ресурса — это инфра-инфа, она на **internal-вью** ресурса, не на публичном.

> Конкретная прежняя control-plane-привязка инфра-слоя (Hypervisor-ресурс, vpn_id, NIC-проекция
> инфра-полей) **удалена в KAC-36/79/80**; принцип «инфра-данные только в `Internal*`-API»
> остаётся как требование к дизайну.

**Публичная поверхность** ресурса показывает только tenant-facing «намерение + результат»: id ресурса, name/labels, привязки (folder/network/subnet/instance), выделенный tenant-адрес(а), `status`. Всё «как это разложено по железу» — только через `Internal*`-методы, которыми пользуются control-plane-компоненты, admin-UI, тулинг.

**Следствия для дизайна ресурсов**: ресурс **может** иметь ДВЕ проекции — публичную (lean, tenant-facing) и internal (full, с инфра-полями). Напр.: `NetworkInterface` — публично {id, instance_id, subnet_id, primary_v4_address, status}; internal-проекция (если понадобится) добавит placement/wiring-поля (физический хост, host-wiring). Реализация — поле с пометкой «internal-only, не заполняется в публичных ответах» либо отдельный internal-message; концептуально — недоступно публично. (Это шире и строже, чем «Запреты» #6 про admin-методы — там про *методы*, тут про *данные*.)

> Прежняя конкретная internal-проекция NIC/Network (vpn_id, hv_id и прочие инфра-поля) и ресурс
> `Hypervisor` **удалены в KAC-36/79/80**. Принцип двух-проекций остаётся как требование к дизайну.

> Почему: defense-in-depth — даже если публичный API скомпрометирован (или tenant имеет read к своим ресурсам), он не должен узнать физическую топологию / placement — это разведка для lateral movement и таргетинга; tenant сети A не должен мочь вывести «мой инстанс и инстанс tenant'а B на одном железе».

## Within-service refs — DB-уровень обязателен (parity с запретом #10)

Все ссылочные зависимости и инварианты **внутри одной БД сервиса** должны быть выражены DB-конструкциями. Software-side `Get → check → Update` (TOCTOU) запрещён — это race-prone и привёл к реальному инциденту (NIC-attach 2026-05-14: две Compute.Instance.Create указали один `existing_network_interface_id`, обе прошли software-guard `if cur.UsedByID != ""`, обе вызвали безусловный `UPDATE network_interfaces SET used_by_id = ...`, second writer wins).

### Инструменты на DB-уровне (выбор по типу инварианта)

| Инвариант | DB-механизм | Пример |
|---|---|---|
| «Этот id обязан существовать в той же БД» | `FK REFERENCES <table>(id) ON DELETE {RESTRICT\|CASCADE\|SET NULL}` | `subnets.network_id → networks(id) ON DELETE RESTRICT` |
| «Поле уникально» | `UNIQUE` или `CREATE UNIQUE INDEX … (...)` | `networks_folder_id_name_key` |
| «Уникально только если поле не пусто» (partial) | partial `UNIQUE … WHERE <cond>` | `addresses_external_pool_ip_uniq … WHERE (external_ipv4 ->> 'address') <> ''` |
| «Range не пересекается с другим range» | `EXCLUDE USING gist (… WITH &&)` | `subnets_no_overlap_v4` |
| «Простой предикат на поле/строке» | `CHECK (…)` | `addresses CHECK (external_ipv4 IS NOT NULL OR internal_ipv4 IS NOT NULL OR internal_ipv6 IS NOT NULL)` |
| «Атомарный compare-and-swap при изменении» | conditional `UPDATE … WHERE <expected-state> RETURNING …` + проверка кардинальности | `UPDATE … SET used_by_id=$new WHERE id=$id AND (used_by_id='' OR used_by_id=$new) RETURNING …` |
| «Read-modify-write с OCC, без отдельной колонки версии» | `xmin::text` snapshot + `UPDATE … WHERE xmin::text = $expected` | `security_group_occ_integration_test` (см. kacho-vpc) |
| «Уникальная аллокация из пула под concurrency» | `FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` | `address_pool_free_ips` (kacho-vpc, миграция 0015) |

### Шаблон: ссылочная безопасность attach-операций / смены ownership

❌ **НЕЛЬЗЯ** (TOCTOU):
```go
cur, _ := repo.Get(ctx, id)                           // (1) SELECT
if cur.OwnerID != "" && cur.OwnerID != newOwner {     // (2) check
    return FailedPrecondition
}
repo.SetOwner(ctx, id, newOwner, ...)                 // (3) unconditional UPDATE — race!
```
Между (2) и (3) другая транзакция меняет `OwnerID`; третий шаг безусловно
перезаписывает уже изменённое значение → second-writer-wins, потеря ownership.
Точно эта схема привела к инциденту 2026-05-14 (KAC-52, NIC attach race).

✅ **МОЖНО** (атомарный single-statement CAS на одной row):
```sql
UPDATE <table>
   SET <owner-col> = $new, <other-fields…>
 WHERE id = $id
   AND (<owner-col> = '' OR <owner-col> = $new)   -- CAS: либо свободно, либо уже наш
RETURNING …;
```
- 0 rows из RETURNING → `pgx.ErrNoRows` → `service.ErrFailedPrecondition` → gRPC `FailedPrecondition`.
- Идемпотентный re-attach к тому же owner проходит (вторая часть условия).
- Single-statement UPDATE на одной row защищён row-level lock-ом Postgres: параллельный writer **ждёт commit-а первого**, после чего видит уже обновлённый row, CAS не matches → 0 rows. Никакого extra UNIQUE-индекса не нужно.

⚠️ **Не пытайтесь добавить `UNIQUE (<owner-col>) WHERE <owner-col> <> ''` как «backstop»** — это семантически другой инвариант: «значение owner-col уникально среди всех row». Для one-owner-per-resource это правильно (например, `addresses_external_pool_ip_uniq` — один IP может принадлежать одному Address). Но для **one-resource-per-owner-or-many-resources** (один Compute.Instance имеет N NetworkInterface — multi-NIC AWS-ENI) такой UNIQUE будет ложно ловить нормальные multi-attach state. Атомарный CAS выше уже race-proof и достаточен. (KAC-52 миграция 0016 наступила на эти грабли — откачена в 0017.)

Когда **partial UNIQUE действительно нужен** — отдельный паттерн ниже:

```sql
-- «один IP назначен максимум одному Address» — правильное применение partial UNIQUE.
CREATE UNIQUE INDEX addresses_external_pool_ip_uniq
    ON addresses ((external_ipv4 ->> 'address_pool_id'),
                  (external_ipv4 ->> 'address'))
    WHERE (external_ipv4 ->> 'address') <> '';
```
Тут уникальность — на свойстве самого ресурса, а не на ссылке от него.

### Что это **НЕ** покрывает

Cross-service ссылки (`Address.folder_id → folders.id`, `Subnet.zone_id → zones.id` после KAC-15, `Instance.network_interfaces[].subnet_id → subnets.id` и т.п.) — это **через границу сервиса**: разные БД, FK невозможны (запрет #8). Для них остаётся software-validation в worker'е через peer-API + грациозный dangling-ref на чтении. Регламент — следующий раздел.

### Чек-лист при добавлении нового ссылочного поля или инварианта

1. Поле ссылается на ресурс **в той же БД**? → FK + при необходимости partial UNIQUE/EXCLUDE. **Никогда** software-only.
2. Уникальность включается условно (например, только пока ресурс «занят») → partial UNIQUE с `WHERE …`.
3. Состояние ресурса может меняться по конкурирующим путям (attach/detach, allocate/free) → атомарный conditional UPDATE с CAS-условием **плюс** partial UNIQUE как safety-net.
4. SQLSTATE → gRPC mapping должен быть в `mapRepoErr` (или сервис-специфичном maperr): 23503→FailedPrecondition, 23505→AlreadyExists/FailedPrecondition (по контексту), 23514→InvalidArgument, 23P01→FailedPrecondition. Никогда не leak `pgx`-текст наружу.
5. Integration-тест (testcontainers): concurrent goroutines на спорный путь → проверить, что **ровно одна** транзакция прошла, остальные получили ожидаемый sentinel. Без этого теста не мерж'им — race не отлавливается unit-тестом.

## Кросс-доменные ссылки на ресурсы (owner-сервис / consumer-сервис) — регламент

> **Парный раздел к §«Within-service refs — DB-уровень обязателен» выше.** Within-service ссылки/инварианты (Network ↔ Subnet ↔ Address ↔ NIC внутри одной БД `kacho_vpc`; Instance ↔ Disk внутри `kacho_compute` и т.п.) — **только DB-уровень** (FK/UNIQUE/EXCLUDE/CAS), software-side TOCTOU запрещён (запрет #10). Этот раздел — про **другую** часть графа ссылок: между разными БД сервисов, где FK физически невозможен (запрет #8).

Когда сервису нужно сослаться на ресурс, которым он **не владеет** (его домен — другой сервис:
VPC-подсеть ссылается на `Zone` из Compute; VPC-сеть / Compute-инстанс ссылается на `Project` из
kacho-iam — DB-колонка `folder_id` = id владельца-проекта, legacy-имя) — действует единый базовый флоу:

1. **Один владелец на тип ресурса.** Каждый тип ресурса хранится ровно в одном сервисе-владельце,
   который экспонирует канонический CRUD/read-API. Другие сервисы **не держат копию строк** (никаких
   mirror-таблиц «на всякий случай») и **не делают cross-service DB FK** (см. §запрет 4, 8 —
   целостность по FK только в пределах одной схемы).

2. **Consumer ссылается по id (строка), валидирует через API владельца.** Чужой id (`folder_id`,
   `zone_id`, `subnet_id`, …) хранится как обычная `TEXT`-колонка без FK. На request-path
   (`Create`/`Update`, где id принимается/меняется) consumer валидирует существование/состояние
   вызовом `Get` у владельца — через типизированный gRPC-клиент `internal/clients/<owner>_client.go`
   (port-интерфейс — в `service/`, реализация — в `clients/`, как любой adapter). Не найдено /
   неподходящее состояние → `InvalidArgument` / `FailedPrecondition`. Владелец недоступен →
   `Unavailable` (fail-closed для мутаций; чтение уже сохранённых данных повторно НЕ валидируется —
   dangling-ref переживается, см. п.4). Кросс-сервисные вызовы идут **сервис→сервис напрямую**
   (cluster-internal), не через api-gateway.

3. **Денормализованные зеркала — read-only и помечены.** Если consumer-у нужно *показывать* атрибуты
   чужого ресурса рядом со своим (имя/статус зоны у подсети, имя фолдера у сети) — допустимо
   денормализовать, но: (a) поле помечено output-only «denormalised mirror, source of truth =
   `<owner>.<Resource>`»; (b) обновляется на чтении / list-poll'ом владельца; (c) **никогда не
   источник истины** и не принимается на вход в `Create`/`Update`.

4. **Удаление и ссылочная целостность через границу сервиса.** Владелец **не спрашивает** consumer-ов
   перед удалением (нет cross-service cascade — §запрет 4). Удаление ещё-используемого чужого ресурса —
   забота оператора; владелец *может* отдавать best-effort usage-hint (`used_by` / `referenced_by`,
   как `Address.used_by`), но это не гарантия. Consumer обязан **грациозно переживать dangling-ref**
   (подсеть, чью зону удалили → деградированный статус, а не паника). Жёсткие гарантии целостности —
   только внутри одной схемы (same-schema FK).

5. **Карта владельцев доменов** (кто канонический owner):
   - **Geography** — `Region`, `Zone` → **`kacho-compute`** (раньше было в `kacho-vpc`; перенесено, см. эпик `KAC-15`).
   - **IAM** — `Account` / `Project` / `User` / `ServiceAccount` / `Group` / `Role` / `AccessBinding` → **`kacho-iam`** (KAC-124: заменил `kacho-resource-manager` Organization / Cloud / Folder; backend и proto-пакеты `kacho.cloud.resourcemanager.v1` / `organizationmanager.v1` удалены).
   - **Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint / NetworkInterface** → `kacho-vpc`.
   - **Instance / Disk / Image / Snapshot / DiskType** → `kacho-compute`.
   - **Operation** — каждый сервис ведёт свои (общая `operations`-таблица per-service из corelib), не кросс-доменно.
   - Если ресурс инфра-чувствительный — он internal-only у своего владельца (см. §«Инфра-чувствительные данные»).

6. **Где экспонируется API владельца.** Tenant-видимый справочник (`Folder`, `Zone`, `Region`) —
   публичный read-only `Get`/`List` на сервисе-владельце; admin-мутации справочника — на
   `Internal*`-сервисе владельца (§запрет 6). Consumer для валидации зовёт у владельца доступный ему
   метод (обычно `Get`) — для consumer-а неважно, internal это listener или public; важно, что вызов
   прямой service→service.

7. **Направление зависимости / build-граф.** Кросс-доменный gRPC-вызов — **runtime**-зависимость
   (consumer импортирует proto-stubs владельца и его клиент), **не build**-зависимость → `replace ../`
   в `go.mod` не меняются, но **новое ребро фиксируется** в §«Кросс-репо зависимости» как runtime-edge.
   **Циклы запрещены**: если A зовёт B, B не должен звать A. Пример: было `kacho-compute → kacho-vpc`
   (proxy зон) — заменяется на `kacho-vpc → kacho-compute` (валидация `zone_id`); `kacho-iam` —
   leaf-owner (Account/Project, заменил `kacho-resource-manager` Folder в KAC-124): в него только звонят, он сам — никуда.

> Почему именно так: DB-per-service (§запрет 8) запрещает общую БД и cross-service FK → ссылочная
> целостность через границу сервиса невозможна на уровне БД, её заменяет «валидация на request-path +
> грациозный dangling-ref». Mirror-таблицы (как старый compute-`zones` seed) расходятся с источником
> и порождают split-brain — поэтому запрещены; вместо зеркала — прямой вызов владельца (+ опц.
> denorm-кэш для UI, но помеченный и не авторитетный).

## Локальная разработка (быстрые команды)

Все команды относительно корня workspace (где этот файл). Сервисы — в `project/`.

- Развернуть стенд: `cd project/kacho-deploy && make dev-up`
- Снести стенд: `cd project/kacho-deploy && make dev-down`
- Перезапустить один сервис: `cd project/kacho-deploy && make reload-svc SVC=compute`
- Логи сервиса: `cd project/kacho-deploy && make logs-svc SVC=compute`
- Открыть psql сервиса: `cd project/kacho-deploy && make psql SVC=compute`
- Обновить все репо: `./sync-all.sh` (или `cd <workspace> && ./sync-all.sh`)

## Спецификация (5 документов)

1. `docs/specs/00-overview-and-scope.md` — обзор и принципы
2. `docs/specs/01-architecture-and-services.md` — граф сервисов, RPC
3. `docs/specs/02-data-model-and-conventions.md` — data model, schemas, naming
4. `docs/specs/03-deployment-and-operations.md` — deployment, operations, CLAUDE.md иерархия
5. `docs/specs/04-roadmap-and-phasing.md` — sub-итерации 0.1–0.7, TDD-workflow

## Subagents (`.claude/agents/`)

**Workspace-level (видны из любого `project/<repo>/` через parent-walkup
discovery — Claude Code поднимается по дереву от cwd до первого `.claude/agents/`):**

**Task-execution (7):** `acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`.

**Specialist-review (6):** `acceptance-reviewer`, `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`, `qa-test-engineer`.

**Service-specific (живут в `project/<repo>/.claude/agents/`):**

Если домен требует узкоспециализированной экспертизы (YC-style parity, специфические инварианты, regression-tooling) — создавай агентов **в самом сервисном репо**, не в workspace. Эталонный пример — `kacho-vpc/.claude/agents/` + `.claude/skills/`:
- `vpc-yc-parity-auditor` — аудит YC-стиля (regex, error texts, status codes, timestamp,
  update_mask discipline). Проверяет **форму** (не структуру); структурные расхождения — норма
  (см. «Что это за проект»). Активен в режиме «стиль да, структура — по делу».
- `vpc-cidr-specialist` — CIDR (host-bits, EXCLUDE constraint, overlap, internal IP).
- `vpc-outbox-watch-engineer` — outbox + LISTEN/NOTIFY + InternalWatchService.
- `vpc-newman-author` — newman regression suites (декларативные `cases/*.py` → `gen.py`).
- `vpc-load-testing` — нагрузочные сценарии VPC (k6 + ghz Jobs).
- skills: `testing-code-coach`, `testing-product-coach`, `vpc-load-testing` (+ workspace `load-testing-coach`).

При совпадении имён project-level override-ит workspace-level (Claude Code находит ближайший `.claude/agents/` первым).

**Использовать готовые (не создавать заново):** `Explore`, `Plan`, `general-purpose`, `superpowers:code-reviewer`, `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:requesting-code-review`.

> Напоминание: `Internal.*` методы сервисов не должны попадать в api-gateway. Это ответственность `api-gateway-registrar`.

## Permissions

`.claude/settings.json` использует `bypassPermissions` для локальной dev-машины. Можно ужесточить позже.
