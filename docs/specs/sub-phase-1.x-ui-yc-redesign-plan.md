# Sub-phase 1.x — kacho-ui redesign под YC console look-and-feel

**Status:** APPROVED 2026-05-10
**Дата:** 2026-05-10
**Скоуп:** только `project/kacho-ui/`. Backend (kacho-api-gateway, kacho-vpc, kacho-resource-manager) **не трогаем** — все API-контракты сохраняются.

## 0. Зафиксированные решения (after approve 2026-05-10)

1. **Phase F (Dashboard)** — делаем только VPC tile. Cloud DNS / IAM tile'ы не показываем (у нас их нет).
2. **Кнопка «Удалить»** в kebab — confirm-заглушка («Удаление через UI временно отключено»). Согласуется с правилом kacho-test «не пишем DELETE-сценарии». Реальный Delete-RPC не вызывается.
3. **Палитра §A.1** — стартуем с предложенной. Корректировки внутри Phase A — одной CSS-переменной.
4. **Доставка** — один PR с 5 commits (по фазе A→E + F-commit). Ветка `feature/ui-yc-redesign`.

---

## 1. Зачем

Текущий kacho-ui — функциональный generic CRUD (REGISTRY-driven), но визуально и структурно далёк от YC console: светлая тема, широкий sidebar с лейблами, плоские таблицы без per-row actions, detail-страницы без sub-nav и блока «Документация».

Целевые скрины (`project/kacho-vpc/docs/scrins/`, 35 PNG, 7 категорий: networks, subnets, addressExternal, addressInternal, routeTable, securityGroups, gateway + root dashboard) фиксируют YC-console reference. Они показывают **структурный шаблон**, не пиксельный эталон.

## 2. Принципы (зафиксированы пользователем)

1. **Структурное сходство, не pixel-perfect.** Расположение блоков, навигация, типы виджетов (kebab, pill, breadcrumb) — копируем. Точные шрифты, цвета, радиусы — близкие, но не идентичные.
2. **Все 7 VPC категорий за одну итерацию.** Никаких per-category PR — иначе UI будет в течение недель в полу-старом-полу-новом виде.
3. **Сначала shell, потом контент.** Theme + sidebar + header — phase A. Пока shell не утвердим, list/detail не трогаем.
4. **Backend контракты неизменны.** Любая нехватка данных → новый Internal-RPC согласно правилам `kacho-vpc/CLAUDE.md` §16.y, **не** расширяем публичный verbatim-YC API.

## 3. Целевой визуальный язык (выжимка из 35 скринов)

### 3.1 Shell

- **Тема:** dark by default. Background `#1c1d22` (≈ HSL `225 9% 12%`), card `#26272d` (≈ `225 8% 16%`), borders subtle `#383941`. Light theme — out of scope этой итерации.
- **Sidebar (left):** narrow icon-only, ширина ≈ 56–60px. Иконки сервисов (для нас — пока только VPC-домены + System). На detail-страницах sidebar **не меняется** — это глобальный навигатор сервиса.
- **Header (top):** высота ≈ 48–52px, состоит из:
  - Logo Kachō (компактный, 24×24).
  - **Cloud pill** `cloud-uid-vf465ie7` с chevron-dropdown.
  - **Folder pill** `IN in-cloud` (badge `IN` + название) с chevron-dropdown.
  - Иконки: «облачный navigator» (apps), «home» (dashboard).
  - Breadcrumb справа от pills: `Virtual Private Cloud / Сети / <name>`.
  - Справа: при hover на ресурс — primary action button (`Создать сеть` / `Создать таблицу маршрутизации`).
- **Левый sub-nav на detail-страницах:** появляется ТОЛЬКО внутри detail. Содержит:
  - Заголовок ресурса + бейдж типа.
  - Tabs: `Обзор` (всегда), плюс контекстные (`IP-адреса` для Subnet, `Операции` для всех).
  - Внизу — блок `Документация` со ссылками (статичный список 5–6 ссылок).

### 3.2 List page

- Заголовок страницы слева вверху (`Сети`, `Группы безопасности`).
- Под заголовком — `Фильтр по имени или идентификатору` (один input).
- Primary CTA в правом верхнем углу header'а (а не на page level).
- Таблица: sortable columns (`Имя ↕`, `Идентификатор ↕`, `Дата создания ↕`); справа — gear-icon column-config; крайняя правая колонка — kebab `…` per-row → dropdown:
  - `Редактировать` (всегда)
  - `Переместить` (если ресурс поддерживает Move)
  - `Включить/Отключить защиту от удаления` (если есть `deletion_protection`)
  - `Редактировать метки` (если ресурс — Address)
  - `Удалить` (красный, в самом низу — НО см. §6 «Out of scope»)
