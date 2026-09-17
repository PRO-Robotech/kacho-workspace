# CI-PY-1 — согласованные имена интерфейса для первого RED

2026-09-17. Автор /root/hygiene_audit и независимый integration-tester
/root/ci_verdict_audit согласовали ниже имена в пределах одобренных D2/D4.
Это конкретизация интерфейса для проб, не заявление о существующей реализации.

Python CLI: `--outcome-file PATH --invocation-id ID` (оба опциональны для обычного
ручного запуска; при запросе машинного результата ID обязателен). Producer также
читает env fallback; явно заданные CLI-значения имеют приоритет. Shell/Make:
`KACHO_CI_OUTCOME_FILE` и `KACHO_CI_INVOCATION_ID`. У родительского и дочернего
результата проверяется producer; результат одного этапа не объясняет отказ другого.
Вызывающий выделяет новый временный каталог вне git для каждого запуска.

Обязательные поля JSON:

```json
{
  "schema_version": 1,
  "invocation_id": "current-invocation",
  "producer": "run-python-probes",
  "category": "green",
  "unit": "python-probe",
  "counters": {
    "files": 1,
    "declarations": 1,
    "executed": 1,
    "failed": 0,
    "skipped": 0,
    "unmet": 0,
    "pytest_declarations": 1,
    "script_entries": 0
  },
  "findings": [],
  "unmet_reasons": []
}
```

`producer`: `run-python-probes`, `run-python-probes/self-test`, `gate-self-test`,
`ci-local`. `category`: `green`, `finding`, `unmet`. `unit`: соответственно
`python-probe`, `self-test-check`, `self-test`, `local-check`.

Все counters — неотрицательные целые. `files` — файлы переписи, `declarations` —
объявленные entrypoints текущего производителя, `executed` — действительно
исполненные экземпляры, `failed` — исполненные упавшие экземпляры, `skipped` —
явно пропущенные экземпляры, `unmet` — число невыполненных обязательных
участников/условий. Отсутствие одного pytest — одно условие; число непройденных
параметризованных экземпляров без collection нельзя выдумывать.

У обычного Python-производителя `declarations` включает pytest-функции и script-main
entrypoints; поля `pytest_declarations` и `script_entries` обязательны и дают
их разбиение. У других производителей это разбиение не применяется и не подставляется
нулём как будто измеренное. Параметризация законно делает `executed > declarations`.
Находка состава может дать `category=finding` при `failed=0`: её несёт findings.

`findings` — массив объектов `{producer, code, coordinate, message}`.
`unmet_reasons` — массив `{producer, code}`. Код отсутствия pytest —
`pytest-unavailable`; сообщение человеку производится из той же причины.
Иные причины не переименовываются в pytest. При finding рядом с unmet категория
finding, обе коллекции сохраняются. Только полный непустой результат даёт green.
Код 2 argparse, Make или неизвестной команды сам по себе не даёт unmet.

JSON записывается атомарно. Consumer проверяет версию, обязательные поля, текущий
ID, ожидаемого producer, категорию и согласованность счётчиков/причин. Старый,
чужой, пустой или повреждённый результат не даёт послабления «нет pytest».

Предложенные имена держателей закреплены в holders.yaml и route.md. До записи
независимого RED ни файл результата, ни имя теста не являются свидетельством.

Имена прямых шагов CI: `python-probes-collect` и `python-probes-verdict`;
второй исполняется с `if: always()`. Отдельный `pr_verdict_test.py` остаётся
обязательным. Реальные тела шагов передают путь и ID через GITHUB_ENV/RUNNER_TEMP;
holder исполняет эти тела, а не поддельный аналог цепочки. На baseline новый
интерфейс проверяется через env и прежний CLI: неизвестный argparse-флаг сам по
себе не является честным RED отсутствующего поведения.
