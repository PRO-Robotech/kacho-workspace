export const meta = {
  name: 'wave',
  description: 'Волна по уровням риска: план скриптом, полосы по шагам своего уровня, сборка, один рецензент на волну, CI, предпроверка посадки скриптом, вливание и каскад',
  whenToUse: 'Любая волна полос kacho, kaname, corelib или воркспейса. args: {repo, wave, epic, base, ws?, targets?, crossRepo?, lanes:[{key, repo, agent, tier?, roles?, branch, deps?, text, ctx?, issues?, paths?, dir?}]}',
  phases: [
    { title: 'План', detail: 'plan-precheck.sh: уровни, слои, corelib, пересечения' },
    { title: 'Полосы', detail: 'шаги уровня из lane-tier.sh; зависимая — от сводки голов deps; lane-precheck.sh до ревью' },
    { title: 'Сборка', detail: 'сведение, рецензент волны, CI' },
    { title: 'Посадка', detail: 'landing-precheck.sh, вливание, каскад, счётчик ошибок' },
  ],
}
// ЕДИНСТВЕННЫЙ шаблон волны (решение владельца 2026-10-06, «Да, по уровням»;
// база диспетчера §8б). Исправленная ошибка оркестровки правится ЗДЕСЬ, а не в
// разовом сценарии. Свойства держит scripts/wave-template-inject.sh:
//  - шаги полосы берутся из вывода plan-precheck.sh (а тот — из lane-tier.sh);
//    своего соответствия «уровень → шаги» здесь нет;
//  - R0 — без рецензентов; R1 — один wave-reviewer на СОБРАННУЮ волну; R2 — роли
//    полосы, рецензент волны и landing-reviewer;
//  - состояние переходит только по ФАКТУ скрипта (lane-precheck, landing-precheck,
//    сверка головы на origin), а не по слову агента;
//  - передача — через файлы: отчёт шага в <WS>/tmp/wave-<N>/<полоса>/<шаг>.md, в
//    задание следующего идёт путь, а не пересказ;
//  - «идёт», «уже сделано», «нечего отправлять» — не провал; повтор шага — только
//    при НОВОЙ голове;
//  - механика (скрипты, git, трекер, чтение CI) — дешёвой моделью;
//  - возврат не из-за кода — строкой wave-errors.sh (часы), доля в итоге.
//  - номер PR сборки — целое ≥ 1 (схема и проверка), иначе остановка с причиной;
//    вердикт роли — только поле verdict (accept | return | void);
//  - итог несёт state: running (CI ещё идёт — не провал) | failed;
//  - полоса с deps стартует, когда ВСЕ её deps прошли (отправлены, предпроверка
//    код 0, ревью уровня), и её ветка заводится от временной сводки их голов:
//    ветка `<N>-stack-<ключ>` от свежей базы, головы deps — коммитами слияния,
//    без переписывания; база её предпроверки — голова сводки (BASE-NOT-ANCESTOR
//    lane-precheck судит, что код предшественников в ветке есть). Сводка
//    конфликтует или не содержит головы dep — остановка с причиной, исполнитель
//    не зовётся (ws#938). Независимые полосы идут сразу, не ожидая чужого слоя.
const A = args || {}
const WS = A.ws || '/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace'
const N = String(A.wave || '')
const D = WS + '/tmp/wave-' + N
const HOMES = 'KACHO_HOME_KACHO=' + WS + '/project/kacho KACHO_HOME_KANAME=' + WS + '/project/kaname KACHO_HOME_CORELIB=' + WS + '/project/corelib'
const MECH = { model: 'haiku', effort: 'low', agentType: 'git-operator' }
const C = [
  'Волна ' + N + ' (' + (A.repo || '?') + ', база ' + (A.base || '?') + ', эпик ' + (A.epic || '?') + '). Шаблон .claude/workflows/wave.js.',
  'ПРАВИЛА: хук отправки не обходить; гейты не ослаблять; подпись pointpu; трейлеры и строки атрибуции НЕ СТАВИТЬ НИКОГДА; нельзя --no-verify, --force, --admin, reset, rebase, squash.',
  'Тяжёлое — через слот ~/.cache/heavy-slots/slot{1..3}.lock (flock). Копии — только под ' + WS + '/tmp/ (основную не трогать, ws#923). Отправка воркспейса — с ' + HOMES + '.',
  'ПЕРЕДАЧА ЧЕРЕЗ ФАЙЛЫ: полный отчёт шага пиши в названный файл, первой строкой `step-start: <date -u +%FT%TZ>`; в ответ — только поля схемы.',
  '«Идёт», «уже сделано», «нечего отправлять» — законные исходы, не провал: верни их своим статусом.',
].join('\n')
const S_MECH = { type: 'object', properties: { code: { type: 'number' }, out: { type: 'string' }, reasons: { type: 'array', items: { type: 'string' } }, head: { type: 'string' } }, required: ['code', 'out', 'reasons', 'head'] }
const S_IMPL = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'nothing-to-push', 'blocked', 'failed'] }, branch: { type: 'string' }, head: { type: 'string' }, copy: { type: 'string' }, hookLog: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['status', 'branch', 'head', 'copy', 'hookLog', 'issues', 'report'] }
// Вердикт роли — ТОЛЬКО поле verdict закрытого словаря (accept | return | void —
// «прогон недействителен»); значок или слово в report не читаются нигде (класс 7).
const S_REV = { type: 'object', properties: { verdict: { type: 'string', enum: ['accept', 'return', 'void'] }, sha: { type: 'string' }, blocking: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['verdict', 'sha', 'blocking', 'report'] }
const S_ASM = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'conflict', 'failed'] }, head: { type: 'string' }, copy: { type: 'string' }, pr: { type: 'integer', minimum: 1 }, conflicts: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['status', 'head', 'copy', 'pr', 'conflicts', 'report'] }
const S_STACK = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'conflict', 'failed'] }, branch: { type: 'string' }, head: { type: 'string' }, contains: { type: 'array', items: { type: 'string' } }, conflicts: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['status', 'branch', 'head', 'contains', 'conflicts', 'report'] }
const S_CI = { type: 'object', properties: { state: { type: 'string', enum: ['green', 'red', 'running', 'not_run', 'unread'] }, head: { type: 'string' }, total: { type: 'number' }, passed: { type: 'number' }, report: { type: 'string' } }, required: ['state', 'head', 'total', 'passed', 'report'] }
const sha40 = s => (typeof s === 'string' && /^[0-9a-f]{40}$/.test(s)) ? s : ''
const rep = (lane, step) => D + '/' + lane + '/' + step + '.md'
const errors = []
// Счётчик ошибок оркестровки: класс из закрытого словаря wave-errors.sh, часы —
// от step-start файла отчёта упавшего шага до момента записи.
const err = async (cls, lane, step, note) => {
  errors.push({ cls, lane, step })
  await agent(C + '\n\nРежим счётчик: часы = (сейчас − step-start в ' + rep(lane, step) + ') / 3600, округли до 0.01 (нет файла — 0.1). Выполни `bash ' + WS + '/scripts/wave-errors.sh add ' + N + ' ' + cls + ' <часы> ' + lane + ' ' + step + ' ' + JSON.stringify(note).slice(0, 300) + '`. Верни code, out (вывод), reasons [], head "".', { ...MECH, label: 'mech:err:' + lane, phase: 'Посадка', schema: S_MECH })
}
const mechanicsReasons = new Set(['UNCOMMITTED', 'HEAD-NOT-ON-ORIGIN', 'HEAD-DIVERGED', 'HOOK-LOG-MISSING', 'HOOK-HEAD-MISMATCH', 'HOOK-RC', 'HOOK-NOT-GREEN', 'DOD-PROOF-MISSING', 'ISSUES-NONE', 'MAIN-COPY'])
const bodyReasons = new Set(['TITLE-FORM', 'TITLE-HEAD-NUMBER', 'BODY-MISSING-COMMIT', 'BODY-FOREIGN-TASK', 'ATTRIBUTION', 'CLOSES-WITHOUT-PROOF'])

