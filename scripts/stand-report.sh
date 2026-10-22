#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# stand-report.sh — суд ОТЧЁТА ПРОГОНА НА ВНЕШНЕМ КЛАСТЕРЕ до CI (ws#1110).
#
# ЗАЧЕМ. Решение владельца 2026-10-16, дословно: «никогда нельзя решать проблемы по
# одному, сначала делается перепись, потом фиксится, потом прогоняется тесты на
# внешнем кластере, потом в master ci». Замер того же дня: kacho#3259 — пять полных
# кругов CI по 52–63 мин, каждый находил корень, который прогон на стенде нашёл бы за
# минуты; чтение CI прерывалось на первом красном. Порядок держит не внимание, а этот
# суд: PR переводится в ready и вливается лишь при коде 0 по отчёту ТОЙ ЖЕ головы
# (`.claude/workflows/wave.js` шаг mech:stand, `landing-precheck.sh --stand-report`).
# Канон — `ai-tooling.md#at-red-ci-one-round`.
#
# ИСПОЛЬЗОВАНИЕ
#   stand-report.sh expect --checkout <копия> --head <sha40> [--base <ref> --draft true|false] > <ожидаемое.json>
#   stand-report.sh check <отчёт.json> --head <sha40> --expect <ожидаемое.json> [--pr-base <ветка>] [--pr-repo <владелец/имя>]
#   stand-report.sh check <отчёт.json> --head <sha40> --of <прежний отчёт.json>
# ОЖИДАЕМОЕ выводится НЕ из отчёта (судимый не объявляет свою полноту): `expect` берёт
# задания CI, которые голова обязана пройти на кластере, из закрытой ведомости STAND
# ниже и источника репозитория — kacho: выбор детекторов CI (`affected.py
# --github-output`) ∩ задания стенда, теми же функциями `event_mode` и `select` модуля
# `.github/scripts/affected.py` КОПИИ ГОЛОВЫ (второй реализации выбора нет): запрос
# не черновик (`--draft false`) либо база из `full_bases` — полный прогон, все задания;
# черновик в ветку эпика — целевой по путям `<base>...HEAD` (условие задания CI —
# `full == 'true' || contains(jobs, <ключ>)`). kaname: CI без выбора — все задания стенда; kacho-workspace:
# заданий на кластере у CI нет — ВЫВЕДЕННЫЙ ноль. Копия не на голове, репозиторий вне
# ведомости, задание ведомости не найдено в файле workflow головы (ведомость отстала
# от CI), выбор не выполнился, нет --base либо --draft — VOID, не ноль. Полный прогон
# судится лишь против ожидаемого `--draft false` (основание ready и вливания — выбор
# ready, а не черновика: STAND-EXPECT-DRAFT); `--pr-base` — база запроса, с которой
# ожидаемое обязано совпасть (STAND-EXPECT-BASE). Паритет с `--github-output` держит
# `scripts/stand-report-inject.sh` настоящим affected.py ствола kacho.
# МАРШРУТ (ws#1192). `expect` печатает строку ROUTE<TAB><задание><TAB>внешний кластер|локальный|нет
# <TAB>выбрано|не выбрано<TAB><основание><TAB><форма> на КАЖДОЕ задание ведомости STAND и пишет их в
# поле routes ожидаемого. Форма — закрытая ведомость STAND_ROUTE ниже: класс слота и argv, которым
# задание воспроизводится на кластере (`<…>` — место значения прогона). Судья — НАСТОЯЩИЙ
# `heavy-slot.sh --route` этого каталога (второй реализации маршрута нет): external — Job либо ns
# внешнего кластера; local — команда на машине при любом кластере; none — при доступном кластере
# слот откажет 77. Задание стенда, чей стенд поднимает механизм ГОЛОВЫ (стенд own kaname,
# kaname#841), несёт третий элемент — его опрос, когда слот маршрута не назвал внешним (local либо none —
# ws#1301 сделал «нет внешнего пути» отказом 77, ws#1303): подкоманда механизма исполняется в копии
# герметично (env -i, <tmp> — свой временный каталог, кубконфиг не читается) и код 0 значит «механизм
# головы выбирает путь сам и знает внешний»; иной код, файла нет — локальный; копия после опроса
# не чиста — VOID. У задания, которое голова обязана пройти (jobs), маршрут не внешний либо строки
# STAND_ROUTE нет — VOID ДО запуска: прогон был бы неполон либо LOCAL (посадка kaname#871 узнала это
# лишь в прогоне: задание стенда пошло локальным слотом с меткой LOCAL). Маршрут невыбранного задания печатается, не судится.
# Без --of судится ПОЛНЫЙ прогон (mode full) — единственное основание для ready и
# вливания: каждое ожидаемое задание покрыто набором с этим `job`. С --of — прогон
# «только красное» (mode only-red): в нём обязан быть КАЖДЫЙ набор, красный в прежнем
# отчёте; зелёный only-red — основание лишь для полного прогона, не для CI.
#
# ФОРМА ОТЧЁТА (пишет ci-watcher; JSON-объект):
#   head     — sha40 головы, на которой гнали;          mode — full | only-red;
#   context  — контекст кластера; внешний — суффикс -client (remote-heavy/run.sh);
#              иное — лишь при proof формы журнала слота «local … proof=<…>»;
#   ns       — пространство имён прогона;               residue — остаток переписи после (0);
#   planned  — число наборов отчёта (согласованность, не полнота: полноту судит --expect);
#   suites   — [{name, job, outcome: green|red|not-run, executed, total, quote, root, reason}],
#              job — задание CI «<файл workflow>:<ключ>», которое набор воспроизводит;
#   images_rev — ревизия образов стенда (нет — голова);  у набора carried_from — ревизия R,
#              с которой его зелёный ПЕРЕНЕСЁН (ws#1148);  carry_basis — {R: {changed:
#              [пути R..head], inputs: вывод `stand-ns inputs -base R` на голове, inputs_rc,
#              report: отчёт R}} на каждую R переноса и на images_rev ≠ head.
# ПЕРЕНОС (ws#1148): набор переносится с R, лишь когда входы сборки R..head не менялись
# (вывод inputs: код 0, «входов сборки 0», строка на КАЖДЫЙ путь разности ПЛОЩАДКИ —
# `gh api …/compare/R...head`, R — предок головы) и ни один путь разности не в его
# ОБЛАСТИ: ведомость AREA ниже, закрытая — путь вне неё закрывает перенос всем, набор
# whole_tree не переносится никогда; источник — зелёный тот же набор отчёта R, внешний.
# Набор, чей путь изменился, — not-run, пока не прогнан (STAND-REPORT-NOT-RUN). ГРАНИЦА:
# разбиение путей на входы читается из вывода inputs, не пересчитывается (копии нет).
#
# ЧТО СУДИТСЯ — строка REASON<TAB><код><TAB><пояснение> на причину:
#   STAND-REPORT-MISSING   — файла нет, он не JSON-объект или без полей формы;
#   STAND-REPORT-STALE     — head отчёта ≠ --head: прогон о другой голове;
#   STAND-EXPECT-STALE     — ожидаемое выведено для другой головы;
#   STAND-EXPECT-DRAFT     — без --of ожидаемое выбора kacho выведено не для ready;
#   STAND-EXPECT-BASE      — база ожидаемого ≠ --pr-base;
#   STAND-EXPECT-REPO      — репозиторий ожидаемого ≠ --pr-repo: выбор о чужом репозитории;
#   STAND-EXPECT-ROUTE     — у задания ожидаемого нет маршрута routes либо он не external (ws#1192);
#   STAND-EXPECT-LEDGER    — ожидаемое расходится с ведомостью STAND (общей у expect и
#                            check): репозиторий вне её, источник или ledger не её, задание
#                            вне ledger, а полный выбор (source full; affected при
#                            --draft false; full: true) — не все задания ledger;
#   STAND-REPORT-UNCOVERED — ожидаемое задание CI не покрыто ни одним набором отчёта;
#   STAND-REPORT-NOT-FULL  — без --of отчёт не mode full (only-red основанием CI не служит);
#   STAND-REPORT-TRUNCATED — наборов ≠ planned; у зелёного executed < total, executed >
#                            total либо total < 1: «исполнено N из M»;
#   STAND-REPORT-RED       — набор red (печатается дословная цитата и корень);
#   STAND-REPORT-NO-QUOTE  — у red нет цитаты отказа: класс корня без цитаты — не класс;
#   STAND-REPORT-NOT-RUN   — набор not-run без живого послабления ведомости ниже;
#   STAND-RELAX-EXPIRED    — послабление названо, а его задача закрыта: снять строку;
#   STAND-REPORT-NOTHING-RUN — наборы либо ожидаемое есть, а зелёным исполнено 0;
#   STAND-REPORT-LOCAL     — контекст не внешний и proof не формы журнала слота;
#   STAND-REPORT-RESIDUE   — residue ≠ 0;
#   STAND-REPORT-RED-DROPPED — с --of: красный прежде набор в only-red отсутствует;
#   STAND-CARRY-BASIS      — обоснования R нет, R не предок головы, перечень путей или вывод
#                            inputs не о разности площадки (обрезан на 300 — тоже);
#   STAND-CARRY-INPUTS     — входы сборки R..head менялись (ВХОД, код inputs ≠ 0);
#   STAND-CARRY-AREA       — набор читает изменённый путь, путь вне AREA, набор whole_tree;
#   STAND-CARRY-SOURCE     — в отчёте R набора нет либо он не зелёный тем же числом.
#
# ПОСЛАБЛЕНИЯ — закрытая ведомость RELAX ниже: причина not-run → задача, пока открыта.
# Живость спрашивается у площадки (`gh api repos/<репо>/issues/<N>` → state open);
# закрыта — STAND-RELAX-EXPIRED (само истекает, `gate-authoring` §9). «Не выполнилось»
# не зелёное: оно печатается строкой CENSUS поимённо и не засчитывается в исполненное.
#
# ИСХОДЫ: 0 — причин нет; 1 — причины строками REASON; 2 — VOID: довод не тот, нет
# python3, ожидаемого нет либо оно не разбирается, площадка не ответила о послаблении.
# Перепись — строками CENSUS всегда.
# ВХОД ПОДМЕНЯЕМ (scripts/stand-report-inject.sh): STAND_REPORT_GH — вместо `gh`.
# VOID и при переносе: площадка не ответила о разности, репозиторий не установлен.
set -uo pipefail

