#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# wave-template-inject.sh — доказательство свойств шаблона волны
# `.claude/workflows/wave.js` ИСПОЛНЕНИЕМ, а не чтением: тело шаблона
# исполняется node с подменёнными agent/phase/log, и проба сверяет, КАКИХ
# агентов, с какой моделью и в каком порядке шаблон позвал.
#
# ВХОД — НАСТОЯЩИЙ там, где он есть: вывод плана, который шаблон получает от
# механика, проба берёт у настоящего `scripts/plan-precheck.sh` (а тот — у
# `lane-tier.sh`) по путям полос R0 (документ), R1 (код), R2 (миграция). Шаги
# уровня тем самым приходят из их единственного дома, и шаблон обязан их
# исполнить, а не выписать свои.
#
# СВОЙСТВА (сценарий на каждое; близнец — соседний сценарий той же формы):
#   meta — чистый литерал; в теле нет Date.now/Math.random/new Date();
#   R0 — ни одного рецензента; механика — модель НЕ задана, усилие — лишь у
#   шагов, чей ответ шаблон не читает (счётчик ошибок);
#   ОБЛАСТЬ (ws#1016): модель, усилие и место отчётов судятся на ОБЪЕДИНЕНИИ
#   вызовов всех сценариев пробы, а покрытие — по классам шагов, выведенным из
#   тела шаблона (`label: '…'`, литералы 'mech:…'): класс, не достигнутый ни
#   одним сценарием, — находка. Модель не задана ни у одного вызова — haiku нет
#   нигде; отчёты и журналы полос — под <D>/reports/, в каталоге полосы лишь
#   копии copy и stack; lane-precheck — с LANE_PRECHECK_WS=<корень>; сборка
#   kacho — npm ci консоли как ui.yml;
#   R1 — ровно один wave-reviewer на сборку, ролей полосы нет;
#   R2 — приёмка, перепись поверхности, роль уровня, рецензент волны,
#        landing-reviewer — по разу;
#   CI «идёт» дважды — ждать, ошибкой не считать;
#   красный CI (ws#1063, ws#1110) — итог несёт порядок «перепись — потом массово» (CI
#   по завершении всех заданий, цитата до класса, среда — перезапуск, одна сборка, только
#   красное на кластере, полный прогон, один CI, два красных — стоп);
#   внешний стенд до CI (ws#1110): шаг mech:stand ci-watcher после рецензента волны и до
#   первого чтения CI, суд stand-report.sh этой головы; красный — ни CI, ни ready, ни
#   вливания; не выполнилось — без круга; идёт — чтение с проверенной паузой; посадка —
#   landing-precheck --stand-report;
#   влитая волна в ветку эпика — пробное схождение и одно чтение CI MR эпика без
#   ожидания; близнецы — волна прямо в main и невлитая волна — без них;
#   предпроверка полосы красная, голова та же — повтора нет, строка счётчика
#   ошибок (executor-mechanics); голова новая — повтор и зелёное;
#   «уже сделано» исполнителя — не провал;
#   предусловия раздачи (ws#1272) — один механик до предполёта: база, задачи полосы, строки
#   premise, у полосы с приёмкой — текст задания автору приёмки (ws#1271); не 0 — полоса и
#   зависимые не раздаются и в предполёт не идут, нет ответа — не раздаётся ни одна;
#   шаг уровня, шаблону неизвестный, — остановка на плане, а не пропуск;
#   corelib разный — полоса перепина первой и повтор плана;
#   вливание — демоном autoland (ws#1147, ws#1152): тело PR — вывод pr-body.sh и на
#   сборке, и перед стартом; start, затем ОДИН шаг status; 3 — state running с путём
#   .state, попытка (args.rerun) — в задании status; красный и прочие исходы —
#   итог с первой строкой .state дословно, каскада нет; после перевода в ready
#   шаблон CI не читает; правки тела агентом нет;
#   вердикт роли не на сведённой голове полосы — остановка, sha не подменяется;
#   одна роль вернула, другая приняла прежнюю голову — повтор только
#   вернувшей (§8а п.8), sha принявшей не переписан, полоса стоит до сборки:
#   новую голову принявшая не видела (ws#933, опыт check-verifier r3); близнец —
#   одна роль уровня вернула и приняла дельту — полоса идёт дальше.
#   агент не ждёт (ws#1001): каждое задание несёт «НЕ ЖДИ» и срок шага, у
#   исполнителя и ревью — свой; CI — CI_READS коротких чтений шаблона, пауза между
#   ними — одна команда ≤ 300 с, у первого чтения паузы нет, агент не ждёт сам;
#   номер PR сборки — целое ≥ 1 и в схеме, и в теле: нет поля, 0, строка, адрес —
#   остановка на сборке с причиной, «PR #undefined» не уходит ни в одно задание
#   (ws#935); близнец — pr 7 доходит до CI и посадки;
#   вердикт роли — только поле verdict словаря accept | return | void: «✅» в
#   report без поля — не принят; void — не принят;
#   CI читается ТОЛЬКО scripts/ci-read.sh (ws#1006): рецепт «ЗАПУСК» с ci-read.sh,
#   состояние из кода (0 green · 1 red · 2 unread · 3 running · 4 stale), иной код —
#   unread; перед вливанием — чтение на голове посадки, вливание только при коде 0
#   на ней; код 4 — стадия «база устарела», вливания нет;
#   CI «идёт» и после ожидания, демон вливания «идёт» (status 3) — state
#   running, а не провал; близнецы — красный CI и CI-PENDING с другой причиной —
#   state failed;
#   полоса с deps (ws#938) — сводка голов deps зовётся после того, как dep
#   прошёл, и получает его ИТОГОВУЮ голову; исполнитель заводит ветку от головы
#   сводки, предпроверка судит её как базу; независимая полоса стартует сразу,
#   не дожидаясь чужого слоя; dep не прошёл — зависимая не начата, соседи идут;
#   сводка конфликтует либо не содержит головы dep — остановка с причиной,
#   исполнитель не зван, полоса — остаток, а соседи садятся (ws#999: вердикт
#   — о своей полосе); сводки сняты шагом вливания; близнец —
#   полоса без deps сводки не зовёт, база — база волны; флаг crossRepo задания
#   доходит до плана, без флага его в плане нет;
#   ответ сводки не годен по одному факту — нет ответа, статус failed, голова не
#   sha40 — остановка со своей причиной, без исключения; близнец — already-done;
#   повторы зависимой полосы (доводка и вторая предпроверка, доводка и
#   предпроверка после возврата роли) — от той же головы сводки; ревью роли
#   зависимой — дельта сводка..голова, близнец без deps — без дельты; в сводку —
#   только deps полосы, при любом порядке окончания соседей (A позже C и C позже
#   A); база сводки — база полосы; имя сводки не по форме либо совпавшее у двух
#   полос — остановка на плане, близнец — два разных имени (ws#939, опыт
#   check-verifier: 11 мутантов выжили на aeb93941);
#   полоса с deps и веткой-номером (kaname: хук принимает лишь `^[0-9]+$`) —
#   сводка в ветке самой полосы, ни одно задание не заводит и не снимает ветку
#   не-номер, слияния по форме `#<N> merge #<M>: …`, голова dep сверяется
#   is-ancestor до исполнителя, имя ветки — из задания, а не из ответа механика,
#   исполнителю — «продолжай свою ветку от головы сводки» без «влей сводку»;
#   близнец kacho — прежняя `<N>-stack-<ключ>`, снимаемая вливанием, исполнителю —
#   «влей сводку» без «уже в твоей ветке» (ws#946).
#   пауза CI (ws#1010): её делает ТОТ ЖЕ агент, что читает, одной командой
#   `sleep N; echo SLEPT …; ci-read.sh`; схема чтения требует slept числом;
#   чтение с паузой при slept < N−10 (нет поля, строка, мало) отвергнуто — повтор и
#   строка счётчика, вливания по нему нет; близнецы — slept = N−10 и первое чтение
#   без паузы; мутант «пауза отдельным агентом без проверки slept» краснеет;
#   каталог волны (ws#1010) — <корень>/tmp/wave-<N>: ws-копия под /ws/tmp/… даёт
#   /ws/tmp/wave-9, args.root его перекрывает, рабочие копии продукта — корня;
#   GOMOD-ABOVE предпроверки — механика исполнителя;
#   пустые ходы (ws#1004): вывод плана со строками CENSUS перед JSON разбирается
#   (объект — из последней строки), задание плана просит только её; JSON не в
#   последней строке и мусор — остановка «не разобран»; правило о чужих файлах — в
#   преамбуле каждого задания и в задании исполнителя вместе с перечнями путей
#   соседей (своего среди них нет; полоса одна — «соседей нет»); hookLog не путь —
#   одна доводка, снова не путь — полоса стоит без предпроверки вслепую, соседи
#   садятся; report — содержательный итог.
#   волна одним проходом (ws#1053): предполёт — один scout до первого исполнителя,
#   задание называет все классы зависимых и критерии по policy.yaml; полоса несёт
#   СВОЮ карту; незакрытый пункт — одна доводка, затем полоса стоит, сосед садится
#   (близнец — доводка закрыла); предполёт без ответа или без карты полосы — раздачи
#   нет; пробная сборка — сразу после предпроверки полосы, красная — полоса в
#   остаток (близнец — код 2 не красное); смена контракта — имитация клиента ДО
#   кода; метрики — последним шагом на любом исходе; каскад щадит держателя ведомости.
#   перепись гейтов (ws#1071): один шаг до старта демона вливания, все шесть гейтов,
#   ничего не чинит, итог несёт таблицу; текстовый шаг без «### ВОЗВРАТ» — один повтор
#   дочитыванием, снова без — полоса стоит, фраза ожидания в задания не уходит.
#   уроки ws#1078: диапазон коммитов рецензента волны исполняется на настоящем репозитории
#   (с коммитом — 0, пустой — 2); стволы — по каждому из kacho, kaname, corelib; задание
#   файлом — во всех шагах с заданием; итог режется и внутри массивов.
#   Чего НЕ держит (вне ws#946): хвостовой дефис имени ветки-номера; форму
#   слияния для веток зависимостей вида `<M>-<суть>` в репозиториях, чей хук её
#   не принимает; не-номерные ветки kaname, уже лежащие на origin.
#   Узнаватель указаний демона (E1–E8) НЕ ВИДИТ безличных и описательных форм — указание без
#   глагола класса в повелительной или неопределённой форме: «Пусть ci-read.sh сперва вернёт
#   код 0», «Перед стартом ожидается код 0 от ci-read.sh» (приёмка check-verifier ws#1152).
#   Обратная сторона правила отрицания — ложное красное: наречие повтора при отрицаемом глаголе
#   («повторно его не запускай») читается как указание повтора; законная форма — «не запускай
#   второй раз»; запрет через слова («закрыть задачи до merged нельзя») — тоже указание,
#   законная форма — вплотную («нельзя закрыть задачи до merged»).
#
# ИНЪЕКЦИИ — без довода проба после контроля прогоняет МУТАНТОВ шаблона (по
# одной правке, у каждой — своё свойство) и требует, чтобы каждый покраснел.
#
# usage: wave-template-inject.sh [<шаблон.js>]   (с доводом — только контроль)
#        wave-template-inject.sh --landing-command <WS> <файл> [<шаблон.js>]
#   — исполняет шаблон сценарием R0 с ws=<WS> и пишет в <файл> команду landing-precheck
#   (рецепт «ЗАПУСК») из задания переписи гейтов, как она есть (вливает демон, ws#1152). Её исполняет
#   landing-precheck-inject.sh, раздел «запуск»: свойства самой команды
#   (вырезает рецепт из origin/main, код наружу как есть) держит он.
# Коды: 0 — все утверждения сошлись (и все мутанты красные); 1 — нет;
#       2 — нет node, шаблона или вывода плана: вердикта нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAND_WS="" LAND_OUT=""
if [ "${1:-}" = --landing-command ]; then
    [ $# -ge 3 ] || { echo "wave-template-inject: VOID — --landing-command <WS> <файл> [<шаблон.js>]" >&2; exit 2; }
    LAND_WS="$2" LAND_OUT="$3"; shift 3
fi
TPL="${1:-$HERE/../.claude/workflows/wave.js}"
command -v node > /dev/null 2>&1 || { echo "wave-template-inject: VOID — нет node" >&2; exit 2; }
command -v jq > /dev/null 2>&1 || { echo "wave-template-inject: VOID — нет jq" >&2; exit 2; }
[ -r "$TPL" ] || { echo "wave-template-inject: VOID — шаблона нет: $TPL" >&2; exit 2; }
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
# Репозиторий диапазона L11 (ws#1078): main = «L11-A», ветка w = «L11-B»; подпись — песочницы.
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || { echo "wave-template-inject: VOID — корневой подписи нет" >&2; exit 2; }
if ! { sandbox_git init -q -b main "$W/l11" && sandbox_git -C "$W/l11" commit -q --allow-empty -m L11-A \
    && sandbox_git -C "$W/l11" switch -qc w && sandbox_git -C "$W/l11" commit -q --allow-empty -m L11-B; }; then
    echo "wave-template-inject: VOID — репозиторий диапазона L11 не заведён" >&2; exit 2
fi

# Вывод плана — настоящим plan-precheck.sh.
planout() { # planout <файл> <jq-массив полос>
    jq -n "{wave: \"9\", lanes: $2}" > "$W/p.json"
    bash "$HERE/plan-precheck.sh" "$W/p.json" --json 2> /dev/null > "$1"
    jq -e '.code == 0' "$1" > /dev/null || { echo "wave-template-inject: VOID — plan-precheck не дал плана: $(cat "$1")" >&2; exit 2; }
}
planout "$W/r0.json" '[{key:"A",repo:"kacho-workspace",paths:["docs/a.md"]},{key:"B",repo:"kacho-workspace",paths:["docs/b.md"]}]'
planout "$W/r1.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"B",repo:"kacho-workspace",paths:["services/x/b.go"],deps:["A"]}]'
planout "$W/r1c.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"B",repo:"kacho-workspace",paths:["services/x/b.go"],deps:["A"]},{key:"C",repo:"kacho-workspace",paths:["services/x/c.go"]}]'
planout "$W/r1d.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"B",repo:"kacho-workspace",paths:["services/x/b.go"],deps:["A"]},{key:"C",repo:"kacho-workspace",paths:["services/x/c.go"]},{key:"D",repo:"kacho-workspace",paths:["services/x/d.go"],deps:["C"]}]'
jq -e '[.layers[] | join(",")] | join("|") == "A,C|B,D"' "$W/r1d.json" > /dev/null || { echo "wave-template-inject: VOID — план A,C|B,D не получен: предпосылка сценария чужого слоя" >&2; exit 2; }
jq -e '[.layers[] | join(",")] | join("|") == "A,C|B"' "$W/r1c.json" > /dev/null || { echo "wave-template-inject: VOID — план A,C|B не получен: предпосылка сценария независимой полосы" >&2; exit 2; }
# Полоса образов без deps рядом с документной (ws#1191).
planout "$W/r0s.json" '[{key:"A",repo:"kacho-workspace",paths:["docs/a.md"]},{key:"S",repo:"kacho-workspace",paths:["docs/s.md"]}]'
planout "$W/r2.json" '[{key:"M",repo:"kacho-workspace",paths:["services/x/migrations/0001.sql"]}]'
# Полоса не migration-writer, но с путём миграции, рядом с документной (ws#1242 п.3).
planout "$W/r0g.json" '[{key:"A",repo:"kacho-workspace",paths:["docs/a.md"]},{key:"G",repo:"kacho-workspace",paths:["services/iam/internal/migrations/0042_roles.sql"]}]'
planout "$W/r2two.json" '[{key:"M",repo:"kacho-workspace",paths:["services/x/migrations/0001.sql","services/x/internal/authz/a.go"]}]'
jq -e '.lanes[0].roles | length >= 2' "$W/r2two.json" > /dev/null || { echo "wave-template-inject: VOID — план R2 без двух ролей: предпосылка сценария возврата одной роли" >&2; exit 2; }
# Зависимая полоса уровня R2 (роли есть): дельта ревью и повтор после ролей.
planout "$W/r2dep.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"M",repo:"kacho-workspace",paths:["services/x/migrations/0001.sql"],deps:["A"]}]'
jq -e '(.lanes[] | select(.key == "M") | (.steps | index("roles")) != null and (.roles | length) >= 1) and ([.layers[] | join(",")] | join("|") == "A|M")' "$W/r2dep.json" > /dev/null || { echo "wave-template-inject: VOID — план A|M с ролями у M не получен: предпосылка сценария ревью зависимой" >&2; exit 2; }
# Две зависимые полосы: ключи, сводящиеся к одному имени сводки, и близнец.
planout "$W/r1coll.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"B-1",repo:"kacho-workspace",paths:["services/x/b.go"],deps:["A"]},{key:"B_1",repo:"kacho-workspace",paths:["services/x/e.go"],deps:["A"]}]'
planout "$W/r1two.json" '[{key:"A",repo:"kacho-workspace",paths:["services/x/a.go"]},{key:"B-1",repo:"kacho-workspace",paths:["services/x/b.go"],deps:["A"]},{key:"B-2",repo:"kacho-workspace",paths:["services/x/e.go"],deps:["A"]}]'
# Полоса с deps в репозитории, чей хук принимает ветку только номером (kaname),
# и близнец той же формы в kacho (ws#946).
planout "$W/kn.json" '[{key:"A",repo:"kaname",paths:["internal/x/a.go"]},{key:"B",repo:"kaname",paths:["internal/x/b.go"],deps:["A"]}]'
planout "$W/kc.json" '[{key:"A",repo:"kacho",paths:["internal/x/a.go"]},{key:"B",repo:"kacho",paths:["internal/x/b.go"],deps:["A"]}]'
jq -e '[.layers[] | join(",")] | join("|") == "A|B"' "$W/kn.json" > /dev/null || { echo "wave-template-inject: VOID — план kaname A|B не получен: предпосылка сценария ws#946" >&2; exit 2; }

cat > "$W/probe.mjs" <<'JS'
import fs from 'node:fs'
import vm from 'node:vm'
import { spawnSync } from 'node:child_process'
const [tplPath, dir, landWs, landOut] = process.argv.slice(2)
const src = fs.readFileSync(tplPath, 'utf8')
const P = n => JSON.parse(fs.readFileSync(dir + '/' + n, 'utf8'))
let pass = 0, fail = 0
const ok = (c, name, extra) => { if (c) { pass++; console.log('  [OK]   ' + name) } else { fail++; console.error('  [FAIL] ' + name + (extra ? ' — ' + extra : '')) } }

// meta — чистый литерал: вычисляется в пустом контексте без единого имени
const m = src.match(/^export const meta = (\{[\s\S]*?\n\})\n/)
let meta = null
try { meta = m && !/\$\{|`/.test(m[1]) ? vm.runInNewContext('(' + m[1] + ')', Object.create(null)) : null } catch (e) { meta = null }
// Литерал — по форме: без строк остаются лишь ключи, true/false/null, числа и
// скобки; вызов, имя, спред, выражение — остаток, и это находка (вычисление в
// пустом контексте ловит только свободные имена).
const rest = m ? m[1].replace(/'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"/g, '').replace(/\b[A-Za-z_]\w*\s*:/g, '').replace(/\b(?:true|false|null)\b|-?\d+(?:\.\d+)?/g, '') : 'x'
ok(meta && meta.name === 'wave' && typeof meta.description === 'string' && /^[\s{}\[\],]*$/.test(rest), 'meta — чистый литерал с name «wave» и description', 'остаток: ' + rest.replace(/\s+/g, ' ').slice(0, 80))
const body = m ? src.slice(m[0].length) : ''
ok(!/Date\.now\(|Math\.random\(|new Date\(\s*\)/.test(body), 'в теле нет Date.now / Math.random / new Date()')

const H = (k, n) => (k + n).padEnd(40, 'a').replace(/[^0-9a-f]/g, 'b').slice(0, 40)
const HW = 'f'.repeat(40)
// Объединение вызовов ВСЕХ сценариев пробы: утверждения о модели, усилии и месте
// отчётов судят его, а не один сценарий по умолчанию (ws#1016, check-verifier ⛔).
const ALL = []
async function run(sc) {
  const calls = []
  const heads = {}, cnt = {}
  const take = (key, def) => { const q = (sc[key] || []); const i = (cnt[key] = (cnt[key] || 0) + 1) - 1; return i < q.length ? q[i] : def() }
  const agent = async (prompt, opts = {}) => {
    const label = opts.label || ''
    calls.push({ label, agentType: opts.agentType, model: opts.model, effort: opts.effort, schema: opts.schema, prompt })
    ALL.push({ label, agentType: opts.agentType, model: opts.model, effort: opts.effort, prompt, has: { model: 'model' in opts, effort: 'effort' in opts } })
    const lane = label.split(':').pop()
    // Предполёт (ws#1053): карта по каждому ключу из задания; сценарий перекрывает (null — нет ответа).
    if (label === 'preflight') { const keys = ((prompt.match(/КЛЮЧИ ПОЛОС: ([^.\n]*)/) || [])[1] || '').split(',').filter(Boolean); const r = take('pre', () => ({ lanes: keys.map(k => ({ key: k, impact: (sc.map || {})[k] || [], criteria: ['критерий ' + k] })), estimate: '6 ч, красных 0', report: 'r' })); return r }
    if (label.startsWith('mech:plan:')) { const o = take('plan', () => P('r0.json')); return { code: o.code, out: (sc.planOut !== undefined ? sc.planOut : (sc.planPrefix || '') + JSON.stringify(o)), reasons: (o.reasons || []).map(r => r.code), head: '' } }
    if (label.startsWith('impl:')) { const r = take('impl:' + lane, () => ({ status: 'done', head: H(lane, cnt['impl:' + lane]) })); heads[lane] = r.head; return { branch: 'b-' + lane, copy: '/ws/tmp/c-' + lane, hookLog: '/ws/tmp/push.log', issues: ['o/r#1'], report: 'r', ...r } }
    if (label.startsWith('mech:stack:')) { const r = take('stack:' + lane, () => ({ status: 'done', head: H('S' + lane, 0) })); if (r === null) return null; heads['stack:' + lane] = r.head; return { branch: (prompt.match(/заведи ветку (\S+)/) || [])[1] || '9-stack-' + lane.toLowerCase(), contains: Object.keys(heads).filter(k => !k.startsWith('stack:')).map(k => heads[k]), conflicts: [], report: 'r', ...r } }
    // Предусловия раздачи (ws#1272): команда — строкой «<n>) [<ключ> <вид>] `…`»; код — из
    // sc.dispatchCode по «<ключ> <вид>», затем по ключу, иначе 0; sc.dispatchNull — нет ответа.
    if (label === 'mech:dispatch-premise') { if (sc.dispatchNull) return null; const dc = sc.dispatchCode || {}; return { items: [...prompt.matchAll(/\n(\d+)\) \[(\S+) (\S+)\] `/g)].map(x => { const c = dc[x[2] + ' ' + x[3]] ?? dc[x[2]] ?? 0; return { n: +x[1], code: c, out: c === 1 ? 'REASON PREMISE-FALSE task o/r#5: задача closed, задание ждёт open' : c === 2 ? 'VOID GH-UNREADABLE task o/r#5' : '' } }) } }
    if (label.startsWith('mech:premise:')) return { out: '', head: '', reasons: [], ...take('premise:' + lane, () => ({ code: 0 })) }
    if (label.startsWith('mech:precheck:')) return { out: '', head: heads[lane], reasons: [], ...take('pre:' + lane, () => ({ code: 0 })) }
    if (label.startsWith('review-wave')) return { verdict: 'accept', sha: HW, blocking: [], report: 'r', ...take('wave', () => ({})) }
    if (label.startsWith('review-landing')) return { verdict: 'accept', sha: HW, blocking: [], report: 'r' }
    if (sc.ret && label === 'review-' + sc.ret + ':' + lane) return { verdict: 'return', sha: heads[lane], blocking: ['x'], report: 'r' }
    if (label.startsWith('review-') || label.startsWith('acceptance-review-')) return { verdict: 'accept', sha: sc.staleRole ? H('old', 0) : heads[lane] || '', blocking: [], report: 'r' }
    if (label.startsWith('mech:assemble:')) return { status: 'done', head: HW, copy: '/ws/tmp/w', pr: 7, conflicts: [], report: 'r', ...take('asm', () => ({})) }
    // Честный агент: slept — секунды sleep ЕГО команды (нет паузы — 0); сценарий перекрывает.
    // Стенд (ws#1110): та же честность паузы, что у CI; сценарий перекрывает код.
    if (label.startsWith('mech:stand:')) return { out: '', reasons: [], head: HW, slept: +((prompt.split('\n\n').slice(1).join(' ').match(/`[^`]*\bsleep (\d+)/) || [])[1] || 0), ...take('stand', () => ({ code: 0 })) }
    if (label.startsWith('mech:ci:')) return { out: '', reasons: [], head: HW, slept: +((prompt.split('\n\n').slice(1).join(' ').match(/`[^`]*\bsleep (\d+)/) || [])[1] || 0), ...take('ci', () => ({ code: 0 })) }
    // Демон вливания (ws#1147, ws#1152): start печатает pid, журнал, state; status — первая строка
    // .state; сценарий перекрывает исход (al) и старт (alstart).
    if (label === 'mech:autoland:status') return { code: 0, out: 'merged ' + 'e'.repeat(40) + '; снятие: ветка снята', reasons: [], head: 'e'.repeat(40), ...take('al', () => ({})) }
    if (label === 'mech:autoland') return { code: 0, out: 'pid\t1\nжурнал\t/ws/tmp/autoland/x.log\nstate\t/ws/tmp/autoland/x.state', reasons: [], head: HW, ...take('alstart', () => ({})) }
    if (label.startsWith('mech:trial:')) return { out: '', head: '', reasons: [], ...take('trial:' + lane, () => ({ code: 0 })) }
    if (label === 'mech:cascade') return { code: 0, out: 'MERGED; доля 0.0 %', reasons: [], head: 'e'.repeat(40), ...take('merge', () => ({})) }
    if (label === 'mech:ci-epic') return { out: '', reasons: [], head: '', ...take('ciepic', () => ({ code: 3 })) }
    if (label.startsWith('mech:')) return { code: 0, out: '', reasons: [], head: '' }
    // Текстовый шаг (без схемы): ответ несёт блок ВОЗВРАТ; сценарий перекрывает ответы по префиксу метки (ws#1071).
    return take('text:' + label.split(':')[0], () => 'отчёт записан\n### ВОЗВРАТ\n- статус: готово')
  }
  const AF = Object.getPrototypeOf(async function () {}).constructor
  const fn = new AF('args', 'agent', 'phase', 'log', 'parallel', 'pipeline', body)
  let res
  try { res = await fn(sc.args, agent, () => {}, () => {}, async t => Promise.all(t.map(f => f())), null) } catch (e) { res = { thrown: String(e) } }
  return { res: res || {}, calls }
}
const REVIEWERS = ['wave-reviewer', 'landing-reviewer', 'go-style-reviewer', 'system-design-reviewer', 'db-architect-reviewer', 'proto-api-reviewer', 'security-auditor', 'acceptance-reviewer', 'acceptance-author']
const lanes2 = [{ key: 'A', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-a', text: 't' }, { key: 'B', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-b', text: 't' }]
const args = { repo: 'PRO-Robotech/kacho-workspace', wave: '9', epic: 'main', base: 'main', ws: '/ws', lanes: lanes2 }
// Задание R1 — то же, из которого построен план r1.json: B зависит от A.
const argsDep = { ...args, lanes: [lanes2[0], { ...lanes2[1], deps: ['A'] }] }
const argsDepC = { ...args, lanes: [...argsDep.lanes, { key: 'C', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-c', text: 't' }] }
// Полоса стоит (ws#999): не в сборке, названа в остатке; соседи — в сборке.
const asmHas = (calls, br) => calls.filter(c => c.label.startsWith('mech:assemble:')).some(c => c.prompt.includes(br + '@'))
const inRest = (res, k) => (res.remainder || []).some(x => x.key === k)
const idx = (calls, label) => calls.findIndex(c => c.label === label)
const prm = (calls, label) => (calls.find(c => c.label === label) || {}).prompt || ''
const by = (calls, f) => calls.filter(f).length
// Ответ не читается шаблоном только у счётчика ошибок — ему усилие low;
// прочей механике (решение ветвится по её ответу) ни модели, ни усилия (ws#1016).
const LOW_OK = l => l.startsWith('mech:err:')
const mechOk = calls => calls.filter(c => c.label.startsWith('mech:')).every(c => c.model === undefined && (LOW_OK(c.label) ? c.effort === 'low' : c.effort === undefined))

if (landWs) {
  // Режим --landing-command: команда landing-precheck переписи гейтов, отрисованная шаблоном, как есть.
  const lr = await run({ args: { ...args, ws: landWs }, plan: [P('r0.json')] })
  const lm = prm(lr.calls, 'mech:gates').match(/Выполни рецепт «ЗАПУСК»[^`]*`([^`]+)`/)
  if (!lm) { console.error('wave-template-inject: VOID — в задании mech:gates нет команды рецепта «ЗАПУСК» в обратных кавычках'); process.exit(2) }
  fs.writeFileSync(landOut, lm[1] + '\n')
  process.exit(0)
}
console.log('== R0: без рецензентов, механика без заданной модели')
let r = await run({ args, plan: [P('r0.json')] })
ok(r.res.ok === true, 'волна R0 влита', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => REVIEWERS.includes(c.agentType)) === 0, 'ни одного рецензента и приёмщика')
ok(by(r.calls, c => c.label.startsWith('mech:precheck:')) === 2, 'lane-precheck — по полосе')
ok(mechOk(r.calls) && by(r.calls, c => c.label.startsWith('mech:')) > 0, 'механика — модель не задана; усилие не задано у шагов, чей ответ читает решение')
ok(prm(r.calls, 'mech:autoland') !== '' && prm(r.calls, 'mech:gates') !== '' && !/--reviews/.test(prm(r.calls, 'mech:autoland') + prm(r.calls, 'mech:gates')), 'без рецензентов демон вливания и перепись гейтов — без --reviews')

console.log('== R1: один рецензент на собранную волну')
r = await run({ args: argsDep, plan: [P('r1.json')] })
ok(r.res.ok === true, 'волна R1 влита', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => c.agentType === 'wave-reviewer') === 1, 'wave-reviewer ровно один на волну')
ok(by(r.calls, c => REVIEWERS.includes(c.agentType) && c.agentType !== 'wave-reviewer') === 0, 'ролей полосы и landing-reviewer нет')
const iA = r.calls.findIndex(c => c.label === 'impl:A'), iB = r.calls.findIndex(c => c.label === 'impl:B'), pA = r.calls.findIndex(c => c.label === 'mech:precheck:A')
ok(iA >= 0 && iB > pA, 'B (зависит от A) начат после предпроверки A — слои плана')
ok(/ start --repo \S+ --pr 7 --head [0-9a-f]{40} --subject "[^"]+" --reviews \/ws\/tmp\/wave-9\/reviews\.json /.test(prm(r.calls, 'mech:autoland')), 'вердикт волны передан демону вливания (его landing-precheck)', prm(r.calls, 'mech:autoland').slice(-500))

console.log('== R2: полный набор')
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')] })
ok(r.res.ok === true, 'волна R2 влита', JSON.stringify(r.res).slice(0, 300))
for (const t of ['acceptance-author', 'db-architect-reviewer', 'wave-reviewer']) ok(by(r.calls, c => c.agentType === t) === 1, t + ' — один раз')
// ws#1242 п.3: задание полосы SQL/миграции несёт обе строки (прогон фикстуры до правки с чтением
// отказа; перепись подъёма в том же прогоне); полоса без SQL — не несёт.
const sqlTwo = s => /SQL\/МИГРАЦИЯ: пробу с новой фикстурой прогони на голове ДО правки и прочти текст отказа/.test(s) && /Перепись подъёма \(TestIntegration_RoleComposition\*[^)]*\) — в том же прогоне, что пробы предмета/.test(s)
ok(sqlTwo(prm(r.calls, 'impl:M')), 'полоса migration-writer — задание несёт обе строки SQL/миграции', prm(r.calls, 'impl:M').slice(0, 300))
{
  const rs = await run({ args: { ...args, lanes: [{ key: 'A', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-a', text: 't' }, { key: 'G', repo: 'kacho-workspace', agent: 'go-implementer', branch: '9-g', text: 't', paths: ['services/iam/internal/migrations/0042_roles.sql'] }] }, plan: [P('r0g.json')] })
  ok(sqlTwo(prm(rs.calls, 'impl:G')), 'полоса go-implementer с путём миграции — задание несёт обе строки')
  ok(prm(rs.calls, 'impl:A') !== '' && !/SQL\/МИГРАЦИЯ/.test(prm(rs.calls, 'impl:A')), 'близнец: полоса без SQL — строк SQL/миграции нет', prm(rs.calls, 'impl:A').slice(0, 200))
}
ok(by(r.calls, c => c.label.startsWith('census:')) === 1, 'перепись поверхности до кода')
ok(r.calls.findIndex(c => c.label.startsWith('census:')) < r.calls.findIndex(c => c.label.startsWith('impl:')), 'перепись — раньше исполнителя')
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')], staleRole: true })
ok(r.res.ok === false && /не на сведённой голове/.test(r.res.stage || ''), 'вердикт роли на чужой голове — остановка, sha не подменяется', JSON.stringify(r.res).slice(0, 200))

const two = P('r2two.json'), roles2 = two.lanes[0].roles
const ret = roles2[0], kept = roles2[1]
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'go-implementer', branch: '9-m', text: 't' }] }, plan: [two], ret })
const head2 = H('M', 2)
const atHead = (role, h) => r.calls.some(c => c.agentType === role && c.label.startsWith('review-') && c.prompt.includes('@' + h))
const laneM = (r.res.lanes || {}).M || {}
ok(r.res.ok === false && /не видели/.test(laneM.stage || '') && laneM.unseen + '' === kept, 'принявшая ' + kept + ' новую голову не видела — полоса стоит, роль названа', JSON.stringify(r.res).slice(0, 300))
ok(atHead(ret, head2) && !atHead(kept, head2), 'повтор — только вернувшей ' + ret + ' (§8а п.8), принявшая не переоткрыта')
ok(by(r.calls, c => c.label.startsWith('mech:assemble:')) === 0, 'остановка — до сборки, а не после CI')
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')], ret: P('r2.json').lanes[0].roles[0] })
const revOne = ((r.res.lanes || {}).M || {}).reviews || []
ok(r.res.ok === true && revOne.length === 1 && revOne[0].sha === head2 && atHead(revOne[0].role, head2), 'близнец: единственная роль вернула и приняла дельту — полоса идёт, вердикт на новой голове', JSON.stringify(r.res).slice(0, 200))

console.log('== зависимая полоса — от сводки голов deps (ws#938)')
// A проходит повтор предпроверки: итоговая голова A — вторая, её и обязана
// получить сводка (голова первой сдачи в сводке — код до доводки).
r = await run({ args: argsDep, plan: [P('r1.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
const hA = H('A', 2), hS = H('SB', 0)
ok(r.res.ok === true, 'волна с зависимой полосой влита', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => c.label === 'mech:stack:B') === 1 && by(r.calls, c => c.label.startsWith('mech:stack:') && c.label !== 'mech:stack:B') === 0, 'сводка — одна, только у полосы с deps')
const lastPreA = r.calls.map(c => c.label).lastIndexOf('mech:precheck:A')
ok(idx(r.calls, 'mech:stack:B') > lastPreA && idx(r.calls, 'impl:B') > idx(r.calls, 'mech:stack:B'), 'сводка — после того, как A прошёл; исполнитель B — после сводки')
ok(prm(r.calls, 'mech:stack:B').includes('9-a@' + hA) && !prm(r.calls, 'mech:stack:B').includes(H('A', 1)), 'в сводку идёт ИТОГОВАЯ голова A, а не первая сдача', prm(r.calls, 'mech:stack:B').slice(-400))
ok(prm(r.calls, 'mech:stack:B').includes('9-stack-b') && /--no-ff/.test(prm(r.calls, 'mech:stack:B')), 'сводка — ветка <N>-stack-<ключ>, коммиты слияния --no-ff')
ok(prm(r.calls, 'impl:B').includes('@' + hS) && !/ветка 9-b от main/.test(prm(r.calls, 'impl:B')), 'исполнитель B заводит ветку от головы сводки, а не от базы волны', prm(r.calls, 'impl:B').slice(-500))
ok(prm(r.calls, 'mech:precheck:B').includes(' b-B ' + hS + ' '), 'предпроверка B судит голову сводки как базу (BASE-NOT-ANCESTOR)', prm(r.calls, 'mech:precheck:B'))
ok(/ветка 9-a от main/.test(prm(r.calls, 'impl:A')) && prm(r.calls, 'mech:precheck:A').includes(' b-A main '), 'близнец: полоса без deps — от базы волны, сводки нет')
ok(prm(r.calls, 'mech:cascade').includes('9-stack-b'), 'временная сводка снимается шагом каскада после вливания')
r = await run({ args: argsDepC, plan: [P('r1c.json')] })
ok(r.res.ok === true && idx(r.calls, 'impl:C') >= 0 && idx(r.calls, 'impl:C') < idx(r.calls, 'mech:precheck:A'), 'независимая C стартует сразу, не дожидаясь A', JSON.stringify(r.res).slice(0, 200))
// A дольше C (доводка предпроверки): D (от C) обязана начаться, не дожидаясь A —
// слой плана порядок deps называет, но чужую полосу ждать не велит.
const argsDepD = { ...args, lanes: [...argsDepC.lanes, { key: 'D', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-d', text: 't', deps: ['C'] }] }
r = await run({ args: argsDepD, plan: [P('r1d.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
// Полоса прошла — после своей пробной сборки (ws#1053): D ждёт пробу C, но не A.
ok(r.res.ok === true && idx(r.calls, 'mech:stack:D') >= 0 && idx(r.calls, 'mech:trial:C') < r.calls.map(c => c.label).lastIndexOf('mech:precheck:A') && idx(r.calls, 'mech:stack:D') < idx(r.calls, 'mech:trial:A'), 'D (от C) стартует, когда прошла C, не дожидаясь A чужого слоя', JSON.stringify(r.calls.map(c => c.label)).slice(0, 400))
ok(prm(r.calls, 'mech:stack:D').includes('9-c@') && !prm(r.calls, 'mech:stack:D').includes('9-a@'), 'в сводку D — только её deps (C), чужая A не вливается')
// Тот же предмет без опоры на тайминг: A с доводкой заканчивает ПОСЛЕ C, и в
// момент сводки B полоса C уже прошла — в сводку B она попасть не должна.
ok(prm(r.calls, 'mech:stack:B').includes('9-a@') && !prm(r.calls, 'mech:stack:B').includes('9-c@') && idx(r.calls, 'mech:stack:B') > r.calls.map(c => c.label).lastIndexOf('mech:precheck:C'), 'в сводку B — только A, хотя C прошла раньше её сводки', prm(r.calls, 'mech:stack:B').slice(-300))
r = await run({ args: argsDepD, plan: [P('r1d.json')], 'pre:C': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
ok(r.res.ok === true && prm(r.calls, 'mech:stack:D').includes('9-c@') && !prm(r.calls, 'mech:stack:D').includes('9-a@') && idx(r.calls, 'mech:stack:D') > r.calls.map(c => c.label).lastIndexOf('mech:precheck:A'), 'зеркально: C с доводкой, A прошла раньше сводки D — в сводке D только C', prm(r.calls, 'mech:stack:D').slice(-300))
r = await run({ args: argsDepC, plan: [P('r1c.json')], 'pre:A': [{ code: 2, reasons: [] }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'impl:B' || c.label === 'mech:stack:B') === 0 && /не начата: deps A/.test(((r.res.remainder || []).find(x => x.key === 'B') || {}).stage || '') && by(r.calls, c => c.label === 'mech:precheck:C') === 1 && asmHas(r.calls, '9-c') && !asmHas(r.calls, '9-a') && !asmHas(r.calls, '9-b'), 'A не прошёл — B не начата (причина названа), A и B — остаток, C сведена и влита', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'conflict', head: '', conflicts: ['go.mod'] }] })
ok(inRest(r.res, 'B') && /конфликт в go\.mod/.test(((r.res.remainder || []).find(x => x.key === 'B') || {}).stage || '') && by(r.calls, c => c.label === 'impl:B') === 0 && !asmHas(r.calls, '9-b') && asmHas(r.calls, '9-a'), 'сводка конфликтует — B стоит с путём, исполнитель B не зван, B не в сборке, A сведена', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'done', head: hS, contains: [] }] })
ok(inRest(r.res, 'B') && !asmHas(r.calls, '9-b') && /нет голов 9-a@/.test(((r.res.remainder || []).find(x => x.key === 'B') || {}).stage || '') && by(r.calls, c => c.label === 'impl:B') === 0, 'сводка «готова», но головы A в ней нет — остановка, исполнитель не зван', JSON.stringify(r.res).slice(0, 300))
// Ответ сводки не годен — по одному факту против близнеца «done»: ответа нет,
// статус вне {done, already-done}, голова не sha40. Исполнитель не зван, шаблон
// не падает исключением, причина названа своими словами.
const stB = () => ((r.res.remainder || []).find(x => x.key === 'B') || {}).stage || ''
const stopB = () => !r.res.thrown && inRest(r.res, 'B') && by(r.calls, c => c.label === 'impl:B') === 0 && !asmHas(r.calls, '9-b')
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [null] })
ok(stopB() && /нет ответа/.test(stB()), 'сводка не ответила — остановка «нет ответа», а не исключение на st.status', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'failed', head: hS }] })
ok(stopB() && /статус failed/.test(stB()), 'сводка вернула failed при голове sha40 и всех головах deps — остановка, исполнитель не зван', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'done', head: 'abc123' }] })
ok(stopB() && /не sha40/.test(stB()), 'голова сводки не sha40 — остановка с этой причиной, исполнитель не зван', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'already-done', head: hS }] })
ok(r.res.ok === true && prm(r.calls, 'impl:B').includes('@' + hS), 'близнец: сводка already-done (уже есть на origin) — полоса идёт от её головы', JSON.stringify(r.res).slice(0, 300))

