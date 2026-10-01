---
name: rule-ai-tooling
description: "AI-оснастка Kachō: канонический набор и lifecycle"
---

**Архив:** `.claude/backup/ai-tooling.md`

## Оснастка: экземпляр, счёт правил и доставка до агента

at-single-copy-no-rollout · единственный экземпляр — `.claude/` воркспейса, копий в рабочих копиях продукта нет · git ls-files продукта без файлов оснастки · red: копия оснастки в дереве продукта
at-walker-derives-and-zero-is-failure · перечень целей — из дерева; ноль целей — отказ; объём осмотренного печатается всегда · scripts/vault-gate/run-all.sh · red: рукописный перечень; «пропущено» с кодом 0
at-unit-is-tracked-git-element · брать `git ls-files`, объявлять рядом с предикатом · skills-gate check-07 исполняет процитированную команду и сверяет · red: число из памяти; счёт по диску вместо индекса
at-two-numbers-one-predicate · величину, взятую двумя объявлениями, сверять одним предикатом · check-07 · red: два объявления одной величины разошлись
at-numbers-held-by-gate · числа правил/агентов/скилов держит гейт, не внимание · check-07, check-03 · red: число просрочено и не замечено
at-claim-about-own-check-runs-or-lies · утверждение об оснастке, проверяемое только ИСПОЛНЕНИЕМ, пиши с координатой, которую резолвит обход, и со знаменателем; числа печатает прибор · tooling-gate measure-claims-about-checks.py · red: держатель назван, артефакта нет; «не найдено» без числа осмотренного
at-settings-without-permissions · не коммитить блок `permissions`/`defaultMode: bypassPermissions` — выбор за каждого, кто сделает клон · scripts/rules-gate/check-09-settings-no-bypass.sh · red: `grep -c permissions .claude/settings.json` не ноль
at-bypass-not-from-repo-layer · режим обхода из проектного и локального слоёв харнесс игнорирует; даёт его лишь личный `~/.claude/settings.json`, policy или флаг · `claude --debug-file` без `mode=bypassPermissions` (CC 2.1.278) · red: режим объявлен в дереве, подтверждения приходят
at-no-autoload-corpus · автозагрузки корпуса нет: `claudeMdExcludes`, в `CLAUDE.md` ни строки `@` · grep claudeMdExcludes .claude/settings.json · red: правило подгружено автозагрузкой
at-main-thread-is-agent · агент `dispatcher`, его тело — единственная база маршрутизации и обязано быть самодостаточным (`@import` в теле агента не раскрывается) · grep '"agent"' .claude/settings.json · red: @import в базе диспетчера
at-rule-preloaded-by-symlink · правило закреплено предзагрузкой: `SKILL.md` — символьная ссылка, агент несёт её в `skills:` · readlink, check-04 · red: правило не в окне агента
at-symlink-not-copy · символьная ссылка на файл правила, не копия · readlink .claude/skills/rule-<имя>/SKILL.md` = `../../rules/<имя>.md · red: копия правила в скиле
at-rule-star-is-binding · `rule-*` — привязка к правилу, не экспертиза; в перечень канонических скилов не входит · check-03 (исключение в гейте) · red: rule-* учтён как канонический скил
at-skills-roster · перечень канонических скилов (14, без `rule-*`) обязан совпадать с деревом в обе стороны · check-03 · red: строка без каталога либо каталог без строки
at-godzila-thirteenth · `godzila` — в перечне; приоритет ниже правил, выше локального `CLAUDE.md` · check-03 · red: отслеживаемый скил вне перечня
at-ci-clone-carries-no-tooling · клон продукта не несёт оснастку; CI-проверки — в его дереве, не в `.claude/` · ЗАВЕСТИ · red: клон без своей CI-проверки продукта
at-dead-asset-does-not-travel · ассет без предмета не заводить «про запас»; исключение обязано самоистекать · --check → STALE-EXCLUSION · red: мёртвый ассет на вид работающий
at-two-grep-engines · `grep` в Bash-инструменте агента и в скрипте — РАЗНЫЕ движки: обёртка харнесса (ugrep, `-G`) не экспортируется, дочерний bash берёт GNU grep · проба предпосылки в tooling-gate inject.sh · red: вердикт ручной команды перенесён на скрипт без перемера
at-handrun-predicate-engine-agnostic · предикат для ручного прогона не ставит якорь ветвью альтернативы (`(^|X)` в обёртке молча не совпадает); границу слова пиши `-P` просмотром назад либо `\b` · tooling-gate check-12 · red: перепись на образце, в обёртке всегда пустом
at-rule-address-as-written · ссылка на правило и скил-привязку резолвится ТЕМ адресом, которым написана; архив — не цель, он не грузится · rules-gate check-11 · red: путь корпуса ведёт в снятый файл, а гейт базовых имён печатает «ВИСИТ 0»
at-rule-address-debt-only-shrinks · остаток висячих адресов объявлен поимённо числом и только сокращается; запись, которой нечего исключать, — находка · rules-gate check-11 с `rule-address-baseline.txt` · red: долг вырос молча либо база пережила свой предмет
at-markup-is-not-a-script · исключение по роли не выдаётся разметке и файлу без строки запуска: судится ФОРМАТ файла, а не `#!` и не перечень каталогов · rules-gate check-11, пары 2 и 4 его инъекции · red: корпус, агент, навык или протокол изъял себя из переписи одной строкой

