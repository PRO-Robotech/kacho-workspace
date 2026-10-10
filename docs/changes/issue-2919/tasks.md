<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2919 (NTF-4, обратная связь доставки и репутация почтового шлюза) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md`, который лежит рядом:
> полосы, исполнитель по базе маршрутизации, репозиторий и пути, предикат снятия, зависимости,
> размер. Это не трекер. Состояние полос живёт в задаче `PRO-Robotech/kacho#2919` и в задачах правок
> Х1–Х5 (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 2 · 2026-09-30 — проект маршрута по замыслу редакции 2** (заход отображения по
> решению диспетчера Д26: строки CX4V-07, 55, 56, 63, 64, 65 — в §2а и в предикатах полос; новая
> полоса S1-A10). Редакция 3 · 2026-09-30 — строки Д26 · 3, 4, 5 по пересверке `cd92e9ac…`; путь
> одобрения сноса в env контейнера `migrate` — зависимость Е7 замысла. Редакция 4 · 2026-09-30 — по
> пересверке `b46bd023…`: Е7 внесена в §1 гейтом S1-A8 и S1-A10, предикат S1-A8 требует решения по Е7.
> Редакция 5 · 2026-09-30 — по решению диспетчера Д28 и пересверке `72f13d01…`: Е7 снята (ключ values
> `migrator.dropApproved`, УК4-36 в S1-A8 и S3-C6); предикат строки Е7 судит поле состояния; §3 п.1
> называет Е7; правило §0 держит посадку ствола — миграция сноса не садится без ключа и его пробы.
> Редакция 6 · 2026-09-30 — по ревью замысла `80dea362…` ролью `design-reviewer`: строки Д26 · 7
> (срок сетевых операций POP3 и попытки контрольного письма, такт не ждёт сеанса ящика), Д26 · 8
> (`OrphanGrace` сверщика), Д26 · 9 (срок запроса DNS) — в §2а и в предикатах S1-A3, S1-A5, S3-C3,
> S5-D1, S5-D3, S7-F1; заказы УК4-37…УК4-40.
> Редакция 7 · 2026-09-30 — по пересверке `1a5cf53f…` (замысел редакции 7): CX4V-66 — условия
> Д26 · 7 (5)–(7) и УК4-37 (в), (г) в S1-A3 и S1-A5; CX4V-67 — срок попытки контрольного письма
> `min(notify.smtp.sessionTimeout, LEASE_TTL / 3)` и близнец УК4-38 в S5-D3; Д26 · 8 (2) в S3-C3;
> второй близнец УК4-40 в S5-D1; предикат посадки §0 — с `--first-parent -m`, как заказывали
> пересверки `80dea362` и `1a5cf53f`.
> Редакция 8 · 2026-09-30 — по решению диспетчера Д41: окна пина corelib NTF-4 — (2) в порядке эпика,
> теги Х1 → Х3 → Х5 по одному (зависимости тегов в строках X1, X3, X5). Иного не меняет.
>
> Редакция 9 · 2026-10-04 — по решению диспетчера Д100: §2б «Часть Основы» — полосы X5, S3-C2н,
> S3-C4н, S3-C5, S3-C6н, S3-C7н, S3-C8н; зависимости Е8–Е10 в §1. Строки §2 не правлены, их остаток после
> Основы назван в §2б.
>
> Редакция 10 · 2026-10-04 — по ревью замысла `f9c77ef4…` (R8-1…R8-4, R8-6), пересверке `f9c77ef4…`
> (RV8-01…08) и решению диспетчера Д113: Е1, Е8, Е9, Е10 сняты (§1); S1-A6 — 21 ручка S1 (Д96); §2б —
> пин Основы на голову линии corelib (Д64), гейт литерала `nop` в S3-C4н, один запрос волны S3-C2н,
> S3-C6н, S3-C7н, S3-C8н с S2-B7 NTF-3 и предикат его посадки в S3-C6н, условия к коду RV8-06…08.
>
> Редакция 11 · 2026-10-04 — по ревью замысла `1e2562a8…` (R9-1…R9-4) и пересверке `1e2562a8…`
> (RV9-01…04): Е11 в §1 — состав волны Н3-Ф3а в маршруте NTF-3, гейт S3-C6н и S3-C8н; §2б — следствие
> для запроса волны, порядок S3-C2н → S3-C7н → S2-B7, шаг на сведённой голове волны в S3-C6н (красный на
> нуле строк), строка пробы З9 в S3-C7н, условия к коду RV9-04 в S3-C4н.
>
> Редакция 12 · 2026-10-10 — приведение к дереву (перепись плана, `scout:replan` п.4; решение диспетчера (г):
> только блокирующее, без расширения объёма). Носитель `notify-api` заведён NTF-5 (`kacho#3070`, `#3099`): корень,
> форма Х5, самоотчёт, оси дескриптора, десять ручек стадии S3, соединение края `notify`, чарт `api-*`, строка
> записи З9 с непустым служимым набором; правки Х1, Х3, Х4, Х5 — в пинах базы. Новый §1а — база маршрута с
> командами; §2б переписан: у каждой «н»-полосы — только остаток против базы, карточкой. Е10 и Е11 сняты
> предметом (служимый набор `notify-api` непуст без S2-B7 NTF-3), связка части носителя с S2-B7 и волна
> Н3-Ф3а сняты, шаг `notify-api-served-set-wave-check.sh` не заводится. Окна пина corelib NTF-4 по тегам
> (Д41) заменены окнами NTF-3 (CX3T-01, §0): NTF-4 поднимает только пин kaname в S3-C2. Новые зависимости
> Е12 (линия A NTF-1 влита — общие пути) и Е13 (В-3 NTF-3 влита — Given NTF4-108). Строки X1, X3, X4, X5,
> S1-A6 §2 сняты: исполнены в дереве (§1а). Прочие строки §2 и §2а не правлены.
>
> Редакция 1 была проектом по замыслу редакции 1. Состояние `TASKS_READY`
> этот файл не объявляет: по §5 SDD-1 оно наступает только после `DESIGN_APPROVED` и проверенного
> writing-plans handoff. Handoff либо подтверждает этот файл без правки, либо переписывает его. В
> обоих случаях действует текст на отпечатке, который назван записью handoff.

## 0. Правила маршрута

- **Порядок стадий приёмки** (§1.1, §10 приёмки; З24 замысла):
  - Х1 → S1;
  - Х3, Х4 → S2;
  - Х2, Х5 → S3;
  - после S3 — S5, S6, S7 параллельно.

  Стадии NTF-4 стартуют после посадки стадий NTF-1, которые им нужны (Д13; Е6 замысла). Полоса
  стартует, когда сняты её зависимости. Полосы одного яруса без общих путей идут параллельно.
- **Окна пина NTF-3** (CX3T-01; `docs/changes/issue-2918/tasks.md` §1 «Окна пина»; заменяют окна пина
  corelib NTF-4 по тегам Д41 — правки Х1, Х3, Х4, Х5 уже в пинах базы, §1а, и тегов NTF-4 потребитель
  не ждёт: пины — на головы линий, Д64). Ветки `77-notify` и `484-notify` общие для маршрутов эпика
  `#2914`. Окно В-2 — от вливания `kaname#673` (**открыто** 2026-10-09T17:16Z) и Ф-C1 NTF-3 до вливания
  волны В-2 NTF-3 в `2914-notify`; окно В-5 — от вливания Ф-C2 или Ф-K2 NTF-3 до вливания В-5. Внутри
  окна пины corelib и kaname в kacho (и пин corelib в kaname) этот маршрут не поднимает. Пин поднимает
  у NTF-4 одна полоса — S3-C2 (пин kaname на голову `484-notify` с Х2), нулевым шагом своей волны
  (`"repin": "kaname"` в плане), на голове `2914-notify` после вливания В-5 NTF-3; пин corelib в kaname
  на целевой голове равен пину corelib в kacho (`plan-precheck.sh`, `CORELIB-SKEW`). Прочие полосы и
  волны NTF-4 пинов не трогают. Предикат на каждом запросе NTF-4 в `2914-notify` и `484-notify`:
  `git diff <база> <голова> -- go.mod | grep -E '^[-+].*PRO-Robotech/(corelib|kaname) '` → пусто, кроме
  запроса волны S3-C2 (держит `git-operator`; скрипт — Е10 NTF-3).
- **Общие пути с соседними волнами** (`issue-2918/tasks.md` §1 «Неделимая цепочка»; перепись плана
  п.4). Волна NTF-4 и волна соседа, правящие один путь, не открыты одновременно: вторая стартует на
  голове `2914-notify` после вливания первой. Предикат на старте волны: пересечение
  `git diff --name-only <база>...<голова>` открытого запроса соседа с путями полос волны → пусто.
- **Перед стартом каждой стадии** исполнитель стадии делает сверку соседей по §0а замысла и пишет
  исход в `docs/changes/issue-2919/reconciliation/<стадия>-<короткий sha воркспейса>.yaml`. Для S3
  в запись входит и поле `notify_api_root` (З18). Исход (б) останавливает стадию и даёт строку
  «нужен следующий: acceptance-author».
- **Проба до кода** в каждой полосе исполнителя кода. Сначала пишется проба с ID сценария в имени
  (`NTF4-01 · …`). Она красная на текущем дереве, исход напечатан. Затем код, затем та же проба
  зелёная — одним изменением (ban #12). Красное фиксируется до кода: это свидетельство `RED_PROVEN`.
- **Заказанные пробы** (строки §11а замысла, УК4-NN) входят в предикат своей полосы наравне со
  сценариями приёмки.
- **Гейт** печатает объём осмотренного, падает на пустом обходе и доказан инъекцией в обе стороны.
  Integration-группа даёт тот же вердикт трижды подряд.
- **Единица сдачи** — коммит исполнителя в ветке полосы. Сведение волны, запрос на слияние,
  вливание и снятие веток делает `git-operator` по решению диспетчера. В ствол идёт только
  одобренное (Д16).
- **Снос ограды не садится в ствол без пути одобрения** (замысел, строка Д26 · 4 (5); Д28). Полосы
  S1-A1 (миграция `DROP TABLE recipient_key_fence` и запись `dropguard.json`) и S1-A8 (ключ
  `migrator.dropApproved` и УК4-36) входят в один запрос волны S1; запрос, несущий S1-A1 без S1-A8,
  не вливается. Предикат посадки: `git -C kacho log --first-parent -m --diff-filter=A --format=%H origin/main --
  services/notify/internal/migrations/<миграция сноса>.sql | tail -1` → коммит C ствола (слияние
  запроса волны, а не коммит внутри её ветки: без `--first-parent -m` вывод назвал бы коммит ветки,
  чьё дерево не судит, что вошло в ствол одним слиянием); на C
  `git -C kacho ls-tree C -- deploy/tests/helm/notify-drop-approval-test.sh` непуст и УК4-36,
  прогнанная на C, зелёная с числом судимых развёртываний ≥ 1. Коммита ствола со сносом и без пути
  одобрения поэтому нет, и выкатка посадкой ствола вне маршрута полос его не получает.
- Размер: **S** — до дня одного исполнителя, **M** — два-три дня, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход. «Зелёный» пишется с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | новая редакция приёмки по сверке соседей (§0а, §13 замысла) | **снята**: редакция 22 одобрена кругом 21, редакция 25 (`d337b360…`) — кругом 23; §0 замысла закреплена на `d337b360` | `grep -c '29cfa368\|ef9c6801' docs/specs/sub-phase-NTF-4-delivery-feedback-reputation-acceptance.md` → 18; `ls docs/specs/reviews/sub-phase-NTF-4-delivery-feedback-reputation-acceptance/ \| grep -c 'd337b360\|01b2888'` → 2 на `24f31fd00` |
| Е2 | согласование с замыслом NTF-1: ключ самоотчёта формы, замещение ключа сетки (З2, З18) | открыта; гейтит полосы S1-A2, S1-A8 и S3-C2 | `grep -n 'Е11' docs/changes/issue-2915/design.md` — строка зависимости есть, снятия нет |
| Е3 | замысел NTF-3: класс поверхности своих регистраций, изъятия осей | открыта; гейтит S3-C2 только при исходе `notify_api_root: present` | `ls docs/changes/issue-2918/design.md` — файла нет |
| Е4 | пересверка разбора и ревью замысла на отпечаток `design.md` | **открыта** | `ls docs/changes/issue-2919/reviews/` — нет `design/`; в `class-exposure/revalidation/` четыре записи — на редакции 1–4 (`b9149d3c…`, `cd92e9ac…`, `b46bd023…`, `72f13d01…`), на редакцию 5 записи нет |
| Е5 | задачи правок Х1–Х5 | **открыта** | задач в трекерах corelib и kaname с заголовками §1.1 приёмки нет (проверяет диспетчер) |
| Е6 | стадии NTF-1 посажены | открыта | `git -C kacho ls-tree origin/main services/notify` — пусто на `1d42a6728bf` |
| Е7 | путь одобрения сноса ограды в env init-контейнера `migrate` (§13 замысла, CX4V-63 (б)) | **снята решением Д28**: вариант 1 — ключ values `migrator.dropApproved` чарта notify, УК4-36; гейтила полосы S1-A8 и S1-A10 | `grep -c '^. Е7 .*Состояние: снята решением' docs/changes/issue-2919/design.md` → 1 — решение записано; 0 — не записано (на редакции 4 замысла, коммит `dfe2cea05`, → 0) |
| Е8 | префикс `nop` для S3-C4н (замысел §13, Е8) | **снята Д113, вариант (б)**: производитель — только каталог corelib `ids`; пин S3-C2н — на голову линии corelib, потомка `4dabea4`; литерал держит гейт `opprefixliteral_test.go` в S3-C4н | `git -C corelib merge-base --is-ancestor 4dabea4 <ревизия пина S3-C2н>` → 0; `git -C corelib grep -c '"nop"' v1.10.0 -- ids/ids.go` → 0 (в теге нет, поэтому пин не на `v1.10.0`) |
| Е9 | рёбра окон пина в части Основы (замысел §13, Е9) | **снята**: маршрут NTF-3 пишет, что теги Основу не гейтят; в Основе пины — на головы линий (Д64); с редакции 12 тегов NTF-4 нет — Х5 в пине базы (§1а), окна — NTF-3 (§0) | `grep -c 'Основу не гейтят' docs/changes/issue-2918/tasks.md` → 1 на `24f31fd00` |
| Е10 | служимый набор носителя на посадке (замысел §13, Е10) | **снята предметом** (редакция 12): служимый набор `notify-api` непуст без S2-B7 NTF-3 — строка `cmd/notify-api` записи З9 несёт `InternalNoticeService`, `NoticeService`, `OperationService` (NTF-5, `#3099`); связки части носителя с S2-B7 нет. Прежнее снятие Д113 (б) — история | `git -C kacho show origin/2914-notify:services/notify/servesurface_ledger.go \| grep -c '"kacho.cloud.notify.v1\.\|"corelib.operation'` → 3 на `e6075f09c2` |
| Е11 | маршрут NTF-3 исполняет Д113 (б) — волна Н3-Ф3а (замысел §13, Е11) | **снята предметом** (редакция 12): связка Е10 снята, волна Н3-Ф3а не нужна; маршрут NTF-3 редакции 21 и позже её не несёт, S2-B7 — в В-3 | `grep -c '^\| Н3-Ф3а' docs/changes/issue-2918/tasks.md` → 0 (строки волны в таблице волн нет; вхождения — только в истории редакций) на `0dba146a6` |
| Е12 | линия A NTF-1 (`2915-wave-ntf1-send`) влита в `2914-notify`: она правит `gateway/internal/config/config.go`, `gateway/internal/config/notify_test.go`, `deploy/helm/notify/values.yaml`, `deploy/helm/notify/templates/configmap.yaml`, `deploy/scripts/assert-production-posture.sh` — пути S3-C4н, S3-C5, S3-C6н | **открыта** на 2026-10-10: голова линии `38619d412f`, запроса нет | `git -C kacho merge-base --is-ancestor <голова линии A> origin/2914-notify` → 0; пересечение путей — `git -C kacho diff --name-only $(git -C kacho merge-base origin/2915-wave-ntf1-send origin/2914-notify) origin/2915-wave-ntf1-send` (20 файлов, пять из них — пути выше) |
| Е13 | В-3 NTF-3 влита (S2-B7 — сервисы NTF-3 на `notify-api`): Given NTF4-108 части Основы — «П1 после посадки Основы: носитель и сервисы NTF-3 на нём» (приёмка §0а) | **открыта** | `git -C kacho show origin/2914-notify:services/notify/servesurface_ledger.go \| grep -c 'NotificationInboxService'` ≥ 1 (регистрация S2-B7 в строке `cmd/notify-api` записи З9; имя — замысел NTF-3 §4); → 0 на `e6075f09c2`; гейтит только S3-C8н |
| Е14 | редакция приёмки NTF-4: NTF4-117 части Основы и замысел З21 требуют окружение `notify-api` «ровно (н1)–(н4) и десять ручек стадии S3», а на базе загрузчик и `api-configmap.yaml` несут и ручки NTF-5 (`KACHO_NOTIFY_NOTICE_REMINDER_LEAD`; Р17 NTF-5 — `KACHO_NOTIFY_LIST_FILTER_CACHE_TTL`). Утверждение «ровно» на дереве красное; нужна формулировка «закрытое объединение частей под-фаз» (как у перечня ручек в З18) | **открыта**; производитель — `acceptance-author` (NTF-4), затем `acceptance-reviewer` | `git -C kacho show origin/2914-notify:deploy/helm/notify/templates/api-configmap.yaml \| grep -c 'KACHO_NOTIFY_NOTICE_REMINDER_LEAD'` → 1 на `e6075f09c2`; снятие — запись ревью ✅ на отпечаток приёмки с новой формулировкой NTF4-117; гейтит только утверждение об окружении в S3-C6н |

## 1а. База маршрута (редакция 12)

Не состояние полос (оно — у трекера), а вход, на котором маршрут стоит: что дерево уже несёт и поэтому
полосой не раздаётся. Ревизии: kacho `2914-notify` @`e6075f09c2`, пины в `go.mod` — corelib
`18d105d0f50a` (C0), kaname `33010d434767`; corelib `77-notify` @`1177490`; kaname `484-notify`
@`d93b69712` (пин corelib — тоже `18d105d0f50a`). Замер 2026-10-10.

| что в дереве | производитель | команда · исход |
|---|---|---|
| Х1: `nsp`, `nop` в каталоге `ids` | corelib `4dabea4` (в пине C0) | `git -C corelib grep -n 'PrefixOperationNotify = "nop"\|PrefixSuppressionHyphen = "nsp"' 18d105d0f50a -- ids/ids.go` → 2 строки; `git -C corelib merge-base --is-ancestor 4dabea4 18d105d0f50a` → 0 |
| Х3: `SUPPRESSED(reason)` ленты | corelib (в пине C0) | `git -C corelib ls-tree 18d105d0f50a notify/feed/suppressed_vocabulary_test.go notify/feed/suppressed_ack_integration_test.go` → 2 файла |
| Х4: пин corelib в kaname на ревизии с Х3 | kaname | `git -C kaname show origin/484-notify:go.mod \| grep 'PRO-Robotech/corelib '` → `…-18d105d0f50a` |
| Х5: `HostInternalOnly`, `PostureOf`, `BootPosture.ListenerForm` | corelib (в пине C0) | `git -C corelib grep -c HostInternalOnly 18d105d0f50a -- servicecontract/contract.go` ≥ 1; `git -C kacho grep -n 'servicehost.PostureOf' origin/2914-notify -- services/notify/cmd/notify-api/bootposture.go` → 1 |
| S1-A6: 21 ручка S1, `required_knobs_test.go` | `kacho#3072` (`cd20a05cfa`) | `git -C kacho ls-tree origin/2914-notify services/notify/internal/config/ntf4.go services/notify/internal/config/required_knobs_test.go` → 2 файла |
| корень `notify-api` в форме Х5 с причиной, самоотчёт `ListenerForm` из `PostureOf` | NTF-5 `#3070`, `#3099` | `git -C kacho grep -n 'HostForm: *servicecontract.HostInternalOnly' origin/2914-notify -- services/notify/cmd/notify-api/describe.go` → 1 |
| оси дескриптора `notify-api` по Р20: `DBSSLMode`, `Authz`, `CheckEdge`, `PeerCheck`, изъятия с причиной | NTF-5 | `services/notify/cmd/notify-api/describe.go` @`e6075f09c2`, строки `DBSSLMode`, `Authz`, `CheckEdge`, `PeerCheck`, `Emits`…`Narrowers` |
| десять ручек стадии S3 в загрузчике `notify-api` (пять звена прав, пять внутреннего слушателя), границы `…_HANDLING_BUDGET > …_AUTHZ_CHECK_TIMEOUT` и `…_INTERNAL_PORT` ≠ порту диагностики | NTF-5 | `services/notify/cmd/notify-api/internal/config/config.go` @`e6075f09c2`: поля `AuthzTrustDomain` … `HandlingBudget`, `Validate` (строки с `InternalPort == diagPort` и `HandlingBudget <= c.AuthzCheckTimeout`) |
| служимый набор `notify-api` непуст: `InternalNoticeService`, `NoticeService`, `OperationService`; операции — приставка `nop` из `ids` | NTF-5 | строка `cmd/notify-api` в `services/notify/servesurface_ledger.go`; `services/notify/internal/apps/kacho/api/notice/operation.go` (`ids.NewID(ids.PrefixOperationNotify)`) |
| перепись поверхности по корням и графу вызовов с ведомостью (проба З9 в форме NTF-1) | NTF-1 `ede4db32c2`, NTF-5 `1d29bab5a7` | `services/notify/servesurface_test.go`: `TestNTF1G19_NotifyServesNoInboundVerb`, `TestNTF1G19Injection` |
| край: соединение `notify` к `notify-api`, адрес без умолчания (пусто — соединения нет) | NTF-5 (`c7240e305` в `#3099`) | `gateway/internal/config/config.go`: поле `NotifyInternalAddr` (`KACHO_API_GATEWAY_NOTIFY_INTERNAL_GRPC`), ключ `InternalBackendKey("notify")` |
| чарт `notify-api`: `api-deployment.yaml` (реплики из `api.replicaCount` = 2, `/readyz`, `checksum/config`), `api-serviceaccount.yaml`, `api-certificate.yaml`, `api-pdb.yaml`, `api-service.yaml`, `api-configmap.yaml`, `api-networkpolicy.yaml` | NTF-5 | `git -C kacho ls-tree --name-only origin/2914-notify deploy/helm/notify/templates/ \| grep -c '^deploy/helm/notify/templates/api-'` → 7 |

**Чего в базе нет** (остаток части носителя — полосы §2б): замок мигратора и `RequireApplied`; init-контейнер
`migrate` и стратегия переката у `notify-api`; AST-держатель УК4-26; проба испытательной регистрации
NTF4-122 и пробы NTF4-92, 119, 124; запись `prefixToBackend` для `nop`; декларация `InternalOnly` и проверка
происхождения до поиска соединения; гейты `notifysurfaceparity_test.go`, `opprefixliteral_test.go`,
`notify_key_internal_refusal_test.go`; рендер-гейты `notify-rollout-and-secret-mount-test.sh`,
`notify-availability-test.sh`, `notify-listeners-test.sh`; инъекция RV8-07 в пробе З9; NTF4-108/109 на
стенде. Команда переписи — та же, что в строках выше: `git -C kacho cat-file -e origin/2914-notify:<путь>` → 1
для каждого из названных файлов на `e6075f09c2`; `git -C kacho grep -c 'pg_advisory\|RequireApplied'
origin/2914-notify -- services/notify/` → пусто; `git -C kacho grep -n 'PrefixOperationNotify'
origin/2914-notify -- gateway/` → пусто.

## 2. Полосы

### Правки вне kacho

Полосы X1, X3, X4, X5 сняты в редакции 12: правки в пинах базы (§1а), теги не выпускаются — пины на
головы линий (Д64), окна — NTF-3 (§0). Остаётся X2.

| полоса | предмет | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| X2 | каталог прав `notify.suppressions.*`, отображение, сверка с аннотациями, проба NTF4-120/121 (Х2, З17) | `go-implementer` | kaname · `internal/apps/kaname/seed/embedded/permission_catalog.json`, `internal/authzmap/permissions_to_relations.go`, `internal/apps/kaname/api/authorize/` (проба) | держатель каталога kaname зелёный; команда сверки З17 → пустой `diff`; NTF4-120/121 зелёные (два SAN, счёт вопросов модели) | Е5 (задача правки Х2 в kaname); S3-C1 посажена в `2914-notify` (контракт, на который ссылается сверка З17); пинов не поднимает | M |

### S1 — приём обратной связи

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1-A1 | миграции §6: `sent_log`, `feedback_message`, `feedback_event`, `suppression`, `feedback_lease`, `canary_issue`, `feedback_state`, `install_flag`, `address_key_check`, затем `DROP TABLE recipient_key_fence` | `migration-writer` | `services/notify/internal/migrations/**` | держатель монотонности миграций зелёный; УК4-12 (23514), УК4-33 (`now()` в SQL — 0) зелёные с инъекциями; DoD S1 п.2; запись `dropguard.json` и её производитель `dropguard_integration_test.go`, `TestEveryDropGuardManifestHasAProducer` зелёный; УК4-35 (§2а, Д26 · 4); индекс `feedback_message (processed_at)` (Д26 · 6) | X1 (в пине базы, §1а), Е6 | M |
| S1-A2 | `addresskey`: функция отпечатка, `Establish`, набор, скрытие ключа; снятие ограды и её сторожа в `limits` и `deliver`; объект ключа томом в загрузчике `notify-sender` (З2, З3) | `go-implementer` | `services/notify/internal/{addresskey,limits,deliver,config}/**`, `services/notify/cmd/notify/**` | NTF4-23, 77, 106 зелёные (106 красная на инъекции «код аутентичности над постоянной строкой»); УК4-05, 06, 07, 08; `redaction_test.go`; `Establish` на `ReadCommitted`, NTF4-116 с `repeatable read` у роли (§2а, Д26 · 1, Д26 · 2) | S1-A1, Е2 (б) | M |
| S1-A3 | клиент `pop3` со сроком каждой сетевой операции, двойник П10, сеанс, независимое продление (З7) | `go-implementer` | `services/notify/internal/{pop3,feedback}/**`, двойник П10 в тестовом дереве | NTF4-10, 104 зелёные (104 красная на инъекции «продление только в начале сеанса»); УК4-02; УК4-37 (а) — молчащий П10: сеанс закрыт в пределах `pop3.opTimeout`, продлений после закрытия 0, такты идут; УК4-37 (в) — остановка процесса при молчащем П10: работа держателя вернулась в пределах срока, горутин сеанса и продления 0, пул закрыт после; прогон под `-race` (§2а, Д26 · 7) | S1-A1, S1-A5 | M |
| S1-A4 | вид, токен-источник, классификация, ограничения разбора, корпус П3, `suppression.Apply` (З8, З9) | `go-implementer` | `services/notify/internal/{feedback,suppression}/**`, корпус `internal/feedback/testdata/corpus/` | NTF4-01…09, 11…14, 78 (integration) зелёные; корпус сверен с таблицей в обе стороны (DoD S1 п.3); УК4-11 | S1-A2, S1-A3 | L |
| S1-A5 | аренда с эпохой, такт, подметальщик у держателя, NTF4-15 (З11) | `go-implementer` | `services/notify/internal/{lease,suppression}/**` | NTF4-95…97, 15 зелёные (95 красная на инъекции «продление только фиксацией»); УК4-01, 01а; уборка по сроку — проход подметальщика у держателя, партии под продлением (§2а, Д26 · 6); порядок такта «продление → признаки → выпуск → запуск сеанса», такт не ждёт сеанса; признак «сеанс идёт» снимает сама горутина; транзакции держателя — явный `ReadCommitted`; УК4-37 (г) — умолчание роли `repeatable read`, отказов 40001 — 0 (§2а, Д26 · 7 (4)–(7)) | S1-A1 | M |
| S1-A7 | `reputation.Register`, наборы метрик, метки (З13, часть S1) | `go-implementer` | `services/notify/internal/reputation/**`, корень `cmd/notify` | УК4-21 зелёный; NTF4-33 (журнал и метки S1) зелёная; УК4-34 — семейства `notify_` реестра корня против объединения Р12 и перечня NTF-1 в обе стороны, двух снятых метрик нет (§2а, Д26 · 5) | S1-A4 | S |
| S1-A8 | чарт: объект ключа томом у `notify-sender`, снятие `secretKeyRef` и `checksum/recipient-key`, правка гейта D1; ключ values `migrator.dropApproved` → env `MIGRATOR_DROP_APPROVED` контейнера `migrate` (З21, Д28); приёмник ящика стенда (З21) | `deploy-engineer` | `deploy/helm/notify/**`, `deploy/helm/umbrella/**`, `deploy/notify_secret_layout_test.go`, `deploy/tests/helm/notify-drop-approval-test.sh` | гейт D1 зелёный в форме З21 и красный на инъекции `secretKeyRef`; DoD S1 п.6; УК4-32 — версия образа и её возможности напечатаны в отчёте полосы; УК4-36 зелёная с напечатанным числом судимых развёртываний ≥ 1, близнец «ключ не задан — переменной нет» зелёный, инъекция «переменная с пустым значением при пустом ключе» даёт красный близнеца (§2а, Д26 · 4); входит в один запрос волны с S1-A1 (§0) | S1-A2, Е7 (снята Д28) | M |
| S1-A9 | сквозные S1 на П1: 01, 02, 11, 13, 15 (две реплики) | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного, признаки установки сверены на обеих репликах | S1-A1…A8 | M |
| S1-A10 | страница перехода S1 службы notify: снос ограды, одобрение `MIGRATOR_DROP_APPROVED` до выкатки там, где стартовала NTF-1, его снятие после применения, откат новой миграцией (замысел З2, §10 п.4; §2а, Д26 · 4) | `docs-writer` | `services/notify/docs/**` | build сайта без битых ссылок; страница ссылается на `docs/architecture/drop-preflight-counts-the-live-database.md`, а не пересказывает его; путь одобрения на странице — ключ values `migrator.dropApproved` (поставить до выкатки, очистить после применения), имя переменной — `MIGRATOR_DROP_APPROVED` | S1-A1, Е7 (снята Д28) | S |

### S2 — подавление при отправке

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S2-B1 | клетка 6а в `Decide`, исход раз на выдачу, таблица ответа `Ack`, синхронный 5xx на `RCPT` (З10) | `go-implementer` | `services/notify/internal/deliver/**` | NTF4-18…23, 80, 81, 89, 90, 101, 102, 110 (красная на инъекции пересчёта), 111 зелёные; УК4-13, 14, 15; ветка «вне таблицы» `ReadAckAnswer` без своего счётчика — сигнал `misconfigured` NTF-1 (§2а, Д26 · 5) | S1; X3, X4 — в пинах базы (§1а), подъёма пина нет | L |
| S2-B2 | `returnaddr`, `sentlog`, `List-Unsubscribe` через `notify/form` (З5, З6) | `go-implementer` | `services/notify/internal/{returnaddr,sentlog,deliver}/**` | NTF4-13, 14 (адрес и заголовок ушедшего письма) зелёные; NTF4-04 зелёная; УК4-03, 09; УК4-01а по пакету `sentlog` (уборка по сроку под продлением, две функции пути письма — по идентичности); неудача отметки `accepted_at` — строка журнала ERROR без адреса, метрики нет (§2а, Д26 · 5, Д26 · 6) | S1-A2, S1-A5 | M |
| S2-B3 | сквозные 16, 17 на П1 (окно `recovery` NTF-2) | `qa-test-engineer` | сквозные пробы kacho | DoD S2 п.1; ответы глагола kaname сверены побайтово | S2-B1, S2-B2 | M |

### S3 — снятие подавления

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S3-C1 | контракт `InternalSuppressionService` (§5) | `proto-sync` | `proto/kacho/cloud/notify/v1/`, `pkg/api/kacho/cloud/notify/v1/` | `buf lint`, `buf breaking` зелёные; держатель аннотаций зелёный (DoD S3 п.1) | S2 | S |
| S3-C2 | корень `notify-api` либо дополнение существующего (по `notify_api_root`), носитель Х5, `PostureOf`, оси, (н1)–(н4), 12 ручек, `RequireApplied`, замок мигратора, сверщик операций, изъятия с пробой (З18, З22) | `service-scaffolder` (при `absent`), затем `go-implementer` | `services/notify/cmd/notify-api/**`, `services/notify/cmd/migrator/**`, `services/notify/internal/{apiserver,config,migrations}/**` | NTF4-119, 91, 92 зелёные; DoD S3 п.7; УК4-26, 27, 28 с вариантами Д26 · 3 (`RequireApplied` через `dropguard.GooseApplied` на `*sql.DB` из `stdlib.OpenDBFromPool`, «схема не прочитана» отдельно от «версия не применена», `hashtext` имён замков, разрыв соединения замка) | S3-C1, X2 влита в `484-notify`; пин kaname на голову с X2 — нулевой шаг волны S3 после вливания В-5 NTF-3 (§0 «Окна пина NTF-3»); X5 — в пине базы; Е2 (а), Е3 (`notify_api_root` = `present`, §1а); остаток «н»-строк §2б посажен | L |
| S3-C3 | `Get`, `Lookup`, `Delete`: сценарии, аудит, операции (З17) | `rpc-implementer` | `services/notify/internal/apiserver/suppression/**` | NTF4-24…29, 31…33, 82…86 зелёные (86 — 50 повторов под `-race`); УК4-23, 24, 25; УК4-39 — `reconcileOrphanGrace` строго больше верхней границы `…_HANDLING_BUDGET`; `Delete` передаёт в `RunSync` контекст обработчика без отвязки (§2а, Д26 · 8) | S3-C2 | L |
| S3-C4 | край: соединение `notify`, адрес без умолчания, внутренний mux, таблица прав, `prefixToBackend`, декларация `InternalOnly`, `notifysurfaceparity_test.go` (З19) | `api-gateway-registrar` | `gateway/internal/{restmux,opsproxy,config,middleware/embed}/**`, `internal/repohygiene/notifysurfaceparity_test.go` | DoD S3 п.6, 6а, 6б, 8а; NTF4-93, 94, 112; инъекция CX4V-51 и маршрут на `…/Send` — красные | S3-C1 | M |
| S3-C5 | гейт посадки: счёт строк на службу, подперечень, форма (З20) | `deploy-engineer` | `deploy/scripts/{assert-production-posture.sh,listener-form-posture-inject.sh,run-injection-proofs.sh}` | NTF4-109: девять красных, (з), (к), (м) зелёные; УК4-30, 31 | S3-C2 | M |
| S3-C6 | чарт `notify-api`: развёртывание, учётка, сертификаты, PDB, окружение (н1)–(н4) + 12; рендер-гейт случаи (7)–(9); `notify-availability-test.sh` по двум развёртываниям (З21) | `deploy-engineer` | `deploy/helm/notify/**`, `deploy/helm/umbrella/**`, `deploy/tests/helm/{notify-rollout-and-secret-mount-test.sh,notify-availability-test.sh,notify-listeners-test.sh}` | NTF4-117 (7)–(9), NTF4-118 зелёные с инъекциями; перепись портов 1 и 2; УК4-29; УК4-36 зелёная с числом судимых развёртываний 2 — `migrate` у `notify-api` получает ключ тем же шаблоном (Д26 · 4) | S3-C2 | M |
| S3-C7 | проба З9 по корням и графу импортов, строки записи с классом поверхности (З1, З18) | `go-implementer` | `services/notify/servesurface_test.go`, `services/notify/servesurface_ledger.go` | DoD S3 п.8: зелёная и четыре инъекции красные; гейт паритета монтирования зелёный | S3-C2 | M |
| S3-C8 | сквозные S3 на П1: 24…30, 93, 94, 108, 112 | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного; `assert-ban6-external-isolation.py` зелёный вживую и в `--self-test` | S3-C3…C7 | M |
| S3-C9 | страница службы notify: `Lookup`, `Delete`, путь через внутренний слушатель края (DoD S3 п.5) | `docs-writer` | `services/notify/docs/**` | build сайта без битых ссылок | S3-C3 | S |

### S5 — DNS и подпись

> **2026-10-03, решение владельца «перенос DKIM ок» (Д96):** подпись DKIM и проверки DKIM, SPF, политики
> DMARC при старте перенесены в NTF-1 (приёмка NTF-1 Р19, группа P). Полоса S5-D2 снята переносом — её
> исполняет N15 `issue-2915/tasks.md`; S5-D1, S5-D4, S5-D5 в части Основы исполняют N14, D10, D11 там же.
> Здесь остаются только части домена возврата: проверки `rua`, выравнивания, MX, длины адреса возврата
> (S5-D1, NTF4-40, 46, 47, 75, 76, 79), пересылка на домен возврата и MX в зоне стенда (S5-D4), дополнение
> страницы (S5-D5). Предикаты строк ниже читаются с этой оговоркой; маршрут NTF-4 пересобирается после
> Основы.

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S5-D1 | `dnscheck`, таблица родов ответа, организационный домен, двойник П7, страж старта (З14) | `go-implementer` | `services/notify/internal/dnscheck/**`, корень `cmd/notify` | NTF4-40, 42…51, 75, 76, 79 зелёные; инъекция «ранний `return nil`» — десять красных; УК4-22; УК4-40 — срок запроса DNS и близнец «родитель отменён во время молчания П7 → признак не изменён» (§2а, Д26 · 9) | S3 | M |
| S5-D2 | `dkim` и проверка независимой реализацией (З15) | `go-implementer` | `services/notify/internal/dkim/**`, `deliver` | NTF4-41, 70 (integration) зелёные с близнецом «изменён байт тела» | S5-D1 | M |
| S5-D3 | контрольное письмо (З12) | `go-implementer` | `services/notify/internal/canary/**` | NTF4-73, 100, 103, 105 (integration) зелёные с инъекциями DoD S7 п.1; УК4-20; УК4-38 — срок попытки `min(notify.smtp.sessionTimeout, LEASE_TTL / 3)`: релей отвечает `250` через 35 с при `LEASE_TTL` = 30 с → `not_accepted`, эпоха та же; близнец `250` через 2 с → `accepted` (§2а, Д26 · 7 (3)) | S5-D1, S5-D2 | M |
| S5-D4 | стенд: зона DNS, `dnsConfig` только в стенде, ключевая пара посевом, пересылка на домен возврата (З21) | `deploy-engineer` | `deploy/helm/umbrella/**` | NTF4-52 красный на инъекции `dnsConfig` в `values.prod.yaml`; `helm install` в боевой посадке доходит до готовности (DoD S5 п.3) | S5-D1 | M |
| S5-D5 | страница «требования к DNS установки» (DoD S5 п.4) | `docs-writer` | `services/notify/docs/**` | build без битых ссылок; записей для примера нет | S5-D1 | S |

### S6 — ротация

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S6-E1 | `secretreload`, `mailslots`, таблица ответа на вход, двойник П5 (З4, З16) | `go-implementer` | `services/notify/internal/{secretreload,mailslots}/**`, оба корня | NTF4-53…55, 60…63, 71, 72, 77, 98, 99, 113…116 зелёные; корпус ответов (DoD S6 п.1); УК4-16, 17; УК4-06 зелёный с `secretreload` в обходе — объект `address_key` не строит `Func` (§2а, Д26 · 1) | S3 | L |
| S6-E2 | рендер-гейт случаи (1)–(6) и три прежние инъекции; стратегия переката обоих развёртываний (З21) | `deploy-engineer` | `deploy/tests/helm/notify-rollout-and-secret-mount-test.sh`, `deploy/helm/notify/**` | DoD S6 п.2 | S3-C6 | S |
| S6-E3 | сквозные 56…59, 71 на П1; УК4-19 | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного; бюджет K + `RELOAD_INTERVAL` + M напечатан | S6-E1, S6-E2 | M |
| S6-E4 | страница «два объекта секрета», процедура ротации (DoD S6 п.4) | `docs-writer` | `services/notify/docs/**` | build без битых ссылок | S6-E1 | S |

### S7 — наблюдаемость

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S7-F1 | признаки установки, доли, `feedback_stale`, `feedback_route`, уровни (З12, З13) | `go-implementer` | `services/notify/internal/{reputation,canary,lease}/**` | NTF4-64…69, 74 (integration), 107 (инъекция) зелёные; DoD S7 п.2а, п.3; УК4-04, 04а, 10, 18; УК4-37 (б) — `feedback_stale` поднят при молчащем П10 (§2а, Д26 · 7) | S5-D3 | M |
| S7-F2 | сквозные 68, 74 на П1 | `qa-test-engineer` | сквозные пробы kacho | 74 — в бюджете I + D + 2P + 2M | S7-F1 | S |
| S7-F3 | страницы метрик и «требования к установке» (DoD S7 п.2, п.5) | `docs-writer` | `services/notify/docs/**` | build без битых ссылок | S7-F1 | S |

### Сквозное

| полоса | предмет | исполнитель | предикат снятия |
|---|---|---|---|
| T1 | trail записок: ресурс `Suppression`, rpc `InternalSuppressionService`, пакет notify (одиночка установки), рёбра `notify-api`→kaname и край→`notify-api` (DoD, строка Trail) | `vault-scribe` | vault-gate зелёный, записки названы в trail задачи |
| T2 | задача владельцу спека-книги по `01` и `04` (DoD S7 п.4) | диспетчер | задача заведена, ссылка в trail |

## 2а. Строки отображения захода Д26

Каждая строка — та же, что строка «Д26 · N» в §11 замысла: пункт, полоса, условие к коду и
проба-держатель с близнецом. Здесь — только куда строка ложится; условие дословно живёт в
замысле, второго места о нём нет.

| строка замысла | пункт | полоса | что входит в предикат снятия полосы |
|---|---|---|---|
| Д26 · 1 | CX4V-07 | S1-A2 | `addresskey.New` — только в двух корнях; `Func` и начальный дайджест объекта ключа — из одних байтов; УК4-06 |
| Д26 · 1 | CX4V-07 | S6-E1 | функция проверки `address_key` в `secretreload` не строит `Func`: `unparsable` · `accepted` · `control_mismatch`; NTF4-77 с близнецом NTF4-71; инъекция УК4-06 — `New` в `secretreload` |
| Д26 · 2 | CX4V-55 | S1-A2 | `Establish` на `ReadCommitted` явно; NTF4-116 с `repeatable read` у роли и близнецом |
| Д26 · 3 | CX4V-56 | S3-C2 | `RequireApplied` через `dropguard.GooseApplied` на `*sql.DB` из `stdlib.OpenDBFromPool`; ошибка чтения схемы — отказ «схема не прочитана»; имена замков не совпадают по `hashtext`; разрыв замка — ненулевой выход; варианты УК4-28 |
| Д26 · 4 | CX4V-63 | S1-A1 | запись `dropguard.json` с таблицей `recipient_key_fence` дословно как в миграции, производитель `dropguard_integration_test.go`; УК4-35 с двумя близнецами |
| Д26 · 4 | CX4V-63 | S1-A8 | ключ values `migrator.dropApproved` рендерится в env `MIGRATOR_DROP_APPROVED` контейнера `migrate` каждого развёртывания, пустой ключ — переменной нет (Д28); УК4-36 с близнецом и инъекцией; сквозные S1 на стенде (S1-A9) идут после S1-A8; посадка ствола — одним запросом волны с S1-A1 (§0) |
| Д26 · 4 | CX4V-63 | S3-C6 | `migrate` у `notify-api` получает ключ тем же шаблоном; УК4-36 судит два развёртывания |
| Д26 · 4 | CX4V-63 | S1-A10 | страница перехода S1: одобрение ключом `migrator.dropApproved` до выкатки, очистка ключа после, откат новой миграцией |
| Д26 · 5 | CX4V-64 | S1-A7 | УК4-34 — семейства `notify_` реестра корня против объединения Р12 и перечня NTF-1 (З27 NTF-1) в обе стороны; инъекция — регистрация снятой метрики в `sentlog` |
| Д26 · 5 | CX4V-64 | S2-B1 | ветка «вне таблицы» `ReadAckAnswer` — сигнал `misconfigured` NTF-1, своего счётчика нет |
| Д26 · 5 | CX4V-64 | S2-B2 | неудача отметки `accepted_at` — строка журнала ERROR без адреса и отпечатка, метрики нет |
| Д26 · 6 | CX4V-65 | S1-A5 | уборка по сроку — проход подметальщика у держателя, партия ≤ 1000 строк в транзакции, открытой продлением |
| Д26 · 6 | CX4V-65 | S2-B2 | пакет `sentlog` в УК4-01а; две функции пути письма — по идентичности; NTF4-04 |
| Д26 · 6 | CX4V-65 | S1-A1 | индекс `feedback_message (processed_at)` |
| Д26 · 6 | CX4V-65 | S1-A6 | граница `…_REPUTATION_WINDOW ≤ …_SENT_LOG_RETENTION` в `config.checkCrossBounds`; девятая инъекция Р16 |
| Д26 · 7 | К1 ревью замысла `80dea362` | S1-A3 | срок `pop3.opTimeout` на каждой сетевой операции, продление срока при прогрессе `RETR`; по сроку — закрытие без `QUIT`, выход горутины продления, временный сбой опроса; УК4-37 (а) с инъекциями «срок снят», «такт ждёт сеанс» и близнецом NTF4-104; УК4-37 (в) — остановка при молчащем П10 |
| Д26 · 7 | К1 ревью замысла `80dea362` | S1-A5 | `lease.Tick`: продление → переходы признаков → выпуск → запуск сеанса; сеанс — горутина держателя, не больше одной, такт её не ждёт; контекст горутины — от работы держателя, работа ждёт выхода горутин сеанса и продления, пул закрывается после; признак «сеанс идёт» снимает сама горутина; транзакции держателя — `pgx.TxOptions{IsoLevel: pgx.ReadCommitted}`; УК4-37 (г) |
| Д26 · 7 | К1 ревью замысла `80dea362` | S5-D3 | `canary.Send` под сроком попытки `canary.AttemptTimeout` = `min(notify.smtp.sessionTimeout, LEASE_TTL / 3)`, вычисленным в корне `cmd/notify` один раз; срок вышел — `not_accepted`, эпоха прежняя; УК4-38 с близнецом «`250` позже `LEASE_TTL`» |
| Д26 · 7 | К1 ревью замысла `80dea362` | S7-F1 | `feedback_stale` вычисляется при зависшем сеансе; УК4-37 (б) |
| Д26 · 8 | М2 ревью замысла `80dea362` | S3-C3 | `OrphanGrace` явно постоянной `reconcileOrphanGrace` = 5 мин > 60 с; УК4-39; `Delete` передаёт в `RunSync` контекст обработчика без `WithoutCancel` и `Background` |
| Д26 · 9 | М3 ревью замысла `80dea362` | S5-D1 | каждый вызов резолвера под `dnscheck.queryTimeout` = 5 с; в «ответа нет» — только истечение своего срока при живом родителе; УК4-40 с близнецом «родитель отменён» |

## 2б. Часть Основы (Д100): носитель `notify-api` — остаток против базы (редакция 12)

Решение диспетчера Д100: носитель `notify-api` входит в «Основу». Что утверждается — приёмка §0а, механизмы —
замысел §2а. **Редакция 12 приводит раздел к дереву.** Корень, форму Х5, самоотчёт, оси, десять ручек стадии
S3, соединение края и чарт `api-*` завела NTF-5 (§1а), и служимый набор `notify-api` непуст без NTF-3. Поэтому:
полоса X5 снята (правка в пине базы); каждая «н»-полоса ниже несёт только **остаток** против §1а; связки с
S2-B7 NTF-3 и волны Н3-Ф3а нет (Е10, Е11 сняты предметом); шаг `notify-api-served-set-wave-check.sh` не
заводится — его предмет (развёртывание с пустым набором) в дереве не выражается: носитель с пустым набором
отказывает в старте (Х5), и строка `cmd/notify-api` записи З9 непуста. Регистраций NTF-4 в части Основы
нет — как и было (приёмка §0а).

**Волна Н4-О** — kacho, ветка волны `2919-wave-ntf4-carrier`, база — голова `2914-notify`. Полосы: S3-C2н →
S3-C6н; S3-C4н, S3-C5, S3-C7н параллельно (общих путей нет). Один запрос волны в `2914-notify`. Пинов не
поднимает (§0 «Окна пина NTF-3»: предикат `go.mod` → пусто), поэтому окна В-2 и В-5 её не держат. Старт —
после Е12 (общие пути с линией A NTF-1) и не одновременно с волной соседа на общих путях (§0): с В-3 NTF-3
общие `services/notify/cmd/notify-api/**` (S2-B7), `deploy/helm/notify/**` и `deploy/tests/helm/**`
(S2-B10a). S3-C8н — шаг на стенде после вливания волны и выкатки, не полоса запроса.

**Неделимая цепочка.** S3-C2н → S3-C6н садятся одним запросом: init-контейнер `migrate` у `notify-api`
(S3-C6н) без замка мигратора (S3-C2н) дал бы параллельный накат двух развёртываний без исключения
(замысел З18 «Миграции»).

Каждая полоса кода сдаёт сверх предиката: `go build ./...`, `go vet ./...`, `go test -race` своих пакетов и
`make lint` зелёные числом исполненного; проба с ID сценария — красная на голове волны до кода, исход
напечатан (§0, ban #12).

**S3-C2н — замок мигратора, `RequireApplied`, пробы носителя (З18, З22; приёмка §0а п.1, п.2).**
- исполнитель: `go-implementer` (корень есть — `service-scaffolder` не нужен). Где: kacho, ветка волны Н4-О.
- пути: `services/notify/cmd/migrator/**` (замок); `services/notify/internal/migrations/require.go` и его
  `_test.go` (функция `RequireApplied`, новых миграций нет); `services/notify/cmd/notify-api/**` (вызов
  `RequireApplied` до подъёма слушателей, пробы); `internal/repohygiene/bootpostureform_test.go` (УК4-26).
- after: Е12 не нужна (путей линии A нет); не одновременно с В-3 NTF-3 (`cmd/notify-api/**`); Е2 (а) как в
  строке S3-C2 §2; пин corelib — C0 базы (`dropguard.GooseApplied`, `migratorrun` в нём; предикат §0 → пусто).
- предмет: корень мигратора до `migratorrun.Runner.Up` берёт `pg_advisory_lock(hashtext('kacho_notify.migrate'))`
  на отдельном соединении с `lock_timeout = 5m` и отпускает после `Up`; `migrations.RequireApplied(ctx, pool)` —
  по каждой версии `migrations.FS` через `dropguard.GooseApplied` на `*sql.DB` из `stdlib.OpenDBFromPool`,
  «схема не прочитана» — отдельный отказ от «версия не применена», разрыв соединения замка — ненулевой выход
  (строка Д26 · 3); `notify-api` зовёт её до подъёма слушателей; AST-держатель УК4-26 — полей `ListenerForm` и
  `NoServedServices` вне `servicehost.PostureOf` в не-тестовом дереве kacho нет; держатель Р16 в части
  загрузчика `notify-api` — десять ручек стадии S3 и (н1)–(н4), незаданная — отказ с именем, вне границы —
  отказ с границей, шестая–девятая инъекции Р16 (DoD S3 п.7 в части Основы).
- сценарии и заказы: NTF4-92, NTF4-119 (а)–(г), NTF4-122, NTF4-123 (в базе — зелёная), NTF4-124; УК4-26;
  УК4-28 в вариантах Д26 · 3. Испытательная регистрация NTF4-122 (RV8-08): дескриптор регистрируется в
  `protoregistry.GlobalFiles` один раз на процесс (`sync.Once` или `TestMain`), путь файла не пересекается с
  `proto/kacho/cloud/notify/v1/`, фикстура только в `_test.go` или `internal/testkit`.
- готово, когда: перечисленные зелёные числом исполненного, NTF4-122 — с близнецом; УК4-28: старт на схеме
  без версии, встроенной в бинарь → отказ с именем версии, близнец после наката → готов; УК4-26 печатает
  число осмотренных файлов и красный на инъекции литерала `ListenerForm:` в корне `notify-api`;
  `git -C kacho grep -c 'pg_advisory_lock' <голова> -- services/notify/cmd/migrator/` ≥ 1.
- уровень · размер: R2 (`lane-tier.sh`: путь `internal/migrations/`) · M.

**S3-C4н — край: `nop` → `notify`, только внутренний, гейты поверхности (З19; приёмка §0а п.5).**
- исполнитель: `api-gateway-registrar`. Где: kacho, ветка волны Н4-О.
- пути: `gateway/internal/opsproxy/proxy.go`, `gateway/internal/opsproxy/internal_only_backend_test.go`,
  `gateway/internal/config/**` (только проба загрузчика DoD S3 п.8а, если её нет на базе),
  `gateway/internal/proxy/notify_key_internal_refusal_test.go`, `internal/repohygiene/notifysurfaceparity_test.go`,
  `internal/repohygiene/opprefixliteral_test.go`.
- after: Е12 (линия A правит `gateway/internal/config/config.go` и `notify_test.go`); постоянная
  `ids.PrefixOperationNotify` — в пине базы (§1а), пин не поднимается.
- предмет: `prefixToBackend[ids.PrefixOperationNotify] = "notify"` — постоянная только из каталога corelib
  `ids`, литерала у края нет; бэкенд `notify` объявлен `InternalOnly: true`, проверка
  `listenerorigin.IsExternal` стоит до поиска соединения; `Internal*` notify на внешнем gRPC-входе отвергает
  звено отказа маршрута; маршрутов трёх методов подавления и их строк в таблице прав нет (после Основы).
  Соединение `notify` и адрес без умолчания — в базе (§1а): полоса их не правит, а утверждает пробой п.8а.
- сценарии и заказы: NTF4-112; DoD S3 п.6 в части Основы, п.6а, п.6б, п.8а; УК4-29; инъекция CX4V-51 (в) и
  маршрут на `…/Send` — красные.
- готово, когда: перечисленные зелёные; проба п.6а утверждает происхождение и выбор соединения `notify`
  (RV8-06); гейт `opprefixliteral_test.go` печатает число осмотренных файлов, зелёный на дереве, красный на
  инъекции литерала `"nop"` ключом записи в копии `gateway/internal/opsproxy/proxy.go`, близнец с
  `ids.PrefixOperationNotify` зелёный; значение литерала сравнивается после `strconv.Unquote`, пакет
  `gateway/internal/opsproxy` из обхода не исключён, вторая инъекция `const prefixOperationNotify = "nop"` в
  крае — красная (RV9-04); `git -C kacho grep -n 'ids.PrefixOperationNotify' <голова> -- gateway/internal/opsproxy/proxy.go` → 1.
- уровень · размер: R2 (`gateway/`) · M.

**S3-C5 — гейт посадки: строки по развёртыванию, подперечень, форма (З20; приёмка §0а п.4).**
- исполнитель: `deploy-engineer`. Где: kacho, ветка волны Н4-О.
- пути: `deploy/scripts/{assert-production-posture.sh,listener-form-posture-inject.sh,run-injection-proofs.sh}`,
  `deploy/tests/helm/posture-listener-form-test.sh`.
- after: Е12 — линия A заводит строку на процесс (`kacho-notify`, `kacho-notify-api`, `kacho-notify-probe`),
  суд `listener_form` и `deploy/tests/helm/posture-listener-form-test.sh`; полоса стоит на них.
- предмет: первым шагом — перепись букв NTF4-109 (а)–(м) против гейта и пробы линии A на голове волны:
  буква → держится (тест и строка) · нет; недостающее — по З20, без второго разбора самоотчёта (программа
  вердикта вынимается из гейта, как у пробы линии A).
- сценарии и заказы: NTF4-109 (а)–(м) на строках, захваченных прогоном гейта на стенде, где `notify-api`
  поднят (либо фикстурой пробы линии A с теми же ключами), — живой прогон в S3-C8н; УК4-30, УК4-31.
- готово, когда: девять букв красные, (з), (к), (м) зелёные; перепись букв напечатана в отчёте полосы.
- уровень · размер: R1 · M.

**S3-C6н — чарт `notify-api`: перекат, `migrate`, рендер-гейты (З21; приёмка §0а п.6).**
- исполнитель: `deploy-engineer`. Где: kacho, ветка волны Н4-О после S3-C2н.
- пути: `deploy/helm/notify/templates/api-deployment.yaml`, `deploy/helm/notify/values.yaml`,
  `deploy/helm/umbrella/**` (только если values зонтика задают ключи `notify.api`),
  `deploy/tests/helm/{notify-rollout-and-secret-mount-test.sh,notify-availability-test.sh,notify-listeners-test.sh}`.
- after: S3-C2н (замок мигратора — та же волна, неделимо); Е12 (линия A правит `values.yaml` и
  `configmap.yaml` чарта); не одновременно с В-3 NTF-3 (S2-B10a — `deploy/helm/notify/**`); Е14 — только для
  утверждения NTF4-117 об окружении.
- предмет: `strategy: RollingUpdate`, `maxUnavailable: 0`, `maxSurge: 1`; init-контейнер `migrate` — тот же, что
  у `notify-sender` (`deploy/helm/notify/templates/deployment.yaml`, контейнер `migrate`), без ключа
  `migrator.dropApproved` (его заводит S1-A8); рендер-гейт `notify-rollout-and-secret-mount-test.sh` —
  утверждения NTF4-117 части Основы об учётках двух развёртываний и случаи (7)–(9); `notify-availability-test.sh`
  судит оба развёртывания закрытым перечнем (реплики ≥ 2, PDB с селектором ровно своих подов);
  `notify-listeners-test.sh` — перепись портов: `notify-api` 2, `notify-sender` 1. Объекта ключа отпечатка,
  секрета почты и ключа DKIM `notify-api` не монтирует.
- сценарии и заказы: NTF4-117 (часть Основы), NTF4-118; УК4-29.
- готово, когда: перечисленные зелёные с инъекциями, число судимых развёртываний напечатано (2);
  `helm template` зонтика зелёный; утверждение NTF4-117 об окружении — по Е14.
- уровень · размер: R2 (чарт, посадка) · M.

**S3-C7н — проба З9: инъекция в корне `notify-api` (DoD S3 п.8 в части Основы; RV8-07).**
- исполнитель: `go-implementer`. Где: kacho, ветка волны Н4-О.
- пути: `services/notify/servesurface_test.go`.
- after: — (проба и запись — в базе, §1а; запись `servesurface_ledger.go` полоса не правит).
- предмет: в `TestNTF1G19Injection` — случай «`Register…Server` вне записи в корне `notify-api`» → находка
  «сервис вне ведомости»; близнец — регистрация сервиса, названного строкой `cmd/notify-api`; утверждение
  «у `notify-api` один вызов точки входа носителя, `grpc.NewServer` — 0 у обоих развёртываний».
- сценарии: DoD S3 п.8 в части Основы — две первые инъекции (вторая — `grpcsrv.NewServer` в `cmd/notify` —
  в базе).
- готово, когда: проба зелёная на дереве, новая инъекция красная, близнец зелёный, трижды подряд.
- уровень · размер: R0 · S.

**S3-C8н — NTF4-108 на П1 (шаг на стенде после волны).**
- исполнитель: `qa-test-engineer`; выкатку перед ним делает `deploy-engineer` шагом после вливания волны.
- пути: файлов дерева нет; исход — в отчёте шага и в задаче `#2919`.
- after: волна Н4-О влита и выкачена на П1; Е13 (Given NTF4-108 части Основы — сервисы NTF-3 на носителе).
- предмет: `make -C deploy assert-production-posture` на П1; строки самоотчёта `notify-api` и `notify-sender`;
  перепись портов; захват строк для живого прогона NTF4-109.
- сценарии: NTF4-108; NTF4-109 на захваченных строках.
- готово, когда: гейт зелёный с числом осмотренных развёртываний, `notify-sender` и `notify-api` среди них;
  ключи строк по NTF4-108; перепись портов 2 и 1.
- уровень · размер: R0 · S.

**Что меняется в строках §2 после Основы.** Строки S3-C2, S3-C4, S3-C6, S3-C7 после Основы делают только то,
чего нет ни в базе (§1а), ни в их «н»-строке, и зависят от неё. Строка S3-C5 исполнена в Основе целиком.
Перед стартом S3 после Основы `notify_api_root` = `present` (§1а). Пути `services/notify/internal/apiserver/**`
в строках S3 после Основы — раскладка З1 замысла; на дереве обработчики `notify-api` живут в
`services/notify/internal/apps/kacho/api/<ресурс>/`, загрузчик — `services/notify/cmd/notify-api/internal/config/`
(NTF-5). Это расхождение замысла с деревом, а не выбор исполнителя: решает сверка перед стартом S3 (§0) по
замыслу З1, З22.

## 3. Порядок и параллельность

0. Волна Н4-О (§2б): после Е12, не одновременно с В-3 NTF-3; S3-C2н → S3-C6н; S3-C4н, S3-C5, S3-C7н
   параллельно; затем шаг S3-C8н на стенде (после Е13). Пинов не поднимает. Полосы части носителя от S3-C1, X2
   и стадий S1, S2 NTF-4 не зависят.
1. S1-A1 → S1-A2, S1-A5, S1-A10 → S1-A3 → S1-A4 → S1-A7, S1-A8 → S1-A9 (X1 и S1-A6 — в базе, §1а).
   S1-A8 и S1-A10 стартуют также только после снятия Е7 (§1; снята Д28). S1-A1 и S1-A8 садятся в
   ствол одним запросом волны (§0).
2. S2-B2 параллельно с S2-B1 → S2-B3 (X3, X4 — в пинах базы, подъёма нет).
3. S3-C1 → X2 (kaname `484-notify`) → S3-C2 (нулевой шаг — пин kaname на голову с X2, после вливания В-5
   NTF-3; §0 «Окна пина NTF-3») → S3-C3, S3-C4, S3-C6, S3-C7 параллельно (общих путей нет: C3 —
   `apiserver/suppression`, C4 — `gateway`, C6 — `deploy/helm`, C7 — `servesurface*`; S3-C5 исполнена
   в Основе целиком) → S3-C8, S3-C9. Остаток части носителя (п.0) посажен до S3-C2.
4. S5, S6, S7 после S3. Общие пути у S5-D2 и S2-B1 (`deliver`) не пересекаются по времени. S6-E1 и
   S5-D1 правят корень `cmd/notify` в разных функциях, поэтому сводит их одна волна.
