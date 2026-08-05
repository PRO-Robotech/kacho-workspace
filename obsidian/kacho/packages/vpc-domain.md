---
title: vpc-domain
category: packages
repo: kacho-vpc
layer: domain
tags:
  - packages
  - kacho-vpc
  - domain
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/domain

**Каталог**: `services/vpc/internal/domain/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/domain/`)
**Импортирует**: стандартную библиотеку + [[corelib-ids]] / [[corelib-validate]] +
сгенерённые стабы (только ради константного отображения перечислений).
**Импортируют**: все слои сервиса — сущности единые.

Чистые сущности домена, собственные типы-обёртки, конструкторы и методы сравнения.
Самовалидирующиеся: конструктор отвергает недопустимое состояние (правило скила
`evgeniy`).

## Экспортируемые типы (снято с дерева, `96b2879a`)

**Ресурсы**: `Network` · `Subnet` · `Address` · `RouteTable` · `SecurityGroup` ·
`SecurityGroupRule` · `Gateway` · `NetworkInterface` · `AddressPool` · `StaticRoute` ·
`DhcpOptions`.
**Обёртки и перечисления**: `RcNameVPC` · `RcDescription` · `RcLabels` (`LabelKey`,
`LabelVal`) · `AddressType` · `IpVersion` · `AddressPoolKind` ·
`NetworkInterfaceStatus` · `GatewayType` · `SecurityGroupRuleDirection` ·
**`SubnetPlacementType`**.
**Спецификации адреса**: `InternalIpv4Spec` · `InternalIpv6Spec` ·
`ExternalIpv4Spec` · `ExternalIpv6Spec` · `AddressRequirements` ·
`AddressReference` · `AllocateResult`.
**Зеркала соседей** (только чтение): `Region` · `Zone`.
**Ошибки**: `ValidationError` · `FieldViolation`.

Прежняя редакция называла таблицей файлов сущность приватной точки подключения,
селектор пула уровня облака, тип `MacAddress` и конструктор сети — ни одного из этих
имён в дереве нет. Перечень выше — по типам, а не по файлам: файлы переименовываются,
типы переживают.

## `SubnetPlacementType` — якорь размещения всего домена

Подсеть несёт дискриминатор «зональная либо региональная», взаимоисключающе, и это
закреплено проверкой на уровне БД. Сетевой интерфейс и адрес зоны **не несут** —
наследуют через подсеть; у региональной (эникаст) подсети зоны нет, поэтому её
адреса регион-областные и из зональной проверки исключены by construction
(`data-integrity.md` §Placement-coherence).

## Правила слоя

- Обёртка вместо голой строки: имя ресурса не принимает недопустимое значение.
- Конструктор — единственный путь создания; собирать структуру снаружи пакета нельзя.
- Сравнение — для расчёта разницы и проверок при конкурентной записи.
- Слой **не** импортирует ни драйвер БД, ни транспорт: это то, что делает его
  проверяемым без стенда.

## See also

[[vpc-dto]] [[vpc-repo-kacho]] [[corelib-ids]] [[corelib-validate]]

#packages #kacho-vpc #domain
