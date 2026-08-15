# Redesign 2026 — integration status (первые под-фазы)

> [!note] Таблица ниже — ИСТОРИЧЕСКАЯ ЗАПИСЬ сведения, а не инвентарь живых веток
> Замер 2026-08-07. Из **восьми** имён `redesign/*`, названных в этом файле, в дереве
> (локально + origin) резолвится **одно** — `redesign/integration`, и та отстала от
> фактического ствола на **91** коммит. Остальные семь (`storage-1`, `iam-1`, `vpc-1`,
> `compute-1`, `registry-1`, `registry-1-namespace-archived`, `nlb-1a`) удалены после
> сведения — это штатный исход по `git-issues.md` §CI («смёржена+удалена»), а не потеря
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

> [!warning] Столбец «Первая под-фаза» перечислял РЕСУРСЫ ДОМЕНА, а не предмет приёмки
> (перемерено 2026-08-08 на `6b1293713`). Рядом стоит «✅ green», поэтому строка читалась как
> «эти ресурсы переделаны», — а две строки называли ресурсы, которые их же APPROVED-приёмка
> **выносит в следующие под-фазы**. Файл читают как инвентарь сделанного, и это делало ложное
> утверждение самым доступным в корпусе.
>
> Хуже всего на vpc: строка перечисляла семь ресурсов, тогда как
> `docs/specs/sub-phase-VPC-1-network-subnet-acceptance.md` (§Обзор, §Out-of-scope) покрывает
> **Network + Subnet** и раскладывает остальное по VPC-2 (SecurityGroup + RouteTable),
> VPC-3 (Address + AddressPool + sweeper), VPC-4 (Gateway + NIC). Дерево подтверждает приёмку,
> а не таблицу:
>
> | Что приземлило бы отсутствующую под-фазу | Предикат над `project/kacho` | Итог |
> |---|---|---|
> | VPC-2 снимает `SecurityGroup.defaultForNetwork°` | `git grep -c default_for_network -- proto/kacho/cloud/vpc/v1/` | **1** — поле живо |
> | VPC-3 переводит Address на `retention`/производное `scope°` | `git grep -n 'Retention\|EPHEMERAL' -- proto/kacho/cloud/vpc/v1/` | **пусто**; Address несёт легаси-пару `bool reserved` / `bool used` |
> | VPC-4 вводит однократный `external_address_spec` и `AssociateAddress` | `git grep -rn 'external_address_spec\|AssociateAddress' -- proto` | **0** и **0** |
> | коммиты под-фазы вообще | `git log --oneline HEAD --grep='VPC-<N>'` | VPC-1 — **21**; VPC-2/VPC-3/VPC-4 — **0** каждая |
>
> Контроль предиката (иначе ноль неотличим от негодного шаблона): `--grep='VPC-9'` → **0**,
> `--grep='VPC-1'` → 21. То же по storage: `--grep='STOR-1'` → **4**, `--grep='STOR-2'` → **0**,
> поэтому `Snapshot` в строке storage — тоже предмет следующей под-фазы, а не сделанное.
>
> Столбец теперь называет **предмет приёмки**. «✅ green» относится к тому, что в нём написано,
> и ни к чему больше; про непройденные под-фазы этот файл не утверждает ничего.

| Сервис | Ветка | Первая под-фаза | Статус |
|---|---|---|---|
| geo | (folded в base) | GEO-1 Region/Zone | ✅ green |
| storage | `redesign/storage-1` | STOR-1 Volume + Image (`Snapshot` — предмет STOR-2) | ✅ green |
| iam | `redesign/iam-1` | IAM-1 tenancy+authz (F1-F11) | ✅ green |
| vpc | `redesign/vpc-1` | VPC-1 Network + Subnet (placement-anchor); SG/RT — VPC-2, Address/AddressPool — VPC-3, Gateway/NIC — VPC-4 | ✅ green |
| compute | `redesign/compute-1` | COMP-1 Instance core + MachineType | ✅ green |
| registry | `redesign/registry-1` | REG-1 Registry+Repository (id-model, **Namespace-rename ОТКАЧЕН** owner-decision) | ✅ green (re-grind) |
| nlb | `redesign/nlb-1a` | NLB-1a FGA rename `lb_*`→`nlb_*` | ✅ green; **1b/1c/1d тоже приземлены** (см. ниже) |

> [!note] «1b-1d pending» пережило свой предмет — перемерено 2026-08-08 на `6b1293713`
> Все три под-фазы приземлены, и это видно с двух сторон.
>
> Коммиты в предках `HEAD` (`git log --oneline HEAD --grep='NLB-1<x>'`): 1a — **3**, 1b — **10**,
> 1c — **7**, 1d — **1**; контроль `--grep='NLB-1z'` → **0**.
>
> Приёмки называют, что должно было измениться, и дерево это несёт: NLB-1b снимает `:start`/`:stop`
> (`git grep -n 'rpc Start\|rpc Stop' -- proto/kacho/cloud/loadbalancer/` → **пусто**), возвращает
> `security_group_ids` и добавляет производные `resolved_backend_port°`/`substatus°`
> (`listener.proto:113`/`:117`, `network_load_balancer.proto:156` — каждое помечено «NLB-1b»);
> NLB-1c переделывает `HealthCheck` и переводит окна на `Duration`
> (`health_check.proto:25`/`:89`, `target_group.proto:26`/`:67`/`:71`).
>
> Замечание о единице счёта: proto-домен nlb лежит в `proto/kacho/cloud/loadbalancer/`, а не в
> `proto/kacho/cloud/nlb/` — предикат по второму пути даёт ноль по **всем** шаблонам и читается
> как «ничего не приземлилось». Пустой вывод по такому пути сперва проверяй наличием каталога.

