---
title: apigw-allowlist
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - security
---

# kacho-api-gateway/internal/allowlist

**Path**: `kacho-api-gateway/internal/allowlist/`

Allowlist для public TLS endpoint — какие RPC'ы могут попадать на edge. Защита от случайного засвечивания `Internal*` методов наружу (CLAUDE.md «Запреты» #6).

## Files

- `list.go` — allowed proto-method strings (например `/kacho.cloud.vpc.v1.NetworkService/Create`); deny-by-default.
- `list_test.go`.

## Pattern

При получении requests на TLS-listener — director проверяет method-string vs allowlist. Если нет — `Unimplemented` (или 404 на REST).

**Deny-by-default — несущее свойство, а не деталь.** Список решает, что попадает наружу; пустой список здесь означает «наружу не выставлено ничего», то есть отказ. Это ровно **обратная** семантика пустоты по сравнению с allow-list доверенных форвардеров в [[corelib-grpcsrv]], где пустой список значит «не сужаем» и потому доверяет всем. Два разных списка, два противоположных смысла пустоты — не переносить рассуждение с одного на другой.

> [!note] Этот список — про поверхность методов, а не про права
> Он отвечает на «опубликован ли RPC на внешнем крае» (ban #6) и **не** заменяет per-RPC
> authz-Check: RPC, законно попавший в список, всё равно проходит проверку прав на своём
> объекте. Точно так же отсутствие метода снаружи не даёт основания снять с него проверку
> на внутреннем листенере.

## See also

[[apigw-proxy]] [[apigw-restmux]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #security