// Повторы зависимой полосы — от той же сводки, а не от базы волны: доводка после
// предпроверки, вторая предпроверка, доводка и предпроверка после возврата ролей.
const allFrom = (label, s) => { const xs = r.calls.filter(c => c.label === label); return xs.length && xs.every(c => c.prompt.includes(s)) ? xs.length : 0 }
r = await run({ args: argsDep, plan: [P('r1.json')], 'pre:B': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
ok(r.res.ok === true && allFrom('impl:B', 'сводки deps 9-stack-b@' + hS) === 2 && !r.calls.some(c => c.label === 'impl:B' && /ветка 9-b от main/.test(c.prompt)), 'доводка B после красной предпроверки — от сводки, не от базы волны', JSON.stringify(r.calls.filter(c => c.label === 'impl:B').map(c => c.prompt.slice(0, 160))))
ok(allFrom('mech:precheck:B', ' b-B ' + hS + ' ') === 2, 'вторая предпроверка B — база та же голова сводки (BASE-NOT-ANCESTOR не теряется)', JSON.stringify(r.calls.filter(c => c.label === 'mech:precheck:B').map(c => c.prompt.slice(-260))))
const hSM = H('SM', 0), roleM = P('r2dep.json').lanes.find(x => x.key === 'M').roles[0]
const argsDepM = { ...args, lanes: [lanes2[0], { key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't', deps: ['A'] }] }
r = await run({ args: argsDepM, plan: [P('r2dep.json')] })
const revM = r.calls.find(c => c.agentType === roleM && c.label === 'review-' + roleM + ':M')
ok(r.res.ok === true && !!revM && revM.prompt.includes('git diff ' + hSM + '..' + H('M', 1)), 'ревью зависимой полосы — своя дельта сводка..голова, код принятых deps не предмет', revM ? revM.prompt.slice(0, 400) : 'ревью роли не звано')
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')] })
ok(r.calls.some(c => c.label.startsWith('review-') && c.label.endsWith(':M') && c.agentType !== 'acceptance-reviewer') && !r.calls.some(c => /своя дельта|git diff/.test(c.prompt) && c.label.startsWith('review-') && c.label.endsWith(':M')), 'близнец: полоса без deps — ревью всей головы, дельты сводки нет')
r = await run({ args: argsDepM, plan: [P('r2dep.json')], ret: roleM })
ok(r.res.ok === true && allFrom('impl:M', 'сводки deps 9-stack-m@' + hSM) === 2 && allFrom('mech:precheck:M', ' b-M ' + hSM + ' ') === 2, 'возврат роли зависимой полосы — доводка и предпроверка от той же сводки', JSON.stringify(r.calls.filter(c => c.label === 'impl:M' || c.label === 'mech:precheck:M').map(c => c.label + ' ' + c.prompt.slice(0, 120))))

// База сводки — база ПОЛОСЫ (l.base), а не волны: у B своя база release-x.
r = await run({ args: { ...argsDep, lanes: [lanes2[0], { ...lanes2[1], deps: ['A'], base: 'release-x' }] }, plan: [P('r1.json')] })
ok(r.res.ok === true && prm(r.calls, 'mech:stack:B').includes('от свежего origin/release-x ') && !prm(r.calls, 'mech:stack:B').includes('origin/main'), 'сводка полосы со своей базой — от origin/<база полосы>, не от базы волны', prm(r.calls, 'mech:stack:B').slice(0, 300))

// Имя сводки: форма <N>-<суффикс> и столкновение — остановка на плане.
r = await run({ args: { ...argsDep, wave: 'x9' }, plan: [P('r1.json')] })
ok(r.res.ok === false && r.res.stage === 'план' && /не по форме/.test(r.res.why || '') && by(r.calls, c => c.label.startsWith('impl:') || c.label.startsWith('mech:stack:')) === 0, 'номер волны не число — имя сводки не по форме, остановка на плане', JSON.stringify(r.res).slice(0, 300))
const dl = k => ({ key: k, repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-' + k.toLowerCase(), text: 't', deps: ['A'] })
r = await run({ args: { ...args, lanes: [lanes2[0], dl('B-1'), dl('B_1')] }, plan: [P('r1coll.json')] })
ok(r.res.ok === false && r.res.stage === 'план' && /совпало у двух/.test(r.res.why || '') && by(r.calls, c => c.label.startsWith('impl:')) === 0, 'ключи B-1 и B_1 дают одно имя сводки — остановка на плане', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: { ...args, lanes: [lanes2[0], dl('B-1'), dl('B-2')] }, plan: [P('r1two.json')] })
ok(r.res.ok === true && prm(r.calls, 'mech:stack:B-1').includes('9-stack-b-1 ') && prm(r.calls, 'mech:stack:B-2').includes('9-stack-b-2 '), 'близнец: ключи B-1 и B-2 — две сводки со своими именами', JSON.stringify(r.res).slice(0, 300))

// Хук kaname принимает ветку только номером (^[0-9]+$): имя <N>-stack-<ключ>
// он отвергает, и полоса с deps не стартует. Сводка такой полосы — в ветке
// самой полосы; голова каждой dep — её предок до исполнителя (ws#946).
console.log('== зависимая полоса kaname — сводка в ветке полосы (ws#946)')
const branchOf = c => (c.prompt.match(/заведи ветку (\S+)/) || [])[1] || ''
const knLanes = [{ key: 'A', repo: 'kaname', agent: 'go-implementer', branch: '683', text: 't' }, { key: 'B', repo: 'kaname', agent: 'go-implementer', branch: '684', text: 't', deps: ['A'] }]
r = await run({ args: { ...args, repo: 'PRO-Robotech/kaname', base: '296', epic: '296', lanes: knLanes }, plan: [P('kn.json')] })
const knStack = r.calls.filter(c => c.label.startsWith('mech:stack:'))
const knNames = [...knStack.map(branchOf), ...(r.res.stacks || [])]
ok(r.res.ok === true && knStack.length === 1 && branchOf(knStack[0]) === '684', 'kaname: сводка deps B заводится в ветке самой полосы 684', JSON.stringify({ res: r.res.stage, names: knNames }).slice(0, 300))
ok(knNames.every(b => /^[0-9]+$/.test(b)) && !r.calls.some(c => /\d+-stack-/.test(c.prompt)), 'kaname: ни одно задание не заводит и не снимает ветку, чьё имя не число', JSON.stringify(knNames))
ok(knStack.length === 1 && /merge-base --is-ancestor/.test(knStack[0].prompt) && knStack[0].prompt.includes('683@' + H('A', 1)), 'kaname: голова A вливается в 684 и сверяется is-ancestor до исполнителя')
ok(knStack.length === 1 && knStack[0].prompt.includes('#684 merge #683: ') && knStack[0].prompt.includes('#684 merge #296: '), 'kaname: слияния в ветке полосы — по форме хука «#<N> merge #<M>: …»', knStack.length ? knStack[0].prompt.slice(0, 600) : '')
ok(idx(r.calls, 'impl:B') > idx(r.calls, 'mech:stack:B') && prm(r.calls, 'impl:B').includes('684@' + H('SB', 0)) && prm(r.calls, 'mech:precheck:B').includes(' ' + H('SB', 0) + ' '), 'kaname: исполнитель B продолжает 684 от головы сводки, предпроверка судит её как базу')
ok(/уже в твоей ветке на origin — продолжай её от этой головы/.test(prm(r.calls, 'impl:B')) && !/влей сводку/.test(prm(r.calls, 'impl:B')), 'kaname: исполнителю B — «продолжай свою ветку», а не «влей сводку»', prm(r.calls, 'impl:B').slice(0, 400))
ok(!(r.res.stacks || []).length && !/временные сводки/.test(prm(r.calls, 'mech:cascade')), 'kaname: ветка полосы не числится временной сводкой и вливанием не снимается', JSON.stringify(r.res.stacks))
r = await run({ args: { ...args, repo: 'PRO-Robotech/kaname', base: '296', epic: '296', lanes: knLanes }, plan: [P('kn.json')], 'stack:B': [{ status: 'done', head: H('SB', 0), branch: '9-stack-b' }] })
ok(r.res.ok === true && prm(r.calls, 'impl:B').includes('684@' + H('SB', 0)) && !r.calls.some(c => c.label !== 'mech:stack:B' && /9-stack-b/.test(c.prompt)), 'kaname: механик вернул чужое имя ветки — исполнитель всё равно в 684, чужое имя дальше не идёт', JSON.stringify(r.calls.filter(c => /9-stack-b/.test(c.prompt)).map(c => c.label)))
const kcLanes = [{ key: 'A', repo: 'kacho', agent: 'go-implementer', branch: '3101-a', text: 't' }, { key: 'B', repo: 'kacho', agent: 'go-implementer', branch: '3101-b', text: 't', deps: ['A'] }]
r = await run({ args: { ...args, repo: 'PRO-Robotech/kacho', lanes: kcLanes }, plan: [P('kc.json')] })
ok(r.res.ok === true && branchOf(r.calls.find(c => c.label === 'mech:stack:B') || { prompt: '' }) === '9-stack-b' && (r.res.stacks || []).join() === '9-stack-b' && prm(r.calls, 'mech:cascade').includes('9-stack-b'), 'близнец kacho: сводка — прежняя ветка 9-stack-b, снимается вливанием', JSON.stringify(r.res.stacks))
ok(/ветка уже есть на origin — влей сводку в неё коммитом слияния/.test(prm(r.calls, 'impl:B')) && !/уже в твоей ветке/.test(prm(r.calls, 'impl:B')), 'близнец kacho: исполнителю B — «влей сводку», а не «сводка уже в твоей ветке»', prm(r.calls, 'impl:B').slice(0, 400))
ok(!/это ветка самой полосы/.test(prm(r.calls, 'mech:stack:B')) && !/#3101-b merge/.test(prm(r.calls, 'mech:stack:B')), 'близнец kacho: механику сводки нет подсказки «ветка самой полосы» и формы «#3101-b merge …»', prm(r.calls, 'mech:stack:B').slice(0, 600))
r = await run({ args: { ...args, repo: 'PRO-Robotech/kacho', lanes: kcLanes }, plan: [P('kc.json')], 'stack:B': [{ status: 'done', head: H('SB', 0), branch: '9-stack-b-m' }] })
ok(r.res.ok === true && prm(r.calls, 'impl:B').includes('сводки deps 9-stack-b-m@' + H('SB', 0)) && (r.res.stacks || []).join() === '9-stack-b-m', 'близнец kacho: ветка сводки — та, что вернул механик (9-stack-b-m), а не имя из задания', JSON.stringify({ stacks: r.res.stacks, impl: prm(r.calls, 'impl:B').slice(0, 200) }))
// Ветвь mergeSubj: номер — с решёткой, не-номер (база main) — как есть.
r = await run({ args: { ...args, repo: 'PRO-Robotech/kaname', base: 'main', epic: 'main', lanes: knLanes }, plan: [P('kn.json')] })
ok(prm(r.calls, 'mech:stack:B').includes('#684 merge main: ') && !prm(r.calls, 'mech:stack:B').includes('#main') && prm(r.calls, 'mech:stack:B').includes('#684 merge #683: '), 'kaname: в форме слияния номер с решёткой (#683), не-номер без неё (main)', prm(r.calls, 'mech:stack:B').slice(0, 600))
// Ветвь базы в форме слияния: база полосы, а не волны, и база волны, когда своей нет.
r = await run({ args: { ...args, repo: 'PRO-Robotech/kaname', base: '296', epic: '296', lanes: [knLanes[0], { ...knLanes[1], base: '297' }] }, plan: [P('kn.json')] })
ok(prm(r.calls, 'mech:stack:B').includes('#684 merge #297: ') && !prm(r.calls, 'mech:stack:B').includes('#684 merge #296: '), 'kaname: слияние базы — база полосы (#297), а не волны (#296)', prm(r.calls, 'mech:stack:B').slice(0, 600))

r = await run({ args: { ...args, crossRepo: true }, plan: [P('r0.json')] })
ok(prm(r.calls, 'mech:plan:1').includes('"crossRepo":true'), 'явный crossRepo задания уходит в план (межрепозиторная сверка — по флагу)')
r = await run({ args, plan: [P('r0.json')] })
ok(!prm(r.calls, 'mech:plan:1').includes('crossRepo'), 'близнец: без флага в плане его нет — сосед на плане одного репозитория не судится')

console.log('== «идёт» и «уже сделано» — не провал')
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, { code: 3 }, { code: 0 }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 3, 'CI идёт дважды — ждать, затем зелёное')
// ws#1013: черновик — целевой зелёный (код 5) переводит PR в ready ОДИН раз и ждёт полного
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 5 }, { code: 3 }, { code: 0 }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:ready') === 1 && /gh pr ready 7/.test(prm(r.calls, 'mech:ready')) && by(r.calls, c => c.label.startsWith('mech:ci:')) === 1 && idx(r.calls, 'mech:autoland') > idx(r.calls, 'mech:ready'), 'черновик: целевой зелёный — перевод в ready один раз; полный прогон шаблон не читает — его ждёт демон вливания (ws#1152)', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 5 }, { code: 5 }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:ready') === 1 && by(r.calls, c => c.label.startsWith('mech:ci:')) === 1, 'после перевода в ready — ни второго чтения, ни второго перевода', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')] })
ok(/открой ЧЕРНОВИКОМ \(`gh pr create --draft`\)/.test(prm(r.calls, 'mech:assemble:1')) && /affected\.py --base origin\/\S+ --run/.test(prm(r.calls, 'mech:assemble:1')), 'сборка: PR черновиком, выбор затронутого до каждой отправки')
ok(/`RITUAL_REPO_DIR=\/ws\/tmp\/wave-9\/assemble bash \/ws\/scripts\/pr-body\.sh PRO-Robotech\/kacho-workspace origin\/main HEAD > \/ws\/tmp\/wave-9\/reports\/pr-body-1\.md`/.test(prm(r.calls, 'mech:assemble:1')) && /gh pr create --draft --body-file/.test(prm(r.calls, 'mech:assemble:1')) && /руками не пишется/.test(prm(r.calls, 'mech:assemble:1')), 'сборка: тело PR — только вывод pr-body.sh (ws#1146), руками не пишется', prm(r.calls, 'mech:assemble:1').slice(-600))
const alS = prm(r.calls, 'mech:autoland')
ok(/`RITUAL_REPO_DIR=\/ws\/tmp\/wave-9\/assemble bash \/ws\/scripts\/pr-body\.sh PRO-Robotech\/kacho-workspace origin\/main f{40} > \/ws\/tmp\/wave-9\/reports\/pr-body-land\.md && gh pr edit 7 -R PRO-Robotech\/kacho-workspace --body-file /.test(alS) && alS.indexOf('pr-body.sh') < alS.indexOf(' start --repo'), 'посадка: тело PR заново генератором до старта демона', alS.slice(-700))
ok(by(r.calls, c => c.label.startsWith('mech:err:')) === 0, 'ожидание CI ошибкой не записано')
r = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'already-done', head: H('A', 9) }] })
ok(r.res.ok === true, '«уже сделано» исполнителя — полоса идёт дальше')

console.log('== повтор — только при новой голове')
r = await run({ args, plan: [P('r0.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }], 'impl:A': [{ status: 'done', head: H('A', 1) }, { status: 'done', head: H('A', 1) }] })
ok(inRest(r.res, 'A') && !asmHas(r.calls, '9-a') && by(r.calls, c => c.label === 'mech:precheck:A') === 1, 'голова не сменилась — предпроверка не повторена, A — остаток', JSON.stringify(r.res).slice(0, 200))
ok(r.calls.some(c => c.label === 'mech:err:A' && /executor-mechanics/.test(c.prompt)), 'возврат не из-за кода — строка счётчика executor-mechanics')
r = await run({ args, plan: [P('r0.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:precheck:A') === 2, 'близнец: голова новая — повтор и зелёное')

console.log('== план — единственный источник шагов')
const odd = P('r0.json'); odd.lanes[0].steps = ['implementer', 'teleport']
r = await run({ args, plan: [odd] })
ok(r.res.ok === false && r.res.stage === 'план' && by(r.calls, c => c.label.startsWith('impl:')) === 0, 'неизвестный шаг — остановка на плане, исполнителей нет')
const skew = { ...P('r0.json'), code: 1, autoRepin: [{ repo: 'kaname', from: 'v1.10.0', to: 'v1.11.0' }], reasons: [{ code: 'CORELIB-SKEW', text: 'x' }] }
const fixed = P('r0.json'); fixed.lanes.unshift({ ...fixed.lanes[0], key: 'repin-kaname' }); fixed.layers = [['repin-kaname'], ['A', 'B']]
r = await run({ args: { ...args, lanes: lanes2.map(l => ({ ...l, repo: 'kaname' })) }, plan: [skew, fixed] })
const p2 = (r.calls.filter(c => c.label.startsWith('mech:plan:'))[1] || {}).prompt || ''
ok(/"key":"repin-kaname"/.test(p2) && /"deps":\["repin-kaname"\]/.test(p2), 'corelib разный — полоса перепина первой, остальные от неё, план повторён')
ok(r.calls.findIndex(c => c.label === 'impl:repin-kaname') < r.calls.findIndex(c => c.label === 'impl:A'), 'перепин исполнен раньше полос репозитория')

console.log('== посадка — демоном вливания (ws#1147, ws#1152): start, один status, исход дословно')
r = await run({ args, plan: [P('r0.json')] })
const alSt = prm(r.calls, 'mech:autoland:status')
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:autoland') === 1 && by(r.calls, c => c.label === 'mech:autoland:status') === 1 && idx(r.calls, 'mech:autoland:status') > idx(r.calls, 'mech:autoland') && idx(r.calls, 'mech:cascade') > idx(r.calls, 'mech:autoland:status') && r.res.merge === 'e'.repeat(40), 'влито демоном: start, ОДИН status, затем каскад; коммит слияния — из строки merged', JSON.stringify(r.res).slice(0, 200))
ok(/`bash \/ws\/scripts\/autoland\/autoland\.sh status \/ws\/tmp\/autoland\/PRO-Robotech__kacho-workspace__7__f{12}\.state`/.test(alSt), 'status — одной командой по .state этой головы', alSt.slice(-400))
ok(!r.calls.some(c => /^mech:(landing|ci-land|delta|merge|pr-edit)/.test(c.label)), 'гейтов ради вливания, чтения CI на голове посадки и правки тела агентом нет')
const BODY_RED = 'red landing-precheck код 1: REASON\tBODY-MISSING-COMMIT\tкоммит ab12 не назван в теле'
r = await run({ args, plan: [P('r0.json')], al: [{ code: 1, out: BODY_RED, reasons: ['BODY-MISSING-COMMIT'] }] })
ok(r.res.ok === false && r.res.state === 'failed' && (r.res.stage || '').includes(BODY_RED) && by(r.calls, c => c.label === 'mech:cascade') === 0 && by(r.calls, c => c.label === 'mech:autoland') === 1 && r.res.redRound === undefined, 'красный исход демона — диспетчеру дословно; ни правки тела, ни повторного старта, ни каскада', JSON.stringify(r.res).slice(0, 300))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 1, out: 'red merge-readiness код 1: REASON\tMERGE-READINESS\tконтекст красный', reasons: ['MERGE-READINESS'] }] })
ok(r.res.ok === false && r.res.state === 'failed' && /^autoland[^:]*: red merge-readiness код 1: REASON\tMERGE-READINESS/.test(r.res.stage || '') && by(r.calls, c => c.label === 'mech:cascade') === 0, 'merge-readiness не 0 (демон: red) — вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 3, out: 'running ci-read' }] })
ok(r.res.ok === false && r.res.state === 'running' && r.res.autoland === '/ws/tmp/autoland/PRO-Robotech__kacho-workspace__7__' + 'f'.repeat(12) + '.state' && by(r.calls, c => c.label === 'mech:cascade') === 0 && by(r.calls, c => c.label === 'mech:autoland:status') === 1, 'демон идёт (status 3) — state running с путём .state, второго status и каскада нет', JSON.stringify(r.res).slice(0, 300))
r = await run({ args, plan: [P('r0.json')], alstart: [{ code: 2, out: 'autoland: ОТКАЗ — --head не sha40' }] })
ok(r.res.ok === false && r.res.state === 'failed' && /^autoland start: демон не запущен \(код 2\): autoland: ОТКАЗ/.test(r.res.stage || '') && by(r.calls, c => c.label === 'mech:autoland:status') === 0, 'start не 0 и не 3 — статуса и вливания нет, отказ дословно', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], alstart: [{ code: 3, out: 'autoland: ОТКАЗ — PR уже ведёт другой демон' }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:autoland:status') === 1, 'близнец: start 3 (PR уже ведёт демон) — исход читается тем же status', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 0, out: 'running ci-read' }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:cascade') === 0 && /merged без sha/.test(r.res.stage || ''), 'код 0 без строки merged <sha> — не влито, каскада нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 4, out: 'stale-base REASON\tBASE-STALE\tбаза ушла', reasons: ['BASE-STALE'] }] })
ok(r.res.ok === false && r.res.state === 'failed' && /база устарела/.test(r.res.stage || '') && r.res.redRound === undefined, 'stale-base (status 4) — база устарела, не красное', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 5, out: 'head-moved ' + 'f'.repeat(40) + ' ' + 'd'.repeat(40) }] })
ok(r.res.ok === false && r.res.state === 'failed' && /^autoland[^:]*: head-moved f{40} d{40}$/.test(r.res.stage || '') && by(r.calls, c => c.label === 'mech:cascade') === 0, 'head-moved (status 5) — вливания нет, обе головы дословно', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], al: [{ code: 2, out: 'void ci-read код 2 3 раз подряд: REASON\tRATE-LIMIT\tсброс в 14:05', reasons: ['RATE-LIMIT'] }] })
ok(r.res.ok === false && r.res.state === 'not-run' && /сброс в 14:05/.test(r.res.stage || ''), 'void (status 2) — not-run, не красное; причина дословно', JSON.stringify(r.res).slice(0, 200))

console.log('== демон вливания: кэш возобновления, запреты заданий (приёмка check-verifier ws#1152)')
{
  // Своё задание шага — текст после общей преамбулы C (её префикс один у всех шагов), в какой бы
  // форме шаг ни был к ней приклеен.
  const PRE = (await run({ args, plan: [P('r0.json')] })).calls[0].prompt.split('\n\n')[0]
  const own = c => c.prompt.startsWith(PRE) ? c.prompt.slice(PRE.length) : c.prompt
  // Узнаватель от КЛАССА, а не от перечня строк (testing.md#recognizer-built-from-class-not-form-list):
  // указание — вхождение глагола класса в предложении задания, не снятое отрицанием. Отрицание
  // засчитывается ровно в двух случаях: (а) частица «не»/«ни» ВПЛОТНУЮ перед глаголом, без слов
  // между; (б) закрытый перечень «не нужно · не надо · не следует · нельзя · запрещено» ВПЛОТНУЮ
  // к неопределённой форме — сразу перед ней («нельзя ждать») либо сразу после («ждать нельзя»):
  // чужой запрет через слова («дождаться …, без этого нельзя») указание не гасит. Прочее —
  // указание: «не забудь X», «не упусти X» — указание X. Предложения — по [.;!?] и «, а|но|затем».
  const LET = '[а-яёa-z0-9_]'
  const word = alts => new RegExp('(?<!' + LET + ')(?:' + alts + ')(?!' + LET + ')', 'gi')
  const NEG_LIST = new RegExp('(?<!' + LET + ')(?:не нужно|не надо|не следует|нельзя|запрещено)(?!' + LET + ')', 'gi')
  const clausesOf = t => t.split(/[.;!?](?=\s|$)|,\s+(?=(?:а|но|затем|потом)\s)/)
  const live = (cl, re) => {
    const g = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g'); let m
    while ((m = g.exec(cl))) {
      const s0 = m.index, e0 = m.index + m[0].length
      if (/(?:^|[^а-яёa-z0-9_])(?:не|ни)\s+[`«"(]*$/i.test(cl.slice(0, s0))) continue   // (а)
      if (/(?:ться|тись|ть|чься|чь|сти)$/i.test(m[0])) {                              // (б)
        const near = [...cl.matchAll(NEG_LIST)].some(n => /^\s+$/.test(cl.slice(n.index + n[0].length, s0)) || /^\s+$/.test(cl.slice(e0, n.index)))
        if (near) continue
      }
      return true
    }
    return false
  }
  // directs — в тексте есть живое указание глагола класса (и, если задан, его предмета в том же предложении).
  const directs = (t, verbs, obj) => clausesOf(t).some(cl => (!obj || obj.test(cl)) && live(cl, verbs))
  const START_CMD = /autoland(?:\.sh)?\s+start(?![a-z])/i
  const START_VERB = word('запусти|запустите|запустить|перезапусти|перезапустить|стартуй|подними|поднять|вызови|вызвать|выполни|выполнить|повтори|повторить')
  const isStart = c => directs(own(c), START_CMD) || directs(own(c), START_VERB, /демон|autoland|старт|start/i)
  const WAIT = word('жди|ждите|дождись|дождитесь|дожидайся|дожидаться|дождаться|ждать|подожди|подождать|ожидай|ожидать|выжди|выждать|sleep\\s+\\d|--watch|gh run watch|gh pr checks|пока\\s+(?:\\S+\\s+){0,4}?не|до\\s+(?:кода|исхода|завершени\\S*|зелён\\S*|конца)')
  const READ = word('читай|прочти|прочитай|перечитай|читать|прочесть|прочитать|зови|вызови|позови|вызвать|звать|запусти|запустить|выполни|выполнить|гони|прогони|прогнать|повтори|повторить|проверь|проверить|посмотри|сверь|опроси|опрашивай')
  const CI_OBJ = /ci-read|(?<![A-Za-z-])CI(?![A-Za-z-])|конвейер|check-runs|вердикт/
  const CLOSE = word('закрой|закройте|закрывай|закрывайте|закрыть|закрывать|gh issue close')
  const TASK_OBJ = /задач|issue|(?<![A-Za-z0-9])#\d|волн/i
  const BODY = word('напиши|напишите|пиши|писать|написать|составь|составить|сочини|дополни|дополнить|допиши|дописать|поправь|поправить|исправь|исправить|отредактируй|редактируй|правь|впиши|вписать|собери|собрать|сформируй|оформи|сделай')
  const BODY_OBJ = /(?<![а-яё])тел(о|а|у|ом|е)(?![а-яё])/i
  const REPEAT = word('повтори|повторяй|повторить|повторять|повторно|ещё раз|еще раз|снова|опять|дважды|трижды|многократно|несколько раз|\\d+\\s*раза?|кажды[ейм]|каждую|через\\s+(?:\\d+\\s*)?(?:минут\\S*|мин|секунд\\S*|сек|с|час\\S*)')
  // E1. Workflow отдаёт шаг из кэша по тексту задания. Start — ЛЮБОЕ задание, велящее исполнить
  // старт демона, какая бы ни была метка: за проходы rerun 0 и 1 — ровно одно различное задание
  // start и по одному на проход; status — новое на каждый проход.
  // Проходы — по пути черновика (ci 5 → ready): старт обязан быть один и среди заданий ready.
  const p0 = await run({ args, plan: [P('r0.json')], ci: [{ code: 5 }], al: [{ code: 3, out: 'running ci-read' }] })
  const p1 = await run({ args: { ...args, rerun: 1 }, plan: [P('r0.json')], ci: [{ code: 5 }] })
  const both = [...p0.calls, ...p1.calls]
  const sts = both.filter(isStart), stDist = new Set(sts.map(c => c.prompt)).size
  const stat = l => new Set(both.filter(c => c.label === l).map(c => c.prompt)).size
  ok(stDist === 1 && p0.calls.filter(isStart).length === 1 && p1.calls.filter(isStart).length === 1 && stat('mech:autoland:status') === 2 && by(p1.calls, c => c.label === 'mech:autoland:status') === 1, 'E1 возобновление: задание старта демона (по команде, не по метке) — одно на оба прохода и одно на проход, status — новое на каждый проход', JSON.stringify({ start: stDist, labels: sts.map(c => c.label), status: stat('mech:autoland:status') }))
  // E3. До каскада ни одно задание не велит закрыть задачи; велит лишь каскад.
  const q = await run({ args, plan: [P('r0.json')] })
  const iC = idx(q.calls, 'mech:cascade')
  const early = q.calls.filter((c, i) => i < iC && directs(own(c), CLOSE, TASK_OBJ)).map(c => c.label)
  ok(iC > 0 && early.length === 0 && directs(own(q.calls[iC]), CLOSE, TASK_OBJ), 'E3 до каскада ни одно задание не велит закрыть задачи; велит лишь каскад', early.join(','))
  // E4. Сбой генератора тела — остановка (сборка и старт); ни одно задание не велит писать тело самому.
  const asmO = own(q.calls.find(c => c.label === 'mech:assemble:1') || { prompt: '' }), alO = own(q.calls.find(isStart) || { prompt: '' })
  const hand = q.calls.filter(c => directs(own(c), BODY, BODY_OBJ)).map(c => c.label)
  ok(/\(код не 0 — (?=[^)]*status failed)(?=[^)]*PR не трогать)[^)]*\)/.test(asmO) && /\(код не 0 — (?=[^)]*code 2)(?=[^)]*демон не запускать)[^)]*\)/.test(alO) && hand.length === 0, 'E4 сбой генератора тела — остановка (сборка: status failed; старт: code 2); тело руками не велит ни одно задание', hand.join(',') || alO.slice(0, 300))
  // E5. После ready ни одно задание не ждёт CI и не читает его повторно. Законно ровно одно —
  // однократное чтение ci-read.sh в переписи гейтов без ожидания: изымается этот факт, а не шаг.
  const qr = await run({ args, plan: [P('r0.json')], ci: [{ code: 5 }] })
  const iR = idx(qr.calls, 'mech:ready'), iRC = idx(qr.calls, 'mech:cascade')
  const ALLOWED = /ci-read\.sh \([^)]*без ожидания[^)]*\)/
  const gt = own(qr.calls.find(c => c.label === 'mech:gates') || { prompt: '' })
  // Во фрагменте разрешено ровно одно чтение без ожидания: ни «ждать», ни «читать» (предмет — сам
  // фрагмент), ни повтора («перечитай», «трижды», «повторно»).
  const frag = (gt.match(ALLOWED) || [''])[0]
  const allowedOnce = (gt.match(/ci-read/g) || []).length === 1 && frag !== '' && !directs(frag, WAIT) && !directs(frag, READ) && !directs(frag, REPEAT)
  const bad = qr.calls.filter((c, i) => i >= iR && i < iRC).filter(c => { const t = c.label === 'mech:gates' ? own(c).replace(ALLOWED, '') : own(c); return directs(t, WAIT) || directs(t, READ, CI_OBJ) }).map(c => c.label)
  ok(iR > 0 && iRC > iR && allowedOnce && bad.length === 0, 'E5 после ready ни одно задание не ждёт CI и не читает его повторно; законно лишь однократное чтение ci-read.sh в переписи без ожидания', JSON.stringify({ bad, allowedOnce }))
  // E6, E8. status — первая строка .state ДОСЛОВНО; ни повтора, ни ожидания.
  const st = own(q.calls.find(c => c.label === 'mech:autoland:status') || { prompt: '' })
  ok(/out \(первая строка \.state[^)]*ДОСЛОВНО/.test(st), 'E6 status требует первую строку .state ДОСЛОВНО', st.slice(0, 400))
  ok(st !== '' && !directs(st, WAIT) && !directs(st, REPEAT), 'E8 задание status не велит ни повторять, ни ждать', st.slice(0, 400))
}

