# CI-RS-1 — DRAFT dependency plan производителя поставки

**Статус:** DRAFT. Это порядок работ, не текущий tracker. Истина состояния —
#2588/#2258/#2230. Никакая строка ниже не открывает source или тестовую реализацию.
Автор использует writing-plans для границ задач; code/test snippets намеренно
не произведены: текущее поручение ограничено reviewable contracts и dependency
plan до независимого review. Полный worker handoff следует после design approval.

**Цель:** проверяемо доставить ready tree через protected main, выпустить его
без ручного обхода и доказать пригодность archive до consumer pin.
**Архитектура:** новый узкий front end над существующим release contour,
reusable archive/census в `internal/release`, два pin predicates.
**Стек:** Bash, Go `x/mod`, Git, GitHub PR/check APIs, Go module proxy.
**Контракт:** `docs/specs/sub-phase-CI-RS-1-release-supply-acceptance.md` и design
рядом; их exact raw-byte hashes записаны в `change.yaml`.

## Общие границы

- Owned worktrees; GOWORK off; внешний TMPDIR; Git environment sanitization.
- Default dry-run; exact repo `--commit`; protected PR route; no force/update
  tags; no policy bypass; no direct main push.
- Ready tree input; existing exporter не prerequisite; foreign lanes и #2661
  вне задач; исторические KAN-RELEASE subjects/review records не меняются.
- П9 дополняет П1–П8. Old service publisher CLI и old pin predicate сохраняются.
- Самостоятельные pre-publication archive и post-publication proxy proofs;
  consumer pins появляются только после ARCHIVE_VERIFIED.
- Наблюдавшийся baseline v1.9.0 перечитывается перед действием; следующий номер
  задаётся оператором явно и проходит compatibility/floor checks.

## T0 — независимое принятие и test handoff

Вход: этот DRAFT и свежие issue comments. Reviewer, отличный от автора,
проверяет каждый scenario, E1–E12 и observable choices D7. Root сохраняет
четыре exact-hash external reviews и читает их обратно; при правках hashes
меняются и downstream approvals не переносятся. После TASKS_READY tester
фиксирует точный CLI/result schema и executable holders как routine interface;
изменение семантики возвращает контракт на review. Ни один current proposed
holder ещё не выдаёт разрешения на код.

## T1 — независимые RED и инверсия держателей

**Владелец:** integration-tester, отличный от source worker. **Зависит:** T0.
**Предмет:** CI-RS-01–22. **Файлы (новые, test-only):**
`internal/release/supply_candidate_test.go`, `consumer_imports_test.go`,
`internal_pins_test.go`, `scripts/release/publish-module-tree-inject.sh`.

Tester делает реальные tiny Git/Go fixtures и lawful twin; считает
single-fact delta; проверяет harness/tool/fixture; лишь затем спрашивает SUT.
Отдельно empty inputs, normal semver, no mutation log, remote uncertainty и
partial completion. Shell driver приводит test set к exact scenario set,
сохраняет captures под holder evidence coordinates. Baseline red не может
быть только «файл будущего executable не найден»: требуется валидированный
capability seam, явно различающий отсутствие поведения и незапуск harness.
Root принимает raw RED/NOT_EXECUTED distinction и отдельно открывает source.

## T2 — archive/census и П9

**Владелец:** release worker. **Зависит:** принятый independent RED T1.
**Сценарии:** CI-RS-03–09, CI-RS-21. **Файлы:** новые
`internal/release/manifest.go`, `archive.go`, `consumers.go`,
`tools/releasepreflight/main.go`; узкие изменения `internal/release/pack_test.go`
для одного кода упаковки, `scripts/release/publish-version.sh` для П9.
Consumer declaration — новый `scripts/release/consumers.json`; canonical
external program — новый `internal/release/testdata/reference-consumer/main.go`.
`consumable_test.go` читает его вместо собственной program string, сохраняя
тот же reference import/Referrer witness.

Вход: immutable candidate Git SHA + manifest. Выход: typed preflight result
из D6 и exact package/import/payload census. Существующая П8 сохраняет свой
reference-import proof. Новая П9 потребляет **тот же** archive builder, но
спрашивает каждый declared consumer import. Пустые consumers и imports красны.
Для corelib manifest составляется по текущим actual Kachō/Kaname revisions.
Для старого Kachō publisher default — external-program reference witness D3,
поскольку actual Kaname→Kachō ребра больше нет. Это явно обозначенная узкая
compatibility программа, не выдуманный downstream и не снятый iam module.
Lawful/missing-import/empty пробы обязательны для обоих declaration types.

Проверки после source: независимые T1 `TestReleaseSupplyCandidatePreflight` и
`TestReleaseDeclaredConsumerImports`; существующие `go test ./internal/release
-count=1 -json` и `scripts/release/publish-version-inject.sh`. Точные commands,
cwd, SHA, выполненные тесты, counts/rc фиксирует verifier; environment failures
не green и не право ослабить assertions.

## T3 — ready-tree producer и защищённая поставка

**Владелец:** release worker. **Зависит:** T2 GREEN и T1 protocol RED.
**Сценарии:** CI-RS-01,02,10,11,12,13,19,20,22.
**Файлы:** новый `scripts/release/publish-module-tree.sh`; только необходимые
repo-explicit seams у `assert-trunk-green.sh`, `publish-tag.sh`,
`probe-published.sh`; existing service publisher поведения не меняет.
Тесты смежных затронутых scripts сохраняются и прогоняются.

