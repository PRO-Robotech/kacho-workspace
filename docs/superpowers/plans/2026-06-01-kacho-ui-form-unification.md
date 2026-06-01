# kacho-ui Form Unification — Implementation Plan (Plan 1: Foundation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a single shared `ResourceFormBody` (+ form primitives) rendered by BOTH the modal and full-page shells, so generic Create/Edit forms look identical (`create==edit==modal==page`), and remove dead Radix UI code.

**Architecture:** Extract the §4-contract form (title+icon, AntD `<Form horizontal labelCol=200px>`, per-field `Form.Item`, footer) currently duplicated across `InlineResourceCreateForm`/`InlineResourceEditForm`/`ResourceCreatePage`/`ResourceEditPage` into composable primitives in `src/components/form/`. Shells keep their data lifecycle (template/hydrate, mutation, Operation-polling) and become thin wrappers that render `<ResourceFormBody>`. Locked/immutable fields render via a new `ImmutableField` affordance (read-only + 🔒 + reason) instead of being hidden (modal) or silently disabled (page).

**Tech Stack:** React 18 + TypeScript, AntD 5, Tailwind (thin), Vitest + @testing-library/react (unit), Playwright (e2e). Commands: `npm test` (vitest run), `npm run typecheck` (tsc -b --noEmit), `npm run e2e`.

**Scope:** Plan 1 = foundation + generic forms + cleanup. Custom forms (Subnet/SG/NIC/AddressPool) + `CidrEditor` = **Plan 2** (separate; written after this lands). Design: `docs/superpowers/specs/2026-06-01-kacho-ui-form-unification-design.md`. Ticket: **KAC-241** (subtask of KAC-239). Branch: `KAC-241` in `kacho-ui`.

**Working dir for all paths:** `project/kacho-ui/` (run all `npm` commands there).

---

## File Structure

