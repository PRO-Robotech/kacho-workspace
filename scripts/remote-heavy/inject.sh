#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — доказательство, что `run.sh` снимает своё ns на каждом исходе,
# передаёт код команды, не печатает адрес кластера и отказывает на чужом ns.
#
# Кластер — двойник kubectl в PATH пробы: он хранит ns, Job и доставку в своём
# каталоге и отвечает тем, что даёт настоящий API (pod с фазами контейнеров,
# AlreadyExists, предупреждение в stderr). Исходники — настоящий git-клон пробы,
# bundle собирается и «доставляется» настоящим потоком stdin. Двойник печатает в
# stderr адрес сервера и IPv4 на КАЖДОМ вызове — как kubectl с предупреждением и
# ошибкой соединения, — поэтому маска run.sh судится настоящим входом; что двойник
# их действительно печатает, утверждает отдельный случай (L0), иначе проба утечки
# была бы пустой.
#
#   K1 команда кодом 0                     → код 0; ns снято; метки и срок на ns
#   K2 команда кодом 42                    → код 42; ns снято
#   K3 TERM посреди идущей команды         → код 143; ns снято; выход ≤ 20 с
#   K4 контейнер OOMKilled                 → код 76; ns снято
#   K4b признак «remote-heavy-oom:» шага   → 76 (команду убил предел, контейнер
#      вышел её кодом); близнец K4c 137 без признака → 137
#   K6 подготовка pod не удалась            → 69; ns снято; близнец K6b — код 125 команды
#   K5 --keep 2                            → код команды; ns НЕ снято; срок ≈ +2 ч
#   R1 NS=kacho                            → 64; к кластеру ни одного обращения
#   R2 --ns kacho                          → 64; к кластеру ни одного обращения
#   R3 --ns вне формы t<задача>-heavy-…    → 64; к кластеру ни одного обращения
#   X1 current-context файла = infra       → прогон в client: каждый вызов kubectl
#      несёт --context client, current-context не изменён (решение владельца
#      2026-10-09 «тебе можно ставить только в client»)
#   X2 KACHO_REMOTE_CONTEXT не на -client  → 64; к kubectl ни одного обращения;
#      близнец X2b — на client → 0; X2c названного нет → 69
#   X3 в файле нет контекста -client       → 69, run и --available, шаг назван
#   X4 контекстов -client два              → 69, шаг назван
#   R4 ns уже есть (близнец K1)            → 64; чужое ns НЕ снято
#   A1 Job — в своём ns t<N>-heavy-*, условий узла по стенду нет: ни
#      podAntiAffinity, ни nodeAffinity, ни упоминания ns kacho в affinity
#      (решение владельца 2026-10-09 «не запускать в NS качо а не на узлах»);
#      каждый созданный объект — в ns прогона; запросы и пределы — числом
#   U0 pod в своём пространстве пользователей (hostUsers: false)
#   U1 профиль с dind: privileged нет нигде, dind на crun без cgroup (F1)
#   S0 сервер добавил законные умолчания   → 0 (близнец S1–S3)
#   S1 API снял hostUsers (Job и pod)       → 69; ns снято и при --keep; доставки нет
#   S2 вебхук снял procMount dind в pod     → 69 до доставки
#   S3 вебхук сделал fetch privileged       → 69 до доставки
#   U2 проверка userns — первой строкой dind и run одним текстом; над поддельным
#      /proc (sh и bash): «0 0 4294967295», 0→0 узла, 0 узла второй строкой,
#      тождественный gid_map —
#      125 и запись в termination-log; законное отображение — 0
#   U3 двойник: dind с тождественным uid_map отказал → 69; ns снято; доставки нет
#   U4 run отказал той же проверкой (код 125) → 69, а не код команды (ср. K6b)
#   N1 NetworkPolicy ns: входящих нет; исходящие — DNS (53) и мир без частных
#      диапазонов, адресов узлов, диапазона служб и управления кластера (F2)
#   P1 проба закрытости в pod — служба kacho, не закрытая политикой kacho;
#      близнец (закрытая) не выбран
#   P1 ни один контейнер Job профиля с go test не зовёт apt и не называет
#      deb.debian.org; шаг пакетов в run есть; lint без пакетов (P1l)
#   P2 шаг пакетов исполнением: jq и PyYAML ставятся с пином суммы, apt не позван;
#      близнецы — сумма не сходится (P2b, P2g), сети нет (P2d), архитектура чужая
#      (P2f), всё уже есть и ничего не качается (P2c)
#   P3 контейнер pgclient исполнением: бинари и библиотеки клиента без семейства
#      libc, обёртки несут LD_LIBRARY_PATH лишь на вызов, готовность — файл ready;
#      нет libpq (P3b) либо psql (P3c) — 125 и файл failed с причиной
#   P4 pgclient — ОБЫЧНЫЙ контейнер из postgres:17-trixie ПОСЛЕ run (холодный pull не
#      съедает срок до доставки исходников), не init; том tools смонтирован; у lint нет
#   P6 шаг pgwait исполнением: готов — 0; отказ pgclient — 125 с причиной (P6a); не
#      дождался — 125 по сроку (P6b); дождался позже старта — 0 и «ждал N с» (P6c);
#      psql не исполняется — 125 (P6d)
#   P5 «подготовка pod до команды — N с» печатается до команды
#   P7 срок Job — команда плюс 1800 с до начала (холодный pull, dind, доставка)
#   C1 идущих 2 при пределе 2              → 75, create не звался (F3)
#   C2 близнец: их Job завершены           → 0
#   C3 близнец: срок ns в прошлом          → 0
#   C4 гонка: чужое ns создано раньше      → 75, своё ns снято, Job нет
#   C4b близнец без гонки                  → 0
#   C5 гонка при --keep                    → 75, ns всё равно снято
#   V2 --available при занятом кластере    → 75; близнец V2b → 0
#   M1 KACHO_REMOTE_HEAVY_MAX=0            → 64
#   M2 предел по умолчанию 4 — страховка над размещением: 4 идущих → 75;
#      близнец M2b 3 идущих → 0 (C1–C5, V2 судят предел явным 2)
#   Q1 стенд (pod ns kacho) на всех узлах, место есть → --available 0 и прогон 0
#      (стенд узел не запирает); Q1d второй go-race на ОДНОМ узле со стендом
#      оставил бы меньше 20 % CPU → 75, запас назван (ws#1143)
#   QH допуск по запросам профиля и запасу 20 %: узлы и фон замера 2026-10-17 —
#      помещаются 4 лёгких, 1 тяжёлый и 2 лёгких, 2 тяжёлых; следующий — 75 с
#      названным запасом (ws#1143); порча «запас 0 %» — mutants.py headroom-0
#   QB запас на самой границе: остаток CPU 3 100m → 0, 3 099m → 75; фон памяти
#      18 007 МиБ → 0, 18 008 МиБ → 75; порча порога hr-0.1 с прежним текстом — по коду
#   Q3 единственный узел не готов / закрыт / taint NoSchedule → 69; прогон 69 без ns
#   Q2 места под go-race нет ни на одном узле → 75 и прогон 75 без ns; близнец Q2b
#      тот же кластер, профиль lint → 0 и прогон 0; Q2c профиля нет → 64
#   Q5 перепись pod кластера > 128 КиБ (строка аргумента) → разбирается, 0
#   Q4 pod ждёт планирования, чужой pod занял последнее место → 75 сразу, ns снято
#      и при --keep; близнец Q4b место есть → run.sh ждёт дальше
#   KX1 команда с $$, $(ИМЯ) env контейнера, $$(…), $(…), $ в конце и незакрытым
#      $( → раскрытием kubelet (двойник правила Kubernetes) доходит до run байт в
#      байт (ws#1142); KX1-ctl — та же команда без экранирования искажается;
#      KX1-env — вход pre-push с $$ и $(HEAVY_NODE) доходит до env run байт в байт;
#      KX1-all — во всех контейнерах Job, init тоже, $ лишь парами
#   O1 строки run.sh после выбора ns несут его имя
#   O2 stderr — файл, в который пишет посторонний живой процесс → предупреждение с
#      его pid; близнец O2b файл держат только предки прогона → молчание
#   G1 остатки kill -9 (каталог, процесс, ns, ссылка) мёртвого владельца → сняты
#   G2 близнецы: живой владелец и ns с чужой меткой — не тронуты
#   E1 ревизия с пинами helm и node в ci.yaml, профиль с go test → пины в окружении
#      run, установка helm пина и node мажора пина с проверкой суммы, сверка среды
#      перед командой, строка «Job создан» их называет (ws#996)
#   E2 сверка среды ИСПОЛНЕНИЕМ над поддельным PATH: helm нет / не та версия /
#      версия-префикс, node нет / не та / префикс → 125 и «среда: …» в
#      termination-log; близнецы — верные версии и ревизия без пинов → 0
#   E7 установка ИСПОЛНЕНИЕМ (двойник curl, настоящие архивы): оба пина, только
#      node, только helm → 0 и инструменты в bin; сумма helm не сошлась, сумма
#      node не сошлась, чужая архитектура → 125 с названной причиной; мажор →
#      последний выпуск мажора; пин 26.1 при v26.11.x в индексе → v26.1.x (не
#      v26.11.x); полный пин 26.1.0 → ровно v26.1.0
#   E8 пины законными формами YAML: ключи шага до uses, поточный шаг с
#      ключом в кавычках → те же пины в окружении run (близнец E1)
#   E9 шаг setup-helm без version, setup-node без node-version → 69 до кластера,
#      шаг и ключ названы
#   E10 пин node вне формы (lts/*) → 69, Job нет; E10b пин helm вне формы
#      (latest) → 69, Job нет
#   D1 модули, которые пробы читают ИСХОДНИКАМИ (ws#1018): Job каждого профиля
#      несёт шаг `go mod download` модуля дерева перед командой; текст шага из Job
#      исполняется настоящим go над файловым прокси: контроль — `go build` модуль,
#      ни одним пакетом не импортированный, в кэш не кладёт; после шага исходник
#      модуля в кэше есть; близнец D1b — модуль не достать → 125 «модули» в
#      termination-log; D1c — каталог без go.mod → 0, строка «качать нечего»
#   E11 задание на ubuntu-latest без setup-helm, buf шагом (форма ci.yml kaname)
#      → helm образа ранера и пин buf в окружении run (ws#1110); E11b self-hosted —
#      helm не ставится; E11c таблица образов не получена → 69; E11d пин buf вне
#      формы → 69; E2-buf-* сверка buf, E7-buf* установка buf с суммой выпуска
#   NC1 Job ci-local kacho с --push-input → вход в окружении run, шаг зависимостей
#      консоли — после сверки среды и до exec (ws#1115); близнецы kaname ci-local
#      и kacho go-race — шага нет; вход вне формы → 64 до кластера
#   NC2 шаг консоли ИСПОЛНЕНИЕМ над деревом пробы (двойники npm и node): правка
#      консоли → npm ci в рабочем каталоге ui.yml и --prefix каждого STANDALONE по
#      порядку, готовы все пакеты; правка без консоли, не отправка, диапазон не
#      выбран → npm не зван, 0; npm ci отказал (корень, standalone), пакет не готов,
#      ui.yml без STANDALONE, npm нет → 125 «консоль: …» в termination-log
#   NC3 инъекция «npm ci снят» → свойство NC2-console не держится (проба не слепа)
#   GI1 ci-local отправкой при корневой учётке копии → имя и адрес в окружении run,
#      шаг записи до exec, адрес не напечатан (ws#1115, отправка 853)
#      GI1-env — имена окружения всех контейнеров Job из разрешённого списка;
#      GI1-decoy — signingkey, credential.helper, http.extraHeader, insteadOf,
#      include.path корневого gitconfig до Job и вывода не доходят
#   NC2-update обновление опубликованной ветки: удалённый sha ненулевой, ветка влила
#      ствол с правкой консоли — диапазон хука её трогает, запасной — нет → npm ci
#   GI2-name-only, GI2-email-only — половина учётки → 69 до кластера
#   GI2 отправка без корневой учётки → 69 до кластера, причина названа; GI2b не
#      отправка → 0, Job без учётки, строка об этом
#   GI3 шаг учётки ИСПОЛНЕНИЕМ: корневая pod = подпись коммита (предикат стража);
#      GI3b инъекция «учётка не передана» → предикат не держится
#   E3 два пина helm                        → 69 до кластера, причина названа
#   E4 профиль lint на ревизии с пинами     → среду не ставит (близнец E1)
#   E5 ревизия без пинов                    → строка называет, что сверять нечего
#   E6 run отказал сверкой среды            → 69 «не выполнилось — среда: …»
#   H1 ревизия только на боковой ветке origin и метка → в bundle и ссылками в
#      дереве pod (FETCH из Job исполняется), ствол и ревизия на месте, временной
#      ссылки run.sh там нет — история как у checkout fetch-depth: 0 (ws#996)
#   RG0 Job несёт шаг красных групп после подготовки, команда — через heavy_cmd;
#      зелёный прогон каталога копий не заводит и о копиях молчит (ws#1136)
#   RG1 шаг ИСПОЛНЕНИЕМ над синтетическим прогоном (настоящий go test, один пакет
#      с упавшим тестом; группы в форме вывода ci-local): дайджест называет пакет,
#      тест и строку отказа; копий ровно две красные (ПРОПУСК и ok — нет); код —
#      код команды; близнец RG1-green — копий нет, 0
#   RG2 тот поток через run.sh → каталог «<журнал>.red-<ns>» рядом с журналом, копии
#      равны журналам pod, адрес pod в копии под маской, дайджест в журнале на
#      машине, строк потока копий там нет, итог называет каталог и файлы
#   RG3 поток повторён (стык переподключения) → копии целы
#   RG4 строка копии выпала → копия не сохранена, причина названа, вторая цела,
#      дайджест на месте; RG4b содержимое подменено при тех же числе строк и байтах
#      → ловит сумма
#   RG5 итога в потоке нет → разбор полного лога контейнера, вывод не повторён
#   RG7 признак OOM шага ИСПОЛНЕНИЕМ: oom_kill вырос → «remote-heavy-oom:» в
#      termination-log, код команды сохранён; близнец RG7b — без роста признака нет
#   RG8 фоновый процесс команды держит её stdout дольше неё → шаг не ждёт его
#      (≤ 10 с), код — код команды, вывод в копии
#   RG9 два упавших пакета дальше 10 строк → дайджест называет оба
#   RG10 паника в горутине без «--- FAIL», стек > 10 строк → сообщение и кадр
#   RG11 журнал больше HEAVY_RED_BYTES → копия = последние байты, обрезка названа
#   RG12 IPv6, IPv4 и имя сервера в журнале → в файлах копий только маска
#   RG13 обрыв внутри копии (нет end и total) → копии из полного лога контейнера
#   RG6 красный код, красных групп ноль → строка с числом групп, каталога нет;
#      RG6b итога нет нигде → «НЕ получены»
#   L0 двойник сам печатает адрес и IPv4   → да (контроль пробы утечки)
#   L0b двойник печатает адреса pod в stdout лога → да (контроль F4)
#   L1 вывод всех случаев без адреса сервера, IPv4/IPv6 узлов и pod, токена,
#      имён контекстов и пути кубконфига (F4: stdout лога тоже)
#   V1 кластер не отвечает (--available)   → 69, причина без адреса
#   W1 узлы с -infra-                       → 69, run и --available, записей ноль, шаг
#      назван (решение владельца 2026-10-10 «По префиксу нод можешь понять тот
#      кластер или нет, куб конфет мог меняться»)
#   W2 узлы смешанные (client и infra)      → 69, записей ноль
#   W3 узлов ноль                           → 69, run и --available, записей ноль
#   W4 узлы чужого профиля (-client-)       → 69, записей ноль
#   W5 узлы профиля → 0, и перепись узлов — раньше первой записи
#   W6 профиль из имени файла <учётка>--<профиль>.yaml без переменной → 0;
#      близнец W6b тот же файл, узлы чужого профиля → 69
#   W7 профиль не выводится (ни имени, ни переменной) → 69 до кластера
#   W8 переменная и имя файла расходятся     → 69 до кластера
#   W9 файл подменён после создания ns, узлы стали infra → 69 до сети ns; ns НЕ
#      снято (оно в прежнем кластере), шаг назван; близнец W9b — файл сменился,
#      узлы те же → 0, узлы переписаны заново
#   W10 узлы с -infra- при остатках мёртвого владельца → 69, уборка ns не звалась
#
# Запуск: bash scripts/remote-heavy/inject.sh   (код 0 — все случаи сошлись)
# Что набор краснеет на порче каждого решения среды и истории — mutants.py рядом
# (REMOTE_HEAVY_RUN — путь испорченной копии run.sh).
set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REMOTE_HEAVY_RUN — испорченная копия run.sh от mutants.sh; иначе run.sh рядом.
RUN="${REMOTE_HEAVY_RUN:-$SELF_DIR/run.sh}"
BOX="$(mktemp -d)" || { echo "inject: каталог пробы не создан" >&2; exit 2; }
trap 'rm -rf -- "$BOX"' EXIT

SERVER_HOST="sentinel-cluster.invalid"
SERVER_IP="203.0.113.7"
TOKEN="SENTINEL-TOKEN-5f1c"
# Адреса, которые настоящий кластер отдаёт в выводе: узла (в сеть ns) и pod/dind
# (в лог команды). Ни один не должен дойти до вывода run.sh.
export FAKE_NODE_IP="198.51.100.10" FAKE_NODE_IP6="2001:db8::10" FAKE_API_IP="198.51.100.77"
export FAKE_POD_IP="192.0.2.44" FAKE_POD_IP6="2001:db8:0:1::44"
PASS=0; FAIL=0; ALL_OUT="$BOX/all.out"; : > "$ALL_OUT"

mkdir -p "$BOX/bin" "$BOX/state"
# kubeconfig_with <current> <контекст>… — кубконфиг пробы (JSON — тоже кубконфиг):
# current-context смотрит на <current>, как файл профиля, который владелец вручную
# переключил на infra (опыт 2026-10-09).
kubeconfig_with() {
    local cur="$1"; shift
    jq -n --arg s "https://$SERVER_HOST:6443" --arg t "$TOKEN" --arg cur "$cur" '{apiVersion: "v1", kind: "Config",
      clusters: [{name: "c", cluster: {server: $s}}], users: [{name: "u", user: {token: $t}}],
      contexts: [$ARGS.positional[] | {name: ., context: {cluster: "c", user: "u"}}], "current-context": $cur}' --args "$@"
}
CTX_CLIENT="lab-a1-client"; CTX_INFRA="lab-a1-infra"
# Профиль кластера пробы (СТРАЖ run.sh): узлы двойника — «lab1-client-<пул>-…».
# Случаи W снимают переменную и выводят профиль из имени файла.
export KACHO_REMOTE_PROFILE=lab1
NODE_PFX="lab1-client-p00l-"
export FAKE_NODE_PFX="$NODE_PFX"
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" "$CTX_CLIENT" > "$BOX/kubeconfig"

# ── двойник kubectl ──────────────────────────────────────────────────────────
cat > "$BOX/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
mkdir -p "$S/ns" "$S/jobs"
mkdir -p "$S/ns" "$S/jobs"
echo "$*" >> "$S/calls"
echo "Warning: cluster https://$FAKE_HOST:6443 ($FAKE_IP) answered slowly" >&2
ns=""; sel=""; all=0; ctx=""; kcfg=""
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --kubeconfig) kcfg="$2"; shift 2 ;;
        --context) ctx="$2"; shift 2 ;;
        --request-timeout=*|--field-selector=*|--wait=*|--timeout=*) shift ;;
        -n) ns="$2"; shift 2 ;;
        -l) sel="$2"; shift 2 ;;
        -o) shift 2 ;;
        -A) all=1; shift ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# spec_of job|pod — spec pod из сохранённого Job, как его вернул бы «сервер»:
