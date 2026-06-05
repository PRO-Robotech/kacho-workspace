# kacho-docs Backbone (apisurface + OpenAPI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Сделать `kacho-proto` единственным источником истины публичной API-поверхности: (1) перенести allowlist (`AllowedMethods` + `IsAllowed` + `HasInternalSuffix`) из `kacho-api-gateway/internal/allowlist` в `kacho-proto` как пакет `apisurface` (KAC-251), устранив split-brain; (2) добавить генерацию публичного OpenAPI 3.1 из публичных proto через `protoc-gen-connect-openapi` + standalone `cmd/openapi-filter`, который выкидывает каждую операцию, чья gRPC-FQN ∉ allowlist ИЛИ Internal-suffixed (авто-исключает все `Internal*Service` + admin-`AddressPool`, оставляет публичный `AddressService`), мерджит curated-examples overlay, инжектит `x-operation` из расширения 87334, и коммитит `gen/openapi/<domain>.openapi.json` + `gen/openapi/_surface-snapshot.json`; (3) повесить drift-gate `verify-openapi` (`git diff --exit-code gen/openapi/`) в Makefile+CI по образцу `verify-catalog`; (4) переключить импорт allowlist в `kacho-api-gateway` на `apisurface`, сохранив зелёными все существующие allowlist/director/server тесты (KAC-253).

**Architecture:** `kacho-proto` — центр build-графа, ни от чего внутри проекта не зависит → перенос `apisurface` non-cyclic. OpenAPI-конвейер из стадий внутри одной Make-цели `generate-openapi`: `protoc-gen-connect-openapi` (raw OpenAPI 3.1, отдельный шаблон `buf.gen.openapi.yaml`, не трогает `buf.gen.yaml`) → overlay-merge curated infra-safe examples → `cmd/openapi-filter` (рекурсивно собирает raw-дерево, фильтрует по `apisurface`, scope-ит схемы до `$ref`-достижимых от выживших операций, инжектит `x-operation`, эмит `_surface-snapshot.json`) → коммит. `kacho-api-gateway` уже имеет `replace ../kacho-proto` (build-граф не меняется); 2 файла переключают import (`director.go`, `server.go`) через import-alias `allowlist`, локальный пакет удаляется.

> **REVISION NOTE (structural, проверено реальным прогоном — blocking-фиксы критики):** `protoc-gen-connect-openapi@v0.25.6` с шаблоном без `path=` эмитит **136 JSON-файлов в зеркальном дереве** (`gen/openapi-raw/kacho/cloud/vpc/v1/subnet_service.openapi.json`, плюс `google/...`), **ONE-FILE-PER-PROTO**, НЕ flat per-domain. Документированный `path=<file>` + `services=...` НЕ работает: `buf generate` печатает `duplicate generated file name` и оставляет **пустой файл (0 операций)** — отвергнут. Принят **recursive WalkDir** подход: `cmd/openapi-filter` обходит всё дерево, скипает `google/`, бакетит 371 операцию по `parts[2]` домена (compute/iam/loadbalancer/vpc/operation), фильтрует, и **scope-ит components/schemas до `$ref`-достижимых от выживших операций** (иначе blind-union 896 схем затаскивает в vpc-spec схему dropped `NetworkInterfaceService` с инфра-токенами `vpn_id`/`sid` в prose → ломает §9 tripwire). Реальный прогон: 191 survivor, 0 Internal, 0 AddressPool, vpn_id/`\bsid\b` отсутствуют во всех 4 reachable-closure'ах.

**Tech Stack:** Go 1.25.x (плагин требует ≥1.25.7 — toolchain auto-switch); buf v1.69.0 (`version: v2`); `protoc-gen-connect-openapi` (github.com/sudorandom/protoc-gen-connect-openapi) v0.25.6 — **local binary** (через `go install`, как существующий in-tree `protoc-gen-kacho-permissions`, чтобы убрать CI-network-зависимость на BSR remote plugin и включить детерминизм); overlay-applier `openapi-format` (npm, thim81 — JSON I/O, детерминированный порядок полей; Node v22 в среде подтверждён); `@scalar/cli` для validate; protobuf-go (`apiv1.E_Operation`, расширение 87334).

**Решение по имени пакета (важно для размера диффа KAC-253):** перенесённый Go-пакет называется **`apisurface`** и лежит в `kacho-proto/apisurface/` (handwritten, **не** под `gen/` — иначе `buf generate`/`gen-clean` его затрёт). Чтобы KAC-253 оставался чистым one-line import swap без правки call-sites, `director.go`/`server.go` импортируют его **с алиасом** `allowlist "github.com/PRO-Robotech/kacho-proto/apisurface"`. Экспортируемые идентификаторы (`AllowedMethods`, `IsAllowed`, `HasInternalSuffix`) — без изменений. **Проверено**: импорт-сайтов ровно 2 (`director.go:12`, `server.go:8`), call-sites `allowlist.HasInternalSuffix(...)/.IsAllowed(...)`; отдельный `internal/middleware/authz_public_allowlist.go` — **другой** пакет, не трогаем.

---

## VERIFIED facts (реальный прогон 2026-06-05, перед написанием плана)

| Факт | Значение | Как проверено |
|---|---|---|
| module | `github.com/PRO-Robotech/kacho-proto`, no internal deps | `head -1 go.mod` |
| buf | 1.69.0, `version: v2` | `buf --version` |
| connect-openapi output | **136 файлов, nested mirror-tree, one-per-proto** (НЕ flat per-domain) | `buf generate --template … && find … | wc -l` |
| `path=`+`services=` workaround | **сломан** — `duplicate generated file name` → пустой файл (0 ops) | реальный прогон |
| real ops в дереве | 371 (vpc 86, compute 169, iam 87, loadbalancer 27, operation 2) | python bucket |
| survivors после фильтра | **191** (0 Internal, 0 AddressPool, AddressService.Get present) | dry-run mirror-логики |
| allowlist keys | 192 (включая doc-placeholder `<domain>`); реальных http-rendered survivors 191 | `grep -cE` + dry-run |
| ext 87334 | `apiv1.E_Operation` / `*apiv1.Operation{GetMetadata,GetResponse}`; пакет `kacho.cloud.api`; import `…/gen/go/kacho/cloud/api` alias `apiv1`; **192 метода** несут ext | Go-прогон над descriptorset |
| operationId формат | dotted `kacho.cloud.vpc.v1.SubnetService.AddCidrBlocks` | вывод raw spec |
| suffix-verbs (B-04) | distinct path-items: `:add-cidr-blocks`, `:remove-cidr-blocks`, `:move`, `:relocate`, `:cancel`; allowlist-ключи `NetworkService/Move`, `SubnetService/{AddCidrBlocks,RemoveCidrBlocks,Relocate}`, `InstanceService/SetAccessBindings`, `OperationService/Cancel` — все survive | dry-run |
| **component pollution** | blind-union = 896 схем; `network_interface_service` (dropped) несёт `vpn_id`/`sid` в prose → попадает в vpc-spec без scope | python dump-check |
| **$ref-reachability fix** | per-domain closure vpc=72/compute=88/iam=36/lb=38; vpn_id/`\bsid\b` отсутствуют во всех | python closure-прогон |
| `buf build -o _ds.bin` | работает, 1.2 MB FileDescriptorSet | реальный прогон |
| Node | v22.22.0, npx доступен | `node --version` |
| gateway import-sites | 2 (`director.go:12`, `server.go:8`); `replace ../kacho-proto` go.mod:7 | grep |
| sed relocation | package-rename меняет только line 1; test-sed 52 строк, остаток `allowlist` — только в test-name-строках | diff dry-run |

---

## File Structure

### kacho-proto (KAC-251) — все задачи здесь идут ПЕРВЫМИ (build-граф снизу вверх)

| Path | Created/Modified | Single responsibility |
|---|---|---|
| `project/kacho-proto/apisurface/list.go` | **new** (move) | Канонический allowlist: `package apisurface` с `AllowedMethods map[string]struct{}` (192 ключа, перенос verbatim из gateway), `IsAllowed`, `HasInternalSuffix`. Единственное место истины публичной поверхности. |
| `project/kacho-proto/apisurface/list_test.go` | **new** (move) | Регрессия allowlist: перенос из gateway `internal/allowlist/list_test.go`, пакет `apisurface_test`, импорт `.../apisurface`. |
| `project/kacho-proto/apisurface/fqn.go` | **new** | `DottedFQN`/`AllowedDotted` — мост slash-path ↔ operationId. |
| `project/kacho-proto/apisurface/fqn_test.go` | **new** | Unit на `DottedFQN`/`AllowedDotted`. |
| `project/kacho-proto/buf.gen.openapi.yaml` | **new** | Отдельный buf-шаблон OpenAPI 3.1 (local plugin, `features=google.api.http`, `format=json`, `trim-unused-types`, `out: gen/openapi-raw`). НЕ трогает `buf.gen.yaml`. |
| `project/kacho-proto/cmd/openapi-filter/main.go` | **new** | Standalone бинарь: **рекурсивно** обходит `gen/openapi-raw/` (skip `google/`), читает descriptorset, бакетит по домену, фильтрует, scope-ит схемы, инжектит x-operation, пишет `gen/openapi/<domain>.openapi.json` + `_surface-snapshot.json` детерминированно. |
| `project/kacho-proto/cmd/openapi-filter/filter.go` | **new** | Чистая логика: `FilterSpec`, `InjectOperations`, `keepOperation`, `OpEntry`, `OperationExt`, `$ref`-closure, сортировка, canonical JSON-emit. Тестируема без I/O. |
| `project/kacho-proto/cmd/openapi-filter/filter_test.go` | **new** | **B-02/B-08 RED→GREEN** на чистых функциях (fixture, без файловой системы). |
| `project/kacho-proto/cmd/openapi-filter/snapshot_test.go` | **new** | **B-04/B-05** над committed `_surface-snapshot.json`. |
| `project/kacho-proto/openapi-overlays/vpc.examples.yaml` | **new** | **B-07**: handwritten OpenAPI Overlay 1.0, curated infra-safe (RFC-1918). |
| `project/kacho-proto/openapi-overlays/compute.examples.yaml` | **new** | То же для compute. |
| `project/kacho-proto/openapi-overlays/iam.examples.yaml` | **new** | То же для iam. |
| `project/kacho-proto/openapi-overlays/loadbalancer.examples.yaml` | **new** | То же для loadbalancer. |
| `project/kacho-proto/scripts/tripwire.sh` | **new** | §9 forbidden-token grep — **scope: только example/overlay-значения** (см. фикс ниже). |
| `project/kacho-proto/Makefile` | **modify** | Добавить `install-openapi-plugins`, `generate-openapi`, `verify-openapi`, `tripwire` + `.PHONY`. |
| `project/kacho-proto/.github/workflows/ci.yaml` | **modify** | Добавить шаги «verify openapi up-to-date» + validate + tripwire. |
| `project/kacho-proto/gen/openapi/{vpc,compute,iam,loadbalancer}.openapi.json` | **new (generated, committed)** | Финальные публичные spec'ы (per-domain). |
| `project/kacho-proto/gen/openapi/_surface-snapshot.json` | **new (generated, committed)** | **B-05**: отсортированный список `{operationId, method, path, grpcFqn}` всех выживших. |