console.log('== номер PR — целое ≥ 1, иначе остановка с причиной (ws#935)')
for (const [name, v] of [['нет поля', { pr: undefined }], ['0', { pr: 0 }], ['строка «—»', { pr: '—' }], ['адрес', { pr: 'https://github.com/o/r/pull/7' }]]) {
  r = await run({ args, plan: [P('r1.json')], asm: [v] })
  const after = by(r.calls, c => c.agentType === 'wave-reviewer' || c.label.startsWith('mech:ci:') || c.label.startsWith('mech:autoland') || c.label === 'mech:cascade')
  const undef = r.calls.some(c => /PR #(undefined|0\b|—|null)/.test(c.prompt || ''))
  ok(r.res.ok === false && r.res.state === 'failed' && /номер PR не целое/.test(r.res.stage || '') && after === 0 && !undef, 'pr ' + name + ' — остановка на сборке, рецензента, CI и посадки нет, «PR #undefined» не подставлен', JSON.stringify(r.res).slice(0, 200))
}
r = await run({ args, plan: [P('r1.json')] })
const prSchema = (((r.calls.find(c => c.label.startsWith('mech:assemble:')) || {}).schema || {}).properties || {}).pr || {}
const revSchema = (((r.calls.find(c => c.label === 'review-wave') || {}).schema || {}).properties || {}).verdict || {}
ok(prSchema.type === 'integer' && prSchema.minimum === 1, 'схема сборки требует pr целым ≥ 1', JSON.stringify(prSchema))
ok(JSON.stringify(revSchema.enum) === JSON.stringify(['accept', 'return', 'void']), 'словарь вердикта роли закрыт: accept | return | void', JSON.stringify(revSchema))
ok(r.res.ok === true && r.calls.filter(c => c.label.startsWith('mech:ci:') || c.label.startsWith('mech:autoland')).every(c => /PR #7\b|\s7\s/.test(c.prompt)), 'близнец: pr 7 — номер идёт в CI и посадку')

console.log('== вердикт рецензента — только поле verdict')
r = await run({ args, plan: [P('r1.json')], wave: [{ verdict: undefined, report: '✅ принято' }] })
ok(r.res.ok === false && by(r.calls, c => c.label.startsWith('mech:autoland')) === 0, 'нет поля verdict, в тексте «✅ принято» — не принят, вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r1.json')], wave: [{ verdict: 'void', report: 'прогон недействителен' }] })
ok(r.res.ok === false && by(r.calls, c => c.label.startsWith('mech:ci:')) === 0, 'verdict void — не принят, CI не зовётся')