// ── План ────────────────────────────────────────────────────────────────
phase('План')
const runPlan = async (lanes, round) => {
  const plan = { wave: N, targets: A.targets || {}, crossRepo: A.crossRepo === true || undefined, lanes: lanes.map(l => ({ key: l.key, repo: l.repo, dir: l.dir || '', base: l.base || A.base, head: l.head || undefined, paths: l.paths || undefined, deps: l.deps || [], declared: l.tier || undefined, repin: l.repin || undefined })) }
  return agent(C + '\n\nРежим план: запиши ровно этот JSON в ' + D + '/plan-' + round + '.json: ' + JSON.stringify(plan) + '\nВыполни `bash ' + WS + '/scripts/wave-errors.sh open ' + N + '` и `bash ' + WS + '/scripts/plan-precheck.sh ' + D + '/plan-' + round + '.json --json > ' + D + '/plan-' + round + '.out.json`. Верни code (код plan-precheck), out (содержимое .out.json дословно), reasons (коды причин из него), head "".', { ...MECH, label: 'mech:plan:' + round, phase: 'План', schema: S_MECH })
}
let lanes = (A.lanes || []).map(l => ({ ...l }))
let plan = null
for (let round = 1; round <= 2; round++) {
  const r = await runPlan(lanes, round)
  try { plan = r ? JSON.parse(r.out) : null } catch (e) { plan = null }
  if (!plan) return { ok: false, stage: 'план', why: 'вывод plan-precheck не разобран — вердикта нет (код 2, не «годен»)' }
  const auto = plan.autoRepin || []
  const onlySkew = (plan.reasons || []).every(x => x.code === 'CORELIB-SKEW')
  if (plan.code === 1 && auto.length && onlySkew && round === 1) {
    for (const a of auto) {
      const key = 'repin-' + a.repo
      lanes = lanes.map(l => l.repo === a.repo ? { ...l, deps: [...(l.deps || []), key] } : l)
      lanes.unshift({ key, repo: a.repo, agent: 'go-implementer', branch: N + '-repin-corelib-' + a.repo, paths: ['go.mod', 'go.sum'], repin: 'corelib', deps: [], dir: (A.targets && A.targets[a.repo] && A.targets[a.repo].dir) || '', text: 'Перепин corelib в ' + a.repo + ' с ' + a.from + ' на ' + a.to + ' (plan-precheck CORELIB-SKEW): go.mod/go.sum, сборка и тесты зелёные.' })
    }
    log('corelib разный: полоса перепина заведена первой (' + auto.map(a => a.repo + ' ' + a.from + '→' + a.to).join(', ') + ')')
    continue
  }
  if (plan.code !== 0) return { ok: false, stage: 'план', code: plan.code, reasons: plan.reasons, voids: plan.voids }
  break
}
const tierOf = {}
for (const p of plan.lanes || []) tierOf[p.key] = p
const KNOWN = new Set(['acceptance(<=2)', 'surface-census', 'implementer', 'implementer-tdd', 'lane-precheck', 'roles', 'wave-reviewer', 'ci', 'landing-reviewer'])
for (const l of lanes) {
  const t = tierOf[l.key]
  if (!t) return { ok: false, stage: 'план', why: 'полоса ' + l.key + ' без уровня в выводе plan-precheck' }
  const unknown = t.steps.filter(s => !KNOWN.has(s))
  if (unknown.length) return { ok: false, stage: 'план', why: 'шаги ' + unknown.join(',') + ' шаблону неизвестны — правка шаблона, а не пропуск шага' }
}