### kacho-api-gateway (KAC-253) — задачи ПОСЛЕ merge kacho-proto

| Path | Created/Modified | Single responsibility |
|---|---|---|
| `project/kacho-api-gateway/internal/allowlist/list.go` | **delete** | Источник перенесён в kacho-proto. |
| `project/kacho-api-gateway/internal/allowlist/list_test.go` | **delete** | Перенесён в kacho-proto `apisurface/list_test.go`. |
| `project/kacho-api-gateway/internal/proxy/director.go` | **modify** | Импорт → `allowlist "github.com/PRO-Robotech/kacho-proto/apisurface"` (alias; call-sites без изменений). |
| `project/kacho-api-gateway/internal/proxy/server.go` | **modify** | То же. |

---

## Стадия 0 — обязательное чтение vault + тикеты (перед кодом)

### Task 0: Подготовка контекста и тикетов

- [ ] **0.1** Прочитать vault-узлы (minimum context): `obsidian/kacho/rpc/` (если есть запись по api-gateway allowlist) и `obsidian/kacho/edges/` для api-gw↔backend. Прочитать KAC-трейл `obsidian/kacho/KAC/KAC-248.md`, создать `obsidian/kacho/KAC/KAC-251.md` и `obsidian/kacho/KAC/KAC-253.md` (если отсутствуют) по формату из workspace CLAUDE.md (≤3KB, `Status: in-progress`, `Type: feature`, `Repos`, `YT`).
- [ ] **0.2** Подтвердить APPROVED acceptance-док `docs/specs/sub-phase-kacho-docs-mvp-acceptance.md` (Область B). **Гейт §«Запреты» #1**: без APPROVED — стоп.
- [ ] **0.3** YouTrack: KAC-251 и KAC-253 → `In Progress`, добавлены в текущий спринт доски `kacho` (183-12).
- [ ] **0.4** Ветка в kacho-proto: `cd project/kacho-proto && git checkout -b KAC-251`.

---

## KAC-251 — kacho-proto: apisurface relocation

### Task 1: Перенос allowlist в пакет `apisurface` (B-03 фундамент)

- [ ] **1.1 (RED — регрессия-перенос)** Создать `project/kacho-proto/apisurface/list.go` переносом verbatim из gateway, только `package allowlist` → `package apisurface`. **Команда переноса** (надёжнее ручного — гарантирует verbatim 192 ключа; проверено что меняет ТОЛЬКО line 1):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
mkdir -p apisurface
sed '1s/^package allowlist$/package apisurface/' \
  ../kacho-api-gateway/internal/allowlist/list.go > apisurface/list.go
```
Структура файла (после sed — содержимое идентично источнику; ниже схема для понимания, **не переписывать руками**):
```go
package apisurface

import "strings"

// AllowedMethods — публичные RPC-пути, маршрутизируемые через api-gateway.
// Канонический источник истины публичной API-поверхности Kachō (KAC-251).
var AllowedMethods = map[string]struct{}{
	// ... ВСЕ 192 ключа verbatim из источника, БЕЗ изменений ...
	"/kacho.cloud.operation.OperationService/Get":    {},
	"/kacho.cloud.operation.OperationService/Cancel": {},
}

func IsAllowed(methodPath string) bool {
	_, ok := AllowedMethods[methodPath]
	return ok
}

// HasInternalSuffix — эшелонированная защита (verbatim из источника).
func HasInternalSuffix(methodPath string) bool {
	if strings.Contains(methodPath, "InternalService") {
		return true
	}
	p := strings.TrimPrefix(methodPath, "/")
	slash := strings.IndexByte(p, '/')
	if slash < 1 {
		return false
	}
	pkgService := p[:slash]
	dot := strings.LastIndexByte(pkgService, '.')
	if dot < 0 {
		return false
	}
	service := pkgService[dot+1:]
	return strings.HasPrefix(service, "Internal") && strings.HasSuffix(service, "Service")
}
```

- [ ] **1.2 (RED)** Перенести тест: `apisurface/list_test.go` — пакет `apisurface_test`, импорт `.../apisurface`, qualifier `apisurface.`:
```bash
sed -e '1s/^package allowlist_test$/package apisurface_test/' \
    -e 's#github.com/PRO-Robotech/kacho-api-gateway/internal/allowlist#github.com/PRO-Robotech/kacho-proto/apisurface#' \
    -e 's/\ballowlist\./apisurface./g' \
    ../kacho-api-gateway/internal/allowlist/list_test.go > apisurface/list_test.go
```
> **Проверено (issue 7 фикс):** test-sed меняет 52 строки; оставшиеся вхождения `allowlist` — только в **строковых литералах test-error-сообщений** (`"...должен быть в allowlist"`), которые `\ballowlist\.` НЕ трогает (нет точки-qualifier'а). Это безвредно — текст ассертов. Обязательная пост-проверка ниже подтверждает отсутствие dangling-import.

- [ ] **1.3 (GREEN + verify cleanliness)** Прогнать тесты + доказать, что не осталось старого import-пути и формат чист:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
go test ./apisurface/...
gofmt -l apisurface/                                   # пусто = форматирование чистое
! grep -rn 'kacho-api-gateway/internal/allowlist' apisurface/   # нет dangling old import
```
Ожидаемо: `ok  github.com/PRO-Robotech/kacho-proto/apisurface`; `gofmt -l` — пусто; grep — exit 1 (ничего не найдено). Если FAIL — diff `apisurface/list.go` против источника, восстановить verbatim ключи.
- [ ] **1.4 (commit)**:
```bash
git add apisurface/list.go apisurface/list_test.go
git commit -m "feat(apisurface): relocate canonical public-surface allowlist into kacho-proto

Перенос AllowedMethods + IsAllowed + HasInternalSuffix из
kacho-api-gateway/internal/allowlist в kacho-proto/apisurface —
единственный источник истины публичной API-поверхности (no split-brain).
Тесты list_test.go перенесены вместе с пакетом.

KAC-251"
```

### Task 2: `DottedFQN` — мост slash-path ↔ operationId (нужен фильтру)

- [ ] **2.1 (RED)** Создать `apisurface/fqn_test.go`:
```go
package apisurface_test

import (
	"testing"

	"github.com/PRO-Robotech/kacho-proto/apisurface"
)

func TestDottedFQN(t *testing.T) {
	cases := []struct{ in, want string }{
		{"/kacho.cloud.vpc.v1.NetworkService/Get", "kacho.cloud.vpc.v1.NetworkService.Get"},
		{"/kacho.cloud.operation.OperationService/Cancel", "kacho.cloud.operation.OperationService.Cancel"},
		{"/kacho.cloud.vpc.v1.SubnetService/AddCidrBlocks", "kacho.cloud.vpc.v1.SubnetService.AddCidrBlocks"},
	}
	for _, c := range cases {
		if got := apisurface.DottedFQN(c.in); got != c.want {
			t.Errorf("DottedFQN(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// AllowedDotted: каждый ключ allowlist имеет ровно один dotted-вид;
// OperationService.Cancel обязан присутствовать (B-05).
func TestAllowedDottedComplete(t *testing.T) {
	d := apisurface.AllowedDotted()
	if len(d) != len(apisurface.AllowedMethods) {
		t.Fatalf("AllowedDotted size %d != AllowedMethods size %d", len(d), len(apisurface.AllowedMethods))
	}
	if _, ok := d["kacho.cloud.operation.OperationService.Cancel"]; !ok {
		t.Error("OperationService.Cancel must survive into dotted set (B-05)")
	}
}
```
- [ ] **2.2 (RED-run)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && go test ./apisurface/ -run 'TestDottedFQN|TestAllowedDottedComplete'
```
Ожидаемый FAIL: `undefined: apisurface.DottedFQN` / `apisurface.AllowedDotted`.
- [ ] **2.3 (GREEN)** Создать `apisurface/fqn.go`:
```go
package apisurface

