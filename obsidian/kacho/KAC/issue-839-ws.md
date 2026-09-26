---
title: "ws#839: ветка docfresh сведена в волну коммитом слияния"
aliases:
  - issue-839-ws
ticket_id: 839
category: kac
status: test
type: fix
repos:
  - kacho-workspace
areas:
  - .claude/agents
  - obsidian/kacho
  - .claude/hooks
  - .github/workflows
  - CLAUDE.md
  - scripts/change-graph-gate
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/840
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/839
opened: 2026-09-25
tags:
  - kac
  - fix
verified_against: "PRO-Robotech/kacho-workspace: голова задачи d5d6a650b5f — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# ws#839: ветка docfresh сведена в волну коммитом слияния

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:S`, `area:tooling`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-805-ws|#805]], волна — в ветку эпика `771` (координата, не живая ссылка) запросом PR #841; в `main` **не** доехала: закроет её посадка эпика #771 в ствол.

## Что и зачем

Ветка общей копии с работой docfresh (#784) сведена в волну 805 коммитом слияния; граница check-05 — слияние, где сошлись записи обеих линий.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `d5d6a650b5f` → слияние в ветку волны `805` `aa378730dcb` — «#839 сведение ветки общей копии в 805» |
| запрос задачи | PR #840 — отмечен влитым вместе со сборкой |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «Предикат» (перечислено как есть, мной не перемерялось):

- `git merge-base --is-ancestor ad26f2f5 origin/805` → 0;
- `git diff --quiet 13e0d0c1 2867f491` → 0: работа `13e0d0c1` вошла в `805` содержимым;
- коммитов с трейлерами атрибуции среди тех, которые вливание добавляет в `805`, — 0;
- наборы проверок оснастки зелёные на голове ветки этой задачи.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.

#kac #fix
