# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
# shellcheck shell=bash
# Переменные файла читает run.sh, подключающий его `source`, — отдельный разбор их не видит.
# shellcheck disable=SC2034
#
# kind.sh — профиль kind тяжёлого прогона (ws#1385). Сам не запускается: run.sh
# подключает его `source` после таблиц PROFILES и PEAKS (REMOTE_HEAVY_KIND_DIR — каталог
# kind.sh для копии run.sh вне каталога, как у inject.sh и mutants.py).
#
# ПРЕДМЕТ. Группы конвейера, поднимающие kind-кластер внутри прогона (registry-operator:
# kind-e2e, kaname — ci/gitlab/kaname.sh ставит kind со kaname, charts-admission), на
# внешнем кластере не исполнялись: dind прочих профилей — без privileged, в пространстве
# пользователей pod, и узел kind падал «OCI runtime create failed: mount `sysfs` to `sys`:
# Operation not permitted» (прогон registry-operator 85ae95b 2026-10-24) — с кодом группы 2,
# то есть КРАСНЫМ вместо «не выполнилось».
#
# ПУТЬ (опыт 2026-10-24, ws#1385; одноразовые pod docker:29-dind в своём ns, сняты):
#   • privileged + hostUsers: false, runc — `runc create failed: … unable to apply cgroup
#     configuration: mkdir /sys/fs/cgroup/docker: permission denied`: cgroup pod принадлежит
#     root узла (изнутри 65534), делегации cgroup в пространство пользователей нет;
#   • privileged + hostUsers: false, crun --cgroup-manager=disabled — вложенный sysfs
#     монтируется, узел kind стартует, но его systemd без cgroup на запись не доходит до
#     цели: «could not find a log line that matches "Reached target .*Multi-User System.*|
#     detected cgroup v1"»;
#   • privileged в пространстве пользователей узла — kind v0.33.0 (kindest/node v1.37.0)
#     создан, control-plane Ready за 18 с.
#   Путь (б) — kind заменить кластером в ns (vcluster, k3s в pod без привилегий) — упирается
#   в ту же делегацию cgroup (k3s/kubelet) либо выносит рабочую нагрузку пробы на узлы
#   общего кластера (образы проб лежат в реестре localhost:5001 внутри pod — узлам хозяина
#   недоступны) и переписывает группы. Поэтому — путь (а). Выделенных узлов (taint) и
#   изолированного RuntimeClass в кластере нет (перепись 2026-10-24: RuntimeClass 0, узлов с
#   taint 0) — уйти профилю от общих узлов некуда.
#
# ПОВЕРХНОСТЬ (ban18-q-security). privileged без своего пространства пользователей ≈ root
# на узле для кода ревизии: побег из контейнера ему не нужен. NetworkPolicy, квота и срок
# ограничивают pod, а не узел. Узел защищает лишь то, ЧЕЙ код сюда попадает:
#   • Ф1 — личность исходников (kind_identity): модуль go.mod ревизии и корневой коммит
#     истории клона --src — того, из которого собирается bundle, — сверяются с таблицей
#     KIND_OPERATORS для названного --repo; строка --repo и адрес origin сами по себе
#     ничего не доказывают. Kacho, kaname, corelib и воркспейс профиля не получают вовсе;
#   • Ф2 — ревизия достижима из ВЕТКИ (refs/heads/*) канонического удалённого репозитория
#     оператора (`git ls-remote`, затем `merge-base --is-ancestor`): локальный коммит,
#     refs/pull/* и форки не проходят; верхушка ветки обязана быть в клоне, иначе отказ с
#     подсказкой `git fetch`;
#   • privileged — у ОДНОГО контейнера dind; run, fetch, tools, pgclient — без расширенных
#     прав: сверка фактического spec Job и pod (spec_drift) судит это как прежде;
#   • исходники — bundle нашего клона, токенов и учётных данных в pod нет.
# Обе сверки — в run.sh, общем пути прямого вызова и вызова слотом, до любого обращения к
# кластеру; отказ — 64 с причиной, канонический не ответил — 69. Проверка пространства
# пользователей pod (USERNS_SH run.sh) этому профилю не ставится — его отличие в этом и
# есть; вместо неё pod печатает строку KIND_NOTE_SH.
#
# ИСХОДЫ. Отказ допуска — пробный pod шаблона Job от имени job-controller
# (`--dry-run=server --as=system:serviceaccount:kube-system:job-controller`: политики допуска
# вправе освобождать учётку запуска, и проба от своего имени прошла бы там, где Job откажут) —
# 77 до создания Job. Kind в pod не исполним — вложенный privileged-контейнер не стартует
# (sysfs, cgroup) — строка «remote-heavy-kind: …» в termination-log run и 77. Образ пробы не
# скачан — «remote-heavy-prep: …» с последними строками `docker pull` (сеть pod, зеркало,
# предел анонимных скачиваний docker.io — что именно, говорит сам демон), 69: kind этим не
# опровергнут и не подтверждён. Ни один из трёх не красный и не зелёный: вердикт даёт лишь
# исполненная команда (её код).

