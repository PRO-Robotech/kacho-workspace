# Permission catalog — source-of-truth и sync-pipeline

**KAC**: [KAC-178](https://prorobotech.youtrack.cloud/issue/KAC-178) §5
**Owner repos**: `kacho-proto`, `kacho-api-gateway`, `kacho-iam`
**Status**: 2026-05-24 — runtime-source clarified, sync rule established

## Контекст

Permission catalog — это JSON-mapping `gRPC fqn → {permission, required_relation, scope_extractor}`,
которым руководствуется per-RPC AuthZ-interceptor api-gateway при вызове
`kacho-iam.InternalIAMService.Check`. До KAC-178 catalog существовал в **двух**
embedded-копиях, что порождало путаницу — какой из них «настоящий».

## Источник истины (runtime)

| Назначение | Path | Размер | Status |
|---|---|---|---|
| **Runtime** (api-gateway middleware embed) | `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` | ~2770 lines | ✅ source-of-truth |
| Integration-test bootstrap (kacho-iam) | `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` | ~2161 lines | mirror, **не runtime** |
| Generated source (планируется) | `kacho-proto/gen/permission_catalog.json` | n/a (Phase 3) | TBD generator |

> [!important] Catalog miss → `403 catalog: no entry for method <fqn>`
> Все runtime-ошибки `"catalog: no entry"` — от api-gateway middleware, НЕ от kacho-iam.

## Sync-pipeline

1. **Phase 1 (текущий)** — catalog поддерживается **вручную** в
   `kacho-api-gateway/internal/middleware/embed/permission_catalog.json`. При
   добавлении нового RPC в любой сервис разработчик одновременно с proto-PR
   делает PR в api-gateway с entry для нового fqn.
2. **Phase 3 (планируется)** — auto-generation из proto-annotations через
   `kacho-proto/gen/permission_catalog.json` (KAC-127 acceptance §6.9.3). После
   реализации sync-pipeline:
   ```
   kacho-proto/gen/permission_catalog.json
      │  (Makefile target: kacho-api-gateway/make sync-permission-catalog)
      ▼
   kacho-api-gateway/internal/middleware/embed/permission_catalog.json
   ```
3. **kacho-iam mirror** обновляется по необходимости integration-тестов; не
   привязан к runtime-релиз-циклу. Расхождения kacho-iam mirror vs api-gateway
   runtime — НЕ инцидент (integration-tests читают только подмножество, нужное
   для KAC-127 Phase 4 проверок). Mirror помечен заголовком в file header.

## Что не source-of-truth (anti-patterns)

- ❌ `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` — **mirror**;
  `LoadPermissionRegistry` вызывается **только** из
  `internal/repo/kacho/pg/kac127_repos_integration_test.go`. Не читается в
  runtime kacho-iam.
- ❌ Любой embedded JSON внутри service-репо (`kacho-vpc`/`kacho-compute`/...) —
  если появится, это явный bug: backend сервисы НЕ должны иметь permission
  catalog (они получают decision от api-gateway interceptor через MD или
  отдельный Check-вызов).

## Sync rule

В `kacho-api-gateway/Makefile` есть target:

```makefile
sync-permission-catalog:
	cp ../kacho-proto/gen/permission_catalog.json internal/middleware/embed/permission_catalog.json
```

> [!note] Phase 1 caveat
> До реализации Phase 3 generator (`kacho-proto/gen/`) target не работает (source
> файла нет). Catalog editing manual + PR-review per change. После Phase 3
> generator-PR в kacho-proto → triggers regeneration → sync-PR в api-gateway.

## Тесты

`kacho-api-gateway/internal/e2e/authz_e2e_test.go` валидирует **runtime catalog**
end-to-end (через docker-compose с api-gateway + kacho-iam stub). Cherry-pick PR
тестируется этим suite.

`kacho-iam/internal/repo/kacho/pg/kac127_repos_integration_test.go` (тесты
`Test_KAC127_PermissionRegistry_*`) валидируют **mirror** — что embedded JSON
parsing работает, что schema сохраняется. Тесты НЕ доказывают runtime-validity.

## Связанные доки

- [`07-conventions.md`](./07-conventions.md) — общие conventions
- [`docs/specs/sub-phase-W1.4-principal-propagation-acceptance.md`](../specs/sub-phase-W1.4-principal-propagation-acceptance.md) — W1.4 catalog usage
- [`kacho-iam/docs/specs/...-iam-acceptance.md`](../../project/kacho-iam/docs/specs/) — Phase 3 catalog rollout (§6.9.3)
- KAC-127 — original IAM Phase 4 epic
- KAC-178 — this consolidation
