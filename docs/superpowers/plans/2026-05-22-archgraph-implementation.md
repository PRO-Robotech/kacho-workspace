# archgraph — Implementation Plan

> **For agentic workers:** план kacho-flow: каждый task реализуется через TDD —
> сначала `integration-tester` конвертирует acceptance-сценарии в падающие
> Go-тесты на фикстурах (RED), затем `rpc-implementer` доводит до GREEN.
> Шаги — checkbox (`- [ ]`). Полный тест-код — НЕ здесь (его пишет
> `integration-tester` из acceptance-дока); план — task-уровень.

**Goal:** Собрать CLI-инструмент `archgraph` в `kacho-corelib` — анализатор,
который генерит L3/L4-артефакты документации из кода и блокирующе проверяет
код на полноту/мёртвость/свежесть (C1/C2/C3).

**Architecture:** Go-бинарь `cmd/archgraph` + библиотечные пакеты под
`internal/archgraph/`. Загрузка кода — `golang.org/x/tools/go/packages`,
reachability — `go/callgraph` (RTA). Две подкоманды: `arch-gen` (генерация),
`arch-audit` (проверки). Запускается из корня сервисного репо.

**Tech Stack:** Go 1.25, `golang.org/x/tools` (новая зависимость corelib),
`gopkg.in/yaml.v3` (frontmatter), testify (тесты), фикстуры — синтетические
Go-пакеты в `cmd/archgraph/testdata/`.

**Источники:**
- Spec: `docs/superpowers/specs/2026-05-22-kacho-architecture-vault-design.md`
- Acceptance (APPROVED): `docs/specs/sub-phase-4.0-archgraph-acceptance.md` — 53 сценария `4.0-<group><n>`.

**Репо/ветка:** всё в `project/kacho-corelib/`, ветка `arch-vault-rebuild`.

---

## Design-решения (зафиксированы до кодинга — из ревью acceptance-дока)

1. **L3-артефакт генерится per-L2-note** (по списку `anchors` заметки), не
   per-entry-point. Один entry-point принадлежит ровно одной L2-заметке (C1 это
   гарантирует) → артефакт «call-дерево функциональности» = union reachable-set
   её якорей. (ревью §FORMAT-D1)
2. **Граница scope записи заметок:** `archgraph` пишет `status`/`source_sha` в
   **уже существующие** L2-заметки (`arch-gen`). Генерацию самих скелетов
   заметок `archgraph` НЕ делает — это фаза раскатки (design §7 п.2), отдельный
   план. (ревью §REALISM-G5/H1)
3. **`archgraph:keep` в library-репо — no-op:** library-репо (нет `main`) → C2
   целиком SKIP, аннотация там ни на что не влияет, ошибки не даёт. (ревью §COVERAGE-F5)
4. **Атомарность генерации — per-file:** каждый артефакт пишется temp+rename;
   гарантия — ни один файл не остаётся полузаписанным. Каталог целиком не
   транзакционен. (ревью §FORMAT-I5)

## File Structure

```
project/kacho-corelib/
├── go.mod                              # +require golang.org/x/tools
├── cmd/archgraph/
│   ├── main.go                         # CLI: разбор подкоманд, exit-коды
│   └── testdata/                       # фикстуры — синтетические Go-пакеты (создаёт integration-tester)
├── internal/archgraph/
│   ├── note/note.go                    # frontmatter L2-заметок: parse/write
│   ├── entrypoints/entrypoints.go      # инвентарь entry-points из main-пакетов
│   ├── reach/reach.go                  # call-граф RTA + reachable-set
│   ├── check/c1.go                     # C1 полнота
│   ├── check/c2.go                     # C2 мёртвый код
│   ├── check/c3.go                     # C3 свежесть
│   ├── gen/gen.go                      # генерация L3/L4-артефактов
│   ├── status/status.go                # вычисление status + write-back
│   └── audit/audit.go                  # оркестрация arch-audit: сбор, вывод, exit
└── internal/archgraph/*/*_test.go      # integration-тесты на фикстурах
```

