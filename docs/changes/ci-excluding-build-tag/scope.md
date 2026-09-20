# CI-EBT-1 — DRAFT границ изменения

Задача: https://github.com/PRO-Robotech/kacho/issues/2672. В актуальном теле
порядок «СЕЙЧАС»; issue не переопределяет пять отдельных задач «В КОНЦЕ».

Возможный продуктовый diff после независимого RED ограничен одним существующим
файлом Kacho internal/repohygiene/excludingbuildtag_test.go. Это реализация gate,
хотя файл имеет суффикс _test.go. Его baseline, tagged и публичная свёртка — один
неразрывный предмет. Новый независимый holder имеет отдельную координату
internal/repohygiene/excludingbuildtag_outcomes_test.go. Автор holder и worker
реализации должны быть разными исполнителями.

Прежние четыре инъекции в excludingbuildtag_injection_test.go неизменны, как и
repoRoot, synthTrack, treecorpus, Go-пины, Makefile, workflows и общий collector.
Не вводится ещё один алгоритм определения тега либо ещё один источник корпуса.
Предлагаемый load-stage — проверка предпосылки существующего compiler predicate.

#2682 остаётся отдельным END-предметом: массовое принудительное GOWORK=off в
синтетических helpers в этой поставке запрещено. Здесь настоящая среда доезжает
до gate, её отказ виден и не становится успехом/ложной находкой. У нового holder
среда является явным входом однофактного опыта; это не миграция чужих helpers.

Не входят: новые комбинации тегов, включающий класс #489, runtime-стенд, общий
механизм release, compiler substitute, молчаливый пропуск, полная проверка всех
неизвестных будущих диагностик Go. Неизвестная форма — NOT_EXECUTED, а не GREEN.
До полного design approval дополнительно рассматривается предложение реальных
deadline/неизвестного-формата controls; 11 сценариев их покрытием не объявляются.

## Применимость policy

Базы: workspace 1261a1ead77412a76df8c9e295d40c0b45a66301 и Kacho
b5fa093341f1fdbe96adfc6a9555482690968253. Обе следуют своему repository-bound
cutover из docs/changes/policy.yaml; ancestry проверена настоящим Git.
В точном реестре 60 legacy coordinates нет #2672. Поэтому создаётся новый
post-cutover package, а исторические policy, census, authority и прежние subjects
не меняются. Это применимость SDD-1 §8, не добавление issue задним числом в census.

Lifecycle пакета ISSUE_READY, статус документов DRAFT. Пустые reviews/evidence
означают отсутствие разрешённых переходов. Ни авторский пакет, ни предварительный
readback не являются independent acceptance/design approval или RED_PROVEN.
