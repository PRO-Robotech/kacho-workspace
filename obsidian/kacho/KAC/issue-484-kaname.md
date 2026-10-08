---
title: "kaname#484: линия kaname эпика notify — нотификации в ленту, снятие SMTP"
aliases:
  - issue-484-kaname
ticket_id: 484
category: kac
status: in-progress
verified_against: "`gh` 2026-10-08: пин kacho на голове `2914-notify` 504bc7acdc51 прочитан в `go.mod`, отставание головы ветки посчитано `gh api compare`. `gh` 2026-10-07: `gh pr list -R PRO-Robotech/kaname --base 484-notify --state all` — 17 PR MERGED (#533…#657), открытых 0; голова `484-notify` = 33010d434767 (merge-коммит #657, родители 22b70ea5d0a7 и 1316a650e); пин corelib на голове — `18d105d0f50a` (со слов описания #657); задача kaname#484 и эпик kacho#2914 OPEN; в `main` kaname из ветки эпика не влито ничего. Состав PR — со слов их заголовков и описаний; прогоны мной не перезапускались"
type: feature
repos:
  - kaname
areas:
  - internal/clients
  - internal/check
  - deploy
prs:
  - https://github.com/PRO-Robotech/kaname/pull/533
  - https://github.com/PRO-Robotech/kaname/pull/544
  - https://github.com/PRO-Robotech/kaname/pull/546
  - https://github.com/PRO-Robotech/kaname/pull/550
  - https://github.com/PRO-Robotech/kaname/pull/552
  - https://github.com/PRO-Robotech/kaname/pull/555
  - https://github.com/PRO-Robotech/kaname/pull/588
  - https://github.com/PRO-Robotech/kaname/pull/598
  - https://github.com/PRO-Robotech/kaname/pull/600
  - https://github.com/PRO-Robotech/kaname/pull/605
  - https://github.com/PRO-Robotech/kaname/pull/611
  - https://github.com/PRO-Robotech/kaname/pull/616
  - https://github.com/PRO-Robotech/kaname/pull/622
  - https://github.com/PRO-Robotech/kaname/pull/624
  - https://github.com/PRO-Robotech/kaname/pull/628
  - https://github.com/PRO-Robotech/kaname/pull/632
  - https://github.com/PRO-Robotech/kaname/pull/657
issue_url: https://github.com/PRO-Robotech/kaname/issues/484
opened: 2026-09-29
closed:
tags:
  - kac
  - kacho-iam
  - feature
---

# kaname#484: линия kaname эпика notify

**Состояние на момент записи**: `in-progress`. Все PR линии идут в ветку эпика kaname
`484-notify` (координата, не живая ссылка), а не в `main`; задача открыта — PR несут `Refs`,
не `Closes`. До посадки эпика в `main` статус `done` записке не положен.

**Эпик:** [[KAC/issue-2914]]. **Блокеры из тела:** PRO-Robotech/kacho-workspace#880 и
[[KAC/issue-77-corelib]]. **Роль исполнителя:** `go-implementer`.

## Что и зачем

kaname перестаёт слать почту сама: приглашение, восстановление и подтверждение адреса
ставятся в её ленту на фундаменте `corelib notify/feed`, notify забирает их и спрашивает kaname
о праве на каждое письмо; собственная отправка и креды почты из kaname и её поставки
снимаются. Предикат из тела — сценарии раздела «kaname» приёмки NTF-1 зелёные и в не-тестовом
Go-коде kaname нет импорта `net/smtp`. Подробности — в теле задачи.

## PR в `484-notify`

