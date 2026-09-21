---
name: rule-ai-tooling
description: "AI-оснастка Kachō: канонический набор и lifecycle"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/ai-tooling.md`

# AI-оснастка Kachō: канонический набор и lifecycle

## Оснастка: экземпляр, счёт правил и доставка до агента

at-single-copy-no-rollout · единственный экземпляр в `.claude/` воркспейса; копий в рабочих копиях продукта не заводить · git ls-files продукта не содержит файлов оснастки · red: копия оснастки в дереве продукта
at-walker-derives-and-zero-is-failure · перечень целей выводить из дерева; ноль целей — отказ; объём осмотренного печатать всегда · kacho-workspace/scripts/vault-gate/run-all.sh · red: рукописный перечень; «пропущено» с кодом 0
at-unit-is-tracked-git-element · брать `git ls-files`, объявлять рядом с предикатом · scripts/skills-gate/check-07-declared-counts-match-tree.sh исполняет процитированную команду и сверяет · red: число из памяти; счёт по диску вместо индекса
at-two-numbers-one-predicate · величину, взятую двумя объявлениями, сверять одним предикатом · check-07 · red: два объявления одной величины разошлись
at-numbers-held-by-gate · числа правил/агентов/скилов держит гейт, не внимание · check-07, check-03 · red: число просрочено и не замечено
at-settings-without-permissions · не коммитить блок `permissions`/`defaultMode: bypassPermissions` — его место в `.claude/settings.local.json` (git игнорирует) · scripts/rules-gate/check-09-settings-no-bypass.sh · red: `grep -c permissions .claude/settings.json` не ноль — обход подтверждения принят за каждого, кто сделает клон
at-no-autoload-corpus · автозагрузки корпуса нет: `claudeMdExcludes`, в `CLAUDE.md` ни строки `@` · grep claudeMdExcludes .claude/settings.json · red: правило подгружено автозагрузкой
at-main-thread-is-agent · агент `dispatcher`, его тело — единственная база маршрутизации и обязано быть самодостаточным (`@import` в теле агента не раскрывается) · grep '"agent"' .claude/settings.json · red: @import в базе диспетчера
at-rule-preloaded-by-symlink · правило закреплено предзагрузкой: `SKILL.md` — символьная ссылка, агент несёт её в `skills:` · readlink, check-04 · red: правило не в окне агента
at-symlink-not-copy · символьная ссылка на файл правила, не копия · readlink .claude/skills/rule-<имя>/SKILL.md` = `../../rules/<имя>.md · red: копия правила в скиле
at-rule-star-is-binding · `rule-*` — привязка к правилу, не экспертиза; в перечень канонических скилов не входит · check-03 (исключение в гейте) · red: rule-* учтён как канонический скил
at-debt-three-gates-stale · `check-02` судит по снятой модели `@import` — до правки его вердикт недействителен · check-02 · red: вердикт о снятой модели принят за действующий
at-skills-roster · перечень канонических скилов (14, без `rule-*`) обязан совпадать с деревом в обе стороны · check-03 · red: строка без каталога либо каталог без строки
at-godzila-thirteenth · `godzila` отслеживается git и входит в перечень; приоритет ниже правил, выше локального `CLAUDE.md` · check-03 · red: отслеживаемый скил вне перечня
at-ci-clone-carries-no-tooling · клон продукта не несёт оснастку; CI-проверки — в его дереве, не в `.claude/` · ЗАВЕСТИ at-ci-clone-carries-no-tooling · red: клон без своей CI-проверки продукта
at-dead-asset-does-not-travel · ассет без предмета не заводить «про запас»; исключение обязано самоистекать · --check → STALE-EXCLUSION · red: мёртвый ассет на вид работающий
at-two-grep-engines · `grep` в Bash-инструменте агента и `grep` в скрипте — РАЗНЫЕ движки: харнесс определяет функцию-обёртку на встроенный ugrep 7.8.4 с `-G`, функция НЕ экспортируется, дочерний bash берёт GNU grep 3.12 · проба предпосылки в scripts/tooling-gate/inject.sh · red: вердикт команды, набранной руками, перенесён на скрипт или конвейер без перемера
at-handrun-predicate-engine-agnostic · выписанный для прогона руками предикат не ставит якорь ветвью альтернативы — `(^|X)` и `(?:^|X)` в обёртке молча не совпадают на части ширин; граница слова пишется `-P` просмотром назад либо `\b` · scripts/tooling-gate/check-10-handrun-predicate-survives-both-greps.sh · red: перепись построена на образце, который в обёртке всегда пуст, и пустота прочитана как факт
at-rule-address-as-written · ссылка на правило и на скил-привязку резолвится ТЕМ адресом, которым написана; архив целью не считается — он не грузится и `Skill` его не откроет · scripts/rules-gate/check-10-rule-address-exists-as-written.sh · red: путь корпуса ведёт в снятый файл, а гейт базовых имён печатает «ВИСИТ 0»
at-rule-address-debt-only-shrinks · остаток висячих адресов объявлен поимённо числом и может только сокращаться; запись, которой нечего исключать, — находка · `scripts/rules-gate/check-10-rule-address-exists-as-written.sh` + `scripts/rules-gate/rule-address-baseline.txt` (воркспейс; `check-10-*` в дереве ТРИ, имя без пути не адресует) · red: долг вырос молча либо база пережила свой предмет
at-markup-is-not-a-script · исключение по роли не выдаётся разметке, чем бы ни начинался файл, и файлу без строки запуска: `#!` в первых двух байтах исполнимости не доказывает, а перечень каталогов ту же дыру заводит заново — судится ФОРМАТ файла · `scripts/rules-gate/check-10-rule-address-exists-as-written.sh`, пары 2 и 4 в `inject-10-rule-address-exists-as-written.sh` (снятие барьера роняет пару 4) · red: корпус, агент, навык или корневой протокол изъял себя из переписи одной строкой

