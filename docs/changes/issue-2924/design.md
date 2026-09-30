<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2924 (NTF-5, извещения оператора) — замысел

> **Что этот документ.** Здесь технические решения, инварианты и отображение каждого пункта разбора
> классов в механизм (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2 «Truth
> ownership»: `design.md` — technical decisions, invariants, exposure mapping). Наблюдаемое
> поведение здесь не описывается и не переопределяется, его единственный владелец — приёмка.
> Порядок работ — `tasks.md` рядом.
>
> **Редакция 2 · 2026-09-30.** Вердикта на неё нет. Действующий вердикт выводится из записи ревью
> на отпечаток этого файла (`reviews/design/<role>/<sha256>.yaml`) и из пересверки разбора классов
> (`reviews/class-exposure/revalidation/<sha256>.yaml`).
>
> **Что изменено против редакции 1** (`a43a19fa`, пересверка — «к замыслу»). Три отображения
> переделаны: CX5-05 (З8 п.5: `Supersede` берёт строки по формуле «нет действующей аренды», а не по
> `lease_until IS NULL`), CX5-07 (З11: резерв окна ставится в транзакции слоя лимитов `notify`, а не
> в `Claim`; он идемпотентен по строке ленты и снимается любым исходом, кроме `SENT`), CX5-24 (З24:
> подметальщик исполняет Р14 без условия на исход; id строк ленты собираются до каскада, строки
> снимает `feed.DeleteUnleased`). Шесть новых пунктов отображены: CX5-49 (З26 — таблица «шаблон ×
> атрибут × откуда значение × законен ли нуль»; довод §0 «Д21 не касается» снят), CX5-50 (З27 —
> аренды `notify`), CX5-51 (З9 п.1, п.4 — признак «раскрытие завершено»), CX5-52 (З12 п.1 — `NULL`
> вместо пустой строки, голова нити в `Claim`), CX5-53 (З2 п.5 — `IsAnonymous`), CX5-54 (З21 п.1 —
> наблюдатель только на изменившем строку `Ack`, порядок строк счётчиков). По ходу найден пятый
> читатель срока строки ленты — условие `Claim` (З10 п.3). §3, §4, §6, §7, §11, §13 и `tasks.md`
> приведены к этим решениям. Приёмка не менялась (Д22).

## 0. Входы и на чём стоит замысел

| вход | координата | отпечаток / ревизия | состояние |
|---|---|---|---|
| приёмка NTF-5 | `docs/specs/sub-phase-NTF-5-operator-notices-acceptance.md` | `367b948297cf260266223e12c62715355435ac894789f73c998b24bc35760153` (редакция 17) | `APPROVED`, круг 16, запись `docs/specs/reviews/sub-phase-NTF-5-operator-notices-acceptance/367b9482….yaml` |
| первичный разбор, редакция 8 | `docs/changes/issue-2924/reviews/class-exposure/initial/1f4852e4….yaml` | `1f4852e4` | CX5-01…28; RA-1…RA-6 закрыты редакцией 9 |
| первичный разбор, редакция 12 | `…/initial/2fe29c35….yaml` | `2fe29c35` | CX5-29…36; RA-7…RA-9 закрыты редакциями 13–14 |
| первичный разбор, редакция 14 | `…/initial/88fabd09….yaml` | `88fabd09` | CX5-37…41; RA-10 закрыт редакцией 15 |
| первичный разбор, редакция 15 | `…/initial/03e291ee….yaml` | `03e291ee` | CX5-42…44; RA-11 закрыт редакцией 16; CX5-44 (а) снят записью на `367b9482` |
| первичный разбор, редакция 17 | `…/initial/367b9482….yaml` | `367b9482` | «к замыслу», CX5-45…48, возврата в приёмку нет (Д22) |
| пересверка на замысел, редакция 1 | `…/class-exposure/revalidation/a43a19fa….yaml` | `a43a19fa` | «к замыслу»: CX5-05, 07, 24 не выдерживали; новые CX5-49…54; возврата в приёмку нет (Д22). Закрыто редакцией 2 |
| замысел NTF-1 | `docs/changes/issue-2915/design.md` | `9bfa92be` (редакция 1, коммит `01c6ea987`) | вердикта нет; на его З8–З10 (аренда, `Ack`, уборщик ленты) стоят З8 п.5, З12 п.1, З21 п.1, З24 этого замысла — зависимость Е6 (§13) |
| дерево продукта | `PRO-Robotech/kacho` | `origin/main@1d42a6728bf` | замеры §1 — на этой ревизии, если не сказано иное |
| фундамент | `PRO-Robotech/corelib` | `origin/main@34bc8104a` (тег `v1.9.0`; последний тег `v1.10.0-rc.5`); kacho пинит `v1.8.0` | |
| служба доступа | `PRO-Robotech/kaname` | ветка эпика `origin/357@734f69fb4` | |
| соседние приёмки | `docs/specs/sub-phase-NTF-{1,2,3,4,6}-*-acceptance.md` на ветке @`04c1f8231` | NTF-1 `29cfa368` ✅, NTF-2 `ef9c6801` ✅, NTF-3 `c26cc7cc` ✅, NTF-4 `5cb8057d` — записи ревью нет, NTF-6 `47bd8b70` ✅ | см. §13 «Зависимости» |

Решения диспетчера Д1–Д22 действуют без изменений. Предмет замысла задают Д2 (звено
`service:`), Д4 (право отправки), Д6 (фундамент в corelib), Д8 (адресация), Д11 (лимиты —
поставляемые значения со стражем), Д12 (прода нет: схема сразу в итоговой форме, без обратного
заполнения), Д14 (тип справочника — в перечне без надзора), Д17 и Д18 (один внутренний слушатель
`notify-api`, маршруты края через `notifyInternal`), Д20 (методы, публичные по контракту, — и по
внешнему gRPC по перечню; одна служба и одно имя на крае; два развёртывания), Д22 (условие к коду —
в замысел). Д19 предмета NTF-5 не касается: `address.Domain` извещения не зовут. Д21 касается.
Р12 ограничивает **типы** атрибутов шаблона `obligation`, а не их обязательность. У атрибута
`endsAt` нуль законен: вид допускает извещение без `endsAt` (M21). Поэтому перечень «шаблон ×
атрибут × откуда значение × законен ли нуль» по каждому пути вызова лежит в З26 (CX5-49). Довод
редакции 1 «атрибутов с законным нулём нет» снят: он опровергнут замером пересверки на `a43a19fa`.

## 1. Замеры, на которых стоят решения

Команды исполнимы из корня рабочей копии соответствующего репозитория.

| № | утверждение | команда | результат |
|---|---|---|---|
| M1 | край открывает по одному соединению на ключ карты адресов | `git show 1d42a6728bf:gateway/cmd/api-gateway/mtls_config.go \| sed -n 60,100p`; `git show 1d42a6728bf:gateway/internal/config/config.go \| sed -n 992,1016p` | `dialBackends` зовёт `grpc.NewClient` на каждый ключ `BackendAddrs()`; ключей 14, у каждого своё поле адреса; плюс петля `operation` |
| M2 | поля адресов бэкендов края несут умолчание в теге | `git grep -nE 'VPCAddr +string' 1d42a6728bf -- gateway/internal/config/config.go` | `default:"vpc.kacho.svc:9090"`; образец, который NTF-4 Р20 для `notify` запрещает |
| M3 | проба (ii) берёт установку только из умолчаний | `git show 1d42a6728bf:gateway/cmd/api-gateway/route_wiring_parity_test.go \| sed -n 52,60p`; `git grep -nE 'func TestMain\|Setenv\(' 1d42a6728bf -- 'gateway/cmd/api-gateway/*_test.go'` | `realBackends` → `config.Load()` без `Setenv` адресов; `Setenv` в пакете — только ручки mTLS и пары носителя |
| M4 | ключ `<домен>Internal` потребляется, если маршрутизируется `<домен>` | `git show 1d42a6728bf:gateway/cmd/api-gateway/route_wiring_parity_test.go \| sed -n 173,205p` | `TestRouteWiring_EveryBackendKeyHasAConsumer` снимает суффикс `Internal` и ищет основу среди доменов перечня |
| M5 | население пробы перечня — blank-импорты, пакета `notify` нет | `git show 1d42a6728bf:gateway/internal/allowlist/parity_test.go \| grep -c '^\s*_ "'` | 11 импортов, `notify` среди них нет |
| M6 | у хранилища операций 13 экспортируемых методов, все записи — на пуле; CAS-помощники принимают `rowQuerier` и имя таблицы | `git grep -nE '^func \([a-z]+ \*?pgRepo\) [A-Z]' 34bc8104a -- 'operations/*.go' ':!*_test.go' \| wc -l`; `git show 34bc8104a:operations/repo.go \| sed -n 155,172p` | 13; `markDoneCAS(ctx, q rowQuerier, table, id string, response *anypb.Any)`; `rowQuerier` — «общий для `*pgxpool.Pool` и `pgx.Tx`» (`repo.go:158`) |
| M7 | `NewRepo` возвращает `FullRepo`; запасной принципал — в `Create` и `CreateWithPrincipal` | `git grep -n 'func NewRepo' 34bc8104a -- operations/`; `git show 34bc8104a:operations/repo.go \| sed -n 329,420p` | `repo.go:315`; `SystemPrincipal()` подставляется при пустом принципале (`:353`, `:384`); `INSERT` пишет литерал `done = false` |
| M8 | переменные уровня пакета `operations` | `git grep -nE '^var ' 34bc8104a -- 'operations/*.go' ':!*_test.go'` | `defaultRegistry = NewWorker()` (`worker.go:83`), сигнальные ошибки `ErrNotFound` (`repo.go:147`), `ErrAlreadyDone` (`:608`), `ErrWorkerStarted`, `errWorkerPanic`, утверждения типов `var _` |
| M9 | движок `Reconciler` поднимают шесть модулей; `OrphanGrace` по умолчанию 5 мин | `git grep -nE 'operations\.NewReconciler\(' 1d42a6728bf -- '*.go' ':!*_test.go' \| wc -l`; `git show 34bc8104a:operations/reconciler.go \| sed -n 90,102p` | 6; `OrphanGrace <= 0 → 5m`, `Interval <= 0 → 30s` |
| M10 | вызовов `listnarrow.New` в kacho | `git grep -nE 'listnarrow\.New\(' 1d42a6728bf -- '*.go' ':!*_test.go' \| wc -l`; то же по `'*_test.go'` | 5 в не-тестовом дереве, 4 в тестах (у модулей тестовые вызовы есть — поэтому правило «ноль в тестах» З14 заводится только для `services/notify`) |
| M11 | гейт окна отзыва: словарь ручек и перечень каталогов | `git show 1d42a6728bf:tools/revocationwindowgate/gate.go \| sed -n 170,190p`; `git show 1d42a6728bf:internal/repohygiene/revocationwindow_test.go \| sed -n 36,50p` | ручек `notify` в `knobNames` нет; каталога `services/notify/internal/config` в `revocationScanRoots` нет |
| M12 | карта носителей гейта изоляции | `git show 1d42a6728bf:deploy/scripts/assert-ban6-external-isolation.py \| sed -n 197,205p` | 7 записей (`iam`, `geo`, `nlb`, `registry`, `vpc`, `compute`, `storage`), `notify` нет |
| M13 | справочника адресов в службе доступа на ветке эпика ещё нет; кодек курсора службы — `kv1.` | `git grep -c InternalNotificationRecipientService 734f69fb4 -- proto internal \| wc -l`; `git show 734f69fb4:internal/apps/kaname/shared/visiblecursor.go \| sed -n 46,70p` | 0 (сервис заводит NTF-3 Р7); `visibleTokenPrefix = "kv1."`, `EncodeVisiblePageToken`/`DecodeVisiblePageToken` |
| M14 | надстройка над терминальной записью в службе доступа | `git grep -n 'func (r \*TerminalRefusalRepo)' 734f69fb4 -- internal/apps/kaname/shared/terminal_refusal_repo.go` | переопределяет `MarkError` (`:147`); встраивает `operations.FullRepo` (со слов разбора на `03e291ee`, перепись встраиваний) |
| M15 | префикса `ntc` в каталоге нет | `git grep -n '"ntc' 34bc8104a -- '*.go'` | 0; каталог — `hyphenFormPrefixes` (`ids/ids.go:374`) |
| M16 | строки ленты NTF-1 не удаляет — только истекает и стирает секрет | `grep -n 'уборщик (истечение' docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` | строка 942: «уборщик (истечение, стирание, возврат лимита)»; удаления строк ленты в NTF-1 нет |
| M17 | NTF-3 Р18 на `c26cc7cc` | `awk '/^\*\*Р18\./,/^\*\*Р19\./' docs/specs/sub-phase-NTF-3-kacho-modules-notifications-acceptance.md` | подлежащее «терминальная запись … ставит строку `operation-failed`» и «фундамент принимает транзакцию вызывающего либо открывает свою» не менялись (CX5-43, CX5-44 — строки диспетчеру остаются в силе) |
| M18 | лента NTF-1: «нет действующей аренды» — `lease_until IS NULL OR lease_until <= now()` в `Claim` и в уборщике; `Ack` снимает аренду при **каждом** исходе, включая `DEFER`; следствия `Ack` — только в ветке, где оператор изменил строку; `Claim` выдаёт строку только при `expires_at > now()` | `git show 01c6ea987:docs/changes/issue-2915/design.md \| grep -nE 'lease_until IS NULL OR lease_until <= now\(\)\|lease_token = NULL, lease_until = NULL\|Следствия записи'` | замысел NTF-1 `9bfa92be` (коммит `01c6ea987`), 4 строки: `Claim` — строка 319, `Ack` — 335, «следствия только на изменившей строке» — 353, уборщик — 376; условие `expires_at > now()` — в той же строке 319 |
| M19 | повтор `Ack` с тем же токеном и исходом — успех без изменения строки; срок аренды ленты 5 мин | `sed -n 962,975p docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` | NTF-1 Р8: «успех **без изменения строки**»; `feed.LeaseTTL` = 5 мин, `feed.SweepInterval` = 1 мин |
| M20 | распознаватель «принципал не называет никого» в фундаменте уже есть | `git show 34bc8104a:operations/types.go \| sed -n 69,71p`; `git show 34bc8104a:operations/owner.go \| sed -n 80,82p` | `IsAnonymous()` — `p.Type == "" \|\| p.ID == "" \|\| p.ID == AnonymousPrincipalID`; им же отсекается `Owner` в `GetOwned`/`CancelOwned` |
| M21 | `startsAt` есть у каждого извещения, `endsAt` — только у `MAINTENANCE` | `awk '/^\*\*Р4\./,/^\*\*Р5\./' docs/specs/sub-phase-NTF-5-operator-notices-acceptance.md` | `startsAt`: обязателен у `MAINTENANCE`, `DECOMMISSION`, `TERMS_CHANGE`, у трёх прочих видов его ставит сервер; `endsAt`: обязателен у `MAINTENANCE`, запрещён у пяти прочих видов. Р11: шаблонов 5 + 2 + 5 + 2 + 2 + 3 = 19 |
| M22 | NTF-1 Р7: у атрибута `presence: required \| optional`, нуль `required` — не значение, `optional` пишется только заданным | `sed -n 706,715p docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md`; `grep -n 'нулевое значение атрибута .required. — не значение' <тот же файл>` | умолчания `presence` нет; блок на атрибут `optional` несёт `when`; тема ссылается только на `required`; нулевое поле `optional` в `XAttrs` — «не задан», ключа в строке нет |
| M23 | комментарии «`NewRepo` возвращает `FullRepo`» | `git grep -n 'NewRepo' 1d42a6728bf -- services/geo/internal/apps/kacho/shared/syncop/syncop.go` (kacho); `git grep -n 'NewRepo' 734f69fb4 -- internal/apps/kaname/api/cluster/ports.go internal/apps/kaname/api/session_revocations/revoke.go` (kaname) | 3 места: `syncop.go:57`, `ports.go:30`, `revoke.go:122`; после З2 п.1 они неверны и правятся тем же изменением (C2) |

