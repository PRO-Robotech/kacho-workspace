---
title: "KAC-55: NIC v4/v6 cardinality ≤ 1 (DB CHECK)"
aliases:
  - KAC-55
ticket_id: KAC-55
category: kac
status: done
type: fix
repos:
  - kacho-vpc
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-55
tags:
  - kac
  - done
  - kacho-vpc
  - ni
---

# KAC-55: NIC v4/v6 cardinality ≤ 1

> [!note] Stub

DB-level CHECK constraint (миграция 0018) гарантирует, что у NIC `v4_address_ids[]` и `v6_address_ids[]` содержат не более одного элемента каждый. Соответствует AWS ENI-семантике (один primary IP на family).

## See also

- [[resources/vpc-networkinterface]]

#kac #done #ni
