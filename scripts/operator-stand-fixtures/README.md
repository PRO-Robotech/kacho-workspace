# Producer captures

- iam-job.json: GitHub API job120041741421, run39834315878 attempt2, source26ee9709d57ca9ba00ac523695b6b927a3e59db3, captured2026-10-22.
- iam-go.log: actual Go verbose census from that completed job's Integration probe, before the workflow repeats its tail. Five top-level cases, all executed.
- vault-ginkgo.log: raw GitHub API job120006092379 log Ginkgo-v2 census from Vault run39830801736 (5/5, no skipped/pending/failed), captured2026-10-22.

These historical captures do not contain source boundary markers and cannot independently authorize final operator readiness. Negative parser experiments mutate one captured fact; source-marker tests must execute the actual producer before claiming a positive producer twin.

cluster-api-shape.json retains only metadata identity, userns and container shape from Registry ca56; command prep and status are redacted. operator-cluster-inject.py explicitly constructs synthetic successful status/logs, never product acceptance.

registry-build-steps.json: actual GitHub API steps from Registry pushrun39788099939, images job119859531581 @ba30eb0e, including both identically named build steps and distinct Post steps. Source producer markers were not present; this is a step-reader fixture only.

`vault-pipeline-native.log` и `vault-load-native.log` содержат только фактические строки RUN/PASS и измерения нагрузки исторического внешнего прогона `97d2d711`, сохранённого в `vo28-97d2d711-pipeline-load-docker.log`. Это фикстуры парсера, а не доказательства приёмки текущей ревизии оператора. Pipeline содержит восемь верхнеуровневых тестов и шесть ownership-подтестов; load — фактическое измерение 1000 заказов за десять минут.
