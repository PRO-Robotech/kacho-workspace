---
title: "kaname#335: схемные писатели отсечки переписывают причину и актора безусловно"
aliases:
  - issue-335-kaname
  - kaname#335
ticket_id: 335
category: kac
status: to-do
type: fix
repos:
  - kaname
prs: []
issue_url: https://github.com/PRO-Robotech/kaname/issues/335
opened: 2026-09-21
tags:
  - kac
  - kacho-iam
  - iam
  - migrations
  - repo
verified_against: "тела функций `kaname.minted_cutoff_on_client_removal` и `kaname.minted_cutoff_on_owner_deactivation` прочитаны в `internal/migrations/0001_initial.sql` на origin/main продукта PRO-Robotech/kaname (2026-09-21); Go-писатель — `internal/repo/kaname/pg/minted_token_revocation_repo.go` на 229a0693"
---

# kaname#335: схемные писатели отсечки переписывают причину и актора безусловно

> [!note] Предмет есть на стволе — задача не ждёт слияния
> Обе функции лежат в `internal/migrations/0001_initial.sql` на `origin/main`, и все четыре
> триггера, которые их зовут, тоже. Полоса `kn-313` нужна здесь только как источник
> формулировки, а не как условие работы.

## Предмет

У строки отсечки отчеканенного (`kaname.minted_token_revocations`) писателей двух родов.
Go-дверь после `kn-313` переписывает **причину и актора только вместе с принятым моментом**:
момент монотонен (`GREATEST`), и на проигравшей записи прежние причина и актор остаются.
Схемные писатели — функции `kaname.minted_cutoff_on_client_removal()` и
`kaname.minted_cutoff_on_owner_deactivation()` — в той же `ON CONFLICT`-ветке присваивают
`reason = EXCLUDED.reason` и `revoked_by = EXCLUDED.revoked_by` **безусловно**.

## Координата

Остаток объявлен в `internal/repo/kaname/pg/minted_token_revocation_repo.go:89-93` на
`229a0693`. Предмет правки — тела двух функций в
`internal/migrations/0001_initial.sql` (на стволе — объявления
`minted_cutoff_on_client_removal` и `minted_cutoff_on_owner_deactivation`); зовут их четыре
триггера: снятие клиентской записи служебной учётки, снятие клиентской записи личности,
выключение служебной учётки, выход личности из активного состояния.

## Признак

Момент отсечки после слияния двух писателей монотонен у всех, а **причина и актор
принадлежат стоящему моменту**. Пока схемный писатель присваивает их безусловно, запись,
проигравшая по моменту, всё равно приносит свою причину и своего решившего — и строка, по
которой судит авторитет отзыва на пути запроса, называет не того, кто решение принял.

Момент при этом не сдвигается назад ни в одном случае: свойство, которое здесь теряется, —
атрибуция, а не сама отсечка.

## Предикат снятия

У обеих функций `minted_cutoff_on_*` в ветке `DO UPDATE` стоит тот же `CASE WHEN` по
моменту, что у Go-двери: присваивание причины и актора условно на
`EXCLUDED.revoke_before >= <текущий>`. Правка идёт **новой** миграцией — применённая не
правится (запрет #5).

## Затронутые сущности vault

- [[resources/iam-minted-token-revocation]] — строка, у которой расходятся писатели.
- [[edges/kaname-cutoff-door-vs-schema-writers]] — само расхождение, оба его свойства.
- [[packages/kaname-migrations]] · [[packages/kaname-repo-pg]] — два дома писателей.

## Связанные задачи

[[KAC/issue-336-kaname]] — второе свойство того же расхождения.

#kac #kacho-iam #iam #migrations #repo