# FAKE_DROP_HOSTUSERS=1 — API без поддержки userns молча снял hostUsers (и в Job,
# и в pod); FAKE_POD_MUT — вебхук правит pod: procmount (снят у dind), privileged
# (fetch привилегирован), defaults (законные умолчания сервера — близнец).
spec_of() {
    jq -c --arg w "$1" '.spec.template.spec
      | if ($ENV.FAKE_DROP_HOSTUSERS // "") == "1" then del(.hostUsers) else . end
      | if $w != "pod" then .
        elif ($ENV.FAKE_POD_MUT // "") == "procmount" then (.initContainers[] | select(.name == "dind") | .securityContext) |= del(.procMount)
        elif ($ENV.FAKE_POD_MUT // "") == "privileged" then (.initContainers[] | select(.name == "fetch") | .securityContext) |= ((. // {}) + {privileged: true})
        elif ($ENV.FAKE_POD_MUT // "") == "defaults" then
          (.initContainers, .containers) |= map(.securityContext = ({procMount: "Default", allowPrivilegeEscalation: true} + (.securityContext // {})) | .terminationMessagePath = "/dev/termination-log")
          | .dnsPolicy = "ClusterFirst" | .hostNetwork = false
        else . end' "$S/job.json"
}
# pods <status> — список из одного pod со spec «сервера».
pods() { jq -nc --argjson sp "$(spec_of pod)" --argjson st "$1" '{items: [{metadata: {name: "run-x"}, spec: $sp, status: $st}]}'; }
# Без --context kubectl берёт current-context файла; контекст не -client ведёт себя
# как infra 2026-10-09: изменяющий запрос отклоняет политика допуска.
[ -n "$ctx" ] || [ -z "$kcfg" ] || ctx="$(jq -r '."current-context"' "$kcfg")"
case "$1" in
    create|apply|delete|exec|patch|label|annotate)
        case "$ctx" in *-client) ;; *)
            echo "Error from server (Forbidden): admission webhook denied the request: policy host-access-allowlist (context $ctx)" >&2; exit 1 ;;
        esac ;;
esac
case "$1 ${2:-}" in
    "config get-contexts") jq -r '.contexts[].name' "$kcfg" ;;
    "config view") printf 'https://%s:6443' "$FAKE_HOST" ;;
    "auth can-i")
        if [ "${FAKE_DOWN:-0}" = 1 ]; then
            echo "Unable to connect to the server: dial tcp $FAKE_IP:6443: i/o timeout" >&2; exit 1
        fi
        echo yes ;;
    "create -f")
        kind="$(jq -r .kind "$3")"
        if [ "$kind" = Namespace ]; then
            name="$(jq -r .metadata.name "$3")"
            if [ -e "$S/ns/$name" ]; then
                echo "Error from server (AlreadyExists): namespaces \"$name\" already exists" >&2; exit 1
            fi
            mkdir -p "$S/ns"
            # FAKE_SWAP_FILE — файл кубконфига подменён сразу после создания ns (опыт
            # 2026-10-10); FAKE_NODES_AFTER_NS — узлы, которые с этого мига видны.
            if [ -n "${FAKE_SWAP_FILE:-}" ]; then echo ' ' >> "$FAKE_SWAP_FILE"; touch "$S/swapped"; fi
            jq --arg t "$(now)" '.metadata.creationTimestamp = $t | .status.phase = "Active"' "$3" > "$S/ns/$name"
            # гонка: другой запуск создал своё ns мгновением раньше
            if [ -n "${FAKE_RACE:-}" ]; then
                jq -n --arg n "$FAKE_RACE" --arg t "$(date -u -d '-1 second' +%Y-%m-%dT%H:%M:%SZ)" --arg e "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
                    '{kind: "Namespace", metadata: {name: $n, creationTimestamp: $t, labels: {"kacho.io/kind": "heavy"}, annotations: {"kacho.io/expires": $e}}, status: {phase: "Active"}}' > "$S/ns/$FAKE_RACE"
            fi
        elif [ "$kind" = NetworkPolicy ]; then
            cp "$3" "$S/netpol.json"
        else
            cp "$3" "$S/job.json"
        fi ;;
    "apply -f") cp "$3" "$S/applied.json" ;;
    "get ns")
        if [ -n "${3:-}" ]; then
            [ -f "$S/ns/$3" ] || { echo "Error from server (NotFound): namespaces \"$3\" not found" >&2; exit 1; }
            cat "$S/ns/$3"
        else
            find "$S/ns" -type f -exec cat {} + 2>/dev/null | jq -s --arg sel "$sel" '{items: [.[] | select(($sel == "") or (.metadata.labels["kacho.io/kind"] == "heavy"))]}'
        fi ;;
    "get jobs") find "$S/jobs" -type f -exec cat {} + 2>/dev/null | jq -s '{items: .}' ;;
    "get svc")
        if [ "$all" = 1 ]; then
            echo '{"items":[{"metadata":{"namespace":"dns-sys","name":"dns"},"spec":{"selector":{"k8s-app":"dns"},"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}]}},
                            {"metadata":{"namespace":"dns-sys","name":"dns-metrics"},"spec":{"selector":{"k8s-app":"dns"},"ports":[{"port":9153,"protocol":"TCP"}]}}]}'
        else
            echo '{"items":[{"metadata":{"name":"edge"},"spec":{"type":"ClusterIP","clusterIP":"10.96.0.20","selector":{"app":"edge"},"ports":[{"port":8080}]}},
                            {"metadata":{"name":"svc-a"},"spec":{"type":"ClusterIP","clusterIP":"10.96.0.21","selector":{"app":"svc-a"},"ports":[{"port":9090}]}}]}'
        fi ;;
    "get netpol") echo '{"items":[{"spec":{"podSelector":{"matchLabels":{"app":"edge"}}}}]}' ;;
    "get nodes")
        # FAKE_NODES — список узлов случая размещения; иначе один готовый узел.
        if [ -e "$S/swapped" ] && [ -n "${FAKE_NODES_AFTER_NS:-}" ]; then printf '%s\n' "$FAKE_NODES_AFTER_NS"; exit 0; fi
        if [ -n "${FAKE_NODES:-}" ]; then printf '%s\n' "$FAKE_NODES"; exit 0; fi
        jq -n --arg e "$FAKE_NODE_IP" --arg v6 "$FAKE_NODE_IP6" --arg n "${FAKE_NODE_PFX}n1" '{items: [{metadata: {name: $n},
          status: {addresses: [{type: "ExternalIP", address: $e}, {type: "InternalIP", address: "10.0.0.5"}, {type: "InternalIP", address: $v6}, {type: "Hostname", address: $n}],
                   conditions: [{type: "Ready", status: "True"}], allocatable: {cpu: "15500m", memory: "30913596Ki"}}}]}' ;;
    "get endpointslices") jq -n --arg a "$FAKE_API_IP" '{items: [{endpoints: [{addresses: [$a]}]}]}' ;;
    "get servicecidrs") echo '{"items":[{"spec":{"cidrs":["10.96.0.0/12"]}}]}' ;;
    "get pods")
        # -A — перепись pod кластера для размещения: FAKE_CLUSTER_PODS, а после
        # создания Job — FAKE_PODS_AFTER_JOB (стенд встал на узел, пока pod ждал).
        if [ "$all" = 1 ]; then
            none='{"items":[]}'
            if [ -e "$S/job.json" ] && [ -n "${FAKE_PODS_AFTER_JOB:-}" ]; then printf '%s\n' "$FAKE_PODS_AFTER_JOB"
            elif [ -n "${FAKE_CLUSTER_PODS_FILE:-}" ]; then cat "$FAKE_CLUSTER_PODS_FILE"
            else printf '%s\n' "${FAKE_CLUSTER_PODS:-$none}"; fi
            exit 0
        fi
        if [ ! -e "$S/job.json" ]; then echo '{"items":[]}'; exit 0; fi
        # FAKE_UNSCHED — планировщик не находит узла: pod ждёт, условие PodScheduled False.
        if [ "${FAKE_UNSCHED:-0}" = 1 ]; then
            pods '{"phase":"Pending","conditions":[{"type":"PodScheduled","status":"False","message":"0/1 nodes are available: 1 node(s) didn'"'"'t match pod anti-affinity rules."}]}'
            exit 0
        fi
        # FAKE_USERNS_DIND — dind отказал проверкой userns и перезапускается: fetch не
        # начинается никогда, отказ — в lastState бокового.
        if [ -n "${FAKE_USERNS_DIND:-}" ]; then
            pods "$(jq -nc --arg m "$FAKE_USERNS_DIND" '{phase: "Pending", initContainerStatuses: [
                {name: "dind", state: {waiting: {reason: "CrashLoopBackOff"}}, lastState: {terminated: {exitCode: 125, message: $m}}},
                {name: "fetch", state: {waiting: {reason: "PodInitializing"}}}], containerStatuses: [{name: "run", state: {waiting: {reason: "PodInitializing"}}}]}')"
            exit 0
        fi
        if [ ! -e "$S/delivered" ]; then
            pods '{"phase":"Pending","initContainerStatuses":[{"name":"fetch","state":{"running":{}}}],"containerStatuses":[{"name":"run","state":{"waiting":{"reason":"PodInitializing"}}}]}'
            exit 0
        fi
        if [ "${FAKE_HANG:-0}" = 1 ]; then
            pods '{"phase":"Running","initContainerStatuses":[{"name":"fetch","state":{"terminated":{"exitCode":0}}}],"containerStatuses":[{"name":"run","state":{"running":{}}}]}'
            exit 0
        fi
        reason=Completed; [ "${FAKE_OOM:-0}" = 1 ] && reason=OOMKilled
        pods "$(jq -nc --argjson rc "${FAKE_EXIT:-0}" --arg r "$reason" --arg m "${FAKE_MSG:-}" '{phase:(if $rc == 0 then "Succeeded" else "Failed" end),
            initContainerStatuses:[{name:"fetch",state:{terminated:{exitCode:0}}}],
            containerStatuses:[{name:"run",state:{terminated:{exitCode:$rc,reason:$r,message:$m}}}]}')" ;;
    "exec -i") cat > "$S/bundle"; touch "$S/delivered" ;;
    "logs -f")
        echo "строка лога команды: pod $FAKE_POD_IP, dind $FAKE_POD_IP6"
        # FAKE_LOG_FILE — поток лога шага красных групп (RG*); без него — итог шага
        # без красных, как его печатает всякий pod после команды.
        if [ -n "${FAKE_LOG_FILE:-}" ]; then cat "$FAKE_LOG_FILE"; else echo "remote-heavy-redlog: total 0 0"; fi
        touch "$S/logging"
        # Висит, пока жив вызвавший run.sh: срок — предикат, а не время.
        if [ "${FAKE_HANG:-0}" = 1 ]; then
            for _ in $(seq 1 600); do kill -0 "$PPID" 2>/dev/null || exit 0; sleep 0.1; done
        fi ;;
    "logs run-x") [ -z "${FAKE_FULL_LOG:-}" ] || cat "$FAKE_FULL_LOG" ;;
    "get events") echo '{"items":[]}' ;;
    "delete ns") rm -f "$S/ns/$3"; echo "$3" >> "$S/deleted" ;;
    "get job")
        [ -e "$S/job.json" ] || { echo "Error from server (NotFound): jobs.batch \"run\" not found" >&2; exit 1; }
        jq -c --argjson sp "$(spec_of job)" '.spec.template.spec = $sp | .status = {}' "$S/job.json" ;;
    *) echo "двойник: вызов «$*» не знаком" >&2; exit 9 ;;
esac
FAKE
chmod +x "$BOX/bin/kubectl"

# ── клон пробы ───────────────────────────────────────────────────────────────
SRC="$BOX/src"
git init -q "$SRC"
mkdir -p "$SRC/.github/workflows"
printf 'module example.com/x\n\ngo 1.26.0\n\ntoolchain go1.26.8\n' > "$SRC/go.mod"
printf 'jobs:\n  lint:\n    steps:\n      - run: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2\n' > "$SRC/.github/workflows/ci.yaml"
git -C "$SRC" add -A
# shellcheck source=scripts/lib/sandbox-git-home.sh
. "$SELF_DIR/../lib/sandbox-git-home.sh"
sandbox_git_home "$BOX/ghome" || { echo "inject: корневой подписи нет — клон пробы не построен (не выполнилось)" >&2; exit 2; }
sandbox_git -C "$SRC" commit -q -m probe
# Ревизии с пинами среды конвейера (ws#996): pins — helm и node объявлены так, как
# в ci.yaml продукта (setup-helm с version, setup-node с node-version; соседний
# setup-kubectl со своим version — законный близнец, его version не пин helm);
# pins2 — два разных пина helm; pins3 — пины законными формами YAML, которые
# разбор строками терял молча; pins4 — шаг без ключа пина.
pin_rev() {
    git -C "$SRC" checkout -q -b "$1"
    printf '%s' "$2" > "$SRC/.github/workflows/ci.yaml"
    sandbox_git -C "$SRC" commit -q -am "$1"
    git -C "$SRC" checkout -q -
}
pin_rev pins 'jobs:
  lint:
    steps:
      - run: go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2
  unit:
    steps:
      - uses: azure/setup-helm@0123  # v5
        with:
          version: v4.2.4
      - uses: azure/setup-kubectl@4567  # v5
        with:
          version: v1.33.0
  ui:
    steps:
      - uses: actions/setup-node@89ab  # v7
        with:
          node-version: '"'"'26'"'"'
  charts:
    steps:
      - uses: azure/setup-helm@0123  # v5
        with:
          version: v4.2.4
'
pin_rev pins2 'jobs:
  unit:
    steps:
      - uses: azure/setup-helm@0123
        with:
          version: v4.2.4
  charts:
    steps:
      - uses: azure/setup-helm@0123
        with:
          version: v3.17.0
'
pin_rev pins3 'jobs:
  unit:
    steps:
      - name: helm
        with:
          version: v4.2.4
        uses: azure/setup-helm@0123
      - uses: azure/setup-kubectl@4567
        with: {version: v1.33.0}
  ui:
    steps:
      - {uses: actions/setup-node@89ab, with: {"node-version": "26"}}
'
pin_rev pins5 'jobs:
  unit:
    steps:
      - uses: azure/setup-helm@0123
        with:
          version: v4.2.4
      - uses: actions/setup-node@89ab
        with:
          node-version: lts/*
'
pin_rev pins6 'jobs:
  unit:
    steps:
      - uses: azure/setup-helm@0123
        with:
          version: latest
'
pin_rev pins4 'jobs:
  unit:
    steps:
      - uses: azure/setup-helm@0123
      - uses: actions/setup-node@89ab
        with:
          cache: npm
'

# Ревизии среды ОБРАЗА ранера и buf (ws#1110), формы ci.yml kaname 746: задание на
# ubuntu-latest без setup-helm (helm несёт образ ранера), buf — шаг
# bufbuild/buf-setup-action с version; imgs2 — только self-hosted (образа нет —
# законный близнец: helm не ставится); imgs3 — пин buf вне формы.
pin_rev imgs 'jobs:
  standalone:
    runs-on: ubuntu-latest
    steps:
      - uses: bufbuild/buf-setup-action@3e33  # v1.9.0
        with:
          version: 1.72.0
          github_token: x
      - run: go test ./tools/standalonetargets/
'
pin_rev imgs2 'jobs:
  unit:
    runs-on: self-hosted
    steps:
      - run: go test ./...
'
pin_rev imgs3 'jobs:
  standalone:
    runs-on: ubuntu-latest
    steps:
      - uses: bufbuild/buf-setup-action@3e33
        with:
          version: latest
'
# Двойник curl машины запуска: таблица образов и Readme образа — формы
# actions/runner-images (строки из настоящих файлов 2026-10-16); FAKE_CURL_DOWN=1 —
# сеть не отвечает.
cat > "$BOX/bin/curl" <<'FAKE'
#!/usr/bin/env bash
u=""; for a in "$@"; do case "$a" in http*) u="$a" ;; esac; done
[ "${FAKE_CURL_DOWN:-0}" = 1 ] && { echo "curl: (6) Could not resolve host" >&2; exit 6; }
case "$u" in
  */actions/runner-images/main/README.md)
    printf '%s\n' '| Ubuntu 24.04<br>![Endpoint Badge](https://img.shields.io/x) | x64 | `ubuntu-latest` or `ubuntu-24.04` | [ubuntu-24.04] |' \
      '| Ubuntu 24.04 Arm64<br>![Endpoint Badge](https://img.shields.io/x) | arm64 | `ubuntu-24.04-arm` | [ubuntu-24.04-arm64] |' \
      '[ubuntu-24.04]: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md' \
      '[ubuntu-24.04-arm64]: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Arm64-Readme.md' ;;
  */images/ubuntu/Ubuntu2404-Readme.md) printf '%s\n' '# Ubuntu 24.04' '- Image Version: 20261012.334.1' '- Helm 3.22.0' '- Kind 0.33.0' ;;
  *) echo "двойник curl: адрес не знаком: $u" >&2; exit 22 ;;
esac
FAKE
chmod +x "$BOX/bin/curl"

fresh() { rm -rf "$BOX/state"; mkdir -p "$BOX/state/ns"; }

# ── kubelet: раскрытие command, args и env контейнера (ws#1142) ─────────────
# Что получит контейнер, решает не spec, а kubelet: в command, args и value env он
# раскрывает $(ИМЯ) значением env контейнера (объявленного раньше — для env),
# сворачивает $$ в $, прочее оставляет как есть — правило expansion.Expand
# Kubernetes (third_party/forked/golang/expansion), перенесённое дословно. Пробы,
# исполняющие текст из Job, читают его через это раскрытие: так они судят то, что
# исполнит pod, а не то, что лежит в манифесте.
cat > "$BOX/kexpand.py" <<'PY'
import json, sys

def expand(s, env):
    out, cp, i, n = [], 0, 0, len(s)
    while i < n:
        if s[i] == "$" and i + 1 < n:
            out.append(s[cp:i])
            rest = s[i + 1:]
            if rest[0] == "$":
                read, isvar, adv = "$", False, 1
            elif rest[0] == "(":
                j = rest.find(")", 1)
                if j < 0:
                    read, isvar, adv = "$(", False, 1
                else:
                    read, isvar, adv = rest[1:j], True, j + 1
            else:
                read, isvar, adv = "$" + rest[0], False, 1
            out.append(env.get(read, "$(" + read + ")") if isvar else read)
            i += adv
            cp = i + 1
        i += 1
    return "".join(out) + s[cp:]

mode, path, name = sys.argv[1:4]
sp = json.load(open(path))["spec"]["template"]["spec"]
c = next(x for x in sp.get("initContainers", []) + sp.get("containers", []) if x["name"] == name)
env = {}
for e in c.get("env", []):
    if "value" in e:
        env[e["name"]] = expand(e["value"], env)
argv = [expand(a, env) for a in c.get("command", []) + c.get("args", [])]
if mode == "cmd":
    sys.stdout.write(argv[int(sys.argv[4])] + "\n")
elif mode == "argv":
    sys.stdout.write("".join(a + "\0" for a in argv))
elif mode == "env":
    if sys.argv[4] in env:
        sys.stdout.write(env[sys.argv[4]] + "\n")
PY
# kodd.py <job.json> — экранирование без исполнения: в command, args и value env КАЖДОГО
# контейнера Job (init — тоже) $ стоят лишь парами. Печатает «нечётных N · строк с $ M
# (init K)» и места нечётных серий.
cat > "$BOX/kodd.py" <<'PY'
import json, re, sys
sp = json.load(open(sys.argv[1]))["spec"]["template"]["spec"]
odd, withd, initd, where = 0, 0, 0, []
for kind in ("initContainers", "containers"):
    for c in sp.get(kind, []):
        vals = [("command", a) for a in c.get("command", [])] + [("args", a) for a in c.get("args", [])]
        vals += [("env " + e["name"], e["value"]) for e in c.get("env", []) if "value" in e]
        for field, v in vals:
            if "$" not in v:
                continue
            withd += 1
            initd += kind == "initContainers"
            if any(len(m) % 2 for m in re.findall(r"\$+", v)):
                odd += 1
                where.append(c["name"] + ": " + field)
print("нечётных %d · строк с $ %d (init %d)%s" % (odd, withd, initd, "".join(" · " + w for w in where)))
PY
# kx cmd <job.json> <контейнер> <номер> | argv <job.json> <контейнер> | env <job.json> <контейнер> <имя>
kx() { python3 "$BOX/kexpand.py" "$@" 2>/dev/null; }

# go <имя> — запуск run.sh в окружении двойника; код — в RC, вывод — в OUT.
go_run() {
    local name="$1"; shift
    OUT="$BOX/$name.out"
    # Срок — чтобы дефект, на котором run.sh ждёт свои 1800 с, краснел, а не висел.
    timeout 90 env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" \
        KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "$@" > "$OUT" 2>&1
    RC=$?
    cat "$OUT" >> "$ALL_OUT"
}
base() { printf '%s\n' bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile lint; }

ok() { PASS=$((PASS + 1)); }
bad() { printf 'ПРОВАЛ %s: %s\n' "$1" "$2"; [ -n "${OUT:-}" ] && sed 's/^/    /' "$OUT"; FAIL=$((FAIL + 1)); }
expect_rc() { if [ "$RC" -eq "$2" ]; then ok; else bad "$1" "код $RC, ждали $2"; fi; }
ns_left() { find "$BOX/state/ns" -type f | wc -l; }
expect_ns_gone() {
    if [ "$(ns_left)" -eq 0 ] && grep -qx "$2" "$BOX/state/deleted" 2>/dev/null; then ok; else bad "$1" "ns $2 не снято (осталось $(ns_left))"; fi
}
# no_cluster_call <случай> — отказ до любого создания: к двойнику ни одного обращения.
no_cluster_call() {
    if [ -s "$BOX/state/calls" ]; then bad "$1" "к кластеру обращались: $(head -n 1 "$BOX/state/calls")"; else ok; fi
}

mapfile -t B < <(base)

# K1
fresh
go_run k1 env FAKE_EXIT=0 "${B[@]}" --short k1 -- true
expect_rc K1 0
expect_ns_gone K1 t1-heavy-k1
# A1 — стенд держит пространство, а не узел (решение владельца 2026-10-09): Job в
# своём ns, без условий узла по стенду, ресурсы run — числом.
J="$BOX/state/job.json"
if [ "$(jq -r '.metadata.namespace' "$J" 2>/dev/null)" = t1-heavy-k1 ]; then ok
else OUT="$J"; bad A1 "Job не в ns прогона t1-heavy-k1"; fi
if jq -e '.spec.template.spec | (has("affinity") or has("nodeSelector") or has("nodeName"))' "$J" >/dev/null 2>&1; then
    OUT="$J"; bad A1 "в Job есть условие узла (affinity/nodeSelector/nodeName) — стенд держит ns, а не узел"
else ok; fi
if jq -e '[.. | strings | select(. == "kacho")] | length > 0' "$J" >/dev/null 2>&1; then
    OUT="$J"; bad A1 "Job называет ns kacho"
else ok; fi
if jq -e '.spec.template.spec.containers[0].resources | (.requests.cpu and .requests.memory and .limits.cpu and .limits.memory)' "$J" >/dev/null 2>&1; then ok
else OUT="$J"; bad A1 "у run нет запросов и пределов cpu и памяти числом"; fi
# A1 — ни одна изменяющая команда не адресована ns kacho (чтение служб для пробы
# закрытости — законно); близнец — изменяющие команды прогона в его ns были
grep -E '(^| )(create|apply|delete|exec|patch|label|annotate)( |$)' "$BOX/state/calls" > "$BOX/mutating.calls"
if grep -qE '(-n kacho( |$)|ns kacho( |$))' "$BOX/mutating.calls"; then
    bad A1 "изменяющая команда адресована ns kacho"
else ok; fi
grep -E '(^| )(exec|delete)( |$)' "$BOX/state/calls" > "$BOX/own.calls"
if grep -qE '(-n t1-heavy-k1 |ns t1-heavy-k1)' "$BOX/own.calls"; then ok
else bad A1 "изменяющих команд в ns прогона не видно — проверка выше пуста"; fi
# X1 — current-context файла смотрит на infra (опыт 2026-10-09), прогон K1 всё
# равно в client: КАЖДЫЙ вызов kubectl, кроме чтения списка контекстов, несёт
# --context <client>; ни одного без него и ни одного в infra. Двойник в контексте
# не -client отклоняет изменяющие запросы, как политика допуска infra, — K1 с кодом 0
# уже это подтверждает; здесь — перепись вызовов.
n_calls="$(grep -vc ' config get-contexts ' "$BOX/state/calls")"
n_client="$(grep -v ' config get-contexts ' "$BOX/state/calls" | grep -c -- "--context $CTX_CLIENT ")"
if [ "$n_calls" -gt 0 ] && [ "$n_calls" -eq "$n_client" ]; then ok
else bad X1 "вызовов kubectl $n_calls, с --context client $n_client"; fi
if grep -q -- "$CTX_INFRA" "$BOX/state/calls"; then bad X1 "вызов в контексте infra"; else ok; fi
if [ "$(jq -r '."current-context"' "$BOX/kubeconfig")" = "$CTX_INFRA" ]; then ok; else bad X1 "current-context кубконфига изменён"; fi
# N1 — сеть ns: входящих нет, исходящие — DNS и мир без частных, узлов и служб (F2)
NP="$BOX/state/netpol.json"
if jq -e --arg n4 "$FAKE_NODE_IP/32" --arg n6 "$FAKE_NODE_IP6/128" --arg a4 "$FAKE_API_IP/32" '
     .spec.podSelector == {} and (.spec.policyTypes | sort) == ["Egress", "Ingress"] and (.spec.ingress // []) == []
     and ([.spec.egress[].to[]] | all(.ipBlock or (.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "dns-sys" and .podSelector.matchLabels["k8s-app"] == "dns")))
     and ([.spec.egress[] | select(any(.to[]; .namespaceSelector)) | .ports[] | "\(.protocol)/\(.port)"] | sort) == ["TCP/53", "UDP/53"]
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "0.0.0.0/0") | .except[]] as $e
          | (["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16", $n4, $a4, "10.96.0.0/12"] - $e) == [])
     and ([.spec.egress[].to[] | .ipBlock | select(.cidr == "::/0") | .except[]] as $e | (["fc00::/7", "fe80::/10", $n6] - $e) == [])' "$NP" >/dev/null 2>&1; then ok
else OUT="$NP"; bad N1 "сетевой политики ns нет либо она пропускает кластер"; fi
# P1 — проба закрытости в pod: служба ns kacho, НЕ закрытая собственной политикой kacho
# (edge закрыта политикой kacho — близнец, который выбран быть не должен)
if [ "$(jq -r '.spec.template.spec.containers[0].env[] | select(.name == "HEAVY_DENY_PROBE") | .value' "$J" 2>/dev/null)" = "svc-a.kacho.svc:9090" ]; then ok
else OUT="$J"; bad P1 "HEAVY_DENY_PROBE не svc-a.kacho.svc:9090"; fi
# U0 — профиль без dind: pod тоже в своём пространстве пользователей
if jq -e '.spec.template.spec.hostUsers == false' "$J" >/dev/null 2>&1; then ok; else OUT="$J"; bad U0 "hostUsers не false"; fi

# U1 — профиль с dind: privileged нет ни у одного контейнера, pod в userns, dind на crun без cgroup (F1)
fresh
go_run u1 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short u1 -- true
expect_rc U1 0
if jq -e '.spec.template.spec.hostUsers == false
          and ([.. | objects | select(has("privileged")) | .privileged] | all(. == false))
          and ([.spec.template.spec.initContainers[] | select(.name == "dind")] | length == 1)
          and (.spec.template.spec.initContainers[] | select(.name == "dind") | .securityContext.privileged == false
               and (.command | join(" ") | test("crun.*--cgroup-manager=disabled")))' "$J" >/dev/null 2>&1; then ok
else OUT="$J"; bad U1 "dind привилегирован либо pod не в своём пространстве пользователей"; fi
cp "$J" "$BOX/u1-job.json"

# ── пространство пользователей ИСПОЛНЕНИЕМ (ревью ws#984, N1) ───────────────
# no_delivery <случай> — исходники в pod не ушли: кода ветки там не было.
no_delivery() { if [ -e "$BOX/state/bundle" ]; then bad "$1" "исходники доставлены до отказа"; else ok; fi; }
# S0 — законный близнец: сервер добавил свои умолчания (procMount Default и пр.) → 0
fresh
go_run s0 env FAKE_EXIT=0 FAKE_POD_MUT=defaults bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s0 -- true
expect_rc S0 0
# S1 — API-сервер молча снял hostUsers (в Job и pod) → 69, ns снято и при --keep, доставки нет
fresh
go_run s1 env FAKE_EXIT=0 FAKE_DROP_HOSTUSERS=1 bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s1 --keep 2 -- true
expect_rc S1 69
expect_ns_gone S1 t1-heavy-s1
no_delivery S1
if grep -q 'hostUsers снято' "$OUT"; then ok; else bad S1 "причина не названа (hostUsers)"; fi
# S2 — вебхук снял procMount у dind в pod (Job цел) → 69 до доставки
fresh
go_run s2 env FAKE_EXIT=0 FAKE_POD_MUT=procmount bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s2 -- true
expect_rc S2 69
expect_ns_gone S2 t1-heavy-s2
no_delivery S2
if grep -q 'контейнер dind: securityContext.procMount' "$OUT"; then ok; else bad S2 "причина не названа (procMount dind)"; fi
# S3 — вебхук сделал fetch привилегированным → 69 до доставки
fresh
go_run s3 env FAKE_EXIT=0 FAKE_POD_MUT=privileged bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short s3 -- true
expect_rc S3 69
no_delivery S3
if grep -q 'контейнер fetch: privileged без запроса' "$OUT"; then ok; else bad S3 "причина не названа (privileged fetch)"; fi

