# CI-RS-1 — замысел ограниченного производителя поставки

> **Статус: DRAFT**, 2026-09-17. Это предложение автора приёмки;
> независимые class initial/revalidation и design review ещё не состоялись.
> Контракт: [CI-RS-1 acceptance](sub-phase-CI-RS-1-release-supply-acceptance.md).

## D1. Существующие механизмы и минимальная граница

На Kachō `b5fa093341f1fdbe96adfc6a9555482690968253` прочитаны:

| Координата | Что уже делает | Что требуется этому изменению |
|---|---|---|
| `scripts/release/publish-service-artifact.sh` | Источник `services/<service>` из monorepo revision; замещение receiving tree; PR-маршрут | Не расширять смысл его service/revision input и exact-tree утверждений; новый ready-tree front end |
| `scripts/release/publish-version.sh` | П1–П8; только проверки и печать команды | Добавить П9 с полным declared consumer-import census и точной archived revision; сохранить отсутствие мутаций |
| `scripts/release/publish-tag.sh` | Dry-run, явный publish, версия, trunk checks, compatibility; создание одной remote tag ref | Использовать его проверяемые обязанности, не исполнять его исторический Kachō-only context против corelib без адаптации |
| `scripts/release/assert-trunk-green.sh` | Сверка обязательных проверок названной ревизии | Переиспользовать через repo-exact interface; отказ от неизвестных required checks |
| `scripts/release/probe-published.sh` | Проверка опубликованного модуля | Сохранить существующий вызов; new front end проверяет exact candidate payload и consumers |
| `internal/release/pack_test.go`, `consumable_test.go` | `x/mod/zip.CreateFromVCS`, файловый proxy, clean consumer; П8 проверяет один reference import | Вынести только необходимый reusable archive/census механизм в обычный код этого же пакета; существующие тесты сохраняют assertions |
| `scripts/release/assert-pin-reachable.sh` | Исторический platform/service pin; main и durable tags; optional cross-tree/history | Не ослаблять и не переназывать исторический predicate. Новый tree walker спрашивает нынешние modules/internal requirements |

Новый front end — `kacho/scripts/release/publish-module-tree.sh`; обычная Go
реализация проверки archive/consumer census — `kacho/internal/release/`, CLI
адаптер — `kacho/tools/releasepreflight/`. Это узкая оснастка выпуска Kachō,
а не общий NP алгоритм. Её перенос во все tool homes не входит в #2661 и не
требуется для первого corelib выпуска. Новый общий NP инструмент остаётся
в corelib по CI-NP-1. Новые файлы ниже — **proposed coordinates**, их пока нет.

Существующие public CLI сохраняются. Только П9 изменяет вердикт
`publish-version.sh` по #2258. Новые helpers не получают неявный cwd, identity
или global Git index; вызывающие явно передают target repository и revision.
Защиты main остаются неизменными. Взятые части существующего алгоритма имеют
один кодовый дом; копировать целиком service publisher запрещено.

## D2. Вход, ownership и commit key

Предлагаемый CLI:

```text
scripts/release/publish-module-tree.sh \
  --phase plan|deliver|release|probe \
  --tree <ready-tree-directory> --repo PRO-Robotech/corelib \
  --version <explicit-semver> --manifest <release-input.json> \
  --via-pull-request \
  [--commit PRO-Robotech/corelib --plan-sha256 <sha256>]
```

Без `--commit` все стадии холостые. `--commit` сравнивается **дословно** с repo;
непустая строка, basename, URL и подтверждение версии вместо repo не подходят.
`release` дополнительно получает `--landed-sha <40hex>`. `probe` read-only и не
принимает mutation key. В manifest version/repo обязаны совпасть с CLI.
Legacy `--publish`/`--confirm` старого service publisher не меняются.

Manifest schema version 1 именует:

- `repository`, `module_path`, `base_sha`, `version`, `baseline_version`;
- `input_tree_digest` и sorted file inventory: path, regular-file/executable
  mode, content digest; symlinks/submodules/служебный `.git` запрещены этому
  формату. Каталог `.github` разрешён и защищён правилами ownership;
