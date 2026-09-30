<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2917 (NTF-2, почта личности) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md` рядом: полосы,
> исполнитель по базе маршрутизации, пути, предикат снятия, зависимости, размер. Это не
> трекер: состояние полос живёт в задачах `PRO-Robotech/kacho#2917`, `PRO-Robotech/kaname#484` и
> их подзадачах (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 4 · 2026-09-30 — проект маршрута под редакцию 4 замысла** (пересверка разбора
> классов на редакцию 3 — «вернуть в приёмку»; новая полоса S12 по CX2-36: классы мест диспетчера и
> пауза доли `register`). Редакция 3 — проект маршрута под редакцию 3 замысла (пересверка разбора
> классов на редакцию 2 — «вернуть в приёмку»; полосы F1, G2, G3, S2, S4, S5, E2, E4 дополнены
> решениями по CX2-05, 11, 21, 34, 35; новая зависимость Е9 гейтит E2 и E4). Редакция 2 —
> полосы по CX2-03, 05, 07, 08, 11, 12, 14, 17, 20, 21, 28…33, З26 и зависимость Е8. Состояние
> `TASKS_READY` этот файл не объявляет: по §5 SDD-1 оно наступает только после
> `DESIGN_APPROVED` и проверенного writing-plans handoff, который производит `tasks.md`.
> Handoff либо подтверждает этот файл без правки, либо переписывает его; в обоих случаях
> действует текст на отпечатке, названном записью handoff.

## 0. Правила маршрута

- **Порядок:** фундамент → контракты → общее → службы → край → развёртывание → воркспейс.
  Полоса стартует, когда сняты её зависимости; полосы одного яруса без общих путей идут
  параллельно.
- **Проба до кода** в каждой полосе исполнителя кода: сначала проба, красная на текущем дереве с
  напечатанным исходом, затем код, затем та же проба зелёная — одним изменением (ban #12).
  Исключение — миграция: до неё предмета утверждения нет (база маршрутизации §7).
- **Стадии гейтятся производителями:** полосы, чьи держатели требуют `corelib notify/*` и
  `notifygen`, стартуют после Е5 (NTF-1 в пине); полосы З21 и сквозные пробы с `ResolveSend` для
  `kaname` — после Е1. Полосы З3/NTF2-51 — после Е2. Окно адресата с предикатом «лимит возвращён»
  (G2) — после Е8 (а). Звено ограничителя края и консоль (E2, E4) — после Е9: исход `503` и
  поведение консоли на нём наблюдаемы и без сценария приёмки держателя не имеют.
- **Одно изменение на дерево:** все полосы kaname сводятся в линию `kaname#484`, все полосы
  kacho — в линию `kacho#2917` (design.md §10: окна без защиты и окна «путь есть у одной стороны»
  нет). Последовательную цепочку (миграция → репозиторий → use-case одного предмета) ведёт один
  исполнитель.
- **Единица сдачи** — коммит исполнителя в ветке полосы; сведение, запрос на слияние, вливание и
  снятие веток — `git-operator` по решению диспетчера.
- Размер: **S** — до дня одного исполнителя, **M** — два-три, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход; «зелёный» — с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | NTF-1 приведена к Д2 для kaname (`service:kaname`, `ResolveSend` для `kaname`) — либо, при ответе владельца «прочтение Д2 по смыслу», правка NTF-2 (design.md §0.1) | **открыта**; вопрос владельцу о прочтении Д2 | NTF1-F21 на действующем одобрении `d524e7bd` (редакция 10) и на редакциях 11 `4d042803` (`CHANGES_REQUESTED`, круг 1), 12 `b92f0c2b` (`CHANGES_REQUESTED`, круг 2), 13 `05828e42` (вердикта нет) утверждает 0 строк `service:kaname` |
| Е2 | один текст и `reason` отказа флага в NTF-1 и NTF-2 | **открыта** | `grep -c 'NOTIFICATION_DELIVERY_NOT_CONFIGURED' docs/specs/sub-phase-NTF-1-*.md` → 2 |
| Е3 | граница `invite.recipient-per-day-all ≤ 50` в Р8 NTF-2 | **открыта** | строки нет в Р8 на `9098d6ef` |
| Е4 | замещение окна обращений по источнику kaname#456 в §3 NTF-2 | **открыта** | строки нет в §3 на `9098d6ef` |
| Е5 | NTF-1 в стволе kacho и в пине corelib обоих деревьев | открыта | команды Р16 п.1 приёмки NTF-2 на базе старта |
| Е6 | событие одобрения приёмки NTF-2 опубликовано | открыта | запись `9098d6ef….yaml`: `event.status: not_performed` |
| Е7 | `DESIGN_APPROVED` (ревью замысла и пересверка разбора классов на отпечаток `design.md`) | открыта; пересверки на редакции 1 и 2 — «вернуть в приёмку», редакция 3 ждёт новой пересверки | записи `reviews/design/*/<sha>.yaml`, `reviews/class-exposure/revalidation/<sha>.yaml` |
| Е8 | условия к коду NTF-1: (а) экспорт предиката «лимит строки возвращён» из `corelib notify/feed`; (б) читатель ответа справочника в notify трактует незаданный вариант и пустой адрес как ошибку протокола (design.md §13) | **открыта** | заказ пакету `docs/changes/issue-2915`; экспорта нет на пине corelib `34bc8104a83` (NTF-1 не в пине, Е5) |
| Е9 | исход `503` ограничителя края (хранилище недоступно) — сценарий с положительным близнецом; поведение консоли на `503` и на исход `expired` решателя (design.md §13) | **открыта** | `grep -nE '503\|limiter is unavailable\|UNAVAILABLE' docs/specs/sub-phase-NTF-2-identity-provider-mail-removal-acceptance.md` → 0 сценарных попаданий на `9098d6ef` |

Е1–Е4 и Е9 — правки приёмок, которые замысел заказывает (design.md §0.1, §13). Е3, Е4 и Е9 правят NTF-2 —
её отпечаток сменится, первичный разбор классов заводится на новый отпечаток, и замысел
пересверяется на него. Е8 — условия к коду NTF-1, наблюдаемого поведения не меняют.

## 2. Полосы

### Ярус 1 — фундамент (kaname: схема, конфигурация, шаблоны)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| F1 | миграция ленты (`notifygen init`) и миграция З6/§6: снятие трёх таблиц, `mail_windows`, `mail_window_letters` (`feed_id NOT NULL`, внешний ключ на якорь `RESTRICT`), `pending_registrations` (`UNIQUE (address_digest, code_digest)`, `password_probe`, внешний ключ на якорь `RESTRICT`), `invite_acts` (без внешних ключей), `trusted_devices` (индекс `issued_at`), `security_notice_ledger`, живой код; `retired.json` | `migration-writer` | kaname · `internal/migrations/<ts>_*.sql`, `internal/migrations/retired.json` | integration-проба «все миграции на пустую базу»: `invite_mail_outbox` нет, таблица ленты есть (NTF2-44 вторая половина); частичные `UNIQUE` живого кода отвергают вторую живую строку; вставка момента с пустым `feed_id` и акта с `lettered` без `feed_id` отвергнуты; вторая запись адреса с тем же `code_digest` отвергнута (пробы вставки); `DELETE` якоря с живым моментом или записью отвергнут (CX2-35); у `invite_acts` внешних ключей 0 по `pg_constraint` (CX2-21); `db-architect-reviewer` ✅ | Е5, Е7 | M |
| F2 | строгая конфигурация: `UnmarshalExact`; строгость окружения в пространстве `__` — множество прямым выводом `EnvNameOfKey` по ключам декодера; перемер профилей обеих поставок (З5) | `go-implementer` | kaname · `internal/apps/kaname/config/{load.go,strict_env.go}` и пробы | NTF2-48 (а)–(г) зелёная; проба `KANAME_INVITE_MAIL__RELAY` → отказ с именем; близнецы — переменные служб кластера и плоские имена обеих поставок (включая `envconfig` посадки транспорта) — старт; вывод перемера профилей приложен к `kaname#484` | Е7 | M |
| F3 | флаг `notifications.enabled` (`*bool`, `IsSet`), таблица границ Р8 `mail_bounds.go` (она же — регистрация `BindEnv` и вход функции срока хранения З26), страж старта, ключи `authn.secrets.*`, снятие ручек З6 из конфигурации (З2, З5, З18, З23, З26) | `go-implementer` | kaname · `internal/apps/kaname/config/{config,defaults,invite,login_lane,mail_bounds,notifications,secrets}.go` | NTF2-50; NTF2-71 kaname-варианты (а, б, в, л, м, н, о, п, у, ф, ч, ш) и (т) по 32 ключам kaname — печатает число; отказ старта без каждого из двух ключей `authn.secrets.*`; проба привязки «ключ, заданный только переменной окружения, доезжает до поля» по виду таблицы; модульная проба З26 «срок хранения > верхней границы каждого читающего окна», инъекция литерала — красный; `git grep -c 'SetDefault("authn.login.mail-window\|SetDefault("notifications' -- internal/apps/kaname/config` → 0 | F2 | M |
| F4 | 24 шаблона, `required-security.yaml`, лимиты З19, генерация `feedgen/` | `go-implementer` | kaname · `notifications/**`, `internal/apps/kaname/mail/feedgen/**` (вывод `notifygen`) | `notifygen -check` зелёный и печатает 24 (NTF2-08 близнец); NTF2-08 и NTF2-99 (б) инъекции — красные; модульная проба «лимит шаблона ≥ максимума по границам Р8» | Е5, Е7 | M |
| F5 | гейт «обязательный класс» (NTF2-99 (а, в, г)) | `integration-tester` | kaname · `internal/check/required_security_templates{,_test}.go` | четыре копии П8 красные с названным нарушением; на дереве печатает 24 | F4 | S |

### Ярус 2 — контракты

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| C1 | proto `InternalNotificationRecipientService` (§5 design.md; ответ `GetVerifiedAddress` — `oneof result`, без перечисления с нулём), записи каталога прав, перечень методов звена идентичности | `proto-sync` | kaname · `proto/kaname/cloud/iam/v1/internal_notification_recipient_service.proto`, каталог прав, регенерация | `buf lint`, `buf breaking` зелёные; `proto-api-reviewer` ✅; `security-auditor` ✅ (каталог прав тронут) | Е5, Е7 | S |
| C2 | строка манифеста kaname `notifications: {namespace: kaname, readers: [notify]}` (З21) | `go-implementer` | kaname · `internal/servicemanifest/manifest.embedded.yaml` | NTF2-47 близнец (строк права 1) и инъекция `notification_namespace:vpc` — отказ; `TestMRW07_GroupWithItsGrantIsAccepted` зелёный | **Е1**, C1 | S |

### Ярус 3 — общее (kaname: постановка, окно, коды, аудит)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| G1 | пакет `mail` (`Enqueuer`, закрытые исходы, флаг, `Available()`), порт журнала `feed.Put` над `subject_change_repo`, метрики `kaname_notifications_enabled`, `kaname_mail_intents_total` (З1–З3, З17); пакет `mailkey` (`Account`, `Abuse` над `address.Normalized`, З11) | `go-implementer` | kaname · `internal/apps/kaname/mail/**`, `internal/repo/kaname/pg/subject_change_repo.go`, `internal/observability/metrics/` | NTF2-52 (строк 0, метрика 0 и близнец 1); проба отката: строка ленты, журнала и окна уходят вместе (CX2-27); гейт `mail_single_enqueuer` печатает число пакетов, инъекция вызова из `api/user` — красный | F1, F3, F4 | M |
| G2 | окно адресата: `mailwindow.Decide`, `mail_window_repo` (`LockAnchor`: вставка без конфликта, затем `FOR UPDATE` ровно одной строки, иначе повтор до 3 раз; моменты после `feed.Put` с `feed_id`; предикат «лимит возвращён» из corelib), коды с `superseded_at`, предметы уборки по функции З26 и уборка якоря под блокировкой строки; закрытый перечень предметов хранения kaname (З11, З12, З26) | `go-implementer` | kaname · `internal/apps/kaname/mailwindow/**`, `internal/repo/kaname/pg/{mail_window_repo,recovery_code_repo,verification_code_repo}.go`, `internal/apps/kaname/retention/registry.go` | табличная проба `Decide` по рядам Р6 и копии с `floor-interval` = 24 ч (CX2-15); проба `mailkey` (регистр, `+метка`, IDN) (CX2-20); integration-проба гонки первых запросов на новом ключе: `N` параллельных в один момент → одна строка ленты, один момент, один живой код (CX2-14); пробы «строка ленты удалена → момент считается» и «момент без `feed.Put` не пишется» (CX2-32); гейт `mail_clock_parameter` печатает число литералов, инъекция `now()` — красный; integration-проба «уборка якоря между вставкой и `FOR UPDATE` → повтор, одна строка ленты, один момент» с близнецом и проба уборки якоря (снят / не снят / пропущен) (CX2-35); проба закрытого перечня предметов хранения kaname, инъекция таблицы без предмета — красный | G1, **Е8 (а)** | L |
| G3 | класс S: `auditwrite.Insert` (5 форм прод-дерева → 1), карта `securitynotice`, снимок адресатов, `security_notice_ledger`, исходы политики и метрика `kaname_security_notices_total` с меткой `unaddressed` в закрытом наборе, зарегистрированном при старте (З16) | `go-implementer` | kaname · `internal/repo/kaname/pg/{auditwrite/**,access_binding_repo.go,audit_session_revocation_repos.go,reconcile_adapter.go}`, `internal/apps/kaname/seed/bootstrap_admin.go` (писатель аудита — параметр, литерала нет), `cmd/kaname/serve.go`, `internal/apps/kaname/securitynotice/**` | NTF2-89, 90, 91, 92, 93, 95, 96, 97 на П6 зелёные с числом; проба «сбой вставки ленты → событие не зафиксировано» (CX2-25); проба «событие без адресата → глагол исполнен, строк ленты 0, `unaddressed` +1» (CX2-07); проба посева «подменённый писатель получил 1 вызов `cluster_admin.granted`; без писателя — ошибка сборки» (CX2-05) | G1 | L |
| G4 | гейт `audit_outbox_single_writer` (CX2-05): обход прод-дерева Go и храповик миграционных форм | `integration-tester` | kaname · `internal/check/audit_outbox_single_writer{,_test}.go` | на дереве печатает «форм Go 1 · миграционных 3» с именами и пакет `seed` в перечне осмотренных; инъекция литерала в `seed/bootstrap_admin.go` — красный (CX2-05); инъекция каждой из четырёх прежних форм — красный с координатой; четвёртая миграция с вставкой и снятие вставки из копии одной из трёх — красные; пустой обход любой стороны — красный | G3 | S |

### Ярус 4 — службы (kaname: глаголы, справочник, снятие почты)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1 | восстановление и подтверждение адреса на ленте; диспетчер `mailDispatchInFlight`, `dropped_overload`, gauge, страж старта «действующий `max-conns` > 2 × ёмкости»; снятие `ChargeSource` (З7, З12, З13) | `rpc-implementer` | kaname · `internal/apps/kaname/api/humansession/{recovery_request,verification,recovery_complete}.go`, `cmd/kaname/loginlane.go` | NTF2-05, 07, 41, 64, 65, 67, 68, 70, 76, 87 (а, б) на П6 зелёные; NTF2-68 (б) с уборкой, сдвинутой на срок З26; проба `dropped_overload` (CX2-17); проба стража пула (32 → отказ, 33 → старт) (CX2-17); `git grep -c 'ChargeSource' -- ':!*_test.go'` → 0 | G2 | L |
| S2 | регистрация «сначала письмо»: `register` асинхронно тремя шагами (предрешение без блокировки → два вывода `password_probe`/`password_hash` через `DeriveWait` под долей `register` = 1 без транзакции → решение под `LockAnchor` с байтовым сравнением проб), исход `dropped_overload` при истёкшем ожидании места; `confirm.go` (код — со всеми записями постоянным временем, пароль — одна свёртка), путь `register/confirm` полосы формы, `23505` → `401` (З14) | `rpc-implementer` | kaname · `internal/apps/kaname/api/registration/{register,confirm}.go`, `internal/repo/kaname/pg/pending_registration_repo.go`, `internal/passwordverify/{verifier,capacity}.go` (`DeriveWait`), `internal/handler/loginlanehttp/handler.go` | NTF2-75, 83, 84 (50 из 50), 86, 87 (в) на П6 зелёные; проба уборки ожидающих записей (CX2-19); проба «вызовов свёртки пароля на `confirm` = 1 при 0, 1, 44 записях» (CX2-33); integration-проба совпавшего кода и повтора чеканки (CX2-33); по CX2-34: проба голодания «16 работ × 44 записи при ёмкости 2 → вход `matched`, мест под `register` ≤ 1» с близнецом без доли, проба исхода «срок ожидания истёк → записей, моментов, строк ленты +0, `dropped_overload` +1», проба числа выводов (0 при непропуске; 2 при 0, 1, 44 записях), проба места выводов (ни якоря, ни соединения), integration-проба записи, появившейся между шагами → `resent_same` | G2 | L |
| S3 | страж попыток на три пути с ключом `mailkey.Account`; снятие `humansession.AddressKey` (11 вызовов ключа → `Account`, значение записи кода — хранимый адрес); неразбираемый адрес на путях предъявления — `401`; снятие `verification-code-attempts` (З11, З15) | `go-implementer` | kaname · `internal/apps/kaname/api/humansession/{attempt_guard,rate,login,change_password,sf_backup_codes,sf_enroll,sf_remove,step_up,recovery_complete,verification}.go`, `internal/apps/kaname/api/registration/confirm.go` | NTF2-66 (а)–(д) и вариант на `verify-email/confirm` зелёные; гейт `attempt_guard_callers` печатает 3, инъекция четвёртого счётчика — красный; `git grep -c 'AddressKey(' -- ':!*_test.go'` → 0 (CX2-20) | S1, S2 | M |
| S4 | метка устройства, письмо `new-device-login`, признак у `session.issued` (З18) | `go-implementer` | kaname · `internal/apps/kaname/api/humansession/login.go`, `internal/repo/kaname/pg/trusted_device_repo.go`, `internal/handler/loginlanehttp/handler.go` | NTF2-70, 78 на П6; вариант «метка `A` для адреса `B` — запаса нет» (CX2-24); отказ старта без `device-label-key-file`; проба уборки меток по функции З26 на управляемых часах (CX2-35) | S1, G3 | M |
| S5 | приглашения: счёт актов `invite_acts` (`invite`, `resend`) без внешних ключей, блокировки строки аккаунта и ключа адресата (форма с двумя `int4`), висящие по `$now`, отказы до `Operation` (З24) | `rpc-implementer` | kaname · `internal/apps/kaname/api/user/{invite,resend_invite}.go`, `internal/repo/kaname/pg/invite_act_repo.go` | NTF2-69, 77 на П6; integration-проба параллельных приглашений на границе (CX2-21); пробы «повторная отправка сверх потолка → `capped`», «удаление приглашения не возвращает потолок» и «удаление аккаунта не возвращает `recipient-per-day-all`» с близнецом «сутки прошли» (CX2-21); страж `recipient-per-day-all ≤ 50` (после Е3) | G1, G2, **Е3** | M |
| S6 | справочник адресатов: `Check` в теле каждого метода, ответ `oneof` (З20) | `rpc-implementer` | kaname · `internal/apps/kaname/api/notification_recipient/**`, `cmd/kaname/grpc_register.go` | NTF2-88 с близнецом `notify`; `TestCatalogReachability_EveryRowResolvesToAServedMethod` зелёный; проба отказа при снятой аннотации и `UNAVAILABLE` при недоступной двери (CX2-08); проба «вариант ответа задан всегда, адрес непуст» (CX2-31) | C1, G3 | M |
| S7 | флаг в глаголах: `mail.Available()` до чтения адреса, отказ З3 (З2, З3) | `go-implementer` | kaname · глаголы S1, S2, S5 | NTF2-51 (а)–(з) и близнец зелёные | S1, S2, S5, **Е2** | S |
| S8 | снятие почты kaname: отправитель, проводка, гейт MAIL-47 → NTF2-44, `mail_kind_sender_parity` → NTF2-45, метрики отправителя, перепись §3б (З6) | `go-implementer` | kaname · `internal/clients/invite_mail*`, `cmd/kaname/invite_mail_wiring*`, `internal/check/{mail_send_paths,mail_kind_sender_parity}*`, `internal/observability/metrics/` | NTF2-44 (печать пакетов > 0; инъекция П8 — красный), NTF2-45 (а, б); DoD п.17: предикат §1.1 даёт ровно три файла | S1, S2, S5 | M |
| S9 | сервер ленты на внутреннем слушателе по флагу; ключ журнала по флагу (З2) | `go-implementer` | kaname · `cmd/kaname/{grpc_register,subscription_wiring}.go` | NTF2-46 с близнецом `notify`, NTF2-06 (надгробие выдачи → `DENIED(revoked)`), NTF2-09 (`DEFER(template_skew)`), NTF2-52 `UNIMPLEMENTED` — на П6 | G1, **Е1** | S |
| S10 | гейт смены адреса и писателей `users.email` через `address.Normalized` (З25) | `go-implementer` | kaname · `internal/check/people_address_writers.go` | NTF2-98 красная копия и близнец (печать числа операторов > 0); инъекция записи сырой строки в `users.email` — красный (CX2-20) | S2, S5 | S |
| S11 | самостоятельная поставка kaname (NTF2-33); правило тревоги `unaddressed` > 0 (CX2-07) | `deploy-engineer` | kaname · `deploy/{values.yaml,templates/configmap.yaml,templates/deployment.yaml}`, правила тревог поставки | NTF2-33 (а)–(в); строка правила тревоги в рендере | F3 | S |
| S12 | классы мест диспетчера и пауза доли `register` (CX2-36): `GoDispatcher` получает классы мест — `recovery` 12, `register` 4, сумма = `mailDispatchInFlight`; работа класса, чьи места заняты, — `dropped_overload` своего глагола; gauge `kaname_mail_dispatch_in_flight{class}`; доля `register` освобождается таймером часов-параметра после паузы `registerSharePause × время выводов` (пауза не держит ни работы, ни места диспетчера) (З13, З14) | `rpc-implementer` | kaname · `internal/apps/kaname/api/humansession/dispatch.go`, `cmd/kaname/loginlane.go`, `internal/apps/kaname/api/registration/register.go` | проба классов мест: при удержанной доле 16 работ `register` → 4 ждут, 12 `dropped_overload{verb="register"}`, затем `recovery` исполнена (строка ленты +1, `dropped_overload{verb="recovery"}` +0); близнец «один счётчик на 16» — `recovery` `dropped_overload` +1 — красный; проба доли времени на управляемых часах при `verifier-capacity = 1`: доля под выводами `register` ≤ 1/2 на `100 d`, вход в паузе `matched`; близнец `registerSharePause = 0` — доля ≥ 0,99, вход — отказ по ёмкости — красный; проба паузы без работы (горутин работы 0, место класса свободно); модульная проба констант (12 + 4 = 16; инъекция 12 + 5 — красный с обоими числами); пробы S1 (`dropped_overload`, страж пула 32/33) и S2 (голодание, исход) зелёные после правки | S1, S2 | M |

### Ярус 5 — край (kacho)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| E1 | ручка `KACHO_API_GATEWAY_TRUSTED_HOPS` вместо двух и обязательный параметр `NewContextExtractor` без умолчания (З8), таблица границ `anon_mail_bounds.go`, страж, ключ PoW (З9) | `go-implementer` | kacho · `gateway/internal/config/{config.go,anon_mail_bounds.go}`, `gateway/internal/middleware/context_extractor.go`, `gateway/cmd/api-gateway/{main.go,login_lane_transport.go}` | NTF2-71 варианты края (г, д, е, ж, з, и, к, р, с, х, ц) и (т) по 19 ключам края — печатает число; отказ старта без ключа PoW; проба конструктора «нулевое `TrustedHops` → ошибка сборки корня» (CX2-12); `git grep -c 'AUTHZ_TRUSTED_PROXY_COUNT\|AUTHZ_TRUSTED_XFF\|WithTrustedProxyHops' -- gateway deploy` → 0 | Е7 | M |
| E2 | звено `anonmail`: `Ladder`, `Admit` под рекомендательными блокировками ключей формы с двумя `int4` по отсортированным парам и строкой ведра последней, закрытые исходы со `StoreUnavailable` → `503`, `lock_timeout`, хранилище (`memory`/`postgres`), PoW и файл векторов, признак `anonMail` в таблице путей, путь `register/confirm`, уборка по функции З26, ведомость собственных статусов края (З8, З9, З26) | `rpc-implementer` | kacho · `gateway/internal/middleware/{anonmail/**,login_lane_paths.go}`, миграция хранилища края, `internal/repohygiene/httpstatusproducer_test.go` | NTF2-60, 61, 62, 63, 74, 79 на П6 зелёные; проба «адрес края = адрес в kaname» (CX2-12); integration-проба гонки нового ключа при `FREE = 1` → пропущен один (CX2-11); проба «хранилище недоступно → `503`, полоса не вызвана, счётчик +1» с близнецом и проба `lock_timeout` (CX2-28); integration-проба пространства ключей «`schemaLockID` удержан соседним соединением → `Admit` отвечает» с близнецом-инъекцией формы с одним ключом и гейт формы блокировки в пакете (CX2-11); проба закрытого перечня предметов хранения края; нагрузочный прогон звена с флотом 2 на `postgres` — число решений в секунду напечатано | E1, **Е9** | L |
| E3 | гейт пары «хранилище ↔ флот» для ограничителя (CX2-11) | `integration-tester` | kacho · `gateway/deploy/idempotency_fleet_test.go` | печатает оба потребителя и пары по профилям; инъекция профиля `memory` + флот 2 — красный | E2 | S |
| E4 | консоль: решатель PoW в `Worker` со сроком жизни одной отправки и бюджетом, `submit`, экран регистрации с кодом, экран восстановления (З10) | `ui-implementer` | kacho · `ui-future/shared/src/{api/login-lane.ts,lib/pow/**,pages/auth/RegistrationPage.tsx,pages/auth/RecoveryPage.tsx}` | модульные пробы решателя по общим векторам `gateway/internal/middleware/anonmail/testdata/pow_vectors.json` и `submit` (размонтирование, повторная отправка, исход `expired`, ответ `503` — решателя нет, повтора нет) на управляемых часах зелёные с числом (CX2-30); `ui-reviewer` ✅ | E2, **Е9** | M |

### Ярус 6 — развёртывание (kacho)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| D1 | зонтик: пин kaname на линию `kaname#484`; строка kaname в помощнике флага и таблице источников; `configmap` kaname без `invite-mail`; ручки Р8 kaname и края, `TRUSTED_HOPS` и ключи-секреты во всех профилях; помощник `kanameDailySum`; правило тревоги `unaddressed` > 0 в подчарте kaname (З4, З16, З19, З23) | `deploy-engineer` | kacho · `deploy/helm/umbrella/{values*.yaml,templates/_notifications.tpl}`, `charts/kaname/**` по §3а | NTF2-53 (а)–(в) и близнец; вариант «глобальный `false`, модуль `true`»; NTF2-73 с двумя близнецами; гейт строки источника (инъекция адреса края) | S1–S11, E1, Е5 | M |
| D2 | снятие почты поставщика и страж листьев (З22; DoD пп.13–14) | `deploy-engineer` | kacho · `deploy/helm/umbrella/charts/kaname/templates/{_kratos-identity.tpl,kratos-hooks-configmap.yaml,kratos-config-configmap.yaml,_helpers.tpl,deployment.yaml}`, `deploy/helm/umbrella/{values.yaml,values.dev.yaml,values.prod.yaml}`, `templates/identity-provider-mail-guard.yaml` | предикаты DoD п.13 (`\$mail` → 0; второй — пусто); NTF2-23 (а, б) и близнец в обоих положениях поставщика; NTF2-22 локальным контейнером | Е7 | M |
| D3 | переписка гейтов рендера §3а: снять 11, переписать 9, держатель NTF2-30…32 с проецируемым томом и «неизвестной формой»; NTF2-18, 20, 21, 24 (З22) | `integration-tester` | kacho · `deploy/*_test.go`, `deploy/tests/helm/*.sh` по §3а | DoD п.16 целиком (оба посева, четыре бегуна); NTF2-31 (а)–(д) и вариант проецируемого тома красные; DoD п.20: вывод гейта приложен к `kacho#2917` | D1, D2 | L |
| D4 | гейт двух поставок kaname (CX2-22), включая строку правила тревоги `unaddressed` (CX2-07) | `integration-tester` | kacho · `deploy/kaname_two_deliveries_keys_test.go` | печатает «поставок 2 · ключей N в каждой · правил тревоги класса S 1 в каждой»; инъекция ключа в одну поставку — красный с именем; снятие правила тревоги из одной поставки — красный | D1, S11 | S |
| X1 | сквозные: коллекция newman NTF2-01…03, 19, 40, 42, 43, 80…82, 85, 94 и запись ведомости производителя (DoD пп.4, 10, 11) | `qa-test-engineer` | kacho · `gateway/tests/newman/cases/<коллекция NTF-2>`, ведомость производителя | прогон на П1 через `assert-suites-green.sh`: исполнено = число кейсов, красных 0; предпосылка §5 (`V < F`) напечатана | D1–D3, E2, S-ярус, NTF-1 на стенде | L |
| X2 | сквозная браузерная NTF2-72 | `ui-implementer` | kacho · `ui-future/e2e/specs/ntf2-72-pow.spec.ts` | зелёная на П1; при нарушении `V < F` — «не выполнилось» | E4, D1 | S |
| T1 | конвейер: `notifygen -check` и гейты `internal/check` в CI kaname; гейты §3а, NTF2-30…32, D4 в CI kacho; прогон миграций хранилища края | `tooling-maintainer` | kaname · `.github/workflows/**`; kacho · `.github/workflows/**` | инъекция падающего гейта — задание красное, снятие — зелёное (DoD пп.1, 19) | F4, F5, D3 | S |

### Ярус 7 — воркспейс

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| W1 | пакет изменения: `holders.yaml` по заведённым файлам, `implementation_diff_set`, свидетельства | `tooling-maintainer` | kacho-workspace · `docs/changes/issue-2917/{holders.yaml,change.yaml,evidence/**}` | строк «ЗАВОДИТСЯ ЭТИМ ИЗМЕНЕНИЕМ» 0; `./scripts/docs-gate/run-all.sh` зелёный | X1, X2, D3 | S |
| W2 | правило топологии: ребро `notify → kaname` (справочник) с доводом ацикличности | `tooling-maintainer` | kacho-workspace · `.claude/rules/polyrepo.md` (задача `kacho-workspace#881`) | `./scripts/rules-gate/` зелёный | S6 | S |
| W3 | документы: страницы поставки и настроек kaname, сайт документации kacho (DoD п.22); строки-ссылки в шапках ID-MAIL-1 и трёх приёмок kaname (DoD п.23) | `docs-writer` | kaname · `docs/content/**`, `docs/engineering/acceptance/*.md` (шапки); kacho · сайт документации края; воркспейс · `docs/specs/sub-phase-ID-MAIL-1-mail-delivery-acceptance.md` (шапка) | мест, называющих почтовый узел kaname, 0; строки-ссылки есть, прежний текст не правлен | посадка линий | M |
| W4 | трекер: `kacho#2700`, `kaname#246`, `kaname#475` закрыть ссылками (DoD п.21) | `git-operator` | GitHub | задачи закрыты ссылками на ID | посадка линий | S |
| W5 | записки (DoD п.24) | `vault-scribe` | воркспейс · записки `resources/`, `rpc/`, `edges/` | `./scripts/vault-gate/run-all.sh` зелёный | посадка линий | S |

## 3. План перехода по составляющим

Прода нет (Д12): переход прямой, без второго пути.

| составляющая | что меняется | наблюдаемое после посадки | откат |
|---|---|---|---|
| kaname (линия `kaname#484`) | лента вместо очереди и отправителя; окна по моментам; коды «тот же живой»; регистрация «сначала письмо»; класс S; справочник; метка устройства; строгая конфигурация; флаг | письма kaname — только строками ленты; `register` без печений | пин kaname назад; миграция снятия необратима по данным |
| край | ограничитель и PoW на `recovery`/`register`; `register/confirm`; одна ручка прыжков | `429` двух форм; `X-Kacho-Proof` | откат образа и чарта края |
| зонтик | флаг и строка kaname в перечне notify; ручки Р8; снятие полосы kaname и почты поставщика | секрет почты — только у notify | откат чарта |
| консоль | решатель PoW; экран кода регистрации | экраны восстановления и регистрации решают вызов сами | откат образов консоли |
| поставщик личности | почтовый процесс выключен ключом, почтовой настройки нет | процесса почты поставщика нет и при повторном включении | откат чарта |

## 4. Порядок по времени

1. Е1–Е4, Е9 (правки приёмок; Е1 — после ответа владельца о прочтении Д2) и Е7; Е5 — посадка NTF-1;
   Е8 — условия к коду NTF-1 в её маршруте.
2. F1–F5, C1 — параллельно (путей общих нет); C2 — после Е1.
3. G1 → G2, G3 → G4.
4. S1, S2, S5, S6, S9, S11 — параллельно после своих зависимостей; затем S3, S4, S7, S8, S10, S12.
5. Линия `kaname#484` сводится и садится (одно изменение).
6. E1 → E2 → E3, E4; D2 — параллельно; D1 (после посадки линии kaname) → D3, D4.
7. Стенд `dev` с флагом `true`; X1, X2; T1.
8. Линия `kacho#2917` сводится и садится (одно изменение).
9. W1–W5.

Сведение линий, запрос на слияние и вливание — `git-operator` по решению диспетчера; в ствол —
только после одобрений всех применимых ролей `holders.yaml` (Д16).
