---
title: nlb-apps-kacho-api-loadbalancer
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - usecase
  - loadbalancer
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов против каталога и против перечня RPC в proto домена; текст записки построчно не пересматривался"
---

# kacho-nlb/internal/apps/kacho/api/loadbalancer

**Каталог**: `services/nlb/internal/apps/kacho/api/loadbalancer/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/apps/kacho/api/loadbalancer/`)
**Implements**: [[../rpc/nlb-network-load-balancer-service|NetworkLoadBalancerService]]
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]], [[nlb-clients-iam]], [[nlb-clients-compute]], [[nlb-internal-fgawrite]]

Use-case slice per LoadBalancer — Clean Architecture: handler.go (gRPC adapter) + per-RPC use-case files (бизнес-логика).

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter; parse req → useCase.Run → dto.Transfer → format resp |
| `ports.go` | port-интерфейсы (Repo, peer-клиенты, Emitter) |
| `mapping.go` / `enum_mapping.go` | domain ↔ proto, включая enum'ы |
| `peer_errors.go` | классификация отказов соседа по полосам (peer-validate vs direct-read) |
| `idvalidate.go` | sync format-check id первым стейтментом RPC |
| `get.go` / `list.go` | sync reads |
| `create.go` | Validate + Project/Region check + ops.Insert + spawn worker |
| `update.go` | UpdateMask discipline; immutable: type/region_id/project_id |
| `delete.go` | sync precheck: deletion_protection / есть ли листенеры |
| `move.go` | cross-project, same-region |
| `get_target_states.go` | sync; computed runtime ramp INITIAL→HEALTHY |
| `list_operations.go` | per-resource history |
| `vip_source.go` / `zones.go` / `sg_validate.go` / `tg_authz.go` / `payloads.go` | резолв VIP-источников, зональность, проверка security-групп, authz на чужую target-группу, payload'ы воркера |
| `*_test.go` | unit-tests against mock repo + mock clients |

> [!warning] Четырёх файлов из прежней редакции нет — и не будет: RPC под них сняты контрактом
> Записка перечисляла отдельные файлы под привязку/отвязку target-группы и под
> административные глаголы включения/выключения балансировщика. **Ни одного из четырёх
> в каталоге нет, потому что нет самих RPC** — они сняты решением, записанным прямо в
> proto (`proto/kacho/cloud/loadbalancer/v1/package_options.proto`, п. 3, и
> `proto/kacho/cloud/loadbalancer/v1/network_load_balancer.proto`):
>
> - привязка target-группы больше не M:N-сводом. Листенер ссылается на **одну**
>   авторитетную группу (`Listener.target_group_id`, FK RESTRICT), а набор групп за
>   балансировщиком — **производное** объединение по его листенерам. Прежнее поле-массив
>   на балансировщике и его JSON-имя переведены в `reserved`, чтобы номер не переиспользовали;
> - административное включение/выключение выражается полем `admin_state`, а не парой
>   глаголов. Три соответствующих значения `Status` тоже `reserved`.
>
> Сами снятые адреса здесь не воспроизводятся: цитата мёртвого имени в обратных кавычках
> читается как живое утверждение о дереве — ровно та форма, которую ловит хук свежести.
> Следствие для соседних строк таблицы: у `delete.go` предусловие про «привязанные группы»
> и у `move.go` запрет «при привязанных группах» предметом больше не обладают — остаётся
> проверка листенеров.

## See also

[[../rpc/nlb-network-load-balancer-service]] [[../resources/nlb-load-balancer]] [[nlb-internal-fgawrite]] [[nlb-clients-vpc]]

#packages #kacho-nlb #handler #usecase #loadbalancer
