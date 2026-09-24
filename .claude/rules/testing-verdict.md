---
name: rule-testing-verdict
description: "Чтение вердикта прогона"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/testing-verdict.md`

# Чтение вердикта прогона

## 0. Чтение вердикта: сначала ОБЛАСТЬ, потом причина

scope-before-cause-revision · установи РЕВИЗИЮ проверяемого — провенанс по образу запущенного контейнера · docker inspect образа стенда · red: причина названа без ревизии
scope-before-cause-branch-touched · спроси, тронуты ли твоей веткой упавшие пробы · git diff origin/main...HEAD -- <файл пробы> · red: регрессию ищут там, где её не могло быть
scope-before-cause-what-it-calls · прочитай, к чему обращается упавшее утверждение — край, консоль, база · ЗАВЕСТИ scope-before-cause-what-it-calls · red: «правил вёрстку, а падал запрос к API»
second-hypothesis-without-measurement · запрещена без замера по первой; не спускайся уровнем ниже, не исчерпав верхний · ЗАВЕСТИ second-hypothesis-without-measurement · red: две гипотезы, ноль замеров
red-report-names-revision · назови в нём ревизию проверяемого · ЗАВЕСТИ red-report-names-revision · red: область не установлена — сказанное о причине про неизвестно что

## 1. Диагноз ставится по ТЕКСТУ отказа

diagnosis-from-refusal-text · ставь по run.failures[].error.message и executions[].response.stream в out/<коллекция>.json; перечень имён шагов диагнозом не является · вниманием (цитата из out/<коллекция>.json) · red: фикс по названию шага, число падений не изменилось
precondition-guard-names-subject · ставь страж предусловия: не отправляй запрос и назови предмет · TestNewmanPrecondMark_ProvenByInjection · red: дефект проявляется отказом уборки по фантому на три шага позже
quote-refusal-text-in-report · процитируй текст отказа · ЗАВЕСТИ quote-refusal-text-in-report · red: не можешь процитировать — значит не читал
artifact-read-its-text-first · прочитай текст НА нём, потом объясняй картинку · ЗАВЕСТИ artifact-read-its-text-first · red: вывод сделан из вида, цитат ноль

## Прогон на исчерпанном ресурсе — третья категория

exhausted-run-is-third-category · считай прогон НЕДЕЙСТВИТЕЛЬНЫМ: вердикта нет ни у одной пробы, перепрогони целиком · scripts/ci-local.sh код 3 · red: «0 находок» при ненулевом коде прочитано как зелёное
exhaustion-corrupts-inflight-git · после срыва сделай перепись: размер .git/index, git ls-files · wc -l против git ls-tree -r HEAD · red: эти команды | дерево выглядит исправным, неверен только граф
local-runner-exit-code-3 · различай коды 0 / 1 / 3 (недействителен); исчерпание распознавай по журналу шага, не по коду инструмента · scripts/ci-local.sh · red: оборванный шаг записан в упавшие
read-dollar-question · читай $?, а не строку · echo $? после прогона · red: код 3 выглядит дословно как код 0
busy-machine-step-zero · шаг 0 перед тяжёлым прогоном и отправкой (решение владельца 2026-09-24): тяжёлое — только `scripts/heavy-slot.sh <класс> -- <команда>`: вход по (MemTotal − MemAvailable) + недобранное занятыми + бюджет ≤ 45 ГиБ, строгая очередь, golangci-lint (классы lint, ci-local) по одному на машину, ожидание — 1800 с, затем 75, ручек `HEAVY_SLOT_*` над настоящей памятью нет; `systemd-run` и `--scope` в argv — 64; 75 и 76 (оборвано пределом памяти) — «не выполнилось»; место — `df -h /` · scripts/heavy-slot-inject.sh; .claude/hooks/heavy-guard/prove.sh · red: тяжёлая команда без слота; «не выполнилось: машина занята» без кода 75; код 76 прочитан красным
heavy-guard-is-reminder · страж heavy-guard — напоминание против случайных форм, а не барьер: предел держит cgroup (слот, потолок сессии); граница стража — перечень `BOUNDARY` в guard.py: переменная вне строки, программа из подстановки, текст оболочке трубой или подстановкой, файл, записанный и запущенный той же строкой, строка одним словом у незнакомой обёртки, `$@` скрипта, запуск из другого языка, `go env -w`, alias, `npm test` · .claude/hooks/heavy-guard/prove.sh: пример границы — [BOUND], пойманный — [FAIL] · red: обход стража назван «защищено»; пример границы засчитан зелёным
session-memcap · потолок сессии — MemoryMax её scope = max(8 ГиБ, 45 ГиБ − занятое вне scope − бюджет docker), swap 0, без MemoryHigh; ставит хук SessionStart, отказ — anon + 4 ГиБ ≥ потолка либо OOMPolicy ≠ continue; терминал заводит scope со stop — сессия с потолком запускается `scripts/session-memcap.sh --launch -- claude`; метку oomd `user.oomd_omit=1` хук пишет на свой scope прямой записью xattr и сверяет чтением — и при отказе потолка; убийцу в пробе oomd называет журнал по имени unit, не код 137 · scripts/session-memcap-inject.sh · red: MemoryMax на scope со stop — первое OOM-убийство снимает всю сессию; потолок или метка названы без сверки по cgroup; 137 от ядра засчитан oomd

## Кэш: сохраняй только на доказанно полном исходе

cache-saved-only-on-proven-complete · сохраняй только при доказанно ПОЛНОМ исходе шага; условие шага проверяй по наличию предмета, не по попаданию в кэш · TestCacheFillsOnTheRunThatPaidForIt · red: шаг пропущен «кэш попал», следующий падает «файла нет»
cache-restore-save-split-paid-run · разделяй cache/restore и cache/save; сохраняй по признаку полноты от самого шага · TestCacheFillsOnTheRunThatPaidForIt · red: кэш наполняется только прогоном, которому он не был нужен
cache-condition-carries-state-function · несёт функцию состояния: always(), !cancelled(), failure(); save-always не годится · TestCacheFillsOnTheRunThatPaidForIt · red: условие без функции состояния — подразумевается success()
remedy-tested-on-its-own-failure · проверь на том исходе, ради которого заведено, — в том числе на своём отказе · ЗАВЕСТИ remedy-tested-on-its-own-failure · red: мера переворачивается ровно на нужном исходе

## 4. Проба не имеет права падать на ДОСТИЖЕНИИ СВОЕЙ ЦЕЛИ

probe-passes-on-empty-ledger · на ПУСТОМ перечне проходи, объявляя перепись «записей 0», а не падай · TestBakedLedgerInjection_AnEmptyLedgerIsTheGoalNotAFailure · red: текст отказа «ведомость пуста — проверять нечего»
fail-ability-proven-on-synthetic · доказывай ОТДЕЛЬНОЙ пробой на синтетике, объём — переписью · *_injection_test.go · red: «ноль находок» неотличимо от «ноль прочитанного»

## 5. Фикстура пробы, привязанная к снимаемому предмету, истекает вместе с ним

twin-fixture-independent-of-subject · привязывай к тому, что живёт НЕЗАВИСИМО от предмета запрета · TestCarrierPredicateSeesTheSubjectAndSpacesTheTwin · red: проба краснеет на исчезновении своей фикстуры

## Локальный прогон: тот же инструмент, версия и подготовка

local-run-same-tool-and-version · значит что-то лишь при том же инструменте, той же версии (пин workflow, go.mod) и воспроизведённой подготовке шага · scripts/ci-local.sh · red: локально зелено, в конвейере красно на том же коммите
ci-local-installs-like-workflow · ставь инструменты теми же командами, что workflow; расхождение — находка · сверка ci-local.sh с .github/workflows · red: плагин из системы вместо модуля
render-provenance-of-dependencies · собирай зависимости в ЭТОМ клоне, не копируй из соседнего · ЗАВЕСТИ render-provenance-of-dependencies · red: проба падает на утверждении, которое ты минуту назад видел выполненным
runner-takes-all-arguments · бери ВСЕ аргументы; сверь число исполненных проверок с числом запрошенных групп · TestNewmanRunnerDerivesItsCollectionSet · red: «исполнено 3, отказов 0» вместо 20
job-composition-count-run-steps · не равно «прогнал джобу»: открой объявление и посчитай шаги run: · подсчёт run: в .github/workflows · red: падает последний шаг, а имя джобы называет первый предмет
runner-prints-what-it-ran · печатай ЧТО прогнал, а не только сколько · TestNewmanRunnerDerivesItsCollectionSet · red: малое число исполненного не замечено

## Фильтр лога проверяется на одном известном падении

log-filter-verified-on-known-failure · проверь на ОДНОМ заведомо упавшем шаге, что видна хотя бы одна строка текста отказа · ЗАВЕСТИ log-filter-verified-on-known-failure · red: видны имена упавших шагов и ни одной строки причины
read-the-file-not-the-command-output · открывай файл целиком (wc -l), а не улучшай выражение · ЗАВЕСТИ read-the-file-not-the-command-output · red: префикс имени задания, tail, фоновый вызов, якорь ^ съели диагностику
pipestatus-not-pipe-exit-code · tail · читай ${PIPESTATUS[0]} либо пиши в файл и бери код напрямую · red: TestPipefailVerdictNeverComesFromAPipe | «код 0» после трубы прочитан как успех
ask-which-step-failed · спроси имя упавшего шага: gh api repos/<o>/<r>/actions/jobs/<id> -q '.steps[] · select(.conclusion=="failure") · red: .name' | эта команда | локально перебраны шесть зелёных шагов

## Колонки чужого вывода — по имени, не по номеру

columns-by-name-not-position · проси поля по имени (-o jsonpath, --custom-columns, --format, --json), не режь по позиции · отсутствие awk '{print $N}' · red: пятое поле взято как возраст, а это перезапуски

## 9. Гейт судит КОММИТ, а работа лежит в ИНДЕКСЕ

pr-red-belongs-to-revision-headsha · сверяй headSha прогона с головой ветки, а не имя проверки с состоянием · TestWorkflowRunUsesTheSubjectCommit · red: прежние проверки висят красными после отправки починки
delta-gate-asks-the-commit · спрашивай о коммите (origin/main...HEAD); закоммить, потом прогоняй · git diff --name-only --diff-filter=A origin/main...HEAD · red: пусто при непустом рабочем дереве
asm-verdict-runs-on-head · вердикт сборки и каждой её задачи бери из прогонов на голове PR сборки в ветку волны: последний прогон КАЖДОГО процесса PR (`git-issues.md#gi-pr-manual-dispatch`) при headSha = голова; своего прогона у задачи нет (решение владельца 2026-09-24); проверки PR (`gh pr checks`, `statusCheckRollup`) ручного запуска не видят · `gh run list -R <репо> --commit <headSha> --json workflowName,status,conclusion` · red: вердикт задачи взят её поштучным или локальным прогоном; «no checks reported» у `gh pr checks` прочитано как отсутствие прогона
no-run-on-head-not-green · процесс PR без прогона на голове — не зелёный: запусти его вручную (`git-issues.md#gi-pr-manual-dispatch`) и читай тем же прибором, что `asm-verdict-runs-on-head` · тот же `gh run list -R <репо> --commit <headSha> --json workflowName,status,conclusion` против перечня процессов PR · red: «проверок 0» прочитано как «замечаний нет»; процесс без прогона на голове не назван

