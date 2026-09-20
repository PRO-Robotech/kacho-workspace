# CI-DT addendum #2590 — принятый scope, RED и локальный GREEN

Эта новая запись сохраняет фактические события. Recorder `/root/e2e_audit`
создал независимый scope review и frozen comparator ранее; source paragraph
реализовал `/root/truth_tests`. Независимую проверку candidate и шесть tests
повторил `/root`. Этот перенос файлов не выдаётся за новый прогон.

## Принятый предмет и разрешение source

Exact addendum `addenda/issue-2590-scope.md` сохраняет историческую DRAFT шапку
и SHA256 0bf009e5c11cf964397bb32274e2492d8aed41fd6901918f4a8e8189587ca105.
Baseline record cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903
также неизменен. Root фактически принял этот scope и независимый RED событием
https://github.com/PRO-Robotech/kacho/issues/2590#issuecomment-5715803787.
Record: `reviews/scope-addendum/2590-0bf009e5.yaml`.

Текущая шапка дала NOT_EXACT_REPLACEMENT при годном comparator. Законный
replacement сохранил 908 program tokens, 7 declarations, position-free AST
без whitelist, directives и все bytes вне [162,964). Девять отрицательных/
законных controls и 17 captures сохранены с собственными hashes. Старые
шесть notice tests прошли в baseline и lawful overlay: 6 RUN/6 PASS, без
FAIL/SKIP. Actual selector прочитал 76 пакетов и выбрал 14, включая migratorcli.
Ни это измерение, ни новый текст не утверждают новый живой DB прогон.

## Независимый локальный candidate GREEN

Root опубликовал и прочитал обратно
https://github.com/PRO-Robotech/kacho/issues/2590#issuecomment-5716007037.
Его review SHA256
73b7333ab2e0aace39c5e9e1e50eb3b9df9e6e006ebbceb81113dd35645a4655
находится в `evidence/addendum-2590/root-candidate/review.json`; record —
`reviews/scope-addendum/2590-green-c0fd76af.yaml`.

Source author commit c0fd76af5c475ee76ddfc5897be58dd67967cd0a механически
интегрирован root как 431984c30e4c15b70c441e14e0438c24942aab7d. Общий tree
51f275bb03f5eb2e267f1b03d3bd299768c287ae. Единственное изменение — указанный
абзац migratorcli/notice_test.go, whole-file SHA256
c85a8ed9b06a0720fa4050e3537ee90892cb1aa81e84103aba63da7fe6125f96.
Root comparator подтвердил exact replacement, все 908 tokens/7 declarations,
AST/directives/prefix/suffix и шесть имён tests. Свежий candidate run:
6 RUN/6 PASS/0 FAIL/0 SKIP, package PASS, GOWORK=off, external TMPDIR.

Все перенесённые bytes перечислены в `evidence/addendum-2590/archive-index.json`.
Corelib snapshot tar остаётся в audit; канон содержит точные reports, captures,
comparator/driver и hash bindings. Readback bodies и исходные reviews не правились.

GREEN ограничен local comment-only source preservation и существующими шестью
пробами. Immutable CI-DT-01..09, принятые acceptance/design/holders, global
package lifecycle и предыдущая история сохранены. Protected main/aggregate
release delivery, final revalidation и closure #2590 остаются pending.
