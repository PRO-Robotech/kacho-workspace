---
title: minted_token_revocations
aliases:
  - MintedTokenRevocation (kaname)
  - вторая запись отсечки
category: resource
domain: iam
id_prefix: (subject)
owner_table: kaname.minted_token_revocations
owner_db: kaname
project_level: false
status: stable
related_rpc:
  - "[[rpc/iam-internal-iam-service]]"
  - "[[rpc/iam-user-service]]"
related_packages:
  - "[[packages/kaname-repo-pg]]"
  - "[[packages/kaname-migrations]]"
related_tickets:
  - "[[KAC/issue-335-kaname]]"
  - "[[KAC/issue-336-kaname]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "DDL, обе функции `kaname.minted_cutoff_on_*` и четыре зовущих их триггера прочитаны в `internal/migrations/0001_initial.sql` на origin/main продукта PRO-Robotech/kaname (2026-09-21); Go-писатель — `internal/repo/kaname/pg/minted_token_revocation_repo.go` на 229a0693; поведение на стенде не наблюдалось"
---

# minted_token_revocations (kaname)

**Schema**: `kaname.minted_token_revocations` · **Owner**: kaname · **Visibility**: internal.

## Назначение

**Вторая** из двух записей отсечки субъекта. Её читает авторитет отзыва **на пути запроса**:
момент отсечки сравнивается с отметкой выпуска предъявленного носителя. Первая запись —
[[resources/iam-user-token-revocation]].

Субъект здесь шире личности: строка адресуется и служебной учёткой, и клиентской записью,
поэтому ключ называется `subject`, а не `user_id`.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `subject` | text | 1..128 |
| `revoke_before` | timestamptz | момент отсечки; **монотонен** (`GREATEST`) |
| `reason` | text | ≤256 |
| `revoked_by` | text | **1..128 — пустой решивший запрещён** |
| `updated_at` | timestamptz | `now()` |

`minted_token_revocations_decider_ck` требует непустого решившего, и это верно: отсечка без
принявшего неоспорима.

## Писателей два рода — и они расходятся

| род | кто | причина и актор при конфликте |
|---|---|---|
| Go-дверь | `upsertSubjectCutoff`, кладёт обе записи | переписываются **только вместе** с принятым моментом |
| схемные | `kaname.minted_cutoff_on_client_removal()`, `kaname.minted_cutoff_on_owner_deactivation()`, четыре триггера | переписываются **безусловно** |

Момент монотонен у всех. Расходится атрибуция: на проигравшей по моменту записи схемный
писатель всё равно приносит свою причину и своего решившего. Предмет —
[[KAC/issue-335-kaname]]; расхождение целиком —
[[edges/kaname-cutoff-door-vs-schema-writers]].

## Уборка

Строка становится бессмысленной после `revoke_before + MaxTokenTTL + ClockSkew`: всякий
токен, который она отвергла бы, к этому моменту уже отвергнут собственным сроком. Порог
снятия больше момента бессмысленности на слагаемое запаса, потому что читатель отсечки
судит в Go, а уборка — часами базы.

## See also

[[resources/iam-user-token-revocation]] · [[edges/kaname-cutoff-door-vs-schema-writers]] ·
[[resources/iam-service-account-oauth-client]] · [[lessons/revocation-that-binds-at-issue-not-at-presentation]]

#resource #kacho-iam #iam #internal #migrations