console.log('== вердикт — о своей полосе: возврат одной не снимает соседние (ws#999)')
// R0, A и B независимы; B не прошла предпроверку дважды на разных головах.
r = await run({ args, plan: [P('r0.json')], 'pre:B': [{ code: 1, reasons: ['UNCOMMITTED'] }, { code: 1, reasons: ['UNCOMMITTED'] }] })
const asmP = n => prm(r.calls, 'mech:assemble:' + n)
ok(r.res.ok === true && /9-a@/.test(asmP(1)) && !/9-b@/.test(asmP(1)) && by(r.calls, c => c.label === 'mech:cascade') === 1, 'полоса B не прошла — A сведена и влита, B не в сборке', JSON.stringify(r.res).slice(0, 300))
ok(((r.res.remainder || []).map(x => x.key)).join() === 'B' && /закрой задачи влитых полос A со ссылкой на их DoD-proof; остаток B не закрывать/.test(prm(r.calls, 'mech:cascade')), 'B — остаток: назван в итоге и в задании вливания, её задачи не закрываются')
r = await run({ args, plan: [P('r0.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }, { code: 1, reasons: ['UNCOMMITTED'] }], 'pre:B': [{ code: 1, reasons: ['UNCOMMITTED'] }, { code: 1, reasons: ['UNCOMMITTED'] }] })
ok(r.res.ok === false && by(r.calls, c => c.label.startsWith('mech:assemble:')) === 0, 'близнец: не прошла ни одна — сборки нет')
// R1 A,C|B (B зависит от A): рецензент волны вернул ТОЛЬКО C — A и B садятся.
const argsABC = { ...args, lanes: [argsDep.lanes[0], argsDep.lanes[1], { key: 'C', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-c', text: 't' }] }
const W3 = (a, b, c) => ({ verdict: 'return', blocking: ['x'], lanes: [{ key: 'A', verdict: a, blocking: [] }, { key: 'B', verdict: b, blocking: [] }, { key: 'C', verdict: c, blocking: [] }] })
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [W3('accept', 'accept', 'return')] })
ok(r.res.ok === true && /9-a@/.test(asmP(2)) && /9-b@/.test(asmP(2)) && !/9-c@/.test(asmP(2)) && by(r.calls, c => c.label === 'mech:cascade') === 1, 'рецензент волны вернул C — пересведение без C, A и B влиты', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => c.agentType === 'wave-reviewer') === 2 && /git diff /.test(prm(r.calls, 'review-wave-2')), 'после снятия полосы — проверка исполнения по дельте сборок, не второй полный круг')
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [W3('return', 'accept', 'accept')] })
ok(r.res.ok === true && /9-c@/.test(asmP(2)) && !/9-a@/.test(asmP(2)) && !/9-b@/.test(asmP(2)), 'возврат A снимает и зависимую B, C влита', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [{ verdict: 'return', blocking: ['x'] }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:autoland') === 0, 'близнец: возврат без разбивки по полосам — факта нет, вливания нет')

console.log('== landing-reviewer — только за недостающим фактом (ws#999)')
const argsM = { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }
r = await run({ args: argsM, plan: [P('r2.json')] })
ok(r.res.ok === true && by(r.calls, c => c.agentType === 'landing-reviewer') === 0 && /ПРАВИЛО ВЛИВАНИЯ/.test(prm(r.calls, 'mech:autoland')), 'R2, факты полны (CI, ревью на голове, предпроверка 0) — вливает правило, landing-reviewer не зван', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: { ...argsM, lanes: [{ ...argsM.lanes[0], publicText: true }] }, plan: [P('r2.json')] })
ok(r.res.ok === true && by(r.calls, c => c.agentType === 'landing-reviewer') === 1, 'публичный текст полосы — факта нет, landing-reviewer зван')
r = await run({ args: argsM, plan: [P('r2.json')], al: [{ code: 5, out: 'head-moved ' + 'f'.repeat(40) + ' ' + 'd'.repeat(40) }] })
ok(r.res.ok === false && by(r.calls, c => c.agentType === 'landing-reviewer') === 0 && /: head-moved /.test(r.res.stage || ''), 'голова сдвинута после вердиктов — судит демон (head-moved), не landing-reviewer; вливания нет', JSON.stringify(r.res).slice(0, 200))

console.log('== приёмка check-verifier ws#1000 r1: CV-M2…CV-M9, CV-EMPTY')
{
const asmQ = n => prm(r.calls, 'mech:assemble:' + n)
const merges = () => by(r.calls, c => c.label === 'mech:cascade')
r = await run({ args: { ...argsM, lanes: [{ ...argsM.lanes[0], publicText: false }] }, plan: [P('r2.json')] })
ok(r.res.ok === true && by(r.calls, c => c.agentType === 'landing-reviewer') === 0, 'CV-M2: publicText=false, факты полны — landing-reviewer не зван')
r = await run({ args: { ...argsM, lanes: [{ ...argsM.lanes[0], publicText: true }] }, plan: [P('r2.json')], asm: [{ head: 'd'.repeat(40) }], ci: [{ code: 0, head: 'd'.repeat(40) }] })
ok(r.res.ok === false && merges() === 0 && by(r.calls, c => c.label === 'mech:autoland') === 0 && /другой sha/.test(r.res.stage || ''), 'CV-M3: landing-reviewer принял другую sha — демон не стартует', JSON.stringify(r.res).slice(0, 200))
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [{ verdict: 'accept', blocking: [], lanes: [{ key: 'A', verdict: 'accept', blocking: [] }, { key: 'B', verdict: 'accept', blocking: [] }, { key: 'C', verdict: 'return', blocking: ['x'] }] }] })
ok(r.res.ok === false && merges() === 0, 'CV-M4: свод accept при возврате C — противоречие, вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [W3('return', 'return', 'return')] })
ok(r.res.ok === false && merges() === 0 && by(r.calls, c => c.label === 'mech:assemble:2') === 0, 'CV-M5: возвращены все полосы — пересведения и вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [{ verdict: 'return', blocking: ['x'], lanes: [{ key: 'C', verdict: 'return', blocking: ['x'] }] }] })
ok(r.res.ok === false && merges() === 0, 'CV-M6: разбивка неполная (только C) — факта по A,B нет, вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args: argsDepM, plan: [P('r2dep.json')], wave: [{ verdict: 'return', blocking: ['x'], lanes: [{ key: 'A', verdict: 'accept', blocking: [] }, { key: 'M', verdict: 'return', blocking: ['x'] }] }] })
ok(r.res.ok === true && /9-a@/.test(asmQ(2)) && !/9-m@|M@/.test(asmQ(2)) && merges() === 1 && (r.res.landed || []).join() === 'A', 'CV-M9: R2, рецензент волны вернул M — A сведена и влита', JSON.stringify(r.res).slice(0, 200) + ' ASM2=' + asmQ(2).slice(0, 300))
}
r = await run({ args: argsDep, plan: [P('r1.json')], wave: [{ verdict: 'return', blocking: ['x'], lanes: [{ key: 'A', verdict: 'return', blocking: ['x'] }, { key: 'B', verdict: 'accept', blocking: [] }] }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:autoland') === 0 && !(r.res.landed || []).length, 'CV-EMPTY: возврат A при B←A снимает обе — сборка пуста, вливания нет', JSON.stringify(r.res).slice(0, 260) + ' ASM2=' + prm(r.calls, 'mech:assemble:2').slice(0, 260))

r = await run({ args: argsABC, plan: [P('r1c.json')], wave: [W3('accept', 'accept', 'accept')] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:autoland') === 0 && by(r.calls, c => c.label === 'mech:assemble:2') === 0, 'CV-R2: свод return при accept у каждой полосы — противоречие, пересведения и вливания нет', JSON.stringify(r.res).slice(0, 200))

console.log('== «идёт» после ожидания — состояние, а не провал')
const CIR = +((body.match(/const CI_READS = (\d+)/) || [])[1] || 0)
const CIP = +((body.match(/const CI_PAUSE_S = (\d+)/) || [])[1] || 0)
r = await run({ args, plan: [P('r0.json')], ci: Array(CIR).fill({ code: 3 }) })
ok(CIR >= 1 && r.res.ok === false && r.res.state === 'running' && r.res.pr === 7 && by(r.calls, c => c.label.startsWith('mech:ci:')) === CIR && by(r.calls, c => c.label.startsWith('mech:autoland')) === 0 && by(r.calls, c => c.label.startsWith('mech:err:')) === 0, 'CI идёт все ' + CIR + ' чтений — state running, ошибки и вливания нет', JSON.stringify(r.res).slice(0, 200))

console.log('== агент не ждёт (ws#1001): срок шага и CI — короткими чтениями шаблона')
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, { code: 3 }, { code: 0 }] })
ok(r.calls.length > 0 && r.calls.every(c => /НЕ ЖДИ/.test(c.prompt) && /СРОК ШАГА/.test(c.prompt)), 'каждое задание несёт норму «НЕ ЖДИ» и срок шага', r.calls.filter(c => !/НЕ ЖДИ/.test(c.prompt) || !/СРОК ШАГА/.test(c.prompt)).map(c => c.label).join(','))
// ws#1008, ws#1152: вливание — только демоном (он — gh pr merge --match-head-commit); изменяющий gh api запрещён в общем задании.
const MERGE_NORM = /ВЛИВАНИЕ \(ws#1008, ws#1152\): только демоном `scripts\/autoland\/autoland\.sh` \(start, затем один шаг status; вливает он `gh pr merge <PR> --merge --match-head-commit <sha>`\); `gh api repos\/\*\/merges`, `gh api …\/pulls\/\*\/merge` и `gh pr merge --auto` запрещены\. `gh api` — только GET: merge-base — `gh api repos\/<o>\/<r>\/compare\/<base>\.\.\.<head> --jq \.merge_base_commit\.sha`/
ok(r.calls.length > 0 && r.calls.every(c => MERGE_NORM.test(c.prompt)), 'каждое задание несёт правило вливания и «gh api — только GET» с чтением merge-base', r.calls.filter(c => !MERGE_NORM.test(c.prompt)).map(c => c.label).join(','))
const mp = prm(r.calls, 'mech:autoland')
ok(/`bash \/ws\/scripts\/autoland\/autoland\.sh start --repo PRO-Robotech\/kacho-workspace --pr 7 --head f{40} --subject "[^"`]+" --stand-report \S+ --stand-expect \S+`/.test(mp) && !/--squash|--rebase|--no-ff|--auto|--admin/.test(mp.split('\n\n').slice(1).join(' ')), 'вливает демон: start со сверкой головы (--head), без локального --no-ff, сквоша и --auto', mp.slice(-600))
// ws#1029: тема вливания — по форме правила ветки `#<N> merge #<M>: …`; база main — номер волны.
ok(/--subject "#9 merge #7: волна 9"/.test(mp), 'тема вливания при базе main — «#<волна> merge #<PR>: …»', mp.slice(0, 400))
{
  const rn = await run({ args: { ...args, epic: '296', base: '296' }, plan: [P('r0.json')] })
  const mpn = prm(rn.calls, 'mech:autoland')
  ok(/--subject "#296 merge #7: волна 9"/.test(mpn), 'тема вливания в эпик-номер — «#<эпик> merge #<PR>: …»', mpn.slice(0, 400))
}
// ws#1036: отсоединённый прогон — без nohup (глушит SIGHUP детям), код — в .rc.
ok(r.calls.length > 0 && r.calls.every(c => /setsid env --default-signal=PIPE sh -c '<команда>; echo \$\? > <журнал>\.rc'/.test(c.prompt) && !/setsid nohup/.test(c.prompt)), 'каждое задание даёт форму setsid env --default-signal=PIPE с кодом в .rc и не предписывает nohup', r.calls.filter(c => !/default-signal=PIPE/.test(c.prompt) || /setsid nohup/.test(c.prompt)).map(c => c.label).join(','))
// ws#1036 (ai-tooling.md#at-lane-retro): урок полосы — полем схемы, в один файл волны, в итоге волны.
{
  const rl = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'done', head: H('A', 1), lesson: 'nohup в отправке · CLAUDE.md «Не жди»' }], 'impl:B': [{ status: 'done', head: H('B', 1), lesson: '—' }] })
  const ia = rl.calls.find(c => c.label === 'impl:A')
  const sch = ia && ia.schema
  ok(!!sch && sch.properties && sch.properties.lesson && (sch.required || []).includes('lesson'), 'схема исполнителя требует поле lesson', JSON.stringify(sch && sch.required))
  ok(!!ia && ia.prompt.includes('>> /ws/tmp/wave-9/reports/lessons.md') && /урока нет — «—», в файл не пиши/.test(ia.prompt), 'задание исполнителя: урок — строкой в reports/lessons.md, «—» — без записи', ia ? ia.prompt.slice(-700) : '')
  const L = rl.res.lessons || {}
  ok(L.file === '/ws/tmp/wave-9/reports/lessons.md' && (L.items || []).length === 1 && L.items[0].key === 'A' && /nohup в отправке/.test(L.items[0].lesson), 'итог волны несёт файл уроков и уроки полос; «—» уроком не считается', JSON.stringify(rl.res.lessons))
  const rf = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'failed', head: H('A', 1), lesson: 'ложный отказ гейта · lane-precheck' }], 'impl:B': [{ status: 'failed', head: H('B', 1), lesson: '—' }] })
  ok(rf.res.ok === false && ((rf.res.lessons || {}).items || []).length === 1, 'урок не теряется, когда волна стала на полосах', JSON.stringify(rf.res).slice(0, 300))
}
ok(r.calls.filter(c => c.label.startsWith('impl:')).every(c => /СРОК ШАГА: \d+ мин/.test(c.prompt.split('\n\n').slice(1).join(' '))), 'задание исполнителя — со своим сроком шага')
const cis = r.calls.filter(c => c.label.startsWith('mech:ci:'))
// Закрытый мир, а не словарь запретных слов (опыт check-verifier по #1002: «--watch
// до окончания» и «повторяй каждые 60 с» прошли мимо /подожди|until|while/):
// указание CI-чтения сверяется ЦЕЛИКОМ с единственной законной редакцией —
// любое иное слово об ожидании меняет текст и краснеет. Числа (CI_READS,
// CI_PAUSE_S, срок шага ci) берутся из шаблона: их смена — близнец, а не мутант.
const CIS = +((body.match(/const STEP_MIN = \{[^}]*\bci: (\d+)/) || [])[1] || 0)
// Команда между обратными кавычками — рецепт «ЗАПУСК» с ci-read.sh (её свойства
// судит сценарий «CI — только кодом ci-read.sh»); указание вокруг неё — закрытый мир.
const ciWant = i => 'Режим CI, чтение ' + (i + 1) + ' из ' + CIR + ': ' + args.repo + ' PR #7, голова ' + HW + '. ' + (i ? 'Пауза и чтение — ОДНА команда, исполни её целиком, не деля: `s0=$(date +%s); sleep ' + CIP + '; echo "SLEPT $(( $(date +%s) - s0 ))"; ' : 'Прочти вердикт ОДИН раз командой: `')
// Срок чтения с паузой — срок CI-шага плюс длина паузы в минутах (ws#1010).
const ciWant2 = i => '` (scripts/ci-read.sh рецептом «ЗАПУСК»; `gh pr checks` и check-runs мимо скрипта не читай, без --watch, без цикла); code — код этой команды: 0 green · 1 red · 2 не прочитано · 3 идёт или набор неполон · 4 база устарела · 5 целевой зелёный черновика (не основание вливать); код не толкуй, идёт — сразу верни: повтор делает шаблон. СРОК ШАГА: ' + (CIS + (i ? Math.ceil(CIP / 60) : 0)) + ' мин; истёк — верни исход с остатком (сделано / не сделано), а не жди. Отчёт — '
const ciGot = c => c.prompt.split('\n\n').slice(1).join(' ')
const ciCut = (g, i) => { if (!g.startsWith(ciWant(i))) return null; const k = g.indexOf(' 2>&1` (', ciWant(i).length); return k < 0 ? null : g.slice(k + ' 2>&1'.length) }
const ciBad = cis.map((c, i) => { const t = ciCut(ciGot(c), i); return t !== null && t.startsWith(ciWant2(i)) ? '' : 'чтение ' + (i + 1) + ': ' + ciGot(c).slice(0, 220) }).filter(Boolean)
ok(cis.length === 3 && CIS >= 1 && CIS <= 10 && ciBad.length === 0, 'чтение CI — одно, без ожидания агентом; повтор — шаблоном (указание сверено целиком)', 'срок ci ' + CIS + '; ' + ciBad.join(' | '))
ok(CIP > 0 && CIP <= 300 && cis.length > 0 && !/sleep/.test(cis[0].prompt.split('\n\n').slice(1).join(' ')) && cis.slice(1).every(c => c.prompt.includes('sleep ' + CIP)), 'пауза между чтениями — одна команда ≤ 300 с, у первого чтения паузы нет', 'CI_PAUSE_S=' + CIP)
console.log('== пауза CI — тем же агентом и с фактом slept (ws#1010)')
const ownP = c => c.prompt.split('\n\n').slice(1).join(' ')
ok(r.calls.filter(c => !c.label.startsWith('mech:ci:') && /`[^`]*\bsleep \d/.test(ownP(c))).length === 0, 'паузу не делает отдельный агент: sleep — только в команде чтения CI', r.calls.filter(c => !c.label.startsWith('mech:ci:') && /`[^`]*\bsleep \d/.test(ownP(c))).map(c => c.label).join(','))
ok(cis.length === 3 && cis.slice(1).every(c => /`s0=\$\(date \+%s\); sleep \d+; echo "SLEPT [^`]*ci-read\.sh/.test(ownP(c))), 'пауза, строка SLEPT и ci-read.sh — одна команда в обратных кавычках', ownP(cis[1] || { prompt: '' }).slice(0, 300))
ok(cis.length === 3 && cis.every(c => ((c.schema || {}).required || []).includes('slept') && (((c.schema || {}).properties || {}).slept || {}).type === 'number'), 'схема чтения CI требует slept числом', JSON.stringify((cis[0] || {}).schema || {}).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, { code: 0, slept: 5 }, { code: 0 }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 3 && r.calls.some(c => c.label === 'mech:err:wave' && /пауза CI не исполнена в 1/.test(c.prompt)), 'чтение с паузой при slept 5 — отвергнуто (даже зелёное), повтор; строка счётчика executor-mechanics', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, { code: 0, slept: undefined }, { code: 0, slept: String(CIP) }, { code: 0 }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 4, 'slept нет или не число — чтение отвергнуто', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, ...Array(CIR - 1).fill({ code: 0, slept: 0 })] })
ok(r.res.ok === false && r.res.state === 'running' && r.res.pauseSkipped === CIR - 1 && by(r.calls, c => c.label === 'mech:autoland') === 0, 'пауза не исполнена ни разу — не вливается, итог называет отвергнутые чтения', JSON.stringify(r.res).slice(0, 260))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 3 }, { code: 0, slept: CIP - 10 }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 2 && !r.calls.some(c => c.label === 'mech:err:wave'), 'близнец: slept = N−10 — чтение принято, строки счётчика нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 0, slept: 0 }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 1, 'близнец: первое чтение без паузы, slept 0 — принято')

console.log('== каталог волны — под корнем воркспейса (ws#1010)')
const wsCopy = '/ws/tmp/wave7/ws-main'
r = await run({ args: { ...args, ws: wsCopy }, plan: [P('r0.json')] })
ok(r.res.ok === true && r.calls.every(c => !c.prompt.includes(wsCopy + '/tmp/')) && prm(r.calls, 'impl:A').includes('копия — /ws/tmp/wave-9/A/copy') && prm(r.calls, 'mech:plan:1').includes('/ws/tmp/wave-9/plan-1.json'), 'ws — копия под /ws/tmp/: каталог волны и копии полос — /ws/tmp/wave-9, ни одного пути под tmp/ копии', r.calls.filter(c => c.prompt.includes(wsCopy + '/tmp/')).map(c => c.label).join(','))
ok(r.calls.every(c => c.prompt.includes('KACHO_HOME_KACHO=/ws/project/kacho ')), 'рабочие копии продукта — корня воркспейса, а не копии')
r = await run({ args: { ...args, ws: wsCopy, root: '/r' }, plan: [P('r0.json')] })
ok(r.res.ok === true && prm(r.calls, 'impl:A').includes('копия — /r/tmp/wave-9/A/copy') && r.calls.every(c => !/\/ws\/tmp\/wave-9/.test(c.prompt)), 'args.root задан — каталог волны /r/tmp/wave-9')
r = await run({ args, plan: [P('r0.json')] })
ok(prm(r.calls, 'impl:A').includes('копия — /ws/tmp/wave-9/A/copy') && prm(r.calls, 'mech:stack:A') === '' && /Копии — только под \/ws\/tmp\/wave-9\/ \(/.test(r.calls[0].prompt.split('\n\n')[0]), 'близнец: ws — сам корень — /ws/tmp/wave-9', r.calls[0].prompt.split('\n\n')[0].slice(0, 400))
r = await run({ args, plan: [P('r0.json')], 'pre:A': [{ code: 1, reasons: ['GOMOD-ABOVE'] }] })
ok(r.calls.some(c => c.label === 'mech:err:A' && /executor-mechanics/.test(c.prompt)), 'GOMOD-ABOVE предпроверки — механика исполнителя (копия не там), строка счётчика')

r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'go-implementer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')] })
const revs = r.calls.filter(c => /^(review-|acceptance-review-)/.test(c.label) && c.label !== 'review-wave' && c.label !== 'review-landing')
ok(revs.length > 0 && revs.every(c => /СРОК ШАГА: \d+ мин/.test(c.prompt.split('\n\n').slice(1).join(' '))), 'задание ревью — со своим сроком шага', 'ревью ' + revs.length)
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 1 }] })
ok(r.res.ok === false && r.res.state === 'failed', 'близнец: CI красный — state failed')

console.log('== CI — только кодом ci-read.sh (ws#1006)')
r = await run({ args, plan: [P('r0.json')] })
const ciCalls = r.calls.filter(c => c.label.startsWith('mech:ci'))
ok(ciCalls.length === 1 && ciCalls.every(c => c.prompt.includes('S=ci-read.sh') && c.prompt.includes(args.repo + ' 7 )') && !/S=landing-precheck\.sh/.test(c.prompt)), 'чтение CI сборки — рецептом «ЗАПУСК» c ci-read.sh на PR сборки; на голове посадки шаблон CI не читает (демон)', ciCalls.map(c => c.label).join(','))
ok(/ci-read\.sh код 0 на этой голове/.test(prm(r.calls, 'mech:autoland')) && /ради вливания нельзя ждать CI, нельзя читать ci-read, нельзя гнать три гейта/.test(prm(r.calls, 'mech:autoland')), 'правило вливания: CI судит демон (ci-read код 0 на голове), вручную — нельзя')
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 4, reasons: ['BASE-STALE'] }] })
ok(r.res.ok === false && r.res.state === 'failed' && /база устарела/.test(r.res.stage || '') && by(r.calls, c => c.label.startsWith('mech:ci:')) === 1 && by(r.calls, c => c.label.startsWith('mech:autoland')) === 0, 'код 4 — база устарела: не ждать, не вливать, стадия называет причину', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 2 }] })
ok(r.res.ok === false && r.res.state === 'failed' && by(r.calls, c => c.label === 'mech:autoland') === 0, 'код 2 — не прочитано: не зелёное, вливания нет')
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 7 }] })
ok(r.res.ok === false && r.res.state === 'failed' && by(r.calls, c => c.label.startsWith('mech:ci:')) === 1, 'неизвестный код — unread, не повтор и не зелёное')
r = await run({ args, plan: [P('r0.json')], ci: [{ code: 0, state: 'green', head: 'a'.repeat(40) }] })
ok(r.res.ok === false && r.res.state === 'failed' && by(r.calls, c => c.label === 'mech:autoland') === 0, 'код 0 на другой голове — не вердикт сборки')
r = await run({ args, plan: [P('r0.json')], al: [{ code: 6, out: 'timeout предел 10800 с; последнее: ci-read код 3' }] })
ok(r.res.ok === false && r.res.state === 'failed' && /^autoland[^:]*: timeout предел 10800 с; последнее: ci-read код 3$/.test(r.res.stage || '') && by(r.calls, c => c.label === 'mech:cascade') === 0, 'timeout демона (status 6) — failed с последним вердиктом, вливания нет', JSON.stringify(r.res).slice(0, 200))

console.log('== пустые ходы (ws#1004): разбор плана, чужие файлы, hookLog — путь')
const CENSUS = 'CENSUS\tплан /ws/tmp/wave-9/plan-1.json: полос 2, слоёв 1\nCENSUS\tcorelib: полос kacho и kaname нет — не судился\nVERDICT\tplan-ok\tпричин 0\n'
r = await run({ args, plan: [P('r0.json')], planPrefix: CENSUS })
ok(r.res.ok === true, 'вывод плана со строками CENSUS перед JSON — разобран (parseJsonTail), волна влита', JSON.stringify(r.res).slice(0, 200))
ok(/ТОЛЬКО последняя строка \.out\.json/.test(prm(r.calls, 'mech:plan:1')), 'задание плана просит только последнюю строку вывода', prm(r.calls, 'mech:plan:1').slice(-300))
r = await run({ args, plan: [P('r0.json')], planOut: JSON.stringify(P('r0.json'), null, 2) })
ok(r.res.ok === true, 'близнец: многострочный JSON целиком — разобран', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], planOut: CENSUS + 'готово' })
ok(r.res.ok === false && r.res.stage === 'план' && /не разобран/.test(r.res.why || '') && by(r.calls, c => c.label.startsWith('impl:')) === 0, 'последняя строка не JSON — остановка «не разобран», исполнители не званы', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], planOut: JSON.stringify(P('r0.json')) + '\nCENSUS\tхвост' })
ok(r.res.ok === false && r.res.stage === 'план', 'близнец: JSON не в последней строке — не разобран (берётся хвост, а не первый попавшийся объект)', JSON.stringify(r.res).slice(0, 200))
const argsP = { ...args, lanes: [{ ...lanes2[0], paths: ['docs/a.md', 'docs/a2.md'] }, { ...lanes2[1], paths: ['docs/b.md'] }] }
r = await run({ args: argsP, plan: [P('r0.json')] })
ok(r.calls.length > 0 && r.calls.every(c => /ФАЙЛЫ ПОЛОСЫ: файл вне твоего перечня, которого нет в перечне соседних полос, — бери сам и назови в отчёте; blocked — только если нужен файл соседа/.test(c.prompt.split('\n\n')[0])), 'правило о чужих файлах — в общей преамбуле каждого задания')
const iPA = prm(r.calls, 'impl:A'), iPB = prm(r.calls, 'impl:B')
const own = x => x.split('\n\n').slice(1).join(' ')
ok(/ФАЙЛЫ ПОЛОСЫ/.test(own(iPA)) && own(iPA).includes('Перечни соседей: B: docs/b.md') && own(iPA).includes('Твой перечень: docs/a.md, docs/a2.md') && !own(iPA).includes('A: docs/a.md'), 'исполнителю A — правило и перечень соседа B, своего перечня среди соседей нет', own(iPA).slice(0, 500))
ok(own(iPB).includes('Перечни соседей: A: docs/a.md, docs/a2.md') && !own(iPB).includes('B: docs/b.md'), 'исполнителю B — перечень соседа A', own(iPB).slice(0, 500))
r = await run({ args: { ...args, lanes: [{ ...lanes2[0], paths: ['docs/a.md'] }] }, plan: [P('r0.json')] })
ok(own(prm(r.calls, 'impl:A')).includes('Перечни соседей: соседей нет'), 'близнец: полоса одна — «соседей нет», а не пустая строка')
r = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'done', head: H('A', 1), hookLog: 'зелёный, отказов 0' }] })
const iAs = r.calls.filter(c => c.label === 'impl:A')
ok(r.res.ok === true && iAs.length === 2 && /hookLog «зелёный, отказов 0» — не путь/.test(iAs[1].prompt) && !/зелёный, отказов 0/.test(prm(r.calls, 'mech:precheck:A')) && prm(r.calls, 'mech:precheck:A').includes('--hook-log /ws/tmp/push.log'), 'hookLog не путь — доводка исполнителя, предпроверка получает путь', JSON.stringify(iAs.map(c => c.prompt.slice(-200))))
ok(/hookLog \(ПУТЬ к журналу отправки/.test(iAs[0].prompt) && /report \(содержательный итог/.test(iAs[0].prompt), 'задание исполнителя: hookLog — путь, report — содержательный итог')
r = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'done', head: H('A', 1), hookLog: 'ok' }, { status: 'done', head: H('A', 2), hookLog: '' }] })
ok(inRest(r.res, 'A') && /hookLog не путь/.test(((r.res.remainder || []).find(x => x.key === 'A') || {}).stage || '') && by(r.calls, c => c.label === 'mech:precheck:A') === 0 && asmHas(r.calls, '9-b'), 'hookLog не путь и после доводки — A стоит с причиной, предпроверки вслепую нет, B садится', JSON.stringify(r.res).slice(0, 300))
r = await run({ args, plan: [P('r0.json')] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'impl:A') === 1, 'близнец: hookLog — путь, доводки нет')

