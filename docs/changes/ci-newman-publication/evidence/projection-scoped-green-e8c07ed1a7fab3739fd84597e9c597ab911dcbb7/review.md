# Независимый scoped GREEN проекции Newman

Вердикт: APPROVED_SCOPED_GREEN только разрешённого Python NP-T2 projection.
Reviewer /root, worker /root/e2e_audit, independent tests /root/ci_verdict_audit.
Source e8c07ed1a7fab3739fd84597e9c597ab911dcbb7, test-only e27d24458cba073fa6a3e0c1843b5543646f96f3.
Worker revision2 manifest bbc2170608ac1ab8f90b605a4b605a76cabee12e7b5b5b805353324fdeaa985f.

Root целиком прочитал все шесть Python source файлов первоначальной ревизии
(604 строки) и затем полностью diff revision2. Первоначальная registration
нереализованного scan отклонена как заглушка вне scope; e8c07ed удалил регистрацию
и ветку. Исторический scanner не объявлен реализованным. Старый worker manifest
и его captures сохранены, новым proof не переименованы.

Проверены hashes всех шести source файлов и всех20 независимых test/fixture
файлов; последние дополнительно побайтово сверены с test-only e27d244.
Root самостоятельно исполнил canonical unittest discover в source tree с
GOWORK=off, внешним TMPDIR, очищенными GIT_* и PYTHONDONTWRITEBYTECODE=1.
Получено rc0,10tests/10PASS/0FAIL/0ERROR/0SKIP за6.666s, 198 фактических
subprocess captures и 23 reader records в собственной папке reviewer.
Проверены реальные green/finding/precondition/script-error reader outcomes,
безопасная проекция свободных носителей, generated ZIP names и file/stdin
roundtrip, Git-bound source, missing/malformed/dirty/foreign/symlink/existing
output refusals. Исходный отрицательный legacy holder сохраняет старый target.

Вывод ограничен доказанным scope. Отрицательная полная ZIP/check/encoding/limits
матрица, historical scan, динамические guard names/широкие reader/verdict формы,
JS/SDK snapshot/upload, consumer workflow wiring, реальные full identity/platform
runs, downloaded rescans и retention/containment/prelanding остаются pending.
Даже CLEAN положительного roundtrip не доказывает способность checker отвергнуть
каждый недопустимый ZIP. Нет разрешения внешней публикации, consumer release,
main delivery либо closure #1810. Никакой product/test source reviewer не менял.
