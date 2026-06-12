---
title: kacho-vpc-operator → kube-ovn / Multus (data-plane materialization)
category: edge
caller_repo: kacho-vpc-operator
callee_repo: kube-ovn
sync_async: sync-poll
protocol: gRPC (upstream) + k8s API (downstream)
status: experimental
tags:
  - edge
  - kacho-vpc-operator
  - kube-ovn
  - grpc
  - cross-service
  - experimental
---

# kacho-vpc-operator → kube-ovn / Multus

Data-plane sibling оператора (`github.com/PRO-Robotech/kacho-vpc-operator`,
kubebuilder/controller-runtime). Control-plane его не касается — он **читает**
VPC-ресурсы из `kacho-vpc` по gRPC и **материализует** их в kube-ovn + Multus.
kube-ovn — **NON_PRIMARY** (secondary CNI; primary — kindnet/Cilium).

## Поток (OP1 — два контура через промежуточный CRD KachoSubnet)

```
kacho-vpc (vpc:9090, NetworkService/SubnetService.List)
   │  gRPC poll (Syncer.reconcileOnce, interval=10s) — Kachō без Watch
   │  ⚠ per-RPC authz-gate: оператор шлёт x-kacho-principal-{type,id}
   ▼
INGRESS (internal/syncer)            EGRESS (internal/controller, controller-runtime)
   ├─ Network → kubeovn.io/Vpc          For(&KachoSubnet{}).Owns(Subnet).Owns(NAD)
   │            (имя=network-id 1:1)     event-driven + periodic resync
   └─ Subnet  → KachoSubnet CR ─────────►  на КАЖДЫЙ CIDR (v4∪v6):
                (kacho.io/v1, cluster,        ├─ 1 kubeovn.io/Subnet (single-family,
                 1:1 зеркало spec)            │   protocol=IPv4|IPv6, решение A — БЕЗ combine)
                                              └─ 1 Multus NAD в projectNamespace
   NIC → pod annotations (webhook, k8s.v1.cni.cncf.io/networks + mac)  ← без изменений
```

**KachoSubnet** (`kacho.io/v1`, **cluster-scoped**) — первый собственный CRD оператора.
Cluster-scope обязателен: его ownerRef каскадит И на cluster-scoped kube-ovn Subnet,
И на namespaced NAD (namespaced owner НЕ мог бы владеть cluster-scoped Subnet).
Имя CR = subnet-id. Child-имена **stable-by-CIDR + by immutable id**:
`<subnet-id>-<shorthash(canonical(cidr))>` (НЕ index-based и НЕ от `spec.name`:
имя kube-ovn неизменяемо, а Kachō `name` мутабелен → имя-на-name осиротило бы
child при переименовании сабнета, S3-02b). Человекочитаемое имя — только в label
`kacho.io/upstream-name`.
Labels child'ов: `managed-by` + `project-id` / `upstream-id` / `upstream-name` /
`kacho.io/cidr`. Каждый child: `SetControllerReference(KachoSubnet)` (controller=true).
`pickCIDR` (first-v4-only, терял v6+лишние CIDR) **удалён** — заменён итерацией v4∪v6.

### Deletion-sync
- **element-level** (CIDR убран из spec): egress считает desired-set
  `{name(cidr)|valid cidr}` vs actual owned-children (List по label upstream-id +
  ownerRef-uid) → PRUNE child'ов ∉ desired (kube-ovn Subnet + парный NAD).
  prune-fail-safe: битый CIDR не порождает имени и не участвует в set-diff (валидный
  child не запрунится из-за соседнего garbage).
- **whole-delete**: ingress сносит KachoSubnet CR → finalizer
  `kacho.io/kachosubnet-teardown` держит в Terminating; контроллер САМ удаляет free
  child'ы (controller-driven, GC по ownerRef не стартует пока владелец жив) → снимает
  finalizer когда чисто → k8s GC завершает каскад.
