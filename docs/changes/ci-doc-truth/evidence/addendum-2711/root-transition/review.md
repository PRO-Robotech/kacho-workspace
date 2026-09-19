# Independent review of bounded issue #2711 addendum

Verdict: ACCEPTED FOR EXACT SOURCE CHANGE.

Subject: docs/changes/ci-doc-truth/addenda/issue-2711-scope.md
SHA256: c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100
Author: /root/docs_truth. Independent reviewer: /root.

The issue remains OPEN and has no newer owner comment at this review. Its body hash is 3a7e98ec0617268dd671a22f2a86c9fcaac98f44802432c8ff163d808f7d4099.

Read the entire addendum, exact current fixture and expectation declaration. The fixture asserts that a removed mandatory option remains in use, while the actual expectation contains no such field and the preserved #1255 explanation records the family removal. This is a current false comment. The prior #1439 closure concerned a different header and remains valid. Historical explanations are outside this delta.

CI-DT-A1-01: accepted exact deletion of the two quoted tab-indented lines only. Frozen base 88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0; file SHA ab38d70525b8d9279c63c711e373a312bfe315fc86e498ef5eeea4c2f5dbd959. Expected candidate file SHA ca976ed9e0be54f6273182d6f58de64e2d8fa8c176c27cefd893b104434e6e41. All other bytes must be equal.

CI-DT-A1-02: independently read all strictpreservation.go and built a separate root copy. Source SHA 7d849a4882496c3fe8620c2a5ea76abee4907c01a0934deb9ab7b9585aab81b9. Strict token/AST comparison has zero string exceptions and retains directives. Root birth controls passed: lawful deletion accepted; a changed program token, extra comment, unchanged source, empty/declaration-free input all refused for their intended reasons. Missing and unread Git inputs returned 2. It reads the baseline by exact Git SHA and additionally checks its full file digest. 482 program tokens and six declarations were actually parsed.

CI-DT-A1-03: independent tester baseline has 15 listed top-level tests, 55 RUN/55 PASS/0 FAIL/0 SKIP at exact 88deb14. Names digest dcf5efe53f313e63b994c5b929904873a9682b28a2f892a935d523ae2650025e. Root's broader exact-source run separately confirmed all 75 tests. The existing diagnostic holder SHA 9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35 remains immutable. Candidate must repeat the existing selection after source change.

This review authorizes only removal of the two lines in internal/repohygiene/subscriptionformshape_test.go. It does not expand the original CI-DT four-Go-file verifier, alter the accepted CI-DT subjects, introduce a prose truth gate, or claim candidate/main GREEN. Independent post-diff, full preservation, convergence and main delivery remain required.
