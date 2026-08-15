---
title: "KAC-124 (vault-label WS23): WS-2.3 — AuthZ decision-cache invalidation on grant/revoke"
category: kac
ticket_id: KAC-WS23
status: done
type: feature
tags:
  - kac
---

# KAC-124 (vault-label WS23): WS-2.3 — AuthZ decision-cache invalidation on grant/revoke

> [!note] Строка «Где ведётся» переписана 2026-08-05: это адрес РАБОТЫ, а не история
> Здесь стояли имена репозиториев полирепо-эпохи. По незакрытой записке эта строка читается
> как указание, куда идти, — и отправляла бы в репозиторий, которого нет. Домены и их
> каталоги сохранены один-в-один; прежние имена оставлены в скобках, чтобы связь со старыми
> PR и разборами не потерялась. В остальном тексте записки имена НЕ трогались — там они
> история и верны как история.

> [!warning] План, на который ссылается записка, из дерева выведен (сверено 2026-08-05)
> `docs/superpowers/plans/` в воркспейсе нет. Ссылка ниже сохранена как след решения, адресом
> она не является.

> [!important] «Оба конца мертвы» пережило свой предмет — все четыре шага плана приземлены
> (перемерено 2026-08-08 на `project/kacho` @ `6b1293713`)
> Записка держалась в ведре «в работе» на утверждении, что инфраструктура отскаффолжена, но
> «никто не пишет/не дренит», а `Invalidate()`/`InvalidateSubject()` в крае — без вызовов.
> Сегодня неверны обе половины, и проверяются они разными предикатами — по **эмитенту**,
> **дренажу** и **приёмнику** отдельно, иначе живой один конец выдаётся за оба.
>
> | Шаг плана | Где он в дереве | Предикат |
> |---|---|---|
> | 1. запись в `subject_change_outbox` в TX привязки | **три** эмитента: `access_binding/create.go:376`, `delete.go:247`, `revoke.go:218` | `git grep -n EmitSubjectChangeEvent -- services/iam \| grep -v _test` |
> | 2. internal-RPC `PollSubjectChanges` | `proto/kacho/cloud/iam/v1/internal_iam_service.proto:109` | `git grep -n PollSubjectChanges -- proto` |
> | 3. синхронный self-flush края на проксируемой мутации | `gateway/internal/middleware/authz.go:252`, зовётся из `:366` и `:467` | `git grep -n MaybeFlushOnMutation -- gateway \| grep -v _test` |
> | 4. фоновая сходимость остальных реплик | `gateway/internal/watcher/subject_change_watcher.go`, провязан в `gateway/cmd/api-gateway/main.go:506` | `git grep -rn 'internal/watcher' -- gateway \| grep -v _test` |
>
> Приёмник вызова живой: `apigatewayv1.RegisterInternalAuthzCacheServiceServer` —
> `gateway/internal/handler/internal_authz_cache_server.go:110`. Отправитель тоже: iam несёт
> push-дренаж очереди (`services/iam/cmd/kacho-iam/subject_change_wiring.go`), причём адрес
> внутреннего листенера края объявлен обязательным — пустой роняет старт.
>
> Почему это стоило перемерить, а не прочитать: «оба конца мертвы» — утверждение о **двух**
> предикатах сразу, и оно остаётся правдоподобным, пока живым стал только один. Здесь ожили оба,
> плюс два шага, которых в исходной формулировке не было.
>
> Чекбоксы §DoD ниже **намеренно не проставлены**: они относятся к прогонам (`newman`,
> integration, `buf`) и к трём PR полирепо-эпохи; отмечать их по факту наличия кода значило бы
> выдать чтение дерева за вердикт прогона. Ведро статуса меняется по предмету, галочки — по
> исходам, и это разные утверждения.

**Состояние на момент записи**: in-progress
**Type**: feature
**Где ведётся**: `PRO-Robotech/kacho` — `proto/`, `services/iam/`, `gateway/` (прежние имена: `kacho-proto`, `kacho-iam`, `kacho-api-gateway`)
**PRs**: PRO-Robotech/kacho-proto#21 · PRO-Robotech/kacho-iam#18 · PRO-Robotech/kacho-api-gateway#21 (открыты, CI идёт)
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-124 (subtask of KAC-123 / эпик vault-label KAC-127)

> vault-label `WS23` — потому что vault-файл `KAC-124.md` уже занят (vault-label
> resource-manager closeout, YT-counter тогда отставал). YT idReadable этого
> тикета — реально `KAC-124`. Ветки во всех репо — `KAC-124`.

## Что и зачем

`AccessBinding.Create/Delete` не инвалидируют authz decision-cache api-gateway
(LRU 10k / 5s TTL). Отозванный грант продолжает авторизовать до истечения TTL —
newman e2e `AUTHZ-REVOKE-ENFORCED-A-NOB` RED (CI `26220429877`), блокирует
kacho-iam PR #17.

**Состояние на момент записи** (2026-05, историческое — см. врезку выше): инфраструктура была
отскаффолжена, но оба конца мертвы — таблица `subject_change_outbox` (migration `0002`) +
NOTIFY-триггер существовали, но никто не писал/не дренил; `decisionCache.Invalidate()`/
`InvalidateSubject()` в gateway — без вызовов.

**Решение (план `docs/superpowers/plans/2026-05-22-ws2.3-authz-cache-invalidation-plan.md`):**
1. iam: `AccessBinding.Create/Delete` пишут `subject_change_outbox` в TX привязки.
2. proto+iam: новый internal-RPC `InternalIAMService.PollSubjectChanges`.
3. gateway: синхронный self-flush `decisionCache` на проксируемой AccessBinding-мутации — детерминизм e2e.
4. gateway: фоновый poll-loop `PollSubjectChanges` → сходимость остальных реплик.

Не LISTEN/NOTIFY напрямую: gateway без доступа к Postgres, давать edge-компоненту
DB-креды iam — расширение blast-radius. RPC-poll переиспользует `iamInternal` gRPC.

## Затронутые сущности vault

- [[../rpc/iam-internal-iam-service]] — новый RPC `PollSubjectChanges` (internal-only)
- [[../resources/iam-access-binding]] — Create/Delete теперь эмитят subject_change_outbox
- [[../rpc/iam-access-binding-service]] — побочный write в outbox
- [[../edges/api-gateway-to-iam-subject-change]] — новый runtime-edge poll-loop (создан)

## Acceptance / Definition of Done

- [ ] integration tests зелёные (iam: EmitSubjectChange in-TX, PollSubjectChanges cursor)
- [ ] unit tests зелёные (gateway: MaybeFlushOnMutation, SubjectChangeWatcher)
- [ ] newman E2E `AUTHZ-REVOKE-ENFORCED-A-NOB` GREEN (RED→GREEN пара в PR)
- [ ] `buf lint`/`buf breaking` зелёные (kacho-proto)
- [ ] vault записи обновлены (rpc / resources / edges)
- [ ] 3 PR merged в main (proto → iam → api-gateway)

## Связанные тикеты

- [[KAC-127]] — эпик Production-Ready IAM (этот WS — remediation его gap'ов)
- PR #17 `iam-authz-review-remediation` — разблокируется этим WS

#kac #feature