// Имя временной сводки — по правилу репозитория `<N>-<суффикс>` (git-issues.md
// §«Имя ветки»): N — задача волны, суффикс — `stack-<ключ>` kebab-case ≤ 40.
const stackName = l => N + '-stack-' + (String(l.key).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+/, '').slice(0, 34).replace(/-+$/, '') || 'lane')
const stackNames = {}
for (const l of lanes) {
  if (!(l.deps || []).length) continue
  const s = stackName(l)
  if (!/^[0-9]+-[a-z0-9][a-z0-9-]*$/.test(s) || s.length - s.indexOf('-') - 1 > 40) return { ok: false, stage: 'план', why: 'имя сводки deps «' + s + '» полосы ' + l.key + ' не по форме <N>-<суффикс> — номер волны не число' }
  if (Object.values(stackNames).includes(s)) return { ok: false, stage: 'план', why: 'имя сводки deps «' + s + '» совпало у двух полос — ключи различаются только знаками' }
  stackNames[l.key] = s
}

// ── Полосы ──────────────────────────────────────────────────────────────
phase('Полосы')
const review = async (role, l, head, prevHead, label, stack) => agent(C + '\n\nРевью ' + role + ': полоса ' + l.key + ' ветка ' + l.branch + ' @' + head + (prevHead ? ' — только дельта `git diff ' + prevHead + '..' + head + '` (принятое не переоткрывается)' : (stack ? ' — своя дельта `git diff ' + stack.head + '..' + head + '` (сводка deps ' + stack.branch + ' — код принятых полос, не предмет ревью)' : '')) + '. Отчёт задания и исполнителя — ' + rep(l.key, 'implement') + '. Запись — ' + rep(l.key, label) + '. Верни verdict, sha (голова, которую смотрел), blocking (пусто при accept), report.', { agentType: role, label: label + ':' + l.key, phase: 'Полосы', schema: S_REV })
const precheck = async (l, impl, stack) => agent(C + '\n\nРежим lane-precheck: `bash ' + WS + '/scripts/lane-precheck.sh ' + impl.copy + ' ' + impl.branch + ' ' + (stack ? stack.head : (l.base || A.base)) + ' ' + (impl.issues || []).map(i => '--issue ' + i).join(' ') + ' --hook-log ' + impl.hookLog + ' > ' + rep(l.key, 'lane-precheck') + ' 2>&1`. Верни code, out (последние строки), reasons (коды из строк REASON), head (голова ветки в копии).', { ...MECH, label: 'mech:precheck:' + l.key, phase: 'Полосы', schema: S_MECH })
const implement = async (l, tdd, extra, stack) => agent(C + '\n\nПолоса ' + l.key + ' (' + tierOf[l.key].tier + '), ветка ' + l.branch + ' от ' + (stack ? 'сводки deps ' + stack.branch + '@' + stack.head + ' (в ней код полос ' + (l.deps || []).join(', ') + '; ветка уже есть на origin — влей сводку в неё коммитом слияния, не переписывая)' : (l.base || A.base)) + ', копия под ' + WS + '/tmp/. ' + (tdd ? 'Строгий TDD: красная проба до кода. ' : '') + 'Задание: ' + l.text + (l.ctx ? '\nКонтекст: ' + l.ctx : '') + (extra ? '\nДоводка: ' + extra : '') + '\nСдача: коммит, DoD-proof в каждой задаче, отправка своей ветки через слот с журналом `{ echo "lane-push head=$(git rev-parse HEAD)"; git push origin HEAD:refs/heads/' + l.branch + ' 2>&1; echo "lane-push rc=$?"; } > ' + D + '/' + l.key + '/push.log`. Отчёт — ' + rep(l.key, 'implement') + '. Верни status, branch, head, copy, hookLog, issues (владелец/репо#N), report.', { agentType: l.agent, label: 'impl:' + l.key, phase: 'Полосы', schema: S_IMPL })
// Сводка голов deps: временная ветка от свежей базы, головы — коммитами слияния
// (--no-ff, без rebase/reset/force); уже есть на origin — дописывается. Факт
// содержания — `git merge-base --is-ancestor` по каждой голове, а не слово.
const stackOf = async (l, deps) => agent(C + '\n\nРежим сводка deps полосы ' + l.key + ': в копии под ' + WS + '/tmp/ от свежего origin/' + (l.base || A.base) + ' заведи ветку ' + stackNames[l.key] + ' и влей в неё по порядку ' + deps.map(d => d.branch + '@' + d.head).join(', ') + ' коммитами слияния pointpu --no-ff. Ветка уже есть на origin — не перезаписывай: влей в неё свежую базу и недостающие головы. Конфликт по существу не решай: `git merge --abort`, верни status conflict и пути в conflicts. Отправь ветку через слот (журнал ' + D + '/' + l.key + '/stack.push.log). ФАКТ: для каждой головы `git merge-base --is-ancestor <голова> HEAD` — код 0; в contains — головы, прошедшие эту проверку. Отчёт — ' + rep(l.key, 'stack') + '. Верни status, branch, head, contains, conflicts, report.', { ...MECH, label: 'mech:stack:' + l.key, phase: 'Полосы', schema: S_STACK })

