# C-CR-3 — YC не enforce-ит уникальность Cloud.name

**Дата:** 2026-05-04
**Категория:** wrong-validation (наша строже YC)

## YC reference

```bash
$ curl -X POST -H "Authorization: Bearer $YC_TOKEN" \
  -H "Content-Type: application/json" \
  https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds \
  -d '{"name":"qa-dup-cloud","organization_id":"bpfgrbrhbbg6e56ue4ol"}'
```
Результат (повторный POST с тем же name):
- HTTP 200
- Operation `done:true`, `response.Cloud{id:b1g3lhmbemiafqtr88fc, name:"qa-dup-cloud", ...}` — **успешное создание дубликата**.

В YC `cloud-list` теперь две записи с `name="qa-dup-cloud"` (разные id).

## Kachō actual

```bash
$ curl -X POST $KACHO/resource-manager/v1/clouds \
  -d '{"name":"qa-dup-cloud","organization_id":"<existing>"}'
```
- HTTP 200, Operation `done:true`, `error: code 6 (ALREADY_EXISTS) "Cloud qa-dup-cloud already exists"`.

## Расхождение

YC **не enforce-ит** уникальность name среди Cloud в рамках организации. У нас миграция содержит `UNIQUE (organization_id, name)`.

## Решение

Два варианта:

1. **Принять YC-поведение** — убрать UNIQUE constraint, разрешить дубликаты.
   - Плюсы: verbatim YC.
   - Минусы: пользователь может создать N одинаковых cloud-ов с одинаковым name. UI это покажет странно (Folder-selector с двумя одинаковыми именами различим только id-prefix).
2. **Оставить нашу строгость** — задокументировать как сознательное решение Kachō (стартер cloud project — лучше чем у YC).
   - Плюсы: cleaner UX.
   - Минусы: deviation от YC contract.

### Рекомендация: Вариант 2

Документировать как Kachō-extension: дополнительная защита от user-error. Migrations не менять. Добавить замечание в spec / CLAUDE.md.

## Repro

```bash
ORG=$(curl -s -H "Authorization: Bearer $YC_TOKEN" \
  https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds | jq -r '.clouds[0].organizationId')

# Первый POST
curl -X POST -H "Authorization: Bearer $YC_TOKEN" \
  -H "Content-Type: application/json" \
  https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds \
  -d "{\"name\":\"qa-dup\",\"organization_id\":\"$ORG\"}"

# Второй POST с тем же name → YC OK, Kachō ALREADY_EXISTS
```
