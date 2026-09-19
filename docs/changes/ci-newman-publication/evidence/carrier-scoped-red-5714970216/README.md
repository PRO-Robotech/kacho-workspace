# Carrier/capacity scoped capability RED — запись root review

Reviewer: `/root`. Holder author: `/root/newman_carrier_tests`. Recorder:
`/root/truth_tests`. Recorder перенёс и сверил свидетельства; он не выдаёт
новый независимый semantic review и не является автором этого holder.

Источник — `newman-root-carrier-red/np-03065890e6` в audit, полный абсолютный
адрес сохранён в `recording-integrity.json`. Здесь сохранены точные root review,
execution, stdout/stderr, event body/readback, шесть основных JSON и хеши всех
3077 subprocess capture records и 828 reader-trio records. Полные subprocess
stdout/stderr и reader JSON остаются по исходному адресу; канонический каталог
не объявляет их полную копию. `process-capture-hashes.jsonl` привязывает каждый
из них к байтам. Recorder повторно сверил 6154 stream-файла с execution hashes.

Поля `status` и `code` верхнего уровня в `carrier-declared.json` и
`carrier-results.json` — ОЖИДАНИЯ holder. Фактический исход лежит в `observed`:
461 `NOT_EXECUTED`, 0 semantic decisions, 461 `no_scan_dispatch`. Root признаёт
отсутствующую CLI capability воспроизведённым scoped RED; это не 461 finding
и не успешный content scan. 501 failed expectation включает ещё 40 отсутствующих
scan-вызовов limits matrix. Предварительные репетиции с негодными fixture
expectations остаются `NOT_EXECUTED` и не приписываются продукту как RED.

Принятые acceptance/design/interface/accounting subjects и holder bytes
не меняются. Root event открывает только supported scanner/decoding/capacity
CLI в corelib. Global lifecycle остаётся TASKS_READY. SDK, consumer workflows,
pins, runtime, retention, convergence, main и closure требуют следующих этапов.
