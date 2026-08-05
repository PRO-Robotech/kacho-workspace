---
title: corelib-filter
category: packages
repo: kacho-corelib
path: pkg/filter
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - filter
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/filter — парсер выражения `filter` списочных RPC

**Каталог**: `pkg/filter/` · импорт `github.com/PRO-Robotech/kacho/pkg/filter`
**Прежде** (полирепо): `kacho-corelib/filter`.
**Импортирует**: `fmt`, `regexp`, `strings`, `pgx/v5`.
**Импортируют** (`go list` на `96b2879a`, non-test): storage 3 · vpc 1 · registry 1 ·
nlb 1 · iam 1 · compute 1.

## Грамматика — ОДНО равенство, и это весь язык

```
<field> = "<value>"
```

`<field>` — из whitelist'а вызывающего (текущая фаза — `name`), `<value>` —
строка в двойных кавычках. Пакет прямо объявляет: **поддержка `AND`/`OR`/
`STARTS_WITH`/`IN` отложена.**

> [!warning] Здесь была описана грамматика, которой пакет никогда не имел
> Прежняя редакция обещала `AND`/`OR`, `IN (…)` и путь по меткам
> `labels.key = "value"`, а пример вдобавок звал несуществующие методы билдера
> ошибок. Это утверждение без предмета: контрибьютор, читавший записку, писал бы
> запрос, который парсер отвергает, и искал бы дефект в своём коде. Записка теперь
> называет ровно то, что принимает `Parse`.

## Экспортируемое API (снято с дерева)

```go
func Parse(input string, allowedFields []string) (*FilterAST, error)
func (a *FilterAST) ToSQL(argStartIdx int) (string, []any)
type FilterAST struct{ Field, Op, Value string }   // Op сейчас всегда "="
type ParseError struct{ ... }
func (e *ParseError) Error() string
```

## Формат сообщений об ошибке — фиксирован

```
Bad expression at column N. Unknown field: "<field>"
Bad expression at column N. Expected an operator
Bad expression at column N. Expected a string, integer, date-time or boolean value
```

Тексты — часть контракта (`api-conventions.md` §Error-format): на них опираются
негативные e2e-кейсы. Ошибка разбора уезжает наружу как `InvalidArgument`.

## Подстановка вместо склейки, и защитный quoting поля

`ToSQL` рендерит значение через плейсхолдеры pgx (`$N`), а имя поля дословно
подставлять безопасно только потому, что `Parse` эмитит его из узкого алфавита
(`^[a-zA-Z_][a-zA-Z0-9_.]*$`). Пакет **перепроверяет** это отдельным regex перед
подстановкой: если `FilterAST` собран в обход `Parse` (руками, в тесте, в будущем
коде), поле уходит под quoting, а не в SQL как есть. Это и есть правильная форма
такой защиты — она не полагается на то, что единственный законный производитель
входа останется единственным.

## См. также

[[corelib-validate]] [[vpc-apps-kacho-api-network]]

#packages #kacho-corelib #filter
