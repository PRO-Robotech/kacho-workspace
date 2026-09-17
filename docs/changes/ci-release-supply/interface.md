# CI-RS-1 — DRAFT интерфейс для независимых holders

Это часть design subject; schema и текст фиксируются **до** T1. Worker не
определяет новые expected outcomes из собственной реализации. Изменение reason,
семантики phase, бюджета или обязательного поля требует пересверки design.

## CLI и seams

`publish-module-tree.sh` принимает только флаги из D2, плюс `--checks-budget`
(целые секунды 1–7200, default 1800) и `--network-budget` (1–300, default 30).
`--phase` по умолчанию `plan`. `--tree`, `--repo`, `--version`, `--manifest`
обязательны для plan/deliver/release. `--via-pull-request` обязательно для
deliver; release требует `--landed-sha`. Probe принимает repo/version/manifest,
запрещает `--commit`. Пропущенный `--commit` при deliver/release даёт dry-run,
не usage error. Наличие commit без exact repo/plan hash даёт usage error.
Неизвестный/повторный флаг и неназванный positional argument дают usage error.

Preflight CLI: `go run ./tools/releasepreflight --mode candidate|consumers|pins
--manifest <file> --revision <40hex>`. Все named modes обязательны, candidate
и consumers читают immutable candidate clone; для них `--revision` обязателен.
Pins читает exact product trees из manifest и не принимает `--revision`, чтобы
общий CLI SHA не подменил несколько repo-bound SHA. Для pins дополнительный `--final-main` включает owner predicate.
Эта строка — proposed executable, сейчас её не запускают как существующую.
`publish-version.sh` сохраняет прежние аргументы и добавляет `--consumers <file>`;
по умолчанию читает `scripts/release/consumers.json` рядом с собой. Декларация
не скрытый optional check: пустой/отсутствующий/невалидный файл закрывает П9.
Архивируется собственная HEAD revision, уже связанная существующей П5 с origin
main; ready-tree producer передаёт своей preflight точный candidate revision.
`--skip-pack` не выключает П9 и по-прежнему оставляет П8 неисполненной.
При invalid invocation, где phase не распознана, result.phase=plan,
repository/version=null до их успешного разбора; outcome=USAGE_ERROR и reason
INVALID_INVOCATION. Probe read-only сам по себе, dry_run=false и effects=[].

Product subprocess boundaries: Git CLI, Go CLI, forge API client, proxy HTTP
client, monotonic clock/sleeper. Независимый fixture driver подменяет эти
границы явной test-only dependency injection; runtime CLI не имеет hidden
«ignore checks» или arbitrary command env var. Live implementation принимает
только github.com и exact declared repo. Локальный bare remote/file proxy
доступен лишь тестовому driver, не production release input.

Каждый normal/usage invocation выдаёт **ровно один** UTF-8 JSON result в stdout
по `result.schema.json`; diagnostics в stderr без credentials. Result error
не маскирует выполненную remote mutation. Подпроцессы захватываются отдельно;
их stdout не смешивается с итоговым JSON. Отсутствие/повреждение JSON —
NOT_EXECUTED **держателя**, не выдуманный outcome производителя.

## Исходы и конечные бюджеты

Result outcome: GREEN→exit 0, RED→1, USAGE_ERROR→2, NOT_EXECUTED→3. Если есть
и RED, и NOT_EXECUTED checks, итог RED, но оба check результата остаются.
Первичный reason берётся у первого non-GREEN в фиксированном порядке проверок
D3 → identity/PR/checks/ancestry/tag → archive → consumers; RED имеет приоритет
над NOT_EXECUTED. GREEN требует reason `OK`.

Все операции имеют конечный deadline. Один Git/forge/proxy read ограничен
network-budget; ожидание required checks — checks-budget с monotonic clock.
Polling interval 5 секунд, последний sleep обрезан оставшимся deadline;
при interval > remaining выполняется только разрешённый остаток. Immediate
terminal RED не ждёт deadline. На read допускаются не более 3 попыток в
общем network-budget, паузы 1 и 2 секунды; бюджет не сбрасывается на retry.
Write не повторяется автоматически: uncertain response → readback. Readback
также ограничен network-budget. Deadline любого шага закрывает dependent action.
Go archive/consumer build имеет 600 секунд на context, максимум 3600 секунд
на стадию; эти значения для первого контракта не CLI knobs. Timeout —
NOT_EXECUTED с reason `BUDGET_EXHAUSTED`.

