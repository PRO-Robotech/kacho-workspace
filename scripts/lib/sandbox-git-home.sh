#!/usr/bin/env bash
# Подпись песочницы пробы: свой HOME со своим `.gitconfig`, в котором та же
# корневая учётная запись, что у вызывающего. Source-only.
#
# ОСНОВАНИЕ. Правило подписи (`.claude/rules/git-issues.md`,
# gi-identity-owner-only) действует и на песочницы проб, в том числе на те, что
# на origin не попадают никогда, — решение диспетчера 2026-09-27 в ws#785.
# Подпись берётся только из корневого gitconfig; переопределение на команду, на
# репозиторий и окружением в пробах не используется. Держит это
# `scripts/tooling-gate/check-16-signature-from-root-gitconfig-only.sh`.
#
# ПОЧЕМУ HOME ПОДМЕНЯЕТСЯ В ВЫЗОВЕ, А НЕ НА ВСЮ ПРОБУ. Проба зовёт проверяемый
# гейт, а гейт — python3 с библиотеками из пользовательского каталога
# (`python3 -c 'import yaml; print(yaml.__file__)'` на машине владельца —
# `~/.local/...`). HOME песочницы на всю пробу увёл бы гейт в «не выполнилось»
# без единой строки о причине. Поэтому HOME песочницы получает только то, что
# пишет историю песочницы: `sandbox_git` и `sandbox_run`.
#
# ПРЕДПОСЫЛКА — корневая подпись у вызывающего есть. На ранере её заводит шаг
# конвейера (учётная запись того, кто запустил прогон). Нет её — код 2: у пробы
# нет предмета, и это не красное и не зелёное.
#
# Использование:
#   . "$WS/scripts/lib/sandbox-git-home.sh"
#   sandbox_git_home "$TMP/home" || exit 2
#   sandbox_git -C "$repo" commit -qm x
#   git() { sandbox_git "$@"; }     # весь посев пробы; дочерние процессы не задеты

# sandbox_git_home <каталог> — HOME песочницы; путь запоминается в SANDBOX_GIT_HOME.
sandbox_git_home() {
    local home="${1:-}" name email
    if [ -z "$home" ]; then
        echo "sandbox-git-home: каталог HOME песочницы не назван" >&2
        return 2
    fi
    name="$(command git config --global --get user.name 2>/dev/null || true)"
    email="$(command git config --global --get user.email 2>/dev/null || true)"
    if [ -z "$name" ] || [ -z "$email" ]; then
        echo "sandbox-git-home: корневой подписи нет (корневой gitconfig без имени или почты) — песочнице не с чего взять подпись" >&2
        return 2
    fi
    mkdir -p "$home/.config" || return 2
    : > "$home/.gitconfig" || return 2
    HOME="$home" XDG_CONFIG_HOME="$home/.config" command git config --global user.name "$name" || return 2
    HOME="$home" XDG_CONFIG_HOME="$home/.config" command git config --global user.email "$email" || return 2
    SANDBOX_GIT_HOME="$home"
}

# sandbox_run <команда…> — команда под HOME песочницы. Переменные подписи
# вызывающего снимаются: подпись песочницы — только её корневой gitconfig.
sandbox_run() {
    if [ -z "${SANDBOX_GIT_HOME:-}" ] || [ ! -f "$SANDBOX_GIT_HOME/.gitconfig" ]; then
        echo "sandbox-git-home: HOME песочницы не заведён (sandbox_git_home не звали либо каталог снят)" >&2
        return 2
    fi
    env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
        -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
        HOME="$SANDBOX_GIT_HOME" XDG_CONFIG_HOME="$SANDBOX_GIT_HOME/.config" "$@"
}

sandbox_git() { sandbox_run git "$@"; }
