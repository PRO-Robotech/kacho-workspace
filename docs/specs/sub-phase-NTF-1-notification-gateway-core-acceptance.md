<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# Sub-phase NTF-1 (единый почтовый шлюз: ядро — лента, формат, служба notify, идентичность служб, права у kaname, флаг установки) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью
> (скилл `change-graph` §«Вердикт привязан к отпечатку»)
> **История review:** только дописывается; прежние строки не редактируются
> — **редакция 1 · 2026-09-30 · вердикта на неё НЕТ.** Отпечаток — `sha256sum <путь>`
> — **2026-09-30 · круг 1 · ⛔ ВОЗВРАТ (блокирующих 5: CONSTRUCTIBILITY ×2, NEGATIVE, FORMAT, TWIN) ·
> SHA-256 `f073429eb514b8c1db6ad385201fff8fa6459f0cb226759bdcd428431f175136` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/f073429eb514b8c1db6ad385201fff8fa6459f0cb226759bdcd428431f175136.yaml`**
> — **редакция 2 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B1-1…B1-5 круга 1; что изменено —
> §9 «Правки по кругам»
> — **2026-09-30 · круг 2 · ⛔ ВОЗВРАТ (блокирующих 2: CONSTRUCTIBILITY, COVERAGE) ·
> SHA-256 `a31661de35b29200d8016ea3957b50a87a36867cf939b7fbcb648075cf0a89d0` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/a31661de35b29200d8016ea3957b50a87a36867cf939b7fbcb648075cf0a89d0.yaml`**
> — **редакция 3 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B2-1, B2-2 и важные замечания
> круга 2; что изменено — §9 «Правки по кругам»
> — **2026-09-30 · круг 3 · ⛔ ВОЗВРАТ (блокирующих 2: CONSTRUCTIBILITY, NEGATIVE) ·
> SHA-256 `077e9fff783bad06b1a3f2f2e051e85fa26d0960d7c3aea0f16e221ea10b5260` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/077e9fff783bad06b1a3f2f2e051e85fa26d0960d7c3aea0f16e221ea10b5260.yaml`**
> — **редакция 4 · 2026-09-30 · вердикта на неё НЕТ.** Перестроена под решения диспетчера Д1–Д13
> и новое разбиение эпика на NTF-1…NTF-6: перевод писем kaname ушёл в NTF-2; субъект службы —
> служебный принципал `service:<имя>`; права — `sender` на `notification_namespace` и `reader` на
> `notification_feed`; флаг установки; лимиты notify. Закрывает B3-1, B3-2; что изменено — §9
> — **2026-09-30 · круг 4 · ⛔ ВОЗВРАТ (блокирующих 4: CONSTRUCTIBILITY ×3, SCOPE) ·
> SHA-256 `46af7f65567c232d1567255cda83f9185cb0e4c716c5a282f9ac1e859057808b` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/46af7f65567c232d1567255cda83f9185cb0e4c716c5a282f9ac1e859057808b.yaml`**
> — **редакция 5 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B4-1…B4-4 и важные замечания
> круга 4; перепись класса CONSTRUCTIBILITY по двум вопросам (решает ли код kaname исход в обход
> модели; не запрещает ли Given собственное правило документа) — §1.11 и §9
> — **2026-09-30 · круг 5 · ⛔ ВОЗВРАТ (блокирующих 2: CONSTRUCTIBILITY ×2) ·
> SHA-256 `a6cb0c1f1e022e6715abb37ba91ac03b82c44968c1c5ebfc6bbb883210dc6e89` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/a6cb0c1f1e022e6715abb37ba91ac03b82c44968c1c5ebfc6bbb883210dc6e89.yaml`**
> — **редакция 6 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B5-1, B5-2 и замечания N5-1, N5-2
> круга 5; класс «факт о дереве взят из прозы, а не из разобранного вывода команды» закрыт по всему
> документу: §1.11 классифицирует построчно вывод расширенного предиката, слово вида — из словаря
> corelib; что изменено — §9
> — **2026-09-30 · круг 6 · ⛔ ВОЗВРАТ (блокирующих 1: PRODUCER) ·
> SHA-256 `0311f05f091e1abe32482e8ba06bc85e3192b1402cd2bc11e82327aa90909cbb` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/0311f05f091e1abe32482e8ba06bc85e3192b1402cd2bc11e82327aa90909cbb.yaml`**
> — **редакция 7 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B6-1 и замечания N6-1, N6-2
> круга 6; класс «существующей проверке приписан исход, которого она дать не может» закрыт по всему
> документу переписью каждого названного существующего держателя против его предмета (§9)
> — **2026-09-30 · круг 7 · ⛔ ВОЗВРАТ (блокирующих 1: PRODUCER) ·
> SHA-256 `12a6692569ca4c0dbfa93cbd84fc7a2f5fab645955092b1e1ee32ed0715430a4` ·
> `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/12a6692569ca4c0dbfa93cbd84fc7a2f5fab645955092b1e1ee32ed0715430a4.yaml`**
> — **редакция 8 · 2026-09-30 · вердикта на неё НЕТ.** Закрывает B7-1 и замечания N7-1, N7-2
> круга 7; класс «держателю приписан исход, которого он на исправном продукте не даст» закрыт по
> всему документу переписью каждого названного **нового** держателя, чей предикат читает уже
> существующее дерево (§9)
> **Дата:** 2026-09-30
> **Эпик/issue:** эпик `PRO-Robotech/kacho#2914`; задачи под-фазы — `PRO-Robotech/kacho#2915`
> (notify, раздел «notify»), `PRO-Robotech/corelib#77` (фундамент, раздел «corelib»),
> `PRO-Robotech/kaname#484` (модель прав и решение на письмо, раздел «kaname»),
> `PRO-Robotech/kacho#2916` (политика выпуска сертификатов, раздел «NS»); документ ведётся задачей
> `PRO-Robotech/kacho-workspace#880`

- **Дом документа** — воркспейс `docs/specs/`: предмет кросс-репозиторный (corelib, kaname, kacho),
  а у приёмки домов два, и кросс-доменный предмет живёт здесь (`.claude/rules/polyrepo.md` note
  «У приёмки домов ДВА»). Пакет изменения заведён — `docs/changes/issue-2915/`; его манифест
  называет этот документ ссылкой и отпечатком и копии приёмки не несёт.
- **Формат:** Given-When-Then, только markdown, только наблюдаемое поведение. Кода здесь нет.
- **Публичный репозиторий:** оба ствола публичны; сборки «точная координата + условие + следствие»
  в документе нет, ссылок на рабочие каталоги задач — тоже (`.claude/rules/security-disclosure.md`
  §«Публичные артефакты»). Защитные меры названы требованиями и ручками, без описания текущих
  слабых мест и без пошаговых инструкций атаки.
- **Разделы для предикатов задач:** «corelib» — стадия S1 (группы A, B, C, D, M); «kaname» —
  стадия S2 (группа F); «notify» — стадии S0, S3, S5 (группы C01–C02, E, G, H, N, I, K, L);
  «NS» — стадия S4 (группа J).

---

## §0 Обзор

### 0.1 Что реализуется

Появляется служба `services/notify` в kacho — единственное место установки, где будут креды почты
(Д1; остальные держатели снимаются в NTF-2, §4). Служба-источник не отправляет почту и не знает ни
пароля, ни адреса ретранслятора: письмо — строка в **ленте** источника, поставленная в транзакции
события сгенерированной функцией `SendX(ctx, tx, XAttrs)`. notify узнаёт о строке сигналом
**существующей** подписки источника (событие несёт только идентификатор ленты), забирает тело
вызовом «взять порцию» (`Claim`), спрашивает у kaname право на каждое письмо, собирает письмо из
**блоков** шаблона в **общем макете** (HTML с inline CSS + текст, `multipart/alternative`),
отправляет ретранслятору по TLS и подтверждает исход (`Ack`).

Общее для всех источников — в corelib: `notify/feed`, `notify/spec`, `cmd/notifygen` и звено
**идентичности служб**: проверенный сертификат службы с точным SAN становится служебным
принципалом `service:<имя>` на закрытом перечне методов (Д2). Право «служба X шлёт письма своего
пространства» — отношение модели kaname, выдаётся одной строкой манифеста модуля (Д4). Флаг
установки решает, генерирует ли прикладная служба почтовые запросы вообще (Д7). Лимиты notify
держат ящик получателя поперёк всех источников (Д11). Политика выпуска сертификатов (NS)
закрепляет идентичность в сертификате за своей службой.

Настоящих источников в NTF-1 нет: kaname становится источником в NTF-2, модули kacho — в NTF-3.
Ядро доказывается фикстурными источниками в пробах и **стендовой пробой-источником**
`notify-probe` — службой kacho на тех же corelib-механизмах, которая поднимается только в
стендовых профилях (Р16) и проходит тот же путь, что пройдёт любой модуль.

### 0.2 Требования владельца — дословно и куда каждое ведёт

| # | требование владельца (дословно, 2026-09-29/30) | решения | сценарии |
|---|---|---|---|
| О1 | «единая точка у кого есть креды от почты» | Р1 | NTF1-I01, NTF1-I02, NTF1-G19 |
| О2 | «простой формат добавления шаблонов» | Р7, Р8, Р17 | NTF1-A01…A09, NTF1-D01…D06, NTF1-K01…K03 |
| О3 | «права доступа сервисов к их шаблонам (не должно быть возможности где сервис А может отправлять нотификации от сервиса Б)» | Р2, Р4, Р5, Р6, Р12 | NTF1-G02, NTF1-C03…C06, NTF1-M01…M10, NTF1-F01…F22, NTF1-J01…J05 |
| О4 | «… html + css и набор атрибутов …» | Р7 | NTF1-A01…A07, NTF1-G03…G05 |
| О5 | «Акцент на максимальную безопасность» | Р2, Р6, Р7, Р10, Р11, Р12, Р13 | NTF1-B03…B07, NTF1-G05…G10, NTF1-G13, NTF1-G20…G22, NTF1-H01…H10, NTF1-M10, NTF1-F12, NTF1-F22 |
| О6 | «на максимальную простоту» | Р5, Р17 | NTF1-F01, NTF1-K01…K03 |
| О7 | «максимально простая поддержка» | Р9, Р11, Р17, Р18 | NTF1-G11, NTF1-G12, NTF1-G14, NTF1-G17, NTF1-N09, NTF1-H09 |
| О8 | «канаме использует шлюз для отправки нотификации, но шлюз проверяет доступы у канаме» | Р3, Р5 | NTF1-F01…F22, NTF1-G22 |
| О9 | «Общий макет + блоки» | Р7 | NTF1-A02, NTF1-G03 |
| О10 | «вынести в корлиб или общую библиотеку, что бы не дублировать код» | Р2, Р8 | NTF1-A09, NTF1-B01…B24, NTF1-D01…D06, NTF1-M01…M09 |
| О11 | «нотификатор должен подписываться на события нотификации каждого модуля для рективной обработки» | Р4 | NTF1-E01…E04 |
| О12 | «К модулю нотификации должны быть подключены все модули …; … отключать …» | — (предмет NTF-3 и NTF-6, §4); ядро даёт процедуру подключения | NTF1-K03 |
| О13 | «заложи вопрос с рейтлимитами и защиту против спама …» | Р10 (часть notify); остальное — NTF-2, NTF-3 (§4) | NTF1-B08, NTF1-B09, NTF1-H01…H10, NTF1-L03, NTF1-L04 |
| О14 | «забудь про кастомные. Заложи только флаги на приклад генерить почтовые запросы в аутбокс или нет. Что бы если нет шлюза не генерить нагрузку» | Р7, Р9 | NTF1-N01…N09, NTF1-G19 |
| О15 | «прода нет так что можно перестраивать все подряд» | Р15 | §3 |
| О16 | «Перспективность, максимальная безопасность, поддреживаемость»; «все решения принимаешь ты» | §2 целиком | — |

---

## §1 Что верно в дереве — измерено, а не предположено

**Ревизии измерения:** воркспейс `13e0d0c1`; `PRO-Robotech/kacho` `origin/main` = `1d42a6728bf`;
`PRO-Robotech/kaname` `origin/main` = `cbbac984b`, ветка эпика `origin/357` = `734f69fb4`;
`PRO-Robotech/corelib` `origin/main` = `34bc810` (= тег `v1.9.0`). Трекер — 2026-09-30.

### 1.1 notify нет; отправителей почты среди служб kacho нет

| утверждение | команда | результат |
|---|---|---|
| служб kacho | `git -C kacho ls-tree --name-only origin/main services/` | compute, geo, nlb, registry, storage, vpc — `notify` нет |
| отправителей в не-тестовом Go kacho | `git -C kacho grep -lE '"net/smtp"\|"html/template"\|"mime/multipart"' origin/main -- '*.go' ':!*_test.go'` | 2 файла, оба — гейты; отправителей 0 |
| отправитель в kaname | `git -C kaname grep -l '"net/smtp"' <ref> -- '*.go' ':!*_test.go'` на `origin/main` и `origin/357` | по 2 файла: отправитель и гейт путей отправки — снимаются в NTF-2 |
| второй отправитель — почтовый процесс поставщика личности | `git -C kacho grep -ci smtp origin/main -- deploy/helm/umbrella/charts/kaname/templates/_kratos-identity.tpl` | 24 — снимается в NTF-2 |

### 1.2 Потоковый контракт один, и занят подпиской

`git -C kacho grep -h 'returns (stream' origin/main -- proto | wc -l` → **1**
(`proto/corelib/subscription/subscription_service.proto`, `Subscribe`). Второго потокового
контракта не заводится (`api-sub-singularity-predicate`).

### 1.3 Посылка «подписчик-служба авторизуется по SAN» опровергнута — подтверждаю опровержение диспетчера

- `corelib/subscription/server.go` @`34bc810`, `Subscribe`, шаг 1 «Личность»:
  `listnarrow.SubjectFromContext` → при отказе `PERMISSION_DENIED` «subscription requires an
  authenticated caller».
- `corelib/listnarrow/subject.go` (`SubjectFromContext`) берёт принципала из
  `operations.PrincipalFromContextOK` и называет субъекта через `authz.TenantSubject`, чей словарь
  **закрыт**: `user`, `service_account` (`corelib/authz/types.go`, `TenantSubject`).
- `corelib/grpcsrv/cert_identity.go` @`34bc810`, `withTrustedPrincipal`: принципал в контексте —
  только **пересланный** доверенным пересылающим; системным он намеренно не засевается.
  Проверенный сертификат службы, которая ничего не пересылает, принципалом не становится.
- `corelib/authz/interceptor.go` @`34bc810`: извлечение субъекта (шаг 3) стоит **перед** веткой
  `ScopeFiltered`; извлекатель по умолчанию — `defaultSubjectExtractor`
  (`authz/subject_extract.go`), читающий тот же пересланный принципал.

Следствие: служебного субъекта из сертификата в дереве нет; его заводит Р2.

### 1.4 В модели kaname нет ни служебного принципала, ни типов нотификаций

`git -C kaname show 734f69fb4:internal/authzmodel/fga_model.fga | grep -c '^type '` → **32**;
`… | grep -cE '^type (service|notification_feed|notification_namespace)$'` → **0**.
Тенантская выдача формирует субъект в одном месте — `internal/domain/subject.go`
(`FGASubjectRef`): `service_account`, `group`, остальное — `user`. Субъекта `service:` не
производит ни одна тенантская поверхность.

### 1.5 У службы доступа своей служебной записи нет — решение MRW-1 Р1

`internal/servicemanifest/manifest.embedded.yaml` @`734f69fb4`, строки 66–67: «Подразделов
`serviceAccounts` и `joins` у этого раздела НЕТ … своей служебной записи у службы доступа не
бывает». Держатель — `internal/servicemanifest/seed_form_test.go`,
`TestMRW07_GroupWithItsGrantIsAccepted`: машинно он судит только подразделы `serviceAccounts` и
`joins`, но его сообщение называет основанием решение Р1 («своей служебной записи у службы не
бывает»). Служебный принципал `service:kaname` был бы именно такой записью, поэтому документ
выбирает исключение, названное диспетчером на этот случай (Р3), а не замещение MRW-1 Р1.

### 1.6 Где живут нужные звенья

- сервер подписки kaname — `cmd/kaname/subscription_wiring.go` (`subscription.NewServer`);
  клиент подписки в kacho один — край (`gateway/cmd/api-gateway/subscription_stream.go`);
- на внутреннем слушателе kaname звена `corelib/authz.Interceptor` нет (цепочка в функции
  подъёма слушателей `cmd/kaname/serve.go`: `CallerPolicy`, пол адресов, пол чтения, пол `acr`,
  `DenyDetailUnary`); перечень точных SAN, задаваемый оператором, у `CallerPolicy` уже есть —
  `WithSANAllowlist` (`internal/authzguard/caller_policy.go`), с отказом на пустом перечне;
- словарь запрещённых к прокси-регистрации типов — `corelib/authz/proxytuple/policy.go`,
  `forbiddenObjectTypes`;
- манифесты модулей kacho — `services/{compute,nlb,registry,storage,vpc}/manifest.yaml`
  (`git -C kacho ls-tree -r --name-only origin/main | grep 'services/.*/manifest.yaml'` → 5);
  валидатор — kaname `tools/modulemanifestcheck`.

### 1.7 Раскладка proto фундамента

`git -C kacho ls-tree -r --name-only origin/main proto/corelib` → 8 файлов; пакеты
`corelib.api.v1`, `corelib.authz.v1`, `corelib.operation` ×3, `corelib.quota.v1`,
`corelib.subscription` ×2; новейший механизм (`subscription`) — без сегмента версии. Стабы — в
corelib `api/corelib/…`; копии трёх контрактов записаны долгом `PRO-Robotech/corelib#9`.

### 1.8 Фундамент corelib: что есть, чего нет

`outbox.Emit` имеет фиксированную схему и ленте не годится; `outbox.SanitizeTable`,
`outbox/drainer` (классификатор исходов), `outbox/metrics`, `outbox.NewQueueSweeper` — годятся;
AEAD в corelib — 0 файлов (`grep -rln 'crypto/cipher\|NewGCM\|chacha20poly1305'`); генераторов и
`//go:generate` — 0; прецедент «corelib поставляет SQL, служба рендерит миграцию» —
`corelib/quota/refusal.go` (`//go:embed`).

### 1.9 Поставка: флага нет, приёмник стенда есть

- `git -C kacho grep -c notifications origin/main -- deploy/helm | wc -l` → **0**: флага нет;
- приёмник писем — `deploy/helm/umbrella/templates/mail-receiver.yaml`, блок `mailpit`
  (`values.yaml:319` — `enabled: false`; включён в `values.dev.yaml` и `values.own-stand.yaml`),
  гейт — `deploy/mail_receiver_core_test.go`;
- цепочки стендов — `deploy/stacks.txt`: `dev`, `dev-prod`, `prod`, `own`, `fe3455`,
  `prorobotech`, `a8f60d`; цепочка `prod` = `values.prod.yaml`.

### 1.10 Пакет изменения и трекер

`docs/changes/issue-2915/change.yaml` существует (`lifecycle_state: ISSUE_READY`,
`co_issues: [corelib#77, kaname#484, kacho#2916]`). Тексты задач #2915, #2916, corelib#77,
kaname#484 ссылаются на `sub-phase-NTF-1-notify-core-acceptance.md`, а документ называется
`sub-phase-NTF-1-notification-gateway-core-acceptance.md` — правка ссылок в задачах названа в
возврате автора (строка «нужен следующий»).

### 1.11 Исход проверки прав в kaname решает не только модель — перепись мест надзора построчно

Дверь проверки прав kaname отвечает тремя входами, и у каждого своя функция вердикта
(`internal/service/authorize_service.go` @`734f69fb4`):

| вход | кто спрашивает | функция вердикта | несёт |
|---|---|---|---|
| `InternalIAMService/Check` (обработчик `internal_iam/handler.go` делегирует `AuthorizeService.CheckRelation`) | перехватчик прав **каждой** службы kacho, в том числе сервер ленты источника (`Claim`, `Ack`) | `verdictForRelation` | субъект, **отношение**, объект; действия нет |
| публичный `AuthorizeService/Check` (обработчик `authorize/handler.go`) | край, клиенты | `check` → `verdict` либо ветка «вопроса нет» (`superGateDecides`) | субъект, **действие**, необязательное `required_relation`, ресурс |
| публичный `AuthorizeService/BatchCheck` (тот же обработчик) | `listnarrow` — сужение строк списка и подписки у каждой службы kacho | `BatchCheck` → `resolveRun` (прогон «вопроса нет» и пообъектный отказ) | как у `Check`, до 100 пунктов |

**Перепись.** Предикат прошлой редакции
(`grep -n 'isClusterAdmin\|superGateDecides\|SubjectIsClusterAdminPlainE'`, 29 строк) сам молчал о
части предмета: он не видит вызовов обёрток `IsClusterAdmin`, `IsClusterAdminE`,
`SubjectIsClusterAdmin`, `SubjectIsClusterAdminE`, задающих тот же вопрос надзора. Предикат этой
редакции — по всему семейству имён, словами целиком:

`git -C kaname grep -nE '\b(IsClusterAdmin|IsClusterAdminE|SubjectIsClusterAdmin|SubjectIsClusterAdminE|SubjectIsClusterAdminPlainE|isClusterAdmin)\b|superGateDecides' 734f69fb4 -- '*.go' ':!*_test.go'`
→ **62** строки. Контроль с другой стороны — прямые вопросы об отношении надзора:
`git -C kaname grep -n '"system_admin"' 734f69fb4 -- '*.go' ':!*_test.go' ':!*.pb.go'` → **11** строк.
Каждая строка обоих выводов получила класс; суммы классов равны выводам.

**Класс «обобщённая дверь» — тип объекта приходит параметром; 8 строк, 7 мест. Касаются типов Р5 —
все семь, и все семь входят в перечень путей надзора Р5:**

| # | строка | функция | вход, который до неё доходит |
|---|---|---|---|
| Д-1 | `authorize_service.go:390`, `:395` | `check`, ветка «вопроса нет» (действие не разрешается в отношение либо идентификатор `*`) | публичный `Check` |
| Д-2 | `authorize_service.go:552` | `verdict` — надзор на отказе модели | публичный `Check` с разрешённым отношением |
| Д-3 | `authorize_service.go:770` | `verdictForRelation` — надзор на отказе модели | `InternalIAMService/Check` |
| Д-4 | `authorize_service.go:1081` | `resolveRun`, прогон «вопроса нет» | `BatchCheck` |
| Д-5 | `authorize_service.go:1123` | `resolveRun`, пообъектный отказ | `BatchCheck` |
| Д-6 | `authzguard/own_door.go:523` | `checkAdapter.Check` — дверь собственного публичного слушателя kaname (`NewOwnDoor`, `cmd/kaname/serve.go`) | публичные методы kaname по их каталогу прав |
| Д-7 | `authzguard/read_authz.go:76` | `AllowsVerb` (и `AllowsVGet`) — надзор спрашивается **первым** | читающие стражи kaname: 7 вызывающих, `git -C kaname grep -n 'AllowsVerb(\|AllowsVGet(' 734f69fb4 -- '*.go' ':!*_test.go'` → 10 строк = 7 вызовов + определения и обёртка |

