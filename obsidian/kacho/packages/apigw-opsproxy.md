---
title: apigw-opsproxy
category: packages
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - operation
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# gateway/internal/opsproxy — маршрутизация операции по её префиксу

**Каталог**: `gateway/internal/opsproxy/`
**Прежде** (полирепо): `kacho-api-gateway/internal/opsproxy`.

Служба операций реализована **локально** и роутит `Get`/`Cancel` в нужный домен по
префиксу идентификатора: транскодирование REST регистрирует один путь на один
адрес, а здесь адрес выбирается по содержимому запроса.

## Таблица префиксов — из констант фундамента, а не переписанная рядом

Ключи таблицы берутся из `pkg/ids` там, где такие константы есть: смена префикса в
фундаменте автоматически меняет ключ здесь, а проба соответствия ловит расхождение.
Домены на ревизии `96b2879a` — vpc, compute, nlb, registry, storage, iam, geo; плюс
отдельная таблица для старой формы идентификатора вида «имя_домена + подчёркивание».

Два префикса **заданы литералом**, и это осознанно оговорено в самом коде: у geo
корень операций живёт не в общем каталоге. Прежняя редакция называла соответствия
поимённо и уже разошлась с деревом (в частности, префикс балансировки был назван
неверно), поэтому здесь перечисляются домены, а не строки.

> [!note] Префикс не восстанавливает тип ресурса
> Несколько ресурсов делят один корень операций (у compute — машина и тип машины,
> у nlb — все три ресурса). Маршрутизация по префиксу отвечает на вопрос «в какой
> домен», а не «какой это ресурс», и закладываться на второе нельзя
> ([[corelib-ids]]).

## Личность обязана доехать до домена

`Get`/`Cancel` конвертируют **входящие** метаданные в **исходящие** перед вызовом
домена. Без этого домен видит неопознанного вызывающего, и его собственная проверка
прав отвечает отказом — на **положительном** пути. Тот же приём, что в сквозном
прокси ([[apigw-proxy]]).

## Creator-only op-authz (`checkOperationOwnership`) + fixture-discipline

`Get`/`Cancel` после backend-вызова проверяют **ownership** (анти-BOLA, CWE-639/863):
операцию может читать/отменять ТОЛЬКО:
- **создавший её principal** — `principal_type` + `principal_id`, записанные в Operation при
  Create (type-match защищает от коллизии id между user/service_account); ЛИБО
- **внутренний `system/bootstrap` worker** (`callerType=="system" && callerID=="bootstrap"` —
  cross-service polling/реконсайл; читает любую, включая owner-less legacy-строки).
Owner-less / system-owned Operation НЕ world-readable для tenant'а (fail-closed). Deny →
NotFound/PermissionDenied (backend hide-existence 404 или gw 403). `jwtBootstrap`
(kacho-bootstrap-admin) — это **tenant `service_account`**, НЕ внутренний system/bootstrap, →
он НЕ может читать чужие операции.

**Fixture-discipline (testing.md-класс, НЕ баг продукта):** async-op, созданный newman-шагом под
`auth=`-override, ОБЯЗАН поллиться (`poll_operation_until_done`/`assert_op_success`) под ТЕМ ЖЕ
creator-actor'ом — иначе creator-only `Get` денаит 404/403 (op-completion verify падает, хотя
сама мутация была авторизована 200). Инцидент #71 VOL-OBJSELF: objself-patch/delete под
`jwtProjectEditorA`, но poll под default `jwtBootstrap` → 404. Фикс: `poll_operation_until_done(auth=…)`
+ unique `poll-op-<n>` имена (commit b191066, storage). Аудит: #73 REPO-SETUP создаёт+поллит под
default registry-actor (без override) → OK.

## See also

[[apigw-restmux]] [[../rpc/operation-service]] [[corelib-ids]] (prefix-determinism)

#packages #kacho-apigw #operation
