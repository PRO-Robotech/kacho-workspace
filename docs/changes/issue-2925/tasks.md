<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2925 (NTF-6, консоль уведомлений) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md` рядом: полосы,
> исполнитель по базе маршрутизации, пути, предикат снятия, зависимости, размер. Это не
> трекер: состояние полос живёт в задаче `PRO-Robotech/kacho#2925` и её подзадачах
> (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 7 · 2026-09-30 — проект маршрута, приведённый к замыслу редакции 7** (пересверка
> разбора классов на `0fff30f0` завела CX6-35, CX6-36 и условия к коду CX6-31, CX6-33): S2 — ключ
> чтения центра по номеру чтения и пробы «новый запрос после дедлайна» со счётом обращений
> (CX6-35), «медленная пара из двух страниц» и «ответ зависшего чтения не продлевает текущее»
> (CX6-36); G4 — `enabled` гасит и поток, счёт открытий потока, отказ отрисовки при `source` с
> серверным сужением (CX6-31); G1 и S3 — действие подписки только при данных у ключа подписок
> (CX6-33); Е2, Е6 — по одобрению редакции 23 NTF-3 (`97afc066`): Е6 (1), (2) выполнены, (3) — нет.
> Редакция 6 — проект маршрута, приведённый к замыслу редакции 6 (пересверка
> разбора классов на `dd683a30` завела CX6-31…34): новая полоса G4 — свойство `source` у
> `ResourceListPage` и опция `enabled` у `useResourceList` с пробами на существующих
> потребителях (CX6-31, путь (а)); S2 зависит от G4, чтение центра — своё, с поколением и
> дедлайном `CENTER_READ_DEADLINE_MS`, пробы `503`, оффлайна, «Показать ещё» во время пары и
> опроса между парами (CX6-31, CX6-32); G1 — форма `mutate` хука и «следствие» подписки,
> пробы «необработанных отказов 0» и «нажатие между исходом и ответом списка» (CX6-33, CX6-34),
> S3 — то же у снятия подписки; C1 — фабрика опций ключа подписок; Е2, Е6 — верхний `verdict`
> записи командой `yq`, записи на `c481e642` и `077fdc20` — `CHANGES_REQUESTED`.
> Редакция 5 — проект маршрута, приведённый к замыслу редакции 5 (пересверка
> разбора классов на `7294a684` завела CX6-26…30): хук синхронной охраны мутации
> `useGuardedMutation` (CX6-28) — в G1, пробы «два нажатия в одном синхронном блоке без сдвига
> часов» с близнецом — в G1, S2, S3, S4, и S2, S4 зависят от G1; снимок пары «настройки + лента»
> и проба порядка ответов (CX6-29) — в S2; предел хвоста — условие к E1 (префикс `notify` в
> существующий location с `proxy_read_timeout`, CX6-27); Е6 снимается по ID сценария NTF3-161
> и записи `APPROVED`, а не по слову (CX6-30); дедлайны названы `CONFIG_DEADLINE_MS` и
> `POLL_DEADLINE_MS`, имя полосы T1 за ними больше не повторяется.)
> Редакция 4 — проект маршрута, приведённый к замыслу редакции 4 (ревью
> замысла на `defdbe67` вернуло его: пробы дедлайнов `T1` и `T2` (B1) — в F1 и S5; перечитывание
> ленты после отметки (I1) — в S2; «одна мутация на действие» (I2, И19) — в G1, S2, S3, S4;
> граница устаревших циклов (I3) — в S5; шапка `shared/src/lib/config.ts` перенесена из S5 в F1
> с основанием в замысле (З2 п.7). Условия пересверки `defdbe67`: снимок исхода у позднего
> подписчика `rememberLoad` — в S5, форма блока раздачи модуля — в E1, шапки синтетических
> входов `internal/repohygiene` — в T1. Е1 — по действующему отпечатку NTF-1, Е6 — новая.)
> Редакция 3 — проект маршрута, приведённый к замыслу редакции 3 (пересверка
> разбора классов на замысел `deeea79a` вернула его: перепись §10 выросла до 32 мест — тестовые
> перечни M2, строки 28–32, разнесены по S6 и E1; новый пункт CX6-25 — в S5; условие CX6-22 к
> обходу пользователей — клиент запросов модуля в S1, проба в S4). Редакция 2 разнесла по полосам
> F1, C1, C2, G1, S3, S4, S5 пункты CX6-20…24 пересверки `7613071f`. Состояние
> `TASKS_READY` этот файл не объявляет: по §5 SDD-1 оно наступает только после
> `DESIGN_APPROVED` и проверенного writing-plans handoff, который производит `tasks.md`.
> Handoff либо подтверждает этот файл без правки, либо переписывает его; в обоих случаях
> действует текст на отпечатке, названном записью handoff.

