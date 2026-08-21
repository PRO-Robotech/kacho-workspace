---
title: "INDEX — полный перечень записок"
aliases:
  - Index
  - указатель
category: hub
status: active
tags:
  - hub
  - index
---

# INDEX — что вообще есть в хранилище

Полный перечень записок, собранный **из дерева**. Ищете конкретный предмет —
листайте таблицы ниже; не знаете, в какой категории искать, — откройте
[[README]], там сказано, с каким вопросом куда идти.

> [!tip] Найти за один шаг
> **Знаете имя** — поиск Obsidian по имени файла: записки называются
> `<домен>-<предмет>` (`vpc-subnet`, `iam-role`, `nlb-clients-vpc`).
> **Знаете предмет, но не имя** — таблицы ниже сгруппированы по домену.
> **Нужен срез** (все живые рёбра, все снятые ресурсы) — виды-таблицы:
> [[resources/all-resources|resources]] · [[rpc/all-services|rpc]] ·
> [[packages/all-packages|packages]] · [[KAC/all-tickets|KAC]].

## Как читать колонку «состояние»

| Ведро | Значит |
|---|---|
| **живо** | предмет есть в дереве продукта сегодня (`stable`, `active`, `done`) |
| **история** | предмет снят или заменён; записка верна как прошлое (`deprecated`, `legacy`, `superseded`, `wontfix`) |
| **в работе** | предмета ещё нет либо он не проверен (`in-progress`, `test`, `to-do`, `planned`, `experimental`, `reference`) |

Ведро — не оценка качества записки, а ответ на первый вопрос читателя: описывает
она сегодняшний код или прошлое. Контракт оболочки целиком — [[CLAUDE]].

## Чего в хранилище НЕТ

Знание о пробелах экономит больше времени, чем перечень имеющегося: не найдя
записку, легко решить, что предмета нет и в продукте. Раздел перемерен
**2026-08-06** по дереву продукта `ee679467` (потомок ствола
`redesign/integration@50e5e624`); предикаты приведены рядом, чтобы число можно
было перемерить, а не поверить ему.

**gRPC-сервисы.** Предикат: имена из `^service ` во всех `proto/**/*.proto`
против упоминания имени в `rpc/*.md` — в обе стороны.

- объявлено сервисов **54**, упомянут хотя бы одной запиской **50**, **без
  записки 4**;
- **домены storage и registry закрыты 2026-08-06** — заведено девять записок
  (storage: том, снимок, образ, тип диска и три внутренних; registry:
  публичный и внутренний). Прежняя редакция называла у storage **шесть**
  сервисов — их **семь**: админский CRUD типов дисков объявлен вторым блоком
  `service` в **том же** файле, что публичное чтение, и счёт по файлам его
  терял;
- остаются **без записки 4**, по одному в четырёх разных доменах:
  `InternalAuthzCacheService` (край), `InternalInteractiveClientService` и
  `InternalSessionRevocationsService` (iam), `InternalLoadBalancerAnnounceService`
  (nlb). Все четыре — внутренние; это остаток, а не намеренное исключение;
- обратная сторона: **16 из 62** записок `rpc/` описывают поверхность, которой в
  `proto/` **нет** — эпоха производственного IAM (внешние поставщики учётных
  записей, организации, условия, федерация) и снятый менеджер ресурсов. Это не
  ошибка: у каждой стоит `status` из ведра «история», по которому видно, что речь
  о прошлом, и срез `rpc/all-services.base` собирает их отдельным видом. Ещё одна
  записка (`vpc-internal-watch-service`) помечена так же, но её предмет **жив под
  другим владельцем** — сервис есть у compute; в эти 16 она не входит.

**Ресурсы.** Домен **storage** — владелец блочного хранения (Volume · Snapshot ·
Image · DiskType плюс таблица привязки томов) — представлен **нулём** записок в
`resources/`: контракты его четырёх сервисов теперь описаны в `rpc/`, а сами
ресурсы — нет. У **registry** описан только Repository; Registry и Tag — нет.

**Рёбра.** Из объявленных правилами рёбер рантайма в `edges/` нет записки про
`storage → geo` (резолв региона зоны при создании тома из образа). Остальные
рёбра storage и registry записки имеют.

**Уроки.** `lessons/` заведён из одного файла; на классы по-прежнему ссылаются
короткими именами **100** раз, и большая часть этих записок не написана —
[[lessons/README]] называет число и предикат.

**Висячие ссылки.** Замер **2026-08-09**: всего **335** на **213** целей — это и
есть перечень ненаписанного (записки категорий 162, уроки 100, номера KAC без
trail 73). За 2026-08-09 перечень сократился ровно на одну цель:
`known-failing-declaration-outlives-the-fix` перестала висеть потому, что урок
**написали**, а не потому, что ссылку переименовали в простой текст. Приём
повторяемый и назван в [[lessons/README]]: заводя урок, называй файл ровно тем
именем, которым на класс уже ссылаются, — тогда все прежние ссылки оживают разом.
Список ведётся как основание храповика
(`scripts/vault-gate/dangling-baseline.txt`): новая висячая ссылка роняет гейт
`check-02`, а исчезнувшая обязывает переписать основание тем же коммитом.

> [!note] Числа в этом абзаце — рукописные, и они уже отставали
> До 2026-08-09 здесь стояло «340 на 217 целей», тогда как основание храповика
> несло 214 записей: рукописная часть указателя отстала от машинной на три цели.
> Генератор её не трогает by construction, поэтому сверять эти числа надо тем же
> прогоном, что переписывает основание, а не памятью.

> [!tip] Почему «Всего» в таблице ниже меньше, чем число в выводе гейта
> Это не расхождение, а **две единицы счёта**. Гейт называет все файлы `.md`
> хранилища (на 2026-08-09 — **544**); таблица суммирует записки **по
> категориям** и не считает пять указателей категорий (`README.md` в `KAC/`,
> `lessons/`, `legacy/`, `docs/`, `runbooks/`) — отсюда **539**. У четырёх
> остальных категорий своего `README.md` нет: их витрина — вид-таблица `all-*.base`,
> а он не `.md`. Сравнивать эти два числа как одно — ошибка, которую легко сделать,
> читая вывод гейта рядом с таблицей.

> [!note] Почему перечень ниже машинный
> Прежняя редакция указателя была рукописной и покрывала **62 %** корпуса: из
> 295 записок четырёх фактических категорий в ней не упоминалось **112**. При
> этом обратная сторона (ссылки указателя резолвятся) была чистой — то есть
> проверка одной стороны показывала «указатель в порядке». Класс снят
> генератором: `./scripts/vault-index/generate.py` собирает перечень из дерева,
> `--check` роняет прогон, когда указатель отстал. Рукописную часть — всё, что
> выше маркера, — генератор не трогает.

<!-- GENERATED:vault-index BEGIN — правится генератором, руками не трогать -->

Ниже — **полный** перечень записок, собранный из дерева хранилища. Предикат счёта — `git ls-files --cached --others --exclude-standard 'obsidian/kacho/*.md'`; пересобрать — `./scripts/vault-index/generate.py`, проверить свежесть — `--check`.

| Категория | Каталог | Записок |
|---|---|---:|
| Ресурсы | `resources/` | 57 |
| gRPC-сервисы | `rpc/` | 66 |
| Рёбра рантайма | `edges/` | 77 |
| Пакеты | `packages/` | 119 |
| Журнал работ (KAC) | `KAC/` | 327 |
| Уроки — классы дефектов | `lessons/` | 43 |
| Записки-переходы прежних репозиториев | `legacy/` | 6 |
| Операционные процедуры | `runbooks/` | 1 |
| Руководства (эпоха KAC-127) | `docs/` | 3 |
| Точки входа и полотно | `(корень)` | 4 |
| **Всего** | | **703** |

### Ресурсы — `resources/` (57)

**домен: compute**

| Записка | Состояние |
|---|---|
| [[resources/compute-guestaccesskey\|GuestAccessKey (compute) — ключ входа в машину]] | живо (done) |
| [[resources/compute-instance\|Instance (compute) — пересборка 2026]] | живо (done) |
| [[resources/compute-machinetype\|MachineType (compute) — sync sizing catalog]] | живо (done) |
| [[resources/compute-placementgroup\|PlacementGroup (compute) — правило взаимного размещения машин]] | живо (done) |

**домен: geo**

| Записка | Состояние |
|---|---|
| [[resources/geo-region\|Region]] | живо (stable) |
| [[resources/geo-zone\|Zone]] | живо (stable) |

**домен: iam**

| Записка | Состояние |
|---|---|
| [[resources/iam-access-binding-condition\|AccessBindingCondition]] | история (deprecated) |
| [[resources/iam-access-binding\|AccessBinding]] | живо (done) |
| [[resources/iam-access-review-item\|AccessReviewItem]] | история (deprecated) |
| [[resources/iam-access-review\|AccessReview]] | история (deprecated) |
| [[resources/iam-account\|Account]] | живо (done) |
| [[resources/iam-audit-outbox\|audit_outbox (iam)]] | живо (stable) |
| [[resources/iam-audit-signing-batch\|AuditSigningBatch]] | история (deprecated) |
| [[resources/iam-caep-subscriber\|CAEPSubscriber]] | история (deprecated) |
| [[resources/iam-cluster-admin-grant\|ClusterAdminGrant]] | живо (done) |
| [[resources/iam-cluster-break-glass-grant\|ClusterBreakGlassGrant]] | история (deprecated) |
| [[resources/iam-cluster\|Cluster]] | живо (done) |
| [[resources/iam-condition\|Condition]] | история (deprecated) |
| [[resources/iam-federation-trust-policy\|FederationTrustPolicy]] | история (deprecated) |
| [[resources/iam-gdpr-erasure-request\|GDPRErasureRequest]] | история (deprecated) |
| [[resources/iam-group\|Group]] | живо (done) |
| [[resources/iam-jit-eligibility\|AccessBindingJITEligibility]] | история (deprecated) |
| [[resources/iam-jwks-key\|JWKS Key (alias)]] | история (deprecated) |
| [[resources/iam-limit\|Limit]] | живо (done) |
| [[resources/iam-oidc-jwks-key\|OIDCJwksKey]] | история (deprecated) |
| [[resources/iam-organization\|Organization]] | история (deprecated) |
| [[resources/iam-project\|Project]] | живо (done) |
| [[resources/iam-recovery-completions\|recovery_completions]] | живо (done) |
| [[resources/iam-resource-mirror\|ResourceMirror]] | живо (done) |
| [[resources/iam-role\|Role]] | живо (done) |
| [[resources/iam-scim-user-mapping\|SCIMUserMapping]] | история (deprecated) |
| [[resources/iam-service-account-oauth-client\|ServiceAccountOAuthClient]] | в работе (planned) |
| [[resources/iam-service-account\|ServiceAccount]] | живо (done) |
| [[resources/iam-session-revocation\|SessionRevocation]] | в работе (planned) |
| [[resources/iam-user\|User]] | живо (done) |

**домен: nlb**

| Записка | Состояние |
|---|---|
| [[resources/nlb-listener\|Listener]] | живо (stable) |
| [[resources/nlb-load-balancer\|NetworkLoadBalancer]] | живо (stable) |
| [[resources/nlb-target-group\|TargetGroup]] | живо (stable) |
| [[resources/nlb-target\|Target]] | живо (stable) |

**домен: operation**

| Записка | Состояние |
|---|---|
| [[resources/operation\|Operation]] | живо (stable) |

**домен: organizationmanager**

| Записка | Состояние |
|---|---|
| [[resources/rm-organization\|Organization]] | история (deprecated) |

**домен: registry**

| Записка | Состояние |
|---|---|
| [[resources/registry-repository\|Repository (registry)]] | в работе (in-progress) |

**домен: resourcemanager**

| Записка | Состояние |
|---|---|
| [[resources/rm-cloud\|Cloud]] | история (deprecated) |
| [[resources/rm-folder\|Folder]] | история (deprecated) |

**домен: vpc**

| Записка | Состояние |
|---|---|
| [[resources/cilium-kachovpc\|KachoVPC (cilium CRD)]] | в работе (planned) |
| [[resources/kacho-vpc-operator-KachoRouteTable\|KachoRouteTable (CRD оператора)]] | в работе (planned) |
| [[resources/kacho-vpc-operator-KachoSubnet\|KachoSubnet (CRD оператора)]] | в работе (planned) |
| [[resources/vpc-address\|Address]] | живо (stable) |
| [[resources/vpc-addresspool\|AddressPool]] | живо (stable) |
| [[resources/vpc-gateway\|Gateway]] | живо (stable) |
| [[resources/vpc-network\|Network]] | живо (stable) |
| [[resources/vpc-networkinterface\|NetworkInterface]] | живо (stable) |
| [[resources/vpc-privateendpoint\|PrivateEndpoint]] | история (deprecated) |
| [[resources/vpc-routetable\|RouteTable]] | живо (stable) |
| [[resources/vpc-securitygroup\|SecurityGroup]] | живо (stable) |
| [[resources/vpc-subnet\|Subnet]] | живо (stable) |