## 2. Решения

### З1. Раскладка: два развёртывания, одна база, пакеты по предмету

- `notify-api` (без секрета почты, NTF-3 Р8) обслуживает три поверхности Р2 на единственном
  слушателе носителя Х5. Use-case на метод — пакеты
  `services/notify/internal/apps/notify/api/notice/{create,get,list,update,start,complete,cancel}`
  (внутренний сервис), `…/api/publicnotice/{list,listbyaccount,get,getbyaccount}` (публичный),
  `…/api/contacts/{account,project}` (контакты; `account` заводит NTF-3, здесь дописывается).
- `notify-sender` (субъект `service:notify`) исполняет всё, что зовёт справочник или пишет строки
  доставки: `services/notify/internal/notice/admit` (заявки `Create`), `…/notice/fanout`
  (раскрытие события этапа), `…/notice/scopecache` (кэш областей), `…/notice/schedule`
  (напоминания), `…/notice/sweeper` (подметальщик), `…/notice/limits` (потолок и темп OB),
  `…/notice/thread` (заголовки нити), `…/notice/metrics` (сборщик метрик Р19).
- Правила, нужные обоим развёртываниям, — один пакет без сетевых зависимостей
  `services/notify/internal/notice/rules`: таблица видов Р4, таблица переходов Р5, таблица
  «переход × этап неотправленной строки» Р5, правило напоминаний Р5, вывод категории, перечень 18
  типов (З22). Второй копии правил ни в одном пакете нет (CX5-05 (а), CX5-18 (а)).
- Связь развёртываний — только база `kacho_notify`. Клиент службы доступа
  `services/notify/internal/clients/kaname_client.go` строится только в корне `notify-sender`;
  корень `notify-api` получает лишь клиента прав фундамента (`Check`, пакетная проверка сужателя).

### З2. Функции фундамента Ф1…Ф4 — отдельный интерфейс вне `FullRepo`

Предмет — правка corelib `operations` (своя задача corelib в эпике `PRO-Robotech/kacho#2914`,
DoD 10.1 п.2а).

1. **Интерфейс.** В пакете `operations` объявляется
   ```
   type TxWriter interface {
       CreatePendingTx(ctx context.Context, tx pgx.Tx, op Operation, p Principal) error          // Ф1
       CreateDoneTx(ctx context.Context, tx pgx.Tx, op Operation, p Principal, response *anypb.Any) error // Ф2
       MarkDoneTx(ctx context.Context, tx pgx.Tx, id string, response *anypb.Any) error          // Ф3
       MarkErrorTx(ctx context.Context, tx pgx.Tx, id string, st *status.Status) error           // Ф4
   }
   type TxRepo interface { FullRepo; TxWriter }
   ```
   `Repo` и `FullRepo` не меняются и `TxWriter` не включают (CX5-42 (а)). `NewRepo(pool, schema)`
   возвращает `TxRepo` вместо `FullRepo`: `TxRepo` включает `FullRepo`, поэтому каждое прежнее
   присваивание результата переменной, полю или параметру типа `Repo`/`FullRepo` компилируется как
   прежде, а сигнатура `NewRepo` по параметрам не меняется. Второго конструктора нет — обвязка
   NTF5-122 собирает хранилище единственным `NewRepo(pool, schema)`.
2. **Одна копия хранилища в корне.** Композиционный корень `notify-api` и `notify-sender` создаёт
   `ops := operations.NewRepo(pool, schema)` один раз и передаёт тот же `ops` обработчику
   `operationspb.Handler` (как `FullRepo`) и use-case (как `TxWriter`) (CX5-38 (в)). Типового
   утверждения к `TxWriter` у значения `Repo`/`FullRepo` нет ни в corelib, ни в `notify`
   (CX5-42 (б)): надстройка, встраивающая `FullRepo` (M14), `TxWriter` не удовлетворяет, и попытка
   подать её туда, где ждут `TxWriter`, ломает сборку.
3. **Параметр — `pgx.Tx`, имени таблицы нет.** Экспортируемые Ф1…Ф4 принимают `pgx.Tx`; пул
   (`*pgxpool.Pool`) `pgx.Tx` не удовлетворяет, и запись вне транзакции вызывающего не
   компилируется (CX5-38 (б)). Таблица — `r.tableName()` из схемы `NewRepo`, параметра `table` у
   экспортируемых функций нет (CX5-38 (а)).
4. **`nil` вместо транзакции — ошибка до первого запроса.** Каждая из Ф1…Ф4 первым оператором
   возвращает `ErrNilTx`, если `tx == nil`. Ветви «транзакции нет — открою свою» в них нет
   (CX5-43 (а)). Путь «фундамент открывает свою транзакцию», который называет NTF-3 Р18, — это
   пуловые `MarkDone`/`MarkError`, существующие методы на пуле, а не режим Ф4 (CX5-43 (б)).
5. **Тела.** Ф3 — проверка `tx == nil` и ровно один вызов `markDoneCAS(ctx, tx, r.tableName(), id,
   response)`; Ф4 — проверка и ровно один вызов `markErrorCAS(ctx, tx, r.tableName(), id, st)`
   (CX5-44 (б)). Тела `markDoneCAS` и `markErrorCAS` правкой **не меняются** (CX5-47 (б)).
   `markDoneWithMetadataCAS` не экспортируется. Ф1 и Ф2 — проверка `tx == nil`, проверка
   принципала, затем общий неэкспортируемый построитель
   `insertOperationTx(ctx, tx, table, op, p, done, response)`. **Проверка принципала — единственный
   распознаватель пакета `p.IsAnonymous()`** (M20; CX5-53): `true` → `ErrEmptyPrincipal`, без
   подстановки `SystemPrincipal`. Сравнения с `Principal{}` в Ф1, Ф2 и построителе нет. Так
   отвергаются и частичная пара (`{Type: "user", ID: ""}`, пара с одним `DisplayName`), и
   зарезервированное слово (`{system, anonymous}`) — все они иначе записали бы операцию, которую
   `GetOwned`/`CancelOwned` отсекают для любого вызывающего. Явный `{system, bootstrap}` проходит:
   `IsAnonymous` его не включает. `AnonymousPrincipalID` — константа, а не переменная пакета, и
   гейт замыкания п.7 её не судит.
   Построитель запасного принципала не содержит; `Create`/`CreateWithPrincipal` сохраняют свой
   запасной путь и зовут построитель на пуле, уже подставив принципал (CX5-38 (г)). Ф2 пишет
   `done = true` и столбцы ответа в той же вставке — «рождённая завершённой».
6. **Замыкание Ф1…Ф4 без настройки мимо хранилища (CX5-47 (а)).** Ф1…Ф4 и каждая функция пакета,
   которую они вызывают (`Principal.IsAnonymous`, `markDoneCAS`, `markErrorCAS`, `insertOperationTx`,
   `marshalAny`, `marshalStatus`, `resolveResourceID`, `extractResourceID`, `extractAccountID`,
   `nullableString`), не читают переменных уровня пакета, кроме сигнальных ошибок (`ErrNotFound`,
   `ErrAlreadyDone`, `ErrNilTx`, `ErrEmptyPrincipal`), не зовут `ctx.Value` ни прямо, ни через
   `*FromContext`, не читают окружение процесса. Из полей хранилища они читают только `schema`,
   и только через `tableName()`; `pool` им не нужен. Чтение реестра типов protobuf внутри
   `UnmarshalNew` (`extractResourceID`, `extractAccountID`) — глобальное состояние чужого пакета,
   а не настройка хранилища: писателя или флага через него не передать, и под запрет (а) оно не
   подпадает.
7. **Держатель замыкания — гейт corelib** (CX5-47 (в)): `operations/txwriter_closure_test.go`
   строит граф вызовов внутри пакета от Ф1…Ф4 по `go/types` (узел — объект функции, не имя) и
   печатает число разобранных функций. Находка — ссылка на переменную уровня пакета вне перечня
   сигнальных ошибок, вызов метода `Value` у `context.Context`, вызов функции пакета с суффиксом
   `FromContext`, вызов `os.Getenv`/`os.LookupEnv`/`os.Environ`. Близнецы: на теге правки гейт
   молчит; инъекция чтения `defaultRegistry` в `markErrorCAS` — красный с именем функции; инъекция
   `PrincipalFromContext(ctx)` в `insertOperationTx` — красный с именем функции; пустой обход
   (ноль функций) — красный.
8. **Перепись входов хранилища DoD 10.1 п.2а (б)** на теге правки перечисляет `NewRepo` (возвращает
   `TxRepo`, объявляющий Ф1…Ф4; параметры `*pgxpool.Pool`, `string`) и 17 экспортируемых методов
   (13 прежних и Ф1…Ф4) со всеми параметрами из допустимого набора. `AsOwned` возвращает
   `OwnedOperationRepo`, который Ф1…Ф4 не объявляет, и в перепись не входит.
9. **Ф4 общая с NTF-3 Р18.** Если правка NTF-3 сядет в corelib первой и заведёт функцию
   терминальной записи ошибки на транзакции, эта правка её не дублирует, а приводит к пп.1–6
   (имя, место в `TxWriter`, тело из одного вызова). Строку `operation-failed` ставит вызывающий
   Ф4 (исполнитель, `Reconciler`) своей записью в ту же транзакцию, а не Ф4 (Р23). Перевод
   исполнителя фундамента на Ф4 требует, чтобы служба доступа подала исполнителю `TxWriter`
   с тем же выбором текста отказа, что у её надстройки над `MarkError` (M14); это предмет NTF-3 и
   строка диспетчеру (CX5-42 (в), §13).

### З3. Заявка `Create` и её проверка у владельца

1. **Приём (`notify-api`).** Проверки Р4 и Р10 синхронно, до записи, в порядке Р4. Момент приёма —
   часы `notify` (порт часов), усечённый до секунды **один раз** и записанный в заявку (CX5-26).
   Одна транзакция на `READ COMMITTED`: строка `notice_create_requests` и Ф1 с принципалом
   trust-aware пары (З17); id операции — `ids.NewID` с приставкой `nop` из каталога префиксов
   операций (Х1 NTF-4), `metadata.noticeId` — уже отчеканенный `ntc-…`.
2. **Взятие (`notify-sender`, шаг 2) — аренда, а не удержание транзакции** (CX5-08 (б)). Короткая
   транзакция `UPDATE notice_create_requests SET lease_token = gen_random_uuid(), lease_until =
   $now + $lease WHERE notice_id = (SELECT notice_id FROM notice_create_requests WHERE <аренда
   свободна> ORDER BY accepted_at, notice_id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING notice_id,
   lease_token, …`. Условие «аренда свободна», токен и часы — З27, одни на три аренды `notify`
   (CX5-50). Заявка вставляется `notify-api` без аренды (`lease_token`, `lease_until` — `NULL`), и
   первое же взятие её видит. Сетевые вызовы идут вне транзакций записи, аренда не даёт второй
   реплике взять ту же заявку.
3. **`done` операции читается через хранилище фундамента, а не SQL `notify`.** DoD 10.1 п.2а
   допускает в пакете `operations` ровно четыре функции с `pgx.Tx`, а в `services/notify` нет SQL
   к таблице операций, поэтому `done` читается `ops.Get(ctx, opID)` на пуле. Это равносильно чтению
   в транзакции взятия: `done = true` необратимо, и увиденное `true` остаётся верным при любом
   последующем порядке. Ветка `done = true` — одна запись
   `DELETE FROM notice_create_requests WHERE notice_id = $1 AND lease_token = $T` без вызова
   справочника; ветка `done = false` — `DescribeScope` на каждую область заявки, мимо кэша, и
   пополнение кэша (З9).
4. **Окно проверки судится в начале каждой попытки и перед фиксацией** (CX5-08 (в)): если
   `now − accepted_at > KACHO_NOTIFY_NOTICE_CREATE_VALIDATION_WINDOW`, фиксация не выполняется —
   исполняется шаг 5 (терминальный отказ `UNAVAILABLE`/`PEER_UNAVAILABLE`). Ответ `DescribeScope`,
   полученный после истечения окна, извещения не создаёт.
5. **Фиксация (шаг 3)** — одна транзакция `READ COMMITTED`: `DELETE … WHERE notice_id = $1 AND
   lease_token = $T RETURNING` (снятие заявки, 0 строк — откат, заявку увела другая реплика
   после истечения аренды), вставка извещения, аудитории, затронутых ресурсов, события этапа
   создания (З6), напоминаний (З7), затем Ф3. `ErrAlreadyDone`/`ErrNotFound` Ф3 — откат **всей**
   транзакции; заявку снимет следующее взятие веткой `done = true`. Уникальность `notices.id`
   держит повторную фиксацию.
6. **Терминальный отказ (шаги 4, 5)** — одна транзакция: снятие заявки и Ф4 с `FAILED_PRECONDITION`
   + `PEER_RESOURCE_MISSING` первой несуществующей области в порядке запроса (шаг 4) либо
   `UNAVAILABLE` + `PEER_UNAVAILABLE` (шаг 5). `ErrAlreadyDone` Ф4 — откат целиком.
7. **Классификатор отказа `DescribeScope`/`ListAccounts` — своя функция** (CX5-08 (а)):
   `classifyScopeCallRefusal(err) scopeRefusal` с исчерпывающим `switch` по 16 кодам и «`OK` без
   поля `exists`» — `pause` (первая строка шага 5) либо `pauseMisconfigured` (вторая строка, сигнал
   и счётчик `notify_recipient_directory_refused_total{ns="notify",code}`, метка
   `code="UnknownOutcome"` у «`OK` без поля»). Ветки «прочее» нет: `switch` перечисляет все 16
   кодов отказа и `OK`; ветка `default` принимает только значения вне `0…16`, которых протокол не
   производит, и относит их ко второй строке с числом кода в метке — законный код в неё не попадает.
   Держатель полноты — модульная проба, перебирающая `codes.Code` от
   0 до 16 и сверяющая строку каждого кода с таблицей Р10 шаг 5 (линтера исчерпывающего `switch`
   в `.golangci.yml` kacho @`1d42a6728bf` нет, `grep -c exhaustive` → 0). Классификатор `Resolve` —
   классификатор NTF-3 Р7 без изменений, **другая**
   функция; сведения двух таблиц в одну нет: клетка `INVALID_ARGUMENT` у них разная.
8. **Форма ответа `DescribeScope` проверяется до кэша** (CX5-09): поле `exists` объявлено
   `optional bool` (§5), отсутствие — `pauseMisconfigured`; `exists = true` с пустым `accountId`
   или `ownerUserId` и `exists = false` с непустым полем — тоже `pauseMisconfigured`, в кэш не
   пишутся.

### З4. Движок `Reconciler` в `notify` не поднимается

