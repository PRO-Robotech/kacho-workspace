---
name: rule-MANIFEST
description: "Состав корпуса: что какое правило покрывает, чем обеспечено и кто его применяет"
---

**Архив:** `.claude/backup/MANIFEST.md`

## Дом правил, путь к агенту, форма строки реестра

mf-rules-not-autoloaded-dup · правило в окне только через агента · check-04-rule-agent-binding.sh · red: правило без привязки к агенту
mf-no-second-rulebook · второй каталог правил не заводится · check-01-corpus-matches-manifest.sh · red: правило вне `.claude/rules/`
mf-column-holder · держатель — имя гейта либо «вниманием» · check-03-manifest-row-is-complete.sh · red: держатель не назван
mf-column-agents-explicit · агенты поимённо, не шаблоном · check-04 в обе стороны · red: правило без агента; агент без правила; шаблон подхватывает агента молча
mf-table-is-sole-declaration · `MANIFEST.md` — одна таблица состава; `.claude/rules/` — единственный дом · check-01 · red: файл без строки; строка без файла
mf-registry-table-30-rows · строка: `<файл> \| <триггер> \| <гейт> \| <агенты>` · rules-gate check-01, check-03, check-04 · red: строка без гейта; агенты разошлись с `skills:`
mf-debt-names-its-row · держатель `ЗАВЕСТИ` без имени — долг на гейт с именем самой строки, `ЗАВЕСТИ <имя>` — на гейт с другим именем · scripts/rules-gate/measure.sh --form (счёт различных долгов) · red: голое `ЗАВЕСТИ` прочитано как долг без имени
mf-archive-anchor · строка `**Архив:**` шапки правила ведёт в `.claude/backup/<файл>.md` — доводы, замеры, снятые редакции; архив не норма и не грузится · вниманием · red: довод или замер записан строкой-нормой

