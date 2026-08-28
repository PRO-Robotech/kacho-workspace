# Kachō — квоты и биллинг: архитектура двух сервисов

**Статус:** проект решения (DRAFT). Не приёмка — приёмка Given-When-Then пишется по
этому документу и проходит `acceptance-reviewer` до первой строки кода (ban #1).

**Дерево, на котором сделаны замеры:** `PRO-Robotech/kacho` @ `16f3313fd`
(`git log --oneline -1`). Каждое число ниже несёт предикат: повторите его прежде,
чем строить на нём план. Правило корпуса действует и на этот документ — **число
из документа есть ориентир, а не факт**, дерево движется ежедневно.

**Кому адресован:** агентам-исполнителям. Документ описывает предмет, форму
контрактов, схему данных, гейты и порядок фаз с предикатами перехода. Он НЕ
заменяет приёмку: приёмка называет сценарии, документ — конструкцию.

---

## 1. Одна формулировка, из которой выведено всё остальное

**Квота — мгновенное значение вектора заряда. Биллинг — интеграл того же вектора
по времени.**

Создание машины производит вектор `{count:1, vcpu:4, memory:8192, gpu[a100]:1}`.
Один и тот же вектор:

| потребитель | что делает |
|---|---|
| квота | `used += Δ`, отказ при `used + Δ > limit` |
| биллинг | закрывает прежний интервал, открывает новый с новым вектором |

Один производитель вектора — сгенерированный триггер в транзакции мутации. Два
потребителя. **Второго механизма измерения не заводится.**

---

## 2. Сводка решений сессии

| # | решение | отвергнутая альтернатива и причина |
|---|---|---|
| Р1 | Учёт остаётся **в транзакции владельца**, но таблица и триггер **генерируются** из объявления | Аренда слотов у изолированного сервиса: заводит синхронную зависимость на пути каждого создания (радиус — всё облако), верит самоописанию соседа и даёт отказ при формально свободном месте |
| Р2 | Сервис квот изолирован: каталог, величины, чтение арендатором, отказ, наблюдаемость | Оставить как есть: механизм живёт в 5 раскладках, 3 реализации разошлись, 6 из 48 коммитов чинили одно в 4–5 сервисах |
| Р3 | **Конечный ресурс только пишет свою строку** | Порт `QuotaGuard` в use-case: второй производитель отказа, отключаемый молча (`if u.quota != nil`) |
| Р4 | Суб-сущности (vCPU/RAM/GPU) — **меры над столбцами той же строки** | Соединение с каталогом машин: `effective_resources` стоит в изменяемом наборе `MachineType.Update`, значит правка справочника меняла бы занятое у арендатора без его мутации |
| Р5 | Мера может нести **измерение** (`gpu_type`, `disk_type_id`); измеряемая мера обязана иметь умолчание `"*"` | Отдельный вид на каждый тип GPU: новый тип в справочнике открывал бы дыру без правки квот |
| Р6 | Квоты и биллинг — **два сервиса**, ноль рёбер между ними, **один манифест** | Один сервис: приёмник квоты принимает снимки от семи владельцев; журнал денег в том же адресном пространстве — неоплаченное расширение поверхности |
| Р7 | Генерируется **только производное**; всё, что содержит решение, пишется руками | Генерировать миграции вообще: генератор решений не принимает, он их тиражирует |
| Р8 | Рендер всегда пишет **новый** файл миграции | Фиксированное имя (как сегодня в `pkg/quota/refusal.go:56`): переписывает применённое, свежая и поднятая базы расходятся молча |

---

## 3. Замеры дерева

### 3.1 Цена сегодняшней схемы

| сервис | не-тестовых файлов со словом quota | миграций |
|---|---:|---:|
| vpc | 48 | 7 |
| iam | 34 | 9 |
| nlb | 34 | 6 |
| compute | 26 | 6 |
| storage | 22 | 4 |
| registry | 20 | 4 |
| **итого** | **184** | **36** |

Предикаты (оба нужны — у колонок они **разные**):

```sh
git grep -lie quota -- "services/<s>" ':!*_test.go' | wc -l        # колонка файлов
git ls-files "services/<s>/internal/migrations" | xargs grep -lie quota | wc -l   # колонка миграций
```

> [!note] Колонка миграций зависит от предиката, и это надо было сказать сразу
> Отбор **по содержимому** даёт 7/9/4/5/4/4 = **33**; отбор **по имени файла** —
> 6/4/4/4/4/4 = **26**; в таблице стоит 7/9/6/6/4/4 = **36** (первый предикат,
> снятый до части правок дерева). Число здесь — ориентир порядка величины, и
> довод Р2 на нём не держится: он держится на колонке файлов, которая
> воспроизводится побайтово.

### 3.2 Механизм существует в трёх раскладках

| раскладка | сервисы | предикат |
|---|---|---|
| `internal/apps/kacho/shared/quota/` | vpc (361 стр.), storage (363), compute (208) | `git ls-files services/<s> \| grep quota` |
| `internal/apps/kacho/quota/` | registry, **nlb** | то же |
| `internal/apps/kacho/shared/quota.go` | iam | то же |

Три реализации первой раскладки уже разошлись по объёму; нормализованные хеши различны.

> [!note] Здесь стояло «пять раскладок», и строка про nlb была ложной
> Прежняя редакция утверждала, что у nlb учёт «встроен в `create.go`/`ports.go`
> каждого ресурса». Перемерено: `services/nlb/internal/apps/kacho/quota/guard.go`
> и `states.go` существуют — та же раскладка, что у registry. Ошибка возникла
> оттого, что первый замер обходил только `internal/apps/.../api/` и пакет
> уровнем выше в выборку не попал.
>
> Число несущее: «пять раскладок» — заголовочный довод решения Р2. Три
> раскладки его не отменяют (механизм по-прежнему существует в трёх местах, и
> три реализации одной из них разошлись), но довод обязан опираться на верное
> число, иначе он рассыплется при первой же проверке читателем.

### 3.3 Один предмет чинился в пяти местах

**Предикат назван, потому что два разумных предиката дают разные числа**, и без
имени предиката число не воспроизводится:

| предикат | число |
|---|---|
| `git log --format='%h' --no-merges \| head -4000` + отбор коммитов, тронувших файл, чей путь содержит `quota` | **48** |
| `git log --oneline main -- '*quota*'` (отбор по маске имени, только ствол) | **36** |

Из **48** (первый предикат) **6** тронули четыре и более сервисов разом.
Их собственные заголовки:

- `refactor(quota): отказ учёта рендерится из одного источника, а не из пяти копий`
- `fix(quota): потребление считается по строкам, а не начинается с нуля`
- `fix(quota): полоса чтения отвечает про НАЗВАННОГО носителя, а не про один`
- `fix(quota): носитель учёта едет в ответе, а не угадывается потребителем`

### 3.4 Что уже есть и переиспользуется

| артефакт | координата | роль в новой схеме |
|---|---|---|
| закрытый каталог видов, **31** запись | `services/iam/internal/domain/limit.go` | переезжает в манифест |
| таблица учёта и триггер списания | `services/nlb/internal/migrations/0032_project_resource_quotas.sql` | образец формы `quota_usage` |
| **рендер миграции из шаблона** | `tools/quota-refusal-migration`, `pkg/quota/refusal.sql.tmpl` | расширяется, второй генератор не заводится |
| обратное заполнение из строк | `services/compute/internal/migrations/0037_quota_usage_seeded_from_rows.sql` | образец backfill |
| скаляры заряда на машине | `services/compute/internal/migrations/0016_instance_redesign.sql:25-28` — `eff_vcpu`, `eff_memory_mib`, `eff_gpus`, `eff_gpu_type` | меры `compute.instance` |
| отдельное полномочие `billing_admin` | `proto/kacho/cloud/iam/v1/fga_model.fga:195,298` | власть над деньгами уже отделена |

### 3.5 Что в дереве УЖЕ решено — и этим документом не отзывается молча

Три решения найдены в дереве **после** написания первой редакции. Каждое либо
переиспользуется, либо отзывается **явно**, с ценой.

| решение дерева | координата | что делает этот документ |
|---|---|---|
| **носитель-идентичность у аккаунта уже построен** | `proto/kacho/cloud/quota/v1/identity_quota_service.proto` | переиспользуется; работы по `iam.account` нет |
| **`InternalLimitService` несёт СЕМЬ RPC** (`Get`, `List`, `Create`, `Update`, `Delete`, `Resolve`, `ListChangedSince`) | `proto/kacho/cloud/iam/v1/internal_limit_service.proto` | §10.2 **расширяет** его мерой и измерением и **не сокращает**: сужение до трёх глаголов было ошибкой первой редакции. Потребители — allowlist края, таблица маршрутов, встроенный каталог прав, `pkg/quota/quotaiam`, `services/*/internal/clients` |
| **постраничности у чтения квот НЕТ — намеренно** | `proto/kacho/cloud/vpc/v1/quota_service.proto:33` | решение **цитируется и отзывается явно**, см. ниже |
| **`GET /iam/v1/quotas`** — чтение квот арендатором, провязано на крае | `identity_quota_service.proto`, `gateway/internal/restmux/mux.go` | **остаётся** как `ListIdentityQuotas` (§10.1.1); переезжает адресом на фазе C с объявленным сломом |
| **`/iam/v1/limits`** — админ-CRUD величин, **5** публичных RPC | `proto/kacho/cloud/iam/v1/limit_service.proto` | **остаётся авторитетом до фазы C**; после — переезд адреса, объявленный слом |
| **`iam.v1.InternalLimitService` — СЕМЬ RPC** | `internal_limit_service.proto` | §10.2 **расширяет** мерой и измерением; сокращение до трёх глаголов было ошибкой первой редакции |

**Пока обе поверхности живы, «где предел» имеет два ответа.** Это допустимо ровно
на время фаз E-M и обязано быть закрыто фазой C — иначе два владельца одного
предмета разойдутся на первом же расхождении.

> [!important] Отзыв объявленного решения о постраничности — с ценой, а не молча
> Дерево говорит дословно: каталог видов закрыт и мал, курсор добавил бы отказной
> режим и не купил бы ничего; **«если каталог однажды перестанет помещаться в один
> ответ, это изменение контракта со своей приёмкой, а не поле, тихо добавленное
> сюда»**.
>
> Меры **умножают** каталог: у `compute.instance` их четыре, у `storage.volumes` две,
> у измеряемых мер строк столько, сколько разрезов у арендатора. То есть предпосылка
> «закрыт и мал» перестаёт быть верной по построению — это ровно тот случай, который
> решение само называет основанием для пересмотра.
>
> Поэтому постраничность вводится **изменением контракта со своей приёмкой**, а не
> добавлением поля: `page_size`/`page_token` объявляются вместе с обоснованием, и
> строка `quota_service.proto` переписывается в том же изменении. Оставить обе
> редакции — два места об одном предмете, из которых верно одно.

### 3.6 Ограничения, определяющие охват

| факт | предикат | следствие |
|---|---|---|
| data plane отсутствует | `docs/specs/00-overview-and-scope.md` §3 | трафик, IOPS, фактические байты не тарифицируются — их знает исполнитель, которого нет |
| удаление жёсткое, `deleted_at` нет ни у одного сервиса | `grep -rln deleted_at services/*/internal/migrations/*.sql` → пусто | интервал обязан закрываться **тем же оператором**, что удаляет строку |
| control plane реестра не знает размера блобов | в миграциях registry нет числового столбца размера | `registry.storage.gib` не заводится, пока нет репортёра хранилища |
| `MachineType.Update` допускает правку `effective_resources` | `machineTypeUpdateKnown` в `services/compute/internal/apps/kacho/api/machinetype/machine_type.go:167` | заряд берётся со строки ресурса, не из справочника |

---

## 4. Понятийная модель

| понятие | определение | пример |
|---|---|---|
| **вид** (kind) | что ограничивается/тарифицируется; токен `domain.resource` из закрытого каталога | `compute.instance` |
| **мера** (measure) | величина, снимаемая со строки: `count` либо значение числового столбца | `vcpu` |
| **измерение** (dimension) | разрез меры по значению столбца; у каждого разреза своя величина и своя цена | `gpu_type=a100` |
| **носитель** (carrier) | к чему привязан учёт: `project`, `account`, `identity` либо родительский вид | `project` |
| **заряд** (charge) | значение меры в строке на момент записи | `eff_vcpu = 4` |
| **вектор заряда** | все меры вида по одной строке | `{count:1, vcpu:4, …}` |
| **уровень** | сумма зарядов по носителю — предмет квоты | `used = 128 vcpu` |
| **интервал** | заряд, помноженный на время — предмет биллинга | `4 vcpu × 3600 s` |

**Вложенность и мера — разные вещи.** Точка в `vpc.network.subnet` означает
**носителя-родителя** («сколько детей в одном родителе»). Мера — величина той же
строки. Поэтому мера — отдельное поле манифеста, а не третий сегмент токена.

---

## 5. Топология

```
                 ┌────────────┐        ┌────────────┐
   владельцы ───▶│   quota    │        │  billing   │◀─── владельцы
   (7 сервисов)  │  (лист)    │        │  (лист)    │     (интервалы)
                 └────────────┘        └────────────┘
                        ▲                     ▲
                        └──── край (gateway) ─┘   (чтение арендатором, authz на крае)
```

**Рёбер между quota и billing — ноль.** Проверено по каждому направлению:

| что могло бы связать | почему не связывает |
|---|---|
| каталог мер | сборочный артефакт: оба встраивают сгенерированное из одного манифеста, байт-идентичность держит гейт (прецедент — `permission-catalog`: seed iam ↔ middleware края) |
| носитель и его аккаунт | приезжает в самоописывающемся запросе владельца |
| величины пределов | биллингу не нужны |
| состояние счёта при неоплате | тянет **владелец** у биллинга, не квота |

**`iam → quota` существует, и это ОТЗЫВАЕТ у iam звание листа.** iam считает свои
же семь видов, значит он клиент сервиса квот наравне с остальными. Норма продукта
(`polyrepo.md`) сегодня говорит: «`geo` и `iam` — leaf-домены: их зовут, они **не
зовут никого** из сервисов», и требует: «новое ребро фиксируется здесь как
runtime-edge; ребро вне перечня не участвует ни в проверке ацикличности, ни в
разборе при отладке».

**Значит фаза E1 обязана внести в `polyrepo.md` два изменения**, и это правка
нормы, а не документа архитектуры: (1) зарегистрировать рёбра `<все семь> → quota`
и `<все семь> → billing`; (2) снять с iam звание чистого листа, назвав его
единственное исходящее ребро.

> [!warning] Довод «иначе взаимная блокировка» был НЕВЕРЕН, и это надо сказать прямо
> Первая редакция снимала per-RPC Check на слушателе владельцев, ссылаясь на
> риск взаимной блокировки цикла `iam → quota → iam`. Оба вызова `iam → quota`
> (§10.3) — **вне пути запроса**: дельта величин и периодический снимок. Фоновое
> ребро такой блокировки с синхронным `quota → iam` не образует.
>
> Настоящая причина локальной авторизации другая и она названа в §5.1: приём
> потребления не должен зависеть от доступности соседа. Отказ приёма теряет
> денежные данные, восстановить которые после жёсткого удаления ресурса нельзя.
> Довод, снятый вместе с ошибкой, заменён — а не отброшен вместе с решением.

Отсюда:

1. всё нужное для решения приезжает в запросе (носитель, его аккаунт, вид);
2. внутренний слушатель — mTLS + непустой круг законных отправителей + отказ
   старта на пустом круге;
3. **авторизация на этом слушателе есть, и её источник — сертификат, а не iam**
   (см. ниже);
4. публичное чтение арендатором авторизуется **на уровне данных**, а не одним
   вопросом на метод (см. §10.1).

### 5.1 Слушатель владельцев: авторизация локальная, а не отсутствующая

Первая редакция объявляла здесь **задокументированное исключение** из per-RPC
Check по образцу маршрута набора ключей. Исключение снято: образец не переносится
ни по одной оси.

| ось | маршрут ключей | слушатель владельцев |
|---|---|---|
| характер операции | чтение | **мутация авторитетной проекции** |
| что на проводе | только публичный ключевой материал | потребление и денежные интервалы **всех** арендаторов |
| радиус ошибки | ноль | ёмкость и деньги платформы |

Довод «иначе цикл `iam → quota → iam`» доказывает лишь, что здесь нельзя звать
**iam**. Он не доказывает, что решения о доступе быть не должно.

**Решение: авторитет прав на этом слушателе — сертификат, и решение принимается
локально.** Личность пира уже читается в дереве (`pkg/grpcsrv/cert_identity.go`,
модульная личность вида `kacho-<svc>`), значит вызова к соседу не требуется и
цикла не заводится.

Правило — одно и выводится из манифеста, а не выписывается:

> **Отправитель вправе писать только о видах СВОЕГО домена.** Строка отчёта, чей
> `kind` принадлежит чужому домену, отвергается `PERMISSION_DENIED`; соответствие
> «вид → домен» берётся из встроенного каталога, собранного из тех же манифестов.

### 5.2 Заявленный носитель сверяется с личностью, а не принимается на веру

`domain`, `carrier_id` и `account_id` — поля **запроса**. Принимать их без сверки
значит вводить ровно тот класс, которым отвергнута аренда слотов (Р1): «счёт
верит заявлению соседа».

Первая редакция предлагала «фиксировать связь проект → аккаунт при первом
предъявлении и отвергать конфликтующее». Это снято, и по трём причинам:

1. защищает **не тот** предмет — отображение носителя, а не право заявителя
   говорить за домен и меру;
2. «первое предъявление» есть гонка **без арбитра**: ребра к владельцу личности у
   сервиса квот нет by construction, проверить заявление не у кого;
3. отвержение конфликтующего превращает опережающее заявление в **отказ в
   обслуживании законному владельцу** — его правдивые отчёты начинают
   конфликтовать и отбрасываться. Защита работает против жертвы.

**Что действует вместо:**

| проверка | чем держится |
|---|---|
| `kind` принадлежит домену отправителя | каталог из манифестов + личность пира |
| `carrier_type` допустим для этого вида | тот же каталог |
| `account_id` не противоречит ранее известному | сверка, а **не** фиксация из первого отчёта; расхождение — `FAILED_PRECONDITION` + тревога, и **отчёт отвергается целиком**, а не частично |
| отчёт полон по объявленному носителю | усечённый перечень открытых интервалов закрыл бы живые (см. §12) |

Отдельно названо, от кого механизм **не** защищает: учёт живёт в транзакции
владельца и исполняется его правами, поэтому квота — контроль против ошибок
владельца и против арендатора, **а не рубеж изоляции арендаторов от
скомпрометированного владельца**. Это законный размен (альтернатива отвергнута в
Р1 с причиной), но он обязан быть назван, иначе следующий читатель примет квоту
за то, чем она не является.

---

## 6. Манифест — единственный источник

Один файл на домен: `services/<svc>/quota.yaml`. Его читают генератор, сервис
квот и сервис биллинга; расхождение невыразимо.

### 6.1 Схема манифеста

```yaml
# services/<svc>/quota.yaml
version: 1                      # версия схемы манифеста, не содержимого
domain: <svc>                   # совпадает с каталогом сервиса
schema: kacho_<svc>             # схема Postgres владельца

kinds:
  - kind: <domain>.<resource>           # токен закрытого каталога
    table: <schema>.<table>             # где лежат строки, по которым считаем
    carrier:                            # к чему привязан учёт
      type: project | account | identity | <parent.kind>
      column: <col>                     # столбец-носитель в этой же таблице
    account_column: <col>               # зеркало аккаунта; '' если носитель = account
    measures:
      - measure: count                  # имя меры; 'count' зарезервировано
        expr: 1                         # ЛИБО expr (константа), ЛИБО column
        unit: item
        quotable: {default: 200}        # умолчание DEFAULT-области; 0 законен
        billable: false                 # решение обязательно, умолчания нет
      - measure: vcpu
        column: eff_vcpu                # числовой столбец ЭТОЙ таблицы
        unit: vcpu
        quotable: {default: 128}
        billable:
          sku: compute.instance.vcpu.hour
          when: "status IN ('RUNNING','STARTING','RESTARTING')"   # предикат ставки
      - measure: gpu
        column: eff_gpus
        dimension: eff_gpu_type         # разрез меры
        unit: gpu
        quotable:
          defaults: {"*": 0, "a100": 8} # '*' ОБЯЗАТЕЛЕН у измеряемой меры
        billable:
          sku: compute.instance.gpu.hour
          when: "status IN ('RUNNING','STARTING','RESTARTING')"
    enforcement: EXACT | OFF            # OFF = считаем, не отказываем
```

**Правила формы, проверяемые генератором и стражем старта:**

| правило | признак нарушения | когда падает |
|---|---|---|
| `column` существует и числовой | опечатка → `NULL` → списание нулём | **при накатке миграции** (`DO … RAISE`) и на старте |
| у меры с `dimension` есть умолчание `"*"` | новый тип GPU без предела | старт |
| `billable` задан явно (`false` — тоже решение) | мера появляется бесплатной по недосмотру | генерация |
| `expr` и `column` взаимоисключающи | два способа сказать одно | генерация |
| `carrier.type` ∈ закрытого перечня либо существующий вид | висячий носитель | генерация |
| `unit` назван | «а у нас в мегабайтах» как второй словарь | генерация |
| токен `kind` уникален по дереву | два владельца одного вида | сводный гейт |
| **`carrier.column`, `account_column`, `dimension`-столбец существуют** | опечатка в носителе даёт `carrier_id = ''` — **все проекты платформы схлопываются в один счётчик**; тихо и необратимо для учёта | накатка **и** старт |
| **значения `defaults` производимы столбцом измерения** | `addr_type` — `smallint`, а ключи объявлены строками: совпадёт только `"*"`, и каждое создание отказывается «по пределу ноль» | генерация: тип столбца против ключей |
| **числовой тип включает `smallint`, `real`, `double precision`** | законный столбец `smallint` объявлялся бы негодным — гейт с ложными находками отключают первым | генерация |
| **`enforcement` доезжает до строки учёта** | поле принимают и не применяют: состояние `DISABLED` объявлено и недостижимо | проба: мера `OFF` пропускает сверх потолка |

### 6.2 vpc

```yaml
version: 1
domain: vpc
schema: kacho_vpc

kinds:
  - {kind: vpc.network,          table: kacho_vpc.networks,           carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 16}, billable: false}], enforcement: EXACT}
  - {kind: vpc.subnet,           table: kacho_vpc.subnets,            carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  - {kind: vpc.securityGroup,    table: kacho_vpc.security_groups,    carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  - {kind: vpc.routeTable,       table: kacho_vpc.route_tables,       carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 32}, billable: false}], enforcement: EXACT}
  - {kind: vpc.gateway,          table: kacho_vpc.gateways,           carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 8}, billable: false}], enforcement: EXACT}
  - {kind: vpc.networkInterface, table: kacho_vpc.network_interfaces, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 128}, billable: false}], enforcement: EXACT}
  - {kind: vpc.cidrGroup,        table: kacho_vpc.cidr_groups,        carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 32}, billable: false}], enforcement: EXACT}

  # Адрес — единственный вид vpc, который стоит денег: внешний адрес есть
  # ограниченный ресурс платформы. Измерение по типу адреса; внутренний
  # НЕ тарифицируется вовсе (предикат `when`), а не «тарифицируется нулём»:
  # нулевая цена и отсутствие начисления — разные вещи, и вторая дешевле
  # (нет строки — нет вопроса «почему ноль»).
  - kind: vpc.address
    table: kacho_vpc.addresses
    carrier: {type: project, column: project_id}
    account_column: ""            # ИЗМЕРЕНО: строка ресурса зеркала не несёт (§8.1.1)
    measures:
      - measure: count
        expr: 1
        dimension: addr_type
        unit: item
        # ИЗМЕРЕНО: `addr_type` — smallint (0001_initial.sql), контракт объявляет
        # INTERNAL=1, EXTERNAL=2 (address.proto). Ключи умолчаний обязаны быть
        # ТЕМИ значениями, которые столбец производит, а не именами вариантов:
        # `v_new ->> 'addr_type'` вернёт "1"/"2" и никогда "EXTERNAL".
        quotable: {defaults: {"*": 0, "2": 16, "1": 256}}
        # Тарифицируется только внешний адрес. Предикат по СТОЛБЦУ, не по имени.
        billable: {sku: vpc.address.hour, when: "addr_type = 2"}
    enforcement: EXACT

  # Вложенность: сколько детей помещается в ОДНОМ родителе. Опасность живёт
  # именно здесь — одна сеть с десятью тысячами подсетей есть другой отказ,
  # чем десять тысяч подсетей по проектам.
  - {kind: vpc.network.subnet,        table: kacho_vpc.subnets,          carrier: {type: vpc.network, column: network_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  - {kind: vpc.network.routeTable,    table: kacho_vpc.route_tables,     carrier: {type: vpc.network, column: network_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 32}, billable: false}], enforcement: EXACT}
  - {kind: vpc.network.securityGroup, table: kacho_vpc.security_groups,  carrier: {type: vpc.network, column: network_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
```

### 6.3 compute — здесь появляются суб-сущности

```yaml
version: 1
domain: compute
schema: public        # ИЗМЕРЕНО: у compute схема отличается от прочих — `public`,
                      # предикат: grep -rhoE 'search_path TO [a-z_, ]+' \
                      #   services/compute/internal/migrations/*.sql → 8× 'public'

kinds:
  - kind: compute.instance
    table: instances
    carrier: {type: project, column: project_id}
    account_column: ""            # ИЗМЕРЕНО: строка ресурса зеркала не несёт (§8.1.1)
    measures:
      - measure: count
        expr: 1
        unit: item
        quotable: {default: 32}
        billable: false                      # штука не стоит денег — стоит её содержимое
      - measure: vcpu
        column: eff_vcpu
        unit: vcpu
        quotable: {default: 128}
        billable: {sku: compute.instance.vcpu.hour, when: "status IN ('RUNNING','STARTING','RESTARTING')"}
      - measure: memory
        column: eff_memory_mib
        unit: MiB
        quotable: {default: 524288}
        billable: {sku: compute.instance.memory.hour, when: "status IN ('RUNNING','STARTING','RESTARTING')"}
      - measure: gpu
        column: eff_gpus
        dimension: eff_gpu_type
        unit: gpu
        quotable: {defaults: {"*": 0}}       # незнакомый тип GPU не выдаётся, пока про него не решили
        billable: {sku: compute.instance.gpu.hour, when: "status IN ('RUNNING','STARTING','RESTARTING')"}
    enforcement: EXACT

  - {kind: compute.placementGroup,  table: placement_groups,   carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 8}, billable: false}], enforcement: EXACT}
  - {kind: compute.guestAccessKey,  table: guest_access_keys,  carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
```

> **Предикат `when` пишется по значениям СТОЛБЦА, а не по вариантам контракта —
> и они расходятся.** Измерено: `instances.status` — `TEXT` со значением по
> умолчанию `'PROVISIONING'` (`services/compute/internal/migrations/0001_initial.sql`),
> то есть хранит имена вариантов; но в БД встречается `'DELETING'`
> (`0027_instances_deleting_since.sql:43`), которого в перечне `Instance.Status`
> контракта **нет**. Предикат, написанный по контракту, промахнулся бы мимо
> живого состояния. Отсюда правило: значения для `when` берутся переписью
> столбца, и генератор обязан её печатать.
>
> **Остановленная машина держит квоту vCPU и не тарифицируется.** Это
> единственное место, где два потребителя вектора расходятся по существу, и оно
> объявлено предикатом `when`, а не выведено. Квота защищает ёмкость (она занята
> и при `STOPPED`), счёт берётся за работу.

### 6.4 storage

```yaml
version: 1
domain: storage
schema: kacho_storage

kinds:
  - kind: storage.volumes
    table: kacho_storage.volumes
    carrier: {type: project, column: project_id}
    account_column: ""            # ИЗМЕРЕНО: строка ресурса зеркала не несёт (§8.1.1)
    measures:
      - {measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}
      - measure: capacity
        column: size_bytes
        dimension: disk_type_id            # цена и предел различаются по типу диска
        unit: B
        quotable: {defaults: {"*": 1099511627776}}   # 1 ТиБ на неназванный тип диска
        billable: {sku: storage.volume.byte.hour, when: "true"}
    enforcement: EXACT

  - kind: storage.snapshots
    table: kacho_storage.snapshots
    carrier: {type: project, column: project_id}
    account_column: ""            # ИЗМЕРЕНО: строка ресурса зеркала не несёт (§8.1.1)
    measures:
      - {measure: count, expr: 1, unit: item, quotable: {default: 128}, billable: false}
      - {measure: capacity, column: size_bytes, unit: B, quotable: {default: 2199023255552}, billable: {sku: storage.snapshot.byte.hour, when: "true"}}
    enforcement: EXACT

  - kind: storage.images
    table: kacho_storage.images
    carrier: {type: project, column: project_id}
    account_column: ""            # ИЗМЕРЕНО: строка ресурса зеркала не несёт (§8.1.1)
    measures:
      - {measure: count, expr: 1, unit: item, quotable: {default: 32}, billable: false}
      - {measure: capacity, column: size_bytes, unit: B, quotable: {default: 549755813888}, billable: {sku: storage.image.byte.hour, when: "true"}}
    enforcement: EXACT
```

> **Единица — байт, а не гибибайт.** Хранение целого числа байт снимает вопрос
> округления на уровне учёта; в человекочитаемое приводит край и консоль, а цена
> объявляется за байт-час в микроединицах валюты. Смешение единиц между учётом и
> прайсом — второй словарь и запрещено.

### 6.5 nlb

```yaml
version: 1
domain: nlb
schema: kacho_nlb

kinds:
  - {kind: loadbalancer.networkLoadBalancers, table: kacho_nlb.load_balancers, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 8},
                 billable: {sku: nlb.balancer.hour, when: "status <> 'DELETING'"}}], enforcement: EXACT}
  - {kind: loadbalancer.targetGroups, table: kacho_nlb.target_groups, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 32}, billable: false}], enforcement: EXACT}
  - {kind: loadbalancer.listeners, table: kacho_nlb.listeners, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  - {kind: loadbalancer.networkLoadBalancers.listeners, table: kacho_nlb.listeners, carrier: {type: loadbalancer.networkLoadBalancers, column: load_balancer_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 16}, billable: false}], enforcement: EXACT}
```

> Пара `targetGroups → targets` в каталоге **отсутствует, и это решение**:
> `Target` — строка `kacho_nlb.targets`, но не грантуемый тип модели прав, а
> токен обязан называть существующий тип. Риск «слишком много целей в одной
> группе» остаётся открытым и несёт свой предикат снятия.

### 6.6 registry

```yaml
version: 1
domain: registry
schema: kacho_registry

kinds:
  - {kind: registry.registries, table: registries, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 8}, billable: false}], enforcement: EXACT}
  - {kind: registry.repositories, table: repository_configs, carrier: {type: project, column: project_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 256}, billable: false}], enforcement: EXACT}
  - {kind: registry.registries.repositories, table: repository_configs, carrier: {type: registry.registries, column: registry_id}, account_column: "",   # столбца нет в строке ресурса — измерено, §8.1.1
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 128}, billable: false}], enforcement: EXACT}
```

> **`registry.storage.byte.hour` НЕ заводится.** Байты блобов живут за пределами
> control plane: числового столбца размера в миграциях registry нет. Мера
> заводится вместе с репортёром хранилища, не раньше. Это отсутствие —
> объявленное решение, а не пропуск: строка стоит в разделе открытого долга §20.
>
> Отдельно: `repository_configs` носит `registry_id`, а до проекта доходит
> соединением со своим реестром **внутри одной БД**. Проектный носитель поэтому
> требует зеркала `project_id` в строке либо представления; **ПЕРЕМЕРИТЬ** и
> выбрать до фазы E2.

### 6.7 iam — владелец величин и владелец типа одновременно

```yaml
version: 1
domain: iam
schema: kacho_iam

kinds:
  # Аккаунт считается по ИДЕНТИЧНОСТИ: без этого каждый предел внутри аккаунта
  # выкупается тем же самообслуживанием, которым получен сам аккаунт.
  - {kind: iam.account, table: kacho_iam.accounts, carrier: {type: identity, column: owner_user_id}, account_column: "",
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 2}, billable: false}], enforcement: EXACT}

  - {kind: iam.project,        table: kacho_iam.projects,         carrier: {type: account, column: account_id}, account_column: account_id,
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 16}, billable: false}], enforcement: EXACT}
  - {kind: iam.user,           table: kacho_iam.users,            carrier: {type: account, column: account_id}, account_column: account_id,
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 128}, billable: false}], enforcement: EXACT}
  - {kind: iam.serviceAccount, table: kacho_iam.service_accounts, carrier: {type: account, column: account_id}, account_column: account_id,
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 128}, billable: false}], enforcement: EXACT}
  - {kind: iam.group,          table: kacho_iam.groups,           carrier: {type: account, column: account_id}, account_column: account_id,
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  - {kind: iam.role,           table: kacho_iam.roles,            carrier: {type: account, column: account_id}, account_column: account_id,
     measures: [{measure: count, expr: 1, unit: item, quotable: {default: 64}, billable: false}], enforcement: EXACT}
  # ИЗМЕРЕНО: `kacho_iam.access_bindings` НЕ несёт ни `account_id`, ни иного
  # столбца тенантности (предикат: grep -A25 'CREATE TABLE kacho_iam.access_bindings'
  # services/iam/internal/migrations/*.sql | grep -c account_id → 0). Значит
  # носитель этого вида столбцом строки НЕ ВЫРАЖАЕТСЯ, и объявить его так, как
  # соседей, нельзя: манифест обязан называть существующий столбец.
  #
  # Вид ОСТАВЛЕН БЕЗ ОБЪЯВЛЕНИЯ и вынесен в долг D9 — исходов два, и оба требуют
  # решения, а не рендера: (а) зеркало `account_id` на самой строке привязки,
  # заполняемое вставкой; (б) объявленный источник носителя не из строки, а из
  # СОБСТВЕННОГО зеркала iam (`resource_mirror.parent_account_id`) — то есть
  # расширение формы манифеста на «носитель через соединение внутри своей БД».
  # Второе шире и потому дороже: соединение в триггере на горячем пути записи.
```

> **Измерено** (`grep -A25 'CREATE TABLE kacho_iam.<t>' services/iam/internal/migrations/*.sql`):
> `projects`, `users`, `service_accounts`, `groups`, `roles` несут `account_id`;
> `accounts` несёт `owner_user_id` и `organization_id`; `access_bindings` —
> **ни одного** столбца тенантности (отсюда D9 выше).

### 6.8 geo — манифест пустой, и это решение

```yaml
version: 1
domain: geo
schema: kacho_geo
kinds: []
# Region/Zone — админ-курируемый глобальный каталог оси размещения; арендатор их
# не создаёт. Ни предела, ни цены. Пустой манифест ОБЯЗАТЕЛЕН: домен без файла
# неотличим от домена, про который забыли.
```

### 6.9 Сводный гейт по манифестам

Наследник `TestEveryTenantTypeIsCountable`: **каждый грантуемый тип модели прав**
обязан либо стоять в манифесте, либо быть перечислен в ведомости исключений с
причиной. Ведомость самоистекает: запись, которой больше нечего исключать, —
находка.

```sh
# перепись: типов в модели · видов в манифестах · исключений
awk '/^ *type /{t++} END{print "типов", t}' proto/kacho/cloud/iam/v1/fga_model.fga
grep -h '^\s*- kind:\|^\s*- {kind:' services/*/quota.yaml | wc -l
```

---

## 7. Генерация и миграции

### 7.1 Что рендерится, а что пишется руками

| артефакт | как | почему |
|---|---|---|
| таблицы `quota_usage`, `quota_measures`, `quota_defaults`, `usage_intervals`, `billing_measures` | **рендер** (параметр — схема) | шесть копий, обязанных совпасть побайтово; расхождение невидимо |
| функции `quota_charge()` и `billing_track()` | **рендер** | по одной на владельца, тела одинаковы |
| привязка триггера к таблице домена | **рендер** | механическое следствие вида |
| строки справочника мер | **рендер** (`INSERT … ON CONFLICT DO UPDATE`) | производно от манифеста |
| обратное заполнение `used` | **рендер** (`SUM(<column>)`) | вывод, не решение |
| таблицы ресурсов (`instances`, `subnets`) | **руками** | предметные решения домена |
| смена формы `quota_usage` | **руками** | решение, а не следствие |

**Порог, при котором генерация оправдана — три условия вместе:** форма повторяется
у ≥3 владельцев · расхождение копий невидимо на обзоре · содержание **производно**
(выводится однозначно, без принятия решения). Не выполнено хотя бы одно — пишется
руками.

**Признак, что генерация зашла не туда:** в манифесте появилось условие,
которого нет в предмете (`if`, «а для nlb иначе»), либо сгенерированный файл
кто-то правит руками.

### 7.2 Имя миграции производно от версии манифеста

Сегодняшний генератор пишет в **фиксированное** имя
(`pkg/quota/refusal.go:56` — `Migration: "0044_quota_refusal_single_source.sql"`),
то есть правка шаблона переписывает **применённую** миграцию. Отказ тихий: goose
применённую версию не перезапускает, поэтому свежая база получит новое, а
поднятая навсегда останется со старым.

**Норма для нового рендера:**

```
services/<svc>/quota.yaml          ← правит человек
services/<svc>/quota.lock.yaml     ← пишет генератор, читает при следующем рендере
services/<svc>/internal/migrations/0045_quota_measures_v3.sql   ← производное
```

Миграция есть разница `lock → manifest`. Прежние файлы неприкосновенны.

### 7.3 Гейты вокруг рендера

| свойство | как проверяется |
|---|---|
| повторный рендер без правки манифеста — ноль файлов | уже так у существующего генератора |
| `lock` сходится с суммой применённых миграций | иначе дельта считается от вымысла |
| ни один **применённый** файл не изменён | реестр хешей; сегодня этого нет |
| ноль целей = отказ, не успех | уже так (`перечень владельцев пуст`) |
| «что сгенерировано» и «что проверяется» — одна функция | уже так (`RenderRefusalMigration` зовут и генератор, и гейт) |
| шаблон **верен**, а не только согласован | поведенческая проба на живой базе: вставка сверх потолка отвергается, в предел — проходит, `UPDATE` даёт дельту нужного знака, `DELETE` возвращает |

Последняя строка — главная. Байт-идентичность доказывает **согласованность**, а не
**правильность**: дефект шаблона разъезжается по шести сервисам разом и остаётся
зелёным на всех текстовых проверках.

---

## 8. Схема у владельца

Владелец несёт **пять сгенерированных объектов и ни одной рукописной строки
учёта**: три таблицы квоты (`quota_usage`, `quota_measures`, `quota_defaults`),
таблица интервалов с её справочником (`usage_intervals`, `billing_measures`) и две
функции (`quota_charge`, `billing_track`).

> [!note] Здесь стояло «две таблицы и одна функция» — и это была не описка
> Функция читала `quota_defaults`, которой не было ни в одном перечне. Прогон на
> живой базе даёт `relation "quota_defaults" does not exist`, причём
> **`CREATE FUNCTION` проходит успешно**: plpgsql не резолвит имена при создании.
> То есть миграция накатывалась бы зелёной, а отказ наступал на первой мутации
> арендатора — и приходил бы к нему как `INTERNAL`/500, потому что `42P01` в
> перечень §9 не входит и уходит в фиксированный текст.

### 8.1 Таблица учёта

```sql
CREATE TABLE IF NOT EXISTS {{.Schema}}.quota_usage (
    carrier_type    text   NOT NULL,
    carrier_id      text   NOT NULL,
    kind            text   NOT NULL,
    measure         text   NOT NULL,
    dimension       text   NOT NULL DEFAULT '',   -- '' = мера без разреза

    used            bigint NOT NULL DEFAULT 0,

    limit_value     bigint NOT NULL,
    source_scope    text   NOT NULL,              -- DEFAULT | ACCOUNT | PROJECT
    source_scope_id text   NOT NULL DEFAULT '',
    limit_revision  bigint NOT NULL,
    enforcement     text   NOT NULL DEFAULT 'EXACT',  -- EXACT | OFF

    account_id      text   NOT NULL,
    synced_at       timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (carrier_type, carrier_id, kind, measure, dimension),
    CONSTRAINT quota_usage_used_check        CHECK (used >= 0),
    CONSTRAINT quota_usage_limit_check       CHECK (limit_value >= 0),
    CONSTRAINT quota_usage_scope_check       CHECK (source_scope IN ('DEFAULT','ACCOUNT','PROJECT')),
    CONSTRAINT quota_usage_enforcement_check CHECK (enforcement IN ('EXACT','OFF')),
    -- Ограничения на непустоту зеркала НЕТ: его заполняет синхронизатор (§8.1.1),
    -- а `CHECK (account_id IS NOT NULL)` на столбце `NOT NULL` не может упасть
    -- ни при каком входе — это декорация, а не инвариант.
    CONSTRAINT quota_usage_dimension_check   CHECK (dimension IS NOT NULL)
);
```

### 8.1.1 Зеркало аккаунта заполняет СИНХРОНИЗАТОР, а не триггер — измерено

Строка ресурса зеркала аккаунта **не несёт**: `account_id` отсутствует в
`kacho_vpc.networks`, `instances`, `kacho_storage.volumes`,
`kacho_nlb.load_balancers` — во всех четырёх ноль вхождений (предикат:
`grep -A40 'CREATE TABLE …' … | grep -cE '^\s+account_id'`). Сегодня зеркало
добывает `Admit`, резолвя проект в аккаунт у владельца величин; при норме
«ресурс только пишет» этого вызова не существует.

Отсюда **`CHECK (account_id <> '')` снят**, и это решение, а не послабление:

| кто | что делает с `account_id` |
|---|---|
| триггер | ставит `''`, если столбца в строке нет (у iam-таблиц он есть и берётся) |
| синхронизатор | заполняет из дельты величин, узнав носителя по появившейся строке |

Строка без зеркала **невидима аккаунтной дельте** и живёт с величиной области
`DEFAULT` до первого прохода синхронизатора. Окно ограничено периодом дельты,
направление ошибки — разрешительное, и оно **наблюдаемо**:
`quota_usage_rows_without_account{domain}` обязана сходиться к нулю; не сходится
— синхронизатор мёртв, и это видно, а не подразумевается.

Прежняя редакция этого раздела требовала непустого зеркала «by construction» —
она была написана по образцу `0032_project_resource_quotas.sql`, где зеркало
проставляет прикладной код. При «ресурс только пишет» такого кода нет, и
требование стало бы неисполнимым: **вставка отвергалась бы ограничением на
каждом ресурсе каждого домена, кроме iam.**

**`CHECK (used <= limit_value) НЕ СТАВИТСЯ.** Такой `CHECK` запретил бы САМО
понижение предела: администратор получал бы отказ, пока проект не освободит место.
Потолок держит предикат `used + Δ <= limit_value` условного `UPDATE` — того же
единственного оператора, что берёт блокировку строки. Решение перенесено дословно
из `0032_project_resource_quotas.sql` и не пересматривалось.

### 8.2 Справочник мер (строки, не тело функции)

```sql
CREATE TABLE IF NOT EXISTS {{.Schema}}.quota_measures (
    kind             text NOT NULL,
    measure          text NOT NULL,
    table_name       text NOT NULL,   -- 'kacho_vpc.subnets'
    value_column     text NOT NULL DEFAULT '',  -- '' ⇒ считаем строки (expr = 1)
    dimension_column text NOT NULL DEFAULT '',
    carrier_type     text NOT NULL,
    carrier_column   text NOT NULL,
    account_column   text NOT NULL DEFAULT '',
    unit             text NOT NULL,
    PRIMARY KEY (kind, measure)
);
```

Справочник законен в миграции: это **справочник продукта**, обязанный существовать
у всякого, кто развернул платформу, а не данные стенда.

Добавление меры = новая строка + обратное заполнение. Тело функции при этом **не
меняется** — иначе шесть тел одного предмета разойдутся, как уже разошлись пять
копий отказа.

### 8.2.1 Таблица умолчаний — та, которую читает триггер

Её отсутствие в первой редакции роняло функцию на первой же мутации
(`relation "quota_defaults" does not exist`), причём **`CREATE FUNCTION`
проходил успешно**: plpgsql не резолвит имена при создании, поэтому миграция
накатывалась зелёной, а отказ наступал на первой записи арендатора.

```sql
CREATE TABLE IF NOT EXISTS {{.Schema}}.quota_defaults (
    kind        text   NOT NULL,
    measure     text   NOT NULL,
    dimension   text   NOT NULL,   -- '*' = умолчание для неназванного значения
    value       bigint NOT NULL,
    revision    bigint NOT NULL DEFAULT 0,
    enforcement text   NOT NULL DEFAULT 'EXACT',
    PRIMARY KEY (kind, measure, dimension),
    CONSTRAINT quota_defaults_value_check       CHECK (value >= 0),
    CONSTRAINT quota_defaults_enforcement_check CHECK (enforcement IN ('EXACT','OFF'))
);
```

Заполняется **рендером из манифеста** (`INSERT … ON CONFLICT DO UPDATE`), то есть
это справочник продукта, а не данные стенда. Рантайм-писателей у неё нет; сверка
`quota_defaults` и `quota_measures` с манифестом — часть стража старта (§16), а не
только накатки: строка, появившаяся позже миграции, иначе не перечитывается никем.

### 8.3 Функция и триггер

```sql
CREATE OR REPLACE FUNCTION {{.Schema}}.quota_charge() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_kind text := TG_ARGV[0];
    -- Строка сериализуется в jsonb ОДИН раз на сторону. Прежняя редакция звала
    -- to_jsonb восемь раз в теле одного оператора — при четырёх мерах это
    -- тридцать сериализаций широкой строки (у машины есть labels jsonb) на одну
    -- мутацию, и именно они стоят за измеренными 42 мс (§8.3.1).
    v_new  jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
    v_old  jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_d    jsonb;      -- вектор заряда, вычисленный ОДИН раз
    v_miss record;
    v_fail record;
BEGIN
    -- ── 1. Вектор заряда ───────────────────────────────────────────────────
    -- ДВА независимых набора: NEW списывает, OLD возвращает. Именно
    -- раздельность делает верной смену ИЗМЕРЕНИЯ и смену НОСИТЕЛЯ — у них
    -- разные ключи, поэтому возврат уходит в старую строку, а списание в новую.
    -- Разность «NEW минус OLD в одной строке» на смене ключа теряет возврат
    -- целиком: старый разрез не уменьшался бы НИКОГДА.
    SELECT jsonb_agg(to_jsonb(x)) INTO v_d FROM (
        SELECT carrier_type, carrier_id, measure, dim,
               COALESCE(max(NULLIF(account_id,'')), '') AS account_id,
               sum(delta)                               AS delta
          FROM (
            SELECT m.carrier_type, m.measure,
                   COALESCE(v_new ->> NULLIF(m.dimension_column,''), '') AS dim,
                   COALESCE(v_new ->> m.carrier_column, '')              AS carrier_id,
                   COALESCE(v_new ->> NULLIF(m.account_column,''), '')   AS account_id,
                   (CASE WHEN m.value_column = '' THEN 1
                         ELSE COALESCE((v_new ->> m.value_column)::bigint, 0) END) AS delta
              FROM {{.Schema}}.quota_measures m
             WHERE m.kind = v_kind AND TG_OP <> 'DELETE'
            UNION ALL
            SELECT m.carrier_type, m.measure,
                   COALESCE(v_old ->> NULLIF(m.dimension_column,''), ''),
                   COALESCE(v_old ->> m.carrier_column, ''),
                   COALESCE(v_old ->> NULLIF(m.account_column,''), ''),
                   -(CASE WHEN m.value_column = '' THEN 1
                          ELSE COALESCE((v_old ->> m.value_column)::bigint, 0) END)
              FROM {{.Schema}}.quota_measures m
             WHERE m.kind = v_kind AND TG_OP <> 'INSERT'
          ) parts
         GROUP BY carrier_type, carrier_id, measure, dim
        HAVING sum(delta) <> 0
    ) x;

    IF v_d IS NULL THEN
        RETURN NULL;   -- мер у вида нет либо вектор нулевой: правка описания
    END IF;

    -- ПУСТОЙ НОСИТЕЛЬ — ОТКАЗ, А НЕ ПРОПУСК. Прежняя редакция отбрасывала такие
    -- строки условием `carrier_id <> ''`, и следствие было измерено прогоном:
    -- «создано 3 · строк учёта 0 · отказов 0» — ресурсы не считаются вовсе, и
    -- заметить это нечем. Столбец при этом СУЩЕСТВУЕТ (накаточный гейт §8.4
    -- доволен), а значение пусто: нулябельный носитель либо строка до обратного
    -- заполнения. Это дефект НАШ, не арендатора, поэтому INTERNAL.
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(v_d)
                    AS d(carrier_type text, carrier_id text, measure text,
                         dim text, account_id text, delta bigint)
                WHERE d.carrier_id = '') THEN
        RAISE EXCEPTION USING ERRCODE = 'KQ003',
            MESSAGE = format('quota: row of %s carries no carrier', v_kind);
    END IF;

    -- ── 2. «Не сказано» — отдельный отказ, а не молчаливый ноль ────────────
    -- Величина ноль ЗАКОННА и означает «этого вида не выдаём». Отсутствие
    -- величины означает другое — «никто не решал», — и обязано звучать иначе,
    -- иначе арендатор не отличит «мне не выделяли» от «я исчерпал».
    SELECT d.carrier_type, d.carrier_id, d.measure, d.dim INTO v_miss
      FROM jsonb_to_recordset(v_d) AS d(carrier_type text, carrier_id text,
                                        measure text, dim text, account_id text, delta bigint)
     WHERE d.delta > 0
       AND NOT EXISTS (SELECT 1 FROM {{.Schema}}.quota_defaults q
                        WHERE q.kind = v_kind AND q.measure = d.measure
                          AND q.dimension IN (d.dim, '*'))
       AND NOT EXISTS (SELECT 1 FROM {{.Schema}}.quota_usage u
                        WHERE u.carrier_type = d.carrier_type AND u.carrier_id = d.carrier_id
                          AND u.kind = v_kind AND u.measure = d.measure AND u.dimension = d.dim)
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'KQ002',
            MESSAGE = format('%s %s has no ceiling stated for %s',
                             v_miss.carrier_type, v_miss.carrier_id, v_kind),
            DETAIL  = jsonb_build_object('carrier_type', v_miss.carrier_type,
                                         'carrier_id',   v_miss.carrier_id,
                                         'kind', v_kind, 'measure', v_miss.measure,
                                         'dimension', v_miss.dim)::text;
    END IF;

    -- ── 3. Заведение строк — ОТДЕЛЬНЫМ ОПЕРАТОРОМ ──────────────────────────
    -- Заводить и списывать в ОДНОМ операторе нельзя: изменяющие данные CTE
    -- работают на общем снимке и не видят вставок друг друга, поэтому
    -- списание не нашло бы только что заведённой строки и КАЖДАЯ первая
    -- мутация в проекте получала бы отказ по исчерпанию. Два оператора внутри
    -- одной функции остаются одной транзакцией — атомарность не теряется.
    INSERT INTO {{.Schema}}.quota_usage
          (carrier_type, carrier_id, kind, measure, dimension,
           used, limit_value, source_scope, limit_revision, account_id, enforcement)
    SELECT d.carrier_type, d.carrier_id, v_kind, d.measure, d.dim,
           0, def.value, 'DEFAULT', def.revision, d.account_id, def.enforcement
      FROM jsonb_to_recordset(v_d) AS d(carrier_type text, carrier_id text,
                                        measure text, dim text, account_id text, delta bigint)
      JOIN LATERAL (
          SELECT q.value, q.revision, q.enforcement
            FROM {{.Schema}}.quota_defaults q
           WHERE q.kind = v_kind AND q.measure = d.measure
             AND q.dimension IN (d.dim, '*')
           ORDER BY (q.dimension = d.dim) DESC   -- точное значение бьёт '*'
           LIMIT 1                               -- ...и только одна строка
      ) def ON true
    ON CONFLICT (carrier_type, carrier_id, kind, measure, dimension) DO NOTHING;

    -- ── 4. Списание и отказ ────────────────────────────────────────────────
    WITH d AS (
        SELECT * FROM jsonb_to_recordset(v_d) AS t(carrier_type text, carrier_id text,
                                                   measure text, dim text,
                                                   account_id text, delta bigint)
    ),
    upd AS (
        -- ОСВОБОЖДЕНИЕ НИКОГДА НЕ РОНЯЕТ УДАЛЕНИЕ: отрицательная дельта
        -- ограничена снизу нулём, а не отвергается CHECK'ом. Расхождение чинит
        -- снимок; отказ в удалении ресурса по причине УЧЁТА был бы отказом
        -- продукта там, где арендатор освобождает место.
        UPDATE {{.Schema}}.quota_usage q
           SET used = CASE WHEN d.delta < 0 THEN GREATEST(0, q.used + d.delta)
                           ELSE q.used + d.delta END,
               updated_at = now()
          FROM d
         WHERE q.carrier_type = d.carrier_type AND q.carrier_id = d.carrier_id
           AND q.kind = v_kind AND q.measure = d.measure AND q.dimension = d.dim
           AND (d.delta < 0 OR q.enforcement = 'OFF' OR q.used + d.delta <= q.limit_value)
        RETURNING q.measure, q.dimension
    )
    SELECT d.carrier_type, d.carrier_id, d.measure, d.dim,
           q.limit_value, q.used, m.unit
      INTO v_fail
      FROM d
      JOIN {{.Schema}}.quota_usage q
        ON q.carrier_type = d.carrier_type AND q.carrier_id = d.carrier_id
       AND q.kind = v_kind AND q.measure = d.measure AND q.dimension = d.dim
      JOIN {{.Schema}}.quota_measures m
        ON m.kind = v_kind AND m.measure = d.measure
     WHERE d.delta > 0
       AND NOT EXISTS (SELECT 1 FROM upd u
                        WHERE u.measure = d.measure AND u.dimension = d.dim)
     -- Порядок объявлен: при ДВУХ исчерпанных осях без него называется
     -- произвольная, арендатор поднимает не тот предел и упирается снова.
     -- Полный перечень исчерпанного уезжает в DETAIL.
     ORDER BY d.measure, d.dim
     LIMIT 1;

    IF v_fail.measure IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'KQ001',
            -- ОДИН производитель текста на обе формы. Для `count` без разреза
            -- текст побайтово прежний — 31 сегодняшний вид не меняется ничем.
            MESSAGE = CASE
                WHEN v_fail.measure = 'count' AND v_fail.dim = ''
                THEN format('%s %s has reached its limit of %s %s',
                            v_fail.carrier_type, v_fail.carrier_id, v_fail.limit_value, v_kind)
                ELSE format('%s %s has reached its limit of %s %s of %s%s',
                            v_fail.carrier_type, v_fail.carrier_id, v_fail.limit_value,
                            v_fail.unit, v_kind,
                            CASE WHEN v_fail.dim <> '' THEN '[' || v_fail.dim || ']' ELSE '' END)
            END,
            DETAIL = jsonb_build_object('carrier_type', v_fail.carrier_type,
                                        'carrier_id',   v_fail.carrier_id,
                                        'kind', v_kind, 'measure', v_fail.measure,
                                        'dimension', v_fail.dim, 'unit', v_fail.unit,
                                        'limit', v_fail.limit_value, 'used', v_fail.used)::text;
    END IF;

    RETURN NULL;   -- AFTER-триггер: возвращаемое значение игнорируется