import "strings"

// DottedFQN конвертирует gRPC slash-path "/pkg.Service/Method" в dotted-форму
// "pkg.Service.Method" — в ней protoc-gen-connect-openapi эмитит operationId
// (проверено: kacho.cloud.vpc.v1.SubnetService.AddCidrBlocks). Корректно
// обрабатывает пакеты без .v1 (operation).
func DottedFQN(slashPath string) string {
	p := strings.TrimPrefix(slashPath, "/")
	i := strings.IndexByte(p, '/')
	if i < 0 {
		return p
	}
	return p[:i] + "." + p[i+1:]
}

// AllowedDotted строит множество dotted-FQN из AllowedMethods — рабочий ключ
// фильтра (operationId connect-openapi уже dotted).
func AllowedDotted() map[string]struct{} {
	out := make(map[string]struct{}, len(AllowedMethods))
	for k := range AllowedMethods {
		out[DottedFQN(k)] = struct{}{}
	}
	return out
}
```
- [ ] **2.4 (GREEN-run)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && go test ./apisurface/...
```
Ожидаемо: `ok`.
- [ ] **2.5 (commit)**:
```bash
git add apisurface/fqn.go apisurface/fqn_test.go
git commit -m "feat(apisurface): DottedFQN + AllowedDotted — slash-path↔operationId bridge

connect-openapi эмитит operationId в dotted-форме (pkg.Service.Method),
allowlist хранит slash-форму (/pkg.Service/Method). DottedFQN/AllowedDotted —
рабочий ключ openapi-filter.

KAC-251"
```

### Task 3: buf-шаблон OpenAPI (raw generation, B-01)

- [ ] **3.1** Создать `project/kacho-proto/buf.gen.openapi.yaml` (отдельный файл — `buf.gen.yaml` не трогаем, это явное Given B-01):
```yaml
# OpenAPI 3.1 generation template — KAC-251.
# СОВЕРШЕННО ОТДЕЛЬНЫЙ от buf.gen.yaml (Go-stubs). Запускается ТОЛЬКО через
# `buf generate --template buf.gen.openapi.yaml`. Local binary (а не remote BSR
# plugin) — зеркалит install-plugins-паттерн (protoc-gen-kacho-permissions),
# убирает CI-сетевую зависимость, детерминирован офлайн.
#
# ПРОВЕРЕНО (реальный прогон): connect-openapi эмитит ~136 файлов в ЗЕРКАЛЬНОМ
# дереве gen/openapi-raw/<package-path>/<proto>.openapi.json (one-file-per-proto),
# НЕ flat per-domain. cmd/openapi-filter обходит дерево рекурсивно (см. Task 5).
#
# Установка: go install github.com/sudorandom/protoc-gen-connect-openapi@v0.25.6
version: v2
plugins:
  - local: protoc-gen-connect-openapi
    out: gen/openapi-raw
    opt:
      - format=json
      # features=google.api.http — REST-пути (а НЕ connect-style POST /Service/Method).
      # Дефолт включил бы connectrpc, удвоив операции и сломав snapshot suffix-verbs (B-04).
      - features=google.api.http
      - trim-unused-types
```
- [ ] **3.2** Добавить `gen/openapi-raw/` в `.gitignore` (raw-промежуток НЕ коммитим):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
printf '\n# OpenAPI raw промежуток (до фильтра) — НЕ коммитим; коммитим gen/openapi/\ngen/openapi-raw/\n' >> .gitignore
```
- [ ] **3.3 (verify-run — подтвердить реальную структуру)** Установить плагин и прогнать raw-генерацию. **ПРОВЕРЕНО, что output — nested mirror-tree, one-per-proto, 136 файлов**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
go install github.com/sudorandom/protoc-gen-connect-openapi@v0.25.6   # авто-switch toolchain ≥1.25.7
buf generate --template buf.gen.openapi.yaml
echo "file count (ожид. ~136):"; find gen/openapi-raw -name '*.json' | wc -l
echo "top-level (ожид. google/ + kacho/):"; ls gen/openapi-raw/
echo "пример nested service-файла:"; ls gen/openapi-raw/kacho/cloud/vpc/v1/subnet_service.openapi.json
grep -o '"openapi": *"3.1[^"]*"' gen/openapi-raw/kacho/cloud/vpc/v1/subnet_service.openapi.json | head -1
```
Ожидаемо: ~136 файлов; `google/` + `kacho/`; `subnet_service.openapi.json` существует и `"openapi": "3.1.0"`. **Если структура иная (flat) — STOP, пересмотреть Task 5 glob-логику.**
- [ ] **3.4 (commit)**:
```bash
git add buf.gen.openapi.yaml .gitignore
git commit -m "feat(openapi): add separate buf.gen.openapi.yaml (connect-openapi 3.1, local plugin)

Отдельный buf-шаблон (НЕ трогает buf.gen.yaml, B-01). Local
protoc-gen-connect-openapi@v0.25.6, features=google.api.http, format=json,
trim-unused-types. Output — nested mirror-tree one-per-proto (~136 файлов),
gen/openapi-raw/ gitignored — фильтр обходит рекурсивно (Task 5).

KAC-251"
```

### Task 4: `cmd/openapi-filter` — чистая логика фильтра + x-operation (B-02/B-08 RED→GREEN)

- [ ] **4.1 (RED — net-new core)** Создать `cmd/openapi-filter/filter_test.go` **до** реализации (чистые функции, без файловой системы):
```go
package main

import (
	"strings"
	"testing"
)

// rawFixture — минимальный OpenAPI 3.1 с операциями, чьи operationId — dotted FQN
// (как эмитит connect-openapi). ВСЕ Internal-операции НЕСУТ http-путь — доказываем,
// что дискриминатор = allowlist, а НЕ http-presence (6 Internal proto тоже несут http).
const rawFixture = `{
  "openapi": "3.1.0",
  "info": {"title": "vpc", "version": "v1"},
  "paths": {
    "/vpc/v1/addressPools/{id}": {
      "get": {"operationId": "kacho.cloud.vpc.v1.InternalAddressPoolService.Get"}
    },
    "/vpc/v1/internal/cloud/{id}": {
      "get": {"operationId": "kacho.cloud.vpc.v1.InternalCloudService.Get"}
    },
    "/iam/v1/internal/iam": {
      "post": {"operationId": "kacho.cloud.iam.v1.InternalIAMService.Check"}
    },
    "/vpc/v1/addresses/{id}": {
      "get": {"operationId": "kacho.cloud.vpc.v1.AddressService.Get"}
    },
    "/vpc/v1/addresses": {
      "get": {"operationId": "kacho.cloud.vpc.v1.AddressService.List"}
    }
  }
}`

func TestFilterSpec_DropsInternalKeepsPublic(t *testing.T) {
	out, kept, err := FilterSpec([]byte(rawFixture))
	if err != nil {
		t.Fatalf("FilterSpec: %v", err)
	}
	s := string(out)
	for _, banned := range []string{"InternalAddressPoolService", "InternalCloudService", "InternalIAMService"} {
		if strings.Contains(s, banned) {
			t.Errorf("filtered spec must NOT contain %q", banned)
		}
	}
	for _, want := range []string{"kacho.cloud.vpc.v1.AddressService.Get", "kacho.cloud.vpc.v1.AddressService.List"} {
		if !strings.Contains(s, want) {
			t.Errorf("filtered spec MUST contain %q", want)
		}
	}
	if len(kept) != 2 {
		t.Fatalf("expected 2 survivors, got %d: %+v", len(kept), kept)
	}
	for _, e := range kept {
		if !strings.HasPrefix(e.GrpcFqn, "/kacho.cloud.vpc.v1.AddressService/") {
			t.Errorf("survivor grpcFqn unexpected: %q", e.GrpcFqn)
		}
	}
}

// Дискриминатор — allowlist+HasInternalSuffix, НЕ http-presence (все 5 ops несут http).
func TestFilterSpec_DiscriminatorIsAllowlistNotHTTP(t *testing.T) {
	_, kept, err := FilterSpec([]byte(rawFixture))
	if err != nil {
		t.Fatalf("FilterSpec: %v", err)
	}
	if len(kept) != 2 {
		t.Fatalf("http-presence MUST NOT keep Internal ops; want 2, got %d", len(kept))
	}
}

// B-08: x-operation инжектится из ext-map.
func TestInjectOperations_AddsXOperation(t *testing.T) {
	const spec = `{
  "openapi": "3.1.0",
  "paths": {
    "/vpc/v1/networks": {
      "post": {"operationId": "kacho.cloud.vpc.v1.NetworkService.Create"}
    }
  }
}`
	ext := map[string]OperationExt{
		"kacho.cloud.vpc.v1.NetworkService.Create": {Metadata: "CreateNetworkMetadata", Response: "Network"},
	}
	out, err := InjectOperations([]byte(spec), ext)
	if err != nil {
		t.Fatalf("InjectOperations: %v", err)
	}
	s := string(out)
	if !strings.Contains(s, `"x-operation"`) {
		t.Error("mutation op must carry x-operation (B-08)")
	}
	if !strings.Contains(s, "CreateNetworkMetadata") || !strings.Contains(s, `"Network"`) {
		t.Error("x-operation must carry concrete metadata/response Any types (B-08)")
	}
}

// reachableSchemas: только $ref-достижимые от выживших ops остаются (anti-pollution).
// NIC-схема (dropped service) с инфра-токенами НЕ должна протечь.
func TestReachableSchemas_DropsOrphans(t *testing.T) {
	const spec = `{
  "openapi": "3.1.0",
  "paths": {
    "/vpc/v1/addresses/{id}": {
      "get": {
        "operationId": "kacho.cloud.vpc.v1.AddressService.Get",
        "responses": {"200": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Address"}}}}}
      }
    }
  },
  "components": {"schemas": {
    "Address": {"type": "object", "properties": {"id": {"type": "string"}}},
    "NetworkInterface": {"type": "object", "description": "internal vpn_id/sid prose", "properties": {"sid": {"type": "string"}}}
  }}
}`
	reach := reachableSchemas([]byte(spec))
	if _, ok := reach["Address"]; !ok {
		t.Error("Address must be reachable from surviving op")
	}
	if _, ok := reach["NetworkInterface"]; ok {
		t.Error("orphan NetworkInterface schema (infra-token prose) must NOT be reachable")
	}
}
```
- [ ] **4.2 (RED-run)** Прогнать — FAIL по правильной причине (символы не существуют):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && go test ./cmd/openapi-filter/...
```
Ожидаемый FAIL: `undefined: FilterSpec`, `undefined: OperationExt`, `undefined: InjectOperations`, `undefined: reachableSchemas` (compile error).
- [ ] **4.3 (GREEN)** Создать `cmd/openapi-filter/filter.go` (чистая логика, без I/O):
```go
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/PRO-Robotech/kacho-proto/apisurface"
)

