# Топология репозиториев, зависимости, порядок работы

## Топология — ОДНО монорепо (факт на 2026-08-02)

Разработка ведётся в **одном** репозитории `PRO-Robotech/kacho` (**публичный**), который
клонируется в `project/kacho` (`bootstrap.sh`); `project/` под gitignore. Workspace
`PRO-Robotech/kacho-workspace` (**тоже публичный**) — корень: CLAUDE.md/rules, общие агенты,
спеки, vault, bootstrap.

> [!warning] Здесь была описана топология из 15 отдельных репозиториев — её нет
> Прежняя редакция этого раздела перечисляла `kacho-proto` / `kacho-corelib` / `kacho-<svc>` /
> `kacho-api-gateway` / `kacho-deploy` / `kacho-ui` / `kacho-test` / `kacho-vpc-implement` как
> действующую структуру, и на неё опирались `bootstrap.sh`, `sync-all.sh` и снятый вместе с
> раскаткой третий скрипт (его имя здесь не воспроизводится: файла в дереве нет, а цитата в
> обратных кавычках читается как координата — хук свежести справедливо считает её находкой) —
> тремя рукописными копиями одного списка, которые к тому же **разошлись между собой** (в
> `sync-all.sh` не хватало `kacho-geo`). Замер 2026-08-02: в `project/` склонирован **один**
> репозиторий продукта, и **ни одно** имя из этих списков с ним не пересекалось. Следствие —
> раскатка оснастки печатала одиннадцать «skip» и выходила успехом, то есть объявленный
> инвариант самодостаточности репо не выполнялся ни разу и это было ненаблюдаемо.
> Перечень теперь **выводится из дерева** (`repos.sh`), а не выписывается: см. `ai-tooling.md`.
>
> Предшествующие полирепо на GitHub **существуют и не заархивированы** (проверено
> `gh repo view`), но разработка в них не ведётся: последний push в каждом — середина июля
> 2026, тогда как в `kacho` — ежедневно. README монорепо называет их «архивом» — по существу
> верно, по факту флага `isArchived` нет. Клонируются только по явной просьбе
> (`KACHO_CLONE_LEGACY_POLYREPOS=1`). `kacho-vpc-operator` не резолвится вовсе (404), хотя
> стоял во всех трёх списках; `kacho-test` и `kacho-vpc-implement` в дереве не представлены.

### Раскладка монорепо (каталог ↔ прежний репозиторий)

| Каталог | Роль | Прежде |
|---|---|---|
| `proto/` | **единственный** дом всех `.proto` (`proto/kacho/cloud/<domain>/v1/`) + `buf.yaml` | `kacho-proto` |
| `pkg/` | общий фундамент: `api/` (сгенерённые стабы, РУКАМИ НЕ ПРАВИТЬ), `ids/ db/ grpcsrv/ grpcclient/ authz/ operations/ outbox/` … | `kacho-corelib` |
| `gateway/` | edge: gRPC-proxy + grpc-gateway REST | `kacho-api-gateway` |
| `services/iam/` | Account / Project / User / ServiceAccount / Group / Role / AccessBinding | `kacho-iam` |
| `services/vpc/` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / NetworkInterface | `kacho-vpc` |
| `services/compute/` | Instance / MachineType (раскол блочного хранения завершён — дубля нет, см. `data-integrity.md` карта владельцев) | `kacho-compute` |
| `services/storage/` | Volume / Snapshot / Image / DiskType — блочное хранение; владелец `volume_attachments` | — |
| `services/nlb/` | LoadBalancer / Listener / TargetGroup / Target | `kacho-nlb` |
| `services/registry/` | Registry / Repository / Tag (OCI) | — |
| `services/geo/` | Region / Zone (Geography — platform topology leaf, owner) | `kacho-geo` |
| `deploy/` | dev-стенд (Postgres + ingress) + e2e | `kacho-deploy` |
| `ui-future/` | Vite + React SPA control plane | `kacho-ui` |

**Новый `.proto` — ВСЕГДА в `proto/`.** Сервисные каталоги `.proto` не содержат — только
Go-импорт из `pkg/api/...`. Единый `buf lint`/`buf breaking` на всё дерево.

> [!note] Обратный раскол монорепо — НАМЕРЕНИЕ, а не факт
> Если продукт когда-нибудь снова разъедется на полирепо, нижеследующее правило про
> `replace` и versioned-модули вступает в силу **как есть** — оно писалось под ту топологию
> и остаётся нормативным на случай её возвращения. Сегодня оно **неприменимо по построению**
> (модуль один), и держать его как описание действительности — значит выдавать намерение за
> факт. Именно поэтому раздел ниже помечен, а не удалён.

