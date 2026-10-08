---
title: "kacho#2919: notify NTF-4 — возвраты, жалобы, подавление, DKIM/SPF/DMARC"
aliases:
  - issue-2919
  - NTF-4
ticket_id: 2919
category: kac
status: in-progress
verified_against: "`gh` 2026-10-07: corelib PR #98 MERGED в `77-notify` 2026-10-06T18:39Z merge-коммитом d3c964ae6fa7; kaname PR #628 MERGED в `484-notify` 2026-10-06T22:55Z (56bcb3036d71); kacho PR #3072 (волна линии E) OPEN в `2914-notify`; задача #2919 и эпик #2914 OPEN. Путь приёмки снят `git ls-tree origin/issue-880 docs/specs/` воркспейса; состав — со слов описаний PR; прогоны мной не перезапускались"
type: feature
repos:
  - kacho
  - corelib
  - kaname
areas:
  - services/notify
prs:
  - https://github.com/PRO-Robotech/corelib/pull/98
  - https://github.com/PRO-Robotech/kaname/pull/628
issue_url: https://github.com/PRO-Robotech/kacho/issues/2919
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2919: notify NTF-4 — возвраты, жалобы, подавление, DKIM/SPF/DMARC

**Состояние на момент записи**: `in-progress`. Предметы линии E в фундаменте влиты в ветки
эпиков corelib и kaname; волна kacho линии E — PR #3072 — открыта и не влита. В `main` не
влито ничего. Статус `done` записке не положен до посадки эпика в `main`.

**Эпик:** [[KAC/issue-2914]]. **Блокеры из тела:** #2915,
PRO-Robotech/kacho-workspace#880. **Роль исполнителя:** `go-implementer`.

## Что и зачем

Сведений о возвратах и жалобах отправитель не получает, подавления адресов нет, подписи
DKIM и политик SPF/DMARC установка не объявляет. Предмет — обратная связь и репутация
notify. Полный объём — в теле задачи.

## Документы

- Приёмка: тело задачи называет `docs/specs/sub-phase-NTF-4-feedback-reputation-acceptance.md`,
  в дереве она лежит как `docs/specs/sub-phase-NTF-4-delivery-feedback-reputation-acceptance.md`
  в ветке `issue-880` воркспейса (координата, не живая ссылка). На `origin/main` воркспейса
  2026-10-07 нет ни одного из двух путей. Предикат снятия оговорки: путь резолвится на
  `origin/main` воркспейса — тогда здесь остаётся одно имя.

## Волны

| репозиторий | ветка эпика | PR | merge-коммит | состав |
|---|---|---|---|---|
| corelib | `77-notify` | [#98](https://github.com/PRO-Robotech/corelib/pull/98) | `d3c964ae6fa7` | E-X3: исход ленты SUPPRESSED с причиной, схема ленты V2 и переход V1→V2 (волна def2 вместе с F-C5 задачи [[KAC/issue-2924]]) |
| kaname | `484-notify` | [#628](https://github.com/PRO-Robotech/kaname/pull/628) | `56bcb3036d71` | E-X4: пин corelib, справочник и лента kaname для NTF-4 (волна def1 вместе с линией D задачи [[KAC/issue-2917]]) |
| kacho | `2914-notify` | [#3072](https://github.com/PRO-Robotech/kacho/pull/3072) | — (OPEN) | волна линии E: исход SUPPRESSED в ленте и ручки стадии S1 |

## DoD (из тела задачи)

- [x] исход ленты SUPPRESSED в фундаменте (corelib #98) и у kaname (kaname #628);
- [ ] исход SUPPRESSED и ручки стадии S1 в kacho (#3072 открыт);
- [ ] приём уведомлений о недоставке и жалоб, подавление адресов;
- [ ] подпись DKIM, требования SPF/DMARC к установке, наблюдаемость репутации;
- [ ] сценарии приёмки NTF-4 зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-2914]] — эпик «Сервис уведомлений».
- [[KAC/issue-2915]] — NTF-1, ядро шлюза; блокер из тела.
- https://github.com/PRO-Robotech/kacho/issues/3017 — DKIM, SPF и DMARC домена отправителя
  профиля a8f60d (P3, решение за владельцем).
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib эпика.
- https://github.com/PRO-Robotech/kaname/issues/484 — линия kaname эпика.
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела.

## History

- 2026-10-07 — trail заведён: corelib #98 (E-X3, `d3c964ae6fa7`) и kaname #628 (E-X4,
  `56bcb3036d71`) влиты в ветки эпиков; kacho #3072 открыт. Статус `in-progress`.

## Затронутые сущности vault

- Узких записок волны не тронули: в kacho ничего не влито, а записки о ленте corelib в
  vault нет.

#kac #feature