Решение CX5-35 (в): ни `notify-api`, ни `notify-sender` не зовут `operations.NewReconciler`.
Осиротевшей операции `nop` не бывает по построению: `Create` пишет заявку и Ф1 одной транзакцией,
и заявку снимает только транзакция, которая той же записью завершает операцию (шаги 3–5), либо
взятие при уже завершённой операции (шаг 2, `done = true`). Операции переходов и контактов
рождаются завершёнными (Ф2). Операции `nop` NTF-4 (`InternalSuppressionService`) движка тоже не
требуют — NTF-4 и NTF-1 его не называют (`grep -ciE 'reconciler|OrphanGrace'` по приёмкам NTF-1
и NTF-4 на ветке @`04c1f8231` → 0 и 0).
Держатель — предикат DoD маршрута: `git grep -nE 'operations\.NewReconciler\(' -- 'services/notify/*.go'
':!*_test.go' | wc -l` → 0, печатается вместе с числом обойдённых файлов. Если соседняя
под-фаза поднимет движок над таблицей операций `notify`, её доменный `Resolver` обязан отвечать
`OutcomeSkip` на операцию с живой строкой `notice_create_requests`, а `OrphanGrace` задаётся явно
и не короче верхней границы окна `1h` (CX5-35 (б)) — строка в задачу той под-фазы (§13).

### З5. Переходы — одна запись с условием, классификация отказа после нуля строк

1. `Start`/`Complete`/`Cancel`: одна транзакция `READ COMMITTED`,
   `UPDATE notices SET state = $to, <момент> = $now, updated_at = $now WHERE id = $1 AND state =
   $from AND kind = ANY($allowed) RETURNING …`. Состояние до записи не читается (CX5-03 (а)).
2. Ноль строк → чтение той же транзакцией **после** оператора: строки нет — `NOT_FOUND`; вид не
   поддерживает глагол — `"Notice <id> of kind <KIND> does not support <Verb>"`; иначе —
   `"Notice <id> is <STATE>, expected <EXPECTED>"` с фактическим состоянием. Порядок «вид раньше
   состояния» — один для всех пяти глаголов, из таблицы `rules` (CX5-03 (б), (г)). `Operation` не
   создаётся, транзакция откатывается.
3. Одна затронутая строка → в той же транзакции: закрытие событий и неотправленных строк по таблице
   Р5 (З6, З8), снятие или пересчёт напоминаний (З7), новое событие этапа с письмом, Ф2
   (CX5-03 (в)).
4. `Update`: неизменяемые поля маски проверяются до `corevalidate.UpdateMask`; вид перехода
   проверяется записью; `UPDATE notices SET starts_at = COALESCE($s, starts_at), ends_at =
   COALESCE($e, ends_at), revision = revision + 1, updated_at = $now WHERE id = $1 AND state =
   'SCHEDULED' AND kind = ANY($allowed) AND (starts_at, ends_at) IS DISTINCT FROM (COALESCE($s,
   starts_at), COALESCE($e, ends_at)) RETURNING revision`. Ноль строк → чтение после оператора:
   состояние и вид годны и значения совпали — успех без изменения ревизии и без события (Ф2 пишет
   операцию); иначе — отказ п.2 (CX5-04 (б)).
5. Согласованность моментов и допустимость полей по виду — ограничения `CHECK` таблицы `notices`
   (§6); каждое ограничение имеет имя, и единственный дом отображения SQLSTATE службы переводит
   `23514` с этим именем в закрытый текст Р4 (`"endsAt: must be after startsAt"` и др.). Правка
   маской только `endsAt` раньше хранимого `startsAt` отвергается ограничением, а не сравнением в
   Go (CX5-04 (а), (в)). `"startsAt: must be in the future"` судится часами `notify` до записи —
   `CHECK` не может читать часы. До записи читается только неизменяемое (CX5-04 (г)): вид в `Update`
   не читается вовсе — он в условии записи.

### З6. Событие этапа — строка, за которую спорят переход, раскрытие и планировщик

1. Транзакция перехода (либо фиксации `Create`, либо планировщика) пишет строку
   `notice_stage_events (id, notice_id, stage, revision, due_at NOT NULL, audience-снимок, cursor,
   closed_at NULL)` с уникальностью `(notice_id, stage, revision, due_at)` (CX5-23). `due_at` у
   этапов, кроме `reminder`, — `now` часов `notify` этой транзакции, у `reminder` — назначенный
   момент. Раскрытие и отправка берут `due_at` только из этой строки и часов для ключей строк не
   зовут (CX5-02). Сетевых вызовов в транзакции перехода нет.
2. **Порядок блокировок (CX5-29).** Каждая транзакция, изменяющая набор строк события,
   первым оператором блокирует общую строку:
   - переход — `UPDATE notices … WHERE …` (блокировка строки извещения), затем
     `UPDATE notice_stage_events SET closed_at = $now WHERE notice_id = $1 AND closed_at IS NULL AND
     <этап по таблице Р5>`, затем закрытие неотправленных строк этих событий (З8 п.5);
   - планировщик — `SELECT 1 FROM notices WHERE id = $1 AND state = 'SCHEDULED' AND revision = $r
     FOR SHARE`, затем `DELETE FROM notice_reminders … RETURNING` (З7); 0 строк на любом шаге —
     откат без события;
   - страница раскрытия — `SELECT 1 FROM notice_stage_events WHERE id = $1 AND closed_at IS NULL
     AND fanned_out_at IS NULL AND lease_token = $T FOR SHARE` (аренда события — З27), повтор
     отложенной строки кандидата — `SELECT 1 FROM notice_stage_events WHERE id = $1 AND closed_at
     IS NULL FOR SHARE` плюс `lease_token = $T` строки кандидата в записи; 0 строк — откат без записи;
   - подметальщик — `SELECT … FROM notices … FOR UPDATE SKIP LOCKED`, затем `SELECT … FROM
     notice_stage_events WHERE notice_id = ANY($ids) ORDER BY id FOR UPDATE` (З24): тот же порядок
     «извещение → события», что у перехода; раскрытие, ждущее его, после фиксации находит 0 строк и
     откатывается.
   Переход, ждущий `FOR SHARE` раскрытия, после его фиксации исполняет следующие операторы на
   свежем снимке `READ COMMITTED` и видит строки, записанные раскрытием, — закрывает и их.
   Раскрытие, ждущее перехода, после его фиксации находит `closed_at IS NOT NULL` и откатывается.
3. Закрытое событие раскрытием больше не берётся и в `notify_notice_fanout_pending` не входит
   (Р5, Р19).

### З7. Напоминания — одна функция правила, планировщик снимает строку записью

1. `rules.Reminders(kind, startsAt, now, lead) []time.Time` — единственная реализация правила Р5
   (`MAINTENANCE` — одно в `startsAt − lead`; `DECOMMISSION` — `−30d`, `−7d`, `−1d`; прошедшие к
   `now` моменты не назначаются). Её зовут фиксация `Create` в `notify-sender` и `Update` в
   `notify-api` (CX5-18 (а)); обе читают `KACHO_NOTIFY_NOTICE_REMINDER_LEAD` (З20).
2. Назначенное напоминание — строка `notice_reminders (notice_id, revision, at)` с PK
   `(notice_id, at)`. `Update` удаляет несостоявшиеся и вставляет пересчитанные в своей
   транзакции; `Start`, `Cancel`, `Complete` удаляют их.
3. Планировщик (`notify-sender`) в момент `at` берёт строку `DELETE FROM notice_reminders WHERE
   notice_id = $1 AND at = $2 AND revision = $3 RETURNING` под блокировкой З6 п.2; событие
   `reminder` пишется, только если удалена ровно одна строка (CX5-29 (в)).
4. Поле `reminders` внутренней проекции читает эти строки в порядке `at` по возрастанию.

### З8. Строки события этапа — две таблицы, у каждой свой ключ и свой путь

1. **Строка адресата** — строка собственной ленты `notify` (NTF-3 Р19; производитель —
   `feed.Put` corelib в транзакции раскрытия) плюс строка `notice_addressees (id, event_id,
   subject, scope, feed_row_id UNIQUE)` с уникальностью `(event_id, subject)` (CX5-01 (а)).
   Вставка — `INSERT … ON CONFLICT (event_id, subject) DO NOTHING RETURNING id`; строка ленты
   ставится той же транзакцией, **только если** вставка вернула строку. `id` строки адресата —
   непрозрачный ключ `Message-ID` (З12). Инвариант «одно письмо на субъекта» стоит на этой
   уникальности и больше ни на чём.
2. **Строка кандидата** — `notice_candidates (event_id, subject, scope, chain_pos, outcome,
   next_attempt_at, lease_token, lease_until)` с уникальностью `(event_id, subject, scope)`
   (CX5-01 (а), CX5-30 (а)). Это отдельная таблица: предикат взятия конвейера отправки её не видит,
   строки без адресата конвейер не получает никогда. `CHECK` закрывает набор исходов клетками NTF-3
   Р24, `INVALID` и `DEFER(platform_unavailable)`; `next_attempt_at` задан тогда и только тогда,
   когда исход — `DEFER`.
3. **Повтор отложенной строки кандидата** — путь раскрытия со своей арендой, не конвейер (CX5-30
   (б)). Исход `ADDRESS` повтора — одна транзакция: вставка строки адресата «если нет» (п.1) и
   удаление строки кандидата (CX5-30 (в)). Терминальный исход — строка кандидата получает его, и
   раскрытие продолжает цепочку с `chain_pos + 1`.
4. **Исход области фиксируется один раз.** `notice_scope_outcomes (event_id, scope, outcome)` с
   уникальностью `(event_id, scope)`, `outcome ∈ {ADDRESSED, UNADDRESSED}`; вставка «если нет» в
   той же транзакции, что последняя строка цепочки области. Счётчик
   `notify_notice_unaddressed_total{kind,stage}` увеличивается в той же транзакции записью в
   таблицу счётчиков (З21), только если вставка вернула строку: повтор страницы после отказа его не
   удваивает (CX5-12 (б)). Область, остановленная терминальным `INVALID` первого кандидата, — тоже
   `UNADDRESSED`.
5. **Закрытие неотправленных строк переходом** — одним оператором по таблице Р5 из `rules` (одно
   место в коде, CX5-05 (а), (б)): строки кандидатов закрытых событий — `DELETE`, строки ленты —
   функцией corelib `feed.Supersede(ctx, tx, ids)`, которая ставит исход `SUPERSEDED` только
   строкам `pending` **без действующей аренды** и возвращает закрытые. Строка, уже взятая конвейером
   и ещё не получившая исхода, доходит до своего исхода (CX5-05 (в)).
   - **«Нет действующей аренды» — одна формула ленты, та же, что у `Claim` и уборщика NTF-1**:
     `(lease_until IS NULL OR lease_until <= now())` по часам базы (M18). `feed` объявляет её
     один раз фрагментом `feed.NoActiveLease(alias string) string`, и его подставляют `Claim`,
     уборщик, `Supersede`, `DeleteUnleased` (З24) и голова нити (З12 п.1). Предиката
     `lease_until IS NULL` в `feed` нет.
   - Почему этого достаточно для отложенной строки: `Ack` снимает аренду при **каждом** исходе,
     включая `DEFER` (M18), поэтому строка, забранная и отложенная потолком, темпом или
     недоступностью, стоит с `lease_until = NULL` и закрывается. Строка, чей держатель упал без
     `Ack`, закрывается после конца аренды — не позже `feed.LeaseTTL` после взятия, — а до того её
     `Ack` ещё возможен, и она «взята на отправку» в смысле Р5.
   - `Supersede` берёт строки `WITH c AS (SELECT id … WHERE id = ANY($ids) AND state = 'pending'
     AND <NoActiveLease> ORDER BY id FOR UPDATE) UPDATE …` — порядок блокировки по `id`.
   - Та же транзакция перехода снимает резервы окна OB у закрытых строк (З11 п.1) и последним
     оператором увеличивает счётчик `SUPERSEDED` (З21 п.1).
   Писатель исхода строки ленты — только пакет `feed`: `notify-api` пишет исход через него, своего
   SQL к таблице ленты у `notify` нет.
6. **Счётчики этапа по исходу** (Р18, Р19) читают вид строки по таблице, а не по полям (CX5-30
   (г)): у субъекта, закрытого по `A1` и ставшего адресатом по `A2`, — одна строка кандидата
   (`DENIED`) и одна строка адресата (`SENT`).

### З9. Раскрытие: области, страницы `allAccounts`, кэш областей

1. Области `accountIds`/`projectIds` раскрываются по одной; позиция — `scope_done`, индекс
   последней завершённой области в строке события. `allAccounts` — страницами
   `ListAccounts{page_size = 100}`; позиция — `page_token` последней страницы, чьи строки
   записаны. **Начальная позиция выражена отдельно от любой законной** (CX5-51 (б)): `scope_done
   IS NULL` — «ни одна область не завершена» (законные значения — `≥ 0`, `CHECK`); `page_token IS
   NULL` — «страниц не было» (`CHECK (page_token IS NULL OR page_token <> '')`: пустая строка не
   пишется).
2. **Страница — одна транзакция после всех вызовов** (CX5-12 (а)): вызовы `ListAccounts`,
   `DescribeScope` (промах кэша), `Resolve` идут вне транзакции под арендой события; затем одна
   транзакция: блокировка события (З6 п.2), строки адресатов и кандидатов страницы, исходы
   областей, продвижение позиции. Отказ любого вызова — транзакции нет, позиция прежняя, повтор
   запрашивает ту же страницу тем же курсором; уже полученные ответы `DescribeScope` берутся из
   кэша (CX5-12 (в)).
3. **Кэш областей** — `notice_scope_cache (scope_type, scope_id, account_id, owner_user_id)`,
   PK `(scope_type, scope_id)`, `CHECK (account_id <> '' AND owner_user_id <> '')`; пишется только
   ответ `exists = true` с обоими полями (CX5-10 (а)); записи без срока. Опора — неизменяемость
   `owner_user_id` и `account_id` проекта в службе доступа; её держит ограничение базы службы
   доступа (З23 п.4, CX5-10 (в)), и ребро `notify → kaname` в таблице спеки называет опору
   (CX5-10 (б), §9).
4. **Окончание — отдельный признак `fanned_out_at`** (CX5-51 (а)). Транзакция последней страницы
   (ответ `ListAccounts` с пустым `next_page_token`) либо последней области ставит `fanned_out_at =
   $now` в той же записи, что строки страницы. Позиция после этого не меняется и не читается.
   `fanned_out_at` не совпадает с `closed_at`: `closed_at` ставит только переход (З6 п.2), и по нему
   переход находит события, чьи неотправленные строки закрывает (З8 п.5). Раскрытие `closed_at` не
   пишет никогда. Взятие события раскрытием — `closed_at IS NULL AND fanned_out_at IS NULL AND
   due_at <= $now AND <аренда свободна>` (З27); метрика `notify_notice_fanout_pending` считает
   события `closed_at IS NULL AND fanned_out_at IS NULL`. Повтор отложенной строки кандидата
   (З8 п.3) идёт своим путём по строке кандидата и от `fanned_out_at` не зависит.

### З10. Класс `obligation` в фундаменте: без срока, валидатор один

1. `corelib/notify/spec` (единый валидатор, `PRO-Robotech/corelib#77`): класс `obligation` —
   только у владельца `notify`; атрибуты — только `timestamp` и `path`; ключи `ttl` и `limits`
   запрещены (Р12). Владелец шаблона — **ключ ведомости источников сборки** (NTF-3 sources), а не
   сегмент пути `<owner>/notifications/` (CX5-20). Проба-инъекция — вложенный каталог
   `…/notify/notifications/<шаблон obligation>/` у чужого источника: отказ сборки с именем
   владельца-источника.