- exact receiving-owned paths из base с mode/digest и причины их владения;
  весь tracked `.github/**` входит обязательно, manifest не может исключить
  его или перевести в source-owned. Новый receiving-owned path требует нового
  reviewed manifest; собственник задаётся принимающей стороной, не exporter;
- exact `preserve_paths`, `replace_paths`, `remove_paths`: перечисления,
  не shell/glob-выражения. Каждый путь base/input классифицирован ровно один
  раз. Пропуск, пересечение и несуществующий remove path дают отказ;
- consumers tagged union: `repository` с exact repo/revision, nonempty module
  roots и build contexts (GOOS/GOARCH/CGO/tags), либо `external-program` с
  nonempty tracked program paths, source identity и contexts. Для последнего
  `source.kind=candidate` означает exact candidate revision, разрешаемую в
  result SHA; это отдельный тип ссылки, не строка HEAD или будущий self-SHA
  внутри committed manifest. Другой допустимый source kind — pinned repository
  с явным 40hex revision. Release payload: exact non-Go paths/digests для NP
  и отдельное свидетельство comment-only CI-DT; `components`/`ci_dt_addenda`
  и полный закрытый набор proof records по interface prerelease table;
- pinned versions нужных инструментов и конечные бюджеты внешних вопросов.

Чистая snapshot-copy вне Git запечатывает вход, затем producer повторно
проверяет digest. Candidate собирается из этого снимка и разрешённых preserve
bytes **из base**, не текущего изменяемого checkout. Все операции Git идут в
новом owned clone под внешним TMPDIR с очищенным `GIT_*`, `GOWORK=off`.
Ready tree может быть создан любым уже проверенным сборщиком, но producer
не вызывает exporter и не меняет исходный каталог.

Exact `replace_paths` не даёт права менять receiving-owned bytes. Исходный
tree может повторять такие bytes; это сверяется на равенство и mode. Если их
нет, только explicit preserve сохраняет их. Поэтому требуемая #2588 инъекция
«нет .github» без declaration красная; lawful explicit preservation зелёная.

## D3. Preflight до любого push

`releasepreflight` получает immutable candidate Git revision и manifest, а
не произвольный текущий HEAD. Обязанности независимы и не заменяют друг друга:

1. Перепись ownership: полный exact-set candidate paths; receiving bytes/modes
   сохранены, непредусмотренных удалений нет, module path соответствует repo.
2. Latest published semver floor: получить remote tags, разыменовать annotated
   tags, проверить каноническое semver сравнение через имеющийся `x/mod/semver`.
   Выбранный baseline должен совпасть с последним опубликованным выпуском этого
   module major. Repo без прошлого выпуска здесь не поддерживается. Созданный
   tag, ещё не известный proxy, нельзя пропускать при выборе baseline.
3. Получить baseline Go zip и candidate zip по правилам `x/mod/zip`, не tar
   рабочего дерева. Package census считает import paths с реальным Go source,
   учитывает nested module исключения Go zip. Baseline и candidate наборы
   непусты; `baseline packages − candidate packages` пусто. Нужный пакет не
   доказывается одним именем каталога. Перепись файлов с constraints полная;
   supported contexts отдельно доказывают разрешение/build, а не подменяют
   структурный floor.
4. Consumer census обоих declaration types извлекается Go parser из tracked
   sources exact revision, включая `_test.go` и build-constrained files. Longest matching
   module root исключает соседний `/foobar`, when releasing `/foo`. Для `repository`
   требуются module root и целевые imports; для `external-program` — tracked
   program paths и целевые imports. Каждый import назначен
   хотя бы одному объявленному build context; непокрытый import даёт RED.
   Невалидный файл/constraint или непрочитанный файл не пропускаются.
5. Каждый import разрешается из **того же** candidate zip в ephemeral proxy
   и отдельном module cache. `go list`/`go build` output сверяется по exact
   import set, rc, Errors и непустому числу результатов. Blanket `go get`
   без последующей проверки/build не является доказательством. Для чужих
   зависимостей допустим подготовленный cache proxy, но факт его наличия и
   проверки отделён; missing prerequisite — NOT_EXECUTED. Для target module
   fallback в общий cache или сеть запрещён. Синтетическая версия file proxy
   никогда не публикуется. П9 вызывает этот же код, не копию предиката.
