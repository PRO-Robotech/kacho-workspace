# Public Go checksum gate — finite routine proposal

PROPOSED for root and independent holder readback. Scope is the already authorized internal/release/publisher_release.go, using the existing SupplyDependencies.Command boundary. No new CLI flag, dependency field, accepted ordinal/reason, product endpoint override or live authority. Existing candidate private-proxy verification stays separate. The prior 50-case publisher holder has no signed-log prerequisite and cannot give full D4/CI-RS-13 acceptance by itself.

Before ARCHIVE_VERIFIED, after exact tag/ancestry and downloaded archive validation, invoke the actual already selected Go executable exactly as:

```
<resolved-go-executable> mod download -json <exact-module-path>@<exact-version>
```

Use a newly created owned directory containing only a minimal go.mod (`module ci-rs-public-probe.invalid/consumer`, supported minimum Go directive), no go.sum or replace, and a new empty module cache. Environment is built by the shared sanitized helper, with these explicit overrides: `GOWORK=off`, `GOENV=off`, `GOFLAGS=`, `GOTOOLCHAIN=local`, `GOPROXY=https://proxy.golang.org`, `GOSUMDB=sum.golang.org`, `GOPRIVATE=`, `GONOPROXY=`, `GONOSUMDB=`, and `GOMODCACHE=<new owned cache>`. No target cache reuse, direct fallback or off mode. The existing 600-second Go/context budget applies and is clipped by the enclosing stage deadline; there is one invocation, without producer-level retries of this command.

A successful prerequisite requires actual exit0 and one complete JSON object, exact Path and Version, no Error, nonempty valid `h1:` Sum and GoModSum, and readable regular Info/GoMod/Zip cache files beneath that owned cache. Source identities from optional Go Origin must match exact declared repository and accepted target when supplied; absence does not replace the mandatory independent exact Git target/tree binding. Never accept a JSON success object after a nonzero exit, an out-of-cache path, an empty sum, a different module/version or a partially parsed stream.

Read those actual verified files, apply the existing archive/module validation, and compare complete member bytes to the previously read public ZIP and accepted target. Recompute the downloaded ZIP Go h1 and single go.mod h1; both must equal the actual Go JSON sums and the source-derived checksum. Keep these actual files/sums and command/rc as evidence subjects. Only then can the shared proxy predicate become GREEN and stage advance to ARCHIVE_VERIFIED. This adds public authentication to the already separate exact supplied-archive consumer proof; it does not replace that build with `go mod download`.

Finite outcome mapping, without interpreting arbitrary localized stderr as a semantic oracle:

| Observation | Result before ARCHIVE_VERIFIED |
|---|---|
| Complete actual successful Go verification and exact identity/files/sum/content agreement | Continue to GREEN proxy and ARCHIVE_VERIFIED |
| Successfully obtained, parseable evidence proves wrong Path/Version/Origin, malformed declared cache coordinates, or actual verified checksum/content differs from expected exact target | RED / PUBLISHED_ARCHIVE_MISMATCH; preserve TAG_PRESENT |
| Command unavailable, nonzero exit with no independently established content mismatch, malformed/truncated/no JSON, missing cache files, signature verification failure, or service unavailable | NOT_EXECUTED / PROXY_UNAVAILABLE; preserve TAG_PRESENT |
| Process/context deadline | NOT_EXECUTED / BUDGET_EXHAUSTED; preserve TAG_PRESENT |

A Go checksum/signature refusal is never GREEN. Nonzero exit alone does not establish which source was wrong; no required RED is invented by matching a generic tool error string. Independently proven ZIP/content disagreement remains RED even if another stage is unavailable, under the existing outcome precedence.

Independent fixture extension: the test-only Command adapter may transform only the exact production proxy/checksum endpoint/trust-anchor values above to an owned local proxy and signed checksum service plus its fixture verification key. It must run actual Go and actual signature/log verification, preserve all other argv/flags, and never set GOSUMDB=off or manufacture process output. Capture original and actual argv and the fixed non-secret environment subset named above, along with exact endpoint/public-key mapping, service request/response bodies/hashes and process result. Production has no access to that mapping. No arbitrary inherited credential environment is printed.

Required prerequisite twins are a real valid signed entry/download; altered ZIP under the same module/version; invalid signature; unavailable checksum service; and timeout/cancellation. The independent holder binds expected outer classifications before author implementation, records actual Go behavior and verifies the normal production argv/environment were requested. The existing frozen cases and historical evidence remain unchanged; root selects an additive holder or narrowly reviewed successor adapter. This proposal itself is neither a test verdict nor source authorization for the public-verification addition.
