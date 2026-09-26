---
title: "kaname#404: согласие и причина consent-withdrawn сняты"
aliases:
  - issue-404-kaname
ticket_id: 404
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - internal/migrations
  - internal/domain
  - internal/repo/kaname/pg
prs:
  - https://github.com/PRO-Robotech/kaname/pull/411
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/404
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - kacho-iam
  - refactor
verified_against: "Перемер 2026-09-26: голова задачи b9dd132dc46 — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`). Сверка 2026-09-24: PRO-Robotech/kaname: голова задачи b9dd132dc46018ef48dac2cd5a6ed758ba7bdd5c (= origin/404) — предок головы сборки 2f45e7c8aa0 и origin/358, не предок origin/357 и origin/main (`git merge-base --is-ancestor`); п.2 предиката перемерен по голове сборки и по origin/358 d22123ba0, 2026-09-24; 2026-09-26: трекер — закрыта 2026-09-26T09:39:10Z, меток status:* нет (`gh issue view`); коммит слияния волны fc9f5aff19c — в origin/357, не в origin/main (`gh api compare`)"
---

# kaname#404: согласие и причина consent-withdrawn сняты

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:39:10Z вместе с волной [[KAC/issue-358-kaname|#358]]: запрос волны PR #422 влит в ветку эпика `357` (координата, не живая ссылка), коммит закрытия — слияние волны `fc9f5aff19c`; метка `status:test` снята, метки сейчас: `P2`, `size:M`, `area:iam`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #357 в ствол.

## Что и зачем

Решение К8 волны 358: первопартийный клиент пропускает согласие по приёмке LINE-A-1, поэтому
дом согласия и значение причины отзыва семейства `consent-withdrawn` снимаются целиком одним
изменением — схема, словарь домена, слой доступа, пробы. Остаток #313.

Применённые миграции не правились (ban #5): снимает новая
`internal/migrations/20260923225650_consent_leaves_the_schema.sql`, её проба схемы —
`consent_leaves_the_schema_integration_test.go`. Запись о снятии таблицы вошла во входной
перечень стража удаления `internal/migrations/dropguard.json` — пятым исключением п.2
предиката (правка тела задачи 2026-09-24).

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `b9dd132dc46018ef48dac2cd5a6ed758ba7bdd5c`; ветка `404` (координата, не живая ссылка) на origin с той же головой |
| коммит слияния в ветке сборки | `ba62d8d8ecd7d039062f8a7fe467edbd1eceb0f2` |
| запрос сборки | PR #411 `408` → `358`, голова `2f45e7c8aa0ebb6a1ec25ff26523cc70e205bb03`, коммит слияния `d22123ba0957625fa791649bd72b6fffd694cfa0` |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD (из тела задачи)

- [x] код и пробы без ссылок на снятое: перепись п.2 предиката с пятью исключениями — **0**
      строк на `2f45e7c8aa0` и на origin/`358` `d22123ba0`; положительный контроль на
      `860078a9` — 45 строк (перемерено мной);
- [x] применённые миграции 175117 и 175119 не тронуты — снимает новая миграция;
- [x] ветка задачи влита в ветку волны `358` коммитом слияния — через сборку 1;
- [x] вердикт головы сборки: 20 заданий, 17 `success`, 3 `skipped`, 0 упавших;
- [ ] проба схемы красна до миграции, секция отката, таблица #339 после посадки — мной не
      перемерялись;
- [x] волна влита в ветку эпика `357` запросом PR #422, коммит слияния `fc9f5aff19c`; голова задачи — его предок;
- [ ] предмет в стволе: изменение доехало до `main` посадкой эпика #357.

## History

- 2026-09-26 — волна #358 влита в ветку эпика `357` запросом PR #422 (`fc9f5aff19c`); в `main` @ `cbbac984b7b` задачи нет, состояние `test` сохраняется.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют ресурс consent_grants (снят), словарь причин token_families и пакеты `internal/migrations` (dropguard.json), `internal/repo/kaname/pg`, `internal/domain`. Записка ресурса семейства заведена этой записью; записки о согласии в хранилище не было.

- [[KAC/issue-358-kaname]] — волна и сборка 1.
- [[resources/iam-token-family]] — словарь причин отзыва без `consent-withdrawn`.

#kac #kacho-iam #refactor
