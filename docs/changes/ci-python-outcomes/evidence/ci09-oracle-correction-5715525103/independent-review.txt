# CI-PY09 independent contract adjudication

Verdict: **HOLDER_ORACLE_DEFECT_CONFIRMED** for the uppercase substring assertion at `tools/pythonprobes/testdata/outcomes_driver.py:608` in source candidate `a7f7203a9b4188ed721d6ed835c8f4fda9ec61de`. The captured real Python selftest defect preserved its refusal and provenance through the actual caller. This finding does not approve the full implementation or change the completed mandatory root run from RED.

Reviewer: `/root/truth_tests`. I did not author this holder or product implementation. I read the accepted CI-PY09/10/11 contract, design D2–D7, transport interface, relevant source producer/aggregation/caller code, frozen holder fixture and assertion, and seven completed root captures. The actual SUT executions belong to root. My independent work is contract adjudication and an executable oracle experiment over copied captures and in-memory single-fact controls; it is not another SUT execution.

## Exact subjects

- Source candidate: `a7f7203a9b4188ed721d6ed835c8f4fda9ec61de`; driver SHA-256 `f637a3d7561014946cefc866aeda96964da574139e8ced6baac5a87c0ae14a8a`.
- Contract snapshot: docs commit `b2b10f136e5c39283e96430c7a212864945da542`.
- Acceptance: `427493262f75bcef467f1864c6327abde34661f03d4748029f26269ae95f658e`.
- Design: `26ab94480f7c8c1fdb263d62dd8b060d5b4f9d698bc8ddd39f46c6f78424604d`.
- Transport interface: `6e98466a99871bc2515b969d7607630d2a4cc30fcad2bd64b87e2c8d51deded1`.
- Proposed replacement: `proposed-replacement.py.txt`, SHA-256 `205ffdf1d836282d9d2806a8ee726f82ee494bca57236cddcf390daa396acbe4`. This is an evidence text file outside all product worktrees. It replaces only the existing `c9.capture(bad); c9.check(...)` line, reusing the existing frozen holder helpers.

The historical DRAFT language in the spec is accompanied by accepted review bindings in the copied `change.yaml`; I checked subject bytes against those bindings rather than treating that historical heading as the current lifecycle.

## Why this is an oracle defect

Acceptance CI-PY09 lines 114–124 requires named unmet when pytest is unavailable and preservation of a genuine selftest refusal when pytest is available. It does not specify uppercase `САМОПРОВЕРКА ПРОВАЛЕНА` or `ПРОВАЛ`. CI-PY10 separately requires the actual full helm route to distinguish five successful checks, four executed plus one unmet, and a genuine defect. Design D4 and the transport interface make current invocation identity, category, typed counters and producer reasons the cross-Make evidence.

In immutable root capture `007-full-helm-genuine-finding`, rc is 1 and the human summary says five executed, one refusal, zero unmet; declared count is five. The current invocation's structured record says `producer=ci-local`, `unit=local-check`, `category=finding`, declarations/executed 5/5, failed 1, skipped/unmet 0/0. Findings retain `gate-self-test/check-failed` at `.github/scripts/run-python-probes.py` and underlying `run-python-probes/self-test/self-test-failed` findings with concrete nonempty coordinates. No unmet reasons are present.

The printed tail contains `!!! самопроверки провалены: .github/scripts/run-python-probes.py`. The caller deliberately prints a log tail (`scripts/ci-local.sh` keeps the full log separately); an uppercase leaf assertion can be outside that tail. The frozen assertion nevertheless only accepts two uppercase fragments. Its rejection is caused by presentation wording, while the actual refusal and source coordinate survive. No source edit is needed for this discrepancy.

The fault fixture is a real one-assert inversion of `_OK_PROBE` from `assert 1 == 1` to `assert 1 == 2`, checked as a unique replacement and restored after the real full helm execution. This review did not synthesize that SUT outcome.

## Exact bounded correction proposal

Replace the uppercase check with the attached 20-line assertion block. It keeps the same genuine-defect fixture and capture and uses `Case.record` to require the current invocation, schema, producer, category, units and all required nonnegative integer counters. It additionally requires rc1, declared/executed 5/5, failed1, skipped0, unmet0, matching human summary, empty unmet reasons, well-formed nonempty finding fields, the exact Python runner parent coordinate, and a concrete Python selftest leaf finding. It does not freeze the number of failing internal self-assertions, their prose labels, or capitalization. Existing absent-pytest, full-helm, transport and caller scenarios remain unchanged.

`oracle_probe.py` is an independently written semantic checker. `exact_proposal_probe.py` extracts only the frozen holder's pure `Case`, `local_summary`, and `local_declarations` definitions through AST, executes the exact proposed assertion text, and submits it to the same control matrix. Neither invokes the product. Both completed successfully: **39 controls / 39 expected outcomes**, including **25 rejecting negative mutations**.

The real lawful capture 003 passes its complete-green predicate; 004 and 005 pass their distinct gate-self-test unmet predicate. The proposed genuine-Python-refusal assertion rejects those records and also rejects actual 006 (local pytest absent), actual 008 (a different selftest finding alongside pytest absent), and actual 022 (later Make failure after the successful prerequisite). This last control prevents a generic nonzero caller exit from replacing evidence of the intended Python defect.

Two cosmetic copies of actual 007 change only the summary marker's wording/capitalization and remain accepted. Negative mutations remove or corrupt current identity, schema/type, producer, unit, category, exit code, findings, parent/leaf provenance, coordinates/messages, counts, unmet reasons, or the independently read human counts; all are rejected. These are oracle controls over saved observations, not new product RED/GREEN runs.

## Root fullrun and preservation

The root-owned mandatory `make test-python-outcomes-integration` run finished with Make rc2 after 2854.847 seconds, 16 RUN / 14 PASS / 2 FAIL / 0 SKIP. The failed entries are CI-PY09 and its `TestPythonOutcomesChain` parent. CI-PY01–08 and CI-PY10–13 passed. This remains the complete run's RED outcome. I copied and verified its final stream hashes and result; I did not execute or alter that run.

All eleven live source/holder hashes match root's start and end hashes. Seven capture execution records agree with their raw stdout/stderr, outcome JSON and invocation IDs. Source, holders, author contracts and root evidence were not edited. Only this independent evidence directory was created.

The next permitted action is a separately authorized bounded test-only holder correction, followed by a fresh full mandatory root run. This report does not itself grant that transition, and capture-level adjudication does not replace that run.
