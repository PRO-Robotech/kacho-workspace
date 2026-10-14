---
title: "ws#896: эпик своей личности — приёмка экранов консоли S3 и S4"
aliases:
  - issue-896-ws
ticket_id: 896
category: kac
status: done
type: epic
repos:
  - kacho-workspace
areas:
  - docs/specs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3158
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/896
opened: 2026-10-01
closed: 2026-10-14
tags:
  - kac
  - epic
verified_against: "kacho-workspace: задача CLOSED completed 2026-10-14, комментарии DoD-proof и закрытия — gh api …/issues/896/comments 2026-10-14; родитель kacho#1266 закрыт, его коммит слияния dd9739fe6dfe — предок kacho origin/main (git merge-base --is-ancestor, код 0); содержимое приёмок этой записью не перечитывалось"
---

# ws#896: эпик своей личности — приёмка экранов консоли S3 и S4

**Status**: `done` — эпик закрыт 2026-10-14 каскадом посадки родителя [[KAC/issue-1266]] в `main` kacho.
**Type**: epic. **Родитель**: [[KAC/issue-1266]].

## Что и зачем

В одобренной F8 нет двух экранов консоли: восстановления доступа (S3) и входа ключом доступа (S4).
Эпик даёт им приёмку до первой строки кода: сценарии Given-When-Then, близнецы и предикат старта
числом. Приёмка консоли живёт в `docs/specs` воркспейса. Это часть релиза своей личности
[[KAC/issue-1266]]: приёмка — вход для экранов S4 (волна-6) и S3 (волна-7) платформы.

## PR и ревизия

- Посадка родителя: https://github.com/PRO-Robotech/kacho/pull/3158, коммит слияния `dd9739fe6dfe`.
- Доказательство эпика снято на `bce29437ca9b` (origin/main воркспейса).

## DoD

- [x] Волна эпика ws#897 закрыта 2026-10-12. Закрыты все подзадачи эпика: 9 из 9 (`gh api …/issues/896/sub_issues`). Ход одобрения приёмок — в комментариях задачи.
- [x] Родитель влит в `main`, эпик закрыт тем же заходом каскада. Доказательство — https://github.com/PRO-Robotech/kacho-workspace/issues/896#issuecomment-6162277661, закрытие — https://github.com/PRO-Robotech/kacho-workspace/issues/896#issuecomment-6166228461.

## Затронутые сущности vault

Узких записок задача не меняет: перечня затронутых сущностей у неё нет.

## Связанные задачи

- [[KAC/issue-1266]] — родитель, релиз своей личности

## History

- 2026-10-14 — trail заведён при закрытии эпика: статус `done`, DoD-proof (#1266).

#kac #epic
