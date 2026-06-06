---
title: InternalNetworkInterfaceService (removed)
aliases:
  - InternalNetworkInterfaceService (vpc)
  - Internal NIS
proto_file: ""
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
related_resource: "[[resources/vpc-networkinterface]]"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalNetworkInterfaceService (vpc) — REMOVED

> [!warning] Удалён в KAC-36/79/80
> Этот сервис — часть kube-ovn-эпохи data-plane control-plane-модели. Удалён вместе с
> internal data-plane-проекцией NetworkInterface и writeback-RPC `ReportNiDataplane`.
> Никогда не был commit'нут в proto. Заметка оставлена как tombstone, чтобы wikilinks не ломались.

Прежде планировался как internal-projection NetworkInterface с инфра/data-plane-полями +
writeback-RPC из `kacho-vpc-implement`. Миграция **0023** (`drop_network_vpn_id_and_ni_dataplane`)
убрала соответствующие колонки из `network_interfaces`. **Публичный** `NetworkInterfaceService`
([[vpc-networkinterface-service]]) — живой и не затронут.

## See also

[[vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../edges/vpc-implement-to-vpc]]

#rpc #kacho-vpc #internal #deprecated
