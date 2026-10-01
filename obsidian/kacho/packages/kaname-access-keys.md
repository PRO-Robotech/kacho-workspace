---
title: "internal/apps/kaname/api/access_keys — полоса ключей доступа"
aliases:
  - kaname access_keys
  - AccessKeyService use-cases
repo: kacho-iam
layer: usecase
path: internal/apps/kaname/api/access_keys
category: packages
status: test
tags:
  - packages
  - kacho-iam
  - iam
  - usecase
  - go
verified_against: "`project/kaname`, ветка `fix/access-key-irreversible-facts` (координата, не живая ссылка) @bd10ba67c1b, 2026-09-22: состав каталога и перечень глаголов контракта `proto/kaname/cloud/iam/v1/access_key_service.proto` сверены в обе стороны — шесть RPC; диффы `revoke.go`, `finish_registration.go`, `begin_registration.go` против `origin/main` прочитаны. Часть описанного в ствол НЕ влита"
---

# internal/apps/kaname/api/access_keys — шесть глаголов, по варианту использования на каждый

Слой вариантов использования домена доступа: обработчик тонкий, каждый глагол — свой файл.

| RPC | вид | файл |
|---|---|---|
| `BeginRegistration` | sync (выдаёт испытание) | `begin_registration.go` |
| `FinishRegistration` | async (Operation) | `finish_registration.go` |
| `List` | sync | `list.go` |
| `Revoke` | async (Operation) | `revoke.go` |
| `BeginAssertion` | sync (выдаёт испытание) | `begin_assertion.go` |
| `FinishAssertion` | sync | `finish_assertion.go` |

Рядом — `refusals.go` (тексты и причины отказов с названным следующим шагом), `audit.go`,
`decoy.go`, `proto.go`, `deps.go`, `iface.go`.

## Два инварианта, стоящих отдельного упоминания

- **страж последнего способа входа считает способы, а не строки.** Годным к предъявлению
  способом является только ключ с подтверждённой обнаружимостью: без обнаруживаемого
  удостоверения полоса входа без имени невозможна by construction. Счёт строк пропускал человека
  без пароля с двумя ключами, об обнаружимости которых чужая реализация промолчала;
- **последний способ судится дважды.** Синхронно — чтобы отказ назвал клиенту следующий шаг; и
  ещё раз под замком внутри транзакции — второе чтение держит инвариант, первое только
  классифицирует.

Чужой и несуществующий ключ **неразличимы**: строка сужена владельцем и не видна, ответ один.

## Рукоятка церемонии — оператор один, ветви «на всякий случай» нет

Завершение регистрации кладёт рукоятку в строку **внутри пишущей транзакции**: её значение —
факт хранилища, а не входа. Оператор «обеспечить рукоятку» и чеканит, и возвращает уже
заведённое; выдача испытания, без которой до завершения не доходят, строку человека уже завела.
Поэтому недостижимой ветви в коде нет. Предмет и состав — [[resources/iam-user-access-key]].

## Гейт рукоятки

`ceremony_handle_gate_test.go` в этом же каталоге держит свойство «рукоятка не несёт имени
человека». Домашний тип — `internal/domain/ceremony_handle.go`.

## Отношения

- Ресурс: [[resources/iam-user-access-key]] · способы входа: [[resources/iam-user-login-methods]].
- Полоса формы, в которую церемонии встраиваются: [[rpc/iam-login-lane]].
- Открытый предмет контракта: [[issue-351-kaname]].

## History

- 2026-09-22 — записка заведена по возврату полосы ключей доступа (`internal/domain`,
  `internal/apps/kaname/api/access_keys`, `internal/repo/kaname/pg`, `internal/migrations`
  названы затронутыми). Изменение в ствол не влито, состояние записки — `test`.

#packages #kacho-iam #iam #usecase #go
