---
title: "kaname internal/apps/kaname/api/internal_iam"
aliases:
  - kaname internal_iam handler
  - kaname-api-internal-iam
category: packages
path: internal/apps/kaname/api/internal_iam
repo: kacho-iam
layer: usecase
status: stable
related_tickets:
  - "[[KAC/issue-334-kaname]]"
  - "[[KAC/issue-340-kaname]]"
tags:
  - packages
  - kacho-iam
  - internal
  - usecase
  - go
verified_against: "перепись непробных файлов каталога на ревизии 229a0693 продукта PRO-Robotech/kaname (2026-09-21) — 9 файлов, перечислены ниже поимённо; построчно прочитан только `force_logout.go`"
---

# kaname `internal/apps/kaname/api/internal_iam`

Варианты использования **внутренней** поверхности IAM — по файлу на глагол плюс транспорт.
Поверхность не публикуется на внешний слушатель (запрет #6).

## Файлы (229a0693, непробные)

`catalog_type.go` · `check_basic_credential_live.go` · `force_logout.go` ·
`get_role_compiled.go` · `handler.go` · `lookup_subject.go` · `proxy_type_owner.go` ·
`register_resource.go` · `resolve_basic_credential.go`

## Порядок в принудительном выходе — несущий

Отсечка идёт **первой**, потому что держится без чьего-либо содействия; снятие сессии
следует, потому что оно и превращает вечный отказ в выход. Из этого порядка растут оба
открытых остатка глагола:

- причина снятия пишется `logout`, потому что значения «выведен распорядителем» в закрытом
  словаре нет — [[KAC/issue-334-kaname]];
- событие кладётся транзакцией отсечки, то есть до снятия, и числа снятого не несёт —
  [[KAC/issue-340-kaname]].

Ноль снятых записей — законный исход, а не отказ: у человека могло не быть ни одной живой
сессии.

## See also

[[rpc/iam-internal-iam-service]] · [[resources/iam-human-session]] ·
[[resources/iam-audit-outbox]] · [[packages/kaname-repo-pg]]

#packages #kacho-iam #internal #usecase #go
