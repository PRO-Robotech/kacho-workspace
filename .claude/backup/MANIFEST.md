# Архив: MANIFEST.md

Снято 2026-09-20. Норма живёт в `.claude/rules/MANIFEST.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.

## Перенесено из строковой ревизии 2026-09-20 (класс C/D, без именованного гейта)

**mf-column-action** — колонка «включается действием»: что относится к делу, когда
тронут этот путь. По ней диспетчер понимает, чья это область, а ревьюер проверяет,
что полоса смотрела туда, куда следовало.

**mf-conditional-not-in-column** — условная загрузка отдельного правила по триггеру
объявляется в теле агента (раздел «Правила по триггеру») и в колонке «закреплено за
агентами» не отражается: она про то, что у агента есть всегда.

**mf-core-does-not-grow-revoked** — здесь прежде стоял раздел «Ядро не растёт» с
доводом против переноса. Довод был верен для своей раскладки и отозван вместе с
ней; его число живёт в контракте волны (`01-wave-contract.md`) — единственном
владельце этой величины, — и там же названо, что именно решение купило и чего не
купило.

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**mf-archive-anchor** — прежняя редакция:

mf-archive-anchor · строка `**Архив:**` в шапке правила ведёт в `.claude/backup/<файл>.md`: доводы, замеры, снятые редакции; архив нормой не является и не грузится · вниманием; адресом правила архив не считается (`ai-tooling.md#at-rule-address-as-written`) · red: довод или замер записан строкой-нормой

(второй проход того же сжатия)

**строка `git-issues.md`, колонка гейтов** — прежняя редакция:

`scripts/tooling-gate/check-19-landing-route-is-one-mr-per-wave.sh` (маршрут посадки и срок заведения задачи о безопасности — в корпусе); перепись меток `gh issue list`; перепись открытых запросов `gh pr list --base <ветка эпика>`

## Снято 2026-09-26 (ws#786): сжатие корпуса под потолок check-06 на сведении 786 с 771

Сведённое дерево `786` × `771` (волна-0 в волну-3) дало 208 847 знаков при потолке 200 000
(решение владельца 2026-09-19); потолок не поднимался. Нормы каскада закрытия и снятия влитых
веток (786) и требования волны-0 (771) сохранены под теми же id; ниже — ПРЕЖНИЕ редакции строк,
сжатых этим изменением, дословно (редакция сведения до сжатия).

mf-column-agents-explicit · агенты поимённо, не шаблоном · check-04-rule-agent-binding.sh в обе стороны · red: правило без агента; агент без правила; шаблон подхватывает агента молча
mf-table-is-sole-declaration · `MANIFEST.md` — одна таблица состава; `.claude/rules/` — единственный дом · check-01-corpus-matches-manifest.sh · red: файл без строки; строка без файла
mf-registry-table-30-rows · строка: `<файл> \| <триггер> \| <гейт> \| <агенты>` · check-01-corpus-matches-manifest.sh / check-03-manifest-row-is-complete.sh / check-04-rule-agent-binding.sh · red: строка без гейта; агенты разошлись с `skills:`
| `00-kacho-core.md` | любое решение о продукте; именование; отказ от работы; круг ревью; число о дереве; сдача правки | двадцать два запрета; у каждого в строке — гейт, «вниманием» или долг на гейт | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `check-verifier`; `ci-watcher`; `class-exposure-analyst`; `convergence-reviewer`; `db-architect-reviewer`; `deploy-engineer`; `docs-writer`; `git-operator`; `go-implementer`; `go-style-reviewer`; `integration-tester`; `landing-reviewer`; `load-tester`; `migration-writer`; `proto-api-reviewer`; `proto-sync`; `qa-test-engineer`; `rpc-implementer`; `scout`; `security-auditor`; `service-scaffolder`; `system-design-reviewer`; `tooling-maintainer`; `ui-implementer`; `ui-reviewer`; `vault-scribe`; `wave-reviewer` |
| `git-issues.md` | заведение задачи; разметка меток и комментариев; коммит; сборка волны и запрос в ветку эпика; закрытие задачи, волны и эпика; вливание и снятие влитой ветки; перевод фазы и под-фазы в трекер | `scripts/docs-gate/check-01-acceptance-verdict.py` (вердикт приёмки); `check-03-scope-row-scenario.py` (сценарий строки Scope); `check-05-ledger-verdict-reproduces.py`; `scripts/tooling-gate/check-19-landing-route-is-one-mr-per-wave.sh` (маршрут посадки, задача о безопасности); `scripts/cascade-census.sh` (tooling-gate check-20); `scripts/branch-audit.sh` по клонам и целям каскада; хук `branches-clean` — нижняя граница; переписи `gh issue list` и `gh pr list --base <ветка эпика>` | `git-operator` |
| `MANIFEST.md` | заведение правила; снятие правила; переименование файла корпуса | `scripts/rules-gate/check-01-corpus-matches-manifest.sh` (состав); `check-03-manifest-row-is-complete.sh` (полнота строки) | `tooling-maintainer`; `wave-reviewer` |
| `data-integrity.md` | правка `services/*/internal/migrations/*.sql`, `services/*/internal/repo/**` | интеграционная проба с конкурирующими транзакциями; FK/UNIQUE/EXCLUDE в схеме | `acceptance-author`; `acceptance-reviewer`; `class-exposure-analyst`; `db-architect-reviewer`; `migration-writer`; `rpc-implementer`; `system-design-reviewer` |
| `security.md` | новый слушатель; новый RPC; правка `deploy/helm/**/values*.yaml`; публичный текст (коммит, issue, vault) | гейт посадки; boot-guard; признак восстановимости (человеком) | `acceptance-author`; `acceptance-reviewer`; `api-gateway-registrar`; `class-exposure-analyst`; `deploy-engineer`; `proto-api-reviewer`; `proto-sync`; `rpc-implementer`; `security-auditor`; `service-scaffolder`; `system-design-reviewer` |
| `security-disclosure.md` | публичный текст: коммит, issue, PR, vault; `cherry-pick` | признак восстановимости (человеком); доказательство сохранности содержимым | `acceptance-author`; `convergence-reviewer`; `docs-writer`; `git-operator`; `landing-reviewer`; `qa-test-engineer`; `security-auditor`; `vault-scribe` |
| `testing.md` | план опыта; написание пробы, гейта, стража; чтение вердикта прогона; замер под нагрузкой | инъекция настоящим входом; перепись объёма; код возврата | `check-verifier`; `go-implementer`; `integration-tester`; `qa-test-engineer`; `tooling-maintainer`; `wave-reviewer` |
| `testing-verdict.md` | чтение вердикта прогона; разбор чужого красного; оценка «зелёного» | область зелёного; код возврата; недействительный прогон отличён от красного | `check-verifier`; `ci-watcher`; `go-implementer`; `integration-tester`; `landing-reviewer`; `load-tester`; `scout` |
| `testing-load.md` | замер под нагрузкой; сравнение прогонов; заявление о производительности | одна посадка на вопрос; прогрев; потолок по отказам, а не по времени | `load-tester` |
| `polyrepo.md` | правка `**/go.mod`, `proto/**`, `services/*/internal/clients/**`; новое ребро между репозиториями | `go list -deps ./...` по каждому модулю; `! grep replace github.com/PRO-Robotech -- go.mod`; гейт границы поставки в репозитории службы (`kaname`, каталог `internal/supplyhygiene`) | `proto-api-reviewer`; `proto-sync`; `service-scaffolder`; `system-design-reviewer` |
