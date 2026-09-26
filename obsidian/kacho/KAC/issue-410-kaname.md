---
title: "kaname#410: адаптеры церемонии на фундаменте corelib v1.10.0-rc.2"
aliases:
  - issue-410-kaname
ticket_id: 410
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - internal/ceremonyport
  - internal/passwordverify
  - THIRD-PARTY-NOTICES.md
  - go.mod
  - go.sum
  - internal/check
prs:
  - https://github.com/PRO-Robotech/kaname/pull/413
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/410
opened: 2026-09-24
closed: 2026-09-26
tags:
  - kac
  - refactor
  - kacho-iam
verified_against: "PRO-Robotech/kaname: голова задачи da385b2e7e1 — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:39:15Z, меток status:* нет (`gh issue view`); коммит слияния волны fc9f5aff19c — в origin/357, не в origin/main (`gh api compare`)"
---

# kaname#410: адаптеры церемонии на фундаменте corelib v1.10.0-rc.2

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:39:15Z вместе с волной [[KAC/issue-358-kaname|#358]]: запрос волны PR #422 влит в ветку эпика `357` (координата, не живая ссылка), коммит закрытия — слияние волны `fc9f5aff19c`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:iam`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #357 в ствол.

## Что и зачем

Служба доступа переведена на corelib v1.10.0-rc.2: поля гранта и порт сверки секрета клиента, которые фундамент отдал службе в волне [[KAC/issue-32-corelib|corelib#32]].

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `da385b2e7e1` → слияние в ветку сборки `412` `ce43d3fb88a` — «#412 merge #410: адаптеры церемонии на фундаменте v1.10.0-rc.2» |
| запрос сборки | PR #413 `412` → `358`, голова `5dfe66b58df`, коммит слияния `f4c6537ac4a`; прогоны головы — 6 прогонов, все `success` |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- падающая проба ДО кода, у отказа — положительный близнец;
- предикат снятия выполнен, вывод — комментарием при сдаче.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `fc9f5aff19c` в ветку эпика `357`;
- [ ] предмет в стволе: `main` — посадкой эпика #357.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: пакеты internal/ceremonyport, internal/passwordverify, гейт internal/check (login_verifier_containment); ребро kaname → corelib v1.10.0-rc.2.

- [[KAC/issue-358-kaname]] — волна.
- [[packages/corelib-oauthceremony]]
- [[KAC/issue-32-corelib]]

#kac #refactor #kacho-iam
