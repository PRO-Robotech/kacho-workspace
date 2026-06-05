All facts now verified. The relocation approach is clean: `kacho-proto` is module `github.com/PRO-Robotech/kacho-proto`, depends on nothing internal, and api-gateway already imports from it. The `(kacho.cloud.api.operation)` extension is field 87334 in `proto/kacho/cloud/api/operation.proto`, confirming the P4 enrichment mechanism is real.

I now have everything to write the revised spec resolving every issue. Key corrections:
- **Verified counts**: 62 `*_service.proto`; **50** carry `google.api.http` (not 51/52); 6 Internal protos carry http (`internal_catalog`, `internal_cluster`, `internal_iam`, `internal_user`, `internal_address_pool`, `internal_cloud`)
- **Custom verbs**: `:move`, `:relocate`, `:add-cidr-blocks`, `:remove-cidr-blocks`, `:setAccessBindings` confirmed; `:cancel` exists but on the **public** OperationService (not a leak concern)
- All proto3, no editions — drop the editions-panic risk
- **Decision made** on allowlist: relocate into kacho-proto, refactor api-gateway as a required epic subtask

Here is the full revised markdown.

---

# kacho-docs — дизайн-документ публичного документационного портала Kachō

> **СТАТУС ДОКУМЕНТА (читать первым).** Это **pre-acceptance design input** — проектный вход, НЕ утверждённый план к исполнению. Согласно gate #1 (workspace CLAUDE.md §«Запреты» #1) **никакой scaffold / код не начинается** до APPROVED Given-When-Then acceptance-документа (`docs/specs/sub-phase-X.Y-kacho-docs-acceptance.md`, автор — `acceptance-author`, approve — `acceptance-reviewer`) и заведённого YouTrack-**EPIC** с subtasks. Следующий шаг после этого документа — именно acceptance-author → acceptance-reviewer → EPIC, и только потом первый коммит. Формулировки «решено, не пересматривать» ниже относятся к **выбору технологий и архитектуре**, обкатанным в исследовании; они становятся обязательными только после APPROVE. MVP-влияющие решения, ранее висевшие как «открытые вопросы» (locale-primary, канонизация allowlist, asymmetry full-reference-vs-stub-concepts), в этой ревизии **закрыты решениями** — см. §1.1, §6.2, §8.1. Реально откладываемые вопросы (sandbox-lifecycle, Ask-AI residency, версионирование) демотированы в Phase-2/Phase-3-секции, а не висят как блокеры ясности.

