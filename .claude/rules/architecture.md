---
name: rule-architecture
description: "Чистая архитектура + переиспользование"
---

**Архив** — доводы, замеры, снятые редакции; **НЕ действующая норма**, цитировать как норму нельзя: `.claude/backup/architecture.md`

# Чистая архитектура + переиспользование

## Clean Architecture (строгое dependency rule)

arch-dependency-diagram · handler/repo/clients → use-case → domain, обратных рёбер нет · go list -deps по слою · red: импорт transport из use-case
arch-domain-pure · только stdlib + kacho-proto · go list -deps ./internal/domain/... без pgx/grpc/internal · red: pgx/grpc/sqlc-тип в domain
arch-usecase-ports · объявляет порты <Res>Repo/<Peer>Client, импортирует domain · нет импорта internal/handler · red: transport-тип в сигнатуре use-case
arch-repo-adapter · реализует порты, импортирует pgx+domain · ЗАВЕСТИ arch-repo-adapter · red: repo объявляет свой порт
arch-clients-adapter · реализует порты, импортирует grpc-стабы+domain · ЗАВЕСТИ arch-clients-adapter · red: бизнес-решение в clients
arch-handler-thin · parse → use-case → format · ЗАВЕСТИ arch-handler-thin · red: ветка бизнес-логики или SQL в handler
arch-wiring-cmd-only · только cmd/<svc>/main.go · TestCompositionRootsCarryNoServerConstructionOfTheirOwn · red: конструктор зависимостей вне cmd/
arch-identity-carrier · несётся нейтральным типом, не transport-типом · grep импорта internal/handler в use-case · red: use-case читает identity из transport
arch-ban-infra-in-domain · не импортируют pgx/grpc-stubs/sqlc-types · go list -deps · red: инфра-тип в чистом слое
arch-ban-biz-in-handler · без бизнес-логики · ЗАВЕСТИ arch-ban-biz-in-handler · red: условие домена в transport
arch-ban-global-singleton · никаких var globalPool и init()-сайд-эффектов вне cmd/ · ЗАВЕСТИ arch-ban-global-singleton · red: пакетный пул или init() в сервисе
arch-tests-by-layer · use-case — mock-порты, integration — testcontainers, e2e — api-gateway · TestPerTestContainerJudgeFiresAndStaysSilent · red: integration подменяет unit
arch-postgres-in-service-test · не требует Postgres · ЗАВЕСТИ arch-postgres-in-service-test · red: use-case-тест поднимает БД = утечка adapter

## Переиспользование: фундамент в `corelib`, своё — в `pkg/` платформы

arch-corelib-horizontal · нужен двум продуктам → PRO-Robotech/corelib пином версии · TestCrossModuleJudgeIsSilentOnTheAllowedDirections · red: вторая копия per-service
arch-new-util-ownership · спроси чей предмет: двум → corelib, одному → pkg/, домену → каталог сервиса · ЗАВЕСТИ arch-new-util-ownership · red: доменная логика в pkg/

## Concurrency / lifecycle / читаемость (выведено из audit-раундов)

arch-per-call-deadline · свой context.WithTimeout на КАЖДОМ peer-gRPC/HTTP/DB; все sibling-методы клиента — один configured-timeout · — (КАНДИДАТ НА ГЕЙТ: обход вызовов peer-gRPC/HTTP/DB без WithTimeout) · red: http.DefaultClient.Do с сырым request-ctx
arch-waitgroup-drain · Stop() делает wg.Done за каждую задачу backlog + guard enqueue-after-stop под тем же mutex · — (КАНДИДАТ НА ГЕЙТ: wg.Add без парного Done на пути Stop) · red: Wait() не доходит до нуля
arch-doc-truthfulness · описывает реальность кода, не намерение · — (частично: TestVpcSchemaGateFindsAColumnThatLiesAboutTheDiagram, TestClientTruth*) · red: комментарий о WHERE/статусе/sentinel, которых в коде нет
arch-lean-no-vestigial · тип/пакет/ветка без прод-импортёров удаляется вместе с тестами · TestDeadHelper* (только пробы) · red: unreachable branch «документирует» контракт

## Пул размеряется по ДЛИННОМУ МЕНЬШИНСТВУ, а не по среднему (выведено 2026-08-21)

arch-pool-long-minority · размеряется по длинным запросам: доля промахов кеша × их длительность, не по среднему · — (КАНДИДАТ НА ГЕЙТ: TestPoolParamPredicateHasASingleHome рядом, предмета не судит) · red: «1 мс × rps, возьмём с запасом»
arch-pool-sign · отвергается, если считана от средней задержки · ЗАВЕСТИ arch-pool-sign · red: множитель «запас» от средней
arch-pool-profile · ищи ограниченный набор, а не нехватку мощности · ЗАВЕСТИ arch-pool-profile · red: добавили реплик вместо глубины
arch-pool-how-choose · из счётчика промахов кеша и гистограммы длительности · ЗАВЕСТИ arch-pool-how-choose · red: число без обеих величин
arch-pool-ceiling · помещаются в предел владельца ресурса · ЗАВЕСТИ arch-pool-ceiling · red: превышение = отказ владельца целиком

## Конфигурация, впервые ставшая ЧИТАЕМОЙ, перебивает умолчание поставщика (выведено 2026-08-23)

arch-config-readable-norm · объявляется ломающим изменением · ЗАВЕСТИ arch-config-readable-norm · red: «просто начали монтировать карту»
arch-config-readable-sign · сверь КАЖДЫЙ свой раздел с умолчанием поставщика · kubectl get deploy -o jsonpath='{..args}' \ · red: grep -c config > 1 | раздел заменён целиком молча

## Параллельные полосы одного механизма обязаны сверяться МЕЖДУ СОБОЙ

arch-lanes-compare-norm · свойство проверяется СРАВНЕНИЕМ полос, не по каждой отдельно · ЗАВЕСТИ arch-lanes-compare-norm · red: полосы объявляют разное, и это никто не решал
arch-lanes-gate-census · печатает «полос N · несут свойство M» · ЗАВЕСТИ arch-lanes-gate-census · red: одно число вместо двух