# Профиль: имя|cpu pod, m|cpu предел run|память предел run|ephemeral|dind|основание.
PROFILES="$PROFILES
kind|4000|12|16Gi|40Gi|1|группы с kind-кластером в Job (kind-e2e, kaname, charts-admission внешних операторов): dind privileged в пространстве пользователей узла (kind.sh)"
# Запрос — КОНСЕРВАТИВНО до замера: прогонов профиля kind в кластере 0; p90 и наибольший —
# строки «go-race|*» (95 прогонов), сборка и go test групп с kind — той же природы. Узел kind
# живёт в cgroup dind (его предел — KIND_DIND_RES), в run_peak не входит.
PEAKS="$PEAKS
kind|*|0|8265|13992"
# dind профиля kind: cpu запрос|cpu предел|память запрос|память предел. Запрос — тот же, что
# у DIND_RES (собственный расход демона); предел выше: в dind живут узел kind (до 2,9 ГиБ,
# строка stand heavy-slot.sh), реестр и сборка образов группы (docker build).
KIND_DIND_RES='100m|8|256Mi|12Gi'
KIND_REPOS='vault-operator kaname-iam-operator registry-operator'
# Личность оператора (Ф1, Ф2): --repo|модуль go.mod|корневой коммит истории|канонический
# удалённый репозиторий (ls-remote). Корень — `git rev-list --max-parents=0 --all` клона
# канонического (2026-10-24: у каждого ровно один). Маркеры — граница, по которой inject.sh
# подменяет таблицу фикстурой (клон пробы со своим корнем и каноническим — каталог).
# kind-operators-begin
KIND_OPERATORS='registry-operator|github.com/PRO-Robotech/registry-operator|39f27cd75c3c161675ced5c315e8e2f714f263fa|git@gitlab.beget.ru:cloud/k8s/controllers/registry-operator.git
vault-operator|github.com/PRO-Robotech/vault-operator|cc0bb2ad55b81f8e1a448b06c5baa77c719d9f01|https://github.com/PRO-Robotech/vault-operator.git
kaname-iam-operator|github.com/PRO-Robotech/kaname-iam-operator|4220c2646b618c327ed33d127348056dcfa49b43|https://github.com/PRO-Robotech/kaname-iam-operator.git'
# kind-operators-end
# Образ пробы исполнимости — по имени docker.io: демон тянет его через своё зеркало
# (--registry-mirror) с откатом на docker.io. Ссылка с явным хостом зеркала обходит и
# зеркало демона, и откат (замер check-verifier: `docker pull mirror.gcr.io/library/busybox:1`
# — «could not fetch content descriptor … not found», `docker pull busybox:1` — код 0).
KIND_PROBE_IMAGE='alpine:3'
KIND_JOB_SA='system:serviceaccount:kube-system:job-controller'

# kind_on — прогон идёт профилем kind (PROFILE run.sh).
kind_on() { [ "${PROFILE:-}" = kind ]; }

# kind_pair_ok <профиль> <репозиторий> — профиль kind лишь клонам KIND_REPOS (ПОВЕРХНОСТЬ).
kind_pair_ok() {
    [ "$1" = kind ] || return 0
    case " $KIND_REPOS " in *" $2 "*) return 0 ;; esac
    say "профиль kind — лишь для клонов внешних операторов ($KIND_REPOS): privileged в пространстве пользователей узла продуктам не даётся (kind.sh, ПОВЕРХНОСТЬ), получено «$2»"
    return 1
}

