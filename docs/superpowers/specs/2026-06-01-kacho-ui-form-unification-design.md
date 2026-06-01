# kacho-ui — унификация Create/Edit форм + UX-уплифт под инфраструктурный UI

**Дата:** 2026-06-01
**Репо:** `kacho-ui` (затрагивает все VPC-формы; generic-движок → бонусом compute/IAM/NLB)
**Тип:** refactor + UX (presentational-слой, без изменения бизнес-логики/мутаций)
**Связано:** эпик `KAC-239` (VPC UI redesign). Тикет — завести как subtask KAC-239.
**Статус:** DRAFT (ожидает ревью пользователя перед writing-plans)

---

## 1. Проблема

Пользователь: «стиль edit и create разный; нужно унифицировать + привести к best-practices
ux/ui инфраструктурных интерфейсов». Аудит подтвердил — расхождение реально и системно:

### 1.1 Две параллельные презентации формы
- **Modal** (`InlineResourceCreateForm` / `InlineResourceEditForm`) — следует нормативному
  `CLAUDE.md §4`: `<Form horizontal labelCol=200px colon=false>`, заголовок `level=4` +
  `ResourceIcon`, per-field `Form.Item` с info-tooltip и required-⭐, фильтрация
  hidden/visibleWhen/locked, футер `DopplerButton`.
- **Full-page** (`ResourceCreatePage` / `ResourceEditPage`) — **НЕ** следует §4: нет `<Form>`-обёртки
  (голый `<Card>`+`<Space>`), заголовок `level=3` без иконки, другой текст («Создать x» vs
  «Создание: X»), нет горизонтального label-layout, нет фильтрации полей, иной механизм immutable
  (`{...f, immutable}` + `editMode` вместо filter-out).

Оба рендерят один и тот же `FormFieldRenderer` и одинаковый submit/Operation-flow — но через
**два разных шелла** → create/edit и modal/page выглядят по-разному.

### 1.2 §3 contract vs реальность роутинга
`CLAUDE.md §3/§15` нормативно требуют «все Create/Edit — модалки, никаких `/create`,`/<id>/edit`
routes». Но `App.tsx` всё ещё роутит full-page формы: VPC-fallback `/vpc/<route>/create`
(Network/Address/RT/SG/Gateway/PE → `ResourceCreatePage`; Subnet → `SubnetCreatePage`),
Compute `/compute/<route>/create`, NLB `/nlb/<route>/create`, System
`/system/{regions,zones,address-pools}/{create,:uid/edit}`, project edit `/projects/:id/edit`.
→ контракт и код разошлись.

### 1.3 Дивергенция кастомных форм (Subnet/SG/NIC/AddressPool)
- **Pending-кнопка**: NIC использует AntD `Button loading` (спиннер); остальные — `DopplerButton pulsing`.
- **Field-help (info-tooltip)**: 3 реализации (generic-pattern / NIC локальный `labelWithInfo` / Subnet
  inline `<Space><Tooltip>`) + **AddressPool без тултипов вовсе**.
- **Immutable-поля**: Subnet Edit показывает read-only + `LockOutlined`; остальные молча `disabled`
  (нет affordance/причины).
- **CIDR-редактор**: Subnet Edit — RPC-driven `SubnetCidrManager`; AddressPool Edit — controlled
  `SubnetCidrChips` (разный UX для «одного и того же»).
- **SecurityGroup** — нет кастомного Create (fallback на generic, может светить edit-only поля).

### 1.4 Мёртвый/дублирующий код
- `src/components/ui/{button,dialog,input,tabs}.tsx` (Radix/shadcn-слой) — **0 импортов** → мёртв.
- Tailwind HSL-токены (`--background`/`--foreground`/…) — **используются** (110+ мест) и осознанно
  зеркалят AntD-токены (`--background: #1c1d22 ← colorBgBase`). Это **good single-source bridge** для
  не-AntD кастом-компонентов → **сохранить**, не трогать.