END $$;
```

**Пять решений этого тела, и каждое — исправленный дефект, а не украшение.**
Все пять найдены разбором, а не предположены; каждое обязано быть закреплено пробой:

| решение | что было бы иначе |
|---|---|
| **два набора вместо разности** | смена измерения (`a100 → h100`) и смена носителя теряли бы возврат: старый разрез не уменьшался бы **никогда**, арендатор видел бы «8 из 8» при нуле живых машин |
| **заведение — отдельным оператором** | изменяющие данные CTE работают на общем снимке и не видят вставок друг друга ⇒ списание не нашло бы только что заведённой строки, и **каждая первая мутация в проекте получала бы 429** |
| **«не сказано» отдельным отказом `KQ002`** | отсутствие величины было бы неотличимо от величины ноль: арендатор не отличит «мне не выделяли» от «я исчерпал», а признак `QUOTA_NOT_PROVISIONED` не производился бы **ни одной веткой** |
| **освобождение ограничено нулём, а не `CHECK`** | расхождение счётчика **отменяло бы удаление ресурса** — отказ продукта по причине учёта там, где арендатор освобождает место |
| **точное измерение бьёт `'*'`, и строка одна** | `IN (dim,'*')` матчит **две** строки умолчаний; предел на `a100` оказывался бы 0 или 8 в зависимости от плана выполнения |

Привязка — из манифеста:

```sql
-- Имя производно от ВИДА, а не от таблицы: у пяти таблиц дерева по два вида
-- (проектная ось и ось вложенности), и имя по таблице дало бы коллизию.
CREATE TRIGGER quota_charge_compute_instance
AFTER INSERT OR DELETE
    OR UPDATE OF eff_vcpu, eff_memory_mib, eff_gpus, eff_gpu_type, status, project_id
