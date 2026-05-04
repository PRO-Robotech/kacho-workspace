# C-CR-INVALID-UUID — Kachō leak-ит сырую SQL-ошибку при невалидном UUID

**Дата:** 2026-05-04
**Категория:** wrong-error-code + leak

## Setup

YC organization_id формат — `bpfgrbrhbbg6e56ue4ol` (20 символов, base32-style).
Kachō organization_id формат — UUID v4 (`f70cf480-a2ae-...`).

При тестировании cross-cloud-API один и тот же `body` отправляется на оба endpoint-а — наш Kachō получает не-UUID строку как `organization_id`.

## Kachō actual

```bash
$ curl -X POST $KACHO/resource-manager/v1/clouds \
  -d '{"name":"qa-dup-cloud","organization_id":"bpfgrbrhbbg6e56ue4ol"}'
```
Сначала возвращает Operation `done:false`. Через ~100мс через polling — `done:true` с error:

```json
{
  "code": 2,
  "message": "repo.Get: ERROR: invalid input syntax for type uuid: \"bpfgrbrhbbg6e56ue4ol\" (SQLSTATE 22P02)",
  "details": []
}
```

## Что не так

1. **Code 2 = UNKNOWN** — должно быть **code 3 INVALID_ARGUMENT**.
2. Message содержит **SQL state code и raw pgx error** — internal-leak, не User-facing.
3. Должно быть что-то вроде: `organization_id "bpfgrbrhbbg6e56ue4ol" не является валидным UUID`.

## Расхождение с YC

YC не имеет такого вопроса — он использует свои короткие IDs, валидность которых проверяется сервером. Но и YC возвращал бы **InvalidArgument** при невалидном формате, не сырой DB error.

## Fix

В `kacho-resource-manager/internal/service/cloud.go` (и аналогично в каждом async-worker через `operations.Run`):
- Перед `repo.Get(orgID)` валидировать UUID format через `uuid.Parse(orgID)` — если ошибка, вернуть `coreerrors.InvalidArgument().AddFieldViolation("organization_id", "must be UUID v4").Err()`.
- Альтернативно — обернуть pgx 22P02 в repo-layer и вернуть NotFound (как-будто id не существует).

Также **общий** fix: в `kacho-corelib/db/` добавить wrapper который преобразует pg-errors `22P02` в gRPC InvalidArgument.

## Repro

```bash
curl -X POST -H 'Content-Type: application/json' \
  http://localhost:8080/resource-manager/v1/clouds \
  -d '{"name":"x","organization_id":"not-a-uuid"}'
# Получим Operation, через 1 сек GET /operations/{id} → error code:2 message:"...22P02..."
```

Ожидание: code:3 INVALID_ARGUMENT, message: `organization_id is invalid UUID`.