Каждый пакет — одна ответственность, тестируется изолированно на фикстурах.
`cmd/archgraph/main.go` — тонкий: разбор флагов → вызов `audit`/`gen` → exit-код.

---

## Task 0: Ветка и зависимость

**Files:** `project/kacho-corelib/go.mod`, `go.sum`

- [ ] **Step 1:** В `project/kacho-corelib/` — `git checkout -b arch-vault-rebuild` от `main`.
- [ ] **Step 2:** `go get golang.org/x/tools@latest` — добавить зависимость.
- [ ] **Step 3:** Проверить: `go build ./...` зелёный, `go.mod`/`go.sum` обновлены.
- [ ] **Step 4:** Commit: `chore(archgraph): ветка + golang.org/x/tools dependency`.

## Task 1: CLI-каркас `cmd/archgraph` — группа A (5 сценариев)

**Files:** Create `cmd/archgraph/main.go`; Test: `cmd/archgraph/main_test.go`

Покрывает: `4.0-A01`…`4.0-A05` — сборка, usage, две подкоманды,
запуск из корня репо, отказы (неизвестная подкоманда, вне Go-репо, build-ошибка фикстуры).

- [ ] **Step 1:** `integration-tester` — фикстуры группы A + падающие тесты (RED).
- [ ] **Step 2:** Прогнать → подтвердить RED по всем A-сценариям.
- [ ] **Step 3:** `rpc-implementer` — `main.go`: разбор `arch-gen`/`arch-audit`,
      usage в stderr, exit-коды (0 ok / 1 проверка-fail / 2 ошибка-запуска).
- [ ] **Step 4:** Прогнать A-тесты → GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): CLI-каркас и подкоманды (A01-A05)`.

## Task 2: Frontmatter L2-заметок — `internal/archgraph/note` (часть группы H)

**Files:** Create `internal/archgraph/note/note.go`; Test: `note/note_test.go`

Покрывает: `4.0-H05`, `4.0-H06` — сохранение YAML при write-back, битый frontmatter.
Design §4.1.

- [ ] **Step 1:** `integration-tester` — фикстуры .md-заметок + RED-тесты на parse/write.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — структура `Note` (`level`,`repo`,`anchors[]`,
      `status`,`source_sha`), `Parse`/`Write` с сохранением порядка ключей и тела;
      `Parse` битого frontmatter → явная ошибка.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): парсинг frontmatter L2-заметок (H05-H06)`.

## Task 3: Инвентарь entry-points — `internal/archgraph/entrypoints` — группа B (7)

**Files:** Create `internal/archgraph/entrypoints/entrypoints.go`; Test: `entrypoints/entrypoints_test.go`

Покрывает: `4.0-B01`…`4.0-B07` — gRPC `RegisterXxxServer`, мульти-сервис,
воркер/реконсилер/cron ({Run,Start} на результате конструктора), нераспознанный
воркер (edge), library-репо без entry-points, резолв FQN через `ServiceDesc.ServiceName`.
Design §4.2.

- [ ] **Step 1:** `integration-tester` — фикстуры: main с gRPC-регистрацией,
      воркерами, library-пакет; RED-тесты.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — загрузка main-пакетов через `go/packages`;
      детект `RegisterXxxServer` → резолв FQN из строкового литерала
      `ServiceDesc.ServiceName`; детект воркеров (конструктор + `.Run`/`.Start` в main);
      классификация library-репо (нет main).
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): инвентарь entry-points (B01-B07)`.

## Task 4: Call-граф и reachability — `internal/archgraph/reach` — группа C (3)

**Files:** Create `internal/archgraph/reach/reach.go`; Test: `reach/reach_test.go`

Покрывает: `4.0-C01`…`4.0-C03` — RTA от entry-point, вызов через интерфейс,
детерминированная сериализация reachable-set. Design §4.2, §10.

- [ ] **Step 1:** `integration-tester` — фикстуры с вызовами через интерфейс; RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — построение RTA call-графа; reachable-set
      (множество функций + множество файлов) на entry-point; детерминированный
      отсортированный вывод.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): RTA call-граф и reachable-set (C01-C03)`.