**Create (new primitives, `src/components/form/`):**
- `FieldLabel.tsx` — label text + optional info-tooltip (asterisk stays ConfigProvider's job). + `FieldLabel.test.tsx`
- `FormFooter.tsx` — primary `DopplerButton` + Cancel, pending/double-submit guard, sticky-on-tall. + `FormFooter.test.tsx`
- `ImmutableField.tsx` — read-only value (mono) + 🔒 + reason tooltip. + `ImmutableField.test.tsx`
- `FormShell.tsx` — title (`level=4` + `ResourceIcon`) + body container. + `FormShell.test.tsx`
- `FormSection.tsx` — titled group + divider, optional collapsible. + `FormSection.test.tsx`
- `ResourceFormBody.tsx` — the core; consumes all above + `FormFieldRenderer`. + `ResourceFormBody.test.tsx`

**Modify (shells → thin wrappers over `ResourceFormBody`):**
- `src/components/InlineResourceCreateForm.tsx`
- `src/components/InlineResourceEditForm.tsx`
- `src/components/ResourceCreatePage.tsx`
- `src/components/ResourceEditPage.tsx`

**Delete (dead, 0 imports):**
- `src/components/ui/button.tsx`, `dialog.tsx`, `input.tsx`, `tabs.tsx`

**Docs:** `project/kacho-ui/CLAUDE.md` §3/§15 sync; vault `obsidian/kacho/KAC/KAC-241.md` + `packages/`.

**Branch setup (do once before Task 1):**
```bash
cd project/kacho-ui && git checkout -b KAC-241
```

---

## Task 1: FieldLabel primitive

**Files:**
- Create: `src/components/form/FieldLabel.tsx`
- Test: `src/components/form/FieldLabel.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/FieldLabel.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { FieldLabel } from "./FieldLabel";

describe("FieldLabel", () => {
  it("renders plain text when no info", () => {
    render(<FieldLabel text="Имя" />);
    expect(screen.getByText("Имя")).toBeInTheDocument();
    expect(screen.queryByLabelText("field-info")).toBeNull();
  });

  it("renders an info trigger when info is provided", () => {
    render(<FieldLabel text="Сеть" info="Сеть, к которой принадлежит подсеть" />);
    expect(screen.getByText("Сеть")).toBeInTheDocument();
    expect(screen.getByLabelText("field-info")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/FieldLabel.test.tsx`
Expected: FAIL — `Failed to resolve import "./FieldLabel"`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/FieldLabel.tsx
// FieldLabel — единый label для Form.Item: текст + опц. info-tooltip справа.
// Звёздочку required рисует ConfigProvider.requiredMark (App.tsx §4.3), НЕ здесь.
// Заменяет 3 разрозненные реализации labelWithInfo (generic/NIC/Subnet).
import { Space, Tooltip } from "antd";
import { QuestionCircleOutlined } from "@ant-design/icons";

interface Props {
  text: React.ReactNode;
  /** Длинные/RFC/optional пояснения — сюда, НЕ в скобки label (CLAUDE.md §4.4). */
  info?: React.ReactNode;
}

export function FieldLabel({ text, info }: Props) {
  if (!info) return <>{text}</>;
  return (
    <Space size={4}>
      {text}
      <Tooltip title={info}>
        <QuestionCircleOutlined
          aria-label="field-info"
          style={{ color: "rgba(255,255,255,0.45)" }}
        />
      </Tooltip>
    </Space>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/FieldLabel.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/form/FieldLabel.tsx src/components/form/FieldLabel.test.tsx
git commit -m "feat(KAC-241): FieldLabel form primitive (label + info-tooltip)"
```

---

## Task 2: FormFooter primitive

**Files:**
- Create: `src/components/form/FormFooter.tsx`
- Test: `src/components/form/FormFooter.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/FormFooter.test.tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi } from "vitest";
import { FormFooter } from "./FormFooter";

describe("FormFooter", () => {
  it("calls onSubmit on primary click", async () => {
    const onSubmit = vi.fn();
    render(<FormFooter submitLabel="Создать сеть" submitting={false} onSubmit={onSubmit} onCancel={() => {}} />);
    await userEvent.click(screen.getByRole("button", { name: "Создать сеть" }));
    expect(onSubmit).toHaveBeenCalledOnce();
  });

  it("disables both actions while submitting", () => {
    render(<FormFooter submitLabel="Создать сеть" submitting onSubmit={() => {}} onCancel={() => {}} />);
    expect(screen.getByRole("button", { name: "Отменить" })).toBeDisabled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/FormFooter.test.tsx`
Expected: FAIL — cannot resolve `./FormFooter`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/FormFooter.tsx
// FormFooter — единый футер Create/Edit форм: primary DopplerButton + Cancel.
// pending → pulsing + защита от double-submit. sticky=true делает футер липким
// (для длинных форм — действия всегда видны).
import { Button, Space } from "antd";
import { DopplerButton } from "@/components/DopplerButton";

interface Props {
  submitLabel: string;
  submitting: boolean;
  onSubmit: () => void;
  onCancel: () => void;
  sticky?: boolean;
}

export function FormFooter({ submitLabel, submitting, onSubmit, onCancel, sticky }: Props) {
  return (
    <div
      style={
        sticky
          ? {
              position: "sticky",
              bottom: 0,
              background: "var(--card, #26272d)",
              paddingTop: 12,
              marginTop: 4,
              borderTop: "1px solid var(--border, #383941)",
              zIndex: 1,
            }
          : undefined
      }
    >
      <Space>
        <DopplerButton type="primary" onClick={onSubmit} pulsing={submitting}>
          {submitLabel}
        </DopplerButton>
        <Button onClick={onCancel} disabled={submitting}>
          Отменить
        </Button>
      </Space>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/FormFooter.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/form/FormFooter.tsx src/components/form/FormFooter.test.tsx
git commit -m "feat(KAC-241): FormFooter primitive (DopplerButton + cancel, pending guard)"
```

---

## Task 3: ImmutableField primitive

**Files:**
- Create: `src/components/form/ImmutableField.tsx`
- Test: `src/components/form/ImmutableField.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/ImmutableField.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { ImmutableField } from "./ImmutableField";

describe("ImmutableField", () => {
  it("shows the value read-only with a lock affordance", () => {
    render(<ImmutableField value="enp1a2b3c4d5e6f7g8h" reason="Неизменяемо после создания" />);
    expect(screen.getByText("enp1a2b3c4d5e6f7g8h")).toBeInTheDocument();
    expect(screen.getByLabelText("immutable-lock")).toBeInTheDocument();
  });

  it("renders an em-dash placeholder for empty value", () => {
    render(<ImmutableField value="" reason="x" />);
    expect(screen.getByText("—")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/ImmutableField.test.tsx`
Expected: FAIL — cannot resolve `./ImmutableField`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/ImmutableField.tsx
// ImmutableField — read-only отображение неизменяемого/preset-поля с affordance:
// 🔒 + tooltip-причина. Инфра-UX best-practice: пользователь видит ПОЧЕМУ поле
// нельзя править (вместо молчаливого disabled-инпута). Для scalar/ref-полей.
import { Space, Tooltip, Typography } from "antd";
import { LockOutlined } from "@ant-design/icons";

interface Props {
  value: React.ReactNode;
  /** Причина: "Неизменяемо после создания" (edit) / "Задано из контекста" (create). */
  reason: string;
}

export function ImmutableField({ value, reason }: Props) {
  const empty = value === "" || value === null || value === undefined;
  return (
    <Space size={6} align="center">
      <Typography.Text style={{ fontFamily: "monospace" }} type={empty ? "secondary" : undefined}>
        {empty ? "—" : value}
      </Typography.Text>
      <Tooltip title={reason}>
        <LockOutlined aria-label="immutable-lock" style={{ color: "rgba(255,255,255,0.45)" }} />
      </Tooltip>
    </Space>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/ImmutableField.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/form/ImmutableField.tsx src/components/form/ImmutableField.test.tsx
git commit -m "feat(KAC-241): ImmutableField primitive (read-only + lock + reason)"
```

---

## Task 4: FormShell primitive

**Files:**
- Create: `src/components/form/FormShell.tsx`
- Test: `src/components/form/FormShell.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/FormShell.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { FormShell } from "./FormShell";

describe("FormShell", () => {
  it("renders verb title + singular and children", () => {
    render(
      <FormShell specId="subnets" mode="create" singular="Подсеть">
        <div>body</div>
      </FormShell>,
    );
    expect(screen.getByText(/Создание: Подсеть/)).toBeInTheDocument();
    expect(screen.getByText("body")).toBeInTheDocument();
  });

  it("uses the edit verb in edit mode", () => {
    render(
      <FormShell specId="subnets" mode="edit" singular="Подсеть">
        <div />
      </FormShell>,
    );
    expect(screen.getByText(/Редактирование: Подсеть/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/FormShell.test.tsx`
Expected: FAIL — cannot resolve `./FormShell`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/FormShell.tsx
// FormShell — единый заголовок (level=4 + ResourceIcon + verb) + контейнер тела
// Create/Edit форм. Унифицирует title между modal и page (раньше page был
// level=3 без иконки и с другим текстом). title-override опционален.
import { Typography } from "antd";
import { ResourceIcon } from "@/components/form/ResourceIcon";

interface Props {
  specId: string;
  mode: "create" | "edit";
  singular: string;
  title?: string;
  children: React.ReactNode;
}

export function FormShell({ specId, mode, singular, title, children }: Props) {
  const heading = title ?? `${mode === "create" ? "Создание" : "Редактирование"}: ${singular}`;
  return (
    <div>
      <Typography.Title
        level={4}
        style={{ margin: "0 0 16px", display: "flex", alignItems: "center", gap: 10 }}
      >
        <ResourceIcon specId={specId} />
        {heading}
      </Typography.Title>
      {children}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/FormShell.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/form/FormShell.tsx src/components/form/FormShell.test.tsx
git commit -m "feat(KAC-241): FormShell primitive (unified title + icon + container)"
```

---

## Task 5: FormSection primitive

**Files:**
- Create: `src/components/form/FormSection.tsx`
- Test: `src/components/form/FormSection.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/FormSection.test.tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect } from "vitest";
import { FormSection } from "./FormSection";

describe("FormSection", () => {
  it("renders a title and its children", () => {
    render(<FormSection title="Сеть"><div>child</div></FormSection>);
    expect(screen.getByText("Сеть")).toBeInTheDocument();
    expect(screen.getByText("child")).toBeInTheDocument();
  });

  it("collapses children when collapsible + defaultOpen=false", async () => {
    render(<FormSection title="Расширенное" collapsible defaultOpen={false}><div>hidden</div></FormSection>);
    expect(screen.queryByText("hidden")).toBeNull();
    await userEvent.click(screen.getByText("Расширенное"));
    expect(screen.getByText("hidden")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/FormSection.test.tsx`
Expected: FAIL — cannot resolve `./FormSection`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/FormSection.tsx
// FormSection — группа полей с заголовком + тонким divider. Best-practice:
// разбивать инфра-форму на секции (Идентичность → Конфигурация → Сеть →
// Расширенное). collapsible+defaultOpen=false — для optional/advanced-блоков.
import { useState } from "react";
import { Typography } from "antd";
import { DownOutlined, RightOutlined } from "@ant-design/icons";

interface Props {
  title: string;
  collapsible?: boolean;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

export function FormSection({ title, collapsible, defaultOpen = true, children }: Props) {
  const [open, setOpen] = useState(defaultOpen);
  const toggle = () => collapsible && setOpen((v) => !v);
  return (
    <div style={{ marginBottom: 8 }}>
      <div
        onClick={toggle}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          cursor: collapsible ? "pointer" : "default",
          margin: "4px 0 12px",
          borderBottom: "1px solid var(--border, #383941)",
          paddingBottom: 6,
        }}
      >
        {collapsible && (open ? <DownOutlined /> : <RightOutlined />)}
        <Typography.Text strong type="secondary" style={{ textTransform: "uppercase", fontSize: 12, letterSpacing: 0.4 }}>
          {title}
        </Typography.Text>
      </div>
      {open && children}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/FormSection.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/form/FormSection.tsx src/components/form/FormSection.test.tsx
git commit -m "feat(KAC-241): FormSection primitive (titled group, collapsible)"
```

---

## Task 6: ResourceFormBody (core)

**Files:**
- Create: `src/components/form/ResourceFormBody.tsx`
- Test: `src/components/form/ResourceFormBody.test.tsx`

**Behavior contract (unifies the 4 shells):**
- Renders `FormShell` (title) + AntD `<Form horizontal labelCol=200px colon=false size=middle>` + fields + `FormFooter`.
- Field visibility: skip `hidden`; in edit also skip `editHidden`/`createOnly`; apply `visibleWhen`. (Same rules the two shells use today, unified.)
- **Locked/immutable fields** (`lockedPaths.has(name)` OR `mode==="edit" && field.immutable`) that are scalar-ish (NOT `array`/`sg-rules`/`custom`/`labels`) render as `<ImmutableField>` (read-only + 🔒). This replaces modal-create's "hide locked" AND page-create's "disabled + Alert" with one visible affordance.
- Other fields render `<Form.Item label={<FieldLabel/>} required>` + `<FormFieldRenderer editMode={mode==="edit"} hideLabel/>`; full-width types (`array`/`sg-rules`/`custom`) render label-less full width (unchanged).
- `fieldOptionsFilter` narrows enum options (was in `InlineResourceCreateForm`).
- No `spec.fields` → warning Alert.

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/form/ResourceFormBody.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { ResourceFormBody } from "./ResourceFormBody";
import type { ResourceSpec } from "@/lib/resource-registry";

const spec = {
  id: "networks",
  singular: "Сеть",
  fields: [
    { name: "name", label: "Имя", type: "string", required: true },
    { name: "network_id", label: "Сеть", type: "string", description: "родитель" },
  ],
} as unknown as ResourceSpec;

describe("ResourceFormBody", () => {
  it("renders create title + editable name field + footer", () => {
    render(
      <ResourceFormBody
        spec={spec} mode="create" obj={{ name: "n1" }} onChange={() => {}}
        submitLabel="Создать сеть" submitting={false} onSubmit={() => {}} onCancel={() => {}}
      />,
    );
    expect(screen.getByText(/Создание: Сеть/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Создать сеть" })).toBeInTheDocument();
  });

  it("renders a locked field as read-only with a lock", () => {
    render(
      <ResourceFormBody
        spec={spec} mode="create" obj={{ name: "n1", network_id: "enpXYZ" }} onChange={() => {}}
        lockedPaths={new Set(["network_id"])}
        submitLabel="Создать сеть" submitting={false} onSubmit={() => {}} onCancel={() => {}}
      />,
    );
    expect(screen.getByText("enpXYZ")).toBeInTheDocument();
    expect(screen.getByLabelText("immutable-lock")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/form/ResourceFormBody.test.tsx`
Expected: FAIL — cannot resolve `./ResourceFormBody`.

- [ ] **Step 3: Write the component**

```tsx
// src/components/form/ResourceFormBody.tsx
// ResourceFormBody — ЕДИНЫЙ рендер тела Create/Edit формы ресурса. Рендерится
// и modal-шеллом (Inline*Form), и page-шеллом (ResourceCreate/EditPage), что
// даёт паритет create==edit==modal==page. Шеллы владеют state + mutation +
// Operation-flow и передают obj/onChange/lockedPaths/submit сюда.
import { Alert, Form, Space } from "antd";
import { FormFieldRenderer } from "@/components/form/FormField";
import { FormShell } from "@/components/form/FormShell";
import { FieldLabel } from "@/components/form/FieldLabel";
import { FormFooter } from "@/components/form/FormFooter";
import { ImmutableField } from "@/components/form/ImmutableField";
import { getByPath } from "@/lib/path";
import type { ResourceSpec } from "@/lib/resource-registry";

export interface ResourceFormBodyProps {
  spec: ResourceSpec;
  mode: "create" | "edit";
  obj: Record<string, unknown>;
  onChange: (next: Record<string, unknown>) => void;
  /** preset/immutable paths → read-only ImmutableField. */
  lockedPaths?: Set<string>;
  /** per-field enum option narrowing (create-context). */
  fieldOptionsFilter?: Record<string, string[]>;
  /** title override (default "Создание/Редактирование: <singular>"). */
  title?: string;
  /** optional banner above the form (e.g. page-create context note). */
  notice?: React.ReactNode;
  submitLabel: string;
  submitting: boolean;
  onSubmit: () => void;
  onCancel: () => void;
  /** sticky footer for tall forms. */
  stickyFooter?: boolean;
}

const FULL_WIDTH = new Set(["sg-rules", "array", "custom"]);

function matchesVisibleWhen(
  obj: Record<string, unknown>,
  vw: { field: string; equals: string | string[] } | undefined,
): boolean {
  if (!vw) return true;
  const cur = getByPath(obj, vw.field) as string | undefined;
  return Array.isArray(vw.equals) ? vw.equals.includes(cur ?? "") : cur === vw.equals;
}

function displayValue(obj: Record<string, unknown>, field: any): React.ReactNode {
  const raw = getByPath(obj, field.name);
  if (field.type === "enum" && Array.isArray(field.options)) {
    const opt = field.options.find((o: { value: string }) => o.value === raw);
    if (opt) return opt.label;
  }
  return raw == null ? "" : String(raw);
}

export function ResourceFormBody({
  spec,
  mode,
  obj,
  onChange,
  lockedPaths,
  fieldOptionsFilter,
  title,
  notice,
  submitLabel,
  submitting,
  onSubmit,
  onCancel,
  stickyFooter,
}: ResourceFormBodyProps) {
  const fields = spec.fields;
  if (!fields) {
    return (
      <Alert
        type="warning"
        message={`У ресурса ${spec.singular} нет form-schema; используйте API напрямую.`}
      />
    );
  }
  const editMode = mode === "edit";
  const locked = lockedPaths ?? new Set<string>();

  const visible = fields.filter((f) => {
    if (f.hidden) return false;
    if (editMode && (f.editHidden || f.createOnly)) return false;
    return matchesVisibleWhen(obj, f.visibleWhen);
  });

  return (
    <FormShell specId={spec.id} mode={mode} singular={spec.singular} title={title}>
      {notice}
      <Form
        layout="horizontal"
        labelCol={{ flex: "200px" }}
        wrapperCol={{ flex: "auto" }}
        labelAlign="left"
        colon={false}
        size="middle"
      >
        {visible.map((f) => {
          const isLocked = locked.has(f.name) || (editMode && (f as any).immutable);
          const fullWidth = FULL_WIDTH.has(f.type as string);

          // Locked scalar/ref → read-only affordance (not hidden, not silent-disabled).
          if (isLocked && !fullWidth && f.type !== "labels") {
            return (
              <Form.Item key={f.name} label={<FieldLabel text={f.label} info={f.description} />}>
                <ImmutableField
                  value={displayValue(obj, f)}
                  reason={editMode ? "Неизменяемо после создания" : "Задано из контекста"}
                />
              </Form.Item>
            );
          }

          const allowed = fieldOptionsFilter?.[f.name];
          const field =
            allowed && f.type === "enum"
              ? {
                  ...f,
                  options: allowed
                    .map((v) => (f as any).options.find((o: { value: string }) => o.value === v))
                    .filter(Boolean),
                }
              : f;

          const inner = (
            <FormFieldRenderer
              field={field as any}
              pathPrefix=""
              value={obj}
              onChange={onChange}
              editMode={editMode}
              hideLabel={!fullWidth}
            />
          );

          if (fullWidth) {
            return (
              <Form.Item key={f.name} wrapperCol={{ offset: 0, flex: "auto" }} colon={false}>
                {inner}
              </Form.Item>
            );
          }
          return (
            <Form.Item
              key={f.name}
              label={<FieldLabel text={f.label} info={f.description} />}
              required={!!f.required}
            >
              {inner}
            </Form.Item>
          );
        })}

        <Form.Item wrapperCol={{ offset: 0, flex: "auto" }}>
          <FormFooter
            submitLabel={submitLabel}
            submitting={submitting}
            onSubmit={onSubmit}
            onCancel={onCancel}
            sticky={stickyFooter}
          />
        </Form.Item>
      </Form>
    </FormShell>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/form/ResourceFormBody.test.tsx`
Expected: PASS (2 tests). If `ResourceSpec`/`FormField` types reject the literal cast, keep the `as unknown as ResourceSpec` cast in the test (test-only).

- [ ] **Step 5: typecheck**

Run: `npm run typecheck`
Expected: PASS (no TS errors introduced).

- [ ] **Step 6: Commit**

```bash
git add src/components/form/ResourceFormBody.tsx src/components/form/ResourceFormBody.test.tsx
git commit -m "feat(KAC-241): ResourceFormBody — single shared form body (modal+page)"
```

---

## Task 7: Refactor InlineResourceCreateForm → ResourceFormBody

**Files:**
- Modify: `src/components/InlineResourceCreateForm.tsx`

This is a behavior-preserving refactor (the data lifecycle stays; only the JSX/`return` changes). One behavior change is intentional: preset/locked fields now render as `ImmutableField` (visible read-only) instead of being filtered out.

- [ ] **Step 1: Replace the `return (...)` block**

Replace the entire `return ( <div> ... </div> );` (lines ~151–263) with:

```tsx
  return (
    <ResourceFormBody
      spec={spec}
      mode="create"
      obj={obj}
      onChange={setObj}
      lockedPaths={lockedPathsRef.current}
      fieldOptionsFilter={fieldOptionsFilter}
      title={title}
      submitLabel={`Создать ${spec.singular.toLowerCase()}`}
      submitting={mutation.isPending || pendingOpId !== null}
      onSubmit={submit}
      onCancel={onCancel}
    />
  );
```

Keep the early `if (!fields)` Alert guard OR delete it (body handles no-fields). Keep it for the typed `fields` usage below it; it's harmless.

- [ ] **Step 2: Fix imports**

At top of file: **remove** now-unused imports `Button, Form, Space, Tooltip, Typography` (from antd), `QuestionCircleOutlined`, `FormFieldRenderer`, `ResourceIcon`, `DopplerButton`, and `getByPath` (from `@/lib/path`). **Keep** `Alert` (used by the no-fields guard) and `setByPath`. **Add**:

```tsx
import { ResourceFormBody } from "@/components/form/ResourceFormBody";
```

- [ ] **Step 3: typecheck**

Run: `npm run typecheck`
Expected: PASS. If TS flags an unused import you missed, remove it.

- [ ] **Step 4: Run existing unit tests**

Run: `npm test`
Expected: PASS (no regressions; `ResourceFormDialog.test.ts` / registry tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add src/components/InlineResourceCreateForm.tsx
git commit -m "refactor(KAC-241): InlineResourceCreateForm renders ResourceFormBody"
```

---

## Task 8: Refactor InlineResourceEditForm → ResourceFormBody

**Files:**
- Modify: `src/components/InlineResourceEditForm.tsx`

- [ ] **Step 1: Replace the `return (...)` block**

Replace the `return ( <div> ... </div> );` (lines ~143–229) with:

```tsx
  return (
    <ResourceFormBody
      spec={spec}
      mode="edit"
      obj={obj}
      onChange={setObj}
      submitLabel="Сохранить"
      submitting={mutation.isPending || pendingOpId !== null}
      onSubmit={submit}
      onCancel={onCancel}
    />
  );
```

(The body applies the edit field-filter — `editHidden`/`createOnly`/`visibleWhen` — and `editMode`, so the local `visibleFields` memo can be deleted.)

- [ ] **Step 2: Remove dead code + fix imports**

Delete the `visibleFields` `useMemo` block (lines ~117–132). Remove now-unused imports: `Button, Form, Space, Tooltip, Typography`, `QuestionCircleOutlined`, `FormFieldRenderer`, `ResourceIcon`, `DopplerButton`, `getByPath`, and `useMemo` if no longer used. Keep `Alert`, `computeUpdateMask`, `snakeToCamelPath`. Add:

```tsx
import { ResourceFormBody } from "@/components/form/ResourceFormBody";
```

- [ ] **Step 3: typecheck + tests**

Run: `npm run typecheck && npm test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/components/InlineResourceEditForm.tsx
git commit -m "refactor(KAC-241): InlineResourceEditForm renders ResourceFormBody"
```

---

## Task 9: Refactor ResourceCreatePage → ResourceFormBody

**Files:**
- Modify: `src/components/ResourceCreatePage.tsx`

This achieves **page == modal** for create. The page keeps its breadcrumb/back-link/navigate lifecycle; only the form `<Card>` block is replaced.

- [ ] **Step 1: Replace the form region**

In the returned JSX, replace the title block + preset `<Alert>` + `<Card size="small">...</Card>` + the footer `<Space>` (lines ~194–250) with a single `ResourceFormBody`. The new `return`:

```tsx
  return (
    <div style={{ maxWidth: 760 }}>
      <Space direction="vertical" size={20} style={{ width: "100%" }}>
        <div>
          <Link to={backHref}>
            <Button type="text" size="small" icon={<ArrowLeftOutlined />} style={{ marginLeft: -8 }}>
              {spec.plural}
            </Button>
          </Link>
        </div>
        <ResourceFormBody
          spec={spec}
          mode="create"
          obj={obj}
          onChange={setObj}
          lockedPaths={lockedPathsRef.current}
          submitLabel={`Создать ${spec.singular.toLowerCase()}`}
          submitting={mutation.isPending || pendingOpId !== null}
          onSubmit={submit}
          onCancel={() => navigate(backHref)}
        />
      </Space>
    </div>
  );
```

(The preset `<Alert>` is removed — locked context now shows inline as `ImmutableField`. The back-link stays as page chrome.)

- [ ] **Step 2: Fix imports + remove dead code**

Remove now-unused imports: `Card, Tag, Typography` (antd) if unused elsewhere — **note** `Typography` is still used in `breadcrumb`; keep it. Remove `FormFieldRenderer`, `DopplerButton`. Remove the `void getByPath;` line and the `getByPath` import (still imported from resource-registry — verify; if `getByPath` is unused after, drop it). Add:

```tsx
import { ResourceFormBody } from "@/components/form/ResourceFormBody";
```

- [ ] **Step 3: typecheck + tests**

Run: `npm run typecheck && npm test`
Expected: PASS. Resolve any "declared but never read" by removing that import.

- [ ] **Step 4: Commit**

```bash
git add src/components/ResourceCreatePage.tsx
git commit -m "refactor(KAC-241): ResourceCreatePage renders ResourceFormBody (page==modal)"
```

---

## Task 10: Refactor ResourceEditPage → ResourceFormBody

**Files:**
- Modify: `src/components/ResourceEditPage.tsx`

> Read this file fully first (it mirrors `ResourceCreatePage` for edit — hydrate + computeUpdateMask + immutable fields). Apply the same transformation.

- [ ] **Step 1: Replace the form region with `ResourceFormBody`**

```tsx
        <ResourceFormBody
          spec={spec}
          mode="edit"
          obj={obj}
          onChange={setObj}
          submitLabel="Сохранить"
          submitting={mutation.isPending || pendingOpId !== null}
          onSubmit={submit}
          onCancel={() => navigate(backHref)}
        />
```

Keep the page's back-link/breadcrumb chrome and the hydrate/`computeUpdateMask`/`submit` logic exactly as-is. Replace only the inner `<Card>`/`FormFieldRenderer`/footer JSX.

- [ ] **Step 2: Fix imports (same pattern as Task 9)**

Remove `FormFieldRenderer`, `DopplerButton`, `Card`, and any now-unused antd imports; add `import { ResourceFormBody } from "@/components/form/ResourceFormBody";`.

- [ ] **Step 3: typecheck + tests**

Run: `npm run typecheck && npm test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/components/ResourceEditPage.tsx
git commit -m "refactor(KAC-241): ResourceEditPage renders ResourceFormBody (page==modal)"
```

---

## Task 11: Delete dead Radix `components/ui/*`

**Files:**
- Delete: `src/components/ui/button.tsx`, `src/components/ui/dialog.tsx`, `src/components/ui/input.tsx`, `src/components/ui/tabs.tsx`

- [ ] **Step 1: Confirm zero imports**

Run: `grep -rn "components/ui/" src --include=*.tsx --include=*.ts | grep -v "src/components/ui/"`
Expected: NO output (no consumers).

- [ ] **Step 2: Delete the files**

```bash
git rm src/components/ui/button.tsx src/components/ui/dialog.tsx src/components/ui/input.tsx src/components/ui/tabs.tsx
rmdir src/components/ui 2>/dev/null || true
```

- [ ] **Step 3: typecheck**

Run: `npm run typecheck`
Expected: PASS (nothing referenced them).

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(KAC-241): delete dead Radix components/ui/* (0 imports)"
```

---

## Task 12: Sync kacho-ui CLAUDE.md §3/§15

**Files:**
- Modify: `project/kacho-ui/CLAUDE.md`

- [ ] **Step 1: Update §3 opening + §15.1**

In §3, replace the absolute "Все Create/Edit ресурсов — модалки. Никаких отдельных страниц" with the variant-B reality:

> **VPC** Create/Edit — модалки (`?modal=<spec>-create|edit`). **Compute / NLB / System / project-edit** — full-page формы, но и модалка, и страница рендерят **единый `ResourceFormBody`** (`src/components/form/ResourceFormBody.tsx`) → визуальный паритет create==edit==modal==page. Запрет на новые `/<route>/create` для **VPC** остаётся; не-VPC page-формы обязаны рендерить `ResourceFormBody`.

In §15.1, soften "Не вводить отдельный /create route" to "для VPC — не вводить; не-VPC page-формы допустимы, но через `ResourceFormBody`."

Add to §2 the new primitives under `form/`: `FormShell`, `FormSection`, `FieldLabel`, `FormFooter`, `ImmutableField`, `ResourceFormBody`.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(KAC-241): sync kacho-ui CLAUDE.md §3/§15 with ResourceFormBody (variant B)"
```

---

## Task 13: Playwright e2e — modal/page parity + immutable affordance

**Files:**
- Modify/Create: `e2e/create-form.spec.ts` (extend existing)

> Read `e2e/create-form.spec.ts` + `e2e/_helpers.ts` first to reuse the existing login/nav helpers and selectors.

- [ ] **Step 1: Add a parity assertion**

Add a test that opens a VPC create modal and asserts the §4 layout is present (title with icon "Создание: …", primary submit button, label column), and that an Edit modal pre-fills and shows the immutable-lock affordance for an immutable field. Use existing helpers. Example skeleton (adapt selectors to `_helpers.ts`):

```ts
test("create modal uses unified form body (title + footer)", async ({ page }) => {
  await login(page);                            // from _helpers
  await gotoVpcList(page, "networks");          // adapt to existing helper
  await page.getByRole("button", { name: /Создать/ }).click();
  await expect(page.getByText(/Создание: /)).toBeVisible();
  await expect(page.getByRole("button", { name: /Создать сет/i })).toBeVisible();
});
```

- [ ] **Step 2: Run e2e (RED→GREEN)**

Run: `npm run e2e -- create-form.spec.ts`
Expected: GREEN against the refactored build (after Tasks 7–10). If the stand isn't reachable locally, document the manual smoke (port-forward UI) instead and mark this step as stand-verified.

- [ ] **Step 3: Commit**

```bash
git add e2e/create-form.spec.ts
git commit -m "test(KAC-241): e2e — unified form body parity (modal create)"
```

---

## Task 14: Final verification + PR

- [ ] **Step 1: Full gates**

Run: `npm run typecheck && npm test && npm run build`
Expected: all PASS (build = `tsc -b && vite build`).

- [ ] **Step 2: Manual smoke on the stand**

Build + load UI image (per kacho-ui CLAUDE.md §14 / memory: push to `docker.io/prorobotech/kacho-ui`, NOT ttl.sh), open: a generic VPC create modal, a generic edit modal, a compute create page, a system (region) create page — confirm identical title/icon/footer/label-column, and that an immutable field on edit shows 🔒 read-only.

- [ ] **Step 3: Push + PR**

```bash
git push -u origin KAC-241
gh pr create --title "[KAC-241] kacho-ui form unification — foundation (ResourceFormBody)" \
  --body "Single ResourceFormBody rendered by modal + page shells → create==edit==modal==page. New primitives (FieldLabel/FormFooter/ImmutableField/FormShell/FormSection). Dead Radix components/ui/* removed. CLAUDE.md §3/§15 synced (variant B). Custom forms (Subnet/SG/NIC/AddressPool) = Plan 2. Closes part of KAC-241 / relates KAC-239."
```

- [ ] **Step 4: Update YouTrack + vault**

Add the PR URL as a comment to KAC-241; tick DoD in `obsidian/kacho/KAC/KAC-241.md`; update `obsidian/kacho/packages/` for the new `form/` primitives.

---

## Self-Review

**Spec coverage (design §3/§4/§5):**
- §3.1 ResourceFormBody → Task 6. §3.2 FormShell → Task 4. §3.3 FormSection → Task 5. §3.4 FieldLabel → Task 1. §3.5 FormFooter → Task 2. §3.6 ImmutableField → Task 3. §3.7 CidrEditor → **Plan 2** (deferred, custom forms).
- §4 best-practices: sections (FormSection, Task 5 — adoption per-resource in Plan 2), immutable affordance (Task 3 + 6), inline-help (FieldLabel Task 1), unified footer (Task 2), sticky (FormFooter `sticky` Task 2), required-mark stays ConfigProvider.
- §5 surfaces: generic modal (Tasks 7–8), page (Tasks 9–10), dead `ui/*` (Task 11), CLAUDE.md (Task 12). Custom forms + new SG Create = **Plan 2**.
- §6 variant B: page kept for non-VPC, renders same body (Tasks 9–10), doc synced (Task 12).
- §7 tokens: untouched (no task changes palette) ✓. §1.4 dead Radix removed (Task 11), tailwind tokens untouched ✓.

**Placeholder scan:** No TBD/TODO in steps. Tasks 9/10/13 instruct "read file first" because exact line numbers shift after earlier edits — the transformation + target JSX are fully specified. ✓

**Type consistency:** `ResourceFormBody` prop names (`spec/mode/obj/onChange/lockedPaths/fieldOptionsFilter/title/submitLabel/submitting/onSubmit/onCancel`) are used identically in Tasks 7–10. `FieldLabel({text, info})`, `FormFooter({submitLabel, submitting, onSubmit, onCancel, sticky})`, `ImmutableField({value, reason})`, `FormShell({specId, mode, singular, title})` — consistent across Task 6 usage. ✓

**Gaps:** New SecurityGroup Create form, Subnet/NIC/AddressPool migration, `CidrEditor`, and unreachable-VPC-page-route removal are intentionally **Plan 2** (need those files read at execution time + foundation present first). Flagged in Scope + design §5.
