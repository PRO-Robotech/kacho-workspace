---
title: "kaname#358: волна-2 identity-own — сборки, влитые в ветку волны"
aliases:
  - issue-358-kaname
ticket_id: 358
category: kac
status: test
type: epic
repos:
  - kaname
areas:
  - internal/migrations
  - internal/repo/kaname/pg
  - internal/domain
  - cmd/kaname
  - internal/check
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kaname/pull/411
  - https://github.com/PRO-Robotech/kaname/pull/326
  - https://github.com/PRO-Robotech/kaname/pull/413
  - https://github.com/PRO-Robotech/kaname/pull/419
  - https://github.com/PRO-Robotech/kaname/pull/421
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/358
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "PRO-Robotech/kaname: запрос волны PR #422 358 → 357 влит коммитом слияния fc9f5aff19c (родители dbf25d17e25, cde2d924260), 2026-09-25T09:23:02Z (`gh pr view 422`); головы задач волны — предки fc9f5aff19c и не предки origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Сверка 2026-09-24 называла origin/358 = d22123ba095; 2026-09-26: трекер волны закрыт 2026-09-26T09:40:56Z, sub-issue закрыты 31 из 31, меток status:* нет (`gh api .../sub_issues`, `gh issue view`); fc9f5aff19c = origin/357, не в origin/main (`gh api compare`)"
---

# kaname#358: волна-2 identity-own — сборки, влитые в ветку волны

**Состояние на момент записи**: `test` — 2026-09-26. Волна **закрыта** на трекере 2026-09-26T09:40:56Z: её запрос PR #422 влит в ветку эпика `357` (координата, не живая ссылка) коммитом слияния `fc9f5aff19c` — это коммит закрытия волны и её задач. Тем же заходом закрыта 21 задача волны, у всех снята `status:test`; #322, #324, #325, #340, #341, #374 и задачи сборок #408, #412, #418, #420 закрыты раньше. В `main` волна **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #357 в ствол. Родитель — эпик kaname#357.

## Что и зачем

Своя запись кода авторизации и семейств токенов в службе доступа. Эта записка — trail волны
как единицы вливания: что влито в её ветку, с какими головами и каким вердиктом. Предмет
каждой задачи — в её записке.

Задачи волны — её sub-issue. Пока волна шла, перечнем они здесь не выписывались: состав
менялся переносами. Влитый состав закреплён запросом волны — раздел «Запрос волны» и ссылки
ниже; выборка sub-issue:

```sh
gh api repos/PRO-Robotech/kaname/issues/358/sub_issues --paginate -q '.[] | "#\(.number) \(.state) \(.title)"'
```

## Как вливается

Готовые задачи сводятся в ветку сборки коммитом слияния (`git merge --no-ff`); конвейер,
рецензенты и сверка гоняются один раз на голову сборки. Задача, влитая в волну, получает
`status:test` и закрывается вместе с волной, когда запрос волны влит в эпик (решение владельца
2026-09-26); прежняя норма — открыты до посадки эпика #357 в `main` — отменена.

## Вливания в ветку волны

| что | запрос | голова | коммит слияния в `358` | вердикт головы |
|---|---|---|---|---|
| #313 (до сборок) | PR #326, влит 2026-09-23T00:33:07Z | `410d750ba46b91f3a7f7300462aebb5df7bf8be3` | `9dc46b4722bea058c3642c803aae6a102ad1f98f` | контекстов на голове нет: триггера на ветку-номер тогда не было ([[KAC/issue-394-kaname]]) |
| база эпика | — | `357` @ `d65f97e9e3e` | `462f916e0eaf43a1b91b367fbcab23f001a285f1` | — |
| сборка 1, задача сборки #408 (закрыта) | PR #411, влит 2026-09-24T14:05:18Z | `2f45e7c8aa0ebb6a1ec25ff26523cc70e205bb03` | `d22123ba0957625fa791649bd72b6fffd694cfa0` (родители `462f916e0`, `2f45e7c8a`) | 3 прогона `pull_request`, 20 заданий: 17 `success`, 3 `skipped` («вердикт ствола» — только push в `main`), 0 упавших |

### Сборка 1 — задачи и головы