## Task 5: Проверка C1 полнота — `internal/archgraph/check/c1.go` — группа E (6)

**Files:** Create `internal/archgraph/check/c1.go`; Test: `check/c1_test.go`

Покрывает: `4.0-E01`…`4.0-E06` — PASS, незаявленный entry-point FAIL,
протухший якорь FAIL, дубль-якорь FAIL, ложный C1 от нераспознанного воркера
(edge), пустой `anchors`. Design §4.3.

- [ ] **Step 1:** `integration-tester` — фикстуры (entry-points + L2-заметки); RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — set-equality: entry-points ⟺ union всех
      `anchors`; каждое расхождение → `Finding` (символ + причина).
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): проверка C1 полнота (E01-E06)`.

## Task 6: Проверка C2 мёртвый код — `internal/archgraph/check/c2.go` — группа F (7)

**Files:** Create `internal/archgraph/check/c2.go`; Test: `check/c2_test.go`

Покрывает: `4.0-F01`…`4.0-F07` — PASS, недостижимый символ FAIL,
`archgraph:keep` подавляет, keep без причины отклоняется, транзитивность keep,
reflection-ложный фейл (edge §10), library-репо SKIP (+ под-кейс: keep в
library-репо — no-op, design-решение #3).

- [ ] **Step 1:** `integration-tester` — фикстуры с unreachable-символами,
      `// archgraph:keep`-аннотациями, library-пакетом; RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — exported-символы не в union reachable-set →
      FAIL; парсинг `// archgraph:keep <причина>` (без причины → отклонить);
      library-репо (нет main) → C2 SKIP целиком.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): проверка C2 мёртвый код (F01-F07)`.

## Task 7: Проверка C3 свежесть — `internal/archgraph/check/c3.go` — группа G (6)

**Files:** Create `internal/archgraph/check/c3.go`; Test: `check/c3_test.go`

Покрывает: `4.0-G01`…`4.0-G06` — PASS, изменённый код FAIL, хеш по
reachable-set а не по репо, детерминизм, пустой `source_sha`, `planned`-заметка
пропускается. Пофайловый хеш (design-решение #4). Design §4.3.

- [ ] **Step 1:** `integration-tester` — фикстуры с заметками + `source_sha`; RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — пофайловый хеш файлов reachable-set якорей
      заметки; сравнение с `source_sha`; mismatch → FAIL; `planned` (нет якорей) → skip.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): проверка C3 свежесть (G01-G06)`.

## Task 8: Генерация L3/L4 — `internal/archgraph/gen` — группа D (6)

**Files:** Create `internal/archgraph/gen/gen.go`; Test: `gen/gen_test.go`

Покрывает: `4.0-D01`…`4.0-D06` — генерация L3/L4 в `docs/arch/generated/`,
нулевой дифф при повторе, обновление при изменении кода, неприкосновенность
курируемых L1/L2, создание каталога, удаление stale-артефактов. L3 — per-L2-note
(design-решение #1); запись temp+rename per-file (design-решение #4).

- [ ] **Step 1:** `integration-tester` — фикстуры (код + L2-заметки); RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — per-L2-note: call-дерево + сигнатуры (L3);
      per-приклад: таблицы типов/полей/config (L4); markdown в
      `docs/arch/generated/`; atomic write; удаление stale; `docs/arch/*.md`
      (курируемые) не трогать.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): генерация L3/L4-артефактов (D01-D06)`.

## Task 9: Вычисление status — `internal/archgraph/status` — группа H (остаток)

**Files:** Create `internal/archgraph/status/status.go`; Test: `status/status_test.go`

Покрывает: `4.0-H01`…`4.0-H04` — вычисление `implemented`/`partial`/`planned`,
write-back во frontmatter, ручная правка ловится `git diff`. Design §4.4.
Write-back только в существующие заметки (design-решение #2).

- [ ] **Step 1:** `integration-tester` — фикстуры с разным состоянием якорей; RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — `implemented` (все якоря достижимы) /
      `partial` (часть отсутствует) / `planned` (якорей нет); write-back через
      пакет `note`.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): вычисляемый status + write-back (H01-H04)`.

