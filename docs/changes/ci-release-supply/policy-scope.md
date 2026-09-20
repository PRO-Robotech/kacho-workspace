# CI-RS-1 — применимость policy и сохранение истории

**DRAFT, 2026-09-17.** Исследована policy SHA-256
`e3cfb84acccb42e3c1d9d34db1e332f8b48625826e0cd1aa76caadae9fad3629`
в workspace base `3f107bc6372ec0e0e855da90d5aabcb3fcc5788d`.

Policy именует cutover workspace `1202e3cf5f6cb4600294ceb2e30fa72b61630eac`
и Kachō `c2d573654cd755c6bbc6755ff0874c8c83501004`. Обе базы этого DRAFT
после своих cutover. По SDD-1 §«Cutover в двух Git DAG и legacy census»
new observable contract требует package; route legacy допустим лишь при
неизменном observable contract, а изменение зарегистрированного legacy subject
требует route migrate и package.

В текущем exact-set из 60 legacy coordinates нет #2230, #2258, #2588 и
отдельного KAN-RELEASE-1 subject. Это не основание добавить три задачи в
исторический census. Выбран **новый** post-cutover package CI-RS-1 с основной
координатой #2588 и двумя связанными задачами. Политика, census, authority и
история старого accepted KAN-RELEASE-1 сохраняются побайтово. Его §1.5/§8
связываются ссылкой как происхождение задач, не задним одобрением новых решений.

Такое разделение явно согласовано root в активной работе. Оно не является
acceptance approval. Если независимый review обнаружит затрагиваемый иной
registered legacy subject, executor обязан предъявить отдельный exact-entry
migrate diff и package linkage до реализации; не менять сразу весь census.

Четыре будущих независимых события: acceptance-reviewer на acceptance bytes,
class-exposure-analyst initial на тот же hash, class revalidation на design,
design-reviewer на design. Authorized actor читается из versioned policy и
проверяется внешним событием; роль в локальном файле сама себя не подтверждает.
После этих событий root может оформить TASKS_READY для test-only работы.
RED_PROVEN и IMPLEMENTING требуют отдельного captured independent RED.

Сейчас lifecycle `ISSUE_READY`; reviews/evidence/implementation diff set пусты
**потому, что стадия не пройдена**. Это не vacuous GREEN; `change.yaml` не
запрашивает переход. Этот пакет не создаёт fictitious external event bodies.

Corelib и Kaname названы координатами supply chain. Policy этого workspace
не объявляет для них несуществующий cutover SHA. Их реальные PR protections,
локальные правила и delivery checks проверяются при соответствующей поставке.
CI-NP-1 и CI-DT-1 уже имеют собственные subjects и историю; новый package
не переносит их scoped verdicts на незавершённые payload или delivery.
