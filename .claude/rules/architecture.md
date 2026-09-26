---
name: rule-architecture
description: "Чистая архитектура + переиспользование"
---

**Архив:** `.claude/backup/architecture.md`

## Clean Architecture (строгое dependency rule)

arch-dependency-diagram · handler/repo/clients → use-case → domain, обратных рёбер нет · go list -deps по слою · red: импорт transport из use-case
arch-domain-pure · только stdlib + kacho-proto · go list -deps ./internal/domain/... без pgx/grpc/internal · red: pgx/grpc/sqlc-тип в domain
arch-usecase-ports · объявляет порты <Res>Repo/<Peer>Client, импортирует domain · нет импорта internal/handler · red: transport-тип в сигнатуре use-case
arch-repo-adapter · реализует порты, импортирует pgx+domain · ЗАВЕСТИ · red: repo объявляет свой порт
arch-clients-adapter · реализует порты, импортирует grpc-стабы+domain · ЗАВЕСТИ · red: бизнес-решение в clients
arch-handler-thin · parse → use-case → format · ЗАВЕСТИ · red: ветка бизнес-логики или SQL в handler
arch-wiring-cmd-only · только cmd/<svc>/main.go · TestCompositionRootsCarryNoServerConstructionOfTheirOwn · red: конструктор зависимостей вне cmd/
arch-identity-carrier · несётся нейтральным типом, не transport-типом · grep импорта internal/handler в use-case · red: use-case читает identity из transport
arch-ban-infra-in-domain · не импортируют pgx/grpc-stubs/sqlc-types · go list -deps · red: инфра-тип в чистом слое
arch-ban-biz-in-handler · без бизнес-логики · ЗАВЕСТИ · red: условие домена в transport
arch-ban-global-singleton · никаких var globalPool и init()-сайд-эффектов вне cmd/ · ЗАВЕСТИ · red: пакетный пул или init() в сервисе
arch-tests-by-layer · use-case — mock-порты, integration — testcontainers, e2e — api-gateway · TestPerTestContainerJudgeFiresAndStaysSilent · red: integration подменяет unit
arch-postgres-in-service-test · не требует Postgres · ЗАВЕСТИ · red: use-case-тест поднимает БД = утечка adapter

## Переиспользование: фундамент в `corelib`, своё — в `pkg/` платформы

arch-corelib-horizontal · нужен двум продуктам → PRO-Robotech/corelib пином версии · TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: вторая копия per-service
arch-new-util-ownership · спроси чей предмет: двум → corelib, одному → pkg/, домену → каталог сервиса · ЗАВЕСТИ · red: доменная логика в pkg/
arch-foreign-code-subtree · ЧУЖОЙ код — поддеревом в фундамент с пробами апстрима (`polyrepo.md#poly-foreign-subtree-default`); пин в `arch-corelib-horizontal` — про НАШ `corelib` · ЗАВЕСТИ: ввезённых поддеревьев нет · red: «берём пином» о стороннем коде, чьи пробы нам нужны

### ВТОРАЯ ПРОПИСКА обязывает — общее не хоронится в продукте (требование владельца 2026-09-20)

Требование владельца дословно: «все общие библиотеки, которые могут быть вынесены должны быть
вынесены в corelib а не хорониться в проекте». «Может быть вынесено» — ФАКТ ВТОРОЙ ПРОПИСКИ,
а не намерение автора. Предмет — связная группа `.go`, попарно близких по нормализованному
содержимому (Jaccard ≥ 0.70) и лежащих в РАЗНЫХ домах (дом = продукт + служба).

arch-second-home-needs-a-decision · предмет со второй пропиской несёт ЗАПИСАННОЕ решение в `docs/foundation-candidates.yaml` (словарь и требования к доводу — там же); истинность класса выносит приёмка записи и `check-verifier` · scripts/foundation-candidates/check-01-every-candidate-carries-a-decision.py · red: кандидат без записи; запись без предмета; `keep` без `class`/`evidence`; девятый класс; координата вне файлов предмета
arch-second-home-no-third · ярус 1, без задач и сроков: ТРЕТЬЯ прописка запрещена; три числа ведомости (предметов · файлов · очереди) точные, красное И на росте, И на просрочке · scripts/foundation-candidates/check-02-second-home-count-does-not-grow.py · red: рост любого из трёх; число поднято вместо выноса
arch-second-home-address · адрес — по числу ПРОДУКТОВ, а не домов: два продукта → `corelib`, один продукт и две службы → `pkg/` платформы · scripts/foundation-candidates (поле «адрес выноса») · red: внутрипродуктовый предмет адресован в фундамент
arch-second-home-unit-is-package · единица отсева — ПАКЕТ, а не файл: ссылка на сиблинга импорта не требует, и отсев по `import` одного файла дыряв по построению (замер — шапка измерителя) · scripts/foundation-candidates/_core.py · red: направление или политика спрошены у файла, а не у пакета
arch-second-home-exclusions-closed · исключений ВОСЕМЬ, перечень закрыт, у каждого механический признак и условие снятия; перечень с признаками — у измерителя · scripts/foundation-candidates/_core.py EXCLUSIONS · red: девятое исключение; «и тому подобное»; «если оправдано»
arch-second-home-upper-bound · счёт — ВЕРХНЯЯ граница, а не мера требования: политика без литерала имени продукта и предмет по экземпляру на продукт признака не имеют · вниманием; остаток называет печать измерителя · red: «в фундамент едет то и только то, что предикат назвал»
arch-second-home-precondition · ярус 0: пока решение владельца о перелицензировании выносимого (отдельно BUSL-1.1 и AGPL-3.0-or-later при Apache-2.0 фундаменте) не опубликовано ЗАПИСЬЮ, очередь пуста и обязанность выноса не наступает · исключения 4а/4б, предикат снятия внешний · red: снятие «одним решением на класс»; AGPL-код в Apache-фундаменте
arch-second-home-move-atomic · вынос атомарен: все импортёры одним изменением, тег `corelib`, подъём пина у ОБОИХ потребителей; расхождение пинов — предусловие выноса · ЗАВЕСТИ arch-second-home-pin-parity · red: вынос при расходящихся пинах
arch-second-home-touch · ярус 2: правку копии кандидата без выноса допускай один раз с причиной строкой; вторая правка той же копии — находка · ЗАВЕСТИ (предикат `class-guard`; до решения о лицензии предмета нет) · red: копия правится третий раз, и об этом не знает никто