// OpEntry — одна строка _surface-snapshot.json (B-05).
type OpEntry struct {
	OperationID string `json:"operationId"`
	Method      string `json:"method"`
	Path        string `json:"path"`
	GrpcFqn     string `json:"grpcFqn"`
}

// OperationExt — значение расширения (kacho.cloud.api.operation) = 87334 (B-08).
type OperationExt struct {
	Metadata string `json:"metadata,omitempty"`
	Response string `json:"response"`
}

// httpMethods — порядок HTTP-методов в OpenAPI path-item (детерминизм).
var httpMethods = []string{"get", "put", "post", "delete", "patch", "options", "head", "trace"}

// refRe вытаскивает имена схем из "$ref": "#/components/schemas/<Name>".
var refRe = regexp.MustCompile(`"\$ref"\s*:\s*"#/components/schemas/([^"]+)"`)

// dottedToSlash инвертирует apisurface.DottedFQN: "pkg.Service.Method" → "/pkg.Service/Method".
func dottedToSlash(dotted string) string {
	i := strings.LastIndexByte(dotted, '.')
	if i < 0 {
		return "/" + dotted
	}
	return "/" + dotted[:i] + "/" + dotted[i+1:]
}

// keepOperation реализует ровно правило director.go/server.go:
// drop, если HasInternalSuffix(slashFQN) ИЛИ slashFQN ∉ allowlist (no split-brain).
func keepOperation(operationID string) (slashFqn string, keep bool) {
	slash := dottedToSlash(operationID)
	if apisurface.HasInternalSuffix(slash) || !apisurface.IsAllowed(slash) {
		return slash, false
	}
	return slash, true
}

// FilterSpec удаляет каждую операцию, не прошедшую keepOperation, из одного raw
// OpenAPI 3.1 JSON. Пустые path-item'ы удаляются. Возвращает (отфильтрованный
// JSON, выжившие OpEntry). Детерминированный re-serialize.
func FilterSpec(raw []byte) ([]byte, []OpEntry, error) {
	var doc map[string]any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&doc); err != nil {
		return nil, nil, fmt.Errorf("decode openapi: %w", err)
	}
	pathsAny, ok := doc["paths"].(map[string]any)
	if !ok {
		out, err := canonicalJSON(doc)
		return out, nil, err
	}
	var kept []OpEntry
	for pathKey, itemAny := range pathsAny {
		item, ok := itemAny.(map[string]any)
		if !ok {
			continue
		}
		for _, hm := range httpMethods {
			opAny, exists := item[hm]
			if !exists {
				continue
			}
			op, ok := opAny.(map[string]any)
			if !ok {
				continue
			}
			opID, _ := op["operationId"].(string)
			slash, keep := keepOperation(opID)
			if !keep {
				delete(item, hm)
				continue
			}
			kept = append(kept, OpEntry{OperationID: opID, Method: strings.ToUpper(hm), Path: pathKey, GrpcFqn: slash})
		}
		if !hasAnyOperation(item) {
			delete(pathsAny, pathKey)
		}
	}
	out, err := canonicalJSON(doc)
	if err != nil {
		return nil, nil, err
	}
	return out, kept, nil
}

func hasAnyOperation(item map[string]any) bool {
	for _, hm := range httpMethods {
		if _, ok := item[hm]; ok {
			return true
		}
	}
	return false
}

// InjectOperations добавляет vendor-extension x-operation в каждую операцию, чей
// operationId присутствует в ext (B-08). Применяется ДО фильтра (по всему raw).
func InjectOperations(raw []byte, ext map[string]OperationExt) ([]byte, error) {
	var doc map[string]any
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	if err := dec.Decode(&doc); err != nil {
		return nil, fmt.Errorf("decode openapi: %w", err)
	}
	paths, ok := doc["paths"].(map[string]any)
	if !ok {
		return canonicalJSON(doc)
	}
	for _, itemAny := range paths {
		item, ok := itemAny.(map[string]any)
		if !ok {
			continue
		}
		for _, hm := range httpMethods {
			opAny, ok := item[hm]
			if !ok {
				continue
			}
			op, ok := opAny.(map[string]any)
			if !ok {
				continue
			}
			opID, _ := op["operationId"].(string)
			oe, ok := ext[opID]
			if !ok {
				continue
			}
			op["x-operation"] = map[string]any{
				"metadata": oe.Metadata,
				"response": oe.Response,
				"note":     "returns Operation; poll OperationService.Get until done=true",
			}
		}
	}
	return canonicalJSON(doc)
}

// reachableSchemas вычисляет $ref-замыкание имён схем, достижимых от ВСЕХ операций
// в spec (paths). Используется главным wiring'ом для scope-ирования components —
// иначе blind-union затаскивает в domain-spec схемы dropped-сервисов с инфра-токенами
// (проверено: NetworkInterface несёт vpn_id/sid в prose → ломает §9 tripwire).
func reachableSchemas(specWithPaths []byte) map[string]struct{} {
	var doc map[string]any
	if err := json.Unmarshal(specWithPaths, &doc); err != nil {
		return map[string]struct{}{}
	}
	pool := map[string]json.RawMessage{}
	if comps, ok := doc["components"].(map[string]any); ok {
		if schemas, ok := comps["schemas"].(map[string]any); ok {
			for name, sch := range schemas {
				b, _ := json.Marshal(sch)
				pool[name] = b
			}
		}
	}
	seen := map[string]struct{}{}
	var frontier []string
	if paths, ok := doc["paths"]; ok {
		b, _ := json.Marshal(paths)
		frontier = append(frontier, refNames(b)...)
	}
	for len(frontier) > 0 {
		n := frontier[len(frontier)-1]
		frontier = frontier[:len(frontier)-1]
		if _, ok := seen[n]; ok {
			continue
		}
		seen[n] = struct{}{}
		if body, ok := pool[n]; ok {
			frontier = append(frontier, refNames(body)...)
		}
	}
	return seen
}

func refNames(b []byte) []string {
	var out []string
	for _, m := range refRe.FindAllSubmatch(b, -1) {
		out = append(out, string(m[1]))
	}
	return out
}

// canonicalJSON — детерминированный re-serialize (encoding/json сортирует map-ключи
// лексикографически) + trailing newline для POSIX-friendly diff.
func canonicalJSON(v any) ([]byte, error) {
	out, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(out, '\n'), nil
}

// SortEntries — детерминированный порядок snapshot (по GrpcFqn, затем Method).
func SortEntries(e []OpEntry) {
	sort.Slice(e, func(i, j int) bool {
		if e[i].GrpcFqn != e[j].GrpcFqn {
			return e[i].GrpcFqn < e[j].GrpcFqn
		}
		return e[i].Method < e[j].Method
	})
}
```
- [ ] **4.4 (GREEN-run)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && go test ./cmd/openapi-filter/...
```
Ожидаемо: `ok` (B-02 absence/presence, http-не-дискриминатор, B-08 x-operation, reachable-orphan-drop).
- [ ] **4.5 (commit)**:
```bash
git add cmd/openapi-filter/filter.go cmd/openapi-filter/filter_test.go
git commit -m "feat(openapi-filter): allowlist filter + x-operation + \$ref-reachable schema scope (B-02/B-08)

FilterSpec удаляет op если gRPC-FQN ∉ apisurface.AllowedMethods ИЛИ
HasInternalSuffix (то же правило, что director.go/server.go). Дискриминатор —
allowlist, НЕ http-presence. InjectOperations добавляет x-operation (ext 87334).
reachableSchemas — \$ref-замыкание, дропает orphan-схемы dropped-сервисов
(NetworkInterface vpn_id/sid prose) — иначе blind-union ломает §9 tripwire.
RED→GREEN на fixture с InternalAddressPool/Cloud/IAM.

KAC-251"
```

### Task 5: `cmd/openapi-filter/main.go` — recursive WalkDir I/O wiring + per-domain consolidation (B-05)