# U2 — проверка в pod: текст берётся из Job (команда dind и run), стоит ПЕРВЫМ и
# исполняется над поддельным /proc: sh — как busybox dind, bash — как run.
UJ="$BOX/u1-job.json"; UP="$BOX/uproc"; mkdir -p "$UP"
kx cmd "$UJ" dind 2 > "$BOX/dind.cmd"
kx cmd "$UJ" run 2 > "$BOX/run.cmd"
sed -n '1,/^# userns-end$/p' "$BOX/dind.cmd" > "$BOX/userns.sh"
if grep -q '^# userns-end$' "$BOX/userns.sh" && [ "$(sed -n '1,/^# userns-end$/p' "$BOX/run.cmd")" = "$(cat "$BOX/userns.sh")" ] \
   && [[ "$(head -n 1 "$BOX/userns.sh")" == 'uf() '* ]]; then ok
else OUT="$BOX/dind.cmd"; bad U2 "проверка userns не стоит первой строкой dind и run одним текстом"; fi
sed -e "s#/proc/self/#$UP/#g" -e "s#/dev/termination-log#$UP/tl#g" "$BOX/userns.sh" > "$BOX/userns-fake.sh"
# userns_case <случай> <оболочка> <uid_map> <gid_map> <код>
userns_case() {
    printf '%s\n' "$3" > "$UP/uid_map"; printf '%s\n' "$4" > "$UP/gid_map"; rm -f "$UP/tl"
    OUT="$BOX/$1.out"; "$2" "$BOX/userns-fake.sh" > "$OUT" 2>&1; RC=$?
    expect_rc "$1" "$5"
    if [ "$5" -ne 0 ]; then
        if grep -q '^remote-heavy-userns: ' "$UP/tl" 2>/dev/null; then ok; else bad "$1" "отказ не записан в termination-log"; fi
    fi
}
LEGIT="0 1879048192 65536"
for sh_ in sh bash; do
    userns_case "U2-$sh_-identity" "$sh_" "0 0 4294967295" "$LEGIT" 125
    userns_case "U2-$sh_-root" "$sh_" "0 0 65536" "$LEGIT" 125
    userns_case "U2-$sh_-gid" "$sh_" "$LEGIT" "         0          0 4294967295" 125
    userns_case "U2-$sh_-tail" "$sh_" "$(printf '0 1879048192 65536\n65536 0 1')" "$LEGIT" 125
    userns_case "U2-$sh_-legit" "$sh_" "         0 1879048192      65536" "$LEGIT" 0
done
printf '0 0 4294967295\n' > "$UP/uid_map"; rm -f "$UP/tl"; sh "$BOX/userns-fake.sh" >/dev/null 2>&1
USERNS_MSG="$(cat "$UP/tl" 2>/dev/null)"
# U3 — двойник: dind с тождественным uid_map отказал (его текст из U2) → 69, ns снято, доставки нет
fresh
go_run u3 env FAKE_EXIT=0 FAKE_USERNS_DIND="$USERNS_MSG" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile integration --short u3 --keep 2 -- true
expect_rc U3 69
expect_ns_gone U3 t1-heavy-u3
no_delivery U3
if grep -q 'пространство пользователей pod не изолировано — dind: remote-heavy-userns:' "$OUT"; then ok; else bad U3 "отказ dind не прочитан"; fi
# U4 — run отказал той же проверкой (код 125, как у K6b) → 69, а не код команды
fresh
go_run u4 env FAKE_EXIT=125 FAKE_MSG="$USERNS_MSG" "${B[@]}" --short u4 -- true
expect_rc U4 69
expect_ns_gone U4 t1-heavy-u4

# ── среда конвейера в pod: helm и node (ws#996) ─────────────────────────────
# E1 ревизия с пинами, профиль с go test → Job несёт пины в окружении run, ставит
#    helm пина и node мажора пина с проверкой контрольной суммы, сверка среды
#    стоит перед командой; строка «Job создан» называет их
fresh
go_run e1 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref pins --src "$SRC" --profile integration --short e1 -- true
expect_rc E1 0
EJ="$BOX/state/job.json"; cp "$EJ" "$BOX/e1-job.json" 2>/dev/null
envv() { kx env "$1" run "$2"; }
if [ "$(envv "$EJ" HEAVY_HELM)" = v4.2.4 ] && [ "$(envv "$EJ" HEAVY_NODE)" = 26 ]; then ok
else OUT="$EJ"; bad E1 "пины в окружении run: helm «$(envv "$EJ" HEAVY_HELM)», node «$(envv "$EJ" HEAVY_NODE)», ждали v4.2.4 и 26"; fi
kx cmd "$EJ" run 2 > "$BOX/e1.cmd" 2>/dev/null
# shellcheck disable=SC2016  # ищется буквальный текст подготовки
if grep -q 'get.helm.sh/helm-$HEAVY_HELM-linux-' "$BOX/e1.cmd" && grep -q 'sha256sum -c' "$BOX/e1.cmd" \
   && grep -q 'nodejs.org/dist/' "$BOX/e1.cmd" && grep -q 'SHASUMS256.txt' "$BOX/e1.cmd"; then ok