void() { printf 'VOID\t%s\n' "$1"; printf 'VERDICT\tunread\tкод 2\n'; exit 2; }
command -v python3 > /dev/null 2>&1 || void "нет python3"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Судья маршрута — слот ЭТОГО каталога (правленая копия инструмента в пробах лежит рядом с ним).
SLOT="$HERE/heavy-slot.sh"
# Ведомость заданий CI, которые прогон на кластере воспроизводит, по репозиторию — ОДНА
# для expect и check: source affected — выбор затронутого репозитория ∩ jobs; full — CI
# без выбора, все jobs; none — у CI заданий на кластере нет (выведенный ноль). Задание —
# «<workflow>:<ключ>».
export STAND_JSON='{
  "PRO-Robotech/kacho": ["affected", ["ci.yaml:unit-shard", "ci.yaml:integration", "e2e-newman.yml:shard",
                                       "console-e2e.yml:probes", "production-posture.yml:stand"]],
  "PRO-Robotech/kaname": ["full", ["ci.yml:unit", "ci.yml:integration", "e2e-newman.yml:stand"]],
  "PRO-Robotech/kacho-workspace": ["none", []]
}'
# Ведомость ОБЛАСТЕЙ переноса (ws#1148): запись paths — [пути (** — любые каталоги, * —
# внутри одного), читатели, почему]. Утверждение записи: из наборов стенда эти пути читают
# ТОЛЬКО названные. Читатель и whole_tree (читают всё дерево) — образец имени набора ЛИБО
# его job. jobs — закрытый реестр: набор переносим, лишь если его job в нём и имя совпало
# с образцом этого job (ban6 под другим именем — не переносится). Путь вне записей
# закрывает перенос всем; репозиторий вне ведомости переноса не имеет.
export STAND_AREA_JSON='{
  "PRO-Robotech/kacho": {"whole_tree": ["unit:*", "ci.yaml:unit-shard"],
    "jobs": {"ci.yaml:integration": ["integration:*"], "console-e2e.yml:probes": ["playwright:probes"],
             "production-posture.yml:stand": ["posture:*"],
             "e2e-newman.yml:shard": ["newman:vpc", "newman:compute", "newman:nlb", "newman:storage", "newman:registry",
                                      "newman:geo", "newman:api-gateway", "newman:ban6-external-isolation"]},
    "paths": [
    [["deploy/scripts/assert-ban6-external-isolation.py"], ["newman:ban6-external-isolation", "unit:*", "ci.yaml:unit-shard"],
     "проба ban6 — шаг «гейт — ban» e2e-newman.yml:shard; её --self-test гонит ci.yaml:helm, набором стенда не являющийся"]]}
}'
# Ведомость МАРШРУТОВ (ws#1192): задание → [класс слота, argv формы, опрос механизма стенда
# головы: [путь, [подкоманда…], {окружение}]]. Форма — шаг CI задания (kaname: integrationshard
# зовёт run-integration.sh; unit — go test -race -short); стенд kacho — ns внешнего кластера
# (stand-ns-run), стенд own kaname — его задание шагами ghjob, стенд в ns задачи ставит сам механизм.
# Пробы консоли — ПЕРЕПИСЬ всего набора: `--max-failures=0` снимает `maxFailures: 5` конфига, предел
# времени шага CI, а не вердикта (ws#1284: прогон kacho#3305 исполнил 179 из 320 и встал на пяти
# падениях); перепись — без остановки на красном (CLAUDE.md «Перепись — потом массово»). Форма
# печатается словами оболочки (shlex.join) — копируется как есть.
export STAND_ROUTE_JSON='{
  "PRO-Robotech/kacho": {
    "ci.yaml:unit-shard": ["go-race", ["make", "test-unit", "SHARD=<шард>"]],
    "ci.yaml:integration": ["integration", ["make", "test-integration"]],
    "e2e-newman.yml:shard": ["stand", ["make", "-C", "deploy", "stand-ns-run", "NS=t<задача>-w<k>", "CMD=<шаги шарда>"]],
    "console-e2e.yml:probes": ["stand", ["make", "-C", "deploy", "stand-ns-run", "NS=t<задача>-w<k>", "DIR=ui-future/e2e", "CMD=npx playwright test --max-failures=0"]],
    "production-posture.yml:stand": ["stand", ["make", "-C", "deploy", "stand-ns-run", "NS=t<задача>-w<k>", "STACK=<стек матрицы>", "CMD=<перепись посадки>"]]
  },
  "PRO-Robotech/kaname": {
    "ci.yml:unit": ["go-race", ["go", "test", "./...", "-race", "-short", "-count=1", "-timeout", "25m"]],
    "ci.yml:integration": ["integration", ["env", "INTEGRATION_SHARD=<k>/3", ".github/scripts/run-integration.sh"]],
    "e2e-newman.yml:stand": ["stand", ["python3", "<ws>/scripts/ghjob/ghjob.py", ".github/workflows/e2e-newman.yml", "stand", "<копия>", "<вывод>", "--env", "KANAME_STAND_TASK=<задача>"],
                             [".github/scripts/stand-own.sh", ["census"], {"KANAME_STAND_KUBECONFIG": "<tmp>/нет", "KANAME_STAND_RUNDIR": "<tmp>/run",
                              "KANAME_STAND_PKI": "<tmp>/pki", "KANAME_STAND_BIN": "<tmp>/bin"}]]
  }
}'
if [ "${1:-}" = expect ]; then
    shift; CO=""; HEAD=""; BASE=""; DRAFT=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --checkout) CO="${2:-}"; shift 2 ;;
            --head) HEAD="${2:-}"; shift 2 ;;
            --base) BASE="${2:-}"; shift 2 ;;
            --draft) DRAFT="${2:-}"; [[ "$DRAFT" =~ ^(true|false)$ ]] || void "--draft «$DRAFT» не true|false"; shift 2 ;;
            *) void "неизвестный довод «$1»" ;;
        esac
    done
    [[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$HEAD» не sha40"
    [ -d "$CO" ] || void "копии «$CO» нет"
    got="$(git -C "$CO" rev-parse HEAD 2>/dev/null)" || void "«$CO» не git-копия"
    [ "$got" = "$HEAD" ] || void "копия «$CO» на ${got:0:12}, а не на голове ${HEAD:0:12} — выбор был бы о другой ревизии"
    dirty="$(git -C "$CO" status --porcelain --untracked-files=all 2>/dev/null)" || void "состояние копии «$CO» не читается"
    [ -z "$dirty" ] || void "в копии «$CO» правки вне коммита ($(printf '%s\n' "$dirty" | grep -c .) путей) — выбор был бы не о голове"
    url="$(git -C "$CO" remote get-url origin 2>/dev/null)" || void "у копии «$CO» нет origin — репозиторий не установить"
    CO="$CO" HEAD="$HEAD" BASE="$BASE" DRAFT="$DRAFT" URL="$url" SLOT="$SLOT" WS="$(dirname "$HERE")" exec python3 - <<'PY'
import importlib.util, json, os, re, shlex, shutil, subprocess, sys, tempfile
STAND = json.loads(os.environ['STAND_JSON'])  # ведомость — в шапке скрипта, общая с check
co, head, base, url, draft = os.environ['CO'], os.environ['HEAD'], os.environ['BASE'], os.environ['URL'], os.environ['DRAFT']


def void(msg):
    print('VOID\t' + msg)
    print('VERDICT\tunread\tкод 2')
    sys.exit(2)


m = re.search(r'github\.com[:/]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$', url)
repo = m.group(1) if m else ''
if repo not in STAND:
    void('репозиторий «%s» (origin %s) вне ведомости STAND — ожидаемое не известно, а не ноль' % (repo, url))
source, jobs = STAND[repo]
try:
    import yaml
except ImportError:
    void('нет python3-yaml — задания ведомости в workflow головы не сверить')
for j in jobs:
    wf, key = j.split(':', 1)
    try:
        doc = yaml.safe_load(open(os.path.join(co, '.github', 'workflows', wf), encoding='utf-8'))
    except (OSError, yaml.YAMLError) as e:
        void('workflow %s головы не читается (%s) — ведомость STAND не сверить' % (wf, e))
    if not (isinstance(doc, dict) and isinstance(doc.get('jobs'), dict) and key in doc['jobs']):
        void('задания %s ведомости STAND нет в .github/workflows/%s головы — ведомость отстала от CI' % (j, wf))
want, full, why = list(jobs), True, 'выбора у CI нет'
if source == 'affected':
    if not base or not draft:
        void('%s выбирает затронутое по событию запроса — нужны --base и --draft' % repo)
    # Выбор — функциями детектора CI из копии головы: event_mode решает полный ли прогон
    # (ready, база full_bases), select — задания по путям; копии этой логики здесь нет.
    try:
        spec = importlib.util.spec_from_file_location('stand_affected', os.path.join(co, '.github', 'scripts', 'affected.py'))
        af = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = af  # dataclass модуля ищет его в sys.modules
        sys.dont_write_bytecode = True  # __pycache__ в копии — неотслеживаемый путь, git_changed выбрал бы по нему
        spec.loader.exec_module(af)
        m = af.load_map()
        full, why = af.event_mode(m, 'pull_request', draft, re.sub(r'^(?:refs/remotes/)?origin/', '', base))
        if not full:
            sel = af.select(m, af.git_changed(base))
            if not sel.files:
                void('выбор затронутого %s: дифф %s...HEAD пуст — выбирать не из чего' % (repo, base))
            full, why = sel.full, sel.reason
        picked = set(jobs) if full else set(sel.jobs)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — любой отказ модуля выбора — «не выполнилось», не ноль
        void('выбор затронутого %s (--base %s, --draft %s) не выполнился: %s: %s' % (repo, base, draft, type(e).__name__, str(e)[-200:]))
    # Задание CI исполняется при `if: full == 'true' || contains(jobs, <ключ>)` — ровно это.
    want = [j for j in jobs if j in picked]
# Маршрут каждого задания ведомости (ws#1192) — судья слота и, у стенда механизма головы, его опрос.
ROUTES = json.loads(os.environ['STAND_ROUTE_JSON']).get(repo, {})
LABEL = {'external': 'внешний кластер', 'local': 'локальный', 'none': 'нет'}


def clean():
    p = subprocess.run(['git', '-C', co, 'status', '--porcelain', '--untracked-files=all'], capture_output=True, text=True)
    return p.returncode == 0 and not p.stdout.strip()


def ask_mech(mech):  # (маршрут, основание) по опросу механизма стенда головы
    path, sub, env = mech[0], mech[1], mech[2]
    if not os.path.isfile(os.path.join(co, path)):
        return 'local', 'механизма стенда %s в голове нет — стенд поднять негде, кроме машины' % path
    tmp = tempfile.mkdtemp(prefix='stand-route.')
    try:
        e = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': tmp, 'XDG_CONFIG_HOME': tmp, 'LANG': 'C.UTF-8'}
        e.update({k: v.replace('<tmp>', tmp) for k, v in env.items()})
        try:
            p = subprocess.run(['bash', path] + sub, cwd=co, env=e, capture_output=True, text=True, timeout=60)
            rc, said = p.returncode, (p.stdout + p.stderr).strip().splitlines()
        except subprocess.TimeoutExpired:
            rc, said = 124, ['не ответил за 60 с']
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not clean():
        void('проба механизма стенда %s %s правила копию «%s» — маршрут не судим, копия не о голове' % (path, ' '.join(sub), co))
    first = (said[0] if said else '')[:160]
    if rc == 0:
        return 'external', 'стенд ставит механизм головы %s сам: «%s» отвечает выбором пути (код 0) — при доступном кластере ns задачи' % (path, ' '.join(sub))
    return 'local', 'механизм стенда головы %s внешнего пути не знает: «%s» — код %d, «%s»' % (path, ' '.join(sub), rc, first)


routes, bad = {}, []
for j in jobs:
    r = ROUTES.get(j)
    if not r:
        route, rwhy, cls, form = 'none', 'строки ведомости STAND_ROUTE нет — как воспроизвести задание на кластере, не объявлено', '', []
    else:
        cls, form = r[0], [a.replace('<ws>', os.environ['WS']) for a in r[1]]
        try:
            p = subprocess.run(['bash', os.environ['SLOT'], '--route', cls, '--'] + form, cwd=co, capture_output=True, text=True, timeout=60)
            m = re.search(r'^ROUTE\t(external|local|none)\t(.*)$', p.stdout, re.M) if p.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            m, p = None, None
        if not m:
            void('heavy-slot.sh --route %s (%s) о задании %s не ответил строкой ROUTE: код %s, «%s» — маршрут не судим'
                 % (cls, os.environ['SLOT'], j, getattr(p, 'returncode', '—'), ((p.stdout + p.stderr) if p else '').strip()[-200:]))
        route, rwhy = m.group(1), m.group(2)
        if len(r) > 2 and route != 'external':
            route, rwhy = ask_mech(r[2])
    routes[j] = {'route': route, 'why': rwhy, 'class': cls, 'form': form}
    print('ROUTE\t%s\t%s\t%s\t%s\tформа: heavy-slot.sh %s -- %s' % (j, LABEL[route], 'выбрано' if j in want else 'не выбрано', rwhy, cls or '—',
          shlex.join(form) or '—'), file=sys.stderr)
    if j in want and route != 'external':
        bad.append('%s — %s: %s' % (j, LABEL[route], rwhy))
if bad:
    void('маршрута во внешний кластер нет у заданий, которые голова %s обязана пройти: %s — прогон был бы неполон либо LOCAL, ожидаемое не выводится'
         % (head[:12], '; '.join(bad)))
print(json.dumps({'head': head, 'repo': repo, 'source': source, 'base': base, 'draft': draft or None,
                  'full': full, 'reason': why, 'ledger': jobs, 'jobs': want, 'routes': routes}, ensure_ascii=False))
print('CENSUS\tожидаемое %s @%s: источник %s, %s (%s), заданий стенда %d из ведомости %d%s'
      % (repo, head[:12], source, 'полный' if full else 'целевой', why, len(want), len(jobs), '' if want else ' — выведенный ноль'), file=sys.stderr)
PY
fi
[ "${1:-}" = check ] || void "первым доводом — check либо expect"
REP="${2:-}"; [ -n "$REP" ] || void "нет пути отчёта"
shift 2
HEAD=""; OF=""; EXP=""; PRBASE=""; PRREPO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --head) HEAD="${2:-}"; shift 2 ;;
        --pr-base) PRBASE="${2:-}"; [ -n "$PRBASE" ] || void "--pr-base без ветки"; shift 2 ;;
        --pr-repo) PRREPO="${2:-}"; [[ "$PRREPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || void "--pr-repo «$PRREPO» не формы владелец/имя"; shift 2 ;;
        --of) OF="${2:-}"; [ -r "$OF" ] || void "прежний отчёт «$OF» не читается"; shift 2 ;;
        --expect) EXP="${2:-}"; [ -r "$EXP" ] || void "ожидаемое «$EXP» не читается — полноту не судить"; shift 2 ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || void "--head «$HEAD» не sha40"
