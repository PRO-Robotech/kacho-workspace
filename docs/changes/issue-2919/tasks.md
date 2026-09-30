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
> одобрения сноса в env контейнера `migrate` — зависимость Е7 замысла.
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
- Размер: **S** — до дня одного исполнителя, **M** — два-три дня, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход. «Зелёный» пишется с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | новая редакция приёмки по сверке соседей (§0а, §13 замысла) | **открыта**; редакция 22 внесена, записи ревью на неё нет; блокирует `DESIGN_APPROVED` | `grep -c '29cfa368\|ef9c6801' docs/specs/sub-phase-NTF-4-delivery-feedback-reputation-acceptance.md` → 18; `ls docs/specs/reviews/sub-phase-NTF-4-delivery-feedback-reputation-acceptance/ \| grep -c 01b2888` → 0 |
| Е2 | согласование с замыслом NTF-1: ключ самоотчёта формы, замещение ключа сетки (З2, З18) | открыта; гейтит полосы S1-A2, S1-A8 и S3-C2 | `grep -n 'Е11' docs/changes/issue-2915/design.md` — строка зависимости есть, снятия нет |
| Е3 | замысел NTF-3: класс поверхности своих регистраций, изъятия осей | открыта; гейтит S3-C2 только при исходе `notify_api_root: present` | `ls docs/changes/issue-2918/design.md` — файла нет |
| Е4 | пересверка разбора и ревью замысла на отпечаток `design.md` | **открыта** | `ls docs/changes/issue-2919/reviews/` — нет `design/`; в `class-exposure/revalidation/` одна запись, на редакцию 1 (`b9149d3c…`), на редакцию 2 записи нет |
| Е5 | задачи правок Х1–Х5 | **открыта** | задач в трекерах corelib и kaname с заголовками §1.1 приёмки нет (проверяет диспетчер) |
| Е6 | стадии NTF-1 посажены | открыта | `git -C kacho ls-tree origin/main services/notify` — пусто на `1d42a6728bf` |

## 2. Полосы

### Правки вне kacho

| полоса | предмет | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| X1 | префиксы `nsp`, `nop` (Х1) | `go-implementer` | corelib · `ids/ids.go` | проба каталога префиксов зелёная; `grep -rn '"nop"\|"nsp"' --include=*.go ids/` → по одной записи; тег corelib | Е5 | S |
| X3 | `SUPPRESSED(reason)` в ленте (Х3) | `proto-sync` (контракт kacho), `go-implementer` (сервер ленты corelib) | kacho · `proto/corelib/notify/`; corelib · `notify/feed/**` | держатель закрытого словаря знает четыре причины, и это доказано инъекцией; проба повтора `Ack` на `SUPPRESSED`; тег | Е5, `corelib#77` | M |
| X4 | пин corelib в kaname (Х4) | `go-implementer` | kaname · `go.mod` | `go build ./...` и CI kaname зелёные на теге Х3 | X3 | S |
| X2 | каталог прав `notify.suppressions.*`, отображение, сверка с аннотациями, проба NTF4-120/121 (Х2, З17) | `go-implementer` | kaname · `internal/apps/kaname/seed/embedded/permission_catalog.json`, `internal/authzmap/permissions_to_relations.go`, `internal/apps/kaname/api/authorize/` (проба) | держатель каталога kaname зелёный; команда сверки З17 → пустой `diff`; NTF4-120/121 зелёные (два SAN, счёт вопросов модели) | Е5, C1 | M |
| X5 | ось `HostForm` + `HostInternalOnly`, `buildServer`, `PostureOf`, поля `BootPosture` (Х5, З18) | `go-implementer` | corelib · `servicecontract/`, `servicehost/`, `observability/bootposture.go` | integration-проба Х5 зелёная; `TestBothListenersRefuseIdenticallyOnTheWire` с формой и инъекцией «цепочка без звена прав» красная, затем зелёная; тег (DoD S3 п.8б) | Е5, Е2 (а), `corelib#77` | L |

