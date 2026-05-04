# <SCENARIO_ID> — короткое описание (например "O-CR-3 — Create org duplicate name")

**Дата:** YYYY-MM-DD
**Тестировщик:** ваш ник
**Категория:** missing-feature | wrong-error-code | wrong-validation | wrong-shape | docs-gap

---

## Setup

(если нужно: какие test-ресурсы предварительно создать в YC и Kachō)

## YC reference

```bash
$ yc <command>
<output>
```
- exit code: 0 / N
- error code (gRPC): N (NAME)

## Kachō actual

```bash
$ curl ...
<output>
```
- HTTP status: 4xx / 5xx / 200
- error code (gRPC): N (NAME)

## Расхождение

- Что отличается:
- Что должно быть согласно YC:
- Что у нас сейчас:

## Предлагаемый fix

- Где править: backend `<repo>/<file>:<line>` или proto `<file>` или UI `<file>`
- Сложность: tiny / small / medium / large

## Repro shell-скрипт

```bash
# минимальный прогон чтобы воспроизвести; копируется в issue
```
