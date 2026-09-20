CI-PY-1 / producer и self-test — APPROVED_SCOPED_TDD_RED.

Роль: landing-reviewer. Независимый review выполнен /root/e2e_audit по тестам /root/ci_verdict_audit; оркестратор публикует фактически полученный вердикт. Разрешён переход к реализации CI-PY-01..08 и решений D1–D3.

- База испытуемого: b5fa093341f1fdbe96adfc6a9555482690968253.
- Test-only commit: 8cc171365e676f07005bfdde9b97d85d0eaa2452; только два файла holder/driver, исходник испытуемого сохранён.
- Manifest SHA-256: d41b0152a6421514b35fc6fe26da44f4fb629427f5d37d3e8ccc22fc5e3619fd.
- Независимый review SHA-256: 677ec11ed0238bbfecd95e4e539d502a61093632b38d5d2c1ce0073d1375f1ac.
- Приёмка SHA-256: 427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e.
- Замысел SHA-256: 26ab94480f7c8c1fdb263d62dd8b060d5b4f9d698bc8ddd39f46c6f78424604d.

Независимый повтор исполнил 17 реальных вызовов producer/self-test, восемь scenario subtests и родителя; Go rc1, SKIP0. Законные близнецы дают rc0, настоящая подмена утверждения — rc1. Воспроизведены неверный rc1 самопроверки без pytest; rc1 и неклассифицированный traceback при потере/повреждении настоящего отчёта JUnit; потеря реальной находки рядом с отсутствующим pytest; историческое число 48 вместо переписи двух объявлений. Отказ на новом CLI и отсутствие нового JSON сами по себе основанием RED не служат.

Область исполнителя: run-python-probes.py и минимальные общий stdlib schema/writer, необходимые для результата этого producer. Worker сохраняет чужие holder assertions. D4–D7 — reader, общий selftest-runner, Make, ci-local, CI и callers — остаются TESTS_PENDING и ждут отдельного доказанного RED. Эта запись разрешает только указанную часть реализации; полного GREEN, посадки и закрытия трёх задач она не подтверждает.
