# C-DL-2 — YC использует soft-delete pending-7-days, у нас FAILED_PRECONDITION

**Дата:** 2026-05-04
**Категория:** missing-feature (Delete pattern)

## YC reference

```bash
$ curl -X DELETE -H "Authorization: Bearer $YC_TOKEN" \
  https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds/$CLOUD_ID
```
Когда у Cloud есть зависимые Folder-ы:
- HTTP 200
- Operation `done:false`, metadata содержит **`deleteAfter: 2026-05-11T...`** — **через 7 дней**.
- Cloud переходит в `PENDING_DELETION` status.
- Folders внутри также cascade в DELETING.
- Admin может вызвать `cloud.recover` (возможно? — нужно проверить отдельно), пока не наступил deleteAfter.

YC **не блокирует** delete с зависимыми ресурсами — наоборот, идёт каскад.

## Kachō actual

HTTP 200, body:
```json
{
  "code": 9,
  "message": "cloud has dependent resources: Folder"
}
```

Это **FAILED_PRECONDITION** (gRPC code 9), service.Cloud.Delete проверяет `repo.HasFolders` и отказывает.

## Расхождение

Kachō требует чтобы пользователь сначала вручную удалил все folders, потом cloud. YC сам каскадит и даёт «window of recovery». Это разные UX.

## Решение

**Вариант 1 (verbatim YC):** реализовать soft-delete с pending state.
- Migration: добавить колонки `pending_deletion_at` (timestamp), `delete_after` в clouds + folders.
- Service: при Delete — set status=DELETING (через UPDATE), затем cascade через child Delete-ops, в конце INSERT Operation с metadata.deleteAfter = now()+7d.
- Background worker: периодически проверяет `delete_after < now()` → physical DELETE.
- Recover RPC (опционально): cloud.recover отменяет soft-delete.
- Объём: ~2-3 дня

**Вариант 2 (текущий):** оставить синхронный FAILED_PRECONDITION.
- Минусы: deviation от YC.
- Плюсы: простой UX, не нужен background reaper.

**Рекомендация:** Документировать Variant 2 как Kachō decision (не реализуем soft-delete). Добавить только `cascade=true` query param на `DELETE /clouds/{id}` который автоматически каскадирует delete (без задержки 7 дней).

Либо добавить soft-delete как отдельную фазу (1.2?).

## Repro

```bash
# Создать cloud + folder
CLOUD_OP=$(curl -X POST $KACHO/resource-manager/v1/clouds -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-c\",\"organizationId\":\"$ORG\"}")
CID=$(echo $CLOUD_OP | jq -r '.metadata.cloudId')
curl -X POST $KACHO/resource-manager/v1/folders -H 'Content-Type: application/json' \
  -d "{\"name\":\"qa-f\",\"cloudId\":\"$CID\"}"

# DELETE — попытка
curl -X DELETE $KACHO/resource-manager/v1/clouds/$CID
# → code:9 message:"cloud has dependent resources"
```
