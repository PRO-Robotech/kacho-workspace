# Sub-phase SEC-G — operators + kube-ovn on mTLS, least-privilege operator SA — Acceptance

> Статус: DRAFT (revision v2 — после acceptance-review v1)
> Дата: 2026-06-11
> Ревьюер: acceptance-reviewer (gate перед кодом, ban #1)
> Эпик/тикет: SEC (`docs/specs/sub-phase-SEC-mtls-iam-authz-epic.md`), KAC-<TBD> (Subtask of SEC-эпик)
> Зависит от: **SEC-D** (vpc/compute mTLS server+client + outbox-FGA), **SEC-F** (cert-manager internal-CA, per-svc Certificate ×2, SA-seed wiring, FGA NetworkPolicy), **SEC-C** (client-cert→SA mapping, ReBAC least-priv SA seed, ACR-модель)
> Затронутые репо: `kacho-vpc-operator` (+ `kacho-deploy`), правка `polyrepo.md` (`kacho-workspace`)

## Обзор

Финальная подфаза security-эпика: перевести **operator→control-plane dial**
(`kacho-vpc-operator/internal/upstream/client.go`) с insecure gRPC на **mTLS с
отдельным client-cert оператора** (раздельные client/server cert — требование эпика
#5), выдать оператору **собственный least-privilege ServiceAccount** в kacho-iam
(read-only синк, никаких мутаций — требование #4, §3.3), согласовать существующий
**webhook-cert оператора** (cert-manager) с internal CA эпика, собрать **весь стенд
целиком** на mTLS и подтвердить, что синк Subnet→kube-ovn и data-path не сломаны. В
завершение зафиксировать в `polyrepo.md` fgaproxy-рёбра (vpc→iam / compute→iam) и
инвариант «vpc⇄compute — не семантический цикл» (§6.6).

**Модель авторизации — ReBAC (ground-truth `kacho-proto/gen/permission_catalog.json`,
§4.1.2/§4.1.3).** Least-priv роль SA — это НЕ список плоских permission-строк, а набор
**relation-tuples** (`viewer`/`editor`) на **scope-объекты** (project / account /
vpc_network / vpc_network_interface / vpc_subnet). Каждый RPC несёт `required_relation`
+ `scope_extractor` + (для user-флоу) `required_acr_min`. **Service→service вызовы под
mTLS-SA освобождены от `required_acr_min`** (§4.1.2): ACR-floor применяется только к
user-token-флоу (у SA нет MFA; его аутентификация — mTLS client-cert). Permission-строка
— производный 4-сегментный `module.resource.resourceName.verb`-литерал из каталога
(`vpc.subnetses.list` и т.п.), не вводится «на глаз» — каноничный набор берётся из
`permission_catalog.json` и подтверждается эмпирически (S2-04/05).

Публичные ресурсные контракты не меняются (требование #8); меняются только транспорт
(insecure→mTLS), identity (anonymous/`system_admin` → персональный SA оператора) и
deploy-обвязка. `enable=false` для всех mTLS-рёбер = текущее insecure-поведение
(требование #1, эпик DoD; rollback per-edge — §6.5).

Трассировка к эпику дана у каждого сценария тегом **[req #N]** / **[§X.Y]** / **[§4.1.N]** / **[§6.N]**.

---

## Стадии

SEC-G — самостоятельный end-to-end deliverable, дробится на 4 стадии, каждая
мёржится отдельным PR в порядке: транспорт (S1) → identity/least-priv ReBAC (S2) →
webhook-CA + full-stack deploy (S3) → polyrepo-фиксация инвариантов (S4).

- **S1** — operator→vpc/iam dial на mTLS с отдельным client-cert оператора (per-edge `enable`).
- **S2** — least-privilege SA оператора (ReBAC viewer-tuples на scope-объекты, SA exempt от ACR) + empirical least-priv validation (over/under-grant).
- **S3** — webhook-cert оператора через internal CA + полный стенд на mTLS (kube-ovn/multus e2e зелёный).
- **S4** — `polyrepo.md`: fgaproxy-рёбра + vpc⇄compute не-цикл-инвариант + operator→{vpc,iam} mTLS-рёбра.

---

## S1 — operator→vpc/iam dial: mTLS с отдельным client-cert оператора

**Контекст (recon):** `internal/upstream/client.go` сейчас дилит plain insecure
(`grpc.WithTransportCredentials(insecure.NewCredentials())` в `dialOptions`),
inject'ит principal через `principalInterceptor` (metadata `x-kacho-principal-{type,id}`);
`Dial`→vpc (`SubnetSvc`/`NetworkSvc`/`NetworkInterfaceSvc`), `DialIAM`→iam
(`AccountSvc`/`ProjectSvc`). SEC-D уже включил на backend'ах (`kacho-vpc`/`kacho-iam`)
mTLS server creds (`RequireAndVerifyClientCert`, client-CA = internal CA). SEC-G даёт
оператору **собственный client-cert** (отдельный от server-cert webhook'а — #5) и
переключает `Dial`/`DialIAM` на TLS client creds через corelib `grpcclient`
(`TLSClient{enable,cert_file,key_file,ca_files,server_name}`, SEC-B). `enable=false` →
текущий insecure (back-compat). Principal-инжект (mTLS-инвариант I2: cluster-internal
listener доверяет principal-metadata ⟺ peer прошёл client-cert verify) сохраняется
поверх mTLS-транспорта. client-cert SAN — каноничный SPIRE-формат
`spiffe://kacho.cloud/ns/<ns>/sa/kacho-vpc-operator` (§4.1.4, существующий формат
umbrella spire-registration; НЕ `spiffe://kacho/<sva-id>`).

### Сценарий S1-01: operator синкает Subnet→kube-ovn по mTLS (happy) [req #5][req #3][§3.2]

**ID:** SEC-G-01

**Given** internal-CA ClusterIssuer и per-pod Certificate из SEC-F выпущены; client-cert
оператора смонтирован в pod (secret `kacho-vpc-operator-client-tls`, SAN =
`spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`)
**And** `kacho-vpc` поднят с mTLS server creds (SEC-D), `enable=true` на ребре `operator→vpc`
**And** существует project-namespace c materialized Network `<net>` + Subnet `<subnet>` (CIDR `192.168.88.0/24`)
**And** оператор-SA имеет viewer-relation tuples на scope-объекты читаемых ресурсов (SEC-C seed, см. S2)

**When** оператор (`internal/syncer`, `Syncer.reconcileOnce`, interval=10s) дилит
`kacho-vpc.kacho-system.svc:9090` через `upstream.Dial(addr, principal)` с
`TLSClient{enable:true, cert_file:<op-client-cert>, key_file:<op-client-key>, ca_files:[<internal-ca>], server_name:"kacho-vpc.kacho-system.svc"}`
и вызывает `SubnetService.List` / `NetworkService.Get`

**Then** mTLS handshake проходит (peer-cert оператора verified из internal CA)
**And** principal-metadata `x-kacho-principal-{type:service_account, id:<operator-sva-id>}` доставлена и принята (инвариант I2)
**And** per-RPC `InternalIAMService.Check` пропускает (viewer-relation на scope-объект присутствует; SA exempt от `required_acr_min` — §4.1.2) → `List`/`Get` возвращают ресурсы (gRPC OK), не `Unavailable`/`PermissionDenied`
**And** оператор материализует `kubeovn.io/Subnet` `<subnet>` (name=id, `spec.vpc=<net>`) + Multus NAD `<project-ns>` в namespace проекта

### Сценарий S1-02: insecure backend при enable=true → handshake fail = Unavailable [req #5][§6.5]

**ID:** SEC-G-02

**Given** ребро `operator→vpc` запущено с `enable=true` (оператор предъявляет client-cert)
**And** `kacho-vpc` сконфигурирован **без** mTLS server creds (insecure listener) — намеренный per-edge mismatch

**When** оператор дилит и вызывает `SubnetService.List`

**Then** TLS handshake fail; вызов завершается gRPC `UNAVAILABLE` (fail-closed, §6.7)
**And** mismatch детектируется e2e per-edge (§6.5); оператор не паникует, retry на следующем `reconcileOnce`

### Сценарий S1-03: enable=false → текущее insecure-поведение (back-compat) [req #1][эпик DoD]

**ID:** SEC-G-03

**Given** ребро `operator→vpc` и `operator→iam` запущены с `enable=false` (dev-профиль)
**And** `kacho-vpc`/`kacho-iam` на insecure listener (как сейчас)

**When** оператор дилит `upstream.Dial`/`DialIAM` (TLSClient.enable=false)

**Then** соединение insecure (`insecure.NewCredentials()`), как до SEC-G
**And** синк Network/Subnet/NIC работает идентично текущему поведению (никакой регрессии в dev)

### Сценарий S1-04: ns-operator→iam dial на mTLS (fan-out через exempt AccountService.List) [req #5][§3.2]

**ID:** SEC-G-04

**Given** оба оператора (`cmd` vpc-operator, `cmd/nsoperator` ns-operator) собираются из одного образа, каждому смонтирован один и тот же operator-client-cert
**And** `kacho-iam` на mTLS server creds; ребро `operator→iam` `enable=true`
**And** оператор-SA имеет viewer-relation на account-scope для проектов, которые синкает (см. S2)

**When** ns-operator (`internal/nssyncer`) дилит `kacho-iam.kacho-system.svc:9090` через `upstream.DialIAM` (TLS client creds) и делает fan-out `AccountService.List → ProjectService.List`

**Then** mTLS handshake проходит; principal-metadata принята
**And** `AccountService.List` = `<exempt>` (permission_catalog: membership scope-filter, никогда `PermissionDenied`) → возвращает аккаунты, на которые SA имеет членство/viewer-relation
**And** `ProjectService.List` (permission `iam.projectses.list`, `required_relation: viewer`, scope `account` из `account_id`) пропускает для аккаунтов с viewer-relation → возвращает проекты (OK)
**And** ns-operator материализует Namespace на каждый project (label'ы `app.kubernetes.io/managed-by`, `project-id`, `account-id`), как и раньше

### Сценарий S1-05: webhook-резолв NIC fixed-IP по mTLS (data-path сохранён) [req #5]

**ID:** SEC-G-05

**Given** pod c аннотацией `{subnetID}.{projectID}.kacho.io/nic: {nicID}`; ребро `operator→vpc` `enable=true`
**And** существуют Address (kacho-vpc IPAM) + NetworkInterface `<nic>` с `v4_address_ids=[<addr>]`
**And** оператор-SA имеет viewer-relation на scope `vpc_network_interface` для `<nic>` (см. S2)

**When** pod-mutating-webhook (`internal/webhook/v1`) дилит `kacho-vpc` по mTLS и резолвит `NetworkInterfaceService.Get(<nic>)` (permission `vpc.network_interfaces.get`, scope `vpc_network_interface`) → `AddressService.Get(<addr>)` для fixed-IP

**Then** mTLS-вызовы проходят (viewer-relation на scope-объект присутствует); webhook ставит `k8s.v1.cni.cncf.io/networks=<subnet-id>`, mac, и `<provider>.kubernetes.io/ip_address=<kacho-allocated-v4>`
**And** guard'ы сохраняются: `projectID`(из ключа) == `pod.Namespace`; NIC реально в этом project+subnet, иначе admission denied (как сейчас)

**DoD S1:**
- `internal/upstream/client.go`: `dialOptions` принимает `TLSClient` config (corelib `grpcclient`, SEC-B); `enable=false` → insecure (текущая ветка), `enable=true` → TLS client creds (op-client-cert + internal-CA + server_name); principal-инжект сохранён.
- per-edge `enable` флаги: `operator→vpc`, `operator→iam` (config-структуры оператора, env `KACHO_VPCOPERATOR_*`).
- Operator-client-cert — **отдельный** от webhook-server-cert (#5): свои Certificate + secret; SAN = `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` (§4.1.4).
- Integration-тест (operator, bufconn/testcontainers): mTLS handshake OK с валидным client-cert; handshake fail → `Unavailable` (S1-02); `enable=false` → insecure path (S1-03).
- Newman/e2e (в сервисных репо + operator-синк-харнес через стенд SEC-F с mTLS-профилем; §4.1.5): синк Subnet→kube-ovn проходит под mTLS (S1-01); ns-operator namespace-fan-out проходит (S1-04).
- vault: `edges/vpc-operator-to-kubeovn.md` (Configuration/AuthZ → mTLS + operator-SA), новая `edges/vpc-operator-to-vpc-mtls.md`.

---

## S2 — least-privilege ServiceAccount оператора (ReBAC viewer-tuples)

**Контекст (§3.3, §4.1.2, §4.1.3 — ground-truth):** каждый внутренний компонент =
ServiceAccount в kacho-iam (тип `service_account`, `sva…`). **Модель — ReBAC, не
flat-capability.** Least-priv роль оператора = набор **viewer-relation tuples** на
**scope-объекты** тех ресурсов, которые он читает, а НЕ декларация плоских permission-строк.

Каноничный набор RPC оператора и их authz-метаданные (из
`kacho-proto/gen/permission_catalog.json`, validated эмпирически — не выдуманы):

| RPC | permission-строка | required_relation | scope (object_type ← request field) | required_acr_min |
|---|---|---|---|---|
| `vpc.SubnetService/List` | `vpc.subnetses.list` | `viewer` | `project` ← `project_id` | 2 (SA exempt) |
| `vpc.NetworkService/Get` | `vpc.networks.get` | `viewer` | `vpc_network` ← `network_id` | 2 (SA exempt) |
| `vpc.NetworkInterfaceService/Get` | `vpc.network_interfaces.get` | `viewer` | `vpc_network_interface` ← `network_interface_id` | 2 (SA exempt) |
| `iam.ProjectService/List` | `iam.projectses.list` | `viewer` | `account` ← `account_id` | 2 (SA exempt) |
| `iam.AccountService/List` | `<exempt>` | — (membership scope-filter) | — | — |

**Ключевые факты модели (закрывают блокер acceptance-review v1):**
1. Permission-строки именно `vpc.subnetses.list` / `iam.projectses.list` /
   `vpc.network_interfaces.get` (4-сегментные `module.resource.resourceName.verb`, §4.1.3) —
   НЕ `vpc.subnets.list` / `iam.projects.list` / `vpc.networkInterfaces.get`.
2. Каждый non-exempt RPC требует **viewer-relation tuple** оператора-SA на свой
   scope-объект (project / account / vpc_network / vpc_network_interface) — это и есть
   least-priv «роль» (ReBAC-tuples в seed SEC-C), а не список permissions.
3. `AccountService.List` — `<exempt>` (membership scope-filter, никогда
   `PermissionDenied`): fan-out строится на членстве SA, не на permission. Поэтому
   проблема Open Question v1 «нужна ли 5-я permission `iam.accounts.list`» — снимается:
   permission не нужна, нужен membership/viewer-relation на читаемые аккаунты.
4. **SA освобождён от `required_acr_min`** (§4.1.2): ACR-floor=2 — для user-token-флоу
   (MFA). У SA нет ACR; его аутентификация — mTLS client-cert. service→service Check
   проходит при наличии relation, не требуя acr_min.

client-cert SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` → IAM
сопоставляет с ServiceAccount при service→service (SEC-C client-cert→SA mapping; SAN —
непрозрачная identity-строка, §6.3, §4.1.4). Эмпирическая проверка least-priv (I6):
прогон синка в production-mode под узким SA; любой легитимный шаг с `PermissionDenied`
→ недостающий viewer-tuple; over-grant ловится diff'ом «relation-set SA ⊇ множество
Check-вызовов из e2e».

### Сценарий S2-01: оператор под своим SA синкает (read-only ReBAC) → OK [req #4][§3.3][§4.1.2]

**ID:** SEC-G-06

**Given** kacho-iam SEC-C seed выдал оператору-SA `<operator-sva-id>` **viewer-relation tuples** на scope-объекты синкаемых ресурсов: `account:<acct>#viewer`, `project:<proj>#viewer`, `vpc_network:<net>#viewer`, `vpc_network_interface:<nic>#viewer` (через role-binding или прямые tuples — детали в SEC-C)
**And** оператор дилит по mTLS, principal = `service_account:<operator-sva-id>`, production-mode (anonymous fail-closed)

**When** оператор выполняет полный reconcile: `iam AccountService.List` (exempt), `iam ProjectService.List`, `vpc SubnetService.List`, `vpc NetworkService.Get`, `vpc NetworkInterfaceService.Get`

**Then** все Check проходят: exempt-RPC возвращает membership-scoped результат; non-exempt-RPC находят viewer-relation на scope-объект; SA exempt от `required_acr_min` (§4.1.2) → `allowed=true`
**And** синк успешен (Subnet→kube-ovn + NAD); ни один легитимный шаг не получает `PermissionDenied` (least-priv достаточен)

### Сценарий S2-02: оператор пытается мутировать VPC → PermissionDenied (нет editor-relation) [req #4][§3.3]

**ID:** SEC-G-07

**Given** оператор-SA имеет только **viewer**-relation tuples (нет `editor`/`owner` ни на одном scope-объекте; мутирующие RPC `vpc.SubnetService/Delete` etc. требуют `required_relation: editor`)
**And** оператор дилит по mTLS, production-mode

**When** от имени оператора вызывается мутирующий RPC, напр. `vpc SubnetService.Delete(<subnet>)` (`required_relation: editor`, scope `vpc_subnet`) или `NetworkService.Create`

**Then** kacho-vpc per-RPC authz-gate (`InternalIAMService.Check`) не находит editor-relation у SA на scope-объект → `allowed=false` → gRPC `PERMISSION_DENIED "permission denied"`
**And** ресурс не изменён (Subnet остаётся; повторный `Get` → OK)

### Сценарий S2-03: оператор читает чужой домен вне relation-set → PermissionDenied [req #4][§3.3]

**ID:** SEC-G-08

**Given** оператор-SA имеет viewer-tuples только на VPC-синк scope-объекты (нет relation на compute-объекты, нет на iam User/ServiceAccount-объекты)
**And** production-mode

**When** от имени оператора вызывается non-exempt RPC вне relation-set, напр. `compute InstanceService.List` (`required_relation: viewer`, scope `project`) для проекта без relation, или `iam UserService.List`

> Примечание: `iam UserService.List`/`ServiceAccountService.List` сами `<exempt>`
> (membership scope-filter) → вернут **пустой** результат, не `PermissionDenied`
> (отсутствие членства = пустая выдача, не отказ). Сценарий-отказ строим на
> non-exempt cross-domain RPC (`compute InstanceService.List` для проекта без relation).

**Then** `PERMISSION_DENIED` (нет viewer-relation на compute scope-объект)
**And** подтверждает least-priv: оператор не может «прощупывать» соседний домен с записью; exempt-list соседнего домена даёт пустоту, не утечку

### Сценарий S2-04: эмпирическая least-priv валидация — under-grant вскрывается [req #4][§3.3 I6][§4.1.2]

**ID:** SEC-G-09

**Given** заведомо **урезанный** relation-set оператора (например удалён `vpc_network:<net>#viewer`, нужный для `NetworkService.Get`)
**And** production-mode, оператор синкает

**When** reconcile доходит до `NetworkService.Get(<net>)` (требует viewer на `vpc_network:<net>`)

**Then** легитимный шаг получает `PERMISSION_DENIED` → сигнал «недостающий viewer-tuple» (under-grant detector)
**And** тест документирует: точный relation-set роли = множество (relation, scope-object) пар из всех Check-вызовов полного e2e синка (не больше, не меньше)

### Сценарий S2-05: эмпирическая least-priv валидация — over-grant ловится diff'ом [req #4][§3.3 I6]

**ID:** SEC-G-10

**Given** полный e2e-прогон синка в production-mode под SA оператора; собран список фактических `InternalIAMService.Check(relation, scope-object)` от оператора
**And** декларированный relation-set оператора (SEC-C seed) известен

**When** сравнивается множество (relation, scope-object) ролёвки SA с множеством, реально запрошенным синком

**Then** diff пуст: «relation-set SA ⊇ Check-set» И «relation-set SA ⊆ Check-set» (никакого лишнего relation/scope в seed)
**And** любой relation в seed, не вызванный ни одним легитимным шагом, — over-grant → урезается

### Сценарий S2-06: неизвестный client-cert SAN → отказ identity-mapping [req #4][§3.3][§6.3][§4.1.4]

**ID:** SEC-G-11

**Given** оператор предъявляет mTLS client-cert с SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-unknown` (нет такого ServiceAccount в kacho-iam)
**And** production-mode

**When** оператор вызывает любой RPC kacho-vpc (mTLS handshake проходит — cert подписан internal CA)

**Then** kacho-iam (SEC-C client-cert→SA mapping) не сопоставляет SAN-identity с известным SA → authz решение DENY → `PERMISSION_DENIED`
**And** cert-identity (модуль) и principal логируются для аудита (инвариант I2); легитимный peer прошёл verify, но identity неизвестна

### Сценарий S2-07: известный SAN, но нет viewer-relation на конкретный scope → PermissionDenied [req #4][§3.3][§4.1.2]

**ID:** SEC-G-19

**Given** оператор предъявляет **валидный, известный** client-cert SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` (mapping → существующий SA)
**And** SA НЕ имеет viewer-relation на конкретный `vpc_network:<other-net>` (напр. проект, в который SA не добавлен)
**And** production-mode

**When** оператор вызывает `vpc NetworkService.Get(<other-net>)` (`required_relation: viewer`, scope `vpc_network` ← `network_id`)

**Then** identity сопоставлена с SA (SAN известна), но ReBAC-Check не находит viewer-relation SA→`vpc_network:<other-net>` → `allowed=false` → `PERMISSION_DENIED`
**And** это **отдельная** от unknown-SAN (S2-06) ветка: identity валидна, но scope-relation отсутствует — подтверждает per-object ReBAC-энфорс, а не flat-capability

**DoD S2:**
- kacho-iam SEC-C seed: детерминированный `<operator-sva-id>` + **viewer-relation tuples** на scope-объекты синка (`account`, `project`, `vpc_network`, `vpc_network_interface`) — НЕ flat permission-list. `AccountService.List` покрывается членством (exempt), не permission. Точный relation-set подтверждается S2-04/05 эмпирически до APPROVED реализации; permission-литералы валидированы из `permission_catalog.json` (`vpc.subnetses.list`, `vpc.networks.get`, `vpc.network_interfaces.get`, `iam.projectses.list`).
- SA освобождён от `required_acr_min` для service→service (§4.1.2) — подтвердить в seed/handler-логике SEC-C, что mTLS-SA-флоу не требует ACR-floor.
- client-cert→SA mapping (SEC-C) принимает SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` (§4.1.4).
- Integration-тест (iam): seed-tuples содержат ровно ожидаемый relation-set; unknown SAN → DENY (S2-06); known SAN без relation на scope → DENY (S2-07).
- Newman/e2e (в сервисных репо, production-mode mTLS-профиль; §4.1.5): read-only синк OK (S2-01); мутация без editor → PERMISSION_DENIED (S2-02); cross-domain non-exempt RPC → PERMISSION_DENIED (S2-03).
- least-priv audit-тест: over-grant diff пуст (S2-05), under-grant вскрывается (S2-04) — e2e-прогон + сравнение Check-set (relation, scope-object) с seed (I6).
- vault: `rpc/iam-service-account-service.md` / `resources/iam-serviceaccount.md` (operator SA seed — ReBAC viewer-tuples), `edges/vpc-operator-to-vpc-mtls.md` (least-priv relation-set + ACR-exempt).

---

## S3 — webhook-cert через internal CA + полный стенд на mTLS

**Контекст (recon):** webhook оператора уже на cert-manager, но через **отдельный
`selfsigned-issuer`** (`config/certmanager/issuer.yaml`, `kind: Issuer` namespace=system,
secret `webhook-server-cert`, SAN = `SERVICE_NAME.SERVICE_NAMESPACE.svc`). SEC-G
согласует это с internal CA эпика: webhook-server-cert выпускается через единый
trust-root. Per §4.1.6: в umbrella уже есть `kacho-selfsigned` ClusterIssuer
(`clusters/e2c825/cert.yaml`) — **переиспользовать его** как internal-CA root (не
плодить второй issuer); локальный `selfsigned-issuer` оператора заменяется на ссылку
на тот же internal-CA `issuerRef`. Это **отдельный** cert от operator-client-cert
(S1) — webhook это server-сторона admission (kube-apiserver → webhook), а dial к vpc —
client-сторона (#5: раздельные client/server cert). Затем — сборка **всего стенда** в
mTLS-профиле: сервисы (api-gateway/iam/vpc/compute/nlb) + vpc-operator + ns-operator +
kube-ovn + multus, все service→service по mTLS; подтверждение, что kube-ovn/multus
data-path (secondary CNI) не сломан.

> NLB-сервис канонически `kacho-nlb` (§4.1.6; spire-registration упоминает legacy
> `kacho-loadbalancer` — выровнять при правке SPIFFE-entries, но это в SEC-F scope).

### Сценарий S3-01: webhook-cert выпущен internal-CA, kube-apiserver доверяет [req #2][req #5][§3.2][§4.1.6]

**ID:** SEC-G-12

**Given** internal-CA root (переиспользован `kacho-selfsigned` ClusterIssuer, §4.1.6) задеплоен; Certificate webhook оператора переключён с локального `selfsigned-issuer` на internal-CA `issuerRef`
**And** `MutatingWebhookConfiguration.caBundle` указывает на internal-CA (cert-manager `inject-ca-from`)

**When** создаётся pod с NIC-аннотацией в project-namespace (scope webhook'а)

**Then** kube-apiserver устанавливает TLS к webhook (server-cert из internal CA, доверяет caBundle)
**And** admission-mutation отрабатывает (NIC резолвится, аннотации проставлены); `failurePolicy=Ignore` сохранён
**And** webhook-server-cert ≠ operator-client-cert (раздельные secret'ы/Certificate — #5)

### Сценарий S3-02: полный стенд на mTLS поднимается, e2e зелёный [req #5][эпик DoD]

**ID:** SEC-G-13

**Given** стенд поднят с mTLS-профилем: все per-edge `enable=true`
**And** деплоятся api-gateway, iam, vpc, compute, `kacho-nlb`, pg-*, openfga/kratos/hydra, multus, kube-ovn, vpc-operator, ns-operator; каждый под — server-cert + client-cert (раздельные, internal CA); kube-labels `app.kubernetes.io/name|component` (§4.1.6)

**When** прогоняется e2e: newman-регрессия (в сервисных репо, через api-gateway, external TLS + JWT) + deploy bash-смоук `make e2e-test` (`e2e/0.1/*.sh`, §4.1.5) + operator-синк-сценарий (project→Network→Subnet→kube-ovn Subnet+NAD→test-pod NIC)

**Then** все service→service коммуникации по mTLS (раздельные client/server cert)
**And** newman-регрессия зелёная (публичные контракты не изменены — #8); JWT-флоу не тронут (#7); bash-смоук `make e2e-test` зелёный
**And** test-pod получает secondary NIC из Kachō-subnet (data-path подтверждён, как 2026-06-09 recon)

### Сценарий S3-03: kube-ovn/multus интеграция не сломана [req #5][эпик DoD]

**ID:** SEC-G-14

**Given** стенд в mTLS-профиле; kube-ovn (secondary CNI, NON_PRIMARY) + multus задеплоены
**And** project A и project B (разные аккаунты) с изолированными subnet'ами (напр. `10.10.0.0/24` / `10.20.0.0/24`)

**When** оператор синкает оба проекта по mTLS; поды vm-a/vm-b создаются с NIC из своих subnet'ов

**Then** kube-ovn материализует изолированные Vpc/Subnet; vm-a получает `net1` из subnet A, vm-b — из subnet B (изоляция сохранена)
**And** kube-ovn/multus сами по себе **не требуют** mTLS к kacho-API (downstream — k8s API, не gRPC к control-plane); mTLS затрагивает только operator→{vpc,iam}, не operator→kube-ovn

> [!note] Граница mTLS-скоупа
> mTLS вводится на gRPC service→service рёбрах. operator→kube-ovn / operator→multus —
> это k8s-API (downstream materialization), вне gRPC-mTLS-периметра control-plane.
> SEC-G требует, чтобы этот data-path **не регрессировал** при включении mTLS на
> upstream-рёбрах оператора, а не чтобы kube-ovn говорил mTLS к kacho-API.

### Сценарий S3-04: deletion-семантика под mTLS не регрессирует [req #5]

**ID:** SEC-G-15

**Given** стенд в mTLS-профиле; Subnet с allocated IP (под с NIC) и отдельный clean Subnet
**And** project B с подами

**When** (a) Subnet удалён в kacho-vpc; (b) project B удалён в iam (ns-operator прунит namespace)

**Then** (a) vpc-operator (read по mTLS) обнаруживает исчезновение Subnet → удаляет kube-ovn Subnet; kube-ovn finalizer держит Terminating до удаления пода (корректная safety, не баг)
**And** (b) ns-operator прунит namespace → vpc-operator (project больше не итерируется) сносит cluster-scoped Vpc/Subnet по label
**And** fail-closed cleanup сохранён: если `iam ProjectService.List`/`AccountService.List` упал (`Unavailable` под mTLS-mismatch) — ns-operator НЕ прунит (не теряет namespace)

### Сценарий S3-05: rollback на insecure-профиль (per-edge) [req #1][§6.5]

**ID:** SEC-G-16

**Given** стенд в mTLS-профиле; включён `enable=true` на всех рёбрах
**And** оператор-рёбра `operator→vpc` / `operator→iam` переключают обратно на `enable=false`, backend'ы — на insecure listener

**When** оператор синкает

**Then** соединение insecure (как до эпика); синк работает; rollback не требует пересборки образа (config-флаг)
**And** подтверждает opt-in-инвариант эпика: mTLS — расширение, не hard-зависимость

**DoD S3:**
- `kacho-vpc-operator/config/certmanager/`: webhook Certificate переключён на internal-CA `issuerRef` (переиспользован `kacho-selfsigned` ClusterIssuer, §4.1.6; отдельно от operator-client-cert); локальный `selfsigned-issuer` заменён ссылкой на internal-CA в mTLS-профиле (dev-профиль может сохранять локальный self-signed, если SEC-F не активен).
- `kacho-deploy`: argo-app `kacho-vpc-operator` + umbrella helm — mTLS-values для operator (client-cert mount, per-edge `enable`); полный стенд-профиль поднимает сервисы + операторы + kube-ovn + multus; kube-labels `app.kubernetes.io/*`, NLB как `kacho-nlb` (§4.1.6).
- **Тест-харнес (§4.1.5):** newman-регрессия зелёная в сервисных репо (`kacho-<svc>/tests/newman`); `make e2e-test` в deploy (bash-смоук `e2e/0.1/*.sh`) зелёный в mTLS-профиле (S3-02); helm-mTLS-конфиг проверяется **новой** helm-assertion-инфрой (yq/helm-unittest — вводится в этой подфазе, не «по прецеденту»). kube-ovn/multus data-path (single + multi-project) подтверждён (S3-03); deletion-семантика не регрессирует (S3-04); insecure-rollback работает (S3-05).
- vault: `edges/vpc-operator-to-kubeovn.md` (mTLS-граница, webhook internal-CA), `edges/vpc-operator-to-vpc-mtls.md` (новая, full).

---

## S4 — polyrepo.md: fgaproxy-рёбра + vpc⇄compute не-цикл-инвариант

**Контекст (§6.6, §4.1.1):** design-review подтвердил ацикличность: iam не импортирует
vpc/compute; fgaproxy-рёбра vpc→iam / compute→iam — усиление существующего направления
`* → kacho-iam`; vpc⇄compute — **не** семантический цикл (N2). Механизм fgaproxy
(§4.1.1): `RegisterResource`/`UnregisterResource` в proto несут опцию
`permission = "<exempt>"` (как все 7 текущих Internal IAM RPC — подтверждено в
`permission_catalog.json`: `InternalIAMService/Check`, `/WriteCreatorTuple` и др. все
exempt). Least-priv энфорсится **в IAM-handler через ReBAC**: mTLS client-cert → SA
(SEC-B), затем проверка, что SA имеет relation `fga_writer` на системном объекте
`iam_fgaproxy:system` (tuple выдаётся модульным SA в seed). Permission-строка
`iam.fgaproxy.write` НЕ вводится. Эпик требует зафиксировать рёбра + не-цикл-инвариант
в `polyrepo.md` (закрывается здесь, в SEC-G, как финал). Чисто docs-правка (markdown), без кода.

### Сценарий S4-01: fgaproxy-рёбра зафиксированы в polyrepo.md (exempt+ReBAC механизм) [req #6][§6.6][§4.1.1]

**ID:** SEC-G-17

**Given** `.claude/rules/polyrepo.md` §«Runtime cross-domain edges» содержит `* → kacho-iam` (ProjectService.Get + InternalIAMService.Check)

**When** добавляется явная фиксация fgaproxy-рёбер: `kacho-vpc → kacho-iam` и `kacho-compute → kacho-iam` через `InternalIAMService.RegisterResource`/`UnregisterResource` (Internal-only, owner-tuple write/delete, idempotent — SEC-A/C/D), с пометкой: проверяются опцией `permission="<exempt>"` + ReBAC-relation `fga_writer` на `iam_fgaproxy:system` (§4.1.1), НЕ permission-строкой `iam.fgaproxy.write`

**Then** `polyrepo.md` явно перечисляет fgaproxy-рёбра как runtime-edges (усиление направления `* → iam`, не новое направление) + механизм exempt+ReBAC
**And** отмечено: модули не ходят в FGA напрямую (vpc/compute openfga-client удалён — SEC-D), только через IAM-proxy (#6)

### Сценарий S4-02: vpc⇄compute не-цикл-инвариант зафиксирован [§6.6 N2]

**ID:** SEC-G-18

**Given** `polyrepo.md` перечисляет `kacho-vpc → kacho-compute` (zone_id validate) и `kacho-compute → kacho-vpc` (NIC-spec validate + IPAM)

**When** добавляется инвариант: vpc⇄compute — **не** семантический цикл (разные ресурсные контексты; vpc→compute запрос не порождает обратный синхронный compute→vpc вызов в той же цепочке)

**Then** `polyrepo.md` явно документирует не-цикл-инвариант + правило «новое cross-domain ребро не должно замыкать синхронную цепочку A→B→A»
**And** операторские рёбра (operator→vpc, operator→iam) добавлены в карту runtime-edges (operator — вне build-графа, sync-poll consumer, mTLS + read-only SA)

### Сценарий S4-03: операторские mTLS-рёбра отражены в edge-карте [req #5]

**ID:** SEC-G-20

**Given** vault edges и `polyrepo.md` runtime-edge карта

**When** SEC-G завершён

**Then** `polyrepo.md` / vault содержат: `kacho-vpc-operator → kacho-vpc` (mTLS, отдельный client-cert SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`, read-only ReBAC viewer-SA) и `kacho-vpc-operator → kacho-iam` (mTLS, fan-out list через exempt AccountService.List + viewer-scoped ProjectService.List)
**And** отмечено, что оператор вне build-графа control-plane (sibling, не импортируется по build)

**DoD S4:**
- `.claude/rules/polyrepo.md` §«Runtime cross-domain edges»: добавлены fgaproxy-рёбра (vpc→iam / compute→iam via InternalIAMService.RegisterResource/Unregister, механизм exempt+ReBAC `fga_writer`@`iam_fgaproxy:system` — §4.1.1) + vpc⇄compute не-цикл-инвариант + operator→{vpc,iam} mTLS-рёбра.
- docs-правка раскатана во все синканные копии `polyrepo.md` (`./sync-tooling.sh`, источник истины — workspace).
- vault: `edges/vpc-operator-to-vpc-mtls.md` финализирован; `edges/vpc-operator-to-kubeovn.md` обновлён.
- Чисто markdown — без кода (S4 не содержит integration/newman, проверяется ревью текста polyrepo.md).

---

## Сводный список тестов (TDD-red до кода)

> Каждый тест пишется **красным** (RED) до реализации, прогоняется, подтверждается
> падение по нужной причине, затем код → GREEN (ban #12). Имена тестов трассируются к
> ID сценария (`SEC-G-NN`). Newman-регрессия — в сервисных репо (`kacho-<svc>/tests/newman`);
> deploy `make e2e-test` — bash-смоук (`e2e/0.1/*.sh`); helm-mTLS — новая helm-assertion-инфра (§4.1.5).

### Integration (Go, testcontainers / bufconn)

| Тест (файл / суть) | Покрывает |
|---|---|
| `internal/upstream/client_mtls_integration_test.go` — handshake OK с валидным op-client-cert (internal CA), SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` | SEC-G-01 |
| `…` — handshake fail при backend-insecure/cert-mismatch → `codes.Unavailable` | SEC-G-02 |
| `…` — `TLSClient.enable=false` → insecure creds path (без TLS) | SEC-G-03, SEC-G-16 |
| `…` — principal-metadata инжектится поверх mTLS (I2) | SEC-G-01, SEC-G-04 |
| kacho-iam `…serviceaccount_seed_integration_test.go` — seed operator-SA имеет ровно ожидаемый relation-set (viewer-tuples на account/project/vpc_network/vpc_network_interface), без editor; SA exempt от acr_min | SEC-G-06, S2 DoD |
| kacho-iam `…clientcert_sa_mapping_integration_test.go` — unknown SAN → DENY; known SAN → resolved SA | SEC-G-11 |
| kacho-iam `…operator_rebac_scope_test.go` — known SAN без viewer-relation на scope-объект → DENY | SEC-G-19 |
| kacho-iam least-priv audit `…operator_role_check_set_test.go` — diff(relation-set, Check-set) пуст (over/under) | SEC-G-09, SEC-G-10 |

### Newman / e2e (сервисные репо + operator-синк-харнес, mTLS-профиль; deploy bash-смоук)

| Кейс (cases/*.py → gen.py, в `kacho-<svc>/tests/newman`) | Покрывает |
|---|---|
| `NEG-` operator мутация без editor-relation → `PERMISSION_DENIED` | SEC-G-07 |
| `NEG-` operator cross-domain non-exempt RPC (compute) → `PERMISSION_DENIED` | SEC-G-08 |
| `NEG-` operator non-exempt RPC, known SAN без scope-relation → `PERMISSION_DENIED` | SEC-G-19 |
| `CONF-` read-only синк под operator-SA (ReBAC viewer) в production-mode → OK (полный reconcile) | SEC-G-01, SEC-G-06 |
| `CONF-` ns-operator fan-out (exempt AccountService.List + viewer ProjectService.List) по mTLS → namespace materialized | SEC-G-04 |
| `CONF-` webhook NIC fixed-IP резолв по mTLS → pod-аннотации проставлены | SEC-G-05 |
| `CONF-` webhook-cert internal-CA → admission-mutation отрабатывает | SEC-G-12 |
| `CONF-` полный стенд mTLS-профиль → newman зелёные + `make e2e-test` bash-смоук + test-pod secondary NIC | SEC-G-13 |
| `CONF-` kube-ovn/multus 2-project изоляция под mTLS → net1 из своих subnet'ов | SEC-G-14 |
| `CONF-` deletion-семантика (clean subnet + project-delete) под mTLS не регрессирует + fail-closed cleanup | SEC-G-15 |
| `CONF-` insecure-rollback (per-edge enable=false) → синк работает | SEC-G-16 |

### Helm-assertion (новая инфра, §4.1.6) + Docs-ревью (S4 — без авто-тестов)

| Проверка | Покрывает |
|---|---|
| helm-unittest/yq: webhook Certificate `issuerRef` = internal-CA (`kacho-selfsigned`); operator-client-cert secret отдельный от webhook-server-cert; kube-labels `app.kubernetes.io/*`; NLB=`kacho-nlb` | SEC-G-12, S3 DoD |
| `polyrepo.md` содержит fgaproxy-рёбра (vpc→iam / compute→iam via RegisterResource/Unregister, exempt+ReBAC) | SEC-G-17 |
| `polyrepo.md` содержит vpc⇄compute не-цикл-инвариант + правило A→B→A | SEC-G-18 |
| `polyrepo.md` / vault содержат operator→{vpc,iam} mTLS-рёбра | SEC-G-20 |

---

## Definition of Done (подфаза SEC-G)

- [ ] **S1**: operator→vpc и operator→iam dial на mTLS с отдельным operator-client-cert (раздельно от webhook-server-cert, #5; SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`, §4.1.4); per-edge `enable`; `enable=false` = insecure back-compat (#1).
- [ ] **S2**: operator-SA с least-priv **ReBAC viewer-relation tuples** на scope-объекты синка (account/project/vpc_network/vpc_network_interface; permission-литералы `vpc.subnetses.list`/`vpc.networks.get`/`vpc.network_interfaces.get`/`iam.projectses.list` validated из `permission_catalog.json`; `AccountService.List` покрыт членством/exempt) seed'ом в kacho-iam (SEC-C); никаких editor/мутаций (#4); SA exempt от `required_acr_min` (§4.1.2); over/under-grant пройдены эмпирически (I6); unknown SAN → DENY; known SAN без scope-relation → DENY.
- [ ] **S3**: webhook-cert оператора через internal-CA (переиспользован `kacho-selfsigned`, единый trust-root, #2, §4.1.6); полный стенд (сервисы + vpc-operator + ns-operator + kube-ovn + multus) на mTLS; newman зелёные в сервисных репо + `make e2e-test` bash-смоук зелёный + helm-assertion (§4.1.5); kube-ovn/multus data-path и deletion-семантика не сломаны; per-edge insecure-rollback работает; kube-labels `app.kubernetes.io/*`, NLB=`kacho-nlb`.
- [ ] **S4**: `polyrepo.md` фиксирует fgaproxy-рёбра (#6, exempt+ReBAC `fga_writer`@`iam_fgaproxy:system`, §4.1.1) + vpc⇄compute не-цикл-инвариант (§6.6) + operator→{vpc,iam} mTLS-рёбра; раскатано sync-tooling'ом.
- [ ] Публичные ресурсные контракты не изменены (#8); JWT-флоу не тронут (#7).
- [ ] Каждая стадия — отдельный PR + ветка `KAC-<N>` в затронутых репо; integration+newman в том же PR (RED→GREEN, ban #12).
- [ ] vault обновлён (`edges/vpc-operator-to-kubeovn.md`, новая `edges/vpc-operator-to-vpc-mtls.md`, `resources/iam-serviceaccount.md`/`rpc/iam-service-account-service.md`); KAC-trail.
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` (operator) + newman зелёные в mTLS-профиле.

## Открытые вопросы к ревью (для acceptance-reviewer)

1. **РАЗРЕШЁН (был блокер v1).** Модель — ReBAC, не flat-permissions. `AccountService.List`
   = `<exempt>` (membership scope-filter, validated из `permission_catalog.json`) → 5-я
   permission `iam.accounts.list` НЕ нужна; fan-out покрывается членством SA. `ProjectService.List`
   = `iam.projectses.list`, `required_relation: viewer`, scope `account`. Permission-литералы
   и relation/scope/ACR-метаданные взяты эмпирически из каталога (см. таблицу S2); точный
   relation-set seed'а подтверждается S2-04/05.
2. **Seed operator-SA — дефолт зафиксирован: в том же SEC-C-seed** (SEC-F-09/SEC-C
   декларируют SA-seed в kacho-iam как единый источник; operator-SA + его viewer-tuples
   входят в этот seed, не в отдельную миграцию SEC-G — избегаем дубля). Подтвердить при ре-ревью.
3. **ACR-exempt для SA — подтвердить реализацию (§4.1.2).** Сценарии S2-01/04/05
   опираются на то, что service→service mTLS-SA-флоу освобождён от `required_acr_min=2`.
   SEC-C обязан реализовать эту ветку в IAM-handler; здесь — acceptance-предпосылка.
