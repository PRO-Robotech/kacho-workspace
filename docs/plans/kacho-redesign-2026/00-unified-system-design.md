# Kachō — Unified Control-Plane System Design

*Единый продуктовый систем-дизайн, сводящий 6 сошедшихся модульных форм (geo · iam · vpc · compute · nlb · registry) вокруг compute-эталона-якоря. Не федерация 6 API — ОДИН control-plane продукт с единым хребтом. Статус: **НЕ готов к немедленному старту всего графа** — Фаза 0 стартует только после закрытия governance-блокеров B1/B3 и приземления change-set'а в `api-conventions.md` (§9). geo+iam (Фаза 1) не блокированы. `storage` **втянут в свод как first-class Phase-2 owner** (см. §2/§7): он — жёсткая зависимость якоря-compute (boot-Volume/ImageCatalog/attach-саги), поэтому не может оставаться «вне свода» — compute GA gated-by storage convergence (B10).*

**Два leaf-фундамента, на которые опирается всё остальное:**
- **geo** — владелец оси размещения (Region/Zone); любая placement-coherence-проверка резолвит `zone.regionId` здесь. Зовёт только iam.
- **iam** — владелец дерева аренды (Account→Project) и единственный источник грантов (AccessBinding→FGA); per-RPC authz-gate всех доменов. Не зовёт никого (Hydra — внешний, под фасадом).

---

## 1. Общий хребет — матрица конвенций

Каждый сервис ОБЯЗАН соблюдать 12 конвенций спайна. Отклонение допустимо **только** как задокументированный by-construction carve-out (не забытьё).

