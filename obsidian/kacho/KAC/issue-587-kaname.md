---
title: "kaname#587: review-event-silence не видит событие вне subject.task"
aliases:
  - issue-587-kaname
  - kaname#587
ticket_id: 587
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/587
opened: 2026-10-03
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - ci
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались; 2026-10-06 — закрытие волной-4: kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb, git ls-remote), состояние — gh issue view, DoD — комментарий DoD-proof задачи; пробы этой записью не перезапускались"
---

# kaname#587: review-event-silence не видит событие вне subject.task

> [!note] Состояние — `test`: задача ЗАКРЫТА 2026-10-06 вливанием волны-4 эпика `296`, в `main` службы не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)). Врезка ниже —
> состояние на 2026-10-04, история.

> [!note] Состояние — `to-do`: заведена по ходу волны-2, волной не исполнялась

## Что и зачем

Гейт записей ревью ищет событие одобрения только в задаче, названной `subject.task` записи
вердикта. Событие, опубликованное в иной задаче, гейт не видит, и запись с неисполненным событием при
уже опубликованном проходит молча: прогон печатает «судимо N, расхождений 0», а вид «событие в другой
задаче» не осмотрен. Предмет — сам гейт и его самопроверка.

## Закрытие волной-4 (2026-10-06)

Коммиты полосы `587`: `bf980cdb9`, `be47f2f36`, `e9cf5ce71`, `75634faaa` (под тем же номером —
[[KAC/issue-371-kaname]]). [DoD-proof @2cf9c852](https://github.com/PRO-Robotech/kaname/issues/587#issuecomment-6009366907):
`review-event-silence.py --self-test` → rc 0, утверждений 23, расхождений 0.

## Затронутые каталоги

`.github/scripts/review-event-silence.py` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] вид «событие в другой задаче» судится — самопроверка гейта: утверждений 23, расхождений 0 (DoD-proof @2cf9c852);
- [ ] эпик влит в `main` службы — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-538-kaname]] — волна-4, закрыла

#kac #kacho-iam #ci
