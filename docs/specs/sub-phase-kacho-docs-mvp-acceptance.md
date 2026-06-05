# Sub-phase kacho-docs MVP — Acceptance (Given-When-Then)

> Статус: DRAFT
> Дата: 2026-06-05
> Ревьюер: acceptance-reviewer (ожидает APPROVED)
> EPIC: KAC-248 · Задача-acceptance: KAC-249
> Гейт: workspace CLAUDE.md §«Запреты» #1 — ни scaffold, ни код не стартуют до APPROVED.

## Обзор

`kacho-docs` — публичный статический документационный портал платформы Kachō (host `docs.kacho.local`)
на Astro Starlight, развёрнутый как статика за nginx в Kubernetes (новый sibling-репо полирепо, НЕ Go-сервис).
Центральный принцип — «один источник — три читателя» (end-user / API-developer / AI-агент): проза пишется
руками как MDX, API-reference **генерируется** из `kacho-proto` и фильтруется против канонического allowlist,
так что на публичную поверхность по построению попадают **только публичные RPC**. Этот документ фиксирует
приёмочные сценарии **только для MVP** (read-only API reference + persona-tabs + AI-native выдача + статические
Operations + verified-snippets + Pagefind/тема + деплой); Phase 2 (Try-it/Hurl/sandbox) и Phase 3
(RAG/topology/semantic/версии/EN-промоут) — **явная граница (non-goals)**, а не недоделка.

Источник истины дизайна: `docs/superpowers/specs/2026-06-05-kacho-docs-2026-design.md` (далее цитируется как §N).
Каждый сценарий трассируется к секции дизайна (таблица в конце).

### Принятые предположения (зафиксированы явно, не угаданы молча)

- **A1.** RU — primary root-locale (чистые URL `/vpc/network/`), EN — scaffold под `/en/` с fallback на RU
  (§1.1, решено в дизайне). Полный EN-перевод — Phase 3, не покрывается здесь.
- **A2.** API Reference (P1) на launch генерируется для **VPC + Compute + IAM + LoadBalancer полностью**
  (отфильтрованная public-поверхность); concept-проза в MVP — **VPC полностью (8 ресурсов)**, IAM и Compute —
  **stub + reference-link** (§8.1, принятая осознанная asymmetry, boundary-разметка). Эта asymmetry проверяется
  сценариями, а не считается багом.
- **A3.** Точный перечень публичных VPC-сервисов/операций, которые ДОЛЖНЫ пережить фильтр, и перечень
  Internal/AddressPool-сервисов, которые НЕ должны, — берётся из §6.3 (`_surface-snapshot.json` enumerated mapping).
  Если фактический allowlist в `kacho-proto` на момент реализации разойдётся с §6.3 — это сигнал на re-review
  acceptance, а не молчаливое отклонение.
- **A4.** Try-it playground в MVP **отсутствует** (Prism-mock/Scalar — Phase 2). MVP P1 — `starlight-openapi`
  read-only. Сценарии P1 проверяют рендер и фильтр, не live-вызовы.
- **A5.** «verified examples» в MVP — только **слой 1** (`remark-code-import` из компилируемых `examples/<lang>/*`).
  Hurl-исполнение (слой 2) — Phase 2.

---

# Область A. Тема, бренд и shell (P7)

## Сценарий A-01: Тема-паритет dark (default) с kacho-ui

**ID:** docs-A-01 · трассировка: §3 (фреймворк), §4 (тема), дизайн §11 MVP-checklist

**Given** `kacho-docs` собран (`npm run build`) с `src/styles/kacho.css`, портирующим `--kc-*` токены из
`kacho-ui/src/index.css` и маппящим их на `--sl-color-*`
**And** dark — дефолтная тема Starlight (`:root, ::backdrop`)

**When** открыта любая страница в preview-сборке без явного выбора темы

**Then** computed `--sl-color-bg` === `--kc-page` === `#0d0e12`
**And** computed `--sl-color-text` === `--kc-text` === `#e7e9ef`
**And** computed `--sl-color-accent` === `--kc-primary` === `#3d8df5`
**And** базовый шрифт (`--sl-font`) резолвится в `Inter Variable` (self-hosted `@fontsource-variable/inter`, без CDN-загрузки)
**And** Starlight НЕ форкнут — кастомизация только через `customCss: ['./src/styles/kacho.css']`

## Сценарий A-02: Тема-паритет light (переключение)

**ID:** docs-A-02 · трассировка: §4

**Given** собранный сайт с light-маппингом `:root[data-theme='light']`

**When** пользователь переключает тему в `light`

**Then** `data-theme="light"` выставляется на корне (конвенция 1-в-1 с kacho-ui)
**And** computed `--sl-color-bg` === `--kc-page` === `#f6f7f9`
**And** computed `--sl-color-text` === `--kc-text` === `#14171c`
**And** `--kc-primary` остаётся `#3d8df5` в обеих темах

## Сценарий A-03: Бренд KachoLogo

**ID:** docs-A-03 · трассировка: §4

**Given** в `astro.config.mjs` задан `logo: { light: './src/assets/kacho-light.svg', dark: './src/assets/kacho-dark.svg', replacesTitle: true }`

**When** рендерится header сайта

**Then** в header присутствует KachoLogo (градиент blue→violet), а не дефолтный текстовый title Starlight
**And** ассеты грузятся локально из `src/assets/` (без внешнего CDN)

