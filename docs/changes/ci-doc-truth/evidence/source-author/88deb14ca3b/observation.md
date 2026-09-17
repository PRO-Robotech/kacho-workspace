# CI-DT-1 — авторский implementation handoff

Source commit: `88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0` на immutable test-only base
`e58e6f581e858df6a9ffd3c25d93cbfcc1800128`.
Локальная проверка автора, не независимый GREEN и не delivery.

Допуск заново прочитан через API:
https://github.com/PRO-Robotech/kacho/issues/2696#issuecomment-5714360568,
body SHA-256 `eae696d06ca2539efa9cba2b14495feef3ca2366e95223a4f1ad79beb1283b0c`.
Acceptance `0d9a2074718bc1de5826696f64bf43af1a98182f91c2866d51e1d93d42986b24`
и design `f77397339a15cd51c09ab59df2e8e4b5072e7549c2242eeae6586fccde1d2047` не изменены.

## Реализованный предел

Ровно четыре принятых Go-файла и canonical proto, без изменения списков,
Kind, predicates, counters, helper/assertions и runtime логики. Два Reason
совпадают с принятым контрактом; их AST выражений сохранён. У proto заменены
только четыре строки одного комментария, все остальные байты равны базе.
Шесть исторических регионов сравнены побайтово; описание прежнего опыта
ослепления ветви и commit-bound census прежние.

Неизменный holder `internal/repohygiene/subscriptionreason_test.go`:
SHA-256 `9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35`.
Файл `subscriptionformshape_test.go` за пределами этого допуска не изменён.

## Исполнение автора

- Uncached selection: 75 RUN / 75 PASS / 0 FAIL / 0 SKIP, rc 0.
- Все 75 имён совпадают с root-approved RED. 31 top-level имя совпало с
  отдельным `-list -count=1`.
- Отдельный diagnostic run: 4 RUN / 4 PASS / 0 FAIL / 0 SKIP, rc 0.
- Неизменный tester verifier `preservation.go`, SHA-256
  `fbaa2f1f049d0f561cf64e2243adc7d240ef396656edf13f5a9cda72501469ee`:
  PASS на exact base/candidate, четыре файла, 9809 program tokens,
  ровно девять разрешённых string leaves двух Reason.
- `git diff --check` и `gofmt -l` чистые; оба owned checkout чистые.

Команды, cwd, GOWORK=off, внешний TMPDIR, hashes stdout/stderr и имена тестов
закреплены в `candidate-*.json`. Сырые потоки лежат рядом. Все дочерние Git
команды запускались с удалёнными унаследованными GIT_*.

## Generated handoff

Baseline staging: `/home/dk/kacho-tmp/area-ci-tools/ci-dt-author-baseline-usp1cb7l`.
Candidate staging: `/home/dk/kacho-tmp/area-ci-tools/ci-dt-author-candidate-6ec47lvs`.
Четыре файла для передачи находятся под candidate `pkg/`; destination в corelib
получается удалением этого префикса. Corelib worktree не редактировался.

| Destination | SHA-256 candidate |
|---|---|
| `api/corelib/subscription/subscription.pb.go` | `b7904d4d4a68efd8d5ab1f60b10489cc51318ff7f35b1fba35bbc96073a252aa` |
| `api/corelib/subscription/subscription_service.pb.go` | `a400a469bd7850d30f011e80cc08b304a56306873e11d8fcefe13ffda9bacea3` |
| `api/corelib/subscription/subscription_service.pb.gw.go` | `b0d2f8ec8b145f163e6cd37b55857cb3f7c5f7b55eed82cc2b84026c81b611c0` |
| `api/corelib/subscription/subscription_service_grpc.pb.go` | `c9d7e47d26254ac5cef33d3aa2508bc915bcc75bab69947f1adc93f71f501b9f` |

Baseline заново воспроизвёл четыре файла module v1.8.0 побайтово. Для обоих
SHA архивированы proto/go.mod/go.sum; prefix buf.gen.yaml до inputs сохранён,
изменён только staged input на corelib/subscription. Выполнены `buf generate`
и `buf build --path corelib/subscription --as-file-descriptor-set
--exclude-source-info` при buf 1.72.0 / Go 1.26.8.

От baseline отличается только `subscription.pb.go`, четырьмя строками
комментария. Три service-файла побайтово прежние. Авторский одноразовый
comparator подтвердил tokens/position-free AST для всех четырёх файлов
(5171 program tokens), без whitelist; его собственные lawful comment,
one-token defect, empty и declaration-free birth controls прошли.
Точный исходник/digest находятся в generated-preservation-execution.json.

Основной raw descriptor: 1388 bytes,
SHA-256 `68d2157de5d3d78b1f0796c70a8e1795fe09a99201fbf6a3e71348f3e3b285e3`.
Semantic FileDescriptorSet без source info побайтово одинаков,
SHA-256 `663029870c57c2c0d5ae1b4655e5a2001839e262d63d7e0b41158ccdd304206f`.
Generated diff сохранён целиком в `generated.diff`; ручных generated edits нет.

## Отдельное предложение #2711

Own docs commit `e3c0c7e18ad3b577b1d3cb8840b1e45277f125ef` поверх точного
approved planning `9606cb32e3413295c7abb0faa48ea25da6df9db3`.
Новый файл `docs/changes/ci-doc-truth/addenda/issue-2711-scope.md`,
SHA-256 `c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100`.
Он DRAFT и требует собственного review/transition; source fifth-file не менялся.
Docs gate: 7 PASS, 0 FAIL, 0 VOID. API body #2711 заново прочитан и совпал
с root snapshot. Старые acceptance/design/review subject bytes сохранены.

Независимая candidate-проверка, Go/proto post-diff review, real corelib release,
archive verification, consumer pin, convergence и main landing остаются root.
Автор не публиковал refs/комментарии, не делал merge и не закрывал issues.
Все перечисленные локальные артефакты имеют hashes в
`implementation-artifact-manifest.json`.

Каноническая запись автора: этот каталог содержит побайтовые копии 27 исходных
артефактов audit по implementation-artifact-manifest.json. Авторские исходы не
заменяют независимый candidate GREEN; lifecycle Change Graph здесь не повышен.
External staging paths являются местом передачи payload, их содержимое судится
по закреплённым hashes и повторной генерации, а не по существованию каталога.