- **in-use safety**: child с реальными pod-аллокациями (version-pinned kube-ovn
  `.status.v4usingIPs`/`.status.v6usingIPs > 0`, **v1.16.1**; gateway/excludeIps НЕ в
  счёт) НЕ удаляется — degraded `Ready=False` reason `CIDRInUse` + Event + requeue.
  finalizer снимается в момент обнуления usingIPs (graceful dangling-ref, data-integrity §4).

**Shared-примитивы** материализации — `internal/kubeovn` (GVK, label-ключи,
`VpcNameFor`/`FirstUsableIP`/`Provider`/`NADConfig`), переиспользуются ingress+egress.
Cleanup orphan'ов ingress: KachoSubnet CR (по label) → egress GC-каскадит child'ы; затем Vpc.

> [!warning] Gotcha: field-scoped apply (иначе OCC hot-loop с kube-ovn)
> Контроллер kube-ovn САМ дефолтит доп. spec-поля созданной Subnet (`gatewayType`,
> `natOutgoing`, … — ~6 полей; 12 ключей итого vs 6 наших). `applyChild` ОБЯЗАН
> сравнивать/писать **только управляемые ключи** (protocol/cidrBlock/gateway/
> excludeIps/provider/vpc; `config` для NAD), а не весь `spec`. Whole-spec replace
> (`current.Object["spec"] = desired`) стирал kube-ovn-дефолты каждый reconcile →
> kube-ovn передефолчивал → два контроллера в hot-loop (~1877 OCC «object has been
> modified» конфликтов/мин, видно только на живом кластере — envtest без реального
> kube-ovn-контроллера это НЕ ловит). Фикс field-scoped: 0 конфликтов. kube-ovn НЕ
> переписывает наши 6 ключей (проверено), поэтому per-key merge безопасен.

## AuthZ (важно)

`kacho-vpc` включает per-RPC authz (`InternalIAMService.Check`) и читает принципала
из metadata `x-kacho-principal-*`. Прямой вызов без принципала → `PermissionDenied`.
Оператор инжектит принципала через unary-interceptor (`upstream.Dial(..., Principal, TLSClient)`);
принципалу нужен FGA-viewer на ресурсы project'а (в dev — cluster `system_admin`).

**SEC-G (mTLS)**: upstream-dial (operator→{vpc,iam}) переведён на mTLS с отдельным
client-cert оператора (SAN `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`,
§4.1.4); per-edge `enable` (`enable=false` → insecure back-compat). Principal-инжект
сохранён поверх mTLS (инвариант I2). В production — персональный least-priv SA
оператора (read-only ReBAC viewer, без мутаций; SEC-C seed). Детали транспорта/
least-priv: [[vpc-operator-to-vpc-mtls]]. webhook server-cert (kube-apiserver→webhook,
отдельный канал от gRPC client-cert, #5) выпускается внутренним CA `kacho-internal-ca`
(§4.1.6). **mTLS — только на gRPC-рёбрах**; operator→kube-ovn/multus (k8s-API,
downstream) — вне mTLS-периметра.

## Реализовано / boundary

- ✅ Network→Vpc, Subnet→Subnet+NAD, NIC→pod-annotation (networks+mac).
- ⏳ boundary (см. `kacho-vpc-operator/MAPPING.md`): SecurityGroup→ACL,
  RouteTable→Vpc.staticRoutes, Gateway→VpcNatGateway, Address→fixed-IP. NIC
  fixed-IP (resolve Address по `v4_address_ids`) — тоже boundary; IP пока даёт
  kube-ovn IPAM.

## Verified (2026-06-09, локальный kind)

Throwaway-кластер `kacho-ovn` (kindnet primary, kube-ovn secondary). **OVS
заводится на macOS Docker Desktop kind** (`ovs-ovn 1/1 Running`). Оператор
(one-shot `cmd/synconce`) материализовал project `prjp9q0576esfmj8yt7z`:
Network `net24p7w…` → Vpc (+3 subnets), subnets → kube-ovn Subnet `192.168.88/89/90.0/24`
+ NAD. Test-pod с NAD `sub3t0b1…` получил secondary NIC `net1=192.168.90.2`
из Kachō-subnet. Полный data-path подтверждён.

## Multi-tenant (два оператора, project↔namespace)

kacho Project ↔ k8s Namespace 1:1 (имя ns = project.id). **Два оператора** из одного
репо/образа (Dockerfile собирает 2 бинаря):

- **kacho-project-operator** (`cmd/nsoperator`, `internal/nssyncer`) — владеет
  namespace-lifecycle: fan-out kacho-iam `AccountService.List → ProjectService.List`
  (нет глобального list проектов) → Namespace на каждый project (label'ы
  managed-by/project-id/account-id). Prune исчезнувших (fail-closed: не прунит если
  iam-list упал). **Только этот** оператор имеет RBAC create/delete namespace.
- **kacho-vpc-operator** (`cmd`, `internal/syncer`) — multi-project: обнаруживает
  project-namespace'ы (label managed-by=kacho-project-operator), и на КАЖДЫЙ проект
  материализует Network→Vpc / Subnet→Subnet (cluster-scoped, name=id) + NAD **в
  namespace проекта** (provider `<sub>.<project-ns>.ovn`). RBAC на namespace —
  read-only. discovery+cleanup читают через НЕкэшированный `mgr.GetAPIReader()`;
  Terminating-namespace'ы пропускаются (иначе их удалённый project → vpc List
  PermissionDenied → listErr заблокировал бы cluster-cleanup).

