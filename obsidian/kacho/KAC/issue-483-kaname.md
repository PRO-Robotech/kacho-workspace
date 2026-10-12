---
title: "kaname#483: сборка 1 волны-4 — одиннадцать слияний полос под один прогон"
aliases:
  - issue-483-kaname
ticket_id: 483
category: kac
status: done
type: refactor
repos:
  - kaname
areas:
  - cmd/kaname
  - internal/apps
  - internal/handler
  - internal/service
  - internal/repo
  - internal/migrations
  - internal/check
  - internal/clients
  - tools/declaredbreak
  - proto
  - pkg/api
  - deploy
  - docs
  - tests/newman
  - .github
prs:
  - https://github.com/PRO-Robotech/kaname/pull/485
  - https://github.com/PRO-Robotech/kaname/pull/492
issue_url: https://github.com/PRO-Robotech/kaname/issues/483
opened: 2026-09-29
closed: "2026-09-30"
tags:
  - kac
  - kacho-iam
  - iam
  - go
verified_against: "kaname 357@73dc6598c (дерево 5bdd770f6, 2026-09-30): предикаты DoD, заданные командой git grep / ls-tree, прогнаны по этой ревизии; состав коммитов и путей — git log/show по диапазону 734f69fb4..4ae67c59e; пробы и конвейер не перезапускались"
---

# kaname#483: сборка 1 волны-4 — одиннадцать слияний полос под один прогон

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-09-30 при вливании своего запроса в ветку волны `367`. Волна влита в
> ветку эпика `357` коммитом слияния `73dc6598c1a38321cdee20731cb5547cd4a158c3`
> ([kaname#492](https://github.com/PRO-Robotech/kaname/pull/492)); в `main` службы код не влит — запрос эпика
> [kaname#359](https://github.com/PRO-Robotech/kaname/pull/359) открыт черновиком (замер 2026-09-30), поэтому состояние
> записки `test`.

**Состояние на 2026-10-03**: `done`, работа в `main`. Задача закрыта на трекере 2026-09-30 (`completed`); эпик kaname#357 влит в `main` запросом kaname#359 2026-10-02 коммитом слияния `8cbc0fdc82c` — предок `origin/main` (`git merge-base --is-ancestor`, 2026-10-03); зонтичный эпик kacho#2564 закрыт 2026-10-03 — [[KAC/issue-2564|#2564]].

## Что и зачем

Сборка 1 волны-4 [[KAC/issue-367-kaname]] сводит полосы под один прогон конвейера. Полосы вливаются в ветку сборки локальными коммитами слияния `--no-ff`, сборка — в ветку волны. Задача сборки закрыта при вливании своего запроса, а не каскадом.

Полосы: [[KAC/issue-368-kaname]], [[KAC/issue-364-kaname]] (с kaname#375), [[KAC/issue-323-kaname]], [[KAC/issue-471-kaname]], [[KAC/issue-474-kaname]], [[KAC/issue-328-kaname]] (несёт [[KAC/issue-329-kaname]] и [[KAC/issue-362-kaname]]), [[KAC/issue-259-kaname]], [[KAC/issue-338-kaname]], [[KAC/issue-480-kaname]] (двумя слияниями), [[KAC/issue-361-kaname]].

Собственные правки сборки: ведомость kaname#323 приведена к сведённому дереву и подъём на 42 отозван (`97a7a8c32`, `49c38e18c`, `1d64cdae8`, `8ce3c1f9c`); возврат ревью по kaname#361 (`86eb67120`). Три конфликта содержимого сведены в коммите слияния `6a3faceda`.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| сборка → волна | ветка `483` → ветка `367` | 86eb67120 | d5e515e04 | [kaname#485](https://github.com/PRO-Robotech/kaname/pull/485) |
| волна → эпик | ветка `367` → ветка `357` | 4ae67c59e | 73dc6598c | [kaname#492](https://github.com/PRO-Robotech/kaname/pull/492) |

## Затронутые каталоги

Каталоги по телу задачи: `cmd/kaname`, `internal/apps`, `internal/handler`, `internal/service`, `internal/repo`, `internal/migrations`, `internal/check`, `internal/clients`, `tools/declaredbreak`, `proto`, `pkg/api`, `deploy`, `docs`, `tests/newman`, `.github`.

## DoD

Отметка `[x]` — измерено этой записью на `73dc6598c` (дерево `5bdd770f6`, то же у головы волны `4ae67c59e`) либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено либо не выполнено, причина в строке.

- [x] коммит слияния сборки `d5e515e04` — два родителя (`git log -1 --format=%P`), его дерево `51c83964f` равно дереву головы сборки `86eb67120` (`git rev-parse <sha>^{tree}`) — перемерено этой записью.
- [x] голова сборки `86eb67120` и коммит слияния `d5e515e04` — предки `73dc6598c` (`git merge-base --is-ancestor`, код 0 — перемерено); головы полос — предки, со слов тела kaname#492.
- [x] ветки полос и сборки на origin сняты: `git ls-remote origin 'refs/heads/*'` 2026-09-30 не даёт ни одной ветки полос и сборок волны-4 (из номерных есть `357` и `2721`).

## Затронутые сущности vault

Пробел, названный как пробел: возвраты полос волны-4 поля «затронуто в vault» не несут (журналы исполнителей, строки `result`; где поле есть — стоит «—»). Узкие записки `resources/` · `rpc/` · `packages/` · `edges/` по этой задаче не заведены и не правлены: без данных полосы предмет не выдумывается. Почему узкие записки о снятом не правятся и сейчас — раздел «Узкие записки» в [[KAC/issue-367-kaname]].

## Связанные задачи

- [[KAC/issue-367-kaname]] — волна-4

#kac #kacho-iam #iam #go