## Расхождение двух прогонов — разные предметы

two-runs-different-subjects · сперва установи, ЧТО мерил каждый (множество пакетов), потом спрашивай, кто прав · ЗАВЕСТИ two-runs-different-subjects · red: расхождение объяснено чужой ошибкой

## Фоновая команда сообщает код обёртки

background-task-exit-code-is-wrapper · читай исход из её собственного вывода, не из уведомления о завершении; предел ставь по длительности предмета · grep Terminated/143/137 в файле · red: «exit code 0» при SIGTERM внутри

## 12. Правило берётся из КАНОНА, а не из формы соседних файлов

form-from-canon-not-neighbours · бери из документа, её объявляющего; канона нет — скажи это в отчёте · TestNewMigrationOutranksEveryAppliedOne · red: на «почему так названо» ответ «как у соседних»

## Чужой предикат прогоняется дословно

foreign-predicate-run-verbatim · исполняй ДОСЛОВНО, копией строки; не пересобирай под свой шелл · ЗАВЕСТИ foreign-predicate-run-verbatim · red: вложение в $( ) с экранированием дало 0 вместо 18

## 14. Твой СОБСТВЕННЫЙ разборщик — тоже распознаватель

own-parser-knows-all-forms · подчиняй тому же требованию, что гейт: знать все законные формы · ЗАВЕСТИ own-parser-knows-all-forms · red: твоё число меньше чужого
count-forms-before-naming-number · спроси, в скольких формах предмет записывается законно и знает ли о них твоё выражение · ЗАВЕСТИ count-forms-before-naming-number · red: пропущена многострочная метка или голое число в ряду

