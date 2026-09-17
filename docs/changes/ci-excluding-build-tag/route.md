# CI-EBT-1 — маршрут DRAFT

Дом контракта — workspace; дом gate и будущего holder — Kacho. Основание — #2672,
новый post-cutover subject, отсутствующий в historical legacy census. Scope,
interface, exact 11-ID matrix и tasks связаны hashes в change.yaml.

Исходный срез e893: фаза ISSUE_READY. Автор подготовил DRAFT после операционной диагностики
main b5fa; предварительный root readback узкой архитектуры не объявляется
внешним approval. На том срезе reviews и implementation_diff_set были пусты, потому что переходов
ещё не было. Ни один executable holder пока не считается существующим.

Порядок: независимый acceptance → initial exposure → design revalidation и review
→ внешние hash-bound события → разрешение T1 → настоящий независимый RED → отдельное
source authorization → worker → независимый GREEN → защищённая посадка → closure.
Автор не меняет исторические доказательства либо accepted subjects соседних потоков.

На исходном срезе диагностическая грань названа отдельно: DC-01/02 — чистые decoder controls
на явно помеченных отрицательных данных; DC-03 — proposed actual-Go deadline
prerequisite. Их план не является покрытием и не разрешает counterfeit Go.

## Зафиксированные события и текущая передача

Независимый root утвердил неизменную приёмку событием
https://github.com/PRO-Robotech/kacho/issues/2672#issuecomment-5718888294
и записал первоначальную экспозицию классов событием
https://github.com/PRO-Robotech/kacho/issues/2672#issuecomment-5718888868.
Точные body/request/published/readback сохранены, recorder не присваивает себе
роль reviewer. Текущая lifecycle-фаза CLASS_EXPOSURE_RECORDED; design revision 2
остаётся DRAFT до отдельного заключительного design review и revalidation.

Root replay закрыл конструктивность DC-03; его точный review и operational evidence
связаны в change.yaml. Старый design/DC proposal сохранены как исходные subjects.
Новая ревизия изменяет только состояние этой предпосылки и её evidence binding;
acceptance, interface, 11 IDs/counters и production deadlines прежние.
Независимый executable holder, его RED и разрешение исходника ещё отсутствуют.
Общий TASKS_READY не объявлен, implementation_diff_set остаётся пустым.
