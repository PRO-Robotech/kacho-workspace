---
title: "ws#832: флоу v2: код первым, агрегаты, память не выше 45 ГБ"
aliases:
  - issue-832-ws
ticket_id: 832
category: kac
status: test
type: feature
repos:
  - kacho-workspace
areas:
  - .claude/agents
  - .claude/rules
  - scripts
  - .claude/backup
  - .claude/hooks
  - CLAUDE.md
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/834
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/832
opened: 2026-09-24
tags:
  - kac
  - feature
verified_against: "PRO-Robotech/kacho-workspace: голова задачи 847bee447d0 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# ws#832: флоу v2: код первым, агрегаты, память не выше 45 ГБ

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:L`, `area:tooling`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-805-ws|#805]], волна — в ветку эпика `771` (координата, не живая ссылка) запросом PR #841; в `main` **не** доехала: закроет её посадка эпика #771 в ствол.

## Что и зачем

Флоу v2: приоритет кода, агрегаты задач, слот памяти для тяжёлых прогонов и страж PreToolUse, держащий потолок 45 ГБ.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `847bee447d0` → слияние в ветку волны `805` `fb7a2cbbb7c` — «#832 флоу v2: код первым, агрегаты, память» |
| запрос задачи | PR #834 — отмечен влитым вместе со сборкой |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ» (перечислено как есть, мной не перемерялось):

- слот тяжёлых прогонов в дереве с пробой и стражем;
- каждый пункт — строка-норма у исполняющего агента;
- `dispatcher.md` — маршруты агрегата;
- гейты оснастки зелёные: `scripts/rules-gate/run-all.sh`, `scripts/skills-gate/run-all.sh`, `scripts/tooling-gate/run-all.sh` — код 0, число исполненных проверок в выводе.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.

#kac #feature