## Сценарий A-04: Pagefind ⌘K-палитра (поиск)

**ID:** docs-A-04 · трассировка: §5 P7, §11

**Given** сайт собран со встроенным Pagefind (`pagefind@1.5.x`), `dist/pagefind/` сгенерирован

**When** пользователь нажимает `⌘K` (или `Ctrl+K`)

**Then** открывается палитра поиска
**And** запрос «network» возвращает релевантные концепт-страницы VPC (keyword-match)
**And** результаты кликабельны и ведут на directory-URL соответствующих страниц
**And** (edge) пустой запрос не роняет палитру; запрос без совпадений показывает «ничего не найдено», не ошибку

## Сценарий A-05 (edge): тема-паритет не дрейфит — порт задокументирован

**ID:** docs-A-05 · трассировка: §4 (примечание о дрейфе)

**Given** `src/styles/kacho.css` содержит шапку-комментарий с источником истины (`kacho-ui/src/index.css`)

**When** ревьюер сверяет таблицу токенов §4 с фактическим CSS

**Then** значения `--kc-page/-container/-elevated/-border/-text/-text-secondary/-primary/-brand-gradient`
для dark и light совпадают с таблицей §4 verbatim
**And** общий пакет `@kacho/tokens` НЕ вводится в MVP (явная out-of-scope-граница, не долг)

---

# Область B. API-reference pipeline + public-filter (P1, §6) — INFRA-SENSITIVITY ядро

> Это самая safety-critical область. Фильтр держит Internal*/AddressPool вне публичной поверхности.
> Net-new Go-код (`cmd/openapi-filter`) подпадает под strict TDD (§12) — сценарии требуют RED→GREEN.

## Сценарий B-01: генерация OpenAPI 3.1 из proto

**ID:** docs-B-01 · трассировка: §6.1

**Given** `kacho-proto` содержит `buf.gen.openapi.yaml` (отдельный шаблон, НЕ трогает `buf.gen.yaml` Go-stub-gen)
с `protoc-gen-connect-openapi@v0.25.6`
**And** все `.proto` — `syntax = "proto3"` (editions-2023 отсутствуют)

**When** запускается `make generate-openapi`

**Then** генерируется по одной спеке на домен: `gen/openapi/{vpc,compute,iam,loadbalancer}.openapi.json`
**And** каждая спека — OpenAPI **3.1** (не Swagger 2.0)
**And** `@scalar/cli validate gen/openapi/*.json` проходит (валидная спека)

## Сценарий B-02 (RED→GREEN, net-new code): фильтр роняет Internal/AddressPool, сохраняет public

**ID:** docs-B-02 · трассировка: §6.2, §6.3 п.1, §12.2 — strict TDD §12

**Given** написан unit-тест `cmd/openapi-filter` с фикстурой-OpenAPI, содержащей операции
`InternalAddressPoolService.*`, `InternalCloudService.*`, `InternalIAMService.*` И публичные `AddressService.Get/List`
**And** канонический `apisurface.AllowedMethods` + `apisurface.HasInternalSuffix` доступны из `kacho-proto`

**When (RED)** тест прогоняется ДО написания фильтра (фильтра нет)

**Then (RED)** тест **падает** — ожидаемое отсутствие Internal/AddressPool-операций не достигается (доказательство, что тест проверяет реальную логику)

**When (GREEN)** реализован `cmd/openapi-filter` (~80 LOC Go): выбрасывает каждую операцию, чей gRPC-FQN ∉ allowlist ИЛИ Internal-suffixed

**Then (GREEN)** после фильтра в выходной спеке:
  - НЕТ ни одной операции `InternalAddressPoolService.*` / `InternalCloudService.*` / `InternalIAMService.*` / любого `Internal*Service`
  - ЕСТЬ публичные `AddressService.Get` и `AddressService.List` (публичный AddressService сохраняется — admin AddressPool дропается)
**And** фильтр опирается на allowlist, а НЕ на наличие `google.api.http` (т.к. 6 Internal-proto тоже несут http — §6.2)

## Сценарий B-03: allowlist канонизирован в kacho-proto, api-gateway не сломан

**ID:** docs-B-03 · трассировка: §6.2, §10 (subtask kacho-api-gateway), §12.2

**Given** `package allowlist` (`AllowedMethods` + `HasInternalSuffix`) перемещён из `kacho-api-gateway/internal/allowlist/`
в `kacho-proto` как канонический `apisurface`-пакет
**And** `kacho-api-gateway` переключил импорт на `github.com/PRO-Robotech/kacho-proto/.../apisurface`
(`replace ../kacho-proto` уже в go.mod — build-граф не меняется)

**When** прогоняются существующие тесты api-gateway (`allowlist`/`director`/`server`)

**Then** все они **зелёные** (regression-guard: переезд не сломал маршрутизацию)
**And** allowlist существует ровно в ОДНОМ месте (`kacho-proto`) — split-brain исключён по построению, а не drift-check'ом

## Сценарий B-04: suffix-verbs рендерятся как distinct operations (snapshot)

**ID:** docs-B-04 · трассировка: §5 P1, §6.3 п.3, §12.3 (fidelity-риск)

**Given** proto использует suffix-action-пути: `:move`, `:relocate`, `:add-cidr-blocks`, `:remove-cidr-blocks`,
`:setAccessBindings` (vpc/compute/iam) + публичный `OperationService:cancel`
**And** написан snapshot-тест над собранным `starlight-openapi`-reference

