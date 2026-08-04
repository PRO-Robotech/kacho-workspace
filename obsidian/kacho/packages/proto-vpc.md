---
title: proto-vpc
category: package
repo: kacho-proto
path: proto/kacho/cloud/vpc/v1
layer: proto
status: stable
tags:
  - proto
  - kacho-vpc
---

# proto/kacho/cloud/vpc/v1 — контракты сетевого домена

**Каталог**: `proto/kacho/cloud/vpc/v1/`
**Пакет контракта**: `kacho.cloud.vpc.v1`
**Go-импорт**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/vpc/v1`
**Владелец**: домен vpc — каталог `services/vpc/` монорепо.

## Ресурсы (по дереву, `96b2879a`)

`network.proto` · `subnet.proto` · `address.proto` · `route_table.proto` ·
`security_group.proto` · `gateway.proto` · `network_interface.proto`.
Плюс `package_options.proto`.

## Публичные службы

`NetworkService` · `SubnetService` · `AddressService` · `RouteTableService` ·
`SecurityGroupService` · `GatewayService` · `NetworkInterfaceService`.

## Внутренние (:9091, admin / cluster-internal)

`InternalNetworkService` · `InternalNetworkInterfaceService` ·
`InternalAddressService` · `InternalAddressPoolService`.

`InternalNetworkInterfaceService` в дереве **есть** — прежняя редакция утверждала
обратное («удалён, в контракт никогда не попадал»). Утверждение об отсутствии
пережило появление своего предмета, и это худший вид устаревания: оно закрывает
вопрос, вместо того чтобы его открыть.

> [!warning] Здесь были перечислены четыре несуществующих файла
> Прежняя редакция называла ресурс приватной точки подключения и его службу,
> внутреннюю службу уровня облака, поток изменений и подкаталог для будущих
> расширений. Ни одного из них в дереве нет; мёртвые имена здесь намеренно не
> воспроизводятся в форме координаты. Записка про приватную точку подключения в
> этой категории удалена той же правкой.

## Что стоит знать, открывая эти контракты

- **Якорь размещения — подсеть.** Она несёт дискриминатор (зональная либо
  региональная), закреплённый проверкой на уровне БД; сетевой интерфейс и адрес
  зоны **не несут** и наследуют её через подсеть. У региональной (эникаст) подсети
  зоны нет — адреса становятся регион-областными.
- **Адресация — по неизменяемому идентификатору.** Имя — косметическая метка в
  пределах проекта; в ссылки, гранты и пути оно не попадает никогда.
- **Мутации возвращают `Operation`**, чтение синхронно; поток наблюдения за
  изменениями как отдельная возможность не существует — опрос списка либо
  чтение операции.

## См. также

[[vpc-domain]] [[vpc-handler]] [[proto-root]] [[../resources/vpc-network]]

#proto #kacho-vpc
