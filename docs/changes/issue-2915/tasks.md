<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# issue-2915 (NTF-1, ядро почтового шлюза) — маршрут работ

> **Что этот документ.** Утверждаемый маршрут исполнения замысла `design.md` рядом: полосы,
> исполнитель по базе маршрутизации, репозиторий и пути, предикат снятия, зависимости, размер.
> Это не трекер. Состояние полос живёт в задачах `PRO-Robotech/kacho#2915`,
> `PRO-Robotech/corelib#77`, `PRO-Robotech/kaname#484`, `PRO-Robotech/kacho#2916`
> (`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md` §2).
>
> **Редакция 1 · 2026-09-30 — проект маршрута по замыслу редакции 1.** Состояние `TASKS_READY`
> этот файл не объявляет: по §5 SDD-1 оно наступает только после `DESIGN_APPROVED` и проверенного
> writing-plans handoff. Handoff либо подтверждает этот файл без правки, либо переписывает его; в
> обоих случаях действует текст на отпечатке, названном записью handoff.

## 0. Правила маршрута

- **Порядок стадий приёмки** (§5 приёмки):
  - S0 — контракт;
  - S1 — corelib, затем тег;
  - S2 — kaname на теге;
  - S3 — notify на обоих пинах;
  - S5 — поставка.

  S4 (NS) идёт параллельно и блокирует только боевое включение. Полоса стартует, когда сняты её
  зависимости; полосы одного яруса без общих путей идут параллельно.
