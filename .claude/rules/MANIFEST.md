# Состав корпуса: что какое правило покрывает, чем держится и кто его применяет

Правила **не грузятся сами никому** (решение владельца 2026-09-17, `01-wave-contract.md`
§«Кто какое правило держит»): каталог `.claude/rules/` снят с автозагрузки в
`.claude/settings.json`, а корневой `CLAUDE.md` корпус не импортирует. Правило попадает
в окно только через агента, за которым оно закреплено: у агента во frontmatter
`skills: rule-<имя>`, и харнесс грузит файл целиком при старте.

Отсюда три колонки, и каждая отвечает на свой вопрос:

- **включается действием** — что относится к делу, когда тронут этот путь. По ней
  диспетчер понимает, чья это область, а ревьюер проверяет, что полоса смотрела туда,
  куда следовало.
- **чем соблюдение держится** — главное в таблице и от раскладки не зависело никогда:
  правило в окне соблюдением не является, судит результат гейт.
- **закреплено за агентами** — кому оно предзагружается. Это ОБЪЯВЛЕНИЕ; исполнение —
  ключ `skills:` в определении агента, и `scripts/rules-gate/` сверяет их в обе стороны:
  правило без агента (его не прочтёт никто) и агент со ссылкой на несуществующее
  правило — обе находки. Перечень поимённый, а не шаблоном «все исполнители»: шаблон
  подхватывает нового агента молча, и тогда «кому это грузится» перестаёт быть решением.

Условная загрузка отдельного правила по триггеру объявляется в теле агента
(раздел «Правила по триггеру») и в этой колонке не отражается: она про то, что у агента
есть всегда.

Таблица — **единственное объявление состава**. `scripts/rules-gate/` сверяет её с
каталогом в обе стороны: файл без строки и строка без файла — обе находки.