**When** reference собран и snapshot зафиксирован

**Then** каждая suffix-операция присутствует как **отдельная** operation, а не схлопнута на base-path:
  - `POST /vpc/v1/subnets/{id}:addCidrBlocks` — distinct
  - `POST /vpc/v1/subnets/{id}:removeCidrBlocks` — distinct
  - `POST /vpc/v1/networks/{id}:move` — distinct
  - `POST /vpc/v1/subnets/{id}:relocate` — distinct
  - `:setAccessBindings` (iam) — distinct
**And** `OperationService:cancel` присутствует (публичный, не leak — rendering-проверка)
**And** snapshot НЕ содержит ни одной Internal/AddressPool-операции

## Сценарий B-05: allowlist↔OpenAPI diff-snapshot — enumerated mapping артефакт

**ID:** docs-B-05 · трассировка: §6.3 (именованный артефакт)

**Given** CI генерирует и коммитит `gen/openapi/_surface-snapshot.json` — отсортированный список
`{operationId, method, path, grpcFqn}` всех переживших фильтр операций

**When** ревьюер сверяет snapshot с `apisurface.AllowedMethods` 1-в-1

**Then** каждая survived-операция ∈ allowlist (нет «лишних»)
**And** ни одна Internal-suffix-операция не survived
**And** для VPC присутствуют (survival): `NetworkService` (Get/List/Create/Update/Delete/ListSubnets/ListSecurityGroups/ListRouteTables/ListOperations/Move),
`SubnetService` (+AddCidrBlocks/RemoveCidrBlocks/Relocate/ListUsedAddresses), `AddressService`
(Get/GetByValue/List/ListBySubnet/Create/Update/Delete/Move/ListOperations), `RouteTableService`,
`SecurityGroupService` (+UpdateRules/UpdateRule), `GatewayService`, `PrivateEndpointService`, `NetworkInterfaceService`
**And** отсутствуют (НЕ survival): `InternalAddressService`, `InternalAddressPoolService`, `InternalNetworkService`,
`InternalCloudService`, `InternalWatchService`, `InternalResourceLifecycleService`

## Сценарий B-06: drift-гейт ловит ручную правку generated JSON

**ID:** docs-B-06 · трассировка: §6.3 п.4

**Given** Makefile-таргет `verify-openapi` = `git diff --exit-code gen/openapi/`, вплетён в CI рядом с buf-generate-гейтом

**When (negative)** разработчик вручную правит `gen/openapi/vpc.openapi.json` без перегенерации

**Then** `verify-openapi` падает (`git diff` ненулевой) → CI красный
**And** легитимный путь добавить пример — overlay (см. B-07), не правка generated

## Сценарий B-07: curated infra-safe examples через overlay (не правка generated)

**ID:** docs-B-07 · трассировка: §6.4

**Given** `kacho-proto/openapi-overlays/<domain>.examples.yaml` — рукописный version-controlled overlay
с infra-safe `examples`/`example` (RFC-1918 CIDR, `enp...`-id и т.п.)
**And** Makefile-шаг `generate-openapi` после connect-openapi применяет overlay (`redocly`/`openapi-overlay` CLI) ДО commit'а

**When** запускается `generate-openapi`

**Then** финальный `gen/openapi/<domain>.openapi.json` содержит curated-examples, привнесённые overlay-шагом детерминированно
**And** drift-гейт (B-06) проходит (overlay — часть pipeline, не ручная правка)
**And** (negative/infra-safety) overlay-значения проходят §9-tripwire grep: запретный токен в overlay роняет CI (см. область H)

## Сценарий B-08: Operation-обогащение per-RPC из proto-опции

**ID:** docs-B-08 · трассировка: §6.3 (обогащение), §5 P4

**Given** мутирующие RPC несут опцию `(kacho.cloud.api.operation){metadata,response}` (extension 87334)

**When** генерируется reference

**Then** каждая мутация в reference показывает `x-operation` с конкретными `metadata`/`response` Any-типами
**And** присутствует callout «returns Operation, poll until done»

---

# Область C. Persona / контент-модель (P2, §7)

## Сценарий C-01: синхронизированные persona-tabs на VPC-концепции

**ID:** docs-C-01 · трассировка: §5 P2, §7

**Given** VPC-концепт-страница использует встроенный `<Tabs syncKey="persona">` с TabItem `Console` / `REST` / `Go` / `Python`

**When** страница рендерится

**Then** все четыре ветки присутствуют в DOM/Markdown (нет условного MDX-ветвления, нет hydration-flash)
**And** выбор таба персистится в `localStorage` и сохраняется между навигациями (`syncKey` синхронизирует все блоки на сайте)
**And** Console-ветка — клик-инструкция; REST — curl; Go/Python — импортированный сниппет (см. область F)

## Сценарий C-02: AI-track получает все ветки бесплатно

**ID:** docs-C-02 · трассировка: §7 (AI-track = сырой Markdown)

**Given** страница с persona-tabs

**When** запрашивается её `.md`-представление (см. область E) или содержимое попадает в `llms-full.txt`

**Then** в Markdown присутствуют ВСЕ четыре ветки (Console/REST/Go/Python) — ни одна не скрыта условным рендером

## Сценарий C-03: deep-link концепт↔reference через ApiRefLink

**ID:** docs-C-03 · трассировка: §7 (`<ApiRefLink>`), §8

