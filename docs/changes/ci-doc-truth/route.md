# CI-DT-1 — предлагаемый маршрут

> DRAFT, 2026-09-17. Маршрут предложен автором, TASKS_READY не объявлен.
> Живое состояние принадлежит issues #2696/#2591/#2592.

1. Acceptance-reviewer проверяет exact acceptance SHA и новый scope двух Reason.
2. Class-exposure-analyst выпускает initial на принятую приёмку и отдельную
   revalidation на design SHA; design-reviewer принимает замысел. Root передаёт
   принятый замысел planning-роли: она фиксирует tasks.md с exact-set сценариев
   CI-DT-01..09. Само наличие этого предложенного маршрута approval не заменяет.
3. Независимый integration-tester подтверждает нынешние ложные утверждения
   первичными свидетельствами и создаёт только узкий diagnostic holder.
   Его exact-text RED связан с рабочим positive twin; source до этого не меняется.
4. После отдельного root authorization исполнитель меняет четыре текущих Go
   файла по D1–D3 и canonical proto comment по D5. Test-only commit приходит от независимого владельца проб.
   Предел двух Reason и существующие assertions не расширяются по дороге.
5. Независимый verifier повторяет semantic comparison, token/AST preservation,
   diagnostic holder и непустую существующую selection; имена и counts сохраняет
   вместе с stdout/stderr, command, SHA и digest инструмента. Пустой охват,
   отказ окружения или непрочитанная сторона не открывают GREEN.
6. Для D5 verifier повторяет staged генерацию приёмом emitStubs: четыре output,
   точный generated diff, равные tokens/AST/raw descriptor. Go и proto reviewers
   проверяют оба repository content. Root интегрирует generated файл в corelib
   и выпускает версию; допустим общий релиз с CI-NP-1, но отдельное evidence.
   Kachō обновляет module pin; independently verified archive и повтор
   selection при GOWORK=off доказывают потребление этой версии.
7. Semantic review границ и истории, convergence на exact
   content, затем root landing и проверка main. Только root публикует итог и
   закрывает каждый issue по его собственному предикату.

Код продукта, proto и политика в авторской стадии не меняются.
Ни один из трёх issues не входит в legacy registry; cutover предок обеих баз.
Поэтому route нового package не требует `policy migrate`. Связь с закрытым
#1439 не превращает новые диагностические строки в его старый approved scope.

## Первичное чтение и открытая граница

Свежие GitHub bodies/comments прочитаны 2026-09-17: три OPEN, комментариев нет.
Digest каждого body, базы и policy закреплены в change.yaml. Повторный reviewer
получает текущие bodies/comments сам; позднее owner-решение сильнее этого среза.

Авторские измерения и read-progress лежат в локальном audit `docs-truth-author`;
это рабочие свидетельства, не долговечные review coordinates. Review/evidence
records появятся отдельно с проверенными внешними событиями; пустые записи
или вымышленные approvals не создаются. Родственное текущее proto-пояснение
включено решением root в D5. Это тот же invariant: форма не гарантирует
заполненность экземпляра. Runtime контракт не меняется. Полный старый exporter
на нынешней базе не собирает дерево; проверенный способ узкой регенерации и
его baseline описаны в design. Отказ exporter не маскируется фиктивным успехом.