**домен: витрина категории**

| Записка | Состояние |
|---|---|
| [[resources/all-resources\|Все ресурсы — указатель]] | — |

### gRPC-сервисы — `rpc/` (66)

**домен: (не указан)**

| Записка | Состояние |
|---|---|
| [[rpc/iam-internal-bootstrap-token-service\|InternalBootstrapTokenService (implemented — #58)]] | живо (done) |

**домен: compute**

| Записка | Состояние |
|---|---|
| [[rpc/compute-guest-access-key-service\|GuestAccessKeyService (compute)]] | живо (done) |
| [[rpc/compute-instance-service\|InstanceService]] | живо (stable) |
| [[rpc/compute-internal-node-and-realization\|InternalNodeOwnershipService + InternalRealizationService (compute)]] | живо (done) |
| [[rpc/compute-machinetype-service\|MachineTypeService + InternalMachineTypeService]] | живо (stable) |
| [[rpc/compute-placement-group-service\|PlacementGroupService (compute)]] | живо (done) |

**домен: geo**

| Записка | Состояние |
|---|---|
| [[rpc/geo-region-service\|RegionService]] | в работе (in-progress) |
| [[rpc/geo-zone-service\|ZoneService]] | в работе (in-progress) |

**домен: iam**

| Записка | Состояние |
|---|---|
| [[rpc/iam-access-binding-service\|AccessBindingService]] | живо (done) |
| [[rpc/iam-account-service\|AccountService]] | живо (done) |
| [[rpc/iam-authorize-service\|AuthorizeService]] | живо (active) |
| [[rpc/iam-caep-subscriber-service\|CAEPSubscriberService]] | история (deprecated) |
| [[rpc/iam-conditions-service\|ConditionsService]] | история (deprecated) |
| [[rpc/iam-federation-exchange-service\|FederationExchangeService]] | история (deprecated) |
| [[rpc/iam-federation-service\|FederationService]] | история (deprecated) |
| [[rpc/iam-group-service\|GroupService]] | в работе (planned) |
| [[rpc/iam-internal-authorize-service\|InternalAuthorizeService]] | в работе (planned) |
| [[rpc/iam-internal-cluster-service\|InternalClusterService]] | живо (done) |
| [[rpc/iam-internal-iam-service\|InternalIAMService]] | в работе (planned) |
| [[rpc/iam-internal-limit-service\|InternalLimitService]] | живо (done) |
| [[rpc/iam-internal-operations-service\|InternalOperationsService]] | живо (done) |
| [[rpc/iam-internal-user-service\|InternalUserService]] | в работе (planned) |
| [[rpc/iam-opa-bundle-service\|OPABundleService]] | история (deprecated) |
| [[rpc/iam-organization-service\|OrganizationService]] | история (deprecated) |
| [[rpc/iam-permission-catalog-service\|PermissionCatalogService]] | в работе (test) |
| [[rpc/iam-project-service\|ProjectService]] | в работе (planned) |
| [[rpc/iam-role-service\|RoleService]] | в работе (planned) |
| [[rpc/iam-sa-key-service\|SAKeyService]] | в работе (planned) |
| [[rpc/iam-saml-sp\|SAML SP endpoints]] | история (deprecated) |
| [[rpc/iam-scim-v2\|SCIM 2.0 (RFC 7644)]] | история (deprecated) |
| [[rpc/iam-service-account-service\|ServiceAccountService]] | в работе (planned) |
| [[rpc/iam-trust-policy-service\|TrustPolicyService]] | история (deprecated) |
| [[rpc/iam-user-service\|UserService]] | живо (done) |

**домен: nlb**

| Записка | Состояние |
|---|---|
| [[rpc/nlb-internal-resource-lifecycle-service\|InternalResourceLifecycleService (nlb)]] | живо (stable) |
| [[rpc/nlb-listener-service\|ListenerService]] | живо (stable) |
| [[rpc/nlb-network-load-balancer-service\|NetworkLoadBalancerService]] | живо (stable) |
| [[rpc/nlb-target-group-service\|TargetGroupService]] | живо (stable) |

**домен: operation**

| Записка | Состояние |
|---|---|
| [[rpc/operation-service\|OperationService]] | живо (stable) |

**домен: organizationmanager**

| Записка | Состояние |
|---|---|
| [[rpc/om-organization-service\|OrganizationService (om alias)]] | история (deprecated) |
| [[rpc/om-user-account-service\|UserAccountService (om)]] | история (deprecated) |
| [[rpc/rm-organization-service\|OrganizationService]] | история (deprecated) |

**домен: registry**

| Записка | Состояние |
|---|---|
| [[rpc/registry-internal-registry-service\|InternalRegistryService]] | живо (stable) |
| [[rpc/registry-registry-service\|RegistryService]] | живо (stable) |

**домен: resourcemanager**

| Записка | Состояние |
|---|---|
| [[rpc/rm-cloud-service\|CloudService]] | история (deprecated) |
| [[rpc/rm-folder-service\|FolderService]] | история (deprecated) |

**домен: storage**

| Записка | Состояние |
|---|---|
| [[rpc/storage-disktype-service\|DiskTypeService]] | живо (stable) |
| [[rpc/storage-image-service\|ImageService]] | живо (stable) |
| [[rpc/storage-internal-disktype-service\|InternalDiskTypeService]] | живо (stable) |
| [[rpc/storage-internal-image-service\|InternalImageService]] | живо (stable) |
| [[rpc/storage-internal-volume-service\|InternalVolumeService]] | живо (stable) |
| [[rpc/storage-snapshot-service\|SnapshotService]] | живо (stable) |
| [[rpc/storage-volume-service\|VolumeService]] | живо (stable) |

**домен: vpc**

| Записка | Состояние |
|---|---|
| [[rpc/vpc-address-service\|AddressService]] | живо (stable) |
| [[rpc/vpc-gateway-service\|GatewayService]] | живо (stable) |
| [[rpc/vpc-internal-address-pool-service\|InternalAddressPoolService]] | живо (stable) |
| [[rpc/vpc-internal-address-service\|InternalAddressService]] | живо (stable) |
| [[rpc/vpc-internal-cloud-service\|InternalCloudService (removed)]] | история (deprecated) |
| [[rpc/vpc-internal-network-interface-service\|InternalNetworkInterfaceService (vpc)]] | живо (stable) |
| [[rpc/vpc-internal-network-service\|InternalNetworkService]] | живо (stable) |
| [[rpc/vpc-internal-watch-service\|InternalWatchService (vpc — снят; у compute живёт)]] | история (deprecated) |
| [[rpc/vpc-network-service\|NetworkService]] | живо (stable) |
| [[rpc/vpc-networkinterface-service\|NetworkInterfaceService]] | живо (stable) |
| [[rpc/vpc-privateendpoint-service\|PrivateEndpointService (снят)]] | история (deprecated) |
| [[rpc/vpc-routetable-service\|RouteTableService]] | живо (stable) |
| [[rpc/vpc-securitygroup-service\|SecurityGroupService]] | живо (stable) |
| [[rpc/vpc-subnet-service\|SubnetService]] | живо (stable) |

### Рёбра рантайма — `edges/` (77)

**вызывающий: (не указан)**

| Записка | Состояние |
|---|---|
| [[edges/cilium-overlap-tier2-l3vpn\|VPC overlap на Cilium — решение (Tier 2 / real L3VPN)]] | в работе (experimental) |
| [[edges/registry-dataplane-public-tls\|registry data-plane → публичный TLS (docker login/push/pull)]] | живо (active) |
| [[edges/terraform-provider-to-gateway\|terraform-провайдер → api-gateway (REST)]] | живо (active) |

**вызывающий: cilium**

| Записка | Состояние |
|---|---|
| [[edges/iam-to-cilium-mesh\|iam ↔ cilium-mesh: mTLS via SPIFFE]] | в работе (planned) |

**вызывающий: google-workspace**

| Записка | Состояние |
|---|---|
| [[edges/iam-to-scim-google\|iam ← google-workspace: inbound SCIM 2.0]] | история (deprecated) |

**вызывающий: kacho-api-gateway**

| Записка | Состояние |
|---|---|
| [[edges/api-gateway-to-iam-acr-floor\|api-gateway → iam — acr-on-internal step-up floor]] | живо (stable) |
| [[edges/api-gateway-to-iam-authorize\|api-gateway → iam: AuthorizeService.Check (per-RPC)]] | живо (active) |
| [[edges/api-gateway-to-iam-subject-change\|api-gateway → iam: PollSubjectChanges (authz-cache invalidation)]] | живо (active) |
| [[edges/apigw-internal-rest-listener\|api-gateway public cmux vs internal-rest]] | живо (stable) |
| [[edges/apigw-internal-vs-tls\|api-gateway: TLS edge vs cluster-internal listener]] | живо (active) |
| [[edges/apigw-to-compute\|api-gateway → compute (proxy)]] | живо (active) |
| [[edges/apigw-to-rm\|api-gateway → rm (proxy)]] | история (deprecated) |
| [[edges/apigw-to-vpc\|api-gateway → vpc (proxy + REST routing)]] | живо (active) |

**вызывающий: kacho-compute**

| Записка | Состояние |
|---|---|
| [[edges/compute-to-geo-zone-validate\|compute → geo: Instance.zone_id validation (#82)]] | живо (active) |
| [[edges/compute-to-iam-check\|compute → iam: per-RPC OpenFGA Check (E3)]] | живо (active) |
| [[edges/compute-to-iam-fgaproxy\|compute → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)]] | живо (done) |
| [[edges/compute-to-iam-listobjects\|compute → iam: сужение страницы списка пакетной проверкой]] | живо (active) |
| [[edges/compute-to-registry-image-resolve\|compute → registry (bootSource image resolve)]] | в работе (planned) |
| [[edges/compute-to-rm-folder-check\|compute → rm: folder existence check]] | история (deprecated) |
| [[edges/compute-to-storage-volume-resolve\|compute → storage: boot/volume Referrer resolve (COMP-1/STOR-1 split)]] | живо (active) |
| [[edges/compute-to-vpc-nic-validate\|compute → vpc: NIC attach/detach + subnet placement (живое ребро)]] | живо (active) |

**вызывающий: kacho-deploy**

| Записка | Состояние |
|---|---|
| [[edges/kube-ovn-to-bgp-fabric\|kube-ovn-speaker → BGP route-reflector (data-plane маршрут-анонс)]] | история (deprecated) |

**вызывающий: kacho-geo**

| Записка | Состояние |
|---|---|
| [[edges/geo-to-iam-check\|geo → iam: per-RPC OpenFGA Check (#82)]] | живо (active) |

**вызывающий: kacho-iam**

| Записка | Состояние |
|---|---|
| [[edges/iam-caep-to-subscriber\|iam → caep-subscriber: outbound SET push]] | в работе (planned) |
| [[edges/iam-openfga-confirm-read-consistency\|owner-tuple confirm-read → OpenFGA HIGHER_CONSISTENCY]] | в работе (experimental) |
| [[edges/iam-to-apigateway-authzcache\|iam → api-gateway: subject_change push (authz-cache invalidation)]] | живо (active) |
| [[edges/iam-to-apigw-cache-invalidation\|kacho-iam → kacho-api-gateway (authz-cache invalidation push)]] | в работе (experimental) |
| [[edges/iam-to-clickhouse-audit\|iam ↔ clickhouse: audit query interface]] | в работе (planned) |
| [[edges/iam-to-hsm\|iam → hsm: PKCS#11 signing]] | в работе (planned) |
| [[edges/iam-to-hydra-admin\|iam → hydra-admin: OAuth2 client lifecycle]] | живо (active) |
| [[edges/iam-to-jackson-saml\|iam → jackson: SAML bridge]] | история (deprecated) |
| [[edges/iam-to-kafka-audit\|iam → kafka: audit event producer]] | в работе (planned) |
| [[edges/iam-to-kratos-admin\|iam → kratos-admin: Identity / Session lifecycle]] | в работе (planned) |
| [[edges/iam-to-nlb-resource-lifecycle\|iam → nlb: D-13 lifecycle subscribe (outbox stream)]] | в работе (planned) |
| [[edges/iam-to-opa\|iam ↔ opa: sidecar policy evaluation]] | в работе (planned) |
| [[edges/iam-to-openfga-check\|iam ↔ openfga: чтение вердикта и применение кортежей]] | живо (active) |
| [[edges/iam-to-openfga-grant-write\|kacho-iam → OpenFGA (grant/revoke write)]] | живо (active) |
| [[edges/iam-to-openfga-scope-grant\|iam → openfga: type-scoped scope_grant + per-verb (fix #177)]] | живо (done) |
| [[edges/iam-to-openfga-sync-revoke\|kacho-iam → OpenFGA (отзыв применяется синхронно)]] | живо (stable) |
| [[edges/iam-to-s3-audit\|iam → s3-audit: archival sink + Glacier]] | в работе (planned) |
| [[edges/iam-to-siem-datadog\|iam → siem-datadog: log forwarder]] | в работе (planned) |
| [[edges/iam-to-siem-splunk\|iam → siem-splunk: HEC forwarder]] | в работе (planned) |
| [[edges/iam-to-spire\|iam ↔ spire: SPIFFE Workload API]] | в работе (planned) |
| [[edges/iam-to-zitadel-oidc\|iam → zitadel: OIDC identity]] | в работе (planned) |

**вызывающий: kacho-nlb**

| Записка | Состояние |
|---|---|
| [[edges/nlb-to-compute-instance-resolve\|nlb → compute: Instance resolve (Target.instance_id)]] | живо (active) |
| [[edges/nlb-to-compute-region-validation\|nlb → compute: Region validation]] | история (deprecated) |
| [[edges/nlb-to-geo-region-validate\|nlb → geo: Region validation (#82)]] | живо (active) |
| [[edges/nlb-to-iam-check\|nlb → iam: per-RPC OpenFGA Check (E3)]] | живо (active) |
| [[edges/nlb-to-iam-creator-tuple\|nlb → iam: D-11 sync creator-tuple write (fgawrite)]] | история (deprecated) |
| [[edges/nlb-to-iam-fga-register\|nlb → iam: SEC-D FGA owner-tuple register (transactional-outbox → mTLS)]] | живо (active) |
| [[edges/nlb-to-iam-listobjects\|nlb → iam: сужение страницы списка пакетной проверкой]] | живо (active) |
| [[edges/nlb-to-vpc-byo-address\|nlb → vpc: link existing Address (SetReference CAS)]] | живо (active) |
| [[edges/nlb-to-vpc-nic-resolve\|nlb → vpc: NIC resolve (Target.nic_id)]] | живо (active) |
| [[edges/nlb-to-vpc-subnet-validation\|nlb → vpc: Subnet validation (INTERNAL Listener + Target ip_ref)]] | живо (active) |
| [[edges/nlb-to-vpc-vip-allocation\|nlb → vpc: VIP acquire/release (LoadBalancer)]] | живо (active) |

**вызывающий: kacho-registry**

| Записка | Состояние |
|---|---|
| [[edges/registry-to-geo-region-validate\|registry → geo: Namespace/Registry.region_id validation (REG-1 F4)]] | живо (active) |
| [[edges/registry-to-iam-anon-public\|registry ← iam: anonymous public pull (user:* wildcard, RG-1 D-7)]] | живо (active) |
| [[edges/registry-to-iam-fga-register\|registry → iam: owner-tuple register/unregister + публикация репозитория]] | живо (active) |
| [[edges/registry-to-iam-jwks-fetch\|registry → iam: JWKS-fetch (data-plane Bearer verify via iam proxy)]] | живо (active) |

**вызывающий: kacho-storage**

| Записка | Состояние |
|---|---|
| [[edges/storage-to-iam-fgaproxy\|storage → iam: FGA-proxy RegisterResource/UnregisterResource (SEC-D)]] | живо (done) |

**вызывающий: kacho-ui**

| Записка | Состояние |
|---|---|
| [[edges/ui-to-apigw-cluster-admins\|kacho-ui → kacho-api-gateway cluster-admins REST]] | живо (done) |
| [[edges/ui-to-zitadel-redirect\|ui → zitadel: OIDC redirect (signup-flow)]] | история (superseded) |

**вызывающий: kacho-vpc**

| Записка | Состояние |
|---|---|
| [[edges/iam-register-resource-callee-contract\|iam ← модули: приёмная сторона RegisterResource (зеркало, форвард, счётчик)]] | живо (active) |
| [[edges/vpc-to-compute-zone-validate\|vpc → compute: zone_id validation (KAC-15)]] | история (deprecated) |
| [[edges/vpc-to-geo-zone-validate\|vpc → geo: zone_id validation (#82)]] | живо (active) |
| [[edges/vpc-to-iam-check\|vpc → iam: per-RPC OpenFGA Check (E3)]] | живо (active) |
| [[edges/vpc-to-iam-fgaproxy\|vpc → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)]] | живо (active) |
| [[edges/vpc-to-iam-limit-resolve\|vpc → iam — разрешение действующего потолка и его дельта]] | в работе (planned) |
| [[edges/vpc-to-iam-listobjects\|vpc → iam: сужение страницы списка пакетной проверкой]] | живо (active) |
| [[edges/vpc-to-iam-project-exists\|vpc → iam: project existence check (replaces folder_id check)]] | живо (active) |
| [[edges/vpc-to-rm-folder-exists\|vpc → rm: folder existence check (DEPRECATED)]] | история (deprecated) |

**вызывающий: kacho-vpc-implement**

| Записка | Состояние |
|---|---|
| [[edges/vpc-implement-to-vpc\|vpc-implement → vpc: ReportNiDataplane (deprecated)]] | история (deprecated) |

**вызывающий: kacho-vpc-operator**

| Записка | Состояние |
|---|---|
| [[edges/vpc-operator-to-cilium-realization\|vpc-operator → cilium (VPC realization module)]] | в работе (planned) |
| [[edges/vpc-operator-to-kubeovn\|kacho-vpc-operator → kube-ovn / Multus (data-plane materialization)]] | история (deprecated) |
| [[edges/vpc-operator-to-vpc-mtls\|kacho-vpc-operator → kacho-vpc / kacho-iam (mTLS read-only sync)]] | в работе (planned) |

**вызывающий: microsoft-entra-id**

| Записка | Состояние |
|---|---|
| [[edges/iam-to-scim-azure\|iam ← azure-ad: inbound SCIM 2.0 (Microsoft Entra ID)]] | история (deprecated) |

**вызывающий: okta**

| Записка | Состояние |
|---|---|
| [[edges/iam-to-scim-okta\|iam ← okta: inbound SCIM 2.0 (Okta SCIM 2.0 Test App)]] | история (deprecated) |

### Пакеты — `packages/` (119)

**домен: (не указан)**

| Записка | Состояние |
|---|---|
| [[packages/terraform-provider\|terraform — провайдер Kachō для Terraform и OpenTofu]] | живо (active) |

**домен: cilium**

| Записка | Состояние |
|---|---|
| [[packages/kacho-vpc-cilium-compiler\|kacho-vpc-cilium compiler]] | в работе (planned) |

**домен: kacho**

| Записка | Состояние |
|---|---|
| [[packages/kacho-ci-determinism\|CI — детерминизм: пины версий и честные exit-коды]] | живо (stable) |
| [[packages/kacho-ci-runners\|CI монорепы — ранеры и раскладка job'ов]] | живо (stable) |
| [[packages/kacho-e2e-fullscope-plan\|e2e-newman fullscope — мастер-план добивания (все 4 сервиса)]] | в работе (in-progress) |
| [[packages/kacho-monorepo\|kacho — монорепа]] | живо (stable) |
| [[packages/kacho-newman-gate\|newman — гейт, known-RED и загрязнение фикстур]] | живо (stable) |
| [[packages/kacho-terraform-provider\|terraform — провайдер Kachō для Terraform и OpenTofu]] | живо (active) |

**домен: kacho-api-gateway**

| Записка | Состояние |
|---|---|
| [[packages/api-gateway-backend-dial-mtls\|api-gateway backend-dial mTLS (per-edge creds selection)]] | живо (stable) |
| [[packages/api-gateway-middleware-authz\|api-gateway-middleware-authz]] | живо (stable) |
| [[packages/api-gateway-middleware-dpop\|api-gateway-middleware-dpop]] | живо (stable) |
| [[packages/apigw-allowlist\|apigw-allowlist]] | живо (stable) |
| [[packages/apigw-cmd\|apigw-cmd]] | живо (stable) |
| [[packages/apigw-config\|apigw-config]] | живо (stable) |
| [[packages/apigw-health\|apigw-health]] | живо (stable) |
| [[packages/apigw-middleware\|apigw-middleware]] | живо (stable) |
| [[packages/apigw-opsproxy\|apigw-opsproxy]] | живо (stable) |
| [[packages/apigw-proxy\|apigw-proxy]] | живо (stable) |
| [[packages/apigw-restmux\|apigw-restmux]] | живо (stable) |

**домен: kacho-compute**

| Записка | Состояние |
|---|---|
| [[packages/compute-internal-check\|kacho-compute/internal/check]] | живо (stable) |

**домен: kacho-corelib**

| Записка | Состояние |
|---|---|
| [[packages/corelib-auth\|kacho-corelib/auth]] | живо (stable) |
| [[packages/corelib-authz-listobjects\|corelib-authz-listobjects]] | история (wontfix) |
| [[packages/corelib-authz\|kacho-corelib/authz]] | живо (stable) |
| [[packages/corelib-backoff\|corelib-backoff]] | живо (stable) |
| [[packages/corelib-baggage\|corelib-baggage]] | живо (stable) |
| [[packages/corelib-config\|corelib-config]] | живо (stable) |
| [[packages/corelib-db\|corelib-db]] | живо (stable) |
| [[packages/corelib-errors\|corelib-errors]] | живо (stable) |
| [[packages/corelib-filter\|corelib-filter]] | живо (stable) |
| [[packages/corelib-grpcclient\|corelib-grpcclient]] | живо (stable) |
| [[packages/corelib-grpcsrv\|corelib-grpcsrv]] | живо (stable) |
| [[packages/corelib-ids\|corelib-ids]] | живо (stable) |
| [[packages/corelib-observability\|corelib-observability]] | живо (stable) |
| [[packages/corelib-operations\|corelib-operations]] | живо (stable) |
| [[packages/corelib-outbox-drainer\|corelib-outbox-drainer]] | живо (stable) |
| [[packages/corelib-outbox\|corelib-outbox]] | живо (stable) |
| [[packages/corelib-peer\|pkg/peer — полоса ответа соседа: единственное место, где чужой отказ становится нашим]] | живо (stable) |
| [[packages/corelib-quota\|corelib-quota]] | в работе (in-progress) |
| [[packages/corelib-retry\|corelib-retry]] | живо (stable) |
| [[packages/corelib-servicehost\|pkg/servicehost + pkg/servicecontract — носитель контура работы сервиса с моделью прав]] | живо (stable) |
| [[packages/corelib-shutdown\|corelib-shutdown]] | история (wontfix) |
| [[packages/corelib-validate\|corelib-validate]] | живо (stable) |

**домен: kacho-geo**

| Записка | Состояние |
|---|---|
| [[packages/geo-domain\|geo-domain]] | в работе (in-progress) |

**домен: kacho-iam**

| Записка | Состояние |
|---|---|
| [[packages/iam-apps-cluster-usecases\|iam apps cluster use-cases]] | живо (stable) |
| [[packages/iam-authzguard\|iam authzguard]] | живо (stable) |
| [[packages/iam-domain\|iam internal/domain]] | живо (done) |
| [[packages/iam-extensions-retired\|iam-extensions-retired]] | история (deprecated) |
| [[packages/iam-handler-iamhooks\|iam internal/handler/iamhooks]] | живо (done) |
| [[packages/iam-handler-internal-cluster\|iam handler internal_cluster]] | живо (stable) |
| [[packages/iam-jobs\|iam-jobs]] | история (deprecated) |
| [[packages/iam-pg-fga-outbox\|kacho-iam · internal/repo/kacho/pg/fga_outbox]] | живо (stable) |
| [[packages/iam-repo-kacho-pg\|iam internal/repo/kacho/pg]] | живо (done) |
| [[packages/iam-seed\|iam internal/apps/kacho/seed]] | живо (done) |
| [[packages/iam-tests-newman-scripts\|tests/newman/scripts (kacho-iam)]] | живо (stable) |
| [[packages/nlb-permissions-catalog\|kacho-nlb permissions catalog]] | живо (stable) |

**домен: kacho-nlb**

| Записка | Состояние |
|---|---|
| [[packages/nlb-apps-kacho-api-internal-lifecycle\|nlb-apps-kacho-api-internal-lifecycle]] | живо (stable) |
| [[packages/nlb-apps-kacho-api-listener\|nlb-apps-kacho-api-listener]] | живо (stable) |
| [[packages/nlb-apps-kacho-api-loadbalancer\|nlb-apps-kacho-api-loadbalancer]] | живо (stable) |
| [[packages/nlb-apps-kacho-api-operation\|nlb-apps-kacho-api-operation]] | живо (stable) |
| [[packages/nlb-apps-kacho-api-targetgroup\|nlb-apps-kacho-api-targetgroup]] | живо (stable) |
| [[packages/nlb-apps-kacho-jobs\|nlb-apps-kacho-jobs]] | живо (stable) |
| [[packages/nlb-clients-compute\|nlb-clients-compute]] | живо (stable) |
| [[packages/nlb-clients-iam\|nlb-clients-iam]] | живо (stable) |
| [[packages/nlb-clients-vpc\|nlb-clients-vpc]] | живо (stable) |
| [[packages/nlb-domain\|nlb-domain]] | живо (stable) |
| [[packages/nlb-internal-check\|kacho-nlb/internal/check]] | живо (stable) |
| [[packages/nlb-internal-fgawrite\|nlb-internal-fgawrite]] | живо (stable) |
| [[packages/nlb-repo-kacho-pg\|nlb-repo-kacho-pg]] | живо (stable) |
| [[packages/nlb-tests-k6\|nlb-tests-k6]] | живо (stable) |
| [[packages/nlb-tests-newman\|nlb-tests-newman]] | живо (stable) |

**домен: kacho-proto**

| Записка | Состояние |
|---|---|
| [[packages/proto-access\|proto-access]] | история (legacy) |
| [[packages/proto-api\|proto-api]] | живо (stable) |
| [[packages/proto-compute\|proto-compute]] | живо (stable) |
| [[packages/proto-geo\|proto-geo]] | живо (stable) |
| [[packages/proto-loadbalancer\|proto-loadbalancer]] | живо (stable) |
| [[packages/proto-operation\|proto-operation]] | живо (stable) |
| [[packages/proto-organizationmanager\|proto-organizationmanager]] | история (deprecated) |
| [[packages/proto-reference\|proto-reference]] | живо (stable) |
| [[packages/proto-rm\|proto-rm]] | история (deprecated) |
| [[packages/proto-root\|proto-root]] | живо (stable) |
| [[packages/proto-vpc\|proto-vpc]] | живо (stable) |

**домен: kacho-resource-manager**

| Записка | Состояние |
|---|---|
| [[packages/rm-bootstrap\|rm-bootstrap]] | история (deprecated) |
| [[packages/rm-cmd\|rm-cmd]] | история (deprecated) |
| [[packages/rm-config\|rm-config]] | история (deprecated) |
| [[packages/rm-domain\|rm-domain]] | история (deprecated) |
| [[packages/rm-handler\|rm-handler]] | история (deprecated) |
| [[packages/rm-repo\|rm-repo]] | история (deprecated) |
| [[packages/rm-service\|rm-service]] | история (deprecated) |

**домен: kacho-ui**

| Записка | Состояние |
|---|---|
| [[packages/ui-pages-auth\|ui — страницы входа и контекст личности]] | история (legacy) |

**домен: kacho-vpc**

| Записка | Состояние |
|---|---|
| [[packages/vpc-apps-kacho-api-address\|vpc-apps-kacho-api-address]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-addresspool\|vpc-apps-kacho-api-addresspool]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-gateway\|vpc-apps-kacho-api-gateway]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-network\|vpc-apps-kacho-api-network]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-networkinterface\|vpc-apps-kacho-api-networkinterface]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-routetable\|vpc-apps-kacho-api-routetable]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-securitygroup\|vpc-apps-kacho-api-securitygroup]] | живо (stable) |
| [[packages/vpc-apps-kacho-api-subnet\|vpc-apps-kacho-api-subnet]] | живо (stable) |
| [[packages/vpc-apps-kacho-check\|kacho-vpc/internal/apps/kacho/check]] | живо (stable) |
| [[packages/vpc-apps-kacho-config\|vpc-apps-kacho-config]] | живо (stable) |
| [[packages/vpc-apps-kacho-services-addressref\|vpc-apps-kacho-services-addressref]] | живо (stable) |
| [[packages/vpc-apps-kacho-services-networkinternal\|vpc-apps-kacho-services-networkinternal]] | живо (stable) |
| [[packages/vpc-apps-kacho-shared-macutil\|vpc-apps-kacho-shared-macutil]] | живо (stable) |
| [[packages/vpc-apps-kacho-shared-pbconv\|vpc-apps-kacho-shared-pbconv]] | живо (stable) |
| [[packages/vpc-apps-kacho-shared-serviceerr\|vpc-apps-kacho-shared-serviceerr]] | живо (stable) |
| [[packages/vpc-apps-migrator\|vpc-apps-migrator]] | живо (stable) |
| [[packages/vpc-clients\|vpc-clients]] | живо (stable) |
| [[packages/vpc-cmd-migrator\|vpc-cmd-migrator]] | живо (stable) |
| [[packages/vpc-cmd-vpc\|vpc-cmd-vpc]] | живо (stable) |
| [[packages/vpc-domain\|vpc-domain]] | живо (stable) |
| [[packages/vpc-dto-toproto\|vpc-dto-toproto]] | живо (stable) |
| [[packages/vpc-dto\|vpc-dto]] | живо (stable) |
| [[packages/vpc-handler\|vpc-handler]] | живо (stable) |
| [[packages/vpc-repo-cqrsadapter\|vpc-repo-cqrsadapter]] | живо (stable) |
| [[packages/vpc-repo-helpers\|vpc-repo-helpers]] | живо (stable) |
| [[packages/vpc-repo-kacho-kachomock\|vpc-repo-kacho-kachomock]] | живо (stable) |
| [[packages/vpc-repo-kacho-pg\|vpc-repo-kacho-pg]] | живо (stable) |
| [[packages/vpc-repo-kacho\|vpc-repo-kacho]] | живо (stable) |
| [[packages/vpc-repo-repomock\|vpc-repo-repomock]] | живо (stable) |

**домен: витрина категории**

| Записка | Состояние |
|---|---|
| [[packages/all-packages\|all-packages]] | — |

### Журнал работ (KAC) — `KAC/` (327)

| Записка | Состояние |
|---|---|
| [[KAC/5.1-iam-internal-reads-system-viewer-floor\|[trail] 5.1 — system_viewer-floor on kacho-iam internal-read RPCs (:9091)]] | живо (done) |
| [[KAC/CIL0-network-vrf-id\|CIL0: Network vrf_id alloc + InternalNetworkService.GetNetwork]] | живо (done) |
| [[KAC/DIVERGENCE-A-unify-iam-label-scope\|DIVERGENCE-A — unify IAM label-scope (all iam-types label-selectable)]] | живо (done) |
| [[KAC/EPIC-SEC-mtls-iam-authz\|[EPIC] SEC — mTLS + IAM-fronted authz + least-privilege identities]] | живо (done) |
| [[KAC/EPIC-geo-extraction\|[EPIC] kacho-geo: extract Geography (Region/Zone) into a leaf-service]] | живо (done) |
| [[KAC/GEO-1\|GEO-1 — Region/Zone redesign (two-projection, sync Operation)]] | живо (done) |
| [[KAC/IAM-INT-1-interactive-login\|[trail] IAM-INT-1 — интерактивный вход человека (S1+S2 посажены, церемония исполняется)]] | в работе (in-progress) |
| [[KAC/KAC-104\|KAC-104: Kachō IAM — Account/Project + Zitadel + OpenFGA (REBAC)]] | история (superseded) |
| [[KAC/KAC-105\|KAC-105: E0 — kacho-iam skeleton + Account/Project/User/SA/Group/Role CRUD]] | живо (done) |
| [[KAC/KAC-106\|KAC-106: E1 — folder_id → project_id migration (hard rename)]] | живо (done) |
| [[KAC/KAC-107\|KAC-107: E2 — Zitadel OIDC deploy + auth-interceptor + Principal in ctx]] | история (superseded) |
| [[KAC/KAC-108\|KAC-108: E3 — OpenFGA REBAC + Check-interceptor + реактивность ≤10s]] | живо (done) |
| [[KAC/KAC-109\|KAC-109: E4 — IAM UI block (CRUD 7 ресурсов) + Operations principal column]] | история (superseded) |
| [[KAC/KAC-110\|KAC-110: E5 — Deprecate kacho-resource-manager + cleanup]] | история (superseded) |
| [[KAC/KAC-111\|KAC-111: Squash kacho-vpc migrations 0001..0034 → 0001 (greenfield)]] | живо (done) |
| [[KAC/KAC-112\|KAC-112: E0 follow-up — IAM resources backend (Project/User/SA/Group/Role/AccessBinding)]] | живо (done) |
| [[KAC/KAC-113\|KAC-113: E0 follow-up — sync principal_* в kacho-vpc/compute/rm/loadbalancer]] | живо (done) |
| [[KAC/KAC-115\|KAC-115: Migrate Zitadel + OpenFGA → Ory stack (Kratos + Hydra + Keto)]] | живо (done) |
| [[KAC/KAC-116\|KAC-116: Ory stack follow-up — Keto AuthZ + Kratos session + DoD#3/4/5]] | живо (done) |
| [[KAC/KAC-122\|KAC-122: AuthZ default-deny matrix newman tests (6 subjects × full CRUD × 3 services)]] | живо (done) |
| [[KAC/KAC-123\|KAC-123: Group default-deny + UI AccessBindings visibility + AccountCrumb fix]] | живо (done) |
| [[KAC/KAC-124\|KAC-124: Полное удаление kacho-resource-manager (E5 closeout)]] | живо (done) |
| [[KAC/KAC-125\|KAC-125: User per-Account + Invite-flow + Cascader UI]] | живо (done) |
| [[KAC/KAC-126\|KAC-126: IAM Newman Test Coverage — оживить мёртвые iam-*.py сюиты]] | в работе (in-progress) |
| [[KAC/KAC-127\|KAC-127 (vault-label) / YT KAC-123: Production-Ready Next-Gen IAM (FULL)]] | живо (done) |
| [[KAC/KAC-128\|KAC-128: AccessBinding.Create idempotency — metadata returns existing id on 5-tuple conflict]] | живо (done) |
| [[KAC/KAC-129\|KAC-129: Symmetric FGA grant/revoke tuples (findings #8/#16/#47/#48)]] | живо (done) |
| [[KAC/KAC-130\|KAC-130: BUG-2 — authz interceptor returns 403/7 for missing credentials (should be 401/16)]] | живо (done) |
| [[KAC/KAC-131\|KAC-131: IAM authz remediation — BUG-3/6/8 fix + newman re-measurement]] | живо (done) |
| [[KAC/KAC-132\|KAC-132: Newman E2E — close Cat-C failures (iam-jit-pending + iam-compliance-report)]] | в работе (in-progress) |
| [[KAC/KAC-133\|KAC-133: close remaining newman assertion failures + authz.ErrNoPath passthrough]] | живо (done) |
| [[KAC/KAC-134\|KAC-134: kacho-iam Full-scope production-ready (epic)]] | история (superseded) |
| [[KAC/KAC-135\|KAC-135: W0 — Newman coverage gate + OpenFGA HA bootstrap]] | живо (done) |
| [[KAC/KAC-136\|KAC-136: W1 — AuthZ critical path (drainer + cache invalidation + Chunks 1+2)]] | живо (done) |
| [[KAC/KAC-137\|KAC-137: W1.1 — fga_outbox drainer (corelib) + FGAApplier wiring (iam)]] | живо (done) |
| [[KAC/KAC-138\|KAC-138: W1.2 — subject_change_outbox push-drain + gateway cache invalidation]] | живо (done) |
| [[KAC/KAC-139\|KAC-139: W1.3 — Gateway authz-middleware fail-closed enable]] | живо (done) |
| [[KAC/KAC-140\|KAC-140: W1.4 — Principal propagation cross-service]] | живо (done) |
| [[KAC/KAC-141\|KAC-141: kacho-nlb — L4 Network Load Balancer control-plane (production-ready)]] | живо (done) |
| [[KAC/KAC-15\|KAC-15: Geography (Region/Zone) moved kacho-vpc → kacho-compute]] | живо (done) |
| [[KAC/KAC-163\|KAC-163: W1.5 — Remediation Chunk 1 (DB/FGA grant-write desync)]] | живо (done) |
| [[KAC/KAC-164\|KAC-164: W1.6 — Remediation Chunk 2 (in-service authz + closeout)]] | живо (done) |
| [[KAC/KAC-165\|KAC-165: VPC Newman 100% coverage по Testing Model]] | история (superseded) |
| [[KAC/KAC-169\|KAC-169: opsproxy.Get/Cancel drops principal metadata → backend NotFound]] | живо (done) |
| [[KAC/KAC-170\|KAC-170: W2/W3 acceptance docs bundle (8 docs) for kacho-iam prod-ready]] | живо (done) |
| [[KAC/KAC-174\|KAC-174: kacho-nlb config DSN — expand $(VAR) placeholder for postgres password]] | живо (done) |
| [[KAC/KAC-175\|KAC-175: kacho-deploy — Kratos/Hydra port-portable auth flow]] | живо (done) |
| [[KAC/KAC-176\|KAC-176: newman-e2e — kacho-iam authz suite assertions fail (regression, post-KAC-141)]] | в работе (to-do) |
| [[KAC/KAC-178\|KAC-178: Stand prod-readiness — закрыть 5 backend gaps после KAC-171/175]] | живо (done) |
| [[KAC/KAC-179\|KAC-179: kacho-api-gateway — fix 3 pre-existing failed unit tests]] | живо (done) |
| [[KAC/KAC-180\|KAC-180: Test plans for 7 APPROVED W2/W3 acceptance docs]] | живо (done) |
| [[KAC/KAC-181\|KAC-181: Hybrid-mode docs batch — 3.7b sync + migration coord + newman finding]] | живо (done) |
| [[KAC/KAC-182\|KAC-182: Wave 2A — F2/F3/F6 newman regression fixes (test-only)]] | живо (done) |
| [[KAC/KAC-183\|KAC-183: F1 — MinIO StatefulSet for dev compliance reports]] | живо (done) |
| [[KAC/KAC-184\|KAC-184: F5 — whitelist AuthorizeService.ListObjects/ListSubjects in kacho-iam authzguard]] | живо (done) |
| [[KAC/KAC-185\|KAC-185: F4 — Internal IAM RPCs lack google.api.http annotation]] | живо (done) |
| [[KAC/KAC-186\|KAC-178: W3.4 freeze gate + workspace CI fix]] | история (superseded) |
| [[KAC/KAC-188\|KAC-188: newman iam main → GREEN — iterative epic]] | живо (done) |
| [[KAC/KAC-189\|KAC-189: kacho-iam — RoleReadAdapter.Get SELECT 10 cols vs scanRole 7 cols]] | живо (done) |
| [[KAC/KAC-190\|KAC-190: InternalIAMService.ListPermissions 501 — DUPLICATE of KAC-188 PR #43]] | живо (done) |
| [[KAC/KAC-191\|KAC-191: kacho-iam — permission_catalog.json mirror has empty `permission` fields]] | живо (done) |
| [[KAC/KAC-192\|KAC-192: kacho-iam — w1-nm-closeout newman cases use unregistered REST paths]] | история (superseded) |
| [[KAC/KAC-193\|KAC-193: [EPIC] kacho-iam production-cleanup refactor (5 waves)]] | история (superseded) |
| [[KAC/KAC-194\|KAC-194: Wave A — kacho-iam cleanup (comments + KAC + phase markers + file/folder renames)]] | живо (done) |
| [[KAC/KAC-196\|KAC-196: InternalClusterService — cluster admin RBAC]] | живо (done) |
| [[KAC/KAC-197\|KAC-197: Phase 3c — Federation OUT (kacho as OIDC IdP)]] | в работе (in-progress) |
| [[KAC/KAC-198\|KAC-198: Phase 4 — drop JIT + simplify GDPR (keep break-glass)]] | история (superseded) |
| [[KAC/KAC-199\|KAC-199: UI auth — sidebar login button broken + missing RequireAuth guard]] | живо (done) |
| [[KAC/KAC-2\|KAC-2: NetworkInterface first-class ресурс + control-plane resource model]] | история (superseded) |
| [[KAC/KAC-201\|KAC-201: [EPIC] Internal-tier authz hardening — 44 unguarded Internal.* methods]] | живо (done) |
| [[KAC/KAC-214\|KAC-214 [EPIC] RBAC v2 — 4-seg grammar + scoped AccessBinding + list-filter + SCIM/SAML/BG removal]] | живо (done) |
| [[KAC/KAC-215\|KAC-215 [W2 RBAC v2] kacho-proto: Scope enum, wildcard_grant, drop BG/SCIM/SAML]] | живо (done) |
| [[KAC/KAC-216\|KAC-216 [W3 RBAC v2] kacho-iam migrations 0005 + 0006]] | живо (done) |
| [[KAC/KAC-217\|KAC-217 [W4 RBAC v2] kacho-iam code: authzmap, fga_tuple_writer, scope plumbing, BG/SCIM/SAML removal]] | живо (done) |
| [[KAC/KAC-218\|KAC-218 [W5 RBAC v2] kacho-api-gateway: REST routes + catalog + allowlist]] | живо (done) |
| [[KAC/KAC-219\|KAC-219 [W6 RBAC v2] kacho-vpc + kacho-compute: list-filter audit + CI gate]] | живо (done) |
| [[KAC/KAC-220\|KAC-220 [W7 RBAC v2] kacho-deploy: helm cleanup + newman list-filter regression]] | живо (done) |
| [[KAC/KAC-221\|KAC-221 [W8 RBAC v2] vault refresh + epic close]] | живо (done) |
| [[KAC/KAC-222\|kacho-iam — final skeleton / no-op / mock-instead-of-real cleanup]] | живо (done) |
| [[KAC/KAC-223\|kacho-iam production-strict cleanup — no dev-disable, dead Org/SCIM/SAML + dead config removed]] | живо (done) |
| [[KAC/KAC-224\|KAC-224: [kacho-ui] RBAC v2 adaptation — scope column + drop dead resource_type]] | живо (done) |
| [[KAC/KAC-225\|KAC-225: gateway WhoAmI GET /iam/v1/me отсутствует в route-table → 403]] | живо (done) |
| [[KAC/KAC-226\|KAC-226: UI NLB список пуст — payloadKey load_balancers vs network_load_balancers]] | живо (done) |
| [[KAC/KAC-227\|KAC-227: NLB authz object_type mismatch nlb_* vs FGA lb_* → Get/sub-list 403]] | живо (done) |
| [[KAC/KAC-228\|KAC-228: dev-up не сеет cluster viewer:* и не зовёт fga-bootstrap → 403 regions / 503 projects]] | живо (done) |
| [[KAC/KAC-229\|KAC-229: ListenerService.List → project-scoped (+ KAC-227 nlb-слой)]] | живо (done) |
| [[KAC/KAC-230\|KAC-230: UI — управление targets у TargetGroup (AddTargets/RemoveTargets)]] | живо (done) |
| [[KAC/KAC-231\|KAC-231: [EPIC] kacho-ui — единый лайаут детализации + формы-панели]] | в работе (in-progress) |
| [[KAC/KAC-239\|KAC-239 — VPC redesign (Network defaultSG · SG used_by · granular rules/routes)]] | история (superseded) |
| [[KAC/KAC-240\|KAC-240 — stale-after-create: List RBAC v2 filter скрывает свежесозданный ресурс]] | живо (done) |
| [[KAC/KAC-241\|KAC-241 — kacho-ui: унификация Create/Edit форм + UX-уплифт (ResourceFormBody)]] | живо (done) |
| [[KAC/KAC-242\|KAC-242 — kacho-ui: действия из таба «Обзор» в шапку detail-страницы]] | в работе (test) |
| [[KAC/KAC-243\|KAC-243 — SG↔Network: обязательна + immutable; правила SG→SG только в одной сети]] | живо (done) |
| [[KAC/KAC-244\|KAC-244 — gRPC keepalive отсутствует на части inter-service dial → authz Check зависает ~30с]] | живо (done) |
| [[KAC/KAC-245\|KAC-245 — UI: Name+ID первые две колонки во всех таблицах по умолчанию]] | в работе (test) |
| [[KAC/KAC-246\|KAC-246: kacho-ui визуальный апгрейд — Фаза 1 (фундамент премиум-UI)]] | в работе (in-progress) |
| [[KAC/KAC-248\|KAC-248: kacho-docs — публичный документационный портал]] | история (superseded) |
| [[KAC/KAC-251\|KAC-251: kacho-proto — apisurface (canonical allowlist) + openapi-filter]] | история (wontfix) |
| [[KAC/KAC-252\|KAC-252: kacho-docs scaffold + тема + P7]] | живо (done) |
| [[KAC/KAC-253\|KAC-253: kacho-api-gateway — allowlist import-switch на kacho-proto/apisurface]] | история (wontfix) |
| [[KAC/KAC-255\|KAC-255: kacho-docs контент + IA + persona-tabs]] | живо (done) |
| [[KAC/KAC-256\|KAC-256: kacho-docs Dockerfile + nginx + Helm + запуск]] | живо (done) |
| [[KAC/KAC-257\|KAC-257: kacho-docs AI-native + OperationEnvelope]] | живо (done) |
| [[KAC/KAC-261\|KAC-261: kacho-vpc — чистка мёртвого кода + squash миграций + evgeniy + зелёный CI]] | в работе (test) |
| [[KAC/KAC-262\|KAC-262: kacho-vpc — продуктовая документация (Docusaurus)]] | в работе (test) |
| [[KAC/KAC-263\|KAC-263: test-infra — zero-manual self-provisioning + бессрочный токен]] | в работе (test) |
| [[KAC/KAC-264\|KAC-264: выпилить PrivateEndpointService (unused)]] | живо (done) |
| [[KAC/KAC-265\|KAC-265: выпил мёртвого kube-ovn data-plane-легаси из доков/кода/obsidian]] | живо (done) |
| [[KAC/KAC-266\|KAC-266: contract-removal — Move / NIC attach-detach / AddressPool override+selector / no auto-NIC]] | живо (done) |
| [[KAC/KAC-268\|KAC-268: SG status removal + docs-UX + data-plane purge]] | живо (done) |
| [[KAC/KAC-269\|KAC-269: AddressPool CIDR-управление как у Subnet]] | живо (done) |
| [[KAC/KAC-271\|KAC-271: per-resource VPC id-prefixes (net/sub/adr/rtb/sgr/gtw/nic/apl)]] | живо (done) |
| [[KAC/KAC-272\|KAC-272: AddressPool DB-level CIDR overlap prevention (EXCLUDE gist)]] | живо (done) |
| [[KAC/KAC-273\|KAC-273: addresses-tab пула — колонки имя/идентификатор/IP-адрес/дата создания]] | в работе (test) |
| [[KAC/KAC-50\|KAC-50: api-gateway listener split (public/TLS vs cluster-internal)]] | живо (done) |
| [[KAC/KAC-52\|KAC-52: NIC attach race fix (atomic CAS)]] | живо (done) |
| [[KAC/KAC-55\|KAC-55: NIC v4/v6 cardinality ≤ 1 (DB CHECK)]] | живо (done) |
| [[KAC/KAC-56\|KAC-56: RouteTable ↔ Subnet auto-association (DB triggers)]] | живо (done) |
| [[KAC/KAC-71\|KAC-71: AddressPool v4/v6 split + cascade family-filter]] | живо (done) |
| [[KAC/KAC-94\|KAC-94: Skill evgeniy 100% эталон в kacho-vpc]] | живо (done) |
| [[KAC/KAC-WS23\|KAC-124 (vault-label WS23): WS-2.3 — AuthZ decision-cache invalidation on grant/revoke]] | живо (done) |
| [[KAC/KAC-XC-11\|KAC-XC-11: конформанс участия сервиса в контракте прав]] | в работе (in-progress) |
| [[KAC/KAC-XC-2\|KAC-XC-2: единая библиотека интеграции с правами]] | в работе (planned) |
| [[KAC/KAC-XC-3\|KAC-XC-3: набор глаголов принадлежит типу]] | в работе (in-progress) |
| [[KAC/KAC-XC-7\|KAC-XC-7: единый контур работы с iam — носитель]] | в работе (in-progress) |
| [[KAC/KAC-newman-100pct-batch\|KAC batch: Newman 100% green push (2026-05-26)]] | в работе (in-progress) |
| [[KAC/KAC-registry-iam-jwks-unify\|registry-iam-jwks-unify: registry verifies via iam INTERNAL Hydra-JWKS proxy]] | живо (done) |
| [[KAC/NLB-1b-expand-loadbalancer-listener-core\|NLB-1b EXPAND — LoadBalancer + Listener core (parallel-change)]] | живо (done) |
| [[KAC/NLB-1c-targetgroup-redesign\|NLB-1c — TargetGroup HealthCheck redesign]] | живо (done) |
| [[KAC/OP2-P-BGP\|OP2-P-BGP: subnet routing via kube-ovn-speaker BGP (replaces stripped Vpc.staticRoutes)]] | живо (done) |
| [[KAC/OP2-P2-routetable\|OP2-P2: KachoRouteTable CRD + RouteTable → Vpc.staticRoutes materialization]] | история (superseded) |
| [[KAC/OP3-MULTIAZ\|OP3-MULTIAZ: cross-zone pod L3 within a VPC across 2 zonal kind clusters + isolation]] | история (superseded) |
| [[KAC/PROD-READINESS-iam-2026-06\|[trail] kacho-iam production-readiness sweep (2026-06-16)]] | живо (done) |
| [[KAC/RG-1-registry-repository-overlay\|[trail] RG-1 — Registry Repository config-overlay + visibility + referrers]] | живо (done) |
| [[KAC/SEC-A-proto-fga-proxy\|SEC-A: proto Internal IAM FGA-proxy (RegisterResource / UnregisterResource)]] | живо (done) |
| [[KAC/SEC-B-corelib-mtls\|SEC-B: corelib mTLS transport (grpcsrv/grpcclient + identity-extractor)]] | живо (done) |
| [[KAC/SEC-C-iam-fga-proxy-sa-roles\|SEC-C: IAM FGA-proxy (Register/UnregisterResource) + least-priv SA-roles (ReBAC) + cert→SA]] | живо (done) |
| [[KAC/SEC-D-services-fga-via-iam-mtls\|SEC-D: vpc/compute/nlb — FGA via IAM (transactional-outbox) + opt-in mTLS]] | живо (done) |
| [[KAC/SEC-E-gateway-mtls\|SEC-E: api-gateway backend-dial mTLS (per-edge), JWT/principal/Check preserved]] | живо (done) |
| [[KAC/SEC-G-operators-ovn-mtls\|SEC-G: operators on mTLS (operator→{vpc,iam} client-cert) + least-priv SA + full-stack]] | история (superseded) |
| [[KAC/SEC-HAT-provider-admin-hop-tls\|SEC-HAT: административный переход к провайдеру личности — TLS терминатором-соседом]] | живо (done) |
| [[KAC/SEC-J-gateway-hydra-jwks-authn\|SEC-J: api-gateway validates real Hydra RS256 access JWTs in the principal path]] | живо (done) |
| [[KAC/SEC-L-rest-internal-isolation\|SEC-L: isolate Internal* REST from the external listener + drop Internal* FQNs from public allowlist]] | живо (done) |
| [[KAC/_TEMPLATE\|#<N>: <one-line summary>]] | в работе (in-progress) |
| [[KAC/api-ux-review-redesign\|API-UX ревью редизайна — панель критиков (раунд 1)]] | в работе (reference) |
| [[KAC/audit-divergence-redesign-vs-main\|Аудит расхождения redesign/integration vs main — раунд 1]] | в работе (reference) |
| [[KAC/audit-hardening-low-2026-07-09\|audit-hardening-low-2026-07-09]] | живо (done) |
| [[KAC/audit-hardening-r5-8-2026-07-08\|audit-hardening-r5-8-2026-07-08]] | живо (done) |
| [[KAC/audit-loop-prompt\|Массированный аудит-рефакторинг — промт-контур (loop-until-dry)]] | в работе (reference) |
| [[KAC/audit-round-2-2026-07-29\|Аудит-раунд 2 — 2026-07-29]] | в работе (reference) |
| [[KAC/audit-round-2026-07-28-findings\|Аудит-раунд 2026-07-28 — 11 зон, 75 поднято, 68 подтверждено]] | в работе (reference) |
| [[KAC/audit-round-5-2026-07-30\|Аудит-раунд 5 — критический (2026-07-30)]] | живо (done) |
| [[KAC/audit-sweep-2026-07-27-findings\|Развёртка аудита 2026-07-27 — 230 подтверждённых, 11 классов]] | в работе (reference) |
| [[KAC/ci-red-triage-iam-storage-registry\|CI e2e-newman red-triage — iam/storage/registry (post geo-seed)]] | живо (done) |
| [[KAC/compute-list-leak-fix\|compute List label-scope over-show leak fix — subject-source mismatch]] | живо (done) |
| [[KAC/compute-redesign-2026\|Compute module — пересборка 2026]] | в работе (planned) |
| [[KAC/debt-waves-2026-08-08\|Две волны закрытия технического долга — 2026-08-08, восемь коммитов в ствол]] | живо (done) |
| [[KAC/declared-enabled-cannot-execute-2026-08-04\|Объявлено, включено — и исполниться не может (2026-08-04)]] | в работе (in-progress) |
| [[KAC/dormant-fix-honest-negative-2026-08-05\|Спящая правка и честный отрицательный результат (2026-08-05)]] | живо (done) |
| [[KAC/e2e-local-first-2026-07-25\|Локальный цикл e2e — что он вскрыл за один день]] | в работе (reference) |
| [[KAC/epic-100-resource-scoped-access-binding\|epic-100 — Resource-scoped AccessBinding (target-в-binding)]] | живо (done) |
| [[KAC/epic-103-rsab-beta-gamma\|epic-103 — Resource-scoped AccessBinding β/γ/condition/δ]] | живо (done) |
| [[KAC/epic-107-rsab-selectors\|epic-107 — RSAB selectors all-services + type-dedup + role-grouping]] | живо (done) |
| [[KAC/executor-refutes-the-brief-2026-08-05\|Постановка задачи — тоже утверждение о дереве (2026-08-05)]] | живо (done) |
| [[KAC/failed-precondition-is-400-not-412\|Отказ по состоянию ресурса — это 400, а не 412 (перепись 2026-08-04)]] | живо (done) |
| [[KAC/fga-register-throughput-inversion\|FGA register-pipeline throughput inversion + drainer false-poison]] | живо (done) |
| [[KAC/forwarded-identity-trust-2026-07-27\|Кто вправе говорить за пользователя — класс и его закрытие]] | живо (done) |
| [[KAC/geo-baseline-greenfield-seed-gap\|geo baseline НЕ засеян на greenfield stand — deploy-flow gap]] | в работе (in-progress) |
| [[KAC/green-here-is-not-green-there-2026-08-04\|Зелёное здесь ≠ зелёное там — оси, по которым расходятся среды (2026-08-04)]] | живо (done) |
| [[KAC/iam-accessbinding-forward-materialization\|iam AccessBinding forward-fast-path materialization]] | живо (done) |
| [[KAC/iam-invite-grant-fga-fix\|IAM invite/grant FGA — anchor-grant emits 0 + invite-activation no member-tuple + every-user default account]] | живо (done) |
| [[KAC/iam-ui-vpc-parity\|IAM UI ↔ VPC parity (sub-phase 2.1) — UI-only epic]] | живо (done) |
| [[KAC/inservice-authz-scope-parity-2026-07-22\|inservice-authz-scope-parity-2026-07-22]] | живо (done) |
| [[KAC/issue-138-f5\|XC-12 Ф5: перезамер стоимости полномодельной формы на сегодняшнем дереве]] | живо (done) |
| [[KAC/issue-138\|XC-12: ролевая модель внутри iam — перенос остановлен после Ф5 (#138)]] | в работе (in-progress) |
| [[KAC/issue-158\|[trail] issue-158 — вычисления: production-модуль]] | живо (done) |
| [[KAC/issue-201\|Сцепка пользователя с аккаунтом: аккаунт по умолчанию неудаляем (#201)]] | в работе (in-progress) |
| [[KAC/issue-208\|issue-208 — ci: три накопителя без не-тестового читателя]] | в работе (test) |
| [[KAC/issue-211-identity-account-decoupling\|Отрыв аккаунта от пользователя — приёмка перед кодом (эпик #211)]] | в работе (test) |
| [[KAC/issue-231\|#231: backend-порт снят с листенера nlb — он живёт на группе целей]] | в работе (test) |
| [[KAC/issue-232\|#232: список групп целей nlb не заполнял targets]] | в работе (test) |
| [[KAC/issue-239\|#239: правки консоли по находкам владельца — волна 2026-08-12]] | в работе (test) |
| [[KAC/issue-240\|issue-240 — перепись веток принимает отставание за расщеплённую работу]] | живо (done) |
| [[KAC/issue-241\|issue-241 — ветки: влитая локальная ветка не снимается и не видна]] | живо (done) |
| [[KAC/issue-242\|#242: docfresh — «не нашёл» неотличимо от «не искал»]] | в работе (test) |
| [[KAC/issue-243\|#243: имя ветки в кавычках судилось как путь в дереве]] | живо (done) |
| [[KAC/issue-244\|issue-244 — vpc: production-полнота модуля сети, волны 0-5]] | живо (done) |
| [[KAC/issue-254\|#254: правило называло enforce_admins false, в обоих репозиториях true]] | живо (done) |
| [[KAC/issue-257\|issue-257 — перепись веток: раздел «работа в стволе не вся» давал ложные находки]] | живо (done) |
| [[KAC/issue-259\|#259: брошенные рабочие копии держали влитые ветки]] | живо (done) |
| [[KAC/issue-282\|#282: триггеры конвейера воркспейса сужены по ветке — правило стало верным]] | в работе (test) |
| [[KAC/issue-285\|#285: версию генератора контракта выбирал PATH, а не дерево]] | в работе (test) |
| [[KAC/issue-287\|#287: перепись читала машинно собираемый файл как расщеплённую работу]] | живо (done) |
| [[KAC/issue-291-quota-v2\|Квоты на число ресурсов: каталог, учёт, отказ и арендаторское чтение (#291)]] | в работе (test) |
| [[KAC/issue-291\|#291: число ресурсов у арендатора не ограничено квотами]] | в работе (in-progress) |
| [[KAC/issue-292\|#292: клетка Ф2 приёмки XC-7 называла шесть обёрток, их три]] | живо (done) |
| [[KAC/issue-293\|#293: у проверки состава приёмок не было ни одной пробы]] | живо (done) |
| [[KAC/issue-295\|[trail] issue-295 — судья переноса не доходил до вердикта]] | в работе (test) |
| [[KAC/issue-296\|[trail] issue-296 — состояние применения выведено в публичный контракт vpc]] | в работе (test) |
| [[KAC/issue-297\|#297: версия shellcheck не пиннилась — вердикт принадлежал образу ранера]] | живо (done) |
| [[KAC/issue-304\|#304: корпус фаззера уезжал в кэш только той ночью, которая ничего не нашла]] | в работе (test) |
| [[KAC/issue-306\|#306: обязательный локальный прогон держался вниманием — цели установки хука не существовало]] | в работе (test) |
| [[KAC/issue-307\|#307: шаг сквозной пробы, захватывающий переменную, не утверждал исход]] | в работе (test) |
| [[KAC/issue-352\|issue-352 — compute: предел числа машин не назначается ни одному проекту]] | в работе (in-progress) |
| [[KAC/issue-364-quota-console\|Витрина квот в консоли: арендатор видит предел, занято и источник (#364)]] | в работе (in-progress) |
| [[KAC/issue-373-list-scope-honesty\|#373: ручка списка называет область, в которой судит]] | в работе (test) |
| [[KAC/issue-375\|#375: ветви контракта, достижимые из создания, выразимы формой]] | в работе (test) |
| [[KAC/issue-405\|#405: общий модуль консоли учится тому, ради чего расходились копии]] | живо (done) |
| [[KAC/issue-411-quota-unity\|Единство квот: что едино, что не будет, и где записаны решения]] | в работе (in-progress) |
| [[KAC/issue-412\|#412: чтение квот арендатором заводится у всех пяти списывающих доменов]] | в работе (test) |
| [[KAC/issue-418\|issue-418 — консоль: окружение проб и 90 копий оснастки сведены к общему модулю]] | живо (done) |
| [[KAC/issue-419\|issue-419 — квоты: линия учёта, величины, носителя и единого источника отказа]] | в работе (test) |
| [[KAC/issue-420\|issue-420 — iam: пользователя ищут по почте, и сужает сервер]] | в работе (test) |
| [[KAC/issue-421\|issue-421 — ui: страница с именем чужого поставщика личности снята]] | в работе (test) |
| [[KAC/issue-425\|issue-425 — ui: пустая заявка на шапку страницы стирала чужую]] | в работе (test) |
| [[KAC/issue-428\|issue-428 — ui: подмена antd брала дублёр динамическим импортом]] | в работе (test) |
| [[KAC/issue-434\|#434: вердикт сквозного прогона был непригоден — три состояния печатались неразличимо]] | в работе (test) |
| [[KAC/issue-436\|issue-436 — iam: отравленная строка очереди прав возвращается в работу]] | в работе (test) |
| [[KAC/issue-440\|issue-440 — iam: запрет участия недоступен из консоли]] | в работе (test) |
| [[KAC/issue-446\|issue-446 — ui: ссылка на ресурс одна, и у неё есть копирование значения]] | в работе (test) |
| [[KAC/issue-447\|ADM-1 S1: административная поверхность пула адресов выставлена на публичный край]] | в работе (test) |
| [[KAC/issue-461\|#461 — порядок суит консоли: что течёт между ними на самом деле]] | в работе (test) |
| [[KAC/issue-467\|issue-467 — nlb: аренда адреса и три пути её возврата]] | в работе (test) |
| [[KAC/issue-469\|issue-469: пробы с git-фикстурами писали в репозиторий прогона]] | живо (done) |
| [[KAC/issue-470\|#470: принадлежность аккаунту уходит из строки пользователя (S1)]] | в работе (in-progress) |
| [[KAC/issue-473\|issue-473 — ui: аккаунт в строке пользователя, список или снятие столбца]] | в работе (test) |
| [[KAC/issue-477\|#477: два набора одного прогона режут один и тот же /24]] | в работе (test) |
| [[KAC/issue-479\|issue-479 — nlb: раздел не загружался, форк контекста темы по идентичности]] | в работе (test) |
| [[KAC/issue-483\|issue-483 — ui: каждое мутирующее действие сообщает свой исход]] | в работе (test) |
| [[KAC/issue-484\|#484: у числа аккаунтов появился потолок, а у вида — носитель «личность»]] | в работе (test) |
| [[KAC/issue-489\|#489: пакет репозитория compute не собирался под своим признаком]] | в работе (test) |
| [[KAC/issue-490\|issue-490: адъюдикация объявленных разрывов не смотрела на ствол]] | в работе (test) |
| [[KAC/issue-494\|#494: набор глаголов объекта материализуется целиком, а не по частям]] | в работе (test) |
| [[KAC/issue-496\|issue-496 — iam: теневая форма расходится с движком на 3215 записях за прогон]] | в работе (in-progress) |
| [[KAC/issue-497\|issue-497: недоступность модели прав отвечала кодом отказа в правах]] | в работе (test) |
| [[KAC/issue-498\|issue-498 — ui: три черновика правят набор без гейта состава]] | в работе (test) |
| [[KAC/issue-503\|#503: сетевая поверхность сборки образа шире его графа импортов]] | в работе (test) |
| [[KAC/issue-505\|#505: фикстура vpc сталкивалась каждый прогон, а утверждение это не ловило]] | в работе (test) |
| [[KAC/issue-510\|issue-510 — iam: проба очереди отбирает свои строки отрицательным списком посевов]] | в работе (test) |
| [[KAC/issue-514\|#514: ствол не требовал ни одной зелёной проверки перед вливанием]] | живо (done) |
| [[KAC/issue-523\|issue-523 — ci: гейт чтения исходников консоли краснеет на синтетике соседа]] | в работе (test) |
| [[KAC/issue-524\|issue-524 — ci: ведомость закрытий пула отстала на три места]] | в работе (test) |
| [[KAC/issue-530\|#530 (R1): гейты и пригодность вердикта — релиз влит]] | в работе (in-progress) |
| [[KAC/issue-537\|issue-537 — git: работа семи веток оказалась в стволе, потерь ноль]] | живо (done) |
| [[KAC/issue-550\|issue-550 — vpc: ветку владения при снятии аренды проверяет проба владельца]] | в работе (test) |
| [[KAC/issue-556\|issue-556 — ui: второе дерево маршрутов vpc снято вместе со своей пробой]] | в работе (test) |
| [[KAC/issue-566\|#566: глагол create мигратора выдавал форму, которой дерево не принимает]] | в работе (test) |
| [[KAC/issue-567\|#567: перепись уникальности миграций видела 263 файла из 268]] | в работе (test) |
| [[KAC/issue-574\|#574: MR #547 красный — четыре корня в пяти джобах]] | в работе (test) |
| [[KAC/issue-580\|#580: контракт access.proto не обслуживался ни одним сервисом — снят]] | в работе (test) |
| [[KAC/issue-581\|#581: сообщения метаданных без операции — и шесть обратного класса]] | в работе (test) |
| [[KAC/issue-582\|#582: имя джобы стало контрактом с защитой ветки — и разошлось]] | в работе (test) |
| [[KAC/issue-584\|#584: замена набора теряет параллельную правку — радиус два поля, а не класс]] | в работе (to-do) |
| [[KAC/issue-600\|#600: три сквозные пробы консоли красны в стволе по дефектам самих проб]] | в работе (test) |
| [[KAC/issue-607\|#607: стенд консоли не нёс каталога внешних адресов]] | в работе (test) |
| [[KAC/issue-608\|#608: формы vpc помечали «Имя» обязательным вопреки контракту — пять мест]] | в работе (test) |
| [[KAC/issue-636\|#636: локатор строки формы попадал в объемлющий блок]] | в работе (test) |
| [[KAC/issue-645\|#645: страница списка iam набиралась до учёта прав]] | в работе (test) |
| [[KAC/issue-650\|#650: локальный прогон судил о рендере другим helm, чем конвейер]] | в работе (test) |
| [[KAC/issue-657\|#657: линия квот — предел, который действительно ограничивает]] | в работе (test) |
| [[KAC/issue-658\|#658: вердикт из трубы под pipefail — найденное объявляется ненайденным]] | в работе (to-do) |
| [[KAC/issue-667\|#667: краснота сквозных проб линии квот — два корня, оба про утечку фикстуры]] | в работе (test) |
| [[KAC/issue-691\|#691: журналы аудита пишутся и не читаются — класс закрыт гейтом по схеме]] | в работе (test) |
| [[KAC/issue-694\|#694: ключ повтора — домен параллелизма защиты сведён с флотом]] | в работе (test) |
| [[KAC/issue-703\|#703: фоновые задачи разведены между репликами]] | в работе (test) |
| [[KAC/issue-709\|#709: ширина пула против потолка соединений базы — считать надо ПАРУ чисел]] | в работе (test) |
| [[KAC/issue-715\|#715: имя ресурса — одна форма по RFC 1123, пустого не бывает, алиасов нет]] | живо (done) |
| [[KAC/issue-720\|#720: единичный отказ недоступности — мёртвое соединение из пула, не сбой стенда]] | в работе (test) |
| [[KAC/issue-727\|#727: приёмка R7-1 — константа на проверку доказана прибором, материализация линейна]] | в работе (in-progress) |
| [[KAC/issue-729\|#729 (R7): ролевая модель — константа на проверку, линейная материализация]] | в работе (in-progress) |
| [[KAC/issue-731\|#731: недоступный Postgres приходил красным вердиктом вместо «не выполнилось»]] | живо (done) |
| [[KAC/issue-732\|Обход цепи областей не платит за размер облака (S2 линии roles-new)]] | в работе (test) |
| [[KAC/issue-734\|#734: вложенность групп решена в пользу базы, federated_subject снят с контракта]] | в работе (in-progress) |
| [[KAC/issue-740\|#740: цепь областей доходит до корня — верхние звенья выводятся из схемы]] | в работе (test) |
| [[KAC/issue-743\|#743: замер предела прочности — чтение, запись, удаление]] | в работе (test) |
| [[KAC/issue-745\|#745: стоимость одной операции против объёма налитой матрицы]] | в работе (test) |
| [[KAC/issue-747\|#747 (R7-3): полный отказ от внешнего движка прав — решение вычисляется в своей базе]] | живо (done) |
| [[KAC/issue-757\|#757: очередь аудита копится, дренажа нет — записано решением с предикатом]] | живо (done) |
| [[KAC/issue-767\|#767: отчёты прибора authzformbench накрыты отпечатком вперёд, граница напечатана]] | живо (done) |
| [[KAC/issue-785\|#785 (R7-4): цепь областей покрывает собственные типы службы прав]] | в работе (test) |
| [[KAC/issue-795\|#795: канал audit_event снят вместе с триггером — будить было некого]] | живо (done) |
| [[KAC/issue-797\|#797: отзыв, записанный у нас, не действовал на пути запроса]] | живо (done) |
| [[KAC/issue-883\|#883: потолок при незанятых ресурсах — посадка базы против срыва хвоста]] | в работе (test) |
| [[KAC/issue-901\|#901: обратные вызовы службы личности — транспорт каждой полосы решает профиль]] | в работе (test) |
| [[KAC/label-grant-revocation-lag-2026-08-04\|Выдача по метке действует сразу, снятие — когда дойдёт очередь (замер 2026-08-04)]] | в работе (in-progress) |
| [[KAC/mechanism-without-callers-2026-08-04\|Средство есть, потребителей нет — фикс, приехавший без своего радиуса (2026-08-04)]] | живо (done) |
| [[KAC/prod-newman-seed-acr-stepup-constraint\|Prod-newman seed: step-up/acr gate blocks non-interactive USER tokens]] | живо (done) |
| [[KAC/queued-behind-a-dead-label-2026-08-04\|Ожидание за несуществующим исполнителем — не отказ, а вид работы (2026-08-04)]] | живо (done) |
| [[KAC/rbac-2026-224-owner-wildcard-content\|RBAC explicit-model 2026 #224 — owner *.* materializes per-object content + verify-gate owner-content check]] | живо (done) |
| [[KAC/rbac-2026-bug2-hide-existence-read-deny\|rbac-2026 BUG-2 — read-deny hide-existence (gateway 403→404)]] | живо (done) |
| [[KAC/rbac-2026-contract-a-fix-iam-content-forward\|RBAC Contract-A fix — forward-materialize owner/creator access on iam-native content (flat FGA no-access-loss)]] | живо (done) |
| [[KAC/rbac-2026-contract-a-flat-bootstrap-fallout\|RBAC Contract-A flat — bootstrap signup owner-binding fallout (ROOT flat-403)]] | живо (done) |
| [[KAC/rbac-2026-contract-b-org-removal\|RBAC Contract-B — full removal of B2B Organization (proto/iam/deploy)]] | живо (done) |
| [[KAC/rbac-2026-edit-leaf-delete-comaterialization\|RBAC — v_delete co-materialized with v_update on leaf objects (edit@project delete-403)]] | живо (done) |
| [[KAC/rbac-2026-review-fixes-pass1-ledger-revoke\|RBAC-2026 review fixes — Pass 1: ledger revoke-correctness (#1/#7/#15/#16)]] | живо (done) |
| [[KAC/rbac-2026-super-admin-cascade-fallout\|Каскад супер-доступа: что он перезарядил задним числом]] | живо (done) |
| [[KAC/rbac-explicit-model-2026-subphase-P11-ui\|RBAC explicit-model 2026 — sub-phase P11 (owner/deletion_protection UX + org-removal + 403 content-access) ui]] | живо (done) |
| [[KAC/rbac-explicit-model-2026-subphase-P6-iam\|RBAC explicit-model 2026 — sub-phase P6 (owner role + auto-binding + deletion_protection) iam]] | живо (done) |
| [[KAC/rbac-explicit-model-2026\|Explicit RBAC model 2026 (epic)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-A-iam\|RBAC rules-model 2026 — sub-phase A (iam)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-C-iam\|RBAC rules-model 2026 — sub-phase C (iam)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-D-consumer-vpc\|RBAC rules-model 2026 — sub-phase D-consumer (kacho-vpc)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-D-iam\|RBAC rules-model 2026 — sub-phase D (iam-core)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-D-nlb-consumer\|RBAC rules-model 2026 — sub-phase D (nlb consumer list-filter)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-E-iam\|RBAC rules-model 2026 — sub-phase E (subjects[] + ExpandAccess + ListByRole)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-F-iam\|RBAC rules-model 2026 — sub-phase F clean-cut (iam + proto)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-F-ui\|RBAC rules-model 2026 — sub-phase F (UI — F-22 rules-editor + thin grant-form)]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-G-iam\|RBAC rules-model 2026 — sub-phase G (Permission Catalog) — proto/iam/gateway/ui]] | живо (done) |
| [[KAC/rbac-rules-model-2026-subphase-H-rule-module-scalar\|RBAC rules-model 2026 — sub-phase H (Rule.module scalar) — proto/iam/gateway/ui]] | живо (done) |
| [[KAC/redesign-2026\|redesign-2026 — 7-сервисный UX-конвергентный редизайн]] | в работе (in-progress) |
| [[KAC/revocation-not-enforced-at-edge-2026-07-28\|Проверка отзыва на краю ведёт в никуда и проглатывает отказ (2026-07-28)]] | живо (done) |
| [[KAC/sec-acr-stepup-refinement\|SEC-acr-stepup-refinement — narrow required_acr_min to 41-set]] | живо (done) |
| [[KAC/sec-hardening-2026-07-05\|sec-hardening-2026-07-05: cross-repo security/architecture/quality audit + fixes]] | живо (done) |
| [[KAC/sec-hardening-r2-2026-07-05-nlb\|sec-hardening-r2-2026-07-05 (kacho-nlb): 2-й аудит — contract-safe medium/low → zero]] | живо (done) |
| [[KAC/sec-nlb-move-crosstenant-authz-relation\|nlb :move cross-tenant deny — FIXTURE bug (NOT a bypass) + design-note]] | живо (done) |
| [[KAC/stor-p-plan-acceptance-reconciled-2026-08-13\|STOR-P: план и приёмка сведены с деревом ветки — 13 недоставленных предметов и 10 сценариев без исполнителя]] | в работе (reference) |
| [[KAC/sub-phase-1.2-iam-operations\|IAM operations visibility (sub-phase 1.2)]] | живо (done) |
| [[KAC/sub-phase-1.3-subject-privileges\|Subject privileges (sub-phase 1.3)]] | живо (done) |
| [[KAC/sub-phase-1.4-tuple-resource-guarantee\|100% tuple↔resource-create guarantee (sub-phase 1.4)]] | живо (done) |
| [[KAC/sub-phase-1.5-assignable-roles\|Assignable roles (sub-phase 1.5)]] | живо (done) |
| [[KAC/sub-phase-T3.1-cross-service-label-revoke\|Cross-service ARM_LABELS revoke on label change (T3.1 / #113)]] | живо (done) |
| [[KAC/sub-phase-T3.2-vpc-residual-label-feed\|vpc residual label-feed: routeTable/address/gateway/NIC (T3.2 / #113-residual)]] | живо (done) |
| [[KAC/sub-phase-T3.3-unify-iam-label-scope-role-ab\|sub-phase T3.3 — unify IAM label-scope (role + access_binding, chunk 2)]] | живо (done) |
| [[KAC/ui-console-fixes-wave-2026-08-15\|Волна правок консоли: путь до машины, границы отказа, форк, тексты, имена (2026-08-15)]] | в работе (test) |
| [[KAC/wave-close-2026-08-02\|Волна закрытия: девять предметов, сверенных с деревом a373c599]] | в работе (reference) |
| [[KAC/wave-gates-and-retire-2026-07-28\|Волна 2026-07-28 — шесть слияний, четыре гейта, один молчаливый откат]] | живо (done) |
| [[KAC/wildcard-relation-sweep-2026-07-28\|Отношение, выполнимое подстановкой — развёртка по каталогу (2026-07-28)]] | живо (done) |

### Уроки — классы дефектов — `lessons/` (43)

| Записка | Состояние |
|---|---|
| [[lessons/a-declared-predicate-can-be-wrong-and-then-it-lies-confidently\|Объявленный предикат может быть негодным — и тогда он лжёт увереннее, чем догадка]] | — |
| [[lessons/a-pointer-cannot-hold-an-unknown-value\|Указатель на структуру не держит неизвестное значение: законная конфигурация отвергается отказом, который не называет поля]] | — |
| [[lessons/a-ratio-of-two-stand-quantities-is-not-a-property-of-the-code\|Отношение двух стендовых величин — не свойство кода, и оно устаревает за сутки]] | — |
| [[lessons/absence-of-finding-versus-absence-of-inspection\|Нет находки — это два разных факта: путь чист или путь не осматривали]] | — |
| [[lessons/acceptance-of-a-request-named-as-its-execution\|Приём запроса, названный его исполнением: шаг утверждает «сделано», проверив «принято»]] | — |
| [[lessons/census-blind-to-the-verb-that-creates\|Перепись покрытия, слепая к глаголу заведения: пропущен не ресурс, а целый вид предмета]] | — |
| [[lessons/checker-keyed-on-a-layout-goes-blind-when-it-moves\|Проверка, ключующаяся на раскладку, слепнет при переезде — и её «ноль находок» остаётся честным]] | — |
| [[lessons/checks-with-form-but-no-substance\|Форма без содержания — проверка, не способная произвести отказ]] | — |
| [[lessons/computed-immutable-field-replaces-on-every-edit\|Вычисляемое неизменяемое поле пересоздаёт ресурс от правки чего угодно]] | — |
| [[lessons/db-refusal-in-open-tx-wedges-the-probe\|Отказ базы внутри открытой транзакции вешает пробу вместо падения]] | — |
| [[lessons/dead-twin-gate-survives-a-merge-and-kills-the-step\|Два гейта об одном предмете пережили слияние, и мёртвый уронил шаг целиком]] | — |
| [[lessons/failure-shape-lives-in-the-connection-not-the-error\|Признака, по которому различают отказ, в самой ошибке нет — он в соединении]] | живо (stable) |
| [[lessons/field-accepted-on-create-and-ignored-on-update\|Поле принято при создании и проигнорировано при изменении: правка видна в плане и не доезжает]] | — |
| [[lessons/guard-whose-concurrency-domain-is-narrower-than-the-fleet\|Защита, чей домен параллелизма уже домена флота]] | живо (stable) |
| [[lessons/idempotency-key-without-the-body-makes-rejection-sticky\|Ключ идемпотентности без тела запроса делает отвергнутое создание липким]] | — |
| [[lessons/identity-column-is-not-immutability\|Столбец, выдающий значение сам, не делает его неизменяемым]] | — |
| [[lessons/inherited-refusal-hides-a-promise-nobody-owns\|Унаследованный отказ прячет обещание, за которое никто не отвечает]] | — |
| [[lessons/invalid-run-arrives-as-a-red-verdict\|Недействительный прогон приходит красным — и его чинят как дефект]] | — |
| [[lessons/is-this-branch-merged-needs-a-tree-level-predicate\|«Смёржена ли ветка» решается слиянием без рабочего дерева — и его вывод не строка]] | живо (stable) |
| [[lessons/known-failing-declaration-outlives-the-fix\|Запись «известное красное» переживает свой фикс и становится ложным утверждением о продукте]] | — |
| [[lessons/load-measurement-instrument-lies-three-ways\|Прибор нагрузки лжёт тремя способами, и все три выглядят как свойство продукта]] | — |
| [[lessons/merging-parallel-work-is-its-own-defect-source\|Сведение параллельных работ — отдельный источник дефектов, которого не видит ни один исполнитель]] | — |
| [[lessons/metric-that-does-not-separate-the-two-states\|Метрика, чьи распределения перекрываются, не различает состояния — ни при каком пороге]] | — |
| [[lessons/one-trick-five-forms-only-a-run-tells-them-apart\|Один приём, пять форм: правило переезжает, а не чинится — различает только прогон]] | — |
| [[lessons/orchestrator-and-its-own-agent-mistake-each-other-for-strangers\|Оркестратор и его собственный исполнитель принимают друг друга за постороннюю сессию]] | — |
| [[lessons/own-command-checked-a-different-project\|Своя команда проверки судила о другом проекте: «ошибок 0» на файле, который не разбирался вовсе]] | живо (stable) |
| [[lessons/predicate-by-name-measures-the-naming-convention\|Предикат верен для СВОЕЙ величины — и применён к соседней]] | — |
| [[lessons/probe-inherits-the-mechanism-own-variables\|Проба наследует переменные своего механизма — и обвиняет исправного производителя]] | — |
| [[lessons/probe-premise-unsatisfiable-in-its-environment\|Предпосылка проверки едет вместе с записью в реестре, а окружение — нет]] | — |
| [[lessons/probe-that-pins-someone-elses-tree-state\|Проба закрепила состояние чужого дерева — его починка прочиталась как поломка]] | — |
| [[lessons/probe-varies-one-axis-while-cost-has-two\|Проба варьирует одну ось, а у стоимости их две — и вторая невидима by construction]] | — |
| [[lessons/production-profile-cannot-bootstrap-from-scratch\|Профиль, который поднимается только поверх однажды поднятого]] | — |
| [[lessons/projection-fed-by-one-producer-of-many\|Проекция, которую наполняет один производитель из многих, отвечает «нет» на всё — и выглядит рабочей]] | — |
| [[lessons/red-gate-on-a-tree-check-the-base-first\|Красное на гейте, читающем дерево: сперва проверь СВЕЖЕСТЬ базы, а не предмет]] | — |
| [[lessons/revocation-that-binds-at-issue-not-at-presentation\|Отзыв, действующий на выдаче, но не на предъявлении]] | — |
| [[lessons/rule-true-for-one-resolver-applied-to-all-addresses\|Правило, верное для одного резолвера, применённое ко всем адресам]] | — |
| [[lessons/second-copy-of-a-tool-in-path-fakes-drift\|Второй экземпляр инструмента в PATH подделывает дрейф порождённого]] | живо (active) |
| [[lessons/sentinel-that-replaces-its-cause-costs-the-next-hour\|Sentinel, подменяющий причину, стоит следующего часа: наружу — фиксированный текст, в журнал — что ответила сеть]] | живо (stable) |
| [[lessons/setup-step-that-checks-its-own-mark-not-its-subject\|Шаг установки, спрашивающий про свою отметку, а не про предмет]] | — |
| [[lessons/swallowed-refusal-stacks-in-layers\|Проглоченный отказ копится слоями: каждая починка вскрывает следующий]] | живо (stable) |
| [[lessons/two-consistency-windows-in-one-case\|Два независимых окна согласованности в одном кейсе — первое заслоняет второе]] | — |
| [[lessons/update-mask-set-knows-one-form-of-the-name\|Набор маски знает одну форму имени — и поле не изменить ни при каком входе]] | — |
| [[lessons/verdict-of-a-tool-belongs-to-its-version\|Вердикт инструмента принадлежит его версии: «локально чисто» не утверждает ничего о конвейере]] | живо (stable) |

### Записки-переходы прежних репозиториев — `legacy/` (6)

| Записка | Состояние |
|---|---|
| [[legacy/repo-kacho-api-gateway\|kacho-api-gateway (сегодня — каталог gateway/ монорепо)]] | история (legacy) |
| [[legacy/repo-kacho-corelib\|kacho-corelib (сегодня — каталог pkg/ монорепо)]] | история (legacy) |
| [[legacy/repo-kacho-deploy\|kacho-deploy (сегодня — каталог deploy/ монорепо)]] | история (legacy) |
| [[legacy/repo-kacho-proto\|kacho-proto (сегодня — каталог proto/ монорепо)]] | история (legacy) |
| [[legacy/repo-kacho-resource-manager\|kacho-resource-manager]] | история (deprecated) |
| [[legacy/repo-kacho-vpc\|kacho-vpc (сегодня — каталог services/vpc/ монорепо)]] | история (legacy) |

### Операционные процедуры — `runbooks/` (1)

| Записка | Состояние |
|---|---|
| [[runbooks/cilium-enable-srv6-addonvalue\|Runbook: включить SRv6 в Cilium через AddonValue (infra-кластер)]] | живо (active) |

### Руководства (эпоха KAC-127) — `docs/` (3)

| Записка | Состояние |
|---|---|
| [[docs/admin-iam-guide\|Admin IAM guide]] | история (legacy) |
| [[docs/dev-iam-integration\|Developer IAM integration]] | история (legacy) |
| [[docs/user-iam-guide\|User IAM guide]] | история (legacy) |

### Точки входа и полотно — корень хранилища (4)

| Файл | Состояние |
|---|---|
| [[CLAUDE\|Obsidian vault — local CLAUDE.md]] | живо (active) |
| [[INDEX\|INDEX — полный перечень записок]] | живо (active) |
| [[README\|Kachō — точка входа в хранилище знаний]] | живо (active) |
| [[architecture\|Архитектура — одно монорепо, семь сервисов, рёбра рантайма]] | живо (active) |

<!-- GENERATED:vault-index END -->

#index
