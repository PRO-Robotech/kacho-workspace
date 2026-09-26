---
title: "corelib#32: волна-2 — порты движка под службу доступа"
aliases:
  - issue-32-corelib
ticket_id: 32
category: kac
status: test
type: epic
repos:
  - corelib
areas:
  - oauthceremony
  - acrlevel
  - grpcsrv
  - tokenpolicy
  - ids
  - scripts/hooks
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/corelib/pull/69
  - https://github.com/PRO-Robotech/corelib/pull/71
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/32
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - epic
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: запрос волны PR #62 32 → 26 влит коммитом слияния 227ed2b77b4, 2026-09-24T20:36:02Z (`gh pr view 62`); восемнадцать голов задач из его тела и коммит 33e11da6840d — предки 227ed2b77b4 и не предки origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Ветка 53 @ 1677303b6c86 — не предок 227ed2b77b4; веток 50, 51, 54, 55, 60, 61 на origin нет (`git ls-remote --heads origin`); 2026-09-26: трекер волны закрыт 2026-09-26T09:41:01Z, sub-issue у волны осталось 25, все закрыты, меток status:* нет; семь невошедших — sub-issue эпика 26 (`gh api .../parent`); 227ed2b77b4 — в origin/26 @ 867dc4c5e41, не в origin/main (`gh api compare`)"
---

# corelib#32: волна-2 — порты движка под службу доступа

**Состояние на момент записи**: `test` — 2026-09-26. Волна **закрыта** на трекере
2026-09-26T09:41:01Z: её запрос PR #62 влит в ветку эпика `26` (координата, не живая ссылка)
коммитом слияния `227ed2b77b4` — это коммит закрытия волны и её задач. Тем же заходом закрыты 22
её sub-issue и [[KAC/issue-21-corelib|#21]], вошедшая в запрос без привязки; #33, #49 и задача
сборки #68 закрыты раньше. Семь невошедших переведены в эпик #26 — см. «Не вошли». В `main`
волна **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #26
в ствол. Родитель — эпик #26.

## Что и зачем

Церемония фундамента отдаёт службе доступа решения, которые служба принимает сама: чем
подписан токен доступа, как сверяется секрет клиента, как чеканится ID гранта, за что отозвано
семейство, какой контекст входа несёт грант, по каким адресам стоит церемония и где потолок
сроков. На этих портах стоит адаптер волны-2 службы доступа — [[KAC/issue-358-kaname|kaname#358]]
(переход на них — [[KAC/issue-410-kaname|kaname#410]]). Описание самих портов —
[[packages/corelib-oauthceremony]].

Эта записка — trail волны как единицы вливания. Предмет каждой задачи — в её записке.

## Вливания в ветку волны

| что | запрос | голова | коммит слияния в `32` | задачи |
|---|---|---|---|---|
| прямые вливания | — | головы задач | по задаче | [[KAC/issue-33-corelib\|#33]], [[KAC/issue-49-corelib\|#49]], [[KAC/issue-38-corelib\|#38]], [[KAC/issue-31-corelib\|#31]], [[KAC/issue-40-corelib\|#40]], [[KAC/issue-35-corelib\|#35]], [[KAC/issue-34-corelib\|#34]], [[KAC/issue-36-corelib\|#36]], [[KAC/issue-37-corelib\|#37]], [[KAC/issue-39-corelib\|#39]], [[KAC/issue-63-corelib\|#63]] |
| сборка 1, [[KAC/issue-68-corelib\|#68]] (закрыта) | PR #69, влит 2026-09-24T13:36:20Z | `c6d8b1b37b5` | `372daa9094a` | полосы `25` ([[KAC/issue-25-corelib\|#25]], [[KAC/issue-58-corelib\|#58]], [[KAC/issue-59-corelib\|#59]]), `45` ([[KAC/issue-45-corelib\|#45]], [[KAC/issue-56-corelib\|#56]], [[KAC/issue-64-corelib\|#64]]), `41` ([[KAC/issue-41-corelib\|#41]], [[KAC/issue-43-corelib\|#43]], [[KAC/issue-57-corelib\|#57]]), `42` ([[KAC/issue-42-corelib\|#42]], [[KAC/issue-44-corelib\|#44]], [[KAC/issue-47-corelib\|#47]]) |
| задача [[KAC/issue-70-corelib\|#70]] | PR #71, влит 2026-09-24T18:31:15Z | `b843c630a8a` | `92caf21abff` — голова ветки волны | #70 |

Прогоны на головах: `c6d8b1b37b5` — 2, `b843c630a8a` — 2, `92caf21abff` — 2, все `success`
(`gh run list -R PRO-Robotech/corelib --commit <sha>`).

## Запрос волны

PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`. Тело запроса называет
по каждой задаче голову и предикат; исхода предикатов и прогонов оно не утверждает. В том же
запросе — [[KAC/issue-21-corelib|#21]] (`issue-21` @ `dd8df2c1e167`), не sub-issue этой волны.

## Не вошли

| задача | основание |
|---|---|
| [[KAC/issue-50-corelib\|#50]], [[KAC/issue-51-corelib\|#51]], [[KAC/issue-55-corelib\|#55]], [[KAC/issue-60-corelib\|#60]], [[KAC/issue-61-corelib\|#61]] | ветки задачи нет — тело PR #62, раздел «вне запроса» |
| [[KAC/issue-53-corelib\|#53]] | ветка `53` @ `1677303b6c86` не предок головы запроса: держатель сохранён как есть и не доведён |
| [[KAC/issue-54-corelib\|#54]] | тело запроса её не называет; ветки на origin нет |

Предикат закрытия трекеров волн (как у kacho#2796): задачи волны закрыты с артефактом либо
переведены. При закрытии волны 2026-09-26T09:40 все семь переведены из #32 в sub-issue эпика #26
с комментарием: коммитов задач в `26` нет, признак на месте, открытой волны в фундаменте после
закрытия #32 и [[KAC/issue-29-corelib|#29]] нет. Остатков у волны 0.

## Затронутые сущности vault

Возвраты исполнителей волны называют пакеты oauthceremony, acrlevel (новый), grpcsrv,
tokenpolicy, ids и ребро oauthceremony → acrlevel. Заведены и обновлены:
[[packages/corelib-oauthceremony]], [[packages/corelib-acrlevel]], [[packages/corelib-grpcsrv]],
[[packages/corelib-ids]].

- [[KAC/issue-358-kaname]] — волна-2 службы доступа, потребитель портов.

#kac #epic #kacho-corelib