> **⚠️ SCOPE-РАЗВОРОТ (2026-06-05, решение заказчика).** Документация делается
> **самодостаточной** — backend-репо (`kacho-proto`, `kacho-api-gateway`) НЕ трогаем.
> **Дескоупнуто:** P1 spec-driven API-reference из proto (§6 целиком — proto→OpenAPI,
> canonical allowlist в kacho-proto, openapi-filter, starlight-openapi), а также парный
> рефактор api-gateway и proto-comment hygiene. Соответствующие тикеты KAC-251/253/254/260
> откачены/отменены (backbone-PR'ы reverted: kacho-proto#47, kacho-api-gateway#64).
> **Остаётся в MVP:** scaffold+тема (P7), VPC-концепции + persona-tabs с **hand-written**
> REST/Go/Python примерами (P2), «Работа с API» guide, AI-native llms.txt/copy-as-md (P3),
> static OperationEnvelope (P4), compiled-snippets (P6 layer1), деплой `docs.kacho.local`.
> API-справочник, если понадобится, — ручной в самих доках или будущее улучшение
> (proto-gen-подход сохранён ниже в §6 как опция, не как текущий план).

## 1. Что это и зачем

**kacho-docs** — отдельный публичный статический сайт документации платформы Kachō (host `docs.kacho.local`, аналог публичного docs-портала облака), собранный на **Astro Starlight** и развёрнутый как статика за nginx в Kubernetes. Это новый sibling-репозиторий полирепо (`git@github.com:PRO-Robotech/kacho-docs`, клонируется в `project/`, собственный `.git`/CI/deploy — НЕ Go-сервис).

Центральный принцип — **«один источник — три читателя»**: единый корпус MDX + spec-driven артефактов одновременно обслуживает три аудитории без скрытых ветвлений контента:

1. **Конечный пользователь / оператор консоли** — концепции + click-through how-to.
2. **Разработчик публичного API** — интерактивный API-reference, мульти-язычные SDK-сниппеты, runnable-примеры.
3. **AI-агенты** (Claude Code / Cursor / ChatGPT + on-site ассистент) — LLM-native выдача: `llms.txt`/`llms-full.txt`, per-page `.md`, docs-as-MCP. Это «2026»-дифференциатор.

Все три читателя видят **один и тот же контент по построению**: проза пишется руками как MDX, API-контракт **генерируется** из центрального `kacho-proto` и перегенерируется в CI с git-diff drift-гейтом — документация никогда не расходится с API. На публичную поверхность по построению попадают **только публичные RPC**: спецификация фильтруется против **канонического allowlist, который переезжает в `kacho-proto`** (§6.2) ещё на этапе генерации (Internal.*-сервисы и admin-ресурсы вроде AddressPool исключены). Тема механически совпадает с kacho-ui (эстетика «Layered Calm») через маппинг `--kc-*` → `--sl-color-*` в одном CSS-файле, без форка Starlight.

### 1.1. Locale-primary — РЕШЕНО (RU-primary, EN-scaffold под `/en/`)

> **Это MVP-решение, а не отложенный вопрос** — `defaultLocale` запекается в каждый URL, поэтому решается ДО scaffold (сменить позже дорого: индексированные URL, входящие ссылки, sitemap).

**Решение: RU — primary root-locale** (чистые URL `/vpc/network/`), **EN — scaffold под `/en/`** с fallback на RU. Обоснование:

- Команда, ближайшие пользователи и весь обвес (vault, YouTrack, kacho-ui-строки) — русскоязычные; первичная launch-аудитория — внутренние и RU-говорящие разработчики/операторы. EN-first дал бы пустые EN-страницы как канон и RU как перевод — обратная реальному порядку авторинга нагрузка.
- `astro`/`starlight` `i18n` с `defaultLocale: 'root'` (RU как root, без префикса) + `locales: { root: { lang: 'ru' }, en: { lang: 'en' } }` оставляет EN-структуру готовой к промоуту в Phase 3 без переписывания RU-URL. Форма URL фиксируется `build.format:'directory'` + `trailingSlash:'always'` уже в MVP — переключение primary позже всё равно ломает URL, поэтому фиксируем сейчас осознанно.
- Если позже launch-стратегия станет EN-first для внешних developer-ов — это **отдельный осознанный re-IA-проект** (редирект-карта RU→EN), а не «дешёвая правка `defaultLocale`». Мы выбираем RU-first и принимаем это как границу.

---

## 2. Цели и не-цели

### Цели

- **Никогда не расходиться с API.** API-reference генерируется из `kacho-proto`, не пишется руками; CI падает при дрейфе (паттерн `git diff --exit-code`, который `kacho-proto` уже применяет для `permission_catalog.json`).
- **Public-RPC-only по построению.** Инфра-чувствительная поверхность отсекается на шаге генерации спеки фильтром против **канонического allowlist** (primary), плюс exclude-globs плагина (secondary), плюс CI-tripwire grep (defense-in-depth).
- **Тройная аудитория из одного корпуса.** Проза = AI-track; синхронизированные Tabs дают все варианты (Console/REST/Go/Python) в DOM/Markdown без скрытых веток.
- **Тема-паритет с kacho-ui** — механический маппинг токенов, dark по умолчанию + light, шрифт Inter, бренд KachoLogo.
- **Async Operations — first-class обучаемая концепция.** Каждая мутация возвращает Operation-envelope; доки учат submit → poll `OperationService.Get` до `done=true`, зеркаля семантику kacho-ui `useOperation`.
- **Reuse over rebuild.** Брать готовые OSS/hosted-блоки (starlight-openapi, Scalar, Prism, Hurl, GitMCP, Kapa) прежде, чем писать своё; самописные острова — только там, где инструмента нет (OperationRunner poll-loop, topology explorer).
- **Никакого тех-долга / TODO-на-потом.** Каждый отгруженный слой завершён. Out-of-scope помечается явной границей; недоделанный-но-отгруженный код запрещён. Падающий verified-example — красный билд, не skip.

### Не-цели (граница MVP — это boundary-разметка, не недоделка)

- **Не SPA**, не приложение с авторизацией — статический multi-page-сайт, публичный, без логина.
- **Не воспроизводим структуру методов YC 1-в-1** — документируем фактический Kachō-API (NIC — first-class и т.п.).
- **Не публикуем Internal.*/AddressPool/admin** в публичном reference — никогда, это постоянная граница, не бэклог.
- **Не версионируем доки в MVP** — публичный API path-versioned (`/v1/`); doc-versioning откладывается до появления v2 (это граница, а не долг).
- **Не строим Ask-AI RAG / topology explorer / semantic search в MVP** — Phase 3.
- **Try-it playground в MVP не ходит в реальные сервисы** — только Prism-mock без upstream.

---

## 3. Архитектура и выбор фреймворка

**Фреймворк — Astro Starlight** (`astro@^6`, `@astrojs/starlight@0.39.3`, `@astrojs/react` для React-19 островов, `@astrojs/mdx`). Обоснование:

- **Тема через CSS-custom-properties.** Starlight темится целиком через `--sl-color-*` / `--sl-font` без форка — kacho-ui уже использует `--kc-*` дизайн-систему, маппинг механический.
- **Та же стек-семья, что kacho-ui** — Vite + React 19 острова, MDX-контент.
- Встроенные dark/light, i18n, Pagefind-поиск (даёт ⌘K-палитру из коробки).
- Богатая экосистема плагинов: `starlight-openapi`, `starlight-llms-txt`, `@scalar/astro`.

**Тип сборки — статический multi-page** (`output: 'static'` по умолчанию, `build.format: 'directory'`, `trailingSlash: 'always'`). Astro эмитит по директории-с-`index.html` на маршрут.

### 3.1. Риск install-friction (Astro 6 peer-deps) и митигация

`@astrojs/react` / `@astrojs/mdx` в линейке Astro 6 имели (зафиксировано на июнь 2026) ERESOLVE peer-конфликт, когда интеграции пиннят `astro@^6.0.0-alpha.*` против стабильного `astro@6.x` (withastro/astro#15924). MVP коммитит React-19-острова (`OperationRunner` Phase 2, `TopologyExplorer` Phase 3) и `@astrojs/react`, поэтому риск называется явно.

**Митигация (требование scaffold-acceptance):** пиннить `@astrojs/react` / `@astrojs/mdx` к версиям, чей peer-range стабилизирован к `astro@^6.0.0` (либо `npm`-`overrides` в `package.json` форсят единый `astro`-резолв). **Acceptance-критерий scaffold:** `npm ci` в чистом CI-окружении резолвится без ERESOLVE и без `--legacy-peer-deps`; зелёный `npm ci` — обязательный гейт первого PR.

### 3.2. Поток деплоя

Зеркало kacho-ui: two-stage Dockerfile `node:22-alpine` (build) → `nginx:1.27-alpine` (runtime), `COPY dist → /usr/share/nginx/html`, EXPOSE 8080, `/healthz`. Helm-чарт скопирован из kacho-ui (`name=docs`, `ingress.host=docs.kacho.local`), подключён в umbrella-чарт `kacho-deploy`. Образ — `docker.io/prorobotech/kacho-docs:KAC-N-<sha>`.

**Критичное расхождение nginx с kacho-ui:** kacho-docs — статический multi-page, поэтому SPA-catch-all `try_files $uri $uri/ /index.html;` **неверен** (он маскирует реальные 404 и ломает per-page URL). Используем directory-index с `=404` + `error_page 404 /404.html`. Все `proxy_pass`-блоки kacho-ui (api-gateway, `/iam/v1`, Ory kratos/hydra) **удаляются** — docs-сайт не ходит ни к чему внутреннему (это и есть infra-sensitivity-граница).

```nginx
server {
  listen 8080; root /usr/share/nginx/html; index index.html;
  resolver ${KUBE_DNS_SERVER} valid=10s ipv6=off;   # parity с entrypoint, upstream-ов нет
  location = /healthz { access_log off; return 200 'ok'; add_header Content-Type text/plain; }
  location / { try_files $uri $uri/ $uri/index.html =404; }   # НЕ /index.html
  error_page 404 /404.html;
  gzip on; gzip_types text/plain text/css application/javascript application/json image/svg+xml; gzip_min_length 1024;
  location ~* \.(js|css|svg|png|woff2?)$ { expires 1y; add_header Cache-Control "public, immutable"; }
  # Cache-Control для HTML-страниц: directory-index URL (/vpc/network/) резолвится через
  # try_files в /vpc/network/index.html — regex по URI (~* /index\.html$) на canonical
  # URL НЕ матчится. Поэтому no-store для HTML скоупим map'ом по Content-Type, а не
  # location-regex'ом. (Корректность проверяется smoke-тестом, см. §9 guard #4.)
  map $sent_http_content_type $docs_cache_control {
    default                      "public, max-age=300";
    "~*text/html"                "no-store";
  }
  add_header Cache-Control $docs_cache_control always;
}
```

> **Cache-Control fix (ответ на критику §3/§9):** прежний `location ~* /index\.html$ { ... no-store }` не срабатывал для чистых directory-URL (`/vpc/network/`), т.к. regex матчит URI, а не разрешённый `try_files`-файл. Заменено на `map $sent_http_content_type` — `no-store` навешивается по фактическому `Content-Type: text/html` независимо от формы URL. **Acceptance-проверка (no-tech-debt):** `curl -I https://docs.kacho.local/vpc/network/` в preview-сборке обязан показать `Cache-Control: no-store` на HTML и `public, immutable` на `/_astro/*.js`. Без зелёного smoke nginx-слой не считается готовым.

---

## 4. Тема и бренд

**Источник истины токенов — `kacho-ui/src/index.css`** (`:root` / `:root[data-theme="light"]`) и зеркало `kacho-ui/src/lib/theme.ts`. Порт делается **в одном файле** `src/styles/kacho.css`, подключённом через `customCss: ['./src/styles/kacho.css']`. Без форка Starlight.

Конвенция тем совпадает 1-в-1: Starlight dark = `:root, ::backdrop`, light = `:root[data-theme='light']` — ровно `data-theme`-конвенция kacho-ui, поэтому переключатель структурно идентичен.

Точные токены (верифицированы в `index.css`):

| Назначение | DARK (`:root`) | LIGHT (`:root[data-theme='light']`) |
|---|---|---|
| `--kc-page` | `#0d0e12` | `#f6f7f9` |
| `--kc-container` | `#15161d` | `#ffffff` |
| `--kc-elevated` | `#1b1d25` | `#ffffff` |
| `--kc-border` | `#272a33` | `#e3e6ea` |
| `--kc-border-secondary` | `#1d1f27` | `#eef0f3` |
| `--kc-text` | `#e7e9ef` | `#14171c` |
| `--kc-text-secondary` | `#9aa0ac` | `#5a616e` |
| `--kc-text-tertiary` | `#6a7080` | `#8b929e` |
| `--kc-primary` | `#3d8df5` | `#3d8df5` |
| `--kc-brand-gradient` | `linear-gradient(135deg,#3d8df5 0%,#6e56cf 100%)` | то же |

Статус-тона (для P5-бейджей / verified-badge) берём из той же палитры: success `#2bb877`/`#4fd6a0`, warning `#e0a338`/`#e9bd6b`, error `#e5484d`/`#f0787c`, violet `#6e56cf`/`#a594ef`.

`src/styles/kacho.css` (несущий порт):

```css
@import '@fontsource-variable/inter';

:root, ::backdrop {                 /* DARK — дефолт Starlight */
  --sl-font: 'Inter Variable', ui-sans-serif, system-ui, sans-serif;
  /* токены kacho-ui verbatim — острова остаются token-идентичны kacho-ui */
  --kc-page:#0d0e12; --kc-container:#15161d; --kc-elevated:#1b1d25;
  --kc-border:#272a33; --kc-border-secondary:#1d1f27;
  --kc-text:#e7e9ef; --kc-text-secondary:#9aa0ac; --kc-text-tertiary:#6a7080;
  --kc-primary:#3d8df5; --kc-brand-gradient:linear-gradient(135deg,#3d8df5,#6e56cf);
  /* маппинг на Starlight */
  --sl-color-bg:var(--kc-page);
  --sl-color-bg-nav:var(--kc-container);
  --sl-color-bg-sidebar:var(--kc-page);
  --sl-color-text:var(--kc-text);
  --sl-color-white:var(--kc-text);
  --sl-color-gray-1:var(--kc-text-secondary);
  --sl-color-gray-2:var(--kc-text-secondary);
  --sl-color-hairline:var(--kc-border);
  --sl-color-hairline-shade:var(--kc-border-secondary);
  --sl-color-accent:var(--kc-primary);
  --sl-color-accent-high:#e7e9ef;
  --sl-color-text-accent:var(--kc-primary);
  --sl-color-green:#2bb877; --sl-color-orange:#e0a338; --sl-color-red:#e5484d;
}
:root[data-theme='light'] {         /* LIGHT — зеркало kacho-ui light */
  --kc-page:#f6f7f9; --kc-container:#fff; --kc-border:#e3e6ea;
  --kc-text:#14171c; --kc-text-secondary:#5a616e;
  --sl-color-bg:var(--kc-page);
  --sl-color-bg-nav:var(--kc-container);
  --sl-color-text:var(--kc-text);
  --sl-color-hairline:var(--kc-border);
  --sl-color-accent:var(--kc-primary);
}
```

**Бренд:** KachoLogo (градиент blue→violet) — через `logo: { light: './src/assets/kacho-light.svg', dark: './src/assets/kacho-dark.svg', replacesTitle: true }`, либо override `SiteTitle.astro` для градиентного рендера. **Inter** — self-hosted через `@fontsource-variable/inter` (без CDN, гигиена). Острова сохраняют имена `--kc-*` verbatim → визуально token-идентичны компонентам kacho-ui.

**Scalar-playground (Phase 2)** темится параллельным набором `--scalar-*`: `--scalar-background-1:#0d0e12; -2:#15161d; -3:#1b1d25; --scalar-border-color:#272a33; --scalar-color-1:#e7e9ef; --scalar-color-accent:#3d8df5` (light аналогично).

> Дрейф двух наборов токенов предотвращается тем, что порт **задокументирован** в шапке `kacho.css` (источник истины — `kacho-ui/src/index.css`). Общий пакет `@kacho/tokens` (CSS) устранил бы дублирование — это явная out-of-scope-граница, не MVP.

---

## 5. Семь столпов P1–P7

### P1 — Spec-driven интерактивный API-reference + Try-it playground

**Что:** sidebar-интегрированный reference из публично-отфильтрованного OpenAPI 3.1 + (Phase 2) «Try it»-клиент.

**Решение:** MVP — `starlight-openapi@0.25.3` рендерит спеки как нативные sidebar-страницы (наследует Layered-Calm через Starlight CSS-vars, read-only). Phase 2 — `@scalar/astro` (`@scalar/api-reference`) на выделенном маршруте `/api/playground/` как Try-it-клиент (реальный send-request + `proxyUrl`), темится через `--scalar-*`, указан **только** на Prism-mock / sandbox.

**Почему оба:** `starlight-openapi` интегрируется в sidebar и темится автоматически, но read-only. Scalar **не** встраивается в sidebar нативно (рендерит full-bleed), зато имеет настоящий клиент — поэтому он не может быть основной навигацией, но идеален как playground. Каждый по своей сильной стороне — без nav-шва и без live-call-инфры в MVP.

**Suffix-verb рендеринг (риск+гейт):** Kachō активно использует suffix-action-пути (`:verb`) — верифицировано: `:move`, `:relocate`, `:add-cidr-blocks`, `:remove-cidr-blocks`, `:setAccessBindings` (vpc/compute/iam), плюс публичный `OperationService:cancel`. starlight-openapi/Scalar должны рендерить каждую suffix-операцию как **отдельную operation** (а не схлопывать на base-path). Acceptance-snapshot-тест (см. §6.3) обязан проверить, что, например, `POST /vpc/v1/subnets/{id}:addCidrBlocks` присутствует как distinct operation в собранном reference.

**MVP:** starlight-openapi read-only. **Phase 2:** Scalar Try-it.
**Риски:** двойная theming-поверхность (две темы держать в Layered Calm); `oneof result{error|response}` + `google.protobuf.Any` + suffix-verbs могут рендериться криво — пин версии плагина + snapshot-тест JSON (incl. suffix-verb distinct-operation assert) + ручная Operation-концепт-страница.

### P2 — Dual-track концепции/how-to (Console vs REST/Go/Python)

**Что:** persona-переключатель Console ↔ API/SDK на каждой концепт-/how-to-странице.

**Решение:** встроенный Starlight `<Tabs syncKey="persona">` с TabItem `Console` / `REST` / `Go` / `Python`. Синхронизированные табы персистят выбор в `localStorage` между навигациями (стабильно с Starlight 0.26). **Никакого** кастомного persona-store, **никаких** условных MDX-веток.

**Почему:** синхронизированные Tabs рендерят **все** ветки в DOM/Markdown — AI/copy-as-md track получает каждый вариант бесплатно, нет SSR-hydration-flash. Условный MDX-store скрыл бы одну ветку из Markdown-корпуса и требовал бы hydrated-острова. Автор пишет прозу + один Tabs-блок, ноль JS.

**MVP.** **Риски:** соблазн условного MDX — запрещён регламентом авторинга (синхронизированные Tabs — единственный санкционированный паттерн).

### P3 — AI-native / agent-ready выдача

**Что:** `llms.txt`/`llms-full.txt`/`llms-small.txt`, per-page «copy as Markdown» / «open in Claude/ChatGPT», docs-as-MCP, Ask-AI.

**Решение:** MVP — `starlight-llms-txt@0.10.0` эмитит три файла; `src/pages/[...slug].md.ts` даёт каждой странице стабильный `.md`-URL; override `PageTitle` добавляет `[Copy as Markdown]` `[View as Markdown]` `[Open in ChatGPT]` `[Open in Claude]`. Phase 2 — регистрация публичного репо в **GitMCP** (`gitmcp.io/PRO-Robotech/kacho-docs`, zero-code, Apache-2.0). Phase 3 — hosted **Kapa.ai** (OSS-tier) или self-hosted **Inkeep** для Ask-AI RAG, grounded только на публичном корпусе.

**Почему:** highest-leverage-first — `llms.txt` + `.md`-маршрут почти бесплатны и являются source-корпусом для всего downstream. GitMCP бесплатен и ценен для этой Claude-Code-heavy команды. RAG отложен и стартует на free/OSS-tier. «Open in X»-ссылки — URL-строки с graceful degradation; `.md`-маршрут — робастный примитив.

**MVP:** llms.txt + copy-as-md. **Phase 2:** GitMCP. **Phase 3:** Ask-AI.
**Риски:** `starlight-llms-txt` — фактически single-maintainer (delucis); fallback — мы владеем `.md`-маршрутом + ручной concat `llms.txt`, плагин build-time-only и снимаемый, так что его поломка не блокирует деплой. `?q=`-deep-links на chatgpt.com/claude.ai — не стабильный API, но graceful (worst-case просто prefilled-prompt).

### P4 — First-class async Operations UX

**Что:** обучаемый submit→poll→done на каждой мутации.

**Решение:** MVP — статический `<OperationEnvelope>` (proto-точная форма полей: `id, description, created_at, modified_at, done, metadata Any, oneof result{error: google.rpc.Status | response}`) + легенда 3 состояний + каноническая концепт-страница «Работа с асинхронными Operations». Типы `metadata`/`response` per-RPC авто-инжектятся из опции `(kacho.cloud.api.operation){metadata,response}` (extension 87334, верифицировано в `proto/kacho/cloud/api/operation.proto`). Phase 2 — live-остров `<OperationRunner>`: запускает мутацию, извлекает `operation_id`, поллит `GET /operations/{id}` до `done`, переиспользуя паттерн kacho-ui `useOperation` (`refetchInterval: done ? false : 1000`).

**Почему:** ни один OpenAPI-инструмент не выражает submit→poll-loop, поэтому остров неизбежно самописный — держим крошечным и переиспользуем код kacho-ui. Опция `(kacho.cloud.api.operation)` машиночитаема, так что каждая мутация показывает ровно, какой Any несёт её Operation, без ручного авторинга.

**MVP:** статический. **Phase 2:** live auto-poll.
**Риски:** bespoke poll-loop = maintenance + должен зеркалить семантику kacho-ui — держим крошечным, покрываем одним e2e против mock; mock-done-flip должен совпадать с реальным backend (контракт-тест mock против бэкенда периодически).

### P5 — Live resource topology explorer

**Что:** интерактивный граф `Network → Subnet → NetworkInterface → Address` из **только публичных** полей, темится `--kc-*`-статус-тонами.

**Решение:** React-19 остров. **Отложен до Phase 3** — единственное место, где тяжёлый остров оправдан.

**Phase 3.**
**Риски:** infra-leak — должен быть строго ограничен публичными tenant-полями (никогда placement/SID/dataplane). Секвенирование последним держит MVP сфокусированным и не открывает infra-leak-поверхность до того, как public-filter-дисциплина обкатана.

### P6 — Verified, non-rotting examples

**Что:** примеры, которые не гниют.

**Решение:** MVP-слой 1 — `remark-code-import` встраивает line-range-блоки из реальных `examples/<lang>/*.go|.py|.sh`, которые компилируются/типизируются/линтятся в CI (markdown — view над тестируемым исходником). Phase 2-слой 2 — `.hurl`-сьюты прогоняют реальный create→poll→done против Prism-mock/sandbox в CI (`[Options] retry/retry-interval` + `[Asserts] jsonpath $.done == true`), эмитят JUnit, post-step штампует `verified.json` (SHA + UTC ts), читаемый `<VerifiedBadge>` («Verified · last checked DATE»). Падающий пример = красный билд — никаких skip/TODO.

**Почему:** два дополняющих слоя — сниппеты не гниют с первого дня (компилируемый исходник), Phase 2 доказывает, что документированные REST-потоки реально работают. Hurl retry-until-assert ложится 1-в-1 на poll-until-done — один `.hurl` и документирует, и верифицирует канонический async-поток.

**Источник curated example-payload'ов (см. §6.4):** Prism-mock возвращает Faker-random; для realism Try-it и для verified-fixtures нужны infra-safe курированные примеры. Они инжектятся НЕ ручной правкой сгенерированного OpenAPI (это поймал бы drift-гейт), а **post-gen overlay-шагом** — см. §6.4.

**MVP:** snippet-import. **Phase 2:** CI-executed.
**Риски:** line-range ломаются при правке исходника — предпочитать region-маркеры/whole-file над `#L3-L6`; «no skip»-правило vs flaky live-тесты — Hurl retry гасит transient, красным падает только реальный drift.

### P7 — Современный shell: поиск + палитра + бренд-тема

**Что:** ⌘K-палитра, поиск, dark/light + бренд.

**Решение:** MVP — встроенный Starlight **Pagefind** (`pagefind@1.5.x`) даёт ⌘K/CtrlK-палитру с нулём конфига — это И есть MVP-палитра. Dark+light через token-map, бренд KachoLogo, Inter через `@fontsource-variable/inter`. Phase 3 — слой **Orama** (или DocSearch) для hybrid keyword+semantic, делящий embeddings-корпус с Ask-AI.

**Почему:** Pagefind keyword-only, но даёт палитру бесплатно; semantic-апгрейд — config-swap, не rebuild. Тема-паритет — один CSS-файл. Версионирование отложено (`starlight-versions@0.9` экспериментален; API path-versioned `/v1/`, MVP не нужно).

**MVP:** Pagefind. **Phase 3:** semantic.
**Риски:** Pagefind keyword-only — ожидания на MVP: keyword ⌘K. `starlight-versions` НЕ брать в MVP (experimental, частые breaking changes).

---

## 6. Spec-driven API-reference: pipeline proto→OpenAPI

Четыре стадии, все в `kacho-proto`, чтобы у контракта был единый источник и CI drift-гейт.

### 6.1. Стадия 1 — генерация (proto → OpenAPI 3.1)

Добавить **отдельный** шаблон `buf.gen.openapi.yaml` (НЕ трогает существующий Go-stub `buf.gen.yaml`), запускающий `protoc-gen-connect-openapi` (sudorandom, `v0.25.6`) → OpenAPI 3.1, по одной спеке на домен (vpc/compute/iam/loadbalancer).

Выбран над grpc-gateway `protoc-gen-openapiv2`, потому что последний эмитит Swagger **2.0**, а connect-openapi — **3.1** (что лучше всего рендерят starlight-openapi/Scalar), уважает аннотации `google.api.http`, которые `kacho-proto` несёт на публичных RPC, и поддерживает services include/exclude-фильтр.

> **Editions-panic — N/A для этого кодобейза.** Прежняя ревизия числила `protoc-gen-openapiv2` known-panic с Protobuf Edition 2023 как live-риск и частично как обоснование выбора connect-openapi. **Верифицировано: все 136 `.proto` в `kacho-proto` — `syntax = "proto3"`, файлов Editions-2023 нет вообще.** Editions-panic здесь произойти не может; убран из рисков. Единственное и достаточное обоснование connect-openapi — **OpenAPI 3.1 output + нативный services include/exclude-фильтр + лучший рендер 3.1 в starlight-openapi/Scalar** (не editions).

```yaml
# kacho-proto/buf.gen.openapi.yaml — отдельный шаблон, Go-stub gen не трогается
version: v2
plugins:
  - remote: buf.build/community/sudorandom-connect-openapi:v0.25.6
    out: gen/openapi
    opt:
      - format=json
      - trim-unused-types=true
      - path-prefix=
```

### 6.2. Стадия 2 — public-surface фильтр + КАНОНИЗАЦИЯ ALLOWLIST (РЕШЕНО)

> **Это самый safety-critical механизм всего дизайна — он держит Internal*/AddressPool вне публичных доков. Раньше он висел как «открытый вопрос: какой путь?». Здесь — РЕШЕНО.**

**Решение (не «или»): allowlist переезжает в `kacho-proto` как единственный канонический источник, api-gateway его импортирует.** Рефактор api-gateway включён в этот EPIC как **обязательный subtask** (не follow-up).

**Почему именно relocate, а не vendor-with-drift-check:**
- Проект **запрещает split-brain** (workspace CLAUDE.md). Vendored-копия — это два места, которые могут разойтись; drift-check лишь *обнаруживает* расхождение постфактум, а канонизация его *исключает по построению*. Для механизма, чья поломка = infra-leak публичной поверхности, исключение > обнаружение.
- Механически дёшево и чисто (верифицировано):
  - `kacho-proto` — модуль `github.com/PRO-Robotech/kacho-proto`, не зависит ни от чего внутри проекта (центр build-графа), поэтому пакет allowlist в нём ничего не зациклит.
  - Сейчас allowlist — `package allowlist` в `kacho-api-gateway/internal/allowlist/list.go`: плоский `var AllowedMethods map[string]struct{}` (ключ — gRPC-FQN-путь `/kacho.cloud.<domain>.v1.<Service>/<Method>`) + `func HasInternalSuffix(methodPath string) bool`. Импортёры внутри api-gateway — `internal/proxy/server.go`, `internal/proxy/director.go` (+ `list_test.go`).
  - Переезд: переместить `list.go`/`list_test.go` в `kacho-proto` (напр. `gen/go/.../apisurface` или новый `pkg/apisurface`), api-gateway меняет import-путь на `github.com/PRO-Robotech/kacho-proto/.../apisurface`. `replace ../kacho-proto` в `kacho-api-gateway/go.mod` уже есть — build-граф не меняется.

**Что делает фильтр.** `~80-LOC` Go-программа `cmd/openapi-filter` (в `kacho-proto`) загружает канонический `apisurface.AllowedMethods` + `apisurface.HasInternalSuffix` и **выбрасывает каждую операцию**, чей gRPC-FQN отсутствует в allowlist ИЛИ Internal-suffixed. Это авто-исключает все `Internal*Service` и admin AddressPool-поверхность, сохраняя **публичный** AddressService.

> **Фильтр — это allowlist, НЕ наличие `google.api.http`.** Верифицированные факты (на момент ревизии):
> - **62** `*_service.proto`; **50** из них несут `google.api.http`.
> - **Критично: 6 `Internal*`-протоколов ВСЁ РАВНО несут `google.api.http`** — `internal_cloud_service`, `internal_address_pool_service` (vpc), `internal_iam_service`, `internal_user_service`, `internal_cluster_service` (iam), `internal_catalog_service` (compute). (Остальные Internal — `internal_network/address/watch/resource_lifecycle` vpc, `internal_authorize/iam_hooks` iam, `internal_resource_lifecycle/watch` compute/lb, `internal_authz_cache` apigateway — http НЕ несут.)
> - **Вывод: наличие `google.api.http` — НЕ безопасный дискриминатор public/internal.** Наивная генерация «из всех proto с http-аннотацией» **утекла бы** AddressPool-admin + Internal cloud/iam/user/cluster/catalog-поверхность (placement-смежные RPC) в публичные доки. **Allowlist-фильтр обязателен** — это главный infra-leak-гард.

(Прежняя ревизия писала «все 51 `*_service.proto`, включая Internal [все]» — это было фактически неверно по двум пунктам: число — 62/50, и http несут НЕ все Internal, а 6. Направленный вывод — «фильтр обязан быть allowlist-based, не http-presence-based» — от этого только усиливается.)

### 6.3. Стадия 3 — commit + drift-гейт + filter-correctness-тест

Записать `gen/openapi/<domain>.openapi.json`; Makefile-таргеты `generate-openapi` + `verify-openapi` (`git diff --exit-code gen/openapi/`), вплетённые в CI рядом с существующим buf-generate-гейтом.

**Test-first для net-new кода (требование §12/§13 strict TDD — этот EPIC сам пишет код, значит сам подпадает):**

1. **`cmd/openapi-filter` unit-тест (Go, RED→GREEN).** RED: тест с фикстурой-OpenAPI, содержащей `InternalAddressPoolService.*` и `InternalCloudService.*` операции, ожидает, что после фильтра их НЕТ, а `AddressService.Get/List` — ЕСТЬ; прогоняется ДО написания фильтра, падает (фильтра нет). GREEN: фильтр написан, тест зелёный. Это прямой тест «фильтр роняет Internal/AddressPool, сохраняет public».
2. **CI infra-leak tripwire — fixture-тест (RED→GREEN).** RED: фикстура `dist`-фрагмента с запретным токеном (`AddressPool`) — grep-tripwire (§9) обязан **упасть**; подтверждаем, что упал. GREEN: на чистом `dist` tripwire проходит. Tripwire без доказательства, что он ловит подброшенный токен, — не считается рабочим.
3. **starlight-openapi snapshot-тест.** Зафиксировать, что собранный reference содержит ожидаемый набор операций (включая suffix-verbs как distinct operations — `:addCidrBlocks`, `:move`, `:relocate`, `:setAccessBindings`) и НЕ содержит ни одной Internal/AddressPool-операции.
4. **drift-гейт** `git diff --exit-code gen/openapi/` — отдельно от (1)-(3): ловит ручную правку сгенерированного JSON.

**Allowlist↔OpenAPI diff-snapshot — именованный acceptance-артефакт (ответ на «missing» #3).** CI генерирует и коммитит `gen/openapi/_surface-snapshot.json` — отсортированный список `{operationId, method, path, grpcFqn}` всех операций, переживших фильтр. Acceptance-ревьюер сверяет его с `apisurface.AllowedMethods` 1-в-1: каждая survived-операция ∈ allowlist, ни одна Internal-suffix не survived. Это даёт ревьюеру конкретный enumerated mapping (а не утверждение «8 публичных VPC ресурсов»). Конкретно для VPC ожидается survival: `NetworkService` (Get/List/Create/Update/Delete/ListSubnets/ListSecurityGroups/ListRouteTables/ListOperations/Move), `SubnetService` (+AddCidrBlocks/RemoveCidrBlocks/Relocate/ListUsedAddresses), `AddressService` (Get/GetByValue/List/ListBySubnet/Create/Update/Delete/Move/ListOperations), `RouteTableService`, `SecurityGroupService` (+UpdateRules/UpdateRule), `GatewayService`, `PrivateEndpointService`, `NetworkInterfaceService` — и НЕ survival: `InternalAddressService`, `InternalAddressPoolService`, `InternalNetworkService`, `InternalCloudService`, `InternalWatchService`, `InternalResourceLifecycleService`.

**Обогащение Operation:** опция `(kacho.cloud.api.operation){metadata,response}` (extension 87334, читается из FileDescriptorSet) инжектит `x-operation` per-мутация, чтобы доки рендерили конкретные `metadata`/`response` Any-типы и callout «returns Operation, poll until done».

`kacho-docs` потребляет закоммиченный JSON read-only на build-time (полирепо COPY/fetch-паттерн). `@scalar/cli validate` гейтит валидность спеки.

### 6.4. Curated infra-safe example-payloads (ответ на «missing» #5)

connect-openapi НЕ авторит response-examples; Prism вернёт Faker-random (нереалистичные CIDR/ID). Ручная правка сгенерированного `gen/openapi/*.json` запрещена (drift-гейт её поймает, и это была бы правка generated-output). Решение — **отдельный committed overlay-файл + post-gen merge-шаг**, не правка generated:

- `kacho-proto/openapi-overlays/<domain>.examples.yaml` — рукописный, version-controlled, содержит **только** `examples`/`example` для request/response-схем (infra-safe значения: `enp...`-id, RFC-1918-CIDR, и т.п.). Каждый пример проходит тот же §9-tripwire grep (запретные токены недопустимы в overlay).
- Makefile-шаг `generate-openapi` после connect-openapi применяет overlay (OpenAPI Overlay-спека, `redocly`/`openapi-overlay` CLI) → результат — это и есть commit-аемый `gen/openapi/<domain>.openapi.json`. Так curated-examples становятся частью «сгенерированного» артефакта **детерминированно** (overlay входит в pipeline), drift-гейт сравнивает финальный merge-результат — ручной правки нет, examples управляются из overlay-источника.
- Эти же curated-examples кормят Prism (Phase 2 P1 Try-it realism) и служат fixtures для Hurl verified-suites (P6 слой 2). Один источник примеров для обоих.

> Без этого механизма P1 Try-it показывал бы Faker-мусор, а P6-fixtures были бы рукописны в отрыве от спеки. Overlay-в-pipeline закрывает оба, не нарушая «не править generated».

```js
// kacho-docs/astro.config.mjs (фрагмент P1)
import starlightOpenAPI, { openAPISidebarGroups } from 'starlight-openapi';
starlight({
  plugins: [ starlightOpenAPI([
    { base: 'api/vpc',     schema: './openapi/vpc.openapi.json',     label: 'VPC API' },
    { base: 'api/compute', schema: './openapi/compute.openapi.json', label: 'Compute API' },
    { base: 'api/iam',     schema: './openapi/iam.openapi.json',     label: 'IAM API' },
  ]) ],
  sidebar: [ /* concepts… */ { label: 'API Reference', items: openAPISidebarGroups } ],
});
```

---

## 7. Модель контента для тройной аудитории + persona-switch

**Структура страницы:** концепт-страница документирует ресурс **один раз прозой** (обслуживает end-user + AI-читателя как plain Markdown), затем **один** синхронизированный Tabs-блок показывает ту же задачу в Console-кликах vs REST-curl vs Go vs Python.

```mdx
import { Tabs, TabItem } from '@astrojs/starlight/components';

<Tabs syncKey="persona">
  <TabItem label="Console">Откройте раздел Сети → Создать сеть…</TabItem>
  <TabItem label="REST">```bash
POST /vpc/v1/networks  { "name": "prod-net" }
```</TabItem>
  <TabItem label="Go">```go file=../../../examples/go/create_network.go
```</TabItem>
  <TabItem label="Python">```python file=../../../examples/python/create_network.py
```</TabItem>
</Tabs>
```

**AI-track не требует условного рендера** — это сырой Markdown страницы (P3 copy-as-md / llms.txt читают MDX как есть). Синхронизированные Tabs рендерят все ветки в DOM/Markdown → все три аудитории из одного источника.

**Авторинг DX:** расширить `docsSchema({ extend })` в `src/content.config.ts` полями Kachō:

```ts
// src/content.config.ts
import { defineCollection, z } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({ extend: z.object({
      persona: z.enum(['user','developer','both']).default('both'),
      apiService: z.string().optional(),     // 'NetworkService' → deep-link концепт↔reference
      kachoResource: z.string().optional(),  // id_prefix, напр. 'enp'
    }) }),
  }),
};
```

Компонент `<ApiRefLink service={frontmatter.apiService}/>` резолвит маршрут `starlight-openapi` (`/api/vpc/networkservice/`) — концепт линкуется на сгенерированный reference без хардкода URL.

---

## 8. Информационная архитектура + VPC-раздел

**Sidebar:** гибрид — explicit `sidebar: []` для top-level порядка/лейблов (Обзор, Быстрый старт — курируемый порядок), `autogenerate: { directory }` внутри `concepts/<domain>` и `how-to` (автор кидает `.mdx` → авто-появляется по `sidebar.order`), и `openAPISidebarGroups` для API-reference. RU root-locale (чистые URL `/vpc/network/`, см. §1.1), EN-scaffold под `/en/`.

### 8.1. Asymmetry «full generated reference vs stub concepts» для Compute/IAM — РЕШЕНО

> **Ответ на «missing» #4.** P1 рендерит `compute.openapi.json` и `iam.openapi.json` **полностью** (это автогенерация — отфильтровать домен из reference было бы искусственно), тогда как concept-проза по Compute/IAM в MVP — stub. Нужно явно решить asymmetry.

**Решение: asymmetry ПРИНИМАЕТСЯ осознанно, с явной разметкой.**
- **API Reference** (P1) на launch включает **VPC + Compute + IAM + LoadBalancer полностью** — это сгенерированная, drift-защищённая, public-отфильтрованная поверхность. Отрезать Compute/IAM из reference в MVP не имеет смысла: генерация уже даёт их корректно и безопасно, а developer-аудитория выигрывает от полного reference сразу.
- **Concept-проза** в MVP — **VPC полностью** (8 ресурсов, §8.2), **IAM и Compute — stub** (короткая вводная + ссылка на их сгенерированный reference). Stub-страница **явно** маркируется callout'ом «Концептуальная документация этого домена в разработке; полный API-reference доступен в разделе API Reference» — это **boundary-разметка (not-in-MVP-depth)**, НЕ недоделанный код и НЕ TODO. Прозу по Compute/IAM добавляют пост-MVP инкрементально (каждая страница — завершённый PR), без изменения reference.
- Это не нарушает no-tech-debt: stub-concept — явная граница глубины контента (как «Релизы — реверс-хрон stub»), а reference для этих доменов — полнофункциональный и завершённый. Альтернатива (скоупить reference до VPC-only под глубину концептов) **отвергнута** — она бы прятала готовую безопасную поверхность.

Полное дерево sidebar:

```
1. Обзор (index.mdx)            — что такое Kachō, control-plane-модель,
                                   flat-resources + async Operations, project/account-scoping
2. Быстрый старт (quickstart)   — «Первая сеть за 5 минут»: Network→Subnet→Address (Console+API tabs)
3. Концепции
   ├─ IAM:     Account, Project, ServiceAccount, AccessBinding (STUB+reference-link в MVP)
   ├─ VPC:     Network, Subnet, SecurityGroup, RouteTable, Gateway,
   │           Address, NetworkInterface, PrivateEndpoint (8 публичных, полностью)
   │           └─ Admin: AddressPool (помечен internal, НЕ в публичном reference)
   └─ Compute: Instance, Disk, Image (STUB+reference-link в MVP)
4. Инструкции (how-to)          — «Зарезервировать static IP», «Подключить NIC»,
                                   «Открыть порты через SG», «Egress через Gateway»
5. API Reference (autogenerate) — starlight-openapi, по сервисам, PUBLIC RPC only
                                   (VPC+Compute+IAM+LB полностью — §8.1)
6. Работа с API (api-guide)     — аутентификация, Operation-polling (P4), error-model
                                   {code,message,details}, пагинация page_token, UpdateMask
7. AI и агенты (ai.mdx)         — llms.txt, copy-as-md, open-in-Claude/ChatGPT, docs-MCP
8. Релизы (changelog)           — реверс-хронологический stub
```

### 8.2. VPC-раздел в деталях

Публичная tenant-поверхность VPC = **8 first-class ресурсов**. Концепт-страница = tenant-поля/lifecycle/limits **БЕЗ инфры**; API/SDK-track = сервис + ключевые RPC + Operation-примеры. **AddressPool — admin/internal-only, ИСКЛЮЧён** из публичных концептов и сгенерированного reference (его `InternalAddressPoolService` не в allowlist → дропается фильтром §6.2). Каждая мутация по всем 8 возвращает `operation.Operation`; клиент поллит `OperationService.Get` (`GET /operations/{id}`) до `done=true`, либо per-resource ListOperations (`GET /vpc/v1/networks/{id}/operations`) для истории.

1. **Network** (id-prefix `enp`) — name (unique per project), description, labels; единственный `ACTIVE`-state; delete-precondition `"network is not empty"`. NetworkService: Get/List/ListSubnets/ListSecurityGroups/ListRouteTables sync; Create/Update/Delete/Move async→Operation. **EXCLUDE** `vpn_id` / kube-ovn-underlay.
2. **Subnet** — `network_id`, `zone_id`, v4/v6 CIDR (primary + extra-блоки, можно v6-only), `route_table_id`-ассоциация; no-overlap-in-network. SubnetService (+AddCidrBlocks/RemoveCidrBlocks/Relocate/ListUsedAddresses). **EXCLUDE** underlay.
3. **SecurityGroup** — `network_id` (required+immutable), `rules[{direction,ports,protocol,cidr|sg_id}]`, `default_for_network`; SG→SG-правило валидно только в той же сети. SecurityGroupService (UpdateRules/UpdateRule с OCC → FailedPrecondition на конфликт).
4. **RouteTable** — `network_id`, `static_routes[{destination_prefix,next_hop|gateway_id}]`, авто-ассоциация подсетей. RouteTableService.
5. **Gateway** — type `SHARED_EGRESS_GATEWAY`, `shared_egress_gateway`-конфиг; in-use delete-precondition. GatewayService.
6. **Address** — external/internal v4/v6, `reserved`-флаг, `is_ephemeral`, `used_by`-hint; delete заблокирован, пока `used_by` set. AddressService (+GetByValue, ListBySubnet). **EXCLUDE** pool-internals (выбор пула автоматический/прозрачный для tenant).
7. **NetworkInterface** — **ДОКУМЕНТИРОВАТЬ KACHO-DIVERGENCE:** first-class ресурс (НЕ inline-in-instance как в YC). `subnet_id`, `network_id` (derived), `security_group_ids[]`, `primary_v4/v6_address`, `used_by_id` (DETACHED↔ATTACHED через atomic CAS). NetworkInterfaceService. **EXCLUDE ВСЕ** data-plane-поля (`hv_id/sid/sid_seq/host_iface/netns/gateway_ip/container_id`).
8. **PrivateEndpoint** — `subnet_id`, `address_id`, `service_kind` (object-storage/container-registry/…), `PROVISIONING→ACTIVE`. PrivateEndpointService (proto под `vpc/v1/privatelink/`).

**ADMIN/INTERNAL ONLY (НЕ публично):** AddressPool (id `apl`) — InternalAddressPoolService на internal-listener; в доках максимум фраза «выбор пула автоматический». Идёт в раздел Admin / опускается, никогда в публичный reference.

---

## 9. Гарды infra-sensitivity

Многослойное enforcement public-only / no-infra-leak:

1. **PRIMARY** — OpenAPI фильтруется против **канонического allowlist (переехавшего в `kacho-proto`, §6.2)** на этапе генерации, так что Internal*Service, AddressPool-admin, internal-проекции Region/Zone/Hypervisor никогда не достигают docs-страницы, llms.txt, MCP-индекса или playground. Корректность фильтра доказывается unit-тестом (§6.3, RED→GREEN) + allowlist↔OpenAPI diff-snapshot-артефактом.
2. **SECONDARY** — `starlight-llms-txt` exclude-globs (`internal/**`, `admin/**`) + scoping proto-входа.
3. **TRIPWIRE** — CI-grep по собранному `dist` + `llms-full.txt` падает, если появляется любой запретный токен: `vpn_id, sid, sid_seq, hv_id, hypervisor, node_index, netns, host_iface, underlay, kube-ovn, gateway_ip` (169.254), `container_id, kh-, AddressPool, Internal`. Tripwire сам покрыт fixture-тестом (§6.3 п.2): подброшенный запретный токен обязан ронять CI.
4. **NGINX** — статический сайт: directory-index (`try_files $uri $uri/ $uri/index.html =404; error_page 404 /404.html`), НЕ SPA-fallback kacho-ui (он бы маскировал 404 и ломал per-page URL); ВСЕ `proxy_pass`-блоки kacho-ui (api-gateway, `/iam/v1`, Ory) **выброшены** — docs-сайт не говорит ни с чем внутренним. Cache-Control HTML-страниц — через `map $sent_http_content_type` (§3.2), smoke-проверяется `curl -I` на чистом directory-URL перед «готово».
5. **PLAYGROUND** — MVP использует Prism-mock БЕЗ upstream (структурно не может достичь внутренних сервисов); Phase 2 sandbox-proxy фронтит **только** PUBLIC-mux api-gateway, hard-pinned base-URL, никогда listener 9091, никогда prod-токен, с существующим `x-kacho-principal-*` header-stripping шлюза как backstop + rate-limit + auto-reaper.
6. **CONTENT** — концепт-страницы курируются вручную из tenant-полей ТОЛЬКО; vault-VPC-заметки содержат инфра-историю (kube-ovn-underlay, removed `vpn_id`, NIC data-plane-поля `hv_id/sid/sid_seq/host_iface/netns/gateway_ip/container_id`), которую НЕЛЬЗЯ копировать — per-page public-fields-only review перед публикацией. Vault подтверждает: AddressPool — `visibility:internal` (id-prefix `apl`, все RPC на internal-listener) → Admin-раздел / опущен, никогда в публичный reference.

```bash
# CI tripwire (фрагмент ci.yaml) — defense-in-depth поверх primary-фильтра.
# Покрыт fixture-тестом (§6.3 п.2): подброшенный 'AddressPool' обязан ронять этот шаг.
FORBIDDEN='vpn_id|sid_seq|sid|hv_id|hypervisor|node_index|netns|host_iface|underlay|kube-ovn|169\.254|container_id|kh-|AddressPool|Internal'
if grep -rEn "$FORBIDDEN" dist/ dist/llms-full.txt 2>/dev/null; then
  echo "INFRA-LEAK: forbidden token in built output"; exit 1
fi
```

---

## 10. Структура репо + сборка + деплой + CI

```
kacho-docs/                       # SIBLING-полирепо: git@github.com:PRO-Robotech/kacho-docs,
                                  # клонируется в project/ (gitignored); НЕ Go-сервис
├─ astro.config.mjs              # starlight + react + mdx + starlightOpenAPI + starlightLlmsTxt;
│                                #   site:'https://docs.kacho.local', trailingSlash:'always',
│                                #   build.format:'directory', i18n defaultLocale root=ru, en-scaffold
├─ package.json                  # scripts: dev/build/preview/check/lint; overrides пиннят astro peer (§3.1)
├─ tsconfig.json
├─ src/
│  ├─ content.config.ts          # docsSchema({extend: persona/apiService/kachoResource})
│  ├─ content/docs/              # MDX, RU root-locale (чистые URL /vpc/network/)
│  │  ├─ index.mdx  quickstart.mdx
│  │  ├─ concepts/{iam,vpc,compute}/*.mdx   # vpc полный; iam/compute stub+reference-link (§8.1)
│  │  ├─ how-to/*.mdx
│  │  ├─ api-guide/*.mdx          # auth, Operation-polling, error-model, pagination, UpdateMask
│  │  ├─ ai.mdx  changelog/*.mdx
│  │  └─ en/                      # EN-scaffold (fallback на RU)
│  ├─ styles/kacho.css            # --kc-* verbatim + map на --sl-* (dark+light); Inter
│  ├─ components/                 # OperationEnvelope.astro (MVP), OperationRunner.tsx (P2),
│  │                              #   PageTitleWithAiActions.astro, VerifiedBadge.astro,
│  │                              #   ApiRefLink.astro, TopologyExplorer.tsx (P3)
│  ├─ pages/[...slug].md.ts       # per-page .md endpoint (copy-as-md / llms / GitMCP-source)
│  └─ assets/kacho-{light,dark}.svg
├─ openapi/                       # потребляет kacho-proto gen/openapi/*.json на build
│                                 #   (без Go/buf-тулчейна в docs-CI)
├─ examples/{go,python,sh}/       # реальный CI-компилируемый исходник для remark-code-import
├─ tests/api/*.hurl               # Phase 2 verified-example-сьюты
├─ public/                        # favicon, Inter woff2 (self-hosted)
├─ Dockerfile  .dockerignore  Makefile
├─ deploy/{Chart.yaml,values.yaml,default.conf.template,
│          05-resolver-from-resolvconf.sh,templates/{deployment,service,ingress,hpa}.yaml}
└─ .github/workflows/{ci.yaml,docker-build.yaml}
```

**Зеркала для копирования verbatim:** `project/kacho-ui/Dockerfile`, `project/kacho-ui/deploy/*` (чарт + entrypoint), `project/kacho-ui/.github/workflows/{ci.yaml,docker-build.yaml}`, `project/kacho-ui/Makefile`.

**`kacho-proto`-сторона (в этом EPIC, обязательные subtasks):**
- переезд `package allowlist` (`AllowedMethods` + `HasInternalSuffix`) из api-gateway в `kacho-proto` как канонический `apisurface`-пакет (§6.2) — **+ subtask в `kacho-api-gateway`: переключить импорт, прогнать существующие `allowlist`/`director` тесты зелёными** (доказать, что переезд не сломал маршрутизацию);
- `buf.gen.openapi.yaml` + `cmd/openapi-filter` (+ его RED→GREEN unit-тест, §6.3) + `openapi-overlays/<domain>.examples.yaml` (§6.4) + `gen/openapi/*.json` + `gen/openapi/_surface-snapshot.json`;
- Makefile `generate-openapi` (connect-openapi → overlay-merge → filter) + `verify-openapi` (`git diff --exit-code gen/openapi/`) в CI.

**`kacho-deploy` получает** `build-docs`-таргет + umbrella docs-sub-chart + `docs.kacho.local`-ingress.

```dockerfile
# kacho-docs/Dockerfile — two-stage, зеркало kacho-ui
# syntax=docker/dockerfile:1.6
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build            # astro build -> ./dist (статика, /_astro, 404.html, pagefind/, llms*.txt)
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY deploy/default.conf.template /etc/nginx/templates/default.conf.template
COPY deploy/05-resolver-from-resolvconf.sh /docker-entrypoint.d/05-resolver-from-resolvconf.sh
RUN chmod +x /docker-entrypoint.d/05-resolver-from-resolvconf.sh
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
```

**CI** (`.github/workflows/ci.yaml`): `setup-node@v4` (node 22, cache npm) → `npm ci` (**зелёный без `--legacy-peer-deps`, §3.1**) → `npm run check` (astro check, type+content) → `@scalar/cli validate openapi/*.json` → `npm run build` → CI-tripwire grep (§9, fixture-tested) → `lychee`-link-check над `dist/`. **docker-build.yaml** (копия kacho-ui): multi-arch amd64/arm64 + manifest → `docker.io/prorobotech/kacho-docs:KAC-N-<sha>` (по MEMORY-feedback — docker.io/prorobotech, НЕ ttl.sh).

**Dev-стенд (`kacho-deploy`, 3 правки):** (1) `Makefile` — `build-docs` (docker build `../kacho-docs` + kind load), вызывается из `dev-up` после `build-ui`, whitelist `docs` в `reload-svc`; (2) umbrella `Chart.yaml` — `- name: docs … repository: file://../../../kacho-docs/deploy`; (3) `values.dev.yaml` — `docs.image=kacho-docs:dev`, `ingress.host=docs.kacho.local` (+`127.0.0.1 docs.kacho.local` в `/etc/hosts`). `deploy/values.yaml`: `name: docs, port: 8080`, HPA min1/max3, requests cpu 25m/mem 32Mi (статика, легче UI).

**Порядок merge (топосортировка графа):** `kacho-proto` (allowlist-переезд + OpenAPI-gen + фильтр + overlay) → `kacho-api-gateway` (переключение импорта allowlist, зелёные тесты) → `kacho-docs` (новый репо) → `kacho-deploy` (wiring) → `kacho-workspace` (docs/vault). Пока вышестоящее не в `main` — нижестоящий CI пиннит siblings к feature-веткам (`ref:`-строки).

---

## 11. Фазовая дорожная карта

> **Gate-напоминание:** ни один пункт MVP-чек-листа не стартует до APPROVED acceptance-документа + заведённого EPIC (см. статус-врезку вверху и §12). Чек-лист ниже — содержимое будущего acceptance-DoD, не разрешение начинать сейчас.

### MVP (read-only + дисциплина anti-rot)

- [ ] **`kacho-proto`:** переезд `apisurface` (allowlist+HasInternalSuffix) из api-gateway → kacho-proto как канонический источник; `cmd/openapi-filter` + его **RED→GREEN unit-тест** (роняет Internal/AddressPool, сохраняет public AddressService); `buf.gen.openapi.yaml` (`protoc-gen-connect-openapi@v0.25.6` → OpenAPI 3.1); `openapi-overlays/*.examples.yaml` (curated infra-safe examples); commit `gen/openapi/<domain>.openapi.json` + `_surface-snapshot.json`; `generate-openapi`+`verify-openapi` в Makefile+CI.
- [ ] **`kacho-api-gateway`:** переключить импорт allowlist на `kacho-proto/apisurface`; существующие `allowlist`/`director`/`server` тесты зелёные (доказать, что маршрутизация не сломана).
- [ ] Scaffold `kacho-docs` sibling-репо (Astro 6 + `@astrojs/starlight@0.39.3` + `@astrojs/react` + `@astrojs/mdx`), **`npm ci` зелёный без `--legacy-peer-deps`** (§3.1 overrides-пин), git-remote `git@github.com:PRO-Robotech/kacho-docs`, клон в `project/` (gitignored), i18n RU-root + EN-scaffold (§1.1).
- [ ] `src/styles/kacho.css`: import `@fontsource-variable/inter`, `--sl-font`, `--kc-*` verbatim из kacho-ui (обе темы), map `--kc-*`→`--sl-*` dark+light. Бренд KachoLogo.
- [ ] P1 read-only: `starlight-openapi` рендерит vpc/compute/iam/loadbalancer public-спеки в sidebar (`openAPISidebarGroups`); **snapshot-тест: suffix-verbs (`:addCidrBlocks/:move/:relocate/:setAccessBindings`) — distinct operations; 0 Internal/AddressPool операций.**
- [ ] IA: Обзор, Быстрый старт, Концепции (IAM-stub+reference-link + 8 публичных VPC полностью + Compute-stub+reference-link, §8.1), How-to (3–4 core VPC), API Reference (generated, VPC+Compute+IAM+LB), Работа с API (auth, Operation-polling, error-model, pagination, UpdateMask), AI и агенты, Релизы-stub.
- [ ] P2: `<Tabs syncKey="persona">` Console/REST/Go/Python на Quickstart, how-to и каждой VPC-концепции; frontmatter-schema расширена; `<ApiRefLink>` deep-link концепт→reference.
- [ ] P3 MVP: `starlight-llms-txt` (llms.txt/full/small + exclude-globs), `src/pages/[...slug].md.ts`, `PageTitle`-override с Copy/View-md/Open-in-ChatGPT/Open-in-Claude; страница «Используйте доки с вашим AI-агентом».
- [ ] P4 MVP: статический `<OperationEnvelope>` + каноническая async-Operations-концепция; типы `metadata`/`response` per-RPC из опции `(kacho.cloud.api.operation)`.
- [ ] P6 слой 1: `remark-code-import` + `examples/` компилируются/линтятся в CI.
- [ ] P7 MVP: Pagefind ⌘K-палитра + dark/light + бренд; `@scalar/cli validate`-гейт.
- [ ] Деплой: two-stage Dockerfile, статический nginx (directory-index, БЕЗ SPA-fallback, БЕЗ proxy_pass, Cache-Control через `map`-Content-Type **со smoke `curl -I`**), Helm-чарт зеркало kacho-ui (`name=docs`, `host=docs.kacho.local`), `kacho-deploy` `build-docs` + umbrella; образ `docker.io/prorobotech/kacho-docs:KAC-N-<sha>`.
- [ ] CI-tripwire: grep `llms-full.txt` + `dist` на запретные токены, **покрыт fixture-тестом (подброшенный токен роняет CI)**; `lychee`-link-check.

### Phase 2 (Try-it + verified-execution)

- [ ] P1 Try-it: `@scalar/astro` на `/api/playground/`, тема `--scalar-*`→`--kc-*`, `proxyUrl`/server-URL hard-pinned на Prism-mock затем sandbox.
- [ ] Prism-mock-контейнер (`docker.io/prorobotech/kacho-docs-mock:KAC-N-<sha>`, `mock -d` на public-спеке + curated overlay-examples §6.4 → реалистичные ответы, не Faker; same-origin → без CORS).
- [ ] **Sandbox-проект lifecycle (демотировано из open-question):** opt-in «Run against sandbox» — крошечный Go reverse-proxy (`docker.io/prorobotech/kacho-docs-sandbox-proxy:…`) перед PUBLIC REST-mux api-gateway, инжектит short-lived low-priv Bearer одного ephemeral sandbox-проекта, опирается на `x-kacho-principal-*` stripping шлюза, CORS + rate-limit + auto-reaper. **Развилка решается в Phase-2-acceptance** (зависит от того, поддержит ли `kacho-iam` ephemeral-проекты + минтинг short-lived Bearer, ИЛИ пул pre-provisioned sandbox-проектов с reaper) — это Phase-2-scoping-деталь, не MVP-блокер.
- [ ] P4 live: `<OperationRunner>`-остров mock→sandbox; RUNNING→DONE/ERROR с resolved-ресурсом или `google.rpc.Status`.
- [ ] P6 слой 2: Hurl `.hurl`-сьюты create→poll→done против mock/sandbox в CI (fixtures из overlay-examples §6.4), JUnit, `verified.json`-штамп, `<VerifiedBadge>`.
- [ ] P2-расширение: SDK-сниппет-табы на runnable-примеры для всех 8 VPC + Compute; curated `x-codeSamples` для marquee-потоков.
- [ ] P3 MCP: регистрация GitMCP над публичным репо; one-line client-config.

### Phase 3 (RAG + topology + semantic + версии)

- [ ] **P3 Ask-AI RAG** (hosted Kapa.ai OSS-tier или self-hosted Inkeep), grounded только на публичном `llms-full`-корпусе, source-cited, отдельный sub-chart (НЕ в статическом nginx-образе). **Data-residency-развилка** (hosted Kapa приемлем т.к. корпус публичен, ИЛИ self-hosted Inkeep для контроля) решается в Phase-3-acceptance — не MVP/Phase-2-блокер.
- [ ] P5 live topology explorer (`Network→Subnet→NIC→Address` из публичных полей).
- [ ] P7 hybrid keyword+semantic (Orama или DocSearch), делящий embeddings-корпус с Ask-AI.
- [ ] Doc-versioning, когда появится v2-поверхность (branch-based или `starlight-versions` после стабилизации; directory-build-формат уже фиксирует форму URL). Триггер — появление v2-API на roadmap; до тех пор API path-versioned `/v1/` и doc-versioning не нужен.
- [ ] Полный EN-перевод (промоут `/en/`-scaffold в first-class). При смене launch-стратегии на EN-first — отдельный re-IA-проект с редирект-картой RU→EN (§1.1), не «дешёвая правка `defaultLocale`».
- [ ] Опц. тонкий кастомный Streamable-HTTP MCP (blueprint `withastro/docs-mcp`) только если generic-search GitMCP недостаточен для OpenAPI/Operation-семантики.
- [ ] `doc-detective` для верификации console click-through how-to.
- [ ] Published typed SDK (Speakeasy: Go/TS/Python) в `kacho-sdk-*`-репо; идиоматичные примеры заменяют generic-сниппеты через `x-codeSamples`.

---

## 12. Acceptance-гейт, тикетинг и риски

### 12.1. Контролирующее предусловие (gate #1) — НЕ open question, а блокер

Это ≥3-репо кросс-репо-фича (`kacho-docs` новый + `kacho-proto` OpenAPI-gen/allowlist-переезд + `kacho-api-gateway` import-switch + `kacho-deploy` wiring) → **обязателен YouTrack-EPIC с subtasks + APPROVED Given-When-Then acceptance-документ ДО любого scaffold/кода** (workspace CLAUDE.md §«Запреты» #1). Последовательность, которая должна произойти ПОСЛЕ этого design-документа и ДО первого коммита:

1. `acceptance-author` пишет `docs/specs/sub-phase-X.Y-kacho-docs-acceptance.md` (GWT-вехи: что именно тестируем — public-filter роняет Internal/AddressPool, suffix-verbs distinct, theme-паритет, tripwire ловит токен, nginx no-store на HTML, `npm ci` чистый, allowlist-переезд не сломал router).
2. `acceptance-reviewer` ставит **APPROVED** (НЕ заказчик — он проверяет только финальный smoke).
3. EPIC заведён в `KAC` + subtasks в порядке графа (§10 merge-order), все в текущий спринт, роли-исполнители/ревьюеры проставлены, vault-trail `KAC/KAC-<N>.md` создан.

Только после (2) начинается scaffold. До этого момента весь §11 — содержимое DoD, не разрешение кодить.

### 12.2. Test-first для net-new кода этого EPIC (§12/§13 strict TDD)

Этот EPIC сам пишет код (Go-фильтр, CI-tripwire, allowlist-переезд) → подпадает под strict TDD. Обязательные RED→GREEN пары в соответствующих PR (детали §6.3):
- `cmd/openapi-filter` unit-тест: RED (фикстура с Internal/AddressPool-операциями ожидает их отсутствие после фильтра — падает без фильтра) → GREEN.
- CI infra-leak tripwire fixture-тест: RED (фрагмент с `AddressPool` обязан ронять grep — подтверждаем, что роняет) → GREEN (чистый `dist` проходит).
- api-gateway allowlist-переезд: существующие `allowlist`/`director` тесты остаются зелёными после смены import-пути (regression-guard, не новый код).
- starlight-openapi snapshot + allowlist↔OpenAPI diff-snapshot — acceptance-артефакты.

### 12.3. Риски (откалибровано под верифицированные факты)

- **INFRA-LEAK (наивысший):** `google.api.http` есть на public И на **6 Internal** proto (`internal_cloud/address_pool` vpc, `internal_iam/user/cluster` iam, `internal_catalog` compute) — наличие http НЕ дискриминирует public/internal; наивная генерация утекла бы Internal/AddressPool/placement-смежные RPC в публичные доки. Митигация: фильтр против **канонического allowlist в `kacho-proto`** (§6.2, split-brain исключён переездом, не drift-check'ом), plugin-excludes, CI-token-tripwire (fixture-tested), allowlist↔OpenAPI diff-snapshot — независимые гарды + доказательство корректности.
- **Fidelity OpenAPI-3.1-эмиттера (suffix-verbs + Operation-envelope):** JSON connect-openapi для `oneof result{error|response}` + `google.protobuf.Any` + verified suffix-verbs (`:move`, `:relocate`, `:add-cidr-blocks`, `:remove-cidr-blocks`, `:setAccessBindings`; публичный `OperationService:cancel`) может рендериться криво или схлопывать suffix-операции на base-path. Митигация: пин плагина, snapshot-тест JSON **с assert «suffix-verb = distinct operation»**, ручная Operation-концепт-страница. (`:cancel` — это публичный `OperationService.Cancel`, не leak; перечислен как rendering-, не security-риск.)
- **SPA-fallback foot-gun + HTML cache-control:** копирование nginx kacho-ui в статический multi-page молча маскирует 404 и (старый `~* /index\.html$`) не навешивает no-store на directory-URL. Митигация: directory-index + `=404` + `error_page`; Cache-Control через `map $sent_http_content_type` (§3.2); **smoke `curl -I` на чистом `/vpc/network/` — обязательный гейт «nginx готов»** (no-tech-debt).
- **Astro-6 peer-deps install-friction (§3.1):** `@astrojs/react`/`@astrojs/mdx` ERESOLVE против stable astro 6. Митигация: `overrides`-пин в `package.json`, **чистый `npm ci` без `--legacy-peer-deps` — scaffold-acceptance-критерий**.
- **Maturity/single-maintainer:** `starlight-llms-txt` (delucis), `starlight-openapi`/`starlight-versions` (HiDeoo) — в основном single-maintainer. Митигация: владеем `.md`-маршрутом как fallback для llms.txt; пин версий; llms-txt build-time-only и снимаемый — поломка плагина не блокирует деплой. НЕ брать `starlight-versions` в MVP (experimental v0.9, частые breaking).
- **Curated-examples drift (§6.4):** Prism иначе вернёт Faker-random. Митигация: overlay-в-pipeline (`openapi-overlays/*.examples.yaml` мёржится ДО commit'а generated JSON), не ручная правка generated; overlay-значения проходят тот же tripwire-grep.
- **Playground на реальные сервисы:** любой Try-it с дефолтным server-URL `api.kacho.local`/internal даёт публичным visitor'ам тыкать в control-plane. Митигация: MVP-mock без upstream (структурно недостижимо); Phase 2 sandbox-URL hard-pinned, никогда listener 9091, env-gated.
- **Async UX bespoke** (OperationRunner poll-loop — ни один инструмент так не делает). Митигация: крошечный, reuse `useOperation`, один e2e против mock; mock-done-flip контракт-тестится против бэкенда.
- **Pagefind keyword-only** — semantic/hybrid (P7-stretch) НЕ встроен; ожидания MVP: keyword ⌘K; swap на Orama/DocSearch — Phase 3.
- **Два render-инструмента** (starlight-openapi + Scalar) = две theming-поверхности под Layered Calm. Приемлемо; MVP отгружает только starlight-openapi, Scalar отложен.
- **GitMCP отдаёт всё публичное в репо** — draft/internal-страница, закоммиченная в kacho-docs, всплывёт. Митигация: держать docs-репо public-clean; граница = «что закоммичено публично».

> **Editions-panic (`protoc-gen-openapiv2`) — УБРАН из рисков как N/A:** все 136 proto — `syntax = "proto3"`, Editions-2023 в `kacho-proto` нет; panic невозможен. Обоснование connect-openapi — OpenAPI 3.1 + include/exclude-фильтр + лучший 3.1-рендер, не editions.

### 12.4. Оставшиеся развилки (демотированы из MVP-блокеров; решаются в acceptance соответствующей фазы)

- **Sandbox-проект lifecycle** (Phase 2): ephemeral-проекты `kacho-iam` vs пул pre-provisioned + reaper — решается Phase-2-acceptance, влияет только на scope Phase 2.
- **Ask-AI data-residency** (Phase 3): hosted Kapa vs self-hosted Inkeep — Phase-3-acceptance.
- **Кастомная ⌘K kacho-ui:** если у kacho-ui появится своя ⌘K сверх поиска — зеркалить островом (Phase 2/3); если нет — Pagefind-палитры достаточно бессрочно. Не блокирует MVP.
- **Версионирование-триггер:** подтверждено отсутствие близкого v2-API → doc-versioning остаётся Phase 3; форма URL уже зафиксирована directory-build + trailingSlash.
