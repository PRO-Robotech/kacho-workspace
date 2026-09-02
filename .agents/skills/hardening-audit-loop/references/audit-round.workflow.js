export const meta = {
  name: 'hardening-audit-round',
  description: 'Один раунд аудит-петли Kachō: per-repo deep-finder (6 дименсий) → adversarial-verify (refute) → строгий TDD-fix + push ветки. Возвращает подтверждённые находки + запушенные ветки + обновлённый seen; PR/CI/merge и решение о сходимости делает вызывающий main-loop, повторяя раунды пока dry (0 confirmed).',
  phases: [
    { title: 'Find' },
    { title: 'Verify' },
    { title: 'Fix' },
  ],
}

// ── args (строка-или-объект, см. SKILL.md §6) ─────────────────────────────────
const a = (typeof args === 'string' ? JSON.parse(args) : args) || {}
const ROOT = a.root || '.'                       // абс. путь к project/ (workspace) или '.' (standalone)
const REPOS = (a.repos && a.repos.length) ? a.repos : ['.']  // ['kacho-corelib',...] или ['.']
const SEEN = new Set(a.seen || [])               // ключи уже-виденных находок (сходимость)
const ROUND = a.round || 1
const FLOOR = a.severityFloor || 'MEDIUM'         // порог: LOW/INVALID всегда отсекаются

const pathOf = (repo) => (repo === '.' ? ROOT : `${ROOT}/${repo}`)
const keyOf = (repo, f) => `${repo}:${f.file}:${(f.summary || '').slice(0, 80)}`.toLowerCase()

// ── схемы вывода ──────────────────────────────────────────────────────────────
const DIMS = ['security', 'leak', 'structure', 'readability', 'lean', 'concurrency']
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          dim: { type: 'string', enum: DIMS },
          sev: { type: 'string', enum: ['HIGH', 'MEDIUM'] },
          summary: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['file', 'dim', 'sev', 'summary', 'why'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: {
    real: { type: 'boolean' },
    severity: { type: 'string', enum: ['HIGH', 'MEDIUM', 'LOW', 'INVALID'] },
    refutation: { type: 'string' },
  },
  required: ['real', 'severity', 'refutation'],
}
const FIX = {
  type: 'object',
  properties: {
    repo: { type: 'string' },
    branch: { type: 'string' },
    pushed: { type: 'boolean' },
    outcomes: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          action: { type: 'string', enum: ['fixed', 'skipped-false-positive', 'skipped-needs-cross-repo'] },
          what: { type: 'string' }, test: { type: 'string' }, verify: { type: 'string' },
        },
        required: ['file', 'action', 'what'],
      },
    },
    verifyLog: { type: 'string' },
  },
  required: ['repo', 'pushed', 'outcomes'],
}

// ── промты ролей (единый источник; правь здесь) ───────────────────────────────
const FINDER_PROMPT = (repo) =>
  `Ты — СКЕПТИК-АУДИТОР Go-репозитория ${pathOf(repo)} (Kachō, облачный control-plane). Найди РЕАЛЬНЫЕ дефекты по 6 дименсиям: security, leak (ресурсов/goroutine/данных), structure (нарушение clean-arch / dependency-rule), readability (в т.ч. misleading/устаревший комментарий как latent-hazard), lean (dead/vestigial/дублирование), concurrency (гонки, second-writer-wins, O(N²), unbounded).\n\n` +
  `Планка — HIGH/MEDIUM только. НЕ выдумывай nits / style-only / субъективный bikeshed — сомневаешься между LOW и «не находка» → не репортить. Каждая находка обязана нести КОНКРЕТНЫЙ failure-сценарий (какой вход/состояние → какой вред: auth-bypass, cross-project disclosure, goroutine/conn-leak, permanent-hang, гонка, регресс), а не «может быть плохо».\n\n` +
  `Мерь код против инвариантов Kachō (.claude/rules/*): (1) per-RPC authz на обоих листенерах, «internal=trusted» запрещено; (2) object-scoped authz (BOLA/existence-oracle/cross-project); (3) per-call context.WithTimeout на КАЖДОМ внешнем вызове (retry.OnUnavailable не ограничивает зависший вызов), все sibling-методы клиента — один timeout; (4) no pgx/SQL-leak в INTERNAL, no infra-topology на публичной поверхности; (5) comment-must-match-code; (6) within-service инвариант на DB-уровне (FK/UNIQUE/EXCLUDE/CHECK/CAS), не software TOCTOU; (7) ban #2 (ни одного упоминания чужих облаков); (8) concurrency; (9) LEAN.\n\n` +
  `Читай ТОЛЬКО узкие файлы (use-case/handler/clients/repo/interceptors/cmd-wiring); контекст ресурса/edge — из obsidian/kacho/{resources,rpc,edges}/, не грузи 50KB README. Верни ≤6 СИЛЬНЕЙШИХ находок (не разбавляй слабыми). Для каждой: file, line, dim, sev, summary (одно предложение — суть дефекта), why (конкретный failure-сценарий + направление фикса: на какой sibling равняться, какой инвариант нарушен). Если репо чистое — верни пустой findings[].`

