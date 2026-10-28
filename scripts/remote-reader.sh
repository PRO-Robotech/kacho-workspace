#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# remote-reader.sh — python-читатель воркспейса с машины владельца исполняется Job-ом внешнего
# кластера (ws#1365, вариант (б) решения диспетчера; владелец 2026-10-22: машина — не для прогонов).
#
# ФОРМА
#   remote-reader.sh scripts/stand-report.sh <доводы…>   судья kaname: expect, check и ступени
#                                                          import-candidate, register-import, report
#   remote-reader.sh scripts/pr-body.sh <репо> <база> <голова>   (RITUAL_REPO_DIR — как у pr-body.sh)
#   remote-reader.sh scripts/landing-precheck.sh <репо> <N> [--reviews …] [--stand-report … --stand-expect …]
#   remote-reader.sh scripts/ci-read.sh --job-names <файл workflow> <имена на голове>
#   remote-reader.sh scripts/ci-read.sh <владелец/репозиторий> <номер PR | sha40> [--base …] [--head …] [--draft …]
#   remote-reader.sh scripts/branch-audit.sh --generator-outputs <файл генератора>
#       — python-части читателей демона вливания (ws#1365): предпроверка целиком; у branch-audit —
#         лишь форма с python3 (перепись клонов машины в pod не годится). ci-read: --job-names сам
#         уходит сюда; полная форма — вход полос, которым ci-read на машине не положен (владелец
#         2026-10-22), и зовётся сюда ЯВНО: демон вливания читает CI на машине (Job на каждый его
#         опрос не годится); --from-state — 64: снимок демона лежит на машине, Job его не видит
# Зовут его сами входы, руками — незачем. Вход идёт ЗДЕСЬ, а не сюда, лишь там, где машины
# владельца нет либо маршрут уже пройден: pod внешнего кластера (KUBERNETES_SERVICE_HOST ставит
# kubelet), ранер конвейера (GITHUB_ACTIONS=true), сторона pod драйвера (KACHO_REMOTE_READER_POD=1 —
# ставит pod.sh) и локальный слот (HEAVY_SLOT_P — heavy-slot.sh идёт на машине лишь при недоступном
# кластере либо пробе машины; с маркером pod.sh — тот же путь), как владелец
# разрешил. ГРАНИЦА: эти переменные, выставленные на машине руками, маршрут обходят — держится
# вниманием, как и прямой `python3 kaname-stand.py` (в строке команды его отказывает heavy-guard ws#1301).
#
# КАК. Job исполняет КОММИТ (scripts/remote-heavy/run.sh, профиль ws), а входы читателя — файлы
# машины, ответы GitHub (токена в pod нет) и реестр принятых импортов. Поэтому:
#   1. копия: связанный worktree того же коммита, что у копии входа (правки scripts/ вне
#      коммита — отказ 64: Job исполнил бы не их);
#      Архив рецепта «ЗАПУСК» (scripts/ из origin/main вне копии; LANDING_PRECHECK_WS — так зовёт
#      гейты демон вливания) — worktree origin/main того воркспейса, архив сверен с ним файл
#      в файл вместе с режимом (`git diff --no-index`);
#   2. входы: каждый довод — существующий файл — копируется в rr/in, довод заменяется путём
#      от rr; в JSON-входе строка — абсолютный путь к файлу — тоже (пакет импорта, отзывы);
#      каталог доводом — 64, кроме копии expect (--checkout): она едет bundle HEAD, веток и origin/*
#      (правка вне коммита — 64), в pod — клон с тем же origin. Реестр tmp/operator-stand-registry
#      машины — в tmp/ копии. У предпроверки файлы — лишь значения --reviews, --stand-report,
#      --stand-expect; у форм --job-names и --generator-outputs — все доводы после ключа формы;
#      у полной формы ci-read файлов нет (репозиторий, номер, ревизии);
#   3. GitHub: ответы снимает здесь `gh` (на машине он разрешён), pod отдаёт их читателю
#      через STAND_REPORT_GH и RITUAL_GH (scripts/remote-reader/replay-gh.sh). Снимается
#      надмножество по плану читателя: hosted kaname — workflow, коммит, прогоны, задания,
#      журналы заданий; pr-body — задачи с номерами из сообщений диапазона и комментарии;
#      предпроверка — запрос, коммиты, сравнения, check-runs, прогоны и файлы workflow головы,
#      ответы merge-readiness и ci-read внутри (в pod gh — снятый, CI_READ_GH — чтение без условия),
#      комментарии задач из тела, hosted-ступень kaname отчёта стенда; кругов — 4.
#      Чего нет в снятом — промах: читатель отказывает, pod называет вызов, здесь он
#      снимается и прогон повторяется, всего не больше ROUNDS раз. Вызов gh — и плана, и
#      промаха — исполняется, лишь если он из ЗАКРЫТОГО перечня чтений (gh_read_ok ниже):
#      промах называет pod, и машина своим токеном исполнила бы что угодно (ws#1365);
#      прочее — отказ строкой «вне перечня чтений», вызова нет. Учётные данные в pod не едут:
#      адрес origin копии — без userinfo, путь внутри JSON-входа в хранилище учётных данных
#      машины (secret_path) не переносится;
#   4. коммит копии (локальный, не публикуется), `heavy-slot.sh suite -- bash
#      ../scripts/remote-reader/pod.sh …` из rr — ведомость PORTABLE слота;
#   5. вывод: pod печатает stdout, stderr, промахи и новые файлы реестра base64 строками
#      с номером; повтор строк при переподключении потока снимается по номеру, пропуск
#      номера либо размер не тот — 70. Новые файлы реестра ложатся в реестр машины, уже
#      существующий иной — 70 (save_new судьи не перезаписывает).
# КОДЫ: код читателя; 64 — вызов неверен; 70 — поток вывода либо реестр не сходятся либо отказ
# стороны pod (привязка клона Job: строка «remote-reader: Job: <проверка>: ожидалось …; получено …»);
# прочие коды слота (69, 74, 75, 77) — его, «не выполнилось»: строки кода читателя нет.
# Копия и её каталог снимаются при любом исходе; журнал Job — tmp/remote-reader/<метка>.log
# основного клона — остаётся лишь на отказе.
# ГРАНИЦА: kacho и ступени операторов не идут — решение диспетчера ws#1365 их не называет, а
# чтений GitHub их судей план драйвера не знает (промахи снимались бы по одному); отчёт стенда
# kacho либо оператора в предпроверке судит stand-report.sh в pod — его чтения снимаются промахами.
set -uo pipefail
ROUNDS=3
say() { printf 'remote-reader: %s\n' "$*" >&2; }
die() { local c="$1"; shift; say "$*"; exit "$c"; }

