CI-DT-1 — SCOPED_RED_APPROVED / independent root review.

Acceptance SHA-256: 0d9a2074718bc1de5826696f64bf43af1a98182f91c2866d51e1d93d42986b24.
Design SHA-256: f77397339a15cd51c09ab59df2e8e4b5072e7549c2242eeae6586fccde1d2047.
Test-only: 0eae6a3569f062bcdf0c1184c1750b95eea5beb7; holder SHA-256: 9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35.
Root review SHA-256: 50ee795ffe30f0959978fe3ab3859937fb79debb20d1c6f39b0d34ff051ce0a3.

Независимый повтор root: 75 RUN / 72 PASS / 3 FAIL / 0 SKIP. Все прежние 71 проверки и новый законный близнец PASS. Только две принятые диагностические строки дают RED; Kind и координаты сохранены. 20 hashes исходных потоков tester сверены. Root не автор holder; это агентный review по автономной директиве, не новое решение владельца.

Разрешён переход к implementation строго принятого CI-DT-1: четыре Go файла, canonical proto и штатная generated проекция; source predicates/history/holder не меняются. Соседний dangling comment за пределами exact-set требует отдельного addendum.

GREEN, проверка токенов/AST/descriptor, реальный release/archive/pin, независимые post-diff review/convergence и main delivery остаются обязательными. Закрытие #2696/#2591/#2592 этим событием не разрешается.