2. `corelib/notify/feed`: столбец `expires_at` допускает `NULL`; `CHECK ((expires_at IS NULL) =
   (class = 'obligation'))` — строка `obligation` срока не имеет, строка `security`/`notice` без
   срока невыразима (CX5-31 (б)). В Go поле — `*time.Time` (признак присутствия), не `time.Time`
   (CX5-31 (а)). Срок строки берётся только из ведомости сборки (CX5-31 (г)).
3. **Перепись читателей срока** (CX5-31 (в)). По приёмке NTF-1 читателей четыре: сверка срока перед
   `DATA`, уборщик, окно Р14 «источник недоступен до `expires_at`», тревога «половина наименьшего
   `ttl`». Каждый получает явную ветку `NULL`: сверки нет, уборщик строку не истекает, окно Р14 у
   строки без срока — «пока строка не закрыта», тревога по `ttl` класс `obligation` не видит (его
   видит тревога Р19 по возрасту, З21). Перепись на дереве повторяется в полосе F3 командой
   `git grep -nE 'expires_at|ExpiresAt' -- 'notify/**' 'services/notify/**'` с напечатанным
   числом попаданий; каждое попадание — строка таблицы «читатель → ветка `NULL`» в описании PR.
   Близнец — NTF5-116 (строка `notice` с `ttl: 24h` истекает, строка `obligation` за 30 суток — нет).
   **Пятый читатель — условие `Claim`**, которого приёмка NTF-1 не перечисляет: `expires_at >
   now()` в операторе взятия (M18, замысел NTF-1 З8). На `NULL` оно даёт `NULL`, и строку
   `obligation` не выдал бы ни один `Claim` — письмо не ушло бы никогда. Ветка `NULL` у него —
   `(expires_at IS NULL OR expires_at > now())`; проба C5 «строка `obligation` без срока выдаётся
   `Claim`» с близнецом «строка `notice` с истёкшим сроком не выдаётся». Перепись командой выше
   его находит: строка входит в таблицу «читатель → ветка `NULL`» пятой.
4. Тоже правки этого пакета, и второго писателя таблицы ленты нет: `feed.NoActiveLease`,
   `feed.Supersede` (З8 п.5), `feed.DeleteUnleased` (З24), столбец `thread_key` и условие головы
   нити в `Claim` (З12 п.1), порт `feed.OutcomeObserver` сервера ленты, который `Ack` зовёт в ветке,
   изменившей строку (З21 п.1).

### З11. Потолок и темп OB — в базе, атомарно

1. **Где стоит резерв.** Не в `Claim`: `Claim` — транзакция сервера ленты corelib, и лимитов OB она
   не знает. Слой лимитов `notice/limits` исполняется в `notify-sender` после `Claim` и до рендера и
   `MAIL FROM` (§7), своей короткой транзакцией в `kacho_notify`, под арендой строки ленты. Потолок
   (CX5-07 (а)) и темп (CX5-07 (б)) решаются в **одной** транзакции, в таком порядке:
   1. `pg_advisory_xact_lock(hashtext($h))`, `$h` — ключевой хеш адреса (тот же ключ, что у сетки
      NTF-1, Р10);
   2. есть ли уже резерв этой строки — `SELECT 1 FROM notice_ob_address_window WHERE feed_row_id =
      $id`. Есть — место не проверяется: оно уже занято этой строкой (строка взята снова после
      потери аренды);
   3. нет — `SELECT count(*) … WHERE address_hash = $h AND reserved_at > $now − 24h`; число
      `≥ $limit` — транзакция откатывается, исход `DEFER(ob_address_ceiling)`;
   4. жетон ведра — `UPDATE notice_ob_stream_bucket SET tokens = <пополнено> − 1, refilled_at = $now
      WHERE id = 1 AND <пополнено> ≥ 1 RETURNING`, пополнение — по часам `notify` в том же
      операторе. Ноль строк — откат, исход `DEFER(ob_stream_pace)`;
   5. резерв — `INSERT INTO notice_ob_address_window (feed_row_id, address_hash, reserved_at)
      VALUES ($id, $h, $now) ON CONFLICT (feed_row_id) DO NOTHING`.

   Откат на шагах 3 и 4 не оставляет нового резерва. Повторная вставка того же `feed_row_id` —
   `DO NOTHING`, а не `23505`: строка, взятая снова, проходит (CX5-07 (в), Р15). Ограничителя в
   памяти процесса нет: темп — на установку, а не на реплику.
2. **Снятие резерва — любым исходом, кроме `SENT`** (CX5-07 (в)). Исход строки пишет `Ack`, и в его
   транзакции, в ветке, изменившей строку, наблюдатель `notify` (З21 п.1) делает одно из двух:
   `SENT` — `UPDATE notice_ob_address_window SET sent_at = $now WHERE feed_row_id = $id` (резерв
   становится записью окна); любой иной исход, включая `DEFER` любой причины, — `DELETE … WHERE
   feed_row_id = $id`. Строки, закрытые мимо `Ack`, снимают резерв той же транзакцией, что их
   закрывает: `Supersede` — транзакция перехода (З8 п.5), `DeleteUnleased` — транзакция
   подметальщика (З24). Строку ленты `obligation` уборщик не истекает (З10 п.3), поэтому третьего
   пути закрытия нет. Резерв строки, чей держатель упал без `Ack`, остаётся, и следующее взятие той
   же строки его переиспользует (п.1, шаг 2); строка `obligation` берётся снова, пока не получит
   исхода, поэтому резерв без строки не повисает.
3. **Отсрочка.** `defer_for` исхода `DEFER(ob_address_ceiling)` — время до выхода из окна
   старейшего резерва адреса, `DEFER(ob_stream_pace)` — время до следующего жетона; оба
   ограничены сверху `feed.MaxDefer` (15 мин, замысел NTF-1 З23). Строка, отложенная дольше, чем
   на `MaxDefer`, берётся снова и откладывается снова — это не потеря.
4. Записи окна старше 24 ч с `sent_at IS NOT NULL` снимает тот же слой лимитов пачкой; в счёт
   потолка они уже не входят.
3. Потолок `obligation` не расходует сетку NTF-1 Р10 и ею не расходуется: у ведра и окна свои
   таблицы, у сетки — свои.

### З12. Нить: одна строка извещения на субъекта в полёте, корень — первая `SENT`

1. У строки ленты появляется необязательный столбец `thread_key` (`feed`, З10 п.4); строка
   адресата извещения несёт `thread_key = <noticeId>/<subject>`.
   - **Отсутствие ключа — `NULL`, одно написание** (CX5-52 (а)): `CHECK (thread_key IS NULL OR
     thread_key <> '')`; в Go — `*string` в параметрах `Put` и в строке ответа `Claim`, а не
     `string`. Строки других источников и классов ключа не несут и пишутся `NULL`.
   - **Условие в `Claim` — голова нити** (CX5-19 (а), CX5-52 (б)): строка с ключом выдаётся, только
     если в ленте нет другой строки того же ключа, которая либо под действующей арендой, либо
     `pending` и стоит раньше в порядке взятия:
     `AND (t.thread_key IS NULL OR NOT EXISTS (SELECT 1 FROM <лента> o WHERE o.thread_key =
     t.thread_key AND o.id <> t.id AND o.state = 'pending' AND (NOT <NoActiveLease(o)> OR
     (o.enqueued_at, o.id) < (t.enqueued_at, t.id))))`. Аренда — та же формула
     `feed.NoActiveLease`, что у уборщика (З8 п.5). Так в полёте не больше одной строки пары и в
     разных `Claim`, и в одном: вторая строка той же нити в пачке не голова. Строка без ключа
     условием не задета. Строка не головы исхода не получает и берётся позже — нового исхода в
     словаре нет. Частичный индекс `(thread_key, enqueued_at, id) WHERE state = 'pending' AND
     thread_key IS NOT NULL`.
   - Правка `Claim` — правка сервера ленты corelib, отдельная строка §4 (CX5-52 (в)).
2. `Message-ID` = `<ntc-…-<stage>-<revision>.<id строки адресата>@<домен отправителя>>` (Р13);
   ключ — непрозрачный id строки `notice_addressees`, без адреса и id субъекта (CX5-19 (в)).
3. Корень — при рендере выбирается `notice_addressees` того же `(notice, subject)` с наименьшим
   `sent_at`. `notice_addressees.sent_at` ставит наблюдатель исхода в транзакции `Ack` `SENT`
   (З21 п.1), поэтому SQL `notify` к таблице ленты для выбора корня не нужен. При п.1 одновременно в
   полёте одна строка пары, и
   корень, увиденный при рендере, не меняется до исхода этой строки (CX5-19 (б)). Отдельной
   таблицы корней нет.
4. Заголовки строит порт `thread.Headers(row)` пакета `notice/thread`, который рендер конвейера
   `notify` зовёт для строк пространства `notify` класса `obligation`.

### З13. Публичное чтение — одна выборка, один отказ, один кодек

1. `Get`/`GetByAccount` — одна выборка с предикатом видимости Р16 в `WHERE` (аудитория `P` либо
   `allAccounts` для проекта; `A`, проект с записанным аккаунтом `A`, либо `allAccounts` для
   аккаунта). Ноль строк — один конструктор ошибки `"Notice <id> not found"` с `reason =
   RESOURCE_NOT_FOUND` (CX5-15). Заявка создания этой выборкой не видна: она в другой таблице.
2. Три списка (`List`, `ListByAccount`, внутренний `List`) — keyset `(created_at, id)` по индексу
   таблицы `notices`; видимость — `EXISTS` по индексу `notice_audience (scope_type, scope_id)` и
   `(account_id)`; курсор — общий кодек страниц kacho, третьей формы нет (CX5-16 (а), (б)). Разбор
   `pageToken`/`pageSize` — первым оператором той же функции use-case, что замыкается, до `Check`
   (CX5-16 (в)); гейты `TestEveryCursorPageReadGetsItsOrderFromAnIndex`,
   `TestPageCursorFormIsDeclaredOnce`, `TestEmptyPageNeverPrecedesPaginationValidation` видят новые
   пакеты без правки.
3. Сужение `affectedResources` — `Narrower.Visible` на каждый различный тип ссылок (CX5-14 (б));
   самодельного клиента `BatchCheck` нет (CX5-14 (а)); `SoftPassOnPeerFailure = false`,
   `Breakglass = false` (CX5-14 (в)). Ссылка остаётся, если её `id` есть в выдаче её типа.
4. **Повтор ссылки** (CX5-14 (г)): `Create` хранит ссылки как прислано, включая повтор, в заданном
   порядке (`notice_affected_resources` с PK `(notice_id, ordinal)`). Отказа на повтор нет: текст
   такого отказа вне закрытого перечня Р4, а новый отказ — наблюдаемое поведение, которого
   приёмка не утверждает. Схлопывания нет: `Visible` схлопывает только свой ответ, а фильтр по
   членству проверяет каждую ссылку, поэтому внутренняя и публичная проекции на повторе не
   расходятся.

### З14. Сужатель `notify-api` — одна функция сборки, окно из ручки, верх из потолка политики

1. `services/notify/internal/apps/notify/authzwiring.NewListNarrower(cfg config.ListFilter, clk
   clock.Clock) (*listnarrow.Narrower, error)` — единственное место вызова `listnarrow.New` в
   не-тестовом дереве `services/notify`; её зовут `main` (`time.Now`) и обвязка (управляемые часы).
   В тестах `services/notify` вызовов `listnarrow.New` ноль (CX5-41 (а), (б)); предикат —
   `git grep -c 'listnarrow\.New(' -- 'services/notify/*.go'` по двум срезам (не-тесты → 1,
   тесты → 0). Кандидат в `class-guard` — после посадки S1, когда близнецы берутся из дерева.
2. `CacheTTL` = значение `KACHO_NOTIFY_LIST_FILTER_CACHE_TTL` без преобразования; ноль не
   передаётся никогда — страж старта его отвергает (CX5-36 (а)). `CacheMaxEntries` — явно
   `listnarrow`-умолчание 10000, записанное в функции сборки константой с комментарием (CX5-36
   (в)).
3. Верх границы стража ручки читается из `authz.RevocationPolicy.Ceiling`; литерала `10s` в
   `services/notify` нет (CX5-40 (а)); проба NTF5-54 (д) берёт значение `Ceiling + 1s` (CX5-40 (б)).
   Нижняя граница `1s` — константа стража.

### З15. Контакты: строка на пару «область × категория», снятие — удалением

1. Таблица контактов аккаунта NTF-3 Р20 приводится к форме `notification_contacts (scope_type,
   scope_id, category, user_id, updated_at)`, PK `(scope_type, scope_id, category)`,
   `CHECK (category IN ('security','account_legal','operations'))`, `CHECK (scope_type IN
   ('account','project'))`, `CHECK (user_id <> '')` — пустого значения в строке нет (CX5-17 (б)).
   Ресурс проекта — те же строки с `scope_type = 'project'`. Прода нет (Д12): если NTF-3 заведёт
   иную форму, миграция S2 переводит её в эту прямо, без двух путей.
2. Назначение — `INSERT … ON CONFLICT (scope_type, scope_id, category) DO UPDATE SET user_id =
   EXCLUDED.user_id` без чтения; снятие — `DELETE` строки; все поля маски и Ф2 — одна транзакция
   (CX5-17 (в)).
3. Ответ `GET` — одна функция на ресурс «нет строки → пара»: аккаунт — пара `ACCOUNT_OWNER` поля
   `security` того же ответа; проект — `{userId: "", source: ACCOUNT}`. Значений `source` другого
   ресурса функция не производит (CX5-17 (а)).
4. Отображение ответа `Check` о назначаемом — исчерпывающее: вердикт «нет» → `FAILED_PRECONDITION`
   одним текстом; любой код ответа → `UNAVAILABLE`/`PEER_UNAVAILABLE`; вердикт из ошибки не
   выводится (CX5-17 (г)).

### З16. Права: аннотация либо освобождение с `Check`, и гейт на это

1. Методы `InternalNoticeService` несут `required_relation` (`system_admin`/`system_viewer` на
   `cluster`), мутации — `required_acr_min = "2"` (Р18). Звено `authz.Interceptor` носителя Х5 на
   слушателе `notify-api` судит каждый метод по его аннотации о принципале trust-aware пары
   (CX5-32 (а)). Других освобождений, кроме восьми методов Р2, нет.
2. Восемь освобождённых методов (`NoticeService.*`, `Get`/`Update` обоих сервисов контактов) несут
   `<exempt>` с `exempt_reason`; их use-case первым оператором после проверок формы зовёт
   `authzcheck.RequireScope(ctx, checker, relation, scope)` — одну функцию пакета
   `services/notify/internal/apps/notify/authzcheck` (CX5-13 (а)).
3. **Гейт** `internal/repohygiene/notify_method_authz_test.go` (kacho): обходит дескрипторы
   сервисов `kacho.cloud.notify.v1`, зарегистрированных на слушателе `notify-api`; метод с
   `required_relation` — засчитан; метод `<exempt>` — засчитан, только если функция его use-case
   (найденная по регистрации обработчика через `go/types`) содержит вызов `authzcheck.RequireScope`;
   прочее — находка с именем метода. Печатает число методов по двум видам; пустой обход — красный.
   Близнецы: инъекция «снята аннотация у `InternalNoticeService.Create`» и «снят вызов у
   `ProjectNotificationContactsService.Update`» — красный с именем (CX5-13 (в), CX5-32 (в), DoD
   10.1 п.11).