ON instances
FOR EACH ROW EXECUTE FUNCTION public.quota_charge('compute.instance');
```

**Набор столбцов срабатывания = меры ∪ измерения ∪ СТОЛБЕЦ НОСИТЕЛЯ ∪ предикаты
`billable.when`.** Он выводится из манифеста, а не выписывается.

**Столбец носителя в наборе — не педантизм, а закрытый дефект.** Перенос ресурса
между проектами есть публичный глагол (`Move` у балансировщика и группы целей,
`UPDATE … SET project_id = $1`). Без носителя в наборе триггер на таком переносе
**не срабатывает вовсе**: прежний проект остаётся занятым выехавшими ресурсами и
упирается в предел, будучи пустым, а новый не платит ни за что. Проверено
прогоном.

**Имя по виду — тоже закрытый дефект.** Таблиц с двумя видами в манифестах пять
(`kacho_vpc.subnets`, `route_tables`, `security_groups`, `kacho_nlb.listeners`,
`repository_configs`). Лучший исход коллизии — падение накатки; худший — имена
разошлись случайно, и **порядок срабатывания** (в Postgres — алфавитный по имени)
оказался обратным нужному.

**Порядок взятия блокировок объявляется, а не получается.** Действующая миграция
дерева несёт **явное** решение: ось вложенности заряжается прежде проектной, ради
дедлоков. Здесь оно сохраняется: имя триггера вложенного вида сортируется раньше,
а внутри одного вида строки берутся `ORDER BY measure, dimension` — детерминированный
порядок на всех писателях.

Следствие, названное честно: включение биллинга **расширяет** набор срабатывания
(добавляется `status`) и требует новой миграции по каждому домену. `CREATE TRIGGER`
берёт `ACCESS EXCLUSIVE` на горячей таблице — разово, но не бесплатно и не
безболезненно.

### 8.3.1 Цена триггера — ИЗМЕРЕНА, а не предположена

Замер на одной прогретой посадке, по 20 000 строк в обеих таблицах, пределы
недостижимы, 8 конкурентных писателей **в один проект**, два повтора:

| | tps | средняя задержка |
|---|---:|---:|
| без триггера | 1366 / 680 | 5.9 / 11.8 мс |
| **с триггером** | **191 / 192** | **41.9 / 41.6 мс** |

Массовая вставка 3000 строк одним оператором: **74 мс → 995 мс (13×)**.

**Что это значит.** Величина без триггера шумит, с триггером устойчива — значит
предмет здесь **ожидание блокировки**, а не счёт. Потолок ~**192 записи в секунду
на один проект** и ~42 мс, и он от нагрузки не растёт. При 64 проектах разницы
почти нет — средняя по платформе этот потолок **скрывает**, поэтому мерить надо
раздельно: «все в один носитель» и «размазано по носителям».

**Следствие для проектирования, а не только для эксплуатации:** строка учёта есть
**точка сериализации** всех писателей одного носителя, и мер на создание четыре, а
не одна. Порог нагрузочной пробы, уже записанный в дереве для nlb (запись p99 ≤ 500 мс
при 500 RPS), в один проект в этот потолок **не помещается**.

**Отсюда обязательное:** метрика **ожидания блокировки**, а не только отказов
(§15); бюджет задержки записи в приёмке; и повторный замер после каждой правки
функции — переустройство проверки требует повторной инъекции, а переустройство
горячего пути требует повторного замера.

### 8.4 Проверка столбца — в самой миграции, а не только на старте

Проверяются **четыре** столбца вида, а не один: мера · носитель · зеркало аккаунта ·
измерение. Опечатка в каждом даёт свой тихий исход, и худший — не в мере:

| столбец | что даёт опечатка |
|---|---|
| `value_column` | `NULL` → списание нулём: **молчаливый недобор** |
| **`carrier_column`** | `carrier_id = ''` → **все проекты платформы схлопываются в один счётчик**: потребление одного арендатора выбирает потолок другого |
| `account_column` | строка невидима аккаунтной дельте (§8.1.1) |
| `dimension_column` | все разрезы схлопываются в один |

```sql
DO $$
DECLARE
    v_col   record;
