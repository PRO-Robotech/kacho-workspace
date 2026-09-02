# Pre-RED driver SDD-1

Этот каталог целиком принадлежит **integration-tester** (приёмка §6). В нём нет
и не может быть implementation: driver загружает fixture и вызывает SUT через
стабильный test seam.

Источник истины — `docs/specs/sub-phase-SDD-1-kacho-change-graph-acceptance.md`.
Driver **читает** её на каждом запуске и своей копии матрицы не держит. Приёмку
harness не правит: её verdict привязан к точному отпечатку файла.

## Единственная matrix command

```sh
python3 scripts/change-graph-gate/tests/run_case.py --case <ID>
```

## Исходов четыре, и четвёртый — не verdict

| код | категория | что значит |
|---:|---|---|
| 0 | `GREEN` | holder verdict |
| 10 | `RED` | holder verdict |
| 20 | `NOT_EXECUTED` | holder verdict |
| **40** | `HARNESS` | **поломка самого driver'а; holder verdict НЕ выдан** |

Четвёртый код существует ради требования §6: command-not-found, посторонний
crash и infrastructure failure **не подменяют** честный
`RED · CASE_CAPABILITY_MISSING · exit 10` и не открывают RED_PROVEN. Код 40 не
может быть прочитан как verdict ни одним потребителем, потому что не входит в
тройку holder-кодов. Он же — исход invalid fixture, как требует §12.

## Порядок проверок несущий

Проба capability стоит **после** всей валидации fixture:

1. приёмка читается и разбирается;
2. case ID существует в §13 и §14;
3. fixture есть и разбирается;
4. fixture дословно совпадает с приёмкой по twin, holder type, expected SUT и
   driver assertion;
5. planned holder coordinates существуют;
6. дельта относительно twin **пересчитывается** и равна одному объявленному факту;
7. **и только теперь** — проба capability SUT;
8. сравнение фактической тройки с assertion по трём полям порознь.

Сломанная fixture поэтому не может выдать себя за отсутствие capability.

## Как driver отличает отсутствие capability от собственной поломки

| состояние SUT | исход |
|---|---|
| файла SUT нет вовсе | `RED · CASE_CAPABILITY_MISSING · exit 10` |
| SUT есть, объявил набор, нашей capability в нём нет | `RED · CASE_CAPABILITY_MISSING · exit 10` |
| SUT есть, объявил набор, наша capability в нём есть | сравнение тройки |
| SUT есть, но проба сломалась | `HARNESS · HARNESS_SUT_PROBE_FAILED · exit 40` |

Отсутствие — положительное определение; сломанность — отсутствие определения.
«Не знаю» никогда не выдаётся за «нет».

## One-fact delta проверяется, а не обещается

Мир derived-кейса **вычисляется** применением одной операции к миру twin'а, а
driver независимо пересчитывает дельту и требует, чтобы она равнялась одному
**объявленному** факту. Больше одного факта либо факт не тот — `exit 40`, holder
verdict не выдан.

## Три birth fixtures драйвера

`SDD-1-DRIVER-01/02/03` — birth inversion **самого компаратора**: их предмет не
поведение SUT, а способность driver'а различать category, diagnostic и exit
порознь. Только им разрешено поле `sut_stub`; список закрыт и проверяется.
Любая другая fixture с этим полем — `HARNESS_STUB_NOT_PERMITTED`, иначе вся
матрица стала бы вакуумной.

## Прогон и доказательства

```sh
python3 scripts/change-graph-gate/tests/run_matrix.py initial   # все 196
bash    scripts/change-graph-gate/tests/selfcheck/prove.sh      # birth inversion harness'а
bash    scripts/change-graph-gate/tests/selfcheck/inject.sh     # доказательство, что prove.sh падает
```

`selfcheck/fake_sut.py` — подставной SUT **только** для проб harness'а. Он
ничего не вычисляет и достижим лишь через `KACHO_CG_SUT`, которой матрица не
выставляет; это проверяется утверждениями H1/H2 в `prove.sh`.

Через ту же переменную строится и **отсутствие** SUT — путь, которого нет на
диске. Оба состояния, дающие `CASE_CAPABILITY_MISSING`, поэтому СТРОЯТСЯ, а не
отыскиваются среди кейсов: утверждение «этого признака у испытуемого нет»,
выписанное на кейсе живого семейства, умирает в момент приземления семейства, и
класс растёт с числом семейств (#485). Требование держит страж внутри `expect`
в `prove.sh`: ожидание `CAP_MISSING` без `KACHO_CG_SUT=` — находка; что предмет
у стража непуст, утверждает `I1`, а что он способен упасть — инъекция
`unpinned-cap` в `inject.sh`. Что переопределение не подменяет production-путь в
матрице, держит `A2`.

## Перестроить fixtures

```sh
python3 scripts/change-graph-gate/tests/tools/build_fixtures.py
```

Авторская часть — `tools/casedata.py`: 48 базовых миров и 148 one-fact дельт.
Остальное выводится из приёмки.
