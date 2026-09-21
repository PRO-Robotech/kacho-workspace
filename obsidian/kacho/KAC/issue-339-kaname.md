---
title: "kaname#339: три причины отзыва семейства без писателя"
aliases:
  - issue-339-kaname
  - kaname#339
ticket_id: 339
category: kac
status: planned
type: feature
repos:
  - kaname
prs: []
issue_url: https://github.com/PRO-Robotech/kaname/issues/339
opened: 2026-09-21
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - migrations
verified_against: "словарь `domain.FamilyRevocationReason` и его писатели переписаны на 229a0693 продукта PRO-Robotech/kaname (2026-09-21) по каждому из шести имён, тестовые файлы и файл объявления исключены; на origin/main ни таблицы `kaname.token_families`, ни файла `internal/repo/kaname/pg/oauth_ceremony_repo.go` нет"
---

# kaname#339: три причины отзыва семейства без писателя

> [!warning] Предмет живёт только в невлитой полосе — задача заблокирована
> Собственная церемония OAuth заведена полосой `kn-313`: на `origin/main` нет ни
> `kaname.token_families`, ни ceremony-адаптера (сверено 2026-09-21). Ни одна посадка
> сегодня этим кодом не обслуживается, и задача ждёт слияния полосы.

## Предмет

Словарь причин отзыва семейства объявлен **закрытым** — корзины «прочее» у него нет — и
держится ограничением `token_families_revoked_reason_ck`. Значений шесть:
`code-replay` · `refresh-replay` · `logout` · `session-ended` · `consent-withdrawn` ·
`client-removed`.

Писателей на `229a0693` имеют **три**: `code-replay`, `refresh-replay` и `session-ended`
(последний завела сама полоса). Остаются без писателя `logout`, `consent-withdrawn`,
`client-removed`.

## Координата

`internal/repo/kaname/pg/oauth_ceremony_repo.go:442-445` на `229a0693` — остаток назван в
шапке писателя `revokeFamiliesOfSessionsTx`.

## Признак

Объявленная возможность, которой никто не исполняет, — **долг, а не будущее**: читатель
словаря видит закрытый перечень причин и заключает, что каждая из них наступает. Проверить
это чтением одного места нельзя — нужен обход писателей по каждому имени, и ровно этот
обход здесь и дал три нуля.

Класс сверх самого перечня: у `client-removed` есть очевидный кандидат в писатели — тот же
путь, что уже гасит отсечку отчеканенного при снятии клиентской записи. Эти два действия
разошлись бы молча, если завести их порознь.

## Предикат снятия

Перепись по оси «имя причины → число непробных писателей» не даёт ни одного нуля. Форма
переписи даётся предикатом, а не списком имён: список разойдётся со словарём молча, а
словарь производен от ограничения схемы.

## Затронутые сущности vault

- [[resources/iam-token-family]] — строка и её закрытый словарь причин.
- [[resources/iam-authorization-code]] · [[resources/iam-refresh-token]] — что снимается вместе с семейством.
- [[packages/kaname-repo-pg]] — дом писателей.
- [[edges/kaname-family-revoke-vs-token-issue]] — что отзыв сегодня не разводится с выдачей.

#kac #kacho-iam #iam #go #migrations
