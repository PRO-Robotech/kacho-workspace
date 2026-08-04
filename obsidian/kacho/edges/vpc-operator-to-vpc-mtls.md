---
title: kacho-vpc-operator → kacho-vpc / kacho-iam (mTLS read-only sync)
category: edge
caller_repo: kacho-vpc-operator
callee_repo: kacho-vpc
sync_async: sync-poll
protocol: gRPC over mTLS
status: planned
related_tickets:
  - SEC-G
tags:
  - edge
  - kacho-vpc-operator
  - kacho-vpc
  - kacho-iam
  - grpc
  - cross-service
  - security
  - experimental
---

# kacho-vpc-operator → {kacho-vpc, kacho-iam} (mTLS)

> [!warning] ВЫЗЫВАЮЩЕГО НЕ СУЩЕСТВУЕТ — ни в дереве, ни на GitHub (замер 2026-08-05)
> Названо прямо, потому что записка читается как описание работающего ребра.
>
> - **Репозиторий не резолвится**: `gh repo view PRO-Robotech/kacho-vpc-operator` →
>   `Could not resolve to a Repository`. Не «архив», не «приватный» — его нет.
> - **В монорепо нет ни одного файла оператора**: `git ls-files | grep -i operator` даёт
>   только чарт сертификата, пробу посева и три миграции iam. Имя `vpc-operator` встречается
>   в **35** файлах, и все 35 — это **следы** на стороне платформы: SPIFFE-SAN в списках
>   законных отправителей (vpc, gateway, чарты), посевы iam и их пробы.
> - Значит **ни один вызов по этому ребру никем не производится**. Проверять по нему живой
>   стенд нечего: у контракта нет второй стороны.
>
> **Что при этом ЖИВО и снимать нельзя** (это половина, которую легко перепутать):
> кластерный кортеж `system_viewer` из посева `0010` **остаётся** — он приобрёл второго,
> действующего читателя (`authzguard.SystemViewerFloor` гейтит на нём read-RPC внутреннего
> листенера; vpc отдельно гейтит на нём чтение инфра-чувствительного поля сети). А вот
> **веер прав служебной учётки оператора снят** миграцией `0076` как мёртвый, и снят
> целиком — вместе с ролью, потому что роль без правил уходит в легаси-ветку и **выдала бы**
> отношение, которого до правки не было. Разбор — `services/iam/internal/repo/kacho/pg/operator_dead_fanout_integration_test.go`.
>
> Ниже — контракт **на случай появления** оператора; как описание сегодняшнего дня он неверен.

SEC-G: оператор дилит control-plane по **mTLS** с отдельным client-cert (req #5).
Оператор — sibling, **вне build-графа** control-plane (общается только по gRPC).

## Рёбра

- **operator→vpc** — `SubnetService.List` / `NetworkService.Get` /
  `NetworkInterfaceService.Get` / `AddressService.Get` (syncer + webhook NIC-резолв).
- **operator→iam** — fan-out ns-operator'а: exempt `AccountService.List` (membership
  scope-filter) → viewer-scoped `ProjectService.List`.

## Транспорт (mTLS, SEC-B/SEC-G)

- corelib `grpcclient.TLSClient`, per-edge `KACHO_VPCOPERATOR_{VPC,IAM}_MTLS_*`.
- `enable=false` (default) → insecure (dev backward-compat, #1).
- `enable=true` → mTLS: op client-cert + internal-CA verify + server_name.
- client-cert SAN = `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator`
  (§4.1.4; ns-segment = фактический namespace оператора). Secret
  `vpc-operator-client-tls` (отдельный от webhook-server-cert, #5), рендерится
  cert-manager-config chart (`vpc-operator` entry, clientOnly).
- handshake-mismatch (backend insecure / cert не тот) → `codes.Unavailable`
  (fail-closed, §6.7); retry на следующем reconcile.

## AuthZ (least-priv ReBAC)

- principal-metadata `x-kacho-principal-{type:service_account,id:<sva>}` инжектится
  поверх mTLS (инвариант I2: listener доверяет principal ⟺ peer прошёл client-cert
  verify). IAM cert→SA mapping резолвит SAN → `sva||md5('kacho-vpc-operator')[:17]`.
- Оператор-SA: **read-only ReBAC viewer**-tuples на scope-объекты
  (account/project/vpc_network/vpc_network_interface), **нет** editor/owner →
  любая мутация (`SubnetService.Delete` …) → `PERMISSION_DENIED`.
- SA **освобождён** от `required_acr_min` (service→service, §4.1.2; у SA нет MFA).
- unknown SAN → DENY; known SAN без relation на конкретный scope → DENY (per-object
  ReBAC, не flat-capability). Seed + mapping — в kacho-iam (SEC-C, migration 0009).

## Граница mTLS-скоупа

operator→kube-ovn / operator→multus = k8s-API (downstream materialization), **вне**
gRPC-mTLS-периметра. mTLS — только на operator→{vpc,iam}. См. [[vpc-operator-to-kubeovn]].

## История

- 2026-06-11 (SEC-G) — insecure → mTLS (отдельный op client-cert) + least-priv
  read-only SA principal; per-edge enable; webhook server-cert на internal-CA.

#edge #kacho-vpc-operator #kacho-vpc #kacho-iam #grpc #cross-service #security #experimental
