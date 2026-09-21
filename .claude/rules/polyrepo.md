---
name: rule-polyrepo
description: "Топология репозиториев, зависимости, порядок работы"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/polyrepo.md`

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
poly-copy-scope-our-trunks · «чужой владелец» в этом разделе — ДРУГОЙ НАШ репозиторий (kacho · kaname · corelib), а не сторонний проект: гейт считает пары по `ls-tree` трёх НАШИХ клонов (`REPOS` — закрытый перечень), одиночное поддерево стороннего происхождения парой не становится и этим запретом не судится вовсе · scripts/crossrepo-gate/check-01-paired-files-are-declared.py · red: ввоз стороннего кода отклонён ссылкой на запрет копии; `vendored` прочитан как «вопрос ввоза решён»

### Внесение ЧУЖОГО (стороннего) кода — ПОДДЕРЕВО с его пробами, не зависимость (решение владельца 2026-09-20)

Другой предмет, чем раздел выше: тот про копию между НАШИМИ стволами, этот — про внос кода,
чей апстрим вне наших репозиториев. Слитые, они отменяют друг друга: запрет копии прочитался бы
как запрет ввоза, а ввоз — как послабление запрета копии.

poly-foreign-subtree-default · форма по умолчанию — поддерево в фундаменте (`corelib`) ВМЕСТЕ с набором проб апстрима; зависимость — исключение, и оно называет, откуда возьмутся пробы (решение владельца 2026-09-20 дословно: «Суть была не использовать либы и готовое от ори а взять готовые части и полирнуть через себя что бы 1) брать околопродовый код 2) взять тесты к коду что намного ценнее при разработке») · ЗАВЕСТИ poly-foreign-subtree-default: ввезённых поддеревьев в дереве сегодня НЕТ, предмета у гейта не существует · red: чужая библиотека в go.mod там, где нужен её код
poly-foreign-why · зависимостью пробы не приезжают — достаётся чёрный ящик; поддеревом приезжает околопродовый код, прогнанный на краевых случаях, и набор, который эти случаи описывает · вниманием · red: довод «так короче» без ответа про пробы
poly-foreign-suite-and-control · набор апстрима сохраняется и прогоняется, и прогон несёт КОНТРОЛЬ — тот же набор на неправленом дереве апстрима; расхождение контроля и правленого прогона и есть утверждение «поведение не изменилось» · ЗАВЕСТИ poly-foreign-suite-and-control · red: один прогон вместо двух; набор апстрима выброшен при ввозе
poly-foreign-provenance · пин апстримного КОММИТА, лицензия и уведомление лежат машинно-читаемой записью рядом с поддеревом · ЗАВЕСТИ poly-foreign-provenance · red: происхождение прозой в README; пин ветки или тега вместо коммита
poly-foreign-cost · цена сопровождения называется числом тронутых строк на обновление и сопоставляется с измеренной частотой релизов апстрима · вниманием · red: частота названа на память
poly-foreign-no-lock · чужое API не проброшено наружу ни одним типом и в граф сборки потребителя не приезжает: `go list -deps` потребителя чужого модуля не содержит · go list -deps ./... · red: чужой тип в сигнатуре нашего пакета
poly-foreign-not-a-pair · ввезённое поддерево не заводится во ВТОРОМ нашем стволе: там оно стало бы парой и попало бы под запрет копии — ребро пином на фундамент, как у любого своего · scripts/crossrepo-gate · red: одно и то же ввезённое поддерево в kacho и corelib

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