Схема имеет `additionalProperties: false` на каждой object границе; unknown
enum/property, malformed SHA, duplicate checks/predicates или contradictory
outcome/exit/stage считаются malformed result и не разрешают действие.
Census `null` означает «не измерено»; 0 — действительно измеренный ноль.
Stage сообщает последний **подтверждённый remote факт**, `NONE` до доставки,
`PR_OPEN`, `MERGED_VERIFIED`, `TAG_PRESENT`, `ARCHIVE_VERIFIED`. Dry-run не
производит remote переходов и имеет effects пустым; stage может отражать
уже существующее состояние, прочитанное без мутации. Snapshot содержит observed main SHA
и target; это не promise о future current main. Effects — только readback
подтверждённые PR/tag/release-note объекты, `UNKNOWN` отражает uncertain write
до успешного readback. Неизвестный исход мутации не превращается в NONE.

## Reason families и single-fact fixture axes

Reason codes закрыты schema. Предикаты считываются в порядке:
`invocation`, `identity`, `input`, `ownership`, `baseline`, `package-floor`,
`consumer-census`, `consumer-archive`, `payload`, `compatibility`,
`pr`, `required-checks`, `main-ancestry`, `tag`, `proxy`, `pins-origin`,
`pins-main`. Required set задан таблицей в следующем разделе; worker не выводит
его из удобства исполнения. Неприменимые predicates отсутствуют, required пустое
множество не GREEN.

| Сценарии | Точный reason отрицательного/неисполненного пути; lawful twin |
|---|---|
| CI-RS-01 | OK и dry_run=true/effects=[]; тот же вход с разрешённой phase/key делает только эту стадию |
| CI-RS-02 | INVALID_CONFIRMATION или REPOSITORY_MISMATCH; exact repo проходит |
| CI-RS-03,04 | UNDECLARED_PATH_LOSS / RECEIVING_OWNERSHIP_CONFLICT; preserve или исходные bytes/mode проходят отдельно |
| CI-RS-05 | PACKAGE_FLOOR_LOSS; возвращённый package archive проходит |
| CI-RS-06 | BASELINE_EMPTY / BASELINE_STALE / BASELINE_UNAVAILABLE; actual nonempty floor проходит |
| CI-RS-07 | CONSUMER_IMPORT_MISSING; добавлен только отсутствующий archive package |
| CI-RS-08 | CONSUMER_CENSUS_EMPTY / CONSUMER_DECLARATION_INVALID / SOURCE_UNAVAILABLE; непустой exact consumer census |
| CI-RS-09 | CONSUMER_IMPORT_MISSING; файл включён в candidate revision, не working tree |
| CI-RS-10 | PR_REQUIRED; exact PR-only invocation проходит |
| CI-RS-11 | TARGET_NOT_ON_MAIN / CONTENT_MISMATCH / REQUIRED_CHECKS_FAILED; actual accepted target с exact content/checks |
| CI-RS-12 | SOURCE_UNAVAILABLE / BUDGET_EXHAUSTED; тот же источник отвечает в бюджет |
| CI-RS-13 | PROXY_UNAVAILABLE / PUBLISHED_ARCHIVE_MISMATCH / CONSUMER_BUILD_FAILED; exact archive и build |
| CI-RS-14 | PIN_UNREACHABLE; remote ref делает commit reachable |
| CI-RS-15 | PIN_NOT_ON_MAIN; pin commit main ancestor |
| CI-RS-16 | OK; обычные semver не дают malformed pseudo |
| CI-RS-17 | MODULE_CENSUS_EMPTY / INTERNAL_CENSUS_EMPTY; непустой product census |
| CI-RS-18 | MODULE_MAPPING_INVALID / SOURCE_UNAVAILABLE; exact mapping и полная remote history |
| CI-RS-19 | TAG_IDENTITY_CONFLICT / WRITE_OUTCOME_UNKNOWN; readback того же объекта продолжает без второй записи |
| CI-RS-20 | OK; ready tree принимается без exporter invocation |
| CI-RS-21 | PAYLOAD_MISMATCH; только exact payload и отдельные NP/DT proofs |
| CI-RS-22 | INPUT_CHANGED / PR_HEAD_CHANGED / TARGET_NOT_ON_MAIN; неизменённый input, stable PR и retained main ancestry |

Непрочитанный fixture, сломанный Go/Git harness, неконструируемый unlawful twin
имеют harness outcome NOT_EXECUTED; они не дают перечисленный SUT reason.
Fixture ledger именует сценарий, positive twin, computed changed field,
expected outcome/reason/exit и forbidden remote effects до первого запуска SUT.

