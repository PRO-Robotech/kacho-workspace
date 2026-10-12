---
title: "kaname#590: уборка испытаний ключа — порог равен сроку испытания"
aliases:
  - issue-590-kaname
  - kaname#590
ticket_id: 590
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/retention
  - internal/apps/kaname/api/access_keys
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
  - https://github.com/PRO-Robotech/kaname/pull/591
issue_url: https://github.com/PRO-Robotech/kaname/issues/590
opened: 2026-10-04
closed: 2026-10-04
tags:
  - kac
  - kacho-iam
  - iam
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#590: уборка испытаний ключа — порог равен сроку испытания

> [!note] Состояние — `test`: задача ЗАКРЫТА вместе с волной-2, в `main` службы не влито
> Волна [[KAC/issue-536-kaname]] влита в ветку эпика `296` запросом [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (коммит слияния `77dae639`,
> 2026-10-04); задача стоит в запросе строкой `Closes` и закрыта каскадом. Запроса `296` → `main` нет —
> до него состояние `test`, и на `origin/main` службы прежнее поведение.

## Что и зачем

Сквозная проба `ak03-replay` плавала: повторное предъявление результата церемонии иногда
получало «испытание не выдавалось» вместо «уже предъявлено» (Ф7-03, Ф7-34). Причина — запись реестра
уборки для испытаний ключа объявляла порог 0, и проход уборки мог снять предъявленное испытание
раньше, чем его прочтёт повтор. Порог теперь — срок испытания (`access_keys.ChallengeTTL`), он
передаётся реестру явно, а без него запись не регистрируется.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| починка ak03 → волна | ветка `590` (координата, не живая ссылка: снята; голова PR kaname#591) → ветка `536` | 335b9571 | 2bf331d1 | [kaname#591](https://github.com/PRO-Robotech/kaname/pull/591) |
| волна → эпик | ветка `536` (координата, не живая ссылка) → ветка `296` | 594af5af | 77dae639 | [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) |

Коммиты задачи: `335b95715`.

## Затронутые каталоги

`internal/apps/kaname/retention/registry.go`, `cmd/kaname/loginlane.go`; проба `access_key_challenge_retention_integration_test.go`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] закрыта вливанием волны — комментарий каскада 2026-10-04: локальный прогон в форме конвейера 13 из 13 на голове 594af5af, хук отправки 6 групп из 6, сверка волны приняла DoD;
- [x] проба порога — красная до правки, близнец (давние строки снимаются) зелёный — со слов тела PR kaname#591;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- [[packages/kaname-access-keys]] — History #590
- [[resources/kaname-access-key]] — уборка испытаний (History #590)

## Связанные задачи

- [[KAC/issue-536-kaname]] — волна-2
- [[KAC/issue-296-kaname]] — эпик

#kac #kacho-iam #iam