4. Секрета почты `notify-api` не монтирует (CX5-27); регистрация `InternalNoticeService` — только
   на слушателе носителя Х5, других слушателей у `notify` нет (Д17).

### З17. Принципал операции — только из trust-aware пары

Операции `notify` создаются только Ф1/Ф2 с принципалом, извлечённым парой
`CertIdentityExtract → TrustedPrincipalExtract` носителя Х5; отсутствие пересланного принципала —
отказ `UNAUTHENTICATED` звена личности до use-case, а не запасной системный (CX5-33 (а)). `Owner`
в `GetOwned`/`CancelOwned` обработчика фундамента берётся той же парой (CX5-33 (б)). Приставка id —
константа `nop` каталога операций corelib (Х1), своей строки нет (CX5-33 (в)).

### З18. Край: один адрес, одно соединение на два ключа, порядок строк перечня

1. **Адрес.** Ключи `notify` и `notifyInternal` берут адрес из **одного** поля конфигурации края —
   поля адреса внутреннего слушателя `notify`, которое заводит NTF-4 Р20 (без умолчания в теге, с
   парой mTLS и значением «notify в установке нет»). Второй ручки адреса `notify` в
   `gateway/internal/config/config.go` нет (CX5-45 (а)).
2. **Соединение.** `BackendAddrs()` несёт только `notifyInternal`; `dialBackends` после цикла
   ставит `backends["notify"] = backends["notifyInternal"]`, если ключ `notifyInternal` есть, по
   таблице псевдонимов `backendAliases = map[string]string{"notify": "notifyInternal"}` — один
   `*grpc.ClientConn`, одно закрытие в `cleanup` (CX5-45 (б)). `backendEdge` отдаёт обоим ключам
   ребро `notify` (CX5-45 (в)). Установка без `notify` — ни одного из двух ключей; методы перечня
   `notify` на внешнем gRPC-входе получают отказ маршрута, а не вызов по пустому адресу (CX5-45 (г)).
3. **Проба «одно соединение».** `gateway/cmd/api-gateway/route_wiring_parity_test.go` получает
   `TestRouteWiring_NotifyKeysShareOneConnection`: `backends["notify"] == backends["notifyInternal"]`
   (равенство указателей); близнец — `backends["vpc"] != backends["vpcInternal"]`.
4. **Установка с `notify` в пробе (ii) задаётся явно** (CX5-46): `realBackends` принимает опцию
   установки; для проб перечня тест задаёт `t.Setenv` адреса `notify` и пары mTLS; близнец
   `TestRouteWiring_NoNotifyAddressNoNotifyKeys` — без адреса ключей `notify`/`notifyInternal` в
   карте нет и ни одна строка `notify` перечня не резолвится. Умолчания полю адреса не
   добавляется. Это правка держателя, которую DoD 10.1 п.4 («эта под-фаза их не правит, кроме
   импорта») не предусмотрел; строка автору приёмки — неблокирующая (§13).
5. **Порядок строк перечня** (CX5-48). Blank-импорт `pkg/api/kacho/cloud/notify/v1` в
   `gateway/internal/allowlist/parity_test.go` обязателен с первого `.proto` пакета `notify` в
   дереве; кто его ни внёс, строки всех публичных методов `notify`, уже лежащих в дереве, входят в
   тот же коммит. Строки четырёх методов `NoticeService` — тем же коммитом, что сервис в контракте
   (S1); `Get`/`Update` контактов проекта — тем же, что `ProjectNotificationContactsService` (S2).
   На ревизии посадки S1 полоса края печатает перепись «публичный сервис `notify` → строк перечня»
   (`TestAllowlist_EveryPublicRPCIsRoutable -v`) и не садится, если хоть один сервис без строк.
   S1 садится после ключа `notify` (§13, Е4).
6. REST: пути `InternalNoticeService` — только на внутреннем mux, по соединению `notifyInternal`;
   публичные пути — на публичном mux, по тому же соединению (Р2).

### З19. Гейт изоляции знает носителя `notify`

Запись `"notify": ("svc/<Service внутреннего слушателя notify-api>", <порт из чарта>,
"<authority из SAN notify-api>")` в `INTERNAL_ENDPOINTS`; значения берутся рендером чарта `notify`
полосой развёртывания, не выдумываются (DoD 10.1 п.9). Перепись носителей `e2e-ban6-domains.py`
узнаёт регистрацию служб `notify-api` в форме носителя Х5; если `REGISTER_CALL` её не узнаёт,
образец дописывается этой формой с парой на синтетическом дереве. `--self-test` сверяет карту в обе
стороны; инъекции «запись снята» и «регистрация не узнана» — красный с именем носителя. Если запись
уже есть на стволе к старту S1, вторая не заводится.

### З20. Ручки — по развёртываниям, окно сужателя в политике, порядок тегов

| ручка | читает | страж старта | значение |
|---|---|---|---|
| `KACHO_NOTIFY_NOTICE_REMINDER_LEAD` | `notify-api` (`Update`), `notify-sender` (фиксация) | оба | values установки |
| `KACHO_NOTIFY_OB_PER_ADDRESS_DAILY` | `notify-sender` | `notify-sender` | values установки |
| `KACHO_NOTIFY_OB_STREAM_PER_MINUTE` | `notify-sender` | `notify-sender` | values установки |
| `KACHO_NOTIFY_NOTICE_RETENTION` | `notify-sender` (подметальщик) | `notify-sender` | values установки |
| `KACHO_NOTIFY_NOTICE_CREATE_VALIDATION_WINDOW` | `notify-sender` (шаги 2–5) | `notify-sender` | values установки |
| `KACHO_NOTIFY_LIST_FILTER_CACHE_TTL` | `notify-api` | `notify-api` | умолчание загрузчика `5s` |

- Страж каждого развёртывания судит ровно ручки, которые оно читает (CX5-18 (б)); NTF5-53, 54
  прогоняются для каждого развёртывания (CX5-18 (в)); `TestDeclaredKnobHasAReader` и
  `TestServiceDeclaringPostureKnobsHasABootGuard` видят оба корня.
- Объявления — `services/notify/internal/config`, по файлу на развёртывание; окно сужателя —
  тегом `envconfig:"KACHO_NOTIFY_LIST_FILTER_CACHE_TTL" default:"5s"` (форма `ScanFile`).
- **Порядок тегов corelib** (CX5-39 (а)): тег T1 — `ntc` и Ф1…Ф4 (S1); теги Х5, Х1 — NTF-4; тег T2
  — `feed`/`spec` класса `obligation`, `NoActiveLease`, `Supersede`, `DeleteUnleased`, `thread_key`
  и голова нити в `Claim`, `OutcomeObserver` в `Ack` (S2); тег TW —
  только запись `RevocationPolicy.Windows["notify KACHO_NOTIFY_LIST_FILTER_CACHE_TTL"] = 5s`,
  выпускается **последним перед посадкой S1** и позже T1, Х5, Х1.
- Подъём пина kacho на TW, объявление ручки с умолчанием, каталог в `revocationScanRoots` и ручка в
  `knobNames` — один коммит одного изменения (CX5-39 (б)). Между выпуском TW и посадкой S1 другие
  полосы пин kacho не поднимают: любой тег после TW запись несёт. Строка «не поднимать пин kacho на
  тег с записью `notify` вне изменения S1 NTF-5» — в задачах corelib (Р23), NTF-1, NTF-4 (CX5-39
  (в), заказ диспетчеру, §13). Если S2 садится после S1, T2 выпускается после TW и несёт запись
  (поднимать T2 можно только после S1).

### З21. Метрики Р19 — состояние базы и счётчики в базе, агрегация названа

1. Метрики состояния базы (`notify_notice_fanout_pending`, `notify_notice_overdue`,
   `notify_notice_create_pending`) — запрос сборщика `notice/metrics` при снятии; счётчики исходов
   (`notify_notice_letters_total`, `notify_notice_unaddressed_total`, `notify_ob_deferred_total`) —
   таблица `notice_counters (name, labels, n)`, увеличиваемая **в той же транзакции**, что пишет
   исход: раскрытие (исходы кандидатов, `UNADDRESSED`), переход (`SUPERSEDED`) и наблюдатель
   исхода строк адресатов (`SENT`, `DEFER(ob_*)` и прочие клетки NTF-1 Р11). Подметальщик счётчики
   не уменьшает — строки счётчиков не связаны со строками извещений.
   - **Наблюдатель — порт сервера ленты corelib `feed.OutcomeObserver`** (CX5-54 (в)):
     `func(ctx context.Context, tx pgx.Tx, row feed.AckedRow) error`, поле конфигурации
     `feed.NewServer`. `Ack` зовёт его последним действием своей транзакции и **только в ветке,
     где записывающий оператор изменил строку**
     (M18: «следствия записи — только на изменившей строке», замысел NTF-1 З9). На ветке «повтор с
     тем же токеном и исходом» (успех без изменения строки, M19) и на отказах `OUTCOME_ALREADY_RECORDED`,
     `LEASE_LOST` вызова нет (CX5-54 (а)). Ошибка наблюдателя откатывает транзакцию `Ack`, и
     вызывающий получает отказ — строка остаётся под арендой и получит исход повтором `Ack`.
     Наблюдатель `notify` регистрирует корень `notify-sender` для ленты пространства `notify`; он
     делает три вещи в транзакции `Ack`: резерв окна OB (З11 п.2), `notice_addressees.sent_at`
     при `SENT` (З12 п.3), счётчики — последним оператором.
   - **Порядок строк счётчиков** (CX5-54 (б)). Все увеличения — одна функция
     `notice/metrics.Add(ctx, tx, deltas)`, и каждая транзакция зовёт её **последним оператором**,
     один раз: `INSERT INTO notice_counters (name, labels, n) SELECT … FROM unnest($names, $labels,
     $deltas) ORDER BY 1, 2 ON CONFLICT (name, labels) DO UPDATE SET n = notice_counters.n +
     EXCLUDED.n`. Дельты одной транзакции сведены по ключу до вызова, строки блокируются в порядке
     `(name, labels)`. Все прочие блокировки транзакции взяты раньше, поэтому две транзакции,
     задевающие пересекающиеся строки счётчиков, ждут друг друга в одном порядке, и `40P01` между
     ними не возникает. Проба — две страницы раскрытия и переход одновременно, 20 повторов,
     `40P01` — 0 (заказ, N9).
2. Каждая реплика `notify-sender` отдаёт одинаковые значения (CX5-28). Правила тревог и панели
   агрегируют `max without (instance, pod)`; сумма по репликам нигде не берётся. Счётчики процесса
   (`notify_recipient_directory_refused_total` — событие вызова) — на процесс, агрегация `sum`.
3. Тревоги: `notify_notice_overdue > 0` дольше 15 мин; рост `notify_notice_unaddressed_total`;
   `notify_notice_create_pending` не падает до 0 дольше окна проверки; возраст старейшей
   непринятой строки источника `notify` класса `obligation` > 24 ч (метрика NTF-1 Р18). Правила — в
   чарте `notify`, их проба — набор NTF-1 `notify_alert_rules_test` с синтетическим рядом **двух**
   реплик (удвоения не видно, если агрегация `max`).

### З22. Перечень 18 типов — одна константа и сверка с моделью службы доступа

`rules.TenantResourceTypes` — единственная константа (порядок как в Р4); комментарий поля
`affectedResources` в контракте её перечисляет, и проба контракта сверяет комментарий с константой.
Гейт `internal/repohygiene/notice_tenant_types_test.go` (kacho) читает модель службы доступа из
модуля `kaname` пина (`go list -m -f '{{.Dir}}'`), выводит типы с `define project: [project]` либо
`define parent: [T]`, где `T` связан с проектом, вычитает записанные исключения
(`iam_access_binding` — выдача прав, `compute_guest_access_key` — учётные данные, у каждого —
причина) и сравнивает с константой в обе стороны; печатает число типов модели. Близнецы: на пине —
молчит (18 = 18); инъекция типа в модель фикстуры — красный с именем типа (CX5-25).

### З23. Служба доступа: `DescribeScope`, `ListAccounts`, неизменяемость связей

1. Оба метода — в `InternalNotificationRecipientService` справочника NTF-3 Р7; ограждение — звено
   `service:notify` на точном SAN, перечень методов звена (§3 З15 приёмки), каталог прав с
   `required_relation reader` на `notification_recipient_directory:root`; путь двери — тот же, что у
   `Resolve`, ни один из 16 вызовов надзора администратора облака на их пути не стоит без сверки
   перечня типов без надзора (CX5-21).
2. `DescribeScope` — первым оператором: обязательность (ни одного / оба), затем
   `shared.ValidateResourceID` своего типа, затем чтение (CX5-22). Чтение — одна выборка: для
   аккаунта `SELECT id, owner_user_id FROM kaname.accounts WHERE id = $1`; для проекта — соединение
   `projects` и `accounts`. Нет строки — `exists = false` с пустыми полями.
3. `ListAccounts` — прямая keyset-выборка `kaname.accounts` по `(created_at, id)` индекса
   `accounts_cursor_idx`, **без** пообъектного сужения и без публичного `ListAccountsUseCase`
   (CX5-11 (а)). Курсор — существующий кодек `kv1.` (`EncodeVisiblePageToken`/`DecodeVisiblePageToken`),
   третьей формы нет (CX5-11 (в)); комментарий метода в контракте: «значение хранится потребителем
   между вызовами; смена формы курсора — смена контракта ребра `notify → kaname`» (CX5-11 (б)).
4. **Неизменяемость `owner_user_id` и `account_id` проекта — ограничением базы** (CX5-10 (в)):
   новая миграция службы доступа заводит триггеры `BEFORE UPDATE OF owner_user_id ON
   kaname.accounts` и `BEFORE UPDATE OF account_id ON kaname.projects`, отвергающие смену значения
   (`RAISE … USING ERRCODE = 'check_violation'`, текст называет потребителя — кэш областей
   `notify`). Интеграционная проба службы доступа: смена значения — отказ `23514`; правка `name` —
   проходит (близнец).

### З24. Подметальщик — Р14 без условия на исход, id строк ленты до каскада

Подметальщик исполняет Р14 как есть: извещение в `COMPLETED`/`CANCELLED` старше
`KACHO_NOTIFY_NOTICE_RETENTION` удаляется вместе с этапами и строками доставки, какой бы исход ни
был у строки доставки (CX5-24 (1)). Своего SQL к таблице ленты у `notify` нет (З8 п.5): строки
ленты снимает функция corelib (CX5-24 (2)). Одна транзакция `READ COMMITTED` на партию, в таком
порядке (CX5-24 (3) — порядок снятия):

1. **Извещения партии** — `SELECT id FROM notices WHERE ((state = 'COMPLETED' AND completed_at <
   $cut) OR (state = 'CANCELLED' AND cancelled_at < $cut)) ORDER BY id LIMIT $batch FOR UPDATE SKIP
   LOCKED`. Предикат состояния и срока — в `WHERE`.
2. **События партии** — `SELECT id FROM notice_stage_events WHERE notice_id = ANY($ids) ORDER BY id
   FOR UPDATE`. Порядок «извещение → события» тот же, что у перехода (З6 п.2). Раскрытие страницы и
   повтор кандидата, ждущие блокировки события, после фиксации находят 0 строк и откатываются, так
   что после шага 3 новых строк адресатов по этим событиям не появится (CX5-24 (4): открытое событие
   и отложенный кандидат снимаются вместе с извещением, а не держат его).