6. Required non-Go payload проверяется по paths/digests **в candidate zip**.
   Для CI-NP-1 достаточен и обязателен exact prerelease set NP-P01..06 из
   interface; projection-only не достаточен. Для CI-DT-1 — DT-P01..03, а при
   включении отдельного approved #2590 ещё DT-A2590-P01/P02. Каждый proof
   связан с exact source/test/output/scoped-review hashes. Ни actual consumer
   pin/materialization, ни runtime/retention, ни postrelease CI-DT-09 не
   требуются до первой публикации; они обязательны после ARCHIVE_VERIFIED.
   Producer не превращает этот scoped permit в общий GREEN CI-NP/CI-DT.

Для существующего Kachō `publish-version.sh` default П9 получает **реальный
исходник объявленного probe**, а не несуществующий Kaname→Kachō consumer:
новый `internal/release/testdata/reference-consumer/main.go`, извлечённый из
нынешней строки `program` в `TestExternalConsumerCanBuildTheModule`.
Он импортирует действующий `pkg/api/kacho/cloud/reference` и использует
`Referrer`; П8 читает тот же canonical program вместо своей строки. П9 получает
его как `external-program` из exact candidate revision, создаёт самостоятельный
временный модуль и собирает против zip. Программа пока **заказана**, не
представлена как существующий файл. Scope — совместимость этого declared
probe; отсутствие иных реальных downstream consumers названо явно и не
означает полноту пользовательского API. Для corelib declarations содержат
actual Kachō/Kaname repos, а не эти синтетические substitute inputs.

Проверка Go module zip не означает совместимость API или поведения. Прежние
compatibility/checks предикаты остаются обязательными и связываются с actual
target repo и SHA. Наличие preserved `.github` само по себе не доказывает CI.

## D4. Доставка, выпуск, readback

Стадии монотонны и имеют разные результаты:
`NONE → BRANCH_PRESENT → PR_OPEN → MERGE_PRESENT → MERGED_VERIFIED → TAG_PRESENT → ARCHIVE_VERIFIED`.
Локально запечатанный plan не объявляется remote стадией.
У каждой есть captured outcome GREEN/RED/NOT_EXECUTED, предыдущее remote
состояние не забывается. Это протокол исполнения producer, не lifecycle
Change Graph и не второй issue tracker.

`deliver` создаёт собственную ветку от exact base и PR. Default main защищён;
без `--via-pull-request` отказ вне зависимости от прав actor. Проверка PR
head, required contexts, findings и mergeability — named finite polling;
missing, skipped, cancelled и stale-head results не становятся success.
Слияние осуществляется штатным GitHub PR API с expected head SHA, после
всех действующих правил. `403` не лечится admin bypass или сменой protections.
Каждая попытка branch/PR/merge/tag/release-note отражается отдельным typed
`effects` entry по interface/schema. До write она UNKNOWN, после exact readback
PRESENT/ABSENT/CONFLICT; ABSENT требует terminal rejection и readback.
Последний stage сохраняется отдельно: успешный branch и rejected PR дают
BRANCH_PRESENT; потерянный merge/readback — PR_OPEN плюс UNKNOWN merge, без
tag. Подтверждённый merge object даёт MERGE_PRESENT до проверки ancestry/content.
Resume начинает с exact repo/ref/PR/plan-marker readback и не повторяет write
при UNKNOWN, не подменяет branch/mutation запись фиктивным PR. Полная finite
матрица CI-RS-12/19 и rules отсутствия/конфликта заданы в interface.

