CI-NP-1 / Python projection — APPROVED_SCOPED_GREEN.

Роль: integration-tester / independent post-diff verifier. Review /root по реализации /root/e2e_audit и неизменённым тестам /root/ci_verdict_audit.

- Source commit: e8c07ed1a7fab3739fd84597e9c597ab911dcbb7.
- Test-only commit: e27d24458cba073fa6a3e0c1843b5543646f96f3.
- Worker revision2 manifest SHA-256: bbc2170608ac1ab8f90b605a4b605a76cabee12e7b5b5b805353324fdeaa985f.
- Независимый review SHA-256: 4f999d733dd072c69db836e396cdc593878db2a30df9cf77e5449b5252637b39.
- Приёмка SHA-256: 2c30dc5fb1ba6fb985b8e63918c5c4bd58a115d06bf31e35006acf737531e400; замысел SHA-256: d60f34f6a2458e011f46cbe460310ed0e5071ee0635ae0fb188a70c387bc9181.

Root прочитал все шесть source файлов и последующий узкий исправляющий diff, сверил source hashes и неизменность всех20 test/fixture файлов с test-only commit. Независимый canonical replay: rc0,10/10PASS,0FAIL/ERROR/SKIP; 198 реальных процессов,23 reader records. Проверены четыре настоящие Newman категории, проекция отчётов/журналов, сохранение читателей, Git-bound source, file/stdin roundtrip и перечисленные local refusal cases. Нереализованная scan-команда была замечена и удалена отдельным исправлением; scanner не объявлен существующим.

APPROVED относится только к ранее разрешённой Python projection части NP-T2. Полная отрицательная ZIP/check/encoding/limits матрица, historical scanner, широкие reader/verdict adapters, JS/SDK transport, consumer workflows, полный identity/all-shard runtime, скачанные результаты и retention/containment/prelanding остаются pending. Положительный CLEAN roundtrip не доказывает полный final checker. Внешняя публикация, consumer release, main delivery и closure #1810 этим событием не разрешены и не подтверждены.
