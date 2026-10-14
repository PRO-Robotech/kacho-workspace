---
title: "kacho#3129: посадка identity-own — запросы 1266→main и 296→main, вливание по зелёному CI"
aliases:
  - issue-3129
ticket_id: 3129
category: kac
status: done
type: feature
repos:
  - kacho
areas:
  - ci
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3158
  - https://github.com/PRO-Robotech/kaname/pull/714
issue_url: https://github.com/PRO-Robotech/kacho/issues/3129
opened: 2026-10-10
closed: 2026-10-14
tags:
  - kac
  - feature
verified_against: "kacho main@dd9739fe6dfe (коммит слияния PR #3158, родители bac26316c468 + 4c7ab49db8ab; предок origin/main — git merge-base --is-ancestor, код 0; ветки 1266 на origin нет — git ls-remote, 0 строк; 2026-10-14); состояние задачи и комментарии — gh issue view / gh api …/comments 2026-10-14; DoD — по комментарию DoD-proof задачи, проверки этой записью не перезапускались"
---

# kacho#3129: посадка identity-own — запросы 1266→main и 296→main, вливание по зелёному CI

**Status**: `done` — задача закрыта 2026-10-14 посадкой. **Type**: feature (шаг посадки).
**Родитель**: [[KAC/issue-1266]].

## Что и зачем

Работа своей личности жила в ветках эпиков: `1266` в kacho и `296` в kaname. В `main` она не
попадала. Задача — открыть запросы обоих эпиков в `main` и влить их по зелёному конвейеру и ✅
`landing-reviewer`. Порядок задаёт граф модулей: kaname вливается раньше kacho. Ветки эпиков
снимаются тем же заходом.

## PR и ревизия

- kacho: https://github.com/PRO-Robotech/kacho/pull/3158 (`1266` → `main`). Коммит слияния —
  `dd9739fe6dfed5195186cbb5ee71557aa63b49fe`, родители `bac26316c468` (main) и `4c7ab49db8ab` (голова).
- kaname: https://github.com/PRO-Robotech/kaname/pull/714 (`296` → `main`). Голова `278ac4c0835e`,
  коммит слияния `9ccdc8d86275`.

## DoD

Доказательство — комментарий DoD-proof: https://github.com/PRO-Robotech/kacho/issues/3129#issuecomment-6166229362.

- [x] Оба запроса влиты в `main` коммитом слияния. Дерево слияния kacho совпадает с деревом головы.
- [x] Обязательные контексты на голове kacho зелёные: 42 из 42. Вердикт `landing-reviewer` — ✅ на `4c7ab49d` / `278ac4c0`.
- [x] Ветки `1266` (kacho) и `296` (kaname) сняты на origin: `git ls-remote` даёт 0 строк.
- [x] Эпики закрыты каскадом: kaname#296, затем kacho#1266.
- [ ] Выкатки ревизии `main` на стенд этой задачей не было. Выкатка — отдельный шаг после посадки, его состояние — в [[KAC/issue-1266]].

## Затронутые сущности vault

Узких записок задача не меняет: перечня затронутых сущностей у неё нет.

## Связанные задачи

- [[KAC/issue-3127]], [[KAC/issue-3128]] — предусловия вливания
- [[KAC/issue-296-kaname]] — эпик службы, влит вторым запросом

## History

- 2026-10-14 — trail заведён при посадке эпика: статус `done`, PR #3158 и kaname#714, DoD-proof (#1266).

#kac #feature