## Task 10: Оркестрация `arch-audit` — `internal/archgraph/audit` — группа I (6)

**Files:** Create `internal/archgraph/audit/audit.go`; Modify `cmd/archgraph/main.go`; Test: `audit/audit_test.go`

Покрывает: `4.0-I01`…`4.0-I06` — exit-коды, сбор всех проверок без остановки
на первом FAIL, детерминированный отсортированный вывод, каждая FAIL-строка с
символом+причиной, CI-дрейф-гейт (`arch-gen` + `git diff`). Design §4.3, §6.1.

- [ ] **Step 1:** `integration-tester` — фикстуры с множественными FAIL; RED.
- [ ] **Step 2:** RED подтверждён.
- [ ] **Step 3:** `rpc-implementer` — `audit` запускает C1+C2+C3, собирает все
      `Finding` (не останавливаясь), сортирует, печатает; exit-код = 1 при любом
      FAIL; wiring в `main.go`.
- [ ] **Step 4:** GREEN.
- [ ] **Step 5:** Commit: `feat(archgraph): оркестрация arch-audit (I01-I06)`.

## Task 11: Makefile-цели + финальная сверка — группа J

**Files:** Modify `project/kacho-corelib/Makefile`

Покрывает: `4.0-J01` — двусторонняя трассировка acceptance↔тест.

- [ ] **Step 1:** Добавить цели `arch-gen` / `arch-audit` в `Makefile` corelib
      (для self-test corelib и как шаблон для сервисных репо).
- [ ] **Step 2:** Прогнать `go test ./internal/archgraph/... ./cmd/archgraph/...`
      `-race` → весь набор GREEN.
- [ ] **Step 3:** Сверить: каждый сценарий `4.0-A01`…`4.0-J01` имеет тест с ID в имени.
- [ ] **Step 4:** `golangci-lint run ./...` зелёный.
- [ ] **Step 5:** Commit: `feat(archgraph): Makefile-цели + трассировка (J01)`.

---

## Порядок и зависимости

Task 0 → 1 → 2,3 (параллельно) → 4 (после 3) → 5,9 (после 4) → 6 (после 4) →
7 (после 4) → 8 (после 4,2) → 10 (после 5,6,7) → 11 (последняя).

## Self-Review

- **Spec coverage:** все 53 сценария (A1-J1) распределены по Task 1-11; design
  §3/§4.1/§4.2/§4.3/§4.4/§6.1/§7/§10 — покрыты (см. ссылки в task'ах).
- **Placeholder scan:** плейсхолдеров нет; полный тест-код намеренно делегирован
  `integration-tester` (kacho-flow) — не плейсхолдер, а разделение ролей.
- **Type consistency:** `Finding` (символ+причина) — общий тип результата
  C1/C2/C3, определяется в Task 5, переиспользуется в 6/7/10; `Note` — Task 2,
  переиспользуется в 9. `reachable-set` (функции+файлы) — Task 4, потребляется 6/7/8.
- **Замечания ревью:** 4 design-решения вынесены наверх и привязаны к task'ам.

## После GREEN

`archgraph` работает в `kacho-corelib`. Следующие планы эпика (отдельные циклы):
план 2 — раскатка по сервисам (vpc → iam → compute), план 3 — workspace-агрегация.
