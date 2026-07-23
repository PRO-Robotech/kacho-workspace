---
title: apigw-opsproxy
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - operation
---

# kacho-api-gateway/internal/opsproxy

**Path**: `kacho-api-gateway/internal/opsproxy/`

Per-domain OperationService proxy — `/operations/{id}` приходит на gw, надо понять, в какой backend проксировать.

## Files

- `proxy.go` — gRPC handler, который реализует `OperationServiceServer` локально и роутит `Get`/`Cancel` по prefix-у operation-id:
  - `enp...`, `e9b...` → vpc backend.
  - `epd...` → compute backend.
  - `iop...` → iam backend (KAC-105).
  - `nlp...` → nlb backend (KAC-161).
  - legacy `vpc_...` → vpc backend.
  - (KAC-124: `b1g`/`bpf`/`rm_` префиксы удалены — resource-manager retire.)
- `proxy_test.go`.

## Why local impl

`RegisterOperationServiceHandlerServer` (а не `HandlerFromEndpoint`) — потому что **per-domain routing** не делается grpc-gateway автоматически: gw регистрирует один URL → один backend. Локальная реализация смотрит id, дёрнет правильный grpc-stub upstream.

## Metadata propagation (KAC-169)

`Get`/`Cancel` обязаны конвертировать **incoming** gRPC metadata → **outgoing** перед вызовом backend через helper `propagateMetadata(ctx)`. Без этого `x-kacho-principal-{type,id,display-name}` (set by `restmux.WithMetadata`) теряются — backend видит анонимный principal и его per-RPC authz возвращает NotFound/PermissionDenied. Тот же pattern что в [[apigw-proxy]] (`director.go` / `shimproxy.go`). См. KAC-169.

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
