---
name: rule-ai-tooling
description: "AI-оснастка Kachō: канонический набор и lifecycle"
---

**Архив:** `.claude/backup/ai-tooling.md`

## Оснастка: экземпляр, счёт правил и доставка до агента

at-single-copy-no-rollout · единственный экземпляр — `.claude/` воркспейса, в копиях продукта его нет · git ls-files продукта без файлов оснастки · red: копия оснастки в дереве продукта
at-walker-derives-and-zero-is-failure · перечень целей — из дерева; ноль целей — отказ; объём осмотренного печатается всегда · scripts/vault-gate/run-all.sh · red: рукописный перечень; «пропущено» с кодом 0
at-unit-is-tracked-git-element · брать `git ls-files`, объявлять рядом с предикатом · skills-gate check-07 исполняет процитированную команду и сверяет · red: число из памяти; счёт по диску вместо индекса
at-two-numbers-one-predicate · числа правил, агентов, скилов держит гейт; величину двух объявлений сверяй одним предикатом · check-07, check-03 · red: число просрочено; два объявления разошлись
at-claim-about-own-check-runs-or-lies · утверждение об оснастке, проверяемое лишь ИСПОЛНЕНИЕМ, — с координатой, которую резолвит обход, и знаменателем; числа печатает прибор · tooling-gate measure-claims-about-checks.py · red: держатель назван, артефакта нет; «не найдено» без числа осмотренного
at-settings-without-permissions · не коммитить блок `permissions`/`defaultMode: bypassPermissions` · scripts/rules-gate/check-09-settings-no-bypass.sh · red: `grep -c permissions .claude/settings.json` не ноль
at-bypass-not-from-repo-layer · режим обхода проектного и локального слоёв харнесс игнорирует; даёт его личный `~/.claude/settings.json`, policy, флаг · `claude --debug-file` без `mode=bypassPermissions` (CC 2.1.278) · red: режим объявлен в дереве, подтверждения приходят
at-no-autoload-corpus · автозагрузки корпуса нет: `claudeMdExcludes`, в `CLAUDE.md` ни строки `@` · grep claudeMdExcludes .claude/settings.json · red: правило подгружено автозагрузкой
at-main-thread-is-agent · агент `dispatcher`; его тело — единственная самодостаточная база маршрутизации (`@import` в нём не раскрывается) · grep '"agent"' .claude/settings.json · red: @import в базе диспетчера
at-rule-preloaded-by-symlink · правило закреплено предзагрузкой: `SKILL.md` — символьная ссылка (не копия) на `../../rules/<имя>.md`, агент несёт её в `skills:`; `rule-*` — привязка, не канонический скил · readlink, check-04, check-03 · red: правило не в окне агента; копия правила в скиле
at-skills-roster · перечень канонических скилов (14, без `rule-*`; `godzila` в нём — ниже правил, выше локального `CLAUDE.md`) совпадает с деревом в обе стороны · check-03 · red: строка без каталога либо каталог без строки
at-ci-clone-carries-no-tooling · клон продукта не несёт оснастку; CI-проверки — в его дереве, не в `.claude/` · ЗАВЕСТИ · red: клон без своей CI-проверки продукта
at-dead-asset-does-not-travel · ассет без предмета не заводить «про запас»; исключение обязано самоистекать · --check → STALE-EXCLUSION · red: мёртвый ассет на вид работающий
at-two-grep-engines · `grep` агента (ugrep, `-G`) и скрипта (GNU) — РАЗНЫЕ движки: ручной предикат без якоря `^`, `$` ветвью альтернативы (молча не совпадает), граница слова — `-P` просмотром назад или `\b` · проба предпосылки tooling-gate inject.sh, check-12 · red: вердикт ручной команды перенесён на скрипт без перемера; перепись в обёртке пуста
at-rule-address-as-written · ссылка на правило и скил-привязку резолвится ТЕМ адресом, которым написана (архив — не цель); остаток висячих объявлен поимённо числом и только сокращается · rules-gate check-10, `rule-address-baseline.txt` · red: путь ведёт в снятый файл при «ВИСИТ 0»; долг вырос молча либо база пережила предмет
at-markup-is-not-a-script · исключение по роли — по ФОРМАТУ файла, не по `#!` и не по перечню каталогов: разметке и файлу без строки запуска не выдаётся · rules-gate check-10, пары 2 и 4 его инъекции · red: корпус, агент, навык или протокол изъял себя из переписи одной строкой
at-window-not-corpus · бюджет токенов — СТАРТОВОЕ ОКНО агента (`CLAUDE.md` + файл агента + `skills:`), а не корпус: совокупного потолка корпуса нет (владелец 2026-10-14, цитата ниже); норма заводится и правится, лишь если скорость не ниже, токенов в окне исполнителя не больше и качество не ниже — с числом (старт до/после, `measure.sh --window`); место нормы — правило агента, который её применяет, либо скилл по триггеру; где `at-norm-criterion` требует сжатия корпуса, действует эта норма · rules-gate check-13, `agent-window-budget.tsv` (храповик: рост — правкой числа с основанием) · red: старт агента выше потолка; потолок поднят без основания; норма одного агента в правиле, предзагружаемом всем

Решение владельца 2026-10-14, дословно: «Размер рулов можно расширить сверх200к но надо понимать что мы их сужали тк агенты выгружал. Их в себя и сжирали по 250к токенов, сейчас мы пишем много рулов но рулы вызывают скилы ко орые вызывает мастер процесс под задачу в саб агентах. Поэтому сами рулы ограничивать в размересовакупном нету смысла вопрос какие скилы будут существовать и какими рулами будут обладать (ограничены только тз, опытом и фантазией.) главное удовлетворять условиям максимальная скорость закрытия задач (планирование, разработка, тестирование публикация), минимальная стоимость в токенах, и максимальное качество как минимум не хуже того как сейчас».

