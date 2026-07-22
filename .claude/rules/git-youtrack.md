# Git, документооборот (YouTrack KAC), баги

## Git / коммиты

- Conventional Commits (`feat:`/`fix:`/`chore:`/`docs:`/`test:`/`ci:`/`refactor:`).
- Подпись — git-config (`user.name`/`user.email` репо). **НЕ добавлять** `Co-Authored-By` или attribution-trailers (локальный проект).
- **Author И committer — ТОЛЬКО личная учётка владельца** (`pointpu@prorobotech.ru`). Ни субагент, ни оркестратор **НЕ переопределяют** git-identity: запрещены `--author=…`, `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env, `git -c user.*`, worktree-local `user.*`-override. Коммить дефолтно (config уже указывает на владельца). Дрейф на «Kacho Workspace»/бот-идентичность = ошибка, фиксится `filter-branch --env-filter` на затронутом диапазоне. Касается ВСЕХ репо (монорепо `project/kacho` и workspace).
- **Не пушить в `main` напрямую и не `--force`** (если владелец явно не разрешил) — работа через ветку = номер тикета → PR.
- `--no-verify` (скип pre-commit hooks) — только по явной просьбе.

## Когда заводить тикет (решается В НАЧАЛЕ запроса)

- **Фича** (новый ресурс/API/раздел UI/кросс-репо поведение) → тикет СНАЧАЛА, ветка `KAC-<N>` в каждом
  затронутом репо, PR'ы ссылаются (`Closes/relates KAC-N`), ссылка на PR — комментарием в тикет.
  ~3+ репо или крупно → **эпик** + Subtask'и + в текущий спринт.
- **Фиксы / мелкие UX** → ОДИН batch-тикет на сессию («<area> bugfix batch — YYYY-MM-DD»).
- **Тривия** (опечатка/однострочник/docs) → без тикета, достаточно коммита.
- Существенный кусок без тикета — завести ретроспективно (тривию не бэкфиллить).

## YouTrack KAC

Трекер — проект `KAC` на `https://prorobotech.youtrack.cloud/` (доска `agiles/183-12`).
MCP `mcp__youtrack__*` или REST `…/api/...` с perm-токеном.

- **Эпик** — `[EPIC]` в summary (нет поля Type) + Subtask-иерархия (link `subtask of KAC-<epic>`). Описан: цель, решения, декомпозиция, кросс-репо порядок, DoD.
- **Subtask** — описан (что/DoD/репо/артефакт) + блокеры в тексте. Каждый issue добавляется в текущий спринт (`Board kacho <sprint>`).
- **Роль исполнителя** — поле `агент` (= имя субагента) + строка `**Роль:** <agent>` в описании.
- **States**: `To do` → `In Progress` → `Test` → `Done`. При завершении — в `Done` + ВСЕ артефакты в комментарий (PR-URL, лог тестов, кросс-репо ссылки).
- **Gate**: кодинг таска (вне `kacho-vpc-implement`) — только после APPROVED acceptance-дока под-фазы (`acceptance-reviewer`).

## Continuous integration — фича→merge СРАЗУ, trunk ведётся к цели (ОСНОВНОЕ, non-negotiable)

**Каждая готовая фича/фикс мержится в интеграционный trunk НЕМЕДЛЕННО по green — не копится в
долгоживущей divergent-ветке.** Ветки — короткоживущие (idealно часы-день, не дни-недели); trunk
(`main`/`redesign/integration`) непрерывно ведётся к цели единым авторитетным состоянием. Причина
(инцидент 2026-07: 5 divergent-веток, `iam-acb` 6 дней → cherry-pick конфликтует, работа «на произвол»,
состояния разъехались): чем дольше ветка живёт в стороне, тем дороже merge (конфликты, drift, потеря
работы, дубли, регресс при слепом merge). Инварианты:

- **Feature→merge каждый green-chunk.** Готовый вертикальный срез (proto→код→тест green) → merge в trunk
  сразу, НЕ «накоплю ветку, потом влью». Крупная фича — серия мелких green-merge (expand-contract:
  каждая фаза green-committable-и-merge-able), не один гигантский divergent-branch.
- **Ни одна ветка НЕ остаётся на произвол.** Ветка либо (a) активно ведётся к merge (короткий цикл),
  либо (b) смёржена+удалена, либо (c) явно закрыта (`wontfix`+удалена). «Висящая» feature-ветка старше
  ~2 дней без merge-плана — долг: догнать trunk (rebase) и влить, ИЛИ закрыть. Регулярный branch-аудит
  (`git branch` vs trunk merge-base age) — часть завершения задачи.
- **Trunk — единственный авторитет.** Не держи параллельные линии работы в расходящихся ветках (feature
  vs CI-hardening vs fixture) — они разъезжаются. Всё сходится в один trunk частым merge; параллельные
  под-задачи rebase'ятся на свежий trunk перед продолжением.
- **Избегать сильных дрейфов by construction.** Перед новой правкой — синхронизируй локальное дерево с
  origin trunk (fetch+rebase/merge); worktree-агенты ветвятся от СВЕЖЕГО trunk ([[isolation-worktree-base-branch]]),
  не от устаревшей базы. Не начинай большую работу поверх устаревшего состояния.

## git-флоу под задачу

- `git checkout -b KAC-<N>` от `main` в каждом затронутом репо (порядок по build-графу).
- `git push -u origin KAC-<N>` → `gh pr create --title "[KAC-<N>] …" --body "… Closes KAC-<N>"` → ссылку комментарием в тикет.
- **Merge как только green** (не копить): маленькие частые PR > один большой divergent. После merge + `Done` —
  удалить ветку (`gh pr merge --delete-branch` или `git push origin --delete KAC-<N>` + `git branch -D`).
  Исключение: ветка нужна зависимой работе — и то rebase'ится на trunk регулярно, не дрейфует.
- KAC-trail в vault (`obsidian/kacho/KAC/KAC-<N>.md`) — обязателен (см. `vault.md`).

## Баги / tech-debt — GitHub Issues (не TODO.md)

- Баг/tech-debt/observability-gap → GitHub Issue в репо, где живёт (общий → `kacho-workspace`). `TODO.md` упразднён.
- Метки: `bug`/`tech-debt`/`enhancement`; `blocked` + `blocked:kacho-<svc>`; `epic`; `wontfix` (с обоснованием).
- Кросс-репо зависимость — `Blocked by PRO-Robotech/<repo>#<n>` в теле.
- Найдено в тестах → issue (`bug`/`tech-debt`); в кейсе — короткая аннотация `# verifies <…>`, не дублировать описание.
- By-design отклонение — не issue, а запись в `docs/architecture/` сервиса. Не путать с feature-acceptance-флоу (новая фича → APPROVED Given-When-Then).
