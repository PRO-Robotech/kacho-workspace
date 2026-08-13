---
title: GuestAccessKeyService (compute)
aliases:
  - GuestAccessKeyService
proto_file: kacho/cloud/compute/v1/guest_access_key_service.proto
category: rpc
backend: kacho-compute
backend_port: 9090
visibility: public
domain: compute
related_resource: "[[resources/compute-guestaccesskey]]"
methods_count: 6
async_methods: 3
status: done
verified_against: "ветка release/compute-production-api @ 451a56cd, сверено 2026-08-13"
tags:
  - rpc
  - kacho-compute
  - compute
  - done
---

# GuestAccessKeyService

Ключи, с которыми арендатор входит в свои машины. Чтения синхронны, мутации возвращают
операцию — общая форма продукта.

| RPC | REST | Форма | Право |
|---|---|---|---|
| `Get` | `GET /compute/v1/guestAccessKeys/{id}` | sync | `v_get` @ ключ |
| `List` | `GET /compute/v1/guestAccessKeys` | sync | `viewer` @ проект |
| `Create` | `POST /compute/v1/guestAccessKeys` | операция | `editor` @ проект |
| `Update` | `PATCH /compute/v1/guestAccessKeys/{id}` | операция | `v_update` @ ключ |
| `Delete` | `DELETE /compute/v1/guestAccessKeys/{id}` | операция | `v_delete` @ ключ |
| `ListOperations` | `GET …/{id}/operations` | sync | `v_list` @ ключ |

**Правка меняет имя и метки.** Материал неизменяем: подменить его значило бы сменить того,
кто может войти, не сменив ни идентификатора, ни ссылок на него с машин — то есть тихо
переадресовать доступ. Смена материала выражается парой «завести новый, снять старый», и
каждая половина этой пары видна в журнале.

**Страница списка сужается пообъектно** тем же отношением, каким гейтится одиночное
чтение: право проекта не отвечает на вопрос «можно ли этому вызывающему видеть ЭТИ строки».

Ресурс и его инварианты — [[resources/compute-guestaccesskey]]. Задача — [[KAC/issue-158]].
