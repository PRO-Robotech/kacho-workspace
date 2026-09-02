# Sub-phase SDD-1 — Kachō Change Graph Acceptance

> **Статус:** DRAFT
> **Статическая форма subject:** DRAFT. Effective verdict выводится только из
> внешнего review event и append-only review artifact; строка subject после
> review не меняется.
> **Дата subject:** 2026-09-02
> **GitHub Issue:** [PRO-Robotech/kacho-workspace#480](https://github.com/PRO-Robotech/kacho-workspace/issues/480)
> **Основание:** прямое решение владельца от 2026-09-02
> **История review:** ❌ CHANGES REQUESTED для SHA-256
> 3f1d91967f46cbeaa9d5f9939712d580ae99e3cce69c28b7169873d2ccc3f9e2;
> ❌ CHANGES REQUESTED для SHA-256
> aaeffb0ac70d68f737c12eec902a38b9fb80d9ebc45dba186fbb1a81d2c2d8c0.
> ❌ CHANGES REQUESTED для SHA-256
> d1a0ee80d108c03d8a39b8e7448a83c4d33421d4d3494c926b9043bc7a6fa251.
> Все три record append-only и не переносят verdict на эту редакцию.

## 1. Scope и единственный bootstrap

Kachō Change Graph соединяет существующие acceptance-first, TDD, профильные
review и landing в vendor-neutral SDD-контур. Контур связывает observable
behavior, technical design, execution route, evidence, actual diff и landed
content.

SDD-1 — единственный bootstrap change. Он начат legacy-процессом до cutover и
долговечно ограничен парой:

- Issue #480 владеет why, priority, owner и live status;
- этот acceptance владеет observable scope SDD-1.

SDD-1 не фабрикует docs/changes/SDD-1 и не изображает прохождение ещё не
существовавшего Change Graph. Обязательность начинается только с cutover,
созданного versioned docs/changes/policy.yaml при landing SDD-1.

docs/specs/04-roadmap-and-phasing.md — обязательный обновляемый нормативный
consumer lifecycle. Он ссылается на этот acceptance, не копирует observable
scope и не становится вторым acceptance.

Это process/tooling change, не RPC. Operation, REST и Newman не обязательны без
соответствующей surface.

## 2. Truth ownership

| Артефакт | Единственный предмет истины |
|---|---|
| GitHub Issue | why, priority, owner, live status |
| acceptance.md | observable behavior и case IDs |
| design.md | technical decisions, invariants, exposure mapping |
| tasks.md | approved execution route, не tracker |
| change.yaml | coordinates, lifecycle state, hashes, links |
| holders.yaml | exact ownership, applicability и evidence coordinates |
| reviews/** | verdict конкретной роли на конкретный subject/content digest |
| evidence/** | captured outputs и provenance |
| vault | landed system knowledge |
| 04-roadmap-and-phasing.md | normative lifecycle consumer |

Semantic duplication, tracker-like tasks, open design decisions и смысловые
конфликты судит human semantic holder. Machine gate не объявляет, что понимает
смысл прозы: он проверяет наличие, authority, subject binding и verdict
зарегистрированного human holder.

## 3. Package layout после cutover

~~~text
docs/changes/<change-id>/
├── change.yaml
├── holders.yaml
├── acceptance.md
├── design.md
├── tasks.md
├── reviews/
│   ├── acceptance/<acceptance-sha256>.yaml
│   ├── class-exposure/initial/<acceptance-sha256>.yaml
│   ├── class-exposure/revalidation/<design-sha256>.yaml
│   ├── design/<role>/<design-sha256>.yaml
│   ├── post-diff/<role>/<content-digest>.yaml
│   └── convergence/<content-digest>.yaml
└── evidence/<holder-id>/<subject-sha256>.yaml
~~~

Bootstrap acceptance review хранится отдельно, потому что package ещё не
существует:

~~~text
docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-acceptance/<subject-sha256>.yaml
~~~

Этот artifact содержит `subject_sha256`, verdict, `authorized_actor`, а также
URL, immutable node ID, body SHA-256 и timestamp verdict event в Issue #480.

## 4. External review authority и noncyclic approval

Acceptance subject всегда сохраняет статическую форму DRAFT.

До cutover у единственного bootstrap есть внешний, не зависящий от ещё не
созданного policy trust root. GitHub API обязан подтвердить, что publisher
verdict event имеет permission `ADMIN` на `PRO-Robotech/kacho-workspace`; event
принадлежит ровно Issue #480, а body связывает exact subject SHA-256, роль
acceptance-reviewer и verdict. Bootstrap artifact ссылается на immutable
node/URL этого event и его body digest. На дату subject actor `pointpu` имеет
подтверждённый `ADMIN`, но gate каждый раз проверяет permission через API, а не
доверяет записанному имени. Поэтому bootstrap approval не читает future policy.

После cutover producer authority future reviews задаёт
`docs/changes/policy.yaml`: append-only artifact ссылается на GitHub
Issue/PR review/comment event, gate получает event через API, actor разрешён для
роли policy allowlist, а event body/subject digests и verdict совпадают.

Самодекларированное role: без event не даёт authority. Недоступный API или ref —
NOT_EXECUTED. Старый review artifact не редактируется и не удаляется; новый
subject получает новый sibling artifact.

С момента cutover bootstrap exception недействителен: acceptance и все design,
specialist, class-exposure, convergence и landing reviews используют только
versioned policy authority. Role name в YAML — coordinate, не доказательство
личности. Недоступность permission, Issue, event или API даёт NOT_EXECUTED.

## 5. Lifecycle, class exposure и applicability

~~~text
ISSUE_READY
→ ACCEPTANCE_APPROVED
→ CLASS_EXPOSURE_RECORDED
→ DESIGN_APPROVED
→ TASKS_READY
→ RED_PROVEN
→ IMPLEMENTING
→ CONVERGED
→ LANDED
→ ARCHIVED
~~~

WITHDRAWN и SUPERSEDED — терминальные боковые состояния.

Class exposure имеет две разные durable записи:

- initial analysis связывается с exact acceptance hash и сохраняет items;
- перед DESIGN_APPROVED тот же class-exposure role revalidate-ит exact design
  hash после exact mapping каждого item → design decision.

Изменение design инвалидирует только revalidation и downstream; initial history
остаётся. Новый external call, async path либо sentinel является новым exposure
item и требует mapping + revalidation.

DESIGN_APPROVED запрещён при TODO, TBD, open decision, unmapped exposure,
отсутствующем applicable review или stale revalidation. После него обязательный
writing-plans handoff производит tasks.md; затем возможен TASKS_READY.

N/A допустим только по predicate ID из versioned applicability registry в
policy.yaml и с evidence, удовлетворяющим этому predicate. Свободный текст N/A
не является evidence.

## 6. Pre-RED driver и implementation boundary

Единственная matrix command:

~~~text
python3 scripts/change-graph-gate/tests/run_case.py --case <ID>
~~~

run_case.py и scripts/change-graph-gate/tests/**, включая fixtures, — pre-RED
test diff integration-tester. Driver загружает fixture и вызывает SUT через
стабильный test seam. Production scripts/change-graph-gate/run.py, production
runner, callers/wiring, adapter generator, canonical .claude, CI/config и
project/kacho являются implementation diff.

До RED_PROVEN допустимы:

- acceptance/design/tasks/change/review records и evidence plan;
- tests/** и fixtures, назначенные integration-tester и не содержащие
  implementation.

Если SUT capability отсутствует, существующий driver обязан вернуть holder RED:

~~~text
RED · CASE_CAPABILITY_MISSING · exit 10
~~~

Это честный acceptance RED. Command-not-found, unrelated driver crash и
infrastructure failure не подменяют его: они не открывают RED_PROVEN.

После implementation driver ассертит exact SUT triple
category + diagnostic + exit. Поэтому expected SUT RED/NOT_EXECUTED в negative
case даёт holder GREEN, если triple совпал. Unexpected SUT GREEN, masked
capability, unrelated crash или неверная triple дают holder RED.

**Implementation diff** включает product source/proto/migrations/deploy/UI,
canonical CLAUDE.md/.claude, scripts/gates, CI/config и process/runtime tooling.
После валидного RED_PROVEN он разрешён; до него — RED. Harness, содержащий либо
маскирующий implementation, запрещён независимо от пути.

## 7. Machine и human holders

holders.yaml объявляет exact required holder set.

Machine holder eligible только при наличии:

- holder ID и owner;
- exact executable и predicate;
- subject/input/output SHA-256;
- stdout и stderr digest;
- captured category;
- evidence coordinate.

Executable true, неизвестная команда, отсутствующее поле или несовпавший digest
дают RED.

До eligibility каждый machine holder проходит birth inversion:

1. known-good input даёт ожидаемый pass;
2. однофактный injected defect даёт ожидаемый RED;
3. zero census не может дать GREEN.

Human semantic holder — verified GitHub event + append-only artifact. Он содержит
immutable event node/URL, actor из role allowlist, body digest, subject digest,
timestamp и verdict. API недоступен → NOT_EXECUTED; role: без event → RED.

У required holder ровно один captured outcome: GREEN, RED или NOT_EXECUTED.
Missing output → NOT_EXECUTED. Active package с 0 acceptance IDs, 0 required
holders или отсутствующим subject/input → RED, не vacuous GREEN.

## 8. Cutover в двух Git DAG и legacy census

Versioned docs/changes/policy.yaml имеет schema_version 1 и отдельные entries:

~~~yaml
repositories:
  - repo: PRO-Robotech/kacho-workspace
    cutover_commit: <40 lowercase hex>
  - repo: PRO-Robotech/kacho
    cutover_commit: <40 lowercase hex>
review_authority:
  <role>: [<authorized GitHub actors>]
applicability_predicates:
  - id: <stable predicate id>
legacy_census:
  path: docs/changes/census/<response-sha256>.yaml
  sha256: <response-sha256>
legacy_changes:
  - issue: <GitHub issue URL>
    acceptance_path: <repo-relative path>
    route: legacy | migrate
~~~

Landing-reviewer записывает реальные commits при landing SDD-1. Для candidate
PR/push authoritative caller передаёт repo identity, target/base SHA и head SHA.
Gate проверяет, что commits существуют именно в названном repo:

- base — ancestor cutover_commit: pre-cutover, допустим только registered legacy;
- base == cutover_commit: package required, кроме SDD-1/#480 bootstrap;
- cutover_commit — ancestor base: package required;
- histories incomparable: RED;
- refs/API unavailable: NOT_EXECUTED.

Не используется эвристика стартового коммита или имени ветки.

Independent legacy census producer при landing получает через GitHub API:

- snapshot open PR для workspace и product;
- Issues с live in-progress state/label;
- exact query, repo, ETag/revision, timestamp и response digest.

Artifact:

~~~text
docs/changes/census/<response-sha256>.yaml
~~~

Policy legacy_changes обязан exact-set совпасть со snapshot. API unavailable →
NOT_EXECUTED; stale snapshot, incomplete repo/query coverage и set mismatch →
RED. Closed historical acceptance не backfill-ятся. Route legacy допускает
только неизменённый observable contract; change требует route migrate + package.

## 9. Tracing, convergence и landing

Acceptance ID set A должен exact-set совпасть с design, tasks и evidence plan.
Missing, orphan и equal-count/different-members → RED. Одному ID разрешены
несколько независимых holders.

Specialist post-diff records хранятся раздельно:

~~~text
reviews/post-diff/<role>/<content-digest>.yaml
~~~

Они не перезаписывают друг друга. Aggregator exact-set сверяет applicable roles,
verified external events и registered N/A predicates. Distributed surface требует
повторный post-diff system-design-review.

Только convergence-reviewer создаёт final durable record:

~~~text
reviews/convergence/<content-digest>.yaml
~~~

Record backed verified external event и содержит exact change hashes, full
base/source SHA каждого repo и SHA-256 canonical diff set:
repo + path + file mode + final blob/deletion marker, sorted.

Squash/cherry-pick с тем же applied content разрешает LANDED и записывает landed
SHA. Content drift инвалидирует convergence. Commit identity не подменяет content
identity.

## 10. Tracked adapter contract

Adapter входит в SDD-1 безусловно. Canonical ownership manifest:

~~~text
.claude/adapters.yaml
~~~

Единственные canonical inputs:

- root CLAUDE.md;
- tracked .claude/adapters.yaml;
- tracked .claude/agents/**;
- tracked .claude/hooks/**;
- tracked .claude/rules/**;
- tracked .claude/skills/**;
- tracked .claude/settings.json.

Точный adapter-owned generated set:

- root AGENTS.md;
- полные tracked packages .agents/skills/<name>/** для каждого manifest skill,
  включая SKILL.md, references, assets и scripts; текущие разновидности включают
  audit-round.workflow.js, EXAMPLES и Obsidian references;
- .codex/agents/*.toml;
- .codex/hooks/**;
- .codex/hooks.json.

Outputs tracked. CI генерирует их во временный каталог и побайтно сравнивает с
tracked tree. Missing nested asset, tracked drift, missing/extra adapter-owned
output, uppercase .Codex, absolute path, noncanonical input и nondeterminism →
RED.

Adapter contract принадлежит отдельному machine holder `adapter-contract`; его
birth inversion и evidence не сливаются с aggregate process-gate holder.

Foreign runtime package вне adapters.yaml не является adapter output и не
маскирует drift. Design «outputs только untracked/runtime» запрещён: generated
contract обязан быть tracked.

## 11. Authoritative wiring

Ровно четыре blocking callers:

- workspace scripts/hooks/pre-push;
- workspace .github/workflows/ci.yaml;
- product project/kacho/scripts/hooks/pre-push;
- product project/kacho/.github/workflows/ci.yaml.

Workspace callers передают repo identity/base/head и sibling product coordinates.
Product ledger хранит change_id + pinned workspace_revision. Product CI fetches
public workspace на этой revision, а product base/head берёт из GitHub event.
Missing fetch/ref → NOT_EXECUTED.

Pre-push читает remote/local SHAs из stdin и получает sibling workspace/product
coordinates. Missing required repo или required ref → NOT_EXECUTED.

У каждого реального caller есть one-fact injection: valid fixture проходит,
тот же input с одним invalid Change Graph fact блокируется. Advisory hooks не
являются authority и не заменяют любой из четырёх callers.

## 12. Case driver contract

Fixtures живут в:

~~~text
scripts/change-graph-gate/tests/testdata/<ID>/
~~~

Каждый negative/NOT_EXECUTED case объявляет positive twin и меняет ровно один
названный факт. Driver fixture, меняющая больше одного факта, invalid и не даёт
holder verdict.

Матрица для каждого ID различает:

- expected SUT triple;
- expected final holder verdict после implementation;
- expected initial holder RED до capability.

Planned coordinates не утверждают, что файлы уже существуют.

## 13. Atomic Given-When-Then cases

### Bootstrap
#### SDD-1-BOOT-01 — единственный bootstrap #480

**Positive twin:** —

**Holder type:** machine

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** Issue #480 и этот static-DRAFT subject начаты legacy-процессом до cutover

**When** SDD-1 проверяется без self-package

**Then** SUT принимает ровно это bootstrap-исключение.

#### SDD-1-BOOT-02 — второе bootstrap-исключение

**Positive twin:** SDD-1-BOOT-01

**Holder type:** machine

**Expected SUT:** RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10

**Given** в twin изменён только bootstrap `change_id` с закреплённого #480 на другой change

**When** запрашивается отсутствие package

**Then** SUT отвергает второе bootstrap-исключение.

### External verdict
#### SDD-1-REVIEW-01 — effective approval из event и artifact

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** actor `pointpu` публикует verdict event ровно в Issue #480, GitHub API подтверждает ему `ADMIN`, body связывает acceptance-reviewer verdict с exact static-DRAFT subject SHA, artifact совпадает с event

**When** effective verdict вычисляется

**Then** SUT выводит APPROVED, не изменяя subject.

#### SDD-1-REVIEW-02 — subject переписан в APPROVED

**Positive twin:** SDD-1-REVIEW-01

**Holder type:** machine

**Expected SUT:** RED · CG_ACCEPTANCE_SUBJECT_MUTATED · exit 10

**Given** в twin изменена только строка static form DRAFT на APPROVED

**When** subject и artifact проверяются

**Then** SUT отвергает циклическое самоизменение subject.

#### SDD-1-REVIEW-03 — review history append-only

**Positive twin:** —

**Holder type:** machine

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** три CHANGES REQUESTED artifacts старых SHA сохранены, новый SHA имеет отдельный artifact

**When** history проверяется

**Then** SUT принимает append-only последовательность.

#### SDD-1-REVIEW-04 — старый review record изменён

**Positive twin:** SDD-1-REVIEW-03

**Holder type:** machine

**Expected SUT:** RED · CG_REVIEW_HISTORY_MUTATED · exit 10

**Given** в twin изменён ровно один byte одного старого review artifact

**When** history проверяется

**Then** SUT отвергает mutation.

#### SDD-1-REVIEW-05 — bootstrap publisher не имеет ADMIN
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_BOOTSTRAP_ACTOR_NOT_ADMIN · exit 10  
**Given** в twin изменён только GitHub permission publisher с `ADMIN` на `WRITE`  
**When** bootstrap effective verdict вычисляется  
**Then** SUT возвращает RED без обращения к future policy.

#### SDD-1-REVIEW-06 — bootstrap artifact подменяет actor
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_BOOTSTRAP_ACTOR_SPOOFED · exit 10  
**Given** в twin изменён только `authorized_actor` artifact на actor, не равного publisher event  
**When** bootstrap effective verdict вычисляется  
**Then** SUT возвращает RED.

#### SDD-1-REVIEW-07 — bootstrap event принадлежит другому Issue
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_BOOTSTRAP_ISSUE_MISMATCH · exit 10  
**Given** в twin изменена только parent Issue coordinate event с #480 на #481  
**When** bootstrap effective verdict вычисляется  
**Then** SUT возвращает RED.

#### SDD-1-REVIEW-08 — bootstrap permission lookup недоступен
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** human-external  
**Expected SUT:** NOT_EXECUTED · CG_BOOTSTRAP_PERMISSION_UNAVAILABLE · exit 20  
**Given** в twin изменена только доступность GitHub permission lookup на unavailable  
**When** bootstrap effective verdict вычисляется  
**Then** SUT возвращает NOT_EXECUTED, не APPROVED.

#### SDD-1-REVIEW-09 — bootstrap event lookup недоступен
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** human-external  
**Expected SUT:** NOT_EXECUTED · CG_BOOTSTRAP_EVENT_UNAVAILABLE · exit 20  
**Given** в twin изменена только доступность Issue #480 event lookup на unavailable  
**When** bootstrap effective verdict вычисляется  
**Then** SUT возвращает NOT_EXECUTED, не APPROVED.

#### SDD-1-REVIEW-10 — bootstrap exception применён после cutover
**Positive twin:** SDD-1-REVIEW-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_BOOTSTRAP_AUTHORITY_EXPIRED · exit 10  
**Given** в twin изменена только authority epoch с pre-cutover на post-cutover  
**When** effective verdict вычисляется без policy-authorized event  
**Then** SUT возвращает RED и не продлевает bootstrap exception.

### External authority
#### SDD-1-AUTH-01 — post-cutover authorized external event

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** artifact содержит immutable event URL/node, actor из post-cutover policy allowlist, body/subject digests и timestamp

**When** gate получает event через GitHub API

**Then** SUT признаёт producer authority.

#### SDD-1-AUTH-02 — role без external event

**Positive twin:** SDD-1-AUTH-01

**Holder type:** machine

**Expected SUT:** RED · CG_REVIEW_EVENT_MISSING · exit 10

**Given** из twin удалена только event coordinate, role оставлена

**When** authority проверяется

**Then** SUT не принимает self-declared role.

#### SDD-1-AUTH-03 — actor не в allowlist

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_REVIEW_ACTOR_UNAUTHORIZED · exit 10

**Given** в twin изменён только actor на отсутствующего в policy allowlist

**When** authority проверяется

**Then** SUT отвергает actor.

#### SDD-1-AUTH-04 — event body digest не совпал

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_REVIEW_BODY_DIGEST_MISMATCH · exit 10

**Given** в twin изменён только body digest

**When** authority проверяется

**Then** SUT отвергает event.

#### SDD-1-AUTH-05 — event subject digest не совпал

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_REVIEW_SUBJECT_DIGEST_MISMATCH · exit 10

**Given** в twin изменён только subject digest

**When** authority проверяется

**Then** SUT отвергает event.

#### SDD-1-AUTH-06 — event не имеет immutable node

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_REVIEW_EVENT_IDENTITY_MISSING · exit 10

**Given** из twin удалён только immutable node ID

**When** authority проверяется

**Then** SUT отвергает непроверяемую ссылку.

#### SDD-1-AUTH-07 — verdict принадлежит другой роли

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_REVIEW_ROLE_UNAUTHORIZED · exit 10

**Given** в twin actor допустим, но event зарегистрирован не для required role

**When** authority проверяется

**Then** SUT не подменяет acceptance-reviewer другой ролью.

#### SDD-1-AUTH-08 — GitHub API недоступен

**Positive twin:** SDD-1-AUTH-01

**Holder type:** human-external

**Expected SUT:** NOT_EXECUTED · CG_REVIEW_API_UNAVAILABLE · exit 20

**Given** в twin изменена только доступность GitHub API

**When** authority проверяется

**Then** SUT возвращает NOT_EXECUTED, не APPROVED.

### Truth ownership
#### SDD-1-TRUTH-01 — human holder подтверждает разделение истины

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** authorized semantic review event проверяет owners table и roadmap как consumer

**When** truth review агрегируется

**Then** SUT принимает GREEN human verdict.

#### SDD-1-TRUTH-02 — semantic prose продублирована

**Positive twin:** SDD-1-TRUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_HUMAN_TRUTH_DUPLICATION · exit 10

**Given** human fixture меняет только один artifact, копируя observable requirement

**When** authorized semantic reviewer даёт CHANGES_REQUESTED

**Then** SUT блокирует transition по verified human verdict.

#### SDD-1-TRUTH-03 — два owners конфликтуют

**Positive twin:** SDD-1-TRUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_HUMAN_TRUTH_CONFLICT · exit 10

**Given** human fixture меняет только одно утверждение второго owner

**When** authorized semantic reviewer даёт CHANGES_REQUESTED

**Then** SUT блокирует transition.

#### SDD-1-TRUTH-04 — tasks стали live tracker

**Positive twin:** SDD-1-TRUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_HUMAN_TASKS_TRACKER · exit 10

**Given** human fixture добавляет в tasks ровно один live status

**When** authorized semantic reviewer даёт CHANGES_REQUESTED

**Then** SUT блокирует transition.

#### SDD-1-TRUTH-05 — manifest содержит normative prose

**Positive twin:** SDD-1-TRUTH-01

**Holder type:** human-external

**Expected SUT:** RED · CG_HUMAN_MANIFEST_PROSE · exit 10

**Given** human fixture добавляет в change.yaml ровно одно requirement paragraph

**When** authorized semantic reviewer даёт CHANGES_REQUESTED

**Then** SUT блокирует transition.

#### SDD-1-TRUTH-06 — semantic claim имеет только machine holder

**Positive twin:** SDD-1-TRUTH-01

**Holder type:** machine

**Expected SUT:** RED · CG_HUMAN_HOLDER_REQUIRED · exit 10

**Given** из twin удалён только required human semantic holder, machine result оставлен

**When** holder exact-set проверяется

**Then** SUT не заявляет автоматическое понимание смысла.

### Lifecycle
#### SDD-1-LIFE-01 — последовательные stages

**Positive twin:** —

**Holder type:** machine

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** все required artifacts и verdicts актуальны

**When** package проходит stages по одной

**Then** SUT принимает каждый transition.

#### SDD-1-LIFE-02 — stage пропущен

**Positive twin:** SDD-1-LIFE-01

**Holder type:** machine

**Expected SUT:** RED · CG_LIFECYCLE_TRANSITION_INVALID · exit 10

**Given** в twin запрошен только один transition через обязательную stage

**When** transition проверяется

**Then** SUT отвергает skip.

#### SDD-1-LIFE-03 — artifact stage отсутствует

**Positive twin:** SDD-1-LIFE-01

**Holder type:** machine

**Expected SUT:** RED · CG_REQUIRED_ARTIFACT_MISSING · exit 10

**Given** из twin удалён ровно один required artifact текущей stage

**When** transition проверяется

**Then** SUT отвергает transition.

### Non-vacuity
#### SDD-1-NONEMPTY-01 — непустой предмет holders

**Positive twin:** —

**Holder type:** machine

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** active package имеет IDs, required holders и существующие subjects

**When** census проверяется

**Then** SUT возвращает GREEN.

#### SDD-1-NONEMPTY-02 — ноль acceptance IDs

**Positive twin:** SDD-1-NONEMPTY-01

**Holder type:** machine

**Expected SUT:** RED · CG_ACCEPTANCE_IDS_EMPTY · exit 10

**Given** в twin очищен только acceptance ID set

**When** census проверяется

**Then** SUT возвращает RED.

#### SDD-1-NONEMPTY-03 — ноль required holders

**Positive twin:** SDD-1-NONEMPTY-01

**Holder type:** machine

**Expected SUT:** RED · CG_REQUIRED_HOLDERS_EMPTY · exit 10

**Given** в twin очищен только required holder set

**When** census проверяется

**Then** SUT возвращает RED.

#### SDD-1-NONEMPTY-04 — holder subject отсутствует

**Positive twin:** SDD-1-NONEMPTY-01

**Holder type:** machine

**Expected SUT:** RED · CG_HOLDER_SUBJECT_MISSING · exit 10

**Given** из twin удалён только subject одного holder

**When** census проверяется

**Then** SUT возвращает RED.

### Class exposure
#### SDD-1-CLASS-01 — initial analysis связан с acceptance

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** initial record от class-exposure role содержит exact acceptance hash и item IDs

**When** CLASS_EXPOSURE_RECORDED проверяется

**Then** SUT принимает record.

#### SDD-1-CLASS-02 — initial analysis отсутствует

**Positive twin:** SDD-1-CLASS-01

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_INITIAL_MISSING · exit 10

**Given** из twin удалён только initial record

**When** stage проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-03 — initial analysis связан со старым acceptance

**Positive twin:** SDD-1-CLASS-01

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_INITIAL_STALE · exit 10

**Given** в twin изменён только acceptance hash

**When** stage проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-04 — exact mapping и design revalidation

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** каждый initial item exact-map-ится в design decision, а role revalidate-ит exact design hash

**When** DESIGN_APPROVED проверяется

**Then** SUT принимает unchanged mapped design.

#### SDD-1-CLASS-05 — exposure item не mapped

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_ITEM_UNMAPPED · exit 10

**Given** из twin удалён только mapping одного item

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-06 — design revalidation отсутствует

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_REVALIDATION_MISSING · exit 10

**Given** из twin удалён только revalidation record

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-07 — design изменён после revalidation

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_REVALIDATION_STALE · exit 10

**Given** в twin изменён только design hash после revalidation

**When** DESIGN_APPROVED проверяется

**Then** SUT сохраняет initial history и отвергает stale revalidation.

#### SDD-1-CLASS-08 — новый external call не revalidated

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_NEW_EXTERNAL_CALL · exit 10

**Given** в twin добавлен только один external call без нового mapping/revalidation

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-09 — новый async path не revalidated

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_NEW_ASYNC_PATH · exit 10

**Given** в twin добавлен только один async path без нового mapping/revalidation

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

#### SDD-1-CLASS-10 — новый sentinel не revalidated

**Positive twin:** SDD-1-CLASS-04

**Holder type:** machine

**Expected SUT:** RED · CG_CLASS_NEW_SENTINEL · exit 10

**Given** в twin добавлен только один sentinel без нового mapping/revalidation

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

### Design and tasks
#### SDD-1-DESIGN-01 — closed design и applicable reviews

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** design не имеет open decisions и все applicable pre-code reviews verified

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает GREEN.

#### SDD-1-DESIGN-02 — design имеет open decision

**Positive twin:** SDD-1-DESIGN-01

**Holder type:** human-external

**Expected SUT:** RED · CG_DESIGN_DECISION_OPEN · exit 10

**Given** human fixture добавляет только один TODO/TBD/open decision

**When** semantic design reviewer даёт CHANGES_REQUESTED

**Then** SUT блокирует DESIGN_APPROVED.

#### SDD-1-DESIGN-03 — applicable review отсутствует

**Positive twin:** SDD-1-DESIGN-01

**Holder type:** machine

**Expected SUT:** RED · CG_PRECODE_REVIEW_MISSING · exit 10

**Given** из twin удалён только один applicable review

**When** DESIGN_APPROVED проверяется

**Then** SUT возвращает RED.

#### SDD-1-NA-01 — registered N/A predicate выполнен

**Positive twin:** —

**Holder type:** machine

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** role ссылается на registered predicate ID и evidence удовлетворяет predicate

**When** applicability проверяется

**Then** SUT принимает N/A.

#### SDD-1-NA-02 — N/A predicate не зарегистрирован

**Positive twin:** SDD-1-NA-01

**Holder type:** machine

**Expected SUT:** RED · CG_NA_PREDICATE_UNREGISTERED · exit 10

**Given** в twin изменён только predicate ID на отсутствующий в policy

**When** applicability проверяется

**Then** SUT возвращает RED.

#### SDD-1-NA-03 — N/A evidence не выполняет predicate

**Positive twin:** SDD-1-NA-01

**Holder type:** machine

**Expected SUT:** RED · CG_NA_PREDICATE_FALSE · exit 10

**Given** в twin изменён только evidence fact так, что predicate false

**When** applicability проверяется

**Then** SUT возвращает RED.

#### SDD-1-TASKS-01 — writing-plans handoff после design

**Positive twin:** —

**Holder type:** human-external

**Expected SUT:** GREEN · CG_OK · exit 0

**Given** DESIGN_APPROVED достигнут и verified writing-plans handoff производит tasks

**When** TASKS_READY проверяется

**Then** SUT возвращает GREEN.

#### SDD-1-TASKS-02 — writing-plans handoff отсутствует

**Positive twin:** SDD-1-TASKS-01

**Holder type:** machine

**Expected SUT:** RED · CG_WRITING_PLANS_HANDOFF_MISSING · exit 10

**Given** из twin удалён только handoff event

**When** TASKS_READY проверяется

**Then** SUT возвращает RED.

#### SDD-1-TASKS-03 — tasks готовы до design approval

**Positive twin:** SDD-1-TASKS-01

**Holder type:** machine

**Expected SUT:** RED · CG_TASKS_BEFORE_DESIGN_APPROVAL · exit 10

**Given** в twin изменена только design stage на неутверждённую

**When** TASKS_READY проверяется

**Then** SUT возвращает RED.

### Pre-RED и implementation boundary

#### SDD-1-TDD-01 — разрешённый test diff
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** до RED изменены только назначенные integration-tester `tests/**`, fixtures и evidence plan, не содержащие implementation  
**When** pre-RED diff классифицируется  
**Then** SUT принимает test diff.

#### SDD-1-TDD-02 — честный acceptance RED открывает RED_PROVEN
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** pre-RED driver на valid assertion записал holder `RED · CASE_CAPABILITY_MISSING · 10` из стабильного seam  
**When** eligibility RED_PROVEN проверяется  
**Then** SUT открывает RED_PROVEN.

#### SDD-1-TDD-03 — unexpected GREEN не открывает RED_PROVEN
**Positive twin:** SDD-1-TDD-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_RED_PROOF_UNEXPECTED_GREEN · exit 10  
**Given** в twin изменён только initial holder outcome на GREEN  
**When** eligibility RED_PROVEN проверяется  
**Then** SUT не открывает RED_PROVEN.

#### SDD-1-TDD-04 — NOT_EXECUTED не открывает RED_PROVEN
**Positive twin:** SDD-1-TDD-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_RED_PROOF_NOT_EXECUTED · exit 10  
**Given** в twin изменён только initial holder outcome на NOT_EXECUTED  
**When** eligibility RED_PROVEN проверяется  
**Then** SUT не открывает RED_PROVEN.

#### SDD-1-TDD-05 — unrelated crash не открывает RED_PROVEN
**Positive twin:** SDD-1-TDD-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_RED_PROOF_INFRA_FAILURE · exit 10  
**Given** в twin изменён только captured outcome на unrelated driver/infrastructure crash  
**When** eligibility RED_PROVEN проверяется  
**Then** SUT не принимает crash как acceptance RED.

#### SDD-1-TDD-06 — implementation разрешён после RED_PROVEN
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** exact acceptance set имеет valid RED_PROVEN  
**When** появляется implementation diff  
**Then** SUT разрешает переход IMPLEMENTING.

#### SDD-1-TDD-07 — implementation появился до RED_PROVEN
**Positive twin:** SDD-1-TDD-06  
**Holder type:** machine  
**Expected SUT:** RED · CG_IMPLEMENTATION_BEFORE_RED · exit 10  
**Given** в twin изменён только stage: RED_PROVEN отсутствует  
**When** implementation diff проверяется  
**Then** SUT отвергает diff.

#### SDD-1-TDD-08 — test harness содержит implementation
**Positive twin:** SDD-1-TDD-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TEST_HARNESS_CONTAINS_IMPLEMENTATION · exit 10  
**Given** в twin добавлен ровно один implementation behavior внутрь `tests/**`  
**When** pre-RED diff классифицируется  
**Then** SUT отвергает harness независимо от пути.

#### SDD-1-TDD-09 — harness маскирует отсутствующую capability
**Positive twin:** SDD-1-TDD-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_TEST_HARNESS_MASKS_CAPABILITY · exit 10  
**Given** в twin driver вместо seam синтезирует ожидаемую SUT triple  
**When** RED_PROVEN проверяется  
**Then** SUT отвергает masked result.

#### SDD-1-TDD-10 — test diff принадлежит не integration-tester
**Positive twin:** SDD-1-TDD-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_TEST_DIFF_OWNER_INVALID · exit 10  
**Given** в twin изменён только verified owner test diff  
**When** pre-RED ownership проверяется  
**Then** SUT отвергает diff.

### Machine-holder provenance и birth inversion

#### SDD-1-HOLDER-01 — полный machine-holder manifest
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** manifest связывает holder ID, owner, exact executable/predicate, subject/input/output hashes, stdout/stderr digests, category и evidence coordinate  
**When** machine holder проверяется  
**Then** SUT признаёт holder eligible.

#### SDD-1-HOLDER-02 — holder ID отсутствует
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_ID_MISSING · exit 10  
**Given** из twin удалён только holder ID  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-03 — executable равен true
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_EXECUTABLE_TRIVIAL · exit 10  
**Given** в twin изменён только executable на `true`  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-04 — executable неизвестен
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_EXECUTABLE_UNKNOWN · exit 10  
**Given** в twin изменён только executable на незарегистрированную команду  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-05 — predicate отсутствует
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_PREDICATE_MISSING · exit 10  
**Given** из twin удалён только predicate  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-06 — subject hash не совпал
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_SUBJECT_HASH_MISMATCH · exit 10  
**Given** в twin изменён только subject hash  
**When** provenance проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-07 — input hash не совпал
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_INPUT_HASH_MISMATCH · exit 10  
**Given** в twin изменён только input hash  
**When** provenance проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-08 — output hash не совпал
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_OUTPUT_HASH_MISMATCH · exit 10  
**Given** в twin изменён только output hash  
**When** provenance проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-09 — stdout digest не совпал
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_STDOUT_DIGEST_MISMATCH · exit 10  
**Given** в twin изменён только stdout digest  
**When** provenance проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-10 — stderr digest не совпал
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_STDERR_DIGEST_MISMATCH · exit 10  
**Given** в twin изменён только stderr digest  
**When** provenance проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-11 — captured category отсутствует
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_CATEGORY_MISSING · exit 10  
**Given** из twin удалена только captured category  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-12 — evidence coordinate отсутствует
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_EVIDENCE_COORDINATE_MISSING · exit 10  
**Given** из twin удалена только evidence coordinate  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HOLDER-13 — owner отсутствует
**Positive twin:** SDD-1-HOLDER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_HOLDER_OWNER_MISSING · exit 10  
**Given** из twin удалён только holder owner  
**When** manifest проверяется  
**Then** SUT возвращает RED.

#### SDD-1-BIRTH-01 — valid birth inversion
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** exact holder version проводит known-good input и краснеет на одном injected defect, а census содержит оба запуска  
**When** birth eligibility проверяется  
**Then** SUT признаёт holder born.

#### SDD-1-BIRTH-02 — known-good не проходит
**Positive twin:** SDD-1-BIRTH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_BIRTH_GOOD_INPUT_FAILED · exit 10  
**Given** в twin изменён только outcome known-good input на non-GREEN  
**When** birth eligibility проверяется  
**Then** SUT возвращает RED.

#### SDD-1-BIRTH-03 — injected defect не краснеет
**Positive twin:** SDD-1-BIRTH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_BIRTH_DEFECT_NOT_DETECTED · exit 10  
**Given** в twin изменён только outcome one-fact defect на GREEN  
**When** birth eligibility проверяется  
**Then** SUT возвращает RED.

#### SDD-1-BIRTH-04 — zero census объявлен GREEN
**Positive twin:** SDD-1-BIRTH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_BIRTH_ZERO_CENSUS · exit 10  
**Given** из twin удалены только birth-run entries, оставлен GREEN verdict  
**When** birth eligibility проверяется  
**Then** SUT возвращает RED.

### Hash invalidation, trace и evidence

#### SDD-1-HASH-01 — hashes и approvals актуальны
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** manifest hashes равны content hashes и каждый approval связан с exact subject  
**When** graph проверяется  
**Then** SUT принимает approvals.

#### SDD-1-HASH-02 — manifest hash подменён
**Positive twin:** SDD-1-HASH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CONTENT_HASH_MISMATCH · exit 10  
**Given** в twin изменён только manifest hash одного artifact  
**When** graph проверяется  
**Then** SUT возвращает RED.

#### SDD-1-HASH-03 — content обновлён, approval остался старым
**Positive twin:** SDD-1-HASH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_APPROVAL_SUBJECT_STALE · exit 10  
**Given** в twin изменён только subject content, review всё ещё связан со старым hash  
**When** graph проверяется  
**Then** SUT инвалидирует stale approval.

#### SDD-1-HASH-04 — acceptance change инвалидирует downstream
**Positive twin:** SDD-1-HASH-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_DOWNSTREAM_STALE_FROM_ACCEPTANCE · exit 10  
**Given** в twin изменён только acceptance content после downstream approvals  
**When** lifecycle проверяется  
**Then** SUT инвалидирует class exposure, design, tasks, RED и convergence.

#### SDD-1-HASH-05 — design change сохраняет initial analysis, но инвалидирует revalidation
**Positive twin:** SDD-1-CLASS-04  
**Holder type:** machine  
**Expected SUT:** RED · CG_DESIGN_REVALIDATION_STALE · exit 10  
**Given** в twin изменён только design content, initial acceptance-bound analysis сохранён  
**When** downstream validity проверяется  
**Then** SUT сохраняет initial history и инвалидирует revalidation и последующие stages.

#### SDD-1-TRACE-01 — exact-set trace совпадает
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** acceptance, design, tasks и evidence plan содержат один exact ID set  
**When** trace gate сравнивает множества  
**Then** SUT возвращает GREEN.

#### SDD-1-TRACE-02 — acceptance ID потерян downstream
**Positive twin:** SDD-1-TRACE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Given** из twin удалён только один acceptance ID из evidence plan  
**When** exact sets сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-TRACE-03 — orphan ID добавлен downstream
**Positive twin:** SDD-1-TRACE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Given** в twin добавлен только один несуществующий acceptance ID  
**When** exact sets сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-TRACE-04 — равное число, разные ID
**Positive twin:** SDD-1-TRACE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_SET_MISMATCH · exit 10  
**Given** в twin один downstream ID заменён другим, cardinality не изменилась  
**When** exact sets сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-TRACE-05 — несколько holders у одного ID
**Positive twin:** —  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** один acceptance ID имеет два независимо named required holders с отдельным evidence  
**When** trace gate сравнивает ID set и holder set  
**Then** SUT сохраняет оба holders и возвращает GREEN.

#### SDD-1-EVID-01 — все required holders GREEN
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** exact required holder set имеет captured GREEN outputs с valid provenance  
**When** evidence агрегируется  
**Then** SUT возвращает GREEN.

#### SDD-1-EVID-02 — negative SUT triple совпала с assertion
**Positive twin:** SDD-1-TRACE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Driver assertion:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Expected final holder:** GREEN · CASE_ASSERTION_MATCHED · exit 0  
**Given** case ожидает эту negative SUT triple и driver получает её точно  
**When** driver ассертит category, diagnostic и exit  
**Then** final holder verdict равен `GREEN · CASE_ASSERTION_MATCHED · 0`.

#### SDD-1-EVID-03 — required holder вернул RED
**Positive twin:** SDD-1-EVID-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_REQUIRED_HOLDER_RED · exit 10  
**Given** в twin изменён только один required holder outcome на RED  
**When** evidence агрегируется  
**Then** SUT возвращает RED.

#### SDD-1-EVID-04 — required holder NOT_EXECUTED
**Positive twin:** SDD-1-EVID-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_REQUIRED_HOLDER_NOT_EXECUTED · exit 20  
**Given** в twin изменён только один required holder outcome на NOT_EXECUTED  
**When** evidence агрегируется  
**Then** SUT возвращает NOT_EXECUTED.

#### SDD-1-EVID-05 — required holder output отсутствует
**Positive twin:** SDD-1-EVID-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_REQUIRED_HOLDER_OUTPUT_MISSING · exit 20  
**Given** из twin удалён только captured output одного required holder  
**When** evidence агрегируется  
**Then** SUT возвращает NOT_EXECUTED.

#### SDD-1-DRIVER-01 — assertion category не совпала
**Positive twin:** SDD-1-EVID-02  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_TRACE_ID_ORPHAN · exit 10  
**Driver assertion:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Expected final holder:** RED · CASE_ASSERTION_CATEGORY_MISMATCH · exit 10  
**Given** относительно twin actual SUT triple отличается от driver assertion только category GREEN вместо RED  
**When** driver сравнивает все три поля  
**Then** final holder возвращает RED с category-mismatch diagnostic.

#### SDD-1-DRIVER-02 — assertion diagnostic не совпал
**Positive twin:** SDD-1-EVID-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Driver assertion:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Expected final holder:** RED · CASE_ASSERTION_DIAGNOSTIC_MISMATCH · exit 10  
**Given** относительно twin actual SUT triple отличается от driver assertion только diagnostic  
**When** driver сравнивает все три поля  
**Then** final holder возвращает RED с diagnostic-mismatch diagnostic.

#### SDD-1-DRIVER-03 — assertion exit code не совпал
**Positive twin:** SDD-1-EVID-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_ORPHAN · exit 0  
**Driver assertion:** RED · CG_TRACE_ID_ORPHAN · exit 10  
**Expected final holder:** RED · CASE_ASSERTION_EXIT_MISMATCH · exit 10  
**Given** относительно twin actual SUT triple отличается от driver assertion только exit 0 вместо 10  
**When** driver сравнивает все три поля  
**Then** final holder возвращает RED с exit-mismatch diagnostic.

### Diff ownership, post-diff review и convergence

#### SDD-1-DIFF-01 — actual implementation diff exact-set принадлежит change
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** actual changed path/blob set равен approved implementation diff set одного change  
**When** diff-to-change gate сравнивает exact sets  
**Then** SUT возвращает GREEN.

#### SDD-1-DIFF-02 — changed path не принадлежит change
**Positive twin:** SDD-1-DIFF-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_DIFF_PATH_UNCLAIMED · exit 10  
**Given** в twin добавлен только один actual changed path вне approved set  
**When** diff-to-change gate сравнивает sets  
**Then** SUT возвращает RED.

#### SDD-1-DIFF-03 — claimed path отсутствует в actual diff
**Positive twin:** SDD-1-DIFF-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_DIFF_CLAIM_ORPHAN · exit 10  
**Given** в twin добавлен только один claimed path без actual change  
**When** diff-to-change gate сравнивает sets  
**Then** SUT возвращает RED.

#### SDD-1-DIFF-04 — path заявлен двумя active changes
**Positive twin:** SDD-1-DIFF-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_DIFF_OWNER_AMBIGUOUS · exit 10  
**Given** в twin только один path дополнительно заявлен вторым active change  
**When** ownership проверяется  
**Then** SUT возвращает RED.

#### SDD-1-DIFF-05 — final diff set отличается от reviewed set
**Positive twin:** SDD-1-DIFF-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_REVIEWED_DIFF_SET_MISMATCH · exit 10  
**Given** в twin изменён только один final blob относительно reviewed diff set  
**When** convergence eligibility проверяется  
**Then** SUT возвращает RED.

#### SDD-1-POST-01 — несколько specialist records хранятся раздельно
**Positive twin:** —  
**Holder type:** human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** два applicable roles имеют отдельные verified records `post-diff/<role>/<content-digest>.yaml` на один digest  
**When** aggregator сверяет exact role set  
**Then** SUT учитывает оба verdict и возвращает GREEN.

#### SDD-1-POST-02 — applicable specialist отсутствует
**Positive twin:** SDD-1-POST-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_POST_DIFF_REVIEW_MISSING · exit 10  
**Given** из twin удалён только record одного applicable role  
**When** aggregator сверяет exact role set  
**Then** SUT возвращает RED.

#### SDD-1-POST-03 — один specialist record перезаписал другой
**Positive twin:** SDD-1-POST-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_POST_DIFF_REVIEW_OVERWRITTEN · exit 10  
**Given** в twin изменена только coordinate второго role на файл первого role  
**When** aggregator проверяет ownership  
**Then** SUT возвращает RED.

#### SDD-1-POST-04 — distributed surface повторно reviewed system-design role
**Positive twin:** —  
**Holder type:** human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** final diff имеет distributed surface и отдельный post-diff system-design record на exact content digest  
**When** applicable reviews проверяются  
**Then** SUT возвращает GREEN.

#### SDD-1-POST-05 — distributed surface без повторного system-design review
**Positive twin:** SDD-1-POST-04  
**Holder type:** machine  
**Expected SUT:** RED · CG_SYSTEM_DESIGN_REREVIEW_MISSING · exit 10  
**Given** из twin удалён только post-diff system-design record  
**When** applicable reviews проверяются  
**Then** SUT возвращает RED.

#### SDD-1-POST-NA-01 — specialist review законно N/A
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** role applicability ссылается на registered predicate, evidence делает predicate false для change  
**When** post-diff role set агрегируется  
**Then** SUT принимает N/A.

#### SDD-1-POST-NA-02 — specialist N/A evidence ложно
**Positive twin:** SDD-1-POST-NA-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_POST_DIFF_NA_FALSE · exit 10  
**Given** в twin изменён только evidence fact так, что role predicate true  
**When** post-diff role set агрегируется  
**Then** SUT возвращает RED.

#### SDD-1-CONV-01 — convergence выдан единственным owner
**Positive twin:** —  
**Holder type:** human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** convergence-reviewer имеет verified event и record с exact change hashes, base/source SHAs и content digest  
**When** final convergence проверяется  
**Then** SUT возвращает GREEN.

#### SDD-1-CONV-02 — convergence выдан spoof owner
**Positive twin:** SDD-1-CONV-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_CONVERGENCE_OWNER_UNAUTHORIZED · exit 10  
**Given** в twin изменён только event actor на неразрешённого convergence-reviewer  
**When** final convergence проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CONV-03 — convergence external event отсутствует
**Positive twin:** SDD-1-CONV-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CONVERGENCE_EVENT_MISSING · exit 10  
**Given** из twin удалена только event coordinate  
**When** final convergence проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CONV-04 — convergence event API недоступен
**Positive twin:** SDD-1-CONV-01  
**Holder type:** human-external  
**Expected SUT:** NOT_EXECUTED · CG_CONVERGENCE_EVENT_UNAVAILABLE · exit 20  
**Given** в twin изменён только GitHub API response на unavailable  
**When** final convergence проверяется  
**Then** SUT возвращает NOT_EXECUTED.

#### SDD-1-CONV-05 — convergence record неполон
**Positive twin:** SDD-1-CONV-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CONVERGENCE_CONTENT_IDENTITY_MISSING · exit 10  
**Given** из twin удалён только source SHA одного repo  
**When** final convergence проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CONV-06 — specialist exact set полностью агрегирован
**Positive twin:** SDD-1-POST-01  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** convergence record ссылается на exact coordinates всех отдельных applicable specialist records  
**When** aggregator сравнивает role/record sets  
**Then** SUT возвращает GREEN.

#### SDD-1-CONV-07 — specialist record не вошёл в aggregator
**Positive twin:** SDD-1-CONV-06  
**Holder type:** machine  
**Expected SUT:** RED · CG_CONVERGENCE_SPECIALIST_SET_MISMATCH · exit 10  
**Given** из twin удалена только одна specialist coordinate из aggregator  
**When** role/record sets сравниваются  
**Then** SUT возвращает RED.

### Landing и terminal states

#### SDD-1-LAND-01 — squash сохраняет applied content
**Positive twin:** —  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** landed commit SHA новый, но canonical repo/path/mode/blob/deletion set равен convergence content digest  
**When** landing-reviewer проверяет applied content  
**Then** SUT разрешает LANDED и записывает новый landed SHA.

#### SDD-1-LAND-02 — squash изменил applied content
**Positive twin:** SDD-1-LAND-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_LANDED_CONTENT_DRIFT · exit 10  
**Given** в twin изменён только один landed blob  
**When** applied content проверяется  
**Then** SUT инвалидирует convergence и возвращает RED.

#### SDD-1-LAND-03 — commit SHA изменился без content drift
**Positive twin:** SDD-1-LAND-01  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** в twin изменён только commit SHA, canonical content set прежний  
**When** applied content проверяется  
**Then** SUT не объявляет verdict stale.

#### SDD-1-WITHDRAW-01 — active change отозван до landing
**Positive twin:** —  
**Holder type:** human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** authorized owner event содержит reason и subject digest active non-landed change  
**When** WITHDRAWN запрашивается  
**Then** SUT переводит change в terminal WITHDRAWN, сохраняя history.

#### SDD-1-WITHDRAW-02 — landed change пытаются отозвать
**Positive twin:** SDD-1-WITHDRAW-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_WITHDRAW_AFTER_LANDING · exit 10  
**Given** в twin изменён только source state на LANDED  
**When** WITHDRAWN запрашивается  
**Then** SUT возвращает RED.

#### SDD-1-WITHDRAW-03 — withdrawal без reason
**Positive twin:** SDD-1-WITHDRAW-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_WITHDRAW_REASON_MISSING · exit 10  
**Given** из twin удалён только reason  
**When** WITHDRAWN запрашивается  
**Then** SUT возвращает RED.

#### SDD-1-SUPER-01 — change superseded новым package
**Positive twin:** —  
**Holder type:** human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** authorized event связывает old active change и distinct successor с mutual links и новым evidence  
**When** SUPERSEDED запрашивается  
**Then** SUT закрывает old change и сохраняет оба histories.

#### SDD-1-SUPER-02 — successor отсутствует
**Positive twin:** SDD-1-SUPER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_SUPERSEDE_SUCCESSOR_MISSING · exit 10  
**Given** из twin удалена только successor coordinate  
**When** SUPERSEDED запрашивается  
**Then** SUT возвращает RED.

#### SDD-1-SUPER-03 — successor backlink отсутствует
**Positive twin:** SDD-1-SUPER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_SUPERSEDE_BACKLINK_MISSING · exit 10  
**Given** из twin удалён только successor backlink  
**When** SUPERSEDED запрашивается  
**Then** SUT возвращает RED.

#### SDD-1-SUPER-04 — supersede образует cycle
**Positive twin:** SDD-1-SUPER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_SUPERSEDE_CYCLE · exit 10  
**Given** в twin изменена только successor coordinate на ancestor  
**When** graph проверяется  
**Then** SUT возвращает RED.

#### SDD-1-SUPER-05 — successor повторно использует old evidence
**Positive twin:** SDD-1-SUPER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_SUPERSEDE_EVIDENCE_REUSED · exit 10  
**Given** в twin изменена только successor evidence coordinate на old subject-bound evidence  
**When** evidence provenance проверяется  
**Then** SUT возвращает RED.

### Policy, dual-DAG cutover и legacy census

#### SDD-1-POLICY-01 — policy содержит две repository coordinates
**Positive twin:** —  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** landing-reviewer записал schema version и отдельные существующие 40-hex cutover commits workspace и product  
**When** policy проверяется в соответствующих repos  
**Then** SUT возвращает GREEN.

#### SDD-1-POLICY-02 — workspace entry отсутствует
**Positive twin:** SDD-1-POLICY-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_POLICY_REPOSITORY_MISSING · exit 10  
**Given** из twin удалён только workspace repository entry  
**When** policy проверяется  
**Then** SUT возвращает RED.

#### SDD-1-POLICY-03 — cutover commit не 40 lowercase hex
**Positive twin:** SDD-1-POLICY-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CUTOVER_SHA_INVALID · exit 10  
**Given** в twin изменён только workspace cutover commit на невалидный lexical SHA  
**When** policy проверяется  
**Then** SUT возвращает RED.

#### SDD-1-POLICY-04 — valid-looking cutover commit не существует
**Positive twin:** SDD-1-POLICY-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CUTOVER_COMMIT_NOT_FOUND · exit 10  
**Given** в twin изменён только workspace cutover на 40-hex, для которого healthy GitHub API подтверждает absence  
**When** commit existence проверяется  
**Then** SUT возвращает RED.

#### SDD-1-POLICY-05 — cutover SHA взят из другого repo
**Positive twin:** SDD-1-POLICY-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CUTOVER_COMMIT_WRONG_REPOSITORY · exit 10  
**Given** в twin изменён только workspace cutover на существующий product SHA, отсутствующий в workspace DAG  
**When** repository binding проверяется  
**Then** SUT возвращает RED.

#### SDD-1-POLICY-06 — API commit lookup недоступен
**Positive twin:** SDD-1-POLICY-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_COMMIT_LOOKUP_UNAVAILABLE · exit 20  
**Given** в twin изменён только GitHub commit API response на unavailable  
**When** existence проверяется  
**Then** SUT возвращает NOT_EXECUTED, не NOT_FOUND.

#### SDD-1-DAG-01 — base до cutover идёт registered legacy route
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** candidate repo/base/head существуют в одном repo, base — ancestor cutover, change exact-set зарегистрирован route legacy  
**When** candidate классифицируется  
**Then** SUT разрешает legacy route.

#### SDD-1-DAG-02 — base ровно cutover и package присутствует
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** candidate base равен cutover_commit своего repo и valid package exact-mapped diff присутствует  
**When** candidate классифицируется  
**Then** SUT требует и принимает package.

#### SDD-1-DAG-03 — base ровно cutover без package
**Positive twin:** SDD-1-DAG-02  
**Holder type:** machine  
**Expected SUT:** RED · CG_PACKAGE_REQUIRED_AT_CUTOVER · exit 10  
**Given** из twin удалён только package  
**When** candidate классифицируется  
**Then** SUT возвращает RED.

#### SDD-1-DAG-04 — base после cutover и package присутствует
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** cutover_commit — ancestor candidate base своего repo и valid package присутствует  
**When** candidate классифицируется  
**Then** SUT принимает package route.

#### SDD-1-DAG-05 — base после cutover без package
**Positive twin:** SDD-1-DAG-04  
**Holder type:** machine  
**Expected SUT:** RED · CG_PACKAGE_REQUIRED_AFTER_CUTOVER · exit 10  
**Given** из twin удалён только package  
**When** candidate классифицируется  
**Then** SUT возвращает RED.

#### SDD-1-DAG-06 — base и cutover histories incomparable
**Positive twin:** SDD-1-DAG-04  
**Holder type:** machine  
**Expected SUT:** RED · CG_CUTOVER_HISTORY_INCOMPARABLE · exit 10  
**Given** в twin изменён только candidate base на существующий commit incomparable с cutover  
**When** ancestry проверяется  
**Then** SUT возвращает RED.

#### SDD-1-DAG-07 — candidate head ref недоступен
**Positive twin:** SDD-1-DAG-04  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_CANDIDATE_REF_UNAVAILABLE · exit 20  
**Given** в twin изменён только head ref lookup на unavailable  
**When** candidate проверяется  
**Then** SUT возвращает NOT_EXECUTED.

#### SDD-1-DAG-08 — candidate repo identity не совпала с commits
**Positive twin:** SDD-1-DAG-04  
**Holder type:** machine  
**Expected SUT:** RED · CG_CANDIDATE_REPOSITORY_MISMATCH · exit 10  
**Given** в twin изменена только repo identity на repo, которому base/head не принадлежат  
**When** repository binding проверяется  
**Then** SUT возвращает RED.

#### SDD-1-DAG-09 — bootstrap #480 на собственной cutover boundary
**Positive twin:** —  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** SDD-1/#480 landing является recorded bootstrap и создаёт cutover coordinates без self-package  
**When** ровно эта boundary проверяется  
**Then** SUT применяет единственное bootstrap-исключение.

#### SDD-1-DAG-10 — иной change просит bootstrap на boundary
**Positive twin:** SDD-1-DAG-09  
**Holder type:** machine  
**Expected SUT:** RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10  
**Given** в twin изменена только change coordinate с #480 на другой change  
**When** boundary проверяется без package  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-01 — independent census snapshot полон
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** independent producer captured open PRs обоих repos и live in-progress Issues с exact queries, ETag/revision, timestamp и response digest  
**When** census artifact проверяется  
**Then** SUT возвращает GREEN.

#### SDD-1-CENSUS-02 — census API недоступен
**Positive twin:** SDD-1-CENSUS-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_CENSUS_PRODUCER_UNAVAILABLE · exit 20  
**Given** в twin изменён только GitHub API outcome на unavailable  
**When** census строится  
**Then** SUT возвращает NOT_EXECUTED.

#### SDD-1-CENSUS-03 — census snapshot stale
**Positive twin:** SDD-1-CENSUS-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CENSUS_STALE · exit 10  
**Given** в twin изменён только timestamp за пределы versioned freshness predicate  
**When** census проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-04 — product PR query отсутствует
**Positive twin:** SDD-1-CENSUS-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10  
**Given** из twin удалён только product open-PR query/result  
**When** census coverage проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-05 — workspace PR query отсутствует
**Positive twin:** SDD-1-CENSUS-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10  
**Given** из twin удалён только workspace open-PR query/result  
**When** census coverage проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-06 — in-progress Issue query отсутствует
**Positive twin:** SDD-1-CENSUS-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10  
**Given** из twin удалён только live in-progress Issue query/result  
**When** census coverage проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-07 — policy legacy registry exact-set совпал
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** каждая snapshot coordinate имеет ровно один issue, acceptance path и route в policy и лишних entries нет  
**When** registry и census exact sets сравниваются  
**Then** SUT возвращает GREEN.

#### SDD-1-CENSUS-08 — active legacy change пропущен
**Positive twin:** SDD-1-CENSUS-07  
**Holder type:** machine  
**Expected SUT:** RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10  
**Given** из twin удалён только один active snapshot change из policy registry  
**When** exact sets сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-09 — inactive change лишний в registry
**Positive twin:** SDD-1-CENSUS-07  
**Holder type:** machine  
**Expected SUT:** RED · CG_LEGACY_REGISTRY_EXTRA_ENTRY · exit 10  
**Given** в twin добавлен только один absent-from-snapshot registry entry  
**When** exact sets сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-10 — unchanged legacy contract продолжает legacy route
**Positive twin:** —  
**Holder type:** machine+human-external  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** registered active legacy acceptance hash и observable contract не изменились после cutover  
**When** route legacy проверяется  
**Then** SUT возвращает GREEN.

#### SDD-1-CENSUS-11 — legacy contract изменён после cutover
**Positive twin:** SDD-1-CENSUS-10  
**Holder type:** machine  
**Expected SUT:** RED · CG_LEGACY_CONTRACT_CHANGED · exit 10  
**Given** в twin изменён только acceptance observable contract hash  
**When** route legacy проверяется  
**Then** SUT требует migration и возвращает RED.

#### SDD-1-CENSUS-12 — explicit migration имеет package
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** registry route изменён на migrate и valid Change Graph package exact-maps candidate diff  
**When** migrated legacy change проверяется  
**Then** SUT возвращает GREEN.

#### SDD-1-CENSUS-13 — explicit migration без package
**Positive twin:** SDD-1-CENSUS-12  
**Holder type:** machine  
**Expected SUT:** RED · CG_MIGRATION_PACKAGE_MISSING · exit 10  
**Given** из twin удалён только package  
**When** migrated legacy change проверяется  
**Then** SUT возвращает RED.

#### SDD-1-CENSUS-14 — closed historical acceptance не backfill-ится
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** acceptance закрыт до census и отсутствует среди open PR/live in-progress snapshot  
**When** migration scope проверяется  
**Then** SUT не требует package или registry entry.

### Tracked adapter

#### SDD-1-ADAPTER-01 — deterministic regeneration совпала побайтно
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** `.claude/adapters.yaml` exact-list-ит owned outputs, temp regeneration из canonical inputs побайтно равна tracked outputs  
**When** adapter gate сравнивает exact set и bytes  
**Then** SUT возвращает GREEN.

#### SDD-1-ADAPTER-02 — tracked generated output drift
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CGA_DERIVED_DRIFT · exit 10  
**Given** в twin изменён только один byte tracked adapter-owned output  
**When** temp regeneration сравнивается  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-03 — nested asset manifest skill потерян
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_NESTED_ASSET_MISSING · exit 10  
**Given** из twin удалён только один nested asset/reference/script полного `.agents/skills/<name>/**` package  
**When** exact package set сравнивается  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-04 — foreign runtime package вне manifest сохранён
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** рядом существует foreign runtime package, которого нет среди adapter-owned outputs в manifest  
**When** temp regeneration и drift проверяются  
**Then** SUT не удаляет и не считает package output, но всё равно проверяет owned exact set.

#### SDD-1-ADAPTER-05 — extra adapter-owned output
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_OWNED_OUTPUT_EXTRA · exit 10  
**Given** в twin добавлен только один tracked output в owned namespace, отсутствующий в manifest exact set  
**When** output set сравнивается  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-06 — manifest-owned output отсутствует
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_OWNED_OUTPUT_MISSING · exit 10  
**Given** из twin удалён только один manifest-owned tracked output  
**When** output set сравнивается  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-07 — design предлагает только untracked outputs
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** human-external  
**Expected SUT:** RED · CG_ADAPTER_OUTPUTS_MUST_BE_TRACKED · exit 10  
**Given** в twin изменено только design decision с tracked outputs на runtime/untracked-only  
**When** design semantics reviewed  
**Then** human holder и SUT отвергают design.

#### SDD-1-ADAPTER-08 — canonical path использует uppercase `.Claude`
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_CANONICAL_CASE_INVALID · exit 10  
**Given** в twin изменён только один canonical path с `.claude` на uppercase variant  
**When** canonical coordinates проверяются  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-09 — generated artifact содержит absolute path
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_PATH_NOT_PORTABLE · exit 10  
**Given** в twin изменена только одна generated coordinate на machine-absolute path  
**When** portability проверяется  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-10 — adapter читает noncanonical input
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_INPUT_NOT_CANONICAL · exit 10  
**Given** в twin добавлен только один input вне root `CLAUDE.md` и tracked `.claude/{adapters.yaml,agents,hooks,rules,skills,settings.json}`  
**When** input ownership проверяется  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-11 — regeneration nondeterministic
**Positive twin:** SDD-1-ADAPTER-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_ADAPTER_NONDETERMINISTIC · exit 10  
**Given** в twin изменён только второй regeneration output при тех же input hashes  
**When** два temp runs сравниваются  
**Then** SUT возвращает RED.

#### SDD-1-ADAPTER-12 — current nested variants сохранены
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** manifest skills включают полные packages с `audit-round.workflow.js`, `EXAMPLES` и Obsidian references/assets/scripts по фактическому дереву  
**When** nested package census сравнивается с regeneration  
**Then** SUT возвращает GREEN.

#### SDD-1-ADAPTER-13 — foreign package не маскирует owned drift
**Positive twin:** SDD-1-ADAPTER-04  
**Holder type:** machine  
**Expected SUT:** RED · CGA_DERIVED_DRIFT · exit 10  
**Given** в twin с неизменным foreign package изменён только один byte adapter-owned tracked output  
**When** temp regeneration сравнивается  
**Then** отдельный `adapter-contract` holder возвращает RED, не исключая drift-check.

### Authoritative callers и advisory hooks

#### SDD-1-WIRE-01 — exact authoritative caller set присутствует
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** blocking gate вызывают ровно workspace/product `scripts/hooks/pre-push` и `.github/workflows/ci.yaml`  
**When** caller exact set проверяется  
**Then** SUT возвращает GREEN.

#### SDD-1-WIRE-02 — workspace pre-push не вызывает gate
**Positive twin:** SDD-1-WIRE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CALLER_WORKSPACE_PRE_PUSH_MISSING · exit 10  
**Given** из twin удалён только вызов из workspace `scripts/hooks/pre-push`  
**When** caller exact set проверяется  
**Then** SUT возвращает RED.

#### SDD-1-WIRE-03 — workspace CI не вызывает gate
**Positive twin:** SDD-1-WIRE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CALLER_WORKSPACE_CI_MISSING · exit 10  
**Given** из twin удалён только вызов из workspace `.github/workflows/ci.yaml`  
**When** caller exact set проверяется  
**Then** SUT возвращает RED.

#### SDD-1-WIRE-04 — product pre-push не вызывает gate
**Positive twin:** SDD-1-WIRE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CALLER_PRODUCT_PRE_PUSH_MISSING · exit 10  
**Given** из twin удалён только вызов из `project/kacho/scripts/hooks/pre-push`  
**When** caller exact set проверяется  
**Then** SUT возвращает RED.

#### SDD-1-WIRE-05 — product CI не вызывает gate
**Positive twin:** SDD-1-WIRE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_CALLER_PRODUCT_CI_MISSING · exit 10  
**Given** из twin удалён только вызов из `project/kacho/.github/workflows/ci.yaml`  
**When** caller exact set проверяется  
**Then** SUT возвращает RED.

#### SDD-1-WSPP-01 — workspace pre-push получает полные coordinates
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** workspace pre-push читает remote/local SHAs из stdin и передаёт workspace identity/base/head и sibling product coordinates  
**When** valid graph push проверяется  
**Then** caller пропускает push.

#### SDD-1-WSPP-02 — workspace pre-push блокирует injected defect
**Positive twin:** SDD-1-WSPP-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Given** из package tasks mapping twin удалён только один существующий acceptance case ID  
**When** реальный workspace pre-push вызывается  
**Then** caller блокирует push с exit 10 и сохраняет underlying `CG_TRACE_ID_MISSING`.

#### SDD-1-WSPP-03 — sibling product repo отсутствует
**Positive twin:** SDD-1-WSPP-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING · exit 20  
**Given** в twin удалён только sibling product repo  
**When** workspace pre-push вызывается  
**Then** caller возвращает NOT_EXECUTED и блокирует push.

#### SDD-1-WSPP-04 — stdin remote SHA отсутствует
**Positive twin:** SDD-1-WSPP-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRE_PUSH_REMOTE_REF_MISSING · exit 20  
**Given** из twin удалён только remote SHA во входной stdin ref line  
**When** workspace pre-push вызывается  
**Then** caller возвращает NOT_EXECUTED и блокирует push.

#### SDD-1-WSCI-01 — workspace CI передаёт оба repo contexts
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** workspace CI передаёт identity/base/head workspace и существующие sibling product coordinates  
**When** valid graph job выполняется  
**Then** caller завершает job GREEN.

#### SDD-1-WSCI-02 — workspace CI блокирует injected defect
**Positive twin:** SDD-1-WSCI-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Given** из package tasks mapping twin удалён только один существующий acceptance case ID  
**When** реальный workspace CI job выполняется  
**Then** caller блокирует job с exit 10 и сохраняет underlying `CG_TRACE_ID_MISSING`.

#### SDD-1-WSCI-03 — product coordinate в workspace CI отсутствует
**Positive twin:** SDD-1-WSCI-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_WORKSPACE_CI_PRODUCT_COORDINATE_MISSING · exit 20  
**Given** из twin удалена только sibling product coordinate  
**When** workspace CI job выполняется  
**Then** caller возвращает NOT_EXECUTED и блокирует job.

#### SDD-1-WSCI-04 — workspace base ref недоступен
**Positive twin:** SDD-1-WSCI-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE · exit 20  
**Given** в twin изменён только base ref lookup на unavailable  
**When** workspace CI job выполняется  
**Then** caller возвращает NOT_EXECUTED и блокирует job.

#### SDD-1-PPRE-01 — product pre-push получает полные coordinates
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** product pre-push читает remote/local SHAs из stdin и получает sibling workspace с pinned policy  
**When** valid graph push проверяется  
**Then** caller пропускает push.

#### SDD-1-PPRE-02 — product pre-push блокирует injected defect
**Positive twin:** SDD-1-PPRE-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Given** из package tasks mapping twin удалён только один существующий acceptance case ID  
**When** реальный product pre-push вызывается  
**Then** caller блокирует push с exit 10 и сохраняет underlying `CG_TRACE_ID_MISSING`.

#### SDD-1-PPRE-03 — sibling workspace repo отсутствует
**Positive twin:** SDD-1-PPRE-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRODUCT_PRE_PUSH_WORKSPACE_REPO_MISSING · exit 20  
**Given** в twin удалён только sibling workspace repo  
**When** product pre-push вызывается  
**Then** caller возвращает NOT_EXECUTED и блокирует push.

#### SDD-1-PPRE-04 — stdin local SHA отсутствует
**Positive twin:** SDD-1-PPRE-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRE_PUSH_LOCAL_REF_MISSING · exit 20  
**Given** из twin удалён только local SHA во входной stdin ref line  
**When** product pre-push вызывается  
**Then** caller возвращает NOT_EXECUTED и блокирует push.

#### SDD-1-PCI-01 — product CI использует pinned public workspace
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** product ledger содержит change_id и pinned workspace_revision, CI fetches public workspace на ней и берёт product base/head из GitHub event  
**When** valid graph job выполняется  
**Then** caller завершает job GREEN.

#### SDD-1-PCI-02 — product CI блокирует injected defect
**Positive twin:** SDD-1-PCI-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_TRACE_ID_MISSING · exit 10  
**Given** из package tasks mapping twin удалён только один существующий acceptance case ID  
**When** реальный product CI job выполняется  
**Then** caller блокирует job с exit 10 и сохраняет underlying `CG_TRACE_ID_MISSING`.

#### SDD-1-PCI-03 — public workspace fetch недоступен
**Positive twin:** SDD-1-PCI-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_FETCH_UNAVAILABLE · exit 20  
**Given** в twin изменён только fetch outcome на unavailable  
**When** product CI job выполняется  
**Then** caller возвращает NOT_EXECUTED и блокирует job.

#### SDD-1-PCI-04 — pinned workspace revision недоступна
**Positive twin:** SDD-1-PCI-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_REVISION_UNAVAILABLE · exit 20  
**Given** в twin изменена только pinned revision на unavailable ref  
**When** product CI job выполняется  
**Then** caller возвращает NOT_EXECUTED и блокирует job.

#### SDD-1-PCI-05 — GitHub event не содержит product base
**Positive twin:** SDD-1-PCI-01  
**Holder type:** machine  
**Expected SUT:** NOT_EXECUTED · CG_PRODUCT_CI_BASE_REF_MISSING · exit 20  
**Given** из twin удалён только product base SHA в GitHub event  
**When** product CI job выполняется  
**Then** caller возвращает NOT_EXECUTED и блокирует job.

#### SDD-1-PCI-06 — product ledger не содержит change_id
**Positive twin:** SDD-1-PCI-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_PRODUCT_LEDGER_CHANGE_ID_MISSING · exit 10  
**Given** из twin удалён только change_id  
**When** product ledger проверяется  
**Then** SUT возвращает RED.

#### SDD-1-ADV-01 — advisory hook зелёный, authority зелёная
**Positive twin:** —  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** advisory hook сообщает GREEN и все четыре authoritative callers независимо получают valid graph  
**When** verdict агрегируется  
**Then** SUT возвращает GREEN только по authoritative evidence.

#### SDD-1-ADV-02 — advisory hook зелёный, authority находит defect
**Positive twin:** SDD-1-ADV-01  
**Holder type:** machine  
**Expected SUT:** RED · CG_AUTHORITATIVE_GATE_BLOCKED · exit 10  
**Given** в twin изменён только один graph fact, advisory outcome оставлен GREEN  
**When** authoritative caller выполняется  
**Then** SUT возвращает RED.

#### SDD-1-ADV-03 — advisory hook отсутствует, authority зелёная
**Positive twin:** SDD-1-ADV-01  
**Holder type:** machine  
**Expected SUT:** GREEN · CG_OK · exit 0  
**Given** из twin удалён только advisory hook, authoritative inputs неизменны  
**When** verdict агрегируется  
**Then** SUT возвращает GREEN.

## 14. Holder matrix

Каждый row — самостоятельная fixture с one-fact delta относительно указанного
positive twin. `Subject holder` называет holder проверяемого предмета; сам
case-assertion всегда принадлежит integration-tester и исполняется pre-RED
driver. Planned records находятся внутри fixture и моделируют будущие package
coordinates, не утверждая, что production-файлы уже существуют.

До появления соответствующей SUT capability каждый row обязан дать initial
holder `RED · CASE_CAPABILITY_MISSING · exit 10`. После implementation driver
сравнивает actual SUT triple с driver assertion и при exact совпадении даёт
final holder `GREEN · CASE_ASSERTION_MATCHED · exit 0`. Три `DRIVER-*` birth
fixtures меняют ровно одно поле actual triple и ожидают final holder RED;
остальные expected SUT RED/NOT_EXECUTED являются ожидаемым поведением fixture,
а не красным тестом.

| Case ID | Positive twin | Subject holder | Fixture coordinate | Planned holder coordinate | Driver command | Driver assertion | Expected actual SUT category · diagnostic · exit | Expected final holder | Expected initial holder |
|---|---|---|---|---|---|---|---|---|---|
| SDD-1-BOOT-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-01/evidence/SDD-1-BOOT-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BOOT-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-BOOT-02 | SDD-1-BOOT-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BOOT-02/evidence/SDD-1-BOOT-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BOOT-02 | RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10 | RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-02 | SDD-1-REVIEW-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-02/evidence/SDD-1-REVIEW-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-02 | RED · CG_ACCEPTANCE_SUBJECT_MUTATED · exit 10 | RED · CG_ACCEPTANCE_SUBJECT_MUTATED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-03 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-03/evidence/SDD-1-REVIEW-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-03 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-04 | SDD-1-REVIEW-03 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-04/evidence/SDD-1-REVIEW-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-04 | RED · CG_REVIEW_HISTORY_MUTATED · exit 10 | RED · CG_REVIEW_HISTORY_MUTATED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-05 | SDD-1-REVIEW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-05/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-05/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-05 | RED · CG_BOOTSTRAP_ACTOR_NOT_ADMIN · exit 10 | RED · CG_BOOTSTRAP_ACTOR_NOT_ADMIN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-06 | SDD-1-REVIEW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-06/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-06/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-06 | RED · CG_BOOTSTRAP_ACTOR_SPOOFED · exit 10 | RED · CG_BOOTSTRAP_ACTOR_SPOOFED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-07 | SDD-1-REVIEW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-07/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-07/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-07 | RED · CG_BOOTSTRAP_ISSUE_MISMATCH · exit 10 | RED · CG_BOOTSTRAP_ISSUE_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-08 | SDD-1-REVIEW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-08/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-08/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-08 | NOT_EXECUTED · CG_BOOTSTRAP_PERMISSION_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_BOOTSTRAP_PERMISSION_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-09 | SDD-1-REVIEW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-09/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-09/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-09 | NOT_EXECUTED · CG_BOOTSTRAP_EVENT_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_BOOTSTRAP_EVENT_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-REVIEW-10 | SDD-1-REVIEW-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-REVIEW-10/evidence/SDD-1-REVIEW-10.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-REVIEW-10 | RED · CG_BOOTSTRAP_AUTHORITY_EXPIRED · exit 10 | RED · CG_BOOTSTRAP_AUTHORITY_EXPIRED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-02 | SDD-1-AUTH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-02/evidence/SDD-1-AUTH-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-02 | RED · CG_REVIEW_EVENT_MISSING · exit 10 | RED · CG_REVIEW_EVENT_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-03 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-03/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-03/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-03 | RED · CG_REVIEW_ACTOR_UNAUTHORIZED · exit 10 | RED · CG_REVIEW_ACTOR_UNAUTHORIZED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-04 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-04/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-04/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-04 | RED · CG_REVIEW_BODY_DIGEST_MISMATCH · exit 10 | RED · CG_REVIEW_BODY_DIGEST_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-05 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-05/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-05/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-05 | RED · CG_REVIEW_SUBJECT_DIGEST_MISMATCH · exit 10 | RED · CG_REVIEW_SUBJECT_DIGEST_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-06 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-06/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-06/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-06 | RED · CG_REVIEW_EVENT_IDENTITY_MISSING · exit 10 | RED · CG_REVIEW_EVENT_IDENTITY_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-07 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-07/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-07/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-07 | RED · CG_REVIEW_ROLE_UNAUTHORIZED · exit 10 | RED · CG_REVIEW_ROLE_UNAUTHORIZED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-AUTH-08 | SDD-1-AUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-08/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-AUTH-08/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-AUTH-08 | NOT_EXECUTED · CG_REVIEW_API_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_REVIEW_API_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-02 | SDD-1-TRUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-02/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-02/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-02 | RED · CG_HUMAN_TRUTH_DUPLICATION · exit 10 | RED · CG_HUMAN_TRUTH_DUPLICATION · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-03 | SDD-1-TRUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-03/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-03/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-03 | RED · CG_HUMAN_TRUTH_CONFLICT · exit 10 | RED · CG_HUMAN_TRUTH_CONFLICT · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-04 | SDD-1-TRUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-04/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-04/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-04 | RED · CG_HUMAN_TASKS_TRACKER · exit 10 | RED · CG_HUMAN_TASKS_TRACKER · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-05 | SDD-1-TRUTH-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-05/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-05/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-05 | RED · CG_HUMAN_MANIFEST_PROSE · exit 10 | RED · CG_HUMAN_MANIFEST_PROSE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRUTH-06 | SDD-1-TRUTH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRUTH-06/evidence/SDD-1-TRUTH-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRUTH-06 | RED · CG_HUMAN_HOLDER_REQUIRED · exit 10 | RED · CG_HUMAN_HOLDER_REQUIRED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LIFE-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-01/evidence/SDD-1-LIFE-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LIFE-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LIFE-02 | SDD-1-LIFE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-02/evidence/SDD-1-LIFE-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LIFE-02 | RED · CG_LIFECYCLE_TRANSITION_INVALID · exit 10 | RED · CG_LIFECYCLE_TRANSITION_INVALID · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LIFE-03 | SDD-1-LIFE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LIFE-03/evidence/SDD-1-LIFE-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LIFE-03 | RED · CG_REQUIRED_ARTIFACT_MISSING · exit 10 | RED · CG_REQUIRED_ARTIFACT_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NONEMPTY-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-01/evidence/SDD-1-NONEMPTY-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NONEMPTY-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NONEMPTY-02 | SDD-1-NONEMPTY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-02/evidence/SDD-1-NONEMPTY-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NONEMPTY-02 | RED · CG_ACCEPTANCE_IDS_EMPTY · exit 10 | RED · CG_ACCEPTANCE_IDS_EMPTY · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NONEMPTY-03 | SDD-1-NONEMPTY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-03/evidence/SDD-1-NONEMPTY-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NONEMPTY-03 | RED · CG_REQUIRED_HOLDERS_EMPTY · exit 10 | RED · CG_REQUIRED_HOLDERS_EMPTY · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NONEMPTY-04 | SDD-1-NONEMPTY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NONEMPTY-04/evidence/SDD-1-NONEMPTY-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NONEMPTY-04 | RED · CG_HOLDER_SUBJECT_MISSING · exit 10 | RED · CG_HOLDER_SUBJECT_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-02 | SDD-1-CLASS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-02/evidence/SDD-1-CLASS-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-02 | RED · CG_CLASS_INITIAL_MISSING · exit 10 | RED · CG_CLASS_INITIAL_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-03 | SDD-1-CLASS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-03/evidence/SDD-1-CLASS-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-03 | RED · CG_CLASS_INITIAL_STALE · exit 10 | RED · CG_CLASS_INITIAL_STALE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-04 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-04/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-04/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-04 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-05 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-05/evidence/SDD-1-CLASS-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-05 | RED · CG_CLASS_ITEM_UNMAPPED · exit 10 | RED · CG_CLASS_ITEM_UNMAPPED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-06 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-06/evidence/SDD-1-CLASS-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-06 | RED · CG_CLASS_REVALIDATION_MISSING · exit 10 | RED · CG_CLASS_REVALIDATION_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-07 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-07/evidence/SDD-1-CLASS-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-07 | RED · CG_CLASS_REVALIDATION_STALE · exit 10 | RED · CG_CLASS_REVALIDATION_STALE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-08 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-08/evidence/SDD-1-CLASS-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-08 | RED · CG_CLASS_NEW_EXTERNAL_CALL · exit 10 | RED · CG_CLASS_NEW_EXTERNAL_CALL · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-09 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-09/evidence/SDD-1-CLASS-09.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-09 | RED · CG_CLASS_NEW_ASYNC_PATH · exit 10 | RED · CG_CLASS_NEW_ASYNC_PATH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CLASS-10 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CLASS-10/evidence/SDD-1-CLASS-10.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CLASS-10 | RED · CG_CLASS_NEW_SENTINEL · exit 10 | RED · CG_CLASS_NEW_SENTINEL · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DESIGN-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DESIGN-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DESIGN-02 | SDD-1-DESIGN-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-02/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-02/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DESIGN-02 | RED · CG_DESIGN_DECISION_OPEN · exit 10 | RED · CG_DESIGN_DECISION_OPEN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DESIGN-03 | SDD-1-DESIGN-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DESIGN-03/evidence/SDD-1-DESIGN-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DESIGN-03 | RED · CG_PRECODE_REVIEW_MISSING · exit 10 | RED · CG_PRECODE_REVIEW_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NA-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NA-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-NA-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-01/evidence/SDD-1-NA-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NA-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NA-02 | SDD-1-NA-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NA-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-NA-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-02/evidence/SDD-1-NA-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NA-02 | RED · CG_NA_PREDICATE_UNREGISTERED · exit 10 | RED · CG_NA_PREDICATE_UNREGISTERED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-NA-03 | SDD-1-NA-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-NA-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-NA-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-NA-03/evidence/SDD-1-NA-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-NA-03 | RED · CG_NA_PREDICATE_FALSE · exit 10 | RED · CG_NA_PREDICATE_FALSE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TASKS-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TASKS-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TASKS-02 | SDD-1-TASKS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-02/evidence/SDD-1-TASKS-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TASKS-02 | RED · CG_WRITING_PLANS_HANDOFF_MISSING · exit 10 | RED · CG_WRITING_PLANS_HANDOFF_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TASKS-03 | SDD-1-TASKS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TASKS-03/evidence/SDD-1-TASKS-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TASKS-03 | RED · CG_TASKS_BEFORE_DESIGN_APPROVAL · exit 10 | RED · CG_TASKS_BEFORE_DESIGN_APPROVAL · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-01/evidence/SDD-1-TDD-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-02 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-02/evidence/SDD-1-TDD-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-02 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-03 | SDD-1-TDD-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-03/evidence/SDD-1-TDD-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-03 | RED · CG_RED_PROOF_UNEXPECTED_GREEN · exit 10 | RED · CG_RED_PROOF_UNEXPECTED_GREEN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-04 | SDD-1-TDD-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-04/evidence/SDD-1-TDD-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-04 | RED · CG_RED_PROOF_NOT_EXECUTED · exit 10 | RED · CG_RED_PROOF_NOT_EXECUTED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-05 | SDD-1-TDD-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-05/evidence/SDD-1-TDD-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-05 | RED · CG_RED_PROOF_INFRA_FAILURE · exit 10 | RED · CG_RED_PROOF_INFRA_FAILURE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-06 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-06/evidence/SDD-1-TDD-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-06 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-07 | SDD-1-TDD-06 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-07/evidence/SDD-1-TDD-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-07 | RED · CG_IMPLEMENTATION_BEFORE_RED · exit 10 | RED · CG_IMPLEMENTATION_BEFORE_RED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-08 | SDD-1-TDD-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-08/evidence/SDD-1-TDD-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-08 | RED · CG_TEST_HARNESS_CONTAINS_IMPLEMENTATION · exit 10 | RED · CG_TEST_HARNESS_CONTAINS_IMPLEMENTATION · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-09 | SDD-1-TDD-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-09/evidence/SDD-1-TDD-09.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-09 | RED · CG_TEST_HARNESS_MASKS_CAPABILITY · exit 10 | RED · CG_TEST_HARNESS_MASKS_CAPABILITY · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TDD-10 | SDD-1-TDD-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-TDD-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-10/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TDD-10/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TDD-10 | RED · CG_TEST_DIFF_OWNER_INVALID · exit 10 | RED · CG_TEST_DIFF_OWNER_INVALID · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-01/evidence/SDD-1-HOLDER-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-02 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-02/evidence/SDD-1-HOLDER-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-02 | RED · CG_HOLDER_ID_MISSING · exit 10 | RED · CG_HOLDER_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-03 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-03/evidence/SDD-1-HOLDER-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-03 | RED · CG_HOLDER_EXECUTABLE_TRIVIAL · exit 10 | RED · CG_HOLDER_EXECUTABLE_TRIVIAL · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-04 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-04/evidence/SDD-1-HOLDER-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-04 | RED · CG_HOLDER_EXECUTABLE_UNKNOWN · exit 10 | RED · CG_HOLDER_EXECUTABLE_UNKNOWN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-05 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-05/evidence/SDD-1-HOLDER-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-05 | RED · CG_HOLDER_PREDICATE_MISSING · exit 10 | RED · CG_HOLDER_PREDICATE_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-06 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-06/evidence/SDD-1-HOLDER-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-06 | RED · CG_HOLDER_SUBJECT_HASH_MISMATCH · exit 10 | RED · CG_HOLDER_SUBJECT_HASH_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-07 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-07/evidence/SDD-1-HOLDER-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-07 | RED · CG_HOLDER_INPUT_HASH_MISMATCH · exit 10 | RED · CG_HOLDER_INPUT_HASH_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-08 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-08/evidence/SDD-1-HOLDER-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-08 | RED · CG_HOLDER_OUTPUT_HASH_MISMATCH · exit 10 | RED · CG_HOLDER_OUTPUT_HASH_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-09 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-09/evidence/SDD-1-HOLDER-09.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-09 | RED · CG_HOLDER_STDOUT_DIGEST_MISMATCH · exit 10 | RED · CG_HOLDER_STDOUT_DIGEST_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-10 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-10/evidence/SDD-1-HOLDER-10.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-10 | RED · CG_HOLDER_STDERR_DIGEST_MISMATCH · exit 10 | RED · CG_HOLDER_STDERR_DIGEST_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-11 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-11/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-11/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-11/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-11/evidence/SDD-1-HOLDER-11.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-11 | RED · CG_HOLDER_CATEGORY_MISSING · exit 10 | RED · CG_HOLDER_CATEGORY_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-12 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-12/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-12/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-12/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-12/evidence/SDD-1-HOLDER-12.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-12 | RED · CG_HOLDER_EVIDENCE_COORDINATE_MISSING · exit 10 | RED · CG_HOLDER_EVIDENCE_COORDINATE_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HOLDER-13 | SDD-1-HOLDER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-13/ | scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-13/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-13/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HOLDER-13/evidence/SDD-1-HOLDER-13.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HOLDER-13 | RED · CG_HOLDER_OWNER_MISSING · exit 10 | RED · CG_HOLDER_OWNER_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-BIRTH-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-01/evidence/SDD-1-BIRTH-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BIRTH-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-BIRTH-02 | SDD-1-BIRTH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-02/evidence/SDD-1-BIRTH-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BIRTH-02 | RED · CG_BIRTH_GOOD_INPUT_FAILED · exit 10 | RED · CG_BIRTH_GOOD_INPUT_FAILED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-BIRTH-03 | SDD-1-BIRTH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-03/evidence/SDD-1-BIRTH-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BIRTH-03 | RED · CG_BIRTH_DEFECT_NOT_DETECTED · exit 10 | RED · CG_BIRTH_DEFECT_NOT_DETECTED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-BIRTH-04 | SDD-1-BIRTH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-BIRTH-04/evidence/SDD-1-BIRTH-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-BIRTH-04 | RED · CG_BIRTH_ZERO_CENSUS · exit 10 | RED · CG_BIRTH_ZERO_CENSUS · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HASH-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-01/evidence/SDD-1-HASH-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HASH-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HASH-02 | SDD-1-HASH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-02/evidence/SDD-1-HASH-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HASH-02 | RED · CG_CONTENT_HASH_MISMATCH · exit 10 | RED · CG_CONTENT_HASH_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HASH-03 | SDD-1-HASH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-03/evidence/SDD-1-HASH-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HASH-03 | RED · CG_APPROVAL_SUBJECT_STALE · exit 10 | RED · CG_APPROVAL_SUBJECT_STALE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HASH-04 | SDD-1-HASH-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-04/evidence/SDD-1-HASH-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HASH-04 | RED · CG_DOWNSTREAM_STALE_FROM_ACCEPTANCE · exit 10 | RED · CG_DOWNSTREAM_STALE_FROM_ACCEPTANCE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-HASH-05 | SDD-1-CLASS-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-HASH-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-HASH-05/evidence/SDD-1-HASH-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-HASH-05 | RED · CG_DESIGN_REVALIDATION_STALE · exit 10 | RED · CG_DESIGN_REVALIDATION_STALE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRACE-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-01/evidence/SDD-1-TRACE-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRACE-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRACE-02 | SDD-1-TRACE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-02/evidence/SDD-1-TRACE-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRACE-02 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRACE-03 | SDD-1-TRACE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-03/evidence/SDD-1-TRACE-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRACE-03 | RED · CG_TRACE_ID_ORPHAN · exit 10 | RED · CG_TRACE_ID_ORPHAN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRACE-04 | SDD-1-TRACE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-04/evidence/SDD-1-TRACE-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRACE-04 | RED · CG_TRACE_SET_MISMATCH · exit 10 | RED · CG_TRACE_SET_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-TRACE-05 | — | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/evidence/SDD-1-TRACE-05.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-TRACE-05/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-TRACE-05 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-EVID-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-01/evidence/SDD-1-EVID-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-EVID-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-EVID-02 | SDD-1-TRACE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-02/evidence/SDD-1-EVID-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-EVID-02 | RED · CG_TRACE_ID_ORPHAN · exit 10 | RED · CG_TRACE_ID_ORPHAN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-EVID-03 | SDD-1-EVID-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-03/evidence/SDD-1-EVID-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-EVID-03 | RED · CG_REQUIRED_HOLDER_RED · exit 10 | RED · CG_REQUIRED_HOLDER_RED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-EVID-04 | SDD-1-EVID-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-04/evidence/SDD-1-EVID-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-EVID-04 | NOT_EXECUTED · CG_REQUIRED_HOLDER_NOT_EXECUTED · exit 20 | NOT_EXECUTED · CG_REQUIRED_HOLDER_NOT_EXECUTED · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-EVID-05 | SDD-1-EVID-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-EVID-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-EVID-05/evidence/SDD-1-EVID-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-EVID-05 | NOT_EXECUTED · CG_REQUIRED_HOLDER_OUTPUT_MISSING · exit 20 | NOT_EXECUTED · CG_REQUIRED_HOLDER_OUTPUT_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DRIVER-01 | SDD-1-EVID-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-01/evidence/SDD-1-DRIVER-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DRIVER-01 | RED · CG_TRACE_ID_ORPHAN · exit 10 | GREEN · CG_TRACE_ID_ORPHAN · exit 10 | RED · CASE_ASSERTION_CATEGORY_MISMATCH · exit 10 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DRIVER-02 | SDD-1-EVID-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-02/evidence/SDD-1-DRIVER-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DRIVER-02 | RED · CG_TRACE_ID_ORPHAN · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CASE_ASSERTION_DIAGNOSTIC_MISMATCH · exit 10 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DRIVER-03 | SDD-1-EVID-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DRIVER-03/evidence/SDD-1-DRIVER-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DRIVER-03 | RED · CG_TRACE_ID_ORPHAN · exit 10 | RED · CG_TRACE_ID_ORPHAN · exit 0 | RED · CASE_ASSERTION_EXIT_MISMATCH · exit 10 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DIFF-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-01/evidence/SDD-1-DIFF-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DIFF-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DIFF-02 | SDD-1-DIFF-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-02/evidence/SDD-1-DIFF-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DIFF-02 | RED · CG_DIFF_PATH_UNCLAIMED · exit 10 | RED · CG_DIFF_PATH_UNCLAIMED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DIFF-03 | SDD-1-DIFF-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-03/evidence/SDD-1-DIFF-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DIFF-03 | RED · CG_DIFF_CLAIM_ORPHAN · exit 10 | RED · CG_DIFF_CLAIM_ORPHAN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DIFF-04 | SDD-1-DIFF-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-04/evidence/SDD-1-DIFF-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DIFF-04 | RED · CG_DIFF_OWNER_AMBIGUOUS · exit 10 | RED · CG_DIFF_OWNER_AMBIGUOUS · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DIFF-05 | SDD-1-DIFF-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DIFF-05/evidence/SDD-1-DIFF-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DIFF-05 | RED · CG_REVIEWED_DIFF_SET_MISMATCH · exit 10 | RED · CG_REVIEWED_DIFF_SET_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-POST-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-02 | SDD-1-POST-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POST-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-02/evidence/SDD-1-POST-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-02 | RED · CG_POST_DIFF_REVIEW_MISSING · exit 10 | RED · CG_POST_DIFF_REVIEW_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-03 | SDD-1-POST-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POST-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-03/evidence/SDD-1-POST-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-03 | RED · CG_POST_DIFF_REVIEW_OVERWRITTEN · exit 10 | RED · CG_POST_DIFF_REVIEW_OVERWRITTEN · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-04 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-POST-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-04/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-04/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-04 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-05 | SDD-1-POST-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POST-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-05/evidence/SDD-1-POST-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-05 | RED · CG_SYSTEM_DESIGN_REREVIEW_MISSING · exit 10 | RED · CG_SYSTEM_DESIGN_REREVIEW_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-NA-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-01/evidence/SDD-1-POST-NA-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-NA-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POST-NA-02 | SDD-1-POST-NA-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POST-NA-02/evidence/SDD-1-POST-NA-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POST-NA-02 | RED · CG_POST_DIFF_NA_FALSE · exit 10 | RED · CG_POST_DIFF_NA_FALSE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-02 | SDD-1-CONV-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-02/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-02/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-02 | RED · CG_CONVERGENCE_OWNER_UNAUTHORIZED · exit 10 | RED · CG_CONVERGENCE_OWNER_UNAUTHORIZED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-03 | SDD-1-CONV-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-03/evidence/SDD-1-CONV-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-03 | RED · CG_CONVERGENCE_EVENT_MISSING · exit 10 | RED · CG_CONVERGENCE_EVENT_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-04 | SDD-1-CONV-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-04/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-04/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-04 | NOT_EXECUTED · CG_CONVERGENCE_EVENT_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_CONVERGENCE_EVENT_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-05 | SDD-1-CONV-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-05/evidence/SDD-1-CONV-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-05 | RED · CG_CONVERGENCE_CONTENT_IDENTITY_MISSING · exit 10 | RED · CG_CONVERGENCE_CONTENT_IDENTITY_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-06 | SDD-1-POST-01 | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/evidence/SDD-1-CONV-06.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-06/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-06 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CONV-07 | SDD-1-CONV-06 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-CONV-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CONV-07/evidence/SDD-1-CONV-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CONV-07 | RED · CG_CONVERGENCE_SPECIALIST_SET_MISMATCH · exit 10 | RED · CG_CONVERGENCE_SPECIALIST_SET_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LAND-01 | — | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/evidence/SDD-1-LAND-01.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LAND-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LAND-02 | SDD-1-LAND-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-02/evidence/SDD-1-LAND-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LAND-02 | RED · CG_LANDED_CONTENT_DRIFT · exit 10 | RED · CG_LANDED_CONTENT_DRIFT · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-LAND-03 | SDD-1-LAND-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-LAND-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-LAND-03/evidence/SDD-1-LAND-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-LAND-03 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WITHDRAW-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WITHDRAW-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WITHDRAW-02 | SDD-1-WITHDRAW-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-02/evidence/SDD-1-WITHDRAW-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WITHDRAW-02 | RED · CG_WITHDRAW_AFTER_LANDING · exit 10 | RED · CG_WITHDRAW_AFTER_LANDING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WITHDRAW-03 | SDD-1-WITHDRAW-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-03/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WITHDRAW-03/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WITHDRAW-03 | RED · CG_WITHDRAW_REASON_MISSING · exit 10 | RED · CG_WITHDRAW_REASON_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-SUPER-01 | — | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-SUPER-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-SUPER-02 | SDD-1-SUPER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-02/evidence/SDD-1-SUPER-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-SUPER-02 | RED · CG_SUPERSEDE_SUCCESSOR_MISSING · exit 10 | RED · CG_SUPERSEDE_SUCCESSOR_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-SUPER-03 | SDD-1-SUPER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-03/evidence/SDD-1-SUPER-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-SUPER-03 | RED · CG_SUPERSEDE_BACKLINK_MISSING · exit 10 | RED · CG_SUPERSEDE_BACKLINK_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-SUPER-04 | SDD-1-SUPER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-04/evidence/SDD-1-SUPER-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-SUPER-04 | RED · CG_SUPERSEDE_CYCLE · exit 10 | RED · CG_SUPERSEDE_CYCLE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-SUPER-05 | SDD-1-SUPER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-SUPER-05/evidence/SDD-1-SUPER-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-SUPER-05 | RED · CG_SUPERSEDE_EVIDENCE_REUSED · exit 10 | RED · CG_SUPERSEDE_EVIDENCE_REUSED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-01 | — | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/evidence/SDD-1-POLICY-01.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-01/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-02 | SDD-1-POLICY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-02/evidence/SDD-1-POLICY-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-02 | RED · CG_POLICY_REPOSITORY_MISSING · exit 10 | RED · CG_POLICY_REPOSITORY_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-03 | SDD-1-POLICY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-03/evidence/SDD-1-POLICY-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-03 | RED · CG_CUTOVER_SHA_INVALID · exit 10 | RED · CG_CUTOVER_SHA_INVALID · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-04 | SDD-1-POLICY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-04/evidence/SDD-1-POLICY-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-04 | RED · CG_CUTOVER_COMMIT_NOT_FOUND · exit 10 | RED · CG_CUTOVER_COMMIT_NOT_FOUND · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-05 | SDD-1-POLICY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-05/evidence/SDD-1-POLICY-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-05 | RED · CG_CUTOVER_COMMIT_WRONG_REPOSITORY · exit 10 | RED · CG_CUTOVER_COMMIT_WRONG_REPOSITORY · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-POLICY-06 | SDD-1-POLICY-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-POLICY-06/evidence/SDD-1-POLICY-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-POLICY-06 | NOT_EXECUTED · CG_COMMIT_LOOKUP_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_COMMIT_LOOKUP_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-01/evidence/SDD-1-DAG-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-02 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-02/evidence/SDD-1-DAG-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-02 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-03 | SDD-1-DAG-02 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-03/evidence/SDD-1-DAG-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-03 | RED · CG_PACKAGE_REQUIRED_AT_CUTOVER · exit 10 | RED · CG_PACKAGE_REQUIRED_AT_CUTOVER · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-04 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-04/evidence/SDD-1-DAG-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-04 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-05 | SDD-1-DAG-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-05/evidence/SDD-1-DAG-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-05 | RED · CG_PACKAGE_REQUIRED_AFTER_CUTOVER · exit 10 | RED · CG_PACKAGE_REQUIRED_AFTER_CUTOVER · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-06 | SDD-1-DAG-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-06/evidence/SDD-1-DAG-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-06 | RED · CG_CUTOVER_HISTORY_INCOMPARABLE · exit 10 | RED · CG_CUTOVER_HISTORY_INCOMPARABLE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-07 | SDD-1-DAG-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-07/evidence/SDD-1-DAG-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-07 | NOT_EXECUTED · CG_CANDIDATE_REF_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_CANDIDATE_REF_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-08 | SDD-1-DAG-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-08/evidence/SDD-1-DAG-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-08 | RED · CG_CANDIDATE_REPOSITORY_MISMATCH · exit 10 | RED · CG_CANDIDATE_REPOSITORY_MISMATCH · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-09 | — | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/evidence/SDD-1-DAG-09.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-09/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-09 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-DAG-10 | SDD-1-DAG-09 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-DAG-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-DAG-10/evidence/SDD-1-DAG-10.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-DAG-10 | RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10 | RED · CG_BOOTSTRAP_NOT_UNIQUE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-01/evidence/SDD-1-CENSUS-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-02 | SDD-1-CENSUS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-02/evidence/SDD-1-CENSUS-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-02 | NOT_EXECUTED · CG_CENSUS_PRODUCER_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_CENSUS_PRODUCER_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-03 | SDD-1-CENSUS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-03/evidence/SDD-1-CENSUS-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-03 | RED · CG_CENSUS_STALE · exit 10 | RED · CG_CENSUS_STALE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-04 | SDD-1-CENSUS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-04/evidence/SDD-1-CENSUS-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-04 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-05 | SDD-1-CENSUS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-05/evidence/SDD-1-CENSUS-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-05 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-06 | SDD-1-CENSUS-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-06/evidence/SDD-1-CENSUS-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-06 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | RED · CG_CENSUS_COVERAGE_INCOMPLETE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-07 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-07/evidence/SDD-1-CENSUS-07.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-07 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-08 | SDD-1-CENSUS-07 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-08/evidence/SDD-1-CENSUS-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-08 | RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10 | RED · CG_LEGACY_REGISTRY_MISSING_ACTIVE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-09 | SDD-1-CENSUS-07 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-09/evidence/SDD-1-CENSUS-09.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-09 | RED · CG_LEGACY_REGISTRY_EXTRA_ENTRY · exit 10 | RED · CG_LEGACY_REGISTRY_EXTRA_ENTRY · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-10 | — | machine+human-external | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/evidence/SDD-1-CENSUS-10.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-10/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-10 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-11 | SDD-1-CENSUS-10 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-11/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-11/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-11/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-11/evidence/SDD-1-CENSUS-11.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-11 | RED · CG_LEGACY_CONTRACT_CHANGED · exit 10 | RED · CG_LEGACY_CONTRACT_CHANGED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-12 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-12/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-12/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-12/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-12/evidence/SDD-1-CENSUS-12.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-12 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-13 | SDD-1-CENSUS-12 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-13/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-13/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-13/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-13/evidence/SDD-1-CENSUS-13.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-13 | RED · CG_MIGRATION_PACKAGE_MISSING · exit 10 | RED · CG_MIGRATION_PACKAGE_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-CENSUS-14 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-14/ | scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-14/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-14/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-CENSUS-14/evidence/SDD-1-CENSUS-14.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-CENSUS-14 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-01/evidence/SDD-1-ADAPTER-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-02 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-02/evidence/SDD-1-ADAPTER-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-02 | RED · CGA_DERIVED_DRIFT · exit 10 | RED · CGA_DERIVED_DRIFT · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-03 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-03/evidence/SDD-1-ADAPTER-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-03 | RED · CG_ADAPTER_NESTED_ASSET_MISSING · exit 10 | RED · CG_ADAPTER_NESTED_ASSET_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-04 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-04/evidence/SDD-1-ADAPTER-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-04 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-05 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-05/evidence/SDD-1-ADAPTER-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-05 | RED · CG_ADAPTER_OWNED_OUTPUT_EXTRA · exit 10 | RED · CG_ADAPTER_OWNED_OUTPUT_EXTRA · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-06 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-06/evidence/SDD-1-ADAPTER-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-06 | RED · CG_ADAPTER_OWNED_OUTPUT_MISSING · exit 10 | RED · CG_ADAPTER_OWNED_OUTPUT_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-07 | SDD-1-ADAPTER-01 | human-external | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-07/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-07/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-07/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-07/reviews/{role}/{subject}.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-07/github-event.json | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-07 | RED · CG_ADAPTER_OUTPUTS_MUST_BE_TRACKED · exit 10 | RED · CG_ADAPTER_OUTPUTS_MUST_BE_TRACKED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-08 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-08/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-08/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-08/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-08/evidence/SDD-1-ADAPTER-08.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-08 | RED · CG_ADAPTER_CANONICAL_CASE_INVALID · exit 10 | RED · CG_ADAPTER_CANONICAL_CASE_INVALID · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-09 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-09/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-09/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-09/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-09/evidence/SDD-1-ADAPTER-09.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-09 | RED · CG_ADAPTER_PATH_NOT_PORTABLE · exit 10 | RED · CG_ADAPTER_PATH_NOT_PORTABLE · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-10 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-10/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-10/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-10/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-10/evidence/SDD-1-ADAPTER-10.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-10 | RED · CG_ADAPTER_INPUT_NOT_CANONICAL · exit 10 | RED · CG_ADAPTER_INPUT_NOT_CANONICAL · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-11 | SDD-1-ADAPTER-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-11/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-11/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-11/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-11/evidence/SDD-1-ADAPTER-11.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-11 | RED · CG_ADAPTER_NONDETERMINISTIC · exit 10 | RED · CG_ADAPTER_NONDETERMINISTIC · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-12 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-12/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-12/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-12/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-12/evidence/SDD-1-ADAPTER-12.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-12 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADAPTER-13 | SDD-1-ADAPTER-04 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-13/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-13/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-13/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADAPTER-13/evidence/SDD-1-ADAPTER-13.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADAPTER-13 | RED · CGA_DERIVED_DRIFT · exit 10 | RED · CGA_DERIVED_DRIFT · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WIRE-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-01/evidence/SDD-1-WIRE-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WIRE-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WIRE-02 | SDD-1-WIRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-02/evidence/SDD-1-WIRE-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WIRE-02 | RED · CG_CALLER_WORKSPACE_PRE_PUSH_MISSING · exit 10 | RED · CG_CALLER_WORKSPACE_PRE_PUSH_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WIRE-03 | SDD-1-WIRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-03/evidence/SDD-1-WIRE-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WIRE-03 | RED · CG_CALLER_WORKSPACE_CI_MISSING · exit 10 | RED · CG_CALLER_WORKSPACE_CI_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WIRE-04 | SDD-1-WIRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-04/evidence/SDD-1-WIRE-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WIRE-04 | RED · CG_CALLER_PRODUCT_PRE_PUSH_MISSING · exit 10 | RED · CG_CALLER_PRODUCT_PRE_PUSH_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WIRE-05 | SDD-1-WIRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WIRE-05/evidence/SDD-1-WIRE-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WIRE-05 | RED · CG_CALLER_PRODUCT_CI_MISSING · exit 10 | RED · CG_CALLER_PRODUCT_CI_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSPP-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-01/evidence/SDD-1-WSPP-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSPP-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSPP-02 | SDD-1-WSPP-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-02/evidence/SDD-1-WSPP-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSPP-02 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSPP-03 | SDD-1-WSPP-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-03/evidence/SDD-1-WSPP-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSPP-03 | NOT_EXECUTED · CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING · exit 20 | NOT_EXECUTED · CG_WORKSPACE_PRE_PUSH_PRODUCT_REPO_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSPP-04 | SDD-1-WSPP-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSPP-04/evidence/SDD-1-WSPP-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSPP-04 | NOT_EXECUTED · CG_PRE_PUSH_REMOTE_REF_MISSING · exit 20 | NOT_EXECUTED · CG_PRE_PUSH_REMOTE_REF_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSCI-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-01/evidence/SDD-1-WSCI-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSCI-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSCI-02 | SDD-1-WSCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-02/evidence/SDD-1-WSCI-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSCI-02 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSCI-03 | SDD-1-WSCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-03/evidence/SDD-1-WSCI-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSCI-03 | NOT_EXECUTED · CG_WORKSPACE_CI_PRODUCT_COORDINATE_MISSING · exit 20 | NOT_EXECUTED · CG_WORKSPACE_CI_PRODUCT_COORDINATE_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-WSCI-04 | SDD-1-WSCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-WSCI-04/evidence/SDD-1-WSCI-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-WSCI-04 | NOT_EXECUTED · CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_WORKSPACE_CI_BASE_REF_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PPRE-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-01/evidence/SDD-1-PPRE-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PPRE-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PPRE-02 | SDD-1-PPRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-02/evidence/SDD-1-PPRE-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PPRE-02 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PPRE-03 | SDD-1-PPRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-03/evidence/SDD-1-PPRE-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PPRE-03 | NOT_EXECUTED · CG_PRODUCT_PRE_PUSH_WORKSPACE_REPO_MISSING · exit 20 | NOT_EXECUTED · CG_PRODUCT_PRE_PUSH_WORKSPACE_REPO_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PPRE-04 | SDD-1-PPRE-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PPRE-04/evidence/SDD-1-PPRE-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PPRE-04 | NOT_EXECUTED · CG_PRE_PUSH_LOCAL_REF_MISSING · exit 20 | NOT_EXECUTED · CG_PRE_PUSH_LOCAL_REF_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-01/evidence/SDD-1-PCI-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-02 | SDD-1-PCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-02/evidence/SDD-1-PCI-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-02 | RED · CG_TRACE_ID_MISSING · exit 10 | RED · CG_TRACE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-03 | SDD-1-PCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-03/evidence/SDD-1-PCI-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-03 | NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_FETCH_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_FETCH_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-04 | SDD-1-PCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-04/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-04/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-04/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-04/evidence/SDD-1-PCI-04.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-04 | NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_REVISION_UNAVAILABLE · exit 20 | NOT_EXECUTED · CG_PRODUCT_CI_WORKSPACE_REVISION_UNAVAILABLE · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-05 | SDD-1-PCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-05/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-05/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-05/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-05/evidence/SDD-1-PCI-05.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-05 | NOT_EXECUTED · CG_PRODUCT_CI_BASE_REF_MISSING · exit 20 | NOT_EXECUTED · CG_PRODUCT_CI_BASE_REF_MISSING · exit 20 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-PCI-06 | SDD-1-PCI-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-06/ | scripts/change-graph-gate/tests/testdata/SDD-1-PCI-06/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-06/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-PCI-06/evidence/SDD-1-PCI-06.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-PCI-06 | RED · CG_PRODUCT_LEDGER_CHANGE_ID_MISSING · exit 10 | RED · CG_PRODUCT_LEDGER_CHANGE_ID_MISSING · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADV-01 | — | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-01/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-01/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-01/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-01/evidence/SDD-1-ADV-01.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADV-01 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADV-02 | SDD-1-ADV-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-02/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-02/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-02/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-02/evidence/SDD-1-ADV-02.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADV-02 | RED · CG_AUTHORITATIVE_GATE_BLOCKED · exit 10 | RED · CG_AUTHORITATIVE_GATE_BLOCKED · exit 10 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |
| SDD-1-ADV-03 | SDD-1-ADV-01 | machine | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-03/ | scripts/change-graph-gate/tests/testdata/SDD-1-ADV-03/holders.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-03/evidence/case-assertion.yaml; scripts/change-graph-gate/tests/testdata/SDD-1-ADV-03/evidence/SDD-1-ADV-03.yaml | python3 scripts/change-graph-gate/tests/run_case.py --case SDD-1-ADV-03 | GREEN · CG_OK · exit 0 | GREEN · CG_OK · exit 0 | GREEN · CASE_ASSERTION_MATCHED · exit 0 | RED · CASE_CAPABILITY_MISSING · exit 10 |

## 15. Definition of Done SDD-1

- Этот subject остаётся `DRAFT`; effective approval может выпустить только
  acceptance-reviewer через ADMIN-verified Issue #480 event и новый append-only
  artifact по exact subject SHA. Все три прежних CHANGES REQUESTED records
  сохранены.
- Issue #480 и этот acceptance долговечно задают bootstrap scope; self-package
  не создаётся, второе bootstrap-исключение невозможно.
- Все 196 case IDs имеют fixtures, exact planned holders и один row matrix;
  negative/NOT_EXECUTED fixtures отличаются от существующего positive twin
  ровно одним названным фактом.
- Integration-tester единолично владеет `tests/**`, fixtures и первым запуском:
  до SUT каждый case даёт exact capability RED; только этот valid RED открывает
  RED_PROVEN. Production SUT, generator и wiring появляются только после него.
- После implementation все behavior rows завершаются final holder GREEN; три
  driver-assertion mutation rows завершаются ожидаемым RED отдельно для
  category, diagnostic и exit. Crash или masked capability не засчитываются.
- `holders.yaml` exact-list-ит required machine/human holders. Каждый machine
  holder имеет полный provenance и доказан birth inversion; каждый human holder
  backed verified external event. Zero census и vacuous subject не зелёные.
- Initial class-exposure record связан с acceptance hash; design exact-map-ит
  каждый item; отдельная revalidation того же role связана с exact design hash.
- `docs/changes/policy.yaml` versioned и содержит schema, два проверенных
  repo-specific cutover commits, authority/applicability registries и exact
  legacy registry из свежего independent census обоих repos.
- Exact-set gates связывают acceptance → design → tasks → evidence, actual diff
  → change и applicable specialist records → convergence. Only
  convergence-reviewer выпускает final record по verified external event.
- `.claude/adapters.yaml` задаёт ownership; deterministic temp regeneration
  побайтно совпадает со всеми tracked adapter-owned outputs, включая полные
  nested skill packages, и не присваивает foreign packages.
- Blocking one-fact injection доказан отдельно для workspace/product pre-push и
  CI в четырёх точных caller paths; advisory hook не влияет на authority.
- Landing-reviewer сверяет applied content, а не только commit identity; squash
  с равными blobs допустим, drift инвалидирует convergence.
- `docs/specs/04-roadmap-and-phasing.md` обновлён как нормативный lifecycle
  consumer без копирования observable scope. После landing vault получает
  durable system knowledge и ссылку на Issue #480.
- Проверки продукта, которым нужен самостоятельный clone, находятся в
  `project/kacho`; canonical SDD/rules остаются в workspace. Указанные monorepo
  paths существуют и authoritative callers используют ровно их.

## 16. Out of scope

- Массовая перепись или backfill закрытых historical acceptance документов.
- Product billing, Cluster Autoscaler semantics и изменение runtime API/RPC.
- Автоматическая смысловая интерпретация prose вместо human semantic review.
- Vendor-specific формат агента как второй canonical source.

До независимого review этот документ не утверждает ни APPROVED, ни готовность к
implementation.
