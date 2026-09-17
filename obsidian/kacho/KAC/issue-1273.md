---
title: "kacho#1273: iam Ф7 — ключи доступа (WebAuthn): сервер, привязка, снятие обещания аттестации"
aliases:
  - issue-1273
  - issue-1273-kaname
ticket_id: 1273
category: kac
status: test
type: feat
repos:
  - kaname
  - corelib
prs:
  - https://github.com/PRO-Robotech/kaname/pull/263
  - https://github.com/PRO-Robotech/corelib/pull/18
issue_url: https://github.com/PRO-Robotech/kacho/issues/1273
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - migrations
verified_against: "kaname release/iam-lines@4b674bf5 (PR #263 влит в линию 2026-09-17); приёмка access-keys-are-ours.md круг 6 APPROVED (kacho#1273 issuecomment-5703628145, 12e9608d…); corelib v1.9.0 = 34bc8104; локально в форме конвейера на 8eae1d05: build/vet/short/lint/gosec/гейты/каталог/169 python-проб/интеграция 5 пакетов/чарт — коды 0; -race не собирается (нет C-компилятора); стенд не поднимался"
---

# kacho#1273: ключи доступа — WebAuthn своими руками, ключ как наш ресурс `ak-<17>`

**Предмет.** Приёмка `PRO-Robotech/kaname:docs/engineering/acceptance/access-keys-are-ours.md`
(Ф7 эпика `kacho#1266`): ключ доступа человека (WebAuthn L2) хранится и проверяется
службой, а не прежним поставщиком. Шесть глаголов `AccessKeyService`, таблицы
`user_access_keys` и `access_key_challenges`, четвёртый потолок `iam.user.accessKey`,
три величины посадки `authn.access-keys.*`.

## Решения, принятые здесь (приёмка их не пересматривала)

| ось | решение | почему |
|---|---|---|
| проверяющий | свой, `internal/webauthnverify`: CBOR строгим режимом (`fxamacker/cbor`), COSE ES256/EdDSA/RS256, хэш имени доверяющей стороны, флаги; аттестация `none` **не читается** (Р4); счётчик подписей односторонний (Р6) | сторонняя библиотека тянула бы аттестационные цепочки и своё чтение флагов; Р4 запрещает обещать проверку аттестации |
| идентификатор | `ak-<17>` — префикс в каноне фундамента **до первой чеканки** (corelib#18 → v1.9.0), пин службы поднят на тег | без записи `validate.ResourceID` отвергал бы id, который служба сама выдала (класс `lim`/`mbr`); псевдоверсия коммита ветки после схлопывания не резолвится |
| испытание | одноразовое, привязано к (испытание, человек, назначение), гасится **только успехом**; срок < окна свежести (§8, декларативная проба сравнивает два объявленных литерала) | повтор чужого испытания и «испытание пережило сессию» закрыты схемой, не кодом |
| отказ утверждения | один текст на четырнадцать полос, побайтово (`refusal_bytes_test.go`) | различимый отказ — оракул существования ключа |
| потолок | `iam.user.accessKey` в закрытом множестве `posture-stated`; ручка `own-ceilings.access-keys-per-user` той же формы, что три соседних, триггер списания в транзакции вставки | Ф7-38; счётчик живёт рядом с ресурсом (`data-integrity.md`) |
| посадка | `authn.access-keys.{rp-id,origins,algorithms}`: незаданная роняет старт под `own` с именем **своей** ручки; пустой перечень происхождений — «никого» (файлом `[]`, переменной `none`) | Ф7-13; пустое ≠ «не сужаем» для перечня-разрешения |
| каталог прав | 6 записей порождены генератором края над стабами службы, слиты побайтово; `CatalogPendingEntry` ×6 до подъёма пина краем | промежуточного состояния совпадения копий нет by construction |
| аттестация как условие | обещание снято с обоих носителей: строка `authz.mdx` и деривация `kaname_device_compliance=attested` в `token_enrichment_service.go`; три пробы iamhooks правлены тем же изменением | Ф7-32/39: обещание без производителя |

## Пары RED → GREEN

`webauthnverify/verify_test.go` · `access_keys/{usecase,handler,declarative,refusal_bytes}_test.go` ·
`pg/access_key_repo_integration_test.go` · `config/access_keys_test.go` ·
`domain/access_key_ceiling_test.go` · `operationresolver` · `dto/toproto` · `metrics` · `retention` ·
`service/access_key_device_compliance_test.go` · `check/authz_page_device_condition_test.go` ·
`pg/name_form_constraint_integration_test.go` (таблица ключей — шестая в гейте формы имени, с
посевом потолка: иначе триггер списания отвергает вставку раньше формы). Все — красные по
отсутствию предмета до кода.

## Решение по переносу трёх ключей — снят вместе с предметом

Сценарии Ф7-21…24, Ф7-43, Ф7-50 описывают перенос ключей прежнего поставщика. Популяции нет:
стенд переустановлен с нуля 2026-09-16, базы эфемерны (тот же замер, что П3 в [[issue-1268]]:
`webauthn 2` у двух личностей, заводимых заново за минуту). Инструмент переноса был бы
механизмом без предмета. Редакция приёмки со снятием — kaname#269.

## Что осталось

- сквозной newman-набор ключей доступа (RS256 + BigInt в песочнице Postman, ручной CBOR) —
  kaname#268 (`Tests-followup`, заведён до посадки в ствол);
- посадка среза 3 линии в `main` — MR kaname#270; имитация клиента (ban #18) над новой
  поверхностью не проведена — агенты не запускались по указанию владельца;
- край платформы: шесть путей `accessKeys` в каталог и таблицу маршрутов — подъёмом пина
  после посадки среза 3; `CatalogPendingEntry` снимаются тогда же.

## Затронутые сущности vault

- [[resources/kaname-access-key]] — заведена этой задачей.
- [[rpc/iam-access-key-service]] — заведена этой задачей.
- [[resources/iam-user]] — четвёртый потолок вида у человека.
- [[issue-1268]] — тот же довод о снятом переносе.

#kac #kacho-iam #iam #go #migrations
