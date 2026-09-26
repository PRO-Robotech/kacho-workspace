---
name: rule-00-kacho-core
description: "Kachō — ядро: продукт, naming, non-negotiables"
---

**Архив:** `.claude/backup/00-kacho-core.md`

## Что это за продукт

core-kaname-separate · Kaname — отдельный продукт, не домен платформы; граф `corelib←kaname←kacho`, кольца запрещены · TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: чужое ребро или кольцо в графе модулей
core-own-conventions · API — в терминах конвенций Kachō, без сравнений с чужими облаками · TestForeignProductInjection* · red: сравнение «как у чужого» в тексте

## Naming convention (обязательно)

naming-ascii-id · ASCII kacho · TestIdentifiersAreASCII · red: Kachō или кириллица в идентификаторе
naming-proto-pkg · kacho.cloud.<domain>.v1 · buf lint + TestProtoPrefixInjection_WrongPrefixIsFound · red: пакет без домена или без версии
naming-pg · kacho_<domain> · TestVpcSchemaGateFindsANamingRuleItDoesNotCover · red: дефис или чужой префикс в схеме
naming-env · KACHO_<DOMAIN>_<NAME> · TestDeclaredKnobHasAReader · red: ручка вне формы имени
naming-json-camel · camelCase: <resource>Id, projectId, createdAt · TestClientTruthRequestBodyKeysExistInTheRequestMessage · red: snake_case в теле края

## Non-negotiables (детали — в соответствующих rule-модулях)