| PR | merge-коммит | влит (UTC) | предмет (по заголовку) | линия kacho |
|---|---|---|---|---|
| [#533](https://github.com/PRO-Robotech/kaname/pull/533) | `df69dd9f5e80` | 2026-10-01 | NTF-2 строгая конфигурация (F2) | — |
| [#544](https://github.com/PRO-Robotech/kaname/pull/544) | `a16d2da0f22f` | 2026-10-01 | пин corelib (Д64) | — |
| [#546](https://github.com/PRO-Robotech/kaname/pull/546) | `a5986266436b` | 2026-10-01 | нейтральное имя в пробе строгого конфига | — |
| [#550](https://github.com/PRO-Robotech/kaname/pull/550) | `bd8413637d68` | 2026-10-01 | K7: гейты дерева notify в kaname (NTF-1) | — |
| [#552](https://github.com/PRO-Robotech/kaname/pull/552) | `0f2395a624f3` | 2026-10-02 | пин corelib (C13) | — |
| [#555](https://github.com/PRO-Robotech/kaname/pull/555) | `57f1841789bd` | 2026-10-02 | пин corelib (C13a) | [[KAC/issue-2915]] |
| [#588](https://github.com/PRO-Robotech/kaname/pull/588) | `06966a081c7a` | 2026-10-03 | догон `main` после посадки Ory | [[KAC/issue-2915]] |
| [#598](https://github.com/PRO-Robotech/kaname/pull/598) | `a3c0158af93e` | 2026-10-04 | пин corelib (Д109) | — |
| [#600](https://github.com/PRO-Robotech/kaname/pull/600) | `0afabc18cc2c` | 2026-10-04 | К2: внутренний сервис выдачи права на нотификации (K3c, K5, K3) | — |
| [#605](https://github.com/PRO-Robotech/kaname/pull/605) | `745640d6c296` | 2026-10-04 | волна модули-1: X4J | [[KAC/issue-2918]] |
| [#611](https://github.com/PRO-Robotech/kaname/pull/611) | `c1b397b735d5` | 2026-10-05 | справочник адресов: полоса acr «1» (Д121), пин corelib | [[KAC/issue-2918]] |
| [#616](https://github.com/PRO-Robotech/kaname/pull/616) | `db080041cd95` | 2026-10-05 | посев пишет журнал с системным инициатором (Д122) | [[KAC/issue-2918]] |
| [#622](https://github.com/PRO-Robotech/kaname/pull/622) | `cbd729cfa9b1` | 2026-10-05 | пин corelib на `e7d6197f` | — |
| [#624](https://github.com/PRO-Robotech/kaname/pull/624) | `460e8f32802b` | 2026-10-06 | пин corelib на `bdb3799`, проба опрашивает операцию | — |
| [#628](https://github.com/PRO-Robotech/kaname/pull/628) | `56bcb3036d71` | 2026-10-06 | волна def1: почта NTF-2, шаблоны security, пин corelib | [[KAC/issue-2917]], [[KAC/issue-2919]] |
| [#632](https://github.com/PRO-Robotech/kaname/pull/632) | `22b70ea5d0a7` | 2026-10-07 | волна fence: ограда аудитории (Д133/Д134), K1 | [[KAC/issue-2918]] |
| [#657](https://github.com/PRO-Robotech/kaname/pull/657) | `33010d434767` | 2026-10-07 | пин corelib на голову `77-notify` (`18d105d`) | — |

Столбец «линия kacho» заполнен там, где связь названа в trail линии; «—» — связь нигде не
названа, и выводом по предмету она не дописывается.

### #657 — перепин на фундамент с окнами notify

Со слов описания PR: один коммит `1316a650e` — пин corelib с `67ba344` на `18d105d` (go.mod,
go.sum, таблица третьих сторон, перепорождённая `make operator-docs`). Зачем — гейт kacho
`TestOutsourcedModuleLinksTheSameFoundation` требует, чтобы kaname линковал тот же фундамент,
что kacho. Изменения corelib для kaname аддитивны, правок кода не потребовалось. Влит слиянием
без схлопывания; образ `484-notify-33010d43` собран (со слов комментария в задаче).

`18d105d` — голова PR corelib #102; дерево головы `77-notify` с ним совпадает (см.
[[KAC/issue-77-corelib]]).

## Потребитель

- kacho `2914-notify` на `504bc7acdc51` (2026-10-08, после kacho #3098) пинит kaname
  `56bcb3036d71` (#628), corelib `67ba3443c149` (прочитано в `go.mod`). Голова `484-notify`
  впереди пина на 13 коммитов (`gh api compare`) — #632 и #657 потребителем kacho не взяты.

## DoD (из тела задачи)

- [ ] сценарии раздела «kaname» приёмки NTF-1 зелёные;
- [ ] в не-тестовом Go-коде kaname нет импорта `net/smtp`;
- [ ] ветка `484-notify` влита в `main` kaname и снята при вливании.

## Связанные задачи

- https://github.com/PRO-Robotech/kacho/issues/2914 — эпик.
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib, блокер.
- https://github.com/PRO-Robotech/kacho/issues/2917 — NTF-2, почта личности: сторона kacho.

## History

- 2026-10-07 — trail заведён после вливания #657 (`33010d434767`) в `484-notify`; внесены
  все 17 PR ветки. Статус `in-progress`.
- 2026-10-08 — потребитель: kacho #3098 поднял пин до `56bcb3036d71`. Статус `in-progress`.

## Затронутые сущности vault

- [[rpc/kaname-internal-notification-recipient-service]] — справочник адресов; записка не
  менялась: #657 контракт не трогал.

#kac #kacho-iam #feature
