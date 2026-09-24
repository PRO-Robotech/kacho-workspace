---
name: rule-00-kacho-core
description: "Kachō — ядро: продукт, naming, non-negotiables"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/00-kacho-core.md`

# Kachō — ядро: продукт, naming, non-negotiables

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
ban03-no-orm · только sqlc + рукописный pgx · ЗАВЕСТИ ban03-no-orm · red: ORM в go.mod
ban04-no-cross-service-cascade · только same-DB FK cascade · ЗАВЕСТИ ban04-no-cross-service-cascade · red: каскад через границу сервиса
ban05-no-edit-applied-migration · не правится, только новая · TestNewMigrationOutranksEveryAppliedOne · red: диф в применённом файле
ban06-internal-not-external · не публикуется на external endpoint, только :9091 · TestGRPCMountParity_EveryDeclaredServiceIsMounted · red: Internal-метод в public mux
ban07-no-broker · не заводится, пока справляется in-process · — (КАНДИДАТ НА ГЕЙТ: запрет kafka/nats в go.mod и чартах) · red: Kafka/NATS в go.mod или чарте
ban08-db-per-service · database-per-service · ЗАВЕСТИ ban08-db-per-service · red: два сервиса на одной базе
ban09-mutations-return-operation · возвращает Operation, не ресурс синхронно · TestSLP_OperationsLaneProducersAreCountedFromTheTree · red: sync-ответ ресурсом на Create
ban10-db-level-invariants · within-service — на DB-уровне: FK/UNIQUE/EXCLUDE/CHECK/CAS · — (КАНДИДАТ НА ГЕЙТ: check-then-act без CAS) · red: software check-then-act
ban11-no-deferral · ни одного в не-тестовом дереве, исключений нет · TestNoDeferredWorkInTheTree · red: TODO:/TODO(тикет): в коде, чарте, контракте
ban11-three-outcomes · исходов три: сделать сейчас · снять вместе с подпираемым кодом · завести предмет с причиной и предикатом снятия · TestLatentMarkerCarriesAReason · red: маркер без ответственного
ban12-tdd · падающий тест ДО кода, тесты в том же PR · ЗАВЕСТИ ban12-tdd · red: прод-правка без пробы
ban13-test-only-pr · не трогает прод-код, без TODO/SKIP/FIXME · TestNoDeferredWorkInTheTree · red: правка сервиса в тестовом PR
ban14-production-grade · сразу production-форма: error-handling, authz, DB-инварианты, observability, тесты; урезание — только под-фазой, production-complete в своих границах · — (КАНДИДАТ НА ГЕЙТ: stub/skeleton-признаки) · red: stub, «happy-path пока», «authz позже»
ban15-id-addressing · только immutable `id`; операции смены id нет; `name` — косметический project-scoped label и в URL не попадает · TestPublishedResourceIdIsGuardedByOperationOutcome · red: name или слаг в URL, pull-пути, гранте, cross-service ссылке
ban16-production-posture · production-posture: authMode=production + mTLS + sslmode=require + RS256 · TestClientTruthDeployAuthModeOneAddress · red: anonymous/HS256/plaintext на поднятом кластере
ban16-boot-guard · несёт production boot-guard Config.Validate() fail-closed refuse-to-start · TestBootGuardPresence · red: AuthMode declared-never-read
ban16-values-prod · реально boots: helm install + rollout ready · — (КАНДИДАТ НА ГЕЙТ: helm install + rollout в production-посадке) · red: зелёный `helm template` вместо подъёма
ban16-iam-facade · только через iam: JWKS :9097, /iam/token · — (КАНДИДАТ НА ГЕЙТ: прямой dial :4444 / /admin/clients) · red: прямой dial :4444 или /admin/clients
ban17-latin-identifiers · только латиница (функция, тип, поле, переменная, параметр, константа, импорт); комментарии и тексты — любой язык · TestIdentifiersAreASCII, console-ascii-identifiers.test.ts · red: кириллическая `В` в имени пробы
ban17-gates · судит узел-идентификатор, печатает объём осмотренного, падает на пустом обходе, рядом проба предпосылки · TestIdentifiersAreASCII · red: поиск по образцу вместо разбора
ban17-edit-by-ast · по позициям из разбора, не текстовой заменой · ЗАВЕСТИ ban17-edit-by-ast · red: замена попала внутрь строки
ban17-ci-job-keys · только латиница · гейт разобранного YAML · red: кириллический ключ: заданий ноль, вместо имени — путь к файлу
ban18-holder · отчёт существует, четыре раздела по направлениям, каждый называет координату прогона · ЗАВЕСТИ ban18-holder · red: раздел без координаты
ban19-fast-not-skip · не смягчает ни один запрет; ускорение берётся из устройства работы · ЗАВЕСТИ ban19-fast-not-skip · red: «сделаем проще, потом допилим»
ban19-block-criterion · блокирует только угроза корректному решению задачи (полное, по приёмке, production-grade) или безопасности, включая текст, вводящий в заблуждение о поведении, от которого они зависят; частные случаи — запрет ядра, маска, пропуск, ослабление проверки, с безопасностью блокируют и вне предмета; процессный артефакт (запись, пакет, форма) — лишь если без него они не доказаны; прочее — улучшение: задача с приоритетом, не возврат и не круг, объём держит диспетчер; иное основание блокировки уступает (решение владельца 2026-09-22) · вниманием рецензентов и приёмщиков · red: ⛔ по основанию, не влияющему на корректность или безопасность
ban19-review-round-one · все блокирующие — в первом круге; круг N+1 судит лишь дельту и закрытие круга N, новое на нетронутом — задача строкой «нужен следующий: git-operator», не ⛔, если не блокирует по ban19-block-criterion · вниманием рецензента · red: ⛔ круга N+1 по строке, не тронутой с круга N, вне ban19-block-criterion
ban19-review-subject-only · блокируй с предикатом и координатой только предмет изменения с его обязательными следствиями вне диффа (импортёры переноса, потребители снятого) и блокирующее вне предмета по ban19-block-criterion · вниманием рецензента; ⛔ без предиката диспетчер круга не открывает · red: ⛔ вне предмета либо без команды и файл:строки
ban19-review-rounds-in-process · круги «исполнитель → ревью → доработка» — внутри одного процесса диспетчера (`Workflow`), до трёх: отбор делает шаг процесса между рецензентом и исполнителем: ⛔ с предикатом и координатой — исполнителю дословно, ⛔ без предиката — рецензенту за предикатом, неблокирующее по ban19-block-criterion — задачей-находкой, не кругом; диспетчеру — итог или тупик; третий круг одного рода — смена формы задания (решение владельца 2026-09-24) · процесс `Workflow` диспетчера (шаг отбора) · red: замечание пересказано диспетчером; исполнителю ушло ⛔ без предиката либо неблокирующее; четвёртый круг
ban19-number-two-predicates · число о дереве — двумя предикатами, по написанию и по предмету, с выводом обоих · вниманием автора; `check-verifier` и `landing-reviewer` возвращают число без второго вывода · red: число одного grep разошлось с предметом
ban19-verdict-after-last-edit · вердикт прибора — прогоном после последней правки · вниманием автора · red: «поправил» сдано раньше такого прогона
ban20-copy-ban · в дереве не лежит: либо ребро пином, либо файла нет · scripts/crossrepo-gate (воркспейс) · red: одноимённый отслеживаемый путь в двух стволах
ban20-match-proves · нарушение не смягчает, а доказывает · scripts/crossrepo-gate · red: «расхождение ноль, значит терпимо»
ban20-atomic-move · все импортёры одним изменением · паника регистрации дескрипторов (свойство protobuf) · red: «пока оставим оба пути»
ban20-gate · решение на каждую пару, словарь закрыт: vendored · own · debt с задачей · scripts/crossrepo-gate · red: пара без записи или запись без пары
