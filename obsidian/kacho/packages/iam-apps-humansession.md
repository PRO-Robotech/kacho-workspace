---
title: iam humansession use-cases
repo: kacho-iam
layer: usecase
category: packages
path: internal/apps/kaname/api/humansession
related_tickets:
  - "[[../KAC/issue-275-kaname]]"
  - "[[../KAC/issue-1281-kaname]]"
  - "[[../KAC/issue-1269]]"
tags:
  - packages
  - kacho-iam
  - internal
  - usecase
  - go
status: stable
verified_against: "kaname origin/main: `git ls-tree -r --name-only origin/main internal/apps/kaname/api/humansession/` прочитан (21 прод-файл, по файлу на глагол полосы); `sf_remove.go` прочитан построчно (строки 36/123/152); прочие use-case построчно не пересматривались"
---

# `internal/apps/kaname/api/humansession/` (kaname)

Слой use-case полосы формы: глаголы сессии человека, за которыми ретранслирует край. Это **ярус
use-case** (по файлу на глагол) — HTTP-контракт путей живёт в [[../rpc/iam-login-lane]], запись
в базе — в [[../resources/iam-human-session]] и [[../resources/iam-user-login-methods]]; здесь не
дублируются, а называются ссылкой.

## Глаголы (файл = предмет)

| Группа | Файлы |
|---|---|
| сессия | `login.go` · `logout.go` · `change_password.go` · `issue.go` · `resolve.go` |
| восстановление (Ф5) | `recovery_request.go` · `recovery_complete.go` |
| второй фактор (Ф12) | `second_factor.go` · `sf_enroll.go` (заведение + подтверждение) · `sf_present.go` · `sf_remove.go` · `sf_status.go` · `sf_backup_codes.go` · `step_up.go` |
| опоры | `dispatch.go` · `iface.go` · `form_token.go` · `password_rule.go` · `rate.go` · `refusals.go` · `observer.go` |

Заведение и подтверждение фактора живут одним файлом: `NewEnrollSecondFactorUseCase` и
`NewConfirmSecondFactorUseCase` — оба в `sf_enroll.go` (отдельного `sf_confirm.go` нет).

## `sf_remove.go` — снятие фактора (предмет [[../KAC/issue-275-kaname]])

`RemoveSecondFactorUseCase.Execute` снимает фактор, кроет **прочие** сессии человека
(`EndOtherSessions`, причина `second-factor-removed`), пере-представляет текущую сессию на новом
уровне и отдаёт `BackupCodesRemaining = 0` **всегда** (Р4 ред. 10): набор запасных кодов уходит
вместе с фактором, а остаток потреблённого набора наружу не выходит.

## See also

[[../rpc/iam-login-lane]] · [[../resources/iam-human-session]] ·
[[../resources/iam-user-login-methods]] · [[../KAC/issue-275-kaname]]

#packages #kacho-iam #internal #usecase #go
