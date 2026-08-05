---
title: "vpc → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - vpc to iam fgaproxy
  - vpc register resource
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: mixed
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
  - security
  - internal
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!warning] Записка стояла в статусе «planned» — ребро живое (сверено 2026-08-05, дерево `96b2879a`)
> Прежний заголовок обещал будущее: «kacho-vpc **начнёт** вызывать это ребро в SEC-D».
> В дереве обе половины на месте: `services/vpc/internal/clients/iam_sync_registrar.go`
> (синхронный путь) и `iam_register_applier.go` + `internal/apps/kacho/fgaregister/`
> (durable-намерение и дренаж). Обещание, пережившее собственное исполнение, читается как
> «ещё не сделано» и заставляет делать заново.

# vpc → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `vpc → iam` (ацикличность: iam не зовёт vpc).
**Synchronicity**: **обе половины**. Синхронный регистратор зовёт `RegisterResource` сразу
после коммита ресурса (per-call 5 с на кортеж), и **та же** регистрация durable лежит в
`fga_register_outbox` той же writer-транзакции — её доставляет дренаж. Обе доставки несут
**одну и ту же** версию, проштампованную БД внутри writer-tx: приёмная сторона гасит вторую
строгим монотонным сравнением, и при равных версиях порядок прибытия перестаёт что-либо
значить. Свежие часы на синхронной стороне это гашение снимали ровно тогда, когда дренаж
выигрывал гонку.

## Контракт

- `RegisterResource({subject_id, relation, object, trace_id})` → пустой response (sync).
  IAM эмитит owner-hierarchy tuple в `kacho_iam.fga_outbox` в одной writer-tx; drainer
  применяет к OpenFGA. **Идемпотентно**: повтор → OK (не AlreadyExists).
