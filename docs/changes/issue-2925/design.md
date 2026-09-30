<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2925 (NTF-6, консоль уведомлений) — замысел

> **Что этот документ.** Технические решения, инварианты и отображение каждого пункта
> разбора классов в механизм (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`
> §2 «Truth ownership»: `design.md` — technical decisions, invariants, exposure mapping).
> Наблюдаемое поведение здесь не описывается и не переопределяется: его единственный
> владелец — приёмка. Порядок работ — `tasks.md` рядом.
>
> **Редакция 5 · 2026-09-30.** Вердикта на неё нет; действующий вердикт выводится из записи
> ревью на отпечаток этого файла (`reviews/design/<role>/<sha256>.yaml`) и из пересверки
> разбора классов (`reviews/class-exposure/revalidation/<sha256>.yaml`).
>
> **Что изменено против редакции 4 (`7294a684`) и почему.** Пересверка разбора классов на
> `7294a684` (`reviews/class-exposure/revalidation/7294a684….yaml`, `к-замыслу`) завела пункты
> CX6-26…30 без строк §11: дедлайн чтения признака с отменой (CX6-26); дедлайн цикла счётчика
> без отмены — хвост запросов без получателя, ложный довод «каждый таймер находит прежний цикл
> завершённым» и неназванный предел хвоста (CX6-27); охрана «одна мутация на действие»
> отрисованным `isPending`, который отстаёт от нажатия на одну макрозадачу (CX6-28); пометки из
> пары «настройки + лента», перечитанной после отметки, — промежуточная пара помечает новым всё
> (CX6-29); предикат снятия Е6, судящий слово, а не предмет, и порядок «наибольшего» (CX6-30).
> Изменено: строки §11 CX6-26…30; синхронная охрана мутации — хук `useGuardedMutation`
> (З10, З13, И19, З20, §4); довод о `POLL_DEADLINE_MS` снят и предел хвоста назван —
> `proxy_read_timeout 30s` location префиксов края (З9, §8, M24); пометки центра — только из
> согласованной пары (З13, И20, З18); Е6 — предикат по ID сценария в Р10 одобренного отпечатка
> и порядок позиции (§9, M25, M22 перемерен); имена дедлайнов `T1`/`T2` редакции 4 совпадали с
> полосой `T1` `tasks.md` — дедлайны названы константами `CONFIG_DEADLINE_MS` и
> `POLL_DEADLINE_MS` (§8); §0 — пересверка `7294a684` и редакция 21 NTF-3; §11а — условия
> пересверки `7294a684`.
>
> **Что изменено в редакции 4 против редакции 3 (`defdbe67`) и почему.** Ревью замысла на `defdbe67`
> (`reviews/design/design-reviewer/defdbe67….yaml`, `CHANGES_REQUESTED`) вернуло замысел: у
> чтения `/console-config.json` и у цикла опроса счётчика нет дедлайна, а оба держат «не больше
> одного в полёте» — зависший запрос останавливает механизм навсегда (B1); запись `seen_up_to`
> из давно открытого окна откатывает отметку (I1); второе нажатие «Подписаться» во время
> мутации не исключено (I2); граница устаревших циклов не названа (I3). Пересверка разбора
> классов на `defdbe67` (`reviews/class-exposure/revalidation/defdbe67….yaml`, `к-коду`)
> поставила условия к коду по CX6-25 и строке 31 §10 и заказала правку §0 и Е1. Изменено:
> новое решение З20 — перепись механизмов с дедупликацией в полёте и решение по каждому;
> дедлайны `T1` (признак, З2 п.3) и `T2` (цикл опроса, З9) на управляемых часах, одно место —
> §8; инвариант И18; исход цикла применяется однократно (И14); граница устаревших циклов и
> прочтение фразы приёмки (З9); опора на монотонную отметку `seen_up_to` решением диспетчера
> Д25 и зависимость Е6, перечитывание ленты после отметки (З13); одна мутация на действие в
> полёте, И19 (З10, З13); условия пересверки — снимок исхода у позднего подписчика (З14) и
> форма блока шаблона раздачи модуля (З3, §10 строка 31); шапка `shared/src/lib/config.ts`
> (З2 п.7); шапки синтетических входов `internal/repohygiene` (§4); §0 и Е1 — по факту
> (приёмка NTF-1 `29cfa368`, `APPROVED`); §11а — отображение условий ревью и пересверки.
>
> **Что изменено в редакции 3 против редакции 2 (`deeea79a`) и почему.** Пересверка на `deeea79a` вернула
> замысел (`reviews/class-exposure/revalidation/deeea79a….yaml`): CX6-10 не выдерживал условия —
> перепись тестовых перечней M2 назвала 2 перечня модулей, написанных руками, а их 6; новый пункт
> CX6-25 (асинхронный путь `rememberLoad`) строки не имел; CX6-22 — с условием к коду (обход
> пользователей повторялся бы на отказ формы). Изменено: M2 перемерен (§1) и в §10 внесены строки
> 28–32 с решением по каждому перечню; `rememberLoad` снимает и публикует только по идентичности
> хранимого обещания, у подписчика названо третье состояние `pending` и ветка кнопки рейла на нём
> (З14, CX6-25); запросы модуля `notify`, включая обход пользователей, исполняет клиент запросов с
> умолчанием `retry: notifyQueryRetry` (З6, З13, CX6-22); строка CX6-25 в §11.
>
> **Что изменено в редакции 2 против редакции 1 (`7613071f`) и почему.** Пересверка на `7613071f` вернула
> замысел (`reviews/class-exposure/revalidation/7613071f….yaml`): CX6-10 не выдерживал условия,
> у новых пунктов CX6-20…24 не было строк. Изменено: перепись §10 — 15 файлов по M1, а не 14, и
> места по образцу модуля (M13); монтирование модуля — обёрткой `NotifyRemote.tsx` общей
> фабрикой (З14); признак Р2 — четыре состояния с исчерпывающим ветвлением и имя «не
> прочитано», не совпадающее со счётчиком (З2, CX6-21); отказ формы — свой класс ошибки без
> HTTP-статуса и без повтора (З6, CX6-22); отмены цикла нет, устаревший цикл отбрасывается
> поколением на обеих ветках (З9, CX6-23); слушатели событий окна — хуком внутри провайдера
> кэша с отпиской (З10, CX6-20); обход пользователей несёт аккаунт (З13, CX6-24); отпечаток
> NTF-3 в §0 — по факту.

## 0. Входы и на чём стоит замысел

| вход | координата | отпечаток / ревизия | состояние |
|---|---|---|---|
| приёмка NTF-6 | `docs/specs/sub-phase-NTF-6-console-notification-center-acceptance.md` | `47bd8b7054c3313c535fe74b53cffc21ae9f59f922e4dae23281453bc47c5328` | `APPROVED`, запись `docs/specs/reviews/sub-phase-NTF-6-console-notification-center-acceptance/47bd8b70….yaml` |
| первичный разбор классов | `docs/changes/issue-2925/reviews/class-exposure/initial/47bd8b70….yaml` | тот же отпечаток | `к-коду`, возврата в приёмку нет; пункты CX6-01…19 |
| пересверка на редакцию 1 | `docs/changes/issue-2925/reviews/class-exposure/revalidation/7613071f….yaml` | замысел `7613071f` | `к-замыслу`; новые пункты CX6-20…24; в приёмку не возвращено ничего |
| пересверка на редакцию 2 | `docs/changes/issue-2925/reviews/class-exposure/revalidation/deeea79a….yaml` | замысел `deeea79a` | `к-замыслу`; CX6-10 не выдерживал (M2); новый пункт CX6-25; условие к коду по CX6-22; в приёмку не возвращено ничего |
| пересверка на редакцию 3 | `docs/changes/issue-2925/reviews/class-exposure/revalidation/defdbe67….yaml` | замысел `defdbe67` | `к-коду`; 25 из 25 выдерживают; условия к коду по CX6-25 и CX6-10 (строка 31 §10); заказ замыслу — §0 и Е1; новых пунктов нет. Отображение условий — §11а |
| ревью замысла на редакцию 3 | `docs/changes/issue-2925/reviews/design/design-reviewer/defdbe67….yaml` | замысел `defdbe67` | `CHANGES_REQUESTED`: B1, I1–I3 и три заметки вне замысла. Отображение — §11а |
| пересверка на редакцию 4 | `docs/changes/issue-2925/reviews/class-exposure/revalidation/7294a684….yaml` | замысел `7294a684` | `к-замыслу`; CX6-01…25 — 25 из 25 выдерживают; новые пункты CX6-26…30 без строк §11; заказы замыслу, автору NTF-3 и полосе E1. Отображение — §11 и §11а |
| дерево продукта | `PRO-Robotech/kacho` | `origin/main@1d42a6728bf` | все замеры §1 — на этой ревизии, если не сказано иное |
| контракт `notify` | приёмка NTF-3, в форме §1.7 приёмки NTF-6 (`ee6f908e`) | в ветке на `235d4f37f` — `c481e642…` (редакция 21, коммит `88fa559c7`); одобренная — `88ad95c6…` (редакция 20) | запись `APPROVED` есть только на `88ad95c6`, в Р10 которой Д25 нет (M22); редакция 21 вносит Д25 в Р10 и сценарий NTF3-161 (M25), записи ревью на `c481e642` нет. Замысел зависит от формы §1.7 и от Д25 (Е2, Е6), а не от текущей редакции NTF-3 |
| ядро и флаг | приёмка NTF-1, Р9 | в ветке на `dfbeffbdb` — `29cfa368…` | `APPROVED`: запись `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/29cfa368….yaml` (коммит `d18efea9c`). Строк о флаге (`notifications.enabled`, `NTF1-N01`, `global.kacho`) в разнице `530e2296` (`2fa62337b`) → `29cfa368` (`HEAD`) — 0 (`git diff 2fa62337b HEAD -- <приёмка NTF-1> \| grep -E '^[-+][^-+]' \| grep -ciE 'notifications\.enabled\|NTF1-N01\|global\.kacho'` → 0) |

Решения диспетчера Д1–Д25 действуют без изменений. Из них предмет консоли задают Д7 (флаг
без умолчания), Д8 (модель получателей), Д9 (неотключаемое), Д15 (контракт — NTF-3), Д16
(в ствол — только одобренное), Д25 (отметка `seen_up_to` монотонна: сервер пишет
`GREATEST(старое, новое)` атомарно, откат назад невозможен — З13, Е6) и Д24 (каждое
утверждение о дереве — предикат с командой и числом на ревизии; §1). Д14 (надзор
администратора облака не распространяется на `notification_feed`) консоли не касается: консоль
ленту не читает потоком и объектов этого типа не адресует. Д17–Д19, Д21, Д23 — о слушателях
службы, шаблонах и секретах почты, поверхности консоли не меняют; Д20 (1) (`done = true` в ответе
мутации) уже отражён З8, Д20 (2) касается внешнего gRPC и REST-пути консоли не меняет; Д22
(условие к коду — в замысел, не в приёмку) задаёт, куда легли условия §11а. Сказано, чтобы
отсутствие отображения не читалось пропуском.

**Прода нет** (Д12, требование владельца «можно перестраивать все подряд»): переход прямой,
без второго пути и без флага совместимости; прежнего поведения консоли, которое пришлось бы
сохранять рядом, у предмета нет — поверхности уведомлений в консоли ноль (§1.1 приёмки).

## 1. Замеры, на которых стоят решения

Ревизия — `PRO-Robotech/kacho` `1d42a6728bf`, если не сказано иное. Команды исполнимы из корня
рабочей копии продукта.

| № | утверждение | команда | результат |
|---|---|---|---|
| M1 | файлов консоли, перечисляющих все восемь модулей руками | `git ls-tree -r --name-only 1d42a6728bf ui-future \| grep -vE '(^\|/)(e2e\|node_modules)/\|\.test\.\|/test/\|__mocks__\|package-lock\|\.md$\|\.snap$\|\.png$\|\.svg$'` → обойдено 1073 файла; по каждому `git show 1d42a6728bf:<файл> \| grep -oiE 'dashboard\|vpc\|compute\|storage\|nlb\|registry\|iam\|system' \| tr A-Z a-z \| sort -u \| wc -l`, порог 8 из 8 | **15** (перечень — §10, строки 1–15). Редакция 1 назвала 14: пропущен `ui-future/host/src/remotes/index.ts` (реэкспорт восьми обёрток `*Remote`) — опровергнуто пересверкой и повторено этим замером |
| M2 | тестовых перечней модулей, написанных руками | `git ls-tree -r --name-only 1d42a6728bf ui-future \| grep -v node_modules \| grep -E '\.test\.\|_test\.go$\|/test/'` → обойдено 469 файлов; по каждому `git show 1d42a6728bf:<файл> \| grep -oE '\b(dashboard\|vpc\|compute\|storage\|nlb\|registry\|iam\|system)' \| sort -u \| wc -l`, порог 7 из 8 → 16 попаданий; затем чтение объявлений каждого (массив-литерал против `readdirSync`/обхода каталога) | **6 перечней руками**, каждый обязан получить решение: `MUTATING_MODULES` (`shared/src/components/molecules/Toaster/Toaster.mounted.test.ts:63`); `CONSOLE_APPS` — четыре копии: `shared/src/test/console-verb-routes-exist.test.ts:62`, `shared/src/test/iam-pages-authz-single-source.test.ts:33`, `shared/src/components/organisms/form/ResourceIcon/ResourceIcon.registry.test.ts:27`, `shared/src/lib/spec-columns.bool-labels.test.ts:27` (шапки трёх требуют вносить новое приложение осознанно, иначе оно молча выпадает из сверки); `REMOTES` (`shared/src/test/ui-chart-remote-entry-cache.test.ts:38`, имена помощников `<mod>Name` чарта). Прочие 10 попаданий перечня модулей не держат: 5 выводят состав обходом каталога (`module-boundary-coverage`, `module-tailwind-scans-shared`, `module-test-setup-single-source`, `request-body-built-not-spread`, `shared-organisms-single-source`; `arrayContaining` в них — проверка предпосылки, а у `module-test-setup-single-source` ещё перечень освобождённых `EXCUSED` = `host`, `dashboard`), 1 — ведомость долга (`module-reachability-ledger.json`), 4 называют модули попутно (`InstancesPage.list`, `StoragePage.list`, `oneof-form-coverage`, `oneof-branch-coverage.ts`). Редакция 2 назвала 2 перечня — опровергнуто пересверкой `deeea79a` и повторено этим замером. Гейт `host/src/remotes/remote-boundary-coverage.test.ts` лежит вне порога (имена модулей в нём не перечислены) и сводит обходом `remotes` федерации `vite.config.ts`, обёртки `*Remote.tsx` и `moduleCatalog.ts` |
| M3 | край выбирает владельца операции ручной картой, приставки операций `notify` в ней нет | `git show 1d42a6728bf:gateway/internal/opsproxy/proxy.go \| sed -n 86,102p` | 8 ключей (`vpc`×2, `compute`, `iam`, `loadbalancer`, `registry`, `storage`, `geo`); неизвестная приставка → `INVALID_ARGUMENT` (`resolveBackend`) |
| M4 | общий `useOperation` опрашивает хотя бы раз и при `done = true` | `git show 1d42a6728bf:ui-future/shared/src/lib/use-operation.ts \| sed -n 18,34p` | `enabled: !!opId`, первый `GET /operations/{id}` уходит всегда |
| M5 | `QueryClient` создаёт **страница** модуля, а не модуль | `git grep -n -B3 'new QueryClient' 1d42a6728bf -- 'ui-future/*/src/*.ts*' ':!*test*'` | 7 мест (compute, iam, nlb, registry, storage, system, vpc), каждое — `useMemo` внутри компонента страницы: клиент живёт, пока смонтирована страница, и при повторном монтировании создаётся заново; кэш одного бандла другому не виден |
| M6 | клиент края переводит ответ в snake_case | `git show 1d42a6728bf:ui-future/shared/src/api/client.ts \| sed -n 128,138p` | `camelToSnake(parsed)`; ответ `200` не-JSON отдаётся вызывающему как `null`, а не отказом |
| M7 | адрес карточки без проекта у спек службы доступа | `git show 1d42a6728bf:ui-future/shared/src/components/molecules/ResourceLink/ResourceLink.tsx \| sed -n 50,57p` | `resourceServicePrefix(specId) === "iam"` → `/iam/<route>/<id>`; прочие без проекта → `null` |
| M8 | шаблон раздачи: location с собственным `add_header` и `include ui.securityHeaders` | `git show 1d42a6728bf:ui-future/deploy/templates/configmap-nginx.yaml \| grep -nE 'location\|add_header\|securityHeaders'` | у всех location хоста с `add_header` (`/healthz`, `= /index.html`, `^~ /assets/`, статика) include есть; гейта нет (разбор, CX6-15) |
| M9 | `ingress.yaml` модулей не перечисляет | `git show 1d42a6728bf:ui-future/deploy/templates/ingress.yaml \| grep -c 'path:'` | 1 (`/` → сервис хоста); точки входа модулей проксирует раздача хоста (`location ^~ /<mod>-remote/`) |
| M10 | пакеты консоли со своим lock-файлом | `git show 1d42a6728bf:.github/workflows/ui.yml \| sed -n 75p` | `STANDALONE: host dashboard compute storage nlb registry e2e`; workspaces корня — `shared vpc iam system` |
| M11 | образы модулей на стенде закреплены профилем | `git show 1d42a6728bf:deploy/helm/umbrella/values.a8f60d.yaml \| grep -c 'kacho-ui-future-'` | 9 (хост и восемь модулей), все — одним коммитом сборки; умолчание образа модуля — подстановка `host → <mod>` в теге хоста (`_helpers.tpl`) |
| M12 | сигналов окна между бандлами сегодня нет | `git grep -c 'window.dispatchEvent\|new CustomEvent' 1d42a6728bf -- ui-future/host/src ui-future/shared/src` | 0 — каналы окна заводятся этим изменением впервые |
| M13 | места, заводимые **по образцу модуля** (файл на модуль, имя модуля в имени файла), — вне M1; образец — `nlb`, самостоятельный пакет той же формы, что `notify` (M10) | `git ls-tree -r --name-only 1d42a6728bf ui-future \| grep -vE '^ui-future/nlb/\|node_modules' \| grep -E '(/\|-)(nlb\|Nlb)(Remote)?[.-]'` | 5: `host/src/remotes/NlbRemote.tsx`, `host/src/remotes/nlb.d.ts`, `host/src/test/nlb-remote.tsx`, `host/src/test/nlb-navigation.ts`, `deploy/templates/deployment-nlb.yaml` |
| M14 | обёртка удалённого модуля строится общей фабрикой, иначе гейт красный | `git show 1d42a6728bf:ui-future/host/src/remotes/remote-boundary-coverage.test.ts` | у каждого remote федерации — файл `^[A-Z]\w*Remote\.tsx$` с литералом `import("<remote>/<Page>")`, вызовом `makeRemote(` и `moduleLabelOf("<remote>")`; собственная связка `lazy`+граница — «форк фабрики», красный |
| M15 | общий клиент края сигнала отмены не принимает | `git show 1d42a6728bf:ui-future/shared/src/api/client.ts \| sed -n 105,175p` | `fetchJson(method, path, body, replayed)` строит запрос без `signal`; у `api.get/list/create/update/delete/action` параметра нет |
| M16 | `ApiError` со статусом `200` показывается общим «ошибка», и запрос повторяется | `git show 1d42a6728bf:ui-future/shared/src/lib/error-presentation.ts \| sed -n 362,368p`; `git grep -n -A4 'new QueryClient' 1d42a6728bf -- 'ui-future/*/src/*.ts*' ':!*test*' \| grep retry` | `statusFromHttp(200)` → `"error"`; `retry: 1` у пяти страниц, `isTest ? false : 1` у двух |
| M17 | `GET /iam/v1/users` без `accountId` не сужает до аккаунта | `git -C <kaname> show cbbac984b:internal/repo/kaname/pg/user_repo.go \| sed -n 375,385p` (ревизия `PRO-Robotech/kaname` `cbbac984b`) | условие членства добавляется только при непустом `AccountID`; пустой — все пользователи, видимые вызывающему |
| M18 | обхода пользователей в клиенте службы доступа нет | `git show 1d42a6728bf:ui-future/shared/src/api/iam.ts \| grep -nE 'listUsers\|listAll'` | `listUsers(q?)` — одна страница, `:755`; обход заводится этим изменением |
| M19 | у фабрики обёрток удалённых модулей предела времени загрузки нет | `git show 1d42a6728bf:ui-future/host/src/remotes/makeRemote.tsx \| grep -ciE 'timeout\|setTimeout\|deadline\|AbortSignal'` | 0; повтор (`attempt`) начинается только из границы отказа — зависшая загрузка любого из восьми модулей держит индикатор загрузки сегодня так же |
| M20 | механизма отмены по сроку в хосте и `shared` нет | `git grep -c 'AbortSignal\|AbortController' 1d42a6728bf -- 'ui-future/host/src' 'ui-future/shared/src' ':!*test*' \| wc -l` | 0 файлов; `fetch` в `client.ts` один (`:115`, `fetch(url, init)`), `init` без `signal` (M15) — дедлайн З20 заводится этим изменением впервые |
| M21 | шапка общего модуля конфигурации утверждает, что все параметры времени выполнения — переменные сборки | `git show 1d42a6728bf:ui-future/shared/src/lib/config.ts \| sed -n 3,6p` | «Все runtime-параметры — env (`VITE_*` …). Любое значение, которое отличается между dev / staging / prod — читается ОТСЮДА»; признак Р2 отличается между установками и читается не отсюда и не из env (З2, И2) — после З2 шапка ложна (З2 п.7) |
| M22 | приёмка NTF-3 в Р10 монотонности `seen_up_to` не записывает | `F=docs/specs/sub-phase-NTF-3-kacho-modules-notifications-acceptance.md; sed -n '/^\*\*Р10\./,/^\*\*Р11\./p' $F \| grep -ciE 'GREATEST\|назад\|только вперёд\|монотон'` (воркспейс, `dfbeffbdb`; блок Р10 — 32 строки) | 0; Д25 решает это за NTF-3, запись в приёмке — Е6. Перемерено тем же `sed` на ревизиях воркспейса: `git show cbb30df7f:$F` (редакция 20, `88ad95c6`, одобрена) — 0; `235d4f37f` (редакция 21, `c481e642`, без вердикта) — `GREATEST\|только вперёд` 0, хотя Д25 в Р10 внесена («наибольшее … откат назад невозможен»): предикат по слову предмета не видит (CX6-30), Е6 снимается предикатом M25 |
| M23 | шапки синтетических входов инъекционных проб `internal/repohygiene` называют состав пакетов консоли «настоящим» | `git grep -n -P 'настоящ\S* (состав дерева\|формы из этого дерева)' 1d42a6728bf -- internal/repohygiene` | 4: `console{formatterversion:37,lintproducer:36,stylelintconfig:31,typecheckproducer:34}_injection_test.go`; с пакетом `notify` число пакетов в них станет неверным (заказ пересверки `defdbe67`; §4) |
| M24 | запрос к префиксам края ограничен таймаутом раздачи; `notify` ложится в тот же location (З3) | `git show 1d42a6728bf:ui-future/deploy/templates/configmap-nginx.yaml \| grep -nE 'location\|timeout'` | `location ~ ^/(vpc\|compute\|storage\|geo\|nlb\|registry\|operations)/` — строка 132, `proxy_read_timeout 30s` и `proxy_send_timeout 30s` — строки 140–141 (в шаблоне строк `proxy_read_timeout` 15, из них `30s` — 13: `git show … \| grep -c 'proxy_read_timeout 30s'`). Предел хвоста цикла счётчика при зависшем апстриме — 30 s на запрос (З9, CX6-27) |
| M25 | Р10 приёмки NTF-3 несёт сценарий монотонности отметки по ID | `F=docs/specs/sub-phase-NTF-3-kacho-modules-notifications-acceptance.md; sed -n '/^\*\*Р10\./,/^\*\*Р11\./p' $F \| grep -c 'NTF3-161'` (воркспейс) | `235d4f37f` (редакция 21, `c481e642`) — 1; `git show cbb30df7f:$F` (редакция 20, `88ad95c6`) — 0: предикат различает обе стороны. Записи ревью на `c481e642` нет (`ls docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/ \| grep -c '^c481e642'` → 0) — Е6 открыта (§9) |
| M26 | охрана «одна мутация на действие» в дереве консоли — отрисованным `isPending` | `git grep -l useMutation 1d42a6728bf -- ui-future \| grep -v node_modules \| wc -l`; `git grep -n isPending 1d42a6728bf -- ui-future \| grep -v node_modules \| grep -v test \| grep -ciE 'disabled\|loading'` | 23 файла с `useMutation`; 11 строк охраны отрисованным `isPending`. В `@tanstack/query-core` 5.101.2 (версия по lock-файлам модулей) состояние мутации доходит до React через `notifyManager`, чей планировщик по умолчанию — `setTimeout(cb, 0)` (`notifyManager.ts`, `defaultScheduler = systemSetTimeoutZero`): отрисованный `isPending` отстаёт от `mutate()` на одну макрозадачу, а на `jest.useFakeTimers` не наступает вовсе, пока часы не сдвинуты (пересверка `7294a684`, CX6-28). Синхронной охраны в дереве нет — заводится З10 |

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
  `react-dom`, `react-router`); `@shared` — алиас на `../shared/src`; свой `QueryClient` —
  `useMemo` в `NotifyPage`, как у прочих (M5).
- Порт предпросмотра — `4183` (следующий за `storage` `4182`); `dev-federation.sh` выводит
  порт из `preview` пакета и правки не требует.
- **Направления графа бандлов** (инвариант И1): `host → shared`, `notify → shared`,
  `<модуль> → shared`, `host → notify` только через федерацию. `shared → <модуль>` — ноль
  (сегодня ноль, §1.8 приёмки). Держатель: `module-boundary-coverage.test.ts` (состав — обходом
  каталога) и предикат §1.8 приёмки (`git grep -lE "from ['\"]@(…|notify)[/'\"]" -- ui-future/shared/src` → 0).

### З2. Признак Р2 — одно чтение на окно, четыре состояния, исчерпывающее ветвление читателей

Механизм (`ui-future/shared/src/lib/console-config.ts`, единственный читатель
`notificationsEnabled` — DoD 6):

1. **Состояния.** `type ConsoleNotificationsState = "loading" | "enabled" | "disabled" | "unreadable"`.
   Три исхода Р2 — `enabled`, `disabled`, `unreadable`; `loading` — не исход, а «чтение ещё не
   завершилось» (CX6-21). Имя `unreadable` выбрано так, чтобы не совпасть со словом счётчика
   «непрочитанное» (`unread-count`, `unread-poll`, `unreadBadge`): в одном предмете одно слово —
   одно значение.
2. **Хранилище на окне.** Ключ — `Symbol.for("kacho.console-config")` (реестр глобальных
   символов общий для всех бандлов одного окна). Значение — объект
   `{ state: ConsoleNotificationsState, inFlight: Promise | null, listeners: Set }`.
   Первый бандл, вызвавший `loadConsoleConfig()`, создаёт объект в состоянии `loading` и
   начинает чтение; прочие получают **тот же** объект и тот же исход (CX6-16 (а)). Бандл своего
   состояния признака не держит. Форма объекта у всех бандлов одна, потому что все образы
   консоли выкатываются одной версией (`tasks.md` §3; M11 — один коммит на профиль).
3. **Чтение.** `fetch("/console-config.json", { cache: "no-store", credentials: "same-origin" })`
   — не клиентом края: путь отдаёт раздача, а не край, и перевод регистра клиента (M6) телу
   признака не нужен. Исход `enabled`/`disabled` — только если ответ `200`, тело разбирается как
   JSON и `typeof body.notificationsEnabled === "boolean"`; всё прочее (не `200`, не JSON, поля
   нет, поле не логическое, сетевой отказ) — `unreadable`. Запасного значения и чтения
   `import.meta.env` нет (И2).
   **Дедлайн чтения `CONFIG_DEADLINE_MS` (B1, З20).** Каждое чтение — первое и повторное — несёт свой
   `AbortController`; таймер `setTimeout(CONFIG_DEADLINE_MS)` окна (часы, которыми управляют пробы через
   `jest.useFakeTimers`) по истечении делает две вещи: `abort()` запроса и **сам** завершает
   чтение исходом `unreadable`, не дожидаясь, отзовётся ли `fetch` на отмену. Исход чтения —
   ответ, отказ или дедлайн — применяется **однократно и только если хранимое `inFlight` — это
   обещание этого чтения** (сравнение идентичности, как у `rememberLoad`, З14); применение
   снимает `inFlight` и таймер. Опоздавший ответ после дедлайна не находит себя в `inFlight` и
   отбрасывается. Первое чтение, не ответившее за `CONFIG_DEADLINE_MS`, переводит `loading → unreadable`, и
   дальше действует обычный выход п.4 (фокус, «Повторить»). `AbortSignal.timeout` не
   используется: его часы — внутренние часы окружения, а дедлайн обязан идти по тем же часам,
   что проба (часы проб — управляемые, З18).
   Условия к коду (CX6-26): исход дедлайна — только `unreadable`, никогда `enabled`/`disabled`;
   таймер ставится тем же синхронным вызовом, что кладёт `inFlight`, и снимается применением
   любого исхода; отказ `fetch`, вызванный `abort()` после дедлайна, находит `inFlight` не своим
   и ничего не применяет; величина читается одной константой `CONFIG_DEADLINE_MS` (§8) —
   литерала срока в `console-config.ts` вне неё нет (рецензент диффа).
4. **Выход из `unreadable`** (CX6-16 (б)). Только из `unreadable`, не из `enabled`/`disabled`:
   - повторное чтение по возврату окна в фокус (`visibilitychange` → `visible`) — не больше
     одного чтения в полёте, и в полёте оно не дольше `CONFIG_DEADLINE_MS` (п.3): фокус и «Повторить» во время
     чтения в полёте схлопываются в него, а после дедлайна начинают новое; на время
     повторного чтения состояние остаётся `unreadable` (в `loading` не возвращается — страница
     «Повторить» не мигает);
   - кнопка «Повторить» на названной странице «Не удалось прочитать конфигурацию консоли…» —
     то же чтение.
   Исход `enabled`/`disabled` на время жизни окна окончателен: смена флага — перекатка раздачи
   (аннотация `checksum/nginx`, замер разбора), и новый исход приходит с перезагрузкой. Держать
   окно в `enabled` после выключения флага безопасно: запросы уйдут на край и получат отказ,
   показанный отказом (Р2, NTF6-56).
5. **Подписка компонентов** — `useConsoleConfig()` на `useSyncExternalStore` поверх
   `listeners` объекта окна: смена состояния, сделанная любым бандлом, перерисовывает все.
   Отдельного события окна для признака нет — объект уже общий.
6. **Исчерпывающее ветвление читателей** (CX6-21). Каждый читатель признака ветвится
   `switch (state)` по четырём значениям с проверкой `never` в ветке по умолчанию
   (`assertNever(state)`) — сведение «не `enabled` и не `unreadable`» к ветке `disabled`
   невыразимо, а пятое значение не скомпилируется у читателя, который его не знает. Ветка
   `loading` у каждого читателя:

   | читатель | `loading` | `enabled` | `disabled` | `unreadable` |
   |---|---|---|---|---|
   | маршрут `/notifications/*` (`App.tsx`) | индикатор ожидания `Spin` с доступным именем; ни названной страницы, ни перевода на панель | обёртка модуля (З14) | названная страница «не подключены» | названная страница с «Повторить» |
   | кнопка рейла (`HostRail`) | кнопки нет | кнопка | кнопки нет | кнопка с признаком недоступности |
   | опрос счётчика (З9) | не запущен | запущен | не запущен | не запущен |
   | действие подписки на карточке (З10) | не рисуется, каталог не запрашивается | по каталогу | не рисуется | не рисуется |

   «Кнопки нет» на `loading` — не утверждение о флаге: кнопка отсутствует до исхода так же,
   как любое содержимое до загрузки, и ни одна названная страница не говорит «не подключены»,
   пока раздача этого не сказала. `loading` длится не дольше `CONFIG_DEADLINE_MS` (п.3).
7. **Шапка `ui-future/shared/src/lib/config.ts`** (M21) правится тем же изменением: утверждение
   «все runtime-параметры — env … читается отсюда» после З2 ложно. Шапка называет исключение —
   признак подключения уведомлений читается во время работы из ответа раздачи модулем
   `console-config.ts`, без умолчания, — **без литерала имени поля**: предикат DoD 6
   (`git grep -n 'notificationsEnabled' -- 'ui-future/*/src/*.ts*' ':!*test*'` → только
   `console-config.ts`) комментарий не отличает от кода. Заметка ревью `defdbe67` («`config.ts` в
   маршруте без основания в замысле») закрывается этим пунктом; место — полоса F1 (§4).

Инварианты: И2 «признак не имеет умолчания»; И3 «одно окно — один исход признака»; И12
«читатель признака ветвится исчерпывающе, `loading` не показывается ни одним исходом»; И18
(З20) «механизм с дедупликацией в полёте не остаётся в полёте дольше своего дедлайна».
Держатели — `console-config.test.ts` (ветки: четыре формы `unreadable`; два вызова загрузчика из
двух «бандлов» — один запрос и один исход; `unreadable` → фокус → `enabled`; `enabled` → фокус →
запроса нет; первое чтение не завершено — состояние `loading`; **«чтение не отвечает → по
истечении `CONFIG_DEADLINE_MS` состояние `unreadable`, фокус начинает новое чтение (запросов 2)»; «чтение не
отвечает, `fetch` на отмену не отзывается — по истечении `CONFIG_DEADLINE_MS` всё равно `unreadable`»; «ответ
`enabled` пришёл после дедлайна — состояние остаётся `unreadable`»** (B1)), ветка `App.test.tsx`
«признак в `loading` — нет названной страницы `disabled` и нет перевода на панель» (заказ
пересверки CX6-21), `tsc` пакетов хоста и `notify` (проверка `never`), NTF6-61 (а)–(в), NTF6-02.

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
  `{"notificationsEnabled":null}` — консоль читает `unreadable`, а не решает за установку;
  рендер зонтика без значения отвергнут NTF-1 (NTF1-N01), второй проверки консоль не заводит (Р2).
- Заголовки защиты уровня `server` в location с собственным `add_header` не наследуются —
  отсюда `include "ui.securityHeaders"` (CX6-15), держатель — З18.
- Перечень префиксов на край: `location ~ ^/(vpc|compute|storage|geo|nlb|registry|operations|notify)/`
  — **безусловно**, при любом значении флага (NTF6-47, третий «Тогда»): при `false` консоль
  запросов к `/notify/v1/*` не делает, а безусловный маршрут не даёт `index.html` с `200`.
  Префикс вносится в **этот существующий** location, а не отдельным: его `proxy_read_timeout 30s`
  — предел хвоста запросов цикла счётчика (M24, З9, CX6-27).
- `location ^~ /notify-remote/` (точка входа модуля) — **только** при флаге `true`: ссылка на
  апстрим `KACHO_UI_NOTIFY_UPSTREAM` без объекта модуля сделала бы конфигурацию раздачи
  неисполнимой.
- Блок `server` раздачи самого модуля `notify` (своя `ConfigMap` в том же шаблоне, как у `iam`
  и `system`) — по образцу: `= /healthz`, `= /index.html`, `~* /remoteEntry\.js$` с
  `Cache-Control "no-cache" always` (гейт `ui-chart-remote-entry-cache.test.ts` называет
  `notify`), статика; каждый location с `add_header` включает `ui.securityHeaders`.
  **Форма блока** (условие пересверки `defdbe67` по строке 31 §10): проба
  `ui-chart-remote-entry-cache.test.ts` делит `configmap-nginx.yaml` по строкам, равным ровно
  `---`, и берёт имя блока первым совпадением `name: (.+)-nginx`. Поэтому блок `notify`
  начинается отдельной строкой `---` без ведущих пробелов и без директивы шаблона на той же
  строке (условие флага `{{- if … }}` — строкой **после** `---`, закрытие `{{- end }}` — до
  следующего `---`), и первое `name:` куска — `{{ include "ui.notifyName" . }}-nginx`. Иначе блок
  сольётся с соседним, и проба будет судить не тот блок.

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
  элемента, которые выводятся).
- **Отказ формы — свой класс ошибки, без HTTP-статуса** (CX6-22). Несовпадение формы бросает
  `ResponseShapeError` (`ui-future/shared/src/api/response-shape.ts`, новый): `name =
  "ResponseShapeError"`, поля `path` (путь запроса) и `field` (первое несовпавшее поле), своего
  `status` **нет**. Это не `ApiError`: ответ пришёл с `200`, и кодировать отказ статусом успеха
  значило бы дать любому читателю, ветвящемуся по `err.status` (успех — `< 400`), принять отказ
  за успех. Распознавание — `isResponseShapeError(err)` по `name` и полям, а не `instanceof`:
  класс компилируется в каждый бандл своей копией.
  - `presentError` получает ветку `isResponseShapeError(err)` **до** ветки `ApiError`:
    `status = "500"` (неисправен производитель ответа, а не вызывающий), текст — отказ данных
    (заголовок и пояснение словаря, не общее «error»), `devDetail = "RESPONSE_SHAPE · <path> ·
    <field>"`. Экраны не различают «не `200`» и «`200` не той формы»: оба выводятся
    `presentError(err)` в одно состояние «отвергнуто» (И4).
  - **Повтора нет.** У каждого запроса `notify` — в том числе у запросов карточки, исполняемых
    чужим `QueryClient` с `retry: 1` (M16), — опция запроса `retry: notifyQueryRetry`,
    где `notifyQueryRetry(failureCount, err) = !isResponseShapeError(err) && failureCount < 1`
    (одно место, `notify.ts`): ответ той же сборки края повтором не исправится, а прочие отказы
    повторяются так же, как у соседей.
  - **Клиент запросов модуля `notify` несёт это умолчанием** (CX6-22, условие пересверки
    `deeea79a`). `ResponseShapeError` производит не только `notify.ts`, но и обход
    `listAllAccountUsers` (З13), чей запрос исполняет клиент запросов страницы `NotifyPage`.
    Поэтому клиент модуля создаёт одна функция `createNotifyQueryClient()`
    (`ui-future/notify/src/lib/queryClient.ts`) с `defaultOptions.queries.retry =
    notifyQueryRetry`; её зовут `NotifyPage` и экранные пробы модуля. Любой запрос модуля —
    `notify` или обход службы доступа — наследует «без повтора на отказ формы»; явная опция
    запроса остаётся только у запросов карточки, исполняемых чужим клиентом (M16). Своего
    `new QueryClient` в `ui-future/notify/src` вне этой функции нет.
- **Обход страниц** (CX6-08 (а)): `listAllSubscriptions()` — `pageSize = 1000` (граница ручки
  NTF-3), цикл до пустого `next_page_token`; повтор уже виденного токена — `ResponseShapeError`
  с `field = "next_page_token"` (обход не зацикливается на неисправном ответе).
- **Константы контракта** — здесь и больше нигде (Р20, DoD 6): `RESOURCE_CHANGE`, `EMAIL`,
  `CONSOLE`, `ALWAYS`, `SWITCHABLE`, `NOTIFY_SEEN_EVENT`, `NOTIFY_SUBSCRIPTIONS_EVENT` (З10).
- **Операции** — З8.

Инвариант И13: «отказ формы ответа не несёт статуса успеха и не повторяется». Держатели —
`notify.test.ts` (по каждой функции чтения и мутации: `200` не той формы → `ResponseShapeError`,
у ошибки нет `status`; `notifyQueryRetry` → `false` на `ResponseShapeError`, `true` на первом
`ApiError` `503`) и ветка `error-presentation.test.ts` «`ResponseShapeError` → `status = "500"`,
текст отказа данных, не общее `"error"`» (заказ пересверки CX6-22); `queryClient.test.ts`
модуля — «умолчание `retry` клиента — `notifyQueryRetry`»; `NotificationContactsPage.test.tsx`
— «`200` не той формы у обхода пользователей — один запрос, без повтора» (условие пересверки
`deeea79a`).

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
  отвергнуто (`ApiError` либо `ResponseShapeError`).

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

### З9. Опрос счётчика — поколение на обеих ветках, схлопывание, сброс по отметке; отмены нет

`ui-future/host/src/lib/unread-poll.ts` (CX6-05, CX6-23):

- Цикл = пара `listInbox({pageSize: 100})` + `getPreferences()` параллельно; номер поколения
  `gen` увеличивается на старте цикла, цикл запоминает свой номер.
- **Отбрасывание устаревшего — только сравнением поколения, на ветке успеха И на ветке
  отказа** (CX6-23, выбор (а)). Исход цикла — успех пары либо отказ любого из двух чтений —
  применяется к значку, только если номер цикла равен текущему `gen`; иначе исход отбрасывается
  целиком, в том числе отказ: отказ устаревшего цикла значок в `"!"` не переводит.
- **Отмены запроса нет.** `AbortController` не заводится: общий клиент края сигнала не
  принимает (M15), а правка `shared/src/api/client.ts` задела бы всех его потребителей ради
  экономии одного ответа, который всё равно отбрасывается поколением. Устаревший запрос
  дорабатывает до конца; его ответ не применяется.
- **Дедлайн цикла `POLL_DEADLINE_MS`** (B1, З20). На старте цикл ставит таймер `setTimeout(POLL_DEADLINE_MS)` окна (часы
  управляемые, как у пробы). Исход цикла — **первое** из двух: исход пары чтений либо
  истечение `POLL_DEADLINE_MS`; второе, пришедшее позже, отбрасывается (у цикла флаг «исход применён»,
  однократно). Истечение `POLL_DEADLINE_MS` — исход «отказ»: значок `"!"`, если номер цикла равен текущему
  `gen`, иначе отброшен, как любой исход устаревшего цикла. Запрос при этом не отменяется
  (отмены нет, см. выше): он дорабатывает до конца, его ответ не находит цикла без исхода и
  отбрасывается. Флаг «исход применён» — поле **объекта цикла**, а не общий флаг механизма
  (CX6-27 (б)): исход одного цикла не закрывает другой.
- **Что даёт `POLL_DEADLINE_MS` меньше периода таймера** (§8, CX6-27). Цикл, начатый **таймером**,
  получает исход до следующего таймера. Цикл, начатый фокусом или `NOTIFY_SEEN_EVENT`, может
  быть без исхода в момент таймера, если начат меньше чем за `POLL_DEADLINE_MS` до него; тогда
  таймер схлопывается в этот цикл (правило схлопывания ниже), и значок получает исход не позже
  дедлайна этого цикла. Утверждения «каждый таймер находит прежний цикл завершённым» замысел не
  делает: оно ложно для цикла, начатого не таймером.
- Триггеры: таймер 60 с по часам вкладки, возврат в фокус, событие `NOTIFY_SEEN_EVENT`.
  Таймер и фокус при **текущем** цикле без исхода **схлопываются** (новый цикл не
  начинается); цикл, получивший исход ответом или дедлайном, не схлопывает ничего.
  `NOTIFY_SEEN_EVENT` начинает новый цикл немедленно (`gen++`), и прежний цикл становится
  устаревшим (инвариант И14 «к значку применяется исход только последнего начатого цикла, и
  не более одного раза»).
- **Граница устаревших циклов** (I3). Текущий цикл — ровно один. Устаревший цикл возникает
  только из `NOTIFY_SEEN_EVENT`, то есть из успешной отметки; отметка — действие, недоступное,
  пока её мутация в полёте (З13, И19), поэтому их не больше одной на время ответа `PATCH`.
  Устаревших циклов без исхода — не больше числа отметок за последние `POLL_DEADLINE_MS`, и каждый получает
  исход (отброшенный) не позже своего `POLL_DEADLINE_MS`. Их HTTP-запросы после этого — хвост
  без получателя: ответ не применяется ни к значку, ни к состоянию механизма, и ни один триггер
  в него не схлопывается.
  **Предел хвоста** (CX6-27 (а)). Запрос к `/notify/v1/*` проходит раздачу хоста в том же
  location префиксов края, что `vpc`…`operations` (З3), а у него `proxy_read_timeout 30s` (M24):
  при зависшем апстриме раздача закрывает запрос не позже 30 s. Хвост поэтому ограничен
  запросами циклов, начатых за последние 30 s, — при периоде 60 s это пара текущего цикла плюс
  пары отметок и фокусов этого окна. Условие к полосе E1: префикс `notify` вносится в
  **существующий** location, а не отдельным location — отдельный без таймаута снял бы предел
  (гейта, требующего таймаут у location префикса `notify`, в дереве нет; держит рецензент диффа
  чарта). Обрыв между браузером и раздачей таймаутом прокси не ограничен — это свойство сети
  окна, все запросы окна висят одинаково, и значок при этом держит `"!"` по дедлайну.
  **Как это читается против приёмки** (строки 676–680: «в полёте не больше одного цикла» и
  «делает начатые циклы устаревшими и начинает новый»): «в полёте» приёмки — цикл, чей исход
  ещё может быть применён к значку. Такой цикл всегда один — текущий: устаревший перестаёт
  быть «в полёте» в этом смысле в момент `gen++`, его исход решён заранее — отброшен. Обе
  фразы приёмки выполняются одновременно; поведения приёмки замысел не меняет.
- Слушатели (`visibilitychange`, `NOTIFY_SEEN_EVENT`) и таймер регистрируются хуком
  `useUnreadPoll()` в эффекте с отпиской и остановкой таймера при размонтировании рейла или при
  выходе признака из `enabled` — та же форма, что З10.
- Опрос существует только в состоянии `enabled` (З2 п.6); в `loading`, `disabled`,
  `unreadable` — ни таймера, ни запросов (NTF6-02, NTF6-61).

Держатель: `unread-poll.test.ts` с управляемыми ответами и часами — «опоздавший ответ
прежнего цикла не меняет значок», «**отказ** устаревшего цикла не меняет значок» (заказ
пересверки CX6-23), «отметка во время цикла: результат цикла отброшен, новый цикл начат»,
«таймер и фокус при цикле в полёте — одно обращение», «признак `disabled` — таймера нет»,
«размонтирование — слушателей и таймера нет» (в том числе таймеров дедлайна);
**«цикл не отвечает → по истечении `POLL_DEADLINE_MS` значок `"!"`; следующий таймер начинает цикл
(обращений к ленте 2); опоздавший ответ первого цикла значок не меняет»; «отметка во время
цикла, затем устаревший цикл не отвечает — его дедлайн значок не меняет»** (B1, I3).

### З10. Действие подписки на карточке — часть общей карточки; кэш каталога и подписок в провайдере страницы

В `ui-future/shared/src/components/organisms/ResourceDetailExtensions` (Р10, CX6-03):

- `SubscribeAction` составляется карточкой **рядом** с `headerActions` расширения спеки, а не
  записью `registerDetailExtension`: расширение спеки не заменяется (держатель —
  `ResourceDetailExtensions.test.tsx`, ветка `networks`).
- Видимость — состояние `enabled` (З2 п.6), `notifyModuleOf(specId) != null` (З11) и в каталоге
  у этого модуля ячейка `(RESOURCE_CHANGE, EMAIL)` с `SWITCHABLE`. В прочих состояниях каталог
  не запрашивается.
- **Кэш** (CX6-19): ключи react-query `["notify", "catalog"]` (`staleTime: Infinity` —
  каталог меняет только установка, а её смена приходит перезагрузкой) и
  `["notify", "subscriptions"]` (`staleTime: Infinity`, значение — результат
  `listAllSubscriptions()`), оба с `retry: notifyQueryRetry` (З6). Кэш принадлежит
  `QueryClient` **страницы** (M5): вторая карточка той же смонтированной страницы запросов не
  делает; повторно смонтированная страница начинает с пустого кэша и читает заново.
- **Сброс кэша подписок** — событием окна `NOTIFY_SUBSCRIPTIONS_EVENT` (CX6-20):
  - **Слушатель — хук, а не побочное действие загрузки модуля.**
    `useNotifySubscriptionsSync()` (`ui-future/shared/src/hooks/useNotifySubscriptionsSync.ts`,
    новый): берёт `useQueryClient()` провайдера, в котором вызван, и в `useEffect` регистрирует
    `window.addEventListener(NOTIFY_SUBSCRIPTIONS_EVENT, h)`, где `h` инвалидирует
    `["notify", "subscriptions"]` **этого** клиента; функция очистки эффекта снимает слушателя.
    Зависимость эффекта — клиент: новый клиент после повторного монтирования страницы получает
    нового слушателя, прежний снят вместе с прежним клиентом. Хук зовут `SubscribeAction` и
    корень `NotifyPage` (внутри своего `QueryClientProvider`). Слушателя уровня модуля,
    привязанного к клиенту, которого уже нет, не существует.
  - **Событие несёт только имя** — `new Event(NOTIFY_SUBSCRIPTIONS_EVENT)`, без данных:
    получатель перечитывает список сам, чужой полезной нагрузке не доверяет.
  - **Отправитель инвалидирует свой ключ тем же путём**: после любой успешной или отвергнутой
    мутации подписки (карточка, экран настроек) — только `window.dispatchEvent(...)`; свой
    слушатель в том же окне срабатывает так же, как чужой, отдельной локальной инвалидации нет.
  - Без события карточка бандла `vpc` после отписки на экране настроек (бандл `notify`) показала
    бы «Вы подписаны» из своего кэша (NTF6-36, четвёртый «Тогда»). Это другой предмет, чем
    `NOTIFY_SEEN_EVENT` (отметка «просмотрено»), поэтому канал свой; оба имени — константы
    `notify.ts`.
- «Вы подписаны» — только из полного списка (CX6-08 (а)); после **любого** отказа создания
  список перечитывается, локального флага «подписан» нет (CX6-08 (б), NTF6-59).
- **Одна мутация на действие** (I2, И19). Пока мутация подписки в полёте, действие
  «Подписаться» недоступно: второе нажатие запроса не делает.
  **Охрана синхронная, а не отрисованная** (CX6-28). Отрисованный `isPending` `useMutation`
  отстаёт от `mutate()` на одну макрозадачу (M26): два нажатия в одном синхронном блоке оба
  видят `false`, а на управляемых часах проб `isPending` не наступает вовсе, и проба не отличила
  бы исправную охрану от неисправной. Поэтому каждое мутирующее действие модуля и карточки идёт
  через один хук `useGuardedMutation(options)` (`ui-future/shared/src/hooks/useGuardedMutation.ts`,
  новый): он держит флаг в `useRef`, поднимает его **синхронно до** вызова `mutateAsync` и
  опускает по исходу **этого** вызова (`finally`); нажатие при поднятом флаге запроса не делает
  и ничего не показывает. Отказ `mutateAsync` хук не глотает: он доходит до `onError` действия,
  как у `useMutation`. Возвращаемый `isPending` — только вид кнопки (состояние ожидания), решения
  по нему не принимаются. Второй охраны под другим именем нет — И7, рецензент диффа. Без этого второе нажатие дошло бы до базы NTF-3, получило бы
  `ALREADY_EXISTS` (NTF3-91) и показало бы текст отказа рядом с «Вы подписаны» из
  перечитанного списка. Дедлайна у мутации нет, и это решение, а не пропуск (З20): исход
  мутации по истечении срока клиенту неизвестен, и объявить его отказом значило бы солгать о
  том, что сервер мог закоммитить (И6); состояние ожидания принадлежит экземпляру хука
  смонтированной карточки, и уход со страницы с возвратом даёт новый экземпляр (M5) — выход не
  идёт через зависшую мутацию.

Инвариант И15: «слушатель события окна живёт ровно столько, сколько клиент кэша, который он
инвалидирует». Держатели: `ResourceDetailExtensions.test.tsx` — «две карточки подряд —
каталог и список по одному запросу», «цель на второй странице списка — «Вы подписаны»»,
«отказ `503` — список перечитан, «Вы подписаны» нет», «событие `NOTIFY_SUBSCRIPTIONS_EVENT` —
список перечитан», «страница размонтирована и смонтирована заново → событие перечитывает
список» (заказ пересверки CX6-20), «два нажатия «Подписаться» в одном синхронном блоке без
сдвига часов — один `POST`; близнец — нажатие после исхода первой мутации — `POST` второй»
(I2, И19, CX6-28); `useGuardedMutation.test.tsx` — «два вызова в одном синхронном блоке без
сдвига часов — вызовов `mutationFn` 1; близнец — вызов после исхода — 2; отказ первой мутации
опускает флаг — следующий вызов уходит» (CX6-28); `useNotifySubscriptionsSync.test.tsx` — «после
размонтирования слушателей `NOTIFY_SUBSCRIPTIONS_EVENT` на окне 0» (подсчёт через
`addEventListener`/`removeEventListener`).

### З11. Переход «спека → модуль каталога» и «тип → спека» — в `subjects.ts`

`ui-future/shared/src/lib/subscription/subjects.ts` (Р10а, CX6-01):

- `NOTIFY_SOURCE_BY_OWNER: Readonly<Record<JournalOwner, string>>` — значения Р10а;
  `notifyModuleOf(specId)` — единственный читатель.
- `specOfKind(kind): string | null` — обратный поиск по `STREAM_SUBJECTS[spec].kind`, одно место
  для строки ленты (Р7) и строки подписки (Р10); второго словаря типов нет (DoD 6).
  Однозначность обратного поиска держит существующая проба `subjects.test.ts:144`
  (`kinds.length = new Set(kinds).size`), подтверждено пересверкой.
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
  после успеха — `NOTIFY_SEEN_EVENT`, перечитывание настроек (Р19) **и перечитывание
  загруженных страниц ленты** (I1).
  - **Отметка из давно открытого окна** (I1). `items[0]` берётся со страницы, загруженной
    раньше; второе окно или устройство могло с тех пор отметить позицию новее. Консоль позиции
    сравнивает только на равенство (Р18) и защититься сама не может. Замысел опирается на
    решение диспетчера **Д25**: у владельца отметка монотонна — сервер пишет
    `GREATEST(старое, новое)` атомарно, откат назад невозможен; запись в приёмке NTF-3 —
    зависимость Е6 (M22: сегодня в Р10 её нет). При Д25 устаревшая отметка сервером не
    применяется, а ответ `done = true` для консоли — тот же успех. Поэтому после успеха
    консоль берёт действующую позицию только из перечитанных настроек и ищет её в
    **перечитанной** ленте: без перечитывания ленты позиция новее верхней загруженной строки
    не нашлась бы на загруженных страницах, и Р18 пометило бы «новым» всё загруженное сразу
    после «Отметить всё просмотренным». Перечитывание — сброс ключа ленты в клиенте запросов
    страницы; новых запросов, кроме повторения уже загруженных страниц, нет.
  - **Пометки — только из согласованной пары** (CX6-29, И20). Настройки и лента — два
    независимых чтения; если после отметки настройки ответят раньше ленты, пара «новые
    настройки + прежняя лента» в сценарии I1 даёт «позиция не найдена, токен есть», и Р18 на
    мгновение помечает новым всё загруженное. Поэтому пометки вычисляются не из текущих данных
    двух запросов, а из **снимка пары** `{ seenUpTo, pages }`, который центр кладёт одним
    обновлением состояния только когда оба чтения **одной** пары завершились успехом:
    (1) первое чтение экрана; (2) после успешной отметки — пара перечитываний, обе начатые после
    успеха (`refetchQueries` обоих ключей с `cancelRefetch: true` — чтение, начатое до успеха,
    отменяется и в пару не входит), снимок — после `Promise.all` обоих; (3) «Показать ещё»
    дописывает страницу к снимку при прежнем `seenUpTo` (настройки при этом не читаются).
    Промежуточная пара снимка не меняет — пометки остаются прежними до прихода обоих ответов.
    Самостоятельного перечитывания одного ключа центра нет: у обоих ключей
    `refetchOnWindowFocus: false`, иначе возврат в фокус перечитал бы одно из двух и дал ту же
    несогласованную пару. Отказ любого из двух перечитываний — экран в «отвергнуто» (И4), снимок
    не обновляется.
  - **Одна мутация на действие** (И19): кнопка отметки недоступна, пока её `PATCH` в полёте;
    охрана — `useGuardedMutation` (З10, CX6-28).
- **Настройки:** матрица из каталога (Р5, Р6); запрос `:setEntries` — **разница «загружено →
  выбрано» по `SWITCHABLE`-ячейкам каталога** (CX6-12), пустая разница — запроса нет; период
  сводки — `patchDigestPeriod`; параметр `module` — выделение группы; «Мои подписки» —
  `listAllSubscriptions()` (кэш З10, хук `useNotifySubscriptionsSync` в корне страницы),
  снятие — `deleteSubscription` + событие. Сохранение матрицы, период сводки и снятие подписки
  недоступны, пока мутация своего действия в полёте (И19; охрана — `useGuardedMutation`, З10).
- **Контакты:** аккаунт — из выбора хоста. Кандидаты — полный обход пользователей **этого
  аккаунта** (CX6-08 (а), CX6-24): новая функция `listAllAccountUsers(accountId)` в
  `shared/src/api/iam.ts` (обхода там нет, M18) — `GET /iam/v1/users?accountId=<id>&pageSize=1000`,
  цикл до пустого `next_page_token`, повтор токена — отказ. `accountId` — **обязательный
  отдельный аргумент**, а не элемент `q`, как у соседней `listAccountMemberships`: пустой
  фильтр у владельца означает «все видимые вызывающему», а не «члены аккаунта» (M17), поэтому
  пустая строка отвергается функцией до запроса (`Error("listAllAccountUsers: accountId
  required")`), а экран без выбранного аккаунта обхода не начинает. Сервисных аккаунтов и групп
  в выборе нет по построению — источник только пользователи. Запрос кандидатов исполняет клиент
  `createNotifyQueryClient()` (З6): отказ формы обхода (`ResponseShapeError`, в том числе повтор
  токена) не повторяется (И13). Сохранение контакта недоступно, пока его мутация в полёте (И19;
охрана — `useGuardedMutation`, З10).

Держатели: `NotificationSettingsPage.test.tsx` — «каталог не `200`», «каталог `200` не той
формы», «настройки не `200`» → текст отказа, матрицы нет (CX6-11); «ничего не изменено —
`:setEntries` не уходит»; «изменена одна ячейка — ровно одна запись» (CX6-12); «два нажатия
сохранения, периода, снятия подписки в одном синхронном блоке без сдвига часов — по одному
запросу; близнец — нажатие после исхода — запрос второй» (И19, CX6-28).
`NotificationCenterPage.test.tsx` — «лента `200` не той формы → отказ, не «Уведомлений пока
нет»» (CX6-06 (б)), «вторая страница после найденного `seenUpTo` — без пометок» (CX6-17);
«два нажатия отметки в одном синхронном блоке без сдвига часов — один `PATCH`; близнец — после
исхода — второй» (И19, CX6-28); «отметка успешна, а перечитанные настройки несут позицию новее
верхней загруженной строки (сервер оставил более новую, Д25) — лента перечитана, позиция
найдена в перечитанной ленте, «новые» — только строки выше неё, а не всё загруженное» (I1);
**порядок ответов пары** (CX6-29, И20): «после отметки настройки отвечают раньше ленты
(управляемые ответы) — ни в один момент между ответами не помечено новым всё загруженное,
пометки меняются одним переходом после ответа ленты»; близнец — «лента отвечает раньше
настроек» — тот же итог; «чтение, начатое до успеха отметки и ответившее после него, в снимок не
входит».
`NotificationContactsPage.test.tsx` — «контакты `200` без `security` → отказ»,
«кандидат на второй странице пользователей виден» (CX6-08), «каждый запрос кандидатов несёт
`accountId` выбранного аккаунта, вторая страница — тоже» (заказ пересверки CX6-24),
«`200` не той формы у обхода пользователей — один запрос, без повтора» (CX6-22); «два нажатия
сохранения контакта в одном синхронном блоке без сдвига часов — один `PATCH`; близнец — после
исхода — второй» (И19, CX6-28);
`iam.test.ts` (или проба рядом с `iam.ts`) — «`listAllAccountUsers("")` — отказ, запросов 0».

### З14. Вход в рейле, маршрут, обёртка модуля, названные страницы

- `host/src/remotes/moduleCatalog.ts` — запись `{ remote: "notify", label: SERVICES.notify.menuTitle }`
  без `section`; комментарий строк 20-21 называет троих без раздела (§3 приёмки).
- **Обёртка модуля — общей фабрикой** (CX6-10, M14). `host/src/remotes/NotifyRemote.tsx`
  (новый):

  ```ts
  export const loadNotifyPage = rememberLoad(() => import("notify/NotifyPage"));
  export const NotifyRemote = makeRemote(
    loadNotifyPage,
    (mod) => (mod.default ?? mod.NotifyPage) as ComponentType<RemotePageProps> | undefined,
    moduleLabelOf("notify"),
  );
  ```

  Литерал `import("notify/NotifyPage")` стоит в файле обёртки (требование плагина федерации и
  гейта `remote-boundary-coverage.test.ts`); граница отказа, повтор и имя раздела — те же, что
  у восьми соседей. Собственной связки `lazy` + `ModuleErrorBoundary` в `App.tsx` нет.
- **Одна загрузка — один исход для маршрута и кнопки** (CX6-25). `rememberLoad(loader)`
  (`host/src/remotes/rememberLoad.ts`, новый) хранит обещание загрузки и публикует его исход
  подписчикам: исполненное обещание хранится до конца жизни окна; **отклонённое снимается с
  хранения в момент отказа**, иначе повтор `makeRemote` (свежий `lazy` на каждую попытку)
  попал бы в тот же отказ немедленно — ровно то, от чего фабрика защищается номером попытки.

  ```ts
  export type LoadOutcome = "pending" | "available" | "unavailable";
  // load(): вернуть хранимое; иначе p = loader(), stored = p, publish("pending"),
  // и тем же синхронным вызовом повесить обработчики исхода p:
  //   успех → if (stored === p) publish("available")
  //   отказ → if (stored === p) { stored = null; publish("unavailable"); }
  ```

  - **Снятие и публикация — по идентичности.** Обработчик исхода обещания `p` снимает
    хранимое и публикует исход, **только если хранимое — это `p`**; безусловного
    `stored = null` нет. Исход подписчику публикует только текущее хранимое обещание, поэтому
    исход прежней загрузки не снимает новую и не перекрывает её исход.
  - **Состояний подписчика три, и все названы:** `pending` (загрузка в полёте — от вызова
    `loader()` до исхода), `available`, `unavailable`. Хук подписки
    `useLoadOutcome(load)` при монтировании зовёт `load()` (предзагрузка), поэтому состояния
    «ещё не звали» у подписчика нет; повтор после отказа переводит `unavailable → pending`,
    успех повтора — в `available`.
  - **Поздний подписчик получает текущий исход снимком** (условие пересверки `defdbe67` по
    CX6-25). `rememberLoad` хранит не только обещание, но и **последний опубликованный исход**;
    `useLoadOutcome` читает его через `useSyncExternalStore` (снимок — хранимый исход,
    подписка — публикации). Подписчик, пришедший после исхода (хранимое обещание уже исполнено,
    `load()` возвращает его и ничего не публикует), сразу видит `available`, а не ждёт
    публикации, которой не будет. Без этого `pending` у позднего подписчика был бы вечным и
    переставал бы значить «загрузка в полёте», как его определяет этот пункт.
  - **Дедлайна у загрузки нет, и это решение** (З20). Состояние `pending` не закрывает ни одного
    пути: кнопка в `pending` обычная и ведёт в маршрут, а маршрут показывает загрузку обёртки
    `makeRemote`, у которой предела нет ни для одного из восьми модулей (M19). Дедлайн
    опубликовал бы `unavailable` для загрузки, которая ещё может завершиться, и кнопка
    объявила бы модуль недоступным без отказа. Зависание загрузки удалённого модуля —
    свойство общей фабрики для всех девяти, этим изменением не вводится и не меняется (§12).
  - **Кнопка рейла ветвится по трём состояниям исчерпывающе** (`switch` с проверкой `never`,
    как у признака Р2, И12) и только в состоянии признака `enabled`: `pending` и `available` —
    обычная кнопка без признака недоступности (переход ведёт в маршрут, где загрузку и отказ
    показывает сама обёртка `makeRemote`; отказ до исхода кнопкой не предсказывается);
    `unavailable` — кнопка с признаком недоступности и `UNAVAILABLE_REASON`, как у соседей.
    Отдельного загрузчика у кнопки нет.
  - **Предел держателя названо.** Пока `load()` возвращает хранимое обещание и обработчики
    вешаются тем же синхронным вызовом, что кладёт `p`, обработчик прежнего обещания не может
    сработать после того, как положено новое: снятие происходит только в самом обработчике
    отказа, а новое кладётся лишь после снятия. Ветка «исход прежнего обещания при хранимом
    новом» поэтому пробой через публичный `load()` не достигается; условие `stored === p`
    держит инвариант независимо от порядка обработчиков и от будущего пути замены хранимого.
    Проба держит достижимое — счёт вызовов загрузчика и последовательность состояний; проверка
    идентичности в обоих обработчиках — пункт чек-листа рецензента диффа (`ui-reviewer`).
- `host/src/remotes/notify.d.ts` (новый) объявляет модуль `notify/NotifyPage` той же формы, что
  `nlb.d.ts`; модуля `notify/navigation` не объявляет — навигации нет.
- `host/src/remotes/index.ts` — `export * from "./NotifyRemote"`.
- `host/src/lib/module-navigation.tsx` **не правится**: `REMOTE_NAV_LOADERS` и `NAV_REMOTES`
  перечисляют модули с навигацией, у `notify` её нет; загрузчик страницы живёт в обёртке.
- `HostRail` — кнопка «Уведомления» в `rail-bottom` над «Администрированием» по таблице З2 п.6:
  `enabled` — кнопка (при исходе загрузки `unavailable` — с признаком недоступности и
  `UNAVAILABLE_REASON`, как у соседей); `unreadable` — с признаком недоступности и подсказкой
  «Конфигурация консоли не прочитана»; `loading`, `disabled` — кнопки нет. Значок и доступное
  имя — `unreadBadge` (З7) из `unread-poll`.
- `host/src/App.tsx` — `/notifications/*` по таблице З2 п.6: `enabled` → `<NotifyRemote
  context={context} />`; `disabled` → названная страница «Уведомления в этой установке не
  подключены»; `unreadable` → названная страница с кнопкой «Повторить» (З2 п.4); `loading` →
  `Spin` с доступным именем. Перевод на панель (`path="*"`) для этих адресов не срабатывает ни
  в одном состоянии.
- `SERVICES.notify = { title: "Уведомления", menuTitle: "Уведомления" }` — в каноне
  `shared/src/lib/entity-names.ts`, затем в зеркале хоста `host/src/lib/entity-names.ts`
  (порядок правки задан шапкой зеркала; держатель — `HostBreadcrumb.names.test.ts`).

Держатели: `remote-boundary-coverage.test.ts` (существующий; с `notify` в федерации, обёртке и
каталоге — зелёный, печать «federation=9, обёрток=9, имён в каталоге=9»); `rememberLoad.test.ts`
(управляемый загрузчик: тест сам решает, когда исполнить или отклонить каждое обещание) —
«два вызова — одна загрузка», «отказ → повтор грузит заново», «успех после отказа — подписчик
получает `available`», «последовательность состояний подписчика `pending → unavailable → pending
→ available`, вызовов загрузчика ровно 2, после успеха хранимое не снимается» (CX6-25),
«подписка после успеха — состояние `available` сразу, вызовов загрузчика 1» (условие пересверки
`defdbe67`);
`App.test.tsx` — ветки NTF6-02 и `loading` (З2); `HostRail.test.tsx` — кнопка в `pending` без
признака недоступности, в `unavailable` — с ним (CX6-25).

### З15. Пояснение отказа в правах (Р17)

Меняется только значение `FORBIDDEN_EXPLANATION` в `shared/src/lib/error-presentation.ts`;
словарь `REFUSALS` и запасной разбор `403` читают ту же константу, поэтому новый текст
действует на всех экранах с `403` (CX6-13). Своего пояснения модуль `notify` не заводит.
Держатель — DoD 12 (проба словаря утверждает новый текст; `git grep -c 'администраторам платформы' -- ui-future` → 0).
Тот же файл получает ветку `ResponseShapeError` (З6) — это другой предмет, пояснение `403` она
не трогает.

### З16. Данные ответа — только текстом

В файлах обхода DoD 11 (`ui-future/notify/src/**` и файлы `shared`, импортирующие
`@shared/api/notify`) `dangerouslySetInnerHTML` — ноль; `initiator` дословно (Р8). Обход
для DoD 6 (литералы) и DoD 11 (вывод HTML) — **одна функция переписи**
`ui-future/notify/src/test/notify-surface-census.ts`, два гейта её зовут; второго обхода нет.

### З17. Фикстуры G1

`ui-future/e2e/specs/fixtures.ts` получает `inviteIntoAccount`, `ownUserId`, `onlyAccount`
(Р14, DoD 14); `users.spec.ts` их импортирует, `secondAccountMembership` остаётся в нём и
зовёт `inviteIntoAccount`. Вызов `users:invite` в дереве проб — один.

### З18. Держатели, заказанные разбором и пересверкой, и где они живут

| пункт | проба | файл |
|---|---|---|
| CX6-05 | опоздавший ответ; отметка во время цикла; схлопывание | `ui-future/host/src/lib/unread-poll.test.ts` |
| CX6-06 (б) | `200` не той формы → отказ, по каждой функции чтения и мутации | `ui-future/shared/src/api/notify.test.ts`; экранные ветки — З13 |
| CX6-08 | цель на второй странице; отказ создания → перечитывание; кандидат на второй странице | `ResourceDetailExtensions.test.tsx`, `NotificationContactsPage.test.tsx` |
| CX6-09 | ноль `GET /operations` при `done = true` | `ui-future/shared/src/api/notify.test.ts` |
| CX6-10 | обёртка `notify` строится фабрикой; три перечня сходятся; шесть тестовых перечней M2 называют `notify` | `ui-future/host/src/remotes/remote-boundary-coverage.test.ts` (существующий), `rememberLoad.test.ts`; перечни §10 строки 21, 22, 28–31 — каждая проба зелёная с `notify` в переписи |
| CX6-11 | экран настроек при отказе каталога/настроек | `NotificationSettingsPage.test.tsx` |
| CX6-15 | каждый location с `add_header` в отрендеренной раздаче хоста и модулей несёт набор заголовков защиты уровня `server` | `ui-future/deploy/console_location_security_headers_test.go` (обход блоков `location` рендера; печать числа; пустой обход — красный; инъекция location без include — красный) |
| CX6-16 | два вызова загрузчика — один запрос; выход из `unreadable` | `ui-future/shared/src/lib/console-config.test.ts` |
| CX6-17 | пометки за первой страницей | `unread-count.test.ts`, `NotificationCenterPage.test.tsx` |
| CX6-19 | две карточки подряд — каталог и список по одному разу | `ResourceDetailExtensions.test.tsx` |
| CX6-20 | страница смонтирована заново → событие перечитывает список; после размонтирования слушателей 0 | `ResourceDetailExtensions.test.tsx`, `ui-future/shared/src/hooks/useNotifySubscriptionsSync.test.tsx` |
| CX6-21 | признак в `loading` → ни названной страницы `disabled`, ни перевода на панель; исчерпывающее ветвление | `ui-future/host/src/App.test.tsx`; `tsc` хоста и `notify` |
| CX6-22 | `ResponseShapeError` → текст отказа данных, не общее `"error"`; без повтора; без `status`; обход пользователей на экране контактов — без повтора | `ui-future/shared/src/lib/error-presentation.test.ts`, `notify.test.ts`, `ui-future/notify/src/lib/queryClient.test.ts`, `NotificationContactsPage.test.tsx` |
| CX6-23 | отказ устаревшего цикла не меняет значок | `ui-future/host/src/lib/unread-poll.test.ts` |
| CX6-24 | запрос кандидатов несёт `accountId`; пустой аккаунт — запросов 0 | `NotificationContactsPage.test.tsx`, проба `iam.ts` |
| CX6-25 | одна загрузка; отказ → повтор; последовательность состояний `pending → unavailable → pending → available`, вызовов загрузчика 2; кнопка в `pending` — без признака недоступности; подписка после успеха — `available` сразу, вызовов 1 | `ui-future/host/src/remotes/rememberLoad.test.ts`, `HostRail.test.tsx`; снятие по идентичности — рецензент диффа (предел — З14) |
| B1 (ревью `defdbe67`) | чтение признака не отвечает → по `CONFIG_DEADLINE_MS` `unreadable`, фокус начинает новое; `fetch` без отклика на отмену — всё равно `unreadable`; опоздавший ответ не меняет состояние. Цикл не отвечает → по `POLL_DEADLINE_MS` значок `"!"`, следующий таймер начинает цикл, опоздавший ответ не меняет значок | `ui-future/shared/src/lib/console-config.test.ts`, `ui-future/host/src/lib/unread-poll.test.ts` |
| I1 (ревью `defdbe67`) | отметка успешна, настройки несут позицию новее загруженной верхней — лента перечитана, «новые» только выше позиции | `NotificationCenterPage.test.tsx`; монотонность у владельца — Е6 |
| CX6-29 (пересверка `7294a684`), И20 | после отметки настройки отвечают раньше ленты — ни в один момент не помечено новым всё загруженное; близнец — лента раньше настроек; чтение, начатое до успеха, в снимок не входит | `NotificationCenterPage.test.tsx` |
| I2 (ревью `defdbe67`), И19, CX6-28 | два нажатия в одном синхронном блоке **без сдвига часов** — один запрос; близнец — нажатие после исхода первой мутации — второй запрос: «Подписаться», отметка, сохранение матрицы, период, снятие подписки, контакт; тот же предмет у хука — вызовов `mutationFn` 1 и 2, отказ опускает флаг | `ui-future/shared/src/hooks/useGuardedMutation.test.tsx`, `ResourceDetailExtensions.test.tsx`, `NotificationCenterPage.test.tsx`, `NotificationSettingsPage.test.tsx`, `NotificationContactsPage.test.tsx` |
| I3 (ревью `defdbe67`) | отметка во время цикла, затем устаревший цикл не отвечает — его дедлайн значок не меняет | `ui-future/host/src/lib/unread-poll.test.ts` |
| CX6-10, строка 31 (пересверка `defdbe67`) | блок `notify` в `configmap-nginx.yaml` начинается отдельной строкой `---`, первое `name:` — `ui.notifyName` | `ui-chart-remote-entry-cache.test.ts` с `"notifyName"` — красный до шаблона, зелёный после (полоса E1) |
| CX6-26 (пересверка `7294a684`) | исход дедлайна — `unreadable`; `fetch` без отклика на отмену — всё равно `unreadable`; ответ после дедлайна не меняет состояние | `console-config.test.ts` (строка B1); одна константа срока и снятие таймера любым исходом — рецензент диффа |
| CX6-27 (пересверка `7294a684`) | исход цикла однократен и поле «исход применён» — у объекта цикла; предел хвоста — location с `proxy_read_timeout` | `unread-poll.test.ts` (строки B1, I3); location префикса `notify` — рецензент диффа чарта (полоса E1, гейта нет) |
| CX6-30 (пересверка `7294a684`) | монотонность и порядок «наибольшего» у владельца | не держатель NTF-6: Е6 (§9, предикат M25 и запись `APPROVED`); порядок позиции — сценарий NTF3-161 приёмки NTF-3 (заказ через диспетчера) |

Модульные пробы шлют запросы в подменённый клиент с управляемыми ответами; ожидание —
условием, часы — управляемые (`jest.useFakeTimers`), без пауз.

### З19. Закрепление образа модуля на стендах

Каждый профиль зонтика, закрепляющий образы модулей консоли (M11: `uif.<модуль>.image`), при
флаге `true` в своей цепочке получает `uif.notify.image` тем же видом закрепления (ветка и
коммит сборки), что соседние модули того же профиля; профиль без закрепления образов модулей
получает образ подстановкой из образа хоста (`_helpers.tpl`). Образ публикует матрица
`build` `ui.yml` (§10). Достижимость закреплённого образа держит существующий гейт
`deploy/published_image_pin_is_reachable*`; профиль с флагом `true` без опубликованного образа
`notify` — его красное, а не ошибка выкатки.

### З20. Механизмы с дедупликацией «в полёте» — перепись и решение по каждому (B1)

Механизм, который, пока его попытка в полёте, не начинает новой (схлопывает триггеры в неё),
при зависшем ответе останавливается навсегда, если **все** пути выхода идут через эту
попытку. Общий клиент края предела времени не ставит (M15), у `fetch` окна своего предела нет,
механизма отмены по сроку в хосте и `shared` сегодня нет (M20). Перепись — по решениям
редакции 3, где механизм держит попытку в полёте: `git show 4e2b4621a:docs/changes/issue-2925/design.md
| sed -n '/^## 2\./,/^## 3\./p' | awk '/^### З/{z=$2} /в полёте|схлопыва|хранимое обещание|хранит обещание/{print z}' | sort -u`
(`4e2b4621a` несёт `defdbe67`) → `З2.`, `З9.`, `З14.`, `З18.`; З18 — таблица держателей, не
механизм. К трём механизмам редакция 4 добавляет четвёртый вид — мутации с действием,
недоступным в полёте (И19, I2). Решение по каждому:

| механизм | что схлопывается в попытку | путь выхода, минуя попытку | решение |
|---|---|---|---|
| чтение признака (З2) | фокус, «Повторить» | нет: оба пути ведут в то же чтение; первое чтение держит `loading`, где кнопки «Повторить» нет | **дедлайн `CONFIG_DEADLINE_MS`**, исход — `unreadable`, применение однократно по идентичности (З2 п.3) |
| цикл счётчика (З9) | таймер, фокус | нет: `NOTIFY_SEEN_EVENT` бывает только после отметки | **дедлайн `POLL_DEADLINE_MS`**, исход — отказ (`"!"` при текущем `gen`), однократно (З9) |
| загрузка модуля `rememberLoad` (З14) | повторные `load()` | не требуется: `pending` не закрывает ни одного пути — кнопка обычная, маршрут показывает загрузку фабрики | **дедлайна нет**: дедлайн объявил бы недоступным модуль без отказа; зависание загрузки — свойство общей фабрики всех девяти модулей (M19, §12) |
| мутации действий (З10, З13; И19) | повторное нажатие того же действия — синхронным флагом `useGuardedMutation` (CX6-28), не отрисованным `isPending` | да: флаг принадлежит экземпляру хука смонтированного экрана или карточки, уход и возврат дают новый (M5) | **дедлайна нет**: исход мутации по истечении срока неизвестен, объявить его отказом — ложь о том, что сервер мог закоммитить (И6) |
| запросы экранов клиентом запросов (З6, З10, З13) | — | — | вне перечня: собственной дедупликации «в полёте» этот замысел им не заводит; повтор и состояние загрузки — общий путь клиента запросов, как у всех экранов консоли |

Инвариант И18: «механизм этого замысла, схлопывающий триггеры в попытку в полёте, ограничен
дедлайном; механизм без дедлайна назван в переписи с путём выхода или причиной». Значения
`CONFIG_DEADLINE_MS`, `POLL_DEADLINE_MS` — одно место, §8. Держатели — пробы З2 и З9 на управляемых часах (З18, строка B1).

## 3. Инварианты

| № | инвариант | чем держится |
|---|---|---|
| И1 | `shared` не импортирует модули; `host → notify` только федерацией | `module-boundary-coverage.test.ts`; предикат §1.8 приёмки |
| И2 | у признака Р2 нет умолчания: ни `import.meta.env`, ни значения в `values.yaml` подчарта, ни запасного исхода | DoD 6 (`notificationsEnabled` только в `console-config.ts`); рендер подчарта без `global.kacho` → тело `null` (З5); `console-config.test.ts` |
| И3 | одно окно — один исход признака | `console-config.test.ts` (CX6-16) |
| И4 | «не `200`» и «`200` не той формы» — одно состояние «отвергнуто» на каждом экране; пустота показывается только на ответ `200` с пустым массивом | `notify.test.ts`, экранные пробы З13; NTF6-56…59 |
| И5 | после найденного `seenUpTo` строки ниже не «новые» на любой странице | `unread-count.test.ts` (CX6-17) |
| И6 | ни одна ветка исхода операции не показывает успех без `done && !error` | `notify.test.ts` (З8) |
| И7 | один клиент, один счёт, один загрузчик, один переход, одна проверка id | DoD 6 (предикаты по имени и пути); вторая реализация под другим именем — вниманием рецензента диффа (`ui-reviewer`, пункт чек-листа), разбор CX6-02 |
| И8 | неотключаемое не попадает в `:setEntries` | З13; NTF6-27, 28, 31 |
| И9 | каждый location раздачи с собственным `add_header` включает заголовки защиты | `console_location_security_headers_test.go` (CX6-15) |
| И10 | признак консоли совпадает с развёртыванием `notify` на каждой поставляемой цепочке | `deploy/console_notify_flag_parity_test.go` (З5, DoD 8) |
| И11 | адрес ресурса строит только `resourceDetailHref`; из ответа принимаются только сегменты в алфавите id | `id-form.test.ts`, `InboxItemRow.test.tsx`, NTF6-16 |
| И12 | каждый читатель признака ветвится исчерпывающе по четырём состояниям; `loading` не показывается ни одним исходом | проверка `never` в `tsc`; `App.test.tsx` (CX6-21) |
| И13 | отказ формы ответа не несёт статуса успеха и не повторяется — ни у запросов `notify`, ни у обхода пользователей на экране контактов | `notify.test.ts`, `error-presentation.test.ts`, `queryClient.test.ts`, `NotificationContactsPage.test.tsx` (CX6-22) |
| И14 | к значку применяется исход только последнего начатого цикла — и успех, и отказ — и не более одного раза: первое из «ответ пары» и «дедлайн `POLL_DEADLINE_MS`» | `unread-poll.test.ts` (CX6-05, CX6-23, B1) |
| И15 | слушатель события окна живёт ровно столько, сколько клиент кэша, который он инвалидирует | `useNotifySubscriptionsSync.test.tsx`, `ResourceDetailExtensions.test.tsx` (CX6-20) |
| И16 | каждый remote федерации хоста монтируется обёрткой общей фабрики с именем раздела из каталога | `remote-boundary-coverage.test.ts` (CX6-10) |
| И17 | исход загрузки модуля снимает и публикует только обработчик хранимого обещания; у подписчика три названных состояния, поздний подписчик получает текущий исход снимком | `rememberLoad.test.ts`, `HostRail.test.tsx`; идентичность — рецензент диффа (CX6-25, предел — З14) |
| И18 | механизм этого замысла, схлопывающий триггеры в попытку в полёте, ограничен дедлайном (`CONFIG_DEADLINE_MS`, `POLL_DEADLINE_MS`); механизм без дедлайна назван в переписи З20 с путём выхода или причиной | `console-config.test.ts`, `unread-poll.test.ts` (B1); перепись З20 — рецензент замысла и диффа |
| И19 | пока мутация действия в полёте, действие недоступно — одна мутация на действие; решение принимает синхронный флаг `useGuardedMutation`, поднятый до вызова, а не отрисованное состояние | `useGuardedMutation.test.tsx`, `ResourceDetailExtensions.test.tsx`, `NotificationCenterPage.test.tsx`, `NotificationSettingsPage.test.tsx`, `NotificationContactsPage.test.tsx` — в форме «два нажатия в одном синхронном блоке без сдвига часов» с близнецом (I2, CX6-28) |
| И20 | пометки «новое» центра вычисляются только из снимка пары «настройки + лента», оба чтения которой завершились в одной паре; после отметки — оба начаты после успеха | `NotificationCenterPage.test.tsx` — порядок ответов пары и близнец (CX6-29) |

## 4. Компоненты и границы

Дерево — `PRO-Robotech/kacho`. «Новый» — файла нет на `1d42a6728bf`.

| компонент | путь | новый/правка | бандл-владелец | читают |
|---|---|---|---|---|
| клиент `notify` | `ui-future/shared/src/api/notify.ts` | новый | компилируется в каждый потребитель | хост, `notify`, карточка в модулях |
| отказ формы ответа | `ui-future/shared/src/api/response-shape.ts` | новый | то же | `notify.ts`, `iam.ts` (обход), `error-presentation.ts` |
| обход пользователей аккаунта | `ui-future/shared/src/api/iam.ts` (`listAllAccountUsers`) | правка (добавление функции; прочие функции не меняются) | то же | `notify` (контакты) |
| признак Р2 | `ui-future/shared/src/lib/console-config.ts` | новый | то же; состояние — на окне | хост, `notify`, карточка |
| шапка общего модуля конфигурации | `ui-future/shared/src/lib/config.ts` | правка (только комментарий шапки, З2 п.7) | то же | — |
| счёт Р18 | `ui-future/shared/src/lib/unread-count.ts` | новый | то же | хост, `notify` |
| проверка id | `ui-future/shared/src/lib/id-form.ts` | новый | то же | `notify` |
| слушатель событий подписок | `ui-future/shared/src/hooks/useNotifySubscriptionsSync.ts` | новый | то же | карточка, `NotifyPage` |
| охрана «одна мутация на действие» | `ui-future/shared/src/hooks/useGuardedMutation.ts` | новый | то же | карточка, экраны `notify` (З10, З13) |
| переход спека↔модуль/тип | `ui-future/shared/src/lib/subscription/subjects.ts` | правка | то же | карточка, `notify` |
| действие подписки | `ui-future/shared/src/components/organisms/ResourceDetailExtensions/` | правка | каждый модуль с карточкой | — |
| пояснение `403`, отказ формы | `ui-future/shared/src/lib/error-presentation.ts` | правка | все | все экраны |
| имена разделов | `ui-future/shared/src/lib/entity-names.ts`, `ui-future/host/src/lib/entity-names.ts` | правка | все / хост | рейл, панель недоступности |
| опрос счётчика | `ui-future/host/src/lib/unread-poll.ts` | новый | хост | `HostRail` |
| обёртка модуля и её загрузка | `ui-future/host/src/remotes/{NotifyRemote.tsx,notify.d.ts,rememberLoad.ts}` | новые | хост | `App.tsx`, `HostRail` |
| клиент запросов модуля | `ui-future/notify/src/lib/queryClient.ts` (`createNotifyQueryClient`) | новый | `notify` | `NotifyPage`, экранные пробы |
| рейл, маршрут, каталог, реэкспорт | `ui-future/host/src/{components/organisms/HostRail,components/atoms/RailButton,App.tsx,remotes/moduleCatalog.ts,remotes/index.ts}` | правка | хост | — |
| сборка хоста | `ui-future/host/{vite.config.ts,jest.config.cjs,Dockerfile}`, `ui-future/host/src/test/notify-remote.tsx` | правка + заглушка новая | хост | — |
| модуль | `ui-future/notify/**` | новый | `notify` | хост (федерация) |
| корневые сценарии | `ui-future/package.json` | правка | — | конвейер |
| чарт консоли | `ui-future/deploy/{values.yaml,templates/*}` | правка + `deployment-notify.yaml` новый | — | зонтик |
| гейты чарта | `ui-future/deploy/console_notify_render_test.go`, `console_location_security_headers_test.go`, `console_notify_source_key_test.go`; `deploy/console_notify_flag_parity_test.go` | новые | — | конвейер |
| профили стендов | `deploy/helm/umbrella/values.a8f60d.yaml` (и каждый профиль, закрепляющий образы модулей, — З19) | правка | — | стенд |
| конвейер | `.github/workflows/ui.yml`, `.github/workflows/console-e2e.yml` | правка | — | — |
| шапки синтетических входов инъекционных проб | `internal/repohygiene/console{formatterversion,lintproducer,stylelintconfig,typecheckproducer}_injection_test.go` (M23) | правка (только комментарий): число пакетов приведено к составу с `notify` либо снято слово «настоящий» — заказ пересверки `defdbe67` | — | конвейер |
| сквозные пробы | `ui-future/e2e/specs/{fixtures.ts,users.spec.ts,notifications-*.spec.ts}` | правка + новые | — | `console-e2e.yml` |

**Общий клиент края `shared/src/api/client.ts` не правится** (З9: отмены нет). **Граница с
соседями.** Край (`gateway/**`: маршруты `/notify/v1/*`, карта операций), служба `notify`, её
чарт и флаг — не этого изменения (NTF-1, NTF-3). Изменение NTF-6 не трогает `gateway/`,
`services/`, `proto/`, `corelib`, `kaname`; в `internal/repohygiene` — только комментарии шапок
M23.

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

// ui-future/shared/src/api/response-shape.ts
export class ResponseShapeError extends Error { readonly name = "ResponseShapeError";
  constructor(readonly path: string, readonly field: string) { super(`unexpected response shape: ${path} ${field}`) } }
export function isResponseShapeError(err: unknown): err is ResponseShapeError;

// ui-future/shared/src/lib/console-config.ts
export type ConsoleNotificationsState = "loading" | "enabled" | "disabled" | "unreadable";
```

Имена событий окна — строки с приставкой `kacho:`, чтобы не совпасть с событиями чужих
библиотек; сравнение — только по константе. Событие — `new Event(<имя>)` без данных.

## 6. Схема БД

**DDL — нет.** Консоль состояния не хранит; всё состояние — у `notify` (NTF-3) и в памяти
окна. `localStorage` не используется: признак, счёт и кэш не переживают перезагрузку
намеренно (исход после перезагрузки — от сервера).

## 7. Последовательности

**П1. Старт окна.**
хост монтируется → `loadConsoleConfig()` создаёт объект на окне в `loading`,
`GET /console-config.json` → модуль с карточкой монтируется → `loadConsoleConfig()` получает тот
же объект (запроса нет) → пока `loading`: кнопки нет, адрес `/notifications/*` показывает
индикатор ожидания (не дольше `CONFIG_DEADLINE_MS`: истечение — `unreadable`) → исход `enabled`: рейл показывает кнопку, зовёт `loadNotifyPage()`,
`unread-poll` запускает цикл; `disabled`: кнопки нет; `unreadable`: кнопка с признаком
недоступности, запросов к `/notify/v1/*` нет → возврат в фокус → повторное чтение → `enabled`:
слушатели всех бандлов перерисованы.

**П2. Цикл счётчика.**
триггер → текущий цикл без исхода? (таймер/фокус — выход) → `gen++`, цикл запоминает номер,
ставит дедлайн `POLL_DEADLINE_MS` → `GET /notify/v1/inbox?pageSize=100` ∥ `GET /notify/v1/preferences` →
первое из двух: исход пары (оба `200` и форма верна → `unreadCount(page1, seen_up_to,
token≠"")`; иначе `"unavailable"`) либо истечение `POLL_DEADLINE_MS` (`"unavailable"`); второе отброшено →
номер цикла равен `gen`? да — значок; нет — исход отброшен (и успех, и отказ).

**П3. «Отметить всё просмотренным».**
центр (кнопка недоступна до исхода мутации синхронным флагом, И19) → `PATCH /notify/v1/preferences` (маска
`seen_up_to`) → владелец пишет `GREATEST(старое, новое)` (Д25, Е6) → `Operation{done:true}` →
`settleNotifyOperation` → успех → `window.dispatchEvent(new Event(NOTIFY_SEEN_EVENT))` → хост:
`gen++`, новый цикл (прежний дорабатывает, его исход отброшен) → значок гаснет; центр
перечитывает настройки и загруженные страницы ленты (обе начаты после успеха) → снимок пары после
обоих ответов → пометки по действующей позиции (И20).
Отказ → значок прежний, текст отказа (NTF6-15).

**П4. Подписка с карточки.**
карточка (бандл `vpc`, провайдер страницы) → состояние `enabled` → `["notify","catalog"]` (кэш
страницы) → ячейка `(RESOURCE_CHANGE, EMAIL: SWITCHABLE)` у `notifyModuleOf("networks") = "vpc"`
→ `["notify","subscriptions"]` (кэш, полный обход) → «Подписаться» (недоступно до исхода
мутации, И19) → `POST /notify/v1/subscriptions` → `done && !error` → `dispatchEvent(NOTIFY_SUBSCRIPTIONS_EVENT)`
→ слушатели всех смонтированных провайдеров (в том числе свой) инвалидируют ключ → «Вы
подписаны» из перечитанного списка. Отказ → событие, перечитывание, текст отказа.

**П5. Отписка на экране настроек и возврат на карточку.**
`notify` → `DELETE /notify/v1/subscriptions/{id}` → успех → событие → слушатели смонтированных
провайдеров инвалидируют ключ → переход на карточку: страница `vpc` монтируется с новым
`QueryClient` (M5) и читает список заново, либо, если она была смонтирована, её слушатель уже
инвалидировал ключ → «Подписаться на изменения» (NTF6-36).

**П6. Сохранение настроек.**
форма → разница по `SWITCHABLE` → пусто: запроса нет; иначе `POST :setEntries` с разницей →
`done` → перечитывание настроек → `explicit` снят с пометки «по умолчанию».

**П7. Контакт безопасности.**
`GET …/contacts` → `200` и `security` есть → строка; иначе отказ, выбора и сохранения нет →
выбор из полного списка пользователей **выбранного аккаунта**
(`GET /iam/v1/users?accountId=<id>&pageSize=1000` до пустого токена) → `PATCH …/contacts` (маска
`security`) → `done` → перечитывание.

## 8. Конфигурация, ручки и границы

**Ручки установки.** Своей ручки включения у консоли нет (Р2).

| ручка | владелец | граница / исходы | где читается |
|---|---|---|---|
| `global.kacho.notifications.enabled` | NTF-1 Р9 | логическое; не задано — рендер зонтика отвергнут NTF-1; в отдельном рендере подчарта — тело `null` → `unreadable` | `configmap-nginx.yaml`, `_helpers.tpl` (`ui.notifyEnabled`) |
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
| страница пользователей | 1000 | `shared/src/api/iam.ts` (`listAllAccountUsers`) | предел края для списка |
| потолок значка | 99 | `unread-count.ts` | Р18 |
| повторов чтения признака в полёте | не больше одного | `console-config.ts` | З2 |
| дедлайн чтения признака `CONFIG_DEADLINE_MS` (в редакции 4 — `T1`) | 10 с | `console-config.ts` | З2 п.3, З20: ответ раздачи — литерал `return 200` без апстрима (З3); предел отделяет «не ответило» от «медленно ответило» с запасом и ограничивает `loading` |
| дедлайн цикла счётчика `POLL_DEADLINE_MS` (в редакции 4 — `T2`) | 30 с | `unread-poll.ts` | З9, З20: меньше периода опроса 60 с — цикл, начатый таймером, получает исход до следующего таймера; цикл, начатый фокусом или отметкой, таймер может застать без исхода и схлопывается в него (З9). Предел хвоста запросов после дедлайна — не эта величина, а `proxy_read_timeout 30s` раздачи (M24, З9) |
| повторов запроса `notify` на отказ формы | 0; на прочий отказ — 1, как у соседей | `notify.ts` (`notifyQueryRetry`) | З6, CX6-22 |

## 9. Рёбра

| ребро | вид | новое? | основание |
|---|---|---|---|
| консоль → край → `notify-api` (`/notify/v1/*`) | runtime, HTTP через раздачу хоста | ребро «консоль → край» существующее; маршруты края — NTF-3 | §10 приёмки |
| консоль → край → служба доступа (`/iam/v1/users?accountId=…`) | runtime, HTTP | существующее; новый вызов с обязательным фильтром аккаунта | З13, CX6-24 |
| раздача хоста → край (префикс `notify`) | runtime, nginx | правка перечня | З3 |
| раздача хоста → сервис модуля `ui-notify` | runtime, nginx | новое внутри чарта консоли | З3, З4 |
| хост → модуль `notify` | сборка, федерация, обёртка `NotifyRemote` | новое | З1, З14 |
| `notify`, хост, модули → `shared` | сборка, алиас | существующее направление | И1 |
| бандл ↔ бандл | runtime, события окна `NOTIFY_SEEN_EVENT`, `NOTIFY_SUBSCRIPTIONS_EVENT` (слушатели — хуками с отпиской); объект признака на окне | новое | З2, З9, З10 |

Межсервисных рёбер изменение не заводит; ацикличность графа служб не затрагивается.

**Внешние зависимости и заказы:**

| № | что | чей предмет | как снимается |
|---|---|---|---|
| Е1 | одобрение NTF-1 с Р9 | NTF-1 | снято на текущей редакции: запись `APPROVED` на `29cfa368` (коммит `d18efea9c`); строк о флаге в разнице `530e2296 → 29cfa368` — 0 (§0). Правка приёмки NTF-1 открывает Е1 снова до записи на новый отпечаток |
| Е2 | одобрение NTF-3 в форме §1.7 приёмки | NTF-3 | запись `APPROVED` на отпечаток NTF-3 с той же формой Р9, Р10, Р11, Р20, Р29 **и с Д25 (Е6)**; иная форма — новая редакция приёмки NTF-6 (Р13). На `88ad95c6` запись `APPROVED` есть, но редакция без Д25 (M22); редакция 21 (`c481e642`) Д25 вносит, записи ревью на неё нет — Е2 открыта |
| Е3 | подчарт `notify` и флаг в зонтике | NTF-1 | посажено в ствол; рендер зонтика несёт `charts/notify/templates/` |
| Е4 | `notify-api` за краем с маршрутами `/notify/v1/*` и каталогом на стенде | NTF-3 | посажено; предпосылка стенда DoD 13 зелёная |
| Е5 | маршрут приставки операций `notify` в `prefixToBackend` края либо записанное производителем «`done = false` у `notify-api` не бывает» с держателем | NTF-3 (заказ разбора CX6-09) | запись в приёмке NTF-3; для NTF-6 не блокирует (З8) |
| Е6 | монотонность отметки `seen_up_to` (Д25): `PATCH` с маской `seen_up_to` пишет наибольшее из хранимого и присланного атомарно, откат назад невозможен; «наибольшее» — **в порядке позиции ленты** (последовательность приёма Р9), а не строкой: позиция на проводе — строка, и строковое сравнение расходится с порядком на смене числа разрядов (`"9" > "10"`) (CX6-30 (б)); сценарий монотонности с положительным близнецом, чьи позиции пересекают смену числа разрядов | NTF-3 (заказ ревью `defdbe67`, I1; порядок позиции — заказ пересверки `7294a684` автору NTF-3 через диспетчера) | снимается по **якорю, а не по слову** (CX6-30 (а)): (1) `sed -n '/^\*\*Р10\./,/^\*\*Р11\./p' <приёмка NTF-3> \| grep -c 'NTF3-161'` ≥ 1 (M25: на `c481e642` — 1, на `88ad95c6` — 0); (2) на том же отпечатке — запись `docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/<sha256 приёмки>.yaml` с `verdict: APPROVED` (сегодня на `c481e642` записи нет — Е6 открыта); (3) порядок позиции в Р10 и близнец смены разрядов в NTF3-161 — судит рецензент приёмки NTF-3 и ревью замысла при снятии Е2 (словом предиката не выразимо: M22 показал, что слово не ловит предмет). Сценарий сменил номер — предикат (1) правится вместе с Е6, а не молча краснеет |

## 10. Перепись мест, перечисляющих модули руками или по образцу модуля (CX6-10)

Предикаты: M1 (15 файлов, строки 1–15), M13 (места по образцу модуля, строки 16–20), тестовые
перечни M2 (строки 21–23 и 28–32; строки 28–32 внесены редакцией 3, номера прежних строк не
сдвинуты, потому что на них ссылаются `tasks.md` и записи ревью), прочие места, названные
приёмкой (строки 24–27). Решение по каждому.

| № | место | источник | решение | основание |
|---|---|---|---|---|
| 1 | `ui-future/host/src/remotes/moduleCatalog.ts` | M1 | **правится**: запись `notify` без раздела; комментарий о модулях без раздела | Р1, §3 приёмки |
| 2 | `ui-future/host/src/App.tsx` | M1 | **правится**: маршрут `/notifications/*` по четырём состояниям признака, `NotifyRemote` из `./remotes` | Р2, З2, З14 |
| 3 | `ui-future/host/src/remotes/index.ts` | M1 | **правится**: `export * from "./NotifyRemote"` | З14 |
| 4 | `ui-future/host/src/lib/module-navigation.tsx` | M1 | **не правится**: `REMOTE_NAV_LOADERS`/`NAV_REMOTES` — модули с навигацией, у `notify` её нет; загрузчик страницы — в `NotifyRemote.tsx` | З14 |
| 5 | `ui-future/host/vite.config.ts` | M1 | **правится**: удалённый модуль `notify` в `remotes` (`KACHO_NOTIFY_REMOTE`, dev `http://localhost:4183/assets/remoteEntry.js`); прокси dev-сервера `/notify/v1` на край | З1, M14 |
| 6 | `ui-future/host/jest.config.cjs` | M1 | **правится**: `^notify/NotifyPage$` → заглушка `src/test/notify-remote.tsx` | пробы хоста NTF6-02 |
| 7 | `ui-future/host/Dockerfile` | M1 | **правится**: `ARG`/`ENV KACHO_NOTIFY_REMOTE` | §8 |
| 8 | `ui-future/package.json` | M1 | **правится**: `notify` в `typecheck`, `lint`, `format:check`, `test`; в `workspaces` — **нет** (самостоятельный пакет) | З1, M10 |
| 9 | `ui-future/shared/src/lib/entity-names.ts` | M1 | **правится**: `SERVICES.notify` (канон) | З14 |
| 10 | `ui-future/deploy/values.yaml` | M1 | **правится**: блок `notify`, `host.upstreams.notify`; ключа `global.kacho.notifications` **нет** | З3, З4, И2 |
| 11 | `ui-future/deploy/templates/_helpers.tpl` | M1 | **правится**: `ui.notifyEnabled`, имя, образ, политика, апстрим | З4 |
| 12 | `ui-future/deploy/templates/service.yaml` | M1 | **правится**: блок под условием | З4 |
| 13 | `ui-future/deploy/templates/hpa.yaml` | M1 | **правится**: блок под условием | З4 |
| 14 | `ui-future/deploy/templates/configmap-nginx.yaml` | M1 | **правится**: префикс, `/console-config.json`, `/notify-remote/`, раздача модуля | З3 |
| 15 | `ui-future/deploy/templates/deployment-host.yaml` | M1 | **правится**: `KACHO_UI_NOTIFY_UPSTREAM` под условием | З4 |
| 16 | `ui-future/host/src/remotes/NotifyRemote.tsx` | M13 (`NlbRemote.tsx`) | **заводится**: `makeRemote(loadNotifyPage, …, moduleLabelOf("notify"))`, литерал `import("notify/NotifyPage")` | З14, M14 |
| 17 | `ui-future/host/src/remotes/notify.d.ts` | M13 (`nlb.d.ts`) | **заводится**: объявление `notify/NotifyPage`; `notify/navigation` не объявляется | З14 |
| 18 | `ui-future/host/src/test/notify-remote.tsx` | M13 (`nlb-remote.tsx`) | **заводится**: заглушка страницы для проб хоста | строка 6 |
| 19 | `ui-future/host/src/test/notify-navigation.ts` | M13 (`nlb-navigation.ts`) | **не заводится**: навигации у модуля нет | З1 |
| 20 | `ui-future/deploy/templates/deployment-notify.yaml` | M13 (`deployment-nlb.yaml`) | **заводится** | З4 |
| 21 | `ui-future/shared/src/components/molecules/Toaster/Toaster.mounted.test.ts` (`MUTATING_MODULES`) | M2 | **правится**: `notify` — мутирующий модуль | M2 |
| 22 | `ui-future/shared/src/test/console-verb-routes-exist.test.ts` (`CONSOLE_APPS`) | M2 | **правится**: `notify` | M2 |
| 23 | `ui-future/host/src/remotes/remote-boundary-coverage.test.ts` | M2 (вывод обходом) | **не правится**: сводит три перечня обходом; с `notify` в строках 1, 5, 16 — зелёный, печать 9/9/9 | З14, И16 |
| 24 | `ui-future/host/src/lib/entity-names.ts` (7 из 8 — без `dashboard`) | зеркало канона | **правится** вслед за каноном | шапка зеркала |
| 25 | `ui-future/deploy/templates/ingress.yaml` | приёмка | **не правится**: модулей не перечисляет | M9 |
| 26 | `.github/workflows/ui.yml`, `.github/workflows/console-e2e.yml` | приёмка | **правится**: `STANDALONE`, матрица `test` (`pkg`), матрица `build` (`project`), имя задания `typecheck` (число пакетов); шаг предпосылки DoD 13 | DoD 9, DoD 13, M10 |
| 27 | `deploy/helm/umbrella/values.*.yaml`, закрепляющие образы модулей консоли (M11) | приёмка | **правится**: `uif.notify.image` в каждом профиле, чья цепочка рендерит модуль (флаг `true`), тем же видом закрепления, что соседи; достижимость образа — существующий гейт `published_image_pin_is_reachable` | З19 |
| 28 | `ui-future/shared/src/test/iam-pages-authz-single-source.test.ts:33` (`CONSOLE_APPS`) | M2 | **правится**: `notify` внесён. Все три ветки гейта с ним зелёные: каталога `notify/src/pages/iam` нет (форка экранов доступа нет); маршрута `path="/iam…"` в `notify/src` нет; литерального перехода `navigate("/iam…")`/`to="/iam…"`/`href="/iam…"` нет — адрес карточки службы доступа строит только `resourceDetailHref` в `shared` (З12, И11). Экран контактов читает пользователей через `@shared/api/iam` и поверхности управления доступом не заводит; условие к коду модуля — литерального пути `/iam` в `notify/src` нет | M2, З12, З13 |
| 29 | `ui-future/shared/src/components/organisms/form/ResourceIcon/ResourceIcon.registry.test.ts:27` (`CONSOLE_APPS`) | M2 | **правится**: `notify` внесён. Реестра `resource-registry*` в `notify/src/lib` нет — модуль спек ресурсов не объявляет (карточка и спеки остаются в реестрах `shared` и модулей, §4), обход каталог пропускает, нижний порог «≥ 5 реестров» не меняется; внесение делает будущий реестр модуля судимым, а не молча выпавшим | M2, §4 |
| 30 | `ui-future/shared/src/lib/spec-columns.bool-labels.test.ts:27` (`CONSOLE_APPS`) | M2 | **правится**: `notify` внесён — то же основание, что строка 29: реестра у модуля нет, колонок с форматом `bool` модуль не объявляет | M2, §4 |
| 31 | `ui-future/shared/src/test/ui-chart-remote-entry-cache.test.ts:38` (`REMOTES`) | M2 | **правится**: `"notifyName"` внесён. Проба читает объявление шаблона, а не рендер; блок раздачи модуля (`{{ include "ui.notifyName" . }}-nginx`) объявлен в `configmap-nginx.yaml` под условием флага (З3, З4) и судится при любом значении флага: правило `remoteEntry.js` с `no-cache` стоит до общего правила для `js`. Условие к форме блока (пересверка `defdbe67`): отдельная строка `---`, первое `name:` — `ui.notifyName` (З3) | З3, M2 |
| 32 | `ui-future/shared/src/test/module-test-setup-single-source.test.ts` (`EXCUSED`) | M2 (перечень освобождённых) | **не правится**: это перечень освобождений (`host`, `dashboard`), а не модулей; `notify` судится обходом каталога. Условие к каркасу модуля (S1): `notify/jest.config.cjs` несёт `setupFilesAfterEnv: ["<rootDir>/../shared/src/test/setup.ts"]`, своего `src/test/setup.ts` нет — как у `nlb` | M2, M10 |
| — | `ui-future/dashboard/**`, `vpc`, `compute`, `storage`, `nlb`, `registry`, `iam`, `system` | — | исходники **не** правятся; образы пересобираются, потому что `shared` компилируется в бандл (карточка, Р17) | §1.8 приёмки |
| — | `ui-future/dev-federation.sh` | — | **не** правится: состав выводит из `host/vite.config.ts` | чтение скрипта |

Предикат полноты строк 1–15 — команда M1 на `1d42a6728bf`: 15 путей, каждый назван в таблице.
Строки 21, 22, 28–31 — шесть перечней руками по команде M2 (16 попаданий, разобраны в M2),
каждый с решением; строки 23 и 32 — гейты обходом, решение «не правится» с основанием.
Строки 16–20 — пять мест предиката M13 по образцу `nlb`, каждое с решением; место по образцу
модуля, не названное здесь, — находка рецензента диффа.

## 11. Отображение пунктов разбора в решения

Каждый пункт первичного разбора на `47bd8b70` и пересверок на `7613071f`, `deeea79a` и `7294a684` → решение замысла →
механизм → держатель.

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX6-01 | З11 | `NOTIFY_SOURCE_BY_OWNER` исчерпывающий по типу; `notifyModuleOf` — единственный читатель; `specOfKind` однозначен | `console_notify_source_key_test.go`, `subjects.test.ts` (в том числе `:144`), NTF6-60 |
| CX6-02 | З6, З7, З2, И7 | клиент, счёт, загрузчик — `shared`, по одному; вторая реализация под другим именем — пункт чек-листа `ui-reviewer` | DoD 6; рецензент диффа |
| CX6-03 | З10 | действие составляется рядом с расширением спеки | `ResourceDetailExtensions.test.tsx` |
| CX6-04 | З2, З3 | канал во время работы, три исхода плюс `loading`, без умолчания | NTF6-61, NTF6-02, NTF6-47, `console-config.test.ts` |
| CX6-05 | З9, И14, З20 | поколение на обеих ветках, схлопывание, новый цикл по `NOTIFY_SEEN_EVENT`; отмены нет (условие — CX6-23); исход однократен, дедлайн `POLL_DEADLINE_MS` (B1) | `unread-poll.test.ts` |
| CX6-06 (а) | З3 | префикс `notify` в перечне безусловно | NTF6-47, NTF6-22 |
| CX6-06 (б) | З6, З13, И4 | разборщик формы на каждую функцию; `ResponseShapeError` — то же состояние экрана, что не-`200` (форма отказа — CX6-22) | `notify.test.ts`, экранные пробы З13 |
| CX6-07 | З12 | `isPlatformId` до `ResourceLink` | `id-form.test.ts`, NTF6-16 |
| CX6-08 | З6, З10, З13 | полный обход подписок и пользователей **аккаунта**; перечитывание после отказа (условие — CX6-24) | `ResourceDetailExtensions.test.tsx`, `NotificationContactsPage.test.tsx` |
| CX6-09 | З8, Е5 | при `done = true` опроса нет; `done = false` — общий путь, отказ показан отказом; маршрут края — заказ NTF-3 | `notify.test.ts`; NTF6-27, 36, 38, 43, 52 |
| CX6-10 | §10, З14, И16 | перепись 32 мест: 15 по M1, 5 по образцу модуля M13, 8 по M2 (6 перечней руками — строки 21, 22, 28–31 — и 2 гейта обходом — строки 23, 32), 4 названных приёмкой — с решением по каждому; монтирование обёрткой общей фабрики `NotifyRemote.tsx`, общий исход загрузки — `rememberLoad` | `remote-boundary-coverage.test.ts` (9/9/9), `rememberLoad.test.ts`; пробы строк 21, 22, 28–31 зелёные с `notify` в переписи; DoD 9, 10; остальное — рецензент диффа по §10 |
| CX6-11 | З13 | одно состояние загрузки; подстановки пустого нет | `NotificationSettingsPage.test.tsx` |
| CX6-12 | З13 | `:setEntries` из разницы по `SWITCHABLE` | NTF6-27, 28, 31; `NotificationSettingsPage.test.tsx` |
| CX6-13 | З15 | меняется только значение константы | DoD 12 |
| CX6-14 | З16 | обход DoD 11 включает файлы `shared`, импортирующие клиент; одна функция переписи | гейт DoD 11, NTF6-18 |
| CX6-15 | З3, И9 | `include ui.securityHeaders` в каждом новом location; гейт по рендеру | `console_location_security_headers_test.go` |
| CX6-16 | З2, И3, З20 | состояние на окне под `Symbol.for`; выход из `unreadable` по фокусу и «Повторить» (четвёртое состояние — CX6-21); чтение в полёте не дольше `CONFIG_DEADLINE_MS` (B1) | `console-config.test.ts` |
| CX6-17 | З7, И5 | счёт над сцепкой загруженных страниц | `unread-count.test.ts`, `NotificationCenterPage.test.tsx` |
| CX6-18 | З12 | пустой `projectId` → `null`; негодный непустой → текст; предикат пересмотра сохранён | `InboxItemRow.test.tsx`; предикат пересмотра |
| CX6-19 | З10 | кэш провайдера страницы, `staleTime: Infinity`; сброс событием (слушатель — CX6-20) | `ResourceDetailExtensions.test.tsx` |
| CX6-20 | З10, И15 | слушатель `NOTIFY_SUBSCRIPTIONS_EVENT` — хук `useNotifySubscriptionsSync` внутри провайдера с отпиской при размонтировании; событие без данных; отправитель инвалидирует свой ключ тем же слушателем. Та же форма у слушателей `useUnreadPoll` (З9) | `ResourceDetailExtensions.test.tsx` «перемонтирование», `useNotifySubscriptionsSync.test.tsx` «слушателей 0» |
| CX6-21 | З2 п.1, п.6, И12 | четыре состояния, `switch` с проверкой `never` у каждого читателя; `loading` — ни названной страницы, ни перевода на панель, ни кнопки; имя `unreadable` вместо `unread` | `App.test.tsx` «`loading`», `tsc`, `console-config.test.ts` |
| CX6-22 | З6, З13, И13 | `ResponseShapeError` без `status`, не `ApiError`; ветка `presentError` → `"500"` и текст отказа данных; `notifyQueryRetry` — без повтора на отказ формы; умолчание клиента запросов модуля `createNotifyQueryClient()` — `notifyQueryRetry`, поэтому и обход пользователей экрана контактов не повторяется (условие пересверки `deeea79a`) | `error-presentation.test.ts`, `notify.test.ts`, `queryClient.test.ts`, `NotificationContactsPage.test.tsx` «обход — без повтора» |
| CX6-23 | З9, И14 | выбор (а): отмены нет, `client.ts` не правится; устаревший цикл отбрасывается сравнением поколения на ветке успеха и на ветке отказа | `unread-poll.test.ts` «отказ устаревшего цикла не меняет значок» |
| CX6-24 | З13, §9 | `listAllAccountUsers(accountId)` — `accountId` обязательный аргумент, пустой отвергается до запроса; каждый запрос обхода несёт `accountId` | `NotificationContactsPage.test.tsx` «запрос несёт `accountId`», проба `iam.ts` «пустой — запросов 0» |
| CX6-25 | З14, И17 | `rememberLoad`: обработчики исхода вешаются тем же синхронным вызовом, что кладёт обещание; снятие и публикация — только при `stored === p`; состояния подписчика `pending`/`available`/`unavailable`, кнопка рейла ветвится по ним исчерпывающе (`pending` — без признака недоступности); последний исход хранится и читается снимком (условие пересверки `defdbe67`) | `rememberLoad.test.ts` «вызовов загрузчика 2, последовательность `pending → unavailable → pending → available`», `HostRail.test.tsx` «`pending`» и «`unavailable`», `rememberLoad.test.ts` «подписка после успеха — `available` сразу»; ветка идентичности недостижима через `load()` — рецензент диффа (предел — З14) |
| CX6-26 | З2 п.3–4, З20, И18, §8 | дедлайн чтения признака `CONFIG_DEADLINE_MS`: свой `AbortController` на чтение, таймер окна сам завершает чтение исходом `unreadable`, исход применяется однократно по идентичности `inFlight`; таймер ставится тем же синхронным вызовом, что кладёт `inFlight`, снимается любым исходом; одна константа срока | `console-config.test.ts` — три пробы B1 (З2, З18); одна константа и снятие таймера — рецензент диффа |
| CX6-27 | З9, З20, И14, И18, §8, M24 | дедлайн цикла `POLL_DEADLINE_MS` без отмены; исход цикла — первое из «ответ пары» и «дедлайн», поле «исход применён» у объекта цикла; ложный довод «каждый таймер находит прежний цикл завершённым» снят — таймер схлопывается в цикл, начатый фокусом или отметкой; предел хвоста — `proxy_read_timeout 30s` location префиксов края, куда З3 вносит `notify` | `unread-poll.test.ts` (B1, I3); location префикса `notify` — рецензент диффа чарта (полоса E1) |
| CX6-28 | З10, З13, З20, И19, M26 | охрана «одна мутация на действие» — синхронный флаг `useRef` хука `useGuardedMutation`, поднятый до `mutateAsync` и опущенный по исходу этого вызова; отрисованный `isPending` — только вид кнопки | `useGuardedMutation.test.tsx` и экранные пробы в форме «два нажатия в одном синхронном блоке без сдвига часов — запросов 1» с близнецом «после исхода — 2» (З18) |
| CX6-29 | З13, И20, П3 | пометки центра — из снимка пары «настройки + лента»; после отметки оба перечитывания начаты после успеха (`cancelRefetch: true`), снимок — после обоих ответов; одиночного перечитывания ключа центра нет (`refetchOnWindowFocus: false`) | `NotificationCenterPage.test.tsx` — порядок ответов пары и близнец (З18) |
| CX6-30 | З13, Е6, §9, M22, M25 | опора на монотонную отметку соседа (Д25); Е6 снимается по ID сценария NTF3-161 в Р10 одобренного отпечатка, а не по слову; «наибольшее» — в порядке позиции ленты, близнец смены разрядов — заказ автору NTF-3 | предикат Е6 (M25) и запись `APPROVED` NTF-3; порядок позиции — держатель NTF3-161 у NTF-3 |

Неотображённых пунктов нет: 30 из 30 (CX6-01…19 первичного разбора, CX6-20…24 пересверки
`7613071f`, CX6-25 пересверки `deeea79a`, CX6-26…30 пересверки `7294a684`; CX6-06 — двумя
строками, строк 31). Пересверка `defdbe67` новых пунктов не завела.

## 11а. Условия ревью и пересверок на редакции 3 (`defdbe67`) и 4 (`7294a684`) и где они исполнены

| источник | условие | где в замысле | держатель или исход |
|---|---|---|---|
| ревью замысла, B1 (блокирующее) | предел времени у чтения `/console-config.json` и у цикла опроса; одно место в §8; инвариант; пробы в F1 и S5; после правки — пересверка разбора классов | З2 п.3–4, З9, З20, И18, И14, §8 (`CONFIG_DEADLINE_MS`, `POLL_DEADLINE_MS`) | `console-config.test.ts`, `unread-poll.test.ts` (З18, строка B1); `tasks.md` F1, S5; пересверка — заказ в возврате автора |
| ревью замысла, I1 | назвать откат `seen_up_to` и выбор у NTF-3 | З13 «Центр», П3, Е6; выбор сделан решением Д25 (монотонно, `GREATEST`) | `NotificationCenterPage.test.tsx` «позиция новее загруженной»; Е6 — приёмка NTF-3 |
| ревью замысла, I2 | «Подписаться» не принимает второго нажатия во время мутации | З10, И19 (расширено на все мутирующие действия модуля и карточки) | `ResourceDetailExtensions.test.tsx` «двойное нажатие — один `POST`» и ветки экранов З13 |
| ревью замысла, I3 | граница устаревших циклов и прочтение против фразы приёмки | З9 «Граница устаревших циклов» | `unread-poll.test.ts` «дедлайн устаревшего цикла значок не меняет» |
| ревью замысла, заметка 1 | `change.yaml`: `hashes.acceptance_sha256` и шапка состояния устарели | вне замысла: `change.yaml` приведён к приёмке `47bd8b70` (`APPROVED`) тем же изменением пакета | `sha256sum` приёмки = `hashes.acceptance_sha256` |
| ревью замысла, заметка 2 | `holders.yaml` `sev-console-e2e`: 21/14/11 против DoD 24/17/10 | вне замысла: предикат держателя приведён к DoD 3, 5, 7 приёмки `47bd8b70` (24, 17, 10) | `holders.yaml` |
| ревью замысла, заметка 3 | `config.ts` в S5 без основания в замысле | З2 п.7 (M21), §4; место — полоса F1, из S5 снято | `tasks.md` F1 |
| пересверка, CX6-25 | поздний подписчик получает текущий исход снимком; проба «подписка после успеха — `available` сразу, вызовов 1» | З14, И17 | `rememberLoad.test.ts` (З18) |
| пересверка, CX6-10 строка 31 | блок `notify` — отдельной строкой `---`, первое `name:` — `ui.notifyName` | З3 «Форма блока», §10 строка 31 | `ui-chart-remote-entry-cache.test.ts` (полоса E1) |
| пересверка, заказ замыслу | §0 и Е1 — по действующему отпечатку NTF-1 | §0 строка «ядро и флаг», Е1 (`29cfa368`, `APPROVED`, флаг не менялся) | предикат в §0 |
| пересверка, заказ пакету | `change.yaml` — на приёмку `47bd8b70` | как заметка 1 ревью | — |
| пересверка, заказ исполнителю | шапки синтетических входов `internal/repohygiene` («настоящий состав дерева») | §4, M23 | `tasks.md` T1 |
| пересверка `deeea79a`, условие CX6-22 | обход пользователей без повтора на отказ формы | З6, З13 (исполнено редакцией 3; пересверка `defdbe67` — «исполнено») | `queryClient.test.ts`, `NotificationContactsPage.test.tsx` |
| пересверка `7294a684`, to_design 1 | строки §11 для CX6-26…30 с решением и держателем | §11, пять строк | — |
| пересверка `7294a684`, to_design 2 (CX6-28) | в З10 и И19 назвать синхронную охрану; `isPending` — вид кнопки; пробы «два нажатия в одном синхронном блоке без сдвига часов — запросов 1» с близнецом | З10 «Охрана синхронная», З13, З20, И19, §4, M26 | `useGuardedMutation.test.tsx`, экранные пробы (З18) |
| пересверка `7294a684`, to_design 3 (CX6-27) | в З9 и §8 снять довод «каждый таймер находит прежний цикл завершённым»; назвать предел хвоста | З9 «Что даёт `POLL_DEADLINE_MS`…», «Предел хвоста»; §8 строка `POLL_DEADLINE_MS`; M24 | `unread-poll.test.ts`; location — рецензент диффа чарта |
| пересверка `7294a684`, to_design 4 (CX6-29) | условие пары перечитываний после отметки и проба порядка ответов | З13 «Пометки — только из согласованной пары», И20, П3, З18 | `NotificationCenterPage.test.tsx` |
| пересверка `7294a684`, to_design 5 (CX6-30) | Е6 и `tasks.md` Е6 — предикат по ID сценария монотонности в Р10 одобренного отпечатка; «наибольшее» — в порядке позиции | §9 Е6, M25, M22; `tasks.md` §1 Е6 | предикат M25 и запись `APPROVED` NTF-3 |
| пересверка `7294a684`, to_design 6 | имя `T1` занято дедлайном §8 и полосой `tasks.md` T1 — развести | дедлайны названы `CONFIG_DEADLINE_MS` и `POLL_DEADLINE_MS` (§8, прежние имена указаны в строках §8); полоса T1 `tasks.md` имени не меняет, потому что на неё ссылаются записи ревью | `grep -nE '\bT[12]\b' design.md` — каждое попадание либо называет прежнее имя как прежнее (абзацы редакций 4 и 5, строки §8, эта строка), либо полосу `tasks.md` (§11а) |
| пересверка `7294a684`, CX6-26 условия к коду | исход дедлайна — только `unreadable`; таймер ставится вызовом, кладущим `inFlight`, и снимается любым исходом; отказ после `abort()` ничего не применяет; одна константа срока | З2 п.3 «Условия к коду» | `console-config.test.ts`; рецензент диффа |
| пересверка `7294a684`, заказ автору NTF-3 | Р10 и NTF3-161: «наибольшее» в порядке позиции, позиции сценария пересекают смену числа разрядов (близнец 9 → 10) | вне замысла: предмет NTF-3; замысел держит его условием снятия Е6 (3) | заказ в возврате автора, через диспетчера |
| пересверка `7294a684`, заказ полосе E1 | префикс `notify` — в существующий location с `proxy_read_timeout`, не отдельным | З3 (перечень префиксов), З9 «Предел хвоста»; `tasks.md` E1 | рецензент диффа чарта |

Условий прежних разборов без строки здесь или в §11 нет: первичный разбор и пересверки
`7613071f`, `deeea79a` отображены §11 (пересверки `defdbe67` и `7294a684` подтвердили 25 из 25),
их условия к коду — в строках §11 и З18; условия ревью и пересверки на `defdbe67` — 12 строк
выше, плюс строка условия CX6-22 пересверки `deeea79a`; условия пересверки `7294a684` — 9 строк
(шесть `to_design`, условия к коду CX6-26, два заказа вне замысла), условия к коду CX6-27…30 —
в строках §11 и З18.

## 12. Что замысел не делает

- Не заводит поток подписки для ленты (Р4) и хранения на стороне консоли (§6).
- Не правит край, службу `notify`, её чарт и контракт — предмет NTF-1 и NTF-3; маршрут
  операций `notify` на краю — заказ Е5.
- Не правит общий клиент края `shared/src/api/client.ts` (З9): дедлайны З20 ставятся в самих
  механизмах, а не в клиенте.
- Не вводит предела времени загрузки удалённых модулей в общей фабрике `makeRemote` (M19):
  предмет — все девять обёрток, а не модуль `notify`; `rememberLoad` его не ухудшает (З14, З20).
- Не заводит экранов извещений оператора (NTF-5 Р22 — отдельная стадия после одобрения NTF-5,
  §4 приёмки).
- Не держит второго представления каталога модулей: всё, что консоль знает о модулях
  уведомлений, приходит каталогом (Р5); ручной перечень §10 — о модулях **консоли**, не о
  модулях уведомлений.

## 13. Открытые решения

Нет. Решения З1–З20 приняты (З6, З13, З14 уточнены редакцией 3; З2, З3, З9, З10, З13, З14
уточнены и З20 заведено редакцией 4; З2, З9, З10, З13, З18, З20 уточнены редакцией 5); выбор по CX6-23 сделан (вариант (а)); выбор по I1 сделан
решением Д25; зависимости Е2–Е6 — предметы соседей с названным предикатом снятия, а не
открытые решения этого замысла.
