---
title: "KAC-2: NetworkInterface first-class ресурс + control-plane resource model"
aliases:
  - KAC-2
ticket_id: KAC-2
category: kac
status: done
type: epic
repos:
  - kacho-vpc
  - kacho-compute
  - kacho-proto
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-2
tags:
  - kac
  - epic
  - done
  - kacho-vpc
  - ni
---

# KAC-2: NetworkInterface first-class ресурс + control-plane resource model

> [!note] Stub
> Полный trail закрытого эпика — в YouTrack. Здесь только запись для wikilink-разрешения.

Эпик: вариант А (NIC — first-class ресурс в kacho-vpc, AWS-ENI стиль; расхождение со YC). Включил `vpn_id` как internal-only field на Network, Hypervisor как internal-ресурс kacho-compute, impl-controller reads from upstream internal API.

Subtasks: KAC-3 ... KAC-11, KAC-14.

## See also

- [[resources/vpc-networkinterface|NetworkInterface]]
- [[rpc/vpc-networkinterface-service|NetworkInterfaceService]]
- [[KAC/KAC-94]] — последующий эпик skill `evgeniy` (использовал KAC-2 как baseline)

#kac #epic #done