- Identifier колонка — monospaced, без полного префикса; click копирует.
- `Default`-бейдж рядом с именем (для default SG).

### 3.3 Detail page

- Header: breadcrumb с именем ресурса + справа `Редактировать` / `Переместить` / kebab.
- Сразу под header — left sub-nav (см. 3.1) + правая основная панель.
- Основная панель: секции `Общее`, `Правила` / `Назначения` / etc. — каждая с заголовком, поля выровнены (`label: 200px / value: остальное`).
- Внизу sub-nav (sticky bottom) — блок `Документация` с фиксированным списком ссылок (берём из YC docs).

### 3.4 Create modal/page

YC console использует **полноэкранные «формы»**, не модалки. Hash-route `?create=1` → отдельная страница с breadcrumb `... / Создать`. Поля сгруппированы:
- `Общее` (Имя, Метки, Описание).
- Domain-specific (Сеть, Зона, CIDR, Правила).
Кнопки `Создать <X>` / `Отменить` снизу слева.

### 3.5 Create flow для Subnet/Address (важная особенность)

Из скринов addressInternal видно: **резервирование internal IP инициируется из Subnet detail → tab «IP-адреса» → CTA `Зарезервировать IP-адрес`**. CIDR родительского subnet'а отображается read-only. Это значит — добавляем context-aware форму: при открытии Address create из Subnet detail, `subnet_id` зафиксирован, `_address_kind=internal`, CIDR показан подсказкой.

## 4. Текущее состояние (audit)