**Given** frontmatter-схема расширена (`docsSchema({ extend })`) полями `persona`, `apiService`, `kachoResource`
**And** концепт Network имеет `apiService: 'NetworkService'`

**When** на странице используется `<ApiRefLink service={frontmatter.apiService}/>`

**Then** генерируется ссылка на сгенерированный reference-маршрут `starlight-openapi` (`/api/vpc/networkservice/`) без хардкода URL
**And** (negative/edge) отсутствующий `apiService` во frontmatter не роняет билд (поле optional)

## Сценарий C-04 (negative): условный MDX-persona-store запрещён

**ID:** docs-C-04 · трассировка: §5 P2 (риски), §7

**Given** регламент авторинга

**When** ревьюер проверяет MDX-источник

**Then** НЕ используется кастомный persona-store / условный MDX, скрывающий ветку из Markdown-корпуса
**And** единственный санкционированный паттерн — `<Tabs syncKey="persona">`

---

# Область D. Информационная архитектура (§8)

## Сценарий D-01: sidebar и top-level IA

**ID:** docs-D-01 · трассировка: §8, §8.1

**Given** sidebar — гибрид: explicit для top-level порядка/лейблов + `autogenerate` внутри `concepts/<domain>` и `how-to` + `openAPISidebarGroups`

**When** сайт собран

**Then** присутствуют top-level разделы: Обзор, Быстрый старт, Концепции, Инструкции (how-to),
API Reference, Работа с API, AI и агенты, Релизы (stub)
**And** RU — root-locale (чистые URL `/vpc/network/`), EN — scaffold под `/en/`
**And** «Работа с API» содержит: аутентификация, Operation-polling, error-model `{code,message,details}`, пагинация `page_token`, UpdateMask

## Сценарий D-02: VPC-концепции — 8 публичных ресурсов полностью

**ID:** docs-D-02 · трассировка: §8.2

**Given** VPC-концепт-раздел

**When** ревьюер открывает раздел Концепции → VPC

**Then** присутствуют все 8 first-class ресурсов: Network, Subnet, SecurityGroup, RouteTable, Gateway,
Address, NetworkInterface, PrivateEndpoint
**And** каждая концепт-страница описывает tenant-поля / lifecycle / limits БЕЗ инфра-полей
**And** NetworkInterface явно документирует kacho-divergence (first-class ресурс, НЕ inline-in-instance как в YC)
**And** каждая мутация описана как возвращающая `operation.Operation` (poll `OperationService.Get` до `done=true`)

## Сценарий D-03 (принятая asymmetry): IAM/Compute concept — stub + reference-link

**ID:** docs-D-03 · трассировка: §8.1 (РЕШЕНО)

**Given** A2: reference генерируется для всех доменов, но concept-проза Compute/IAM в MVP — stub

**When** ревьюер открывает концепт IAM (или Compute)

**Then** stub-страница содержит короткую вводную + ссылку на сгенерированный reference домена
**And** stub явно помечена callout'ом «Концептуальная документация этого домена в разработке; полный API-reference доступен в разделе API Reference» — boundary-разметка
**And** это НЕ нарушает no-tech-debt: stub — явная граница глубины контента, а reference домена — полнофункциональный (не TODO, не недоделанный код)

## Сценарий D-04: AddressPool отсутствует в публичных концептах и reference

**ID:** docs-D-04 · трассировка: §8.2 (ADMIN/INTERNAL ONLY), §9

**Given** AddressPool (id `apl`) — admin/internal-only (`InternalAddressPoolService` на internal-listener)

**When** ревьюер ищет AddressPool в публичных концептах и в API Reference

**Then** AddressPool-ресурс/сервис отсутствует в публичном reference (дропнут фильтром B-02)
**And** в концептах максимум фраза «выбор пула автоматический», без admin-RPC
**And** строка `AddressPool` ловится tripwire (область H), если просочится в `dist`

## Сценарий D-05: Quickstart «Первая сеть за 5 минут»

**ID:** docs-D-05 · трассировка: §8 (IA), §7

**Given** страница Быстрый старт

**When** ревьюер открывает её

**Then** описан поток Network → Subnet → Address с persona-tabs (Console + API)
**And** каждый шаг-мутация показывает submit→poll Operation (консистентно с областью G)

---

# Область E. AI-native выдача (P3, §5)

## Сценарий E-01: llms.txt / llms-full.txt / llms-small.txt эмитятся с infra-excludes

**ID:** docs-E-01 · трассировка: §5 P3, §9 SECONDARY

**Given** `starlight-llms-txt@0.10.0` подключён с exclude-globs (`internal/**`, `admin/**`)

**When** `npm run build`

**Then** в `dist/` присутствуют `/llms.txt`, `/llms-full.txt`, `/llms-small.txt`
**And** `llms-full.txt` НЕ содержит ни одного запретного инфра-токена (проверяется tripwire, область H)
**And** `llms-full.txt` НЕ содержит Internal/AddressPool-поверхности

## Сценарий E-02: per-page .md маршрут

**ID:** docs-E-02 · трассировка: §5 P3, §7

**Given** реализован `src/pages/[...slug].md.ts`

**When** запрашивается `<любая-страница>.md` (например `/vpc/network.md`)

**Then** возвращается стабильный Markdown-источник страницы
**And** (edge) `.md` для несуществующего slug — 404, не 500
**And** этот `.md`-маршрут — робастный примитив (fallback для llms.txt, источник для GitMCP Phase 2)