### NIC-attach пода (webhook) + ownership
Правильный процесс: **внутренний Address (kacho-vpc IPAM в subnet) →
NetworkInterface (`v4_address_ids=[addr]`) → pod с аннотацией-ключом**:
```
{subnetID}.{projectID}.kacho.io/nic: {nicID}
```
Ключ кодирует subnet+project (kube-ovn-style), значение — id NIC'а. Pod-mutating-webhook
(`internal/webhook/v1`, включён self-signed cert + MutatingWebhookConfiguration, scope —
project-namespace'ы, failurePolicy=Ignore):
- парсит ключи, резолвит NIC → ставит `k8s.v1.cni.cncf.io/networks=<subnet-id>`
  (NAD в ns пода), `<provider>.kubernetes.io/mac_address`, и **fixed-IP**

> [!warning] KNOWN-BROKEN после OP1 (issue kacho-vpc-operator#1)
> Webhook ссылается на NAD по голому `<subnet-id>`, но OP1 создаёт NAD'ы
> **per-CIDR** с именем `<subnet-id>-<cidrhash>` → ни одного NAD с именем
> `<subnet-id>` нет → NIC-attach к secondary-сети не матчится. До OP1 совпадало
> (1 subnet → 1 NAD =id). Fix: резолвить NIC→Address→CIDR и ссылаться на
> `childName(subnetID, cidr)`. Латентно (подов с NIC ещё нет).
  `<provider>.kubernetes.io/ip_address` = аллоцированный kacho-vpc IPv4 (Address по
  `nic.v4_address_ids[0]`); kube-ovn фиксируется на него (kacho-vpc — источник истины IPAM).
- **Гарды**: `projectID`(из ключа) == `pod.Namespace` (доверяем namespace: k8s RBAC,
  не аннотации); резолвленный NIC обязан реально быть в этом `project`+`subnet` (ключ
  не врёт), иначе admission **denied**.

### Multi-NIC в поде
Несколько NIC = несколько ключей `{subnetID}.{projectID}.kacho.io/nic`.
- **Разные subnet'ы** — работает: каждый NIC → свой interface (net1/net2/…) + свой
  kacho-allocated fixed-IP. Проверено: net1=192.168.90.91, net2=192.168.88.157.
- **Один subnet дважды** — **структурно невозможно**: ключ `<sub>.<proj>.kacho.io/nic`
  одинаковый → второй перетёр бы первый в манифесте. Совпадает с ограничением kube-ovn
  (один logical-switch-port на под на subnet; raw-попытка → `AcquireAddressFailed`).
  Несколько IP → несколько NIC в РАЗНЫХ subnet'ах.

### Deletion-семантика (штатно)
- Subnet удалён в kacho-vpc → vpc-operator сразу удаляет kube-ovn Subnet. Если в
  subnet'е есть allocated IP (под с NIC) — kube-ovn finalizer
  (`kubeovn.io/kube-ovn-controller`) держит Subnet в Terminating до удаления пода
  (корректная data-plane safety, не баг оператора). Нет workload → prune за ~10с.
- Project удалён в iam → ns-operator прунит namespace (с подами/NAD внутри) →
  vpc-operator (project больше не итерируется) сносит cluster-scoped Vpc/Subnet по label.

Проверено 2026-06-09: accounts A/B (разные аккаунты) → projects A/B → изолированные
Subnet'ы (10.10.0.0/24 / 10.20.0.0/24) в отдельных kube-ovn VPC; поды vm-a/vm-b
получили `net1` из своих subnet'ов; delete subnet (clean) и delete project-B —
оба отработали штатно.

## История

- 2026-06-12 (id-naming fix, `b8b4cc5`) — child kube-ovn Subnet/NAD имена переведены
  с мутабельного `spec.name` на иммутабельный `spec.id` (`<subnet-id>-<cidrhash>`):
  rename Kachō Subnet больше не осиротит/пересоздаёт data-plane (rename-test RED→GREEN,
  проверено на живом стенде — старые `subnetwork-196829-*` запрунены, пересозданы
  `subs3z1…-*`). Найден смежный баг: NIC-webhook ссылается на NAD по `<subnet-id>`,
  а NAD'ы теперь `<subnet-id>-<cidrhash>` → **issue kacho-vpc-operator#1** (латентно).
- 2026-06-12 (OP1, KachoSubnet CRD redesign) — Subnet больше НЕ маппится напрямую в
  одну kube-ovn Subnet (first-v4-only `pickCIDR` удалён). Введён промежуточный
  cluster-scoped CRD `KachoSubnet` (`kacho.io/v1`) + два контура: ingress (syncer 1:1
  reflect Kachō Subnet → KachoSubnet CR) и egress (controller-runtime Reconciler →
  N×(kube-ovn Subnet+NAD) per-CIDR, single-family/решение A, stable-by-CIDR имена,
  ownerRef-каскад, element-prune, finalizer + in-use safety по version-pinned
  `v4usingIPs`/`v6usingIPs` kube-ovn v1.16.1). envtest egress-reconcile. Network→Vpc и
  NIC-webhook без изменений; SEC-G mTLS/FGA не тронуты; ns-operator не тронут.
  **Live-fix (тот же день, найдено на чистом `make dev-up MTLS=on`):** (1) `config/dev`
  kustomize не мог сослаться на `../rbac/role.yaml` (load-restrictor) → RBAC bundle
  применяется out-of-band из `operator-up.sh`; (2) egress field-scoped apply против
  OCC hot-loop с kube-ovn (см. callout выше). Оба провалидированы на живом кластере
  (create→reconcile→delete-cascade, 0 конфликтов).
- 2026-06-11 (SEC-G) — upstream-dial operator→{vpc,iam} переведён на mTLS (отдельный
  op client-cert, per-edge enable); least-priv read-only SA principal; webhook
  server-cert на internal-CA. Подробности: [[vpc-operator-to-vpc-mtls]].
- 2026-06-09 (v2) — multi-project + ns-operator (project↔namespace), NAD в namespace
  проекта, uncached cleanup-reader + skip-terminating-ns. Test accounts A/B.
- 2026-06-09 (v1) — core mapping (Network/Subnet/NIC) + principal-auth + names=id;
  kube-ovn+multus deploy на kind (`kacho-deploy/argo-apps/kube-ovn/values.kind.yaml`).
  Syncer был single-project, NAD в shared `kacho-multus`.

#edge #kacho-vpc-operator #kube-ovn #experimental
