---
title: PrivateEndpointService (снят)
aliases:
  - PrivateEndpointService (vpc)
proto_file: "нет — контракта в дереве не существует"
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
status: deprecated
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_resource: "[[resources/vpc-privateendpoint]]"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - privateendpoint
  - deprecated
---

# PrivateEndpointService (vpc) — сервиса нет

> [!warning] Ни контракта, ни сервиса, ни маршрутов
> Предикат переписи (ствол `redesign/integration`, 2026-08-05):
> `grep -ril 'private_endpoint\|PrivateEndpoint\|privatelink'` по `proto/`, `services/`,
> `gateway/`, `pkg/` — **ноль** файлов. Каталога `proto/kacho/cloud/vpc/v1/privatelink/`
> не существует; в `proto/kacho/cloud/vpc/v1/` девятнадцать файлов, ни одного про
> privatelink.
>
> Прежняя редакция перечисляла шесть методов и шесть REST-маршрутов как действующие.
> Это уверенное описание отсутствующего: по нему нельзя ни позвать, ни найти код, а
> читается оно как контракт.

## Что было замыслом

Приватная точка входа тенанта к платформенным сервисам внутри его подсети. Ресурс —
[[../resources/vpc-privateendpoint]] (там же разбор, что от замысла осталось верным).

## Если заводить заново

Начинать с приёмки Given-When-Then (ban #1), а не с этой записки: форма ресурса,
адресация по `id`, async-мутации и якорь размещения выводятся из общих правил, а
маршруты `/vpc/v1/endpoints/*` из прежней таблицы никем не заняты и ничего не значат.

## См. также

[[../resources/vpc-privateendpoint]] · [[vpc-address-service]] · [[vpc-subnet-service]]

#rpc #kacho-vpc #privateendpoint #deprecated
