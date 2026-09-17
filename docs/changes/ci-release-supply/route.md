# CI-RS-1 — передача независимому tester

**Текущее состояние:** TASKS_READY. Только T1 test-only; source TESTS_PENDING.

Авторские commits 2f079c8e, e652c529 и 9e067edd механически импортированы
без изменения 13 author paths. Принятые acceptance/design/interface/holders
и исторические DRAFT headings сохраняют исходные байты. Их слова о будущих
reviews относятся к авторскому срезу; текущие фактические события записаны
здесь и в `change.yaml`, без переписывания исторических документов.

Независимый reviewer `/root/truth_tests` рассмотрел архитектуру автора
`/root/release_supply_arch`; root опубликовал четыре вердикта через actor
`pointpu`. Recorder `/root/e2e_audit` сверил exact body/subject/digest
с опубликованными ответами и API readback, не выполнял повторный review.

| Роль | Фактическое событие | Вердикт |
|---|---|---|
| acceptance-reviewer | [5715835485](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5715835485) | APPROVED |
| class-exposure-analyst initial | [5715835935](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5715835935) | RECORDED |
| class-exposure-analyst revalidation | [5715836426](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5715836426) | REVALIDATED |
| design-reviewer | [5715836975](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5715836975) | APPROVED |

Исходный независимый review SHA256
10918d0a508ad2f0ff45da4ad22c4d28396e18892cfc8b57fa78ccb36a690aa5
сохранён в `review-history/20260917-independent-review-9e067edd.md`.
Каждый внешний record имеет отдельные event/body/subject bindings.

## Разрешённый test handoff

Root открывает T1 независимому integration-tester `/root/truth_tests`.
Источник сценариев — exact CI-RS-01–22 и существующий `holders.yaml`;
routine interface — `interface.md` и `result.schema.json` из accepted subject.
Имена proposed executable не утверждают, что тесты уже написаны или запущены.
Tester фиксирует реальные fixtures, lawful/negative/empty/unread controls,
проверяет инструменты и harness перед оценкой поведения, сохраняет команды,
repo/SHA, непустой census, rc и raw evidence. NOT_EXECUTED отделяется от RED.

Следующий source transition требует отдельного captured independent RED
и решения root по точному scope. Никаких source mutations, product GREEN,
разрешения live release, consumer pins, main delivery или issue closure
этот переход не выдаёт. Политика, legacy census, исторические KAN-RELEASE
subjects, CI-NP и CI-DT остаются прежними.


## Последующие routine и bounded source события, 2026-09-17

Начальный handoff выше сохранён как история. Событие
[5716256869](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5716256869)
зафиксировало consolidated routine v2 с SHA256
cd0897c91c1a86cf0579fff5b9dd1a5a2c47f00848ed1fb926dff29f5c60f607.
Первый proposal и замечания архитектора R1–R4 сохранены побайтно рядом.
Root согласовал exact evidence/authority binding, candidate|repository union,
реальные Git/Go/archive operations и test-only compile bridge. Это routine
согласование не разрешало source или D8 producer execution.

Событие [5716590453](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5716590453)
открыло только CI-RS-07–09 consumers/preflight engine в manifest.go, archive.go
и consumers.go. Root прочитал holder автора /root/truth_tests, commit
9e9e9401ab5d133db7045da8c7304b57662ab3cc, и независимо повторил его:
3 RUN / 1 PASS / 2 FAIL / 0 SKIP, 82 capture pairs. После реальных prerequisites
установлен CAPABILITY_ABSENT: 27 prepared cases, 0 SUT invocations и 0 semantic
decisions. Отдельно воспроизведён пробел старого P8: неполный архив проходит
его witness, но полный consumer с двумя импортами отказывает; lawful архив
проходит. Событие не объявляет 27 семантических RED и не меняет P1–P8.

Событие [5716964873](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5716964873)
приняло отдельную test-only коррекцию Git transport в holder
d38aa34845a1bcfd0ce6e99ee69a2c3f04553f07. Canonical identity читается без
fixture rewrite; только реальные transport operations используют test mapping.
Root независимо подтвердил 16 parser controls, 3 identity controls и 2 transport
controls; 4 RUN / 2 PASS / 2 FAIL / 0 SKIP, 119 capture pairs. Прежние
325 evidence bindings сохранены, новые 457 проверены. Состояние 27 cases
остаётся CAPABILITY_ABSENT с нулём semantic decisions. Ограниченный source
допуск продолжается на исправленном holder; дополнение касается только
package comment doc.go с сохранением copyright/SPDX/package.

Exact records находятся в reviews/system-design-reviewer/routine-v2-5716256869.yaml,
reviews/landing-reviewer/consumer-scoped-red-5716590453.yaml и
reviews/landing-reviewer/consumer-bridge-correction-5716964873.yaml.
Recorder /root/e2e_audit только сохраняет независимые выводы /root.
Global TASKS_READY, все 22 сценария и accepted subjects неизменны.
Полный T1, остальной T2 source, candidate/pins/publisher/P9 wiring, полные
регрессии, отдельная D8 authority, protected delivery и closure остаются pending.
Эти записи не объявляют full release-supply GREEN или разрешение live release.


## Последующие независимые этапы, 2026-09-17

Recorder /root/e2e_audit переносит опубликованные выводы /root. Авторский GREEN
не заменяет независимый root verdict; прежние события и попытки сохранены побайтно.

