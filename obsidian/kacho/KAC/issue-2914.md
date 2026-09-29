---
title: "#2914: сервис уведомлений — единый почтовый шлюз"
aliases:
  - issue-2914
  - NTF
ticket_id: 2914
category: kac
status: in-progress
type: epic
repos:
  - kacho
  - kacho-workspace
  - corelib
  - kaname
areas:
  - services/notify
  - docs/specs
  - deploy
prs: []
issue_url: https://github.com/PRO-Robotech/kacho/issues/2914
opened: 2026-09-29
tags:
  - kac
  - epic
---

# #2914: сервис уведомлений — единый почтовый шлюз

**Type**: epic · **Роль исполнителя первой задачи**: acceptance-author / tooling-maintainer

**Состояние на момент записи**: in-progress — идёт пакет документов
(PRO-Robotech/kacho-workspace#880, ветка воркспейса `issue-880` — координата, не ссылка);
остальные задачи открыты с меткой `blocked` до APPROVED приёмки своей под-фазы.

**Чем сверено**: `gh issue view` по эпику и каждой задаче таблицы ниже (2026-09-30).

## Что и зачем

Цель эпика — одна служба платформы (`services/notify` в kacho) держит доступ к почте; прочие
модули и kaname ставят нотификацию в свою ленту и почтовых кредов не знают. Требования владельца
(дословно) и одиннадцать решений — в теле эпика; здесь не пересказываются, чтобы два места об
одном предмете не разошлись.

Порядок по графу зависимостей (из эпика): DOCS → (corelib → kaname) ∥ NS ∥ notify → NTF-2,
NTF-3 → NTF-4.

## Задачи

| предмет | задача | состояние 2026-09-30 |
|---|---|---|
| DOCS — приёмки NTF-1..4, замысел, маршрут | PRO-Robotech/kacho-workspace#880 → [[KAC/issue-880-ws]] | open, в работе |
| RULES — рёбра notify, замещение правил о почте | PRO-Robotech/kacho-workspace#881 | open, blocked |
| NTF-1 — служба notify | PRO-Robotech/kacho#2915 | open, blocked |
| NTF-1 — corelib: лента, формат шаблона, генератор | PRO-Robotech/corelib#77 | open, blocked |
| NTF-1 — kaname ставит нотификации в ленту | PRO-Robotech/kaname#484 | open, blocked |
| NS — политика выпуска сертификатов служб | PRO-Robotech/kacho#2916 | open, blocked |
| NTF-2 — снятие почты поставщика личности | PRO-Robotech/kacho#2917 | open, blocked |
| NTF-3 — уведомления модулей kacho | PRO-Robotech/kacho#2918 | open, blocked |
| NTF-4 — возвраты, жалобы, репутация отправителя | PRO-Robotech/kacho#2919 | open, blocked |
| находка — профиль развёртывания | PRO-Robotech/kacho#2920 | open |
| находка — приёмка 3.7 | PRO-Robotech/kacho-workspace#882 | open |

Находки названы ссылкой; их разбор в хранилище не пишется — адресом будет дифф фикса.

## Затронутые сущности vault

Пока нет. С посадкой NTF-1 появятся записки о службе notify (`rpc/`, `packages/`) и рёбрах
notify → источники, notify → kaname (`edges/`).

## DoD

- [ ] все дочерние задачи закрыты по предикатам приёмок своих под-фаз;
- [ ] секрет почты существует ровно в одном объекте установки;
- [ ] запрос эпика влит в `main`.

## History

- 2026-09-30 — trail заведён вместе с веткой пакета документов (#880 воркспейса).

#kac #epic
