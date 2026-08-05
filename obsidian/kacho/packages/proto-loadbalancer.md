---
title: proto-loadbalancer
category: packages
repo: kacho-proto
path: proto/kacho/cloud/loadbalancer/v1
layer: proto
status: stable
tags:
  - proto
  - kacho-nlb
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# proto/kacho/cloud/loadbalancer/v1 — контракты домена балансировки

**Каталог**: `proto/kacho/cloud/loadbalancer/v1/`
**Пакет контракта**: `kacho.cloud.loadbalancer.v1`
**Go-импорт**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/loadbalancer/v1`
**Владелец**: домен nlb — каталог `services/nlb/` монорепо.
**Импортируют** (`go list` на `96b2879a`, non-test): nlb 10 пакетов · шлюз 1.

> [!warning] «Заморожен, бэкенд не написан» — было неверно
> Прежняя редакция объявляла контракт замороженным, скопированным у чужого облака и
> ждущим, когда сервис появится. По дереву сервис существует, реализован и является
> **самым крупным потребителем** общего перехватчика прав; контрактов в каталоге
> вдвое больше, чем перечисляла записка. Утверждение «вне области» пережило момент,
> когда область его накрыла.

## Файлы (по дереву, `96b2879a`)

**Ресурсы**: `network_load_balancer.proto` · `listener.proto` ·
`target_group.proto` · `health_check.proto`.
**Публичные службы**: `network_load_balancer_service.proto` ·
`listener_service.proto` · `target_group_service.proto`.
**Внутренние (:9091)**: `internal_load_balancer_announce_service.proto` ·
`internal_resource_lifecycle_service.proto`.
Плюс `package_options.proto`.

Слушатель (`Listener`) как отдельный ресурс и обе внутренние службы прежней
редакции известны не были.

## Что важно помнить про этот домен

- **Размещение когерентно.** Зональный балансировщик связывается с подсетью и
  адресом **своей** зоны (включая пару адресов разных семейств — в одной зоне),
  региональный — своего региона плюс эникаст. Регион зоны берётся **резолвом у
  владельца** (geo), а не выводом из имени: строковая деривация молча возвращает
  пустую строку на ресурсе без зоны, и проверка превращается в тождественно
  истинную (`data-integrity.md` §Placement-coherence).
- **Чужие идентификаторы.** Для источников виртуального адреса домен **вправе**
  прогнать чужой идентификатор через общий синтаксический разбор до обращения к
  владельцу — это **задокументированное** исключение с тремя границами; остальные
  чужие ссылки проверяются только на существование у владельца
  (`api-conventions.md` §By-lane code-split).
- **Аллокация из ограниченного пула.** Внешний адрес обязан возвращаться в
  свободный список на **каждом** пути высвобождения, атомарно; иначе параллельный
  прогон исчерпывает пул.

## См. также

[[nlb-domain]] [[nlb-apps-kacho-api-loadbalancer]] [[nlb-apps-kacho-api-listener]]
[[nlb-apps-kacho-api-targetgroup]] [[nlb-apps-kacho-api-internal-lifecycle]]

#proto #kacho-nlb
