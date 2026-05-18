---
title: "KAC-71: AddressPool v4/v6 split + cascade family-filter"
aliases:
  - KAC-71
ticket_id: KAC-71
category: kac
status: done
type: feature
repos:
  - kacho-vpc
  - kacho-proto
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-71
tags:
  - kac
  - done
  - kacho-vpc
  - addresspool
---

# KAC-71: AddressPool v4/v6 split

> [!note] Stub

Разделение AddressPool по IP family: `v4_cidr_blocks` и `v6_cidr_blocks` — отдельные fields. Нельзя mix family в одном pool. 5-step cascade resolve фильтрует по запрашиваемой family. Subnet может быть v6-only (новая возможность). Миграция 0022.

## See also

- [[resources/vpc-addresspool]]
- [[resources/vpc-subnet]]
- [[rpc/vpc-internal-address-pool-service]]

#kac #done #addresspool
