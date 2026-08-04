---
title: api-gateway → iam — acr-on-internal step-up floor
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-iam
sync_async: sync
protocol: grpc
status: stable
related_tickets:
  - kacho-iam#122
tags:
  - edge
  - kacho-api-gateway
  - kacho-iam
  - internal
  - cross-service
---

# api-gateway → iam — `required_acr_min` step-up on :9091 (sub-phase 5.4)

**Edge**: api-gateway internal-mux re-dial → kacho-iam :9091 (gateway-fronted privileged RPCs).
**Protocol**: gRPC over mTLS (SEC-K gateway client-cert SAN `…/sa/kacho-api-gateway`). Sync.

## Что

`required_acr_min` (step-up / MFA-freshness floor) энфорсился **только** на публичном пути
(gateway `StepUpGate`), но gateway **ронял** acr при re-dial на :9091 → gateway-fronted privileged
RPC (`InternalClusterService/{Get,GrantAdmin,RevokeAdmin,ListAdmins}`, уже с `acr_min=2`) **не**
acr-энфорсился внутри. Sub-phase 5.4 замыкает плечо end-to-end:

1. **gateway** (`restmux/mux.go` `buildPrincipalMetadata`) — пробрасывает validated acr
   (`X-Kacho-Token-Acr`, который public DPoP-middleware уже выставляет) как `x-kacho-token-acr`
   metadata, рядом с `x-kacho-principal-*`. absent acr ⇒ ключ не добавляется.
2. **corelib** (`grpcsrv.UnaryTrustedPrincipalExtract`) — вносит acr в trusted-carrier **только**
   когда trusted (FD-4: peer mTLS-verified); на unverified peer acr dropped (anti-spoof).
   `TrustedACRFromContext` + shared `ACRRank`/`ACRSatisfies`.
3. **iam** (`authzguard.ACRFloor`) — interceptor на :9091 **после** `UnaryTrustedPrincipalExtract`
   + `internalCallerPolicy`: для gateway-fronted RPC с catalog `acr_min>0` энфорсит
   `acr >= acr_min` → иначе `PermissionDenied` + step-up signal (`PreconditionFailure`,
   `authz.step_up`, `acr_values:<min>`) для RFC-9470 challenge. FQN→acr_min из embedded
   permission-каталога (`seed.PermissionRegistry.RequiredACRMin`).

## Trust / scope

- acr доверяем **только** на mTLS-verified gateway-ребре (FD-4). Спуфнутый acr с non-gateway peer
  → dropped (rank 0) + `internalCallerPolicy` отклоняет non-gateway SAN на gateway-fronted RPC
  **раньше** floor'а (5.4-06).
- Module-SA (vpc/compute fgaproxy) — **acr-exempt** (не user-principal, нет MFA); floor трогает
  только gateway-fronted set.
- Default-OFF: dev/newman (prod=false) ⇒ NO-OP pass-through (byte-identical). Prod fail-closed:
  absent acr на acr-требующем RPC ⇒ denied.
- Latent-until-policy: прочие gateway-fronted admin-RPC сегодня `acr_min=0` ⇒ floor inert до
  policy-изменения (механизм generic по FQN→acr_min — доказано фикстурой 5.4-08).

## Уровень человека доезжает до гейта (2026-08-04, ствол `a39a7de6`)

До этой правки край брал уровень **только** из стандартного верхнеуровневого
утверждения, тогда как собственный хук выдачи кладёт его в **карту обогащения**, а
поднимать это имя наверх не просит ни один профиль развёртывания. Уровень приезжал
ВНУТРИ подписанного токена и отбрасывался **до** того, как его увидит гейт ступени:
человек, честно поднявший уровень, ранжировался нулём. Отказ был **fail-closed** —
потеря возможности, не проход внутрь.

**Почему ребро выглядело исправным.** Машинный принципал освобождён от порога
**до** сравнения (см. `Trust / scope` выше), поэтому на нём расхождение
ненаблюдаемо. Единственный наблюдатель — предъявитель, принадлежащий человеку, — на
стендах не существовал, пока его не начала производить церемония
([[../KAC/IAM-INT-1-interactive-login]]).

**Что теперь верно на ребре:**

- разрешение карты обогащения сведено в **одну** точку и принимает **обе** формы,
  которые выпускает провайдер (поднятую наверх и вложенную в его обёртку). Иначе
  одно утверждение видно одним читателям и невидимо другим в зависимости от
  профиля, причём слепым оказывался **боевой**;
- порядок: стандартное утверждение **выигрывает**, карта — запасной путь;
- источник по-прежнему **только подписанный токен**: ни заголовок, ни метаданные
  уровень задать не могут, токен без уровня получает отказ;
- следствие названо намеренно: на боевом профиле снова начинает работать
  освобождение машинного принципала, которое там молча не применялось.

> [!warning] Фикстура была снисходительнее продукта
> Прежние пробы клали уровень туда, куда его продукт **не кладёт**, и потому не
> могли увидеть расхождение ни при каком состоянии кода. Проба обязана класть
> значение **только** туда, куда его кладёт продукт, — иначе она проверяет себя.

## History

- **2026-06-16** (sub-phase 5.4, kacho-iam#122): edge создан. corelib `feat/acr-on-internal`
  (grpcsrv acr carrier) → iam (ACRFloor) → api-gateway (forward acr). Merge order
  corelib → iam → gateway. PRs: kacho-corelib#23, kacho-iam#149, kacho-api-gateway#80.
- **2026-08-04** (IAM-INT-1 S2, ствол `a39a7de6`): пол начал энфорситься для
  **человеческих** предъявителей — разрешение имени уровня сведено в одну точку,
  принимаются обе формы провайдера. До этого гейт исполнялся на каждом запросе и
  читал пусто. Класс уровня в пробах волны церемонии держит гейт
  `deploy/scripts/assert-step-up-bearer-matches-catalog.py` (недобор и перебор —
  оба находки).

## See also

[[../packages/corelib-grpcsrv]] [[api-gateway-to-iam-authorize]] [[../KAC/KAC-122]]
[[../KAC/IAM-INT-1-interactive-login]] [[../packages/iam-authzguard]]

#edge #kacho-api-gateway #kacho-iam #internal #cross-service