Д-6 и Д-7 сегодня типов Р5 не получают: каталог публичных методов kaname не называет этих типов, а
7 вызывающих `AllowsVerb` передают литералы `account`, `project`, `iam_group`,
`iam_service_account`, `iam_user`. Документ всё равно вносит их в перечень, а не держит довод
«сегодня не доходит»: у обобщённой двери тип — параметр, и довод истёк бы с первым же вызывающим,
передавшим тип Р5. Предикат перечня стоит во всех семи местах.

**Класс «место с закреплённым предметом» — тип объекта или вопроса закреплён самим use-case;
14 строк. Типов Р5 не касаются:**

| строки | функция | о чём решает | почему не типы Р5 и чем держится |
|---|---|---|---|
| `access_binding/helpers.go:170`, `:289`; `list.go:243`; `list_by_role.go:163`; `subject_read_authority.go:189` | `requireGrantAuthority`, `fgaHoldsAdminE`, `Execute` (список привязок), `grantAuthorityVerdict`, `subjectReadAuthority` | право выдавать и читать **привязки доступа** | привязка к типам Р5 невыразима: субъект `service` привязкой не выдаётся, а отношения `reader`/`sender` модель допускает только субъекту `service` — NTF1-M10 (а), `tools/modelcanoncheck` |
| `account/list.go:176`, `group/list.go:131`, `project/list.go:160`, `role/list.go:172`, `service_account/list.go:131`, `user/list.go:133` | `Execute` списков | видимость строк **своего** типа kaname | тип списка закреплён литералом use-case |
| `account/list_all_operations.go:139` | `requireAccountViewAuthority` | чтение операций аккаунта | объект — `account` |
| `authorize/caller_authority.go:112` | `authorizeCaller` | можно ли **задать** вопрос о чужом субъекте | решает допустимость вопроса, а не его ответ: ответ по-прежнему даёт дверь Д-1…Д-5 |
| `module/authz.go:50` | `requireClusterSystemAdmin` | право на методы модулей | объект — `cluster` |

**Класс «определение или обёртка» — 11 строк:** `cluster_admin_shortcircuit.go:30`, `:38`, `:53`,
`:61`, `:68`, `:69`, `:92`; `subject_question.go:52`; `authorize_service.go:331`, `:333`, `:349`.
Своего исхода не решают — решает вызывающий.

**Класс «план и группировка» — 7 строк, исхода не решают, только несут метку «вопроса нет»:**
`authorize_service.go:442` (поле), `:482`, `:510` (`planCheck` ставит метку), `:890`, `:896`
(`BatchCheck` сводит пункты в прогоны), `:1037` (`runKeyOf`), `:594` (`NeutralDenyReasons` — только
текст отказа).

**Класс «комментарий» — 22 строки:** `access_binding/helpers.go:163`, `:245`, `:273`;
`access_binding/list.go:179`; `account/list_all_operations.go:134`; `module/authz.go:25`, `:26`;
`cluster_admin_shortcircuit.go:8`, `:27`, `:41`, `:51`, `:64`, `:73`, `:83`; `subject_question.go:11`,
`:43`; `check/authz_wrapper_outcome_lanes.go:9`, `:10`; `publicauthzcensus/census.go:218`,
`publicauthzcensus/exempt.go:59`; `authorize_service.go:316`, `:440`.

8 + 14 + 11 + 7 + 22 = **62**.

**Контрольный вывод `"system_admin"` — 11 строк, надзора над чужим объектом среди них нет:**
вопрос о праве на сам объект `cluster` — `cluster/admin_authz.go:73`,
`internal_iam/force_logout.go:298`, `internal_operations/list_iam_operations.go:100`,
`authorize/whoami.go:126` (флаг для консоли); запись кортежей выдачи администратора —
`cluster/helpers.go:81`, `access_binding/tuples.go:279`, посев `seed/bootstrap_admin.go:229`;
тело определений надзора — `cluster_admin_shortcircuit.go:99`, `subject_question.go:56`,
`own_door.go:534` (`isSuperGateQuestion`); стенд замера `tools/authzformbench/fullworld.go:270`.
Право на `Revoke`/`Restore` Р5 — вопрос первого вида и перечнем не затронуто.

**Прочие пути, меняющие исход, — не надзор:**

