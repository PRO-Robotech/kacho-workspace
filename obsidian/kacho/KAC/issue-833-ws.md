---
title: "ws#833: trail сборок волны kacho#2796 — задачи со статусом test"
aliases:
  - issue-833-ws
ticket_id: 833
category: kac
status: test
type: docs
repos:
  - kacho-workspace
areas:
  - obsidian/kacho
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/836
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/833
opened: 2026-09-24
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace: голова задачи a8d59e0e194 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# ws#833: trail сборок волны kacho#2796 — задачи со статусом test

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P2`, `size:S`, `area:vault`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-805-ws|#805]], волна — в ветку эпика `771` (координата, не живая ссылка) запросом PR #841; в `main` **не** доехала: закроет её посадка эпика #771 в ствол.

## Что и зачем

Trail хранилища по сборкам волны [[KAC/issue-2796|kacho#2796]] и волн kaname 358 и 377: записки по влитым задачам в состоянии `test`.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `a8d59e0e194` → слияние в ветку сборки `835` `cea875ca0ab` — «#835 merge #833: trail сборок волны kacho#2796» |
| запрос сборки | PR #836 `835` → `805`, голова `2345ef6cd86`, коммит слияния `f46878626e8`; прогоны головы — 1 прогон, `success` |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- по каждой задаче влитой сборки есть записка `KAC/issue-<N>.md` с состоянием `test`, ссылкой на PR сборки и головами задач;
- `./scripts/vault-gate/run-all.sh` даёт код 0, указатель `INDEX-notes.md` регенерирован, дельта только машинная.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.
- [[KAC/issue-2796]]
- [[KAC/issue-358-kaname]]

#kac #docs