## Канонические агенты (единственный экземпляр — `.claude/agents/` воркспейса; копий нет)

at-agents-roster-dispatcher · главный поток — `dispatcher`: без Read/Bash/Edit, решает по возврату и своей самодостаточной базе · check-03 · red: диспетчер сам читает или правит файлы
at-agents-roster-execution · task-execution: 16 агентов, каждый — единственный держатель своей зоны правки · check-03 · red: зона правки без держателя либо с двумя
at-agents-roster-review · specialist-review: 10 ролей; `wave-reviewer` — один на волну, `convergence-reviewer` — держатель схождения · check-03 · red: посадка без ревью применимой ролью
at-agents-roster-boundary · границы задачи: 5 read-only ролей (scout…ci-watcher), кода не пишут · check-03 · red: роль-разведка правит код
at-agents-count-32 · счёт generic-агентов — 32 (31 исполнитель + dispatcher) · git ls-files .claude/agents/ | wc -l · red: перечень и число расходятся
at-executors-dont-launch-executors · у каждого агента, кроме `dispatcher`, `disallowedTools` содержит `Agent` · grep -rL disallowedTools .claude/agents/ · red: исполнитель запускает исполнителя
at-no-nested-launches · агент не зовёт другого напрямую — возвращает диспетчеру «нужен следующий» · check-05 · red: вложенный вызов агента из тела другого

> Счёт: **32** агентов — предикат `git ls-files .claude/agents/ | wc -l`.
> Перечень — адреса запуска, он сверяется с деревом в обе стороны (`check-03`):
> строка без файла и файл без строки — обе находки.

