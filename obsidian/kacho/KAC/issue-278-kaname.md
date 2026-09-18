---
title: "kaname#278: гейт формы ключей судит ДЕЙСТВУЮЩУЮ схему, а не одну базовую миграцию"
aliases:
  - issue-278-kaname
ticket_id: 278
category: kac
status: done
type: fix
repos:
  - kaname
areas:
  - internal/repo/kaname/pg
  - internal/check
prs:
  - PRO-Robotech/kaname#291
issue_url: https://github.com/PRO-Robotech/kaname/issues/278
opened: 2026-09-18
closed: 2026-09-19
tags:
  - kac
  - kacho-iam
  - iam
  - fix
  - migrations
verified_against: "kaname f8fc5a37 (волна «второй фактор Ф11/Ф12/Ф5 + гейты схемы»): `internal/repo/kaname/pg/catalog_key_form_test.go` (+ `catalog_key_form_injection_test.go`) и `internal/check/catalog_seed_parity.go` прочитаны; шапка гейта называет kaname#278 предметом переезда. PR #291, ствол f8fc5a37 и предикат «4/4 тест-функции + 25/25 инъекций» — со слов полосы, лог прогона не пересматривался"
---

# kaname#278: гейт формы ключей судит ДЕЙСТВУЮЩУЮ схему

**Состояние**: done — влит волной, PR kaname#291, ствол `f8fc5a37`.

**PRs**: PRO-Robotech/kaname#291
**Issue**: https://github.com/PRO-Robotech/kaname/issues/278

## Что и зачем

Гейт формы внешних ключей (`RESTRICT … DEFERRABLE`, `INITIALLY DEFERRED`; kacho#1030, приёмка
`rule-segments-have-a-referent.md`, Т1/Т2) читал **одну** базовую миграцию `0001_initial.sql`,
хотя на ревизии переезда миграций было 32. Отсюда две слепоты сразу:

- ключ, заведённый **поздней** миграцией, не судился вовсе — на той ревизии перепись гейта
  считала 42 объявления ключа в базовой миграции при 49 внешних ключах действующей схемы;
- запись ведомости-послабления жила, пока имя стояло в тексте базовой миграции, а применённую
  миграцию не правят (запрет #5): послабление не истекло бы **никогда**.

Гейт переехал в ярус репозитория (`internal/repo/kaname/pg/`) и судит то, что **цепочка
миграций оставляет в базе**: накат всех миграций на живую базу и чтение схемы через
`pg_catalog`. Снятие ключа/индекса, вносимое `DROP COLUMN` (напр. `DROP COLUMN users.account_id`,
который готовит kacho#1351 — неявно уносит `users_account_fk`), теперь распознаётся; прежний
гейт остался бы на нём зелёным, а при снятии записи ведомости вместе с ключом — покраснел бы на
**исправном** дереве.

## Затронутые сущности vault

- [[packages/iam-check]] — откуда гейт уехал (парность каталога seed/copy осталась там).
- [[resources/iam-human-session]], [[resources/iam-user-login-methods]] — примеры ключей поздних
  миграций, которые прежний гейт не видел.

## DoD

- [x] гейт судит действующую схему через `pg_catalog`, а не текст одной миграции
- [x] снятие ключа/индекса через `DROP COLUMN` распознаётся (инъекция)
- [x] предикат прогнан (4/4 тест-функции + 25/25 инъекций — со слов полосы)

## Связанные задачи

- kacho#1030 — приёмка формы ключей (Т1/Т2).
- kacho#1351 — производитель `DROP COLUMN users.account_id`, ради которого слепота и закрыта.

#kac #kacho-iam #iam #fix #migrations