BEGIN
    FOR v_col IN
        SELECT * FROM (VALUES
            ('public','instances','eff_vcpu',      'numeric'),
            ('public','instances','eff_gpu_type',  'any'),
            ('public','instances','project_id',    'any')
        ) AS t(sch, tbl, col, kindof)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns c
             WHERE c.table_schema = v_col.sch AND c.table_name = v_col.tbl
               AND c.column_name  = v_col.col
               AND (v_col.kindof <> 'numeric'
                    OR c.data_type IN ('smallint','integer','bigint',
                                       'numeric','real','double precision'))
        ) THEN
            RAISE EXCEPTION 'манифест объявляет столбец %.%.% — его нет либо тип негоден',
                            v_col.sch, v_col.tbl, v_col.col;
        END IF;
    END LOOP;
END $$;
```

**Годные типы меры — ЦЕЛЫЕ: `smallint`, `integer`, `bigint`, `numeric` со шкалой 0.**
`real`, `double precision` и `numeric` со шкалой больше нуля **отвергаются по
имени**, и это решение, а не забывчивость:

| почему не дробные | |
|---|---|
| арифметика | `(v_new ->> col)::bigint` на значении `1.5` даёт `invalid input syntax`, то есть **каждая мутация арендатора** роняется сырой ошибкой Postgres, не попадающей в перечень §9 → `INTERNAL` |
| существо | дробная мера не складывается без правила округления, а правило округления **в учёте** — второй словарь: у денег оно уже есть и объявлено (`HALF_UP`, §12.1), второе рядом разойдётся с первым |
| измерено | в дереве дробных столбцов-кандидатов нет: `eff_vcpu integer`, `eff_memory_mib bigint`, `eff_gpus integer`, `size_bytes bigint` |

`smallint` при этом **обязан** быть в перечне: узкий список (`integer`/`bigint`/
`numeric`) отверг бы законный `addr_type smallint` живой таблицы, а гейт с
ложными находками отключают первым.

**Проверка стоит и на СТАРТЕ, а не только при накатке.** Миграционный блок судит
дерево один раз. Любая позднейшая миграция, дропнувшая или переименовавшая
столбец (прецедент в дереве: откат `0016_instance_redesign.sql` дропает те самые
`eff_*`), оставляет строку справочника указывающей в пустоту — и это снова
молчаливый недобор, которого накатка уже не увидит.

### 8.5 Таблица интервалов (биллинг)

```sql
CREATE TABLE IF NOT EXISTS {{.Schema}}.usage_intervals (
    id           bigserial PRIMARY KEY,
    carrier_type text NOT NULL,
    carrier_id   text NOT NULL,
    account_id   text NOT NULL,
    resource_id  text NOT NULL,          -- координата живёт и после DELETE строки
    sku          text NOT NULL,
    dimension    text NOT NULL DEFAULT '',
    quantity     bigint NOT NULL,
    started_at   timestamptz NOT NULL DEFAULT now(),
    ended_at     timestamptz,            -- NULL = открыт
    shipped_at   timestamptz,
    CONSTRAINT usage_intervals_time_check CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT usage_intervals_qty_check  CHECK (quantity >= 0)
);
CREATE INDEX IF NOT EXISTS usage_intervals_unshipped_idx
    ON {{.Schema}}.usage_intervals (id) WHERE shipped_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS usage_intervals_open_idx
    ON {{.Schema}}.usage_intervals (resource_id, sku, dimension) WHERE ended_at IS NULL;
```

Последний индекс — инвариант «у ресурса не бывает двух открытых интервалов одной
меры»: он держится схемой, а не аккуратностью.

Отгрузка — тем же transactional outbox, что уже работает, с клеймом **по голове
партиции** (партиция = `resource_id`): «открыт» и «закрыт» одного ресурса **не
коммутативны**, наивная конкуренция переставила бы их и оставила интервал вечно
открытым.

Частичный индекс под клейм по голове партиции обязателен и **другой**, чем индекс
неотгруженного:

```sql
CREATE INDEX IF NOT EXISTS usage_intervals_partition_head_idx
    ON {{.Schema}}.usage_intervals ((resource_id), id) WHERE shipped_at IS NULL;
```

Индекс по одному `id` для коррелированного `NOT EXISTS` по партиции недостаточен.

### 8.6 Производитель интервалов — второй сгенерированный триггер

Первая редакция объявляла «один производитель вектора, два потребителя» и
показывала функцию, которая пишет **только** в учёт. То есть у половины биллинга
не было производителя вовсе: `usage_intervals.resource_id` было нечем заполнить,
а предикаты `billable.when` не читались ни одной строкой.

Производитель — **вторая функция того же рендера**, привязанная к той же таблице
и тем же оператором `CREATE TRIGGER`, но с собственным именем и собственным
набором срабатывания. Разделение не косметическое: у квоты и биллинга **разные**
условия (квота считает независимо от состояния, биллинг — по предикату) и разные
последствия отказа.

```sql
CREATE OR REPLACE FUNCTION {{.Schema}}.billing_track() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_kind text := TG_ARGV[0];
    v_id   text;
BEGIN
    v_id := COALESCE(to_jsonb(COALESCE(NEW, OLD)) ->> 'id', '');
    IF v_id = '' THEN
        RAISE EXCEPTION USING ERRCODE = 'KQ003',
            MESSAGE = format('billing: row of %s carries no id', v_kind);
    END IF;

    -- 1. Закрыть ВСЕ открытые интервалы ресурса, чей вектор больше не верен.
    --    Закрываем всегда: и на DELETE, и на UPDATE — новый вектор откроется
    --    ниже. Закрытие идёт ПЕРВЫМ: иначе частичный уникальный индекс
    --    (один открытый интервал на ресурс×SKU×разрез) отвергнет вставку.
    UPDATE {{.Schema}}.usage_intervals
       SET ended_at = now()
     WHERE resource_id = v_id AND ended_at IS NULL;

    IF TG_OP = 'DELETE' THEN
        RETURN NULL;   -- ресурса больше нет: новый вектор не открывается
    END IF;

    -- 2. Открыть интервалы по текущему вектору — только для мер, чей предикат
    --    ставки выполнен. Предикат хранится РАЗОБРАННЫМ (см. ниже), а не как
    --    строка SQL: строка означала бы динамическую сборку запроса из данных.
    INSERT INTO {{.Schema}}.usage_intervals
          (carrier_type, carrier_id, account_id, resource_id,
           sku, dimension, region_id, quantity, started_at)
    SELECT b.carrier_type,
           COALESCE(v_new ->> b.carrier_column, ''),
           COALESCE(v_new ->> NULLIF(b.account_column,''), ''),
           v_id, b.sku,
           COALESCE(v_new ->> NULLIF(b.dimension_column,''), ''),
           COALESCE(v_new ->> NULLIF(b.region_column,''), ''),
           (CASE WHEN b.value_column = '' THEN 1
                 ELSE COALESCE((v_new ->> b.value_column)::bigint, 0) END),
           now()
      FROM {{.Schema}}.billing_measures b
     WHERE b.kind = v_kind
       -- предикат ставки: столбец IN (перечень значений) либо «всегда»
       AND (b.state_column = ''
            OR (v_new ->> b.state_column) = ANY (b.state_values))
       AND (CASE WHEN b.value_column = '' THEN 1
                 ELSE COALESCE((v_new ->> b.value_column)::bigint, 0) END) > 0;

    RETURN NULL;