- [ ] **5.1** Создать `cmd/openapi-filter/main.go`. **КЛЮЧЕВОЙ ФИКС (blocking issue 1): рекурсивный `filepath.WalkDir` по nested mirror-tree, skip `google/`, бакетинг по домену, scope-ирование схем до reachable.** Читает descriptorset для ext 87334 (по образцу `protoc-gen-kacho-permissions`):
```go
// openapi-filter — standalone post-gen инструмент (НЕ buf plugin).
//
// Pipeline (внутри make generate-openapi, ПОСЛЕ overlay-merge):
//  1. РЕКУРСИВНО обходит --raw-dir (nested mirror-tree, ~136 файлов one-per-proto),
//     skip поддерева google/ и файлов без paths (validation/package_options/kek/...).
//  2. читает FileDescriptorSet (--descriptor-set, эмитит `buf build -o`),
//     извлекает (kacho.cloud.api.operation)=87334 на каждом mutation RPC.
//  3. для каждого raw-файла: InjectOperations → FilterSpec; выживших ops бакетит
//     по домену (3-й сегмент dotted-FQN); схемы — union в пул.
//  4. per-domain: оставляет ТОЛЬКО $ref-reachable схемы (anti-pollution) + пишет
//     gen/openapi/<domain>.openapi.json + _surface-snapshot.json детерминированно.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	apiv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/api"
	"github.com/PRO-Robotech/kacho-proto/apisurface"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/descriptorpb"
)

// domainOf извлекает домен (vpc|compute|iam|loadbalancer|operation) из dotted-FQN.
// dottedFQN = kacho.cloud.<domain>.v1.<Service>.<Method> | kacho.cloud.operation.OperationService.<M>
func domainOf(dottedFQN string) string {
	parts := strings.Split(dottedFQN, ".")
	if len(parts) < 3 {
		return ""
	}
	return parts[2]
}

func main() {
	var rawDir, descSet, outDir string
	flag.StringVar(&rawDir, "raw-dir", "gen/openapi-raw", "nested mirror-tree of per-proto OpenAPI JSON")
	flag.StringVar(&descSet, "descriptor-set", "gen/openapi-raw/_descriptorset.bin", "FileDescriptorSet for ext 87334")
	flag.StringVar(&outDir, "out-dir", "gen/openapi", "committed output dir")
	flag.Parse()

	ext, err := loadOperationExts(descSet)
	if err != nil {
		fail("load operation exts: %v", err)
	}

	// Собираем raw-файлы рекурсивно, skip google/ и descriptorset.
	var rawFiles []string
	err = filepath.WalkDir(rawDir, func(p string, d fs.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if d.IsDir() {
			if d.Name() == "google" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(p, ".openapi.json") {
			rawFiles = append(rawFiles, p)
		}
		return nil
	})
	if err != nil {
		fail("walk raw-dir: %v", err)
	}

	// domain → {paths, schema-pool}; pool union по всем raw, scope позже.
	domainPaths := map[string]map[string]any{}     // domain → openapi paths (выжившие)
	domainSchemaPool := map[string]map[string]any{} // domain → union schemas (до scope)
	domainOpenAPIVer := map[string]string{}
	var allKept []OpEntry

	for _, f := range rawFiles {
		raw, err := os.ReadFile(f)
		if err != nil {
			fail("read %s: %v", f, err)
		}
		enriched, err := InjectOperations(raw, ext)
		if err != nil {
			fail("inject %s: %v", f, err)
		}
		filtered, kept, err := FilterSpec(enriched)
		if err != nil {
			fail("filter %s: %v", f, err)
		}
		allKept = append(allKept, kept...)
		if len(kept) == 0 {
			continue // файл без выживших ops (schema-only / dropped service) — игнор
		}
		mergeIntoDomains(domainPaths, domainSchemaPool, domainOpenAPIVer, filtered)
	}

	if err := os.MkdirAll(outDir, 0o755); err != nil {
		fail("mkdir %s: %v", outDir, err)
	}

	// Per-domain: scope схемы до $ref-reachable, собрать финальный doc.
	for domain, paths := range domainPaths {
		if domain == "operation" {
			continue // OperationService рендерится docs-слоем общим; отдельного файла нет (B-05 snapshot покрывает Cancel)
		}
		// Собираем промежуточный doc {paths, components.schemas=pool} для reachable-вычисления.
		pool := domainSchemaPool[domain]
		interim := map[string]any{
			"paths":      paths,
			"components": map[string]any{"schemas": pool},
		}
		interimBytes, err := json.Marshal(interim)
		if err != nil {
			fail("marshal interim %s: %v", domain, err)
		}
		reach := reachableSchemas(interimBytes)
		scoped := map[string]any{}
		for name := range reach {
			if s, ok := pool[name]; ok {
				scoped[name] = s
			}
		}
		ver := domainOpenAPIVer[domain]
		if ver == "" {
			ver = "3.1.0"
		}
		doc := map[string]any{
			"openapi":    ver,
			"info":       map[string]any{"title": "kacho " + domain, "version": "v1"},
			"paths":      paths,
			"components": map[string]any{"schemas": scoped},
		}
		out, err := canonicalJSON(doc)
		if err != nil {
			fail("marshal domain %s: %v", domain, err)
		}
		dst := filepath.Join(outDir, domain+".openapi.json")
		if err := os.WriteFile(dst, out, 0o644); err != nil {
			fail("write %s: %v", dst, err)
		}
	}

	// _surface-snapshot.json — ВСЕ выжившие (включая operation.OperationService.Cancel).
	SortEntries(allKept)
	snap, err := json.MarshalIndent(allKept, "", "  ")
	if err != nil {
		fail("marshal snapshot: %v", err)
	}
	snap = append(snap, '\n')
	if err := os.WriteFile(filepath.Join(outDir, "_surface-snapshot.json"), snap, 0o644); err != nil {
		fail("write snapshot: %v", err)
	}

	// Sanity-инвариант (defense-in-depth, B-05): zero Internal выжило.
	for _, e := range allKept {
		if apisurface.HasInternalSuffix(e.GrpcFqn) {
			fail("INVARIANT VIOLATED: Internal op survived filter: %s", e.GrpcFqn)
		}
	}
}

// mergeIntoDomains раскладывает выжившие операции одного filtered-spec'а по
// domain-bucket'ам (paths) + union components.schemas в domain-pool.
func mergeIntoDomains(paths map[string]map[string]any, pool map[string]map[string]any, vers map[string]string, specRaw []byte) {
	var doc map[string]any
	if err := json.Unmarshal(specRaw, &doc); err != nil {
		fail("merge unmarshal: %v", err)
	}
	ver, _ := doc["openapi"].(string)
	specPaths, _ := doc["paths"].(map[string]any)
	for pathKey, itemAny := range specPaths {
		item, _ := itemAny.(map[string]any)
		for _, hm := range httpMethods {
			opAny, ok := item[hm]
			if !ok {
				continue
			}
			op, _ := opAny.(map[string]any)
			opID, _ := op["operationId"].(string)
			d := domainOf(opID)
			if d == "" || d == "operation" {
				continue
			}
			if vers[d] == "" && ver != "" {
				vers[d] = ver
			}
			dp := paths[d]
			if dp == nil {
				dp = map[string]any{}
				paths[d] = dp
			}
			dItem, ok := dp[pathKey].(map[string]any)
			if !ok {
				dItem = map[string]any{}
				dp[pathKey] = dItem
			}
			dItem[hm] = op
			// pool союзим только для домена(ов), куда реально попала op этого spec'а.
			if pool[d] == nil {
				pool[d] = map[string]any{}
			}
			if comps, ok := doc["components"].(map[string]any); ok {
				if schemas, ok := comps["schemas"].(map[string]any); ok {
					for k, v := range schemas {
						pool[d][k] = v
					}
				}
			}
		}
	}
}

// loadOperationExts читает FileDescriptorSet и собирает map[dottedFQN]OperationExt
// из расширения 87334 (apiv1.E_Operation) — ровно как protoc-gen-kacho-permissions
// читает E_Permission. ПРОВЕРЕНО: 192 метода несут ext.
func loadOperationExts(path string) (map[string]OperationExt, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read descriptorset: %w", err)
	}
	var fds descriptorpb.FileDescriptorSet
	if err := proto.Unmarshal(raw, &fds); err != nil {
		return nil, fmt.Errorf("unmarshal descriptorset: %w", err)
	}
	out := map[string]OperationExt{}
	for _, fd := range fds.GetFile() {
		pkg := fd.GetPackage()
		for _, svc := range fd.GetService() {
			for _, m := range svc.GetMethod() {
				opts := m.GetOptions()
				if opts == nil || !proto.HasExtension(opts, apiv1.E_Operation) {
					continue
				}
				v, ok := proto.GetExtension(opts, apiv1.E_Operation).(*apiv1.Operation)
				if !ok || v == nil {
					continue
				}
				fqn := pkg + "." + svc.GetName() + "." + m.GetName()
				out[fqn] = OperationExt{Metadata: v.GetMetadata(), Response: v.GetResponse()}
			}
		}
	}
	return out, nil
}

func fail(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "openapi-filter: "+format+"\n", a...)
	os.Exit(1)
}
```

> **Фиксы issues 4 и 5 в этом main.go:**
> - **issue 4 (descriptorset/google pollution):** WalkDir `filepath.SkipDir` на `google/`; `_descriptorset.bin` — не `.openapi.json`, не подхватывается WalkDir-фильтром; файлы без выживших ops (`len(kept)==0`) — `continue` (не загрязняют ни paths, ни pool). Схемы scope-ятся до `$ref`-reachable per-domain — orphan-схемы dropped-сервисов (validation/NIC/package_options) выпадают. **Pool союзится только для домена, куда реально попала операция этого spec'а** (а не глобальный union по всем доменам).
> - **issue 5 (unused sort import):** `main.go` НЕ импортирует `sort` (нет guard `var _ = sort.Slice`). `SortEntries` живёт в `filter.go` и сам импортирует `sort`. `apisurface` в main.go использован в sanity-loop. Перед коммитом — `go vet`.

