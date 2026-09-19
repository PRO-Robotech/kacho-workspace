# #2590: независимый scope review и test-only RED

**Scope APPROVED** исключительно для subject
`0bf009e5c11cf964397bb32274e2492d8aed41fd6901918f4a8e8189587ca105`
из workspace `b2b10f13` и baseline record
`cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903`.
Автор reviewer/comparator — `e2e_audit`, не автор абзаца или product source.
Разрешение source worker остаётся отдельным переходом root.

Свежая issue #2590 открыта, comments отсутствуют; дополнительных owner bans в ней
нет. Свежий GitHub main corelib — `34bc8104a832b67e53c868646ab2b1e0ac4c8562`.
Notice file имеет полный SHA256
`90a9ddd66f9d2aa0bb992010cd4101b769c433f46de7cb37e2229db0e5bb6ee8`.
Read-only review прочитал весь notice file, integration producer, CI caller,
TestMain, синтетическую threshold chain и lazy-start путь pgtest. Hashes трёх
route-source файлов независимо совпали с baseline record. Авторский
`notice-doc-architect/verification.json` и root preflight были прочитаны как
атрибутированные данные; ниже приведён собственный повтор.

Предложенный текст правдив: локальные notice-пробы передают Notice приёмнику
напрямую; отдельные integration tests применяют синтетическую цепочку к Postgres;
producer выбирает пакет через TestImports/XTestImports и запускает без -short;
CI integration вызывает producer, pgtest.Run поднимает БД лениво. Текст не
приписывает этим пробам проверку настоящих platform migrations или доказанный
успех живого DB-прогона. Соседние устаревшие комментарии в scope не включены.

## Самостоятельный comparator и его контроль

Новый одноразовый внешний инструмент:
`/var/tmp/area-ci-independent-verifier/issue-2590/notice-preservation.go`.
Это не старый `strictpreservation.go` и не root-generated holder. Повторно
использованы только принципы полного scanner/token/AST разбора. Никаких whitelist
программных выражений/Reason/имён функций нет. Parser требует непустой input,
завершённый разбор и ненулевые declarations. Token stream полный, без comments;
AST исключает только физические позиции, comments в него не включаются.
Directives сохраняются отдельной проверкой. Literal patch и prefix/suffix bytes
проверяются независимо от program equivalence.

Comparator SHA256:
`756bccc81889d93333ccd9a285c3e7bc14e99de93a591d66bcaa0abbedc6a655`.
Driver SHA256:
`1bba2fd055ea093639d87e53eaab09b6854e1e26869d9c458bf26156dd7de433`.
Binary SHA256:
`b9b3b44d8eb49f0184913b5f4528301eb6f80e141b22fb0eb8347a147eadda64`.
Исходники verifier зафиксированы hashes и сделаны read-only после исполнения.

Все девять controls выполнены и дали ожидаемые исходы:

| Контроль | Наблюдаемый исход |
|---|---|
| Ровно proposed literal replacement | PASS / EXACT_REPLACEMENT_PRESERVED |
| Один program token: `const over = 7` → `8` | FAIL / PROGRAM_TOKEN_CHANGED |
| Один дополнительный комментарий вне региона | FAIL / NOT_EXACT_REPLACEMENT |
| Сохранённая старая шапка | FAIL / NOT_EXACT_REPLACEMENT |
| Пустой input | NOT_EXECUTED / CANDIDATE_EMPTY_INPUT |
| Реально нечитаемый файл при непривилегированном caller | NOT_EXECUTED / CANDIDATE_UNREADABLE |
| Валидный Go без declarations | NOT_EXECUTED / CANDIDATE_NO_DECLARATIONS |
| Незавершённый Go parse | NOT_EXECUTED / CANDIDATE_PARSE_FAILED |
| Новый directive вне региона | FAIL / DIRECTIVE_CHANGED |

Lawful fixture имеет exact ожидаемый полный SHA256
`c85a8ed9b06a0720fa4050e3537ee90892cb1aa81e84103aba63da7fe6125f96`
и 10443 bytes. Во всех допустимых сравнениях совпали **908 tokens, 7 declarations,
position-free AST**, набор шести test names и directives. Единственная замена —
baseline byte interval `[162,964)`; весь prefix/suffix совпадает побайтно.

## Честный RED и исполнимый охват

Отдельный `current-header-red` читает исходный notice из точного Git archive
main 34bc: rc1 / FAIL / NOT_EXACT_REPLACEMENT. Полная программа при этом разобрана,
tokens/AST/directives совпадают; причина RED — требуемый новый абзац ещё отсутствует.
Это не отказ notice delivery и не отказ harness.

Собственный actual selection: **76 пакетов прочитано, 14 отобрано, migratorcli
включён**. Census сохранён целиком, число 14 не зашито в comparator как вечная норма.

Шесть существующих notice tests исполнены дважды с точным declared/RUN/PASS набором:

- baseline archive: **6 RUN / 6 PASS / 0 FAIL / 0 SKIP**;
- lawful fixture через Go overlay: **6 RUN / 6 PASS / 0 FAIL / 0 SKIP**.

Overlay подменяет только внешнюю тестовую фикстуру при сборке. Ни одного product
файла не записано: все **473 файла** baseline archive сохранили исходные hashes,
notice checkout остался старым. Lawful proof не объявляется product implementation.
`GOWORK=off`, внешний TMPDIR, очищенные GIT_* и `GOFLAGS=-mod=readonly` зафиксированы
driver. Живую Postgres integration не запускали; её GREEN этим review не заявляется.

Все **17 command captures** завершены, stdout/stderr hashes каждого проверены.
Главный `holder-manifest.json` имеет SHA256
`99f9a2ac82f2eb0fbc7595f267d6e26c7a87f56795cb5aee0c7496f27e335fd1`.
`freeze.json` имеет SHA256
`c45a5bc0d7ecf027e89a109a6aaa76d21e85bd7efbe07b9f6e622bc2ffde57ce`.
Корпус, exact commands, raw streams, selection и исходники verifier лежат рядом.

Следующий допустимый шаг — отдельная root-авторизация worker на ровно эту замену,
затем независимый повтор comparator и шести existing tests на его exact commit.
Main/release delivery и закрытие issue остаются отдельными доказательствами.
