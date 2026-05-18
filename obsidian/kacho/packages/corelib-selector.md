---
title: corelib-selector
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - selector
  - planned
---

# corelib/selector

**Path**: `kacho-corelib/selector/`
**Imports**: `encoding/json`, `fmt`, `strings`
**Imported by**: (нет — стандарт ещё не принят сервисами; planned для List handlers)

Структурный builder list-фильтров: pagination + opaque page-token + field selectors → SQL WHERE/ORDER BY/LIMIT.

## Exported types

- `Selector struct{ Field, Op, Value }` — единичный предикат.
- `FieldFilter struct{ ... }` — agregate selectors.
- `PageToken struct{ ... }` — opaque base64-encoded cursor (`json.Marshal` + base64).
- `BuildResult struct{ Where string; Args []any; OrderBy string; Limit int }`.
  - `Build(selectors []Selector) (BuildResult, error)` — от `$1`.
  - `BuildFrom(selectors []Selector, startParam int) (BuildResult, error)` — продолжить с `$N+1`.
- `BuildPageClause(token *PageToken, startParam int) (clause string, args []any)` — `WHERE (key,id) > ($N,$N+1)` для seek-pagination.

## Status

Standalone (test-covered), но handler'ы VPC ещё используют ad-hoc handlers (`vpc-apps-kacho-api-*/list.go`). План — миграция на selector в KAC-94 (skill `evgeniy` rule «list — table-driven с реальной поддержкой filter»).

## See also

[[corelib-filter]] [[vpc-apps-kacho-api-network]]

#packages #kacho-corelib #selector #planned
