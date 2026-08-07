# Redesign 2026 — integration status (первые под-фазы)

> [!note] Таблица ниже — ИСТОРИЧЕСКАЯ ЗАПИСЬ сведения, а не инвентарь живых веток
> Замер 2026-08-07. Из **восьми** имён `redesign/*`, названных в этом файле, в дереве
> (локально + origin) резолвится **одно** — `redesign/integration`, и та отстала от
> фактического ствола на **91** коммит. Остальные семь (`storage-1`, `iam-1`, `vpc-1`,
> `compute-1`, `registry-1`, `registry-1-namespace-archived`, `nlb-1a`) удалены после
> сведения — это штатный исход по `git-youtrack.md` §CI («смёржена+удалена»), а не потеря
> работы: их содержимое в стволе. Плюс в дереве живёт `redesign/iam-condition-convention`,
> которую этот файл не называет.
>
> Предикат: `git rev-parse --verify --quiet <branch>` и `origin/<branch>` по каждому имени;
> перечень живых — `git branch -a --list '*redesign/*'`.
>
> **Читать этот файл как список того, куда идти работать, нельзя.** Фактический ствол —
> ветка `work` (на 2026-08-07 — `1653387b`, зелёный e2e run 31054749944), и снимок волны
> 08-06 `938e2909` поверх неё. Столбец «Ветка» сохранён ради прослеживаемости коммитов,
> названных ниже, а не как адрес.

Ground-truth снимок сведения feature-веток редизайна. База всех веток —
`phase0-governance` @ `60e2827` (B1 ref-naming law + B3 id-prefix router/hyphen-canon).
Сама ветка `phase0-governance` в дереве тоже не резолвится — но её база `60e2827`
является предком ствола, поэтому утверждение о происхождении остаётся верным.
Монорепо `project/kacho` (single go.mod; proto+Go — один compile-unit). Все коммиты —
`pointpu@prorobotech.ru` (pre-commit hook enforce).

## Инвентарь первых под-фаз

| Сервис | Ветка | Первая под-фаза | Статус |
|---|---|---|---|
| geo | (folded в base) | GEO-1 Region/Zone | ✅ green |
| storage | `redesign/storage-1` | STOR-1 Volume/Image/Snapshot | ✅ green |
| iam | `redesign/iam-1` | IAM-1 tenancy+authz (F1-F11) | ✅ green |
| vpc | `redesign/vpc-1` | VPC-1 Network/Subnet/SG/RT/GW/NIC/Address | ✅ green |
| compute | `redesign/compute-1` | COMP-1 Instance core + MachineType | ✅ green |
| registry | `redesign/registry-1` | REG-1 Registry+Repository (id-model, **Namespace-rename ОТКАЧЕН** owner-decision) | ✅ green (re-grind) |
| nlb | `redesign/nlb-1a` | NLB-1a FGA rename `lb_*`→`nlb_*` | ✅ green (1b-1d pending) |

**Registry — corrected id-модель** (owner-decision 2026-07-20, core rule #15): `Registry` (не Namespace), pull `$domain/$registryId/$repo:$tag`, id immutable, БЕЗ globalSlug/`:rename`; F4 region + F5 defaultRepositoryVisibility + F7 lifecycle сохранены. Namespace-impl архивирован `redesign/registry-1-namespace-archived`. Commits 89685f5/33d1637/6c8ee83/a282c90.

**Hardening round** (adversarial-review 6 CONFIRMED, все green TDD, ждут re-merge): storage `082265c` (images CHECK at-most-one), vpc `8d789f3`/`4cc2e25`/`7fb2f4a` (CIDR pagination/supernet/primary-anchor), iam `deb47e1`/`ff453f4` (target.resources[] least-priv over-grant + account-role→nested-project).

## Cross-cutting deferred (не блокирует под-фазы, но зафиксировать)
- **`google.rpc.ErrorInfo` reason-token plumbing отсутствует во ВСЕЙ базе** (`serviceerr` мапит sentinel→code; токена нет нигде). api-conventions.md предписывает reason-token (`INVALID_RESOURCE_ID`/`PEER_RESOURCE_MISSING`/…) в `details` — но by-lane **code+contract-text split реализован**, отсутствует только машинно-читаемый токен. Pre-existing (не введён редизайном), cross-cutting (все сервисы). → отдельная под-фаза/issue, не red-tree каждого сервиса.

## Интеграционная поверхность (verified)

- **Zero-conflict**: ни один файл не тронут >1 завершённой веткой (`uniq -c` пусто).
  → merge в любом порядке, конфликтов нет.
- **Shared-surface касания** (вне `services/<svc>/`):
  - compute → `pkg/ids/ids.go` (+test): additive `NewHyphenID` (ins-/mt-), base-compatible.
  - vpc → `pkg/operations/worker.go` + пред-фикс `services/nlb/internal/clients/vpc/subnet_client.go`
    (+test) под новую Subnet-proto форму.
  - iam, storage → полностью self-contained (только свой `services/` + `proto/`).
- **Coupling-порядок**: vpc пред-фиксил nlb's vpc-client под новую Subnet-форму →
  **vpc интегрируется ПЕРЕД nlb** (иначе nlb's subnet_client не совпадёт с proto). При grind
  NLB-1 ветка должна ребейзиться на integration (взять новую vpc Subnet-proto + фикс клиента).

## Валидация `redesign/integration`

Ветка `redesign/integration` = base + merge(compute-1, iam-1, vpc-1, storage-1), sequential, rc=0 все.
- `GOWORK=off go build ./...` → **green** (BUILD_EXIT=0).
- **compute+storage cross-coupling** → **green** (CS_EXIT=0): storage-Referrer ссылки compute
  (bootSource→storage.image, bootVolume°/secondaryVolumes°→storage.volume) резолвятся против
  НОВОЙ redesigned-proto storage → split компилятивно-консистентен.
- `GOWORK=off go vet` (compute/iam/vpc/storage/pkg) → **green** (VET_EXIT=0): тестовые файлы тоже типизируются.
- `GOWORK=off go test -short` (compute/iam/vpc/storage/pkg) → **green**: **129 pkg ok, 0 FAIL, 0 упавших тестов**
  (59 no-test-files — type/wiring-пакеты). Unit-уровень merged-дерева подтверждён; testcontainers/-race/newman
  скипаются `-short` → прогнать ОДИН раз на полном 7-сервисном дереве (после registry+nlb), не piecemeal.

## Следующие шаги интеграции

1. registry REG-1 green → merge `redesign/registry-1` в `redesign/integration` (self-contained, ожидается zero-conflict).
2. nlb: grind 1a→1b→1c→1d поверх integration (ветка ребейзится на новую vpc-proto), затем merge.
3. Полный `go test ./... -race -timeout 30m -p 1` на integration (pg-пакеты тяжёлые — `-p 1`).
4. Далее — поздние под-фазы (COMP-2/3/4, STOR-2/3, VPC-2/3/4, IAM-2/3/4, REG-2/3, NLB-2/3/4),
   per-service gateway registration + newman (общая схема) + UI (ui-future).

_Не пушить / не открывать PR до явного разрешения владельца._