Input/ownership/candidate freeze идёт до push. Deliver выдаёт свой PR; release
принимает actual merged SHA, повторяет checks и preflight; probe проверяет
actual proxy archive. План producer не вызывает consumer `go get` до доказанного
zip. Existing protections — источник, не параметр для отключения. Проверяется
также журнал запрещённых вызовов, zero external mutation в dry-run, exact repo
identity и readback после uncertain response. SDK/credential setup не изменяется.

## T4 — текущие внутренние pins

**Владелец:** release worker. **Зависит:** собственный accepted RED T1; может
идти независимо от T2/T3 после review. **Сценарии:** CI-RS-14–18.
**Файлы:** новый `internal/release/pins.go`,
`scripts/release/assert-internal-pins-reachable.sh`,
`scripts/release/internal-modules.json`; CLI adapter T2 получает subcommand
без изменения согласованного результата. Existing historical
`assert-pin-reachable.sh` и инъекции сохраняются.

Вход: product repo trees и mapping internal module → origin repo. Выход:
origin/general и final/main results с непустым product census. Новый caller
в release preflight и именованный CI/pre-merge caller Kachō должны быть
доказаны исполнением; process declaration без вызова не закрывает #2230.
Kaname не получает копию общего алгоритма: cross-repo проверку выполняет
release orchestrator над её exact tree. Если потребуется постоянный Kaname
CI caller, сначала отдельный согласованный home/delivery общего инструмента,
не незаметный scope creep в #2661.

## T5 — independent verification и landing производителя

**Владельцы:** independent tester, Go/system-design reviewers, root landing.
**Зависит:** T2–T4. **Сценарии:** все 22.
Tester запускает собственные lawful/negative/empty проверки на exact source
content; worker не редактирует независимые assertions. Review сверяет
ownership/floor/archives, result classification, remote races, callers и
полный scope. Нужны actual-diff applicability для DB/proto N/A, а не заранее
поставленные exemptions. Root доставляет producer в Kachō main штатным PR;
механическое cherry-pick не называется independent verification.

## T6 — первый bounded corelib выпуск

**Владелец:** root/operator producer; independent verifier. **Зависит:** T5
landed, собственные CI-NP и CI-DT acceptance/evidence для включаемых payload.
**Сценарии:** CI-RS-01–13,19–22 на реальном receiving repo.

1. Считать свежий corelib main и предыдущую published version. Собрать ready
   tree от main с **только** принятыми NP additions и CI-DT generated delta.
   Foreign subscription lanes не добавлять даже при clean cherry-pick.
2. Сделать receiving ownership manifest и declared consumers Kachō/Kaname.
   Проверить исходные `.github` bytes, full previous-package floor, required
   Python/JS/lock files и CI-DT descriptors/tokens. DRAFT не назначает будущую
   версию или будущий commit SHA.
3. Выполнить producer dry-run; verifier читает exact plan/census. Выполнить
   deliver с repo-exact commit key и plan hash; дождаться штатного PR merge.
4. Повторить merged-SHA preflight и required checks, выполнить release тем же
   producer, считать tag обратно; выполнить published archive probe. Факт
   существующего tag сохраняется при последующем отказе, pin остаётся прежним.

Это первый реальный remote proof producer, не тестовый выпуск ради инъекции.
Отсутствующий NP GREEN не блокирует разработку producer, но закрывает включение
соответствующего payload. CI-DT может выпускаться отдельно тем же маршрутом,
если его собственные зависимости замкнулись.

## T7 — потребители и closure

**Владелец:** consumer workers, independent verifier, root. **Зависит:** T6
ARCHIVE_VERIFIED и собственные CI-NP/CI-DT green transitions.

Kaname получает real published corelib pin и канонический NP caller по своему
контракту. Затем Kachō получает corelib pin и нужный Kaname main pin; прямое
Kachō → corelib ребро учитывается отдельно, поэтому это DAG, не линейная
замена одного go.mod. В каждом одиночном checkout `GOWORK=off`, no replace,
обычный checksum verification; документируются actual resolved modules и
non-Go payload. Финальный #2230 run проверяет main ancestry всех текущих
internal pseudo versions и origin reachability.

Closure каждого issue имеет собственное основание: #2588 — landed producer,
его invocations и реальная защищённая поставка; #2258 — landed П9 с lawful,
missing-import и empty-census proof до тега; #2230 — исполняемый полный tree
gate, birth inversion и owner main-ancestor predicate на final delivered pins.
После независимых convergence/landing и повторной проверки main root закрывает
задачи. Успех producer не закрывает автоматически CI-NP или CI-DT.

## Exact-set scenario → task

| Работа | Сценарии |
|---|---|
| T2 | CI-RS-03, CI-RS-04, CI-RS-05, CI-RS-06, CI-RS-07, CI-RS-08, CI-RS-09, CI-RS-21 |
| T3 | CI-RS-01, CI-RS-02, CI-RS-10, CI-RS-11, CI-RS-12, CI-RS-13, CI-RS-19, CI-RS-20, CI-RS-22 |
| T4 | CI-RS-14, CI-RS-15, CI-RS-16, CI-RS-17, CI-RS-18 |
| T1, T5 | Независимые evidence для объединения этих exact sets |
| T6, T7 | Remote delivery и consumer proofs под указанными зависимостями |
