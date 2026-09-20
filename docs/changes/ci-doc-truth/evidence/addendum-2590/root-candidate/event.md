#2590 / CI-DT addendum — SCOPED_GREEN_APPROVED, local source candidate.

Source author /root/truth_tests; independent frozen comparator/test holder /root/e2e_audit; review and fresh candidate execution /root. Root прочитал полный diff, проверил 24 worker evidence hashes и самостоятельно исполнил неизменённый comparator и те же существующие notice tests.

- Author commit: c0fd76af5c475ee76ddfc5897be58dd67967cd0a; mechanical aggregate import: 431984c30e4c15b70c441e14e0438c24942aab7d; identical tree 51f275bb03f5eb2e267f1b03d3bd299768c287ae.
- Единственная правка: migratorcli/notice_test.go, дословная замена принятого абзаца [162,964), 13 added / 7 removed comment lines; whole-file SHA-256 c85a8ed9b06a0720fa4050e3537ee90892cb1aa81e84103aba63da7fe6125f96.
- Acceptance scope 0bf009e5c11cf964397bb32274e2492d8aed41fd6901918f4a8e8189587ca105; baseline record cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903; unchanged independent comparator 756bccc81889d93333ccd9a285c3e7bc14e99de93a591d66bcaa0abbedc6a655.
- Root comparator: PASS / EXACT_REPLACEMENT_PRESERVED. All 908 program tokens and 7 declarations, full position-free AST with zero whitelist, directives, prefix/suffix and six test names identical.
- Fresh exact-candidate Go execution: 6 RUN / 6 PASS / 0 FAIL / 0 SKIP; package PASS. GOWORK=off, cleared GIT_*, external TMPDIR, -mod=readonly. No code/assertion/helper edits and all other corelib aggregate paths unchanged.
- Root review SHA-256: 73b7333ab2e0aace39c5e9e1e50eb3b9df9e6e006ebbceb81113dd35645a4655. Raw comparator/list/test streams and exact command records preserved separately.

Текст теперь точно различает local NoticeRelay probes, выбранные CI интеграционные тесты с синтетической цепочкой и настоящие миграции платформы. Этот comment-only candidate не утверждает новый live Postgres/platform-migration прогон. GREEN ограничен local source/preservation и прежними шестью tests. Protected main/aggregate release delivery, final revalidation and issue closure остаются впереди; #2590 остаётся OPEN.
