---
title: corelib-backoff
category: packages
repo: kacho-corelib
path: pkg/backoff
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/backoff — обёртка над экспоненциальным backoff

**Каталог**: `pkg/backoff/` · импорт `github.com/PRO-Robotech/kacho/pkg/backoff`
**Прежде** (полирепо): `kacho-corelib/backoff`.
**Импортирует**: `time`, `github.com/cenkalti/backoff/v4`.
**Импортируют** (`go list` на `96b2879a`, non-test): `pkg/retry`, `pkg/operations`,
`pkg/dbready` — **только внутри фундамента**. Ни один сервис не зовёт пакет
напрямую, и это правильная форма: сервисы получают backoff через [[corelib-retry]]
и через воркер операций, а не настраивают его каждый по-своему.

## Экспортируемое API (снято с дерева)

```go
type Backoff        = backoff.BackOff         // алиасы внешней библиотеки
type BackOffContext = backoff.BackOffContext

var Stop        = backoff.Stop                // «больше не повторять»
var WithContext = backoff.WithContext         // context-aware обёртка

func NewConstantBackOff(d time.Duration) Backoff
func ExponentialBackoffBuilder() exponentialBackoffBuilder
```

Билдер: `.WithInitialInterval` · `.WithMultiplier` · `.WithMaxInterval` ·
**`.WithMaxElapsedThreshold`** · `.WithRandomizationFactor` · `.Build()`.
Метод называется `WithMaxElapsedThreshold`, а не `WithMaxElapsedTime` — прежняя
редакция записки называла второе, такого метода в дереве нет.

## `Build()` делает `Reset()` — и это не деталь реализации

Без сброса первый `NextBackOff()` вернул бы дефолт внешней библиотеки (500 мс),
**молча проигнорировав** сконфигурированный начальный интервал. То есть настройка
присутствовала бы, читалась бы в коде и не влияла бы на поведение — ровно тот класс
«форма без содержания», который дороже всего искать. Комментарий у `Build()` это
называет прямо; при правке пакета сброс не убирать.

## См. также

[[corelib-retry]] [[corelib-operations]]

#packages #kacho-corelib
