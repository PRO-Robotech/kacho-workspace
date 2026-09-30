<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2918 (NTF-3, модули kacho подключаются к сервису уведомлений) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md`, который лежит рядом:
> полосы, исполнитель по базе маршрутизации, репозиторий и пути, предикат снятия, зависимости,
> размер. Это не трекер. Состояние полос живёт в задаче `PRO-Robotech/kacho#2918`, в
> `PRO-Robotech/corelib#77` и в PR службы доступа той же волны
> (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 1 · 2026-09-30 — проект маршрута по замыслу редакции 1** (заход в форме Д26: каждая
> строка §11 и §11а замысла стоит в предикате своей полосы).
>
> Состояние `TASKS_READY` этот файл не объявляет: по §5 SDD-1 оно наступает только после
> `DESIGN_APPROVED` и проверенного writing-plans handoff. Handoff либо подтверждает этот файл без
> правки, либо переписывает его. В обоих случаях действует текст на отпечатке, который назван
> записью handoff.

## 0. Правила маршрута

- **Порядок стадий приёмки** (§12 приёмки; §10 замысла):
  - X1 → S1;
  - X2, X4 → S2; S2 стартует после посадки корня `notify-api`, носителя Х5 и края NTF-4 либо вместе с
    ними (замысел З28, Е2);
  - X3 → S3; S3 после S2.

  Стадии NTF-3 стартуют после посадки стадий NTF-1, которые им нужны (Д13; Е3 замысла). Полоса
  стартует, когда сняты её зависимости. Полосы одного яруса без общих путей идут параллельно.
- **Полоса S2-B1 не стартует, пока открыта Е1 замысла** (функция базы `resource-event` против
  запрета замысла NTF-1). Предикат — строка Е1 §1 ниже.
- **Проба до кода** в каждой полосе исполнителя кода. Сначала пишется проба с ID сценария в имени
  (`NTF3-68 · …`) либо с номером заказа (`УК3-NN · …`). Она красная на текущем дереве, исход
  напечатан. Затем код, затем та же проба зелёная — одним изменением (ban #12). Красное фиксируется
  до кода: это свидетельство `RED_PROVEN`.
- **Заказанные пробы** (строки §11а замысла, `УК3-NN`) входят в предикат своей полосы наравне со
  сценариями приёмки. Каждая — с близнецом, отличающимся одним фактом.
- **Гейт** печатает объём осмотренного, падает на пустом обходе и доказан инъекцией в обе стороны.
  Integration-группа даёт тот же вердикт трижды подряд.
- **Единица сдачи** — коммит исполнителя в ветке полосы. Сведение волны, запрос на слияние, вливание
  и снятие веток делает `git-operator` по решению диспетчера. В ствол идёт только одобренное (Д16).
- **Стенд пересоздаётся**: миграции журналов (S1-A1) и `intent_initiator` (S3-C1) на непустых
  таблицах отказывают штатным отказом базы (Д12, Р15). Шаг «пересоздать стенд» — страница перехода
  S3-C5.
- Размер: **S** — до дня одного исполнителя, **M** — два-три дня, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход. «Зелёный» пишется с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | решение по расхождению с замыслом NTF-1 (функция базы `resource-event`, З10 и §13 Е1 замысла) | **открыта**; гейтит S2-B1 | `grep -c 'resource-event' docs/changes/issue-2915/design.md` — строки исключения в ведомости гейта З16 NTF-1 нет (`grep -n 'fanout.*resource-event\|resource-event.*fanout' docs/changes/issue-2915/design.md` → 0 на `bd526f8a`); 1 и более — решение записано |
| Е2 | корень `notify-api`, носитель Х5, край NTF-4 | открыта; гейтит S2-B7, S2-B8, S2-B10 | `git -C kacho ls-tree origin/main services/notify/cmd/notify-api` — пусто на `1d42a6728bf` |
| Е3 | стадии NTF-1 посажены | открыта; гейтит X2 и все полосы S2 | `git -C corelib ls-tree -d origin/main notify` — пусто на `34bc8104a` |
| Е4 | пересверка разбора и ревью замысла на отпечаток `design.md` | **открыта** | `ls docs/changes/issue-2918/reviews/` — нет `design/`, нет `class-exposure/revalidation/` |
| Е5 | строки-ссылки NTF-1 на Р19, Р24, Р27, Р28 | открыта; гейтит X2, X4 | на одобренном отпечатке приёмки NTF-1 строк нет (проверяет диспетчер по записи ревью NTF-1) |

## 2. Полосы

### Правки вне kacho

| полоса | предмет | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| X1 | контракт события `initiator`, `occurred_at`, `name` (З2, §5); `auth.InitiatorOf` (З3); `journaltx` с хуками после коммита (З4); функция журнала с дескриптором таблицы, `NameForm`, `Scope` в дескрипторе вида (З2, З5) | `proto-sync` (контракт в kacho), `go-implementer` (corelib) | kacho · `proto/corelib/subscription/`; corelib · `subscription/`, `outbox/`, `auth/initiator.go`, `journaltx/` | `buf lint`, `buf breaking` зелёные; проба таблицы З3 — каждая строка и близнец (`{system, bootstrap}` → отказ, `{user, system.x-y}` → `system:x-y`); проба `journaltx`: нет принципала → отказ до первого оператора, установка локальна (следующая транзакция соединения настройки не видит); УК3-04 (хук после коммита); тег corelib | — | L |
| X2 | формы адресата и отказ `Put` по семейству `usr` (З3, УК3-11); ключ окна «проект», `notify_suppressed_total` хуком (Р14); набор `{v_get}` в `notify/spec` (З27); генерация `resource-event`/`operation-failed`, соответствие `kind → resourceType`, функция базы `resource-event` и её триггер в `notifygen init` (З10, З19); набор локалей `{ru, en}` | `go-implementer` | corelib · `notify/feed/**`, `notify/spec/**`, `cmd/notifygen/**` | УК3-11 зелёная; `notifygen -check` сверяет Go- и SQL-половину `resource-event` и красный на инъекции расхождения атрибута; проба функции базы: флаг `false` — 0 строк, строка сигнала строки ленты не даёт, вид вне таблицы — отказ; тег | X1, Е1, Е3, Е5 | L |
| X3 | `operations.FailTerminal` с транзакцией и ставящим отправителем, `NoFailedSender`, `pgRepo.MarkError` в транзакции; `Cancel`/`CancelOwned` без постановки (З16) | `go-implementer` | corelib · `operations/**` | проба CAS: повтор не ставит; путь в запросе зовёт неставящую; `Cancel` не ставит (часть УК3-38 на уровне фундамента); тег | X1 | M |
| X4 | справочник `InternalNotificationRecipientService` (Р7): `Resolve`, `ListProjectAudience`, `ListExpiringCredentials`; тип `notification_recipient_directory`, строка манифеста и правило происхождения, перечень звена, каталог прав, перечень без надзора (Р28); одна функция курсора (З27); инициатор и время журнала службы доступа (Р2); `body.en.yaml` шаблонов службы доступа (Р21) | `go-implementer`, `rpc-implementer` | kaname · `internal/apps/kaname/api/recipientdirectory/**`, `internal/subscriptionjournal/**`, `internal/migrations/**`, `proto/kaname/cloud/iam/v1/`, модель, манифесты, шаблоны | NTF3-24…30, 50, 63, 117…122, 151 зелёные; УК3-07, УК3-08; гейты каталога и подстановки печатают три метода | X1, X2 (набор отношений), Е5 | L |
| X5 | подъём пинов corelib в kacho и kaname, kaname в kacho — одним изменением на каждый тег | `go-implementer` | kacho, kaname · `go.mod`, `go.sum` | `go build ./...` и CI зелёные на новых тегах | X1…X4 по мере выпуска | S |

### S1 — журнал, флаг, перепись, локаль, сборка

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1-A1 | миграции журналов пяти модулей: колонка `initiator` с умолчанием из настройки и `CHECK` из каталога `ids`; `CHECK` вида журнала nlb со словом `notification` (З2, З5, §6) | `migration-writer` | `services/{compute,vpc,nlb,registry,storage}/internal/migrations/**` | NTF3-62 зелёная по пяти таблицам и шести функциям; УК3-28 (переиспользованное соединение) зелёная; держатель монотонности миграций зелёный; `TestNewMigrationCitesAnApprovedAcceptance` | X1, X5 | M |
| S1-A2 | `journaltx` во всех пишущих транзакциях пяти модулей; автокоммитные записи в журналируемые таблицы — через помощника (сверщик storage М1, `Detach` М4); фоновые пути — `AsComponent` (З4, З13) | `go-implementer` (по модулю — пять подполос) | `services/<svc>/internal/{repo,apps,reconciler}/**` | УК3-27 (гейт помощника) зелёный с объёмом по модулю и красный на двух инъекциях; NTF3-57, 58 зелёные; пробы nlb `TestFreeIP_ReconcileStuckDeleting`, `TestFreeIP_CreateOrphanReconciled` зелёные без правки утверждений (CX3G-05) | S1-A1 | L |
| S1-A3 | новые виды в `Mapping.Kinds` (PlacementGroup, GuestAccessKey, AddressPool, Repository), `NameForm` и `Scope` видов, снятие строк `AddressPoolNetworkDefault` (Р2, З2) | `go-implementer` | `services/*/internal/subscriptionjournal/**`, `services/vpc/internal/apps/kacho/api/addresspool/**` | NTF3-59, 60, 61, 62 (часть `AddressPool`) зелёные; УК3-13 (а), (б) | S1-A2 | M |
| S1-A4 | флаг `KACHO_<MODULE>_NOTIFICATIONS_ENABLED`: загрузчик без умолчания, три читателя одного значения, вывод в чарте из `global.kacho.notifications.enabled` + переопределения, метрика (З11) | `go-implementer`, `deploy-engineer` | `services/<svc>/internal/config/**`, корни, `deploy/helm/umbrella/**` | NTF3-64…67 зелёные; УК3-12 (registry, vpc, nlb); самоотчёт посадки несёт флаг | S1-A2 | M |
| S1-A5 | `services/notify/sources.yaml` и гейт переписи 12 шагов; `bundle`/`bundle-check`; таблица видов по полным именам шаблонов; локали; гейты словаря причины и путей кнопок (З29) | `go-implementer` | `services/notify/**`, `internal/repohygiene/notifysources_test.go` | NTF3-01…05, 31…35, 37, 39, 40 зелёные; УК3-05, УК3-06, УК3-09, УК3-24 | X2, X5 | M |
| S1-A6 | гейт NTF3-70 на распознавателе `journalwriteforms`, функции базы живым телом, объём по видам файла; гейт NTF3-60; гейт нелокальной установки инициатора; правка границы 3 `journalwriteforms.go` и абзаца nlb `journal.go` (З4, З10; CX3C-06, CX3E-08) | `go-implementer` | `internal/repohygiene/{journalparity,journalhelper}_test.go`, `internal/repohygiene/journalwriteforms.go`, `services/nlb/internal/subscriptionjournal/journal.go` | NTF3-60, NTF3-70 (инъекции (а)–(г), пустой обход) зелёные; УК3-25, УК3-29; `journalwriteforms_injection_test.go` зелёный | S1-A7, S1-A8, S2-B1 для «строки ленты» | M |
| S1-A7 | nlb: эмиттер модуля и `emitReconcileFinalize` — через функцию фундамента с дескриптором; `SystemPrincipalFor` вместо `SystemPrincipal` у отправителей nlb и compute на пишущих межмодульных вызовах; гейт `SystemPrincipal()` на пересылаемых путях (З5, З6, З13) | `go-implementer` | `services/nlb/internal/{repo,apps/kacho/jobs}/**`, `services/compute/cmd/compute/stuck_delete_finisher.go`, `internal/repohygiene/**` | NTF3-160 (б) зелёная; УК3-30, УК3-31; литеральных вставок в журнал nlb — 0 (печать гейта NTF3-70) | S1-A2 | M |
| S1-A8 | посев стенда: одна транзакция с `system:stand-seed`, строка журнала в CTE `RETURNING`, без `'actor'`, одна форма состояния; рецепт после миграций (З8) | `deploy-engineer` | `deploy/scripts/{vpc-address-pool-baseline.sql,seed-vpc-address-pools.sh}`, `internal/repohygiene/seedaddresspoolparity_test.go` | NTF3-162 и близнец зелёные; УК3-37 | S1-A1 | S |

### S2 — лента событий, лента консоли, настройки, подписки, сводка, контакты, справочник

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S2-B1 | `notifygen init` у пяти модулей: миграция ленты, функция базы `resource-event` и триггер на журнале; сервер ленты, звено Р2, каталог прав, строка манифеста, ключ ленты, декларация `.spiffe` — шаги §3 (1)–(12) (З10) | `migration-writer` (миграции), `go-implementer` (корни) | `services/<svc>/internal/migrations/**`, `services/<svc>/cmd/**`, `services/<svc>/manifest.yaml`, `services/<svc>/notifications/**` | NTF3-68, 69, 71, 160 (а)–(в) зелёные; NTF3-04 печатает «шагов проверено 5 × 9 + 1»; строк ленты на строку журнала — 1 в печати NTF3-70 | **Е1**, X2, S1-A1…A4 | L |
| S2-B2 | vpc: `NetworkInterface UPDATED` на Attach/Detach, `Address UPDATED` на `SetAddressReference` и `DETACHED`, решение «изменилось» в том же операторе; инициатор из trust-aware пары; правка комментариев `cqrsadapter.go:169-171` и `values.prod.yaml:395`; сужение `ListByInstance` не трогается (З12) | `go-implementer` | `services/vpc/internal/{apps/kacho/services/{nicinternal,addressref},repo/cqrsadapter,repo/kacho/pg,apps/kacho/api/address}/**`, `deploy/helm/umbrella/values.prod.yaml` | NTF3-160 (д), (е), (ж) зелёные; УК3-33; `git diff` полосы не касается `authzfilter` и `ListByInstance` | S1-A2, S2-B1 | L |
| S2-B3 | storage `Attach`/`Detach` в `journaltx` с пересланным инициатором; личность `releaseAndDelete` — исполнителя; фоновый проход compute — `AsComponent` (З7, З12, З13) | `go-implementer` | `services/storage/internal/{repo/pg,apps}/**`, `services/compute/internal/api/instance/**`, `services/compute/cmd/compute/**` | NTF3-160 (г), (з) зелёные; УК3-32, УК3-39 | S1-A2, S2-B1 | M |
| S2-B4 | `notify-sender`: приём `INGESTED`, `inbox_clock`, `inbox_event` с уникальностью, уборщик, `RightObject` (З19, З20) | `go-implementer`, `migration-writer` (`kacho_notify`) | `services/notify/internal/{ingest,inbox}/**`, `services/notify/internal/migrations/**` | NTF3-72 зелёная; соответствие `kind → resourceType` из сборки (часть NTF3-73); УК3-16, УК3-35 | X2, Е3, S2-B1 | L |
| S2-B5 | сводка: окна, открытие и закрытие, поднятие `inbox_clock.t` до `E`, страницы аудитории, `Resolve` строк (З21) | `go-implementer` | `services/notify/internal/digest/**` | NTF3-103…111 зелёные; УК3-17, УК3-18 | S2-B4, S2-B9 | L |
| S2-B6 | мгновенные письма: схлопывание, всплеск, потолок, сетка условным оператором, отметка «ушло» (З22) | `go-implementer` | `services/notify/internal/instant/**` | NTF3-96…102, 153 зелёные; УК3-19 | S2-B4, S2-B9 | M |
| S2-B7 | контракт и сервисы `notify-api`: лента, каталог, настройки (`seen_up_to` по З23), подписки (З24), контакты (З25); регистрации с классом `public` в ведомости З9 NTF-4; снятие изъятий осей; ведомость G19; гейт графа импортов (З28) | `proto-sync`, затем `rpc-implementer` | `proto/kacho/cloud/notify/v1/`, `pkg/api/kacho/cloud/notify/v1/`, `services/notify/internal/apiserver/**`, `services/notify/servesurface_ledger.go`, `services/notify/cmd/notify-api/**` | `buf lint`, `buf breaking` зелёные; NTF3-73…95, 112…116, 149, 156…158, 161 зелёные; УК3-20, УК3-21, УК3-23, УК3-26, УК3-34; УК4-27 NTF-4 и `TestScopeFilteredRowsBelongToADomainThatEnforcesThem` зелёные на ревизии посадки | S2-B4, X5, **Е2** | L |
| S2-B8 | край: REST-маршруты `/notify/v1/…`, перечень разрешённых методов, каталог прав — из дескрипторов (З28) | `api-gateway-registrar` | `gateway/internal/{restmux,allowlist,middleware/embed}/**` | NTF3-159 (а)–(е) зелёные; `allowlist/parity_test.go` и `permission-catalog-check` зелёные | S2-B7, **Е2** | M |
| S2-B9 | `notify-sender`: клиент справочника, `resolvecell.Of` (таблица Р7), клетки Р24, формы адресата по пространству (З27) | `go-implementer` | `services/notify/internal/{directory,resolvecell,deliver}/**` | NTF3-15…23, 36, 46…48, 55, 56, 125, 150, 154, 155 зелёные; NTF3-18, NTF3-19 — `t0` из времени коммита в базе, момент приёма из приёмника, задержка напечатана, N прогонов (CX3B-22) | X4, S2-B4 | M |
| S2-B10 | чарт `notify`: два развёртывания, учётка `kacho-notify-api`, контрольная сумма объекта ключа у обоих, адрес и срок службы доступа, PDB, ≥2 реплики; допуск `notify-sender` в политике vpc из перечня источников (З30) | `deploy-engineer` | `deploy/helm/{notify,umbrella}/**`, `deploy/tests/helm/**` | NTF3-66, 126, 127, 128 зелёные; `TestMailSecretIsMountedByTheSenderOnly`, `TestNotifyServesNoSendVerb` зелёные | S2-B7, **Е2** | M |
| S2-B11 | обвязка NTF3-160 (С15, С21, С22 в тестовом дереве, сверщик не запущен) и интеграционные S2 (З33) | `integration-tester` | тестовые деревья `services/{storage,compute,vpc,nlb}/**` | NTF3-160 (а)–(з) зелёные трижды подряд; `git grep` в не-тестовом дереве storage и compute — новых ручек «без сверщика» и перевода статуса 0 | S2-B1…B3 | M |

### S3 — сбои ресурсов, сбой операции, напоминания, сквозные

| полоса | предмет | исполнитель | пути (kacho) | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S3-C1 | `intent_initiator` у трёх таблиц без умолчания; один конструктор; запись шестью вставками; вычитание из полезной нагрузки журнала (З14) | `migration-writer`, `go-implementer` | `services/storage/internal/{migrations,domain,repo/pg}/**` | NTF3-09, 51 зелёные; УК3-01, УК3-02; интеграционная проба на каждый глагол Р15 | S2 | M |
| S3-C2 | запись перехода: оператор CTE, предикаты сбоя и восстановления, `SendX` шести шаблонов, классификация `Put`, отказ пустой причины, `loop.go:376` без отбрасывания (З15, З17, З18) | `go-implementer` | `services/storage/internal/{reconciler,notifications}/**`, `internal/repohygiene/storageerrorwriters_test.go` | NTF3-06, 07, 10, 12, 13, 14, 43, 49, 52, 53, 54, 129, 130, 131, 132 зелёные; УК3-03, УК3-15, УК3-40, УК3-41, УК3-43 | S3-C1, X2 | L |
| S3-C3 | `FailTerminal` в пяти модулях: генерируемые `operation-failed`, объявление «тип метаданных → вид», транзакционная запись (З16, З17) | `go-implementer` | `services/<svc>/internal/{apps,notifications}/**`, корни | NTF3-133…139 зелёные; УК3-10, УК3-14, УК3-38, УК3-42 | X3, S2-B1 | M |
| S3-C4 | задание напоминаний: `feed.NewLocal`, все страницы, границы на проход, `Put` затем однократность, проверка контакта с тремя исходами; `identityNamespaces = {kaname, notify}` (З26) | `go-implementer` | `services/notify/internal/reminder/**` | NTF3-140…145, 152 зелёные; УК3-22 | S2-B9 | M |
| S3-C5 | гейты NTF-1 печатают пять модулей; строки рёбер спеки (DoD 12.2 п.6); страницы арендатора модулей и инженерная страница `notify`, страница перехода (пересоздание стенда); записи vault | `go-implementer` (гейты), `docs-writer`, `vault-scribe` | `services/*/docs/**`, `services/notify/docs/**` | DoD 12.3 п.4, п.7, п.8; build сайтов без битых ссылок; строки рёбер — строкой «нужен следующий» автору спеки-книги | S3-C2…C4 | M |
| S3-C6 | сквозные стенда NTF3-38, 146…148; записи ведомости производителя у новых коллекций newman | `qa-test-engineer` | сквозные пробы kacho | зелёные числом исполненного; ведомость производителя сверена | S3-C1…C5 | M |

## 3. Что проверяет handoff

1. Каждая строка §11 и §11а замысла стоит в предикате ровно одной полосы: `УК3-01…43` (кроме
   неиспользуемого `УК3-36`) — `grep -o 'УК3-[0-9]*' tasks.md | sort -u`.
2. Е1 названа гейтом S2-B1, Е2 — гейтом S2-B7, S2-B8, S2-B10.
3. Полосы, трогающие фоновые пути (S1-A2, S1-A7, S2-B3), не меняют их исход: пробы nlb `TestFreeIP_*`
   зелёные без правки утверждений, УК3-39 зелёная.
