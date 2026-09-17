# Independent comparator and baseline for DRAFT #2711

Status: comparator born and baseline proven; no #2711 source edit was made or authorized by this tester. Root must record the separate transition before the author changes the source.

DRAFT document commit: `e3c0c7e18ad3b577b1d3cb8840b1e45277f125ef`.
Document: `docs/changes/ci-doc-truth/addenda/issue-2711-scope.md`.
Document SHA-256: `c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100`.
Frozen source baseline: `88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0`.
Only admitted source path: `internal/repohygiene/subscriptionformshape_test.go`.
Baseline file SHA-256: `ab38d70525b8d9279c63c711e373a312bfe315fc86e498ef5eeea4c2f5dbd959`.

The external one-off comparator `strictpreservation.go` is SHA-256 `7d849a4882496c3fe8620c2a5ea76abee4907c01a0934deb9ab7b9585aab81b9`. It is not installed as a product gate. Its addendum mode reads the fixed baseline commit through Git, verifies the fixed baseline content hash and exactly one occurrence of these two literal lines including two leading tabs and newline endings:

```go
		// Обязательность в этом дереве выражается ОПЦИЕЙ поля, а не ключевым
		// словом: `required` из proto3 убрано, а опция жива и употребляется.
```

The only successful candidate is the complete baseline byte sequence minus those two lines. Both inputs must be readable, nonempty, parseable Go with declarations. All 482 program tokens and the full position-free AST must match with zero whitelist; directives are compared as well. Expected exact candidate file SHA-256: `ca976ed9e0be54f6273182d6f58de64e2d8fa8c176c27cefd893b104434e6e41`. This expected digest was obtained from an in-memory lawful control, not from editing product source.

Birth passed the lawful two-comment deletion and rejected a single renamed function identifier, an extra unrelated comment, unchanged baseline source, empty source and a package-only file with no declarations. External process controls returned exit 2 for missing arguments and unreadable candidate revision. Raw commands/outcomes are in `addendum-birth.*`, `addendum-no-input.*` and `addendum-unread-input.*`. Failure and missing evidence are not accepted as success.

Build and future candidate comparison, from the reviewer's isolated Kacho tree with inherited Git variables removed and `GOWORK=off`:

```text
go build -o /var/tmp/area-ci-truth-tests/strictpreservation /var/tmp/area-ci-truth-tests/strictpreservation.go
/var/tmp/area-ci-truth-tests/strictpreservation -mode addendum -repo . -candidate <exact-author-commit>
```

The candidate comparison checks the target file's exact bytes. The reviewer must separately confirm the whole commit's changed-path set is exactly this one path; the tool is not a general repository scope oracle.

The unchanged baseline ran these existing commands with `GOWORK=off`, `TMPDIR=/var/tmp/area-ci-truth-tests` and child `GIT_*` removed:

```text
go test ./internal/repohygiene -list '^Test(SubscriptionFormShape|SubscriptionShape)' -count=1
go test ./internal/repohygiene -run '^Test(SubscriptionFormShape|SubscriptionShape)' -count=1 -json -timeout=5m
```

Both returned exit 0. The list contains 15 top-level tests. The JSON stream contains 55 unique RUN names and the same 55 PASS names, zero FAIL and SKIP; listed top-level names equal executed top-level names. The sorted full name set is saved in `addendum-baseline-names.txt`, SHA-256 `dcf5efe53f313e63b994c5b929904873a9682b28a2f892a935d523ae2650025e`. After the authorized edit, compare the exact RUN/PASS names and repeat the immutable-holder check; mere exit 0 or an empty selection is insufficient.

The baseline includes `TestSubscriptionShapeReasonContract`; its file remains SHA-256 `9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35`. Baseline stdout SHA-256 is `e88763b557459c2a9d37f740fb41874c70b8a2922db47b2ad4c048f0a86be6c3`; list stdout SHA-256 is `1fc206b943008fd018474c41ef3411115c7784884320e9ca79fc42c17950d95d`. Both stderr files are empty. The `.json` records preserve commands, exact revision, environment choices and elapsed times.

The comparator does not inspect arbitrary canonical prose for truth and does not add a permanent gate. This handoff is limited to the exact two-line deletion and preservation checks. Canonical record/archive work is pending coordination with root.
