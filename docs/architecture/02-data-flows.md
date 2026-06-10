# 02 — Data Flows

Sequence-диаграммы ключевых сценариев. Все примеры — то, что **реально**
происходит в коде на момент написания (см. соответствующие service/repo).

## Содержание

1. [Setup: Account → Project](#1-setup-account--project)
2. [Network create + автогенерация default-SG](#2-network-create)
3. [External Address allocate с cascade](#3-external-address-allocate-с-cascade)
4. [Internal Address allocate из Subnet CIDR](#4-internal-address-allocate)
5. [Operations LRO polling](#5-operations-lro)
6. [InternalWatchService outbox stream](#6-internalwatchservice-outbox-stream)
7. [Admin: задать pool-selector на Project](#7-admin-задать-pool-selector-на-project)

## 1. Setup: Account → Project

```mermaid
sequenceDiagram
  autonumber
  participant U as User (UI/CLI)
  participant GW as api-gateway
  participant IAM as kacho-iam
  participant DB as pg-iam

  U->>GW: POST /iam/v1/accounts<br/>{name:"acme"}
  GW->>IAM: AccountService.Create
  IAM->>IAM: Validate name (Kachō name regex)
  IAM->>DB: INSERT account + outbox
  IAM-->>GW: Operation{id:opiam..., done:false, metadata:{accountId:...}}
  GW-->>U: 200 + Operation

  loop polling 1-2s
    U->>GW: GET /operations/{id}
    GW->>IAM: OperationService.Get
    IAM-->>GW: Operation{done:true, response:Account}
    GW-->>U: 200 + Operation done
  end

  Note over U,DB: повторить для Project (FK account_id)
```

Ключевые инварианты:
- `Project.UNIQUE(account_id, name)` — Create падает с `ALREADY_EXISTS`.
- `Project.account_id` иммутабельно через Update (immutable after Create).
- Malformed id → sync `InvalidArgument "invalid <res> id '<X>'"` первым стейтментом
  RPC; well-formed-но-нет → `NotFound` через `repo.Get`.

## 2. Network create

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant GW as api-gateway
  participant V as kacho-vpc
  participant IAM as kacho-iam
  participant DB as pg-vpc

  U->>GW: POST /vpc/v1/networks {projectId, name:"prod"}
  GW->>V: NetworkService.Create
  V->>V: sync validate (NameVPC, labels, mask)
  V->>V: ids.NewID(PrefixNetwork) → "net..."
  V->>DB: INSERT operation (sync)
  V-->>GW: Operation{id:opvpc..., metadata:{networkId:net...}}
  GW-->>U: 200 + Operation

  rect rgb(255,247,230)
  Note over V: async worker — operations.Run(...)
  V->>IAM: ProjectService.Get(project_id)
  alt project not found
    V->>DB: UPDATE operations SET done=true, error=NotFound
  else project OK
    V->>DB: BEGIN
    V->>DB: INSERT networks (id, project_id, name, …)
    V->>DB: INSERT vpc_outbox (Network CREATED) → pg_notify
    V->>DB: COMMIT
    V->>V: short = first-8-chars(net_id)
    V->>DB: BEGIN (default-SG)
    V->>DB: INSERT security_groups (default-sg-{short}, network_id, default_for_network=true)
    V->>DB: UPDATE networks SET default_security_group_id=...
    V->>DB: INSERT vpc_outbox (SG CREATED, Network UPDATED)
    V->>DB: COMMIT
    V->>DB: UPDATE operations SET done=true, response=Network
  end
  end
```

Особенности:
- **Inline default-SG creation** — раньше делал отдельный reconciler-loop, позже
  удалили, всё inline в worker'е операции.
- Error mapping: UNIQUE-violation `(project_id, name)` (миграция 0018) → `ALREADY_EXISTS`.

## 3. External Address allocate с cascade

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant GW as api-gateway
  participant V as kacho-vpc
  participant IAM as kacho-iam
  participant DB as pg-vpc

  U->>GW: POST /vpc/v1/addresses<br/>{projectId, externalIpv4AddressSpec:{zoneId:"ru-central1-a"}}
  GW->>V: AddressService.Create
  V->>V: sync validate (oneof spec, zone whitelist)
  V-->>GW: Operation{id:opvpc..., addressId:adr...}
  GW-->>U: 200 + Operation

  rect rgb(255,247,230)
  Note over V: async worker — doCreate
  V->>IAM: ProjectService.Get(project_id)
  V->>DB: INSERT addresses (external_ipv4 spec, address="")

  Note over V,DB: AddressAllocator.AllocateExternalIP(addressID)
  V->>V: ResolvePoolForAddress(addressID) → cascade:

  Note over V,DB: Step 1: address_pool_address_override[addressID]
  V->>DB: SELECT pool_id FROM address_pool_address_override WHERE address_id=$1
  alt found
    V->>DB: SELECT pool by id → return ResolvedPool{matched_via:"address_override"}
  else miss

    Note over V,DB: Step 2: address_pool_network_default[networkID]<br/>(только internal IP — у external нет network_id)

    Note over V,DB: Step 3: project-label-selector
    V->>IAM: ProjectService.Get(project_id)
    V->>DB: SELECT selector FROM project_pool_selector WHERE project_id=$1
    alt selector present
      V->>DB: SELECT pool FROM address_pools<br/>WHERE selector_labels @> $selector<br/>AND (zone_id=$zone OR zone_id IS NULL)<br/>ORDER BY (size_diff ASC, priority DESC) LIMIT 1
      V->>V: matched_via:"label_selector"
    else no selector or no match

      Note over V,DB: Step 4: zone_default
      V->>DB: SELECT pool WHERE is_default=true AND zone_id=$zone AND kind=$kind
      V->>V: matched_via:"zone_default"

      Note over V,DB: Step 5: global_default
      V->>DB: SELECT pool WHERE is_default=true AND zone_id IS NULL AND kind=$kind
      V->>V: matched_via:"global_default"
    end
  end

  Note over V,DB: Pick IP в выбранном pool
  loop for attempt in 1..max
    V->>V: pickRandomIPv4(cidr)
    V->>DB: UPDATE addresses SET external_ipv4.address=$ip<br/>(WHERE id=...)
    alt UNIQUE violation
      V->>V: continue (try другой IP)
    else success
      V->>DB: INSERT vpc_outbox (Address UPDATED)
      V->>DB: UPDATE operations SET done, response=Address
    end
  end

  alt все CIDR исчерпаны
    V-->>GW: ResourceExhausted "address pool X exhausted (no free IP in any cidr_block)"
  end
  end
```

Подробности cascade — в [03-ipam.md](03-ipam.md).

## 4. Internal Address allocate

То же что external, но:
- Нет `external_ipv4_spec`, есть `internal_ipv4_address_spec.subnet_id`.
- `AllocateInternalIP`: zone и pool не нужны — берётся CIDR из subnet.
- Step 2 cascade (`network_default`) активен — через `subnet.network_id`.
- UNIQUE на `(internal_subnet_id, address)` — `addresses_internal_subnet_ip_uniq` (computed-column на subnet_id, миграция 0006).

## 5. Operations LRO

```mermaid
sequenceDiagram
  participant U as User
  participant GW as api-gateway
  participant OPS as opsproxy (in-process)
  participant V as kacho-vpc
  participant DB as pg-vpc

  U->>GW: POST /vpc/v1/networks
  GW->>V: NetworkService.Create
  V->>DB: INSERT operations(id=opvpc..., done=false)
  V-->>GW: Operation{done:false}
  GW-->>U: Operation
  Note right of V: worker goroutine крутит doCreate

  loop polling
    U->>GW: GET /operations/opvpc...
    GW->>OPS: OperationService.Get(id)
    OPS->>OPS: prefix("opvpc") → kacho-vpc backend
    OPS->>V: OperationService.Get
    V->>DB: SELECT * FROM operations WHERE id=$1
    V-->>OPS: Operation{done?, response?, error?}
    OPS-->>GW: Operation
    GW-->>U: 200
  end
```

`opsproxy` — in-process router в api-gateway, который смотрит на ID prefix
(`opvpc...` → vpc, `opiam...` → iam) и делегирует на нужный backend.
Это даёт **один** `OperationService` URL для клиента без знания о том, какой
backend выполнил мутацию. Watch-стриминга на публичной поверхности нет — клиент
поллит `OperationService.Get(id)` до `done=true` (и `List` 2–5 c для актуализации
коллекций).

## 6. InternalWatchService outbox stream

Только для server-to-server (UI/CLI не используют; на external TLS-endpoint не
маршрутизируется — internal mux :9091).

```mermaid
sequenceDiagram
  participant Client as gRPC Client
  participant V as kacho-vpc :9091
  participant CONN as pgx.Conn
  participant DB as pg-vpc

  Client->>V: InternalWatchService.Watch(from_sequence_no)
  V->>CONN: pool.Acquire — dedicated conn
  V->>CONN: LISTEN vpc_outbox

  V->>DB: catchup: SELECT * FROM vpc_outbox WHERE seq > from_seq
  loop catchup rows
    V-->>Client: Event{seq, resource_type, resource_id, op, payload}
  end

  loop forever
    V->>CONN: WaitForNotification(ctx)
    CONN->>V: pg_notify('vpc_outbox', '<sequence_no>')
    V->>DB: SELECT * FROM vpc_outbox WHERE seq = $1
    V-->>Client: Event{...}
  end

  Note over V,CONN: defer UNLISTEN + Release()
```

Тригер `vpc_outbox_notify_trg` на INSERT в `vpc_outbox` шлёт `pg_notify`. Это
internal-механизм журнала событий (транзакционный outbox), а не публичный Watch
RPC.

## 7. Admin: задать pool-selector на Project

```mermaid
sequenceDiagram
  participant Admin as Admin (kachoctl/UI)
  participant GW as api-gateway
  participant V as kacho-vpc :9091

  Admin->>GW: POST /vpc/v1/projects/{project_id}/poolSelector<br/>{selector:{tier:"premium"}, set_by:"admin@kacho"}
  GW->>V: InternalProjectService.SetPoolSelector
  V->>V: validate project_id non-empty
  V->>V: AddressPoolService.SetProjectPoolSelector
  V->>V: projectSel.Set(project_id, selector, set_by)
  V->>V: BEGIN
  V->>V: INSERT INTO project_pool_selector ON CONFLICT UPDATE
  V->>V: INSERT vpc_outbox (ProjectPoolSelector UPDATED)
  V->>V: COMMIT
  V-->>GW: SetProjectPoolSelectorResponse{}
  GW-->>Admin: 200 {}
```

После set'а **следующий** `AllocateExternalIP` для Address из этого project'а
будет использовать selector в cascade Step 3.

## Где смотреть детали

| Поток | Код |
|---|---|
| Network create + default-SG | `kacho-vpc/internal/service/network.go::doCreate` |
| Address allocate cascade | `kacho-vpc/internal/service/address_pool_service.go::resolveWithRunnerUp` |
| AllocateExternalIP retry loop | `kacho-vpc/internal/service/address_allocate.go::AllocateExternalIP` |
| Operations worker | `kacho-corelib/operations/run.go` |
| Outbox + LISTEN/NOTIFY | `kacho-vpc/internal/handler/internal_watch_handler.go` |
| ProjectClient.Get | `kacho-vpc/internal/clients/iam_client.go` |
