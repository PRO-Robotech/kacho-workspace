---
title: "kaname#242: коллекция iam-membership-mine — запись ведомости производителя и захват тела"
aliases:
  - issue-242-kaname
ticket_id: 242
category: kac
status: done
type: fix
repos:
  - kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/265
  - https://github.com/PRO-Robotech/kaname/pull/267
issue_url: https://github.com/PRO-Robotech/kaname/issues/242
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - iam
  - ci
  - newman
verified_against: "kaname main@16b5cade (MR #266): newman-suite-debt.py → 0, --self-test → 0, run-python-probes.py → 169/169; задание «набор — оснастка, пробы, покрытие, долг» на MR зелёное"
---

# kaname#242: новая коллекция без записи ведомости роняет MR линии — дважды за сутки

**Предмет.** Коллекция `iam-membership-mine` (kaname#206, `MembershipService.ListMine`) приехала
без записи в ведомости производителя `.github/scripts/newman-suite-debt.py` и с захватом тела
через `JSON.stringify` (пересобранное, а не тело ответа). Задание `suite` красное на MR #266.

**Решение.** Запись категории **B** (служба + человеческий предъявитель): читает
`jwtHumanCeremonyNoBindings` — человек без выдач видит ровно свои строки; `md.resource` не
читается (PR #267). Захват тела — гейт формы тела не читает производное от ответа как тело
(PR #265).

**Класс, переехавший в форму задания.** Всякая новая коллекция набора службы несёт запись
ведомости производителя тем же изменением — иначе `newman-suite-debt.py` роняет MR. Класс переехал в
форму задания полосе (а не в записку: держит его гейт `newman-suite-debt.py`, а не память).

## Затронутые сущности vault

- [[rpc/iam-membership-service]] — `ListMine` и его сквозной кейс.

#kac #kacho-iam #iam #ci