### S1 — приём обратной связи

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1-A1 | миграции §6: `sent_log`, `feedback_message`, `feedback_event`, `suppression`, `feedback_lease`, `canary_issue`, `feedback_state`, `install_flag`, `address_key_check`, затем `DROP TABLE recipient_key_fence` | `migration-writer` | `services/notify/internal/migrations/**` | держатель монотонности миграций зелёный; УК4-12 (23514), УК4-33 (`now()` в SQL — 0) зелёные с инъекциями; DoD S1 п.2; запись `dropguard.json` и её производитель `dropguard_integration_test.go`, `TestEveryDropGuardManifestHasAProducer` зелёный; УК4-35 (§2а, Д26 · 4); индекс `feedback_message (processed_at)` (Д26 · 6) | X1, Е6 | M |
| S1-A2 | `addresskey`: функция отпечатка, `Establish`, набор, скрытие ключа; снятие ограды и её сторожа в `limits` и `deliver`; объект ключа томом в загрузчике `notify-sender` (З2, З3) | `go-implementer` | `services/notify/internal/{addresskey,limits,deliver,config}/**`, `services/notify/cmd/notify/**` | NTF4-23, 77, 106 зелёные (106 красная на инъекции «код аутентичности над постоянной строкой»); УК4-05, 06, 07, 08; `redaction_test.go`; `Establish` на `ReadCommitted`, NTF4-116 с `repeatable read` у роли (§2а, Д26 · 1, Д26 · 2) | S1-A1, Е2 (б) | M |
| S1-A3 | клиент `pop3`, двойник П10, сеанс, независимое продление (З7) | `go-implementer` | `services/notify/internal/{pop3,feedback}/**`, двойник П10 в тестовом дереве | NTF4-10, 104 зелёные (104 красная на инъекции «продление только в начале сеанса»); УК4-02 | S1-A1, S1-A5 | M |
| S1-A4 | вид, токен-источник, классификация, ограничения разбора, корпус П3, `suppression.Apply` (З8, З9) | `go-implementer` | `services/notify/internal/{feedback,suppression}/**`, корпус `internal/feedback/testdata/corpus/` | NTF4-01…09, 11…14, 78 (integration) зелёные; корпус сверен с таблицей в обе стороны (DoD S1 п.3); УК4-11 | S1-A2, S1-A3 | L |
| S1-A5 | аренда с эпохой, такт, подметальщик у держателя, NTF4-15 (З11) | `go-implementer` | `services/notify/internal/{lease,suppression}/**` | NTF4-95…97, 15 зелёные (95 красная на инъекции «продление только фиксацией»); УК4-01, 01а; уборка по сроку — проход подметальщика у держателя, партии под продлением (§2а, Д26 · 6) | S1-A1 | M |
| S1-A6 | 23 ручки S1, группы, зависимые границы, `required_knobs_test.go` (З22) | `go-implementer` | `services/notify/internal/config/**` | DoD S1 п.5: зелёная и красная на четырёх инъекциях; NTF4-87, 88; зависимая граница окна долей и срока журнала (§2а, Д26 · 6) | Е6 | M |
| S1-A7 | `reputation.Register`, наборы метрик, метки (З13, часть S1) | `go-implementer` | `services/notify/internal/reputation/**`, корень `cmd/notify` | УК4-21 зелёный; NTF4-33 (журнал и метки S1) зелёная; УК4-34 — семейства `notify_` реестра корня против объединения Р12 и перечня NTF-1 в обе стороны, двух снятых метрик нет (§2а, Д26 · 5) | S1-A4 | S |
| S1-A8 | чарт: объект ключа томом у `notify-sender`, снятие `secretKeyRef` и `checksum/recipient-key`, правка гейта D1; приёмник ящика стенда (З21) | `deploy-engineer` | `deploy/helm/notify/**`, `deploy/helm/umbrella/**`, `deploy/notify_secret_layout_test.go` | гейт D1 зелёный в форме З21 и красный на инъекции `secretKeyRef`; DoD S1 п.6; УК4-32 — версия образа и её возможности напечатаны в отчёте полосы; путь одобрения сноса в env контейнера `migrate` — по снятию Е7 замысла; в этом заходе ключа чарта нет (§2а, Д26 · 4) | S1-A2 | M |
| S1-A9 | сквозные S1 на П1: 01, 02, 11, 13, 15 (две реплики) | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного, признаки установки сверены на обеих репликах | S1-A1…A8 | M |
| S1-A10 | страница перехода S1 службы notify: снос ограды, одобрение `MIGRATOR_DROP_APPROVED` до выкатки там, где стартовала NTF-1, его снятие после применения, откат новой миграцией (замысел З2, §10 п.4; §2а, Д26 · 4) | `docs-writer` | `services/notify/docs/**` | build сайта без битых ссылок; страница ссылается на `docs/architecture/drop-preflight-counts-the-live-database.md`, а не пересказывает его | S1-A1 | S |

