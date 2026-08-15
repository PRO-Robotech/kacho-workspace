---
title: "kacho-corelib/authz"
aliases:
  - corelib authz
  - authz interceptor
category: packages
repo: kacho-corelib
layer: corelib
tags:
  - packages
  - kacho-corelib
  - authz
  - cross-service
  - e3
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/authz — перехватчик проверки прав

**Каталог**: `pkg/authz/` · импорт `github.com/PRO-Robotech/kacho/pkg/authz`
**Прежде** (полирепо): `kacho-corelib/authz`.
**Импортируют** (`go list` на `96b2879a`, non-test): nlb 6 · vpc 2 · registry 2 ·
compute 2 · storage 1 · geo 1 · gateway 1 · собственный подпакет сверки каталога 1.
**iam в этом списке НЕТ**: у него собственная стража (`services/iam/internal/authzguard`),
а не общий перехватчик. Прежняя редакция называла iam потребителем, а nlb —
«будущим» (`TODO, KAC-108`); в дереве всё наоборот, и nlb — **самый крупный**
потребитель.

Перехватчик unary и stream поверх внешнего порта проверки, который каждый сервис
реализует своим адаптером к внутреннему RPC проверки прав в iam.

## Состав

| Файл | Назначение |
|---|---|
| `doc.go` | обзор конвейера решения |
| `types.go` | `RPCMap`, `RPCEntry`, `ObjectExtractor`, `StaticExtractor`, `Decision`, sentinel-ошибки, `FormatObject`, `FormatSubject` |
| `cache.go` | `Cache` — кэш **только положительных** вердиктов + `InvalidateBySubject`/`InvalidateAll`, потолок числа записей |
| `check_client.go` | порт `CheckClient` + `CheckClientFunc` |
| `subject_extract.go` | извлечение субъекта из личности вызывающего |
| `interceptor.go` | `Interceptor`, `NewInterceptor`, `Unary()`/`Stream()`, метрики, вытеснение неактивных субъектов |
| `rate_limiter.go` | ведро токенов на субъекта — против шторма отказов |
| `listen_invalidate.go` | слушатель на выделенном соединении (см. предупреждение ниже) |
| `hide_existence.go` | скрытие существования объекта при отказе |
| `revocation_policy.go` | **объявленная** политика окна отзыва |
| `catalogparity/` | сверка каталога прав между сторонами |

## Порты и типы (снято с дерева)

```go
type CheckClient interface{ Check(ctx, subjectID, relation, object string) (bool, error) }
type CheckClientFunc func(ctx, subjectID, relation, object string) (bool, error)
type ObjectExtractor func(req any) (objectType, objectID string, err error)
func StaticExtractor(objectType string, extractID func(req any) (string, error)) ObjectExtractor
type RPCMap map[string]RPCEntry
func (m RPCMap) Lookup(fullMethod string) (RPCEntry, bool)

type RPCEntry struct {
    Relation      string          // отношение, требуемое на объекте
    Extract       ObjectExtractor // (тип, id) объекта из запроса
    Public        bool            // явное освобождение от per-RPC проверки
    ScopeFiltered bool            // авторизация на уровне данных, а не одним вопросом
    Permission    string          // строка каталога прав; перехватчик её ПОКА не читает
}

var ErrUnmapped      = errors.New("authz: RPC not mapped in PermissionMap")
var ErrUnavailable   = errors.New("authz: check service unavailable")
var ErrNoPath        = errors.New("authz: no FGA path to resource")
var ErrPermissionDenied = errors.New("authz: permission denied")
var ErrHideExistence = errors.New("authz: hide existence (deny on existing object)")
```

Порта `CreatorTupleWriter` в дереве **нет** — прежняя редакция называла его и в
таблице файлов, и в блоке API; запись пережила свой предмет.

### `Public` и `ScopeFiltered` — разные вещи, и путать их опасно

- **`Public`** — «вообще вне арендаторской авторизации», разрешение отдаётся **до**
  чтения субъекта. Применимо только там, где авторизация есть в другом месте
  (предикат владельца прямо в запросе к БД) либо где ответ — глобальный справочник,
  который обязан читать каждый аутентифицированный.
- **`ScopeFiltered`** — единичная проверка снимается, но **аутентификация
  обязательна**: RPC авторизует на уровне данных (страница → вопрос про её
  идентификаторы пакетом). Субъект извлекается **до** ветвления на это поле, и
  запрос, который никого не называет, отбивается безусловно — второго рубежа за
  такой полосой нет по построению.
- Имя `Public` историческое: оно означает «не требует арендаторской проверки», а не
  «доступен извне».

Спрашивать «перечисли все объекты, которые субъекту можно» для полосы фильтрации
**запрещено** — почему именно, разобрано в [[corelib-authz-listobjects]].

## Decision pipeline (interceptor.authorize)