| правило | включается действием | чем соблюдение обеспечено | закреплено за агентами (предзагрузка) |
|---|---|---|---|
| `00-kacho-core.md` | решение о продукте; именование; отказ; круг ревью; число о дереве; сдача правки | двадцать два запрета, у каждого — гейт, «вниманием» или долг | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `check-verifier`; `ci-watcher`; `class-exposure-analyst`; `convergence-reviewer`; `db-architect-reviewer`; `deploy-engineer`; `docs-writer`; `git-operator`; `go-implementer`; `go-style-reviewer`; `integration-tester`; `landing-reviewer`; `load-tester`; `migration-writer`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `scout`; `security-auditor`; `service-scaffolder`; `system-design-reviewer`; `tooling-maintainer`; `ui-implementer`; `ui-reviewer`; `vault-scribe`; `wave-reviewer` |
| `git-issues.md` | задача, метки, комментарии, ветка, коммит; сборка и запрос волны; каскад; вливание и снятие ветки; фазы в трекер | docs-gate check-01, check-03, check-05; tooling-gate check-19 (маршрут посадки), check-20 (`scripts/cascade-census.sh`), check-22, check-23 (имя ветки); `scripts/branch-audit.sh`; хук `branches-clean`; переписи `gh issue list`, `gh pr list` | `git-operator` |
| `MANIFEST.md` | заведение, снятие, переименование правила | rules-gate check-01 (состав), check-03 (полнота строки) | `tooling-maintainer`; `wave-reviewer` |
| `api-conventions.md` | правка `proto/**`, `gateway/internal/**`, `services/*/internal/handler/**`, `services/*/internal/apps/**/api/**` | `buf lint`; `buf breaking`; гейт каталога разрешений; `corevalidate.ResourceID` | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `class-exposure-analyst`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `service-scaffolder` |
| `data-integrity.md` | правка `services/*/internal/migrations/*.sql`, `services/*/internal/repo/**` | проба с конкурирующими транзакциями; FK/UNIQUE/EXCLUDE в схеме | `acceptance-author`; `acceptance-reviewer`; `class-exposure-analyst`; `db-architect-reviewer`; `migration-writer`; `rpc-implementer`; `system-design-reviewer` |
| `security.md` | новый слушатель или RPC; правка `deploy/helm/**/values*.yaml`; публичный текст | гейт посадки; boot-guard; признак восстановимости (человеком) | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `class-exposure-analyst`; `deploy-engineer`; `proto-api-reviewer`; `proto-sync`; `rpc-implementer`; `security-auditor`; `service-scaffolder`; `system-design-reviewer` |
| `security-hardening.md` | аудит-раунд; отзыв доступа; правка модели прав; супер-доступ | девять инвариантов раунда; отношение, не выполнимое подстановкой | `api-gateway-registrar`; `class-exposure-analyst`; `deploy-engineer`; `go-style-reviewer`; `rpc-implementer`; `security-auditor` |
| `security-disclosure.md` | публичный текст: коммит, issue, PR, vault; перенос | признак восстановимости (человеком); сохранность содержимым | `acceptance-author`; `convergence-reviewer`; `docs-writer`; `git-operator`; `landing-reviewer`; `qa-test-engineer`; `security-auditor`; `vault-scribe` |
| `testing.md` | план опыта; проба, гейт, страж; чтение вердикта; замер | инъекция настоящим входом; перепись объёма; код возврата | `check-verifier`; `go-implementer`; `integration-tester`; `qa-test-engineer`; `tooling-maintainer`; `wave-reviewer` |
| `testing-verdict.md` | чтение вердикта; разбор чужого красного | область зелёного; код возврата; недействительный прогон отличён от красного | `check-verifier`; `ci-watcher`; `go-implementer`; `integration-tester`; `landing-reviewer`; `load-tester`; `scout` |
| `testing-newman.md` | правка `tests/newman/**`; сквозная проба через край; путь края; выкатка, тронувшая край | `assert-suites-green.sh`; `validate-cases.py`; реальная задержка поллера; пул под `--jobs` | `integration-tester`; `landing-reviewer`; `qa-test-engineer` |
| `testing-load.md` | замер под нагрузкой; сравнение прогонов | одна посадка на вопрос; прогрев; потолок по отказам | `load-tester` |
| `polyrepo.md` | правка `**/go.mod`, `proto/**`, `services/*/internal/clients/**`; новое ребро между репозиториями | `go list -deps ./...` по модулям; `! grep replace github.com/PRO-Robotech -- go.mod`; гейт границы поставки (`kaname`, `internal/supplyhygiene`) | `proto-api-reviewer`; `proto-sync`; `service-scaffolder`; `system-design-reviewer` |
| `architecture.md` | правка `services/*/internal/**`, `pkg/**`, `**/cmd/*/main.go` | гейт импорт-графа; отсутствие pgx/grpc в domain; `scripts/foundation-candidates` (вторая прописка) | `go-implementer`; `go-style-reviewer`; `rpc-implementer`; `service-scaffolder`; `system-design-reviewer`; `wave-reviewer` |
| `ui.md` | правка `ui-future/**` | `npm test` модуля; гейт единого источника; `console-list-filter-declared` | `ui-implementer`; `ui-reviewer` |
| `e2e-flow.md` | правка `tests/newman/**`, `ui-future/e2e/**`; заведение набора | `assert-suites-green.sh`; `exec-coverage.py` | `integration-tester`; `landing-reviewer`; `qa-test-engineer`; `ui-implementer` |
| `subscription.md` | правка `corelib/subscription`, `corelib/outbox`, `services/*/internal/subscriptionjournal`, `gateway/internal/subscriptionstream` | девять гейтов `internal/repohygiene` | `go-implementer` |
| `ai-tooling.md` | правка `.claude/**` | `skills-gate`; `tooling-gate`; `rules-gate` | `tooling-maintainer` |
| `flow-acceleration.md` | раздача полос и срок; сборка волны; схождение документов | `scripts/lane-schedule/` (`inject.sh`, `mutants.py`; инструмент — ориентир, не гейт); поле «вопросы владельцу» ВОЗВРАТа | `acceptance-author`; `acceptance-reviewer`; `class-exposure-analyst`; `git-operator`; `scout`; `tooling-maintainer` |
