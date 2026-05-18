---
title: "KAC-56: RouteTable ↔ Subnet auto-association (DB triggers)"
aliases:
  - KAC-56
ticket_id: KAC-56
category: kac
status: done
type: feature
repos:
  - kacho-vpc
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-56
tags:
  - kac
  - done
  - kacho-vpc
  - routetable
---

# KAC-56: RouteTable ↔ Subnet auto-association

> [!note] Stub

PL/pgSQL триггеры (миграции 0019/0020) auto-ассоциируют новый Subnet с default RouteTable той же Network (если есть). Tenant может override через `Subnet.Update.route_table_id`. Удаление RouteTable, к которому привязаны Subnet'ы → `route_table_id` сбрасывается в NULL (ON DELETE SET NULL).

## See also

- [[resources/vpc-routetable]]
- [[resources/vpc-subnet]]

#kac #done #routetable
