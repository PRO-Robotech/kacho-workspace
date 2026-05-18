---
title: "KAC-15: Geography (Region/Zone) moved kacho-vpc → kacho-compute"
aliases:
  - KAC-15
ticket_id: KAC-15
category: kac
status: done
type: refactor
repos:
  - kacho-vpc
  - kacho-compute
  - kacho-api-gateway
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-15
tags:
  - kac
  - done
  - kacho-vpc
  - kacho-compute
  - geography
---

# KAC-15: Geography (Region/Zone) moved kacho-vpc → kacho-compute

> [!note] Stub
> Полный trail в YouTrack.

Перенесён ownership Region/Zone из kacho-vpc в kacho-compute. Развернул кросс-сервисное ребро: было `compute → vpc` (proxy зон), стало `vpc → compute` (validation zone_id). Mirror-таблица `compute.zones` (seeded из vpc) — удалена.

## See also

- [[edges/vpc-to-compute-zone-validate]]
- [[resources/vpc-subnet]] — теперь использует cross-service zone validation
- [[KAC/KAC-94]] — последующий рефакторинг

#kac #done #geography
