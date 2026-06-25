---
title: "flat-authz verb-bearing-complete (Design B) — Stage 5: deploy configmap regen + geo pull-published"
ticket_id: rbac-flat-verb-bearing-deploy
status: test
type: feat
repos:
  - kacho-deploy
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-nlb
  - kacho-api-gateway
prs:
  - https://github.com/PRO-Robotech/kacho-deploy/pull/128
opened: 2026-06-25
tags:
  - kac
  - kacho-deploy
  - feat
  - authz
  - cross-service
---

# flat-authz verb-bearing-complete — Stage 5 (deploy + geo-unify)

Финальная стадия Design-B verb-bearing стека. Anchor: [[rbac-flat-verb-bearing-complete-proto]] (proto#88) · [[rbac-explicit-model-2026]].

## Часть A — OpenFGA configmap regen (flat Design-B)

`helm/umbrella/charts/openfga-bootstrap/templates/openfga-model-stub-configmap.yaml`
регенерирован из канонического `kacho-proto/.../iam/v1/fga_model.fga`
(ветка `rbac-flat-verb-bearing-proto`, proto#88) через `make openfga-model-json`.

Подтверждено на сгенерированном `model.json`:
- **flat**: 0 cascade (0 `tupleToUserset` `X from Y`);
- **poison-fixed**: viewer/editor directly-assignable на `iam_user`/`iam_role`/`iam_condition`;
- **0 union viewer⊇v_***: ни один tier не union-ит `v_*`;
- **v_* pure-direct**: 115 `v_*` relations на 23 типах = `{"this":{}}`;
- **is_valid: true** (`openfga model validate`).

CI `REF_PROTO` → `rbac-flat-verb-bearing-proto` — coverage-gate и configmap читают
один артефакт.

## Часть B — geo-unify (pull published, не build :dev)

geo теперь **внешний OSS**, потребляется как published-зависимость. umbrella
newman-e2e больше НЕ строит `kacho-geo:dev` из runtime-сломанного OSS-source
(geo-read 503 → каскад в compute). Вместо — pull/kind-load known-good
`docker.io/prorobotech/kacho-geo:main-84d9d68f` (билд с fe3455) + `helm --set
kacho-geo.image`. `KACHO_GEO_IMAGE` — единый источник тега (pull + kind-load +
--set в lockstep). geo в wait-for-core (compute→geo на request-path) и log-dump;
geo **НЕ** в openfga-bootstrap restart-set (не держит FGA store/model id —
делегирует Check в iam). `values.dev.yaml` geo.image → published tag.

Pull-подход раскатан в per-repo `newman-e2e.yml`: iam/vpc/compute/nlb/api-gateway.

**Supersede-ит** build-:dev (geo#3): закрыты deploy#127, iam#244, vpc#8,
compute#63, nlb#40, gw#98 (как superseded).

## Затронутые сущности vault
- [[compute-to-geo-zone-validate]] — geo как published-зависимость umbrella (не build-from-source).
- [[geo-to-iam-check]] — geo не держит FGA store/model id; Check делегируется в iam.
- [[rbac-flat-verb-bearing-complete-proto]] — configmap regen из proto#88 fga_model.

## Кросс-репо порядок
proto#88 → iam#245 / vpc#9 / compute#64 / nlb#41 → api-gateway#99 → **deploy#128
(этот, NOT merged)**. Deploy newman пиннит verb-bearing feature-ветки для
coordinated e2e; revert к main после merge каждого. **Merge координируется заказчиком.**

## Связанные
- anchor: [[rbac-flat-verb-bearing-complete-proto]] · [[rbac-explicit-model-2026]]

#kac #kacho-deploy #feat #authz #cross-service