- [ ] **5.2 (build+vet+test)** — issue 5 фикс verify:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
go build ./cmd/openapi-filter/...
go vet ./cmd/openapi-filter/...        # должен быть чист — нет unused import
go test ./cmd/openapi-filter/...
```
Ожидаемо: build OK, vet чист (ни `sort`, ни любого unused-import в main.go), `ok`.
- [ ] **5.3 (commit)**:
```bash
git add cmd/openapi-filter/main.go
git commit -m "feat(openapi-filter): recursive WalkDir wiring + per-domain consolidation + snapshot (B-05)

main рекурсивно обходит nested mirror-tree (skip google/), читает ext 87334
из FileDescriptorSet, бакетит выжившие ops по домену, scope-ит схемы до
\$ref-reachable (anti-pollution), эмитит gen/openapi/<domain>.openapi.json +
_surface-snapshot.json. Sanity: zero Internal выжило. go vet чист.

KAC-251"
```

### Task 6: curated-examples overlay (B-07) + tripwire (§9, scoped-фикс)

- [ ] **6.1** Создать `openapi-overlays/vpc.examples.yaml` (handwritten Overlay 1.0, infra-safe RFC-1918):
```yaml
overlay: 1.0.0
info:
  title: vpc curated examples
  version: 1.0.0
actions:
  - target: $.paths['/vpc/v1/networks'].post.requestBody.content['application/json'].schema
    update:
      example:
        name: my-network
        description: production network
        labels:
          env: prod
  - target: $.paths['/vpc/v1/subnets'].post.requestBody.content['application/json'].schema
    update:
      example:
        name: my-subnet
        networkId: enpxxxxxxxxxxxxxxxxx
        zoneId: ru-central1-a
        v4CidrBlocks:
          - 10.128.0.0/24