| путь | где | в какую сторону | касается типов Р5 |
|---|---|---|---|
| допуск субъекта (`admission.Subject`, Р4а kaname#456) | `check`, `CheckRelation` → `admissionDenied` | только «да» → «нет», и только человеку с неподтверждённым адресом; не-человек допущен | нет: разрешения не добавляет |
| `Breakglass` звена прав kacho | corelib `authz/interceptor.go` | пропуск без проверки | нет: в боевой посадке запрещён стражем (`sec-bootguard-fail-closed-axes`) |

**Держатель переписи** — гейт дерева kaname (NTF1-F12): вызовы семейства находятся разбором по
идентичности объекта (`go/types`), а не по имени; каждое найденное место сверяется с ведомостью
классов в дереве kaname; место вне ведомости, строка ведомости без места и место класса
«обобщённая дверь» без предиката перечня — находка с координатой; гейт печатает число осмотренных
файлов и мест по классам и падает на пустом обходе. Следствие для документа — Р5 п. «надзор не
применяется».

---

## §2 Решения — ратифицировать явно, ревьюер проверяет каждое

Р1–Р11 переносят решения диспетчера Д1–Д7, Д11 и следствия Д12–Д13 в части ядра; Р12–Р18 —
решения автора, закрывающие пробелы (§7). Открытых развилок документ не несёт.

### Р1 (Д1). notify — дом кредов почты; свой чарт; входящих вызовов отправки нет

- служба `services/notify` в kacho; секрет почты монтируется только в неё; своя база
  `kacho_notify` — только для счётчиков лимитов (Р10), без адресов открытым текстом;
- свой чарт `deploy/helm/notify/`: зонтик kacho включает его подчартом, и он же ставится рядом с
  самостоятельной kaname (NTF1-I06);
- gRPC-сервисов notify не обслуживает вовсе и gRPC-слушателя не поднимает: единственный слушатель —
  диагностический HTTP (`/healthz`, `/readyz`, `/metrics`, как у служб kacho — проба готовности по
  HTTP); глагола «отправь письмо» нет (NTF1-G19);
- **основание:** О1; О5 — поверхности, которой нет, атаковать нельзя.

### Р2 (Д2). Звено идентичности служб: проверенный сертификат → служебный принципал `service:<имя>`

Заводится в corelib (S1) и ставится одинаково на обоих слушателях службы и в звено прав
`authz.Interceptor` kacho — до ветки `ScopeFiltered`:

1. **Закрытый перечень методов.** Композиционный корень передаёт звену перечень полных имён
   методов; вне перечня субъект из сертификата не появляется (исход прежний). Метод перечня обязан
   быть в каталоге прав службы — иначе отказ старта с именем метода.
2. **Таблица `{точный SAN → имя службы}`.** Строится из декларации `<служба>.spiffe` (Р12);
   сравнение — побайтовое равенство полного URI, домен доверия входит в ключ, разбора SAN на
   сегменты нет. SAN вне таблицы субъекта не даёт. Имя — DNS label из закрытого перечня служебных
   принципалов модели (п.5).
3. **Второй носитель, а не засев первого.** `operations.PrincipalFromContext` его не видит.
   `listnarrow.SubjectFromContext` и извлекатель субъекта `authz.Interceptor` зовут **одну**
   функцию corelib: пересланный доверенным пересылающим принципал решает, если он есть; иначе, если
   метод в перечне и сертификат проверен, — `service:<имя>`; иначе «субъекта нет»
   (`sec-one-predicate-three-readers`). Пересылка личности от пира вне круга пересылающих
   по-прежнему снимается.
4. **Не владелец операций.** Субъект из сертификата не становится принципалом операции и не
   совпадает с системным принципалом (NTF1-M06). Пол `acr` оценивается общей
   `grpcsrv.EvaluateStepUp` как для машинного принципала.
5. **Служебный принципал заводится только манифестом модели.** В модели kaname — тип `service`
   без собственных отношений; объект `service:<модуль>` существует, когда доставленный манифест
   модуля с `module: <модуль>` несёт раздел `notifications` (Р5), а `service:notify` — манифестом
   `services/notify/manifest.yaml`. Тенантские поверхности субъекта `service:` не производят:
   выдача с таким типом отвергается; типы `service`, `notification_feed` и `notification_namespace`
   внесены в `forbiddenObjectTypes` (`corelib/authz/proxytuple/policy.go`) — все три вне доменов-
   эмитентов, и гейт `TestForbiddenProxyObjectTypesAgreeWithTheModel` kacho (сторона Б) требует
   каждого такого типа модели в наборе; на этой же записи держится отказ `RegisterResource` для
   трёх типов (NTF1-M10 (б)).
6. **Стражи старта:** перечень непуст ⇔ таблица непуста; повтор SAN или имени; метод вне каталога;
   имя вне формы — отказ старта с именем ручки и значением (NTF1-M09).
7. **Самоотчёт:** перечень методов и строки таблицы входят в самоотчёт посадки и оцениваются
   `assert-production-posture.sh` (`sec-forwarder-in-selfreport-and-gate`).

**Основание:** О3, О10; факт §1.3. Прочие внутренние вызовы модулей не меняются (NTF1-M07).

### Р3 (Д2, исключение). У kaname служебного принципала нет; её пространство авторизуется сертификатом

- `service:kaname` не заводится: это была бы своя служебная запись службы доступа, которую
  запрещает MRW-1 Р1 (§1.5). MRW-1 Р1 не замещается;
- пространство `kaname` (литерал; не выводится из `module: iam` её манифеста) — **записанное
  исключение**: запись перечня источников notify для `kaname` несёт `authorization: certificate`;
  notify проверяет точный SAN сервера ленты kaname из декларации `kaname.spiffe` и `ResolveSend`
  по этому пространству не зовёт (NTF1-G22). Исключение допустимо только для `kaname` — иная
  запись с `certificate` отвергается стражем старта notify;
- рычаг оператора по пространству `kaname` — флаг Р9 (выключить генерацию), а не `Revoke`;
- манифест службы доступа может нести только `notifications: {readers: [notify]}` без
  `namespace` — это выдаёт `service:notify reader notification_feed:kaname`, субъекта kaname не
  создаёт (NTF1-F21). Сама лента kaname и эта строка манифеста появляются в NTF-2;
- **основание:** О8 («шлюз проверяет доступы у канаме»: служба доступа не спрашивает сама себя);
  решение диспетчера на случай §1.5.

### Р4 (Д3). Реакция — сигнал существующей подписки; тело — `Claim`/`Ack`; второго потока нет

- notify — подписчик `corelib.subscription.InternalSubscriptionService/Subscribe` каждого
  источника своего перечня (Р6) — LISTEN-сигнал, почти сразу;
- ключ `notification` в `Mapping.Kinds` источника — **слово журнала владельца**, наружу оно не
  выходит; ключ привязан к типу модели `notification_feed` и действию `reader`. Словарь видов
  `Subscribe` собирается из `ObjectType` (`corelib subscription/journal.go`, `KindDictionary`), поэтому
  **на проводе вид — `notification_feed`**: подписка `kinds: ["notification_feed"]`, событие вида
  `notification_feed`. Во всех сценариях ниже вид назван словом провода. Объект события —
  `notification_feed:<модуль>`; событие несёт только
  идентификатор ленты и род изменения, состояние — словом в `state_unavailable`: ни атрибутов, ни
  адресата, ни имени шаблона;
- по событию notify перечитывает (`sub-refetch-not-apply`): вызывает `Claim`; `Claim` зовётся
  также при каждом (пере)открытии потока и по таймеру (ручка без умолчания) — подписка ускоряет,
  но не условие корректности;
- `Claim`/`Ack` ленты (`corelib notify/feed`) авторизуются вопросом
  `Check(<субъект>, reader, notification_feed:<модуль>)`; `reader` в модели выдаётся **только**
  субъекту `service:notify` — валидатор манифеста отвергает иного читателя (NTF1-F03), а надзор
  администратора облака на этом типе не применяется (Р5, NTF1-F12, F22), поэтому тело письма
  забрать может только notify;
- правило `sub-consumer-opens` — «край либо notify» (внесено задачей `kacho-workspace#881`);
- **основание:** О11; единственность потока (§1.2).

### Р5 (Д4). Право на отправку — `sender` на пространство; одна строка манифеста; решение kaname на каждое письмо

- в модели kaname:
  - `type service` — служебный принципал (Р2 п.5);
  - `type notification_feed` — `define reader: [service]`;
  - `type notification_namespace` — `define sender: [service]`;
  без каскада, без подстановочного знака, без членства групп;
- **форма строки манифеста модуля** — одна строка:
  `notifications: {namespace: <модуль>, readers: [notify]}`. Валидатор принимает её, только если
  `namespace` равно `module` этого манифеста и `readers` ровно `[notify]`. Применитель посева пишет
  `service:<модуль> sender notification_namespace:<модуль>` и
  `service:notify reader notification_feed:<модуль>`. Прочие поверхности эти отношения не пишут;
- **запись выдачи** в kaname: `{пространство, выдано, отозвано, отсечка}`; кортеж `sender` — её
  проекция через очередь kaname в той же транзакции. Посев идемпотентен: создаёт запись, если её
  нет, и не меняет существующую ни в одном поле (надгробие уважает). **Отсечка** — момент
  последнего `Restore`; у выдачи, ни разу не восстановленной, её нет;
- **запись шаблона** `{пространство, шаблон, отозвано, отсечка шаблона}` — одна на пару
  (уникальность в базе), заводится первым `Revoke(namespace, template)`; оси ленты и шаблона
  независимы;
- на каждое письмо notify зовёт `kaname.cloud.iam.v1.InternalNotificationGrantService/ResolveSend
  (namespace, template, enqueued_at)`. Право вызова — у субъекта, который `reader` ленты этого
  пространства (`Check(субъект, reader, notification_feed:<namespace>)`, заданный **той же дверью
  проверки прав** kaname, что отвечает `InternalIAMService/Check`, — не своим вопросом к хранилищу
  отношений); иначе `PERMISSION_DENIED`. Исходов три:

| исход | условие | что делает notify |
|---|---|---|
| `ALLOW` | выдача есть, надгробий ленты и шаблона строки нет, и `enqueued_at ≥ отсечка + полоса` для **каждой** имеющейся отсечки | отправляет |
| `NOT_YET_GRANTED` | записи выдачи нет и надгробия нет (включая неизвестное пространство) | `DEFER(grant_skew)`, попытку не тратит, тревога сразу |
| `REVOKED` | надгробие ленты либо шаблона строки, либо `enqueued_at < отсечка + полоса` по ленте или по шаблону строки | терминальный `DENIED(revoked)`, секрет стёрт |

  **полоса** — ручка kaname `notificationCutoffGuard` (граница `[1s..10m]`, ориентир 30s; без
  значения — отказ старта): `enqueued_at` ставят часы базы источника, отсечку — часы kaname, и
  строка, поставленная до `Restore` по часам kaname, не должна пройти из-за опережающих часов
  источника. Цена названа: законная строка, поставленная в пределах полосы после `Restore`,
  получает `REVOKED` (fail-closed). Строка, поставленная до первой выдачи, после появления выдачи
  — `ALLOW`. Существование шаблона kaname не судит — его судит notify (`template_skew`);
  недоступность kaname — `DEFER(platform_unavailable)`;
- `Revoke(namespace[, template])`, `Restore(namespace[, template])` — внутренний слушатель kaname,
  ответ `Operation`, право — администратор кластера (образец `RevokeAdmin`,
  `proto/kaname/cloud/iam/v1/internal_cluster_service.proto`). `Revoke(namespace)` пишет надгробие
  и снимает кортеж `sender` одной транзакцией; `Restore(namespace)` снимает надгробие, ставит
  отсечку и возвращает кортеж; варианты с шаблоном работают с записью шаблона и кортеж не трогают;
- **переходы — CAS в базе kaname** (`UPDATE … WHERE … AND отозвано IS [NOT] NULL`, вставка записи
  шаблона с отказом от конфликта одним оператором); ноль строк → классификация по состоянию.
  Отказы синхронны, `Operation` при отказе не создаётся; `ErrorInfo.domain` — домен отказов kaname
  (`refusaldomain.For(refusaldomain.ServiceIAM)`), `metadata = {resource_type:
  notification_namespace, resource_id}`:

| вход | код | `reason` | текст |
|---|---|---|---|
| `namespace` пуст | `INVALID_ARGUMENT` | `INVALID_RESOURCE_ID` | `namespace: required` |
| `namespace` не DNS label | `INVALID_ARGUMENT` | `INVALID_RESOURCE_ID` | `invalid notification_namespace id '<X>'` |
| `template` не DNS label | `INVALID_ARGUMENT` | — ; `field = template` | `template: invalid name '<X>'` |
| `enqueued_at` не задан (`ResolveSend`) | `INVALID_ARGUMENT` | — ; `field = enqueued_at` | `enqueued_at: required` |
| выдачи нет (`Revoke`/`Restore`, с шаблоном и без) | `NOT_FOUND` | `RESOURCE_NOT_FOUND` | `NotificationNamespace <id> not found` |
| `Revoke` отозванного | `FAILED_PRECONDITION` | `NOTIFICATION_GRANT_STATE` | `NotificationNamespace <id> is already revoked` (с шаблоном: `… template <name> is already revoked`) |
| `Restore` без надгробия | `FAILED_PRECONDITION` | `NOTIFICATION_GRANT_STATE` | `NotificationNamespace <id> is not revoked` (с шаблоном: `… template <name> is not revoked`) |

  `ResolveSend` на неизвестное пространство ошибкой не отвечает: исход `NOT_YET_GRANTED`;
- объекты `notification_feed:<модуль>` и `notification_namespace:<модуль>` адресуются именем модуля:
  это неизменяемый идентификатор из закрытого перечня модулей (как `cluster_root`), а не
  косметическое имя ресурса арендатора — `ban15-id-addressing` не задет;
- **надзор администратора облака на типах Р5 не применяется** (отступление от
  `hard-cloud-admin-cascade`, §3 З5): закрытый перечень типов объектов
  `{notification_feed, notification_namespace}` объявлен в kaname **одним** местом — рядом с дверью
  проверки прав. Перечень путей надзора — **все семь мест класса «обобщённая дверь» переписи
  §1.11**: Д-1 `check`, ветка «вопроса нет»; Д-2 `verdict`; Д-3 `verdictForRelation` (вход
  `InternalIAMService/Check`, которым идут `Claim`, `Ack` и перехватчик прав каждой службы kacho);
  Д-4 и Д-5 `resolveRun`, обе ветки (вход `BatchCheck`, которым идёт сужение строк `listnarrow`);
  Д-6 `checkAdapter.Check` двери публичного слушателя kaname; Д-7 `AllowsVerb`. В каждом из них для
  объекта типа из перечня надзор не спрашивается: исход — исход модели, а там, где вопроса к модели
  нет (отношение не разрешается, идентификатор `*`), — отказ. Места класса «закреплённый предмет»
  §1.11 перечнем не затронуты: их предмет — не объекты типов Р5, довод и держатель названы там же.
  Человек не отправитель и не читатель ленты; рычаг администратора — `Revoke`/`Restore` (право на
  объекте `cluster`, перечнем не затронуто). Гейт дерева kaname судит множество мест, которое
  печатает перепись, а не число: место класса «обобщённая дверь» без предиката перечня, место вне
  ведомости классов и вторая декларация перечня — находка (NTF1-F12);
- **основание:** О3, О6 (одна строка), О8.

### Р6. Пространство — чья лента; перечень источников выводится из флага; класс и адресат ограничены

- у notify перечень источников `{модуль, адрес ленты, точный SAN из <модуль>.spiffe, классы,
  формы адресата, authorization}` **выводится чартом** из флага Р9 и закрытой таблицы
  подключаемых источников (NTF1-N03); пустой перечень или запись без поля — отказ старта;
- шаблон строки ищется как `<модуль ленты, из которой строка забрана>/<имя из строки>`; поля «чей
  шаблон» в строке нет;
- **класс `security`** допустим только пространствам закрытого перечня notify `identityNamespaces`
  = `{kaname}` (гейт сборки и страж старта, NTF1-G20): взломанный модуль не отправит письмо вида
  «сбросьте пароль». Перечень — **константа сборки notify, а не ручка**: значением установки не
  расширяется. Поэтому письма `security` в NTF-1 приходят ровно из одного пространства, и свойство
  «сетка поперёк источников» доказывается классом `notice` (NTF1-H10), а сетка `security` — одним
  источником и двумя репликами (NTF1-H01, H03);
- **форма адресата в NTF-1 одна — адрес.** notify принимает строку с адресом только из
  пространства `kaname` и из пространства, названного стендовой ручкой `standProbeNamespace`
  (Р16; гейт NTF1-I04 держит её вне цепочки `prod`); адресация субъекта — NTF-3 (NTF1-G21);
- что держит «А шлёт от имени Б»: (1) пространство — из перечня лент, а не из данных; (2) сертификат
  ленты выпускается только своей службе (NS, Р12); (3) `ResolveSend` — отзыв и порядок выкатки;
- **основание:** О3, О5.

### Р7 (Д5). Шаблон — данные: общий макет в notify, у источника только блоки; кастомных нет

- раскладка `<owner>/notifications/<name>/{notification.yaml, body.<locale>.yaml}`;
- `notification.yaml`: имя, класс (`security` | `notice`), `ttl`, `limits` (обязательны для
  `security`), закрытые типы атрибутов (`text`, `secret`, `path`, `token`, `timestamp`), тема;
- тело — только блоки: `heading`, `p`, `button{text, path|token}`, `code`, `list`, `kv`,
  `warning`, `divider`; HTML источник написать не может;
- общий макет — HTML с inline CSS и табличной вёрсткой в `services/notify/layout/`; рендер
  экранирует значения; письмо `multipart/alternative`; картинки — вложения `cid:`; внешних ресурсов
  нет; ссылка = origin установки из конфигурации notify + `path`/`token`;
- заголовки — MIME-библиотекой, RFC 2047; CR/LF в значении заголовка → `INVALID`; `From` один на
  установку; `Reply-To` у `security` не выражается; локали — `{ru}`;
- шаблоны попадают в notify **только при сборке** (`make -C services/notify bundle` + гейт);
  регистрации в рантайме нет; **кастомных шаблонов установки нет** — ни ручки пути, ни вызова
  загрузки (снято владельцем, NTF1-G19); эталоны `.eml` и превью — в notify;
- названный остаток: почтовые клиенты сами делают ссылки из похожего на адрес текста;
- **основание:** О2, О4, О9, О14.

### Р8 (Д6). Фундамент — в corelib; контракт — `proto/corelib/notify/`

- `corelib/notify/feed` — `Put` в транзакции события, точный счётчик лимита (CAS), AEAD секрета
  ключом службы, сервер ленты `Claim`/`Ack`, уборщик (истечение, стирание, возврат лимита), флаг
  Р9 — на существующих `outbox.SanitizeTable`, `outbox/metrics`, `outbox.NewQueueSweeper`,
  `drainer.Classify`;
- `corelib/notify/spec` — формат и **единый** валидатор (генератор, гейт, notify на старте);
- `corelib/cmd/notifygen` — `SendX`, миграция ленты (`init`), эталон структуры, `-check`;
  директива `tool` в `go.mod`, версия равна пину corelib;
- звено идентичности служб (Р2) — `corelib/grpcsrv`, читатели — `listnarrow`, `authz`;
- контракт — `kacho proto/corelib/notify/`, пакет `corelib.notify` без сегмента версии; стабы в
  corelib; путь вписывается комментарием в `PRO-Robotech/corelib#9`; corelib не знает имён
  потребителей;
- **`Claim`, `Ack`, `ResolveSend` унарны и `Operation` не возвращают — это не нарушение
  `ban09`:** ban09 судит мутации ресурса, чей исход клиент поллит; `Claim` — аренда из очереди
  работ, `Ack` — отметка исхода аренды, `ResolveSend` — чтение решения; ответ равен закоммиченному.
  `Revoke`/`Restore` меняют ресурс «запись выдачи» и `Operation` возвращают;
- **границы `Claim(max, classes)`:** `max` — целое в `[1..500]`: `0` → `max: required`,
  `> 500` → `max: must be ≤ 500`; `classes` — непустой набор из `{security, notice}`: пусто →
  `classes: required`; всё — `INVALID_ARGUMENT` с `field_violations[].field`, без усечения.
  `Ack` с `id` не по форме → `invalid notification id '<X>'` (`INVALID_RESOURCE_ID`); с
  неизвестным → `NOT_FOUND` `Notification <id> not found` (`RESOURCE_NOT_FOUND`); без исхода →
  `outcome: required`; с утраченной арендой → `FAILED_PRECONDITION` `LEASE_LOST`;
- идентификатор строки — `corelib ids.NewID("ntf")`, приставка вносится в `ids.KnownHyphenPrefixes`;
- **основание:** О10.

### Р9 (Д7). Флаг установки: генерировать ли почтовые запросы — одно объявление, без умолчания

- объявление одно: `global.kacho.notifications.enabled` + переопределение
  `<модуль>.notifications.enabled`; действующее значение модуля = переопределение, иначе глобальное;
- **умолчания нет:** глобальное не задано — рендер отвергнут с именем ручки; служба-источник без
  своей переменной `KACHO_<SVC>_NOTIFICATIONS_ENABLED` не стартует (NTF1-N01, N08);
- из того же объявления чарт выводит перечень источников notify: источник в перечне ⇔ он в таблице
  подключаемых и его флаг включён. Рендер notify и секрета почты ⇔ перечень непуст. Рассинхрон
  флага и перечня невыразим: ручного перечня нет (NTF1-N03, N04);
- **выключен:** `SendX` строк не пишет и событий подписки не порождает; сервер ленты не
  регистрируется; ключ `notification` (тип `notification_feed`) в `Mapping.Kinds` не объявляется;
  notify модуль не опрашивает; схема базы (миграция ленты) — та же, от флага не зависит
  (NTF1-N05, N07). Исход `Subscribe` при выключенном флаге зависит от того, остаются ли у источника
  другие виды, и выбран так (NTF1-N07):
  - **есть другие виды** (каждый модуль kacho NTF-3) — журнал подписки собирается без ключа ленты;
    `Subscribe` с `kinds: ["notification_feed"]` — `INVALID_ARGUMENT` текстом corelib
    `kinds: "notification_feed" is not a kind of this owner; known kinds: <прочие виды>`;
  - **других видов нет** (`notify-probe`) — `Mapping.Kinds` был бы пуст, а пустой словарь corelib
    отвергает при сборке журнала; поэтому журнал не собирается, а сервер подписки **не объявляется
    и не монтируется** — объявление и монтирование выводятся из одного условия. Согласие
    наблюдается в integration-пробе corelib (NTF1-N07 (б)): набор сервисов сервера
    (`GetServiceInfo`) не содержит `corelib.subscription.InternalSubscriptionService`. Статический
    гейт `TestGRPCMountParity_EveryDeclaredServiceIsMounted` этого исхода **не** производит: он
    сверяет стабы с вызовами регистрации в композиционных корнях kacho, условного монтирования во
    время работы не видит и пакет, которым бинарь не владеет, не судит. Служба стартует;
    `Subscribe` — `UNIMPLEMENTED`;
- **письма класса `security` при выключенном флаге не глотаются:** `SendX` возвращает сторож
  `feed.ErrDeliveryNotConfigured`, и глагол источника отвечает единым отказом corelib
  `feed.DeliveryNotConfiguredStatus()`: `FAILED_PRECONDITION`, текст `email delivery is not
  configured in this installation`, `ErrorInfo{reason: NOTIFICATION_DELIVERY_NOT_CONFIGURED}` —
  одинаковым для любого адреса: глагол спрашивает флаг до поиска адреса (NTF1-N06). Глаголы kaname
  (восстановление, приглашение, подтверждение) переводятся на это в NTF-2;
- метрика состояния: источник — `kacho_notifications_enabled{module}` (1/0); notify —
  `notify_source_enabled{source}` (NTF1-N09);
- **основание:** О14 («если нет шлюза не генерить нагрузку»), О5.

### Р10 (Д11, часть notify). Лимиты: точный счётчик у источника, сетка на адресата и потолки в notify

- **источник** — `Put` обновляет счётчик окна CAS в транзакции события по `limits` шаблона; сверх
  лимита строки нет — сторож `feed.ErrLimitExhausted`; ответ вызывающему выбирает глагол источника;
  уборщик, закрывая строку `EXPIRED(platform_unavailable)`, возвращает её вклад в окно той же
  транзакцией (только если строка ни разу не получила ответа ретранслятора на `RCPT`);
- **notify, сетка на адресата поперёк источников** — CAS-строки в `kacho_notify`, ключ —
  HMAC адреса ключом notify (адрес открытым текстом не хранится):
  - `security` — своя сетка (ручка `notify.limits.recipient.security.perDay`, граница
    `[1..1000]`, ориентир 40): сверх — терминальный `DROPPED(recipient_net)`, секрет стёрт,
    **тревога** на каждое срабатывание;
  - прочее — `notify.limits.recipient.notice.perHour`/`perDay` (границы `[1..10000]`, ориентир
    100/500): сверх — `DEFER(recipient_net)` до освобождения окна в пределах срока строки (сводку
    вместо отложенных писем заводит NTF-3);
  - **инвариант:** сетка `security` ≥ 1,25 × сумма суточных `limits` на адресата всех шаблонов
    класса `security` в сборке — страж старта notify (NTF1-H07): сетка никогда не срезает то, что
    источник законно пропустил («пол» владельца, NTF-2);
- **на источник** — ведро в памяти реплики (`notify.sourceLimits.<модуль>.rate`, `burst`; границы
  `[1..1000]`/`[1..10000]`, ориентир kaname 20/200, модуль 10/100): избыток остаётся строками у
  источника — notify просто не забирает, терминальных исходов нет;
- **весь поток** — суточный потолок CAS-строкой (`notify.limits.global.perDay`, граница
  `[1..10⁷]`, ориентир — 80% квоты ретранслятора): выше — notify забирает только `security`
  (`Claim(classes={security})`);
- **пауза источника только оператором** — ручка `notify.sourceLimits.<модуль>.paused` (значение
  установки, перекатка по `checksum/config`): у приостановленного источника notify забирает только
  `security`; вызова паузы в рантайме нет. **Автоматической паузы нет ни в NTF-1, ни в NTF-4**
  (Д11: «пауза по жалобам только оператором»); реакция NTF-4 на жалобы и возвраты — подавление
  адресата, а не пауза источника;
- **где живут ручки на источник.** Перечень источников — выводимый (Р6, Р9) и значением установки
  не задаётся: запись перечня в values — красный NTF1-N03. Ручки на источник — отдельный словарь
  values `notify.sourceLimits`, ключ — имя модуля; он не порождает источника и не входит в
  перечень, а лишь параметризует уже выведенный. Рендер отвергается с именем ключа, если ключ
  словаря — не модуль таблицы подключаемых, и с именем модуля, если у источника выведенного
  перечня нет своей записи `sourceLimits` (умолчания нет) (NTF1-N03, H08);
- все величины — ручки values установки; незаданная или вне границы — отказ старта с именем ручки
  и границей (`sec-no-silent-default-for-guarded-knob`);
- **основание:** О13 («кто-то вводит на восстановление логин не свой и спамит владельца почты»):
  поперёк любого числа источников ящик получает не больше сетки.

### Р11. Словарь исходов закрыт; корзины «прочее» нет

| событие | исход `Ack` | тратит попытку |
|---|---|---|
| ретранслятор принял `DATA` | `SENT`, секрет стёрт | — |
| 5xx на `RCPT` | `RECIPIENT_REJECTED` (терминально) | — |
| отказ `AUTH`; 5xx на `MAIL FROM`/`DATA` | `DEFER(platform_unavailable)` + сигнал `misconfigured` | нет |
| 4xx, разрыв, нет TLS, недоверенный сертификат | `DEFER(platform_unavailable)`, размыкатель | нет |
| `ResolveSend` = `REVOKED` | `DENIED(revoked)` | — |
| `ResolveSend` = `NOT_YET_GRANTED` | `DEFER(grant_skew)` | нет |
| kaname недоступна | `DEFER(platform_unavailable)` | нет |
| шаблона нет в сборке для пространства / `schema_rev` новее | `DEFER(template_skew)` | нет |
| класс или форма адресата не разрешены пространству; атрибуты не по схеме; CR/LF в заголовке; шифротекст не открывается | `INVALID` (терминально) | — |
| сетка `security` на адресата исчерпана | `DROPPED(recipient_net)` (терминально) | — |
| сетка прочего исчерпана | `DEFER(recipient_net)` | нет |
| срок истёк | `EXPIRED(<причина последнего DEFER>)` — ставит только уборщик источника | — |

Повтор ограничен **сроком** строки, а не счётом попыток; перед `DATA` notify сверяет срок.

### Р12. Идентичность в сертификате выпускается только своей службе (NS); декларация одна

- политика выпуска сертификатов служб привязывает SAN к пространству имён и учётке службы;
  сертификат с чужой идентичностью не выпускается;
- источник SAN — одна декларация `<служба>.spiffe: {trustDomain, namespace, saName}` в зонтике,
  литералом (образец `bootstrapOperator.spiffe`, `deploy/helm/umbrella/values.yaml`); читатели:
  выпуск сертификата, перечень источников notify, таблица Р2 у каждой службы-вызываемой; их
  согласие судит гейт рендера (NTF1-J05). В NTF-1 декларации: `notify.spiffe`,
  `notifyProbe.spiffe` (стенд), `kaname.spiffe`;
- прежний разбор SAN в kaname (`SANToServiceDomain` и производные) Р2 не использует и не меняет;
- NS блокирует боевое включение notify (NTF1-J04);
- **основание:** О3, О5.

### Р13. Секрет в покое — шифротекст; ключ вне базы

AEAD, AAD = таблица ‖ id строки ‖ имя шаблона; ключ — в секрете службы, кольцо «активный +
прежний»; `Claim` отдаёт открытый текст только `service:notify` по mTLS; после терминального исхода
и истечения секрет стирается (CHECK: не-`pending` строка секрета не несёт). Названный остаток: WAL,
реплика и копия несут шифротекст; ротация с выводом прежнего ключа делает его нечитаемым.

### Р14. Дубль возможен ровно в окне `DATA → Ack`

`Message-ID = <hash(пространство, id строки)>@<домен отправителя>`; дубль возможен, если реплика
упала между приёмом `DATA` и `Ack`; документ не утверждает иного.

### Р15 (Д12). Прода нет — прямое переключение

Прежние редакции этого документа замещаются целиком без периода совместимости (§3). Снятие почты
kaname и поставщика личности — NTF-2 с его предикатом (§4).

### Р16. Стенд: приёмник с TLS и проба-источник — только стендовые объекты

- приёмник (`templates/mail-receiver.yaml`) говорит STARTTLS с сертификатом из УЦ стенда; ручки
  отключения проверки TLS у notify нет;
- проба-источник `notify-probe` — служба kacho (`services/notify/cmd/notify-probe`, своя база
  `kacho_notifyprobe`), подключённая процедурой K03: лента, сервер ленты, ключ журнала `notification`
  (вид провода `notification_feed`; других видов у пробы нет — при флаге `false` сервер подписки не
  объявляется, Р9),
  звено Р2 в `authz.Interceptor`, манифест `notifications: {namespace: notify-probe, readers:
  [notify]}`, шаблон `probe-hello` класса `notice`; внутренний глагол
  `InternalNotifyProbeService/Send` ставит письмо на адрес;
- приёмник, проба и ручка `standProbeNamespace` — вне цепочки `prod` (гейт NTF1-I04): приёмник —
  читатель писем, проба — генератор писем;
- **основание:** «приёмник писем на стенде с TLS и гейт «его нет в values.prod»» (постановка);
  сквозная проба ядра на поднятом стенде без настоящего источника иначе невыполнима.

### Р17. Процедуры считаются шагами, и у каждого пропуска есть свой красный

«Добавить нотификацию» — 4 шага в подключённой службе; «подключить службу» — 7 шагов один раз
(NTF1-K01…K03). Выпуск corelib не нужен ни для одной.

### Р18. Доступность и наблюдаемость notify

≥ 2 реплики и PDB в каждой цепочке, где notify рендерится; метрики: возраст старейшей непринятой
строки по источнику и классу, исходы по клеткам Р11, срабатывания сетки, ведра, потолка,
`notify_source_enabled`; тревоги: половина наименьшего `ttl` шаблонов `security` по возрасту
строки, `grant_skew`, `template_skew`, `misconfigured`, любое срабатывание сетки `security`.

---

## §3 Явное замещение прежних решений

| # | прежнее | где | чем замещается | вступление |
|---|---|---|---|---|
| З1 | Р3 редакций 1–3: `send: [service_account]` на `notification_feed`, выдача `{feed: <id ленты>}` | этот документ, редакции 1–3 | `sender: [service]` на `notification_namespace:<модуль>`, `reader: [service]` на `notification_feed:<модуль>`, строка `notifications: {namespace, readers: [notify]}` (Р5) | эта редакция |
| З2 | Р22 редакций 1–3: субъект `service_account:<учётка>` из таблицы `SAN → saName` | там же | служебный принципал `service:<имя>` (Р2); учётки для служб не заводятся | эта редакция |
| З3 | перечень SAN читателей ленты у источника (C06 редакций 1–3) | там же | читатель — только `reader` в модели + звено Р2 | эта редакция |
| З4 | `sub-notification-kind`: объект `notification_feed:<id ленты>` | `.claude/rules/subscription.md` | `notification_feed:<модуль>` (Р4) | правка правила — `kacho-workspace#881` |
| З5 | `hard-cloud-admin-cascade` — администратор кластера получает каскадом всякое отношение; в коде — надзор в семи местах обобщённой двери kaname (§1.11, Д-1…Д-7) | `.claude/rules/security-hardening.md`; kaname `internal/service/authorize_service.go`, `internal/authzguard/own_door.go`, `internal/authzguard/read_authz.go` | у `notification_feed`/`notification_namespace` надзор не применяется ни в одном из мест Д-1…Д-7; перечень типов — одна декларация; места с закреплённым предметом не затронуты (§1.11); рычаг — `Revoke`/`Restore` (Р5) | правило — `kacho-workspace#881`; код — S2 (kaname#484) |
| З6 | `sec-forwarded-trust-aware-extract`: личность — только пересланная | `.claude/rules/security.md` | + служебный принципал из проверенного сертификата на закрытом перечне методов, отдельным носителем (Р2) | правка правила — `kacho-workspace#881` |
| З7 | `authz.TenantSubject`: субъект подписки — только `user`/`service_account` | corelib `authz/types.go` | словарь тенантских субъектов не меняется; `service:` приходит вторым носителем одной функцией (Р2 п.3) | S1 |
| З8 | `poly-edge-notify-sources` / `poly-edge-notify-kaname`: «источники — kaname (NTF-1)» | `.claude/rules/polyrepo.md` | kaname — источник с NTF-2 (исключение Р3); в NTF-1 — `notify-probe` на стенде; `notify → kaname` несёт `ResolveSend` | правка правила — `kacho-workspace#881` |
| З9 | таблица рёбер выполнения | `docs/specs/01-architecture-and-services.md` | + notify→источники, notify→kaname (`ResolveSend`), notify→ретранслятор; входящих в notify нет | `kacho-workspace#881` |
| З10 | спека-книга не знает эпика | `docs/specs/04-roadmap-and-phasing.md` §5 | строка эпика #2914 и NTF-1…NTF-6 | `kacho-workspace#881` |
| З11 | текст задачи NS kacho#2916 «единый перевод SAN для всех служб» | трекер | «таблица Р2 из декларации `<служба>.spiffe`; прежний разбор kaname не меняется» | правка тела задачи |

**Не замещается:** MRW-1 Р1 (у службы доступа своей служебной записи нет) — выбрано исключение Р3.
**Замещается в NTF-2 (#2917), а не здесь:** ID-MAIL-1 Р23, Р25, MAIL-25, MAIL-47, MAIL-48, В5;
очередь `invite_mail_outbox`; условие старта `own` kaname#475 (Д12, Д13).

---

## §4 Что НЕ входит

- **NTF-2** (`PRO-Robotech/kacho#2917`, `PRO-Robotech/kaname#484` в части писем) — лента kaname,
  перевод приглашения, восстановления и подтверждения адреса, строка
  `notifications: {readers: [notify]}` в манифесте kaname, снятие `net/smtp`, кредов и
  `invite_mail_outbox`, снятие почты поставщика личности и предикат «секрет почты смонтирован ровно
  в одном объекте», класс S из аудита kaname, лимиты kaname и края для анонимных почтовых
  глаголов, регистрация «сначала письмо», гейт пары пинов notify↔kaname и журнала шаблонов kaname.
- **NTF-3** (`PRO-Robotech/kacho#2918`) — получатели (модель E), адресация субъекта, сводки
  (включая замену `DEFER(recipient_net)` сводкой), журналы модулей, флаг по модулю у каждого
  модуля kacho, API настроек и контактов, перепись модулей.
- **NTF-4** (`PRO-Robotech/kacho#2919`) — возвраты, жалобы, подавление, DKIM/SPF/DMARC, ротация
  кредов без потерь. Автоматической паузы источника нет и там (Д11; Р10).
- **NTF-5** (новая задача) — извещения оператора, класс OB.
- **NTF-6** (новая задача) — консоль: центр уведомлений, настройки, контакты.
- Каналы кроме почты — интерфейсом в NTF-3; белая метка отправителя — вне эпика.
- Перевод прежних вызывающих разбора SAN в kaname на таблицу Р2 — их исход NTF-1 не меняет
  (NTF1-M07); предмет — задача-преемник в kaname, предикат снятия — команда
  `git -C kaname grep -nE 'ServiceNameFromSAN\(|SANToServiceDomain\(|SANToServiceAccountID\(' -- '*.go' ':!*_test.go' | grep -v 'func '` → 0.

---

## §5 Стадии и порядок

| стадия | задача | что производит | зависит от |
|---|---|---|---|
| **S0** | #2915 | контракт `kacho proto/corelib/notify/`, стабы в corelib | — |
| **S1** | corelib#77 | `notify/spec`, `notify/feed` (с флагом), `cmd/notifygen`, звено Р2 в `grpcsrv`/`listnarrow`/`authz`; `notification_feed`, `notification_namespace` и `service` в `forbiddenObjectTypes` (Р2 п.5); тег corelib | S0 |
| **S2** | kaname#484 | типы модели `service`, `notification_feed`, `notification_namespace`; форма строки манифеста и валидатор; запись выдачи; `ResolveSend`/`Revoke`/`Restore` (право `ResolveSend` — той же дверью проверки прав); перечень типов без надзора администратора облака и его предикат во всех семи местах обобщённой двери Д-1…Д-7, ведомость классов переписи и её гейт (Р5, §1.11); звено Р2 на слушателях kaname (перечень `{ResolveSend}`); отказ тенантских поверхностей | S1 |
| **S3** | #2915 | `services/notify`: перечень, подписка, `Claim`/`Ack`, `ResolveSend`, рендер, отправка, лимиты, база `kacho_notify`, метрики, тревоги | S1, S2 |
| **S4** | #2916 | политика выпуска, декларации `<служба>.spiffe`, гейт согласия | — (блокирует боевое включение S3) |
| **S5** | #2915 | чарт notify, флаг, выведенный перечень, приёмник с TLS, `notify-probe`, сквозные пробы | S3, S4 |

Каждая стадия production-complete в своих границах.

---

## §6 Сценарии

### Средства построения условий (каждое «Дано» строится посевом, а не ожиданием)

| ось | средство | где |
|---|---|---|
| шаблон, класс, `ttl`, блоки | фикстурный каталог `testdata/notifications/` | corelib, notify |
| служебный принципал, выдача | фикстурный манифест модуля `probe` + применитель посева kaname | kaname integration |
| звено Р2 | тестовый УЦ пробы; декларация `spiffe` фикстуры; перечень методов и таблица | corelib, kaname, notify integration |
| отзыв, восстановление | `Revoke`/`Restore` от администратора кластера | kaname integration |
| время | управляемые часы в `feed`, notify и kaname | integration |
| ретранслятор | тестовый SMTP-узел в процессе пробы с TLS, ответы задаются на `AUTH`/`MAIL FROM`/`RCPT`/`DATA` | notify integration |
| фикстурный источник | служба в процессе пробы на `corelib notify/feed` с базой testcontainers; пространства `probe`, `probe-b` и фикстурное `kaname` (класс `security` допустим только ему — `identityNamespaces`); перечень notify пробы: у `kaname` и `probe` форма адресата `address`, `standProbeNamespace = probe` (кроме G21, где он явно не задан); у `probe-b` формы `address` нет — строки `probe-b` в пробах до отправки не доходят | notify integration |
| проверка прав фикстурного источника | клиент проверки прав источника в пробе notify отвечает по посеянным кортежам (Р5 — только `service:notify reader …`; иначе — как сказано в Given); **кроме F22 (а), (в)**, где источник спрашивает настоящую дверь kaname в процессе пробы — средство названо в самом F22 | notify integration |
| дверь kaname в процессе пробы | kaname на testcontainers с посевом F01 и фикстурным краем в круге пересылающих | notify integration (F22 (а), (в)) |
| пересылающий | фикстурный край в круге пересылающих пробы, пересылает посеянного пользователя (в том числе администратора облака) | kaname, notify integration |
| фикстурные источники флага | corelib: `probe` с ключами журнала `notification` → `notification_feed` и `item` → `probe_item` (тип фикстуры); `probe-solo` — только `notification` → `notification_feed`; переменная флага процесса | corelib integration (N07) |
| таблица подключаемых источников | фикстурная копия чарта notify с таблицей из двух источников `notify-probe`, `probe-b` | гейт рендера |
| недоступность | остановка тестового сервера в процессе пробы | notify integration |
| флаг | значения рендера по `deploy/stacks.txt`; переменная процесса источника | chart, corelib, notify |
| стенд | цепочка `dev-prod` с `mailpit` и `notify-probe` | стенд |

### A. Формат шаблона и единый валидатор — раздел «corelib» (S1)

**ID:** NTF1-A01 — **корректный шаблон принимается**

**Given** каталог `invite/` с `notification.yaml` (класс `security`, `ttl: 168h`, `limits` на адресата и инициатора, атрибуты `inviter_name: text`, `token: token`) и `body.ru.yaml` из блоков `heading`, `p`, `button{text, token}`
**When** валидатор `notify/spec` проверяет каталог
**Then** находок ноль; валидатор печатает число проверенных шаблонов и блоков (знаменатель > 0)

**ID:** NTF1-A02 — **блок вне закрытого набора отвергается** (близнец A01)

**Given** условия A01, но один блок тела — `html: "<b>…</b>"`
**When** валидатор проверяет каталог
**Then** находка называет файл, номер блока и правило «блок вне закрытого набора»
**And** генератор на этом каталоге не порождает ни одного файла

**ID:** NTF1-A03 — **кнопка с полной ссылкой отвергается** (близнец A01)

**Given** условия A01, но `button.path: "https://example.invalid/x"`
**When** валидатор проверяет каталог
**Then** находка «ссылка — путь или токен; origin задаёт установка» с именем файла и блока

**ID:** NTF1-A04 — **класс `security` без `limits` отвергается** (близнец A01)

**Given** условия A01 без `limits`
**When** валидатор проверяет каталог
**Then** находка «класс security требует limits» с именем шаблона

**ID:** NTF1-A05 — **тело ссылается на необъявленный атрибут** (близнец A01)

**Given** условия A01, но блок `p` ссылается на `{{ account_name }}`, которого нет в `notification.yaml`
**When** валидатор проверяет каталог
**Then** находка называет атрибут, файл и блок

**ID:** NTF1-A06 — **локаль вне закрытого набора** (близнец A01)

**Given** условия A01, но тело в `body.xx.yaml`
**When** валидатор проверяет каталог
**Then** находка «локаль вне {ru}» с именем файла

**ID:** NTF1-A07 — **секретный атрибут вне допустимого блока** (близнец A01)

**Given** условия A01, но атрибут `code: secret` выведен в блоке `heading`
**When** валидатор проверяет каталог
**Then** находка «секретный атрибут допустим только в блоках code и button.token»

**ID:** NTF1-A08 — **формат только расширяется: замороженный корпус** (отрицание; близнец — расширяющая правка)

**Given** корпус принятых фикстур всех выпущенных версий формата, замороженный в corelib
**When** в валидатор вносится сужающая правка (ранее законный блок отвергается)
**Then** гейт корпуса красный и называет фикстуру и версию
**And** на расширяющей правке тот же гейт зелёный и печатает число фикстур

**ID:** NTF1-A09 — **валидатор один на три места применения**

**Given** деревья corelib, kacho, kaname на пинах
**When** гейт перечисляет реализации проверки формата шаблона (узлы разбора): реализация — функция, открывающая или разбирающая файл формата шаблона (`notification.yaml`, `body.<locale>.yaml`); вызов `text/template`/`html/template` сам по себе реализацией формата не считается — в corelib `34bc810` такой вызов уже есть (`quota/refusal.go`, текст отказа), к формату шаблонов отношения не имеет, и гейт, судящий по нему, покраснел бы на исправном продукте
**Then** реализация ровно одна — `notify/spec`; генератор, гейт сборки notify и notify на старте её зовут
**And** инъекция второй реализации в дерево notify — находка с координатой; без инъекции гейт молчит и печатает знаменатель

### B. Лента — раздел «corelib» (S1)

**ID:** NTF1-B01 — **постановка в транзакции: закоммичено — строка и сигнал есть**

**Given** фикстурный источник `probe` с лентой и журналом подписки, флаг включён; шаблон `probe-hello` собран
**When** use-case вызывает `SendProbeHello(ctx, tx, attrs)` и транзакция коммитится
**Then** в ленте ровно одна строка `pending`: `template = probe-hello`, `schema_rev`, `class = notice`, `expires_at = enqueued_at + ttl`, `enqueued_at` — серверное время транзакции, `id` с приставкой `ntf-`
**And** в журнале подписки ровно одна строка по объекту `notification_feed:probe` (ключ журнала `notification`; на проводе — вид `notification_feed`)

**ID:** NTF1-B02 — **откат — нет ни строки, ни сигнала** (близнец B01)

**Given** условия B01
**When** транзакция откатывается после `SendProbeHello`
**Then** строк в ленте 0, строк журнала подписки по `notification_feed:probe` 0, счётчик лимита не изменился

**ID:** NTF1-B03 — **секрет в покое — шифротекст; notify получает открытый текст**

**Given** строка с секретным атрибутом, значение которого — посеянная уникальная строка
**When** проба читает таблицу ленты целиком (`COPY … TO STDOUT`) и вызывает `Claim` от `service:notify` с `reader`
**Then** посеянная строка в выгрузке не встречается ни разу
**And** ответ `Claim` несёт её открытым текстом

**ID:** NTF1-B04 — **шифротекст, перенесённый в другую строку, не открывается** (близнец B03)

**Given** две строки; шифротекст первой записан в колонку второй прямым `UPDATE` пробы
**When** notify забирает вторую строку
**Then** открытого текста в ответе нет; строка закрыта `INVALID(sealed_mismatch)`, секрет стёрт; SMTP-сессий 0

**ID:** NTF1-B05 — **боевая посадка без ключа ленты не стартует** (близнец — ключ задан)

**Given** источник в боевой посадке с включённым флагом, ключ ленты не задан
**When** процесс стартует
**Then** старт отвергнут с именем ручки ключа
**And** с заданным ключом процесс стартует, и самоотчёт посадки называет ось ключа

**ID:** NTF1-B06 — **ротация ключа: строка прежнего ключа открывается**

**Given** строка, запечатанная K1; кольцо — «активный K2, прежний K1»
**When** notify забирает строку
**Then** ответ несёт открытый текст; новые строки запечатаны K2

**ID:** NTF1-B07 — **ключ выведен из кольца — строка `INVALID`** (близнец B06)

**Given** условия B06, но кольцо — только K2
**When** notify забирает строку
**Then** `INVALID(key_unavailable)`, секрет стёрт, SMTP-сессий 0

**ID:** NTF1-B08 — **лимит: L параллельных постановок при лимите L проходят все**

**Given** шаблон с лимитом L на адресата за окно; счётчик 0
**When** L горутин параллельно ставят письмо одному адресату, каждая в своей транзакции
**Then** строк L; счётчик окна L

**ID:** NTF1-B09 — **лимит: сверх L ровно L строк** (близнец B08)

**Given** условия B08
**When** L+k горутин параллельно ставят письмо
**Then** строк ровно L; k вызовов получили сторож `feed.ErrLimitExhausted` (`errors.Is`), их транзакции откатились; счётчик L
**And** гейт дерева не находит в `feed` чтения счётчика с последующей записью (CAS в базе)

**ID:** NTF1-B10 — **`Claim`: параллельные вызовы получают непересекающиеся строки**

**Given** 100 строк `pending`
**When** два `Claim(max=60, classes={notice})` идут параллельно
**Then** объединение ответов — 100 строк без повторов; у каждой токен и срок аренды

**ID:** NTF1-B11 — **`Claim` не выдаёт истёкшую строку** (близнец B10)

**Given** одна строка `pending`, `expires_at` прошёл по управляемым часам
**When** notify вызывает `Claim`
**Then** ответ пуст

**ID:** NTF1-B12 — **`Ack SENT` с действующим токеном**

**Given** строка, выданная `Claim`, токен T
**When** notify зовёт `Ack(id, T, SENT)`
**Then** `state = sent`, `secret_attrs IS NULL`, `outcome_at` проставлен — одной транзакцией

**ID:** NTF1-B13 — **`Ack` с утраченной арендой** (близнец B12)

**Given** условия B12; аренда истекла, строка выдана повторно с токеном T2
**When** notify зовёт `Ack(id, T, SENT)`
**Then** `FAILED_PRECONDITION`, `reason = LEASE_LOST`; строка не изменилась

**ID:** NTF1-B14 — **`Ack` без исхода** (близнец B12)

**Given** условия B12
**When** notify зовёт `Ack` с `outcome = OUTCOME_UNSPECIFIED`
**Then** `INVALID_ARGUMENT`, текст `outcome: required`, `field = outcome`; строка не изменилась

**ID:** NTF1-B15 — **истечение по вине платформы возвращает лимит**

**Given** строка `pending`, последний `DEFER` — `platform_unavailable`; счётчик окна = 3
**When** часы переходят `expires_at`, уборщик проходит
**Then** строка `EXPIRED(platform_unavailable)`, секрет стёрт, счётчик = 2 — одной транзакцией

**ID:** NTF1-B16 — **истечение по иной причине лимит не возвращает** (близнец B15)

**Given** условия B15, но последний `DEFER` — `template_skew`
**When** уборщик проходит
**Then** `EXPIRED(template_skew)`, секрет стёрт, счётчик = 3

**ID:** NTF1-B17 — **не-`pending` строка с секретом невыразима в базе** (близнец — `UPDATE` со стиранием)

**Given** строка `pending` с секретом
**When** проба прямым `UPDATE` ставит `state = 'sent'`, не трогая `secret_attrs`
**Then** база отвергает запись: SQLSTATE `23514` с именем ограничения «не-pending строка секрета не несёт»
**And** тот же `UPDATE`, стирающий `secret_attrs`, принят

**ID:** NTF1-B18 — **`Claim` не удерживает соединение пула источника**

**Given** источник с пулом размера 4
**When** 16 `Claim` идут параллельно с 16 глаголами источника
**Then** все глаголы завершились в свой срок; после ответа `Claim` соединений пула, занятых лентой, 0

**ID:** NTF1-B19 — **прямая вставка в ленту мимо `feed` — находка** (близнец — вставка через `SendX`)

**Given** дерево источника
**When** гейт дерева ищет узлы вставки в таблицу ленты вне `corelib/notify/feed`
**Then** инъекция `INSERT INTO <svc>_notification_outbox` в use-case — находка с координатой
**And** на дереве со вставкой только через `SendX` гейт молчит и печатает число осмотренных файлов

**ID:** NTF1-B20 — **наблюдаемость ленты**

**Given** источник с лентой
**When** снимаются метрики
**Then** есть возраст старейшей непринятой строки по классу, счётчики исходов по клеткам Р11, число доставленных за жизнь
**And** «ноль доставленных за всю жизнь» видим метрикой в той же пробе: источник без единой принятой строки отдаёт счётчик доставленных `0` и растущий возраст старейшей строки
**And** гейт `outboxobservedgate` (существующий) расширяется **четвёртым** входом предмета; входов сегодня три — `drainer.Config{Table: X}` (дренируемые), `CollectorConfig{Table: X}` (наблюдаемые) и перепись колонок доставки по миграциям (`sent_at`, `next_attempt_at`: таблица с ними обязана иметь движущего — дренаж или оператор прод-кода службы — либо запись с обоснованием). Новый вход — подъём сервера ленты в композиционном корне (разбор AST, как `drainer.Config` сегодня): он засчитывается за движущего таблицу ленты и вносит её в обязанные быть наблюдаемыми
**And** без нового входа исход зависит от схемы ленты, и оба исхода неверны: если в схеме ленты нет колонок `sent_at` и `next_attempt_at`, гейт ленту не видит вовсе (её двигает `Claim` фундамента, а не `drainer` и не оператор службы); если они есть — перепись колонок доставки объявит ленту находкой «двигать некому» на исправном продукте
**And** корень `notify-probe` с лентой и без сборщика состояния — находка (инъекция); близнец — тот же корень со сборщиком: гейт молчит, перепись печатает таблицу ленты среди наблюдаемых и среди движимых

**ID:** NTF1-B21 — **`Claim` с `max` вне границ** (близнец — `max` на границах)

**Given** 3 строки `pending`; notify как в C03
**When** `Claim(max=0)`, затем `Claim(max=501)`
**Then** оба `INVALID_ARGUMENT`: `max: required` и `max: must be ≤ 500`, `field = max`; ни одна строка не арендована
**And** `Claim(max=1)` отдаёт 1 строку, затем `Claim(max=500)` — оставшиеся 2

**ID:** NTF1-B22 — **`Ack` с id не по форме** (близнец B12)

**Given** условия B12
**When** `Ack(id = "not-an-id", T, SENT)`
**Then** `INVALID_ARGUMENT`, `invalid notification id 'not-an-id'`, `reason = INVALID_RESOURCE_ID`; строка не изменилась

**ID:** NTF1-B23 — **`Ack` с неизвестным id** (близнец B12)

**Given** условия B12
**When** `Ack` с `id` по форме, которого в ленте нет
**Then** `NOT_FOUND`, `Notification <id> not found`, `reason = RESOURCE_NOT_FOUND`, `metadata.resource_id = <id>`; строка B12 не изменилась

**ID:** NTF1-B24 — **`Claim` без классов отвергается; с классом — отдаёт только его** (близнец — `classes={security}`)

**Given** строка `security` и строка `notice` в фикстурной ленте пространства `kaname`
**When** `Claim(max=10, classes={})`
**Then** `INVALID_ARGUMENT`, `classes: required`, `field = classes`; ни одна строка не арендована
**And** `Claim(max=10, classes={security})` отдаёт ровно строку `security`; строка `notice` остаётся `pending`

### C. Контракт ленты и её сервер — разделы «notify» (S0) и «corelib» (S1)

**ID:** NTF1-C01 — **потоковая форма по-прежнему одна**

**Given** контракт `proto/corelib/notify/` в дереве kacho
**When** `git grep -h 'returns (stream' -- proto | wc -l`
**Then** **1**; сервис ленты — `InternalNotificationFeedService`, методы `Claim` и `Ack` унарны, `google.api.http` у них нет

**ID:** NTF1-C02 — **лента не маршрутизируется на внешний край** (близнец — внутренний слушатель в том же прогоне)

**Given** стенд с `notify-probe`, чей сервер ленты поднят на внутреннем слушателе
**When** запрос `Claim` приходит на внешний TLS-вход установки
**Then** метод не резолвится; `assert-ban6-external-isolation.py` относит `Claim` и `Ack` к предмету и печатает для каждого вердикт `ISOLATED` (`INCONCLUSIVE` изоляцией не засчитывается); встречный контроль печатает домен `notify` обслуженным у носителя `notify`
**And** предмет у скрипта есть только при двух условиях, и оба — часть S5: вызов `RegisterInternalNotificationFeedServiceServer(` стоит в прод-файле композиционного корня `services/notify/cmd/notify-probe` (перепись `e2e-ban6-domains.py` находит регистрации поиском по прод-файлам kacho; регистрация, спрятанная в corelib, оставила бы домен вне предмета — непровязанным, с напечатанным «предмета нет»); в `INTERNAL_ENDPOINTS` скрипта заведена строка носителя `notify` — внутренний слушатель `notify-probe` (без неё встречный контроль домена не подтверждается, и прогон падает как отказ харнесса, а не как изоляция)
**And** в том же прогоне `Claim` от notify на внутреннем слушателе `notify-probe` получает ответ сервера ленты (не `UNIMPLEMENTED`)

**ID:** NTF1-C03 — **`service:notify` с `reader` забирает строки**

**Given** фикстурный источник `probe` с одной строкой `pending`; звено Р2 источника: перечень `{Subscribe, Claim, Ack}`, таблица `{SAN notify → notify}`; модель посеяна: `service:notify reader notification_feed:probe`; notify предъявляет сертификат с SAN из `notify.spiffe`
**When** notify вызывает `Claim(max=10, classes={notice})`
**Then** ответ несёт строку

**ID:** NTF1-C04 — **другой служебный принципал без `reader` получает отказ** (близнец C03)

**Given** условия C03, но вызывает служба `probe-b`, чей SAN — тоже ключ таблицы (`→ probe-b`), кортежа `reader` у `service:probe-b` нет
**When** она вызывает `Claim`
**Then** `PERMISSION_DENIED`, текст `permission denied`; строка не арендована (следующий `Claim` notify её получает)

**ID:** NTF1-C05 — **notify без `reader` — отказ, побайтово как C04** (близнец C03)

**Given** условия C03, но кортеж `service:notify reader notification_feed:probe` снят
**When** notify вызывает `Claim`
**Then** `PERMISSION_DENIED`, `permission denied`; ответ побайтово равен ответу C04; строка не арендована

**ID:** NTF1-C06 — **SAN вне таблицы Р2 — субъекта нет, отказ** (близнец C03)

**Given** условия C03, но вызывает служба с действительным сертификатом, SAN которого не ключ таблицы
**When** она вызывает `Claim`
**Then** `PERMISSION_DENIED`, `permission denied`; строка не арендована

**ID:** NTF1-C07 — **методы ленты аннотированы правом**

**Given** контракт ленты; в перечень `catalogProtoPackages` (`internal/repohygiene/catalogparity_test.go`) внесён пакет `corelib.notify` и импорт его стабов — без этой строки пакет не обходится вовсе, и гейт о ленте молчит
**When** `TestCatalogMatchesTheAnnotationsItWasGeneratedFrom` обходит аннотированные RPC перечня пакетов
**Then** `Claim` и `Ack` среди обойдённых; перепись печатает «без аннотации 0» и число обойдённых RPC; строки каталога края для обоих перегенерированы (`make -C gateway permission-catalog-apply`), расхождений 0
**And** способность падать на неаннотированном методе доказывает `TestAnnotationLaneInjection_UnannotatedMethodIsAFinding` на подставном входе (по дереву он не ходит); снятие аннотации с `Claim` в дереве — находка обхода «не несёт аннотации» с именем метода

### D. Генератор — раздел «corelib» (S1)

**ID:** NTF1-D01 — **`make notifications` порождает типизированную функцию**

**Given** каталог A01 в дереве источника
**When** `make notifications`
**Then** порождены `SendInvite(ctx, tx, InviteAttrs)` и эталон структуры; поля структуры — атрибуты с типами из `notification.yaml`

**ID:** NTF1-D02 — **правка шаблона без перегенерации — красный `-check`** (близнец D01)

**Given** условия D01; в `notification.yaml` добавлен атрибут, `make notifications` не выполнен
**When** в CI источника `notifygen -check`
**Then** красный с именем файла и расхождения
**And** после `make notifications` — зелёный

**ID:** NTF1-D03 — **`notifygen init` пишет новую миграцию и не трогает существующие**

**Given** служба без ленты
**When** `notifygen init`, затем повторно `notifygen init`
**Then** после первого — один новый файл миграции с меткой времени; после второго — изменений 0

**ID:** NTF1-D04 — **смена версии схемы ленты — новый файл** (близнец D03)

**Given** применённая миграция ленты v1; пин corelib поднят до схемы v2
**When** `notifygen init`
**Then** новый файл `v2_from_v1`, применённый файл побайтово тот же; метка нового файла старше каждой применённой миграции службы (`TestNewMigrationOutranksEveryAppliedOne`, существующий, зелёный)
**And** правка применённого файла миграции ленты — красный `notifygen -check` с именем файла: генератор держит побайтовое содержимое каждой выпущенной им версии схемы и сверяет с ним файлы дерева (гейт монотонности правки содержимого не видит — он судит только номер добавленного файла)
**And** близнец отрицания: то же дерево без правки применённого файла (v1 побайтово как выпущен, v2_from_v1 добавлен) — `notifygen -check` зелёный

**ID:** NTF1-D05 — **рантайм источника не тянет формат и рендер**

**Given** `notify-probe` на пине corelib с `notify/*`
**When** `go list -deps ./services/notify/cmd/notify-probe | grep -c 'corelib/notify/spec'`
**Then** **0**; инъекция импорта `notify/spec` в рантайм — красный гейт с координатой

**ID:** NTF1-D06 — **версия генератора равна пину corelib**

**Given** `go.mod` kacho
**When** гейт читает директивы
**Then** генератор подключён директивой `tool`; `go tool notifygen -version` печатает версию пина

### E. Сигнал подписки — раздел «notify» (S3)

**ID:** NTF1-E01 — **постановка даёт notify событие без атрибутов, и письмо уходит**

**Given** фикстурный источник `probe` с сервером подписки и лентой; модель посеяна как в F01; notify открыл подписку на `probe` с `kinds: ["notification_feed"]`
**When** в `probe` коммитится постановка письма с посеянными уникальными значениями атрибутов
**Then** notify получает событие вида `notification_feed` с объектом `notification_feed:probe`, состояние — словом в `state_unavailable`
**And** байты события не содержат ни одного посеянного значения, ни адреса, ни имени шаблона
**And** notify вызывает `Claim`, `ResolveSend` (`ALLOW`) и отправляет письмо; на тестовом узле одна сессия с этим получателем

**ID:** NTF1-E02 — **служба без `reader` событий ленты не видит** (близнец — тот же подписчик с `reader` в фикстурной проверке прав)

**Given** условия E01; служба `probe-b` (ключ таблицы Р2 источника) открывает подписку на `probe` с `kinds: ["notification_feed"]`; фикстурная проверка прав источника кортежа `service:probe-b reader notification_feed:probe` не несёт
**When** в `probe` коммитится постановка письма
**Then** поток `probe-b` открыт, события по `notification_feed:probe` он не несёт; поток notify это событие несёт (E01)
**And** близнец: в фикстурной проверке прав посеян кортеж `service:probe-b reader notification_feed:probe` (в модели kaname такой кортеж невыразим — F03; здесь он различает ровно один факт), остальное то же — поток `probe-b` несёт событие по `notification_feed:probe`

**ID:** NTF1-E03 — **поток недоступен — письмо уходит по таймеру** (близнец E01)

**Given** условия E01, но сервер подписки источника остановлен; сервер ленты доступен; таймер `Claim` = T
**When** коммитится постановка письма
**Then** письмо отправлено не позже T после постановки (управляемые часы)
**And** метрика notify «поток источника недоступен» ненулевая

**ID:** NTF1-E04 — **таймер `Claim` без значения — отказ старта notify** (близнец — задан)

**Given** notify в боевой посадке без ручки таймера `Claim`
**When** процесс стартует
**Then** старт отвергнут с именем ручки; с заданной — стартует

### M. Звено идентичности служб — раздел «corelib» (S1)

**ID:** NTF1-M01 — **точный SAN на методе перечня даёт `service:notify` и открывает подписку**

**Given** модульная проба corelib: перечень `{Subscribe}`, таблица `{spiffe://T/ns/N/sa/kacho-notify → notify}`; пир с проверенным сертификатом этого SAN, пересланного принципала нет
**When** сервер подписки обрабатывает `Subscribe` с видом, чей объект виден `service:notify`
**Then** поток открыт; субъект сужения — `service:notify`; пол `acr` вынесен `EvaluateStepUp` как машинному принципалу

**ID:** NTF1-M02 — **метод вне перечня — субъекта нет** (близнец M01)

**Given** условия M01
**When** тот же пир вызывает посеянный пробный метод с `scope_filtered` вне перечня, обслуживаемый за звеном `authz.Interceptor`
**Then** `PERMISSION_DENIED`, текст `permission denied` — производитель `authz.Interceptor`, ветка «субъекта нет» (шаг извлечения субъекта стоит до ветки `ScopeFiltered`); обработчик не вызван
**And** тот же метод, внесённый в перечень, от того же пира вызывает обработчик с субъектом `service:notify`

**ID:** NTF1-M03 — **сравнение SAN — равенство полного URI** (близнец M01)

**Given** условия M01
**When** пир предъявляет SAN, отличающийся от ключа только доменом доверия; только пространством имён; только именем учётки; либо равный ключу по началу, но длиннее
**Then** в каждом случае субъекта нет, `Subscribe` — `PERMISSION_DENIED` «subscription requires an authenticated caller»
**And** SAN, равный ключу, в той же пробе даёт исход M01

**ID:** NTF1-M04 — **пересланная личность без проверенного сертификата — отказ** (близнец M01)

**Given** модульная проба с синтезированным контекстом пира (`verified = false`), контекст несёт заголовки личности
**When** сервер подписки обрабатывает `Subscribe`
**Then** `PERMISSION_DENIED` «subscription requires an authenticated caller»; поток не открыт
**And** тот же запрос с `verified = true` и SAN из таблицы открывает поток с `service:notify`

**ID:** NTF1-M05 — **пересланный принципал решает; вне круга пересылка снимается** (близнец — край из круга)

**Given** круг пересылающих = {край}; пир — служба `probe-b` с проверенным сертификатом (ключ таблицы → `probe-b`), вне круга; заголовки несут пользователя `U`, у которого право на объект `O` есть, а у `service:probe-b` нет
**When** `probe-b` вызывает `Subscribe` с видом, объект которого — `O`
**Then** пересланный принципал снят; субъект — `service:probe-b`; событий по `O` поток не несёт
**And** те же заголовки от края дают субъект `user:U`, и событие по `O` приходит; субъект из сертификата с ним не смешан

**ID:** NTF1-M06 — **служебный принципал не владелец операций, даже когда метод операций в перечне** (близнец — принципал от края)

**Given** модульная проба corelib со звеном Р2, перечень которого **включает** `OperationService.Get` (метод в каталоге прав пробы), таблица `{SAN notify → notify}`; системная операция `op-s`; операция `op-u` пользователя `U`
**When** пир с сертификатом notify без пересланного принципала вызывает `OperationService.Get(op-s)` и `Get(op-u)`
**Then** субъект звена прав — `service:notify` (метод в перечне), а `operations.PrincipalFromContext` в обработчике сообщает «принципала нет»; оба ответа побайтово равны ответам на тот же вызов с сертификатом, SAN которого в таблице нет; операция не отдана ни одна
**And** `Get(op-u)` с `U`, пересланным краем, отдаёт операцию

**ID:** NTF1-M07 — **прочие внутренние вызовы модулей не меняются** (близнец — `ResolveSend` в перечне)

**Given** kaname с перечнем Р2 = `{ResolveSend}`; записанные до Р2 ответы на корпус внутренних вызовов модулей (`InternalIAMService/Check`, `RegisterResource`, `Allocate*`) от их учёток
**When** корпус исполняется после Р2
**Then** каждый ответ побайтово равен записанному; в контексте этих методов служебного принципала нет
**And** на `ResolveSend` от notify служебный принципал `service:notify` есть

**ID:** NTF1-M08 — **`authz.Interceptor` kacho видит служебный принципал до ветки `ScopeFiltered`, одинаково на обоих слушателях** (близнец — пустой перечень)

**Given** служба kacho (`notify-probe` в integration-пробе) со звеном прав `authz.Interceptor` на публичном и внутреннем слушателях; перечень `{Subscribe, Claim, Ack}`, таблица `{SAN notify → notify}`
**When** notify вызывает `Claim` (не `ScopeFiltered`) и `Subscribe` (`ScopeFiltered`) на каждом слушателе, где метод обслуживается, а проба перехватчика зовёт извлекатель на обоих слушателях
**Then** извлекатель отдаёт `service:notify` на обоих слушателях; `Claim` проходит `Check(service:notify, reader, notification_feed:notify-probe)`; `Subscribe` открыт
**And** с пустым перечнем и пустой таблицей извлекатель отдаёт «субъекта нет», и оба вызова — `PERMISSION_DENIED` как до Р2
**And** гейт дерева находит у `listnarrow` и `authz` одну функцию извлечения служебного принципала; инъекция второй — находка

**ID:** NTF1-M09 — **стражи старта звена** (близнец — согласное звено)

**Given** служба в боевой посадке
**When** по отдельности: (а) перечень непуст, таблица пуста; (б) таблица непуста, перечень пуст; (в) метод перечня вне каталога прав; (г) один SAN дважды; (д) одно имя дважды; (е) имя не DNS label
**Then** каждый — отказ старта с именем ручки и значением; слушатели не подняты
**And** с согласным звеном служба стартует, самоотчёт несёт перечень и строки таблицы, `assert-production-posture` их оценивает

**ID:** NTF1-M10 — **арендатор служебный принципал не создаёт** (близнец — тенантский субъект и разрешённый тип)

**Given** kaname; администратор аккаунта; модульная учётка с правом `RegisterResource`
**When** (а) `AccessBinding.Create` с субъектом типа `service`; (б) `RegisterResource` с типом объекта `service`, `notification_feed`, `notification_namespace`
**Then** (а) `INVALID_ARGUMENT`, `field = subjects[0].type`, текст `subjects[0].type: 'service' is not a grantable subject type`, `Operation` не создана; (б) `PERMISSION_DENIED`, `permission denied` (отображение `TestProxyTupleRefusalMapsToPermissionDenied`); кортежей с субъектом `service:` и объектом этих типов не прибавилось
**And** (а) с субъектом `user` и (б) с разрешённым типом — приняты
**And** гейт дерева kaname: писатель кортежей с субъектом `service:` — только применитель манифеста; инъекция второго — находка

### F. Права в модели kaname — раздел «kaname» (S2)

**ID:** NTF1-F01 — **строка манифеста даёт `sender` и `reader`; `ResolveSend` — `ALLOW`**

**Given** доставленный фикстурный манифест модуля `probe` несёт `notifications: {namespace: probe, readers: [notify]}`; манифест `services/notify/manifest.yaml` доставлен; kaname поднят, посев прошёл; таблица Р2 kaname = `{SAN notify → notify}`
**When** notify зовёт `ResolveSend(probe, probe-hello, enqueued_at = сейчас)`
**Then** `ALLOW`
**And** `Check(service:probe, sender, notification_namespace:probe)` и `Check(service:notify, reader, notification_feed:probe)` — `true`
**And** в integration-пробе notify: выдали → поставили → отправил: на тестовом узле одна сессия

**ID:** NTF1-F02 — **`namespace` не своего модуля отвергается** (близнец F01)

**Given** манифест модуля `probe` несёт `notifications: {namespace: vpc, readers: [notify]}`
**When** исполняется `tools/modulemanifestcheck`
**Then** находка «пространство не своего модуля» с именем модуля и строки; посев строку не применяет; кортежей по `vpc` нет

**ID:** NTF1-F03 — **читатель не `notify` отвергается** (близнец F01)

**Given** манифест модуля `probe` несёт `notifications: {namespace: probe, readers: [compute]}` — либо `readers: [notify, compute]`
**When** исполняется `tools/modulemanifestcheck` и применитель посева
**Then** находка «reader ленты — только notify» с именем модуля и строки; кортежа `service:compute reader notification_feed:probe` нет; посев строку не применяет
**And** та же строка с `readers: [notify]` (F01) — кортеж `service:notify reader notification_feed:probe` заведён

**ID:** NTF1-F04 — **права ещё нет — `NOT_YET_GRANTED`, строка ждёт** (близнец F01)

**Given** манифест `probe` без `notifications`; записи выдачи и надгробия нет; строка поставлена в `t0`
**When** notify забирает строку и зовёт `ResolveSend(probe, probe-hello, t0)`
**Then** `NOT_YET_GRANTED`; `Ack DEFER(grant_skew)`; попытка не потрачена; тревога `grant_skew` сразу
**And** строка манифеста появляется, посев создаёт выдачу в `t1 > t0`; `ResolveSend(t0)` — `ALLOW`, строка отправлена в пределах срока

**ID:** NTF1-F05 — **отзыв — терминальный отказ, секрет стёрт** (близнец F01)

**Given** условия F01; администратор кластера вызвал `Revoke(probe)`, Operation `done`
**When** notify забирает строку, поставленную до отзыва, и строку после
**Then** обе — `DENIED(revoked)`, секрет стёрт, SMTP-сессий 0
**And** `Check(service:probe, sender, notification_namespace:probe)` — `false` после опустошения очереди kaname

**ID:** NTF1-F06 — **восстановление не выпускает накопленное** (близнец F01)

**Given** `Revoke(probe)`; поставлены 3 строки; затем `Restore(probe)`, Operation `done`; затем, позже отсечки на полосу и больше, 4-я строка
**When** notify забирает все четыре
**Then** три первые — `DENIED(revoked)`, SMTP-сессий по ним 0; четвёртая отправлена

**ID:** NTF1-F07 — **отзыв одного шаблона не трогает соседний** (близнец F01 по второму шаблону)

**Given** `Revoke(probe, probe-hello)`; поставлены строки `probe-hello` и `probe-bye`
**When** notify забирает обе
**Then** `probe-hello` — `DENIED(revoked)`; `probe-bye` — отправлено

**ID:** NTF1-F08 — **перезапуск kaname не оживляет отозванное; посев идемпотентен** (близнец — без `Revoke`)

**Given** `Revoke(probe)`; kaname перезапущен, посев прошёл заново
**When** notify зовёт `ResolveSend`
**Then** `REVOKED`; запись выдачи побайтово та же
**And** без `Revoke`: строка в `t0`, перезапуск в `t1 > t0`; `ResolveSend(t0)` — `ALLOW`; два перезапуска подряд оставляют запись побайтово неизменной

**ID:** NTF1-F09 — **`ResolveSend` — только читателю ленты этого пространства** (близнец F01)

**Given** условия F01; модель несёт также `service:notify reader notification_feed:probe`, но не `…:probe-c`
**When** (а) `ResolveSend(probe, …)` зовёт служба, чей SAN не ключ таблицы kaname; (б) notify зовёт `ResolveSend(probe-c, …)`
**Then** оба — `PERMISSION_DENIED`, `permission denied`, `ErrorInfo{reason: AUTHZ_DENIED, …}` от `DenyDetailUnary`; решения в ответе нет
**And** notify на `ResolveSend(probe, …)` — `ALLOW` (F01)

**ID:** NTF1-F10 — **`Revoke` — только администратору кластера** (близнец F05)

**Given** пользователь без роли администратора кластера
**When** он вызывает `Revoke(probe)`
**Then** `PERMISSION_DENIED`; надгробия нет; `ResolveSend` — `ALLOW`

**ID:** NTF1-F11 — **kaname недоступна — строка ждёт** (близнец F01)

**Given** строка арендована notify; внутренний слушатель kaname остановлен
**When** notify зовёт `ResolveSend`
**Then** `Ack DEFER(platform_unavailable)`; попытка не потрачена; SMTP-сессий 0
**And** после подъёма kaname в пределах срока строка отправлена

**ID:** NTF1-F12 — **надзор администратора облака на типах Р5 не срабатывает ни в одном месте обобщённой двери** (близнецы — служебный принципал; и администратор на типе вне перечня)

**Given** условия F01; пользователь `U_ca` — администратор облака (`system_admin` на `cluster`) с подтверждённым адресом (допуск субъекта §1.11 его не отсекает), кортежей на объектах типов Р5 у него нет; для близнеца по типу посеян пользователь `U2`, объект `iam_user:<id U2>`: отношение `token_issuer` модель определяет как `subject` без ветви администратора, поэтому администратору облака его даёт **только** надзор (довод записан у `checkAdapter`, `own_door.go`) — модель на вопрос `U_ca` отвечает «нет»
**When** каждый подслучай идёт своим входом двери (§1.11), и каждое место Д-1…Д-7 достигнуто хотя бы одним:
- (а) `InternalIAMService/Check` `{subject: user:U_ca, relation: sender, object: notification_namespace:probe}` — место Д-3 `verdictForRelation`;
- (б) `InternalIAMService/Check` `{subject: user:U_ca, relation: reader, object: notification_feed:probe}` — Д-3;
- (в) публичный `AuthorizeService/BatchCheck` от `U_ca` о себе: пункты `{subject: user:U_ca, action: <непустое действие>, required_relation: reader, resource: notification_feed/probe}`, то же с `notification_feed/probe-c` и с `notification_feed/*` — Д-5 `resolveRun` (пообъектный отказ) и Д-4 (прогон «вопроса нет»);
- (г) публичный `AuthorizeService/Check` от `U_ca` о себе с непустым действием и `required_relation: reader`, ресурс `notification_feed/*` — Д-1 `check`, ветка «вопроса нет» по идентификатору `*`;
- (д) публичный `AuthorizeService/Check` от `U_ca` о себе на `notification_feed/probe` с действием, не разрешающимся в отношение, без `required_relation` — Д-1, ветка «вопроса нет» по действию;
- (е) публичный `AuthorizeService/Check` от `U_ca` о себе с непустым действием и `required_relation: reader` на `notification_feed/probe` — Д-2 `verdict`;
- (ж) модульная проба kaname: `checkAdapter.Check(user:U_ca, reader, notification_feed:probe)` двери публичного слушателя и `AllowsVerb(reader, notification_feed, probe)` с принципалом `U_ca` в контексте — Д-6, Д-7
**Then** каждый пункт каждого подслучая — `allowed = false` (в (ж) — `false` без ошибки), отказ назван, `UNAVAILABLE` нет
**And** близнец по субъекту (меняется только субъект вопроса): (а) от `service:probe`; (б), (в, пункт `probe`), (е) от `service:notify` — `true`; вопрос о чужом субъекте в (в), (е) задаёт тот же `U_ca`: право **задать** вопрос у администратора облака есть (`authorizeCaller`, §1.11), ответ даёт дверь
**And** близнец по типу (меняется только объект вопроса — тип вне перечня с отношением, которое этот тип объявляет): (а), (б) — `InternalIAMService/Check` `{user:U_ca, token_issuer, iam_user:<id U2>}`; (в) — пункты `iam_user/<id U2>` и `iam_user/*` с `required_relation: token_issuer`; (г) — `iam_user/*`; (д) — `iam_user/<id U2>` с тем же неразрешающимся действием; (е) — `iam_user/<id U2>` с `required_relation: token_issuer`; (ж) — `checkAdapter.Check` и `AllowsVerb` на `iam_user:<id U2>` с `token_issuer` — каждый `true`: модель ответила «нет», «да» дал надзор (надзор жив вне перечня)
**And** гейт дерева kaname (§1.11, держатель переписи): перечень типов объявлен одним местом; каждое место класса «обобщённая дверь», найденное разбором, стоит под предикатом перечня; гейт судит множество мест из переписи, а не число; инъекция места без предиката, места вне ведомости классов или второй декларации перечня — находка с координатой; без инъекции гейт молчит и печатает число мест по классам

**ID:** NTF1-F13 — **негодный вход отвергается синхронно с именем поля** (близнецы F01 / F05 / F06)

**Given** условия F01; администратор кластера для `Revoke`/`Restore`
**When** по отдельности: `ResolveSend(namespace = "")`; `ResolveSend(namespace = "Bad_Ns")`; `ResolveSend(probe, template = "Invite_1")`; `ResolveSend(probe, probe-hello)` без `enqueued_at`; `Revoke(namespace = "Bad_Ns")`; `Restore(namespace = "Bad_Ns")`
**Then** каждый — `INVALID_ARGUMENT` с текстом и деталями строки таблицы отказов Р5
**And** `Operation` не создана, запись и кортеж не изменились
**And** тот же вызов с исправленным полем даёт исход F01, F05, F06 соответственно

**ID:** NTF1-F14 — **`ResolveSend` на неизвестное пространство — исход, а не ошибка** (близнец F01)

**Given** пространство `probe-c` по форме, без записи выдачи и надгробия; notify — `reader` ленты `probe-c`
**When** notify зовёт `ResolveSend(probe-c, probe-hello, сейчас)`
**Then** исход `NOT_YET_GRANTED` (не код ошибки gRPC)
**And** `ResolveSend(namespace = "Bad_Ns")` — `INVALID_ARGUMENT` (F13): форма проверяется первым шагом

**ID:** NTF1-F15 — **`Revoke`/`Restore` неизвестного пространства — `NOT_FOUND`** (близнец F05)

**Given** пространство `probe-c` из F14
**When** администратор вызывает `Revoke(probe-c)`, затем `Restore(probe-c)`
**Then** оба — `NOT_FOUND`, `NotificationNamespace probe-c not found`, `reason = RESOURCE_NOT_FOUND`, `metadata = {resource_type: notification_namespace, resource_id: probe-c}`; `Operation` не создана; надгробия у `probe-c` нет

**ID:** NTF1-F16 — **повторный `Revoke` — `FAILED_PRECONDITION`** (близнец F05)

**Given** `Revoke(probe)` исполнен
**When** повторный `Revoke(probe)`; и после F07 — повторный `Revoke(probe, probe-hello)`
**Then** `FAILED_PRECONDITION`, `NotificationNamespace probe is already revoked` / `NotificationNamespace probe template probe-hello is already revoked`, `reason = NOTIFICATION_GRANT_STATE`; `Operation` не создана; «отозвано» прежнее

**ID:** NTF1-F17 — **`Restore` без надгробия — `FAILED_PRECONDITION`** (близнец F06)

**Given** выдача активна, отсечки нет; строка поставлена в `t0`
**When** `Restore(probe)` в `t1 > t0`; и `Restore(probe, probe-hello)`, когда у шаблона надгробия нет
**Then** `FAILED_PRECONDITION`, `… is not revoked` / `… template probe-hello is not revoked`, `reason = NOTIFICATION_GRANT_STATE`; `Operation` не создана; отсечек нет
**And** `ResolveSend(t0)` — `ALLOW`

**ID:** NTF1-F18 — **гонка на записи выдачи: ровно один переход** (близнец — последовательно)

**Given** выдача активна
**When** (а) 8 горутин — `Revoke(probe)`; (б) затем 8 — `Restore(probe)`; (в) из активного `Revoke ∥ Restore`; (г) записи шаблона нет, 8 — `Revoke(probe, probe-hello)`; (д) затем 8 — `Restore(probe, probe-hello)`
**Then** (а), (б), (г), (д) — ровно одна `Operation` успешна, 7 — `FAILED_PRECONDITION` `NOTIFICATION_GRANT_STATE`; в (г) запись шаблона ровно одна; в (г), (д) запись выдачи побайтово прежняя
**And** (в) — одно из двух законных последовательных состояний, третьего нет
**And** после опустошения очереди kaname кортеж `sender` есть ⇔ надгробия нет; гейт дерева не находит чтения состояния с последующей безусловной записью
**And** те же вызовы последовательно дают ровно одну успешную `Operation` на переход

**ID:** NTF1-F19 — **восстановление шаблона не выпускает накопленное по нему** (близнец F06)

**Given** `Revoke(probe, probe-hello)`; поставлены `probe-hello` (r1) и `probe-bye` (i1); `Restore(probe, probe-hello)`; позже, чем отсечка шаблона плюс полоса, — ещё `probe-hello` (r2)
**When** notify забирает все три
**Then** r1 — `DENIED(revoked)`, SMTP-сессий 0; i1 и r2 — отправлены; запись выдачи пространства без надгробия и отсечки

**ID:** NTF1-F20 — **полоса отсечки: строки в полосе после `Restore` — `REVOKED`** (близнец — строка за полосой)

**Given** полоса `notificationCutoffGuard` = G; `Revoke(probe)`, `Restore(probe)` с отсечкой `c` по часам kaname
**When** `ResolveSend` по строкам с `enqueued_at` = `c − 1s`, `c + G − 1s`, `c + G`
**Then** первые две — `REVOKED`; третья — `ALLOW`
**And** kaname в боевой посадке без полосы или с полосой вне `[1s..10m]` не стартует, отказ называет ручку и границу; с полосой в границах — стартует

**ID:** NTF1-F21 — **исключение службы доступа: только `readers`, без `namespace`** (близнец — форма без `namespace`)

**Given** фикстурный манифест службы доступа (форма `manifest.embedded.yaml`)
**When** валидатор и применитель обрабатывают его с (а) `notifications: {readers: [notify]}`; (б) `notifications: {namespace: kaname, readers: [notify]}`
**Then** (б) — находка «у службы доступа служебного принципала нет (MRW-1 Р1)», ни одного кортежа не заведено
**And** (а) — принят: заведён ровно `service:notify reader notification_feed:kaname`; кортежей с субъектом `service:kaname` и объектом `notification_namespace:kaname` 0; `TestMRW07_GroupWithItsGrantIsAccepted` зелёный

**ID:** NTF1-F22 — **пересланный администратор облака не забирает тело, не получает решения и не видит событий ленты** (близнец — те же вызовы от `service:notify`)

**Given** условия F01 и C03; фикстурный край в круге пересылающих источника `probe` и kaname пересылает `U_ca` (F12); в ленте `probe` одна строка `pending`
**And** проверку прав источника `probe` решает **настоящая дверь kaname**, поднятая в процессе пробы на testcontainers с посевом F01, а не фикстурная проверка прав §6 — (а) `Claim` спрашивает её входом `InternalIAMService/Check` (место Д-3 §1.11), (в) сужение строк подписки — входом `BatchCheck` (Д-4, Д-5), (б) право вызова `ResolveSend` — той же функцией вердикта, что `InternalIAMService/Check` (Д-3)
**When** от фикстурного края с пересланным `U_ca`: (а) `Claim(max=10, classes={notice})` на внутреннем слушателе `probe`; (б) `ResolveSend(probe, probe-hello, сейчас)` на внутреннем слушателе kaname; (в) `Subscribe` на `probe` с `kinds: ["notification_feed"]`, затем в `probe` коммитится постановка письма
**Then** (а) `PERMISSION_DENIED`, текст `permission denied`; строка не арендована (следующий `Claim` notify её получает); (б) `PERMISSION_DENIED`, `permission denied`, `ErrorInfo{reason: AUTHZ_DENIED, …}`, решения в ответе нет; (в) поток открыт, события по `notification_feed:probe` не несёт
**And** близнец: те же три вызова от notify по его сертификату без пересланного принципала (субъект `service:notify`) — (а) строка в ответе; (б) `ALLOW`; (в) событие по `notification_feed:probe` приходит

### G. Служба notify — раздел «notify» (S3)

**ID:** NTF1-G01 — **перечень источников: пустой или неполный — отказ старта** (близнец — полный)

**Given** notify в боевой посадке; перечень пуст — либо у записи нет одного из полей
**When** процесс стартует
**Then** старт отвергнут с именем ручки и, для неполной записи, с её модулем и недостающим полем
**And** с полным перечнем стартует

**ID:** NTF1-G02 — **служба А не может отправить шаблон службы Б** (близнец — шаблон в своём пространстве)

**Given** в сборке notify шаблон `probe-bhello` есть только в пространстве `probe-b`; источник `probe` (форма `address` разрешена, `standProbeNamespace = probe`) поставил строку с `template = probe-bhello`
**When** notify забирает строку из ленты `probe`
**Then** шаблон ищется как `probe/probe-bhello` и не найден; `DEFER(template_skew)`; тревога `template_skew` сразу; SMTP-сессий 0
**And** строка истекает `EXPIRED(template_skew)` и не отправляется никогда
**And** когда `probe-bhello` есть и в `probe`, та же строка отправлена по шаблону `probe/probe-bhello`

**ID:** NTF1-G03 — **письмо собрано общим макетом: эталон `.eml`**

**Given** шаблон фикстуры `kaname/invite` (форма A01), атрибуты с не-ASCII именем; управляемые часы; origin `https://console.example.invalid`
**When** notify рендерит письмо
**Then** оно побайтово равно `services/notify/testdata/golden/kaname/invite.ru.eml`
**And** `multipart/alternative` из `text/plain` и `text/html`; стили inline; картинки только `cid:`
**And** в HTML ни одного обращения к внешнему ресурсу — перепись по всем эталонам со знаменателем
**And** тема по RFC 2047; кнопка ведёт на `https://console.example.invalid/<путь>?token=<токен>`

**ID:** NTF1-G04 — **значение атрибута с разметкой экранируется** (близнец G03)

**Given** условия G03, но `inviter_name = "<a href=x>Y</a>"`
**When** notify рендерит письмо
**Then** в HTML-части значение экранировано, элементов `<a>` из атрибута 0; в текстовой — как есть

**ID:** NTF1-G05 — **CR/LF в значении заголовка — `INVALID`** (близнец G03)

**Given** условия G03, но значение, входящее в тему, содержит `\r\n`
**When** notify обрабатывает строку
**Then** `Ack INVALID`; SMTP-сессий 0

**ID:** NTF1-G06 — **без origin установки — отказ старта** (близнец — задан)

**Given** notify в боевой посадке без ручки origin
**When** процесс стартует
**Then** отказ с именем ручки; с заданной — стартует

**ID:** NTF1-G07 — **ретранслятор без TLS — письмо не уходит** (близнец — узел с TLS)

**Given** тестовый узел не предлагает STARTTLS и не слушает неявный TLS
**When** notify обрабатывает строку
**Then** `MAIL FROM` не отправлен; `DEFER(platform_unavailable)`; размыкатель открыт; попытка не потрачена
**And** на узле с TLS та же строка отправлена
**And** ручки отключения проверки TLS в конфигурации notify нет (перепись ручек)

**ID:** NTF1-G08 — **недоверенный сертификат ретранслятора** (близнец — узел с TLS из G07)

**Given** узел предлагает TLS с сертификатом не из доверенного набора
**When** notify обрабатывает строку
**Then** `DEFER(platform_unavailable)`, `MAIL FROM` не отправлен

**ID:** NTF1-G09 — **отказ `AUTH` — не отравление** (близнец — `AUTH` принят)

**Given** узел отвечает 535 на `AUTH`
**When** notify обрабатывает 20 строк
**Then** все — `DEFER(platform_unavailable)`, сигнал `misconfigured` ненулевой, терминальных исходов 0
**And** после смены удостоверения на принимаемое все 20 отправлены

**ID:** NTF1-G10 — **отказ получателя — терминальный и отдельный** (близнец — `RCPT` 250)

**Given** узел отвечает 550 на `RCPT` одному адресату и 250 остальным
**When** notify обрабатывает по строке на каждого
**Then** строка отвергнутого — `RECIPIENT_REJECTED`, счётчик по `(пространство, шаблон)` +1; остальные отправлены; `misconfigured` нулевой

**ID:** NTF1-G11 — **ретранслятор лежит долго — ничего не отравлено** (близнец — узел доступен)

**Given** узел недоступен дольше любого бюджета попыток (управляемые часы); строки с разными сроками
**When** узел возвращается
**Then** непросроченные отправлены; просроченные закрыты `EXPIRED(platform_unavailable)`; терминальных исходов иного рода 0

**ID:** NTF1-G12 — **тревога на половине срока письма `security`** (близнец — возраст меньше половины)

**Given** фикстурный шаблон `kaname/recovery` класса `security`, `ttl = 5m`; строка `pending`, ретранслятор недоступен
**When** возраст строки достигает 2 мин 30 с
**Then** правило тревоги срабатывает
**And** при 2 мин 29 с — не срабатывает

**ID:** NTF1-G13 — **в журналах нет PII и секретов** (близнец — id строки в журнале есть)

**Given** строки с посеянными уникальными адресом, `text`, кодом и токеном
**When** они проходят все исходы Р11
**Then** ни одно посеянное значение не встречается в журналах notify и источника
**And** идентификатор каждой строки встречается

**ID:** NTF1-G14 — **каждый ответ ретранслятора — в названной клетке**

**Given** узел, отвечающий 250, 421, 451, 535, 550 на `RCPT`, 552 на `DATA`, 554 на `MAIL FROM`, разрыв
**When** notify обрабатывает по строке на ответ
**Then** каждый — клетка Р11; «прочего» нет; 5xx вне `RCPT` — `DEFER` с `misconfigured`

**ID:** NTF1-G15 — **посадка notify: боевые оси** (близнец — посадка исправна)

**Given** notify в боевой посадке с одной нарушенной осью: mTLS выключен, `authMode` не `production`, секрет почты не смонтирован, `sslmode` базы не `require`
**When** процесс стартует
**Then** отказ с именем оси
**And** с исправной посадкой стартует; `assert-production-posture.sh` оценивает самоотчёт: новый элемент `NoServedServices` (`git grep -l NoServedServices` → 0 файлов в kacho `1d42a6728bf`, corelib `34bc810`, kaname `734f69fb4`), перечень Р2 у notify пуст

**ID:** NTF1-G16 — **две реплики; падение реплики не теряет писем**

**Given** notify с 2 репликами и PDB; 200 строк `pending`
**When** одна реплика удаляется посреди обработки
**Then** все 200 отправлены; дважды отправленных не больше числа строк в окне `DATA → Ack` удалённой реплики
**And** `Message-ID` каждого письма равен `hash(пространство, id строки)` и одинаков у дубля

**ID:** NTF1-G17 — **сборка шаблонов равна пересборке из дерева** (близнец — сборка обновлена)

**Given** в дереве `notify-probe` изменён шаблон; `make -C services/notify bundle` не выполнен
**When** гейт сборки notify
**Then** красный с именем шаблона и источника
**And** после `bundle` зелёный; эталоны и превью пересобраны тем же шагом

**ID:** NTF1-G18 — **отправитель один, `Reply-To` у `security` нет**

**Given** все эталоны `.eml` сборки
**When** перепись читает заголовки
**Then** у каждого `From` — адрес отправителя установки; у `security` `Reply-To` нет; перепись печатает число эталонов

**ID:** NTF1-G19 — **у notify нет входящего глагола и кастомных шаблонов**

**Given** notify поднят
**When** перепись слушателей пода, обслуживаемых сервисов и ручек конфигурации
**Then** слушатель один — диагностический HTTP с `/healthz`, `/readyz`, `/metrics`; gRPC-слушателя нет (порт gRPC в поде не объявлен и не открыт); перепись печатает число слушателей — **1**
**And** ручек пути к шаблонам и загрузки шаблонов нет; шаблоны читаются только из встроенной сборки
**And** перепись поверхности notify разбором по идентичности (цель вызова — по типам, а не по тексту): в не-тестовых файлах пакетов kacho под `services/notify/` (без `cmd/notify-probe` и пакетов только его корня) вызовов, чья цель — `google.golang.org/grpc.NewServer`, точка входа фундамента, поднимающая gRPC-сервер, либо функция `Register…Server` сгенерированного стаба, — **0**
**And** фундамент в предмет переписи не входит, и это не послабление: notify импортирует его законно — самоотчёт собирается через corelib `servicecontract` (G15), а `servicecontract` импортирует `grpcsrv`, где стоят `grpc.NewServer` и `RegisterHealthServer`; импортированная функция поднимает сервер только будучи вызванной, поэтому судится ВЫЗОВ из кода notify в точку входа фундамента, а не достижимость по импорту (перепись импортного замыкания покраснела бы на исправном notify)
**And** перечень точек входа не пишется по памяти — его выводит та же проба из пина corelib в `go.mod`: замыкание вызывающих `grpc.NewServer` по не-тестовым файлам corelib (разбор по идентичности), экспортируемые функции замыкания — точки входа; на corelib `34bc810` это `grpcsrv.NewServer` и `servicehost.Serve` (через `serverPair`); новая точка входа фундамента входит в перечень сама, без правки пробы
**And** перепись печатает число осмотренных пакетов, файлов и вызовов и выведенный перечень точек входа; пустой обход или пустой перечень — красный; инъекция вызова `grpcsrv.NewServer` в `cmd/notify` — находка с координатой; близнец — то же дерево notify без инъекции, где импорт `servicecontract` → `grpcsrv` на месте, — перепись молчит

**ID:** NTF1-G20 — **класс `security` — только пространствам `identityNamespaces`** (близнец — `security` в `kaname`)

**Given** шаблон класса `security` в пространстве `probe`
**When** гейт сборки notify; и отдельно — строка класса `security` (данные ленты) из пространства `probe` в integration-пробе
**Then** гейт — красный «класс security вне identityNamespaces» с именем шаблона; строка — `INVALID(class_not_allowed)`, SMTP-сессий 0
**And** тот же шаблон в фикстурном пространстве `kaname` — зелёный, строка отправлена

**ID:** NTF1-G21 — **адрес получателя — только разрешённым пространствам** (близнец — адрес из `kaname`)

**Given** запись перечня `probe` без формы `address`; `standProbeNamespace` не задан
**When** notify забирает строку `probe` с адресатом-адресом
**Then** `INVALID(recipient_form_not_allowed)`, SMTP-сессий 0
**And** та же строка из фикстурного пространства `kaname` отправлена
**And** страж старта notify отвергает запись перечня с формой `address` для пространства вне `{kaname, standProbeNamespace}` с именем записи

**ID:** NTF1-G22 — **исключение `kaname`: сертификат вместо `ResolveSend`, и только для `kaname`** (близнец — пространство `probe` зовёт `ResolveSend`)

**Given** перечень notify: `kaname` с `authorization: certificate` и SAN из `kaname.spiffe`; `probe` без исключения; фикстурные источники обоих в процессе
**When** notify забирает по строке из каждого
**Then** строка `kaname` отправлена без вызова `ResolveSend` (счётчик вызовов 0); строка `probe` — после `ResolveSend` (`ALLOW`)
**And** если сервер ленты `kaname` предъявил SAN, отличный от записи, — подключение отвергнуто, `Claim` не вызван, тревога `source_identity_mismatch`
**And** страж старта notify отвергает `authorization: certificate` у любой записи, кроме `kaname`, с именем записи

### H. Лимиты notify — раздел «notify» (S3)

**ID:** NTF1-H01 — **сетка `security` на адресата: сверх — `DROPPED` и тревога** (близнец — в пределах)

**Given** сетка `security` = S в сутки; единственный источник класса `security` — фикстурный `kaname` (`identityNamespaces`, Р6); адрес `a` уже получил от него S писем за сутки
**When** notify обрабатывает ещё одну строку `security` на `a` из ленты `kaname`
**Then** `DROPPED(recipient_net)`, секрет стёрт, SMTP-сессий 0; тревога сетки `security`; `notify_recipient_net_hits_total{class="security"}` +1
**And** при S−1 доставленных та же строка отправлена

**ID:** NTF1-H02 — **сетка прочего: сверх — ждёт окна, не теряется** (близнец — в пределах)

**Given** сетка `notice` = N в час; адрес `a` получил N писем за час из ленты `probe`
**When** в `probe` поставлена ещё одна строка `notice` на `a`, срок которой больше часа
**Then** `DEFER(recipient_net)`, попытка не потрачена; после освобождения окна (управляемые часы) — отправлена
**And** строка со сроком короче остатка окна — `EXPIRED(recipient_net)`; при N−1 доставленных строка отправлена сразу

**ID:** NTF1-H03 — **сетка точна поперёк реплик** (близнец — последовательно)

**Given** 2 реплики notify, сетка `security` = S; 2S строк `security` на один адрес в ленте фикстурного `kaname` (единственного источника класса)
**When** реплики обрабатывают их параллельно
**Then** отправлено ровно S, `DROPPED(recipient_net)` — ровно S; счётчик в `kacho_notify` = S
**And** последовательная обработка даёт то же; в базе нет адреса открытым текстом (выгрузка таблиц `kacho_notify` не содержит посеянного адреса)

**ID:** NTF1-H04 — **ведро источника задерживает, но не теряет** (близнец — в пределах темпа)

**Given** ведро источника `probe` (`notify.sourceLimits.probe.rate = 5`, `burst = 5`); поставлено 50 строк
**When** notify обрабатывает ленту
**Then** все 50 отправлены; терминальных исходов из-за ведра 0; `notify_source_throttled_total{source="probe"}` > 0
**And** при 5 строках ведро не срабатывает

**ID:** NTF1-H05 — **суточный потолок потока: выше — только `security`** (близнец — ниже потолка)

**Given** потолок = P; за сутки отправлено P; в ленте фикстурного `kaname` строки `security`, в ленте `probe` — `notice`
**When** notify обрабатывает ленты
**Then** notify вызывает `Claim(classes={security})`; `security` отправлены; `notice` остаются `pending`
**And** ниже потолка notify забирает оба класса

**ID:** NTF1-H06 — **пауза источника — только оператором, `security` не трогает** (близнец — без паузы)

**Given** `notify.sourceLimits.probe.paused = true`, заданная значением установки; фикстурный `kaname` не на паузе; в ленте `kaname` строки обоих классов, в ленте `probe` — `notice`
**When** notify обрабатывает ленты
**Then** у `probe` notify зовёт `Claim(classes={security})` — ответ пуст, `notice` остаются `pending`; у `kaname` забирается всё
**And** перепись поверхностей notify: вызова паузы в рантайме нет (G19); без паузы `probe` обрабатывается полностью

**ID:** NTF1-H07 — **инвариант «сетка ≥ 1,25 × сумма лимитов источников»** (близнец — инвариант выполнен)

**Given** сборка с шаблонами `security`, сумма суточных `limits` на адресата = 27
**When** notify стартует с сеткой 33
**Then** отказ старта: «сетка security 33 меньше 1,25 × 27», с именем ручки
**And** с сеткой 34 — стартует

**ID:** NTF1-H08 — **ручки лимитов без значения или вне границы — отказ старта** (близнец — в границах)

**Given** notify в боевой посадке
**When** по отдельности: любая ручка Р10 не задана; `recipient.security.perDay = 0`; `= 1001`; `notify.sourceLimits.probe.rate = 0`
**Then** отказ старта с именем ручки и границей
**And** со всеми ручками в границах — стартует

**ID:** NTF1-H09 — **метрики лимитов без PII**

**Given** срабатывания H01–H06 с посеянными адресами
**When** снимаются метрики notify
**Then** есть `notify_recipient_net_hits_total{class}`, `notify_source_throttled_total{source}`, `notify_global_ceiling_hits_total`, `notify_source_paused{source}`
**And** ни одна метка и ни одно значение не содержит посеянного адреса или его хеша

**ID:** NTF1-H10 — **сетка `notice` считается поперёк источников** (близнец — N−1 поперёк тех же источников)

**Given** сетка `notice` = N в час; два источника с формой `address` — фикстурный `kaname` (строки `notice`) и `probe`; адрес `a` получил за час k писем `notice` из `kaname` и N−k из `probe`, 0 < k < N
**When** в `probe` поставлена ещё одна строка `notice` на `a`
**Then** `DEFER(recipient_net)`, попытка не потрачена, SMTP-сессий по ней 0; счётчик сетки адреса в `kacho_notify` один на оба источника
**And** близнец: из `kaname` получено k−1 (всего N−1), остальное то же — строка отправлена сразу

### N. Флаг установки — разделы «notify» (S5) и «corelib» (S1)

**ID:** NTF1-N01 — **глобальный флаг не задан — рендер отвергнут** (близнец — задан)

**Given** цепочка по `deploy/stacks.txt` без `global.kacho.notifications.enabled`
**When** рендер зонтика
**Then** рендер отвергнут с именем ручки
**And** с заданным значением рендер проходит; перепись печатает число цепочек

**ID:** NTF1-N02 — **переопределение модуля выключает только его** (близнец — модуль включён)

**Given** гейт рендера на фикстурной копии чарта, где таблица подключаемых — два источника `notify-probe` и `probe-b`; глобальный `true`, `notifyProbe.notifications.enabled: false`, у `probe-b` переопределения нет
**When** рендер
**Then** перечень источников notify = `{probe-b}`: `notify-probe` в нём нет, notify и ссылка на секрет почты отрендерены; переменная процесса `notify-probe` — `KACHO_NOTIFYPROBE_NOTIFICATIONS_ENABLED=false`, у `probe-b` — `true`
**And** близнец: `notifyProbe.notifications.enabled: true` — перечень `{notify-probe, probe-b}`, переменная `notify-probe` — `true`

**ID:** NTF1-N03 — **перечень источников выводится, ручного нет** (близнец — дерево)

**Given** чарт notify
**When** гейт рендера сравнивает перечень источников notify с множеством `{модуль ∈ таблица подключаемых | флаг включён}` по каждой цепочке; и по отдельности инъекции: запись перечня значением установки (`notify.sources`); ключ `notify.sourceLimits` не из таблицы подключаемых; источник выведенного перечня без своей записи `notify.sourceLimits`
**Then** на дереве множества равны, у каждого источника перечня есть запись `sourceLimits`; гейт печатает число цепочек и записей
**And** первая инъекция — красный «перечень источников задан вручную» с координатой; вторая — отказ рендера с именем ключа; третья — отказ рендера с именем модуля

**ID:** NTF1-N04 — **все источники выключены — notify и секрет не рендерятся** (близнец — хотя бы один включён)

**Given** цепочка с глобальным `false` и без переопределений
**When** рендер
**Then** объектов notify 0; ссылок на секрет почты от notify 0
**And** при включённой `notify-probe` — notify и ссылка на секрет есть

**ID:** NTF1-N05 — **выключено: `SendX` класса `notice` строк и событий не пишет** (близнец — включено, B01)

**Given** фикстурный источник с флагом `false`; глагол ставит `probe-hello`
**When** глагол коммитится
**Then** `SendProbeHello` вернул `nil`; строк в ленте 0; событий вида `notification_feed` 0; ресурсная мутация глагола закоммичена
**And** с флагом `true` — исход B01

**ID:** NTF1-N06 — **выключено: письмо `security` — явный отказ, одинаковый для любого адреса** (близнец — включено)

**Given** фикстурный источник пространства `kaname` с флагом `false`; фикстурный глагол «запросить код» по адресу; адрес `a` известен источнику, адрес `b` — нет
**When** глагол вызывается для `a` и для `b`
**Then** оба — `FAILED_PRECONDITION`, `email delivery is not configured in this installation`, `ErrorInfo{reason: NOTIFICATION_DELIVERY_NOT_CONFIGURED}`; ответы побайтово равны; строк в ленте 0
**And** гейт дерева: глагол спрашивает флаг до чтения адреса (порядок вызовов в пробе: флаг — первым)
**And** с флагом `true` глагол для `a` ставит строку, для `b` — отвечает как для `a` без строки

**ID:** NTF1-N07 — **выключено: сервера ленты и вида нет, схема та же; исход `Subscribe` выбран по наличию других видов** (близнец каждого случая — тот же источник с флагом `true`)

**Given** два фикстурных источника corelib, различающиеся только набором видов: (а) `probe` — ключи `notification` → `notification_feed` и `item` → `probe_item`; (б) `probe-solo` — только ключ `notification` → `notification_feed` (форма `notify-probe`); у обоих флаг `false`
**When** каждый стартует; проба зовёт `Claim(max=10, classes={notice})` и `Subscribe` с `kinds: ["notification_feed"]`; сравниваются схемы баз при `false` и `true`
**Then** оба стартуют; у обоих `Claim` — `UNIMPLEMENTED`; набор сервисов сервера (`GetServiceInfo`) не содержит `corelib.notify.InternalNotificationFeedService`; таблица ленты существует, схемы побайтово равны
**And** (а) `Subscribe` — `INVALID_ARGUMENT`, текст `kinds: "notification_feed" is not a kind of this owner; known kinds: probe_item`; набор сервисов сервера содержит `corelib.subscription.InternalSubscriptionService`
**And** (б) журнал подписки не собран, сервер подписки не объявлен и не смонтирован: набор сервисов сервера (`GetServiceInfo`) не содержит `corelib.subscription.InternalSubscriptionService`; `Subscribe` — `UNIMPLEMENTED`
**And** близнец: тот же источник с флагом `true` — `Claim` обслуживается, `Subscribe` с `kinds: ["notification_feed"]` открыт; набор сервисов сервера содержит `corelib.notify.InternalNotificationFeedService` и `corelib.subscription.InternalSubscriptionService`; у (а) словарь видов — `notification_feed, probe_item`

**ID:** NTF1-N08 — **переменная флага не задана — служба-источник не стартует** (близнец — задана)

**Given** `notify-probe` без `KACHO_NOTIFYPROBE_NOTIFICATIONS_ENABLED`
**When** процесс стартует
**Then** отказ старта с именем переменной
**And** со значением `true` или `false` — стартует

**ID:** NTF1-N09 — **метрика состояния флага**

**Given** `notify-probe` с `true`, фикстурный источник с `false`
**When** снимаются метрики источников и notify
**Then** `kacho_notifications_enabled{module="notify-probe"} = 1`, у фикстурного `= 0`; `notify_source_enabled{source="notify-probe"} = 1`

### I. Поставка — раздел «notify» (S5)

**ID:** NTF1-I01 — **секрет почты среди служб kacho — только у notify**

**Given** рендер по каждой цепочке `deploy/stacks.txt`
**When** перепись объектов, ссылающихся на секрет почты
**Then** среди объектов служб kacho — ровно notify (там, где он рендерится), у модулей kacho и `notify-probe` — 0; ссылки kaname и поставщика личности напечатаны числом отдельно (их снимает NTF-2); перепись печатает число отрендеренных объектов

**ID:** NTF1-I02 — **ссылка модуля kacho на секрет почты — красный** (близнец I01)

**Given** инъекция ссылки на секрет почты в шаблон модуля `vpc`
**When** перепись I01
**Then** красный с именем объекта

**ID:** NTF1-I03 — **стенд: приёмник с TLS, письмо читается пробой**

**Given** цепочка `dev-prod` с `mailpit.enabled` и сертификатом приёмника из УЦ стенда
**When** notify отправляет письмо `probe-hello`
**Then** сессия шифрована, сертификат проверен; проба читает письмо у приёмника и извлекает кнопку

**ID:** NTF1-I04 — **стендовые объекты в цепочке `prod` — красный** (близнец — стендовые цепочки)

**Given** инъекция в `values.prod.yaml` одного из: `mailpit.enabled: true`; `notifyProbe.enabled: true`; `notify.standProbeNamespace`
**When** гейт стендовых объектов (`deploy/mail_receiver_core_test.go`, расширенный)
**Then** красный с именем профиля и объекта
**And** без инъекции зелёный и печатает перечень цепочек, где объекты подняты

**ID:** NTF1-I05 — **notify: реплики ≥ 2 и PDB в каждой цепочке, где он рендерится** (близнец — инъекция одной реплики)

**Given** рендер по каждой цепочке
**When** гейт доступности notify
**Then** у Deployment notify `replicas ≥ 2`, есть PDB с `minAvailable ≥ 1`; перепись печатает число цепочек
**And** инъекция `replicas: 1` — красный с именем цепочки

**ID:** NTF1-I06 — **чарт notify ставится отдельно, рядом с самостоятельной kaname**

**Given** чарт `deploy/helm/notify/` с собственными значениями (флаг, перечень подключаемых, декларации `spiffe`, секрет)
**When** `helm template` чарта без зонтика и `helm install` на кластере рядом с самостоятельной kaname
**Then** рендер проходит без обращения к значениям зонтика; rollout notify готов; самоотчёт посадки оценён

### J. Сертификаты служб — раздел «NS» (S4)

**ID:** NTF1-J01 — **сертификат с идентичностью чужой учётки не выпускается** (близнец J02)

**Given** кластер с политикой выпуска; учётка `X` в пространстве имён `A`
**When** от имени `X` подаётся запрос сертификата с SAN notify
**Then** запрос не одобрен, сертификат не выпущен; событие отказа наблюдаемо

**ID:** NTF1-J02 — **свой SAN выпускается**

**Given** условия J01
**When** от имени `X` подаётся запрос с SAN `ns/A/sa/X`
**Then** сертификат выпущен

**ID:** NTF1-J03 — **SAN сверяется целиком сквозь звено** (близнец — свой SAN в той же пробе)

**Given** тестовый УЦ пробы; `notify.spiffe = {T, N, kacho-notify}`; таблица Р2 kaname построена из неё; модель посеяна как в F01
**And** сертификат A — `spiffe://T/ns/N/sa/kacho-notify`; сертификат B — `spiffe://T/ns/X/sa/kacho-notify`
**When** каждый вызывает `ResolveSend(probe, probe-hello, сейчас)` у kaname
**Then** B — `PERMISSION_DENIED`; A — `ALLOW`

**ID:** NTF1-J04 — **боевое включение notify без политики выпуска — красный** (близнец — политика есть)

**Given** боевая посадка с notify без политики выпуска
**When** `make -C deploy assert-production-posture`
**Then** красный «notify требует политики выпуска сертификатов служб»; с политикой — зелёный

**ID:** NTF1-J05 — **SAN у всех читателей — из одной декларации** (близнец — согласный рендер)

**Given** рендер зонтика
**When** гейт сравнивает SAN в сертификате notify, в таблицах Р2 kaname и `notify-probe`, SAN `notify-probe` в перечне источников и SAN kaname в перечне источников
**Then** все — литералы `notify.spiffe`, `notifyProbe.spiffe`, `kaname.spiffe`; гейт зелёный и печатает число читателей
**And** правка одного читателя в обход декларации — красный с его именем

### K. Процедуры — раздел «notify» (S5)

**ID:** NTF1-K01 — **«добавить нотификацию» — 4 шага**

**Given** `notify-probe`, уже подключённая
**When** ровно шаги: (1) `notifications/probe-bye/` с `notification.yaml` и `body.ru.yaml`; (2) `make notifications`; (3) вызов `SendProbeBye` в транзакции use-case; (4) `make -C services/notify bundle` — всё одним PR kacho
**Then** все гейты цепочки зелёные, эталон `.eml` создан шагом 4, письмо доставлено на стенде
**And** выпуска corelib и строк манифеста прав не потребовалось

**ID:** NTF1-K02 — **пропуск шага «добавить» назван своим красным** (близнец K01)

**Given** условия K01 с пропуском одного шага
**When** исполняется цепочка
**Then** пропуск (2) — красный `notifygen -check` (D02); (3) — генератор сообщает «функция `SendProbeBye` без вызова»; (4) — красный гейт сборки (G17)
**And** ни один пропуск не проходит молча

**ID:** NTF1-K03 — **«подключить службу» — 7 шагов, каждый пропуск назван**

**Given** служба kacho без ленты
**When** выполняются: (1) ключ ленты и его ручка; (2) `notifygen init`; (3) подъём сервера ленты и ключ `notification` → `notification_feed` в `Mapping.Kinds` журнала подписки; (4) звено Р2: перечень `{Subscribe, Claim, Ack}`, таблица из `notify.spiffe`; (5) строки каталога прав для `Claim`/`Ack`; (6) строка `notifications: {namespace: <модуль>, readers: [notify]}` в манифесте; (7) строка таблицы подключаемых источников в чарте и флаг модуля
**Then** письмо фикстурного шаблона доставлено
**And** пропуск (1) — отказ старта (B05); (2) — отказ старта сервера ленты «таблицы нет»; (3) — `Claim` notify к источнику — `UNIMPLEMENTED` и тревога возраста; у службы с другими видами `Subscribe` notify с `kinds: ["notification_feed"]` — `INVALID_ARGUMENT` полным текстом corelib (как NTF1-N07 (а)); (4) — `Claim` notify `PERMISSION_DENIED` (C06) и тревога возраста; (5) — отказ старта с именем метода (NTF1-M09 (в): метод перечня Р2 вне каталога прав); (6) — `NOT_YET_GRANTED` и `grant_skew` (F04); (7) — нет в перечне notify (N03), тревога возраста

### L. Сквозные: стенд (L01, L02) и integration с управляемыми часами (L03–L05) — раздел «notify» (S5)

**ID:** NTF1-L01 — **письмо пробы доходит по всей цепочке**

**Given** стенд `dev-prod` после S5: kaname, notify (2 реплики), `notify-probe`, приёмник
**When** проба вызывает `InternalNotifyProbeService/Send` на адрес приёмника
**Then** у приёмника письмо `probe-hello`; кнопка ведёт на origin установки
**And** метрики notify: событие подписки получено, `ResolveSend` = `ALLOW`, исход `SENT`

**ID:** NTF1-L02 — **отзыв на стенде останавливает письма** (близнец L01)

**Given** условия L01; администратор кластера вызвал `Revoke(notify-probe)`, Operation `done`
**When** проба вызывает `Send`
**Then** у приёмника нового письма нет; исход строки `DENIED(revoked)`
**And** после `Restore(notify-probe)` и полосы отсечки следующий `Send` доходит

**ID:** NTF1-L05 — **положительный контроль integration-стенда**

**Given** integration-стенд kacho с управляемыми часами: фикстурный источник `kaname` (шаблон `recovery` класса `security`, `ttl = 5m`, лимит на адрес L за окно `ttl`), notify, kaname-решатель в процессе, тестовый узел с TLS
**When** фикстурный глагол ставит код на адрес
**Then** ответ глагола обычный; на узле одна сессия; строка `SENT`; счётчик окна = 1
**And** ответ записан эталоном для L03, L04 в том же прогоне

**ID:** NTF1-L03 — **notify лежит дольше срока: ответ прежний, лимит возвращён, тревога была** (близнец L05)

**Given** условия L05, но notify остановлен
**When** глагол ставит код; часы идут 6 мин; notify поднимается; повторный вызов
**Then** первый ответ побайтово равен L05; строка `EXPIRED(platform_unavailable)`; счётчик вернулся
**And** тревога возраста сработала на 2 мин 30 с
**And** повторный вызов поставлен и отправлен

**ID:** NTF1-L04 — **простой не открывает почтовой бомбы** (близнец L05)

**Given** условия L05, но notify остановлен
**When** за простой 3×`ttl` сделано 3L вызовов; notify поднимается
**Then** SMTP-сессий на адрес после подъёма ≤ L
**And** вызов после подъёма поставлен

---

## §6.1 Сценарий → производитель

| ID | что производит «Тогда» | координата в дереве (новая, если не сказано иное) | чем измерено |
|---|---|---|---|
| A01–A07 | валидатор `notify/spec` | corelib `notify/spec/spec_test.go`, `notify/spec/testdata/` | `go test ./notify/spec/...` |
| A08 | гейт замороженного корпуса | corelib `notify/spec/corpus_test.go` | `go test`, инъекция |
| A09 | гейт единственности валидатора (узел — функция, читающая файл формата шаблона; вызов `text/template` узлом не считается) | kacho `internal/repohygiene/notifyspecsingular*_test.go` | `go test ./internal/repohygiene/...`, инъекция |
| B01–B18, B20–B24 | `feed.Put`, сервер ленты, уборщик, схема, метрики | corelib `notify/feed/*_integration_test.go` (testcontainers, управляемые часы); для B20 (гейт) — kacho `outboxobservedgate_test.go` (существующий, три входа; расширяется четвёртым — «подъём сервера ленты в корне», засчитываемым и за движущего для переписи колонок доставки) | `go test -tags integration ./notify/feed/...` |
| B19 | гейт прямой вставки | corelib `notify/feed` гейт дерева, вызываемый из CI kacho | `go test`, инъекция |
| C01 | гейт формы подписки | kacho `TestSubscriptionFormIsDeclaredOnce` (существующий) | `go test ./internal/repohygiene/...` |
| C02 | гейт внешней изоляции | kacho `deploy/scripts/assert-ban6-external-isolation.py` (существующий, расширяется строкой носителя `notify` в `INTERNAL_ENDPOINTS`); регистрация сервера ленты — в прод-файле корня `notify-probe`, иначе перепись `e2e-ban6-domains.py` домена не видит | прогон на стенде |
| C03–C06 | авторизация сервера ленты через `reader` и звено Р2 | corelib `notify/feed/authz_integration_test.go` | `go test -tags integration` |
| C07 | обход аннотаций по дереву | kacho `TestCatalogMatchesTheAnnotationsItWasGeneratedFrom` (существующий; перечень `catalogProtoPackages` получает `corelib.notify`); способность падать — `TestAnnotationLaneInjection_UnannotatedMethodIsAFinding` (существующий, подставной вход) | `go test ./internal/repohygiene/...` |
| D01–D04, D06 | генератор (D04: правка применённого файла — `notifygen -check`) | corelib `cmd/notifygen/*_test.go`; D04 номер нового файла — kacho `TestNewMigrationOutranksEveryAppliedOne` (существующий) | `go test ./cmd/notifygen/...`; `go test ./internal/repohygiene/...` |
| D05 | перепись зависимостей рантайма | kacho `services/notify/runtimedeps_test.go` | `go test`, инъекция |
| E01–E03 | подписчик notify + сервер подписки фикстурного источника (E02 — фикстурная проверка прав с посеянным кортежем) | kacho `services/notify/internal/…/subscribe_integration_test.go` | `go test -tags integration ./services/notify/...` |
| E04, G01, G06, G15 | стражи старта и самоотчёт notify | kacho `services/notify/internal/config/*_test.go`; corelib `servicecontract` (элемент `NoServedServices`); `deploy/scripts/assert-production-posture.sh` | `go test`; `make -C deploy assert-production-posture` |
| M01, M03–M05, M09 | звено Р2, порядок отказов `Subscribe`, стражи | corelib `grpcsrv/service_subject_test.go`, `subscription/server_test.go` (существующий, новые случаи) | `go test ./grpcsrv/... ./subscription/...` |
| M02 | отказ `authz.Interceptor` без субъекта | corelib `authz/interceptor_service_subject_test.go` | `go test ./authz/...` |
| M06 | звено с `OperationService.Get` в перечне; носитель сертификата не виден владельцу операций | corelib `operations/service_subject_not_owner_test.go` | `go test ./operations/...` |
| M07 | звено на слушателях kaname; корпус ответов до Р2 | kaname `internal/authzguard/service_subject_corpus_integration_test.go` | `go test -tags integration ./internal/authzguard/...` (kaname) |
| M08 | извлекатель `authz.Interceptor` на обоих слушателях | corelib `authz/interceptor_service_subject_test.go`; kacho `services/notify/cmd/notify-probe/…/listeners_integration_test.go`; гейт одной функции — kacho `internal/repohygiene/servicesubjectsingular_test.go` | `go test`; `go test -tags integration` |
| M10 | отказ тенантских поверхностей, писатель кортежей `service:` | kaname `internal/apps/kaname/api/access_binding/*_test.go`; `TestProxyTupleRefusalMapsToPermissionDenied` (существующий); corelib `authz/proxytuple/policy.go`; kacho `proxyforbiddentypes_test.go` (существующий); kaname гейт `internal/check/servicesubjectwriter_test.go` | `go test` в kaname и kacho |
| F01, F04–F11, F13–F20 | модель, выдача, `ResolveSend`, `Revoke`/`Restore`, посев, полоса | kaname `internal/…/notificationgrant/*_integration_test.go` (testcontainers; F18 — горутины); модель — `tools/modelcanoncheck` (существующий) | `go test -tags integration ./...` (kaname) |
| F12 (а), (б) | место Д-3 `verdictForRelation` через обработчик `InternalIAMService/Check` | kaname `internal/apps/kaname/api/internal_iam/supergate_exempt_test.go` (вызов обработчика; дверь — настоящая `AuthorizeService` на посеве F01) | `go test ./internal/apps/kaname/api/internal_iam/...` (kaname) |
| F12 (в)–(е) | места Д-1, Д-2, Д-4, Д-5 через обработчики публичного `AuthorizeService` (`Check`, `BatchCheck`) | kaname `internal/apps/kaname/api/authorize/supergate_exempt_test.go` | `go test ./internal/apps/kaname/api/authorize/...` (kaname) |
| F12 (ж) | места Д-6 `checkAdapter.Check`, Д-7 `AllowsVerb` | kaname `internal/authzguard/supergate_exempt_test.go` | `go test ./internal/authzguard/...` (kaname) |
| F12 (гейт) | перепись мест семейства надзора разбором по идентичности против ведомости классов §1.11; предикат перечня в каждом месте «обобщённой двери» | kaname `internal/check/supergateexemptsites_test.go` + ведомость классов в `internal/check/testdata/` | `go test ./internal/check/...` (kaname), инъекция в обе стороны |
| F22 (б) | `ResolveSend` пересланному администратору облака | kaname `internal/…/notificationgrant/forwarded_admin_integration_test.go` | `go test -tags integration ./...` (kaname) |
| F22 (а), (в) | сервер ленты и сужение подписки фикстурного источника против двери kaname | kacho `services/notify/internal/…/forwarded_admin_integration_test.go` (kaname в процессе пробы на testcontainers) | `go test -tags integration ./services/notify/...` |
| F02, F03, F21 | валидатор и применитель манифестов | kaname `tools/modulemanifestcheck`, `internal/servicemanifest/seed_form_test.go` (существующий, новые случаи) | `go test ./tools/modulemanifestcheck/... ./internal/servicemanifest/...` |
| F01 (доставка), F04–F07, F11, G02, G07–G14, G20–G22 | конвейер notify с тестовым узлом TLS | kacho `services/notify/internal/…/deliver_integration_test.go` | `go test -tags integration ./services/notify/...` |
| G03–G05, G18 | рендер и эталоны | kacho `services/notify/layout/*_test.go`, `services/notify/testdata/golden/` | `go test ./services/notify/...` |
| G12 | правило тревоги | kacho чарт notify + `deploy/tests/…/notify_alert_rules_test.go` | прогон проб правил с синтетическим рядом |
| G16 | реплики, падение реплики | kacho `services/notify/internal/…/replica_integration_test.go` | `go test -tags integration` |
| G17, G20 (гейт) | гейт сборки | kacho `services/notify/bundle_test.go` | `make -C services/notify bundle-check` |
| G19 | перепись слушателей, поверхностей и ручек notify | kacho `services/notify/servesurface_test.go` (вызовы из пакетов kacho под `services/notify/` в `grpc.NewServer`, точки входа фундамента, выведенные замыканием вызывающих `grpc.NewServer` в corelib, и `Register…Server`: 0; объём осмотренного, перечень точек входа, инъекция и близнец); `services/notify/internal/config/knobcensus_test.go`; перепись портов пода — `deploy/tests/helm/notify-listeners-test.sh` | `go test ./services/notify/...`; прогон скрипта по рендеру |
| H01–H10 | лимиты notify, база `kacho_notify` | kacho `services/notify/internal/…/limits_integration_test.go` (2 реплики в процессе для H03); `services/notify/internal/config/*_test.go` (H07, H08) | `go test -tags integration ./services/notify/...` |
| N01–N04, I01, I02, I04, I05, J05 | гейты рендера по `deploy/stacks.txt` (N02 — на фикстурной копии чарта с таблицей из двух источников) | kacho `deploy/notifications_flag_test.go`, `deploy/notify_source_list_derived_test.go`, `deploy/identity_mail_lane_feeds_both_senders_test.go` (существующий, переписывается под I01), `deploy/mail_receiver_core_test.go` (существующий, расширяется), `deploy/tests/helm/notify-availability-test.sh`, `deploy/tests/helm/service-identity-declaration-test.sh` | `go test ./deploy/...`; прогон по `deploy/stacks.txt` |
| I03, L01, L02 | стенд с приёмником и `notify-probe` | kacho newman `tests/newman/notify-delivery/` + строка ведомости производителя | прогон newman на стенде `dev-prod` |
| N05–N07, N09 | флаг в `feed`; N07 — сборка журнала и объявление сервера подписки по наличию видов (источники `probe`, `probe-solo`), «не смонтирован» — набором `GetServiceInfo` сервера пробы | corelib `notify/feed/flag_integration_test.go`; источник-фикстура | `go test -tags integration ./notify/feed/...` |
| N08 | страж старта `notify-probe` | kacho `services/notify/cmd/notify-probe/config_test.go` | `go test` |
| I06 | чарт notify отдельно | kacho `deploy/tests/helm/notify-standalone-test.sh`; `helm install` на кластере | прогон скрипта; `.github/workflows/production-posture.yml` |
| J01, J02, J04 | политика выпуска | kacho политика в чарте + `deploy/tests/cluster/cert-issuance-policy-test.sh`; `assert-production-posture.sh` | прогон на поднятом кластере |
| J03 | SAN сквозь звено kaname | kaname `internal/…/notificationgrant/service_subject_san_integration_test.go` | `go test -tags integration ./...` (kaname) |
| K01–K03 | репетиция процедур; исход каждого пропуска K03 — наблюдаемый ответ или отказ старта в самой репетиции (гейт монтирования и гейт аннотаций исходом пропуска не названы: пакетом `corelib.notify` пропустившая служба не владеет, а обход аннотаций судит контракт, не службу) | kacho `services/notify/procedure_rehearsal_test.go` | `go test` |
| L03–L05 | конвейер с управляемыми часами | kacho `services/notify/internal/…/outage_integration_test.go` | `go test -tags integration ./services/notify/...` |

**Сценариев без производителя — ноль.** Каждый ID §6 входит хотя бы в одну строку таблицы
(F01, F22, G20 — в двух, F12 — в четырёх, по своим «Тогда» и входам двери).

## §6.2 Близнецы: один изменённый факт на каждое отрицание

| отрицательный | положительный близнец | единственное различие |
|---|---|---|
| A02 | A01 | вид одного блока |
| A03 | A01 | форма значения кнопки |
| A04 | A01 | наличие `limits` |
| A05 | A01 | объявлен ли атрибут |
| A06 | A01 | локаль |
| A07 | A01 | блок, несущий секрет |
| A08 (сужение) | A08 (расширение) | направление правки |
| A09 (инъекция) | A09 (дерево) | вторая реализация |
| B02 | B01 | исход транзакции |
| B04 | B03 | строка шифротекста |
| B05 (без ключа) | B05 (с ключом) | задан ли ключ |
| B07 | B06 | прежний ключ в кольце |
| B09 | B08 | число горутин |
| B11 | B10 | `expires_at` в прошлом |
| B13 | B12 | токен аренды |
| B14 | B12 | значение `outcome` |
| B16 | B15 | причина последнего `DEFER` |
| B17 | B17 (со стиранием) | стёрт ли секрет |
| B19 (инъекция) | B19 (дерево) | путь вставки |
| B21 (0 и 501) | B21 (1 и 500) | значение `max` |
| B22 | B12 | форма `id` |
| B23 | B12 | есть ли строка |
| B24 (пусто) | B24 (`{security}`) | набор классов |
| C02 | C02 (внутренний слушатель) | слушатель |
| C04 | C03 | субъект без `reader` |
| C05 | C03 | кортеж `reader` notify |
| C06 | C03 | SAN в таблице Р2 |
| D02 | D01 | перегенерация |
| D04 | D03 | версия схемы |
| D05 (инъекция) | D05 (дерево) | импорт `notify/spec` |
| E02 | E02 (кортеж посеян) | `reader` у `probe-b` в фикстурной проверке прав |
| E03 | E01 | доступность потока |
| E04 (без ручки) | E04 (с ручкой) | ручка таймера |
| M02 | M02 (метод в перечне) | метод в перечне |
| M03 | M01 | равенство SAN ключу |
| M04 | M04 (`verified = true`) | проверен ли сертификат |
| M05 (пир вне круга) | M05 (край в круге) | пересылающий пир |
| M06 (сертификат notify, метод в перечне) | M06 (принципал от края) | носитель личности |
| M07 (корпус) | M07 (`ResolveSend`) | метод в перечне |
| M08 (пустое звено) | M08 (звено задано) | перечень и таблица |
| M09 (а)–(е) | M09 (согласное) | одно нарушение звена |
| M10 (а) `service` | M10 (а) `user` | тип субъекта |
| M10 (б) запрещённый тип | M10 (б) разрешённый тип | тип объекта |
| F02 | F01 | `namespace` в строке |
| F03 | F01 | состав `readers` |
| F04 | F01 | есть ли строка манифеста |
| F05 | F01 | вызван ли `Revoke` |
| F06 | F01 | отзыв и восстановление до постановки |
| F07 | F01 (другой шаблон) | шаблон строки |
| F08 (после `Revoke`) | F08 (без `Revoke`) | предшествующий `Revoke` |
| F09 | F01 | субъект / пространство вызова |
| F10 | F05 | роль вызывающего |
| F11 | F01 | доступность kaname |
| F12 (а), (б), (в, `probe`), (е) — администратор, типы Р5 | тот же вход и место: `service:probe` в (а), `service:notify` в (б), (в), (е) | субъект вопроса |
| F12 (а)–(ж) — администратор, типы Р5 | тот же вход и место, объект `iam_user:<id U2>` с `token_issuer` | объект вопроса: тип вне перечня (с отношением, которое этот тип объявляет и которое администратору даёт только надзор) |
| F12 (гейт, инъекция) | F12 (гейт, дерево) | место без предиката / вне ведомости / вторая декларация |
| F22 (а)–(в), пересланный администратор | F22 (а)–(в), `service:notify` | субъект вызова |
| F13 (по полю) | F01 / F05 / F06 | одно поле |
| F14 | F01 | есть ли выдача |
| F15 | F05 | есть ли выдача |
| F16 | F05 | отозвано ли |
| F17 | F06 | отозвано ли |
| F18 (параллельно) | F18 (последовательно) | параллельность |
| F19 | F06 | ось отзыва — шаблон |
| F20 (в полосе) | F20 (за полосой) | `enqueued_at` относительно полосы |
| F21 (б) | F21 (а) | ключ `namespace` |
| G01 (неполный) | G01 (полный) | полнота перечня |
| G02 | G02 (шаблон в своём пространстве) | есть ли шаблон в пространстве `probe` |
| G04 | G03 | значение атрибута |
| G05 | G03 | CR/LF |
| G06 (без origin) | G06 (с origin) | ручка origin |
| G07 | G07 (узел с TLS) | TLS у узла |
| G08 | G07 (узел с TLS) | доверие сертификату |
| G09 | G09 (после смены) | ответ на `AUTH` |
| G10 | G10 (остальные адресаты) | ответ на `RCPT` |
| G11 | G11 (узел доступен) | доступность узла |
| G12 (2:30) | G12 (2:29) | возраст строки |
| G13 (значения) | G13 (id строки) | что ищется |
| G15 (ось нарушена) | G15 (исправна) | одна ось |
| G17 | G17 (после `bundle`) | выполнен ли `bundle` |
| G20 | G20 (`kaname`) | пространство шаблона |
| G21 | G21 (`kaname`) | пространство строки |
| G22 (чужое исключение / SAN) | G22 (`probe` через `ResolveSend`) | запись исключения |
| H01 | H01 (S−1) | число доставленных |
| H02 | H02 (N−1) | число доставленных |
| H03 (параллельно) | H03 (последовательно) | параллельность реплик |
| H04 | H04 (5 строк) | темп |
| H05 | H05 (ниже потолка) | потолок достигнут |
| H06 | H06 (без паузы) | пауза |
| H07 (33) | H07 (34) | величина сетки |
| H08 | H08 (в границах) | значение ручки |
| H10 (N поперёк источников) | H10 (N−1) | число доставленных из `kaname` |
| N01 | N01 (задан) | глобальный флаг |
| N02 (`false`, два источника) | N02 (`true`) | переопределение модуля |
| N03 (инъекция ×3) | N03 (дерево) | ручная запись перечня / ключ `sourceLimits` / отсутствие записи `sourceLimits` |
| N04 (всё выключено) | N04 (проба включена) | флаги |
| N05 | B01 | флаг |
| N06 (`false`) | N06 (`true`) | флаг |
| N07 (а) `false` | N07 (а) `true` | флаг |
| N07 (б) `false` | N07 (б) `true` | флаг |
| N08 | N08 (задана) | переменная |
| I02 | I01 | ссылка модуля на секрет |
| I04 | I04 (стендовые цепочки) | профиль |
| I05 (инъекция) | I05 (дерево) | число реплик |
| J01 | J02 | SAN в запросе |
| J03 (B) | J03 (A) | пространство имён в SAN |
| J04 | J04 (политика есть) | наличие политики |
| J05 (инъекция) | J05 (согласный) | обход декларации |
| K02 | K01 | пропущенный шаг |
| L02 | L01 | вызван ли `Revoke` |
| L03 | L05 | доступность notify |
| L04 | L05 | длительность простоя и число вызовов |

---

## §7 Пробелы критика полноты — как закрыт каждый

| пробел | суть | закрыт |
|---|---|---|
| В1 | кто выпускает сертификат с нужным SAN | Р12; NTF1-J01…J05 |
| В2 | ротация кредов отравляет очередь | Р11; NTF1-G09 |
| В3 | 5xx получателя смешан с неисправностью настройки | Р11; NTF1-G10, G14 |
| В4 | ретранслятор лежит часами | Р11; NTF1-G11 |
| В5 | неверный порядок раскатки теряет письма | Р5 (`NOT_YET_GRANTED` ≠ `REVOKED`), Р11 (`template_skew`); NTF1-F04, G02 |
| В6 | общий страж старта для службы без сервисов | NTF1-G15 (`NoServedServices`) |
| В7 | снятие шаблона и службы | Р5 (отзыв шаблона, отсечка); NTF1-F07, F16, F17, F19 |
| В8 | стенд без настоящей почты | Р16; NTF1-I03, I04 |
| В10 | секрет в WAL и копиях | Р13; NTF1-B03 |
| В11 | дедупликация по `Message-ID` | Р14; NTF1-G16 |
| В12 | потолки в памяти × реплики | Р10 (сетка и потолок — CAS в базе); NTF1-H03 |
| В16 | подписчик-служба без субъекта | Р2; NTF1-M01…M09 |
| В17 | часы источника против часов kaname | Р5 (полоса); NTF1-F20 |
| В18 | нагрузка без шлюза | Р9; NTF1-N01…N09 |
| В19 | взломанный модуль шлёт «сбросьте пароль» или на произвольный адрес | Р6; NTF1-G20, G21 |
| В9, В13, В15 | приглашения, аудит инициатора, пины kaname | NTF-2 (§4) |

---

## §8 Definition of Done

**Общее:**

1. Первой в каждой стадии ложится **красная** проба её группы; краснота названа выводом прогона и
   ревизией.
2. Имя каждой пробы начинается с ID сценария (`NTF1-B09 · …`). Перепись: множество ID с имён проб
   по трём деревьям против множества ID §6; разность печатается поимённо в обе стороны и пуста.
3. Каждый гейт печатает объём осмотренного, падает на пустом обходе и доказан инъекцией в обе
   стороны.
4. Ни одна проба не пропущена; отложенного в дереве нет (ban #11).
5. Каждая integration-группа даёт тот же вердикт трижды подряд.

**S0 — контракт (#2915):**

6. `proto/corelib/notify/` в kacho; `buf lint`, `buf breaking` зелёные; стабы в corelib; путь
   вписан в `PRO-Robotech/corelib#9`. Зелёные: NTF1-C01, NTF1-C07.

**S1 — corelib (#77):**

7. Зелёные исполненными пробами: NTF1-A01…A09, NTF1-B01…B24, NTF1-C03…C06, NTF1-D01…D06,
   NTF1-M01…M06, NTF1-M09, NTF1-N05…N07, NTF1-N09 (сторона corelib).
8. Тег corelib выпущен; kacho и kaname встают на него пином без `replace`.
9. `go list -deps ./notify/...` corelib без `net/smtp`, `mime/multipart`, `html/template`; имён
   потребителей в `notify/` нет.

**S2 — kaname (#484, часть NTF-1):**

10. Зелёные: NTF1-F01…F21, NTF1-F22 (б), NTF1-M07, NTF1-M10, NTF1-J03; гейт переписи мест надзора (F12)
    доказан инъекцией в обе стороны и печатает число мест по классам §1.11.
11. Модель несёт `service`, `notification_feed`, `notification_namespace`; `tools/modelcanoncheck`,
    kacho `modelrelationproducer_test.go` и `proxyforbiddentypes_test.go` на новом пине зелёные;
    перечень Р2 kaname = `{ResolveSend}`. Пины corelib (S1) и kaname (S2) поднимаются в kacho
    **одним изменением**: сторона А гейта `TestForbiddenProxyObjectTypesAgreeWithTheModel` называет
    находкой тип набора, которого нет в модели, и пин corelib с тремя новыми типами без пина kaname
    с ними же красит ствол.

**S3 — notify (#2915):**

12. Зелёные: NTF1-E01…E04, NTF1-G01…G22, NTF1-H01…H10, NTF1-F22 (а), (в), NTF1-D05, NTF1-M08.
13. `make -C services/notify bundle-check`, `golangci-lint` (цель `make lint`), `gosec` зелёные;
    миграции `kacho_notify` применяются в боевой посадке с `sslmode=require`.

**S4 — NS (#2916):**

14. Зелёные: NTF1-J01, NTF1-J02, NTF1-J04 на поднятом кластере; NTF1-J05 — гейт рендера.

**S5 — поставка (#2915):**

15. Зелёные: NTF1-C02, NTF1-N01…N04, NTF1-N08, NTF1-I01…I06, NTF1-K01…K03, NTF1-L01…L05.
16. Новая коллекция newman `tests/newman/notify-delivery/` внесена строкой в ведомость
    производителя.
17. `helm install` + rollout-ready в боевой посадке цепочки `dev-prod` с notify и `notify-probe`,
    а не только `helm template`.
18. Правки З4…З10 внесены задачей `kacho-workspace#881` не позже S5; З11 — в тексте задачи #2916.
19. Записки хранилища контекста: ресурсы `notification_feed`, `notification_namespace`,
    `<svc>_notification_outbox`; rpc `corelib.notify.InternalNotificationFeedService/{Claim,Ack}`,
    `kaname.cloud.iam.v1.InternalNotificationGrantService/{ResolveSend,Revoke,Restore}`; пакеты
    `corelib/notify/*`, `corelib/grpcsrv` (звено Р2); рёбра notify→источники, notify→kaname,
    notify→ретранслятор.

---

## §9 Правки по кругам

| круг | замечание | класс | что изменено |
|---|---|---|---|
| 1 | B1-1…B1-5 | CONSTRUCTIBILITY ×2, NEGATIVE, FORMAT, TWIN | см. редакцию 2 (отсечка только после `Restore`, идемпотентный посев, таблица отказов, коды H06/F08, близнецы в том же стенде) — перенесено в Р5, F04, F08, F13–F18, L05 |
| 2 | B2-1 источник привязки «SAN → субъект»; B2-2 `Restore(…, template)` | CONSTRUCTIBILITY, COVERAGE | одна декларация `<служба>.spiffe` (Р12); таблица звена (Р2 п.2); запись шаблона и F19 — сохранены |
| 3 | B3-1 у права `send` на ленту kaname нет субъекта (своей учётки у службы доступа нет) | CONSTRUCTIBILITY | Д2/Д4: субъект — служебный принципал `service:<имя>` (Р2), право — `sender` на `notification_namespace` (Р5); у kaname принципала нет, её пространство — записанное исключение Р3 (MRW-1 Р1 не замещается, §1.5); F21 и G22 — обе стороны исключения; перевод kaname на ленту — NTF-2 |
| 3 | B3-2 у выдачи `reader` нет формы и правила «кому можно» | NEGATIVE | форма `notifications: {namespace: <модуль>, readers: [notify]}` (Р5); валидатор принимает только `readers: [notify]`; NTF1-F03 (отрицание) с близнецом F01 в §6.1 и §6.2 |
| 3 | класс CONSTRUCTIBILITY в четвёртый раз: Given опирается на субъект, которого дерево не допускает | CONSTRUCTIBILITY | перепись всех субъектов Given по вопросу «существует ли субъект правила и кто его заводит»: `service:notify` — манифест notify; `service:<модуль>` — манифест модуля; `service:probe-b` в C04, E02, M05 — фикстурный манифест; субъекта kaname нет нигде (F21); учётка `kacho-notify` больше не субъект — только `saName` сертификата |
| 3 | важные | — | команда §1.1 без ошибочной оговорки `-c`; строки `serve.go` заменены именами функций (§1.6); `WithSANAllowlist` назван образцом перечня SAN (§1.6); посев ленты проб в E02 назван |
| 4 | гигиена посадки | — | снята фраза о незакоммиченном документе в строке редакции 1 (документ внесён коммитом `e34a4db5`); снято утверждение «пакет изменения не заводится» — пакет `docs/changes/issue-2915/` существует (§1.10) |
| 4 | новое разбиение эпика (Д13) и решения Д1–Д12 | — | группа H редакции 3 (перевод kaname) и группы I01/I06, G19 (пары пинов) — в NTF-2; новые группы M (звено), N (флаг), H (лимиты notify); проба-источник стенда (Р16); ID перенумерованы: соседние приёмки, ссылающиеся на NTF1-ID редакции 3, сверяются с этой редакцией |
| 4 | B4-1 надзор администратора облака в двери kaname решал исход F12, Claim, `ResolveSend` в обход модели | CONSTRUCTIBILITY | §1.11 — перепись путей решения двери (4 пути надзора, допуск, право спрашивать, `Breakglass`); Р5 — перечень типов без надзора, одна декларация, предикат на всех путях, право `ResolveSend` той же дверью; З5 и S2 называют правку кода; F12 — через `Check`/`BatchCheck`, с путями «вопроса нет» и близнецом по типу; новая пара F22 (Claim, `ResolveSend`, подписка) с близнецом `service:notify` — §6.1, §6.2, DoD |
| 4 | B4-2 письма `security` из двух источников в H01, H03 | CONSTRUCTIBILITY | H01 — один источник `kaname`; H03 — точность двумя репликами на одном источнике; `identityNamespaces` объявлен константой сборки, не ручкой (Р6); свойство «поперёк источников» — новый H10 на `notice` (`kaname` + `probe`) с близнецом N−1 |
| 4 | B4-3 E02 — вторая лента одной службы; N02 — пустой предмет на стенде | CONSTRUCTIBILITY | E02 — одна лента, близнец — кортеж `reader` у `probe-b` в фикстурной проверке прав; N02 — в гейт рендера на фикстурной копии чарта с таблицей из двух источников |
| 4 | B4-4 автоматическая пауза против Д11 | SCOPE | снята из Р10 и §4: пауза — только оператором и в NTF-1, и в NTF-4 |
| 4 | класс CONSTRUCTIBILITY пятый раз подряд — перепись по двум вопросам ревьюера | CONSTRUCTIBILITY | (1) «решает ли код kaname исход в обход модели»: перепись §1.11 — единственный разрешающий обход для типов Р5 — надзор, закрыт Р5; допуск только сужает; `Breakglass` запрещён посадкой. (2) «не запрещает ли Given собственное правило документа»: перепись всех Given, где строка доходит до отправки, по правилам Р6 (класс `security` — только `kaname`; форма `address` — только `kaname` и `standProbeNamespace`) и Р4/Р5 (одна лента на службу, `reader` — только notify): найдены и исправлены H01, H03 (два источника `security`), E02 (вторая лента), G02 (близнец отправлял из `probe-b`, у которого нет формы `address` — роли поменяны), H05/H06 (класс строк по лентам назван); средства §6 называют `standProbeNamespace = probe` в пробах notify |
| 4 | важные | — | M02 — текст и производитель `authz.Interceptor` (`permission denied`), близнец — метод в перечне; G19 и Р1 — один диагностический HTTP-слушатель, gRPC-слушателя нет; ручки на источник — словарь `notify.sourceLimits.<модуль>` (Р10, H04, H06, H08, N03 с двумя новыми инъекциями); M06 — перечень включает `OperationService.Get`, проверяется Р2 п.4; рассинхрон NTF-4 с этой редакцией — правка NTF-4, названа в возврате |
| 5 | B5-1 перепись путей надзора неполна: пропущен `verdictForRelation` (вход `InternalIAMService/Check`); `module/authz.go:26` — комментарий, а не вызов; `checkAdapter.Check` и `AllowsVerb` не названы; F12 (д) невыразим через `InternalIAMService/Check`; `BatchCheck` приписан не тому сервису | CONSTRUCTIBILITY | §1.11 переписан построчно: предикат прошлой редакции (29 строк) молчал о вызовах обёрток — новый предикат по всему семейству имён даёт 62 строки, контрольный `"system_admin"` — 11; каждая строка получила класс (обобщённая дверь 8 · закреплённый предмет 14 · определение 11 · план 7 · комментарий 22), сумма сверена с выводом; все семь мест обобщённой двери Д-1…Д-7 (включая `verdictForRelation`, `checkAdapter.Check`, `AllowsVerb`) внесены в перечень Р5, места с закреплённым предметом — с доводом и держателем; Р5, З5, S2 называют Д-1…Д-7; F12 разведён по входам: (а), (б) — `InternalIAMService/Check`, (в)–(е) — публичный `AuthorizeService` (`BatchCheck`, `Check` с действием), (ж) — модульная проба Д-6, Д-7; гейт F12 судит множество мест из переписи против ведомости классов, а не константу; §6.1 — четыре строки F12, `BatchCheck` — публичного `AuthorizeService` |
| 5 | B5-2 слово вида на проводе и пустой словарь видов | CONSTRUCTIBILITY | во всех When/Then вид провода — `notification_feed` (`kinds: ["notification_feed"]`, событие вида `notification_feed`); слово `notification` — только ключ `Mapping.Kinds` (Р4, Р9, Р16, B01, B02, K03); исход флага `false` выбран по наличию других видов (Р9): есть — `INVALID_ARGUMENT` полным текстом corelib, нет — журнал не собирается, сервер подписки не объявляется и не монтируется, служба стартует, `Subscribe` — `UNIMPLEMENTED`; N07 утверждает оба случая на двух фикстурных источниках (`probe` с видом `probe_item`, `probe-solo`), близнец каждого отличается только флагом |
| 5 | важные N5-1, N5-2 | — | Р2 п.5 и S1: `notification_feed`, `notification_namespace` внесены в `forbiddenObjectTypes` рядом с `service` (сторона Б гейта `TestForbiddenProxyObjectTypesAgreeWithTheModel`, M10 (б)); средство F22 (а), (в) — настоящая дверь kaname в процессе пробы — названо в самом F22 и отдельной строкой §6, строка фикстурной проверки прав оговаривает исключение |
| 5 | класс CONSTRUCTIBILITY шестой раз подряд — общий знаменатель «факт о дереве из прозы» | CONSTRUCTIBILITY | перепись фактов документа о коде по вопросу «из разобранного вывода или из прозы»: утверждения §1.11 — из вывода, построчно; слово вида — из `KindDictionary` corelib, а не из имени ключа; исход флага `false` — из проверки пустого `Mapping.Kinds` corelib; адресаты проверки прав F22 — из цепочки обработчиков; F12 (г) ведётся публичным `Check`, а не `InternalIAMService/Check`: ветка «вопроса нет» по `*` есть только у `check` (Д-1), а `CheckRelation` отдаёт `*` модели как обычный объект |
| 6 | B6-1 гейту монтирования приписан исход, которого он дать не может (Р9, N07 (б), K03 (3), G19) | PRODUCER | Р9 и N07 (б): «не смонтирован» наблюдается набором сервисов сервера (`GetServiceInfo`) в integration-пробе corelib, у (а) и близнеца `true` — тот же набор; K03 (3): исход пропуска — `Claim` `UNIMPLEMENTED` и тревога возраста в репетиции; G19: новая перепись импортного замыкания `cmd/notify` (0 `grpc.NewServer`/`Register…Server`, объём осмотренного, инъекция) вместо гейта монтирования |
| 6 | класс PRODUCER по всему документу: перепись каждого названного **существующего** держателя против его предмета (читано в kacho `1d42a6728bf`) | PRODUCER | найдено ещё пять: C07 — названная проба инъекционная и по дереву не ходит, обход дерева — `TestCatalogMatchesTheAnnotationsItWasGeneratedFrom` по перечню `catalogProtoPackages`, куда вносится `corelib.notify`; K03 (5) — обход аннотаций судит контракт, а не службу, исход пропуска — отказ старта M09 (в); D04 — гейт монотонности судит номер добавленного файла, а не правку применённого, исход правки — `notifygen -check`; C02 — скрипт внешней изоляции видит домен, только если регистрация стоит в прод-файле корня kacho и у носителя есть строка `INTERNAL_ENDPOINTS` — оба условия названы в C02 и §6.1; B20 — `outboxobservedgate` берёт предмет из `drainer.Config`, а ленту дренирует `Claim` — назван новый вход гейта; подтверждены без правки: C01 (`TestSubscriptionFormIsDeclaredOnce` обходит весь `proto`), M10 (б) (сторона Б `TestForbiddenProxyObjectTypesAgreeWithTheModel`), F21 (`TestMRW07_GroupWithItsGrantIsAccepted` — только «зелёный», исхода не несёт) |
| 6 | N6-1, N6-2 | — | S2 п.11: пины corelib и kaname поднимаются в kacho одним изменением (сторона А гейта запретительного набора); F22: строка средства — продолжение Given, а не отдельная строка перед When |
| 7 | B7-1 G19: перепись импортного замыкания `cmd/notify` покраснела бы на исправном notify — `servicecontract` (самоотчёт G15) импортирует `grpcsrv`, где `grpc.NewServer` и `RegisterHealthServer` | PRODUCER | выбран вариант (б) рецензента, уточнённый: предмет — вызовы из пакетов kacho под `services/notify/`; фундамент не входит, потому что импорт функции её не вызывает, а вызов из notify в точку входа фундамента судится; перечень точек входа выводится пробой замыканием вызывающих `grpc.NewServer` по corelib, а не пишется. Сверка: `git -C project/corelib grep -nE 'NewServer\(\|Register[A-Za-z]*Server\(' 34bc810 -- '*.go' ':!*_test.go'` — не-тестовый `grpc.NewServer` один (`grpcsrv/server.go`, в `grpcsrv.NewServer`); `git -C project/corelib grep -nE 'grpcsrv\.NewServer\b' 34bc810 -- '*.go' ':!*_test.go'` — вызывающий один (`servicehost/serve.go`, `serverPair`), `serverPair` зовёт только `servicehost.Serve`; вызывающих `servicehost.Serve` в не-тестовом corelib 0 — перечень на `34bc810`: `grpcsrv.NewServer`, `servicehost.Serve`; `servicehost/surface.go` `srv.Serve` — HTTP-сервер, в замыкание не входит |
| 7 | класс PRODUCER по всему документу: перепись каждого названного **нового** держателя, чей предикат судит уже существующее дерево (фундамент, чужой репозиторий, существующие миграции), против этого дерева (kacho `1d42a6728bf`, corelib `34bc810`, kaname `734f69fb4`) | PRODUCER | найдено ещё два: B20 — перепись колонок доставки существующего `outboxobservedgate` (`deliveryColumnMarks` = `sent_at`, `next_attempt_at`) объявила бы ленту находкой «двигать некому», если схема ленты несёт эти колонки: новый вход назван четвёртым и засчитывается за движущего (N7-1); A09 — узел «реализация проверки формата» по вызову `template.Parse` поймал бы `quota/refusal.go` corelib (`git -C project/corelib grep -lE '"(text\|html)/template"' 34bc810 -- '*.go' ':!*_test.go'` → 1 файл), узел назван по файлу формата (`git grep -l 'notification\.yaml' <ревизия> -- '*.go'` → 0 во всех трёх деревьях); подтверждены без правки: B19 (`git grep -il notification_outbox` → 0 во всех трёх), D05 (импортёров `corelib/notify/spec` 0 во всех трёх), M10 (писателей кортежей `service:` в не-тестовом kaname 0: `git -C project/kaname grep -nE '"service:\|`service:' 734f69fb4 -- '*.go' ':!*_test.go'` → пусто), F12 (гейт) — перепись §1.11 круга 5; M08, G17/G20, N01–N04 судят только новое дерево |
| 7 | N7-2 | TWIN | D04: положительный близнец отрицания «правка применённого файла» назван строкой — без правки `notifygen -check` зелёный |