## Обязательные predicates и порядок remote effects

Обозначение **B** — точный set `invocation`, `identity`, `input`, `ownership`,
`baseline`, `package-floor`, `consumer-census`, `consumer-archive`, `payload`,
`compatibility`, `pins-origin`. Он не зависит от числа findings. Manifest
producer отдельно именует `product_trees` Kachō и Kaname с exact revisions;
это scope pin gates, не подмена consumer declarations. Corelib leaf проверяется
на отсутствие обратных рёбер в `compatibility`, а не трактуется как пустой продукт.

| Phase/mode | Required set для GREEN | Когда разрешён внешний эффект |
|---|---|---|
| plan | B + `pr` в read-only policy mode | Никогда. `pr` доказывает существующий repo/main и допустимый штатный PR route; не выдаёт несуществующие candidate checks за GREEN |
| deliver/release без commit | Тот же set, что plan, независимо от requested phase | Никогда. Result dry_run=true; completed PR/tag predicates не утверждаются |
| deliver с commit | B + `pr`, `required-checks`, `main-ancestry` | После B и policy-half `pr` разрешены только own branch/PR. Merge требует live `pr` identity/head + actual PR-head required checks. GREEN стадии только после merge readback и ancestry |
| release с commit | B + `pr`, `required-checks`, `main-ancestry`, `tag` | `pr` подтверждает принятую собственную дельту и exact merged content. Checks на target accepted-main SHA. До tag write — весь set GREEN, где `tag` означает vacancy либо same-identity idempotent resume. После write `tag` и ancestry перечитываются |
| probe | B + `pr`, `required-checks`, `main-ancestry`, `tag`, `proxy` | Никогда. B спрашивается по published zip и закреплённому pre-tag baseline; exact target checks/PR evidence перечитываются. ZIP/package/payload/consumer proofs обязательны, не наследуются от одного tag |
| preflight candidate | `invocation`, `identity`, `input`, `ownership`, `baseline`, `package-floor`, `consumer-census`, `consumer-archive`, `payload` | Никогда; меньшая область явно названа mode, не общий permit публикации |
| preflight consumers / П9 | `invocation`, `identity`, `input`, `consumer-census`, `consumer-archive` | Никогда; П9 не заменяет П1–П8, compatibility или whole publisher |
| preflight pins | `invocation`, `identity`, `input`, `pins-origin` | Никогда; ordinary semver и zero-pseudo outcome определены приёмкой |
| preflight pins --final-main | Предыдущий set + `pins-main` | Никогда; этот mode обязателен после repin и перед closure #2230 |

`pr` имеет ровно три declared scopes в result subjects: `policy`, `candidate`,
`merged`. Это разные требуемые факты внутри одного именованного predicate:
plan/dry-run использует только policy, deliver — policy затем candidate и
merged, release/probe — merged. `required-checks` subjects включают ровно
один checked commit SHA и actual required context set; пустой набор обязательных
проверок не разрешает доставку/выпуск. Отсутствующий stage fact — NOT_EXECUTED,
не skip/GREEN. Before-effect set и final-phase set различаются явно: будущий
PR не нужен для проверки кандидата, но нужен для успешного deliver.

`payload` обязателен в B всегда. Manifest поле `components` — exact set
включаемых в bounded выпуск subjects из `CI-NP-1`, `CI-DT-1`; root утверждает
его вместе с candidate diff. Если component не включён, его predicate-ветвь
не исполняется и явно отсутствует в payload subjects. Нельзя исключить component,
чьи delta paths включены в ready tree: каждый изменённый payload path связан
с принятым subject, иначе PAYLOAD_MISMATCH. При CI-NP-1 обязателен exact
непустой Python/JS/SDK-lock inventory и собственное release-eligible NP evidence;
scoped projection GREEN не удовлетворяет этому. При CI-DT-1 обязательны exact
generated-file digest и отдельный comment-only descriptor/program proof.
Если components пуст и payload delta пуст, `payload` GREEN с examined=0
означает измеренную неприменимость **только этой ветви**; package/consumer
census по-прежнему обязаны быть непустыми. Fixture инвертирует каждый condition.

`pins-main` не добавляется молча к общему origin mode. После consumer changes
root создаёт новый verification manifest с **actual final consumer revisions**
и запускает final-main; pre-release pins/old consumer SHA не закрывают #2230.
Все required proofs связываются с тем же candidate/manifest subject; captures
от другого phase/commit не засчитываются. Existing witness program у Kachō
не заменяет actual consumer trees в первой corelib поставке.