3. **id строк ленты — до каскада**: `SELECT a.feed_row_id FROM notice_addressees a JOIN
   notice_stage_events e ON e.id = a.event_id WHERE e.notice_id = ANY($ids)`.
4. **Строки ленты** — `feed.DeleteUnleased(ctx, tx, feedIDs) (deleted, leased []string, err
   error)`: удаляет строки из переданных, у которых нет действующей аренды (`feed.NoActiveLease`,
   З8 п.5), в любом состоянии — `pending`, в `DEFER` или терминальном — и возвращает удалённые и
   оставшиеся под арендой.
5. **Извещения с арендованной строкой** выходят из партии: у строки под действующей арендой ещё
   может быть `Ack`, и конвейер доводит её до исхода (как строку, взятую до перехода, З8 п.5). Такое
   извещение удаляет следующий проход — не позже `feed.LeaseTTL` плюс период подметальщика: `Ack`
   снимает аренду, упавший держатель теряет её по сроку (M18). Это не новый исход и не условие на
   исход: предикат Р14 не меняется, меняется лишь проход, в котором удаление случается.
6. **Резервы окна OB** снятых строк ленты без `SENT` — `DELETE FROM notice_ob_address_window WHERE
   feed_row_id = ANY($deleted) AND sent_at IS NULL` (З11 п.2); записи `SENT` остаются в счёт окна
   24 ч.
7. `DELETE FROM notices WHERE id = ANY($deletable) RETURNING id`. Зависимые таблицы извещения
   (`notice_audience`, `notice_affected_resources`, `notice_reminders`, `notice_stage_events` →
   `notice_addressees`, `notice_candidates`, `notice_scope_outcomes`) — `FOREIGN KEY … ON DELETE
   CASCADE` в той же базе.

Печатается число удалённых извещений и строк ленты и число извещений, отложенных шагом 5. `feed`
удаляет только переданные ему id и только без действующей аренды — строку другого источника и
строку в полёте он не снимает (проба C5 с близнецами «арендованная — осталась, `leased`»,
«`pending` без аренды и терминальная — удалены»). Закрытые строки ленты может раньше снять уборка
по сроку хранения NTF-1 (замысел NTF-1 `9bfa92be`, §6: «уборка закрытых строк … по сроку
хранения»); id, которого уже нет, для
`DeleteUnleased` — не ошибка и не строка ответа. Незакрытые строки извещения снимает только этот
вызов (М16).

### З25. Моменты — секунды

Момент приёма усекается до секунды один раз (З3 п.1); фиксация копирует его и часов не зовёт;
`startedAt`/`completedAt`/`cancelledAt`, `updatedAt` — `now` часов `notify`, усечённое до секунды,
в той же записи; ответ контракта усечён повторно на выходе (`api-timestamp-truncate`,
`TestOperationTimestampsAreTruncatedEverywhere`) (CX5-26).

### З26. Атрибуты шаблонов: шаблон × атрибут × откуда значение × законен ли нуль (Д21)

`feed.Put` для шаблонов `notice-*` зовут ровно **два пути**, оба в `notify-sender`, оба в
транзакции, которая пишет строку адресата (З8 п.1): (П1) страница раскрытия (З9 п.2) и (П2) повтор
отложенной строки кандидата с исходом `ADDRESS` (З8 п.3). Посева, ставящего письма извещений, нет:
строки ставит только раскрытие события этапа, а событие пишет транзакция `Create`, перехода либо
планировщика (З6 п.1). Путь без человека в NTF-5 — планировщик (`reminder`); он пишет событие, а
значения берёт тот же П1. Оба пути читают значения одной функцией `notice/fanout.letterAttrs(notice,
addressee)` в своей транзакции под блокировкой события: пока событие открыто, ревизия извещения
равна ревизии события (`Update` закрывает события ревизий `≤ r`, З8 п.5), а `Start`/`Complete`
моментов `starts_at`/`ends_at` не меняют — значения те, что у события.

| шаблоны (из 19, Р11) | атрибут | тип | `presence` | откуда значение | законен ли нуль |
|---|---|---|---|---|---|
| все 19 | `startsAt` | `timestamp` | `required` | `notices.starts_at` | нет: у `MAINTENANCE`, `DECOMMISSION`, `TERMS_CHANGE` поле обязательно, у `OUTAGE`, `SUSPENSION`, `SECURITY_INCIDENT` его ставит сервер моментом приёма (Р4, M21); `NOT NULL` в `notices` |
| все 19 | `link` | `path` | `required` | `/notices/<notices.id>/accounts/<scope_id>` либо `…/projects/<scope_id>` — область строки адресата (`notice_addressees.scope`, Р6) | нет: область строки адресата `NOT NULL` |
| `notice-maintenance-{scheduled,reminder,rescheduled,cancelled,completed}` (5) | `endsAt` | `timestamp` | `required` | `notices.ends_at` | нет: у `MAINTENANCE` поле обязательно (Р4), `CHECK` вида в `notices` держит `ends_at IS NOT NULL` |
| `notice-outage-{started,resolved}`, `notice-decommission-{scheduled,reminder,rescheduled,cancelled,completed}`, `notice-suspension-{started,lifted}`, `notice-security-incident-{opened,closed}`, `notice-terms-change-{scheduled,rescheduled,cancelled}` (14) | `endsAt` | `timestamp` | `optional` | `notices.ends_at` | **да**: у этих пяти видов поле запрещено (Р4, NTF5-07), `ends_at IS NULL` всегда |

- **Одно написание отсутствия** (CX5-49 (в), M22). `notices.ends_at` читается в `*time.Time`;
  `NULL` — поле `EndsAt` сгенерированного `XAttrs` не задаётся (нулевое значение `optional` —
  «не задан»), и `Put` ключа в строку не пишет. Функция `letterAttrs` — единственное место этого
  перевода; ненулевой `time.Time{}` в `EndsAt` она не пишет никогда.
- **Тело и тема** (CX5-49 (б)). Блок тела, ссылающийся на `endsAt` в 14 шаблонах, несёт `when:
  endsAt`; тема ни одного из 19 шаблонов на `endsAt` не ссылается (NTF-1 Р7: тема — только
  `required`). В пяти шаблонах `MAINTENANCE` `endsAt` — `required`, `when` на нём нет.
- **Почему `required` там, где нуль невозможен.** `required` у `MAINTENANCE` переводит нарушенный
  инвариант (`ends_at IS NULL` у `MAINTENANCE`, который `CHECK` не пропускает) в отказ `Put`, а не в
  письмо без срока работ. `optional` у 14 шаблонов — не «на всякий случай»: там нуль — единственное
  значение.
- **Эталоны** (CX5-49 (г)). Эталон `.eml` — на каждую пару «шаблон × локаль», 19 × 2 = 38; 28
  эталонов 14 шаблонов — это и есть случай «без `endsAt`», 10 эталонов `MAINTENANCE` — с ним.
  Сборка (`bundle-check`) сверяет число эталонов с ведомостью (N11).

### З27. Аренды `notify`: одна формула, токен на взятие, часы `notify`

Аренд в `notify` три: заявка создания (З3 п.2), событие этапа (З9), строка кандидата в `DEFER`
(З8 п.3). У всех трёх одна форма (CX5-50):

1. **Столбцы** `lease_token uuid NULL`, `lease_until timestamptz NULL`, `CHECK ((lease_token IS
   NULL) = (lease_until IS NULL))`. Вставка строки — без аренды, оба `NULL`: строка, которую ещё
   никто не брал, свободна.
2. **«Аренда свободна» — одна формула** `(lease_until IS NULL OR lease_until <= $now)`, тем же
   написанием, что `feed.NoActiveLease` ленты (З8 п.5). Предиката `lease_until < now()` без ветки
   `NULL` нет. Формула объявлена один раз — `notice/lease.FreeSQL(alias)` — и её подставляют три
   взятия и ничего больше.
3. **Держатель — токен взятия, а не имя процесса** (CX5-50 (б)). Взятие ставит `lease_token =
   gen_random_uuid()` и возвращает его; каждая запись под арендой несёт `AND lease_token = $T`.
   Токен новый на каждое взятие, поэтому CAS различает и две реплики, и прежнее и новое воплощение
   одного процесса, и два взятия одной реплики. Имени пода и константы в условии нет.
4. **Часы — часы `notify`, параметром** (CX5-50 (в)). `$now` — порт часов `notify` (тот же, что судит
   окно проверки З3 п.4 и моменты З25); `now()` базы в трёх арендах не зовётся. Срок — константа
   пакета (§8). Лента живёт на часах своей базы (замысел NTF-1 З8, `lease_until` в ответе
   `Claim`): это аренда другого владельца, и её формула с арендами `notify` совпадает написанием,
   а часы у каждой — владельца таблицы.
5. **Проба** «упавшая реплика держит аренду — другая берёт после срока» исполнима управляемыми
   часами NTF5-18: реплика A берёт заявку и не завершает попытку; часы сдвигаются на срок аренды;
   реплика B берёт её и фиксирует; запись A с прежним токеном — 0 строк (заказ, N3). Близнец — до
   срока B заявку не берёт.

## 3. Инварианты

| № | инвариант | чем держится |
|---|---|---|
| И1 | Ф1…Ф4 пишут только строку операции и получают настройку только из `NewRepo(pool, schema)` | NTF5-122 (з), (и); перепись входов DoD 10.1 п.2а (б); гейт замыкания З2 п.7 |
| И2 | запись операции вне транзакции вызывающего не компилируется; `nil` — ошибка до запроса | сигнатура `pgx.Tx` (З2 п.3); буква `nil` в NTF5-122 (заказ исполнителю corelib) |
| И3 | успешной операции без извещения и отменённой с извещением не бывает | Ф3/Ф4 с условием `done = false` в транзакции фиксации; NTF5-118, 119, 122 (ж), (к) |
| И4 | у операции `Create` терминальных писателей три: фиксация, терминальный отказ, отмена | З4, предикат «`NewReconciler` в `services/notify` — 0» |
| И5 | одно письмо на субъекта на событие этапа при любом порядке областей и реплик | уникальность `notice_addressees (event_id, subject)`; NTF5-65, 107, 111 |
| И6 | ни одной строки по закрытому событию после фиксации перехода | порядок блокировок З6 п.2; NTF5-112…115; проба гонки CX5-29 (заказ) |
| И7 | строка кандидата не попадает в конвейер отправки | отдельная таблица З8 п.2; NTF5-62 (а), 111 |
| И8 | строка `obligation` без срока, строка иного класса со сроком | `CHECK` `feed` З10 п.2; NTF5-116, 117 |
| И9 | потолок и темп OB — на установку, при любом числе реплик | таблицы З11; NTF5-82, 83 при двух репликах (заказ) |
| И10 | «не видно из области» побайтно равно «нет» | одна выборка З13 п.1; NTF5-46 |
| И11 | каждый метод `notify-api` — аннотация либо освобождение с `RequireScope` | гейт З16 п.3; NTF5-121, §9 приёмки |
| И12 | ключи края `notify` и `notifyInternal` — одно соединение, один адрес без умолчания | З18 п.2, пробы З18 п.3, п.4 |
| И13 | окно сужателя — только из ручки, верх — потолок политики | З14; NTF5-120, 54 (д); гейт окна отзыва (DoD 10.1 п.10) |
| И14 | кэш областей не расходится со службой доступа | триггеры З23 п.4 + проба; `CHECK` кэша З9 п.3 |
| И15 | метрика состояния базы не удваивается числом реплик в тревоге | агрегация `max` З21 п.2; проба правил на двух рядах |
| И16 | «аренда свободна» пишется одной формулой с веткой `NULL` у ленты и у трёх аренд `notify`; держатель — токен взятия | `feed.NoActiveLease` (З8 п.5), `notice/lease.FreeSQL` (З27); проба C5 «отложенная строка с истёкшей арендой закрыта `Supersede`»; проба N3 «упавшая реплика» |
| И17 | резерв окна OB не мешает повторному взятию строки и снимается любым исходом, кроме `SENT` | З11 п.1, п.2; проба N10 «резерв, затем `DEFER(ob_stream_pace)`, взята снова — письмо ушло, `23505` нет» |
| И18 | в полёте не больше одной строки нити; строки без ключа нити условием не задеты | голова нити в `Claim` (З12 п.1); проба C5: две строки без ключа — один `Claim` выдаёт обе, две строки одного ключа — одну |
| И19 | повтор `Ack` счётчиков не меняет; строки счётчиков блокируются в одном порядке, последним оператором | наблюдатель в ветке изменившей строки (З21 п.1); проба «ответ `Ack` потерян, повтор — `SENT` = 1» (N10); проба «две страницы и переход — `40P01` 0» (N9) |
| И20 | извещение старше срока хранения удаляется со всеми строками доставки; строка под арендой откладывает удаление не дольше аренды | З24; NTF5-50, 51, 92; проба C5 `DeleteUnleased` |
| И21 | у каждого атрибута каждого из 19 шаблонов объявлено `presence`; нуль — только у `optional` и пишется отсутствием ключа | З26; NTF5-57, 73, 107; эталоны `.eml` 38 |
| И22 | завершённое раскрытие не повторяется; начальная позиция отлична от законной | `fanned_out_at`, `NULL`-позиции с `CHECK` (З9 п.1, п.4); проба N9 «раскрыто на двух страницах — `ListAccounts` не зовётся, `fanout_pending` = 0» |
| И23 | Ф1, Ф2 отказывают любому принципалу, который `IsAnonymous` | З2 п.5; буквы NTF5-122 (заказ C2) |

## 4. Компоненты и границы

Дерево — `PRO-Robotech/kacho`, если не сказано иное. «Новый» — файла нет на ревизии §0.

