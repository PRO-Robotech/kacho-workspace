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
`BRANCH_PRESENT`, `PR_OPEN`, `MERGE_PRESENT`, `MERGED_VERIFIED`, `TAG_PRESENT`,
`ARCHIVE_VERIFIED`. MERGE_PRESENT подтверждает merge object, но ещё не ancestry/content. Dry-run не
производит remote переходов и имеет effects пустым; stage может отражать
уже существующее состояние, прочитанное без мутации. Snapshot содержит observed main SHA
и target; это не promise о future current main. Effects — полный типизированный
журнал всех запрошенных либо повторно использованных remote действий из следующего
раздела. Stage не подменяет журнал: UNKNOWN branch при NONE и UNKNOWN merge при
PR_OPEN сохраняются явно. Непопытанное действие в effects отсутствует.

## Полный remote effect ledger и resume

Закрытый union `effects` имеет kinds **branch, pr, merge, tag, release-note**.
Каждая запись содержит exact `repository`, `state` и типизированные координаты
по schema; свободное имя PR не может изображать ветку или merge. Запись готовится
как UNKNOWN **до** сетевого write, затем заменяется только по наблюдённому ответу
и readback. Result сохраняет все попытки этого plan и найденные exact объекты
при resume; перед каждым новым invocation сначала readback. Неполный/malformed
result не разрешает продолжение. После прерывания процесса новый invocation
заново выводит те же координаты из plan и читает их; потерянный stdout не даёт
права на blind write.

| Kind | Неизменяемая identity / ожидаемые и наблюдаемые значения | PRESENT readback и stage |
|---|---|---|
| branch | repo + `ref=refs/heads/release/module-<full plan_sha256>`; expected_sha=candidate, sha=observed ref target | Точная ref указывает на expected SHA → BRANCH_PRESENT. Создание только expected-empty; чужое содержимое не перезаписывается |
| pr | repo + head_ref той ветки + base_ref=refs/heads/main + expected_head_sha + exact body marker `CI-RS-1 plan-sha256:<full digest>`; pr_number и sha=observed head | Ровно один PR того же repo/head/base/marker и expected head → PR_OPEN; номер берётся из readback, не предполагается заранее |
| merge | repo + pr_number + head_ref/base_ref + expected_head_sha; sha=observed PR head, merge_sha и main_sha из readback | PR merged=true с тем же expected head и actual merge commit → MERGE_PRESENT; только content/checks/ancestry дают MERGED_VERIFIED. Squash merge_sha может отличаться от expected_head_sha |
| tag | repo + exact `ref=refs/tags/<version>` + expected_sha=accepted target; sha=peeled target | Exact peeled SHA → TAG_PRESENT; дальнейшая потеря ancestry не стирает факт тега |
| release-note | repo + tag_ref + expected_sha=tag target; sha=observed target и release_id | Exact release object для того же tag/target → PRESENT, stage остаётся TAG_PRESENT либо ARCHIVE_VERIFIED; note не равна archive proof |

`PRESENT` означает exact identity после readback; `CONFLICT` — наблюдённый иной
объект/SHA под этой identity, `UNKNOWN` — исход запроса нельзя доказать.
`ABSENT` требует **обоих** фактов: окончательный отрицательный ответ mutation
(например, явно rejected PR creation/merge) и успешный точный readback отсутствия
эффекта. Пустой readback после потерянного ответа не доказывает завершение
возможного запроса: остаётся UNKNOWN. Для UNKNOWN/ABSENT неизвестные observed
SHA/ID — null, expected identity/SHA обязательны; null не подменяется ожидаемым.
Для merge ABSENT PR существует, но merged=false, merge_sha=null; не удалять PR.

Все write и readback имеют network-budget каждый; reads допускают только
описанные выше три попытки внутри своего deadline. После UNKNOWN final reason
WRITE_OUTCOME_UNKNOWN, NOT_EXECUTED/3 (если другой RED не имеет общего приоритета).
Dependent actions запрещены: UNKNOWN branch не создаёт PR, UNKNOWN pr не делает
merge, UNKNOWN merge не создаёт tag, UNKNOWN tag не создаёт note и не разрешает
pin. Явно rejected mutation + ABSENT → RED/REMOTE_WRITE_REJECTED. CONFLICT →
RED/EFFECT_IDENTITY_CONFLICT, кроме tag (TAG_IDENTITY_CONFLICT) и changed PR head
(PR_HEAD_CHANGED). Журнал сохраняет предыдущие PRESENT записи и последний
подтверждённый stage при любом таком отказе.