const runLane = async (l, stack) => {
  const t = tierOf[l.key]
  const has = s => t.steps.includes(s)
  const out = { key: l.key, tier: t.tier, ok: false, reviews: [] }
  if (has('acceptance(<=2)')) {
    let acc = null
    for (let r = 1; r <= 2; r++) {
      await agent(C + '\n\nПриёмка полосы ' + l.key + ' (смена публичного контракта либо миграция): ' + l.text + (acc ? '\nВозврат круга ' + (r - 1) + ': ' + rep(l.key, 'acceptance-review-' + (r - 1)) : '') + '. Отчёт — ' + rep(l.key, 'acceptance-' + r) + '.', { agentType: 'acceptance-author', label: 'acc:' + l.key + ':' + r, phase: 'Полосы' })
      acc = await review('acceptance-reviewer', l, '', '', 'acceptance-review-' + r)
      if (acc && acc.verdict === 'accept') break
    }
    if (!acc || acc.verdict !== 'accept') return { ...out, stage: 'приёмка: 2 круга исчерпаны — спор решает диспетчер', report: rep(l.key, 'acceptance-review-2') }
  }
  if (has('surface-census')) {
    await agent(C + '\n\nПерепись поверхности ДО кода, полоса ' + l.key + ': ' + l.text + '. Слушатели, RPC, каталог прав, секреты, профили. Запись — ' + rep(l.key, 'surface-census') + ' (её путь получит исполнитель).', { agentType: 'security-auditor', label: 'census:' + l.key, phase: 'Полосы' })
  }
  const tdd = has('implementer-tdd')
  let impl = await implement(l, tdd, has('surface-census') ? 'перепись поверхности — ' + rep(l.key, 'surface-census') : '', stack)
  if (!impl || ['blocked', 'failed'].includes(impl.status) || !sha40(impl.head)) return { ...out, stage: 'исполнитель', report: rep(l.key, 'implement') }
  // предпроверка; повтор — только при новой голове
  let pc = await precheck(l, impl, stack)
  if (pc && pc.code === 1) {
    const mech = (pc.reasons || []).filter(x => mechanicsReasons.has(x))
    await err(mech.length ? 'executor-mechanics' : 'new:lane-precheck-' + String((pc.reasons || ['unknown'])[0]).toLowerCase(), l.key, 'implement', (pc.reasons || []).join(','))
    const prev = impl.head
    impl = await implement(l, tdd, 'lane-precheck вернул ' + (pc.reasons || []).join(', ') + ' — ' + rep(l.key, 'lane-precheck'), stack)
    if (!impl || !sha40(impl.head)) return { ...out, stage: 'исполнитель (доводка предпроверки)' }
    if (impl.head === prev && impl.status !== 'already-done') return { ...out, stage: 'предпроверка: голова не сменилась — повтора нет', reasons: pc.reasons }
    pc = await precheck(l, impl, stack)
  }
  if (!pc || pc.code !== 0) return { ...out, stage: 'предпроверка', code: pc ? pc.code : null, reasons: pc ? pc.reasons : [] }
  out.head = impl.head
  out.copy = impl.copy
  if (stack) out.stack = { branch: stack.branch, head: stack.head }
  if (has('roles')) {
    const roles = t.roles.length ? t.roles : ['go-style-reviewer']
    let vs = await Promise.all(roles.map(r => review(r, l, impl.head, '', 'review-' + r, stack)))
    const back = vs.map((v, i) => ({ v, r: roles[i] })).filter(x => !x.v || x.v.verdict !== 'accept')
    if (back.length) {
      const prev = impl.head
      impl = await implement(l, tdd, 'возврат ролей: ' + back.map(x => x.r + ' — ' + rep(l.key, 'review-' + x.r)).join('; '), stack)
      if (!impl || !sha40(impl.head) || impl.head === prev) return { ...out, stage: 'ревью ролей: голова не сменилась — повтора нет' }
      pc = await precheck(l, impl, stack)
      if (!pc || pc.code !== 0) return { ...out, stage: 'предпроверка после ревью', reasons: pc ? pc.reasons : [] }
      // Второй круг — только вернувшим, по дельте (база диспетчера §8а п.8).
      // Вердикт принявшей роли остаётся на голове, которую она СМОТРЕЛА: sha
      // не переписывается (ws#933). Голову новее её вердикта никто из неё не
      // видел — полоса стоит здесь, до сборки, и решает диспетчер.
      const again = await Promise.all(back.map(x => review(x.r, l, impl.head, prev, 'review-' + x.r + '-2')))
      if (again.some(v => !v || v.verdict !== 'accept')) return { ...out, stage: 'ревью ролей: второй круг — тупик, решает диспетчер' }
      vs = vs.map((v, i) => { const j = back.findIndex(x => x.r === roles[i]); return j < 0 ? v : again[j] })
      const unseen = roles.filter((r, i) => !vs[i] || vs[i].sha !== impl.head)
      if (unseen.length) return { ...out, head: impl.head, stage: 'ревью ролей: ' + unseen.join(', ') + ' приняли ' + prev.slice(0, 12) + ', новую голову ' + impl.head.slice(0, 12) + ' не видели (повтор принявших запрещён §8а п.8) — решает диспетчер', unseen }
      out.head = impl.head
    }
    out.reviews = vs.map((v, i) => ({ role: roles[i], sha: v.sha, verdict: v.verdict, blocking: v.blocking }))
  }
  return { ...out, ok: true }
}
// Порядок — по deps (слои плана): полоса стартует, когда ВСЕ её deps прошли;
// независимая — сразу. Зависимая — от сводки голов deps (ws#938): без неё в
// ветке полосы нет кода предшественника, а сводит полосы только сборка.
const layers = plan.layers && plan.layers.length ? plan.layers : [lanes.map(l => l.key)]
const done = {}
const stacks = []
const started = {}
const launch = k => started[k] || (started[k] = (async () => {
  const l = lanes.find(x => x.key === k)
  if (!l) return (done[k] = { key: k, ok: false, stage: 'полосы ' + k + ' нет в задании' })
  const deps = await Promise.all((l.deps || []).map(launch))
  const notReady = deps.filter(d => !d.ok)
  let r
  if (notReady.length) r = { key: k, ok: false, stage: 'не начата: deps ' + notReady.map(d => d.key).join(', ') + ' не прошли' }
  else if (!deps.length) r = await runLane(l, null)
  else {
    const ds = deps.map(d => ({ branch: lanes.find(x => x.key === d.key).branch, head: d.head }))
    const st = await stackOf(l, ds)
    const missing = st ? ds.filter(d => !(st.contains || []).includes(d.head)) : ds
    if (st && sha40(st.head)) stacks.push(st.branch || stackNames[k])
    if (!st || st.status === 'conflict' || !['done', 'already-done'].includes(st.status) || !sha40(st.head) || missing.length) {
      r = { key: k, ok: false, stage: 'сводка deps ' + stackNames[k] + ': ' + (st && st.status === 'conflict' ? 'конфликт в ' + ((st.conflicts || []).join(', ') || 'путях без имени') : !st ? 'нет ответа' : missing.length ? 'нет голов ' + missing.map(d => d.branch + '@' + String(d.head).slice(0, 12)).join(', ') : 'статус ' + st.status) + ' — исполнитель не зван, решает диспетчер', conflicts: st ? st.conflicts || [] : [], report: rep(k, 'stack') }
    } else r = await runLane(l, { branch: st.branch || stackNames[k], head: st.head })
  }
  done[k] = r
  return r
})())
await Promise.all(layers.flat().map(launch))
if (Object.values(done).some(r => !r.ok)) return { ok: false, stage: 'полосы', lanes: done, stacks, errors }

