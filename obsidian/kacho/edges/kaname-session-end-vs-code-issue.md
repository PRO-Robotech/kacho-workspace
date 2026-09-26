---
title: "kaname: снятие сессии vs выдача кода авторизации"
aliases:
  - session end vs code issue
  - снятие сессии и вставка кода
category: edge
caller_repo: kacho-iam
callee_repo: kacho-iam
sync_async: sync
protocol: postgres
status: test
related_tickets:
  - "[[KAC/issue-358-kaname]]"
  - "[[KAC/issue-339-kaname]]"
tags:
  - edge
  - kacho-iam
  - iam
  - migrations
  - repo
verified_against: "писатель выдачи прочитан в `internal/repo/kaname/pg/oauth_ceremony_repo.go` (шапка замков и оператор заведения семейства), писатель снятия — вызовы `revokeFamiliesOfSessionsTx` в `internal/repo/kaname/pg/human_session_repo.go`, оба на ветке эпика 357 (fc9f5aff) продукта PRO-Robotech/kaname (2026-09-26); коммит фикса найден `git log -S` на той же ветке, его PR — через API коммита; пробы названы по дереву и не запускались; на origin/main (cbbac984) таблиц церемонии нет"
---

# kaname: снятие сессии vs выдача кода авторизации

> [!warning] Состояние — `test`: предмета на стволе нет
> Собственная церемония живёт в ветке эпика `357` и в `main` не влита (сверено 2026-09-26).

Ребро **внутри одного продукта**: снятие записи сессии человека и заведение семейства с
кодом авторизации в этой сессии. Обещание ребра: **в снятой сессии нет живого выданного** —
ни выданного до снятия, ни заведённого после.

## Чем держится

Писателями, с обеих сторон:

- снятие сессии **той же транзакцией** отзывает семейства названных сессий причиной
  `session-ended` (`revokeFamiliesOfSessionsTx`), а отзыв семейства доезжает до выданного
  по [[edges/kaname-family-revoke-vs-token-issue]];
- выдача берёт строку сессии замком, несовместимым со снятием, **первой**, и заводит
  семейство условием на живость сессии в том же операторе, что запись.

- фикс — коммит `5a279949c` полосы `kn-313`, вошёл в PR
  [kaname#326](https://github.com/PRO-Robotech/kaname/pull/326) ветки волны
  [[KAC/issue-358-kaname]];
- пробы выдачи внахлёст со снятием сессии —
  [kaname#369](https://github.com/PRO-Robotech/kaname/issues/369), коммит `27bc66dc9`.

Схема живость сессии здесь сама не держит: обе стороны — обязательство писателей, и
держатся они пробами, а не ключом. Класс —
[[lessons/invariant-held-by-the-package-not-the-schema]].

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`, предшествующей фиксу.
- 2026-09-26 (#778) — описание переведено на ветку эпика. Снят пересказ того, чем снятие и
  выдача расходились до фикса и что из этого следовало: адрес такого разбора — дифф фикса, а
  не записка (`security-disclosure.md` §«Публичные артефакты»). Повод — возврат ревью волны.

## See also

[[resources/iam-human-session]] · [[resources/iam-token-family]] ·
[[resources/iam-authorization-code]] · [[packages/kaname-repo-pg]]

#edge #kacho-iam #iam #migrations #repo
