# JSON case style — наш snake_case vs YC camelCase

**Дата:** 2026-05-04
**Категория:** wrong-shape (cross-cutting на ВСЕХ ресурсах)

## Что отличается

YC отдаёт JSON в **camelCase**:
```json
{
  "id": "b1g3lhmbemiafqtr88fc",
  "createdAt": "2026-05-04T00:36:50Z",
  "name": "qa-dup-cloud",
  "organizationId": "bpfgrbrhbbg6e56ue4ol"
}
```

Kachō отдаёт **snake_case**:
```json
{
  "id": "9801d92a-1e9e-46dd-acc6-573030b2fcc5",
  "created_at": "2026-05-04T00:36:50.813266Z",
  "name": "qa-dup-cloud",
  "organization_id": "764b6f78-c1d9-47a0-a201-7ccea40b0e26"
}
```

## Почему так

В `kacho-api-gateway/internal/restmux/mux.go` мы **намеренно** включили:

```go
jsonMarshaler := &runtime.JSONPb{
  MarshalOptions: protojson.MarshalOptions{
    UseProtoNames:   true,    // ← snake_case вместо camelCase
    EmitUnpopulated: true,
  },
}
```

Это сделано чтобы UI (`resource-registry.ts` colums.path = `"created_at"`, fields `"organization_id"`) работал без mapping-а.

YC default — `UseProtoNames=false` → camelCase.

## Расхождение

Все клиенты, ожидающие YC contract verbatim (yc-go-sdk, yc-cli, terraform provider, custom клиенты), будут падать на shape mismatch.

## Решение

**Вариант 1 (verbatim YC):** убрать `UseProtoNames`, переписать UI.
- backend: 1 строка в restmux.go.
- UI: ~всё в resource-registry.ts (paths и fields), client.ts (typed responses), api/types.ts (interface field names) — порядка 50-100 правок.
- Выгода: настоящая совместимость с YC SDK / CLI / докой.

**Вариант 2 (status quo):** оставить snake_case как Kachō convention.
- Плюсы: меньше работы, UI работает.
- Минусы: deviation, документировать как breaking-change для YC-compatible client.

**Вариант 3 (compromise):** включить `UseEnumNumbers=false` + `UseProtoNames=false` (default) → camelCase JSON; в UI добавить адаптер Object→snake_case in api/client.ts (transform once), всё остальное UI ничего не знает.
- Backend в полной совместимости с YC.
- UI — один адаптер.
- ~Среднее усилие.

### Рекомендация: Вариант 3

Это даст true verbatim contract на API level + минимум UI работы. Адаптер в `api/client.ts` (~30 строк рекурсивный камелкейс↔snake_case).

## Затрагиваемые ресурсы

ВСЕ — это transport-level concern.

## Repro

```bash
# YC
curl -s -H "Authorization: Bearer $YC_TOKEN" \
  https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds | jq '.clouds[0]'
# → "createdAt", "organizationId"

# Kachō
curl -s http://localhost:8080/resource-manager/v1/clouds | jq '.clouds[0]'
# → "created_at", "organization_id"
```