ban01-acceptance · не пишется без APPROVED acceptance Given-When-Then · acceptance-reviewer, TestNewMigrationCitesAnApprovedAcceptance · red: коммит без приёмки
ban02-no-foreign-clouds · ни одного упоминания в коде/доках/env/именах · TestForeignProductInjection_ForeignNameIsFoundWithItsCoordinate · red: yandex/aws в дереве
ban03-no-orm · только sqlc + рукописный pgx · ЗАВЕСТИ · red: ORM в go.mod
ban04-no-cross-service-cascade · только same-DB FK cascade · ЗАВЕСТИ · red: каскад через границу сервиса
ban05-no-edit-applied-migration · не правится, только новая · TestNewMigrationOutranksEveryAppliedOne · red: диф в применённом файле
ban06-internal-not-external · не публикуется на external endpoint, только :9091 · TestGRPCMountParity_EveryDeclaredServiceIsMounted · red: Internal-метод в public mux
ban07-no-broker · не заводится, пока справляется in-process · — (КАНДИДАТ НА ГЕЙТ: запрет kafka/nats в go.mod и чартах) · red: Kafka/NATS в go.mod или чарте
ban08-db-per-service · database-per-service · ЗАВЕСТИ · red: два сервиса на одной базе
ban09-mutations-return-operation · возвращает Operation, не ресурс синхронно · TestSLP_OperationsLaneProducersAreCountedFromTheTree · red: sync-ответ ресурсом на Create
ban10-db-level-invariants · within-service — на DB-уровне: FK/UNIQUE/EXCLUDE/CHECK/CAS · — (КАНДИДАТ НА ГЕЙТ: check-then-act без CAS) · red: software check-then-act
ban11-no-deferral · ни одного в не-тестовом дереве, исключений нет · TestNoDeferredWorkInTheTree · red: TODO:/TODO(тикет): в коде, чарте, контракте
ban11-three-outcomes · исходов три: сделать сейчас · снять вместе с подпираемым кодом · завести предмет с причиной и предикатом снятия · TestLatentMarkerCarriesAReason · red: маркер без ответственного
ban12-tdd · падающий тест ДО кода, тесты в том же PR · ЗАВЕСТИ · red: прод-правка без пробы
ban12-second-echelon · сквозные пробы края (newman) — второй эшелон, обязателен ОТДЕЛЬНО: unit/integration судят собранное, а не развёрнутое · контекст «сводный вердикт (все шарды)», `PRO-Robotech/kacho:.github/scripts/assert-required-contexts-match-jobs.py` · red: готовность к посадке по зелёному первому эшелону
ban13-test-only-pr · не трогает прод-код, без TODO/SKIP/FIXME · TestNoDeferredWorkInTheTree · red: правка сервиса в тестовом PR
ban14-production-grade · сразу production-форма: error-handling, authz, DB-инварианты, observability, тесты; урезание — только под-фазой, production-complete в своих границах · — (КАНДИДАТ НА ГЕЙТ: stub/skeleton-признаки) · red: stub, «happy-path пока», «authz позже»
ban15-id-addressing · только immutable `id`; операции смены id нет; `name` — косметический project-scoped label и в URL не попадает · TestPublishedResourceIdIsGuardedByOperationOutcome · red: name или слаг в URL, pull-пути, гранте, cross-service ссылке
ban16-production-posture · production-posture: authMode=production + mTLS + sslmode=require + RS256 · TestClientTruthDeployAuthModeOneAddress · red: anonymous/HS256/plaintext на поднятом кластере
ban16-boot-guard · несёт production boot-guard Config.Validate() fail-closed refuse-to-start · TestBootGuardPresence · red: AuthMode declared-never-read
ban16-values-prod · реально boots: helm install + rollout ready · — (КАНДИДАТ НА ГЕЙТ: helm install + rollout в production-посадке) · red: зелёный `helm template` вместо подъёма
ban16-iam-facade · только через iam: JWKS :9097, /iam/token · — (КАНДИДАТ НА ГЕЙТ: прямой dial :4444 / /admin/clients) · red: прямой dial :4444 или /admin/clients
ban17-latin-identifiers · только латиница (функция, тип, поле, переменная, параметр, константа, импорт); проза комментария — по-русски (ban #22), текст наружу — контракт `api-error-tone`; «любой язык» отозвано 2026-09-21 · TestIdentifiersAreASCII, console-ascii-identifiers.test.ts · red: кириллическая `В` в имени пробы
ban17-gates · судит узел-идентификатор, печатает объём осмотренного, падает при НУЛЕ прочитанных файлов; предпосылку ОБХОДА (прочитано дерево продукта) не проверяет никто · TestIdentifiersAreASCII; разбор — corelib/treehygiene/identifiers_test.go · red: поиск по образцу вместо разбора; зелёное на дереве из одного файла
ban17-gates-walkjudge · редакцию ban17-gates с судьёй обхода вписать, когда починка сядет в дерево продукта, не раньше · ЗАВЕСТИ — предикат: git -C project/kacho grep -c 'func TestEveryTreeGateAsksTheWalkJudge' больше нуля · red: редакция с судьёй обхода в правиле, пробы в продукте нет
ban17-edit-by-ast · по позициям из разбора, не текстовой заменой · ЗАВЕСТИ · red: замена попала внутрь строки
ban17-ci-job-keys · только латиница · гейт разобранного YAML · red: кириллический ключ: заданий ноль, вместо имени — путь к файлу
ban18-criteria · всякое решение проходит критерии продукта, названные владельцем 2026-09-20 дословно: «Требования к продукту - максимальная производительность, безопасность, иновационность, узнаваемость относительно рынка, перспективность». «Нет» на любом одном — ОТКАЗ, а не повод к обсуждению; снимается переделкой объёма (ban18-decides-dispatcher) · вниманием · red: решение внесено, критерии не названы; «нет» переведено в обсуждение
ban18-q-perf · максимальная производительность — отвергается, когда цена решения не названа числом с единицей счёта и посадкой замера · вниманием · red: «быстро» без замера; число без единицы
ban18-q-security · безопасность — отвергается, когда решение расширяет поверхность, не назвав расширения в приёмке, профиле или модели (`security.md`) · вниманием · red: расширение поверхности не названо
ban18-q-innovation · иновационность (слово владельца) — отвергается, когда единственный довод «так уже делают» и нового свойства продукта решение не даёт · вниманием · red: довод только «так принято»
ban18-q-market-recognition · узнаваемость относительно рынка — проверяемый признак: решение называет, чему у конкурентов соответствует имя ресурса или метода, либо объявляет «аналога нет» и почему наш вариант лучше; «как у соседнего продукта» доводом не является (ban #2) · вниманием · red: имя введено без соответствия и без объявления «аналога нет»
ban18-q-prospect · перспективность — отвергается, когда ошибка решения необратима: отзыв ломает внешне адресуемую координату (ban #15) либо требует миграции данных арендатора · вниманием · red: шаг необратим
ban18-q-product-kept · благо продукта (вопрос 2026-08-24, словами 2026-09-20 не покрыт) — отвергается, когда единственный выигрыш «меньше работы сейчас» у исполнителя, обзора или проверки · вниманием · red: выигрыш только «меньше работы сейчас»
ban18-q-production-kept · производственность (вопрос 2026-08-24; производительность — скорость, производственность — боевая форма) — отвергается, когда у решения есть режим, годный только для стенда, либо часть «на потом» (ban #11, #14, #16) · вниманием · red: режим годен только для стенда
ban18-decides-dispatcher · решение по критериям принимает ДИСПЕТЧЕР сам (решение владельца 2026-09-20 «Все решения принимаешь сам меня не спрашиваешь»); владельцу — только три пункта базы диспетчера §11 · вниманием · red: «это решение владельца» сказано о том, что решает диспетчер
ban18-no-human-block · препятствие исходом НЕ является: встретив отказ, ищут обход, перебирая более безопасные способы (решение владельца 2026-09-20 дословно: «решения принимаешь ты на человеке не блокируемся»); «жду человека» — не исход · tooling-gate check-11 (якорь цитаты) · red: препятствие названо исходом; полоса стоит на человеке
ban18-three-outcomes-at-obstacle · исходов при препятствии три: обход применён · предмет переформулирован в обход препятствия · недостижимость ДОКАЗАНА перебором — что требуется, число попыток и ДОСЛОВНЫЙ отказ каждой · вниманием · red: одна попытка названа недостижимостью; отказ пересказан, а не процитирован
ban18-workaround-is-not-a-breach · обход ищется СРЕДИ безопасных способов, а не вместо безопасности: способ, отклонённый средой по безопасности (закрепление без нужды, учётные данные в аргументах и выводе, обход защиты ствола), обходом не считается и не повторяется · вниманием · red: отклонённый способ повторён; «обход» прочитан как разрешение обходить защиту
ban18-holder · отчёт существует, четыре раздела по направлениям, каждый называет координату прогона · ЗАВЕСТИ · red: раздел без координаты
ban19-fast-not-skip · не смягчает ни один запрет; ускорение берётся из устройства работы · ЗАВЕСТИ · red: «сделаем проще, потом допилим»
ban19-block-criterion · блокирует только угроза корректному решению задачи (полное, по приёмке, production-grade) или безопасности, включая текст, вводящий в заблуждение о поведении, от которого они зависят; запрет ядра, маска, пропуск, ослабление проверки и угроза безопасности блокируют и вне предмета; процессный артефакт — лишь если без него они не доказаны; прочее — улучшение: задача с приоритетом, не возврат и не круг; иное основание уступает (решение владельца 2026-09-22) · вниманием рецензентов и приёмщиков · red: ⛔ по основанию, не влияющему на корректность или безопасность
ban19-review-round-one · все блокирующие — в первом круге; круг N+1 судит лишь дельту и закрытие круга N, новое на нетронутом — задача «нужен следующий: git-operator», не ⛔, если не блокирует по ban19-block-criterion · вниманием рецензента · red: ⛔ круга N+1 по строке, не тронутой с круга N
ban19-review-subject-only · блокируй с предикатом и координатой только предмет изменения с обязательными следствиями вне диффа (импортёры переноса, потребители снятого) и блокирующее вне предмета по ban19-block-criterion · вниманием рецензента · red: ⛔ вне предмета либо без команды и файл:строки
ban19-review-rounds-in-process · круги «исполнитель → ревью → доработка» — на сборке, их два (`git-issues.md#gi-asm-one-round`); отбор — шаг процесса диспетчера: ⛔ с предикатом и координатой — исполнителю дословно, без предиката — рецензенту за предикатом, неблокирующее — задачей-находкой; диспетчеру — итог или тупик (решение владельца 2026-09-24) · шаг отбора процесса `Workflow` · red: замечание пересказано диспетчером; круг на задаче вне сборки; третий круг
ban19-number-two-predicates · число о дереве — двумя предикатами, по написанию и по предмету, с выводом обоих · вниманием автора; `check-verifier` и `landing-reviewer` возвращают число без второго · red: число одного grep разошлось с предметом
ban19-verdict-after-last-edit · вердикт прибора — прогоном после последней правки · вниманием автора · red: «поправил» сдано раньше такого прогона
ban20-copy-ban · в дереве не лежит: либо ребро пином, либо файла нет · scripts/crossrepo-gate (воркспейс) · red: одноимённый отслеживаемый путь в двух стволах
ban20-match-proves · нарушение не смягчает, а доказывает · scripts/crossrepo-gate · red: «расхождение ноль, значит терпимо»
ban20-atomic-move · все импортёры одним изменением · паника регистрации дескрипторов (свойство protobuf) · red: «пока оставим оба пути»
ban20-gate · решение на каждую пару, словарь закрыт: vendored · own · debt с задачей · scripts/crossrepo-gate · red: пара без записи или запись без пары
ban20-scope-is-our-trunks · предмет ban #20 — одноимённый путь в ДВУХ НАШИХ стволах (kacho · kaname · corelib), и только он; чужое поддерево судится ban #21 (`polyrepo.md#poly-copy-scope-our-trunks`) · scripts/crossrepo-gate/check-01-paired-files-are-declared.py · red: ban #20 назван запретом ввоза чужого кода
ban21-foreign-code-as-subtree · чужой код — ПОДДЕРЕВОМ в фундамент вместе с набором проб апстрима, не зависимостью (решение владельца 2026-09-20); канон формы — `polyrepo.md` §«Внесение ЧУЖОГО (стороннего) кода» · ЗАВЕСТИ; ввезённых поддеревьев ноль — вниманием `system-design-reviewer` · red: чужая библиотека в go.mod там, где нужен её КОД
ban21-why-not-a-dependency · зависимостью пробы не приезжают (`polyrepo.md#poly-foreign-why`) · вниманием · red: довод «зависимостью короче» без ответа, откуда возьмутся пробы
ban21-upstream-suite-kept · набор проб апстрима сохраняй и прогоняй (`polyrepo.md#poly-foreign-suite-and-control`) · ЗАВЕСТИ · red: пробы апстрима выброшены при ввозе
ban21-control-run · прогон несёт КОНТРОЛЬ на неправленом апстриме (`polyrepo.md#poly-foreign-suite-and-control`) · ЗАВЕСТИ · red: один прогон вместо двух
ban21-provenance-machine-checkable · происхождение — машинно-читаемой записью с пином коммита (`polyrepo.md#poly-foreign-provenance`) · ЗАВЕСТИ · red: происхождение прозой; пин ветки или тега
ban21-maintenance-cost-in-numbers · цену сопровождения называй ЧИСЛОМ против измеренной частоты релизов (`polyrepo.md#poly-foreign-cost`) · вниманием · red: частота названа на память
ban21-no-vendorlock-strengthened · чужое API наружу не пробрасывай (`polyrepo.md#poly-foreign-no-lock`) · ЗАВЕСТИ · red: чужой тип в сигнатуре нашего пакета
ban22-comment-prose-ru · проза комментария в нашем Go — по-русски; требование владельца 2026-09-21 дословно: «комментарии только на русском. Существующие правки привести к виду» · scripts/comment-language-gate/check-01-comment-language-does-not-grow.py · red: строка комментария без кириллицы с двумя прозаическими латинскими словами ПОДРЯД
ban22-subject-is-go-today · предмет нормы — Go: замер сделан только по Go; `.ts`, `.py`, `.sh`, `.sql`, `.proto` и шаблоны чартов — отдельным изменением с отдельным замером, строки вне Go называются вслух · docs/comment-language.yaml, поле `predicate` и ревизии замера · red: «в нашем коде» без оговорки о языке
ban22-unit-is-the-line · единица нарушения — СТРОКА комментария, а не блок: кириллица блока английский текст не амнистирует · scripts/comment-language-gate/_core.py, `line_is_finding` · red: одна руна амнистировала блок
ban22-one-normalized-text · обе ступени решения читают ОДИН нормализованный текст: отброшенное как не-проза (URL, обратные кавычки) языка не свидетельствует · scripts/comment-language-gate/_core.py, `normalize` · red: плечо языка читает сырой текст, плечо прозы — очищенный
ban22-mixed-is-the-norm · смешанный комментарий — НОРМА: судится проза, латинский идентификатор в русской фразе прозой не является · scripts/comment-language-gate/inject.sh, ось C, обе стороны · red: гейт краснеет на русской фразе с латинским именем
ban22-two-words-adjacent · порог — два прозаических слова ПОДРЯД: перечень значений через разделитель прозой не является и не переводится · scripts/comment-language-gate/_core.py, `prose_run` · red: перечень значений объявлен прозой; одно слово названо изложением
ban22-prose-word-by-form · прозаическое слово определяй ФОРМОЙ токена, а не словарём английского; перечень форм — у прибора · scripts/comment-language-gate/_core.py, `is_prose_word` · red: заведён словарь английского; имя сущности засчитано языком
ban22-directive-token-latin · токен директивы (`//имя:` без пробела) — латиницей, обоснование после разделителя — по-русски; аргументы директивы прозой не являются, словаря инструментов нет · scripts/comment-language-gate/inject.sh, ось B · red: заведён словарь инструментов; амнистирован блок ради директивы
ban22-exclusions-closed · исключений ВОСЕМЬ (И1–И8), перечень закрыт, у каждого признак, вычисляемый командой; перечень с признаками — у прибора · scripts/comment-language-gate/_core.py вместе с inject.sh · red: девятое исключение; «и тому подобное»; исключение без исполнимого признака
ban22-exclusion-derived-not-written · признак исключения ВЫВОДИ обходом дерева, а не выписывай координатой · scripts/comment-language-gate/check-02-instrument-premise-holds.py, предпосылка 3 · red: в признаке исключения стоит выписанный путь поддерева
ban22-generated-is-not-the-address · порождённый файл не правится — адрес правки его `.proto` · scripts/comment-language-gate/inject.sh, ось E, обе стороны · red: правка комментария в `pkg/api`
ban22-generated-source-is-open-debt · ОТКРЫТЫЙ ДОЛГ: комментарий, который наш генератор пишет литералом, недостижим (И6 снимает исходник, И3 — адресата); снятие — обход литералов генераторов · ЗАВЕСТИ ban22-generated-source · red: «порождённое снято» о тексте нашего прод-кода
ban22-translation-may-trip-ban11 · перевод, называющий отложенную работу, краснит запрет #11; исход — `ban11-three-outcomes`, а не «оставить английским» · project/corelib/treehygiene/deferral.go вместе с TestNoDeferredWorkInTheTree · red: английская формулировка отсрочки оставлена ради молчания гейта
ban22-ratchet-not-a-sweep · «привести к виду» исполняется СОБЫТИЕМ: файл, в который изменение вносит строку, выходит из него без не-русской прозы; массовый проход запрещён · scripts/comment-language-gate/check-01-comment-language-does-not-grow.py, ведомость docs/comment-language.yaml · red: число в ведомости поднято вместо правки; перевод массовым проходом
ban22-outward-text-is-elsewhere · тексты НАРУЖУ этой нормой не затрагиваются: сообщение ошибки — контракт `api-error-tone`, перевод там — ломающее изменение · TestErrorMappersTailReturnsAFixedText, TestOperationLaneMessageIsAssertedVerbatim · red: норма о комментариях применена к тексту ошибки наружу
