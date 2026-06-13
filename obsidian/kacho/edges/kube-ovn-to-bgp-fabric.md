---
title: kube-ovn-speaker → BGP route-reflector (data-plane маршрут-анонс)
category: edge
caller_repo: kacho-deploy
callee_repo: kube-ovn
sync_async: async
protocol: BGP (TCP-179)
status: deprecated
superseded_by: "[[vpc-operator-to-cilium-realization]]"
related_tickets:
  - OP2-P-BGP
tags:
  - edge
  - kacho-deploy
  - kube-ovn
  - cross-service
  - deprecated
---

# kube-ovn-speaker → BGP route-reflector

> [!warning] DEPRECATED (2026-06-13) — вытеснено Cilium SRv6
> kube-ovn-speaker-часть заморожена вместе с [[vpc-operator-to-kubeovn]] (канон —
> Cilium SRv6, см. [[vpc-operator-to-cilium-realization]]). **Но BGP route-reflector
> фабрика переиспользуема**: Cilium BGP control plane анонсирует SRv6 SID/VPN-маршруты
> по тому же BGP в ту же фабрику. Сохранить RR (ASN-план 65000/65001, GoBGP); заменить
> speaker (kube-ovn) на Cilium BGP CP. Контент НЕ удалён.

Новое **data-plane** ребро (OP2-P-BGP): `kube-ovn-speaker` анонсирует CIDR Kachō-подсетей
в BGP-фабрику (route-reflector), чтобы доставить их в маршрутизацию **минуя** стрипаемый
`Vpc.spec.staticRoutes` (kacho-vpc-operator#2). Фундамент prod-тира multi-AZ inter-zone L3.

## Поток

```
kube-ovn Subnet (annotation ovn.kubernetes.io/bgp=cluster)   ← ставит kacho-vpc-operator
        │  (egress-reconciler, OP2-P-BGP — см. [[vpc-operator-to-kubeovn]])
        ▼
kube-ovn-speaker (DaemonSet, gateway-ноды ovn.kubernetes.io/bgp=true, hostNetwork)
        │  BGP UPDATE: анонс subnet-CIDR (+ pod /32)
        │  cluster-as=65001 → neighbor-as=65000, TCP-179
        ▼
route-reflector (GoBGP, PoC на kind) — учит маршрут, реанонсит (multi-AZ)
```

## Свойства

- **Sync/async**: async, continuous BGP-сессия (keepalive). Анонс/withdraw — событийно по
  появлению/снятию аннотации на Subnet.
- **Opt-in**: аннотация `ovn.kubernetes.io/bgp` на kube-ovn Subnet/Pod. `cluster`/`true` →
  policy Cluster (анонс со всех speaker-нод); `local` → только ноды с pod'ами; снятие —
  `ovn.kubernetes.io/bgp-`. Оператор ставит `cluster` always-on на все Kachō-подсети.
- **Identity / next-hop**: на single-node kind speaker (hostNetwork) дозванивается до pod-IP
  RR напрямую; kube-proxy/cni SNAT'ит source в `10.244.0.1` → RR видит peer/next-hop как
  `10.244.0.1` (RR — dynamic-neighbor, принимает любой source). Для prod/multi-AZ next-hop =
  IP gateway-ноды (RR вне pod-network / direct node peering).
- **ASN-план** (private, RFC 6996): speaker 65001, RR 65000.
- **v6**: на стенде `NET_STACK ipv4` v6-анонс не активен (нужен `--neighbor-ipv6-address` +
  v6 AFI/SAFI); v6-подсети аннотируются оператором, но speaker их не анонсит. Вне scope PoC.

## Безопасность

- **Вне gRPC mTLS-mesh**: mTLS Kachō — только gRPC-рёбра operator→{vpc,iam} (SEC-G).
  BGP — отдельный data-plane канал; аутентификация = BGP TCP-MD5 / `--auth-password`,
  НЕ mTLS. Happy-path PoC без auth; пароль (если нужен) — k8s Secret, никогда не plaintext
  в git/values/vault (vault.md запрет секретов).
- **Инфра-чувствительно**: ASN/neighbor/auth — underlay-конфиг (security.md), НЕ на публичной
  поверхности Kachō-ресурсов (Subnet/Network показывают tenant-intent: id/name/CIDR/status).
- **Не цикл / не build-edge**: чисто data-plane; нового gRPC service→service вызова не вводит
  (polyrepo.md).

## Деплой / verify

`kacho-deploy/argo-apps/kube-ovn/bgp/` (speaker.yaml, route-reflector.yaml, README runbook) +
`scripts/bgp-up.sh` (kind-dev-safe). Verify:
`kubectl -n kacho-kube-ovn exec deploy/kube-ovn-bgp-rr -- gobgp neighbor` (Established) /
`... gobgp global rib` (выученные CIDR).

## История

- 2026-06-12 (OP2-P-BGP, создано) — speaker + GoBGP RR PoC на kind. Live: session
  Established, custom-VPC subnet-CIDR (`192.168.88/89.0/24`, `29.62.0.0/16`) + Kachō-NIC /32
  выучены RR + персистят (≠ стрип #2), withdraw на снятие аннотации. PR kacho-deploy#75 +
  kacho-vpc-operator#3 (аннотация на Subnet — см. [[vpc-operator-to-kubeovn]]).

#edge #kacho-deploy #kube-ovn #deprecated
