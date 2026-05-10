# kacho-ui — добивание YC-редизайна (фаза 1.x продолжение)

**Дата:** 2026-05-10
**Статус:** DESIGN — ожидает review пользователем
**Скоуп:** только `project/kacho-ui/`. Backend (api-gateway, vpc, resource-manager) не трогаем — все API контракты сохраняются.
**Связан с:** `docs/specs/sub-phase-1.x-ui-yc-redesign-plan.md` (формально APPROVED 2026-05-10, фактически наполовину). Этот документ — продолжение и уточнение.

---

## 1. Контекст

В `kacho-ui` за прошлые итерации сделана половина YC-style редизайна: AntD `darkAlgorithm`, Cloud/Folder pills, `DetailShell`, `ResourceCreatePage`, `RowActionsMenu`, `VpcSubNav`, кастомные detail-страницы для Subnet/SG/AddressPool. Нужно довести оставшийся объём (28 gap'ов) и закрепить shell-фундамент так, чтобы дальнейшие фичи на нём собирались без перекраивания layout'а.

Аудит фактического vs YC reference (35 PNG в `project/kacho-vpc/docs/scrins/`) выявил 28 gap'ов в 5 категориях: Shell (5), Dashboard (4), List (6), Detail (6), Create+Flow (7). Все одобрены к работе.

## 2. Скоуп

**В скоупе:**
- 28 gap'ов из аудита (см. §4 — распределение по PR).
- Shell-foundation: icon-only sidebar 56px, tree → Cloud-pill dropdown, detail-layout с двумя боковинами, sticky banner для async ops, удаление мёртвого Tailwind theme.
- Vertical slices «Сеть», «Подсеть+IP», «SG» — в каждом доводим Create flow, Detail content и List polish для соответствующего домена.
- Dashboard tile-row + onboarding empty-state.
- IPAM admin preview в Address Create (label-selector resolve → какой pool сработает).

**Out of scope:**
- DELETE через UI как реальная операция — кнопка остаётся `DeleteConfirmStub`-заглушкой (правило kacho-test: не пишем DELETE-сценарии).
- Bulk operations (multi-select), light theme переключатель, локализация (`ru` only остаётся), pixel-perfect соответствие YC шрифтам.
- B1 «Что нового / Управление виджетами» в Dashboard — у нас этого функционала нет.
- Backend изменения (новые RPC, миграции, схема). Если в процессе обнаружится отсутствующий filter/RPC (например, OperationService.List без `resource_id`) — фиксируем как TODO в этом spec'е, но **в этом редизайне не реализуем backend**. В UI делаем graceful fallback.
- Marketplace tile (нет в Kachō).

## 3. Принципы

1. **Структурное сходство с YC, не pixel-perfect.** Расположение блоков, навигация, типы виджетов (kebab, pill, breadcrumb, sticky banner) — копируем. Точные шрифты/цвета/радиусы — близкие.
2. **Backend untouched.** Любая нехватка данных — graceful fallback в UI (placeholder, скрытый tab) + TODO в этом spec'е. Не расширять публичный API под admin/UI.
3. **Foundation first.** PR 1 — shell+detail+async layer. Vertical slices в PR 2-4 опираются на готовый фундамент. Никаких «пол-старого пол-нового» состояний после PR 1 (rail/sub-pane/banner работают на всех страницах сразу).
4. **Один theme.** AntD dark tokens — единственный источник правды для цветов. Tailwind остаётся как утилитарный layout/spacing-инструмент, но `:root`/`.dark` CSS-переменные удаляются — пусть Tailwind utilities ссылаются на AntD CSS-vars (`var(--ant-color-*)`) либо удаляются.
5. **Verbatim YC API parity сохраняется.** Все admin-only нужды (preview pool, regions/zones — уже сделано) — через `/vpc/v1/regions`, `/vpc/v1/zones`, `/vpc/v1/addressPools` cluster-internal listener. На external TLS endpoint эти пути НЕ публикуются (см. `kacho-vpc/CLAUDE.md` §16.x).

## 4. Roadmap — 5 PR

Гибрид Foundation-first + Vertical-slice. Каждый PR на отдельной ветке `feature/ui-redesign-pr<N>-<topic>`, мержится в `main` независимо. После merge — short demo cycle перед следующим PR.

### PR 1 — Shell + Async foundation
**Цель:** убрать все cross-cutting layout-изменения, чтобы PR 2-5 не переписывали shell.
- A1 — sidebar 56px icon-only (новый компонент `VpcSidebar`).
- A2 — удалить Tailwind `:root`/`.dark` CSS-vars; Tailwind utilities → `var(--ant-color-*)` или удалить use-site.
- A3 — Cloud/Folder pills polish (контракт badge IN, иконки в 18px-square, ARIA).
- A4 — `HierarchyTree` уезжает из sidebar в Cloud-pill dropdown (двухуровневый tree Org→Cloud→Folder при клике на Cloud-pill).
- A5 + D1 — detail layout: icon-rail остаётся, появляется sub-pane 240px (resource info + tabs + Документация), main pane занимает остальное.
- C3 — убрать `PollingIndicator` plug; статус «offline» индексируется только через тост-ошибку при isError.
- C4 — стилизация `StatusBadge` под YC (без иконки, плотнее, h=18px).
- E5 — `OperationBanner` (sticky под header) заменяет `OperationDialog` для Create/Update flows. `OperationDialog` остаётся для verb-actions (Start/Stop/Restart) — не критично, можно мигрировать в PR 4.

**Trade-off:** PR 1 — самый большой по изменениям файлов (~12 файлов), но изменения механические. После него UI смотрится непривычно для уже-знающих, но фундаментально стабилен.

### PR 2 — Слайс «Сеть» + generic infra
**Цель:** end-to-end путь пустого облака → Network с детьми + закрепить generic FormSection mechanism.
- E1 — full-page Create вместо modal: для networks, через `ResourceCreatePage`. Старый modal-режим `ResourceFormDialog` остаётся для Edit; modal-Create в `BreadcrumbSelector` для Cloud/Folder переключаем на route в PR 5.
- E2 — generic `FormSchema.sections` infra + поле `ResourceSpec.formSections?: FormSection[]`. В PR 2 настраиваем для networks (две секции: «Общее» / «Подключения»). PR 3-4 — только заводят `formSections` для subnets/addresses/SG, не трогая infra.
- D5 — Network detail: вкладки `Подсети`, `Группы безопасности`, `Маршруты` inline (списки дочерних ресурсов с навигацией на их detail).
- E7 — onboarding: если в текущем folder нет Network — full-screen «Начнём с создания сети» в DashboardPage и в `/networks` list.
- C1 — gear column-toggle (на Networks-list — настраиваем механизм + storage; в PR 3 расширяем на Subnets/Addresses).
- C5 — verify click-name → detail везде (фикс если кое-где не работает).

### PR 3 — Слайс «Подсеть + IP»
**Цель:** end-to-end управление подсетью и резервированием IP.
- E1 для subnets и addresses (через generic `ResourceCreatePage`, infra уже из PR 2).
- E2 — заводим `formSections` для subnets (Общее / Сеть и зона / CIDR) и addresses (Общее / Тип адреса).
- E3 — Subnet Create: добавить **новую** поддержку query-prefill `?network_id=X` — при открытии из Network detail network read-only, immutable. CIDR-подсказка «Свободные внутри родительских v4_cidr_blocks» (вычисление client-side через `IpamUtilizationBar` логику). Для addresses query-prefill `?subnet_id=X&kind=internal` уже работает в коде, в PR 3 только добавляем CIDR-подсказку.
- D2 — `Операции` tab в Subnet detail. Backend-side filter `resource_id` отсутствует → fallback: список всех Operations за последние 24ч в folder, отфильтрованных client-side по metadata.
- D3 — secondary actions row на Subnet detail: «Перенести в зону» (`SubnetRelocateDialog`), «Привязать таблицу маршрутизации» (через UpdateRoutTableId mutation).
- D6 — Address detail редизайн: блок «Назначен ресурсу» (read-only список references из `references[]` поля API), pool-info для admin (если запрос идёт от UI у которого активна `kacho-only` секция).
- E4 — Address (external) Create: при выборе network — preview какой pool сработает (`InternalAddressPoolService.Check` — вызов через api-gateway internal mux).
- C2 — Subnets list: select «Все зоны доступности» (через `/vpc/v1/zones`).

### PR 4 — Слайс «Security Group»
- E1 для security-groups (через generic `ResourceCreatePage`).
- E2 — заводим `formSections` для security-groups (Общее / Сеть / Правила).
- E6 — SG Create wizard: переключатель «Базовый / Расширенный» в начале формы. Базовый — скрывает секцию `Правила` (создаётся пустая SG). Расширенный — показывает inline rules editor. Default — Базовый. Rules после создания добавляются на detail (Edit rules → `UpdateRules`).
- D4 — SG detail: split tabs `Входящий трафик` / `Исходящий трафик` (`SgRulesEditor` принимает prop `direction: "ingress"|"egress"|null`).
- C6 — SG list: chip `Default` рядом с именем default-SG (`default_for_network` уже в spec.columns как text — переделать в badge через `render` callback).
- Опционально (если осталось время): миграция OperationDialog → OperationBanner для verb-actions (Start/Stop/Restart на compute, когда тот появится).

### PR 5 — Dashboard + остатки
- B2 — info-tile row: 3 малых тайла (Квоты / Права доступа / Сервисные уведомления) — все заглушечные плашки без чисел.
- B3 — секция «Ресурсы» с inline `Поиск сервисов` строкой; добавить tile `Resource Manager` (counts: Clouds / Folders в текущем Org).
- B4 — VPC tile: 4-е поле «Публичных IP» (счётчик из /vpc/v1/addresses?type=external), яркая акцентная иконка.
- B5 — empty-state «нет ресурсов» переезжает inline в VPC-tile (вместо отдельной карточки внизу).
- Подчистка: что не вошло в PR 1-4 (E1+E2 для Org/Cloud/Folder, всё ещё через ResourceFormDialog modal? — переключить в PR 5 если нет времени в PR 1).

## 5. Architecture

### 5.1 Shell layout

```
┌─ Header (sticky, h=48) ─────────────────────────────────────────────────────┐
│ Logo │ CloudPill ▾ │ FolderPill[IN] ▾ │ ⊞ apps │ ⌂ home │ /breadcrumb │ CTA │
├──────┬──────────────────────────────────────────────────────────────────────┤
│ Rail │  ListPage / DashboardPage                                            │
│ w=56 │     (full-width main, без sub-pane)                                  │
│      │                                                                      │
│ ⌂🔍  │  ИЛИ                                                                 │
│ ⊟⊠⊕  │                                                                      │
│ ⇄⛛   │  DetailPage:                                                         │
│ ─    │  ┌─ Sub-pane (w=240) ─┬─ Main pane ─────────────────────────────────┐│
│ ⚙    │  │ Resource label     │ Tab content (Overview / IP-адреса / ...)    ││
│ 👤   │  │ Name + status      │                                              ││
│      │  │ Tabs               │                                              ││
│      │  │ Документация       │                                              ││
│      │  └────────────────────┴──────────────────────────────────────────────┘│
└──────┴──────────────────────────────────────────────────────────────────────┘
```

**Rail (w=56)** — `VpcSidebar` (новый), всегда виден. Иконки: ⌂ Dashboard, 🔍 Search, ⊟ Networks, ⊠ Subnets, ⊕ Addresses, ⇄ Route Tables, ⛛ Security Groups, разделитель, ⚙ System (Regions/Zones/Pools), 👤 Profile (заглушка). Tooltip on hover. Активный — заливка `var(--ant-color-bg-elevated)`, ширина выделения 4px вертикальная полоска слева как у YC.

**Sub-pane (w=240, только на detail)** — рендерится `DetailShell`. Внутри: малый caps-label (`ПОДСЕТЬ`), bold name, status badges, antd Menu с табами, в самом низу секция «Документация» с фиксированными ссылками per resource type. Не sticky внутри — full-height aside.

**Main pane** — `flex:1`, `min-width:0` (никаких overflow). Top-bar с secondary actions (для Subnet — «Перенести в зону», для SG — «Edit rules», ...). Под ним — content активного tab'а.

### 5.2 IA / навигация

- **Глобальная иерархия Org/Cloud/Folder** — через **Cloud-pill dropdown** (после A4 — Tree уезжает сюда). При клике на Cloud-pill — раскрывается dropdown, в нём antd `Tree`: Org → Clouds внутри Org → Folders внутри Cloud. Клик на Folder — `setContext(folder)` + navigate на текущий VPC-resource, сохраняя tail. Клик на Cloud — переход на `/clouds/:cloudId/folders` (list folders).
- **Sidebar (VpcSidebar)** — глобальный навигатор сервисов (VPC категории + System разделитель + Profile). Статичный — НЕ меняется per route.
- **Breadcrumb в header** — справа от pills. Формат: `<Service> / <Категория> / <Имя ресурса>`. На list-странице — `<Service> / <Категория>`. На dashboard — `Дашборд`.
- **Detail tabs** — внутри sub-pane (sub-pane = вторая боковина, не путать с main-pane top-tabs). Активный tab — через `?tab=<id>` query param. Default tab = первый.

### 5.3 Async UX (sticky banner)

```
┌─────────────────────────────────────────────────────────────┐
│ ⌛ Создание сети my-net... [Подробно]            [×]        │ ← sticky под header
└─────────────────────────────────────────────────────────────┘
```

`OperationBanner` — глобальный компонент, рендерится в `Layout` под Header'ом. Слот: показывается, когда в `useOperationStore` есть active operation. Состояния:

- **`pending`** (`done=false`) — spinner + текст «X-ing <name>...» + opaque link `Подробно` (открывает `OperationDialog` для подробностей operation_id/metadata) + dismiss `×`.
- **`success`** (`done=true && error=null`) — ✓ + текст. Auto-dismiss 5сек.
- **`error`** (`done=true && error!=null`) — ✗ + текст + persistent (требует ручного dismiss).

Один banner за раз — если идёт несколько операций, показывается последняя инициированная (FIFO queue из 1 элемента). При завершении — переключается на следующую из queue.

**Trigger:** Create / Update flows вызывают `operationStore.start(opId, title)` → mutation возвращает `Operation.id` → store начинает poll каждые 1сек.
**Replace `OperationDialog` modal:** для Create. `OperationDialog` остаётся для verb-actions (Restart/Start/Stop) — там UX modal оправдан (пользователь явно хочет ждать результат).
**Redirect after start:** Create — после `start()` сразу navigate(list). Список обновится через poll и покажет ресурс с status=CREATING.

### 5.4 Theme

Удаляем Tailwind `:root`/`.dark` CSS-переменные из `index.css`. AntD `darkAlgorithm` + custom tokens в `App.tsx` (уже настроены) — единственный источник цветов. Tailwind utilities остаются как layout/spacing helpers, но не должны определять цвета через CSS-vars `--background` / `--foreground` etc. Заменить usage на:
- AntD `theme.useToken()` (для inline styles, как уже делается в `Layout.tsx`).
- Tailwind `bg-[var(--ant-color-bg-container)]` / `text-[var(--ant-color-text)]` (для use-sites, где token-hook неудобен).

`<html class="dark">` НЕ устанавливаем — AntD сам перекрашивает body через injected CSS, нам нужен только AntD-режим, не Tailwind dark mode.

## 6. Component design

### 6.1 `Layout.tsx` (рефактор, PR 1)

**Сейчас:** AntD `Sider w=260` рендерит `HierarchyTree` или `VpcSubNav` per route. Header с pills.
**После:** AntD `Sider w=56` (новый компонент `VpcSidebar`). `HierarchyTree` уходит в `BreadcrumbSelector`. `OperationBanner` рендерится в Layout под Header (sticky, h=44).

```tsx
<AntLayout>
  <ContextUrlSync />
  <Header>...</Header>
  <OperationBanner />              // NEW
  <AntLayout>
    <Sider width={56}><VpcSidebar /></Sider>  // CHANGED
    <Content>...</Content>
  </AntLayout>
</AntLayout>
```

### 6.2 `BreadcrumbSelector.tsx` (расширить, PR 1)

Добавить `<HierarchyDropdown>` внутрь `CloudCrumb` — antd `Tree` со списком Org→Clouds. При expand узла Cloud — lazy load Folders. Click на Folder — `setContext` + navigate. Удаляет необходимость в `HierarchyTree` как отдельной боковой панели.

`FolderCrumb` — без изменений (уже работает).

### 6.3 `VpcSidebar.tsx` (новый, PR 1)

Заменяет существующий `VpcSubNav` для всех routes. Не контекстный — статичный список:

```ts
const ITEMS = [
  { key: "dashboard", icon: HomeOutlined, route: "/dashboard", tooltip: "Дашборд" },
  { key: "search", icon: SearchOutlined, route: "/system/search", tooltip: "Поиск" },
  { kind: "divider" },
  { key: "networks", icon: ApartmentOutlined, route: (folder) => `/folders/${folder}/networks`, tooltip: "Сети", requiresFolder: true },
  { key: "subnets", icon: ClusterOutlined, ... },
  { key: "addresses", icon: GlobalOutlined, ... },
  { key: "route-tables", icon: NodeIndexOutlined, ... },
  { key: "security-groups", icon: SafetyOutlined, ... },
  { kind: "divider" },
  { key: "system", icon: SettingOutlined, route: "/system/regions", tooltip: "Администрирование" },
];
```

`requiresFolder: true` — если folder не выбран, иконка disabled (visually muted, tooltip «Выберите folder»). Клик на disabled — navigate на dashboard.

Активный определяется по pathname match. Selection-стиль: 4px вертикальная полоска слева + `bg-elevated` заливка. Tooltip on hover (через antd `Tooltip` с placement="right").

`VpcSubNav.tsx` (старый) удаляется.

### 6.4 `DetailShell.tsx` (рефактор, PR 1)

Сейчас рендерится в `Content` без учёта sidebar. После PR 1: `Sider w=56` остаётся (VpcSidebar), `DetailShell` рендерит свой sub-pane w=240 + main внутри `Content`. Sub-pane содержит:

```tsx
<aside style={{ width: 240 }}>
  <header>          {/* label caps + name + badges */}
  <Menu mode="inline" items={tabs} />
  <div className="docs">
    <span className="label">Документация</span>
    <ul>{docLinks.map(...)}</ul>
  </div>
</aside>
<main style={{ flex: 1, minWidth: 0 }}>
  <SecondaryActionsBar>{secondaryActions}</SecondaryActionsBar>  {/* NEW prop */}
  <ActiveTabContent />
</main>
```

Новый prop `secondaryActions?: ReactNode` — рендерится в `SecondaryActionsBar` над content'ом main pane (используется в PR 3 для Subnet «Перенести в зону»).

Default `docLinks` — статические per resource type, как уже сделано (`DEFAULT_VPC_DOCS`). Добавить fallback per-spec из registry (поле `ResourceSpec.docLinks?: DocLink[]`).

### 6.5 `OperationBanner.tsx` + `useOperationStore` (новый, PR 1)

`useOperationStore` — Zustand или кастомный хук. State:

```ts
type OpState = {
  id: string | null;
  title: string;       // "Создание сети my-net"
  status: "pending" | "success" | "error";
  errorMessage?: string;
  startedAt: number;
};
```

Actions: `start({id, title})`, `markDone(success: boolean, errorMessage?)`, `dismiss()`.

`OperationBanner` подписан на этот store + поллит `/operations/{id}` каждые 1сек пока `pending`. На done — обновляет status, на success — `setTimeout(dismiss, 5000)`.

Migrating Create flows: в `ResourceCreatePage`, `ResourceFormDialog` (которая остаётся для Edit) — после успешного POST с extracted operationId:
```ts
operationStore.start({ id: opId, title: `Создание ${spec.singular} ${name}` });
navigate(listPath);  // редирект на list
```

`OperationToastWatcher` (старый) — устаревает; на текущей фазе оставляем для backward-compat в `BreadcrumbSelector` (Cloud/Folder Delete via toast). В PR 4 — переключаем тоже.

### 6.6 `ResourceListPage.tsx` (PR 1 + PR 2-4 incremental)

PR 1 изменения:
- Удалить `PollingIndicator` (C3).
- Стилизация StatusBadge (C4) — затрагивает все strings ListPage через `formatCell`.

PR 2 (механизм + для networks):
- Добавить `ColumnTogglePopover` — antd `Popover` с trigger gear-icon в right-top таблицы. Список колонок с чекбоксами. State в `localStorage` под ключом `kacho.columns.<spec.id>`. Применяется к `ResourceTable` через prop `enableColumnToggle: boolean` (default false → не ломает текущие use-sites; PR 3 включает для subnets/addresses).

PR 3 (для subnets):
- Добавить второй Select «Все зоны доступности» рядом с Input.Search. Filter — client-side по `zone_id`. Условный рендер на основе `spec.id === "subnets"` (либо новое поле `spec.listFilters?: FilterDef[]`).
- Включить `enableColumnToggle` для subnets/addresses.

PR 4 (для security-groups):
- В `ResourceTable` cell для `default_for_network` рендерим `<Tag>Default</Tag>` вместо text (через `ResourceColumn.render`).

### 6.7 `ResourceCreatePage.tsx` (PR 2-4)

Уже существует (полу-реализован). Доводим:
- Form sections: `FormSchema.sections: [{ title, fields: FormField[] }]` (E2). Поле `ResourceSpec.formSections?` в registry — если задано, рендерим по секциям; если нет — fallback к flat `fields`.
- Pre-fill из query: `?subnet_id=X&kind=internal` (уже работает) — расширяем для `?network_id=X` (Subnet Create из Network detail).
- Submit: вызывает `operationStore.start` + redirect (см. §6.5).

`ResourceFormDialog.tsx` — modal — остаётся для Edit. Удаляем modal-режим Create (он сейчас используется в `BreadcrumbSelector` для Cloud/Folder Create — переключаем на `<Link to="/clouds/create">`).

### 6.8 Domain pages (PR 2-4)

**`pages/NetworkDetailPage.tsx` (новый, PR 2)** — extends `ResourceDetailPage` с `extraTabs`:
- `Подсети` — `useResourceList(REGISTRY.subnets, "network_id", uid)`, рендерим compact-таблицу.
- `Группы безопасности` — analog.
- `Маршруты` — список Route Tables привязанных к этой Network (RT.network_id фильтр).

**`pages/SubnetDetailPage.tsx` (расширить, PR 3)** — добавить `secondaryActions`:
```tsx
<SecondaryActionsBar>
  <Button icon={<GlobalOutlined />} onClick={openRelocate}>Перенести в зону</Button>
  <Button icon={<NodeIndexOutlined />} onClick={openAttachRT}>Привязать таблицу маршрутизации</Button>
</SecondaryActionsBar>
```
Operations tab (D2) — компонент `<OperationsTab resourceId={uid} createdAfter={now-24h} />`. Поллит `/operations?folder_id=<X>&page_size=100`, фильтрует client-side по `metadata.<resource_type>_id == uid`. Если ни одной — empty-state «За последние 24ч операций по этой подсети не было».

**`pages/SecurityGroupDetailPage.tsx` (расширить, PR 4)** — `Обзор` tab + `Входящий трафик` tab + `Исходящий трафик` tab. `SgRulesEditor` принимает prop `direction: "ingress"|"egress"|null` для фильтрации.

**`pages/AddressDetailPage.tsx` (новый, PR 3)** — заменяет generic `ResourceDetailPage` для addresses. Tabs:
- `Обзор` — общие поля + блок «Назначен ресурсу» (если есть references).
- `Pool info` (admin-only) — какой pool сработал, label-selector — fetched через `InternalAddressService.GetByValue` или (если допилено backend) extra-поле в Get-response.

## 7. Data flow (что не меняется)

- `useQuery` polling 3-5сек везде остаётся.
- `useResourceList` (lib/use-resource-list.ts) — без изменений.
- `useFolderStore` / `useContext` — Zustand stores — не трогаем.
- `api` client (lib/api/client.ts) — без изменений.
- Operation polling сейчас идёт через `OperationDialog`/`useOperation`. Заменяется на `useOperationStore` → центральный poll. `useOperation` хук остаётся для verb-actions (Restart/Start/Stop).

## 8. Error / empty states

- **isError на List page:** существующий `<Alert type="error">` остаётся.
- **isError на Detail page:** существующий `<Alert>` + `<Button>Назад</Button>` остаётся.
- **Empty list (folder выбран, ресурсов нет):** в PR 2 заменяем generic message на per-resource onboarding emp-state. Network list при empty — full-screen «У вас нет сетей. Сеть нужна для ВМ и k8s. [Создать сеть]». Subnet list при empty + есть Networks — «У вас нет подсетей. Подсети живут внутри сетей. [Создать подсеть]». Аналогично для других.
- **No folder selected:** `<FolderRequiredEmpty>` (уже есть) — остаётся.
- **Operation error:** banner persistent + (опционально) `[Подробно]` link открывает `OperationDialog` со stack-trace.

## 9. Testing

**Unit (`vitest`):**
- `VpcSidebar` — рендерит правильные disabled states (no folder selected → folder-scoped icons disabled).
- `OperationBanner` — state machine pending → success → auto-dismiss.
- `useOperationStore` — start/markDone/dismiss поведение.
- `BreadcrumbSelector` — HierarchyDropdown lazy load Folders.

**E2E (`playwright`):**
- Существующие сценарии в `kacho-ui/e2e/` — должны проходить без изменений (поведение API не меняется). Если поломались — фикс selectors (icon-only sidebar — другие aria-label'ы).
- Новые: `networks-onboarding.spec.ts` — пустой folder → click «Создать сеть» → form filled → submit → banner pending → banner success → list показывает Network.
- `subnet-relocate.spec.ts` — Subnet detail → Перенести в зону → confirm → banner pending → list reflects.

**Manual smoke:**
- После каждого PR — manual прогон по сценариям из vertical slice.

## 10. Migration / cleanup

- Удалить `VpcSubNav.tsx` (заменён `VpcSidebar.tsx`) — после PR 1.
- Удалить `:root`/`.dark` CSS-vars из `index.css` — после PR 1, проверив что нет use-site (`grep -r 'var(--background)'` в `src/`).
- Удалить mode `create` из `ResourceFormDialog.tsx` — после PR 5 (когда все Create через `ResourceCreatePage`).
- `OperationDialog.tsx` — оставить для verb-actions; в PR 4 опционально мигрировать тоже.

## 11. Open risks / TODO

1. **OperationService filter `resource_id`** не существует в API. Workaround: list-then-filter client-side (limit page_size=100, since=24h). Если в folder >100 ops/day — будет потеря событий. **TODO для backend (вне scope этого spec'а):** добавить `OperationService.List(folder_id, resource_id?)` с index'ом по metadata.
2. **`InternalAddressPoolService.Check`** — вызов из UI требует, чтобы api-gateway пробрасывал internal-mux на cluster-internal listener. Это уже сделано (см. `kacho-vpc/CLAUDE.md` §16.x). Но E4 требует либо `Check` либо custom RPC. **Action:** проверить наличие `Check`-RPC при старте PR 3; если нет — реализовать как `kacho-only` admin-RPC в `InternalAddressPoolService`.
3. **`StatusBadge` styling** — придётся переписать `<Tag>` rendering, чтобы не зависеть от status-text. Чтобы не сломать существующие use-sites — компонент остаётся API-совместимым (props не меняем), меняется только внутренний render.
4. **Hierarchy dropdown loading** — двухуровневый Tree с lazy-load Folders может тормозить если в Cloud >50 folders. Mitigation: virtualization через antd `Tree` virtual mode (есть из коробки).
5. **Vertical-slice merge order** — PR 2-4 могут идти параллельно после PR 1, но E1+E2 generic-механизм (form sections schema) лучше доделать в PR 2 и в PR 3-4 расширять. Если несколько разработчиков — закрепить за одним PR 2 first.

## 12. Success criteria

После всех 5 PR:
- 28/28 gap'ов закрыты (см. аудит-чеклист).
- Все existing playwright тесты проходят.
- Smoke-сценарии из §9 проходят manually.
- `grep -r "VpcSubNav\|--background\|--foreground" src/` — пусто (удалили мёртвый код).
- Визуально сравнимо с YC reference (не pixel-perfect, но узнаваемая структура).
- DELETE-кнопки везде остаются заглушками (`DeleteConfirmStub`).
- Backend не тронут (`git diff --stat` по project/kacho-vpc, project/kacho-resource-manager, project/kacho-api-gateway = 0 строк).

---

## Approve gate

Не начинаю писать план реализации (writing-plans), пока пользователь не подтвердит:
1. Roadmap (5 PR, гибрид A+B) — OK или поправки?
2. Architecture §5 (icon-rail + sub-pane + sticky banner) — OK?
3. OperationDialog → OperationBanner для Create only (verb-actions остаются modal в PR 1) — OK?
4. Удалить Tailwind `:root`/`.dark` CSS-vars (вместо подключить `<html class="dark">`) — OK?
5. Open risks §11 — что-то критично нужно решить до PR 1, или fall-through ОК?

После approve — invoke `superpowers:writing-plans` для PR 1.
