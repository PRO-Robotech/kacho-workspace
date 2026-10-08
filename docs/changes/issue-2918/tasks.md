<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2918 (NTF-3, модули kacho подключаются к сервису уведомлений) — маршрут работ

> **Что этот документ.** Маршрут исполнения приёмки NTF-3 и замысла `design.md` рядом: полосы,
> исполнитель по базе маршрутизации, репозиторий и пути, предикат снятия, зависимости (`after`),
> уровень риска, волны. Это не трекер. Состояние полос живёт в задаче `PRO-Robotech/kacho#2918`,
> в `PRO-Robotech/corelib#77`, `PRO-Robotech/kaname#484` и в запросах волн в ветки эпиков
> (`2914-notify`, `77-notify`, `484-notify`).
>
> **Редакция 20 · 2026-10-08 — под действующую приёмку редакции 42** (`1d7d2ad0…73ba`, одобрена кругом 3,
> событие — `PRO-Robotech/kacho#2918` 2026-10-07T15:33Z) и замысел редакции 17. Редакции 1–19 стояли на
> приёмке редакции 33 (`ac1f9fc9…`) и не знали Д129, Д133, Д134. Переписаны §0–§6: влитое отмечено (§3),
> добавлены полосы ограды — corelib FC и kacho FM0, FM-c, FM-v, FM-n, FM-r, FM-s, FM-i (сторона модулей:
> `R_E`, `g_E`, факты объекта, одна строка намерения на событие); S2-B9 и S2-B4 переписаны на
> `ListEventAudience` вместо `ListProjectAudience`, порядок S2-B9 → S2-B4; остаток B1 (vpc — стенды
> пересоздаются по Д12; nlb) — полосы B1v, B1n; B2–B5 и пп. 5–8 §0.1 приёмки (S2-B7k, S3-C1…C4, X3, X4e)
> маршрутизированы сейчас, деление «Основа / после Основы» (редакции 17–19) снято; новая полоса S2-B7L —
> подписка с отбором по меткам (решение владельца 2026-10-08 (2)) за зависимостью Е9. Уровень полос —
> `scripts/lane-tier.sh`, волны — `scripts/plan-precheck.sh` (§5). Строки редакций 1–19 ниже — история;
> их утверждения о состоянии (Е1–Е6, теги, Основа) заменены §1–§6 этой редакции.
>
> **Редакция 1 · 2026-09-30 — проект маршрута по замыслу редакции 1** (заход в форме Д26: каждая
> строка §11 и §11а замысла стоит в предикате своей полосы).
>
> **Редакция 2 · 2026-09-30 — по замыслу редакции 2** (пересверка `89d1f0ad`): УК3-44 в S3-C2, УК3-45 в
> S2-B4, S2-B5, S2-B7, УК3-46 в S3-C3; УК3-31 на обе половины в S1-A7; место установки личности nlb и
> compute; проба `AsComponent` в X1.
>
> **Редакция 3 · 2026-09-30 — по замыслу редакции 3** (пересверка `3730bca2`, CX3H-02): личность прохода
> compute не ставится — снято из S1-A2 и S2-B3; вызывающих `AsComponent` два; УК3-31 в S1-A7 — близнец nlb
> и строка-исключение входа compute с предикатом снятия; УК3-39 в S2-B3 — сравнение с базой на машине с
> привязками; третий исход `AsComponent` в X1 (CX3B-25 (4)); счётчик отказов приёма в S2-B4 (CX3H-01 (г)).
>
> **Редакция 4 · 2026-09-30 — по замыслу редакции 4** (пересверка `374789b5`, CX3I-01…04, CX3J-01; Д33,
> Д34): Е1 — зависимость от одобрения записи реестра NTF-1, а не открытое решение; новая полоса X2-F —
> форма `fanout` и запись реестра `treehygiene` одним тегом, отдельным от раннего тега X2; подъём пина на
> тег X2-F — внутри изменения S2-B1 вместе с миграциями функций (не X5); правило версий тела,
> извлечение входов, `name` ключом, строка сигнала из одного источника — X2-F (форма строки сигнала и
> Go-половина — X2); УК3-49 — X2-F, S2-B1; УК3-50 — S2-B1; позиция ленты — тип и кодек
> `inbox.Position`, УК3-47, УК3-48, обвязка NTF3-161 (г) — S2-B7; единственный генератор позиции — S2-B4.
>
> **Редакция 5 · 2026-09-30 — по замыслу редакции 5** (пересверка `3dbb8b23`, CX3J-01 (б), CX3K-01…03):
> тег X2-F выпускается, когда у S2-B1 сняты все прочие зависимости (S1-A1…A4, тег X2 в kacho, Е1, Е6), —
> код X2-F и выпуск тега разведены; от выпуска тега до посадки S2-B1 пин corelib в kacho не поднимает
> никакое изменение, кроме S2-B1 (ограничение эпика, новая Е6); УК3-51 и обвязка NTF3-82 (м) с двумя
> масками, позиции JSON-строкой, гейты дома SQLSTATE — S2-B7; УК3-52 (колонка мигрированной схемы) вместо
> текстового `grep` — S2-B4.
>
> **Редакция 6 · 2026-09-30 — по решению диспетчера Д37** (замысел редакции 6): выпуск тега X2-F — после посадки
> N11 NTF-1; строка Е6 называет решённый порядок окон. Иного не меняет.
>
> **Редакция 7 · 2026-09-30 — к замыслу редакции 7** (Е6 снята решением диспетчера Д37): строка Е6 §1 —
> «снята», предикат снятия — рёбра Д37 вместо строк ограничения в маршрутах соседей; окна NTF-4 ребром не
> упорядочены и держатся правилом Д37. Полос и рёбер не меняет.
>
> **Редакция 8 · 2026-09-30 — по решению диспетчера Д41** (уточняет Д37; замысел редакции 8): окна NTF-4 —
> (2) в порядке эпика, до X2-F; теги X1, X2, X3 и X2-F — после посадки S3-C2 `issue-2919`. Строки Е4, Е6
> и §0 «Выпуск тега X2-F» — по Д41. Полос не меняет.
>
> **Редакция 9 · 2026-09-30 — к замыслу редакции 9** (заход отображения по Д26, остаток пересверки
> `b34a411e`): строка Е4 — на редакцию 9; строка X5 и §0 «Теги X1, X2, X3» называют подъём kaname с X4,
> сдвигающий пин corelib в kacho, подъёмом пина corelib под тем же ограничением. Полос и рёбер не меняет.
>
> **Редакция 10 · 2026-09-30 — к замыслу редакции 10** (заход отображения по Д26 на ревью замысла роли
> `design-reviewer`, запись `97c51264….yaml`, коммит `38283c50d`): X3 — терминальная запись под личностью
> компонента `(<служба>, operations)`, `Reconciler` — транзакция на кандидата, классификатор исходов,
> УК3-53, УК3-54 (К1, М1); тег X3 — после посадки S2-B1, относительно окна TW — правилом Д37 при выпуске
> (В4); S3-C3 — пара корня модуля, УК3-55 (К1); S2-B5, S3-C4 — срок константой пакета, `Resolve` сводки вне
> транзакции адресата, УК3-56, УК3-57 (К2); S2-B9 — клиент справочника срока не ставит, предикат (К2);
> S2-B2 — один оператор NIC `Attach` и `SetAddressReference` (В1, В2); S2-B4 — пропуск позиции на повторе
> назван (В3); Е4 — на редакцию 10. Новых полос нет; новое ребро одно — тег X3 после посадки S2-B1.
>
> **Редакция 11 · 2026-09-30 — к замыслу редакции 11** (заход отображения по Д26 на пересверку классов
> `f6809e98….yaml`, коммит `26e8a652d`): X3 — взятие кандидата `Reconciler` с условием сироты целиком тем
> же порогом (CX3L-01), `FailedNotify` одним значением и проверка пары конструктором (CX3L-02, CX3L-03),
> счёт `Sweep` — только разрешённые (CX3L-04), `Resolve` под контекстом прохода без пары (CX3L-05), проба
> УК3-58, близнец УК3-54; X1 — `journaltx.NewOptions`, отказ нулевых `Options`; S1-A4 — четыре потребителя
> флага; S3-C3 — корень строит `FailedNotify` из того же `Options`, близнецы УК3-55; Е4 — на редакцию 11.
> Полос и рёбер не меняет.
>
> **Редакция 12 · 2026-09-30 — к замыслу редакции 12** (заход отображения по Д26 на пересверку классов
> `7bc43f21….yaml`, коммит `9ef3435bc`): X3 — `NewWorker` и `NewReconciler` с позиционным `FailedNotify` и
> возвратом ошибки, пакетный реестр с явным `NoFailedSender`, проба УК3-60 corelib (CX3M-01); X5 — подъём
> на тег X3 правит шесть вызывающих `NewReconciler` в kacho и один в kaname явным `NoFailedSender`; S1-A4 —
> держатели `Options` отвергают нулевые при сборке, УК3-61 (CX3M-02); S3-C3 — `Worker` корня в пяти
> модулях, 54 вызова `operations.Run` → `RunWithWorker`, корни registry и geo поимённо, гейт УК3-59,
> УК3-60, размер M → L; Е4 — на редакцию 12. Полос и рёбер не меняет.
>
> **Редакция 13 · 2026-09-30 — к замыслу редакции 13** (механизм для К1 и К2 ревью замысла `97c51264` —
> исключение из Д26 по заданию диспетчера; прочее — отображение пересверки `5400c528….yaml`, коммит
> `a5df02586`): X3 — `NewNotifyingRepo`, метод `pgRepo.FailTerminal` своей транзакцией под парой с
> классификатором и запасной записью, выбор в ветке ошибки исполнителя по `terminalFailer`; `Worker`,
> пакетный реестр, `NewWorker`, `NewReconciler`, `Reconciler.Sweep` не меняются (транзакция кандидата,
> УК3-58 и правки `NewReconciler` сняты); X5 — подъём на тег X3 правок вызывающих не несёт (CX3N-01 снят);
> S3-C3 — корни пяти модулей строят `NewNotifyingRepo` вместо `NewRepo`, 54 вызова `operations.Run` и
> `lroreconciler` не трогаются (CX3M-01, CX3N-02, CX3N-04, CX3N-05 сняты), гейт УК3-59 по имени импорта
> (CX3N-03), размер L → M; S2-B9 — клиент справочника отвергает вызов без срока, УК3-62 (К2); S2-B4 — приём
> клиента справочника не импортирует; S2-B5, S3-C4 — исход `ErrCallWithoutDeadline` у вызывающего; S1-A4
> — поимённо registry и geo по новому механизму; Е4 — на редакцию 13. Полос и рёбер не меняет.
>
> **Редакция 14 · 2026-09-30 — к замыслу редакции 14** (место механизма К1 без цикла импортов —
> то же исключение из Д26; прочее — отображение пересверки `6cf94b11….yaml`, коммит `cf1886152`): X3 —
> `operations` объявляет интерфейс `FailedNotify`, `TerminalQuerier` и `FailTerminalCAS` и не импортирует
> ни `journaltx`, ни `auth`; ставящая функция, значение подключения и классификатор (со строкой
> `ErrNotFound`) — в новом подпакете `operations/opsnotify`; `NoFailedSender` снят; УК3-63 (граф импортов),
> УК3-64 (`ErrNotFound`) (CX3O-01, CX3O-04 (а)); S3-C3 — корни строят `opsnotify.New`, три комментария с
> `operations.NewRepo` переписаны, предикат прозы (CX3O-04 (б)); S2-B9 — утверждения сужены до клиента
> `internal/directory`, `ErrCallWithoutDeadline` без обёртки, третий близнец УК3-62 (CX3O-02, CX3O-03);
> S2-B5, S3-C4 — `errors.Is` до `resolvecell.Of`, метка `no_deadline`, близнецы УК3-56, УК3-57 (CX3O-03);
> Е4 — на редакцию 14. Полос, рёбер и размеров не меняет.
>
> **Редакция 15 · 2026-09-30 — к замыслу редакции 15** (заход отображения по Д26 на пересверку классов
> `350b291d….yaml`, коммит `f18d0252c`; механизм не меняется): X3 — УК3-65 и УК3-66 на дереве corelib
> (вызывающие `FailTerminalCAS` только в `operations` и `operations/opsnotify`, реализация `FailedNotify`
> одна), УК3-67 и внешний тестовый пакет для УК3-53, УК3-54, УК3-60, УК3-64 (CX3P-01 (а), CX3P-02 (а),
> CX3P-03), комментарий `FailTerminalCAS` (CX3P-01 (б)), исход УК3-63 по числу; S3-C3 — УК3-65, УК3-66 на
> дереве kacho, УК3-59 в расширенной форме (третий аргумент `NewNotifyingRepo` — результат
> `opsnotify.New`, CX3P-02 (б)); X5 — УК3-65, УК3-66 на дереве kaname при подъёме на тег X3; §3 — диапазон
> `УК3-01…67`; Е4 — на редакцию 15. Полос, рёбер и размеров не меняет.
>
> **Редакция 16 · 2026-09-30 — к замыслу редакции 16** (заход отображения по Д26 на пересверку классов
> `14176770….yaml`, коммит `530d9c251`; механизм не меняется): X5 и S3-C3 — контроль в обратную сторону
> УК3-65 и УК3-66 по каталогу закреплённой corelib исполняется `grep -r` (или `git grep --no-index`) после
> проверки предпосылок; провал предпосылки — «не выполнилось», а не 0 (CX3Q-01); Е4 — на редакцию 16.
> Полос, рёбер и размеров не меняет.
>
> **Редакция 19 · 2026-10-04 — Д113 (б) NTF-4** (ревью замысла NTF-4 `1e2562a8…`, R9-1, R9-3; пересверка
> `1e2562a8…`, RV9-01, RV9-02). S2-B7 в части Основы переходит в волну Н3-Ф3а: корень, развёртывание и проба
> поверхности `notify-api` NTF-4 и регистрации S2-B7 — один запрос волны, порядок S3-C2н → S3-C7н → S2-B7
> (общий файл записи З9). Н3-Ф4 идёт после Н3-Ф3а без S2-B7; строка Е2 §1 — гейт S2-B7 на голове волны.
> Прочие полосы, рёбра и размеры не меняются.
>
> **Редакция 18 · 2026-10-03 — Д100.** Ответ на В1 — «да»: носитель `notify-api` из NTF-4 (X5, S3-C2,
> S3-C4…S3-C7 в части носителя, без `InternalSuppressionService`) входит в Основу; волна Н3-Ф3а — без условия, с
> предикатом старта «деление NTF-4 одобрено» (§4). Прочие строки не меняются.
>
> **Редакция 17 · 2026-10-03 — объём «Основа» (Д96) и режим ревью волны (Д97).** Новые §4 «Основа» и §5
> «После Основы»; полосы X4, S2-B7, S3-C5, S3-C6 делятся на часть Основы и часть после неё (имена частей —
> в §4, §5). Прочие строки, рёбра и размеры не меняются.