else OUT="$BOX/e1.cmd"; bad E1 "установки helm и node с проверкой суммы в подготовке run нет"; fi
if awk '/^# tools-check$/ { c = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(c && e && c < e) }' "$BOX/e1.cmd"; then ok
else OUT="$BOX/e1.cmd"; bad E1 "сверки среды перед командой нет либо команда не своей строкой (за маркером — комментарий)"; fi
if grep -q 'Job создан: .*helm v4.2.4, node 26' "$BOX/e1.out"; then ok; else OUT="$BOX/e1.out"; bad E1 "строка «Job создан» не называет helm и node"; fi
# E2 сверка среды ИСПОЛНЕНИЕМ: текст из Job, PATH поддельный
sed -n '/^# tools-check$/,/^# tools-end$/p' "$BOX/e1.cmd" | sed "s#/dev/termination-log#$BOX/etl#g" > "$BOX/tools.sh"
ET="$BOX/etools"; mkdir -p "$ET"
fake_tool() { printf '#!/bin/sh\necho "%s"\n' "$2" > "$ET/$1"; chmod +x "$ET/$1"; }
# tools_case <случай> <helm|-> <node|-> <пин helm> <пин node> <код> [слово отказа]
tools_case() {
    rm -f "$ET"/* "$BOX/etl"
    [ "$2" = - ] || fake_tool helm "$2"; [ "$3" = - ] || fake_tool node "$3"
    OUT="$BOX/$1.out"
    env -i PATH="$ET:/usr/bin:/bin" HEAVY_HELM="$4" HEAVY_NODE="$5" bash "$BOX/tools.sh" > "$OUT" 2>&1; RC=$?
    expect_rc "$1" "$6"
    if [ "$6" -ne 0 ]; then
        if grep -q "^remote-heavy-prep: среда: $7" "$BOX/etl" 2>/dev/null; then ok; else bad "$1" "отказ «среда: $7» не записан в termination-log"; fi
    fi
}
if grep -q '^# tools-end$' "$BOX/tools.sh"; then ok; else OUT="$BOX/e1.cmd"; bad E2 "текста сверки среды в Job нет — исполнять нечего"; fi
tools_case E2-helm-absent - v26.8.1 v4.2.4 26 125 helm
tools_case E2-helm-other v3.17.0+gabc v26.8.1 v4.2.4 26 125 helm
tools_case E2-helm-prefix v4.2.40+gabc v26.8.1 v4.2.4 26 125 helm
tools_case E2-node-absent v4.2.4+g3900f43 - v4.2.4 26 125 node
tools_case E2-node-other v4.2.4+g3900f43 v24.1.0 v4.2.4 26 125 node
tools_case E2-node-prefix v4.2.4+g3900f43 v260.1.0 v4.2.4 26 125 node
tools_case E2-legit v4.2.4+g3900f43 v26.8.1 v4.2.4 26 0
tools_case E2-nopins - - "" "" 0
# buf (ws#1110): сверка той же формы — нет, не та, версия-префикс → 125; верная → 0
buf_tools_case() {
    rm -f "$ET"/* "$BOX/etl"; [ "$2" = - ] || fake_tool buf "$2"
    OUT="$BOX/$1.out"
    env -i PATH="$ET:/usr/bin:/bin" HEAVY_BUF=1.72.0 bash "$BOX/tools.sh" > "$OUT" 2>&1; RC=$?
    expect_rc "$1" "$3"
    if [ "$3" -ne 0 ]; then
        if grep -q "^remote-heavy-prep: среда: buf" "$BOX/etl" 2>/dev/null; then ok; else bad "$1" "отказ «среда: buf» не записан в termination-log"; fi
    elif ! grep -q 'buf 1.72.0' "$OUT"; then bad "$1" "строка среды не называет buf 1.72.0"; else ok; fi
}
buf_tools_case E2-buf-absent - 125
buf_tools_case E2-buf-other 1.71.0 125
buf_tools_case E2-buf-prefix 1.72.01 125
buf_tools_case E2-buf-legit 1.72.0 0
# ── пакеты без apt (ws#1178) ─────────────────────────────────────────────────
# Подготовка pod не ходит на deb.debian.org: jq и PyYAML ставит шаг пакетов с пином
# суммы, psql и pg_dump приносит контейнер pgclient из образа postgres.
#   P1  ни один контейнер Job профиля с go test не зовёт apt и не называет зеркало
#       Debian; шаг пакетов (pkgs-begin) в run есть; близнец P1l — lint без пакетов
#   P4  pgclient — обычный контейнер из образа postgres:17-trixie ПОСЛЕ run, не init;
#       том tools смонтирован в pgclient и run; у lint ни pgclient, ни тома
#   P5  «подготовка pod до команды — N с» печатается до команды, отсчёт — с начала PREP
#   P2* шаг пакетов ИСПОЛНЕНИЕМ (текст из Job, curl и python3 — двойники, суммы
#       заменены на суммы двойных архивов — это же доказывает, что пин стоит в тексте
#       ровно один раз): чисто → jq и yaml на месте, apt не позван; близнецы — суммы
#       не сходятся, сеть мертва, архитектура чужая, всё уже есть (ничего не качается)
#   P3* контейнер pgclient ИСПОЛНЕНИЕМ над поддельным образом: бинари и
#       библиотеки (кроме семейства libc) в /tools, обёртки несут LD_LIBRARY_PATH
#       лишь на вызов, готов — файл ready; нет libpq либо psql — 125 и файл failed
#   P6* шаг pgwait ИСПОЛНЕНИЕМ: ждёт ready/failed, судит исполнение psql и pg_dump
EJ="$BOX/e1-job.json"
p_apt_count() { python3 - "$1" <<'PY'
import json, re, sys
sp = json.load(open(sys.argv[1]))["spec"]["template"]["spec"]
n = 0
for kind in ("initContainers", "containers"):
    for c in sp.get(kind, []):
        vals = list(c.get("command", [])) + list(c.get("args", [])) + [e.get("value", "") for e in c.get("env", [])]
        n += sum(1 for v in vals if re.search(r"\bapt(-get)?\b|deb\.debian\.org", v))
print(n)
PY
}
if [ "$(p_apt_count "$EJ")" = 0 ]; then ok; else OUT="$EJ"; bad P1 "в Job профиля с go test остался apt либо зеркало Debian (строк: $(p_apt_count "$EJ"))"; fi
if grep -q '^# pkgs-begin$' "$BOX/e1.cmd" && grep -q '^# pkgs-end$' "$BOX/e1.cmd"; then ok; else OUT="$BOX/e1.cmd"; bad P1 "шага пакетов (pkgs-begin … pkgs-end) в подготовке run нет"; fi
fresh
go_run p1l env FAKE_EXIT=0 "${B[@]}" --short p1l -- true
cp "$BOX/state/job.json" "$BOX/p1l-job.json" 2>/dev/null
kx cmd "$BOX/p1l-job.json" run 2 > "$BOX/p1l.cmd"
if ! grep -q '^# pkgs-begin$' "$BOX/p1l.cmd" && [ -s "$BOX/p1l.cmd" ]; then ok; else OUT="$BOX/p1l.cmd"; bad P1l "lint ставит пакеты — ему jq, yaml и клиент postgres не нужны"; fi
p_spec() { python3 - "$1" <<'PY'
import json, sys
sp = json.load(open(sys.argv[1]))["spec"]["template"]["spec"]
ini = [c["name"] for c in sp.get("initContainers", [])]
names = [c["name"] for c in sp["containers"]]
pg = next((c for c in sp["containers"] if c["name"] == "pgclient"), None)
run = next(c for c in sp["containers"] if c["name"] == "run")
tm = lambda c: any(m["name"] == "tools" and m["mountPath"] == "/tools" for m in c.get("volumeMounts", []))
vol = any(v["name"] == "tools" for v in sp.get("volumes", []))
print("pg=%d image=%s init=%d after_run=%d pg_mount=%d run_mount=%d volume=%d" % (
    pg is not None, (pg or {}).get("image", "-"), "pgclient" in ini,
    pg is not None and names.index("pgclient") > names.index("run"), tm(pg) if pg else 0, tm(run), vol))
PY
}
if [ "$(p_spec "$EJ")" = "pg=1 image=mirror.gcr.io/library/postgres:17-trixie init=0 after_run=1 pg_mount=1 run_mount=1 volume=1" ]; then ok
else OUT="$EJ"; bad P4 "pgclient в Job: $(p_spec "$EJ")"; fi
if [ "$(p_spec "$BOX/p1l-job.json")" = "pg=0 image=- init=0 after_run=0 pg_mount=0 run_mount=0 volume=0" ]; then ok
else OUT="$BOX/p1l-job.json"; bad P4l "pgclient либо том tools в Job lint: $(p_spec "$BOX/p1l-job.json")"; fi
# P4k — образ клиента postgres подменяется KACHO_REMOTE_HEAVY_PG_IMAGE; вне формы — 64 до кластера
fresh
go_run p4k env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_PG_IMAGE=mirror.gcr.io/library/postgres:16-trixie bash "$RUN" --task 1 --repo kaname --ref pins --src "$SRC" --profile integration --short p4k -- true
if [ "$(p_spec "$BOX/state/job.json")" = "pg=1 image=mirror.gcr.io/library/postgres:16-trixie init=0 after_run=1 pg_mount=1 run_mount=1 volume=1" ]; then ok
else OUT="$BOX/state/job.json"; bad P4k "образ pgclient не подменён: $(p_spec "$BOX/state/job.json")"; fi
fresh
go_run p4kb env KACHO_REMOTE_HEAVY_PG_IMAGE="postgres 16" "${B[@]}" --short p4kb -- true
expect_rc P4kb 64
no_cluster_call P4kb
# P7 — срок Job: команда (по умолчанию 5400 с) плюс 1800 с до начала (pull, dind, доставка)
if [ "$(jq -r '.spec.activeDeadlineSeconds' "$EJ")" = 7200 ]; then ok; else OUT="$EJ"; bad P7 "срок Job $(jq -r '.spec.activeDeadlineSeconds' "$EJ") с, ждали 5400 + 1800"; fi
# P5 — число «до/после» печатается и стоит перед командой
if awk '/PT0=\$\(date \+%s\)/ { a = NR } /подготовка pod до команды/ { b = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(a && b && e && a < b && b < e) }' "$BOX/e1.cmd"; then ok
else OUT="$BOX/e1.cmd"; bad P5 "времени подготовки до команды в тексте run нет либо оно стоит после команды"; fi

# P2 — шаг пакетов исполнением
PW="$BOX/pw"; PS="$BOX/pstub"
sed -n '/^# pkgs-begin$/,/^# pkgs-end$/p' "$BOX/e1.cmd" > "$BOX/pkgs.raw"
if grep -q '^# pkgs-end$' "$BOX/pkgs.raw"; then ok; else OUT="$BOX/e1.cmd"; bad P2 "текста шага пакетов в Job нет — исполнять нечего"; fi
rm -rf "$BOX/passets"; mkdir -p "$BOX/passets/pyyaml-6.0.2/lib/yaml"
printf '#!/bin/sh\necho jq-1.7.1\n' > "$BOX/passets/jq"
printf '# yaml\n' > "$BOX/passets/pyyaml-6.0.2/lib/yaml/__init__.py"
tar -czf "$BOX/passets/pyyaml.tgz" -C "$BOX/passets" pyyaml-6.0.2
printf 'другие байты\n' > "$BOX/passets/other"
JQSUM="$(sha256sum < "$BOX/passets/jq" | cut -d' ' -f1)"; YSUM="$(sha256sum < "$BOX/passets/pyyaml.tgz" | cut -d' ' -f1)"
# Пины в тексте: у jq две суммы (amd64, arm64), у PyYAML одна, каждая — РОВНО раз.
pins_jq="$(grep -oE '(js=)[0-9a-f]{64}' "$BOX/pkgs.raw" | wc -l)"; pins_y="$(grep -oE 'pyyaml.tgz [0-9a-f]{64}' "$BOX/pkgs.raw" | wc -l)"
if [ "$pins_jq" = 2 ] && [ "$pins_y" = 1 ]; then ok; else OUT="$BOX/pkgs.raw"; bad P2 "пинов сумм в тексте: jq $pins_jq (ждали 2), PyYAML $pins_y (ждали 1)"; fi
sed -E -e "s/(js=)[0-9a-f]{64}/\1$JQSUM/" -e "s/(pyyaml.tgz )[0-9a-f]{64}/\1$YSUM/" -e "s#/work#$PW#g" "$BOX/pkgs.raw" > "$BOX/pkgs.body"
# shellcheck disable=SC2016  # текст шага для исполнения в песочнице, не здесь
{ echo 'pf() { echo "remote-heavy-prep: $1" >&2; exit 125; }'; cat "$BOX/pkgs.body"; } > "$BOX/pkgs.sh"
# p_stubs — двойники curl, python3, apt-get; uname — по STUB_UNAME
p_stubs() {
    rm -rf "$PW" "$PS"; mkdir -p "$PW/bin" "$PS"
    cat > "$PS/curl" <<'STUB'
#!/bin/sh
o=""; u=""
while [ "$#" -gt 0 ]; do case "$1" in -o|--retry|--retry-delay|--connect-timeout|--max-time) [ "$1" = -o ] && o="$2"; shift 2 ;; -*) shift ;; *) u="$1"; shift ;; esac; done
echo "$u" >> "$P_LOG"
[ -z "$STUB_NET_DOWN" ] || { echo "curl: (22) нет сети" >&2; exit 22; }
case "$u" in
  *jq-linux-*) if [ -n "$STUB_BAD_JQ" ]; then cat "$P_ASSETS/other" > "$o"; else cat "$P_ASSETS/jq" > "$o"; fi ;;
  *pyyaml-6.0.2.tar.gz) if [ -n "$STUB_BAD_YAML" ]; then cat "$P_ASSETS/other" > "$o"; else cat "$P_ASSETS/pyyaml.tgz" > "$o"; fi ;;
  *) echo "curl: чужой адрес $u" >&2; exit 22 ;;
esac
STUB
    cat > "$PS/python3" <<'STUB'
#!/bin/sh
ok=0; [ -z "$STUB_YAML" ] || ok=1
OLDIFS="$IFS"; IFS=:; for d in $PYTHONPATH; do [ -f "$d/yaml/__init__.py" ] && ok=1; done; IFS="$OLDIFS"
[ "$ok" = 1 ] || { echo "ModuleNotFoundError: No module named 'yaml'" >&2; exit 1; }
case "$*" in *__version__*) echo 6.0.2 ;; esac
STUB
    # shellcheck disable=SC2016  # тексты двойников: раскрываются при их запуске
    printf '#!/bin/sh\necho позван >> "$P_APT"\nexit 1\n' > "$PS/apt-get"; cp "$PS/apt-get" "$PS/apt"
    # shellcheck disable=SC2016  # текст двойника
    printf '#!/bin/sh\n[ -n "$STUB_UNAME" ] && echo "$STUB_UNAME" || exec /usr/bin/uname "$@"\n' > "$PS/uname"
    chmod +x "$PS"/*
    # PATH песочницы — лишь перечисленное: jq, curl, python3 и apt машины в неё не входят
    # (иначе «jq уже есть» пропускало бы загрузку и проба P2 судила бы машину, а не шаг)
    local t
    for t in bash cat gzip head install mkdir rm sha256sum tar tr cut; do ln -sf "$(command -v "$t")" "$PS/$t"; done
    : > "$BOX/p.log"; rm -f "$BOX/p.apt" "$BOX/p.etl"
}
# p_run <случай> <ожидаемый код> [VAR=знач…] — шаг пакетов в песочнице; нужные двойники — PATH
p_run() {
    local n="$1" want="$2"; shift 2
    OUT="$BOX/$n.out"
    env -i PATH="$PW/bin:$PS" P_LOG="$BOX/p.log" P_ASSETS="$BOX/passets" P_APT="$BOX/p.apt" "$@" bash "$BOX/pkgs.sh" > "$OUT" 2>&1; RC=$?
    cat "$OUT" >> "$ALL_OUT"
    expect_rc "$n" "$want"
}
# P2 — чисто: ни jq, ни yaml в образе → ставятся; apt не позван; адреса — не Debian
p_stubs; p_run P2 0
if [ -x "$PW/bin/jq" ] && [ "$("$PW/bin/jq" --version)" = jq-1.7.1 ] && [ -f "$PW/pylib/yaml/__init__.py" ]; then ok; else bad P2 "после шага нет исполняемого jq либо каталога yaml"; fi
if [ ! -e "$BOX/p.apt" ]; then ok; else bad P2 "шаг пакетов позвал apt"; fi
if grep -q 'github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-' "$BOX/p.log" && grep -q 'files.pythonhosted.org/.*pyyaml-6.0.2.tar.gz' "$BOX/p.log" && ! grep -qi debian "$BOX/p.log"; then ok
else OUT="$BOX/p.log"; bad P2 "адреса загрузок не те: jq с GitHub и PyYAML с PyPI, без Debian"; fi
if grep -q 'инструменты без пакетного менеджера — jq-1.7.1, PyYAML 6.0.2' "$BOX/P2.out"; then ok; else bad P2 "строка итога шага не называет версии"; fi
# P2a — arm64: берётся jq-linux-arm64
p_stubs; p_run P2a 0 STUB_UNAME=aarch64
if grep -q 'jq-linux-arm64' "$BOX/p.log"; then ok; else OUT="$BOX/p.log"; bad P2a "на aarch64 не взят jq-linux-arm64"; fi
# P2b — сумма jq не сходится: 125, jq не поставлен; P2g — то же для PyYAML
p_stubs; p_run P2b 125 STUB_BAD_JQ=1
if grep -q 'remote-heavy-prep: jq 1.7.1 не поставлен' "$BOX/P2b.out" && [ ! -e "$PW/bin/jq" ]; then ok; else bad P2b "порченый jq принят либо отказ не назван"; fi
p_stubs; p_run P2g 125 STUB_BAD_YAML=1
if grep -q 'remote-heavy-prep: PyYAML 6.0.2 не поставлен' "$BOX/P2g.out" && [ ! -e "$PW/pylib/yaml" ]; then ok; else bad P2g "порченый PyYAML принят либо отказ не назван"; fi
# P2d — сети нет: 125, а не тихий пропуск
p_stubs; p_run P2d 125 STUB_NET_DOWN=1
if grep -q 'remote-heavy-prep: jq 1.7.1 не поставлен' "$BOX/P2d.out"; then ok; else bad P2d "отказ сети не назван отказом jq (проглоченная загрузка прячется за соседним отказом)"; fi
# P2f — чужая архитектура
p_stubs; p_run P2f 125 STUB_UNAME=riscv64
if grep -q 'jq: архитектура riscv64 не поддержана' "$BOX/P2f.out"; then ok; else bad P2f "чужая архитектура не отвергнута"; fi
# P2c — близнец: jq и yaml уже есть → ничего не качается
p_stubs; printf '#!/bin/sh\necho jq-1.7.1\n' > "$PS/jq"; chmod +x "$PS/jq"
p_run P2c 0 STUB_YAML=1
if [ ! -s "$BOX/p.log" ]; then ok; else OUT="$BOX/p.log"; bad P2c "инструменты уже есть, а шаг качает"; fi

# P3 — init-контейнер pgclient исполнением над поддельным образом postgres
PG="$BOX/pgimg"
kx cmd "$EJ" pgclient 2 > "$BOX/pg.raw"
if grep -q 'pgf()' "$BOX/pg.raw"; then ok; else OUT="$BOX/pg.raw"; bad P3 "текста init-контейнера pgclient в Job нет — исполнять нечего"; fi
sed -e "s#/dev/termination-log#$PG.tl#g" -e "s#/tools#$PG/tools#g" -e "s#/usr/lib/postgresql#$PG/usr/lib/postgresql#g" "$BOX/pg.raw" > "$BOX/pg.sh"
# pg_image <без libpq?> <без psql?> — поддельный образ: 16 и 17 (берётся старшая), библиотеки, ldd
pg_image() {
    rm -rf "$PG" "$PG.tl" "$BOX/pgbin"; mkdir -p "$PG/usr/lib/x86_64-linux-gnu" "$BOX/pgbin"
    local v x
    for v in 16 17; do
        mkdir -p "$PG/usr/lib/postgresql/$v/bin"
        for x in psql pg_dump pg_dumpall pg_restore pg_isready; do
            [ "$x" = psql ] && [ "$2" = nopsql ] && [ "$v" = 17 ] && continue
            # shellcheck disable=SC2016  # текст двойника: LD_LIBRARY_PATH раскрывается при его запуске
            printf '#!/bin/sh\necho "%s %s LD=$LD_LIBRARY_PATH"\n' "$x" "$v" > "$PG/usr/lib/postgresql/$v/bin/$x"
            chmod +x "$PG/usr/lib/postgresql/$v/bin/$x"
        done
    done
    for x in libpq.so.5.17 libssl.so.3 libc.so.6 libm.so.6 libnss_files.so.2 libpthread.so.0 ld-linux-x86-64.so.2; do echo "$x" > "$PG/usr/lib/x86_64-linux-gnu/$x"; done
    ln -s libpq.so.5.17 "$PG/usr/lib/x86_64-linux-gnu/libpq.so.5"
    {
        echo '#!/bin/sh'
        echo "echo '	linux-vdso.so.1 (0x00007ffd)'"
        [ "$1" = nolibpq ] || echo "echo '	libpq.so.5 => $PG/usr/lib/x86_64-linux-gnu/libpq.so.5 (0x00007f01)'"
        for x in libssl.so.3 libc.so.6 libm.so.6 libnss_files.so.2 libpthread.so.0; do echo "echo '	$x => $PG/usr/lib/x86_64-linux-gnu/$x (0x00007f02)'"; done
        echo "echo '	/lib64/ld-linux-x86-64.so.2 (0x00007f03)'"
    } > "$BOX/pgbin/ldd"; chmod +x "$BOX/pgbin/ldd"
}
pg_run() {
    OUT="$BOX/$1.out"
    env -i PATH="$BOX/pgbin:/usr/bin:/bin" bash "$BOX/pg.sh" > "$OUT" 2>&1; RC=$?
    cat "$OUT" >> "$ALL_OUT"
    expect_rc "$1" "$2"
}
pg_image - -; pg_run P3 0
pgw=0; for x in psql pg_dump pg_dumpall pg_restore pg_isready; do [ -x "$PG/tools/$x" ] && pgw=$((pgw + 1)); done
if [ "$pgw" = 5 ]; then ok; else bad P3 "обёрток в /tools: $pgw из 5"; fi
if [ -f "$PG/tools/pg/lib/libpq.so.5" ] && [ -f "$PG/tools/pg/lib/libssl.so.3" ] && [ "$(cat "$PG/tools/pg/lib/libpq.so.5")" = libpq.so.5.17 ]; then ok
else bad P3 "libpq.so.5 (по ссылке — содержимым) и libssl среди библиотек клиента не лежат"; fi
if [ -f "$PG/tools/pg/ready" ] && [ ! -e "$PG/tools/pg/failed" ]; then ok; else bad P3 "после успеха нет файла ready либо есть failed"; fi
if [ ! -e "$PG/tools/pg/lib/libc.so.6" ] && [ ! -e "$PG/tools/pg/lib/libm.so.6" ] && [ ! -e "$PG/tools/pg/lib/libnss_files.so.2" ] && [ ! -e "$PG/tools/pg/lib/libpthread.so.0" ]; then ok
else bad P3 "в библиотеки клиента попало семейство libc — ABI берётся из образа golang"; fi
# старшая major: 17, а не 16; библиотечный путь — на вызов обёртки, не на вызывающего
pgo="$(env -i PATH="/usr/bin:/bin" LD_LIBRARY_PATH=вызывающий "$PG/tools/psql" --version 2>&1)"
if [ "$pgo" = "psql 17 LD=$PG/tools/pg/lib" ]; then ok; else bad P3 "обёртка psql: «$pgo», ждали «psql 17 LD=$PG/tools/pg/lib» (старшая major и свой путь библиотек)"; fi
if [ "$(env -i PATH="/usr/bin:/bin" LD_LIBRARY_PATH=вызывающий bash -c "$PG/tools/psql >/dev/null; echo \$LD_LIBRARY_PATH")" = вызывающий ]; then ok; else bad P3 "обёртка меняет библиотечный путь вызывающего"; fi
pg_image nolibpq -; pg_run P3b 125
if grep -q 'remote-heavy-prep: pgclient: libpq.so.5 среди библиотек клиента не найдена' "$PG.tl"; then ok; else bad P3b "нет libpq — отказ не записан в termination-log"; fi
if grep -q 'libpq.so.5 среди библиотек клиента не найдена' "$PG/tools/pg/failed" 2>/dev/null && [ ! -e "$PG/tools/pg/ready" ]; then ok; else bad P3b "отказ не записан файлом failed с причиной либо рядом лежит ready"; fi
pg_image - nopsql; pg_run P3c 125
if grep -q 'remote-heavy-prep: pgclient: .*/psql в образе postgres нет' "$PG.tl"; then ok; else bad P3c "нет psql в образе — отказ не записан в termination-log"; fi

# P6 — шаг pgwait исполнением (ожидание клиента postgres перед командой)
sed -n '/^# pgwait-begin$/,/^# pgwait-end$/p' "$BOX/e1.cmd" > "$BOX/pgwait.raw"
if grep -q '^# pgwait-end$' "$BOX/pgwait.raw"; then ok; else OUT="$BOX/e1.cmd"; bad P6 "текста шага pgwait в Job нет — исполнять нечего"; fi
if ! grep -q '^# pgwait-begin$' "$BOX/p1l.cmd"; then ok; else OUT="$BOX/p1l.cmd"; bad P6l "lint ждёт клиент postgres, которого не получает"; fi
PGW="$BOX/pgw"; PGS="$BOX/pgwstub"
# shellcheck disable=SC2016  # текст шага для исполнения в песочнице
{ echo 'pf() { echo "remote-heavy-prep: $1" >&2; exit 125; }'; sed "s#/tools#$PGW/tools#g" "$BOX/pgwait.raw"; } > "$BOX/pgwait.sh"
# pgw_stubs — песочница: psql и pg_dump исполняются (PGW_BROKEN=psql — psql падает), маркеров нет
pgw_stubs() {
    rm -rf "$PGW" "$PGS"; mkdir -p "$PGW/tools/pg" "$PGS"
    printf '#!/bin/sh\necho "psql (PostgreSQL) 17.fake"\n' > "$PGS/psql"
    printf '#!/bin/sh\necho "pg_dump (PostgreSQL) 17.fake"\n' > "$PGS/pg_dump"
    [ "${1:-}" != broken ] || printf '#!/bin/sh\necho "psql: error while loading shared libraries: libpq.so.5" >&2\nexit 127\n' > "$PGS/psql"
    chmod +x "$PGS"/*
    local t; for t in bash sleep head cat; do ln -sf "$(command -v "$t")" "$PGS/$t"; done
}
pgw_run() {
    local n="$1" want="$2"; shift 2
    OUT="$BOX/$n.out"
    timeout 60 env -i PATH="$PGS" "$@" bash "$BOX/pgwait.sh" > "$OUT" 2>&1; RC=$?
    cat "$OUT" >> "$ALL_OUT"
    expect_rc "$n" "$want"
}
pgw_stubs; touch "$PGW/tools/pg/ready"; pgw_run P6 0
if grep -q 'клиент postgres — psql (PostgreSQL) 17.fake, ждал 0 с' "$BOX/P6.out"; then ok; else bad P6 "итог шага не называет клиент и ожидание 0 с"; fi
pgw_stubs; printf 'libpq.so.5 среди библиотек клиента не найдена\n' > "$PGW/tools/pg/failed"; pgw_run P6a 125
if grep -q 'remote-heavy-prep: pgclient: libpq.so.5 среди библиотек клиента не найдена' "$BOX/P6a.out"; then ok; else bad P6a "причина отказа pgclient не названа"; fi
pgw_stubs; pgw_run P6b 125 HEAVY_PG_WAIT_S=2
if grep -q 'клиент postgres не появился за 2 с' "$BOX/P6b.out"; then ok; else bad P6b "срок ожидания не назван отказом"; fi
# P6c — маркер приходит ПОЗЖЕ старта шага: шаг ждёт, а не проскакивает
pgw_stubs; ( timeout 20 bash -c "sleep 3; touch '$PGW/tools/pg/ready'" > /dev/null 2>&1 & )
pgw_run P6c 0 HEAVY_PG_WAIT_S=30
if grep -qE 'жду клиент postgres' "$BOX/P6c.out" && grep -qE 'ждал [2-9] с' "$BOX/P6c.out"; then ok; else bad P6c "шаг не дождался маркера, пришедшего через 3 с"; fi
# P6d — ready есть, а psql в образе golang не исполняется → отказ здесь, не красная проба
pgw_stubs broken; touch "$PGW/tools/pg/ready"; pgw_run P6d 125
if grep -q 'remote-heavy-prep: psql из образа postgres не исполняется в образе golang: psql: error while loading shared libraries' "$BOX/P6d.out"; then ok; else bad P6d "отказ psql не назван причиной"; fi
# D1 модули исходниками (ws#1018). Пакет deploy kacho читает исходник пиненного
#    kaname из GOMODCACHE, а сборка этот модуль не тянет: без шага загрузки кэш
#    Job его не содержит (32 отказа «stat /cache/mod/…: no such file»). Конвейер
#    делает `go mod download` до тестов; Job обязан тоже — каждого профиля.
modstep_in() { awk '/^# moddl-begin$/ { b = NR } /^# moddl-end$/ { m = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(b && m && e && b < m && m < e) }' "$1"; }
if modstep_in "$BOX/e1.cmd"; then ok; else OUT="$BOX/e1.cmd"; bad D1 "шага загрузки модулей перед командой в Job профиля integration нет"; fi
for prof in go-race ci-local lint; do
    fresh
    go_run "d1-$prof" env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile "$prof" --short "d1$prof" -- true
    expect_rc "D1-$prof" 0
    kx cmd "$BOX/state/job.json" run 2 > "$BOX/d1-$prof.cmd" 2>/dev/null
    if modstep_in "$BOX/d1-$prof.cmd"; then ok; else OUT="$BOX/d1-$prof.cmd"; bad "D1-$prof" "шага загрузки модулей перед командой в Job профиля $prof нет"; fi
done
# Исполнение: настоящий go, сеть — файловый прокси с модулем, который модуль
# дерева требует, но ни один его пакет не импортирует (форма пина kaname в kacho).
DM="$BOX/dm"; rm -rf "$DM"; mkdir -p "$DM/px/example.invalid/dep/@v" "$DM/z/example.invalid/dep@v0.1.0" "$DM/m/sub" "$DM/nomod"
printf 'module example.invalid/dep\n\ngo 1.22\n' > "$DM/z/example.invalid/dep@v0.1.0/go.mod"
printf 'package dep\n' > "$DM/z/example.invalid/dep@v0.1.0/dep.go"
( cd "$DM/z" && python3 -c 'import zipfile; z = zipfile.ZipFile("../px/example.invalid/dep/@v/v0.1.0.zip", "w"); [z.write("example.invalid/dep@v0.1.0/" + f) for f in ("go.mod", "dep.go")]' )
cp "$DM/z/example.invalid/dep@v0.1.0/go.mod" "$DM/px/example.invalid/dep/@v/v0.1.0.mod"
echo '{"Version":"v0.1.0"}' > "$DM/px/example.invalid/dep/@v/v0.1.0.info"; echo v0.1.0 > "$DM/px/example.invalid/dep/@v/list"
printf 'module example.invalid/m\n\ngo 1.22\n\nrequire example.invalid/dep v0.1.0\n' > "$DM/m/go.mod"
printf 'package m\n' > "$DM/m/m.go"; printf 'package sub\n' > "$DM/m/sub/sub.go"
# shellcheck disable=SC2016  # раскрывается в исполняемом тексте шага
{ echo 'pf() { echo "remote-heavy-prep: $1" | tee "$DM_TL" >&2; exit 125; }'; sed -n '/^# moddl-begin$/,/^# moddl-end$/p' "$BOX/e1.cmd"; } > "$BOX/moddl.sh"
DEP_SRC="$DM/cache/example.invalid/dep@v0.1.0/dep.go"
# moddl_case <случай> <каталог> <прокси> <код> <слово вывода либо отказа>
moddl_case() {
    rm -rf "$DM/cache" "$DM/tl"; OUT="$BOX/$1.out"
    ( cd "$2" && env GOMODCACHE="$DM/cache" GOPROXY="$3" GOSUMDB=off GOFLAGS=-modcacherw GOTOOLCHAIN=local \
        GOWORK=off DM_TL="$DM/tl" bash "$BOX/moddl.sh" ) > "$OUT" 2>&1; RC=$?
    expect_rc "$1" "$4"
    if [ "$4" -ne 0 ]; then
        if grep -q "^remote-heavy-prep: $5" "$DM/tl" 2>/dev/null; then ok; else bad "$1" "отказ «$5» не записан в termination-log"; fi
    elif ! grep -q "$5" "$OUT"; then bad "$1" "строка «$5» не напечатана"; else ok; fi
}
# Контроль предпосылки: сборка модуля дерева исходник dep в кэш НЕ кладёт — иначе
# проба шага пуста (тот же класс, что 32 отказа в pod).
rm -rf "$DM/cache"
( cd "$DM/m" && env GOMODCACHE="$DM/cache" GOPROXY="file://$DM/px" GOSUMDB=off GOFLAGS=-modcacherw GOTOOLCHAIN=local GOWORK=off go build ./... ) > "$BOX/d1-control.out" 2>&1
if [ ! -e "$DEP_SRC" ]; then ok; else OUT="$BOX/d1-control.out"; bad D1-control "сборка сама положила исходник dep в кэш — проба шага пуста"; fi
if grep -q '^# moddl-end$' "$BOX/moddl.sh"; then ok; else OUT="$BOX/e1.cmd"; bad D1 "текста шага загрузки в Job нет — исполнять нечего"; fi
moddl_case D1-exec "$DM/m/sub" "file://$DM/px" 0 'модули загружены'
if [ -f "$DEP_SRC" ]; then ok; else bad D1-exec "после шага исходника модуля, не импортированного сборкой, в кэше нет"; fi
moddl_case D1b "$DM/m" off 125 'модули'
moddl_case D1c "$DM/nomod" "file://$DM/px" 0 'качать нечего'
# NC зависимости консоли в Job хука отправки kacho (ws#1115). Отправка 3258
#    2026-10-16: хук отказал через 1328 с — ui-types «зависимости не установлены»
#    по 11 пакетам, pod — чистое дерево. Job профиля ci-local клона kacho ставит
#    их как ui.yml до хука, лишь когда правка трогает консоль (признак хука).
# NC1 форма Job: вход pre-push — в окружении run, шаг — после сверки среды и до
#     exec; близнецы — kaname ci-local и kacho go-race шага не несут; вход вне
#     формы — 64 до кластера
ZS=0000000000000000000000000000000000000000
PUSH_LINE="refs/heads/x $(git -C "$SRC" rev-parse HEAD) refs/heads/x $ZS"
npm_in() { awk '/^# tools-end$/ { t = NR } /^# npmci-begin$/ { b = NR } /^# npmci-end$/ { m = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(t && b && m && e && t < b && b < m && m < e) }' "$1"; }
fresh
go_run nc1 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kacho --ref HEAD --src "$SRC" --profile ci-local --short nc1 --push-input "$PUSH_LINE" -- true
expect_rc NC1 0
kx cmd "$BOX/state/job.json" run 2 > "$BOX/nc1.cmd" 2>/dev/null
if npm_in "$BOX/nc1.cmd"; then ok; else OUT="$BOX/nc1.cmd"; bad NC1 "шага зависимостей консоли между сверкой среды и exec в Job ci-local kacho нет"; fi
if [ "$(envv "$BOX/state/job.json" HEAVY_PUSH_INPUT)" = "$PUSH_LINE" ]; then ok
else OUT="$BOX/state/job.json"; bad NC1 "вход pre-push не дошёл до окружения run: «$(envv "$BOX/state/job.json" HEAVY_PUSH_INPUT)»"; fi
for tw in kaname:ci-local kacho:go-race; do
    tr_="${tw%%:*}"; tp="${tw#*:}"; fresh
    go_run "nc1-$tr_-$tp" env FAKE_EXIT=0 bash "$RUN" --task 1 --repo "$tr_" --ref HEAD --src "$SRC" --profile "$tp" --short "nc1$tp" --push-input "$PUSH_LINE" -- true
    expect_rc "NC1-$tr_-$tp" 0
    tw_cmd="$(kx cmd "$BOX/state/job.json" run 2)"
    if [[ $'\n'"$tw_cmd"$'\n' == *$'\n# npmci-begin\n'* ]]; then
        bad "NC1-$tr_-$tp" "шаг консоли в Job $tr_ $tp — он лишь у ci-local kacho"; else ok; fi
done
fresh
go_run nc1-badin env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kacho --ref HEAD --src "$SRC" --profile ci-local --short nc1b --push-input "x y z" -- true
expect_rc NC1-badin 64
if [ -s "$BOX/state/calls" ]; then bad NC1-badin "к кластеру обращались: $(head -n 1 "$BOX/state/calls")"; else ok; fi
# NC2 шаг ИСПОЛНЕНИЕМ: текст из Job над деревом пробы — ui.yml ревизии (рабочий
#     каталог и STANDALONE), консоль с членом workspace и двумя standalone,
#     производитель диапазона хука; npm и node — двойники: npm пишет, где и с чем
#     зван, и наполняет node_modules цели; node отвечает предикатом готовности
#     (член — корень, standalone — свой каталог), как deps-ready.mjs.
NT="$BOX/nct"; NB="$BOX/ncbin"; rm -rf "$NT" "$NB"; mkdir -p "$NB" "$NT/.github/workflows" "$NT/scripts/hooks" "$NT/ui-future/scripts"
git init -q "$NT"
printf 'defaults:\n  run:\n    working-directory: ui-future\nenv:\n  STANDALONE: host e2e\njobs: {}\n' > "$NT/.github/workflows/ui.yml"
printf '{"workspaces": ["shared"]}\n' > "$NT/ui-future/package.json"
for p in shared host e2e; do mkdir -p "$NT/ui-future/$p"; printf '{"name": "%s"}\n' "$p" > "$NT/ui-future/$p/package.json"; done
printf '// двойник: готовность судит node пробы\n' > "$NT/ui-future/scripts/deps-ready.mjs"
printf 'node_modules\n' > "$NT/.gitignore"
# Производитель диапазона — той же формы входа, что у хука; FAKE_RANGE_RC — отказ.
cat > "$NT/scripts/hooks/prepush-range.sh" <<'RANGE'
#!/usr/bin/env bash
[ -z "${FAKE_RANGE_RC:-}" ] || exit "$FAKE_RANGE_RC"
r=""
while read -r _ l _ rm; do
  [ -n "${l:-}" ] || continue
  case "$rm" in 0000000000000000000000000000000000000000) r="$r origin/main...$l" ;; *) r="$r $rm..$l" ;; esac
done
printf '%s\n' "${r# }"
RANGE
echo 'package x' > "$NT/x.go"
git -C "$NT" add -A; sandbox_git -C "$NT" commit -q -m base
git -C "$NT" update-ref refs/remotes/origin/main HEAD
NBASE="$(git -C "$NT" rev-parse HEAD)"
# nc_rev <ветка> <правка> — ревизия от базы с правкой (функция ниже); печатает sha
nc_rev() { git -C "$NT" checkout -q -b "$1" "$NBASE"; "$2"; git -C "$NT" add -A; sandbox_git -C "$NT" commit -q -m "$1"; git -C "$NT" rev-parse HEAD; }
edit_ui() { echo "export const a = 1" > "$NT/ui-future/host/a.ts"; }
edit_go() { echo "package x // y" > "$NT/x.go"; }
edit_nostd() { echo "export const b = 1" > "$NT/ui-future/host/b.ts"; printf 'defaults:\n  run:\n    working-directory: ui-future\njobs: {}\n' > "$NT/.github/workflows/ui.yml"; }
NC_UI="$(nc_rev ui edit_ui)"
NC_GO="$(nc_rev go edit_go)"
NC_NOSTD="$(nc_rev nostd edit_nostd)"
# Обновление опубликованной ветки (ревью ws#1115, V4): ствол ушёл вперёд правкой
# консоли, ветка (опубликована на NC_GO) влила его. Диапазон хука — NC_GO..слияние —
# консоль трогает; запасной origin/main...HEAD при стволе на NC_TRUNK — нет.
edit_trunk() { echo "export const t = 1" > "$NT/ui-future/shared/t.ts"; }
NC_TRUNK="$(nc_rev trunk edit_trunk)"
git -C "$NT" checkout -q -b merged "$NC_GO"
sandbox_git -C "$NT" merge -q --no-edit "$NC_TRUNK" > /dev/null 2>&1
NC_MERGED="$(git -C "$NT" rev-parse HEAD)"
git -C "$NT" checkout -q --detach "$NBASE"
cat > "$NB/npm" <<'NPM'
#!/usr/bin/env bash
pre=""; [ "${1:-}" = ci ] && [ "${2:-}" = --prefix ] && pre="$3"
echo "$(basename "$PWD")|$*" >> "$NC_NPM_LOG"
case " ${FAKE_NPM_FAIL:-} " in *" ${pre:-root} "*) echo "npm ERR! двойник: отказ ${pre:-root}" >&2; exit 1 ;; esac
case " ${FAKE_NPM_EMPTY:-} " in *" ${pre:-root} "*) exit 0 ;; esac
mkdir -p "$PWD/${pre:+$pre/}node_modules/dep"
NPM
cat > "$NB/node" <<'NODE'
#!/usr/bin/env bash
d="$2"; n="$(basename "$d")"; t="$d"
[ "$n" = shared ] && t="$(dirname "$d")"
[ -n "$(ls -A "$t/node_modules" 2>/dev/null)" ]
NODE
chmod +x "$NB/npm" "$NB/node"
# shellcheck disable=SC2016  # раскрывается в исполняемом тексте шага
nc_block() { { echo 'pf() { echo "remote-heavy-prep: $1" | tee "$NC_TL" >&2; exit 125; }'; sed -n '/^# npmci-begin$/,/^# npmci-end$/p' "$1"; } > "$2"; }
nc_block "$BOX/nc1.cmd" "$BOX/npmci.sh"
if grep -q '^# npmci-end$' "$BOX/npmci.sh"; then ok; else OUT="$BOX/nc1.cmd"; bad NC2 "текста шага консоли в Job нет — исполнять нечего"; fi
# nc_exec <шаг> <ревизия|-> [окружение…] — исполнить шаг в дереве на ревизии; код — NRC
nc_exec() {
    local sh="$1" rev="$2"; shift 2
    git -C "$NT" checkout -q --detach "$NBASE"; git -C "$NT" clean -qfdx
    rm -f "$BOX/nc.npm" "$BOX/nc.tl"
    local inp=""; [ "$rev" = - ] || inp="refs/heads/x $rev refs/heads/x ${NC_REMOTE:-$ZS}"
    [ "$rev" = - ] || git -C "$NT" checkout -q --detach "$rev"
    ( cd "$NT" && env -i HOME="$BOX" PATH="${NC_PATH:-$NB}:/usr/bin:/bin" NC_NPM_LOG="$BOX/nc.npm" NC_TL="$BOX/nc.tl" \
        HEAVY_PUSH_INPUT="$inp" "$@" bash "$sh" ) > "$NC_OUT" 2>&1
    NRC=$?
}
npm_calls() { [ -s "$BOX/nc.npm" ] && tr '\n' ';' < "$BOX/nc.npm" || echo нет; }
NC_WANT="ui-future|ci;ui-future|ci --prefix host;ui-future|ci --prefix e2e;"
# nc_console_holds <шаг> — правка консоли: код 0, npm ci как ui.yml по порядку, все
# пакеты готовы предикатом проверок. Код 0 — свойство держится.
nc_console_holds() {
    NC_OUT="$BOX/nc-ui.out"; nc_exec "$1" "$NC_UI"
    [ "$NRC" -eq 0 ] && [ "$(npm_calls)" = "$NC_WANT" ] && grep -q 'готовы пакетов 3 из 3' "$NC_OUT"
}
OUT="$BOX/nc-ui.out"
if nc_console_holds "$BOX/npmci.sh"; then ok
else bad NC2-console "правка консоли: код $NRC, npm «$(npm_calls)», ждали код 0, «$NC_WANT» и «готовы пакетов 3 из 3»"; fi
# nc_case <случай> <ревизия|-> <код> <npm: звался|нет> <слово вывода либо отказа> [окружение…]
nc_case() {
    local name="$1" rev="$2" want="$3" calls="$4" word="$5"; shift 5
    NC_OUT="$BOX/$name.out"; OUT="$NC_OUT"; nc_exec "$BOX/npmci.sh" "$rev" "$@"; RC="$NRC"
    expect_rc "$name" "$want"
    if [ "$calls" = нет ] && [ -s "$BOX/nc.npm" ]; then bad "$name" "npm звался: $(npm_calls)"; else ok; fi
    if [ "$want" -ne 0 ]; then
        if grep -q "^remote-heavy-prep: консоль: $word" "$BOX/nc.tl" 2>/dev/null; then ok; else bad "$name" "отказ «консоль: $word» не записан в termination-log"; fi
    elif grep -q "$word" "$NC_OUT"; then ok; else bad "$name" "строка «$word» не напечатана"; fi
}
nc_case NC2-noconsole "$NC_GO" 0 нет 'правка её не трогает'
nc_case NC2-nopush - 0 нет 'команда не отправка'
nc_case NC2-norange "$NC_UI" 0 нет 'диапазон отправки не выбран' FAKE_RANGE_RC=2
nc_case NC2-fail-root "$NC_UI" 125 звался 'npm ci в ui-future не исполнился' FAKE_NPM_FAIL=root
nc_case NC2-fail-e2e "$NC_UI" 125 звался 'npm ci --prefix e2e не исполнился' FAKE_NPM_FAIL=e2e
nc_case NC2-notready "$NC_UI" 125 звался 'после npm ci пакет host не готов' FAKE_NPM_EMPTY=host
nc_case NC2-nostd "$NC_NOSTD" 125 нет 'ui.yml ревизии не разобран'
# NC2-update: удалённый sha ненулевой — признак берётся из диапазона хука, а не из
# запасного origin/main...HEAD. Предпосылка случая проверяется: иначе он не различает.
git -C "$NT" update-ref refs/remotes/origin/main "$NC_TRUNK"
nc_upd_range="$(git -C "$NT" diff --name-only "$NC_GO..$NC_MERGED")"
nc_upd_fallback="$(git -C "$NT" diff --name-only "$NC_TRUNK...$NC_MERGED")"
if [[ "$nc_upd_range" == *ui-future/* ]] && [[ "$nc_upd_fallback" != *ui-future/* ]] && [ -n "$nc_upd_fallback" ]; then ok
else bad NC2-update "предпосылка: диапазон «$nc_upd_range» обязан трогать консоль, запасной «$nc_upd_fallback» — нет"; fi
NC_REMOTE="$NC_GO" nc_case NC2-update "$NC_MERGED" 0 звался 'готовы пакетов 3 из 3'
if [ "$(npm_calls)" = "$NC_WANT" ]; then ok; else bad NC2-update "npm «$(npm_calls)», ждали «$NC_WANT»"; fi
git -C "$NT" update-ref refs/remotes/origin/main "$NBASE"
NC_PATH="$BOX/ncnonpm"; mkdir -p "$NC_PATH"; cp "$NB/node" "$NC_PATH/"
nc_case NC2-nonpm "$NC_UI" 125 нет 'правка её трогает, а npm нет в PATH'
unset NC_PATH
# NC3 инъекция «npm ci снят»: тот же случай над шагом без вызова npm ci —
#     свойство NC2-console обязано НЕ держаться (иначе проба мимо предмета).
sed 's/&& npm ci/\&\& true/g' "$BOX/npmci.sh" > "$BOX/npmci-gone.sh"
if cmp -s "$BOX/npmci.sh" "$BOX/npmci-gone.sh"; then bad NC3 "порча не легла: «&& npm ci» в шаге не найден"
elif nc_console_holds "$BOX/npmci-gone.sh"; then OUT="$BOX/nc-ui.out"; bad NC3 "шаг без npm ci прошёл как поставивший зависимости — проба NC2-console слепа"
else ok; fi
# GI корневая учётка git в Job ci-local (ws#1115). Отправка 853 2026-10-16: страж
#    подписи хука kaname — «подпись НЕ сверена… корневая учётная запись не задана»:
#    в pod корневого gitconfig нет. Учётка вызывающей копии (--global) уходит в Job.
# GI1 учётка у копии есть, отправка → в окружении run имя и адрес, шаг записи —
#     до команды; адрес в вывод run.sh не попал
GI_NAME="Probe Signer"; GI_EMAIL="probe-signer@example.invalid"
printf '[user]\n\tname = %s\n\temail = %s\n' "$GI_NAME" "$GI_EMAIL" > "$BOX/gi.cfg"; : > "$BOX/gi-empty.cfg"
gi_in() { awk '/^# gitid-begin$/ { b = NR } /^# gitid-end$/ { m = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(b && m && e && b < m && m < e) }' "$1"; }
fresh
go_run gi1 env FAKE_EXIT=0 GIT_CONFIG_GLOBAL="$BOX/gi.cfg" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile ci-local --short gi1 --push-input "$PUSH_LINE" -- true
expect_rc GI1 0
kx cmd "$BOX/state/job.json" run 2 > "$BOX/gi1.cmd" 2>/dev/null
if [ "$(envv "$BOX/state/job.json" HEAVY_GIT_NAME)" = "$GI_NAME" ] && [ "$(envv "$BOX/state/job.json" HEAVY_GIT_EMAIL)" = "$GI_EMAIL" ]; then ok
else OUT="$BOX/state/job.json"; bad GI1 "учётка не дошла до окружения run: «$(envv "$BOX/state/job.json" HEAVY_GIT_NAME)» «$(envv "$BOX/state/job.json" HEAVY_GIT_EMAIL)»"; fi
if gi_in "$BOX/gi1.cmd"; then ok; else OUT="$BOX/gi1.cmd"; bad GI1 "шага записи учётки перед командой в Job ci-local нет"; fi
if grep -qF "$GI_EMAIL" "$BOX/gi1.out"; then bad GI1 "адрес учётки напечатан в выводе run.sh"; else ok; fi
# GI1-env: состав окружения КАЖДОГО контейнера Job — только разрешённые имена (до
#     правки учётки и вход pre-push плюс HEAVY_GIT_NAME/EMAIL); envFrom нет
GI_ALLOW="CI DOCKER_HOST GOCACHE GOLANGCI_LINT_CACHE GOMODCACHE GOTOOLCHAIN HEAVY_BUF HEAVY_DENY_PROBE HEAVY_GIT_EMAIL HEAVY_GIT_NAME HEAVY_HELM HEAVY_MAIN HEAVY_NODE HEAVY_PUSH_INPUT HEAVY_SHA HEAVY_WORKDIR TESTCONTAINERS_RYUK_DISABLED"
gi_extra="$(jq -r --arg a "$GI_ALLOW" '($a | split(" ")) as $al | [.spec.template.spec | (.containers[]?, .initContainers[]?) | (.env[]?.name), (if .envFrom then "envFrom" else empty end)] | unique | map(select(IN($al[]) | not)) | join(" ")' "$BOX/state/job.json" 2>/dev/null)" || gi_extra="(spec не разобран)"
if [ -z "$gi_extra" ]; then ok; else bad GI1-env "в окружении Job имена вне разрешённого списка: $gi_extra"; fi
# GI1-decoy: корневой gitconfig копии несёт приманки — ключ подписи, помощник
#     учётных данных, заголовок http, подмену адреса, включение; ни одна не доходит
#     до Job и до вывода
GI_DECOYS="DECOY-signingkey-7f3a DECOY-credhelper-7f3a DECOY-extraheader-7f3a DECOY-insteadof-7f3a DECOY-include-7f3a"
{ printf '[user]\n\tname = %s\n\temail = %s\n\tsigningkey = DECOY-signingkey-7f3a\n' "$GI_NAME" "$GI_EMAIL"
  printf '[credential]\n\thelper = DECOY-credhelper-7f3a\n[http]\n\textraHeader = Authorization: DECOY-extraheader-7f3a\n'
  printf '[url "https://DECOY-insteadof-7f3a.invalid/"]\n\tinsteadOf = https://github.com/\n[include]\n\tpath = %s/DECOY-include-7f3a.cfg\n' "$BOX"; } > "$BOX/gi-decoy.cfg"
fresh
go_run gi1-decoy env FAKE_EXIT=0 GIT_CONFIG_GLOBAL="$BOX/gi-decoy.cfg" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile ci-local --short gi1d --push-input "$PUSH_LINE" -- true
expect_rc GI1-decoy 0
if [ "$(envv "$BOX/state/job.json" HEAVY_GIT_NAME)" = "$GI_NAME" ]; then ok; else bad GI1-decoy "учётка с приманками рядом не дошла до Job — проба пуста"; fi
for d in $GI_DECOYS; do
    if grep -qF "$d" "$BOX/state/job.json" "$BOX/gi1-decoy.out" 2>/dev/null; then bad GI1-decoy "приманка «$d» из корневого gitconfig дошла до Job или вывода"; else ok; fi
done
# GI2 отправка, а корневой учётки у копии нет → 69 до кластера, причина названа;
#     близнец GI2b — не отправка → 0, Job без учётки, строка это называет
fresh
go_run gi2 env FAKE_EXIT=0 GIT_CONFIG_GLOBAL="$BOX/gi-empty.cfg" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile ci-local --short gi2 --push-input "$PUSH_LINE" -- true
expect_rc GI2 69
if [ -s "$BOX/state/calls" ]; then bad GI2 "к кластеру обращались: $(head -n 1 "$BOX/state/calls")"; else ok; fi
if grep -q 'нет корневой учётной записи' "$OUT"; then ok; else bad GI2 "причина «нет корневой учётной записи» не названа"; fi
# GI2-name-only, GI2-email-only — половина учётки — та же учётки нет: 69 до кластера
printf '[user]\n\tname = %s\n' "$GI_NAME" > "$BOX/gi-name.cfg"; printf '[user]\n\temail = %s\n' "$GI_EMAIL" > "$BOX/gi-email.cfg"
for half in name email; do
    fresh
    go_run "gi2-$half" env FAKE_EXIT=0 GIT_CONFIG_GLOBAL="$BOX/gi-$half.cfg" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile ci-local --short "gi2$half" --push-input "$PUSH_LINE" -- true
    expect_rc "GI2-$half-only" 69
    if [ -s "$BOX/state/calls" ]; then bad "GI2-$half-only" "к кластеру обращались: $(head -n 1 "$BOX/state/calls")"; else ok; fi
done
fresh
go_run gi2b env FAKE_EXIT=0 GIT_CONFIG_GLOBAL="$BOX/gi-empty.cfg" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile ci-local --short gi2b -- true
expect_rc GI2b 0
if [ -z "$(envv "$BOX/state/job.json" HEAVY_GIT_NAME)" ] && grep -q 'Job идёт без неё' "$OUT"; then ok; else bad GI2b "без учётки и не отправка: ждали Job без учётки и строку об этом"; fi
# GI3 шаг ИСПОЛНЕНИЕМ над HOME пробы: после него предикат стража подписи (корневая
#     «имя <адрес>» из --global равна подписи коммита, branch_rule_root_ident
#     kaname) держится; GI3b инъекция «учётка не передана» — тот же шаг без
#     окружения учётки: предикат не держится (прежний отказ «корневая не задана»)
# shellcheck disable=SC2016  # раскрывается в исполняемом тексте шага
{ echo 'pf() { echo "remote-heavy-prep: $1" | tee "$GI_TL" >&2; exit 125; }'; sed -n '/^# gitid-begin$/,/^# gitid-end$/p' "$BOX/gi1.cmd"; } > "$BOX/gitid.sh"
if grep -q '^# gitid-end$' "$BOX/gitid.sh"; then ok; else OUT="$BOX/gi1.cmd"; bad GI3 "текста шага учётки в Job нет — исполнять нечего"; fi
GR="$BOX/girepo"; rm -rf "$GR"; git init -q "$GR"; echo x > "$GR/f"; git -C "$GR" add f
# Подпись коммита пробы — из HOME песочницы со своим корневым gitconfig (check-16).
mkdir -p "$BOX/gi-author"
env -u GIT_CONFIG_GLOBAL HOME="$BOX/gi-author" git config --global user.name "$GI_NAME"
env -u GIT_CONFIG_GLOBAL HOME="$BOX/gi-author" git config --global user.email "$GI_EMAIL"
env -u GIT_CONFIG_GLOBAL HOME="$BOX/gi-author" git -C "$GR" commit -q -m p
# gi_sign_holds <окружение…> — исполнить шаг в чистом HOME pod и судить предикат стража
gi_sign_holds() {
    local ph="$BOX/gi-podhome"; rm -rf "$ph" "$BOX/gi.tl"; mkdir -p "$ph"
    OUT="$BOX/gi3.out"
    env -i HOME="$ph" PATH=/usr/bin:/bin GI_TL="$BOX/gi.tl" "$@" bash "$BOX/gitid.sh" > "$OUT" 2>&1 || return 1
    local n e
    n="$(env -i HOME="$ph" PATH=/usr/bin:/bin git config --global --get user.name)" || return 1
    e="$(env -i HOME="$ph" PATH=/usr/bin:/bin git config --global --get user.email)" || return 1
    [ "$n <$e>" = "$(git -C "$GR" log -1 --format='%an <%ae>')" ]
}
if gi_sign_holds HEAVY_GIT_NAME="$GI_NAME" HEAVY_GIT_EMAIL="$GI_EMAIL"; then ok; else bad GI3 "после шага корневая учётка pod не равна подписи коммита — страж подписи сверять не с чем"; fi
if gi_sign_holds; then bad GI3b "без переданной учётки предикат подписи держится — проба мимо предмета"; else ok; fi
# E7 установка ИСПОЛНЕНИЕМ: текст из Job, сеть — двойник curl, архивы настоящие.
#    Оба пина → helm и node в bin; только node (helm без пина) → node ставится
#    (опыт 2026-10-10: каталог загрузки создавался лишь веткой helm); сумма helm
#    не сходится → отказ «helm … не поставлен»; архитектура чужая → отказ.
sed -n '/^# install-begin$/,/^# install-end$/p' "$BOX/e1.cmd" > "$BOX/install.raw"
if grep -q '^# install-end$' "$BOX/install.raw"; then ok; else OUT="$BOX/e1.cmd"; bad E7 "текста установки в Job нет — исполнять нечего"; fi
IW="$BOX/iw"; IS="$BOX/istub"; IA="$BOX/iarch"
# shellcheck disable=SC2016  # раскрывается в исполняемом тексте установки
{ echo 'pf() { echo "remote-heavy-prep: $1" >&2; exit 125; }'; sed "s#/work#$IW#g" "$BOX/install.raw"; } > "$BOX/install.sh"
rm -rf "$IA" "$IS"; mkdir -p "$IA/linux-amd64" "$IS"
printf '#!/bin/sh\necho v4.2.4+gprobe\n' > "$IA/linux-amd64/helm"; chmod +x "$IA/linux-amd64/helm"
tar -czf "$IA/helm-v4.2.4-linux-amd64.tar.gz" -C "$IA" linux-amd64
# Архивы node — у каждого выпуска свой node, печатающий свою версию: какой
# выпуск поставлен, судится по node --version из bin, а не по строке установки.
for nv in v26.11.1 v26.1.2 v26.1.0; do
    mkdir -p "$IA/node-$nv-linux-x64/bin"
    printf '#!/bin/sh\necho %s\n' "$nv" > "$IA/node-$nv-linux-x64/bin/node"; chmod +x "$IA/node-$nv-linux-x64/bin/node"
    tar -czf "$IA/node-$nv-linux-x64.tar.gz" -C "$IA" "node-$nv-linux-x64"
done
cat > "$IS/curl" <<'STUB'
#!/bin/bash
o=""; u=""
while [ "$#" -gt 0 ]; do case "$1" in -o) o="$2"; shift 2 ;; --retry) shift 2 ;; -*) shift ;; *) u="$1"; shift ;; esac; done
out() { if [ -n "$o" ]; then cat > "$o"; else cat; fi; }
Z=0000000000000000000000000000000000000000000000000000000000000000
case "$u" in
  */index.json) echo '[{"version":"v27.0.0"},{"version":"v26.11.1"},{"version":"v26.10.0"},{"version":"v26.1.2"},{"version":"v26.1.0"}]' | out ;;
  *.sha256sum) a="${u##*/}"; ( cd "$STUB_ARCH" && sha256sum "${a%.sha256sum}" ) | if [ -n "${STUB_BADSUM:-}" ]; then sed 's/^[0-9a-f]*/'"$Z"'/'; else cat; fi | out ;;
  # Как настоящий SHASUMS256.txt — строки всех архивов; при STUB_BADSUM_NODE сумма
  # каждой строки не сходится, а имя файла на месте (grep строку находит).
  */SHASUMS256.txt) ( cd "$STUB_ARCH" && sha256sum node-*.tar.gz ) | if [ -n "${STUB_BADSUM_NODE:-}" ]; then sed 's/^[0-9a-f]*/'"$Z"'/'; else cat; fi | out ;;
  *.tar.gz) cat "$STUB_ARCH/${u##*/}" | out ;;
  # Выпуск buf (ws#1110): sha256.txt — строки всех бинарей и архивов, как настоящий.
  */bufbuild/buf/releases/download/*/sha256.txt) ( cd "$STUB_ARCH/buf" && sha256sum buf-Linux-* ) | if [ -n "${STUB_BADSUM_BUF:-}" ]; then sed 's/^[0-9a-f]*/'"$Z"'/'; else cat; fi | out ;;
  */bufbuild/buf/releases/download/*/buf-Linux-*) cat "$STUB_ARCH/buf/${u##*/}" | out ;;
  *) echo "двойник curl: адрес не знаком" >&2; exit 22 ;;
