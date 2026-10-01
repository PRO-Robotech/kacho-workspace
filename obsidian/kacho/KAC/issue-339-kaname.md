---
title: "kaname#339: три причины отзыва семейства без писателя"
aliases:
  - issue-339-kaname
  - kaname#339
ticket_id: 339
category: kac
status: test
type: feature
repos:
  - kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/457
  - https://github.com/PRO-Robotech/kaname/pull/481
issue_url: https://github.com/PRO-Robotech/kaname/issues/339
opened: 2026-09-21
closed: "2026-09-29"
tags:
  - kac
  - kacho-iam
  - iam
  - go
  - migrations
verified_against: "2026-10-01: доставка — коммиты полосы 339 (последний c7fdbc297) в слиянии полосы f5820c99b сборки 3 волны-3 (`git merge-base --is-ancestor`), слияние волны-3 734f69fb4 — предок origin/357 @ 7c5409f5e, не предок origin/main @ cbbac984b; словарь на голове 357 — `internal/domain/oauth_ceremony.go` и Up-раздел `20260927072645_family_revocation_reason_leaves_the_words_without_a_writer.sql`; гейт и проба схемы найдены `git grep` по имени функции; пробы не перезапускались. Прежняя сверка: словарь `domain.FamilyRevocationReason` и его писатели переписаны на 229a0693 продукта PRO-Robotech/kaname (2026-09-21) по каждому из шести имён, тестовые файлы и файл объявления исключены; на origin/main ни таблицы `kaname.token_families`, ни файла `internal/repo/kaname/pg/oauth_ceremony_repo.go` нет"
---

# kaname#339: три причины отзыва семейства без писателя

> [!note] Состояние — `test`: слова без писателя сняты, код в ветке эпика `357`
> Задача закрыта каскадом волны-3 [[KAC/issue-366-kaname|kaname#366]] 2026-09-29. Исход — снятие:
> слова `logout` и `client-removed` ушли из словаря и из базы, писателя они не получили. Домен
> несёт четыре слова (`code-replay`, `refresh-replay`, `session-ended`, `client-revoke`), базу
> держит миграция `20260927072645_family_revocation_reason_leaves_the_words_without_a_writer.sql`,
> писателя каждого слова — гейт `TestFamilyRevocationVocabulary_KN_FRV_17_EveryWordHasAWriter`,
> согласие домена и схемы — проба `TestIntegration_RevocationVocabularyAgreesWithTheDomain`.
> Полоса влита сборкой 3 волны-3 (PR #457, слияние полосы `f5820c99b`), волна — в `357` коммитом
> `734f69fb4`. В `main` службы таблицы семейств по-прежнему нет, поэтому `test`, а не `done`.
>
> Разделы ниже описывают состояние на `229a0693` (2026-09-21) и верны как история.

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

## History

- 2026-09-21 — заведена по ревизии полосы `229a0693`.
- 2026-10-01 — `planned` → `test`: задача закрыта каскадом волны-3 2026-09-29, слова без писателя
  сняты (полоса `339`, сборка 3 волны-3); стояла пометка «предмет только в невлитой полосе», хотя
  полоса `kn-313` влита в `357` ещё волной-2.

## Затронутые сущности vault

- [[resources/iam-token-family]] — строка и её закрытый словарь причин.
- [[resources/iam-authorization-code]] · [[resources/iam-refresh-token]] — что снимается вместе с семейством.
- [[packages/kaname-repo-pg]] — дом писателей.
- [[edges/kaname-family-revoke-vs-token-issue]] — соседний предмет того же семейства: отзыв и
  выдача по нему; на ветке эпика `357` ребро держит схема (запись поправлена 2026-09-26, #778).

#kac #kacho-iam #iam #go #migrations
