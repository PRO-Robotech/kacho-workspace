---
title: "ws#850: values.prod требуют подъёма, конвейер поднимает dev-prod"
aliases:
  - issue-850-ws
ticket_id: 850
category: kac
status: in-progress
type: fix
repos:
  - kacho-workspace
areas:
  - .claude/rules/security.md
  - .claude/rules/00-kacho-core.md
  - .claude/agents/dispatcher.md
prs: []
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/850
opened: 2026-09-26
tags:
  - kac
  - fix
  - conventions
verified_against: "PRO-Robotech/kacho-workspace: трекер — задача открыта, родителя нет (`gh issue view 850`, `gh api .../parent` → 404), PR с номером нет, 2026-09-26. Маркеры sec-values-prod-must-boot в security.md и ban16-values-prod в 00-kacho-core.md есть на origin/main 6eddaa5e9c и называют держателя так, как сказано в теле задачи (`git show | grep`); место в dispatcher.md и задания конвейера продукта — из тела задачи, мной не перемерялись; 2026-09-28 (#846): состояние, метки и родитель — трекер (`gh issue view 850 -R PRO-Robotech/kacho-workspace`, `gh api .../parent`), вливания — `gh pr view` либо лог ветки волны; DoD не перемерялся"
---

# ws#850: values.prod требуют подъёма, конвейер поднимает dev-prod

**Состояние на момент записи**: `to-do` — 2026-09-26. Задача **открыта**, метки: `bug`, `P2`,
`size:S`, `area:rules`, `release:gates`; родителя нет. Заведена 2026-09-26T11:44:04Z по итогам
сверки выкатки линии эпика kacho `2564` (координата, не живая ссылка). Роль —
`tooling-maintainer`. Работы по ней нет.

**Состояние на 2026-09-28**: `in-progress`. Задача открыта, метка `status:in-progress`; родителя нет. Взята 2026-09-27T18:09Z веткой `issue-714` (координата, не живая ссылка), релиз `release:gates` (комментарий задачи).

## Что и зачем

**Признак.** Три места корпуса требуют подъёма именно `values.prod` (замер тела задачи @
`origin/main` `6eddaa5e9c`): `.claude/rules/security.md` `sec-values-prod-must-boot` — держателем
назван `.github/workflows/production-posture.yml` продукта; `.claude/rules/00-kacho-core.md`
`ban16-values-prod` — держатель «КАНДИДАТ НА ГЕЙТ»; `.claude/agents/dispatcher.md:250` — выкатка
принимается только с исходом `helm-install` + `rollout-ready` на `values.prod`.

Конвейер продукта (`origin/main` @ `1d42a672` и `2564` @ `7190c3e527`) поднимает другое:
`production-posture.yml` зовёт `make dev-prod-up` — цепочку `dev-prod`, а `console-e2e.yml` и
`e2e-newman.yml` — `make dev-up`. Цепочки с `values.prod.yaml` (`prod`, `own` и стенд на них,
по `deploy/stacks.txt`) не поднимает ни одно задание. Сверка выкатки 2026-09-26 посылку «на
`values.prod`» опровергла: стенд поднят цепочкой на `values.dev-prod`, и CI гоняет её же.
Правило держатель называет, а тот держит другую цепочку.

**Предмет.** Правило и конвейер называют одну и ту же цепочку. Два исхода, выбор с доводом — в
задаче:

- (а) конвейер поднимает цепочку с `values.prod` (`prod` или `own`) — правка в
  PRO-Robotech/kacho, правило остаётся;
- (б) правило называет боевой цепочку `dev-prod` и говорит, почему `values.prod` не поднимается в
  kind и что судит сам `values.prod` (рендер, стражи старта); держатель назван верно во всех трёх
  местах.

## DoD

Из тела задачи, раздел «ПРЕДИКАТ» (перечислено как есть):

1. цепочка, которую называют `security.md` `sec-values-prod-must-boot`, `00-kacho-core.md`
   `ban16-values-prod` и `dispatcher.md:250`, совпадает с цепочкой, которую поднимает названный
   держатель: `git grep` правила и `grep make` по `production-posture.yml` дают одно имя;
2. при исходе (а): задание конвейера на голове PR поднимает цепочку с `values.prod` и выходит с
   кодом 0; ссылка на прогон;
3. колонка держателя у `ban16-values-prod` либо называет механизм, либо остаётся «КАНДИДАТ» с
   названной причиной.

Артефакт — PR с `Closes` этой задачи; при исходе (а) — ещё и PR продукта и ссылка на прогон.

## History

- 2026-09-28 (#846) — состояние приведено к трекеру: to-do → in-progress: задача взята в работу 2026-09-27.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — таблица цепочек `deploy/stacks.txt`; какие из них
  поднимает конвейер, записка не утверждает.

#kac #fix #conventions
