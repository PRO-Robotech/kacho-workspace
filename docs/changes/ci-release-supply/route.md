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