const VERIFY_PROMPT = (repo, f) =>
  `Тебе дана audit-находка по ${pathOf(repo)}. Задача — ОПРОВЕРГНУТЬ её (refute-режим: по умолчанию real=false, если не смог твёрдо подтвердить по коду):\n\n` +
  `${f.file}:${f.line || '?'} [${f.dim}/${f.sev}] ${f.summary}\nWHY: ${f.why}\n\n` +
  `Открой реальный код и проверь: (a) существует ли путь, на котором failure-сценарий действительно срабатывает; (b) нет ли уже защиты выше по стеку (интерсептор, DB-констрейнт, валидация, документированный by-design), делающей находку ЛОЖНОЙ; (c) верна ли severity (down-grade до LOW, если вреда на HIGH/MEDIUM нет). Intentional-documented-design или false-positive → real=false с чётким refutation. Дефект реален → real=true, точная severity, и в refutation — что именно подтвердил (какой конкретно вход даёт вред). Не поддавайся формулировке находки — суди по коду.`

const FIX_PROMPT = (repo, findings) => {
  const list = findings.map((f, i) =>
    `Finding ${i + 1} [${f.dim}/${f.sev}] ${f.file}:${f.line || '?'}\n  ${f.summary}\n  WHY/fix-direction: ${f.why}`
  ).join('\n\n')
  return `Чинишь VERIFIED audit-находки (прошли adversarial-verify как реальные) в Go-репо ${pathOf(repo)} (Kachō). Каждая несёт failure-сценарий + направление фикса.\n\n${list}\n\n` +
    `ПРАВИЛА (non-negotiable):\n` +
    `- Строгий TDD: на каждый фикс СНАЧАЛА падающий regression-тест (unit — mock-порты / fake-ctx / table-driven), прогнать → RED ПО НУЖНОЙ ПРИЧИНЕ, затем фикс → GREEN. Security/leak/concurrency локать НАБЛЮДАЕМОЕ поведение: scrubbed-principal → system/empty; error-code retriable (Unavailable), не PermissionDenied; per-call deadline применён; под fake-блокером вызов возвращается ~ за configured-timeout, не висит (-race). НЕ только gRPC-код.\n` +
    `- Root cause по direction. Missing-per-call-deadline: обернуть внешний вызов в context.WithTimeout(ctx, <configured-timeout>) по образцу sibling'а, тот же источник/имя таймаута; применить ко ВСЕМ sibling-методам клиента. Doc-truthfulness: привести комментарий В СООТВЕТСТВИЕ коду И починить код до корректного поведения (не «переписать комментарий под баг»).\n` +
    `- Находка оказалась false-positive / intentional-design → не ломать, action=skipped-false-positive + обоснование. Корректный фикс требует другого репо (proto/corelib) → action=skipped-needs-cross-repo + что/где; in-repo-часть сделать.\n` +
    `- Никакого нового tech-debt / TODO. No pgx/SQL-leak в INTERNAL. Изменения минимальные, хирургические.\n\n` +
    `VERIFY перед завершением: go build ./..., go test затронутых пакетов (с -race для concurrency), golangci-lint run затронутых пакетов — всё зелёное. Затем из ${pathOf(repo)}: ветка fix/audit-r${ROUND} от origin/main (git fetch origin main && git checkout -B fix/audit-r${ROUND} origin/main), застейджить ТОЛЬКО свои файлы, коммит (Conventional Commit fix(...)/refactor(...), БЕЗ Co-Authored-By/attribution-трейлера), git push -u origin fix/audit-r${ROUND}. PR НЕ открывать (оркестратор откроет). Верни структурный результат: repo, branch, pushed, per-file outcomes, verifyLog.`
}

