---
title: "KAC-<N>: <one-line summary>"
aliases:
  - KAC-<N>
ticket_id: KAC-<N>
category: kac
status: in-progress
type: feature
repos:
  - kacho-vpc
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-<N>
opened: 2026-MM-DD
tags:
  - kac
---

# KAC-<N>: <one-line summary>

**Status**: in-progress | test | done | wontfix
**Type**: feature | fix | refactor | docs | epic
**Repos**: kacho-vpc, kacho-deploy
**PRs**: PRO-Robotech/kacho-vpc#<N>, ...
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-<N>

## Что и зачем

1-2 абзаца: проблема + решение.

## Затронутые сущности vault

- [[../resources/<X>]] — что изменилось
- [[../packages/<repo>-<pkg>]] — что добавлено/удалено
- [[../edges/<edge>]] — runtime изменения
- [[../rpc/<service>]] — RPC изменения

## Acceptance / Definition of Done

> [!important] Проставляй `[x]` сразу по факту выполнения пункта.
> Перед переводом `status: done` (в frontmatter и YouTrack) — пробеги по DoD и убедись, что все выполненные пункты отмечены. `status: done` + любой `[ ]` среди фактически сделанного — регрессия, vault-stop-check hook её ловит.

- [ ] integration tests зелёные
- [ ] newman E2E зелёный
- [ ] vault записи обновлены
- [ ] PR merged в main

## Связанные тикеты

- [[KAC-<N-prev>]] (предусловие)
- [[KAC-<N-next>]] (follow-up)

#kac
