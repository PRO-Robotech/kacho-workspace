# CI-DT-1 — архив независимого исхода и отдельного допуска #2711

Эта запись сохраняет полученные исходы и их границы. Её составитель
`/root/docs_truth` — автор source, а не независимый reviewer. Accepted
acceptance/design/addendum bytes и прежние review records не редактируются.

## Исходный candidate 88deb14

Независимый `/root/truth_tests` выпустил SCOPED GREEN на exact source
`88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0` и повторённую им generated проекцию.
Полный отчёт сохранён в
`docs/changes/ci-doc-truth/evidence/independent-88deb14/tester/candidate-88deb14-review.md`,
SHA-256 `635bbf13af1087713edd54a3ff01b91aeec96ccb98017c6e3a8a311f11d033be`.

Его frozen manifest проверен по всем 71 entries и скопирован побайтово вместе
с артефактами, включая оба набора generated файлов, descriptors, исходники
comparator, birth controls и raw outputs. Изменённые Kind/predicates не
маскируются: исходный verifier сохраняет 9809 tokens с ровно согласованными
Reason leaves, generated comparator — 5171 tokens без whitelist.
Tester исполнил 55/55 shape probes; root отдельно подтвердил 75/75 broader
probes с теми же именами, неизменным holder и полным source preservation.

Корневые command records и потоки находятся в том же archive под `root/`.
Ранний `root/boundary-review.json` сохранён буквально: его поле о ещё
ожидавшейся на тот момент independent generation не переписано задним числом.
Последующий завершённый результат генерации принадлежит указанному tester
review и его собственным captures. Archive index связывает каждый файл с hash.

Root выпустил отдельное событие SCOPED GREEN:
https://github.com/PRO-Robotech/kacho/issues/2696#issuecomment-5714927198.
Автор повторно прочитал его через API: body SHA-256
`cf51cb5c999accb56d4cbf58b737a973c22e3bd28414e8ed9fdaaa29f2795428`.
Root review SHA-256:
`5ff3917948c272faf9e4847291e93a07f6875f259b30fc2756b2c859f6500b64`.
Машиночитаемая граница записи:
`docs/changes/ci-doc-truth/reviews/integration-tester/green-88deb14.yaml`.
Это scoped source/projection outcome, не полный GREEN Change Graph.
CI-DT-09 release/archive/pin/main не завершён.

## Отдельный допуск #2711

Root независимо принял addendum subject
`c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100`
и опубликовал отдельный source transition:
https://github.com/PRO-Robotech/kacho/issues/2711#issuecomment-5714826585.
Событие заново прочитано автором через API; body SHA-256
`46053c141c406767484645f576f69663d7aa8f444cbf6a583bb591ae99f37c4d`.
Независимый review SHA-256:
`22e5c04b1aa36e9c218d4a01c3ff9c76e34677850842c090e7ec7a15ce9f0242`.

Review, root birth controls и readback сохранены в
`docs/changes/ci-doc-truth/evidence/addendum-2711/root-transition/`.
Record допуска:
`docs/changes/ci-doc-truth/reviews/scope-addendum/2711-c57a9d30.yaml`.
Допуск разрешает только удаление двух строк в пятом Go-файле и не расширяет
исходный четырёхфайловый verifier или approvals CI-DT-1.

Автор исполнил этот допуск commit
`d248443319f9bc927d81bea04794c4405528f62e`; отдельный observation и captures
сохранены в `docs/changes/ci-doc-truth/evidence/addendum-2711/source-author-d248443319f/`.
Это авторский PASS exact deletion/comparator/55+75 probes. Затем root
независимо прочитал весь новый diff и повторил строгий comparator и 75 probes:
все PASS, имена равны baseline. Его review SHA-256:
`6716e76ca68efab81074f1bb38d84f60bd6a8b094c2e6c8c382e3d30313b4b34`.
Событие SCOPED GREEN заново прочитано через API:
https://github.com/PRO-Robotech/kacho/issues/2711#issuecomment-5714931717,
body SHA-256 `95d43b6a02dfe19fd081f22c0bdf8c951ad5570fd5e3596450c6e68917d0202d`.
Полные records находятся в `evidence/addendum-2711/root-candidate/`, запись
исхода — `reviews/scope-addendum/2711-green-d248443319f.yaml` внутри CI-DT package.

## Механическая локальная интеграция root

Root импортировал test/source/addendum в Kachō aggregate commit
`7a41adf7b53cbcee1fbddc84b7408299a0832742`; его tree равен d248443319f.
В corelib aggregate commit `80447d27a89398bc1cfca8ceea878204bb3ab4ba` root
скопировал четыре independently generated payload после сверки baseline;
изменился только `subscription.pb.go` четырьмя строками комментария, с
ранее проверенным SHA-256 `b7904d4d4a68efd8d5ab1f60b10489cc51318ff7f35b1fba35bbc96073a252aa`.
Ручного редактирования generated кода нет. Исходные root records и полный diff
сохранены в `docs/changes/ci-doc-truth/evidence/local-integration/`.

Это локальная интеграция. Публикация, выпуск версии corelib, archive/pin,
aggregate convergence и main delivery ещё не состоялись; issues этой записью
не закрываются. Старые accepted subjects и lifecycle целого пакета не меняются.
