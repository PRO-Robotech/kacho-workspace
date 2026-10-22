---
name: rule-polyrepo
description: "Топология репозиториев, зависимости, порядок работы"
---

**Архив:** `.claude/backup/polyrepo.md`

## Топология — ТРИ репозитория

### Раскладка `kacho` (каталог ↔ прежний репозиторий)

poly-generated-stubs · сгенерированные стабы руками не правятся · buf generate в CI · red: диф в pkg/api вне регенерации
poly-proto-single-home · только `proto/` репозитория kacho; каталоги сервисов .proto не содержат · TestVocabularyJudgeCatchesACatalogModuleWithNoProtoDirectory · red: .proto в services/
poly-buf-single-lint · один на всё дерево · .github/workflows/ci.yaml · red: второй buf.yaml

## Build-граф — три модуля, рёбра ПИНАМИ, `replace` ЗАПРЕЩЁН

poly-build-graph-pins · ровно три, пином: kacho→corelib, kaname→corelib, kacho→kaname; corelib — лист; кольца запрещены · TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: обратное ребро или импорт вместо пина
poly-green-without-subject · различает «предмета нет» и «предмет чист» · TestCrossModuleJudgeRefusesAnEmptyWalkInsteadOfReportingNoFindings · red: пустой обход как успех

### Копия между репозиториями ЗАПРЕЩЕНА — берут пином, а не копируют

poly-copy-ban · файла чужого владельца в дереве нет: нужен — ребро пином · scripts/crossrepo-gate · red: путь без объявленного ребра
poly-copy-sign-file · признак механический — ФАЙЛ, не импорт · scripts/crossrepo-gate · red: одноимённый путь с совпадающим содержимым в двух стволах
poly-copy-trunk-predicate · судит СТВОЛ `ls-tree origin/main`, не рабочую копию · scripts/crossrepo-gate · red: замер по ls-files
poly-copy-atomic · переезд атомарен: два пути контракта разом — паника регистрации дескрипторов · ЗАВЕСТИ · red: оба пути слинкованы
poly-copy-lawful-forms · сгенерированное из своего контракта, фикстура внутри пробы, историческая записка · scripts/crossrepo-gate · red: послабление вне трёх форм
poly-copy-gate · обходит три ствола, пара — строкой ведомости `docs/crossrepo-pairs.yaml` · scripts/crossrepo-gate · red: путь с парой без записи в ведомости
poly-copy-gate-home · дом гейта — воркспейс: пара — свойство двух деревьев · scripts/crossrepo-gate · red: проверка одного дерева без второго клона
poly-copy-decisions-three · словарь закрыт: vendored, own, debt с задачей · scripts/crossrepo-gate · red: debt без задачи
poly-copy-ledger-expires · истекает в обе стороны; `own` на побайтово совпадающей паре — находка · scripts/crossrepo-gate · red: запись без пары
poly-copy-scope-our-trunks · «чужой владелец» — ДРУГОЙ НАШ репозиторий (kacho, kaname, corelib); стороннее поддерево запретом не судится · crossrepo-gate check-01 · red: ввоз стороннего кода отклонён ссылкой на запрет копии

### Внесение ЧУЖОГО (стороннего) кода — ПОДДЕРЕВО с его пробами, не зависимость

Предмет — код с апстримом вне наших репозиториев.

poly-foreign-subtree-default · по умолчанию — поддерево в `corelib` ВМЕСТЕ с пробами апстрима; зависимость — исключение, называющее, откуда пробы (владелец 2026-09-20, архив) · ЗАВЕСТИ · red: чужая библиотека в go.mod
poly-foreign-why · зависимость — чёрный ящик без проб; поддерево — код с краевыми пробами апстрима · вниманием · red: довод «так короче» без ответа про пробы
poly-foreign-suite-and-control · набор апстрима сохраняй и гоняй с КОНТРОЛЕМ — им же на неправленом апстриме: исходы совпали = поведение не изменилось · ЗАВЕСТИ · red: один прогон вместо двух; набор апстрима выброшен при ввозе
poly-foreign-provenance · пин апстримного КОММИТА, лицензия и уведомление — машинно-читаемой записью рядом с поддеревом · ЗАВЕСТИ · red: происхождение прозой в README; пин ветки или тега вместо коммита
poly-foreign-cost · цена — тронутые строки на обновление против измеренной частоты релизов апстрима · вниманием · red: частота названа на память
poly-foreign-no-lock · чужой тип наружу не проброшен: `go list -deps` потребителя чужого модуля не содержит · go list -deps ./... · red: чужой тип в сигнатуре нашего пакета
poly-foreign-not-a-pair · ввезённое поддерево — в одном стволе, прочим — пином на фундамент (иначе пара под запретом копии) · scripts/crossrepo-gate · red: одно ввезённое поддерево в kacho и corelib