| # | Конвенция | geo | iam | vpc | compute | nlb | registry | Оправданное отклонение |
|---|---|---|---|---|---|---|---|---|
| 1 | **Flat resource** (нет envelope spec/status/metadata; `°`=output-only; enum inline gloss) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — (universal) |
| 2 | **Read sync / mutate async→Operation** (id в `metadata` сразу; poll `OperationService.Get`; Watch нет) | ✓* | ✓ | ✓ | ✓ | ✓ | ✓ | geo: Operation `done:true` **сразу** (config-INSERT, без саги) — spine-preserving, unwrap `.response`. iam: 2 declared sync-мутации (`OAuthClient:token`, `AuthService.TokenExchange` — derivation, не durable-мутация) |
| 3 | **`Operation.done`=DURABLE, не downstream-видимость** (owner-tuple EC; bounded client-retry; confirm-gate запрещён, ban #9) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | registry: EC-петля замыкается **client-side** bounded-retry-поллом `GetEffectiveAccess` (docker CLI не ретраит `NAME_UNKNOWN`) — это **клиентский** readiness-poll, НЕ серверный барьер; `GetEffectiveAccess` НЕ гейтит `Operation.done`, underlying `Check` — strong-consistency-read или bounded-retry (см. §5.4) |
| 4 | **One-shot Create** (зависимые под-ресурсы `*Specs` в ОДНОЙ Operation у owner) | ✓ (`zoneSpecs`) | ✓ (Account→proj+owner-binding; SA→OAuthClient+grant) | ✓ (Network→default SG/RT; NIC `addressSpecs`) | ✓ (NIC/Volume attach-саги + **compensation-path**, §5.4) | ✓ (LB→listener→TG→HC→VIP) | ✓ (Repository overlay+adopt) | — |
| 5 | **Discovery рядом с мутацией** (sync-каталог, item несёт paste-ready `requestFragment`) | ✓ (geo **сам** — каталог placement) | ✓ (`RoleService.List(assignableOn)`→`grantFragment`) | ✓ (`ListPlaceableZones`/`SuggestCidr`/`ListLaunchableSubnets`) | ✓ (`MachineType`/`ImageCatalog`/`VolumeType`) | ✓ (`:regions`/`:addableInstances`/`:vipAnchorCandidates`) | ✓ (`ListNamespaces`→`namespaceGrantTemplate`) | — |
| 6 | **`validateOnly:true`** — sync dry-run (полная валидация, без мутации/Operation/state-gate; `warnings[]`+resolved-echo) | ✓ | ✓ | ✓ | ✓ (**не** триггерит STOPPED-gate — pre-Stop capacity-check) | ✓ | ✓ (echo pre-push `fgaObject` для grant-до-push) | — |
| 7 | **Reference-law по классу** (within→FK; scope-coord→peer-validate; dependency→handle-wrapper) | ✓ (только class-A `zone.regionId`) | ✓ | ✓ | ✓ | ✓ | ✓ | **3-way naming disambiguation** (B1, §8/§9): `ResourceRef{type,id}` (iam AccessBinding target — closed authzmap.ObjectType table, БЕЗ name) — **уже landed**; generic `Referrer{type,id,name°}` (cross-owner dependency handle) — **уже landed** в compute; registry OCI-1.1 artifact-граф получает **ТРЕТЬЕ** имя (`OciReferrer`/`ArtifactRef`). Три разных типа, три разные семантики — НЕ overload одного идентификатора |
| 8 | **Two-projection** (инфра-чувствительное — только Internal* :9091) | ✓ (сырой `status` UP/DOWN + `infra°` — Internal, и readable, и writable) | ✓ (FGA-tuples, compiled `permissions`, `external_id`-map — Internal) | ✓ (`vrfId`/underlay/AddressPool free-list) | ✓ (node/host/scheduler/topologyKey) | ✓ (dataplane-node/underlay/vrf) | ✓ (engineNamespace/bucket/blob-layout) | — |
| 9 | **AuthN+AuthZ на КАЖДОМ RPC обоих листенеров** (mTLS/JWT; per-RPC `Check`; object-scoped `scope_extractor`; fail-closed) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Documented exceptions: iam JWKS-route `:9097` (public-key-only, server-TLS); geo public-read **project-scope EXEMPT** (каждый tenant читает каталог); `AuthService.Login/Callback` (pre-auth OIDC) |
| 10 | **Placement-coherence** (дискриминатор `placementType∈{ZONAL,REGIONAL}`; ZONAL↔ZONAL та же зона; REGIONAL=anycast) | якорь-owner | **N/A by construction** (identity-плоскость глобальна) | ✓ (Subnet — canonical anchor; Gateway) | ✓ (Instance↔Subnet/Volume; PlacementGroup) | ✓ (LB `placement`; TG region-coherent, zone-coherent на wire к ZONAL) | REGIONAL-only (OCI-контент region-scoped; `placementType` always-REGIONAL const — LEAN carve-out) | iam: осознанное исключение (§16 iam) |
| 11 | **Единый тон ошибок** (`"<Resource> <id> not found"`; `"<field> is immutable after <R>.Create"`; коды INVALID_ARGUMENT/NOT_FOUND/FAILED_PRECONDITION/ALREADY_EXISTS/UNAVAILABLE/INTERNAL-opaque; malformed-id первым стейтментом) | ✓ (+ by-lane reason-token в `rpc.Status.details`) | ✓ (declared-exception: User-mirror `"…read-only…"`, тот же код+`details{reason,field}`) | ✓ | ✓ | ✓ | ✓ | by-lane code-split (direct-read→NOT_FOUND / peer-validate→FAILED_PRECONDITION) — **PROPOSED**, приземляется Phase-0 governance change-set'ом в `api-conventions.md` (§9); до merge — не «landed» |
| 12 | **Формат** (JSON camelCase; id=3-char prefix+crockford-base32; UNIQUE(project,name) partial; timestamps truncate-to-seconds) | slug-id carve-out | ✓ | ✓ | ✓ | ✓ | Namespace `ns-`; Repository/Tag/Image — natural/content-key | **id-prefix hyphen-форма PENDING (B3)** — драйв `ins-`/`prj-`/`ns-` (с дефисом) vs `net`/`sub`/`nlb` (без); фиксируется Phase-0 в `corevalidate` (рекомендация: **с дефисом**), vpc/nlb приводятся. geo: **THE ONE** id carve-out (`ru-central1` slug). registry: OCI natural-keys |

\* geo public-поверхность — **чистая read-discovery, ноль tenant-мутаций**; async-обёртка живёт только на admin Internal-CRUD.

> **Doc-truthfulness (LOW-finding):** conv-11 by-lane split, conv-12 id-prefix и conv-7 ref-naming помечены **PROPOSED**, а не «landed» — их приземляет **ещё не смёрженный** Phase-0 governance change-set (§9). Контрибьютор НЕ должен строить против текста, которого в `api-conventions.md`/`data-integrity.md` пока нет. «Landed» проставляется только после фактического merge change-set'а.

---

## 2. Карта ресурсов (по сервису)

### geo (`kacho.cloud.geo.v1`) — leaf, placement-axis owner
| Ресурс | id | Owner-table | Ключевые решения |
|---|---|---|---|
| **Region** | `ru-central1` (slug) | `kacho_geo.regions` | REGIONAL anycast-якорь; cluster-scoped (нет project); `openForPlacement°`=status==UP; **сырой `status`+`infra°` только Internal** (и read, и write); fresh=DOWN fail-safe |
| **Zone** | `ru-central1-a` (slug) | `kacho_geo.zones` | class-A FK `region_id` RESTRICT; coupling `zone.id==regionId+"-"+suffix` (строгий startsWith); `placementBlockedReason°∈{NONE,ZONE_DOWN,REGION_DOWN}` — **accepted two-projection carve-out** (§5.1): tenant-facing «могу ли разместить», грубее сырого host-class/capacity (те — Internal) |

Ось (ZONAL/REGIONAL) НЕ эмитится полем — consumer выводит по вызванному сервису. Мутации→Operation `done:true` сразу.

### iam (`kacho.cloud.iam.v1`) — leaf, tenancy+authz owner
| Ресурс | id | Ключевые решения |
|---|---|---|
| **Account** | `acc-` | Top-level; `ownerUserId°` derived из caller; Create-сага→default-Project+owner-AccessBinding |
| **Project** | `prj-` | Leaf-workspace (строго 2 уровня, без вложенности); `accountId` immutable (Move удалён) |
| **User** | `usr-` | Output-mirror внешнего IdP; **нет public Create**; **нет `accountId`** (членство derived); Update только `labels` |
| **UserInvitation** | `inv-` | Пред-провижн по email до входа; accept=side-effect первого OIDC-login. **email→usr- remap материализуется reconciler'ом** (§5.4): pending email-grant хранится как intent, на первом login резолвится в `usr-<id>`-tuple в ограниченном окне |
| **ServiceAccount** | `sva-` | IAM-native; `defaultProjectId`=informational (НЕ authz); `status↔{ACTIVE,DISABLED}`; public `:forceLogout` — **семантика «no-new-tokens + bounded revocation window = access-token TTL»** (B11, §5.3), НЕ мгновенный hard-cutoff на stateless-JWKS-верификаторах (registry data-plane верит подпись без introspection) |
| **Group** | `grp-` | Полиморфные members; member-tuple **materialize через outbox-emit + EC** (НЕ «co-commit»: внешний FGA не может атомарно co-commit'иться в DB-tx; intent в `fga_outbox` → at-least-once drainer → reconciler покрывает `Group#member`) |
| **Role** | `rol-` | Allow-only verb-bundle; `definitionTier` (**НЕ** «scope»); `isSystem°`=derived(cluster-tier); system-catalog (viewer/editor/admin/owner + narrow `registry.puller`/`compute.operator`/…) |
| **AccessBinding** | `acb-` | Единственная grant-запись (subjects+role+scope-anchor+target); `target`=`ResourceRef{type,id}` (closed-table, БЕЗ name); `target` **обязателен** (least-priv); `Delete`=hard / `:revoke`=soft; subject `EMAIL` grant-by-email (pending-intent до login — см. UserInvitation); **`roleId` seam PENDING (B6)**: registry-templates шлют dotted system-role NAME (`registry.repoCreator`), iam-поле=FK на `rol-` id → iam-side решение (alt-reference-резолв vs rename поля) |
| **OAuthClient** | (sub-ресурс SA) | one-time `clientSecret°`; `:token`=**sync** IAM-фасад→Bearer |

### vpc (`kacho.cloud.vpc.v1`) — VRF/network owner
| Ресурс | id | Ключевые решения |
|---|---|---|
| **Network** | `net` | Изолированный SRv6-VRF + declared супернет `ipv4/6CidrBlocks[]`; auto default-SG+RT; op-in-response |
| **Subnet** | `sub` | **Единственный placement-anchor**; `placementType°` derived из `zoneId`XOR`regionId` (DB-CHECK); op-in-response |
| **SecurityGroup** | `scg` | Stateful на NIC (NACL нет by design); rules через verb-pair `:add-rule`/`:remove-rule` + per-rule OCC |
| **RouteTable** | `rtb` | `staticRoutes` через `:add-route`; `natGatewayId` vs `nextHopAddress`; coherence-gate Subnet↔Gateway |
| **Gateway** | `gwy` | NAT/egress (internet-gw-ресурса нет); `placementType°`; shared default-route target обязан быть REGIONAL |
| **NetworkInterface** | `nic` | First-class; `usedBy°` polymorphic `Referrer`; **poll** (не op-in-response — lifecycle-присутствие); `effectiveSecurityGroupIds°` |
| **Address** | `adr` | IPAM lease (1 IP/строка); `scope°` derived из binding-ref; `usedBy°` CAS; **recycle-on-delete обязателен** (§5.9): Delete и NIC/VIP-teardown возвращают lease в AddressPool free-list **атомарно** |
| **AddressPool** | `apl` | **Internal-only**, admin/cloud-level; free-list — Internal-проекция |

### compute (`kacho.cloud.compute.v1`) — ЭТАЛОН-ЯКОРЬ, workload owner
| Ресурс | id | Ключевые решения |
|---|---|---|
| **Instance** | `ins-` | Единственный вычислит. ресурс; `instanceKind∈{VM,CONTAINER}` (oneof `vmSpec`/`containerSpec`); one-shot launch (NIC/Volume/ssh специфицируются, worker разворачивает саги **с compensation-path**, §5.4); `serviceAccountId`=**class-C `Referrer{iam.service_account}`** (graceful-dangling — B2 разрешён в пользу iam-версии, §8) |
| **MachineType** | `mt-` | Sync-каталог; единственный канал sizing; GPU=гранулярность каталога (`gpu-a100-8`), не поле |
| **PlacementGroup** | `plg-` | Ось `spread∈{ZONE_SPREAD,HOST_SPREAD,PARTITION,PACK}` первична; `placementType°` derived; `maxSkew=\|max−min\|` |
| **ImageCatalog / VolumeType** | (проекция) / `vt-` | Sync-discovery; thin-проекция над storage/registry (ownership не меняется). **bootSource несёт owner-дискриминатор** (B5-note, §5): `imageKind∈{STORAGE_IMAGE,OCI_IMAGE}` (или `Referrer.type` `storage.image`/`registry.image`) — bare `imageId` НИКОГДА не двусмыслен между двумя owner'ами |

### storage (`kacho.cloud.storage.v1`) — **first-class Phase-2 owner** (втянут в свод, B10)
| Ресурс | id | Ключевые решения |
|---|---|---|
| **Volume** | `vol-` | ZONAL block-lease; attach через owner (compute→storage сага); placement-coherent с Instance (та же зона) |
| **Image** | `img-` | **VM boot-image** (ортогонален registry OCI-Image — разные owner'ы, разные Referrer-токены `storage.image`≠`registry.image`; см. B5) |
| **Snapshot** | `snp-` | Point-in-time Volume; region-scoped restore |

> storage — жёсткая зависимость якоря-compute (boot-Volume/ImageCatalog/secondary-attach). Его собственная сходимость (CS-1 spec) идёт **в этом своде** Phase-2 step 5; **compute GA gated-by storage convergence** (§9 B10) — якорь не может тихо зависеть от несошедшегося owner'а.

### nlb (`kacho.cloud.nlb.v1`) — regional L4 LB owner
| Ресурс | id | Ключевые решения |
|---|---|---|
| **NetworkLoadBalancer** | `nlb` | `regionId` immutable; один input-дискриминатор `placement∈{EXTERNAL_REGIONAL,INTERNAL_REGIONAL,INTERNAL_ZONAL}`; `type°`/`placementType°` derived; `adminState` (не compute `:start/:stop`); **несёт VIP** — один `vpc.Address` на семейство, источник per-family на Create (`v4Source`/`v6Source`), наружу `v4AddressId°`/`v6AddressId°` |
| **Listener** | `lst` | `(port, protocol)` на VIP родительского LB — **собственного адреса не несёт и не аллоцирует**; **единственный** authoritative `targetGroupId`; Create — чистый INSERT, Delete VIP не освобождает |
| **TargetGroup** | `tgr` | Region-scoped, LB-agnostic, reusable; `port`=единственный backend-порт; embedded HealthCheck (oneof-replace) |
| **Target** (child) | — | 4-way identity (instance/nic/ipRef/externalIp); 3 ортогональные оси→`servingTraffic°`. **instance-target resolution PENDING (B9)**: `instance→primary NIC→primary IP` синхронизируется с compute `AttachNetworkInterface`-редизайном; «primary NIC» (lowest-index vs explicit-flag) + multi-NIC-ambiguity определяются до GA; `nic`/`ipRef`/`externalIp` — load-bearing fallback |

### registry (`kacho.cloud.registry.v1`) — OCI namespace owner
| Ресурс | id | Ключевые решения |
|---|---|---|
| **Namespace** | `ns-` | Group-of-images (≠ k8s ns); `name` (UNIQUE(project,name)) ⟂ `globalSlug°`; REGIONAL always; **FGA-тип `registry_registry` заморожен (Rosetta)** — scope-строка `registry_registry:ns-…` читается как «другой продукт» (B7, §9): going-forward iam-side alias `registry_namespace:` |
| **Repository** | natural `(namespaceId,name)` | Overlay⟂projection; `lifecycle∈{DURABLE,EPHEMERAL}`; явный Create=DURABLE; имя несёт `/` |
| **Tag / Image / OciReferrer** | natural/content-key | Read-only projections движка (материализуются на `docker push`); **`OciReferrer`** (переименован с `Referrer`, B1)=OCI-1.1 artifact-граф |

---

## 3. RPC-паттерн (единый)

**Каноничный сервис-шаблон (все домены):**
```
rpc Get   (…) returns (Resource);           // sync
rpc List  (…) returns (ListResponse);       // sync — cursor (created_at,id), filter-whitelist, listauthz row-filter
rpc Create(…) returns (operation.Operation);// async — validateOnly:true → sync dry-run
rpc Update(…) returns (operation.Operation);// async — update_mask known-set, mutability-классы
rpc Delete(…) returns (operation.Operation);// async
rpc <Action>(…) returns (operation.Operation); // :verb-действия → Operation
// + OperationService.Get (sync poll, GET /<svc>/v1/operations/{id})
```

**Инварианты шаблона:** `id`/ключ ресурса — в `Operation.metadata` СРАЗУ (до `done`). `validateOnly:true` → sync `{valid, warnings[], resolved{…}}` без Operation/state-gate. Discovery-`List` — sync, item несёт paste-ready фрагмент. Internal-листенер (:9091) несёт те же authz-Check.

**Per-сервис отличия от шаблона (все — spine-preserving):**

| Сервис | Отличие |
|---|---|
| **geo** | Ноль public-мутаций (read-discovery); CRUD — admin Internal, Operation `done:true` **немедленно**, unwrap `.response` |
| **iam** | `AuthService.{Login,Callback,TokenExchange}`, `OAuthClient:token` — **sync**; `AuthorizeService.{Check,BatchCheck,ListObjects,ListSubjects,ExpandAccess}` — единая introspection-поверхность |
| **vpc** | **op-in-response** для statusless (Network/Subnet/SG/RT/Gateway); NIC/Address — **poll**. Collection-мутации verb-pair (`:add-rule`/`:add-route`/`:add-cidr-blocks`) |
| **compute** | `Start/Stop/Reboot/Reinstall/AttachVolume/AttachNetworkInterface` (:verb); `GetInstanceOutput` sync; power-state сохраняется; launch-worker несёт **cross-service compensation** (§5.4) |
| **nlb** | `AddTargets/RemoveTargets(2-phase drain)/UpdateTargets`; `GetTargetStates` sync; enable/disable=`adminState`; нет `AttachTargetGroup` |
| **registry** | Мутации prefix `epd`; CP-only DELETE tag/image (data-plane→`405`); data-plane docker (OCI Distribution) — thin auth-proxy на `:443`; `GetEffectiveAccess` sync — **client-side** readiness-poll (не серверный барьер) |

---

## 4. Cross-service рёбра — runtime-граф (АЦИКЛИЧЕН)

Рёбра — **runtime gRPC service→service** (НЕ build-зависимость; DB-per-service, versioned-modules, `replace` запрещён). A→B = «A зовёт B».

```
                          ┌─────────────────────────── iam (LEAF, зовёт никого) ◄── Hydra (внешний, под фасадом)
                          │        ▲ ▲ ▲ ▲ ▲ ▲ ▲
        ProjectService.Get│        │ │ │ │ │ │ └── registry ─┐ Check + ProjectService.Get + JWKS-fetch(:9097)
        + Check(:9091)    │        │ │ │ │ │ └──── geo       │ Check(:9091, authz на обоих листенерах)
        + fgaproxy(:9091) │        │ │ │ │ └────── nlb       │
                          │        │ │ │ └──────── compute   │  (registry→iam ТОЛЬКО; НИКОГДА iam→registry)
                          │        │ │ └────────── vpc       │
                          │        │ └──────────── storage   │
   geo ◄──────────────────┼────────┤                         │
   (Region/Zone.Get,      │        │                         │
    peer-validate)   vpc──┘  compute──┐  nlb──┐               │
        ▲  ▲  ▲              │  │  │   │  │  │                │
        │  │  └── nlb→geo    │  │  │   │  │  └── nlb→geo (region)
        │  └───── compute→geo│  │  │   │  └───── nlb→vpc (Address/Subnet/SG для VIP)
        └──────── vpc→geo    │  │  │   └──────── nlb→compute (Instance target resolve)
                             │  │  └── compute→registry (boot-image pull resolve + puller-tuple EC)
                             │  └───── compute→storage (boot-Volume / image materialize)
                             └──────── compute→vpc (NIC-spec + IPAM Address alloc + compensation Free)
```

**Полный список рёбер:**

| Ребро | Sync/Async | Зачем | Класс seam-ссылки |
|---|---|---|---|
| `* → iam` `ProjectService.Get` | sync | existence + account lookup (scope-validate) | B (scope-coord `projectId`) |
| `* → iam` `InternalIAMService.Check` (:9091) | sync | per-RPC authz-gate | — (authz) |
| `{vpc,compute,storage} → iam` fgaproxy `RegisterResource` (:9091) | async (outbox) | owner-tuple в FGA | — (least-priv `fga_writer`) |
| `vpc → geo` `ZoneService.Get` | sync | validate Subnet/Gateway `zoneId` | B (`zoneId`) |
| `compute → geo` `ZoneService.Get` | sync | validate Instance `zoneId` | B |
| `nlb → geo` `RegionService.Get` | sync | validate LB/TG `regionId` | B (`regionId`) |
| `geo → iam` `Check` | sync | authz на обоих листенерах | — |
| `compute → vpc` `Subnet/SG` validate + `InternalAddressService.Allocate`+`SetReference`; **+compensation `Free`/`ClearReference` на launch-fail** | sync/CAS | NIC-spec + IPAM + rollback | B (Subnet/SG) + within-owner CAS |
| `nlb → vpc` `AddressService`/`SetReference` + Subnet/SG | sync/CAS | VIP-аллокация + firewall | B + `Referrer(vpc.address)` |
| `nlb → compute` `InstanceService.Get` | sync | резолв Instance-target (только Instance) | C (`compute.instance` Referrer) |
| `compute → registry` (boot resolve) | sync | resolve `tag→digest`, pull-grant precheck (зависит от instance-SA **puller-tuple EC**, §5.4) | C (`registry.image` bootSource, `imageKind=OCI_IMAGE`) |
| `compute → storage` | sync/сага | materialize boot-Volume, secondary attach; **compensation `Delete` на fail** | B/`Referrer(storage.volume)`, bootSource `imageKind=STORAGE_IMAGE` |
| `registry → iam` `Check`+`ProjectService.Get`+JWKS(:9097) | sync | authz + scope + data-plane token-verify (signature-only, без revocation-check — B11) | B + — |

**Проверка ацикличности:** iam не зовёт никого → geo зовёт только iam → vpc зовёт {geo,iam} → registry зовёт только iam → storage зовёт {geo?,iam} → compute зовёт {vpc,geo,registry,storage,iam} → nlb зовёт {compute,vpc,geo,iam}. Топологический порядок существует ⇒ **циклов нет**. Ключевые «не-рёбра»: geo **никогда** не зовёт consumer'ов; iam **никогда** не зовёт registry/compute; owner **никогда** не спрашивает consumer'ов при Delete (нет cross-service cascade — поэтому launch-compensation живёт **на стороне инициатора compute**, а не через обратный вызов, §5.4); vpc больше не зовёт compute.

> **B2 acyclicity-уточнение:** `compute→iam` (ProjectService.Get/Check) **уже существует** — поэтому `Instance.serviceAccountId`-peer-validate НЕ добавлял бы цикла; выбор class-C (graceful-dangling `Referrer{iam.service_account}`) — это чисто **семантическое** решение (dangling-tolerance vs hard-fail), а не защита ацикличности. Цикл-риск несёт только `iam→owner` (D-5), а это **не** направление данного ребра. Решение зафиксировано в пользу class-C (§8).

**Seam-контракты:**
- **Class-B scope-координата** (`projectId`/`zoneId`/`regionId`) → flat slug, peer-validate на request-path, fail-closed (`UNAVAILABLE` если peer down). Нет mirror-строк, нет cross-service FK.
- **Class-C dependency** (`bootSource`, Target-identity, `usedBy`, `Instance.serviceAccountId`) → `Referrer{type:{value,displayName},id,name°}` — polymorphic, graceful-dangling (референт удалён → DETACHED/degraded, не паника). Токены `type` — dotted `domain.resource` из версионированного shared-каталога `kacho.cloud.common.v1.ReferrerType`. **Три разных ref-типа** (B1): `ResourceRef` (iam AccessBinding target, closed-table), `Referrer` (generic cross-owner handle), `OciReferrer` (registry OCI-1.1 граф).
- **fgaproxy** — все owner-модули пишут owner/member-tuple **только** через iam `RegisterResource` (:9091, идемпотентно, at-least-once transactional-outbox), никогда напрямую в OpenFGA. Касается и `Group#member` (iam-собственный outbox).

---

## 5. Сквозные инварианты (во ВСЕХ модулях)

1. **Two-projection.** Инфра-чувствительное (node/host/scheduler/underlay/vrf/numeric-infra-id/wiring/топология/free-list/blob-layout, а в geo — **сырой `status`** UP/DOWN и весь `infra°`) — **только** `Internal*` :9091 (и readable, и writable там). Публичная поверхность = намерение + результат. geo public capacity-fail **обезличен** (не эхает host-class); geo public `placementBlockedReason°∈{NONE,ZONE_DOWN,REGION_DOWN}` — **accepted carve-out** (tenant-facing «могу ли разместить»; ZONE/REGION-дискриминатор грубее сырого host-class/capacity, которые остаются Internal; задокументирован как осознанный, не leak). registry deny = existence-hiding (byte-identical 404).

2. **Placement-coherence** (`data-integrity.md`). Дискриминатор `placementType∈{ZONAL,REGIONAL}`. Якорь — **Subnet** (vpc); NIC/Address наследуют через `subnetId`. Энфорсмент: within-service — DB-CAS; cross-service — peer-validate через **единый corelib-хелпер `geoconsumer.ValidatePlacement`** (все 3 consumer'а обязаны звать; conformance-lock охраняет хелпер). iam — **N/A by construction**. registry — REGIONAL-only. Instance↔Volume — та же зона (storage-seam).

3. **Authz-uniform.** AuthN+AuthZ на КАЖДОМ RPC обоих листенеров; per-RPC `Check`→OpenFGA **flat Contract-A**; object-scoped `scope_extractor` (anti-BOLA); permission-catalog byte-identical iam-seed↔gateway (CI drift-gate); public `List*` фильтруется listauthz; validate-format ДО authz-short-circuit. Fail-closed везде.

4. **Eventual-consistency.** `Operation.done`=ресурс DURABLE, **не** downstream-видимость. owner/grant/member-tuple, `usedBy.name°`-зеркала, engine-remap материализуются в ограниченном окне (sync-registrar best-effort + `fga_outbox` at-least-once drainer + reconciler). **Group#member** и **grant-by-email** идут той же дисциплиной: member-tuple — outbox-emit (не «co-commit»); pending email-grant хранится как intent, reconciler ремапит в `usr-<id>`-tuple на первом OIDC-login (invitation-accept) в ограниченном окне (conformance: `grant-by-email → login → access materializes`; `revoke-before-login → clears pending intent`). «Создал→сразу мутирую/пуллю своё» → **bounded client-retry** (SDK `retry_until_authorized`/`retry_until_present`, budget ~10s) ТОЛЬКО на первый доступ к своему свежему ресурсу. **registry `GetEffectiveAccess`-readiness — CLIENT-side** bounded-retry-поллом (`retry_until_authorized` против `GetEffectiveAccess`), **никогда серверный барьер**; underlying `Check` — strong-consistency-read или bounded-retry; НЕ гейтит `Operation.done`. **compute→registry boot-pull couples на puller-tuple EC**: instance-boot pull-grant зависит от материализации puller-tuple SA — resolve через тот же readiness-паттерн, boot-worker ретраит pull в bounded-окне (не hard-fail на первом NAME_UNKNOWN). Серверный confirm-барьер запрещён (ban #9 — phantom). Fixture обязан проверять `!op.error` перед извлечением id.

   **Cross-service saga compensation (one-shot launch).** compute `Create.launch` спанит compute→vpc (IPAM Address alloc + NIC `SetReference` CAS), compute→storage (boot-Volume materialize), compute→registry (pull-grant). Partial-fail (Address зализен, затем storage-Volume Create падает) НЕ должен оставлять orphan-lease / half-attached NIC. Поскольку owner никогда не спрашивает consumer'ов на Delete (нет cross-service cascade), **компенсация живёт на инициаторе**: compute-worker на launch-fail **до** пометки `Operation` error эмитит компенсирующие `Free`/`ClearReference` (vpc) и `Delete` (storage) через **собственный `compute.compensation_outbox`** (at-least-once); **backstop** — vpc/storage sweeper-reconciler освобождает lease/Volume, чей `usedBy`-Referrer DETACHED/dangling дольше TTL. Оба пути обязаны landing до Phase-2 compute (§9 B10).

5. **Единый тон ошибок** (часть контракта). `"<Resource> <id> not found"` (NOT_FOUND); `"<field> is immutable after <R>.Create"` (INVALID_ARGUMENT, до UpdateMask); mutual-exclusion — spoken; коды INVALID_ARGUMENT/NOT_FOUND/FAILED_PRECONDITION/ALREADY_EXISTS/UNAVAILABLE(peer down, fail-closed)/INTERNAL(**opaque, без pgx/SQL-leak** — regression-lock на message); malformed-id **первым стейтментом**. **By-lane code-split — PROPOSED** (direct-read→NOT_FOUND; peer-validate→FAILED_PRECONDITION; клиент ключуется на `reason`-token в `rpc.Status.details`): приземляется Phase-0 governance change-set'ом в `api-conventions.md` — **до merge не «landed»**, контрибьютор не строит против отсутствующего текста (§9).

6. **Within-service инварианты — на DB-уровне** (ban #10). FK/partial-UNIQUE/EXCLUDE-gist/CHECK/atomic-CAS/xmin-OCC/FOR-UPDATE-SKIP-LOCKED. SQLSTATE→gRPC в mapRepoErr. Concurrent-race integration-тест на каждый спорный путь.

7. **Update mutability-классы** (exhaustive). LIVE-mutable / next-boot-deferred (принять+отложить) / STOPPED-gated / immutable (reject до UpdateMask). Power-state сохраняется. Пустой mask → full-PATCH.

8. **Vendor-agnostic** (ban #2). Никаких имён чужих облаков/third-party-product-noun'ов. Узнаваемость — ФОРМОЙ (flat+Operation+Referrer+placementType; OCI push/pull; NetworkLoadBalancer/5-tuple; NAT-gateway), не брендом.

9. **Lease-recycle-on-delete** (IPAM/pool-ресурсы). Address Delete **и** NIC/VIP-teardown возвращают lease в AddressPool free-list **атомарно** (single-statement, под row-lock) — без этого orphan-lease + saga-fail исчерпывают пул под параллельным e2e. Regression: concurrent alloc/free integration-тест (ровно один writer выигрывает slot) + pool-exhaustion e2e-guard. Тот же принцип — любой ресурс из ограниченного пула (внешний VIP/AddressPool).

---

## 6. Единый UX-хребет (один продукт при переходе между модулями)

**Каждый launch любого ресурса в любом домене следует ОДНОМУ ритму:**

```
1. DISCOVER   sync-каталог рядом с мутацией отвечает «что я могу выбрать», item несёт paste-ready
              requestFragment/grantFragment (id не гадать): geo ListZones · compute MachineType/ImageCatalog
              (bootSource несёт imageKind-дискриминатор STORAGE_IMAGE/OCI_IMAGE) · vpc ListPlaceableZones/SuggestCidr ·
              nlb :regions/:addableInstances/:vipAnchorCandidates · iam RoleService.List(assignableOn) · registry ListNamespaces
2. VALIDATE   validateOnly:true → sync dry-run: полная валидация БЕЗ мутации/Operation/state-gate;
              {valid, warnings[], resolved{echo выведенных значений}}
3. CREATE     one-shot: зависимые под-ресурсы в *Specs, worker разворачивает саги в ОДНОЙ Operation
              (с compensation-path при partial-fail); id ресурса в Operation.metadata СРАЗУ (до done)
4. POLL       OperationService.Get(op.id) с inter-poll delay пока !done (Watch RPC нет);
              geo-исключение: done:true сразу, unwrap .response
5. READ-YOUR-WRITES  первый Get/Update/Delete/pull СВОЕГО свежего ресурса → bounded client-retry на 403/404
              (owner-tuple/puller-tuple EC); SDK-дефолт retry_until_authorized / retry_until_present;
              registry GetEffectiveAccess — client-side readiness-poll, не серверный барьер
```

Один пользователь, перейдя compute→vpc→nlb→registry→iam→geo→storage, видит: те же `°`-маркеры, тот же enum-контракт, те же коды/тон ошибок, тот же `Operation`-конверт, тот же ref-закон (три типа с чёткой семантикой: `ResourceRef`/`Referrer`/`OciReferrer`), ту же `validateOnly`-семантику, тот же id-prefix-закон. Никаких «диалектов». Bootstrap-цепочка не покидает контракт Kachō.

---

## 7. Порядок реализации (топосорт по build-графу)

Build-граф (versioned `require`, БЕЗ `replace`): `kacho-proto → kacho-corelib → сервисы → kacho-api-gateway → kacho-deploy → docs`.

**Фаза 0 — фундамент corelib/proto (блокирует всё; стартует ТОЛЬКО после закрытия B1/B3):**
1. `kacho-proto`: proto всех доменов, shared `kacho.cloud.common.v1` с **тремя** ref-типами (`ResourceRef`{type,id} / `Referrer`{type,id,name} / `OciReferrer`), `ReferrerType`-каталог, `kacho.cloud.operation.v1`. `buf lint`/`breaking` зелёные.
2. `kacho-corelib`: `ids` (+ carve-out `GeoSlug`; **id-prefix hyphen-форма зафиксирована — B3**; prefix→type-router), `operations`, `outbox` (+ compute compensation-outbox паттерн), `authz`, `validate`, `geoconsumer.ValidatePlacement`, `filter`, `db`.
3. **Governance change-set (ОДИН commit, ДО прод-кода):** приземлить в `api-conventions.md`+`data-integrity.md`: (a) **3-way ref-naming** (B1); (b) **id-prefix hyphen** (B3); (c) **by-lane error-token** таблица; (d) **saga-compensation**-паттерн; (e) **lease-recycle-on-delete**; (f) Group/email-grant EC-materialization; (g) forceLogout-семантика. **Пока change-set не смёржен — conv-7/11/12 остаются PROPOSED** (§9), downstream против них не строит.

**Фаза 1 — leaf-сервисы (не блокированы §9-блокерами; идут первыми):**
4. **`kacho-geo`** — Region/Zone + `Internal*` CRUD + `geoconsumer`-контракт.
5. **`kacho-iam`** — Account/Project/User/SA/Group/Role/AccessBinding + `InternalIAMService.Check`/`RegisterResource` + AuthService + permission-catalog-gen. Включает: Group#member outbox-materialize, grant-by-email intent+reconciler, forceLogout bounded-window, `roleId`-seam-решение (B6).

**Фаза 2 — owner-сервисы:**
6. **`kacho-storage`** (**first-class, B10**) — Volume/Image/Snapshot + fgaproxy + lease/attach-семантика. Блокирует compute boot-Volume/ImageCatalog. **compute GA gated-by этой сходимости.**
7. **`kacho-vpc`** — Network/Subnet/SG/RT/Gateway/NIC/Address + fgaproxy + `InternalAddress/NetworkInterfaceService` + **recycle-on-delete** + sweeper-reconciler (compensation backstop).
8. **`kacho-registry`** — Namespace/Repository/Tag/Image + docker auth-proxy + `GetEffectiveAccess` client-side gate + iam scope-alias (B7).
9. **`kacho-compute`** (ЭТАЛОН) — Instance/MachineType/PlacementGroup/ImageCatalog + **launch compensation-outbox** + bootSource imageKind-дискриминатор. Зависит от vpc+geo+registry+storage+iam.
10. **`kacho-nlb`** — NetworkLoadBalancer/Listener/TargetGroup + instance-target resolution (синхронизирован с compute Attach-редизайном, B9).

**Фаза 3 — edge + деплой + docs:**
11. **`kacho-api-gateway`** — регистрация public/Internal RPC; embedded permission-catalog byte-identical; hide-existence 404 byte-identity; grpc-gateway REST.
12. **`kacho-deploy`** — helm/compose (PG-per-service, internal-CA/mTLS, Hydra, JWKS-terminator).
13. **`kacho-workspace`** — docs/specs + vault trail (после фактического merge governance change-set — проставить «landed» в §1/§5).

Внутри каждого сервиса: строгий TDD (RED→GREEN), integration (testcontainers) + newman в том же PR, ревью ролями, финал `go test -race`+`golangci-lint`+`govulncheck`+`make audit-list-filter`+newman зелёные. **Gate:** кодинг — только после APPROVED acceptance-дока под-фазы.

---

## 8. Открытые cross-cutting решения/блокеры

| # | Блокер | Суть | Решение |
|---|---|---|---|
| **B1** | **ref-type naming — 3-way, НЕ rename** | `ResourceRef{type,id}` **уже landed** в iam (AccessBinding target, closed authzmap.ObjectType, БЕЗ name); generic `Referrer{type,id,name}` **уже landed** в compute (cross-owner handle). Предложенный «rename Referrer→ResourceRef везде» overload'ил бы landed iam-тип и сломал бы AccessTarget wire-form. registry OCI-1.1 граф — третья семантика. | **3-way disambiguation** ОДНИМ change-set в `kacho.cloud.common.v1`+`api-conventions.md`: (a) iam `ResourceRef` остаётся; (b) generic `Referrer` остаётся; (c) registry OCI-граф → **`OciReferrer`/`ArtifactRef`**. **Блокирует Phase-0 proto.** |
| **B3** | **id-prefix hyphen** | `ins-`/`prj-`/`ns-` (дефис) vs `net`/`sub`/`nlb` (без) → дрейф ломает prefix→type-router. | Зафиксировать **с дефисом** в `api-conventions.md`+`corevalidate`, привести vpc/nlb. **Блокирует Phase-0 corelib.** |
| **B2** | `Instance.serviceAccountId` класс | peer-validate (hard-fail) vs graceful-dangling. Ацикличность-обоснование overstated — `compute→iam` уже есть, ребро цикла не добавляет; выбор чисто семантический. | **Принять class-C** `Referrer{iam.service_account}` (graceful-dangling). Влияет на error-семантику при удалённом SA. |
| **B4** | Foreign-id prefix-check на seam | vpc: «prefix кодирует тип» vs «foreign owned-id НИКОГДА не prefix-checked». ~~nlb-примеры: общий prefix~~ — **факт неверен, снят**: Subnet=`sub`, Address=`adr`, общего префикса нет; и ни один из них не сверяется — `corevalidate.ResourceID` **family-agnostic** (`expectedPrefix` не читается), проверяет лишь членство в ПЛАТФОРМЕННОМ каталоге `ids.KnownPrefixes()`/`KnownHyphenPrefixes()`+config-extras. | Закреплено: format-check (`"invalid <res> id"`) — **только own-owned id**; foreign id — peer-validate existence-only. **Записанное исключение — nlb VIP-источники** (`v4/v6Source.subnetId`/`.addressId`): синтаксический gate оставлен (терминальный 400 вместо retryable `UNAVAILABLE` при недоступном vpc + правдивый текст вместо `"subnet garbage!! not found"`), тип/существование по-прежнему решает владелец. Обоснование — `services/nlb/docs/architecture/08-known-divergences.md` §«Формат чужого id (VIP-источники)». |
| **B5** | vpc default-subnet для compute `useDefaultNetwork` | форма есть, vpc-side default-subnet-релиза нет. | Решение: вводит ли vpc first-class «project-default subnet» (owner=vpc, compute не автосоздаёт — цикл-риск). Блокирует «zero-to-instance за один Create». |
| **B6** | AccessBinding `roleId`: id vs dotted-name | registry-templates шлют `registry.repoCreator`; iam-поле=FK на `rol-` id. | iam-side: alt-reference-резолв в scope ИЛИ rename поля. Conformance «template-body валиден как вход iam.AccessBindingService/Create». |
| **B7** | registry FGA-тип leak на iam-шве | `registry_registry:ns-…` читается как «другой продукт»; типы заморожены. | iam accepted-synonym `registry_namespace:`/`registry_repository:`. Не блокирует старт (Rosetta достаточно), решить до docs-финала. |
| **B8** | nlb duration-конвенция | nlb: Duration-строки; compute/vpc: scalar/секунды. | Единая duration-конвенция во всех модулях. Не блокирует старт nlb, фиксировать до второго duration-домена. |
| **B9** | nlb instance-target vs compute Attach-редизайн | `instance→primary NIC→primary IP` pending compute-redesign; «primary NIC»/multi-NIC undefined. | Синхронизировать compute `AttachNetworkInterface` с nlb resolution; определить primary-NIC до GA. |
| **B10** | **storage — жёсткая зависимость якоря-compute, но «вне свода»** | compute (эталон) не может GA без storage (boot-Volume/ImageCatalog/attach), а его сходимость не покрыта и отсутствовала в блокерах. | **Втянуть storage в свод как first-class Phase-2 owner** (§2/§7 step 6) с собственным acceptance (CS-1 spec); **compute GA gated-by storage convergence**. Не оставлять «если в scope» на load-bearing edge. |
| **B11** | **iam `:forceLogout` hard-cutoff vs stateless-JWKS** | registry data-plane верит docker-Bearer **только по подписи** через iam JWKS (fail-closed, без introspection/revocation) → уже выпущенный JWT DISABLED-SA валиден до natural expiry. «hard-cutoff» недостижим на stateless-верификаторах. | **Downgrade семантики** до «no-new-tokens + bounded revocation window = access-token TTL» (задокументировать) ИЛИ revocation-list/introspection на registry verify-path (убивает stateless-JWKS latency). Решить до registry GA; согласовать формулировку контракта. |
| **B12** | **compute one-shot launch — нет cross-service compensation** | partial-fail (Address зализен → storage-Volume Create падает) оставляет orphan IPAM-lease/half-attached NIC; owner-never-asks-consumer → никто не реклеймит. | **Специфицировать компенсацию** (§5.4): compute-worker эмитит компенсирующие `Free`/`Delete` в `compute.compensation_outbox` (at-least-once) до пометки op-error; **+** vpc/storage sweeper-реклейм dangling-lease past TTL. **Land до Phase-2 compute.** |
| **B13** | **'Image' overloaded (storage VM-boot vs registry OCI)** | bootSource несёт `imageId`, но owner-резолвер не дискриминирован; ImageCatalog проецирует оба. | **owner-дискриминатор** на bootSource/ImageCatalog: `imageKind∈{STORAGE_IMAGE,OCI_IMAGE}` (или `Referrer.type` routing compute→storage/compute→registry). Bare `imageId` НИКОГДА не двусмыслен. |
| **B14** | **Group member-tuple «co-commit» vs EC/outbox** | внешний FGA не может атомарно co-commit'иться в DB-tx; формулировка подразумевает sync dual-write с дрейфом. | Выровнять по outbox-модели: member-tuple intent в `fga_outbox` → at-least-once drainer → reconciler покрывает `Group#member`. Fix wording «co-commit»→«outbox-emit + EC». |
| **B15** | **grant-by-email / UserInvitation FGA-timing undefined** | tuple keyed на email не матчит enforcement (резолвит `usr-`); keyed на future `usr-` не существует pre-login. Remap не специфицирован. | pending email-grant как intent → reconciler ремапит в `usr-<id>` на первом OIDC-login (accept), bounded window. Conformance: grant-by-email→login→materialize; revoke-before-login→clear intent. |
| **B16** | **registry `GetEffectiveAccess` риск серверного confirm-барьера (ban #9)** | если читает EC-FGA at default-consistency → false-ready; если блокирует server-side до материализации → banned confirm-gate (phantom). | Frame как **client-side** bounded-retry-поллом (`retry_until_authorized`); underlying `Check` — strong-consistency-read или bounded-retry; assert «не гейтит `Operation.done`». |
| **B17** | **Address/AddressPool recycle-on-delete не специфицирован** | alloc/CAS описан, lease-return-to-pool на Delete/teardown — нет; с saga-gap orphan-lease исчерпывает пул под parallel-e2e. | **recycle-on-delete атомарно** (§5.9): Address Delete + NIC/VIP-teardown возвращают lease в free-list. Concurrent alloc/free integration-тест + pool-exhaustion e2e-guard. |
| **DT** | **Doc-truthfulness: «landed» vs «PENDING»** | §1/§5 заявляли by-lane-split / id-prefix / ref-naming как «landed в api-conventions.md», хотя это те же PENDING-items (B1/B3/by-lane), а change-set не смёржен. | §1/§5 говорят **«PROPOSED, приземляется Phase-0 governance change-set»** + cross-ref §9. «Landed» — только после фактического merge. Устранено в этом документе. |

---

## 9. Готовность и блокеры

**`readyToStart = false`** для полного графа. geo+iam (Фаза 1) готовы к старту; Фаза 0 и всё downstream — нет, пока не закрыт governance-набор.

**MUST-close ДО Phase-0 proto/corelib (жёсткие блокеры старта):**
1. **B1** — 3-way ref-naming disambiguation (`ResourceRef`/`Referrer`/`OciReferrer`) приземлён ОДНИМ change-set в `kacho.cloud.common.v1`+`api-conventions.md`. Без него shared `common.v1` proto нельзя писать → блокирует ВСЕ сервисы.
2. **B3** — id-prefix hyphen-форма зафиксирована в `corevalidate`/`api-conventions.md`, vpc/nlb приведены. Без него сломан prefix→type-router corelib.
3. **DT-reconcile** — governance change-set (by-lane code-split + id-prefix + ref-naming + saga-compensation + lease-recycle + Group/email EC + forceLogout) **фактически смёржен** в `api-conventions.md`+`data-integrity.md`. До merge conv-7/11/12 — PROPOSED; downstream не строит против отсутствующего текста.

**MUST-close ДО соответствующей Phase-2 под-фазы (блокируют конкретный сервис, не весь старт):**
4. **B10 + B12 + B17** (compute/vpc/storage) — storage втянут first-class; compute launch-compensation-outbox + vpc/storage sweeper-реклейм + Address recycle-on-delete специфицированы и покрыты concurrent-тестом. **compute GA gated-by storage convergence.**
5. **B11 + B16** (iam/registry) — forceLogout-семантика downgrade'нута до bounded-window (или revocation-check добавлен); `GetEffectiveAccess` — client-side readiness (не серверный барьер), не гейтит `Operation.done`. Согласовать до registry GA.
6. **B13 + B14 + B15** (compute/iam) — bootSource imageKind-дискриминатор; Group#member outbox-materialize; grant-by-email intent+reconciler-remap. Conformance-тесты в тех же PR.
7. **B2 + B6 + B9** (seam-решения) — SA class-C принят; AccessBinding `roleId` alt-reference/rename решён; nlb instance-target синхронизирован с compute Attach-редизайном.

**NON-блокеры старта (есть рабочие fallback'и), решить до GA/docs-финала:**
8. **B4** (foreign-id prefix-check закреплён own-only; единственное записанное исключение — nlb VIP-источники, см. строку B4), **B5** (vpc project-default subnet), **B7** (iam registry-scope-alias), **B8** (единая duration-конвенция).

**Стартовать можно немедленно:** Фаза 1 (`kacho-geo`, `kacho-iam`) — не блокированы ничем из списка и идут первыми. Фаза 0 (proto/corelib + governance change-set) — сразу после решения B1/B3. Всё остальное открывается по мере закрытия соответствующих блокеров выше.