[ -n "$OF" ] || [ -n "$EXP" ] || void "полный прогон судится лишь против --expect (stand-report.sh expect): отчёт свою полноту не объявляет"

REP="$REP" HEAD="$HEAD" OF="$OF" EXP="$EXP" PRBASE="$PRBASE" PRREPO="$PRREPO" GH="${STAND_REPORT_GH:-gh}" python3 - <<'PY'
import fnmatch, json, os, re, subprocess, sys

# Ведомость послаблений: причина not-run → задача, которая её снимает. Закрыта — истекло.
RELAX = {
    # ws#1110 закрыта, предмет живёт в kacho#3260 (решение диспетчера 2026-10-17)
    'NO-PR-IMAGES': ('PRO-Robotech/kacho', '3260',
                     'стенд проб не принимает образы ветки PR (kacho#3260) — newman и консоль ветки до CI не прогнать'),
}
reasons, census = [], []
rep, head, of, gh, exp = os.environ['REP'], os.environ['HEAD'], os.environ['OF'], os.environ['GH'], os.environ['EXP']


def reason(code, text):
    reasons.append((code, text))


def void(msg):
    print('VOID\t' + msg)
    print('VERDICT\tunread\tкод 2')
    sys.exit(2)


def load(path):
    try:
        d = json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError):
        return None
    ok = (isinstance(d, dict) and isinstance(d.get('suites'), list) and isinstance(d.get('head'), str)
          and isinstance(d.get('mode'), str) and all(isinstance(s, dict) for s in d['suites']))
    return d if ok else None


