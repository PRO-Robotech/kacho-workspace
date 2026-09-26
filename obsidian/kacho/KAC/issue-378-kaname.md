---
title: "kaname#378: записи ревью Ф3 и Ф12 ред. 11 несут событие полномочия"
aliases:
  - issue-378-kaname
ticket_id: 378
category: kac
status: test
type: docs
repos:
  - kaname
areas:
  - docs/specs/reviews
prs:
  - https://github.com/PRO-Robotech/kaname/pull/409
issue_url: https://github.com/PRO-Robotech/kaname/issues/378
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - kacho-iam
  - docs
verified_against: "PRO-Robotech/kaname: последняя голова задачи f4190035d7a48fa40ae91204529b268b4e1c4987 — предок головы волны dda965ecef3 и origin/357, не предок origin/main (`git merge-base --is-ancestor`); предикат расхождения исполнен мной по дереву dda965ecef3 (`git archive` каталога docs/specs/reviews), 2026-09-24; 2026-09-26: трекер — закрыта 2026-09-26T09:37:08Z, меток status:* нет (`gh issue view`); коммит слияния волны dbf25d17e25 — в origin/357, не в origin/main (`gh api compare`)"
---

# kaname#378: записи ревью Ф3 и Ф12 ред. 11 несут событие полномочия

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:37:08Z вместе с волной [[KAC/issue-377-kaname|#377]]: запрос волны PR #409 влит в ветку эпика `357` (координата, не живая ссылка), коммит закрытия — слияние волны `dbf25d17e25`; метка `status:test` снята, метки сейчас: `documentation`, `P2`, `size:S`, `area:docs`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #357 в ствол.

## Что и зачем

Записи ревью приёмок Ф3 и Ф12 редакции 11 несли вердикт `APPROVED`, но не содержали блока
опубликованного события полномочия и объявляли санкцию невыданной, хотя события на трекере
уже были (PRO-Robotech/kacho#1281 и PRO-Robotech/kacho#1269). Задача дописывает блок `event`
по форме круга 7 и приводит `effective_approval` к факту события; вердикт, разбор и находки
записей не трогаются. Содержимое перенесено из PR #301 без изменений.

## Путь в волну

| что | координата |
|---|---|
| первое слияние в `377` | голова `d060e6df67e` → `2209bce0b62665942adb5e6241d0dffc8fbfdd19` |
| второе слияние в `377` | голова `f4190035d7a48fa40ae91204529b268b4e1c4987` → `0ea18de483e99b24df7fedfa17199720ebffe1bf` |
| запрос волны | PR #409 `377` → `357`, голова `dda965ecef351b97c563a80b37e626bc05dc9ef2`, коммит слияния `dbf25d17e25cba5368856da789c2674705a2392f` |

## DoD (из тела задачи)

- [x] перепись `docs/specs/reviews/*/*.yaml` по условию «`APPROVED` и `event.status:
      performed`, но `effective_approval.issued` не `true`» — «осмотрено 59 · расхождений 0»
      на `dda965ecef3` (перемерено мной; команда — `effective_approval.sanction.divergence_predicate`
      записей);
- [x] ветка задачи влита в ветку волны `377` коммитом слияния, волна — в ветку эпика `357`;
- [ ] предмет в стволе: изменение доехало до `main` посадкой эпика #357.

## Затронутые сущности vault

Поля «затронуто в vault» нет; узкие записки этой записью не менялись.

- [[KAC/issue-377-kaname]] — волна.
- [[KAC/issue-1281-kaname]] — приёмка Ф12, чьё событие записи теперь несут.

#kac #kacho-iam #docs
