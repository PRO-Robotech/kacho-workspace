---
name: rule-ai-tooling
description: "AI-оснастка Kachō: канонический набор и lifecycle"
---

**Архив:** `.claude/backup/ai-tooling.md`

## Оснастка: экземпляр, счёт правил и доставка до агента

at-single-copy-no-rollout · единственный экземпляр в `.claude/` воркспейса; копий в рабочих копиях продукта не заводить · git ls-files продукта не содержит файлов оснастки · red: копия оснастки в дереве продукта
at-walker-derives-and-zero-is-failure · перечень целей выводить из дерева; ноль целей — отказ; объём осмотренного печатать всегда · kacho-workspace/scripts/vault-gate/run-all.sh · red: рукописный перечень; «пропущено» с кодом 0
at-unit-is-tracked-git-element · брать `git ls-files`, объявлять рядом с предикатом · scripts/skills-gate/check-07-declared-counts-match-tree.sh исполняет процитированную команду и сверяет · red: число из памяти; счёт по диску вместо индекса
at-two-numbers-one-predicate · величину, взятую двумя объявлениями, сверять одним предикатом · check-07 · red: два объявления одной величины разошлись
at-numbers-held-by-gate · числа правил/агентов/скилов держит гейт, не внимание · check-07, check-03 · red: число просрочено и не замечено
at-claim-about-own-check-runs-or-lies · утверждение об оснастке, проверяемое только ИСПОЛНЕНИЕМ предмета, пиши с координатой, которую резолвит обход, и со знаменателем обхода; такие числа печатает прибор · scripts/tooling-gate/measure-claims-about-checks.py · red: держатель назван, артефакта нет; «не найдено» без числа осмотренного
at-settings-without-permissions · не коммитить блок `permissions`/`defaultMode: bypassPermissions` — выбор за каждого, кто сделает клон · scripts/rules-gate/check-09-settings-no-bypass.sh · red: `grep -c permissions .claude/settings.json` не ноль
at-bypass-not-from-repo-layer · режим обхода из проектного и локального слоёв харнесс игнорирует (оба repo-controllable); даёт его только личный `~/.claude/settings.json`, policy или флаг · claude --debug-file <лог> -p … → нет строки `settings defaultMode "bypassPermissions" ignored`; `[session-notices] mode=bypassPermissions` (измерено 2026-09-21, CC 2.1.278) · red: объявление режима лежит в дереве, подтверждения продолжают приходить
at-no-autoload-corpus · автозагрузки корпуса нет: `claudeMdExcludes`, в `CLAUDE.md` ни строки `@` · grep claudeMdExcludes .claude/settings.json · red: правило подгружено автозагрузкой
at-main-thread-is-agent · агент `dispatcher`, его тело — единственная база маршрутизации и обязано быть самодостаточным (`@import` в теле агента не раскрывается) · grep '"agent"' .claude/settings.json · red: @import в базе диспетчера
at-rule-preloaded-by-symlink · правило закреплено предзагрузкой: `SKILL.md` — символьная ссылка, агент несёт её в `skills:` · readlink, check-04 · red: правило не в окне агента
at-symlink-not-copy · символьная ссылка на файл правила, не копия · readlink .claude/skills/rule-<имя>/SKILL.md` = `../../rules/<имя>.md · red: копия правила в скиле
at-rule-star-is-binding · `rule-*` — привязка к правилу, не экспертиза; в перечень канонических скилов не входит · check-03 (исключение в гейте) · red: rule-* учтён как канонический скил
at-debt-three-gates-stale · `check-02` судит по снятой модели `@import` — до правки его вердикт недействителен · check-02 · red: вердикт о снятой модели принят за действующий
at-skills-roster · перечень канонических скилов (14, без `rule-*`) обязан совпадать с деревом в обе стороны · check-03 · red: строка без каталога либо каталог без строки
at-godzila-thirteenth · `godzila` отслеживается git и входит в перечень; приоритет ниже правил, выше локального `CLAUDE.md` · check-03 · red: отслеживаемый скил вне перечня
at-ci-clone-carries-no-tooling · клон продукта не несёт оснастку; CI-проверки — в его дереве, не в `.claude/` · ЗАВЕСТИ · red: клон без своей CI-проверки продукта
at-dead-asset-does-not-travel · ассет без предмета не заводить «про запас»; исключение обязано самоистекать · --check → STALE-EXCLUSION · red: мёртвый ассет на вид работающий
at-two-grep-engines · `grep` в Bash-инструменте агента и в скрипте — РАЗНЫЕ движки: обёртка харнесса (ugrep, `-G`) не экспортируется, дочерний bash берёт GNU grep · проба предпосылки в scripts/tooling-gate/inject.sh · red: вердикт команды, набранной руками, перенесён на скрипт без перемера
at-handrun-predicate-engine-agnostic · выписанный для прогона руками предикат не ставит якорь ветвью альтернативы (`(^|X)` в обёртке молча не совпадает); границу слова пиши `-P` просмотром назад либо `\b` · scripts/tooling-gate/check-12-handrun-predicate-survives-both-greps.sh · red: перепись на образце, в обёртке всегда пустом
at-rule-address-as-written · ссылка на правило и скил-привязку резолвится ТЕМ адресом, которым написана; архив целью не считается — он не грузится · scripts/rules-gate/check-11-rule-address-exists-as-written.sh · red: путь корпуса ведёт в снятый файл, а гейт базовых имён печатает «ВИСИТ 0»
at-rule-address-debt-only-shrinks · остаток висячих адресов объявлен поимённо числом и только сокращается; запись, которой нечего исключать, — находка · `scripts/rules-gate/check-11-rule-address-exists-as-written.sh` с `rule-address-baseline.txt` · red: долг вырос молча либо база пережила свой предмет
at-markup-is-not-a-script · исключение по роли не выдаётся разметке и файлу без строки запуска: судится ФОРМАТ файла, а не `#!` и не перечень каталогов · rules-gate check-11, пары 2 и 4 его инъекции · red: корпус, агент, навык или протокол изъял себя из переписи одной строкой

