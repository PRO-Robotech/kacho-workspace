# Polyrepo: структура, зависимости, порядок работы

Workspace — корневой git-репо. Sibling-репо клонируются в `./project/`
(`bootstrap.sh`); `project/` под gitignore, у каждого свой `.git/` и
`git@github.com:PRO-Robotech/<repo>.git` (`gh` авторизован).

## Репозитории

| Репо | Роль |
|---|---|
| `kacho-workspace` | корень: CLAUDE.md/rules, общие агенты, спеки, bootstrap |
| `kacho-proto` | **единственный** дом всех `.proto` (`proto/kacho/cloud/<domain>/v1/`); сгенерированные Go-stubs commit-ятся в `gen/go/...` |
| `kacho-corelib` | переиспользуемые Go-пакеты (см. `architecture.md`) |
| `kacho-api-gateway` | edge: gRPC-proxy + grpc-gateway REST |
| `kacho-iam` | Account / Project / User / ServiceAccount / Group / Role / AccessBinding |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address / Gateway / NetworkInterface |
| `kacho-compute` | Instance / Disk / Image / Snapshot / DiskType |
| `kacho-geo` | Region / Zone (Geography — platform topology leaf, owner) |
| `kacho-deploy` | dev-стенд (Postgres + ingress) + e2e |
| `kacho-ui` | Vite + React SPA control plane |
| `kacho-test` | сводный e2e/regression стенд |
| `kacho-vpc-implement` | data-plane sibling VPC — spec-only, вне build-графа, control-plane его не касается |

**Новый `.proto` — ВСЕГДА в `kacho-proto/`.** Сервисные репо `.proto` не содержат —
только Go-импорт `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1`.
Единый `buf lint`/`buf breaking` на всё, синхронные версии, готовые клиентские SDK.

## Build-граф (источник истины — `replace github.com/PRO-Robotech/...` в `*/go.mod`)

```
kacho-proto                 ← ни от чего внутри проекта не зависит
  └─ kacho-corelib          ← replace ../kacho-proto
       ├─ kacho-iam         ┐ каждый сервис: replace ../kacho-corelib + ../kacho-proto.
       ├─ kacho-geo         │ Между собой сервисы НЕ зависят по build (DB-per-service,
       ├─ kacho-vpc         │ общение только по API). kacho-geo — leaf-домен Geography
       ├─ kacho-compute     │ (Region/Zone), как iam: ни от какого сервиса не зависит.
       └─ kacho-api-gateway ┘ (api-gateway импортирует proto-stubs всех доменов)
kacho-deploy   ← Dockerfile'ы COPY ../kacho-*; build-context = parent dir
kacho-ui/test  ← зависят от REST api-gateway в runtime (не build)
```

Связь — `replace ../` (осознанный выбор для polyrepo-dev в одном дереве; переход на
versioned modules — под релизную фазу). Проверка: `grep -rn "replace github.com/PRO-Robotech" project/*/go.mod`.

## Runtime cross-domain edges (gRPC service→service; НЕ build-зависимость)

