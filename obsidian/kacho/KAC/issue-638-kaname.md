---
title: "kaname#638: сброс ключей доступа распорядителем — сторона службы (бывш. ResetLoginMethods)"
aliases:
  - issue-638-kaname
  - kaname#638
ticket_id: 638
category: kac
status: in-progress
type: feature
repos:
  - kaname
areas:
  - docs/engineering/acceptance
  - docs/specs/reviews
prs:
  - https://github.com/PRO-Robotech/kaname/pull/672
issue_url: https://github.com/PRO-Robotech/kaname/issues/638
opened: 2026-10-07
tags:
  - kac
  - feature
  - kacho-iam
verified_against: "kaname 296@aa253fa9bcad (git ls-remote 2026-10-08): приёмка docs/engineering/acceptance/cloud-administrator-resets-login-methods.md — git show | sha256sum → 120ae199…, совпадает с записью ревью круга 5 (verdict APPROVED, event published → комментарий в kacho#2702); глаголов ResetLoginMethods и ResetAccessKeys в proto нет (git grep); PR kaname#672 — gh pr view (MERGED 2026-10-08T05:12Z, f3f5aa8f54c6); состояние задачи — gh issue view 2026-10-08 (OPEN)"
---

# kaname#638: сброс ключей доступа распорядителем — сторона службы (бывш. ResetLoginMethods)

> [!note] Состояние — `in-progress`: приёмка в линии, кода нет
> Редакция 5 приёмки влита в ветку эпика `296` запросом [kaname#672](https://github.com/PRO-Robotech/kaname/pull/672)
> (`f3f5aa8f54c6`, 2026-10-08) и одобрена записью круга 5. Со слов диспетчера 2026-10-08 приёмка
> переделывается — этой записью не измерено: на `296`@`aa253fa9bcad` последняя редакция — 5, одобренная.

## Что и зачем

Сторона службы для задачи платформы kacho#2702 (сброс способа входа распорядителем, F4d-20). Редакции 1–4
называли глагол `ResetLoginMethods` и снимали пароль вместе с ключами. Редакция 5 опровергла посылку полосы
реализации и сузила глагол: **`ResetAccessKeys`** снимает все ключи доступа человека и гасит сессии; строка
пароля и путь восстановления не трогаются — пароль возвращается восстановлением (решение Р8). Имена причины,
события и токена отказа сменены тем же доводом.

## Затронутые каталоги

`docs/engineering/acceptance`, `docs/specs/reviews` (PRO-Robotech/kaname). Код, proto и миграции — впереди.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] приёмка редакции 5 одобрена и в линии — отпечаток `120ae199…` равен записи круга 5, событие опубликовано;
- [ ] глагол `ResetAccessKeys` в контракте и реализация — нет (`git grep` по proto пуст);
- [ ] DoD-proof — нет.

## Затронутые сущности vault

- [[resources/kaname-access-key]] — ключ доступа, который глагол снимает (History 2026-10-08)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- kacho#2702 — задача платформы, на которой опубликовано событие одобрения

#kac #feature #kacho-iam
