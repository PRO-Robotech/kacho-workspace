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

**Status**: in-progress | test | done | wontfix | superseded | reference
**Type**: feature | fix | refactor | docs | epic

> [!note] Какой статус выбирать, чтобы вид `KAC/all-tickets.base` не солгал
> Вид «Active» показывает всё, что **не** `done`/`wontfix`/`superseded`/`reference` —
> то есть неверно выбранный статус читается как «по этому кто-то работает».
> - `done` — работа доехала (проверяется по дереву продукта, а не по списку пунктов);
> - `wontfix` — отказались, с обоснованием;
> - `superseded` — предмет поглощён другой работой или снят с продукта решением;
> - `reference` — отчёт раунда / методика: единицей работы никогда не была, закрывать нечего.
>
> Заводя новый статус — впиши его в `all-tickets.base` в **оба** места (формулу значка и
> фильтр «Active»), иначе вид перестанет отличать закрытое от открытого.
**Repos**: kacho-vpc, kacho-deploy
**PRs**: PRO-Robotech/kacho-vpc#<N>, ...
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-<N>

## Что и зачем

1-2 абзаца: проблема + решение.

## Затронутые сущности vault

- `[[resources/<X>]]` — что изменилось
- `[[packages/<repo>-<pkg>]]` — что добавлено/удалено
- `[[edges/<edge>]]` — runtime изменения
- `[[rpc/<service>]]` — RPC изменения

## Acceptance / Definition of Done

> [!important] Проставляй `[x]` сразу по факту выполнения пункта.
> Перед переводом `status: done` (в frontmatter и YouTrack) — пробеги по DoD и убедись, что все выполненные пункты отмечены. `status: done` + любой `[ ]` среди фактически сделанного — регрессия, vault-stop-check hook её ловит.

- [ ] integration tests зелёные
- [ ] newman E2E зелёный
- [ ] vault записи обновлены
- [ ] PR merged в main

## Связанные тикеты

- `[[KAC-<N-prev>]]` (предусловие)
- `[[KAC-<N-next>]]` (follow-up)

#kac
