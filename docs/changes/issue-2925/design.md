<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2925 (NTF-6, консоль уведомлений) — замысел

> **Что этот документ.** Технические решения, инварианты и отображение каждого пункта
> первичного разбора классов в механизм (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`
> §2 «Truth ownership»: `design.md` — technical decisions, invariants, exposure mapping).
> Наблюдаемое поведение здесь не описывается и не переопределяется: его единственный
> владелец — приёмка. Порядок работ — `tasks.md` рядом.
>
> **Редакция 1 · 2026-09-30.** Вердикта на неё нет; действующий вердикт выводится из записи
> ревью на отпечаток этого файла (`reviews/design/<role>/<sha256>.yaml`) и из пересверки
> разбора классов (`reviews/class-exposure/revalidation/<sha256>.yaml`).

## 0. Входы и на чём стоит замысел

| вход | координата | отпечаток / ревизия | состояние |
|---|---|---|---|
| приёмка NTF-6 | `docs/specs/sub-phase-NTF-6-console-notification-center-acceptance.md` | `47bd8b7054c3313c535fe74b53cffc21ae9f59f922e4dae23281453bc47c5328` | `APPROVED`, запись `docs/specs/reviews/sub-phase-NTF-6-console-notification-center-acceptance/47bd8b70….yaml` |
| первичный разбор классов | `docs/changes/issue-2925/reviews/class-exposure/initial/47bd8b70….yaml` | тот же отпечаток | `к-коду`, возврата в приёмку нет; пункты CX6-01…19 |
| дерево продукта | `PRO-Robotech/kacho` | `origin/main@1d42a6728bf` | все замеры §1 — на этой ревизии |
| контракт `notify` | приёмка NTF-3, в форме §1.7 приёмки NTF-6 (`ee6f908e`) | в ветке сейчас `c784a8ff…` | не одобрена; стадии гейтятся её одобрением (Р13 приёмки) |
| ядро и флаг | приёмка NTF-1, Р9 | `530e2296…` | `APPROVED` (запись круга 1 прохода редакции 9) |

Решения диспетчера Д1–Д16 действуют без изменений. Из них предмет консоли задают Д7 (флаг
без умолчания), Д8 (модель получателей), Д9 (неотключаемое), Д15 (контракт — NTF-3), Д16
(в ствол — только одобренное). Д14 (надзор администратора облака не распространяется на
`notification_feed`) консоли не касается: консоль ленту не читает потоком и объектов этого
типа не адресует; сказано, чтобы отсутствие отображения не читалось пропуском.

**Прода нет** (Д12, требование владельца «можно перестраивать все подряд»): переход прямой,
без второго пути и без флага совместимости; прежнего поведения консоли, которое пришлось бы
сохранять рядом, у предмета нет — поверхности уведомлений в консоли ноль (§1.1 приёмки).

## 1. Замеры, на которых стоят решения

Ревизия — `PRO-Robotech/kacho` `1d42a6728bf`, если не сказано иное. Команды исполнимы из корня
рабочей копии продукта.

| № | утверждение | команда | результат |
|---|---|---|---|
| M1 | файлов консоли, перечисляющих все восемь модулей руками | `git ls-tree -r --name-only 1d42a6728bf ui-future \| grep -vE '(^\|/)(e2e\|node_modules)/\|\.test\.\|/test/\|__mocks__\|package-lock\|\.md$\|\.snap$\|\.png$\|\.svg$'` → 1073 файла; по каждому `git show` и счёт различных `dashboard\|vpc\|compute\|storage\|nlb\|registry\|iam\|system` **без учёта регистра**, порог 8 из 8 | **14** (перечень — §6). С учётом регистра — 13: четырнадцатый, `deploy/templates/deployment-host.yaml`, пишет имена заглавными (`KACHO_UI_<MOD>_UPSTREAM`). Разбор назвал 13 — его предикат регистр различал; расхождение — единица счёта, а не дерево |
| M2 | тестовых перечней модулей, написанных руками | тот же обход по `*.test.ts*`, порог 8 из 8, затем чтение объявлений | 2 перечня, которые обязаны назвать `notify`: `MUTATING_MODULES` (`shared/src/components/molecules/Toaster/Toaster.mounted.test.ts:63`) и `CONSOLE_APPS` (`shared/src/test/console-verb-routes-exist.test.ts:62`); прочие выводят состав обходом каталога |
| M3 | край выбирает владельца операции ручной картой, приставки операций `notify` в ней нет | `git show 1d42a6728bf:gateway/internal/opsproxy/proxy.go \| sed -n 86,102p` | 8 ключей (`vpc`×2, `compute`, `iam`, `loadbalancer`, `registry`, `storage`, `geo`); неизвестная приставка → `INVALID_ARGUMENT` (`resolveBackend`) |
| M4 | общий `useOperation` опрашивает хотя бы раз и при `done = true` | `git show 1d42a6728bf:ui-future/shared/src/lib/use-operation.ts \| sed -n 18,34p` | `enabled: !!opId`, первый `GET /operations/{id}` уходит всегда |
| M5 | у каждого бандла модуля свой `QueryClient` | `git grep -n 'new QueryClient' 1d42a6728bf -- 'ui-future/*/src/*.ts*' ':!*test*'` | 7 (compute, iam, nlb, registry, storage, system, vpc) — кэш запросов одного бандла другому не виден |
| M6 | клиент края переводит ответ в snake_case | `git show 1d42a6728bf:ui-future/shared/src/api/client.ts \| sed -n 128,138p` | `camelToSnake(parsed)`; ответ `200` не-JSON отдаётся вызывающему как `null`, а не отказом |
| M7 | адрес карточки без проекта у спек службы доступа | `git show 1d42a6728bf:ui-future/shared/src/components/molecules/ResourceLink/ResourceLink.tsx \| sed -n 50,57p` | `resourceServicePrefix(specId) === "iam"` → `/iam/<route>/<id>`; прочие без проекта → `null` |
| M8 | шаблон раздачи: location с собственным `add_header` и `include ui.securityHeaders` | `git show 1d42a6728bf:ui-future/deploy/templates/configmap-nginx.yaml \| grep -nE 'location\|add_header\|securityHeaders'` | у всех location хоста с `add_header` (`/healthz`, `= /index.html`, `^~ /assets/`, статика) include есть; гейта нет (разбор, CX6-15) |
| M9 | `ingress.yaml` модулей не перечисляет | `git show 1d42a6728bf:ui-future/deploy/templates/ingress.yaml \| grep -c 'path:'` | 1 (`/` → сервис хоста); точки входа модулей проксирует раздача хоста (`location ^~ /<mod>-remote/`) |
| M10 | пакеты консоли со своим lock-файлом | `git show 1d42a6728bf:.github/workflows/ui.yml \| sed -n 75p` | `STANDALONE: host dashboard compute storage nlb registry e2e`; workspaces корня — `shared vpc iam system` |
| M11 | образы модулей на стенде закреплены профилем | `git show 1d42a6728bf:deploy/helm/umbrella/values.a8f60d.yaml \| grep -c 'kacho-ui-future-'` | 9 (хост и восемь модулей); умолчание образа модуля — подстановка `host → <mod>` в теге хоста (`_helpers.tpl`) |
| M12 | сигналов окна между бандлами сегодня нет | `git grep -c 'window.dispatchEvent\|new CustomEvent' 1d42a6728bf -- ui-future/host/src ui-future/shared/src` | 0 — каналы окна заводятся этим изменением впервые |

## 2. Решения

Нумерация `З<N>`; у каждого — что решено, инвариант, держатель. Ссылки на приёмку — номером
решения `Р<N>` и ID сценария.

### З1. Модуль `ui-future/notify` — удалённый модуль федерации без раздела в полосе модулей

- Пакет `ui-future/notify` — **самостоятельный** (свой `package.json` и lock-файл), как `nlb`,
  `registry` (M10): DoD 1 приёмки исполняет `npm ci --prefix notify`, а у пакета workspace
  своего lock-файла нет.
- Федерация: имя удалённого модуля `notify`, экспорт один — `./NotifyPage` (роутер трёх экранов
  под `/notifications/*`). Экспорта `./navigation` нет: раздела в полосе модулей нет (Р1),
  кнопку ставит рейл.
- Общие библиотеки федерации — те же пять, что у хоста (`antd`, `lucide-react`, `react`,
  `react-dom`, `react-router`); `@shared` — алиас на `../shared/src`; свой `QueryClient` на
  странице модуля, как у прочих (M5).
- Порт предпросмотра — `4183` (следующий за `storage` `4182`); `dev-federation.sh` выводит
  порт из `preview` пакета и правки не требует.
- **Направления графа бандлов** (инвариант И1): `host → shared`, `notify → shared`,
  `<модуль> → shared`, `host → notify` только через федерацию. `shared → <модуль>` — ноль
  (сегодня ноль, §1.8 приёмки). Держатель: `module-boundary-coverage.test.ts` (состав — обходом
  каталога) и предикат §1.8 приёмки (`git grep -lE "from ['\"]@(…|notify)[/'\"]" -- ui-future/shared/src` → 0).

### З2. Признак Р2 — одно чтение на окно, три исхода, объявленный выход из «не прочитано»

Механизм (`ui-future/shared/src/lib/console-config.ts`, единственный читатель
`notificationsEnabled` — DoD 6):

1. **Хранилище на окне.** Ключ — `Symbol.for("kacho.console-config")` (реестр глобальных
   символов общий для всех бандлов одного окна). Значение — объект
   `{ state: "loading" | "true" | "false" | "unread", inFlight: Promise | null, listeners: Set }`.
   Первый бандл, вызвавший `loadConsoleConfig()`, создаёт объект и начинает чтение; прочие
   получают **тот же** объект и тот же исход (CX6-16 (а)). Бандл своего состояния признака не
   держит.
2. **Чтение.** `fetch("/console-config.json", { cache: "no-store", credentials: "same-origin" })`
   — не клиентом края: путь отдаёт раздача, а не край, и перевод регистра клиента (M6) телу
   признака не нужен. Исход `true`/`false` — только если ответ `200`, тело разбирается как JSON и
   `typeof body.notificationsEnabled === "boolean"`; всё прочее (не `200`, не JSON, поля нет,
   поле не логическое, сетевой отказ) — `unread`. Запасного значения и чтения `import.meta.env`
   нет (И2).
3. **Выход из `unread`** (CX6-16 (б)). Только из `unread`, не из `true`/`false`:
   - повторное чтение по возврату окна в фокус (`visibilitychange` → `visible`) — не больше
     одного чтения в полёте;
   - кнопка «Повторить» на названной странице «Не удалось прочитать конфигурацию консоли…» —
     то же чтение.
   Исход `true`/`false` на время жизни окна окончателен: смена флага — перекатка раздачи
   (аннотация `checksum/nginx`, замер разбора), и новый исход приходит с перезагрузкой. Держать
   окно в `true` после выключения флага безопасно: запросы уйдут на край и получат отказ,
   показанный отказом (Р2, NTF6-56).
4. **Подписка компонентов** — `useConsoleConfig()` на `useSyncExternalStore` поверх
   `listeners` объекта окна: смена исхода, сделанная любым бандлом, перерисовывает все.
   Отдельного события окна для признака нет — объект уже общий.

Инварианты: И2 «признак не имеет умолчания»; И3 «одно окно — один исход признака». Держатели
— `console-config.test.ts` (ветки: четыре формы `unread`; два вызова загрузчика из двух
«бандлов» — один запрос и один исход; `unread` → фокус → `true`; `true` → фокус → запроса нет)
и NTF6-61 (а)–(в), NTF6-02.

### З3. Ответ раздачи `/console-config.json` и перечень проксирования

В блоке `server` хоста шаблона `ui-future/deploy/templates/configmap-nginx.yaml`:

```nginx
location = /console-config.json {
    default_type application/json;
    add_header Cache-Control "no-store" always;
    {{- include "ui.securityHeaders" . | nindent 12 }}
    return 200 '{"notificationsEnabled":{{ dig "kacho" "notifications" "enabled" nil (.Values.global | default dict) | toJson }}}';
}
```

- Значение — из `global.kacho.notifications.enabled` (NTF-1 Р9). **`values.yaml` подчарта
  ключа `global.kacho.notifications` не объявляет** (И2): объявление было бы вторым
  умолчанием. Не заданное значение в отдельном рендере подчарта даёт тело
  `{"notificationsEnabled":null}` — консоль читает `unread`, а не решает за установку; рендер
  зонтика без значения отвергнут NTF-1 (NTF1-N01), второй проверки консоль не заводит (Р2).
- Заголовки защиты уровня `server` в location с собственным `add_header` не наследуются —
  отсюда `include "ui.securityHeaders"` (CX6-15), держатель — З18 п.3.
- Перечень префиксов на край: `location ~ ^/(vpc|compute|storage|geo|nlb|registry|operations|notify)/`
  — **безусловно**, при любом значении флага (NTF6-47, третий «Тогда»): при `false` консоль
  запросов к `/notify/v1/*` не делает, а безусловный маршрут не даёт `index.html` с `200`.
- `location ^~ /notify-remote/` (точка входа модуля) — **только** при флаге `true`: ссылка на
  апстрим `KACHO_UI_NOTIFY_UPSTREAM` без объекта модуля сделала бы конфигурацию раздачи
  неисполнимой.
- Блок `server` раздачи самого модуля `notify` (своя `ConfigMap` в том же шаблоне, как у `iam`
  и `system`) — по образцу: `= /healthz`, `= /index.html`, `~* /remoteEntry\.js$` с
  `Cache-Control "no-cache" always` (гейт `ui-chart-remote-entry-cache.test.ts` называет
  `notify`), статика; каждый location с `add_header` включает `ui.securityHeaders`.

### З4. Объекты чарта модуля — ровно при включённом глобальном флаге

Условие одно на все объекты модуля: `{{- if eq (dig "kacho" "notifications" "enabled" nil (.Values.global | default dict)) true }}`,
вынесенное в `_helpers.tpl` как `ui.notifyEnabled` (одно место вывода; шаблоны зовут
`include`). Объекты:

| объект | где | как |
|---|---|---|
| Deployment `ui-notify` | новый `templates/deployment-notify.yaml` | по образцу `deployment-registry.yaml`; аннотация контрольной суммы своей конфигурации раздачи |
| Service | `templates/service.yaml` | блок `notify` под условием |
| HPA | `templates/hpa.yaml` | блок `notify` под условием и `.Values.notify.autoscaling.enabled` |
| имя, образ, политика, апстрим | `templates/_helpers.tpl` | `ui.notifyName`, `ui.notifyImage` (умолчание — подстановка `host → notify` в образе хоста, как у прочих, M11), `ui.notifyImagePullPolicy`, `ui.notifyUpstream` |
| переменная апстрима хоста | `templates/deployment-host.yaml` | `KACHO_UI_NOTIFY_UPSTREAM` под условием |
| точка входа и раздача модуля | `templates/configmap-nginx.yaml` | З3 |

`values.yaml`: блок `notify:` той же формы, что у соседей (`name: ui-notify`, `replicas`,
`image: ""`, `imagePullPolicy: ""`, `port: 8080`, `resources`, `autoscaling`), и
`host.upstreams.notify: ""`. Это **не** флаг включения: включение — только глобальный флаг.
`ingress.yaml` не меняется (M9).

### З5. Совпадение признака консоли с развёртыванием `notify` на поставляемых цепочках

Гейт `deploy/console_notify_flag_parity_test.go` — в пакете `deploy`, потому что читатель
`deploy/stacks.txt` в Go там один (`deployStacks(t)`, шапка `stacks.txt`), и второй читатель в
`ui-future/deploy` был бы вторым местом о цепочках. По каждой цепочке:

- `helm template` зонтика цепочкой `-f` из `deployStacks`;
- признак консоли — литерал тела `location = /console-config.json` в отрендеренной
  `ConfigMap` раздачи хоста;
- факт «`notify` отрендерен» — число объектов `Deployment`, чей комментарий `# Source:`
  лежит под `charts/notify/templates/` (подчарт службы NTF-1; опознание по пути шаблона, а
  не по имени объекта — имя объявит NTF-1, путь подчарта — свойство зонтика);
- `true` ⇔ число > 0; печатает число цепочек и пару по каждой; пустой обход — красный;
  инъекция цепочки «глобальный `false` + `<модуль>.notifications.enabled: true`» — красный с
  именем цепочки (DoD 8).

Пара проб рендера `false`/`true` (NTF6-47) — в `ui-future/deploy/console_notify_render_test.go`
(держатель `prod-console-chart-render`), третья ветка — отдельный рендер подчарта без
`global.kacho` (тело `null`, объектов модуля нет; И2).

### З6. Клиент `/notify/v1/*` — один, с проверкой формы каждого ответа

`ui-future/shared/src/api/notify.ts` — единственный файл консоли с путём `/notify/v1/`
(DoD 6). Поверх общего `api` (M6: работает в snake_case).

- **Функции:** `listInbox({pageSize, pageToken, module?})`, `getCatalog()`,
  `getPreferences()`, `patchSeenUpTo(position)`, `patchDigestPeriod(period)`,
  `setEntries(entries)`, `listSubscriptionsPage({pageSize, pageToken})`,
  `listAllSubscriptions()`, `createResourceSubscription(resourceType, resourceId)`,
  `deleteSubscription(id)`, `getAccountContacts(accountId)`,
  `patchSecurityContact(accountId, userId)`.
- **Проверка формы** (CX6-06 (б)): у каждой функции чтения — свой разборщик
  (`parseInboxPage`, `parseCatalog`, `parsePreferences`, `parseSubscriptionsPage`,
  `parseContacts`); у мутаций — `parseOperation` (`id` — строка, `done` — логическое). Разборщик
  проверяет только поля, которые консоль читает (Р2: у ленты `items` массив, у каталога
  `modules` массив, у настроек `entries` массив, у контактов объект `security`; плюс типы полей
  элемента, которые выводятся). Несовпадение — **тот же исход, что не-`200`**: бросается
  `ApiError(status = 200, code = "RESPONSE_SHAPE", details = {path, field}, message)`; экраны
  не различают «не 200» и «200 не той формы» и выводят `presentError(err)` (И4).
- **Обход страниц** (CX6-08 (а)): `listAllSubscriptions()` — `pageSize = 1000` (граница ручки
  NTF-3), цикл до пустого `next_page_token`; повтор уже виденного токена — отказ
  `RESPONSE_SHAPE` (обход не зацикливается на неисправном ответе).
- **Константы контракта** — здесь и больше нигде (Р20, DoD 6): `RESOURCE_CHANGE`, `EMAIL`,
  `CONSOLE`, `ALWAYS`, `SWITCHABLE`, `NOTIFY_SEEN_EVENT`, `NOTIFY_SUBSCRIPTIONS_EVENT` (З10).
- **Операции** — З8.

### З7. Счёт «нового» — одна функция над сцепкой загруженного

`ui-future/shared/src/lib/unread-count.ts`, чистая:

```ts
unreadCount(items: readonly { position: string }[], seenUpTo: string, hasMore: boolean):
  { n: number; exact: boolean; isNew: (position: string) => boolean }
```

- Вход — **сцепка всех загруженных страниц** в порядке ответа (CX6-17): хост передаёт первую
  страницу (`pageSize = 100`) и её `next_page_token != ""`; центр — все загруженные страницы
  (`pageSize = 50`) и токен последней. Позиции сравниваются только на равенство (Р18).
- Правило Р18: индекс `i` элемента с `position == seenUpTo` найден — новое `items[0..i)`,
  счёт точен; не найден и `hasMore = false` — новое всё, точно; не найден и `hasMore = true` —
  новое всё загруженное, «не меньше»; `seenUpTo` пуст — новое всё.
- Следствие сцепки: после того как `seenUpTo` найден на первой странице, ни одна строка
  следующих страниц «новой» не помечена (инвариант И5).
- `unreadBadge({n, exact} | "unavailable")` — там же: `""`, `"N"`, `"min(N,99)+"`, `"!"` и
  доступное имя кнопки (Р18). Состояние `"unavailable"` — если хотя бы одно из двух чтений цикла
  отвергнуто (не `200` либо `RESPONSE_SHAPE`).

Держатели: `unread-count.test.ts` — ветки DoD 2 плюс «`seenUpTo` на первой странице — строки
второй не новые» и «`seenUpTo` не найден на двух загруженных, токен есть — «не меньше»».

### З8. Операции `notify`: исход из ответа мутации; опрос — только при `done = false`

Контракт производителя: мутации `notify` отвечают `Operation` с `done = true` на коммите
(NTF-3 Р25). Край опроса операций `notify` не знает (M3), а общий `useOperation` опрашивает
хотя бы раз (M4).

- `settleNotifyOperation(op)` в `notify.ts`: `done = true` и `error` пуст → успех; `done = true`
  и `error` есть → отказ `ApiError` из `error` (`code`, `message`, `details`); `done = false` →
  идентификатор отдаётся общему `useOperation`. **При `done = true` `GET /operations/{id}` не
  выполняется** (CX6-09, Р3).
- Ветка `done = false` исполняется общим путём, и его отказ (край ответит
  `INVALID_ARGUMENT` на неизвестную приставку) показывается `operationOutcome` как «исход
  неизвестен» — отказом, а не успехом. Ложного «сохранено» нет ни в одной ветке (И6).
- Маршрут приставки операций `notify` в `prefixToBackend` края — предмет владельца поверхности
  `notify` на краю (NTF-3); заказ — §9, Е5. Замысел NTF-6 от его посадки не зависит: ветка
  `done = true` исполнима без него, ветка `done = false` без него отказывает честно.

Держатель: `notify.test.ts` — по каждой из пяти мутаций (`patchSeenUpTo`, `patchDigestPeriod`,
`setEntries`, подписка создание/снятие, контакт) ответ `done = true` → обращений к
`/operations/` ноль; `done = false` → ровно одно обращение общим путём; `done = true` с
`error` → отказ с кодом из `error`.

### З9. Опрос счётчика — поколение, один цикл в полёте, сброс по отметке

`ui-future/host/src/lib/unread-poll.ts` (CX6-05):

- Цикл = пара `listInbox({pageSize: 100})` + `getPreferences()` параллельно; номер поколения
  `gen` увеличивается на старте цикла; ответ применяется, только если его `gen` равен текущему
  (устаревший отбрасывается).
- Триггеры: таймер 60 с по часам вкладки, возврат в фокус, событие `NOTIFY_SEEN_EVENT`.
  Таймер и фокус при цикле в полёте **схлопываются** (новый цикл не начинается);
  `NOTIFY_SEEN_EVENT` делает цикл в полёте устаревшим (`gen++`, `AbortController.abort()`) и
  начинает новый.
- Опрос существует только при признаке `true` (З2); при `false`/`unread` — ни таймера, ни
  запросов (NTF6-02, NTF6-61).

Держатель: `unread-poll.test.ts` с управляемыми ответами и часами — «опоздавший ответ
прежнего цикла не меняет значок», «отметка во время цикла: результат цикла отброшен, новый
цикл начат», «таймер и фокус при цикле в полёте — одно обращение», «признак `false` — таймера
нет».

### З10. Действие подписки на карточке — часть общей карточки; кэш каталога и подписок в бандле

В `ui-future/shared/src/components/organisms/ResourceDetailExtensions` (Р10, CX6-03):

- `SubscribeAction` составляется карточкой **рядом** с `headerActions` расширения спеки, а не
  записью `registerDetailExtension`: расширение спеки не заменяется (держатель —
  `ResourceDetailExtensions.test.tsx`, ветка `networks`).
- Видимость — признак `true` (З2), `notifyModuleOf(specId) != null` (З11) и в каталоге у
  этого модуля ячейка `(RESOURCE_CHANGE, EMAIL)` с `SWITCHABLE`. При `false`/`unread` каталог
  не запрашивается.
- **Кэш** (CX6-19): ключи react-query бандла `["notify", "catalog"]` (`staleTime: Infinity` —
  каталог меняет только установка, а её смена приходит перезагрузкой) и
  `["notify", "subscriptions"]` (`staleTime: Infinity`, значение — результат
  `listAllSubscriptions()`). Вторая карточка в том же бандле запросов не делает.
- **Сброс кэша подписок** — своей мутацией и событием окна `NOTIFY_SUBSCRIPTIONS_EVENT`:
  любая успешная или отвергнутая мутация подписки в любом бандле (карточка, экран настроек)
  посылает событие; слушатель регистрируется один раз на бандл при загрузке модуля
  `notify.ts` и инвалидирует ключ в `QueryClient` бандла. Без события карточка бандла `vpc`
  после отписки на экране настроек (бандл `notify`) показала бы «Вы подписаны» из своего кэша
  (NTF6-36, четвёртый «Тогда»). Это другой предмет, чем `NOTIFY_SEEN_EVENT` (отметка
  «просмотрено»), поэтому канал свой; оба имени — константы `notify.ts`.
- «Вы подписаны» — только из полного списка (CX6-08 (а)); после **любого** отказа создания
  список перечитывается, локального флага «подписан» нет (CX6-08 (б), NTF6-59).

Держатели: `ResourceDetailExtensions.test.tsx` — «две карточки подряд — каталог и список по
одному запросу», «цель на второй странице списка — «Вы подписаны»», «отказ `503` — список
перечитан, «Вы подписаны» нет», «событие `NOTIFY_SUBSCRIPTIONS_EVENT` — список перечитан».

### З11. Переход «спека → модуль каталога» и «тип → спека» — в `subjects.ts`

`ui-future/shared/src/lib/subscription/subjects.ts` (Р10а, CX6-01):

- `NOTIFY_SOURCE_BY_OWNER: Readonly<Record<JournalOwner, string>>` — значения Р10а;
  `notifyModuleOf(specId)` — единственный читатель.
- `specOfKind(kind): string | null` — обратный поиск по `STREAM_SUBJECTS[spec].kind`, одно место
  для строки ленты (Р7) и строки подписки (Р10); второго словаря типов нет (DoD 6).
- Гейт `ui-future/deploy/console_notify_source_key_test.go` — вывод из журналов дерева и
  ведомости `journalsOutsideThisTree` тем же разбором, что у
  `console_stream_kind_dictionary_test.go` (общий помощник, не копия); печать 6/23; инъекция
  `loadbalancer: "loadbalancer"`.

### З12. Сегменты адреса из ленты — проверка алфавита; пустой проект законен

`ui-future/shared/src/lib/id-form.ts` — `isPlatformId(s)`: `^[a-z0-9][a-z0-9-]{0,63}$` (Р7).
Строка ленты (`InboxItemRow`) передаёт в `ResourceLink`:

- `id = resourceId`, только если `isPlatformId(resourceId)`; иначе — имя текстом;
- `projectId`: **пустая строка → `null`** (законное отсутствие: спеки службы доступа адрес без
  проекта строят сами, у `scope = cluster` проект пуст — CX6-18); непустая и
  `isPlatformId` — значение; непустая и не прошедшая — имя текстом, ссылки нет.
- Решение, нужен ли проект спеке, принимает только `resourceDetailHref` (M7); вернул `null` —
  текст.

Держатели: `id-form.test.ts` (DoD 3, §8 приёмки) и ветка `InboxItemRow.test.tsx` «пустой
`projectId` у спеки службы доступа — ссылка `/iam/<route>/<id>`; пустой у спеки проекта —
текст; `a/../b` — текст». Сквозной ветки с пустым проектом в объёме нет (у kaname ячейки
`CONSOLE` нет, NTF-3 Р29) — **предикат пересмотра** разбора сохраняется: в каталоге `notify`
появилась ячейка `CONSOLE` у модуля, чьи спеки не несут проект в адресе, либо спека вида
`scope = cluster` в `STREAM_SUBJECTS` — тогда ветка NTF6-16 с пустым `projectId` заводится
приёмкой.

### З13. Экраны модуля — одно состояние загрузки на экран

Каждый экран (`NotificationCenterPage`, `NotificationSettingsPage`,
`NotificationContactsPage`) выводит ровно одно из: «загрузка» · «отвергнуто» (`presentError`)
· «пусто» (только центр, только ответ `200` с `items = []`) · «данные». Подстановки пустого
значения вместо отказа (`?? []`, `?? {}` над результатом запроса) нет (CX6-11, И4); экран
настроек при отвергнутом каталоге или настройках матрицы не рисует.

- **Центр:** `ResourceListPage`; страницы по 50, «Показать ещё» по `next_page_token`;
  фильтр модуля — модули каталога с ячейкой `CONSOLE`, в порядке каталога (Р5); пометки
  «новое» — З7 над сцепкой; «Отметить всё просмотренным» — `patchSeenUpTo(items[0].position)`,
  после успеха — `NOTIFY_SEEN_EVENT` и перечитывание настроек (Р19).
- **Настройки:** матрица из каталога (Р5, Р6); запрос `:setEntries` — **разница «загружено →
  выбрано» по `SWITCHABLE`-ячейкам каталога** (CX6-12), пустая разница — запроса нет; период
  сводки — `patchDigestPeriod`; параметр `module` — выделение группы; «Мои подписки» —
  `listAllSubscriptions()` (кэш З10), снятие — `deleteSubscription` + событие.
- **Контакты:** аккаунт — из выбора хоста; кандидаты — полный обход пользователей аккаунта
  `GET /iam/v1/users?pageSize=1000` до пустого токена (CX6-08 (а)) через
  `shared/src/api/iam.ts` (функция обхода заводится там, если её нет); сервисных аккаунтов и
  групп в выборе нет по построению — источник только пользователи.

Держатели: `NotificationSettingsPage.test.tsx` — «каталог не `200`», «каталог `200` не той
формы», «настройки не `200`» → текст отказа, матрицы нет (CX6-11); «ничего не изменено —
`:setEntries` не уходит»; «изменена одна ячейка — ровно одна запись» (CX6-12).
`NotificationCenterPage.test.tsx` — «лента `200` не той формы → отказ, не «Уведомлений пока
нет»» (CX6-06 (б)), «вторая страница после найденного `seenUpTo` — без пометок» (CX6-17).
`NotificationContactsPage.test.tsx` — «контакты `200` без `security` → отказ»,
«кандидат на второй странице пользователей виден» (CX6-08).

### З14. Вход в рейле, маршрут, названные страницы

- `host/src/remotes/moduleCatalog.ts` — запись `{ remote: "notify", label: SERVICES.notify.menuTitle }`
  без `section`; комментарий строк 20-21 называет троих без раздела (§3 приёмки).
- `host/src/lib/module-navigation.tsx` — `NOTIFY_PAGE_LOADER = () => import("notify/NotifyPage")`
  (литерал — требование плагина федерации) с запоминанием обещания: **одна загрузка, один
  исход** для маршрута и для признака недоступности кнопки. `NAV_REMOTES` не меняется —
  навигации у модуля нет.
- `HostRail` — кнопка «Уведомления» в `rail-bottom` над «Администрированием» при признаке
  `true` и `unread` (с признаком недоступности и подсказкой «Конфигурация консоли не
  прочитана»); при `false` кнопки нет. Значок и доступное имя — `unreadBadge` (З7) из
  `unread-poll`.
- `host/src/App.tsx` — `/notifications/*`: `true` → ленивый `NOTIFY_PAGE_LOADER` в
  `ModuleErrorBoundary`; `false` → названная страница «Уведомления в этой установке не
  подключены»; `unread` → названная страница с кнопкой «Повторить» (З2 п.3). Перевод на панель
  (`path="*"`) для этих адресов не срабатывает.
- `SERVICES.notify = { title: "Уведомления", menuTitle: "Уведомления" }` — в каноне
  `shared/src/lib/entity-names.ts`, затем в зеркале хоста `host/src/lib/entity-names.ts`
  (порядок правки задан шапкой зеркала; держатель — `HostBreadcrumb.names.test.ts`).

### З15. Пояснение отказа в правах (Р17)

Меняется только значение `FORBIDDEN_EXPLANATION` в `shared/src/lib/error-presentation.ts`;
словарь `REFUSALS` и запасной разбор `403` читают ту же константу, поэтому новый текст
действует на всех экранах с `403` (CX6-13). Своего пояснения модуль `notify` не заводит.
Держатель — DoD 12 (проба словаря утверждает новый текст; `git grep -c 'администраторам платформы' -- ui-future` → 0).

### З16. Данные ответа — только текстом

В файлах обхода DoD 11 (`ui-future/notify/src/**` и файлы `shared`, импортирующие
`@shared/api/notify`) `dangerouslySetInnerHTML` — ноль; `initiator` дословно (Р8). Обход
для DoD 6 (литералы) и DoD 11 (вывод HTML) — **одна функция переписи**
`ui-future/notify/src/test/notify-surface-census.ts`, два гейта её зовут; второго обхода нет.

### З17. Фикстуры G1

`ui-future/e2e/specs/fixtures.ts` получает `inviteIntoAccount`, `ownUserId`, `onlyAccount`
(Р14, DoD 14); `users.spec.ts` их импортирует, `secondAccountMembership` остаётся в нём и
зовёт `inviteIntoAccount`. Вызов `users:invite` в дереве проб — один.

### З18. Держатели, заказанные разбором, и где они живут

| пункт | проба | файл |
|---|---|---|
| CX6-05 | опоздавший ответ; отметка во время цикла; схлопывание | `ui-future/host/src/lib/unread-poll.test.ts` |
| CX6-06 (б) | `200` не той формы → отказ, по каждой функции чтения и мутации | `ui-future/shared/src/api/notify.test.ts`; экранные ветки — З13 |
| CX6-08 | цель на второй странице; отказ создания → перечитывание; кандидат на второй странице | `ResourceDetailExtensions.test.tsx`, `NotificationContactsPage.test.tsx` |
| CX6-11 | экран настроек при отказе каталога/настроек | `NotificationSettingsPage.test.tsx` |
| CX6-15 | каждый location с `add_header` в отрендеренной раздаче хоста и модулей несёт набор заголовков защиты уровня `server` | `ui-future/deploy/console_location_security_headers_test.go` (обход блоков `location` рендера; печать числа; пустой обход — красный; инъекция location без include — красный) |
| CX6-16 | два вызова загрузчика — один запрос; выход из `unread` | `ui-future/shared/src/lib/console-config.test.ts` |
| CX6-17 | пометки за первой страницей | `unread-count.test.ts`, `NotificationCenterPage.test.tsx` |
| CX6-19 | две карточки подряд — каталог и список по одному разу | `ResourceDetailExtensions.test.tsx` |
| CX6-09 | ноль `GET /operations` при `done = true` | `ui-future/shared/src/api/notify.test.ts` |

Модульные пробы шлют запросы в подменённый клиент с управляемыми ответами; ожидание —
условием, часы — управляемые (`jest.useFakeTimers`), без пауз.

### З19. Закрепление образа модуля на стендах

Каждый профиль зонтика, закрепляющий образы модулей консоли (M11: `uif.<модуль>.image`), при
флаге `true` в своей цепочке получает `uif.notify.image` тем же видом закрепления (ветка и
коммит сборки), что соседние модули того же профиля; профиль без закрепления образов модулей
получает образ подстановкой из образа хоста (`_helpers.tpl`). Образ публикует матрица
`build` `ui.yml` (§10 п.18). Достижимость закреплённого образа держит существующий гейт
`deploy/published_image_pin_is_reachable*`; профиль с флагом `true` без опубликованного образа
`notify` — его красное, а не ошибка выкатки.

## 3. Инварианты

| № | инвариант | чем держится |
|---|---|---|
| И1 | `shared` не импортирует модули; `host → notify` только федерацией | `module-boundary-coverage.test.ts`; предикат §1.8 приёмки |
| И2 | у признака Р2 нет умолчания: ни `import.meta.env`, ни значения в `values.yaml` подчарта, ни запасного исхода | DoD 6 (`notificationsEnabled` только в `console-config.ts`); рендер подчарта без `global.kacho` → тело `null` (З5); `console-config.test.ts` |
| И3 | одно окно — один исход признака | `console-config.test.ts` (CX6-16) |
| И4 | «не `200`» и «`200` не той формы» — один исход на каждом экране; пустота показывается только на ответ `200` с пустым массивом | `notify.test.ts`, экранные пробы З13; NTF6-56…59 |
| И5 | после найденного `seenUpTo` строки ниже не «новые» на любой странице | `unread-count.test.ts` (CX6-17) |
| И6 | ни одна ветка исхода операции не показывает успех без `done && !error` | `notify.test.ts` (З8) |
| И7 | один клиент, один счёт, один загрузчик, один переход, одна проверка id | DoD 6 (предикаты по имени и пути); вторая реализация под другим именем — вниманием рецензента диффа (`ui-reviewer`, пункт чек-листа), разбор CX6-02 |
| И8 | неотключаемое не попадает в `:setEntries` | З13; NTF6-27, 28, 31 |
| И9 | каждый location раздачи с собственным `add_header` включает заголовки защиты | `console_location_security_headers_test.go` (CX6-15) |
| И10 | признак консоли совпадает с развёртыванием `notify` на каждой поставляемой цепочке | `deploy/console_notify_flag_parity_test.go` (З5, DoD 8) |
| И11 | адрес ресурса строит только `resourceDetailHref`; из ответа принимаются только сегменты в алфавите id | `id-form.test.ts`, `InboxItemRow.test.tsx`, NTF6-16 |

## 4. Компоненты и границы

Дерево — `PRO-Robotech/kacho`. «Новый» — файла нет на `1d42a6728bf`.

| компонент | путь | новый/правка | бандл-владелец | читают |
|---|---|---|---|---|
| клиент `notify` | `ui-future/shared/src/api/notify.ts` | новый | компилируется в каждый потребитель | хост, `notify`, карточка в модулях |
| признак Р2 | `ui-future/shared/src/lib/console-config.ts` | новый | то же; состояние — на окне | хост, `notify`, карточка |
| счёт Р18 | `ui-future/shared/src/lib/unread-count.ts` | новый | то же | хост, `notify` |
| проверка id | `ui-future/shared/src/lib/id-form.ts` | новый | то же | `notify` |
| переход спека↔модуль/тип | `ui-future/shared/src/lib/subscription/subjects.ts` | правка | то же | карточка, `notify` |
| действие подписки | `ui-future/shared/src/components/organisms/ResourceDetailExtensions/` | правка | каждый модуль с карточкой | — |
| пояснение `403` | `ui-future/shared/src/lib/error-presentation.ts` | правка | все | все экраны |
| имена разделов | `ui-future/shared/src/lib/entity-names.ts`, `ui-future/host/src/lib/entity-names.ts` | правка | все / хост | рейл, панель недоступности |
| опрос счётчика | `ui-future/host/src/lib/unread-poll.ts` | новый | хост | `HostRail` |
| рейл, маршрут, каталог | `ui-future/host/src/{components/organisms/HostRail,components/atoms/RailButton,App.tsx,remotes/moduleCatalog.ts,lib/module-navigation.tsx}` | правка | хост | — |
| сборка хоста | `ui-future/host/{vite.config.ts,jest.config.cjs,Dockerfile}` | правка | хост | — |
| модуль | `ui-future/notify/**` | новый | `notify` | хост (федерация) |
| корневые сценарии | `ui-future/package.json` | правка | — | конвейер |
| чарт консоли | `ui-future/deploy/{values.yaml,templates/*}` | правка + `deployment-notify.yaml` новый | — | зонтик |
| гейты чарта | `ui-future/deploy/console_notify_render_test.go`, `console_location_security_headers_test.go`, `console_notify_source_key_test.go`; `deploy/console_notify_flag_parity_test.go` | новые | — | конвейер |
| профили стендов | `deploy/helm/umbrella/values.a8f60d.yaml` (и каждый профиль, закрепляющий образы модулей, — З19) | правка | — | стенд |
| конвейер | `.github/workflows/ui.yml`, `.github/workflows/console-e2e.yml` | правка | — | — |
| сквозные пробы | `ui-future/e2e/specs/{fixtures.ts,users.spec.ts,notifications-*.spec.ts}` | правка + новые | — | `console-e2e.yml` |

**Граница с соседями.** Край (`gateway/**`: маршруты `/notify/v1/*`, карта операций),
служба `notify`, её чарт и флаг — не этого изменения (NTF-1, NTF-3). Изменение NTF-6 не
трогает `gateway/`, `services/`, `proto/`, `corelib`, `kaname`.

## 5. Набросок контракта

**proto — нет.** Контракт — NTF-3 (Д15, Р3 приёмки); консоль своего proto не заводит.
Ниже — форма, которую **читает** клиент (после перевода регистра клиентом края, M6); она
сверяется с proto NTF-3 гейтом `console-verb-routes-exist.test.ts` (пути) при посадке NTF-3.

```ts
// ui-future/shared/src/api/notify.ts — только читаемые поля
export const RESOURCE_CHANGE = "RESOURCE_CHANGE";
export const EMAIL = "EMAIL";
export const CONSOLE = "CONSOLE";
export const ALWAYS = "ALWAYS";
export const SWITCHABLE = "SWITCHABLE";
export const NOTIFY_SEEN_EVENT = "kacho:notify-seen";
export const NOTIFY_SUBSCRIPTIONS_EVENT = "kacho:notify-subscriptions";

export interface InboxItem { module: string; kind: string; resource_type: string; resource_id: string;
  project_id: string; change: string; initiator: string; occurred_at: string; name: string; position: string }
export interface InboxPage { items: InboxItem[]; next_page_token: string }
export interface CatalogChannelCell { channel: string; policy: typeof ALWAYS | typeof SWITCHABLE }
export interface CatalogKind { key: string; display_name: string; class: string; channels: CatalogChannelCell[] }
export interface Catalog { modules: { key: string; display_name: string; kinds: CatalogKind[] }[];
  channels: { key: string; display_name: string }[] }
export interface PreferenceEntry { module: string; kind: string; channel: string;
  state: "ENABLED" | "DISABLED"; explicit: boolean }
export interface Preferences { entries: PreferenceEntry[]; digest_period: "HOUR" | "DAY"; seen_up_to: string }
export interface NotificationSubscription { id: string; channel: string; created_at: string;
  target: { resource?: { resource_type: string; resource_id: string };
            project?: { project_id: string; module: string } } }
export interface AccountNotificationContacts { account_id: string;
  security: { user_id: string; source: "EXPLICIT" | "ACCOUNT_OWNER" } }
```

Имена событий окна — строки с приставкой `kacho:`, чтобы не совпасть с событиями чужих
библиотек; сравнение — только по константе.

## 6. Схема БД

**DDL — нет.** Консоль состояния не хранит; всё состояние — у `notify` (NTF-3) и в памяти
окна. `localStorage` не используется: признак, счёт и кэш не переживают перезагрузку
намеренно (исход после перезагрузки — от сервера).

## 7. Последовательности

**П1. Старт окна.**
хост монтируется → `loadConsoleConfig()` создаёт объект на окне, `GET /console-config.json`
→ модуль с карточкой монтируется → `loadConsoleConfig()` получает тот же объект (запроса нет)
→ исход `true`: рейл показывает кнопку, `unread-poll` запускает цикл; `false`: кнопки нет;
`unread`: кнопка с признаком недоступности, запросов к `/notify/v1/*` нет → возврат в фокус →
повторное чтение → `true`: слушатели всех бандлов перерисованы.

**П2. Цикл счётчика.**
триггер → цикл в полёте? (таймер/фокус — выход) → `gen++` → `GET /notify/v1/inbox?pageSize=100`
∥ `GET /notify/v1/preferences` → оба `200` и форма верна → `unreadCount(page1, seen_up_to, token≠"")`
→ `gen` совпал → значок; иначе ответ отброшен. Любой отказ → `"!"`.

**П3. «Отметить всё просмотренным».**
центр → `PATCH /notify/v1/preferences` (маска `seen_up_to`) → `Operation{done:true}` →
`settleNotifyOperation` → успех → `window.dispatchEvent(NOTIFY_SEEN_EVENT)` → хост: `gen++`,
отмена цикла в полёте, новый цикл → значок гаснет; центр перечитывает настройки → пометки сняты.
Отказ → значок прежний, текст отказа (NTF6-15).

**П4. Подписка с карточки.**
карточка (бандл `vpc`) → признак `true` → `["notify","catalog"]` (кэш) → ячейка `(RESOURCE_CHANGE,
EMAIL: SWITCHABLE)` у `notifyModuleOf("networks") = "vpc"` → `["notify","subscriptions"]` (кэш,
полный обход) → «Подписаться» → `POST /notify/v1/subscriptions` → `done && !error` → событие
`NOTIFY_SUBSCRIPTIONS_EVENT` → все бандлы инвалидируют ключ → «Вы подписаны» из перечитанного
списка. Отказ → событие, перечитывание, текст отказа.

**П5. Отписка на экране настроек и возврат на карточку.**
`notify` → `DELETE /notify/v1/subscriptions/{id}` → успех → событие → бандл `vpc` инвалидирует
ключ (слушатель модуля `notify.ts`) → переход на карточку → список перечитан → «Подписаться на
изменения» (NTF6-36).

**П6. Сохранение настроек.**
форма → разница по `SWITCHABLE` → пусто: запроса нет; иначе `POST :setEntries` с разницей →
`done` → перечитывание настроек → `explicit` снят с пометки «по умолчанию».

**П7. Контакт безопасности.**
`GET …/contacts` → `200` и `security` есть → строка; иначе отказ, выбора и сохранения нет →
выбор из полного списка пользователей аккаунта → `PATCH …/contacts` (маска `security`) → `done` →
перечитывание.

## 8. Конфигурация, ручки и границы

**Ручки установки.** Своей ручки включения у консоли нет (Р2).

| ручка | владелец | граница / исходы | где читается |
|---|---|---|---|
| `global.kacho.notifications.enabled` | NTF-1 Р9 | логическое; не задано — рендер зонтика отвергнут NTF-1; в отдельном рендере подчарта — тело `null` → `unread` | `configmap-nginx.yaml`, `_helpers.tpl` (`ui.notifyEnabled`) |
| `notify.{name, replicas, image, imagePullPolicy, port, resources}` | этот чарт | та же форма и те же границы, что у блоков соседних модулей `values.yaml`; `image: ""` — подстановка из образа хоста | шаблоны модуля |
| `notify.autoscaling.{enabled, minReplicas, maxReplicas, targetCPUUtilizationPercentage}` | этот чарт | как у соседей; держатель — `module_autoscaling_test.go` (перепись модулей обходом) | `hpa.yaml` |
| `host.upstreams.notify` | этот чарт | пусто — адрес сервиса модуля в пространстве релиза | `_helpers.tpl` |
| `KACHO_NOTIFY_REMOTE` (аргумент сборки хоста) | `host/Dockerfile` | умолчание `/notify-remote/assets/remoteEntry.js`, как у соседей | `host/vite.config.ts` |

**Величины консоли** (константы кода, не ручки установки; у каждой — одно место):

| величина | значение | место | основание |
|---|---|---|---|
| период опроса счётчика | 60 с | `host/src/lib/unread-poll.ts` | Р4 |
| страница ленты хоста | 100 | `unread-poll.ts` | Р18 |
| страница ленты центра | 50 | `NotificationCenterPage` | NTF6-06 |
| страница подписок | 1000 | `notify.ts` | граница ручки NTF-3; обход до пустого токена |
| страница пользователей | 1000 | `shared/src/api/iam.ts` | предел края для списка |
| потолок значка | 99 | `unread-count.ts` | Р18 |
| повторов чтения признака в полёте | не больше одного | `console-config.ts` | З2 |

## 9. Рёбра

| ребро | вид | новое? | основание |
|---|---|---|---|
| консоль → край → `notify-api` (`/notify/v1/*`) | runtime, HTTP через раздачу хоста | ребро «консоль → край» существующее; маршруты края — NTF-3 | §10 приёмки |
| раздача хоста → край (префикс `notify`) | runtime, nginx | правка перечня | З3 |
| раздача хоста → сервис модуля `ui-notify` | runtime, nginx | новое внутри чарта консоли | З3, З4 |
| хост → модуль `notify` | сборка, федерация | новое | З1 |
| `notify`, хост, модули → `shared` | сборка, алиас | существующее направление | И1 |
| бандл ↔ бандл | runtime, события окна `NOTIFY_SEEN_EVENT`, `NOTIFY_SUBSCRIPTIONS_EVENT`; объект признака на окне | новое | З2, З9, З10 |

Межсервисных рёбер изменение не заводит; ацикличность графа служб не затрагивается.

**Внешние зависимости и заказы:**

| № | что | чей предмет | как снимается |
|---|---|---|---|
| Е1 | одобрение NTF-1 с Р9 | NTF-1 | снято: запись `APPROVED` на `530e2296` (коммит `a67820c41`) |
| Е2 | одобрение NTF-3 в форме §1.7 приёмки | NTF-3 | запись `APPROVED` на отпечаток NTF-3 с той же формой Р9, Р10, Р11, Р20, Р29; иная форма — новая редакция приёмки NTF-6 (Р13) |
| Е3 | подчарт `notify` и флаг в зонтике | NTF-1 | посажено в ствол; рендер зонтика несёт `charts/notify/templates/` |
| Е4 | `notify-api` за краем с маршрутами `/notify/v1/*` и каталогом на стенде | NTF-3 | посажено; предпосылка стенда DoD 13 зелёная |
| Е5 | маршрут приставки операций `notify` в `prefixToBackend` края либо записанное производителем «`done = false` у `notify-api` не бывает» с держателем | NTF-3 (заказ разбора CX6-09) | запись в приёмке NTF-3; для NTF-6 не блокирует (З8) |

## 10. Перепись мест, перечисляющих модули руками (CX6-10)

Предикат — M1 (14 файлов) плюс места вне `ui-future`, названные приёмкой, и тестовые перечни
M2. Решение по каждому.

| № | место | решение | основание |
|---|---|---|---|
| 1 | `ui-future/host/src/remotes/moduleCatalog.ts` | **правится**: запись `notify` без раздела; комментарий о модулях без раздела | Р1, §3 приёмки |
| 2 | `ui-future/host/src/App.tsx` | **правится**: маршрут `/notifications/*` по признаку | Р2, З14 |
| 3 | `ui-future/host/src/lib/module-navigation.tsx` | **правится**: `NOTIFY_PAGE_LOADER`; `REMOTE_NAV_LOADERS` — **не** правится (навигации нет) | З14 |
| 4 | `ui-future/host/vite.config.ts` | **правится**: удалённый модуль `notify` (`KACHO_NOTIFY_REMOTE`, dev `http://localhost:4183/assets/remoteEntry.js`); прокси dev-сервера `/notify/v1` на край | З1 |
| 5 | `ui-future/host/jest.config.cjs` | **правится**: `^notify/NotifyPage$` → заглушка `src/test/notify-remote.tsx` | пробы хоста NTF6-02 |
| 6 | `ui-future/host/Dockerfile` | **правится**: `ARG`/`ENV KACHO_NOTIFY_REMOTE` | §8 |
| 7 | `ui-future/package.json` | **правится**: `notify` в `typecheck`, `lint`, `format:check`, `test`; в `workspaces` — **нет** (самостоятельный пакет) | З1, M10 |
| 8 | `ui-future/shared/src/lib/entity-names.ts` | **правится**: `SERVICES.notify` (канон) | З14 |
| 9 | `ui-future/deploy/values.yaml` | **правится**: блок `notify`, `host.upstreams.notify`; ключа `global.kacho.notifications` **нет** | З3, З4, И2 |
| 10 | `ui-future/deploy/templates/_helpers.tpl` | **правится**: `ui.notifyEnabled`, имя, образ, политика, апстрим | З4 |
| 11 | `ui-future/deploy/templates/service.yaml` | **правится**: блок под условием | З4 |
| 12 | `ui-future/deploy/templates/hpa.yaml` | **правится**: блок под условием | З4 |
| 13 | `ui-future/deploy/templates/configmap-nginx.yaml` | **правится**: префикс, `/console-config.json`, `/notify-remote/`, раздача модуля | З3 |
| 14 | `ui-future/deploy/templates/deployment-host.yaml` | **правится**: `KACHO_UI_NOTIFY_UPSTREAM` под условием | З4 |
| 15 | `ui-future/host/src/lib/entity-names.ts` (7 из 8 — без `dashboard`) | **правится** вслед за каноном | шапка зеркала |
| 16 | `ui-future/deploy/templates/ingress.yaml` | **не правится**: модулей не перечисляет (M9) | M9 |
| 17 | `ui-future/deploy/templates/deployment-notify.yaml` | **заводится** | З4 |
| 18 | `.github/workflows/ui.yml` | **правится**: `STANDALONE`, матрица `test` (`pkg`), матрица `build` (`project`), имя задания `typecheck` (число пакетов) | DoD 9, M10 |
| 19 | `.github/workflows/console-e2e.yml` | **правится**: шаг предпосылки DoD 13 | DoD 13 |
| 20 | `deploy/helm/umbrella/values.*.yaml`, закрепляющие образы модулей консоли (M11) | **правится**: `uif.notify.image` в каждом профиле, чья цепочка рендерит модуль (флаг `true`), тем же видом закрепления, что соседи; достижимость образа — существующий гейт `published_image_pin_is_reachable` | З19 |
| 21 | `ui-future/shared/src/components/molecules/Toaster/Toaster.mounted.test.ts` (`MUTATING_MODULES`) | **правится**: `notify` — мутирующий модуль | M2 |
| 22 | `ui-future/shared/src/test/console-verb-routes-exist.test.ts` (`CONSOLE_APPS`) | **правится**: `notify` | M2 |
| — | `ui-future/dashboard/**`, `vpc`, `compute`, `storage`, `nlb`, `registry`, `iam`, `system` | исходники **не** правятся; образы пересобираются, потому что `shared` компилируется в бандл (карточка, Р17) | §1.8 приёмки |
| — | `ui-future/dev-federation.sh` | **не** правится: состав выводит из `host/vite.config.ts` | чтение скрипта |

## 11. Отображение пунктов разбора в решения

Каждый пункт первичного разбора на `47bd8b70` → решение замысла → механизм → держатель.

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX6-01 | З11 | `NOTIFY_SOURCE_BY_OWNER` исчерпывающий по типу; `notifyModuleOf` — единственный читатель | `console_notify_source_key_test.go`, `subjects.test.ts`, NTF6-60 |
| CX6-02 | З6, З7, З2, И7 | клиент, счёт, загрузчик — `shared`, по одному; вторая реализация под другим именем — пункт чек-листа `ui-reviewer` | DoD 6; рецензент диффа |
| CX6-03 | З10 | действие составляется рядом с расширением спеки | `ResourceDetailExtensions.test.tsx` |
| CX6-04 | З2, З3 | канал во время работы, три исхода, без умолчания | NTF6-61, NTF6-02, NTF6-47, `console-config.test.ts` |
| CX6-05 | З9 | поколение, один цикл в полёте, сброс по `NOTIFY_SEEN_EVENT`, схлопывание | `unread-poll.test.ts` |
| CX6-06 (а) | З3 | префикс `notify` в перечне безусловно | NTF6-47, NTF6-22 |
| CX6-06 (б) | З6, З13, И4 | разборщик формы на каждую функцию; `RESPONSE_SHAPE` — тот же исход, что не-`200` | `notify.test.ts`, экранные пробы З13 |
| CX6-07 | З12 | `isPlatformId` до `ResourceLink` | `id-form.test.ts`, NTF6-16 |
| CX6-08 | З6, З10, З13 | полный обход подписок и пользователей; перечитывание после отказа | `ResourceDetailExtensions.test.tsx`, `NotificationContactsPage.test.tsx` |
| CX6-09 | З8, Е5 | при `done = true` опроса нет; `done = false` — общий путь, отказ показан отказом; маршрут края — заказ NTF-3 | `notify.test.ts`; NTF6-27, 36, 38, 43, 52 |
| CX6-10 | §10 | перепись 22 мест с решением по каждому | DoD 9, 10; гейты с переписью обходом; остальное — рецензент диффа по §10 |
| CX6-11 | З13 | одно состояние загрузки; подстановки пустого нет | `NotificationSettingsPage.test.tsx` |
| CX6-12 | З13 | `:setEntries` из разницы по `SWITCHABLE` | NTF6-27, 28, 31; `NotificationSettingsPage.test.tsx` |
| CX6-13 | З15 | меняется только значение константы | DoD 12 |
| CX6-14 | З16 | обход DoD 11 включает файлы `shared`, импортирующие клиент; одна функция переписи | гейт DoD 11, NTF6-18 |
| CX6-15 | З3, И9 | `include ui.securityHeaders` в каждом новом location; гейт по рендеру | `console_location_security_headers_test.go` |
| CX6-16 | З2, И3 | состояние на окне под `Symbol.for`; выход из `unread` по фокусу и «Повторить» | `console-config.test.ts` |
| CX6-17 | З7, И5 | счёт над сцепкой загруженных страниц | `unread-count.test.ts`, `NotificationCenterPage.test.tsx` |
| CX6-18 | З12 | пустой `projectId` → `null`; негодный непустой → текст; предикат пересмотра сохранён | `InboxItemRow.test.tsx`; предикат пересмотра |
| CX6-19 | З10 | кэш бандла `staleTime: Infinity`; сброс мутацией и `NOTIFY_SUBSCRIPTIONS_EVENT` | `ResourceDetailExtensions.test.tsx` |

Неотображённых пунктов нет: 19 из 19 (CX6-06 — двумя строками).

## 12. Что замысел не делает

- Не заводит поток подписки для ленты (Р4) и хранения на стороне консоли (§6).
- Не правит край, службу `notify`, её чарт и контракт — предмет NTF-1 и NTF-3; маршрут
  операций `notify` на краю — заказ Е5.
- Не заводит экранов извещений оператора (NTF-5 Р22 — отдельная стадия после одобрения NTF-5,
  §4 приёмки).
- Не держит второго представления каталога модулей: всё, что консоль знает о модулях
  уведомлений, приходит каталогом (Р5); ручной перечень §10 — о модулях **консоли**, не о
  модулях уведомлений.

## 13. Открытые решения

Нет. Решения З1–З19 приняты; зависимости Е2–Е5 — предметы соседей с названным предикатом
снятия, а не открытые решения этого замысла.
