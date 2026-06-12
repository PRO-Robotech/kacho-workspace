---
title: "compute → vpc: NIC validate + attach (severed)"
aliases:
  - compute to vpc NIC validate
category: edge
caller_repo: kacho-compute
callee_repo: kacho-vpc
sync_async: async
protocol: grpc-cluster-internal
status: deprecated
related_tickets:
  - "[[KAC/KAC-94]]"
  - "[[KAC/KAC-266]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-vpc
  - ni
---

# compute → vpc: NIC validation + attach

> [!warning] Ребро разорвано в KAC-266 — инстанс без авто-NIC
> `kacho-compute` **больше не создаёт и не привязывает NIC** при `Instance.Create`. Удалены
> compute `materializeNICs` / `attachExistingNIC` / `releaseNICs` / `setNICAddressReferences`
> и vpc-side RPC `NetworkInterfaceService.AttachToInstance` / `DetachFromInstance` (contract-removal).
> `network_interface_specs` в `CreateInstanceRequest` теперь **игнорируется**. NIC остаётся
> first-class CRUD-ресурсом vpc; привязка NIC↔Instance выпилена из request-path и переосмысляется
> отдельно («compute proper rework deferred»). Ниже — historical-описание для archeology.

**Caller** (historical): `kacho-compute` (Instance.Create / .UpdateNetworkInterfaces)
**Callee** (historical): `kacho-vpc` (`NetworkInterfaceService.AttachToInstance` + `SubnetService.Get` + `SecurityGroupService.Get`)
**Protocol**: gRPC cluster-internal
**Sync/Async**: async (внутри Compute Operation worker'а)

## When invoked (historical, до KAC-266)

- **Instance.Create** с NIC-spec:
  - Если `existing_network_interface_id` → `NetworkInterfaceService.AttachToInstance` (CAS на `used_by_id`).
  - Если inline NIC-spec → `NetworkInterfaceService.Create` → `AttachToInstance`.
  - Для каждого NIC валидировался `subnet_id` (Subnet.Get) + `security_group_ids` (SG.Get для каждой).
- **Instance.Delete** — `DetachFromInstance` через vpc → освобождал NIC.

## Что осталось (KAC-266)

- vpc NIC CRUD (`NetworkInterfaceService.Create/Get/Update/Delete`) — живо.
- compute → vpc Address-IPAM (`CreateExternalAddress`/`GetExternalAddress`/`DeleteAddress` +
  address-referrer) для AddOneToOneNat/RemoveOneToOneNat — живо (это **не** NIC-attach).

## Attach race (KAC-52) — historical

Внутри vpc был CAS-update, см. [[../resources/vpc-networkinterface]]. Compute должен был **ждать**
`AttachToInstance.Operation.done=true`. RPC удалён в KAC-266.

## History

- **KAC-94** — ребро заведено (compute создаёт/аттачит NIC при Create).
- **KAC-52** — attach защищён single-statement CAS (race-fix).
- **KAC-266** — ребро **разорвано**: compute больше не создаёт/привязывает NIC (инстанс без
  авто-NIC); vpc `AttachToInstance`/`DetachFromInstance` удалены (contract-removal). compute proper
  rework (как именно NIC будет привязываться к инстансу) — deferred.
- **SEC-M** — transport на **оставшемся** живом compute→vpc ребре (NIC-spec валидация
  `Subnet/SecurityGroup.Get` :9090 + one-to-one-NAT IPAM `Address.Get`/`InternalAddressService`
  :9091, см. «Что осталось KAC-266») переведён на **client-cert mTLS**. `kacho-compute`
  composition-root (`cmd/compute/main.go` `dialPeers` → `dialVPCPeer`) ветвится на
  `cfg.VPCMTLS.Enable`: enable=true → оба vpc-conn'а предъявляют `kacho-compute-client-tls`
  через corelib `grpcclient.TLSClientTransportCreds(cfg.VPCMTLS)` (тот же seam
  `dialPeerCreds`/`peerDialOptsCreds`, что несёт SEC-I iam-creds); enable=false → insecure
  (dev, нулевая регрессия). Один `cfg.VPCMTLS` (один ServerName=`vpc.kacho.svc.cluster.local`)
  покрывает оба listener'а (vpc Service = `vpc`). Зеркало `vpc→compute` (SEC-D-19). Helm
  (compute deploy chart) уже рендерит `KACHO_COMPUTE_VPC_MTLS_*` gated на `mtls.edges.vpc`;
  umbrella `values.mtls.yaml` → `compute.mtls.edges.vpc=true`. Контракт/RPC не менялись —
  только транспорт.

## See also

[[../rpc/vpc-networkinterface-service]] [[../rpc/vpc-internal-address-service]] [[../resources/vpc-networkinterface]] [[../KAC/KAC-266]]

#edge #cross-service #kacho-compute #kacho-vpc #ni