// ── Сборка ──────────────────────────────────────────────────────────────
phase('Сборка')
const steps = new Set(lanes.flatMap(l => tierOf[l.key].steps))
const order = layers.flat()
const assemble = async round => agent(C + '\n\nРежим сборка ' + round + ': в копии под ' + WS + '/tmp/ от свежего origin/' + (A.base || '?') + ' сведи в ветку волны ' + N + ' полосы по порядку ' + order.map(k => lanes.find(l => l.key === k).branch + '@' + done[k].head).join(', ') + ' коммитами слияния pointpu --no-ff; конфликт по существу не решай — верни conflicts. Отправь ветку волны через слот (журнал ' + D + '/assemble-' + round + '.push.log); PR ' + N + ' → ' + (A.epic || A.base) + ' открой, если его нет (заголовок «#' + N + ' …», тело — ровно состав git log база..голова, Closes — только задачи с DoD-proof). Отчёт — ' + D + '/assemble-' + round + '.md. Верни status, head, copy, pr, conflicts, report.', { ...MECH, label: 'mech:assemble:' + round, phase: 'Сборка', schema: S_ASM })
let asm = await assemble(1)
if (!asm || !['done', 'already-done'].includes(asm.status) || !sha40(asm.head)) return { ok: false, state: 'failed', stage: 'сборка', conflicts: asm ? asm.conflicts : [], errors }
// Номер PR идёт в задания рецензента, CI, предпроверки и вливания. Не целое ≥ 1
// (нет поля, 0, строка «—», адрес) — остановка ЗДЕСЬ с причиной: иначе шаги ниже
// получили бы «PR #undefined» и судили бы не тот запрос либо никакой (ws#935).
if (!Number.isInteger(asm.pr) || asm.pr < 1) return { ok: false, state: 'failed', stage: 'сборка: номер PR не целое ≥ 1 (' + JSON.stringify(asm.pr === undefined ? null : asm.pr) + ') — рецензент, CI и посадка без номера не зовутся', head: asm.head, errors }
const waveReviews = []
if (steps.has('wave-reviewer')) {
  const wr = await agent(C + '\n\nСверка волны ' + N + ' на сборке @' + asm.head + ' (PR #' + asm.pr + '): полосы ' + order.join(', ') + ', отчёты — ' + D + '/<полоса>/implement.md. Пять классов столкновений; один раз на волну. Запись — ' + D + '/wave-review.md. Верни verdict, sha (голова сборки), blocking, report.', { agentType: 'wave-reviewer', label: 'review-wave', phase: 'Сборка', schema: S_REV })
  if (!wr || wr.verdict !== 'accept') return { ok: false, stage: 'рецензент волны — возврат; один круг: доводка по ' + D + '/wave-review.md в ветках полос и пересведение решает диспетчер', blocking: wr ? wr.blocking : [], errors }
  waveReviews.push({ role: 'wave-reviewer', sha: wr.sha, verdict: wr.verdict, blocking: wr.blocking })
}
// CI: «идёт» — ждать, не провал; вердикт — только на голове сборки
let ci = null
for (let i = 0; i < 12; i++) {
  ci = await agent(C + '\n\nРежим CI: ' + (A.repo || '?') + ' PR #' + asm.pr + ', голова ' + asm.head + '. Прочти check-runs НА ЭТОЙ голове; идёт — подожди до 10 минут и верни running. Отчёт — ' + D + '/ci-' + i + '.md. Верни state, head, total, passed, report.', { ...MECH, agentType: 'ci-watcher', label: 'mech:ci:' + i, phase: 'Сборка', schema: S_CI })
  if (!ci || ci.state !== 'running') break
}
// «Идёт» и после ожидания — СОСТОЯНИЕ, а не провал: волна не влита и не сломана,
// повтор шаблона продолжит с той же головы (state running отличим от failed).
if (ci && ci.state === 'running' && ci.head === asm.head) return { ok: false, state: 'running', stage: 'CI идёт на ' + asm.head.slice(0, 12) + ' — ожидание исчерпано, провала нет', pr: asm.pr, head: asm.head, report: ci.report, errors }
if (!ci || ci.state !== 'green' || ci.head !== asm.head) return { ok: false, state: 'failed', stage: 'CI ' + (ci ? ci.state : 'нет ответа'), report: ci ? ci.report : '', errors }

