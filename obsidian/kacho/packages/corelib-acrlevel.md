---
title: corelib-acrlevel
category: packages
repo: kacho-corelib
path: PRO-Robotech/corelib:acrlevel
layer: shared
status: test
tags:
  - packages
  - kacho-corelib
verified_against: "PRO-Robotech/corelib@227ed2b77b4 (коммит слияния волны 32 в ветку эпика 26), 2026-09-26: acrlevel/acrlevel.go прочитан целиком, экспортированных функций две (Rank, Satisfies); непробных импортёров в модуле два — grpcsrv/acr.go и oauthceremony/logincontext.go (`git grep -l PRO-Robotech/corelib/acrlevel`). В origin/main фундамента (34bc8104a83) пакета нет"
---

# acrlevel — одна таблица ранжирования уровня аутентификации

**Каталог**: `PRO-Robotech/corelib:acrlevel/` · импорт `github.com/PRO-Robotech/corelib/acrlevel`
**Состояние**: пакет есть в ветке эпика `26` фундамента (волна [[KAC/issue-32-corelib|corelib#32]]),
в `main` фундамента его ещё нет — отсюда `status: test`.
**Импортирует**: ничего.
**Импортируют** (непробные, в модуле): `grpcsrv` (устаревшие псевдонимы) и `oauthceremony`
(контекст входа гранта).

## Что даёт

```go
func Rank(acr string) int                       // "" / "0" < "1" < "2" < "3"; незнакомое — 0
func Satisfies(presented, required string) bool // required "" или "0" — требования нет
```

Незнакомое или искажённое значение ранжируется нулём — fail-closed там, где политика ждёт
не меньше единицы. Таблица в модуле одна: правило повышения уровня `grpcsrv.EvaluateStepUp`
берёт ранг отсюда и своей не держит.

## Почему отдельный пакет

Ранжирование — чистая функция, и читают его слои без транспорта: разбор настроек посадки,
use-case службы доступа, контекст входа церемонии. Пока таблица жила в `grpcsrv`, каждый такой
читатель получал ребро на gRPC-сервер ради одной функции. Что транспорт не приезжает и
транзитивно, держит проба `TestRankingPackagePullsNoTransport` рядом с пакетом.

Прежний адрес `grpcsrv.ACRRank` / `grpcsrv.ACRSatisfies` остаётся устаревшими псевдонимами —
[[packages/corelib-grpcsrv]]: путь модуля без суффикса мажорной версии, и снятое имя в минорном
выпуске ломало бы потребителя, поднявшего пин.

## History

- 2026-09-23 — пакет заведён, таблица перенесена из `grpcsrv`
  ([[KAC/issue-49-corelib|corelib#49]]).
- 2026-09-24 — прежний адрес возвращён псевдонимами ([[KAC/issue-64-corelib|corelib#64]]);
  контекст входа гранта церемонии ранжируется отсюда ([[KAC/issue-36-corelib|corelib#36]],
  [[packages/corelib-oauthceremony]]).

#packages #kacho-corelib
