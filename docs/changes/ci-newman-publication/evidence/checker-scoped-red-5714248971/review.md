# CI-NP-1 — независимый scoped RED final ZIP boundary

Reviewer /root, tester /root/ci_verdict_audit, future source worker /root/e2e_audit. Source e8c07ed1a7fab3739fd84597e9c597ab911dcbb7; holder 08d5d91cd431a34159af5d7d556764c4ecc52372. Root прочитал все 196 строк независимого holder и underlying fixtures/invocation path, проверил 314 artifact SHA и 6 source SHA. Тестовые изменения механически перенесены в source tree commit f9b8fba49387d3bdcc4f30d479b5ae63620c163d, исходные байты сохранены.

Свежий независимый запуск в отдельном внешнем каталоге повторил 8 parents: 5 PASS / 3 FAIL, 24 negative variants: 8 unsafe CLEAN / 16 correct refusals, 0 ERROR/SKIP. Три failed parents имеют 8 subtest failures. Перед каждой группой реальная проекция/проверка создаёт законный twin; всего 24 positive project/file-check/stdin-check calls. Ни missing interface, ни неготовая fixture не используются вместо semantic RED. Оба набора сохраняют actual ZIP bytes, command/rc/closed result и hashes.

Разрешён минимальный source scope: полная проверка envelope/неперекрывающегося покрытия байтов конечного ZIP, согласованность local/central metadata и регулярность производимых members. Исправляется наблюдённый класс неполноты, без ручного перечисления только известных примеров. Сохраняются весь raw byte digest, closed refusals, доверенная привязка каталога, положительные читатели и прежние 10 projection tests. Новый holder с 8 tests и прежние 10 должны полностью пройти; assertions не правит source worker.

Manifest SHA 949a5e01a84c4fea650e767c7f06998a6634ee7894eec33476573144457ff34a. Старый scoped manifest 576b3f уже правильно различал 20 negative, 4 unsafe, 16 refusals, 21 positive CLI; промежуточное словесное число 17 refusals было ошибкой сводки. Исторический replay сохранён отдельно.

Это APPROVED_SCOPED_TDD_RED для указанного checker hardening, не полный security GREEN. Carrier scanner, прочая capacity/encoding matrix, adapters/SDK/workflows/runtime/retention и main delivery остаются отдельными обязательными этапами.
