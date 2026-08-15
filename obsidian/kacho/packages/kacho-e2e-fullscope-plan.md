---
title: e2e-newman fullscope — мастер-план добивания (все 4 сервиса)
category: packages
repo: kacho
layer: ci
status: in-progress
tags: [packages, architecture, cross-service, ci]
---

# e2e-newman fullscope: мастер-план (2026-07-16, multiagent triage)

Полный e2e-гейт (iam+vpc+compute+nlb) — **НЕ сотни продуктовых багов**, а несколько
корней. Baseline ~850 failed-assert **ложно занижен** (poll-op-коллизия пропускала ~2500
шагов → ложные «0 failed»). **Истинный residual после Phase A ~2455** (poll-op разблокировал
скрытые шаги → латентные корни всплыли). Источник: workflow `wf_6d82758e-5ec`.

## Систекмные корни (Phase A — ПРИМЕНЕНО, commit f3cbfbd)

- **A1 auth-missing-Bearer** (compute 96, nlb 648): запросы с `auth=None` шли анонимно →
  IAM authn-gate 401 fail-closed (**продукт корректен**). Fix: дефолтный Bearer `jwtBootstrap`
  в `gen.py` PRE_GLOBAL (compute), fallback на `jwtBootstrap` в nlb (`jwtProjectEditorA`||`jwtBootstrap`).
  nlb 648→330 (остаток = authz-специфичные тесты без засеянных subject-JWT).
- **A3 poll-op name-collision** (vpc/compute): все poll-шаги имени `poll-op` +
  `setNextRequest(pm.info.requestName)` → newman резолвит в ПОСЛЕДНИЙ poll-op (last-wins) →
  прыжок через кейсы, пропуск setup → ~2500 шагов не исполнялось. Fix: уникальное имя
  `poll-op-<N>` (ретраит СЕБЯ) + бюджет 6/8→20. nlb уже был корректен (`poll-op-{_poll_seq}`).

## Доминирующий продуктовый корень → РЕШЕНИЕ владельца: ПРОДУКТ

- **owner-tuple lag** (~тысячи): fgaproxy (kacho-vpc/compute/storage→iam RegisterResource
  via transactional-outbox) регистрирует owner-tuple ПОЗЖЕ, чем Create-Operation помечается
  `done` → создатель получает **403 «no direct relations granted» на немедленный
  Update/Delete СВОЕГО ресурса**. Бьёт ВСЕ CRUD-lifecycle наборы (vpc subnet/SG/network/
  route-table/address, compute instance/disk/image/snapshot). Тот же корень у iam
  AccessBinding.Create (rank 4). **Решение владельца (2026-07-16): Create.op-done БЛОКИРУЕТ
  до tuple-confirm (read-after-register)** — гарантия «создал → могу сразу действовать».
  Продукт-фикс в каждом сервисе (iam/vpc/compute/storage), TDD. Проверить register-drainer
  поднят на kind. См. [[../edges/storage-to-iam-fgaproxy]].

## Продолжение (Phase B/C — АВТОНОМНО, решение владельца)

- **Phase B (test-fixture/deploy, без product-gate):** compute `existingProjectId` (+existingSubnet/
  Sg/Network) hardcoded, не засеян → patch-env.py переписать на реальные seeded-id (rank 15);
  nlb subject-JWT в authz-fixtures/setup.sh + patch-env (rank 1 полный, снимет остаток 330);
  iam `_internal_url_override` на оставшиеся :check-пробы (rank 5); list-filter-d subset-viewer
  fixture в setup.sh (rank 7); iam external-endpoint api.kacho.local:443 (rank 6, decision:
  provision-or-pass).
- **Phase C (продукт):** owner-tuple op-gating (выше); DeleteAccessBinding LRO не доходит до
  done (rank 8); read-authz hide-existence v_list-vs-v_get (rank 11).
- **Phase D (findings + decisions):** **cross-account List-leak** — AccountAdminB листит
  Networks/SecurityGroups чужого accountA (200+rows вместо 403/empty), детерминирован —
  **реальный security-баг** (listauthz не scope-фильтрует по caller vs param projectId) ЛИБО
  seed over-grant → GitHub Issue + регрессия; subnet create-fail без placement_type (rank 14).

## Открытые продуктовые вопросы (владельцу)
anon Operation 401-vs-404-hide; sec-c-fga-proxy Internal RPC drop-from-gate-or-expose-:18081;
SA project-anchor role assignability. Owner-tuple — уже решён (блокировать op-done).

Связано: [[kacho-newman-gate]], [[kacho-ci-runners]], [[../edges/storage-to-iam-fgaproxy]].

#packages #architecture #cross-service #ci
