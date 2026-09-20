Независимый review отдельного addendum принят. Subject: `docs/changes/ci-doc-truth/addenda/issue-2711-scope.md`, SHA256 `c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100`, author commit `e3c0c7e18ad3b577b1d3cb8840b1e45277f125ef`. Reviewer — root, независимо от автора docs_truth и tester truth_tests. Прежние CI-DT acceptance/design и их exact-set не изменяются.

Проверены CI-DT-A1-01..03: нынешний комментарий действительно называет живой удалённую опцию; разрешено удалить ровно эти две строки, сохранив все остальные байты. История #1255 и узкое закрытие #1439 сохраняются.

Независимый comparator `7d849a4882496c3fe8620c2a5ea76abee4907c01a0934deb9ab7b9585aab81b9` прочитан root целиком, собран отдельно и проверен собственными контролями. Законное удаление проходит; изменение программного токена, дополнительная проза, отсутствие удаления, пустой/непрочитанный/не содержащий объявлений входы отвергнуты. Реально разобраны 482 токена и 6 объявлений, AST и directives сравниваются без исключений.

Baseline `88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0`: 15 объявленных top-level проверок; 55 RUN / 55 PASS / 0 FAIL / 0 SKIP. Root отдельно повторил более широкий набор 75/75. Существующий holder диагностик неизменен.

**Разрешён ограниченный source transition:** только удаление двух приведённых в addendum строк из `internal/repohygiene/subscriptionformshape_test.go`. Ожидаемый полный SHA файла после удаления: `ca976ed9e0be54f6273182d6f58de64e2d8fa8c176c27cefd893b104434e6e41`. Автор не правит comparator, assertions, остальные комментарии или исходный exact-set.

Review `area-ci-audit/contracts/doc-truth-root-review/addendum/review.md`, SHA256 `22e5c04b1aa36e9c218d4a01c3ff9c76e34677850842c090e7ec7a15ce9f0242`. После изменения обязательны independent candidate review, сохранение 55 исполненных имён и проверенный main delivery. Это ещё не GREEN кандидата и не основание для закрытия issue.
