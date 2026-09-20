# CI-NP-1 — Routine interface независимого держателя

Документ фиксирует обычные имена CLI, полей и тестового seam до fixtures и
реализации. Он не меняет APPROVED приёмку
`2c30dc5fb1ba6fb985b8e63918c5c4bd58a115d06bf31e35006acf737531e400` и замысел
`d60f34f6a2458e011f46cbe460310ed0e5071ee0635ae0fb188a70c387bc9181`.
Наличие executable или RED здесь не утверждается.

## Python CLI и результат

Канонический каталог corelib: `ci/newman_publication/`. Из корня разрешённой
версии corelib либо с добавленным только этим корнем в PYTHONPATH:

```sh
python3 -m ci.newman_publication project --manifest PRIVATE.json --output-dir FRESH
python3 -m ci.newman_publication scan --archive LEGACY.zip
python3 -m ci.newman_publication check --archive FRESH/publication.zip --manifest PRIVATE.json
```

`check --archive -` принимает полный ZIP через stdin: это штатный IPC загрузчика.
`scan` проверяет поддержанные исторические carriers; `check` дополнительно требует
закрытую projected schema и связь с доверенным каталогом. CLEAN от scan сырого ZIP
не разрешает новую публикацию. Ни одна команда не печатает исходные path/key/value,
parser message, peer error или traceback. Неправильный CLI также получает безопасный
NOT_EXECUTED: argparse не должен возвращать недоверенный аргумент в диагностике.

stdout содержит ровно один JSON; stderr пуст при штатном отказе. Поля только эти:

```json
{
  "schema_version": 1,
  "operation": "project",
  "status": "CLEAN",
  "code": "COMPLETE",
  "files_declared": 1,
  "files_checked": 1,
  "fields_checked": 1,
  "findings": 0,
  "archive_bytes": 100,
  "archive_sha256": "64 lowercase hex characters, or null"
}
```

operation — project/scan/check; status и rc: CLEAN=0, FINDING=1, NOT_EXECUTED=3.
Все числа — неотрицательные integer, JSON bool не подходит. Закрытые codes:
COMPLETE, SECRET_MATERIAL, EMPTY_INPUT, MISSING_INPUT, UNREADABLE_INPUT,
MALFORMED_INPUT, UNSUPPORTED_INPUT, UNSUPPORTED_ENCODING, LIMIT_EXCEEDED,
SOURCE_MISMATCH, UNSAFE_PATH, OUTPUT_EXISTS, INTERRUPTED, CHECKER_UNAVAILABLE,
INTERNAL_ERROR. При публикации checker должен дать CLEAN/COMPLETE, findings=0,
положительные files_declared=files_checked, полные digest/size ZIP.

Для project digest относится к выходному ZIP, для scan/check — ко всем входным
байтам ZIP. Это не digest выбранных members. При неполном чтении digest=null;
доля осмотренного сохраняется, отсутствующий вход не вычитается из declared.
Находка не печатает секрет. project требует новый ещё не существующий output-dir;
успех оставляет только publication.zip и verdict.json (точно тот же JSON, что stdout).
Отказ не оставляет publication.zip и не использует результат прошлого запуска.
Полный отчёт с упавшим тестом может дать CLEAN публикации: красный тестовый факт
сохраняется. Отсутствующий объявленный отчёт даёт NOT_EXECUTED без готового ZIP.

## Приватный manifest и связь с исходным каталогом

Schema version1, фиксированные top-level keys:

```json
{
  "schema_version": 1,
  "source_root": "/private/checked-out-repository",
  "source_commit": "40 lowercase hex commit",
  "input_root": "/private/raw-report-root",
  "run": {"id": 1, "attempt": 1, "shard_index": 0},
  "reports": [{
    "index": 0,
    "collection": "tracked/path/collection.postman_collection.json",
    "collection_sha256": "64 lowercase hex",
    "report": "relative/path/raw-report.json"
  }],
  "logs": [{"index": 0, "path": "relative/path/raw.log"}],
  "verdicts": [{"index": 0, "kind": "kacho-shard-v1", "path": "relative/path/verdict.json"}]
}
```