- **Проба до кода** в каждой полосе исполнителя кода. Сначала проба с ID сценария в имени
  (`NTF1-B09 · …`, DoD 2), красная на текущем дереве с напечатанным исходом, затем код, затем та
  же проба зелёная — одним изменением (ban #12). Красное фиксируется до кода: это свидетельство
  `RED_PROVEN` полосы.
- **Заказанные пробы** — строки §11а замысла (УК…) — входят в предикат своей полосы наравне со
  сценариями приёмки.
- **Гейт** печатает объём осмотренного, падает на пустом обходе и доказан инъекцией в обе
  стороны (DoD 3). Integration-группа даёт тот же вердикт трижды подряд (DoD 5).
- **Единица сдачи** — коммит исполнителя в ветке полосы. Сведение волны, запрос на слияние,
  вливание и снятие веток — `git-operator` по решению диспетчера; в ствол — только одобренное
  (Д16).
- Размер: **S** — до дня одного исполнителя, **M** — два-три, **L** — больше трёх.
- Предикат снятия — команда и ожидаемый исход. «Зелёный» — с напечатанным числом исполненного.

## 1. Внешние зависимости

| № | зависимость | состояние на 2026-09-30 | чем проверено |
|---|---|---|---|
| Е5 | событие одобрения приёмки NTF-1 опубликовано | **открыта** | `grep -n 'status:' docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/29cfa368….yaml` → `not_performed` |
| Е6 | `DESIGN_APPROVED` и пересверка разбора на отпечаток `design.md` | **открыта** | `ls docs/changes/issue-2915/reviews/` — нет `design/`, нет `class-exposure/revalidation/` |
| Е2 | L03 и Р11 согласованы в приёмке (design.md §13) | **открыта**; гейтит только L-пробы полосы D5 | приёмка строки 1169 и 2566 |
| Е1 | Х5 NTF-4 — значение оси формы хоста | открыта; **не блокирует** NTF-1 | design.md §13 |
| Е3 | норма видов (1)–(7) в правилах | открыта; **не блокирует** код | design.md §13 |
| Е4 | NTF-3: ведомость G19 для `notify-api`, `schema_rev` ведомости, цены замещения Р6 | открыта; **не блокирует** NTF-1 | design.md §13 |

Полосы кода стартуют после Е5 и Е6.

## 2. Полосы

### Ярус 0 — контракт (S0, kacho#2915)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| P1 | контракт ленты `corelib.notify` и поле `bound_to_server` аннотации прав (З5 замысла §5, З14) | `proto-sync` | kacho · `proto/corelib/notify/feed.proto`, `proto/corelib/authz/v1/authz_options.proto`; corelib · `api/corelib/notify/**`, `api/corelib/authz/v1/**` | `buf lint`, `buf breaking` зелёные; `git grep -h 'returns (stream' -- proto \| wc -l` → 1 (NTF1-C01); стабы порождены воспроизводимо; путь вписан в `PRO-Robotech/corelib#9` | Е5, Е6 | S |

### Ярус 1 — фундамент (S1, corelib#77)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| C1 | `notify/form` (З2) | `go-implementer` | corelib · `notify/form/**` | `go test ./notify/form/... -count=1` зелёный с числом: B28 (форма типа, нуль), B29 (тема, перечень типов с инъекцией `duration`, пять типов); проба выходов четырьмя путями (УК47); `Presence` по перечню видов, `timestamp` + 0,5 с — «не задано», год вне `[0000..9999]` — отказ (УК51, УК56, УК58, УК66); `go list -deps ./notify/form` без `notify/spec`, `html/template`, `text/template` | P1 | M |
| C2 | `notify/address` (З3) | `go-implementer` | corelib · `notify/address/**` | `go test ./notify/address/...` зелёный: B27 (форма типа, нуль, IDNA, замороженный корпус `corpus_test.go`); Unicode и A-label — один ключ, `ß`/`ss` — два (УК36); проба выходов (УК47) | P1 | S |
| C3 | `notify/spec` (З4) | `go-implementer` | corelib · `notify/spec/**` | `go test ./notify/spec/...` зелёный: A01–A11, A08 с числом фикстур; `RefSites` по восьми видам блока из `spec.BlockKinds()`, вид без строки таблицы — красный (УК59, УК66); отпечаток: перестановка атрибутов, кавычки, комментарии — прежний, прежняя версия алгоритма при том же наборе — «набор тот же», база прежнего формата читается (УК52, УК56) | C1 | M |
| C4 | `notify/feed`: схема, `Put`, окно, флаг (З6, З7, З12) | `go-implementer` | corelib · `notify/feed/{put,window,flag,desc,errors}*.go`, `notify/feed/schema/**` | `go test -tags integration ./notify/feed/... -run 'NTF1-B0[1-2]\|NTF1-B0[89]\|NTF1-B2[7-9]\|NTF1-B30\|NTF1-N0[5-7]\|NTF1-N09' -count=3` — тот же вердикт трижды; B28 (`Put`), B29 (`Put`, ревизия) (УК40, УК42); пустая строка флага — отказ (УК20, УК26); гейт «нет чтения счётчика с последующей записью» (B09) | C1, C2 | L |
| C5 | сервер ленты: `Claim`, `Ack`, уборщик, запечатывание, словарь исходов и метрики (З8–З11, З27) | `go-implementer` | corelib · `notify/feed/{server,claim,ack,sweeper,seal,outcomes,metrics}*.go` | integration зелёный трижды: B03–B07, B10–B18, B20–B26, B31, C03–C06; повтор `DEFER` после выдачи T2 — успех, `DEFER` другой причины — `OUTCOME_ALREADY_RECORDED` (УК36); смена шаблона при прежнем шифротексте — `sealed_mismatch` (УК19); «выдана, аренда истекла, больше не выдана» → `no_ack`, вклад не возвращён (УК66); два уборщика над одной строкой — вклад −1, строк `EXPIRED` 1 (УК66); C05 без разрешения в кэше (УК22); экспорт `feed.Classes()`, `feed.Reasons()`, `feed.RefundReasons()`, `feed.LimitRefundedPredicate` (УК62, УК68) | C4 | L |
| C6 | `cmd/notifygen` (З5) | `go-implementer` | corelib · `cmd/notifygen/**` | `go test ./cmd/notifygen/...` зелёный: D01–D04, D06, D07 (включая (д), (е), A→B→A), `-list` равен записанному множеству в обе стороны; экспорт `X<Scope>Per<Window>` (УК70); `SendX` без литерала сравнения по виду — проба разбора порождённого файла (УК58) | C3, C4 | M |
| C7 | звено идентичности служб, `CallerSubject`, `ServiceSubject` (З13) | `go-implementer` | corelib · `grpcsrv/service_identity*.go`, `authz/{caller_subject,subject_extract}.go`, `listnarrow/subject.go`, `servicehost/serve.go` (`unaryChain`, `streamChain`), `servicecontract/contract.go` (`ServiceIdentity`) | `go test ./grpcsrv/... ./authz/... ./listnarrow/... ./subscription/... ./operations/... ./servicehost/...` зелёный: M01–M06, M09; пересланный `service`, сертификат вне таблицы → субъекта нет; ключ не канонический → отказ старта; два URI-SAN → субъекта нет; корзина `service:x` отдельна от `user:x` (УК2, УК26); `TestBothListenersRefuseIdenticallyOnTheWire` — оба слушателя несут звено | P1 | L |
| C8 | ось формы хоста, самоотчёт (З15) | `go-implementer` | corelib · `servicecontract/{contract,hostform}.go`, `servicehost/serve.go`, `observability/bootposture.go` | `go test ./servicecontract/... ./servicehost/... ./observability/...` зелёный: `HostNoGRPC` + адрес, транспорт или `OwnContour` → отказ с именем поля; нуль — пара; `Serve` на `HostNoGRPC` → ошибка (УК38, УК42) | — | S |
| C9 | форма `ScopeBound` в выводе каталога, привязка `Spec.Bound` (З14) | `go-implementer` | corelib · `authz/catalogderive/**`, `authz/interceptor.go`, `servicecontract/contract.go` | `go test ./authz/... ./servicecontract/...` зелёный: `bound_to_server` вместе с `from_request_field` — отказ вывода с именем метода; метод формы без привязки — отказ старта; две привязки одного типа — отказ | P1 | S |
| C10 | гейты дерева в `treehygiene` (З16, З31) | `go-implementer` | corelib · `treehygiene/notify_{typesafety,idna,domainreceivers,feedput,feedwrites,valueerr,wiring,exceptions}.go` и пробы | `go test ./treehygiene/... -count=1` зелёный (без `-short`-пропуска): инъекции B27 (гейт, приёмник (1)–(3)) и (4) значения-функции (УК64); B28 (гейт) (1)–(9); B28 (гейт `Put`) (1)–(3) с входом из `-list`; B19; D08 (1)–(9); узел `Value()` отброшена — инъекция и близнец (УК46); вид (7) сверен с `go/build` в обе стороны, `NoGoError`-каталог — находка, обход по `git ls-files` (УК45); запись реестра без довода или без предиката снятия — красный (УК48); «`StartSweeper` под условием флага» — находка (УК63); проба «перечни объявлены один раз» (УК44, УК55); прогон по corelib печатает версию модуля и числа видов | C3, C4, C5 | L |
| C11 | запрещённые типы и приставка `ntf` | `go-implementer` | corelib · `authz/proxytuple/policy.go`, `ids/ids.go` | `go test ./authz/proxytuple/... ./ids/...` зелёный; три типа в `forbiddenObjectTypes`; `ntf` в `KnownHyphenPrefixes` | — | S |
| C12 | тег corelib | `git-operator` | corelib · тег | DoD 7–9: `go list -deps ./notify/...` без `net/smtp`, `mime/multipart`, `html/template`; тег выпущен | C1–C11 | S |

### Ярус 2 — kaname (S2, kaname#484)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| K8 | пин corelib на теге C12 | `git-operator` | kaname · `go.mod`, `go.sum` | `go build ./...` зелёный без `replace` | C12 | S |
| K1 | модель: `service`, `notification_feed`, `notification_namespace` (З17) | `go-implementer` | kaname · `internal/authzmodel/fga_model.fga` | `go run ./tools/modelcanoncheck` зелёный; `grep -cE '^type (service\|notification_feed\|notification_namespace)$'` → 3 | K8 | S |
| K2 | манифест: форма строки, валидатор, применитель с `authz.ServiceSubject` (З17) | `go-implementer` | kaname · `tools/modulemanifestcheck/**`, `internal/servicemanifest/**`, `internal/repo/kaname/pg/module_seed_writer.go` | `go test ./tools/modulemanifestcheck/... ./internal/servicemanifest/...` зелёный: F02, F03, F21; `TestMRW07_GroupWithItsGrantIsAccepted` зелёный; применитель не зовёт `FGASubjectRef` для `service` (УК1) | K1 | M |
| K3 | запись выдачи, `ResolveSend`, `Revoke`/`Restore` (З18) | `rpc-implementer` (схема — `migration-writer`) | kaname · `proto/kaname/cloud/iam/v1/internal_notification_grant_service.proto`, `internal/migrations/<новая>.sql`, `internal/…/notificationgrant/**` | `go test -tags integration ./... -run 'NTF1-F(0[1-9]\|1[013-9]\|2[03])\|NTF1-J03' -count=3` — тот же вердикт трижды; дробная отсечка `c − 0,5 с → REVOKED` (УК8, УК27); гейт F18 | K2, K5 | L |
| K4 | надзор не применяется: `SuperGateExempt`, `planCheck`, семь мест, гейт F12 (З19) | `go-implementer` | kaname · `internal/authzguard/supergate_exempt.go`, `internal/service/authorize_service.go`, `internal/authzguard/{own_door,read_authz}.go`, `internal/check/supergateexemptsites_test.go` + ведомость | F12 (а)–(ж) и близнецы; гейт F12 с инъекцией в обе стороны и числом мест по классам; смешанный батч `notification_feed/*` и `iam_user/*` в одном `BatchCheck` → `false` и `true` (УК5, УК27) | K1 | M |
| K5 | звено Р2 на слушателях kaname (`{ResolveSend}`), корпус M07 (З13) | `go-implementer` | kaname · `cmd/kaname/serve.go` (`identityUnary`), `internal/authzguard/service_subject_corpus_integration_test.go` | M07 зелёный: корпус ответов до Р2 побайтово равен; `authzguard.PrincipalSubject` второго носителя не читает (УК3) | K8 | M |
| K6 | отказ тенантских поверхностей и гейт писателя (З17) | `go-implementer` | kaname · `internal/apps/kaname/api/access_binding/**`, `internal/check/servicesubjectwriter_test.go` | M10 зелёный; инъекция второго писателя кортежей `service:` — находка | K2 | S |
| K7 | тонкие вызывающие гейтов дерева и вызов в CI kaname (З16, З31) | `tooling-maintainer` | kaname · `internal/check/{addressnormalizesingular,notifytypesafety,notify_wiring}_test.go`, `Makefile` (`notifications-check`, `notify-tree-gates`), `.github/workflows/ci.yml` | прогоны по kaname печатают версию corelib и объём; инъекции B27 (гейт) (1), B28 (гейт) (5), (9), B28 (гейт `Put`) (3), D08 (9) — находки; копий перечней в kaname нет (`git grep -n` литерала перечня расширений → 0, УК50); исполненный шаг `notifications-check` печатает отпечаток базы (DoD 10) | C10, K8 | M |

### Ярус 3 — notify и гейты kacho (S3, kacho#2915)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| N11 | пины corelib и kaname одним изменением | `git-operator` | kacho · `go.mod`, `go.sum` | `TestForbiddenProxyObjectTypesAgreeWithTheModel`, `modelrelationproducer_test.go`, `proxyforbiddentypes_test.go` зелёные на новых пинах (DoD 11) | C12, K1 | S |
| N1 | каркас службы: конфигурация, стражи, дескриптор `HostNoGRPC`, диагностика (З15, З20) | `service-scaffolder` | kacho · `services/notify/cmd/notify/**`, `services/notify/internal/config/**`, `services/notify/servesurface_ledger.go` | E04, G01, G06, G15 зелёные; `knobcensus_test.go` — ручки отключения TLS нет; страж суммы сроков с именами ручек (УК31) | N11, C8 | M |
| N2 | перечень источников, клиент с точным SAN, подписка, цикл `Claim` (З21) | `go-implementer` | kacho · `services/notify/internal/source/**` | E01–E03, G22 зелёные; размер `Claim` ≤ свободных исполнителей | N1 | M |
| N3 | `deliver.Decide`: порядок клеток, `Resolved` без колонки `class`, срок по аренде (З21, З22) | `go-implementer` | kacho · `services/notify/internal/deliver/**` | G02, G20, G21, G24–G26 зелёные; пары «чужая ревизия + REVOKED / адрес вне формы / исчерпанная сетка» → `DEFER(template_skew)`, вызовов `ResolveSend` и резервов 0 (УК57); чужая ревизия с колонкой `security` при исчерпанной сетке → `template_skew`, резервов 0 (УК67); `DATA` дольше аренды → сессий по строке ≤ 1 (УК31, УК37); аренда фикстурного сервера короче константы → сессий ≤ 1 (УК65, УК67); гейт «`row.Class` читает одна строка» | N2, N4 | L |
| N4 | ответ `ResolveSend`: классификатор, отсрочка, метрика с кодом (З23) | `go-implementer` | kacho · `services/notify/internal/{grant,peeranswer}/**` | F01, F04–F07, F11, F23 (сторона notify), G23 зелёные; число вызовов `ResolveSend` по строке в `NOT_YET_GRANTED` ≤ T / `deferFor` + 1 (УК14, УК28); пространство A отказывает, строки `kaname` отправлены в срок (УК32, УК37); незаданный вариант ответа — род «отказ» (УК69) | N1 | M |
| N5 | рендер, макет, сборщики ссылки и заголовков, эталоны (З25) | `go-implementer` | kacho · `services/notify/layout/**`, `services/notify/internal/render/**`, `services/notify/testdata/golden/**` | G03, G04, G18, B27 и B28 (нуль, приёмники notify) зелёные; блок с `when` — по проверенному набору (УК59) | N3 | M |
| N6 | SMTP и таблица классификатора (З26) | `go-implementer` | kacho · `services/notify/internal/smtp/**` | G07–G11, G14, G16 зелёные; три формы 5xx на `RCPT` — три строки таблицы (УК17) | N1 | M |
| N7 | сетка, потолок, ведро, пауза; база `kacho_notify` (З24) | `go-implementer` (схема — `migration-writer`) | kacho · `services/notify/internal/limits/**`, `services/notify/internal/migrations/**` | H01–H10 зелёные; H03 с двумя репликами в процессе; резерв после `DEFER` возвращён, затем письмо при S−1 проходит (УК15, УК28); повтор `Ack` не освобождает резерв второй раз (УК30); миграции в боевой посадке с `sslmode=require` (DoD 13) | N1 | M |
| N8 | метрики и правила тревог (З27) | `go-implementer` | kacho · `services/notify/internal/metrics/**`, `deploy/helm/notify/templates/prometheusrule.yaml`, `deploy/tests/…/notify_alert_rules_test.go` | G12, G27 зелёные; проба G27 берёт перечни из `feed.Classes()`, `feed.Reasons()` (УК62, УК67); метка `direction` у `template_skew` (УК54) | N3, C5 | S |
| N9 | сборка шаблонов и `bundle-check` | `go-implementer` | kacho · `services/notify/bundle/**`, `services/notify/Makefile` | G17 зелёный; `make -C services/notify bundle-check`, `make lint`, `gosec` зелёные (DoD 13) | N5, C3 | S |
| N10 | гейты kacho (A09, M08, G19, D05, C07, B20) | `tooling-maintainer` | kacho · `internal/repohygiene/{notifyspecsingular,servicesubjectsingular}*_test.go`, `internal/repohygiene/catalogparity_test.go` (пакет `corelib.notify`), `internal/repohygiene/outboxobservedgate_test.go` (четвёртый вход), `services/notify/{servesurface,runtimedeps}_test.go` | каждый гейт печатает объём и доказан инъекцией; G19 сверяет с ведомостью корней, корень без записи — находка (УК23); M08 — одна функция, инъекция второй — находка (УК1, УК3) | N1, C10 | M |
| N12 | фикстурные источники и проба F22 (а), (в), B26 (в) | `integration-tester` | kacho · `services/notify/internal/…/{forwarded_admin,deliver}_integration_test.go` | F22 (а), (в), B26 (в) зелёные трижды; в B26 (в) счётчик клетки `SENT` = 1 (УК37) | N3, K3 | M |

### Ярус 4 — NS (S4, kacho#2916)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| J1 | политика выпуска сертификатов служб (З30) | `deploy-engineer` | kacho · `deploy/helm/umbrella/templates/**` (политика), `deploy/tests/cluster/cert-issuance-policy-test.sh`, `deploy/scripts/assert-production-posture.sh` | J01, J02, J04 зелёные на поднятом кластере | — | M |
| J2 | декларации `<служба>.spiffe` и гейт согласия (З28, З30) | `deploy-engineer` | kacho · `deploy/helm/umbrella/values*.yaml`, `deploy/tests/helm/service-identity-declaration-test.sh` | J05 зелёный с числом читателей; правка одного читателя в обход — красный с именем (УК24) | — | S |

### Ярус 5 — поставка (S5, kacho#2915)

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| D4 | `notify-probe` (З29) | `service-scaffolder` | kacho · `services/notify/cmd/notify-probe/**`, `services/notify/notifications/probe-hello/**` | M08, N08 зелёные; регистрация сервера ленты в прод-файле корня | C5, C7, N11 | M |
| D1 | чарт notify: реплики, PDB, секрет, отдельная установка (З28) | `deploy-engineer` | kacho · `deploy/helm/notify/**` | I01, I02, I05, I06; `helm lint` | N1 | M |
| D2 | флаг, помощник `enabledFor`, выведенный перечень, `sourceLimits` (З28) | `deploy-engineer` | kacho · `deploy/helm/umbrella/templates/_notifications.tpl`, `deploy/helm/notify/templates/_sources.tpl`, `deploy/notifications_flag_test.go`, `deploy/notify_source_list_derived_test.go` | N01–N04 зелёные с числом цепочек; вариант рендера «глобальный `false`, модуль `true`» (УК20) | D1 | M |
| D3 | приёмник с TLS и стендовые объекты вне `prod` | `deploy-engineer` | kacho · `deploy/helm/umbrella/templates/mail-receiver.yaml`, `deploy/mail_receiver_core_test.go` | I03, I04 зелёные | D1 | S |
| D7 | вызов в CI kacho и изоляция края (З31) | `tooling-maintainer` | kacho · `.github/workflows/ci.yaml`, `Makefile` (`notifications-check`, `notify-tree-gates`), `internal/repohygiene/notifywiring_test.go`, `deploy/scripts/assert-ban6-external-isolation.py` (`INTERNAL_ENDPOINTS` — `notify`) | D08 по kacho зелёный с инъекциями (1)–(9); исполненный шаг печатает отпечаток базы и число шаблонов `notify-probe` (DoD 12); C02 на стенде — `ISOLATED` | C10, D4 | S |
| D5 | сквозные: коллекция newman `notify-delivery` и запись ведомости производителя | `qa-test-engineer` | kacho · `tests/newman/notify-delivery/**`, ведомость производителя | прогон через `assert-suites-green.sh`: исполнено = число кейсов, красных 0 (I03, L01, L02); integration L03–L05 зелёные — **L03 после Е2** | D1–D4, J1, J2 | L |
| D6 | подъём в боевой посадке | `deploy-engineer` | kacho · `.github/workflows/production-posture.yml`, `deploy/tests/helm/notify-standalone-test.sh` | `helm install` и rollout-ready цепочки `dev-prod` с notify и `notify-probe` (DoD 17) | D1–D4, J1 | S |
| D8 | репетиция процедур (K01–K03) | `integration-tester` | kacho · `services/notify/procedure_rehearsal_test.go` | K01–K03 зелёные; каждый пропуск назван своим красным | D4, N9 | S |

### Ярус 6 — воркспейс

| № | полоса | исполнитель | репозиторий · пути | предикат снятия | зависит от | размер |
|---|---|---|---|---|---|---|
| W1 | пакет: исполняемые держателей `ЗАВОДИТСЯ ЭТИМ ИЗМЕНЕНИЕМ` по заведённым файлам, `implementation_diff_set`, свидетельства | `tooling-maintainer` | kacho-workspace · `docs/changes/issue-2915/{holders.yaml,change.yaml,evidence/**}` | в `holders.yaml` строк «ЗАВОДИТСЯ ЭТИМ ИЗМЕНЕНИЕМ» 0; `./scripts/docs-gate/run-all.sh` зелёный | D5, D6 | S |
| W2 | правки правил и спеки-книги §3 приёмки (З4…З10) и норма видов (1)–(7) (Е3) | `tooling-maintainer` (спека-книга — `docs-writer`) | kacho-workspace · `.claude/rules/**`, `docs/specs/01-architecture-and-services.md`, `docs/specs/04-roadmap-and-phasing.md` (задача `kacho-workspace#881`) | правки названы в тексте; `./scripts/rules-gate/…` зелёный; `grep -rl unsafe .claude/rules/` находит строку нормы | — | M |
| W3 | trail записок (DoD 19) | `vault-scribe` | kacho-workspace · записки ресурсов, rpc, пакетов и рёбер DoD 19 | `./scripts/vault-gate/run-all.sh` зелёный | посадка S3, S5 | S |
| W4 | согласование L03 и Р11 в приёмке (Е2) | `acceptance-author` | kacho-workspace · `docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` | новая редакция одобрена; первичный разбор по Д22 судит дельту | — | S |

## 3. Порядок по времени

1. Е5, Е6, затем P1.
2. Параллельно: C1, C2, C7, C8, C11 и P1-зависимые C9. Затем C3 (после C1), C4 (после C1, C2),
   C5 (после C4), C6 (после C3, C4), C10 (после C3–C5). Затем C12.
3. После C12:
   - K8, затем K1, K5 параллельно;
   - K2, K4 (после K1), K6 (после K2), K3 (после K2, K5), K7 (после C10).
4. После C12 и K1 — N11. Затем N1, дальше:
   - N2, N4, N6, N7 параллельно;
   - N3 (после N2, N4), N5 (после N3), N8, N9, N10, N12.
5. J1, J2 — в любой момент, параллельно ярусам 1–3.
6. D4, D1, затем D2, D3, D7, D8, D6. D5 — после всего яруса и Е2 для L03.
7. W1, W3 — после посадки; W2 и W4 — независимо, в любой момент.