- `src/components/Layout.tsx` — top header (h-14) + left sidebar (w-60) с лейблами и группами (`VPC`, `System`). Используется light theme.
- `src/index.css` — определены `--background`/`--foreground`/etc. для light + dark, но `dark` класс нигде не активируется (всегда light).
- `tailwind.config.js` — `darkMode: "class"`. Цвета через CSS-переменные (хорошая основа).
- `ResourceTable.tsx` — generic таблица; уже умеет рендерить ResourceSpec.columns.
- `ResourceListPage.tsx` — заголовок + Create-кнопка inline (а не в header'е).
- `ResourceDetailPage.tsx` — generic; нет sub-nav, нет Документация block, нет per-resource tabs.
- `ResourceFormDialog.tsx` — модалка, не full-page (надо переделать в route, но это можно отложить — см. фазы).
- Custom: `SubnetDetailPage.tsx`, `AddressPoolDetailPage.tsx`, `SystemSearchPage.tsx`.
- Per-row kebab dropdown отсутствует (есть DeleteButton inline).
- Cloud/Folder pills — частично есть в `BreadcrumbSelector.tsx`, но рендерятся как обычная цепочка, не pills.

## 5. Фазы

### Phase A — Shell + Theme (затрагивает все экраны, минимальная функциональная нагрузка)

**Файлы:**
- `src/index.css` — переписать `:root` и `.dark` на YC-палитру (ниже §A.1). Активировать dark по умолчанию через `<html class="dark">` в `index.html` или `main.tsx` (без переключателя на этой фазе).
- `tailwind.config.js` — расширить fontFamily (Inter/SF), добавить border-color tokens (`--border-strong`).
- `src/components/Layout.tsx`:
  - Header: переписать на pills (Cloud + Folder), home icon, app-grid icon, breadcrumb справа. Высота 48–52px.
  - Sidebar: переписать на icon-only, ширина 56px, tooltip на hover. Уже существующие 9 NAV items сохраняем — только переключаем на icon-only режим.
  - Primary CTA в header'е (передаётся через React context `<PageActions>` или slot prop у Outlet — выберу slot prop, проще).
- `src/components/BreadcrumbSelector.tsx` — переделать в два отдельных pill-компонента (`<CloudPill>`, `<FolderPill>`) с dropdown'ом «Сети / Поиск / Создать сеть».
- Новый `src/components/PageHeaderSlot.tsx` — context-провайдер для Primary CTA в header'е.

**Принимаемый critery:** все существующие страницы открываются, выглядят темно, sidebar узкий, header с pills. Никакая функциональность не сломана.

### Phase B — List pages (общий generic, применится к 7 категориям)

**Файлы:**
- `src/components/ResourceListPage.tsx` — Primary CTA убираем из page-body, регистрируем в `PageHeaderSlot`. Заголовок страницы (`<h1>`) под header'ом.
- `src/components/ResourceTable.tsx`:
  - Sortable headers (стрелки ↕). Local sort — без backend, by `name`/`id`/`created_at`.
  - Gear-icon column-config (открывает popover «какие колонки показывать», state в localStorage). MVP: статичный список колонок без persist — потом доделаем.
  - Right-most kebab `…` per-row → dropdown с действиями. Действия описываются декларативно в `ResourceSpec.rowActions`:
    ```ts
    rowActions?: Array<{
      id: "edit"|"move"|"toggle-protection"|"edit-labels"|"delete";
      label: string;
      icon: LucideIcon;
      destructive?: boolean;
      visible?: (item: any) => boolean; // hide for default SG etc
      onClick: (item: any, ctx: ActionCtx) => void;
    }>
    ```
  - Identifier колонка — `<CopyableId>` (уже есть).
- `src/lib/resource-registry.ts` — добавить rowActions для всех 7 VPC ресурсов согласно тому, что предлагает YC (см. §A.2 ниже).

### Phase C — Detail pages

**Файлы:**
- Новый `src/components/DetailShell.tsx` — обёртка с left sub-nav + main panel + bottom Документация block.
  - Props: `resource: { name, type, badge? }`, `tabs: Tab[]`, `docLinks: { label, href }[]`.
- `src/components/ResourceDetailPage.tsx` — переписать на использование `DetailShell`. Текущий «monolithic Обзор» становится `Обзор` tab.
- `ResourceSpec.detail` — расширить:
  ```ts
  detail?: {
    tabs: Array<{ id: string; label: string; render: (item) => ReactNode }>;
    docLinks: { label: string; href: string }[];
  }
  ```
- Default tabs: `Обзор` (текущая ResourceDetailPage logic) + `Операции` (новая — list ops по resource_id, через `?resource_id=` query — **проверить, поддерживает ли OperationService такой фильтр; если нет — оставить tab placeholder и записать в TODO**).
- Subnet detail: добавить `IP-адреса` tab (использовать существующий `<SubnetCidrManager>` + новый список internal addresses через `/vpc/v1/addresses?subnet_id=<X>` — этот RPC уже есть как `Address.ListBySubnet`, см. kacho-vpc CLAUDE.md §1).
- SecurityGroup detail: добавить tabs `Входящий трафик` / `Исходящий трафик` (split существующих rules по direction).

### Phase D — Create flow в page-mode

**Файлы:**
- Новый `src/components/ResourceCreatePage.tsx` — full-page форма (вместо ResourceFormDialog modal).
- Routes: `/folders/:folderId/<resource>/create` → `<ResourceCreatePage spec={...}>`.
- Контекстный pre-fill: при открытии из Subnet `IP-адреса` tab — query `?subnet_id=<X>&kind=internal` → форма стартует с заполненными полями (immutable input).
- Header CTA `Создать <X>` теперь линкует на route, а не открывает modal. Modal-вариант оставляем как fallback (DeleteButton-confirm и Edit остаются модалками).
- Поля: визуально перейти на YC-style sections (`Общее` group + domain-specific sections) — добавить `FormSection` обёртку в `form-schema.ts`:
  ```ts
  export type FormSchema = { sections: { title: string; fields: FormField[] }[] }
  ```
  В registry уточнить группировку для каждого ресурса.

### Phase E — Domain-specific actions per category

После phase B у нас уже есть declarative `rowActions`. Здесь — наполнение:

| Ресурс | rowActions (из YC скринов) |
|---|---|
| Network | Редактировать / Переместить / Удалить |
| Subnet | Редактировать / Перенести в другую зону (Relocate) / Включить защиту от удаления / Удалить |
| Address (external) | Редактировать / Переместить / Редактировать метки / Включить защиту от удаления / Удалить |
| Address (internal) | Переместить / Редактировать метки / Включить защиту от удаления / Удалить |
| RouteTable | Редактировать / Переместить / Удалить |
| SecurityGroup | Редактировать / Переместить (default SG — без Удалить) |
| Gateway | Редактировать / Переместить / Удалить |

Domain actions:
- Subnet **Relocate** — modal-confirm + dropdown зон (используем `InternalZoneService`, который мы уже подключили на прошлом шаге).
- SG **UpdateRules** — full-page editor с tabs Входящий/Исходящий (используем существующий `SgRulesEditor`).
- Address **AllocateExternalIP** — internal RPC, но нужен для UI workflow «Зарезервировать IP-адрес» (см. screenshot addressInternal/image copy 3). Триггерится из Address Create flow.

### Phase F (optional, можно выкинуть) — Dashboard

Root дашборд (`scrins/image.png`) — 3 tile'а Cloud DNS / IAM / Virtual Private Cloud со счётчиками. Cloud DNS / IAM у нас не реализованы. **Предлагаю Phase F вынести из этой итерации** — в текущем Kachō только VPC + Resource Manager. Сделать dashboard-tile только для VPC (счётчики Networks/Subnets/SGs в текущем folder) — это 1 файл, можно за час. **Решение оставляю на approve.**

## 6. Out of scope этой итерации

- **Удаление ресурсов** через UI — пользователь явно сказал «никогда не пишем DELETE-сценарии тестов» (CLAUDE.md kacho-test). Кнопка `Удалить` в kebab может быть, но только как заглушка с confirm-dialog «Удаление через UI отключено» — или вообще скрыть. **Решение на approve.**
- Multi-select на List page (bulk operations).
- Поиск (System Search) — оставляем как есть в текущем виде.
- Smart fuzzy filter в таблицах — пока только одна строка `Фильтр по имени или идентификатору` (sub-string match локально).
- Локализация (en/ru) — сейчас всё ru, оставляем.
- Light theme переключатель.
- Pixel-perfect соответствие YC шрифтам и иконкам.

## 7. Файлы которых план НЕ касается

- `src/api/*` — API client, никаких изменений.
- `src/lib/folder-store.ts` — Zustand store, оставляем.
- Backend (kacho-api-gateway, kacho-vpc, kacho-resource-manager) — нулевые изменения.

## 8. Риски и unknowns

1. **OperationService filter by resource_id.** Не уверен, что текущий `OperationService.List` принимает `?resource_id=<X>`. Если нет — `Операции` tab на detail-странице покажет либо ВСЕ ops по folder'у, либо placeholder. **Action item:** проверить kacho-corelib/operations при старте Phase C.
2. **InternalAddressService.AllocateExternalIP** — пока вызывается controller'ом async после Network outbox. Если делать UI «Зарезервировать IP-адрес» с inline allocation, нужно либо ждать controller (poll Operation), либо вызывать internal-RPC напрямую через api-gateway internal mux. **Предпочтительный путь:** poll Address.external_ipv4.address до non-empty (тот же паттерн что у других async ops).
3. **Размер изменения.** ~12–15 файлов изменения, ~3–5 новых файлов. Один PR, но логически делится на 5 коммитов (по фазам A→E).
4. **Регрессии.** Текущий Layout/ResourceDetailPage используется для Resource Manager (Org/Cloud/Folder) — они не на скринах. Применяем тот же shell, но **не** добавляем им domain-specific tabs/actions. Они будут выглядеть «голо» (Обзор + Операции tabs) — это OK.

## A. Аппендикс

### A.1 Палитра (предложение)

```css
.dark {
  --background:        225 9% 12%;   /* page bg #1c1d22 */
  --foreground:        220 14% 88%;  /* text */
  --card:              225 8% 16%;   /* cards/inputs */
  --card-foreground:   220 14% 88%;
  --primary:           211 100% 60%; /* CTA blue (YC-style) */
  --primary-foreground: 0 0% 100%;
  --secondary:         225 8% 22%;   /* nav-item hover/active */
  --secondary-foreground: 220 14% 88%;
  --muted:             225 8% 18%;
  --muted-foreground:  220 9% 56%;
  --accent:            225 8% 22%;
  --accent-foreground: 220 14% 88%;
  --destructive:       0 73% 56%;
  --destructive-foreground: 0 0% 100%;
  --border:            225 8% 22%;
  --radius:            0.4rem;
}
```

### A.2 Цветовая семантика бейджей

- `Active` — green `#1a9c52` (`bg-emerald-700/30 text-emerald-400`).
- `Default` — neutral pill `bg-muted text-muted-foreground border`.
- `IN` (internal) badge у Folder — square pill `bg-blue-700/40 text-blue-300`.
- Status `CREATING`/`DELETING` — amber.
- Error/failed — destructive.

## 9. Гейт approve

**Не приступаю к коду, пока пользователь не подтвердит:**
1. Phase A scope (shell first) — OK / поправки?
2. Phase F (Dashboard) — делаем только VPC tile или вообще выкинуть?
3. Кнопка `Удалить` в kebab — заглушка-confirm / hide совсем / оставить рабочей?
4. Палитра в §A.1 — OK для старта или пользователь хочет точную выборку из конкретного скрина?

После approve — открываю отдельные задачи на phase A → E последовательно.