def num(x):
    return x if isinstance(x, int) and not isinstance(x, bool) else -1


expected, erepo = None, None
if exp:
    try:
        e = json.load(open(exp, encoding='utf-8'))
    except (OSError, ValueError):
        e = None
    if not (isinstance(e, dict) and isinstance(e.get('head'), str) and isinstance(e.get('jobs'), list)
            and all(isinstance(j, str) for j in e['jobs'])):
        void('ожидаемое %s не формы stand-report.sh expect (head, jobs) — полноту не судить' % exp)
    expected = e['jobs']
    census.append('ожидаемое %s: %s @%s, источник %s, заданий %d%s' % (exp, e.get('repo', '?'), e['head'][:12], e.get('source', '?'),
                  len(expected), '' if expected else ' — выведенный ноль'))
    if e['head'] != head:
        reason('STAND-EXPECT-STALE', 'ожидаемое выведено для %s, судится %s — выбор о другой голове' % (e['head'][:12], head[:12]))
    if not of and e.get('source') == 'affected' and e.get('draft') != 'false':
        reason('STAND-EXPECT-DRAFT', 'ожидаемое выведено при --draft %s — основание ready и вливания судится выбором ready (--draft false)' % e.get('draft'))
    STAND, erepo = json.loads(os.environ['STAND_JSON']), e.get('repo')
    if erepo not in STAND:
        reason('STAND-EXPECT-LEDGER', 'репозиторий ожидаемого «%s» вне ведомости STAND' % erepo)
    else:
        src, ledger = STAND[erepo]
        if e.get('source') != src or e.get('ledger') != ledger:
            reason('STAND-EXPECT-LEDGER', 'источник %s и ledger ожидаемого — не ведомости STAND для %s (%s, %d заданий)'
                   % (e.get('source'), erepo, src, len(ledger)))
        out = sorted(set(expected) - set(ledger))
        if out:
            reason('STAND-EXPECT-LEDGER', 'задания ожидаемого вне ведомости STAND: %s' % ', '.join(out))
        if ((src == 'full' or (src == 'affected' and e.get('draft') == 'false') or e.get('full') is True)
                and sorted(set(expected)) != sorted(ledger)):
            reason('STAND-EXPECT-LEDGER', 'выбор полный (source %s, draft %s, full %s), а заданий %d из ведомости %d — полный обязан нести все'
                   % (src, e.get('draft'), e.get('full'), len(set(expected) & set(ledger)), len(ledger)))
    # Маршрут (ws#1192): каждое задание ожидаемого — с внешним маршрутом; expect иного не выводит.
    rts = e.get('routes') if isinstance(e.get('routes'), dict) else {}
    for j in expected:
        r = rts.get(j)
        if not (isinstance(r, dict) and r.get('route') == 'external'):
            reason('STAND-EXPECT-ROUTE', '%s: маршрут в ожидаемом — %s, а не внешний кластер; stand-report.sh expect такое ожидаемое не выводит (VOID до запуска)'
                   % (j, r.get('route') if isinstance(r, dict) else 'нет'))
    prr = os.environ['PRREPO']
    if prr and erepo != prr:
        reason('STAND-EXPECT-REPO', 'ожидаемое выведено для %s, запрос — %s' % (erepo, prr))
    prb = os.environ['PRBASE']
    if prb and e.get('source') == 'affected' and re.sub(r'^(?:refs/remotes/)?origin/', '', str(e.get('base') or '')) != prb:
        reason('STAND-EXPECT-BASE', 'ожидаемое выведено от базы %s, база запроса %s' % (e.get('base'), prb))