### S2 — подавление при отправке

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S2-B1 | клетка 6а в `Decide`, исход раз на выдачу, таблица ответа `Ack`, синхронный 5xx на `RCPT` (З10) | `go-implementer` | `services/notify/internal/deliver/**` | NTF4-18…23, 80, 81, 89, 90, 101, 102, 110 (красная на инъекции пересчёта), 111 зелёные; УК4-13, 14, 15; ветка «вне таблицы» `ReadAckAnswer` без своего счётчика — сигнал `misconfigured` NTF-1 (§2а, Д26 · 5) | S1, X3, X4 (пины одним изменением) | L |
| S2-B2 | `returnaddr`, `sentlog`, `List-Unsubscribe` через `notify/form` (З5, З6) | `go-implementer` | `services/notify/internal/{returnaddr,sentlog,deliver}/**` | NTF4-13, 14 (адрес и заголовок ушедшего письма) зелёные; NTF4-04 зелёная; УК4-03, 09; УК4-01а по пакету `sentlog` (уборка по сроку под продлением, две функции пути письма — по идентичности); неудача отметки `accepted_at` — строка журнала ERROR без адреса, метрики нет (§2а, Д26 · 5, Д26 · 6) | S1-A2, S1-A5 | M |
| S2-B3 | сквозные 16, 17 на П1 (окно `recovery` NTF-2) | `qa-test-engineer` | сквозные пробы kacho | DoD S2 п.1; ответы глагола kaname сверены побайтово | S2-B1, S2-B2 | M |

### S3 — снятие подавления

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S3-C1 | контракт `InternalSuppressionService` (§5) | `proto-sync` | `proto/kacho/cloud/notify/v1/`, `pkg/api/kacho/cloud/notify/v1/` | `buf lint`, `buf breaking` зелёные; держатель аннотаций зелёный (DoD S3 п.1) | S2 | S |
| S3-C2 | корень `notify-api` либо дополнение существующего (по `notify_api_root`), носитель Х5, `PostureOf`, оси, (н1)–(н4), 12 ручек, `RequireApplied`, замок мигратора, сверщик операций, изъятия с пробой (З18, З22) | `service-scaffolder` (при `absent`), затем `go-implementer` | `services/notify/cmd/notify-api/**`, `services/notify/cmd/migrator/**`, `services/notify/internal/{apiserver,config,migrations}/**` | NTF4-119, 91, 92 зелёные; DoD S3 п.7; УК4-26, 27, 28 с вариантами Д26 · 3 (`RequireApplied` через `dropguard.GooseApplied` на `*sql.DB` из `stdlib.OpenDBFromPool`, «схема не прочитана» отдельно от «версия не применена», `hashtext` имён замков, разрыв соединения замка) | S3-C1, X5, X2 (пины одним изменением), Е2 (а), Е3 при `present` | L |
| S3-C3 | `Get`, `Lookup`, `Delete`: сценарии, аудит, операции (З17) | `rpc-implementer` | `services/notify/internal/apiserver/suppression/**` | NTF4-24…29, 31…33, 82…86 зелёные (86 — 50 повторов под `-race`); УК4-23, 24, 25 | S3-C2 | L |
| S3-C4 | край: соединение `notify`, адрес без умолчания, внутренний mux, таблица прав, `prefixToBackend`, декларация `InternalOnly`, `notifysurfaceparity_test.go` (З19) | `api-gateway-registrar` | `gateway/internal/{restmux,opsproxy,config,middleware/embed}/**`, `internal/repohygiene/notifysurfaceparity_test.go` | DoD S3 п.6, 6а, 6б, 8а; NTF4-93, 94, 112; инъекция CX4V-51 и маршрут на `…/Send` — красные | S3-C1 | M |
| S3-C5 | гейт посадки: счёт строк на службу, подперечень, форма (З20) | `deploy-engineer` | `deploy/scripts/{assert-production-posture.sh,listener-form-posture-inject.sh,run-injection-proofs.sh}` | NTF4-109: девять красных, (з), (к), (м) зелёные; УК4-30, 31 | S3-C2 | M |
| S3-C6 | чарт `notify-api`: развёртывание, учётка, сертификаты, PDB, окружение (н1)–(н4) + 12; рендер-гейт случаи (7)–(9); `notify-availability-test.sh` по двум развёртываниям (З21) | `deploy-engineer` | `deploy/helm/notify/**`, `deploy/helm/umbrella/**`, `deploy/tests/helm/{notify-rollout-and-secret-mount-test.sh,notify-availability-test.sh,notify-listeners-test.sh}` | NTF4-117 (7)–(9), NTF4-118 зелёные с инъекциями; перепись портов 1 и 2; УК4-29 | S3-C2 | M |
| S3-C7 | проба З9 по корням и графу импортов, строки записи с классом поверхности (З1, З18) | `go-implementer` | `services/notify/servesurface_test.go`, `services/notify/servesurface_ledger.go` | DoD S3 п.8: зелёная и четыре инъекции красные; гейт паритета монтирования зелёный | S3-C2 | M |
| S3-C8 | сквозные S3 на П1: 24…30, 93, 94, 108, 112 | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного; `assert-ban6-external-isolation.py` зелёный вживую и в `--self-test` | S3-C3…C7 | M |
| S3-C9 | страница службы notify: `Lookup`, `Delete`, путь через внутренний слушатель края (DoD S3 п.5) | `docs-writer` | `services/notify/docs/**` | build сайта без битых ссылок | S3-C3 | S |

