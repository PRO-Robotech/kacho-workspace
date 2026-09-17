# CI-NP-1 — маршрут поставки проверяемой публикации

Приёмка и замысел — точные SHA в change.yaml. Живое состояние задачи находится
в kacho#1810; этот документ задаёт порядок и зависимости, не второй трекер.
Историческая пустая acceptance_path не даёт разрешения пропустить новый контракт.

1. Root публикует и читает обратно четыре действительных независимых review-события:
   acceptance, class initial, class revalidation, design. Их автор анализа —
   /root/hygiene_audit, а не автор контрактов /root/e2e_audit. Новая связь пакета
   и действующая policy должны указывать на нынешний subject; старые записи сохраняются.
2. Независимый integration-tester (/root/ci_verdict_audit) в area-ci-newman-tests
   фиксирует routine CLI/result interface и фактические executable координаты holders.
   Смена семантики при этом требует новой редакции и review; имена флагов сами по себе
   её не меняют. Ни один proposed holder ещё не считается реализованным.
3. Tester строит пробы на годных настоящих Newman fixtures, доказывает lawful twins
   и честный RED отсутствующего поведения. Отказ fixture, node, pytest, SDK import
   либо несовпавший каталог не является RED реализации. Root проверяет RED и открывает
   переход; worker не меняет чужие assertions, чтобы получить GREEN.
4. Worker /root/e2e_audit реализует общий corelib инструмент в выделенной ветке
   release/ci-newman-publication-20260917. Root переносит независимые tests, выполняются
   scoped проверки и независимые post-diff reviews. До выпуска потребители не получают
   committed copy общего алгоритма.
5. Root выпускает corelib и подтверждает, что Go module archive несёт Python, JS-action
   и pinned SDK lock. Kaname обновляет pin и заменяет свой private sanitizer рабочим
   вызовом общего инструмента; его старая реализация снимается в той же поставке.
   Затем Kachō получает соответствующие corelib/Kaname pins и собственную wiring.
   Каждый single-repo proof использует GOWORK=off, без локального replace.
6. В обоих workflows каноническая JS action материализуется в свежий runtime каталог
   из того же module pin. SDK работает под runs.using=node24, runtime credentials не
   передаются обычным shell шагам и не попадают в Python checker. Проверяются все
   публикации, clean materialization, byte binding и старые пути upload.
7. Независимый tester получает полный положительный собственный identity Newman Kaname
   и все нынешние платформенные shards. Учитываются реальные reader semantics, в том
   числе newman-live, покрытие, script failure, recorded precondition и чужой отчёт.
   Stand revision, actual checkout, run/attempt, artifact ID/digest и counts связаны.
8. Root-owned private retention inventory/download становится входом общего scanner
   лишь после его готовности. DOWNLOADED_NOT_INSPECTED не означает CLEAN/FINDING.
   Historical CLEAN сохраняет объявленную carrier-границу. Удаление допускает только
   отдельный content-verified manifest, independent landing review, повторную полную
   identity/digest сверку и exact 404; runs/job logs сохраняются.
9. Перед посадкой выполняются новая metadata перепись и scan новых/изменившихся пакетов.
   Затем convergence/landing reviews, доставка root в main всех необходимых repos,
   проверка доставленного содержимого и только после этого closure evidence #1810.

Scoped predecessor: закрытый #1804 остаётся источником продуктового контракта отказа
и этой поставкой не переоткрывается. Quota, Playwright и чужие runtime-стенды вне scope.


## Текущий разрешённый переход

Четыре внешних события17сентября опубликованы root от actor pointpu и прочитаны
обратно через API; immutable node/body/subject bindings сохранены в reviews/.
Независимый policy review подтвердил exact diff перехода #1810 в migrate.
Routine interface.md SHA256
44035f95b5b85f330e3e06b75ab88922286fe9a3e4e14010ed1fef7587735800
согласован /root/e2e_audit и /root/hygiene_audit после замечаний о limits и отмене.

