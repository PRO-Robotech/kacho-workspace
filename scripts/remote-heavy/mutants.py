#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""mutants — набор `inject.sh` обязан КРАСНЕТЬ на однофактной порче каждого
решения среды и истории `run.sh` (ws#996).

Зачем: приёмка ws#996 (check-verifier, круг 1, ⛔ на 0d9c92582) нашла две порчи,
на которых `inject.sh` оставался зелёным: снятая проверка суммы архива node
(в перечне — M12: двойник curl ломал только сумму helm, а E1 искал
«SHASUMS256.txt» и «sha256sum -c» поиском по тексту) и префикс мажора node без
точки (M8: в индексе двойника не было выпуска, который префикс без точки
перепутал бы). Перечень ниже — по РЕШЕНИЮ установки, сверки среды, разбора пина
и доставки истории, у каждой порчи — проба `inject.sh`, которая её держит.
Полноты перечень не утверждает: он держит названные решения; новое решение среды
без строки здесь — та же дыра заново.

КАК: порча — точная замена фрагмента исходника копии `run.sh`. Копия кладётся
во временный каталог, `inject.sh` гонится против неё через `REMOTE_HEAVY_RUN`.
Порча УБИТА, если набор вышел кодом 1 и напечатал строку «ПРОВАЛ <проба>:» той
пробы, что названа у порчи (красное названо СВОЕЙ пробой, а не соседним случаем
и не обрывом набора).

ПРЕДПОСЫЛКИ (их отказ — код 1 харнесса, а не «порча выжила»):
  - контроль: набор против НЕиспорченной копии зелёный (код 0) — иначе
    красное порчи неотличимо от красного набора;
  - фрагмент порчи встречается в исходнике РОВНО один раз — иначе порча
    устарела вместе с правкой `run.sh` и молча перестала что-либо портить.

ИСХОДЫ: 0 — все порчи убиты; 1 — выжила хоть одна порча либо отказала
предпосылка; 2 — порч ноль (перечень пуст — проверено ничего).

Запуск: python3 scripts/remote-heavy/mutants.py [-j <параллельно>] [<id>…]
"""
import argparse
import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.join(HERE, "run.sh")
INJECT = os.path.join(HERE, "inject.sh")

# (id, проба, что портит, фрагмент, замена)
MUTANTS = [
    # ОБРАЗЫ TESTCONTAINERS (ws#1268): предел, застой и код вердикта загрузки.
    ("pull-no-limit", "PW3", "загрузка образа без предела: попытка не ограничена сроком шага",
     "ctx, cancel := context.WithDeadline(context.Background(), deadline)",
     "ctx, cancel := context.WithCancel(context.Background())"),
    ("pull-no-stall", "PW4", "застой загрузки не снимает попытку — повтор после зависания не наступает",
     "case <-t.C:\n\t\t\tcancel()",
     "case <-make(chan time.Time):\n\t\t\tcancel()"),
    ("pull-same-line-moves", "PWL1", "повтор той же строки прогресса (слой заперт, «locked for») считается движением",
     "if s.seen[p.ID] == k {",
     "if false && s.seen[p.ID] == k {"),
    ("pull-moved-by-neighbour", "PWI1", "движение судится по соседней строке, а не по слою: чередование двух стоящих слоёв — «движение»",
     "moved := st.moved(p, ln.b)",
     "moved := ln.b != st.last"),
    ("pull-unconditional", "PWC1", "прогрев безусловный: ci-local на медленном реестре получает 75",
     "PULL_IMG=0  # кому прогрев",
     "PULL_IMG=1  # кому прогрев"),
    ("pull-code-69", "PW9", "отказ загрузки образа читается как 69, а не 75",
     '''команда не запускалась (не выполнилось)"; exit 75''',
     '''команда не запускалась (не выполнилось)"; exit 69'''),
    ("M12", "E7-badsum-node", "сумма архива node не проверяется",
     r'''| grep "  $f\$" | sha256sum -c --quiet -''',
     r'''| grep "  $f\$" >/dev/null'''),
    ("M8", "E7-minor", "префикс мажора node без точки: пин 26.1 берёт v26.11.x",
     r'''--arg m "v$HEAVY_NODE."''',
     r'''--arg m "v$HEAVY_NODE"'''),
    ("helm-sum", "E7-badsum", "сумма архива helm не проверяется",
     r'''| cut -d" " -f1)  $f" | sha256sum -c --quiet -''',
     r'''| cut -d" " -f1)  $f" >/dev/null'''),
    ("node-dl-dir", "E7-node-only", "каталог загрузки node создаётся лишь веткой helm",
     r'''mkdir -p /work/dl /work/node''',
     r'''mkdir -p /work/node'''),
    ("node-oldest", "E7", "мажор разрешается в старейший выпуск, а не в последний",
     r'''[0] // empty''',
     r'''[-1] // empty'''),
    ("node-exact", "E7-exact", "полный пин N.N.N не находит свой выпуск",
     r''' or . == (\$m | rtrimstr(\".\"))''',
     r''''''),
    ("arch", "E7-arch", "чужая архитектура проходит как amd64",
     r'''*) return 1;; esac; }''',
     r'''*) echo "$1";; esac; }'''),
    ("tools-helm-prefix", "E2-helm-prefix", "сверка helm принимает v4.2.40 за v4.2.4",
     r'''"$HEAVY_HELM"|"$HEAVY_HELM+"*)''',
     r'''"$HEAVY_HELM"*)'''),
    ("tools-node-prefix", "E2-node-prefix", "сверка node принимает v260 за 26",
     r'''"v$HEAVY_NODE"|"v$HEAVY_NODE."*)''',
     r'''"v$HEAVY_NODE"*)'''),
    ("pin-own-step", "E1", "ключ пина берётся у любого шага с uses (version setup-kubectl)",
     r'''or not str(st.get("uses", "")).startswith(u):''',
     r'''or not str(st.get("uses", "")):'''),
    ("pin-bare", "E9", "шаг без ключа пина молча значит «пина нет»",
     r'''sys.exit(4 if bare else 0)''',
     r'''sys.exit(0)'''),
    ("pin-ambiguous", "E3", "два разных пина helm не отказ",
     r'''-eq 1 ] || { say "пин $3 неоднозначен''',
     r'''-ge 1 ] || { say "пин $3 неоднозначен'''),
    ("pin-lint", "E4", "профиль lint ставит среду",
     'if [ "$PROFILE" != lint ]; then\n    HELM_PIN=',
     'if true; then\n    HELM_PIN='),
    ("pin-helm-form", "E10b", "пин helm вне формы vX.Y.Z принимается",
     r'''"$HELM_PIN" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$''',
     r'''"$HELM_PIN" =~ .'''),
    ("pin-node-form", "E10", "пин node вне формы N[.N[.N]] принимается",
     r'''"$NODE_PIN" =~ ^[0-9]+(\.[0-9]+){0,2}$''',
     r'''"$NODE_PIN" =~ .'''),
    ("env-helm", "E1", "пин helm не доходит до окружения run",
     r'''{name: "HEAVY_HELM", value: $helm}, ''',
     r''''''),
    ("env-refusal", "E6", "отказ сверки среды выдаётся кодом команды, а не 69",
     r'''if [[ "$RUN_MSG" == "remote-heavy-prep: среда: "* ]]; then''',
     r'''if false; then'''),
    ("moddl-gone", "D1-exec", "шаг модулей не качает: исходника неимпортированного модуля в кэше нет",
     r'''( cd "${gm%/go.mod}" && go mod download )''',
     r'''( cd "${gm%/go.mod}" && true )'''),
    ("moddl-refusal", "D1b", "отказ загрузки модулей проглочен — команда судит неполный кэш",
     r'''|| pf "модули: go mod download не исполнился"''',
     r'''|| true'''),
    ("moddl-lint", "D1-lint", "шаг модулей пропущен профилем lint",
     'PREP="$PREP\n$MODDL_SH"',
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$MODDL_SH"'),
    # ws#1110: buf шагом bufbuild/buf-setup-action и helm образа ранера.
    ("buf-sum", "E7-buf-badsum", "сумма бинаря buf не проверяется",
     r'''sums | sha256sum -c --quiet --strict -''',
     r'''sums >/dev/null'''),
    ("buf-arch", "E7-buf-arch", "чужая архитектура buf проходит как x86_64",
     r'''*) pf "buf: архитектура $(uname -m) не поддержана";;''',
     r'''*) ba=x86_64;;'''),
    ("tools-buf-prefix", "E2-buf-prefix", "сверка buf принимает 1.72.01 за 1.72.0",
     r'''[ "$bv" = "$HEAVY_BUF" ]''',
     r'''[[ "$bv" == "$HEAVY_BUF"* ]]'''),
    ("pin-buf-form", "E11d", "пин buf вне формы [v]X.Y.Z принимается",
     r'''"$BUF_PIN" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$''',
     r'''"$BUF_PIN" =~ .'''),
    ("env-buf", "E11", "пин buf не доходит до окружения run",
     r'''{name: "HEAVY_BUF", value: $buf}, ''',
     r''''''),
    ("image-helm", "E11", "helm образа ранера не выводится при отсутствии setup-helm",
     r'''HELM_PIN="$(image_helm)"; [ "$?" -eq 2 ] && exit 69''',
     r'''true'''),
    ("image-helm-refusal", "E11c", "таблица образов не получена — молча «helm нет», а не 69",
     r'''|| { say "helm образа ранера: таблица образов actions/runner-images не получена — версию не выбрать"; return 2; }''',
     r'''|| return 1'''),
    ("hist-bundle", "H1", "bundle несёт лишь ствол, без веток origin и меток",
     r'''"$TMPREF" --remotes=origin --tags''',
     r'''"$TMPREF" ${MAIN_SHA:+refs/remotes/origin/main}'''),
    ("hist-fetch", "H1", "дерево pod берёт из bundle лишь ствол",
     r'''refs/remotes/*|refs/tags/*) git update-ref''',
     r'''refs/remotes/origin/main) git update-ref'''),
    # ws#1115: зависимости консоли в Job хука отправки kacho.
    ("npmci-gone", "NC2-console", "npm ci корня консоли снят — зависимости workspace не ставятся",
     r'''( cd "$nr/$nwd" && npm ci ) >&2''',
     r'''( cd "$nr/$nwd" && true ) >&2'''),
    ("npmci-standalone-gone", "NC2-console", "npm ci --prefix standalone-пакетов снят",
     r'''( cd "$nr/$nwd" && npm ci --prefix "$p" ) >&2''',
     r'''( cd "$nr/$nwd" && true ) >&2'''),
    ("npmci-signal-never", "NC2-console", "признак правки консоли не срабатывает никогда",
     r'''    *ui-future/*)''',
     r'''    *ui-future-never/*)'''),
    ("npmci-signal-always", "NC2-noconsole", "зависимости ставятся и без правки консоли",
     r'''  case "$nch" in''',
     r'''  case "ui-future/" in'''),
    ("npmci-refusal", "NC2-fail-e2e", "отказ npm ci standalone проглочен",
     r'''|| pf "консоль: npm ci --prefix $p не исполнился''',
     r'''|| true "консоль: npm ci --prefix $p не исполнился'''),
    ("npmci-ready-gone", "NC2-notready", "готовность пакетов после npm ci не сверяется",
     r'''|| pf "консоль: после npm ci пакет''',
     r'''|| true "консоль: после npm ci пакет'''),
    ("npmci-unwired", "NC1", "шаг консоли не включён в Job ci-local kacho",
     r'''[ "$PROFILE" = ci-local ] && [ "$REPO" = kacho ] && PREP=''',
     r'''false && PREP='''),
    ("npmci-env", "NC1", "вход pre-push не доходит до окружения run",
     r'''{name: "HEAVY_PUSH_INPUT", value: $pushin}, ''',
     r''''''),
    # ws#1115: корневая учётка git в Job ci-local.
    ("gitid-env", "GI1", "учётка не доходит до окружения run",
     r'''{name: "HEAVY_GIT_NAME", value: $gname}, {name: "HEAVY_GIT_EMAIL", value: $gemail}, ''',
     r''''''),
    ("gitid-unwired", "GI1", "шаг записи учётки не включён в Job ci-local",
     'PREP="$PREP\n$MODDL_SH"\n[ "$PROFILE" = ci-local ] && PREP=',
     'PREP="$PREP\n$MODDL_SH"\nfalse && PREP='),
    ("gitid-refusal", "GI2", "отправка без корневой учётки идёт в кластер",
     r'''            say "учётка git: у вызывающей копии нет корневой учётной записи''',
     r'''            true "учётка git: у вызывающей копии нет корневой учётной записи'''),
    # Ревью ws#1115 (check-verifier на 5312e9622): выжившие V4, V9, V11.
    ("V4-npmci-range", "NC2-update", "признак консоли берётся из запасного origin/main...HEAD, а не из диапазона хука",
     r'''  elif [ -n "$nrg" ]; then''',
     r'''  elif false; then'''),
    ("V9-gitid-credential", "GI1-env", "в окружение pod добавлен credential.helper",
     r'''{name: "HEAVY_GIT_EMAIL", value: $gemail}, ''',
     r'''{name: "HEAVY_GIT_EMAIL", value: $gemail}, {name: "GIT_CONFIG_COUNT", value: "1"}, {name: "GIT_CONFIG_KEY_0", value: "credential.helper"}, {name: "GIT_CONFIG_VALUE_0", value: "store"}, '''),
    ("V9b-gitid-smuggle", "GI1-decoy", "помощник учётных данных копии провезён в значении разрешённого имени",
     r'''    GIT_EMAIL="$(git -C "$SRC" config --global --includes --get user.email 2>/dev/null)" || GIT_EMAIL=""''',
     r'''    GIT_EMAIL="$(git -C "$SRC" config --global --includes --get user.email 2>/dev/null)$(git -C "$SRC" config --global --get credential.helper)" || GIT_EMAIL=""'''),
    ("V11-gitid-email-only", "GI2-name-only", "учётка без адреса принимается",
     r'''[ -z "$GIT_EMAIL" ] || ''',
     r''''''),
    ("gitid-write", "GI3", "шаг не пишет корневой gitconfig pod",
     r'''git config --global user.name "$HEAVY_GIT_NAME" && git config --global user.email "$HEAVY_GIT_EMAIL"''',
     r'''true'''),
    # ws#1136: журналы красных групп ci-local — дайджест и копия потоком лога.
    ("red-skip-is-red", "RG1", "копируется журнал всякой группы с «целиком:», и ПРОПУСК тоже",
     r'''"   | целиком: "*) [ "$red" = 1 ] && reds+=''',
     r'''"   | целиком: "*) reds+='''),
    ("red-digest-gone", "RG1", "дайджест строк отказа не печатается",
     r"""head -n "$lim" /work/heavy-red.dig | sed 's/^/   ! /'""",
     r''':'''),
    ("red-rc-lost", "RG1", "код контейнера — не код команды",
     r'''"$@" >&"$fd" 2>&1; rc=$?''',
     r'''"$@" >&"$fd" 2>&1; rc=0'''),
    ("red-tee-pipe", "RG8", "копия вывода — трубой: фоновый писатель держит шаг до срока Job",
     r'''  exec {fd}> >(tee /work/heavy-cmd.out); tp=$!
  "$@" >&"$fd" 2>&1; rc=$?''',
     r'''  tp=0
  "$@" 2>&1 | tee /work/heavy-cmd.out; rc="${PIPESTATUS[0]}"'''),
    ("red-unwired", "RG1", "команда идёт мимо шага красных групп",
     ' с\\" >&2\nheavy_cmd \\"\\$@\\""',
     ' с\\" >&2\nheavy_cmd() { \\"\\$@\\"; }\nheavy_cmd \\"\\$@\\""'),
    ("red-no-mask", "RG2", "копия журнала кладётся без маски адресов",
     r'''mask < "$RP/$n.raw" > "$f"''',
     r'''cat < "$RP/$n.raw" > "$f"'''),
    ("red-data-leaks", "RG2", "строки потока копий проходят в журнал",
     r'''                    total) printf '%s\n' "${w[*]}" > "$RP/total" ;;
                esac ;;''',
     r'''                    total) printf '%s\n' "${w[*]}" > "$RP/total" ;;
                esac; printf '%s\n' "$line" ;;'''),
    ("red-no-dedup", "RG3", "повтор строк на стыке не снимается номером",
     r'''sort -n -u -k1,1 "$RP/$n.data" | cut -d' ' -f2''',
     r'''sort -n -k1,1 "$RP/$n.data" | cut -d' ' -f2'''),
    ("red-no-count", "RG4", "неполная копия не ловится числом строк",
     r'''if [ "$got" != ok ]; then''',
     r'''if false; then'''),
    ("red-no-sum", "RG4b", "подменённая копия не ловится суммой",
     r'''[ "$(sha256sum < "$RP/$n.raw" | cut -d' ' -f1)" != "$sum" ]''',
     r'''false'''),
    ("red-no-fallback", "RG5", "итога в потоке нет — полный лог контейнера не разбирается",
     r'''kc -n "$NSNAME" logs "$POD" -c run 2>/dev/null | RED_QUIET=1 red_split | mask''',
     r''':'''),
    ("red-oom-unread", "K4b", "признак OOM шага не читается — 137 вместо 76",
     r'''[ "$RUN_REASON" = OOMKilled ] || [[ "$RUN_MSG" == remote-heavy-oom:* ]]''',
     r'''[ "$RUN_REASON" = OOMKilled ]'''),
    ("red-oom-unwritten", "RG7", "рост oom_kill не пишется в termination-log",
     r'''[ "$o1" -gt "$o0" ]; then''',
     r'''false; then'''),
    # приёмка ws#1136, круг 2: пять порч, каждая — со своим случаем.
    ("red-digest-first-only", "RG9", "дайджест берёт лишь первое совпадение",
     r'''grep -n -E -B "$ctx" -A "$ctx" -- "$pat" "$p" > /work/heavy-red.dig''',
     r'''grep -m 1 -n -E -B "$ctx" -A "$ctx" -- "$pat" "$p" > /work/heavy-red.dig'''),
    ("red-no-panic", "RG10", "образец дайджеста без panic:",
     r"""local pat=$'--- FAIL|^FAIL\t|panic:'""",
     r"""local pat=$'--- FAIL|^FAIL\t'"""),
    ("red-sum-whole-file", "RG11", "сумма в pod — от всего файла, а не от отправленного хвоста",
     r'''f="$(sha256sum < /work/heavy-red.raw | cut -d' ' -f1)"''',
     r'''f="$(sha256sum < "$p" | cut -d' ' -f1)"'''),
    ("red-mask-v4-only", "RG12", "маска копии — лишь IPv4",
     r'''mask < "$RP/$n.raw" > "$f"''',
     r'''sed -E "s#$MASK_V4#<адрес>#g" < "$RP/$n.raw" > "$f"'''),
    ("red-fallback-skips-begun", "RG13", "полный лог не разбирается, если начало копии уже пришло",
     r'''if [ ! -s "$RP/total" ] && [ -n "${POD:-}" ]; then''',
     r'''if [ ! -s "$RP/total" ] && ! ls "$RP"/*.begin >/dev/null 2>&1 && [ -n "${POD:-}" ]; then'''),
    ("red-zero-silent", "RG6", "красный код при нуле красных групп молчит",
     r'''[ "$rc" = 0 ] || say "красных групп ci-local''',
     r'''[ "$rc" != x ] || say "красных групп ci-local'''),
    # ws#1142: kubelet сворачивает $$ и раскрывает $(ИМЯ) в command, args и env.
    ("k8s-dollar", "KX1", "команда уходит в Job без экранирования $ — kubelet её искажает",
     r'''  | .spec.template.spec |= ((.initContainers, .containers) |= map(kesc_c))''',
     r''''''),
    # ws#1293 (ёмкость из кластера): число прогонов — раскладкой по узлам, константа — потолок.
    ("max-par-const-6", "CP5", "предел — константа 6, а не ёмкость кластера: на 5 узлах 7-й ждёт при месте",
     r'''MAX_PAR="${KACHO_REMOTE_HEAVY_MAX:-40}"''',
     r'''MAX_PAR="${KACHO_REMOTE_HEAVY_MAX:-6}"'''),
    ("cluster-sum", "CPB-out", "ёмкость — суммой по кластеру, без раскладки по узлам",
     r'''      | [$ns[] | select(.open)] as $open''',
     r'''      | [{fcpu: ([$ns[] | select(.open) | .fcpu] | add // 0), fmem: ([$ns[] | select(.open) | .fmem] | add // 0)}] as $open'''),
    ("pending-ignored", "CPB-out", "идущий pod без узла места не держит",
     r'''[$alive[] | select(.spec.nodeName | not) | select(.metadata.namespace | IN($busy[])) | {c: eff("cpu"), m: eff("memory")}]''',
     r'''[]'''),
    ("nopod-ignored", "CPN", "идущее ns без pod места не держит",
     r'''+ [$busy[] | select(. as $x | $alive | any(.metadata.namespace == $x) | not) | {c: $cpu, m: $mem}]''',
     r'''+ []'''),
    ("race-cap-only", "CPR", "гонка решается лишь потолком: младший остаётся при месте лишь под старшего",
     r'''placement "$NEED_CPU" "$NEED_MIB" "$(head -n "$(( pos - 1 ))" <<< "$busy")"; prc=$?''',
     r'''prc=0'''),
    # ws#1195 (4–5 окон): запрос по замеру профиля и репозитория, без запаса узла сверх него.
    ("const-7-12", "QW-3", "запрос pod — константа 7 CPU / 12 ГиБ, а не по замеру",
     r'''    NEED_CPU="$podc"
    NEED_MIB=$(( (p90 * PEAK_MARGIN_PCT + 25599) / 25600 )); NEED_MIB=$(( NEED_MIB * 256 ))''',
     r'''    NEED_CPU=7000
    NEED_MIB=12288'''),
    ("headroom-back", "QW-2", "запас 20 % allocatable сверх запроса вернулся",
     r'''(if $cpu > 0 then (.fcpu / $cpu | floor) else 1e9 end), (if $mem > 0 then (.fmem / $mem | floor) else 1e9 end)''',
     r'''(if $cpu > 0 then ((.fcpu - .acpu * 20 / 100) / $cpu | floor) else 1e9 end), (if $mem > 0 then ((.fmem - .amem * 20 / 100) / $mem | floor) else 1e9 end)'''),
    ("place-off-by-one", "QB-cpu-out", "место судится строго больше запроса — граница сдвинута",
     r'''(if $cpu > 0 then (.fcpu / $cpu | floor) else 1e9 end), (if $mem > 0 then (.fmem / $mem | floor) else 1e9 end)''',
     r'''(if $cpu > 0 then ((.fcpu + 1) / $cpu | floor) else 1e9 end), (if $mem > 0 then ((.fmem + 1) / $mem | floor) else 1e9 end)'''),
    ("repo-ignored", "QR-repo", "строка PEAKS выбирается без репозитория",
     r'''      $1 == p && $2 == r && $3 + 0 >= m { own = $0 }''',
     r'''      $1 == p && $2 == "*" && $3 + 0 >= m { own = $0 }'''),
    ("min-n-ignored", "QR-ci-corelib", "строка репозитория судит и при прогонах меньше PEAK_MIN_N",
     r'''$3 + 0 >= m { own = $0 }''',
     r'''$3 + 0 >= 0 { own = $0 }'''),
    ("margin-off", "QR-ci-kacho", "запас 1,2 к p90 пика снят",
     r'''PEAK_MARGIN_PCT=120''',
     r'''PEAK_MARGIN_PCT=100'''),
    ("no-repo-min", "QR-ci-any", "без --repo берётся не наибольший запрос профиля",
     r'''[ "$NEED_MIB" -gt "$best" ] && { best="$NEED_MIB"; bestr="$r"; }''',
     r'''bestr=kaname'''),
    # приёмка ws#1195, круг 1 (D1, D3, E1, E2): учёт dind и pgclient при посадке,
    # предел run по наибольшему пику, пустой PEAKS.
    ("place-run-req", "QB-dind-run-mem-out", "посадка в прогоне по запросу run, без dind и pgclient",
     r'''МиБ — $SIZE_WHY"
placement "$NEED_CPU" "$NEED_MIB" "$busy"; prc=$?''',
     r'''МиБ — $SIZE_WHY"
placement "$RUN_CPU_REQ" "$RUN_MEM_REQ" "$busy"; prc=$?'''),
    ("avail-run-req", "QB-dind-mem-out", "--available судит место по запросу run, без dind и pgclient",
     r'''need="$NEED_CPU $NEED_MIB"; avw=''',
     r'''need="$RUN_CPU_REQ $RUN_MEM_REQ"; avw='''),
    ("lim-is-req", "QL-go-race-kacho", "предел памяти run равен запросу",
     r'''    RUN_MEM_LIM="$(to_mib "$liml")"
    mx=$(( (mx * PEAK_MARGIN_PCT + 102399) / 102400 )); mx=$(( mx * 1024 ))
    [ "$mx" -gt "$RUN_MEM_LIM" ] && RUN_MEM_LIM="$mx"''',
     r'''    RUN_MEM_LIM="$RUN_MEM_REQ"'''),
    ("lim-no-raise", "QL-go-race-kacho", "предел run не поднимается по наибольшему пику",
     r'''    [ "$mx" -gt "$RUN_MEM_LIM" ] && RUN_MEM_LIM="$mx"''',
     r''''''),
    ("lim-no-margin", "QL-go-race-kacho", "подъём предела по наибольшему пику без запаса 1,2",
     r'''mx=$(( (mx * PEAK_MARGIN_PCT + 102399) / 102400 ))''',
     r'''mx=$(( (mx * 100 + 102399) / 102400 ))'''),
    ("empty-peaks-64", "QE-av", "пустой PEAKS в --available — «профиля нет» (64)",
     r'''sizing "$3" "${5:-}" || { say "запрос профиля $3 не выведен из PEAKS: строки профиля в таблице нет (не выполнилось)"; exit 69; }''',
     r'''sizing "$3" "${5:-}" || { say "профиля «$3» нет"; exit 64; }'''),
    ("pg-not-subtracted", "QR-job", "запрос pgclient сверх запроса pod",
     r'''    [ "$1" = lint ] || { RUN_CPU_REQ=$(( RUN_CPU_REQ - PG_REQ_M )); RUN_MEM_REQ=$(( RUN_MEM_REQ - PG_REQ_MIB )); }''',
     r''''''),
    ("sweep-off", "SW1-expired", "уборка просроченных тяжёлых ns не зовётся",
     r'''reap_local
sweep_heavy
''',
     r'''reap_local
'''),
    ("sweep-keep", "SW1-keep-t5-heavy-kept", "уборка снимает ns --keep",
     r'''(.old and (.keep | not))''',
     r'''(.old)'''),
    ("sweep-live", "SW1-keep-t5-heavy-live", "уборка снимает ns с живым Job",
     r'''select(.heavy and (.live | not) and (.exp''',
     r'''select(.heavy and (.exp'''),
    # приёмка ws#1195, круг 1: прежняя редакция — срок ns снимал и живой Job
    ("sweep-exp-live", "SW1-keep-t5-heavy-keep1", "истёкший срок снимает ns с живым Job",
     r'''select(.heavy and (.live | not) and (.exp or (.old and (.keep | not))))''',
     r'''select(.heavy and (.exp or (.old and (.live | not) and (.keep | not))))'''),
    ("sweep-exp-off", "SW1-keep1dead", "истёкший срок при завершённом Job не снимает",
     r'''(.exp or (.old and (.keep | not)))''',
     r'''((.old and (.keep | not)))'''),
    ("keep-life-short", "K5b", "срок ns при --keep — часы от создания, короче срока Job",
     r'''[ -n "$KEEP_H" ] && LIFE_S=$(( LIFE_S + KEEP_H * 3600 ))''',
     r'''[ -n "$KEEP_H" ] && LIFE_S=$(( KEEP_H * 3600 ))'''),
    ("sweep-foreign", "SW1-keep-t3258-w9", "уборка снимает чужой стенд задачи",
     r'''select(.heavy and (.live''',
     r'''select((.heavy or .exp) and (.live'''),
    ("sweep-age", "SW1-keep-t5-heavy-young", "уборка снимает молодое ns без Job",
     r'''SWEEP_AGE_S=7200''',
     r'''SWEEP_AGE_S=60'''),
    ("peak-silent", "PK1", "строка пика шага не печатается",
     r'''  echo "remote-heavy-peak: $pk $c1 $(( $(date +%s) - t0 ))"''',
     r'''  :'''),
    ("peak-no-journal", "PK2-journal", "пик не пишется в журнал слотов",
     r'''"$(date -Is)" "$1" "$REPO" "$2" "$mib" "$RUN_MEM_REQ" "$RUN_MEM_LIM" "$avg" "$RUN_CPU_REQ" "$sec" "$NSNAME" >> "$d/journal.log" 2>/dev/null''',
     r'''"$(date -Is)" "$1" "$REPO" "$2" "$mib" "$RUN_MEM_REQ" "$RUN_MEM_LIM" "$avg" "$RUN_CPU_REQ" "$sec" "$NSNAME" > /dev/null'''),
    ("evict-as-red", "EV1", "выселенный pod читается кодом контейнера",
     r'''if [[ "${POD_REASON:-}" == Evicted* ]]; then''',
     r'''if false; then'''),
    # Приёмка ws#1142: экранирование value env и init-контейнеров.
    ("k8s-env", "KX1-env", "value env контейнеров Job не экранируется",
     r'''  | (if .env then .env |= map(if has("value") then .value |= kesc else (.) end) else (.) end);''',
     r''';'''),
    ("k8s-init", "KX1-all", "экранируются лишь .containers, init-контейнеры — нет",
     r'''((.initContainers, .containers) |= map(kesc_c))''',
     r'''(.containers |= map(kesc_c))'''),

    # ws#1178: подготовка pod без apt — пакеты шагом с пином суммы и клиент postgres из образа.
    ("apt-back", "P1", "в подготовке снова apt вместо шага пакетов",
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$PKGS_SH"',
     '[ "$PROFILE" = lint ] || PREP="$PREP; apt-get -qq update && apt-get install -y jq python3-yaml postgresql-client"'),
    ("pkgs-lint", "P1l", "шаг пакетов ставится и профилю lint",
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$PKGS_SH"',
     'PREP="$PREP\n$PKGS_SH"'),
    ("pk-sum", "P2b", "сумма загруженного jq и PyYAML не проверяется",
     '-o "$2" "$1" && echo "$3  $2" | sha256sum -c --quiet -; }',
     '-o "$2" "$1"; }'),
    ("pk-swallow", "P2d", "отказ загрузки jq проглочен",
     '|| pf "jq 1.7.1 не поставлен"',
     '|| true'),
    ("pk-arch", "P2f", "чужая архитектура проходит как amd64",
     '*) pf "jq: архитектура $(uname -m) не поддержана" ;;',
     '*) ja=amd64 ;;'),
    ("pgw-exec", "P6d", "исполнение psql и pg_dump перед командой не проверяется",
     '"$x" --version >/dev/null 2>&1 || pf "$x из образа postgres не исполняется в образе golang: $("$x" --version 2>&1 | head -n 1)"',
     'true'),
    ("pk-always", "P2c", "jq качается и тогда, когда он уже есть",
     'if ! command -v jq >/dev/null 2>&1; then',
     'if true; then'),
    ("pg-libc", "P3", "в библиотеки клиента попадает семейство libc",
     "  | grep -v -E '/(libc|libm|libdl|libpthread|librt|libresolv|libutil|libnss_[a-z]+|ld-linux[^/]*)\\.so' \\\n",
     "  | cat \\\n"),
    ("pg-ld", "P3", "обёртка без LD_LIBRARY_PATH на вызов",
     'exec env LD_LIBRARY_PATH=/tools/pg/lib /tools/pg/bin/%s',
     'exec /tools/pg/bin/%s'),
    ("pg-libpq", "P3b", "отсутствие libpq в клиенте не замечено",
     '[ -f /tools/pg/lib/libpq.so.5 ] || pgf "libpq.so.5 среди библиотек клиента не найдена"',
     'true'),
    ("pg-major", "P3", "берётся младшая major образа postgres",
     'sort -V | tail -n 1)"',
     'sort -V | head -n 1)"'),
    ("pg-dropped", "P4", "init-контейнера pgclient в Job нет",
     '(if $pg == 1 then [',
     '(if $pg == 2 then ['),
    ("pg-lint", "P4l", "pgclient заводится и профилю lint",
     'PG=1; [ "$PROFILE" != lint ] || PG=0',
     'PG=1'),
    ("pgw-failed", "P6a", "отказ контейнера pgclient (файл failed) не читается",
     '[ ! -f /tools/pg/failed ] || pf "pgclient: $(head -n 1 /tools/pg/failed)"',
     'true'),
    ("pgw-deadline", "P6b", "срок ожидания клиента postgres не действует",
     '[ "$pgw" -lt "${HEAVY_PG_WAIT_S:-1500}" ] || pf "клиент postgres не появился за ${HEAVY_PG_WAIT_S:-1500} с: образ postgres не скачан либо контейнер pgclient не стартовал"',
     'true'),
    ("pgw-nowait", "P6c", "шаг не ждёт маркер, а проверяет клиент сразу",
     'while [ ! -f /tools/pg/ready ] && [ ! -f /tools/pg/failed ]; do',
     'while false; do'),
    ("pgw-lint", "P6l", "шаг ожидания клиента postgres стоит и у lint",
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$PGWAIT_SH"',
     'PREP="$PREP\n$PGWAIT_SH"'),
    ("pg-ready", "P3", "контейнер pgclient не отмечает готовность",
     'touch /tools/pg/ready\n',
     ''),
    ("pg-failed-file", "P3b", "отказ pgclient не записывается файлом failed",
     "printf '%s\\n' \"$1\" > /tools/pg/failed; ",
     ''),
    ("pg-knob", "P4k", "KACHO_REMOTE_HEAVY_PG_IMAGE не читается",
     'PG_IMAGE="${KACHO_REMOTE_HEAVY_PG_IMAGE:-$REGISTRY/postgres:17-trixie}"',
     'PG_IMAGE="$REGISTRY/postgres:17-trixie"'),
    ("pg-knob-form", "P4kb", "образ вне формы принимается",
     '[[ "$PG_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]*$ ]] ||',
     'true ||'),
    ("wait-start", "P7", "срок до начала команды снова 900 с — холодный pull его не укладывает",
     'WAIT_START_S=1800\n',
     'WAIT_START_S=900\n'),
    # Приёмка ws#1178: подмена должна краснеть ИМЕННО на сумме, пин остаётся в тексте.
    ("yaml-nosum-keeppin", "P2g", "сумма PyYAML не проверяется, пин стоит в тексте комментарием-аргументом",
     'pk_dl "https://files.pythonhosted.org/packages/source/p/pyyaml/pyyaml-6.0.2.tar.gz" /work/dl/pk/pyyaml.tgz d584d9ec91ad65861cc08d42e834324ef890a082e591037abe114850ff7bbc3e',
     'curl -fsSL -o /work/dl/pk/pyyaml.tgz "https://files.pythonhosted.org/packages/source/p/pyyaml/pyyaml-6.0.2.tar.gz" && : /work/dl/pk/pyyaml.tgz d584d9ec91ad65861cc08d42e834324ef890a082e591037abe114850ff7bbc3e'),
    ("jq-nosum-keeppin", "P2b", "сумма jq не проверяется, пины стоят в тексте",
     'pk_dl "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$ja" /work/dl/pk/jq "$js" \\',
     'curl -fsSL -o /work/dl/pk/jq "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-$ja" \\'),
    ("pgwait-integration-only", "P8-go-race", "ожидание клиента postgres стоит только у профиля integration",
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$PGWAIT_SH"',
     '[ "$PROFILE" = integration ] && PREP="$PREP\n$PGWAIT_SH"'),
    ("pkgs-integration-only", "P8-go-race", "шаг пакетов стоит только у профиля integration",
     '[ "$PROFILE" = lint ] || PREP="$PREP\n$PKGS_SH"',
     '[ "$PROFILE" = integration ] && PREP="$PREP\n$PKGS_SH"'),
    ("pg-integration-only", "P8-go-race", "контейнер pgclient заводится только профилю integration",
     'PG=1; [ "$PROFILE" != lint ] || PG=0',
     'PG=0; [ "$PROFILE" = integration ] && PG=1'),
    ("prep-timing", "P5", "времени подготовки до команды не печатается",
     'echo \\"remote-heavy: подготовка pod до команды — \\$(( \\$(date +%s) - PT0 )) с\\" >&2\n',
     ''),
    # ws#1210: ответ кластера и склеенная команда — словом argv jq (предел 128 КиБ).
    ("argv-busy", "AL1", "перепись идущих тяжёлых ns снова словом argv",
     '''--slurpfile NS <(printf '%s' "$nsj") --slurpfile JB <(printf '%s' "$jbj")''',
     '''--argjson NS "[$nsj]" --argjson JB "[$jbj]"'''),
    ("argv-deny", "AL3", "перепись служб ns kacho снова словом argv",
     '''--slurpfile SV <(kc get svc -n kacho -o json 2>/dev/null || echo '{"items":[]}')''',
     '''--argjson SV "[$(kc get svc -n kacho -o json 2>/dev/null || echo '{"items":[]}')]"'''),
    ("argv-cmd", "AL4", "склеенная команда снова словом argv",
     '''--slurpfile cmdv <(printf '%s' "$CMD_JSON")''',
     '''--argjson cmdv "[$CMD_JSON]"'''),
    ("defect-as-down", "AL5", "отказ разбора прочитанной переписи — снова 69 «недоступен»",
     '''2) defect "перепись идущих тяжёлых ns прочитана, а разбор её отказал${1:-}" ;;''',
     '''2) say "перепись идущих тяжёлых ns не прочитана${1:-}"; exit 69 ;;'''),
    # Строка на КАЖДУЮ ветку нового кода возврата, а не на класс: приёмка ws#1210
    # (check-verifier, круг 1) — guard2 и place2 выжили, 628/628.
    ("guard2", "AL5n", "страж узлов: отказ разбора прочитанной переписи — снова 1 «не доказан»",
     '''WHY="перепись узлов прочитана, а разбор её отказал — кластер не доказан"; return 2;''',
     '''WHY="перепись узлов прочитана, а разбор её отказал — кластер не доказан"; return 1;'''),
    ("place2", "AL5p", "размещение: отказ разбора прочитанной переписи — снова 1 «не прочитана»",
     '''PLACE_WHY="перепись узлов и pod прочитана, а разбор её отказал"; return 2;''',
     '''PLACE_WHY="перепись узлов и pod прочитана, а разбор её отказал"; return 1;'''),
    ("np", "AL6", "перепись политик ns kacho снова словом argv",
     '''--slurpfile NP <(kc get netpol -n kacho -o json 2>/dev/null || echo '{"items":[]}')''',
     '''--argjson NP "[$(kc get netpol -n kacho -o json 2>/dev/null || echo '{"items":[]}')]"'''),
    ("guard-exit", "AL5w", "страж фазы записи: дефект обёртки — снова 69 «не доказан»",
     '''guard_exit() { [ "$1" = 2 ] && exit 70; exit 69; }''',
     '''guard_exit() { exit 69; }'''),
    ("deny-silent", "AL7", "отказ разбора переписи ns kacho — снова пустая проба закрытости молча",
     '''"\\(.n).kacho.svc:\\(.p)"')" \\
    || defect "перепись служб и политик ns kacho прочитана, а разбор её отказал — проба закрытости ns kacho не выбрана, прогон без неё не идёт"''',
     '''"\\(.n).kacho.svc:\\(.p)"')"'''),
    # ws#1247: file для пробы хука отправки — сборка исходника выпуска фоном и сверка исполнением.
    ("file-unwired", "F0", "шаг сборки file не включён в Job ci-local",
     '''[ "$PROFILE" = ci-local ] && PREP="$PREP
$FILE_SH"''',
     '''[ "$PROFILE" = x ] && PREP="$PREP
$FILE_SH"'''),
    ("filewait-unwired", "F0", "ожидание сборки file не включено в Job ci-local",
     '''[ "$PROFILE" = ci-local ] && PREP="$PREP
$FILEWAIT_SH"''',
     '''[ "$PROFILE" = x ] && PREP="$PREP
$FILEWAIT_SH"'''),
    ("file-sum", "F2b", "сумма архива file не проверяется",
     '''src.tgz" | sha256sum -c --quiet - && { got="$u"; break; }''',
     '''src.tgz" >/dev/null && { got="$u"; break; }'''),
    ("file-fallback", "F2m", "мёртвый первый адрес архива file не выручается вторым",
     '''|| { echo "file: $u не скачан"; continue; }''',
     '''|| { echo "file: $u не скачан"; break; }'''),
    ("file-refusal", "F2c", "отказ сборки file проглочен — причина не названа",
     '''wait "$fpid" || pf "file 5.45 не поставлен''',
     '''wait "$fpid" || echo "file 5.45 не поставлен'''),
    ("file-elf", "F2x", "собранный file не судится исполнением на настоящем ELF",
     '''case "$fk" in ELF*) ;;''',
     '''case "$fk" in *) ;;'''),
]


def run_inject(run_path, tmp):
    env = dict(os.environ, REMOTE_HEAVY_RUN=run_path, TMPDIR=tmp)
    p = subprocess.run(["bash", INJECT], env=env, capture_output=True, text=True, timeout=1800)
    out = p.stdout + p.stderr
    fails = [ln for ln in out.splitlines() if ln.startswith("ПРОВАЛ ")]
    tail = out.strip().splitlines()[-1] if out.strip() else ""
    return p.returncode, fails, tail


def one(src, root, m):
    mid, probe, _, frag, repl = m
    d = tempfile.mkdtemp(prefix=f"mut-{mid}-", dir=root)
    path = os.path.join(d, "run.sh")
    with open(path, "w") as f:
        f.write(src.replace(frag, repl, 1))
    rc, fails, tail = run_inject(path, d)
    shutil.rmtree(d, ignore_errors=True)
    # Убита — красным СВОЕЙ пробы: красное соседнего случая порчу не убивает.
    by_probe = any(ln.startswith(f"ПРОВАЛ {probe}:") for ln in fails)
    killed = rc == 1 and by_probe
    return mid, killed, by_probe, rc, fails, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=4)
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()
    todo = [m for m in MUTANTS if not a.ids or m[0] in a.ids]
    if not todo:
        print("mutants: порч ноль — проверено ничего")
        return 2
    src = open(RUN).read()
    bad = [m[0] for m in todo if src.count(m[3]) != 1]
    if bad:
        print("mutants: ПРЕДПОСЫЛКА — фрагмент встречается не ровно один раз: " + ", ".join(bad))
        return 1
    root = tempfile.mkdtemp(prefix="remote-heavy-mutants-")
    try:
        rc, fails, tail = run_inject(RUN, root)
        print(f"контроль: код {rc} · {tail}")
        if rc != 0:
            print("mutants: ПРЕДПОСЫЛКА — набор красный без порчи")
            return 1
        survived = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.j) as ex:
            res = list(ex.map(lambda m: one(src, root, m), todo))
        for m, (mid, killed, by_probe, rc, fails, tail) in zip(todo, res):
            survived += not killed
            names = sorted({ln.split(":", 1)[0][len("ПРОВАЛ "):] for ln in fails})
            print(f"{'УБИТА ' if killed else 'ВЫЖИЛА'} {mid:18} держит {m[1]}"
                  f" · код {rc} · {tail} · красные: {', '.join(names) or '—'} · {m[2]}")
        print(f"remote-heavy mutants: порч {len(todo)} · убито {len(todo) - survived} · выжило {survived}")
        return 1 if survived else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