END $$;
```

**Три решения этой функции:**

| решение | почему не иначе |
|---|---|
| **предикат хранится разобранным** (`state_column` + `state_values`), а не строкой SQL | строка из данных означала бы динамическую сборку запроса — единственный путь к инъекции, которого в схеме квоты нет by construction (`->>` берёт имя ключа **параметром**) |
| **сначала закрыть, потом открыть** | обратный порядок отвергается частичным уникальным индексом «один открытый интервал на ресурс×SKU×разрез» |
| **интервал нулевой величины не открывается** | иначе у каждой машины без ускорителя висел бы вечно открытый интервал `gpu` с количеством ноль |

**Регион приезжает со строки, а не угадывается.** Цена ключуется тройкой
`(sku, dimension, region_id)`; интервал без региона делает выбор цены
невыразимым. Столбец региона объявляется в манифесте (`region_column`), и у
ресурсов, где его нет, регион **резолвится владельцем при отгрузке** из
авторитетного поля — никогда деривацией из имени зоны (`data-integrity.md`
§Placement-coherence: строковая деривация молча возвращает пустую строку).

### 8.6.1 Справочник ставок — вторая половина того же рендера

```sql
CREATE TABLE IF NOT EXISTS {{.Schema}}.billing_measures (
    kind             text NOT NULL,
    measure          text NOT NULL,
    sku              text NOT NULL,
    table_name       text NOT NULL,
    value_column     text NOT NULL DEFAULT '',
    dimension_column text NOT NULL DEFAULT '',
    carrier_type     text NOT NULL,
    carrier_column   text NOT NULL,
    account_column   text NOT NULL DEFAULT '',
    region_column    text NOT NULL DEFAULT '',
    -- Предикат ставки хранится РАЗОБРАННЫМ: столбец + перечень значений.
    -- Строка SQL здесь означала бы сборку запроса из данных — единственный
    -- путь к инъекции, которого в схеме нет by construction.
    state_column     text   NOT NULL DEFAULT '',
    state_values     text[] NOT NULL DEFAULT '{}',
    unit             text NOT NULL,
    PRIMARY KEY (kind, measure)
);
```

### 8.7 Пересчёт — вызываемая функция, а не разовая миграция

В три часа ночи нужен оператор, возвращающий `used` к правде. Обратное заполнение
существует в дереве как **разовая миграция**; здесь оно обязано быть **вызываемым**:

```sql
-- Идемпотентна. Носитель обязателен: пересчёт всей таблицы на живой базе
-- берёт блокировки на всём и потому недопустим как штатное действие.
CREATE OR REPLACE FUNCTION {{.Schema}}.quota_recalculate(
    p_carrier_type text, p_carrier_id text, p_kind text
) RETURNS TABLE (measure text, dimension text, was bigint, now_ bigint) …
```

Наружу — `InternalQuotaService.RecalculateUsage(carrier, kind)` и
`ListUsageContributors(carrier, kind, measure, dimension)`, отдающий строки, из
которых сложилось число (ресурс · разрез · заряд). Без второй поддержка не может
ответить на «8 из 8 GPU, а машин с GPU нет» иначе как доступом к БД.

### 8.8 Величину применяет НАЗВАННЫЙ синхронизатор

Живой синхронизатор величин в дереве существует (`pkg/quota/limitsync.go`,
`pkg/quota/projection.go`) и пишет `limit_value`, `limit_revision`, `synced_at`
**в `project_resource_quotas`** — таблицу с ключом `(carrier_type, carrier_id, kind)`.
Ключ новой таблицы шире на две колонки, поэтому:

1. проекция расширяется до `(carrier_type, carrier_id, kind, measure, dimension)`;
2. **`synced_at` обновляется тем же оператором** — без этого состояние `UNKNOWN`
   (§13) либо не наступает никогда, либо наступает для каждой строки через `T`
   после её заведения и не снимается;
3. дельта переопределений применяется **до** переключения авторитета (см. предикат
   перехода фазы M в §18).

---

## 9. Ошибки: коды, признаки, тон

Тон отказа **уже задан деревом** и здесь не переизобретается. Измерено
(`pkg/quota/refusal.sql.tmpl:66-89`, `services/vpc/internal/apps/kacho/shared/serviceerr/quota.go:44-80`):

| SQLSTATE | gRPC | HTTP | `reason` | текст производителя |
|---|---|---:|---|---|
| `KQ001` | `RESOURCE_EXHAUSTED` | 429 | `QUOTA_EXCEEDED` | `<carrier_type> <carrier_id> has reached its limit of <limit> <kind>` |
| `KQ002` | `FAILED_PRECONDITION` | 400 | `QUOTA_NOT_PROVISIONED` | `<carrier_type> <carrier_id> has no ceiling stated for <kind>` |

`ErrorInfo.domain` — домен **владельца** (`vpc.kacho.cloud`, `compute.kacho.cloud`, …),
потому что отказ производит он. `DETAIL` несёт объект
`{carrier_type, carrier_id, kind, limit, used}`.

### 9.1 Расширение тона под меры — совместимое побайтово

Текст — часть контракта, поэтому мера добавляется **не переписыванием**:

| случай | текст |
|---|---|
| `measure = count` (все 31 сегодняшний вид) | **прежний, побайтово** |
| `measure ≠ count` | `<carrier_type> <carrier_id> has reached its limit of <limit> <unit> of <kind>` |

`DETAIL` дополняется полями `measure`, `dimension`, `unit` — добавление ключей в
объект деталей не ломает читателя, который их не знает.

Новый признак: `QUOTA_EXCEEDED` остаётся; в `ErrorInfo.metadata` приезжают
`measure` и `dimension`, чтобы клиент машинно понял, **какая** ось кончилась, не
разбирая прозу.

### 9.2 Недоступность авторитета — СВОЙ признак, а не «исчерпано»

| SQLSTATE | gRPC | HTTP | `reason` | когда |
|---|---|---:|---|---|
| `KQ003` | `INTERNAL` | 500 | — | строка не несёт носителя: дефект **наш**, не арендатора |
| `40P01` | `ABORTED` | 409 | `TX_DEADLOCK_RETRY` | взаимная блокировка — **повторить транзакцию** |

> **Взаимная блокировка между видами РАЗНЫХ таблиц не устраняется порядком внутри
> триггера — и это надо сказать прямо.** Порядок объявлен внутри вида
> (`ORDER BY measure, dimension`) и между двумя видами одной таблицы (имя
> триггера). Но две транзакции, вставляющие в **разные** таблицы одного проекта
> в **обратном порядке операторов**, берут строки учёта в обратном порядке, и
> триггер об этом решить не может: порядок операторов выбирает прикладной код.
>
> Воспроизведено на живой базе обычными арендаторскими действиями в одном
> проекте. Значит `40P01` — **штатный исход**, обязанный иметь свой код и совет
> «повторить», а не уезжать в `INTERNAL`/500 на законном действии.
| — | `UNAVAILABLE` | 503 | `QUOTA_AUTHORITY_UNAVAILABLE` | снимок величин устарел дольше `T`, политика `DENY` |

**Почему отдельный код, а не 429.** `RESOURCE_EXHAUSTED` (429) советует «освободи
место или подними предел»; `UNAVAILABLE` (503) советует «повтори позже». Это
разные советы, и подменять первым второй значит посылать арендатора чистить
ресурсы там, где чинить нужно нам. Ровно тот же довод, по которому в дереве
разведены `KQ001` и `KQ002`: «строки нет» требует **завести** потолок, «строка
полна» — **поднять** его.

### 9.3 Признаки биллинга

| `reason` | gRPC | HTTP | когда |
|---|---|---:|---|
| `ACCOUNT_RESTRICTED` | `FAILED_PRECONDITION` | 400 | баланс ниже порога: создание запрещено, существующее живёт |
| `ACCOUNT_SUSPENDED` | `FAILED_PRECONDITION` | 400 | льготное окно истекло |
| `PRICE_NOT_PUBLISHED` | `FAILED_PRECONDITION` | 400 | у SKU нет действующей цены — оценщик отказывается, а не начисляет ноль |
| `BUDGET_EXCEEDED` | `FAILED_PRECONDITION` | 400 | бюджет проекта исчерпан (если объявлен как жёсткий) |

`ErrorInfo.domain = "billing.kacho.cloud"`.

**`FAILED_PRECONDITION` — это 400, а не 412.** Край собирается без
`WithErrorHandler`, множество производимых статусов задано библиотекой; кейс,
ожидающий 412, не может покраснеть никогда.

---

## 10. Сервис `quota` — контракт

Пакет `kacho.cloud.quota.v1`, REST-префикс `/quota/v1`. Идентификаторы:
`lim-<crockford>` (существует), новые префиксы регистрируются в
`ids.KnownHyphenPrefixes()`.

### 10.0 Быстрый старт — четыре величины, без которых запрос не собрать

Первая редакция давала один вызов и **ни одного** из его предусловий. Читатель
не мог отправить даже первый запрос.

| # | что нужно | откуда берётся |
|---|---|---|
| 1 | базовый адрес | внешний край платформы, `https://<edge-host>`; на стенде — адрес, который печатает подъём стенда |
| 2 | токен | `Authorization: Bearer <jwt>`; чеканится единым фасадом личности (`iam`), никогда напрямую у провайдера |
| 3 | `carrierId` | идентификатор проекта из `GET /iam/v1/projects` — сервис квот перечня проектов **не имеет** by construction (§5) |
| 4 | `carrierType` | `project` в 9 случаях из 10; полный перечень — §4 |

```
GET https://<edge-host>/quota/v1/quotas?carrierType=project&carrierId=prj-01H8XQ2M4K7N9P3R
Authorization: Bearer <jwt>
```

### 10.1 Публичная поверхность (арендатор, через край)

```protobuf
// Пакет kacho.cloud.quota.v1 УЖЕ СУЩЕСТВУЕТ, и message Quota в нём тоже
// (proto/kacho/cloud/quota/v1/quota.proto). Расширение АДДИТИВНОЕ: номера 1-7
// принадлежат сданному контракту и не двигаются — переименование или сдвиг
// сломали бы wire-форму у каждого сегодняшнего читателя.
service QuotaService {
  rpc List (ListQuotasRequest) returns (ListQuotasResponse);   // sync
  rpc Get  (GetQuotaRequest)   returns (Quota);                // sync
}

message Quota {
  // --- сдано, номера неприкосновенны ---
  string kind            = 1;   // "compute.instance"
  int64  limit           = 2;   // 0 — законное значение, НЕ «не задано»
  int64  used            = 3;
  kacho.cloud.iam.v1.Limit.Scope source_scope = 4;
  string source_scope_id = 5;
  string carrier_type    = 6;
  string carrier_id      = 7;

  // --- NET-NEW этой фазы ---
  string measure         = 8;   // "vcpu"; "count" у видов без мер
  string dimension       = 9;   // "a100"; "" у меры без разреза
  string unit            = 10;  // "vcpu" | "MiB" | "B" | "item"
  State  state           = 11;

  // Ревизия величины и момент её применения. Без них «поднял предел — не
  // подействовало» неразрешимо: значения совпадают, если администратор выставил
  // то же число, что уже стояло, и отличить «не доехало» от «перебито другой
  // областью» нечем.
  int64  limit_revision  = 12;
  google.protobuf.Timestamp synced_at = 13;

  // Что произойдёт, если авторитет недоступен. Без неё арендатор не может
  // ответить себе на вопрос «создавать или ждать».
  UnknownPolicy unknown_policy = 14;
  google.protobuf.Timestamp unknown_since = 15;   // пусто, кроме state = UNKNOWN

  enum State {
    STATE_UNSPECIFIED = 0;
    ENFORCED = 1;   // предел действует; limit заполнен
    DISABLED = 2;   // объявлено решением: считаем, не отказываем; limit НЕ заполняется
    UNKNOWN  = 3;   // авторитет недоступен — НЕ «безлимит»; limit НЕ заполняется
  }
  enum UnknownPolicy { UNKNOWN_POLICY_UNSPECIFIED = 0; DENY = 1; ALLOW = 2; }
}

message ListQuotasRequest {
  string carrier_type = 1;   // required
  string carrier_id   = 2;   // required
  string kind         = 3;   // фильтр, опционально
  string measure      = 4;   // фильтр, опционально
  int32  page_size    = 5;   // 0 → 50, максимум 1000; вне [0..1000] → INVALID_ARGUMENT
  string page_token   = 6;   // opaque; мусор → INVALID_ARGUMENT
}
message ListQuotasResponse {
  repeated Quota quotas = 1;
  string next_page_token = 2;
}
message GetQuotaRequest {
  string carrier_type = 1; string carrier_id = 2;
  string kind = 3; string measure = 4; string dimension = 5;
}
```

**`List` отдаёт ОБЪЯВЛЕННЫЕ виды, а не только материализованные строки.** Пустой
проект иначе видит `{"quotas": []}` — «квот нет», при том что отказ по ним он
получит на первой же мутации. Виды без строки учёта отдаются с величиной области
`DEFAULT` и `used: 0`.

**Постраничность вводится ИЗМЕНЕНИЕМ КОНТРАКТА, а не добавлением поля** — см. §3.5:
дерево содержит явное решение «постраничности нет намеренно», и оно отзывается с
причиной (меры умножают каталог), а не молча.

### 10.1.1 Полиморфный носитель в параметре — ОТОЗВАН, и это решение дерева, а не вкус

Первая редакция объявляла один RPC с `carrierType`/`carrierId` в запросе. Отозвано
по трём измеренным причинам:

1. **запись каталога прав несёт ровно один тип объекта на метод** — полиморфную
   цель выразить нечем;
2. **типа `identity` в модели прав не существует**: `grep -nE '^type ' fga_model.fga`
   → 33 типа, `identity` среди них нет. Носитель `iam.account` объявлен именно им
   (§6.7) — проверять не против чего;
3. **это уже решали, и решили обратно.** `identity_quota_service.proto` несёт
   `ListIdentityQuotasRequest {}` с объяснением: *полей у запроса нет, и в этом
   всё дело — нечего подставить, потому что нечего прислать*; там же отвергнут
   обходной путь через отношение уровня кластера как **худший**, чем освобождение,
   ибо оно выполнимо подстановочным кортежем.

**Что действует вместо — три RPC, у каждого своя фиксированная цель:**

| RPC | цель Check | как берётся носитель |
|---|---|---|
| `ListProjectQuotas(project_id, …)` | `object_type: project`, `from_request_field: project_id` | из запроса |
| `ListAccountQuotas(account_id, …)` | `object_type: account`, `from_request_field: account_id` | из запроса |
| `ListIdentityQuotas()` | — | **выводится из принципала**; полей у запроса нет, подставлять нечего |

Вложенные носители (`vpc.network`, `loadbalancer.networkLoadBalancers`,
`registry.registries`) читаются `ListProjectQuotas` с фильтром по виду: их
родитель принадлежит проекту, и проверка проекта покрывает их by construction.

Работающий сегодня образец фиксированной цели — `vpc/v1/quota_service.proto`:
`required_relation: "viewer"`, `object_type: "project"`,
`from_request_field: "project_id"`.

**Сегодняшний клиент не ломается ни на байт.** Он не знает полей 8-11 и
продолжает читать 1-7; вид без мер отдаёт `measure = "count"`, а число в `used`
для него то же самое, что и было.

**Путь чтения объединяется, и это ломающее изменение — объявленное.** Сегодня
каждый домен отдаёт свой `GET /<domain>/v1/quotas?projectId=…` (измерено:
`proto/kacho/cloud/vpc/v1/quota_service.proto:37`, и так у шести доменов).
Новый путь один — `/quota/v1/quotas`. Доменные пути остаются **сквозным
проксированием** на фазе M и снимаются на фазе C с резервированием номеров и
объявлением слома в сообщении коммита. Арендатор, ходивший в шесть мест за одним
ответом, ходит в одно.

**`GET /quota/v1/quotas?carrierType=project&carrierId=prj-01H8…`**

```json
{
  "quotas": [
    { "kind": "compute.instance", "measure": "count",  "dimension": "", "unit": "item",
      "limit": 32,  "used": 7,   "sourceScope": "PROJECT", "sourceScopeId": "prj-01H8XQ2M4K7N9P3R",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R", "state": "ENFORCED",
      "limitRevision": "17", "syncedAt": "2026-08-27T09:10:00Z", "unknownPolicy": "DENY" },
    { "kind": "compute.instance", "measure": "vcpu",   "dimension": "", "unit": "vcpu",
      "limit": 128, "used": 96,  "sourceScope": "ACCOUNT", "sourceScopeId": "acc-01H8XQ2M4K7N9P3S",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R", "state": "ENFORCED" },
    { "kind": "compute.instance", "measure": "gpu",    "dimension": "a100", "unit": "gpu",
      "limit": 8,   "used": 8,   "sourceScope": "DEFAULT", "sourceScopeId": "",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R", "state": "ENFORCED" },
    { "kind": "vpc.address", "measure": "count", "dimension": "2", "unit": "item",
      "used": 3,   "sourceScope": "DEFAULT", "sourceScopeId": "",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R",
      "state": "DISABLED", "limitRevision": "0", "syncedAt": "2026-08-27T09:10:00Z" }
  ],
  "nextPageToken": ""
}
```

Отказ по исчерпанию, каким его видит арендатор:

```json
{
  "code": 8,
  "message": "project prj-01H8XQ2M4K7N9P3R has reached its limit of 128 vcpu of compute.instance",
  "details": [{
    "@type": "type.googleapis.com/google.rpc.ErrorInfo",
    "reason": "QUOTA_EXCEEDED",
    "domain": "compute.kacho.cloud",
    "metadata": { "kind": "compute.instance", "measure": "vcpu", "dimension": "",
                  "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R",
                  "limit": "128", "used": "128", "unit": "vcpu",
                  "sourceScope": "ACCOUNT", "sourceScopeId": "acc-01H8XQ2M4K7N9P3S" }
  }]
}
```
HTTP-статус — **429**.

**`sourceScope` в метаданных отвечает на второй вопрос арендатора — «кто может
поднять».** Без него ему нужен ещё один вызов и соединение по пяти полям на
**каждый** отказ. Раскрытие идентификатора аккаунта-родителя принципалу с
проектной привязкой — **осознанное решение**, а не побочный эффект: без него
отказ не восстанавливает следующий шаг. Границы решения: раскрывается
**координата**, не имя и не состав.

### 10.2 Административная поверхность (:9091, `system_admin`)

```protobuf
service InternalLimitService {
  rpc Set    (SetLimitRequest)    returns (operation.Operation);  // async
  rpc Delete (DeleteLimitRequest) returns (operation.Operation);  // async
  rpc List   (ListLimitsRequest)  returns (ListLimitsResponse);   // sync
}

message Limit {
  string id              = 1;   // lim-<crockford>, immutable
  google.protobuf.Timestamp created_at = 2;
  Scope  scope           = 3;   // DEFAULT | ACCOUNT | PROJECT
  string scope_id        = 4;   // '' и ТОЛЬКО '' для DEFAULT (DB CHECK)
  string kind            = 5;
  string measure         = 6;
  string dimension       = 7;   // '*' — умолчание для неназванного значения
  int64  value           = 8;   // 0 законен; отрицательное отвергается
  int64  revision        = 9;   // растёт при смене значения и при отзыве
}
```

**`POST /quota/v1/internal/limits`**

```json
{ "scope": "PROJECT", "scopeId": "prj-01H8XQ2M4K7N9P3R",
  "kind": "compute.instance", "measure": "gpu", "dimension": "a100", "value": 16 }
```

Ответ — `Operation`, как у всякой мутации:

```json
{ "id": "iop-01H8XQ2M4K7N9P3T", "description": "Set limit compute.instance:gpu[a100]",
  "createdAt": "2026-08-27T09:14:00Z", "done": true,
  "metadata": { "@type": "…/SetLimitMetadata", "limitId": "lim-01H8XQ2M4K7N9P3U" },
  "response": { "@type": "…/Limit", "id": "lim-01H8XQ2M4K7N9P3U", "revision": 42 } }
```

Величина на вид, которого нет в каталоге, **отвергается по имени**: предел на
вид, который никто не считает, был бы принят и никогда не применён.

### 10.3 Поверхность владельцев (:9091, mTLS + круг отправителей)

```protobuf
service OwnerSyncService {
  // Дельта величин по монотонной ревизии; включает ОТОЗВАННЫЕ.
  rpc ListEffectiveLimitsChangedSince (ListChangedSinceRequest) returns (ListChangedSinceResponse);
  // Снимок фактического потребления — сходимость проекции.
  rpc ReportUsage (ReportUsageRequest) returns (ReportUsageResponse);
}

message ReportUsageRequest {
  string domain = 1;                       // "compute"
  google.protobuf.Timestamp taken_at = 2;  // часы ВЛАДЕЛЬЦА, для его же сравнений
  repeated UsageRow rows = 3;
}
message UsageRow {
  string carrier_type = 1; string carrier_id = 2; string account_id = 3;
  string kind = 4; string measure = 5; string dimension = 6; int64 used = 7;
}
```

Снимок — единственный способ, которым сервис квот узнаёт о новых носителях:
**ребра `quota → iam` не существует**, перечня проектов у него нет.

---

## 11. Сервис `billing` — контракт

Пакет `kacho.cloud.billing.v1`, REST-префикс `/billing/v1`. Новые префиксы:
`prl-` (версия прайса), `prc-` (строка цены), `ivc-` (счёт), `chg-` (запись
журнала), `bdg-` (бюджет). Регистрируются в `ids.KnownHyphenPrefixes()`.

### 11.1 Публичная поверхность

