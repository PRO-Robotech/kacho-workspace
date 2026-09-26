---
title: "ws#773: приёмка F8 — свои экраны церемоний личности в консоли"
aliases:
  - issue-773-ws
ticket_id: 773
category: kac
status: test
type: docs
repos:
  - kacho-workspace
areas:
  - docs/specs
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/773
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace: голова задачи 28699f217e5 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:33:56Z, меток status:* нет (`gh issue view`); коммит слияния волны 27eb0775252 — в origin/771, не в origin/main (`gh api compare`)"
---

# ws#773: приёмка F8 — свои экраны церемоний личности в консоли

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:33:56Z вместе с волной [[KAC/issue-805-ws|#805]]: запрос волны PR #841 влит в ветку эпика `771` (координата, не живая ссылка), коммит закрытия — слияние волны `27eb0775252`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:vault`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #771 в ствол.

## Что и зачем

Приёмка под-фазы F8: консоль рисует свои экраны церемоний личности. Документ `docs/specs/sub-phase-F8-console-identity-ceremony-screens-acceptance.md` и записи кругов ревью; реализацию несёт [[KAC/issue-1274|kacho#1274]].

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `28699f217e5` → слияние в ветку волны `805` `a8ffa48c9fd` — «#805 merge #773: приёмка F8 — свои экраны входа» |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «DoD · каталоги · артефакт» (перечислено как есть, мной не перемерялось):

- **DoD:** вердикт APPROVED привязан к отпечатку документа в ветке задачи.
- **Каталоги:** `docs/specs/` и `docs/specs/reviews/sub-phase-F8-console-identity-ceremony-screens-acceptance/`.
- **Артефакт:** коммит документа и записи круга 4 в ветке задачи. Ветка вливается в ветку волны `772` через `git merge --no-ff`.

Сверено мной:

- [ ] в ветке эпика `771` лежит редакция 6 приёмки: `git show origin/771:docs/specs/sub-phase-F8-console-identity-ceremony-screens-acceptance.md | sha256sum` → `6c64f565…fd7`. Переутверждённая после неё редакция 8 (`8704b3d1…a526`, APPROVED круг C18-2) — на ветке `acc-f8` @ `a9952dae` (координата, не живая ссылка), и этот коммит не предок `origin/771` (`git merge-base --is-ancestor`, код 1). По комментарию [[KAC/issue-1274|kacho#1274]] от 2026-09-24 код консоли и края пишется по редакции 8;
- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.
- [[KAC/issue-1274]]

#kac #docs
