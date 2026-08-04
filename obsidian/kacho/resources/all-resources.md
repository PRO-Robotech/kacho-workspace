---
title: Все ресурсы — указатель
aliases:
  - all resources
category: hub
verified_against: "ствол redesign/integration, сверено 2026-08-05"
tags:
  - hub
  - resource
---

# Все ресурсы

Файл был пуст (ноль байт), при том что на него ссылается корневой указатель vault.
Пустая заметка с тем же именем, что у базы, перехватывает ссылку и показывает пустоту
вместо таблицы — поэтому здесь стоит содержание, а не заглушка.

Табличные срезы живут в базе **`all-resources.base`** (виды: все ресурсы · VPC ·
Deprecated · карточки). Свойство разреза называется `project_level` — «папки» как уровня
иерархии не существует, её преемник — проект iam.

## Домены и владельцы (сверено по стволу `redesign/integration`, 2026-08-05)

| Домен | Владелец (каталог монорепо) | Ресурсы |
|---|---|---|
| iam | `services/iam/` | Account · Project · User · ServiceAccount · Group · Role · AccessBinding · Cluster |
| vpc | `services/vpc/` | Network · Subnet · SecurityGroup · RouteTable · Address · Gateway · NetworkInterface · AddressPool (админский) |
| compute | `services/compute/` | Instance · MachineType |
| storage | `services/storage/` | Volume · Snapshot · Image · DiskType |
| geo | `services/geo/` | Region · Zone |
| nlb | `services/nlb/` | NetworkLoadBalancer · Listener · TargetGroup · Target |
| registry | `services/registry/` | Registry · Repository · Tag |
| operation | у каждого сервиса своя таблица | [[operation]] |

## Что в этой папке — история, а не описание сегодняшнего дня

Записки со `status: deprecated` описывают снятые предметы и несут предупреждение с
предикатом переписи по дереву. Срез «Deprecated» в базе собирает их **по статусу**, а не
по имени домена, — чтобы следующее снятие не потребовало править базу.

## Пробел, названный числом

Блочное хранение (Volume / Snapshot / Image / DiskType) принадлежит **storage**, и записок
ресурсов по нему в этой папке **ноль**. Дубль в compute ретайрен (см. [[compute-instance]]),
то есть описания владельца нет ни с одной стороны. Это открытый долг, а не «нечего
описывать».

#hub #resource
