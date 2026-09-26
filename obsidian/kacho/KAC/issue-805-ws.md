---
title: "ws#805: волна-2 оснастки — приёмки F8 и KAN-AUTHN-1, флоу v2, записи ревью"
aliases:
  - issue-805-ws
ticket_id: 805
category: kac
status: test
type: epic
repos:
  - kacho-workspace
areas:
  - docs/specs
  - docs/changes
  - .claude/agents
  - .claude/rules
  - scripts/hooks
  - obsidian/kacho
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/828
  - https://github.com/PRO-Robotech/kacho-workspace/pull/831
  - https://github.com/PRO-Robotech/kacho-workspace/pull/834
  - https://github.com/PRO-Robotech/kacho-workspace/pull/836
  - https://github.com/PRO-Robotech/kacho-workspace/pull/840
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/805
opened: 2026-09-22
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho-workspace: запрос волны PR #841 805 → 771 влит коммитом слияния 27eb0775252 (родители 16ddf129d27, aa378730dcb), 2026-09-25T20:35:37Z (`gh pr view 841`); восемнадцать голов из его тела — предки origin/771 и не предки origin/main 6eddaa5e (`git merge-base --is-ancestor`), 2026-09-26"
---

# ws#805: волна-2 оснастки — приёмки F8 и KAN-AUTHN-1, флоу v2, записи ревью

**Состояние на момент записи**: `test` — 2026-09-26. Волна **влита** в ветку эпика `771`
(координата, не живая ссылка) запросом PR #841, коммит слияния `27eb0775252`; в `main` **не**
доехала: закроет её посадка эпика #771 в ствол. Трекер волны открыт; метки `status:test` у него
нет. Родитель — эпик #771.

## Что и зачем

Две приёмки, возвращённые рецензентом в волне-1, — F8 ([[KAC/issue-773-ws|#773]]) и
KAN-AUTHN-1 ([[KAC/issue-618-ws|#618]]), — и оснастка, которую потребовали волны-2 продукта:
флоу v2, правила newman и сборки волны, хуки отправки, записи ревью полос. Эта записка — trail
волны как единицы вливания; предмет каждой задачи — в её записке.

## Вливания в ветку волны

| что | запрос | коммит слияния в `805` | задачи |
|---|---|---|---|
| прямые вливания | — | `e9302c03`, `a8ffa48c` | [[KAC/issue-618-ws\|#618]], [[KAC/issue-773-ws\|#773]] |
| по запросу задачи | PR #828, #831, #834 | `80221e24`, `80971a64`, `fb7a2cbb` | [[KAC/issue-826-ws\|#826]], [[KAC/issue-829-ws\|#829]], [[KAC/issue-832-ws\|#832]] |
| сборка 1, [[KAC/issue-835-ws\|#835]] (закрыта) | PR #836, голова `2345ef6cd86` | `f46878626e8` | [[KAC/issue-810-ws\|#810]], [[KAC/issue-811-ws\|#811]], [[KAC/issue-813-ws\|#813]], [[KAC/issue-815-ws\|#815]], [[KAC/issue-818-ws\|#818]], [[KAC/issue-823-ws\|#823]], [[KAC/issue-825-ws\|#825]], [[KAC/issue-827-ws\|#827]], [[KAC/issue-830-ws\|#830]], [[KAC/issue-833-ws\|#833]] |
| сведение общей копии | PR #840, голова `d5d6a650b5f` | `aa378730dcb` | [[KAC/issue-839-ws\|#839]] и ветка docfresh #784 |

Догон ветки эпика после волны-1 — `086847c7`.

## Запрос волны

PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогон головы — 1,
`success`. Вынесены в волну-3 #786 (тело трекера, 2026-09-24 и 2026-09-25): #816, #785, #821,
#822, #824, #837.

Приёмка F8 в ветке эпика — редакция 6; переутверждённая редакция 8 лежит на ветке `acc-f8`
(координата, не живая ссылка) и в `771` не вошла — подробности в [[KAC/issue-773-ws]].

## Затронутые сущности vault

Возвраты исполнителей волны ресурсов, rpc и рёбер продукта не называют; хранилище задевала
[[KAC/issue-833-ws|#833]] — trail сборок kacho#2796 и волн kaname 358 и 377.

- [[KAC/issue-2796]] · [[KAC/issue-358-kaname]] · [[KAC/issue-32-corelib]] — волны-2 продукта.

#kac #epic
