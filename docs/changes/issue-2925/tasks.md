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
> **Редакция 2 · 2026-09-30 — проект маршрута, приведённый к замыслу редакции 2** (пересверка
> разбора классов на замысел `7613071f` вернула его; новые пункты CX6-20…24 и перепись §10
> замысла на 27 мест разнесены по полосам F1, C1, C2, G1, S3, S4, S5). Состояние
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
| Е1 | NTF-1 одобрена с Р9 (флаг) | снята | запись `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/530e2296….yaml`, `APPROVED` |
| Е2 | NTF-3 одобрена в форме §1.7 приёмки NTF-6 | **открыта** (последний круг — возврат) | `ls docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/`; запись `APPROVED` на текущий отпечаток отсутствует |
| Е3 | подчарт `notify` и флаг в зонтике посажены | открыта | `helm template` зонтика несёт `# Source: …/charts/notify/templates/` |
| Е4 | `notify-api` за краем, `/notify/v1/*` и каталог на стенде консоли | открыта | шаг предпосылки DoD 13 зелёный |
| Е5 | маршрут операций `notify` на краю или записанное «`done = false` не бывает» | открыта; **не блокирует** (design.md З8) | запись в приёмке NTF-3 |

## 2. Полосы

### Ярус 1 — фундамент (`shared`, чистые функции и признак)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| F1 | проверка id, счёт «нового», признак Р2 (З2, З7, З12) | `ui-implementer` | kacho · `ui-future/shared/src/lib/{id-form,unread-count,console-config}.ts` и их `*.test.ts` | `npm test --prefix vpc -- id-form unread-count console-config` (пробы `shared` исполняет модуль с `../shared/src` в `roots`) зелёный с числом исполненного; ветки: DoD 2 целиком, CX6-16 (одно чтение на окно, выход из `unreadable`), CX6-21 (четыре состояния `loading`/`enabled`/`disabled`/`unreadable`; первое чтение не завершено — `loading`), CX6-17 (сцепка страниц), `isPlatformId` по каждому виду `STREAM_SUBJECTS` и восемь отвергаемых входов | Е2 | M |
| F2 | переходы в `subjects.ts` (З11) | `ui-implementer` | kacho · `ui-future/shared/src/lib/subscription/subjects.ts`, `subjects.test.ts` | `subjects.test.ts` зелёный, печатает 23 записи; `tsc` краснеет на удалении записи владельца из `NOTIFY_SOURCE_BY_OWNER` (проверено инъекцией, вывод приложен) | Е2 | S |
| F3 | гейт перехода (З11) | `integration-tester` | kacho · `ui-future/deploy/console_notify_source_key_test.go` (+ общий помощник вывода владельцев с `console_stream_kind_dictionary_test.go`) | `go test ./ui-future/deploy/ -run ConsoleNotifySourceKey -count=1 -v` печатает «владельцев 6, записей 23», зелёный; инъекция `loadbalancer: "loadbalancer"` — красный с именем владельца | F2 | S |

### Ярус 2 — контракты (клиент и словарь отказов)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| C1 | клиент `notify.ts`: функции, разборщики формы, отказ формы, повтор, обход страниц, константы, исход операции (З6, З8) | `ui-implementer` | kacho · `ui-future/shared/src/api/{notify.ts,notify.test.ts,response-shape.ts}` | `notify.test.ts` зелёный с числом: по каждой функции чтения — «`200` не той формы → `ResponseShapeError`, у ошибки нет `status`» (CX6-06 (б), CX6-22); `notifyQueryRetry` — `false` на `ResponseShapeError`, `true` на первом `503` (CX6-22); по каждой из пяти мутаций — «`done = true` → обращений к `/operations/` 0» и «`done = false` → 1» (CX6-09); повтор токена — отказ; `git grep -l '/notify/v1/' -- 'ui-future/*/src/*.ts*' ':!*test*'` → только `notify.ts` | Е2 | M |
| C2 | текст Р17 (З15) и ветка отказа формы (З6) | `ui-implementer` | kacho · `ui-future/shared/src/lib/error-presentation.ts`, `error-presentation.test.ts` | проба словаря утверждает новый текст у `AUTHZ_DENIED`; `git grep -c 'администраторам платформы' -- ui-future` → 0; ветка «`ResponseShapeError` → `status = "500"`, текст отказа данных, не общее `"error"`» (CX6-22) | C1 (класс `ResponseShapeError`) | S |