- `UnregisterResource(...)` — симметричный revoke; снятие отсутствующего → OK (не NotFound).
- **at-least-once**: vpc-сторона (SEC-D) пишет intent в свой outbox в той же tx, что и
  Insert ресурса (no dual-write); drainer ретраит при IAM `Unavailable` — tuple не теряется.

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` → `sva`-id vpc →
ReBAC `Check(service_account:<sva-vpc>, fga_writer, iam_fgaproxy:system)`. vpc-SA несёт этот
relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## Mirror-feed (labels + parent_project_id)

`RegisterResource`-intent несёт не только tuple, но и mirror-feed (`labels` +
`parent_project_id` + монотонный `source_version`) для IAM `resource_mirror` —
это питает ARM_LABELS-селектор (rsab reconciler материализует/ревокает
membership на `mirror.upsert`). Эмит-точка обязана использовать
`RegisterItems(ProjectHierarchyItem(projectID, <vpc_type>, id, LabelsToMap(labels)))`,
а не bare `RegisterIntent(ProjectHierarchy(...))` (последний оставляет mirror без
labels → селектор не матчит, under-show). На Update — `labelsInMask`-gated
re-emit с обновлёнными labels (revoke при снятии метки). `parent_project_id` =
собственный ProjectID ресурса.

## Барьера на видимость больше НЕТ — и это решение, а не упущение

> [!warning] Здесь стоял раздел про confirm-gate — механизма нет в дереве
> Прежняя редакция описывала как действующее: Create-операция сети/группы/подсети
> достигает успеха **только после** подтверждающего чтения владельческого кортежа, с
> отдельным дедлайном подтверждения. Механизм **снят целиком** по system-design-review как
> нарушение ban #9. Перепись 2026-08-05 по дереву `96b2879a`: ни `RunWithConfirm`, ни
> `OwnerConfirmer`, ни `WithConfirmationDeadline`, ни переменная дедлайна подтверждения, ни
> текст отказа «owner-tuple registration not confirmed» — **ноль вхождений** во всём
> монорепо (предикат: `git grep` по каждому из пяти имён).

`Operation.done` означает **durability предмета мутации** и ничего больше. Гейтить его на
видимость downstream-эффекта запрещено, и запрет выведен из последствий, а не из вкуса:
на fail-closed он рождает **фантом** (строка закоммичена, имя занято уникальным
ограничением, а операция — ошибка), и он превращает ограниченный лаг чтения-своих-записей
в неограниченный жёсткий отказ под нагрузкой на downstream.

Что стоит вместо барьера:

- **синхронный регистратор** сокращает окно видимости, но **не является условием успеха**:
  его ошибка — WARN, а не отказ мутации. Провалить операцию здесь значило бы отдать
  вызывающему код узла прав на **уже созданную** подсеть, чей CIDR уже занят
  EXCLUDE-ограничением, — то есть фантом с другой стороны;
- **durable-намерение + дренаж** доводят кортеж at-least-once;
- **остаточный лаг** закрывается ограниченным клиентским повтором (`testing.md`
  §e2e-инварианты), а не серверным подтверждением.

> [!note] Расхождение внутри самого дерева, зафиксировано как наблюдение
> godoc `SyncRegistrar` в vpc до сих пор говорит «любая ошибка пробрасывается наверх →
> create-Operation fail-closed». Вызывающие use-case'ы делают **не это**: они логируют
> предупреждение и продолжают (см. `api/subnet/create.go` и сиблинги). Верен код,
> устарел комментарий; здесь описано поведение, а не комментарий.

## History

- **T3.1 (#113)**: network Update + securityGroup Create+Update переведены на
  mirror-feed (labels). subnet — эталон.
- **T3.2 ([kacho-vpc#10](https://github.com/PRO-Robotech/kacho-vpc/issues/10))**:
  закрыт остаточный gap — routeTable / address / gateway / networkInterface
  переведены с bare tuple на `RegisterItems(ProjectHierarchyItem(... labels))` на
  Create + `labelsInMask`-gated re-emit на Update. proto/схема без изменений.
  PR [kacho-vpc#11](https://github.com/PRO-Robotech/kacho-vpc/pull/11). См.
  [[../KAC/sub-phase-T3.2-vpc-residual-label-feed]].
- **owner-tuple opgate (заведён, затем снят)**: Create сети/группы/подсети какое-то время
  гейтился на подтверждающем чтении владельческого кортежа. Снят целиком по
  system-design-review как нарушение ban #9 — см. §«Барьера на видимость больше НЕТ».
  Оставлено здесь как история: механизм существовал, и записки соседних сервисов на него
  ссылались.
- **2026-08-05** — записка приведена к дереву `96b2879a`: статус `planned` → `active`
  (обе половины ребра давно в дереве), снят раздел про confirm-gate, добавлены
  классификация отказов и ссылка на контракт приёмной стороны.

## Что происходит при отказе

| Что отказало | Синхронный путь | Путь очереди (дренаж) |
|---|---|---|
| iam недоступен, дедлайн, транспорт | WARN, мутация успешна | ретрай с задержкой, намерение durable (`sent_at IS NULL`) |
| `INVALID_ARGUMENT` — кривой кортеж | WARN | **отравление** строки: повтор не починит |
| `PERMISSION_DENIED` — отношение вне закрытого набора iam либо нет права писать | WARN | **отравление**, а НЕ ретрай: решение зависит от (вызывающий, отношение, объект), и повтор не меняет ни одного из трёх; временная классификация навсегда заклинила бы голову партиции |
| неизвестный тип события / нечитаемый payload | — | **отравление** |

Отравление — ограниченная пауза, а не потеря: периодический `RedrivePoisoned` возвращает
такие строки в доставляемое состояние (`cmd/vpc/backstop.go`; тот же backstop у compute,
nlb, storage, registry).

## See also

[[iam-register-resource-callee-contract]] (что делает приёмная сторона: зеркало, гашение
повторной доставки, пост-коммитный форвард, счётчик)
[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[vpc-to-iam-check]] [[compute-to-iam-fgaproxy]] [[iam-to-openfga-grant-write]] [[../KAC/EPIC-SEC-mtls-iam-authz]] [[../KAC/sub-phase-T3.2-vpc-residual-label-feed]]

#edge #kacho-vpc #kacho-iam #cross-service #security #internal
