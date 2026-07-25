# NLB-1 grind notes (carve APPROVED × 4 — замечания ревьюера к учёту)

Carve `sub-phase-NLB-1{a,b,c,d}-*-acceptance.md` = ✅ APPROVED × 4. Партиция 58/58 verified
(1b=47: `01–33,35,43–55`; 1c=11: `34,36–42,56,57,58`; 1a/1d — net-new DoD-сценарии).

## Порядок grind (жёсткие зависимости)
`1a → 1b → 1c → 1d`. Все ветвятся **off `redesign/integration`** (не off базы — там iam authzmap + vpc Subnet-proto + nlb vpc-client уже правильные).
- **1a ПЕРЕД 1b**: иначе 1b пишется на legacy `lb_*`, rename в 1a переконфликтит новый код 1b.
- **1c ПОСЛЕ 1b**: удаление `HealthCheck.name` в 1c безопасно только после удаления `attach_target_group.go` (pivot-removal) в 1b.
- registry REG-1 мёржится в integration независимо; при grind 1a FGA-хунки дизъюнктны с registry (lb_→nlb_ vs registry_→namespace_).

## 4 non-blocking замечания ревьюера — ОБЯЗАТЕЛЬНО в мандаты
1. **[SEAM → в мандат 1b]** TG name-UNIQUE (`NLB-1-49`) **owned by 1b**, но родитель делегировал TG-аналог в 1c, а 1c его не подхватил.
   → **1b ассертит LB+Listener+TG name-UNIQUE в собственном кейсе** (не «провалиться в щель» между PR). TG Create-able уже в 1b.
2. **[EVOLUTION → 1a done так]** 1b обновит AS-IS-form newman/authz-фикстуры 1a (Create с `type`+`placement_type` → `placement`);
   1c обновит AS-IS HealthCheck-фикстуры 1b (`name` → oneof без name). Межфазовая эволюция, НЕ регрессия — упомянуть в 1b/1c PR.
3. **[UX-minor → в мандат 1b]** FK RESTRICT `Listener.targetGroupId→TargetGroup` создаётся в 1b; friendly blocker-list precheck — 1c.
   В окне «1b merged, 1c нет» TG.Delete референсимой TG → FK 23503 → **1b обязан мапить в фикс. тон (не leak pgx)**, даже до enum-precheck 1c.
4. **[COSMETIC → в мандат 1b]** Cross-ref `NLB-1-11-зона` в 1b-доке (~строка 196) неточен — zone/region-mismatch для INTERNAL_ZONAL живёт в F5 (`NLB-1-32/33`), не в `NLB-1-11` (regionId peer-validate). Поправить формулировку на «F5 / NLB-1-32/33».

## Дефолты родителя (Q1–Q4) — распределение
- Q1 hard-rename `lb_*`→`nlb_*` → **1a**.
- Q2 permission-string/package `→nlb.*`/`nlb.v1` → **NLB-4** (вне scope всех 4 первых слайсов).
- Q3 inline `targetGroup` config-only → **1c** (`57/58`).
- Q4 `securityGroupIds` revival → **1b** (`51/52`).

## Ключевые carve-решения (для реализатора)
- **NLB-1-35 (TG.port BVA) → 1b**: bare-поле `port` + required-BVA — co-req `resolvedBackendPort°` (родитель кладёт resolvedBackendPort° в 1b).
  Полная port-семантика (LIVE-mutable re-echo `56`, `effectivePort°`-inheritance `39`) + HC-redesign → 1c.
- **NLB-1-57/58 → 1c**: inline `targetGroup` использует redesigned HealthCheck (без `name`, `tcp:{}` oneof) → требует 1c-формы.
- Миграции: только новые; `0013` (status-trigger) переписывается новой (ban #5). VIP-на-LB **остаётся** — реверса на Listener нет; мёртвый listener-level `listeners_region_vip_uniq` (ошибочно возвращён `0021`) снят `0025`.
