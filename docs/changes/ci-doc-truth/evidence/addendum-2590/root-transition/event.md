#2590 / отдельный bounded CI-DT addendum — APPROVED_SCOPE_AND_SCOPED_TDD_RED.

Независимый scope review и test-only comparator: /root/e2e_audit, не автор абзаца. Root /root прочитал exact scope/правку и полный comparator, проверил 17 command captures и самостоятельно повторил baseline RED, lawful replacement и две отрицательные инверсии.

- Scope subject: 0bf009e5c11cf964397bb32274e2492d8aed41fd6901918f4a8e8189587ca105.
- Baseline subject: cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903.
- Corelib main baseline: 34bc8104a832b67e53c868646ab2b1e0ac4c8562; migratorcli/notice_test.go SHA-256 90a9ddd66f9d2aa0bb992010cd4101b769c433f46de7cb37e2229db0e5bb6ee8.
- Expected candidate whole-file SHA-256: c85a8ed9b06a0720fa4050e3537ee90892cb1aa81e84103aba63da7fe6125f96.
- Independent review: 1812685d84243d98f46ba640783bcf2fa71283c0db1e98766c17c621f1f753ef; holder manifest: 99f9a2ac82f2eb0fbc7595f267d6e26c7a87f56795cb5aee0c7496f27e335fd1.
- Comparator: 756bccc81889d93333ccd9a285c3e7bc14e99de93a591d66bcaa0abbedc6a655; root review: be40f2d9c9019dae11919a1abeed229ffffdf7ef7dad29f910407ea8622836ee.

Текущая шапка даёт FAIL/NOT_EXACT_REPLACEMENT при годном harness и прежних успешных assertions. Законная внешняя fixture даёт PASS: 908 program tokens, 7 declarations, весь position-free AST без whitelist и directives совпадают; все bytes вне [162,964) сохранены. Девять comparator controls различают program-token drift, посторонний комментарий/directive, старую шапку и непрочитанные/пустые/неразбираемые inputs. Existing notice tests в baseline и lawful Go-overlay: оба 6 RUN/6 PASS/0 FAIL/0 SKIP; actual integration selector 76/14 включает пакет. Live DB/platform migration proof этим не заявляется.

Разрешена worker ровно дословная замена одного header paragraph по принятому subject, без изменения программы, assertions, helpers или соседних комментариев. После отдельного source commit обязательны независимые comparator и те же шесть tests на exact candidate. Этот addendum не расширяет immutable CI-DT-01..09 и не заменяет generated-file proof. Main/release delivery и closure #2590 остаются впереди.