Resume с тем же repo/version/input/plan сначала читает все известные identities
в порядке branch→PR→merge→tag→note. Exact PRESENT повторно не записывается.
UNKNOWN запрещает новую попытку; допускается только новый bounded readback.
После достоверного ABSENT возможен новый явный invocation с тем же exact key,
повторным preflight и свежей проверкой absence; автоматического retry write нет.
CONFLICT требует остановки, без force/update/delete/duplicate PR. PR lookup с
нулём результатов при uncertain request остаётся UNKNOWN; с несколькими —
CONFLICT. Обычный CLOSED_UNMERGED PR того же plan не переоткрывается автоматически.
No-op resume имеет effects с найденными exact объектами; dry-run и probe
имеют effects=[] и не заявляют совершённые ими mutations.

CI-RS-12/19 требуют конечные single-fact fixtures до реализации:

- Полный lawful branch→PR→merge с exact readback служит общей парой. Изменить
  только ответ создания PR на terminal rejection: branch PRESENT, pr ABSENT,
  stage BRANCH_PRESENT, RED/REMOTE_WRITE_REJECTED, merge/tag calls 0.
- Изменить только readback availability после lost branch response: при
  недоступности branch UNKNOWN, stage NONE, NOT_EXECUTED/WRITE_OUTCOME_UNKNOWN;
  lawful readback exact ref → PRESENT без второго push, затем можно продолжать.
- Lost PR response: exact unique lookup даёт PRESENT без duplicate create;
  недоступный/пустой uncertain lookup сохраняет pr UNKNOWN и BRANCH_PRESENT;
  второй matching PR — отдельный CONFLICT fixture.
- Lost merge response: merged=true + expected head + actual merge SHA даёт
  MERGE_PRESENT, затем проверяются content/checks/ancestry; lost readback даёт
  merge UNKNOWN при PR_OPEN, tag calls 0. Отдельный terminal rejection с
  merged=false даёт merge ABSENT; отдельный changed head даёт CONFLICT.
- Аналогичные exact-present/unknown/conflicting tag и release-note readbacks
  сохраняют уже созданные объекты. Ошибка note не повторяет tag; ошибка proxy
  сохраняет TAG_PRESENT. В каждом варианте один вычисленный changed field,
  полный mutation log и lawful ответ того же вида; fixture error не SUT RED.

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
| CI-RS-12 | SOURCE_UNAVAILABLE / BUDGET_EXHAUSTED до write; WRITE_OUTCOME_UNKNOWN после write и исчерпанного readback; тот же источник отвечает в бюджет |
| CI-RS-13 | PROXY_UNAVAILABLE / PUBLISHED_ARCHIVE_MISMATCH / CONSUMER_BUILD_FAILED; exact archive и build |
| CI-RS-14 | PIN_UNREACHABLE; remote ref делает commit reachable |
| CI-RS-15 | PIN_NOT_ON_MAIN; pin commit main ancestor |
| CI-RS-16 | OK; обычные semver не дают malformed pseudo |
| CI-RS-17 | MODULE_CENSUS_EMPTY / INTERNAL_CENSUS_EMPTY; непустой product census |
| CI-RS-18 | MODULE_MAPPING_INVALID / SOURCE_UNAVAILABLE; exact mapping и полная remote history |
| CI-RS-19 | REMOTE_WRITE_REJECTED / EFFECT_IDENTITY_CONFLICT / TAG_IDENTITY_CONFLICT / WRITE_OUTCOME_UNKNOWN; точный typed readback продолжается без второй записи |
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

`payload` обязателен в B всегда. Manifest `components` — exact set из
`CI-NP-1`, `CI-DT-1`, принятый root вместе с candidate diff. Каждый изменённый
payload path связан с exact approved subject; исключить component при наличии
его delta нельзя. Если components и payload delta пусты, GREEN/examined=0
означает измеренную неприменимость только payload; package/consumer census
по-прежнему непусты. Включённый component требует **все** перечисленные ниже
prerelease predicates; другого sufficient subset нет. Missing/RED proof даёт
PAYLOAD_MISMATCH/RED; недоступный proof — SOURCE_UNAVAILABLE/NOT_EXECUTED.

## Закрытый prerelease set и последующие обязательства

