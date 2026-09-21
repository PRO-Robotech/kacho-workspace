---
name: rule-ui
description: "Канон консоли Kachō — как писать UI"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/ui.md`

# Канон консоли Kachō — как писать UI

## Как проверить правку консоли

ui-rule-triple-form · норма — тройка: норма, признак, держатель · ЗАВЕСТИ ui-rule-triple-form · red: держателя нет

ui-verify-command · гоняй `npm run typecheck && npm test` в модуле · .github/workflows/ui.yml · red: вердикт без прогона модуля

ui-shared-no-own-run · shared проверяй прогоном `vpc`, не «прогоном shared» · module-runs-shared-suite.test.ts · red: сослался на «прогон shared»

ui-standalone-npm-ci · ставь `npm ci --prefix <пакет>` до прогона · .github/workflows/ui.yml · red: `MODULE_NOT_FOUND` назван красным

ui-verdict-by-exit-code · читай `$?` и `Tests:`, не вид вывода · pipefailguard_test.go · red: вердикт по `●` или потерян `grep`

ui-memory-death-not-red · смерть по памяти (code 134) — «не выполнилось», не красное · хвост без строки `Tests:` · red: объявлен красный вердикт

## Форма: имя слева, ввод справа

ui-form-label-left-input-right · labelCol 200px — имя+тултип, wrapperCol — ввод · ResourceFormBody.test.tsx · red: рамка, левая пуста, имя дважды

ui-form-frame-duplicates-label · имя поля — один раз, не рамкой и меткой · ResourceFormBody.test.tsx · red: имя названо дважды

ui-form-holder-desc · labelCol несёт имя+пояснение, wrapperCol — только ввод · ResourceFormBody.test.tsx · red: пояснение вне labelCol

ui-fullwidth-only-when-not-fits · во всю ширину — редактор SG, `custom`-виджет, составной список · ResourceFormBody.test.tsx · red: обычное поле растянуто

ui-list-alone-not-fullwidth · список из подполя — в правой колонке, не во всю ширину · ResourceFormBody.test.tsx · red: список во всю ширину

ui-width-not-declared-by-hand · fullWidth руками не ставь, пока вывод не подвёл · ResourceFormBody.test.tsx · red: fullWidth у влезающего поля

ui-probe-not-on-antd-classes · утверждай о заглушке `antd-stub.ts`, классов `ant-*` нет · antd-stub.test.tsx · red: проба ищет `.ant-form-item-label`

## Ссылка на ресурс: RefNameLink и якорь размещения

ui-ref-is-link-not-id · id ресурса — `RefNameLink`; свой id — `CopyableId` · RefNameLink.test.tsx · red: `reg-…` плоским текстом

ui-ref-violation-sign · сверяй с соседними ссылками в таблице · RefNameLink.test.tsx · red: id моноширинным при кликабельных соседях

ui-ref-scope-decides-project-id · scope из реестра: project несёт project_id, global/account — нет · ref-name-link-scope.test.ts · red: безусловный project_id к geo

ui-placement-anchor-single · якорь размещения — только `PlacementAnchor` · PlacementAnchor.test.tsx · red: своя ветка вида в списке/карточке

ui-rule2-holder · пробы размещения проверяй по адресу, не по тексту · PlacementAnchor.test.tsx · red: зелена на плоском id

## Один предмет — один вид (CIDR-редакторы)

ui-one-subject-one-view · предмет — общей геометрией `CidrTableSection`, отличия — параметрами · value-set-editors-one-geometry.test.ts · red: второй компонент предмета

ui-two-components-violation · при разошедшихся копиях сверяй тексты кнопок · value-set-editors-one-geometry.test.ts · red: кнопка «Add» в русском UI

ui-action-path-owned-by-resource · путь держи в файле ресурса, общий берёт `actionPath(verb)` · api-path-surface.test.ts · red: путь спрятан за пропом

ui-user-texts-verbatim · тексты пользователя при слиянии сохраняй дословно · SubnetCidrManager.test.tsx · red: сообщение переписано заодно

ui-rule3-holder · перепись гейта называй ресурсы поимённо · api-path-surface.test.ts · red: падает молча без имён

ui-value-set-as-table · список поля — таблицей: колонка, строки, «Добавить» снизу · value-set-editors-one-geometry.test.ts · red: чипы вместо таблицы

## Кэш точки входа модуля

ui-immutable-only-hashed-names · immutable — только хэшу в имени; remoteEntry — no-cache ВЫШЕ общего · ui-chart-remote-entry-cache.test.ts · red: правило после общего location

ui-cache-checked-by-header · проверяй заголовком ответа, не глазами · ui-chart-remote-entry-cache.test.ts · red: «не доходит» объяснена глазами

ui-fix-where-config-acts · правь конфиг, что действует в поде, не только образ · ui-chart-remote-entry-cache.test.ts · red: починка в неиспользуемом nginx.conf

ui-rule4-holder · гейт называет модуль-виновника при провале · ui-chart-remote-entry-cache.test.ts · red: инъекция без имени модуля

## Переход по имени ресурса

ui-name-is-link-row-is-not · ссылка — ИМЯ через `ResourceLink`, строка не кликабельна · spec-columns.name-link.test.tsx · red: клик на `<tr>`

ui-no-clickable-inside-link · внутрь ссылки — ничего кликабельного, копия — иконкой рядом · spec-columns.name-link.test.tsx · red: клик копирует

ui-link-on-identity-column · переход — на колонку ИДЕНТИЧНОСТИ, не на `name` · spec-columns.name-link.test.tsx · red: ресурс без имени без ссылок

ui-address-same-expression · адрес — тем же выражением, что переход (`childRoute`) · spec-columns.name-link.test.tsx · red: адрес как «база + id»

ui-rule5-holder · иконку типа — по требованию, не всегда · spec-columns.name-link.test.tsx · red: иконка есть/нет невпопад

## Отображение: булево, оболочка форм, поле, прокрутка

ui-bool-named-by-consequence · исходы называй словами предмета через `BoolFact` · spec-columns.bool.test.tsx · red: подпись «Да»/«Нет»

ui-bool-violation-yes · не поясняй «Да» подписью — называй исход явно · spec-columns.bool.test.tsx · red: «Да» рядом с «Защита от удаления»

ui-shared-table-and-form-shell · список — общей таблицей, форма — общей оболочкой · shared-organisms-single-source.test.ts · red: своя `<table>` во вкладке

ui-own-table-violation · своя `<table>`/форма — проверь и карточки · shared-organisms-single-source.test.ts · red: старая страница, те же следствия

ui-no-field-without-source · поле без источника не показывай · ЗАВЕСТИ ui-no-field-without-source · red: прочерк на месте факта

ui-page-single-scroll · шапка фиксирована, прокрутка ОДНА · ЗАВЕСТИ ui-page-single-scroll · red: две полосы прокрутки

## Правило 12. На находку по консоли пишется проба браузером — до фикса и в том же PR

ui-finding-closed-by-e2e-probe · находку — пробой playwright, красной ДО фикса, одним PR · TestConsoleProbeIssueLinksNameATaskAndLiveInsideTheProbe · red: фикс без пробы

ui-what-counts-as-finding · находка — наблюдение о поведении; вёрстка — нет · ЗАВЕСТИ ui-what-counts-as-finding · red: проба на смену отступа

ui-probe-asserts-observable · утверждай наблюдаемое на адресе находки, не разметку · ЗАВЕСТИ ui-probe-asserts-observable · red: утверждает разметку/класс

ui-probe-lives-in-e2e-specs · проба — в `e2e/specs/`; модульная не замещает · TestConsoleProbeIssueLinksNameATaskAndLiveInsideTheProbe · red: находка закрыта jest-пробой

ui-probe-carries-issue-number · `// verifies #<N>` ВНУТРИ `test(…)` · TestConsoleProbeIssueLinksNameATaskAndLiveInsideTheProbe · red: ссылка над файлом

