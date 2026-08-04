---
title: nlb :move cross-tenant deny — FIXTURE bug (NOT a bypass) + design-note
category: kac
tags: [kacho-nlb, kac, fix, architecture]
ticket_id: TBD
status: done
type: fix
repos: [kacho-nlb]
prs: []
opened: 2026-07-23
---

# nlb `:move` cross-tenant deny — RED-flagged → adversarially RETRACTED

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Прежний статус — `in-progress`; он пережил свой предмет и держался на списке
> пунктов, часть которых больше не существует как единица работы.
>
> **done.** Исход записки — **отозванная находка**: враждебная проверка показала, что обхода между тенантами нет, а красный кейс дала фикстура. Ценность именно в хронологии отказа принять вывод ревьюера на слово. Работы не осталось.

> [!success] Итог: NO product cross-tenant bypass. Fixture-bug (test-only) + design-note.
> Adversarial-verification (HOLD+wire-probe координатора + self-refute пира) отсекла
> false-positive. Пример работающей refute-дисциплины.

## Хронология (важна как процесс)

1. Пир RED-flag: «`:move` dst-guard проверяет неправильную relation (tier editor vs
   enforcement v_create) → cross-tenant BOLA (CWE-863)».
2. Координатор: **HOLD фикса** (два root-cause пира расходились; мои прогонные данные
   показали precond=200 → subject РЕАЛЬНО имеет доступ к «cross»). Запустил wire-probe.
3. Пир self-refute: `prodseed_matrix.py:240-241` — `tok_editorA` = editor на ОБОИХ
   projA1+projA2 (same account acctA) → «cross» = same-account, грант законен.
4. **Wire-подтверждение (координатор, iam Check HIGHER_CONSISTENCY):** move-actor
   `service_account:svafeb31…` → `editor@project:cross`=**allowed**, `v_update@cross`=
   **allowed** (direct relations `[v_get,v_list,v_update,editor]`; `v_create`=deny). →
   `authorizeDestination(editor, cross)`=allowed → move 200 **ЗАКОННО**. Не bypass.

## Реальный дефект — FIXTURE (test-only, ban #13-clean)

Move-DENY кейсы (`AZD-{NLB,TGR}-MV-SCOPE-DST-DENIED`) используют актора, легитимно
гранченного editor на same-account «cross» проект → не могут протестировать genuine
cross-TENANT denial (premise ложна vs фактический fixture). Historical intent:
`prodseed_matrix.py:249-250` `tok_editorCrossA2` = «editor cross A2 ONLY», но
`jwtProjectEditorA` позже расширили до edit@A2, сломав premise.

**Фикс:** ретаргет move-deny dst на genuinely-foreign — **cross-ACCOUNT** проект
(acctB `projB1`), где актор не имеет гранта → продукт КОРРЕКТНО denies (нет
binding/cascade в acctB) → real cross-tenant-move deny RED→GREEN. Fixtures/newman only.

## Design-observation (НЕ bypass, follow-up)

`authorizeDestination` гейтит **`editor`-tier**; create-in гейтит **`v_create`-verb**
(flat Contract-A: tier ≠ verb-implication). svafeb31 имеет editor+v_update но НЕ
v_create → **может move-in, но не create-in** в тот же проект. Move-in семантически ≈
create-in (ресурс появляется в dst). Вопрос: должен ли move-in гейтить v_create-эквивалент
для консистентности? Intra-account granularity (cross-account граница держится). Low-sev
design-decision → зафиксировать в `docs/architecture/nlb` или tracked-note, не emergency.
(Побочно: SA `editor` без `v_create` даже на HOME — понять, намеренно ли role-set SA.)

## Затронутые сущности vault
- [[in-service-gateway-authz-scope-parity]] · move: [[resources/nlb-load-balancer]] / [[resources/nlb-target-group]]

## Статус
- [x] RED-flag → adversarial refute → **wire-confirmed: no bypass** (fixture-bug)
- [ ] Fixture-fix: ретаргет move-deny на cross-account projB1 (RED→GREEN, test-only)
- [ ] deploy/rerun nlb → 10 fixture-premise clear (17→7)
- [ ] design-note (editor vs v_create для move-in) в docs/architecture/nlb
- [ ] 7 logic/state (effectivePort int64-string, target-state, wrong-region, cross-region-400) — отдельный триаж

#kacho-nlb #kac #fix #architecture
