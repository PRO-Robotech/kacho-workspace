# Что какое правило покрывает

Оркестратор кладёт применимое правило в задание полосы либо называет его
координатой отсюда. Полоса читает **только** то, что относится к её действию.

Раскладка выбрана замером: `scripts/compliance/`. Держит её `scripts/rules-gate/`.

| правило | включается действием | чем соблюдение держится |
|---|---|---|
| `api-conventions.md` | правка `proto/**`, `gateway/internal/**`, `services/*/internal/handler/**`, `services/*/internal/apps/**/api/**` | `buf lint` · `buf breaking` · гейт каталога разрешений · `corevalidate.ResourceID` |
| `data-integrity.md` | правка `services/*/internal/migrations/*.sql`, `services/*/internal/repo/**` | интеграционная проба с конкурирующими транзакциями · FK/UNIQUE/EXCLUDE в схеме |
| `security.md` | новый слушатель · новый RPC · правка `deploy/helm/**/values*.yaml` · публичный текст (коммит, issue, vault) | гейт посадки · boot-guard · признак восстановимости (человеком) |
| `testing.md` | написание пробы, гейта, стража · чтение вердикта прогона · замер под нагрузкой | инъекция настоящим входом · перепись объёма · код возврата |
| `git-issues.md` | `git commit` · `git push` · `git merge` · `gh pr` · `gh issue` · снятие ветки | `scripts/branch-audit.sh` · `scripts/merge-readiness.sh` · перепись меток |
| `multi-agent-flow.md` | **оркестратор**: раздача волны, захват задачи, работа в общей копии | у каждой полосы назван свой агент · перепись работ в единственном экземпляре |
| `polyrepo.md` | правка `**/go.mod`, `proto/**`, `services/*/internal/clients/**` · новое ребро | `! grep replace github.com/PRO-Robotech -- go.mod` · перечень рёбер |
| `architecture.md` | правка `services/*/internal/**`, `pkg/**`, `**/cmd/*/main.go` | гейт импорт-графа · отсутствие pgx/grpc в domain |
| `ui.md` | правка `ui-future/**` | `npm test` модуля · гейт единого источника · `console-list-filter-declared` |
| `e2e-flow.md` | правка `tests/newman/**`, `ui-future/e2e/**` · заведение набора | `assert-suites-green.sh` · `exec-coverage.py` |
| `subscription.md` | правка `pkg/subscription/**`, `**/subscriptionjournal/**`, `**outbox**` | девять гейтов `internal/repohygiene` |
| `vault.md` | правка `obsidian/kacho/**` · закрытие задачи | `scripts/vault-gate/run-all.sh` |
| `ai-tooling.md` | правка `.claude/**` | `skills-gate` · `tooling-gate` · `adapter-gate` · `rules-gate` |
| `change-graph.md` | ведение изменения по контуру | `scripts/change-graph-gate/run.py` — обязательность начинается с cutover |

## Ядро — читают все, всегда

`00-kacho-core.md` (запреты и naming) · `01-wave-contract.md` (устройство волны)
· `writing.md` (форма производимого текста).

Ядро **не растёт**: перенос сюда всех четырнадцати возвращает свод целиком в окно
каждого агента волны, одного — его долю. Величина и предикат, которым она получена,
живут в контракте волны — единственном их владельце; здесь они не пересказываются,
иначе два места об одном предмете разойдутся молча. Координата контракта в этом
разделе не пишется намеренно: всякое имя правила в обратных кавычках здесь читается
гейтом как ОБЪЯВЛЕНИЕ состава ядра. Переноса гейт не пропустит.