SHA = re.compile(r'^[0-9a-f]{40}$')


def glob_re(g):  # ** — любые каталоги, * и ? — внутри одного
    return re.compile('^' + ''.join('.*' if t == '**' else '[^/]*' if t == '*' else '[^/]' if t == '?' else re.escape(t)
                                    for t in re.findall(r'\*\*|\*|\?|[^*?]+', g)) + '$')


def known(s, pats):  # образец ведомости — имя набора либо его job
    return any(fnmatch.fnmatchcase(str(s.get('name') or ''), w) or fnmatch.fnmatchcase(str(s.get('job') or ''), w) for w in pats)


def carry(d, suites):
    carried = [s for s in suites if s.get('carried_from') is not None]
    img = d.get('images_rev')
    if img is not None and not (isinstance(img, str) and SHA.match(img)):
        reason('STAND-CARRY-BASIS', 'images_rev «%s» не sha40' % img)
        img = None
    if not carried and img in (None, head):
        return
    crepo = os.environ['PRREPO'] or erepo
    basis = d.get('carry_basis') if isinstance(d.get('carry_basis'), dict) else {}
    done = {}

    def base(r, who):  # множество изменённых путей r..head, если перенос с r обоснован; иначе None
        if r in done:
            return done[r]
        done[r] = None
        b = basis.get(r)
        if not (isinstance(b, dict) and isinstance(b.get('changed'), list) and isinstance(b.get('inputs'), str)):
            reason('STAND-CARRY-BASIS', '%s: обоснования carry_basis[%s] нет либо оно без changed и inputs' % (who, r[:12]))
            return None
        if not crepo:
            void('перенос с %s: репозиторий не установлен (--pr-repo либо --expect) — разность у площадки не спросить' % r[:12])
        p = subprocess.run([gh, 'api', 'repos/%s/compare/%s...%s' % (crepo, r, head)], capture_output=True, text=True)
        if p.returncode != 0:
            void('площадка не ответила о разности %s...%s: %s' % (r[:12], head[:12], p.stderr.strip()[:200]))
        try:
            c = json.loads(p.stdout)
            st, behind, plat = c['status'], c['behind_by'], {f['filename'] for f in c['files']}
            gone = {f['previous_filename'] for f in c['files'] if f.get('previous_filename')}
        except (ValueError, KeyError, TypeError):
            void('ответ площадки о разности %s...%s не разбирается' % (r[:12], head[:12]))
        if behind != 0 or st not in ('ahead', 'identical'):
            reason('STAND-CARRY-BASIS', '%s: %s не предок головы (status %s, behind %s) — разность не одна' % (who, r[:12], st, behind))
            return None
        if len(c['files']) >= 300:
            reason('STAND-CARRY-BASIS', '%s: перечень площадки о %s...head обрезан (%d) — разность не судить' % (who, r[:12], len(c['files'])))
            return None
        rec = {str(x) for x in b['changed']}
        if rec != plat:
            reason('STAND-CARRY-BASIS', '%s: путей отчёта %d, площадки %d — лишние %s, недостающие %s'
                   % (who, len(rec), len(plat), sorted(rec - plat)[:5], sorted(plat - rec)[:5]))
            return None
        rows = dict((pth, mk) for mk, pth in re.findall(r'^\s*(ВХОД|не вход)\s+(\S+) — ', b['inputs'], re.M))
        tot = re.search(r'изменённых путей (\d+), из них входов сборки (\d+)', b['inputs'])
        if not (type(b.get('inputs_rc')) is int and b.get('inputs_rc') == 0) or not tot or tot.group(2) != '0' or 'ВХОД' in rows.values():
            reason('STAND-CARRY-INPUTS', '%s: входы сборки %s..head менялись (код inputs %s, %s) — перенос запрещён'
                   % (who, r[:12], b.get('inputs_rc'), tot.group(0) if tot else 'итога inputs нет'))
            return None
        if set(rows) != plat or int(tot.group(1)) != len(plat):
            reason('STAND-CARRY-BASIS', '%s: вывод inputs не о разности площадки — строк %d, путей площадки %d, без вердикта %s'
                   % (who, len(rows), len(plat), sorted(plat - set(rows))[:5]))
            return None
        done[r] = plat | gone
        return done[r]

    if img not in (None, head):
        base(img, 'образы стенда %s' % img[:12])
    area = json.loads(os.environ['STAND_AREA_JSON']).get(crepo)
    moved = 0
    for s in carried:
        name, r = str(s.get('name') or '?'), s.get('carried_from')
        if not (isinstance(r, str) and SHA.match(r)) or r == head:
            reason('STAND-CARRY-BASIS', '%s: carried_from «%s» не sha40 другой ревизии' % (name, r))
            continue
        changed = base(r, name)
        if changed is None:
            continue
        if not area:
            reason('STAND-CARRY-AREA', '%s: у %s ведомости областей нет — по умолчанию закрыто' % (name, crepo))
            continue
        if known(s, area['whole_tree']):
            reason('STAND-CARRY-AREA', '%s (%s): набор читает всё дерево — не переносится' % (name, s.get('job')))
            continue
        if not any(fnmatch.fnmatchcase(name, w) for w in area['jobs'].get(str(s.get('job') or ''), [])):
            reason('STAND-CARRY-AREA', '%s (%s): имени и задания нет в реестре jobs ведомости — по умолчанию закрыто' % (name, s.get('job')))
            continue
        hit, unknown = [], []
        for pth in sorted(changed):
            ents = [en for en in area['paths'] if any(glob_re(g).match(pth) for g in en[0])]
            if not ents:
                unknown.append(pth)
            elif any(known(s, en[1]) for en in ents):
                hit.append(pth)
        if hit:
            reason('STAND-CARRY-AREA', '%s: набор читает изменённое (%s) — гнать заново, не переносить' % (name, ', '.join(hit[:5])))
        if unknown:
            reason('STAND-CARRY-AREA', '%s: пути вне ведомости областей (%s) — по умолчанию закрыто' % (name, ', '.join(unknown[:5])))
        if hit or unknown:
            continue
        sp = str(basis[r].get('report') or '')
        src = load(os.path.join(os.path.dirname(os.path.abspath(rep)), sp)) if sp else None
        twin = [x for x in (src or {}).get('suites', []) if x.get('name') == s.get('name') and x.get('job') == s.get('job')]
        ex = num(s.get('executed'))
        if (src is None or src['head'] != r or len(twin) != 1 or twin[0].get('outcome') != 'green' or s.get('outcome') != 'green'
                or ex < 1 or ex != num(s.get('total')) or ex != num(twin[0].get('executed')) or ex != num(twin[0].get('total'))
                or num(src.get('residue')) != 0
                or not (str(src.get('context') or '').endswith('-client') or re.match(r'local\b.*\bproof=\S', str(src.get('proof') or '')))):
            reason('STAND-CARRY-SOURCE', '%s: в отчёте «%s» о %s нет того же набора зелёным %s из %s на внешнем стенде с остатком 0'
                   % (name, sp, r[:12], s.get('executed'), s.get('total')))
            continue
        xi = src.get('images_rev') or r
        if xi != head and base(xi, '%s: образы источника %s' % (name, str(xi)[:12])) is None:
            continue
        moved += 1
    census.append('перенос: наборов %d из %d, перенесено обоснованно %d; образы стенда %s; ГРАНИЦА — разбиение путей на входы '
                  'прочитано из вывода inputs и сверено с разностью площадки, не пересчитано' % (len(carried), len(suites), moved, (img or head)[:12]))


