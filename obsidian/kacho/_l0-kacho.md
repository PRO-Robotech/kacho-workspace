---
title: L0 — Kachō (Проект)
level: project
status: living
tags: [l0, project, architecture-vault]
---

# L0 — Kachō

Вершина 5-уровневой модели Architecture Vault. Описывает платформу целиком;
ниже — L1 Приклады (сервисы), L2 Функциональности, L3 Функции, L4 Переменные.

## Что за продукт

Kachō — облачная управляющая платформа: домены Organization/Account/Project,
VPC (Network/Subnet/SecurityGroup/RouteTable/Address/Gateway/PrivateEndpoint),
Compute (Instance/Disk/Image/Snapshot), IAM (Account/Project/User/
ServiceAccount/Group/Role/AccessBinding + authz/reviews/GDPR/JIT), плюс
data-plane на гипервизорах (`kacho-vpc-implement`, SRv6/eBPF).

## Как читать этот vault (5 уровней)

| Уровень | Что | Режим | Где |
|---|---|---|---|
| **L0** | Проект Kachō (этот файл) | курируется | `obsidian/kacho/_l0-kacho.md` |
| **L1** | Приклад — один сервис | курируется | `<repo>/docs/arch/_l1-<repo>.md` |
| **L2** | Функциональность — фича-кластер | курируется | `<repo>/docs/arch/l2-*.md` |
| **L3** | Функции — call-дерево, сигнатуры, RPC contract | генерится `archgraph` | `<repo>/docs/arch/generated/l3-*.md` |
| **L4** | Переменные — типы, поля, связи | генерится `archgraph` | `<repo>/docs/arch/generated/l4-*.md` |

L0–L2 пишет человек/Claude («зачем»). L3–L4 детерминированно генерит инструмент
`archgraph` («как»; по построению не содержит мёртвого кода). Агрегат всех
`<repo>/docs/arch/` стягивается сюда `make vault-sync` → `obsidian/kacho/<repo>/arch/`.

## Приклады (L1) и их дока

| Приклад | Роль | L1-дока |
|---|---|---|
| `kacho-iam` | Account/Project/User/SA/Group/Role/AccessBinding + authz/reviews/GDPR/JIT | [[kacho-iam/arch/_l1-kacho-iam]] |
| `kacho-vpc` | Network/Subnet/SG/RouteTable/Address/Gateway/PE/NIC | [[kacho-vpc/arch/_l1-kacho-vpc]] |
| `kacho-compute` | Instance/Disk/Image/Snapshot + Geography | [[kacho-compute/arch/_l1-kacho-compute]] |
| `kacho-api-gateway` | edge: gRPC-proxy + REST mux | [[kacho-api-gateway/arch/_l1-kacho-api-gateway]] |
| `kacho-corelib` | переиспользуемые Go-пакеты (вкл. инструмент `archgraph`) | — |
| `kacho-proto` | центральная директория `.proto` всех доменов | — |
| `kacho-deploy` / `kacho-ui` / `kacho-test` | стенд / SPA / e2e | — |

## Cross-service runtime-граф (Связи L0)

```
api-gateway ──→ iam, vpc, compute        (edge проксирует домены; корень графа)
vpc ──→ compute   (валидация zone_id — Geography в compute)
vpc ──→ iam       (ProjectService.Get; InternalIAMService.Check — authz)
compute ──→ vpc   (валидация NIC-spec Subnet/SG; IPAM Address)
compute ──→ iam   (ProjectService.Get; InternalIAMService.Check)
vpc-implement ──→ vpc   (write-back ReportNiDataplane)
```

`kacho-iam` — leaf-owner (Account/Project): в него зовут, он сам — никуда.
Циклы запрещены. БД — database-per-service, cross-service FK нет.

## Инструмент archgraph

`archgraph` (в `kacho-corelib/cmd/archgraph`) генерит L3/L4 и прогоняет
CI-блокирующие проверки: **C1** полнота (entry-point ⟺ L2-якорь), **C2**
мёртвый код, **C3** свежесть, **C4** doc-coverage (функция/переменная без
doc-коммента → FAIL). См. [[packages/corelib-archgraph]].

## Статус раскатки

L1/L2 + L3/L4 — заведены для `kacho-iam`, `kacho-vpc`, `kacho-compute`,
`kacho-api-gateway` (C1 completeness PASS у всех). Остаётся: триаж C2-findings,
заполнение `source_sha` (C3), дозаполнение doc-комментов (C4), CI-job `arch-vault`.