### Ярус 3 — общее (карточка, имена, фикстуры)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| G1 | действие подписки на карточке, кэш провайдера страницы, слушатель событий подписок (З10) | `ui-implementer` | kacho · `ui-future/shared/src/components/organisms/ResourceDetailExtensions/**`, `ui-future/shared/src/hooks/{useNotifySubscriptionsSync.ts,useNotifySubscriptionsSync.test.tsx}` | `ResourceDetailExtensions.test.tsx` зелёный: ветка `networks` (своё расширение и действие), две карточки подряд — каталог и список по одному запросу (CX6-19), цель на второй странице — «Вы подписаны» (CX6-08), отказ `503` — список перечитан, событие — список перечитан, страница размонтирована и смонтирована заново — событие перечитывает список (CX6-20); признак `loading`/`disabled`/`unreadable` — запросов каталога 0; `useNotifySubscriptionsSync.test.tsx` — после размонтирования слушателей на окне 0 (CX6-20) | F1, F2, C1 | M |
| G2 | имена раздела `notify` (З14; §10 пп.9, 24) | `ui-implementer` | kacho · `ui-future/shared/src/lib/entity-names.ts`, затем `ui-future/host/src/lib/entity-names.ts` | `HostBreadcrumb.names.test.ts` и `console-entity-names-single-source.test.ts` зелёные | — | S |
| G3 | фикстуры G1: `inviteIntoAccount`, `ownUserId`, `onlyAccount` (З17) | `ui-implementer` | kacho · `ui-future/e2e/specs/{fixtures.ts,users.spec.ts}` | DoD 14: `git grep -n 'function inviteIntoAccount\|function ownUserId\|function onlyAccount' -- ui-future/e2e` → 3 строки в `fixtures.ts`; `git grep -n 'users:invite' -- ui-future/e2e` → 1 строка в `fixtures.ts`; `users.spec.ts` исполнен на стенде зелёным с числом | — | S |