d = load(rep)
if d is None:
    reason('STAND-REPORT-MISSING', 'отчёта %s нет либо он не объект с полями head, mode, suites — прогона на кластере нет' % rep)
else:
    suites = d['suites']
    census.append('отчёт %s: голова %s, mode %s, контекст %s, ns %s; наборов %d из planned %s'
                  % (rep, d['head'][:12], d['mode'], d.get('context', '?'), d.get('ns', '?'), len(suites), d.get('planned')))
    if d['head'] != head:
        reason('STAND-REPORT-STALE', 'отчёт о голове %s, судится %s — прогон о другой голове' % (d['head'][:12], head[:12]))
    want = 'only-red' if of else 'full'
    if d['mode'] != want:
        reason('STAND-REPORT-NOT-FULL' if not of else 'STAND-REPORT-TRUNCATED',
               'mode %s, нужен %s%s' % (d['mode'], want, '' if of else ' — only-red основанием ready и CI не служит'))
    planned = num(d.get('planned'))
    if planned < 0 or planned != len(suites):
        reason('STAND-REPORT-TRUNCATED', 'исполнено наборов %d из planned %s — перепись обрезана' % (len(suites), d.get('planned')))
    if expected is not None:
        have = {str(s.get('job') or '') for s in suites}
        for j in expected:
            if j not in have:
                reason('STAND-REPORT-UNCOVERED', 'задание CI %s ожидаемо по выбору головы, набора с job %s в отчёте нет' % (j, j))
        extra = sorted(have - set(expected) - {''})
        if extra:
            census.append('наборы сверх ожидаемого: %s' % ', '.join(extra))
    ctx, proof = str(d.get('context') or ''), str(d.get('proof') or '').strip()
    if not ctx.endswith('-client') and not re.match(r'local\b.*\bproof=\S', proof):
        reason('STAND-REPORT-LOCAL', 'контекст «%s» не внешний (-client), proof «%s» не формы журнала слота «local … proof=»' % (ctx, proof[:80]))
    if num(d.get('residue')) != 0:
        reason('STAND-REPORT-RESIDUE', 'остаток переписи после прогона %s, нужен 0' % d.get('residue'))
    green = notrun = 0
    alive = {}
    for s in suites:
        name, out = str(s.get('name') or '?'), s.get('outcome')
        ex, tot = num(s.get('executed')), num(s.get('total'))
        if out == 'green':
            if tot < 1 or ex != tot:
                reason('STAND-REPORT-TRUNCATED', '%s: зелёный при исполнено %s из %s' % (name, s.get('executed'), s.get('total')))
            else:
                green += 1
        elif out == 'red':
            q = str(s.get('quote') or '').strip()
            if not q:
                reason('STAND-REPORT-NO-QUOTE', '%s: красный без дословной цитаты отказа' % name)
            reason('STAND-REPORT-RED', '%s: «%s» · корень: %s' % (name, q[:300], str(s.get('root') or 'не назван')))
        elif out == 'not-run':
            why = str(s.get('reason') or '')
            if why not in RELAX:
                reason('STAND-REPORT-NOT-RUN', '%s: не выполнилось, причина «%s» вне ведомости послаблений' % (name, why))
                continue
            if why not in alive:
                r, n, _ = RELAX[why]
                p = subprocess.run([gh, 'api', 'repos/%s/issues/%s' % (r, n)], capture_output=True, text=True)
                if p.returncode != 0:
                    void('площадка не ответила о задаче послабления %s#%s: %s' % (r, n, p.stderr.strip()[:200]))
                try:
                    alive[why] = json.loads(p.stdout).get('state') == 'open'
                except (ValueError, AttributeError):
                    void('ответ о задаче послабления %s#%s не разбирается' % (r, n))
            if alive[why]:
                notrun += 1
                census.append('не выполнилось (не зелёное): %s — %s, послабление до закрытия %s#%s' % ((name, RELAX[why][2]) + RELAX[why][:2]))
            else:
                reason('STAND-RELAX-EXPIRED', '%s: послабление %s истекло — %s#%s закрыта; снять строку ведомости и прогнать набор' % ((name, why) + RELAX[why][:2]))
        else:
            reason('STAND-REPORT-MISSING', '%s: исход «%s» вне словаря green | red | not-run' % (name, out))
    if (suites or expected) and green == 0:
        reason('STAND-REPORT-NOTHING-RUN', 'зелёным исполнено 0 наборов из %d' % len(suites))
    census.append('исход: зелёных %d · красных %d · не выполнилось %d' % (green, sum(1 for s in suites if s.get('outcome') == 'red'), notrun))
    carry(d, suites)
    if of:
        prev = load(of)
        if prev is None:
            void('прежний отчёт %s не разбирается' % of)
        mine = {str(s.get('name')) for s in suites}
        for s in prev['suites']:
            if s.get('outcome') == 'red' and str(s.get('name')) not in mine:
                reason('STAND-REPORT-RED-DROPPED', '%s: красный в %s, в прогоне «только красное» его нет' % (s.get('name'), of))

for c in census:
    print('CENSUS\t' + c)
for code, text in reasons:
    print('REASON\t%s\t%s' % (code, text))
print('VERDICT\t%s\tкод %d; причин %d' % ('green' if not reasons else 'stop', 1 if reasons else 0, len(reasons)))
sys.exit(1 if reasons else 0)
PY
