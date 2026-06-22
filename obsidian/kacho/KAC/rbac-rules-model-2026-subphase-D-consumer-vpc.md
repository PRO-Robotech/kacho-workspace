---
title: RBAC rules-model 2026 — sub-phase D-consumer (kacho-vpc)
ticket_id: rbac-rules-model-2026-D-consumer-vpc
status: test
type: feature
repos:
  - kacho-vpc
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-workspace/issues/111
opened: 2026-06-21
tags:
  - kac
  - kacho-vpc
  - feature
  - usecase
  - repo
  - authz
  - fga
  - cross-service
---

# RBAC rules-model 2026 — sub-phase D-consumer (kacho-vpc)

**Status**: test (code-complete on branch `rbac-rules-d-consumer`, NOT committed/pushed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase D — per-object filtered `List`, §11)
**Repo**: kacho-vpc (consumer track; iam-core track = [[rbac-rules-model-2026-subphase-D-iam]])
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` (APPROVED раунд 2) — D-40..D-47 (LST-1..6)
**Issue**: PRO-Robotech/kacho-workspace#111 (D-consumer per-object filtered List for vpc/compute/nlb)

## Что и зачем

`List<Resource>` в kacho-vpc возвращает **только доступные объекты** (per-object FGA, НЕ
all-or-nothing). Заменяет project-level `CanViewProject` (KAC-240) на per-object
`AuthorizeService.ListObjects(subject, "vpc_<type>", "vpc.<res>.list")` → relation `viewer`
(read==enforce). Тот же tuple-base (scope_grant + materialized per-object из sub-phase B/C).

## Сделано (D-consumer, vpc)

- **`internal/authzfilter/`** (новый пакет, эталон — kacho-compute): `FGAFilter` поверх
  `AuthorizeService.ListObjects` (TTL-cache 5s, fail-closed default, `wildcard_grant`→bypass),
  `Decision`, `UseCasePort`, `AsPort`, `EnforceVisible` (Get no-leak helper), actions/resourceType
  константы (`vpc_subnet`/`vpc.subnets.list` …).
- **`internal/clients/iam_listobjects_client.go`**: gRPC adapter к `AuthorizeService.ListObjects`
  с `auth.PropagateOutgoing` (caller-principal, не system:bootstrap).
- **7 List use-cases** (network/subnet/securityGroup/routeTable/address/gateway/networkInterface):
  port `ListFilter` → `ListAllowedIDs(viewer)` → `repo.ListByIDs(WHERE id=ANY)`; bypass→repo.List;
  empty grant→пустой (no-leak D-44); fail-closed Unavailable (D-47); **pagination ПОСЛЕ фильтра** (D-46).
- **repo `ListByIDs`** добавлен в 6 ReaderIface + pg + kachomock (Network уже имел из KAC-127);
  `WHERE id = ANY($1::text[])`, LIMIT pageSize+1, keyset `(created_at,id)` над отфильтрованным набором.
- **Get no-leak** (D-44/LST-5): 7 `Get<Resource>` прогоняют id через тот же grant-set;
  id∉set → `NotFound` (тот же текст, что несуществующий ресурс) — НЕ PermissionDenied; fail-closed.
- **config** `authz.list-filter.enabled` default `false`→**`true`**; endpoint/mtls — через values (deploy).
- **`cmd/vpc/main.go`**: `buildListFilter`/`buildAuthorizeConn` (per-object FGA filter) заменили
  `newListAuthz` (project-level Check); фильтр инжектится во все 7 List + 7 Get use-cases.
- **CI-гейт `make audit-list-filter`** ужесточён до per-object (`ListAllowedIDs` обязателен; project-level `CanViewProject` больше не принимается).

## Тесты (RED→GREEN)

- **unit** (`subnet/list_perobject_test.go`, `network/list_perobject_test.go`): LST-1/4/5 (только доступные),
  D-42 wildcard bypass, D-44 no-leak (List+Get), D-47 fail-closed, read==enforce (relation viewer / vpc_subnet).
  RED = `undefined ListFilter`; GREEN после порта.
- **integration** (`pg/subnet_listbyids_integration_test.go`, testcontainers PG16): WHERE id=ANY фильтр,
  empty short-circuit, **D-46 pagination-after-filter** (5/8 → плотные 2+2+1), garbage token→InvalidArgument.
  RED = `SubnetReaderIface has no method ListByIDs`; GREEN после pg impl. ✅ colima, -p 1, не -short.
- **newman** (`cases/list-filter-d.py`, 5 кейсов): SUBNET-LF-D-VISIBLE/NOLEAK/GET-404/GET-OK/NONE.
  Чёрный ящик через api-gateway; фикстуры — `tests/authz-fixtures/setup.sh` (rules-role per-object grant).
- Удалены obsolete KAC-240 project-level тесты (`subnet/list_filter_test.go`, `network/list_project_authz_test.go`) — superseded §11.

## Затронутые сущности vault

- [[../edges/vpc-to-iam-listobjects]] — status planned→active; relation viewer, vpc_subnet, fail-closed, Get no-leak
- [[../edges/compute-to-iam-listobjects]] — эталон того же контракта
- [[rbac-rules-model-2026-subphase-D-iam]] (iam-core ListObjects) · [[rbac-rules-model-2026-subphase-B-iam]] / [[rbac-rules-model-2026-subphase-C-iam]] (tuple-base)

## DoD

- [x] 7 List per-object filtered (read==enforce, viewer)
- [x] Get no-leak (D-44) — NotFound, не PermissionDenied
- [x] fail-closed Unavailable (D-47)
- [x] pagination-after-filter (D-46)
- [x] enable-default true + audit-list-filter per-object
- [x] RED→GREEN unit + integration; newman gen
- [ ] deploy values (list-filter.enabled + authorize-endpoint + mtls) — отдельный kacho-deploy PR
- [ ] load-testing-coach gate (O-5) перед prod-flip — обязателен по acceptance DoD D
- [ ] commit/push + PR (НЕ в scope текущей сессии)

## Связанные

- Сиблинг-треки: compute D-consumer, nlb D-consumer (тот же §11 паттерн).
- CI: vpc НЕ build-зависит от iam (runtime edge); `AuthorizeService.ListObjects` уже в iam main/проде → CI-pin не нужен.