| компонент | путь | новый/правка | стадия |
|---|---|---|---|
| префикс `ntc` | corelib `ids/ids.go` (`hyphenFormPrefixes`) | правка | S1 |
| Ф1…Ф4, `TxWriter`, `TxRepo`, гейт замыкания | corelib `operations/{repo.go,txwriter.go,txwriter_closure_test.go,txwriter_integration_test.go}` | правка + новые | S1 |
| запись окна политики | corelib `authz/revocation_policy.go` (`Windows`) | правка | S1 (тег TW) |
| класс `obligation` | corelib `notify/spec` | правка | S2 |
| лента: срок `NULL` и ветка `NULL` в условии `Claim`, `thread_key`, `NoActiveLease`, `Supersede`, `DeleteUnleased` | corelib `notify/feed` | правка | S2 |
| сервер ленты: `Claim` — условие головы нити (З12 п.1) | corelib `notify/feed` (сервер ленты) | правка | S2 |
| сервер ленты: `Ack` — порт `OutcomeObserver` в ветке, изменившей строку (З21 п.1) | corelib `notify/feed` (сервер ленты) | правка | S2 |
| контракт извещений | `proto/kacho/cloud/notify/v1/{notice.proto,notice_service.proto,internal_notice_service.proto}` | новые | S1 |
| контракт контактов, вид `OPERATOR_NOTICE` | `proto/kacho/cloud/notify/v1/` (файлы NTF-3) + `project_notification_contacts_service.proto` | правка + новый | S2 |
| справочник: два метода | kaname `proto/kaname/cloud/iam/v1/` (сервис NTF-3), use-case справочника, перечень звена, каталог прав | правка | S1 (`DescribeScope`), S2 (`ListAccounts`) |
| неизменяемость связей | kaname `internal/migrations/<новая>.sql` | новая | S1 |
| миграции извещений | `services/notify/internal/migrations/<новые>.sql` | новые | S1 (заявки, извещения, аудитория, ссылки, напоминания, события, кэш, счётчики), S2 (адресаты, кандидаты, исходы областей, окно и ведро OB, контакты) |
| use-case `notify-api` | `services/notify/internal/apps/notify/api/{notice,publicnotice,contacts}/`, `…/authzcheck`, `…/authzwiring` | новые / правка `contacts/account` | S1, S2 |
| `notify-sender` | `services/notify/internal/notice/{admit,fanout,scopecache,schedule,sweeper,limits,thread,metrics,rules,lease}` | новые | S1 (`admit`, `schedule`, `sweeper`, `metrics`, `rules`, `lease`), S2 (прочее, наблюдатель исхода) |
| конфигурация | `services/notify/internal/config` | новые файлы | S1 |
| шаблоны | `services/notify/notifications/notice-<kind>-<stage>/` ×19 | новые | S2 |
| край | `gateway/internal/config/config.go`, `gateway/cmd/api-gateway/{mtls_config.go,route_wiring_parity_test.go}`, `gateway/internal/allowlist/{list.go,parity_test.go}`, `gateway/internal/restmux/mux.go`, каталог прав | правка | S1, S2 |
| гейты kacho | `internal/repohygiene/{notify_method_authz_test.go,notice_tenant_types_test.go,revocationwindow_test.go}`, `tools/revocationwindowgate/gate.go` | новые + правка | S1 |
| гейт изоляции | `deploy/scripts/{assert-ban6-external-isolation.py,e2e-ban6-domains.py}` | правка | S1 |
| чарт | чарт `notify` (NTF-1): ручки, правила тревог | правка | S1, S2 |
| сквозные | коллекция newman извещений + запись ведомости производителя | новая | S3 |
| воркспейс | `docs/specs/01-architecture-and-services.md` §«Runtime cross-domain edges»; vault | правка | S2, S3 |

**Граница с соседями.** Служба `notify`, конвейер, `feed.Put`, сервер ленты, носитель Х5,
префикс `nop`, соединение `notifyInternal` и поле его адреса — NTF-1 и NTF-4; справочник `Resolve`,
ресурс контактов аккаунта, настройки и каталог — NTF-3; экраны — NTF-6. Этот замысел их форм не
переопределяет; где он требует от них формы (поле адреса без умолчания, ключ таблицы контактов,
перевод исполнителя на Ф4), это строка §13.

## 5. Набросок контракта

Форма полей — приёмка (Р2, Р4, Р16, Р18, Р21); здесь — только то, что решает замысел.

- `optional bool exists = 1;` в ответе `DescribeScope` — присутствие отделено от значения (З3 п.8).
- `ListAccountsResponse.account_ids` — `repeated string`, комментарий: «упорядочено `(created_at,
  id)` по возрастанию»; `page_token` — комментарий о хранении потребителем (З23 п.3).
- `Notice.affected_resources` — `repeated ResourceRef`, комментарий: «порядок — заданный оператором;
  повтор хранится как прислан; в `List` не заполняется; в публичном `Get` сужено по `v_get`
  вызывающего; допустимые типы — <18 типов>» (З13 п.4, З22).
- `Notice.reminders` — только во внутренней проекции, «упорядочено по `at`».
- `ProjectNotificationContacts` — те же поля, что `AccountNotificationContacts`; `source` дополнен
  `ACCOUNT`, комментарий: «производит только ресурс проекта».
- Метаданные операции `Create` — `NoticeCreateMetadata { notice_id }`; `resolveResourceID`
  фундамента берёт `notice_id` (первое поле `*_id`).

## 6. Схема БД (набросок; миграции пишет `migration-writer`, судит `db-architect-reviewer`)

Схема `kacho_notify`. Все моменты — `timestamptz`, усечённые до секунды приложением.

| таблица | ключ и ограничения |
|---|---|
| `notice_create_requests` | PK `notice_id`; `operation_id` UNIQUE; `CHECK` ровно одной формы аудитории; `accepted_at NOT NULL`; аренда З27 (`lease_token`, `lease_until` — `NULL` при вставке, `CHECK` парности) |
| `notices` | PK `id`; `kind`, `state` — `CHECK` закрытых перечней; `CHECK` допустимости `starts_at`/`ends_at` по виду (Р4), `CHECK (ends_at IS NULL OR ends_at > starts_at)`; `CHECK` согласованности моментов с состоянием (`started_at IS NOT NULL` ⇔ состояние после `IN_PROGRESS`, и т.д.); `revision ≥ 1`; индекс `(created_at, id)` |
| `notice_audience` | PK `(notice_id, scope_type, scope_id)`; `account_id NOT NULL` (для проекта — из `DescribeScope`); FK → `notices ON DELETE CASCADE`; индексы `(scope_type, scope_id)`, `(account_id)`; признак `allAccounts` — столбец `notices.audience_all` с `CHECK` против строк аудитории |
| `notice_affected_resources` | PK `(notice_id, ordinal)`; `type` — `CHECK` 18 типов; FK `CASCADE` |
| `notice_reminders` | PK `(notice_id, at)`; `revision`; FK `CASCADE` |
| `notice_stage_events` | PK `id`; UNIQUE `(notice_id, stage, revision, due_at)`; `due_at NOT NULL`; `closed_at` (только переход); `fanned_out_at` (только последняя страница, З9 п.4); аренда З27; позиция `scope_done integer NULL CHECK (scope_done >= 0)` либо `page_token text NULL CHECK (page_token IS NULL OR page_token <> '')`; FK `CASCADE` |
| `notice_addressees` | PK `id`; UNIQUE `(event_id, subject)`; `scope NOT NULL`; `feed_row_id` UNIQUE; `sent_at` (ставит наблюдатель на `SENT`, З12 п.3); FK → события `CASCADE` |
| `notice_candidates` | PK `(event_id, subject, scope)`; `outcome` `CHECK`; `CHECK ((next_attempt_at IS NOT NULL) = (outcome = 'DEFER_PLATFORM_UNAVAILABLE'))`; аренда З27; FK `CASCADE` |
| `notice_scope_outcomes` | PK `(event_id, scope)`; `outcome ∈ {ADDRESSED, UNADDRESSED}`; FK `CASCADE` |
| `notice_scope_cache` | PK `(scope_type, scope_id)`; `CHECK` непустых полей |
| `notice_ob_address_window` | PK `feed_row_id`; `address_hash NOT NULL`, `reserved_at NOT NULL`, `sent_at` (ставит наблюдатель на `SENT`); индекс `(address_hash, reserved_at)` (З11) |
| `notice_ob_stream_bucket` | одна строка, `CHECK (id = 1)`, `tokens ≥ 0` |
| `notice_counters` | PK `(name, labels)`; `n ≥ 0` |
| `notification_contacts` | З15 п.1 |

Имя каждого `CHECK` уникально и отображается в тексте Р4 единственным домом SQLSTATE службы.

**Отсутствие — одним написанием по всей схеме.** Аренда, позиция раскрытия, признак «раскрытие
завершено», `sent_at`, `thread_key` ленты — `NULL`; пустая строка там, где отсутствие законно,
закрыта `CHECK`. Выбор для аренд — «`NULL` при вставке, свободна по формуле с веткой `NULL`» (З27),
один на три таблицы.

## 7. Последовательности

**`Create`.** `notify-api`: проверки Р4/Р10 → транзакция {заявка, Ф1} → ответ `done=false`.
`notify-sender`: аренда заявки → `ops.Get` → (`done=true`: удаление заявки) | (`done=false`:
`DescribeScope` каждой области → окно не истекло → транзакция {снятие заявки, извещение, аудитория,
ссылки, событие создания, напоминания, Ф3} | область `exists=false` → транзакция {снятие, Ф4
`PEER_RESOURCE_MISSING`} | отказ → классификатор З3 п.7 → повтор либо по истечении окна транзакция
{снятие, Ф4 `PEER_UNAVAILABLE`}). Отмена — `operationspb.Handler.Cancel` → `CancelOwned`; при её
первенстве Ф3/Ф4 дают `ErrAlreadyDone` → откат.

**Переход.** `notify-api`: транзакция {`UPDATE notices` с условием → (0 строк: чтение → отказ) |
закрытие событий → `feed.Supersede` (нет действующей аренды) + удаление кандидатов → резервы окна
закрытых строк → напоминания → новое событие → Ф2 → счётчики последними}.

**Страница раскрытия.** `notify-sender`: аренда события (З27) → вызовы (`ListAccounts`,
`DescribeScope` при промахе, `Resolve` по цепочке) → транзакция {`FOR SHARE` события с его токеном
→ адресаты (+ `feed.Put`, значения З26), кандидаты, исходы областей, позиция либо `fanned_out_at`,
счётчики последними}.

**Отправка строки адресата.** Конвейер NTF-1: `Claim` (голова нити, З12 п.1) → слой лимитов OB —
своя транзакция {замок адреса → свой резерв? → потолок → жетон → резерв} либо `Ack DEFER(ob_*)`
(З11) → рендер (`thread.Headers`, корень по `sent_at`) → SMTP → `Ack` {изменила строку →
наблюдатель: резерв окна, `sent_at`, счётчики последними} (З21 п.1).

**Подметальщик.** `notify-sender`: транзакция партии {извещения `FOR UPDATE SKIP LOCKED` →
события `FOR UPDATE` → id строк ленты → `feed.DeleteUnleased` → извещения с арендованной строкой
выходят из партии → резервы окна без `SENT` → `DELETE notices` с каскадом} (З24).

## 8. Конфигурация, ручки и границы

Ручки — §2 З20 и Р17 приёмки. Константы без ручек (ни один довод оператора их не меняет): размер
страницы `ListAccounts` — 100 (Р10); аренда заявки, события и строки кандидата (З27) — константы
пакетов `admit`/`fanout`,
больше худшего времени одной попытки (сумма сроков вызовов попытки), с комментарием о выводе;
`CacheMaxEntries` сужателя — 10000 (З14 п.2).

## 9. Рёбра

- `notify-sender → kaname`: `DescribeScope`, `ListAccounts`, `Resolve`, `ResolveSend` (субъект
  `service:notify`); опора кэша — неизменяемость `owner_user_id` и `account_id` проекта (З23 п.4).
- `notify-api → kaname`: `Check`, пакетная проверка сужателя — о вызывающем либо названном
  пользователе.
- `gateway → notify-api`: одно соединение `notifyInternal` (ключ `notify` — псевдоним).
- Служба доступа `notify` не вызывает — ребро ациклично. Строка `notify → kaname` в
  `docs/specs/01-architecture-and-services.md` дописывается по DoD 10.2 п.8 с опорой кэша.

## 10. Последовательность тегов и пинов

1. corelib T1 (`ntc`, Ф1…Ф4, гейт замыкания) → пин kacho поднимается полосой S1 **без** записи TW.
2. corelib Х5, Х1 (NTF-4) → пин kacho поднимает полоса NTF-4.
3. corelib TW (запись окна `notify`) — последним перед посадкой S1; пин kacho на TW — коммитом S1
   вместе с ручкой и каталогом.
4. corelib T2 (`obligation`, лента: ветка `NULL` срока в `Claim`, `NoActiveLease`, `Supersede`,
   `DeleteUnleased`, `thread_key` и голова нити, `OutcomeObserver`) — после TW; пин kacho на T2 —
   полосой S2.
5. kaname: `DescribeScope` + триггеры — до S1; `ListAccounts` — до S2; пин kaname в kacho поднимается
   вместе с потребителем.

## 11. Отображение пунктов разбора в решения

