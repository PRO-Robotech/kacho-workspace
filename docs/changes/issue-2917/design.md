<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2917 (NTF-2, почта личности) — замысел

> **Что этот документ.** Технические решения, инварианты и отображение каждого пункта
> первичного разбора классов в механизм (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`
> §2 «Truth ownership»: `design.md` — technical decisions, invariants, exposure mapping).
> Наблюдаемое поведение здесь не описывается и не переопределяется: его единственный
> владелец — приёмка. Порядок работ — `tasks.md` рядом.
>
> **Редакция 4 · 2026-09-30.** Вердикта на неё нет; действующий вердикт выводится из записи
> ревью на отпечаток этого файла (`reviews/design/<role>/<sha256>.yaml`) и из пересверки
> разбора классов (`reviews/class-exposure/revalidation/<sha256>.yaml`).
>
> **Что изменилось против редакции 3** (`c3e37381…`, пересверка
> `reviews/class-exposure/revalidation/c3e373812378ad7b9d6894d261d2b9fec5f8f0d9c8260da55b6959ce2ab5e1cc.yaml` —
> «вернуть в приёмку»): CX2-36 получил механизм, а не только цену. Места диспетчера
> постановки разделены по классу работы (`recovery` 12, `register` 4, сумма — прежние 16):
> ожидающие долю проверяющего работы `register` не вытесняют восстановление ни при каком
> потоке (З13). Доля `register` освобождается после паузы, равной времени выводов, и место
> проверяющего занято выводами не больше половины времени при любом потоке, в том числе на
> границе края (З14). Новые И27, М33, строки §4, §8, §11. Решения диспетчера не тронуты,
> лимиты Д11 в силе: ни одна ручка Р8 не добавлена.
>
> **Что изменилось в редакции 3 против редакции 2** (`2886b89f…`, пересверка
> `reviews/class-exposure/revalidation/2886b89f1e0fd77aa4f834845e6466fa06cf31405bbf60fcb2bc8a39dd35f850.yaml` —
> «вернуть в приёмку»):
> - CX2-21 решён заново: у `invite_acts` нет внешнего ключа ни на `accounts`, ни на `users`, и
>   счёт потолков не уменьшает ни удаление приглашения, ни удаление аккаунта (З24, §6);
> - CX2-34 (новый асинхронный путь) получил решение. Сверка пароля в работе `register` заменена
>   двумя выводами argon2id на работу, независимо от числа записей. Они идут вне блокировки
>   якоря и без соединения пула, занимают не больше одного места проверяющего на все работы
>   `register` и ждут место в сроке работы. У исхода «ёмкость исчерпана» свой исход (З14);
> - CX2-35 получил решение: у якоря окна и у метки устройства есть срок хранения. Уборка
>   якоря не уносит моментов: внешние ключи стали `RESTRICT`, а уборка берёт якорь блокировкой.
>   «`FOR UPDATE` вернул 0 строк» — повтор вставки, а не проход без сериализации (З11, З18, З26, §6);
> - условия к коду CX2-05 (посев получает писатель аудита параметром) и CX2-11 (форма ключа
>   блокировки из двух `int4` — пространство, не пересекающееся со схемной блокировкой края)
>   вписаны в решения и держатели (З16, З8, З24);
> - §0 стоит на фактической редакции NTF-1 в ветке; новая приёмочная зависимость Е9 (исход `503`
>   ограничителя края и поведение консоли — вне приёмки).
>
> **Что изменилось в редакции 2 против редакции 1** (`f21384ed…`, пересверка
> `reviews/class-exposure/revalidation/f21384ed7d2236deed882f84dc1bfdc576f1f81f7e5ce5ad1108aeff69472892.yaml` —
> «вернуть в приёмку»): пять отображений, не выдержавших дерево, решены заново — З5 (строгость
> окружения сужена до выводимого пространства `__`, CX2-03), З16 (одна форма записи аудита — в
> прод-дереве; миграционные формы — двусторонний храповик, CX2-05), З8 (механизм блокировки ключа
> без строки, CX2-11), З11 (судьба `humansession.AddressKey`, CX2-20), З24 (счёт актов
> приглашения вместо строк, CX2-21); условия к коду пяти пунктов «выдерживает с условием»
> (CX2-07, 08, 12, 14, 17) вписаны в решения; новые пункты CX2-28…33 получили решения и строки
> §11; §0 стоит на действующем одобрении NTF-1. Новое решение З26 (срок хранения выводится из
> верхней границы окон). Новая внешняя зависимость Е8.

## 0. Входы и на чём стоит замысел

| вход | координата | отпечаток / ревизия | состояние |
|---|---|---|---|
| приёмка NTF-2 | `docs/specs/sub-phase-NTF-2-identity-provider-mail-removal-acceptance.md` | `9098d6ef95e558aa7bb376fc266835777fd814116da098772bf5f3698962c8a1` (редакция 11) | `APPROVED`, запись `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/9098d6ef….yaml`; событие одобрения не опубликовано (`event.status: not_performed`) |
| первичный разбор классов | `docs/changes/issue-2917/reviews/class-exposure/initial/9098d6ef….yaml` | тот же отпечаток | `к-коду`, возврата в приёмку нет; пункты CX2-01…27 |
| пересверка разбора на редакцию 1 | `docs/changes/issue-2917/reviews/class-exposure/revalidation/f21384ed….yaml` | отпечаток редакции 1 замысла | `вернуть-в-приёмку`; пункты CX2-28…33; заказы замыслу исполнены редакцией 2 (§11), приёмочные Е1–Е4 — §13 |
| пересверка разбора на редакцию 2 | `docs/changes/issue-2917/reviews/class-exposure/revalidation/2886b89f….yaml` | отпечаток редакции 2 замысла | `вернуть-в-приёмку`; CX2-21 не выдерживает; новые пункты CX2-34, CX2-35; условия к коду CX2-05, CX2-11; заказы замыслу исполнены редакцией 3 (§11), приёмочные Е3, Е4, Е9 — §13 |
| пересверка разбора на редакцию 3 | `docs/changes/issue-2917/reviews/class-exposure/revalidation/c3e37381….yaml` | отпечаток редакции 3 замысла | `вернуть-в-приёмку`; новый пункт CX2-36 — отображён этой редакцией (З13, З14, §11); условие к коду CX2-35 (уровень изоляции транзакции работы окна) и заказ по §0 (действующее одобрение NTF-1) этой редакцией не исполнены |
| приёмка NTF-1 (ядро) | `docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` | `d524e7bdd133b70da9335f027a83007800be4bdc567ab9ec740e08e7d497d31e` (редакция 10) | `APPROVED` (запись `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/d524e7bd….yaml`). В ветке после неё: редакция 11 `4d042803…` (`CHANGES_REQUESTED`, круг 1), редакция 12 `b92f0c2b7d5ebd753861d18292a46f3438fe1d768980b5bf326e8e7eed9712d3` (`CHANGES_REQUESTED`, круг 2) и редакция 13 `05828e42f3f5bce888a7dad5e7ada2d77ef538a37490075d53c12e0772f22130` (вердикта нет). Замысел стоит на действующем одобрении. К1 и К2 (§0.1) есть во всех четырёх редакциях (М31). Поставщик `corelib notify/feed`, `notify/spec`, `notifygen`, звена идентичности служб, сервера ленты, `ResolveSend` |
| дерево kaname | `PRO-Robotech/kaname` | `origin/357@734f69fb4` | замеры §1 |
| дерево kacho | `PRO-Robotech/kacho` | `origin/2564@6edea09c2ee` (ствол `origin/main@1d42a6728bf`) | замеры §1 |
| corelib | `PRO-Robotech/corelib` | `origin/main@34bc8104a83` | не открывался: содержимое `notify/*` — предмет NTF-1 |

Решения диспетчера Д1–Д16 действуют без изменений. Предмет NTF-2 задают Д1–Д7 (шлюз, звено
идентичности, подписка, права, шаблоны, corelib, флаг), Д8–Д9 в части личности, Д11 (лимиты для
анонимных почтовых глаголов), Д12 (снятие почты поставщика), Д13 (порядок), Д14 (надзор
администратора облака не распространяется на `notification_feed`). Д10, Д15 к предмету не
относятся; Д16 — в ствол идёт только одобренное.

**Прода нет** (Д12, требование владельца «можно перестраивать все подряд»): переход прямой, без
второго пути и без флага совместимости. Строки прежней очереди писем kaname не переносятся.

### 0.1 Расхождения двух одобренных приёмок — и чем они снимаются

Замысел реализует NTF-2. Сверка с NTF-1, на которую NTF-2 стоит (Р16 п.1), дала два расхождения
**наблюдаемого** поведения, которые замысел не вправе снять сам: у каждого есть сценарий, который
в одной приёмке зелёный, а в другой — красный. Оба решаются правкой приёмки, а не замыслом.

| № | предмет | NTF-1 (`d524e7bd`; то же в `4d042803`, `b92f0c2b`, `05828e42`) | NTF-2 (`9098d6ef`) | чем решено в замысле | что нужно |
|---|---|---|---|---|---|
| К1 | субъект ленты kaname | Р3: `service:kaname` не заводится; пространство `kaname` авторизуется сертификатом, `ResolveSend` для него не зовётся; NTF1-F21: кортежей с субъектом `service:kaname` — 0; NTF1-G22 | Р1: «`service:kaname` sender на `notification_namespace:kaname`» — одна строка манифеста; NTF2-47 (близнец: строк права ровно 1); NTF2-06 (надгробие выдачи → `DENIED(revoked)`); Р14 (три исхода `ResolveSend`) | по Д2: условие запасного пути Д2 — «**если TestMRW07 запрещает** `service:kaname`». Замер (М15) — тест судит только подразделы `seed.serviceAccounts` и `seed.joins` и о типах модели не утверждает; это же признаёт NTF-1 §1.5. Условие не выполнено — действует основной путь Д2: служебный принципал `service:kaname` (З21) | правка NTF-1: Р3, §1.5, NTF1-F21, NTF1-G22 и строка валидатора манифеста для kaname (Е1) |
| К2 | отказ при выключенном флаге | Р9, NTF1-N06: `feed.DeliveryNotConfiguredStatus()` — текст `email delivery is not configured in this installation`, `reason: NOTIFICATION_DELIVERY_NOT_CONFIGURED`; «глаголы kaname переводятся на это в NTF-2» | Р4, NTF2-51: текст `mail delivery is not configured in this installation`, `reason: MAIL_DELIVERY_DISABLED` | код один (`FAILED_PRECONDITION`, HTTP 400); производитель статуса один — corelib (З3). Текст и `reason` в замысле — из NTF-2, потому что его сценарий утверждает побайтовое равенство | выровнять одну из приёмок; рекомендация — NTF-1 (правится по К1 тем же кругом; других потребителей текста нет — М16) (Е2) |

Условие Д2 допускает два прочтения — машинное (что судит тест) и по смыслу (что называют
сообщение теста и комментарий манифеста); пересверка на редакцию 1 вынесла выбор владельцу. До
ответа замысел держит машинное прочтение (основной путь Д2, З21), и полосы, которые от него
зависят, гейтятся Е1 (`tasks.md` §0). Если владелец выберет прочтение по смыслу, правится NTF-2
(Р1, NTF2-47, NTF2-06, Р14), а в замысле — только З21 и строка §9 про `ResolveSend`.

Три меньших расхождения замысел снимает сам, не меняя ни одного «Тогда»: имя метрики флага
(З3), ключ окна поверх единственной нормализации ящика (З11), два предела на адресата — лимит
шаблона ленты и рубеж по ручкам (З19).

## 1. Замеры, на которых стоят решения

Команды — из корня воркспейса; `R_KN=734f69fb4`, `R_KC=6edea09c2ee`. Замеры первичного разбора
(CX2-*) не повторяются, на них — ссылка.

| № | утверждение | команда | результат |
|---|---|---|---|
| М1 | загрузчик kaname не отвергает неизвестный ключ файла | `git -C project/kaname show $R_KN:internal/apps/kaname/config/load.go \| sed -n 185,197p` | `v.Unmarshal(&cfg, decoderOpts)` без `ErrorUnused` (как в разборе, CX2-03) |
| М2 | переменные окружения kaname: вложенные ключи viper выводит из пути ключа с разделителем `__`; `AutomaticEnv` резолвит только зарегистрированный ключ (умолчанием или `BindEnv`) | `git -C project/kaname show $R_KN:internal/apps/kaname/config/load.go \| sed -n 40,80p` | `SetEnvPrefix(EnvPrefix)`, `SetEnvKeyReplacer(".", "__", "-", "_")`; ключи без умолчания регистрируются `BindEnv` (посадка личности, доставка манифестов) |
| М2а | плоских имён (без `__`) читают **четыре** механизма, и одного объявления у них нет | `git -C project/kaname grep -hoE '"KANAME_[A-Z0-9_]+"' $R_KN -- '*.go' ':!*_test.go' \| tr -d '"' \| sort -u \| grep -v __ \| wc -l`; литералы `flatEnvKnobs` (`service_link_collision.go`); `git … grep -nE 'os\.(Getenv\|LookupEnv)\(' $R_KN -- '*.go' ':!*_test.go'`; `… show $R_KN:internal/apps/kaname/config/mtls.go \| grep -n envconfig` | плоских литералов 42, из них в `flatEnvKnobs` 12, вне — 30 (`authn.go` — 10 прямых чтений, `cmd/kaname/*`, `KANAME_CONFIG_PATH` и др.); `os.Getenv/LookupEnv` — 30 вызовов в 14 файлах; структуры `envconfig` с приставкой (`mtls.go`, выводимые имена `KANAME_<ЛИСТЕНЕР>_SERVER_MTLS_*`); ключи `*-env` (`username-env: "KANAME_INVITE_MAIL_USERNAME"`) — имя переменной значением ключа |
| М2б | имён с `__` производит только вывод viper из пути ключа | тот же перечень литералов с `grep __`; `git … grep -hoE 'KANAME_[A-Z0-9_]+' $R_KN -- deploy \| sort -u`; `walkEnvconfigNames` (`service_link_collision.go`) | вложенные литералы — только ключи конфигурации; `envconfig` склеивает сегменты одним `_`; плоские имена поставок `__` не содержат |
| М3 | у края две ручки о числе прыжков, обе с умолчанием, и ни один чарт их не задаёт | `git -C project/kacho show $R_KC:gateway/internal/config/config.go \| sed -n 647,661p`; `git -C project/kacho grep -c 'AUTHZ_TRUSTED_PROXY_COUNT\|AUTHZ_TRUSTED_XFF' $R_KC -- deploy gateway/deploy ui-future/deploy` | `…_AUTHZ_TRUSTED_XFF` (`true`), `…_AUTHZ_TRUSTED_PROXY_COUNT` (`1`); объявлений в чартах 0 |
| М4 | адрес клиента вычисляет одна функция, и `0` прыжков уже значит «TCP-пир» | `git -C project/kacho show $R_KC:gateway/internal/middleware/context_extractor.go \| sed -n 193,250p` | `ClientIP` → `resolveClientIP`; `clientIPFromForwardHeaders` возвращает пусто при `!trustedXFF \|\| trustedProxyCount <= 0` |
| М5 | у края уже есть общее хранилище флота и гейт пары «хранилище ↔ флот» | `git -C project/kacho show $R_KC:gateway/internal/config/config.go \| sed -n 520,528p`; `… gateway/deploy/idempotency_fleet_test.go \| sed -n 1,30p` | `KACHO_IDEMPOTENCY_STORE` = `memory` \| `postgres`; гейт читает объявления чарта и каждого профиля |
| М6 | форм записи в `audit_outbox` в прод-дереве Go — пять | `git -C project/kaname grep -nE 'INSERT INTO (kaname\.)?audit_outbox' $R_KN -- '*.go' ':!*_test.go'` | `audit_outbox_emitter.go:60` (`insertAuditEventTx`), `access_binding_repo.go:1261`, `audit_session_revocation_repos.go:67`, `reconcile_adapter.go:1334`, `seed/bootstrap_admin.go:269` |
| М6а | миграций, пишущих `audit_outbox` SQL-ом, — три, и гейт соседа этого требует | `git -C project/kaname grep -liE 'insert\s+into\s+(kaname\.)?audit_outbox' $R_KN -- 'internal/migrations/*.sql'`; `… show $R_KN:internal/migrations/grant_removal_trace.go \| sed -n 1,80p` | `20260909202745_module_identities_leave_the_baseline.sql`, `20260914091500_limit_reader_grant_is_revoked.sql`, `20260916150000_quota_readers_group_leaves_the_baseline.sql`; виды `iam.access_binding.revoked` (2) и `iam.group.deleted` (1), субъекты — служебные учётки модулей и группа системного аккаунта, `actor` пуст; `TestMigrationRemovingGrantsLeavesATrace` требует след вставкой в `kaname.audit_outbox` у миграции, снимающей выдачи (храповик `GrantRemovalRatchet = 0`, двусторонний) |
| М7 | постановка письма восстановления — вне пути ответа, с ёмкостью-константой | `git -C project/kaname grep -n 'recoveryDispatchInFlight\|recoveryDispatchTimeout' $R_KN -- cmd`; `… humansession/dispatch.go \| sed -n 82,113p` | `const recoveryDispatchInFlight = 16`, `recoveryDispatchTimeout = 30 * time.Second`; сверх ёмкости — `onDrop`, после остановки — синхронно |
| М8 | у kaname **свой** предел по источнику на регистрацию и запрос восстановления | `git -C project/kaname grep -ln 'ChargeSource' $R_KN -- ':!*_test.go'`; `… show $R_KN:cmd/kaname/loginlane.go \| sed -n 538p` | `registration/register.go`, `humansession/recovery_request.go`; `SourcePace{Limit: login.SourceAttempts, Window: login.SourceWindow}`; таблица `source_request_windows` (миграция `20260927190000_*`) |
| М9 | окна писем kaname сегодня — строка-счётчик на (вид, адрес) | `git -C project/kaname show $R_KN:internal/migrations/20260927190000_address_verification_is_our_verb.sql \| grep -n 'invite_mail_windows'` | `invite_mail_windows (kind, recipient)` — одна строка-счётчик; моментов писем нет |
| М10 | запросы кодов берут время у базы | `git -C project/kaname grep -c 'now()' $R_KN -- internal/repo/kaname/pg/recovery_code_repo.go internal/repo/kaname/pg/verification_code_repo.go` | 3 и 5 (по всему `internal/repo` — 137 в 46 файлах, CX2-16) |
| М11 | регистрация и запрос восстановления уже берут часы параметром use-case | `git -C project/kaname show $R_KN:cmd/kaname/loginlane.go \| sed -n 540,560p` | `Now: time.Now` в `registration.Deps` и `RequestRecoveryDeps` |
| М12 | консоль ходит в полосу формы одним клиентом | `git -C project/kacho grep -ln 'auth/register\|auth/recovery' $R_KC -- 'ui-future/*/src/*' ':!*test*'` | `ui-future/shared/src/api/login-lane.ts` (единственный не-тестовый файл) |
| М13 | манифест службы доступа — `module: iam` | `git -C project/kaname show $R_KN:internal/servicemanifest/manifest.embedded.yaml \| grep -n '^module:'` | `module: iam` — имя модуля не равно имени источника `kaname` (CX2-09) |
| М14 | край знает внутренний адрес kaname под доменом `iam` | разбор, замер «Р1, Д3: имя источника kaname» | `iam`/`iamInternal` в `BackendAddrs` края; notify к kaname через край не ходит (NTF-1 Р4) |
| М15 | TestMRW07 не судит типы модели | `git -C project/kaname show $R_KN:internal/servicemanifest/seed_form_test.go \| sed -n 88,101p` | проверяет `len(m.Seed.ServiceAccounts) == 0 && len(m.Seed.Joins) == 0` — и только |
| М16 | текст отказа флага нужен только NTF-1 и NTF-2 | `grep -c 'NOTIFICATION_DELIVERY_NOT_CONFIGURED\|MAIL_DELIVERY_DISABLED' docs/specs/sub-phase-NTF-*.md` | NTF-1 — 2, NTF-2 — 9, NTF-3…6 — 0 |
| М17 | в kaname есть вторая функция ключа адреса — `humansession.AddressKey` | `git -C project/kaname grep -n 'AddressKey(' $R_KN -- ':!*_test.go'` | `rate.go:56` — `strings.ToLower(strings.TrimSpace(email))`; 12 вызовов в 10 файлах: ключ стража попыток входа, восстановления, регистрации, второго фактора, смены пароля, `step_up`; в `verification.go:265` — значение `Email` записи кода |
| М18 | `address.Normalize` corelib локальную часть не меняет | `git show eb29a7d93:docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md \| grep -n 'локальная часть без'` (коммит редакции 10, отпечаток `d524e7bd`) | Р8 NTF-1: «локальная часть без изменений, домен — `address.NormalizeDomain`»; гейт единственности IDNA обходит и дерево kaname |
| М19 | приглашение — строка `kaname.users`; повторная отправка строки не заводит, удаление — снимает | `git -C project/kaname ls-tree --name-only $R_KN internal/apps/kaname/api/user/ \| grep -iE 'invite\|delete'`; `… show $R_KN:internal/apps/kaname/api/user/resend_invite.go \| grep -n mailLimit` | `invite.go`, `resend_invite.go` (письмо без новой строки, сегодня под `invite.mail-rate-limit`), `delete.go`; `invite_status = 'PENDING'` у строки `users` |
| М20 | верхняя граница окна письма о торможении — 30 сут | `grep -n 'mail-throttled-interval' docs/specs/sub-phase-NTF-2-identity-provider-mail-removal-acceptance.md` | Р8: «1 сут ≤ x ≤ 30 сут»; прочие окна kaname и края ≤ 24 ч |
| М21 | у конструктора адреса клиента есть умолчание числа прыжков | `git -C project/kacho show $R_KC:gateway/internal/middleware/context_extractor.go \| sed -n 85,100p`; `git -C project/kacho grep -nE 'NewContextExtractor\(\|newClientAddressOperator' $R_KC -- gateway ':!*_test.go'` | `trustedProxyCount: 1` в `NewContextExtractor`; конструирует одна функция `newClientAddressOperator`, вызовов 2 (`main.go:185`, `:1580`) |
| М22 | пул базы kaname: умолчание процесса — умолчание драйвера; поставки задают явно | `git -C project/kaname show $R_KN:deploy/templates/configmap.yaml \| grep -n max-conns`; `git -C project/kaname grep -n maxConns $R_KN -- deploy/values.yaml deploy/values.dev.yaml`; `git -C project/kacho grep -n maxConns $R_KC -- deploy/helm/umbrella/charts/kaname/values.yaml deploy/helm/umbrella/values.dev.yaml` | `default 0` в шаблоне; 80 и 40 в обеих поставках |
| М23 | свёртка пароля kaname — argon2id с ценой на вызов | `git -C project/kaname show $R_KN:internal/domain/password_cost_class.go \| sed -n 55,60p` | `argon2id memory=65536 iterations=3 parallelism=4` |
| М24 | у края есть образец fail-closed отказа хранилища | `git -C project/kacho show $R_KC:gateway/internal/middleware/idempotency.go \| sed -n 455,462p` | `writeIdempotencyStoreUnavailable` — `503`, `UNAVAILABLE`, фиксированный текст; проба `TestIdempotency_StoreUnavailable_FailsClosedAndDoesNotMutate` |
| М25 | транзакционная рекомендательная блокировка — существующий приём kaname | `git -C project/kaname grep -l 'pg_advisory_xact_lock' $R_KN -- ':!*_test.go' ':!*.md' \| wc -l` | 17 файлов (выдачи, сверка, каталог модулей, `repo/kaname/pg/tx.go`, две миграции) |
| М26 | проверяющий пароля занимает место без ожидания; ожидающий захват есть, но полоса входа им не ходит; у полосы церемонии — своя доля ёмкости, половина | `git -C project/kaname show $R_KN:internal/passwordverify/verifier.go \| sed -n 134,151p`; `… capacity.go \| sed -n 53,90p`; `… internal/ceremonyport/client_secrets.go \| sed -n 68,122p` | `Verify` и `WithCapacity` — `acquire` (select с `default`): нет места — `OutcomeCapacityExhausted` сразу; `acquireWait(ctx)` — захват с ожиданием в сроке контекста (им ходит калибровка огибающей); доля церемонии — канал ёмкостью `Capacity()/2`, меньше 1 — отказ сборки |
| М27 | ёмкость проверяющего на профилях поставки — 1, 2 и 8 | `git -C project/kacho grep -nE 'verifierCapacity' $R_KC -- deploy/helm/umbrella` | `values.a8f60d.yaml:433` — 1 (предел памяти профиля поднять нечем, довод в самом профиле), `values.dev.yaml:1925` — 2, `values.prod.yaml:756` — 8 |
| М28 | хешер пароля kaname ёмкостью не ограничен; `register` сегодня хеширует на пути запроса | `git -C project/kaname show $R_KN:internal/passwordverify/hasher.go \| sed -n 59,86p`; `… internal/apps/kaname/api/registration/register.go \| sed -n 165,175p` | `Hash` — `argon2.IDKey` со случайной солью 16 байт, без захвата места; `uc.hasher.Hash(in.Password)` в use-case |
| М29 | аккаунт удаляется физически | `git -C project/kaname show $R_KN:internal/repo/kaname/pg/account_repo.go \| sed -n 298,312p` | `DELETE FROM accounts` при отсутствии проектов, сервисных учёток, групп и ролей; каскадный внешний ключ на `accounts` унёс бы строки вместе с аккаунтом |
| М30 | в базе края уже есть сеансовая рекомендательная блокировка одним `bigint`; kaname берёт свои транзакционные блокировки формой с одним ключом | `git -C project/kacho grep -n 'pg_advisory' $R_KC -- gateway ':!*_test.go'`; `git -C project/kaname grep -nE 'pg_advisory(_xact)?_lock\(' $R_KN -- ':!*_test.go' ':!*.md'` | край: `pg_advisory_lock($1)` с `schemaLockID` на время миграции схемы (`idempotencypg/store.go:434`); kaname: `pg_advisory_xact_lock(hashtext(…))` — только форма с одним ключом, формы с двумя `int4` нет. По документации PostgreSQL пространства ключей «один `bigint`» и «два `int4`» не пересекаются |
| М31 | К1 и К2 не сняты и в последней редакции NTF-1 в ветке (на редакции 12 — замер пересверки `2886b89f…`) | `sha256sum docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md`; `grep -c NOTIFICATION_DELIVERY_NOT_CONFIGURED …`; `grep -n 'service:kaname' …` | в ветке редакция 13 `05828e42…`: `NOTIFICATION_DELIVERY_NOT_CONFIGURED` — 2 попадания; «`service:kaname` не заводится» и «кортежей с субъектом `service:kaname` … 0» на месте |
| М32 | посев администратора облака пишет аудит своим литералом внутри своей транзакции; вызывается процессом | `git -C project/kaname show $R_KN:internal/apps/kaname/seed/bootstrap_admin.go \| grep -n 'func RunBootstrapAdmin\|INSERT INTO'`; `git -C project/kaname grep -n 'RunBootstrapAdmin' $R_KN -- cmd ':!*_test.go'` | `RunBootstrapAdmin(ctx, pool, logger, in)` — `INSERT INTO audit_outbox` в строке 269 рядом со вставками `cluster_admin_grants` и `fga_outbox`; вызов — `cmd/kaname/serve.go` |
| М33 | у диспетчера постановки один счётчик мест на все работы; класса у работы нет | `git -C project/kaname show $R_KN:internal/apps/kaname/api/humansession/dispatch.go \| grep -nE 'inFlight\|cap '`; `… show $R_KN:cmd/kaname/loginlane.go \| sed -n 549,551p` | поля `inFlight int`, `cap int`; отказ при `d.inFlight >= d.cap` (строка 94); корень строит один `GoDispatcher` с `WithCap(recoveryDispatchInFlight, …)` |

## 2. Решения

Нумерация `З<N>`; у каждого — что решено, инвариант, держатель. Ссылки на приёмку — номером
решения `Р<N>` и ID сценария; на NTF-1 — `NTF-1 Р<N>`.

### З1. Постановка письма — один пакет kaname, одна функция решения

- Пакет `internal/apps/kaname/mail` — **единственный** не-тестовый вызыватель сгенерированных
  функций `Send<Шаблон>` (они лежат в `internal/apps/kaname/mail/feedgen/`, вывод
  `notifygen` над `notifications/`). Порт use-case — `mail.Enqueuer`:
  `Enqueue(ctx, tx, Letter) (Outcome, error)`, где `Letter` — закрытый тип (шаблон · атрибуты ·
  адресат) по одному конструктору на шаблон.
- Решение «ставить строку или нет» принимает только `Enqueue` (CX2-02 (б)): флаг (З2), окно
  адресата (З9) и лимит шаблона ленты (З19) судятся внутри; места вызова строку не решают.
- Строка ставится в **транзакции события**: `tx` — транзакция глагола либо строки аудита (З16).
  `feed.Put` corelib пишет строку ленты и строку журнала подписки kaname в ту же `tx` (З17).
- Исходы `Enqueue` — закрытый тип: `Queued`, `ResentSame`, `Floor`, `TrustedDevice`, `Capped`,
  `Cooldown`, `Disabled`, `NoRecipient`; прочее — ошибка хранилища. Корзины «прочее» нет.

Держатели: гейт NTF2-45 (множество шаблонов = множество вызовов `Send*`); гейт дерева
`mail_single_enqueuer` — вызовы `feedgen.Send*` вне пакета `mail` — находка с координатой (разбор
импортов, печать числа пакетов, инъекция вызова из `api/user`).

### З2. Флаг почты: трёхзначный на входе, одно значение в процессе

- Ключ kaname `notifications.enabled`; поле конфигурации — `*bool`. Загрузчик судит **наличие**
  (`v.IsSet`), а не значение: отсутствие — отказ старта `notifications.enabled must be declared`
  (NTF2-50); `false` — законное значение (CX2-01 (а)). В `defaults.go` ключа нет.
- Значение читается один раз в композиционном корне (`cmd/kaname`) и передаётся как
  `mail.Enabled` в `mail.Enqueuer`, в сборку сервера ленты и в метрику (CX2-02 (а)).
- **Выключен:**
  - `Enqueue` возвращает `Disabled` без записи; строка журнала не пишется (NTF-1 Р9);
  - сервер ленты (`Claim`/`Ack`) не регистрируется на внутреннем слушателе — вызов даёт
    `UNIMPLEMENTED` (NTF2-52); ключ `notification` в `Mapping.Kinds` журнала kaname не объявляется
    (у kaname есть другие виды — журнал собирается без него, NTF-1 Р9);
  - четыре глагола — `recovery`, `register`, `users:invite`, `verify-email` — зовут
    `mail.Available()` **до** любого чтения по адресу (CX2-02 (в)): у `register` — после правил
    пароля (Р9, NTF2-51 (е)), у прочих — после проверки формы и `csrf`. Отказ — статус З3;
  - писатель аудита (З16) ставит события без строк ленты; глаголы класса S исполняются (Р4).
- Метрика `kaname_notifications_enabled` (gauge, `1`/`0`) выставляется корнем из того же значения.

Держатели: NTF2-50, NTF2-51 (пары и порядок (е)), NTF2-52.

### З3. Отказ «доставка почты не настроена» — один производитель

- Производитель статуса — corelib `feed.DeliveryNotConfiguredStatus()` (NTF-1 Р9); kaname своего
  текста не заводит. Форма, которую утверждает NTF2-51: `FAILED_PRECONDITION`, HTTP `400`,
  `code` `9`, текст `mail delivery is not configured in this installation`,
  `ErrorInfo{reason: MAIL_DELIVERY_DISABLED}` — расхождение с NTF-1 — К2, зависимость Е2.
- Для полосы формы (HTTP без gRPC) статус переводится в тело `{code, message, details}` той же
  функцией полосы, что прочие отказы полосы; ответ не зависит от адреса по построению — отказ
  стоит до чтения адреса.
- `users:invite` — синхронный отказ до заведения `Operation` (NTF2-51 (г, з)).
- Метрика источника: corelib регистрирует gauge с именем, которое передаёт корень службы:
  модули kacho — `kacho_notifications_enabled{module}` (NTF-1 Р9, NTF-3), kaname —
  `kaname_notifications_enabled` (NTF2-52). Второй метрики о том же у kaname нет.

### З4. Флаг в зонтике — один помощник; перечень источников выводится из него

- Помощник `kacho.notifications.enabledFor` в `deploy/helm/umbrella/templates/_notifications.tpl`
  (дом помощника — NTF-1; NTF-2 добавляет в него строку `kaname`):
  - глобальное значение `global.kacho.notifications.enabled` проверяется `hasKey`; отсутствие —
    `fail` с именем ключа (NTF2-53 (а));
  - переопределение модуля — `hasKey .Values.<модуль>.notifications "enabled"`; при наличии берётся
    оно, **в том числе `false` при глобальном `true` и `true` при глобальном `false`**; `default`,
    `or`, `coalesce` и `if` по значению флага запрещены (CX2-01 (б));
  - возвращает строку `"true"`/`"false"`.
- Два читателя помощника: `configmap.yaml` подчарта kaname (`notifications.enabled`) и перечень
  источников `notify` (NTF-1 Р6) — оба `include` одного помощника (CX2-01 (в)).
- Строка kaname в закрытой таблице подключаемых источников NTF-1 (Р6):
  `{name: kaname, module: iam, flag: kaname.notifications.enabled, namespace: kaname,
  address: <внутренний сервис kaname из помощника подчарта>, san: kaname.spiffe,
  classes: [security], recipientForms: [address, subject]}`. **Имя источника, имя модуля и адрес —
  три поля одной строки**; ни одно не выводится из написания другого (CX2-09 (а)); край и его
  словарь `iam` в этой строке не участвуют — notify зовёт kaname напрямую (М14).

Держатели: NTF2-53 (а)–(в) и близнец; новый вариант рендера «глобальный `false`,
`kaname.notifications.enabled: true`» — у kaname `true`, запись kaname в перечне есть (CX2-01,
заказ разбора); гейт строки источника (З4 п.4): инъекция `address` = адрес края для `iam` —
красный с именем поля (CX2-09).

### З5. Строгая конфигурация kaname: файл целиком, окружение — в выводимом пространстве

- **Файл** (CX2-03 (а)): декодер с `ErrorUnused: true` (`v.UnmarshalExact`); неизвестный ключ —
  отказ старта с полным путём ключа (NTF2-48 (а)–(г)).
- **Окружение** (CX2-03 (б)) — строгость **сужена до пространства `__`**, и это решение, а не
  недоделка. Довод (М2а, М2б): имя с `__` производит ровно один механизм — вывод viper из пути
  ключа, поэтому множество законных имён этого пространства вычислимо из одного объявления, а
  кластер и прочие механизмы в нём имён не производят. Плоские имена читают четыре механизма
  (`flatEnvKnobs`, 30 прямых чтений окружения, `envconfig` с приставкой, ключи `*-env`), и
  одного объявления у них нет; строгость по неполному перечню отказала бы в старте каждому
  профилю, а сведение четырёх механизмов в одно — предмет, которого NTF-2 не несёт (приёмка
  утверждает строгость только для ключей файла, NTF2-48).
  - Множество законных имён — **прямой** вывод: для каждого ключа, который знает декодер
    (`mapstructure`-пути структуры `Config` — то же множество, которым судит `UnmarshalExact`),
    имя = `EnvNameOfKey(key)` (существующая экспортируемая функция `service_link_collision.go` —
    то же правило, что `SetEnvKeyReplacer`). Обратного разбора имени нет: `-` и `_` в ключе дают
    один символ, и обратный вывод неоднозначен.
  - При старте каждая переменная с приставкой `KANAME_` и хотя бы одним `__`, которой нет в
    множестве, — отказ старта «unknown configuration variable `<имя>`». Плоские имена этой
    проверкой не судятся.
  - Снятые NTF-2 плоские имена (`KANAME_INVITE_MAIL_USERNAME`, `KANAME_INVITE_MAIL_PASSWORD` —
    значения ключей `*-env`) уходят из обеих поставок тем же изменением; что их нет ни в одном
    объекте рендера, утверждает держатель единственного держателя секрета почты (NTF2-30…32, З22).
- **Регистрация ключей без умолчания** (CX2-03, замечание пересверки): 32 ключа Р8 kaname,
  `notifications.enabled` и два ключа `authn.secrets.*` (З18) регистрируются `v.BindEnv(key)` в
  цикле **по той же таблице границ** `mail_bounds.go` (З23), которую читает страж старта; флаг и
  ключи секретов — строки той же таблицы с видом «обязателен, без границ». Второго перечня
  регистрации нет: ключ, внесённый в таблицу, получает и привязку, и суждение стража.
- **Перемер профилей** (CX2-03 (в)): до включения строгости исполняется рендер обеих поставок
  kaname (подчарт зонтика по всем цепочкам `deploy/stacks.txt` и `deploy/` kaname) и старт
  проверки конфигурации на каждом рендере; ключ файла или имя с `__` без читателя снимаются тем
  же изменением. Вывод прикладывается к задаче `kaname#484`.

Держатели: NTF2-48; проба «переменная `KANAME_INVITE_MAIL__RELAY` → отказ старта с её именем»
(заказ разбора); близнецы — стенд с переменными служб кластера и с плоскими именами обеих поставок
стартует; проба привязки «ключ Р8, заданный только переменной окружения, доезжает до поля» — по
одному ключу каждого вида таблицы.

### З6. Снятие собственной почты kaname — порядок снятия

Одним изменением, в порядке (CX2-04 (а)):

1. места постановки в очередь (`api/user/invite.go`, `resend_invite.go`, `humansession/recovery_request.go`,
   `verification.go`) переводятся на `mail.Enqueue`;
2. снимаются проводка дренажа и отправитель (`internal/clients/invite_mail*.go`,
   `cmd/kaname/invite_mail_wiring*.go`), ручки `invite-mail.*`, `invite.mail-rate-limit.*`,
   `authn.login.verification-resend-{interval,limit,window}`,
   `authn.login.verification-code-attempts`;
3. новая миграция снимает `invite_mail_outbox`, `invite_mail_windows`, `source_request_windows` и
   дописывает их в `internal/migrations/retired.json` (применённые не правятся, ban #5);
4. снимаются метрики отправителя.

Гейт MAIL-47 (`internal/check/mail_send_paths.go`) **переписывается тем же коммитом** в гейт
NTF2-44 (CX2-04 (б)): окна без запрета SMTP нет. Утверждение «таблицы очереди нет» идёт в паре с
живым контролем «таблица ленты есть» (CX2-04 (в), NTF2-44).

### З7. Ось источника — только у края

- Предел kaname по источнику на `register` и `recovery` (М8: `ChargeSource`, `SourcePace` из
  `authn.login.source-{attempts,window}`, таблица `source_request_windows`) **снимается**: Р5 отдаёт
  ось источника анонимных почтовых глаголов краю, а два предела одной оси с разными ключами
  расходятся молча. Ручки `authn.login.source-{attempts,window}` остаются: их второй читатель —
  окно неудач входа паролем (`humansession/rate.go`), предмет которого NTF-2 не меняет.
- Снятие — замещение решения kaname#456 об окне обращений по источнику; строка-ссылка на него
  дописывается в шапку приёмки kaname `access-beyond-login-needs-a-verified-address.md` по DoD
  п.23 (Е4).

Держатели: NTF2-60, NTF2-63 (ряды без отказа kaname по источнику); проба дерева «`ChargeSource`
вызывающих 0».

### З8. Звено-ограничитель края

- Пакет `gateway/internal/middleware/anonmail`; звено ставится в HTTP-цепочку **перед**
  ретрансляцией полосы формы. Перечень путей не пишется вторым местом: у строк таблицы путей
  полосы (`login_lane_paths.go`) появляется признак `anonMail: true` — у `recovery` и `register`
  и только у них (NTF2-63). Там же добавляется строка `register/confirm` (`RelayTargetForm`,
  без признака).
- **Ключи:** адрес — результат `ContextExtractor.ClientIP(r)` (CX2-12 (а)): тот же адрес
  ретрансляция отдаёт kaname в `X-Forwarded-For`. Источник — адрес целиком (IPv4 `/32`, IPv6
  `/64`), подсети — `/24` (IPv4), `/56` и `/48` (IPv6); общий поток — один ключ.
- **Одна ручка прыжков** (CX2-12 (б)): `KACHO_API_GATEWAY_TRUSTED_HOPS` без умолчания **замещает**
  `KACHO_API_GATEWAY_AUTHZ_TRUSTED_PROXY_COUNT` и `KACHO_API_GATEWAY_AUTHZ_TRUSTED_XFF` тем же
  изменением. `0` — «пересланным заголовкам не верить, ключ — TCP-пир» (семантика `0` уже такова,
  М4), `N ≥ 1` — `N` доверенных прыжков. Условие `client_ip` модели прав читает тот же
  `ContextExtractor`, поэтому край и модель прав видят один адрес. Признака «учитывать пересланные»
  больше нет, и пара «ограничитель включён, пересланные выключены» (CX2-12 (в)) невыразима.
- **Число прыжков — обязательный параметр конструктора** (CX2-12, условие пересверки):
  `NewContextExtractor(now, hops TrustedHops, …)`; умолчание `trustedProxyCount: 1` (М21) и опция
  `WithTrustedProxyHops` снимаются тем же изменением. Значение `TrustedHops` строится только
  разбором ручки (`ParseTrustedHops`: пусто или отрицательно — отказ старта с именем ручки);
  нулевое значение типа (не построенное разбором) конструктор отвергает ошибкой сборки корня. Оба
  вызова `newClientAddressOperator` (М21) получают значение из конфигурации; «вызывающий забыл
  опцию» невыразимо.
- **Решение и счёт — одна операция** (CX2-11 (а)): `Admit(keys, now)` считает окна по хранимым
  моментам пропущенных запросов, вычисляет ступень (чистая функция `Ladder`, Р5) и при исходе
  «пропустить» записывает момент **в той же** операции. Ответ-вызов и `429` момента не пишут (Р5,
  «счёт ключа»).
- **Чем сериализуется ключ, у которого ещё нет строк** (CX2-11, отказ пересверки): у таблицы
  моментов строки-якоря нет, поэтому блокируется не строка, а **ключ**:
  - `postgres` — в одной транзакции `pg_advisory_xact_lock(class, obj)` **формы с двумя `int4`**
    на каждый ключ запроса: `class` — константа звена `anonMailLockClass`, `obj =
    hashtext('anonmail:' || key)`. Пары берутся **отсортированными по значению** и без повторов —
    порядок один для любых двух запросов, в том числе при совпадении свёрток ключей разных классов,
    поэтому взаимной блокировки нет. Совпадение свёрток двух ключей только сериализует их лишний
    раз и счёта не меняет (счёт — по `key` строк). Приём в kaname уже используется (М25);
  - **пространство ключей блокировки** (CX2-11, условие пересверки на редакцию 2): база края уже
    несёт сеансовую блокировку `pg_advisory_lock(schemaLockID)` одним `bigint` на всё время
    миграции схемы (М30). Форма «один `bigint`» с ней сталкивалась бы: ключ, чья свёртка совпала
    со `schemaLockID`, ждал бы до `lock_timeout` и получал бы `503`. Форма с двумя `int4` живёт
    в другом пространстве ключей PostgreSQL и с блокировкой одним ключом не пересекается ни при
    каком значении. Поэтому совпадение исключено формой, а не вероятностью. Форма с одним ключом
    в звене `anonmail` запрещена гейтом дерева: вызовы `pg_advisory*` в пакете — только с двумя
    аргументами, печать числа вызовов, инъекция формы с одним ключом — красный;
  - `memory` — полосатые мьютексы по той же свёртке, взятые в том же отсортированном порядке;
  - строка ведра общего потока (`anon_mail_bucket`, единственная, заводится миграцией хранилища)
    берётся `SELECT … FOR UPDATE` **последней**, после ключей, и держится только до конца
    транзакции решения (CX2-28 (в)).
- **Отказ хранилища — свой исход** (CX2-28 (а, б)): `Admit` возвращает закрытый тип
  `Pass · Challenge · Reject(retryAfter) · StoreUnavailable`; проверка одноразовости (З9) —
  `Fresh · Replayed · StoreUnavailable`. `StoreUnavailable` — ошибка соединения, ошибка запроса и
  превышение времени ожидания блокировки (`SET LOCAL lock_timeout` = 250 мс — константа звена с
  доводом: решение ключа — единицы операторов к базе, и ожидание дольше означает очередь, а не
  конкуренцию). Ответ — `503`, `code` `14`, тело той же функцией формы края, что у однократности
  (`writeIdempotencyStatus`, М24), фиксированный текст `request limiter is unavailable`,
  одинаковый для любого адреса (адрес ещё не прочитан); до kaname запрос не
  доходит; счётчик `kacho_api_gateway_anon_mail_store_unavailable_total`. Ветки «не смог
  спросить → пропустить» в типе исходов нет.
- **Хранилище** (CX2-11 (б)) — то же объявление, что у однократности (М5):
  `KACHO_IDEMPOTENCY_STORE` = `memory` \| `postgres` и его DSN. `memory` законно только при флоте из
  одной реплики; пару «вид хранилища ↔ флот» судит расширенный гейт
  `gateway/deploy/idempotency_fleet_test.go` для обоих потребителей, отказ рендера на неисполнимой
  паре — тот же. Второго объявления «где живёт состояние края» не заводится.
- **Общий поток:** ведро `RATE`/`BURST` — строка хранилища, взятая последней (см. выше); сверх —
  вызов (не `429`), в том числе источнику ниже своего порога (NTF2-74). Цена названа: все
  анонимные почтовые запросы флота проходят строку ведра по одному; время её удержания — одна
  транзакция решения. Число до кода не называется: оно видно только прогоном под нагрузкой с
  флотом ≥ 2 (пересверка, «не измеримо до кода»); нагрузочный прогон ограничителя — предикат
  полосы E2 (`tasks.md`).
- Ответы — `429` двух форм Р5; `Retry-After` — секунды до момента, когда старейший засчитанный
  момент выйдет из окна `HARD` (источник или подсеть — что позже). Оба статуса и `503`
  `StoreUnavailable` вносятся в ведомость собственных статусов края
  (`internal/repohygiene/httpstatusproducer_test.go`), DoD п.7.

Держатели: NTF2-60…63, 74, 79, 71 (е, ж, з, и, к, р, с, х, ц); проба «адрес, которым считает
край, равен адресу, пришедшему в kaname» (CX2-12, заказ) — integration-проба края с фиктивной
полосой формы, печатающей полученный `X-Forwarded-For`; гейт пары хранилища (CX2-11, заказ);
integration-проба гонки «`N` одновременных запросов с нового ключа при `FREE = 1` → пропущен ровно
один» на `postgres` (CX2-11); модульная проба «хранилище недоступно → `503`, фиктивная полоса формы
вызовов не получила, счётчик +1» и близнец «хранилище исправно → пропуск» (CX2-28); проба
«ожидание блокировки дольше `lock_timeout` → `StoreUnavailable`» (CX2-28 (б)); проба конструктора
«нулевое `TrustedHops` → отказ сборки корня» (CX2-12); integration-проба пространства ключей
(CX2-11, условие): соседнее соединение держит `pg_advisory_lock(schemaLockID)`, а функция ключа блокировки
звена подменена в пробе так, что `obj` равен младшим 32 битам `schemaLockID`, а `class` —
старшим. `Admit` отвечает в пределах `lock_timeout`. Близнец-инъекция: та же подмена в форме
«один `bigint`» со значением `schemaLockID` даёт `StoreUnavailable`. Гейт формы
блокировки в пакете `anonmail` (печать числа вызовов, инъекция формы с одним ключом — красный).
Исход `503` звена — наблюдаемое поведение публичного пути, и его сценарий заводит приёмка (Е9).

### З9. Proof-of-work края

- **Вызов** — `base64url(v1 ‖ id[16 случайных байт] ‖ expiresAt ‖ bits ‖ HMAC-SHA256(k, v1 ‖ id ‖ expiresAt ‖ bits))`.
  Срок вызова — константа 5 мин в коде звена (довод: верхняя граница решения на 24 битах в
  браузере с запасом; ручкой не является и в 51 ключ Р8 не входит).
- **Проверка** — локальная, без обращения к kaname (CX2-11 (в)): разбор, подпись (постоянное
  время), срок по часам звена, число ведущих нулевых битов `SHA-256(challenge ":" nonce)` ≥ `bits`,
  затем **одноразовость**: вставка `id` в множество использованных того же хранилища З8
  (`postgres` — `INSERT … ON CONFLICT DO NOTHING`, 0 строк — повтор; `memory` — множество со
  сроком). Любой отказ проверки — новый вызов (NTF2-62), до kaname запрос не доходит; исход
  `StoreUnavailable` одноразовости — не отказ проверки, а `503` З8 (CX2-28): «не смог проверить»
  за «свежий» не считается.
- **Ключ `k`** — удостоверение профиля: файл секрета, путь — `KACHO_API_GATEWAY_ANON_MAIL_POW_KEY_FILE`;
  без файла или с ключом короче 32 байт — отказ старта с именем ручки; вывода из другого секрета
  нет; один секрет на флот (CX2-13 (а, б)). Смена ключа делает невалидными выданные вызовы — не
  дольше срока вызова (CX2-13 (в)); объявлено на странице поставки края.

### З10. Консоль: вызов решается прозрачно

- Единственный клиент полосы — `ui-future/shared/src/api/login-lane.ts` (М12). В функции `submit`
  ответ `429` с `reason: PROOF_OF_WORK_REQUIRED` решается **один раз**: поиск `nonce` — в
  выделенном `Worker` (`ui-future/shared/src/lib/pow/solver.worker.ts`, собственная SHA-256, без
  сетевых ресурсов), повтор того же тела с заголовком `X-Kacho-Proof`. Второй вызов подряд либо
  `RATE_LIMITED` — отказ, показанный текстом отказа полосы.
  Ответ `503` края (`StoreUnavailable`, З8) решатель не запускает и запрос не повторяет: это
  отказ, показанный тем же текстом отказа полосы; что именно видит пользователь на `503` и на
  исход `expired`, утверждает приёмка (Е9).
- Экран регистрации — два шага: форма `register` → единый текст и поле кода → `register/confirm`
  (форма `register-confirm`). Экран восстановления после отправки показывает единый текст
  независимо от ответа `200`/решённого вызова (NTF2-72).

- **Срок жизни решателя** (CX2-30 (а, б)): `Worker` принадлежит одной отправке формы. Он
  завершается (`terminate()`) при размонтировании экрана, при новой отправке той же формы и по
  исчерпании бюджета поиска. Бюджет — 4 мин от получения вызова по монотонным часам страницы
  (`performance.now()`): меньше срока вызова (5 мин, З9) на запас, покрывающий передачу и
  проверку; часы клиента с часами края не сравниваются. Исчерпанный бюджет — свой исход
  `expired` решателя, отличимый от «второго вызова подряд»: запрос не отправляется, форма
  возвращается в редактируемое положение с тем же текстом отказа полосы, что при любом
  неуспехе; при следующей отправке вызов получается заново. Результат `Worker`, пришедший после
  `terminate()` или от прежней отправки, отбрасывается по номеру отправки.
- **Одна функция — две реализации, одни векторы** (CX2-30 (в)): SHA-256 решателя консоли и
  проверка края судятся общим файлом векторов `gateway/internal/middleware/anonmail/testdata/pow_vectors.json`
  (вызов, `nonce`, число ведущих нулевых битов, ожидаемый исход; и срок вызова с бюджетом
  решателя). Файл читают модульная проба края (Go) и модульная проба решателя (TS) — одни входы,
  одни ответы; расхождение любой стороны — красный. Инвариант «бюджет решателя < срока вызова»
  утверждается над тем же файлом; константы кода обеих сторон сверяются с ним пробами своих
  сторон.

Держатели: NTF2-72; модульная проба решателя по общим векторам и пробы `submit` (вызов → один
повтор с заголовком; второй вызов → отказ; размонтирование и повторная отправка → прежний
`Worker` завершён, его результат отброшен; бюджет исчерпан → исход `expired`, запроса нет) —
управляемые часы страницы (CX2-30).

### З11. Рубеж kaname на адресата — хранимые моменты и одна чистая функция

- **Нормализация ящика одна, ключей от неё два** (CX2-20; отказ пересверки — в kaname есть
  `humansession.AddressKey`, М17):
  - разбор адреса — только `address.Normalize` corelib (NTF-1 Р8, М18): локальная часть без
    изменений, домен A-label. Своего разбора и своего IDNA у kaname нет (гейт NTF-1 B27 обходит и
    дерево kaname);
  - ключи — пакет `internal/apps/kaname/mailkey`, **две именованные производные** от значения типа
    `address.Normalized` (входа-строки у них нет, поэтому вызвать их мимо `Normalize`
    невыразимо):
    - `mailkey.Account(n)` — локальная часть в нижнем регистре, домен как есть. Совпадает с
      правилом уникальности учётки `lower(email)`: ключ **учётки**;
    - `mailkey.Abuse(n)` — то же и без `+метки` локальной части: ключ **злоупотребления**;
  - `humansession.AddressKey` **снимается** тем же изменением. Её 11 вызовов ключа стража попыток
    (вход, завершение восстановления, регистрация, второй фактор, смена пароля, `step_up`) берут
    `mailkey.Account` — семантика ключа стража сохраняется (регистр не удваивает окно) и
    дополняется A-label домена; 12-й вызов (`verification.go:265`) ключом не является — это
    значение `Email` записи кода, и оно берёт хранимый адрес учётки как `address.Normalized`, без
    понижения регистра;
  - кому какой ключ: окна `recovery`, `verification` и страж попыток (З15) — `Account` (защищают
    учётку); окно `registration` и потолки приглашений на адресата (З24) — `Abuse` (защищают
    ящик от спама написаниями одного адреса);
  - в хранилище ключ окна — только свёртка `HMAC-SHA256(k_window, purpose ‖ key)`.
- **Неразбираемый адрес** (CX2-20 (в)): у глаголов, ставящих письмо (`recovery`, `register`), —
  один отказ формата до любого чтения, одинаковый для любого адреса; у путей предъявления с
  адресом (`login`, `recovery/complete`, `register/confirm`) — тот же ответ, что на неверные
  учётные данные (`401 authentication failed`): учётки с таким адресом не бывает, потому что каждый
  писатель `users.email` после NTF-2 пишет результат `Normalize` (`register/confirm`, приглашение)
  — это утверждает гейт `people_address_writers` (З25) новой строкой условия. Хранимый адрес,
  который `Normalize` не разбирает, — нарушенный инвариант данных: `INTERNAL` фиксированным
  текстом и счётчик, а не отказ пользователю «формат».
- **Хранение** (CX2-15 (б, в)): таблица моментов писем `mail_window_letters` с видом
  `progression` \| `floor` \| `trusted_device` \| `throttled`; окно считается по моментам, а не по
  корзинам. Строка-якорь `mail_windows (purpose, key_digest)` — для блокировки.
- **Якорь заводится до блокировки** (CX2-14, условие пересверки): в транзакции работы сначала
  `INSERT INTO mail_windows … ON CONFLICT DO NOTHING`, затем `SELECT … FOR UPDATE` той же строки.
  `SELECT … FOR UPDATE` по отсутствующему якорю ничего не блокирует, поэтому порядок «вставка →
  блокировка» — часть решения, и его судит integration-проба гонки первых запросов на новом ключе.
- **`FOR UPDATE` обязан вернуть ровно одну строку** (CX2-35 (б)): якорь может убрать уборка (ниже)
  между вставкой работы (`ON CONFLICT DO NOTHING` — строка была) и её `SELECT … FOR UPDATE`, и
  тогда блокировка возвращает 0 строк. Работа читает это как «якоря нет», а не как «заблокировано»:
  она повторяет пару «вставка → `FOR UPDATE`» (константа `anchorAttempts = 3` с доводом:
  уборка снимает якорь только без моментов и записей, поэтому второй повтор подряд требует
  ещё одной гонки с уборкой того же ключа). После третьей пустой блокировки — ошибка хранилища
  работы, строк нет. Функция якоря одна (`mail_window_repo.LockAnchor`), и её зовут все работы
  окна: `recovery`, `register`, `verify-email`. Отдельной пары «вставка → блокировка» в местах
  вызова нет.
- **Срок хранения якоря** (CX2-35 (а)): якорь заводит каждый новый ключ, в том числе анонимный
  `register` на произвольный адрес, поэтому без уборки число строк росло бы с числом адресов,
  когда-либо названных анонимно. Якорь снимается, когда у ключа нет ни моментов, ни ожидающих
  записей. Моменты и записи уходят своими сроками (З26, З14), поэтому якорь живёт не дольше
  самого долгого из них плюс шаг уборки. Уборка (предмет `mail_windows` реестра `retention`)
  берёт кандидатов пачкой `SELECT … FOR UPDATE SKIP LOCKED` и в **той же** транзакции, под
  блокировкой строки якоря, снимает его одним `DELETE … WHERE NOT EXISTS (моменты) AND NOT
  EXISTS (записи)`. Работа пишет моменты и записи только под блокировкой якоря, поэтому при
  взятой уборкой блокировке ни момент, ни запись не появятся. Занятый работой якорь уборка
  пропускает (`SKIP LOCKED`). Страховка базы — внешние ключи `mail_window_letters` и
  `pending_registrations` на якорь с `ON DELETE RESTRICT` (§6), а не `CASCADE`: снятие якоря с
  живым моментом отвергает база, и уборка окна не уменьшает ни при каком порядке операторов.
- **Одна чистая функция** (CX2-15 (а)): `mailwindow.Decide(h History, now time.Time, k Knobs,
  label *DeviceLabel) Decision`, где `History` — моменты по видам, `Decision` —
  `{Admit: progression|floor|trusted_device|none, Outcome, RetryAfter}`, `Outcome` из закрытого
  набора `queued · resent_same · cooldown · capped · floor · trusted_device` (`resent_same`
  уточняется слоем кода, З12). Правило пола — Р6 дословно (`Tc`, `Tw`, возобновление); паузы — только
  от моментов `progression`.
- **Лимит возвращается без второго счётчика** (CX2-32): строка `mail_window_letters` несёт
  `feed_id text NOT NULL` — идентификатор строки ленты, который вернул `feed.Put` **в той же
  транзакции**; момент пишется только после успешного `feed.Put`, поэтому «момент без строки
  ленты» невыразим (`NULL` колонка не принимает). Внешнего ключа на таблицу ленты нет: удаление
  строки ленты по сроку хранения момент не трогает. Окно считает момент, если **нет** строки
  ленты с этим `id`, у которой лимит возвращён; предикат «лимит возвращён» — экспорт corelib
  `notify/feed` (фрагмент запроса над строкой ленты), а не литерал исхода и причины в kaname
  (Е8). Отсутствующая строка ленты (удалена по сроку) — момент **считается**: удаление предела
  не ослабляет. Уборщик NTF-1, закрывая строку исходом с возвратом лимита, уменьшает окно по
  построению (NTF2-07).
- **Исход, отданный наружу:** `recovery`, `registration` — ответ `200 {}` всегда; `verify-email` —
  `429 TOO_MANY_ATTEMPTS` с `Retry-After` = `Decision.RetryAfter` (Р6).
- Метрика `kaname_mail_intents_total{verb,outcome}` — набор меток закрыт (7 исходов, с
  `dropped_overload` из З13); регистрация меток при старте, значение вне набора — паника сборки.

Держатели: NTF2-40, 41, 64, 65, 68, 70, 75, 76, 78; модульная табличная проба `Decide` на ряды
базового профиля Р6 и копии с `floor-interval` = 24 ч (CX2-15, заказ); модульная проба
`mailkey`: регистр, `+метка` (`Account` сохраняет, `Abuse` снимает), IDN-домен (CX2-20); проба
дерева «вызовов `AddressKey` 0, `idna` в kaname 0» (CX2-20); integration-проба «`N` параллельных
первых запросов на новом ключе → один момент» (CX2-14); проба «момент без `feed.Put` не пишется;
вставка момента с пустым `feed_id` — ошибка базы» и проба «строка ленты удалена по сроку → момент
считается» (CX2-32); integration-проба «уборка якоря между вставкой и `FOR UPDATE` → работа
повторила вставку, строка ленты одна, момент один» — точка вмешательства между двумя операторами
`LockAnchor` задаётся пробой (CX2-35 (в)); близнец — без уборки работа проходит с первой попытки;
проба уборки «якорь без моментов и записей снят; с моментом или записью — нет; занятый работой —
пропущен»; проба базы «`DELETE` якоря с живым моментом отвергнут внешним ключом» (CX2-35 (а)).

### З12. Коды: один живой код на (назначение, субъект)

- Таблицы `recovery_codes`, `email_verification_codes` получают `superseded_at`; частичный
  `UNIQUE (user_id) WHERE consumed_at IS NULL AND superseded_at IS NULL` — один живой код
  (CX2-14 (б)). Код хранится свёрткой, сравнение — за постоянное время (CX2-19 (б)).
- В транзакции окна: живой код есть и `now < expires_at` → письмо несёт **тот же** код
  (`resent_same`); иначе прежний помечается `superseded_at = now`, чеканится новый
  (`expires_at = now + ttl`) — `queued`/`floor`. Срок от чеканки; повтор срок не продлевает (Р6).
- Время — параметр `now` из внедрённых часов во всех запросах кодов, окон, ожидающих регистраций,
  висящих приглашений и меток; `now()` базы в этих запросах нет, включая переписанные
  существующие (М10) (CX2-16).
- Неверное предъявление код не гасит (Р6); ручка `verification-code-attempts` снята (З6).

Держатели: NTF2-40, 41, 87, 03, 82; гейт дерева `mail_clock_parameter` — в SQL-литералах файлов
`recovery_code_repo.go`, `verification_code_repo.go`, `mail_window_repo.go`,
`pending_registration_repo.go`, `trusted_device_repo.go` и запросах висящих приглашений
`now()`/`CURRENT_TIMESTAMP`/`clock_timestamp` — 0, печать числа разобранных литералов, инъекция
`now()` в один запрос — красный с координатой.

### З13. Постановка вне пути ответа — одна транзакция, отбрасывание не тратит окно

- `recovery` и `register` (после правил пароля и флага) отвечают `200 {}` и передают работу
  диспетчеру М7; путь ответа ничего не читает по адресу (CX2-17 (а)).
- Всё, что работа **пишет**, пишется **одной транзакцией**: якорь окна (`LockAnchor`, З11) →
  `Decide` → код (З12) → ожидающая запись (З14) → `feed.Put` → момент `mail_window_letters` с
  его `feed_id` (З11). Всё или ничего (CX2-14 (а, в)). У `register` этой транзакции
  предшествуют чтение без блокировки и выводы пароля вне транзакции (З14, CX2-34). Оба шага
  ничего не пишут, и решение, которое пишется, принимается только под блокировкой якоря.
- Отброшенная ёмкостью работа окна не касается (транзакции нет) и считается исходом
  `dropped_overload` той же метрики (CX2-17 (б)).
- Ёмкость — константа `mailDispatchInFlight = 16` (М7; переименование `recoveryDispatchInFlight`);
  метрика занятости `kaname_mail_dispatch_in_flight{class}` (gauge) (CX2-17 (в)). Ручкой не
  является: 51 ключ Р8 — предел писем, а не ресурсов процесса.
- **Места диспетчера разделены по классу работы** (CX2-36 (а)). Сегодня у диспетчера один
  счётчик на все работы (М33). Работа `register` ждёт место доли проверяющего до 30 с (З14), и
  с общим счётчиком поток регистраций занял бы все 16 мест ожидающими работами — письмо
  восстановления владельцу адреса отбрасывалось бы из-за чужих регистраций. Поэтому
  `mailDispatchInFlight` — сумма двух непересекающихся классов: `recoveryDispatchPlaces = 12` и
  `registerDispatchPlaces = 4`. Работа класса, чьи места заняты, отбрасывается `dropped_overload`
  **своего** глагола; места другого класса она не берёт ни при каком потоке. Довод числа 4:
  выводы `register` идут по одному (доля = 1, З14), поэтому пятая ожидающая работа не получила
  бы вывода раньше, чем при повторе запроса, — она только держала бы горутину и срок. Четыре
  места — одна работа на выводах и три в очереди: сглаживает всплеск, а
  восстановлению остаются 12 мест из прежних 16 при любом потоке `register`. Сумма классов
  равна `mailDispatchInFlight`, поэтому страж пула (ниже) и И22 не меняются: транзакций
  постановки одновременно по-прежнему не больше 16. Равенство суммы и «каждый класс ≥ 1»
  судит модульная проба констант.
- **Отношение к пулу базы держит страж старта, а не довод** (CX2-17, условие пересверки):
  транзакции постановки берут соединения из общего пула kaname, и при пуле не больше ёмкости они
  вытеснили бы вход и прочие глаголы. Страж старта сравнивает `mailDispatchInFlight` с
  **действующим** пределом пула — значением `MaxConns` разобранной конфигурации пула после
  подстановки умолчания драйвера (М22: умолчание процесса `0` значит «умолчание драйвера»), — и
  при `MaxConns ≤ 2 × mailDispatchInFlight` отказывает в старте, называя оба числа и ключ
  `repository.postgres.max-conns`. Множитель 2 — половина пула остаётся путям запроса. Обе
  поставки задают 80 и 40 (М22) и проходят.

Держатели: NTF2-67; модульная проба «ёмкость исчерпана → `dropped_overload`, окно не тронуто»
(CX2-17, заказ); проба стража «`max-conns` = 32 → отказ старта с обоими числами; 33 → старт»
(CX2-17); integration-проба гонки окна (CX2-14, заказ): `N` параллельных `recovery` на `A`
в один момент часов → одна строка ленты, один живой код; то же для `register`. По CX2-36 —
проба классов мест: место доли `register` держит заглушка проверяющего, приходят 16 работ
`register` → 4 ждут, 12 — `dropped_overload{verb="register"}`; затем работа `recovery` →
исполнена (строка ленты +1, `dropped_overload{verb="recovery"}` +0). Близнец меняет один факт —
классы сняты инъекцией (один счётчик на 16): те же 16 работ `register` занимают все места,
`recovery` → `dropped_overload{verb="recovery"}` +1, строк ленты +0 — красный. Модульная проба
констант: `recoveryDispatchPlaces + registerDispatchPlaces = mailDispatchInFlight`, каждый
класс ≥ 1; инъекция 12 + 5 — красный с обоими числами.

### З14. Регистрация «сначала письмо»

- Таблица `pending_registrations`: `id`, `key_digest` (ключ окна `registration`, `mailkey.Abuse`),
  `address_digest` (`HMAC(k_window, mailkey.Account(Normalize(email)))` — то же тождество, что
  уникальность учётки `lower(email)`), `password_hash`, `code_digest`, `created_at`, `expires_at`.
  Адреса открытым текстом нет.
- **Код однозначно указывает запись адреса** (CX2-33): `code_digest = HMAC(k_window,
  address_digest ‖ code)` — детерминированная свёртка; `UNIQUE (address_digest, code_digest)` не
  допускает двух записей адреса с одним кодом (индекс полный: живость записи зависит от часов и
  в предикат частичного индекса не входит; совпадение с истёкшей, ещё не убранной записью только
  вызывает повтор чеканки). Чеканка кода, давшая `23505` на этом индексе, повторяется новым
  случайным кодом в той же транзакции (точкой сохранения), не более 3 раз, затем — ошибка
  хранилища.
- `register` (асинхронная часть, З13): свободный адрес (нет `users.lower(email)`) — ищется живая
  запись с тем же `address_digest` и тем же паролем: есть → письмо с её кодом (`resent_same`);
  нет → новая запись с новым кодом, если окно пропустило. Занятый — письмо
  `registration-existing`, учётка не меняется. Число живых записей адреса ≤ числа писем окна
  (Р6): ≤ `per-day` + ⌈24 ч / `floor-interval`⌉ = 44 на границах Р8 (CX2-19 (б)).
- **«Тот же пароль» узнаётся одним выводом, а не сверкой с каждой записью** (CX2-34 (в)). Запись
  несёт, кроме `password_hash` (случайная соль хешера, М28; становится паролем учётки при
  подтверждении), **пробу пароля** `password_probe = argon2id(пароль, соль_адреса)` с
  параметрами класса цены пароля kaname (М23). Соль адреса — первые 16 байт
  `HMAC-SHA256(k_window, "registration-probe" ‖ address_digest)`: одна на адрес, выводится только
  с ключом службы. У всех записей одного адреса проба одного пароля совпадает. Поэтому работа
  вычисляет пробу **один раз** и сравнивает её со пробами всех живых записей адреса
  постоянным временем, без раннего выхода. Сравнение байтов стоит микросекунды и под
  блокировкой допустимо. Цена хранения названа: у записи два значения, производных от пароля,
  оба ценой argon2id. Проба без ключа службы не вычисляется, поэтому перебор по утёкшей базе
  не дешевле, чем по `password_hash`. Запись живёт не дольше `expires_at + 24 ч` (ниже).
- **Порядок работы `register`** — три шага, и выводы пароля не идут ни под блокировкой якоря, ни
  с соединением пула (CX2-34 (в)):
  1. **предрешение** — короткое чтение без блокировки: моменты окна, занятость адреса. `Decide`
     над снимком не пропускает письмо или адрес занят → выводов нет. Исход непропуска —
     исход `Decide`, строк нет. Занятый адрес идёт сразу к шагу 3. Шаг 1 ничего не пишет и
     только отсекает работы, которым выводы не понадобятся;
  2. **выводы** — без транзакции и без соединения: `password_probe` и `password_hash`, ровно
     **два** вывода argon2id на работу (константа `registerDerivations = 2`) при любом числе
     записей адреса. Хеш вычисляется всегда, даже если запись найдётся: иначе шаг 3 при
     истёкшей под ним записи вычислял бы хеш под блокировкой;
  3. **решение** — транзакция З13 под `LockAnchor`: `Decide` заново (решает только он). Затем
     занятость адреса заново. Затем живые записи адреса и сравнение пробы со всеми. Совпала →
     `resent_same` с её кодом. Не совпала ни одна, в том числе запись, появившаяся после шага 1, →
     новая запись с `password_hash` и `password_probe` из шага 2. Выводов под блокировкой нет.
- **Ёмкость выводов** (CX2-34 (б)). Выводы шага 2 занимают место **того же** проверяющего, что
  вход: память одного вывода учтена стражем памяти `verifier-capacity` (М26), и второго
  неучтённого пула argon2id в процессе нет. Правила занятия:
  - **ожидание, а не отказ** — выводы берут место ожидающим захватом (`acquireWait`, М26;
    проверяющий получает метод `DeriveWait(ctx, work)`), срок ожидания — срок работы
    (`30 с`, М7);
  - **не больше одной работы `register` на проверяющем одновременно** — перед захватом места
    работа берёт место доли `register`: канал ёмкостью `registerDerivationShare = 1` (приём
    доли церемонии, М26). Сколько бы работ ни шло в диспетчере (16, З13), выводы `register`
    занимают не больше одного места проверяющего;
  - вход и полоса церемонии ходят прежним захватом без ожидания. При ёмкости `c` у входа
    остаётся `c − 1` мест, пока идут выводы, и `c − 1 − ⌊c/2⌋`, пока ещё и церемония занимает
    свою долю. Цена названа числами профилей (М27): при `c = 8` — не меньше 3 мест входу; при
    `c = 2` — 1 место без церемонии. При `c = 1` (профиль с пределом памяти, который поднять
    нечем) вход, пришедший во время двух выводов одной пропущенной окном работы `register`,
    получает прежний отказ по ёмкости. Отказ виден существующей тревогой ёмкости проверяющего.
    Долю `register` меньше одного места не сделать: при нуле регистрация на этом профиле не
    работала бы вовсе;
  - **доля занята не дольше половины времени при любом потоке** (CX2-36 (б)). Цена «два вывода
    на письмо» — цена одного письма, а поток пропущенных `register` край не ограничивает сверху:
    выше 20 rps общего потока Р8 — вызов PoW, а не отказ, а окно адресата считает письма на
    адрес, а не число адресов. Когда поток выше пропускной способности доли, без меры доля была
    бы занята непрерывно и вход на `c = 1` получал бы отказ всё время потока. Поэтому доля
    освобождается не в момент возврата места проверяющего, а после **паузы, равной времени,
    которое выводы этой работы держали место** (множитель `registerSharePause = 1`; время —
    по монотонным часам, параметром, И9). Пауза держит только место доли: работа идёт к шагу 3
    сразу, место диспетчера и горутину пауза не держит (снятие доли — таймером часов). Отсюда
    доля времени, когда место проверяющего занято выводами `register`, не больше
    `1 / (1 + registerSharePause) = 1/2` при **любом** потоке, в том числе на границе края и
    выше неё. Числа по профилям при потоке, насыщающем долю: `c = 1` — место свободно для входа
    не меньше половины времени (без паузы — 0); `c = 2` при занятой доле церемонии — одно место
    входу не меньше половины времени (без паузы — 0); `c = 8` — не меньше 3 мест всё время, как и
    прежде. Цена паузы — пропускная способность `register`: одна работа на `4d` вместо `2d`
    (`d` — один вывод argon2id). Насыщение наступает, когда 20 rps > `1 / (4d)`, то есть при
    `d` > 12,5 мс; время вывода на узле стенда до кода не измерено (пересверка на редакцию 3,
    `not_measurable`), поэтому замысел утверждает свойство при насыщении, а не порог. Работы
    сверх пропускной способности кончаются `dropped_overload{verb="register"}` — у диспетчера
    (класс, З13) или по сроку ожидания доли (ниже); ответ уже отдан, повтор законен.
- **Исход «ёмкость исчерпана» у работы `register` — свой** (CX2-34 (а)). Срок ожидания места
  доли или проверяющего истёк → работа кончается **до** транзакции шага 3: записи нет, момента
  нет, письма нет, код не чеканится. Исход — `dropped_overload` метрики
  `kaname_mail_intents_total{verb="register"}` (тот же исход, что отброс диспетчером, З13: работа
  не исполнена по ёмкости процесса, окно не тронуто). Прочтения «пароль не совпал» (новая запись)
  и «ошибка» (молчаливое падение) у этого исхода нет. Ответ пользователю уже отдан (`200 {}`), и
  повтор `register` — законный путь.
- `register/confirm` (CX2-33 — ровно одна сверка пароля при любом числе записей): живые записи с
  тем же `address_digest` → `code_digest` предъявленного кода вычисляется один раз и сравнивается
  **постоянным временем со всеми** живыми записями адреса (без раннего выхода); пароль
  сверяется **только** со свёрткой записи совпавшего кода; совпадения нет — сверка с
  фиктивной свёрткой той же цены (параметры класса цены пароля kaname, М23), результат
  отбрасывается. Итог: один вызов свёртки пароля на каждый `confirm`, время ответа не зависит ни
  от числа записей, ни от их наличия. Нашлась и пароль совпал — одна транзакция: учётка,
  **подтверждённый** адрес (значение `Normalize`, З11), личный аккаунт, сессия (следствия Ф4),
  удаление **всех** ожидающих записей адреса (CX2-19 (а)). `23505` на `users_identity_email_uniq` в
  этой транзакции → побайтово тот же `401 authentication failed`, не `ALREADY_EXISTS` и не
  `INTERNAL` (CX2-19 (в), NTF2-84). Уникальность адреса судит база (ban #10).
- Истёкшие ожидающие записи удаляет уборка kaname (реестр `internal/apps/kaname/retention`,
  предмет `pending_registrations`) через `expires_at + 24 ч` — константа хранения с доводом:
  истёкшая запись предъявлением не принимается (Р9), окно считает `mail_window_letters`, а не
  записи, поэтому сутки запаса нужны только разбору обращений и затем свёртка пароля удаляется;
  уборка — вне пути запроса (CX2-19 (а)).

Держатели: NTF2-80…87; проба «истёкшая запись удалена к сроку хранения» (CX2-19, заказ); проба
«число вызовов свёртки пароля на `confirm` = 1 при 0, 1 и 44 живых записях адреса, при совпавшем и
несовпавшем коде» — счётчик вызовов на порте проверяющего (CX2-33); integration-проба «вторая живая
запись адреса с тем же кодом отвергнута индексом, чеканка повторена» (CX2-33). По CX2-34:
- проба голодания: 16 работ `register` на 16 разных свободных адресов, у каждого по 44 живые
  записи, при `verifier-capacity = 2`. Вход паролем во время работ получает `matched`, а не
  отказ по ёмкости. Одновременно занятых выводами `register` мест проверяющего не больше 1
  (наблюдается датчиком доли). Близнец: доля снята инъекцией, вход получает отказ по ёмкости;
- проба исхода: срок ожидания места истёк в работе `register` → записей +0, моментов +0, строк
  ленты +0, `dropped_overload` +1;
- проба числа выводов: 2 вывода на работу при 0, 1 и 44 живых записях адреса и 0 выводов при
  непропуске окна на шаге 1 (счётчик на порте проверяющего);
- проба места выводов: во время выводов шага 2 работа не держит ни блокировки якоря, ни
  соединения пула (датчик соединений пула и соседняя транзакция, берущая якорь без ожидания);
- integration-проба «запись с тем же паролем появилась между шагом 1 и шагом 3 → `resent_same`,
  второй записи нет».

По CX2-36 (проба классов мест диспетчера — З13):
- проба доли времени: управляемые часы, `verifier-capacity = 1`, заглушка вывода длительностью
  `d` по этим часам, поток работ `register`, насыщающий класс, на отрезке `100 d`. Датчик
  занятости проверяющего печатает долю времени под выводами `register` — не больше `1/2`
  (допуск — один вывод на краях отрезка). Вход в момент внутри паузы → `matched`. Близнец меняет
  один факт — `registerSharePause = 0` инъекцией: доля ≥ `0,99`, вход в тот же момент →
  отказ по ёмкости — красный;
- проба паузы без работы: во время паузы работа уже прошла шаг 3 (строка записи есть), место
  её класса у диспетчера свободно, горутин работы 0.

### З15. Один страж попыток на три пути предъявления

- `humansession.AttemptGuard` с параметром пути `recovery-complete` \| `register-confirm` \|
  `verify-email-confirm`; оси Р6: «адрес + источник» (`address-source-per-window` за `window`) и
  потолок неудач адреса для устройств без метки (`address-failure-ceiling`, окно от первой неудачи,
  истекает с ним). Отказ по частоте — одна форма Ф5-08, одинаковая для любого адреса. Успех
  сбрасывает счёт (CX2-18). Ключ адреса стража — `mailkey.Account` (З11), единственный ключ
  стража во всём `humansession`.
- Вызывающих стража ровно три; гейт дерева печатает их число (3) и краснеет на четвёртом
  собственном счётчике попыток в `humansession` (инъекция — копия счёта в `verification.go`).

Держатели: NTF2-66 (а)–(д), 03, 82; вариант NTF2-66 на `verify-email/confirm` (CX2-18, заказ).

### З16. Класс S — одна точка записи аудита, карта, снимок адресатов

- **Одна точка в прод-дереве** (CX2-05 (а)): `auditwrite.Insert(ctx, tx, ev)` (переименованная
  `insertAuditEventTx`) — единственный оператор `INSERT INTO kaname.audit_outbox` в не-тестовом
  дереве Go; четыре отдельные формы М6 переписываются на неё. `Insert` после строки аудита зовёт
  `securitynotice.Enqueue(ctx, tx, ev)`.
- **Миграции пишут аудит SQL-ом, и писем не ставят** (CX2-05, отказ пересверки; М6а): миграция,
  снимающая выдачи, обязана оставить след вставкой в `kaname.audit_outbox` — это норма соседнего
  гейта (`TestMigrationRemovingGrantsLeavesATrace`), и замысел её не меняет. Письмо класса S из
  миграции не ставится: постановка — это окно, лимит шаблона и `feed.Put`, то есть код процесса
  kaname, а миграция исполняется мигратором до старта процесса и применённой не правится (ban #5).
  Довод, что это не дыра класса S: три существующие формы снимают выдачи служебных учёток модулей
  и группу системного аккаунта с пустым `actor` — ни субъект, ни аккаунт этих строк не
  человек-арендатор, которому класс S адресует письмо (М6а). Чтобы будущая
  миграция не сняла доступ человека молча, число миграционных форм держит **двусторонний
  храповик** гейта `audit_outbox_single_writer` (`MigrationAuditFormsRatchet = 3`, тот же приём,
  что `GrantRemovalRatchet` соседа): новая миграция, пишущая `audit_outbox`, краснит гейт до
  сознательного изменения числа, и находка называет вопрос, на который обязан ответить автор —
  снимает ли миграция доступ человека; если да, снятие идёт прод-глаголом с письмом, а не
  миграцией.
- **Посев** администратора облака (CX2-05 (б)) идёт через ту же точку без исключения: строка
  `cluster_admin.granted` посева ставит письмо, как любая выдача; адресат, не подтвердивший адрес,
  письма не получит (`DENIED(recipient)` в notify) — отдельной ветки «посев не извещает» нет.
- **Писатель аудита приходит в посев параметром** (CX2-05, условие пересверки на редакцию 2;
  М32). Сегодня `RunBootstrapAdmin` пишет `audit_outbox` своим литералом в своей транзакции.
  После изменения он получает порт `auditwrite.Writer` (`Insert(ctx, tx, ev)`) параметром входа
  и зовёт его в той же транзакции, где пишет `cluster_admin_grants` и `fga_outbox`.
  Композиционный корень (`cmd/kaname/serve.go`) передаёт **тот же** писатель, что получают
  глаголы, уже собранный с `securitynotice`. Литерала `INSERT INTO audit_outbox` в пакете
  `seed` нет. Незаданный писатель — ошибка сборки посева, а не пропуск аудита. Иначе первый обход
  гейта краснел бы на посеве, а посев оказался бы вне карты класса S молча.
- **Карта** `internal/apps/kaname/securitynotice/map.go`: 23 вида аудита → шаблон → правило
  адресата (Р3); вид вне карты писем не ставит.
- **Адресаты — снимок в транзакции события** (CX2-07 (а, б)): «владельцы аккаунта» — одно
  определение: `accounts.owner_user_id` строки аккаунта события; «администраторы облака» — строки
  `cluster_admin_grants`; «контакт безопасности области» в NTF-2 — владельцы аккаунта для области
  аккаунта и администраторы облака для облака (контакты по категориям — NTF-3). Модель прав не
  спрашивается. На каждого адресата — строка ленты с формой адресата `subject` \|
  `account_security_contact`.
- **Идемпотентность** (CX2-06): таблица `security_notice_ledger (audit_event_id, template,
  recipient_user_id)` с первичным ключом; вставка `ON CONFLICT DO NOTHING` в той же `tx`,
  `feed.Put` — только при вставленной строке. Конфликт — не ошибка и транзакцию события не роняет.
  Схема ленты NTF-1 не меняется.
- **Исход глагола при сбое письма** (CX2-25) — одна ветка: исходы политики (`Disabled`,
  `Capped` лимита шаблона, пустое множество адресатов) глагол **не** роняют — событие фиксируется
  без строки, исход виден метрикой `kaname_security_notices_total{kind,outcome}`; ошибка
  хранилища на вставке — ошибка всей транзакции события (fail-closed: частичного коммита
  «событие без письма из-за сбоя базы» нет). Довод — тот же, что у Р4: действие безопасности
  (блокировка, отзыв) не зависит от возможности известить.
- **Пустое множество адресатов** (CX2-07 (в)) — исход `unaddressed` метрики с именем вида и
  тревога на любое ненулевое значение, а не ошибка транзакции: вид без адресата — неисправность
  установки (нет администраторов облака), и отказ в блокировке из-за неё ослабил бы защиту.
  Отступление от формулировки разбора принято пересверкой на редакцию 1 с условием к коду, и
  условие — часть решения (CX2-07): метка `unaddressed` входит в закрытый набор меток
  `kaname_security_notices_total`, зарегистрированный при старте; правило тревоги
  «`unaddressed` > 0» ставит чарт kaname обеих поставок (строка правила — в гейте двух поставок
  З23); проба «событие без адресата → глагол исполнен, строк ленты 0, метрика `unaddressed` +1».

Держатели: NTF2-88…97, 89 (писатель аудита производит `access_key.transferred`); гейт дерева
`audit_outbox_single_writer` (CX2-05 (в)) — два обхода одним распознавателем
(`(?i)insert\s+into\s+(kaname\s*\.\s*)?audit_outbox`, терпимым к регистру и пробелам, как у
соседа): (1) не-тестовый Go вне `auditwrite` — находка с координатой, печать числа форм (1),
инъекция одной из четырёх прежних форм — красный; (2) накатные половины `internal/migrations/*.sql`
— храповик 3, печать имён; инъекция четвёртой миграции с вставкой — красный, снятие вставки из
копии одной из трёх — красный; пустой обход любой стороны — красный; проба «событие без адресата»
(CX2-07). Обход (1) называет пакет `seed` в напечатанном перечне осмотренных пакетов. Инъекция
литерала обратно в `seed/bootstrap_admin.go` — красный с координатой. Проба посева: подменённый
писатель получил ровно 1 вызов с видом `cluster_admin.granted` в транзакции посева; посев без
писателя — ошибка сборки (CX2-05, условие).

### З17. Сигнал ленты — строка журнала kaname в той же транзакции

- `feed.Put` corelib пишет строку журнала подписки через порт журнала, который композиционный
  корень kaname передаёт адаптером над `subject_change_repo` (`tx` та же). Событие вида
  `notification_feed`, объект `notification_feed:kaname`, состояние — словом
  `state_unavailable` (CX2-27).
- Проба отката (заказ разбора): откат транзакции глагола уносит строку ленты, строку журнала и
  строку окна (NTF2-89 — тот же исход для аудита).

### З18. Метка доверенного устройства

- Печенье `kacho_device` (`Secure`, `HttpOnly`, `SameSite=Strict`, путь `/iam/v1/auth/`):
  `v1.<id>.<HMAC-SHA256(k_device, id ‖ user_id ‖ issued_at)>`. В базе — `trusted_devices (id,
  user_id FK, label_digest, issued_at)`; `label_digest = SHA-256(значение)`.
- Метка действует, только если подпись верна, строка есть, `user_id` строки = субъект, чей адрес
  в запросе, и `now < issued_at + ttl` (CX2-24). Запас восстановления — по паре (ключ окна,
  метка). Вход с действующей меткой новой не выдаёт и срок не продлевает (NTF2-78 (а, б)).
- Выдают метку: вход паролем без действующей метки (с письмом `new-device-login`),
  `register/confirm` и `recovery/complete` (без письма, Р12).
- **Срок хранения метки** (CX2-35 (а)): строка `trusted_devices` заводится на каждый вход паролем
  без действующей метки, а после `issued_at + ttl` не действует ни для чего. Уборка (предмет
  `trusted_devices` реестра `retention`) снимает строки с `issued_at` старше `now − retention`,
  где `retention = верхняя граница ручки срока метки + 1 ч`. Функция та же, что у моментов (З26),
  над той же таблицей границ, а не над настроенным значением. Поэтому поднятие ручки в пределах
  границы не делает действующую метку убранной. Уборщик пишет одним `DELETE … WHERE issued_at <
  $cutoff` пачками, вне пути запроса. Недействующая строка на путь входа не влияет, и гонки со
  входом нет: вход сверяет срок сам, а строки, которую удалили, для него просто нет.
- **Ключи kaname** (CX2-13): `k_window` (свёртка ключа окна и адресов ожидающих регистраций) и
  `k_device` — удостоверения профиля, файлы секрета по ручкам
  `authn.secrets.mail-window-key-file` и `authn.secrets.device-label-key-file` (вне поддерева
  `authn.login.*` — чтобы не смешиваться с 51 ключом Р8); без файла или короче 32 байт — отказ
  старта с именем ручки; вывода из другого секрета нет. **Смена `k_window`** — окна адресатов и
  ожидающие регистрации начинаются заново (прежние свёртки не совпадут); **смена `k_device`** —
  все метки недействительны. Оба свойства объявлены на странице поставки kaname.

Держатели: NTF2-70, 78, 94, 43, 80; вариант «метка `A` предъявлена для адреса `B` — запаса нет»
(CX2-24, заказ); отказ старта без каждого из трёх ключей (З9, З18) (CX2-13, заказ); проба уборки
меток «строка старше срока хранения снята, младше — нет» на управляемых часах и строка
`trusted_devices` в табличной пробе З26 (CX2-35).

### З19. Шаблоны kaname и лимит шаблона ленты

- 24 каталога `notifications/<name>/{notification.yaml, body.ru.yaml}` по таблице Р3, все класса
  `security`; `notifications/required-security.yaml` — 24 имени; гейт «обязательный класс»
  `internal/check/required_security_templates.go` (NTF2-99).
- **Лимит шаблона** (`limits`, обязателен у `security`, NTF-1 Р7) — предохранитель ленты, а не
  рубеж: значение статично (время сборки), а рубеж З11 задают ручки установки. Поэтому лимит
  шаблона **не меньше наибольшего числа писем, которое допускают границы Р8**, и никогда не режет
  письмо, пропущенное окном (иначе лимит отрезал бы владельца):

  | шаблоны | лимит на адресата в сутки | вывод |
  |---|---|---|
  | `recovery` | 49 | `per-day` ≤ 20 + пол ⌈24 ч / 1 ч⌉ = 24 + запас устройства ≤ 5 |
  | `verification`, `registration`, `registration-existing` | по 44 | 20 + 24 |
  | `mail-throttled` | 1 | интервал ≥ 1 сут |
  | `invite` | 50 | граница стража ниже («Приглашения») |
  | 18 шаблонов аудита | по 10 | событийные; сверх — исход `capped` метрики класса S |

- **Приглашения:** у `invite.recipient-per-day-all` в Р8 верхней границы нет; поэтому страж
  старта kaname требует `invite.recipient-per-day-all ≤ 50` (лимит шаблона `invite`, вписанный
  генератором константой) — иначе значение выше 50 было бы принятым и проигнорированным. Граница
  добавляется в таблицу Р8 правкой приёмки (Е3).
- **Сумма для сетки notify:** страж старта notify (NTF-1 H07) требует сетку `security` ≥ 1,25 ×
  Σ лимитов шаблонов = 1,25 × 412 = 515 (граница ручки NTF-1 — `[1..1000]`); инвариант NTF2-73
  (1,25 × суммы суточных пределов kaname по ручкам) при этом выполняется всегда, потому что
  лимиты шаблонов не меньше пределов по ручкам. Цена названа: сетка `security` на адресата — не
  ниже 515 писем в сутки. Класс `security` приходит только из пространства `kaname` (NTF-1 Р6),
  и точный предел на адресата держит рубеж З11; сетка — защита от ошибки kaname, а не рубеж.
- Помощник суммы NTF2-73 один — `kacho.notifications.kanameDailySum` (CX2-23): слагаемые по
  назначениям (`per-day` + ⌈24 ч / `floor-interval`⌉ ×3), запас устройства и
  ⌈1 сут / `mail-throttled-interval`⌉; отказ рендера печатает слагаемые.

Держатели: NTF2-08, 45, 73, 99; гейт «лимит шаблона ≥ максимума по границам Р8» — модульная проба
над константами генератора и таблицей границ стража kaname (одно объявление границ).

### З20. Справочник адресов и разрешение адресатов — внутренние методы kaname

- Новый сервис `kaname.cloud.iam.v1.InternalNotificationRecipientService` (§5) на **внутреннем**
  слушателе kaname: `GetVerifiedAddress`, `ResolveAccountOwners`, `ResolveCloudAdmins`
  (CX2-08 (в)). Письма NTF-2 зовут только `GetVerifiedAddress`; два прочих нужны NTF-3.
- **Право — отношение модели, не сравнение строки** (CX2-08 (а)): аннотация каждого метода —
  отношение `reader` на объект `notification_feed:kaname`; проверку исполняет та же дверь прав
  kaname, что отвечает `InternalIAMService/Check` (как `ResolveSend`, NTF-1 Р5). `reader` на ленту
  kaname есть только у `service:notify` (строка манифеста, З21). Сравнения имени службы в Go нет.
- **Проверка исполняется в теле метода** (CX2-08, условие пересверки): у внутреннего слушателя
  kaname звена `authz.Interceptor` нет (NTF-1 §1.6), поэтому аннотация сама ничего не исполняет.
  Каждый из трёх методов первым стейтментом после проверки формы идентификатора зовёт
  `Check(вызывающий, reader, notification_feed:kaname)` той же двери прав — так же, как
  `ResolveSend` (NTF-1 Р5); аннотация остаётся записью каталога прав и входом гейта
  «аннотация ↔ исполняемая проверка». Отказ двери — `PERMISSION_DENIED` ниже; недоступность
  двери — `UNAVAILABLE` (fail-closed).
- **Закрытый перечень методов звена идентичности** (NTF-1 Р2) у kaname дополняется тремя методами;
  пустой перечень — отказ старта (CX2-08 (б)); записи каталога прав — у каждого метода.
- **Отказ** — `PERMISSION_DENIED` фиксированным текстом звена `DenyDetailUnary` kaname, побайтово
  один у трёх методов, без адреса и идентификатора (CX2-08 (г)).
- **Не подходящий адресат** (не ACTIVE, не подтверждён, нет такого) — не ошибка, а ответ
  `not_eligible` (§5): notify закрывает строку `DENIED(recipient)` (NTF2-92, 96). Негодный по
  форме id — `INVALID_ARGUMENT` первым стейтментом.
- **Ответ справочника без нулевого значения** (CX2-31): ответ — `oneof result { string address;
  NotEligible not_eligible; }` вместо перечисления с `…_UNSPECIFIED = 0` и строки «пусто иначе».
  Отсутствие ответа (`result` не задан) представимо отдельно от обоих значений. Сервер
  утверждает: ровно один вариант задан, и `address` непуст и разбирается `address.Normalize`
  (иначе — `INTERNAL` фиксированным текстом, а не ответ). Читатель (notify, NTF-1) трактует
  `result` не задан и пустой `address` как ошибку протокола — не `DENIED(recipient)`, а исход
  «ответ не разобран» классификатора чужого ответа notify (повтор с отсрочкой и счётчик); это
  условие к читателю — заказ пакету NTF-1 (Е8).
- Ребро `notify → kaname` (справочник) записывается в правило топологии с доводом ацикличности:
  kaname не зовёт notify ни одним вызовом (CX2-08 (д)); запись — задача `kacho-workspace#881`.

Держатели: NTF2-88 с близнецом; `TestCatalogReachability_EveryRowResolvesToAServedMethod`;
`assert-ban6-external-isolation.py` (метода нет на внешнем слушателе); модульная проба каждого из
трёх методов «вызывающий без `reader` → `PERMISSION_DENIED`, хранилище не спрошено; дверь
недоступна → `UNAVAILABLE`» при снятой аннотации — проверка в теле держит отказ сама (CX2-08);
модульная проба сервера «ответ всегда с заданным вариантом, `address` непуст» (CX2-31).

### З21. Служебный принципал kaname и строка права отправки

- По Д2 (К1): в манифесте kaname — одна строка
  `notifications: {namespace: kaname, readers: [notify]}`; применитель посева NTF-1 пишет
  `service:kaname sender notification_namespace:kaname` и `service:notify reader
  notification_feed:kaname`. Правило валидатора NTF-1 «`namespace` = `module`» для манифеста
  `module: iam` (М13) исполняется через строку таблицы источников З4: имя источника `kaname`
  — литерал этой строки, а не вывод из `module`.
- `service:kaname` — объект модели, заводимый манифестом (NTF-1 Р2 п.5), и субъект выдачи
  `sender`. Вызывающим он не бывает: kaname не зовёт ни notify, ни иную службу от имени
  `service:kaname`, поэтому в перечень звена идентичности kaname как вызывающий не входит.
  Записи `seed.serviceAccounts`/`joins` у kaname по-прежнему нет — TestMRW07 остаётся зелёным
  (М15). Тенантские поверхности субъекта `service:` не производят (NTF-1 Р2 п.5).
- Решение на письмо `ResolveSend` для пространства `kaname` зовётся, как для любого источника
  (Р14, NTF2-06): «шлюз проверяет доступы у канаме» исполняется одинаково для всех.

Держатели: NTF2-46, 47, 06; зависимость Е1.

### З22. Снятие почты поставщика личности (S6)

- Правки по DoD п.13–14 целиком; ключ `kratos.courier.enabled: false` — в
  `deploy/helm/umbrella/values.yaml` рядом с `kratos.enabled: false`.
- **Страж листа под `courier`** (NTF2-23): шаблон `deploy/helm/umbrella/templates/identity-provider-mail-guard.yaml`
  обходит `kratos.kratos.config.courier` рекурсивно и считает **скалярные листья**; лист — `fail` с
  полным путём ключа и текстом «почту установки шлёт только notify». Умолчание подчарта
  `{smtp: {}}` листьев не имеет и проходит (CX2-26 (а)).
- **Гейт единственного держателя** (NTF2-30…32, переписанный `identity_mail_lane_feeds_both_senders*`)
  перечисляет **все** источники томов и окружения: `secretKeyRef`, `envFrom.secretRef`, том
  `secret`, **проецируемый том** (`projected.sources[].secret`); источник тома или окружения
  неизвестного вида, чьё поле упоминает секрет, — красный «неизвестная форма» (CX2-26 (б)).
  Вариант инъекции NTF2-31 — проецируемый том (заказ).
- Гейты NTF2-18, 20, 21, 24 — по рендеру; каждый печатает объём обхода, пустой — красный.

### З23. Ручки лимитов без умолчаний; две поставки kaname — одна сверка

- 51 ключ Р8 и флаг: ни `SetDefault` в `defaults.go`, ни тега `default:` у края; страж старта
  называет ключ и нарушенную границу (NTF2-71). Границы Р8 объявлены **одной таблицей** в каждом
  из двух деревьев (`gateway/internal/config/anon_mail_bounds.go`,
  `internal/apps/kaname/config/mail_bounds.go`) — её читают и страж, и перепись вариантов (т)
  NTF2-71 (CX2-22 (а, б)).
- Ключи kaname приходят двумя поставками (подчарт зонтика и `deploy/` kaname). Гейт
  `deploy/kaname_two_deliveries_keys_test.go` (kacho) рендерит обе с базовыми значениями, разбирает
  конфигурацию kaname и сверяет множества ключей почтовых ручек (Р4, Р8, З18); печатает
  «поставок 2 · ключей N в каждой», расхождение — красный с именем ключа (CX2-22 (в)). Самостоятельная
  поставка kaname берётся пином (как в NTF-1 Р1).

### З24. Потолки приглашений — счёт актов, а не строк; в транзакции глагола

- **Что считается** (CX2-21, отказ пересверки; М19): приглашение — строка `kaname.users`
  (`invite_status = PENDING`), и эта строка — **состояние**, а не момент: повторная отправка
  письма строки не заводит, а удаление приглашения её снимает. Поэтому потолки считаются по
  таблице актов `invite_acts (id, account_id, kind, key_digest, at, lettered, feed_id)`:
  - `kind` — `invite` (глагол `users:invite`) \| `resend` (повторная отправка); одна строка на
    каждый принятый акт, в той же транзакции;
  - `key_digest` — свёртка `mailkey.Abuse` адреса приглашения (З11);
  - `lettered` — поставлено ли письмо; `feed_id` — строка ленты, если поставлено (`NOT NULL` при
    `lettered`, `CHECK`);
  - **внешних ключей нет ни на `users`, ни на `accounts`** (CX2-21, отказ пересверки на
    редакцию 2; М29): аккаунт удаляется физически, и каскад с `accounts` уносил бы акты вместе с
    аккаунтом. Тогда счёт `recipient-per-day-all` поперёк аккаунтов уменьшался бы удалением
    аккаунта: завести аккаунт, пригласить адрес до потолка, удалить аккаунт и повторить. Поэтому
    `account_id` — `text NOT NULL` без ссылки. Строка акта снимается **только** уборкой по сроку
    хранения (З26). Ни удаление приглашения, ни удаление аккаунта, ни удаление пользователя счёт
    не уменьшают. Это свойство строки без каскада, а не соглашение кода.
  - акт удалённого аккаунта остаётся в счёте потолков аккаунта до срока хранения. Этот счёт
    больше никто не читает: `users:invite` на удалённый аккаунт отвергается раньше, не найдя
    строки аккаунта под `FOR UPDATE`. Идентификатор аккаунта выпускается новым при каждом
    заведении и повторно не выдаётся, поэтому чужого счёта висящий акт не задевает. Ссылочной целостности у `account_id` нет
    намеренно: акт — след события, а не зависимая строка. Какого аккаунта он касался, пишет
    сам глагол в той же транзакции под блокировкой строки аккаунта.
- **Потолки:**
  - `account-per-day` (для аккаунта моложе `young-account-age` — `young-account-per-day`) —
    число актов `kind = invite` аккаунта за `(now − 1 сут, now]`; отказ Р7 синхронно, до
    `Operation`;
  - `pending-max` — число строк `users` аккаунта в `PENDING` с `expires_at > $now` (состояние,
    параметр часов); уборщика на пути нет (NTF2-77 (г));
  - `recipient-per-hour`, `recipient-per-day` — акты с `lettered` по паре (аккаунт,
    `key_digest`) за час и за сутки; `recipient-per-day-all` — по `key_digest` поперёк аккаунтов
    за сутки. Сверх — акт записан с `lettered = false`, письма нет, исход `capped` (Р7). Акты
    обоих видов, `invite` и `resend`, в эти потолки входят: повторная отправка — такое же письмо
    тому же адресату.
  - `resend` в `account-per-day` не входит: потолок аккаунта Р7 — про заведение приглашений, а
    повторная отправка приглашения не заводит; число её адресатов уже ограничено `pending-max`,
    а число писем каждому — потолками на адресата. Нового явного отказа у повторной отправки нет.
- **Сериализация:** `users:invite` и повторная отправка — одна транзакция: `SELECT … FOR UPDATE`
  строки аккаунта (потолки аккаунта и адресата «от аккаунта») → `pg_advisory_xact_lock(class,
  obj)` формы с двумя `int4` (`class` — константа `inviteRecipientLockClass`, `obj` — первые 4
  байта `key_digest`; потолок поперёк аккаунтов; тот же приём, что З8) → счёт → строка
  приглашения (только `invite`) → акт → письмо. Порядок блокировок один у обоих глаголов. Форма
  с двумя `int4` выбрана по той же причине, что у края (З8, CX2-11). Существующие
  рекомендательные блокировки kaname — только формы с одним ключом `hashtext(…)` (М30). Пространства
  не пересекаются, и ключ адресата не сериализуется с выдачами, каталогом или сверкой.
- Срок хранения актов — З26 (не меньше верхней границы окон, которые их читают: 1 сут).

Держатели: NTF2-69, 77; integration-проба параллельных приглашений на границе `account-per-day`
и `pending-max` (CX2-21); проба «повторная отправка сверх `recipient-per-hour` → `capped`, письма
нет» и «удаление приглашения после `recipient-per-day` писем → следующее приглашение того же
адреса в те же сутки — `capped`» (CX2-21); integration-проба «аккаунт `X` пригласил адрес до
`recipient-per-day-all`, аккаунт `X` удалён → приглашение того же адреса из аккаунта `Y` в те же
сутки — `capped`» с близнецом «сутки прошли → письмо» (CX2-21, пересверка на редакцию 2); проба
схемы «у `invite_acts` внешних ключей 0» (разбор `pg_constraint`).

### З25. Гейт смены адреса и документы

- Текст находки `internal/check/people_address_writers.go` называет условием внесения глагола
  смены адреса письмо класса `security` на прежний адрес в той же транзакции (NTF2-98).
- Тот же гейт получает второе условие (З11, CX2-20): каждый оператор, пишущий `users.email`
  (заведение учётки в `register/confirm`, строка приглашения), берёт значение типа
  `address.Normalized`; оператор, получающий адрес строкой мимо `Normalize`, — находка с
  координатой. Печать числа операторов; инъекция записи сырой строки — красный.
- Страницы поставки и настроек kaname (`docs/content/`) и сайт документации kacho называют флаг,
  ручки Р8, ключи З9 и З18 с поведением при их смене, одну ручку прыжков края и то, что почту
  шлёт только notify (DoD п.22).

### З26. Срок хранения моментов выводится из верхней границы окон, которые их читают

- **Правило** (CX2-29): у каждой таблицы моментов срок хранения — функция, а не литерал:
  `retention(kind) = max(верхняя граница каждого окна, читающего kind) + 1 ч`. Верхняя граница
  берётся из **той же** таблицы границ, что судит страж старта (З23: `mail_bounds.go` у kaname,
  `anon_mail_bounds.go` у края), а не из настроенного значения: поднятие ручки в пределах границы
  не делает прежние моменты невидимыми, и срок хранения строго больше любого окна, которое
  установка вправе задать. Запас 1 ч покрывает шаг уборки.
- **Сроки на границах Р8** (М20):

  | таблица · вид | окна, которые её читают | верхняя граница | срок хранения |
  |---|---|---|---|
  | `mail_window_letters` · `throttled` | `authn.login.mail-throttled-interval` | 30 сут | 30 сут + 1 ч |
  | `mail_window_letters` · `progression`, `floor` | паузы, `per-hour`, `per-day`, `floor-interval` | 24 ч | 25 ч |
  | `mail_window_letters` · `trusted_device` | `trusted-device.recovery-per-day` | 24 ч | 25 ч |
  | `invite_acts` | потолки приглашений «в час», «в сутки» | 24 ч | 25 ч |
  | край · `anon_mail_passes` | окна источника и подсети `W_*` | 24 ч | 25 ч |
  | `trusted_devices` (по `issued_at`) | срок метки `authn.login.trusted-device.ttl` (З18) | 365 сут | 365 сут + 1 ч |

  Числа таблицы — вывод, а не объявление: в коде стоит функция над таблицей границ, а табличная
  проба сверяет её вывод с этими строками.
- Предметы уборки kaname — реестр `internal/apps/kaname/retention`, по предмету на вид; у края —
  уборщик хранилища однократности, по той же функции. Прочие предметы хранения окнами не
  читаются, и их срок назван у их решения: ожидающие регистрации (З14, `expires_at + 24 ч`),
  использованные вызовы (З9, `expires_at`), `security_notice_ledger` (З16, сроком хранения
  аудита), якорь `mail_windows` (З11: снимается, когда у ключа нет ни моментов, ни ожидающих
  записей; числа срока у него нет — он следует за своими зависимыми строками). Строка ведра
  края `anon_mail_bucket` одна на всю установку и уборке не подлежит.
- **Перечень предметов хранения закрыт** (CX2-35): у каждой таблицы, которую заводит этот
  замысел, строка «предмет уборки — чем снимается» есть в реестре `retention` kaname или у
  уборщика хранилища края, либо её отсутствие названо доводом (ведро — одна строка). Табличная
  проба каждого дерева сверяет множество таблиц своих миграций NTF-2 с множеством своих
  предметов уборки и доводов. Таблица без
  строки — красный с её именем. Печать «таблиц N · предметов N · доводов M» по дереву.

Держатели: модульная проба «для каждого вида каждой таблицы моментов срок хранения > верхней
границы каждого читающего окна» над таблицами границ обоих деревьев — инъекция: вид `throttled`
с литералом 25 ч — красный с именем вида и границы (CX2-29); NTF2-68 (б) на П6 с управляемыми
часами и уборкой, сдвинутой на срок; проба закрытого перечня предметов хранения — инъекция
таблицы без предмета в копию миграции даёт красный с её именем (CX2-35).

## 3. Инварианты

| № | инвариант | чем держится |
|---|---|---|
| И1 | вызовы `Send*` — только в пакете `mail` kaname | гейт `mail_single_enqueuer`; NTF2-45 |
| И2 | флаг kaname не имеет умолчания ни в бинаре, ни в чарте; «не задан» ≠ `false` | NTF2-50, NTF2-53 (а); вариант рендера «глобальный `false`, модуль `true`» |
| И3 | флаг и перечень источников notify — один помощник | NTF2-53 (гейт печатает равенство чисел) |
| И4 | ось источника анонимных почтовых глаголов — только у края | проба дерева `ChargeSource` → 0; NTF2-60 |
| И5 | край и kaname считают источником один адрес | `ClientIP` — единственный вычислитель; проба «адрес края = адрес в kaname» |
| И6 | решение ограничителя и приращение — одна операция; ключ без строк сериализуется блокировкой ключа; состояние — у флота; отказ хранилища — `503`, не пропуск | рекомендательные блокировки по отсортированным свёрткам З8; integration-проба гонки нового ключа; проба `StoreUnavailable`; гейт пары хранилища |
| И7 | окно адресата — функция хранимых моментов; решение, код, запись и строка ленты — одна транзакция | табличная проба `Decide`; integration-проба гонки |
| И8 | один живой код на (назначение, субъект) | частичный `UNIQUE`; NTF2-40, 41 |
| И9 | время окон, кодов, записей, приглашений, меток — только параметр | гейт `mail_clock_parameter`; П6 |
| И10 | каждая запись `audit_outbox` в прод-дереве Go проходит через `auditwrite.Insert`, посев — тоже (писатель — параметр); миграционных форм ровно 3, изменение числа — сознательное | гейт `audit_outbox_single_writer` (два обхода, храповик); проба посева |
| И11 | одно событие — не больше одной строки на (шаблон, адресат) | PK `security_notice_ledger`; NTF2-97 |
| И12 | справочник адресов отвечает только `service:notify` — по отношению модели | NTF2-88 |
| И13 | секрет почты смонтирован ровно в одном объекте; форм ссылки — все, неизвестная — красный | NTF2-30…32 |
| И14 | лимит шаблона ленты не меньше максимума окна по границам Р8 | модульная проба констант генератора |
| И15 | неизвестный ключ файла или переменная kaname с `__` вне выводимого множества — отказ старта; ключи без умолчания зарегистрированы из таблицы границ | NTF2-48; проба переменной; проба привязки |
| И16 | нормализация ящика одна (`address.Normalize`), ключей от неё два именованных (`mailkey.Account`, `mailkey.Abuse`); `AddressKey` нет | проба `mailkey`; проба дерева `AddressKey` → 0; гейт NTF-1 B27 по kaname |
| И17 | `register/confirm` делает ровно одну свёртку пароля при любом числе записей | счётчик вызовов на порте проверяющего (0, 1, 44 записи) |
| И18 | срок хранения моментов строго больше верхней границы каждого читающего окна | модульная проба над таблицами границ; NTF2-68 (б) |
| И19 | ответ справочника адресов без нулевого значения: ровно один вариант, адрес непуст | модульная проба сервера; условие к читателю (Е8) |
| И20 | потолки приглашений считают акты; ни удаление приглашения, ни удаление аккаунта счёт не уменьшают — у `invite_acts` нет внешних ключей | integration-пробы З24; проба схемы |
| И21 | момент окна не существует без строки ленты своей транзакции | `feed_id NOT NULL`; проба отката |
| И22 | ёмкость постановки меньше половины действующего пула базы kaname | страж старта З13 |
| И23 | работа `register` делает 0 или 2 вывода argon2id при любом числе записей адреса; выводы — вне блокировки якоря и без соединения пула; одновременно не больше одного места проверяющего под выводами `register`; срок ожидания места истёк — `dropped_overload`, строк нет | пробы З14 (голодание, исход, число и место выводов) |
| И24 | уборка якоря окна не уносит ни момента, ни записи; `FOR UPDATE` якоря возвращает ровно одну строку, иначе — повтор вставки | внешние ключи `RESTRICT`; пробы З11 (уборка между вставкой и блокировкой, уборка с моментом) |
| И25 | у каждой таблицы NTF-2 есть предмет уборки или довод его отсутствия | табличная проба закрытого перечня З26 |
| И26 | рекомендательные блокировки NTF-2 — только формы с двумя `int4`; с блокировками одним ключом (схема края, прочие kaname) не пересекаются | гейт формы в `anonmail`; integration-проба пространства ключей З8 |
| И27 | работа `register` не занимает места диспетчера класса `recovery` (12 + 4 = 16); место проверяющего занято выводами `register` не больше половины времени при любом потоке | пробы классов мест (З13) и доли времени (З14) с близнецами; модульная проба констант |

## 4. Компоненты и границы

| компонент | репозиторий · путь | новый / правка | заводит |
|---|---|---|---|
| шаблоны и перечень | kaname · `notifications/**`, `notifications/required-security.yaml` | новый | З19 |
| сгенерированные функции и миграция ленты | kaname · `internal/apps/kaname/mail/feedgen/`, `internal/migrations/<ts>_notification_feed.sql` (вывод `notifygen init`) | новый | З1 |
| постановка, окно, коды, ключи адреса | kaname · `internal/apps/kaname/mail/`, `internal/apps/kaname/mailwindow/`, `internal/apps/kaname/mailkey/`, `internal/repo/kaname/pg/{mail_window_repo,pending_registration_repo,trusted_device_repo,invite_act_repo}.go` | новый | З1, З11–З14, З18, З24 |
| проверяющий пароля | kaname · `internal/passwordverify/{verifier,capacity}.go` (метод `DeriveWait` поверх `acquireWait`) | правка | З14 |
| диспетчер постановки | kaname · `internal/apps/kaname/api/humansession/dispatch.go` (классы мест), `cmd/kaname/loginlane.go` (константы классов) | правка | З13 (CX2-36) |
| глаголы | kaname · `api/humansession/{recovery_request,verification,recovery_complete,login,change_password,sf_backup_codes,sf_enroll,sf_remove,step_up,rate}.go`, `api/registration/{register,confirm}.go`, `api/user/{invite,resend_invite}.go` | правка / `confirm.go` новый; `AddressKey` снимается | З2, З7, З11–З15, З24 |
| полоса формы | kaname · `internal/handler/loginlanehttp/handler.go` (путь `register/confirm`, печенье метки) | правка | З14, З18 |
| аудит и класс S | kaname · `internal/repo/kaname/pg/auditwrite/`, `internal/apps/kaname/securitynotice/`, 4 формы М6 (включая `seed/bootstrap_admin.go` — писатель параметром), `cmd/kaname/serve.go` | новый + правка | З16 |
| справочник адресатов | kaname · `proto/kaname/cloud/iam/v1/internal_notification_recipient_service.proto`, `internal/apps/kaname/api/notification_recipient/`, регистрация в `cmd/kaname/grpc_register.go`, каталог прав | новый | З20 |
| манифест | kaname · `internal/servicemanifest/manifest.embedded.yaml` | правка (одна строка) | З21 |
| конфигурация | kaname · `internal/apps/kaname/config/{load,defaults,config,invite,login_lane,mail_bounds,notifications,strict_env}.go`; страж пула в `cmd/kaname/loginlane.go` | правка + новые | З2, З5, З13, З18, З23 |
| снятие почты kaname | kaname · `internal/clients/invite_mail*`, `cmd/kaname/invite_mail_wiring*`, `internal/check/mail_send_paths*`, `mail_kind_sender_parity*`, `internal/observability/metrics/*mail*` | снятие / переписка | З6 |
| гейты дерева kaname | kaname · `internal/check/{no_smtp_senders,mail_templates_match_calls,required_security_templates,mail_single_enqueuer,audit_outbox_single_writer,mail_clock_parameter,attempt_guard_callers,people_address_writers}.go` | новый / переписанный | З1, З6, З11, З12, З15, З16, З19, З25 |
| уборка | kaname · `internal/apps/kaname/retention/registry.go` (предметы по видам, функция срока над `mail_bounds.go`; предметы `mail_windows`, `trusted_devices`) | правка | З11, З14, З18, З26 |
| самостоятельная поставка kaname | kaname · `deploy/{values.yaml,templates/configmap.yaml,templates/deployment.yaml}` | правка | З23; NTF2-33 |
| ограничитель края | kacho · `gateway/internal/middleware/anonmail/**` (включая `testdata/pow_vectors.json`), `gateway/internal/middleware/{login_lane_paths.go,context_extractor.go}`, `gateway/internal/config/{config.go,anon_mail_bounds.go}`, `gateway/cmd/api-gateway/*` | новый + правка | З8, З9, З10, З26 |
| хранилище края | kacho · миграция хранилища однократности края (таблицы моментов и использованных вызовов) | новый | З8, З9 |
| консоль | kacho · `ui-future/shared/src/api/login-lane.ts`, `ui-future/shared/src/lib/pow/**` (решатель, срок жизни `Worker`, проба по общим векторам), `ui-future/shared/src/pages/auth/{RegistrationPage,RecoveryPage}.tsx` | правка + новые | З10 |
| зонтик | kacho · `deploy/helm/umbrella/{values*.yaml,templates/_notifications.tpl,templates/identity-provider-mail-guard.yaml}`, `charts/kaname/**` по §3а приёмки | правка + новые | З4, З19, З22 |
| гейты рендера | kacho · `deploy/*_test.go` по §3а; `deploy/kaname_two_deliveries_keys_test.go`; `gateway/deploy/idempotency_fleet_test.go` | переписка + новые | З8, З22, З23 |
| сквозные пробы | kacho · `gateway/tests/newman/cases/<коллекция NTF-2>` и запись ведомости производителя; `ui-future/e2e/specs/ntf2-*.spec.ts` | новые | DoD п.4, 9, 10 |

**Граница с соседями.** `corelib notify/*`, `notifygen`, служба `notify`, её чарт, таблица
подключаемых источников, звено идентичности служб, `ResolveSend`, `Revoke`/`Restore`, тревоги
ленты — NTF-1; NTF-2 их не пишет, а подключает источник kaname и добавляет в таблицу его строку.
Контакты по категориям, истечение ключей — NTF-3. Физическое снятие поставщика — `kacho#1276`.
Экспорт предиката «лимит возвращён» из `corelib notify/feed` и правило читателя ответа
справочника в notify — условия к NTF-1 (Е8), а не код NTF-2.

## 5. Набросок контракта

**proto (kaname), внутренний слушатель:**

```proto
// proto/kaname/cloud/iam/v1/internal_notification_recipient_service.proto
package kaname.cloud.iam.v1;

service InternalNotificationRecipientService {
  // Подтверждённый адрес пользователя в момент вызова. Право — reader на notification_feed:kaname.
  rpc GetVerifiedAddress(GetVerifiedAddressRequest) returns (GetVerifiedAddressResponse);
  // Владельцы аккаунта (accounts.owner_user_id). Для NTF-3.
  rpc ResolveAccountOwners(ResolveAccountOwnersRequest) returns (ResolveAccountOwnersResponse);
  // Администраторы облака (cluster_admin_grants). Для NTF-3.
  rpc ResolveCloudAdmins(ResolveCloudAdminsRequest) returns (ResolveCloudAdminsResponse);
}

message GetVerifiedAddressRequest { string user_id = 1; }
message GetVerifiedAddressResponse {
  // Ровно один вариант задан всегда; незаданный result — ошибка протокола у читателя (З20).
  oneof result {
    string address = 1;           // подтверждённый адрес, непустой, разбирается address.Normalize
    NotEligible not_eligible = 2; // не ACTIVE, не подтверждён или нет такого — без различения
  }
  message NotEligible {}
}
message ResolveAccountOwnersRequest { string account_id = 1; }
message ResolveAccountOwnersResponse { repeated string user_ids = 1; } // набор, порядок не значим
message ResolveCloudAdminsRequest {}
message ResolveCloudAdminsResponse { repeated string user_ids = 1; }  // набор, порядок не значим
```

Методы — чтения: `Operation` не возвращают. Отказы: негодный `user_id`/`account_id` —
`INVALID_ARGUMENT` `invalid <res> id '<X>'` первым стейтментом; затем проверка права в теле
метода (З20): не `service:notify` — `PERMISSION_DENIED` фиксированным текстом, дверь прав
недоступна — `UNAVAILABLE`; хранилище не ответило — `UNAVAILABLE` фиксированным текстом без
драйвера.

**HTTP полосы формы (kaname, ретранслирует край):**

- `POST /iam/v1/auth/register` — тело `{email, password, csrfToken}` без изменений формы; ответ
  `200 {}` без печений.
- `POST /iam/v1/auth/register/confirm` — **новый**: `{email, code, password, csrfToken}`, форма
  `register-confirm`; ответ — как у `login` (`{user, session}` + печенья сессии и метки).

**Отказы края:** `503` · `{code: 14, message: "request limiter is unavailable", details: []}` (З8,
`StoreUnavailable`);
`429` · `{code: 8, message: "proof of work required", details:
[ErrorInfo{reason: PROOF_OF_WORK_REQUIRED, domain: <домен отказов края>, metadata: {challenge,
difficultyBits, expiresAt}}]}` и `429` · `{code: 8, message: "too many requests", details:
[ErrorInfo{reason: RATE_LIMITED}]}` + `Retry-After`. Заголовок доказательства —
`X-Kacho-Proof: <challenge>:<nonce>`.

**Шаблон (пример формы, `notifications/recovery/notification.yaml`):**

```yaml
name: recovery
class: security
ttl: 15m
limits: {perRecipient: {perDay: 49}}
attributes: {code: secret, requested_at: timestamp}
subject: {ru: "Код восстановления доступа"}
```

## 6. Схема БД (набросок)

kaname, одна новая миграция после миграции ленты `notifygen init`:

```sql
-- +goose Up
DROP TABLE kaname.invite_mail_outbox;
DROP TABLE kaname.invite_mail_windows;
DROP TABLE kaname.source_request_windows;

CREATE TABLE kaname.mail_windows (
  purpose     text        NOT NULL CHECK (purpose IN ('recovery','verification','registration')),
  key_digest  bytea       NOT NULL CHECK (octet_length(key_digest) = 32),
  created_at  timestamptz NOT NULL,
  PRIMARY KEY (purpose, key_digest)
);

CREATE TABLE kaname.mail_window_letters (
  id              text        PRIMARY KEY,
  purpose         text        NOT NULL,
  key_digest      bytea       NOT NULL,
  kind            text        NOT NULL CHECK (kind IN ('progression','floor','trusted_device','throttled')),
  device_label_id text        NULL,
  at              timestamptz NOT NULL,
  feed_id         text        NOT NULL, -- строка ленты той же транзакции; без внешнего ключа (З11)
  -- RESTRICT, не CASCADE: снятие якоря с живым моментом отвергает база (З11, CX2-35)
  FOREIGN KEY (purpose, key_digest) REFERENCES kaname.mail_windows ON DELETE RESTRICT,
  CHECK ((kind = 'trusted_device') = (device_label_id IS NOT NULL))
);
CREATE INDEX mail_window_letters_window_idx ON kaname.mail_window_letters (purpose, key_digest, at);

CREATE TABLE kaname.pending_registrations (
  id             text        PRIMARY KEY,
  purpose        text        NOT NULL DEFAULT 'registration' CHECK (purpose = 'registration'),
  key_digest     bytea       NOT NULL,
  address_digest bytea       NOT NULL CHECK (octet_length(address_digest) = 32),
  password_hash  text        NOT NULL,                      -- случайная соль хешера; пароль учётки при подтверждении
  password_probe bytea       NOT NULL CHECK (octet_length(password_probe) = 32), -- argon2id с солью адреса (З14)
  code_digest    bytea       NOT NULL,
  created_at     timestamptz NOT NULL,
  expires_at     timestamptz NOT NULL CHECK (expires_at > created_at),
  FOREIGN KEY (purpose, key_digest) REFERENCES kaname.mail_windows ON DELETE RESTRICT,
  UNIQUE (address_digest, code_digest)
);
CREATE INDEX pending_registrations_address_idx ON kaname.pending_registrations (address_digest, expires_at);
CREATE INDEX pending_registrations_window_idx  ON kaname.pending_registrations (purpose, key_digest);

CREATE TABLE kaname.invite_acts (
  id          text        PRIMARY KEY,
  account_id  text        NOT NULL, -- без внешнего ключа: удаление аккаунта счёт не уменьшает (З24, CX2-21)
  kind        text        NOT NULL CHECK (kind IN ('invite','resend')),
  key_digest  bytea       NOT NULL CHECK (octet_length(key_digest) = 32),
  at          timestamptz NOT NULL,
  lettered    boolean     NOT NULL,
  feed_id     text        NULL,
  CHECK (lettered = (feed_id IS NOT NULL))
);
CREATE INDEX invite_acts_account_idx ON kaname.invite_acts (account_id, kind, at);
CREATE INDEX invite_acts_recipient_idx ON kaname.invite_acts (key_digest, at) WHERE lettered;
CREATE INDEX invite_acts_at_idx        ON kaname.invite_acts (at);             -- уборка по сроку З26

CREATE TABLE kaname.trusted_devices (
  id           text        PRIMARY KEY,
  user_id      text        NOT NULL REFERENCES kaname.users(id) ON DELETE CASCADE,
  label_digest bytea       NOT NULL UNIQUE,
  issued_at    timestamptz NOT NULL
);
CREATE INDEX trusted_devices_issued_idx ON kaname.trusted_devices (issued_at); -- уборка по сроку З18

CREATE TABLE kaname.security_notice_ledger (
  audit_event_id    text        NOT NULL,
  template          text        NOT NULL,
  recipient_user_id text        NOT NULL,
  created_at        timestamptz NOT NULL,
  PRIMARY KEY (audit_event_id, template, recipient_user_id)
);

ALTER TABLE kaname.recovery_codes           ADD COLUMN superseded_at timestamptz NULL;
ALTER TABLE kaname.email_verification_codes ADD COLUMN superseded_at timestamptz NULL;
CREATE UNIQUE INDEX recovery_codes_one_live
  ON kaname.recovery_codes (user_id) WHERE consumed_at IS NULL AND superseded_at IS NULL;
CREATE UNIQUE INDEX email_verification_codes_one_live
  ON kaname.email_verification_codes (user_id) WHERE consumed_at IS NULL AND superseded_at IS NULL;
```

Имена колонок `consumed_at` существующих таблиц кодов и имя таблицы ленты сверяются с деревом на
базе старта (миграцию пишет `migration-writer`, схему судит `db-architect-reviewer`); форма
инвариантов — обязательная. Строки существующих кодов перед созданием индекса: прода нет,
но стенды несут данные — миграция помечает `superseded_at = now()` у всех живых кодов, кроме
самого позднего на пользователя, одним оператором (единственное `now()` — в миграции, не в
запросе окна). `retired.json` дописывается тремя снятыми таблицами. Уборка — в реестре
`internal/apps/kaname/retention`: `mail_window_letters`, `invite_acts` и `trusted_devices` — сроком из
функции З26 над таблицей границ (не литералом); `pending_registrations` — `expires_at + 24 ч`;
`mail_windows` — когда у ключа нет ни моментов, ни записей, под блокировкой строки (З11);
`security_notice_ledger` — сроком хранения аудита. Порядок уборки внутри прохода — зависимые
строки, затем якоря; внешние ключи `RESTRICT` отвергают обратный порядок.

Край (`postgres` хранилища однократности): таблицы `anon_mail_passes (key text, at timestamptz)`
с индексом `(key, at)` и уборкой сроком из функции З26 над `anon_mail_bounds.go` (25 ч на
границах Р8); `pow_spent (id bytea PRIMARY KEY, expires_at timestamptz)` с уборкой по
`expires_at`; `anon_mail_bucket (id smallint PRIMARY KEY CHECK (id = 1), tokens double precision,
at timestamptz)` — единственная строка, заводимая миграцией хранилища (строка-якорь ведра, З8).
Ключи моментов края блокируются не строками, а `pg_advisory_xact_lock` по свёртке ключа (З8).

## 7. Последовательности

**П1. `recovery` (флаг `true`).** край: `ClientIP` → `Admit` (пропустить / вызов / `429`) →
ретрансляция → kaname: форма, `csrf` → `mail.Available()` → `200 {}` → диспетчер: tx { поиск учётки
по `Normalize(email)` → нет: конец (строки окна нет) → якорь `(recovery, key)`: вставка
`ON CONFLICT DO NOTHING`, затем `FOR UPDATE` →
моменты → `Decide` → код (тот же / новый) → `feed.Put` → момент `mail_window_letters` (+ журнал) } →
notify: сигнал → `Claim` → `ResolveSend(kaname, recovery, enqueued_at)` → `GetVerifiedAddress` →
отправка → `Ack SENT`.

**П2. `register`.** край: `Admit` → kaname: форма, пароль (отказ `400` о пароле) → флаг →
`200 {}` → диспетчер: чтение без блокировки { моменты → `Decide`; адрес занят? } → не пропущено:
конец (выводов нет) · свободен и пропущено: доля `register` (1 место) → `DeriveWait` × 2
{ `password_probe`, `password_hash` } без транзакции (срок истёк → `dropped_overload`, конец) →
tx { `LockAnchor (registration, key)` (вставка, `FOR UPDATE` = 1 строка, иначе повтор) → `Decide`
→ адрес занят? → письмо `registration-existing` : (проба совпала с живой записью → её код)
иначе (новая запись с выводами шага 2 + код) → `feed.Put` → момент `mail_window_letters` }.

**П3. `register/confirm`.** край: ретрансляция без ограничителя → kaname: страж попыток
(`register-confirm`) → живые записи по `address_digest` → код сравнивается со всеми записями
постоянным временем → одна свёртка пароля (запись совпавшего кода либо фиктивная) → tx { учётка (23505 →
`401`) · подтверждённый адрес · личный аккаунт · сессия · метка · удаление записей адреса } →
печенья.

**П4. `verify-email`.** kaname: сессия в положении подтверждения → флаг → tx { якорь (вставка,
затем `FOR UPDATE`) → `Decide` →
не пропущено: `429 TOO_MANY_ATTEMPTS` + `Retry-After` (строки нет) · пропущено: код → письмо }.

**П5. Класс S.** глагол → tx { строка события → `auditwrite.Insert` → карта (вид → шаблон →
правило) → снимок адресатов → по каждому: `security_notice_ledger ON CONFLICT DO NOTHING` →
вставлено? `Enqueue` } → коммит. Флаг `false` — строк ленты нет, событие есть.

**П6. Вход с нового устройства.** `login` → пароль верен → метки нет или недействительна → сессия
+ новая метка + событие `session.issued` с признаком «новое устройство» → `auditwrite.Insert` →
письмо `new-device-login`.

**П7. notify лежит.** строка ленты `pending` → уборщик NTF-1 по сроку: `EXPIRED(platform_unavailable)`
в своей tx → окно З11 считает этот момент исключённым с той же tx (`feed_id` момента и
предикат «лимит возвращён» corelib, Е8).

**П8. Флаг выключен.** старт: `notifications.enabled=false` → `mail.Enabled=false` → сервер ленты
не регистрируется, ключ журнала не объявляется, метрика `0` → глаголы П1–П4: отказ З3 до чтения
адреса; П5: событие без строк.

**П9. Хранилище края недоступно.** край: `ClientIP` → `Admit` → ошибка соединения, запроса или
`lock_timeout` → `StoreUnavailable` → `503` фиксированным текстом, счётчик +1; ретрансляции нет,
kaname запроса не видит.

## 8. Конфигурация, ручки и границы

**Ручки Р8** — 51 ключ, имена и границы — таблица Р8 приёмки; объявление границ — одна таблица на
дерево (З23). Здесь — только то, что добавляет или снимает замысел.

| ручка | владелец | граница / исход | читатель |
|---|---|---|---|
| `notifications.enabled` (kaname) | kaname | обязательна; `true`/`false`; отсутствие — отказ старта | корень kaname (З2) |
| `global.kacho.notifications.enabled`, `kaname.notifications.enabled` | зонтик (помощник NTF-1) | глобальное обязательно; переопределение по `hasKey` | помощник З4 |
| `KACHO_API_GATEWAY_TRUSTED_HOPS` | край | целое ≥ 0, без умолчания; задано в каждом профиле | `ContextExtractor` (З8) |
| `KACHO_API_GATEWAY_ANON_MAIL_POW_KEY_FILE` | край | путь к файлу секрета; ключ ≥ 32 байт; отсутствие — отказ старта | звено PoW (З9) |
| `authn.secrets.mail-window-key-file` | kaname | то же | окно, ожидающие регистрации (З11, З14) |
| `authn.secrets.device-label-key-file` | kaname | то же | метка устройства (З18) |
| `KACHO_IDEMPOTENCY_STORE` (+ DSN) | край (существующая) | `memory` законно только при флоте 1 — гейт пары | однократность и ограничитель (З8) |
| `invite.recipient-per-day-all` | kaname (Р8) | **добавочная** граница `≤ 50` (З19, Е3) | страж kaname |

**Снимаются** (ban #11, вместе с предметом): `invite-mail.*` (10), `invite.mail-rate-limit.*`,
`authn.login.verification-resend-{interval,limit,window}`, `authn.login.verification-code-attempts`,
`KACHO_API_GATEWAY_AUTHZ_TRUSTED_PROXY_COUNT`, `KACHO_API_GATEWAY_AUTHZ_TRUSTED_XFF`; переменные
`KANAME_INVITE_MAIL_*` в обеих поставках. Снятый ключ в файле или переменная с `__`, выводимая из
снятого ключа, — отказ старта (З5); плоские снятые имена уходят из поставок (З5, NTF2-30…32).

**Константы кода** (не ручки установки; у каждой — одно место и довод):

| величина | значение | место |
|---|---|---|
| срок вызова PoW | 5 мин | `gateway/internal/middleware/anonmail/pow.go` |
| ёмкость диспетчера постановки | 16; страж старта: действующий `max-conns` > 2 × 16 | `cmd/kaname/loginlane.go` (`mailDispatchInFlight`) |
| места диспетчера по классу работы | `recovery` 12 · `register` 4; сумма = `mailDispatchInFlight` (модульная проба) | `cmd/kaname/loginlane.go` (`recoveryDispatchPlaces`, `registerDispatchPlaces`) |
| предел одной постановки | 30 с | там же (существующая) |
| хранение ожидающих регистраций | `expires_at + 24 ч` | реестр `retention` |
| хранение моментов окон kaname и края, актов приглашения | функция З26: верхняя граница читающих окон + 1 ч (30 сут + 1 ч у `throttled`, 25 ч у прочих на границах Р8) | реестр `retention`; уборщик хранилища края |
| ожидание блокировки ключей ограничителя | 250 мс (`SET LOCAL lock_timeout`) | `gateway/internal/middleware/anonmail/store_pg.go` |
| бюджет решателя PoW в консоли | 4 мин по монотонным часам страницы; сверяется с файлом векторов | `ui-future/shared/src/lib/pow/` |
| повторы чеканки кода регистрации при совпадении | 3 | `pending_registration_repo.go` |
| выводов argon2id на работу `register` | 2 (`registerDerivations`): проба и хеш | `internal/apps/kaname/api/registration/register.go` |
| доля `register` в ёмкости проверяющего | 1 место (`registerDerivationShare`) | там же |
| пауза доли `register` после выводов | 1 × время, которое выводы держали место (`registerSharePause`); доля времени под выводами ≤ 1/2 | там же |
| попыток «вставка → `FOR UPDATE`» якоря окна | 3 (`anchorAttempts`) | `mail_window_repo.go` (`LockAnchor`) |
| классы рекомендательных блокировок (форма с двумя `int4`) | `anonMailLockClass` (край), `inviteRecipientLockClass` (kaname) — по одной константе на дерево | `anonmail/store_pg.go`; `invite_act_repo.go` |
| лимиты шаблонов kaname | таблица З19 | `notifications/*/notification.yaml` |

## 9. Рёбра

| ребро | вид | новое? | основание |
|---|---|---|---|
| notify → kaname (`Subscribe`, `Claim`/`Ack` ленты kaname) | runtime, gRPC, внутренний слушатель | новое для kaname-источника; форма — NTF-1 | Р1 |
| notify → kaname (`ResolveSend`) | то же | форма NTF-1; для `kaname` — З21 (Е1) | Р14 |
| notify → kaname (`InternalNotificationRecipientService`) | то же | **новое** | З20 |
| край → kaname (`register/confirm`) | runtime, HTTP ретрансляция полосы формы | новый путь существующего ребра | Р9 |
| край → хранилище края | runtime, база края; отказ — `StoreUnavailable` → `503`, fail-closed (З8) | существующее (однократность), новые таблицы | З8, З9 |
| kacho → kaname | сборка, пин (шаблоны kaname в `notify bundle`) | существующее направление | Р3 |
| kaname → notify | — | **нет ни одного вызова** | ацикличность |

## 10. План перехода

Прода нет: без второго пути. Порядок посадки задаёт `tasks.md`; здесь — что меняется в поведении
на каждом шаге и почему окна без защиты нет.

1. **NTF-1 в стволе** (Р16 п.1) и правка NTF-1 по Е1–Е2 одобрена и влита.
2. **kaname — одним изменением** (линия `kaname#484`): постановка через ленту, окна, коды,
   регистрация, класс S, справочник, конфигурация, снятие почты и очереди, гейт NTF2-44 вместо
   MAIL-47. До его посадки письма kaname идут прежним отправителем; после — только через ленту.
3. **kacho — одним изменением** (линия `kacho#2917`): пин kaname на изменение п.2, ограничитель и
   PoW края с одной ручкой прыжков, путь `register/confirm`, флаг и строка источника kaname в
   зонтике, снятие полосы kaname и почты поставщика из чарта, гейты рендера §3а, консоль.
   Ретрансляция `register/confirm` и ограничитель садятся тем же изменением, что пин: kaname,
   ждущая `register/confirm`, без пути на краю не посажена ни в одной цепочке.
4. Стенд `dev` поднимается с флагом `true`; сквозные пробы.
5. Трекер, документы, записки (DoD пп.21–24).

Откат — пин kaname назад и откат чарта; миграция снятия таблиц необратима по данным (строки
очереди и окон не восстанавливаются), что допустимо без прода.

## 11. Отображение пунктов разбора в решения

Каждый пункт первичного разбора на `9098d6ef` → решение → механизм → держатель.

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX2-01 | З2, З4 | `*bool` + `IsSet`; `hasKey` без `default`/`or`/`if`; один помощник | NTF2-50, 53; вариант рендера «глобальный `false`, модуль `true`» |
| CX2-02 | З1, З2 | флаг читается корнем; решение о строке — только `Enqueue`; `mail.Available()` до чтения адреса | NTF2-51, 52 |
| CX2-03 | З5 | `UnmarshalExact`; строгость окружения в выводимом пространстве `__` (множество — прямой вывод `EnvNameOfKey` по ключам декодера); плоские имена четырёх механизмов не судятся — довод М2а, М2б; ключи без умолчания — `BindEnv` из таблицы границ; перемер профилей | NTF2-48; проба переменной с `__`; близнец с плоскими именами поставок; проба привязки |
| CX2-04 | З6 | порядок снятия; гейт NTF2-44 тем же коммитом; пара «очереди нет — ленты есть» | NTF2-44, 45; DoD п.17 |
| CX2-05 | З16 | `auditwrite.Insert` — единственная форма прод-дерева Go; посев через неё — писатель аудита параметром `RunBootstrapAdmin`, литерала в `seed` нет (условие пересверки на редакцию 2); миграции пишут след SQL-ом по норме соседа и писем не ставят (довод М6а); число миграционных форм — двусторонний храповик 3 | гейт `audit_outbox_single_writer` (два обхода, `seed` в перечне осмотренных, инъекция литерала в посев); проба посева; NTF2-90 |
| CX2-06 | З16 | `security_notice_ledger` PK + `ON CONFLICT DO NOTHING`; строка в tx события | NTF2-97 |
| CX2-07 | З16 | снимок из `accounts.owner_user_id` и `cluster_admin_grants` в tx; пустое множество — метка `unaddressed` закрытого набора, зарегистрированная при старте, и правило тревоги в чарте обеих поставок (отступление от (в), принятое пересверкой с условием) | NTF2-90, 93, 96; проба «событие без адресата → глагол исполнен, метрика +1» |
| CX2-08 | З20 | отношение `reader` на `notification_feed:kaname`; `Check` первым стейтментом после проверки формы в теле каждого метода (внутренний слушатель без перехватчика); закрытый перечень; `DenyDetailUnary`; ребро записано | NTF2-88; каталог; ban6; проба отказа при снятой аннотации |
| CX2-09 | З4 | строка источника: имя, модуль, адрес — три поля; край не участвует | гейт строки источника; NTF2-53 |
| CX2-10 | З4 | пустой перечень — notify не рендерится, пустой на старте — отказ (NTF-1 Р6, Р9) | NTF-1 (перечень источников) |
| CX2-11 | З8, З9 | решение и момент — одна транзакция; ключ без строк сериализуется `pg_advisory_xact_lock(class, obj)` формы с двумя `int4` по отсортированным парам (`memory` — полосатые мьютексы в том же порядке); пространство ключей не пересекается со схемной блокировкой края одним `bigint` (условие пересверки на редакцию 2, М30); ведро — строка-якорь последней; хранилище однократности; гейт пары | NTF2-60, 62; integration-проба гонки нового ключа; integration-проба пространства ключей с близнецом-инъекцией; гейт формы блокировки; гейт пары |
| CX2-12 | З8 | `ClientIP`; `TRUSTED_HOPS` замещает две ручки; число прыжков — обязательный параметр конструктора, умолчание `1` снято | NTF2-71 (е), 79; проба «адрес края = адрес в kaname»; проба конструктора |
| CX2-13 | З9, З18 | три ключа — файлы секрета; отказ старта; поведение при смене объявлено | проба отказа старта на каждый ключ |
| CX2-14 | З11–З14 | якорь: вставка `ON CONFLICT DO NOTHING`, затем `FOR UPDATE`; частичный `UNIQUE` живого кода; запись в той же tx | integration-проба гонки первых запросов на новом ключе |
| CX2-15 | З11 | `Decide` — чистая функция, закрытые исходы; моменты по видам | табличная проба `Decide` |
| CX2-16 | З12 | `now` — параметр во всех запросах предмета | гейт `mail_clock_parameter`; П6 |
| CX2-17 | З13 | одна tx внутри работы; отброшенное окна не тратит; константа 16 + gauge; страж старта «действующий `max-conns` > 2 × ёмкости» | NTF2-67; проба `dropped_overload`; проба стража (32 / 33) |
| CX2-18 | З15 | `AttemptGuard` с параметром пути; вызывающих 3 | NTF2-66; вариант на `verify-email/confirm` |
| CX2-19 | З14 | уборка `expires_at + 24 ч`; удаление записей адреса при заведении учётки; `23505` → `401` | NTF2-83, 84, 86; проба уборки |
| CX2-20 | З11, З15, З25 | одна нормализация `address.Normalize`; две именованные производные `mailkey.Account` / `mailkey.Abuse` от `address.Normalized`; `humansession.AddressKey` снята, 11 вызовов ключа → `Account`, значение записи кода — хранимый адрес; неразбираемый адрес — отказ формата у постановки и `401` у предъявления; писатели `users.email` берут `address.Normalized` | проба `mailkey`; проба дерева `AddressKey` → 0; гейт `people_address_writers` |
| CX2-21 | З24, §6 | потолки считают акты `invite_acts` (`invite` и `resend`), а не строки `users`; у `invite_acts` нет внешних ключей ни на `users`, ни на `accounts` — ни удаление приглашения, ни удаление аккаунта счёт не уменьшают, строка уходит только по сроку З26 (отказ пересверки на редакцию 2); `pending-max` — по состоянию строк `users`; блокировки: строка аккаунта, затем рекомендательная формы с двумя `int4` по ключу адресата | NTF2-69, 77; integration-проба параллельных приглашений; пробы повторной отправки и удаления приглашения; integration-проба «удаление аккаунта не возвращает `recipient-per-day-all`» с близнецом; проба схемы «внешних ключей 0» |
| CX2-22 | З23 | одна таблица границ на дерево; гейт двух поставок | NTF2-71, 33; гейт поставок |
| CX2-23 | З19 | помощник `kanameDailySum` со слагаемыми | NTF2-73 |
| CX2-24 | З18 | метка привязана к субъекту; запас по паре; без продления | NTF2-70, 78, 94; вариант «чужой адрес» |
| CX2-25 | З16 | политика не роняет глагол; сбой хранилища — вся tx | NTF2-90; проба «сбой вставки ленты → событие не зафиксировано» |
| CX2-26 | З22 | листья, а не ключи; проецируемый том и «неизвестная форма» | NTF2-21, 23, 30, 31; вариант проецируемого тома |
| CX2-27 | З17 | журнал через порт `feed.Put` в той же tx; `state_unavailable` | проба отката |

Пункты пересверки на редакцию 1 (`reviews/class-exposure/revalidation/f21384ed….yaml`):

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX2-28 | З8, З9 | закрытые исходы `Admit` и одноразовости со своим `StoreUnavailable` → `503` фиксированным текстом, счётчик; `lock_timeout` 250 мс; ведро последним и на время решения | модульная проба «хранилище недоступно → `503`, полоса формы не вызвана, счётчик +1» и близнец; проба `lock_timeout` |
| CX2-29 | З26 | срок хранения — функция верхней границы читающих окон из таблицы границ стража + 1 ч (30 сут + 1 ч у `throttled`) | модульная проба над таблицами границ обоих деревьев с инъекцией литерала; NTF2-68 (б) с уборкой, сдвинутой на срок |
| CX2-30 | З10 | `Worker` одной отправки: завершение при размонтировании, новой отправке и исчерпании бюджета 4 мин; `expired` — свой исход; общий файл векторов хеша и сроков для Go и TS | пробы `submit` на управляемых часах; проба решателя и проба края по общим векторам |
| CX2-31 | З20, §5 | `oneof result { address; not_eligible }` вместо перечисления с нулём; сервер: ровно один вариант, адрес непуст; читатель notify: незаданный вариант и пустой адрес — ошибка протокола (Е8) | модульная проба сервера; проба читателя — заказ NTF-1 |
| CX2-32 | З11, §6 | `feed_id NOT NULL` без внешнего ключа, момент пишется только после `feed.Put` своей tx; удалённая строка ленты — момент считается; предикат «лимит возвращён» — экспорт corelib (Е8) | проба «вставка с пустым `feed_id` — ошибка базы»; проба удалённой строки ленты; NTF2-07 |
| CX2-33 | З14 | код однозначно указывает запись адреса (`UNIQUE (address_digest, code_digest)`); код сравнивается со всеми записями постоянным временем, пароль — один раз (запись совпавшего кода либо фиктивная свёртка той же цены); сторона `register` — CX2-34 | проба «вызовов свёртки на `confirm` = 1 при 0, 1, 44 записях»; integration-проба совпавшего кода |

Пункты пересверки на редакцию 2 (`reviews/class-exposure/revalidation/2886b89f….yaml`):

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX2-34 | З14, З13, §6 | (а) срок ожидания места истёк → работа кончается до транзакции: записей, моментов, писем 0, исход `dropped_overload`; (б) выводы ждут место (`DeriveWait` поверх `acquireWait`) в сроке работы и не занимают больше одного места проверяющего на все работы `register` (доля `registerDerivationShare = 1`); вход и церемония — прежним захватом; цена для `c = 1` названа; (в) «тот же пароль» узнаётся пробой `password_probe` (argon2id с солью адреса под ключом службы) — 0 или 2 вывода на работу при любом числе записей; выводы — между чтением без блокировки и транзакцией решения, без блокировки якоря и без соединения пула; сравнение проб под блокировкой — байтовое | проба голодания (16 работ × 44 записи при ёмкости 2 → вход `matched`, мест под `register` ≤ 1) с близнецом без доли; проба исхода; проба числа выводов (0 / 2 при 0, 1, 44 записях); проба места выводов; integration-проба записи, появившейся между шагами |
| CX2-35 | З11, З18, З26, §6 | (а) якорь снимается уборкой, когда у ключа нет ни моментов, ни записей, — пачкой `FOR UPDATE SKIP LOCKED` и `DELETE … WHERE NOT EXISTS` под блокировкой строки; внешние ключи зависимых строк — `RESTRICT`; метка устройства — по `issued_at` сроком функции З26 (365 сут + 1 ч на границе); закрытый перечень предметов хранения; (б) `LockAnchor`: `FOR UPDATE` обязан вернуть одну строку, иначе повтор вставки (`anchorAttempts = 3`), затем ошибка хранилища; одна функция для всех работ окна | integration-проба «уборка между вставкой и `FOR UPDATE` → повтор, одна строка ленты» (в) с близнецом; проба уборки якоря (без зависимых — снят, с моментом или записью — нет, занятый — пропущен); проба базы «`DELETE` якоря с моментом отвергнут»; проба уборки меток; проба закрытого перечня предметов хранения |

Пункт пересверки на редакцию 3 (`reviews/class-exposure/revalidation/c3e37381….yaml`):

| пункт | решение | механизм | держатель |
|---|---|---|---|
| CX2-36 | З13, З14 | (а) места диспетчера разделены по классу работы: `recovery` 12, `register` 4, сумма — прежние 16 (страж пула и И22 не меняются); работа класса, чьи места заняты, — `dropped_overload` своего глагола, чужих мест не берёт, поэтому ожидающие долю `register` не вытесняют `recovery` ни при каком потоке; (б) доля `register` освобождается после паузы, равной времени, которое выводы держали место проверяющего (`registerSharePause = 1`, монотонные часы параметром; пауза держит только место доли, не работу и не место диспетчера) — место проверяющего занято выводами `register` не больше 1/2 времени при любом потоке, в том числе на границе края (20 rps, выше — PoW, а не отказ): на `c = 1` вход получает свободное место не меньше половины времени (без паузы — 0), на `c = 2` при занятой доле церемонии — то же, на `c = 8` — не меньше 3 мест всё время; цена — пропускная способность `register` одна работа на `4d`, насыщение при `d` > 12,5 мс; (в) — пробы | проба классов мест (16 работ `register` при удержанной доле → 4 ждут, 12 `dropped_overload{register}`, затем `recovery` исполнена) с близнецом «один счётчик на 16» → `recovery` `dropped_overload` — красный; проба доли времени на управляемых часах при `c = 1` (≤ 1/2 на `100 d`, вход в паузе `matched`) с близнецом `registerSharePause = 0` (≥ 0,99, вход — отказ по ёмкости); проба паузы без работы; модульная проба констант (12 + 4 = 16, инъекция 12 + 5 — красный) |

Неотображённых пунктов нет: 36 из 36 (27 первичного разбора, 6 пересверки на редакцию 1, 2 пересверки на редакцию 2, 1 пересверки на редакцию 3).

## 12. Что замысел не делает

- Не меняет схему ленты, `SendX`, сервер ленты, `ResolveSend`, notify и его чарт — NTF-1.
- Не заводит глагол смены адреса (Р13) и контакты по категориям (NTF-3).
- Не заводит ручек сверх названных в §8; ёмкость диспетчера и срок вызова PoW — константы.
- Не держит второй нормализации ящика: `mailkey` — две именованные производные от
  `address.Normalized`, своего разбора и IDNA у kaname нет; `humansession.AddressKey` снята.
- Не сводит плоские переменные окружения kaname к одному объявлению: четыре механизма их
  чтения остаются, строгость окружения — только в выводимом пространстве `__` (З5).
- Не ставит писем из миграций (З16).
- Не меняет захват места входом и церемонией: ожидание места и пауза доли — только у выводов `register` (З14).
- Не оставляет предел kaname по источнику на анонимных почтовых глаголах (З7).

## 13. Открытые решения

Нет. Решения З1–З26 приняты. Внешние зависимости — предметы соседних приёмок с названным
предикатом снятия, а не открытые решения этого замысла:

| № | зависимость | чей предмет | предикат снятия |
|---|---|---|---|
| Е1 | NTF-1 приведена к Д2: `service:kaname` и строка `sender` для kaname; `ResolveSend` зовётся и для `kaname`; исключение «сертификат вместо `ResolveSend`» снято (Р3, §1.5, NTF1-F21, NTF1-G22 — на `d524e7bd`, `4d042803`, `b92f0c2b` и `05828e42` не снято) — либо, при ответе владельца «прочтение Д2 по смыслу», правка NTF-2 (§0.1) | приёмка NTF-1 (или NTF-2 — по ответу владельца) | запись `APPROVED` на отпечаток NTF-1, где NTF1-F21 утверждает ровно одну строку `service:kaname sender notification_namespace:kaname` |
| Е2 | один текст и `reason` отказа флага в NTF-1 и NTF-2 (К2) | приёмка NTF-1 (рекомендация) либо NTF-2 | `grep -c 'NOTIFICATION_DELIVERY_NOT_CONFIGURED' docs/specs/sub-phase-NTF-1-*.md` → 0 на одобренном отпечатке, либо обратное для NTF-2 |
| Е3 | граница `invite.recipient-per-day-all ≤ 50` в таблице Р8 и вариант NTF2-71 на неё | приёмка NTF-2 | строка границы в Р8 на одобренном отпечатке |
| Е4 | замещение окна обращений по источнику kaname#456 названо в §3 NTF-2 и строкой в шапке приёмки kaname | приёмка NTF-2 (§3), DoD п.23 | строка §3 на одобренном отпечатке |
| Е5 | NTF-1 в стволе kacho и в пине corelib обоих деревьев (Р16 п.1) | NTF-1 | команды Р16 п.1 на базе старта |
| Е6, Е7 | событие одобрения приёмки NTF-2 и `DESIGN_APPROVED` — зависимости маршрута, а не замысла | `tasks.md` §1 | там же |
| Е8 | условия к коду NTF-1, которых требует этот замысел и которые не меняют ни одного «Тогда»: (а) `corelib notify/feed` экспортирует предикат «лимит строки возвращён» (фрагмент запроса над строкой ленты), чтобы kaname не писала литерал исхода (З11, CX2-32); (б) классификатор ответа справочника адресов в notify трактует незаданный `result` и пустой `address` как ошибку протокола, а не `DENIED(recipient)` (З20, CX2-31) | замысел и маршрут NTF-1 (`docs/changes/issue-2915`) | экспорт предиката есть в corelib на пине старта; проба читателя notify на незаданный вариант — в держателях пакета NTF-1 |
| Е9 | исход «хранилище ограничителя недоступно» (`503`, `code` `14`, фиксированный текст, одинаковый для любого адреса, до kaname запрос не доходит, З8, П9) — сценарий с положительным близнецом «хранилище исправно → пропуск» в рядах ограничителя NTF2-60…63, 74; поведение консоли на `503` и на исход `expired` решателя (З10) в NTF2-72 | приёмка NTF-2 | сценарий `503` с близнецом и строка консоли на одобренном отпечатке NTF-2 |
