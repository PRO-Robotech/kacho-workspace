---
title: kacho-corelib/cmd/archgraph
category: packages
repo: kacho-corelib
layer: tool
status: implemented
related_tickets: []
tags: [packages, kacho-corelib, archgraph, tooling]
---

# cmd/archgraph + internal/archgraph/* — анализатор архитектуры

CLI-инструмент в `kacho-corelib` (первый `cmd/` в репо — раньше library-only).
Анализатор Go-кода сервисного репо: строит call-граф от entry-points, генерит
документацию L3/L4 и прогоняет три CI-блокирующие проверки. Фундамент эпика
«Architecture Vault» (5-уровневая модель Проект→Приклад→Функциональность→
Функции→Переменные; L0–L2 курируются, L3–L4 генерятся).

## Подкоманды

- `archgraph arch-gen` — генерит `docs/arch/generated/**` (L3 — call-дерево +
  сигнатуры per-L2-note; L4 — domain-типы/поля/константы per-репо), пишет
  вычисленный `status` во frontmatter курируемых L2-заметок.
- `archgraph arch-audit` — прогоняет C1/C2/C3, exit 0/1; CI-гейт.

Exit-коды: `0` ok, `1` проверка FAIL, `2` ошибка запуска. CI-дрейф-гейт свежести
генерата — связка `arch-gen` + `git diff --exit-code` (флага `--check` нет).

## Три проверки (arch-audit)

- **C1 полнота** — каждый entry-point ⟺ ровно один якорь L2-заметки;
  незаявленный entry-point / протухший якорь / дубль → FAIL.
- **C2 мёртвый код** — exported-функция/метод, недостижимая ни от одного
  entry-point → FAIL. Подавление — `// archgraph:keep <причина>` (причина
  обязательна; kept-символ — доп-роут графа). Library-репо (нет `main`) → SKIP.
- **C3 свежесть** — пофайловый хеш reachable-set якорей заметки vs `source_sha`;
  расхождение / пустой source_sha при якорях → FAIL. Хеш скоуплен к файлам
  репо (не deps/stdlib) — детерминизм между машинами.

## Пакеты (импорт-граф — чистый DAG)

```
cli → audit → check → reach → entrypoints
  ├→ gen, status, note (note — лист, только stdlib+yaml.v3)
```

- `entrypoints` — инвентарь entry-points из `main`-пакетов: gRPC по
  `RegisterXxxServer`→`ServiceDesc.ServiceName` (FQN `kacho.cloud.<d>.v1.<Svc>/<M>`),
  воркеры по конвенции `New<Name>`+`Run`/`Start`.
- `reach` — RTA call-граф (`x/tools/go/callgraph/rta`), reachable-set per
  entry-point; root-set = entry-points + kept + все `main`.
- `check` — C1/C2/C3, тип `Finding`/`Result`; `BuildAuditReach` — единый SSA-билд.
- `gen` — генерация L3/L4-артефактов, атомарная запись, stale-removal.
- `status` — вычисление `implemented`/`partial`/`planned`.
- `audit` — оркестрация C1+C2+C3, детерминированный CI-вывод.
- `note` — парсинг/surgical-write YAML-frontmatter L2-заметок.
- `archtest` — фикстур-билдер (тест-инфра, синтетические Go-модули в `t.TempDir()`).

## Известные ограничения (by-design, задокументированы в коде)

- C2 проверяет только exported **функции/методы**, не типы/var/const (мёртвый
  exported-тип без методов не ловится).
- L4 — типы/поля/константы; DB-колонки/config-ключи не извлекаются.
- C3 — пофайловый хеш (правка соседней функции в файле reachable-set протухляет
  заметку — принятый консервативный over-trigger).
- RTA не видит reflection-вызовы (ложный C2 → лечится `archgraph:keep`).

## Конфиг загрузчика

`packages.Config.Env` += `GOTOOLCHAIN=local` + `GOWORK=off` — детерминизм и
независимость от ambient `go.work`.

## Зависимости

`golang.org/x/tools` (`go/packages`,`go/ssa`,`go/callgraph/rta`),
`gopkg.in/yaml.v3`. Без grpc-runtime/pgx.

## Trail

design: `docs/superpowers/specs/2026-05-22-kacho-architecture-vault-design.md`;
acceptance: `docs/specs/sub-phase-4.0-archgraph-acceptance.md` (APPROVED, 53
сценария); план: `docs/superpowers/plans/2026-05-22-archgraph-implementation.md`.
Ветка `arch-vault-rebuild` в `kacho-corelib`.