```protobuf
service BillingService {
  rpc GetAccountSummary (GetAccountSummaryRequest) returns (AccountSummary);   // sync
  rpc ListCharges       (ListChargesRequest)       returns (ListChargesResponse); // sync
  rpc ListInvoices      (ListInvoicesRequest)      returns (ListInvoicesResponse); // sync
  rpc GetInvoice        (GetInvoiceRequest)        returns (Invoice);           // sync
}

service BudgetService {
  rpc Get    (GetBudgetRequest)    returns (Budget);
  rpc List   (ListBudgetsRequest)  returns (ListBudgetsResponse);
  rpc Create (CreateBudgetRequest) returns (operation.Operation);
  rpc Update (UpdateBudgetRequest) returns (operation.Operation);
  rpc Delete (DeleteBudgetRequest) returns (operation.Operation);
}
```

**`GET /billing/v1/accounts/acc-01H8XQ2M4K7N9P3S/summary`**

```json
{
  "accountId": "acc-01H8XQ2M4K7N9P3S",
  "currency": "RUB",
  "state": "ACTIVE",
  "balanceMicros": "1450000000",
  "periodStart": "2026-08-01T00:00:00Z",
  "periodEnd": "2026-09-01T00:00:00Z",
  "periodToDateMicros": "382640000",
  "forecastMicros": "1180000000",
  "restrictedThresholdMicros": "0",
  "graceEndsAt": null
}
```

> **Все денежные величины — целые микроединицы валюты в строке JSON.** `int64` в
> JSON сериализуется строкой (proto3-канон), дробных типов не существует нигде:
> ни в контракте, ни в БД, ни в расчёте. Цена за единицу-час хранится в
> микроединицах, количество — целое, округление **одно**, на границе периода
> начисления, правило объявлено (`HALF_UP`) и является частью контракта.

```protobuf
message Charge {
  string id            = 1;   // chg-<crockford>
  Type   type          = 2;   // CHARGE | CREDIT — иначе возврат неотличим от начисления
  string sku           = 3;
  string dimension     = 4;
  string unit          = 5;   // единица КОЛИЧЕСТВА: "vcpu·h", "B·h", "item·h"
  string resource_id   = 6;   // координата живёт и после удаления ресурса
  string carrier_type  = 7; string carrier_id = 8;
  string region_id     = 9;   // цена ключуется тройкой — без региона она невыразима
  google.protobuf.Timestamp period_start = 10;   // граница часа, UTC
  google.protobuf.Timestamp period_end   = 11;
  int64  quantity            = 12;
  int64  price_per_unit_micros = 13;
  int64  unit_scale          = 14;  // за сколько единиц объявлена цена
  string price_list_id       = 15;  // prl-<...> — версия прайса, по которой считано
  string currency            = 16;
  int64  amount_micros       = 17;
  string corrects_charge_id  = 18;  // непусто только у CREDIT
  string reason              = 19;  // непусто только у CREDIT

  enum Type { TYPE_UNSPECIFIED = 0; CHARGE = 1; CREDIT = 2; }
}
```

**Клиент обязан уметь воспроизвести арифметику своей строки**, и для этого в ней
есть **всё**.

**Порядок операций объявлен, потому что от него зависит, будет ли ответ вообще.**

```
amount_micros = round( quantity::numeric * price_per_unit_micros / unit_scale )   -- HALF_UP
```

Промежуточное вычисляется в **произвольной точности**, и только результат
приводится к целому. Прямой порядок в целых переполняется **на 2.554 ТиБ·месяц**:
`2 407 930 464 829 440 × 4500 = 1.08 × 10^19`, тогда как предел знакового
64-битного — `9.22 × 10^18`. Переполняется **промежуточное**, а не ответ: сам счёт
при этом порядка десяти тысяч рублей, то есть отказ наступает на совершенно
обычном томе.

**Это не противоречит §17.1** («целые микроединицы вместо типа произвольной
точности»): там речь о **хранении и контракте** — там дробная запись допускала бы
два способа выразить одну сумму. Здесь произвольная точность живёт **внутри одного
выражения** и наружу не выходит ни в контракте, ни в схеме. Первая редакция не давала ни `unit_scale`,
ни `region_id`, ни версии прайса — сумму нельзя было проверить ни при каком числе
запросов, а единственный пример со `unit_scale ≠ 1` расходился с прайсом
**в 8.4 раза**.

**`GET /billing/v1/charges?projectId=prj-…&from=2026-08-01&to=2026-08-27&groupBy=sku`**

```json
{
  "charges": [
    { "type": "CHARGE", "sku": "compute.instance.vcpu.hour", "dimension": "", "unit": "vcpu·h",
      "quantity": "2880", "pricePerUnitMicros": "1200", "unitScale": "1",
      "amountMicros": "3456000", "currency": "RUB", "regionId": "reg-ru-central",
      "priceListId": "prl-01H8XQ2M4K7N9P40",
      "periodStart": "2026-08-01T00:00:00Z", "periodEnd": "2026-08-27T00:00:00Z",
      "resourceId": "ins-01H8XQ2M4K7N9P3V",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R" },
    { "type": "CHARGE", "sku": "compute.instance.gpu.hour", "dimension": "a100", "unit": "gpu·h",
      "quantity": "48", "pricePerUnitMicros": "980000", "unitScale": "1",
      "amountMicros": "47040000", "currency": "RUB", "regionId": "reg-ru-central",
      "priceListId": "prl-01H8XQ2M4K7N9P40",
      "periodStart": "2026-08-20T00:00:00Z", "periodEnd": "2026-08-22T00:00:00Z",
      "resourceId": "ins-01H8XQ2M4K7N9P3W",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R" },
    { "type": "CHARGE", "sku": "storage.volume.byte.hour", "dimension": "dt-ssd", "unit": "B·h",
      "quantity": "824633720832", "pricePerUnitMicros": "4500", "unitScale": "1073741824",
      "amountMicros": "3456000", "currency": "RUB", "regionId": "reg-ru-central",
      "priceListId": "prl-01H8XQ2M4K7N9P40",
      "periodStart": "2026-08-01T00:00:00Z", "periodEnd": "2026-08-27T00:00:00Z",
      "resourceId": "vol-01H8XQ2M4K7N9P3X",
      "carrierType": "project", "carrierId": "prj-01H8XQ2M4K7N9P3R" }
  ],
  "totalMicros": "53952000",
  "completeness": "COMPLETE",
  "nextPageToken": "eyJjcmVhdGVkX2F0IjoiMjAyNi0wOC0yN1QwOTowMDowMFoiLCJpZCI6ImNoZy0wMUg4In0="
}
```

> **Проверьте арифметику третьей строки — она сходится:**
> `824 633 720 832 B·h ÷ 1 073 741 824 = 768 ГиБ·ч`, `768 × 4500 = 3 456 000` мкр.
> Итог: `3 456 000 + 47 040 000 + 3 456 000 = 53 952 000`. В первой редакции здесь
> стояло `unitPriceMicros: "0"` и сумма `412 316` — то есть «цена ноль, к оплате
> 412 316», расхождение с опубликованным прайсом **в 8.4 раза**, и итог был
> согласован с неверным слагаемым. Это был единственный пример, на котором
> реализующий мог откалиброваться.

**`POST /billing/v1/budgets`**

```json
{ "projectId": "prj-01H8XQ2M4K7N9P3R", "displayName": "команда-платформа",
  "amountMicros": "5000000000", "period": "MONTH",
  "thresholds": [ {"percent": 50, "action": "NOTIFY"},
                  {"percent": 90, "action": "NOTIFY"},
                  {"percent": 100, "action": "RESTRICT"} ] }
```

`RESTRICT` — жёсткий бюджет: по достижении аккаунт переходит в `RESTRICTED`
(создание запрещено, существующее живёт). Уничтожения ресурсов бюджет **не
производит ни при каком значении** — это отдельное решение владельца аккаунта.

### 11.2 Административная поверхность (:9091, `billing_admin`)

```protobuf
service InternalPriceService {
  rpc PublishPriceList (PublishPriceListRequest) returns (operation.Operation);
  rpc ListPriceLists   (ListPriceListsRequest)   returns (ListPriceListsResponse);
}
service InternalCreditService {
  rpc Grant (GrantCreditRequest) returns (operation.Operation);   // компенсация, начисление
}
```

**`POST /billing/v1/internal/priceLists`**

```json
{
  "currency": "RUB",
  "effectiveFrom": "2026-09-01T00:00:00Z",
  "prices": [
    { "sku": "compute.instance.vcpu.hour",   "dimension": "",      "regionId": "reg-ru-central",
      "pricePerUnitMicros": "1200",    "unitScale": "1" },
    { "sku": "compute.instance.memory.hour", "dimension": "",      "regionId": "reg-ru-central",
      "pricePerUnitMicros": "150",     "unitScale": "1024" },
    { "sku": "compute.instance.gpu.hour",    "dimension": "a100",  "regionId": "reg-ru-central",
      "pricePerUnitMicros": "980000",  "unitScale": "1" },
    { "sku": "storage.volume.byte.hour",     "dimension": "dt-ssd","regionId": "reg-ru-central",
      "pricePerUnitMicros": "4500",    "unitScale": "1073741824" },
    { "sku": "vpc.address.hour",             "dimension": "EXTERNAL","regionId": "reg-ru-central",
      "pricePerUnitMicros": "3000",    "unitScale": "1" }
  ]
}
```

`unitScale` — за сколько единиц учёта объявлена цена (`1073741824` = за ГиБ-час
при учёте в байт-часах). Так цена остаётся целой при любой мелкости единицы, а
округление не размазывается по строкам.

**Прайс задним числом не правится никогда.** Новая цена — новая версия с
`effectiveFrom`; уже начисленное пересчитывается только компенсирующей записью
через `InternalCreditService.Grant`, и она видна арендатору.

### 11.3 Поверхность владельцев (:9091)

```protobuf
service OwnerIngestService {
  rpc ReportIntervals (ReportIntervalsRequest) returns (ReportIntervalsResponse);
}
service OwnerStateService {
  rpc ListAccountStateChangedSince (ListChangedSinceRequest) returns (AccountStateDeltaResponse);
}

message UsageInterval {
  string idempotency_key = 1;  // "<domain>:<resource_id>:<sku>:<dimension>:<started_at>"
  string carrier_type = 2; string carrier_id = 3; string account_id = 4;
  string resource_id  = 5; string sku = 6; string dimension = 7;
  int64  quantity     = 8;
  google.protobuf.Timestamp started_at = 9;
  google.protobuf.Timestamp ended_at   = 10;  // отсутствует ⇒ интервал открыт
}
```

### 11.4 Приёмник интервалов — схема и правило повтора

Первая редакция объявляла `UNIQUE(idempotency_key)` и **схемы приёмника не
давала**. На этом ключе — без `ended_at` — вторая доставка **того же интервала,
теперь закрытого**, отвергалась бы как дубликат: закрытие не доезжает, интервал
остаётся открытым навсегда, и §12 продолжает начислять за удалённый ресурс. То
есть ровно тот исход, который §12 объявляет самым дорогим.

```sql
CREATE TABLE IF NOT EXISTS billing.received_intervals (
    idempotency_key text PRIMARY KEY,   -- <domain>:<resource_id>:<sku>:<dim>:<started_at>
    account_id   text NOT NULL,
    carrier_type text NOT NULL, carrier_id text NOT NULL,
    resource_id  text NOT NULL,
    sku          text NOT NULL, dimension text NOT NULL DEFAULT '',
    region_id    text NOT NULL DEFAULT '',
    quantity     bigint      NOT NULL,
    started_at   timestamptz NOT NULL,
    ended_at     timestamptz,           -- NULL = открыт
    CONSTRAINT received_time_check CHECK (ended_at IS NULL OR ended_at >= started_at)
);
```

**Повтор — идемпотентная ДОЗАПИСЬ, а не отказ:**

```sql
INSERT INTO billing.received_intervals (...) VALUES (...)
ON CONFLICT (idempotency_key) DO UPDATE
   SET ended_at = COALESCE(billing.received_intervals.ended_at, EXCLUDED.ended_at)
 WHERE billing.received_intervals.ended_at IS NULL;   -- закрытое не переоткрывается
```

**`ended_at` В КЛЮЧ НЕ ВХОДИТ намеренно** — иначе идемпотентности не было бы
вовсе. Ключ отвечает на «тот ли это интервал», а не «в том ли он состоянии».
Закрытие есть **уточнение** уже принятого факта, а не второе потребление.

**Это НЕ противоречит «журнал только на дозапись» (§12).** Дозаписной — журнал
**начислений** (`billing.charges`); приёмник интервалов — не журнал, а вход, и
его строка обязана уметь закрыться ровно один раз.

**Ключ целиком приходит от вызывающего**, поэтому против сетевого повтора он
работает, а против недобросовестного отправителя — нет. Второе закрывает §5.1
(отправитель пишет только о видах своего домена), и называть ключ «единственной
защитой» без этой оговорки означает шире, чем есть.

---

## 12. Начисление: время начисляет количество, событие меняет ставку

Ресурс живёт — событий нет, а деньги идут. Поэтому оценщик **не ждёт события,
чтобы начислить**:

1. раз в расчётный период (час) берёт все **открытые** интервалы и начисляет за
   истёкший час;
2. закрытые интервалы начисляет по фактической длительности;
3. режет по границам часа **в UTC и только у себя** — два сервиса, режущие сами,
   разойдутся на секунде.

**Идемпотентность начисления:** `UNIQUE(resource_id, sku, dimension, period_start)`.
Повторный проход — no-op. Журнал — **только на дозапись**: коррекция есть
компенсирующая запись со ссылкой на исходную, никогда `UPDATE` начисления.

**Сходимость без ребра `billing → owner`:** владелец раз в период шлёт перечень
**открытых** интервалов. Биллинг закрывает у себя то, чего в перечне нет
(событие удаления потерялось), и **приостанавливает** начисление, если перечень
от домена не пришёл дольше `T`.

Приостановка, а не продолжение по последнему известному, — осознанный размен:
недоначислить можно доначислить, лишнее списание вернуть дороже. И это же делает
наблюдаемым «репортёр умер».

### 12.0 Журнал начислений — DDL, а не «принцип»

«Только на дозапись» без схемы есть намерение. Схема:

```sql
CREATE TABLE IF NOT EXISTS billing.charges (
    id            text        PRIMARY KEY,          -- chg-<crockford>
    type          text        NOT NULL,             -- CHARGE | CREDIT
    account_id    text        NOT NULL,
    carrier_type  text        NOT NULL,
    carrier_id    text        NOT NULL,
    resource_id   text        NOT NULL DEFAULT '',
    sku           text        NOT NULL,
    dimension     text        NOT NULL DEFAULT '',
    region_id     text        NOT NULL DEFAULT '',
    period_start  timestamptz NOT NULL,
    period_end    timestamptz NOT NULL,
    quantity      bigint      NOT NULL,
    price_per_unit_micros bigint NOT NULL,
    unit_scale    bigint      NOT NULL,
    price_list_id text        NOT NULL DEFAULT '',
    currency      char(3)     NOT NULL,
    amount_micros bigint      NOT NULL,
    corrects_charge_id text   NOT NULL DEFAULT '',
    reason_code   text        NOT NULL DEFAULT '',
    actor         text        NOT NULL DEFAULT '',  -- кто применил полномочие
    late          boolean     NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT charges_type_check  CHECK (type IN ('CHARGE','CREDIT')),
    CONSTRAINT charges_scale_check CHECK (unit_scale > 0),
    CONSTRAINT charges_credit_check
        CHECK (type = 'CHARGE' OR (corrects_charge_id <> '' AND reason_code <> '' AND actor <> ''))
) PARTITION BY RANGE (period_start);

-- Идемпотентность начисления: повторный проход оценщика — no-op.
CREATE UNIQUE INDEX charges_rating_key_idx
    ON billing.charges (resource_id, sku, dimension, period_start) WHERE type = 'CHARGE';

-- Оси чтения РАЗНЫЕ, поэтому индексов два, а не один.
CREATE INDEX charges_carrier_period_idx ON billing.charges (carrier_type, carrier_id, period_start, sku);
CREATE INDEX charges_account_period_idx ON billing.charges (account_id, period_start);
```

| требование | решение |
|---|---|
| **партиционирование по месяцу** | 10 000 машин × 3 SKU × 24 × 30 ≈ **21.6 млн строк в месяц**, ≈263 млн в год. Без секций закрытие периода и выгрузка становятся полным сканом, а срок хранения — недостижимым |
| **срок хранения** | секции старше объявленного срока **отсоединяются**, а не удаляются: журнал денег дозаписной и по `Down` не откатывается (§18) |
| **курсор чтения — по оси фильтра** | фильтр объявлен по `period_start`; курсор по `created_at,id` обслуживался бы **другим** индексом, и вторая ось стала бы пост-фильтром |
| **`groupBy` и курсор не сочетаются** | группировка считается **на закрытом множестве**: либо весь период без курсора, либо страницы строк без группировки. Иначе та же `sku` вернётся на второй странице с другой частичной суммой |

**Интервалы у владельца — не «дозаписные», и это надо знать заранее:** `ended_at`
и `shipped_at` суть предикаты частичных индексов, поэтому закрытие интервала и
отметка отгрузки переписывают индексы (измерено: **0 HOT-обновлений из 2000**).
Секционировать `usage_intervals` по `started_at` и отсоединять отгруженные —
часть фазы B1, а не «когда вырастет».

### 12.1 Минимальная единица тарификации и округление — названы числами

Без них на вопрос «сколько за машину, прожившую 928 секунд» существует **четыре**
взаимоисключающих ответа, и разброс между ними — вчетверо.

| правило | значение |
|---|---|
| минимальной единицы тарификации **нет** | считаем по фактической длительности с точностью до секунды |
| длительность **не округляется** | `quantity = величина_меры × секунды`; SKU назван `.hour` потому, что **цена** объявлена за час, а не потому, что час — минимальная единица |
| округление денег — **одно**, `HALF_UP` | на строке `(ресурс, SKU, разрез, расчётный час)`; сумма периода есть сумма округлённых строк |
| интервал внутри одного часа **начисляется** | оценщик обрабатывает и открытые, и закрытые интервалы; закрытые — по факту, независимо от того, пересекли ли они границу часа |

