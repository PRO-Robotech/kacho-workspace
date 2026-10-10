---
title: apigw-allowlist
category: packages
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - security
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался; 2026-10-10 — строки geo RegionService/ZoneService и iam ClusterService сверены git show kacho 1266@0ca889983ee4:gateway/internal/allowlist/list.go"
---

# gateway/internal/allowlist — что вообще выставлено наружу

**Каталог**: `gateway/internal/allowlist/`
**Прежде** (полирепо): `kacho-api-gateway/internal/allowlist`.

Перечень методов, допущенных на внешний слушатель. Защита от случайной публикации
внутренних поверхностей (core §Non-negotiables, п. 6).

## Экспортируемое API (снято с дерева)

```go
var AllowedMethods map[string]struct{}          // deny-by-default
func IsAllowed(methodPath string) bool
func HasInternalSuffix(methodPath string) bool
```

Файл один — `list.go`; вокруг него **шесть** отдельных проб (соответствие перечню
доменов, именованные поверхности, паритет, а также по одной на geo, registry и
storage). Такое соотношение объёмов само по себе сообщение: содержание списка
проверяется многими независимыми предикатами, потому что молчаливое добавление
строки сюда — и есть способ вынести наружу лишнее.

Запрос на внешнем слушателе сверяется с перечнем; несовпадение — отказ (для REST
это отсутствие маршрута). Отдельно и сильнее: внутренний метод, попавший на внешний
слушатель, **отвергается явно** перехватчиком в [[apigw-proxy]].

**Deny-by-default — несущее свойство, а не деталь.** Список решает, что попадает наружу; пустой список здесь означает «наружу не выставлено ничего», то есть отказ. Это ровно **обратная** семантика пустоты по сравнению с allow-list доверенных форвардеров в [[corelib-grpcsrv]], где пустой список значит «не сужаем» и потому доверяет всем. Два разных списка, два противоположных смысла пустоты — не переносить рассуждение с одного на другой.

> [!note] Этот список — про поверхность методов, а не про права
> Он отвечает на «опубликован ли RPC на внешнем крае» (ban #6) и **не** заменяет per-RPC
> authz-Check: RPC, законно попавший в список, всё равно проходит проверку прав на своём
> объекте. Точно так же отсутствие метода снаружи не даёт основания снять с него проверку
> на внутреннем листенере.

## Строки по задачам (ветка эпика `1266`, в `main` не влиты)

- geo `RegionService` и `ZoneService`: к чтению добавлены `Create`/`Update`/`Delete` — публичное
  администрирование каталога ([[KAC/issue-3092]]); `InternalRegionService`/`InternalZoneService` в перечне нет.
- iam `ClusterService` — четыре метода публичного близнеца администраторов кластера
  ([[KAC/issue-3093]], [[rpc/iam-cluster-service]]); `InternalClusterService` в перечне нет.

## History

- 2026-10-10 — строки geo и `ClusterService`: [[KAC/issue-3092]], [[KAC/issue-3093]], kacho#3104 → `1266` @`ad74c3ea01b5`.

## See also

[[apigw-proxy]] [[apigw-restmux]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #security
