---
name: rule-polyrepo
description: "Топология репозиториев, зависимости, порядок работы"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/polyrepo.md`

# Топология репозиториев, зависимости, порядок работы

## Топология — ТРИ репозитория (перемер 2026-09-13)

### Раскладка `kacho` (каталог ↔ прежний репозиторий)

poly-generated-stubs · сгенерированные стабы руками не правятся · buf generate в CI · red: диф в pkg/api вне регенерации
poly-proto-single-home · только `proto/` репозитория kacho; каталоги сервисов .proto не содержат · TestVocabularyJudgeCatchesACatalogModuleWithNoProtoDirectory · red: .proto в services/
poly-buf-single-lint · один на всё дерево · .github/workflows/ci.yaml · red: второй buf.yaml

## Build-граф — три модуля, рёбра ПИНАМИ, `replace` ЗАПРЕЩЁН

poly-build-graph-pins · ровно три, пином: kacho→corelib, kaname→corelib, kacho→kaname; corelib — лист; кольца запрещены · TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: обратное ребро или импорт вместо пина
poly-green-without-subject · различает «предмета нет» и «предмет чист» · TestCrossModuleJudgeRefusesAnEmptyWalkInsteadOfReportingNoFindings · red: пустой обход как успех

### Копия между репозиториями ЗАПРЕЩЕНА — берут пином, а не копируют (решение владельца 2026-09-13)

poly-copy-ban · файл с чужим владельцем в дереве не лежит; нужен предмет — ребро пином, не нужен — файла нет · scripts/crossrepo-gate · red: путь без объявленного ребра
poly-copy-sign-file · признак нарушения механический, про ФАЙЛ, а не про импорт · scripts/crossrepo-gate · red: одноимённый путь с совпадающим содержимым в двух стволах
poly-copy-trunk-predicate · судит СТВОЛ `ls-tree origin/main`, не рабочую копию · scripts/crossrepo-gate · red: замер по ls-files
poly-copy-atomic · переезд атомарен by construction: старый и новый путь контракта одновременно — паника регистрации дескрипторов · ЗАВЕСТИ poly-copy-atomic · red: старый и новый путь слинкованы одновременно
poly-copy-lawful-forms · сгенерированное из своего контракта · фикстура внутри пробы · историческая записка · kacho-workspace:scripts/crossrepo-gate/ · red: послабление вне трёх форм
poly-copy-gate · гейт копии обходит три ствола, требует пары в ведомости `docs/crossrepo-pairs.yaml` · scripts/crossrepo-gate · red: путь с парой без записи в ведомости
poly-copy-gate-home · дом гейта — воркспейс: пара — свойство двух деревьев, каждое по себе исправно · scripts/crossrepo-gate · red: проверка одного дерева без второго клона
poly-copy-decisions-three · словарь закрыт: vendored · own · debt, и debt обязан называть задачу · scripts/crossrepo-gate · red: debt без задачи
poly-copy-ledger-expires · истекает в обе стороны; `own` на побайтово совпадающей паре — находка · scripts/crossrepo-gate · red: запись без пары

### `replace` на внутренний модуль — НИ ОДНОГО, ни в одном `go.mod`

poly-replace-ban · ни одного replace github.com/PRO-Robotech/... · ! grep -rnE '^replace github.com/PRO-Robotech' project/*/go.mod · red: replace ../ ломает single-repo сборку образа
poly-gowork · через git-ignored go.work (шаблон go.work.example), бамп — GOWORK=off go get …@<sha> · TestCrossModuleWorkspaceGateCanFailAndCanStaySilent · red: правка go.mod ради локальной разработки
poly-replace-gate · CI-гейт грепом ловит replace на внутренний модуль; зелёный не свидетельство при отсутствии предмета · .github/workflows · red: зелёный без проверки наличия предмета
poly-dockerfile-no-replace · собирается versioned-модулями, go.mod без replace в любом варианте контекста · TestBuildContextGuard · red: COPY siblings с replace
poly-services-no-code-dep · не импортирует services/<b>/; общение только по API · TestCrossModuleJudgeCatchesTheServiceTakingThePlatform · red: импорт соседнего сервиса
poly-no-cycles · циклы build-графа запрещены · TestTargetModuleLayoutIsAcyclic · red: кольцо в графе модулей

## Runtime cross-domain edges (gRPC service→service; НЕ build-зависимость)

poly-jwks-fail-closed · JWKS только с iam :9097, fail-closed: нет пригодного ключа → 401, никогда allow · — (КАНДИДАТ НА ГЕЙТ: ветка allow при недоступном авторитете) · red: allow при недоступном iam
poly-jwks-issuer-selection · по объявленному издателю токена, у каждой записи свой путь; издатель без записи → отказ · ЗАВЕСТИ poly-jwks-issuer-selection · red: перебор записей или путь, выведенный из издателя
poly-jwks-revocation · читается на пути ПРЕДЪЯВЛЕНИЯ; недоступность авторитета — fail-closed · TestEdgeRevocationLaneHasAReaderOnTheRequestPath · red: отзыв действует только на выдаче
poly-internal-prefix · дискриминатор ban #6, во внешний маршрутизатор не попадает by construction; имя ребра пишется целиком · TestGRPCMountParity_EveryDeclaredServiceIsMounted · red: ребро названо без префикса
poly-subscription-pkg-noversion · corelib.subscription, без сегмента версии · TestSubscriptionFormIsDeclaredOnce · red: доменная версия в общей форме
poly-consumer-opens · соединение открывает ПОТРЕБИТЕЛЬ · TestSubscriptionServerIsSingularAndLivesInTheFoundation · red: толчок от владельца замыкает граф
poly-acyclicity-statement · объявляется вместе с доводом ацикличности · ЗАВЕСТИ poly-acyclicity-statement · red: ребро без утверждения о направлении
poly-owners-list-closed · пустое значение = «не объявлен» → 501, а не «все»; заводя такую ручку скажи, сужает она или разрешает · ЗАВЕСТИ poly-owners-list-closed · red: пустой перечень открывает поток всем доменам
poly-two-dictionaries · называет словарь (proto-пакет или каталог чарта) и сверяется с тем, который читает код · ЗАВЕСТИ poly-two-dictionaries · red: имя из чужого словаря → отказ старта края
poly-cycles-forbidden · A зовёт B ⇒ B не зовёт A; новое ребро фиксируется перечнем · TestTargetModuleLayoutIsAcyclic · red: обратный вызов владельца к потребителю

## Порядок работы для кросс-доменной фичи (топосортировка графа)

poly-verdict-one-recognizer · читается одним распознавателем `scripts/docs-gate/_lib.py:verdict` в обоих домах · check-01 и check-04 · red: APPROVED, которого никто не читает
