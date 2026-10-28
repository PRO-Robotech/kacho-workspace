# syntax=docker/dockerfile:1
# Образ pod слота (scripts/remote-heavy/run.sh, ws#1482): golang той же версии, что у ревизии,
# и среда, которую подготовка pod прежде качала на КАЖДОМ запуске. Аудит загрузок 2026-10-28:
# 6 из 270 запусков сорвались кодом 69 на всплесках 19–22 pod (jq и yq с github.com, модули с
# proxy.golang.org). Решение диспетчера: инструменты — в образ, а не загрузкой при запуске.
# Шаги подготовки в run.sh ставят лишь отсутствующее либо не той версии — на этом образе они
# молчат; версия, не совпавшая с пином ревизии, по-прежнему ставится шагом (а не подменяется).
# Версии и суммы — те же, что у шагов run.sh (PKGS_SH, PYTEST_SH, FILE_SH, INSTALL_SH,
# WSTOOLS_SH): сверку держит inject.sh remote-heavy (IMG2). Личность образа — digest строки
# go-versions рядом (run.sh берёт лишь <repo>@sha256:…); тег сборки (.github/workflows/slot-image.yaml)
# — для людей.
ARG GO_VERSION
FROM golang:${GO_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Пакеты Debian (образ trixie): данные локалей — residue-census K6 ждёт ru_RU и en_US UTF-8
# (ранер их несёт); python3-venv — ensurepip (ghjob создаёт venv); jq 1.7.1 и PyYAML 6.0.2 —
# версии шага пакетов run.sh (там — те, что ставил apt trixie). Кэш apt снимается тем же слоем.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      locales python3-venv python3-yaml jq xz-utils \
 && sed -i -E 's/^# *(en_US\.UTF-8 UTF-8|ru_RU\.UTF-8 UTF-8)$/\1/' /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

# Загрузка с суммой: несошедшаяся сумма роняет сборку, а не кладёт чужой бинарь.
RUN mkdir -p /tmp/dl && cd /tmp/dl \
 && dl() { curl -fsSL --retry 4 --retry-all-errors --retry-delay 3 -o "$2" "$1" && echo "$3  $2" | sha256sum -c --quiet -; } \
 && dl https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_linux_amd64 yq b96de04645707e14a12f52c37e6266832e03c29e95b9b139cddcae7314466e69 \
 && install -m 0755 yq /usr/local/bin/yq \
 && dl https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz sc.txz 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 \
 && tar -xJf sc.txz && install -m 0755 shellcheck-v0.11.0/shellcheck /usr/local/bin/shellcheck \
 && dl https://github.com/bats-core/bats-core/archive/refs/tags/v1.10.0.tar.gz bats.tgz a1a9f7875aa4b6a9480ca384d5865f1ccf1b0b1faead6b47aa47d79709a5c5fd \
 && tar -xzf bats.tgz && bash bats-core-1.10.0/install.sh /usr/local > /dev/null \
 && dl https://nodejs.org/dist/v26.12.1/node-v26.12.1-linux-x64.tar.xz node.txz 6170b2d474e1c626f43cff3adc118df9fe3b573258a4fc3d850c8dbc6b079bbd \
 && tar -xJf node.txz -C /usr/local --strip-components=1 --exclude=node-v26.12.1-linux-x64/CHANGELOG.md \
      --exclude=node-v26.12.1-linux-x64/README.md --exclude=node-v26.12.1-linux-x64/LICENSE \
 && dl https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz helm.tgz c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3 \
 && tar -xzf helm.tgz && install -m 0755 linux-amd64/helm /usr/local/bin/helm \
 && dl https://github.com/bufbuild/buf/releases/download/v1.72.0/buf-Linux-x86_64 buf 8720830e26a733da55bb89bcd3cb44849c0965fc0c44fb5d691cccdc64dca5af \
 && install -m 0755 buf /usr/local/bin/buf \
 && for e in pytest-9.1.1-py3-none-any.whl:37a86b45efb9a47a61a36449063e8e18d0cab3161329fc099eb21783169c4f0c \
             pluggy-1.7.0-py3-none-any.whl:7dd7b0d8832ba3cb632c306926ded123429211b83641b35dc5c41ad2d34f9bec \
             iniconfig-2.3.1-py3-none-any.whl:9121e2c1fdb355232495be3194c8dfe87ccc2d5dee45947b78e68f499790d7a7 \
             packaging-26.3-py3-none-any.whl:d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c \
             pygments-2.21.0-py3-none-any.whl:2363c69b61c4a97c838da3b130dcd6468f4848992b21a82f2a63ec34377137d9; do \
      w="${e%%:*}"; n="${w%%-*}"; \
      dl "https://files.pythonhosted.org/packages/py3/${n:0:1}/$n/$w" "$w" "${e#*:}" \
        && python3 -m zipfile -e "$w" "$(python3 -c 'import site; print(site.getsitepackages()[0])')" || exit 1; \
    done \
 && dl https://astron.com/pub/file/file-5.45.tar.gz file.tgz fc97f51029bb0e2c9f4e3bffefdaf678f0e039ee872b9de5c002a6d09c784d82 \
 && mkdir file && tar -xzf file.tgz -C file --strip-components=1 && cd file \
 && ./configure --quiet --prefix=/usr/local --disable-shared --enable-static \
      --disable-zlib --disable-bzlib --disable-xzlib --disable-zstdlib --disable-lzlib --disable-libseccomp \
 && make -s -j4 && make -s install && cd / && rm -rf /tmp/dl

# Пользователь команды профиля ws (шаг wsuser run.sh: uid 1001, как у ранера конвейера).
RUN useradd -m -u 1001 -U -s /bin/bash runner

# Сверка образа ИСПОЛНЕНИЕМ — тем же, что судит шаг wscheck в pod: образ без любого из них не
# публикуется.
RUN set -e; for t in bash python3 git curl go node npm jq yq shellcheck bats helm buf file setpriv; do command -v "$t" > /dev/null; done \
 && env -i /usr/bin/python3 -c 'import yaml, pytest, ensurepip' \
 && locale -a | grep -qixE 'en_US\.utf-?8' && locale -a | grep -qixE 'ru_RU\.utf-?8' \
 && [ "$(shellcheck --version | sed -n 's/^version: //p')" = 0.11.0 ] \
 && yq --version | grep -q ' v4\.45\.4' && node --version | grep -qx 'v26\.12\.1' \
 && helm version --template '{{.Version}}' | grep -qx 'v4\.2\.4' && buf --version | grep -qx '1\.72\.0' \
 && jq --version | grep -qx 'jq-1\.7\.1' && bats --version | grep -qx 'Bats 1\.10\.0' \
 && file --version | grep -q '^file-5\.45'