## Сценарий E-03: AI-actions в заголовке страницы

**ID:** docs-E-03 · трассировка: §5 P3, §11

**Given** override `PageTitle` добавляет действия `[Copy as Markdown]` `[View as Markdown]` `[Open in ChatGPT]` `[Open in Claude]`

**When** страница рендерится

**Then** все четыре действия присутствуют
**And** `[View as Markdown]` ведёт на `.md`-маршрут (E-02)
**And** (edge/graceful) `[Open in ChatGPT]`/`[Open in Claude]` — URL-строки с graceful degradation: worst-case prefilled-prompt, отсутствие стабильного `?q=`-API не роняет страницу

## Сценарий E-04: страница «AI и агенты»

**ID:** docs-E-04 · трассировка: §8 (раздел 7), §5 P3

**Given** раздел AI и агенты (`ai.mdx`)

**When** ревьюер открывает раздел

**Then** документированы: llms.txt, copy-as-md, open-in-Claude/ChatGPT, docs-as-MCP
**And** GitMCP / Ask-AI помечены как Phase 2 / Phase 3 (boundary, не MVP)

## Сценарий E-05 (resilience): поломка llms-txt-плагина не блокирует деплой

**ID:** docs-E-05 · трассировка: §5 P3 (риски — single-maintainer)

**Given** `starlight-llms-txt` build-time-only и снимаемый; владеем `.md`-маршрутом как fallback

**When** плагин гипотетически снят

**Then** билд по-прежнему проходит, `.md`-маршрут продолжает работать (llms.txt тогда — ручной concat, деплой не заблокирован)

---

# Область F. Verified examples — слой 1 (P6, §5)

## Сценарий F-01: сниппеты импортируются из компилируемого исходника

**ID:** docs-F-01 · трассировка: §5 P6 (MVP слой 1), §7

**Given** `remark-code-import` подключён; `examples/{go,python,sh}/*` — реальный исходник
**And** MDX-блоки ссылаются на файлы (предпочтительно region/whole-file, не голый `#L3-L6`)

**When** `npm run build`

**Then** Go/Python/sh-ветки persona-tabs показывают содержимое реальных файлов `examples/<lang>/*` (markdown — view над тестируемым исходником)
**And** (negative) ссылка на несуществующий файл/region роняет билд — не выдаёт пустой блок

## Сценарий F-02 (RED→GREEN дисциплина): примеры компилируются/линтятся в CI

**ID:** docs-F-02 · трассировка: §5 P6, §11 («падающий пример = красный билд»)

**Given** CI-шаг компилирует/типизирует/линтит `examples/go/*` (go build/vet), `examples/python/*` (type-check/lint), `examples/sh/*` (shellcheck)

**When (negative/RED)** в `examples/go/create_network.go` намеренно внесена ошибка компиляции

**Then (RED)** CI-шаг падает (пример не компилируется) — никаких skip/TODO

**When (GREEN)** ошибка исправлена

**Then (GREEN)** CI-шаг зелёный
**And** Hurl-исполнение (слой 2) явно НЕ входит в MVP (Phase 2, A5) — это boundary, не пропущенный долг

---

# Область G. Async Operations UX — статический (P4, §5)

## Сценарий G-01: статический <OperationEnvelope> — proto-точная форма

**ID:** docs-G-01 · трассировка: §5 P4 (MVP статический)

**Given** реализован статический компонент `<OperationEnvelope>`

**When** он рендерится на концепт-странице

**Then** показаны поля proto-точно: `id, description, created_at, modified_at, done, metadata (Any), oneof result{error: google.rpc.Status | response}`
**And** присутствует легенда 3 состояний (in-flight `done=false` → success `response` / error `error`)
**And** типы `metadata`/`response` инжектятся per-RPC из опции `(kacho.cloud.api.operation)` (B-08)

## Сценарий G-02: каноническая концепт-страница «Работа с асинхронными Operations»

**ID:** docs-G-02 · трассировка: §5 P4, §8 (раздел 6)

**Given** концепт-страница async-Operations

**When** ревьюер открывает её

**Then** объяснён канонический поток: каждая мутация → `Operation`; клиент поллит `OperationService.Get` (`GET /operations/{id}`) до `done=true`
**And** показано чтение `oneof result{error|response}` и `metadata`
**And** упомянут per-resource `ListOperations` (`GET /vpc/v1/networks/{id}/operations`) для истории
**And** live-остров `<OperationRunner>` (auto-poll) явно помечен Phase 2 (boundary)

## Сценарий G-03 (консистентность): каждая VPC-мутация в доках возвращает Operation

**ID:** docs-G-03 · трассировка: §8.2, §5 P4

**Given** VPC-концепты и reference

**When** ревьюер проверяет любую мутацию (Create/Update/Delete/Move/:add-cidr-blocks и т.п.)

**Then** документация описывает её как возвращающую `operation.Operation` (а не синхронный ресурс)
**And** это консистентно с flat-resources + Operations контрактом платформы

---

# Область H. Infra-sensitivity гарды (§9) — HARD CONSTRAINT

> Defense-in-depth: PRIMARY (allowlist-фильтр) + SECONDARY (exclude-globs) + TRIPWIRE (grep) + NGINX + CONTENT.
> Public output (страницы, dist, llms-full.txt, reference, любой будущий playground) НИКОГДА не содержит
> Internal*/AddressPool-поверхности или инфра-токенов.