## Канонические агенты (единственный экземпляр — `.claude/agents/` воркспейса; копий нет)

at-agents-roster-dispatcher · главный поток — `dispatcher`: без Read/Bash/Edit, решает по возврату и своей самодостаточной базе · check-03 · red: диспетчер сам читает или правит файлы
at-agents-roster-execution · task-execution: 16 агентов, каждый — единственный держатель своей зоны правки · check-03 · red: зона правки без держателя либо с двумя
at-agents-roster-review · specialist-review: 10 ролей; `wave-reviewer` — один на сборку, `convergence-reviewer` — держатель схождения · check-03 · red: посадка без ревью применимой ролью
at-agents-roster-boundary · границы задачи: 5 read-only ролей (scout…ci-watcher), кода не пишут · check-03 · red: роль-разведка правит код
at-agents-count-32 · счёт generic-агентов — 32 (31 исполнитель + dispatcher) · git ls-files .claude/agents/ | wc -l · red: перечень и число расходятся
at-executors-dont-launch-executors · у каждого агента, кроме `dispatcher`, `disallowedTools` содержит `Agent` · grep -rL disallowedTools .claude/agents/ · red: исполнитель запускает исполнителя
at-no-nested-launches · агент не зовёт другого напрямую — возвращает диспетчеру «нужен следующий» · check-05 · red: вложенный вызов агента из тела другого

> Счёт: **32** агентов — предикат `git ls-files .claude/agents/ | wc -l`.
> Перечень — адреса запуска, он сверяется с деревом в обе стороны (`check-03`):
> строка без файла и файл без строки — обе находки.
> Что делает агент — поле `description` его файла; здесь оно не повторяется.