---

## 2. Цели / Не-цели

**Цели**
1. **Create/Edit паритет**: одинаковый порядок полей, компоненты, лейблы, layout. Edit отличается
   только заголовком (verb), префиллом и пометкой immutable-полей.
2. **Modal/Page паритет**: обе презентации рендерят **один** `ResourceFormBody` → выглядят идентично.
3. Привести 4 кастомные формы к §4-контракту через общие примитивы (убрать 3 реализации тултипов,
   разнобой кнопок, immutable-affordance, CIDR).
4. UX-уплифт под инфраструктурные best-practices (см. §4), оставаясь в YC-style/AntD.
5. Удалить мёртвый Radix `components/ui/*`; синхронизировать `CLAUDE.md §3/§15` с реальностью.

**Не-цели (YAGNI)**
- Не менять цвета/тему/AntD-`ConfigProvider` токены (палитра §4.6 остаётся).
- Не трогать бизнес-логику мутаций/`update_mask`/Operation-polling/`sanitize`/`hydrate`.
- Не делать schema-движок «всё в один движок» (подход C) — это отдельный возможный follow-up.
- Не переписывать compute/IAM/NLB-специфичные экраны (InstanceDetailPage и т.п.) — они улучшаются
  бонусом через generic-`ResourceFormBody`, но кастом-логика не трогается.

---

## 3. Дизайн — общие примитивы

Новый каталог `src/components/form/` пополняется примитивами, кодирующими §4 + best-practices.
Изоляция: каждый примитив — одна ответственность, тестируемый, потребляется и modal-, и page-шеллом.

### 3.1 `ResourceFormBody` (ядро)
Единственный источник рендера формы ресурса. Инкапсулирует то, что сейчас дублируется в
`InlineResourceCreateForm`/`InlineResourceEditForm`/`ResourceCreatePage`/`ResourceEditPage`.

```
ResourceFormBody({
  spec, mode: "create" | "edit",
  obj, onChange,                       // controlled state (владелец — шелл)
  lockedPaths,                          // immutable/preset paths
  fieldOptionsFilter?, sections?,       // §4.5 фильтры + §4 секции
  submitting, onSubmit, onCancel,
  submitLabel?, presetNotice?,          // page показывает preset-Alert, modal — нет (опц.)
})
```
- Заголовок: `FormShell` (см. 3.2) — `level=4` + `ResourceIcon` + «Создание/Редактирование: {singular}».
- `<Form layout="horizontal" labelCol={{flex:"200px"}} colon={false} size="middle">` (§4.2).
- Поля: фильтрация hidden/visibleWhen/locked (§4.5) → `Form.Item` через `FieldLabel` (3.4); immutable
  на Edit → `ImmutableField` (3.6); full-width типы (sg-rules/array/custom) — как сейчас.
- Футер: `FormFooter` (3.5).
- **Шеллы становятся тонкими**: modal-шелл и page-шелл только владеют state + submit/Operation-flow
  (он остаётся как есть, §12.3 контракта) и рендерят `<ResourceFormBody>`.

### 3.2 `FormShell` — заголовок + контейнер тела
Иконка + verb-заголовок (`level=4`) + опц. подзаголовок; обёртка тела с едиными отступами.
Убирает расхождение title level/wording/icon между modal и page.

### 3.3 `FormSection` — группа полей
`<FormSection title="Сеть" collapsible? defaultOpen?>` — заголовок секции + тонкий divider.
Best-practice: группировать поля (Идентичность → Конфигурация → Сеть → Расширенное). Секции
декларируются в `ResourceSpec` (опц. `sectionsOf(fields)` или поле `field.section`); при отсутствии
— одна неявная секция (обратная совместимость; ничего не ломается).

### 3.4 `FieldLabel` — единый label
`<FieldLabel text required info?>` = label + required-⭐ справа + `QuestionCircleOutlined` tooltip
если есть `info`. Заменяет 3 реализации `labelWithInfo` (generic/NIC/Subnet) одной. Запрет
скобочных пояснений в label (§4.4) — централизуется здесь.