console.log('== модель не задаётся; уроки волны 7 (ws#1016)')
{
  const all = []
  for (const x of [{ args, plan: [P('r0.json')] }, { args: argsDep, plan: [P('r1.json')] }, { args: argsM, plan: [P('r2.json')] }]) all.push(...(await run(x)).calls)
  const withModel = all.filter(c => c.model !== undefined)
  ok(all.length > 0 && all.some(c => REVIEWERS.includes(c.agentType)) && all.some(c => c.label.startsWith('impl:')) && withModel.length === 0, 'модель не задана ни у одного шага R0/R1/R2 (наследуется) — haiku нет нигде; шагов ' + all.length, withModel.map(c => c.label + ':' + c.model).join(',').slice(0, 200))
}
r = await run({ args, plan: [P('r0.json')] })
const lane7 = r.calls.filter(c => /\/ws\/tmp\/wave-9\/[A-Z]+\/[A-Za-z0-9-]+\.(md|log)\b/.test(c.prompt)).map(c => c.label)
ok(r.res.ok === true && prm(r.calls, 'impl:A').includes('Отчёт — /ws/tmp/wave-9/reports/A/implement.md') && prm(r.calls, 'impl:A').includes('} > /ws/tmp/wave-9/reports/A/push.log`') && prm(r.calls, 'mech:precheck:A').includes('> /ws/tmp/wave-9/reports/A/lane-precheck.md 2>&1') && lane7.length === 0, 'отчёты и журнал отправки полосы — под /ws/tmp/wave-9/reports/A/, ни одного файла в каталоге полосы рядом с копией', lane7.join(','))
ok(r.calls.every(c => c.prompt.split('\n\n')[0].includes('Отчёты и журналы полос — только под /ws/tmp/wave-9/reports/, ВНЕ дерева копии')), 'преамбула каждого задания: отчёты и журналы — вне дерева копии')
ok(prm(r.calls, 'mech:precheck:A').includes('`LANE_PRECHECK_WS=/ws bash /ws/scripts/lane-precheck.sh /ws/tmp/c-A '), 'lane-precheck — с LANE_PRECHECK_WS=<корень>', prm(r.calls, 'mech:precheck:A').slice(-400))
ok(!/npm ci/.test(prm(r.calls, 'mech:assemble:1')), 'близнец: сборка воркспейса — без npm ci консоли')
r = await run({ args: { ...args, ws: '/ws/tmp/wave7/ws-main' }, plan: [P('r0.json')] })
ok(prm(r.calls, 'mech:precheck:A').includes('`LANE_PRECHECK_WS=/ws bash /ws/tmp/wave7/ws-main/scripts/lane-precheck.sh '), 'ws — копия: LANE_PRECHECK_WS — корень воркспейса, а не копия шаблона', prm(r.calls, 'mech:precheck:A').slice(-400))
r = await run({ args: { ...args, repo: 'PRO-Robotech/kacho', lanes: kcLanes }, plan: [P('kc.json')] })
const asmK = prm(r.calls, 'mech:assemble:1')
ok(r.res.ok === true && asmK.includes('(cd ui-future && npm ci && for p in $(sed -n') && asmK.includes('../.github/workflows/ui.yml); do npm ci --prefix "$p"; done)') && asmK.indexOf('npm ci') < asmK.indexOf('Отправь ветку волны'), 'сборка kacho: npm ci в ui-future и в пакетах STANDALONE из ui.yml — до отправки и проверок', asmK.slice(0, 600))
r = await run({ args: { ...args, repo: 'PRO-Robotech/kaname', base: '296', epic: '296', lanes: knLanes }, plan: [P('kn.json')] })
ok(!/npm ci/.test(prm(r.calls, 'mech:assemble:1')), 'близнец: сборка kaname — без npm ci консоли')

console.log('== волна одним проходом (ws#1053): предполёт, карта влияния, пробная сборка, метрики')
{
  const MAP = { A: ['tests/newman/x.json — утверждает поле → поправить кейс', 'deploy/seed.sh — посев стенда → поправить посев'] }
  let q = await run({ args, plan: [P('r0.json')], map: MAP, 'impl:A': [{ status: 'done', head: H('A', 1), impact: ['1 → правка tests/newman/x.json', '2 → не затронуто — потому что посев поле не пишет'] }] })
  const iPre = idx(q.calls, 'preflight'), iImpl = q.calls.findIndex(c => c.label.startsWith('impl:'))
  const pp = prm(q.calls, 'preflight')
  ok(q.res.ok === true && by(q.calls, c => c.label === 'preflight') === 1 && iPre >= 0 && iPre < iImpl && (q.calls[iPre] || {}).agentType === 'scout', 'предполёт — один scout на волну, до первого исполнителя', JSON.stringify(q.res).slice(0, 200))
  ok(['посевы стенда', 'кейсы newman', 'живы ли держатели', 'копии каталога прав в другом репозитории', 'сквозные пробы консоли', 'документация и приёмки', 'записи ревью и их гейты', 'профили и чарты', 'docs/changes/policy.yaml', 'его полоса идёт в ЭТУ волну', 'пин — на ревизию производителя с опубликованным образом', 'Пункт чужого класса (консоль — ui-implementer)', 'КЛЮЧИ ПОЛОС: A,B', '/ws/tmp/wave-9/reports/preflight.md'].every(f => pp.includes(f)), 'задание предполёта: все классы зависимых, критерии по policy.yaml, зависимый другого репозитория — в эту волну', pp.slice(0, 300))
  const ia = prm(q.calls, 'impl:A'), ib = prm(q.calls, 'impl:B')
  ok(ia.includes('1) tests/newman/x.json — утверждает поле → поправить кейс; 2) deploy/seed.sh') && ia.includes('полоса с незакрытым пунктом не сдаётся') && ia.includes('Критерии рецензентов: критерий A') && !ib.includes('tests/newman/x.json') && ib.includes('пунктов нет'), 'задание полосы несёт СВОЮ карту и критерии, чужих пунктов нет', ia.slice(0, 200))
  ok(by(q.calls, c => c.label === 'impl:A') === 1, 'пункты карты закрыты — доводки нет')
  ok(((q.calls.find(c => c.label === 'impl:A') || {}).schema?.required || []).includes('impact'), 'impact обязателен в схеме исполнителя')
  const iT = idx(q.calls, 'mech:trial:A'), iP = idx(q.calls, 'mech:precheck:A'), iAsm = idx(q.calls, 'mech:assemble:1')
  ok(iT > iP && iT < iAsm && idx(q.calls, 'mech:trial:B') >= 0 && /git push --dry-run origin HEAD:refs\/heads\/9-a`/.test(prm(q.calls, 'mech:trial:A')), 'пробная сборка — сразу после предпроверки полосы, до сборки; хук отправки судит сведённое (--dry-run на ветку полосы)', prm(q.calls, 'mech:trial:A').slice(-300))
  const mt = prm(q.calls, 'mech:metrics')
  ok(by(q.calls, c => c.label === 'mech:metrics') === 1 && q.calls[q.calls.length - 1].label === 'mech:metrics' && mt.includes('/ws/tmp/wave-9/reports/metrics.json') && q.res.metrics?.preflightItems === 2 && q.res.metrics?.implCalls === 2 && q.res.metrics?.rework === 0, 'метрики — последним шагом в reports/metrics.json; пунктов карты 2, вызовов исполнителя 2, переделок 0', JSON.stringify(q.res.metrics))
  ok(prm(q.calls, 'mech:cascade').includes('КРОМЕ держателей записей ведомостей'), 'каскад не закрывает держателя записи ведомости')
  // незакрытый пункт: одна доводка, снова незакрыт — полоса стоит, сосед садится
  q = await run({ args, plan: [P('r0.json')], map: MAP, 'impl:A': [{ status: 'done', head: H('A', 1), impact: ['1 → правка tests/newman/x.json'] }, { status: 'done', head: H('A', 2), impact: ['1 → правка tests/newman/x.json', '2 → посмотрю потом'] }] })
  ok(q.res.ok === true && by(q.calls, c => c.label === 'impl:A') === 2 && prm(q.calls, 'impl:A').length > 0 && q.calls.filter(c => c.label === 'impl:A')[1].prompt.includes('КАРТА ВЛИЯНИЯ: пункты 2 не закрыты') && inRest(q.res, 'A') && /карта влияния: пункты 2 не закрыты и после доводки/.test(((q.res.remainder || []).find(x => x.key === 'A') || {}).stage || '') && by(q.calls, c => c.label === 'mech:precheck:A') === 0 && !asmHas(q.calls, '9-a') && asmHas(q.calls, '9-b') && q.res.metrics?.rework === 1, 'пункт карты не закрыт и после доводки — полоса стоит до предпроверки, сосед садится', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args, plan: [P('r0.json')], map: MAP, 'impl:A': [{ status: 'done', head: H('A', 1), impact: [] }, { status: 'done', head: H('A', 2), impact: ['1 -> правка tests/newman/x.json', '2 → не затронуто — потому что посев поле не пишет'] }] })
  ok(q.res.ok === true && by(q.calls, c => c.label === 'impl:A') === 2 && !inRest(q.res, 'A'), 'близнец: доводка закрыла пункты (и форма «->») — полоса идёт', JSON.stringify(q.res).slice(0, 200))
  // предполёт без ответа либо без карты полосы — раздачи нет
  q = await run({ args, plan: [P('r0.json')], pre: ['отчёт записан'] })
  ok(q.res.ok === false && /предполёт/.test(q.res.stage || '') && by(q.calls, c => c.label.startsWith('impl:')) === 0 && by(q.calls, c => c.label === 'mech:metrics') === 1, 'предполёт без ответа — раздачи нет, метрики всё равно записаны', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args, plan: [P('r0.json')], pre: [{ lanes: [{ key: 'A', impact: [], criteria: [] }], estimate: 'e', report: 'r' }] })
  ok(q.res.ok === false && /по полосам B/.test(q.res.stage || '') && by(q.calls, c => c.label.startsWith('impl:')) === 0, 'карты нет по одной полосе — раздачи нет, полоса названа', JSON.stringify(q.res).slice(0, 200))
  // пробная сборка красная — полоса в остаток, сосед садится, счёт красных на сведённом
  q = await run({ args, plan: [P('r0.json')], 'trial:A': [{ code: 1, reasons: ['newman: ф13-25'] }] })
  ok(q.res.ok === true && inRest(q.res, 'A') && /пробная сборка: красное на сведённом — newman: ф13-25/.test(((q.res.remainder || []).find(x => x.key === 'A') || {}).stage || '') && !asmHas(q.calls, '9-a') && asmHas(q.calls, '9-b') && q.res.metrics?.trialRed === 1, 'пробная сборка красная — полоса в остаток, сосед садится, trialRed 1', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args, plan: [P('r0.json')], 'trial:A': [{ code: 2, reasons: [] }] })
  ok(q.res.ok === true && !inRest(q.res, 'A') && q.res.metrics?.trialRed === 0, 'близнец: проба не выполнилась (код 2) — не красное, суд за CI', JSON.stringify(q.res).slice(0, 200))
  // CI красный на сведённом — счёт ciRed и метрики на провале
  q = await run({ args, plan: [P('r0.json')], ci: [{ code: 1, reasons: ['x'] }] })
  ok(q.res.ok === false && q.res.metrics?.ciRed === 1 && by(q.calls, c => c.label === 'mech:metrics') === 1, 'красный CI на сведённом — ciRed 1, метрики записаны и на провале', JSON.stringify(q.res.metrics))
  // смена контракта: имитация клиента по замыслу ДО кода
  q = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')] })
  const iSim = idx(q.calls, 'sim:M')
  ok(q.res.ok === true && iSim > idx(q.calls, 'acceptance-review-1:M') && iSim < idx(q.calls, 'impl:M') && (q.calls[iSim] || {}).agentType === 'client-simulator' && prm(q.calls, 'impl:M').includes('имитация клиента до кода — /ws/tmp/wave-9/reports/M/client-sim.md'), 'смена контракта — имитация клиента после приёмки и ДО кода, путь — исполнителю', JSON.stringify(q.res).slice(0, 200))
  ok(by(q.calls, c => c.agentType === 'client-simulator') === 1, 'имитация клиента — один раз на полосу')
}

console.log('== красный CI — одним кругом; после волны — пробное схождение и CI MR эпика (ws#1063)')
const RR_FRAGS = ['перепись ВСЕЙ красноты', 'CI читается по завершении ВСЕХ заданий (ci-read код 3 при красном и идущих)', 'класс корня — лишь после дословной цитаты отказа', 'среда с двумя признаками — один перезапуск без полосы', 'все корни — исполнителям их классов параллельно, ОДНОЙ сборкой', 'проверка — только бывшее красным на внешнем кластере (stand-report.sh --of)', 'всё зелёное — полный прогон на внешнем кластере (stand-report.sh код 0)', 'затем ОДИН CI', 'два красных CI подряд — стоп и разбор паритета']
{
  const argsE = { ...args, epic: '296', base: '296' }
  let q = await run({ args: argsE, plan: [P('r0.json')] })
  const iM = idx(q.calls, 'mech:cascade'), iTc = idx(q.calls, 'trial-convergence'), iEc = idx(q.calls, 'mech:ci-epic')
  const tc = prm(q.calls, 'trial-convergence'), ec = prm(q.calls, 'mech:ci-epic')
  ok(q.res.ok === true && by(q.calls, c => c.label === 'trial-convergence') === 1 && iTc > iM && (q.calls[iTc] || {}).agentType === 'convergence-reviewer' && tc.includes('пересчитай отпечатки пакета') && tc.includes('недостающих записей ролей и событий') && tc.includes('без блока event записи') && tc.includes('/ws/tmp/wave-9/reports/trial-convergence.md') && !!q.res.trialConvergence, 'влитая волна — пробное схождение convergence-reviewer после вливания: отпечатки пакета, недостающие записи ролей и событий', JSON.stringify(q.res).slice(0, 200))
  ok(by(q.calls, c => c.label === 'mech:ci-epic') === 1 && iEc > iM && (q.calls[iEc] || {}).agentType === 'ci-watcher' && ec.includes('--head 296 --base main') && ec.includes('S=ci-read.sh') && ec.includes('без ожидания: код 3 (идёт) — законный исход') && q.res.epicCi && q.res.epicCi.code === 3 && !q.res.epicCi.redRound, 'влитая волна — одно чтение полного CI MR эпика ci-read.sh без ожидания; «идёт» — не красное', ec.slice(-300))
  q = await run({ args: argsE, plan: [P('r0.json')], ciepic: [{ code: 1, reasons: ['newman'] }] })
  ok(q.res.ok === true && q.res.epicCi && /все корни — исполнителям их классов параллельно, ОДНОЙ сборкой/.test(q.res.epicCi.redRound || ''), 'красный CI MR эпика после волны — итог несёт порядок круга', JSON.stringify(q.res.epicCi))
  q = await run({ args: argsE, plan: [P('r0.json')], merge: [{ code: 1, head: '' }] })
  ok(q.res.ok === false && by(q.calls, c => c.label === 'mech:cascade') === 1 && by(q.calls, c => c.label === 'trial-convergence' || c.label === 'mech:ci-epic') === 0, 'вливание не состоялось — схождения и чтения MR эпика нет', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args, plan: [P('r0.json')] })
  ok(q.res.ok === true && by(q.calls, c => c.label === 'trial-convergence' || c.label === 'mech:ci-epic') === 0, 'близнец: волна прямо в main (MR эпика нет) — схождения и чтения MR эпика нет', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args: argsE, plan: [P('r0.json')], ci: [{ code: 1, reasons: ['x'] }] })
  const rr = q.res.redRound || ''
  ok(q.res.ok === false && RR_FRAGS.every(f => rr.includes(f)) && by(q.calls, c => c.label === 'trial-convergence') === 0, 'красный CI сборки — итог несёт порядок «перепись — потом массово» (все задания, цитата до класса, одна сборка, только красное на кластере, полный, один CI)', rr.slice(0, 300))
  q = await run({ args: argsE, plan: [P('r0.json')], al: [{ code: 1, out: 'red ci-read код 1: REASON\tRED\tnewman', reasons: ['RED'] }] })
  ok(q.res.ok === false && /затем ОДИН CI; два красных CI подряд — стоп/.test(q.res.redRound || '') && q.res.metrics?.ciRed === 1, 'красный CI у демона вливания — порядок круга в итоге, ciRed 1', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args: argsE, plan: [P('r0.json')], ci: [{ code: 4, reasons: ['BASE-STALE'] }] })
  ok(q.res.ok === false && q.res.redRound === undefined, 'близнец: база устарела (код 4) — не красное, круга починки нет', JSON.stringify(q.res).slice(0, 200))
}

console.log('== внешний стенд до CI: перепись прогоном, ready и вливание — лишь при коде 0 (ws#1110)')
{
  let q = await run({ args, plan: [P('r1.json')] })
  const iS = idx(q.calls, 'mech:stand:0'), sp = prm(q.calls, 'mech:stand:0')
  ok(q.res.ok === true && iS > idx(q.calls, 'review-wave') && iS < idx(q.calls, 'mech:ci:0') && (q.calls[iS] || {}).agentType === 'ci-watcher' && ['ВНЕШНЕМ кластере', 'теми же целями, что CI', 'без остановки на первом красном', 'stand-report.sh check /ws/tmp/wave-9/stand.json --head ' + HW + ' --expect /ws/tmp/wave-9/stand-expect.json', 'stand-report.sh expect --checkout /ws/tmp/wave-9/assemble --head ' + HW, ' --draft false > /ws/tmp/wave-9/stand-expect.json', 'NO-PR-IMAGES', 'make stand-ns-run NS=t9-w<k>', 'job задания и дословной цитатой у красного'].every(f => sp.includes(f)), 'стенд — шаг ci-watcher после рецензента волны и ДО первого чтения CI: весь набор на внешнем кластере, суд stand-report.sh этой головы', sp.slice(-400))
  ok(prm(q.calls, 'mech:autoland').includes('--stand-report /ws/tmp/wave-9/stand.json --stand-expect /ws/tmp/wave-9/stand-expect.json') && prm(q.calls, 'mech:gates').includes('--stand-report /ws/tmp/wave-9/stand.json --stand-expect /ws/tmp/wave-9/stand-expect.json'), 'посадка судит отчёт стенда снова: демон (его landing-precheck) и перепись — --stand-report')
  q = await run({ args, plan: [P('r0.json')], stand: [{ code: 1, reasons: ['STAND-REPORT-RED'] }] })
  ok(q.res.ok === false && q.res.state === 'failed' && /внешний стенд до CI: красное/.test(q.res.stage || '') && by(q.calls, c => /^mech:(ci:|ready|autoland|cascade)/.test(c.label)) === 0 && RR_FRAGS.every(f => (q.res.redRound || '').includes(f)), 'красный стенд — ни CI, ни ready, ни вливания; итог несёт порядок «перепись — потом массово»', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args, plan: [P('r0.json')], stand: [{ code: 2, reasons: [] }] })
  ok(q.res.ok === false && q.res.state === 'failed' && /не выполнилось/.test(q.res.stage || '') && q.res.redRound === undefined && by(q.calls, c => c.label.startsWith('mech:ci:')) === 0, 'стенд не выполнился — не зелёное и не красное: CI нет, круга починки нет', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args, plan: [P('r0.json')], stand: [{ code: 3 }, { code: 0 }] })
  ok(q.res.ok === true && by(q.calls, c => c.label.startsWith('mech:stand:')) === 2 && /sleep \d+/.test(prm(q.calls, 'mech:stand:1')) && !/sleep/.test(prm(q.calls, 'mech:stand:0').split('\n\n').slice(1).join(' ')), 'стенд идёт — второе чтение с паузой той же командой, затем CI', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args, plan: [P('r0.json')], stand: [{ code: 3 }, { code: 0, slept: 5 }] })
  ok(q.res.ok === true && by(q.calls, c => c.label.startsWith('mech:stand:')) === 3, 'чтение стенда с неисполненной паузой отвергнуто — повтор', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args, plan: [P('r0.json')], stand: Array(40).fill({ code: 3 }) })
  ok(q.res.ok === false && q.res.state === 'running' && by(q.calls, c => c.label.startsWith('mech:ci:')) === 0, 'стенд идёт и после ожидания — state running, CI не читается', JSON.stringify(q.res).slice(0, 200))
}

console.log('== лимит GitHub — не выполнилось со временем сброса, не красное (урок 2026-10-16, ws#1110)')
{
  const RL = { code: 2, reasons: ['RATE-LIMIT'], out: 'REASON\tRATE-LIMIT\tлимит REST: остаток 5 из 5000 < порога 100, сброс в 14:05\nVOID\t…' }
  let q = await run({ args, plan: [P('r0.json')], ci: [RL] })
  ok(q.res.ok === false && q.res.state === 'not-run' && /лимит GitHub исчерпан — не выполнилось, не красное; сброс в 14:05/.test(q.res.stage || '') && by(q.calls, c => /^mech:(autoland|cascade)/.test(c.label)) === 0, 'CI: RATE-LIMIT — state not-run со временем сброса, ни посадки, ни вливания', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args, plan: [P('r0.json')], al: [{ code: 2, out: 'void landing-precheck код 2 3 раз подряд: REASON\tRATE-LIMIT\tсброс в 14:05', reasons: ['RATE-LIMIT'] }] })
  ok(q.res.state === 'not-run' && /сброс в 14:05/.test(q.res.stage || '') && by(q.calls, c => c.label === 'mech:cascade') === 0, 'лимит у демона вливания — not-run, не вливать', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args, plan: [P('r0.json')], ci: [{ code: 2, reasons: [] }] })
  ok(q.res.state === 'failed', 'близнец: код 2 без RATE-LIMIT — прежний failed (unread), не not-run')
  q = await run({ args, plan: [P('r0.json')] })
  ok(/сперва ОДНО чтение `gh api rate_limit` — остаток core либо graphql < 300 — code 2, reasons \['RATE-LIMIT'\]/.test(prm(q.calls, 'mech:gates')), 'перепись гейтов начинается с чтения лимита: ниже 300 — code 2 RATE-LIMIT, гейты не гнать', prm(q.calls, 'mech:gates').slice(0, 200))
}
{
  const q = await run({ args, plan: [P('r1.json')] })
  ok(/heavy-slot\.sh --enqueue \/ws\/tmp\/wave-9 <класс> -- …` \(билет держится/.test(prm(q.calls, 'mech:stand:0')), 'стенд ставится в очередь ОДИН раз: heavy-slot.sh --enqueue, 74/75 повтором не лечится', prm(q.calls, 'mech:stand:0').slice(0, 200))
  ok(q.calls.every(c => /ОДИН раз `heavy-slot\.sh --enqueue <каталог> <класс> -- …`/.test(c.prompt) && /имя журнала и \.rc — уникальное/.test(c.prompt)), 'каждое задание: долгое ожидание — --enqueue один раз, перезапуск запрещён; имя .rc уникальное')
}

console.log('== перепись гейтов посадки разом; ответ без ВОЗВРАТ — не-выполнилось (ws#1071)')
{
  let q = await run({ args, plan: [P('r0.json')] })
  const iG = idx(q.calls, 'mech:gates'), gp = prm(q.calls, 'mech:gates')
  ok(by(q.calls, c => c.label === 'mech:gates') === 1 && iG > idx(q.calls, 'review-wave') && iG < idx(q.calls, 'mech:autoland') && ['landing-precheck.sh', 'merge-readiness.sh', 'ci-read.sh', 'applicability.py обоих пакетов', 'cascade-census.sh --proof', 'branch-audit.sh'].every(f => gp.includes(f)) && gp.includes('ДО первой починки прогони КАЖДЫЙ гейт по разу, ничего не чини') && gp.includes('/ws/tmp/wave-9/reports/gates-census.md') && q.res.gates && q.res.gates.file === '/ws/tmp/wave-9/reports/gates-census.md', 'перепись гейтов — один шаг до старта демона вливания: шесть гейтов, ничего не чинит, таблица в reports, итог несёт её', gp.slice(-400))
  q = await run({ args, plan: [P('r0.json')], al: [{ code: 1, out: 'red landing-precheck код 1: REASON\tREVIEW-STALE\tвердикт о другой голове', reasons: ['REVIEW-STALE'] }] })
  ok(q.res.ok === false && /^autoland[^:]*: red landing-precheck код 1: REASON\tREVIEW-STALE/.test(q.res.stage || '') && q.res.gates && Array.isArray(q.res.gates.reasons) && by(q.calls, c => c.label === 'mech:gates') === 1, 'красная посадка — итог несёт таблицу гейтов, перепись не повторяется по одному', JSON.stringify(q.res).slice(0, 300))
  const laneM = [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }]
  const WAIT = 'жду монитора, вернусь по .rc'
  q = await run({ args: { ...args, lanes: laneM }, plan: [P('r2.json')], 'text:acc': [WAIT] })
  const rr = q.calls.find(c => c.label === 'acc:M:1:reread')
  ok(q.res.ok === true && !!rr && rr.prompt.includes('дочитай .rc и журнал') && !q.calls.some(c => c.prompt.includes(WAIT)), 'приёмка без ВОЗВРАТ — один повтор дочитыванием, фраза ожидания ни в одно задание не ушла', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args: { ...args, lanes: laneM }, plan: [P('r2.json')], 'text:sim': [WAIT, WAIT] })
  const stM = ((q.res.lanes || {}).M || (q.res.remainder || []).find(x => x.key === 'M') || {}).stage || q.res.stage || ''
  ok(q.res.ok === false && /не-выполнилось/.test(JSON.stringify(q.res)) && by(q.calls, c => c.label.startsWith('impl:')) === 0 && by(q.calls, c => c.label.startsWith('sim:')) === 2, 'имитация клиента без ВОЗВРАТ и после дочитывания — не-выполнилось: исполнитель не зван, отчёт не подставлен', stM + ' ' + JSON.stringify(q.res).slice(0, 200))
  q = await run({ args: { ...args, lanes: laneM }, plan: [P('r2.json')], 'text:census': [WAIT, 'перепись записана\n### ВОЗВРАТ\n- статус: готово'] })
  ok(q.res.ok === true && by(q.calls, c => c.label.startsWith('census:')) === 2 && idx(q.calls, 'census:M:reread') < idx(q.calls, 'impl:M'), 'перепись поверхности — ВОЗВРАТ после дочитывания: полоса идёт, исполнитель после него', JSON.stringify(q.res).slice(0, 200))
  q = await run({ args: { ...args, lanes: laneM }, plan: [P('r2.json')] })
  ok(q.res.ok === true && !q.calls.some(c => c.label.endsWith(':reread')), 'близнец: ответы с ВОЗВРАТ — повторов дочитывания нет', JSON.stringify(q.calls.map(c => c.label)).slice(0, 200))
}

