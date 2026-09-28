---
title: "ws#775: записи wave-reviewer волны 0 identity-own — в волне-3"
aliases:
  - issue-775-ws
ticket_id: 775
category: kac
status: in-progress
type: docs
repos:
  - kacho-workspace
areas:
  - docs/changes/wave-identity-own-w0/reviews/wave/wave-reviewer
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/812
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/775
opened: 2026-09-22
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace, 2026-09-26: трекер — задача открыта, метка blocked, родитель ws#786 (`gh issue view 775`, `gh api .../parent`); PR #812 открыт, база main (`gh pr view 812`); ветка review/wave0-wave-reviewer на origin — b99a2ca9 (`git ls-remote`). Причина перевода (форма дайджеста записей и check-05 change-graph-gate) — из комментария задачи 2026-09-26, мной не перемерялась; 2026-09-28 (#846): состояние, метки и родитель — трекер (`gh issue view 775 -R PRO-Robotech/kacho-workspace`, `gh api .../parent`), вливания — `gh pr view` либо лог ветки волны; DoD не перемерялся"
---

# ws#775: записи wave-reviewer волны 0 identity-own — в волне-3

**Состояние на момент записи**: `to-do` — 2026-09-26. Задача **открыта**, метки: `blocked`, `P1`,
`size:S`, `area:tooling`, `release:identity-own`; `Blocked by #822`, `Blocked by #824`.
2026-09-26 переведена из волны 0 [[KAC/issue-778-ws|#778]] в волну-3 ws#786, волна 0 закрыта без
этих записей. Работа есть — PR #812, ветка `review/wave0-wave-reviewer` (координата, не живая
ссылка) @ `b99a2ca9`, — но задачу никто не ведёт: она ждёт механизма посадки записей.

**Состояние на 2026-09-28**: `in-progress`. Задача открыта, метка `status:in-progress`, метка `blocked` снята 2026-09-28T13:07Z: оба блокера (#822, #824) сданы в ветку волны `786` — их головы `4b9eac04` и `06b18c29` предки `origin/786` @ `99fbac9f` (комментарий задачи). Взята 2026-09-28T13:20Z веткой `775` (координата, не живая ссылка) от `786` @ `99fbac9`. PR #812 по-прежнему открыт, база `main` (`gh pr view 812`).

## Что и зачем

Две записи wave-reviewer по запросу PRO-Robotech/kacho#2787 лежат только в этой ветке: круг 2 и
проход дельты B5, обе приняты; неблокирующие C3 и R5 уходят с предметом в PRO-Robotech/kacho#2792.
Запись на последнем дайджесте — одна из предпосылок записи схождения [[KAC/issue-767-ws|#767]].

Почему не в волне 0: записи сняты без полного индекса, и `check-05` в `scripts/change-graph-gate/`
считает их новыми; переносить границу проверки — послабление. Записи садятся механизмом, который
принимается в ws#822 и ws#824.

## Путь

| что | координата |
|---|---|
| запрос | PR #812, база `main`, открыт; передан волне-3 комментарием 2026-09-26 |
| по каскаду | ветка приходит в `786` сборкой волны-3, а не вливанием #812 в `main` |

## DoD

Из тела задачи:

- [ ] в стволе обе записи `wave/wave-reviewer/` на дайджестах `3c93ec13…` и `64de754d…`;
- [ ] ветка снята.

## History

- 2026-09-28 (#846) — состояние приведено к трекеру: to-do → in-progress: блокеры сданы, метка `blocked` снята, задача взята в работу. Назначение снято с «ждут #822 и #824»: блокеров больше нет.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах по этой задаче нет.

- [[KAC/issue-778-ws]] — волна, из которой переведена · [[KAC/issue-779-ws]],
  [[KAC/issue-783-ws]] — записи других ролей той же волны продукта.

#kac #docs