### Это не редкость, а РУТИНА

divergence-check-own-parser-first · проверяй СВОЙ разборщик первым, а не чужую работу · ЗАВЕСТИ divergence-check-own-parser-first · red: расхождение объяснено ошибкой автора
same-method-twice-is-not-evidence · считай свидетельством только при РАЗНЫХ выражениях · ЗАВЕСТИ same-method-twice-is-not-evidence · red: «посчитали дважды» названо проверкой
task-gives-question-not-number · давай вопросом и требуй «перемерь» · ЗАВЕСТИ task-gives-question-not-number · red: число дано фактом — исполнитель разбирается с ним после выбора направления
parser-discards-known-form · сперва проверь, знает ли он её и ОТБРАСЫВАЕТ · ЗАВЕСТИ parser-discards-known-form · red: пополнение словаря закрыло экземпляр, отбрасывание осталось
ask-parser-directly-about-input · спроси распознаватель НАПРЯМУЮ о входе, а не о его исходе · python3 -c 'import mod; print(mod.direction(...))' · red: «не читается» при живом слове словаря = прочитано и погашено
fix-the-guard-measure-its-radius · чини охрану, не словарь, и мерь её радиус по дереву ДО правки · ЗАВЕСТИ fix-the-guard-measure-its-radius · red: «сузил» неотличимо от «сузил слишком сильно»

## Предикат снятия обещания знает все его формулировки

promise-removal-knows-all-forms · ищи по ВСЕМ формулировкам; в отчёте назови перечень форм и счёт по каждой · internal/repohygiene/deferredwork_test.go · red: «исправлено 4» без перечня форм

## Флаг принадлежит своей программе

flag-belongs-to-its-program · принадлежит ТОЙ программе, которой передан; у git grep отбор задаётся pathspec после -- · ЗАВЕСТИ flag-belongs-to-its-program · red: sort | uniq -c по составу | фильтруешь по типу, а в выводе другие типы
finding-born-from-way-of-looking · роди из дерева, не из способа смотреть: повтори свой же замер · ЗАВЕСТИ finding-born-from-way-of-looking · red: обрыв head -2, неверная единица счёта, окно sed со смещением на глаз