# ЗАКРЫТЫЙ ПЕРЕЧЕНЬ ЧТЕНИЙ GitHub, которые машина исполняет своим токеном (ws#1365). Форма —
# ровно та, что строят план драйвера и читатели в pod; всё прочее — 1, вызова нет:
#   api [--method GET] [--paginate] [--allow-escape-sequences] <repos/<вл>/<имя>[/…][?…] | rate_limit>
#   pr|issue|run view <номер> [-R <вл>/<имя>] [--json <поля>]
#   pr|issue|run list [-R <вл>/<имя>] [--json <поля>] [-L <число>]
# Довод — латиница, цифры и знаки адреса, без пробелов и управляющих; ключ — отдельным доводом
# (`--method=…`, `-XGET` — отказ); сегмент `.`/`..`, полный URL, graphql, тело (-f/-F/--input),
# заголовки, --jq/--template (jq видит окружение), --hostname, --verbose — вне перечня.
RR_ARG_RE='^[A-Za-z0-9_.,/%@:+=~&?-]+$'
RR_REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
RR_EP_RE='^/?(rate_limit|repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.,%@:+=~-]+)*(\?[A-Za-z0-9_.,%@:+=~&/-]*)?)$'
RR_DOT_RE='(^|/)\.\.?(/|\?|$)'
gh_read_ok() {  # gh_read_ok <доводы gh> — 0, если вызов из закрытого перечня чтений
    local a sub ep=0 pos=0
    [ $# -gt 0 ] || return 1
    for a in "$@"; do [[ "$a" =~ $RR_ARG_RE ]] || return 1; done
    case "$1" in
        api)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --paginate|--allow-escape-sequences) ;;
                    --method) [ "${2:-}" = GET ] || return 1; shift ;;
                    -*) return 1 ;;
                    *) [ "$ep" = 0 ] && [[ "$1" =~ $RR_EP_RE ]] && ! [[ "$1" =~ $RR_DOT_RE ]] || return 1; ep=1 ;;
                esac
                shift
            done
            [ "$ep" = 1 ] ;;
        pr|issue|run)
            sub="${2:-}"; [ "$sub" = view ] || [ "$sub" = list ] || return 1
            shift 2
            while [ $# -gt 0 ]; do
                case "$1" in
                    -R) [[ "${2:-}" =~ $RR_REPO_RE ]] || return 1; shift ;;
                    --json) [[ "${2:-}" =~ ^[A-Za-z]+(,[A-Za-z]+)*$ ]] || return 1; shift ;;
                    -L) [ "$sub" = list ] && [[ "${2:-}" =~ ^[1-9][0-9]{0,3}$ ]] || return 1; shift ;;
                    -*) return 1 ;;
                    *) [ "$sub" = view ] && [ "$pos" = 0 ] && [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 1; pos=1 ;;
                esac
                shift
            done
            [ "$sub" = list ] || [ "$pos" = 1 ] ;;
        *) return 1 ;;
    esac
}

