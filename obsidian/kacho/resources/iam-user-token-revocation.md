---
title: user_token_revocations
aliases:
  - UserTokenRevocation (kaname)
  - первая запись отсечки
category: resource
domain: iam
id_prefix: (user_id)
owner_table: kaname.user_token_revocations
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
  - "[[KAC/issue-336-kaname]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
  - migrations
verified_against: "DDL прочитан в `internal/migrations/0001_initial.sql` на origin/main продукта PRO-Robotech/kaname (2026-09-21); дверь `upsertSubjectCutoff` и перепись её вызывающих — на ревизии 229a0693 (полоса не влита); поведение на стенде не наблюдалось"
---

# user_token_revocations (kaname)

**Schema**: `kaname.user_token_revocations` · **Owner**: kaname · **Visibility**: internal.

## Назначение

**Первая** из двух записей отсечки субъекта. Её читают хуки **выдачи**: момент отсечки
сравнивается с моментом аутентификации сессии. Вторая запись —
[[resources/iam-minted-token-revocation]] — читается авторитетом отзыва на пути запроса и
сравнивается с отметкой выпуска предъявленного носителя.

Разные читатели и есть причина, по которой записей две, а не одна.

## Колонки

| Column | Type | Notes |
|---|---|---|
| `user_id` | text | ключ субъекта |
| `revoke_before` | timestamptz | момент отсечки; **монотонен** (`GREATEST`) |
| `reason` | text | ≤256, по умолчанию пусто |
| `revoked_by_user_id` | text | допускает `NULL` — человек вправе выйти сам |
| `updated_at` | timestamptz | `now()` |

## Писатель — одна дверь

`upsertSubjectCutoff` (`internal/repo/kaname/pg/user_token_revocations_repo.go`) —
единственная дверь к отсечке субъекта: она кладёт **обе** записи. Пока писатели звали
оператор напрямую, состояние «одна запись без второй» было представимо — и представилось.

Различие, которое дверь обязана сглаживать: `revoked_by_user_id` здесь законно пуст, а
вторая запись требует непустого решившего. Пустой замещается **именем механизма**,
выведенным из причины отсечки, — не пустой строкой и не подставным человеком.

## Чего дверь НЕ делает

Непредставимым состояние сделано **в пределах пакета**, а не схемы: писатель на голом SQL
мимо двери по-прежнему положит одну запись. Держит это сегодня гейт дерева
`TestSubjectCutoffWritersWriteBothRecords`. Предмет — [[KAC/issue-336-kaname]], класс —
[[lessons/invariant-held-by-the-package-not-the-schema]].

## See also

[[resources/iam-minted-token-revocation]] · [[edges/kaname-cutoff-door-vs-schema-writers]] ·
[[resources/iam-human-session]] · [[resources/iam-session-revocation]]

#resource #kacho-iam #iam #internal #migrations
