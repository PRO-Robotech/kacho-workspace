---
title: "KAC-2: NetworkInterface first-class ресурс + control-plane resource model"
aliases:
  - KAC-2
ticket_id: KAC-2
category: kac
status: superseded
type: epic
repos:
  - kacho-vpc
  - kacho-compute
  - kacho-proto
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-2
tags:
  - kac
  - epic
  - deprecated
  - kacho-vpc
  - ni
---

# KAC-2: NetworkInterface first-class ресурс + control-plane resource model (SUPERSEDED)

> [!warning] Superseded — data-plane control-plane-слой удалён в KAC-36/79/80
> Эта запись — stub для wikilink-разрешения. **Живым** осталось только вариант-А-решение:
> NIC — first-class публичный ресурс в kacho-vpc (AWS-ENI стиль). **Удалена** kube-ovn-эпохи
> data-plane control-plane-привязка: internal-only data-plane-id на Network, Hypervisor как
> internal-ресурс kacho-compute, NIC-dataplane-проекция и writeback из impl-controller.

Subtasks: KAC-3 ... KAC-11, KAC-14 (data-plane-части отменены).

## See also

- [[resources/vpc-networkinterface|NetworkInterface]]
- [[rpc/vpc-networkinterface-service|NetworkInterfaceService]]
- [[KAC/KAC-94]] — последующий эпик skill `evgeniy` (использовал KAC-2 как baseline)

#kac #epic #done
