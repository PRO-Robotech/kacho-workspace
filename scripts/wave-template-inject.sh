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
#   R0 — ни одного рецензента; механика — модель haiku, усилие low;
#   R1 — ровно один wave-reviewer на сборку, ролей полосы нет;
#   R2 — приёмка, перепись поверхности, роль уровня, рецензент волны,
#        landing-reviewer — по разу;
#   CI «идёт» дважды — ждать, ошибкой не считать;
#   предпроверка полосы красная, голова та же — повтора нет, строка счётчика
#   ошибок (executor-mechanics); голова новая — повтор и зелёное;
#   «уже сделано» исполнителя — не провал;
#   шаг уровня, шаблону неизвестный, — остановка на плане, а не пропуск;
#   corelib разный — полоса перепина первой и повтор плана;
#   причины тела PR — правка тела механиком и повтор landing-precheck;
#   вердикт роли не на сведённой голове полосы — остановка, sha не подменяется;
#   одна роль вернула, другая приняла прежнюю голову — повтор только
#   вернувшей (§8а п.8), sha принявшей не переписан, полоса стоит до сборки:
#   новую голову принявшая не видела (ws#933, опыт check-verifier r3); близнец —
#   одна роль уровня вернула и приняла дельту — полоса идёт дальше.
#   номер PR сборки — целое ≥ 1 и в схеме, и в теле: нет поля, 0, строка, адрес —
#   остановка на сборке с причиной, «PR #undefined» не уходит ни в одно задание
#   (ws#935); близнец — pr 7 доходит до CI и посадки;
#   вердикт роли — только поле verdict словаря accept | return | void: «✅» в
#   report без поля — не принят; void — не принят;
#   CI «идёт» и после ожидания, landing-precheck только с CI-PENDING — state
#   running, а не провал; близнецы — красный CI и CI-PENDING с другой причиной —
#   state failed;
#   полоса с deps (ws#938) — сводка голов deps зовётся после того, как dep
#   прошёл, и получает его ИТОГОВУЮ голову; исполнитель заводит ветку от головы
#   сводки, предпроверка судит её как базу; независимая полоса стартует сразу,
#   не дожидаясь чужого слоя; dep не прошёл — зависимая не начата, соседи идут;
#   сводка конфликтует либо не содержит головы dep — остановка с причиной,
#   исполнитель не зван, сборки нет; сводки сняты шагом вливания; близнец —
#   полоса без deps сводки не зовёт, база — база волны; флаг crossRepo задания
#   доходит до плана, без флага его в плане нет.
#
# ИНЪЕКЦИИ — без довода проба после контроля прогоняет МУТАНТОВ шаблона (по
# одной правке, у каждой — своё свойство) и требует, чтобы каждый покраснел.
#
# usage: wave-template-inject.sh [<шаблон.js>]   (с доводом — только контроль)
# Коды: 0 — все утверждения сошлись (и все мутанты красные); 1 — нет;
#       2 — нет node, шаблона или вывода плана: вердикта нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${1:-$HERE/../.claude/workflows/wave.js}"
command -v node > /dev/null 2>&1 || { echo "wave-template-inject: VOID — нет node" >&2; exit 2; }
command -v jq > /dev/null 2>&1 || { echo "wave-template-inject: VOID — нет jq" >&2; exit 2; }
[ -r "$TPL" ] || { echo "wave-template-inject: VOID — шаблона нет: $TPL" >&2; exit 2; }
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

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
planout "$W/r2.json" '[{key:"M",repo:"kacho-workspace",paths:["services/x/migrations/0001.sql"]}]'
planout "$W/r2two.json" '[{key:"M",repo:"kacho-workspace",paths:["services/x/migrations/0001.sql","services/x/internal/authz/a.go"]}]'
jq -e '.lanes[0].roles | length >= 2' "$W/r2two.json" > /dev/null || { echo "wave-template-inject: VOID — план R2 без двух ролей: предпосылка сценария возврата одной роли" >&2; exit 2; }

