---
title: "KAC-52: NIC attach race fix (atomic CAS)"
aliases:
  - KAC-52
ticket_id: KAC-52
category: kac
status: done
type: fix
repos:
  - kacho-vpc
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-52
tags:
  - kac
  - done
  - kacho-vpc
  - ni
  - race-fix
---

# KAC-52: NIC attach race fix

> [!warning] TOCTOU race
> Старый софт-guard `if cur.UsedByID != ""` + безусловный `UPDATE` пропускал concurrent attach к одному NIC: second-writer-wins.

Заменён на single-statement CAS:

```sql
UPDATE network_interfaces
   SET used_by_id = $new
 WHERE id = $id
   AND (used_by_id = '' OR used_by_id = $new)
RETURNING ...;
```

Миграция 0016 пыталась добавить partial `UNIQUE(used_by_id) WHERE <>''` как backstop — оказалось семантически неверно (multi-NIC instance), откачена 0017. CAS-only достаточно.

## See also

- [[resources/vpc-networkinterface]]
- [[rpc/vpc-networkinterface-service]]
- [[edges/compute-to-vpc-nic-validate]]

#kac #done #ni #race-fix