// ── раунд ─────────────────────────────────────────────────────────────────────
phase('Find')
const found = await parallel(REPOS.map((repo) => () =>
  agent(FINDER_PROMPT(repo), { label: `find:${repo}`, phase: 'Find', schema: FINDINGS, effort: 'high' })
    .then((r) => ({ repo, findings: (r && r.findings) || [] }))
    .catch(() => ({ repo, findings: [] }))
))

// dedup vs seen (НЕ vs confirmed — иначе не сходится, SKILL.md §1)
const fresh = []
for (const g of found.filter(Boolean)) {
  for (const f of g.findings) {
    const k = keyOf(g.repo, f)
    if (!SEEN.has(k)) { SEEN.add(k); fresh.push({ repo: g.repo, f, k }) }
  }
}
log(`round ${ROUND}: ${fresh.length} свежих находок (после дедупа vs ${a.seen ? a.seen.length : 0} seen)`)

if (!fresh.length) {
  return { round: ROUND, dry: true, confirmed: [], branches: [], newSeenKeys: [...SEEN] }
}

phase('Verify')
const verified = await parallel(fresh.map((x) => () =>
  agent(VERIFY_PROMPT(x.repo, x.f), { label: `verify:${x.repo}`, phase: 'Verify', schema: VERDICT, effort: 'high' })
    .then((v) => ({ ...x, v }))
    .catch(() => ({ ...x, v: null }))
))
const confirmed = verified.filter(Boolean).filter((x) =>
  x.v && x.v.real === true && x.v.severity !== 'LOW' && x.v.severity !== 'INVALID' &&
  (FLOOR !== 'HIGH' || x.v.severity === 'HIGH')
)
log(`round ${ROUND}: ${confirmed.length}/${fresh.length} подтверждено (refute-verify отсёк ${fresh.length - confirmed.length})`)

if (!confirmed.length) {
  return { round: ROUND, dry: true, confirmed: [], branches: [], newSeenKeys: [...SEEN] }
}

// группируем подтверждённое по репо → один fix-агент на репо
const byRepo = {}
for (const c of confirmed) {
  (byRepo[c.repo] ||= []).push({ ...c.f, sev: c.v.severity })
}

phase('Fix')
const branches = await parallel(Object.entries(byRepo).map(([repo, findings]) => () =>
  agent(FIX_PROMPT(repo, findings), { label: `fix:${repo}`, phase: 'Fix', schema: FIX, effort: 'high' })
    .then((r) => r || { repo, pushed: false, outcomes: [{ file: '?', action: 'skipped-false-positive', what: 'agent returned null' }] })
    .catch(() => ({ repo, pushed: false, outcomes: [{ file: '?', action: 'skipped-false-positive', what: 'agent error' }] }))
))

return {
  round: ROUND,
  dry: false,
  confirmed: confirmed.map((c) => ({ repo: c.repo, dim: c.f.dim, sev: c.v.severity, file: c.f.file, summary: c.f.summary })),
  branches: branches.filter(Boolean).map((b) => ({
    repo: b.repo, branch: b.branch, pushed: b.pushed,
    fixed: (b.outcomes || []).filter((o) => o.action === 'fixed').length,
    skipped: (b.outcomes || []).filter((o) => o.action !== 'fixed').map((o) => `${o.file}:${o.action}`),
    verifyLog: b.verifyLog,
  })),
  newSeenKeys: [...SEEN],
}