esac
STUB
# shellcheck disable=SC2016  # раскрывается в двойнике uname
printf '#!/bin/sh\necho "${STUB_ARCH_M:-x86_64}"\n' > "$IS/uname"
chmod +x "$IS/curl" "$IS/uname"
# install_case <случай> <пин helm> <пин node> <код> <что обязано быть в bin|слово отказа> [окружение…]
install_case() {
    local name="$1" h="$2" n="$3" want="$4" what="$5"; shift 5
    rm -rf "$IW"; mkdir -p "$IW/bin"
    OUT="$BOX/$name.out"
    env PATH="$IS:$PATH" STUB_ARCH="$IA" HEAVY_HELM="$h" HEAVY_NODE="$n" "$@" bash "$BOX/install.sh" > "$OUT" 2>&1; RC=$?
    expect_rc "$name" "$want"
    if [ "$want" -eq 0 ]; then
        for t in $what; do
            if [ -x "$IW/bin/$t" ] && "$IW/bin/$t" --version >/dev/null 2>&1; then ok; else bad "$name" "$t не поставлен в bin"; fi
        done
    elif ! grep -q "remote-heavy-prep: $what" "$OUT"; then bad "$name" "отказ «$what» не назван"; fi
}
install_case E7-both v4.2.4 26 0 "helm node"
install_case E7-node-only "" 26 0 "node"
mkdir -p "$IA/buf"; printf '#!/bin/sh\necho 1.72.0\n' > "$IA/buf/buf-Linux-x86_64"; chmod +x "$IA/buf/buf-Linux-x86_64"
printf 'tar' > "$IA/buf/buf-Linux-x86_64.tar.gz"
install_case E7-buf "" "" 0 "buf" HEAVY_BUF=1.72.0
install_case E7-buf-badsum "" "" 125 "buf 1.72.0 не поставлен" HEAVY_BUF=1.72.0 STUB_BADSUM_BUF=1
if [ -e "$IW/bin/buf" ]; then OUT="$BOX/E7-buf-badsum.out"; bad E7-buf-badsum "buf с несошедшейся суммой лежит в bin"; else ok; fi
install_case E7-buf-arch "" "" 125 "buf: архитектура" HEAVY_BUF=1.72.0 STUB_ARCH_M=s390x
install_case E7-helm-only v4.2.4 "" 0 "helm"
install_case E7-badsum v4.2.4 26 125 "helm v4.2.4 не поставлен" STUB_BADSUM=1
install_case E7-arch v4.2.4 26 125 "helm: архитектура" STUB_ARCH_M=s390x
install_case E7-badsum-node "" 26 125 "node v26.11.1 не поставлен" STUB_BADSUM_NODE=1
if [ -e "$IW/bin/node" ] && "$IW/bin/node" --version >/dev/null 2>&1; then OUT="$BOX/E7-badsum-node.out"; bad E7-badsum-node "node с несошедшейся суммой исполним из bin"; else ok; fi
# node_installed <случай> <пин> <выпуск> — пин разрешён в <выпуск>: node из bin
# печатает его (архив каждого выпуска несёт свой node).
node_installed() {
    install_case "$1" "" "$2" 0 "node"
    local got; got="$("$IW/bin/node" --version 2>/dev/null)"
    if [ "$got" = "$3" ]; then ok; else bad "$1" "пин $2 разрешён в «$got», ждали $3"; fi
}
node_installed E7-minor 26.1 v26.1.2
node_installed E7-exact 26.1.0 v26.1.0
if [ "$(cat "$BOX/E7-both.out" 2>/dev/null | grep -c 'ставлю node v26.11.1')" -eq 1 ]; then ok
else OUT="$BOX/E7-both.out"; bad E7 "мажор 26 разрешён не в последний выпуск 26 (v26.11.1)"; fi
# E8 пины законными формами YAML (ключи шага до uses, поточный шаг) → те же пины
fresh
go_run e8 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref pins3 --src "$SRC" --profile integration --short e8 -- true
expect_rc E8 0
if [ "$(envv "$BOX/state/job.json" HEAVY_HELM)" = v4.2.4 ] && [ "$(envv "$BOX/state/job.json" HEAVY_NODE)" = 26 ]; then ok
else OUT="$BOX/state/job.json"; bad E8 "пины формами YAML: helm «$(envv "$BOX/state/job.json" HEAVY_HELM)», node «$(envv "$BOX/state/job.json" HEAVY_NODE)», ждали v4.2.4 и 26"; fi
# E9 шаг есть, ключа пина нет → 69 до кластера, шаг и ключ названы
fresh
go_run e9 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref pins4 --src "$SRC" --profile integration --short e9 -- true
expect_rc E9 69
if [ -e "$BOX/state/job.json" ]; then bad E9 "Job создан при шаге без пина"; else ok; fi
if grep -q 'шаг azure/setup-helm без скалярного with.version' "$OUT"; then ok; else bad E9 "шаг helm без version не назван"; fi
# E10 пин вне формы → 69 до кластера, Job нет, причина названа
for c in "E10 pins5 node" "E10b pins6 helm"; do
    read -r cn cref ctool <<< "$c"
    fresh
    go_run "$cn" env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref "$cref" --src "$SRC" --profile integration --short e10 -- true
    expect_rc "$cn" 69
    if [ -e "$BOX/state/job.json" ]; then bad "$cn" "Job создан при пине вне формы"; else ok; fi
    if grep -q "пин $ctool на .* вне формы" "$OUT"; then ok; else bad "$cn" "пин $ctool вне формы не назван"; fi
