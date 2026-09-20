# CI-DT-1 — независимый test-only RED

Tester: /root/truth_tests. Kachō base b5fa093341f1fdbe96adfc6a9555482690968253.
Test-only commit 0eae6a3569f062bcdf0c1184c1750b95eea5beb7 добавляет только
internal/repohygiene/subscriptionreason_test.go, SHA-256
9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35.

Собственный baseline: 30 top-level, 71 RUN = 71 PASS, 0 FAIL/SKIP.
-list без -count=1 был честно отвергнут TestMain; повтор с -count=1 дал список.
Отказ первого запуска не засчитан RED. Имена declared top-level = executed.

Committed selection: 75 RUN, 72 PASS, 3 FAIL, 0 SKIP. 71 прежних имён точно
равны baseline и каждое PASS. Новый lawful case PASS. Две новые дефектные
подпробы и их родитель FAIL; в выводе ровно две ошибки exact Reason.
Оба Kind carrier-not-a-choice, Where proto/corelib/subscription/subscription.proto,
Line 49 подтверждены до сверки Reason. Каждая дефектная форма имеет одну находку.
Fixture replacement count и обратное восстановление проверяются до анализатора.
Положительный близнец прошёл до дефектов; его census непуст.

Существующий TestSubscriptionShapeRefusesAnEmptyRead и все три подпробы
(непрочитанный контракт, пустой разбор, чужой пакет) PASS в baseline и committed selection.
Новый holder утверждает принятые Reason, а не читает их из source.
Прежние assertions, исходники и комментарии не изменены.

Отдельный собственный опыт с реальным corelib v1.8.0 при GOWORK=off:
branches=2 selected=false marshal_ok=true bytes=0. Это свидетельство границы
формы и экземпляра, не заключение о runtime-доставке.

Raw evidence: baseline-list-uncached.*, baseline-selection.*, baseline-census.json,
diagnostic-red.*, diagnostic-lawful.*, committed-selection-red.*,
committed-selection-census.json, independent-empty-message.*, baseline-module.*.
*.json каждого запуска содержит точный command/cwd/HEAD/rc и digests потоков.
All child GIT_* очищены; TMPDIR /var/tmp/area-ci-truth-tests вне Git.

Holder завершён и заморожен для handoff. Source implementation, его GREEN,
генерация/release/archive, convergence и main delivery этим RED не утверждаются.
