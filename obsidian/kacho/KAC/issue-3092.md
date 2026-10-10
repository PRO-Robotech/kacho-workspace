---
title: "kacho#3092: geo — публичная служба администрирования регионов и зон (ADM-1)"
aliases:
  - issue-3092
  - kacho#3092
ticket_id: 3092
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - proto/kacho/cloud/geo/v1
  - services/geo
  - gateway/internal/restmux
  - gateway/internal/allowlist
  - gateway/internal/middleware
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3104
issue_url: https://github.com/PRO-Robotech/kacho/issues/3092
opened: 2026-10-07
tags:
  - kac
  - feature
  - kacho-geo
  - kacho-api-gateway
verified_against: "kacho 1266@0ca889983ee4 (git fetch 2026-10-10); коммит слияния PR #3104 = ad74c3ea01b5 (gh pr view → MERGED 2026-10-08T17:01Z, тело — состав третьей сборки волны-6); состояние задачи — gh issue view / gh api …/comments 2026-10-10 (OPEN, status:test); proto RegionService/ZoneService — git show 0ca889983ee4:proto/kacho/cloud/geo/v1/{region,zone}_service.proto (Create/Update/Delete с путями REST); allowlist — git show …:gateway/internal/allowlist/list.go (строки RegionService/ZoneService Create/Update/Delete); прогоны этой записью не перезапускались"
---

# kacho#3092: geo — публичная служба администрирования регионов и зон (ADM-1)

> [!note] Состояние — `test`: код влит в ветку эпика, задача открыта и ждёт DoD
> Полоса вошла в третью сборку волны-6 — [kacho#3104](https://github.com/PRO-Robotech/kacho/pull/3104),
> коммит слияния `ad74c3ea01b5` в `1266` 2026-10-08 (`Refs`: пункты DoD «выкатка на стенд» и «trail» на тот
> момент не выполнены). Trail — эта записка.

## Что и зачем

Правка каталога регионов и зон была только у внутренней службы, то есть только на внутреннем слушателе:
системный администратор на посадке внешнего края не мог управлять каталогом ничем. Публичные
[[rpc/geo-region-service]] и [[rpc/geo-zone-service]] получили Create/Update/Delete с правом системного
администратора кластера; мутации возвращают Operation; методы внесены в каталог прав и allowlist края;
внутренние близнецы остаются только на внутреннем слушателе. Приёмка ADM-1 geo одобрена до кода (запись
ревью — комментарий задачи от 2026-10-07).

## Затронутые каталоги

`proto/kacho/cloud/geo/v1`, `services/geo`, `gateway/internal/{restmux,allowlist,middleware}`,
`services/geo/tests/newman` — PRO-Robotech/kacho.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] приёмка одобрена — [запись ревью](https://github.com/PRO-Robotech/kacho/issues/3092#issuecomment-6044116164);
- [x] DoD-proof полосы @`5a79c99f7fd5` — [комментарий](https://github.com/PRO-Robotech/kacho/issues/3092#issuecomment-6045936944): прогон в собственном пространстве стенда проб (со слов комментария);
- [x] код влит в ветку эпика `1266` — `ad74c3ea01b5` (kacho#3104);
- [x] trail — эта записка;
- [ ] выкатка на стенд и перемер DoD после неё — нет (комментарий задачи 2026-10-10);
- [ ] влито в `main` — нет.

## Затронутые сущности vault

- [[rpc/geo-region-service]] — публичные мутации (History #3092)
- [[rpc/geo-zone-service]] — публичные мутации (History #3092)
- [[packages/apigw-allowlist]] — строки geo (History #3092)

## Связанные задачи

- [[KAC/issue-3093]] — тот же образец для администраторов кластера
- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик

#kac #feature #kacho-geo #kacho-api-gateway
