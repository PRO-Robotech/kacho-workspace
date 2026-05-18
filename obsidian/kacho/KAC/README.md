---
title: KAC tickets — trail
aliases:
  - KAC index
  - KAC tickets
category: hub
tags:
  - kac
  - index
---

# KAC tickets — trail

Папка с заметками по KAC-тикетам YouTrack. Каждый тикет (feature / batch fix / эпик) обязан иметь файл `KAC-<N>.md` (см. workspace `CLAUDE.md` §«Obsidian vault — обязательный context-источник и trail»).

## Шаблон

См. [[_TEMPLATE]] либо workspace CLAUDE.md.

## Текущие активные тикеты

(автоматически НЕ заполняется — Claude должен создавать/обновлять при работе над тикетом)

- [[KAC-104]] — Kachō IAM: Account/Project + Zitadel + OpenFGA (REBAC) — **epic, to-do**
  - [[KAC-105]] — E0: `kacho-iam` skeleton + Account/Project/User/SA/Group/Role/AccessBinding CRUD — to-do
  - KAC-106 — E1: folder_id → project_id миграция (vault-entry будет при старте работы)
  - KAC-107 — E2: Zitadel OIDC + auth-interceptor
  - KAC-108 — E3: OpenFGA REBAC + Check-interceptor + реактивность (DoD #5)
  - KAC-109 — E4: signup-flow + UI блок IAM + principal в Operations
  - KAC-110 — E5: deprecate `kacho-resource-manager`

## Закрытые эпики

- [[KAC-2]] — NetworkInterface first-class ресурс + control-plane resource model
- [[KAC-15]] — Geography (Region/Zone) moved kacho-vpc → kacho-compute
- [[KAC-50]] — api-gateway listener split (public/TLS vs cluster-internal)
- [[KAC-52]] — NIC attach race fix (atomic CAS)
- [[KAC-55]] — NIC v4/v6 cardinality ≤ 1 (DB CHECK)
- [[KAC-56]] — RouteTable ↔ Subnet auto-association (DB triggers)
- [[KAC-71]] — AddressPool v4/v6 split + cascade family-filter
- [[KAC-94]] — Skill `evgeniy` 100% эталон в kacho-vpc (18 PR'ов)
- [[KAC-111]] — Squash migrations 0001..0034 → clean baseline (greenfield)

#kac #index
