---
title: "KAC-94: Skill evgeniy 100% эталон в kacho-vpc"
aliases:
  - KAC-94
ticket_id: KAC-94
category: kac
status: done
type: epic
repos:
  - kacho-vpc
  - kacho-deploy
  - kacho-compute
prs:
  - https://github.com/PRO-Robotech/kacho-vpc/pulls
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-94
tags:
  - kac
  - epic
  - done
  - kacho-vpc
  - evgeniy
---

# KAC-94: Skill `evgeniy` 100% эталон в kacho-vpc

**Status**: done
**Type**: epic
**Repos**: kacho-vpc, kacho-deploy, kacho-compute
**PRs**: PRO-Robotech/kacho-vpc#71–96 (18 PR'ов) + kacho-deploy#10–26 + kacho-compute#2,#20
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-94

## Что и зачем

Привести kacho-vpc к 100% соответствию skill `evgeniy` (48 архитектурных правил, основанных на ревью PR #52 от @EvgenyGRI/@pointpu). Затем распространить на каждый ресурс (8 public + 3 admin).

## Что закрыто (per правилу)

- **C.5** — закрытый sum-type `Transferrable` generic constraint
- **C.6** — `protoconv` → `dto/toproto`
- **D.1 / H.1** — `<X>Record` в repo-leaf, `CreatedAt` не в domain
- **D.10** — `Equal-методы на 8 domain-типов + 9 nested
- **E.2** — labels DB-CHECK constraints на 8 таблицах (миграция 0033;
  после KAC-111 — inline в baseline `0001_initial.sql`)
- **E.4** — schema rename `public` → `kacho_vpc` (миграция 0034; после
  KAC-111 — таблицы создаются сразу в `kacho_vpc`, без промежуточного rename)
- **E.5** — docs про CHECK constraints inline с CREATE TABLE (после
  KAC-111 — фактически inline во всём squashed baseline)
- **E.6** — ER diagram обновлён под `kacho_vpc` schema
- **G.1** — `internal/ports` → `internal/repo` + `ports.go` → `iface.go` в use-case пакетах
- **G.2–G.5** — CQRS Reader/Writer + Repository + explicit TX + outbox-in-TX
- **G.7** — `kachomock` на 8 ресурсов с TX-семантикой
- **I.4** — sync `folder.Exists` precheck убран (async-only)
- **I.6–I.10** — builders + enum + atomic compound writes + `CreateDefaultSGUseCase` extracted
- **K.3** — Dialect interface + cockroach scaffold
- **K.4 / K.5 / AP-7** — `parallel.ExecAbstract`
- **AP-11** — legacy `dto/toproto.Network()` удалён
- **A.2** — `pkg/sdk/vpc` Go SDK обёртка
- **A.7 / G.6** — удалены все 11 legacy `*_repo.go` + production CQRS-only
- **G.4** — slave-pool wiring (`kachopg.New(master, slave)`)
- **B.3 / I.1** — тривиальные `CreateInput` обёртки убраны
- **I.9-residual** — `CreateDefaultSGUseCase` в отдельный use-case

## Затронутые сущности vault

- [[../resources/vpc-network]] — atomic default-SG в одной writer-TX
- [[../resources/vpc-networkinterface]] — CQRS NIC use-cases
- [[../resources/vpc-addresspool]] — переезд `services/` → `apps/kacho/api/`
- [[../packages/vpc-domain]] — newtypes + Equal-методы + builders
- [[../packages/vpc-repo-kacho]] — CQRS Reader/Writer interface
- [[../packages/vpc-repo-kacho-pg]] — pgxpool-impl (master + slave)
- [[../packages/vpc-repo-kacho-kachomock]] — in-memory mock с TX-семантикой
- [[../packages/vpc-repo-helpers]] — SQL helpers extracted
- [[../packages/vpc-apps-kacho-api-network]] — CreateDefaultSGUseCase composition
- [[../packages/vpc-dto]] — закрытый Transferrable sum-type
- [[../edges/vpc-to-rm-folder-exists]] — sync precheck removed (только async)
- [[../rpc/vpc-network-service]] — sync `NotFound` → async через Operation
- [[../packages/proto-vpc]] — без изменений (proto stable)

## Связанные тикеты

- [[KAC-2]] — NetworkInterface first-class (предусловие)
- [[KAC-15]] — Geography moved (предусловие)
- [[KAC-50]] — api-gateway listener split (параллельно)
- [[KAC-52]] — NIC attach-race (включено в KAC-94 как I.10)
- [[KAC-71]] — AddressPool v4/v6 split (предусловие для KAC-94 addresspool migration)
- [[KAC-111]] — squash migrations 0001..0034 → 0001 (follow-up: свёрнуты
  все ALTER'ы Wave 2 / KAC-99 / KAC-89 / KAC-71 в один baseline `0001_initial.sql`)

## Финальный аудит

48 / 48 правил PASS (0 FAIL, 0 PARTIAL, 0 N/A).

#kac #epic #done #kacho-vpc #evgeniy
