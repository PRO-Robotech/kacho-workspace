---
name: rule-vault
description: "Vault Obsidian: context-источник, trail задачи, запреты"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/vault.md`

# Obsidian vault — обязательный context-источник и trail

Дом — `obsidian/kacho/`. Категории заданы каталогом верхнего уровня, других нет: `resources/`,
`rpc/`, `packages/`, `edges/`, `KAC/`, `lessons/`, `runbooks/`, `docs/`, `legacy/`. Оболочка
записки — `obsidian/kacho/CLAUDE.md`, здесь она не пересказывается.

vt-one-note-one-subject · одна записка — один предмет; соседа называй ссылкой, не пересказом · vault-gate check-03 · red: два места об одном предмете
vt-write-by-own-worktree · пиши `Edit`/`Write` по `obsidian/kacho/**` СВОЕЙ копии; MCP-сервер пишет мимо коммита · `find . -maxdepth 2 -name .mcp.json` пусто · red: запись мимо гейта и origin
vt-owner-is-scribe · записки ведёт `vault-scribe`; прочий называет затронутое строкой возврата · MANIFEST.md, колонка закрепления · red: полоса правит vault сама

## ДО кода (читать минимум — 1-2 узких файла, не 50KB README)

vt-read-narrow-before-code · бери 1-2 узких записки: ресурс `resources/`, RPC `rpc/`, пакет `packages/`, ребро `edges/`, задача `KAC/issue-<N>.md` · вниманием · red: в окне большой `CLAUDE.md` репозитория вместо двух записок

## ПОСЛЕ работы (обновить trail — НЕ упускать)

vt-update-touched-notes · обнови записку тронутого: поле и FK ресурса, RPC, exported API пакета, cross-service поведение с записью в History и номером задачи · vault-gate run-all.sh · red: поведение изменилось, записка описывает прежнее
vt-new-subject-new-note · предмета в vault нет — заводи НОВУЮ узкую запись, не абзац в чужой · vault-gate check-03 · red: записка выросла вторым предметом

## Trail задачи (обязателен для каждой)

vt-trail-per-issue · заводи `KAC/issue-<N>.md` при первом упоминании задачи: Status, Type, каталоги, PR, «Что и зачем», затронутые сущности, DoD · docs-gate check-02-kac-trail-status.py · red: задача закрыта без trail
vt-trail-updated-on-state-change · обновляй после каждого вливания и смены состояния · docs-gate check-02-kac-trail-status.py · red: Status отстал от задачи

## Запреты

vt-no-stale-facts · устаревший факт правь тем же заходом · vault-gate check-02 (висячие ссылки) · red: записка называет координату, которой в дереве нет
vt-vault-is-public · пиши так, чтобы выдерживало публикацию: оба репозитория публичны · `security.md` §«Публичные артефакты» · red: секрет либо сборка «координата плюс условие отказа защиты»