ui-link-inside-test-call · verifies — внутри теста, не в `describe` · consoleprobeissuelink_test.go · red: ссылка переживает пробу

ui-probe-no-retries · не заводи повтор: `retries: 0` · playwright.config.ts · red: повтор суиты

ui-probe-waits-condition · жди условие, не время · newmanfreshreadwrap_test.go · red: `waitForTimeout`/`sleep`

ui-probe-not-status-200 · утверждай элемент/вызов API, не код 200 · ЗАВЕСТИ ui-probe-not-status-200 · red: утверждает «страница ответила»

ui-rule12-violation-sign · при фиксе проверь пробу с номером задачи · consoleprobeissuelink_test.go · red: фикс без пробы

ui-rule12-holder · гейт печатает объём осмотренного; «пусто» — цель · consoleprobeissuelink_test.go · red: молчит на пустом корпусе

## Пустой экран — пустой ответ края

ui-drop-counts-as-narrowing · отбор строки — считай сужением · console-list-filter-declared.test.ts · red: ветка без признака сужения

ui-show-rule-belongs-to-spec · правило показа — в СПЕКе ресурса · console-list-filter-declared.test.ts · red: ветка по `spec.id` в общем

ui-empty-state-for-empty-answer · «создайте первый» — только на пустом ответе края · console-list-filter-declared.test.ts · red: приглашение при непустом ответе

ui-neighbour-decisions-consistent · соседние решения согласуй с отбором · console-list-filter-declared.test.ts · red: фильтр читает недопущенное поле

ui-rule13-holder · гейт печатает перепись, падает на пустом обходе · console-list-filter-declared.test.ts · red: молчит на пустом обходе (#927)

## Долг правила 2 — ПЕРЕМЕРЕН 2026-08-15, три блокатора из трёх оказались ложны

ui-radius-by-mechanism · радиус — по МЕХАНИЗМУ, не по файлу находки · git grep -c по дереву · red: починено где найдено

ui-obstacle-needs-predicate · каждому препятствию — ПРЕДИКАТ, команда · ЗАВЕСТИ ui-obstacle-needs-predicate · red: препятствие без предиката

## Незакрытый форк, который дороже правила 2 (замер 2026-08-15, ПЕРЕМЕРЕН 2026-08-18)

ui-fork-measure · форк — по ведомости, не «разошлось файлов» · fork-excused-by-two-ledgers.test.ts · red: реэкспорт засчитан форком

ui-number-from-rules-is-reference · число из правила — в задание с пометкой «перемерь» · ЗАВЕСТИ ui-number-from-rules-is-reference · red: план на числе без перемера

ui-single-source-gate-must-grow · гейт единого источника — растущий по числу компонентов · fork-excused-by-two-ledgers.test.ts · red: удостоверяет 5 из 50

ui-closed-formbody · компонент гейта — тремя фактами: каталог, файл, символ · shared-organisms-single-source.test.ts · red: копия без красного
