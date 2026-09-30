<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2924 (NTF-5, извещения оператора) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md` рядом: полосы,
> исполнитель по базе маршрутизации, пути, предикат снятия, зависимости, размер. Это не трекер:
> состояние полос живёт в задаче `PRO-Robotech/kacho#2924` и её подзадачах
> (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 1 · 2026-09-30 — проект маршрута к замыслу редакции 1.** Состояние `TASKS_READY`
> этот файл не объявляет: по §5 SDD-1 оно наступает только после `DESIGN_APPROVED` и проверенного
> writing-plans handoff, который производит `tasks.md`. Handoff либо подтверждает этот файл без
> правки, либо переписывает его; в обоих случаях действует текст на отпечатке, названном записью
> handoff.

## 0. Правила маршрута

- **Порядок:** фундамент → контракты → служба доступа → служба `notify` → край → развёртывание →
  гейты → воркспейс. Полоса стартует, когда сняты её зависимости; полосы одного яруса без общих
  путей идут параллельно.
- **Проба до кода** в каждой полосе исполнителя кода: сначала проба, красная на текущем дереве с
  напечатанным исходом, затем код, затем та же проба зелёная — одним изменением (ban #12). Красное
  фиксируется до кода: это свидетельство `RED_PROVEN` полосы. Имя каждой пробы несёт ID сценария
  (DoD 10.1 п.6, 10.2 п.7).
- **Стадии гейтятся производителями** (приёмка §5): S1 — после Е1, Е3, Е4, Е5 и тегов T1, TW; S2 — после
  S1, Е2 и тега T2; S3 — после S2.
- **Теги и пины — порядок `design.md` §10.** Тег TW выпускается последним перед посадкой S1, и
  между его выпуском и посадкой S1 пин kacho не поднимает никто, кроме полосы S1.
- **Единица сдачи** — коммит исполнителя в ветке полосы; сведение волны, запрос на слияние,
  вливание и снятие веток — `git-operator` по решению диспетчера.
- Размер: **S** — до дня одного исполнителя, **M** — два-три, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход; «зелёный» — с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е1 | служба `notify`, конвейер, `feed.Put`, сервер ленты (NTF-1) посажены | приёмка ✅ `29cfa368`; кода нет | `git -C project/kacho ls-tree origin/main services/` — `notify` нет |
| Е2 | справочник `Resolve`, контакты аккаунта, настройки и каталог (NTF-3) посажены | приёмка ✅ `c26cc7cc`; кода нет | то же; `git grep -c InternalNotificationRecipientService 734f69fb4 -- proto` в kaname → 0 |
| Е3 | NTF-4 редакции по Д20 (2) одобрена | записи ревью на `5cb8057d` нет | `ls docs/specs/reviews/sub-phase-NTF-4-delivery-feedback-reputation-acceptance/` |
| Е4 | край NTF-4 Р20: `notifyInternal`, строка `nop`, поле адреса без умолчания, ключ `notify` в форме псевдонима (design.md З18) | кода нет | пробы NTF4-93, 94 на стволе |
| Е5 | теги corelib Х5, Х1 (NTF-4) | не выпущены | `git -C project/corelib tag` |

## 2. Полосы

### Ярус 0 — фундамент (corelib)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| C1 | префикс `ntc` (Р3) | `go-implementer` | corelib · `ids/ids.go`, проба `ids` | `go test ./ids/ -run 'Ntc\|HyphenPrefix' -count=1 -v` зелёный с числом исполненного; `ids.ValidateResourceID("ntc-0123456789abcdefg")` проходит, на `34bc8104a` — отказ (красное до кода) | — | S |
| C2 | Ф1…Ф4, `TxWriter`, `TxRepo`, `NewRepo → TxRepo`, `ErrNilTx`, `ErrEmptyPrincipal`; проба NTF5-122 (а)–(к) с буквой «`nil` вместо транзакции → ошибка, строк 0» и близнецом; перепись входов DoD 10.1 п.2а (б); гейт замыкания (design.md З2 п.7) | `go-implementer` (проба — `integration-tester` до кода) | corelib · `operations/{repo.go,txwriter.go,txwriter_integration_test.go,txwriter_closure_test.go,storage_inputs_test.go}` | `go test -tags integration ./operations/ -run NTF5_122 -count=1 -v` зелёный, (ж), (к) — 20 повторов; перепись печатает «функций, возвращающих хранилище, 1; методов 17»; гейт замыкания печатает число функций и красный на инъекции чтения `defaultRegistry` в `markErrorCAS` (вывод приложен); `git grep -nE '^func \([a-z]+ \*?pgRepo\) [A-Z][A-Za-z]*\([^)]*pgx\.Tx' -- operations/ \| wc -l` → 4; `git diff 34bc8104a -- operations/repo.go` не меняет тела `markDoneCAS`/`markErrorCAS`; сборка kaname на теге-кандидате зелёная (`go build ./...` с `replace` на ветку C2) | — | M |
| C3 | тег T1 (C1 + C2) | `git-operator` | corelib · тег | тег выпущен; `go build ./...` kacho и kaname с пином на T1 зелёные | C1, C2 | S |
| C4 | запись окна политики `notify KACHO_NOTIFY_LIST_FILTER_CACHE_TTL = 5s`, тег TW **последним перед посадкой S1** | `go-implementer` → `git-operator` | corelib · `authz/revocation_policy.go` | проба политики corelib зелёная; тег TW выпущен после T1, Х5, Х1 (`git tag --contains` каждого) | C3, Е5, готовность N-полос S1 | S |
| C5 | класс `obligation` в `notify/spec` (Р12, владелец — ключ ведомости, З10 п.1); `feed`: `expires_at NULL` + `CHECK`, `*time.Time`, `thread_key` и исключение взятия, `Supersede`, `DeleteTerminal`; перепись читателей срока (З10 п.3) | `go-implementer` | corelib · `notify/spec`, `notify/feed` | модульные пробы NTF5-55, 56, 117 и инъекция вложенного каталога — зелёные; интеграционные пробы `feed` (`Supersede` не трогает арендованную; `DeleteTerminal` не трогает нетерминальную; строка `obligation` без срока не истекает; строка `notice` без срока невыразима — `23514`) — зелёные; перепись `git grep -nE 'expires_at\|ExpiresAt' -- notify/` с числом попаданий и таблицей «читатель → ветка `NULL`» в описании PR | Е1 | M |
| C6 | тег T2 (C5), **после TW** | `git-operator` | corelib · тег | тег выпущен; `git tag --contains <TW>` включает T2 | C5, C4 | S |

### Ярус 1 — контракты

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| P1 | `notice.proto`, `notice_service.proto`, `internal_notice_service.proto` с аннотациями Р16, Р18; комментарии полей (design.md §5); строки перечня четырёх методов `NoticeService` — **тем же коммитом**, вместе с blank-импортом пакета `notify` в `parity_test.go`, если его нет, и строками всех публичных сервисов `notify`, уже лежащих в дереве (З18 п.5) | `proto-sync` (строки перечня — `api-gateway-registrar` в той же ветке) | kacho · `proto/kacho/cloud/notify/v1/`, `pkg/api/…`, `gateway/internal/allowlist/{list.go,parity_test.go}` | `buf lint`, `buf breaking` зелёные; регенерация закоммичена; `go test ./gateway/internal/allowlist/ -count=1 -v` — четыре пробы зелёные, перепись печатает сервисы и методы `notify`; инъекции DoD 10.1 п.4 — снятая строка `NoticeService/GetByAccount`, строка `InternalNoticeService/Create`, снятый импорт — красные с именем | Е1 | M |
| P2 | контакты: поля `account_legal`, `operations`, `source = ACCOUNT`, `ProjectNotificationContactsService`; вид `OPERATOR_NOTICE`; строки перечня `Get`/`Update` контактов проекта — тем же коммитом | `proto-sync` (+ `api-gateway-registrar`) | kacho · `proto/kacho/cloud/notify/v1/`, `gateway/internal/allowlist/` | то же; снятая строка `ProjectNotificationContactsService/Update` — красный с именем метода | P1, Е2 | S |
| P3 | kaname: `DescribeScope` (`optional bool exists`), `ListAccounts` (комментарий о курсоре, З23 п.3) в сервисе справочника | `proto-sync` | kaname · `proto/kaname/cloud/iam/v1/` | `buf lint`, `buf breaking` зелёные | Е2 (сервис справочника NTF-3) | S |

### Ярус 2 — служба доступа (kaname)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| K1 | `DescribeScope`: вход и отказы первым оператором, одна выборка; перечень методов звена; каталог прав `reader` | `rpc-implementer` (проба NTF5-68 (а)–(ж) и ветка `user:usr-op` — `integration-tester` до кода) | kaname · use-case справочника, перечень звена, каталог прав | интеграционная проба NTF5-68 (а)–(ж) против самой службы доступа зелёная, три сертификата; PR в `PRO-Robotech/kaname` | P3 | M |
| K2 | `ListAccounts`: keyset без сужения, кодек `kv1.`, отказы первым оператором | `rpc-implementer` (проба — `integration-tester`) | kaname · тот же use-case | NTF5-68 (з)–(к) зелёная над 5 посеянными аккаунтами, включая посеянный миграцией | K1 | S |
| K3 | триггеры неизменяемости `owner_user_id` и `account_id` проекта (З23 п.4) | `migration-writer` (проба — `integration-tester`) | kaname · `internal/migrations/<новая>.sql` | интеграционная проба: смена значения → `23514`, правка `name` проходит; `db-architect-reviewer` ✅ | — | S |

### Ярус 3 — служба `notify` (S1)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| N0 | честный красный S1: пробы NTF5-01..54, 86..92, 109, 110, 118..122 в обвязке §6 приёмки | `integration-tester` | kacho · `services/notify/…_integration_test.go` | прогон печатает число красных по каждому ID; красное — по отсутствию предмета, не по поломке обвязки; `landing-reviewer` на сыром красном | Е1, C3 | M |
| N1 | миграции S1: заявки, извещения, аудитория, ссылки, напоминания, события этапа, кэш областей, счётчики (design.md §6) | `migration-writer` | kacho · `services/notify/internal/migrations/` | миграции применяются на пустой базе; `db-architect-reviewer` ✅; `CHECK` с именами (З5 п.5) | Е1 | M |
| N2 | `notify-api`: `InternalNoticeService` (`Create` приём, `Get`, `List`, переходы, `Update`), `NoticeService` (четыре чтения), `authzcheck.RequireScope`, `authzwiring.NewListNarrower`, регистрация на носителе Х5 | `rpc-implementer` | kacho · `services/notify/internal/apps/notify/api/{notice,publicnotice}`, `…/authzcheck`, `…/authzwiring`, корень `notify-api` | пробы N0 своих ID зелёные; NTF5-33 — 20 повторов; `git grep -c 'listnarrow\.New(' -- 'services/notify/*.go' ':!*_test.go'` → 1, по `'*_test.go'` → 0; `git grep -nE 'INSERT INTO [a-z_.]*operations\|UPDATE [a-z_.]*operations' -- 'services/notify/*.go' \| wc -l` → 0 | N1, C3, Е5 | L |
| N3 | `notify-sender`: `admit` (аренда, `ops.Get`, шаги 2–6, окно), классификатор `DescribeScope`/`ListAccounts` (модульная проба на все коды и «`OK` без поля», противоречивые ответы — CX5-08, 09), клиент `kaname_client.go` | `go-implementer` | kacho · `services/notify/internal/notice/admit`, `…/clients/kaname_client.go`, корень `notify-sender` | NTF5-17, 18 (а)–(е), 118, 119 зелёные (119 — 20 повторов); модульная проба классификатора печатает 17 строк | N1, K1 | M |
| N4 | `schedule` (правило напоминаний — `rules`), `sweeper` (З24), `metrics` (З21), `rules` (таблицы Р4, Р5, 18 типов), конфигурация и стражи обоих корней (З20) | `go-implementer` | kacho · `services/notify/internal/notice/{schedule,sweeper,metrics,rules}`, `services/notify/internal/config` | NTF5-34, 50, 51, 52, 53, 54 (на обоих корнях), 72, 92 зелёные; NTF5-54 (д) берёт `Ceiling + 1s`; проба «маска только `endsAt` раньше хранимого `startsAt`» (CX5-04) зелёная; `git grep -nE 'operations\.NewReconciler\(' -- 'services/notify/*.go' ':!*_test.go' \| wc -l` → 0 | N1 | M |
| N5 | окно сужателя в переписи гейта — **один коммит** с подъёмом пина на TW: ручка с умолчанием `5s`, каталог в `revocationScanRoots`, ручка в `knobNames` | `go-implementer` | kacho · `services/notify/internal/config`, `internal/repohygiene/revocationwindow_test.go`, `tools/revocationwindowgate/gate.go`, `go.mod` | `go test ./internal/repohygiene/ -run 'RevocationWindow\|AuthzWindowKnob\|VerdictCacheService\|KnobShape' -count=1 -v` зелёный; перепись печатает площадок и записей на 1 больше, чем на стволе; инъекции (а)–(д) DoD 10.1 п.10 — каждая красная с именем процесса и ручки | N2, C4 | S |

### Ярус 3 — служба `notify` (S2)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| N6 | честный красный S2: NTF5-55..83, 93..108, 111..117 | `integration-tester` | kacho · `services/notify/…_integration_test.go` | как N0 | S1 посажена, Е2 | M |
| N7 | миграции S2: адресаты, кандидаты, исходы областей, окно и ведро OB; таблица контактов в форме З15 п.1 | `migration-writer` | kacho · `services/notify/internal/migrations/` | `db-architect-reviewer` ✅ | N6 | M |
| N8 | контакты: поля категорий ресурса аккаунта, ресурс проекта, `RequireScope`, отображение `Check` о назначаемом | `rpc-implementer` | kacho · `services/notify/internal/apps/notify/api/contacts/{account,project}` | NTF5-96..106 зелёные (106 — 20 повторов) | N7, P2 | M |
| N9 | раскрытие: цепочка кандидатов, `Resolve`, две таблицы строк, повтор кандидата, исходы областей, `ListAccounts` постранично, кэш областей, порядок блокировок З6 | `go-implementer` | kacho · `services/notify/internal/notice/{fanout,scopecache}` | NTF5-58..67, 93..95, 107, 111 зелёные (65, 107 — 20 повторов; 111 — два порядка × 20); пробы заказа разбора зелёные: «переход во время приостановленного раскрытия — строк по закрытому событию нет», «`dueAt` × `Start`» (20 повторов), «кандидат не берётся конвейером; повтор с `ADDRESS` при существующем адресате снимает кандидата», «повтор страницы не удваивает `unaddressed_total`» | N7, K2, C6 | L |
| N10 | переходы S2: закрытие строк `SUPERSEDED` по таблице Р5 (`feed.Supersede`); лимиты OB (окно, ведро); нить (`thread_key`, `thread.Headers`); наблюдатель исхода; правило класса `obligation` в фильтре подавления | `go-implementer` | kacho · `services/notify/internal/notice/{limits,thread}`, `…/api/notice/{start,complete,cancel,update}`, конвейер `notify` (порты) | NTF5-69..77, 80..83, 108, 112..116 зелёные; NTF5-82, 83 — при **двух** репликах `notify-sender`; проба «два письма одной пары в полёте — один корень» зелёная | N9 | L |
| N11 | 19 шаблонов `notice-<kind>-<stage>` ×`{ru, en}`, эталоны `.eml` и превью; вид `OPERATOR_NOTICE` в таблице сборки, правило «`obligation` → `ALWAYS`» | `go-implementer` | kacho · `services/notify/notifications/notice-*`, таблица видов сборки (NTF-3) | `make -C services/notify bundle-check` зелёный; NTF5-57, 78, 79 зелёные | C6, P2 | M |

### Ярус 4 — край

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| E1 | REST-маршруты `InternalNoticeService` (внутренний mux) и `NoticeService` (публичный mux) по `notifyInternal`; каталог прав (Р16, Р18); псевдоним `notify → notifyInternal`, если Е4 его ещё не завёл (предикат, а не авторство); `TestRouteWiring_NotifyKeysShareOneConnection` с близнецом `vpc`; явная установка `notify` в `realBackends` и `TestRouteWiring_NoNotifyAddressNoNotifyKeys` (З18 п.3, п.4) | `api-gateway-registrar` | kacho · `gateway/internal/restmux/mux.go`, каталог прав, `gateway/cmd/api-gateway/{mtls_config.go,route_wiring_parity_test.go}` | `go test ./gateway/cmd/api-gateway/ -run RouteWiring -count=1 -v` — шесть проб зелёные; `go test ./gateway/internal/allowlist/ -v` зелёный; перепись «публичный сервис `notify` → строк перечня» напечатана на ревизии посадки; полю адреса `notify` умолчания нет (`git grep -nE 'NOTIFY[A-Z_]*GRPC.*default:' -- gateway/internal/config/config.go \| wc -l` → 0) | P1, Е4 | M |
| E2 | маршруты `/notify/v1/projects/{projectId}/contacts`, каталог прав `<exempt>` без пола | `api-gateway-registrar` | kacho · `gateway/internal/restmux/mux.go`, каталог прав | те же пробы зелёные; NTF5-102 зелёная | P2, E1 | S |

### Ярус 5 — развёртывание и гейты

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| D1 | запись носителя `notify` в гейте изоляции; узнавание регистрации `notify-api` (З19) | `deploy-engineer` | kacho · `deploy/scripts/{assert-ban6-external-isolation.py,e2e-ban6-domains.py}` | `--self-test` зелёный, `lost`, `gap`, `missing` пусты; инъекции «запись снята», «регистрация не узнана» — красные с именем носителя; живой прогон на стенде печатает `InternalNoticeService/*` | E1, стенд с `notify-api` | S |
| D2 | чарт `notify`: пять ручек-лимитов во всех профилях, правила тревог Р19 с агрегацией `max`, проба правил на двух рядах (З21) | `deploy-engineer` | kacho · чарт `notify`, `deploy/tests/…/notify_alert_rules_test.go` | проба правил зелёная на двух рядах и красная на инъекции `sum`; `helm template` всех профилей несёт пять ручек; `helm install` + `rollout-ready` на `values.prod` | N4 | S |
| G1 | гейт «метод `notify-api` ↔ аннотация либо `RequireScope`» (З16 п.3, DoD 10.1 п.11) | `tooling-maintainer` | kacho · `internal/repohygiene/notify_method_authz_test.go` | зелёный с числом методов по двум видам; инъекции «снята аннотация `InternalNoticeService.Create`», «снят вызов у `ProjectNotificationContactsService.Update`» — красные | N2 (для второй инъекции — N8) | S |
| G2 | гейт «18 типов ↔ модель службы доступа» (З22) | `tooling-maintainer` | kacho · `internal/repohygiene/notice_tenant_types_test.go` | зелёный, печатает число типов модели; инъекция типа в фикстуру модели — красный с именем | N4 | S |

### Ярус 6 — стенд и воркспейс

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| S1e | сквозные NTF5-26 (а)–(е), 49 (а)–(г) на стенде | `integration-tester` | kacho · коллекция newman | зелёные на стенде в боевой посадке; провенанс ревизии сверен | E1, D1 | S |
| S3 | сквозные NTF5-84, 85; запись ведомости производителя новой коллекции | `qa-test-engineer` | kacho · коллекция newman, ведомость | зелёные на стенде; ведомость несёт строку коллекции | S2 посажена | M |
| W1 | ребро `notify → kaname` в `docs/specs/01-architecture-and-services.md` с вызывающими развёртываниями и опорой кэша (DoD 10.2 п.8) | `tooling-maintainer` | воркспейс · `docs/specs/01-architecture-and-services.md` | `./scripts/docs-gate/run-all.sh` зелёный | S2 | S |
| W2 | страницы сайта `services/notify/docs` (DoD 10.3 п.2) | `docs-writer` | kacho · `services/notify/docs` | сборка сайта — 0 битых ссылок | S3 | S |
| W3 | записи vault (DoD 10.3 п.3) | `vault-scribe` | воркспейс · vault | vault-gate зелёный | S3 | S |

## 3. Порядок по времени

1. Параллельно: C1, C2 (→ C3); P3 (после Е2), K3; ожидание Е1, Е3, Е5.
2. После Е1: P1, N0, N1; после K1: N3; параллельно N2, N4.
3. После Е4 и P1: E1; после E1 и стенда: D1, S1e; G1, G2.
4. Перед посадкой S1: C4 (тег TW) → N5 одним коммитом с подъёмом пина → посадка S1 волной.
5. После S1 и Е2: C5 → C6 (T2); P2, K2; N6 → N7 → N8, N9 → N10, N11; E2; D2.
6. После S2: S3, W1; затем W2, W3.