Каждый proof manifest именует `predicate_id`, exact source repo/revision и
непустой path/mode/SHA256 set, независимый test/comparator repo/revision и
path/SHA256 set, полные output path/SHA256 captures (command/cwd/runtime/rc,
непустой declared/executed census), отдельный scoped review record path/SHA256
и его подтверждённую authority coordinate. Самозаявленный GREEN worker не
подходит. Review относится к тем же source/test/output subjects. Каждый source
path в payload совпадает по bytes/mode с reviewed source и candidate zip;
сборочный commit может отличаться, но предметная дельта и все покрываемые bytes
должны совпасть. Проверка proof records не требует публикации будущего module.
Точный set этих identities входит в plan digest; их смена инвалидирует permit.
`components` и `ci_dt_addenda` не имеют duplicates/unknown IDs; непустой
`ci_dt_addenda` требует CI-DT-1 в components. Required proof ID set равен
объединению строк выбранных components и их включённых addenda; duplicate,
unknown или отсутствующий required ID даёт PAYLOAD_MISMATCH. Extra исторические
records могут храниться вне этого proof set, но не участвуют в permit.
RS проверяет binding/полноту и scoped verdict, не создаёт новый oracle NP/DT.

| Component / обязательный predicate_id | Достаточный предмет до первого выпуска; существующее основание |
|---|---|
| CI-NP-1 / NP-P01 | Полный project + настоящие readers до/после: stats, failures, HTTP, coverage, precondition/script/unanswered/assertion, provenance/catalogue, отсутствие opaque/meta carriers и честный нулевой Newman. Lawful, красный и неполный результаты, однофактные mutations и безопасный вывод. CI-NP-01/02/03/06, `publication-projection-and-readers`; одна projection ветвь без остальных NP-P не достаточна |
| CI-NP-1 / NP-P02 | Полный standalone scan supported carriers/families/contexts и семи representations raw/JSON/URL/base64/base64url/Buffer/nested JSON; filename/key/test/collection/error/manifest/log, lawful null/empty, public keys/IDs и отсутствие canary-specific recognizer. Все declared lawful/negative/incomplete случаи независимого carrier corpus, none skipped; FINDING/NOT_EXECUTED не CLEAN. CI-NP-02/03, scanner design и scoped carrier holder |
| CI-NP-1 / NP-P03 | Все шесть limits `archive_bytes`, `expanded_bytes`, `document_bytes`, `zip_entries`, `decode_depth`, `decoded_nodes` у **каждой** project/scan/check: exact equality lawful, one-step-over отказ, malformed/unknown/above-ceiling override отказ, без silent truncation. Полный typed decoding accounting по двум hash-bound conventions ниже; все independently declared cases исполняются. CI-NP-02/03 и routine interface |
| CI-NP-1 / NP-P04 | Полный final ZIP checker: закрытые manifest/projected schema, source binding, точные members/digests/size, ZIP metadata и весь envelope, включая compressed tail/trailing bytes; пропуск/повреждение/непрочитанный member и ложный digest не дают CLEAN. Отдельные scan/check semantics; только complete check разрешает upload. Project/check regression вместе с новым scanner, не старый изолированный GREEN. CI-NP-02/03 и `publication-projection-and-readers` |
| CI-NP-1 / NP-P05 | `publishSnapshot` получает private immutable bytes, checker видит копию, receiving transport получает ровно checked snapshot. Add/remove/mutate до снимка и мутация после последнего check, raw path bypass, malformed/missing/non-CLEAN/throwing checker, digest/size mismatch, transport mismatch/errors, budget/abort варианты с lawful twins и нулём forbidden transport calls. CI-NP-03/04, `publication-byte-binding` |
| CI-NP-1 / NP-P06 | Настоящий pinned `@actions/artifact@6.2.1` из exact dependency lock и его selected internal stream API исполняются на Node24, recording network boundary принимает те же bytes/digest/size; fake SDK function не proof. Exact action/entrypoint `runs.using: node24`, fixed canonical checker+SDK; private SDK stdout/stderr/exception handling, credential-free checker env, actual child termination при timeout, safe refusal без runtime capability/credential, create/finalize metadata mismatch. CI-NP design SDK seam и только prerelease часть `publication-sdk-and-delivery`; реальные Actions credentials/upload здесь не требуются и не объявляются проверенными |
| CI-DT-1 / DT-P01 | Exact canonical `proto/corelib/subscription/subscription.proto` source delta принят отдельным scoped review; только разрешённый carrier comment, semantic descriptor без source info неизменён. CI-DT-08 |
| CI-DT-1 / DT-P02 | Штатный D5 emitStubs из exact source/tool versions воспроизводит baseline и candidate set из четырёх файлов. Единственная generated delta — комментарий `api/corelib/subscription/subscription.pb.go`; остальные три byte-identical. Полные Go tokens/AST и raw descriptor одинаковы, независимый comparator имеет lawful/one-token/empty controls. Prerelease часть CI-DT-09 |
| CI-DT-1 / DT-P03 | Independent proto/Go post-diff reviews связывают DT-P01/02 с exact source, generated output и comparator evidence; accepted CI-DT allowed-set соблюдён. Этот scoped proof не объявляет весь CI-DT GREEN |

