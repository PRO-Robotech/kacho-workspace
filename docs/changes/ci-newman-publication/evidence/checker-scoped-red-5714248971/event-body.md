CI-NP-1 — APPROVED_SCOPED_TDD_RED: полнота проверки конечного ZIP.

Source: e8c07ed1a7fab3739fd84597e9c597ab911dcbb7. Independent test commit: 08d5d91cd431a34159af5d7d556764c4ecc52372. Manifest SHA-256: 949a5e01a84c4fea650e767c7f06998a6634ee7894eec33476573144457ff34a. Независимый review /root SHA-256: 187909c76bef168972575045a4739b0759f44dc7393bdf400bc1f72281ff4a6d.

Root прочитал holder, проверил 314 artifact SHA и 6 source SHA, затем независимо повторил исполняемую матрицу: 8 parent tests, 24 отрицательных варианта, 8 ошибочных CLEAN и 16 корректных отказов, 0 ERROR/SKIP. Законные project/file-check/stdin-check controls проходят. Это наблюдённая неполнота существующего checker, не отказ из-за отсутствующего CLI.

Разрешена минимальная реализация полноты byte coverage конечного ZIP и согласованности metadata регулярных members. Общий класс исправляется с сохранением catalogue binding, digest полных байтов, закрытой диагностики и всех независимых assertions. До GREEN обязательны прежние 10 projection tests и 8 новых boundary tests; source worker не меняет holders.

Acceptance/design не меняются. Carrier scanner, полная capacity/encoding matrix, SDK/upload, consumer workflows, runtime/retention, main delivery и closure остаются на последующих этапах. Это агентный независимый review по действующей директиве, не новое решение владельца от его имени.
