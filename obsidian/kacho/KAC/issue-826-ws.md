---
title: "ws#826: правила: край проверяет newman чёрным ящиком"
aliases:
  - issue-826-ws
ticket_id: 826
category: kac
status: test
type: docs
repos:
  - kacho-workspace
areas:
  - .claude/agents
  - .claude/rules
  - .claude/backup
  - .claude/skills
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/828
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/826
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace: голова задачи cada5aad0b5 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:34:36Z, меток status:* нет (`gh issue view`); коммит слияния волны 27eb0775252 — в origin/771, не в origin/main (`gh api compare`)"
---

# ws#826: правила: край проверяет newman чёрным ящиком

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:34:36Z вместе с волной [[KAC/issue-805-ws|#805]]: запрос волны PR #841 влит в ветку эпика `771` (координата, не живая ссылка), коммит закрытия — слияние волны `27eb0775252`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:rules`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #771 в ствол.

## Что и зачем

Свод опыта QA и флоу: край проверяется набором newman как чёрный ящик. Правила и агенты оснастки дополнены классами и порядком работы.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `cada5aad0b5` → слияние в ветку волны `805` `80221e24fe6` — «#826 слияние в волну 805: край проверяет newman чёрным ящиком» |
| запрос задачи | PR #828 — отмечен влитым вместе со сборкой |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ» (перечислено как есть, мной не перемерялось):

- правило в корпусе закреплено за тестировщиками (`qa-test-engineer`, `integration-tester`) и посадочным (`landing-reviewer`): строка `MANIFEST.md` называет их, скил-ссылка есть в `skills:` каждого;
- `dispatcher.md` назначает newman на каждое изменение, видимое через край; HTTP-пути края приравнены к «новому RPC» `testing.md:38`;
- гейты оснастки зелёные: `scripts/rules-gate/run-all.sh`, `scripts/skills-gate/run-all.sh`, `scripts/tooling-gate/run-all.sh` — код 0, число исполненных проверок в выводе.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.

#kac #docs
