---
title: "kacho#3093: край — публичная служба администраторов кластера, пин kaname и регистрация"
aliases:
  - issue-3093
  - kacho#3093
ticket_id: 3093
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - go.mod
  - gateway/internal/restmux
  - gateway/internal/allowlist
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3104
issue_url: https://github.com/PRO-Robotech/kacho/issues/3093
opened: 2026-10-07
tags:
  - kac
  - feature
  - kacho-api-gateway
  - kacho-iam
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10); коммит слияния PR #3104 = ad74c3ea01b5 (gh pr view → MERGED 2026-10-08T17:01Z, тело — состав третьей сборки волны-6); состояние задачи — gh issue view / gh api …/comments 2026-10-10 (OPEN, status:test); пин — git show 0ca889983ee4:go.mod (kaname v0.4.1-0.20261008024157-8b0379e2a9c5), внесён коммитом fcaae93ecd (git log -S); allowlist — git show …:gateway/internal/allowlist/list.go (четыре строки ClusterService); регистрация — git grep RegisterClusterServiceHandlerFromEndpoint gateway/internal/restmux/mux.go; kaname#661 — gh issue view 2026-10-10 (OPEN); прогоны этой записью не перезапускались"
---

# kacho#3093: край — публичная служба администраторов кластера, пин kaname и регистрация

> [!note] Состояние — `test`: код влит в ветку эпика, задача открыта, блокер открыт
> Полоса вошла в третью сборку волны-6 — [kacho#3104](https://github.com/PRO-Robotech/kacho/pull/3104),
> коммит слияния `ad74c3ea01b5` в `1266` 2026-10-08 (через полосу #3094; `Refs`). Метка `blocked` оставлена:
> [[KAC/issue-661-kaname]] открыта.

## Что и зачем

Публичный близнец администраторов кластера заводится в службе доступа ([[rpc/iam-cluster-service]]). Без
регистрации на внешнем крае и подъёма пина консоль на посадке внешнего края его не достигнет. Пин службы
поднят до `8b0379e2a9c5` (сборка 6b службы); четыре метода внесены в allowlist и зарегистрированы на внешнем
слушателе; внутренний близнец остаётся только на внутреннем слушателе.

## Затронутые каталоги

`go.mod` (пин kaname), `gateway/internal/{restmux,allowlist}` — PRO-Robotech/kacho.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] код влит в ветку эпика `1266` — `ad74c3ea01b5` (kacho#3104);
- [ ] DoD-proof (newman на внешнем крае) — нет;
- [ ] блокер [[KAC/issue-661-kaname]] — открыт;
- [ ] влито в `main` — нет.

## Затронутые сущности vault

- [[rpc/iam-cluster-service]] — регистрация на крае (History #3093)
- [[packages/apigw-allowlist]] — строки ClusterService (History #3093)
- [[edges/kacho-to-kaname-module-pin]] — пин 8b0379e2 (History #3093)

## Связанные задачи

- [[KAC/issue-661-kaname]] — сторона службы
- [[KAC/issue-3092]] — тот же образец для geo
- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик

#kac #feature #kacho-api-gateway #kacho-iam