done
# E11 (ws#1110) задание на ubuntu-latest без setup-helm, buf шагом → helm ОБРАЗА
#     ранера (Readme образа) и пин buf в окружении run, строка «Job создан» их
#     называет; близнец E11b — только self-hosted: helm не ставится, код 0; E11c —
#     таблица образов не получена → 69, Job нет; E11d — пин buf вне формы → 69.
fresh
go_run e11 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref imgs --src "$SRC" --profile ci-local --short e11 -- true
expect_rc E11 0
if [ "$(envv "$BOX/state/job.json" HEAVY_HELM)" = v3.22.0 ] && [ "$(envv "$BOX/state/job.json" HEAVY_BUF)" = 1.72.0 ]; then ok
else OUT="$BOX/state/job.json"; bad E11 "helm образа «$(envv "$BOX/state/job.json" HEAVY_HELM)», buf «$(envv "$BOX/state/job.json" HEAVY_BUF)», ждали v3.22.0 и 1.72.0"; fi
if grep -q 'Job создан: .*helm v3.22.0 (образ ранера), node нет пина, buf 1.72.0' "$OUT"; then ok; else bad E11 "строка «Job создан» не называет helm образа и buf"; fi
fresh
go_run e11b env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref imgs2 --src "$SRC" --profile ci-local --short e11b -- true
expect_rc E11b 0
if [ -z "$(envv "$BOX/state/job.json" HEAVY_HELM)" ] && [ -z "$(envv "$BOX/state/job.json" HEAVY_BUF)" ]; then ok
else OUT="$BOX/state/job.json"; bad E11b "self-hosted без шагов: helm «$(envv "$BOX/state/job.json" HEAVY_HELM)», buf «$(envv "$BOX/state/job.json" HEAVY_BUF)», ждали пусто"; fi
fresh
go_run e11c env FAKE_EXIT=0 FAKE_CURL_DOWN=1 bash "$RUN" --task 1 --repo kaname --ref imgs --src "$SRC" --profile ci-local --short e11c -- true
expect_rc E11c 69
if [ -e "$BOX/state/job.json" ]; then bad E11c "Job создан, хотя helm образа не выведен"; else ok; fi
if grep -q 'таблица образов actions/runner-images не получена' "$OUT"; then ok; else bad E11c "причина не названа"; fi
fresh
go_run e11d env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref imgs3 --src "$SRC" --profile ci-local --short e11d -- true
expect_rc E11d 69
if [ -e "$BOX/state/job.json" ]; then bad E11d "Job создан при пине buf вне формы"; else ok; fi
if grep -q 'пин buf на .* вне формы' "$OUT"; then ok; else bad E11d "пин buf вне формы не назван"; fi
# E3 два пина helm в конвейере ревизии → 69 до кластера, причина названа
fresh
go_run e3 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref pins2 --src "$SRC" --profile integration --short e3 -- true
expect_rc E3 69
if [ -e "$BOX/state/job.json" ]; then bad E3 "Job создан при неоднозначном пине"; else ok; fi
if grep -q 'пин helm неоднозначен' "$OUT"; then ok; else bad E3 "причина не названа"; fi
# E4 профиль lint на той же ревизии — go test нет, среду не ставит (близнец E1)
fresh
go_run e4 env FAKE_EXIT=0 bash "$RUN" --task 1 --repo kaname --ref pins --src "$SRC" --profile lint --short e4 -- true
expect_rc E4 0
e4cmd="$(kx cmd "$BOX/state/job.json" run 2)"
if [ -z "$(envv "$BOX/state/job.json" HEAVY_HELM)" ] && [ -n "$e4cmd" ] && ! grep -q 'get.helm.sh' <<< "$e4cmd"; then ok
else OUT="$BOX/state/job.json"; bad E4 "lint ставит helm"; fi
# E5 ревизия без пинов — сверять нечего, строка это называет
if grep -q 'helm, node и buf: пинов в конвейере ревизии и helm в образе ранера нет' "$BOX/u1.out" 2>/dev/null; then ok; else OUT="$BOX/u1.out"; bad E5 "отсутствие пинов не названо"; fi
# E6 run отказал сверкой среды → 69 «не выполнилось — среда», а не код команды
fresh
go_run e6 env FAKE_EXIT=125 FAKE_MSG="remote-heavy-prep: среда: helm v4.2.4 (пин конвейера) нет в PATH" bash "$RUN" --task 1 --repo kaname --ref pins --src "$SRC" --profile integration --short e6 -- true
expect_rc E6 69
if grep -q 'не выполнилось — среда: helm v4.2.4' "$OUT"; then ok; else bad E6 "отказ среды не назван «не выполнилось — среда»"; fi

# ── история как у клона конвейера (ws#996) ─────────────────────────────────
# H1 конвейер берёт checkout с fetch-depth: 0 — все ветки origin и метки. Ревизия,
#    достижимая лишь из боковой ветки origin (не предок ни ствола, ни HEAD), и
#    метка обязаны доехать в bundle и стать ссылками дерева pod: FETCH из Job
#    исполняется над доставленным bundle. Близнец — ствол и ревизия на месте.
SIDE="$(git -C "$SRC" rev-parse pins2)"
git -C "$SRC" update-ref refs/remotes/origin/main HEAD
git -C "$SRC" update-ref refs/remotes/origin/side "$SIDE"
git -C "$SRC" tag probe-tag pins
fresh
go_run h1 env FAKE_EXIT=0 "${B[@]}" --short h1 -- true
expect_rc H1 0
heads="$(git bundle list-heads "$BOX/state/bundle" 2>/dev/null)"
if grep -q " refs/remotes/origin/side$" <<< "$heads" && grep -q " refs/tags/probe-tag$" <<< "$heads"; then ok
else bad H1 "в bundle нет боковой ветки origin либо метки: $(tr '\n' ';' <<< "$heads")"; fi
FW="$BOX/fw"; rm -rf "$FW"; mkdir -p "$FW"; cp "$BOX/state/bundle" "$FW/in.bundle"; touch "$FW/in.done"
kx cmd "$BOX/state/job.json" fetch 2 | sed "s#/work#$FW#g" > "$BOX/fetch.sh"
OUT="$BOX/h1-fetch.out"
( cd "$FW" && env HEAVY_SHA="$(git -C "$SRC" rev-parse HEAD)" HEAVY_MAIN="$(git -C "$SRC" rev-parse HEAD)" \
    GIT_CONFIG_GLOBAL="$BOX/ghome/.gitconfig" sh "$BOX/fetch.sh" ) > "$OUT" 2>&1; frc=$?
if [ "$frc" -eq 0 ] && [ "$(git -C "$FW/src" rev-parse -q --verify refs/remotes/origin/side)" = "$SIDE" ] \
   && git -C "$FW/src" rev-parse -q --verify refs/tags/probe-tag >/dev/null \
   && [ "$(git -C "$FW/src" rev-parse HEAD)" = "$(git -C "$SRC" rev-parse HEAD)" ] \
   && [ "$(git -C "$FW/src" rev-parse refs/remotes/origin/main)" = "$(git -C "$SRC" rev-parse HEAD)" ]; then ok
else bad H1 "дерево pod без боковой ветки, метки, ствола или ревизии (код FETCH $frc)"; fi
fwrefs="$(git -C "$FW/src" for-each-ref --format='%(refname)')"
if grep -q '^refs/remote-heavy/' <<< "$fwrefs"; then bad H1 "временная ссылка run.sh доехала в дерево pod"; else ok; fi
git -C "$SRC" update-ref -d refs/remotes/origin/side; git -C "$SRC" update-ref -d refs/remotes/origin/main; git -C "$SRC" tag -d probe-tag >/dev/null

# K2
fresh
go_run k2 env FAKE_EXIT=42 "${B[@]}" --short k2 -- false
expect_rc K2 42
expect_ns_gone K2 t1-heavy-k2

# K3 — TERM посреди команды
fresh
(
    env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_HANG=1 \
        KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "${B[@]}" --short k3 -- true > "$BOX/k3.out" 2>&1 &
    pid=$!
    for _ in $(seq 1 100); do [ -e "$BOX/state/logging" ] && break; sleep 0.1; done
    t0=$(date +%s)
    kill -TERM "$pid"
    wait "$pid"; rc=$?
    echo "$rc $(( $(date +%s) - t0 ))" > "$BOX/k3.rc"
)
OUT="$BOX/k3.out"; cat "$OUT" >> "$ALL_OUT"
read -r RC took < "$BOX/k3.rc"
expect_rc K3 143
if [ -e "$BOX/state/logging" ]; then ok; else bad K3 "команда не дошла до лога — TERM пришёл не посреди команды"; fi
if [ "$took" -le 20 ]; then ok; else bad K3 "выход через $took с после TERM"; fi
expect_ns_gone K3 t1-heavy-k3

# K4 — OOMKilled
fresh
go_run k4 env FAKE_EXIT=137 FAKE_OOM=1 "${B[@]}" --short k4 -- true
expect_rc K4 76
expect_ns_gone K4 t1-heavy-k4
# K4b — команду убил предел памяти, контейнер вышел кодом команды (между ними bash
#      шага красных групп): признак «remote-heavy-oom:» в termination-log → 76;
#      близнец K4c — 137 без признака → 137 (красное, а не «не выполнилось»)
fresh
go_run k4b env FAKE_EXIT=137 FAKE_MSG="remote-heavy-oom: процесс команды убит пределом памяти (oom_kill 0 → 1, код 137)" "${B[@]}" --short k4b -- true
expect_rc K4b 76
if grep -q 'оборвана пределом памяти .*oom_kill 0 → 1' "$OUT"; then ok; else bad K4b "причина не названа"; fi
fresh
go_run k4c env FAKE_EXIT=137 "${B[@]}" --short k4c -- true
expect_rc K4c 137

# K6 — подготовка pod не удалась (termination-log): 69, не код 125 команды
fresh
go_run k6 env FAKE_EXIT=125 FAKE_MSG="remote-heavy-prep: jq не поставлен" "${B[@]}" --short k6 -- true
expect_rc K6 69
expect_ns_gone K6 t1-heavy-k6
# близнец K6: тот же код 125 без строки подготовки — код команды
fresh
go_run k6b env FAKE_EXIT=125 "${B[@]}" --short k6b -- true
expect_rc K6b 125

# K5 — --keep 2: ns остаётся, срок ≈ +2 ч, метки на месте
fresh
t0=$(date +%s)
go_run k5 env FAKE_EXIT=0 "${B[@]}" --short k5 --keep 2 -- true
expect_rc K5 0
f="$BOX/state/ns/t1-heavy-k5"
if [ -f "$f" ]; then
    ok
    exp="$(jq -r '.metadata.annotations["kacho.io/expires"]' "$f")"
    d=$(( $(date -u -d "$exp" +%s) - t0 - 7200 )); [ "$d" -lt 0 ] && d=$(( -d ))
    if [ "$d" -le 60 ]; then ok; else bad K5 "kacho.io/expires=$exp, ждали ≈ +2 ч"; fi
    labels="$(jq -r '.metadata.labels | "\(.["kacho.io/task"]) \(.["kacho.io/stand"]) \(.["kacho.io/kind"])"' "$f")"
    if [ "$labels" = "1 test heavy" ]; then ok; else bad K5 "метки «$labels», ждали «1 test heavy»"; fi
else
    bad K5 "ns с --keep снято"
fi
if [ -e "$BOX/state/deleted" ]; then bad K5 "delete ns звался при --keep"; else ok; fi

# R1, R2, R3 — отказ до кластера
fresh
go_run r1 env NS=kacho "${B[@]}" -- true
expect_rc R1 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R1 "ns создано"; fi
no_cluster_call R1
fresh
go_run r2 "${B[@]}" --ns kacho -- true
expect_rc R2 64
if [ "$(ns_left)" -eq 0 ]; then ok; else bad R2 "ns создано"; fi
no_cluster_call R2
for bad_ns in t2-heavy-x t1-stand-x kacho-heavy t1-heavy- default; do
    fresh
    go_run "r3-$bad_ns" "${B[@]}" --ns "$bad_ns" -- true
    expect_rc "R3 $bad_ns" 64
    no_cluster_call "R3 $bad_ns"
done

# cluster_calls — вызовов kubectl, кроме чтения списка контекстов (локальная операция)
cluster_calls() { [ -e "$BOX/state/calls" ] || { echo 0; return; }; grep -vc ' config get-contexts ' "$BOX/state/calls"; }
# X2 — KACHO_REMOTE_CONTEXT на infra → 64 до любого обращения, и к kubectl тоже
for ov in "$CTX_INFRA" lab-a1; do
    fresh
    go_run "x2-$ov" env KACHO_REMOTE_CONTEXT="$ov" FAKE_EXIT=0 "${B[@]}" --short x2 -- true
    expect_rc "X2 $ov" 64
    no_cluster_call "X2 $ov"
    if grep -q 'только в контекст -client' "$OUT"; then ok; else bad "X2 $ov" "шаг «что сделать» не назван"; fi
done
fresh
go_run x2a env KACHO_REMOTE_CONTEXT="$CTX_INFRA" bash "$RUN" --available
expect_rc X2a 64
no_cluster_call X2a
# X2b — близнец: KACHO_REMOTE_CONTEXT на client → 0
fresh
go_run x2b env KACHO_REMOTE_CONTEXT="$CTX_CLIENT" FAKE_EXIT=0 "${B[@]}" --short x2b -- true
expect_rc X2b 0
# X2c — названного -client в файле нет → 69, к кластеру ни одного обращения
fresh
go_run x2c env KACHO_REMOTE_CONTEXT=lab-zz-client FAKE_EXIT=0 "${B[@]}" --short x2c -- true
expect_rc X2c 69
if [ "$(cluster_calls)" -gt 0 ]; then bad X2c "к кластеру обращались"; else ok; fi
# X3 — в файле нет контекста -client (только infra) → 69 и с --available; X4 — два -client → 69
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" > "$BOX/kc-noclient"
kubeconfig_with "$CTX_INFRA" "$CTX_INFRA" "$CTX_CLIENT" lab-b2-client > "$BOX/kc-twoclient"
for cs in "noclient:X3:нет контекста с суффиксом -client" "twoclient:X4:выбор неоднозначен"; do
    IFS=: read -r f nm why <<< "$cs"
    for mode in run avail; do
        fresh
        if [ "$mode" = run ]; then
            go_run "$nm-$mode" env KACHO_REMOTE_KUBECONFIG="$BOX/kc-$f" FAKE_EXIT=0 "${B[@]}" --short x3 -- true
        else
            go_run "$nm-$mode" env KACHO_REMOTE_KUBECONFIG="$BOX/kc-$f" bash "$RUN" --available
        fi
        expect_rc "$nm $mode" 69
        if [ "$(cluster_calls)" -gt 0 ]; then bad "$nm $mode" "к кластеру обращались"; else ok; fi
        if grep -q "$why" "$OUT" && grep -q 'KACHO_REMOTE_CONTEXT\|добавь контекст' "$OUT"; then ok; else bad "$nm $mode" "причина или шаг не названы"; fi
    done
done

# R4 — ns уже есть: отказ, и чужое не снято (близнец K1 по имени)
fresh
echo '{"kind":"Namespace"}' > "$BOX/state/ns/t1-heavy-k1"
go_run r4 env FAKE_EXIT=0 "${B[@]}" --short k1 -- true
expect_rc R4 64
if [ -f "$BOX/state/ns/t1-heavy-k1" ]; then ok; else bad R4 "существовавшее ns снято"; fi
if [ -e "$BOX/state/deleted" ]; then bad R4 "delete ns звался для чужого ns"; else ok; fi

# ── предел одновременных прогонов (F3) ──────────────────────────────────────
# seed_ns <имя> <срок: +1 hour | -1 hour> — чужое идущее тяжёлое ns
seed_ns() {
    jq -n --arg n "$1" --arg t "$(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)" --arg e "$(date -u -d "$2" +%Y-%m-%dT%H:%M:%SZ)" \
        '{kind: "Namespace", metadata: {name: $n, creationTimestamp: $t, labels: {"kacho.io/kind": "heavy"}, annotations: {"kacho.io/expires": $e}}, status: {phase: "Active"}}' > "$BOX/state/ns/$1"
}
seed_done_job() {
    mkdir -p "$BOX/state/jobs"
    jq -n --arg n "$1" '{metadata: {namespace: $n, name: "run"}, status: {conditions: [{type: "Complete", status: "True"}]}}' > "$BOX/state/jobs/$1"
}
own_gone() {
    if [ ! -e "$BOX/state/ns/$2" ] && grep -qx "$2" "$BOX/state/deleted" 2>/dev/null; then ok; else bad "$1" "своё ns $2 не снято"; fi
}
no_job() { if [ -e "$BOX/state/job.json" ]; then bad "$1" "Job создан"; else ok; fi; }

# C1 — идущих 2 при пределе 2 → 75 до создания ns
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'
go_run c1 env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=2 "${B[@]}" --short c1 -- true
expect_rc C1 75
if grep -qE '(^| )create -f ' "$BOX/state/calls"; then bad C1 "create звался при занятом кластере"; else ok; fi
# C2 — близнец C1: те же ns, их Job завершены → не идущие → 0
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'; seed_done_job t7-heavy-a; seed_done_job t8-heavy-b
go_run c2 env FAKE_EXIT=0 "${B[@]}" --short c2 -- true
expect_rc C2 0
# C3 — близнец C1: ns со сроком в прошлом (остаток kill -9) не идущее → 0
fresh; seed_ns t7-heavy-a '-1 hour'; seed_ns t8-heavy-b '-1 hour'
go_run c3 env FAKE_EXIT=0 "${B[@]}" --short c3 -- true
expect_rc C3 0
# C4 — гонка: первая перепись видит 1 из 2, второй запуск создал ns мгновением раньше → 75, своё ns снято, Job нет
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c4 env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=2 FAKE_RACE=t9-heavy-racer "${B[@]}" --short c4 -- true
expect_rc C4 75
own_gone C4 t1-heavy-c4
no_job C4
# C4b — близнец C4 без гонки → 0
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c4b env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=2 "${B[@]}" --short c4b -- true
expect_rc C4b 0
# C5 — --keep не спасает ns запуска, вышедшего сверх предела
fresh; seed_ns t7-heavy-a '+1 hour'
go_run c5 env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=2 FAKE_RACE=t9-heavy-racer "${B[@]}" --short c5 --keep 2 -- true
expect_rc C5 75
own_gone C5 t1-heavy-c5
# V2 — --available при занятом кластере → 75; близнец с одним идущим → 0
fresh; seed_ns t7-heavy-a '+1 hour'; seed_ns t8-heavy-b '+1 hour'
go_run v2 env KACHO_REMOTE_HEAVY_MAX=2 bash "$RUN" --available
expect_rc V2 75
fresh; seed_ns t7-heavy-a '+1 hour'
go_run v2b env KACHO_REMOTE_HEAVY_MAX=2 bash "$RUN" --available
expect_rc V2b 0
# M2 — предел по умолчанию — 4, страховка над размещением (ws#1143): 4 идущих → 75 с
# пределом в причине; близнец — 3 идущих → 0
fresh; for x in a b c d; do seed_ns "t7-heavy-$x" '+1 hour'; done
go_run m2 bash "$RUN" --available
expect_rc M2 75
if grep -q 'идущих тяжёлых прогонов 4 при пределе 4' "$OUT"; then ok; else bad M2-why "предел по умолчанию не 4 либо не назван"; fi
fresh; for x in a b c; do seed_ns "t7-heavy-$x" '+1 hour'; done
go_run m2b bash "$RUN" --available
expect_rc M2b 0
# M1 — предел вне 1..8 → 64
fresh
go_run m1 env KACHO_REMOTE_HEAVY_MAX=0 "${B[@]}" -- true
expect_rc M1 64

# ── размещение: место под профиль, без условия по стенду (ws#991) ─────────
# node_j <имя> <готов 1|0> <закрыт 1|0> <taint-эффект|""> — узел 15,5 CPU и 29,5 ГиБ;
# pod_j <ns> <узел> <фаза> <cpu> <память> — pod с запросами; items — список.
node_j() {
    jq -nc --arg n "$NODE_PFX$1" --arg r "$2" --arg c "$3" --arg t "$4" --arg e "$FAKE_NODE_IP" '{metadata: {name: $n},
      spec: ((if $c == "1" then {unschedulable: true} else {} end) + (if $t != "" then {taints: [{key: "k", effect: $t}]} else {} end)),
      status: {addresses: [{type: "InternalIP", address: $e}], conditions: [{type: "Ready", status: (if $r == "1" then "True" else "False" end)}],
               allocatable: {cpu: "15500m", memory: "30913596Ki"}}}'
}
pod_j() {
    jq -nc --arg ns "$1" --arg n "$NODE_PFX$2" --arg ph "$3" --arg c "$4" --arg m "$5" '{metadata: {namespace: $ns, name: "p"},
      spec: {nodeName: $n, containers: [{name: "c", resources: {requests: {cpu: $c, memory: $m}}}]}, status: {phase: $ph}}'
}
items() { jq -sc '{items: .}'; }
created() { grep -qE '(^| )create -f ' "$BOX/state/calls" 2>/dev/null && echo да || echo нет; }
NODES1="$(node_j n1 1 0 "" | items)"
NODES12="$( { node_j n1 1 0 ""; node_j n2 1 0 ""; } | items)"
# Стенд замера 2026-10-09 (kubectl describe nodes): запросы 450m CPU и 2 756 МиБ.
STAND_ALL="$( { pod_j kacho n1 Running 450m 2756Mi; pod_j kacho n2 Running 450m 2756Mi; } | items)"
# Q1 — стенд на всех узлах, место есть → 0: стенд узел не запирает (опыт 2026-10-09:
# прежнее условие давало здесь 69, а прогон шёл локально)
fresh
go_run q1 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$STAND_ALL" bash "$RUN" --available --profile go-race
expect_rc Q1 0
fresh
go_run q1r env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$STAND_ALL" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile go-race --short q1r -- true
expect_rc Q1r 0
if [ "$(created)" = да ]; then ok; else bad Q1r "ns не создавалось при стенде на всех узлах и месте под профиль"; fi
expect_ns_gone Q1r t1-heavy-q1r
# Q1d — запас 20 % (ws#1143): единственный узел со стендом и одним идущим go-race —
# второй go-race на нём оставил бы узлу меньше 20 % по CPU → 75, запас назван
IFS='|' read -r _ gcpu _ gmib _ <<< "$(sed -n "s/^PROFILES='\\(go-race|.*\\)/\\1/p" "$RUN")"
IFS='|' read -r dind_cpu _ dind_gi _ <<< "$(sed -n "s/^DIND_RES='\\(.*\\)'$/\\1/p" "$RUN")"
dind_gi="${dind_gi%Gi}"
if [ -n "$gcpu" ] && [ -n "$dind_cpu" ] && [ -n "$dind_gi" ]; then
    one_run="$(pod_j t9-heavy-a n1 Running "$(( gcpu + dind_cpu ))" "$(( ${gmib%Gi} + dind_gi ))Gi")"
    fresh
    go_run q1d env FAKE_NODES="$NODES1" FAKE_CLUSTER_PODS="$( { pod_j kacho n1 Running 450m 2756Mi; echo "$one_run"; } | items)" bash "$RUN" --available --profile go-race
    expect_rc Q1d 75
    if grep -q 'с запасом 20 % узла' "$OUT"; then ok; else bad Q1d-why "причина без запаса"; fi