**Пример, который обязан быть в приёмке дословно.** Машина 4 vCPU создана
`14:37:12Z`, удалена `14:52:40Z` — 928 секунд. Цена 1200 мкр за vCPU-час,
`unit_scale = 1`:

```
quantity      = 4 × 928       = 3712 vcpu·s
amount_micros = 3712 × 1200 / 3600 = 1237.33… → HALF_UP → 1237
```

**Почему не минимальный час.** Минимальная единица есть скрытая цена, о которой
клиент узнаёт постфактум; отсутствие минимума проверяемо арифметикой и потому
спорам не подлежит. Если минимум когда-нибудь понадобится, он объявляется **полем
прайса**, а не поведением оценщика.

### 12.2 Расчётный период: состояние, отсечка, поздняя доставка

Первая редакция не имела периода как объекта — закрывать было нечего, и
«закрытое» ничем не защищалось.

| состояние | что означает | что можно писать |
|---|---|---|
| `OPEN` | период идёт | начисления и коррекции |
| `CLOSING` | отсечка пройдена, ждём поздние доставки (окно `L`) | только начисления с `period_start` внутри периода |
| `CLOSED` | счёт выставлен | **ничего**; ограничение БД, а не дисциплина |

**Поздняя доставка после `CLOSED` идёт отдельной строкой СЛЕДУЮЩЕГО периода** с
`type: CHARGE`, собственным `period_start` из прошлого и признаком `late: true`.
Правило выбрано, а не выведено: переписывать закрытый период значит менять уже
предъявленный документ, а терять данные — недоначислять молча.

**`completeness` в ответе — обязательное поле, а не украшение.** Приостановка
начисления (§12) без него оставляет в детализации **дыру, неотличимую** от
«ресурс был выключен», «интервал потерян» и «доначислим позже»:

```
COMPLETE   — все домены отчитались за весь период
SUSPENDED  — начисление приостановлено, окна перечислены в suspendedWindows[]
BACKFILLED — дыра закрыта поздней доставкой; строки несут late: true
```

Плюс административное чтение `ListRatingGaps(accountId, from, to)` — чтобы
поддержка отвечала на «пропали два часа» одним запросом, а не доступом к
журналам.

### 12.3 Счёт как документ

```protobuf
message Invoice {
  string id           = 1;   // ivc-<crockford>
  string number       = 2;   // человекочитаемый, монотонный в пределах года
  string account_id   = 3;
  string currency     = 4;
  google.protobuf.Timestamp period_start = 5;
  google.protobuf.Timestamp period_end   = 6;
  google.protobuf.Timestamp issued_at    = 7;
  State  state        = 8;
  int64  subtotal_micros = 9;
  int64  total_micros    = 10;
  string completeness    = 11;
  repeated InvoiceLine lines = 12;

  enum State { STATE_UNSPECIFIED = 0; DRAFT = 1; ISSUED = 2; SETTLED = 3; VOID = 4; }
}
```

**Налог, платёжная единица и платежи — ГРАНИЦА, названная вслух, а не молчание.**

| предмет | решение |
|---|---|
| **налог** | `subtotal_micros` — база; налог **не вычисляется** control plane и полем счёта не является. Причина: ставка есть свойство юрисдикции плательщика, а тенантности юрисдикция не принадлежит. Заводится отдельным доменом со своей приёмкой |
| **приведение к платёжной единице** | сумма **периода** округляется в копейки один раз, при выставлении; построчное округление в копейки запрещено — на тысяче строк оно накапливает расхождение, необъяснимое клиенту |
| **валюта** | одна на аккаунт, **неизменяема** после первого начисления; публикация прайса в другой валюте на существующий аккаунт отвергается |
| **платежи** | **вне этого документа**: приёма оплаты, привязки способа платежа и сверки с банком здесь нет ни одного глагола. `InternalCreditService.Grant` — компенсация, **не платёж**; смешивать их в одном журнале значит сделать невозможной сверку кассы |

Последняя строка — **блокирующее следствие для продукта**: пока платежей нет,
отказ `ACCOUNT_RESTRICTED` не восстанавливает следующий шаг клиента (у него нет
кнопки «оплатить»), и время простоя равно времени реакции поддержки. Это записано
долгом D11, а не спрятано.

### 12.4 Коррекция несёт актора, причину и ссылку

```protobuf
message GrantCreditRequest {
  string account_id          = 1;
  int64  amount_micros       = 2;   // > 0
  string corrects_charge_id  = 3;   // обязателен для компенсации начисления
  string reason_code         = 4;   // закрытый перечень
  string reason_text         = 5;
  string idempotency_key     = 6;   // повтор не чеканит деньги дважды
}
```

Актор (`user`/`service_account`, от чьего имени) пишется журналом аудита **на
применение полномочия**, а не только на его выдачу: выданное `billing_admin` видно
в привязках, применённое — нет. Без этого изменение суммы к оплате невозможно ни
подтвердить, ни опровергнуть — сравнивать не с чем.

**«Только на дозапись» держится ролью БД, а не намерением:** у роли, обслуживающей
чтения, нет `UPDATE`/`DELETE` на журнал; пишет отдельная роль. Иначе инвариант —
дисциплина, а `data-integrity.md` требует держать инварианты конструкцией.

**`effective_from` в прошлом отвергается** ограничением: «прайс задним числом не
правится» — иначе запрет объявлен и необеспечен.

---

## 13. Отключение — состояние, а не отсутствие

Три ответа, и они **различимы**:

| ответ чтения | когда | что делает триггер |
|---|---|---|
| `ENFORCED{limit, used}` | мера объявлена `EXACT` | списывает и отказывает по потолку |
| `DISABLED{used}` | мера объявлена `OFF` **решением** | списывает, не отказывает |
| `UNKNOWN` | авторитет недоступен дольше `T` | по объявленной политике: `DENY` (умолчание) либо `ALLOW` **со счётчиком** |

**Различие «выключено» и «недоступно» — не педантизм.** Контроль, который их
путает, превращает постоянную неправильную настройку в штатный режим и не
отказывает ни разу за свою жизнь. `ALLOW` при недоступности законен **только** с
метрикой: «ноль отказов за всё время» обязано быть заметно.

**Свойство, которого сегодня нет: учёт отделён от предела.** `OFF` продолжает
списывать и слать снимок, поэтому потребление видно **до** включения потолка.
Сегодня «включить квоты» означает накатить триггеры вслепую.

Отключение биллинга — тем же переключателем: `billable: false` на мере даёт учёт
без начисления.

---

## 14. Неоплата: четыре состояния счёта

| состояние | что можно | чем вызвано |
|---|---|---|
| `ACTIVE` | всё | — |
| `RESTRICTED` | существующее живёт, **создание запрещено** | баланс ниже порога либо жёсткий бюджет |
| `SUSPENDED` | ресурсы остановлены, данные хранятся | льготное окно истекло |
| `CLOSED` | — | по заявлению либо по истечении срока хранения |

**Проверка платёжеспособности — снимок с ревизией у владельца, а не синхронный
вызов биллинга.** Тот же `ListChangedSince`, что у величин. Причина: состояние
счёта меняется раз в сутки-месяц, а мутаций тысячи в час; синхронная зависимость
превратила бы падение биллинга в остановку облака для **платящих** клиентов.

Устаревший снимок — это «не знаю», и здесь **fail-open** с ограниченным окном:
цена ложного отказа платящему выше цены нескольких часов бесплатного
использования неплательщиком.

**Величина названа числом, а не обещанием числа:**

| величина | значение | почему такая |
|---|---|---|
| период дельты состояния счёта | **60 с** | состояние меняется раз в сутки-месяц; чаще не нужно |
| окно fail-open (`T_state`) | **6 ч** | переживает перекатку и короткий отказ соседа; за это окно неплательщик не успевает построить дорого |
| после `T_state` | **fail-closed** | «не знаю» дольше шести часов есть поломка, а не задержка |
| **холодный старт** (снимка не было НИКОГДА) | **fail-closed** | иначе одновременная раскатка всех владельцев даёт общеплатформенное окно fail-open, неотличимое от штатной работы |

**Мягкий проход обязан быть посчитан, иначе его нет.** §13 требует метрику при
`ALLOW` — и §14 обязан ей подчиняться, а не быть исключением из собственного
правила:

```
billing_state_snapshot_age_seconds{domain}
billing_state_failopen_decisions_total{domain}
```

Без второй «ноль отказов за всю жизнь контроля» неотличимо от исправной работы —
ровно класс, который корпус ловит в чужом коде.

**Ресурсы не удаляются биллингом ни при каком состоянии.** `SUSPENDED`
останавливает, `CLOSED` наступает по заявлению либо по истечении объявленного
срока хранения — и удаление данных арендатора остаётся отдельным, явным
действием с собственной приёмкой.

---

## 15. Наблюдаемость

Минимальный набор, без которого механизм «работает» неотличимо от «мёртв»:

| метрика | почему обязательна |
|---|---|
| `quota_charge_refusals_total{domain,kind,measure,dimension}` | отказы по осям: видно, какая ось кончается у арендаторов |
| `quota_usage_rows{domain,carrier_type}` | ноль строк учёта при живых ресурсах = триггер не привязан |
| `quota_snapshot_divergence{domain,kind,measure}` | расхождение проекции и снимка; **предикат перехода фазы M** |
| `quota_limit_sync_lag_seconds{domain}` | дельта величин отстала — переопределения не доезжают |
| `quota_usage_rows_without_account{domain}` | §8.1.1: зеркало не заполнено ⇒ строка невидима аккаунтной дельте. Обязана сходиться к нулю; не сходится — синхронизатор мёртв |
| `quota_state_unknown_total{domain,policy}` | сколько решений принято при недоступном авторитете |
| `billing_intervals_open{domain}` | открытые интервалы; резкое падение = потерянный репортёр |
| `billing_intervals_unshipped_age_seconds{domain}` | глубина очереди отгрузки |
| `billing_rating_period_lag` | оценщик отстаёт от расчётного периода |
| `billing_charges_total{sku}` / `billing_charge_amount_micros{sku}` | **ноль начислений за всю жизнь** обязано быть заметно |
| `billing_price_missing_total{sku}` | SKU без действующей цены — оценщик отказывается, а не начисляет ноль |
| **`quota_charge_lock_wait_seconds{domain,kind}`** | строка учёта — точка сериализации всех писателей носителя; без гистограммы ожидания замедление записи **не видно ни одной строкой** (§8.3.1: 5.9 → 41.9 мс) |
| **`quota_limit_divergence{domain,kind,measure}`** | расхождение **величин** старой и новой таблиц. `quota_snapshot_divergence` сверяет `used` — он сойдётся идеально, потому что обе считают одни строки; разойдутся **пределы**, и метрика по `used` этого не спросит |
| **`billing_state_snapshot_age_seconds`**, **`billing_state_failopen_decisions_total`** | §14: мягкий проход без счётчика неотличим от исправной работы |

**Сегодня метрик квот в дереве — ноль** (ни счётчика, ни гейджа, ни гистограммы;
вместо них `slog` и два поля курсора, которые никто не собирает). Поэтому §15 —
**DoD фазы E1**, а не пожелание: E1 единственная, про которую сказано «поведение
не меняется ни на байт», то есть безопасная для заведения приборов.

Инцидент-прецедент дерева: в очереди регистраций одного сервиса **ни одна строка
никогда не была доставлена** — 198 отказов, и это было ненаблюдаемо, потому что
синхронная полоса работала. Ровно этот класс закрывают две строки таблицы про
«ноль за всю жизнь».

---

## 16. Безопасность

| требование | как исполняется |
|---|---|
| authN+authZ на обоих слушателях | публичное чтение — на крае (Check уже стоит); админ-поверхности — `system_admin` / `billing_admin` |
| внутренний слушатель приёма от владельцев | mTLS + **непустой** круг законных отправителей (SAN) + **отказ старта** при пустом круге |
| per-RPC Check на слушателе владельцев | **задокументированное исключение** (иначе цикл `iam → quota → iam` с риском взаимной блокировки), по образцу JWKS-маршрута |
| самоописывающийся носитель | связь «проект → аккаунт» фиксируется при первом предъявлении; конфликтующее заявление отвергается с тревогой |
| деньги отделены от ёмкости | отдельный процесс, отдельная БД, отдельное полномочие `billing_admin` (в модели уже есть) |
| `INTERNAL` не эхает `err.Error()` | фиксированный текст; SQLSTATE `KQ00x` маппится, прочее — opaque |
| PII не логируется | коррелировать по `accountId`/`projectId`, никогда по почте плательщика |
| производственный страж старта | см. перечень ниже — **девять** условий, и каждое **меняет исход старта**, а не печатается в самоотчёте |

### 16.1 Страж старта: девять условий, каждое роняет пуск

| # | условие отказа |
|---|---|
| 1 | `sslmode = disable` на соединении с БД |
| 2 | режим не `production` на развёрнутом стенде |
| 3 | mTLS с проверкой клиента выключен на **любом** из двух слушателей |
| 4 | круг законных отправителей **пуст** — считанный **тем же предикатом**, каким его читает транспорт (вырожденное значение из одного разделителя даёт «непусто» стражу и «пусто» проверке) |
| 5 | контроль включён, а удостоверение к соседу не задано (адрес без сертификата — контроль, отказывающий всегда) |
| 6 | мера с измерением без умолчания `"*"` |
| 7 | `quota_measures` / `quota_defaults` расходятся с встроенным манифестом |
| 8 | объявленный столбец (мера · носитель · зеркало · измерение) отсутствует либо негоден по типу |
| 9 | окно fail-open (§14) и политика `UNKNOWN` (§13) не заданы, либо метрика под них не провязана |

Условия 7 и 8 — **на старте, а не только при накатке**: строка справочника,
появившаяся позже миграции, миграционным блоком не перечитывается никем.

**Отдельно про журнал денег.** Он append-only, содержит суммы и координаты
арендаторов и является самой чувствительной таблицей платформы. Его чтение
арендатором — только своя область; чтение оператором — `billing_admin`;
экспорт — отдельная поверхность с собственным решением, в этот документ не
входящая.

---

## 17. Рынок: классы решений, а не имена

**Имён поставщиков в этом разделе нет намеренно.** Норма продукта запрещает
сравнения с чужими облаками в коде и документах, и как довод они пусты: своя ось
— предсказуемость контракта, время до первого успешного вызова, цена
эксплуатации. Ниже — **классы** решений, встречающиеся на рынке учёта и
тарификации, и решение по каждому.

### 17.1 Конвейер тарификации — общий для отрасли

Отрасль сошлась на четырёх звеньях: **счётчик** (сырые события с ключом
идемпотентности) → **оценщик** (условия договора × потребление = сумма) →
**выставление** (счета за период) → **журнал** (неизменяемые записи для
аудитора). Наша конструкция совпадает по составу и расходится в одном: счётчик у
нас **не поток событий, а вектор со строки в транзакции мутации**, потому что
data plane отсутствует, а удаление жёсткое.

| приём рынка | взято / отвергнуто |
|---|---|
| ключ идемпотентности на каждом событии; `UNIQUE` на приёмнике | **взято** — §11.3, единственная защита от «повтор сети = второе потребление» |
| типы агрегации `COUNT` / `SUM` / `UNIQUE COUNT` / `MAX` | **взято частично**: `COUNT` и `SUM` (это и есть меры). `UNIQUE COUNT` и `MAX` — не заводятся: у них нет предмета в control plane без data plane |
| произвольный SQL как определение метрики | **отвергнуто**: определение метрики становится кодом без обзора; наш словарь закрыт — столбец, измерение, единица |
| журнал двойной записи (дебет/кредит) | **взято по существу**: журнал только на дозапись, коррекция — компенсирующая запись. Полноценная двойная запись с планом счетов — не заводится: у control plane нет второй стороны проводки, она у финансовой системы |
| хранение денег в типе произвольной точности | **отвергнуто в пользу целых микроединиц**: `NUMERIC` допускает дробную запись, а дробная запись допускает два способа выразить одну сумму |
| разделение «главная книга» и «витрина клиента» | **взято**: журнал начислений и `AccountSummary` — разные поверхности |
| потоковый приём событий с большой скоростью | **не требуется**: наш источник — мутации control plane, их скорость на порядки ниже |

### 17.2 Учёт пределов — классы

| приём | взято / отвергнуто |
|---|---|
| пределы как защита общей инфраструктуры, а не как продажа | **взято**: предел живёт отдельно от цены; вид может иметь потолок и не иметь цены |
| три уровня специфичности (платформа → организация → проект) | **взято**: `DEFAULT → ACCOUNT → PROJECT`, «не сказано» на уровне — не «безлимит» |
| распределённое допущение через общий кеш/резервирование слотов | **отвергнуто**: заводит синхронную зависимость на пути создания и верит самоописанию; см. §2 Р1 |
| декларативное определение пределов как политики | **взято** и усилено: манифест производит не только политику, но и **исполнение** (триггер) |
| раздельные пределы по разновидностям (тип диска, тип ускорителя) | **взято** как измерение меры, с обязательным умолчанием `"*"` |
| увеличение предела как заявка с рассмотрением | **не в этой фазе**: сегодня величину назначает администратор облака; заявка — отдельная поверхность |

### 17.3 Управление расходами (FinOps) — что берём

| приём | решение |
|---|---|
| **showback перед chargeback**: сначала показать, потом списывать | **взято и встроено**: `billable` без включённого начисления даёт ровно showback; это же снимает риск включить деньги вслепую |
| бюджеты с порогами и действиями | **взято**: §11.1, `NOTIFY` / `RESTRICT`; уничтожения ресурсов бюджет не производит |
| разбор расходов по меткам ресурсов | **не в этой фазе** и названо долгом: метки мутабельны, а разбор по мутабельному ключу даёт историю, которая меняется задним числом |
| прогноз расхода до конца периода | **взято**: `forecastMicros` в сводке — иначе бюджет узнаётся по факту исчерпания |
| «40 % расходов без владельца» — обязательность разметки | **закрыто иначе**: носитель обязателен by construction (`carrier`), безвладельческой строки не существует |

---

## 18. Порядок работ: фазы, DoD, предикаты перехода

Каждая фаза **production-complete сама по себе**: реализована, покрыта, безопасна
в своих границах. «Потом допилим» — не декомпозиция.

### Фаза E1 — манифест и генератор (без поведения)