# Хранилища учётных данных машины и псевдо-ФС: файл оттуда в pod не переносится (ws#1365).
# ГРАНИЦА: перечень мест — не обход; верхний довод входа — выбор вызывающего, путь внутри
# JSON-входа — содержимое файла, и для обоих судится одно и то же.
secret_path() {  # secret_path <путь> — 0, если путь (после разрешения ссылок) — в таком месте
    local r h="${HOME:-/nonexistent}"
    r="$(realpath -e -- "$1" 2> /dev/null)" || return 0
    case "$r/" in
        /proc/*|/sys/*|/dev/*|/etc/*|/run/*|*/.git/*) return 0 ;;
        "$h"/.ssh/*|"$h"/.gnupg/*|"$h"/.config/*|"$h"/.kube/*|"$h"/.docker/*|"$h"/.aws/*|"$h"/.claude/*|"$h"/.admin/*) return 0 ;;
        "$h"/.netrc/*|"$h"/.git-credentials/*|"$h"/.pgpass/*|"$h"/.local/share/keyrings/*) return 0 ;;
    esac
    return 1
}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Явная привязка воркспейса (LANDING_PRECHECK_WS) сильнее объемлющей копии git: архив, лёгший в
# чужой репозиторий, судится по воркспейсу привязки, а не по чужому корню. Привязка — корень копии.
if [ -n "${LANDING_PRECHECK_WS:-}" ]; then
    TOP="$(git -C "$LANDING_PRECHECK_WS" rev-parse --show-toplevel 2>/dev/null)" || die 64 "LANDING_PRECHECK_WS «$LANDING_PRECHECK_WS» — не копия git"
    [ "$(realpath -- "$LANDING_PRECHECK_WS")" = "$(realpath -- "$TOP")" ] || die 64 "workspace binding is not the repository root"
else
    TOP="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || TOP=""
fi
ENTRY="${1:-}"; [ $# -gt 0 ] && shift
case "$ENTRY" in
    scripts/stand-report.sh|scripts/pr-body.sh|scripts/landing-precheck.sh) ;;
    scripts/ci-read.sh)
        for a in "$@"; do
            [ "$a" != --from-state ] || die 64 "ci-read.sh --from-state — снимок демона лежит на машине, Job его не видит: без ключа — живое чтение Job-ом"
        done ;;
    scripts/branch-audit.sh) [ "${1:-}" = --generator-outputs ] || die 64 "branch-audit.sh — лишь формой --generator-outputs (перепись судит клоны машины)" ;;
    *) die 64 "вход «$ENTRY» вне перечня (scripts/stand-report.sh, scripts/pr-body.sh, scripts/landing-precheck.sh, scripts/ci-read.sh, scripts/branch-audit.sh --generator-outputs)" ;;
esac
# Ревизия Job. Копия: HEAD копии, где лежит вход. Архив рецепта «ЗАПУСК» (scripts/ из origin/main в
# каталог вне копии, LANDING_PRECHECK_WS — воркспейс; так зовёт гейты демон вливания): origin/main
# того воркспейса, и архив обязан совпасть с ним файл в файл — иначе Job исполнил бы не то, что
# вызвано (64). Правка scripts/ вне коммита в копии привязки — 64 в обоих видах.
REV=HEAD; ARCHIVE=0
if ! { [ -n "$TOP" ] && [ "$TOP/scripts" -ef "$HERE" ]; }; then
    [ -n "${LANDING_PRECHECK_WS:-}" ] || die 64 "$HERE — не scripts/ копии git воркспейса и не архив рецепта «ЗАПУСК» (LANDING_PRECHECK_WS не задан)"
    REV="$(git -C "$TOP" rev-parse --verify -q 'refs/remotes/origin/main^{commit}')" || die 64 "в $TOP нет origin/main — архив рецепта сверить не с чем"
    ARCHIVE=1
fi
[ -z "$(git -C "$TOP" status --porcelain --untracked-files=no -- scripts)" ] ||
    die 64 "в $TOP правки scripts/ вне коммита — Job исполнил бы коммит, а не их: закоммить и повтори"

branch_task() { local b; b="$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null)" && [[ "$b" =~ ^([1-9][0-9]*) ]] && printf '%s' "${BASH_REMATCH[1]}"; }
TASK="${KACHO_TASK:-}"
[ -n "$TASK" ] || TASK="$(branch_task "$PWD")" || TASK=""
[ -n "$TASK" ] || TASK="$(branch_task "$TOP")" || TASK=""
[ -n "$TASK" ] || TASK="$(branch_task "${RITUAL_REPO_DIR:-/nonexistent}")" || TASK=""
# Голова pr-body — ВЕТКА копии (refs/heads либо refs/remotes/origin) с номером: голой `<N>` (правило
# веток kaname) либо `<N>-…` — тоже номер задачи (ws#1402, урок d3555257: ветка kaname «997» при копии
# не на ней — 64). Номер берётся лишь у имени, которое резолвится веткой: короткий sha из одних цифр
# веткой не является.
head_task() {
    local d="$1" b="${2#refs/heads/}"; b="${b#refs/remotes/}"; b="${b#origin/}"
    git -C "$d" show-ref -q --verify "refs/heads/$b" 2>/dev/null || git -C "$d" show-ref -q --verify "refs/remotes/origin/$b" 2>/dev/null || return 1
    [[ "$b" =~ ^([1-9][0-9]*)(-|$) ]] && printf '%s' "${BASH_REMATCH[1]}"
}
if [ -z "$TASK" ] && [ "$ENTRY" = scripts/pr-body.sh ]; then TASK="$(head_task "${RITUAL_REPO_DIR:-$PWD}" "${3:-}")" || TASK=""; fi
[[ "$TASK" =~ ^[1-9][0-9]*$ ]] || die 64 "номер задачи для ns Job не установить: KACHO_TASK=<N> либо ветка <N>-… (каталог, копия входа, RITUAL_REPO_DIR; у pr-body — и ветка-голова <N> либо <N>-…)"

COMMON="$(git -C "$TOP" rev-parse --path-format=absolute --git-common-dir)"
WSROOT="$(dirname "$COMMON")"
# Реестр — тот, что открыл бы судья на машине (operator-stand.py registry()).
RSRC="${LANDING_PRECHECK_WS:-$HERE}"
RROOT="$(git -C "$RSRC" rev-parse --show-toplevel 2>/dev/null)" || die 64 "привязка реестра «$RSRC» — не копия git"
[ -z "${LANDING_PRECHECK_WS+x}" ] || [ "$(realpath -- "$RSRC")" = "$(realpath -- "$RROOT")" ] || die 64 "workspace binding is not the repository root"
canonical_origin() {
    case "$1" in
        git@github.com:PRO-Robotech/kacho-workspace.git|https://github.com/PRO-Robotech/kacho-workspace.git|https://github.com/PRO-Robotech/kacho-workspace) return 0 ;;
        *) return 1 ;;
    esac
}
SOURCE_ORIGIN="$(git -C "$TOP" remote get-url origin 2>/dev/null)" || die 64 "workspace origin missing"
REGISTRY_ORIGIN="$(git -C "$RROOT" remote get-url origin 2>/dev/null)" || die 64 "registry workspace origin missing"
canonical_origin "$SOURCE_ORIGIN" && canonical_origin "$REGISTRY_ORIGIN" || die 64 "workspace repository differs"
REG="$(dirname "$(git -C "$RROOT" rev-parse --path-format=absolute --git-common-dir)")/tmp/operator-stand-registry"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
BOX="$WSROOT/tmp/remote-reader/$STAMP"
WT="$BOX/wt"; RR="$WT/rr"; LOG="$WSROOT/tmp/remote-reader/$STAMP.log"
mkdir -p "$BOX" || die 69 "каталог $BOX не создан"
cleanup() {
    git -C "$TOP" worktree remove --force "$WT" >/dev/null 2>&1
    rm -rf -- "$BOX"
}
trap cleanup EXIT
git -C "$TOP" worktree add -q --detach "$WT" "$REV" 2>/dev/null || die 69 "копия $WT не создана"
# Сверка — файл в файл, вместе с режимом и видом файла (исполнимость, символьная ссылка, лишний
# и недостающий): архив, разошедшийся с origin/main хоть битом режима, исполнил бы не вызванное.
[ "$ARCHIVE" = 0 ] || git -c core.filemode=true diff --no-index --quiet --no-ext-diff --no-textconv -- "$WT/scripts" "$HERE" ||
    die 64 "архив $HERE не совпадает с origin/main ${REV:0:12} воркспейса $TOP — Job исполнил бы не вызванное"
mkdir -p "$RR/in" "$RR/gh" && : > "$RR/gh/index.jsonl"
# Адрес — без userinfo (`https://<учётка>@…`): учётные данные в pod не едут.
no_userinfo() { sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#'; }
# Адрес origin воркспейса — pod.sh (лишь канонический, сверен выше): клону Job без origin он
# заводится, у клона с origin (remote-heavy/run.sh) сверяется репозиторий, а не написание (ws#1403).
printf '%s\n' "$SOURCE_ORIGIN" > "$RR/workspace-origin" || die 69 "workspace origin binding not written"

# Каталог на вход — свой (mktemp): ship* зовутся подстановкой $(…), и счётчик в подоболочке не
# доживал до следующего вызова — одноимённые входы из разных каталогов ложились в один путь.
ship_plain() {  # ship_plain <файл> — копия в rr/in, печатает путь от rr
    local d
    secret_path "$1" && { say "«$1» — хранилище учётных данных машины либо псевдо-ФС: в pod не переносится"; return 1; }
    d="$(mktemp -d "$RR/in/f.XXXXXX")" || return 1
    cp -- "$1" "$d/$(basename -- "$1")" || return 1
    printf '%s' "${d#"$RR/"}/$(basename -- "$1")"
}
ship() {  # ship <файл> — то же, и в JSON-входе абсолютные пути к файлам машины — путями от rr
    local dst p q tmp
    dst="$(ship_plain "$1")" || return 1
    if jq -e . "$RR/$dst" > /dev/null 2>&1; then
        while IFS= read -r p; do
            [ -f "$p" ] || continue
            # Путь внутри JSON — содержимое файла, не выбор вызывающего: хранилище учётных
            # данных не переносится, строка остаётся как есть (читатель в pod его не найдёт).
            secret_path "$p" && { say "путь «$p» в $1 — хранилище учётных данных машины: в pod не переносится"; continue; }
            q="$(ship_plain "$p")" || return 1
            tmp="$RR/$dst.tmp"
            jq --arg a "$p" --arg b "$q" '(.. | select(type == "string" and . == $a)) |= $b' "$RR/$dst" > "$tmp" &&
                mv -- "$tmp" "$RR/$dst" || return 1
        done < <(jq -r '[.. | strings | select(startswith("/"))] | unique[]' "$RR/$dst")
    fi
    printf '%s' "$dst"
}

ship_checkout() {  # ship_checkout <копия> — bundle HEAD, веток и origin/*, адрес origin; печатает метку для pod
    local d dst
    d="$(mktemp -d "$RR/in/c.XXXXXX")" || return 1
    dst="${d#"$RR/"}/checkout.bundle"
    git -C "$1" bundle create "$RR/$dst" HEAD --branches --remotes=origin > /dev/null 2>&1 || return 1
    git -C "$1" remote get-url origin 2> /dev/null | no_userinfo > "$d/checkout.url" &&
        [ -s "$d/checkout.url" ] || return 1
    printf '@checkout:%s' "$dst"
}

ORIG=("$@"); EXTRA=()
has_arg() { local a; for a in "${ORIG[@]}"; do [ "$a" = "$1" ] && return 0; done; return 1; }
ARGS=(); prev=""
# Доводы pr-body — имя, ревизии, не файлы: переносится лишь копия его репозитория (ниже).
[ "$ENTRY" = scripts/pr-body.sh ] && ARGS=("$@") && set --
# Предпроверка посадки: файлы — лишь значения --reviews, --stand-report, --stand-expect (репозиторий
# и номер — не пути, даже если в каталоге вызова лежит одноимённый файл). Формы --job-names и
# --generator-outputs: после ключа формы — только файлы; полная форма ci-read — без файлов, как есть.
if [ "$ENTRY" = scripts/ci-read.sh ] && [ "${1:-}" != --job-names ]; then
    ARGS=("$@"); set --
elif [ "$ENTRY" = scripts/landing-precheck.sh ]; then
    for a in "$@"; do
        case "$prev" in
            --reviews|--stand-report|--stand-expect)  # не файл — довод как есть: отказ скажет предпроверка
                if [ -f "$a" ]; then a="$(ship_plain "$a")" || die 69 "вход «$a» не скопирован"; fi ;;
        esac
        ARGS+=("$a"); prev="$a"
    done
    set --
elif [ "$ENTRY" = scripts/ci-read.sh ] || [ "$ENTRY" = scripts/branch-audit.sh ]; then
    ARGS=("$1"); shift
    for a in "$@"; do
        [ -f "$a" ] || die 64 "довод формы «$a» — не файл"
        a="$(ship_plain "$a")" || die 69 "вход «$a» не скопирован"
        ARGS+=("$a")
    done
    set --
fi
for a in "$@"; do
    if [ "$prev" = --checkout ] && [ -d "$a" ]; then
        # expect судит голову копии, Job получает её коммитом: правка вне коммита — отказ, а не
        # тихий суд другого дерева; ветка копии — доводом --ref (в pod копия отсоединена).
        [ -z "$(git -C "$a" status --porcelain --untracked-files=all 2> /dev/null)" ] ||
            die 64 "в копии «$a» правки вне коммита — expect судил бы не голову"
        ref="$(git -C "$a" symbolic-ref -q HEAD 2> /dev/null)" || ref=""
        # Копия без ветки и без --ref: судья выводит ref из ветки, клон Job отсоединён — отказ здесь,
        # а не «producer command failed: git» после Job (уроки daaa30fd, dff7480a; ws#1428).
        [ -n "$ref" ] || has_arg --ref ||
            die 64 "копия «$a» без ветки источника (HEAD отсоединена): expect выводит ref из ветки — переключи копию на ветку либо передай --ref refs/heads/<ветка>"
        a="$(ship_checkout "$a")" || die 69 "копия «$prev» не упакована"
        ARGS+=("$a"); prev="$a"
        has_arg --ref || [ -z "$ref" ] || EXTRA=(--ref "$ref")
        continue
    fi
    [ -d "$a" ] && die 64 "довод «$a» — каталог: Job-у он не переносится"
    [ -f "$a" ] && secret_path "$a" && die 64 "довод «$a» — хранилище учётных данных машины либо псевдо-ФС: в pod не переносится"
    if [ -f "$a" ]; then
        # Пути внутри JSON переносятся лишь у пакета импорта и перечня отзывов: ожидаемое и
        # отчёт судья сверяет отпечатком содержимого, и правка их строк сменила бы его.
        case "$prev" in --packet|--hosted-reviews) a="$(ship "$a")" ;; *) a="$(ship_plain "$a")" ;; esac ||
            die 69 "вход «$a» не скопирован"
    fi
    ARGS+=("$a"); prev="$a"
done
ARGS+=("${EXTRA[@]}")
[ -d "$REG" ] && { mkdir -p "$WT/tmp/operator-stand-registry" && cp -R -- "$REG/." "$WT/tmp/operator-stand-registry/"; }

declare -A GOT=()
LAST=""
gh_fetch() {  # gh_fetch <доводы gh> — ответ, текст отказа и код в rr/gh, строка указателя; повтор не снимается
    local key rc
    key="$(printf '%s\n' "$@" | jq -Rsc 'split("\n")[:-1]')"  # не --args: доводы вида --method он съел бы
    if [ -n "${GOT[$key]:-}" ]; then LAST="${GOT[$key]#* }"; return "${GOT[$key]%% *}"; fi
    # Подоболочкой: [[ =~ ]] перечня затёр бы BASH_REMATCH вызывающего (план читает его после gh_fetch).
    ( gh_read_ok "$@" ) || { say "вызов gh вне перечня чтений — не исполнен: ${key:0:200}"; LAST=""; return 126; }
    LAST="gh/$(( ${#GOT[@]} + 1 ))"
    # stderr — данные ответа, как stdout: отказ площадки («Branch not protected», HTTP 404) читатель
    # различает лишь по его тексту (ci-read.sh: «защиты нет» против VOID «не прочитана»).
    gh "$@" > "$RR/$LAST" 2> "$RR/$LAST.err"; rc=$?
    GOT[$key]="$rc $LAST"
    jq -cn --argjson argv "$key" --arg out "$LAST" --arg err "$LAST.err" --argjson rc "$rc" \
        '{argv: $argv, rc: $rc, out: $out, err: $err}' >> "$RR/gh/index.jsonl"
    return "$rc"
}
gh_pages() {  # gh_pages <поле|-> <путь без per_page> <доводы gh перед путём…> — страницы до неполной
    local field="$1" path="$2" sep='?' page=1 n
    case "$path" in *\?*) sep='&' ;; esac
    while [ "$page" -le 100 ]; do
        gh_fetch "${@:3}" "$path${sep}per_page=100&page=$page" || return 1
        n="$(jq -r --arg f "$field" 'if $f == "-" then length else (.[$f] // [] | length) end' "$RR/$LAST" 2>/dev/null)" || return 1
        [ "${n:-0}" -ge 100 ] || return 0
        page=$(( page + 1 ))
    done
}

opt() {  # opt <имя> — значение довода --имя из исходных доводов
    local want="$1" prev="" a
    for a in "${ORIG[@]}"; do [ "$prev" = "$want" ] && { printf '%s' "$a"; return 0; }; prev="$a"; done
    return 1
}

plan_kaname_hosted() {  # ответы GitHub для hosted-ступени kaname (report без --external-only, check полного)
    local exp events
    exp="$(opt --expected || opt --expect)" || return 0
    has_arg --external-only && return 0
    case "${ORIG[0]:-}" in
        report) events="$(opt --events)" || return 0; events="$(cat -- "$events")" ;;
        import-candidate|register-import|expect) return 0 ;;
        check) events="$(jq -c '.events // {}' "${ORIG[1]}" 2>/dev/null)" || return 0 ;;
        *) events="$(jq -c '.events // {}' "${ORIG[0]}" 2>/dev/null)" || return 0 ;;
    esac
    hosted_reads "$exp" "$events"
}

hosted_reads() {  # <ожидаемое kaname> <события JSON> — workflow, коммит, прогоны, задания, журналы hosted-заданий
    local exp="$1" events="$2" repo head branch file event key id attempt
    [ "$(jq -r '.repo // empty' "$exp" 2>/dev/null)" = PRO-Robotech/kaname ] || return 0
    repo=PRO-Robotech/kaname; head="$(jq -r .head "$exp")"; branch="$(jq -r '.ref | ltrimstr("refs/heads/") | @uri' "$exp")"
    while IFS=$'\t' read -r file event; do
        gh_fetch api "repos/$repo/contents/.github/workflows/$file?ref=$head"
        gh_fetch api "repos/$repo/git/commits/$head"
        gh_pages workflow_runs "repos/$repo/actions/workflows/$file/runs?event=$event&head_sha=$head&branch=$branch" api || continue
        while IFS=$'\t' read -r id attempt; do
            gh_pages jobs "repos/$repo/actions/runs/$id/attempts/$attempt/jobs" api || continue
            while IFS= read -r key; do
                gh_fetch api --allow-escape-sequences "repos/$repo/actions/jobs/$key/logs"
            done < <(jq -r --arg p "repos/$repo/actions/runs/$id/attempts/$attempt/jobs?" \
                        'select(.argv[1] | startswith($p)) | .out' "$RR/gh/index.jsonl" |
                     while IFS= read -r o; do jq -r '.jobs[]?.id' "$RR/$o" 2> /dev/null; done)
        done < <(jq -r --arg p "repos/$repo/actions/workflows/$file/runs?" \
                    'select(.argv[1] | startswith($p)) | .out' "$RR/gh/index.jsonl" |
                 while IFS= read -r o; do
                     jq -r --arg h "$head" '.workflow_runs[]? | select(.head_sha == $h) | "\(.id)\t\(.run_attempt)"' "$RR/$o" 2> /dev/null
                 done | sort -u)
    done < <(jq -r --argjson ev "$events" '.definitions | to_entries[] | select(.value.executor == "github-hosted")
                | [(.value.workflow_job | split(":")[0]), ($ev[.key] // empty)] | select(length == 2) | @tsv' "$exp" | sort -u)
}

plan_pr_body() {  # задачи номеров из сообщений диапазона (надмножество) и комментарии задач репозитория запроса
    local repo="${ORIG[0]:-}" base="${ORIG[1]:-}" head="${ORIG[2]:-}" rrd="${RITUAL_REPO_DIR:-$PWD}" n r trunks
    trunks="$(awk -F'\t' '!/^[[:space:]]*#/ && NF {print $1}' "$TOP/scripts/ci-read-expected.tsv" 2>/dev/null | sort -u)"
    while IFS= read -r n; do
        if gh_fetch api --method GET "repos/$repo/issues/$n"; then
            gh_pages - "repos/$repo/issues/$n/comments" api --method GET
        else
            for r in $trunks; do [ "$r" = "$repo" ] || gh_fetch api --method GET "repos/$r/issues/$n"; done
        fi
    done < <(git -C "$rrd" log --format=%B "$base..$head" 2>/dev/null | grep -oE '#[0-9]+' | tr -d '#' | sort -un)
}

pages_q() {  # pages_q <поле|-> <путь до page=> <после page=N…> — страницы до неполной, адрес — ДОСЛОВНО вызова
    local field="$1" pre="$2" post="$3" page=1 n
    while [ "$page" -le 100 ]; do
        gh_fetch api "$pre$page$post" || return 1
        n="$(jq -r --arg f "$field" 'if $f == "-" then length else (.[$f] // [] | length) end' "$RR/$LAST" 2>/dev/null)" || return 1
        [ "${n:-0}" -ge 100 ] || return 0
        page=$(( page + 1 ))
    done
}

ci_read_reads() {  # ci_read_reads <репо> <голова> <база> — чтения ci-read.sh после головы и базы (надмножество)
    # Адреса — те, что строит scripts/ci-read.sh (CI_READ_GH в pod — чтение без условия: api, apip).
    local repo="$1" head="$2" base="$3" p st f sx
    gh_fetch api --paginate "repos/$repo/commits/$head/check-runs?per_page=100"
    while IFS= read -r p; do gh_fetch api "repos/$repo/check-runs/$p/annotations"; done < <(
        jq -r '.check_runs[]? | select(.status == "completed" and .conclusion == "failure") | .id' "$RR/$LAST" 2>/dev/null | sort -u)
    gh_fetch api "repos/$repo/commits/$head/status"
    gh_fetch api --paginate "repos/$repo/actions/runs?head_sha=$head&per_page=100"
    gh_fetch api "repos/$repo/branches/$base/protection/required_status_checks"
    gh_fetch api "repos/$repo/rules/branches/$base"
    if gh_fetch api "repos/$repo/branches/$base"; then
        st="$(jq -r '.commit.sha // empty' "$RR/$LAST" 2>/dev/null)"
        [[ "$st" =~ ^[0-9a-f]{40}$ ]] && gh_fetch api "repos/$repo/compare/$st...$head"
    fi
    # файлы workflow на голове: условие if у skipped (предпроверка), имена вытесненного (ci-read);
    # прогоны — любой формой чтения (страницами предпроверки и --paginate ci-read)
    while IFS= read -r f; do gh_fetch api "repos/$repo/contents/$f?ref=$head"; done < <(
        jq -r 'select(any(.argv[]; test("/actions/runs\\?head_sha="))) | .out' "$RR/gh/index.jsonl" |
        while IFS= read -r sx; do jq -r '.workflow_runs[]?.path // empty' "$RR/$sx" 2>/dev/null; done | sed 's/@.*//' | sort -u)
    return 0
}

