---
title: corelib-oauthceremony
category: packages
repo: kacho-corelib
path: PRO-Robotech/corelib:oauthceremony
layer: shared
status: test
tags:
  - packages
  - kacho-corelib
  - ports
verified_against: "PRO-Robotech/corelib@227ed2b77b4 (коммит слияния волны 32 в ветку эпика 26), 2026-09-26: doc.go прочитан; объявления типов ports.go и полей Config в ceremony.go сняты `git show`; снятые имена ProofKeyVault, SigningSecret, SecretHashCost, IdentityToken, IDTokenIssuer — 0 вхождений в непробных файлах пакета (`git grep -c -F`). Пин потребителя — go.mod kaname@fc9f5aff19c; теги v1.10.0-rc.1..rc.3 — `git ls-remote --tags origin`. Поведение проб не перезапускалось"
---

# oauthceremony — граница церемонии OAuth 2.0 между службой и движком

**Каталог**: `PRO-Robotech/corelib:oauthceremony/` · импорт `github.com/PRO-Robotech/corelib/oauthceremony`
**Состояние**: пакет в ветке эпика `26` фундамента (движок пришёл волной-1, порты — волной
[[KAC/issue-32-corelib|corelib#32]]); в `main` фундамента его нет — отсюда `status: test`.
**Потребитель**: служба доступа kaname — адаптеры портов в `internal/ceremonyport` и
`internal/repo/kaname/pg` ([[KAC/issue-396-kaname|kaname#396]], [[KAC/issue-410-kaname|kaname#410]]).

## Главное правило

Ни один экспортированный элемент пакета не называет чужого типа: движок внесён поддеревом
`internal/oauth2`, и пакет над ним не протаскивает его типы наружу. Правило держит проба
`TestNoForeignTypeInExportedSurface`, разбирающая исходники деревом. Смена движка поэтому не
становится правкой каждой службы.

## Порты — решения, которые принимает служба

Все порты объявлены здесь и реализуются **службой**; фундамент реализаций не приносит.

| порт / поле | что решает служба | задача волны |
|---|---|---|
| `AccessTokenIssuer` | чем подписан и что несёт токен доступа; код и токен обновления непрозрачны, `SigningSecret` снят | [[KAC/issue-34-corelib\|#34]] |
| `Config.NewGrantID` | ID гранта — ключ семейства (`tfm-…`, [[packages/corelib-ids]]); зовётся один раз на грант, `New` без крючка отказывает | [[KAC/issue-35-corelib\|#35]] |
| `ClientSecretVerifier` | сверка секрета клиента и её постоянное время; хешера у церемонии нет, `SecretHashCost` снят | [[KAC/issue-37-corelib\|#37]] |
| `GrantRevoker` + `RevocationReason` | отзыв семейства с причиной из закрытого словаря: `code-replay`, `refresh-replay`, `client-revoke` | [[KAC/issue-33-corelib\|#33]] |
| `AuthorizationGrant.SessionID`, `ACR`, `AuthTime` | контекст входа — поля гранта, а не ключи карты Claims; снимок не меняется по кругу выдачи, обмена и обновления; словарь уровня — [[packages/corelib-acrlevel]] | [[KAC/issue-36-corelib\|#36]] |
| `Config.AuthorizationEndpoint`, `TokenEndpoint` | адреса церемонии названы, а не выводятся из `Issuer` | [[KAC/issue-38-corelib\|#38]] |
| потолки `tokenpolicy` | срок кода и семейства обновления не выше `MaxAuthorizationCodeTTL` и `MaxRefreshTokenFamilyTTL` | [[KAC/issue-39-corelib\|#39]] |
| `AuthorizationCodeRecord` | привязка PKCE — поля записи кода, метод только S256; порт `ProofKeyVault` снят | [[KAC/issue-40-corelib\|#40]] |

Порты хранения — `ClientDirectory`, `AuthorizationCodeVault`, `AccessTokenVault`,
`RefreshTokenVault`, `GrantRevoker` и необязательный `UnitOfWork`. `Config.PortTimeout` — срок
одного вызова порта хранения и порта выпуска токена доступа.

## Поведение, уточнённое сборкой 1 волны

- артефакт клиента, снятого из справочника, отвечается как негодный ([[KAC/issue-41-corelib|#41]]);
- откат единицы работы получает живой контекст со сроком не дальше `PortTimeout`
  ([[KAC/issue-43-corelib|#43]]);
- интроспекция отвергает по имени способ доказательства, которого точка не принимает
  ([[KAC/issue-42-corelib|#42]]);
- поверхность токена личности без обработчика снята — `IdentityToken`, `IDTokenIssuer`
  ([[KAC/issue-44-corelib|#44]]);
- выданная область — scope-token по RFC 6749 §3.3, иная не выдаётся ([[KAC/issue-47-corelib|#47]]);
- у каждого поля `Config`, что судит `New`, есть читатель ([[KAC/issue-56-corelib|#56]]); отказ
  адреса называет правило схемы, хоста и пути ([[KAC/issue-57-corelib|#57]]); сопряжение #36 с
  #37 и #39 держат пробы под `-race` ([[KAC/issue-63-corelib|#63]]).

## Чего здесь нет

Реализации хранилища (она у службы, владеющей базой) и сетевых обработчиков (церемония
возвращает, что написать, но не пишет). Нет утверждений клиента RFC 7523 и объектов запроса
OpenID Connect, нет вида гранта `client_credentials` — у машинных клиентов службы доступа своя
выдача, нет неявного потока.

## Выпуски и пин потребителя

| тег | коммит | что несёт |
|---|---|---|
| v1.10.0-rc.1 | `f213439a409` — слияние #34 | порты до #34 включительно |
| v1.10.0-rc.2 | `c8b7650112d` — слияние #63 | все прямые вливания волны; **сборки 1 нет** |
| v1.10.0-rc.3 | `867dc4c5e41` — после волны-4 #29 | волна 32 целиком |

Служба доступа на голове своего эпика `357` (`fc9f5aff19c`) закреплена на v1.10.0-rc.2: правки
сборки 1 (#41–#47, #56, #57, #64) до неё доедут подъёмом пина.

## History

- 2026-09-23…24 — порты волны [[KAC/issue-32-corelib|corelib#32]]: #33–#40, #63 прямыми
  вливаниями, #41–#47, #56, #57 сборкой 1; запрос волны PR #62 влит в ветку эпика `26`
  (`227ed2b77b4`).
- 2026-09-26 — записка заведена: поведения пакета не описывала ни одна записка хранилища.

#packages #kacho-corelib #ports
