---
title: "kaname#268: сквозной набор newman ключей доступа"
aliases:
  - issue-268-kaname
ticket_id: 268
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/582
issue_url: https://github.com/PRO-Robotech/kaname/issues/268
opened: 2026-09-17
closed: "2026-10-03"
tags:
  - kac
  - kacho-iam
  - iam
  - kacho-test
verified_against: "kaname 296@d2f6f182 (коммит слияния PR #582, родители 9bac42bdcbc + ed95e66f1; голова origin/296 = этот коммит, 2026-10-03): состав коммитов — git log по 9bac42bdcbc..ed95e66f1, предикаты DoD, названные в строках, — git grep -c / sha256sum на базе и на слиянии; пробы и конвейер этой записью не перезапускались"
---

# kaname#268: сквозной набор newman ключей доступа

> [!note] Состояние — `test`, хотя задача закрыта
> Закрыта в трекере 2026-10-03 каскадом волны-1 [[KAC/issue-535-kaname]]: волна влита в ветку эпика `296`
> запросом [kaname#582](https://github.com/PRO-Robotech/kaname/pull/582), коммит слияния `d2f6f182fab9d9727a7fab35a82a798005eb0d89`.
> В `main` службы код не влит — открытого запроса эпика `296` → `main` нет
> (`gh pr list --base main --head 296` → пусто, 2026-10-03), поэтому состояние записки `test`.
> Комментарий закрытия: хук отправки на сведённой голове `ed95e66f1` и на слиянии — 6 из 6 групп,
> отказов 0; сквозные прогоны на стенде не проверялись.

## Что и зачем

Шесть глаголов `AccessKeyService` (Ф7) не имели ни одного сквозного кейса. Исход: набор
`kaname-access-keys` — шесть глаголов Ф7 сквозь собственный фронт службы, сверен с приёмкой Ф7
ред.15 (Ф7-16 — кейсом), с фикстурой-аутентификатором в песочнице.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса → волна | ветка `268` (координата, не живая ссылка) → ветка `535` | — | 5c1f7e8b4 | — (локальное слияние `--no-ff`) |
| волна → эпик | ветка `535` → ветка `296` | ed95e66f1 | d2f6f182 | [kaname#582](https://github.com/PRO-Robotech/kaname/pull/582) |

## Затронутые каталоги

Коммиты: `3dd9d83bf`, `26b2ad669`, `0f5bb161a`, `7eda4f4d8`, `5d3cdd87a`, `8bc6d1358`. Путь: `tests/newman/` (кейс `cases/kaname-access-keys.py`, коллекция, `RESULTS`).

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] кейс набора в дереве: `tests/newman/cases/kaname-access-keys.py` есть на `d2f6f182`, на базе нет (`git ls-tree`).
- [ ] два зелёных прогона и три инъекции — со слов коммитов `7eda4f4d8`, `8bc6d1358`; этой записью набор не прогонялся.
- [ ] `newman-suite-debt.py` → 0 — этой записью не исполнялся.

## Затронутые сущности vault

- [[resources/kaname-access-key]] — ключ доступа: Ф7 на ветке эпика (History kaname#268)
- [[packages/kaname-access-keys]] — глаголы, которые набор проходит

## Связанные задачи

- [[KAC/issue-535-kaname]] — волна-1, родитель
- [[KAC/issue-296-kaname]] — эпик
- [[KAC/issue-1273]] — Ф7

#kac #kacho-iam #iam #kacho-test