## 0. Правила маршрута

- **Порядок:** фундамент → контракты → общее → службы → край → развёртывание → воркспейс.
  Полоса стартует, когда сняты её зависимости; полосы одного яруса без общих путей идут
  параллельно.
- **Проба до кода** в каждой полосе исполнителя кода: сначала модульная или сквозная проба,
  красная на текущем дереве с напечатанным исходом, затем код, затем та же проба зелёная —
  одним изменением (`ui.md` правило 12; ban #12). Красное фиксируется до кода: это
  свидетельство состояния `RED_PROVEN` для своей полосы.
- **Стадии приёмки гейтятся производителями** (Р13 приёмки): полосы, чьи держатели требуют
  живого `notify` на стенде, стартуют только после Е2 (одобрение NTF-3) и посадки Е3–Е4.
  Полосы фундамента и контрактов исполняются на подменённых ответах и стартуют после Е2.
- **Единица сдачи** — коммит исполнителя в ветке полосы; сведение волны, запрос на слияние,
  вливание и снятие веток — `git-operator` по решению диспетчера.
- Размер: **S** — до дня одного исполнителя, **M** — два-три, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход; «зелёный» — с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | NTF-1 одобрена с Р9 (флаг) | снята | `sha256sum docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` → `29cfa368…`; запись `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/29cfa368….yaml`, `APPROVED`; строк о флаге в разнице с `530e2296` — 0 (design.md §0) |
| Е2 | NTF-3 одобрена в форме §1.7 приёмки NTF-6 и с Д25 (Е6) | **открыта**: одобрение с Д25 есть, Е6 (3) не выполнено | `yq -r '.verdict' docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/<sha256>.yaml`: `97afc066` (редакция 23) — `APPROVED`, NTF3-161 в Р10 есть (design.md M25, запись в `a38a26229`); `88ad95c6` — `APPROVED`, но Р10 без Д25 (design.md M22); `c481e642` (редакция 21) и `077fdc20` (редакция 22) — `CHANGES_REQUESTED`. Осталось суждение рецензента: сверка формы Р9, Р10, Р11, Р20, Р29 с §1.7 и Е6 (3) |
| Е3 | подчарт `notify` и флаг в зонтике посажены | открыта | `helm template` зонтика несёт `# Source: …/charts/notify/templates/` |
| Е4 | `notify-api` за краем, `/notify/v1/*` и каталог на стенде консоли | открыта | шаг предпосылки DoD 13 зелёный |
| Е5 | маршрут операций `notify` на краю или записанное «`done = false` не бывает» | открыта; **не блокирует** (design.md З8) | запись в приёмке NTF-3 |
| Е6 | монотонная отметка `seen_up_to` (Д25) записана в Р10 приёмки NTF-3 со сценарием, «наибольшее» — в порядке позиции ленты | **открыта**; входит в Е2 | по якорю, не по слову (design.md §9 Е6, M25): `sed -n '/^\*\*Р10\./,/^\*\*Р11\./p' <приёмка NTF-3> \| grep -c 'NTF3-161'` ≥ 1 **и** на том же отпечатке `yq -r '.verdict' docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/<sha256 приёмки>.yaml` → `APPROVED` (верхний ключ; поиск строки `verdict: APPROVED` даёт ложное «одобрено» у 10 из 21 записи — design.md M25); порядок позиции и близнец смены разрядов в NTF3-161 — рецензент при снятии Е2. Сегодня (`65d4ccd4e`): на `97afc066` (редакция 23) (1) → 1, (2) → `APPROVED`; (3) не выполнено — позиции абстрактны, `sed -n '/Сценарий NTF3-161/,/Группа O/p' <приёмка NTF-3> \| grep -cE 'разряд'` → 0 (заказ автору NTF-3 — третий повтор) |

## 2. Полосы

### Ярус 1 — фундамент (`shared`, чистые функции и признак)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| F1 | проверка id, счёт «нового», признак Р2 с дедлайном `CONFIG_DEADLINE_MS`, шапка общего модуля конфигурации (З2, З7, З12, З20) | `ui-implementer` | kacho · `ui-future/shared/src/lib/{id-form,unread-count,console-config}.ts` и их `*.test.ts`; шапка `ui-future/shared/src/lib/config.ts` (только комментарий, без литерала имени поля признака — design.md З2 п.7) | `npm test --prefix vpc -- id-form unread-count console-config` (пробы `shared` исполняет модуль с `../shared/src` в `roots`) зелёный с числом исполненного; ветки: DoD 2 целиком, CX6-16 (одно чтение на окно, выход из `unreadable`), CX6-21 (четыре состояния `loading`/`enabled`/`disabled`/`unreadable`; первое чтение не завершено — `loading`), CX6-17 (сцепка страниц), `isPlatformId` по каждому виду `STREAM_SUBJECTS` и восемь отвергаемых входов; B1 на управляемых часах: «чтение не отвечает → по `CONFIG_DEADLINE_MS` `unreadable`, фокус — новое чтение (запросов 2)», «`fetch` не отзывается на отмену — по `CONFIG_DEADLINE_MS` всё равно `unreadable`», «ответ после дедлайна состояние не меняет»; `git grep -n 'notificationsEnabled' -- 'ui-future/*/src/*.ts*' ':!*test*'` → только `console-config.ts` | Е2 | M |
| F2 | переходы в `subjects.ts` (З11) | `ui-implementer` | kacho · `ui-future/shared/src/lib/subscription/subjects.ts`, `subjects.test.ts` | `subjects.test.ts` зелёный, печатает 23 записи; `tsc` краснеет на удалении записи владельца из `NOTIFY_SOURCE_BY_OWNER` (проверено инъекцией, вывод приложен) | Е2 | S |
| F3 | гейт перехода (З11) | `integration-tester` | kacho · `ui-future/deploy/console_notify_source_key_test.go` (+ общий помощник вывода владельцев с `console_stream_kind_dictionary_test.go`) | `go test ./ui-future/deploy/ -run ConsoleNotifySourceKey -count=1 -v` печатает «владельцев 6, записей 23», зелёный; инъекция `loadbalancer: "loadbalancer"` — красный с именем владельца | F2 | S |

### Ярус 2 — контракты (клиент и словарь отказов)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| C1 | клиент `notify.ts`: функции, разборщики формы, отказ формы, повтор, обход страниц, константы, исход операции (З6, З8) | `ui-implementer` | kacho · `ui-future/shared/src/api/{notify.ts,notify.test.ts,response-shape.ts}` | `notify.test.ts` зелёный с числом: по каждой функции чтения — «`200` не той формы → `ResponseShapeError`, у ошибки нет `status`» (CX6-06 (б), CX6-22); `notifyQueryRetry` — `false` на `ResponseShapeError`, `true` на первом `503` (CX6-22); по каждой из пяти мутаций — «`done = true` → обращений к `/operations/` 0» и «`done = false` → 1» (CX6-09); повтор токена — отказ; фабрика опций ключа подписок `notifySubscriptionsQuery()` несёт `retry: notifyQueryRetry` и `networkMode: "always"` (design.md З10, CX6-33); `git grep -l '/notify/v1/' -- 'ui-future/*/src/*.ts*' ':!*test*'` → только `notify.ts` | Е2 | M |
| C2 | текст Р17 (З15) и ветка отказа формы (З6) | `ui-implementer` | kacho · `ui-future/shared/src/lib/error-presentation.ts`, `error-presentation.test.ts` | проба словаря утверждает новый текст у `AUTHZ_DENIED`; `git grep -c 'администраторам платформы' -- ui-future` → 0; ветка «`ResponseShapeError` → `status = "500"`, текст отказа данных, не общее `"error"`» (CX6-22) | C1 (класс `ResponseShapeError`) | S |

### Ярус 3 — общее (карточка, имена, фикстуры)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| G1 | действие подписки на карточке, кэш провайдера страницы, слушатель событий подписок (З10) | `ui-implementer` | kacho · `ui-future/shared/src/components/organisms/ResourceDetailExtensions/**`, `ui-future/shared/src/hooks/{useNotifySubscriptionsSync.ts,useNotifySubscriptionsSync.test.tsx,useGuardedMutation.ts,useGuardedMutation.test.tsx}` | `ResourceDetailExtensions.test.tsx` зелёный: ветка `networks` (своё расширение и действие), две карточки подряд — каталог и список по одному запросу (CX6-19), цель на второй странице — «Вы подписаны» (CX6-08), отказ `503` — список перечитан, событие — список перечитан, страница размонтирована и смонтирована заново — событие перечитывает список (CX6-20); признак `loading`/`disabled`/`unreadable` — запросов каталога 0; `useNotifySubscriptionsSync.test.tsx` — после размонтирования слушателей на окне 0 (CX6-20); «два нажатия «Подписаться» в одном синхронном блоке без сдвига часов — один `POST`; близнец — после исхода — второй» (I2, И19, CX6-28); `useGuardedMutation.test.tsx` — «два вызова в одном синхронном блоке без сдвига часов — `mutationFn` 1; после исхода — 2; отказ опускает флаг» (CX6-28); «`mutationFn` отказывает — `onError` 1 раз, необработанных отказов 0 (счётчик `unhandledRejection`), флаг опущен» (CX6-34); «следствие не завершено — вызов после исхода мутации `mutationFn` не зовёт; завершено — зовёт; следствие отказало — флаг опущен» (CX6-33); `ResourceDetailExtensions.test.tsx` — «`POST` `200`, список отвечает позже — нажатие в промежутке запроса не делает; после ответа — «Вы подписаны»; близнец `POST` `503` — после перечитывания нажатие уходит» (CX6-33); «первое чтение списка подписок отвечает позже — кнопок «Подписаться»/«Отписаться» 0, после ответа — кнопка есть; первое чтение отказало — кнопок 0» (условие пересверки `0fff30f0` к CX6-33, design.md З10) | F1, F2, C1 | M |
| G2 | имена раздела `notify` (З14; §10 пп.9, 24) | `ui-implementer` | kacho · `ui-future/shared/src/lib/entity-names.ts`, затем `ui-future/host/src/lib/entity-names.ts` | `HostBreadcrumb.names.test.ts` и `console-entity-names-single-source.test.ts` зелёные | — | S |
| G3 | фикстуры G1: `inviteIntoAccount`, `ownUserId`, `onlyAccount` (З17) | `ui-implementer` | kacho · `ui-future/e2e/specs/{fixtures.ts,users.spec.ts}` | DoD 14: `git grep -n 'function inviteIntoAccount\|function ownUserId\|function onlyAccount' -- ui-future/e2e` → 3 строки в `fixtures.ts`; `git grep -n 'users:invite' -- ui-future/e2e` → 1 строка в `fixtures.ts`; `users.spec.ts` исполнен на стенде зелёным с числом | — | S |
| G4 | `ResourceListPage` с источником извне (design.md З13, CX6-31) | `ui-implementer` | kacho · `ui-future/shared/src/components/organisms/ResourceListPage/{ResourceListPage.tsx,ResourceListPage.source.test.tsx}`, `ui-future/shared/src/lib/use-resource-list.ts` и его проба | `ResourceListPage.source.test.tsx` красный до правки с напечатанным исходом, затем зелёный с числом: при `source` — запросов к `spec.apiPath` 0 и открытий потока 0 за 10 с управляемых часов (поток — подменой транспорта подписки, счёт открытий; `enabled` передан и в `useResourceStream`, design.md M32), строки и состояние из `source`, «Показать ещё» зовёт `source.loadMore` 1 раз и недоступно при `loadMoreDisabled`; близнец без `source` — запросов ≥ 2 за 3 с (опрос прежний); проба `use-resource-list` — `enabled: false` → запросов 0 и открытий потока 0; `source` вместе с `listFilters`, `search.serverTerm` или `serverSearchField` — отказ отрисовки с текстом design.md З13, близнец — спека без серверного сужения рисует строки `source` (условия пересверки `0fff30f0` к CX6-31); `ResourceListPage.hookorder.test.tsx` и все файлы проб, называющие `ResourceListPage` (`git grep -l 'ResourceListPage' -- ui-future ':!*node_modules*' \| grep '\.test\.'` — 18 на `1d42a6728bf`, design.md M28), зелёные без правки, число исполненного напечатано | — | S |

### Ярус 4 — службы (модуль `notify` и хост)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1 | каркас модуля: пакет, федерация `./NotifyPage`, сборка, пробы, перепись поверхности, клиент запросов модуля (З1, З6, З16; §10 пп.8, 32) | `ui-implementer` | kacho · `ui-future/notify/{package.json,package-lock.json,vite.config.ts,jest.config.cjs,tsconfig.json,Dockerfile,src/main.tsx,src/test/notify-surface-census.ts,src/lib/queryClient.ts,src/lib/queryClient.test.ts}`; `ui-future/package.json` (сценарии корня) | DoD 1: `npm ci --prefix notify && npm run typecheck && npm test` в модуле зелёный с числом; гейты DoD 6 (литералы) и DoD 11 (вывод HTML) печатают число файлов, красные на пустом обходе и на инъекции; `queryClient.test.ts` — умолчание `retry` клиента `createNotifyQueryClient()` — `notifyQueryRetry` (CX6-22); `git grep -n 'new QueryClient' -- ui-future/notify/src ':!*test*'` → 1 строка в `queryClient.ts`; `notify/jest.config.cjs` — общий `setupFilesAfterEnv` `shared`, `module-test-setup-single-source.test.ts` зелёный с `notify` в переписи (§10 п.32) | C1 | M |
| S2 | центр уведомлений (З7, З13, Р5, Р7, Р19) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationCenterPage/**`, `src/components/InboxItemRow/**` | `NotificationCenterPage.test.tsx` и `InboxItemRow.test.tsx` зелёные: форма не та — отказ (CX6-06 (б)); вторая страница после найденного `seenUpTo` без пометок (CX6-17); пустой `projectId` у спеки службы доступа — ссылка, у спеки проекта — текст (CX6-18); «два нажатия отметки в одном синхронном блоке без сдвига часов — один `PATCH`», близнец «после исхода — второй» (И19, CX6-28); «настройки после отметки несут позицию новее загруженной верхней — лента перечитана, «новые» только выше позиции» (I1); «настройки отвечают раньше ленты — ни в один момент не помечено новым всё загруженное», близнец «лента раньше настроек», «чтение, начатое до успеха, в снимок не входит» (CX6-29, И20); перечитывание ленты `503` — «отвергнуто», близнец оба `200`; оффлайн во время пары — «отвергнуто»; «Показать ещё» во время пары запроса не делает; пара не отвечает — по `CENTER_READ_DEADLINE_MS` «отвергнуто», опоздавший ответ снимок не меняет (CX6-32); после дедлайна следующий таймер — обращений к `/notify/v1/preferences` и `/notify/v1/inbox` по 2, близнец «после ответившей пары — 2, снимок из второго», дочитывание после дедлайна — запросов по токену 2, перемонтирование центра при зависшем чтении — новый запрос (CX6-35); две страницы по 20 с на управляемых часах — снимок обновлён, «отвергнуто» не было, близнец «первая страница молчит — «отвергнуто» на границе и новый запрос», ответ зависшего чтения не продлевает дедлайн текущего (CX6-36); опрос между парами меняет строки и пометки одним переходом (CX6-31); `git grep -n 'refetchQueries\|fetchNextPage' -- ui-future/notify/src ':!*test*'` → 0 | S1, F1, F2, C1, G1, G4 | M |
| S3 | личные настройки и «Мои подписки» (З13; хук `useNotifySubscriptionsSync` в корне `NotifyPage`) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationSettingsPage/**`, `ui-future/notify/src/pages/NotifyPage/**` | `NotificationSettingsPage.test.tsx` зелёный: отказ каталога и настроек (не `200` и форма) — матрицы нет (CX6-11); пустая разница — `:setEntries` не уходит; одна ячейка — одна запись (CX6-12); два нажатия сохранения, периода, снятия подписки в одном синхронном блоке без сдвига часов — по одному запросу, близнец «после исхода — второй» (И19, CX6-28); снятие подписки: `DELETE` `200`, список отвечает позже — нажатие в промежутке запроса не делает (CX6-33); первое чтение «Моих подписок» отвечает позже — кнопок «Отписаться» 0 (условие пересверки `0fff30f0` к CX6-33) | S1, C1, G1 | M |
| S4 | контакты аккаунта (З13) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationContactsPage/**`; `listAllAccountUsers(accountId)` в `ui-future/shared/src/api/iam.ts` и её проба | `NotificationContactsPage.test.tsx` зелёный: `200` без `security` — отказ; кандидат на второй странице виден (CX6-08); каждый запрос кандидатов, вторая страница тоже, несёт `accountId` выбранного аккаунта (CX6-24); «`200` не той формы у обхода пользователей — один запрос, без повтора» на клиенте `createNotifyQueryClient()` (CX6-22); проба `iam.ts`: `listAllAccountUsers("")` — отказ, запросов 0 (CX6-24); два нажатия сохранения контакта в одном синхронном блоке без сдвига часов — один `PATCH`, близнец «после исхода — второй» (И19, CX6-28) | S1, C1, G1 | S |
| S5 | хост: рейл, значок, опрос с дедлайном `POLL_DEADLINE_MS`, маршрут, названные страницы, каталог, обёртка модуля и её загрузка, сборка (З2 п.6, З9, З14, З20; §10 пп.1–3, 5–7, 16–18) | `ui-implementer` | kacho · `ui-future/host/src/{App.tsx,remotes/moduleCatalog.ts,remotes/index.ts,remotes/NotifyRemote.tsx,remotes/notify.d.ts,remotes/rememberLoad.ts,remotes/rememberLoad.test.ts,lib/unread-poll.ts,components/organisms/HostRail/**,components/atoms/RailButton/**,test/notify-remote.tsx}`, `ui-future/host/{vite.config.ts,jest.config.cjs,Dockerfile}`; `lib/module-navigation.tsx` не правится | `remote-boundary-coverage.test.ts` зелёный с печатью «federation=9, обёрток=9, имён в каталоге=9» (CX6-10); `rememberLoad.test.ts` на управляемом загрузчике (одна загрузка; отказ → повтор грузит заново; успех после отказа — `available`; последовательность `pending → unavailable → pending → available`, вызовов загрузчика ровно 2, после успеха хранимое не снимается — CX6-25; «подписка после успеха — `available` сразу, вызовов загрузчика 1» — условие пересверки `defdbe67`); в диффе `rememberLoad.ts` оба обработчика исхода проверяют `stored === p` (CX6-25, пункт рецензента — ветка недостижима через `load()`, design.md З14); `unread-poll.test.ts` (CX6-05: опоздавший ответ, отметка во время цикла, схлопывание, `disabled` — таймера нет, размонтирование — слушателей и таймера нет; CX6-23: отказ устаревшего цикла не меняет значок; B1 на управляемых часах: «цикл не отвечает → по `POLL_DEADLINE_MS` значок `"!"`, следующий таймер начинает цикл (обращений к ленте 2), опоздавший ответ значок не меняет»; I3: «отметка во время цикла, затем устаревший цикл не отвечает — его дедлайн значок не меняет»; размонтирование — таймеров дедлайна нет), `HostRail.test.tsx` (кнопка в `pending` — без признака недоступности, в `unavailable` — с ним, CX6-25), `App.test.tsx` «NTF6-02» обеими ветками и ветка «`loading` — ни названной страницы, ни перевода на панель» (CX6-21), `RailButton.test.tsx` — зелёные с числом; `tsc` хоста зелёный (проверка `never`) | F1, C1, G2, S1 | M |
| S6 | тестовые перечни модулей (§10 пп.21, 22, 28–30; п.23 — существующий гейт обходом, держит S5; п.31 — в E1; п.32 — условие к S1) | `ui-implementer` | kacho · `ui-future/shared/src/components/molecules/Toaster/Toaster.mounted.test.ts`, `ui-future/shared/src/test/{console-verb-routes-exist,iam-pages-authz-single-source}.test.ts`, `ui-future/shared/src/components/organisms/form/ResourceIcon/ResourceIcon.registry.test.ts`, `ui-future/shared/src/lib/spec-columns.bool-labels.test.ts` | пять проб зелёные с числом исполненного, в каждой `notify` в перечне; `iam-pages-authz-single-source.test.ts` — все три ветки зелёные при непустом `notify/src` (форка, маршрута и литерального перехода `/iam` нет); `git grep -nE '"/iam(/\|")' -- ui-future/notify/src` → 0 | S1, S3, S4 | S |

### Ярус 5 — край (раздача консоли)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| E1 | раздача хоста: `/console-config.json`, префикс `notify`, `/notify-remote/`, раздача модуля, переменная апстрима (З3; §10 пп.14–15, 31) | `deploy-engineer` | kacho · `ui-future/deploy/templates/{configmap-nginx.yaml,deployment-host.yaml}`; `ui-future/shared/src/test/ui-chart-remote-entry-cache.test.ts` (`REMOTES` получает `"notifyName"` — красный до шаблона) | `helm template ui-future/deploy` с `global.kacho.notifications.enabled=true` и `=false`: тело `{"notificationsEnabled":true}` / `false`, префикс `notify` в обоих, `/notify-remote/` только в `true`; без `global.kacho` — тело `null`; `ui-chart-remote-entry-cache.test.ts` с `"notifyName"` в `REMOTES` — красный до правки шаблона с напечатанным исходом, зелёный после, с числом исполненного (§10 п.31); блок `notify` в `configmap-nginx.yaml` начинается отдельной строкой `---` без директивы шаблона на ней, первое `name:` куска — `{{ include "ui.notifyName" . }}-nginx` (условие пересверки `defdbe67`, design.md З3); префикс `notify` внесён в **существующий** location `~ ^/(…)/` с `proxy_read_timeout 30s`, отдельного location для `notify` нет (условие пересверки `7294a684`, CX6-27; design.md З3, З9, M24) | S1 | S |
| E2 | гейт заголовков защиты по рендеру (З18, CX6-15) | `integration-tester` | kacho · `ui-future/deploy/console_location_security_headers_test.go` | `go test ./ui-future/deploy/ -run ConsoleLocationSecurityHeaders -count=1 -v` печатает число location, зелёный; инъекция location с `add_header` без include — красный с именем location; пустой обход — красный | E1 | S |

Маршруты края `/notify/v1/*` и карта операций (`gateway/**`) — не полосы этого изменения:
их владелец — NTF-3 (Е4, Е5).

### Ярус 6 — развёртывание

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| D1 | объекты чарта модуля (З4; §10 пп.10–13, 20) | `deploy-engineer` | kacho · `ui-future/deploy/{values.yaml,templates/_helpers.tpl,templates/service.yaml,templates/hpa.yaml,templates/deployment-notify.yaml}` | `helm lint ui-future/deploy`; `module_autoscaling_test.go` называет `notify`; в `values.yaml` ключа `global.kacho.notifications` нет (`yq '.global.kacho.notifications' ui-future/deploy/values.yaml` → `null`) | E1 | S |
| D2 | пара рендеров и совпадение по цепочкам (З5, DoD 8, NTF6-47) | `integration-tester` | kacho · `ui-future/deploy/console_notify_render_test.go`; `deploy/console_notify_flag_parity_test.go` | пара `false`/`true` и рендер без `global.kacho` зелёные; гейт цепочек печатает их число и пару по каждой, пустой обход — красный, инъекция «глобальный `false` + модуль `true`» — красный с именем цепочки | D1, Е3 | M |
| D3 | закрепление образа модуля на стендах (З19; §10 п.27) | `deploy-engineer` | kacho · `deploy/helm/umbrella/values.*.yaml` с `uif.<модуль>.image` | по каждому профилю с флагом `true` в цепочке — `uif.notify.image` рядом с соседями; `go test ./deploy/ -run PublishedImagePin -count=1` зелёный | D1, T1 (образ опубликован) | S |
| T1 | конвейер консоли (§10 п.26, DoD 9, DoD 13); шапки синтетических входов (design.md §4, M23) | `tooling-maintainer` | kacho · `.github/workflows/ui.yml` (`STANDALONE`, матрицы `pkg` и `project`, имя задания `typecheck`), `.github/workflows/console-e2e.yml` (шаг предпосылки); `internal/repohygiene/console{formatterversion,lintproducer,stylelintconfig,typecheckproducer}_injection_test.go` (только комментарии шапок) | матрица содержит `notify`; инъекция падающей пробы в `ui-future/notify/src` — задание `unit (notify)` красное, снятие — зелёное (DoD 9); шаг предпосылки: провал — «не выполнилось», не красное; шапки четырёх инъекционных проб называют состав с `notify` либо не называют его «настоящим» (`git grep -n -P 'настоящ\S* состав дерева' -- internal/repohygiene` — каждое попадание с числом пакетов, равным составу дерева) | S1 | S |
| X1 | сквозные пробы S1–S3 (DoD 3, 5, 7) | `ui-implementer` | kacho · `ui-future/e2e/specs/{notifications-center,notifications-settings,notifications-contacts}.spec.ts` | против стенда G0: 24 из 24, 17 из 17, 10 из 10, красных 0; каждая проба несёт ID сценария в имени `test(…)`; до кода каждая исполнена красной с напечатанным исходом | S2–S5, G1, G3, E1, D1–D3, T1, Е4 | L |
| X2 | гейты единого источника и «отправлено, не доставлено» (DoD 4, 10, 12) | `integration-tester` | kacho · прогон `ui-future/shared/src/test/{module-runs-shared-suite,shared-organisms-single-source,console-list-filter-declared}.test.ts`, `go test ./ui-future/deploy/ -run 'ConsoleMailSaysSentNeverDelivered\|ConsoleRefusalReasonCoverage'` | переписи называют `notify`; гейт почты печатает `ui-future/notify/src/**`; словарь отказов зелёный на дереве, где `notify` производит `PEER_RESOURCE_MISSING` и `PEER_UNAVAILABLE` | S1–S4, C2, Е4 | S |

### Ярус 7 — воркспейс

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| W1 | пакет изменения: исполняемые держателей `prod-console-*` по заведённым файлам, `implementation_diff_set`, свидетельства | `tooling-maintainer` | kacho-workspace · `docs/changes/issue-2925/{holders.yaml,change.yaml,evidence/**}` | в `holders.yaml` нет строк «ЗАВОДИТСЯ ЭТИМ ИЗМЕНЕНИЕМ»; `./scripts/docs-gate/run-all.sh` зелёный | X1, X2, D2 | S |
| W2 | trail записок (DoD 16) | `vault-scribe` | kacho-workspace · `resources/kacho-notify-console.md`, `edges/console-notify.md` | `./scripts/vault-gate/run-all.sh` зелёный | посадка X1 | S |

## 3. План перехода по пакетам консоли

Прода нет (Д12): переход прямой, без второго пути; все образы консоли выкатываются одной
версией, потому что `shared` компилируется в каждый бандл.

| пакет | что меняется | нужна ли пересборка образа | наблюдаемое после выкатки |
|---|---|---|---|
| `host` | рейл, значок, опрос, маршрут `/notifications/*`, названные страницы, загрузчик модуля, сборка | да | кнопка «Уведомления» по признаку Р2 |
| `notify` (новый) | три экрана | новый образ | центр, настройки, контакты |
| `shared` | клиент, признак, счёт, проверка id, переходы, действие карточки, текст Р17, имена | — (исходник, собирается в потребителей) | — |
| `vpc`, `compute`, `storage`, `nlb`, `registry`, `iam`, `system` | исходников нет | да — карточка и текст Р17 приходят через `shared` | действие подписки на карточках спек из `STREAM_SUBJECTS` с ячейкой каталога; новое пояснение `403` |
| `dashboard` | нет | нет по предмету; выкатывается той же версией | — |
| `e2e` | фикстуры G1, три набора проб | — | — |
| чарт `ui-future/deploy` | объекты модуля, раздача, признак | — | объекты модуля ровно при флаге `true` |

Откат — выкатка предыдущей версии всех образов и чарта; состояния консоль не хранит (design.md
§6), поэтому откат данных не требует.

## 4. Порядок по времени

1. После Е2: F1, F2, C1, C2, G2, G3, G4 — параллельно (путей общих нет).
2. F3 (после F2); G1 (после F1, F2, C1); S1 (после C1).
3. S2, S3, S4, S5, E1, T1 — параллельно после своих зависимостей; S6 — после S3 и S4 (перечень
   `iam-pages-authz-single-source` судит исходники экранов модуля).
4. E2, D1 → D2 (после Е3) → D3 (после публикации образа матрицей T1).
5. X2, X1 — после посадки Е4 и выкатки на стенд консоли.
6. W1, W2.

Сведение волны, запрос на слияние и вливание — `git-operator` по решению диспетчера; в ствол —
только после одобрений всех применимых ролей `holders.yaml` (Д16).