### 3.5 `FormFooter` — единый футер действий
`DopplerButton type=primary pulsing` (primary) + `Button` Cancel; единая раскладка/порядок;
защита от double-submit (`disabled` на pending). NIC переходит с `loading`-спиннера на этот футер.
Sticky-вариант (`position:sticky; bottom:0`) когда форма выше N — чтобы действия всегда видны
(инфра-формы бывают длинные). Текст: единый «Создать/Сохранить {singular}».

### 3.6 `ImmutableField` — affordance неизменяемости
На Edit immutable-поле = read-only значение (моноширинный для id/CIDR/IP) + `LockOutlined` +
tooltip «Неизменяемо после создания». Заменяет молчаливый `disabled`. Best-practice инфра-UI:
пользователь видит **почему** поле нельзя править. Унифицирует Subnet-стиль на все ресурсы.

### 3.7 Единый CIDR-редактор
`SubnetCidrChips` (controlled, Create) и `SubnetCidrManager` (RPC-driven, Edit) уже визуально
идентичны (§9). Сводим к одному `CidrEditor` с режимом `controlled | rpc`; AddressPool Edit
переходит на тот же компонент (сейчас рассинхрон). Визуал не меняется — убирается дублирование.

---

## 4. Инфраструктурные UX best-practices (зашиваются в примитивы)

1. **Create/Edit паритет** (ядро) — одинаковая форма; Edit = префилл + immutable-locks + verb.
2. **Группировка в секции** с заголовками; «Расширенное/optional» — collapsible, свёрнуто по
   умолчанию (снижение когнитивной нагрузки в плотных инфра-формах).
3. **Immutable affordance** — 🔒 + причина (3.6), не молчаливый disabled.
4. **Inline-help, не стены текста** — per-field tooltip + плейсхолдеры/примеры (CIDR `10.0.0.0/24`,
   паттерн имени). Длинные/RFC-пояснения — в info, не в label (§4.4).
5. **Валидация** — inline-ошибки полей + form-level summary для не-полевых ошибок; ввод не теряется
   при ошибке submit (уже §3.5 — сохраняем).
6. **Единый pending/LRO-feedback** — `DopplerButton pulsing`, защита от double-submit, отражение
   Operation-polling (контракт §12.3 не трогаем).
7. **Единый футер** — primary + Cancel, sticky при высокой форме.
8. **Клавиатура/фокус** — autofocus первого поля, Enter=submit, Esc=cancel (modal уже maskClosable);
   `:focus-visible`-кольца.
9. **Плотность/скан** — YC dark dense; выровненный label-col 200px; моноширинный для id/CIDR/IP.

---

## 5. План по поверхностям (что меняется)

| Поверхность | Действие |
|---|---|
| `InlineResourceCreateForm` / `InlineResourceEditForm` | Свести к тонкому шеллу над `ResourceFormBody` (state + submit/op-flow остаются). |
| `ResourceCreatePage` / `ResourceEditPage` | Рефактор: рендерят `<ResourceFormBody mode>` вместо bare `<Card>`. → page == modal. |
| `InlineSubnetCreate/EditForm` | Перейти на `FieldLabel`/`FormFooter`/`FormSection`; CIDR → `CidrEditor`. |
| `InlineSecurityGroupEditForm` + **новый** `InlineSecurityGroupCreateForm` | Кастом Create (только metadata; rules — edit-only); общие примитивы. |
| `InlineNetworkInterfaceCreate/EditForm` | `Button loading` → `FormFooter`(DopplerButton); локальный `labelWithInfo` → `FieldLabel`. |
| `InlineAddressPoolCreate/EditForm` | Добавить info-tooltips (`FieldLabel`); Edit CIDR → `CidrEditor` (rpc). |
| `src/components/ui/{button,dialog,input,tabs}.tsx` | **Удалить** (0 импортов). |
| `CLAUDE.md §3/§15` (kacho-ui) | Синхронизировать с реальностью (см. §6). |