## Канонические агенты (единственный экземпляр — `.claude/agents/` воркспейса; копий нет)

at-agents-roster-dispatcher · главный поток — `dispatcher`: без Read/Bash/Edit, решает по возврату и своей самодостаточной базе · check-03 · red: диспетчер сам читает или правит файлы
at-agents-roster-execution · task-execution: 16 агентов, каждый — единственный держатель своей зоны правки · check-03 · red: зона правки без держателя либо с двумя
at-agents-roster-review · specialist-review: 10 ролей; `wave-reviewer` — один на сборку, `convergence-reviewer` — держатель схождения · check-03 · red: посадка без ревью применимой ролью
at-agents-roster-boundary · границы задачи: 5 read-only ролей (scout…ci-watcher), кода не пишут · check-03 · red: роль-разведка правит код
at-agents-count-32 · число агентов — одно, у предиката ниже · check-07 · red: перечень и число расходятся
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

- `evgeniy`
- `code-authoring`
- `testing-code-coach`
- `testing-product-coach`
- `load-testing-coach`
- `kacho-docs-writer`
- `hardening-audit-loop`
- `measurement-discipline`
- `gate-authoring`
- `verdict-and-landing`
- `security-surface`
- `doc-truthfulness`
- `godzila`
- `change-graph`
- `<svc>-load-testing` (repo)

## Lifecycle, который ОБЯЗАН удовлетворяться (gates для автономной разработки)

at-lifecycle-preamble · порядок lifecycle выставляет диспетчер по возвратам; шаг не запускает следующий сам · check-05 · red: шаг цепляет следующий без диспетчера
lc1-acceptance-first · новая работа — только после APPROVED Given-When-Then; без APPROVED не кодить (ban #1) · docs-gate check-01 · red: код без APPROVED-приёмки
lc2-issue-branch-trail · фича — issue + ветка `<N>-<суффикс>` (`git-issues.md` §«Имя ветки») + trail в vault · docs-gate check-02 · red: код без issue, ветки или trail
lc4-crossrepo-order · порядок proto → corelib → сервис → api-gateway → deploy → docs; `replace` на свои модули не заводить · go list -deps ./... по модулям, grep replace github.com/PRO-Robotech go.mod пусто · red: сервис собран против несуществующего контракта
lc5-tdd-red-before-code · падающая проба ДО кода, integration и newman в том же PR · kacho/tests/newman (assert-suites-green.sh) · kacho-workspace/scripts/docs-gate/ · red: проба, не падавшая ни разу
lc6-role-reviews · ревью — по `git-issues.md#gi-asm-one-round` · ЗАВЕСТИ · red: посадка без роли задетой области; четвёртая роль на задачу
lc7-final-verification · `testing.md#final-verification-before-merge` и make audit-list-filter — зелёные на PR сборки · ci.yaml — зелёный по всем поимённым контекстам · red: вердикт по подмножеству
lc8-trail-and-close · обновить vault (resources/rpc/edges + записка) и закрыть issue с артефактами · vault-gate, docs-gate check-02 · red: issue закрыт без trail

## Сторонние агенты/скилы (использовать, не пересоздавать)
