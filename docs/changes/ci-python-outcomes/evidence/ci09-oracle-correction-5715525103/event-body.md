CI-PY-1 / CI-PY09 — APPROVED_BOUNDED_TEST_ONLY_CORRECTION.

Оркестратор /root разрешает отдельному tester только замену ошибочного uppercase-substring oracle в tools/pythonprobes/testdata/outcomes_driver.py. Независимое рассмотрение: /root/truth_tests; это агентный review, не заявление о личном review владельца.

- Source candidate: a7f7203a9b4188ed721d6ed835c8f4fda9ec61de.
- Прежний holder SHA-256: f637a3d7561014946cefc866aeda96964da574139e8ced6baac5a87c0ae14a8a.
- Точный 20-строчный replacement SHA-256: 205ffdf1d836282d9d2806a8ee726f82ee494bca57236cddcf390daa396acbe4.
- Независимый report SHA-256: 6d8defa8a1aec9f50c9a2f7edf53a6383320d674f941fea7be102f020f546640.
- Manifest 58 файлов SHA-256: c64dac63d5b07b1cbe4f505b4b9fbc74c20267307545109fcecef5c1df2021eb.
- Root review SHA-256: 1524fee08c59bc42839f12dbb685f1627beb9acdbf42b56c1c62d6e32fd26ea3.
- Acceptance: 427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e; design: 26ab94480f7c8c1fdb263d62dd8b060d5b4f9d698bc8ddd39f46c6f78424604d.

Завершённый обязательный root run остаётся RED: Make rc2, 16 RUN / 14 PASS / 2 FAIL / 0 SKIP, 2854.847 s. Провалены CI-PY09 и его parent. Настоящий Python selftest defect сохранил rc1, declared/executed 5/5, failed1, unmet0, человеческую сводку и конкретные parent/leaf finding coordinates. Acceptance требует сохранённый отказ, но не uppercase текст, который ищет прежнее assertion.

Проверенный replacement требует текущий invocation, typed finding, все счётчики и сводку, отсутствие unmet, точную координату Python runner и исходный Python selftest finding. Два независимых прогона oracle по сохранённым наблюдениям дали 39/39 controls, включая 25 отрицательных инверсий; lawful, missing-pytest, соседняя находка и поздний Make refusal не подменяют искомый Python defect. Это проверка oracle, не новый запуск продукта.

Разрешена только точная замена указанной строки на reviewed block. Исходники, fault fixture, helpers, остальные scenarios и принятые контракты сохраняются. После отдельного test-only commit требуется новый полный mandatory run трёх parents/13 scenarios и фактический final CI verdict с полным и отсутствующим результатом. Старый RED не переклассифицируется. GREEN, main delivery и закрытие #2281/#2629/#2705 этой записью не заявляются.
