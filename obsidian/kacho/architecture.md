---
title: "Архитектура — cross-repo граф"
aliases:
  - architecture
category: hub
tags:
  - architecture
  - dependencies
  - polyrepo
---

# Архитектура — cross-repo граф

## Build-зависимости (Go-replace + Dockerfile COPY)

```mermaid
graph TD
    proto[kacho-proto<br/>«центр всех .proto»]
    corelib[kacho-corelib<br/>ids/operations/db/outbox/...]
    rm[kacho-resource-manager]
    vpc[kacho-vpc]
    compute[kacho-compute]
    nlb[kacho-loadbalancer]
    apigw[kacho-api-gateway]
    deploy[kacho-deploy]
    ui[kacho-ui]
    test[kacho-test]

    proto --> corelib
    corelib --> rm
    corelib --> vpc
    corelib --> compute
    corelib --> nlb
    corelib --> apigw
    proto --> rm
    proto --> vpc
    proto --> compute
    proto --> nlb
    proto --> apigw

    rm --> deploy
    vpc --> deploy
    compute --> deploy
    apigw --> deploy
    ui --> deploy

    deploy -.runtime.- apigw
    apigw -.runtime.- ui
    test -.runtime.- apigw
```

Источник истины — `replace github.com/PRO-Robotech/...` в `*/go.mod` + `COPY ../kacho-*` в `*/Dockerfile`.

## Runtime cross-domain edges (gRPC service → service)

```mermaid
graph LR
    apigw[api-gateway:8080] --> vpc[vpc:9090/9091]
    apigw --> compute[compute:9090/9091]
    apigw --> rm[resource-manager:9090]

    vpc -.zone_id validate.-> compute
    vpc -.folder check.-> rm
    compute -.NIC validate.-> vpc
    compute -.folder check.-> rm

    vpcimpl[vpc-implement] -.ReportNiDataplane.-> vpc
```

Циклы запрещены (workspace `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы»).

## Порядок merge'а для cross-repo фичи

Топологическая сортировка build-графа:
1. `kacho-proto` — proto changes + регенерация Go-stubs (commit `gen/`).
2. `kacho-corelib` — общие пакеты (если меняются).
3. Сервисы (`kacho-vpc` / `kacho-rm` / `kacho-compute` / `kacho-nlb`) — в любом порядке между собой (DB-per-service).
4. `kacho-api-gateway` — регистрация новых RPC.
5. `kacho-deploy` — helm/compose tweaks.

Пока вышестоящие изменения не в `main` — нижестоящий CI **временно пиннит siblings** к feature-веткам (`ref:`-строки в `.github/workflows/ci.yaml`).

## Tracking кросс-репо эпика

Через [[../docs/specs/|spec docs]] + tracking-issue в `PRO-Robotech/kacho-workspace` (метка `epic`). Per-repo issue/PR помечает `Blocked by PRO-Robotech/<repo>#<n>`.

## См. также

- [[README|hub]]
- [[kacho-vpc/README]] — most active service
- [[kacho-deploy/README]] — orchestration

#architecture #dependencies #polyrepo
