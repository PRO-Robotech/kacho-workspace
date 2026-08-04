---
title: corelib-db
category: package
repo: kacho-corelib
path: pkg/db
layer: shared
status: stable
tags:
  - packages
  - kacho-corelib
  - db
  - postgres
---

# pkg/db — пул pgx и транзактор

**Каталог**: `pkg/db/` · импорт `github.com/PRO-Robotech/kacho/pkg/db`
**Прежде** (полирепо): `kacho-corelib/db`.
**Импортирует**: `context`, `strings`, `pgx/v5`, `pgx/v5/pgxpool`.
**Импортируют** (`go list` на `96b2879a`, non-test): по одному пакету в каждом из
семи сервисов — vpc · iam · geo · compute · nlb · storage · registry. Ровно один
потребитель на сервис, потому что пул создаётся в композиционном корне и дальше
раздаётся репозиториям.

## Экспортируемое API (снято с дерева)

```go
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error)
func NewTransactor(p *pgxpool.Pool) *Transactor
func (t *Transactor) InTx(ctx context.Context, fn func(tx pgx.Tx) error) error
type Transactor struct{ ... }

func SSLModeFromDSN(dsn string) string
const DefaultSSLMode = "prefer"
```

> [!warning] Метод транзактора — `InTx`, а не `Do`
> Прежняя редакция описывала `Transactor.Do(ctx, fn func(ctx) error)`, кладущий
> `pgx.Tx` в контекст, и приводила пример, где `outbox.Emit` «подхватывает Tx из
> контекста». Ни того, ни другого в дереве нет: `InTx` передаёт `pgx.Tx`
> **явным аргументом**, и вызываемое внутри пишет через этот аргумент. Разница не
> косметическая — скрытая передача через контекст и есть тот приём, при котором
> «забыли достать транзакцию» выглядит как рабочий код.

## Транзакционный шаблон

```go
err := transactor.InTx(ctx, func(tx pgx.Tx) error {
    if err := repo.CreateNetwork(ctx, tx, n); err != nil { return err }
    return outboxRepo.Emit(ctx, tx, intent)   // тот же tx — атомарность by construction
})
```

Атомарность «строка + намерение в исходящей очереди» держится тем, что оба пишутся
**одним** `tx`. Это несущее свойство для всей материализации прав и для
компенсации саг ([[corelib-outbox]], `data-integrity.md`).

## `SSLModeFromDSN` — не утилита, а часть гейта посадки

Разбор `sslmode` из строки подключения нужен boot-guard'у: в production-режиме
`sslmode=disable` обязан **отказать в старте**. `DefaultSSLMode = "prefer"` — то,
что libpq/pgx применяет, когда режим в строке не задан вовсе; именно поэтому
«параметр не указан» нельзя читать как «шифрование есть».

Отдельно к тому же классу: «под Ready» не является доказательством посадки —
независимое подтверждение шифрования берётся **со стороны БД** (`pg_stat_ssl`), а не
из настроек (`security.md` §Production-mode, п. 2а).

## См. также

[[corelib-outbox]] [[vpc-repo-kacho-pg]] [[corelib-config]]

#packages #kacho-corelib #db #postgres