## Канонические агенты

at-agents-roster-dispatcher · главный поток — `dispatcher`: без Read/Bash/Edit, решает по возврату и своей самодостаточной базе · check-03 · red: диспетчер сам читает или правит файлы
at-agents-roster-execution · task-execution: 16 агентов, каждый — единственный держатель своей зоны правки · check-03 · red: зона правки без держателя либо с двумя
at-agents-roster-review · specialist-review: 10 ролей; `wave-reviewer` — один на сборку, `convergence-reviewer` — держатель схождения · check-03 · red: посадка без ревью применимой ролью
at-agents-roster-boundary · границы задачи: 5 read-only ролей (scout…ci-watcher), кода не пишут · check-03 · red: роль-разведка правит код
at-executors-dont-launch-executors · у каждого агента, кроме `dispatcher`, `disallowedTools` содержит `Agent`; нужен другой — «нужен следующий» · grep -rL disallowedTools .claude/agents/, check-05 · red: исполнитель запускает исполнителя или зовёт из тела
at-agent-does-not-wait · вызов не ждёт > 10 мин (`CLAUDE.md` «Не жди») · stall-census.sh, wave-template-inject, no-wait-guard · red: STALL-POLL; без вызова > 15 мин
at-parallel-while-ci · пока идёт CI, независимые предметы (пути не пересекаются, от ждущего вердикта не зависят) идут в лимитах; ci-local очередит лишь отправки (владелец 2026-10-12, архив) · tooling-gate check-19 · red: в ходе лишь ожидания CI при свободных предметах
at-lane-retro · по возврату каждой полосы — работа над ошибками (владелец 2026-10-12, архив): урок правь там, где его предотвратить дешевле всего; отбор по порядку: «потребление токенов было минимально» (сжатие, снятие устаревшего — вклад), «скорость разработки максимальна», «качество кода и тестов аналогичное или выше» (проверки не сняты и не ослаблены — опытом); урок без места — не урок; 2+ случая — механизм, не фраза; пачка волны — полосой `tooling-maintainer` · поле «урок» ВОЗВРАТа, `wave.js` `lessons.md`, tooling-gate check-21 · red: тот же класс ошибки третий раз
at-one-pass-wave · волна — одним проходом (владелец 2026-10-13, архив): предполёт до кода ≤ 45 мин — карта влияния, критерии рецензентов, поверхность, имитация клиента; пункт карты закрывает та же полоса правкой либо «не затронуто — потому что …», пункт чужого класса — полосой его исполнителя; зависимая другого репозитория — в той же волне, пин — на ревизию с опубликованным образом; сборка непрерывная, CI — на сведённом; каскад щадит держателя ведомости; метрики — в `reports` · tooling-gate check-22 · red: зависимый поправлен лишь после красного сведённого; второй PR в ветку эпика при незакрытой волне; пин без образа
at-red-ci-one-round · красный полный CI MR эпика — одним кругом (владелец 2026-10-13, архив): перепись красноты по корням, класс корня — после цитаты отказа, среда с двумя признаками — один перезапуск без полосы; корень чинит исполнитель класса, проверка точечно без CI (тот же шаг: красный до, зелёный после; хук; `check-verifier`); починки — одной сборкой, одним PR в ветку эпика; повтор CI MR эпика — один, после неё; после каждой волны — CI MR эпика и пробное схождение; событие и блок `event` — одним заходом · tooling-gate check-23 · red: два PR починок одного круга со своим CI; класс без цитаты

> Счёт: **32** агентов — предикат `git ls-files .claude/agents/ | wc -l`.
> Перечень — адреса запуска, сверка с деревом в обе стороны (`check-03`); назначение — `description` агента.

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

## Канонические скилы

Единица перечня — отслеживаемый git-каталог скила, кроме привязочных `rule-*`:
`git ls-files .claude/skills/ | cut -d/ -f3 | sort -u | grep -v '^rule-' | wc -l` (**14**).
Сверка с выводом в обе стороны — `check-03`; `<svc>-load-testing` — в репо сервиса, вне счёта.

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

## Lifecycle, который ОБЯЗАН удовлетворяться

at-lifecycle-preamble · порядок lifecycle выставляет диспетчер по возвратам; шаг не запускает следующий сам · check-05 · red: шаг цепляет следующий без диспетчера
lc1-acceptance-first · приёмка — `00-kacho-core.md#ban01-acceptance` · docs-gate check-01 · red: смена контракта без APPROVED
lc2-issue-branch-trail · фича — issue + ветка `<N>-<суффикс>` (`git-issues.md` §«Имя ветки») + trail в vault; закрытие — с vault (resources/rpc/edges, записка) и артефактами · docs-gate check-02, vault-gate · red: код без issue, ветки или trail; закрыт без trail
lc4-crossrepo-order · порядок proto → corelib → сервис → api-gateway → deploy → docs; без `replace` на свои модули · go list -deps ./...; grep replace github.com/PRO-Robotech go.mod пусто · red: сервис собран против несуществующего контракта
lc5-tdd-red-before-code · проба — `testing.md#test-first-red-before-code` · assert-suites-green.sh, scripts/docs-gate/ · red: проба, не падавшая ни разу
lc6-role-reviews · ревью — по уровню, `git-issues.md#gi-asm-one-round` · ЗАВЕСТИ · red: R2 без роли области; четвёртая роль
lc7-final-verification · `testing.md#final-verification-before-merge` и make audit-list-filter — зелёные на PR сборки · ci.yaml — зелёный по всем поимённым контекстам · red: вердикт по подмножеству

## Сторонние агенты/скилы
