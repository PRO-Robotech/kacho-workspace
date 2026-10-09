---
title: "kaname#636: дефект факта права, найденный пробой NTF3-184"
aliases:
  - issue-636-kaname
ticket_id: 636
category: kac
status: in-progress
verified_against: "`gh` 2026-10-09: kaname PR #673 MERGED в `484-notify` 2026-10-09T17:16Z merge-коммитом d93b69712f0d (родители 33010d434767 и голова полосы 1197a78edd8e), голова `484-notify` = d93b69712f0d (`gh api .../branches`); kaname#636 OPEN. `gh` 2026-10-08: kaname#636 OPEN (заведена 2026-10-06, метки bug, P1, size:M, area:iam, release:notifications); комментарии 2026-10-08T04:29Z — `DoD-proof @bdc36c614` и ссылка на PR #673; kaname PR #673 OPEN в `484-notify`, голова 1197a78edd8e (`gh pr view`), вердикта посадки нет — со слов описания. Прогоны мной не перезапускались"
type: fix
repos:
  - kaname
areas:
  - internal
prs:
  - https://github.com/PRO-Robotech/kaname/pull/673
issue_url: https://github.com/PRO-Robotech/kaname/issues/636
opened: 2026-10-06
closed:
tags:
  - kac
  - kacho-iam
  - fix
---

# kaname#636: дефект факта права, найденный пробой NTF3-184

**Состояние на момент записи**: `in-progress`. Фикс — в kaname
[#673](https://github.com/PRO-Robotech/kaname/pull/673), влитом в ветку эпика
`484-notify` (координата, не живая ссылка) 2026-10-09 merge-коммитом `d93b69712f0d`; в `main` не влит. До вливания
линии kaname в `main` статус `done` записке не положен.

**Линия:** [[KAC/issue-484-kaname]]. **Найдено:** красной пробой NTF3-184 под-фазы NTF-3,
[[KAC/issue-2918]].

## Что и зачем

Дефект корректности службы доступа kaname, P1. Условие и следствие названы в задаче; разбор
и механизм фикса — в задаче и диффе #673 и здесь не пересказываются.

## Ход

- 2026-10-08 — в задаче оставлен `DoD-proof @bdc36c614`: проба NTF3-184 красная до фикса и
  зелёная на нём, полный набор проб kaname зелёный (числа — в комментарии задачи). PR #673
  открыт в `484-notify` с `Refs PRO-Robotech/kacho#2918`.

- 2026-10-09 — #673 влит в `484-notify` merge-коммитом `d93b69712f0d`. Задача на `gh` 2026-10-09
  OPEN.

## DoD

- [x] красная проба NTF3-184 до фикса, зелёная после — `DoD-proof @bdc36c614` в задаче;
- [x] #673 влит в `484-notify` (`d93b69712f0d`, 2026-10-09);
- [ ] линия kaname посажена в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-484-kaname]] — линия kaname эпика notify.
- [[KAC/issue-2918]] — NTF-3, источник пробы.
- [[KAC/issue-667-kaname]] — второй фикс той же волны #673.

## History

- 2026-10-08 — trail заведён: #673 открыт с фиксом, не влит. Статус `in-progress`.
- 2026-10-09 — #673 влит в `484-notify` (`d93b69712f0d`); задача OPEN. Статус `in-progress`.

## Затронутые сущности vault

- Узких записок не тронуто: фикс влит только в ветку эпика `484-notify`, в `main` его нет.

#kac #kacho-iam #fix