| задача | первое сведение: голова → слияние | повторное сведение: голова → слияние |
|---|---|---|
| [[KAC/issue-317-kaname\|#317]] | `2b203955a36` → `a37b67366bb` | — |
| [[KAC/issue-404-kaname\|#404]] | `b9dd132dc46` → `ba62d8d8ecd` | — |
| [[KAC/issue-396-kaname\|#396]] | `c49152dd3c7` → `61c47dcf79d` | `b372cba3e1c` → `dd1e253219c` |
| [[KAC/issue-314-kaname\|#314]] | `30c41bbcf0c` → `0abe7af28a9` | `0b8113cb894` → `effd23c3f17` |
| [[KAC/issue-394-kaname\|#394]] | `bae45d0fdd5` → `b709c3a218c` | `09bb99905d9` → `8fc953171b8` |
| [[KAC/issue-320-kaname\|#320]] | `074b2fd3e51` → `6e7fc244372` | `e4048dc37d9` → `351a853b117` |

Таблица тела PR #411 называет только головы **первого** сведения; повторное сведение и два
коммита #379 прямо на ветке сборки (`d0afbb45d4c`, `2f45e7c8aa0`) пришли после. #379 —
задача волны-1 #365, её записки в хранилище нет. Финальные головы задач — предки origin/`358`
и не предки origin/`357` и origin/`main`; у пяти задач они равны голове их ветки на origin,
ветка `394` с origin снята.

Не вошли по конфликту слияния, возвращены исполнителю: #316 и #319 — пути и стороны названы
в теле PR #411.

### Сборки 2–4 и вливания вне сборок

| что | запрос | голова | коммит слияния в `358` | задачи | вердикт головы |
|---|---|---|---|---|---|
| сборка 2, [[KAC/issue-412-kaname\|#412]] (закрыта) | PR #413, влит 2026-09-24T22:02:14Z | `5dfe66b58df` | `f4c6537ac4a` | [[KAC/issue-399-kaname\|#399]], [[KAC/issue-410-kaname\|#410]], [[KAC/issue-316-kaname\|#316]], [[KAC/issue-402-kaname\|#402]], а также #349 и #356 — не sub-issue этой волны | 6 прогонов, все `success` |
| сборка 3, [[KAC/issue-418-kaname\|#418]] (закрыта) | PR #419, влит 2026-09-24T23:39:35Z | `a6486c23423` | `196bf966488` | [[KAC/issue-401-kaname\|#401]], [[KAC/issue-393-kaname\|#393]] и #384 — не sub-issue этой волны | 5 прогонов, все `success` |
| сборка 4, [[KAC/issue-420-kaname\|#420]] (закрыта) | PR #421, влит 2026-09-25T03:19:27Z | `3519378f86d` | `ee2b564b82b` | [[KAC/issue-369-kaname\|#369]], [[KAC/issue-395-kaname\|#395]], [[KAC/issue-319-kaname\|#319]], [[KAC/issue-414-kaname\|#414]] | 6 прогонов, все `success` |
| вне сборок | — | — | `b2008871a86`, `cca75858382`, `1673b811eff`, `860078a9679`, `d6d8170ff57` | [[KAC/issue-341-kaname\|#341]], [[KAC/issue-340-kaname\|#340]], [[KAC/issue-397-kaname\|#397]], [[KAC/issue-321-kaname\|#321]], [[KAC/issue-334-kaname\|#334]] | прогонов нет — запросов у них не было |

С #313 запросом #326 пришли [[KAC/issue-322-kaname|#322]], [[KAC/issue-324-kaname|#324]],
[[KAC/issue-325-kaname|#325]] и [[KAC/issue-374-kaname|#374]].

## Запрос волны

PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5,
все `success`. Две правки самой волны и перечень вынесенного в волны 3 и 4 (#315, #318, #406,
#407, #405, #339, #352, #338, #368) — в теле запроса.

## Закрытие

Каскад 2026-09-26 — по комментарию закрытия трекера волны: закрыта 21 задача, новых остатков
0, переведённых без сдачи в этом заходе 0 (раньше в волну-3 #366 ушли #315, #318, #405, #406,
#407; вне волн — #339, #352). Остаток п.3 [[KAC/issue-393-kaname|#393]] (коллекции `iam-role`
и `iam-user`) ведёт существующая [[KAC/issue-415-kaname|#415]] в волне-3 #366. Строка и
комментарий полосы [[KAC/issue-313-kaname|#313]] в корне композиции стали остатком п.3 задачи
#337 волны-1 — [[KAC/issue-428-kaname|#428]], см. [[KAC/issue-365-kaname]].

## Затронутые сущности vault

Возвраты исполнителей волны называют ресурсы interactive_clients, token_families, authorization_codes,
refresh_tokens, access_tokens, human_sessions, consent_grants (снят); rpc InternalIAMService.ForceLogout и
InternalSessionRevocationsService.IsRevoked; пакеты ceremonyport, tokenrevocation, passwordverify,
repo/kaname/pg; ребро kaname → corelib v1.10.0-rc.2. Обновлены и заведены узкие записки:
[[resources/iam-token-family]], [[resources/iam-interactive-client]], [[resources/iam-human-session]],
[[rpc/iam-internal-iam-service]], [[rpc/iam-internal-session-revocations-service]].

- [[KAC/issue-317-kaname]] · [[KAC/issue-404-kaname]] · [[KAC/issue-396-kaname]] ·
  [[KAC/issue-314-kaname]] · [[KAC/issue-394-kaname]] · [[KAC/issue-320-kaname]] — задачи
  сборки 1.
- [[KAC/issue-313-kaname]] · [[KAC/issue-408-kaname]] — #313 до сборок и задача сборки 1.
- остальные задачи волны — по ссылкам в таблице сборок 2–4 выше.
- [[KAC/issue-295-kaname]] — sub-issue этой волны, влита через волну [[KAC/issue-377-kaname|#377]].

#kac #kacho-iam #epic