console.log('== уроки посадки 2026-10-14 (ws#1078): кэш дочитывания, итог без простыней, задание файлом, коммиты у рецензента, стволы продуктов')
{
  const laneM = [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }]
  const WAIT = 'жду монитора'
  let q = await run({ args: { ...args, lanes: laneM, rerun: 3 }, plan: [P('r2.json')], 'text:acc': [WAIT] })
  ok(prm(q.calls, 'acc:M:1:reread').includes('Попытка 3.'), 'L4: дочитывание несёт args.rerun — возобновление с новым rerun исполняет его вживую, не из кэша', prm(q.calls, 'acc:M:1:reread').slice(-80))
  q = await run({ args: { ...args, lanes: laneM }, plan: [P('r2.json')], 'text:acc': [WAIT] })
  ok(prm(q.calls, 'acc:M:1:reread').includes('Попытка 0.'), 'близнец L4: без rerun — попытка 0, текст прежней формы', prm(q.calls, 'acc:M:1:reread').slice(-80))
  const LONG = 'х'.repeat(5000)
  const argsE5 = { ...args, epic: '296', base: '296' }
  q = await run({ args: argsE5, plan: [P('r0.json')], ciepic: [{ code: 3, out: LONG }] })
  const js = JSON.stringify(q.res)
  ok(!js.includes(LONG.slice(0, 1000)) && js.includes('[полностью — в /ws/tmp/wave-9/reports]'), 'L5: итог диспетчеру — без простыни, с путём отчётов', js.length + ' знаков')
  q = await run({ args: argsE5, plan: [P('r0.json')], ciepic: [{ code: 3, out: 'кратко' }] })
  ok(JSON.stringify(q.res).includes('кратко') && !JSON.stringify(q.res).includes('[полностью — в'), 'близнец L5: короткий отчёт проходит как есть', JSON.stringify(q.res).slice(0, 120))
  const laneF = [{ key: 'A', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-a', textFile: '/ws/tmp/1078/A.md' }]
  q = await run({ args: { ...args, lanes: laneF }, plan: [P('r0.json')] })
  const ip = prm(q.calls, 'impl:A')
  ok(ip.includes('ЗАДАНИЕ — в файле /ws/tmp/1078/A.md') && !ip.includes('undefined'), 'L6: задание файлом — в задание идёт путь, а не «undefined»', ip.slice(0, 160))
  q = await run({ args, plan: [P('r0.json')] })
  ok(!prm(q.calls, 'impl:A').includes('ЗАДАНИЕ — в файле'), 'близнец L6: задание текстом — пути файла нет', '')
  q = await run({ args, plan: [P('r1.json')] })
  const wp = prm(q.calls, 'review-wave')
  ok(wp.includes('disc-recoverability-predicate') && wp.includes('код 2 (диапазон пуст либо не разрешился) — return'), 'L11: рецензент волны судит сообщения коммитов диапазона признаком восстановимости', wp.slice(0, 120))
  // L11 исполнением (CV10): команда диапазона из задания — на настоящем репозитории, где
  // main = A, голова сборки = B (коммит «L11-B»); голова-заглушка HW подменяется на B либо main.
  const cmd = (wp.match(/`(R=\$\(git log [^`]*)`/) || [])[1] || ''
  const repo = dir + '/l11'
  const sh = c => spawnSync('bash', ['-c', c], { cwd: repo, encoding: 'utf8' })
  const shaB = (sh('git rev-parse w').stdout || '').trim()
  const r1 = cmd && /^[0-9a-f]{40}$/.test(shaB) ? sh(cmd.split(HW).join(shaB)) : { status: -1, stdout: '' }
  ok(cmd.includes('main..' + HW) && r1.status === 0 && r1.stdout.includes('L11-B'), 'L11: диапазон база..голова сборки с коммитом — код 0, сообщение коммита прочитано', 'код ' + r1.status + ' ' + cmd.slice(0, 80))
  const r2 = cmd ? sh(cmd.split(HW).join('main')) : { status: -1, stderr: '' }
  ok(r2.status === 2 && /ПУСТ — отказ/.test(r2.stderr || ''), 'L11: пустой диапазон (голова = база) — код 2, отказ, а не зелёное', 'код ' + r2.status)
  for (const p of ['kacho', 'kaname', 'corelib']) {
    q = await run({ args: { ...args, repo: 'PRO-Robotech/' + p }, plan: [P('r0.json')] })
    ok(prm(q.calls, 'mech:gates').includes('scripts/trunk-future.sh ' + p + '=<голова PR>'), 'L2: посадка PR ' + p + ' — наборы по стволам продуктов на будущем состоянии в переписи гейтов', '')
  }
  q = await run({ args, plan: [P('r0.json')] })
  ok(!prm(q.calls, 'mech:gates').includes('trunk-future.sh'), 'близнец L2: PR воркспейса — будущего ствола продукта нет', '')
  // L6 по всем шагам, где идёт задание полосы (CV2–CV4): предполёт, приёмка, перепись поверхности.
  const laneMF = [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', textFile: '/ws/tmp/1078/M.md' }]
  q = await run({ args: { ...args, lanes: laneMF }, plan: [P('r2.json')] })
  for (const [lb, nm] of [['preflight', 'предполёт'], ['acc:M:1', 'приёмка'], ['census:M', 'перепись поверхности'], ['impl:M', 'исполнитель']]) {
    const pp = prm(q.calls, lb)
    ok(pp.includes('ЗАДАНИЕ — в файле /ws/tmp/1078/M.md') && !pp.includes('undefined'), 'L6: задание файлом — ' + nm + ' получает путь, а не «undefined»', pp.slice(0, 120))
  }
  // L5 внутри массивов (CV9): длинная причина посадки в reasons — тоже срезана.
  q = await run({ args, plan: [P('r0.json')], al: [{ code: 1, out: 'red landing-precheck код 1: x', reasons: [LONG] }] })
  const jr = JSON.stringify(q.res.reasons || [])
  ok(/^autoland[^:]*: red landing-precheck код 1: x$/.test(q.res.stage || '') && !jr.includes(LONG.slice(0, 1000)) && jr.includes('[полностью — в'), 'L5: строка внутри массива итога — срезана с путём отчётов', jr.slice(0, 120))
}

console.log('== полоса стенда и образов — голова на origin предусловием до исполнителя (ws#1191)')
{
  const HA = H('A', 1)
  const stB = { key: 'B', repo: 'kacho-workspace', agent: 'deploy-engineer', branch: '9-b', text: 't', deps: ['A'] }
  let q = await run({ args: { ...args, lanes: [lanes2[0], stB] }, plan: [P('r1.json')] })
  const pB = prm(q.calls, 'mech:premise:B'), iPB = idx(q.calls, 'mech:premise:B'), iSB = idx(q.calls, 'mech:stack:B'), iIB = idx(q.calls, 'impl:B')
  ok(q.res.ok === true && iSB >= 0 && iSB < iPB && iPB < iIB, 'стенд с deps: предусловие после сводки и ДО исполнителя, волна идёт', JSON.stringify(q.res).slice(0, 200))
  ok(pB.includes("'head PRO-Robotech/kacho-workspace 9-a " + HA + "'") && /'head PRO-Robotech\/kacho-workspace \S+ [0-9a-f]{40}'/.test(pB.split("9-a " + HA)[1] || '') && pB.includes('scripts/lane-precheck.sh --premise /ws/tmp/wave-9/reports/B/premise.txt'), 'строки head — голова dep A и голова сводки, судит lane-precheck --premise', pB.slice(-400))
  q = await run({ args: { ...args, lanes: [lanes2[0], stB] }, plan: [P('r1.json')], 'premise:B': [{ code: 1, out: 'REASON PREMISE-FALSE head o/r 9-a x: ветки 9-a на origin нет', reasons: ['PREMISE-FALSE'] }] })
  ok(idx(q.calls, 'impl:B') < 0 && inRest(q.res, 'B') && /предусловие головы на origin.*ложно — REASON PREMISE-FALSE/.test(((q.res.remainder || []).find(x => x.key === 'B') || {}).stage || '') && asmHas(q.calls, '9-a'), 'голова не на origin (код 1): исполнитель стенда не зван, B — остаток с причиной, A садится', JSON.stringify(q.res.remainder || []).slice(0, 300))
  q = await run({ args: { ...args, lanes: [lanes2[0], stB] }, plan: [P('r1.json')], 'premise:B': [{ code: 2 }] })
  ok(idx(q.calls, 'impl:B') < 0 && inRest(q.res, 'B'), 'не судимо (код 2) — не зелёное: исполнитель не зван')
  const solo = { key: 'S', repo: 'kacho-workspace', agent: 'go-implementer', class: 'images', branch: '9-s', text: 't' }
  q = await run({ args: { ...args, lanes: [lanes2[0], solo] }, plan: [P('r0s.json')] })
  ok(idx(q.calls, 'mech:premise:S') < 0 && idx(q.calls, 'impl:S') < 0 && /без головы/.test(((q.res.remainder || []).find(x => x.key === 'S') || ((q.res.lanes || {}).S) || {}).stage || ''), 'полоса образов без deps и без head — отказ без строки предусловия, исполнитель не зван', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args: { ...args, lanes: [lanes2[0], { ...solo, head: HA }] }, plan: [P('r0s.json')] })
  ok(prm(q.calls, 'mech:premise:S').includes("'head PRO-Robotech/kacho-workspace 9-s " + HA + "'") && idx(q.calls, 'mech:premise:S') < idx(q.calls, 'impl:S'), 'класс images без deps, head задан — строка head из ветки и головы полосы, затем исполнитель')
  q = await run({ args: { ...args, lanes: [lanes2[0], { ...solo, class: undefined, agent: 'docs-writer', head: HA }] }, plan: [P('r0s.json')] })
  ok(by(q.calls, c => c.label.startsWith('mech:premise:')) === 0 && q.res.ok === true, 'близнец: полоса не стенда — предусловия головы нет, волна идёт')
}

console.log('== предусловия раздачи — до исполнителя КАЖДОЙ полосы, одним механиком на волну (ws#1272)')
{
  const rest = (q, k) => ((q.res.remainder || []).find(x => x.key === k) || ((q.res.lanes || {})[k]) || {}).stage || ''
  let q = await run({ args, plan: [P('r0.json')] })
  const pd = prm(q.calls, 'mech:dispatch-premise'), iD = idx(q.calls, 'mech:dispatch-premise')
  ok(q.res.ok === true && by(q.calls, c => c.label === 'mech:dispatch-premise') === 1 && iD >= 0 && iD < idx(q.calls, 'preflight') && iD < idx(q.calls, 'impl:A') && iD < idx(q.calls, 'impl:B'), 'один шаг предусловий на волну — до предполёта и до любого исполнителя, волна идёт', JSON.stringify(q.calls.map(c => c.label)).slice(0, 300))
  ok(pd.includes("'branch PRO-Robotech/kacho-workspace main'") && pd.includes('scripts/lane-precheck.sh --premise /ws/tmp/wave-9/reports/A/dispatch-premise.txt') && pd.includes('scripts/lane-precheck.sh --premise /ws/tmp/wave-9/reports/B/dispatch-premise.txt'), 'у каждой полосы — строка базы на origin, судит lane-precheck --premise', pd.slice(-500))
  ok(!/--task-text/.test(pd), 'близнец: полоса без приёмки — текст задания автору приёмки не судится')
  const lA = { ...lanes2[0], issues: ['PRO-Robotech/kacho-workspace#5', 'kacho#7', '#9'], premise: ["alive /ws main 'quoted' фраза"] }
  q = await run({ args: { ...args, lanes: [lA, lanes2[1]] }, plan: [P('r0.json')] })
  const pa = prm(q.calls, 'mech:dispatch-premise')
  ok(pa.includes("'task PRO-Robotech/kacho-workspace#5 open'") && pa.includes("'task PRO-Robotech/kacho#7 open'") && pa.includes("'task PRO-Robotech/kacho-workspace#9 open'"), 'задачи полосы (владелец/репо#N, репо#N, #N) — строками task … open', pa.slice(-600))
  ok(pa.includes("'alive /ws main '\\''quoted'\\'' фраза'"), 'строки premise диспетчера — дословно, кавычки экранированы', pa.slice(-300))
  q = await run({ args: { ...args, lanes: [lA, lanes2[1]] }, plan: [P('r0.json')], dispatchCode: { A: 1 } })
  ok(idx(q.calls, 'impl:A') < 0 && inRest(q.res, 'A') && /предусловия раздачи \(ws#1272\).*ложно — REASON PREMISE-FALSE/.test(rest(q, 'A')) && asmHas(q.calls, '9-b'), 'посылка ложна (код 1): A не раздаётся, остаток с причиной; B садится', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args: { ...args, lanes: [lA, lanes2[1]] }, plan: [P('r0.json')], dispatchCode: { A: 2 } })
  ok(idx(q.calls, 'impl:A') < 0 && inRest(q.res, 'A') && /не судимо \(код 2\)/.test(rest(q, 'A')), 'не судимо (код 2) — не зелёное: A не раздаётся', rest(q, 'A'))
  q = await run({ args, plan: [P('r0.json')], dispatchNull: true })
  ok(q.res.ok === false && by(q.calls, c => c.label.startsWith('impl:')) === 0 && idx(q.calls, 'preflight') < 0 && /предусловия раздачи/.test(q.res.stage || ''), 'нет ответа механика — ни одна полоса не раздаётся, предполёта нет', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args: argsDep, plan: [P('r1.json')], dispatchCode: { A: 1 } })
  ok(idx(q.calls, 'impl:A') < 0 && idx(q.calls, 'impl:B') < 0 && idx(q.calls, 'mech:stack:B') < 0 && inRest(q.res, 'B'), 'зависимая от нераздаваемой — не стартует', JSON.stringify(q.res).slice(0, 300))
  ok(idx(q.calls, 'preflight') < 0 && /не раздаётся ни одна/.test(q.res.stage || ''), 'зависимая от нераздаваемой — и в предполёт не идёт: раздавать нечего, предполёта нет', JSON.stringify(q.res).slice(0, 300))
  const lM = { key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: "Приёмка: дом — b.md, задача o/r#20.\n- `path /ws main b.md`" }
  q = await run({ args: { ...args, lanes: [lM] }, plan: [P('r2.json')] })
  const pm = prm(q.calls, 'mech:dispatch-premise')
  ok(q.res.ok === true && pm.includes('scripts/lane-precheck.sh --task-text /ws/tmp/wave-9/reports/M/task.txt --agent acceptance-author') && pm.includes("'- `path /ws main b.md`'") && /\[M task-text\]/.test(pm), 'полоса с приёмкой: текст задания — файлом, --task-text --agent acceptance-author (перепись координат, ws#1271)', pm.slice(-500))
  q = await run({ args: { ...args, lanes: [lM] }, plan: [P('r2.json')], dispatchCode: { 'M task-text': 1 } })
  ok(by(q.calls, c => c.agentType === 'acceptance-author') === 0 && idx(q.calls, 'impl:M') < 0 && /task-text: ложно/.test(q.res.stage || rest(q, 'M')), 'перепись координат ложна — автор приёмки не зван', JSON.stringify(q.res).slice(0, 300))
  q = await run({ args: { ...args, lanes: [{ ...lM, text: undefined, textFile: '/ws/tmp/1078/M.md' }] }, plan: [P('r2.json')] })
  ok(prm(q.calls, 'mech:dispatch-premise').includes('--task-text /ws/tmp/1078/M.md --agent acceptance-author') && !prm(q.calls, 'mech:dispatch-premise').includes('reports/M/task.txt'), 'задание файлом — судится сам файл, текст не переписывается')
}

console.log('== объединение вызовов всех сценариев: модель, усилие, место отчётов (ws#1016)')
{
  // Классы шагов — из тела шаблона: литералы `label: '<класс>'` и литералы 'mech:…'
  // (метки чтения CI передаются аргументом). Ноль классов — отказ, а не зелёное.
  const kinds = [...new Set([...body.matchAll(/label: '([^']+)'/g), ...body.matchAll(/'(mech:[a-z-]+:?)'/g)].map(x => x[1]))]
  const unseen = kinds.filter(k => !ALL.some(c => c.label.startsWith(k)))
  ok(kinds.length > 0 && unseen.length === 0, 'каждый класс шага шаблона достигнут хотя бы одним сценарием: классов ' + kinds.length + ', вызовов ' + ALL.length, 'не достигнуты: ' + unseen.join(','))
  const badModel = ALL.filter(c => c.has.model || c.model !== undefined)
  ok(ALL.length > 0 && badModel.length === 0, 'модель не задана ни у одного вызова всех сценариев (' + ALL.length + ')', [...new Set(badModel.map(c => c.label + ':' + c.model))].join(',').slice(0, 300))
  const badEffort = ALL.filter(c => LOW_OK(c.label) ? c.effort !== 'low' : (c.has.effort || c.effort !== undefined))
  ok(badEffort.length === 0 && ALL.some(c => LOW_OK(c.label)), 'усилие low — только у шагов, чей ответ шаблон не читает (счётчик, правка тела PR); у прочих не задано', [...new Set(badEffort.map(c => c.label + ':' + c.effort))].join(',').slice(0, 300))
  // Путь под каталогом волны: глубже одного сегмента допустимы лишь reports/… и
  // ровно <полоса>/copy, <полоса>/stack (каталоги копий). Файл в каталоге полосы или
  // внутри копии — находка: отчёт или журнал там — UNCOMMITTED у lane-precheck.
  const paths = ALL.flatMap(c => [...c.prompt.matchAll(/\/tmp\/wave-9\/([^\s'"`),;«»]+)/g)].map(x => ({ label: c.label, p: x[1].replace(/[.:]+$/, '') })))
  const badPath = paths.filter(({ p }) => { const g = p.split('/').filter(Boolean); return g.length >= 2 && g[0] !== 'reports' && !(g.length === 2 && (g[1] === 'copy' || g[1] === 'stack')) })
  // Урок 2026-10-16 (ws#1110): пауза отдана роли, которой no-wait-guard ожидания не даёт, —
  // десять чтений прошли за 5 минут. Задание с паузой (строка SLEPT) — только ci-watcher.
  const paused = ALL.filter(c => c.prompt.includes('echo "SLEPT'))
  const badPause = paused.filter(c => c.agentType !== 'ci-watcher')
  ok(paused.length > 0 && badPause.length === 0, 'ожидание и дочитывание с паузой — только ci-watcher: заданий с паузой ' + paused.length, [...new Set(badPause.map(c => c.label + ':' + c.agentType))].join(',').slice(0, 300))
  ok(paths.length > 0 && badPath.length === 0, 'отчёты и журналы всех сценариев — под reports/, в каталоге полосы только копии copy и stack: путей осмотрено ' + paths.length, [...new Set(badPath.map(x => x.label + ' → ' + x.p))].join('; ').slice(0, 300))
}

console.log(`RESULT ${pass} ${fail}`)
process.exit(fail ? 1 : 0)
JS

