---
title: "kaname#587: review-event-silence не видит событие вне subject.task"
aliases:
  - issue-587-kaname
  - kaname#587
ticket_id: 587
category: kac
status: to-do
type: fix
repos:
  - kaname
areas:
  - .github/scripts
prs: []
issue_url: https://github.com/PRO-Robotech/kaname/issues/587
opened: 2026-10-03
tags:
  - kac
  - kacho-iam
  - ci
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#587: review-event-silence не видит событие вне subject.task

> [!note] Состояние — `to-do`: заведена по ходу волны-2, волной не исполнялась

## Что и зачем

Гейт записей ревью ищет событие одобрения только в задаче, названной `subject.task` записи
вердикта. Событие, опубликованное в иной задаче, гейт не видит, и запись с неисполненным событием при
уже опубликованном проходит молча: прогон печатает «судимо N, расхождений 0», а вид «событие в другой
задаче» не осмотрен. Предмет — сам гейт и его самопроверка.

## Затронутые каталоги

`.github/scripts/review-event-silence.py` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [ ] вид «событие в другой задаче» судится, инъекция краснит, близнец зелёный — не начато.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик

#kac #kacho-iam #ci