plan_ci_read() {  # ответы GitHub полной формы ci-read.sh; --job-names GitHub не читает
    local repo="${ORIG[0]:-}" ref="${ORIG[1]:-}" base="" head="" a prev=""
    [[ "$repo" =~ $RR_REPO_RE ]] || return 0
    for a in "${ORIG[@]:2}"; do [ "$prev" = --base ] && base="$a"; prev="$a"; done
    gh_fetch api rate_limit
    if [[ "$ref" =~ ^[0-9]+$ ]]; then
        gh_fetch api "repos/$repo/pulls/$ref" || return 0
        head="$(jq -r '.head.sha // empty' "$RR/$LAST" 2>/dev/null)"; base="$(jq -r '.base.ref // empty' "$RR/$LAST" 2>/dev/null)"
    elif [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        head="$ref"
        if [ -z "$base" ]; then
            gh_fetch api "repos/$repo" || return 0
            base="$(jq -r '.default_branch // empty' "$RR/$LAST" 2>/dev/null)"
        fi
    fi
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] && [[ "$base" =~ $RR_ARG_RE ]] || return 0
    ci_read_reads "$repo" "$head" "$base"
}

plan_landing_precheck() {  # ответы GitHub предпроверки посадки и её merge-readiness и ci-read (надмножество)
    # Адреса — те, что строят scripts/landing-precheck.sh, merge-readiness.sh и ci-read.sh (CI_READ_GH в
    # pod — чтение без условия); лишний ответ безвреден (отказ площадки снимается с кодом, как у gh),
    # недостающий — промах, его снимает круг повтора.
    local repo="${ORIG[0]:-}" pr="${ORIG[1]:-}" pull head base bsha href rb rh o r n sx f b
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$pr" =~ ^[0-9]+$ ]] || return 0
    gh_fetch api rate_limit
    gh_fetch api "repos/$repo/pulls/$pr" || return 0
    pull="$RR/$LAST"
    head="$(jq -r '.head.sha // empty' "$pull" 2>/dev/null)"; base="$(jq -r '.base.ref // empty' "$pull" 2>/dev/null)"
    bsha="$(jq -r '.base.sha // empty' "$pull" 2>/dev/null)"; href="$(jq -r '.head.ref // empty' "$pull" 2>/dev/null)"
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || return 0
    # предпроверка: коммиты, сравнение base...head (объявлено больше отданного), check-runs, прогоны, workflow
    pages_q - "repos/$repo/pulls/$pr/commits?per_page=100&page=" ""
    [[ "$bsha" =~ ^[0-9a-f]{40}$ ]] && gh_pages commits "repos/$repo/compare/$bsha...$head" api
    pages_q check_runs "repos/$repo/commits/$head/check-runs?per_page=100&filter=latest&page=" ""
    gh_pages workflow_runs "repos/$repo/actions/runs?head_sha=$head" api
    # merge-readiness
    gh_fetch pr view "$pr" -R "$repo" --json state,baseRefName,baseRefOid,headRefName,headRefOid,mergeStateStatus,statusCheckRollup,body,closingIssuesReferences
    o="$RR/$LAST"
    rb="$(jq -r '.baseRefOid // empty' "$o" 2>/dev/null)"; rh="$(jq -r '.headRefOid // empty' "$o" 2>/dev/null)"
    [[ "$rb" =~ ^[0-9a-f]{40}$ && "$rh" =~ ^[0-9a-f]{40}$ ]] && [ "$rb...$rh" != "$bsha...$head" ] &&
        gh_pages commits "repos/$repo/compare/$rb...$rh" api
    if [[ "$href" =~ ^([0-9]+)(-[^/]*)?$ ]]; then
        gh_fetch api "repos/$repo/issues/${BASH_REMATCH[1]}"; gh_fetch api "repos/$repo/issues/${BASH_REMATCH[1]}/parent"
    fi
    for b in "$base" main; do gh_fetch api "repos/$repo/branches/$b/protection"; done
    gh_fetch api "repos/$repo/actions/workflows/ci.yaml/runs?event=workflow_dispatch&head_sha=$head&per_page=100"
    gh_fetch api "repos/$repo/commits/$head/check-runs?per_page=100&filter=latest"
    # задачи из тела и закрываемые хостингом: комментарии обеими формами (предпроверка — страницами,
    # merge-readiness — --paginate)
    while IFS= read -r r; do
        n="${r##*#}"; r="${r%#*}"; [ -n "$r" ] || r="$repo"
        pages_q - "repos/$r/issues/$n/comments?per_page=100&page=" ""
        gh_fetch api "repos/$r/issues/$n/comments?per_page=100" --paginate
    done < <({ jq -r '.body // ""' "$pull" 2>/dev/null |
                 grep -oE '([[:alnum:]_.-]+/[[:alnum:]_.-]+)?#[0-9]+|github\.com/[[:alnum:]_.-]+/[[:alnum:]_.-]+/issues/[0-9]+' |
                 sed -E 's|^github\.com/||; s|/issues/|#|'
             jq -r '.closingIssuesReferences[]? | "\(.repository.owner.login)/\(.repository.name)#\(.number)"' "$o" 2>/dev/null
           } | sort -u)
    # ci-read внутри merge-readiness (база без контекстов со строкой ведомости)
    ci_read_reads "$repo" "$head" "$base"
    # отчёт стенда — судья kaname (hosted-ступень), события — из отчёта
    f="$(opt --stand-expect)" && [ -f "$f" ] && sx="$(opt --stand-report)" && [ -f "$sx" ] &&
        hosted_reads "$f" "$(jq -c '.events // {}' "$sx" 2>/dev/null || echo '{}')"
    return 0
}

