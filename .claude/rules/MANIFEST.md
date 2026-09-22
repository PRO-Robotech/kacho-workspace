---
name: rule-MANIFEST
description: "Состав корпуса: что какое правило покрывает, чем обеспечено и кто его применяет"
---

**Архив**: `.claude/backup/MANIFEST.md`

# Состав корпуса: что какое правило покрывает, чем обеспечено и кто его применяет

## Дом правил, путь к агенту, форма строки реестра

mf-rules-not-autoloaded-dup · правило в окне только через агента · check-04-rule-agent-binding.sh · red: правило без привязки к агенту
mf-no-second-rulebook · второй каталог правил не заводится · check-01-corpus-matches-manifest.sh · red: правило вне `.claude/rules/`
mf-column-holder · держатель — имя гейта либо «вниманием» · check-03-manifest-row-is-complete.sh · red: держатель не назван
mf-column-agents-explicit · агенты поимённо, не шаблоном · check-04-rule-agent-binding.sh в обе стороны · red: правило без агента; агент без правила; шаблон подхватывает агента молча
mf-table-is-sole-declaration · `MANIFEST.md` — одна таблица состава; `.claude/rules/` — единственный дом · check-01-corpus-matches-manifest.sh · red: файл без строки; строка без файла
mf-registry-row-form · строка: `<файл> \| <триггер> \| <гейт> \| <агенты>` · check-01-corpus-matches-manifest.sh / check-03-manifest-row-is-complete.sh / check-04-rule-agent-binding.sh · red: строка без гейта; агенты разошлись с `skills:`

## Что такое `.claude/backup/<имя>.md`, на который ссылается каждое правило

Архив — **действующий дом раздела, не перенесённого в норму-строку**: сжатие оставляет там
разбор и замер, чей адрес `§«…»` из дерева продолжают называть. Правило чтения одно на весь
корпус: адрес `<файл>.md §«Заголовок»`, не найденный в `.claude/rules/<файл>.md`, ищется в
`.claude/backup/<файл>.md` по тому же имени — так резолвит и `check-07-address-resolves.sh`
(корпус старше архива). Прежняя строка 6 обещала архиву «доводы, замеры, снятые редакции»;
измерено 2026-09-22: по тем же адресам лежат действующие нормы, целей 10.

mf-archive-is-a-home · ищи раздел, не найденный в корпусе, в архиве по тому же имени файла · check-07-address-resolves.sh резолвит по корпусу И архиву · red: строка 6 обещает архиву только историю
mf-archive-not-addressed-by-live-briefing · переноси в норму-строку раздел, который называет живой брифинг или исполняемая оснастка · check-12-rule-coordinate-triple-is-complete.sh плюс check-07 · red: агент послан по адресу, которого в его окне нет

| правило | включается действием | чем соблюдение обеспечено | закреплено за агентами (предзагрузка) |
|---|---|---|---|
| `00-kacho-core.md` | любое решение о продукте; именование; отказ от работы | двадцать запретов, у каждого назван свой гейт внутри | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `check-verifier`; `ci-watcher`; `class-exposure-analyst`; `convergence-reviewer`; `db-architect-reviewer`; `deploy-engineer`; `docs-writer`; `git-operator`; `go-implementer`; `go-style-reviewer`; `integration-tester`; `landing-reviewer`; `load-tester`; `migration-writer`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `scout`; `security-auditor`; `service-scaffolder`; `system-design-reviewer`; `tooling-maintainer`; `ui-implementer`; `ui-reviewer`; `vault-scribe`; `wave-reviewer` |
| `git-issues.md` | заведение задачи; разметка меток и комментариев; перевод фазы и под-фазы в трекер | `scripts/docs-gate/check-01-acceptance-verdict.py` (вердикт приёмки); `check-03-scope-row-scenario.py` (сценарий строки Scope); `check-05-ledger-verdict-reproduces.py`; перепись меток `gh issue list` | `git-operator` |
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
| `architecture.md` | правка `services/*/internal/**`, `pkg/**`, `**/cmd/*/main.go` | гейт импорт-графа; отсутствие pgx/grpc в domain | `go-implementer`; `go-style-reviewer`; `rpc-implementer`; `service-scaffolder`; `system-design-reviewer`; `wave-reviewer` |
| `ui.md` | правка `ui-future/**` | `npm test` модуля; гейт единого источника; `console-list-filter-declared` | `ui-implementer`; `ui-reviewer` |
| `e2e-flow.md` | правка `tests/newman/**`, `ui-future/e2e/**`; заведение набора | `assert-suites-green.sh`; `exec-coverage.py` | `integration-tester`; `landing-reviewer`; `qa-test-engineer`; `ui-implementer` |
| `subscription.md` | правка `corelib/subscription`, `corelib/outbox`, `services/*/internal/subscriptionjournal`, `gateway/internal/subscriptionstream` | девять гейтов `internal/repohygiene` | `go-implementer` |
| `ai-tooling.md` | правка `.claude/**` | `skills-gate`; `tooling-gate`; `rules-gate` | `tooling-maintainer` |
| `01-wave-contract.md` | раздача волны; вердикт ревью по форме без доказательства | `scripts/compliance/`; перепись ролей ревью волны | `wave-reviewer` |
| `change-graph.md` | переход между фазами изменения В ВОРКСПЕЙСЕ (к полосам продукта контур не применяется) | `scripts/change-graph-gate/run-all.sh`; `docs-gate/check-01-acceptance-verdict.py` | `acceptance-reviewer`; `convergence-reviewer`; `landing-reviewer` |
| `git-issues-branch-audit.md` | перенос работы между ветками; снятие ветки; перепись веток | `scripts/branch-audit.sh`; `scripts/branch-audit-inject.sh` | `git-operator` |
| `git-issues-ci-runs.md` | разбор красного прогона; локальные проверки перед отправкой; правка шага конвейера | `scripts/ci-local.sh`; `scripts/tooling-gate` | `ci-watcher` |
| `git-issues-issue-lifecycle.md` | закрытие задачи; метка `blocked`; возражение рецензента | `scripts/docs-gate/check-01-acceptance-verdict.py`; `check-05-ledger-verdict-reproduces.py` | `git-operator` |
| `multi-agent-flow.md` | ведение задачи волной: захват, форма задачи, отправка, конец сессии | `scripts/branch-audit.sh`; `docs-gate check-03-scope-row-scenario.py` | `git-operator` |
| `multi-agent-flow-orchestration.md` | раздача заданий; сборка волны; приёмка работы-проверки | `scripts/rules-gate/check-05-dispatcher-routes-every-agent.sh`; форма задания рецензенту | `check-verifier`; `wave-reviewer` |
| `multi-agent-flow-shared-tree.md` | ветка, рабочая копия, чужое состояние, коды набора | `scripts/branch-audit.sh`; `scripts/*/run-all.sh` (коды 0/1/2) | `git-operator`; `tooling-maintainer` |
| `multi-agent-flow-waiting.md` | ожидание вердикта; заведение наблюдателя; правка его порогов | перепись идущих наблюдателей; `gh pr list` | `ci-watcher` |
| `rag.md` | вопрос к локальному индексу кода до широкого обхода дерева | `rag status` (ревизия индекса); отложенный набор `kacho-rag/bench/heldout.json` | `scout` |
| `vault.md` | чтение записок до кода; trail задачи; запись в `obsidian/kacho/**` | `scripts/vault-gate/run-all.sh`; `scripts/docs-gate/check-02-kac-trail-status.py` | `vault-scribe` |
