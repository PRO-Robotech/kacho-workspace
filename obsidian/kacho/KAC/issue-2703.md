---
title: "kacho#2703: регистрация личности ключом без пароля — обещание снято с приёмок"
aliases:
  - issue-2703
ticket_id: 2703
category: kac
status: test
type: docs
repos:
  - kacho
  - kaname
areas:
  - kaname: docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/582
issue_url: https://github.com/PRO-Robotech/kacho/issues/2703
opened: 2026-09-17
closed: "2026-10-03"
tags:
  - kac
  - kacho-iam
  - docs
verified_against: "kaname 296@d2f6f182 (коммит слияния PR #582, родители 9bac42bdcbc + ed95e66f1; голова origin/296 = этот коммит, 2026-10-03): состав коммитов — git log по 9bac42bdcbc..ed95e66f1, предикаты DoD, названные в строках, — git grep -c / sha256sum на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kacho#2703: регистрация личности ключом без пароля — обещание снято с приёмок

> [!note] Состояние — `test`, хотя задача закрыта
> Задача платформы, исполненная в доме службы: закрыта 2026-10-03 после вливания волны-1 службы
> [[KAC/issue-535-kaname]] в ветку эпика `296` запросом [kaname#582](https://github.com/PRO-Robotech/kaname/pull/582)
> (`d2f6f182`). В `main` службы не влито — состояние `test`.

## Что и зачем

Две приёмки дома службы (Ф7 и Ф13) обещали третью — регистрацию личности ключом без пароля, — у
которой не было ни задачи, ни исполнителя. Решение: «полосы регистрации ключом не будет»; обещание
снято с приёмок, а не исполнено.

Исполнено в приёмках волны-1 службы: Ф1 (коммит `61d7dd8fb`), Ф7 и Ф13 (коммит `bfbfa3a07`).

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса → волна | ветка `269` (координата, не живая ссылка) → ветка `535` | — | ae5f0df0b | — (локальное слияние `--no-ff`) |
| волна → эпик | ветка `2964` → ветка `1266` | 25ba0c48664 | 656955b66b7 | [kacho#3009](https://github.com/PRO-Robotech/kacho/pull/3009) |

## Затронутые каталоги

Коммиты: `61d7dd8fb`, `bfbfa3a07` (полоса kaname#269). Пути: `docs/engineering/acceptance/{login-session-and-credentials-are-our-contract,access-keys-are-ours,passwordless-login-with-access-key}.md` и их записи ревью.

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] записи ревью на текущие отпечатки на `d2f6f182` — `APPROVED`: Ф1 `0f758d32`, Ф7 `5ea26ad0`, Ф13 `322251f6` (`sha256sum` документа → `docs/specs/reviews/<документ>/<отпечаток>.yaml`, поле `verdict`).

## Затронутые сущности vault

- [[resources/kaname-access-key]] — ключ доступа: обещание регистрации ключом снято (History kacho#2703)

## Связанные задачи

- [[KAC/issue-535-kaname]] — волна службы, где исполнено
- [[KAC/issue-1266]] — эпик
- [[KAC/issue-1273]] — Ф7

#kac #kacho-iam #docs
