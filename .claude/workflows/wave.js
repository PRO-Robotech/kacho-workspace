export const meta = {
  name: 'wave',
  description: 'Волна по уровням риска: план скриптом, полосы по шагам своего уровня, сборка, один рецензент на волну, CI, предпроверка посадки скриптом, вливание и каскад',
  whenToUse: 'Любая волна полос kacho, kaname, corelib или воркспейса. args: {repo, wave, epic, base, ws?, root?, targets?, crossRepo?, lanes:[{key, repo, agent, tier?, roles?, branch, deps?, text, ctx?, issues?, paths?, dir?, class?, head?, premise?}]}',
  phases: [
    { title: 'План', detail: 'plan-precheck.sh: уровни, слои, corelib, пересечения; предусловия раздачи каждой полосы — lane-precheck.sh (ws#1272)' },
    { title: 'Предполёт', detail: 'до кода: карта влияния полос, критерии рецензентов (ws#1053)' },
    { title: 'Полосы', detail: 'шаги уровня из lane-tier.sh; зависимая — от сводки голов deps; lane-precheck.sh до ревью; пункты карты закрыты; пробная сборка сразу' },
    { title: 'Сборка', detail: 'сведение, рецензент волны, CI' },
    { title: 'Посадка', detail: 'перепись гейтов разом, демон вливания autoland.sh (start и один status), каскад, счётчик ошибок' },
  ],
}
// ЕДИНСТВЕННЫЙ шаблон волны (решение владельца 2026-10-06, «Да, по уровням»;
// база диспетчера §8б). Исправленная ошибка оркестровки правится ЗДЕСЬ, а не в
// разовом сценарии. Свойства держит scripts/wave-template-inject.sh:
//  - до предполёта — предусловия раздачи КАЖДОЙ полосы одним механиком (ws#1272):
//    код lane-precheck.sh не 0 — полоса и зависимые не раздаются;
//  - шаги полосы берутся из вывода plan-precheck.sh (а тот — из lane-tier.sh);
//    своего соответствия «уровень → шаги» здесь нет;
//  - R0 — без рецензентов; R1 — один wave-reviewer на СОБРАННУЮ волну; R2 — роли
//    полосы, рецензент волны; landing-reviewer — только за НЕДОСТАЮЩИМ фактом;
//  - вердикт и решение (база диспетчера §7 «Вердикт и решение», владелец
//    2026-10-10): роль даёт вердикт о СВОЕЙ полосе, решение «вливать» принимает
//    демон вливания по ПРАВИЛУ ВЛИВАНИЯ диспетчера (ниже), запускает его git-operator.
//    Непрошедшая полоса и возвращённая рецензентом волны — остаток (с зависимыми
//    от неё), соседи с полными фактами садятся;
//  - состояние переходит только по ФАКТУ скрипта (lane-precheck, autoland status,
//    сверка головы на origin), а не по слову агента;
//  - передача — через файлы: отчёт шага в <WS>/tmp/wave-<N>/reports/<полоса>/<шаг>.md, в
//    задание следующего идёт путь, а не пересказ;
//  - «идёт», «уже сделано», «нечего отправлять» — не провал; повтор шага — только
//    при НОВОЙ голове;
//  - механика (скрипты, git, трекер, чтение CI) — модель НЕ задаётся, наследуется;
//    у шага, чей ответ читает решение, не задаётся и усилие
//    (ws#1016, решение диспетчера): лёгкой модели нет ни на одном шаге, чей вывод
//    читает решение. Волна 7: код ci-read пересказан неверно, пауза пропущена, в
//    поле головы — фраза, невозможные числа;
//  - отчёты и журналы полос — под <D>/reports/<полоса>/, ВНЕ дерева копии (ws#1016,
//    волна 7: отчёт в копии — UNCOMMITTED у lane-precheck); lane-precheck зовётся
//    с LANE_PRECHECK_WS=<корень воркспейса> (иначе корень выводится из места
//    скрипта и выходит WS-UNKNOWN либо MAIN-COPY); сборка kacho ставит зависимости
//    консоли как ui.yml (`npm ci` в ui-future и в пакетах STANDALONE) до проверок;
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
//  - ветка полосы — голый номер (`^[0-9]+$`, форма kaname: его хук другого имени
//    не принимает) — сводка заводится в ВЕТКЕ САМОЙ ПОЛОСЫ, слияния по форме
//    хука `#<ветка> merge #<M>: …`; временной ветки нет, вливание её не снимает.
//    Имени, проходящего хуки всех репозиториев, не существует: kaname требует
//    голый номер, воркспейс и corelib — `<N>-<суть>` (ws#946).
//  - агент не ждёт (ws#1001, CLAUDE.md «Не жди»): у каждого шага — срок по классу
//    (STEP_MIN), долгий прогон — отсоединённо с исходом «идёт»; CI читается
//    КОРОТКИМ шагом без ожидания, повтор и паузу делает шаблон (CI_READS чтений,
//    между ними одна команда паузы CI_PAUSE_S ≤ 300 с), а не агент циклом.
//  - CI читается ТОЛЬКО scripts/ci-read.sh (ws#1006; урок kacho#3142 — влит при
//    «зелёно 30 из 30», когда проверок было 68 и 3 шли, база устарела): рецептом
//    «ЗАПУСК» из origin/main; состояние — из КОДА (CI_STATE: 0 green · 1 red ·
//    2 unread · 3 running · 4 stale), ответ агента не толкуется. После перевода в
//    ready шаблон CI не ждёт: полный прогон ждёт и судит демон вливания (ws#1152).
//  - пустые ходы (ws#1004): вывод plan-precheck разбирается parseJsonTail — объект
//    из ПОСЛЕДНЕЙ строки, строки CENSUS перед ним не мешают; файл вне перечня полосы,
//    которого нет и в перечнях соседей, исполнитель берёт сам и называет в отчёте —
//    blocked только за файлом соседа (перечни соседей — в его задании из args.lanes);
//    hookLog — путь к журналу отправки (не путь — доводка), report — содержательный итог.
//  - вливание (ws#1008, ws#1152): только демоном scripts/autoland/autoland.sh (ws#1147):
//    start сразу печатает pid, журнал, .state, исход — ОДИН шаг status; ci-read,
//    merge-readiness, landing-precheck и `gh pr merge --merge --match-head-commit`
//    исполняет демон. status 3 — итог running с путём .state: возобновление с новым
//    args.rerun читает status вживую, start берётся из кэша. Тело PR — вывод
//    scripts/pr-body.sh (ws#1146), не текст агента. Общее задание каждого шага
//    запрещает `repos/*/merges`, `pulls/*/merge` и `--auto` и даёт чтение merge-base
//    GET-запросом. Агенты ci-watcher звали `gh api repos/<r>/merges -X POST`, думая,
//    что читают merge-base, и влили три PR мимо посадки; отказ держит хук gh-api-guard.
//  - пауза между чтениями CI (ws#1010): её делает ТОТ ЖЕ агент, что читает CI, одной
//    командой — `sleep N`, строка `SLEPT <секунды>` по часам машины, затем ci-read.sh;
//    ответ несёт slept (реально прошедшие секунды), и чтение с паузой при slept
//    < N−10 шаблон ОТВЕРГАЕТ: его код не судится, чтение повторяется. Урок: агенты-
//    паузы на лёгкой модели sleep не исполняли — 12 чтений прошли за 7 мин вместо
//    40, цикл кончился раньше CI. Первое чтение — без паузы.
//  - копии полос и каталог волны — под КОРНЕМ воркспейса (ws#1010): ROOT/tmp/wave-<N>/;
//    ROOT — args.root, иначе выводится из ws (ws — копия под <корень>/tmp/… → корень).
//    Не <ws>/tmp, когда ws — отдельная копия: копия шаблона tmp/wave7/ws-main была
//    переключена на дерево kacho, копии полос в её tmp/ взяли ws-main/go.mod за корень
//    модуля. Чужой go.mod над копией отказывает lane-precheck (GOMOD-ABOVE).
//  - волна одним проходом (ws#1053, ai-tooling.md#at-one-pass-wave): ПРЕДПОЛЁТ до
//    кода — scout строит карту влияния каждой полосы и критерии рецензентов в
//    reports/preflight.md; полоса закрывает КАЖДЫЙ пункт своей карты правкой либо
//    «не затронуто — потому что …» (поле impact), незакрытый — одна доводка, затем
//    полоса стоит; смена контракта — имитация клиента по замыслу ДО кода; прошедшая
//    полоса СРАЗУ идёт в пробную сборку (хук отправки судит сведённое, --dry-run),
//    красное там — полоса в остаток; метрики волны — reports/metrics.json на любом
//    исходе; каскад не закрывает держателя записи ведомости.
const A = args || {}
const WS = A.ws || '/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace'
const N = String(A.wave || '')
// Корень воркспейса: явный args.root; иначе ws, а если ws — копия под
// <корень>/tmp/…, то <корень> (последний «/tmp/» с непустым префиксом).
const rootOf = w => { const i = w.lastIndexOf('/tmp/'); return i > 0 ? w.slice(0, i) : w }
const ROOT = A.root || rootOf(WS)
const D = ROOT + '/tmp/wave-' + N
// Отчёты и журналы полос — ВНЕ дерева копии (ws#1016): копия — D/<полоса>/copy.
const R = D + '/reports'
const HOMES = 'KACHO_HOME_KACHO=' + ROOT + '/project/kacho KACHO_HOME_KANAME=' + ROOT + '/project/kaname KACHO_HOME_CORELIB=' + ROOT + '/project/corelib'
// Шаг, по выводу которого шаблон ветвится (код, статус, голова, PR), — без модели и
// без усилия: оба наследуются (ws#1016, решение диспетчера 2026-10-11, вариант «б»).
// Усилие low — только шагам, чей ответ шаблон не читает (счётчик ошибок).
const MECH = { agentType: 'git-operator' }
const MECH_LOW = { ...MECH, effort: 'low' }
// Сборка kacho: зависимости консоли — как ui.yml, ДО проверок (ws#1016, волна 7:
// без них пакеты консоли падают MODULE_NOT_FOUND — «не выполнилось», не вердикт).
const UI_DEPS = /(^|\/)kacho$/.test(A.repo || '') ? ' Репозиторий kacho: ДО проверок консоли (хук отправки) поставь её зависимости как ui.yml — в копии `(cd ui-future && npm ci && for p in $(sed -n \'s/^  STANDALONE: //p\' ../.github/workflows/ui.yml); do npm ci --prefix "$p"; done)`; код не 0 — не отправлять, вернуть failed.' : ''
// Срок шага — минуты работы агента; по истечении — возврат с остатком, а не ожидание.
const STEP_MIN = { preflight: 45, implement: 90, review: 30, mech: 10, ci: 2 }
const CI_READS = 30
const CI_PAUSE_S = 240
// Чтение с паузой засчитывается при slept ≥ CI_PAUSE_S − CI_SLEPT_SLACK (ws#1010).
const CI_SLEPT_SLACK = 10
// Правило полосы о файлах (ws#1004): blocked на ничейном файле — пустой ход волны.
const FILES_RULE = 'ФАЙЛЫ ПОЛОСЫ: файл вне твоего перечня, которого нет в перечне соседних полос, — бери сам и назови в отчёте; blocked — только если нужен файл соседа (назови его и полосу).'
// Объект плана — из ПОСЛЕДНЕЙ непустой строки вывода (механик кладёт в out и строки
// CENSUS/VERDICT stderr); весь текст — JSON целиком (многострочный) тоже годен.
const parseJsonTail = out => {
  if (typeof out !== 'string') return null
  const obj = x => (x && typeof x === 'object' && !Array.isArray(x)) ? x : null
  try { const o = obj(JSON.parse(out.trim())); if (o) return o } catch (e) { /* не целиком — хвост */ }
  const lines = out.split('\n').map(x => x.trim()).filter(Boolean)
  if (!lines.length) return null
  try { return obj(JSON.parse(lines[lines.length - 1])) } catch (e) { return null }
}
// hookLog — путь к журналу отправки: абсолютный, без пробелов. Слово «зелёный» вместо
// пути lane-precheck прочесть не может — доводка, а не предпроверка вслепую.
const isPath = s => typeof s === 'string' && /^\/[^\s]+$/.test(s)
const due = (cls, plus) => 'СРОК ШАГА: ' + (STEP_MIN[cls] + (plus || 0)) + ' мин; истёк — верни исход с остатком (сделано / не сделано), а не жди.'
const C = [
  'Волна ' + N + ' (' + (A.repo || '?') + ', база ' + (A.base || '?') + ', эпик ' + (A.epic || '?') + '). Шаблон .claude/workflows/wave.js.',
  'ПРАВИЛА: хук отправки не обходить; гейты не ослаблять; подпись pointpu; трейлеры и строки атрибуции НЕ СТАВИТЬ НИКОГДА; нельзя --no-verify, --force, --admin, reset, rebase, squash.',
  'Тяжёлое — через ' + WS + '/scripts/heavy-slot.sh <класс> -- …: занят — код 74 сразу, это «не выполнилось»; ожидание — --wait N ≤ 300, дольше — ОДИН раз `heavy-slot.sh --enqueue <каталог> <класс> -- …` (билет держится до 2 ч, код — в .rc строки ENQUEUED); перезапуск ожидания на 74/75 ставит в конец очереди — запрещён (урок 2026-10-16). Копии — только под ' + D + '/ (каталог волны под корнем воркспейса, не под tmp/ другой копии; основную не трогать, ws#923, ws#1010). Отправка воркспейса — с ' + HOMES + '.',
  'ПЕРЕДАЧА ЧЕРЕЗ ФАЙЛЫ: полный отчёт шага пиши в названный файл, первой строкой `step-start: <date -u +%FT%TZ>`; в ответ — только поля схемы. Отчёты и журналы полос — только под ' + R + '/, ВНЕ дерева копии: файл в копии — UNCOMMITTED у lane-precheck (ws#1016, урок волны 7).',
  '«Идёт», «уже сделано», «нечего отправлять» — законные исходы, не провал: верни их своим статусом.',
  FILES_RULE,
  'ВЛИВАНИЕ (ws#1008, ws#1152): только демоном `scripts/autoland/autoland.sh` (start, затем один шаг status; вливает он `gh pr merge <PR> --merge --match-head-commit <sha>`); `gh api repos/*/merges`, `gh api …/pulls/*/merge` и `gh pr merge --auto` запрещены. `gh api` — только GET: merge-base — `gh api repos/<o>/<r>/compare/<base>...<head> --jq .merge_base_commit.sha` либо `git merge-base`, а `repos/*/merges -X POST` ВЛИВАЕТ (kacho#3142, kacho#3144, kaname#703 ушли мимо посадки так).',
  'НЕ ЖДИ (CLAUDE.md «Не жди», ws#1001): ни один вызов не держит ожидание дольше 10 мин; долгий прогон — отсоединённо `setsid env --default-signal=PIPE sh -c \'<команда>; echo $? > <журнал>.rc\' > <журнал> 2>&1 &` и pid-файл (nohup НЕ ставить: глушит SIGHUP детям, пробы internal/check краснеют; исход — код из .rc, не EXIT setsid), верни «идёт: pid, журнал, ожидаемое окончание»; имя журнала и .rc — уникальное ($$ либо sha), .rc снять до запуска. Слот тяжёлого — внутри того же отсоединённого прогона. Ждёт и читает с паузой только ci-watcher. Циклы until/while со sleep, tail --pid, опрос CI — запрещены. Механика: ' + due('mech'),
].join('\n')
const S_MECH = { type: 'object', properties: { code: { type: 'number' }, out: { type: 'string' }, reasons: { type: 'array', items: { type: 'string' } }, head: { type: 'string' } }, required: ['code', 'out', 'reasons', 'head'] }
// Чтение CI — схема механики и slept: реально прошедшие секунды паузы (строка SLEPT).
const S_CI = { type: 'object', properties: { ...S_MECH.properties, slept: { type: 'number' } }, required: [...S_MECH.required, 'slept'] }
const S_IMPL = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'nothing-to-push', 'blocked', 'failed'] }, branch: { type: 'string' }, head: { type: 'string' }, copy: { type: 'string' }, hookLog: { type: 'string' }, issues: { type: 'array', items: { type: 'string' } }, impact: { type: 'array', items: { type: 'string' } }, report: { type: 'string' }, lesson: { type: 'string' } }, required: ['status', 'branch', 'head', 'copy', 'hookLog', 'issues', 'impact', 'report', 'lesson'] }
// Предполёт: карта влияния и критерии рецензентов — по КАЖДОЙ полосе (ws#1053).
const S_PRE = { type: 'object', properties: { lanes: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, impact: { type: 'array', items: { type: 'string' } }, criteria: { type: 'array', items: { type: 'string' } } }, required: ['key', 'impact', 'criteria'] } }, estimate: { type: 'string' }, report: { type: 'string' } }, required: ['lanes', 'estimate', 'report'] }
// Вердикт роли — ТОЛЬКО поле verdict закрытого словаря (accept | return | void —
// «прогон недействителен»); значок или слово в report не читаются нигде (класс 7).
// Рецензент волны — вердикт по КАЖДОЙ полосе (lanes), общий verdict — свод.
const S_WREV = { type: 'object', properties: { verdict: { type: 'string', enum: ['accept', 'return', 'void'] }, sha: { type: 'string' }, blocking: { type: 'array', items: { type: 'string' } }, lanes: { type: 'array', items: { type: 'object', properties: { key: { type: 'string' }, verdict: { type: 'string', enum: ['accept', 'return', 'void'] }, blocking: { type: 'array', items: { type: 'string' } } }, required: ['key', 'verdict', 'blocking'] } }, report: { type: 'string' } }, required: ['verdict', 'sha', 'blocking', 'lanes', 'report'] }
const S_REV = { type: 'object', properties: { verdict: { type: 'string', enum: ['accept', 'return', 'void'] }, sha: { type: 'string' }, blocking: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['verdict', 'sha', 'blocking', 'report'] }
const S_ASM = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'conflict', 'failed'] }, head: { type: 'string' }, copy: { type: 'string' }, pr: { type: 'integer', minimum: 1 }, conflicts: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['status', 'head', 'copy', 'pr', 'conflicts', 'report'] }
const S_STACK = { type: 'object', properties: { status: { type: 'string', enum: ['done', 'already-done', 'conflict', 'failed'] }, branch: { type: 'string' }, head: { type: 'string' }, contains: { type: 'array', items: { type: 'string' } }, conflicts: { type: 'array', items: { type: 'string' } }, report: { type: 'string' } }, required: ['status', 'branch', 'head', 'contains', 'conflicts', 'report'] }
// Код scripts/ci-read.sh → состояние CI; иного кода нет — unread (не «зелёное»).
// 5 — целевой зелёный черновика (ws#1013): исполненное зелёное, но прогон не полный —
// вливанию не основание; шаблон переводит PR в ready и ждёт полного прогона.
const CI_STATE = { 0: 'green', 1: 'red', 2: 'unread', 3: 'running', 4: 'stale', 5: 'targeted-green' }
const ciState = r => (r && Number.isInteger(r.code) && CI_STATE[r.code]) || 'unread'
const sha40 = s => (typeof s === 'string' && /^[0-9a-f]{40}$/.test(s)) ? s : ''
// Рецепт «ЗАПУСК» — ОДИН источник: шапка scripts/landing-precheck.sh на origin/main
// между метками «рецепт ЗАПУСК». Текста рецепта шаблон не несёт: команда вырезает
// его по меткам из origin/main и исполняет с WS, S и аргументами. Не вырезан —
// код 2: пустой текст под `bash -c` дал бы код 0, то есть «можно». Код скрипта
// проходит наружу как есть. Проба — landing-precheck-inject.sh, раздел «запуск»:
// исполняет ЭТУ команду, отрисованную шаблоном, на случаях с кодом 0, 1 и 2.
const recipeRun = (s, argv, out) => '( set -o pipefail; WS=' + WS + '; git -C "$WS" fetch -q origin main && R=$(git -C "$WS" show origin/main:scripts/landing-precheck.sh | sed -n \'/^# >>> рецепт ЗАПУСК$/,/^# <<< рецепт ЗАПУСК$/{/рецепт ЗАПУСК$/d;s/^#//;p}\') && [ -n "$R" ] || { echo "ЗАПУСК: рецепт не вырезан из шапки origin/main:scripts/landing-precheck.sh «$WS»" >&2; exit 2; }; WS="$WS" S=' + s + ' TMPDIR=' + D + ' bash -c "$R" _ ' + argv + ' ) > ' + out + ' 2>&1'
const rep = (lane, step) => R + '/' + lane + '/' + step + '.md'
// Сообщения коммитов диапазона сборки (ws#1078, L11): пустой либо неразрешимый диапазон — код 2.
const logRange = (b, h) => 'R=$(git log --format=%B ' + b + '..' + h + ') && [ -n "$R" ] && printf \'%s\\n\' "$R" || { echo "ДИАПАЗОН ' + b + '..' + h + ' ПУСТ — отказ, не зелёное" >&2; exit 2; }'
// Задание полосы — файлом (ws#1078, L6: вставка обрезалась между шагами): textFile — путь под
// tmp/<задача>/, в задание идёт путь, а не пересказ; text — лишь для короткого.
const taskOf = l => l.textFile ? 'ЗАДАНИЕ — в файле ' + l.textFile + ' (прочти целиком; пересказа здесь нет)' : l.text
// Итог диспетчеру — без простыней (ws#1078, L5: обрезанный итог дочитывал разведчик, ~100 тыс.
// токенов на раз): строка длиннее SLIM_MAX — начало и путь отчётов; полный текст — в файлах R;
// redRound — порядок круга диспетчеру дословно, не режется.
const SLIM_MAX = 400
const slim = x => typeof x === 'string' ? (x.length > SLIM_MAX ? x.slice(0, SLIM_MAX) + ' … [полностью — в ' + R + ']' : x) : Array.isArray(x) ? x.map(slim) : (x && typeof x === 'object') ? Object.fromEntries(Object.entries(x).map(([k, v]) => [k, k === 'redRound' ? v : slim(v)])) : x
const errors = []
// Уроки полос (ai-tooling.md#at-lane-retro, владелец 2026-10-12): исполнитель дописывает
// урок строкой в ОДИН файл волны; итог несёт файл и перечень — пачку для tooling-maintainer.
const LESSONS = R + '/lessons.md'
const lessons = []
const lessonsOf = () => ({ file: LESSONS, items: lessons })
// Счётчик ошибок оркестровки: класс из закрытого словаря wave-errors.sh, часы —
// от step-start файла отчёта упавшего шага до момента записи.
const err = async (cls, lane, step, note) => {
  errors.push({ cls, lane, step })
  await agent(C + '\n\nРежим счётчик: часы = (сейчас − step-start в ' + rep(lane, step) + ') / 3600, округли до 0.01 (нет файла — 0.1). Выполни `bash ' + WS + '/scripts/wave-errors.sh add ' + N + ' ' + cls + ' <часы> ' + lane + ' ' + step + ' ' + JSON.stringify(note).slice(0, 300) + '`. Верни code, out (вывод), reasons [], head "".', { ...MECH_LOW, label: 'mech:err:' + lane, phase: 'Посадка', schema: S_MECH })
}
const mechanicsReasons = new Set(['UNCOMMITTED', 'HEAD-NOT-ON-ORIGIN', 'HEAD-DIVERGED', 'HOOK-LOG-MISSING', 'HOOK-HEAD-MISMATCH', 'HOOK-RC', 'HOOK-NOT-GREEN', 'DOD-PROOF-MISSING', 'ISSUES-NONE', 'MAIN-COPY', 'GOMOD-ABOVE'])

