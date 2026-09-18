---
title: "kaname#275: RemoveSecondFactor всегда отдаёт backupCodesRemaining=0"
aliases:
  - issue-275-kaname
ticket_id: 275
category: kac
status: done
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/humansession
prs:
  - PRO-Robotech/kaname#294
issue_url: https://github.com/PRO-Robotech/kaname/issues/275
opened: 2026-09-18
closed: 2026-09-19
tags:
  - kac
  - kacho-iam
  - iam
  - fix
verified_against: "kaname origin/main `internal/apps/kaname/api/humansession/sf_remove.go` прочитан (строки 36 и 152: `BackupCodesRemaining` всегда 0, Р4 ред.10, kaname#275; остаток потреблённого набора наружу не выходит). PR #294, squash-sha `8294f83a` (`[#275] волна second-factor: backupCodesRemaining=0 + authz ResetSecondFactor (#294)`) и предикат `TestF12_28_29…` PASS — со слов полосы, лог прогона не пересматривался"
---

# kaname#275: RemoveSecondFactor всегда отдаёт backupCodesRemaining=0

**Состояние**: done — влит волной 2, PR kaname#294, squash-sha в `main` `8294f83a`.

**PRs**: PRO-Robotech/kaname#294
**Issue**: https://github.com/PRO-Robotech/kaname/issues/275

## Что и зачем

`RemoveSecondFactor` (`POST /iam/v1/auth/second-factor/remove`, use-case `sf_remove.go`) снимает
заведённый фактор. Поле ответа `backupCodesRemaining` теперь **всегда `0`** — и при снятии
запасным кодом тоже (Р4 ред. 10): снятие уносит и сам фактор, и его набор запасных кодов, поэтому
остатка не остаётся, а остаток частично потреблённого набора наружу и не выходил бы (он выдал бы
число ещё годных кодов постороннему с одним кодом). Прочие сессии человека снимаются той же
транзакцией отметкой `ended_reason = second-factor-removed`
(`EndOtherSessions`, `domain.RevokeReasonSecondFactorRemoved`).

Один squash-коммит `8294f83a` (PR #294) несёт **и** этот фикс, **и** authz-часть
[[KAC/issue-254-kaname]] (governingRPCs у `ResetSecondFactor`) — волна second-factor.

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — путь `/second-factor/remove`, поле `backupCodesRemaining`.
- [[resources/iam-user-login-methods]] — материал фактора и его снятие.
- [[resources/iam-human-session]] — отметка `second-factor-removed` на прочих сессиях.

## DoD

- [x] `backupCodesRemaining` = 0 всегда (в т.ч. снятие запасным кодом)
- [x] прочие сессии сняты причиной `second-factor-removed`
- [x] предикат прогнан (`TestF12_28_29…` PASS — со слов полосы)

## Связанные задачи

- kaname#297 — контракт запасных кодов несогласован (открыт по дороге; сведение семантики
  `backupCodesRemaining` по всем путям семейства).

#kac #kacho-iam #iam #fix