# Копия pr-body: ws — сам клон Job, продукт — project/<имя> его клонов; голова — на origin.
if [ "$ENTRY" = scripts/pr-body.sh ]; then
    RRD="${RITUAL_REPO_DIR:-$PWD}"
    url="$(git -C "$RRD" remote get-url origin 2>/dev/null)" || die 64 "RITUAL_REPO_DIR «$RRD» — не копия git с origin"
    name="${url%.git}"; name="${name##*/}"
    case "$name" in
        kacho-workspace) printf '.\n' > "$RR/env" ;;
        kacho|kaname|corelib) printf 'project/%s\n' "$name" > "$RR/env" ;;
        *) die 64 "копия «$name»: клона его в Job нет (kacho-workspace, kacho, kaname, corelib)" ;;
    esac
    [ -n "$(git -C "$RRD" branch -r --contains "${ORIG[2]:-}" 2>/dev/null)" ] ||
        die 64 "голова «${ORIG[2]:-}» не на origin копии $RRD — клон Job её не увидит: отправь ветку и повтори"
fi
[ "$ENTRY" = scripts/pr-body.sh ] && plan_pr_body
[ "$ENTRY" = scripts/stand-report.sh ] && plan_kaname_hosted
[ "$ENTRY" = scripts/ci-read.sh ] && [ "${ORIG[0]:-}" != --job-names ] && plan_ci_read
# Предпроверка посадки: цепочки чтений длиннее (merge-readiness, ci-read, комментарии) — кругов больше.
[ "$ENTRY" = scripts/landing-precheck.sh ] && plan_landing_precheck && ROUNDS=4

