---
title: "Subject privileges (sub-phase 1.3)"
aliases:
  - sub-phase-1.3-subject-privileges
  - subject-privileges
ticket_id: "(none — sub-phase acceptance doc)"
category: kac
status: done
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-ui
  - kacho-api-gateway
---

# Subject privileges (sub-phase 1.3)

> [!note] Трек без KAC-номера
> Acceptance-док `docs/specs/sub-phase-1.3-*-acceptance.md`; YouTrack-тикет не заводился.

**Status**: ✅ done — merged на `main` + live `fe3455` (helm **rev14**, 2026-06-18; 1.3b group support).
**Type**: feature
**Repos / PRs**: kacho-proto (merged), kacho-iam [#159](https://github.com/PRO-Robotech/kacho-iam/pull/159), kacho-api-gateway [#84](https://github.com/PRO-Robotech/kacho-api-gateway/pull/84), kacho-ui [#80](https://github.com/PRO-Robotech/kacho-ui/pull/80). **1.3b**: kacho-iam [#162](https://github.com/PRO-Robotech/kacho-iam/pull/162), kacho-ui [#82](https://github.com/PRO-Robotech/kacho-ui/pull/82).

## Что и зачем

UI-деталь субъекта (User / ServiceAccount) должна показывать **все его привилегии** (effective roles) одним списком — не вынуждая обходить access-bindings вручную. Нужен один sync-read, агрегирующий привязки субъекта с человекочитаемым именем роли и источником деривации.

## Сделано

- **proto**: `AccessBindingService.ListSubjectPrivileges` + message `SubjectPrivilege` (`subject_type`, `subject_id`, `role_id`, `role_name`, `resource_type`, `resource_id`, `scope`, `derivation`) + enum `Derivation`. REST `GET /iam/v1/accessBindings:listSubjectPrivileges`.
- **kacho-iam #159**: use-case `ListSubjectPrivileges` — authz self-OR-account-admin через `requireAccountViewAuthority`; LEFT JOIN `roles` для `role_name`.
- **kacho-api-gateway #84**: регистрация `ListSubjectPrivileges` (public sync read).
- **kacho-ui #80**: «Привилегии» на детальных страницах User + ServiceAccount + кнопка «добавить привилегии» → AccessBindingCreatePage с locked subject.

## 1.3b — group subject privileges (scope extension)

После live-прогона заказчик попросил привилегии и для **Group** (в 1.3 group был **вне scope** — D-5/Q#5). Additive-расширение (`buf breaking` зелёный), оформлено addendum'ом к acceptance-доку (ретроспективный ban #1).

- **kacho-iam #162**: `ListSubjectPrivileges` принимает `subject_type=group` (было user\|service_account); group connected roles = прямые AccessBinding'и на группе (`derivation=DIRECT`); `resolveSubjectHomeAccount` резолвит home-account группы через `groups.account_id` (within-`kacho_iam`, не новый cross-domain edge). Плюс — в том же PR migration `0017` backfill `operations.account_id` (см. [[sub-phase-1.2-iam-operations]]).
- **kacho-ui #82**: «Привилегии» переработана из detail-**таба** в detail-**секцию** (`overviewBelow`, VPC-`RoutesPanel`/`SubnetCidrPanel`-стиль): `SectionHeader` с кнопкой «Добавить привилегии» в `right=`-слоте (без page-level `HeaderSlotPortal`), таблица — `ResourceTable` (визуальный паритет с access-bindings-списком), секция **добавлена на Group** (3-я секция: Обзор + Участники + Привилегии) в дополнение к User/ServiceAccount.

> [!note] UI: секция, не таб
> «Привилегии» с 1.3b — detail-**секция** (`overviewBelow`), не отдельный таб. Это сменило исходное решение Q#6 (`extraTabs`) после live-feedback — паритет с VPC `RoutesPanel`/`SubnetCidrPanel`.

> [!warning] Follow-up (не блокер)
> `kacho-proto` `ListSubjectPrivilegesRequest.subject_type` doc-comment всё ещё «group — вне scope» (stale после 1.3b) — отдельный proto-comment-фикс.

## Затронутые сущности vault

[[../rpc/iam-access-binding-service]] [[../rpc/iam-user-service]] [[../resources/iam-access-binding]] [[../resources/iam-user]] [[../resources/iam-service-account]]

## DoD

- [x] proto merged
- [x] iam #159: use-case + authz + LEFT JOIN role_name; тесты RED→GREEN
- [x] api-gateway #84: public sync-read зарегистрирован
- [x] ui #80: «Привилегии» на User/SA + «добавить привилегии» с locked subject
- [x] 1.3b: iam #162 (group subject_type + ops 0017 backfill) + ui #82 (секция вместо таба, +Group)
- [x] всё на `main` + live `fe3455` rev14
- [x] vault обновлён

## Связанные тикеты

- [[sub-phase-1.2-iam-operations]] — operations visibility (та же IAM-эпопея)
- [[sub-phase-1.4-tuple-resource-guarantee]] — 100% tuple↔resource
- [[iam-ui-vpc-parity]] — UI registry-движок (поверхность тех же ресурсов)

#kac #feature #kacho-iam #kacho-ui #kacho-api-gateway
