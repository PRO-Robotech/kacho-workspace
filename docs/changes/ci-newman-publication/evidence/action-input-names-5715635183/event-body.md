CI-NP-1 / JavaScript action — routine naming agreement перед зависимыми NP-T1 tests.

Согласовано tester /root/release_supply_arch, source worker /root/e2e_audit и оркестратором /root. Приёмка 2c30dc5fb1ba6fb985b8e63918c5c4bd58a115d06bf31e35006acf737531e400, design d60f34f6a2458e011f46cbe460310ed0e5071ee0635ae0fb188a70c387bc9181 и interface 44035f95b5b85f330e3e06b75ab88922286fe9a3e4e14010ed1fef7587735800 не изменены. Routine record SHA-256: 04b04c1c2a259bb48f92f5d1b797a935d6c942843dffac319c0bd89d261af7de.

Имена inputs: archive-path, manifest-path, run-id, run-attempt, shard-index, max-archive-bytes, checker-timeout-ms. Используется стандартная INPUT_<UPPERCASE NAME> среда JavaScript action; дефисы имени сохраняются. Числа проверяются как полные integer strings с ранее принятыми диапазонами; optional budgets только уменьшают прежние потолки. Path values остаются приватными координатами.

Фиксированный action/main.mjs под runs.using: node24 печатает один закрытый publishSnapshot JSON; exits PUBLISHED=0, FINDING=1, NOT_EXECUTED=3. Canonical Python checker и pinned SDK задаются реализацией; workflow/env не выбирают команду, checker или transport. Обязательства snapshot bytes, abort с завершением child, очищенной среды checker и приватных SDK diagnostics сохраняются.

Это конкретизация имён для независимых test-only holders NP-T1. Наличие action, RED/GREEN, разрешение source implementation, consumer wiring, release/runtime и закрытие #1810 не заявляются. Для NP-T2 JS по-прежнему нужны самостоятельный prerequisite-valid RED и отдельный root transition.