## Сценарий H-01 (RED→GREEN, net-new): CI-tripwire ловит подброшенный запретный токен

**ID:** docs-H-01 · трассировка: §9 TRIPWIRE, §6.3 п.2, §12.2 — strict TDD §12

**Given** CI-tripwire — grep по `dist/` + `llms-full.txt` на запретные токены:
`vpn_id, sid, sid_seq, hv_id, hypervisor, node_index, netns, host_iface, underlay, kube-ovn, gateway_ip (169.254), container_id, kh-, AddressPool, Internal`
**And** написан fixture-тест tripwire

**When (RED)** в фикстуру `dist`-фрагмента подброшен запретный токен (например `AddressPool`)

**Then (RED)** tripwire-grep **падает** (exit 1) — подтверждено, что он ловит подброшенный токен (tripwire без доказательства поимки не считается рабочим)

**When (GREEN)** фикстура очищена (чистый `dist`)

**Then (GREEN)** tripwire проходит (exit 0)

## Сценарий H-02 (negative, полный список токенов): ни один инфра-токен не в публичном output

**ID:** docs-H-02 · трассировка: §9 TRIPWIRE, §«Инфра-чувствительные данные» workspace CLAUDE.md

**Given** реальная собранная `dist` + `llms-full.txt`

**When** прогоняется tripwire-grep на полный список

**Then** НЕТ ни одного совпадения по: `vpn_id, sid, sid_seq, hv_id, hypervisor, node_index, netns, host_iface, underlay, kube-ovn, 169.254, container_id, kh-, AddressPool, Internal`
**And** CI зелёный (exit 0) только при нулевом совпадении

## Сценарий H-03: PRIMARY-фильтр — Internal-проекции Region/Zone/Hypervisor недостижимы

**ID:** docs-H-03 · трассировка: §9 PRIMARY

**Given** OpenAPI отфильтрован против канонического allowlist на этапе генерации

**When** ревьюер проверяет reference / llms.txt / MCP-индекс

**Then** Internal-проекции (placement, SID-схема, underlay, Hypervisor целиком) не достигают ни одной публичной поверхности
**And** корректность доказана B-02 (unit RED→GREEN) + B-05 (diff-snapshot)

## Сценарий H-04: CONTENT-гард — концепты курируются из tenant-полей, vault-инфра не копируется

**ID:** docs-H-04 · трассировка: §9 CONTENT

**Given** vault-VPC-заметки содержат инфра-историю (kube-ovn-underlay, removed `vpn_id`, NIC data-plane-поля `hv_id/sid/sid_seq/host_iface/netns/gateway_ip/container_id`)

**When** автор пишет публичную концепт-страницу

**Then** копируются ТОЛЬКО tenant-поля; инфра-история НЕ переносится (per-page public-fields-only review перед публикацией)
**And** NetworkInterface-концепт EXCLUDE ВСЕ data-plane-поля; Network EXCLUDE `vpn_id`/underlay; Subnet EXCLUDE underlay; Address EXCLUDE pool-internals

---

# Область I. Деплой и CI (§3.2, §10)

## Сценарий I-01: two-stage Docker-образ

**ID:** docs-I-01 · трассировка: §3.2, §10

**Given** two-stage Dockerfile `node:22-alpine` (build) → `nginx:1.27-alpine` (runtime), `COPY dist → /usr/share/nginx/html`

**When** образ собирается

**Then** runtime-образ содержит статику (`/_astro`, `404.html`, `pagefind/`, `llms*.txt`)
**And** EXPOSE 8080, есть `/healthz`
**And** тег образа — `docker.io/prorobotech/kacho-docs:KAC-N-<sha>` (НЕ ttl.sh, по MEMORY-feedback)

## Сценарий I-02 (negative/critical): nginx — directory-index, БЕЗ SPA-fallback

**ID:** docs-I-02 · трассировка: §3.2, §9 NGINX

**Given** nginx-конфиг с `try_files $uri $uri/ $uri/index.html =404; error_page 404 /404.html;`
(НЕ SPA-catch-all `/index.html`)

**When** запрашивается несуществующий путь

**Then** возвращается **404** (`/404.html`), а не молча-замаскированный 200 (SPA-fallback маскировал бы реальные 404 и ломал per-page URL)
**And** ВСЕ `proxy_pass`-блоки kacho-ui (api-gateway, `/iam/v1`, Ory kratos/hydra) **удалены** — docs-сайт не ходит ни к чему внутреннему

## Сценарий I-03 (smoke, обязательный гейт «nginx готов»): Cache-Control на HTML и ассетах

**ID:** docs-I-03 · трассировка: §3.2 (Cache-Control fix), §9 NGINX, §12.3

**Given** Cache-Control скоупится через `map $sent_http_content_type` (не `location ~* /index\.html$`,
который не матчит directory-URL)

**When** `curl -I https://docs.kacho.local/vpc/network/` (чистый directory-URL) в preview-сборке

**Then** HTML-ответ содержит `Cache-Control: no-store`
**And** `curl -I` на `/_astro/*.js` содержит `Cache-Control: public, immutable`
**And** без зелёного этого smoke nginx-слой НЕ считается готовым (no-tech-debt)

## Сценарий I-04 (scaffold-acceptance критерий): чистый npm ci без legacy-peer-deps