// Метрики волны (ws#1053): сверка с оценкой предполёта; цель — 0 красных на сведённом.
const PRE = R + '/preflight.md'
const METRICS = R + '/metrics.json'
const M = { implCalls: 0, rework: 0, trialRed: 0, ciRed: 0, roleReturns: 0, preflightItems: 0 }
const metricsOf = () => ({ file: METRICS, ...M })
// Красный CI и красный стенд — перепись, потом массово (ws#1063, ws#1110, ai-tooling.md#at-red-ci-one-round):
// шаблон чинить не берётся — итог несёт порядок круга диспетчеру дословно.
const RED_ROUND = 'перепись — потом массово (ai-tooling.md#at-red-ci-one-round, владелец 2026-10-16): перепись ВСЕЙ красноты — CI читается по завершении ВСЕХ заданий (ci-read код 3 при красном и идущих), класс корня — лишь после дословной цитаты отказа, среда с двумя признаками — один перезапуск без полосы; все корни — исполнителям их классов параллельно, ОДНОЙ сборкой; проверка — только бывшее красным на внешнем кластере (stand-report.sh --of), красное — снова перепись; всё зелёное — полный прогон на внешнем кластере (stand-report.sh код 0); затем ОДИН CI; два красных CI подряд — стоп и разбор паритета'
const redOf = r => ciState(r) === 'red' ? { redRound: RED_ROUND } : {}
// Ответ без блока «### ВОЗВРАТ» (фраза ожидания, «жду монитора») — «не-выполнилось» (ws#1071,
// ai-tooling.md#at-agent-does-not-wait): в задания следующих он не подставляется; шаг
// повторяется ОДИН раз заданием дочитать .rc и журнал, снова без блока — null, полоса стоит.
const RET_MARK = '### ВОЗВРАТ'
const hasRet = t => typeof t === 'string' && t.includes(RET_MARK)
// Кэш возобновления (ws#1078, L4): шаг без ВОЗВРАТ, взятый из кэша, — снова null; args.rerun
// входит в текст дочитывания, и возобновление с новым rerun исполняет его вживую, а не из кэша.
const REREAD = 'Прошлый ответ без блока «### ВОЗВРАТ» — это «не-выполнилось». Не жди: дочитай .rc и журнал своего прогона и верни блок ВОЗВРАТ с фактом. Попытка ' + (A.rerun || 0) + '.'
const textStep = async (prompt, opts) => {
  const a = await agent(prompt, opts)
  if (hasRet(a)) return a
  const b = await agent(prompt + '\n\n' + REREAD, { ...opts, label: opts.label + ':reread' })
  return hasRet(b) ? b : null
}
const noRet = (out, l, step) => ({ ...out, stage: step + ': ответ без «### ВОЗВРАТ» и после дочитывания — не-выполнилось', report: rep(l.key, step) })
// Тело волны — внутри: итог любого исхода проходит через запись метрик (ниже).
const res = await (async () => {
// ── План ────────────────────────────────────────────────────────────────
phase('План')
const runPlan = async (lanes, round) => {
  const plan = { wave: N, targets: A.targets || {}, crossRepo: A.crossRepo === true || undefined, lanes: lanes.map(l => ({ key: l.key, repo: l.repo, dir: l.dir || '', base: l.base || A.base, head: l.head || undefined, paths: l.paths || undefined, deps: l.deps || [], declared: l.tier || undefined, repin: l.repin || undefined })) }
  return agent(C + '\n\nРежим план: запиши ровно этот JSON в ' + D + '/plan-' + round + '.json: ' + JSON.stringify(plan) + '\nВыполни `bash ' + WS + '/scripts/wave-errors.sh open ' + N + '` и `bash ' + WS + '/scripts/plan-precheck.sh ' + D + '/plan-' + round + '.json --json > ' + D + '/plan-' + round + '.out.json 2> ' + D + '/plan-' + round + '.census.txt`. Верни code (код plan-precheck), out (ТОЛЬКО последняя строка .out.json — JSON-объект плана, дословно, без строк CENSUS и пояснений), reasons (коды причин из него), head "".', { ...MECH, label: 'mech:plan:' + round, phase: 'План', schema: S_MECH })
}
let lanes = (A.lanes || []).map(l => ({ ...l }))
let plan = null
for (let round = 1; round <= 2; round++) {
  const r = await runPlan(lanes, round)
  plan = r ? parseJsonTail(r.out) : null
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

// ── Предусловия раздачи (ws#1272) ───────────────────────────────────────
// ДО предполёта и любого исполнителя, ОДНИМ механиком на волну (уроки 18–19.10: посылка
// устаревала до раздачи и всплывала лишь перед сдачей). Строки каждой полосы — база на
// origin, её задачи open, строки premise диспетчера дословно; суд — lane-precheck.sh
// --premise. Полоса с приёмкой — и текст задания автору приёмки (перепись координат,
// ws#1271). Код не 0 (2 — не судимо, не зелёное) — полоса не раздаётся, остаток с причиной,
// зависимые от неё — вслед; нет ответа — не раздаётся ни одна.
const ghRepo = r => /\//.test(String(r || '')) ? String(r) : (String(A.repo || '').split('/')[0] || 'PRO-Robotech') + '/' + (r || String(A.repo || '').split('/').pop())
const shq = s => "'" + String(s).replace(/'/g, "'\\''") + "'"
const issueLine = (l, i) => { const [r, n] = String(i).split('#'); return 'task ' + ghRepo(r === 'ws' ? 'kacho-workspace' : r || l.repo) + '#' + n + ' open' }
const premLines = l => ['branch ' + ghRepo(l.repo) + ' ' + (l.base || A.base)].concat((l.issues || []).map(i => issueLine(l, i)), l.premise || [])
const S_GATE = { type: 'object', properties: { items: { type: 'array', items: { type: 'object', properties: { n: { type: 'integer' }, code: { type: 'number' }, out: { type: 'string' } }, required: ['n', 'code', 'out'] } } }, required: ['items'] }
const gateItems = []
for (const l of lanes) {
  const f = R + '/' + l.key + '/dispatch-premise.txt'
  gateItems.push({ key: l.key, kind: 'premise', cmd: 'mkdir -p ' + R + '/' + l.key + ' && printf \'%s\\n\' ' + premLines(l).map(shq).join(' ') + ' > ' + f + ' && bash ' + WS + '/scripts/lane-precheck.sh --premise ' + f + ' > ' + rep(l.key, 'dispatch-premise') + ' 2>&1' })
  const tf = l.textFile || R + '/' + l.key + '/task.txt'
  if (tierOf[l.key].steps.includes('acceptance(<=2)')) gateItems.push({ key: l.key, kind: 'task-text', cmd: (l.textFile ? '' : 'mkdir -p ' + R + '/' + l.key + ' && printf \'%s\\n\' ' + String(l.text || '').split('\n').map(shq).join(' ') + ' > ' + tf + ' && ') + 'bash ' + WS + '/scripts/lane-precheck.sh --task-text ' + tf + ' --agent acceptance-author > ' + rep(l.key, 'dispatch-task-text') + ' 2>&1' })
}
const gate = await agent(C + '\n\nРежим предусловия раздачи волны ' + N + ' (ws#1272): каждую команду ниже выполни как есть, ОДНОЙ командой оболочки, по порядку и без остановки на ненулевом коде. code — код команды как есть: 0 — посылка верна; 1 — ложна; 2 — не судимо. Верни items — по КАЖДОМУ номеру {n, code, out (строки REASON и VOID дословно)}.' + gateItems.map((x, i) => '\n' + (i + 1) + ') [' + x.key + ' ' + x.kind + '] `' + x.cmd + '`').join(''), { ...MECH, label: 'mech:dispatch-premise', phase: 'План', schema: S_GATE })
if (!gate || !Array.isArray(gate.items)) return { ok: false, stage: 'предусловия раздачи (ws#1272): нет ответа механика — ни одна полоса не раздаётся, решает диспетчер', errors, lessons: lessonsOf() }
const gateBlock = {}
gateItems.forEach((x, i) => {
  const it = gate.items.find(y => y && y.n === i + 1)
  if (!it || it.code !== 0) gateBlock[x.key] = (gateBlock[x.key] ? gateBlock[x.key] + '; ' : '') + x.kind + ': ' + (!it ? 'исхода нет' : it.code === 1 ? 'ложно — ' + (String(it.out || '').slice(0, 300) || 'причина не названа') : 'не судимо (код ' + it.code + ')')
})
const blockStage = k => 'предусловия раздачи (ws#1272): ' + gateBlock[k] + ' — исполнитель не зван, решает диспетчер (' + rep(k, 'dispatch-premise') + ')'
// Нераздаваемые — сами и транзитивно зависимые; предполёт — лишь раздаваемым.
const held = new Set(Object.keys(gateBlock))
for (let more = true; more;) { more = false; for (const l of lanes) if (!held.has(l.key) && (l.deps || []).some(d => held.has(d))) { held.add(l.key); more = true } }
const toGo = lanes.filter(l => !held.has(l.key))
if (!toGo.length) return { ok: false, stage: 'предусловия раздачи (ws#1272): не раздаётся ни одна полоса — ' + lanes.map(l => l.key + ' — ' + (gateBlock[l.key] || 'зависит от нераздаваемой')).join('; '), remainder: lanes.map(l => ({ key: l.key, stage: gateBlock[l.key] ? blockStage(l.key) : 'зависит от нераздаваемой полосы' })), errors, lessons: lessonsOf() }

// ── Предполёт ───────────────────────────────────────────────────────────
// ДО кода, одним заходом на волну (ws#1053): карта влияния — все, кто утверждает
// или использует меняемое свойство; критерии применимых рецензентов — в задание
// полосе заранее. Нет карты по какой-либо полосе — раздачи нет (fail-closed).
phase('Предполёт')
const pre = await agent(C + '\n\nПредполёт волны ' + N + ' ДО кода (ai-tooling.md#at-one-pass-wave). КЛЮЧИ ПОЛОС: ' + toGo.map(l => l.key).join(',') + '. Полосы: ' + toGo.map(l => l.key + ' [' + tierOf[l.key].tier + ', роли ' + ((tierOf[l.key].roles || []).join('+') || 'нет') + '; пути ' + ((l.paths || []).join(', ') || 'не заданы') + ']: ' + taskOf(l)).join(' | ') + '\nКАРТА ВЛИЯНИЯ каждой полосы — все, кто утверждает или использует меняемое свойство: посевы стенда, кейсы newman, ведомости производителя и долгов (живы ли держатели — задача открыта), копии каталога прав в другом репозитории, сквозные пробы консоли, документация и приёмки, записи ревью и их гейты, профили и чарты. Пункт — «<координата> — <что утверждает> → <что поправить>», координата найдена командой (её — в отчёт). Зависимый в другом репозитории — пункт с репозиторием: его полоса идёт в ЭТУ волну, пин — на ревизию производителя с опубликованным образом (ветки волны образов не публикуют): до вливания — последний опубликованный, перенос пина строкой после публикации. Пункт чужого класса (консоль — ui-implementer) назови классом: его закрывает отдельная полоса этого исполнителя в ЭТОЙ волне. КРИТЕРИИ рецензентов — по предикатам docs/changes/policy.yaml для ролей полосы, дословно. Оценка — часы волны и ожидаемые красные на сведённом (цель 0). Запись — ' + PRE + '. ' + due('preflight') + ' Верни lanes [{key, impact, criteria}] по КАЖДОМУ ключу, estimate, report.', { agentType: 'scout', label: 'preflight', phase: 'Предполёт', schema: S_PRE })
const preMap = {}
for (const x of (pre && Array.isArray(pre.lanes) ? pre.lanes : [])) if (x && typeof x.key === 'string' && Array.isArray(x.impact) && Array.isArray(x.criteria)) preMap[x.key] = x
const noMap = toGo.filter(l => !preMap[l.key]).map(l => l.key)
if (noMap.length) return { ok: false, stage: 'предполёт: нет карты влияния по полосам ' + noMap.join(', ') + ' — раздачи нет, решает диспетчер', report: PRE, errors, lessons: lessonsOf() }
for (const l of toGo) M.preflightItems += preMap[l.key].impact.length
// Пункт карты закрыт строкой «<n> → правка <путь>» либо «<n> → не затронуто — потому что <довод>».
const CLOSED = n => new RegExp('^' + n + '\\s*(?:→|->)\\s*(?:правка\\s+\\S|не затронуто — потому что\\s+\\S)')
const unclosed = (l, r) => { const got = r && Array.isArray(r.impact) ? r.impact.filter(x => typeof x === 'string').map(x => x.trim()) : []; return preMap[l.key].impact.map((_, i) => i + 1).filter(n => !got.some(x => CLOSED(n).test(x))) }
const mapText = l => { const m = preMap[l.key]; return '\nКАРТА ВЛИЯНИЯ (предполёт, ' + PRE + '): ' + (m.impact.length ? m.impact.map((x, i) => (i + 1) + ') ' + x).join('; ') : 'пунктов нет') + '. Каждый пункт закрой В ЭТОЙ полосе правкой либо «не затронуто — потому что …»; полоса с незакрытым пунктом не сдаётся. Критерии рецензентов: ' + (m.criteria.join('; ') || 'нет') + '.' }

// Имя временной сводки — по правилу репозитория `<N>-<суффикс>` (git-issues.md
// §«Имя ветки»): N — задача волны, суффикс — `stack-<ключ>` kebab-case ≤ 40.
// Полоса с веткой-номером — сводка в её же ветке (ws#946): имя уже то, что
// принимает хук её репозитория, и другого шаблон не выдумывает.
const inLane = l => /^[0-9]+$/.test(String(l.branch || ''))
const stackName = l => inLane(l) ? String(l.branch) : N + '-stack-' + (String(l.key).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+/, '').slice(0, 34).replace(/-+$/, '') || 'lane')
const stackNames = {}
for (const l of lanes) {
  if (!(l.deps || []).length) continue
  const s = stackName(l)
  if (!inLane(l) && !/^[0-9]+-[a-z0-9][a-z0-9-]*$/.test(s) || s.length - s.indexOf('-') - 1 > 40) return { ok: false, stage: 'план', why: 'имя сводки deps «' + s + '» полосы ' + l.key + ' не по форме <N>-<суффикс> — номер волны не число' }
  if (Object.values(stackNames).includes(s)) return { ok: false, stage: 'план', why: 'имя сводки deps «' + s + '» совпало у двух полос — ключи различаются только знаками' }
  stackNames[l.key] = s
}

// ── Полосы ──────────────────────────────────────────────────────────────
phase('Полосы')
const review = async (role, l, head, prevHead, label, stack) => agent(C + '\n\nРевью ' + role + ': полоса ' + l.key + ' ветка ' + l.branch + ' @' + head + (prevHead ? ' — только дельта `git diff ' + prevHead + '..' + head + '` (принятое не переоткрывается)' : (stack ? ' — своя дельта `git diff ' + stack.head + '..' + head + '` (сводка deps ' + stack.branch + ' — код принятых полос, не предмет ревью)' : '')) + '. Отчёт задания и исполнителя — ' + rep(l.key, 'implement') + '. Запись — ' + rep(l.key, label) + '. ' + due('review') + ' Верни verdict, sha (голова, которую смотрел), blocking (пусто при accept), report.', { agentType: role, label: label + ':' + l.key, phase: 'Полосы', schema: S_REV })
const precheck = async (l, impl, stack) => agent(C + '\n\nРежим lane-precheck (LANE_PRECHECK_WS — корень воркспейса ' + ROOT + ', дом копий полос; KACHO_WS скрипт не читает; без неё корень выводится из места скрипта — WS-UNKNOWN или MAIN-COPY, ws#1016): `LANE_PRECHECK_WS=' + ROOT + ' bash ' + WS + '/scripts/lane-precheck.sh ' + impl.copy + ' ' + impl.branch + ' ' + (stack ? stack.head : (l.base || A.base)) + ' ' + (impl.issues || []).map(i => '--issue ' + i).join(' ') + ' --hook-log ' + impl.hookLog + ' > ' + rep(l.key, 'lane-precheck') + ' 2>&1`. Верни code, out (последние строки), reasons (коды из строк REASON), head (голова ветки в копии).', { ...MECH, label: 'mech:precheck:' + l.key, phase: 'Полосы', schema: S_MECH })
const neighbours = l => lanes.filter(x => x.key !== l.key).map(x => x.key + ': ' + ((x.paths || []).join(', ') || 'перечень не задан')).join('; ')
// Исполнитель с hookLog не путём — одна доводка тем же заданием; снова не путь —
// полоса стоит (runLane), предпроверка вслепую не зовётся.
const implement = async (l, tdd, extra, stack) => {
  const r = await implementOnce(l, tdd, extra, stack)
  if (r && typeof r.lesson === 'string' && r.lesson.trim() && r.lesson.trim() !== '—') lessons.push({ key: l.key, lesson: r.lesson.trim() })
  if (!r || !sha40(r.head) || ['blocked', 'failed'].includes(r.status)) return r
  const fix = []
  if (!isPath(r.hookLog)) fix.push('hookLog «' + String(r.hookLog).slice(0, 80) + '» — не путь: верни путь журнала отправки ' + R + '/' + l.key + '/push.log')
  const gap = unclosed(l, r)
  if (gap.length) fix.push('КАРТА ВЛИЯНИЯ: пункты ' + gap.join(', ') + ' не закрыты — закрой их в этой полосе и верни в impact')
  if (!fix.length) return r
  return implementOnce(l, tdd, (extra ? extra + '\n' : '') + fix.join('\n'), stack)
}
// Полоса SQL/миграции (ws#1242 п.3): красное фикстуры (CHECK имени, разрешения) выглядело
// красным предмета и стоило прогона на кластере; убранная охрана прошла пробы предмета и упала
// лишь в чужой переписи подъёма. Задание такой полосы несёт обе строки; прочим — не несёт.
const sqlLane = l => ['sql', 'migration'].includes(l.class) || l.agent === 'migration-writer' || (l.paths || []).some(p => /(^|\/)migrations\/|\.sql$/.test(p))
const SQL_RULE = '\nSQL/МИГРАЦИЯ: пробу с новой фикстурой прогони на голове ДО правки и прочти текст отказа до записи «красное» (CHECK имени или разрешений фикстуры — красное фикстуры, не предмета). Перепись подъёма (TestIntegration_RoleComposition* и иные читатели схемы) — в том же прогоне, что пробы предмета, не отдельным шагом.'
// Круг переделки — каждый вызов исполнителя полосы после первого (метрика волны).
const impl1st = {}
const implementOnce = async (l, tdd, extra, stack) => (M.implCalls++, impl1st[l.key] ? M.rework++ : (impl1st[l.key] = true), agent(C + '\n\nПолоса ' + l.key + ' (' + tierOf[l.key].tier + '), ветка ' + l.branch + ' от ' + (stack ? 'сводки deps ' + stack.branch + '@' + stack.head + ' (в ней код полос ' + (l.deps || []).join(', ') + (inLane(l) ? '; сводка уже в твоей ветке на origin — продолжай её от этой головы, не переписывая)' : '; ветка уже есть на origin — влей сводку в неё коммитом слияния, не переписывая)') : (l.base || A.base)) + ', копия — ' + D + '/' + l.key + '/copy. ' + (tdd ? 'Строгий TDD: красная проба до кода. ' : '') + 'Задание: ' + taskOf(l) + (l.ctx ? '\nКонтекст: ' + l.ctx : '') + mapText(l) + (sqlLane(l) ? SQL_RULE : '') + '\n' + FILES_RULE + ' Твой перечень: ' + ((l.paths || []).join(', ') || 'не задан') + '. Перечни соседей: ' + (neighbours(l) || 'соседей нет') + '.' + (extra ? '\nДоводка: ' + extra : '') + '\nСдача: коммит, DoD-proof в каждой задаче, отправка своей ветки через слот с журналом `{ echo "lane-push head=$(git rev-parse HEAD)"; git push origin HEAD:refs/heads/' + l.branch + ' 2>&1; echo "lane-push rc=$?"; } > ' + R + '/' + l.key + '/push.log`. Отчёт — ' + rep(l.key, 'implement') + '. ' + due('implement') + ' Верни status, branch, head, copy, hookLog (ПУТЬ к журналу отправки ' + R + '/' + l.key + '/push.log, а не слово об исходе), issues (владелец/репо#N), impact (по пункту карты строкой «<n> → правка <путь>» либо «<n> → не затронуто — потому что <довод>»), report (содержательный итог: что сделано, какие файлы, исход проверок числами, взятые файлы вне перечня), lesson (урок полосы — ошибка, переделка, лишний агент или круг, ложный отказ гейта, застой, обход — строкой «<класс> · <где предотвратить>», её же допиши `>> ' + LESSONS + '` с префиксом «' + l.key + ' · »; урока нет — «—», в файл не пиши).', { agentType: l.agent, label: 'impl:' + l.key, phase: 'Полосы', schema: S_IMPL }))
// Сводка голов deps: временная ветка от свежей базы, головы — коммитами слияния
// (--no-ff, без rebase/reset/force); уже есть на origin — дописывается. Факт
// содержания — `git merge-base --is-ancestor` по каждой голове, а не слово.
const mergeSubj = (l, b) => '«#' + l.branch + ' merge ' + (/^[0-9]+$/.test(String(b)) ? '#' + b : b) + ': …»'
const stackOf = async (l, deps) => agent(C + '\n\nРежим сводка deps полосы ' + l.key + ': в копии ' + D + '/' + l.key + '/stack от свежего origin/' + (l.base || A.base) + ' заведи ветку ' + stackNames[l.key] + ' и влей в неё по порядку ' + deps.map(d => d.branch + '@' + d.head).join(', ') + ' коммитами слияния pointpu --no-ff' + (inLane(l) ? ' (это ветка самой полосы — хук репозитория принимает лишь номер; первая строка слияния — ' + [l.base || A.base, ...deps.map(d => d.branch)].map(b => mergeSubj(l, b)).join(', ') + ')' : '') + '. Ветка уже есть на origin — не перезаписывай: влей в неё свежую базу и недостающие головы. Конфликт по существу не решай: `git merge --abort`, верни status conflict и пути в conflicts. Отправь ветку через слот (журнал ' + R + '/' + l.key + '/stack.push.log). ФАКТ: для каждой головы `git merge-base --is-ancestor <голова> HEAD` — код 0; в contains — головы, прошедшие эту проверку. Отчёт — ' + rep(l.key, 'stack') + '. Верни status, branch, head, contains, conflicts, report.', { ...MECH, label: 'mech:stack:' + l.key, phase: 'Полосы', schema: S_STACK })

// Полоса стенда и сборки образов (ws#1191; класс — args.lanes[].class stand|images либо
// исполнитель deploy-engineer) работает на головах, которые УЖЕ на origin: строки `head
// <репо> <ветка> <sha>` порождает шаблон — из веток и голов deps и сводки, а без deps — из
// branch и head самой полосы; судит `lane-precheck.sh --premise`. Код не 0 либо строк нет —
// исполнитель не зван: kacho#3284 — полоса стенда ушла раньше, чем голова доехала до origin.
const STAND_CLASS = ['stand', 'images']
const standLane = l => STAND_CLASS.includes(l.class) || l.agent === 'deploy-engineer'
const headLines = (l, ds, stack) => (ds && ds.length ? ds.map(d => 'head ' + ghRepo(d.repo) + ' ' + d.branch + ' ' + d.head).concat(stack ? ['head ' + ghRepo(l.repo) + ' ' + stack.branch + ' ' + stack.head] : []) : (sha40(l.head) && l.branch ? ['head ' + ghRepo(l.repo) + ' ' + l.branch + ' ' + l.head] : []))
const headGate = async (l, ds, stack) => {
  if (!standLane(l)) return null
  const lines = headLines(l, ds, stack)
  if (!lines.length) return { key: l.key, ok: false, stage: 'полоса стенда и образов без головы: ни deps, ни branch и head sha40 в задании — предусловия головы на origin нет, исполнитель не зван (ws#1191)' }
  const f = R + '/' + l.key + '/premise.txt'
  const p = await agent(C + '\n\nРежим предусловие головы полосы ' + l.key + ' (ws#1191): выполни ОДНОЙ командой `mkdir -p ' + R + '/' + l.key + ' && printf \'%s\\n\' ' + lines.map(x => "'" + x + "'").join(' ') + ' > ' + f + ' && bash ' + WS + '/scripts/lane-precheck.sh --premise ' + f + ' > ' + rep(l.key, 'premise') + ' 2>&1`. code — код команды как есть: 0 — головы на origin те; 1 — PREMISE-FALSE; 2 — не судимо. Верни code, out (строки REASON и VOID дословно), reasons (коды из строк REASON), head "".', { ...MECH, label: 'mech:premise:' + l.key, phase: 'Полосы', schema: S_MECH })
  if (p && p.code === 0) return null
  return { key: l.key, ok: false, stage: 'предусловие головы на origin (ws#1191): ' + (!p ? 'нет ответа' : p.code === 1 ? 'ложно — ' + (String(p.out || '').slice(0, 300) || 'причина не названа') : 'не судимо (код ' + p.code + ')') + ' — исполнитель не зван', report: rep(l.key, 'premise') }
}
const runLane = async (l, stack) => {
  const t = tierOf[l.key]
  const has = s => t.steps.includes(s)
  const out = { key: l.key, tier: t.tier, ok: false, reviews: [] }
  if (has('acceptance(<=2)')) {
    let acc = null
    for (let r = 1; r <= 2; r++) {
      const a1 = await textStep(C + '\n\nПриёмка полосы ' + l.key + ' (смена публичного контракта либо миграция): ' + taskOf(l) + (acc ? '\nВозврат круга ' + (r - 1) + ': ' + rep(l.key, 'acceptance-review-' + (r - 1)) : '') + '. Отчёт — ' + rep(l.key, 'acceptance-' + r) + '.', { agentType: 'acceptance-author', label: 'acc:' + l.key + ':' + r, phase: 'Полосы' })
      if (!a1) return noRet(out, l, 'acceptance-' + r)
      acc = await review('acceptance-reviewer', l, '', '', 'acceptance-review-' + r)
      if (acc && acc.verdict === 'accept') break
    }
    if (!acc || acc.verdict !== 'accept') return { ...out, stage: 'приёмка: 2 круга исчерпаны — спор решает диспетчер', report: rep(l.key, 'acceptance-review-2') }
    // Имитация клиента — по замыслу ДО кода, а не только перед MR эпика (ws#1053).
    const s1 = await textStep(C + '\n\nИмитация клиента ДО кода, полоса ' + l.key + ': по одобренной приёмке (' + R + '/' + l.key + '/acceptance-*.md) пройди сценарии клиента меняемого контракта; блокеры — пунктами условий к коду. Контракт не меняется — так и запиши. Запись — ' + rep(l.key, 'client-sim') + ' (её путь получит исполнитель). ' + due('review'), { agentType: 'client-simulator', label: 'sim:' + l.key, phase: 'Полосы' })
    if (!s1) return noRet(out, l, 'client-sim')
  }
  if (has('surface-census')) {
    const c1 = await textStep(C + '\n\nПерепись поверхности ДО кода, полоса ' + l.key + ': ' + taskOf(l) + '. Слушатели, RPC, каталог прав, секреты, профили. Запись — ' + rep(l.key, 'surface-census') + ' (её путь получит исполнитель).', { agentType: 'security-auditor', label: 'census:' + l.key, phase: 'Полосы' })
    if (!c1) return noRet(out, l, 'surface-census')
  }
  const tdd = has('implementer-tdd')
  let impl = await implement(l, tdd, [has('surface-census') ? 'перепись поверхности — ' + rep(l.key, 'surface-census') : '', has('acceptance(<=2)') ? 'имитация клиента до кода — ' + rep(l.key, 'client-sim') : ''].filter(Boolean).join('; '), stack)
  if (!impl || ['blocked', 'failed'].includes(impl.status) || !sha40(impl.head)) return { ...out, stage: 'исполнитель', report: rep(l.key, 'implement') }
  if (!isPath(impl.hookLog)) return { ...out, stage: 'исполнитель: hookLog не путь и после доводки (' + JSON.stringify(impl.hookLog === undefined ? null : impl.hookLog).slice(0, 60) + ')', report: rep(l.key, 'implement') }
  const gap = unclosed(l, impl)
  if (gap.length) return { ...out, stage: 'карта влияния: пункты ' + gap.join(', ') + ' не закрыты и после доводки — полоса не сдаётся', report: rep(l.key, 'implement') }
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
      M.roleReturns += back.length
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
  const gapEnd = unclosed(l, impl)
  if (gapEnd.length) return { ...out, stage: 'карта влияния: на сданной голове пункты ' + gapEnd.join(', ') + ' не закрыты', report: rep(l.key, 'implement') }
  return { ...out, ok: true }
}
// Порядок — по deps (слои плана): полоса стартует, когда ВСЕ её deps прошли;
// независимая — сразу. Зависимая — от сводки голов deps (ws#938): без неё в
// ветке полосы нет кода предшественника, а сводит полосы только сборка.
// Пробная сборка НЕПРЕРЫВНАЯ (ws#1053): прошедшая полоса сразу сводится с уже
// вошедшими; хук отправки судит СВЕДЁННОЕ: `git push --dry-run` на ветку САМОЙ
// полосы — её имя хук репозитория уже принял, и кандидат — её потомок (перемотка
// вперёд; на занятое имя волны git отверг бы его до хука, и хук не судил бы ничего). Пробы идут по одной (одна копия —
// один писатель); красное — полоса в остаток, на origin ничего не меняется.
let trialChain = Promise.resolve()
const trialIn = (l, r) => (trialChain = trialChain.then(async () => {
  const t = await agent(C + '\n\nРежим пробная сборка полосы ' + l.key + ': в копии ' + D + '/trial (нет — клон от свежего origin/' + (A.base || '?') + ', ветка trial) заведи `git switch -C cand-' + l.key + ' trial` и влей ' + l.branch + '@' + r.head + ' коммитом слияния pointpu --no-ff; конфликт — `git merge --abort`, code 1, пути в reasons.' + UI_DEPS + ' Суд СВЕДЁННОГО — хук отправки через слот: `git push --dry-run origin HEAD:refs/heads/' + l.branch + '` (кандидат — потомок головы полосы; ' + HOMES + '), журнал ' + R + '/' + l.key + '/trial.push.log. code: 0 — хук зелёный, затем `git switch trial && git merge --ff-only cand-' + l.key + '`; 1 — красное на сведённом (зависимый не поправлен), trial не двигать, в reasons — упавшие проверки; 2 — не выполнилось (слот 74/75/76). Верни code, out, reasons, head (голова cand).', { ...MECH, label: 'mech:trial:' + l.key, phase: 'Полосы', schema: S_MECH })
  if (t && t.code === 1) { M.trialRed++; return { ...r, ok: false, stage: 'пробная сборка: красное на сведённом — ' + ((t.reasons || []).join(', ') || 'причина не названа') + ' (' + R + '/' + l.key + '/trial.push.log)' } }
  if (!t || t.code !== 0) log('пробная сборка ' + l.key + ': не выполнилась (код ' + (t ? t.code : 'нет ответа') + ') — суд сведённого за CI сборки')
  return r
}))
const layers = plan.layers && plan.layers.length ? plan.layers : [lanes.map(l => l.key)]
const done = {}
const stacks = []
const started = {}
const launch = k => started[k] || (started[k] = (async () => {
  const l = lanes.find(x => x.key === k)
  if (!l) return (done[k] = { key: k, ok: false, stage: 'полосы ' + k + ' нет в задании' })
  if (gateBlock[k]) return (done[k] = { key: k, ok: false, stage: blockStage(k), report: rep(k, 'dispatch-premise') })
  const deps = await Promise.all((l.deps || []).map(launch))
  const notReady = deps.filter(d => !d.ok)
  let r
  if (notReady.length) r = { key: k, ok: false, stage: 'не начата: deps ' + notReady.map(d => d.key).join(', ') + ' не прошли' }
  else if (!deps.length) r = (await headGate(l, [], null)) || await runLane(l, null)
  else {
    const ds = deps.map(d => ({ branch: lanes.find(x => x.key === d.key).branch, head: d.head, repo: lanes.find(x => x.key === d.key).repo }))
    const st = await stackOf(l, ds)
    const missing = st ? ds.filter(d => !(st.contains || []).includes(d.head)) : ds
    if (st && sha40(st.head) && !inLane(l)) stacks.push(st.branch || stackNames[k])
    if (!st || st.status === 'conflict' || !['done', 'already-done'].includes(st.status) || !sha40(st.head) || missing.length) {
      r = { key: k, ok: false, stage: 'сводка deps ' + stackNames[k] + ': ' + (st && st.status === 'conflict' ? 'конфликт в ' + ((st.conflicts || []).join(', ') || 'путях без имени') : !st ? 'нет ответа' : !['done', 'already-done'].includes(st.status) ? 'статус ' + st.status : !sha40(st.head) ? 'голова сводки не sha40 (' + JSON.stringify(st.head === undefined ? null : st.head).slice(0, 60) + ')' : missing.length ? 'нет голов ' + missing.map(d => d.branch + '@' + String(d.head).slice(0, 12)).join(', ') : 'причина не названа') + ' — исполнитель не зван, решает диспетчер', conflicts: st ? st.conflicts || [] : [], report: rep(k, 'stack') }
    } else { const so = { branch: inLane(l) ? stackNames[k] : st.branch || stackNames[k], head: st.head }; r = (await headGate(l, ds, so)) || await runLane(l, so) }
  }
  if (r.ok) r = await trialIn(l, r)
  done[k] = r
  return r
})())
await Promise.all(layers.flat().map(launch))
// Вердикт — о своей полосе: непрошедшая (и не начатая из-за неё зависимая) —
// остаток, соседи с полными фактами идут в сборку. Не прошла ни одна — стоп.
const remainder = Object.values(done).filter(r => !r.ok).map(r => ({ key: r.key, stage: r.stage }))
let order = layers.flat().filter(k => done[k] && done[k].ok)
if (!order.length) return { ok: false, stage: 'полосы', lanes: done, remainder, stacks, errors, lessons: lessonsOf() }
// Снять полосы и транзитивно зависимых от них (в сборке без предшественника нет кода).
const dropWithDeps = (keys, why) => {
  const gone = new Set(keys)
  for (let grew = true; grew;) { grew = false; for (const k of order) if (!gone.has(k) && ((lanes.find(l => l.key === k) || {}).deps || []).some(d => gone.has(d))) { gone.add(k); grew = true } }
  for (const k of order) if (gone.has(k)) remainder.push({ key: k, stage: keys.includes(k) ? why : 'зависит от снятой ' + keys.join(', ') })
  order = order.filter(k => !gone.has(k))
}

// ── Сборка ──────────────────────────────────────────────────────────────
phase('Сборка')
const steps = new Set(order.flatMap(k => tierOf[k].steps))
const assemble = async round => agent(C + '\n\nРежим сборка ' + round + ': в копии ' + D + '/assemble от свежего origin/' + (A.base || '?') + ' сведи в ветку волны ' + N + ' полосы по порядку ' + order.map(k => lanes.find(l => l.key === k).branch + '@' + done[k].head).join(', ') + ' коммитами слияния pointpu --no-ff; конфликт по существу не решай — верни conflicts.' + UI_DEPS + ' Отправь ветку волны через слот (журнал ' + D + '/assemble-' + round + '.push.log); PR ' + N + ' → ' + (A.epic || A.base) + ' открой ЧЕРНОВИКОМ (`gh pr create --draft`), если его нет: на черновике конвейер исполняет только затронутое, полный прогон — один раз перед посадкой (ws#1013); доводки идут в черновике, затронутое до отправки судит хук отправки Job-ом слота, на машине не гоняется (ws#1301) (заголовок «#' + N + ' …»; тело — ТОЛЬКО вывод генератора (ws#1146), руками не пишется: `RITUAL_REPO_DIR=' + D + '/assemble bash ' + WS + '/scripts/pr-body.sh ' + (A.repo || '?') + ' origin/' + (A.epic || A.base || '?') + ' HEAD > ' + R + '/pr-body-' + round + '.md` (код не 0 — status failed, PR не трогать) в `gh pr create --draft --body-file`, PR есть — `gh pr edit --body-file`). Отчёт — ' + D + '/assemble-' + round + '.md. Верни status, head, copy, pr, conflicts, report.', { ...MECH, label: 'mech:assemble:' + round, phase: 'Сборка', schema: S_ASM })
let asm = await assemble(1)
if (!asm || !['done', 'already-done'].includes(asm.status) || !sha40(asm.head)) return { ok: false, state: 'failed', stage: 'сборка', conflicts: asm ? asm.conflicts : [], errors, lessons: lessonsOf() }
// Номер PR идёт в задания рецензента, CI, предпроверки и вливания. Не целое ≥ 1
// (нет поля, 0, строка «—», адрес) — остановка ЗДЕСЬ с причиной: иначе шаги ниже
// получили бы «PR #undefined» и судили бы не тот запрос либо никакой (ws#935).
if (!Number.isInteger(asm.pr) || asm.pr < 1) return { ok: false, state: 'failed', stage: 'сборка: номер PR не целое ≥ 1 (' + JSON.stringify(asm.pr === undefined ? null : asm.pr) + ') — рецензент, CI и посадка без номера не зовутся', head: asm.head, errors, lessons: lessonsOf() }
const waveReviews = []
if (steps.has('wave-reviewer')) {
  let wr = await agent(C + '\n\nСверка волны ' + N + ' на сборке @' + asm.head + ' (PR #' + asm.pr + '): полосы ' + order.join(', ') + ', отчёты — ' + R + '/<полоса>/implement.md. Пять классов столкновений; один раз на волну. Сообщения коммитов `' + logRange(A.base || '?', asm.head) + '` судятся признаком восстановимости (security-disclosure.md#disc-recoverability-predicate): до-фиксное состояние уязвимости в тексте — return полосы; код 2 (диапазон пуст либо не разрешился) — return, а не accept (ws#1078, L11). Вердикт — по КАЖДОЙ полосе в lanes (key, verdict, blocking): возврат одной полосы соседние не снимает. Запись — ' + D + '/wave-review.md. Верни verdict, sha (голова сборки), blocking, lanes, report.', { agentType: 'wave-reviewer', label: 'review-wave', phase: 'Сборка', schema: S_WREV })
  const per = wr && Array.isArray(wr.lanes) ? wr.lanes : []
  const verdictOf = k => (per.find(x => x && x.key === k) || {}).verdict
  const covered = order.every(k => ['accept', 'return'].includes(verdictOf(k)))
  const back = order.filter(k => verdictOf(k) === 'return')
  if (wr && wr.verdict === 'return' && covered && back.length) { // все вернули — пусто после снятия, стоп ниже
    // Возврат — о своих полосах: снять их (с зависимыми), пересвести без них;
    // рецензент — лишь проверка исполнения по дельте сборок, не второй круг.
    dropWithDeps(back, 'возврат рецензента волны — ' + D + '/wave-review.md')
    // Зависимые снялись вслед за возвращёнными — сводить может быть нечего.
    if (!order.length) return { ok: false, state: 'failed', stage: 'рецензент волны вернул ' + back.join(', ') + ', зависимые сняты вслед — сводить нечего, вливания нет', remainder, errors, lessons: lessonsOf() }
    const prevAsm = asm.head
    asm = await assemble(2)
    if (!asm || !['done', 'already-done'].includes(asm.status) || !sha40(asm.head) || !Number.isInteger(asm.pr) || asm.pr < 1) return { ok: false, state: 'failed', stage: 'пересведение без возвращённых полос', remainder, errors, lessons: lessonsOf() }
    wr = await agent(C + '\n\nПроверка исполнения сверки волны ' + N + ': сняты полосы ' + remainder.map(x => x.key).join(', ') + '; только дельта `git diff ' + prevAsm + '..' + asm.head + '` (принятое не переоткрывается), полосы ' + order.join(', ') + '. Запись — ' + D + '/wave-review-2.md. Верни verdict, sha (голова сборки), blocking, lanes, report.', { agentType: 'wave-reviewer', label: 'review-wave-2', phase: 'Сборка', schema: S_WREV })
  } else if (wr && wr.verdict === 'accept' && back.length) wr = { ...wr, verdict: 'void' } // свод «принято» при возврате полосы — противоречие, факта нет
  if (!wr || wr.verdict !== 'accept') return { ok: false, stage: 'рецензент волны — ' + (wr && wr.verdict === 'return' && !covered ? 'возврат без вердикта по каждой полосе: факта нет, ' : 'возврат; ') + 'доводка по ' + D + '/wave-review.md в ветках полос и пересведение решает диспетчер', blocking: wr ? wr.blocking : [], remainder, errors, lessons: lessonsOf() }
  waveReviews.push({ role: 'wave-reviewer', sha: wr.sha, verdict: wr.verdict, blocking: wr.blocking })
}
// CI: «идёт» — ждать, не провал; вердикт — только на голове сборки и только
// кодом scripts/ci-read.sh (ws#1006): полный набор, завершённые прогоны,
// обязательные контексты базы, свежая база.
// Пауза — в ТОЙ ЖЕ команде, что чтение: часы машины до и после sleep, строка SLEPT.
const pauseCmd = 's0=$(date +%s); sleep ' + CI_PAUSE_S + '; echo "SLEPT $(( $(date +%s) - s0 ))"; '
// Перепись прогоном на ВНЕШНЕМ кластере ДО CI (ws#1110, ai-tooling.md#at-red-ci-one-round,
// владелец 2026-10-16): весь затронутый набор теми же целями, что CI, без остановки на
// первом красном; ready и вливание — лишь при коде 0 stand-report.sh по отчёту ЭТОЙ
// головы (landing-precheck --stand-report судит его снова). Прогон долгий — отсоединённо:
// шаг запускает либо дочитывает (код 3 — идёт), шаблон читает с паузой, как CI.
const STAND = D + '/stand.json'
const STAND_EXP = D + '/stand-expect.json'
const standRead = (i, out) => agent(C + '\n\nРежим стенд (перепись прогоном, ai-tooling.md#at-red-ci-one-round), чтение ' + (i + 1) + ' из ' + CI_READS + ': ' + (A.repo || '?') + ' PR #' + asm.pr + ', голова ' + asm.head + '. ' + (i > 0 ? 'Сначала пауза ОДНОЙ командой `' + pauseCmd + 'true`, затем ' : '') + 'ожидаемое выводит механизм, не отчёт: `bash ' + WS + '/scripts/stand-report.sh expect --checkout ' + D + '/assemble --head ' + asm.head + ' --base origin/' + (A.epic || A.base || '?') + ' --draft false > ' + STAND_EXP + '` (выбор ready — основание ready и вливания; не 0 — code 2); отчёт ' + STAND + ' о голове ' + asm.head + ' есть и прогон завершён — выполни `bash ' + WS + '/scripts/stand-report.sh check ' + STAND + ' --head ' + asm.head + ' --expect ' + STAND_EXP + '`; прогон этой головы идёт (pid жив, .rc нет) — code 3; прогона нет — ЗАПУСТИ ОДИН раз: на ВНЕШНЕМ кластере через `' + WS + '/scripts/heavy-slot.sh --enqueue ' + D + ' <класс> -- …` (билет держится, код — в .rc строки ENQUEUED; 74/75 повтором не лечится) (стенд — `make stand-ns-run NS=t' + N + '-w<k>` своего прогона: подъём и снятие им же на любом исходе, census после 0) КАЖДОЕ задание jobs из ' + STAND_EXP + ' теми же целями, что CI, без остановки на первом красном; набор, которому до ws#1110 п.1 нет образов ветки PR, — outcome not-run, reason NO-PR-IMAGES; отчёт — форма шапки scripts/stand-report.sh (head, mode full, context, ns, planned, suites с job задания и дословной цитатой у красного, residue) в ' + STAND + ', затем code 3. code: 0 — полный зелёный; 1 — причины stand-report.sh; 2 — не выполнилось (слот 74–77); 3 — идёт. ' + due('mech') + ' Отчёт шага — ' + out + '. Верни code, out (строки REASON и VERDICT), reasons (коды из строк REASON), head (' + asm.head + '), slept (' + (i > 0 ? 'число из строки SLEPT' : '0 — паузы не было') + ').', { ...MECH, agentType: 'ci-watcher', label: 'mech:stand:' + i, phase: 'Сборка', schema: S_CI })
let stand = null
for (let i = 0; i < CI_READS; i++) {
  const got = await standRead(i, D + '/stand-' + i + '.md')
  if (i > 0 && !(got && Number.isFinite(got.slept) && got.slept + CI_SLEPT_SLACK >= CI_PAUSE_S)) { stand = { code: 3, reasons: ['PAUSE-SKIPPED'] }; continue }
  stand = got
  if (!stand || stand.code !== 3) break
}
if (!stand || stand.code !== 0) return { ok: false, state: stand && stand.code === 3 ? 'running' : 'failed', stage: 'внешний стенд до CI: ' + (!stand ? 'нет ответа' : stand.code === 3 ? 'прогон идёт' : stand.code === 1 ? 'красное либо отчёт не полон — ' + ((stand.reasons || []).join(', ') || 'причина не названа') : 'не выполнилось (код ' + stand.code + ')') + ' — ready, CI и вливания нет (' + STAND + ')', pr: asm.pr, head: asm.head, reasons: stand ? stand.reasons || [] : [], ...(stand && stand.code === 1 ? { redRound: RED_ROUND } : {}), errors, lessons: lessonsOf() }
const ciRead = (what, head, pause, label, out) => agent(C + '\n\nРежим CI, ' + what + ': ' + (A.repo || '?') + ' PR #' + asm.pr + ', голова ' + head + '. ' + (pause ? 'Пауза и чтение — ОДНА команда, исполни её целиком, не деля: ' : 'Прочти вердикт ОДИН раз командой: ') + '`' + (pause ? pauseCmd : '') + recipeRun('ci-read.sh', (A.repo || '?') + ' ' + asm.pr, out) + '` (scripts/ci-read.sh рецептом «ЗАПУСК»; `gh pr checks` и check-runs мимо скрипта не читай, без --watch, без цикла); code — код этой команды: 0 green · 1 red · 2 не прочитано · 3 идёт или набор неполон · 4 база устарела · 5 целевой зелёный черновика (не основание вливать); код не толкуй, идёт — сразу верни: повтор делает шаблон. ' + due('ci', pause ? Math.ceil(CI_PAUSE_S / 60) : 0) + ' Отчёт — ' + out + '. Верни code, out (строки REASON и VERDICT), reasons (коды из строк REASON), head (голова из строки VERDICT), slept (' + (pause ? 'число из строки SLEPT' : '0 — паузы не было') + ').', { ...MECH, agentType: 'ci-watcher', label, phase: 'Сборка', schema: S_CI })
// Лимит GitHub (урок 2026-10-16, ws#1110): REASON RATE-LIMIT ci-read, landing-precheck и
// merge-readiness — «не выполнилось» со временем сброса, а не красное и не тайм-аут.
const rateOf = r => !!(r && Array.isArray(r.reasons) && r.reasons.includes('RATE-LIMIT'))
const rateStop = (what, r, head) => ({ ok: false, state: 'not-run', stage: what + ': лимит GitHub исчерпан — не выполнилось, не красное; ' + ((String(r.out || '').match(/сброс в \d\d:\d\d/) || ['время сброса — в отчёте шага'])[0]), pr: asm.pr, head, reasons: r.reasons, errors, lessons: lessonsOf() })
let ci = null
let skipped = 0
// Черновик (ws#1013): ci-read код 5 — целевой зелёный. Это не основание вливать:
// PR переводится в ready ОДИН раз (событие ready_for_review заводит полный прогон
// того же состава). Полный прогон шаблон НЕ ждёт: его ждёт и судит демон вливания
// (ws#1147, ws#1152), чтение CI после перевода — ожидание агентом, которое он заменил.
let readied = false
for (let i = 0; i < CI_READS; i++) {
  const got = await ciRead('чтение ' + (i + 1) + ' из ' + CI_READS, asm.head, i > 0, 'mech:ci:' + i, D + '/ci-' + i + '.md')
  // Чтение с паузой при slept < N−10 (нет поля, не число, мало) — отвергнуто: его код
  // не судится, состояние — «идёт», цикл продолжается (ws#1010).
  if (i > 0 && !(got && typeof got.slept === 'number' && got.slept >= CI_PAUSE_S - CI_SLEPT_SLACK)) { skipped++; ci = { code: 3, reasons: ['PAUSE-SKIPPED'], head: asm.head, slept: got ? got.slept : null }; log('CI чтение ' + (i + 1) + ': пауза не исполнена (slept ' + JSON.stringify(got ? got.slept : null) + ' < ' + (CI_PAUSE_S - CI_SLEPT_SLACK) + ') — чтение отвергнуто'); continue }
  ci = got
  if (rateOf(ci)) return rateStop('CI', ci, asm.head)
  if (ciState(ci) === 'targeted-green' && !readied && sha40(ci.head) === asm.head) {
    readied = true
    const rd = await agent(C + '\n\nРежим ready: PR #' + asm.pr + ' (' + (A.repo || '?') + ') — черновик, целевой прогон зелёный (ci-read код 5, ' + D + '/ci-' + i + '.md). Переведи запрос в готовый ОДНОЙ командой `gh pr ready ' + asm.pr + ' -R ' + (A.repo || '?') + '` — событие ready_for_review заводит полный прогон. ФАКТ: `gh pr view ' + asm.pr + ' -R ' + (A.repo || '?') + ' --json isDraft` — false. Верни code (0 — isDraft false), out, reasons [], head "".', { ...MECH, label: 'mech:ready', phase: 'Сборка', schema: S_MECH })
    if (!rd || rd.code !== 0) return { ok: false, state: 'failed', stage: 'перевод PR #' + asm.pr + ' в ready не исполнен — полного прогона нет', pr: asm.pr, head: asm.head, errors, lessons: lessonsOf() }
    break
  }
  if (ciState(ci) !== 'running') break
}
if (skipped) await err('executor-mechanics', 'wave', 'ci', 'пауза CI не исполнена в ' + skipped + ' чтениях из ' + CI_READS + ' (slept < ' + (CI_PAUSE_S - CI_SLEPT_SLACK) + ')')
// «Идёт» и после ожидания — СОСТОЯНИЕ, а не провал: волна не влита и не сломана,
// повтор шаблона продолжит с той же головы (state running отличим от failed).
const ciHead = sha40(ci && ci.head)
if (ciState(ci) === 'running' && ciHead === asm.head) return { ok: false, state: 'running', stage: 'CI идёт на ' + asm.head.slice(0, 12) + ' (ci-read код 3) — ожидание исчерпано, провала нет' + (skipped ? '; чтений с неисполненной паузой ' + skipped + ' — отвергнуты' : ''), pauseSkipped: skipped, pr: asm.pr, head: asm.head, reasons: ci.reasons || [], errors, lessons: lessonsOf() }
if (ciState(ci) === 'stale') return { ok: false, state: 'failed', stage: 'CI: база устарела (ci-read код 4) — влить свежую ' + (A.epic || A.base) + ' в ветку волны и читать заново', pr: asm.pr, head: asm.head, reasons: ci.reasons || [], errors, lessons: lessonsOf() }
if (ciState(ci) === 'red') M.ciRed++
if (!(ciState(ci) === 'green' || (readied && ciState(ci) === 'targeted-green')) || ciHead !== asm.head) return { ok: false, state: 'failed', stage: 'CI ' + ciState(ci) + ' (ci-read код ' + (ci ? ci.code : 'нет ответа') + ')' + (ciState(ci) === 'green' ? ' на другой голове ' + (ciHead || '?').slice(0, 12) : ''), reasons: ci ? ci.reasons || [] : [], ...redOf(ci), errors, lessons: lessonsOf() }

// ── Посадка ─────────────────────────────────────────────────────────────
// Факты собираются (CI на голове, ревью уровня на головах, коды предпроверки);
// решение «вливать» — ПРАВИЛО ВЛИВАНИЯ ниже; landing-reviewer — за недостающим
// фактом: публичный текст полосы либо голова PR сдвинута не только вливанием базы.
phase('Посадка')
// Вердикты ролей полос судятся на голове ПОЛОСЫ, сведённой в сборку (sha
// вердикта = голова, отданная сборке); на голове PR — вердикты волны: их и
// судит landing-precheck (REVIEW-STALE). Подменять sha вердикта нельзя.
for (const d of Object.values(done)) {
  const stale = (d.reviews || []).filter(r => r.sha !== d.head)
  if (stale.length) return { ok: false, stage: 'вердикт роли не на сведённой голове полосы ' + d.key, stale, errors, lessons: lessonsOf() }
}
const reviews = waveReviews
// Тема вливания (ws#1029): `#<эпик> merge #<PR>: …`; база не номер (main) — `#<волна> merge #<PR>: …`.
// Без --subject хостинг берёт заголовок PR, и правило ветки краснит запрос эпика.
const mergeTitle = '#' + (/^[0-9]+$/.test(String(A.epic || A.base || '')) ? String(A.epic || A.base) : N) + ' merge #' + asm.pr + ': волна ' + N
// ПРАВИЛО ВЛИВАНИЯ — код демона (ws#1147, ws#1152; новый флоу владельца 2026-10-17, части 1–2):
// `autoland.sh start` отсоединяет «ci-read 0 → merge-readiness 0 → landing-precheck 0 →
// gh pr merge --merge --match-head-commit» и снятие ветки и СРАЗУ печатает pid, журнал,
// .state; исход — ОДИН шаг `status`. Шаблон CI не ждёт и гейтов ради вливания не гонит.
const landRule = 'ПРАВИЛО ВЛИВАНИЯ диспетчера: PR #' + asm.pr + ' на голове ' + asm.head + ' вливает ТОЛЬКО демон scripts/autoland/autoland.sh (ws#1147): он ждёт CI (ci-read.sh код 0 на этой голове), гонит merge-readiness.sh и landing-precheck.sh и вливает коммитом слияния; ради вливания нельзя ждать CI, нельзя читать ci-read, нельзя гнать три гейта'
const AUTOLAND = ROOT + '/scripts/autoland/autoland.sh'
const AL_STATE = ROOT + '/tmp/autoland/' + String(A.repo || '?').replace('/', '__') + '__' + asm.pr + '__' + asm.head.slice(0, 12) + '.state'
// Перепись гейтов посадки разом (ws#1071, ai-tooling.md#at-red-ci-one-round): ДО первой починки
// и первого круга схождения все гейты — одним шагом, одной таблицей; находка по одной за круг —
// нарушение. Шаг ничего не чинит; итог несёт таблицу на любом исходе посадки.
const GATES = ['landing-precheck.sh (рецепт «ЗАПУСК»)', 'merge-readiness.sh', 'ci-read.sh (рецепт «ЗАПУСК», без ожидания)', 'пробное схождение и applicability.py обоих пакетов', 'cascade-census.sh --proof по каждой задаче', 'branch-audit.sh']
// Наборы воркспейса по стволам продуктов — на БУДУЩЕМ состоянии (ws#1078, L2: foundation-candidates
// покраснел после вливания kaname#714): ствол продукта PR = голова посадки.
const PROD = (A.repo || '').split('/').pop()
if (['kacho', 'kaname', 'corelib'].includes(PROD)) GATES.push('`bash ' + WS + '/scripts/trunk-future.sh ' + PROD + '=<голова PR>` (наборы по стволам продуктов на будущем состоянии)')
const GATES_FILE = R + '/gates-census.md'
const gates = await agent(C + '\n\nРежим «Перепись гейтов» посадки PR #' + asm.pr + ' (ai-tooling.md#at-red-ci-one-round): сперва ОДНО чтение `gh api rate_limit` — остаток core либо graphql < 300 — code 2, reasons [\'RATE-LIMIT\'], out «лимит, сброс в HH:MM» (местное время), гейты не гнать; иначе ДО первой починки прогони КАЖДЫЙ гейт по разу, ничего не чини: ' + GATES.join('; ') + '. landing-precheck — Выполни рецепт «ЗАПУСК» шапки landing-precheck.sh (вырезается по меткам из origin/main; каталог scripts/ целиком из origin/main; сбой подготовки — код 2), предварительно записав ' + D + '/reviews.json = ' + JSON.stringify(reviews) + ': `' + recipeRun('landing-precheck.sh', (A.repo || '?') + ' ' + asm.pr + (reviews.length ? ' --reviews ' + D + '/reviews.json' : '') + ' --stand-report ' + STAND + ' --stand-expect ' + STAND_EXP, D + '/landing-precheck-1.md') + '`. Перепись — не основание вливать: вливает только демон. Таблица — ' + GATES_FILE + ', строка на гейт «гейт · код · причина · число · корень · кто снимает». Верни code (0 — все гейты 0; 1 — есть красный; 2 — гейт не исполнился), out (таблица), reasons (коды причин ВСЕХ гейтов разом), head.', { ...MECH, label: 'mech:gates', phase: 'Посадка', schema: S_MECH })
const gatesOf = () => ({ gates: { file: GATES_FILE, code: gates ? gates.code : null, reasons: gates ? gates.reasons || [] : [] } })
if (steps.has('landing-reviewer')) {
  const gap = order.filter(k => (lanes.find(l => l.key === k) || {}).publicText === true).map(k => 'публичный текст полосы ' + k)
  if (gap.length) {
    const lr = await agent(C + '\n\nДо посадки, за недостающим фактом (' + gap.join('; ') + '): PR #' + asm.pr + ' @' + asm.head + ' → ' + (A.epic || A.base) + '. Вердикт — об этом PR. Запись — ' + D + '/landing-review.md. Верни verdict, sha, blocking, report.', { agentType: 'landing-reviewer', label: 'review-landing', phase: 'Посадка', schema: S_REV })
    if (!lr || lr.verdict !== 'accept' || lr.sha !== asm.head) return { ok: false, stage: 'landing-reviewer — ' + (lr && lr.verdict === 'accept' ? 'вердикт о другой sha' : 'возврат'), blocking: lr ? lr.blocking : [], remainder, errors, lessons: lessonsOf() }
  }
}
const alStart = await agent(C + '\n\nРежим autoland start: PR #' + asm.pr + ' (' + (A.repo || '?') + ') → ' + (A.epic || A.base) + ', голова ' + asm.head + '. ' + landRule + '. 1) Тело PR — заново генератором (ws#1146), руками не пишется: `RITUAL_REPO_DIR=' + D + '/assemble bash ' + WS + '/scripts/pr-body.sh ' + (A.repo || '?') + ' origin/' + (A.epic || A.base || '?') + ' ' + asm.head + ' > ' + R + '/pr-body-land.md && gh pr edit ' + asm.pr + ' -R ' + (A.repo || '?') + ' --body-file ' + R + '/pr-body-land.md` (код не 0 — code 2, демон не запускать). 2) ОДНОЙ командой `bash ' + AUTOLAND + ' start --repo ' + (A.repo || '?') + ' --pr ' + asm.pr + ' --head ' + asm.head + ' --subject "' + mergeTitle + '"' + (reviews.length ? ' --reviews ' + D + '/reviews.json' : '') + ' --stand-report ' + STAND + ' --stand-expect ' + STAND_EXP + '` — он сразу печатает pid, журнал и state и возвращается; не нужно ждать его. code — код start: 0 демон запущен · 3 PR уже ведёт демон · 2 довод не тот. Верни code, out (строки pid, журнал, state дословно), reasons [], head (' + asm.head + ').', { ...MECH, label: 'mech:autoland', phase: 'Посадка', schema: S_MECH })
if (!alStart || ![0, 3].includes(alStart.code)) return { ok: false, state: 'failed', stage: 'autoland start: демон не запущен (код ' + (alStart ? alStart.code : 'нет ответа') + ')' + (alStart && alStart.out ? ': ' + alStart.out : ''), pr: asm.pr, head: asm.head, ...gatesOf(), remainder, errors, lessons: lessonsOf() }
// ОДИН шаг status; попытка (args.rerun) — в задании: возобновление читает исход вживую, а не из кэша.
const alStatus = await agent(C + '\n\nРежим autoland status: PR #' + asm.pr + ' (' + (A.repo || '?') + '), демон вливания запущен. ОДНОЙ командой `bash ' + AUTOLAND + ' status ' + AL_STATE + '`; code — её код: 0 merged · 1 red · 2 void или демон умер · 3 идёт · 4 stale-base · 5 head-moved · 6 timeout. Исход не толкуй, не жди, демон не перезапускай. Верни code, out (первая строка .state ДОСЛОВНО), reasons (коды из строк REASON в out), head (sha коммита слияния при 0, иначе ' + asm.head + '). Попытка ' + (A.rerun || 0) + '.', { ...MECH, label: 'mech:autoland:status', phase: 'Посадка', schema: S_MECH })
const alOut = String((alStatus && alStatus.out) || '')
if (alStatus && alStatus.code === 3) return { ok: false, state: 'running', stage: 'вливание идёт: демон autoland ведёт PR #' + asm.pr + ' (status код 3) — провала нет; исход — возобновлением шаблона с новым args.rerun', autoland: AL_STATE, pr: asm.pr, head: asm.head, ...gatesOf(), errors, lessons: lessonsOf() }
const alMerge = alStatus && alStatus.code === 0 ? sha40((alOut.match(/^merged ([0-9a-f]{40})/) || [])[1]) : ''
if (!alMerge) {
  const ciRedGate = /^red ci-read /.test(alOut)
  if (ciRedGate) M.ciRed++
  const AL_STAGE = { 0: 'merged без sha коммита слияния — не-выполнилось', 1: 'красное', 2: 'не выполнилось', 4: 'база устарела — влить свежую ' + (A.epic || A.base) + ' в ветку волны и запустить демон заново', 5: 'голова сдвинулась', 6: 'предел ожидания исчерпан' }
  return { ok: false, state: alStatus && alStatus.code === 2 ? 'not-run' : 'failed', stage: 'autoland ' + (alStatus ? (AL_STAGE[alStatus.code] || 'код ' + alStatus.code) : 'нет ответа') + ': ' + alOut, autoland: AL_STATE, pr: asm.pr, head: asm.head, reasons: alStatus ? alStatus.reasons || [] : [], ...gatesOf(), remainder, ...(ciRedGate ? { redRound: RED_ROUND } : {}), errors, lessons: lessonsOf() }
}
// Влито демоном (ветку PR он снял): каскад — шагом git-operator.
const merged = await agent(C + '\n\nРежим каскад: PR #' + asm.pr + ' (' + (A.repo || '?') + ') влит демоном autoland коммитом слияния ' + alMerge + ' (' + AL_STATE + '). ФАКТ: `gh pr view ' + asm.pr + ' -R ' + (A.repo || '?') + ' --json state,mergeCommit` — state MERGED, mergeCommit ' + alMerge + '. ' + (stacks.length ? 'Сними временные сводки deps ' + stacks.join(', ') + ' коммитным предикатом (git-operator.md §«Вливание и снятие»). ' : '') + 'Каскад: закрой задачи влитых полос ' + order.join(', ') + ' со ссылкой на их DoD-proof' + (remainder.length ? '; остаток ' + remainder.map(x => x.key).join(', ') + ' не закрывать — его задачи в следующую волну' : '') + '; КРОМЕ держателей записей ведомостей (`git grep -n \'#<N>\'` задачи по ведомостям производителя и долгов: на задаче держится запись — не закрывать, назвать в out; ws#1053). Затем `bash ' + WS + '/scripts/wave-errors.sh rate ' + N + ' <часы волны: (сейчас − step-start ' + D + '/plan-1.json mtime)/3600>`. Верни code (0 — закрыто), out (state, mergeCommit, вывод rate), reasons [], head (mergeCommit).', { ...MECH, label: 'mech:cascade', phase: 'Посадка', schema: S_MECH })
// Профилактика (ws#1063): после КАЖДОЙ влитой волны в ветку эпика — пробное схождение на
// сведённом состоянии и одно чтение полного CI MR эпика в main (без ожидания: «идёт» —
// законный исход); красное читается в этой волне, а не впервые перед посадкой эпика.
const landedOk = !!(merged && merged.code === 0 && sha40(merged.head))
const epicMr = landedOk && !!A.epic && A.epic !== 'main'
const trialConv = epicMr ? await agent(C + '\n\nРежим пробное схождение после вливания волны ' + N + ' в ' + A.epic + ' @' + merged.head + ' (ai-tooling.md#at-red-ci-one-round): на сведённом состоянии ветки эпика пересчитай отпечатки пакета изменения и дай перечень недостающих записей ролей и событий (опубликованное событие без блока event записи — пункт; записи ролей снимаются по ходу, на сведённом). Ничего не правь. Запись — ' + R + '/trial-convergence.md. ' + due('review') + ' Верни verdict, sha, blocking (недостающее строками), report.', { agentType: 'convergence-reviewer', label: 'trial-convergence', phase: 'Посадка', schema: S_REV }) : null
const epicCi = epicMr ? await agent(C + '\n\nРежим CI MR эпика после волны ' + N + ': номер — `gh pr list -R ' + (A.repo || '?') + ' --head ' + A.epic + ' --base main --json number -q \'.[0].number\'`; прочти полный прогон MR эпика ОДИН раз командой (НОМЕР — этот номер) `' + recipeRun('ci-read.sh', (A.repo || '?') + ' НОМЕР', R + '/epic-ci.md') + '` — без ожидания: код 3 (идёт) — законный исход, верни его. Красное (код 1) — перепись корней с цитатами в тот же отчёт; порядок круга: ' + RED_ROUND + '. Верни code, out, reasons, head.', { ...MECH, agentType: 'ci-watcher', label: 'mech:ci-epic', phase: 'Посадка', schema: S_MECH }) : null
return { ok: landedOk, stacks, pr: asm.pr, head: asm.head, landed: order, remainder, merge: merged ? merged.head : '', rate: merged ? merged.out : '', lanes: done, trialConvergence: trialConv, epicCi: epicCi ? { ...epicCi, ...redOf(epicCi) } : null, ...gatesOf(), errors, lessons: lessonsOf() }
})()
// Метрики — в reports волны на ЛЮБОМ исходе (ws#1053): время, круги переделки,
// красные на сведённом (проба и CI), сверка с оценкой предполёта; токены — из итога Workflow.
await agent(C + '\n\nРежим метрики: запиши ' + METRICS + ' = ' + JSON.stringify({ wave: N, ok: !!res.ok, stage: res.stage || '', ...M }) + ' и допиши поля hours = (сейчас − mtime ' + D + '/plan-1.json)/3600 (старт→вливание, если ok), estimate — оценка из ' + PRE + ', tokens — из журнала Workflow, иначе null с причиной. Верни code, out, reasons [], head "".', { ...MECH, label: 'mech:metrics', phase: 'Посадка', schema: S_MECH })
return slim({ ...res, metrics: metricsOf() })
