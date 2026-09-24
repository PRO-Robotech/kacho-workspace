---
name: rule-git-issues
description: "Разметка задач и комментариев GitHub Issues и перевод этапности в трекер"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/git-issues.md`

# Разметка задач и комментариев GitHub Issues, перевод этапности

Трекер — **GitHub Issues того репозитория, где живёт предмет**; общее — в
`PRO-Robotech/kacho-workspace`, работа через `gh issue …`. Номера `KAC-<N>` в истории —
свидетельство о сделанном, а не указание на трекер; вперёд связывает только это правило.

## Git / коммиты

gi-conventional-commits · Conventional Commits: `feat:` `fix:` `chore:` `docs:` `test:` `ci:` `refactor:` · ЗАВЕСТИ gi-conventional-commits · red: тип не из набора либо тип отсутствует
gi-identity-owner-only · author И committer — ТОЛЬКО личная учётка владельца; `--author=`, `GIT_AUTHOR_*`/`GIT_COMMITTER_*`, `git -c user.*` и worktree-local override запрещены; коммить дефолтно, дрейф чинится `filter-branch --env-filter` по затронутому диапазону · `git log --format='%an %ae' <диапазон> | sort -u` — одна подпись владельца · red: коммит подписан бот-идентичностью либо «Kacho Workspace»
gi-no-attribution-trailers · подпись берёт git-config репозитория; `Co-Authored-By` и attribution-трейлеры НЕ добавлять — проект локальный · ЗАВЕСТИ gi-no-attribution-trailers · red: трейлер атрибуции в теле коммита
gi-no-direct-push-main · в `main` не пушить напрямую и не `--force` без явного разрешения владельца: работа идёт веткой с номером задачи через PR · защита ветви (`enforce_admins`, обязательные контексты) · red: коммит в `main`, которому не предъявить PR
gi-no-verify-by-request · `--no-verify` — только по явной просьбе владельца · ЗАВЕСТИ gi-no-verify-by-request · red: хук отправки обойдён, чтобы «пройти»

## Текст коммита: ёмко, информативно, не поэма

Читают люди — в списке из полусотни строк, в `git blame`, в обзоре PR: много букв означает
«не прочитают вовсе». Мера — вопрос: поймёт ли это через полгода тот, кто откроет `git log`
и не помнит контекста.

gi-subject-72 · заголовок до 72 символов, повелительно-описательно, ОДНО утверждение, без точки · ЗАВЕСТИ gi-commit-msg-hook · red: второе утверждение через тире или точку с запятой; точка в конце
gi-blank-line-required · пустая строка между заголовком и телом обязательна · ЗАВЕСТИ gi-commit-msg-hook · red: `git log --oneline` показывает склеенное с телом
gi-body-says-why · тело до 12 строк и говорит ПОЧЕМУ изменение верно; чинится дефект — чем он проявлялся · ЗАВЕСТИ gi-commit-msg-hook (длина) · red: пересказ диффа «добавил X, поправил Y»
gi-body-excludes · в тело не идут: ход работы (его место — задача), разбор дефекта по шагам (репозиторий публичный), число без предиката · `security-disclosure.md` §«Публичные артефакты» плюс признак восстановимости · red: «улучшено на 30%» без предиката; шаги воспроизведения дефекта
gi-closes-last-line · `Closes #<N>` — последней строкой · ЗАВЕСТИ gi-closes-last-line · red: номер задачи в середине абзаца
gi-two-subjects-two-commits · два предмета в одном коммите — это два коммита; заголовок, которому нужна точка с запятой, сообщает об этом сам · ЗАВЕСТИ gi-two-subjects-two-commits · red: один коммит о двух предметах
gi-commit-form-by-hook · форму сообщения (строки выше) судит хук `commit-msg`, а не ревью: рецензент формой круга не открывает · ЗАВЕСТИ gi-commit-msg-hook (воркспейс — хук #770 без длины; corelib#25, kaname#356; kacho — задачи нет) · red: форма коммита — замечание ревью; принят заголовок длиннее 72 знаков

## Волна: вливание сборкой (решение владельца 2026-09-24 «запиши в рулы новый подход»)

gi-wave-assemble-only · в ветку волны задачи вливай только сборкой: готовые (ревью ✅, прогоны PR зелёные на её голове, `testing-verdict.md#task-verdict-runs-on-head`) — разом, `git merge --no-ff` каждой, состав доказан до прогона; поштучное `gh pr merge` в волну и догон волны в ветку задачи отменены · журнал ветки `gh api 'repos/<o>/<r>/activity?ref=refs/heads/<волна>'`: сборка пришла одной записью `push`, чей `git log --first-parent --merges <before>..<after>` называет все задачи; записей `pr_merge` с 2026-09-24 ноль (`merge-base --is-ancestor` одинаков у обоих путей и сборку не отличает) · red: PR задачи влит в волну поштучно (`pr_merge` в журнале); задачи пришли в волну разными отправками; в ветке задачи слияние волны
gi-wave-one-run-one-push · после сборки: один прогон на сведённой голове и `wave-reviewer`, затем посадочный, затем одна отправка; повтор прогона — только после пересборки по возврату · ЗАВЕСТИ gi-wave-one-run-one-push · red: прогон после каждого вливания; отправка до ✅ посадочного
gi-pr-manual-dispatch · открыл PR, а триггера PR в базу нет (kacho#2793, corelib#31, kaname#394) — тем же заходом `gh workflow run <файл> --ref <ветка>` КАЖДОГО процесса с `pull_request` и `workflow_dispatch` (воркспейс — `ci.yaml`: у него только `workflow_dispatch`); свод без `workflow_dispatch` (kacho `required-verdict.yml`) не встаёт, вердикт — по процессам · `gh run list -R <репо> --commit <headSha> --json workflowName,status,conclusion` — у каждого процесса прогон на голове · red: PR без проверок ждёт триггера, которого нет; запущен не каждый процесс PR

## Трекер — GitHub Issues: когда заводится задача

gi-feature-issue-first · фича (ресурс, API, раздел UI, кросс-доменное поведение) → задача ПЕРВОЙ, ветка с её номером, PR `Closes #<N>`, ссылка на PR — комментарием в задаче · ЗАВЕСТИ gi-feature-issue-first · red: ветка или PR, которым не предъявить задачу
gi-batch-one-per-session · фиксы и мелкий UX — ОДНА batch-задача на сессию («<область> bugfix batch — YYYY-MM-DD») · ЗАВЕСТИ gi-batch-one-per-session · red: десять задач на одну сессию фиксов
gi-trivia-no-issue · опечатка, однострочник, docs — без задачи, достаточно коммита · ЗАВЕСТИ gi-trivia-no-issue · red: задача на однострочник
gi-retro-backfill · существенный кусок без задачи заводится ретроспективно; тривию не бэкфиллить · ЗАВЕСТИ gi-retro-backfill · red: в истории работа, которой нечего предъявить
gi-find-own-issue · находка по дороге заводится СВОЕЙ задачей, а не чинится в чужом PR · ЗАВЕСТИ gi-find-own-issue · red: PR несёт правку не своего предмета
gi-zero-findings-aloud · ноль соседних находок — законный ответ, но названный вслух: «смотрел, чисто» отличимо от «не смотрел» только сказанным · ЗАВЕСТИ gi-zero-findings-aloud · red: отчёт без находок и без названного осмотренного места

## Разметка тела задачи

gi-epic-label-and-list · крупное или многодоменное — эпик (метка `epic`): цель, решения, декомпозиция, порядок по ГРАФУ ЗАВИСИМОСТЕЙ, DoD; дочерние — списком задач `- [ ] #<N>` в теле · ЗАВЕСТИ gi-epic-label-and-list · red: эпик без дочерних; порядок взят по номеру вместо графа
gi-task-body-four · тело задачи несёт четыре вещи: что · DoD · затронутые каталоги · артефакт · ЗАВЕСТИ gi-task-body-four · red: задача без DoD либо без артефакта
gi-blocked-by-label · блокер — строкой `Blocked by #<N>` И меткой `blocked`: словами без метки его не видит соседняя сессия · ЗАВЕСТИ gi-blocked-by-label · red: блокер прозой, метки нет
gi-role-line · исполнитель — строкой `**Роль:** <agent>` в теле: поля исполнителя у задачи нет, назначение — assignee, если учётка есть · ЗАВЕСТИ gi-role-line · red: роль выводится из текста, а не названа

## Состояние — метками, снимается ТЕМ ЖЕ действием

gi-state-by-labels · состояние — метками (`status:in-progress`, `status:test`) плюс сам факт open/closed; своего поля состояния не изобретать · ЗАВЕСТИ gi-state-by-labels · red: состояние прозой в теле вместо метки
gi-label-same-action · метка описывает ТЕКУЩЕЕ состояние: закрыл — снял в том же заходе; сдал на проверку — ЗАМЕНИЛ одну на другую, а не добавил вторую · `gh issue list -R <репо> --state closed --label status:test --limit 100 --json number -q '.[].number'` и то же для `status:in-progress` — вывод обязан быть ПУСТ · red: закрытая задача с `status:test`
gi-open-label-needs-artifact · `status:test` на открытой законен ровно пока есть артефакт, ждущий ствола · ЗАВЕСТИ gi-open-label-needs-artifact · red: метка без артефакта — «кто-то что-то делал», то есть ничего
gi-stale-label-blocks-capture · перепись выше прогоняется при завершении накопительной линии: пережившая метка ЗАПРЕЩАЕТ брать задачу, которую никто не ведёт, и запрет невидим · ЗАВЕСТИ gi-stale-label-blocks-capture · red: свободная задача выглядит чужой работой

## Комментарий — предъявление, не пересказ

gi-close-with-artifacts · закрывать С АРТЕФАКТАМИ В КОММЕНТАРИИ: PR-URL, лог прогона, ссылки · ЗАВЕСТИ gi-close-with-artifacts · red: закрыто словом «сделано»
gi-pr-link-comment · ссылка на PR кладётся комментарием в задачу тем же заходом, которым PR открыт · ЗАВЕСТИ gi-pr-link-comment · red: PR есть, задача о нём не знает

## Перевод этапности в трекер

gi-phase-source-is-roadmap · этапность берётся из `docs/specs/04-roadmap-and-phasing.md`, не из трекера и не из памяти · ЗАВЕСТИ gi-phase-source-is-roadmap · red: порядок работ выведен из задач, дорожная карта его не знает
gi-subphase-acceptance-doc · под-фаза переводится в `docs/specs/sub-phase-<N>-<имя>-acceptance.md`; каждая строка Scope несёт сценарий · scripts/docs-gate/check-03-scope-row-scenario.py · red: строка Scope без сценария
gi-coding-after-approved · кодинг-задача открывается только после APPROVED приёмки под-фазы · `acceptance-reviewer`; scripts/docs-gate/check-01-acceptance-verdict.py · red: код пошёл раньше вердикта приёмки
gi-verdict-reproduces · вердикт приёмки обязан воспроизводиться по дереву, а не держаться записью · scripts/docs-gate/check-05-ledger-verdict-reproduces.py · red: ведомость утверждает вердикт, которого дерево не даёт