## Build-граф — ОДИН Go-модуль (факт)

Замер 2026-08-02: `go.mod` в дереве **1**, модуль `github.com/PRO-Robotech/kacho`;
`replace` на внутренний модуль — **0**. Внутренних версионированных зависимостей между
частями продукта нет by construction: `proto/` → `pkg/` → `services/*` / `gateway/` — это
пакеты одного модуля, и порядок между ними — порядок импортов, а не пинов.

Что от прежнего графа остаётся нормой **и сегодня**:

- **Между собой сервисы НЕ зависят по коду.** DB-per-service, общение только по API
  (ban #8). Каталог `services/<a>/` не импортирует `services/<b>/` — общее живёт в `pkg/`.
  `geo` и `iam` — leaf-домены: их зовут, они не зовут никого из сервисов.
- **`gateway/` импортирует стабы всех доменов** — это его роль, а не нарушение.
- **Циклы запрещены** (см. рёбра ниже).

### Правило зависимостей при полирепо-топологии — `replace` ЗАПРЕЩЁН (норма, сегодня неприменима)

Действует, **если** части продукта снова станут отдельными модулями. Сегодня предмета нет
(модуль один), но правило выведено из реального инцидента и потому сохраняется дословно:

**В committed `go.mod` НЕ должно быть НИ ОДНОГО `replace github.com/PRO-Robotech/...`.**
Зависимости резолвятся **только** как versioned-модули (`require …@<pseudo-version>` с
public/GOPRIVATE-proxy). Причина: локальный `replace ../` не резолвится при single-repo
checkout (CI/Docker) → `reading ../kacho-corelib/go.mod: no such file` → падает
`go build`/`docker-build` → образ main не собирается (реальный инцидент: storage-split-gateway,
2026-07-13 — storage/v1 403 на проде из-за несобранного gateway-образа).

- **Локальная кросс-репо разработка** — через **git-ignored `go.work`** (`use ./kacho-*`;
  шаблон — `go.work.example`). go.work даёт локальные siblings БЕЗ правки go.mod; CI его не
  видит (single-repo) → использует versioned require. Заменяет `replace ../` полностью.
- **Бамп зависимости** — `GOWORK=off go get github.com/PRO-Robotech/<repo>@<sha>` в затронутом
  модуле → PR. Кросс-репо фича: proto → corelib → сервисы → gateway, каждый шаг бампит пин на предыдущий.
- **CI-гейт:** `! grep -rnE '^replace github.com/PRO-Robotech' project/*/go.mod` (пусто = OK).
  На монорепо гейт **тривиально зелёный** (один go.mod, ноль replace) — и это не «он работает»,
  а «ему нечего рассматривать»: не считать его прохождение свидетельством.
- **Dockerfile'ы** собираются versioned-модулями (single-repo context) ЛИБО через
  build-context = parent + COPY siblings — но **go.mod остаётся без replace** в обоих случаях.

## Runtime cross-domain edges (gRPC service→service; НЕ build-зависимость)

> Имена `kacho-<svc>` ниже — **домены**, а не отдельные репозитории: сегодня это каталоги
> `services/<svc>/` одного репо. Содержание раздела от этого не меняется — рёбра рантайма,
> направления и запрет циклов остаются нормой: сервисы общаются по API и не импортируют
> друг друга по коду независимо от того, в скольких репозиториях они лежат.
>
> [!note] Здесь стояли два ребра оператора сети — сняты решением владельца 2026-08-09
> Прежняя редакция держала их «как контракт на случай появления компонента», честно оговаривая,
> что репозиторий не резолвится, а в дереве ноль файлов по этому имени. Оговорка не спасала:
> место под несуществующий компонент **держалось не только здесь**. Его SPIFFE-имя стояло в
> кругах доверенных отправителей четырёх профилей и двух чартов, а тест круга этих записей
> **требовал** — то есть проверка безопасности защищала не фактического отправителя, а бронь
> под будущее. Круг, объявленный шире фактического, разрешает говорить за пользователя
> предъявителю сертификата, которого мы не выпускаем; `security.md` требует пинить его по
> **фактическим** отправителям, найденным по графу рёбер.
>
> Что сделано: записи сняты из шести мест, тест круга **перевёрнут** — он больше не требует
> брони, а падает на любой записи, которой в дереве не соответствует ни один чарт. Появится
> компонент со своим чартом — его сертификат отрендерится и проверка пройдёт сама; послабление
> истекает от появления предмета, а не от чьей-то памяти.
>
> **Что осталось и почему это отдельный предмет:** служебная учётка оператора и выданные ей
> права заведены применёнными миграциями, которые править нельзя (ban #5) — их снятие требует
> новой миграции и идёт своим изменением. Здесь снят только круг отправителей: «кто вправе
> говорить за пользователя» и «что этой учётке разрешено» — разные вопросы.

- `kacho-vpc → kacho-geo` — валидация `zone_id` Subnet/AddressPool (`geo.v1.ZoneService.Get`); Geography — домен geo (KAC-эпик #82). Заменяет прежнее ложное ребро `vpc→compute (zone)`.
- `kacho-compute → kacho-geo` — валидация `Instance.zone_id` (`geo.v1.ZoneService.Get`). Geography больше не «своя» таблица compute — теперь peer-валидация через geo-client (KAC-эпик #82).
- `kacho-nlb → kacho-geo` — валидация `region_id` LoadBalancer/TargetGroup (`geo.v1.RegionService.Get`, sync precheck на request-path, кэша нет). Заменяет прежнее ложное ребро `nlb→compute (region)`.
- `kacho-registry → kacho-geo` (REG-1 F4) — валидация `Namespace.region_id` (**required** на Create, `placement_type` всегда `REGIONAL`, оба immutable) через `geo.v1.RegionService.Get`, sync peer-validate на request-path, per-call 5s deadline + `retry.OnUnavailable`, fail-closed `UNAVAILABLE`. Namespace — regional-anycast (zone-независим). geo — leaf (не зовёт registry обратно) → ацикличность holds. Client `services/registry/internal/clients/geo`, wired в `serve.go` (`GeoGRPCAddr`/`GeoMTLS`).
- `kacho-geo → kacho-iam` — `InternalIAMService.Check` (authz-gate на каждом RPC обоих листенеров; read-RPC `system_viewer`-floor, admin-CRUD `system_admin`). geo — leaf-консумер только iam (как любой сервис).
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup) + IPAM-аллокация Address.
- `kacho-compute → kacho-vpc` (subnet-placement, 2026-07-25) — `SubnetService.Get` на **request-path** `Instance.Create`:
  зона подсети каждого NIC обязана совпадать с зоной инстанса (REGIONAL/anycast-подсеть из зональной
  проверки исключена, проверяется регионально). Читается **под identity вызывающего**, per-call deadline,
  fail-closed. Ребро заведено именно ради этой проверки: без резолва подсети у владельца зональная
  когерентность интерфейса ничем не обеспечена (см. `data-integrity.md` §Placement-coherence).
  Переиспользует уже объявленную, но мёртвую группу mTLS-переменных чарта.
- `kacho-nlb → kacho-geo` (zone→region для instance-таргетов, 2026-07-25) — `ZoneService.Get` через порт
  `ZoneRegionClient`. Заменяет **удалённую** строковую деривацию региона из имени зоны (`regionFromZone`).
  Для nic/ip_ref-таргетов регион берётся из авторитетного `Subnet.RegionID` (peer-ответ vpc), без вызова geo.
- `kacho-storage → kacho-geo` (zone→region для Volume из Image, 2026-07-25) — `RegionOfZone` на request-path:
  регион зоны тома обязан совпадать с регионом образа; сверка **внутри insert-CAS** (`AND i.region_id = $12`),
  0 строк → байт-идентичный hide-existence `Image <id> not found`. Реализует заявление миграции 0007,
  которого в коде не было.
- `kacho-compute → kacho-storage` — **несущее ребро раскола блочного хранения** (было не задокументировано
  до 2026-07-25, хотя живо в коде: `services/compute/internal/clients/storage_client.go`, провязано в
  composition root). Резолв boot-источника (`storage.image`/`storage.snapshot`/`storage.volume`) + attach/detach
  тома. **Attach инициируется compute, payload самоописывающийся** (несёт `instance_id`/`instance_zone_id`/
  `project_id`/`instance_name`) → storage валидирует **свою** строку одним CAS-INSERT и **никогда не зовёт
  compute обратно** — ацикличность держится (проверено: ноль импортов `computev1` в `services/storage`).
  Таблица привязки `volume_attachments` живёт **у владельца-storage**; compute-шная `attached_disks` дропнута.
  На Instance — read-only зеркало с мягкой деградацией при dangling-ref.
- `kacho-nlb → kacho-compute` — резолв Instance-таргетов (`compute.v1.InstanceService.Get`); **только** для Instance (НЕ для geography — region-валидация теперь `nlb→geo`).
- `* → kacho-iam` — `ProjectService.Get` (existence + account lookup, leaf-owner) + `InternalIAMService.Check` (authz-gate).
- `kacho-vpc → kacho-iam` (fgaproxy, SEC-A) — `InternalIAMService.RegisterResource`/`UnregisterResource`: запись/снятие
  owner-hierarchy-tuple в FGA через IAM (модули не ходят в FGA напрямую). Internal-only :9091, идемпотентно, at-least-once
  через transactional-outbox (SEC-D). Least-priv: ReBAC `fga_writer` @ `iam_fgaproxy:system`.
- `kacho-compute → kacho-iam` (fgaproxy, SEC-A) — то же ребро: `RegisterResource`/`UnregisterResource` для owner-tuple
  compute-ресурсов. Internal-only :9091, идемпотентно, fgaproxy least-priv `fga_writer` @ `iam_fgaproxy:system`.
- `kacho-storage → kacho-iam` (fgaproxy, SEC-D / CS-1 GAP-D) — то же ребро: `RegisterResource`/`UnregisterResource`
  для owner-tuple storage-ресурсов (`storage_volume:<id>` / `storage_snapshot:<id>`). Нужен, чтобы gateway
  scope_extractor'ы `{storage_volume,volume_id}`/`{storage_snapshot,snapshot_id}` резолвили target→project (анти-BOLA).
  Internal-only :9091, идемпотентно, at-least-once через transactional-outbox (`kacho_storage.fga_register_outbox`) +
  register-drainer, fgaproxy least-priv `fga_writer` @ `iam_fgaproxy:system`. Одностороннее (storage не зовётся обратно).
- `kacho-registry → kacho-iam` (jwks-fetch) — **HTTPS GET публичного JWKS** с cluster-internal iam-эндпоинта
  (`:9097` `GET /.well-known/jwks.json`), **sync** на request-path (data-plane верифицирует подпись
  docker-Bearer'а), **fail-closed** (iam недоступен/5xx и в кэше нет пригодного ключа → verify reject →
  docker-клиенту `401 invalid_token`; **никогда** allow), **server-TLS** (one-way) с trust'ом internal-CA.
  **Замещает** прежний прямой fetch публичного JWKS Hydra: iam — short-TTL кэширующий reverse-proxy
  Hydra-JWKS (байт-в-байт зеркало; **Hydra остаётся issuer'ом/подписантом**, iam ключи не чеканит, issuer-pin
  registry остаётся на Hydra). Ацикличность holds: iam **никогда** не зовёт registry. Уже существующие рёбра
  `kacho-registry → kacho-iam`: `InternalIAMService.Check`/fgaproxy (:9091, authz-gate) + `ProjectService.Get`
  (:9090, existence + account lookup). Детали — `edges/registry-to-iam-jwks-fetch.md`.

**Циклы запрещены**: если A зовёт B — B не зовёт A. Новое ребро фиксируется здесь как runtime-edge.
- `kacho-geo` — **leaf** (как iam): geo никого, кроме iam (authz-Check), не зовёт. Рёбра `vpc→geo` / `compute→geo` /
  `nlb→geo` однонаправлены (geo не вызывает consumer'ов обратно) → циклов с geo нет. После выноса Geography ложные
  «ради geography» рёбра `vpc→compute` и `nlb→compute (region)` удалены.
- `kacho-compute → kacho-vpc` (NIC/IPAM) — единственное оставшееся ребро между vpc и compute, **одностороннее**:
  vpc больше не зовёт compute (zone-валидация ушла в geo). Семантического цикла нет.
Регламент кросс-доменных ссылок — `data-integrity.md`.

## Порядок работы для кросс-доменной фичи (топосортировка графа)

Порядок остаётся тем же — он про **зависимости**, а не про репозитории, и на монорепо
означает порядок каталогов внутри одного PR (или серии green-коммитов, `git-issues.md`
§CI), а не последовательность merge в разные репо:

1. `proto/` (новый `.proto` + регенерация в `pkg/api/`, `buf lint`/`breaking` зелёные)
2. `pkg/` (если меняется общий фундамент)
3. `services/<svc>/` (между собой в любом порядке; leaf-домены `iam`/`geo` обычно первыми — их зовут consumer'ы)
4. `gateway/` (регистрация RPC: public mux / internal mux)
5. `deploy/` (helm/compose)
6. `kacho-workspace` (docs/specs, vault-trail) — **отдельный репозиторий**, отдельный коммит

Единственная оставшаяся кросс-**репозиторная** граница — между монорепо и workspace:
спека, приёмка и vault-trail живут в workspace, код — в монорепо. Ссылка между ними —
по URL коммита/PR, не по пину модуля.

> [!note] Прежний абзац про временный пин sibling-репо к feature-ветке (`ref:` в CI) снят:
> при одном репозитории пиннить нечего. Правило возвращается вместе с полирепо-топологией,
> если она вернётся (см. §«Обратный раскол — намерение»).

Кросс-доменный эпик — tracking-issue в `kacho-workspace` (метка `epic`) + issue в `kacho`.
