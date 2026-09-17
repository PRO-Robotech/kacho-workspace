# CI-NP-1 — маршрут поставки проверяемой публикации

Приёмка и замысел — точные SHA в change.yaml. Живое состояние задачи находится
в kacho#1810; этот документ задаёт порядок и зависимости, не второй трекер.
Историческая пустая acceptance_path не даёт разрешения пропустить новый контракт.

1. Root публикует и читает обратно четыре действительных независимых review-события:
   acceptance, class initial, class revalidation, design. Их автор анализа —
   /root/hygiene_audit, а не автор контрактов /root/e2e_audit. Новая связь пакета
   и действующая policy должны указывать на нынешний subject; старые записи сохраняются.
2. Независимый integration-tester (/root/hygiene_audit) в area-ci-newman-tests
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
