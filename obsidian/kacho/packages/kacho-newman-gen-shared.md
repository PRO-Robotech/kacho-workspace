---
title: kacho-newman-gen-shared
aliases:
  - общий слой генератора newman
  - gen_shared
category: packages
repo: kacho
path: tests/newman/kacholib
layer: tests
status: stable
related_tickets:
  - "[[issue-1367]]"
tags:
  - packages
  - kacho
  - newman
  - tests
verified_against: "заведён задачей #1367 на ревизии продукта a9be7df26 (2026-08-27); состав переехавшего снят разбором AST по восьми копиям"
---

# Общий слой генератора коллекций newman

**Где живёт**: `tests/newman/kacholib/gen_shared.py` — единственный экземпляр на
дерево. Генераторы наборов (`*/tests/newman/scripts/gen.py`, их восемь) находят
его **вверх от себя**, а не от текущего каталога: генератор зовут из каталога
набора, поэтому путь от cwd был бы свойством того, откуда позвали.

## Что здесь лежит

**19 функций и 11 констант** — сериализация литерала JavaScript (`js_str`,
`js_comment`), разбор порождаемого скрипта (`_strip_js_comments`,
`_js_code_and_literals`), признаки шага (`_writes_env`, `_clears_env`,
`_assigns_env_var`, `_carries_assertion`, `_asserts_done`, `_asserts_outcome`),
утверждения об исходе операции (`_delete_outcome_assert`,
`_published_id_outcome_assert`, `_assert_delete_operation_outcome`),
`_accepted_http_codes`, `_reset_captured_operation_id`.

## Что сюда НЕ переехало и почему

- **16 разошедшихся функций** остались у наборов: `retry_until_authorized`
  (пять версий на шесть копий), `poll_operation_until_done` (шесть на шесть),
  `assert_operation_envelope`, `build_collection`, `step_to_postman`, `main` и
  другие. По каждой нужен вердикт «чья версия верна» — это работа со своей
  приёмкой, а не перенос.
- **`_wrap_own_fresh_reads`** — зовёт `retry_until_authorized` и обязана
  переехать в тот же заход, что и та.
- **`Step`** — модель кейса, у каждого набора своя (восемь различных версий), и
  это законно. Общий слой обращается к ней **по утиному**: только к полям,
  которые есть у всех восьми.

## Чем держится единственность

Гейт `TestNewmanSharedHelperIsDeclaredOnce`
(`internal/repohygiene/artifactgates/newmansharedhelpers_test.go`): имя,
объявленное здесь, не может быть объявлено вторично в генераторе набора. Судит
**обе** формы записи — `def` и верхнеуровневую константу; знавший бы одну,
оставил бы одиннадцать констант вне наблюдения.

## Ловушка для того, кто будет менять состав

Гейты дерева, отбирающие генераторы **по тексту** (`def <имя>`), после переноса
перестают видеть предмет — не красным и не зелёным, а невидимостью. Так вышло с
`TestResponseCodeFormCorpusIsHonoredByEveryNewmanGenerator`; он расширен и знает
теперь обе формы. Перенося сюда следующую функцию, найди всех, кто отбирает
генераторы по её имени.

Связано: [[issue-1367]], [[checks-with-form-but-no-substance]].