1. Breakglass=true → `Allowed` + WARN (на развёрнутом стенде недостижимо, см. Fail modes).
2. RPCMap lookup; **not found → `Unmapped` → `PermissionDenied` (fail-closed)**, без
   исключений — stream в том числе.
   > [!important] Пропуск Check выдаётся ЗАПИСЬЮ в карте, а не выводится из имени метода
   > Прежде здесь стояла эвристика по имени (`Internal*` ⇒ пропуск). Имя метода —
   > свойство строки, а не решение о доступе: любой новый RPC, попавший под шаблон,
   > молча получал пропуск, и добавление такого RPC выглядело в диффе как обычная
   > фича. Теперь `DecisionInternal` выдаётся **только** явной записью `Public=false` /
   > `ScopeFiltered=true` — то есть кто-то принял решение и оставил его в карте, где
   > drift-guard-тест его видит. Незамапленный RPC отказывает.
3. Principal extract; пусто → `Denied`. **Безусловно**, в том числе для
   `ScopeFiltered`-полосы: за ней нет per-RPC Check, на который можно откатиться,
   поэтому неопознанный вызывающий не имеет запасного пути.
4. Object extract; ошибка → `Denied`.
5. Cache lookup (positive-only); hit → `Allowed`/`Denied`.
6. Rate-limit per-principal (denied-storm).
7. `Client.Check(subject, relation, object)`; err →
   - `errors.Is(err, ErrNoPath)` → **DecisionNoPath**: pass-through к handler'у,
     который вернёт `NOT_FOUND` из БД (вместо masking как 403). Используется
     когда FGA hierarchy-tuple для объекта ещё не записан — KAC-133.
   - иначе → `Unavailable` (fail-closed).
8. allowed → cache positive + `Allowed`; иначе `Denied`.

## Fail modes (acceptance D-6)

- FGA/kacho-iam недоступен → fail-closed `PermissionDenied`.
- **Breakglass — аварийный полный обход Check, и он гейтится посадкой, а не дисциплиной.**
  В `production`/`production-strict` `Config.Validate()` **отказывает в старте**, называя
  ручку в тексте отказа (message-lock'нуто тестами в geo/registry/compute). Ручка,
  снимающая контроль, обязана быть недостижима на развёрнутом стенде — иначе она есть
  всегда, а «мы ею не пользуемся» проверить нечем. Живёт только в in-process
  unit/integration-фикстурах.

> [!note] Не путать с `ClusterBreakGlassGrant`
> Это **разные** механизмы. Здесь — config-ручка процесса (обход Check целиком).
> [[../resources/iam-cluster-break-glass-grant]] — доменный ресурс: аварийная выдача
> прав с двумя подписантами, сроком и kill-switch'ем, то есть решение внутри модели,
> а не в обход неё.

## Окно отзыва — ОБЪЯВЛЕННАЯ политика, а не сумма умолчаний

Кешируются **только положительные** вердикты. Поэтому свежая **выдача** видна
сразу (промах по кешу всегда идёт к авторитетному Check), а **отзыв ждёт**: запись
«разрешено» живёт до истечения своего срока. Значит срок жизни записи **и есть**
окно отзыва — время, в течение которого субъект, у которого право уже отобрали,
продолжает проходить. Асимметрия намеренная: выдавший не ждёт, отобравший ждёт
ограниченное и **объявленное** время.

Политика живёт в `pkg/authz/revocation_policy.go` — одним местом на все сервисы.
До этого окно было **эмерджентным**: шесть сервисов несли положительный кеш, каждый
называл своё число в своём комментарии, и ни одно место не говорило, каким числу
быть позволено. Параметр безопасности, которого никто не выбирал, нельзя ни
обсудить, ни отозвать, ни заметить при смене. Гейт связывает запись с деревом:
смена умолчания без правки политики роняет проверку.

> [!warning] Push-invalidate по каналу НЕ работает — у канала нет отправителя
> Прежняя редакция этой записки обещала проактивное снятие записи через
> `pg_notify('kacho_iam_subjects', subject_id)` и складывала из этого бюджет
> распространения. **В репозитории у этого канала нет ни одного отправителя** —
> только слушатели. Слагаемое было фиктивным, а обещание ложным: следующий
> читатель стал бы оптимизировать путь, которого нет. Итоговое число от снятия
> слагаемого не изменилось, но теперь это **объявленный потолок**, а не сумма с
> несуществующим членом.
>
> Слушатель (`ListenInvalidator`, выделенное соединение; переподключение →
> консервативный сброс всего кеша) в коде есть и провязан — отсюда и обманчивость:
> механизм выглядит рабочим с обеих сторон, кроме той, где его нет.
>
> **Немедленный отзыв учётных данных по этому окну не ездит** и остаётся на своём
> пути. Это записано здесь, чтобы «сделать окно поменьше» не подменяло «снять
> учётные данные».

## Decoupling

corelib НЕ импортирует kacho-proto stubs — adapter (`<service>/internal/.../check_client.go`)
живёт в сервисе и импортирует `iamv1.InternalIAMServiceClient`.

## Кто подключает (по дереву, `96b2879a`)

- [[vpc-apps-kacho-check]] · [[compute-internal-check]] · [[nlb-internal-check]] —
  сервисные адаптеры порта проверки;
- аналогичные пакеты проверки у geo, storage, registry;
- middleware шлюза;
- подпакет сверки каталога прав — держит обе стороны каталога согласованными.

## See also

[[../edges/iam-to-openfga-check]] [[../edges/vpc-to-iam-check]] [[../edges/compute-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-corelib #authz #cross-service #e3
