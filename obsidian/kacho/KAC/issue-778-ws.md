---
title: "ws#778: волна-0 identity-own воркспейса — оснастка волны 0, влита в эпик 771"
aliases:
  - issue-778-ws
ticket_id: 778
category: kac
status: done
type: epic
repos:
  - kacho-workspace
areas:
  - .claude/agents
  - .claude/rules
  - .claude/skills
  - scripts
  - docs/changes/wave-identity-own-w0
  - obsidian/kacho
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/853
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/778
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho-workspace, 2026-09-26: PR #853 778 → 771 влит 2026-09-26T18:54:48Z коммитом слияния 3956217c (родители 27eb0775, a9159c46) (`gh pr view 853`); 3956217c = origin/771 и не предок origin/main 6eddaa5e (`git merge-base --is-ancestor`); `git diff a9159c46 3956217c` пуст; на a9159c46 check-runs 10 из 10 success, все из прогона workflow_dispatch 36260919447 (`gh api .../commits/a9159c46/check-runs`); трекер — закрыта 2026-09-26T19:24:10Z, sub-issue 12 из 12 закрыты, закрытых с status:test и status:in-progress 0 (`gh api .../sub_issues`, `gh issue list`); перенесённые и остатки — sub-issue ws#786 (`gh api .../parent`). Вердикты ролей — из комментария закрытия, мной не перемерялись"
---

# ws#778: волна-0 identity-own воркспейса — оснастка волны 0, влита в эпик 771

**Состояние на момент записи**: `done` — 2026-09-26. Волна **закрыта** на трекере
2026-09-26T19:24:10Z: её запрос PR #853 влит в ветку эпика `771` (координата, не живая ссылка)
коммитом слияния `3956217c`. Тем же заходом закрыты одиннадцать задач волны, у всех снята
`status:test`; [[KAC/issue-779-ws|#779]] закрыта раньше. В `main` волна **не** доехала: посадка эпика #771 в ствол — предмет эпика, а не волны; закрытая каскадом волна — `done` (`git-issues.md#gi-close-cascade`, решение владельца 2026-09-26). Родитель — эпик #771.

## Что и зачем

Воркспейс-половина волны 0 линии `release:identity-own`; кодовая половина — PRO-Robotech/kacho#2794
(запрос PRO-Robotech/kacho#2787). Предмет: требования владельца 2026-09-20 и 2026-09-21 — в корпус,
волна сдаётся одним запросом, общее выносится в `corelib`, записи ревью волны 0 — в ствол, вершина
линии оснастки (корпус под потолком, корень гейта из расположения проверки), trail kaname #334..#340.
Эта записка — trail волны как единицы вливания; предмет каждой задачи — в её записке.

## Задачи волны

| задача | исход |
|---|---|
| [[KAC/issue-716-ws\|#716]] · [[KAC/issue-720-ws\|#720]] · [[KAC/issue-721-ws\|#721]] | закрыты, работа в `771` |
| [[KAC/issue-722-ws\|#722]] | закрыта; остаток — ws#855 |
| [[KAC/issue-724-ws\|#724]] | закрыта; остаток — ws#856 |
| [[KAC/issue-780-ws\|#780]] | закрыта; остаток — ws#854 |
| [[KAC/issue-783-ws\|#783]] · [[KAC/issue-789-ws\|#789]] · [[KAC/issue-803-ws\|#803]] · [[KAC/issue-804-ws\|#804]] | закрыты, работа в `771` |
| [[KAC/issue-787-ws\|#787]] | закрыта; остаток — ws#858 |
| [[KAC/issue-779-ws\|#779]] | закрыта 2026-09-22, записи в `main` запросом PR #809 |
| [[KAC/issue-767-ws\|#767]] · [[KAC/issue-775-ws\|#775]] · [[KAC/issue-788-ws\|#788]] | не доставлены, переведены в волну-3 ws#786 |

Столкновение C5 из записи wave-reviewer круга 2 — ws#857: норма об изъятии отправленного решена
по-разному в `771` и в `786`. Trail у ws#854..#858 не заведён.

## Запрос волны

PR #853 `778` → `771`, голова `a9159c46`, коммит слияния `3956217c`. Круг 1 на голове `58631015`
вернул #722 и #724 и полосу записок kaname; правки круга 1 — `2bf4af63` (#724), `55161f0c` (#722),
`a9159c46` (записки). Ручной прогон `ci` на голове — 36260919447, check-runs 10 из 10 `success`.
Первая строка `2bf4af63` — 75 знаков при норме 72: решение диспетчера — отправленную историю не
переписывать, отступление названо.

Ветки: `778` снята при вливании; ветка `wave/identity-own-w0-ws` и ветка `review/wave0-post-diff-go`
(координаты, не живые ссылки) сняты на origin и локально — по `git ls-remote` на 2026-09-26 их нет.
На origin остались ветки задач `issue-716`..`issue-724` и ветка
`lane/rules-gate-root-and-ceiling-20260922` (координата, не живая ссылка): их головы не предки
`771` (`git merge-base --is-ancestor` → 1), работа вошла двойниками по дереву с переписанными
сообщениями — по комментариям задач от 2026-09-26, мной не перемерялось. PR #808 закрыт, PR #812 передан
волне-3 вместе с #775.

## History

- 2026-09-27 (#846) — состояние приведено к каскаду закрытия: волна закрыта тем, что её запрос влит в ветку эпика, `test` → `done`; посадка в `main` — DoD эпика, а не волны.

## Затронутые сущности vault

Полоса записок kaname волны: trail [[KAC/issue-334-kaname]] … [[KAC/issue-340-kaname]] и записки по
затронутым сущностям. Ревью вернуло полосу: записки описывали ревизию до фикса и собирали в одном
публичном месте, чем прежнее состояние было представимо. В `a9159c46` описание переведено на
ветку эпика kaname `357`, адрес разбора прежнего состояния — дифф фикса PRO-Robotech/kaname#326.

- [[edges/kaname-session-end-vs-code-issue]] · [[edges/kaname-family-revoke-vs-token-issue]] ·
  [[edges/kaname-cutoff-door-vs-schema-writers]]
- [[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
  [[resources/iam-refresh-token]] · [[resources/iam-human-session]]
- [[packages/kaname-migrations]] · [[lessons/invariant-held-by-the-package-not-the-schema]]

#kac #epic