- `dispatcher`
- `acceptance-author`
- `proto-sync`
- `service-scaffolder`
- `rpc-implementer`
- `go-implementer`
- `migration-writer`
- `api-gateway-registrar`
- `ui-implementer`
- `integration-tester`
- `docs-writer`
- `vault-scribe`
- `deploy-engineer`
- `tooling-maintainer`
- `git-operator`
- `load-tester`
- `client-simulator`
- `acceptance-reviewer`
- `system-design-reviewer`
- `db-architect-reviewer`
- `go-style-reviewer`
- `proto-api-reviewer`
- `ui-reviewer`
- `qa-test-engineer`
- `security-auditor`
- `wave-reviewer`
- `convergence-reviewer`
- `scout`
- `class-exposure-analyst`
- `landing-reviewer`
- `check-verifier`
- `ci-watcher`

## Канонические скилы (`.claude/skills/<name>/SKILL.md`)

Единица перечня — отслеживаемый git-каталог скила, кроме привязочных `rule-*`:
`git ls-files .claude/skills/ | cut -d/ -f3 | sort -u | grep -v '^rule-' | wc -l` (**14**).
Перечень обязан совпадать с выводом в обе стороны (`check-03`); `<svc>-load-testing`
живёт в репо сервиса и в счёт не входит. Что делает скил — `description` его `SKILL.md`.

- `evgeniy` (workspace)
- `code-authoring` (workspace)
- `testing-code-coach` (workspace)
- `testing-product-coach` (workspace)
- `load-testing-coach` (workspace)
- `kacho-docs-writer` (workspace)
- `hardening-audit-loop` (workspace)
- `measurement-discipline` (workspace)
- `gate-authoring` (workspace)
- `verdict-and-landing` (workspace)
- `security-surface` (workspace)
- `doc-truthfulness` (workspace)
- `godzila` (workspace)
- `change-graph` (workspace)
- `<svc>-load-testing` (repo)

## Lifecycle, который ОБЯЗАН удовлетворяться (gates для автономной разработки)

at-lifecycle-preamble · порядок lifecycle выставляет диспетчер по возвратам; шаг не запускает следующий сам · check-05 · red: шаг цепляет следующий без диспетчера
lc1-acceptance-first · новая работа — только после APPROVED Given-When-Then; без APPROVED не кодить (ban #1) · docs-gate check-01 · red: код без APPROVED-приёмки
lc2-issue-branch-trail · фича — issue + ветка `issue-<N>` + trail в vault · docs-gate check-02 · red: код без issue, ветки или trail
lc4-crossrepo-order · вести в порядке proto → corelib → сервис → api-gateway → deploy → docs; `replace` на свои модули не заводить · go list -deps ./... по каждому модулю зелен, grep replace github.com/PRO-Robotech go.mod пусто · red: сервис собран против несуществующего контракта
lc5-tdd-red-before-code · падающая проба ДО кода, integration и newman в том же PR · kacho/tests/newman (assert-suites-green.sh) · kacho-workspace/scripts/docs-gate/ · red: проба, не падавшая ни разу
lc6-role-reviews · провести ревью четырьмя ролями (proto-api-reviewer, db-architect-reviewer, go-style-reviewer, system-design-reviewer) плюс <svc>-conventions-auditor · ЗАВЕСТИ · red: посадка при неполном множестве ролей
lc7-final-verification · go test ./... -race, golangci-lint run, govulncheck, make audit-list-filter, newman — все зелёные на PR сборки в ветку волны (`testing.md#final-verification-before-merge`) · .github/workflows/ci.yaml даёт зелёный по всем поимённым контекстам · red: вердикт по подмножеству
lc8-trail-and-close · обновить vault (resources/rpc/edges + записка) и закрыть issue с артефактами · vault-gate, docs-gate check-02 · red: issue закрыт без trail

## Сторонние агенты/скилы (использовать, не пересоздавать)
