---
title: "api-gateway backend-dial mTLS (per-edge creds selection)"
aliases:
  - apigw backend dial mtls
  - api-gateway per-edge dial creds
category: packages
repo: kacho-api-gateway
layer: cmd
tags:
  - packages
  - kacho-api-gateway
  - security
  - cmd
  - composition-root
---

# api-gateway backend-dial mTLS (per-edge)

**Где**: `gateway/cmd/api-gateway/mtls_config.go` + `gateway/internal/config/config.go`.
**Слой**: композиционный корень плюс конфигурация. Только транспортные учётные
данные — они **ортогональны** личности вызывающего: сертификат отвечает «какой это
модуль», личность — «за кого он говорит». Одно не заменяет другого.

## Модель: одна личность модуля, включение и имя сервера — по ребру

Общая для всех рёбер пара «сертификат и ключ края» плюс общий корень доверия; на
каждом ребре — **своё** включение и **своё** ожидаемое имя сервера, что даёт
независимый откат по ребру.

**Семь рёбер** (по `backendEdge` на ревизии `96b2879a`): vpc · compute · iam · nlb ·
**geo** · **registry** · **storage**. Каждое накрывает пару ключей — публичный и
внутренний адрес домена. Прежняя редакция знала четыре: geo, registry и storage
появились позже и в таблицу не попали, то есть три ребра выглядели незащищаемыми.

Имена переменных строятся единообразно: включение mTLS и переопределение имени
сервера **на домен**, плюс общие сертификат, ключ и корень (полный перечень групп —
[[apigw-config]]; сами имена там намеренно не выписаны, они менялись).

Ключ, не попавший ни в одно ребро (например петля к самому себе для операций),
получает пустое имя ребра, и сборка учётных данных его **отвергает** — то есть
будущий дрейф карты падает громко, а не тихо уезжает в незащищённый набор.

## Exported / key funcs

- `config.EdgeTLSClient(edge, dialAddr) (grpcclient.TLSClient, error)` — собирает
  per-edge value-struct; **fail-fast** при enable без cert-материала (SEC-E-03);
  server-name = override или derive из dial-host.
- `backendEdge(backendKey) string` — backend-domain key → edge name.
- `buildBackendDialCreds(cfg) (map[key]grpc.DialOption, error)` — per-edge creds-map.
- `loopbackDialCreds() grpc.DialOption` — **всегда insecure** (operation self-loopback,
  in-process, не cross-pod — SEC-E-07).
- `iamEdgeDialCreds(cfg, addr)` — для двух standalone iam-dial (subject + authorize).
- `dialBackends(cfg) (proxy.Backends, cleanup, error)` — открывает ClientConn per-edge
  (+ keepalive 10s/3s + round-robin, сохранены) + opsLoopback insecure.

## Contract / invariants

- `enable=false` (default) ⇒ `insecure.NewCredentials()`, идентично pre-SEC-E (dev backward-compat).
- `enable=true` без cert/key/ca ⇒ ошибка → `log.Fatalf` в main (НЕ тихий insecure-fallback, epic §6.7).
- mTLS-client vs insecure-server / untrusted-CA ⇒ handshake fail → `Unavailable` (fail-closed, §3.9/§3.11).
- opsLoopback (`operation` domain) — никогда не mTLS.
- creds-слой ⊥ principal-metadata: `x-kacho-principal-*` пробрасывается director'ом поверх mTLS.

## Импортирует

- [[corelib-grpcclient]] — `TLSClient` + `TLSClientCreds` (единственный законный
  способ собрать учётные данные для межсервисного gRPC; прямая сборка мимо него
  ловится стражем);
- `gateway/internal/config` (сборка значения по ребру), `gateway/internal/proxy`
  (карта соединений).

> [!note] `enable=false` — фикстурный режим, а не эксплуатационный
> Нулевое значение даёт незашифрованное ребро. На развёрнутом стенде посадка всегда
> production (core §16), и boot-guard обязан отказать в старте на insecure-конфигурации.
> Именно этот путь маскирует всё, что здесь защищается.

## See also

[[../KAC/SEC-E-gateway-mtls]] [[../edges/api-gateway-to-iam-authorize]] [[../edges/api-gateway-to-iam-subject-change]] [[corelib-grpcclient]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-api-gateway #security #cmd #composition-root
