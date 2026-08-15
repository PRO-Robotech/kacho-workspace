---
title: "Prod-newman seed: step-up/acr gate blocks non-interactive USER tokens"
tags: [kac, kac/finding, domain/iam, area/authz, area/testing]
status: done
category: kac
---

# Prod-newman seed: step-up/acr gate blocks non-interactive USER tokens

**Дата:** 2026-07-22 · **Источник:** GitHub `PRO-Robotech/kacho#60`/`#59` · эмпирически подтверждено на live-стенде (helm rev 13, `production-strict`).

> [!important] Блокер закрыт — взята опция 2. Число «372 RPC» относится к прошлому (перемерено 2026-08-08)
> Записка называла блокером «`required_acr_min="2"` на **372 RPC** — практически все resource
> Get/List/Create/Update/Delete» и просила решение владельца из двух опций. **Опция 2 принята и
> исполнена** — [[KAC/sec-acr-stepup-refinement]] (`status: done`), приёмка
> `docs/specs/sub-phase-SEC-acr-stepup-refinement-acceptance.md`: step-up остаётся только на
> posture-changing операциях (RFC 9470 / NIST 800-63B), а не как дефолт.
>
> Дерево `project/kacho` @ `6b1293713`, обе встроенные копии каталога
> (`gateway/internal/middleware/embed/permission_catalog.json` и
> `services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json`) дают одно и то же:
> записей **295**, из них `required_acr_min="2"` — **27**, `"1"` — **209**, пусто (exempt) — **59**.
>
> Зеркальный контроль, ради которого он и нужен: `Get*`/`List*`-записей в каталоге **123**, и
> `required_acr_min="2"` среди них — **0** (97 на `"1"`, 26 exempt). То есть исчезло именно то, из
> чего складывался блокер: рутинное чтение больше не требует интерактивной MFA. Оставшиеся 27 —
> ровно posture-changing поверхность: выдача и отзыв учётных данных (`UserTokenService`/`SAKeyService`),
> изменение выдач (`AccessBindingService`, `Set/UpdateAccessBindings`), состав групп, роли,
> `InternalClusterService.Grant/RevokeAdmin`, `Account/Project.Delete`, блокировка/приглашение
> пользователя.
>
> Предикат (единица счёта — запись каталога, не строка файла): разобрать JSON и посчитать
> `required_acr_min` по значениям, отдельно — по методам, чьё имя начинается с `Get`/`List`.
> Грубый греп по `required_acr_min` этого не различает и на обеих сторонах даёт одно число.
>
> **Что остаётся открытым и почему это НЕ предмет этой записки.** Живой user-субъектный
> production-newman по-прежнему заблокирован — но seed-гэпами RS256, а не acr-полом: они
> перечислены в [[KAC/sec-acr-stepup-refinement]] §«Блокер production-newman (Phase C, НЕ acr)»
> и принадлежат `#59`/`#60`. Здесь они не пересказываются, чтобы два места об одном предмете не
> разошлись; смена ведра статуса означает «предмет ЭТОЙ записки закрыт», а не «suite зелёный».

## Находка на 2026-07-22 (cross-cutting, важнее чем #60 created_by)

Production-mode e2e для **user-субъектных resource-suite'ов** (vpc/compute/nlb authz-deny matrix) **невозможен non-interactive** из-за step-up-гейта:

- Permission-catalog штампует `required_acr_min="2"` на **372 RPC** — практически все resource Get/List/Create/Update/Delete.
- Gateway step-up-гейт (`gateway/internal/middleware/stepup_gate.go`) освобождает от acr-floor **только** `service_account`-принципал (hardened O-1 mechanism-lock: `user` НИКОГДА не exempt).
- **Live-доказательство:** `MintBootstrapToken` (#58) отдаёт RS256 с `kacho_acr=""` (rank 0) + `principal_type=service_account`, и он проходит `GET /vpc/v1/networks` (acr>=2) → **200** ЧИСТО через SA-exemption. USER-токен (client_credentials ⇒ acr=0, non-exempt) получил бы **401 step-up**.

**Следствие:** ни `MintUserToken` RPC, ни root-USER-caller, ни «SA issues user-token» не проведут user-субъект через acr>=2 resource-RPC. Caller acr>=2-RPC обязан быть `service_account` (acr-exempt) либо нести реальный MFA-acr (недостижимо non-interactive).

## Что сделано (#60)

`UserTokenService.Issue`: acr-exempt #58 bootstrap-SA caller теперь пишет `created_by = target user (self)` (SA-id не в `users(id)` → раньше async FK code-9) + sync `created_by`-валидация (DEFECT-b: non-usr → InvalidArgument; unknown usr → FailedPrecondition — не opaque async code-9). Commit `05a2291` (`kacho@redesign/integration`), deployed. Снимает ЛИТЕРАЛЬНЫЙ FK-блокер, но не step-up.

## Опции для green resource-suite'ов — решение принято, взята опция 2

1. **SA-субъекты** для resource-матрицы (acr-exempt — единственный non-interactive путь): нужен тот же created_by-relax на `SAKeyService.Issue` + valid-user `created_by` (у SA-target нет self-user → seeded `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` admin-user) + порт user-кейсов на SA. **НЕ выбрана.**
2. Пересмотреть дефолт `required_acr_min=2` на routine read/list resource-RPC. ✅ **Выбрана и исполнена** — см. врезку выше и [[KAC/sec-acr-stepup-refinement]]. Рутинное чтение MFA больше не требует: `Get*`/`List*`-записей каталога **123**, с `acr=2` среди них — **0**.

Опция 1 сохранена не как незакрытый выбор, а потому что её механика (`created_by`-relax,
seeded admin-user) переиспользуется в seed'е и на неё ссылаются `#59`/`#60`.

## Связанные

- [[iam-internal-bootstrap-token-service]] (#58 non-interactive SA mint)
- [[api-gateway-to-iam-acr-floor]] (acr-floor edge)
- `docs/specs/sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md` (#58, D-1 SA-vs-User acr-обоснование)
- `docs/specs/sub-phase-IAM-USER-TOKEN-MINT-acceptance.md` (WITHDRAWN — root-USER/MintUserToken отвергнуты step-up-гейтом)
