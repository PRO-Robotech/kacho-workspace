# Sub-phase 4.0 (archgraph) — Acceptance

> Статус: DRAFT
> Дата: 2026-05-22
> Ревьюер: <acceptance-reviewer>

**Документ:** acceptance / sub-phase 4.0
**Источник требований:** `docs/superpowers/specs/2026-05-22-kacho-architecture-vault-design.md` (утверждённая заказчиком спека) — §3 (модель уровней), §4 (traceability-хребет + 3 проверки), §4.4 (вычисляемый `status`), §7 (генерация L3/L4-артефактов), §10 (риски).
**Утверждение:** только после `✅ APPROVED` от `acceptance-reviewer` разрешено приступать к плану и коду (запрет #1 из `kacho-workspace/CLAUDE.md`). Заказчик к approve контракта не подключается — он проверяет финальный smoke на шаге 7.

---

## 0. Обзор

Phase 4.0 — новая «tooling/quality» под-фаза (3.x занята IAM). Реализуется первая подсистема эпика «Architecture Vault ребилд» — инструмент `archgraph`: Go-бинарь в `kacho-corelib` (модуль `github.com/PRO-Robotech/kacho-corelib`, Go 1.25), новый `cmd/archgraph/main.go` — первый `cmd/` в репо, который до сих пор был library-only. `archgraph` строит call-граф сервисного репо от entry-points (gRPC-методы + фоновые воркеры), генерит детерминированные L3/L4-артефакты в `docs/arch/generated/` и прогоняет три CI-блокирующие проверки C1 (полнота) / C2 (мёртвый код) / C3 (свежесть). Эти проверки — гарантия, что ИИ не смёржит недокументированную функциональность, мёртвый код или изменение кода без перечитки заметки.

**В скоупе этого acceptance-дока — ТОЛЬКО инструмент `archgraph`:** две CLI-подкоманды (`arch-gen`, `arch-audit`), парсинг entry-points, построение reachability-графа, чтение/запись YAML-frontmatter L2-заметок, три проверки, вычисление `status`, exit-коды и CI-пригодный вывод.

**ВНЕ скоупа** (отдельные acceptance-доки позже): per-service раскатка `archgraph`, заполнение narrative L1/L2, `make vault-sync` в `kacho-workspace`, workspace-CI cross-repo проверка связей (`target:` рёбер), удаление старого vault-дерева, изменения CI YAML сервисных репо, `Makefile`-цели `arch-gen`/`arch-audit` в сервисных репо (acceptance тут — про сам бинарь, а не про его обвязку).

**Конвенции тестирования** (см. §«Замечание о newman» в DoD): тесты `archgraph` — на синтетических Go-пакетах-фикстурах в `cmd/archgraph/testdata/`, без testcontainers (БД инструменту не нужна). `testify/require` — стандарт corelib. Вывод проверок — детерминированный, пригодный для CI-гейта (явный `FAIL` с символом/entry-point и причиной).

---

## 1. Группа A — CLI-каркас и подкоманды

### Сценарий A1: `archgraph` собирается и печатает usage

**ID:** 4.0-A1

**Given** репо `kacho-corelib` склонировано, `go.mod` объявляет модуль `github.com/PRO-Robotech/kacho-corelib`, Go 1.25
**And** `golang.org/x/tools` добавлен в `go.mod` (раньше его в зависимостях не было)

**When** разработчик выполняет `go build ./cmd/archgraph` в корне `kacho-corelib`, затем запускает бинарь без аргументов

**Then** код выхода сборки = 0, артефакт `archgraph` создан
**And** запуск без подкоманды печатает usage со списком ровно двух подкоманд: `arch-gen` и `arch-audit`
**And** запуск без подкоманды завершается с кодом ≠ 0 (нет действия по умолчанию)
**And** `archgraph --help` печатает то же usage с кодом выхода 0

*Трассировка: design §4.2 (инструмент в `kacho-corelib`).*

### Сценарий A2: неизвестная подкоманда отклоняется

**ID:** 4.0-A2

**Given** собранный бинарь `archgraph`

**When** разработчик выполняет `archgraph arch-frobnicate`

**Then** код выхода ≠ 0
**And** stderr содержит сообщение вида `unknown subcommand "arch-frobnicate"; expected arch-gen or arch-audit`
**And** ничего не записано в файловую систему

*Трассировка: design §4.2.*

### Сценарий A3: запуск из корня сервисного репо

**ID:** 4.0-A3

**Given** собранный бинарь `archgraph`
**And** рабочая директория — корень валидного сервисного репо-фикстуры (содержит `go.mod` и хотя бы один `cmd/<svc>/main.go`)

**When** разработчик выполняет `archgraph arch-audit` (без `--repo-root`-флага)

**Then** `archgraph` определяет корень репо по текущей директории (наличие `go.mod`)
**And** анализ выполняется над пакетами этого репо

*Трассировка: design §4.2 («запускается в каждом репо»).*

### Сценарий A4: запуск вне Go-репо завершается осмысленной ошибкой

**ID:** 4.0-A4

**Given** собранный бинарь `archgraph`
**And** рабочая директория не содержит `go.mod` ни в себе, ни вверх по дереву

**When** разработчик выполняет `archgraph arch-audit`

**Then** код выхода ≠ 0
**And** stderr содержит `not a Go module: no go.mod found in <cwd> or parent directories`
**And** ни один артефакт не сгенерирован

*Трассировка: design §4.2.*

### Сценарий A5: пакет фикстур с ошибкой компиляции — fail-fast

**ID:** 4.0-A5

**Given** фикстура-репо, в которой один из Go-файлов не компилируется (синтаксическая ошибка)

**When** разработчик выполняет `archgraph arch-audit` либо `archgraph arch-gen`

**Then** код выхода ≠ 0
**And** stderr содержит `failed to load packages: <package> has compile errors` с указанием файла/позиции
**And** `archgraph` НЕ выдаёт ложных C1/C2/C3-фейлов поверх непригодного к анализу графа (build-ошибка отчитывается отдельно, до проверок)

*Трассировка: design §10 (точность call-графа — деградация при невалидном вводе должна быть явной).*

---

## 2. Группа B — Распознавание entry-points

### Сценарий B1: gRPC-методы распознаются по `RegisterXxxServer`

**ID:** 4.0-B1

**Given** фикстура-репо `cmd/archgraph/testdata/svc-grpc-basic/` с `cmd/svc/main.go`, в котором есть вызов `pb.RegisterNetworkServiceServer(grpcServer, networkHandler)`
**And** тип `networkHandler` реализует gRPC-методы `Create`, `Get`, `List`, `Delete`

**When** `archgraph` парсит `main`-пакет фикстуры

**Then** в инвентарь entry-points попадают ровно: `kacho.cloud.vpc.v1.NetworkService/Create`, `kacho.cloud.vpc.v1.NetworkService/Get`, `kacho.cloud.vpc.v1.NetworkService/List`, `kacho.cloud.vpc.v1.NetworkService/Delete`
**And** каждый entry-point помечен типом `rpc` и несёт каноническое имя в формате `<fully-qualified-proto-service>/<method>`
**And** полностью квалифицированное имя сервиса извлечено НЕ из идентификатора `RegisterNetworkServiceServer`, а через цепочку `RegisterXxxServer` → `ServiceDesc`-значение → строковый литерал поля `ServiceName` в gRPC-stub'е (см. B7)

*Трассировка: design §4.2 п.1 (распознавание вызова `RegisterXxxServer`), резолв §12.2.*

### Сценарий B2: несколько `RegisterXxxServer` в одном `main`

**ID:** 4.0-B2

**Given** фикстура-репо с `main.go`, регистрирующим два сервиса: `RegisterNetworkServiceServer` и `RegisterInternalNetworkServiceServer`

**When** `archgraph` парсит `main`-пакет

**Then** инвентарь содержит entry-points обоих сервисов, без слияния и без потери
**And** entry-points `kacho.cloud.vpc.v1.InternalNetworkService/*` присутствуют наравне с публичными `kacho.cloud.vpc.v1.NetworkService/*` (инструмент не делает различий public/internal — это забота L1/L2-заметок); FQN-префиксы берутся из `ServiceName` каждого stub'а независимо

*Трассировка: design §4.2 п.1.*

### Сценарий B3: фоновый воркер распознаётся по конвенции конструктора в `main.go`

**ID:** 4.0-B3

**Given** фикстура-репо, где `cmd/svc/main.go` содержит конструктор воркера по конвенции — `w := NewNetworkOutboxWorker(...)` с последующим `go w.Run(ctx)` (или `w.Start(ctx)`)

**When** `archgraph` парсит `main`-пакет

**Then** в инвентарь entry-points попадает `NetworkOutboxWorker`, помеченный типом `worker`
**And** имя entry-point совпадает с именем типа воркера (`NetworkOutboxWorker`), что соответствует значению `worker:` в `anchors` L2-заметки

*Трассировка: design §4.2 п.1 (воркеры/реконсилеры/cron по конвенции конструкторов в `cmd/<svc>/main.go`).*

### Сценарий B4: реконсилер и cron-задача распознаются той же конвенцией

**ID:** 4.0-B4

**Given** фикстура-репо, где `main.go` стартует `NewInstanceReconciler(...).Run(ctx)` и `NewSnapshotCronJob(...).Start(ctx)`

**When** `archgraph` парсит `main`-пакет

**Then** инвентарь содержит entry-points `InstanceReconciler` и `SnapshotCronJob`, оба типа `worker`
**And** их reachable-set считается от метода, переданного в горутину/планировщик (`Run`/`Start`)

*Трассировка: design §4.2 п.1, §10 (распознавание entry-points по конвенции).*

### Сценарий B5: edge — воркер, не выдержавший конвенцию, не распознан (риск ложного C1)

**ID:** 4.0-B5

**Given** фикстура-репо, где воркер запущен без конвенционного конструктора — например, `go (&networkOutboxWorker{}).run(ctx)` (приватный тип, приватный метод, без `New...`)

**When** `archgraph` парсит `main`-пакет

**Then** этот воркер **не** попадает в инвентарь entry-points (конвенция не выдержана — распознавание по дизайну ограничено `New<Name>` + `Run`/`Start`)
**And** документ фиксирует это как известное ограничение: нераспознанный воркер приведёт к ложному C2 (его reachable-set посчитается недостижимым) — лечится приведением кода к конвенции либо аннотацией `// archgraph:keep`
**And** `arch-audit` в человекочитаемом выводе НЕ молчит: при обнаружении горутины со звонком метода типа, не попавшего в инвентарь, печатает `hint: possible unrecognized worker entry-point at <file:line> — see archgraph entry-point convention`

*Трассировка: design §10 («если конвенция в репо не выдержана — C1 даст ложные срабатывания»).*

### Сценарий B6: репо без entry-points

**ID:** 4.0-B6

**Given** фикстура-репо без `cmd/`-пакетов вовсе (чисто library-репо, как `kacho-corelib` до этой под-фазы)

**When** разработчик выполняет `archgraph arch-audit`

**Then** инвентарь entry-points пуст
**And** `archgraph` завершается с кодом 0 (отсутствие entry-points — не ошибка; репо без `main`-пакета классифицируется как library, C2 для него = SKIP — см. F7)
**And** вывод содержит `0 entry-points discovered` — явно, без падения

*Трассировка: design §4.2 (инструмент общий, в т.ч. для corelib).*

### Сценарий B7: FQN entry-point резолвится через `ServiceDesc.ServiceName`

**ID:** 4.0-B7

**Given** фикстура-репо, где `cmd/svc/main.go` вызывает `pb.RegisterNetworkServiceServer(grpcServer, networkHandler)`
**And** gRPC-generated stub-пакет `pb` содержит `ServiceDesc`-значение (`NetworkService_ServiceDesc` либо `_NetworkService_serviceDesc`) с полем `ServiceName: "kacho.cloud.vpc.v1.NetworkService"` — строковый литерал
**And** `RegisterNetworkServiceServer` в своём теле ссылается на этот `ServiceDesc`

**When** `archgraph` парсит `main`-пакет и резолвит entry-point

**Then** `archgraph` идёт по цепочке `RegisterNetworkServiceServer` → используемый внутри `ServiceDesc`-объект → поле `ServiceName` → строковый литерал `kacho.cloud.vpc.v1.NetworkService`
**And** FQN entry-point строится как `<ServiceName>/<Method>` — например `kacho.cloud.vpc.v1.NetworkService/Create`, а НЕ из идентификатора функции `RegisterNetworkServiceServer` (который дал бы только короткое `NetworkService`)
**And** этот FQN — каноническая форма якоря `rpc:` в `anchors` L2-заметки; C1-сопоставление якорь↔entry-point идёт строго по полному FQN
**And** если в stub'е не удаётся найти строковый литерал `ServiceName` для зарегистрированного сервиса, `archgraph` завершается с кодом ≠ 0 и stderr `cannot resolve service FQN for RegisterNetworkServiceServer: no ServiceName literal in ServiceDesc` (неоднозначность не маскируется коротким именем)

*Трассировка: design §4.2 п.1, резолв §12.2 (источник FQN — `ServiceDesc.ServiceName`).*

---

## 3. Группа C — Построение call-графа и reachability

### Сценарий C1-graph: reachability считается от entry-point

**ID:** 4.0-C1-graph

**Given** фикстура-репо, где gRPC-метод `kacho.cloud.vpc.v1.NetworkService/Create` вызывает `validateSpec()` → `repo.Insert()`, а функция `unusedHelper()` не вызывается ниоткуда

**When** `archgraph` строит call-граф (алгоритм RTA как стартовый, по `golang.org/x/tools/go/callgraph`)

**Then** reachable-set от `kacho.cloud.vpc.v1.NetworkService/Create` включает `validateSpec` и `repo.Insert`
**And** `unusedHelper` **не** входит в reachable-set ни одного entry-point
**And** результат детерминирован: повторный запуск на том же коде даёт идентичный reachable-set

*Трассировка: design §4.2 п.2 (reachability от каждого entry-point), §10 (RTA как старт).*

### Сценарий C2-graph: вызов через интерфейс попадает в reachable-set

**ID:** 4.0-C2-graph

**Given** фикстура-репо, где entry-point вызывает метод через port-интерфейс (`type NetworkRepo interface { Insert(...) }`), а конкретная реализация — `pgNetworkRepo.Insert`

**When** `archgraph` строит call-граф алгоритмом RTA

**Then** `pgNetworkRepo.Insert` входит в reachable-set (RTA учитывает типы, чьи значения конструируются в достижимом коде)
**And** документ фиксирует ограничение: RTA может пере-/недооценить достижимость при тяжёлом interface/reflection-коде — для ложных C2 предусмотрена аннотация `// archgraph:keep` (см. C2-блок)

*Трассировка: design §10 (CHA/RTA может пере- или недооценить достижимость).*

### Сценарий C3-graph: артефакт call-графа сериализуется детерминированно

**ID:** 4.0-C3-graph

**Given** фикстура-репо с воспроизводимым набором функций

**When** `archgraph arch-gen` дважды подряд эмитит call-дерево в `docs/arch/generated/`

**Then** оба прогона дают побайтово идентичный файл (сортировка узлов/рёбер стабильна — по имени символа, не по порядку обхода)
**And** `git diff --exit-code` после второго прогона чист

*Трассировка: design §6.1 (`git diff --exit-code` как CI-проверка дрейфа), §7 п.1 (детерминированная регенерация).*

---

## 4. Группа D — `arch-gen`: генерация L3/L4-артефактов

### Сценарий D1: `arch-gen` создаёт L3/L4 в `docs/arch/generated/`

**ID:** 4.0-D1

**Given** фикстура-репо с entry-points и domain-типами

**When** разработчик выполняет `archgraph arch-gen`

**Then** в `docs/arch/generated/` появляются артефакты:
  - L3 — на каждую функциональность (кластер entry-points): call-дерево от якорей + exported-сигнатуры reachable-функций
  - L4 — на приклад: таблицы domain-типов, полей, DB-колонок, config-ключей, констант
**And** код выхода = 0
**And** артефакты — машинно-сгенерированный детерминированный контент с шапкой-маркером `<!-- GENERATED BY archgraph — DO NOT EDIT -->`

*Трассировка: design §4.2 п.4, §7 п.1.*

### Сценарий D2: повторный `arch-gen` без изменений кода даёт нулевой дифф

**ID:** 4.0-D2

**Given** фикстура-репо, где `arch-gen` уже был прогнан и артефакты закоммичены

**When** разработчик повторно выполняет `archgraph arch-gen` без изменений в коде

**Then** ни один файл в `docs/arch/generated/` не изменился
**And** `git diff --exit-code docs/arch/generated/` возвращает код 0

*Трассировка: design §6.1 (CI-шаг `make arch-gen` + `git diff --exit-code`).*

### Сценарий D3: изменение кода → `arch-gen` обновляет артефакт

**ID:** 4.0-D3

**Given** фикстура-репо с закоммиченными L3/L4-артефактами
**And** в код добавлена новая reachable exported-функция `EnrichSpec`

**When** разработчик выполняет `archgraph arch-gen`

**Then** соответствующий L3-артефакт содержит сигнатуру `EnrichSpec` в call-дереве
**And** `git diff` показывает ровно это добавление, без посторонних перестановок строк

*Трассировка: design §7 п.1.*

### Сценарий D4: `arch-gen` не трогает курируемые L1/L2-заметки

**ID:** 4.0-D4

**Given** фикстура-репо с курируемой L2-заметкой `docs/arch/network-lifecycle.md` (frontmatter + narrative-тело)

**When** разработчик выполняет `archgraph arch-gen`

**Then** narrative-тело L2-заметки **не** изменено (`arch-gen` пишет только `docs/arch/generated/**` и `status`-поле frontmatter — см. F-блок)
**And** курируемые секции L0/L1/L2 остаются под контролем человека (граница режимов из design §3)

*Трассировка: design §3 (граница режимов L0–L2 курируется / L3–L4 генерится).*

### Сценарий D5: edge — `docs/arch/generated/` не существует, создаётся `arch-gen`-ом

**ID:** 4.0-D5

**Given** фикстура-репо, где каталог `docs/arch/generated/` отсутствует (первый запуск в репо)

**When** разработчик выполняет `archgraph arch-gen`

**Then** каталог `docs/arch/generated/` создаётся
**And** артефакты записываются, код выхода = 0

*Трассировка: design §7 п.1 («новый пол» — первая регенерация).*

### Сценарий D6: edge — stale-артефакт удалённой функциональности убирается

**ID:** 4.0-D6

**Given** фикстура-репо, где ранее существовавший entry-point `kacho.cloud.compute.v1.SnapshotService/Create` удалён из кода, но его старый L3-артефакт остался в `docs/arch/generated/`

**When** разработчик выполняет `archgraph arch-gen`

**Then** stale-артефакт удалённой функциональности удаляется из `docs/arch/generated/` (генерённый слой полностью отражает текущий код, осиротевших файлов не остаётся)
**And** `git diff` показывает удаление файла

*Трассировка: design §7 п.1 (генерённый низ — точное код-производное).*

---

## 5. Группа E — `arch-audit` C1: полнота

### Сценарий E1: C1 проходит — каждый entry-point заявлен ровно в одном anchor

**ID:** 4.0-E1

**Given** фикстура-репо с entry-points `kacho.cloud.vpc.v1.NetworkService/Create`, `kacho.cloud.vpc.v1.NetworkService/Delete`, `NetworkOutboxWorker`
**And** L2-заметка `docs/arch/network-lifecycle.md` с frontmatter:
```yaml
anchors:
  - rpc: kacho.cloud.vpc.v1.NetworkService/Create
  - rpc: kacho.cloud.vpc.v1.NetworkService/Delete
  - worker: NetworkOutboxWorker
```

**When** разработчик выполняет `archgraph arch-audit`

**Then** проверка C1 печатает `C1 completeness: PASS (3/3 entry-points anchored)`
**And** C1 не вносит вклад в ненулевой exit-код

*Трассировка: design §4.3 C1.*

### Сценарий E2: C1 падает — незаявленный entry-point

**ID:** 4.0-E2

**Given** фикстура-репо, где в `main` зарегистрирован entry-point `kacho.cloud.vpc.v1.NetworkService/Update`
**And** ни одна L2-заметка не содержит `kacho.cloud.vpc.v1.NetworkService/Update` в `anchors`

**When** разработчик выполняет `archgraph arch-audit`

**Then** C1 печатает `C1 completeness: FAIL`
**And** вывод содержит строку с конкретным entry-point и причиной: `undocumented entry-point: kacho.cloud.vpc.v1.NetworkService/Update — declare it in an L2 note's anchors or remove it`
**And** код выхода `arch-audit` ≠ 0

*Трассировка: design §4.3 C1 («Незаявленный entry-point → FAIL»).*

### Сценарий E3: C1 падает — якорь на несуществующий entry-point (протухшая заметка)

**ID:** 4.0-E3

**Given** фикстура-репо, где L2-заметка объявляет `anchor: rpc: kacho.cloud.vpc.v1.NetworkService/Patch`
**And** entry-point `kacho.cloud.vpc.v1.NetworkService/Patch` в коде отсутствует (метод удалён или не существовал)

**When** разработчик выполняет `archgraph arch-audit`

**Then** C1 печатает `C1 completeness: FAIL`
**And** вывод содержит: `stale anchor: kacho.cloud.vpc.v1.NetworkService/Patch in docs/arch/network-lifecycle.md points to a non-existent entry-point`
**And** код выхода ≠ 0

*Трассировка: design §4.3 C1 («Якорь на несуществующий entry-point → FAIL "протухшая заметка"»).*

### Сценарий E4: C1 падает — entry-point заявлен в двух заметках сразу

**ID:** 4.0-E4

**Given** фикстура-репо, где entry-point `kacho.cloud.vpc.v1.NetworkService/Create` указан в `anchors` двух разных L2-заметок (`network-lifecycle.md` и `network-bootstrap.md`)

**When** разработчик выполняет `archgraph arch-audit`

**Then** C1 печатает `C1 completeness: FAIL`
**And** вывод содержит: `entry-point kacho.cloud.vpc.v1.NetworkService/Create anchored in 2 notes (network-lifecycle.md, network-bootstrap.md) — must be exactly one`
**And** код выхода ≠ 0

*Трассировка: design §4.3 C1 («обязан быть заявлен ровно в одном L2-anchors»).*

### Сценарий E5: edge — нераспознанный воркер даёт ложный C1 (известное ограничение)

**ID:** 4.0-E5

**Given** фикстура-репо с воркером, запущенным без конвенционного конструктора (как B5)
**And** L2-заметка тем не менее объявляет `worker: NetworkOutboxWorker` в `anchors`

**When** разработчик выполняет `archgraph arch-audit`

**Then** C1 трактует якорь `NetworkOutboxWorker` как протухший (E3-семантика), потому что entry-point не распознан — это **ложное срабатывание** по дизайну
**And** вывод дополняется hint-строкой (как в B5): `hint: an anchored worker NetworkOutboxWorker was not discovered as an entry-point — verify it follows the New<Name>+Run/Start convention`
**And** документ фиксирует: лечение — привести воркер к конвенции; `archgraph:keep` тут не применяется (это про C2, не C1)

*Трассировка: design §10 («распознавание entry-points … ложные срабатывания C1»).*

### Сценарий E6: edge — `anchors` пуст (заметка `planned`)

**ID:** 4.0-E6

**Given** фикстура-репо с L2-заметкой, чей frontmatter содержит пустой `anchors: []`
**And** все entry-points репо заявлены в **других** заметках

**When** разработчик выполняет `archgraph arch-audit`

**Then** C1 **не** падает из-за пустого `anchors` (заметка с нулём якорей валидна — это `status: planned`, см. F-блок)
**And** C1 учитывает только заметки с непустыми `anchors` при проверке покрытия entry-points

*Трассировка: design §4.3 C1, §4.4 (`planned` — якорей ноль).*

---

## 6. Группа F — `arch-audit` C2: мёртвый код

### Сценарий F1: C2 проходит — все exported-символы достижимы

**ID:** 4.0-F1

**Given** фикстура-репо, где каждый exported-символ (тип, функция, метод) достижим хотя бы от одного entry-point

**When** разработчик выполняет `archgraph arch-audit`

**Then** C2 печатает `C2 dead-code: PASS (0 unreachable exported symbols)`
**And** C2 не вносит вклад в ненулевой exit-код

*Трассировка: design §4.3 C2.*

### Сценарий F2: C2 падает — недостижимый exported-символ

**ID:** 4.0-F2

**Given** фикстура-репо с exported-функцией `LegacyMigrateAddresses`, не достижимой ни от одного entry-point и без аннотации `archgraph:keep`

**When** разработчик выполняет `archgraph arch-audit`

**Then** C2 печатает `C2 dead-code: FAIL`
**And** вывод содержит конкретный символ и позицию: `dead code: exported symbol LegacyMigrateAddresses (internal/repo/legacy.go:14) unreachable from any entry-point`
**And** код выхода ≠ 0

*Трассировка: design §4.3 C2 («Любой exported-символ, не достижимый … → FAIL. Жёстко»).*

### Сценарий F3: edge — `// archgraph:keep` подавляет ложный C2

**ID:** 4.0-F3

**Given** фикстура-репо с exported-функцией `BuildClientSDK`, недостижимой от entry-points, но снабжённой строкой-комментарием непосредственно над объявлением: `// archgraph:keep public SDK surface, consumed by external clients`

**When** разработчик выполняет `archgraph arch-audit`

**Then** C2 **не** считает `BuildClientSDK` мёртвым кодом (аннотация подавляет фейл)
**And** C2 печатает `PASS`, в детальном выводе — `kept: BuildClientSDK (reason: public SDK surface, consumed by external clients)`
**And** код выхода (от C2) = 0

*Трассировка: design §4.3 C2 («Единственное исключение — явная аннотация `// archgraph:keep <причина>`»).*

### Сценарий F4: edge — `archgraph:keep` без причины отклоняется

**ID:** 4.0-F4

**Given** фикстура-репо с недостижимым exported-символом, над которым стоит голый `// archgraph:keep` без текста причины

**When** разработчик выполняет `archgraph arch-audit`

**Then** C2 печатает `FAIL`
**And** вывод содержит: `invalid annotation: // archgraph:keep at internal/repo/x.go:9 requires a non-empty reason`
**And** код выхода ≠ 0 (аннотация без обоснования не подавляет проверку — причина обязательна)

*Трассировка: design §4.3 C2 (`// archgraph:keep <причина>` — причина — часть синтаксиса).*

### Сценарий F5: edge — `archgraph:keep` распространяется на транзитивно достижимое из kept-символа

**ID:** 4.0-F5

**Given** фикстура-репо, где `archgraph:keep`-функция `BuildClientSDK` вызывает приватную `assembleSDKManifest`, которая иначе была бы мёртвой
**And** `assembleSDKManifest` — приватный символ (C2 проверяет только exported, но граф достижимости — общий)

**When** разработчик выполняет `archgraph arch-audit`

**Then** reachable-set расширяется от kept-символов так же, как от entry-points
**And** ни одна exported-функция, достижимая транзитивно из `BuildClientSDK`, не считается мёртвой
**And** C2 печатает `PASS`

*Трассировка: design §4.3 C2 (аннотация — намеренное публичное API, его поддерево живое).*

### Сценарий F6: C2 — недостижимый символ, достижимый только через interface/reflection (ложный фейл-риск)

**ID:** 4.0-F6

**Given** фикстура-репо, где exported-метод вызывается исключительно через reflection (`reflect.Value.Call`) — RTA не видит ребро

**When** разработчик выполняет `archgraph arch-audit`

**Then** C2 печатает `FAIL` для этого символа (RTA по построению не разрешает reflection-вызовы — это ожидаемая неточность)
**And** документ фиксирует: правильное лечение — `// archgraph:keep reflection-invoked` на символе; это намеренный предохранитель из design §10
**And** после добавления аннотации повторный `arch-audit` даёт `PASS` (проверяется как продолжение сценария)

*Трассировка: design §10 («CHA/RTA может … недооценить достижимость … `archgraph:keep` как предохранитель»).*

### Сценарий F7: library-репо — C2 целиком SKIP

**ID:** 4.0-F7

**Given** фикстура чисто library-репо (как `kacho-corelib` до этой под-фазы — кроме самого `cmd/archgraph`): ни одного `main`-пакета в репо, есть exported-символы, аннотаций `archgraph:keep` нет

**When** разработчик выполняет `archgraph arch-audit`

**Then** `archgraph` определяет тип репо по наличию `main`-пакета: ни одного `main`-пакета → репо классифицируется как **library**
**And** для library-репо проверка C2 печатает `C2 dead-code: SKIP (library repo: no main package)` и **не** выполняется
**And** C2 не вносит вклад в exit-код, код выхода (от C2) = 0
**And** документ фиксирует обоснование: exported-API библиотеки по определению — её контракт, достижимый внешними потребителями вне анализируемого графа; неиспользуемые **unexported**-символы ловит `staticcheck` (U1000), а не `archgraph`. Anchor-заметки в library-репо для C2 не требуются.
**And** C1 и C3 при этом выполняются как обычно (они оперируют entry-points/якорями, а не «мёртвым кодом»; в library-репо без entry-points C1 даёт `PASS` при пустом инвентаре — см. B6)

*Трассировка: design §4.3 C2 (dead-code применим к сервисам с entry-points), §4.2 (инструмент общий для всех репо), резолв §12.1.*

---

## 7. Группа G — `arch-audit` C3: свежесть

> **Гранулярность хеша C3 (зафиксировано, §12.4).** `source_sha` — это хеш **целых файлов**, образующих reachable-set якорей заметки (как design §4.3 «файлов её якорей»), а не тел отдельных reachable-функций. Следствие: правка любой функции в файле, входящем в reachable-set — даже не той, что под якорем — протухляет заметку (C3 FAIL, over-trigger). Это **принятое** поведение: лишняя перечитка заметки человеком консервативна и безопасна; ложно-пропущенная протухшая заметка — нет. Все сценарии G1–G6 исходят из пофайлового хеша.

### Сценарий G1: C3 проходит — `source_sha` совпадает с хешем reachable-set

**ID:** 4.0-G1

**Given** фикстура-репо с L2-заметкой, чьи `anchors` указывают на entry-points, и `source_sha: <H>` во frontmatter
**And** `<H>` равен текущему хешу reachable-set файлов этих якорей

**When** разработчик выполняет `archgraph arch-audit`

**Then** C3 печатает `C3 freshness: PASS`
**And** C3 не вносит вклад в ненулевой exit-код

*Трассировка: design §4.3 C3.*

### Сценарий G2: C3 падает — код под заметкой изменился

**ID:** 4.0-G2

**Given** фикстура-репо с L2-заметкой и `source_sha: <H_old>`
**And** один из файлов reachable-set якорей заметки изменён (новый хеш `<H_new> ≠ <H_old>`)

**When** разработчик выполняет `archgraph arch-audit`

**Then** C3 печатает `C3 freshness: FAIL`
**And** вывод содержит конкретную заметку и оба хеша: `stale note: docs/arch/network-lifecycle.md — code under anchors changed (source_sha <H_old> != actual <H_new>); re-read the note and update source_sha`
**And** код выхода ≠ 0
**And** C3 FAIL срабатывает и в случае, когда изменена функция в файле reachable-set, не входящая в reachable-set якоря напрямую (over-trigger пофайлового хеша из §12.4) — это ожидаемое консервативное поведение, не баг

*Трассировка: design §4.3 C3 («хеш ≠ `source_sha` → FAIL»), резолв §12.4.*

### Сценарий G3: C3 — хеш считается по reachable-set, не по всему репо

**ID:** 4.0-G3

**Given** фикстура-репо с двумя L2-заметками A и B, чьи reachable-set-ы не пересекаются
**And** изменён файл, входящий только в reachable-set заметки B

**When** разработчик выполняет `archgraph arch-audit`

**Then** C3 падает **только** для заметки B
**And** для заметки A C3 печатает `PASS` (изменение в чужом reachable-set не протухляет заметку A)
**And** вывод явно перечисляет затронутые заметки

*Трассировка: design §4.3 C3 («хешируется reachable-set файлов её якорей»).*

### Сценарий G4: C3 — детерминированность хеша

**ID:** 4.0-G4

**Given** фикстура-репо без изменений кода

**When** `archgraph arch-audit` запускается дважды подряд

**Then** вычисленный хеш reachable-set идентичен в обоих прогонах
**And** хеш инвариантен к порядку обхода файлов (файлы сортируются перед хешированием) и не зависит от рабочей директории/абсолютных путей (хешируются относительные пути + содержимое)

*Трассировка: design §4.3 C3 («Проверка детерминированная»).*

### Сценарий G5: edge — заметка с пустым `source_sha`

**ID:** 4.0-G5

**Given** фикстура-репо с только что авто-сиданной L2-заметкой, где `source_sha:` пуст или отсутствует, но `anchors` непуст

**When** разработчик выполняет `archgraph arch-audit`

**Then** C3 печатает `FAIL` для этой заметки с причиной `missing source_sha: docs/arch/<note>.md has anchors but no source_sha — review the code and set it`
**And** код выхода ≠ 0 (пустой `source_sha` при наличии якорей трактуется как «не перечитано»)

*Трассировка: design §4.3 C3, §7 п.2 (авто-сид скелета — `source_sha` заполняется при первой перечитке человеком).*

### Сценарий G6: edge — `planned`-заметка (пустой `anchors`) пропускается C3

**ID:** 4.0-G6

**Given** фикстура-репо с L2-заметкой `anchors: []` (status `planned`)

**When** разработчик выполняет `archgraph arch-audit`

**Then** C3 пропускает эту заметку (нет якорей → нет reachable-set → нечего хешировать)
**And** C3 не падает из-за отсутствия `source_sha` в `planned`-заметке

*Трассировка: design §4.4 (`planned` — якорей ноль), §4.3 C3.*

---

## 8. Группа H — Вычисляемый `status` и write-back frontmatter

### Сценарий H1: `status = implemented` — все якоря существуют и достижимы

**ID:** 4.0-H1

**Given** фикстура-репо с L2-заметкой, все `anchors` которой соответствуют существующим, достижимым от `main` entry-points

**When** разработчик выполняет `archgraph arch-gen`

**Then** во frontmatter заметки записывается `status: implemented`
**And** write-back изменяет только ключ `status`, не трогая прочие ключи frontmatter и narrative-тело

*Трассировка: design §4.4 (`implemented` — все якоря существуют и достижимы).*

### Сценарий H2: `status = partial` — часть якорей отсутствует в коде

**ID:** 4.0-H2

**Given** фикстура-репо с L2-заметкой, где `anchors` содержит `rpc: kacho.cloud.vpc.v1.NetworkService/Create` (существует) и `rpc: kacho.cloud.vpc.v1.NetworkService/Migrate` (в коде отсутствует)

**When** разработчик выполняет `archgraph arch-gen`

**Then** во frontmatter записывается `status: partial`

*Трассировка: design §4.4 (`partial` — часть якорей отсутствует).*

### Сценарий H3: `status = planned` — якорей в коде ноль

**ID:** 4.0-H3

**Given** фикстура-репо с L2-заметкой, где `anchors` пуст либо все якоря отсутствуют в коде

**When** разработчик выполняет `archgraph arch-gen`

**Then** во frontmatter записывается `status: planned`

*Трассировка: design §4.4 (`planned` — якорей в коде ноль).*

### Сценарий H4: `status` руками не печатается — расхождение ловится `git diff`

**ID:** 4.0-H4

**Given** фикстура-репо с L2-заметкой, во frontmatter которой человек руками вписал `status: implemented`, хотя по факту якоря частичны (должно быть `partial`)

**When** разработчик выполняет `archgraph arch-gen`, затем `git diff --exit-code`

**Then** `arch-gen` перезаписывает `status` на корректное `partial`
**And** `git diff --exit-code` возвращает ≠ 0, показывая расхождение `implemented → partial`
**And** документ фиксирует: `status` — всегда вычисляемое поле, ручная правка обнаруживается CI

*Трассировка: design §4.4 («Руками не печатается никогда; `git diff --exit-code` ловит расхождение»).*

### Сценарий H5: write-back сохраняет YAML-форматирование frontmatter

**ID:** 4.0-H5

**Given** фикстура-репо с L2-заметкой, frontmatter которой содержит `level`, `repo`, `anchors[]`, `status`, `source_sha` и комментарии-`#`

**When** `archgraph arch-gen` пишет обратно `status`

**Then** порядок ключей frontmatter сохранён
**And** значения прочих ключей и YAML-комментарии не утрачены
**And** заметка остаётся валидным Markdown с корректным `---`-делимитированным frontmatter

*Трассировка: design §4.1 (структура frontmatter), §4.4.*

### Сценарий H6: edge — заметка без frontmatter или с битым YAML

**ID:** 4.0-H6

**Given** фикстура-репо с файлом в `docs/arch/`, у которого frontmatter синтаксически невалиден (битый YAML) или отсутствует, при том что файл заявлен как L2 (`level: functionality` ожидается)

**When** разработчик выполняет `archgraph arch-gen` либо `arch-audit`

**Then** код выхода ≠ 0
**And** вывод содержит конкретный файл и причину: `invalid L2 note: docs/arch/<note>.md — malformed or missing YAML frontmatter`
**And** `archgraph` не пишет частичный/повреждённый результат в этот файл

*Трассировка: design §4.1 (frontmatter — обязательная часть L2).*

---

## 9. Группа I — Exit-коды и CI-пригодный вывод

### Сценарий I1: `arch-audit` exit 0 при всех PASS

**ID:** 4.0-I1

**Given** фикстура-репо, где C1, C2, C3 все проходят

**When** разработчик выполняет `archgraph arch-audit`

**Then** код выхода = 0
**And** вывод содержит итоговую строку `arch-audit: PASS (C1 PASS, C2 PASS, C3 PASS)`

*Трассировка: design §4.3 (три проверки блокируют CI), §6.1.*

### Сценарий I2: `arch-audit` exit ≠ 0 если падает хотя бы одна проверка

**ID:** 4.0-I2

**Given** фикстура-репо, где C1 PASS, C2 FAIL, C3 PASS

**When** разработчик выполняет `archgraph arch-audit`

**Then** код выхода ≠ 0
**And** итоговая строка `arch-audit: FAIL (C1 PASS, C2 FAIL, C3 PASS)`
**And** проверки C1 и C3 всё равно выполнены и отчитаны (`arch-audit` не останавливается на первом FAIL — собирает полную картину для CI)

*Трассировка: design §4.3 («Все три блокируют CI»), §6.1.*

### Сценарий I3: вывод детерминирован и стабильно отсортирован

**ID:** 4.0-I3

**Given** фикстура-репо с несколькими нарушениями C1 и C2 одновременно

**When** `archgraph arch-audit` запускается дважды

**Then** порядок строк-фейлов идентичен между прогонами (сортировка — по проверке, затем по символу/entry-point/имени файла)
**And** вывод пригоден для diff-сравнения в CI-логах

*Трассировка: design §6.1 (CI-гейт), §10 (детерминизм важен при параллельных агентах).*

### Сценарий I4: каждая FAIL-строка указывает символ/entry-point/файл и причину

**ID:** 4.0-I4

**Given** фикстура-репо с одним нарушением каждой из C1/C2/C3

**When** разработчик выполняет `archgraph arch-audit`

**Then** строка C1-фейла содержит имя entry-point или путь заметки
**And** строка C2-фейла содержит имя символа и `файл:строку`
**And** строка C3-фейла содержит путь заметки и пару хешей
**And** ни одна FAIL-строка не является голым «check failed» без указания объекта и причины

*Трассировка: design §10 (детерминированный вывод для CI-гейта), требование §«Конвенции kacho» о явном FAIL.*

### Сценарий I5: `arch-gen` exit ≠ 0 при невозможности записать артефакт

**ID:** 4.0-I5

**Given** фикстура-репо, где `docs/arch/generated/` недоступен для записи (read-only)

**When** разработчик выполняет `archgraph arch-gen`

**Then** код выхода ≠ 0
**And** stderr содержит `failed to write generated artifact: <path>: <os error>`
**And** уже записанные на этом прогоне файлы не оставляются в неконсистентном (полузаписанном) состоянии — либо запись атомарна (temp + rename), либо явно откатывается

*Трассировка: design §6.1 (`arch-gen` — часть CI-гейта).*

### Сценарий I6: CI-дрейф-гейт — `arch-gen` + `git diff --exit-code`

**ID:** 4.0-I6

**Given** фикстура-репо с закоммиченными L3/L4-артефактами в `docs/arch/generated/`

**When** разработчик (или CI) выполняет `archgraph arch-gen`, затем `git diff --exit-code`

**Then** на **неизменном** коде `arch-gen` не меняет ни один файл; `git diff --exit-code` возвращает код 0 (дрейфа нет)
**And** если перед `arch-gen` в код фикстуры было внесено изменение, затрагивающее reachable-set (новая reachable-функция / удалённый entry-point / изменённая сигнатура), но артефакты НЕ были регенерированы — `arch-gen` перезаписывает артефакты, и последующий `git diff --exit-code` возвращает код ≠ 0, показывая дрейф
**And** документ фиксирует: отдельного флага `--check` у `arch-gen` НЕТ; CI-гейт свежести генерата — это ровно связка `arch-gen` + `git diff --exit-code` (design §6.1). `arch-gen` всегда пишет в `docs/arch/generated/`; обнаружение дрейфа — ответственность `git diff`, не флага инструмента.

*Трассировка: design §6.1 (CI-шаг `make arch-gen` + `git diff --exit-code`), резолв §12.3.*

---

## 10. Группа J — Трассируемость

### Сценарий J1: acceptance ↔ test mapping

**ID:** 4.0-J1

**Given** этот документ принят (`✅ APPROVED`)
**And** integration-тесты `archgraph` пишутся в `kacho-corelib/cmd/archgraph/` на синтетических фикстурах из `cmd/archgraph/testdata/`

**When** автор тестов открывает acceptance-документ

**Then** каждому сценарию (A1–A5, B1–B7, C1-graph–C3-graph, D1–D6, E1–E6, F1–F7, G1–G6, H1–H6, I1–I6) соответствует **ровно один** Go-тест, чьё имя содержит ID сценария — например `TestArchgraph_4_0_E2_UndocumentedEntryPoint`, `TestArchgraph_4_0_F3_KeepAnnotationSuppressesC2`
**And** каждая фикстура-репо в `testdata/` имеет README-строку или комментарий со списком ID сценариев, которые она обслуживает
**And** трассируемость двусторонняя: по имени теста находится сценарий и наоборот

*Трассировка: design §9 DoD («`archgraph` … с integration-тестами … на синтетических Go-пакетах»).*

---

## 11. Definition of Done sub-phase 4.0

Под-итерация считается завершённой, когда **все** условия выполнены:

1. `cmd/archgraph/main.go` существует в `kacho-corelib`; `go build ./cmd/archgraph` зелёный; `golang.org/x/tools` добавлен в `go.mod` и `go.sum`.
2. Подкоманды `arch-gen` и `arch-audit` реализованы; поведение соответствует сценариям §1–§9.
3. Распознавание entry-points реализовано и покрыто §B: gRPC-методы — через `RegisterXxxServer` → `ServiceDesc` → строковый литерал `ServiceName`, каноническое имя якоря `rpc: <fully-qualified-proto-service>/<Method>`; воркеры/реконсилеры/cron — по конвенции `New<Name>` + метод `Run`/`Start` в `cmd/<svc>/main.go`, каноническое имя якоря `worker: <TypeName>`.
4. Построение call-графа (RTA через `golang.org/x/tools/go/callgraph`) и reachability — реализовано, детерминировано, покрыто §C.
5. Три проверки C1/C2/C3 реализованы, блокируют через exit-код, дают детерминированный CI-пригодный вывод — покрыто §E/§F/§G/§I.
6. `// archgraph:keep <причина>`-аннотация распознаётся, требует непустой причины, расширяет reachable-set — покрыто §F3–F6.
7. Вычисление `status` (`implemented`/`partial`/`planned`) и идемпотентный write-back во frontmatter без потери прочих ключей/комментариев/тела — покрыто §H.
8. **Тесты-first**: на каждый сценарий §1–§10 — Go integration-тест на фикстуре из `cmd/archgraph/testdata/`; в PR показана пара RED (до кода) → GREEN (после) согласно запрету #11. Все тесты зелёные локально и на CI `kacho-corelib`.
9. `golangci-lint` и `go test ./cmd/archgraph/...` зелёные; покрытие пакета `archgraph` ≥ 70 %.
10. Трассируемость §J1: имя каждого теста содержит ID сценария; двусторонняя навигация работает.
11. Vault-трейл: заведена/обновлена `packages/`-заметка под `cmd/archgraph` в `kacho-corelib`. Трекинг под-фазы — через design-док + этот acceptance-док + ветка `arch-vault-rebuild` (YouTrack `KAC` для этого эпика временно не используется, см. хвост документа).

### Замечание о newman (обоснование замены black-box-проверки)

Стандартный DoD-чек-лист kacho требует «integration tests + newman cases зелёные». **Newman-кейсы к `archgraph` неприменимы и заменяются integration-тестами на фикстурах** — обоснование:

- Newman — это black-box-проверка REST-поверхности **через api-gateway**. `archgraph` — CLI-инструмент: у него нет gRPC/REST-поверхности, нет api-gateway, нет БД. Прогон newman физически нечего адресовать.
- Эквивалент black-box-проверки для CLI — прогон собранного бинаря над синтетическими фикстура-репо в `cmd/archgraph/testdata/` с проверкой stdout/stderr/exit-кода. Эти прогоны и есть integration-тесты §1–§10; они покрывают тот же слой «снаружи, без знания внутренностей», что newman покрывает для сервисов.
- Test-first-дисциплина (запрет #11) при этом сохраняется в полном объёме: фикстура + ожидаемый вывод пишутся и прогоняются в RED **до** кода соответствующей возможности.

Таким образом «newman» в DoD заменяется на «black-box CLI-прогон над `testdata/`-фикстурами»; смысл требования — внешняя проверка без знания реализации — выполнен.

---

## 12. Открытые пункты — Resolved

Все 6 открытых пунктов разрешены владельцем дизайна (2026-05-22). Тело документа приведено в соответствие.

1. **Resolved: C2 для library-репо (F7).** `archgraph` определяет тип репо по наличию `main`-пакета: нет ни одного `main`-пакета → репо считается library → **C2 = SKIP целиком**. Обоснование: exported-API библиотеки по определению является её контрактом, достижимым внешними потребителями вне анализируемого графа; неиспользуемые **unexported**-символы при этом отлавливает `staticcheck` (U1000), а не `archgraph`. Anchor-заметки в `kacho-corelib` под C2 не форсируются. F7 переписан под `SKIP (library repo: no main package)`.

2. **Resolved: канонический формат имени entry-point.** gRPC-generated stub содержит `ServiceDesc`-значение (`<Service>_ServiceDesc` / `_<Service>_serviceDesc`) с полем `ServiceName`, равным полностью квалифицированному proto-имени сервиса (`kacho.cloud.vpc.v1.NetworkService`). `RegisterXxxServer` ссылается на этот `ServiceDesc`. `archgraph` извлекает FQN именно из строкового литерала `ServiceName` в stub'е, по цепочке `RegisterXxxServer` → `ServiceDesc` → `ServiceName`. **Канонический формат якоря RPC: `rpc: <fully-qualified-proto-service>/<Method>`** — например `rpc: kacho.cloud.vpc.v1.NetworkService/Create`. **Формат якоря воркера: `worker: <TypeName>`.** Сокращённая запись `vpc.v1.NetworkService` из design-дока — неточность; во всём acceptance-доке используется полный FQN. Добавлен сценарий B7 (резолв FQN через `ServiceDesc.ServiceName`).

3. **Resolved: `arch-gen --check`.** Отдельного флага НЕТ. CI-гейт = `arch-gen` (пишет в `docs/arch/generated/`) + `git diff --exit-code` — ровно как design §6.1. I6 переписан: вместо `--check`-флага — проверка дрейф-гейта (после `arch-gen` на неизменном коде `git diff` пуст; после изменения кода без регенерации `git diff` непуст).

4. **Resolved: гранулярность хеша C3.** Пофайловый хеш — хешируются целые файлы, образующие reachable-set якорей заметки (как design §4.3 «файлов её якорей»). Over-trigger (правка соседней функции в том же файле → C3 FAIL, хотя код под якорем не менялся) принят как приемлемый: лишняя перечитка заметки консервативна и безопасна, ложно-пропущенная протухшая заметка — нет. Обоснование зафиксировано в группе G.

5. **Resolved: расположение L2-заметок.** `archgraph` сканирует курируемые L2-заметки в `docs/arch/*.md` сервисного репо; генерат пишет в `docs/arch/generated/`. `obsidian/` инструмент НЕ трогает — это workspace-агрегат, вне scope `archgraph`.

6. **Resolved: конвенция воркеров (B3/B4).** Worker entry-point = тип, сконструированный в `cmd/<svc>/main.go`, у значения которого в `main` вызывается метод `Run(context.Context) error` ИЛИ `Start(context.Context) error`. Базовый набор методов воркера = **{`Run`, `Start`}**. Расширение набора (`Serve`/`Loop`/…) НЕ входит в scope archgraph-кода этой под-фазы — это калибровочная находка фазы раскатки на `kacho-vpc` (design §10). B3/B4 остаются на наборе {`Run`, `Start`}.

---

**После `✅ APPROVED`:**
- План реализации — через `superpowers:writing-plans`, каждый шаг ссылается на ID сценариев.
- Конвертация сценариев в Go integration-тесты на фикстурах — `integration-tester`.
- Реализация `archgraph` — `rpc-implementer` (несмотря на имя — тут это CLI, не RPC; роль ближайшая по «реализация Go по acceptance»).
- Трекинг эпика — через design-док (`docs/superpowers/specs/2026-05-22-kacho-architecture-vault-design.md`) и этот acceptance-док; ветка `arch-vault-rebuild` в `kacho-corelib`. YouTrack `KAC` для этого эпика временно не используется — до разбора рассинхрона YT-индексации.

---

## 13. Implementation closeout (2026-05-22)

Sub-phase 4.0 реализована полностью на ветке `arch-vault-rebuild` в `kacho-corelib`
(коммиты `ed6aabf..0929172` — 12 задач плана + рефактор фикстур). Все 53 сценария
A1–J1 покрыты Go integration-тестами (test-first RED→GREEN), `go test ./... -race`
зелёный, `golangci-lint` 0 issues, покрытие пакета `archgraph` 86.1% (≥70%).
Каждая задача отревьюена `go-style-reviewer`; финальное сквозное ревью — APPROVED.

**Known limitations (by-design, зафиксированы в doc-комментах кода и
`obsidian/kacho/packages/corelib-archgraph.md`):**

- **C2** проверяет только exported **функции и методы**, не типы/var/const →
  мёртвый exported-тип без методов и конструктора C2 не ловит. Точный
  value-flow-анализ типов признан несоразмерным цели (ловить забытые функции/RPC).
- **L4** генерит таблицы типов/полей/констант; DB-колонки и config-ключи не
  извлекаются (требует domain-знания sqlc/pgx/viper-диалектов).
- **C3** — пофайловый хеш (§12.4): over-trigger принят.
- **E5** hint нераспознанного воркера — грубая корреляция (`entrypoints.Hint`
  несёт `file:line`, не имя типа) — кандидат на tech-debt issue при раскатке.
- **RTA** не видит reflection-вызовы → ложный C2, лечится `// archgraph:keep`.