После merge `release` заново получает main. При squash его SHA закономерно
отличается от branch head: сравниваются exact approved content и manifest
дельта. Если база сдвинулась, preflight нового merged tree повторяется;
сохранность receiving paths сверяется с новой базой. Изменившийся plan digest
требует нового явного execution input. Tag target — exact verified SHA,
который был принятым main в зафиксированном snapshot. Required checks и
compatibility выносятся именно на него. Перед push читается свежий main:
target обязан остаться его предком; штатное продвижение main не требует
выпускать непроверенные новые commits. Переписывание, потеря ancestry или
недоступная история закрывают выпуск. Гонка на tag не допускает force.

GitHub не предоставляет этому producer атомарную транзакцию «сверить main
и создать tag»; query-before-write такой гарантии не даёт. Поэтому permit
утверждает проверенный snapshot и ancestry, а не вечное равенство current
main. Post-tag readback повторяет exact tag identity и ancestry относительно
нового main snapshot. Если после записи это невозможно подтвердить, producer
сохраняет TAG_PRESENT, возвращает RED/NOT_EXECUTED и не открывает repin;
уже созданный tag не переписывается и не удаляется. Protections не ослабляются.

Tag создаётся одной точной remote ref операцией `<sha>:refs/tags/<version>`
без локального тега, `--tags` и `--follow-tags`. Expected-empty remote tag
является условием создания. При неоднозначном ответе сначала exact readback.
Повтор при той же peeled commit identity идёт к archive probe; другой SHA
под тем же tag — RED. Release note может быть отдельной последующей операцией;
её отказ не отменяет уже существующий tag. Автоматическая ретракция или
перепубликация версии отсутствуют.

`probe` сохраняет exact pre-tag baseline version/commit/archive identity:
новая опубликованная версия не выбирается своим собственным floor. Повтор
после уже существующего tag проверяет baseline, записанный в том же plan;
при несовпадении его identity — RED. Pre-tag новая попытка с другим plan
повторно выбирает latest baseline. `probe` получает `.info`, `.mod`, `.zip` публичного Go proxy, проверяет version,
module path, origin commit и обычную checksum-валидацию, извлекает полный
payload и повторяет consumer import/build proof из опубликованного zip.
Сравниваются нормализованные member paths, bytes/modes и обязательные payload
digests: raw zip byte hash может зависеть от допустимой упаковки, поэтому
он не заменяет содержимое. Идентификаторы и raw archive digest сохраняются
как provenance. Только ARCHIVE_VERIFIED открывает consumer pin.

## D5. Два предиката #2230

Новый `scripts/release/assert-internal-pins-reachable.sh` и reusable Go
module parser обходят tracked go.mod каждого объявленного **product repo**.
Первичный scope: Kachō и Kaname, каждый с единственным root module на
исследованных SHA. Corelib leaf проверяется отдельно на отсутствие обратных
PRO-Robotech dependencies; ноль internal requirements там ожидаем по его
роли и не маскирует пустой обход продукта.

Mapping module → exact repo хранится в декларации рядом с release scripts.
Нет substring guess или предположения, что любой SHA относится к Kachō.
Псевдоверсия разбирается `x/mod/module` с проверкой формы; semver не подвергается
ручному извлечению 12-symbol suffix. Для каждого repo новое отдельное bare
хранилище получает свежие heads и tags и полную историю; annotated tags
разыменовываются. Local refs, stale `origin/*`, shallow отрицание и cache
proxy не являются remote reachability. Недоступность получения истории —
NOT_EXECUTED. При полном успешном fetch и отсутствии reachable commit — RED.

