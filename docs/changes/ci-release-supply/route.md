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