| правило | включается действием | чем соблюдение держится | закреплено за агентами (предзагрузка) |
|---|---|---|---|
| `00-kacho-core.md` | любое решение о продукте · именование · отказ от работы | двадцать запретов, у каждого назван свой гейт внутри | `acceptance-author` · `acceptance-reviewer` · `api-gateway-registrar` · `check-verifier` · `ci-watcher` · `class-exposure-analyst` · `convergence-reviewer` · `db-architect-reviewer` · `deploy-engineer` · `docs-writer` · `git-operator` · `go-implementer` · `go-style-reviewer` · `integration-tester` · `landing-reviewer` · `load-tester` · `migration-writer` · `proto-api-reviewer` · `proto-sync` · `qa-test-engineer` · `rpc-implementer` · `scout` · `security-auditor` · `service-scaffolder` · `system-design-reviewer` · `tooling-maintainer` · `ui-implementer` · `ui-reviewer` · `vault-scribe` · `wave-reviewer` |
| `01-wave-contract.md` | раздача волны · заведение ревьюера · правка любого файла `.claude/rules/` | `scripts/rules-gate/` держит состав; величину корпуса — внимание, и это сказано там прямо | `tooling-maintainer` · `wave-reviewer` |
| `writing.md` | отчёт · тело задачи · сообщение коммита · комментарий · правило | вниманием; проверяемая половина названа в §10 | `acceptance-author` · `acceptance-reviewer` · `api-gateway-registrar` · `check-verifier` · `ci-watcher` · `class-exposure-analyst` · `convergence-reviewer` · `db-architect-reviewer` · `deploy-engineer` · `docs-writer` · `git-operator` · `go-implementer` · `go-style-reviewer` · `integration-tester` · `landing-reviewer` · `load-tester` · `migration-writer` · `proto-api-reviewer` · `proto-sync` · `qa-test-engineer` · `rpc-implementer` · `scout` · `security-auditor` · `service-scaffolder` · `system-design-reviewer` · `tooling-maintainer` · `ui-implementer` · `ui-reviewer` · `vault-scribe` · `wave-reviewer` |
| `rag.md` | исследование чужого кода · поиск координаты | `rag status` · отложенный набор 400 вопросов | `api-gateway-registrar` · `check-verifier` · `class-exposure-analyst` · `db-architect-reviewer` · `deploy-engineer` · `docs-writer` · `go-implementer` · `go-style-reviewer` · `integration-tester` · `migration-writer` · `proto-api-reviewer` · `proto-sync` · `qa-test-engineer` · `rpc-implementer` · `scout` · `security-auditor` · `service-scaffolder` · `system-design-reviewer` · `tooling-maintainer` · `ui-implementer` · `ui-reviewer` · `wave-reviewer` |
| `MANIFEST.md` | заведение правила · снятие правила · переименование файла корпуса | `scripts/rules-gate/check-01-corpus-matches-manifest.sh` (состав) · `check-03-manifest-row-is-complete.sh` (полнота строки) | `tooling-maintainer` · `wave-reviewer` |
| `api-conventions.md` | правка `proto/**`, `gateway/internal/**`, `services/*/internal/handler/**`, `services/*/internal/apps/**/api/**` | `buf lint` · `buf breaking` · гейт каталога разрешений · `corevalidate.ResourceID` | `acceptance-author` · `acceptance-reviewer` · `api-gateway-registrar` · `class-exposure-analyst` · `proto-api-reviewer` · `proto-sync` · `qa-test-engineer` · `rpc-implementer` · `service-scaffolder` |
| `data-integrity.md` | правка `services/*/internal/migrations/*.sql`, `services/*/internal/repo/**` | интеграционная проба с конкурирующими транзакциями · FK/UNIQUE/EXCLUDE в схеме | `acceptance-author` · `acceptance-reviewer` · `class-exposure-analyst` · `db-architect-reviewer` · `migration-writer` · `rpc-implementer` · `system-design-reviewer` |
| `security.md` | новый слушатель · новый RPC · правка `deploy/helm/**/values*.yaml` · публичный текст (коммит, issue, vault) | гейт посадки · boot-guard · признак восстановимости (человеком) | `acceptance-author` · `acceptance-reviewer` · `api-gateway-registrar` · `class-exposure-analyst` · `deploy-engineer` · `proto-api-reviewer` · `proto-sync` · `rpc-implementer` · `security-auditor` · `service-scaffolder` · `system-design-reviewer` |
| `security-hardening.md` | аудит-раунд · отзыв доступа · правка модели прав · супер-доступ | девять инвариантов раунда · отношение, не выполнимое подстановкой | `api-gateway-registrar` · `class-exposure-analyst` · `deploy-engineer` · `go-style-reviewer` · `rpc-implementer` · `security-auditor` |
| `security-disclosure.md` | публичный текст: коммит, issue, PR, vault · `squash` · `cherry-pick` | признак восстановимости (человеком) · доказательство сохранности содержимым | `acceptance-author` · `convergence-reviewer` · `docs-writer` · `git-operator` · `landing-reviewer` · `qa-test-engineer` · `security-auditor` · `vault-scribe` |
| `testing.md` | написание пробы, гейта, стража · чтение вердикта прогона · замер под нагрузкой | инъекция настоящим входом · перепись объёма · код возврата | `check-verifier` · `go-implementer` · `integration-tester` · `qa-test-engineer` · `tooling-maintainer` · `wave-reviewer` |
| `testing-verdict.md` | чтение вердикта прогона · разбор чужого красного · оценка «зелёного» | область зелёного · код возврата · недействительный прогон отличён от красного | `check-verifier` · `ci-watcher` · `go-implementer` · `integration-tester` · `landing-reviewer` · `load-tester` · `scout` |
| `testing-newman.md` | правка `tests/newman/**` · сквозная проба через край | `assert-suites-green.sh` · реальная задержка поллера · пул под `--jobs` | `integration-tester` · `qa-test-engineer` |
| `testing-load.md` | замер под нагрузкой · сравнение прогонов · заявление о производительности | одна посадка на вопрос · прогрев · потолок по отказам, а не по времени | `load-tester` |
| `git-issues.md` | `git commit` · `git push` · `git merge` · `gh pr` · `gh issue` · снятие ветки | `scripts/branch-audit.sh` · `scripts/merge-readiness.sh` · перепись меток | `ci-watcher` · `convergence-reviewer` · `git-operator` · `landing-reviewer` |
| `git-issues-branch-audit.md` | снятие ветки · вливание · вопрос «не потеряна ли работа» | `scripts/branch-audit.sh` · семь признаков вливания · срок годности вердикта | `convergence-reviewer` |
| `git-issues-issue-lifecycle.md` | `gh issue` · закрытие задачи · метка `blocked` · возражение рецензента | перепись меток · авто-закрытие вливанием · отзыв «вопрос закрыт» | `acceptance-reviewer` · `git-operator` |
| `git-issues-ci-runs.md` | чтение вердикта конвейера · порядок предотправочных проверок | `scripts/merge-readiness.sh` · шаг под `bash -e` | `ci-watcher` · `git-operator` · `landing-reviewer` |
| `multi-agent-flow.md` | **оркестратор**: раздача волны, захват задачи, работа в общей копии | у каждой полосы назван свой агент · перепись работ в единственном экземпляре | `git-operator` |
| `multi-agent-flow-shared-tree.md` | работа в ОБЩЕЙ машине и общем дереве: заведение ветки, рабочая копия, `tmp/`, `git push` | перепись работ в единственном экземпляре · `scripts/branch-audit.sh` · запрет прямого push в `main` | `ci-watcher` · `deploy-engineer` · `git-operator` · `load-tester` |
| `multi-agent-flow-orchestration.md` | **оркестратор**: раздача волны, форма задания полосе, сборка волны, приёмка результата | у каждой полосы назван свой агент · эксперимент вместо чтения отчёта | `check-verifier` · `wave-reviewer` |
| `multi-agent-flow-waiting.md` | заведение наблюдателя · ожидание чужого вердикта | `scripts/compliance/` посадка `watcher` · порог, не срабатывающий на штатном состоянии | `ci-watcher` · `deploy-engineer` · `load-tester` |
| `polyrepo.md` | правка `**/go.mod`, `proto/**`, `services/*/internal/clients/**` · новое ребро между репозиториями | `go list -deps ./...` по каждому модулю · `! grep replace github.com/PRO-Robotech -- go.mod` · гейт границы поставки в репозитории службы (`kaname`, каталог `internal/supplyhygiene`) | `proto-api-reviewer` · `proto-sync` · `service-scaffolder` · `system-design-reviewer` |
| `architecture.md` | правка `services/*/internal/**`, `pkg/**`, `**/cmd/*/main.go` | гейт импорт-графа · отсутствие pgx/grpc в domain | `go-implementer` · `go-style-reviewer` · `rpc-implementer` · `service-scaffolder` · `system-design-reviewer` · `wave-reviewer` |
| `ui.md` | правка `ui-future/**` | `npm test` модуля · гейт единого источника · `console-list-filter-declared` | `ui-implementer` · `ui-reviewer` |
| `e2e-flow.md` | правка `tests/newman/**`, `ui-future/e2e/**` · заведение набора | `assert-suites-green.sh` · `exec-coverage.py` | `integration-tester` · `landing-reviewer` · `qa-test-engineer` · `ui-implementer` |
| `subscription.md` | правка `corelib/subscription`, `corelib/outbox`, `services/*/internal/subscriptionjournal`, `gateway/internal/subscriptionstream` | девять гейтов `internal/repohygiene` | `go-implementer` |
| `vault.md` | правка `obsidian/kacho/**` · закрытие задачи | `scripts/vault-gate/run-all.sh` | `vault-scribe` |
| `ai-tooling.md` | правка `.claude/**` | `skills-gate` · `tooling-gate` · `adapter-gate` · `rules-gate` | `tooling-maintainer` |
| `change-graph.md` | ведение изменения по контуру | `scripts/change-graph-gate/run.py` — обязательность начинается с cutover | `acceptance-author` · `acceptance-reviewer` · `convergence-reviewer` · `integration-tester` · `tooling-maintainer` |

## Второго каталога правил нет

`.claude/rulebook/` **снят** решением владельца 2026-09-13 и обратно не заводится. Его
возрождение — находка `rules-gate`, а не организационная свобода: правило вне
единственного дома не попадает ни в одну строку этой таблицы, а значит не закреплено ни
за одним агентом — его не прочтёт никто, и заметить это по поведению агента нечем.

Здесь прежде стоял раздел «Ядро не растёт» с доводом против переноса. Довод был
верен для своей раскладки и **отозван вместе с ней**; его число живёт в контракте
волны — единственном владельце этой величины, — и там же названо, что именно
решение купило и чего не купило.