Каждый пункт первичных разборов на `1f4852e4`, `2fe29c35`, `88fabd09`, `03e291ee`, `367b9482` и
пересверки на `a43a19fa` → решение замысла → механизм → держатель.

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX5-01 | З8 п.1, п.2, п.6 | две таблицы, ключ кандидата с областью; «одно письмо» — только на адресатах; счётчики по виду строки | NTF5-111, 65 |
| CX5-02 | З6 п.1 | `due_at` пишет транзакция перехода; часы для ключей не зовутся | NTF5-65, 107 |
| CX5-03 | З5 п.1–3 | одна запись с условием; классификация после 0 строк; порядок «вид → состояние» из `rules` | NTF5-33 (20 повторов), 30, 31, 32, 35, 86 |
| CX5-04 | З5 п.4, п.5 | `CHECK` с именами → тексты Р4; `IS DISTINCT FROM` в записи; «в будущем» — часами до записи | NTF5-41, 87, 88; проба «маска только `endsAt` раньше хранимого `startsAt`» (заказ, `tasks.md` N4) |
| CX5-05 | З8 п.5, З1 | таблица Р5 в `rules`; закрытие одним оператором; `Supersede` по формуле «нет действующей аренды» (`feed.NoActiveLease`, та же, что у `Claim` и уборщика); `Ack` снимает аренду и у `DEFER` | NTF5-74, 112…115; проба «`Cancel` при строке, отложенной потолком, после конца её аренды — `SUPERSEDED`, SMTP 0» (заказ, N10); проба C5 «`Supersede` не трогает арендованную, закрывает отложенную» |
| CX5-06 | З10 п.1, п.2 | `ttl` запрещён валидатором; строка без срока | NTF5-116, 117 |
| CX5-07 | З11 п.1–п.3 | окно и ведро в базе, в транзакции слоя лимитов `notify` (не в `Claim`); свой резерв переиспользуется, вставка — `DO NOTHING`; откат не оставляет резерва; снятие — наблюдателем любым исходом, кроме `SENT`, и транзакциями `Supersede`/`DeleteUnleased` | NTF5-82, 83 при двух репликах (N10); проба «резерв, затем `DEFER(ob_stream_pace)`, взята снова — письмо ушло, `23505` нет» (заказ, N10) |
| CX5-08 | З3 п.2, п.4, п.7 | аренда заявки; вызовы вне транзакции; окно в каждой попытке; классификатор — своя функция | NTF5-18 (а)–(е), 67 (а)–(в), 62 (в); модульная проба классификатора на 16 кодов (N3) |
| CX5-09 | З3 п.8, §5 | `optional bool exists`; противоречивые ответы — вторая строка, в кэш не пишутся | модульная проба классификатора (N3) |
| CX5-10 | З9 п.3, З23 п.4, §9 | кэш только полных ответов; триггеры службы доступа; опора в ребре | проба триггеров (K3); NTF5-93 |
| CX5-11 | З23 п.3 | прямая keyset-выборка без сужения; кодек `kv1.`; комментарий о хранении | NTF5-68 (з)–(к), 66 |
| CX5-12 | З9 п.2, З8 п.4 | страница — одна транзакция после вызовов; исход области — один раз; счётчик в той же транзакции | NTF5-67 (а)–(в); проба «повтор страницы не удваивает» (заказ, N7) |
| CX5-13 | З16 п.2, п.3 | `RequireScope` в каждом освобождённом use-case; гейт метод ↔ право | NTF5-44 (б), 103 (в), 49 (б), (г); гейт З16 |
| CX5-14 | З13 п.3, п.4 | `Visible` на тип; без своего клиента; без мягкого прохода; повтор хранится | NTF5-45, 45 (а), 90 |
| CX5-15 | З13 п.1 | одна выборка с видимостью; один конструктор отказа | NTF5-46, 39, 17 |
| CX5-16 | З13 п.2 | один кодек; порядок из индекса; разбор до `Check` в замыкающейся функции | NTF5-47 (а)–(и), 48, 110; три гейта пагинации |
| CX5-17 | З15 | строка на пару; `DELETE` при снятии; одна функция «нет → пара»; исчерпывающее отображение `Check` | NTF5-96, 97, 99, 100, 101, 104, 106 |
| CX5-18 | З7 п.1, З20 | одна функция правила; таблица «ручка → развёртывание»; страж по читаемым | NTF5-53, 54 на двух корнях, 34, 72; `TestDeclaredKnobHasAReader`, `TestServiceDeclaringPostureKnobsHasABootGuard` |
| CX5-19 | З12 | голова нити в `Claim` исключает второе взятие пары (форма отсутствия ключа — CX5-52); корень — наименьший `sent_at` строки адресата; ключ — id строки | NTF5-75, 95, 108; проба «два письма пары в полёте» (заказ, N8) |
| CX5-20 | З10 п.1 | владелец — ключ ведомости источников | NTF5-55, 56; инъекция вложенного каталога (F2) |
| CX5-21 | З23 п.1 | путь `Resolve`; надзор без сверки перечня на пути не стоит | NTF5-68 ветка `user:usr-op` для обоих методов |
| CX5-22 | З23 п.2 | обязательность → форма → чтение | NTF5-68 (г)–(ж) |
| CX5-23 | З6 п.1 | событие этапа в транзакции перехода; строки — раскрытием | NTF5-66, 67 |
| CX5-24 | З24 | Р14 без условия на исход; блокировка «извещение → события»; id строк ленты до каскада; `feed.DeleteUnleased` вместо SQL `notify`; арендованная строка откладывает извещение до следующего прохода; каскад `FK`; партии | NTF5-50, 51, 92; проба C5 `DeleteUnleased` с близнецами; проба N4 «извещение с отложенной строкой и открытым событием старше срока — удалено вместе с ними» |
| CX5-25 | З22 | одна константа; гейт против модели пина | NTF5-21; гейт З22 |
| CX5-26 | З3 п.1, З25 | момент приёма усечён один раз; фиксация копирует | NTF5-01, 02, 18 (б), (в); `TestOperationTimestampsAreTruncatedEverywhere` |
| CX5-27 | З16 п.4, З18 п.6 | единственный слушатель Х5; REST внутреннего сервиса — только внутренний mux; секрета нет | NTF5-26, 49; гейт изоляции (З19) |
| CX5-28 | З21 п.1, п.2 | одинаковое значение на репликах, агрегация `max` в правилах; увеличение в транзакции исхода — CX5-54 | проба правил на двух рядах (D2) |
| CX5-29 | З6 п.2, З7 п.3 | порядок блокировок; снятие напоминания записью | NTF5-112…115; пробы «переход во время приостановленного раскрытия» и «`dueAt` × `Start`», 20 повторов (заказ, N7) |
| CX5-30 | З8 п.2–п.6 | отдельная таблица кандидатов; повтор — путь раскрытия; снятие и вставка — одна транзакция | NTF5-111, 62 (а); проба «кандидат не берётся конвейером; повтор с `ADDRESS` при существующем адресате» (заказ, N7) |
| CX5-31 | З10 п.2, п.3 | `NULL` + `*time.Time` + `CHECK`; перепись читателей командой | NTF5-116, 117; перепись в PR F3 |
| CX5-32 | З16 п.1, п.3 | звено прав `notify-api` по аннотации; гейт | NTF5-121; гейт З16 |
| CX5-33 | З17 | принципал из trust-aware пары; без запасного; `nop` из каталога | NTF5-118 (а), (в), 26 (г), (е), 122 (д1), (д2) |
| CX5-34 | З2, З3 п.5, п.6 | функции фундамента на транзакции; `ErrAlreadyDone` → откат; `READ COMMITTED` | NTF5-118, 119 (а)–(д), 122 |
| CX5-35 | З4 | движок не поднимается; условие для соседа | предикат «`NewReconciler` в `services/notify` — 0» (N4) |
| CX5-36 | З14 п.2 | окно из ручки; ноль невыразим; `CacheMaxEntries` явно | NTF5-120; гейт окна отзыва |
| CX5-37 | З2 п.1, п.9 | четыре функции поимённо; граница с NTF-3 по Ф4 | NTF5-122; предикат DoD 10.1 п.2а (а) |
| CX5-38 | З2 п.1–п.3, п.5 | методы `TxRepo`; `pgx.Tx`; без `table`; одна копия в корне; построитель без запасного | NTF5-122 (а), (в), (д1), (д2); ревью диффа корня |
| CX5-39 | З20, §10 | порядок тегов; TW последним; один коммит подъёма | строка в задачах (заказ диспетчеру); `TestRevocationWindowIsDeclaredPolicy` |
| CX5-40 | З14 п.3 | верх из `Ceiling`; проба `Ceiling + 1s` | NTF5-54 (д) |
| CX5-41 | З14 п.1 | одна функция сборки; вызов `listnarrow.New` — 1 / 0 | NTF5-120 (б); предикат (N2) |
| CX5-42 | З2 п.1, п.2, п.9 | `TxWriter` вне `FullRepo`; без типового утверждения; надстройка — строка NTF-3 | ревью диффа сигнатур; строка диспетчеру (§13) |
| CX5-43 | З2 п.4 | `ErrNilTx` первым оператором; «своя транзакция» — пуловые методы | буква `nil` в NTF5-122 (заказ исполнителю corelib, C2) |
| CX5-44 (б) | З2 п.5 | Ф3, Ф4 — проверка и один вызов | гейт замыкания З2 п.7 |
| CX5-44 (а) | — | снят записью на `367b9482` (заменён CX5-47) | — |
| CX5-45 | З18 п.1–п.3 | одно поле адреса без умолчания; псевдоним ключа; одно ребро | `TestRouteWiring_NotifyKeysShareOneConnection` с близнецом `vpc`; NTF5-49 (б) на стенде |
| CX5-46 | З18 п.4 | явная установка `notify` в пробе; близнец без адреса | `TestRouteWiring_NoNotifyAddressNoNotifyKeys` |
| CX5-47 | З2 п.5–п.7 | замыкание Ф1…Ф4 без переменных пакета, `ctx.Value`, окружения; тела CAS-помощников неизменны | гейт замыкания с инъекцией `defaultRegistry` |
| CX5-48 | З18 п.5 | строки перечня — в коммите сервиса; импорт — со строками всех публичных сервисов; S1 после ключа | `TestAllowlist_EveryPublicRPCIsRoutable`, `TestRouteWiring_EveryAllowedMethodResolvesOnTheRealBackends` |
| CX5-49 | З26, §0 | таблица «шаблон × атрибут × откуда значение × законен ли нуль» на 19 шаблонов, три атрибута, два пути вызова; `endsAt` — `optional` в 14 шаблонах, `required` в 5 `MAINTENANCE`; `NULL` → поле не задано, одной функцией; `when: endsAt`, тема без `endsAt`; 38 эталонов | NTF5-57, 73, 107; эталоны `.eml` 28 без `endsAt` (N11) |
| CX5-50 | З27, З3 п.2, §6 | «аренда свободна» — `lease_until IS NULL OR lease_until <= $now` на трёх таблицах; вставка без аренды; токен на взятие вместо `$me`; часы `notify` параметром | NTF5-18 (а); проба «упавшая реплика держит аренду — другая берёт после срока» с близнецом (заказ, N3) |
| CX5-51 | З9 п.1, п.4, §6 | `fanned_out_at` ставит последняя страница, отдельно от `closed_at`; взятие и `fanout_pending` его читают; `scope_done`/`page_token` `NULL` — «не начато», пустая строка закрыта `CHECK` | NTF5-66, 67; проба «`allAccounts` раскрыт на двух страницах — следующий проход `ListAccounts` не зовёт, `fanout_pending` = 0» (заказ, N9) |
| CX5-52 | З12 п.1, З10 п.4, §4 | отсутствие `thread_key` — `NULL` с `CHECK`, `*string`; голова нити в `Claim` с формулой `NoActiveLease`; строка правки `Claim` в §4 | NTF5-75, 95, 108; проба C5 «две строки без ключа — один `Claim` выдаёт обе; две строки одного ключа — одну» |
| CX5-53 | З2 п.5 | Ф1, Ф2 судят `p.IsAnonymous()`; сравнения с `Principal{}` нет | буквы NTF5-122: `{Type: "user", ID: ""}` и `{system, anonymous}` → `ErrEmptyPrincipal`, строк операции 0; близнец — полная пара, строка есть (заказ, C2) |
| CX5-54 | З21 п.1, §4 | `feed.OutcomeObserver` — последним действием `Ack` и только в ветке, изменившей строку; счётчики — одна функция, один оператор в порядке `(name, labels)` последним в каждой транзакции; строка порта в §4 | проба C5 «повтор `Ack` с тем же токеном не зовёт наблюдателя»; проба N10 «ответ `Ack` потерян, повтор — `SENT` = 1»; проба N9 «две страницы и переход одновременно — `40P01` 0» |

Неотображённых пунктов нет: 54 из 54 (CX5-01…28, 29…36, 37…41, 42…44, 45…48 первичных разборов и
CX5-49…54 пересверки на `a43a19fa`; CX5-44 — двумя строками, (а) снят разбором на `367b9482`).
Отображения CX5-05, 07, 24, не выдержавшие пересверку на `a43a19fa`, переписаны в редакции 2.

## 12. Что замысел не делает

- Не меняет наблюдаемого поведения приёмки: ни одного нового отказа, исхода, поля или пути.
  Решения, которые близки к этому краю, названы строками автору приёмки (§13), а не внесены.
- Не заводит поток подписки, второго слушателя `notify`, второго соединения края к `notify`.
- Не правит форму носителя Х5, поле адреса края, конвейер доставки NTF-1 сверх портов З12 п.4 и
  З21 п.1 и условий сервера ленты З10 п.3, З12 п.1, справочник `Resolve`, экраны консоли.
- Не добавляет подметальщику условия на исход строки доставки: Р14 исполняется как написана (З24).
- Не поднимает движок `Reconciler` в `notify` (З4).

## 13. Открытые решения и зависимости

**Открытых решений нет.** З1–З27 приняты; выборы по CX5-35 (движок не поднимается), CX5-14 (г)
(повтор ссылки хранится), CX5-10 (в) (ограничение базы, а не гейт дерева), CX5-28 (одинаковое
значение и агрегация `max`), CX5-24 (Р14 без условия на исход, арендованная строка откладывает
удаление до следующего прохода), CX5-52 (голова нити, а не «нет арендованной строки того же ключа»),
CX5-50 (часы `notify` и токен на взятие) сделаны.

**Зависимости — предметы соседей с предикатом снятия:**

| № | зависимость | состояние на 2026-09-30 | предикат снятия |
|---|---|---|---|
| Е1 | NTF-1 одобрена; служба `notify`, конвейер, `feed.Put`, сервер ленты посажены | приёмка ✅ (`29cfa368`); кода нет | `git ls-tree origin/main services/notify` непуст; пробы NTF-1 зелёные |
| Е2 | NTF-3 одобрена; справочник `Resolve`, контакты аккаунта, настройки посажены | приёмка ✅ (`c26cc7cc`); кода нет | пробы NTF-3 для Р7, Р20, Р29 зелёные на стволе |
| Е3 | NTF-4 в редакции по Д20 (2) одобрена | запись ревью на `5cb8057d` отсутствует | `docs/specs/reviews/sub-phase-NTF-4-…/<отпечаток>.yaml` с `APPROVED` |
| Е4 | край по NTF-4 Р20: `notifyInternal`, строка `nop`, поле адреса без умолчания, ключ `notify` — псевдоним (З18) | кода нет | пробы NTF4-93, 94 зелёные; проба З18 п.3 зелёная |
| Е5 | теги corelib Х5, Х1 | не выпущены | тег в `git -C corelib tag` и пин kacho на нём |
| Е6 | замысел NTF-1 одобрен с тем, на чём стоят З8 п.5, З12 п.1, З21 п.1, З24: `Ack` снимает аренду при каждом исходе, «нет действующей аренды» — `lease_until IS NULL OR lease_until <= now()`, следствия `Ack` — только на изменившей строке (M18) | редакция 1 `9bfa92be`, вердикта нет | запись `APPROVED` на отпечаток замысла NTF-1, и в нём эти три утверждения (`grep` M18 даёт 4 строки); если одобренная редакция их меняет — пересверка этого замысла |

**Строки диспетчеру (заказы соседям, не блокируют этот замысел):**

- автору NTF-4 (Р20): происхождение адреса ключа `notify` — то же поле, что у `notifyInternal`, без
  умолчания, одно соединение (З18 п.1, п.2; CX5-45); `EveryBackendKeyHasAConsumer` на ключе
  `notifyInternal` без строк `notify` в перечне — красный (M4), поэтому ключ `notifyInternal`
  садится не раньше первых строк перечня `notify` (NTF-3 либо S1 этой под-фазы);
- автору NTF-3 (Р18): «вызывающий терминальной записи ставит строку `operation-failed`»; «открывает
  свою» — пуловый метод, не режим Ф4; перевод исполнителя на Ф4 — вместе с `TxWriter` службы
  доступа, повторяющим выбор текста её надстройки (З2 п.9; CX5-42, CX5-43); таблица контактов с
  ключом `(scope_type, scope_id, category)` (З15 п.1);
- задачам corelib (Р23), NTF-1, NTF-4: «не поднимать пин kacho на тег с записью окна `notify` вне
  изменения S1 NTF-5» (З20; CX5-39);
- любой под-фазе, которая поднимет движок `Reconciler` над таблицей операций `notify`: `OutcomeSkip`
  при живой заявке, `OrphanGrace ≥ 1h` явно (З4; CX5-35);
- автору NTF-1 (пакет `feed`, замысел З8–З10): правки этой под-фазы в `feed` — фрагмент
  `feed.NoActiveLease` вместо трёх копий условия аренды; ветка `NULL` срока в условии `Claim`
  (`expires_at IS NULL OR expires_at > now()`); голова нити в `Claim`; порт `OutcomeObserver`
  последним действием `Ack` в ветке, изменившей строку; `DeleteUnleased` (З10 п.3, п.4; CX5-05,
  CX5-52, CX5-54, CX5-24). Если NTF-1 сядет первой, эти правки ложатся поверх её `feed` в T2, а не
  заводят второй путь;
- исполнителю corelib (C2): комментарии «`NewRepo` возвращает `FullRepo`» — 3 места (M23) — правятся
  тем же изменением, что тип результата (З2 п.1).

**Строки автору приёмки (неблокирующие, о точности формулировок):**

- Р2, DoD 10.1 п.4, 10.2 п.5: «по тому же соединению / второго соединения нет» верно при псевдониме
  ключа (З18 п.2); можно сослаться на него (CX5-45);
- DoD 10.1 п.4: «эта под-фаза их не правит, кроме импорта» — проба (ii) правится явной установкой
  `notify` и получает близнеца (З18 п.4; CX5-46);
- Р23: остаток «флаг из окружения» дополняется переменной пакета и контекстом — держит гейт
  замыкания (З2 п.7; CX5-47);
- Р10 шаг 2: `done` читается хранилищем фундамента на пуле, а не в транзакции взятия (З3 п.3) —
  следствие DoD 10.1 п.2а, наблюдаемо равносильно.