### `replace` на внутренний модуль — НИ ОДНОГО, ни в одном `go.mod`

poly-replace-ban · ни одного replace github.com/PRO-Robotech/... · ! grep -rnE '^replace github.com/PRO-Robotech' project/*/go.mod · red: replace ../ ломает single-repo сборку образа
poly-gowork · через git-ignored go.work (шаблон go.work.example), бамп — GOWORK=off go get …@<sha> · TestCrossModuleWorkspaceGateCanFailAndCanStaySilent · red: правка go.mod ради локальной разработки
poly-replace-gate · CI-гейт грепом ловит replace на внутренний модуль; зелёный без предмета — не свидетельство · .github/workflows · red: зелёный на пустом предмете
poly-dockerfile-no-replace · собирается versioned-модулями, без replace в любом контексте · TestBuildContextGuard · red: COPY siblings с replace
poly-services-no-code-dep · не импортирует services/<b>/; общение только по API · TestCrossModuleJudgeCatchesTheServiceTakingThePlatform · red: импорт соседнего сервиса
poly-no-cycles · циклы build-графа запрещены · TestTargetModuleLayoutIsAcyclic · red: кольцо в графе модулей

## Runtime cross-domain edges (gRPC service→service; НЕ build-зависимость)

poly-jwks-fail-closed · JWKS только с iam :9097, fail-closed: нет пригодного ключа → 401, никогда allow · — (КАНДИДАТ НА ГЕЙТ: ветка allow при недоступном авторитете) · red: allow при недоступном iam
poly-jwks-issuer-selection · по объявленному издателю токена, у каждой записи свой путь; издатель без записи → отказ · ЗАВЕСТИ · red: перебор записей или путь, выведенный из издателя
poly-jwks-revocation · читается на пути ПРЕДЪЯВЛЕНИЯ; недоступность авторитета — fail-closed · TestEdgeRevocationLaneHasAReaderOnTheRequestPath · red: отзыв действует только на выдаче
poly-internal-prefix · дискриминатор ban #6: во внешний маршрутизатор не попадает; имя ребра — целиком · TestGRPCMountParity_EveryDeclaredServiceIsMounted · red: ребро названо без префикса
poly-subscription-pkg-noversion · corelib.subscription, без сегмента версии · TestSubscriptionFormIsDeclaredOnce · red: доменная версия в общей форме
poly-consumer-opens · соединение открывает ПОТРЕБИТЕЛЬ · TestSubscriptionServerIsSingularAndLivesInTheFoundation · red: толчок от владельца замыкает граф
poly-acyclicity-statement · объявляется вместе с доводом ацикличности · ЗАВЕСТИ · red: ребро без утверждения о направлении
poly-owners-list-closed · пустое значение = «не объявлен» → 501, а не «все»; новая ручка называет, сужает она или разрешает · ЗАВЕСТИ · red: пустой перечень открывает поток всем доменам
poly-two-dictionaries · называет словарь (proto-пакет или каталог чарта), сверенный с читаемым кодом · ЗАВЕСТИ · red: имя из чужого словаря → отказ старта края
poly-cycles-forbidden · A зовёт B ⇒ B не зовёт A (runtime-ребро; build-граф — poly-no-cycles); новое ребро — перечнем · TestTargetModuleLayoutIsAcyclic · red: обратный вызов владельца к потребителю
poly-external-operators · внешние операторы (registry-operator, kaname-iam-operator, vault-operator) — наши стволы их не зовут; kaname — по REST `/iam/v1` (gRPC требует клиентский лист): iam-proxy registry-operator — `POST /iam/v1/authorize:check` токеном клиента о нём же, kaname-iam-operator — `/iam/v1/token` · вниманием; `git grep -lE '(registry|kaname-iam|vault)-operator' origin/main` в kacho, kaname, corelib = 0 · red: ствол зовёт оператора; прокси спрашивает о чужом субъекте

## Порядок работы для кросс-доменной фичи (топосортировка графа)

poly-verdict-one-recognizer · читается одним распознавателем `scripts/docs-gate/_lib.py:verdict` в обоих домах · check-01 и check-04 · red: APPROVED, которого никто не читает