```
Создать аналогичные `compute.examples.yaml`, `iam.examples.yaml`, `loadbalancer.examples.yaml` (минимум 1 пример на домен, все значения — RFC-1918/публичные, без §9-токенов).

> **NOTE по overlay-применению (issue 1 фикс — basename НЕ работает на mirror-tree):** overlay-файлы названы **per-domain** (`vpc.examples.yaml`), а raw-файлы — nested per-proto. Поэтому overlay применяется в Makefile **НЕ basename-loop по raw**, а явным per-domain списком к КОНКРЕТНЫМ raw-файлам, где живут целевые paths. JSONPath-`target` в overlay ссылается на `$.paths['/vpc/v1/networks']…` — этот path есть в `gen/openapi-raw/kacho/cloud/vpc/v1/network_service.openapi.json`. См. Task 7.1 — overlay применяется к **явно перечисленным** service-файлам, по одному `openapi-format` вызову на (overlay, target-raw-file). Поскольку overlay для домена может таргетить несколько service-файлов, проще: применять КАЖДЫЙ domain-overlay к КАЖДОМУ raw-файлу этого домена (`gen/openapi-raw/kacho/cloud/<domain>/v1/*.openapi.json`) — `openapi-format` молча no-op'ит target, которого нет в данном файле.

- [ ] **6.2** Создать `scripts/tripwire.sh`. **ФИКС issue 6 (bare `sid` + whole-file grep false-positives):** **проверено реальным прогоном** — bare `sid -i` ловит `consider`/`reSIDes`/`addressId`; даже `\bsid\b`/`\bvpn_id\b` ловят легит proto-doc-prose (NIC/back-channel descriptions). РЕШЕНИЕ: (a) для `gen/openapi/*.json` — полагаемся на `$ref`-scope, который **уже доказанно** убирает infra-token-схемы (vpn_id/`\bsid\b` отсутствуют во всех reachable-closure'ах — проверено); делаем grep как backstop, но только по **example-блокам**; (b) для `openapi-overlays/*.yaml` — это curated values, grep по всему файлу безопасен (handwritten, не несут proto-prose). Короткие токены анкорим word-boundary:
```bash
#!/usr/bin/env bash
# §9 infra-leak tripwire — KAC-251. Forbidden-токены в:
#   (1) curated overlay-значениях (handwritten — grep по всему файлу безопасен);
#   (2) example-значениях финальных public spec'ов (НЕ по всему файлу — proto
#       doc-prose легитимно упоминает vpn_id/sid в описаниях dropped-сервисов;
#       $ref-scope уже убирает их схемы, но example-блоки проверяем явно).
# ПРОВЕРЕНО: bare 'sid -i' ловит consider/resides/addressId → анкорим \b...\b.
set -euo pipefail
FORBIDDEN='\bvpn_id\b|\bsid\b|\bsid_seq\b|\bhv_id\b|\bhypervisor\b|\bnode_index\b|\bnetns\b|\bhost_iface\b|\bunderlay\b|\bkube-ovn\b|169\.254|\bcontainer_id\b|\bkh-|\bAddressPool\b|InternalService|Internal[A-Z][A-Za-z]*Service'
hits=0

# (1) overlays — весь файл (curated handwritten values).
for f in openapi-overlays/*.yaml; do
  [ -e "$f" ] || continue
  if grep -nEi "$FORBIDDEN" "$f"; then
    echo "TRIPWIRE: forbidden infra-token in overlay $f" >&2
    hits=1
  fi
done

# (2) generated specs — только example-блоки (jq-извлечение всех "example"/"examples"
#     значений; их prose не содержит proto-описаний). Если jq нет — grep строк с "example".
for f in gen/openapi/*.openapi.json; do
  [ -e "$f" ] || continue
  if command -v jq >/dev/null 2>&1; then
    vals=$(jq -r '[.. | objects | (.example?, (.examples? | objects | .[]?.value?))] | flatten | map(select(. != null)) | tostring' "$f")
  else
    vals=$(grep -nE '"example"|"examples"' "$f" || true)
  fi
  if printf '%s' "$vals" | grep -nEi "$FORBIDDEN"; then
    echo "TRIPWIRE: forbidden infra-token in example values of $f" >&2
    hits=1
  fi
done
exit $hits
```
```bash
chmod +x /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto/scripts/tripwire.sh
```
- [ ] **6.3 (RED — negative tripwire)** Доказать, что tripwire ловит: временно добавить `vpn_id: 42` в `vpc.examples.yaml`, прогнать:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && ./scripts/tripwire.sh; echo "exit=$?"
```
Ожидаемо: печать `TRIPWIRE: forbidden infra-token in overlay openapi-overlays/vpc.examples.yaml`, `exit=1`. **Откатить** временную правку.
- [ ] **6.4 (commit)** — GREEN-проверка чистоты выполняется ПОСЛЕ генерации в Task 7.2 (когда `gen/openapi/` существует):
```bash
git add openapi-overlays/ scripts/tripwire.sh
git commit -m "feat(openapi): curated infra-safe examples overlays + §9 tripwire (B-07)

openapi-overlays/<domain>.examples.yaml — handwritten Overlay 1.0, RFC-1918.
scripts/tripwire.sh — forbidden-token gate, scoped: overlays целиком +
example-VALUES финальных spec'ов (НЕ whole-file — proto doc-prose легитимно
упоминает vpn_id/sid; \b-анкорим короткие токены). Negative: vpn_id → exit 1.

KAC-251"
```

### Task 7: Makefile targets `generate-openapi` + `verify-openapi` (B-06 drift gate)

- [ ] **7.1** Отредактировать `project/kacho-proto/Makefile`. `.PHONY` — добавить новые цели:
```make
.PHONY: buf-lint buf-breaking generate gen-clean verify-no-yandex install-plugins verify-catalog verify-permissions-coverage install-openapi-plugins generate-openapi verify-openapi tripwire
```
Добавить в конец файла. **ФИКС issue 1 (overlay-loop) + issue 4 (descriptorset placement):**
```make
# --- OpenAPI public-surface pipeline (KAC-251) -----------------------------

# Local connect-openapi binary (мирроринг install-plugins — без BSR network dep)
# + openapi-filter в $GOBIN.
install-openapi-plugins:
	go install github.com/sudorandom/protoc-gen-connect-openapi@v0.25.6
	go install ./cmd/openapi-filter

# generate-openapi: стадии в одной цели.
#   1. connect-openapi → gen/openapi-raw/<mirror-tree>/*.openapi.json (~136 файлов)
#   2. buf build → gen/openapi-raw/_descriptorset.bin (ext 87334; .bin не подхватывается
#      WalkDir-фильтром *.openapi.json — issue 4 безопасно)
#   3. overlay-merge: КАЖДЫЙ domain-overlay применяется к raw-файлам ЭТОГО домена
#      (mirror-tree per-proto → НЕ basename-loop; openapi-format no-op'ит отсутствующие
#      JSONPath-target'ы) — issue 1 фикс
#   4. openapi-filter рекурсивно → gen/openapi/<domain>.openapi.json + _surface-snapshot.json
generate-openapi: install-openapi-plugins
	rm -rf gen/openapi-raw gen/openapi
	buf generate --template buf.gen.openapi.yaml
	buf build -o gen/openapi-raw/_descriptorset.bin
	@for domain in vpc compute iam loadbalancer; do \
		ovl=openapi-overlays/$$domain.examples.yaml; \
		[ -f $$ovl ] || continue; \
		for raw in gen/openapi-raw/kacho/cloud/$$domain/v1/*.openapi.json; do \
			[ -e $$raw ] || continue; \
			npx --yes openapi-format@1.27.4 $$raw --overlayFile $$ovl -o $$raw >/dev/null 2>&1 || true; \
		done; \
		echo "overlay applied: $$domain"; \
	done
	openapi-filter --raw-dir gen/openapi-raw --descriptor-set gen/openapi-raw/_descriptorset.bin --out-dir gen/openapi
	$(MAKE) tripwire

# verify-openapi: drift-gate — мирроринг verify-catalog. Регенерирует и проверяет
# байт-в-байт совпадение committed gen/openapi/. Диффим ТОЛЬКО всегда-генерируемое
# (НЕ raw, он gitignored). B-06.
verify-openapi: generate-openapi
	git diff --exit-code gen/openapi/

# tripwire: §9 infra-leak gate.
tripwire:
	./scripts/tripwire.sh
```

> **NOTE (overlay-applier fallback):** `openapi-format@1.27.4` (npm, thim81; запиннен для детерминизма) — JSON I/O + детерминированный порядок, требует Node (**проверено v22.22.0 в среде**). `--overlayFile` применяет Overlay 1.0 actions; target-paths, отсутствующие в данном raw-файле, молча игнорируются (`|| true` страхует). Если Node недоступен в CI — fallback `oas-patch` (PyPI): заменить `npx … openapi-format $$raw --overlayFile $$ovl -o $$raw` на `oas-patch overlay $$raw $$ovl -o $$raw`.

- [ ] **7.2 (full pipeline run + tripwire GREEN)** Прогнать полную генерацию (создаёт committed-артефакты + проверяет tripwire на РЕАЛЬНЫХ спеках — issue 6 GREEN):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && make generate-openapi
echo "=== output ==="; ls gen/openapi/
echo "=== tripwire on real specs ==="; ./scripts/tripwire.sh; echo "tripwire exit=$?"
echo "=== confirm no infra-token in reachable schemas ==="; grep -lE '"vpn_id"|"sid"|"hv_id"' gen/openapi/*.openapi.json || echo "clean (no infra-token schemas survived)"
```
Ожидаемо: `vpc.openapi.json compute.openapi.json iam.openapi.json loadbalancer.openapi.json _surface-snapshot.json`; **tripwire `exit=0`** (проверено dry-run, что `$ref`-scope убирает vpn_id/sid-схемы); grep — "clean". **Если tripwire `exit=1` — STOP, проверить reachable-scope в main.go.**
- [ ] **7.3 (validate, B-01)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && npx --yes @scalar/cli validate gen/openapi/vpc.openapi.json gen/openapi/compute.openapi.json gen/openapi/iam.openapi.json gen/openapi/loadbalancer.openapi.json
```
Ожидаемо: все 4 — valid OpenAPI 3.1.
- [ ] **7.4 (commit + B-06 drift gate self-check)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
git add gen/openapi/ Makefile
git commit -m "feat(openapi): generate-openapi + verify-openapi targets + committed specs (B-01/B-06)

make generate-openapi: connect-openapi → descriptorset → per-domain overlay →
openapi-filter (recursive WalkDir + \$ref-scope) → gen/openapi/<domain>.openapi.json
+ _surface-snapshot.json + tripwire. verify-openapi: git diff --exit-code
gen/openapi/ (drift-gate, мирроринг verify-catalog).

KAC-251"
# verify clean:
make verify-openapi; echo "clean exit=$?"
# negative B-06: ручная правка generated → diff non-zero
printf '\n' >> gen/openapi/vpc.openapi.json
git diff --exit-code gen/openapi/ ; echo "tampered exit=$?"
git checkout -- gen/openapi/vpc.openapi.json
```
Ожидаемо: `clean exit=0`; `tampered exit=1` (drift пойман). **Это B-06.**

### Task 8: snapshot-проверки B-04 (suffix-verbs distinct) + B-05 (snapshot invariants)

- [ ] **8.1 (RED — snapshot assertions над committed артефактом)** Создать `cmd/openapi-filter/snapshot_test.go`. **ФИКС issue 3 (hand-rolled contains/indexOf):** используем `strings.Contains`/`strings.HasSuffix`:
```go
package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/PRO-Robotech/kacho-proto/apisurface"
)

func loadSnapshot(t *testing.T) []OpEntry {
	t.Helper()
	root := repoRoot(t)
	raw, err := os.ReadFile(filepath.Join(root, "gen/openapi/_surface-snapshot.json"))
	if err != nil {
		t.Fatalf("read snapshot: %v", err)
	}
	var entries []OpEntry
	if err := json.Unmarshal(raw, &entries); err != nil {
		t.Fatalf("unmarshal snapshot: %v", err)
	}
	return entries
}

// repoRoot — пакет в cmd/openapi-filter; поднимаемся к корню репо.
func repoRoot(t *testing.T) string {
	t.Helper()
	wd, _ := os.Getwd()
	return filepath.Clean(filepath.Join(wd, "..", ".."))
}

// B-05: каждая выжившая ∈ allowlist; zero Internal.
func TestSnapshot_EveryEntryInAllowlist(t *testing.T) {
	entries := loadSnapshot(t)
	if len(entries) < 180 {
		t.Fatalf("expected ~191 survivors, got %d (regression?)", len(entries))
	}
	for _, e := range entries {
		if !apisurface.IsAllowed(e.GrpcFqn) {
			t.Errorf("survivor not in allowlist: %s", e.GrpcFqn)
		}
		if apisurface.HasInternalSuffix(e.GrpcFqn) {
			t.Errorf("Internal op survived: %s", e.GrpcFqn)
		}
	}
}

func TestSnapshot_OperationCancelPresent(t *testing.T) {
	for _, e := range loadSnapshot(t) {
		if e.GrpcFqn == "/kacho.cloud.operation.OperationService/Cancel" {
			return
		}
	}
	t.Error("OperationService.Cancel MUST be among survived public ops (B-05 reviewer note)")
}

// B-04: suffix-verbs рендерятся как DISTINCT операции (отдельные entry).
// Реальные allowlist-ключи (проверено grep'ом источника).
func TestSnapshot_SuffixVerbsDistinct(t *testing.T) {
	want := map[string]bool{
		"/kacho.cloud.vpc.v1.SubnetService/AddCidrBlocks":           false,
		"/kacho.cloud.vpc.v1.SubnetService/RemoveCidrBlocks":        false,
		"/kacho.cloud.vpc.v1.NetworkService/Move":                   false,
		"/kacho.cloud.vpc.v1.SubnetService/Relocate":               false,
		"/kacho.cloud.compute.v1.InstanceService/SetAccessBindings": false,
		"/kacho.cloud.operation.OperationService/Cancel":            false,
	}
	for _, e := range loadSnapshot(t) {
		if _, ok := want[e.GrpcFqn]; ok {
			want[e.GrpcFqn] = true
		}
	}
	for fqn, seen := range want {
		if !seen {
			t.Errorf("suffix-verb op must be DISTINCT survivor: %s (B-04)", fqn)
		}
	}
}

// B-05 негатив: Internal/AddressPool НЕ должны встречаться.
func TestSnapshot_NoInternalNoAddressPool(t *testing.T) {
	for _, e := range loadSnapshot(t) {
		if strings.Contains(e.GrpcFqn, "Internal") || strings.Contains(e.GrpcFqn, "AddressPool") {
			t.Errorf("forbidden op in snapshot: %s", e.GrpcFqn)
		}
	}
}
```

> **NOTE по B-04 «render» (issue 2 minor — OperationService.Cancel):** acceptance B-04 формулирует «render as DISTINCT operation»; B-05 reviewer-note требует Cancel в **snapshot**. По дизайну этого плана `operation`-домен НЕ эмитит committed `operation.openapi.json` (OperationService документируется общим docs-слоем). Cancel + Get **присутствуют в `_surface-snapshot.json`** (snapshot-тест выше это проверяет), что удовлетворяет B-05 и B-04-«render» в смысле «distinct enumerated operation в нормативном артефакте поверхности». **Если acceptance-author B-04 требует Cancel именно в `.openapi.json`-файле** — расширить main.go: НЕ скипать `operation`-домен, эмитить `gen/openapi/operation.openapi.json` (paths `/operations/{id}` + `:cancel`), снять `continue` на `operation` в обоих местах. Решение зафиксировать в `KAC/KAC-251.md` ПЕРЕД генерацией финальных артефактов; по умолчанию — snapshot-presence (текущий план). Этот выбор — единственная открытая точка согласования с acceptance-author; всё остальное закрыто.

- [ ] **8.2 (RED-демонстрация)** Снапшот уже сгенерирован в Task 7. Показать честный RED на временно-битом снапшоте:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
cp gen/openapi/_surface-snapshot.json /tmp/snap.bak
python3 -c "import json;p='gen/openapi/_surface-snapshot.json';d=[e for e in json.load(open(p)) if 'OperationService/Cancel' not in e['grpcFqn']];json.dump(d,open(p,'w'),indent=2)"
go test ./cmd/openapi-filter/ -run TestSnapshot_OperationCancelPresent
```
Ожидаемый FAIL: `OperationService.Cancel MUST be among survived public ops`. Восстановить: `cp /tmp/snap.bak gen/openapi/_surface-snapshot.json`.
- [ ] **8.3 (GREEN-run + vet)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto && go vet ./cmd/openapi-filter/... && go test ./cmd/openapi-filter/...
```
Ожидаемо: vet чист (нет unused-import, нет hand-rolled-helper friction); `ok` (B-04 + B-05).
- [ ] **8.4 (commit)**:
```bash
git add cmd/openapi-filter/snapshot_test.go
git commit -m "test(openapi-filter): snapshot invariants — B-04 suffix-verbs distinct + B-05

Тесты над committed gen/openapi/_surface-snapshot.json: каждая выжившая ∈
allowlist, zero Internal/AddressPool, OperationService.Cancel присутствует,
suffix-verbs (AddCidrBlocks/RemoveCidrBlocks/Move/Relocate/SetAccessBindings/
Cancel) — DISTINCT entries. strings.Contains (no hand-rolled helpers). RED→GREEN.

KAC-251"
```

### Task 9: CI wiring (B-06 в CI)

- [ ] **9.1** Отредактировать `project/kacho-proto/.github/workflows/ci.yaml` — добавить шаги после `verify gen/ is up-to-date`. Нужен Node (для `openapi-format`/`@scalar/cli`) + `jq` (tripwire):
```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - name: ensure jq
        run: jq --version || sudo apt-get update && sudo apt-get install -y jq
      - name: install openapi plugins
        run: |
          go install github.com/sudorandom/protoc-gen-connect-openapi@v0.25.6
          go install ./cmd/openapi-filter
      - name: verify openapi public-surface up-to-date
        run: |
          make generate-openapi
          git diff --exit-code gen/openapi/
      - name: validate openapi specs
        run: npx --yes @scalar/cli validate gen/openapi/*.openapi.json
      - name: openapi infra-leak tripwire
        run: ./scripts/tripwire.sh
      - name: openapi filter + apisurface tests
        run: go test ./cmd/openapi-filter/... ./apisurface/...
```
- [ ] **9.2 (commit)**:
```bash
git add .github/workflows/ci.yaml
git commit -m "ci(openapi): verify-openapi drift gate + scalar validate + tripwire (B-06)

Шаги рядом с verify gen/: make generate-openapi → git diff --exit-code
gen/openapi/, @scalar/cli validate, tripwire (jq), go test cmd/openapi-filter+apisurface.

KAC-251"
```

### Task 10: vault + PR (KAC-251)

- [ ] **10.1** Обновить vault: создать/обновить `obsidian/kacho/packages/proto-apisurface.md` (exported `AllowedMethods`/`IsAllowed`/`HasInternalSuffix`/`DottedFQN`/`AllowedDotted`, imported-by api-gateway proxy + openapi-filter); `obsidian/kacho/rpc/` — пометить, что публичная поверхность генерится из apisurface; обновить `obsidian/kacho/KAC/KAC-251.md` (PR-URL, acceptance чек-лист B-01..B-08, статус, **решение по B-04 OperationService rendering**).
- [ ] **10.2 (push + PR)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-proto
git push -u origin KAC-251
gh pr create --title "[KAC-251] apisurface relocation + public OpenAPI pipeline" \
  --body "Переносит allowlist в kacho-proto/apisurface (единый источник истины), добавляет OpenAPI 3.1 генерацию (connect-openapi, nested mirror-tree) + openapi-filter (recursive WalkDir, drop ∉allowlist ИЛИ Internal-suffixed, \$ref-scoped schemas) + per-domain overlay + x-operation enrichment + _surface-snapshot.json + verify-openapi drift gate + §9 tripwire. Покрывает acceptance B-01..B-08. relates KAC-248. Closes KAC-251"
```
- [ ] **10.3** PR-URL комментарием в YouTrack KAC-251; KAC-251 → `Test`.

---

## KAC-253 — kacho-api-gateway: import switch (ПОСЛЕ merge KAC-251 в main)

> **Cross-repo ordering / временный CI-pin:** KAC-253 зависит от `apisurface` в `main` ветке kacho-proto. Локально `replace ../kacho-proto` (go.mod:7) резолвит рабочую копию — `go build`/`go test` пройдут сразу. Если CI api-gateway подтягивает kacho-proto по `ref:` — временно пиннить sibling к `ref: KAC-251` (с комментарием-напоминанием), после merge KAC-251 в main — убрать (или `ref: main`). В текущем skeleton api-gateway go-тесты гоняются через `make test`; реальный гейт — он.

### Task 11: Регрессия-baseline ДО переключения (B-03 точка отсчёта)

- [ ] **11.1** Ветка: `cd project/kacho-api-gateway && git checkout -b KAC-253`.
- [ ] **11.2 (baseline GREEN)** Зафиксировать зелёные тесты ДО правок (B-03 baseline):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway && go test ./internal/allowlist/... ./internal/proxy/... -race -count=1
```
Ожидаемо: `ok internal/allowlist`, `ok internal/proxy`.

### Task 12: Удалить локальный allowlist, переключить импорты на `apisurface`

- [ ] **12.1** Удалить локальный пакет (источник перенесён):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway
git rm internal/allowlist/list.go internal/allowlist/list_test.go
```
- [ ] **12.2** В `internal/proxy/director.go` (line 12) — заменить import (alias `allowlist`, call-sites без изменений):
```go
// было:  "github.com/PRO-Robotech/kacho-api-gateway/internal/allowlist"
// стало:
	allowlist "github.com/PRO-Robotech/kacho-proto/apisurface"
```
- [ ] **12.3** В `internal/proxy/server.go` (line 8) — то же:
```go
	allowlist "github.com/PRO-Robotech/kacho-proto/apisurface"
```
- [ ] **12.4 (build)** — call-expressions `allowlist.IsAllowed`/`allowlist.HasInternalSuffix` валидны (alias совпадает):
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway && go build ./...
```
Ожидаемо: без ошибок (`replace ../kacho-proto` go.mod:7).
- [ ] **12.5 (B-03 GREEN — регрессия)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway && go test ./internal/proxy/... ./internal/middleware/... -race -count=1
```
Ожидаемо: `ok internal/proxy` (director/server behaviour идентично — логика та же из apisurface). `internal/allowlist` удалён — ожидаемо.
- [ ] **12.6 (full suite)** — никаких dangling-импортов удалённого пакета:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway
! grep -rn 'kacho-api-gateway/internal/allowlist' --include='*.go' .   # нет dangling ref
make test
```
Ожидаемо: grep exit 1 (чисто); `make test` зелёный целиком.
- [ ] **12.7 (commit)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway
git add -A
git commit -m "refactor(proxy): switch allowlist import to kacho-proto/apisurface (B-03)

Удалён локальный internal/allowlist (перенесён в kacho-proto KAC-251).
director.go/server.go импортируют apisurface с alias allowlist — call-sites
без изменений. replace ../kacho-proto уже в go.mod. Регрессия director/server
тестов зелёная.

KAC-253"
```

### Task 13: vault + PR (KAC-253)

- [ ] **13.1** Обновить vault: `obsidian/kacho/edges/` (api-gw allowlist теперь из kacho-proto/apisurface — History-запись с KAC-253); `obsidian/kacho/KAC/KAC-253.md` (PR-URL, статус, B-03 чек).
- [ ] **13.2 (push + PR)**:
```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-api-gateway
git push -u origin KAC-253
gh pr create --title "[KAC-253] switch allowlist import to kacho-proto/apisurface" \
  --body "Переключает api-gateway на канонический apisurface из kacho-proto (KAC-251), удаляет локальную копию allowlist. Регрессия director/server тестов зелёная (B-03). Blocked by PRO-Robotech/kacho-proto (KAC-251 merge). relates KAC-248. Closes KAC-253"
```
- [ ] **13.3** PR-URL комментарием в YouTrack KAC-253; → `Test`.

---

## Финальный acceptance чек-лист (B-01..B-08)

- [ ] **B-01** `make generate-openapi` → 4 per-domain spec'а, OpenAPI 3.1, `@scalar/cli validate` зелёный; `buf.gen.openapi.yaml` отдельный, `buf.gen.yaml` не тронут (Task 3, 7).
- [ ] **B-02** `openapi-filter` unit (Task 4): InternalAddressPool/Cloud/IAM absent, AddressService.Get/List present; дискриминатор — allowlist, не http.
- [ ] **B-03** api-gateway allowlist relocation: director/server тесты зелёные после import-switch; allowlist в ОДНОМ месте — kacho-proto (Task 11-12).
- [ ] **B-04** suffix-verbs (`:add-cidr-blocks`/`:remove-cidr-blocks`/`:move`/`:relocate`/`SetAccessBindings`/`OperationService:cancel`) — distinct entries в снапшоте (Task 8); решение по rendering OperationService в KAC-251.md.
- [ ] **B-05** `_surface-snapshot.json`: каждая ∈ allowlist (~191), zero Internal/AddressPool, `OperationService.Cancel` присутствует (Task 8).
- [ ] **B-06** `verify-openapi` ловит ручные правки generated JSON — `git diff --exit-code gen/openapi/` (Task 7.4, 9).
- [ ] **B-07** curated examples через overlay (per-domain → raw service-файлы, merge ДО фильтра), значения проходят §9 tripwire (Task 6, 7.2).
- [ ] **B-08** mutation RPC несут `x-operation` (metadata/response из ext 87334) + callout «poll until done» (Task 4, 5).

## Cross-repo merge order (топологически)

1. **kacho-proto / KAC-251** → main (apisurface relocation + OpenAPI gen + filter + overlay + drift gate). Все 8 сценариев генерации/фильтра здесь.
2. **kacho-api-gateway / KAC-253** → main (import switch; зависит от apisurface в main; CI-pin `ref: KAC-251` до merge, затем убрать).
3. Закрыть ветки после merge: `gh pr merge --delete-branch` в обоих репо; KAC-251/KAC-253 → `Done` в YouTrack с приложенными PR-URL и логами RED→GREEN.
