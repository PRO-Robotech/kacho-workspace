# #2711 — авторский исход точного удаления

Автор: `/root/docs_truth`. Это исполнение разрешённой правки. Последующий
независимый post-diff GREEN принадлежит отдельному root review, не этому отчёту.

Source commit: `d248443319f9bc927d81bea04794c4405528f62e`.
Parent: `88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0`.
Изменён только `internal/repohygiene/subscriptionformshape_test.go`: удалены
ровно две строки комментария, процитированные в принятом addendum.

Допуск повторно прочитан через API:
https://github.com/PRO-Robotech/kacho/issues/2711#issuecomment-5714826585.
Body SHA-256: `46053c141c406767484645f576f69663d7aa8f444cbf6a583bb591ae99f37c4d`.
Addendum SHA-256: `c57a9d30e9ce1876297f40e0b589ec2d01a551a9913064c81fc73cfcd1d49100`.
Полный target file SHA-256 после удаления совпал с заранее ожидаемым:
`ca976ed9e0be54f6273182d6f58de64e2d8fa8c176c27cefd893b104434e6e41`.

## Сохранность

Исполнен неизменный независимый `strictpreservation.go` из frozen tester bundle,
SHA-256 `7d849a4882496c3fe8620c2a5ea76abee4907c01a0934deb9ab7b9585aab81b9`.
Инструмент отдельно собран автором во внешнем TMPDIR; результат candidate:
PASS, 482 program tokens, 6 declarations, zero whitelist. Проверены точное
удаление двух строк, равенство всех остальных байтов, tokens/AST/directives.
Команда и полные потоки находятся в `strict-candidate.*`; инструмент не менялся.
Его рождение и отрицательные контроли принадлежат независимому tester/root и
сохранены в соседнем immutable archive, не выдаются за работу автора.

Holder `internal/repohygiene/subscriptionreason_test.go` остался SHA-256
`9b64d9cb6e89e94f3416bc671caff9d7c3927ca1a60ca199f58d7915bfac1b35`.
Assertions, прочие комментарии, историческое пояснение #1255 и предыдущие
accepted subjects не правились. Исходный четырёхфайловый verifier CI-DT-1
не расширялся. Полный commit diff — один файл, две удалённые строки.

## Исполнение

Оба набора прогнаны с `-count=1`, GOWORK=off, внешним TMPDIR и без
унаследованных GIT_* у дочерних команд. Каждый предварён своим uncached `-list`.

| Selection | Top-level | RUN / PASS / FAIL / SKIP | Exact names |
|---|---:|---|---|
| Форма и её инъекции | 15 | 55 / 55 / 0 / 0 | Совпали с independent baseline на 88deb14 |
| Форма, mount и catalog | 31 | 75 / 75 / 0 / 0 | Совпали с отдельным root baseline на 88deb14 |

SHA-256 сортированного полного набора 55 имён:
`dcf5efe53f313e63b994c5b929904873a9682b28a2f892a935d523ae2650025e`.
SHA-256 набора 75 имён:
`8d51298cf25fa512ab49170d0d32015cb18de34c12b5faabe1c94bbc62faf930`.
JSON records и исходные потоки содержат exact commands, cwd, source SHA,
rc, elapsed time и hashes; census хранит каждое имя. Пустой прогон не принят.
Все запущенные процессы завершились до handoff; product worktree чистый.

Последующий независимый review нового candidate сохранён в
`docs/changes/ci-doc-truth/evidence/addendum-2711/root-candidate/review.md`.
Его SCOPED GREEN подтверждён событием #2711/5714931717. Отдельный исход
88deb14 не переносился на d248443319f: root прочитал новый diff и исполнил
собственные comparator и 75 probes. Aggregate verification и main delivery,
а также release/archive/pin из CI-DT-09 остаются открытыми.