else bad Q1d "запрос go-race и dind не прочитаны из run.sh"; fi
# QH — допуск по запросам профиля и запасу 20 % (ws#1143). Узлы и фон — замер
# 2026-10-17 (get nodes и get pods -A): два узла по 15 500m и 30 189 МиБ, фон
# 2 265m/8 436 МиБ и 2 335m/9 460 МиБ. Тяжёлый (go-race, ci-local) — 7 CPU и 12 ГиБ,
# лёгкий (integration, lint) — 4 CPU и 6 ГиБ (запросы PROFILES с dind). Уже идущие
# прогоны — pod на узлах; число идущих ns ноль: решает размещение, а не счёт штуками.
# Помещаются 4 лёгких, или 1 тяжёлый и 2 лёгких, или 2 тяжёлых; следующий — 75.
BG="$(pod_j sys n1 Running 2265m 8436Mi) $(pod_j sys n2 Running 2335m 9460Mi)"
qh() {  # qh <случай> <профиль> <код> <узлы идущих: h1 l2 …>
    local id="$1" prof="$2" want="$3" pods="$BG" r; shift 3
    for r in "$@"; do
        case "$r" in
            h*) pods="$pods $(pod_j t9-heavy-h n"${r#h}" Running 7 12Gi)" ;;
            l*) pods="$pods $(pod_j t9-heavy-l n"${r#l}" Running 4 6Gi)" ;;
        esac
    done
    fresh
    go_run "qh-$id" env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$(printf '%s\n' "$pods" | items)" bash "$RUN" --available --profile "$prof"
    expect_rc "QH-$id" "$want"
    if [ "$want" = 75 ]; then
        if grep -q 'с запасом 20 % узла по CPU и памяти нет' "$OUT"; then ok; else bad "QH-$id-why" "причина 75 не называет запас"; fi
    fi
}
qh light-0 lint 0
qh light-1 integration 0 l1
qh light-2 lint 0 l1 l2
qh light-3 integration 0 l1 l1 l2
qh light-4 lint 75 l1 l1 l2 l2
qh mix-0 go-race 0
qh mix-1 lint 0 h1
qh mix-2 integration 0 h1 l2
qh mix-3 lint 75 h1 l2 l2
qh mix-3h go-race 75 h1 l2 l2
qh heavy-1 ci-local 0 h1
qh heavy-2 go-race 75 h1 h2
qh heavy-2c ci-local 75 h2 h1
# QB — запас на самой границе (приёмка ws#1143): один узел 15 500m и 30 913 596 КиБ,
# профиль lint (4 000m и 6 ГиБ), фон — один pod. Запас 20 % — 3 100m и 6 037,8 МиБ:
# фон 8 400m оставляет после посадки ровно 3 100m (0), 8 401m — 3 099m (75); фон
# 18 007 МиБ оставляет 6 038,06 МиБ (0), 18 008 МиБ — 6 037,06 МиБ (75). Судится КОДОМ:
# id случая стоит лишь у expect_rc, порча порога с прежним текстом причины краснеет им.
qb() {  # qb <случай> <фон cpu> <фон память> <код>
    fresh
    go_run "qb-$1" env FAKE_NODES="$NODES1" FAKE_CLUSTER_PODS="$(pod_j sys n1 Running "$2" "$3" | items)" bash "$RUN" --available --profile lint
    expect_rc "QB-$1" "$4"
}
qb cpu-in 8400m 1000Mi 0
qb cpu-out 8401m 1000Mi 75
qb mem-in 100m 18007Mi 0
qb mem-out 100m 18008Mi 75
qb both-in 8400m 18007Mi 0
qb both-out 8401m 18008Mi 75
# Q3 — единственный узел не готов / закрыт / с taint NoSchedule → 69; прогон 69 без ns
for q in "0 0 :не-готов" "1 1 :закрыт" "1 0 NoSchedule:taint"; do
    read -r rdy cord rest <<< "$q"; eff="${rest%%:*}"; nm="${rest#*:}"
    fresh
    go_run "q3-$nm" env FAKE_NODES="$(node_j n1 "$rdy" "$cord" "$eff" | items)" bash "$RUN" --available
    expect_rc "Q3-$nm" 69
    if grep -q 'открытого для планирования узла нет' "$OUT"; then ok; else bad "Q3-$nm" "причина не названа"; fi
done
fresh
go_run q3r env FAKE_EXIT=0 FAKE_NODES="$(node_j n1 1 1 "" | items)" "${B[@]}" --short q3r -- true
expect_rc Q3r 69
if [ "$(created)" = нет ]; then ok; else bad Q3r "ns создавалось без открытого узла"; fi
# Q2 — оба узла заняты: 16 ГиБ запрошено чужими pod → go-race (12 ГиБ) с запасом
# 20 % не встаёт → 75 до ns
BUSY="$( { pod_j kacho n1 Running 450m 2756Mi; pod_j other n1 Running 2 16Gi; pod_j other n2 Running 2 16Gi; } | items)"
fresh
go_run q2 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --available --profile go-race
expect_rc Q2 75
if grep -q 'места' "$OUT"; then ok; else bad Q2 "причина не названа (места нет)"; fi
fresh
go_run q2r env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --task 1 --repo kaname --ref HEAD --src "$SRC" --profile go-race --short q2r -- true
expect_rc Q2r 75
if [ "$(created)" = нет ]; then ok; else bad Q2r "ns создавалось без места под профиль"; fi
# Q2b — близнец: тот же кластер, профиль lint (6 ГиБ) встаёт → 0 и прогон исполняется
fresh
go_run q2b env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" bash "$RUN" --available --profile lint
expect_rc Q2b 0
fresh
go_run q2br env FAKE_EXIT=0 FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS="$BUSY" "${B[@]}" --short q2br -- true
expect_rc Q2br 0
# Q2c — профиля нет → 64
fresh
go_run q2c bash "$RUN" --available --profile nope
expect_rc Q2c 64
# Q5 — перепись pod кластера больше строки аргумента (128 КиБ) → разбирается, 0
# (опыт 2026-10-09: настоящий кластер, jq не запускался)
fresh
{ for i in $(seq 1 700); do pod_j "ns-$i-$(printf '%0120d' 0)" n2 Running 10m 16Mi; done; pod_j kacho n2 Running 100m 256Mi; } | items > "$BOX/bigpods.json"
go_run q5 env FAKE_NODES="$NODES12" FAKE_CLUSTER_PODS_FILE="$BOX/bigpods.json" bash "$RUN" --available --profile go-race
expect_rc Q5 0
if [ "$(stat -c %s "$BOX/bigpods.json")" -gt 131072 ]; then ok; else bad Q5 "перепись меньше 128 КиБ — случай пуст"; fi
# Q4 — pod ждёт планирования, а чужой pod занял последнее место → 75 сразу, а не
# через 1800 с; ns снято и при --keep
fresh
t0=$(date +%s)
go_run q4 env FAKE_EXIT=0 FAKE_UNSCHED=1 FAKE_PODS_AFTER_JOB="$(pod_j other n1 Running 15 28Gi | items)" "${B[@]}" --short q4 --keep 2 -- true
expect_rc Q4 75
if [ $(( $(date +%s) - t0 )) -le 30 ]; then ok; else bad Q4 "выход через $(( $(date +%s) - t0 )) с"; fi
expect_ns_gone Q4 t1-heavy-q4
if grep -q 'места под запрос' "$OUT"; then ok; else bad Q4 "причина не названа"; fi
# Q4b — близнец: pod ждёт, место есть (стенд на узле не мешает) → run.sh ждёт дальше
fresh
OUT="$BOX/q4b.out"
timeout 15 env PATH="$BOX/bin:$PATH" FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_EXIT=0 FAKE_UNSCHED=1 \
    FAKE_PODS_AFTER_JOB="$(pod_j kacho n1 Running 450m 2756Mi | items)" \
    KACHO_REMOTE_KUBECONFIG="$BOX/kubeconfig" TMPDIR="$BOX" "${B[@]}" --short q4b -- true > "$OUT" 2>&1
RC=$?; cat "$OUT" >> "$ALL_OUT"
expect_rc Q4b 124