// ── Посадка ─────────────────────────────────────────────────────────────
phase('Посадка')
if (steps.has('landing-reviewer')) {
  const lr = await agent(C + '\n\nДо посадки: PR #' + asm.pr + ' @' + asm.head + ' → ' + (A.epic || A.base) + '. Запись — ' + D + '/landing-review.md. Верни verdict, sha, blocking, report.', { agentType: 'landing-reviewer', label: 'review-landing', phase: 'Посадка', schema: S_REV })
  if (!lr || lr.verdict !== 'accept') return { ok: false, stage: 'landing-reviewer — возврат', blocking: lr ? lr.blocking : [], errors }
  waveReviews.push({ role: 'landing-reviewer', sha: lr.sha, verdict: lr.verdict, blocking: lr.blocking })
}
// Вердикты ролей полос судятся на голове ПОЛОСЫ, сведённой в сборку (sha
// вердикта = голова, отданная сборке); на голове PR — вердикты волны: их и
// судит landing-precheck (REVIEW-STALE). Подменять sha вердикта нельзя.
for (const d of Object.values(done)) {
  const stale = (d.reviews || []).filter(r => r.sha !== d.head)
  if (stale.length) return { ok: false, stage: 'вердикт роли не на сведённой голове полосы ' + d.key, stale, errors }
}
const reviews = waveReviews
const landCheck = async round => agent(C + '\n\nРежим landing-precheck ' + round + ': запиши ' + D + '/reviews.json = ' + JSON.stringify(reviews) + '\nВыполни `bash ' + WS + '/scripts/landing-precheck.sh ' + (A.repo || '?') + ' ' + asm.pr + (reviews.length ? ' --reviews ' + D + '/reviews.json' : '') + ' > ' + D + '/landing-precheck-' + round + '.md 2>&1`. Верни code, out (строки REASON и VERDICT), reasons (коды из строк REASON), head (голова PR из CENSUS).', { ...MECH, label: 'mech:landing:' + round, phase: 'Посадка', schema: S_MECH })
let lp = await landCheck(1)
if (lp && lp.code === 1) {
  const rs = lp.reasons || []
  if (rs.every(x => bodyReasons.has(x))) {
    await err('executor-mechanics', 'wave', 'assemble-1', rs.join(','))
    await agent(C + '\n\nРежим pr-edit: PR #' + asm.pr + ' — причины landing-precheck ' + rs.join(', ') + ' (' + D + '/landing-precheck-1.md). Исправь заголовок и тело по составу git log база..голова; Closes без DoD-proof → Refs; строк атрибуции 0. Верни code 0, out, reasons [], head.', { ...MECH, label: 'mech:pr-edit', phase: 'Посадка', schema: S_MECH })
    lp = await landCheck(2)
  } else if (rs.every(x => x === 'CI-PENDING')) {
    lp = await landCheck(2)
  }
}
if (lp && lp.code === 1 && (lp.reasons || []).length && lp.reasons.every(x => x === 'CI-PENDING')) return { ok: false, state: 'running', stage: 'landing-precheck: CI на голове ещё идёт — провала нет', pr: asm.pr, head: asm.head, reasons: lp.reasons, errors }
if (!lp || lp.code !== 0) return { ok: false, state: 'failed', stage: 'landing-precheck', code: lp ? lp.code : null, reasons: lp ? lp.reasons : [], errors }
const merged = await agent(C + '\n\nРежим merge: PR #' + asm.pr + ' (' + (A.repo || '?') + '), голова ' + asm.head + '; основание — landing-precheck код 0 (' + D + '/landing-precheck-*.md). Влей коммитом слияния pointpu (--no-ff) в свежей копии, отправь через слот; ветку волны сними' + (stacks.length ? ' и временные сводки deps ' + stacks.join(', ') : '') + '. ФАКТ: `gh pr view ' + asm.pr + ' --json state,mergeCommit` — state MERGED. Затем каскад: закрой задачи волны со ссылкой на их DoD-proof. Затем `bash ' + WS + '/scripts/wave-errors.sh rate ' + N + ' <часы волны: (сейчас − step-start ' + D + '/plan-1.json mtime)/3600>`. Верни code (0 — влит и закрыто), out (state, mergeCommit, вывод rate), reasons [], head (mergeCommit).', { ...MECH, label: 'mech:merge', phase: 'Посадка', schema: S_MECH })
return { ok: !!(merged && merged.code === 0 && sha40(merged.head)), stacks, pr: asm.pr, head: asm.head, merge: merged ? merged.head : '', rate: merged ? merged.out : '', lanes: done, errors }
