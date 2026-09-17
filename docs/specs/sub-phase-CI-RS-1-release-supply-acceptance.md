# CI-RS-1 — поставка готового дерева модуля и проверка его потребителей

> **Статус: DRAFT.** Дата: 2026-09-17. Автор: release-supply-architect.
> Независимого одобрения этой редакции нет. Статическая форма остаётся DRAFT;
> действительное одобрение требует внешнего события на точный SHA-256.
> Задачи: [#2588](https://github.com/PRO-Robotech/kacho/issues/2588),
> [#2258](https://github.com/PRO-Robotech/kacho/issues/2258),
> [#2230](https://github.com/PRO-Robotech/kacho/issues/2230).

## Предмет и граница

Оператор передаёт **уже собранное дерево** одного Go-модуля, точный receiving
repository, версию и объявления потребителей. Производитель сначала доказывает
годность кандидата, доставляет его через защищённый PR, затем отдельно выпускает
версию только из принятого main. Потребитель получает pin после проверки
опубликованного module archive. Публикация вручную не является шагом этого маршрута.

Это новый контракт поставки и две новые проверки существующего контура.
Принятые subjects, история и сценарии KAN-RELEASE-1 не изменяются: его §1.5 и §8
объясняют происхождение #2258/#2230, но исторические пути службы не становятся
требованием вернуть снятую зависимость Kaname → Kachō. Политика версий остаётся
у `kacho/docs/architecture/release-and-versioning.md`; выбор номера не выводится
из факта успешной сборки.

Вход не зависит от работоспособности foundation exporter. Сведение всех tools
по #2661, чужие corelib lanes и решение о доме subscription сюда не входят.
Выпуск CI-NP-1 и CI-DT-1 допускается только после их собственных независимых
проверок. CI-DT-1 сохраняет runtime semantics и имеет один изменённый generated
Go-файл; канонический общий NP-инструмент живёт в corelib.

## Слова и наблюдаемые исходы

`input` — запечатанный снимок готового дерева; `candidate` — итоговое дерево после
явно объявленного сохранения receiving-owned файлов; `base` — прочитанный main
принимающего repo. Манифест содержит base SHA, input digest, полный перечень
путей с content/mode digests и явные операции сохранения/замены/снятия. `.git`
не является содержимым; подмодули, выходящие за корень ссылки и неразбираемые
типы входа отвергаются. Receiving-owned `.github/**` сохраняется дословно,
включая режимы файлов; этот маршрут не редактирует правила защиты main.

Отсутствующий receiving файл без явного решения — ошибка, не неявное удаление.
`preserve` копирует файл из base; `remove` допускается лишь для явно названного
source-owned файла и не отменяет package floor. Изменение receiving-owned файла
или его классификация как source-owned этим входом запрещены.

Положительный результат проверки — `GREEN`, отказ по доказанному нарушению —
`RED`, недоступный источник или несозданное окружение — `NOT_EXECUTED`. Любой
исход кроме GREEN закрывает зависимые мутации. Некорректный CLI-вызов отдельно
получает usage error. Итог называет repository, SHA/digests, версию, фактическую
стадию и непустые census; частично опубликованное никогда не называется «ничего
не создано». Проекция CLI и exit codes фиксируется в design, не в историческом
контракте KAN-RELEASE-1.

Проверки пакетов относятся к **реальному Go module zip**, произведённому из
candidate revision по правилам Go. Локальный незакоммиченный файл, соседний
checkout, `go.work` или `replace` не восполняют отсутствующий пакет архива.
Поддерживаются ровно два типа объявления: `repository` именует actual consumer
repo, точную revision, module roots и build contexts; `external-program` именует
отслеживаемую исходную программу внешнего compatibility probe и её source
revision. Второй тип не объявляется существующим downstream продуктом. Census
в обоих случаях выводится из импортов tracked Go sources, включая тесты
и файлы с build constraints. Импорт считается относительно longest matching
module path, а не по общему строковому префиксу организации. Для каждого
declared consumer обоих типов требуется хотя бы один импорт выпускаемого модуля.
Для corelib actual consumers — Kachō и Kaname. Для старого Kachō publisher,
у которого Kaname больше не потребляет Kachō, default declaration — committed
external reference-consumer program на основе существующего П8 witness
`pkg/api/kacho/cloud/reference`. Это узкий явно названный compatibility probe,
а не утверждение о полноте потребителей всего API Kachō. Он и П8 используют
одну исходную программу; снятый iam module не возвращается.

## Сценарии

### CI-RS-01 — холостой прогон

**Given** годные input, base, floor и consumers. **When** оператор запускает
производителя без явного ключа выполнения. **Then** он получает план и census;
remote refs, PR, release и локальные refs receiving repo не меняются. Создание
временного изолированного кандидата не является разрешением публикации.

### CI-RS-02 — точное подтверждение адресата

**Given** тот же положительный вход. **When** указан ключ выполнения, но repo
confirmation отсутствует или отличается от канонического `PRO-Robotech/corelib`.
**Then** отказ до внешних мутаций. **And** точное подтверждение вместе с теми же
проверенными аргументами разрешает только явно выбранную стадию этого repo;
подмена origin или forge endpoint не перенаправляет её в другой repo.

### CI-RS-03 — отсутствие receiving файлов названо

**Given** input не содержит tracked `.github/workflows/ci.yml` из base.
**When** нет preserve-декларации. **Then** RED перечисляет потерянный путь и не
отправляет ветку. **And** законный близнец добавляет только явное сохранение
этого пути: candidate имеет исходные bytes/mode и проходит этот предикат.

### CI-RS-04 — receiving ownership сильнее входа

**Given** input несёт изменённый receiving-owned файл. **When** строится plan.
**Then** RED называет конфликт; `remove`, реклассификация и широкая маска не
разрешают его. **And** близнец с исходными bytes/mode проходит. Исчезновение
другого receiving-owned файла наблюдается тем же полным path census.

### CI-RS-05 — пакетный floor опубликованной версии

**Given** у repo есть прежняя выпущенная версия с непустым набором Go package
paths; её tag и module archive идентифицированы. **When** candidate archive
теряет один путь. **Then** RED с именем пакета и обеими версиями; ветка и тег не
публикуются. **And** близнец, вернувший пакет в archive, проходит. Наличие папки
без Go-пакета не считается сохранённым пакетом.

### CI-RS-06 — baseline нельзя заменить пустотой

**Given** repo уже выпускал версии. **When** baseline недоступен, его census
пуст или запрошена устаревшая версия вместо актуального floor. **Then** выпуск
не открыт: ошибка данных — RED, недоступность источника — NOT_EXECUTED.
**And** получение и проверка актуального непустого baseline даёт GREEN.
Для этого bounded producer bootstrap без прежнего выпуска не поддерживается;
новый repo требует отдельного контракта, а не обхода floor.

### CI-RS-07 — каждый импорт потребителя есть в архиве

**Given** объявленный consumer импортирует два различных пакета выпускаемого
модуля. **When** archive содержит только первый. **Then** новая П9 производителя
версии возвращает RED с repo/revision consumer и вторым import path до тега.
**And** добавление только второго пакета даёт GREEN при герметичном разрешении
обоих импортов из проверяемого archive. Обе стороны доказываются для каждого
типа declaration; текстовый перечень импортов без tracked consumer program
не заменяет ни один из них.

### CI-RS-08 — перепись потребителей не бывает пустым успехом

**Given** lawful declaration и прочитанные consumer sources. **When** список
consumers пуст, указан отсутствующий module root либо declared consumer имеет
ноль целевых импортов. **Then** RED и точные counts. **And** непустой годный
consumer/import census проходит. Недоступная exact revision — NOT_EXECUTED,
а не consumer с нулём импортов. Частичный обход не даёт GREEN.

### CI-RS-09 — проверяется архив выбранной ревизии

**Given** consumer требует пакет, присутствующий лишь в working tree рядом с
candidate revision. **When** исполняется П9 с `GOWORK=off`, без replace и с
изолированным module cache. **Then** RED; локальный файл и уже населённый кэш
не восполняют пакет. **And** близнец с файлом внутри candidate archive проходит.

### CI-RS-10 — защищённый main получает PR

**Given** target main защищён. **When** разрешена стадия доставки с
`--via-pull-request`. **Then** producer создаёт или находит собственный PR из
ветки с точным candidate; обязательные проверки относятся к actual PR head.
Он ожидает разрешённое штатными правилами слияние, не меняя protections и не
толкая main напрямую. Без `--via-pull-request` этот producer отказывает.

### CI-RS-11 — тег после принятого main

**Given** ветка/PR candidate зелёная, но candidate content ещё не принят main.
**When** запрошен выпуск. **Then** RED, тега нет. **And** после merge producer
читает actual main commit, сверяет принятую дельту, package/archive proofs и
required checks на этом SHA: лишь затем разрешается точный tag target.
Одна достижимость PR head не заменяет сверку содержимого при squash.

### CI-RS-12 — неотвеченные внешние вопросы закрывают мутации

**Given** валидный локальный candidate. **When** GitHub, Git refs, проверка
required checks или нужный proxy не ответили в объявленном бюджете. **Then**
NOT_EXECUTED, имя вопроса и достигнутая стадия; зависящие мутации запрещены.
**And** тот же вход с ответом источника проходит соответствующий предикат.
После write потерянный ответ и недоступный readback сохраняют typed UNKNOWN
именно branch/pr/merge/tag/release-note; последний подтверждённый stage не
сбрасывается. В частности UNKNOWN merge при PR_OPEN запрещает tag.

### CI-RS-13 — опубликованный archive до pin

**Given** tag существует на проверенном main commit. **When** proxy archive
ещё недоступен либо не содержит ожидаемые package paths и необходимые non-Go
payload files. **Then** consumer pin не изменяется; отчёт различает отсутствие
ответа и доказанную неполноту архива. **And** годные `.info`, `.mod`, `.zip`,
обычная проверка checksum и clean consumer resolve/build открывают repin.

### CI-RS-14 — общий гейт достижимости внутренних псевдоверсий

**Given** tracked go.mod требует внутренний module псевдоверсией. **When** её
commit не достижим ни из одной свежей origin head/tag соответствующего repo.
**Then** RED с координатой go.mod и module/version. **And** добавление только
достижимой remote ref делает этот предикат GREEN; локальная ref не подходит.

### CI-RS-15 — post-merge pin обязан быть предком main

**Given** псевдоверсия достижима только из временной ветки. **When** проверяется
финальная поставка #2230. **Then** общий origin-предикат может пройти, но
post-merge predicate возвращает RED. **And** pin, commit которого подтверждён
предком свежего main **своего** repo, проходит. Отдельный тег для такой
псевдоверсии не требуется; прежняя зависимость не возвращается ради проверки.

### CI-RS-16 — нормальная версия и ноль псевдоверсий

**Given** непустой обход modules/internal requirements, все внутренние версии
обычные semver и корректно разрешаются. **When** исполняется tree gate.
**Then** GREEN с `pseudo_versions=0` и ненулевыми остальными census. Обычная
версия не разбирается как commit suffix. Семантика её тега проверяется своим
предикатом разрешения, а не синтетической псевдоверсией.

### CI-RS-17 — ноль осмотренного не равно нулю дефектов

**Given** ожидается дерево продукта с внутренними зависимостями. **When** обход
не прочёл ни одного tracked module либо ни одного internal requirement.
**Then** RED с census; обрезанный обход или parse error не превращаются в
пустое множество. **And** lawful tree из CI-RS-16 проходит.

### CI-RS-18 — происхождение доказательства достижимости

**Given** есть модуль и commit, но отсутствует соответствие module → exact repo,
полная история недоступна либо fresh remote snapshot не получен. **When**
исполняется gate. **Then** неизвестная декларация — RED, недоступный источник —
NOT_EXECUTED. Cached/local refs и commit другого repo не дают GREEN.

### CI-RS-19 — повтор после частичного исполнения

**Given** ответ на branch/PR creation, PR merge, tag или release-note потерян.
**When** повторяется тот же repo/version/input/plan digest. **Then** producer
сначала читает exact typed identity: совпавшее действие не повторяется; иной
объект под тем же именем — RED без force/update/delete/duplicate PR.
**And** если branch push подтверждён, но PR creation окончательно отклонён и
его absence прочитано, result содержит branch PRESENT, pr ABSENT и stage
BRANCH_PRESENT. При lost branch write/readback остаётся branch UNKNOWN и NONE,
а не effects=[]; lawful readback той же ref разрешает продолжение без push.
**And** lost merge/readback сохраняет отдельный merge UNKNOWN при PR_OPEN;
readback merged=true с тем же PR head даёт actual merge SHA и MERGE_PRESENT,
затем отдельно проверяется main ancestry/content. Tag до этого запрещён.
Каждый отрицательный/неисполненный случай имеет однофактный lawful readback
близнец и полный mutation log. Если tag создан, а note/proxy отказали,
TAG_PRESENT сохраняется; восстановление продолжает с readback.

### CI-RS-20 — входом служит готовое receiving tree

**Given** годное подготовленное дерево corelib с новым tool payload или одним
comment-only generated delta. **When** producer проверяет и доставляет его.
**Then** он не вызывает foundation exporter и не запрашивает monorepo revision
как источник файлов; потребительские proofs относятся к этому candidate.
Ни foreign lane, ни broad tools unification не становятся скрытой зависимостью.
**And** первый выпуск допускает independently verified frozen producer из локального
Kachō aggregate с exact source/executable/test/review provenance и отдельной root
authorization. Его будущая посадка в Kachō main не prerequisite этого вызова:
она обязательна в одном готовом T7 aggregate с безопасными consumer workflows
и pins. Это не меняет corelib protected-main/tag predicate и не разрешает ранний
Kachō PR. Drift source или отсутствующая authorization запрещает remote effect.

### CI-RS-21 — состав non-Go инструмента до потребителей

**Given** release manifest именует проверенный NP payload и CI-DT generated
delta с точными digests. **When** zip теряет один объявленный Python/JS/lock
файл или меняет program tokens/descriptor CI-DT. **Then** RED до repin; наличие
Go packages само по себе не даёт поставку. **And** полный prerelease set
NP-P01..06 и DT-P01..03 из design/interface с exact source/test/output/review
binding достаточен до первой published version; projection-only NP недостаточен.
Удаление, искажение либо недоступность каждого required proof проверяется отдельно.
**And** включённый отдельно approved #2590 требует ещё DT-A2590-P01/P02:
exact allowed comment region и неизменные полные program tokens/AST без whitelist,
existing assertions и шесть notice tests. Это дополнение не меняет CI-DT-01..09
и не заменяет generated four-file proof; undeclared addendum delta красна.
**And** pending consumer pins/materialization/runtime/retention/main/closure и
postrelease часть CI-DT-09 не блокируют первый выпуск при полном prerelease set,
но остаются обязательными после него и не объявляются исполненными producer.

### CI-RS-22 — дрейф входа и принимающего дерева

**Given** dry-run связан с base/input/consumer/baseline digests. **When** любой
вход поменялся до внешней мутации либо PR head поменялся во время ожидания.
**Then** producer останавливается, перестраивает candidate/proofs и требует
подтверждения нового plan digest; старый GREEN не применяется к новым bytes.
Изменения base не затираются. **And** обычное продвижение main после принятия
проверенного target допускается, если он остаётся предком свежего main;
отсутствие этой достижимости закрывает выпуск. Pre-tag snapshot и post-tag
readback записываются отдельно: обещания атомарности двух refs нет.

## Производители и готовность

Точная proposed карта scenario → producer → holder → task находится в
`docs/changes/ci-release-supply/holders.yaml` и `tasks.md`; это **заказ**,
а не сообщение о существующей реализации. У каждой отрицательной и
NOT_EXECUTED пробы есть lawful twin и вычисленная одно-фактная дельта.
Независимый tester проверяет fixtures/harness до проверки отсутствующей
возможности. Нулевой набор сценариев или непрочитанный transcript не даёт RED_PROVEN.

Готовность означает: независимые acceptance/class/design review на точные
hashes; честный RED; реализация; самостоятельное GREEN всех применимых holders;
protected PR/main delivery; tag/main/zip identity; consumer pins и одиночные
repo builds; convergence/landing; отдельный closure predicate каждой задачи.
Ни один из этих последующих этапов этим DRAFT не объявлен состоявшимся.