> **Резерв сужения scope**: если объём великоват для одного PR — режем по доменам/ресурсам, но
> примитивы (§3) идут первым PR, затем форма-за-формой переезжает на них. Никаких TODO-стабов
> (workspace §11): каждый PR доводит затронутые формы до конца.

---

## 6. Решение — page vs modal: **вариант B** (принято 2026-06-01)

§3 говорил «modal-only», App.tsx держит page-routes → противоречие снимаем так:
- **VPC** — modal-first (как §3). Generic VPC page-routes (`/vpc/<route>/create` → `ResourceCreatePage`)
  проверить на достижимость; если из UI на них никто не навигирует (list «Создать» открывает `?modal=`)
  — **удалить** как unreachable. `SubnetCreatePage` — отдельно (используется; перевести на
  `ResourceFormBody` либо в модалку — решить в плане).
- **Compute / NLB / System / project-edit** — **оставить full-page** (там уместно), но рендерить
  **тот же** `ResourceFormBody` → визуальный паритет без рискованной миграции в модалки.
- **Обновить §3/§15 (kacho-ui CLAUDE.md)**: «VPC — modal; для не-VPC допускается page, но **обязан**
  рендерить `ResourceFormBody`». Убирает doc-vs-code противоречие.

> Не-цель (явно): НЕ мигрировать compute/NLB/system create/edit в модалки — паритет достигается
> общим `ResourceFormBody`, а не сменой презентации.

---

## 7. Токены / дизайн-система
- AntD `ConfigProvider` (App.tsx) + CSS-vars (index.css) остаются **источником истины палитры**
  (они синхронны, §4.6). Не меняем.
- Tailwind HSL-токены — оставить (используются не-AntD компонентами).
- Удалить только мёртвый Radix `components/ui/*`. Решение «возвращать ли shadcn-слой» — **нет**
  (YAGNI; формы на AntD, контракт §15.5).

---

## 8. Тестирование
- `npx tsc --noEmit` — zero ошибок (строгий gate).
- **Playwright e2e** (`e2e/`): для каждого затронутого ресурса — Create открывает форму с §4-layout
  (label-col, title-icon, footer), Edit префиллит + immutable-поля показывают 🔒/read-only, submit →
  Operation-flow → success-toast + invalidate. Modal и page рендерят идентичный body (snapshot/role-
  assertions). RED→GREEN где есть текущее расхождение (workspace test-first §12).
- Визуальная проверка на стенде (port-forward UI) для 2-3 ресурсов на каждую категорию (generic /
  custom / page).

---

## 9. Риски
- **Блок-радиус**: `ResourceFormBody` потребляется generic-движком → задевает и compute/IAM/NLB.
  Митигируется паритетом (тот же FormFieldRenderer внутри) + tsc + e2e + поэтапным переездом.
- **Кастом-логика** (Subnet CIDR RPC, NIC ref-resolution, SG split-endpoint) — НЕ трогаем поведение,
  только presentational-обёртку. Регресс ловится e2e.
- **§6 решение** влияет на размер: вариант B (рекомендуемый) минимизирует риск.

---

## 10. Definition of Done
- [ ] Примитивы §3 реализованы + unit-покрыты.
- [ ] generic modal + page рендерят `ResourceFormBody`; create==edit==modal==page визуально.
- [ ] 4 кастом-формы (+новый SG Create) на общих примитивах; дивергенции §1.3 устранены.
- [ ] Мёртвый `components/ui/*` удалён; `CLAUDE.md §3/§15` синхронизирован.
- [ ] tsc clean; playwright e2e зелёные (RED→GREEN показан); смоук на стенде.
- [ ] vault: `KAC/KAC-<N>.md` + затронутые `packages/` записи обновлены; PR-ссылки.