Событие [5717180465](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5717180465): Nested-module correction только archive.go и consumers.go; 2 реальных решения, lawful false RED. Старые 27 cases и schema неизменны.
Record: reviews/landing-reviewer/nested-scoped-red-5717180465.yaml.

Событие [5717405622](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5717405622): Bounded consumer/nested implementation: 39 RUN / 39 PASS / 0 SKIP, 29 SUT cases, 221 capture pairs. Остальные режимы отдельны.
Record: reviews/integration-tester/consumer-scoped-green-5717405622.yaml.

Событие [5717407454](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5717407454): 14 SUT calls вернули USAGE_ERROR неподдержанного pins mode; разрешены только pins.go, manifest.go, consumers.go. Это не 14 отдельных semantic pin findings.
Record: reviews/landing-reviewer/pins-scoped-red-5717407454.yaml.

Событие [5717469012](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5717469012): Producer review R и execution E — отдельные subjects/authority events; exact input_files serialization. Синтетические vectors не дают live D8 authority.
Record: reviews/system-design-reviewer/serialization-routine-5717469012.yaml.

Событие [5717627211](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5717627211): Bounded pins и consumer regression: 56 RUN / 56 PASS / 0 SKIP, 43 SUT reports, 376 capture pairs. Live pins/main этим не утверждаются.
Record: reviews/integration-tester/pins-scoped-green-5717627211.yaml.

Событие [5718038428](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5718038428): Publisher admission и release-note protocol в существующем CLI; read-only probe, bounded readback после потерянного ответа без retry write. Только holder vocabulary, не source/live authorization.
Record: reviews/system-design-reviewer/publisher-routine-5718038428.yaml.

Событие [5718113086](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5718113086): 61 реальный compiled SUT call вернул schema-valid unsupported candidate mode; 64 RUN / 1 PASS / 63 FAIL / 0 SKIP. Разрешены ровно 6 source paths; additive publisher test coordinate отдельно, без publisher source authority.
Record: reviews/landing-reviewer/candidate-scoped-red-5718113086.yaml.

Consumer и pins GREEN относятся к указанным bounded implementations.
Candidate source допущен отдельно событием 5718113086 только в шести путях;
publisher routine и additive holder placement не разрешают publisher source.
Полный T1 из 22 сценариев, producer review/actual D8 authority, P9 wiring,
protected release и последующие consumer/main predicates ещё не завершены.
Global TASKS_READY сохраняется. Synthetic authority fixtures не дают live полномочий.


## Последующие publisher и checksum события, 2026-09-17

Следующие записи механически сохраняют уже опубликованные и повторно прочитанные
решения `/root` через actor `pointpu`. Recorder `/root/release_supply_arch`
не авторизует собственную реализацию и не выполняет новый независимый review.
Исторические subjects, holders, правила и предыдущие события не переписаны.

| Внешнее событие | Точный ограниченный scope | Record |
|---|---|---|
| [5718548000](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5718548000) | Candidate: независимые 120/120 PASS. Publisher: 50 подготовленных CAPABILITY_ABSENT, 0 вызовов SUT. Разрешены ровно 9 source paths; CLI/P9 и live authority исключены. | `reviews/landing-reviewer/publisher-source-5718548000.yaml` |
| [5718644045](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5718644045) | Foreign canonical proof: 6 RUN / 6 PASS, 5 фактических решений. Предыдущий прогон 120 тестов отдельный; foreign-only proof не покрывает receiving source. | `reviews/integration-tester/foreign-scoped-green-5718644045.yaml` |
| [5719181670](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5719181670) | Разрешены exact expected-empty CAS собственной ветви, личная snapshot identity и native credential transport. Подготовлено 52 случая, 0 вызовов SUT; cleanup failure сохранён; publisher GREEN не заявлен. | `reviews/landing-reviewer/publisher-cas-source-5719181670.yaml` |
| [5719582632](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5719582632) | После настоящих signed-log prerequisites получены 7 RED: 8 RUN / 8 FAIL с родительским тестом. Для public Go / SumDB разрешён только publisher_release.go; bypass и изменение budgets исключены. | `reviews/landing-reviewer/checksum-scoped-red-5719582632.yaml` |
| [5719665143](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5719665143) | Разрешён только независимый дополнительный holder: 22 профиля / 37 фазовых ячеек и отдельный release resume, actual squash/deletion и numbered PR detail. Product source не разрешён. | `reviews/landing-reviewer/deleted-head-holder-5719665143.yaml` |
| [5719792493](https://github.com/PRO-Robotech/kacho/issues/2588#issuecomment-5719792493) | Checksum: независимые 8 RUN / 8 PASS, 7 фактических Go-вызовов. Неудачная попытка с timestamp сохранена. Авторский прогон 80 узлов отдельный; полный D4/T5, live, CLI и deleted-head остаются незавершёнными. | `reviews/integration-tester/checksum-scoped-green-5719792493.yaml` |

Candidate 120, foreign 5, прежний full 206 на 0fb и checksum 7 — разные
ревизии и evidence scopes; они не складываются в выдуманный единый полный прогон.
Событие checksum GREEN отдельно называет авторский прогон 80 узлов, сохраняя
его отличие от независимого root исполнения. Global TASKS_READY сохраняется.
Ни одно из этих событий не предоставляет actual D8 live execution authority,
не утверждает опубликованный corelib tag/archive, main delivery или closure.
Новые CLI/P9 решения не зарегистрированы до их отдельного внешнего события.