#### Как эта норма сведена с тремя действующими про границу фундамента

arch-second-home-vs-horizontal · сильнее `arch-corelib-horizontal` в срабатывании (факт копии), слабее в адресе: в фундамент — только нужное двум ПРОДУКТАМ, вторая прописка внутри продукта — в `pkg/` (`arch-new-util-ownership`) · scripts/foundation-candidates + TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: «копия есть — значит в corelib» о предмете одного продукта
arch-second-home-vs-k3-1 · не отменяет ограничение K3-1 («пакет, от которого зависит прод-код фундамента, обязан быть в фундаменте»): предмет, чей пакет импортирует модуль продукта, в очередь не попадает; очередь берётся СВЕРХУ (разбор — шапка измерителя) · scripts/foundation-candidates исключение 1, инъекция осей F и G · red: вынос, заводящий `require` на продукт в `go.mod` фундамента; отсечение по импорту того, что само переезжает; очередь снизу
arch-second-home-vs-copy-ban · шире запрета #20: тот ловит пару по ПУТИ, эта — по СОДЕРЖИМОМУ; исход у обеих — вынос, «оставить все три» исходом не является · scripts/foundation-candidates + scripts/crossrepo-gate · red: «в ведомости пар записи нет — значит копии нет»


## Concurrency / lifecycle / читаемость (выведено из audit-раундов)

arch-per-call-deadline · свой context.WithTimeout на КАЖДОМ peer-gRPC/HTTP/DB; все sibling-методы клиента — один configured-timeout · — (КАНДИДАТ НА ГЕЙТ: обход вызовов peer-gRPC/HTTP/DB без WithTimeout) · red: http.DefaultClient.Do с сырым request-ctx
arch-waitgroup-drain · Stop() делает wg.Done за каждую задачу backlog + guard enqueue-after-stop под тем же mutex · — (КАНДИДАТ НА ГЕЙТ: wg.Add без парного Done на пути Stop) · red: Wait() не доходит до нуля
arch-doc-truthfulness · описывает реальность кода, не намерение · — (частично: TestVpcSchemaGateFindsAColumnThatLiesAboutTheDiagram, TestClientTruth*) · red: комментарий о WHERE/статусе/sentinel, которых в коде нет
arch-lean-no-vestigial · тип/пакет/ветка без прод-импортёров удаляется вместе с тестами · TestDeadHelper* (только пробы) · red: unreachable branch «документирует» контракт

## Пул размеряется по ДЛИННОМУ МЕНЬШИНСТВУ, а не по среднему (выведено 2026-08-21)

arch-pool-long-minority · размеряется по длинным запросам: доля промахов кеша × их длительность, не по среднему · — (КАНДИДАТ НА ГЕЙТ: TestPoolParamPredicateHasASingleHome рядом, предмета не судит) · red: «1 мс × rps, возьмём с запасом»
arch-pool-sign · отвергается, если считана от средней задержки · ЗАВЕСТИ · red: множитель «запас» от средней
arch-pool-profile · ищи ограниченный набор, а не нехватку мощности · ЗАВЕСТИ · red: добавили реплик вместо глубины
arch-pool-how-choose · из счётчика промахов кеша и гистограммы длительности · ЗАВЕСТИ · red: число без обеих величин
arch-pool-ceiling · помещаются в предел владельца ресурса · ЗАВЕСТИ · red: превышение = отказ владельца целиком

## Конфигурация, впервые ставшая ЧИТАЕМОЙ, перебивает умолчание поставщика (выведено 2026-08-23)

arch-config-readable-norm · объявляется ломающим изменением · ЗАВЕСТИ · red: «просто начали монтировать карту»
arch-config-readable-sign · сверь КАЖДЫЙ свой раздел с умолчанием поставщика · kubectl get deploy -o jsonpath='{..args}' \ · red: grep -c config > 1 | раздел заменён целиком молча

## Параллельные полосы одного механизма обязаны сверяться МЕЖДУ СОБОЙ

arch-lanes-compare-norm · свойство проверяется СРАВНЕНИЕМ полос, не по каждой отдельно · ЗАВЕСТИ · red: полосы объявляют разное, и это никто не решал
arch-lanes-gate-census · печатает «полос N · несут свойство M» · ЗАВЕСТИ · red: одно число вместо двух
