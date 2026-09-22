---
name: rule-MANIFEST
description: "Состав корпуса: что какое правило покрывает, чем обеспечено и кто его применяет"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/MANIFEST.md`

# Состав корпуса: что какое правило покрывает, чем обеспечено и кто его применяет

## Дом правил, путь к агенту, форма строки реестра

mf-rules-not-autoloaded-dup · правило в окне только через агента · check-04-rule-agent-binding.sh · red: правило без привязки к агенту
mf-no-second-rulebook · второй каталог правил не заводится · check-01-corpus-matches-manifest.sh · red: правило вне `.claude/rules/`
mf-column-holder · держатель — имя гейта либо «вниманием» · check-03-manifest-row-is-complete.sh · red: держатель не назван
mf-column-agents-explicit · агенты поимённо, не шаблоном · check-04-rule-agent-binding.sh в обе стороны · red: правило без агента; агент без правила; шаблон подхватывает агента молча
mf-table-is-sole-declaration · `MANIFEST.md` — одна таблица состава; `.claude/rules/` — единственный дом · check-01-corpus-matches-manifest.sh · red: файл без строки; строка без файла
mf-registry-table-30-rows · строка: `<файл> \| <триггер> \| <гейт> \| <агенты>` · check-01-corpus-matches-manifest.sh / check-03-manifest-row-is-complete.sh / check-04-rule-agent-binding.sh · red: строка без гейта; агенты разошлись с `skills:`

| правило | включается действием | чем соблюдение обеспечено | закреплено за агентами (предзагрузка) |
|---|---|---|---|
| `00-kacho-core.md` | любое решение о продукте; именование; отказ от работы; круг ревью; число о дереве; сдача правки | двадцать два запрета; у каждого в строке — гейт, «вниманием» или долг на гейт | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `check-verifier`; `ci-watcher`; `class-exposure-analyst`; `convergence-reviewer`; `db-architect-reviewer`; `deploy-engineer`; `docs-writer`; `git-operator`; `go-implementer`; `go-style-reviewer`; `integration-tester`; `landing-reviewer`; `load-tester`; `migration-writer`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `scout`; `security-auditor`; `service-scaffolder`; `system-design-reviewer`; `tooling-maintainer`; `ui-implementer`; `ui-reviewer`; `vault-scribe`; `wave-reviewer` |
| `git-issues.md` | заведение задачи; разметка меток и комментариев; перевод фазы и под-фазы в трекер; сборка волны и запрос на слияние в ствол | `scripts/docs-gate/check-01-acceptance-verdict.py` (вердикт приёмки); `check-03-scope-row-scenario.py` (сценарий строки Scope); `check-05-ledger-verdict-reproduces.py`; `scripts/tooling-gate/check-10-landing-route-is-one-mr-per-wave.sh` (маршрут посадки и срок заведения задачи о безопасности — в корпусе); перепись меток `gh issue list`; перепись открытых запросов `gh pr list --base main` | `git-operator` |
| `MANIFEST.md` | заведение правила; снятие правила; переименование файла корпуса | `scripts/rules-gate/check-01-corpus-matches-manifest.sh` (состав); `check-03-manifest-row-is-complete.sh` (полнота строки) | `tooling-maintainer`; `wave-reviewer` |
| `api-conventions.md` | правка `proto/**`, `gateway/internal/**`, `services/*/internal/handler/**`, `services/*/internal/apps/**/api/**` | `buf lint`; `buf breaking`; гейт каталога разрешений; `corevalidate.ResourceID` | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `class-exposure-analyst`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `service-scaffolder` |
| `data-integrity.md` | правка `services/*/internal/migrations/*.sql`, `services/*/internal/repo/**` | интеграционная проба с конкурирующими транзакциями; FK/UNIQUE/EXCLUDE в схеме | `acceptance-author`; `acceptance-reviewer`; `class-exposure-analyst`; `db-architect-reviewer`; `migration-writer`; `rpc-implementer`; `system-design-reviewer` |
| `security.md` | новый слушатель; новый RPC; правка `deploy/helm/**/values*.yaml`; публичный текст (коммит, issue, vault) | гейт посадки; boot-guard; признак восстановимости (человеком) | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `class-exposure-analyst`; `deploy-engineer`; `proto-api-reviewer`; `proto-sync`; `rpc-implementer`; `security-auditor`; `service-scaffolder`; `system-design-reviewer` |
| `security-hardening.md` | аудит-раунд; отзыв доступа; правка модели прав; супер-доступ | девять инвариантов раунда; отношение, не выполнимое подстановкой | `api-gateway-registrar`; `class-exposure-analyst`; `deploy-engineer`; `go-style-reviewer`; `rpc-implementer`; `security-auditor` |
| `security-disclosure.md` | публичный текст: коммит, issue, PR, vault; `squash`; `cherry-pick` | признак восстановимости (человеком); доказательство сохранности содержимым | `acceptance-author`; `convergence-reviewer`; `docs-writer`; `git-operator`; `landing-reviewer`; `qa-test-engineer`; `security-auditor`; `vault-scribe` |
| `testing.md` | написание пробы, гейта, стража; чтение вердикта прогона; замер под нагрузкой | инъекция настоящим входом; перепись объёма; код возврата | `check-verifier`; `go-implementer`; `integration-tester`; `qa-test-engineer`; `tooling-maintainer`; `wave-reviewer` |
| `testing-verdict.md` | чтение вердикта прогона; разбор чужого красного; оценка «зелёного» | область зелёного; код возврата; недействительный прогон отличён от красного | `check-verifier`; `ci-watcher`; `go-implementer`; `integration-tester`; `landing-reviewer`; `load-tester`; `scout` |
| `testing-newman.md` | правка `tests/newman/**`; сквозная проба через край | `assert-suites-green.sh`; реальная задержка поллера; пул под `--jobs` | `integration-tester`; `qa-test-engineer` |
| `testing-load.md` | замер под нагрузкой; сравнение прогонов; заявление о производительности | одна посадка на вопрос; прогрев; потолок по отказам, а не по времени | `load-tester` |
| `polyrepo.md` | правка `**/go.mod`, `proto/**`, `services/*/internal/clients/**`; новое ребро между репозиториями | `go list -deps ./...` по каждому модулю; `! grep replace github.com/PRO-Robotech -- go.mod`; гейт границы поставки в репозитории службы (`kaname`, каталог `internal/supplyhygiene`) | `proto-api-reviewer`; `proto-sync`; `service-scaffolder`; `system-design-reviewer` |
| `architecture.md` | правка `services/*/internal/**`, `pkg/**`, `**/cmd/*/main.go` | гейт импорт-графа; отсутствие pgx/grpc в domain; `scripts/foundation-candidates` (вторая прописка) | `go-implementer`; `go-style-reviewer`; `rpc-implementer`; `service-scaffolder`; `system-design-reviewer`; `wave-reviewer` |
| `ui.md` | правка `ui-future/**` | `npm test` модуля; гейт единого источника; `console-list-filter-declared` | `ui-implementer`; `ui-reviewer` |
| `e2e-flow.md` | правка `tests/newman/**`, `ui-future/e2e/**`; заведение набора | `assert-suites-green.sh`; `exec-coverage.py` | `integration-tester`; `landing-reviewer`; `qa-test-engineer`; `ui-implementer` |
| `subscription.md` | правка `corelib/subscription`, `corelib/outbox`, `services/*/internal/subscriptionjournal`, `gateway/internal/subscriptionstream` | девять гейтов `internal/repohygiene` | `go-implementer` |
| `ai-tooling.md` | правка `.claude/**` | `skills-gate`; `tooling-gate`; `rules-gate` | `tooling-maintainer` |
