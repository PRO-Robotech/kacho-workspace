# Kachō Change Graph — design сведения SDD и `.claude`

**Статус:** решения закрыты; ожидается review владельца перед implementation plan.

**Issue:** [PRO-Robotech/kacho-workspace#480](https://github.com/PRO-Robotech/kacho-workspace/issues/480).

**Acceptance source:**
`docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`, SHA-256
`47f5f98fe1f01611a70ae1c2a5187b54d88dfd9cfb5c8566d74b5e5783d19c28`.

**Effective acceptance review:**
`docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-acceptance/47f5f98fe1f01611a70ae1c2a5187b54d88dfd9cfb5c8566d74b5e5783d19c28.yaml`;
ADMIN-verified event
`https://github.com/PRO-Robotech/kacho-workspace/issues/480#issuecomment-5502359141`.

**Initial class exposure:**
`docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-class-exposure/initial/47f5f98fe1f01611a70ae1c2a5187b54d88dfd9cfb5c8566d74b5e5783d19c28.md`,
SHA-256 `e6bc585c83bf494450e5ab2511493d3dc71ae68ec2c4207e403801b4fe6fd1dd`.

**Измеренные деревья:**
`workspace@eafd100fc911dcf6759d72337e038b258c310948` и
`kacho@b59191a90bfd2fba52f8c143977dfe0142a7d67a`. Числа ниже относятся
только к этим ревизиям либо отдельно помеченному снимку рабочего дерева.

## 1. Результат

Kachō получает собственный vendor-neutral SDD-контур поверх уже сильных
acceptance-first, TDD, specialist-review и landing-практик. Контур не копирует
Spec Kit, OpenSpec или формат конкретного агента. Он вводит один проверяемый
граф изменения, в котором observable behavior, design, execution route, RED,
implementation content, evidence, reviews и landing связаны точными identities.

GitHub Issue остаётся единственным живым трекером. Markdown остаётся удобным
человеку нормативным содержимым. Структурированные envelopes позволяют машине
доказать порядок стадий, актуальность verdict, полноту множеств и идентичность
применённого содержимого.

Главное отличие от текущего процесса: стадия больше не следует из текста
`APPROVED`, чекбокса или поля `state`. Она каждый раз выводится из одного
immutable Git snapshot и валидных входящих edges. Hooks дают раннюю обратную
связь; только pre-push и CI имеют blocking authority.

## 2. Закрытые решения

1. `D01` — `.claude` и root `CLAUDE.md` — единственные canonical AI-tooling inputs.
2. `D02` — `AGENTS.md`, `.agents/**` и `.codex/**` — tracked generated adapters, но не
   второй canon; CI воспроизводит их во временном каталоге и сравнивает bytes.
3. `D03` — каждый новый change после cutover получает ровно один package
   `docs/changes/<change-id>/` и одну GitHub Issue coordinate.
4. `D04` — acceptance владеет observable behavior; design — техническими решениями;
   tasks — утверждённым execution route; manifest — координатами; holders —
   планом доказательств; evidence — captured outputs; vault — landed knowledge.
5. `D05` — `change.yaml` не хранит authoritative `effective_stage` и собственный hash.
   Неизменяемое `lifecycle.target` задаёт terminal intent; каждый фактический
   переход — отдельный append-only edge ровно к successor derived stage.
6. `D06` — Markdown subjects хешируются как exact raw UTF-8 bytes. Structured artifacts
   используют закрытый JSON-профиль YAML и versioned canonical digest domains.
7. `D07` — digest graph ацикличен: review, evidence или verdict никогда не входят в
   subject, который сами подписывают; tracked record ссылается на уже
   существующий pre-record source commit, не на commit, содержащий себя.
8. `D08` — actual diff делится на disjoint `payload-set` и phase-frozen workflow
   sets; их объединение обязано точно равняться контролируемому diff, а
   downstream record не меняет upstream subject.
9. `D09` — future review authority читается только из trusted base policy. Candidate не
   может разрешить себе actor собственной head-правкой policy.
10. `D10` — SDD-1/#480 — единственный pre-cutover bootstrap. После activation его
    authority автоматически истекает.
11. `D11` — class exposure имеет initial record на acceptance hash и обязательную
    revalidation на каждый exact design hash; любое изменение design требует
    новой revalidation.
12. `D12` — specialist applicability определяется registered predicate, а не свободным
    `N/A`; каждое role/phase/content имеет отдельный record.
13. `D13` — `integration-tester` единолично владеет test driver, fixtures и первым
    capability RED. Implementer не пишет этот RED и не стартует параллельно.
14. `D14` — test driver и production gate — разные artifacts. Driver может существовать
    до RED; production SUT, generator и wiring — только после `RED_PROVEN`.
15. `D15` — любой result несёт ровно `category + diagnostic + exit_code`: GREEN/0,
    RED/10 либо NOT_EXECUTED/20.
16. `D16` — один CLI обслуживает четыре blocking callers: workspace/product pre-push и
    workspace/product CI. Все четыре блокируют exit 10 и exit 20.
17. `D17` — два Git DAG никогда не сравниваются по имени branch или lexical SHA. Каждый
    object проверяется в объявленном repository; ancestry считается отдельно.
18. `D18` — product хранит отдельный Change Graph ledger с full workspace coordinates;
    семь legacy migration entries существующего acceptance ledger не меняют
    значение и не становятся authority нового контура.
19. `D19` — cutover выполняется W0 → P0 → W1 → P1 → W2 → W3 → W4 → W5: оба
    cutover objects существуют до policy activation, а четыре post-P1 commits
    exact-limited к bootstrap convergence, landing, archive input и archive
    record; ни один файл не содержит future/self commit SHA.
20. `D20` — convergence принадлежит только `convergence-reviewer`; landing — только
    `landing-reviewer`. Squash/cherry-pick допустимы при равном applied content.
21. `D21` — closed historical acceptance не backfill-ятся. Active legacy work берётся
    из свежего external census и явно получает route `legacy|migrate`.
22. `D22` — gate читает Git objects и пишет только temp/output artifacts. Он не делает
    checkout, add, stash, reset и не очищает чужой dirty/shared worktree.
23. `D23` — external API work дедуплицируется внутри одного invocation; authority cache
    между invocations запрещён.
24. `D24` — SDD-1 не меняет Kubernetes/Cluster Autoscaler, billing, runtime API, proto,
    schema или продуктовую бизнес-семантику.
25. `D25` — WITHDRAWN и SUPERSEDED имеют отдельные event-backed terminal records
    на full terminal subject; reason, reciprocal links, acyclicity и запрет reuse
    старого subject-bound evidence входят в проверяемый контракт.
26. `D26` — first diagnostic выбирается versioned closed registry rank из trusted
    tool revision; implementation-defined `priority` и map order запрещены.
27. `D27` — census freshness — activation-time predicate
    `github-census-fresh-at-activation-v1` с окном 900 s и future skew 60 s;
    после activation проверяется captured proof, а не стареющий timestamp заново.
28. `D28` — acceptance/design/tasks/evidence-plan case IDs сравниваются exact-set
    в обе стороны; missing, orphan, duplicate и equal-count substitution
    различаются, а один case может иметь несколько independently named holders.

## 3. Truth ownership и package

| Artifact | Единственный предмет истины |
|---|---|
| GitHub Issue | why, priority, owner, live work status |
| `acceptance.md` | observable behavior и case IDs |
| `design.md` | technical decisions, invariants, failure model и review applicability |
| `tasks.md` | утверждённая последовательность исполнения; не status tracker |
| `change.yaml` | issue/repository/artifact/path/relationship coordinates и target lifecycle |
| `holders.yaml` | case → required holder plan, owner, predicate и evidence coordinate |
| `reviews/**` | verdict конкретной роли для exact subject и external authority event |
| `evidence/**` | captured result и минимальная воспроизводимая provenance |
| vault | знание о фактически landed system; не план и не копия acceptance |
| `04-roadmap-and-phasing.md` | нормативный consumer lifecycle; не observable requirements |

Package v1:

```text
docs/changes/<change-id>/
├── change.yaml
├── acceptance.md
├── design.md
├── tasks.md
├── holders.yaml
├── reviews/
│   ├── acceptance/<acceptance-sha256>.yaml
│   ├── class-exposure/initial/<acceptance-sha256>.yaml
│   ├── class-exposure/revalidation/<design-sha256>.yaml
│   ├── design/<role>/<design-sha256>.yaml
│   ├── transition/<to-stage>/<transition-subject-digest>.yaml
│   ├── post-diff/<role>/<payload-digest>.yaml
│   ├── convergence/<convergence-subject-digest>.yaml
│   ├── landing/<landing-subject-digest>.yaml
│   ├── archive-input/<vault-holder-subject-digest>.yaml
│   ├── archive/<archive-subject-digest>.yaml
│   └── terminal/<withdrawn|superseded>/<terminal-subject-digest>.yaml
└── evidence/<holder-id>/<subject-sha256>.yaml
```

Один deterministic coordinate на `role + phase + subject` запрещает двум
вердиктам перезаписать друг друга. Повторный review после исправления имеет
новый subject digest. Поэтому convergence path ключуется полным subject, а не
одним payload digest: изменение evidence, applicable-role set или source commit
создаёт sibling, не collision. RED/NOT_EXECUTED попытки одного holder остаются
в Git history; stage использует только текущий exact artifact из immutable
snapshot.

Placeholder `<content-digest>` из acceptance layout для convergence здесь
конкретизирован как domain-separated `convergence-subject-digest`; это не
payload-only hash. Для `post-diff/<role>/...` content digest остаётся digest
reviewed payload, потому что role и phase уже входят в directory coordinate.

`change.yaml` содержит только machine coordinates. Минимальные поля:

```json
{
  "schema_version": 1,
  "kind": "kacho_change",
  "manifest_projection_version": "kacho-manifest-projection-v1",
  "change_id": "KAC-000",
  "issue": {"repository": "owner/repo", "number": 1},
  "repositories": [
    {"id": "workspace", "repository": "PRO-Robotech/kacho-workspace"},
    {"id": "product", "repository": "PRO-Robotech/kacho"}
  ],
  "artifacts": {
    "acceptance": {"path": "acceptance.md", "raw_sha256": null},
    "design": {"path": "design.md", "raw_sha256": null},
    "tasks": {"path": "tasks.md", "raw_sha256": null},
    "holders": {"path": "holders.yaml", "raw_sha256": null}
  },
  "ownership": {"payload": []},
  "relations": {"supersedes": [], "superseded_by": null},
  "lifecycle": {"model": "kacho-linear-v1", "target": "ARCHIVED"}
}
```

Это ISSUE_READY shape: paths и terminal intent известны, future hashes равны
`null`. Manifest имеет versioned cumulative field projections:

| Projection owner | Поля, впервые входящие в subject |
|---|---|
| `ISSUE_READY` | schema/kind/projection version, change/Issue/repository coordinates, все fixed artifact paths, lifecycle model/target |
| `ACCEPTANCE_APPROVED` | `artifacts.acceptance.raw_sha256` |
| `DESIGN_APPROVED` | `artifacts.design.raw_sha256` |
| `TASKS_READY` | tasks/holders raw hashes и полный ownership exact set |
| `CONVERGED` | full canonical manifest, включая empty relations |
| terminal edge | изменённые reciprocal relations и terminal source projection |

Future-owned field может перейти `null/empty → value` только в transition своего
owner. Ранняя edge хеширует только cumulative projection своей стадии, поэтому
законное позднее заполнение design/tasks/holders не переписывает историю
acceptance. Изменение уже активированного поля создаёт новый stage subject и
инвалидирует только его и downstream. Каждый non-null raw hash независимо от
projection всегда сверяется с текущими bytes; поэтому manifest hash mismatch не
может спрятаться за исключённым future field.

На `CONVERGED` full manifest blob входит в payload и замораживается для linear
landing. Supersede до landing может изменить relations только отдельным
pre-terminal source commit; это намеренно инвалидирует прежний convergence и
переходит в terminal branch. Unknown field, обновление не своей stage и изменение
lifecycle target после ISSUE_READY дают RED.

Файлы с расширением `.yaml` обязаны быть YAML 1.2 JSON-profile: только object,
array, string, integer, boolean и null; duplicate keys, aliases, tags, implicit
timestamps, floats и non-finite numbers запрещены. Это позволяет использовать
stdlib JSON parser и не делать CI зависимым от незафиксированной YAML-библиотеки.

## 4. Digest domains и graph

### 4.1 Primitive identities

- Markdown и GitHub event body: SHA-256 exact raw bytes.
- Structured artifact: schema validation → canonical JSON с UTF-8, sorted keys,
  no insignificant whitespace и закрытым scalar set → domain-separated SHA-256.
- Composite: `SHA256("kacho-change-graph\\0" + domain-version + "\\0" + canonical-json)`.
- Repo path: normalized relative POSIX path; absolute path, `..`, backslash,
  control character и duplicate normalized path дают RED.
- Git mode: только `100644`, `100755`, `120000`.
- Deletion: `state=deleted`, `blob_sha256=null`.

Canonical content member:

```json
{
  "repository": "PRO-Robotech/kacho",
  "path": "services/compute/example.go",
  "mode": "100644",
  "state": "present",
  "blob_sha256": "<sha256-of-blob-bytes>"
}
```

Members сортируются по UTF-8 bytes `(repository, path)`. Sets сравниваются по
members в обе стороны, никогда только по cardinality.

### 4.2 Acyclic dependency graph и pre-record source projection

```text
trusted policy epoch ───────────────────────────────────────────┐
                                                               │
acceptance raw ──> acceptance subject ──> review event/artifact│
      │                                                        │
      └──> initial class exposure                              │
                 │                                             │
acceptance + design raw + exposure item set                    │
                 └──> design subject                           │
                         ├──> design specialist reviews <──────┘
                         └──> class-exposure revalidation

design subject + tasks raw + ownership projection
                 └──> tasks subject / writing-plans handoff

tasks subject + holders raw + test-content-set
                 └──> pre-red subject ──> RED evidence

pre-red proof + payload content-set
                 ├──> final machine evidence
                 └──> post-diff specialist reviews

payload-set + pre-convergence-set + applicable-review-set
+ base commits + existing convergence-source commits
                 └──> convergence subject ──> verdict event/record
                                                └──> publication event

convergence subject + convergence-record raw digest
+ publication event + existing convergence-record commit + landed payload-set
+ landed commit coordinates
                 └──> landing subject ──> event/record

landing subject + landing-record raw digest
+ existing landing-record commit + closed archive-input-set/commit
+ issue-close event
                 └──> archive subject ──> archive record

any non-landed active subject + terminal source commit
                 └──> withdrawn|superseded subject ──> terminal record
```

Контролируемый diff имеет семь disjoint фазовых множеств:

```text
controlled actual diff
  = payload-set
  ⊎ pre-convergence-set
  ⊎ convergence-record-set
  ⊎ landing-record-set
  ⊎ archive-input-set
  ⊎ archive-record-set
  ⊎ terminal-record-set
```

`payload-set` содержит product/tooling/normative artifacts и core package
(`change.yaml`, acceptance, design, tasks, holders). `pre-convergence-set`
содержит только upstream
`reviews/{acceptance,class-exposure,design,transition,post-diff}` и
`evidence/**`; transition records в нём заканчиваются `IMPLEMENTING`.
Convergence и landing records сами являются edges следующих двух linear stages.
`archive-input-set` содержит только назначенную vault note и её holder evidence;
он закрывается существующим commit до создания archive record. Terminal set
содержит ровно один withdrawal либо supersede record.

Linear и terminal branches mutually exclusive: terminal snapshot может иметь
уже существующий convergence set, но landing/archive sets обязаны быть empty;
linear LANDED/ARCHIVED snapshot требует empty terminal set. На любой стадии
поздние sets могут быть empty, но каждый changed path обязан принадлежать ровно
одному из семи sets.

Subject каждой фазы хеширует только payload и уже закрытые upstream phase sets.
Собственная и все downstream phase исключены по schema, не широким glob. Поэтому
добавление landing/archive record не меняет convergence subject, но exact-union
gate всё равно видит лишний или неверно классифицированный path.

Tracked verdict не ссылается на commit, который его содержит. Record объявляет
для каждого repo уже существующий `source_commit`; gate проверяет membership,
ancestry и пересчитывает projection `base_commit → source_commit`. Candidate
head caller-а используется только как immutable snapshot размещения: diff
`source_commit → candidate_head` обязан состоять ровно из разрешённых records
текущей/более поздней phase. Для convergence это
`convergence_source_commit`, для landing — уже существующий
`convergence_record_commit`, для archive — существующий `archive_input_commit`,
а для terminal record — `terminal_source_commit`. Reciprocal supersede links и
новое successor evidence сначала попадают в terminal source commit; следующий
record-only commit не пинует сам себя.

Downstream coordinates не записываются обратно в `change.yaml`: record
обнаруживается по injective full-subject path и сам несёт upstream coordinate.
Так нет ни file-digest self-cycle, ни commit-SHA self-cycle. Timestamp, fetch
time и runtime path не входят в subject identity; если provenance нужна дальше,
её raw digest сначала фиксируется upstream evidence и только затем входит в
следующий subject.

## 5. Lifecycle как derived state

```text
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
```

`effective_stage` — последний элемент непрерывного GREEN-prefix predicates:

| Stage | Required predicate |
|---|---|
| `ISSUE_READY` | manifest, repository и Issue coordinates валидны |
| `ACCEPTANCE_APPROVED` | current acceptance raw hash и authorized external review совпадают |
| `CLASS_EXPOSURE_RECORDED` | nonempty initial item set exact-bound к acceptance |
| `DESIGN_APPROVED` | current design, exact acceptance trace, exposure mapping/revalidation и все applicable pre-code reviews GREEN |
| `TASKS_READY` | current tasks, exact trace/path plan и verified writing-plans handoff |
| `RED_PROVEN` | test-only pre-code snapshot и valid SUT capability RED от integration-tester |
| `IMPLEMENTING` | `RED_PROVEN` и non-test payload diff существует |
| `CONVERGED` | required evidence GREEN, payload current, post-diff reviews exact и convergence authority valid |
| `LANDED` | applied payload равен convergence payload и landing authority valid |
| `ARCHIVED` | `LANDED`, immutable issue-close event, vault holder GREEN и archive record valid |

`change.yaml.lifecycle.target` — immutable terminal intent, обычно `ARCHIVED`;
после первого `ISSUE_READY` edge его изменение даёт RED и не используется как
current state. Linear переходы до `IMPLEMENTING` хранятся в:

```text
reviews/transition/<to-stage>/<transition-subject-digest>.yaml
```

Transition subject содержит change ID, exact predecessor edge/subject,
`from_stage`, `to_stage` и required-artifact subject set, но исключает собственный
record. Convergence, landing и archive records несут те же edge fields и тем
самым являются переходами последних трёх стадий без дублирующего файла.

Проверка идёт между immutable snapshots. Для package, отсутствующего в trusted
base, base stage равен virtual `NONE`, а единственный legal edge ведёт в
`ISSUE_READY`. Иначе gate выводит `base_effective_stage` и predecessor из base
object. Candidate может добавить ровно один active edge к непосредственному
successor; read-only/no-op verification не добавляет edge. Прыжок на две стадии,
движение назад, второй competing edge или linear edge после terminal record дают
`CG_LIFECYCLE_TRANSITION_INVALID` до проверки artifacts новой стадии.

Для legal successor gate проверяет required artifact set. Если один artifact
отсутствует, получается `CG_REQUIRED_ARTIFACT_MISSING`; более поздний файл не
закрывает дыру. `effective_stage` — конец непрерывной цепи valid edges с GREEN
predicates, а не поле manifest. Поэтому `SDD-1-LIFE-02` отличается и от обычного
derived promotion, и от `SDD-1-LIFE-03`, а изменение stage не мутирует
convergence payload.

Если predicate следующей стадии RED, effective stage остаётся предыдущей, а
общий result RED. Если он NOT_EXECUTED, поздняя стадия не доказана и общий result
NOT_EXECUTED. Наличие файлов поздней стадии не перепрыгивает predecessor.

### 5.1 Terminal records

`WITHDRAWN` и `SUPERSEDED` выводятся только из отдельных records:

```text
reviews/terminal/withdrawn/<terminal-subject-digest>.yaml
reviews/terminal/superseded/<terminal-subject-digest>.yaml
```

Withdrawal subject содержит change ID, current subject digest, derived
non-landed stage, nonblank reason digest, trusted authority epoch и immutable
Issue event coordinate. Event body domain `kacho-terminal-v1` exact-bind-ит
`WITHDRAWN`, subject и reason; actor одновременно разрешён policy role
`change-owner` и подтверждён текущим Issue owner/assignee. `LANDED` withdrawal,
пустой reason, unavailable event/ownership и actor mismatch классифицируются
раздельно по acceptance result algebra.

Supersede subject содержит distinct old/successor IDs, оба current subject
digests, reciprocal `superseded_by`/`supersedes` coordinates, successor
evidence-set digest, authority epoch и event. Gate обходит всю successor chain,
запрещает cycle и требует пустое пересечение subject-bound evidence coordinates
старого и нового changes. Общие immutable policy/tool artifacts не считаются
evidence reuse. Отсутствующий successor/backlink и reuse получают собственные
diagnostics.

Оба record исключают собственные bytes из subject, key-ятся full terminal
subject и не удаляют прежние reviews/evidence. После terminal state package
immutable; продолжение работы возможно только distinct successor package.
Linear `lifecycle.target` больше не действует.

Изменение upstream raw/canonical bytes меняет subject digest и транзитивно
делает downstream records stale. Gate ничего не удаляет: он перестаёт считать
старый edge действующим.

## 6. Validation order и result algebra

Фиксированный порядок:

1. schema, path safety, duplicate keys и reference cycles;
2. repository identity, object membership, ref availability и ancestry;
3. raw hashes, canonical digests, exact sets, ownership и non-vacuity;
4. applicability, holder evidence и external authority;
5. lifecycle/terminal transition.

Trusted tool revision несёт closed
`scripts/change-graph-gate/diagnostics.json`. Для каждого допустимого diagnostic
там ровно одна запись `{code, phase, rank}`; `phase` равна номеру списка выше,
а `rank` — уникальное положительное integer внутри phase. Policy pin-ит
`diagnostic_registry_version=kacho-diagnostics-v1`. Candidate registry не
используется для проверки самого candidate.

Diagnostics сортируются по
`(result-severity, phase, rank, repository, path, holder-or-role-id)`, где RED
предшествует NOT_EXECUTED. Duplicate/missing registry entry делает tool contract
неисполняемым. Runner имеет ровно один вне-реестровый boot sentinel
`NOT_EXECUTED · CG_DIAGNOSTIC_REGISTRY_INVALID · 20`; никакой обычный validator
не может его эмитить. YAML/map order и порядок обнаружения не влияют на первый
diagnostic.

Aggregation:

```text
есть RED                    → RED · exit 10
иначе есть NOT_EXECUTED     → NOT_EXECUTED · exit 20
иначе                       → GREEN · exit 0
```

Known finding доминирует независимую недоступную проверку. Empty result, warning,
`nil`, zero subjects и отсутствующий result JSON не являются GREEN.

## 7. External review authority

Future policy находится в `docs/changes/policy.yaml`. Для candidate всегда
читается policy trusted base, а не candidate head. Proposed epoch начинает
действовать только после landing и только для следующего candidate.

Review artifact хранит subject domain/digest, role, verdict, authority epoch и
immutable GitHub event coordinate. Recorded actor — cross-check; authority даёт
actor повторно fetched event и allowlist trusted policy.

Bootstrap до cutover — hard-coded tuple:

```text
repository = PRO-Robotech/kacho-workspace
issue       = 480
subject     = 47f5f98fe1f01611a70ae1c2a5187b54d88dfd9cfb5c8566d74b5e5783d19c28
publisher   = actor with GitHub repository permission ADMIN
```

После W1 policy activation этот tuple остаётся только историческим основанием
уже выданного acceptance verdict и не авторизует ни одного нового review.
Post-P1 bootstrap-finalization phases W2–W5 используют role allowlists trusted
W1 policy; их узкий package-exemption route не продлевает ADMIN-bootstrap
authority.

GitHub response classification закрыта:

| Response class | Result |
|---|---|
| transport, DNS, TLS, timeout | bounded retry, затем NOT_EXECUTED |
| 429, 502, 503, 504 | bounded retry, затем NOT_EXECUTED |
| 401/403 проверяющего credential | NOT_EXECUTED без retry |
| authenticated 404 immutable event/object | RED |
| malformed 2xx | NOT_EXECUTED |
| actor/parent/body/subject/verdict mismatch | RED |
| неизвестный status | NOT_EXECUTED |

Только idempotent GET повторяется. Максимум три attempts, общий deadline 12 s;
`Retry-After` используется только внутри остатка budget. Token, headers и raw
response body в public evidence не сохраняются.

## 8. Class exposure и specialist applicability

Initial record связывается с acceptance digest. Design обязан exact-map-ить
каждый `CGX-*` item на решение ниже. Перед `DESIGN_APPROVED`
`class-exposure-analyst` выпускает отдельную revalidation exact design hash.
Любая правка design инвалидирует revalidation без попытки угадать, является ли
она «существенной».

Policy registry задаёт `predicate ID → role → phases → input domain → executable
ID`.

- predicate true: отдельный role review обязателен;
- predicate false: derived N/A требует machine evidence на exact subject;
- unknown predicate: RED;
- predicate не исполнился: NOT_EXECUTED;
- prose `N/A`: не участвует в verdict;
- изменение relevant content меняет subject и инвалидирует record.

Для SDD-1 pre-code применимы как минимум `system-design-reviewer` и security
review: есть cross-repo authority, external API, generated executable tooling и
public evidence. DB/proto/schema reviewers получают N/A только от path/surface
predicates. Post-diff applicability пересчитывается на actual content-set;
distributed surface требует повторный `system-design-reviewer`.

Semantic duplication, open decision и качество truth ownership не выдаются за
машинно распознаваемые свойства. Их держит authorized human semantic holder;
machine gate проверяет его authority, subject и verdict.

## 9. TDD, holders и evidence

`holders.yaml` описывает plan, но не captured result. Для каждого holder он
задаёт owner role, subject domain, predicate/executable identity, required stage,
case set и evidence coordinate.

Trace invariant:

```text
unique(acceptance case IDs)
  = unique(design trace IDs)
  = unique(tasks trace IDs)
  = unique(evidence-plan case IDs)
```

До equality каждый source отдельно отвергает duplicate/malformed ID. Затем sets
сравниваются members в обе стороны: missing, orphan и equal-cardinality
substitution имеют отдельные diagnostics. Holder set сравнивается отдельно от
case set; одному case разрешено несколько independently named holders, и
aggregate обязан сохранить каждый holder coordinate.

Machine evidence содержит:

- exact subject/input/output census;
- executable repository, source commit, path, raw hash и invocation ID;
- predicate ID/version;
- category, diagnostic и exit code;
- output/stdout/stderr digests, но не полный секретосодержащий stream;
- work-unit counters;
- public evidence security profile.

Unknown executable, `true`, zero census, absent subject/output либо command crash
не дают GREEN. Каждый eligible machine holder имеет birth inversion: known-good
input, one-fact injected defect и zero-census control проходят одним entry point.

Pre-RED driver:

```text
python3 scripts/change-graph-gate/tests/run_case.py --case <case-id>
```

Он вызывает stable SUT seam. До implementation отсутствие capability должно
проявляться как explicit assertion RED на ожидаемом поведении; command-not-found,
import error, crash или synthesized expected triple не считаются capability RED.
После implementation driver независимо сравнивает category, diagnostic и exit.

Only `integration-tester` owns `tests/**`, fixtures и первый RED run.
Production `run.py`, generator, canonical rules/agents и caller wiring относятся
к implementation diff и запрещены до valid `RED_PROVEN`.

## 10. Unified CLI и четыре authoritative callers

Low-level contract:

```text
python3 <trusted-workspace>/scripts/change-graph-gate/run.py verify
  --caller-id <workspace-pre-push|workspace-ci|product-pre-push|product-ci>
  --input-json <runtime-file>
  --result-json <runtime-file>
```

Input JSON содержит sorted push updates и для каждой candidate:

- candidate repository identity, base SHA и head SHA;
- workspace repository/root/base/head;
- product repository/root/base/head;
- change IDs и package/product-ledger coordinates.

Caller не передаёт policy path, allowlist, retry policy, verdict или required
authority epoch. Runtime paths не входят в durable evidence.

Output — ровно один JSON object schema v1 с category, diagnostic, exit code,
subjects examined и work units. Отсутствующий/unparseable output сам становится
`NOT_EXECUTED · CG_GATE_OUTPUT_MISSING · 20`.

| Caller | Base/head producer | Second repository |
|---|---|---|
| workspace pre-push | каждая stdin push строка; zero remote разрешается только через exact published integration base | package exact product SHAs; workspace-only использует один существующий `base=head` |
| workspace CI | PR `base.sha/head.sha`; push `before/after`; dispatch требует explicit full inputs | temp fetch exact product SHAs из package, никогда floating `main` |
| product pre-push | существующий `prepush-range.sh` возвращает exact base/head для каждой update | sibling workspace policy/package objects; absence → 20 |
| product CI | PR/push event SHAs; dispatch без exact inputs → 20 | product Change Graph ledger pin → public exact workspace fetch |

Workspace `scripts/hooks/pre-push` вызывает Change Graph отдельной blocking
полосой. Его существующий `run-all` законно трактует old exit 2 как nonblocking
VOID и поэтому не может быть transport для нового exit 20.

Workspace CI добавляет invocation в существующий required `tooling-gate` job.
Product CI добавляет invocation в существующий required `build-test` job.
Новый optional job не считается enforcement. Product pre-push сохраняет
существующий Git-environment scrub и ref-range producer.

Каждый caller имеет one-fact injection: в otherwise-valid package из tasks
удалён один acceptance ID, underlying gate возвращает
`CG_TRACE_ID_MISSING · 10`, wrapper сохраняет diagnostic и блокирует.

## 11. Product ledger и cross-repo convergence

Новый `project/kacho/docs/change-graph.json` является pointer ledger Change
Graph. Existing `docs/acceptance-ledger.yaml` остаётся legacy migration ledger;
его семь записей и short historical revisions не переинтерпретируются.

```json
{
  "schema_version": 1,
  "trusted_tool_revision": "<full-workspace-40-sha>",
  "changes": [
    {
      "change_id": "KAC-000",
      "workspace_revision": "<full-workspace-40-sha>"
    }
  ]
}
```

`trusted_tool_revision` читается из product base object. Candidate head может
предложить next value, но не использовать его для собственной проверки.
`workspace_revision` связывает product diff с immutable
acceptance/design/tasks/RED package revision; это не policy authority.

Convergence record появляется позже и намеренно не записывается обратно в
product ledger. После record commit тот же authorized `convergence-reviewer`
публикует второй, non-verdict event domain
`kacho-record-publication-v1` в Issue change. Его closed body содержит:

```json
{
  "change_id": "KAC-000",
  "convergence_subject_sha256": "<64hex>",
  "record_repository": "PRO-Robotech/kacho-workspace",
  "record_revision": "<full-workspace-40-sha>",
  "record_path": "docs/changes/KAC-000/reviews/convergence/<64hex>.yaml",
  "record_raw_sha256": "<64hex>",
  "verdict_event_node_id": "<immutable-node-id>"
}
```

Publication event адресует уже существующий record, но не выдаёт новый verdict:
actor/role/Issue/subject обязаны совпасть с исходным convergence event, а record
revision обязан содержать exact path/blob. Gate exact-search-ит Issue events и
требует ровно один matching publication; none/unavailable даёт NOT_EXECUTED,
conflicting duplicate или mismatch — RED. Так product ledger остаётся stable,
а плавающий workspace ref и cross-repo pointer cycle не появляются.

Product CI:

1. читает base ledger из Git object;
2. создаёт temp bare clone public workspace;
3. fetch-ит exact trusted tool и package `workspace_revision` в named temp refs;
4. сверяет fetched object IDs;
5. исполняет CLI только из trusted tool revision;
6. для non-draft PR проверяет verdict event по exact product source/content,
   затем publication event, fetch-ит его exact `record_revision` и проверяет
   record path/raw/subject;
7. fetch/ref/API failure возвращает exit 20.

Draft PR и pre-push обязаны доказать корректный текущий stage, но не требуют
ещё не существующего convergence. Non-draft merge candidate требует
`CONVERGED`. Изменение product head после review перестаёт совпадать с event и
автоматически краснит check. Внешний convergence event избавляет product commit
от self-cycle: product ledger не обновляется ссылкой на record, который зависит
от этого же product SHA; post-record publication event даёт CI точную workspace
coordinate уже после появления record.

## 12. Staged cutover двух Git DAG

### W0 — workspace expand

Landing включает уже RED-proven tests, CLI/adapters, workspace callers и
bootstrap policy `mode=bootstrap`. Product coordinate указывает на существующий
object. Final cutover SHAs ещё не записываются.

### P0 — product expand

Landing добавляет product ledger, repohygiene и два product callers;
`trusted_tool_revision=W0`. P0 проверяется exact bootstrap route #480. После P0
оба будущих cutover objects существуют.

### W1 — census and enforce

Landing-time producer получает GitHub census open PR + live in-progress Issue в
обоих repositories с query, ETag/revision, response `Date` и response digest.
Policy становится `mode=enforced` и содержит:

```json
{
  "workspace_cutover_commit": "<W0-full-40-sha>",
  "product_cutover_commit": "<P0-full-40-sha>",
  "diagnostic_registry_version": "kacho-diagnostics-v1",
  "census_freshness": {
    "predicate_id": "github-census-fresh-at-activation-v1",
    "max_age_seconds": 900,
    "max_future_skew_seconds": 60,
    "evaluation": "activation_once"
  }
}
```

При W1 verification trusted current time берётся из authenticated GitHub
response `Date`. Возраст больше 900 s или время более чем на 60 s в будущем даёт
`CG_CENSUS_STALE · 10`; невозможность получить trusted time/API даёт
NOT_EXECUTED. Result, evaluation time и census digest попадают в activation
evidence. После W1 обычный gate проверяет captured proof/hash, а не применяет
окно к вечному historical snapshot заново.

W1 также содержит exact legacy registry и закрытый
`bootstrap_finalization` route для четырёх будущих workspace phases #480. W1
судится base bootstrap policy W0, не собственной head policy.

### P1 — promote trusted epoch

Product ledger меняет trusted tool revision с W0 на already-existing W1. P1
судится старым base pin W0. После landing обычные workspace/product candidates
читают enforced W1 contract и требуют package.

### W2 — bootstrap convergence record

После существующих W1/P1 convergence-reviewer выпускает policy-authorized event
на exact payload, pre-convergence sets и `convergence_source_commit` каждого
repo. Workspace добавляет только:

```text
docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-convergence/
  <convergence-subject-digest>.yaml
```

Record ссылается на W1/P1 как уже существующие source commits; W2 SHA в его
subject отсутствует. После W2 тот же convergence-reviewer выпускает
`kacho-record-publication-v1` event с exact W2 revision/path/raw digest; без него
следующая phase и product CI дают NOT_EXECUTED.

### W3 — bootstrap landing record

После W2 landing-reviewer сравнивает applied content и выпускает отдельный
policy-authorized event. Workspace добавляет только:

```text
docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-landing/
  <landing-subject-digest>.yaml
```

Landing subject включает raw digest W2 record, publication event, существующий
W2 record commit, landed W1/P1 coordinates и applied content set, но не W3 SHA.

### W4 — archive input и vault

После W3 workspace добавляет только фактическую vault note и отдельный holder,
который связывает её raw digest с W3 landing record:

```text
docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-archive-input/
  <vault-holder-subject-digest>.yaml
<designated-vault-note-path>
```

W4 является закрытым `archive-input-set`; archive verdict в него не входит.

### W5 — archive record

После W4 Issue #480 получает exact close event. Archive subject включает W3
landing record/commit, W4 archive-input set/commit и close event. Workspace
добавляет только:

```text
docs/specs/reviews/sub-phase-SDD-1-kacho-change-graph-archive/
  <archive-subject-digest>.yaml
```

W5 SHA не входит в record. `ARCHIVED` монотонен: поздний reopen не переписывает
W5 и не оживляет старый package. Он даёт live-status divergence, пока работа не
перенесена в distinct successor Issue/package с reciprocal link; новый close
event не требует sibling bootstrap archive record.

`bootstrap_finalization` — не второе bootstrap change и не продолжение ADMIN
authority. Trusted W1 policy разрешает только Issue #480, ровно следующий из
W2/W3/W4/W5 phase kinds, exact predecessor subject и exact allowlisted paths;
core package, policy, tool или product path в таком diff запрещён. Unrelated
normal packaged commits могут находиться между phases: проверяется ancestry и
content projection, не соседство SHAs. После valid W5 в base route навсегда
возвращает `CG_BOOTSTRAP_AUTHORITY_EXPIRED · 10`.

Partial states:

- W0 без P0: expand-only; двухрепозиторная authority ещё не заявляется;
- W0+P0: bootstrap-only, допускается только rollout #480;
- W1 до P1: workspace enforced; product fail-closed кроме exact P1 promotion;
- W1+P1 до W5: оба repos enforced для обычных packages; #480 допускает только
  очередную finalization phase W2, W3, W4 или W5;
- после W5: bootstrap и finalization routes истекли.

Repo/ref classification разделяет ложь и невозможность спросить:

- base ancestor of cutover: только exact registered legacy route;
- base equals cutover либо cutover ancestor of base: package required;
- healthy lookup подтвердил отсутствие объявленного immutable SHA, wrong-repo
  membership или incomparable history: RED;
- caller не передал required ref/repository, transport/API недоступен либо ref
  нельзя получить: NOT_EXECUTED;
- один lexical 40-hex без доказанной membership не считается object.

Closed historical acceptance не попадают в census. Active unchanged contract
может завершиться route `legacy`; observable contract change требует `migrate`,
successor package и новые evidence.

## 13. Canonical `.claude` и deterministic adapters

`.claude/adapters.yaml` — canonical closed-schema ownership manifest. Он читает
только tracked Git tree candidate SHA:

```json
{
  "schema_version": 1,
  "canonical": {
    "tracked_only": true,
    "exact_files": ["CLAUDE.md", ".claude/adapters.yaml", ".claude/settings.json"],
    "tracked_trees": [
      ".claude/agents",
      ".claude/hooks",
      ".claude/rules",
      ".claude/skills"
    ],
    "allowed_git_modes": ["100644", "100755"]
  },
  "targets": {
    "codex": {
      "reader_contract": {
        "cli_version": "0.151.0",
        "project_doc_max_bytes": 32768
      },
      "ownership": {
        "exact_files": ["AGENTS.md", ".codex/hooks.json"],
        "file_transforms": [
          {
            "sources": ["CLAUDE.md", ".claude/rules"],
            "target": "AGENTS.md",
            "transform": "claude-index-to-codex-router-v1"
          },
          {
            "sources": [".claude/settings.json"],
            "target": ".codex/hooks.json",
            "transform": "claude-settings-hooks-to-codex-v1"
          }
        ],
        "tree_mappings": [
          {
            "source": ".claude/agents",
            "target": ".codex/agents",
            "transform": "yaml-frontmatter-to-toml-v1",
            "ownership": "exact"
          },
          {
            "source": ".claude/hooks",
            "target": ".codex/hooks",
            "transform": "tracked-tree-byte-copy-v1",
            "ownership": "exact"
          }
        ],
        "skill_packages": {
          "source_root": ".claude/skills",
          "target_root": ".agents/skills",
          "transform": "tracked-tree-byte-copy-v1",
          "owned_packages": [
            "code-authoring",
            "defuddle",
            "doc-truthfulness",
            "evgeniy",
            "gate-authoring",
            "godzila",
            "hardening-audit-loop",
            "json-canvas",
            "kacho-docs-writer",
            "load-testing-coach",
            "measurement-discipline",
            "obsidian-bases",
            "obsidian-cli",
            "obsidian-markdown",
            "security-surface",
            "testing-code-coach",
            "testing-product-coach",
            "verdict-and-landing"
          ],
          "unlisted_package_policy": "foreign-preserve"
        },
        "runtime_exclusions": [
          ".codex/hooks/**/.state/**",
          ".codex/hooks/**/__pycache__/**",
          ".codex/hooks/**/*.pyc",
          ".codex/hooks/**/*.pyo",
          ".codex/hooks/**/*.pyd"
        ]
      }
    }
  }
}
```

Для каждого `owned_packages[i]` source и target выводятся только как
`source_root/name` и `target_root/name`; полный nested tracked source set
проектируется в полный owned target set. Поэтому manifest exact-list-ит package
names, а transform — files/modes внутри package. Tracked canonical package,
которого нет в `owned_packages`, и owned output вне выведенного set дают RED;
untracked unlisted target package остаётся foreign.

Symlink `120000` и gitlink `160000` запрещены во всех canonical/owned trees.
Runtime exclusions применяются только к disk census: `.state/**`,
`__pycache__/**`, `*.pyc`, `*.pyo`, `*.pyd`. Если такой path tracked, это RED,
а не исключение.

### 13.1 Skill ownership

Acceptance требует полный текущий nested corpus, включая
`audit-round.workflow.js`, `EXAMPLES.md` и Obsidian references. Поэтому пять
сейчас ignored packages сначала проходят provenance/license review и затем
становятся tracked canonical inputs. После promotion owned set равен:

```text
code-authoring
defuddle
doc-truthfulness
evgeniy
gate-authoring
godzila
hardening-audit-loop
json-canvas
kacho-docs-writer
load-testing-coach
measurement-discipline
obsidian-bases
obsidian-cli
obsidian-markdown
security-surface
testing-code-coach
testing-product-coach
verdict-and-landing
```

Если provenance/license хотя бы одного package не позволяет tracked
публикацию, cutover блокируется; ignored bytes не становятся тайным canonical
input. Любой будущий tracked package, отсутствующий в manifest, даёт RED.
Unlisted untracked package остаётся foreign, не читается, не удаляется и не
может отключить drift-check owned outputs.

Transform `tracked-tree-byte-copy-v1` переносит полный package tree с bytes и
mode без free-text substitution. Basename source, frontmatter `name` и
destination basename обязаны совпадать.

### 13.2 `AGENTS.md`

Corpus `CLAUDE.md + .claude/rules/*.md` на pinned HEAD занимает 875,077 bytes,
а Codex project-doc limit по умолчанию — 32 KiB. Полный inline будет молча
обрезан; literal `@import` Codex не раскрывает.

Transform `claude-index-to-codex-router-v1` создаёт generated router меньше
32 KiB:

1. generated/do-not-edit marker и ссылка на canonical `CLAUDE.md`;
2. компактная workspace topology/operation часть canonical index;
3. explicit MUST-read routing: `00-kacho-core.md` и `ai-tooling.md` всегда;
4. остальные `.claude/rules/*.md` читаются полностью до действия при applicable
   scope; сомнение означает applicable;
5. coordinates сохраняют lowercase `.claude`; массовой замены на `.Codex` нет.

До generation canonical `CLAUDE.md` исправляется: модель «generated copies не
существует» заменяется на «canonical inputs + tracked verified adapters», а
host-specific `/home/...` example становится portable. Transform не скрывает
canonical defect исключением.

Real-reader smoke использует pinned `codex debug prompt-input probe`: generated
marker/router должен целиком присутствовать без truncation. Foreign runtime
prefix от codebase-memory не сравнивается как часть файла.

### 13.3 Agent roles

Каждый tracked `.claude/agents/<name>.md` имеет frontmatter только с nonblank
`name` и `description`; name равен basename. Body без path/text replacement
становится `.codex/agents/<name>.toml` field `developer_instructions`.

Deterministic TOML key order:

```text
name
description
developer_instructions
```

Строки получают deterministic escaping; `tomllib` возвращает ровно три
nonblank strings. Expected role set выводится из candidate Git tree, поэтому
новые `design-author` и `convergence-reviewer` появляются автоматически, а
HEAD count не становится вечной константой. Реальный multi-agent loader обязан
видеть exact target set; parser-only GREEN недостаточен.

### 13.4 Hooks

Static `.claude/hooks/**` копируется byte-for-byte с mode в `.codex/hooks/**`.
Из `.claude/settings.json` переносится только `hooks`; локальное
`permissions.defaultMode=bypassPermissions`, trust и user config не становятся
tracked output.

Mapping:

- `UserPromptSubmit` → `UserPromptSubmit`;
- `Stop` → `Stop`;
- source `PostToolUse` matcher `Write|Edit|MultiEdit` → target
  `^apply_patch$`;
- timeout сохраняется;
- source command обязан ссылаться на известный `.claude/hooks/<rel>`,
  произвольный shell fragment отвергается;
- target command вычисляет `workspace_root` через
  `git rev-parse --show-toplevel`, выставляет `CLAUDE_PROJECT_DIR` и вызывает
  `.codex/hooks/<rel>` без absolute machine path.

Support boundary честная: Codex запускается с workspace как project root.
Самостоятельная сессия, стартовавшая внутри nested `project/kacho`, может не
обнаружить workspace hooks; product enforcement всё равно находится в product
pre-push/CI, не в advisory session hook.

Текущие canonical `guard.py`/`docfresh.py` понимают Claude payload
`Write|Edit|MultiEdit + tool_input.file_path`, тогда как Codex 0.151 edit несёт
`apply_patch + tool_input.command`. Canonical hooks становятся dual-schema:

- Claude path сохраняет `file_path`;
- Codex path разбирает все `Add/Update/Delete File` members patch;
- relative paths разрешаются от event `cwd` после containment check;
- multi-file patch обрабатывается как set;
- edit event с нулём разобранных paths — hook failure, не clean/no-op;
- aggregate остаётся одним valid hook result.

`hooks/list` доказывает только discovery/parse. Birth evidence дополнительно
запускает isolated настоящий `apply_patch` и требует unique observation каждого
изменённого path. Если pinned Codex runtime недоступен, holder NOT_EXECUTED и
cutover не объявляется GREEN.

### 13.5 Generation and verification

Порядок одного adapter invocation:

1. parse closed manifest;
2. развернуть inputs только из candidate Git tree;
3. проверить tracked-only, modes, UTF-8/frontmatter, lowercase, containment;
4. вычислить exact expected owned output set;
5. дважды render в два fresh temp roots;
6. сравнить `(relative path, mode, SHA-256(blob))` двух runs;
7. выполнить static parsers/syntax checks;
8. выполнить pinned real loaders;
9. сравнить expected owned set с tracked candidate tree в обе стороны;
10. сравнить bytes/modes, не читая и не удаляя foreign/runtime files.

Static checks: JSON/frontmatter closed schema, AGENTS UTF-8/size/case/path,
`tomllib`, hooks JSON schema, `bash -n`, Python `compile()` без pycache и
`go test ./...` для `class-guard/goast`.

Real readers: `codex debug prompt-input`, app-server `skills/list(forceReload)`,
`hooks/list`, role loader и isolated apply-patch sentinel. CI pins one supported
CLI; текущие desktop/CLI versions не объявляются эквивалентными без отдельного
compatibility run.

Cache key:

```text
adapter-v1 + trusted generator revision + canonical input tree digest
+ target + pinned reader version
```

Cache живёт только внутри invocation. Evidence печатает hashes/work units,
ровно два determinism render runs и loader run counts, но не host paths или
полный hook output.

## 14. Security, performance и shared-worktree safety

Public evidence сохраняет только минимальную provenance. Env, Authorization
headers, tokens, raw GitHub body, host-absolute paths, Secret values и полный
stdout/stderr не сериализуются. Path traversal и symlink escape проверяются до
любого write; generator output root всегда fresh temp directory.

GitHub fetch, permission lookup, file hash и adapter generation memoized внутри
одного invocation по immutable identity. Между invocations authority cache не
живёт. Result печатает work units, чтобы 196 cases не означали 196 одинаковых
network fetches или generator runs.

Gate читает blobs/tree/commit objects через explicit repository + SHA. Adapter
генерирует только во временный каталог, затем сравнивает expected tracked bytes.
Ни один из них не выполняет checkout/add/stash/reset, не удаляет foreign/runtime
files и не пишет в `project/kacho` из workspace process.

Перед каждой implementation write фиксируется fresh dirty baseline и path
ownership отдельно для двух repos. Снимок class exposure показывал 34 status
entries и 8 worktrees в workspace, 1 entry и 40 worktrees в product; эти числа
относятся только к `2026-09-02T00:19:46Z` и не являются разрешением трогать их.

## 15. Compatibility и rollout

- `docs/specs/04-roadmap-and-phasing.md` становится lifecycle consumer и ссылается
  на acceptance/design, но не копирует observable requirements.
- `git-issues.md`, `multi-agent-flow.md`, `testing.md`, `ai-tooling.md` и
  `00-kacho-core.md` описывают один порядок без конкурирующих owners.
- New roles: `design-author` и `convergence-reviewer`.
- Existing roles получают узкие handoff contracts; specialist reviewers не
  заменяются универсальным SDD reviewer.
- `integration-tester` остаётся единственным RED owner; implementer начинает
  non-test diff только после evidence.
- Active agent paths исправляются на monorepo `project/kacho/{proto,pkg,services,
  gateway,deploy}`; sibling polyrepo merge/sync больше не является handoff.
- Legacy acceptance homes остаются читаемыми. Только post-cutover new work и
  observable contract changes требуют package.
- Hooks остаются advisory и не участвуют в effective verdict.
- Vault обновляется после landing фактическим knowledge/trail, а не design prose.

## 16. Planned implementation boundary

Design задаёт радиус; точные task slices появятся только через
`superpowers:writing-plans` после review этого документа.

Workspace canonical/process surface:

- root `CLAUDE.md`;
- `.claude/rules/{00-kacho-core,ai-tooling,git-issues,multi-agent-flow,testing}.md`;
- `.claude/rules/change-graph.md`;
- `.claude/agents/acceptance-author.md`;
- `.claude/agents/acceptance-reviewer.md`;
- `.claude/agents/class-exposure-analyst.md`;
- `.claude/agents/design-author.md`;
- `.claude/agents/integration-tester.md`;
- `.claude/agents/rpc-implementer.md`;
- `.claude/agents/system-design-reviewer.md`;
- `.claude/agents/convergence-reviewer.md`;
- `.claude/agents/landing-reviewer.md`;
- профильные agents, где исправляются monorepo paths/handoff;
- `.claude/adapters.yaml` и change-package templates;
- tracked generated `AGENTS.md`, `.agents/**`, `.codex/**`.

Workspace enforcement/support surface:

- `scripts/change-graph-gate/**`;
- `scripts/change-graph-gate/diagnostics.json` как closed rank registry;
- `scripts/ai-tooling-adapter/**`;
- `scripts/hooks/pre-push`;
- `.github/workflows/ci.yaml` existing required job;
- `scripts/docs-gate/**` и `scripts/tooling-gate/**` only where integration is
  required;
- `docs/changes/policy.yaml`;
- `docs/specs/04-roadmap-and-phasing.md`;
- design/acceptance/review artifacts for #480, включая bootstrap-specific
  convergence/landing/archive-input/archive directories W2–W5;
- одна archive-time vault note, выбранная tasks по действующему vault naming
  contract.

Product surface:

- `docs/change-graph.json`;
- `scripts/hooks/pre-push` and its existing ref-range producer;
- `.github/workflows/ci.yaml` existing `build-test` job;
- product-local repohygiene tests/wrapper needed for a standalone clone.

DB, proto, runtime API, business handlers, charts and billing are outside SDD-1.
If actual diff touches them, applicability and acceptance invalidate this design
instead of silently expanding scope.

## 17. Class-exposure mapping

| Exposure | Design sections that hold it |
|---|---|
| `CGX-01` | §7 raw subject + external event authority |
| `CGX-02` | §7 trusted-base epoch; §12 bootstrap expiry |
| `CGX-03` | §4 domain-separated DAG, phase freeze и pre-record source commits |
| `CGX-04` | §5 base→head one-step transition edge, derived stage и invalidation |
| `CGX-05` | §6 trusted versioned diagnostic-rank registry |
| `CGX-06` | §6 result algebra; §10 four blocking callers |
| `CGX-07` | §7 closed response table and bounded retry; §14 minimization |
| `CGX-08` | §9 sole RED owner and pre-code boundary |
| `CGX-09` | §9 stable SUT seam and honest RED |
| `CGX-10` | §9 holder provenance/non-vacuity/birth inversion |
| `CGX-11` | §9 case-ID exact sets and independently named holders |
| `CGX-12` | §8 registered applicability and separate role records |
| `CGX-13` | §13 explicit owned/foreign adapter manifest |
| `CGX-14` | §13 real reader/parser contracts and portable paths |
| `CGX-15` | §10 explicit repo identities; §12 membership/ancestry |
| `CGX-16` | §10 one CLI and four real callers |
| `CGX-17` | §12 W0→P0→W1→P1→W2→W3→W4→W5 protocol |
| `CGX-18` | §12 activation-time fresh external census predicate and no backfill |
| `CGX-19` | §4 canonical content members; §12 applied content |
| `CGX-20` | §14 temp/object-only operation and dirty safety |
| `CGX-21` | §14 public evidence and path/secret controls |
| `CGX-22` | §14 invocation-local memoization/work units |

Любая правка design требует новой class-exposure revalidation exact design SHA;
эта таблица сама себе approval не выдаёт.

## 18. Acceptance traceability

Каждый case ID ниже имеет хотя бы одно design decision. Этот block является
machine-readable exact-set input; range и count вместо members не допускаются.

| Acceptance case | Design decision / section |
|---|---|
| `SDD-1-BOOT-01` | D03, D10, D19 · §3, §7, §12 |
| `SDD-1-BOOT-02` | D03, D10, D19 · §3, §7, §12 |
| `SDD-1-REVIEW-01` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-02` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-03` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-04` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-05` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-06` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-07` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-08` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-09` | D06, D09, D10 · §4, §7 |
| `SDD-1-REVIEW-10` | D06, D09, D10 · §4, §7 |
| `SDD-1-AUTH-01` | D09 · §7 |
| `SDD-1-AUTH-02` | D09 · §7 |
| `SDD-1-AUTH-03` | D09 · §7 |
| `SDD-1-AUTH-04` | D09 · §7 |
| `SDD-1-AUTH-05` | D09 · §7 |
| `SDD-1-AUTH-06` | D09 · §7 |
| `SDD-1-AUTH-07` | D09 · §7 |
| `SDD-1-AUTH-08` | D09 · §7 |
| `SDD-1-TRUTH-01` | D04 · §3 |
| `SDD-1-TRUTH-02` | D04 · §3 |
| `SDD-1-TRUTH-03` | D04 · §3 |
| `SDD-1-TRUTH-04` | D04 · §3 |
| `SDD-1-TRUTH-05` | D04 · §3 |
| `SDD-1-TRUTH-06` | D04 · §3 |
| `SDD-1-LIFE-01` | D05, D08 · §5 |
| `SDD-1-LIFE-02` | D05, D08 · §5 |
| `SDD-1-LIFE-03` | D05, D08 · §5 |
| `SDD-1-NONEMPTY-01` | D15 · §9 |
| `SDD-1-NONEMPTY-02` | D15 · §9 |
| `SDD-1-NONEMPTY-03` | D15 · §9 |
| `SDD-1-NONEMPTY-04` | D15 · §9 |
| `SDD-1-CLASS-01` | D11, D12 · §8 |
| `SDD-1-CLASS-02` | D11, D12 · §8 |
| `SDD-1-CLASS-03` | D11, D12 · §8 |
| `SDD-1-CLASS-04` | D11, D12 · §8 |
| `SDD-1-CLASS-05` | D11, D12 · §8 |
| `SDD-1-CLASS-06` | D11, D12 · §8 |
| `SDD-1-CLASS-07` | D11, D12 · §8 |
| `SDD-1-CLASS-08` | D11, D12 · §8 |
| `SDD-1-CLASS-09` | D11, D12 · §8 |
| `SDD-1-CLASS-10` | D11, D12 · §8 |
| `SDD-1-DESIGN-01` | D11, D12 · §8 |
| `SDD-1-DESIGN-02` | D11, D12 · §8 |
| `SDD-1-DESIGN-03` | D11, D12 · §8 |
| `SDD-1-NA-01` | D12 · §8 |
| `SDD-1-NA-02` | D12 · §8 |
| `SDD-1-NA-03` | D12 · §8 |
| `SDD-1-TASKS-01` | D04, D05 · §4, §5 |
| `SDD-1-TASKS-02` | D04, D05 · §4, §5 |
| `SDD-1-TASKS-03` | D04, D05 · §4, §5 |
| `SDD-1-TDD-01` | D13, D14 · §9 |
| `SDD-1-TDD-02` | D13, D14 · §9 |
| `SDD-1-TDD-03` | D13, D14 · §9 |
| `SDD-1-TDD-04` | D13, D14 · §9 |
| `SDD-1-TDD-05` | D13, D14 · §9 |
| `SDD-1-TDD-06` | D13, D14 · §9 |
| `SDD-1-TDD-07` | D13, D14 · §9 |
| `SDD-1-TDD-08` | D13, D14 · §9 |
| `SDD-1-TDD-09` | D13, D14 · §9 |
| `SDD-1-TDD-10` | D13, D14 · §9 |
| `SDD-1-HOLDER-01` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-02` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-03` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-04` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-05` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-06` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-07` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-08` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-09` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-10` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-11` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-12` | D04, D15 · §3, §9 |
| `SDD-1-HOLDER-13` | D04, D15 · §3, §9 |
| `SDD-1-BIRTH-01` | D14, D15 · §9 |
| `SDD-1-BIRTH-02` | D14, D15 · §9 |
| `SDD-1-BIRTH-03` | D14, D15 · §9 |
| `SDD-1-BIRTH-04` | D14, D15 · §9 |
| `SDD-1-HASH-01` | D06, D07, D08 · §4, §5 |
| `SDD-1-HASH-02` | D06, D07, D08 · §4, §5 |
| `SDD-1-HASH-03` | D06, D07, D08 · §4, §5 |
| `SDD-1-HASH-04` | D06, D07, D08 · §4, §5 |
| `SDD-1-HASH-05` | D06, D07, D08 · §4, §5 |
| `SDD-1-TRACE-01` | D28 · §9 |
| `SDD-1-TRACE-02` | D28 · §9 |
| `SDD-1-TRACE-03` | D28 · §9 |
| `SDD-1-TRACE-04` | D28 · §9 |
| `SDD-1-TRACE-05` | D28 · §9 |
| `SDD-1-EVID-01` | D04, D15 · §6, §9 |
| `SDD-1-EVID-02` | D04, D15 · §6, §9 |
| `SDD-1-EVID-03` | D04, D15 · §6, §9 |
| `SDD-1-EVID-04` | D04, D15 · §6, §9 |
| `SDD-1-EVID-05` | D04, D15 · §6, §9 |
| `SDD-1-DRIVER-01` | D14, D15 · §9 |
| `SDD-1-DRIVER-02` | D14, D15 · §9 |
| `SDD-1-DRIVER-03` | D14, D15 · §9 |
| `SDD-1-DIFF-01` | D08, D17 · §4, §10 |
| `SDD-1-DIFF-02` | D08, D17 · §4, §10 |
| `SDD-1-DIFF-03` | D08, D17 · §4, §10 |
| `SDD-1-DIFF-04` | D08, D17 · §4, §10 |
| `SDD-1-DIFF-05` | D08, D17 · §4, §10 |
| `SDD-1-POST-01` | D12, D20 · §8, §4 |
| `SDD-1-POST-02` | D12, D20 · §8, §4 |
| `SDD-1-POST-03` | D12, D20 · §8, §4 |
| `SDD-1-POST-04` | D12, D20 · §8, §4 |
| `SDD-1-POST-05` | D12, D20 · §8, §4 |
| `SDD-1-POST-NA-01` | D12, D20 · §8, §4 |
| `SDD-1-POST-NA-02` | D12, D20 · §8, §4 |
| `SDD-1-CONV-01` | D07, D08, D09, D20 · §4, §7 |
| `SDD-1-CONV-02` | D07, D08, D09, D20 · §4, §7 |
| `SDD-1-CONV-03` | D07, D08, D09, D20 · §4, §7 |
| `SDD-1-CONV-04` | D09, D15, D20 · §6, §7 |
| `SDD-1-CONV-05` | D07, D08, D20 · §4, §5 |
| `SDD-1-CONV-06` | D07, D08, D20 · §4, §5 |
| `SDD-1-CONV-07` | D07, D08, D20 · §4, §5 |
| `SDD-1-LAND-01` | D07, D20 · §4, §5 |
| `SDD-1-LAND-02` | D07, D20 · §4, §5 |
| `SDD-1-LAND-03` | D07, D20 · §4, §5 |
| `SDD-1-WITHDRAW-01` | D08, D25 · §5 |
| `SDD-1-WITHDRAW-02` | D08, D25 · §5 |
| `SDD-1-WITHDRAW-03` | D08, D25 · §5 |
| `SDD-1-SUPER-01` | D08, D25 · §5 |
| `SDD-1-SUPER-02` | D08, D25 · §5 |
| `SDD-1-SUPER-03` | D08, D25 · §5 |
| `SDD-1-SUPER-04` | D08, D25 · §5 |
| `SDD-1-SUPER-05` | D08, D25 · §5 |
| `SDD-1-POLICY-01` | D09, D19 · §7, §12 |
| `SDD-1-POLICY-02` | D09, D19 · §7, §12 |
| `SDD-1-POLICY-03` | D09, D19 · §7, §12 |
| `SDD-1-POLICY-04` | D09, D19 · §7, §12 |
| `SDD-1-POLICY-05` | D09, D19 · §7, §12 |
| `SDD-1-POLICY-06` | D09, D19 · §7, §12 |
| `SDD-1-DAG-01` | D17, D19 · §10, §12 |
| `SDD-1-DAG-02` | D17, D19 · §10, §12 |
| `SDD-1-DAG-03` | D17, D19 · §10, §12 |
| `SDD-1-DAG-04` | D17, D19 · §10, §12 |
| `SDD-1-DAG-05` | D17, D19 · §10, §12 |
| `SDD-1-DAG-06` | D17, D19 · §10, §12 |
| `SDD-1-DAG-07` | D17, D19 · §10, §12 |
| `SDD-1-DAG-08` | D17, D19 · §10, §12 |
| `SDD-1-DAG-09` | D17, D19 · §10, §12 |
| `SDD-1-DAG-10` | D17, D19 · §10, §12 |
| `SDD-1-CENSUS-01` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-02` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-03` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-04` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-05` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-06` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-07` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-08` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-09` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-10` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-11` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-12` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-13` | D19, D21, D27 · §12 |
| `SDD-1-CENSUS-14` | D19, D21, D27 · §12 |
| `SDD-1-ADAPTER-01` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-02` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-03` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-04` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-05` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-06` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-07` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-08` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-09` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-10` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-11` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-12` | D01, D02, D22 · §13, §14 |
| `SDD-1-ADAPTER-13` | D01, D02, D22 · §13, §14 |
| `SDD-1-WIRE-01` | D16 · §10 |
| `SDD-1-WIRE-02` | D16 · §10 |
| `SDD-1-WIRE-03` | D16 · §10 |
| `SDD-1-WIRE-04` | D16 · §10 |
| `SDD-1-WIRE-05` | D16 · §10 |
| `SDD-1-WSPP-01` | D16, D17 · §10 |
| `SDD-1-WSPP-02` | D16, D17 · §10 |
| `SDD-1-WSPP-03` | D16, D17 · §10 |
| `SDD-1-WSPP-04` | D16, D17 · §10 |
| `SDD-1-WSCI-01` | D16, D17 · §10 |
| `SDD-1-WSCI-02` | D16, D17 · §10 |
| `SDD-1-WSCI-03` | D16, D17 · §10 |
| `SDD-1-WSCI-04` | D16, D17 · §10 |
| `SDD-1-PPRE-01` | D16, D17 · §10 |
| `SDD-1-PPRE-02` | D16, D17 · §10 |
| `SDD-1-PPRE-03` | D16, D17 · §10 |
| `SDD-1-PPRE-04` | D16, D17 · §10 |
| `SDD-1-PCI-01` | D16, D17, D18 · §10, §11 |
| `SDD-1-PCI-02` | D16, D17, D18 · §10, §11 |
| `SDD-1-PCI-03` | D16, D17, D18 · §10, §11 |
| `SDD-1-PCI-04` | D16, D17, D18 · §10, §11 |
| `SDD-1-PCI-05` | D16, D17, D18 · §10, §11 |
| `SDD-1-PCI-06` | D16, D17, D18 · §10, §11 |
| `SDD-1-ADV-01` | D16 · §10 |
| `SDD-1-ADV-02` | D16 · §10 |
| `SDD-1-ADV-03` | D16 · §10 |

## 19. Rejected alternatives

- Копировать Spec Kit/OpenSpec целиком: создаёт второй workflow и размывает уже
  работающие Kachō gates/roles.
- Оставить design/tasks optional: acceptance не определяет технический failure
  model, а convergence нечего сравнивать.
- Хранить `effective_stage` в manifest: ручное поле подменяет доказательство.
- Один hash всего package: downstream record инвалидирует upstream approval.
- Включать review/evidence/convergence record в собственный subject: hash cycle.
- Пиновать candidate head внутри tracked record того же commit: commit-level
  self-cycle; record обязан ссылаться на pre-record source commit.
- Один mutable `reviews/**` envelope для всех фаз: landing/archive делали бы
  convergence stale; phase sets замораживаются по направлению DAG.
- Читать policy из candidate head: self-authorizing change.
- Доверять `role:`/`authorized_actor:` из YAML без external event: spoofable.
- Считать commit SHA равенством содержимого: ломает squash/cherry-pick и не
  доказывает applied blobs.
- Свободный prose `N/A`: specialist review можно обойти формулировкой.
- Один owner для RED у tester и implementer: невозможно доказать RED-before-code.
- Пускать Change Graph через старый workspace `run-all` VOID: NOT_EXECUTED станет
  nonblocking.
- Fetch product `main` в CI: плавающий ref не является candidate coordinate.
- Расширить legacy acceptance ledger новым смыслом: migration-specific проверки
  и short historical revisions станут ложной authority.
- Untracked adapters: CI не способен доказать byte drift локальных файлов.
- Copy only `SKILL.md`: nested references/assets исчезают.
- Native YAML implicit types/anchors: canonical input неоднозначен.
- Persistent authority cache: вчерашнее разрешение переживает revoke/изменение.
- Backfill 173 historical acceptance documents: изобретает историю и не отличает
  active work от закрытого.
- Закончить bootstrap на P1: после него некуда положить durable
  convergence/landing/archive records; W2–W5 являются exact-limited finalizer.

## 20. Bootstrap handoff

SDD-1 остаётся legacy bootstrap и не создаёт себе фиктивный package. После review
этого design порядок таков:

1. `class-exposure-analyst` revalidates all `CGX-01..22` against exact design SHA.
2. Pre-code `system-design-reviewer` проверяет authority epoch, pre-record
   projections, phase-frozen digest DAG и partial states W0–W5.
3. Security review проверяет GitHub trust root, public evidence, generated hooks,
   path traversal и secret handling.
4. `superpowers:writing-plans` создаёт tasks с exact files/interfaces/commands.
5. `integration-tester` единолично создаёт test driver/fixtures и доказывает RED.
6. Только после `RED_PROVEN` начинается implementation.

До review владельца этот документ не разрешает implementation и не утверждает
`DESIGN_APPROVED`.