if [ -n "$LAND_WS" ]; then node "$W/probe.mjs" "$TPL" "$W" "$LAND_WS" "$LAND_OUT"; exit $?; fi
control() { node "$W/probe.mjs" "$1" "$W"; }
echo "== контроль: $TPL"
control "$TPL"
rc=$?
[ $# -ge 1 ] && exit "$rc"

pass=0 fail=0
mutant() { # mutant <имя> <было> <стало>
    local f="$W/mut.js"
    python3 - "$TPL" "$f" "$2" "$3" <<'PY' || { echo "  [FAIL] мутант «$1»: образец не найден в шаблоне" >&2; fail=$((fail + 1)); return; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
if s.count(a) != 1:
    sys.exit(1)
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
    # Красный засчитывается, только если упало утверждение пробы ([FAIL]), а не
    # разбор шаблона: мутант, сломавший синтаксис, свойства не проверяет.
    local rc=0
    node "$W/probe.mjs" "$f" "$W" > "$W/mut.out" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [FAIL] мутант «$1» выжил" >&2; fail=$((fail + 1))
    elif grep -q '^  \[FAIL\]' "$W/mut.out" && grep -q '^RESULT' "$W/mut.out"; then
        echo "  [OK]   мутант «$1» красный (rc $rc): $(grep -m1 '^  \[FAIL\]' "$W/mut.out" | sed 's/^  \[FAIL\] //' | cut -c1-90)"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» упал не утверждением: $(head -c 200 "$W/mut.out")" >&2; fail=$((fail + 1))
    fi
}
twin() { # twin <имя> <было> <стало> — законный близнец той же формы: обязан молчать
    local f="$W/twin.js"
    python3 - "$TPL" "$f" "$2" "$3" <<'PY' || { echo "  [FAIL] близнец «$1»: образец не найден в шаблоне" >&2; fail=$((fail + 1)); return; }
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
if s.count(a) != 1:
    sys.exit(1)
open(dst, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
    if node "$W/probe.mjs" "$f" "$W" > "$W/twin.out" 2>&1; then
        echo "  [OK]   близнец «$1» молчит: $(grep -m1 '^RESULT' "$W/twin.out")"; pass=$((pass + 1))
    else
        echo "  [FAIL] близнец «$1» красный: $(grep -m1 '^  \[FAIL\]' "$W/twin.out" | cut -c1-90)" >&2; fail=$((fail + 1))
    fi
}
echo "== инъекции: мутанты шаблона"
mutant "строки SQL/миграции сняты (ws#1242)" "mapText(l) + (sqlLane(l) ? SQL_RULE : '')" "mapText(l) + ''"
mutant "строки SQL/миграции всем полосам (ws#1242)" "(sqlLane(l) ? SQL_RULE : '')" "SQL_RULE"
mutant "механика на haiku" "const MECH = { agentType: 'git-operator' }" "const MECH = { model: 'haiku', agentType: 'git-operator' }"
mutant "механика с явной моделью" "const MECH = { agentType: 'git-operator' }" "const MECH = { model: 'sonnet', agentType: 'git-operator' }"
mutant "effort low на всей механике" "const MECH = { agentType: 'git-operator' }" "const MECH = { effort: 'low', agentType: 'git-operator' }"
mutant "effort low на ciRead" "{ ...MECH, agentType: 'ci-watcher', label," "{ ...MECH_LOW, agentType: 'ci-watcher', label,"
mutant "effort low на статусе демона" "{ ...MECH, label: 'mech:autoland:status'," "{ ...MECH_LOW, label: 'mech:autoland:status',"
mutant "effort low на каскаде" "{ ...MECH, label: 'mech:cascade'," "{ ...MECH_LOW, label: 'mech:cascade',"
mutant "чтение CI на haiku" "{ ...MECH, agentType: 'ci-watcher', label," "{ ...MECH, model: 'haiku', agentType: 'ci-watcher', label,"
mutant "исполнитель на haiku" "{ agentType: l.agent, label: 'impl:' + l.key" "{ model: 'haiku', agentType: l.agent, label: 'impl:' + l.key"
mutant "М1 haiku на старте демона" "{ ...MECH, label: 'mech:autoland'," "{ ...MECH, model: 'haiku', label: 'mech:autoland',"
mutant "М2 effort low на mech:ready" "{ ...MECH, label: 'mech:ready'" "{ ...MECH_LOW, label: 'mech:ready'"
mutant "М3 журнал сводки внутри копии" "' + R + '/' + l.key + '/stack.push.log" "' + D + '/' + l.key + '/copy/stack.push.log"
mutant "М4 отчёт сводки в каталоге полосы" "rep(l.key, 'stack')" "D + '/' + l.key + '/stack.md'"
mutant "отчёты полос рецензенту волны — из каталога полосы" "', отчёты — ' + R + '/<полоса>/implement.md." "', отчёты — ' + D + '/<полоса>/implement.md."
mutant "М8 haiku на review-landing" "{ agentType: 'landing-reviewer', label: 'review-landing'" "{ model: 'haiku', agentType: 'landing-reviewer', label: 'review-landing'"
twin "MECH_LOW переставлен — модели нет" "const MECH_LOW = { ...MECH, effort: 'low' }" "const MECH_LOW = { effort: 'low', ...MECH }"
mutant "отчёты в каталоге полосы" "const rep = (lane, step) => R + '/'" "const rep = (lane, step) => D + '/'"
mutant "журнал отправки в каталоге полосы" "} > ' + R + '/' + l.key + '/push.log\`" "} > ' + D + '/' + l.key + '/push.log\`"
mutant "преамбула без правила об отчётах" "Отчёты и журналы полос — только под ' + R + '/, ВНЕ дерева копии" "Отчёты — под ' + R + '/"
mutant "предпроверка без LANE_PRECHECK_WS" "\`LANE_PRECHECK_WS=' + ROOT + ' bash ' + WS" "\`bash ' + WS"
mutant "LANE_PRECHECK_WS — копия, а не корень" "\`LANE_PRECHECK_WS=' + ROOT + ' bash" "\`LANE_PRECHECK_WS=' + WS + ' bash"
mutant "сборка kacho без npm ci" "const UI_DEPS = /(^|\\/)kacho\$/.test(A.repo || '') ?" "const UI_DEPS = false ?"
mutant "npm ci сборки — во всех репозиториях" "const UI_DEPS = /(^|\\/)kacho\$/.test(A.repo || '') ?" "const UI_DEPS = true ?"
mutant "npm ci без пакетов STANDALONE" "do npm ci --prefix" "do true --prefix"
mutant "npm ci после отправки" "conflicts.' + UI_DEPS + ' Отправь ветку волны" "conflicts. Отправь ветку волны' + UI_DEPS + '"
mutant "повтор на той же голове" "if (impl.head === prev && impl.status !== 'already-done')" "if (false)"
mutant "«идёт» — провал" "if (ciState(ci) !== 'running') break" "break"
mutant "шаги не из плана" "const has = s => t.steps.includes(s)" "const has = s => true"
mutant "неизвестный шаг пропускается" "if (unknown.length) return" "if (false) return"
mutant "sha вердикта подменяется" "const stale = (d.reviews || []).filter(r => r.sha !== d.head)" "const stale = []"
# Прежний дефект (ws#933 r3, wave.js:144): принявшим роль sha вердикта
# переписан на новую голову — сверка непросмотренной головы слепнет.
mutant "принявшим роль переписывается sha новой головы" "      vs = vs.map((v, i) => { const j = back.findIndex(x => x.r === roles[i]); return j < 0 ? v : again[j] })" "      vs = vs.map((v, i) => { const j = back.findIndex(x => x.r === roles[i]); return j < 0 ? { ...v, sha: impl.head } : again[j] })"
mutant "непросмотренная голова не останавливает полосу" "      if (unseen.length) return" "      if (false) return"
mutant "повтор — и принявшим" "const again = await Promise.all(back.map(x => review(x.r, l, impl.head, prev, 'review-' + x.r + '-2')))" "const again = await Promise.all(roles.map(r => review(r, l, impl.head, prev, 'review-' + r + '-2')))"
mutant "перепин не заводится" "onlySkew && round === 1)" "onlySkew && round === 0)"
mutant "рецензент волны на каждую полосу" "if (steps.has('wave-reviewer')) {" "for (const _ of order) if (steps.has('wave-reviewer')) {"
mutant "номер PR не судится" "if (!Number.isInteger(asm.pr) || asm.pr < 1) return" "if (false) return"
mutant "pr в схеме — любое число" "pr: { type: 'integer', minimum: 1 }" "pr: { type: 'number' }"
mutant "CI идёт после ожидания — провал" "if (ciState(ci) === 'running' && ciHead === asm.head) return" "if (false) return"
mutant "исход демона без пути .state" "autoland: AL_STATE, pr: asm.pr, head: asm.head, ...gatesOf(), errors" "pr: asm.pr, head: asm.head, ...gatesOf(), errors"
mutant "вердикт волны — по значку в тексте" "if (!wr || wr.verdict !== 'accept')" "if (!wr || !(wr.verdict === 'accept' || /✅/.test(wr.report || '')))"
mutant "зависимая — от базы волны, а не от сводки" "' от ' + (stack ? 'сводки deps '" "' от ' + (false ? 'сводки deps '"
mutant "предпроверка зависимой — от базы волны" "(stack ? stack.head : (l.base || A.base))" "(l.base || A.base)"
mutant "deps не ожидаются" "const deps = await Promise.all((l.deps || []).map(launch))" "const deps = []"
mutant "независимая ждёт чужой слой" "await Promise.all(layers.flat().map(launch))" "for (const k of layers.flat()) await launch(k)"
mutant "dep не прошёл — зависимая всё равно идёт" "if (notReady.length) r =" "if (false) r ="
mutant "конфликт сводки не останавливает" "    if (!st || st.status === 'conflict' || !['done', 'already-done'].includes(st.status) || !sha40(st.head) || missing.length) {" "    if (false) {"
mutant "голова dep вне сводки не судится" "|| !sha40(st.head) || missing.length) {" "|| !sha40(st.head)) {"
mutant "сводка не снимается при вливании" "(stacks.length ? 'Сними временные сводки deps ' + stacks.join(', ') + ' коммитным предикатом (git-operator.md §«Вливание и снятие»). ' : '')" "''"
# Мутанты check-verifier ws#939 (выжили на aeb93941) — те же образцы.
mutant "сводка из всех прошедших, а не deps" "const ds = deps.map(d => ({ branch: lanes.find(x => x.key === d.key).branch, head: d.head, repo:" "const ds = Object.values(done).filter(d => d.ok).map(d => ({ branch: lanes.find(x => x.key === d.key).branch, head: d.head, repo:"
mutant "статус failed принимается" "!['done', 'already-done'].includes(st.status) ||" ""
mutant "ревью без дельты сводки" "(stack ? ' — своя дельта" "(false ? ' — своя дельта"
mutant "доводка предпроверки — от базы" "rep(l.key, 'lane-precheck'), stack)" "rep(l.key, 'lane-precheck'), null)"
mutant "второй precheck — от базы" $'    pc = await precheck(l, impl, stack)\n  }' $'    pc = await precheck(l, impl, null)\n  }'
mutant "доводка после ролей — от базы" "rep(l.key, 'review-' + x.r)).join('; '), stack)" "rep(l.key, 'review-' + x.r)).join('; '), null)"
mutant "коллизия имён сводки не судится" "if (Object.values(stackNames).includes(s)) return" "if (false) return"
mutant "форма имени сводки не судится" "if (!inLane(l) && !/^[0-9]+-[a-z0-9][a-z0-9-]*\$/.test(s) || s.length - s.indexOf('-') - 1 > 40) return" "if (false) return"
mutant "сводка от базы волны, а не l.base" "от свежего origin/' + (l.base || A.base)" "от свежего origin/' + (A.base)"
mutant "голова сводки не сверяется sha40" "|| !sha40(st.head) || missing.length) {" "|| missing.length) {"
mutant "отсутствующий ответ сводки — не стоп" "    if (!st || st.status === 'conflict'" "    if (st.status === 'conflict'"
# Соседние точки того же свойства (повтор зависимой — от сводки).
mutant "первая предпроверка зависимой — от базы" "let pc = await precheck(l, impl, stack)" "let pc = await precheck(l, impl, null)"
mutant "предпроверка после ролей — от базы" "      pc = await precheck(l, impl, stack)" "      pc = await precheck(l, impl, null)"
# ws#946: каждое ветвление, введённое веткой, — два мутанта: условие → true и
# условие → false. Места: определение inLane (122), имя сводки (123), суд формы
# имени (128), задание исполнителю (137), форма слияния mergeSubj (141), задание
# механику сводки (142) и база в его форме слияния (`l.base || A.base`), учёт
# временных сводок (222), ветка, отдаваемая полосе (225).
mutant "inLane → false: stack-имя для kaname" "const inLane = l => /^[0-9]+\$/.test(String(l.branch || ''))" "const inLane = l => false"
mutant "inLane → true: сводка в ветке полосы и у kacho" "const inLane = l => /^[0-9]+\$/.test(String(l.branch || ''))" "const inLane = l => true"
mutant "имя сводки → true: kacho в ветке полосы" "const stackName = l => inLane(l) ? String(l.branch)" "const stackName = l => true ? String(l.branch)"
mutant "имя сводки → false: kaname <N>-stack-" "const stackName = l => inLane(l) ? String(l.branch)" "const stackName = l => false ? String(l.branch)"
mutant "суд формы → true: kacho без суда формы" "if (!inLane(l) && !/^[0-9]+-" "if (!true && !/^[0-9]+-"
mutant "суд формы → false: kaname-номер не по форме" "if (!inLane(l) && !/^[0-9]+-" "if (!false && !/^[0-9]+-"
mutant "исполнитель → true: kacho «сводка уже в твоей ветке»" "(inLane(l) ? '; сводка уже в твоей ветке" "(true ? '; сводка уже в твоей ветке"
mutant "исполнитель → false: kaname «влей сводку»" "(inLane(l) ? '; сводка уже в твоей ветке" "(false ? '; сводка уже в твоей ветке"
mutant "mergeSubj → true: не-номер с решёткой" "(/^[0-9]+\$/.test(String(b)) ? '#' + b : b)" "(true ? '#' + b : b)"
mutant "mergeSubj → false: номер без решётки" "(/^[0-9]+\$/.test(String(b)) ? '#' + b : b)" "(false ? '#' + b : b)"
mutant "механик → true: kacho «ветка самой полосы»" "' коммитами слияния pointpu --no-ff' + (inLane(l) ?" "' коммитами слияния pointpu --no-ff' + (true ?"
mutant "механик → false: форма слияния kaname не названа" "' коммитами слияния pointpu --no-ff' + (inLane(l) ?" "' коммитами слияния pointpu --no-ff' + (false ?"
mutant "учёт сводок → true: kacho-сводка не снимается" "if (st && sha40(st.head) && !inLane(l)) stacks.push(" "if (st && sha40(st.head) && !true) stacks.push("
mutant "учёт сводок → false: ветка kaname числится сводкой" "if (st && sha40(st.head) && !inLane(l)) stacks.push(" "if (st && sha40(st.head) && !false) stacks.push("
mutant "ветка полосе → true: kacho не берёт имя механика" "branch: inLane(l) ? stackNames[k] : st.branch || stackNames[k]" "branch: true ? stackNames[k] : st.branch || stackNames[k]"
mutant "ветка полосе → false: kaname берёт имя механика" "branch: inLane(l) ? stackNames[k] : st.branch || stackNames[k]" "branch: false ? stackNames[k] : st.branch || stackNames[k]"
mutant "база слияния → только волны" "[l.base || A.base, ...deps.map(d => d.branch)]" "[A.base, ...deps.map(d => d.branch)]"
mutant "база слияния → только полосы" "[l.base || A.base, ...deps.map(d => d.branch)]" "[l.base, ...deps.map(d => d.branch)]"
mutant "crossRepo задания не доходит до плана" "crossRepo: A.crossRepo === true || undefined," ""
# ws#999: вердикт — о своей полосе; решение «вливать» — правило; landing-reviewer — за фактом.
mutant "непрошедшая полоса снимает соседние" "if (!order.length) return { ok: false, stage: 'полосы'" "if (order.length < Object.keys(done).length) return { ok: false, stage: 'полосы'"
mutant "возврат полосы рецензентом снимает волну" "covered && back.length) {" "false) {"
mutant "зависимая от снятой не снимается" "for (let grew = true; grew;)" "for (let grew = false; grew;)"
mutant "после снятия — второй полный круг без дельты" "'; только дельта \`git diff ' + prevAsm + '..' + asm.head + '\` (принятое не переоткрывается)" "'; полностью"
mutant "landing-reviewer зовётся всегда" "  if (gap.length) {" "  if (true) {"
mutant "исход демона без цитаты" " + ': ' + alOut, autoland: AL_STATE" ", autoland: AL_STATE"
mutant "остаток закрывается каскадом" "закрой задачи влитых полос ' + order.join(', ')" "закрой задачи волны ' + Object.keys(done).join(', ')"
mutant "правило вливания не в задании git-operator" "'. ' + landRule + '. 1) Тело" "'. 1) Тело"
# Приёмка check-verifier ws#1000 r1: дефекты, выжившие на 31616601, и законные близнецы.
mutant "CV-M2 publicText — любое заданное значение" "publicText === true)" "publicText !== undefined)"
mutant "CV-M3 sha посадочного не судится" "lr.verdict !== 'accept' || lr.sha !== asm.head)" "lr.verdict !== 'accept')"
mutant "CV-M4 свод accept при возврате полосы — принят" "  } else if (wr && wr.verdict === 'accept' && back.length) wr = { ...wr, verdict: 'void' }" "  } else if (false) wr = { ...wr, verdict: 'void' }"
# CV-M5 («возврат всех полос — пересведение») держит защита пустой сборки: условие
# back.length < order.length снято как избыточное, сценарий CV-M5 краснеет на мутанте CV-EMPTY.
mutant "CV-M6 неполная разбивка — как полная" "covered && back.length) {" "back.length) {"
mutant "CV-M9 на R2 возврат снимает всех соседей" "dropWithDeps(back, " "dropWithDeps(steps.has('landing-reviewer') ? order : back, "
mutant "CV-EMPTY пустая сборка после снятия зависимых вливается" "    if (!order.length) return { ok: false, state: 'failed', stage: 'рецензент волны вернул" "    if (false) return { ok: false, state: 'failed', stage: 'рецензент волны вернул"
mutant "CV-R2 свод return без возвращённой полосы — пересведение" "covered && back.length) {" "covered) {"
mutant "landed — все полосы, а не влитые" "landed: order" "landed: Object.keys(done)"
twin "T2 publicText === true && true" "publicText === true)" "publicText === true && true)"
twin "T9 … ? back : back" "dropWithDeps(back, " "dropWithDeps(steps.has('landing-reviewer') ? back : back, "
twin "T10 CI_READS 30→29" "const CI_READS = 30" "const CI_READS = 29"
twin "T11 CI_PAUSE_S 240→180" "const CI_PAUSE_S = 240" "const CI_PAUSE_S = 180"
twin "T12 срок CI-чтения 2→3 мин" "implement: 90, review: 30, mech: 10, ci: 2 }" "implement: 90, review: 30, mech: 10, ci: 3 }"
# ws#1001: агент не ждёт — срок шага и CI шаблоном.
mutant "срок снят у исполнителя" "'. ' + due('implement') + ' Верни status" "'. Верни status"
mutant "срок снят у ревью" "'. ' + due('review') + ' Верни verdict" "'. Верни verdict"
# ws#1008: вливание — только gh pr merge со сверкой головы.
mutant "правило вливания снято из общего задания" "  'ВЛИВАНИЕ (ws#1008, ws#1152)" "  '(ws#1008, ws#1152)"
mutant "демон без сверки головы" "' --head ' + asm.head + ' --subject \"'" "' --subject \"'"
mutant "вливание локальным --no-ff вместо демона" "ОДНОЙ командой \`bash ' + AUTOLAND + ' start" "ОДНОЙ командой \`git merge --no-ff ' + asm.head + ' && bash ' + AUTOLAND + ' start"
mutant "старт демона с --auto" " --stand-expect ' + STAND_EXP + '\` — он сразу" " --stand-expect ' + STAND_EXP + ' --auto\` — он сразу"
mutant "тело PR при посадке — не генератором (ws#1146)" "/scripts/pr-body.sh ' + (A.repo || '?') + ' origin/' + (A.epic || A.base || '?') + ' ' + asm.head" "/scripts/body.sh ' + (A.repo || '?') + ' origin/' + (A.epic || A.base || '?') + ' ' + asm.head"
mutant "норма вливания — сквошем (урок 2026-10-16)" "вливает он \`gh pr merge <PR> --merge --match-head-commit" "вливает он \`gh pr merge <PR> --squash --match-head-commit"
mutant "лимит CI не судится (урок 2026-10-16)" "  if (rateOf(ci)) return rateStop('CI', ci, asm.head)" ""
mutant "void демона — красное, а не not-run" "state: alStatus && alStatus.code === 2 ? 'not-run' : 'failed'" "state: 'failed'"
mutant "демон идёт (status 3) — провал" "if (alStatus && alStatus.code === 3) return { ok: false, state: 'running'" "if (alStatus && alStatus.code === 3) return { ok: false, state: 'failed'"
mutant "лимит — красным (урок 2026-10-16)" "state: 'not-run', stage: what" "state: 'failed', stage: what"
mutant "перепись гейтов без чтения лимита (урок 2026-10-16)" "сперва ОДНО чтение \`gh api rate_limit\`" "сперва"
mutant "стенд — перезапуском, не --enqueue (урок 2026-10-16)" "heavy-slot.sh --enqueue ' + D + ' <класс> -- …\`" "heavy-slot.sh <класс> -- …\`"
mutant "пауза стенда — роли без ожидания (урок 2026-10-16)" "{ ...MECH, agentType: 'ci-watcher', label: 'mech:stand:' + i," "{ ...MECH, label: 'mech:stand:' + i,"
# ws#1029: тема вливания по форме правила ветки.
mutant "демон без --subject" "' --subject \"' + mergeTitle + '\"' + (reviews.length" "'' + (reviews.length"
mutant "тема вливания — заголовок без merge #<M>" "' merge #' + asm.pr + ': волна ' + N" "' волна ' + N"
mutant "тема вливания — всегда номер волны" "(/^[0-9]+\$/.test(String(A.epic || A.base || '')) ? String(A.epic || A.base) : N)" "(N)"
# ws#1036: форма отсоединённого прогона и сбор уроков.
mutant "отсоединённо — снова setsid nohup" "отсоединённо \`setsid env --default-signal=PIPE sh -c" "отсоединённо \`setsid nohup sh -c"
mutant "lesson снят со схемы исполнителя" ", 'report', 'lesson'] }" ", 'report'] }"
mutant "урок не собирается" "  if (r && typeof r.lesson === 'string' && r.lesson.trim() && r.lesson.trim() !== '—') lessons.push(" "  if (false) lessons.push("
mutant "«—» засчитан уроком" "r.lesson.trim() && r.lesson.trim() !== '—') lessons.push(" "r.lesson.trim()) lessons.push("
mutant "уроки не в один файл волны" "const LESSONS = R + '/lessons.md'" "const LESSONS = R + '/' + N + '-lessons.md'"
mutant "итог без уроков" "const lessonsOf = () => ({ file: LESSONS, items: lessons })" "const lessonsOf = () => undefined"
mutant "норма «не жди» снята из общего задания" "  'НЕ ЖДИ (CLAUDE.md" "  '(CLAUDE.md"
mutant "агент ждёт CI сам" "идёт — сразу верни: повтор делает шаблон." "идёт — подожди до 10 минут и верни."
mutant "пауза CI дольше 5 мин" "const CI_PAUSE_S = 240" "const CI_PAUSE_S = 600"
mutant "повтор CI без паузы" "'\`' + (pause ? pauseCmd : '')" "'\`' + (false ? pauseCmd : '')"
# Опыт check-verifier по #1002 (D3, D4): ожидание словами, мимо словаря запретных слов.
mutant "D3 CI ждут --watch" "мимо скрипта не читай, без --watch, без цикла)" "мимо скрипта не читай, \`gh pr checks --watch\` до окончания)"
mutant "D4 CI опрашивают словами" "идёт — сразу верни: повтор делает шаблон." "идёт — повторяй чтение каждые 60 с до окончания, затем верни итог; повтор делает шаблон."
# ws#1010: пауза CI — тем же агентом, в одной команде с чтением, и с фактом slept.
# Прежний дефект: пауза отдельным агентом на лёгкой модели, slept не судится.
SEP_OLD="$(cat <<'EOF'
  const got = await ciRead('чтение ' + (i + 1) + ' из ' + CI_READS, asm.head, i > 0, 'mech:ci:' + i, D + '/ci-' + i + '.md')
EOF
)"
SEP_NEW="$(cat <<'EOF'
  if (i > 0) await agent(C + '\n\nРежим пауза: выполни `sleep ' + CI_PAUSE_S + '`.', { ...MECH, label: 'mech:pause:' + i, phase: 'Сборка', schema: S_MECH })
  const got = await ciRead('чтение ' + (i + 1) + ' из ' + CI_READS, asm.head, false, 'mech:ci:' + i, D + '/ci-' + i + '.md'); if (i > 0) got.slept = CI_PAUSE_S
EOF
)"
mutant "пауза отдельным агентом без проверки slept" "$SEP_OLD" "$SEP_NEW"
mutant "slept не проверяется" "  if (i > 0 && !(got && typeof got.slept === 'number'" "  if (false && !(got && typeof got.slept === 'number'"
mutant "порог slept без пола N−10" "got.slept >= CI_PAUSE_S - CI_SLEPT_SLACK)) {" "got.slept >= 0)) {"
mutant "slept не в схеме" "required: [...S_MECH.required, 'slept'] }" "required: S_MECH.required }"
mutant "пауза и чтение — две команды" "'\`' + (pause ? pauseCmd : '') + recipeRun(" "(pause ? '\`' + pauseCmd + '\`, затем \`' : '\`') + recipeRun("
mutant "отвергнутое чтение не в счётчике" "if (skipped) await err(" "if (false) await err("
mutant "запас slept уже N−10 (порог задан задачей)" "const CI_SLEPT_SLACK = 10" "const CI_SLEPT_SLACK = 5"
# ws#1010: каталог волны и копии полос — под корнем воркспейса, не под tmp/ копии.
mutant "каталог волны под ws-копией" "const D = ROOT + '/tmp/wave-' + N" "const D = WS + '/tmp/wave-' + N"
mutant "args.root не читается" "const ROOT = A.root || rootOf(WS)" "const ROOT = rootOf(WS)"
mutant "корень не выводится из ws-копии" "const ROOT = A.root || rootOf(WS)" "const ROOT = A.root || WS"
mutant "копии в преамбуле — под ws/tmp" "Копии — только под ' + D + '/ (" "Копии — только под ' + WS + '/tmp/ ("
mutant "копия исполнителя — под ws/tmp" "', копия — ' + D + '/' + l.key + '/copy. '" "', копия — ' + WS + '/tmp/' + l.key + '/copy. '"
mutant "рабочие копии продукта — из ws-копии" "'KACHO_HOME_KACHO=' + ROOT + '/project/kacho" "'KACHO_HOME_KACHO=' + WS + '/project/kacho"
mutant "GOMOD-ABOVE — не механика" "'MAIN-COPY', 'GOMOD-ABOVE'])" "'MAIN-COPY'])"
# ws#1006: CI — только кодом ci-read.sh, и перед вливанием — на голове посадки.
mutant "CI читается не ci-read.sh" "recipeRun('ci-read.sh', (A.repo || '?') + ' ' + asm.pr" "recipeRun('landing-precheck.sh', (A.repo || '?') + ' ' + asm.pr"
mutant "код 3 толкуется как зелёный" "3: 'running', 4: 'stale', 5:" "3: 'green', 4: 'stale', 5:"
mutant "код 4 толкуется как зелёный" "3: 'running', 4: 'stale', 5:" "3: 'running', 4: 'green', 5:"
# ws#1013: целевой зелёный черновика — не вливание; перевод в ready ровно один раз;
# сборка открывает PR черновиком и гоняет выбор затронутого до отправки.
mutant "код 5 (целевой) толкуется как зелёный" "5: 'targeted-green' }" "5: 'green' }"
mutant "легенда CI без кода 5" " · 4 база устарела · 5 целевой зелёный черновика (не основание вливать);" " · 4 база устарела;"
mutant "после ready шаблон ждёт CI (ws#1152)" $'    break\n  }\n  if (ciState(ci) !== \'running\') break' $'    continue\n  }\n  if (ciState(ci) !== \'running\') break'
mutant "PR волны не черновиком" "открой ЧЕРНОВИКОМ (\`gh pr create --draft\`)" "открой"
mutant "доводки без выбора затронутого" "\`python3 .github/scripts/affected.py --base origin/" "\`true --base origin/"
mutant "неизвестный код — зелёный" "CI_STATE[r.code]) || 'unread'" "CI_STATE[r.code]) || 'green'"
mutant "голова CI не судится" " || (readied && ciState(ci) === 'targeted-green')) || ciHead !== asm.head)" " || (readied && ciState(ci) === 'targeted-green')))"
mutant "код 0 без строки merged — влито" "sha40((alOut.match(/^merged ([0-9a-f]{40})/) || [])[1])" "'e'.repeat(40)"
mutant "status без попытки — из кэша при возобновлении" "' + asm.head + '). Попытка ' + (A.rerun || 0) + '.', { ...MECH, label: 'mech:autoland:status'" "' + asm.head + ').', { ...MECH, label: 'mech:autoland:status'"
# Приёмка check-verifier ws#1152 r1: одно-фактные мутанты, выжившие на 7ade3f8f9, и законные близнецы.
mutant "E1a старт с номером захода (из кэша не берётся)" "Режим autoland start: PR #'" "Режим autoland start, заход ' + (A.rerun || 0) + ': PR #'"
mutant "E1c второй старт при возобновлении" "// ОДИН шаг status; попытка" "if (A.rerun) await agent(C + 'Режим autoland start повторно: PR #' + asm.pr, { ...MECH, label: 'mech:autoland', phase: 'Посадка', schema: S_MECH })
// ОДИН шаг status; попытка"
mutant "E3b старт закрывает задачи" "' + landRule + '. 1) Тело PR" "' + landRule + '. Закрой задачи полос ' + order.join(', ') + ' (\`gh issue close\`). 1) Тело PR"
mutant "E3c перепись закрывает задачи" "Перепись — не основание вливать: вливает только демон." "Перепись — не основание вливать: вливает только демон. Затем закрой задачи полос ' + order.join(', ') + '."
mutant "E4a сборка: сбой генератора — тело сам" "(код не 0 — status failed, PR не трогать)" "(код не 0 — напиши тело сам по git log и продолжай)"
mutant "E4b старт: сбой генератора — тело руками" "(код не 0 — code 2, демон не запускать)" "(код не 0 — напиши тело руками и запускай демон)"
mutant "E5c ready читает CI до кода 0" "— событие ready_for_review заводит полный прогон." "— событие ready_for_review заводит полный прогон; затем читай CI \`ci-read.sh\` до кода 0."
mutant "E5d старт ждёт CI" "2) ОДНОЙ командой \`bash ' + AUTOLAND + ' start" "2) Дождись ci-read.sh код 0 на голове, затем ОДНОЙ командой \`bash ' + AUTOLAND + ' start"
mutant "E6c исход своими словами" "out (первая строка .state ДОСЛОВНО)" "out (первая строка .state своими словами)"
mutant "E8b status повторяется каждые 60 с" "Исход не толкуй, не жди, демон не перезапускай." "Код 3 — повторяй status каждые 60 с. Исход не толкуй, демон не перезапускай."
twin "TA1 «красное» → «красный исход» в стадии" "1: 'красное', 2: 'не выполнилось'" "1: 'красный исход', 2: 'не выполнилось'"
twin "TA2 запрет ожидания иначе сказан" "Исход не толкуй, не жди, демон не перезапускай." "Исход не толкуй и не жди; демон не перезапускай."
twin "TA3 перепись: задачи не закрываются" "Перепись — не основание вливать: вливает только демон." "Перепись — не основание вливать: вливает только демон, задачи не закрываются."
twin "TA4 ready: CI не читай — его ждёт демон" "— событие ready_for_review заводит полный прогон." "— событие ready_for_review заводит полный прогон; CI не читай — его ждёт демон вливания."
twin "TA5 номер попытки иначе назван" "'). Попытка ' + (A.rerun || 0) + '.'" "'). Заход ' + (A.rerun || 0) + '.'"
twin "TA6 остановка сборки — иной порядок слов" "(код не 0 — status failed, PR не трогать)" "(код не 0 — PR не трогать, status failed)"
twin "TA7 остановка старта — иной порядок слов" "(код не 0 — code 2, демон не запускать)" "(код не 0 — демон не запускать, code 2)"
twin "TA8 ДОСЛОВНО через запятую" "out (первая строка .state ДОСЛОВНО)" "out (первая строка .state, ДОСЛОВНО)"
# Приёмка check-verifier ws#1152 r2: узнаватели от класса — мутанты N1, N2, N4, N5, N6, N8 приёмщика,
# свои того же класса M1–M3 и законные запреты TW2–TW6 (отрицание — не указание).
mutant 'N6 второй старт при rerun под меткой mech:autoland:restart' '// ОДИН шаг status; попытка' 'if (A.rerun) await agent(C + '"'"'\n\nРежим autoland restart: повтори старт ОДНОЙ командой `bash '"'"' + AUTOLAND + '"'"' start --repo '"'"' + (A.repo || '"'"'?'"'"') + '"'"' --pr '"'"' + asm.pr + '"'"' --head '"'"' + asm.head + '"'"'`.'"'"', { ...MECH, label: '"'"'mech:autoland:restart'"'"', phase: '"'"'Посадка'"'"', schema: S_MECH })
// ОДИН шаг status; попытка'
mutant 'N1 правило вливания велит дождаться ci-read.sh' 'гонит merge-readiness.sh и landing-precheck.sh и вливает коммитом слияния; ради вливания нельзя' 'гонит merge-readiness.sh и landing-precheck.sh и вливает коммитом слияния, а ты перед стартом сам дождись ci-read.sh код 0; ради вливания нельзя'
mutant 'N8 перепись: ci-read.sh — жди до кода 0' ''"'"'ci-read.sh (рецепт «ЗАПУСК», без ожидания)'"'"'' ''"'"'ci-read.sh (рецепт «ЗАПУСК», жди до кода 0)'"'"''
mutant 'N2 старт: «Закрывай задачи…»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Закрывай задачи полос '"'"' + order.join('"'"', '"'"') + '"'"' сразу. 1) Тело PR'
mutant 'N4 старт: тело дополни вручную' '1) Тело PR — заново генератором (ws#1146), руками не пишется:' '1) Тело PR — заново генератором (ws#1146), затем тело дополни вручную:'
mutant 'N5 status: через минуту вызови status ещё раз' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй; через минуту вызови status ещё раз.'
mutant 'M1 E1: status при коде 2 перезапускает демон' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, не жди; при коде 2 перезапусти демон вливания той же командой.'
mutant 'M2 E5: ready — прочти вердикт CI ещё раз' '— событие ready_for_review заводит полный прогон.' '— событие ready_for_review заводит полный прогон; после перевода прочти вердикт CI ещё раз.'
mutant 'M3 E5: перепись — повторяй ci-read, пока не станет 0' 'Перепись — не основание вливать: вливает только демон.' 'Перепись — не основание вливать: вливает только демон. Чтение CI повторяй, пока код не станет 0.'
twin 'TW2 «Нельзя закрыть задачи до merged»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Нельзя закрыть задачи до merged. 1) Тело PR'
# shellcheck disable=SC2016  # обратные кавычки — текст JS-шаблона, а не подстановка
twin 'TW3 «ci-read.sh больше не зови»' '— событие ready_for_review заводит полный прогон.' '— событие ready_for_review заводит полный прогон; `ci-read.sh` больше не зови.'
twin 'TW4 «не повторяй status»' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, не жди, не повторяй status, демон не перезапускай.'
twin 'TW5 «не пиши тело руками»' '1) Тело PR — заново генератором (ws#1146), руками не пишется:' '1) Тело PR — заново генератором (ws#1146), не пиши тело руками:'
twin 'TW6 демон уже запущен — упоминание, не старт' 'Режим autoland status: PR #'"'"' + asm.pr + '"'"' ('"'"' + (A.repo || '"'"'?'"'"') + '"'"'), демон вливания запущен.' 'Режим autoland status: PR #'"'"' + asm.pr + '"'"' ('"'"' + (A.repo || '"'"'?'"'"') + '"'"'), демон вливания уже запущен шагом start, второй раз его не запускай.'
# Приёмка check-verifier ws#1152 r3: отрицание — лишь вплотную либо из закрытого перечня при своей
# неопределённой форме; маски F4–F8 и «не забудь <глагол>» на каждый класс — указания.
mutant 'F4 старт: «Не забудь дождаться ci-read.sh код 0»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Не забудь дождаться ci-read.sh код 0. 1) Тело PR'
mutant 'F5 старт: «Дождаться ci-read.sh код 0 обязательно — стартовать раньше нельзя»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Дождаться ci-read.sh код 0 обязательно — стартовать раньше нельзя. 1) Тело PR'
mutant 'F6 status: при коде 2 не забудь перезапустить демон' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, не жди; при коде 2 не забудь перезапустить демон вливания той же командой.'
mutant 'F7 старт: «Не забудь закрыть задачи полос»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Не забудь закрыть задачи полос '"'"' + order.join('"'"', '"'"') + '"'"'. 1) Тело PR'
mutant 'F8 перепись: без ожидания; перечитай его трижды' ''"'"'ci-read.sh (рецепт «ЗАПУСК», без ожидания)'"'"'' ''"'"'ci-read.sh (рецепт «ЗАПУСК», без ожидания; перечитай его трижды)'"'"''
mutant 'NZ-E1 ready: не забудь запустить демон вливания' '— событие ready_for_review заводит полный прогон.' '— событие ready_for_review заводит полный прогон; не забудь запустить демон вливания.'
mutant 'NZ-E3 перепись: не забудь закрыть задачи' 'Перепись — не основание вливать: вливает только демон.' 'Перепись — не основание вливать: вливает только демон; не забудь закрыть задачи полос.'
mutant 'NZ-E4 сборка: не забудь написать тело сам' '(код не 0 — status failed, PR не трогать)' '(код не 0 — status failed, PR не трогать; не забудь написать тело сам)'
mutant 'NZ-E5 status: не забудь прочесть CI ci-read.sh' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, демон не перезапускай; не забудь прочесть CI ci-read.sh.'
mutant 'NZ-E8 status: не забудь повторить status' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, демон не перезапускай; не забудь повторить status.'
# r4: запрет из перечня — лишь вплотную к своей форме; «<указание>, <наречие> нельзя» — указание.
mutant 'G1 правило вливания: дождаться ci-read.sh код 0 обязательно, без этого нельзя' 'ради вливания нельзя ждать CI, нельзя читать ci-read, нельзя гнать три гейта'"'"'' 'ради вливания нельзя ждать CI, нельзя читать ci-read, нельзя гнать три гейта; перед стартом дождаться ci-read.sh код 0 обязательно, без этого нельзя'"'"''
mutant 'G2 старт: «Закрыть задачи полос сразу, позже нельзя»' ''"'"' + landRule + '"'"'. 1) Тело PR' ''"'"' + landRule + '"'"'. Закрыть задачи полос '"'"' + order.join('"'"', '"'"') + '"'"' сразу, позже нельзя. 1) Тело PR'
mutant 'G3 status: повторить status обязательно, раньше нельзя' 'Исход не толкуй, не жди, демон не перезапускай.' 'Исход не толкуй, демон не перезапускай; повторить status обязательно, раньше нельзя.'
mutant "старт демона не судится" "if (!alStart || ![0, 3].includes(alStart.code)) return" "if (false) return"
mutant "тело сборки руками (ws#1146)" "тело — ТОЛЬКО вывод генератора (ws#1146), руками не пишется: \`RITUAL_REPO_DIR=" "тело — ровно состав git log база..голова: \`true RITUAL_REPO_DIR="
mutant "демон без отчёта стенда" "' --stand-report ' + STAND + ' --stand-expect ' + STAND_EXP + '\` — он сразу" "'\` — он сразу"
mutant "срок CI-чтения больше 10 мин" "implement: 90, review: 30, mech: 10, ci: 2 }" "implement: 90, review: 30, mech: 10, ci: 60 }"
# ws#1004: пустые ходы.
mutant "план — JSON.parse всего вывода" "  plan = r ? parseJsonTail(r.out) : null" "  try { plan = r ? JSON.parse(r.out) : null } catch (e) { plan = null }"
mutant "план — первый объект, а не хвост" "  try { return obj(JSON.parse(lines[lines.length - 1])) } catch (e) { return null }" "  for (const x of lines) { try { const o = obj(JSON.parse(x)); if (o) return o } catch (e) { /* дальше */ } } return null"
mutant "задание плана без «только последняя строка»" "out (ТОЛЬКО последняя строка .out.json — JSON-объект плана, дословно, без строк CENSUS и пояснений)" "out (содержимое .out.json дословно)"
mutant "правило о файлах снято из преамбулы" $'  FILES_RULE,\n' ""
mutant "правило о файлах снято у исполнителя" "'\\n' + FILES_RULE + ' Твой перечень: '" "'\\n' + ' Твой перечень: '"
mutant "перечни соседей не передаются" "'. Перечни соседей: ' + (neighbours(l) || 'соседей нет')" "'. Перечни соседей: ' + ('соседей нет')"
mutant "соседи — все полосы, включая свою" "lanes.filter(x => x.key !== l.key).map(" "lanes.map("
mutant "hookLog не судится" "const isPath = s => typeof s === 'string' && /^\\/[^\\s]+\$/.test(s)" "const isPath = s => true"
mutant "hookLog не путь после доводки — дальше" "  if (!isPath(impl.hookLog)) return" "  if (false) return"
mutant "report без содержания" "report (содержательный итог: что сделано, какие файлы, исход проверок числами, взятые файлы вне перечня)" "report"
# ws#1053: волна одним проходом.
# Предполёт выпал, карта пустая — полосы идут без неё (форма настоящей регрессии).
mutant "предполёт не зовётся" "const pre = await agent(C + " "const pre = { lanes: lanes.map(l => ({ key: l.key, impact: [], criteria: [] })) } || await agent(C + "
mutant "карта без полосы — раздача идёт" "if (noMap.length) return { ok: false, stage: 'предполёт" "if (false) return { ok: false, stage: 'предполёт"
mutant "предполёт без держателей ведомостей" "ведомости производителя и долгов (живы ли держатели — задача открыта)" "ведомости производителя и долгов"
mutant "предполёт без каталога прав соседа" "копии каталога прав в другом репозитории, " ""
mutant "зависимый другого репозитория — не в эту волну" "его полоса идёт в ЭТУ волну, пин — на ревизию" "его полоса — в следующую волну, пин — на ревизию"
# ws#1058: пин на голову сборки — образа ветки нет в реестре; пункт чужого класса без своей полосы.
mutant "пин на ветку без образа" "пин — на ревизию производителя с опубликованным образом" "пин — на голову сборки производителя"
mutant "пункт чужого класса — без своей полосы" "Пункт чужого класса (консоль — ui-implementer)" "Пункт консоли"
mutant "карта не в задании полосы" "+ mapText(l) + (sqlLane(l)" "+ (sqlLane(l)"
mutant "карта всех полос в задании" "const m = preMap[l.key]; return" "const m = { impact: Object.values(preMap).flatMap(x => x.impact), criteria: Object.values(preMap).flatMap(x => x.criteria) }; return"
mutant "незакрытый пункт не судится" "return preMap[l.key].impact.map((_, i) => i + 1).filter(" "return [].filter("
mutant "«посмотрю потом» — закрытие" "(?:правка\\\\s+\\\\S|не затронуто — потому что\\\\s+\\\\S)" "(?:правка|не затронуто|посмотрю)"
mutant "доводки по карте нет" "  if (gap.length) fix.push(" "  if (false) fix.push("
mutant "незакрытый после доводки — полоса идёт" "  if (gap.length) return { ...out, stage: 'карта влияния: пункты" "  if (false) return { ...out, stage: 'карта влияния: пункты"
mutant "пробной сборки нет" "  if (r.ok) r = await trialIn(l, r)" ""
mutant "красная пробная — полоса идёт" "  if (t && t.code === 1) {" "  if (false) {"
mutant "пробная сборка — отправкой ветки" "\`git push --dry-run origin HEAD:refs/heads/' + l.branch + '\`" "\`git push origin HEAD:refs/heads/' + N + '-trial\`"
mutant "пробная сборка — на имя волны (git отвергнет до хука)" "\`git push --dry-run origin HEAD:refs/heads/' + l.branch + '\`" "\`git push --dry-run origin HEAD:refs/heads/' + N + '\`"
mutant "имитация клиента не зовётся" "    const s1 = await textStep(C + '\\n\\nИмитация клиента ДО кода" "    const s1 = '### ВОЗВРАТ' || await textStep(C + '\\n\\nИмитация клиента ДО кода"
mutant "метрики не пишутся" "await agent(C + '\\n\\nРежим метрики:" "false && await agent(C + '\\n\\nРежим метрики:"
mutant "L4: дочитывание без rerun — кэш вечен (ws#1078)" "журнал своего прогона и верни блок ВОЗВРАТ с фактом. Попытка ' + (A.rerun || 0) + '.'" "журнал своего прогона и верни блок ВОЗВРАТ с фактом. Попытка 0.'"
mutant "L5: итог — простынёй (ws#1078)" "const slim = x => typeof x === 'string' ? (x.length > SLIM_MAX" "const slim = x => typeof x === 'string' ? (false"
mutant "L6: textFile не читается (ws#1078)" "const taskOf = l => l.textFile ?" "const taskOf = l => false ?"
mutant "L11: коммиты рецензенту волны не даны (ws#1078)" "Сообщения коммитов \`' + logRange(" "Сообщения \`git show --stat ' + String("
mutant "L11: диапазон base..base (CV10)" "logRange(A.base || '?', asm.head)" "logRange(A.base || '?', A.base || '?')"
mutant "L11: пустой диапазон — зелёное (CV10)" "') && [ -n \"\$R\" ] && printf" "') && printf"
mutant "L2: стволы продуктов — не в переписи гейтов (ws#1078)" "if (['kacho', 'kaname', 'corelib'].includes(PROD)) GATES.push(" "if (false) GATES.push("
mutant "L2: kacho выпал из перечня стволов (CV5)" "if (['kacho', 'kaname', 'corelib'].includes(PROD))" "if (['kaname', 'corelib'].includes(PROD))"
mutant "L2: corelib выпал из перечня стволов (CV6)" "if (['kacho', 'kaname', 'corelib'].includes(PROD))" "if (['kacho', 'kaname'].includes(PROD))"
mutant "L6: предполёт без taskOf (CV2)" "']: ' + taskOf(l)).join(' | ')" "']: ' + l.text).join(' | ')"
mutant "L6: приёмка без taskOf (CV3)" "(смена публичного контракта либо миграция): ' + taskOf(l)" "(смена публичного контракта либо миграция): ' + l.text"
mutant "L6: перепись поверхности без taskOf (CV4)" "Перепись поверхности ДО кода, полоса ' + l.key + ': ' + taskOf(l)" "Перепись поверхности ДО кода, полоса ' + l.key + ': ' + l.text"
mutant "L5: slim не заходит в массивы (CV9)" " : Array.isArray(x) ? x.map(slim) :" " : Array.isArray(x) ? x :"
mutant "метрики без итога" "return slim({ ...res, metrics: metricsOf() })" "return slim(res)"
mutant "переделка не считается" "impl1st[l.key] ? M.rework++ :" "impl1st[l.key] ? 0 :"
mutant "красный CI не считается" "if (ciState(ci) === 'red') M.ciRed++" ""
mutant "каскад закрывает держателя ведомости" "; КРОМЕ держателей записей ведомостей" ""
mutant "impact снят со схемы исполнителя" "'issues', 'impact', 'report', 'lesson'] }" "'issues', 'report', 'lesson'] }"
mutant "пробного схождения после волны нет (ws#1063)" "const trialConv = epicMr ? await agent(" "const trialConv = false ? await agent("
mutant "CI MR эпика после волны не читается (ws#1063)" "const epicCi = epicMr ? await agent(" "const epicCi = false ? await agent("
mutant "CI MR эпика читается не ci-read.sh (ws#1063)" "recipeRun('ci-read.sh', (A.repo || '?') + ' НОМЕР'" "recipeRun('landing-precheck.sh', (A.repo || '?') + ' НОМЕР'"
mutant "CI MR эпика — с ожиданием (ws#1063)" "без ожидания: код 3 (идёт) — законный исход" "жди окончания прогона"
mutant "схождение до вливания (ws#1063)" "const epicMr = landedOk && " "const epicMr = true && "
mutant "порядок круга не в итоге (ws#1063)" "const redOf = r => ciState(r) === 'red' ? { redRound: RED_ROUND } : {}" "const redOf = r => ({})"
mutant "починки поштучно (ws#1063, ws#1110)" "все корни — исполнителям их классов параллельно, ОДНОЙ сборкой" "каждый корень — своей сборкой"
mutant "CI после каждой починки (ws#1063, ws#1110)" "затем ОДИН CI; два красных CI подряд" "затем CI после каждой починки; два красных CI подряд"
mutant "класс до цитаты (ws#1063)" "класс корня — лишь после дословной цитаты отказа" "класс корня — сразу, цитата потом"
mutant "среда — полосой починки (ws#1063)" "среда с двумя признаками — один перезапуск без полосы" "среда — полоса починки"
mutant "проверка починки — через CI (ws#1110)" "проверка — только бывшее красным на внешнем кластере (stand-report.sh --of)" "проверка — прогоном CI своего PR"
mutant "CI читается до конца заданий (ws#1110)" "CI читается по завершении ВСЕХ заданий (ci-read код 3 при красном и идущих)" "CI читается до первого красного"
mutant "полного прогона перед CI нет (ws#1110)" "всё зелёное — полный прогон на внешнем кластере (stand-report.sh код 0); " ""
mutant "два красных CI — без стопа (ws#1110)" "два красных CI подряд — стоп и разбор паритета" "CI — сколько потребуется"
mutant "стенд не судится (ws#1110)" "if (!stand || stand.code !== 0) return {" "if (false) return {"
mutant "CI при идущем стенде (ws#1110)" "  if (!stand || stand.code !== 3) break" "  break"
mutant "пауза стенда не проверяется (ws#1110)" "if (i > 0 && !(got && Number.isFinite(got.slept) && got.slept + CI_SLEPT_SLACK >= CI_PAUSE_S)) { stand = " "if (false) { stand = "
mutant "отчёт стенда не в посадке (ws#1110)" "' --stand-report ' + STAND + ' --stand-expect ' + STAND_EXP," "'',"
mutant "ожидаемое стенда из отчёта (ws#1110)" " + ' --expect ' + STAND_EXP" ""
mutant "ожидаемое не в посадке (ws#1110)" " + ' --stand-expect ' + STAND_EXP," ","
mutant "ожидаемое стенда — выбор черновика, не ready (ws#1110, паритет с --github-output)" "' --draft false > ' + STAND_EXP" "' > ' + STAND_EXP"
mutant "стенд — до первого красного (ws#1110)" "без остановки на первом красном; набор" "до первого красного; набор"
mutant "красный стенд без порядка круга (ws#1110)" "...(stand && stand.code === 1 ? { redRound: RED_ROUND } : {})" "...({})"
mutant "перепись гейтов не зовётся (ws#1071)" "const gates = await agent(C + " "const gates = null && await agent(C + "
mutant "перепись гейтов без branch-audit (ws#1071)" ", 'branch-audit.sh']" "]"
mutant "перепись гейтов чинит по одному (ws#1071)" "прогони КАЖДЫЙ гейт по разу, ничего не чини" "прогони первый красный гейт и почини его"
mutant "таблица гейтов не в итоге посадки (ws#1071)" "const gatesOf = () => ({ gates:" "const gatesOf = () => ({ gatesX:"
mutant "ответ без ВОЗВРАТ принят (ws#1071)" "const hasRet = t => typeof t === 'string' && t.includes(RET_MARK)" "const hasRet = t => typeof t === 'string'"
mutant "без ВОЗВРАТ — повтора дочитыванием нет (ws#1071)" "  return hasRet(b) ? b : null" "  return a"
mutant "не-выполнилось подставлено дальше (ws#1071)" "    if (!s1) return noRet(out, l, 'client-sim')" "    if (false) return noRet(out, l, 'client-sim')"
twin "дочитывание: формулировка (ws#1071)" "дочитай .rc и журнал своего прогона и верни" "дочитай .rc и журнал своего прогона, затем верни"
twin "схождение: формулировка запрета правки (ws#1063)" "Ничего не правь. Запись — ' + R + '/trial-convergence.md" "Ничего не правь в дереве. Запись — ' + R + '/trial-convergence.md"
mutant "строка head не порождается (ws#1191)" "const headLines = (l, ds, stack) => (ds && ds.length ?" "const headLines = (l, ds, stack) => (false ?"
mutant "код предусловия головы не судится (ws#1191)" "  if (p && p.code === 0) return null" "  return null"
mutant "стенд не опознан (ws#1191)" "const standLane = l => STAND_CLASS.includes(l.class) || l.agent === 'deploy-engineer'" "const standLane = l => false"
mutant "голова сводки не в предусловии (ws#1191)" ".concat(stack ? ['head ' + ghRepo(l.repo) + ' ' + stack.branch + ' ' + stack.head] : [])" ""
mutant "предусловия раздачи не судятся (ws#1272)" "if (!it || it.code !== 0) gateBlock[x.key]" "if (false) gateBlock[x.key]"
mutant "нераздаваемая полоса раздаётся (ws#1272)" "  if (gateBlock[k]) return (done[k] =" "  if (false) return (done[k] ="
mutant "строка базы не порождается (ws#1272)" "const premLines = l => ['branch ' + ghRepo(l.repo) + ' ' + (l.base || A.base)]" "const premLines = l => []"
mutant "задачи полосы не в предусловии (ws#1272)" ".concat((l.issues || []).map(i => issueLine(l, i)), l.premise || [])" ".concat(l.premise || [])"
mutant "кавычки строки не экранированы (ws#1272)" "const shq = s => \"'\" + String(s).replace(/'/g, \"'\\\\''\") + \"'\"" "const shq = s => \"'\" + String(s) + \"'\""
mutant "зависимая от нераздаваемой в предполёте (ws#1272)" "{ held.add(l.key); more = true }" "{ }"
mutant "текст автору приёмки не судится (ws#1271)" "  if (tierOf[l.key].steps.includes('acceptance(<=2)')) gateItems.push(" "  if (false) gateItems.push("
mutant "meta не литерал: вызов" "name: 'wave'," "name: ['wa', 've'].join(''),"
mutant "meta не литерал: шаблонная строка" "name: 'wave'," "name: \`wave\`,"
echo
echo "wave-template-inject: контроль код $rc; мутантов и близнецов $((pass + fail)), сошлось $pass (мутант красный, близнец молчит), разошлось $fail"
[ "$rc" -eq 0 ] && [ "$fail" -eq 0 ]
