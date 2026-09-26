# Архив: ai-tooling.md

Снято 2026-09-20. Норма живёт в `.claude/rules/ai-tooling.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.

## Компрессия в строковую форму (2026-09-20, ветка rules/corpus-200k-w3)

Ниже — записи описи `inventory-2026-09-19.json` для `ai-tooling.md`, не вошедшие
строкой в корпус (класс C/D без названного гейта, либо явно снятая история).
Каждая — id описи, дословная первая фраза источника и её судьба.

- **at-preamble** — «Проект разрабатывается, тестируется и сопровождается автономно
  через Claude Code.» Вводный абзац без предиката; предмет (структура оснастки)
  переизложен заголовком корпуса.
- **at-old-duplication-note** — «Прежняя модель дублирования снята — и её обоснование
  было ЛОЖНЫМ.» История отменённой раскатки и замер 2026-08-02; действующие
  требования из этого блока («перечень выводится из дерева», «ноль целей — отказ»)
  уже строкой `at-walker-derives-and-zero-is-failure`.
- **at-edit-only-in-workspace** — «Правишь оснастку → только в `.claude/` воркспейса.»
  Переизлагает предмет `at-single-copy-no-rollout`; второе место об одном факте.
- **at-unit-of-count-diverged** — «Единица счёта здесь разошлась — и расхождение
  СНЯТО, а не объяснено.» Закрытый исторический инцидент (rag.md, 18↔19), без
  действующего предиката.
- **at-nineteen-historical** — «Девятнадцать выше — историческое число, и оно уже не
  действует.» Само себя объявляет неактуальным; текущее число (30) держит гейт, не
  абзац.
- **at-three-overdue-note** — «Три просрочки подряд — ОДИН класс, и держателя у него
  не было.» Постмортем трёх просрочек; вывод («числа держит гейт») уже строкой
  `at-numbers-held-by-gate`.
- **at-domain-agents-native** — «Domain-агенты/скилы (`vpc-*`, `compute-*`,
  `<svc>-load-testing`) — НАТИВНЫЕ в своём репо.» Без гейта на предикат (перечень
  доменов выводится из `services/*`); k=C, hold=вниманием.
- **at-why-exclude-not-move** — «Почему исключение, а не перенос каталога.»
  Рационале выбора `claudeMdExcludes`; не предикат, а объяснение решения
  2026-09-17.
- **at-conditional-rule-by-skill** — «Условное правило — инструментом `Skill`, и это
  единственное место, где модель держится вниманием.» Явно вне гейта по тексту
  источника; k=C, hold=вниманием (опись: слить с другой — не слито, оставлено здесь
  ради бюджета строк).
- **at-session-without-dispatcher** — «Сессия без диспетчера, если она нужна
  человеку: `claude --agent <имя исполнителя>`.» Описание обходного пути, не норма
  продукта; без гейта.
- **at-probe-output-not-captured** — «На чём здесь держится каждое утверждение — и
  чего у этой пробы нет.» Оговорка о непойманном выводе пробы `claude -p`; предикаты
  таблицы выше уже застроены отдельными нормами.
- **at-cost-per-agent-elsewhere** — «Цена модели считается НА АГЕНТА — по его
  закреплённому набору.» Указатель на другой файл (`01-wave-contract.md`); предмет
  там же и норма, если нужна, — его.
- **at-claude-code-mechanics** — «CLAUDE.md — загружается из cwd + parent-walkup;
  `@import` подтягивает файлы.» Справочная механика платформы (замер пробой); её
  действующие следствия уже строками `at-main-thread-is-agent`,
  `at-rule-preloaded-by-symlink`, `at-no-nested-launches`.
- **at-agents-roster-domain** — «Domain-specific (в `project/kacho/.claude/agents/`)
  — только узкая экспертиза.» Без гейта (k=D, gate=None); домены сверяются иначе,
  чем generic-перечень check-03.
- **at-six-skills-seam** — «Шесть скилов делят один шов и не пересекаются по
  построению.» Разбор границ предметов шести скилов; описательно, без предиката.
- **lc3-context-from-vault** — «Контекст из vault — перед кодом прочитать узкий
  `resources/`/`rpc/`/`edges/` файл.» Шаг 3 lifecycle без названного гейта (k=C,
  hold=вниманием); соседние шаги 1,2,4-8 — строки корпуса.
- **at-third-party-agents** — «`Explore`, `Plan`, `general-purpose`,
  `claude-code-guide` (вопросы про Claude Code/SDK/API), `superpowers:*`
  (code-reviewer, brainstorming, writing-plans, test-driven-development,
  systematic-debugging).» Перечень сторонних инструментов; без гейта на состав
  (k=C, hold=вниманием), заголовок-адрес «Сторонние агенты/скилы» в корпусе цел.

## Снято 2026-09-24 (ws#832): поштучный вердикт задачи (ws#829) → агрегат

Решение владельца 2026-09-24: «Пересмотри весь флоу с ориентиром на 1) приоритет написания кода 2) тестирование агрегатами а не каждую таску отдельно 3) контроль за оперативной памятью не должна переваливать за 45гб». Прежние редакции строк — дословно:

lc7-final-verification · go test ./... -race, golangci-lint run, govulncheck, make audit-list-filter, newman — все зелёные на PR задачи в ветку волны; сборку волны гонит local (`testing.md#final-verification-before-merge`) · .github/workflows/ci.yaml даёт зелёный по всем поимённым контекстам · red: вердикт по подмножеству

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**at-claim-about-own-check-runs-or-lies** — прежняя редакция:

at-claim-about-own-check-runs-or-lies · утверждение об оснастке, проверяемое только ИСПОЛНЕНИЕМ названного предмета, пиши с координатой, которую резолвит обход, и со знаменателем самого обхода; числа этого класса не выписывай — их печатает прибор · scripts/tooling-gate/measure-claims-about-checks.py · red: держатель назван, артефакта под этим именем нет; «не найдено» напечатано без числа осмотренного

**at-bypass-not-from-repo-layer** — прежняя редакция:

at-bypass-not-from-repo-layer · режим обхода из проектного и локального (`.claude/settings.local.json`) слоёв харнесс игнорирует — оба repo-controllable; даёт его только личный `~/.claude/settings.json`, policy или флаг · claude --debug-file <лог> -p … → нет строки `settings defaultMode "bypassPermissions" ignored`; `[session-notices] mode=bypassPermissions` (измерено 2026-09-21, CC 2.1.278) · red: объявление режима лежит в дереве, подтверждения продолжают приходить

**at-two-grep-engines** — прежняя редакция:

at-two-grep-engines · `grep` в Bash-инструменте агента и `grep` в скрипте — РАЗНЫЕ движки: харнесс определяет функцию-обёртку на встроенный ugrep 7.8.4 с `-G`, функция НЕ экспортируется, дочерний bash берёт GNU grep 3.12 · проба предпосылки в scripts/tooling-gate/inject.sh · red: вердикт команды, набранной руками, перенесён на скрипт или конвейер без перемера

**at-handrun-predicate-engine-agnostic** — прежняя редакция:

at-handrun-predicate-engine-agnostic · выписанный для прогона руками предикат не ставит якорь ветвью альтернативы — `(^|X)` и `(?:^|X)` в обёртке молча не совпадают на части ширин; граница слова пишется `-P` просмотром назад либо `\b` · scripts/tooling-gate/check-12-handrun-predicate-survives-both-greps.sh · red: перепись построена на образце, который в обёртке всегда пуст, и пустота прочитана как факт

**at-markup-is-not-a-script** — прежняя редакция:

at-markup-is-not-a-script · исключение по роли не выдаётся разметке, чем бы ни начинался файл, и файлу без строки запуска: `#!` в первых двух байтах исполнимости не доказывает, а перечень каталогов ту же дыру заводит заново — судится ФОРМАТ файла · `scripts/rules-gate/check-11-rule-address-exists-as-written.sh`, пары 2 и 4 в его инъекции · red: корпус, агент, навык или корневой протокол изъял себя из переписи одной строкой

**перечень канонических агентов** — прежняя редакция (описания — копии `description` файлов агентов):

- `dispatcher` — выбирает агента под задачу и выставляет последовательность
- `acceptance-author` — пишет Given-When-Then acceptance-док ПЕРЕД новой работой
- `proto-sync` — синхронизирует и адаптирует `.proto`
- `service-scaffolder` — скелет нового сервиса, без бизнес-логики
- `rpc-implementer` — один RPC end-to-end строгим TDD
- `go-implementer` — не-RPC правка Go по TDD: багфикс, рефакторинг, corelib/pkg, конфиг
- `migration-writer` — goose SQL-миграции
- `api-gateway-registrar` — новый public RPC в api-gateway; никогда Internal.* наружу
- `ui-implementer` — `ui-future/**`, включая красную playwright-пробу до фикса
- `integration-tester` — APPROVED-сценарии в падающие integration+e2e пробы (TDD red)
- `docs-writer` — `docs/**`: спека-книга, сайты документации компонентов, README
- `vault-scribe` — `obsidian/kacho/**`: trail задачи, записки, vault-гейт
- `deploy-engineer` — `deploy/helm/**`, `terraform/**`, стенд: подъём, выкатка, посев
- `tooling-maintainer` — `.claude/**`, `scripts/*-gate`, хуки, CI воркспейса
- `git-operator` — трекер и git: issue, метки, ветка, commit, push, PR, слияние
- `load-tester` — нагрузочные замеры и сравнение прогонов
- `client-simulator` — имитация клиента с ПУСТЫМ контекстом (ban #18)
- `acceptance-reviewer` — единственный gate APPROVED для acceptance-дока (не заказчик)
- `system-design-reviewer` — распределённые аспекты: dual-write, идемпотентность, OCC, реконсайл
- `db-architect-reviewer` — Postgres-схемы и миграции против `data-integrity.md`
- `go-style-reviewer` — Go clean-code: error wrapping, ctx, slog, thin handlers
- `proto-api-reviewer` — proto-изменения: именование пакета, envelope, sync-vs-Operation
- `ui-reviewer` — пост-дифф `ui-future/**` по нормам, которые не держат пробы
- `qa-test-engineer` — расширяет regression-suite (Newman) против приёмки и спеки
- `security-auditor` — поверхность безопасности до кода, раунды аудита, модель прав
- `wave-reviewer` — **единственный, кто видит диффы всех полос РЯДОМ**, ОДИН раз на волну
- `convergence-reviewer` — **единственная** роль записи схождения перед посадкой
- `scout` — read-only разведка для диспетчера: дерево, ветки, стенд, конвейер, трекер
- `class-exposure-analyst` — запускается ПЕРЕД первой строкой кода по APPROVED-приёмке
- `landing-reviewer` — запускается ПЕРЕД посадкой: коммит, мёрж, squash, push, закрытие
- `check-verifier` — приёмка работ-проверок ЭКСПЕРИМЕНТОМ, а не прочтением
- `ci-watcher` — вердикт конвейера, разбор красного по корням в трёх категориях

(второй проход того же сжатия)

**at-bypass-not-from-repo-layer** — прежняя редакция:

at-bypass-not-from-repo-layer · режим обхода из проектного и локального (`.claude/settings.local.json`) слоёв харнесс игнорирует — оба repo-controllable; даёт его только личный `~/.claude/settings.json`, policy или флаг · `claude --debug-file <лог> -p …`: строка `settings defaultMode "bypassPermissions" ignored` (замер 2026-09-21, CC 2.1.278) · red: объявление режима лежит в дереве, подтверждения продолжают приходить

**at-handrun-predicate-engine-agnostic** — прежняя редакция:

at-handrun-predicate-engine-agnostic · выписанный для прогона руками предикат не ставит якорь ветвью альтернативы (`(^|X)`, `(?:^|X)` в обёртке молча не совпадают); границу слова пиши `-P` просмотром назад либо `\b` · scripts/tooling-gate/check-12-handrun-predicate-survives-both-greps.sh · red: перепись на образце, в обёртке всегда пустом, и пустота прочитана как факт

**at-claim-about-own-check-runs-or-lies** — прежняя редакция:

at-claim-about-own-check-runs-or-lies · утверждение об оснастке, проверяемое только ИСПОЛНЕНИЕМ предмета, пиши с координатой, которую резолвит обход, и со знаменателем обхода; числа этого класса печатает прибор, не выписывай · scripts/tooling-gate/measure-claims-about-checks.py · red: держатель назван, артефакта под этим именем нет; «не найдено» без числа осмотренного

(второй проход того же сжатия)

**at-rule-address-debt-only-shrinks** — прежняя редакция:

at-rule-address-debt-only-shrinks · остаток висячих адресов объявлен поимённо числом и может только сокращаться; запись, которой нечего исключать, — находка · `scripts/rules-gate/check-11-rule-address-exists-as-written.sh` вместе с `scripts/rules-gate/rule-address-baseline.txt` · red: долг вырос молча либо база пережила свой предмет

**at-rule-address-as-written** — прежняя редакция:

at-rule-address-as-written · ссылка на правило и на скил-привязку резолвится ТЕМ адресом, которым написана; архив целью не считается — он не грузится и `Skill` его не откроет · scripts/rules-gate/check-11-rule-address-exists-as-written.sh · red: путь корпуса ведёт в снятый файл, а гейт базовых имён печатает «ВИСИТ 0»

**at-two-grep-engines** — прежняя редакция:

at-two-grep-engines · `grep` в Bash-инструменте агента и в скрипте — РАЗНЫЕ движки: обёртка харнесса на ugrep с `-G` не экспортируется, дочерний bash берёт GNU grep · проба предпосылки в scripts/tooling-gate/inject.sh · red: вердикт команды, набранной руками, перенесён на скрипт или конвейер без перемера

(второй проход того же сжатия)

**at-markup-is-not-a-script** — прежняя редакция:

at-markup-is-not-a-script · исключение по роли не выдаётся разметке и файлу без строки запуска: судится ФОРМАТ файла, а не `#!` и не перечень каталогов · `scripts/rules-gate/check-11-rule-address-exists-as-written.sh`, пары 2 и 4 его инъекции · red: корпус, агент, навык или корневой протокол изъял себя из переписи одной строкой

**перечень канонических скилов** — прежняя редакция (описания — копии `description` из `SKILL.md`):

- `evgeniy` (workspace) — Go-архитектура kacho-*
- `code-authoring` (workspace) — семантика прод-кода в момент написания
- `testing-code-coach` (workspace) — unit/integration против прод-кода
- `testing-product-coach` (workspace) — black-box против развёрнутого стенда, включая Newman
- `load-testing-coach` (workspace) — методология нагрузки
- `kacho-docs-writer` (workspace) — регламент документации Kachō
- `hardening-audit-loop` (workspace) — аудит-рефакторинг до сходимости: 6 дименсий, 9 инвариантов
- `measurement-discipline` (workspace) — как получить число о дереве, стенде и чужой работе
- `gate-authoring` (workspace) — как построить проверку, СПОСОБНУЮ упасть
- `verdict-and-landing` (workspace) — как прочесть исход и внести изменение
- `security-surface` (workspace) — поверхность безопасности сервиса
- `doc-truthfulness` (workspace) — долговечность утверждения в документе
- `godzila` (workspace) — готовые ШАБЛОНЫ КОДА kachō-стиля
- `change-graph` (workspace) — контур Kachō Change Graph
- `<svc>-load-testing` (repo) — нагрузочные сценарии сервиса
