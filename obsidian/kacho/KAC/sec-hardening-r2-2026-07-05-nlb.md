# sec-hardening-r2-2026-07-05 (kacho-nlb): 2-й аудит — contract-safe medium/low → zero

**Status**: test
**Type**: fix / security-hardening (batch)
**Repos**: kacho-nlb
**Branch**: `sec-hardening-r2-2026-07-05`
**YT**: — (KAC-тикет слинковать вручную)

## Что и зачем

2-й аудит kacho-nlb: 8 находок (0 critical/high, 3 medium, 5 low), все contract-safe.
Закрыты все — tests-first (RED→GREEN), контракты (proto/REST/wire/DB-схема публично)
заморожены. Изменения — internal Go/SQL + новые тесты (без новых миграций: гварды на
существующих таблицах).

## Находки и фиксы

1. **[M] Move↔Attach TOCTOU (cross-project attach)** — `MoveProject` был безусловным
   `UPDATE project_id`; конкурентный `Attach` мог связать LB проекта B с TG проекта A.
   Фикс: `MoveProject` теперь `UPDATE ... WHERE NOT EXISTS(attached_target_groups)` →
   0 rows при наличии attach → FailedPrecondition (различаем NotFound vs FP через
   follow-up EXISTS). Симметрично `AttachedTargetGroups.Attach` переписан на
   `INSERT ... SELECT` с JOIN, re-check'ающий `project_id`/`region_id` LB↔TG на строках
   в момент вставки → race закрыт с обеих сторон (ban #10).
2. **[M/L] Per-group target cap не кумулятивный** — `AddTargets` проверял только per-call
   `≤100`; серия вызовов раздувала группу без границ. Фикс: в writer-tx `SELECT ... FOR
   UPDATE` на parent target_groups (сериализует конкурентные AddTargets) + `count(*)` →
   `current+len > MaxTargetsPerGroup` → FailedPrecondition. `ListTargets` получил
   `LIMIT MaxTargetsPerGroup` (safety-net для Get, CWE-770).
3. **[M] Дублированный mapDomainErr/stripSentinel ×3** — вынесен единый
   `internal/apps/kacho/api/shared/errmap.go` (`MapDomainErr`/`StripSentinel`); listener/
   loadbalancer/targetgroup делегируют. Устранена дивергенция (loadbalancer пропускал
   codes.Unknown → leak; теперь единый guard `code != Unknown`).
4. **[L] deletion_protection не атомарный** — worker делал безусловный DELETE. Добавлен
   `DeleteIfUnprotected` (`DELETE ... WHERE deletion_protection=false`, 0 rows → FP/NotFound);
   delete-worker использует его. Compensation-rollback в Create оставляет безусловный `Delete`.
5. **[L] 23505 всегда «name already exists»** — `mapPgErr` теперь ветвится по
   `ConstraintName`: `listeners_lb_port_proto_uniq` → port/protocol, `listeners_region_vip_uniq`
   → VIP-in-region, `targets_*_uniq` → identity; остальные → name.
6. **[L] Мёртвый Logger port** в loadbalancer/ports.go удалён (никто не потреблял).
7. **[L] Flaky TTL-тест** (`authzfilter`) — в `FGAFilter` инъектирован `now func() time.Time`;
   тест двигает часы детерминированно вместо `time.Sleep(40ms)`.

## Затронутые сущности vault

- [[../resources/nlb-load-balancer]] — Move guard (NOT EXISTS attach), DeleteIfUnprotected
- [[../resources/nlb-target-group]] — cumulative cap на AddTargets + ListTargets LIMIT
- [[../resources/nlb-target]] — cap enforcement
- [[../rpc/nlb-load-balancer-service]] — Move/Delete: FailedPrecondition по DB-гварду (contract same)

## Acceptance / DoD

- [x] RED→GREEN: integration-тесты (testcontainers) для находок 1/2/4/5 (RED подтверждён на
      reverted-гвардах: cap-тест FAIL на require.Error)
- [x] go build ./... + go vet ./... зелёные
- [x] touched-pkg unit-тесты (-race) зелёные (api/*, authzfilter)
- [ ] pg integration -race GREEN (в прогоне; testcontainers)
- [ ] PR merged в main

#kac #fix #security
