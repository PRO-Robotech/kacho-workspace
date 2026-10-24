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
# ПУТЬ ВЫБРАН ПО ФАКТУ ПОЛИТИКИ КЛАСТЕРА (перепись 2026-10-24, ws#1385):
#   • допуск — PodSecurity по метке ns (t<N>-heavy-* с dind ставят enforce=privileged и без
#     этого профиля); ValidatingAdmissionPolicy кластера судят лишь ns платформы, а не ns
#     задач; политик Kyverno ноль.
#     Под privileged от имени job-controller (`--dry-run=server --as`) в ns t1385-* принят; тот
#     же в ns платформы — отказ политики допуска (контроль: проба умеет увидеть отказ);
#   • исполнение — одноразовые pod docker:29-dind в ns t1385-kindprobe-* (сняты, перепись ns
#     до/после — новых 0):
#       privileged + hostUsers: false, runc — `runc create failed: … unable to apply cgroup
#         configuration: mkdir /sys/fs/cgroup/docker: permission denied`: cgroup pod принадлежит
#         root узла (изнутри 65534), делегации cgroup в пространство пользователей нет;
#       privileged + hostUsers: false, crun --cgroup-manager=disabled — вложенный sysfs
#         монтируется, узел kind стартует, но его systemd без cgroup на запись не доходит до
#         цели: «could not find a log line that matches "Reached target .*Multi-User System.*|
#         detected cgroup v1"»;
#       privileged в пространстве пользователей узла — kind v0.33.0 (kindest/node v1.37.0)
#         создан, control-plane Ready за 18 с.
#   Путь (б) — kind заменить кластером в ns (vcluster, k3s в pod без привилегий) — упирается
#   в ту же делегацию cgroup (k3s/kubelet) либо выносит рабочую нагрузку пробы на узлы
#   общего кластера (vcluster синхронизирует pod в ns хозяина, а образы проб лежат в
#   реестре localhost:5001 внутри pod — узлам хозяина недоступны), и переписывает группы
#   registry-operator. Поэтому — путь (а): dind privileged в пространстве пользователей узла.
#
# ПОВЕРХНОСТЬ (ban18-q-security). privileged в пространстве пользователей узла — root узла
# для кода ревизии: побег из контейнера ему не нужен. Поэтому профиль уже прочих:
#   • только клоны внешних операторов (KIND_REPOS); kacho, kaname, corelib и воркспейс его
#     не получают — kind_pair_ok в pair_ok run.sh, и heavy-slot даёт класс kind лишь им;
#   • privileged — у ОДНОГО контейнера dind; run, fetch, tools, pgclient — без расширенных
#     прав: сверка фактического spec Job и pod (spec_drift) судит это как прежде;
#   • ns — свой t<N>-heavy-kind-*: NetworkPolicy та же (вход закрыт; управление кластера,
#     частные диапазоны и адреса узлов закрыты — предпосылка сети в pod та же), квота,
#     срок Job и ns, снятие trap'ом;
#   • исходники — bundle нашего клона, токенов и учётных данных в pod нет.
# Проверка пространства пользователей pod (USERNS_SH run.sh) этому профилю не ставится —
# его отличие в этом и есть; вместо неё pod печатает строку KIND_NOTE_SH.
#
# ИСХОДЫ. Отказ допуска — пробный pod шаблона Job от имени job-controller
# (`--dry-run=server --as=system:serviceaccount:kube-system:job-controller`: VAP кластера
# освобождают system:masters, и проба от своего имени прошла бы там, где Job откажут) — 77
# до создания Job. Kind в pod не исполним — вложенный privileged-контейнер не стартует
# (sysfs, cgroup) — строка «remote-heavy-kind: …» в termination-log run и 77. Образ пробы не
# скачан — «remote-heavy-prep: …», 69 (сеть, а не политика). Ни один из трёх не красный и
# не зелёный: вердикт даёт лишь исполненная команда (её код).

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
# Образ пробы исполнимости — через то же зеркало, что docker:dind (registry-mirror демона).
KIND_PROBE_IMAGE='mirror.gcr.io/library/alpine:3'
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
docker pull -q "$HEAVY_KIND_PROBE" > /dev/null 2>&1 || pf "образ пробы kind $HEAVY_KIND_PROBE не скачан в dind"
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