- `dispatcher` — выбирает агента под задачу и выставляет последовательность
- `acceptance-author` — пишет Given-When-Then acceptance-док (markdown, не код) ПЕРЕД любой новой работой
- `proto-sync` — синхронизирует/адаптирует `.proto` в `kacho-proto` (envelope flat-resources, package…
- `service-scaffolder` — скелет нового сервиса (cmd/internal/migrations/deploy/CI), без бизнес-логики
- `rpc-implementer` — реализует один RPC end-to-end строгим TDD (proto→migration→repo(sqlc)→handler→outbox→tests)
- `go-implementer` — не-RPC правка Go по TDD: багфикс, рефакторинг, corelib/pkg, конфиг, подписки и…
- `migration-writer` — goose SQL-миграции (JSONB/GIN/UNIQUE/EXCLUDE/CHECK/CAS/triggers)
- `api-gateway-registrar` — регистрирует новый public RPC в api-gateway (никогда Internal.* на external)
- `ui-implementer` — `ui-future/**`, включая красную playwright-пробу до фикса
- `integration-tester` — конвертит APPROVED-сценарии в падающие integration+e2e тесты (TDD red)
- `docs-writer` — `docs/**`: спека-книга, сайты документации компонентов, README
- `vault-scribe` — `obsidian/kacho/**`: trail задачи, узкие записки по ресурсам и рёбрам, vault-гейт
- `deploy-engineer` — `deploy/helm/**`, `values*.yaml`, `terraform/**`, стенд: подъём, выкатка, посев, провенанс…
- `tooling-maintainer` — `.claude/**`, `scripts/*-gate`, хуки, CI воркспейса
- `git-operator` — трекер и git: issue, метки, ветка и worktree, commit, push, PR, слияние (только после ✅…
- `load-tester` — нагрузочные замеры и сравнение прогонов
- `client-simulator` — имитация клиента с ПУСТЫМ контекстом (`00-kacho-core.md`, ban #18): без протокола и без…
- `acceptance-reviewer` — единственный gate APPROVED для acceptance-дока (не заказчик)
- `system-design-reviewer` — распределённые аспекты (dual-write, идемпотентность, OCC, реконсайл, replica-isolation)
- `db-architect-reviewer` — Postgres-схемы/миграции против `data-integrity.md`…
- `go-style-reviewer` — Go clean-code (error wrapping, ctx, slog, no panic в prod-path, thin handlers) плюс скил…
- `proto-api-reviewer` — proto-изменения: package naming, flat-resource envelope, `Get/List` sync +…
- `ui-reviewer` — пост-дифф ревью `ui-future/**` по нормам, которые не держатся тестами
- `qa-test-engineer` — расширяет regression-suite (Newman) против acceptance/спеки как источника истины
- `security-auditor` — поверхность безопасности до кода, раунды аудита, модель прав, публичный текст на…
- `wave-reviewer` — **единственный, кто видит диффы всех полос РЯДОМ**: принимает их за один заход, ОДИН раз на…
- `convergence-reviewer` — **единственная** роль, создающая финальную запись схождения перед посадкой: сверяет…
- `scout` — read-only разведка для диспетчера: состояние дерева, веток, стенда, конвейера и трекера
- `class-exposure-analyst` — запускается ПЕРЕД первой строкой кода по APPROVED-приёмке или сформулированному замыслу:…
- `landing-reviewer` — запускается ПЕРЕД посадкой (коммит, мёрж, squash, cherry-pick, push, закрытие тикета) и при…
- `check-verifier` — приёмка работ-проверок ЭКСПЕРИМЕНТОМ: вернуть дефект, предъявить законный близнец,…
- `ci-watcher` — читает вердикт конвейера и разбирает красное по корням в трёх категориях, перезапускает…

## Канонические скилы (`.claude/skills/<name>/SKILL.md`)

Единица перечня — отслеживаемый git-каталог скила, кроме привязочных `rule-*`:
`git ls-files .claude/skills/ | cut -d/ -f3 | sort -u | grep -v '^rule-' | wc -l` (**14**).
Перечень обязан совпадать с выводом в обе стороны (`check-03`); `<svc>-load-testing`
живёт в репо сервиса и в счёт не входит.

- `evgeniy` (workspace) — Go-архитектура kacho-*
- `code-authoring` (workspace) — семантика прод-кода в момент написания
- `testing-code-coach` (workspace) — unit/integration против прод-кода
- `testing-product-coach` (workspace) — black-box против развёрнутого стенда, включая Newman
- `load-testing-coach` (workspace) — методология нагрузки
- `kacho-docs-writer` (workspace) — регламент документации Kachō
- `hardening-audit-loop` (workspace) — аудит-рефакторинг до сходимости: 6 дименсий, 9 инвариантов Kachō как определение «дефекта»
- `measurement-discipline` (workspace) — как получить число или факт о дереве, стенде и чужой работе, который выдержит проверку
- `gate-authoring` (workspace) — как построить проверку, СПОСОБНУЮ упасть
- `verdict-and-landing` (workspace) — как прочесть полученный исход и внести изменение
- `security-surface` (workspace) — поверхность безопасности сервиса
- `doc-truthfulness` (workspace) — долговечность утверждения в документе
- `godzila` (workspace) — готовые ШАБЛОНЫ КОДА kachō-стиля
- `change-graph` (workspace) — контур Kachō Change Graph
- `<svc>-load-testing` (repo) — конкретные нагрузочные сценарии сервиса

## Lifecycle, который ОБЯЗАН удовлетворяться (gates для автономной разработки)

at-lifecycle-preamble · порядок lifecycle выставляет диспетчер по возвратам; шаг не запускает следующий сам · check-05 · red: шаг цепляет следующий без диспетчера
lc1-acceptance-first · новая работа — только после APPROVED Given-When-Then; без APPROVED не кодить (ban #1) · docs-gate check-01 · red: код без APPROVED-приёмки
lc2-issue-branch-trail · фича — issue + ветка `issue-<N>` + trail в vault · docs-gate check-02 · red: код без issue, ветки или trail
lc4-crossrepo-order · вести в порядке proto → corelib → сервис → api-gateway → deploy → docs; `replace` на свои модули не заводить · go list -deps ./... по каждому модулю зелен, grep replace github.com/PRO-Robotech go.mod пусто · red: сервис собран против несуществующего контракта
lc5-tdd-red-before-code · падающая проба ДО кода, integration и newman в том же PR · kacho/tests/newman (assert-suites-green.sh) · kacho-workspace/scripts/docs-gate/ · red: проба, не падавшая ни разу
lc6-role-reviews · провести ревью четырьмя ролями (proto-api-reviewer, db-architect-reviewer, go-style-reviewer, system-design-reviewer) плюс <svc>-conventions-auditor · ЗАВЕСТИ lc6-role-reviews · red: посадка при неполном множестве ролей
lc7-final-verification · go test ./... -race · golangci-lint run · govulncheck · make audit-list-filter · newman — все зелёные · .github/workflows/ci.yaml даёт зелёный по всем поимённым контекстам · red: вердикт по подмножеству
lc8-trail-and-close · обновить vault (resources/rpc/edges + записка) и закрыть issue с артефактами · vault-gate, docs-gate check-02 · red: issue закрыт без trail

## Сторонние агенты/скилы (использовать, не пересоздавать)