Разрешена только следующая фаза NP-T1: integration-tester создаёт fixtures/holders
в area-ci-newman-tests, получает и предъявляет RED. Proposed executable paths
названы в holders.yaml; executable остаётся null до фактической поставки tester.
Worker source ещё не разрешён; NP-T2 откроет root по независимому RED. Это состояние
TASKS_READY, не TESTS_RED/IMPLEMENTING и не runtime/retention GREEN.


Root передал текущую NP-T1 tester-фазу /root/ci_verdict_audit, чтобы /root/hygiene_audit
исполнял отдельно разрешённый Python producer scope. Независимый acceptance/design
review и прежнее routine agreement остаются результатами hygiene без переписывания
истории. Новый tester получил точные документы, SHA interface, настоящие Newman
fixtures/reader captures и pinned SDK probe. Автор/source worker /root/e2e_audit
остаётся отделённым от автора RED; NP-T2 по-прежнему закрыт до root transition.


## Ограниченный переход NP-T2 после независимого RED

17 сентября root опубликовал и прочитал обратно событие
https://github.com/PRO-Robotech/kacho/issues/1810#issuecomment-5713435493.
Точное тело и record находятся в reviews/landing-reviewer/. Независимый reviewer
/root/hygiene_audit подтвердил holder автора /root/ci_verdict_audit: test-only
corelib e27d24458cba073fa6a3e0c1843b5543646f96f3, исходный review сохранён
в review-history/20260917-projection-scoped-red-review.md.

Открыта только часть NP-T2: Python report/log projection, Git-bound manifest и
связь каталога, положительный file/stdin roundtrip check, перечисленные holder
отказы missing/malformed/dirty/foreign/symlink/existing-output. Executable:
`python3 -m unittest discover -s ci/newman_publication/tests -p test_publication.py`
в указанном corelib commit. Все 20 test/fixture файлов сохраняются без изменений;
исторический legacy_red.py продолжает судить прежний Kaname target.

Global TASKS_READY и исходные review bindings не меняются: частичный переход
не объявляет весь holder/scenario выполненным. Полная отрицательная ZIP/scanner/
encoding/limits матрица, более широкие reader/verdict формы, SDK/upload/workflows,
полный runtime и retention/containment/prelanding остаются TESTS_PENDING.
Worker GREEN отдельно подлежит независимому review; это не разрешение upload,
consumer release, main delivery или закрытия #1810.


## Carrier/capacity: typed-result clarification и scoped RED

Событие root от 17 сентября 5714676827 уточнило единицу typed-result accounting
перед замораживанием holder. Точный subject и readback сохранены в
`conventions/decoding-typed-result-0f5c81dd85a2ada556e3d599db160e85befe28903c74646795cce89c0e49a50a.json`
и `reviews/system-design-reviewer/decoding-typed-result-5714676827.yaml`.
Прежний accounting subject, acceptance/design/interface и потолки неизменны;
само уточнение не открывало scanner implementation.

Следующее событие root 5714970216 открыло только supported scanner/decoding/
capacity CLI в corelib `ci/newman_publication`. Его основание — независимый
root review неизменённого holder `/root/newman_carrier_tests`, test-only commit
3aa95633b5f635847997ce55f590c63d5dfce68e на source
4d37cfb6ef62d31c09cd65daadf09bdef671d3a5. Record:
`reviews/landing-reviewer/carrier-scoped-red-5714970216.yaml`.

Root исполнил 412 prerequisites и 828 reader trios; 461 scan attempt вернул
ноль semantic decisions вследствие отсутствующего dispatch. Это capability
RED; фактические ответы NOT_EXECUTED не превращаются в FINDING или CLEAN.
Limits matrix: 120 вызовов, project 40 PASS, check 40 PASS, scan 40 отсутствует.
Предварительные репетиции с негодными fixtures остаются NOT_EXECUTED.

Автор реализации `/root/e2e_audit` сохраняет frozen holders, accepted limits,
generic credential semantics и прежние projection/checker obligations.
Recorder `/root/truth_tests` лишь перенёс root review и сверил evidence hashes.
Global lifecycle остаётся TASKS_READY; SDK, consumer workflows/pins, runtime,
retention, convergence, main delivery и closure не разрешаются этим RED.