reports непуст; logs/verdicts могут быть пусты. Каждый список имеет уникальные
непрерывные индексы от0. Paths приватны и не становятся именами результата.
Абсолютные member paths, traversal, symlink, дубли и неоднозначные members дают
отказ. Два root-поля задают явные приватные корни. source_commit равен настоящему
HEAD source_root. Каждая collection отслеживается в этом commit; и bytes checkout,
и blob этого commit имеют collection_sha256. Manifest создаётся локально из текущего
объявленного каталога суит, а не из raw report. Fixture holder создаёт настоящий
малый Git repo с tracked catalogue; произвольный заявленный hash не является twin.

Упорядоченный fingerprint коллекции сырого отчёта и cursor relations сверяются с
доверенной collection ДО подстановки доверенных имён. Равного числа requests мало:
однофактный stale-source того же размера должен отказать. Неизвестные обязательные
формы отчёта, manifest keys и явно объявленные encoding дают отказ без их вывода.

ZIP members имеют производимые имена: manifest.json, reports/report-000001.json,
logs/log-000001.json, verdicts/verdict-000001.json; нумерация от1 по index.
Исходные archive comments, ZIP extras и filenames не копируются. Публичный manifest
несёт schema_version, numeric run, производимые member names, SHA256/size members,
catalogue indices/digests. В нём нет input roots/paths, arbitrary metadata и raw logs.

Projected report сохраняет run.stats, execution/HTTP факты, iterations и число
failures. Сохраняются различия precondition, script-error, unanswered и обычного
assertion. Разрешённые source/parent IDs происходят из проверенного каталога;
opaque body, URL, scripts, free error/test message и неизвестные keys снимаются.
Узкий reader adapter может читать фиксированную категорию failure, но не менять
предикат. Держатель вызывает настоящие readers до/после, без второй таблицы истинности.

Начальная verdict shape только kacho-shard-v1 — текущая
.github/scripts/shard-verdict.py. Числовые факты: expected, reported, requests,
unanswered, assertions, failed, script_failed. missing/empty/per_collection
связываются с declared report indices, а не копируют входные keys. shard/suite
labels происходят из доверенного consumer catalogue; precondition — фиксированная
категория и наблюдаемый bool, без свободного detail. Неизвестная verdict shape
отказывает. Другой producer требует явно заданного узкого adapter; arbitrary JSON
сквозь публикацию не проходит. Regex над входным текстом не создаёт доверия.

## Явные пределы

Это выбранная capacity policy, не результат измерения производительности.
Срез metadata17сентября дал максимальный retained ZIP 6105197 bytes Kachō и
900690 bytes Kaname. Частичный осмотр central directories скачанных архивов
(475 Kachō, 208 Kaname, bodies inspected0) дал max expanded91781172/12324641,
max entry19517096/3523512 и max entries67/50 соответственно. Это метаданные
архивов, а не содержимое и не verdict CLEAN. Запас над срезом не доказывает,
что любой будущий вход помещается;
каждый предел проверяется отдельно при чтении, превышение даёт
NOT_EXECUTED/LIMIT_EXCEEDED без молчаливой обрезки.

| Поле limits | Default и верхний потолок |
|---|---:|
| archive_bytes | 67108864 |
| expanded_bytes | 268435456 |
| document_bytes | 67108864 |
| zip_entries | 1024 |
| decode_depth | 8 |
| decoded_nodes | 100000 |

Каждая Python-команда принимает необязательный `--limits LIMITS.json`: JSON object
из выбранных полей этой таблицы. Неуказанные имеют default. Значения только integer
от1 до соответствующего потолка; неизвестные поля или попытка увеличить потолок
дают безопасный MALFORMED_INPUT. Точное равенство допустимо, превышение отказывает.
Настройка нужна для меньших runtime budgets и воспроизводимой проверки границы;
тест не должен создавать гигабайты ради инъекции малого лимита.

## JavaScript receiving seam

Общая action: ci/newman_publication/action/action.yml, runs.using=node24.
Штатный entrypoint action/main.mjs; импортируемая граница action/publish.mjs:

```js
await publishSnapshot({
  archivePath, manifestPath, run: {id, attempt, shardIndex},
  checker, transport, afterCheck,
  maxArchiveBytes: 67108864, checkerTimeoutMs: 120000
});
```

Функции — module seam держателя, не workflow inputs или команды из env. Production
main фиксированно задаёт canonical Python checker и @actions/artifact@6.2.1 transport.
Необязательный afterCheck не получает ссылку на snapshot и нужен для изменения
исходного файла после последнего успешного check. Два числовых budget options могут
только уменьшать показанные потолки, оставаясь integer>=1; неправильный option
даёт NOT_EXECUTED/INVALID_REQUEST. Неокончившийся checker отменяется за заданный
timeout: publisher вызывает abort() своего AbortController и передаёт AbortSignal
через signal. Штатный checker связывает этот signal с завершением child; одного
Promise.race недостаточно. Holder наблюдает abort и отсутствие transport; actual
child termination дополнительно проверяется у fixed entrypoint.

checker({bytes, manifestPath, signal}) получает отдельную копию private snapshot и возвращает
точный check-result выше. Publisher проверяет schema, operation=check, size/digest,
counts и CLEAN до первого transport call. Missing/throwing/malformed/non-CLEAN
checker не вызывает transport. transport({name, stream, size, sha256}) получает
поток того же private snapshot, без пути/raw inputs. name строго
newman-publication-<id>-<attempt>-<shardIndex>, numeric id/attempt>=1, shardIndex>=0.
Успешный return транспорта: {artifactId, size, sha256}; artifactId positive integer,
size/digest совпадают. Несовпадение/exception не даёт публичного успеха.

publishSnapshot всегда разрешает promise в один безопасный object с полями:
schema_version=1, status, code, artifact_id, archive_bytes, archive_sha256.
На успехе status=PUBLISHED, code=COMPLETE, artifact_id positive integer,
archive_bytes/digest полного snapshot. На отказе artifact_id=null; size/digest
сохранены лишь если snapshot прочитан полностью, иначе0/null. Других полей нет.

Закрытые пары status/code:

- PUBLISHED / COMPLETE;
- FINDING / SECRET_MATERIAL (только подтверждённый checker FINDING);
- NOT_EXECUTED / INVALID_REQUEST, INPUT_UNAVAILABLE, LIMIT_EXCEEDED,
  CHECKER_UNAVAILABLE, CHECKER_TIMEOUT, CHECKER_INVALID, CHECKER_INCOMPLETE,
  TRANSPORT_UNAVAILABLE, TRANSPORT_MISMATCH, INTERNAL_ERROR.

Non-CLEAN NOT_EXECUTED checker даёт CHECKER_INCOMPLETE. Нарушенная форма/другой
digest/operation дают CHECKER_INVALID. Ошибка/отсутствие checker функции —
CHECKER_UNAVAILABLE; исключение транспорта — TRANSPORT_UNAVAILABLE. Внешний
message/stack не является code и не переносится в результат.

Runtime credentials runner передаёт JS action; их видит только SDK, checker env
очищено. SDK stdout/stderr приватно захватываются до вызова; action не печатает
исходные exceptions. Holder инъецирует узнаваемый материал в ошибки checker/transport
и в filesystem после check, сравнивает bytes именно принимающего транспорта.
Отдельная SDK compatibility probe исполняет измеренный pinned internal stream API,
а не подменяет выбранную SDK функцию пустой заглушкой.

## Владение держателями и граница доказательства

Независимые executable координаты до их создания:

- corelib ci/newman_publication/tests/test_publication.py через Python unittest;
- corelib ci/newman_publication/tests/upload.test.mjs через Node test runner;
- собственные parsed-workflow holders в Kachō и Kaname;
- отдельные реальные full-runtime, retention/containment и prelanding records.

Tester сначала доказывает годность Newman fixtures, readers, Python/Node/SDK,
затем судит отсутствие требуемой producer capability как RED. Негодный interpreter
или fixture — NOT_EXECUTED. Синтетические локальные tests не закрывают полный
identity/all-shard runtime, download re-scan, историческую retention перепись,
exact containment и свежую prelanding перепись. Это отдельные последующие holders.