decode() {  # decode <вид> — поток вида из журнала: номера без пропуска, размер — объявленный
    local kind="$1" want got
    want="$(awk -v k="remote-reader-size" -v t="$kind" '$1 == k && $2 == t {print $3; exit}' "$LOG")"
    [ -n "$want" ] || return 1
    awk -v k="remote-reader-$kind" '$1 == k && !seen[$2]++ {print $2 "\t" $3}' "$LOG" | sort -n -k1,1 |
        awk -F'\t' 'BEGIN {e = 1} $1 != e {exit 3} {print $2; e++}' > "$BOX/$kind.b64" || return 1
    base64 -d < "$BOX/$kind.b64" > "$BOX/$kind" 2> /dev/null || return 1
    got="$(wc -c < "$BOX/$kind")"
    [ "$got" = "$want" ]
}

round=1
while :; do
    git -C "$WT" add -A -f rr && { [ ! -d "$WT/tmp/operator-stand-registry" ] || git -C "$WT" add -A -f tmp/operator-stand-registry; } ||
        die 69 "входы читателя в $WT не добавлены"
    git -C "$WT" commit -q --allow-empty -m "#$TASK remote-reader: входы читателя (не публикуется)" ||
        die 69 "коммит входов в $WT не записан"
    ( cd "$RR" && KACHO_TASK="$TASK" bash "$WT/scripts/heavy-slot.sh" --wait 120 suite -- \
        bash ../scripts/remote-reader/pod.sh "$ENTRY" "${ARGS[@]}" ) > "$LOG" 2>&1
    hrc=$?
    rc="$(awk '$1 == "remote-reader-rc" {print $2}' "$LOG" | tail -n 1)"
    if ! [[ "$rc" =~ ^[0-9]+$ ]]; then
        say "строки кода читателя нет — Job не дошёл до читателя (код слота $hrc); журнал $LOG:"
        grep -v '^remote-reader-' "$LOG" | tail -n 20 >&2
        [ "$hrc" -ne 0 ] && exit "$hrc"; exit 69
    fi
    # Отказ стороны pod (привязка клона Job, перепись реестра) называет проверку — диспетчеру, а не «70».
    grep '^remote-reader-fail ' "$LOG" | sed 's/^remote-reader-fail /remote-reader: Job: /' >&2
    for k in out err miss tar; do
        : > "$BOX/$k"
        if grep -q "^remote-reader-size $k " "$LOG"; then
            decode "$k" || { say "поток «$k» вывода Job неполон либо не сходится по размеру — журнал $LOG"; exit 70; }
        fi
    done
    if [ "$rc" -ne 0 ] && [ -s "$BOX/miss" ] && [ "$round" -lt "$ROUNDS" ]; then
        fetched=0
        while IFS= read -r key; do
            # Промах называет pod: исполняется лишь чтение из закрытого перечня (gh_read_ok),
            # доводы — ровно те, что в ключе (строка с переводом строки разбилась бы — отказ).
            argv=()
            if n="$(jq -e 'if type == "array" and length > 0 and all(.[]; type == "string") then length else false end' <<< "$key" 2> /dev/null)"; then
                mapfile -t argv < <(jq -r '.[]' <<< "$key")
            fi
            if [ "${#argv[@]}" -eq 0 ] || [ "${#argv[@]}" != "$n" ] || ! gh_read_ok "${argv[@]}"; then
                say "промах вне перечня чтений GitHub не снимается: ${key:0:200}"; continue
            fi
            gh_fetch "${argv[@]}"; fetched=$(( fetched + 1 ))
        done < "$BOX/miss"
        if [ "$fetched" -gt 0 ]; then
            say "промахов GitHub $fetched — сняты, прогон $(( round + 1 )) из $ROUNDS"
            round=$(( round + 1 )); continue
        fi
    fi
    break