# ── команда доходит до контейнера байт в байт (ws#1142) ────────────────────
# Составной Job потерял переменные и коды осей: kubelet свернул $$ в $ и раскрыл
# $(ИМЯ) значением env контейнера. KX1 — команда со всеми формами, которые kubelet
# трогает ($$, $(ИМЯ) объявленного env, $$(…), $(…) команды оболочки, $ в конце,
# незакрытое $(), читается раскрытием kubelet (kx) и сверяется с отправленной
# поэлементно. KX1-ctl — контроль пробы: та же команда, положенная в Job как есть,
# раскрытием искажается (иначе KX1 не судит ничего).
# shellcheck disable=SC2016  # все $ — буквальные байты команды
CMDX=(bash -c 'printf "%s|" "$$" "$(CI)" "$(id -u)"' 'arg0' '$$' '$(CI)' '$(HEAVY_WORKDIR)' '$$(CI)' '$(echo a b)' 'tail$' '$(open' 'x$$$y' '$')
fresh
go_run kx1 env FAKE_EXIT=0 "${B[@]}" --short kx1 -- "${CMDX[@]}"
expect_rc KX1 0
mapfile -d '' -t KXGOT < <(kx argv "$BOX/state/job.json" run)
kx_diff=""
[ "${#KXGOT[@]}" -eq $(( ${#CMDX[@]} + 4 )) ] || kx_diff="элементов ${#KXGOT[@]}, ждали $(( ${#CMDX[@]} + 4 ))"
for i in "${!CMDX[@]}"; do
    [ "${KXGOT[$((i + 4))]:-}" = "${CMDX[$i]}" ] || kx_diff="${kx_diff:+$kx_diff; }[$i] отправлено «${CMDX[$i]}», получено «${KXGOT[$((i + 4))]:-}»"
done
[ "${KXGOT[0]:-} ${KXGOT[1]:-} ${KXGOT[3]:-}" = "bash -c run" ] || kx_diff="${kx_diff:+$kx_diff; }голова команды «${KXGOT[0]:-} ${KXGOT[1]:-} … ${KXGOT[3]:-}»"
if [ -z "$kx_diff" ]; then ok; else OUT="$BOX/state/job.json"; bad KX1 "команда дошла до контейнера искажённой: $kx_diff"; fi
jq --argjson c "$(printf '%s\0' "${CMDX[@]}" | jq -Rsc 'split("\u0000")[:-1]')" \
    '(.spec.template.spec.containers[] | select(.name == "run") | .command) |= (.[0:4] + $c)' "$BOX/state/job.json" > "$BOX/kx-raw.json"
mapfile -d '' -t KXRAW < <(kx argv "$BOX/kx-raw.json" run)
# CMDX[4] — «$$», CMDX[5] — «$(CI)»; в команде Job они — элементы 8 и 9.
if [ "${KXRAW[8]:-}" = '$' ] && [ "${KXRAW[9]:-}" = true ]; then ok
else bad KX1-ctl "раскрытие kubelet пробы не искажает неэкранированную команду: «${CMDX[4]}» → «${KXRAW[8]:-}», «${CMDX[5]}» → «${KXRAW[9]:-}» — KX1 слепа"; fi
# KX1-env — value env: вход pre-push с $$ и $(HEAVY_NODE) (env, объявленный в run РАНЬШЕ
# HEAVY_PUSH_INPUT, — kubelet раскрыл бы его) доходит до окружения run байт в байт.
# shellcheck disable=SC2016  # $ — буквальные байты имени ссылки
KXREF='refs/heads/kx$$a$(HEAVY_NODE)b'
KXPL="$KXREF $(git -C "$SRC" rev-parse HEAD) $KXREF $ZS"
fresh
go_run kx1e env FAKE_EXIT=0 "${B[@]}" --short kx1e --push-input "$KXPL" -- true
expect_rc KX1-env-run 0
if [ "$(envv "$BOX/state/job.json" HEAVY_PUSH_INPUT)" = "$KXPL" ]; then ok
else OUT="$BOX/state/job.json"; bad KX1-env "вход pre-push дошёл до env искажённым: «$(envv "$BOX/state/job.json" HEAVY_PUSH_INPUT)»"; fi
# KX1-all — каждый контейнер Job, init тоже (fetch несёт $ подготовки): $ лишь парами;
# строк с $ в init больше нуля — иначе init судить нечем.
kodd="$(python3 "$BOX/kodd.py" "$BOX/state/job.json" 2>&1)"
if [[ "$kodd" == "нечётных 0 · "* ]] && ! [[ "$kodd" == *"(init 0)"* ]]; then ok
else OUT="$BOX/state/job.json"; bad KX1-all "экранирование не во всех контейнерах: $kodd"; fi

# ── вывод прогона (ws#991) ──────────────────────────────────────────────────
# O1 — каждая строка run.sh после выбора ns несёт его имя (K1 — тот же прогон)
fresh
go_run o1 env FAKE_EXIT=0 "${B[@]}" --short o1 -- true
expect_rc O1 0
n_all="$(grep -c '^remote-heavy: ' "$OUT")"; n_tag="$(grep -c '^remote-heavy: \[t1-heavy-o1\] ' "$OUT")"
if [ "$n_all" -gt 0 ] && [ "$n_all" -eq "$n_tag" ]; then ok; else bad O1 "строк run.sh $n_all, с именем ns $n_tag"; fi
# O2 — stderr прогона — файл, в который пишет посторонний живой процесс → строка-предупреждение
fresh
: > "$BOX/o2.out"
( exec 3>> "$BOX/o2.out"; exec sleep 60 ) & holder=$!
for _ in $(seq 1 50); do [ -e "/proc/$holder/fd/3" ] && break; sleep 0.1; done
go_run o2 env FAKE_EXIT=0 "${B[@]}" --short o2 -- true
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
expect_rc O2 0
if grep -q 'пишет и другой процесс' "$OUT" && grep -q "pid $holder" "$OUT"; then ok; else bad O2 "общий файл вывода не назван"; fi
# O2b — близнец: файл держат только предки прогона (timeout, env) → молчание
if grep -q 'пишет и другой процесс' "$BOX/o1.out"; then OUT="$BOX/o1.out"; bad O2b "предупреждение без постороннего писателя"; else ok; fi

# ── локальная уборка после kill -9 ──────────────────────────────────────────
# shellcheck disable=SC2086  # поля stat — слова
pstart() { local st; st="$(cat "/proc/$1/stat")"; st="${st##*) }"; set -- $st; echo "${20}"; }
sleep 0 & dead_pid=$!; wait "$dead_pid"
DEAD="$dead_pid.1.dead"
LIVE="$$.$(pstart $$).live"
fresh
mkdir -p "$BOX/remote-heavy.dead1" "$BOX/remote-heavy.dead2" "$BOX/remote-heavy.live1"
printf '%s\nt1-heavy-old\n1\n\n' "$DEAD" > "$BOX/remote-heavy.dead1/owner"
echo bundle > "$BOX/remote-heavy.dead1/src.bundle"
printf '%s\nt1-heavy-other\n1\n\n' "$DEAD" > "$BOX/remote-heavy.dead2/owner"
printf '%s\nt1-heavy-live\n1\n\n' "$LIVE" > "$BOX/remote-heavy.live1/owner"
for n in old other; do seed_ns "t1-heavy-$n" '+1 hour'; done
jq --arg o "$DEAD" '.metadata.annotations["kacho.io/owner"] = $o' "$BOX/state/ns/t1-heavy-old" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-old"
jq '.metadata.annotations["kacho.io/owner"] = "someone-else"' "$BOX/state/ns/t1-heavy-other" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-other"
env REMOTE_HEAVY_OWNER="$DEAD" tail -f /dev/null & orphan=$!   # стоит до kill — подобие kubectl logs -f
env REMOTE_HEAVY_OWNER="$LIVE" tail -f /dev/null & liveproc=$!
git -C "$SRC" update-ref "refs/remote-heavy/$DEAD" HEAD
git -C "$SRC" update-ref "refs/remote-heavy/$LIVE" HEAD
go_run g1 env FAKE_EXIT=0 KACHO_REMOTE_HEAVY_MAX=3 "${B[@]}" --short g1 -- true
expect_rc G1 0
if [ ! -e "$BOX/remote-heavy.dead1" ] && [ ! -e "$BOX/remote-heavy.dead2" ]; then ok; else bad G1 "каталог мёртвого владельца остался"; fi
if kill -0 "$orphan" 2>/dev/null; then bad G1 "процесс мёртвого владельца жив"; kill "$orphan"; else ok; fi
if grep -qx t1-heavy-old "$BOX/state/deleted" 2>/dev/null; then ok; else bad G1 "ns мёртвого владельца не снято"; fi
if git -C "$SRC" show-ref --verify --quiet "refs/remote-heavy/$DEAD"; then bad G1 "ссылка мёртвого владельца осталась"; else ok; fi
if grep -q 'уборка прежних запусков' "$OUT"; then ok; else bad G1 "перепись уборки не напечатана"; fi
# G2 — близнецы: живой владелец и чужое ns того же вида не тронуты
if [ -f "$BOX/remote-heavy.live1/owner" ]; then ok; else bad G2 "каталог живого владельца снят"; fi
if kill -0 "$liveproc" 2>/dev/null; then ok; else bad G2 "процесс живого владельца убит"; fi
if git -C "$SRC" show-ref --verify --quiet "refs/remote-heavy/$LIVE"; then ok; else bad G2 "ссылка живого владельца снята"; fi
if grep -qx t1-heavy-other "$BOX/state/deleted" 2>/dev/null; then bad G2 "снято ns с чужой меткой владельца"; else ok; fi
kill "$liveproc" 2>/dev/null; wait "$liveproc" "$orphan" 2>/dev/null
rm -rf "$BOX/remote-heavy.live1"; git -C "$SRC" update-ref -d "refs/remote-heavy/$LIVE"

# ── страж кластера по узлам (решение владельца 2026-10-10) ──────────────────
# writes — изменяющие вызовы двойника (can-i — чтение).
writes() { [ -e "$BOX/state/calls" ] || { echo 0; return; }; grep -v 'auth can-i' "$BOX/state/calls" | grep -cE '(^| )(create|apply|delete|exec|patch|label|annotate) '; }
# wnode <имя> — узел, годный для размещения, с полным именем
wnode() { jq -nc --arg n "$1" --arg e "$FAKE_NODE_IP" '{metadata: {name: $n}, spec: {},
    status: {addresses: [{type: "InternalIP", address: $e}], conditions: [{type: "Ready", status: "True"}], allocatable: {cpu: "15500m", memory: "30913596Ki"}}}'; }
N_INFRA="$( { wnode lab1-infra-q11-a; wnode lab1-infra-q11-b; } | items)"
N_MIXED="$( { wnode lab1-client-p00l-a; wnode lab1-infra-q11-b; } | items)"
N_ZERO='{"items":[]}'
N_FOREIGN="$( { wnode lab2-client-p00l-a; wnode lab2-client-p00l-b; } | items)"
N_CLIENT="$( { wnode lab1-client-p00l-a; wnode lab1-client-zz9-b; } | items)"
for cs in "w1:$N_INFRA:с -infra- 2" "w2:$N_MIXED:с -infra- 1" "w3:$N_ZERO:узлов в контексте ноль" "w4:$N_FOREIGN:с префиксом <профиль>-client- 0"; do
    nm="${cs%%:*}"; rest="${cs#*:}"; nodes="${rest%:*}"; why="${rest##*:}"; NM="${nm^^}"
    for mode in run avail; do
        fresh
        if [ "$mode" = run ]; then
            go_run "$nm-$mode" env FAKE_EXIT=0 FAKE_NODES="$nodes" "${B[@]}" --short "$nm" -- true
        else
            go_run "$nm-$mode" env FAKE_NODES="$nodes" bash "$RUN" --available
        fi
        expect_rc "$NM $mode" 69
        if [ "$(writes)" -eq 0 ]; then ok; else bad "$NM $mode" "изменяющих вызовов $(writes) при узлах не того кластера"; fi
        if grep -qF -- "$why" "$OUT" && grep -q 'что сделать:' "$OUT"; then ok; else bad "$NM $mode" "причина «$why» или шаг не названы"; fi
    done
done
# W5 — узлы профиля (хвосты пула разные: хэш не зашит) → 0; get nodes раньше первой записи
fresh
go_run w5 env FAKE_EXIT=0 FAKE_NODES="$N_CLIENT" "${B[@]}" --short w5 -- true
expect_rc W5 0
first_nodes="$(grep -nE '(^| )get nodes' "$BOX/state/calls" | head -n 1 | cut -d: -f1)"
first_write="$(grep -nE '(^| )(create|apply|delete|exec) ' "$BOX/state/calls" | grep -v 'auth can-i' | head -n 1 | cut -d: -f1)"
if [ -n "$first_nodes" ] && [ -n "$first_write" ] && [ "$first_nodes" -lt "$first_write" ]; then ok; else bad W5 "перепись узлов (строка ${first_nodes:-нет}) не раньше первой записи (строка ${first_write:-нет})"; fi
# W6 — профиль из имени файла, переменной нет → 0; W6b — тот же файл, узлы чужого профиля → 69
cp "$BOX/kubeconfig" "$BOX/probe--lab1.yaml"
fresh
go_run w6 env -u KACHO_REMOTE_PROFILE KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_CLIENT" "${B[@]}" --short w6 -- true
expect_rc W6 0
fresh
go_run w6b env -u KACHO_REMOTE_PROFILE KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_FOREIGN" "${B[@]}" --short w6 -- true
expect_rc W6b 69
if [ "$(writes)" -eq 0 ]; then ok; else bad W6b "изменяющие вызовы при чужом профиле"; fi
# W7 — профиль не выводится → 69 до кластера; W8 — переменная и имя файла расходятся → 69
fresh
go_run w7 env -u KACHO_REMOTE_PROFILE FAKE_EXIT=0 "${B[@]}" --short w7 -- true
expect_rc W7 69
if [ "$(cluster_calls)" -eq 0 ] && grep -q 'KACHO_REMOTE_PROFILE=<профиль>' "$OUT"; then ok; else bad W7 "к кластеру обращались либо шаг не назван"; fi
fresh
go_run w8 env KACHO_REMOTE_PROFILE=lab2 KACHO_REMOTE_KUBECONFIG="$BOX/probe--lab1.yaml" FAKE_EXIT=0 FAKE_NODES="$N_FOREIGN" "${B[@]}" --short w8 -- true
expect_rc W8 69
if [ "$(cluster_calls)" -eq 0 ] && grep -q 'расходятся' "$OUT"; then ok; else bad W8 "к кластеру обращались либо причина не названа"; fi
# W9 — файл подменён после создания ns, узлы стали infra → 69 до сети ns; ns не снято
cp "$BOX/kubeconfig" "$BOX/kc-swap"
fresh
go_run w9 env KACHO_REMOTE_KUBECONFIG="$BOX/kc-swap" FAKE_SWAP_FILE="$BOX/kc-swap" FAKE_NODES_AFTER_NS="$N_INFRA" FAKE_EXIT=0 "${B[@]}" --short w9 -- true
expect_rc W9 69
if [ -e "$BOX/state/swapped" ]; then ok; else bad W9 "подмена файла не случилась — случай пуст"; fi
if [ ! -e "$BOX/state/netpol.json" ] && [ ! -e "$BOX/state/job.json" ]; then ok; else bad W9 "запись после подмены кластера"; fi
if [ -e "$BOX/state/deleted" ]; then bad W9 "delete ns звался в чужом кластере"; else ok; fi
if grep -q 'фаза «сетевая политика ns» не начата' "$OUT" && grep -q 'НЕ снято' "$OUT" && grep -q 'delete ns t1-heavy-w9' "$OUT"; then ok; else bad W9 "фаза, неснятое ns или шаг не названы"; fi
# W9b — близнец: файл сменился, узлы те же → 0, узлы переписаны заново
cp "$BOX/kubeconfig" "$BOX/kc-swap"
fresh
go_run w9b env KACHO_REMOTE_KUBECONFIG="$BOX/kc-swap" FAKE_SWAP_FILE="$BOX/kc-swap" FAKE_EXIT=0 "${B[@]}" --short w9b -- true
expect_rc W9b 0
expect_ns_gone W9b t1-heavy-w9b
nb="$(grep -nE ' create -f ' "$BOX/state/calls" | head -n 1 | cut -d: -f1)"
na="$(tail -n +"$(( ${nb:-1} + 1 ))" "$BOX/state/calls" | grep -cE '(^| )get nodes')"
if [ "${na:-0}" -ge 1 ]; then ok; else bad W9b "после смены файла узлы не переписаны"; fi
# W10 — узлы с -infra- при остатках мёртвого владельца → 69, его ns не снимается
fresh
mkdir -p "$BOX/remote-heavy.deadw"
printf '%s\nt1-heavy-oldw\n1\n\n' "$DEAD" > "$BOX/remote-heavy.deadw/owner"
seed_ns t1-heavy-oldw '+1 hour'
jq --arg o "$DEAD" '.metadata.annotations["kacho.io/owner"] = $o' "$BOX/state/ns/t1-heavy-oldw" > "$BOX/x.json" && mv "$BOX/x.json" "$BOX/state/ns/t1-heavy-oldw"
go_run w10 env FAKE_EXIT=0 FAKE_NODES="$N_INFRA" "${B[@]}" --short w10 -- true
expect_rc W10 69
if [ -e "$BOX/state/deleted" ] || [ "$(writes)" -ne 0 ]; then bad W10 "уборка писала в кластер с узлами infra"; else ok; fi
rm -rf "$BOX/remote-heavy.deadw"

# ── красные группы (ws#1136) ─────────────────────────────────────────────────
# RG0 — шаг красных групп в Job: после подготовки, команда — через heavy_cmd; зелёный
#      прогон (итог шага без красных) каталога копий не заводит и о копиях молчит
rg_in() { awk '/^# redlog-begin$/ { b = NR } /^# redlog-end$/ { m = NR } /^heavy_cmd "\$@"$/ { e = NR } END { exit !(b && m && e && b < m && m < e) }' "$1"; }
red_dirs() { find "$BOX" -maxdepth 1 -name "$1.out.red-*" | wc -l; }
fresh
go_run rg0 env FAKE_EXIT=0 "${B[@]}" --short rg0 -- true
expect_rc RG0 0
kx cmd "$BOX/state/job.json" run 2 > "$BOX/rg0.cmd" 2>/dev/null
if rg_in "$BOX/rg0.cmd"; then ok; else OUT="$BOX/rg0.cmd"; bad RG0 "шага красных групп перед командой в Job нет либо команда идёт не через heavy_cmd"; fi
if [ "$(red_dirs rg0)" -eq 0 ] && ! grep -q 'журналы красных групп' "$OUT"; then ok; else bad RG0 "зелёный прогон завёл каталог копий либо заговорил о них"; fi
# RG1 — шаг ИСПОЛНЕНИЕМ (текст из Job) над синтетическим прогоном: настоящий go test,
#      один пакет с заведомо упавшим тестом, второй зелёный; группы в форме вывода
#      ci-local — красная go test, красная линтера (без строк FAIL, с адресом pod),
#      ПРОПУСК с «целиком:» и ok. Дайджест называет пакет, тест и строку отказа;
#      копий — ровно две красные; код — код команды (близнец зелёный → 0)
RW="$BOX/rw"; RM="$RW/m"; mkdir -p "$RW/w" "$RM/good" "$RM/bad" "$RW/ci/run-1"
# Хвост команды Job — от шага до строки запуска включительно: переопределение после
# шага исполнилось бы и в pod, поэтому исполняется и здесь.
sed -n '/^# redlog-begin$/,$p' "$BOX/rg0.cmd" | sed "s#/work/#$RW/w/#g" > "$BOX/redlog.sh"
printf 'module example.com/redprobe\n\ngo 1.21\n' > "$RM/go.mod"
printf 'package good\n\nimport "testing"\n\nfunc TestGreen(t *testing.T) {}\n' > "$RM/good/good_test.go"
printf 'package bad\n\nimport "testing"\n\nfunc TestRedProbeFails(t *testing.T) {\n\tt.Errorf("строка отказа: ждали %%d, получили %%d", 2, 3)\n}\n' > "$RM/bad/bad_test.go"
cat > "$RW/cmd.sh" <<EOF
d="$RW/ci/run-1"
( cd "$RM" && go test -short "\${1:-./...}" ) > "\$d/log-26-go-test-short.txt" 2>&1; t=\$?
printf 'level=error msg="pod $FAKE_POD_IP: x.go:1: unused"\n' > "\$d/log-27-golangci-lint.txt"
printf 'gosec: не поставлен\n' > "\$d/log-28-gosec.txt"
echo "== go vet"; echo "   ok"
echo "== go test -short"
if [ "\$t" -ne 0 ]; then echo "   ОТКАЗ (код \$t)"; tail -3 "\$d/log-26-go-test-short.txt" | sed 's/^/   | /'; echo "   | целиком: \$d/log-26-go-test-short.txt"; else echo "   ok"; fi
echo "== gosec"; echo "   ПРОПУСК: инструмента нет — НЕ выполнено"; echo "   | целиком: \$d/log-28-gosec.txt"
echo "== golangci-lint"
if [ "\$t" -ne 0 ]; then echo "   ОТКАЗ (код 1)"; echo "   | целиком: \$d/log-27-golangci-lint.txt"; exit 1; fi
echo "   ok"
EOF
rg_step() { ( cd "$RW" && env GOTOOLCHAIN=local GOFLAGS=-mod=mod GOWORK=off bash "$BOX/redlog.sh" bash "$RW/cmd.sh" "$@" ) > "$OUT" 2>&1; RC=$?; }
digest_names() { grep -q '^   ! .*example\.com/redprobe/bad' "$1" && grep -q '^   ! .*TestRedProbeFails' "$1" \
                 && grep -q '^   ! .*bad_test\.go:6: строка отказа: ждали 2, получили 3' "$1"; }
if ! command -v go >/dev/null 2>&1; then OUT=""; bad RG1 "go нет в PATH — синтетического прогона с упавшим тестом не построить (не выполнилось)"
else
    OUT="$BOX/rg1.stream"; rg_step
    expect_rc RG1 1
    if digest_names "$OUT"; then ok; else bad RG1 "дайджест не называет пакет, тест и строку отказа"; fi
    if grep -qx 'remote-heavy-redlog: total 2 4' "$OUT" && [ "$(grep -c '^remote-heavy-redlog: begin ' "$OUT")" -eq 2 ] \
       && grep -q '^remote-heavy-redlog: begin 1 log-26-go-test-short.txt ' "$OUT" && grep -q '^remote-heavy-redlog: begin 2 log-27-golangci-lint.txt ' "$OUT"; then ok
    else bad RG1 "копий не ровно две красные группы (ПРОПУСК и ok не копируются) либо итог не «total 2 4»"; fi
    if grep -q '^remote-heavy-red: «golangci-lint» — строк --- FAIL' "$OUT"; then ok; else bad RG1 "красная группа без строк FAIL не названа"; fi
    cp "$OUT" "$BOX/rg1.stream.keep"; cp "$RW/ci/run-1/log-26-go-test-short.txt" "$BOX/rg1.gotest.keep"
    OUT="$BOX/rg1g.stream"; rg_step ./good
    expect_rc RG1-green 0
    if grep -qx 'remote-heavy-redlog: total 0 4' "$OUT" && ! grep -q '^remote-heavy-redlog: begin ' "$OUT"; then ok; else bad RG1-green "итога «total 0 4» нет либо зелёный прогон копирует журналы"; fi
fi
# RG7 — признак OOM шага ИСПОЛНЕНИЕМ: oom_kill cgroup вырос за время команды →
#      «remote-heavy-oom:» в termination-log, код команды сохранён; близнец RG7b —
#      137 без роста → termination-log пуст
if ! grep -q '^# redlog-end$' "$BOX/redlog.sh"; then OUT="$BOX/rg0.cmd"; bad RG7 "шага красных групп в Job нет — признак OOM исполнять нечего"
else
    sed "s#/dev/termination-log#$RW/tl#g" "$BOX/redlog.sh" > "$BOX/redlog-oom.sh"
    printf 'low 0\noom 0\noom_kill 0\n' > "$RW/mev"
    rm -f "$RW/tl"
    ( cd "$RW" && HEAVY_MEM_EVENTS="$RW/mev" bash "$BOX/redlog-oom.sh" bash -c 'printf "oom 1\noom_kill 1\n" > "$1"; exit 137' x "$RW/mev" ) > "$BOX/rg7.out" 2>&1; RC=$?; OUT="$BOX/rg7.out"
    expect_rc RG7 137
    if grep -q '^remote-heavy-oom: .*oom_kill 0 → 1, код 137' "$RW/tl" 2>/dev/null; then ok; else bad RG7 "рост oom_kill не записан в termination-log"; fi
    printf 'oom_kill 3\n' > "$RW/mev"; rm -f "$RW/tl"
    ( cd "$RW" && HEAVY_MEM_EVENTS="$RW/mev" bash "$BOX/redlog-oom.sh" bash -c 'exit 137' ) > "$BOX/rg7b.out" 2>&1; RC=$?; OUT="$BOX/rg7b.out"
    expect_rc RG7b 137
    if [ -e "$RW/tl" ]; then bad RG7b "признак OOM без роста oom_kill"; else ok; fi
fi
# RG8 — фоновый процесс команды унёс её stdout и живёт дольше неё → шаг не ждёт
#      его (≤ 10 с), код — код команды, вывод в копии; на трубе шаг висел бы до срока Job
if grep -q '^# redlog-end$' "$BOX/redlog.sh"; then
    t0="$(date +%s)"
    # shellcheck disable=SC2016  # строка дочерней оболочки, $BASHPID и $1 раскрывает она
    ( cd "$RW" && timeout 25 bash "$BOX/redlog.sh" bash -c '(echo "$BASHPID" > "$1"; exec sleep 40) & echo "строка до выхода"; exit 3' rg8 "$RW/bg.pid" ) > "$BOX/rg8.out" 2>&1; RC=$?; OUT="$BOX/rg8.out"
    dt=$(( $(date +%s) - t0 ))
    [ -s "$RW/bg.pid" ] && kill "$(cat "$RW/bg.pid")" 2>/dev/null
    expect_rc RG8 3
    if [ "$dt" -le 10 ] && grep -qx 'строка до выхода' "$RW/w/heavy-cmd.out" 2>/dev/null; then ok
    else bad RG8 "шаг ждал фонового писателя $dt с либо вывода команды в копии нет"; fi
else OUT="$BOX/rg0.cmd"; bad RG8 "шага красных групп в Job нет"; fi
# RG9–RG13 (приёмка ws#1136, круг 2): шаг над одной красной группой с заданным
# журналом; поток — в $BOX/<имя>.stream, код шага — в RC.
rg_one() {
    local name="$1" src="$2"; shift 2
    # shellcheck disable=SC2016  # строка дочерней оболочки, $1… раскрывает она
    ( cd "$RW" && env "$@" bash "$BOX/redlog.sh" bash -c 'mkdir -p "$1" && cp "$2" "$1/log-30-go-test-short.txt"
echo "== go test -short"; echo "   ОТКАЗ (код 1)"; echo "   | целиком: $1/log-30-go-test-short.txt"; exit 1' rg "$RW/ci/$name" "$src" ) > "$BOX/$name.stream" 2>&1
    RC=$?; OUT="$BOX/$name.stream"
}
okfill() { local i; for ((i = 1; i <= $1; i++)); do printf 'ok  \texample.com/redprobe/p%02d\t0.00%ds\n' "$i" "$((i % 10))"; done; }
# RG9 — два упавших пакета дальше 10 строк друг от друга → дайджест называет ОБА
{ printf -- '--- FAIL: TestAlpha (0.00s)\n    a_test.go:7: альфа сломана\nFAIL\nFAIL\texample.com/redprobe/alpha\t0.003s\n'
  okfill 15
  printf -- '--- FAIL: TestOmega (0.00s)\n    o_test.go:9: омега сломана\nFAIL\nFAIL\texample.com/redprobe/omega\t0.004s\nFAIL\n'; } > "$BOX/rg9.log"
rg_one rg9 "$BOX/rg9.log"
expect_rc RG9 1
if grep -q '^   ! .*TestAlpha' "$OUT" && grep -q '^   ! .*альфа сломана' "$OUT" && grep -q '^   ! .*example\.com/redprobe/alpha' "$OUT" \
   && grep -q '^   ! .*TestOmega' "$OUT" && grep -q '^   ! .*омега сломана' "$OUT" && grep -q '^   ! .*example\.com/redprobe/omega' "$OUT"; then ok
else bad RG9 "дайджест не называет оба упавших пакета, их тесты и строки отказа"; fi
# RG10 — паника в горутине без «--- FAIL», стек длиннее 10 строк → в дайджесте
#      сообщение паники и первый кадр, а не только «FAIL<таб>пакет»
{ printf 'panic: горутина упала: ждали 2, получили 3\n\ngoroutine 18 [running]:\n'
  printf 'example.com/redprobe/gor.worker(0x3)\n\t/src/gor/gor.go:12 +0x1d\n'
  for i in 1 2 3 4 5 6; do printf 'example.com/redprobe/gor.step%d(...)\n\t/src/gor/gor.go:%d +0x2%d\n' "$i" "$((20 + i))" "$i"; done
  printf 'created by example.com/redprobe/gor.TestGoroutine in goroutine 17\n\t/src/gor/gor_test.go:8 +0x25\nFAIL\texample.com/redprobe/gor\t0.005s\nFAIL\n'; } > "$BOX/rg10.log"
rg_one rg10 "$BOX/rg10.log"
expect_rc RG10 1
if [ "$(grep -c -- '--- FAIL' "$BOX/rg10.log")" -eq 0 ] && grep -q '^   ! .*panic: горутина упала: ждали 2, получили 3' "$OUT" \
   && grep -q '^   ! .*gor\.go:12' "$OUT" && grep -q '^   ! .*example\.com/redprobe/gor' "$OUT"; then ok
else bad RG10 "дайджест паники в горутине без сообщения паники, кадра или пакета"; fi
# RG11 — журнал группы больше HEAVY_RED_BYTES → на машине ровно последние байты,
#      обрезка названа; сумма — от отправленного хвоста, а не от файла
for i in $(seq 1 120); do printf 'line %03d of an oversized red group log\n' "$i"; done > "$BOX/rg11.log"
rg_one rg11 "$BOX/rg11.log" HEAVY_RED_BYTES=1000
tail -c 1000 "$BOX/rg11.log" > "$BOX/rg11.tail"
fresh
go_run rg11r env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg11.stream" "${B[@]}" --short rg11r -- true
expect_rc RG11 1
if cmp -s "$BOX/rg11r.out.red-t1-heavy-rg11r/log-30-go-test-short.txt" "$BOX/rg11.tail" \
   && grep -q "1000 байт, последние из $(wc -c < "$BOX/rg11.log") — журнал обрезан пределом" "$OUT"; then ok
else bad RG11 "обрезанная копия не сохранена, не равна хвосту в 1000 байт либо обрезка не названа"; fi
# RG12 — IPv6 pod, IPv4 pod и имя сервера в журнале группы → в ФАЙЛАХ каталога копий
#      ни одного, на их месте маска
printf 'dial tcp [%s]:5432: connect: refused\nGet "https://%s:6443/api": pod %s\n' "$FAKE_POD_IP6" "$SERVER_HOST" "$FAKE_POD_IP" > "$BOX/rg12.log"
rg_one rg12 "$BOX/rg12.log"
fresh
go_run rg12r env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg12.stream" "${B[@]}" --short rg12r -- true
expect_rc RG12 1
RD12="$BOX/rg12r.out.red-t1-heavy-rg12r"
if [ -f "$RD12/log-30-go-test-short.txt" ] && grep -q '<адрес>' "$RD12/log-30-go-test-short.txt" && grep -q '<кластер>' "$RD12/log-30-go-test-short.txt" \
   && ! grep -rqF -e "$FAKE_POD_IP6" -e "$SERVER_HOST" -e "$FAKE_POD_IP" "$RD12"; then ok
else bad RG12 "в файлах каталога копий адрес IPv6, IPv4 или имя сервера без маски либо копии нет"; fi
# RG13 — поток оборван внутри копии (begin и часть data, нет end и total), полный
#      лог есть → копии из полного лога
awk '{ print } /^remote-heavy-redlog: data 1 1 / { exit }' "$BOX/rg1.stream.keep" > "$BOX/rg13.stream"
fresh
go_run rg13 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg13.stream" FAKE_FULL_LOG="$BOX/rg1.stream.keep" "${B[@]}" --short rg13 -- true
expect_rc RG13 1
if grep -q '^remote-heavy-redlog: begin 1 ' "$BOX/rg13.stream" && ! grep -q '^remote-heavy-redlog: \(end\|total\) ' "$BOX/rg13.stream" \
   && cmp -s "$BOX/rg13.out.red-t1-heavy-rg13/log-26-go-test-short.txt" "$BOX/rg1.gotest.keep" && grep -q 'скопировано 2 из 2' "$OUT"; then ok
else bad RG13 "обрыв внутри копии не добран из полного лога контейнера"; fi
# RG2 — тот поток через run.sh: на машине каталог копий рядом с журналом, копии равны
#      журналам pod (адрес — под маской), дайджест в журнале, строк потока копий нет
fresh
go_run rg2 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg1.stream.keep" "${B[@]}" --short rg2 -- true
expect_rc RG2 1
RD="$BOX/rg2.out.red-t1-heavy-rg2"
if [ -d "$RD" ] && cmp -s "$RD/log-26-go-test-short.txt" "$BOX/rg1.gotest.keep"; then ok
else bad RG2 "копии журнала go test в $RD нет либо она не равна журналу группы"; fi
if [ "$(find "$RD" -type f 2>/dev/null | wc -l)" -eq 2 ] && grep -qF 'pod <адрес>: x.go:1: unused' "$RD/log-27-golangci-lint.txt" 2>/dev/null \
   && ! grep -rqF "$FAKE_POD_IP" "$RD"; then ok
else bad RG2 "в каталоге копий не ровно две красные либо адрес pod не замаскирован"; fi
if digest_names "$OUT"; then ok; else bad RG2 "в журнале на машине нет пакета, теста и строки отказа"; fi
if grep -q 'remote-heavy-redlog:' "$OUT"; then bad RG2 "строки потока копий дошли до журнала"; else ok; fi
if grep -qF "скопировано 2 из 2 в $RD" "$OUT" && grep -qF "«go test -short» → $RD/log-26-go-test-short.txt" "$OUT"; then ok; else bad RG2 "итог не называет каталог и файлы"; fi
# RG3 — повтор строк на стыке переподключения (поток дважды) → копии целы
cat "$BOX/rg1.stream.keep" "$BOX/rg1.stream.keep" > "$BOX/rg3.stream"
fresh
go_run rg3 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg3.stream" "${B[@]}" --short rg3 -- true
expect_rc RG3 1
if cmp -s "$BOX/rg3.out.red-t1-heavy-rg3/log-26-go-test-short.txt" "$BOX/rg1.gotest.keep" && grep -q 'скопировано 2 из 2' "$OUT"; then ok
else bad RG3 "повтор строк потока испортил копию"; fi
# RG4 — строка копии выпала → копия НЕ сохранена, причина названа, вторая цела,
#      дайджест на месте; RG4b — строка подменена при том же числе → сумма ловит
grep -v '^remote-heavy-redlog: data 1 2 ' "$BOX/rg1.stream.keep" > "$BOX/rg4.stream"
fresh
go_run rg4 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg4.stream" "${B[@]}" --short rg4 -- true
expect_rc RG4 1
if [ ! -e "$BOX/rg4.out.red-t1-heavy-rg4/log-26-go-test-short.txt" ] && [ -f "$BOX/rg4.out.red-t1-heavy-rg4/log-27-golangci-lint.txt" ] \
   && grep -q '«go test -short» — копия НЕ цела: строк копии' "$OUT" && grep -q 'скопировано 1 из 2.*не скопировано 1' "$OUT" && digest_names "$OUT"; then ok
else bad RG4 "неполная копия сохранена либо причина не названа"; fi
# Подмена — другое содержимое той же длины, сжатое и с верным числом строк: число
# строк и байты сходятся, держит только сумма.
sed '1s/TestRedProbeFails/TestRedProbeFailz/' "$BOX/rg1.gotest.keep" > "$BOX/rg4b.alt"
if [ "$(wc -c < "$BOX/rg4b.alt")" != "$(wc -c < "$BOX/rg1.gotest.keep")" ] || cmp -s "$BOX/rg4b.alt" "$BOX/rg1.gotest.keep"; then
    OUT=""; bad RG4b "подмена не той же длины либо не изменила содержимое — случай пуст"
fi
{ grep -v -e '^remote-heavy-redlog: data 1 ' -e '^remote-heavy-redlog: end 1 ' -e '^remote-heavy-redlog: total ' "$BOX/rg1.stream.keep"
  i=0
  while IFS= read -r c; do i=$((i + 1)); echo "remote-heavy-redlog: data 1 $i $c"; done < <(gzip -c < "$BOX/rg4b.alt" | base64 -w 76)
  echo "remote-heavy-redlog: end 1 $i"
  grep '^remote-heavy-redlog: total ' "$BOX/rg1.stream.keep"; } > "$BOX/rg4b.stream"
fresh
go_run rg4b env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg4b.stream" "${B[@]}" --short rg4b -- true
if [ ! -e "$BOX/rg4b.out.red-t1-heavy-rg4b/log-26-go-test-short.txt" ] && grep -q '«go test -short» — копия НЕ цела: байты или сумма' "$OUT"; then ok
else bad RG4b "подменённая копия сохранена либо причина не названа"; fi
# RG5 — итога в потоке нет (поток оборвался) → разбор полного лога контейнера:
#      копии есть, вывод команды повторно не печатается
printf 'строка до обрыва\n' > "$BOX/rg5.stream"
fresh
go_run rg5 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg5.stream" FAKE_FULL_LOG="$BOX/rg1.stream.keep" "${B[@]}" --short rg5 -- true
expect_rc RG5 1
if [ -f "$BOX/rg5.out.red-t1-heavy-rg5/log-26-go-test-short.txt" ] && grep -q 'разбираю полный лог контейнера' "$OUT" \
   && ! grep -q '^== go vet' "$OUT" && digest_names "$OUT"; then ok
else bad RG5 "полный лог контейнера не разобран либо вывод команды напечатан повторно"; fi
# RG6 — красный код, красных групп нет → строка с числом прочитанных групп, каталога нет;
#      RG6b итога нет нигде → «НЕ получены»
printf 'remote-heavy-redlog: total 0 4\n' > "$BOX/rg6.stream"
fresh
go_run rg6 env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg6.stream" "${B[@]}" --short rg6 -- true
expect_rc RG6 1
if [ "$(red_dirs rg6)" -eq 0 ] && grep -q 'красных групп ci-local в выводе команды нет (групп «== » прочитано 4)' "$OUT"; then ok
else bad RG6 "ноль красных при красном коде не назван числом либо каталог заведён"; fi
fresh
go_run rg6b env FAKE_EXIT=1 FAKE_LOG_FILE="$BOX/rg5.stream" "${B[@]}" --short rg6b -- true
expect_rc RG6b 1
if [ "$(red_dirs rg6b)" -eq 0 ] && grep -q 'журналы красных групп НЕ получены' "$OUT"; then ok; else bad RG6b "отсутствие итога не названо"; fi

# V1 — кластер не отвечает
fresh
go_run v1 env FAKE_DOWN=1 bash "$RUN" --available
expect_rc V1 69
if grep -q 'не отвечает' "$OUT"; then ok; else bad V1 "причина не названа"; fi

# L0 — двойник печатает адрес и IPv4 (иначе L1 пуста)
OUT="$BOX/l0.out"
env FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" FAKE_DOWN=1 \
    "$BOX/bin/kubectl" auth can-i create namespaces > "$OUT" 2>&1
if grep -q "$SERVER_HOST" "$OUT" && grep -q "$SERVER_IP" "$OUT"; then ok; else bad L0 "двойник не печатает адрес — проба утечки пуста"; fi
# L0b — двойник печатает адреса pod (IPv4 и IPv6) в STDOUT лога команды
env FAKE_STATE="$BOX/state" FAKE_HOST="$SERVER_HOST" FAKE_IP="$SERVER_IP" "$BOX/bin/kubectl" logs -f run-x 2>/dev/null > "$OUT"
if grep -qF "$FAKE_POD_IP" "$OUT" && grep -qF "$FAKE_POD_IP6" "$OUT"; then ok; else bad L0b "двойник не печатает адрес pod в stdout — проба F4 пуста"; fi

# L1 — ни адреса, ни IPv4, ни токена, ни пути кубконфига в выводе run.sh
OUT="$ALL_OUT"
for s in "$SERVER_HOST" "$SERVER_IP" "$TOKEN" "$BOX/kubeconfig" "$BOX/probe--lab1.yaml" "$BOX/kc-swap" lab1-client- lab1-infra- lab2-client- "$CTX_CLIENT" "$CTX_INFRA" "$FAKE_NODE_IP" "$FAKE_NODE_IP6" "$FAKE_API_IP" "$FAKE_POD_IP" "$FAKE_POD_IP6"; do
    if grep -qF -- "$s" "$ALL_OUT"; then bad L1 "в выводе run.sh — «$s»"; else ok; fi
done
if [ -s "$ALL_OUT" ]; then ok; else bad L1 "вывод пуст — судить нечего"; fi

printf 'remote-heavy inject: утверждений %d · сошлось %d · разошлось %d\n' $((PASS + FAIL)) "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