| DoD | предикат |
|---|---|
| манифест у **всех семи** доменов, включая пустой у geo | `ls services/*/quota.yaml \| wc -l` → 7 |
| генератор рендерит таблицы, функцию, справочник; повторный прогон — ноль файлов | прогон дважды, второй пишет 0 |
| гейт: грантуемый тип модели прав либо в манифесте, либо в ведомости исключений с причиной | ведомость самоистекает |
| гейт формы манифеста (столбец существует и числовой, `"*"` у измеряемой меры, `billable` задан явно) | инъекция в обе стороны по каждому правилу |

| **метрики §15 провязаны** | это единственная фаза, где поведение не меняется, — приборы заводятся здесь |
| рёбра `<семь> → quota` и `<семь> → billing` внесены в `polyrepo.md`, с iam снято звание чистого листа | §5 |

**Поведение не меняется ни на байт.** Сегодняшний учёт продолжает работать.

**Единица выкатки — релиз, а не сервис.** Все сервисы едут одним зонтичным
релизом; `<svc>.enabled` **выключает** сервис, а не удерживает его версию.
Частичная выкатка = ручной пин тегов и тот же единственный `helm upgrade`.

**Окно «старый бинарь / новая схема» существует структурно в каждой выкатке.**
Миграции идут `initContainer`-ом нового пода, старый под обслуживает трафик, пока
новый не станет Ready. Значит **старый бинарь какое-то время пишет в таблицу с уже
накаченным новым триггером**. Отсюда требование к каждой фазе: новый триггер
обязан быть безвреден для старого бинаря — иначе сервис, чей образ не трогали,
встаёт целиком.

### Фаза E2 — параллельный учёт (наблюдение)

| DoD | предикат |
|---|---|
| `quota_usage` заполняется новым триггером **рядом** с сегодняшним `project_resource_quotas` | обе таблицы непусты |
| отказ по-прежнему производит **старый** механизм | тон отказа не изменился побайтово |
| метрика расхождения двух счётчиков | `quota_snapshot_divergence` |
| снимок уезжает в сервис квот, чтение арендатором работает | ответ `ListQuotas` непуст |

**Предикаты перехода к M — ДВА, и второй важнее первого:**

1. `quota_snapshot_divergence` — **ноль** по всем видам и мерам за объявленный
   период наблюдения. Не «почти ноль».
2. **`quota_limit_divergence` — ноль**: каждое переопределение области `ACCOUNT`
   и `PROJECT`, живущее в старой таблице, **воспроизведено** в новой.

Без второго переход выглядит безупречным и ломает самых крупных клиентов в момент
переключения: `used` сойдётся идеально (обе таблицы считают одни строки), а
предел вернётся к умолчанию, засеянному при первой мутации. Наблюдалось бы как
`429` при пределе, который никто не понижал, и без единой записи в журнале
администратора.

### Фаза M — переключение авторитета

| DoD | предикат |
|---|---|
| отказ производит новый триггер; тон для `measure=count` побайтово прежний | сравнение текстов |
| `Admit` и порт `QuotaGuard` сняты из use-case всех доменов | `git grep -c 'QuotaGuard' -- services/ ':!*_test.go'` → 0 |
| шесть публичных `quota_service.proto` заменены одним | `git ls-files proto \| grep -c quota_service.proto` → 1 |
| отказ по мере несёт `measure`/`dimension` в `metadata` | e2e-кейс |

### Фаза C — снятие старого

| DoD | предикат |
|---|---|
| `project_resource_quotas`, `nested_quota_defaults`, `quota_sync_cursor` дропнуты миграциями | таблиц нет |
| `pkg/quota/quotaiam` и **три** раскладки учёта сняты (§3.2) | `git grep -l -ie quota -- services/ ':!*_test.go' \| wc -l` → 7 (по манифесту на домен) |
| величины переехали из `kacho_iam.limits` в сервис квот | `iam` — клиент как все |

### Фаза B1 — биллинг: учёт без денег

| DoD | предикат |
|---|---|
| `usage_intervals` заполняются тем же триггером; отгрузка работает | очередь дренится, `billing_intervals_open` > 0 |
| прайс публикуется, но **начисление выключено** | `billing_charges_total` = 0 **и это объявлено**, а не случайно |
| арендатор видит потребление (showback) | `ListCharges` с нулевыми суммами |

> [!warning] Политика отката названа ПО КАЖДОЙ таблице — иначе штатный откат уничтожает деньги
> В дереве `Down` есть почти у всех миграций, но в развёртывании он **не
> вызывается ниоткуда**; документированный путь восстановления — снос схемы
> целиком. Для `quota_usage` это переживаемо: `used` восстановим пересчётом
> (§8.7). Для `usage_intervals` — **нет**: удаление ресурса жёсткое, `deleted_at`
> нет ни у одного сервиса, и интервал есть единственная запись о том, что ресурс
> жил.
>
> | таблица | `Down` | восстановление |
> |---|---|---|
> | `quota_measures`, `quota_defaults` | дроп разрешён | рендер из манифеста |
> | `quota_usage` | дроп разрешён | `quota_recalculate` |
> | **`usage_intervals`** | **`Down` ЗАПРЕЩЁН** | невосстановимо |
> | журнал начислений | **`Down` ЗАПРЕЩЁН** | невосстановимо |
>
> Штатный откат на фазах B — **откат образов при сохранённой схеме**. Это значит,
> что новый триггер продолжает работать под старым бинарём, и требование
> совместимости из фазы E1 действует на всех фазах.

### Фаза B2 — начисление и счёт

| DoD | предикат |
|---|---|
| оценщик начисляет почасово, идемпотентно | повторный проход даёт ноль новых записей |
| журнал только на дозапись; коррекция — компенсирующая запись | попытка `UPDATE` начисления отвергается |
| состояние счёта доезжает до владельцев дельтой | `ACCOUNT_RESTRICTED` наблюдаем в e2e |
| бюджеты с порогами | e2e: 100 % → `RESTRICTED` |

---

## 19. Сводка гейтов

| # | гейт | что держит | доказывается |
|---|---|---|---|
| G1 | форма манифеста | столбец существует и числовой; `"*"` у измеряемой меры; `billable` задан; `expr` xor `column` | инъекция по каждому правилу |
| G2 | полнота каталога | грантуемый тип либо в манифесте, либо в ведомости исключений с причиной | ведомость самоистекает |
| G3 | рендер идемпотентен | повторный прогон — ноль файлов; ноль целей — отказ | прогон дважды |
| G4 | применённая миграция неизменна | реестр хешей; имя производно от версии манифеста | правка старого файла → красное |
| G5 | шаблон **верен** | поведенческая проба на живой БД: потолок отказывает, предел пропускает, дельта знаковая, `DELETE` возвращает | RED→GREEN |
| G6 | тон отказа един | текст, SQLSTATE и признаки — из одного производителя; для `count` побайтово прежний | сравнение текстов шести доменов |
| G7 | ресурс только пишет | в пути мутации объявленной таблицы нет обращений к учёту | обход дерева |
| G8 | идемпотентность начисления | `UNIQUE(resource_id, sku, dimension, period_start)` | повторная доставка → ноль новых |
| G9 | у ресурса не бывает двух открытых интервалов одной меры | частичный уникальный индекс | конкурентная проба |
| G10 | цена есть у каждого тарифицируемого SKU | оценщик отказывается, а не начисляет ноль | старт с неполным прайсом → отказ |
| G11 | круг отправителей непуст | отказ старта | пустое значение и вырожденное (`","`) |
| G12 | «ноль за всю жизнь» заметно | метрики §15 | синтетическая остановка репортёра |
| G13 | значения `defaults` **производимы** столбцом измерения | тип столбца против ключей умолчаний | `smallint` со строковыми ключами — находка; `disk_type_id text` — молчание |
| G14 | мера объявлена на **целом** столбце | `real`/`double`/`numeric(p,s>0)` отвергаются по имени | дробный столбец — находка; `smallint` — молчание |
| G15 | перечень метрик §15 провязан у **каждого** домена | обход дерева | домен без метрики — находка |
| G16 | `effective_from` не в прошлом | ограничение БД | публикация задним числом — отказ |
| G17 | журнал начислений недоступен на `UPDATE`/`DELETE` роли чтения | права роли | попытка правки — отказ БД, а не дисциплина |

---

## 20. Открытый долг — с числом и предикатом, а не намерением

| # | предмет | предикат снятия |
|---|---|---|
| D1 | `registry.storage.byte.hour` не заводится: control plane не знает байтов блобов | появился репортёр хранилища, отдающий размер по репозиторию |
| D2 | носитель `registry.repositories` доходит до проекта соединением; проектный носитель требует зеркала либо представления | перемерено и выбрано до фазы E2 |
| ~~D3~~ | **ЗАКРЫТ замером**: схема compute — `public` (`pkg/quota/refusal.go`, восемь миграций с `search_path TO public`); столбцы носителей iam измерены (§6.7) | — |
| D4 | разбор расходов по меткам ресурсов не заводится (метки мутабельны, история менялась бы задним числом) | принято решение о неизменяемой оси разметки |
| D5 | заявка на повышение предела как поверхность продукта | отдельная приёмка |
| D6 | `targetGroups → targets`: риск «слишком много целей в одной группе» открыт | `nlb_target` стал грантуемым типом модели прав |
| D7 | сегодняшний генератор пишет в фиксированное имя миграции — перезапись применённого | реестр хешей (G4) заведён |
| D8 | правило-страж в профиле развёртывания iam стережёт предмет, которого в продукте не существует, и адресуется не по тому виду идентичности, какой продукт использует; координаты и разбор — в задаче, не здесь | правило снято либо переписано на существующий предмет |
| D9 | `iam.accessBinding` не объявлен: `kacho_iam.access_bindings` не несёт столбца тенантности (измерено, ноль вхождений) | выбран исход — зеркало на строке либо расширение формы манифеста на носителя через соединение внутри своей БД |
| D10 | зеркало аккаунта в строке учёта заполняет синхронизатор; до его первого прохода действует величина области `DEFAULT` | `quota_usage_rows_without_account` сходится к нулю на всех доменах |

| D11 | платежей нет ни одного глагола: отказ по неоплате не восстанавливает следующий шаг клиента | заведена поверхность приёма оплаты со своей приёмкой |
| D12 | токены видов несогласованы по числу (`storage.volumes` против `compute.instance`) — унаследовано от каталога дерева | принято решение о переименовании **с объявленным сломом** либо о сохранении как есть, записанное явно |
| D13 | у бюджета есть пороги предупреждения, у квоты нет: клиент узнаёт о пределе только отказом | заведено предупреждение по квоте либо записано, почему предметы разные |
| D14 | **держателя у гейта G5 (поведенческая проба на живой базе) нет** — а он единственный ловит весь класс дефектов §21.2 | проба заведена и прогоняется по КАЖДОМУ владельцу, а не по одному «эталонному» |

**Долг назван числом и предикатом.** Строка отсюда **не считается действующей
нормой**: ссылаться на неё как на правило — то же, что ссылаться на
несуществующий гейт.


---

## 21. Разбор ролями: что нашли и что изменилось

Документ прогнан через **десять** ролей, каждая — с **пустым контекстом**: роль
получала только сам документ, дерево и своё задание. Пустой контекст здесь условие
годности, а не аккуратность: рецензент, знающий наши обоснования, изображает не
клиента, а нас.

**Задание каждой роли требовало находку в форме ОТКАЗА**, а не пожелания, и
запрещало «мне непривычно» и сравнения с чужими облаками. Разделял один вопрос:
назови второе место, с которым это расходится, **либо** цену в шагах, времени или
деньгах.

### 21.1 Что дал разбор — числом

| роль | блокирующих | из них подтверждено **прогоном**, а не чтением |
|---|---:|---|
| архитектор | 5 | SQL прогнан на живой базе; воспроизведён отказ первой мутации |
| DevOps/SRE | 9 | SQL прогнан; **измерена цена триггера** (§8.3.1) |
| DBA / данные | 5 | SQL прогнан; воспроизведены дедлок, переполнение, пустой носитель |
| безопасность | 5 | предикаты по дереву |
| CTO | 9 | 19 замеров, из них 5 не сошлись |
| QA / гейты | 13 | предикаты по дереву + 27 сценариев приёмки |
| продакт | 22 | по трём признакам находки |
| финансовый оператор | 11 | арифметика примеров |
| разработчик-клиент | 12 | арифметика и подсчёт шагов |
| поддержка / ops | 6 | разбор десяти типовых тикетов |

**Три роли независимо прогнали SQL на поднятом Postgres** — и именно они нашли то,
чего чтение не находит ни при какой внимательности.

### 21.2 Дефекты, которые нашёл только ПРОГОН

| дефект | что было бы у арендатора |
|---|---|
| заведение и списание в одном операторе (изменяющие CTE не видят вставок друг друга) | **первая мутация в каждом проекте** отвергалась бы как «квота исчерпана» при `used = 0`, и состояние не сходилось бы никогда |
| `quota_defaults` не существует, а `CREATE FUNCTION` проходит успешно | миграция зелёная, `INTERNAL`/500 на первой записи **любого** ресурса **любого** домена |
| `d` вне области видимости `RAISE` | отказ квоты приходил бы как `42P01` → фиксированный `INTERNAL`, признак терялся целиком |
| смена измерения `a100 → h100` разностью «NEW − OLD» | старый разрез не уменьшался бы **никогда**; новый заряжался бы нулём — **обход потолка через Update** |
| столбец носителя вне набора срабатывания | перенос ресурса между проектами не срабатывал бы вовсе: прежний проект занят навсегда, новый не платит |
| `addr_type` — `smallint`, ключи объявлены строками | **каждый** внешний адрес отвергался бы «по пределу ноль» |
| `CHECK (used >= 0)` без пола | `DELETE` арендатора отменялся бы **по причине учёта** |
| `IN (dim, '*')` матчит две строки умолчаний | предел `a100` был бы 0 или 8 **в зависимости от плана выполнения** |
| прямой порядок `quantity × price` в целых | переполнение `int64` на **2.55 ТиБ·месяц** — обычном томе |
| две транзакции, вставляющие в разные таблицы в обратном порядке | `40P01` → `INTERNAL`/500 на законном действии |
| пустой носитель отбрасывался условием | «создано 3 · строк учёта 0 · отказов 0» — ресурсы не считаются, и заметить нечем |
| `to_jsonb` восемь раз в теле | 30 сериализаций широкой строки на одну мутацию — механизм за измеренными 42 мс |

### 21.3 Что изменилось в конструкции, а не в тексте

| было | стало | чья находка |
|---|---|---|
| задокументированное исключение из per-RPC Check на слушателе владельцев | **локальная авторизация по сертификату**: отправитель пишет только о видах своего домена | безопасность |
| «связь проект→аккаунт фиксируется при первом предъявлении» | **сверка**, а не фиксация: TOFU защищал не тот предмет и бил по жертве | безопасность |
| один RPC с `carrierType`/`carrierId` в параметре | **три RPC с фиксированной целью**; полиморфная цель отозвана — её уже отвергло дерево | архитектор |
| «`iam → quota` не заводится, иначе цикл» | ребро **зарегистрировано**, с iam снято звание листа; довод о взаимной блокировке **признан неверным** (оба вызова вне пути запроса) | архитектор |
| у биллинга не было производителя | **второй сгенерированный триггер** `billing_track()` + DDL журнала с секциями | DBA, QA |
| «прайс задним числом не правится» — словами | **ограничением**: `effective_from` в прошлом отвергается; журнал дозаписной **ролью БД**, а не намерением | безопасность, финансы |
| период не существовал как объект | **три состояния**, отсечка, правило поздней доставки, `completeness` в ответе | финансы, поддержка |
| минимальная единица тарификации не названа | **нет минимума**, счёт по секундам, одно округление — с примером на 928 секунд | финансы |
| строка начисления не воспроизводилась клиентом | `resourceId`, границы периода, `unitScale`, `regionId`, версия прайса, тип записи | разработчик, финансы |
| окно fail-open «объявляется числом» | **6 часов**, холодный старт — fail-closed, два счётчика | безопасность |
| `DISABLED` показывался вместе с `limit` | при `DISABLED`/`UNKNOWN` предел **не заполняется** | разработчик, продакт |
| у поддержки не было роли | отдельное полномочие **только на чтение** квот и начислений любого носителя | поддержка |
| пересчёта не существовало | `RecalculateUsage` + `ListUsageContributors` — вызываемые, а не разовая миграция | поддержка, SRE |

### 21.4 Что осталось спорным и решено ЯВНО

| вопрос | решение | цена |
|---|---|---|
| платежи | **вне охвата документа**; названо границей, а не молчанием | отказ `ACCOUNT_RESTRICTED` не восстанавливает следующий шаг клиента, пока платежей нет — **долг D11** |
| налог | не вычисляется control plane: ставка есть свойство юрисдикции плательщика | счёт несёт базу, не итог с налогом |
| разбор расходов по меткам | не заводится: метки мутабельны, история менялась бы задним числом | **долг D4** |
| множественное и единственное число в токенах видов (`storage.volumes` против `compute.instance`) | **не трогаем**: токены унаследованы от каталога дерева и являются контрактом | несогласованность остаётся видимой — **долг D12** |
| предупреждение о приближении к пределу | у бюджета есть, у квоты нет | **долг D13**: разные предметы, но клиенту это не объяснить |

### 21.5 Чего разбор НЕ закрыл

Названо, чтобы не читалось шире, чем есть:

- **ни одна проба не написана.** Все находки закрыты **в тексте**; поведенческая
  проба на живой базе (гейт G5) остаётся единственным, что доказывает верность
  шаблона, и её держателя сегодня нет;
- **прогоны шли на синтетических таблицах**, повторяющих типы столбцов дерева, а
  не против настоящих схем сервисов;
- **три роли из десяти читали более раннюю редакцию** и часть их находок закрылась
  между чтениями; в §21.2 такие помечены как закрытые, но перепроверять их обязан
  тот, кто будет реализовывать;
- **число ролей — не мера полноты.** Десять направлений покрывают тех, кто
  соприкасается с системой сегодня; появится одиннадцатое (аудитор, партнёр,
  посредник) — разбор придётся повторить по его оси.