**Registry — corrected id-модель** (owner-decision 2026-07-20, core rule #15): `Registry` (не Namespace), pull `$domain/$registryId/$repo:$tag`, id immutable, БЕЗ globalSlug/`:rename`; F4 region + F5 defaultRepositoryVisibility + F7 lifecycle сохранены. Namespace-impl архивирован `redesign/registry-1-namespace-archived`. Commits 89685f5/33d1637/6c8ee83/a282c90.

**Hardening round** (adversarial-review 6 CONFIRMED, все green TDD, ждут re-merge): storage `082265c` (images CHECK at-most-one), vpc `8d789f3`/`4cc2e25`/`7fb2f4a` (CIDR pagination/supernet/primary-anchor), iam `deb47e1`/`ff453f4` (target.resources[] least-priv over-grant + account-role→nested-project).

## Cross-cutting deferred (не блокирует под-фазы, но зафиксировать)

- **`google.rpc.ErrorInfo` reason-token — ОДИН эмитент, а не «нигде»** (перемерено 2026-08-08 на
  `6b1293713`). Прежняя редакция утверждала «токена нет нигде»; утверждение пережило свой предмет.

  Предикат — по тому, кто **прикрепляет** деталь, а не по тому, кто её называет:
  `git grep -rln 'errdetails.ErrorInfo' -- services gateway pkg | grep -v _test` → **три** файла.
  Из них by-lane-токен `api-conventions.md` несёт **один**:
  `services/nlb/internal/apps/kacho/api/loadbalancer/peer_errors.go:171` —
  `PEER_RESOURCE_MISSING`, `domain = "nlb.kacho.cloud"`. Форма не мёртвая: живой вызывающий
  `.../loadbalancer/create.go:335`, проба `linked_address_visibility_lane_test.go:79` утверждает
  именно токен. Два остальных файла эмитят **не** by-lane-словарь, а authz-причины края
  (`AUTHZ_DENIED`/`AUTHN_REQUIRED`) — их в этот счёт не берём.

  Почему грубый греп по имени токена тут врёт: `git grep -ln PEER_RESOURCE_MISSING` даёт **13**
  файлов, но в registry (`internal/apps/kacho/api/registry/create.go:71,166`,
  `internal/clients/geo/region_client.go:90`) это **проза godoc**, а не эмиссия — весь сервис
  не импортирует `errdetails` ни в одном не-тестовом файле (**0**). Считать надо импорт и
  прикрепление, не упоминание.

  Остаток долга: `PEER_RESOURCE_STATE` — **0** файлов вообще; `RESOURCE_NOT_FOUND` и
  `INVALID_RESOURCE_ID` в прод-коде сервисов — **0** (встречаются только в кейсе
  `services/iam/tests/newman/cases/iam-interactive-client.py` и одном integration-тесте
  registry). By-lane **code + contract-text split** реализован; машинного токена нет у всех
  полос, кроме названной. → отдельная под-фаза/issue (`docs/specs/sub-phase-XC-1-error-reason-token-acceptance.md`),
  не red-tree каждого сервиса. Формулировка «нигде» снимала бы регрессию, которая уже написана.

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

> [!note] Шаги 1 и 2 исполнены — список читается как история, а не как задание (2026-08-08)
> Оба были сформулированы как merge названных веток; веток нет, а содержимое в стволе:
> `git log --oneline HEAD --grep='REG-1'` → **9**, `--grep='NLB-1b'` → **10**, `--grep='NLB-1c'` → **7**,
> `--grep='NLB-1d'` → **1** (контроль `--grep='NLB-1z'` → **0**). Шаги оставлены дословно, потому
> что по ним прослеживаются коммиты; выполнять их заново нечего.

1. ~~registry REG-1 green → merge `redesign/registry-1` в `redesign/integration`~~ — исполнено.
2. ~~nlb: grind 1a→1b→1c→1d поверх integration, затем merge~~ — исполнено.
3. Полный `go test ./... -race -timeout 30m -p 1` на integration (pg-пакеты тяжёлые — `-p 1`).
   Этот файл его исхода **не утверждает**: числа §Валидация относятся к прогону `-short` на
   `redesign/integration`, а не к сегодняшнему стволу.
4. Далее — поздние под-фазы (COMP-2/3/4, STOR-2/3, VPC-2/3/4, IAM-2/3/4, REG-2/3, NLB-2/3/4),
   per-service gateway registration + newman (общая схема) + UI (ui-future).

_Не пушить / не открывать PR до явного разрешения владельца._