### Ярус 4 — службы (модуль `notify` и хост)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1 | каркас модуля: пакет, федерация `./NotifyPage`, сборка, пробы, перепись поверхности (З1, З16; §10 п.8) | `ui-implementer` | kacho · `ui-future/notify/{package.json,package-lock.json,vite.config.ts,jest.config.cjs,tsconfig.json,Dockerfile,src/main.tsx,src/test/notify-surface-census.ts}`; `ui-future/package.json` (сценарии корня) | DoD 1: `npm ci --prefix notify && npm run typecheck && npm test` в модуле зелёный с числом; гейты DoD 6 (литералы) и DoD 11 (вывод HTML) печатают число файлов, красные на пустом обходе и на инъекции | C1 | M |
| S2 | центр уведомлений (З7, З13, Р5, Р7, Р19) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationCenterPage/**`, `src/components/InboxItemRow/**` | `NotificationCenterPage.test.tsx` и `InboxItemRow.test.tsx` зелёные: форма не та — отказ (CX6-06 (б)); вторая страница после найденного `seenUpTo` без пометок (CX6-17); пустой `projectId` у спеки службы доступа — ссылка, у спеки проекта — текст (CX6-18) | S1, F1, F2, C1 | M |
| S3 | личные настройки и «Мои подписки» (З13; хук `useNotifySubscriptionsSync` в корне `NotifyPage`) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationSettingsPage/**`, `ui-future/notify/src/pages/NotifyPage/**` | `NotificationSettingsPage.test.tsx` зелёный: отказ каталога и настроек (не `200` и форма) — матрицы нет (CX6-11); пустая разница — `:setEntries` не уходит; одна ячейка — одна запись (CX6-12) | S1, C1, G1 | M |
| S4 | контакты аккаунта (З13) | `ui-implementer` | kacho · `ui-future/notify/src/pages/NotificationContactsPage/**`; `listAllAccountUsers(accountId)` в `ui-future/shared/src/api/iam.ts` и её проба | `NotificationContactsPage.test.tsx` зелёный: `200` без `security` — отказ; кандидат на второй странице виден (CX6-08); каждый запрос кандидатов, вторая страница тоже, несёт `accountId` выбранного аккаунта (CX6-24); проба `iam.ts`: `listAllAccountUsers("")` — отказ, запросов 0 (CX6-24) | S1, C1 | S |
| S5 | хост: рейл, значок, опрос, маршрут, названные страницы, каталог, обёртка модуля и её загрузка, сборка (З2 п.6, З9, З14; §10 пп.1–3, 5–7, 16–18) | `ui-implementer` | kacho · `ui-future/host/src/{App.tsx,remotes/moduleCatalog.ts,remotes/index.ts,remotes/NotifyRemote.tsx,remotes/notify.d.ts,remotes/rememberLoad.ts,remotes/rememberLoad.test.ts,lib/unread-poll.ts,components/organisms/HostRail/**,components/atoms/RailButton/**,test/notify-remote.tsx}`, `ui-future/host/{vite.config.ts,jest.config.cjs,Dockerfile}`, шапка `ui-future/shared/src/lib/config.ts`; `lib/module-navigation.tsx` не правится | `remote-boundary-coverage.test.ts` зелёный с печатью «federation=9, обёрток=9, имён в каталоге=9» (CX6-10); `rememberLoad.test.ts` (одна загрузка; отказ → повтор грузит заново; успех после отказа — `available`); `unread-poll.test.ts` (CX6-05: опоздавший ответ, отметка во время цикла, схлопывание, `disabled` — таймера нет, размонтирование — слушателей и таймера нет; CX6-23: отказ устаревшего цикла не меняет значок), `HostRail.test.tsx`, `App.test.tsx` «NTF6-02» обеими ветками и ветка «`loading` — ни названной страницы, ни перевода на панель» (CX6-21), `RailButton.test.tsx` — зелёные с числом; `tsc` хоста зелёный (проверка `never`) | F1, C1, G2, S1 | M |
| S6 | тестовые перечни модулей (§10 пп.21–22; п.23 — существующий гейт обходом, держит S5) | `ui-implementer` | kacho · `ui-future/shared/src/components/molecules/Toaster/Toaster.mounted.test.ts`, `ui-future/shared/src/test/console-verb-routes-exist.test.ts` | обе пробы зелёные и печатают `notify` в переписи | S1 | S |

### Ярус 5 — край (раздача консоли)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| E1 | раздача хоста: `/console-config.json`, префикс `notify`, `/notify-remote/`, раздача модуля, переменная апстрима (З3; §10 пп.14–15) | `deploy-engineer` | kacho · `ui-future/deploy/templates/{configmap-nginx.yaml,deployment-host.yaml}` | `helm template ui-future/deploy` с `global.kacho.notifications.enabled=true` и `=false`: тело `{"notificationsEnabled":true}` / `false`, префикс `notify` в обоих, `/notify-remote/` только в `true`; без `global.kacho` — тело `null`; `ui-chart-remote-entry-cache.test.ts` называет `notify` | S1 | S |
| E2 | гейт заголовков защиты по рендеру (З18, CX6-15) | `integration-tester` | kacho · `ui-future/deploy/console_location_security_headers_test.go` | `go test ./ui-future/deploy/ -run ConsoleLocationSecurityHeaders -count=1 -v` печатает число location, зелёный; инъекция location с `add_header` без include — красный с именем location; пустой обход — красный | E1 | S |

Маршруты края `/notify/v1/*` и карта операций (`gateway/**`) — не полосы этого изменения:
их владелец — NTF-3 (Е4, Е5).

### Ярус 6 — развёртывание

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| D1 | объекты чарта модуля (З4; §10 пп.10–13, 20) | `deploy-engineer` | kacho · `ui-future/deploy/{values.yaml,templates/_helpers.tpl,templates/service.yaml,templates/hpa.yaml,templates/deployment-notify.yaml}` | `helm lint ui-future/deploy`; `module_autoscaling_test.go` называет `notify`; в `values.yaml` ключа `global.kacho.notifications` нет (`yq '.global.kacho.notifications' ui-future/deploy/values.yaml` → `null`) | E1 | S |
| D2 | пара рендеров и совпадение по цепочкам (З5, DoD 8, NTF6-47) | `integration-tester` | kacho · `ui-future/deploy/console_notify_render_test.go`; `deploy/console_notify_flag_parity_test.go` | пара `false`/`true` и рендер без `global.kacho` зелёные; гейт цепочек печатает их число и пару по каждой, пустой обход — красный, инъекция «глобальный `false` + модуль `true`» — красный с именем цепочки | D1, Е3 | M |
| D3 | закрепление образа модуля на стендах (З19; §10 п.27) | `deploy-engineer` | kacho · `deploy/helm/umbrella/values.*.yaml` с `uif.<модуль>.image` | по каждому профилю с флагом `true` в цепочке — `uif.notify.image` рядом с соседями; `go test ./deploy/ -run PublishedImagePin -count=1` зелёный | D1, T1 (образ опубликован) | S |
| T1 | конвейер консоли (§10 п.26, DoD 9, DoD 13) | `tooling-maintainer` | kacho · `.github/workflows/ui.yml` (`STANDALONE`, матрицы `pkg` и `project`, имя задания `typecheck`), `.github/workflows/console-e2e.yml` (шаг предпосылки) | матрица содержит `notify`; инъекция падающей пробы в `ui-future/notify/src` — задание `unit (notify)` красное, снятие — зелёное (DoD 9); шаг предпосылки: провал — «не выполнилось», не красное | S1 | S |
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

1. После Е2: F1, F2, C1, C2, G2, G3 — параллельно (путей общих нет).
2. F3 (после F2); G1 (после F1, F2, C1); S1 (после C1).
3. S2, S3, S4, S5, S6, E1, T1 — параллельно после своих зависимостей.
4. E2, D1 → D2 (после Е3) → D3 (после публикации образа матрицей T1).
5. X2, X1 — после посадки Е4 и выкатки на стенд консоли.
6. W1, W2.

Сведение волны, запрос на слияние и вливание — `git-operator` по решению диспетчера; в ствол —
только после одобрений всех применимых ролей `holders.yaml` (Д16).