# kind_identity <репозиторий> <клон> <ревизия> — Ф1 и Ф2 (ПОВЕРХНОСТЬ). 0 — исходники того
# оператора и ревизия достижима из ветки канонического; 64 — нет (причина — строкой);
# 69 — канонический не ответил.
# Состояние клона и окружение вызова не должны подменять то, что судится (ревью ws#1385:
# insteadOf клона подменял канонический, replace --graft — историю, а bundle уносил
# настоящий коммит). Поэтому:
# kind_git <клон> <доводы git> — git по клону без подмен и без исполнения чужого: окружение
# пустое (ни GIT_* процесса, ни GIT_CONFIG_COUNT/KEY/VALUE), конфигурации учётки и системы нет,
# замены объектов выключены, хуки (reference-transaction и прочие) и fsmonitor клона не
# исполняются. Им идут и сверка личности, и временная ссылка, и сборка bundle (ревью ws#1385).
kind_git() {
    local s="$1"; shift
    env -i PATH="$PATH" LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 \
        git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$s" "$@"
}
# kind_ls_remote <адрес> — ветки канонического из нейтрального пустого каталога с пустым
# окружением git: ни insteadOf клона и учётки, ни GIT_CONFIG_*, ни include адрес не подменят.
# ssh берёт ключи и known_hosts из каталога учётки по passwd, а не из HOME.
kind_ls_remote() {
    local nb out rc
    nb="$(mktemp -d)" || return 1
    out="$(cd "$nb" && env -i PATH="$PATH" HOME="$nb" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
        ${SSH_AUTH_SOCK:+SSH_AUTH_SOCK="$SSH_AUTH_SOCK"} timeout 60 git ls-remote "$1" 'refs/heads/*' 2>/dev/null)"; rc=$?
    rm -rf -- "$nb"
    [ "$rc" = 0 ] || return "$rc"
    printf '%s\n' "$out"
}
# kind_history_forged <клон> — 0, если клон подменяет историю для сверки (info/grafts,
# refs/replace, shallow, objects/info/alternates — чужое хранилище объектов): сверка видела бы не то, что уходит в bundle; что именно — KIND_FORGED.
kind_history_forged() {
    local gd
    gd="$(kind_git "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { KIND_FORGED="каталог git клона не выведен"; return 0; }
    [ ! -e "$gd/info/grafts" ] || { KIND_FORGED="info/grafts"; return 0; }
    [ ! -s "$gd/objects/info/alternates" ] || { KIND_FORGED="objects/info/alternates"; return 0; }
    [ -z "$(kind_git "$1" for-each-ref refs/replace 2>/dev/null)" ] || { KIND_FORGED="refs/replace"; return 0; }
    [ "$(kind_git "$1" rev-parse --is-shallow-repository 2>/dev/null)" = false ] || { KIND_FORGED="shallow-клон"; return 0; }
    return 1
}
kind_identity() {
    local repo="$1" src="$2" sha="$3" row mod root roots canon have heads h ok=""
    row="$(awk -F'|' -v r="$repo" '$1 == r' <<< "$KIND_OPERATORS")"
    [ -n "$row" ] || { say "профиль kind: оператора «$repo» нет в таблице личности (KIND_OPERATORS) — Job не создаётся"; return 64; }
    IFS='|' read -r _ mod root canon <<< "$row"
    if kind_history_forged "$src"; then
        say "профиль kind: клон --src подменяет историю ($KIND_FORGED) — сверка судила бы не то, что уходит в bundle; нужен полный клон без замен и прививок (Ф2)"; return 64
    fi
    have="$(kind_git "$src" show "$sha:go.mod" 2>/dev/null | awk '$1 == "module" { print $2; exit }')"
    if [ "$have" != "$mod" ]; then
        say "профиль kind: клон --src не $repo — модуль go.mod ревизии «${have:-нет}», ждали «$mod» (Ф1: судятся исходники bundle, а не строка --repo)"; return 64
    fi
    roots="$(kind_git "$src" rev-list --max-parents=0 "$sha" 2>/dev/null)"
    if ! grep -qxF -- "$root" <<< "$roots"; then
        say "профиль kind: история ревизии не начинается корнем $repo (${root:0:12}) — клон --src не этот репозиторий (Ф1)"; return 64
    fi
    heads="$(kind_ls_remote "$canon")" \
        || { say "профиль kind: канонический репозиторий $repo не ответил (git ls-remote) — достижимость ревизии не проверена (не выполнилось)"; return 69; }
    while read -r h _; do
        [ -n "$h" ] || continue
        kind_git "$src" cat-file -e "$h^{commit}" 2>/dev/null || continue
        if kind_git "$src" merge-base --is-ancestor "$sha" "$h" 2>/dev/null; then ok=1; break; fi
    done <<< "$heads"
    if [ -z "$ok" ]; then
        say "профиль kind: ревизия ${sha:0:12} не достижима ни из одной ветки канонического $repo, чьи верхушки есть в клоне (веток $(grep -c . <<< "$heads")) — отправь ветку в канонический и обнови клон (git fetch); refs/pull и форки не в счёт (Ф2)"; return 64
    fi
    say "профиль kind: исходники — $repo (модуль и корень сверены), ревизия достижима из ветки канонического (Ф1, Ф2)"
    return 0
}

