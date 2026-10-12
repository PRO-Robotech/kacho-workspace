---
title: "kacho#2886: отпечаток доставки манифестов не попадает в контекст сборки образов"
aliases:
  - issue-2886
ticket_id: 2886
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy/helm/umbrella
  - .dockerignore
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3016
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/2886
opened: 2026-09-27
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
verified_against: "kacho 1266@9b14ae7f01c (коммит слияния PR #3016, родители 656955b66b7 + be1d233cc8c; голова origin/1266 = этот коммит, 2026-10-04): состав — git log 656955b66b7..9b14ae7f01c --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям-доказательствам задачи; пробы и конвейер этой записью не перезапускались; 2026-10-06 — закрытие волной-4: kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb, git ls-remote), состояние — gh issue view, DoD — комментарий DoD-proof задачи; пробы этой записью не перезапускались"
---

# kacho#2886: отпечаток доставки манифестов не попадает в контекст сборки образов

> [!note] Состояние — `test`: задача ЗАКРЫТА 2026-10-06 вливанием волны-4 в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)). Врезка ниже — состояние
> на 2026-10-04, история.

> [!warning] Состояние — `in-progress`: задача ОТКРЫТА, перенесена из волны-2 в волну-3
> Волна [[KAC/issue-2965]] влита в `1266` запросом [kacho#3016](https://github.com/PRO-Robotech/kacho/pull/3016) (`9b14ae7f01c`); задача стоит в нём строкой `Refs`
> и перенесена открытой в волну-3 [[KAC/issue-2966]] (sub-issue #2966, 2026-10-04).

## Что и зачем

Признак — файл отпечатка доставки манифестов модулей ехал в контекст сборки образов. Перемер
посылки на сборке волны: предмет уже выполнен коммитом `4c4344b1e25` (#2846, в `1266`) — строка файла
стоит в `.dockerignore`. Проба `TestBuildContextCarriesNothingOurPipelinesWrite` (`internal/repohygiene`)
зелёная при лежащем файле, близнец без строки в `.dockerignore` — красный (комментарий задачи 2026-10-03).

Коммитов по задаче в сборке волны-2 нет, закрыть её запросом волны-2 было нечем — перенесена. Решение
2026-10-04: предикат `repohygiene` доказывается локально в составе волны-3.

## Как доехало

Предмет — `4c4344b1e25` (#2846), предок `origin/1266`.

## Волна-4 — закрыта (2026-10-06)

[DoD-proof @680d1794](https://github.com/PRO-Robotech/kacho/issues/2886#issuecomment-6012642838):
`go test -count=1 -v ./internal/repohygiene/ -run TestBuildContextCarriesNothingOurPipelinesWrite` → код 0,
PASS 1; правка `4c4344b1e25` — предок `origin/1266`. Коммитов волны-4 по задаче нет.

## Затронутые каталоги

`.dockerignore`, `internal/repohygiene`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] предикат и близнец измерены на сборке волны-2 — комментарий задачи 2026-10-03;
- [x] закрытие с артефактом — DoD-proof @680d1794, волна-4 [[KAC/issue-2967]] (волной-3 не закрыта);
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4, закрыла
- [[KAC/issue-2966]] — волна-3
- [[KAC/issue-2965]] — волна-2

#kac #kacho-deploy