Для NP-P02/03 reference declarations — принятые CI-NP acceptance/design/interface
и conventions `1604e73f8b496a5be946da4a732e7c57f4d6e6118f2b95ef7dd3d572a243b96c`
и `0f5c81dd85a2ada556e3d599db160e85befe28903c74646795cce89c0e49a50a` из
`docs/changes/ci-newman-publication/conventions/`. Их exact paths/hashes вместе
с frozen independent corpus/driver входят в proof manifest; tester не выбирает
новую единицу depth/nodes или более узкую матрицу. Старые RED/scoped GREEN сами
по себе не доказывают полный текущий combined source.

CI-DT дополнительно может включать **отдельно approved bounded addendum** того же
contour. Это новое явно reviewable решение CI-RS; immutable CI-DT-01..09 не
расширяются. Начальный разрешённый addendum ровно #2590:
`docs/changes/ci-doc-truth/addenda/issue-2590-scope.md`, subject SHA256
`0bf009e5c11cf964397bb32274e2492d8aed41fd6901918f4a8e8189587ca105`, baseline record
`cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903`.
Manifest `ci_dt_addenda` — exact subset этого списка; чужой ID/path/hash красный.
При включении #2590 обязательны ещё **DT-A2590-P01**: exact allowed paragraph и
whole-file candidate digest из addendum, полные tokens/position-free AST без
whitelist, неизменность bytes вне allowed region и existing assertions, собственные
lawful/one-token/outside-comment/old-header/empty controls; **DT-A2590-P02**:
exact шесть existing notice tests 6 RUN/6 PASS/0 FAIL/0 SKIP и independent scoped
review по A2-01..03. Evidence binds exact source/test/output/review как выше.
Положительный DB integration не требуется и не утверждается этим comment proof.
Эти два predicates **добавляются** к DT-P01..03, не заменяют four-file generation.
Если delta `migratorcli/notice_test.go` есть, исключить addendum из manifest нельзя.
Включение другого addendum или изменение hash возвращает этот supply subject на
review; принимать будущие unknown deltas по wildcard запрещено.

Для CI-RS-21 finite fixture matrix: полный NP-P01..06 до published version lawful;
projection-only RED; по одному убрать/исказить/сделать недоступным **каждый**
обязательный proof; отдельно все DT-P01..03 и при #2590 оба DT-A predicates.
Тот же полный prerelease set с pending postrelease records остаётся eligible;
никакой record будущей публикации не синтезируется. Exact NP nonempty Python/JS/
SDK-lock inventory и DT/addendum digests в **candidate archive** обязательны
дополнительно к proofs, затем снова проверяются из published archive.

Последующие обязательства сохраняются полностью: после T6 ARCHIVE_VERIFIED
идут NP-T3 (real consumer pins, clean materialization, удалить private copy,
parsed workflows CI-NP-05), NP-T4 (CI-NP-07 real own identity/all shards и download
rescan), NP-T5/6 (CI-NP-08/09 retention/при необходимости exact containment),
NP-T7 (CI-NP-10 fresh revalidation/convergence/main/closure). Для CI-DT-09 после
выпуска обязательны public archive equality, actual Kachō pin и GOWORK-off
повтор required tests; остальные CI-DT и addendum A2-04 main/delivery obligations
не исчезают. Эти **postrelease** результаты не prerequisites первого T6 и не
становятся GREEN из prerelease proof. T7 начинает consumer work после archive,
а завершение CI-NP/CI-DT/issue closure требует их собственных полных вердиктов.

`pins-main` не добавляется молча к общему origin mode. После consumer changes
root создаёт новый verification manifest с **actual final consumer revisions**
и запускает final-main; pre-release pins/old consumer SHA не закрывают #2230.
Все required proofs связываются с тем же candidate/manifest subject; captures
от другого phase/commit не засчитываются. Existing witness program у Kachō
не заменяет actual consumer trees в первой corelib поставке.
