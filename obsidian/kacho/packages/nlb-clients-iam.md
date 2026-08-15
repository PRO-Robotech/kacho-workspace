---
title: nlb-clients-iam
category: packages
repo: kacho-nlb
layer: clients
tags:
  - packages
  - kacho-nlb
  - clients
  - cross-service
  - iam
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога, экспортируемая поверхность project- и check-клиента, отсутствие кэша; текст записки построчно не пересматривался"
---

# kacho-nlb/internal/clients/iam

**Каталог**: `services/nlb/internal/clients/iam/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/clients/iam/`)
**Imports**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/iam/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]] (Project check), [[nlb-internal-check]] (Check client), [[nlb-internal-fgawrite]] (WriteCreatorTuple)

Typed peer-service gRPC client adapters для kacho-iam.

## Files

| File | Содержание |
|---|---|
| `doc.go` | overview пакета |
| `project_client.go` | wraps `iamv1.ProjectServiceClient` — метод `Get(ctx, projectID)`; per-call timeout, `mapProjectErr` в контракт-тон |
| `check_client.go` | wraps `iamv1.InternalIAMServiceClient.Check` — per-RPC authz-гейт; распознаёт `no path`-reason, `mapCheckErr` fail-closed |
| `register_applier.go` | `RegisterResourceClient` + `Applier` для дренажа очереди регистраций (owner-tuple через fgaproxy) |
| `sync_registrar.go` | синхронный регистратор — window-оптимизация post-commit; отказ классифицируется отдельно от дренажного |
| `*_test.go` | unit-tests (retry, timeout, маппинг отказов, отказ в правах, метки) |

> [!warning] Ни одного кэша в клиентах nlb нет — прежняя редакция описывала несуществующий
> Записка называла отдельный файл под LRU и приписывала project-клиенту `Exists`-хелпер с
> TTL 30s «positive-only». В дереве **ноль** упоминаний кэша во всём `services/nlb/internal/clients/`
> (проверено переписью по каталогу, не по одному файлу), а экспортируемый метод —
> `Get`, а не `Exists`. Разница не косметическая: запись про «positive-only кэш с
> анти-staleness» описывает поведение, которого нет, и следующий читатель стал бы
> объяснять им наблюдаемую задержку видимости, которая на деле приходит из
> eventually-consistent материализации прав, а не отсюда.
>
> Отдельно снят `WriteCreatorTuple`: прямая запись owner-tuple **заменена** регистрацией
> ресурса через fgaproxy (`RegisterResource`), см. [[../edges/nlb-to-iam-creator-tuple]].

## Pattern

Service-layer определяет port-interface; adapter в `clients/iam/` реализует, оборачивая
typed gRPC-stub + `corelib/retry.OnUnavailable` с per-call deadline.

## Imports

- `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/iam/v1`
- `kacho-corelib/retry`

## See also

[[../edges/nlb-to-iam-check]] [[../edges/nlb-to-iam-creator-tuple]] [[nlb-internal-check]] [[nlb-internal-fgawrite]]

#packages #kacho-nlb #clients #cross-service #iam
