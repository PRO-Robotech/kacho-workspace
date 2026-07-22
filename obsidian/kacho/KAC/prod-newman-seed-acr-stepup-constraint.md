---
tags: [kac/finding, domain/iam, area/authz, area/testing]
status: active
---

# Prod-newman seed: step-up/acr gate blocks non-interactive USER tokens

**Дата:** 2026-07-22 · **Источник:** GitHub `PRO-Robotech/kacho#60`/`#59` · эмпирически подтверждено на live-стенде (helm rev 13, `production-strict`).

## Находка (cross-cutting, важнее чем #60 created_by)

Production-mode e2e для **user-субъектных resource-suite'ов** (vpc/compute/nlb authz-deny matrix) **невозможен non-interactive** из-за step-up-гейта:

- Permission-catalog штампует `required_acr_min="2"` на **372 RPC** — практически все resource Get/List/Create/Update/Delete.
- Gateway step-up-гейт (`gateway/internal/middleware/stepup_gate.go`) освобождает от acr-floor **только** `service_account`-принципал (hardened O-1 mechanism-lock: `user` НИКОГДА не exempt).
- **Live-доказательство:** `MintBootstrapToken` (#58) отдаёт RS256 с `kacho_acr=""` (rank 0) + `principal_type=service_account`, и он проходит `GET /vpc/v1/networks` (acr>=2) → **200** ЧИСТО через SA-exemption. USER-токен (client_credentials ⇒ acr=0, non-exempt) получил бы **401 step-up**.

**Следствие:** ни `MintUserToken` RPC, ни root-USER-caller, ни «SA issues user-token» не проведут user-субъект через acr>=2 resource-RPC. Caller acr>=2-RPC обязан быть `service_account` (acr-exempt) либо нести реальный MFA-acr (недостижимо non-interactive).

## Что сделано (#60)

`UserTokenService.Issue`: acr-exempt #58 bootstrap-SA caller теперь пишет `created_by = target user (self)` (SA-id не в `users(id)` → раньше async FK code-9) + sync `created_by`-валидация (DEFECT-b: non-usr → InvalidArgument; unknown usr → FailedPrecondition — не opaque async code-9). Commit `05a2291` (`kacho@redesign/integration`), deployed. Снимает ЛИТЕРАЛЬНЫЙ FK-блокер, но не step-up.

## Опции для green resource-suite'ов (нужно решение owner)

1. **SA-субъекты** для resource-матрицы (acr-exempt — единственный non-interactive путь): нужен тот же created_by-relax на `SAKeyService.Issue` + valid-user `created_by` (у SA-target нет self-user → seeded `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` admin-user) + порт user-кейсов на SA.
2. Пересмотреть дефолт `required_acr_min=2` на routine read/list resource-RPC (сейчас требует MFA на каждый List).

IAM-only suite'ы и SA-субъектные кейсы уже работоспособны; user-субъектная resource-матрица требует опции 1 или 2.

## Связанные

- [[iam-internal-bootstrap-token-service]] (#58 non-interactive SA mint)
- [[api-gateway-to-iam-acr-floor]] (acr-floor edge)
- `docs/specs/sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md` (#58, D-1 SA-vs-User acr-обоснование)
- `docs/specs/sub-phase-IAM-USER-TOKEN-MINT-acceptance.md` (WITHDRAWN — root-USER/MintUserToken отвергнуты step-up-гейтом)
