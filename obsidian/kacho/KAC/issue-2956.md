---
title: "kacho#2956: край: отказы /oauth/logout не в форме google.rpc.Status"
aliases:
  - issue-2956
  - kacho#2956
ticket_id: 2956
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/handler
  - gateway/docs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/2956
opened: 2026-10-01
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2956: край: отказы /oauth/logout не в форме google.rpc.Status

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Отказы `/oauth/logout` отдаются в форме `google.rpc.Status`, как прочие отказы края; обзор API края называет эту форму.

## Затронутые каталоги

`gateway/internal/handler`, `gateway/docs` (PRO-Robotech/kacho).

Коммиты в составе волны: `7112c2087be`, `610eb0911a6`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2956#issuecomment-6012630805): `go test -count=1 -v ./gateway/internal/handler/ -run TestLogout_2956_524` → код 0, PASS 1 (тела отказов `/oauth/logout` — google.rpc.Status, проба утверждает их дословно); обзор API называет форму ответов края (`gateway/docs/content/api/overview.mdx`). Конвейер: юниты gateway docs-sites — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4
- [[KAC/issue-2996]]
- [[KAC/issue-2959]]

#kac #kacho-api-gateway
