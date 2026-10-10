---
title: ClusterService
aliases:
  - ClusterService (kaname)
  - публичный близнец InternalClusterService
proto_file: kaname/cloud/iam/v1/cluster_service.proto
category: rpc
backend: kaname
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-cluster]]"
methods_count: 4
async_methods: 2
status: test
related_tickets:
  - "[[KAC/issue-661-kaname]]"
  - "[[KAC/issue-540-kaname]]"
  - "[[KAC/issue-3093]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "kaname 296@aa253fa9bcad (git ls-remote 2026-10-08): proto/kaname/cloud/iam/v1/cluster_service.proto — git show (служба, четыре RPC и их пути REST); регистрация — cmd/kaname/grpc_register.go и internal/restfront/registration.go (git grep ClusterService); внесено коммитом 701512a5d (#661) в сборке 6b (PR kaname#668, 8b0379e2a9c5); порт публичного слушателя :9090 — cmd/kaname/bootposture.go (git grep); поля сообщений построчно не пересматривались"
---

# ClusterService (kaname) — администраторы кластера на публичной поверхности

**Предмет.** Публичный близнец [[rpc/iam-internal-cluster-service]]: перечень, назначение и снятие
администраторов единственного кластера на публичном слушателе службы и её REST-фронте. До него эти глаголы
были только на внутреннем слушателе, и системный администратор на посадке внешнего края не мог ими
воспользоваться ([[KAC/issue-661-kaname]]).

**Состояние — `test`.** В ветке эпика `296`, в `main` службы не влито; задача #661 открыта (S1 в дереве,
сценарии CAP-20 и CAP-21 приёмки переутверждены после сборки — PR kaname#674). Пин службы на краю (`8b0379e2a9c5`) и
регистрация на внешнем слушателе края — [[KAC/issue-3093]], влиты в ветку эпика платформы `1266`
(kacho#3104, `ad74c3ea01b5`); экраны консоли — kacho#3094.

## Методы

| RPC | REST | ответ | порог уверенности |
|---|---|---|---|
| `Get` | `GET /iam/v1/cluster` | `Cluster` (синхронно) | 1 |
| `GrantAdmin` | `POST /iam/v1/cluster/admins` | `Operation` | 2 |
| `RevokeAdmin` | `DELETE /iam/v1/cluster/admins/{subject_id}` | `Operation` | 2 |
| `ListAdmins` | `GET /iam/v1/cluster/admins` | `ListClusterAdminsResponse` (синхронно) | 1 |

## Что держит контракт

- **Одна форма предмета.** Сообщения запросов и ответов — те же, что у внутреннего близнеца (импорт
  `internal_cluster_service.proto`); оба близнеца исполняют одни и те же экземпляры сценариев, поэтому у
  таблицы назначений один путь записи.
- **Право** — отношение `system_admin` на синглтоне кластера; оно объявлено для пользователя и сервисного
  аккаунта и подстановочным знаком не выполняется, поэтому ни один из четырёх RPC не является чтением каталога.
- **Мутации** возвращают `Operation`, сохранённую до мутации и завершённую тем же запросом (`done = true`).
- **Последний активный администратор** не снимается — инвариант держит база (условный UPDATE под
  транзакционной блокировкой); публичный путь его не обходит.

## History

- 2026-10-08 — заведена: служба внесена сборкой 6b волны-6 ([[KAC/issue-540-kaname]], PR kaname#668,
  `8b0379e2a9c5`); приёмка `cluster-admins-on-the-public-surface` — PR kaname#666 и #674.

- 2026-10-10 — край платформы: четыре метода в allowlist и зарегистрированы на внешнем REST-слушателе,
  пин службы `8b0379e2a9c5` — [[KAC/issue-3093]], kacho#3104 → `1266` @`ad74c3ea01b5` (сверено
  `git show 0ca889983ee4:gateway/internal/allowlist/list.go` и `…/restmux/mux.go`); DoD-proof задачи нет.

## See also

[[rpc/iam-internal-cluster-service]] · [[resources/iam-cluster]] · [[edges/ui-to-apigw-cluster-admins]]

#rpc #kacho-iam #iam