### S5 — DNS и подпись

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S5-D1 | `dnscheck`, таблица родов ответа, организационный домен, двойник П7, страж старта (З14) | `go-implementer` | `services/notify/internal/dnscheck/**`, корень `cmd/notify` | NTF4-40, 42…51, 75, 76, 79 зелёные; инъекция «ранний `return nil`» — десять красных; УК4-22 | S3 | M |
| S5-D2 | `dkim` и проверка независимой реализацией (З15) | `go-implementer` | `services/notify/internal/dkim/**`, `deliver` | NTF4-41, 70 (integration) зелёные с близнецом «изменён байт тела» | S5-D1 | M |
| S5-D3 | контрольное письмо (З12) | `go-implementer` | `services/notify/internal/canary/**` | NTF4-73, 100, 103, 105 (integration) зелёные с инъекциями DoD S7 п.1; УК4-20 | S5-D1, S5-D2 | M |
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
| S7-F1 | признаки установки, доли, `feedback_stale`, `feedback_route`, уровни (З12, З13) | `go-implementer` | `services/notify/internal/{reputation,canary,lease}/**` | NTF4-64…69, 74 (integration), 107 (инъекция) зелёные; DoD S7 п.2а, п.3; УК4-04, 04а, 10, 18 | S5-D3 | M |
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
| Д26 · 4 | CX4V-63 | S1-A8 | путь `MIGRATOR_DROP_APPROVED` в env контейнера `migrate` не назван этим заходом — зависимость Е7 замысла; до её снятия выкатки на базу со строкой ограды нет |
| Д26 · 4 | CX4V-63 | S1-A10 | страница перехода S1: одобрение до выкатки, снятие после, откат новой миграцией |
| Д26 · 5 | CX4V-64 | S1-A7 | УК4-34 — семейства `notify_` реестра корня против объединения Р12 и перечня NTF-1 (З27 NTF-1) в обе стороны; инъекция — регистрация снятой метрики в `sentlog` |
| Д26 · 5 | CX4V-64 | S2-B1 | ветка «вне таблицы» `ReadAckAnswer` — сигнал `misconfigured` NTF-1, своего счётчика нет |
| Д26 · 5 | CX4V-64 | S2-B2 | неудача отметки `accepted_at` — строка журнала ERROR без адреса и отпечатка, метрики нет |
| Д26 · 6 | CX4V-65 | S1-A5 | уборка по сроку — проход подметальщика у держателя, партия ≤ 1000 строк в транзакции, открытой продлением |
| Д26 · 6 | CX4V-65 | S2-B2 | пакет `sentlog` в УК4-01а; две функции пути письма — по идентичности; NTF4-04 |
| Д26 · 6 | CX4V-65 | S1-A1 | индекс `feedback_message (processed_at)` |
| Д26 · 6 | CX4V-65 | S1-A6 | граница `…_REPUTATION_WINDOW ≤ …_SENT_LOG_RETENTION` в `config.checkCrossBounds`; девятая инъекция Р16 |

## 3. Порядок и параллельность

1. Х1 → S1-A1, S1-A6 параллельно → S1-A2, S1-A5, S1-A10 → S1-A3 → S1-A4 → S1-A7, S1-A8 → S1-A9.
2. Х3 → Х4 → S2-B2 параллельно с S2-B1 → S2-B3.
3. S3-C1 → Х2; Х5 → S3-C2 → S3-C3, S3-C4, S3-C5, S3-C6, S3-C7 параллельно (общих путей нет: C3 —
   `apiserver/suppression`, C4 — `gateway`, C5 — `deploy/scripts`, C6 — `deploy/helm`, C7 —
   `servesurface*`) → S3-C8, S3-C9.
4. S5, S6, S7 после S3. Общие пути у S5-D2 и S2-B1 (`deliver`) не пересекаются по времени. S6-E1 и
   S5-D1 правят корень `cmd/notify` в разных функциях, поэтому сводит их одна волна.