done
cat -- "$BOX/err" >&2
cat -- "$BOX/out"
if [ -s "$BOX/tar" ]; then
    mkdir -p "$REG"
    listing="$(tar -tf "$BOX/tar")" || { say "файлы реестра из Job не читаются"; exit 70; }
    grep -qv '^\(\./\)\?kaname-imports/[0-9a-f]\{64\}\.json$\|^\(\./\)\?kaname-imports/\?$\|^\./$' <<< "$listing" &&
        { say "файлы реестра вне kaname-imports/<64 hex>.json — не приняты; журнал $LOG"; exit 70; }
    mkdir -p "$BOX/reg" && tar -xf "$BOX/tar" -C "$BOX/reg" ||
        { say "файлы реестра из Job не распакованы"; exit 70; }
    while IFS= read -r f; do
        rel="${f#"$BOX/reg/"}"
        if [ -e "$REG/$rel" ]; then
            cmp -s -- "$f" "$REG/$rel" || { say "реестр: $rel уже есть и другой — не перезаписан"; exit 70; }
        else
            mkdir -p "$(dirname -- "$REG/$rel")" && cp -- "$f" "$REG/$rel" || { say "реестр: $rel не записан"; exit 70; }
        fi
    done < <(find "$BOX/reg" -type f)
fi
[ "$rc" -eq 0 ] && rm -f -- "$LOG" || say "код читателя $rc; журнал Job — $LOG"
exit "$rc"
