---
title: corelib-filter
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - filter
---

# corelib/filter

**Path**: `kacho-corelib/filter/`
**Imports**: `fmt`, `strings`
**Imported by**: `kacho-vpc` (10 files — List handlers)

Парсер YC-style filter expressions (`name = "abc" AND labels.env = "prod"`) → AST → SQL `WHERE`.

## Exported types

- `FilterAST struct{ ... }` — root parse-tree.
  - `func Parse(input string, allowedFields []string) (*FilterAST, error)` — парсит выражение, валидирует, что все поля в `allowedFields` (whitelist на handler-стороне).
  - `(*FilterAST).ToSQL(startParam int) (clause string, args []any)` — рендер в pgx-плейсхолдеры `$N`.
- `ParseError struct{ ... }` — позиционная ошибка парсинга (offset, message); конвертируется в `InvalidArgument`.

## Grammar (subset)

- Equality: `field = "value"` / `field != "value"`.
- AND/OR: `a = "x" AND b = "y"`.
- `IN`: `name IN ("a","b","c")`.
- Labels: `labels.key = "value"` (key-path).

## Usage

```go
ast, err := filter.Parse(req.Filter, []string{"name","labels.env","status"})
if err != nil { return errors.InvalidArgument().Field("filter", err.Error()).Build() }
where, args := ast.ToSQL(1)
rows, _ := repo.Query(ctx, "SELECT ... WHERE "+where, args...)
```

## See also

[[corelib-selector]] [[vpc-apps-kacho-api-network]]

#packages #kacho-corelib #filter