Общий predicate проверяет достижимость из хотя бы одной live origin ref.
Final mode дополнительно требует main ancestry **для всех текущих внутренних
псевдоверсий product repos**, включая Kachō → Kaname. Это напрямую исполняет
[owner comment #2230](https://github.com/PRO-Robotech/kacho/issues/2230#issuecomment-5600657173).
Origin-only GREEN при branch-only pin не закрывает issue. Зависимость Kaname
→ Kachō не возвращается. Перепись: repos/modules/files/internal requirements,
ordinary versions/pseudo versions, resolved commits, remote snapshots,
reachable и main-ancestor outcomes. Ноль pseudo законен при непустом product
census; ноль product modules/internal requirements — RED.

## D6. Протокол результатов и независимое доказательство

CLI exit codes: `0` — GREEN выбранной стадии, `1` — RED, `2` — invalid invocation,
`3` — NOT_EXECUTED. Machine result schema содержит phase, outcome, reason code,
repo/base/candidate/landed SHA, version, digests, census и per-predicate results.
Ненулевой code не классифицируется по одному виду stderr. Отказ инфраструктуры
до исполнения harness не даёт honest RED. Если есть и RED, и NOT_EXECUTED,
оба сохраняются; dependent action закрыта в любом случае. Закрытая схема,
reason enum и бюджеты заданы до независимых holders в
`docs/changes/ci-release-supply/interface.md` и `result.schema.json`.

Независимый tester создаёт маленькие настоящие Git repos/modules, local bare
remote и file proxy. CLI forge boundary получает журнал вызовов и контролируемые
ответы; законный путь доводится до конца до отрицательных инъекций. Одно-фактные
дельты вычисляются, а не объявляются. Тестовая подмена доказывает protocol и
запрет вызовов, **не** живые GitHub protections. Последние подтверждает отдельный
remote holder на настоящем PR/main без отключения правил и без вредоносных
production публикаций. Для missing capability сначала валидируются fixture,
tools и lawful twin; отсутствующий shell command не выдаётся за product RED.

## D7. Решения, внешние зависимости и предмет принятия

Root согласовал создание нового CI-RS-1 package без изменения исторического
KAN-RELEASE-1 и legacy policy census в текущем делегировании. Это не внешнее
acceptance/design approval. Policy applicability подробно в `policy-scope.md`.

Приёмке подлежат новые observable choices: explicit ownership manifest с
`.github` floor; обязательный PR-only путь; отказ bootstrap без previous
release; exact accepted-main tag target; full declared-consumer census; origin и final
main modes; закрытый prerelease/postrelease proof partition; typed branch/PR/
merge/tag/note ledger; включение exact bounded CI-DT addendum #2590 с собственным
proof сверх generated set. Последнее не меняет immutable CI-DT acceptance и
не делегирует принятие неизвестных addenda worker. Они перечислены для независимого review, не представлены
«рутинной convention» уже принятого исторического контракта.

Foreign `lane/w7-homes-lib` и `lane/envelope-neutral` не входят в ready tree.
Их семантический конфликт подтверждён owner comment #2588, и этот producer
не разрешает его по отсутствию textual conflict. Актуальная corelib main
служит базой, поверх неё допускаются только отдельно принятые NP и CI-DT
дельты, включая только явно перечисленный отдельно approved #2590 comment-only
addendum по его exact subject. T6 требует scoped prerelease proofs interface,
а T7 исполняет postrelease CI-NP/CI-DT обязанности; complete component GREEN
до выпуска не требуется, поэтому цикла T6→NP-T3/CI-DT-09→T6 нет.
Если дельты требуют этих foreign работ по существу, доставка останавливает
соответствующий payload, а producer и независимые gates продолжают свой scope.

## Exact-set трассировка

| Решение | Сценарии |
|---|---|
| D1, D2 | CI-RS-01, CI-RS-02, CI-RS-03, CI-RS-04, CI-RS-20 |
| D3 | CI-RS-05, CI-RS-06, CI-RS-07, CI-RS-08, CI-RS-09, CI-RS-21 |
| D4 | CI-RS-10, CI-RS-11, CI-RS-12, CI-RS-13, CI-RS-19, CI-RS-22 |
| D5 | CI-RS-14, CI-RS-15, CI-RS-16, CI-RS-17, CI-RS-18 |
| D6, D7 | Все перечисленные сценарии: evidence boundary и полномочия |

## Зафиксированные входы design subject

- `docs/changes/ci-release-supply/interface.md` — SHA-256 `855caf63e222db5733b110087107bb0e2e8af5f34cf8c648964c2c25edfa2932`.
- `docs/changes/ci-release-supply/result.schema.json` — SHA-256 `d4cd888ef8edea93f2b771fe2d5b65b4dbeb01cd01603dd2843fc5bfca13da32`.

Их изменение требует новой редакции этого design и независимой пересверки.
