# Kachō — Workspace CLAUDE.md

Этот файл загружается Claude Code при работе из самого `kacho-workspace/`
и **из любой подпапки `kacho-workspace/project/<repo>/`** благодаря
parent-walkup discovery (см. §«Структура репозиториев»).

## Что это за проект

Kachō — облачная управляющая платформа: домены Organization/Cloud/Folder, VPC (Network/Subnet/SecurityGroup/RouteTable/Address/Gateway/PrivateEndpoint), Compute (Instance/Disk/Image/…), NLB, плюс **реальный data-plane на гипервизорах** (`kacho-vpc-implement` — SRv6/eBPF; остальные сервисы пока control-plane-only).

> **Verbatim-YC parity — ОТЛОЖЕНА (не текущее требование).** Раньше цель была — побайтовое
> соответствие Yandex Cloud API (proto-форма, error texts, status codes, regex'ы, behavioural
> semantics). Сейчас это **снято с приоритета**: API проектируем в **чистой, удобной форме**
> (можно расходиться с YC — например, NIC как отдельный AWS-ENI-подобный ресурс, `vpn_id` на
> Network, отдельный ресурс Hypervisor, и т.п.), а YC-совместимость — это **отдельная поздняя
> фаза** (compat-слой через `kacho-yc-shim` или таргетированный рефакторинг), а не constraint
> на нынешний дизайн. Следствия: где документы/агенты/правила говорят «verbatim YC / нельзя
> расходиться с YC / сломает parity» — читать как **«пока неактивно»**; `vpc-yc-parity-auditor`
> / `proto-api-reviewer` (в части YC-parity) на паузе; «known divergence с verbatim YC» больше
> не понятие — расхождения это норма. Что остаётся в силе: §«Запреты» #2 («НЕ упоминать
> «yandex»» — гигиена, тем более когда мы не копируем), Internal-vs-external разделение (#6),
> flat-resources+Operations контракт, acceptance-workflow (#1).

Полная спека: `kacho-workspace/docs/specs/00-overview-and-scope.md` и далее (раздел про YC-parity
там тоже надо читать через эту врезку — «отложено»).

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
| `kacho-resource-manager` | Organization / Cloud / Folder |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint |
| ~~`kacho-vpc-controllers`~~ | **Упразднён в Phase 2.** IPAM (allocate external/internal IP) inline в `kacho-vpc/internal/service/address.go` (request-path); default-SG creation inline в `network.go::doCreate` при `KACHO_VPC_DEFAULT_SG_INLINE=true` (default). |
| `kacho-vpc-implement` | data-plane sibling to kacho-vpc: SRv6 + IPv6 underlay + dual-stack overlay + NLB-DSR на гипервизорах. Spec-only до Phase 1.0 (+ runnable MVP). Стратегия реализации **зафиксирована** в `docs/specs/09-implementation-strategy.md`: свой eBPF data-plane, `cilium/ebpf` как loader, `cilium/cilium/pkg/maglev` как библиотека, **GoBGP** (не FRR), kernel-native `seg6local`. Серия `docs/specs-oss-stack/` (vendor Cilium eBPF C) — отвергнута, оставлена как архив. Bootstrap (`sub-phase-1.0`) требует APPROVED acceptance-док перед кодированием. **Control-plane resource model — реализована** (эпик `KAC-2`, subtasks `KAC-3…KAC-11`,`KAC-14`): NIC — first-class ресурс `kacho-vpc` (вариант А); `vpn_id` на Network — internal-only, аллоцирует kacho-vpc; `Hypervisor`/`node_index` — internal-ресурс kacho-compute; impl-controller **читает** `vpn_id`/`node_index` из upstream internal API (per-NI `sid_seq` аллоцирует сам), пишет data-plane-state обратно через `kacho-vpc InternalNetworkInterfaceService.ReportNiDataplane`. |
| `kacho-compute` | Instance / Disk / Image / Snapshot |
| `kacho-loadbalancer` | NLB / TargetGroup |
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
       ├─ kacho-resource-manager  ┐
       ├─ kacho-vpc                │ каждый сервис: replace ../kacho-corelib + ../kacho-proto.
       ├─ kacho-compute            │ Между собой сервисы НЕ зависят (DB-per-service, общение
       ├─ kacho-loadbalancer       │ только по API) → внутри слоя порядок не важен.
       └─ kacho-api-gateway       ┘  (+ импортирует proto-stubs всех доменов, что проксирует)
kacho-deploy             ← не Go-зависимость; Dockerfile'ы сервисов делают COPY ../kacho-* ,
                            а kacho-deploy/Makefile собирает образы с build-context = parent dir →
                            зависит от исходников всех сервисов + corelib + proto
kacho-ui / kacho-test    ← зависят от REST api-gateway в runtime (не build)
kacho-workspace          ← docs/specs/agents; зависит от всего, от него — ничто
kacho-vpc-implement      ← spec-only до Phase 1.0 (+ runnable MVP); sibling kacho-vpc (data-plane), пока не в build-графе.
                           Control-plane resource model реализована (эпик KAC-2): NIC — first-class ресурс kacho-vpc,
                           impl-controller читает vpn_id/node_index из upstream internal API, write-back ReportNiDataplane.
```

Проверить актуальность графа:
`grep -rn "replace github.com/PRO-Robotech" project/*/go.mod` + `grep -rln "COPY \.\./kacho" project/*/Dockerfile`.

**Runtime cross-domain edges** (gRPC service→service вызовы — НЕ build-зависимости, `replace ../` от
них не меняется; см. §«Кросс-доменные ссылки на ресурсы»):
- `kacho-vpc → kacho-compute` — валидация `zone_id` (`compute.v1.ZoneService.Get`), т.к. Geography
  (Region/Zone) — домен kacho-compute (эпик `KAC-15`; раньше было наоборот: `kacho-compute → kacho-vpc`
  proxy зон — **это ребро удалено**).
- `kacho-vpc-implement → kacho-vpc` — write-back `InternalNetworkInterfaceService.ReportNiDataplane` (эпик `KAC-2`).
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup), IPAM-аллокация эфемерных Address (`AddressService` / `InternalAddressService`).
- `* → kacho-resource-manager` — `FolderService.Get` (folder existence + cloud lookup); leaf-owner, обратно не зовёт.
Циклы запрещены (см. регламент): A↔B быть не должно.

> Почему `replace ../` а не versioned-модули: осознанный выбор для polyrepo-dev-в-одном-дереве
> (`bootstrap.sh` клонирует siblings в `project/`, локальный gitignored `go.work` из
> `go.work.example`). Переход на versioned modules — workspace-wide migration под релизную фазу,
> не делается раньше (это `wontfix` пока проект не релизится).

**Порядок выполнения / merge для кросс-репо фичи** — топологическая сортировка графа:

1. `kacho-proto` — новые `.proto` + регенерация `gen/` (commit-ится), `buf lint`/`breaking` зелёные.
2. `kacho-corelib` — если меняются общие пакеты (`ids`/`operations`/`db`/...).
3. Сервис(ы) — `kacho-vpc` / `kacho-resource-manager` / ... — в любом порядке между собой.
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
- Эпик **`KAC-2`** (control-plane resource model: NetworkInterface вариант А + vpn_id на Network internal + Hypervisor в compute + impl reads from upstream) — **код смержен** (subtasks `KAC-3…KAC-11`,`KAC-14`); `KAC-13` — doc-обновление под него.

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
- **Не баг** (осознанное by-design-поведение; «расхождение с YC» больше не повод заводить issue — verbatim-parity отложена) → **не issue**, а запись в
  `docs/architecture/` соответствующего сервиса (раздел/файл «известные расхождения»).
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

**Исключение:** бизнес-логика конкретного домена (Compute reconciler, VPC ref-validation, NLB target-deregister finalizer) живёт в сервисном репо. В corelib — только горизонтальные cross-cutting concerns.

## Запреты (обязательно соблюдать)

1. **НЕ начинать кодирование** до **APPROVED** acceptance-документа Given-When-Then в `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`. Approve выставляет агент `acceptance-reviewer` (а НЕ заказчик — он проверяет только итоговый smoke). См. `04-roadmap-and-phasing.md` §2.
2. **НЕ упоминать «yandex»** в handwritten-коде, README, комментариях, env-name, именах функций.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая миграция.
6. **`Internal.*` методы НЕ публиковать на external endpoint** (TLS-listener `api.kacho.local:443`, advertised endpoint для `yc` CLI / external клиентов). Они могут быть зарегистрированы через api-gateway REST mux и доступны на cluster-internal listener (для UI, admin-tooling, port-forward). Текущие зарегистрированные Internal admin-ресурсы (kacho-only): `AddressPool` под `/vpc/v1/addressPools` (kacho-vpc); `Region`, `Zone` под `/compute/v1/regions`, `/compute/v1/zones` (kacho-compute — перенесены из kacho-vpc, эпик `KAC-15`; до его merge'а ещё `/vpc/v1/regions`, `/vpc/v1/zones`). См. `kacho-vpc/CLAUDE.md` §16, `kacho-compute/CLAUDE.md` §«Geography».

   **Admin-UI правило**: любой новый RPC, нужный admin-UI и не существующий в verbatim-YC API — добавлять **только в `Internal*` сервис** на internal-port (9091), регистрировать через тот же `vpcInternalAddr` блок в `kacho-api-gateway/internal/restmux/mux.go`. Не расширять публичные сервисы для admin-нужд — это засветит admin-функции на external TLS endpoint (verbatim-parity — отложена, см. «Что это за проект», но Internal-vs-external разделение остаётся).
7. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process реализация справляется.
8. **НЕ создавать новые единые БД** — только database-per-service.
9. **НЕ возвращать ресурс синхронно из мутирующих RPC.** Все мутации (`Create/Update/Delete/Start/Stop/Restart`) возвращают `Operation` (long-running async). Клиент поллит `OperationService.Get(id)` до `done=true`. См. ниже «API contract — flat resources + Operations».

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
- **placement / физика**: на каком гипервизоре (HV) лежит NI/инстанс; инвентарь и состояние/ёмкость HV; ресурс `Hypervisor` целиком — internal-only.
- **underlay / транспорт**: SID-локаторы HV, per-NI SID'ы, underlay/carrier-адреса, GRE/FOU/туннельные эндпоинты, BGP-детали, id routing-таблиц/VRF.
- **data-plane-wiring**: имена host-интерфейсов (`kh-…`), netns'ов, gateway-anchor'ы (`169.254.x.y`), id контейнеров на хостах, содержимое eBPF-/conntrack-map'ов, статусы программирования ядра.
- **числовой data-plane-идентификатор** ресурса (напр. `vpn_id` у Network) — это инфра-инфа, она на **internal-вью** ресурса, не на публичном.

**Публичная поверхность** ресурса показывает только tenant-facing «намерение + результат»: id ресурса, name/labels, привязки (folder/network/subnet/instance), выделенный tenant-адрес(а), `status`. Всё «как это разложено по железу» — только через `Internal*`-методы, которыми пользуются control-plane-компоненты (impl-controller/impl-agent), admin-UI, тулинг.

**Следствия для дизайна ресурсов**: ресурс может иметь ДВЕ проекции — публичную (lean, tenant-facing) и internal (full, с инфра-полями). Напр.: `Network` — публично {id,name,folder,…}, internal — +`vpn_id`; `NetworkInterface` — публично {id, instance_id, subnet_id, primary_v4_address, status}, internal — +{`vpn_id`-resolved, `hv_id`(placement!), `sid`/`sid_seq`, `host_iface`, `netns`, `gateway_ip`, `container_id`}; `Hypervisor` — internal целиком. Реализация — поле с пометкой «internal-only, не заполняется в публичных ответах» либо отдельный internal-message; концептуально — недоступно публично. (Это шире и строже, чем «Запреты» #6 про admin-методы — там про *методы*, тут про *данные*.)

> Почему: defense-in-depth — даже если публичный API скомпрометирован (или tenant имеет read к своим ресурсам), он не должен узнать физическую топологию / placement / SID-схему — это разведка для lateral movement и таргетинга; tenant сети A не должен мочь вывести «мой инстанс и инстанс tenant'а B на одном железе».

## Кросс-доменные ссылки на ресурсы (owner-сервис / consumer-сервис) — регламент

Когда сервису нужно сослаться на ресурс, которым он **не владеет** (его домен — другой сервис:
VPC-подсеть ссылается на `Zone` из Compute; VPC-сеть / Compute-инстанс ссылается на `Folder` из
resource-manager; NLB ссылается на `Subnet` из VPC) — действует единый базовый флоу:

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
   - **Organization / Cloud / Folder** → `kacho-resource-manager`.
   - **Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / PrivateEndpoint / NetworkInterface** → `kacho-vpc`.
   - **Instance / Disk / Image / Snapshot / DiskType / Hypervisor** → `kacho-compute`.
   - **NetworkLoadBalancer / TargetGroup** → `kacho-loadbalancer`.
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
   (proxy зон) — заменяется на `kacho-vpc → kacho-compute` (валидация `zone_id`); `kacho-resource-manager` —
   leaf-owner (Folder): в него только звонят, он сам — никуда.

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

Если домен требует узкоспециализированной экспертизы (verbatim-parity, специфические инварианты, regression-tooling) — создавай агентов **в самом сервисном репо**, не в workspace. Эталонный пример — `kacho-vpc/.claude/agents/` + `.claude/skills/`:
- `vpc-yc-parity-auditor` — аудит verbatim YC parity (regex, error texts, status codes, timestamp). **На паузе** — verbatim-parity отложена (см. «Что это за проект»).
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