- `kacho-vpc → kacho-geo` — валидация `zone_id` Subnet/AddressPool (`geo.v1.ZoneService.Get`); Geography — домен geo (KAC-эпик #82). Заменяет прежнее ложное ребро `vpc→compute (zone)`.
- `kacho-compute → kacho-geo` — валидация `Instance.zone_id` (`geo.v1.ZoneService.Get`). Geography больше не «своя» таблица compute — теперь peer-валидация через geo-client (KAC-эпик #82).
- `kacho-nlb → kacho-geo` — валидация `region_id` LoadBalancer/TargetGroup (`geo.v1.RegionService.Get`, sync precheck на request-path, кэша нет). Заменяет прежнее ложное ребро `nlb→compute (region)`.
- `kacho-geo → kacho-iam` — `InternalIAMService.Check` (authz-gate на каждом RPC обоих листенеров; read-RPC `system_viewer`-floor, admin-CRUD `system_admin`). geo — leaf-консумер только iam (как любой сервис).
- `kacho-compute → kacho-vpc` — валидация NIC-spec (Subnet/SecurityGroup) + IPAM-аллокация Address.
- `kacho-nlb → kacho-compute` — резолв Instance-таргетов (`compute.v1.InstanceService.Get`); **только** для Instance (НЕ для geography — region-валидация теперь `nlb→geo`).
- `* → kacho-iam` — `ProjectService.Get` (existence + account lookup, leaf-owner) + `InternalIAMService.Check` (authz-gate).
- `kacho-vpc → kacho-iam` (fgaproxy, SEC-A) — `InternalIAMService.RegisterResource`/`UnregisterResource`: запись/снятие
  owner-hierarchy-tuple в FGA через IAM (модули не ходят в FGA напрямую). Internal-only :9091, идемпотентно, at-least-once
  через transactional-outbox (SEC-D). Least-priv: ReBAC `fga_writer` @ `iam_fgaproxy:system`.
- `kacho-compute → kacho-iam` (fgaproxy, SEC-A) — то же ребро: `RegisterResource`/`UnregisterResource` для owner-tuple
  compute-ресурсов. Internal-only :9091, идемпотентно, fgaproxy least-priv `fga_writer` @ `iam_fgaproxy:system`.
- `kacho-vpc-operator → kacho-vpc` (SEC-G) — sync-poll read: `SubnetService.List` / `NetworkService.Get` /
  `NetworkInterfaceService.Get` / `AddressService.Get`. **mTLS** (отдельный operator client-cert, SAN
  `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`); per-edge `enable` (`enable=false` → insecure
  back-compat). Least-priv: персональный SA оператора с **read-only ReBAC viewer**-tuples (SEC-C seed), без editor/мутаций.
  Оператор — **вне build-графа** control-plane (sibling, не импортируется по build).
- `kacho-vpc-operator → kacho-iam` (SEC-G) — sync-poll read (ns-operator fan-out): exempt `AccountService.List`
  (membership scope-filter) → viewer-scoped `ProjectService.List`. **mTLS** (тот же operator client-cert);
  per-edge `enable`. SA освобождён от `required_acr_min` (service→service, §4.1.2).

**Циклы запрещены**: если A зовёт B — B не зовёт A. Новое ребро фиксируется здесь как runtime-edge.
- `kacho-geo` — **leaf** (как iam): geo никого, кроме iam (authz-Check), не зовёт. Рёбра `vpc→geo` / `compute→geo` /
  `nlb→geo` однонаправлены (geo не вызывает consumer'ов обратно) → циклов с geo нет. После выноса Geography ложные
  «ради geography» рёбра `vpc→compute` и `nlb→compute (region)` удалены.
- `kacho-compute → kacho-vpc` (NIC/IPAM) — единственное оставшееся ребро между vpc и compute, **одностороннее**:
  vpc больше не зовёт compute (zone-валидация ушла в geo). Семантического цикла нет.
Регламент кросс-доменных ссылок — `data-integrity.md`.

## Порядок работы / merge для кросс-репо фичи (топосортировка графа)

1. `kacho-proto` (новый `.proto` + регенерация `gen/`, `buf lint`/`breaking` зелёные)
2. `kacho-corelib` (если меняются общие пакеты)
3. сервис(ы) (`kacho-geo`/`kacho-iam`/`kacho-vpc`/`kacho-compute` — между собой в любом порядке; leaf-домены iam/geo обычно первыми, т.к. их зовут consumer'ы)
4. `kacho-api-gateway` (регистрация RPC: public mux / internal mux)
5. `kacho-deploy` (helm/compose)
6. `kacho-workspace` (docs/specs)

Пока вышестоящее не в `main` — нижестоящий CI временно пиннит sibling к feature-ветке
(`ref:` в `.github/workflows/ci.yaml`); после merge — `ref: main`. Кросс-репо эпик —
tracking-issue в `kacho-workspace` (метка `epic`) + per-repo issue с `Blocked by PRO-Robotech/<repo>#<n>`.
