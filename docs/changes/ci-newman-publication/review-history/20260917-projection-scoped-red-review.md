# Независимый ограниченный RED публикации Newman

Вердикт: APPROVED_SCOPED_TDD_RED. Reviewer `/root/hygiene_audit`; test author
`/root/ci_verdict_audit`; будущий source worker `/root/e2e_audit`.
Предмет: test-only commit e27d24458cba073fa6a3e0c1843b5543646f96f3 поверх
corelib 34bc8104a832b67e53c868646ab2b1e0ac4c8562. Manifest SHA-256
09f673c9a6dafaf8f413adfdc9ea0122e9dae301c8fc647b365828ecfdfd7fbd.

Полностью прочитаны 455 строк legacy_red.py, support.py и test_publication.py.
Проверены SHA всех 20 test/fixture файлов и всех перечисленных capture artifacts.
Три fixture reader побайтово сверены с исходниками Kachō b5fa093341f1fdbe96adfc6a9555482690968253:
exec-coverage.py, assert-suites-green.sh, newman-live.py. Настоящий predecessor
извлечён без изменений из Kaname 39628487099fe44990e9e03b09b725f3d7e37abb;
его run прочитан вместе с наблюдаемыми capture. Отсутствие новой команды
не принято за самостоятельное поведенческое RED.

Независимо повторены обе команды manifest с GOWORK=off,
PYTHONDONTWRITEBYTECODE=1, TMPDIR вне Git и удалённым GIT_* контекстом.
Собственные stdout/stderr, команды и reader records находятся рядом.
Legacy replay: 5 тестов, 5 FAIL, 0 ERROR, 0 SKIP. Каждый начинает с настоящего
lawful Newman report: cleaner rc0, реальные читатели до/после дают одинаковые
категории и счётчики. Изменён ровно проверяемый носитель/условие. Наблюдения:
произвольные response Buffer bytes, metadata key и raw log сохраняются в
публикуемом выводе; неизвестный файл пропускается с rc0; malformed JSON
отдаёт незакрытый traceback. Это недостаточность прежней границы для нового
одобренного контракта, а не утверждение о дефекте внутри его прежних обещаний.

Canonical replay: 10 родителей; prerequisite PASS для четырёх реальных
Newman сцен; 9 product parents, 21 failure, 0 ERROR/SKIP. Все эти failures
CAPABILITY_ABSENT, учтены отдельно от пяти поведенческих predecessor failures.
Holder уже требует реальную положительную проекцию и финальный check файла
и stdin, точный digest/размер, закрытые имена ZIP/выходов, сохранение трёх
читателей для green/finding/precondition/script-error, отсутствие свободных
носителей и связь source fingerprint до подстановки доверенных имён.

Разрешаемая следующая часть реализации: общий Python projector отчётов и
журналов, private Git-bound manifest/source relation, ограниченный финальный
check, необходимый этим положительным roundtrip-сценариям, и перечисленные
локальные отказы missing/malformed/dirty source/foreign commit/symlink/existing
output. Новый test_publication.py остаётся неизменным держателем GREEN;
исторический legacy_red.py не переключается на новый target. Это разрешение
части реализации после внешнего события root, не полный RED CI-NP-01..10.

Не доказаны и остаются TESTS_PENDING: отрицательная полная матрица финального
check и historical scan, все secret/encoding/capacity пределы, unanswered и
более широкий reader matrix, kacho-shard-v1 verdict projection, JS/SDK private
snapshot/upload/timeout, consumer workflow bypass census, реальный полный
own-identity/all-platform runtime и downloaded-artifact rescan, retention/body
inventory/containment/prelanding. Чистый roundtrip check не доказывает
способность final checker отклонить вредоносный ZIP. Никакой source реализации,
публикации, upload, main delivery либо closure #1810 этим review не заявлено.