## 0. На чём стоит маршрут

| вход | координата | ревизия / отпечаток | состояние |
|---|---|---|---|
| приёмка NTF-3 | `docs/specs/sub-phase-NTF-3-kacho-modules-notifications-acceptance.md` | `1d7d2ad0a39805c3345efb48aee562d76a812e6a19087be427982f7d0d8373ba` (редакция 42; сценариев-номеров 189, снято 16, живых 173; стадий 3) | `ACCEPTED`, круг 3 — запись `docs/specs/reviews/sub-phase-NTF-3-kacho-modules-notifications-acceptance/1d7d2ad0….yaml` (коммит `6b57d573c`), событие — коммит `263360803`. Текст редакции 42 на ветке `issue-880` не закоммичен: на `HEAD` лежит редакция 33 (`git log -1 -- <путь>` → `1ef875dc7`); посадка текста — шаг автора приёмки, не этого маршрута |
| замысел | `design.md` рядом | редакция 17 | вердикта нет; по решению владельца 2026-10-04 не ворота (§1) |
| ветка эпика kacho | `PRO-Robotech/kacho` `2914-notify` | `515e017c87` (2026-10-08, после #3099) | пины: corelib `v1.10.1-0.20261007153021-18d105d0f50a`, kaname `v0.4.1-0.20261007174715-33010d434767` (`go.mod`) |
| ветка эпика corelib | `PRO-Robotech/corelib` `77-notify` | `1177490` (#102) | атрибутов ограды у `resource-event` нет: `git grep -n 'authz_rev\|parent_chain' origin/77-notify -- notify/ cmd/notifygen/` → 0 |
| ветка эпика kaname | `PRO-Robotech/kaname` `484-notify` | `33010d434767` | есть `CurrentAuthzRevision` (K1, #632); `ListEventAudience`, `SetPublicReadPublication`, `generation`, `tuples` — только в открытом #673 (голова `1197a78edd8e`) |

## 1. Правила маршрута

- **Код — по одобренной приёмке; замысел не ворота** (решение владельца 2026-10-04). Ревью замысла
  редакции 17, пересверка классов и полный набор рецензентов на сведённом — один раз, перед запросом
  эпика в `main`. Правка приёмки, если её потребует реализация, — новым кругом автора приёмки, а не
  кодом мимо неё (так шли редакции 40–42 по находкам K2).
- **Проба до кода** в каждой полосе исполнителя кода: проба с ID сценария в имени (`NTF3-NN`) либо с
  номером заказа (`УК3-NN`) красная на голове волны, исход напечатан; затем код; та же проба зелёная —
  одним изменением (ban #12). Отрицательная проба — с близнецом, отличающимся одним фактом.
- **Заказанные пробы** (§11а замысла, `УК3-NN`) входят в предикат своей полосы наравне со сценариями.
- **Гейт** печатает объём осмотренного, падает на пустом обходе и доказан инъекцией в обе стороны.
  Integration-группа даёт тот же вердикт трижды подряд.
- **Уровень полосы** — `scripts/lane-tier.sh` (R0 / R1 / R2); объявленный уровень выше вычисленного
  допустим, ниже — нет. Уровень в таблицах §4 — вычисленный по путям полосы либо объявленный выше него
  (помечено «↑»). R2 — полный набор ролей уровня; R1 — один рецензент на собранную волну.
- **Единица сдачи** — коммит исполнителя в ветке полосы; свою ветку исполнитель отправляет сам. Волна —
  единица запроса в ветку эпика: полосы сводятся в одну ветку, проверки — на сведённом, запрос один;
  зависимые полосы идут в одну волну. Сведение, запрос, вливание и снятие веток — `git-operator`.
  Посадка — только при коде 0 у `landing-precheck.sh` и `merge-readiness.sh`; `Closes` — только с
  комментарием `DoD-proof @<ревизия>` в задаче, иначе `Refs`.
- **Пины** — на головы веток эпиков (Д64). В волне kacho подъём пина каждого фундамента — отдельная
  первая полоса волны (FM0, P5), прочие полосы волны — на её голове. Контракт службы доступа после
  `PRO-Robotech/kaname#673` ломающий (`reserved` полей регистрации, обязательный `generation`,
  `ListProjectAudience` снят): подъём пина kaname и перевод **всех пяти** модулей идут одной волной В-2
  (замысел З34 «Порядок посадки»).
- **Стенд пересоздаётся** (Д12, Р15): колонки журнала `generation`/`facts` (В-2) и `intent_initiator`
  storage (В-5) — миграциями на пустых таблицах, переходного пути нет. Шаг «пересоздать стенд» —
  страница перехода S3-C5.
- Размер: **S** — до дня одного исполнителя, **M** — два-три дня, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход; «зелёный» — с напечатанным числом исполненного.

## 2. Внешние зависимости

| № | зависимость | состояние на 2026-10-08 | чем проверено | гейтит |
|---|---|---|---|---|
| Е1 | запись реестра исключений `AuditFeedTableWrites` для `resource-event` | **исполнена**: corelib #96 влит в `77-notify` 2026-10-06 (Д120) | `gh pr view 96 -R PRO-Robotech/corelib --json state` → `MERGED` | — |
| Е2 | корень `notify-api`, носитель Х5, край к `notify` | **закрыта** на `515e017c87` | `git ls-tree origin/2914-notify services/notify/cmd/` содержит `notify-api`; край маршрутизирует `notify` (коммит `c7240e305` в #3099) | — |
| Е3 | стадии NTF-1 в ветках эпиков | **закрыта** для маршрута: `services/notify` и `corelib/notify/feed` есть на головах веток эпиков | `git ls-tree origin/2914-notify services/notify/internal/`, `git ls-tree origin/77-notify notify/feed/` | — |
| Е4 | ревью замысла и пересверка классов | по решению 2026-10-04 — не ворота; исполняется перед запросом эпика в `main` | — | запрос эпика в `main` |
| Е5 | строки-ссылки приёмки NTF-1 на Р19, Р24, Р27, Р28 (DoD 12.2 п.4, п.5) | не проверялась этой редакцией | диспетчер — по одобренному отпечатку приёмки NTF-1 | S2-B9, X4e |
| Е6 | одно окно пина за раз (Д37, Д41) | **снята** Д64: пины — на головы веток эпиков | — | — |
| Е7 | ограда службы доступа: K2, K3, факт права — `PRO-Robotech/kaname#673` влит в `484-notify` | **открыта**: PR `OPEN`, голова `1197a78edd8e`, `MERGEABLE`; проверка «правило запроса (заголовок · голова · тело · коммиты)» — `FAILURE`; вердикта посадки нет | `gh pr view 673 -R PRO-Robotech/kaname --json state,statusCheckRollup` | В-2 (FM0), S2-B9, X4e |
| Е8 | форма ограды в corelib (полоса FC) влита в `77-notify` | **открыта**: полоса не начата | `git grep -c authz_rev origin/77-notify -- notify/feed/resourceevent/` → 0 | В-2 (FM0) |
| Е9 | дельта приёмки NTF-3: подписка с отбором по меткам ресурсов (решение владельца 2026-10-08 (2) «в этом релизе»; редакция 42 держит её вне объёма — §6, Д129 (7), предикат возврата там же выполнен решением) | **открыта**: дельты нет | одобренная запись ревью на отпечаток с этими сценариями | S2-B7L |

## 3. Влито

| репозиторий · ветка эпика | PR · merge-коммит | полосы этого маршрута |
|---|---|---|
| corelib · `77-notify` | коммиты `98c3586`, `5065868` (в ветке эпика) | X1 — контракт события `initiator`, `occurred_at`, `name`, `auth.InitiatorOf`, `journaltx` |
| corelib · `77-notify` | #89 · `fd6d603b52ca` | X2 (формы адресата, `notify/spec`), X2-F (функция `resource-event` формы `fanout`) |
| corelib · `77-notify` | #92, #96 | запись реестра `resource-event` (Д120; Е1) |
| corelib · `77-notify` | #95 · `e7d6197fc5dc` | флаг ленты в самоотчёте, серия `kacho_notifications_enabled` (часть S1-A4) |
| kaname · `484-notify` | #605 · `745640d6c296` | X4J — журнал службы доступа с инициатором (NTF3-63); X4D — справочник (`Resolve`, `ListProjectAudience`; последний снимает #673) |
| kaname · `484-notify` | #611, #616 | Д121 (полоса acr чтений справочника), Д122 (посев под `system:kaname-seed`) |
| kaname · `484-notify` | #632 · `22b70ea5d0a7` | K1 — `authz_rev` на исходных строках прав, `CurrentAuthzRevision` (NTF3-179 (г), 180, 183 — пробы в дереве) |
| kacho · `2914-notify` | #3027 · `4517cc69c135` | S1-A1, S1-A2, S1-A8 |
| kacho · `2914-notify` | #3042 · `829e1a26cb18` | S1-A3, S1-A4, S1-A7 |
| kacho · `2914-notify` | #3098 · `504bc7acdc51` | S2-B1 для compute, registry, storage (`journal.yaml`, миграция ленты, функция `resource-event`, шаблоны); vpc и nlb — остаток (B1v, B1n) |

**В полёте, не влито:** `PRO-Robotech/kaname#673` (K2, K3, факт права — Е7).

Пробы в дереве kacho на `515e017c87` (`git grep -ohE 'NTF3[-_][0-9]+' origin/2914-notify -- '*_test.go' | sort -u`):
NTF3-57…62, 64…70, 160, 162; заказы УК3-13, УК3-27, УК3-28, УК3-30, УК3-31, УК3-37, УК3-61. NTF3-68…70, 160, 162 покрыты не у всех
пяти модулей (vpc, nlb — B1v, B1n, S1-A6) и без ограды (В-2). В kaname на голове #673 пробы есть у
NTF3-165…168, 170, 171, 173, 174, 176…186, 189 (сторона службы доступа); нет у NTF3-48, 122, 154
(`git grep -l "NTF3-<N>\b" origin/484-wave-fence-2 -- '*_test.go'`). На голове `484-notify` пробы стороны
службы доступа уже есть у NTF3-23, 26…30, 50, 63, 119, 120, 151 (тот же предикат по `origin/484-notify`).
Заказ УК3-12 (флаг у registry, vpc, nlb; S1-A4 влит #3042) пробы с номером в дереве kacho не имеет
(`git grep -c 'УК3-12' origin/2914-notify -- '*_test.go'` → 0) — его закрывает полоса S1-A6 (§4.3).

## 4. Полосы впереди

Колонка `after` — полосы и зависимости, которые сняты до старта. Уровень — `lane-tier.sh` по путям
полосы (§5 — вывод `plan-precheck.sh`); «↑» — объявлен выше вычисленного.

### 4.1 corelib (`77-notify`)

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| FC | форма ограды (З34): атрибуты `resource-event` `source_version` (`g_E`), `authz_rev`, `project_id`, `account_id`, `labels`, `parent_chain`, у `UPDATED` — `previous_labels`, `previous_parent_chain` в Go- и SQL-половине `notifygen` из одной формы (Р3); колонки журнала `generation`, `facts` в форме журнала фундамента (З5); третья настройка транзакции `kacho_feed.authz_rev` в `journaltx` (значение — из `Options`); отказ функции `resource-event` без токена при флаге `true`; счётчик поколения — таблица и функция базы `next_object_generation` в `notifygen init` и Go-помощник, который её зовёт | `go-implementer` | `notify/feed/resourceevent/**`, `cmd/notifygen/**`, `journaltx/**`, `subscription/**` (форма строки журнала) | УК3-68, УК3-69, УК3-70 зелёные с близнецами; `notifygen -check` зелёный; `go test ./... -race` и интеграция corelib зелёные числом исполненного; поля события подписки на проводе не меняются (`buf breaking` по `proto/corelib/subscription` зелёный) | — | R2 | M |
| X3 | терминальная запись ошибки операции со строкой `operation-failed` (п.7 §0.1 приёмки; З16 редакций 13–16 без изменений): `TerminalQuerier`, `FailTerminalCAS`, интерфейс `FailedNotify`, `NewNotifyingRepo`, `pgRepo.FailTerminal`; подпакет `operations/opsnotify` (`New`, `Ready`, `RunTerminal` через `journaltx.AsComponent` пары `(<служба>, operations)`); `NewRepo`, `MarkError`, `RunSync`, `NewWorker`, `Run`, `RunWithWorker`, `NewReconciler`, `Reconciler.Sweep` не меняются | `go-implementer` | `operations/**` | УК3-53, УК3-54, УК3-60 (половина corelib), УК3-63, УК3-64, УК3-65, УК3-66, УК3-67 зелёные (формы — §11а замысла); проба CAS: повтор не ставит, `RunSync` и `Cancel` не ставят; `go doc` экспортированных `NewRepo`, `NewWorker`, `NewReconciler`, `Run`, `RunWithWorker` до и после совпадают | — | R1 | M |

### 4.2 kaname (`484-notify`)

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| X4e | `ListExpiringCredentials` справочника (п.8 §0.1; Р7, Р19): обязательные границы окна, порядок `(expires_at, id)`, отказы `page_size` вне `[0..1000]` и мусорного `page_token` первым стейтментом, пустой `next_page_token` на последней странице; метод — в перечне звена и каталоге прав (`required_relation reader` на `notification_recipient_directory:root`); перечень звена — `{ResolveSend}` + три метода справочника | `rpc-implementer` (контракт и сервис), `go-implementer` | `proto/kaname/cloud/iam/v1/internal_notification_recipient_service.proto`, `internal/apps/kaname/api/recipientdirectory/**`, каталог прав и перечень звена в композиционном корне | NTF3-122 (а)–(з), NTF3-154 зелёные; `buf lint`, `buf breaking` зелёные; гейты каталога и подстановки печатают три метода справочника | **Е7** (тот же файл контракта), Е5 | R2 | M |

### 4.3 kacho (`2914-notify`)

**Остаток S1 и B1, пересылаемые пути — волна В-1.**

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| B1v | остаток S2-B1 для vpc (Р3, З10): `notifygen init -journal` — `journal.yaml`, миграция ленты, функция `resource-event` и триггер на журнале vpc, шаблон `resource-event` на двух локалях; посев стенда исполняет транзакцию с настройками `journaltx` (флаг, инициатор `system:stand-seed`) — функция базы ставит строку ленты той же транзакцией. Отложение #3098 снимается Д12: стенд пересоздаётся, переходного пути посева нет | `migration-writer`, `deploy-engineer` (посев) | `services/vpc/{journal.yaml,notifications/**,notifications_resource-event.gen.go,internal/migrations/**}`, `deploy/scripts/{vpc-address-pool-baseline.sql,seed-vpc-address-pools.sh}` | NTF3-68, 69, 71 по vpc зелёные; NTF3-162 зелёная (строка ленты от посева); NTF3-160 (а)–(в) в части функции `subnets_outbox_emit_route_table_change`; `notifygen -check` зелёный; `TestNewMigrationCitesAnApprovedAcceptance` зелёный | — | R2 | M |
| B1n | остаток S2-B1 для nlb: то же для журнала nlb (эмиттер модуля и шаг доведения снятия пишут журнал через функцию фундамента с S1-A7; функция базы `lb_status_recompute` — тем же триггером) | `migration-writer` | `services/nlb/{journal.yaml,notifications/**,notifications_resource-event.gen.go,internal/migrations/**}` | NTF3-68, 69, 71 по nlb зелёные; NTF3-160 (б) в части `lb_status_recompute`; `notifygen -check` зелёный | — | R2 | M |
| B2 | vpc: `NetworkInterface UPDATED` на Attach/Detach, `Address UPDATED` на `SetAddressReference` и `DETACHED`, решение «изменилось» в том же операторе; инициатор — из trust-aware пары; правка комментариев `cqrsadapter.go` и `values.prod.yaml`; сужение `ListByInstance` не трогается (З12) | `go-implementer` | `services/vpc/internal/{apps/kacho/services/{nicinternal,addressref},repo/cqrsadapter,repo/kacho/pg,apps/kacho/api/address}/**`, `deploy/helm/umbrella/values.prod.yaml` | NTF3-160 (д), (е), (ж) зелёные; УК3-33; NIC `Attach` — один оператор `WITH prev … FOR UPDATE` + `UPDATE`, «изменилось» — `old_used_by = ''`; `SetAddressReference` — один оператор с изменяющими CTE и `RETURNING` прежнего `used` и `(xmax = 0)`; `git diff` полосы не касается `authzfilter` и `ListByInstance` | B1v | R2 | L |
| B3 | storage `Attach`/`Detach` в `journaltx` с пересланным инициатором; личность `releaseAndDelete` — исполнителя; пересылаемая личность фонового прохода compute **не меняется** (ни `AsComponent`, ни `WithPrincipal` в цикле `FinishStuckDeletes`); строка `Instance DELETED` — инициатор только из принципала контекста (З7, З12, З13, CX3H-02) | `go-implementer` | `services/storage/internal/{repo/pg,apps}/**`, `services/compute/internal/apps/kacho/api/instance/**` | NTF3-160 (г), (з) зелёные; УК3-32; УК3-39 (сравнение с базой на машине с интерфейсом и томом); `git grep -nE '(operations\.WithPrincipal\|journaltx\.AsComponent)\(' -- 'services/compute/*.go' ':!*_test.go' \| wc -l` → 0, контроль тем же предикатом по `services/nlb` → 4 (оба числа — на `515e017c87`) | — | R1 | M |
| S1-A5 | `services/notify/sources.yaml` и гейт переписи по 12 шагам §3; `bundle`/`bundle-check`; таблица видов по полным именам шаблонов; локали; гейты словаря причины и путей кнопок (З29) | `go-implementer` | `services/notify/{sources.yaml,Makefile}`, `internal/repohygiene/notifysourcesledger*.go` | NTF3-01…05, 29 (`bundle` с инъекцией), 31…35, 37, 39, 40 зелёные; NTF3-04 печатает пять подключённых модулей и шаги (1)–(10) у каждого; УК3-05, УК3-06, УК3-09, УК3-24 | B1v, B1n | R1 | M |
| S1-A6 | гейт NTF3-70 на распознавателе `journalwriteforms` — функции базы живым телом, объём по видам файла у **пяти** модулей; гейт NTF3-60; гейт нелокальной установки инициатора; правка границы 3 `journalwriteforms.go` и абзаца nlb `journal.go` (З4, З10) | `go-implementer` | `internal/repohygiene/{journalparity,journalhelper}_test.go`, `internal/repohygiene/journalwriteforms*.go`, `services/nlb/internal/subscriptionjournal/journal.go` | NTF3-60, NTF3-70 (инъекции (а)–(г), пустой обход) зелёные, печать — пять модулей, строк ленты на строку журнала 1, литеральных вставок в журнал 0; УК3-25, УК3-29; УК3-12 — проба с номером заведена либо названа существующая проба флага registry, vpc, nlb с координатой | B1v, B1n | R2 | M |

**Ограда — сторона модулей (FENCE-M) — волна В-2.** Все полосы — на голове FM0 одной волны (§1 «Пины»).

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| FM0 | подъём пинов: kaname — на голову `484-notify` с #673, corelib — на голову `77-notify` с FC; каталог прав края из дескрипторов (`ListEventAudience` и `SetPublicReadPublication` вместо `ListProjectAudience`) и гейт достижимости каталога; гейты дерева kacho — `TestEveryJournalEventRegistersItsMirrorVersion` (NTF3-175), `TestOwnerIntentIsOneEventOfOneObject` (NTF3-187 (а)–(д)), половина kacho `TestPublicReadIsPublishedByItsOwnMethod` (NTF3-186) — красные до полос модулей | `go-implementer` (пины, гейты), `api-gateway-registrar` (каталог края) | `go.mod`, `go.sum`, `gateway/internal/middleware/{embed/permission_catalog.json,permission_catalog_acr_invariant_test.go}`, `internal/repohygiene/{catalogreachability_test.go,journaleventmirrorversion*.go,ownerintentoneevent*.go,publicreadownmethod*_test.go}` | три гейта печатают объём и доказаны инъекциями с близнецами и пустым обходом; `git grep -c ListProjectAudience` по дереву kacho → 0; `permission-catalog-check` зелёный; красное трёх гейтов на голове FM0 напечатано (`RED_PROVEN` для полос модулей) | **Е7**, **Е8**, волна В-1 влита | R2 | M |
| FM-c | compute: токен `R_E` до транзакции записи в сценариях использования и фоновых путях (§3 шаг (14)); счётчик поколения и колонки журнала (миграции из формы FC); факты события и набор намерения — один построитель вида; одна строка намерения на событие с `tuples` и `generation`, вызов на строку (`fgaintent`, применитель, синхронный регистратор) | `migration-writer` (миграции), `go-implementer` | `services/compute/{internal,cmd}/**`, `services/compute/journal.yaml` | NTF3-175 и NTF3-187 по compute зелёные (печать гейтов FM0 называет compute); NTF3-68 по compute с атрибутами ограды; NTF3-182 (поколение намерения = `source_version` строки) | FM0 | R2 ↑ | L |
| FM-v | vpc: то же; снятие сети с маршрутной таблицей и группой безопасности по умолчанию — три события, три строки намерения (`apps/kacho/api/network/delete.go`); функции базы vpc зовут `next_object_generation`; посев стенда берёт токен вызовом `CurrentAuthzRevision` с сертификатом vpc и передаёт его транзакции посева | `migration-writer`, `go-implementer`, `deploy-engineer` (посев) | `services/vpc/{internal,cmd}/**`, `services/vpc/journal.yaml`, `deploy/scripts/{vpc-address-pool-baseline.sql,seed-vpc-address-pools.sh}` | NTF3-175, 187 по vpc зелёные; NTF3-162 с токеном (без токена посев отказывает); NTF3-188 (б) — три намерения | FM0, B1v, B2 | R2 ↑ | L |
| FM-n | nlb: то же; `lb_status_recompute` зовёт `next_object_generation` | `migration-writer`, `go-implementer` | `services/nlb/{internal,cmd}/**`, `services/nlb/journal.yaml` | NTF3-175, 187 по nlb зелёные | FM0, B1n | R2 ↑ | M |
| FM-r | registry: то же; публикация — `SetPublicReadPublication` с `publication_version` и `object_generation`, регистрация публикацию не несёт; переименование — `DELETED` прежнего id и `CREATED` нового по намерению на каждое (`rename_repository.go`, `renameIntents`); синхронный регистратор — вызов на строку, а не на кортеж (`clients/iam/sync_registrar.go`) | `migration-writer`, `go-implementer` | `services/registry/{internal,cmd}/**`, `services/registry/journal.yaml` | NTF3-175, 186 (половина kacho), 187 (а)–(д) по registry зелёные; NTF3-189 (в) — два события переименования; отказ публичного создания без `admin` на реестре не тронут | FM0 | R2 ↑ | L |
| FM-s | storage: то же; функции базы `storage_outbox_emit_source`, `storage_outbox_emit_attachment` зовут `next_object_generation`; отказ пути токена — `UNAVAILABLE` `PEER_UNAVAILABLE` до транзакции | `migration-writer`, `go-implementer` | `services/storage/{internal,cmd}/**`, `services/storage/journal.yaml` | NTF3-175, 187 по storage зелёные; NTF3-179 (а), (в) зелёные (обвязка storage + служба доступа с перехватчиком С26) | FM0, B3 | R2 ↑ | L |
| FM-i | обвязка registry + vpc + служба доступа на пине FM0: доставка события одним вызовом с полным набором, три снятия сети — три намерения, параллельные события одного объекта — разные поколения подряд; объект с id снятого продолжает поколения, переименование, публикация прежнего воплощения — `REJECTED_STALE` | `integration-tester` | `services/registry/internal/clients/iam/*fence*_integration_test.go`, `services/vpc/internal/apps/kacho/api/network/*fence*_integration_test.go` | NTF3-188 (а)–(в), NTF3-189 зелёные трижды подряд (записи С27, С28; посевы С1, С24) | FM-r, FM-v | R0 | M |

**Справочник, приём, API `notify`, край — волна В-3.**

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| S2-B9 | клиент справочника `internal/directory`: `ListEventAudience` (поколение, токен, факты — без преобразования), `Resolve` формы `event` (с `via_subscription`), `self`, `account_owner`, `account_reader`; `resolvecell.Of` — таблица Р7 и клетки Р24, включая `DEFER(audience_pending)`, `EXPIRED(audience_pending)`, `DENIED(audience_horizon)`; формы адресата по пространству (Р27); клиент срока не ставит и вызов без срока отвергает `ErrCallWithoutDeadline` до соединения (З27); второй клиент службы доступа (`clients/kaname_client.go`, NTF-5) не трогается | `go-implementer` | `services/notify/internal/{directory,resolvecell,deliver}/**` | NTF3-15…23, 25, 26, 36, 46…48, 55, 56, 125, 150, 154 (сторона `notify`), 155 зелёные; NTF3-18, 19 — `t0` из времени коммита, задержка напечатана, N прогонов; `git grep -nE 'context\.With(Timeout\|Deadline)' -- services/notify/internal/directory/` → 0 с числом осмотренных файлов; УК3-62 | волна В-2 влита (пин kaname с #673), Е5 | R2 ↑ | M |
| S2-B4 | приём `notify-sender` (Р9, Р24; З19, З34): `ListEventAudience` всех страниц (`KACHO_NOTIFY_DIRECTORY_PAGE_SIZE`) под сроком пакета `ingest` **до** транзакции; одна транзакция «запись + строки аудитории + `INGESTED`»; `inbox_clock`, `inbox_event` с уникальностью `(module, source_row_id)`, позицию выдаёт только оператор `inbox_clock`; барьер и горизонт — клетки Р24 и счётчики `notify_audience_pending_total`, `notify_audience_below_horizon_total`; уборщик снимает строки аудитории вместе с записью | `go-implementer`, `migration-writer` (`kacho_notify`) | `services/notify/internal/{ingest,inbox,migrations}/**`, `services/notify/cmd/notify/**` | NTF3-72, 78, 79, 170 зелёные; УК3-16, УК3-35, УК3-45 (приём), УК3-52, УК3-71; миграция `kacho_notify` вставляет строку `inbox_clock` | S2-B9 | R2 | L |
| S2-B7 | контракт и сервисы `notify-api` (Р9–Р11, Р25, Р29): лента — выдача по строкам аудитории вызывающего без вызова службы доступа; каталог; настройки (`seen_up_to` по З23, ячейка `(notify, OWN_ACTIONS, EMAIL)` с умолчанием `DISABLED`); подписки с `channel` (Р11, Р11а); регистрации класса `public` в ведомости поверхности; гейт графа импортов (З28) | `proto-sync`, затем `rpc-implementer` | `proto/kacho/cloud/notify/v1/`, `pkg/api/kacho/cloud/notify/v1/`, `services/notify/internal/apiserver/**`, `services/notify/servesurface_ledger.go`, `services/notify/cmd/notify-api/**` | `buf lint`, `buf breaking` зелёные; NTF3-73…77, 80…95, 149, 156, 161 (включая (г)), 169 (настройки), 172 зелёные; УК3-20, УК3-21, УК3-26, УК3-34, УК3-45 (отметка), УК3-47, УК3-48, УК3-51; `TestIntegritySQLStateIsDecidedInOnePlace`, `TestErrorMappersTailReturnsAFixedText` зелёные на дереве `notify` | S2-B4 | R2 | L |
| S2-B7k | контакт безопасности аккаунта (п.5 §0.1; Р20, З25): `AccountNotificationContactsService`, `account_id: required` и формат до права, `Check` в use-case после формата, годность контакта — `CheckSubject` по SAN `notify-api`, `UNAVAILABLE` при недоступной службе доступа | `proto-sync`, затем `rpc-implementer` | `proto/kacho/cloud/notify/v1/`, `pkg/api/kacho/cloud/notify/v1/`, `services/notify/internal/apiserver/contacts/**`, `services/notify/servesurface_ledger.go` | NTF3-112…116, 157 зелёные; УК3-23 | S2-B7 (те же файлы контракта и ведомости) | R2 | M |
| S2-B8 | край: REST-маршруты `/notify/v1/…` методов Р25, записи перечня разрешённых методов (внешний gRPC-вход, Д20), каталог прав края — из дескрипторов (З28); `Internal*` — отказ маршрута | `api-gateway-registrar` | `gateway/internal/{restmux,allowlist,middleware/embed}/**` | NTF3-30 (сторона края), NTF3-159 (а)–(е) зелёные; `allowlist/parity_test.go` и `permission-catalog-check` зелёные | S2-B7, S2-B7k | R2 | M |

**Сводка, мгновенные письма, развёртывание, сквозные S2 — волна В-4.**

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| S2-B5 | сводка (Р12, З21): адресаты — строки аудитории записей окна, `ListEventAudience` в проходе 0 вызовов; `Resolve{self}` на письмо вне транзакции адресата под сроком пакета `digest`; окна, открытие и закрытие, поднятие `inbox_clock.t` до `E`; такт `KACHO_NOTIFY_DIGEST_TICK`, сетка периода в UTC; ячейка `OWN_ACTIONS` | `go-implementer` | `services/notify/internal/digest/**`, `services/notify/notifications/digest/**` | NTF3-103 (а)–(е), 105…111, 168 (сводка), 169 (сводка) зелёные; УК3-17, УК3-18, УК3-45 (сводка), УК3-56 | волна В-3 влита (S2-B4, S2-B9) | R1 | L |
| S2-B6 | мгновенные письма (Р11, Р13, З22): адресат — подписчик из строк аудитории; подписчику вне строк — `Resolve{event, via_subscription}` при приёме (в том числе право уровня кластера только по подписке); схлопывание, всплеск, потолок, сетка `notice` условным оператором, отметка «ушло»; ячейка `OWN_ACTIONS` | `go-implementer` | `services/notify/internal/{instant,ingest}/**` | NTF3-76, 96…102, 153, 176 (сторона `notify`) зелёные; УК3-19 | волна В-3 влита (S2-B4, S2-B7 — таблица подписок, S2-B9) | R1 | M |
| S2-B10 | чарт `notify` поверх развёртываний NTF-5 (#3099): ручки Р26 со стражами старта (`KACHO_NOTIFY_DIRECTORY_PAGE_SIZE`, `KACHO_NOTIFY_DIGEST_TICK`, срок хранения ленты); адрес и срок службы доступа у `notify-api`; допуск `notify-sender` в политике сети внутреннего порта vpc из перечня источников (§3 шаг (10)); `TestMailSecretIsMountedByTheSenderOnly`, `TestNotifyServesNoSendVerb` | `deploy-engineer` | `deploy/helm/{notify,umbrella}/**`, `deploy/tests/helm/**` | NTF3-27 (учётка и декларация `notifyApi.spiffe`), 66 (шаг (10)), 126, 127, 128 зелёные; самоотчёт посадки несёт ручки Р26 | S2-B5, S2-B6 | R2 ↑ | M |
| S2-B11 | обвязки S2 (З33): NTF3-160 (а)–(з) — С15, С21, С22 в тестовом дереве, сверщик не запущен; аудитория по всем охватам и объединение `UPDATED` (165…167), решение приёма не пересуживается (168), барьер (170), `DELETED` держателям каскадно снятых выдач (178), окно токена (179 (б)) — `notify` + служба доступа + модули | `integration-tester` | тестовый пакет `services/notify/internal/integration/`, `*_ntf3_160_integration_test.go` в пакетах storage, vpc, nlb, compute | перечисленные зелёные трижды подряд; `git grep` в не-тестовом дереве storage и compute — новых ручек «без сверщика» и перевода статуса 0 | S2-B5, S2-B6 | R1 | L |
| S2-B7L | подписка с отбором по меткам ресурсов (решение владельца 2026-10-08 (2)) | `proto-sync`, `rpc-implementer` | по одобренной дельте приёмки | сценарии дельты зелёные | **Е9**, S2-B7 | R2 | — (размер — по дельте) |

**Сбои и напоминания (пп. 6–8 §0.1) — волна В-5.**

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| P5 | подъём пинов: corelib — на голову `77-notify` с X3; kaname — на голову `484-notify` с X4e | `go-implementer` | `go.mod`, `go.sum` | `go build ./...` и CI зелёные; `git diff --name-only` полосы — два пути | X3, X4e влиты | R1 | S |
| S3-C1 | `intent_initiator` у тома, снимка и образа — `NOT NULL` + `CHECK` без умолчания; один конструктор; запись шестью вставками; вычитание из полезной нагрузки журнала (Р15, З14) | `migration-writer`, `go-implementer` | `services/storage/internal/{migrations,domain,repo/pg}/**` | NTF3-09, 10 (вставка), 51 зелёные; УК3-01, УК3-02; интеграционная проба на каждый глагол Р15 | волна В-4 влита | R2 | M |
| S3-C2 | запись перехода storage (Р16, Р17, З15, З17, З18): оператор CTE, предикаты сбоя и восстановления, `SendX` шести шаблонов, адресат — инициатор намерения при членстве в аудитории версии перехода (`Resolve{event}`), классификация `Put`, отказ пустой причины | `go-implementer` | `services/storage/internal/reconciler/**`, `services/storage/notifications/{volume,snapshot,image}-{error,recovered}/**`, `internal/repohygiene/storageerrorwriters_test.go` | NTF3-06, 07, 10, 12, 13, 14, 43, 49, 52, 53, 54, 129…132 зелёные; УК3-03, УК3-15, УК3-40, УК3-41, УК3-43, УК3-44 | S3-C1 | R1 | L |
| S3-C3 | `FailTerminal` в пяти модулях (п.7; З16, З17): генерируемые `operation-failed`, корни строят `operations.NewNotifyingRepo(pool, schema, n)` с `n, err := opsnotify.New(sender, "<служба>", opts)` — один вызов на корень (compute `cmd/compute/main.go`, nlb `cmd/kacho-loadbalancer/main.go`, registry `cmd/kacho-registry/serve.go`, storage `cmd/storage/serve.go`, vpc `cmd/vpc/main.go`), ошибка — отказ старта с именем службы; geo — `NewRepo` без изменения; три комментария с `operations.NewRepo(pool, …)` переписаны | `go-implementer` | `services/{compute,nlb,registry,storage,vpc}/cmd/**`, `services/<svc>/notifications/operation-failed/**`, `internal/repohygiene/notifyingopsrepo_test.go` | NTF3-133…139 зелёные; УК3-10, УК3-14, УК3-38, УК3-42, УК3-46, УК3-55, УК3-59 (расширенная форма), УК3-60 (половина корней), УК3-65, УК3-66 на дереве kacho (контроль по каталогу закреплённой corelib — форма УК3-65 замысла, провал предпосылки — «не выполнилось»); `git grep -n 'operations\.NewRepo(' -- services/{compute,nlb,registry,storage,vpc} ':!*_test.go'` → 0, контроль по `services/geo` → 2 (на `515e017c87` у пяти модулей — 8) | P5 | R1 | M |
| S3-C4 | задание напоминаний (п.8; Р19, З26): `feed.NewLocal`, все страницы `ListExpiringCredentials`, границы окна на проход, `Put` затем однократность, проверка контакта с тремя исходами; `identityNamespaces = {kaname, notify}`; срок вызова — константа пакета `reminder` | `go-implementer` | `services/notify/internal/reminder/**`, `services/notify/notifications/credential-expiring/**` | NTF3-140…145, 152 зелёные; УК3-22, УК3-57 | P5 | R2 | M |

**Закрытие — волна В-6.**

| полоса | предмет | исполнитель | пути | предикат снятия | after | уровень | размер |
|---|---|---|---|---|---|---|---|
| S3-C5 | гейты NTF-1 печатают пять модулей (DoD 12.3 п.4); страницы арендатора модулей и инженерная страница `notify`, страница перехода (пересоздание стенда); строки рёбер спеки (DoD 12.2 п.6) — строкой «нужен следующий» автору спеки-книги и владельцу `polyrepo.md` (ребро `<модуль> → kaname` дописывается `CurrentAuthzRevision`); записи vault | `go-implementer` (гейты), `docs-writer`, `vault-scribe` | `services/*/docs/**`, `services/notify/docs/**` | DoD 12.3 п.4, п.7, п.8; build сайтов без битых ссылок | волна В-5 влита | R1 | M |
| S3-C6 | сквозные стенда NTF3-38, 146…148; записи ведомости производителя у новых коллекций newman | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного; ведомость производителя сверена | S3-C5 | R0 | M |

## 5. Волны и цепочки

Волна — один запрос в ветку эпика своей линии; полосы волны сводятся в одну ветку. Слои — вывод
`scripts/plan-precheck.sh` (origin/main воркспейса) на планах волн с путями §4, база — `2914-notify`
`515e017c87`: у всех шести волн kacho код 0, причин (`LANES-OVERLAP`, `DEP-CYCLE`, `TIER-UNDERSTATED`) нет.

| волна | линия | полосы (слои) | старт | уровни |
|---|---|---|---|---|
| Ф-C | corelib `77-notify` | FC ∥ X3 | сейчас | FC R2, X3 R1 |
| Ф-K | kaname `484-notify` | посадка #673 (Е7) → X4e | Е7 — вердикт посадки #673 | X4e R2 |
| В-1 | kacho `2914-notify` | [B1v, B1n, B3] → [B2, S1-A5, S1-A6] | сейчас | R2: B1v, B1n, B2, S1-A6; R1: B3, S1-A5 |
| В-2 | kacho | [FM0] → [FM-c, FM-v, FM-n, FM-r, FM-s] → [FM-i] | В-1 влита, Е7, Е8 | R2 все, FM-i R0 |
| В-3 | kacho | S2-B9 → S2-B4 → S2-B7 → S2-B7k → S2-B8 | В-2 влита | R2 все |
| В-4 | kacho | [S2-B5, S2-B6] → [S2-B10, S2-B11]; S2-B7L — если Е9 снята до раздачи, иначе отдельной волной после В-4 | В-3 влита | R1: B5, B6, B11; R2: B10, B7L |
| В-5 | kacho | [P5, S3-C1] → [S3-C2, S3-C3, S3-C4] | В-4 влита; X3 и X4e влиты | R2: C1, C4; R1: P5, C2, C3 |
| В-6 | kacho | S3-C5 → S3-C6 | В-5 влита | C5 R1, C6 R0 |

**Цепочки.**

- **Критическая:** (#673 → Е7) ∥ (FC → Е8) → В-2 → В-3 → В-4 → В-5 → В-6. В-1 идёт сейчас, параллельно
  линиям фундамента, и к старту В-2 обязана быть влита (FM-v ждёт B1v и B2, FM-n — B1n, FM-s — B3).
- **Ограда:** FC (corelib) и #673 (kaname) → FM0 (пины, гейты 175/186/187 красные) → пять модулей
  параллельно → FM-i. Пока FM0 не влита, ни одна полоса `notify`, читающая `ListEventAudience`, не
  стартует: контракт есть только на пине FM0.
- **Приём:** S2-B9 → S2-B4 (приём импортирует клиент справочника — порядок обратный редакциям 1–19) →
  S2-B7 (лента читает таблицы приёма) → S2-B7k → S2-B8; затем S2-B5, S2-B6.
- **пп. 5–8 §0.1:** п.5 — S2-B7k (В-3); п.6 — S3-C1 → S3-C2 (В-5); п.7 — X3 (Ф-C) → P5 → S3-C3; п.8 — X4e
  (Ф-K) → P5 → S3-C4.
- Волн kacho одновременно открыто не больше одной (единица запроса — волна); линии corelib и kaname
  идут параллельно kacho.

Итог: полос впереди **30** — corelib 2 (FC, X3), kaname 1 (X4e), kacho 27 (В-1 — 6, В-2 — 7, В-3 — 5,
В-4 — 5 с S2-B7L, В-5 — 5 с P5, В-6 — 2); волн **8** (Ф-C, Ф-K, В-1…В-6); внешних зависимостей
открыто 3 (Е7, Е8, Е9), Е5 не проверена. Посадка #673 — не полоса этого маршрута, а зависимость Е7.

## 6. Что проверяет передача полосы

1. Каждая строка §11 и §11а замысла стоит в предикате своей полосы: `УК3-01…71` (кроме
   неиспользуемого `УК3-36`, снятого `УК3-58` и заказов, чьи пробы уже в деревьях: kacho `515e017c87` —
   УК3-13, УК3-27, УК3-28, УК3-30, УК3-31, УК3-37, УК3-61; corelib `77-notify` — УК3-04, УК3-11, УК3-49, УК3-50; kaname `484-notify` — УК3-07, УК3-08;
   `git grep -ohE 'УК3-[0-9]+' <ветка> -- '*_test.go' | sort -u`) — `grep -o 'УК3-[0-9]*' tasks.md | sort -u`.
2. Каждый номер §12 DoD приёмки (12.1 п.6, 12.2 п.7, 12.3 п.6) — в предикате ровно одной полосы впереди
   либо в §3 «Влито» с координатой пробы; номера стороны службы доступа — на ветке `484-notify` после Е7.
3. Полосы, трогающие фоновые пути (B3, FM-*), не меняют их исход: пробы nlb `TestFreeIP_*` зелёные без
   правки утверждений; личность прохода compute ни одна полоса не ставит (CX3H-02).
4. В В-2 гейты NTF3-175 и NTF3-187 печатают **пять** модулей; модуль, выпавший из печати, — красный, а не
   «обход меньше».
5. `ListProjectAudience` после В-2 в дереве kacho не встречается (`git grep -c` → 0); `inbox.RightObject`
   и проверка права при выдаче ленты не заводятся (З34).

## 7. Снято этой редакцией

- §4 «Основа» и §5 «После Основы» редакций 17–19: пп. 5–8 маршрутизированы в В-3 и В-5; деление X4 на X4 и
  X4e сохранено (X4 влит как X4D, X4e — §4.2), деление S2-B7 на S2-B7 и S2-B7k сохранено; S3-C5r и S3-C6r
  влиты обратно в S3-C5 и S3-C6.
- Правила выпуска тегов X1, X2, X3, X2-F и окна пина (§0 редакций 4–9, Е6): пины — на головы веток эпиков
  (Д64); X1, X2, X2-F влиты.
- X4 в форме `ListProjectAudience` (Р7 редакции 33) — заменён `ListEventAudience` (#673); S2-B4 без клиента
  справочника — заменён приёмом с чтением аудитории (З34).
- S2-B1 как одна полоса пяти модулей — влит #3098 для трёх модулей, остаток — B1v, B1n.
- Ошибка пути редакций 1–19: проход compute живёт в `services/compute/internal/apps/kacho/api/instance/`, а
  не в `services/compute/internal/api/instance/` (`git cat-file -t origin/2914-notify:<путь>`).