**ID:** docs-I-04 · трассировка: §3.1, §12.3

**Given** `package.json` пиннит `@astrojs/react`/`@astrojs/mdx` (или `overrides` форсят единый `astro`-резолв) под `astro@^6.0.0`

**When** в чистом CI-окружении выполняется `npm ci`

**Then** резолв проходит **без ERESOLVE** и **без** `--legacy-peer-deps`
**And** зелёный `npm ci` — обязательный гейт первого PR

## Сценарий I-05: CI-pipeline kacho-docs

**ID:** docs-I-05 · трассировка: §10 (CI)

**Given** `.github/workflows/ci.yaml`: `npm ci` → `npm run check` → `@scalar/cli validate openapi/*.json` → `npm run build` → CI-tripwire grep → `lychee`-link-check

**When** CI прогоняется на PR

**Then** все шаги зелёные на валидном состоянии
**And** (negative) сломанная ссылка ловится `lychee`; невалидная спека — `@scalar/cli validate`; инфра-токен — tripwire (H-01)

## Сценарий I-06: kacho-deploy wiring

**ID:** docs-I-06 · трассировка: §10 (Dev-стенд), §3.2 (Helm)

**Given** Helm-чарт зеркало kacho-ui (`name=docs`, `ingress.host=docs.kacho.local`, port 8080), подключён в umbrella `kacho-deploy`
**And** `kacho-deploy/Makefile` имеет `build-docs` (вызывается из `dev-up` после `build-ui`), `docs` в whitelist `reload-svc`

**When** `make dev-up`

**Then** `kacho-docs` собирается, грузится в kind, разворачивается; `docs.kacho.local` резолвится на статический сайт
**And** umbrella `Chart.yaml` ссылается `file://../../../kacho-docs/deploy`; `values.dev.yaml` задаёт `docs.image`/`ingress.host`

## Сценарий I-07 (порядок merge): топосортировка графа соблюдена

**ID:** docs-I-07 · трассировка: §10 (порядок merge), §12.1

**Given** кросс-репо EPIC (≥3 репо)

**When** работа мёржится

**Then** порядок: `kacho-proto` (allowlist-переезд + OpenAPI-gen + фильтр + overlay) → `kacho-api-gateway` (import-switch, зелёные тесты) → `kacho-docs` (новый репо) → `kacho-deploy` (wiring) → `kacho-workspace` (docs/vault)
**And** пока вышестоящее не в `main` — нижестоящий CI пиннит siblings к feature-веткам (`ref:`-строки)

---

# Таблица трассируемости (сценарий → секция дизайна)

| Сценарий | Область | Дизайн § |
|---|---|---|
| docs-A-01 | Тема dark | §3, §4, §11 |
| docs-A-02 | Тема light | §4 |
| docs-A-03 | Бренд | §4 |
| docs-A-04 | Pagefind ⌘K | §5 P7, §11 |
| docs-A-05 | Анти-дрейф токенов | §4 |
| docs-B-01 | OpenAPI 3.1 gen | §6.1 |
| docs-B-02 | Фильтр RED→GREEN | §6.2, §6.3, §12.2 |
| docs-B-03 | allowlist канонизация | §6.2, §10, §12.2 |
| docs-B-04 | suffix-verbs distinct | §5 P1, §6.3, §12.3 |
| docs-B-05 | surface-snapshot mapping | §6.3 |
| docs-B-06 | drift-гейт | §6.3 |
| docs-B-07 | overlay examples | §6.4 |
| docs-B-08 | Operation-обогащение | §6.3, §5 P4 |
| docs-C-01 | persona-tabs | §5 P2, §7 |
| docs-C-02 | AI-track все ветки | §7 |
| docs-C-03 | ApiRefLink deep-link | §7, §8 |
| docs-C-04 | запрет условного MDX | §5 P2, §7 |
| docs-D-01 | IA / sidebar | §8, §8.1 |
| docs-D-02 | VPC 8 ресурсов | §8.2 |
| docs-D-03 | IAM/Compute stub | §8.1 |
| docs-D-04 | AddressPool отсутствует | §8.2, §9 |
| docs-D-05 | Quickstart | §8, §7 |
| docs-E-01 | llms.txt excludes | §5 P3, §9 |
| docs-E-02 | per-page .md | §5 P3, §7 |
| docs-E-03 | AI-actions | §5 P3, §11 |
| docs-E-04 | AI-страница | §8, §5 P3 |
| docs-E-05 | llms-txt resilience | §5 P3 |
| docs-F-01 | snippet-import | §5 P6, §7 |
| docs-F-02 | examples компилируются | §5 P6, §11 |
| docs-G-01 | OperationEnvelope | §5 P4 |
| docs-G-02 | async-Operations концепт | §5 P4, §8 |
| docs-G-03 | мутации → Operation | §8.2, §5 P4 |
| docs-H-01 | tripwire RED→GREEN | §9, §6.3, §12.2 |
| docs-H-02 | полный список токенов | §9, CLAUDE.md infra |
| docs-H-03 | PRIMARY-фильтр недостижимость | §9 |
| docs-H-04 | CONTENT-гард | §9 |
| docs-I-01 | Docker-образ | §3.2, §10 |
| docs-I-02 | nginx no-SPA | §3.2, §9 |
| docs-I-03 | Cache-Control smoke | §3.2, §9, §12.3 |
| docs-I-04 | чистый npm ci | §3.1, §12.3 |
| docs-I-05 | CI-pipeline | §10 |
| docs-I-06 | kacho-deploy wiring | §10, §3.2 |
| docs-I-07 | порядок merge | §10, §12.1 |

