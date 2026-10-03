---
title: "kaname: отзыв семейства vs выдача токена"
aliases:
  - family revoke vs token issue
  - отзыв семейства и вставка выданного
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
verified_against: "ключи семейства и ссылки кода и обновляющего токена на него прочитаны в `internal/migrations/20260920175117_authorization_code_is_our_record.sql` на ветке эпика 357 (fc9f5aff) продукта PRO-Robotech/kaname (2026-09-26); коммит, заведший ключ живости, найден `git log -S token_families_live_uk` на той же ветке, его PR — через API коммита; пробы названы по дереву и не запускались; на origin/main (cbbac984) таблиц церемонии нет"
---

# kaname: отзыв семейства vs выдача токена

> [!warning] Состояние — `test`: предмета на стволе нет
> Собственная церемония живёт в ветке эпика `357` и в `main` не влита (сверено 2026-09-26).

Ребро **внутри одного продукта**: пометка отзыва семейства и вставка выданного по нему —
кода авторизации либо обновляющего токена. Обещание ребра: **у отозванного семейства нет
живого выданного**.

## Чем держится

Схемой, а не писателем. Живость семейства — отдельная колонка в уникальном ключе
`token_families_live_uk`, и код и обновляющий токен ссылаются на неё своими ключами живости
(`authorization_codes_family_live_fk`, `refresh_tokens_family_live_fk`, каскад на
обновлении). Вставку в отозванное семейство отвергает база; отзыв доезжает до выданного
тем же каскадом.

- фикс — коммит `43d53cd75` полосы `kn-313`, вошёл в PR
  [kaname#326](https://github.com/PRO-Robotech/kaname/pull/326) ветки волны
  [[KAC/issue-358-kaname]];
- пробы ключа живости и выдачи внахлёст —
  [kaname#369](https://github.com/PRO-Robotech/kaname/issues/369), коммит `27bc66dc9`.

Класс, из которого ребро этим фиксом вышло, —
[[lessons/invariant-held-by-the-package-not-the-schema]]: переход с «держит писатель» на
«держит схема».

Отдельный предмет, не этот: причины отзыва без писателя — [[KAC/issue-339-kaname]].

## История

- 2026-09-21 — заведена по ревизии полосы `229a0693`, предшествующей фиксу.
- 2026-09-26 (#778) — описание переведено на ветку эпика, где ребро держит схема. Снят
  пересказ того, чем состояние было представимо до фикса: адрес такого разбора — дифф
  фикса, а не записка (`security-disclosure.md` §«Публичные артефакты»). Повод — возврат
  ревью волны.

## See also

[[resources/iam-token-family]] · [[resources/iam-authorization-code]] ·
[[resources/iam-refresh-token]] · [[edges/kaname-session-end-vs-code-issue]]

#edge #kacho-iam #iam #migrations #repo
