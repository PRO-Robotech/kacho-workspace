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


## Заключительный design review и post-design handoff

Прежний раздел фиксирует состояние e721 до заключительных событий; его payload
сохранён. Root записал revalidation точного design revision 2 событием
https://github.com/PRO-Robotech/kacho/issues/2672#issuecomment-5719256456
и утвердил тот же предмет событием
https://github.com/PRO-Robotech/kacho/issues/2672#issuecomment-5719256839.
Независимый review, точные body/request/published/readback и их bindings лежат в
evidence/design-final-root; reviewer — root, здесь выполнена только запись.

Текущая lifecycle-фаза DESIGN_APPROVED. Автор применил writing-plans после
опубликованного approval: tasks.md теперь задаёт exact-set, реальные команды,
роли, файлы, предпосылки и переход RED → source → независимый GREEN → main.
Старый tasks SHA 5c74583815877a5f7664d27a4ce1060ae1c996144f09daf720ff2b7b7c96faea
сохранён побайтно в history/tasks-e7214a79.txt. Accepted subjects, матрица и
история operational попыток не менялись.

Передача нового tasks зафиксирована как SUBMITTED_PENDING_ROOT_READBACK,
не как independent approval. До проверки root точного плана нет TASKS_READY,
разрешения T1, source или product GREEN. Machine holder по-прежнему отсутствует;
implementation_diff_set пуст. Непроверенные DC-ветви не становятся покрытыми
после одного 11-case прогона. Полный deadline и child cleanup проверяются
будущим holder на реальном Go и через публичный gate.