---

# Definition of Done (чек-лист эпика)

## Net-new код — strict TDD RED→GREEN пары (§12, §12.2)

- [ ] `cmd/openapi-filter` unit-тест: **RED** (фикстура с Internal/AddressPool → ожидание отсутствия → падает без фильтра) → **GREEN** (фильтр роняет Internal/AddressPool, сохраняет public AddressService) — docs-B-02
- [ ] CI infra-leak tripwire fixture-тест: **RED** (подброшенный `AddressPool` роняет grep) → **GREEN** (чистый dist проходит) — docs-H-01
- [ ] `examples/*` компиляция/линт: **RED** (внесённая ошибка роняет CI) → **GREEN** — docs-F-02
- [ ] api-gateway allowlist-переезд: существующие `allowlist`/`director`/`server` тесты остаются зелёными (regression-guard) — docs-B-03

## Acceptance-артефакты (snapshot / diff)

- [ ] starlight-openapi snapshot: suffix-verbs (`:addCidrBlocks/:removeCidrBlocks/:move/:relocate/:setAccessBindings`) — distinct operations; 0 Internal/AddressPool — docs-B-04
- [ ] `gen/openapi/_surface-snapshot.json` коммитнут; каждая survived-операция ∈ allowlist, 0 Internal survived; enumerated VPC-mapping сверен — docs-B-05
- [ ] `verify-openapi` (`git diff --exit-code gen/openapi/`) зелёный в CI — docs-B-06

## Контент и UX

- [ ] Тема-паритет dark+light с kacho-ui (токены §4 verbatim), Inter self-hosted, KachoLogo — docs-A-01/02/03/05
- [ ] Pagefind ⌘K-палитра работает — docs-A-04
- [ ] persona-tabs `<Tabs syncKey="persona">` на Quickstart + how-to + каждой VPC-концепции; `<ApiRefLink>` deep-link — docs-C-01/03
- [ ] IA полная: Обзор/Quickstart/Концепции/How-to/API Reference/Работа с API/AI/Релизы-stub; RU-root + EN-scaffold — docs-D-01
- [ ] VPC concept — 8 публичных ресурсов полностью (БЕЗ инфры, NIC-divergence задокументирован); IAM/Compute — stub+reference-link (boundary) — docs-D-02/03
- [ ] AddressPool отсутствует в публичных концептах и reference — docs-D-04
- [ ] llms.txt/full/small с excludes; per-page `.md`-маршрут; AI-actions в PageTitle; «AI и агенты»-страница — docs-E-01..04
- [ ] `<OperationEnvelope>` (proto-точная форма) + каноническая async-Operations-концепция; per-RPC типы из `(kacho.cloud.api.operation)` — docs-G-01/02
- [ ] verified examples слой 1: `remark-code-import` из компилируемых `examples/` — docs-F-01

## Infra-sensitivity (HARD)

- [ ] tripwire-grep по `dist`+`llms-full.txt` зелёный (0 совпадений по полному списку токенов); fixture-доказательство поимки — docs-H-01/02
- [ ] PRIMARY-фильтр: Internal/AddressPool/placement/SID/underlay недостижимы публично — docs-H-03
- [ ] CONTENT-review per-page public-fields-only (vault-инфра не скопирована) — docs-H-04

## Деплой и CI

- [ ] two-stage Docker-образ `docker.io/prorobotech/kacho-docs:KAC-N-<sha>` — docs-I-01
- [ ] nginx directory-index, БЕЗ SPA-fallback, БЕЗ proxy_pass; smoke `curl -I` на `/vpc/network/` → `no-store` (HTML) + `public, immutable` (`/_astro/*`) — docs-I-02/03
- [ ] чистый `npm ci` без `--legacy-peer-deps` (scaffold-критерий) — docs-I-04
- [ ] CI: check + `@scalar/cli validate` + build + tripwire + lychee link-check — docs-I-05
- [ ] kacho-deploy wiring (`build-docs`, umbrella sub-chart, `docs.kacho.local` ingress) — docs-I-06
- [ ] порядок merge соблюдён (proto → api-gateway → docs → deploy → workspace) — docs-I-07

## Процесс / trail

- [ ] integration/unit тесты + verified examples зелёные (с RED→GREEN-парами в PR-описаниях)
- [ ] vault обновлён (новый sibling kacho-docs: README + затронутые `edges/` proto↔gateway↔docs; `KAC/KAC-248.md` + `KAC-249.md`)
- [ ] EPIC KAC-248 + subtasks в текущем спринте; роли-исполнители/ревьюеры проставлены
- [ ] все PR merged в `main` своих репо; ветки `KAC-N` удалены после merge

## Границы MVP (явные non-goals — boundary-разметка, НЕ долг)

- Try-it playground (Scalar/Prism-mock), Hurl verified-execution (P6 слой 2), sandbox-proxy, `<OperationRunner>` live — **Phase 2**.
- Ask-AI RAG (Kapa/Inkeep), topology explorer (P5), semantic/hybrid search (Orama/DocSearch), doc-versioning, полный EN-перевод/промоут, GitMCP — **Phase 3** (E-04 помечает их boundary в доках).
