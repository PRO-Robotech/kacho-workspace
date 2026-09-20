# CI-DT-1 — независимый root review диагностического RED

Предмет: переход от test-only к реализации уже принятого CI-DT-1.
Reviewer /root; tester /root/truth_tests. Root не автор holder или implementation.
Acceptance SHA256 0d9a2074718bc1de5826696f64bf43af1a98182f91c2866d51e1d93d42986b24.
Design SHA256 f77397339a15cd51c09ab59df2e8e4b5072e7549c2242eeae6586fccde1d2047.
Test-only commit 0eae6a3569f062bcdf0c1184c1750b95eea5beb7;
root mechanical import e58e6f581e858df6a9ffd3c25d93cbfcc1800128.

Root прочитал весь новый holder (87 строк), принятую приёмку и маршрут,
исходные Shape helper/Reason координаты; сверил 20 hashes stdout/stderr tester.
Новый файл единственный diff к b5fa093341f1fdbe96adfc6a9555482690968253;
его SHA256 9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35.
Образцы задают два независимых одно-фактных изменения непустого законного
контракта; число замен и обратное восстановление проверены до shapeAudit.
Оба Kind и Where/Line проверены до exact Reason. Expected Reason буквально
совпадают с двумя утверждёнными строками CI-DT-03/04.

Собственное исполнение root через go test -count=1 -json, GOWORK=off,
внешний TMPDIR, без наследованных GIT_* дало 75 RUN, 72 PASS, 3 FAIL, 0 SKIP.
Прежние 71 имён точно сохранены и все PASS. Новый lawful twin PASS.
Падают только две диагностические подпробы по Reason и их parent;
ошибок Reason ровно две. Kind/Where/Line и непустой census прошли.
Root protobuf опыт ранее независимо подтвердил branches2, selectedfalse,
marshal_oktrue, bytes0, не делая вывод о runtime доставки.

VERDICT: SCOPED_RED_APPROVED. Разрешена реализация четырёх Go файлов и
canonical proto в точных границах D1–D5, CI-DT-01..09. Generated артефакты
только штатной узкой генерацией. Прежние assertions, history, descriptor,
Kind/control flow и holder неизменны. Дополнительный dangling comment в
subscriptionformshape_test.go:102–103 находится вне утверждённого exact-set:
его изменение этим событием не разрешается; нужен отдельный scope addendum.

Полный GREEN, token/AST comparator с birth inversions, generated comparison,
release/archive/pin, post-diff review/convergence и main delivery обязательны.
Результат не закрывает #2696/#2591/#2592 и не объявляет delivery состоявшейся.