# dind профиля kind: среда исполнения по умолчанию (runc) и cgroup — узла, как у dind
# конвейера; crun без cgroup-менеджера здесь не нужен.
KIND_NOTE_SH='echo "remote-heavy: пространство пользователей — узла (профиль kind: dind privileged, kind.sh)" >&2'
KIND_DIND_SH="$KIND_NOTE_SH
exec dockerd --host=unix:///run/dind/docker.sock --registry-mirror=https://mirror.gcr.io"

# Проба исполнимости kind в pod — перед командой, в контейнере run (DOCKER_HOST — сокет
# dind). Вложенный privileged-контейнер монтирует sysfs и получает cgroup — ровно то, на чём
# падал узел kind. Маркеры — граница, по которой inject.sh исполняет шаг над двойником docker.
KIND_PREFLIGHT_SH="$(cat <<'KIND'
# kind-begin
kf() { echo "remote-heavy-kind: $1" | tee /dev/termination-log >&2; exit 125; }
po="$(docker pull -q "$HEAVY_KIND_PROBE" 2>&1)" || pf "образ пробы kind $HEAVY_KIND_PROBE не скачан в dind: $(printf '%s\n' "$po" | tail -n 2 | tr '\n' ' ')"
ko="$(docker run --rm --privileged "$HEAVY_KIND_PROBE" sh -c 'mount -t sysfs sysfs /mnt && mkdir /sys/fs/cgroup/kind-probe && rmdir /sys/fs/cgroup/kind-probe && echo ok' 2>&1)"; krc=$?
if [ "$krc" -ne 0 ] || [ "$(printf '%s\n' "$ko" | tail -n 1)" != ok ]; then
  kf "вложенный privileged-контейнер не исполним, узел kind не встанет (код $krc): $(printf '%s\n' "$ko" | tail -n 2 | tr '\n' ' ')"
fi
echo "remote-heavy: kind исполним — вложенный privileged-контейнер смонтировал sysfs и получил cgroup" >&2
# kind-end
KIND
)"

# kind_admission <job.json> — допуск pod шаблона Job, как его создаст job-controller.
# 0 — принят; 77 — отказ допуска (текст сервера — в строке); 69 — допуск не проверен.
kind_admission() {
    local doc out line
    doc="$BOX/kind-admission.json"
    jq '{apiVersion: "v1", kind: "Pod",
         metadata: {generateName: "run-", namespace: .metadata.namespace, labels: .spec.template.metadata.labels},
         spec: .spec.template.spec}' "$1" > "$doc" || { say "допуск pod профиля kind не проверен: шаблон Job не разобран (не выполнилось)"; return 69; }
    if out="$(kc create --dry-run=server --as="$KIND_JOB_SA" -f "$doc" -o name 2>&1)"; then
        say "допуск pod профиля kind: принят от имени job-controller (--dry-run=server)"; return 0
    fi
    # Строка сервера — первая «Error…», а не предупреждение PodSecurity (warn) перед ней.
    line="$(grep -m 1 '^Error' <<< "$out" || head -n 1 <<< "$out")"
    case "$out" in
        # Нет права выдать себя за job-controller — допуск не проверен, а не отказан.
        *"cannot impersonate"*) ;;
        *[Ff]orbidden*|*denied*|*"violates PodSecurity"*)
            KEEP_H=""
            say "допуск pod профиля kind отказан кластером: $(mask <<< "$line") — Job не создаётся, kind здесь не исполним (не выполнилось)"; return 77 ;;
    esac
    say "допуск pod профиля kind не проверен: $(mask <<< "$line") (не выполнилось)"; return 69
}
