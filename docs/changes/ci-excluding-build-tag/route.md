# CI-EBT-1 — маршрут DRAFT

Дом контракта — workspace; дом gate и будущего holder — Kacho. Основание — #2672,
новый post-cutover subject, отсутствующий в historical legacy census. Scope,
interface, exact 11-ID matrix и tasks связаны hashes в change.yaml.

Текущая фаза ISSUE_READY. Автор подготовил DRAFT после операционной диагностики
main b5fa; предварительный root readback узкой архитектуры не объявляется
внешним approval. Reviews и implementation_diff_set пусты, потому что переходов
ещё нет. Ни один executable holder пока не считается существующим.

Порядок: независимый acceptance → initial exposure → design revalidation и review
→ внешние hash-bound события → разрешение T1 → настоящий независимый RED → отдельное
source authorization → worker → независимый GREEN → защищённая посадка → closure.
Автор не меняет исторические доказательства либо accepted subjects соседних потоков.

Открытая диагностическая грань названа отдельно: DC-01/02 — чистые decoder controls
на явно помеченных отрицательных данных; DC-03 — proposed actual-Go deadline
prerequisite. Их план не является покрытием и не разрешает counterfeit Go.