cat > "$W/probe.mjs" <<'JS'
import fs from 'node:fs'
import vm from 'node:vm'
const [tplPath, dir] = process.argv.slice(2)
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
async function run(sc) {
  const calls = []
  const heads = {}, cnt = {}
  const take = (key, def) => { const q = (sc[key] || []); const i = (cnt[key] = (cnt[key] || 0) + 1) - 1; return i < q.length ? q[i] : def() }
  const agent = async (prompt, opts = {}) => {
    const label = opts.label || ''
    calls.push({ label, agentType: opts.agentType, model: opts.model, effort: opts.effort, schema: opts.schema, prompt })
    const lane = label.split(':').pop()
    if (label.startsWith('mech:plan:')) { const o = take('plan', () => P('r0.json')); return { code: o.code, out: JSON.stringify(o), reasons: (o.reasons || []).map(r => r.code), head: '' } }
    if (label.startsWith('impl:')) { const r = take('impl:' + lane, () => ({ status: 'done', head: H(lane, cnt['impl:' + lane]) })); heads[lane] = r.head; return { branch: 'b-' + lane, copy: '/ws/tmp/c-' + lane, hookLog: '/ws/tmp/push.log', issues: ['o/r#1'], report: 'r', ...r } }
    if (label.startsWith('mech:stack:')) { const r = take('stack:' + lane, () => ({ status: 'done', head: H('S' + lane, 0) })); heads['stack:' + lane] = r.head; return { branch: '9-stack-' + lane.toLowerCase(), contains: Object.keys(heads).filter(k => !k.startsWith('stack:')).map(k => heads[k]), conflicts: [], report: 'r', ...r } }
    if (label.startsWith('mech:precheck:')) return { out: '', head: heads[lane], reasons: [], ...take('pre:' + lane, () => ({ code: 0 })) }
    if (label.startsWith('review-wave')) return { verdict: 'accept', sha: HW, blocking: [], report: 'r', ...take('wave', () => ({})) }
    if (label.startsWith('review-landing')) return { verdict: 'accept', sha: HW, blocking: [], report: 'r' }
    if (sc.ret && label === 'review-' + sc.ret + ':' + lane) return { verdict: 'return', sha: heads[lane], blocking: ['x'], report: 'r' }
    if (label.startsWith('review-') || label.startsWith('acceptance-review-')) return { verdict: 'accept', sha: sc.staleRole ? H('old', 0) : heads[lane] || '', blocking: [], report: 'r' }
    if (label.startsWith('mech:assemble:')) return { status: 'done', head: HW, copy: '/ws/tmp/w', pr: 7, conflicts: [], report: 'r', ...take('asm', () => ({})) }
    if (label.startsWith('mech:ci:')) return { head: HW, total: 3, passed: 3, report: 'r', ...take('ci', () => ({ state: 'green' })) }
    if (label.startsWith('mech:landing:')) return { out: '', head: HW, ...take('land', () => ({ code: 0, reasons: [] })) }
    if (label.startsWith('mech:merge')) return { code: 0, out: 'MERGED; доля 0.0 %', reasons: [], head: 'e'.repeat(40) }
    if (label.startsWith('mech:')) return { code: 0, out: '', reasons: [], head: '' }
    return 'отчёт записан'
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
const idx = (calls, label) => calls.findIndex(c => c.label === label)
const prm = (calls, label) => (calls.find(c => c.label === label) || {}).prompt || ''
const by = (calls, f) => calls.filter(f).length
const mechOk = calls => calls.filter(c => c.label.startsWith('mech:')).every(c => c.model === 'haiku' && c.effort === 'low')

console.log('== R0: без рецензентов, механика дешёвой моделью')
let r = await run({ args, plan: [P('r0.json')] })
ok(r.res.ok === true, 'волна R0 влита', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => REVIEWERS.includes(c.agentType)) === 0, 'ни одного рецензента и приёмщика')
ok(by(r.calls, c => c.label.startsWith('mech:precheck:')) === 2, 'lane-precheck — по полосе')
ok(mechOk(r.calls) && by(r.calls, c => c.label.startsWith('mech:')) > 0, 'механика — haiku, усилие low')
ok(!/--reviews/.test((r.calls.find(c => c.label.startsWith('mech:landing:')) || {}).prompt || 'x'), 'без рецензентов landing-precheck зовётся без --reviews')

console.log('== R1: один рецензент на собранную волну')
r = await run({ args: argsDep, plan: [P('r1.json')] })
ok(r.res.ok === true, 'волна R1 влита', JSON.stringify(r.res).slice(0, 300))
ok(by(r.calls, c => c.agentType === 'wave-reviewer') === 1, 'wave-reviewer ровно один на волну')
ok(by(r.calls, c => REVIEWERS.includes(c.agentType) && c.agentType !== 'wave-reviewer') === 0, 'ролей полосы и landing-reviewer нет')
const iA = r.calls.findIndex(c => c.label === 'impl:A'), iB = r.calls.findIndex(c => c.label === 'impl:B'), pA = r.calls.findIndex(c => c.label === 'mech:precheck:A')
ok(iA >= 0 && iB > pA, 'B (зависит от A) начат после предпроверки A — слои плана')
ok(/--reviews/.test((r.calls.find(c => c.label.startsWith('mech:landing:')) || {}).prompt || ''), 'вердикт волны передан landing-precheck')

console.log('== R2: полный набор')
r = await run({ args: { ...args, lanes: [{ key: 'M', repo: 'kacho-workspace', agent: 'migration-writer', branch: '9-m', text: 't' }] }, plan: [P('r2.json')] })
ok(r.res.ok === true, 'волна R2 влита', JSON.stringify(r.res).slice(0, 300))
for (const t of ['acceptance-author', 'db-architect-reviewer', 'wave-reviewer', 'landing-reviewer']) ok(by(r.calls, c => c.agentType === t) === 1, t + ' — один раз')
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
ok(prm(r.calls, 'mech:merge').includes('9-stack-b'), 'временная сводка снимается шагом вливания')
r = await run({ args: argsDepC, plan: [P('r1c.json')] })
ok(r.res.ok === true && idx(r.calls, 'impl:C') >= 0 && idx(r.calls, 'impl:C') < idx(r.calls, 'mech:precheck:A'), 'независимая C стартует сразу, не дожидаясь A', JSON.stringify(r.res).slice(0, 200))
// A дольше C (доводка предпроверки): D (от C) обязана начаться, не дожидаясь A —
// слой плана порядок deps называет, но чужую полосу ждать не велит.
const argsDepD = { ...args, lanes: [...argsDepC.lanes, { key: 'D', repo: 'kacho-workspace', agent: 'docs-writer', branch: '9-d', text: 't', deps: ['C'] }] }
r = await run({ args: argsDepD, plan: [P('r1d.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }] })
ok(r.res.ok === true && idx(r.calls, 'mech:stack:D') >= 0 && idx(r.calls, 'mech:stack:D') < r.calls.map(c => c.label).lastIndexOf('mech:precheck:A'), 'D (от C) стартует, когда прошла C, не дожидаясь A чужого слоя', JSON.stringify(r.calls.map(c => c.label)).slice(0, 400))
ok(prm(r.calls, 'mech:stack:D').includes('9-c@') && !prm(r.calls, 'mech:stack:D').includes('9-a@'), 'в сводку D — только её deps (C), чужая A не вливается')
r = await run({ args: argsDepC, plan: [P('r1c.json')], 'pre:A': [{ code: 2, reasons: [] }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'impl:B' || c.label === 'mech:stack:B') === 0 && /не начата: deps A/.test(((r.res.lanes || {}).B || {}).stage || '') && by(r.calls, c => c.label === 'mech:precheck:C') === 1 && by(r.calls, c => c.label.startsWith('mech:assemble:')) === 0, 'A не прошёл — B не начата (причина названа), C прошла, сборки нет', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'conflict', head: '', conflicts: ['go.mod'] }] })
ok(r.res.ok === false && r.res.stage === 'полосы' && /конфликт в go\.mod/.test(((r.res.lanes || {}).B || {}).stage || '') && by(r.calls, c => c.label === 'impl:B') === 0 && by(r.calls, c => c.label.startsWith('mech:assemble:')) === 0, 'сводка конфликтует — остановка с путём, исполнитель B не зван, сборки нет', JSON.stringify(r.res).slice(0, 300))
r = await run({ args: argsDep, plan: [P('r1.json')], 'stack:B': [{ status: 'done', head: hS, contains: [] }] })
ok(r.res.ok === false && /нет голов 9-a@/.test(((r.res.lanes || {}).B || {}).stage || '') && by(r.calls, c => c.label === 'impl:B') === 0, 'сводка «готова», но головы A в ней нет — остановка, исполнитель не зван', JSON.stringify(r.res).slice(0, 300))

r = await run({ args: { ...args, crossRepo: true }, plan: [P('r0.json')] })
ok(prm(r.calls, 'mech:plan:1').includes('"crossRepo":true'), 'явный crossRepo задания уходит в план (межрепозиторная сверка — по флагу)')
r = await run({ args, plan: [P('r0.json')] })
ok(!prm(r.calls, 'mech:plan:1').includes('crossRepo'), 'близнец: без флага в плане его нет — сосед на плане одного репозитория не судится')

console.log('== «идёт» и «уже сделано» — не провал')
r = await run({ args, plan: [P('r0.json')], ci: [{ state: 'running' }, { state: 'running' }, { state: 'green' }] })
ok(r.res.ok === true && by(r.calls, c => c.label.startsWith('mech:ci:')) === 3, 'CI идёт дважды — ждать, затем зелёное')
ok(by(r.calls, c => c.label.startsWith('mech:err:')) === 0, 'ожидание CI ошибкой не записано')
r = await run({ args, plan: [P('r0.json')], 'impl:A': [{ status: 'already-done', head: H('A', 9) }] })
ok(r.res.ok === true, '«уже сделано» исполнителя — полоса идёт дальше')

console.log('== повтор — только при новой голове')
r = await run({ args, plan: [P('r0.json')], 'pre:A': [{ code: 1, reasons: ['UNCOMMITTED'] }], 'impl:A': [{ status: 'done', head: H('A', 1) }, { status: 'done', head: H('A', 1) }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:precheck:A') === 1, 'голова не сменилась — предпроверка не повторена')
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

console.log('== посадка — по коду landing-precheck')
r = await run({ args, plan: [P('r0.json')], land: [{ code: 1, reasons: ['BODY-MISSING-COMMIT'] }, { code: 0, reasons: [] }] })
ok(r.res.ok === true && by(r.calls, c => c.label === 'mech:pr-edit') === 1, 'причина тела — правка механиком и повтор')
r = await run({ args, plan: [P('r0.json')], land: [{ code: 1, reasons: ['MERGE-READINESS'] }] })
ok(r.res.ok === false && by(r.calls, c => c.label === 'mech:merge') === 0, 'merge-readiness не 0 — вливания нет')

console.log('== номер PR — целое ≥ 1, иначе остановка с причиной (ws#935)')
for (const [name, v] of [['нет поля', { pr: undefined }], ['0', { pr: 0 }], ['строка «—»', { pr: '—' }], ['адрес', { pr: 'https://github.com/o/r/pull/7' }]]) {
  r = await run({ args, plan: [P('r1.json')], asm: [v] })
  const after = by(r.calls, c => c.agentType === 'wave-reviewer' || c.label.startsWith('mech:ci:') || c.label.startsWith('mech:landing:') || c.label.startsWith('mech:merge'))
  const undef = r.calls.some(c => /PR #(undefined|0\b|—|null)/.test(c.prompt || ''))
  ok(r.res.ok === false && r.res.state === 'failed' && /номер PR не целое/.test(r.res.stage || '') && after === 0 && !undef, 'pr ' + name + ' — остановка на сборке, рецензента, CI и посадки нет, «PR #undefined» не подставлен', JSON.stringify(r.res).slice(0, 200))
}
r = await run({ args, plan: [P('r1.json')] })
const prSchema = (((r.calls.find(c => c.label.startsWith('mech:assemble:')) || {}).schema || {}).properties || {}).pr || {}
const revSchema = (((r.calls.find(c => c.label === 'review-wave') || {}).schema || {}).properties || {}).verdict || {}
ok(prSchema.type === 'integer' && prSchema.minimum === 1, 'схема сборки требует pr целым ≥ 1', JSON.stringify(prSchema))
ok(JSON.stringify(revSchema.enum) === JSON.stringify(['accept', 'return', 'void']), 'словарь вердикта роли закрыт: accept | return | void', JSON.stringify(revSchema))
ok(r.res.ok === true && r.calls.filter(c => c.label.startsWith('mech:ci:') || c.label.startsWith('mech:landing:')).every(c => /PR #7\b|\s7\s/.test(c.prompt)), 'близнец: pr 7 — номер идёт в CI и посадку')

console.log('== вердикт рецензента — только поле verdict')
r = await run({ args, plan: [P('r1.json')], wave: [{ verdict: undefined, report: '✅ принято' }] })
ok(r.res.ok === false && by(r.calls, c => c.label.startsWith('mech:merge')) === 0, 'нет поля verdict, в тексте «✅ принято» — не принят, вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r1.json')], wave: [{ verdict: 'void', report: 'прогон недействителен' }] })
ok(r.res.ok === false && by(r.calls, c => c.label.startsWith('mech:ci:')) === 0, 'verdict void — не принят, CI не зовётся')

console.log('== «идёт» после ожидания — состояние, а не провал')
r = await run({ args, plan: [P('r0.json')], ci: Array(12).fill({ state: 'running' }) })
ok(r.res.ok === false && r.res.state === 'running' && r.res.pr === 7 && by(r.calls, c => c.label.startsWith('mech:merge')) === 0 && by(r.calls, c => c.label.startsWith('mech:err:')) === 0, 'CI идёт все 12 ожиданий — state running, ошибки и вливания нет', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], ci: [{ state: 'red' }] })
ok(r.res.ok === false && r.res.state === 'failed', 'близнец: CI красный — state failed')
r = await run({ args, plan: [P('r0.json')], land: [{ code: 1, reasons: ['CI-PENDING'] }, { code: 1, reasons: ['CI-PENDING'] }] })
ok(r.res.ok === false && r.res.state === 'running' && by(r.calls, c => c.label.startsWith('mech:merge')) === 0, 'landing-precheck: только CI-PENDING и после повтора — state running, не провал', JSON.stringify(r.res).slice(0, 200))
r = await run({ args, plan: [P('r0.json')], land: [{ code: 1, reasons: ['CI-PENDING'] }, { code: 1, reasons: ['CI-PENDING', 'MERGE-READINESS'] }] })
ok(r.res.ok === false && r.res.state === 'failed', 'близнец: CI-PENDING и MERGE-READINESS — state failed')

console.log(`RESULT ${pass} ${fail}`)
process.exit(fail ? 1 : 0)
JS

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
    if node "$W/probe.mjs" "$f" "$W" > "$W/mut.out" 2>&1; then
        echo "  [FAIL] мутант «$1» выжил" >&2; fail=$((fail + 1))
    elif grep -q '^  \[FAIL\]' "$W/mut.out" && grep -q '^RESULT' "$W/mut.out"; then
        echo "  [OK]   мутант «$1» красный: $(grep -m1 '^  \[FAIL\]' "$W/mut.out" | sed 's/^  \[FAIL\] //' | cut -c1-90)"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» упал не утверждением: $(head -c 200 "$W/mut.out")" >&2; fail=$((fail + 1))
    fi
}
echo "== инъекции: мутанты шаблона"
mutant "механика на полной модели" "model: 'haiku', effort: 'low', " ""
mutant "повтор на той же голове" "if (impl.head === prev && impl.status !== 'already-done')" "if (false)"
mutant "«идёт» — провал" "if (!ci || ci.state !== 'running') break" "break"
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
mutant "CI идёт после ожидания — провал" "if (ci && ci.state === 'running' && ci.head === asm.head) return" "if (false) return"
mutant "CI-PENDING посадки — провал" "if (lp && lp.code === 1 && (lp.reasons || []).length && lp.reasons.every(x => x === 'CI-PENDING')) return" "if (false) return"
mutant "вердикт волны — по значку в тексте" "if (!wr || wr.verdict !== 'accept')" "if (!wr || !(wr.verdict === 'accept' || /✅/.test(wr.report || '')))"
mutant "зависимая — от базы волны, а не от сводки" "' от ' + (stack ? 'сводки deps '" "' от ' + (false ? 'сводки deps '"
mutant "предпроверка зависимой — от базы волны" "(stack ? stack.head : (l.base || A.base))" "(l.base || A.base)"
mutant "deps не ожидаются" "const deps = await Promise.all((l.deps || []).map(launch))" "const deps = []"
mutant "независимая ждёт чужой слой" "await Promise.all(layers.flat().map(launch))" "for (const k of layers.flat()) await launch(k)"
mutant "dep не прошёл — зависимая всё равно идёт" "if (notReady.length) r =" "if (false) r ="
mutant "конфликт сводки не останавливает" "    if (!st || st.status === 'conflict' || !['done', 'already-done'].includes(st.status) || !sha40(st.head) || missing.length) {" "    if (false) {"
mutant "голова dep вне сводки не судится" "|| !sha40(st.head) || missing.length) {" "|| !sha40(st.head)) {"
mutant "сводка не снимается при вливании" "(stacks.length ? ' и временные сводки deps ' + stacks.join(', ') : '')" "''"
mutant "crossRepo задания не доходит до плана" "crossRepo: A.crossRepo === true || undefined," ""
mutant "meta не литерал: вызов" "name: 'wave'," "name: ['wa', 've'].join(''),"
mutant "meta не литерал: шаблонная строка" "name: 'wave'," "name: \`wave\`,"
echo
echo "wave-template-inject: контроль код $rc; мутантов $((pass + fail)), красных $pass, выживших $fail"
[ "$rc" -eq 0 ] && [ "$fail" -eq 0 ]
