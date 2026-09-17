# CI-RS-1 — авторская экспозиция классов для независимого разбора

**DRAFT, 2026-09-17.** Это вход будущему class-exposure-analyst, не независимая
initial/revalidation запись. Автор совпадает с автором acceptance/design.
Independent initial привязывается к acceptance hash; revalidation — к design
hash. Все держатели в таблице заказаны, их исполнения здесь нет.

| ID | Решение и класс | Проверяемое условие на реализацию | Design; держатель |
|---|---|---|---|
| E1 | Ready-tree вместо revision; «Перечень входных поверхностей неполон» | Полный path/mode/content census из immutable snapshot, file kind проверяется до чтения; input не меняется в процессе | D2; candidate-preflight |
| E2 | Preserve/replace/remove; «Умолчание, которое становится утверждением» | Все base/input paths классифицированы ровно один раз; receiving owner нельзя понизить manifest входа; `.github` — обязательное сохранение | D2; candidate-preflight |
| E3 | Floor; «Инвариант, замкнутый по одной стороне вердикта» | Previous release существует, идентифицирован и census непуст; candidate не теряет ни одного package path; counts участвуют в permit | D3; candidate-preflight |
| E4 | Consumer import declaration; «Состав написан, а не выведен» | Перечень imports выводится из exact repository tree либо committed external-program; тип явно объявлен, probe не притворяется downstream; сравнивается set, не длина; zero consumer/imports и непрочитанный файл отказывают | D3; consumer-imports |
| E5 | Archive против checkout; «Применённое ≠ исходник» | Target только из candidate zip; отдельные cache/proxy, GOWORK off, replace absent; локальная копия не помогает | D3; consumer-imports |
| E6 | План и необратимый шаг разделены; «Решение и его следствие разнесены» | Execution bound to repo/base/input/plan digests; fresh checks перед мутацией; новый head отменяет старый permit | D2/D4; publisher-protocol |
| E7 | GitHub/Go proxy ответ; «Третий исход — не смог спросить» | Ошибка сети/бюджета/источника отдельно от нарушения дерева; ни неизвестный required context, ни skipped не дают GREEN | D4/D6; publisher-protocol |
| E8 | Merge/tag/release note — разные операции | Readback после uncertain write; remote факт монотонен; force/rewrite и повторный несовпавший tag запрещены; partial state отражён честно | D4; publisher-protocol |
| E9 | origin reachability/main ancestry; «Гейт сверяет имя, а не идентичность» | Exact repo mapping, complete fresh refs, peeled commits, repository-bound ancestry; branch-only допускается общим gate и отвергается final mode | D5; internal-pins |
| E10 | Zero pseudo и empty walk | Ноль pseudo при ненулевом product census законен; ноль modules/internal requirements продукта красный. Leaf corelib имеет отдельный запрет обратных рёбер | D5; internal-pins |
| E11 | NP non-Go payload и CI-DT generation | Archive содержит точные non-Go members; comment-only proof связан с generated SHA; положительный Go build не заменяет эти две обязанности | D3/D4/D7; released-payload |
| E12 | Переиспользование существующей оснастки; «Намеренная узость становится контрактом абстракции» | Service/revision старого publisher не переосмыслен; переиспользуется узкий archive/census код, не копия publisher; #2661 и чужие lanes не внедряются | D1/D7; scope-review |

## Измеренное и срок наблюдений

На 2026-09-17 прочитаны tracked go.mod трёх exact trees:

| Repo и SHA | Module roots; текущие внутренние requirements |
|---|---|
| Kachō `b5fa093341f1fdbe96adfc6a9555482690968253` | 1, root; corelib `v1.8.0`, Kaname `v0.4.1-0.20260917021918-94352d9c4a88` |
| Kaname `39628487099fe44990e9e03b09b725f3d7e37abb` | 1, root; corelib `v1.9.0` |
| Corelib candidate `4d37cfb6ef62d31c09cd65daadf09bdef671d3a5` | 1, root; внутренних PRO-Robotech requirements 0 |

Единица — tracked go.mod и require, не совпадение в комментарии. Предикат:
`git ls-tree -r --name-only <sha>` с точным suffix go.mod, затем чтение каждого
`git show <sha>:<path>` и разбор директив. Это перечисление трёх деревьев, не
полная перепись всех remote repos. Kachō pin commit `94352d9c4a88` на прочитанной
Kaname main ревизии — ancestor, `git merge-base --is-ancestor` вернул 0.

Fresh GitHub main refs совпали с указанной Kaname ревизией и corelib
`34bc8104a832b67e53c868646ab2b1e0ac4c8562`. Публичный
`corelib/@v/v1.9.0.info` ответил 200 и именует именно этот origin hash и tag.
GitHub `releases/latest` ответил 404: tag/module version не равны release-note
object. Полный v1.9.0 zip и package floor здесь **не измерены**; это заказ
preflight перед следующим выпуском, не нулевой floor.

`publish-version.sh` на Kachō SHA имеет П1–П8; П8 вызывает
`TestExternalConsumerCanBuildTheModule`, чей один target import —
`github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/reference`. Это чтение
источников, не их новый прогон. Existing `assert-pin-reachable.sh` спрашивает
исторический service/platform pin и durable main/tags, что уже иное, чем
будущий product-tree census. Снятие этих old contracts не предложено.

Whole foundation exporter с нулём eligible files — **переданное root
измерение текущего main**, здесь не повторялось. Из него следует только
отсутствие зависимости ready-tree producer от exporter, не доказательство
неработоспособности любого другого сборщика.

Числа этого раздела перестают характеризовать кандидат при смене SHA.
Будущий mutation gate получает новые census сам; эти строки разрешение на
выпуск не дают. Точные issue snapshots сохранены отдельно автором исследования;
публичные основания — issue и owner comment links acceptance/design.

## Что следует принять отдельно

Схема ownership не выводится из отсутствия файлов в exporter. Для первого
использования root собирает receiving declaration из actual corelib main и
передаёт независимому reviewer полный manifest. Все `.github` paths обязательны;
прочие receiving-owned paths назначаются явно. Default Kachō П9 использует proposed committed reference-consumer program из нынешнего П8 witness; actual downstream из Kaname не выдумывается. Номер новой версии и точный
NP/CI-DT payload определяются после соответствующих независимых GREEN.
Версия `v1.9.0` здесь baseline наблюдения, а не предложение переиздать её.

Независимый tester получает заказы по всем E1–E12 и 22 acceptance IDs. Ни
один заказ не объявляется существующим тестом. Post-diff reviewers отдельно
сверяют Go/style, распределённый протокол записи, CI caller, archive provenance
и scope. Миграции БД не предполагаются; окончательное N/A допустимо лишь по
actual diff и policy predicate, не по намерению этого файла.
