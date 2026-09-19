# CI-EBT-1 — DRAFT зависимостей и передачи работы

Текущий lifecycle ISSUE_READY; tasks не разрешают holder/source. Единственный
текущий результат — документируемый проект по #2672. Автор контракта не выдаёт
себе независимый verdict.

## T0 — независимые контракт и замысел

Acceptance-reviewer проверяет 11 ID и сохранение predicate владельца;
class-exposure-analyst делает initial по acceptance и revalidation по design;
design-reviewer проверяет механизм и его constructive prerequisites. Root
публикует точные subject/body bindings настоящих verdicts, читает события обратно.
До них пакет DRAFT. Отдельно рассматривается diagnostic-controls-proposal:
неизвестный формат и deadline не выдаются за уже покрытые 11 сценариями.

## T1 — независимый holder и RED

Зависит от принятого T0 и отдельного разрешения test-only. Автор holder отличается
от будущего source worker. Единственный новый holder-path назван в holders.yaml;
старые четыре теста не изменяются. Точная предложенная группа TestExcludingBuildTagOutcomes
выбирается вместе с прежними TestExcludingBuildTagGate и публичным tree gate.
До появления файла команда является будущим маршрутом, не текущим test evidence.

Предмет exact-set: CI-EBT-01, CI-EBT-02, CI-EBT-03, CI-EBT-04, CI-EBT-05,
CI-EBT-06, CI-EBT-07, CI-EBT-08, CI-EBT-09, CI-EBT-10, CI-EBT-11.

Сначала настоящие compiler/load и Git-fixture controls; затем публичный gate,
вычисленная дельта каждой пары, реальный executed census и отсутствие SKIP.
Главный ожидаемый baseline RED — скрытые baseline failures и tagged loader,
а не отсутствие строки нового JSON само по себе. Диагностика автора в evidence
не подменяет независимый RED. Root читает/replay frozen bytes и отдельно открывает T2.

## T2 — ограниченная реализация

Worker меняет только internal/repohygiene/excludingbuildtag_test.go в собственном
Kacho worktree. Реальные load/vet results, три исхода, полная диагностика, публичный
отказ и сохранение частичных находок реализуются вместе. Scope/interface/spec и
tests не подгоняются под implementation. Другой путь требует отдельного readback.

## T3 — независимый GREEN и проверка неизменности

На frozen candidate исполняются неизменные CI-EBT-01, CI-EBT-02, CI-EBT-03,
CI-EBT-04, CI-EBT-05, CI-EBT-06, CI-EBT-07, CI-EBT-08, CI-EBT-09, CI-EBT-10,
CI-EBT-11; старые четыре инъекции и публичный gate реального дерева.
Новые diagnostic controls учитываются отдельно ровно в принятом объёме.
Source/holder/capture hashes, argv, env, RUN/PASS/FAIL/SKIP и частичные отказы
проверяются независимо; root фиксирует фактический scoped verdict.

## T4 — посадка и снятие issue

Protected delivery, действующие проверки итогового дерева и сверка применённых
байтов предшествуют closure #2672. Существующий Make/CI маршрут сохраняется;
новый job для выполнения той же логики не нужен. До исполнения T4 локальный
GREEN не означает main delivery или закрытую задачу. END-issue #2682 не снимается
побочным изменением и не объявляется выполненной этим потоком.
