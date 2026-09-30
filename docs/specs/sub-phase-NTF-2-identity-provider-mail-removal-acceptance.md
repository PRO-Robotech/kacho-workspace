<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# Sub-phase NTF-2 (почта личности: kaname на ленте notify, защита почтовых глаголов, регистрация, секрет почты у одного объекта) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью
> в `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/`
> **История review:** строки только дописываются; прежние не правятся и не удаляются
> — редакция 1 · 2026-09-30 · вердикта нет · отпечаток — `sha256sum` этого файла
> — 2026-09-30 · круг 1 · ⛔ ВОЗВРАТ (блокирующих 6: CONSTRUCTIBILITY, SCOPE, NEGATIVE, COVERAGE,
> PRODUCER, FORMAT) · SHA-256 `fc9628df0bb9a136327b89f776db28f58368616449a2b94d4a63285455250b21` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/fc9628df0bb9a136327b89f776db28f58368616449a2b94d4a63285455250b21.yaml`
> — редакция 2 · 2026-09-30 · вердикта нет · закрывает B1-1…B1-6 и I1-1…I1-6 круга 1; что изменено — §11
> — 2026-09-30 · круг 2 · ⛔ ВОЗВРАТ (блокирующих 3: COVERAGE, CONSTRUCTIBILITY) · SHA-256
> `1658e6f5e93312d524f1b5a8ad670691ed1d05566a7d62b53f053f1a338d491a` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/1658e6f5e93312d524f1b5a8ad670691ed1d05566a7d62b53f053f1a338d491a.yaml`
> — редакция 3 · 2026-09-30 · вердикта нет · закрывает B2-1…B2-3 и I2-1…I2-5 круга 2; что изменено — §11
> — 2026-09-30 · круг 3 · ⛔ ВОЗВРАТ (блокирующих 2: COVERAGE, COVERAGE) · SHA-256
> `7e6e8bb881ad3d68207345532ef664bad8547898bbd22bd5db4d7b1540c2536c` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/7e6e8bb881ad3d68207345532ef664bad8547898bbd22bd5db4d7b1540c2536c.yaml`
> — редакция 4 · 2026-09-30 · вердикта нет · закрывает B3-1, B3-2, I3-1, I3-2 круга 3; что изменено — §11
> — 2026-09-30 · круг 4 · ⛔ ВОЗВРАТ (блокирующих 1: CONSTRUCTIBILITY) · SHA-256
> `3fb89e6b74a02454f3911da0c7421b4ba51befdf3a546e5dcf8c5d181016cc97` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/3fb89e6b74a02454f3911da0c7421b4ba51befdf3a546e5dcf8c5d181016cc97.yaml`
> — редакция 5 · 2026-09-30 · вердикта нет · закрывает B4-1, I4-1, I4-2 круга 4; что изменено — §11
> — редакция 6 · 2026-09-30 · вердикта нет · **предмет сменён** решением диспетчера: NTF-2 — «почта
> личности» (kaname на ленте, флаг почты, защита почтовых глаголов, регистрация, класс S из аудита
> kaname, снятие почты поставщика по новому предикату Д12); редакцию 5 не рассматривал ни один круг;
> что изменено — §11
> — 2026-09-30 · круг 1 после смены предмета · ⛔ ВОЗВРАТ (блокирующих 3: CONSTRUCTIBILITY, COVERAGE,
> COVERAGE) · SHA-256 `4991ac4fb26d34f8dcb2b15030666285fa36a4a8dab6ee1d4e483141a610feb9` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/4991ac4fb26d34f8dcb2b15030666285fa36a4a8dab6ee1d4e483141a610feb9.yaml`
> — редакция 7 · 2026-09-30 · вердикта нет · закрывает B-1…B-3 и I-1…I-4 этого круга; класс COVERAGE
> закрыт по всему документу таблицей «правило → держатель» (§6б); что изменено — §11
> — 2026-09-30 · круг 2 после смены предмета · ⛔ ВОЗВРАТ (блокирующих 6: CONSTRUCTIBILITY ×3, FORMAT,
> NEGATIVE, COVERAGE) · SHA-256 `33e199c9ce4e4e19d3b183db98e36c0270529ebcb21915be0e9348c6d4f44078` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/33e199c9ce4e4e19d3b183db98e36c0270529ebcb21915be0e9348c6d4f44078.yaml`
> — редакция 8 · 2026-09-30 · вердикта нет · закрывает B2-1…B2-6 и I2-1…I2-4 этого круга; род
> CONSTRUCTIBILITY повторился трижды — класс закрыт по всему документу переписью «Given и счёт →
> построение» (§6в); что изменено — §11
> — 2026-09-30 · круг 1 прохода Д14–Д16 · ⛔ ВОЗВРАТ (блокирующих 3: COVERAGE ×2, CONSTRUCTIBILITY) ·
> SHA-256 `a4f11ceefcbbc753ee047e964699f0b555cbd2c2d2ace037d5fc4a9e6e59b9d6` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/a4f11ceefcbbc753ee047e964699f0b555cbd2c2d2ace037d5fc4a9e6e59b9d6.yaml`
> — редакция 9 · 2026-09-30 · вердикта нет · закрывает B-1…B-3 и I-1…I-3 этого круга; класс COVERAGE
> закрыт переписями по предмету — «ручка → поведение» и «равенство для любого адреса» (§6б); класс
> CONSTRUCTIBILITY — перепись символов времени и равенства ответов по тексту §6 (§6в); что изменено — §11
> — 2026-09-30 · круг 2 прохода Д14–Д16 · ⛔ ВОЗВРАТ (блокирующих 1: COVERAGE) · SHA-256
> `dd806ce949eb6c0ab84663629cd0fc9ed67acdc750d08c390abec0534e7ec9c0` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/dd806ce949eb6c0ab84663629cd0fc9ed67acdc750d08c390abec0534e7ec9c0.yaml`
> — редакция 10 · 2026-09-30 · вердикта нет · закрывает B-1 и I-1…I-5 этого круга; класс COVERAGE
> закрыт по длительностям: у каждой длительности Р8 — ручки и окна, заданного именем ручки, —
> держатель утверждает обе стороны границы (§6б, «длительность → обе стороны»); что изменено — §11
> — 2026-09-30 · круг 3 прохода Д14–Д16 · ⛔ ВОЗВРАТ (блокирующих 1: CONSTRUCTIBILITY) · SHA-256
> `27cd8f0612549600b16f42301934e6b85c165fd477055195563e81571a05f689` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/27cd8f0612549600b16f42301934e6b85c165fd477055195563e81571a05f689.yaml`
> — редакция 11 · 2026-09-30 · вердикта нет · закрывает B-1 и I-1…I-3 этого круга; пол при скользящих
> окнах — одно правило Р6 (`Tc`, `Tw`, возобновление прогрессии), класс проведён по всем сценариям с
> `Tc`; что изменено — §11
> — редакция 12 · 2026-09-30 · вердикта нет · правка одобренной редакции 11 (`9098d6ef…`) по возврату
> разбора классов изменения `issue-2917`: К1, К2 (NTF-2 приведена к одобренной NTF-1 — исключение
> `kaname` и единый отказ флага), Е3 (граница `invite.recipient-per-day-all`), Е4 (замещение окна
> обращений по источнику `kaname#456`), Е9 (исход `503` ограничителя края и консоль на `503` и
> `expired`); одобрение редакции 11 к этому отпечатку не переносится; что изменено — §11
> — 2026-09-30 · круг 1 редакции 12 · ⛔ ВОЗВРАТ (блокирующих 1: COVERAGE) · SHA-256
> `f38dee0f359578c0eb23ea2f715072e7dd1dcce9c61c0b9dfd19d8c42fd00780` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/f38dee0f359578c0eb23ea2f715072e7dd1dcce9c61c0b9dfd19d8c42fd00780.yaml`
> — редакция 13 · 2026-09-30 · вердикта нет · закрывает B-1 и N-1…N-6 этого круга; класс COVERAGE
> «правило единственного производителя без держателя, падающего на копии» закрыт по всему документу
> пятой переписью §6б — «единственный производитель → держатель»; что изменено — §11
> — 2026-09-30 · круг 2 редакции 13 · ✅ APPROVED (блокирующих 0) · SHA-256
> `ef9c68019a7d58c7bce1ba0bdeb3ba2f56d508d1c53cb5db9b51de98b3bd825f` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/ef9c68019a7d58c7bce1ba0bdeb3ba2f56d508d1c53cb5db9b51de98b3bd825f.yaml`
> — редакция 14 · 2026-09-30 · вердикта нет · правка одобренной редакции 13 (`ef9c6801…`) по решениям
> диспетчера Д39 (снятие почты поставщика личности — релиз identity-own, `kacho#1276`; страж секрета
> почты один) и Д40 (база — линия релиза; все утверждения о дереве перемерены на её ветках); одобрение
> редакции 13 к этому отпечатку не переносится; что изменено — §11
> — 2026-09-30 · круг 1 редакции 14 · ⛔ ВОЗВРАТ (блокирующих 2: CONSTRUCTIBILITY, PRODUCER) · SHA-256
> `e618a9f7c2cec159a864aa9b83d2071ae37f34d2788ab1ff9e5639653a172f95` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/e618a9f7c2cec159a864aa9b83d2071ae37f34d2788ab1ff9e5639653a172f95.yaml`
> — редакция 15 · 2026-09-30 · вердикта нет · закрывает B-1, B-2 и N-1, N-2 этого круга; класс
> PRODUCER («производителем назван объект или механизм под-фазы, которая его не производит») закрыт
> переписью всех мест, где производителем названа другая под-фаза (§7, §6б); что изменено — §11
> — 2026-09-30 · круг 1 редакции 15 · ✅ APPROVED (блокирующих 0) · SHA-256
> `229a43791107c01c74c4538a08da389573674f372793434cffd1834feba9f929` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/229a43791107c01c74c4538a08da389573674f372793434cffd1834feba9f929.yaml`
> — редакция 16 · 2026-09-30 · вердикта нет · правка одобренной редакции 15 (`229a4379…`) по возврату
> первичного разбора классов изменения `issue-2917` на этот отпечаток
> (`docs/changes/issue-2917/reviews/class-exposure/initial/229a43791107c01c74c4538a08da389573674f372793434cffd1834feba9f929.yaml`):
> RA-1 (чтение узла полосы и удостоверения почты чартом `notify` названо — Р20, NTF2-34), RA-2
> (исключение DoD п.16 привязано к факту снятия файла посадкой `kacho#1276`, а не к исходу строки §3а);
> одобрение редакции 15 к этому отпечатку не переносится; что изменено — §11
> — 2026-09-30 · круг 1 редакции 16 · ⛔ ВОЗВРАТ (блокирующих 2: CONSTRUCTIBILITY, DoD) · SHA-256
> `c79fea783eac045d66438c3c7b793bac60b8c3f94ce41d2e5633a129d3c00ada` ·
> `docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/c79fea783eac045d66438c3c7b793bac60b8c3f94ce41d2e5633a129d3c00ada.yaml`
> — редакция 17 · 2026-09-30 · вердикта нет · закрывает B-1, B-2 и N-1…N-3 круга 1 редакции 16; что
> изменено — §11
> — редакция 18 · 2026-09-30 · вердикта нет · решение диспетчера Д44 применено к исходу «`notify`
> включён, узел почты пуст» (цепочки `prod`, `fe3455`): отказ старта отправителя `notify` (NTF-1),
> пустой узел доезжает до отправителя пустым — NTF2-34 (е), (е'); что изменено — §11
> **Дата:** 2026-09-30
> **Эпик:** `PRO-Robotech/kacho#2914` (сервис уведомлений — единый почтовый шлюз)
> **Задачи:** `PRO-Robotech/kacho#2917` (чарт, край, консоль, страж секрета почты) и
> `PRO-Robotech/kaname#484` (сторона kaname); документ ведётся задачей `PRO-Robotech/kacho-workspace#880`;
> пакет изменения — `docs/changes/issue-2917/` (заведён, ссылается на этот файл)
> **Соседние под-фазы:** NTF-1 `kacho#2915` (`corelib#77`), NS `kacho#2916`, NTF-3 `kacho#2918`,
> NTF-4 `kacho#2919`, NTF-5 `kacho#2924`, NTF-6 `kacho#2925`
> **База — линия релиза identity-own (Д40):** kacho — ветка эпика релиза `origin/2564` = `6edea09c2ee`,
> в неё вливается волна-4 `origin/2798` = `96e2fa72b3a` (`2564` — предок `2798`, 31 коммит сверху);
> kaname — `origin/357` = `734f69fb4`, волна-4 `origin/367` = `caf1c95ca` (`357` — предок, 72 коммита
> сверху); corelib — `origin/26` = `cfe49ef00fa` = тег `v1.10.0-rc.5` (его пинят оба дерева). Замеры —
> на головах волн-4 (`2798`, `367`) и `origin/26`; где число на ветке эпика другое, названо оба.
> Предикат ревизий: `git rev-parse --short origin/{2564,2798}` в kacho, `origin/{357,367}` в kaname,
> `origin/26` в corelib; `git merge-base --is-ancestor origin/2564 origin/2798` → 0
> **Соседняя приёмка NTF-1, на которую опираются Р1, Р4, Р14:** редакция 16, SHA-256 `390b5a33368b…`,
> вердикт APPROVED — `docs/specs/reviews/sub-phase-NTF-1-notification-gateway-core-acceptance/390b5a33368bc84b6d0b9351a85413d91bdab031c893391fa23ae5132c6b524e.yaml`.
> Строки её изменённого текста против редакции 13 (`05828e42…`, которую сверял разбор классов) не
> задевают NTF1-F21, NTF1-G22, NTF1-N06, `authorization: certificate` и `DeliveryNotConfigured`
> (`git diff 5f3851113 9636eb28f -- <док NTF-1> | grep '^[+-]' | grep -cE 'NTF1-(N06|G22|F21)|DeliveryNotConfigured|authorization: certificate'` → 0)
> **Формат:** Given-When-Then, только наблюдаемое поведение. Кода в документе нет по построению
> **Публичный репозиторий:** документ называет требования, ручки и границы; текущих слабых мест и
> пошаговых описаний атаки в нём нет (§10)

---

## §0 Обзор

NTF-2 переводит **всю почту личности** на единый шлюз `notify` и делает почтовые глаголы личности
безопасными для владельца адреса. Под-фаза даёт шесть результатов (S1–S5, S7; номер S6 не
переиспользуется):

1. **S1. kaname — источник ленты.** Приглашение, восстановление, подтверждение адреса и новые
   письма личности kaname ставит в свою ленту `corelib notify/feed` в транзакции события. Доставляет
   их `notify`. Собственный отправитель kaname, её почтовые ручки, креды и очередь писем снимаются.
2. **S2. Флаг почты kaname** (Д7). Явное объявление «генерить почтовые запросы или нет», без
   умолчания. При выключенном флаге действия, которым нужна почта, получают явный отказ, одинаковый
   для любого адреса.
3. **S3. Лимиты и защита от спама для анонимных почтовых глаголов** (Д11): край — по источнику и
   подсети, своя proof-of-work, `429` с `Retry-After`; kaname — на адресата, с повтором того же
   действующего кода и «полом», который никогда не отрезает владельца; потолки приглашений;
   доверенное устройство.
4. **S4. Регистрация «сначала письмо, потом сессия».** Ответ одинаков для свободного и занятого
   адреса; учётная запись и сессия появляются только после предъявления кода.
5. **S5. Обязательный класс S из аудита kaname** (Д9 в части личности): роли, ключи и токены,
   блокировка, сессии, пароль и второй фактор, ключ входа, вход с нового устройства, совершённое
   восстановление, удаление аккаунта и проекта.
6. **S6 — вне NTF-2** (Д39). Снятие почты поставщика личности — раздел `courier`, почтовый процесс,
   потоки и хуки поставщика, подчарты `kratos` и `hydra` — принадлежит релизу identity-own:
   `kacho#1276` в волне-4 `kacho#2798` (§4, Р19).
7. **S7. Секрет почты смонтирован ровно в одном объекте — отправителе `notify`** (Д20, Д23, Д39) —
   при напечатанном объёме обхода. **Отправитель `notify`** — рабочий объект чарта `notify`,
   исполняющий отправку письма: при посаженной NTF-1 без NTF-3 это единственное развёртывание службы
   (`notify`, NTF-1 Р9, NTF1-I01, NTF1-N04); после NTF-3 Р8 — развёртывание `notify-sender` (у
   `notify-api` ссылок на секрет почты 0, NTF3-127). Предикат ниже не опирается ни на одно из двух имён
   и выполним при любом порядке посадки NTF-2 и NTF-3 (Р16). Страж рендера один — существующий
   `deploy/helm/umbrella/templates/identity-mail-lane-guard.yaml`; второго шаблона стража NTF-2 не
   заводит, а условие «секрет только у отправителя» судит гейт рендера по всем объектам (Р19).

**Предикат завершения** — одна формулировка, одинаковая здесь, в NTF2-30, NTF2-33 и в DoD п.20. В
рендере каждой цепочки `deploy/stacks.txt` и в рендере самостоятельной поставки kaname:

- объектов со ссылкой на секрет почты вне чарта `notify` — **0**;
- объектов, несущих адрес почтового узла, вне чарта `notify` — **0**;
- в цепочке, объявляющей удостоверение почты, объектов чарта `notify` со ссылкой — **ровно 1**; это
  и есть отправитель `notify`, узнаваемый по идентичности объявления (`# Source:` под чартом
  `notify`), а не по образцу имени.

Объект, несущий адрес узла, — любой объект чарта `notify` (развёртывание или его карта настроек):
где именно чарт держит адрес, решает замысел; предикат судит границу чарта.

Гейт печатает число цепочек и объектов обхода. Пустой обход — красный. Поставщик личности выключен во
всех цепочках (§1.6), поэтому его объекты в обход цепочек не попадают; рендер с поставщиком,
поднятым заново, — предмет `kacho#1276` (§1.7).

Переход прямой, без периода двух путей: прода нет (В-прод, Д12).

### §0.1 Дом документа

Дом — воркспейс `docs/specs/`. Предмет лежит в двух продуктах: kaname (глаголы, лента, аудит,
модель), kacho (край, чарт, служба `notify`, консоль). Приёмка
кросс-доменного предмета живёт в воркспейсе (`.claude/rules/polyrepo.md` note «У приёмки домов ДВА,
и это решение, а не дрейф»). Пакет изменения — `docs/changes/issue-2917/`; он ссылается на этот файл
по отпечатку и не несёт его копии.

---

## §1 Что верно сегодня — с командой пересчёта

Все замеры — на ревизиях шапки (Д40). «Дерево kaname» — `origin/367` @`caf1c95ca`, «дерево kacho» —
`origin/2798` @`96e2fa72b3a`, «corelib» — `origin/26` @`cfe49ef00fa`. Каждое утверждение — предикат с
командой и числом (Д24); где число на ветке эпика (`357` @`734f69fb4`, `2564` @`6edea09c2ee`) другое,
оно названо рядом.

### §1.1 Почта kaname: отправитель, виды, очередь, ручки

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca (origin/367) · единица — не-тестовый файл Go
git grep -l '"net/smtp"' origin/367 -- '*.go' ':!*_test.go'
#   → internal/check/mail_send_paths.go (гейт MAIL-47) · internal/clients/invite_mail.go (отправитель)
git grep -hoE '"mail\.[a-z_]+\.[a-z_]+"' origin/367 -- '*.go' ':!*_test.go' | sort -u
#   → "mail.invite.send" "mail.recovery.send" "mail.verification.send"   (3 вида)
git grep -n 'var OurMailKinds' origin/367 -- internal/check/mail_send_paths.go
#   → :112 — {MailKindInvite, MailKindRecovery, MailKindVerification}
git grep -l 'invite_mail_outbox' origin/367 -- 'internal/migrations/*.sql'
#   → 0001_initial.sql · 20260917015400_recovery_code_is_our_record.sql · 20260927190000_address_verification_is_our_verb.sql
git show origin/367:internal/apps/kaname/config/defaults.go | grep -cE '"invite-mail\.'
#   → 10 ключей почтового узла (relay, from, from-name, username-env, password-env, tls-mode, ca-bundle-file, login-url, attempt-timeout, max-attempts)
# на origin/357 все пять команд дают то же
```

**Перепись файлов kaname, задевающих почту.** Предикат — слова отправителя, очереди, видов и узла:

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca · единица — отслеживаемый файл, кроме *.md
P='invite-mail|inviteMail|KANAME_INVITE_MAIL|invite_mail|net/smtp|MailKind|OurMailKinds'
LC_ALL=C git grep -lE "$P" origin/367 -- ':!*.md' | wc -l                    # → 97
LC_ALL=C git grep -lE "$P" origin/367 -- ':!*.md' ':!*_test.go' | wc -l      # → 49 не-тестовых
# на origin/357 — 94 и 48; разность по файлам (diff двух выводов):
#   − cmd/kaname/provider_compensation_wiring.go (файл есть, слов предиката в нём после волны-4 нет)
#   + deploy/mail_lane_names_every_letter_kind{,_injection}_test.go (#259) · deploy/values.prod.yaml
#   + docs/content/install/configuration.mdx
```

Разбивка по каталогам и исход каждой группы — §3б.

### §1.2 Аудит kaname — источник класса S

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca
git grep -hoE '"iam\.[a-z_]+\.[a-z_]+"' origin/367 -- '*.go' ':!*_test.go' | sort -u | wc -l   # → 61 вид события
git grep -n 'CREATE TABLE kaname.audit_outbox' origin/367 -- internal/migrations/0001_initial.sql  # → :1716
for e in <23 вида перечня ниже>; do git grep -hoE "\"iam\.$e\"" origin/367 -- '*.go' ':!*_test.go' | wc -l; done
#   → у каждого из 23 видов ≥ 1 (видов с нулём — 0)
```

Из обязательного набора Д9 в аудите есть: `access_binding.granted/revoked`,
`cluster_admin.granted/revoked`, `user.removed_from_account`, `sa_key.issued`,
`user_token.issued`, `user.blocked`, `service_account.disabled`, `account.deleted`,
`project.deleted`, `session.all_revoked`, `session.force_logout`, `user.password_changed`,
`user.second_factor_enrolled/removed/reset`, `user.backup_codes_regenerated`,
`access_key.registered/revoked/transferred`, `user.recovery_completed`, `session.issued`.

Нет трёх: события приглашения (приглашение и так ставит письмо своим глаголом), признака «новое
устройство» у `session.issued` и события смены адреса.

Производители видов, на которые пробы NTF2-90 и NTF2-89 опираются:

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca · единица — место вызова вне объявления константы
git grep -n 'AuditSecondFactorRemoved\|auditEventUserSecondFactorReset\|AuditAccessKeyRevoked\|eventSessionForceLogout' origin/367 -- '*.go' ':!*_test.go'
#   → humansession/sf_remove.go:144 (самостоятельное снятие фактора) · user/reset_second_factor.go:190
#     (сброс распорядителем, UserService/ResetSecondFactor) · access_keys/revoke.go:173 (снятие ключа
#     входа) · internal_iam/force_logout.go:531 (InternalIAMService.ForceLogout) — у каждого есть глагол
git grep -n 'AuditAccessKeyTransferred' origin/367 -- '*.go'
#   → 1 строка: internal/apps/kaname/api/access_keys/audit.go:25 — объявление; вызова нет
```

Вид `access_key.transferred` объявлен, но глагола переноса ключа в дереве нет. Держатель этого
вида — NTF2-89 (карта «вид → шаблон → правило адресата» и проба писателя аудита), а не глагол.

### §1.3 Глагола смены адреса нет

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca
git grep -hoE '"iam\.user\.email[a-z_]*"' origin/367 -- '*.go' ':!*_test.go'   # → "iam.user.email_verified" — и только
git show origin/367:internal/check/people_address_writers.go | grep -n 'глагол смены адреса вносится только вместе'
#   → :23 (на origin/357 — :20): гейт держит «мест, где непроверочный код пишет адрес в СУЩЕСТВУЮЩУЮ
#     строку человека, — ноль»; находка называет, с чем вместе глагол вносится (`addressWriterFinding`)
```

У пользователя один адрес: колонка `kaname.users.email` с отметкой `email_verified_at`, которую база
снимает при смене значения (`20260915111233_login_methods_live_in_their_own_rows.sql:96-125`).

### §1.4 Полоса формы: пути и регистрация

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca
git grep -hoE '"/iam/v1/auth/[a-z0-9/_:-]+"' origin/367 -- 'internal/handler/loginlanehttp/*.go' ':!*_test.go' | sort -u
#   → 15 путей: csrf · login · logout · password · recovery · recovery/complete · register · second-factor (5) · step-up · verify-email · verify-email/confirm
# ДОМ: PRO-Robotech/kacho @96e2fa72b3a (origin/2798) — край
git grep -hoE '"/iam/v1/auth/[a-z0-9/_:-]*"' origin/2798 -- gateway/internal/middleware/login_lane_paths.go | sort -u | wc -l
#   → 15, те же пути (на origin/2564 — те же 15); `register/confirm` — 0 и у kaname, и у края
```

Регистрация сегодня — контракт Ф4 (приёмка kaname `registration-and-its-three-consequences.md`,
Ф4-01, Ф4-11, Ф4-12). NTF-2 заменяет его (§3, Р9).

### §1.5 Звенья, на которых стоит решение Д2 и Д3

```
# ДОМ: PRO-Robotech/kaname @caf1c95ca — подписка у kaname есть
git grep -l 'corelib/subscription' origin/367 -- '*.go' ':!*_test.go'
#   → 6 файлов: cmd/kaname/grpc_register.go · cmd/kaname/subscription_wiring.go ·
#     internal/repo/kaname/pg/subject_change_{repo,retention}.go · internal/restfront/registration.go ·
#     internal/subscriptionjournal/journal.go
# ДОМ: PRO-Robotech/kaname — что судит TestMRW07
git show origin/367:internal/servicemanifest/seed_form_test.go | grep -n 'func TestMRW07\|ServiceAccounts) != 0'
#   → :90 объявление, :98 проверка: судит ВСТРОЕННЫЙ манифест kaname — `seed.serviceAccounts` и
#     `seed.joins` пусты («своей служебной записи у службы не бывает»); о типах модели он не утверждает ничего
git show origin/367:internal/servicemanifest/manifest.embedded.yaml | grep -n 'служебной записи'   # → :67
# ДОМ: PRO-Robotech/corelib @cfe49ef00fa (origin/26) — подписка требует субъекта арендатора
git show origin/26:subscription/server.go | grep -n 'subscription requires an authenticated caller'   # → :233
```

Вывод для Р1. Машинно TestMRW07 судит только подразделы `seed.serviceAccounts` и `seed.joins`, но
держит решение MRW-1 Р1, которое его сообщение называет основанием: «своей служебной записи у службы
доступа не бывает» (`internal/servicemanifest/manifest.embedded.yaml`, строки 66–67). Служебный
принципал `service:kaname` был бы именно такой записью, как бы он ни заводился — строкой посева или
типом модели. Поэтому действует запасной путь Д2: лента kaname авторизуется закрытым перечнем
источников `notify` и сертификатом, записанным исключением. Этот путь выбрала одобренная приёмка
NTF-1 (Р3, §1.5, NTF1-F21, NTF1-G22), владелец механизма; NTF-2 его не оспаривает, а применяет
(Р1). Прежняя редакция делала обратный вывод из того же замера, и две одобренные приёмки
утверждали взаимоисключающее о субъекте ленты kaname — это снято здесь.

### §1.6 Рендер установки: держатели секрета и адреса почтового узла

Цепочки объявлены в `deploy/stacks.txt`, их **7**: dev, dev-prod, prod, own, fe3455, prorobotech,
a8f60d. Единица — объект рендера (`kind/name`).

```
# ДОМ: PRO-Robotech/kacho @96e2fa72b3a, каталог deploy/helm/umbrella; локальные подчарты
# (`file://../../../…` в Chart.yaml) — из того же дерева, затем `helm dependency build .`; helm v4.2.4
grep -v '^#' ../../stacks.txt | grep -v '^$' | while IFS=: read n c; do
  a="-f values.yaml"; for f in ${c//,/ }; do a="$a -f $f"; done
  helm template r . $a > chain-$n.yaml; done
# посадка края: значение KACHO_API_GATEWAY_IDENTITY_PROVIDER; ручка полосы формы — число
#   KACHO_API_GATEWAY_IAM_LOGIN_LANE_URL; рабочие объекты поставщика — Deployment/StatefulSet/Job
#   с `# Source:` под charts/{kratos,hydra,pg-kratos,pg-hydra,identity-selfservice-ui}/;
# держатель секрета: переменная окружения с valueFrom.secretKeyRef на удостоверение почты
#   (KANAME_INVITE_MAIL_PASSWORD, KANAME_IDENTITY_SMTP_CREDENTIAL) либо на ключ smtpConnectionURI;
# адрес узла: ConfigMap с ключом `relay:` в блоке `invite-mail`
```

| цепочка | объектов обхода | посадка края | ручка полосы формы | рабочих объектов поставщика | держателей секрета | адрес узла в |
|---|---|---|---|---|---|---|
| dev | 203 | own | 1 | 0 | 0 | ConfigMap `kaname-config` |
| dev-prod | 217 | own | 1 | 0 | 0 | ConfigMap `kaname-config` |
| prod | 186 | own | 1 | 0 | 0 | — |
| own | 219 | own | 1 | 0 | 0 | ConfigMap `kaname-config` |
| fe3455 | 137 | own | 1 | 0 | 0 | — |
| prorobotech | 216 | own | 1 | 0 | 0 | ConfigMap `kaname-config` |
| a8f60d | 146 | own | 1 | 0 | 1 — Deployment `kaname` | ConfigMap `kaname-config` |

Замер @`96e2fa72b3a` совпал поштучно с замером редакции 13 @`6edea09c2ee`: волна-4 переименовала
файлы поставщика (`kacho#2759`), но рендера цепочек по этим столбцам не изменила.

- Приёмник писем стенда отрендерен в 5 цепочках (dev, dev-prod, own, prorobotech, a8f60d).
- Службы `notify` в дереве kacho нет: `git ls-tree -d origin/2798 services/notify | wc -l` → 0; её
  заводит NTF-1.
- Поставщик не поднимается ни в одной цепочке: выключение объявлено в базе зонтика, раздел «ЧУЖОЙ
  СТЕК ЛИЧНОСТИ НЕ ПОДНИМАЕТСЯ НИ НА ОДНОМ СТЕНДЕ» (`deploy/helm/umbrella/values.yaml:749`, ключ
  `kratos.enabled: false` — `:767-768`). Согласие посадки и флагов держит существующий гейт
  `TestOwnPostureRaisesNoForeignIdentityService` (`deploy/own_posture_foreign_identity_test.go:347`).

### §1.7 Почта поставщика в дереве остаётся — предмет `kacho#1276`

Снятие почты поставщика личности NTF-2 не делает (Д39): его делает релиз identity-own, `kacho#1276`
(подчарты `kratos` и `hydra`, волна-4 `kacho#2798`). На базе он не влит:

```
# ДОМ: PRO-Robotech/kacho @96e2fa72b3a
git log --oneline origin/2798 | grep -c '#1276'                                        # → 0
git ls-tree --name-only origin/2798 deploy/helm/umbrella/charts/ | grep -cE '^.*/(kratos|hydra)-'   # → 2 (архивы подчартов)
git grep -cE 'courier|smtpConnectionURI|KANAME_IDENTITY_SMTP_CREDENTIAL' origin/2798 -- \
  deploy/helm/umbrella/charts/kaname/templates/_identity-provider.tpl                  # → 6 строк
# прежнее имя файла `_kratos-identity.tpl` снято волной-4 (`kacho#2759`): на 2798 его нет
```

Отсюда одно следствие для S7. При повторном включении поставщика набором ручек, которым дерево
поднимает его в своих пробах (`IDENTITY_STORE_UP_ARGS`, `deploy/tests/helm/provider-up.sh:53-55`),
рендер получает держателей секрета почты у поставщика:

```
# тот же рендер §1.6 плюс --set kratos.enabled=true --set kaname.kratos.config.enabled=true
#   --set kaname.kratos.identitySchema.enabled=true
#   dev    → держателей 2: Deployment `r-kratos`, StatefulSet `r-kratos-courier` (ключ smtpConnectionURI)
#   a8f60d → держателей 3: те же два и Deployment `kaname`
```

Этот вход — предмет `kacho#1276`; гейт S7 судит рендер цепочек `deploy/stacks.txt`, где поставщик
выключен (§1.6), поэтому до `kacho#1276` предикат §0 на цепочках выполним. Полоса, правящая страж
почты, всё же садится после вливания `kacho#1276`: шаблон стража называет шаг подстановки
поставщика — `kacho.identity.configRenderInitContainer` в `_identity-provider.tpl` (шапка, :11) и в
тексте отказа (:134), — и этот шаг снимает `kacho#1276`; один файл двух задач правится в порядке
вливания (Р16 п.4, Д40).

### §1.8 (снят редакцией 14)

Прежний §1.8 — источники конфигурации процесса поставщика — служил сценариям снятия почты поставщика
и ушёл с ними в `kacho#1276` (Д39).

### §1.9 Перепись файлов дерева kacho, задевающих предмет

```
# ДОМ: PRO-Robotech/kacho @96e2fa72b3a · единица — отслеживаемый файл под deploy/, кроме *.md
W='courier|COURIER_|statefulSet|smtpConnectionURI|KANAME_IDENTITY_SMTP_CREDENTIAL|mailCred|show_verification_ui|require_verified_address|flows\.recovery|flows\.verification|"recovery"|"verification"|hookRecoveryPayload|recovery-payload|hooks/recovery|kacho-mail-anchor|ВЫКЛЮЧЕНЫ|ВКЛЮЧЕНЫ|methods\.code|MAIL-[0-9]+'
K='invite-mail|inviteMail|KANAME_INVITE_MAIL|kaname-mail-anchor|kaname-mail-credential'
{ LC_ALL=C git grep -lE "$W|$K" origin/2798 -- deploy ':!*.md' | sed 's|^origin/2798:||'
  git ls-tree -r --name-only origin/2798 deploy | grep -iE 'mail|courier|identity_method' | grep -v '\.md$'; } | LC_ALL=C sort -u | wc -l
#   → 49  (только по W — 46; на origin/2564 — те же 49 и 46)
# разность списков 2564 → 2798 — четыре переименования `kacho#2759`, файлов не прибавилось и не убыло:
#   _kratos-identity.tpl → _identity-provider.tpl · kratos-config-configmap.yaml → identity-provider-config-configmap.yaml
#   kratos-hooks-configmap.yaml → identity-provider-hooks-configmap.yaml · values.fe3455-ory-posture.yaml → values.fe3455-identity-posture.yaml
```

Слово `W` — предмет прежней редакции (почта поставщика); после Д39 перепись по нему остаётся, чтобы
исход каждого из 49 файлов был назван, а не выпал: у файлов почты поставщика исход — «за
`kacho#1276`». Таблица исходов — §3а.

### §1.10 Объявление удостоверения почты одно; страж видит только объявления

```
# ДОМ: PRO-Robotech/kacho @96e2fa72b3a (origin/2798); на origin/2564 — те же числа
git grep -l 'identity).smtp' origin/2798 -- 'deploy/helm/**/templates/*'
#   → 4: charts/kaname/templates/{deployment.yaml,configmap.yaml,_identity-provider.tpl} ·
#     templates/identity-mail-lane-guard.yaml — все читают один узел `global.kacho.identity.smtp`;
#     своего ключа удостоверения почты у подчарта нет (ссылка `secretKeyRef` у Deployment `kaname` —
#     deployment.yaml, `$mailNode.credentialSecret` того же узла)
git grep -lE '\bfail\b.*credentialSecret' origin/2798 -- 'deploy/helm/**/templates/*' | wc -l
#   → 1: identity-mail-lane-guard.yaml (строк с таким `fail` в нём 6)
git show origin/2798:deploy/helm/umbrella/templates/identity-mail-lane-guard.yaml | grep -cE '\b(include|lookup|tpl)\b'
#   → 3: `tpl` над значением адреса (:60) и `include "kacho.mailReceiver.fullname"` (:219) — манифестов
#     других объектов страж не читает
```

Вывод для Р19. Какой объект монтирует удостоверение, решает шаблон этого объекта, а не объявление:
объявление у удостоверения одно, и после NTF-2 (читатель kaname снят, читатель — чарт `notify`
заведён, Р20) и `kacho#1276` (читатели поставщика сняты) ни одно значение установки не отдаёт ссылку
объекту, отличному от отправителя `notify`. Вывод держится только при названном читателе: чарт
`notify` одобренной NTF-1 этого узла не называет (`grep -cE 'global\.kacho\.identity\.smtp|credentialSecret'
docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md` → 0 @`29cfa368…`; NTF1-I06 даёт
чарту собственные значения), поэтому чтение узла чартом `notify` проводит NTF-2 (Р20, NTF2-34). Условие «только у отправителя», поставленное в страж, судило бы вход, которого нет, —
его судит гейт над рендером (NTF2-30, NTF2-31 (а), (б), (д)).

---

## §2 Решения

Решения диспетчера по эпику приняты; здесь перенесены те, что относятся к предмету NTF-2, с
основанием в требованиях владельца. Решения автора помечены. Числа лимитов — поставляемые значения
установки с границами (Р15); в документе — ручка, граница и ориентир.

### §2.0 Требования владельца, на которые опираются решения (дословно, 2026-09-29/30)

- **В1:** «единая точка у кого есть креды от почты»
- **В2:** «простой формат добавления шаблонов»
- **В3:** «права доступа сервисов к их шаблонам (не должно быть возможности где сервис А может
  отправлять нотификации от сервиса Б)»
- **В4:** «html + css и набор атрибутов»; «Общий макет + блоки»
- **В-без:** «Акцент на максимальную безопасность … на максимальную простоту … и должна быть
  максимально простая поддержка.»
- **В-шлюз:** «канаме использует шлюз для отправки нотификации, но шлюз проверяет доступы у канаме»
- **В-реакт:** «нотификатор должен подписываться на события нотификации каждого модуля для рективной
  обработки»
- **В-прод:** «прода нет так что можно перестраивать все подряд»
- **В-спам:** «заложи вопрос с рейтлимитами и защиту против спама. Например кейс что кто-то вводит на
  восстановление логин не свой и спамит владельца почты.»
- **В-флаг:** «забудь про кастомные. Заложи только флаги на приклад генерить почтовые запросы в
  аутбокс или нет. Что бы если нет шлюза не генерить нагрузку»
- **В-цель:** «Перспективность, максимальная безопасность, поддреживаемость»
- **В-реш:** «все решения принимаешь ты с учетом требований на входе»

### Р1. kaname — источник ленты `notification_feed:kaname` (Д1–Д4, Д6)

- Каждое письмо личности kaname ставит сгенерированной функцией `corelib notify/feed` в **той же
  транзакции**, что и событие: глагол (приглашение, запрос кода, регистрация) либо строку аудита
  (класс S). Отдельной очереди писем у kaname нет.
- Сигнал `notify` — событие вида «нотификация» существующей подписки kaname с объектом
  `notification_feed:kaname`; событие несёт только идентификатор строки (Д3). Тело с зашифрованным
  секретом `notify` забирает вызовом `Claim`/`Ack` ленты, доступным только `service:notify`.
- **Право на отправку пространства `kaname` — записанное исключение Д2, принятое NTF-1 (Р3):**
  служебного принципала `service:kaname` нет (решение MRW-1 Р1 не замещается, §1.5), строки
  «`service:kaname` sender на `notification_namespace:kaname`» нет. Запись перечня источников
  `notify` для `kaname` несёт `authorization: certificate`: `notify` принимает ленту kaname, только
  если её сервер предъявил точный SAN из декларации `kaname.spiffe`, и решение на письмо
  (`ResolveSend`) по пространству `kaname` не зовёт. Сервер ленты с другим SAN — подключение
  отвергнуто, `Claim` не вызван, тревога `source_identity_mismatch` (NTF2-06).
- Манифест kaname несёт в разделе `notifications` только `readers: [notify]`, без `namespace`:
  это выдаёт ровно `service:notify reader notification_feed:kaname` и субъекта kaname не заводит;
  манифест с `namespace` отвергает валидатор NTF-1 (NTF2-47).
- Рычаг оператора по письмам kaname — флаг почты Р4, а не отзыв права: отзыва по пространству
  `kaname` нет (NTF-1 Р3). Пространство имён шаблона — чья лента; поля «чей шаблон» в строке нет.
- Тип `notification_feed:kaname` входит в закрытый перечень типов, на которые надзор администратора
  облака не распространяется, на всех путях, где надзор спрашивается (Д14): тело ленты с секретом не
  читает никто, кроме `service:notify`. Перечень и его держатель заводит NTF-1; лента kaname входит в
  него по построению — перечень называет тип `notification_feed` целиком, а не ленты по модулям.
- **Основание:** В1 (кредов у kaname нет), В3 (чей шаблон — решает лента; ленту kaname отдаёт
  только сервер с её сертификатом), В-шлюз (права решает kaname; служба доступа не спрашивает сама
  себя — поэтому её пространство авторизуется сертификатом, NTF-1 Р3), В-реакт (сигнал — подписка),
  В-без (один механизм подписки и ленты на всех источников).

### Р2. Собственная почта kaname снимается целиком (Д1, Д12)

- Из kaname снимаются: отправитель (`internal/clients/invite_mail.go` и его проводка), 10 ручек
  `invite-mail.*`, креды и якорь сертификата узла в поставке, очередь `kaname.invite_mail_outbox`
  (новой миграцией; применённые миграции не правятся, ban #5), метрики отправителя.
- Гейт MAIL-47 (`internal/check/mail_send_paths.go`, перечень `OurMailKinds`) замещается двумя
  гейтами: «отправителей SMTP в kaname 0» (NTF2-44) и «виды писем kaname = шаблоны kaname» (NTF2-45).
- Ключ почтового узла в конфигурации kaname после NTF-2 — неизвестный ключ, отказ старта
  (NTF2-48): принятое и проигнорированное запрещено (`.claude/rules/api-conventions.md`
  §«Принято-и-проигнорировано — ЗАПРЕЩЕНО»).
- **Основание:** В1, В-прод (строки очереди в полёте не переносятся: прода нет).

### Р3. Шаблоны kaname — закрытый перечень (Д5)

Шаблоны лежат в дереве kaname: `notifications/<name>/{notification.yaml, body.ru.yaml}`; тело —
только блоки; макет, рендер и эталоны `.eml` — в `notify`; в сборку `notify` шаблоны попадают шагом
`make -C services/notify bundle` при подъёме пина kaname. Перечень шаблонов kaname после NTF-2:

| шаблон | класс | повод | адресат (Р11) |
|---|---|---|---|
| `invite` | security | глагол приглашения | приглашённый адрес |
| `recovery` | security | запрос кода восстановления | хранимый адрес учётки |
| `verification` | security | запрос кода подтверждения | хранимый адрес учётки |
| `registration` | security | регистрация на свободный адрес | введённый адрес |
| `registration-existing` | security | регистрация на занятый адрес | хранимый адрес учётки |
| `mail-throttled` | security | исход `capped` окна `recovery`, не чаще `mail-throttled-interval` (Р6) | хранимый адрес учётки |
| `recovery-completed` | security | аудит `user.recovery_completed` | подтверждённые адреса субъекта |
| `new-device-login` | security | аудит `session.issued` пути входа без действующей метки устройства (Р12) | субъект |
| `password-changed` | security | `user.password_changed` | субъект |
| `second-factor-changed` | security | `user.second_factor_enrolled/removed/reset` | субъект |
| `backup-codes-regenerated` | security | `user.backup_codes_regenerated` | субъект |
| `access-key-changed` | security | `access_key.registered/revoked/transferred` | владелец ключа до и после события |
| `sessions-revoked` | security | `session.all_revoked`, `session.force_logout` | субъект |
| `role-granted` · `role-revoked` | security | `access_binding.granted/revoked` | субъект-пользователь; иначе контакт безопасности области |
| `cluster-admin-granted` · `cluster-admin-revoked` | security | `cluster_admin.granted/revoked` | все администраторы облака и субъект |
| `removed-from-account` | security | `user.removed_from_account` | исключённый и контакт безопасности аккаунта |
| `sa-key-issued` | security | `sa_key.issued` | контакт безопасности аккаунта сервисного аккаунта |
| `user-token-issued` | security | `user_token.issued` | владелец токена |
| `user-blocked` | security | `user.blocked` | администраторы облака — блокировка действует на личность во всей установке (право `identity_suspender` на `iam_user`) |
| `service-account-disabled` | security | `service_account.disabled` | контакт безопасности аккаунта |
| `account-deleted` · `project-deleted` | security | `account.deleted`, `project.deleted` | владельцы аккаунта на момент события |

- Все шаблоны класса `security` объявляют раздел `limits`; шаблон класса `security` без `limits` —
  красная сборка (NTF2-08). Отписки у класса `security` нет (Д9).
- **Перечень записан в дереве kaname одним файлом** — `notifications/required-security.yaml`: 24 имени
  шаблонов этой таблицы. Файл — не производное от шаблонов: гейт kaname «обязательный класс» читает
  его и `notifications/*/notification.yaml` и красен, если имя перечня объявлено не классом `security`,
  если шаблона с таким именем нет или если перечень пуст (NTF2-99). Сверку файла с этой таблицей
  держит DoD п.1.
- **Карта «вид аудита → шаблон → правило адресата»** — одна, в дереве kaname; по ней писатель аудита
  ставит строки ленты. В ней 23 вида аудита этой таблицы, и `access_key.transferred` среди них, хотя
  глагола переноса ещё нет (§1.2): правило адресата «владелец ключа до и после события» записано в
  карте, и первый глагол, пишущий этот вид, получает письмо без правки карты (NTF2-89).
- В письмах класса S нет пользовательского текста (Д9): ни имени ресурса, ни `display_name`, ни
  имени роли или аккаунта. Письмо несёт идентификаторы, время, факт и ссылку в консоль — путь из
  шаблона, origin из конфигурации установки (Д5). Приглашающий показан своим **подтверждённым
  адресом**, а не именем.
- В письме `recovery` есть фраза «Если это были не вы — ничего не делайте»; ссылки «это не я» нет
  (Д11).
- **Основание:** В2 (добавить письмо — каталог и строка вызова), В4 (макет и блоки), В-без
  (доверенный отправитель не несёт чужого текста).

### Р4. Флаг почты kaname — явный, без умолчания (Д7)

- Ручка kaname `notifications.enabled`. В зонтике kacho она выводится из
  `global.kacho.notifications.enabled` с переопределением `kaname.notifications.enabled`; из того же
  объявления выводится перечень источников `notify` — рассинхрон невозможен (NTF2-53).
- Не задан — kaname не стартует и называет ключ (NTF2-50). Самостоятельная поставка kaname требует
  ручку так же (NTF2-33).
- **Выключен:** строк в ленте kaname 0; сервер ленты не поднимается; `notify` kaname не опрашивает;
  схема базы от флага не зависит. Действия, которым нужна почта, — запрос кода восстановления,
  регистрация, приглашение по почте, запрос кода подтверждения — получают явный синхронный отказ
  `FAILED_PRECONDITION` (HTTP `400`, `code` `9`), текст `email delivery is not configured in this
  installation`, `ErrorInfo{reason: NOTIFICATION_DELIVERY_NOT_CONFIGURED}` — единый отказ corelib
  `feed.DeliveryNotConfiguredStatus()`, объявленный NTF-1 (Р9, NTF1-N06); своего текста и своего
  `reason` у kaname нет. Держателей два, и каждый ловит своё: гейт дерева kaname NTF2-54 — литералов
  текста и `reason` отказа в не-тестовом дереве 0, каждое действие перечня достигает ссылки на эту
  функцию, копия литерала — красный; NTF2-51 сверяет ответ с полями, которые функция возвращает на пине
  corelib, — расхождение текста corelib и kaname красно, хотя копию она сама не видит. Отказ
  **одинаковый для любого адреса**: у каждого действия,
  принимающего адрес, ответ на адрес с учётной записью и на адрес без неё побайтово один
  (NTF2-51: восстановление — (а, б), регистрация — (в, ж), приглашение — (г, з)). Письма аудита (класс S) при выключенном флаге не порождаются, а сами действия
  исполняются.
- **Толкование Д7 (решение автора; спор — строкой возврата, не молчаливым отступлением).** Д7
  требует «письма класса security при выключенном флаге не глотаются» и называет действия, которым
  отказывают: восстановление, приглашение по почте, подтверждение адреса. У этих действий письмо —
  **сам продукт**: без письма действие бессмысленно, и отказ честнее тихого успеха. Письмо класса S
  из аудита — **извещение о совершённом действии**, продукт которого другой (снятая роль,
  заблокированный человек, сменённый пароль). Отказывать таким действиям в установке без почты
  значило бы запретить в ней блокировку и отзыв прав — то есть ослабить защиту ради письма, которое
  всё равно не может уйти. Поэтому отказ получает только перечень действий Д7 (NTF2-51), а действия
  класса S исполняются без строки ленты (NTF2-52). Что установка работает без извещений, видно
  метрикой `kaname_notifications_enabled = 0` и объявлено на странице поставки (DoD п.22).
- Метрика состояния `kaname_notifications_enabled` — `1` или `0` (NTF2-52).
- **Установка без почты.** Подтвердить адрес без письма нельзя: второго пути подтверждения, не
  доказывающего владения адресом, не вводится. Установка с выключенным флагом обслуживает машинных
  субъектов и людей с уже подтверждёнными адресами; это её объявленное свойство, а не тихий сбой.
  Установка без почтового узла выключает флаг (Д44): флаг `true` при пустом узле — отказ старта
  отправителя `notify`, а не молчаливая лента без доставки (Р20).
- **Основание:** В-флаг (не генерить нагрузку без шлюза), В-без (отказ явный и не раскрывает
  существование адреса), `.claude/rules/security.md` §«Production-mode» (`sec-issuance-four-knobs-bootguard`:
  незаданное — отказ пуска, а не разумное умолчание).

### Р5. Край: лимит по источнику и proof-of-work для анонимных почтовых глаголов (Д11)

- Звено-ограничитель стоит в HTTP-цепочке края **перед** ретрансляцией полосы формы и действует
  только на анонимные почтовые глаголы — пути, которые ставят письмо на адрес из тела запроса:
  `POST /iam/v1/auth/recovery` и `POST /iam/v1/auth/register`. Прочие пути полосы и платформы, в том
  числе пути предъявления кода `recovery/complete` и `register/confirm`, он не трогает (NTF2-63).
- **Почему пути предъявления кода вне ограничителя края (решение автора).** Д11 ставит край «только
  для анонимных почтовых глаголов»; путь предъявления кода письма не ставит. Перебор кода на обоих
  анонимных путях предъявления держат оси kaname, точные и одинаковые для обоих путей (Р6, NTF2-66):
  они знают адрес, которого край не знает. Прежняя редакция включала `register/confirm` в перечень, а
  `recovery/complete` нет; различие не имело основания и снято.
- Ключи: адрес источника (IPv4 `/32`, IPv6 `/64`) и подсети (IPv4 `/24`; IPv6 `/56` и `/48`).
  Адрес источника — адрес на **доверенной глубине** цепочки пересланных адресов; число доверенных
  прыжков задаёт профиль (страж старта). Значения цепочки дальше доверенной глубины на ключ не
  влияют: запросы с одним адресом на доверенной глубине — один источник, с разными — разные (NTF2-79).
- **Счёт ключа** — число запросов, которые звено **пропустило** к kaname в окне ручки (без вызова или
  с верным доказательством). Ответ-вызов и ответ `429` в счёт не входят: запрос, получивший вызов и
  повторённый с доказательством, считается один раз — когда пропущен.
- **Окно ручки** `X` — скользящий интервал `(t − W_X, t]`, где `W_X` — длина окна ручки (Р8): запрос,
  пропущенный в момент `t1`, входит в счёт по `t1 + W_X − 1 с` включительно и выходит из него в
  `t1 + W_X` (NTF2-60 (в), NTF2-61 (г)).
- **Лестница источника — три ступени, и каждую задаёт своя ручка.** Пусть `c(X)` — счёт ключа
  источника к приходу запроса в окне ручки `X` (у `FREE`, `POW`, `HARD` окна свои, Р8); ступени
  проверяются сверху вниз:
  - `c(HARD) ≥ HARD` — `429` `RATE_LIMITED` с `Retry-After`; вызова нет, доказательство не принимается;
  - иначе `c(POW) ≥ POW` — вызов со сложностью **повышенной** ступени: `difficultyBits` =
    `POW_BITS_HIGH`, строго больше базовой (граница стража, Р8);
  - иначе `c(FREE) ≥ FREE` — вызов со сложностью **базовой** ступени: `difficultyBits` = `POW_BITS_BASE`;
  - иначе запрос проходит без вызова.

  Порог `POW` меняет только сложность вызова; вызов, выданный по оси подсети или по общему потоку при
  счёте источника ниже `POW`, несёт базовую сложность (NTF2-60, NTF2-61, NTF2-74).
- При превышении общего потока (скорость и всплеск по всем источникам вместе) вызов PoW получают все
  запросы без доказательства сверх него, включая запросы источников ниже их собственного порога;
  верное доказательство такой запрос пропускает (NTF2-74).
- **Своя proof-of-work, без сторонней капчи.** Вызов — ответ `429`, `code` `8`, текст
  `proof of work required`, `ErrorInfo{reason: PROOF_OF_WORK_REQUIRED, metadata: {challenge,
  difficultyBits, expiresAt}}`. Клиент находит `nonce`, при котором SHA-256 от
  `challenge + ":" + nonce` имеет не меньше `difficultyBits` ведущих нулевых битов, и повторяет
  запрос с заголовком `X-Kacho-Proof: <challenge>:<nonce>`. Вызов подписан краем, одноразовый и
  ограничен сроком. Решение проверяется краем без обращения к kaname.
- Жёсткий отказ — `429`, `code` `8`, текст `too many requests`, `ErrorInfo{reason: RATE_LIMITED}`,
  заголовок `Retry-After` в секундах.
- Ответ края **не зависит от адресата**: ключи — только источник и подсеть.
- **Хранилище ограничителя недоступно — свой исход, отказ, а не пропуск.** Если звено не может
  прочитать или записать счёт ключа (хранилище не отвечает, запрос к нему не исполнен, ожидание
  ключа дольше предела звена), ответ — `503`, `code` `14`, текст `request limiter is unavailable`,
  тело — форма собственных статусов края `{code, message, details}` с пустым `details`; ответ
  одинаков для любого адреса (тело запроса звено не читает) и для обоих путей; до kaname запрос не
  доходит. Проверка одноразовости доказательства при недоступном хранилище — тот же `503`:
  доказательство, которое не удалось проверить, свежим не считается. Ветки «не смог спросить —
  пропустить» нет (fail-closed); каждый такой ответ считает метрика края
  `kacho_api_gateway_anon_mail_store_unavailable_total` (NTF2-59).
- **Ось источника анонимных почтовых глаголов — только у края.** Собственный предел kaname по
  источнику на `register` и запрос восстановления — окно обращений по источнику, заведённое
  `kaname#456`, — снимается: два предела одной оси с разными ключами расходились бы молча. Замещение
  названо в §3. Ручки `authn.login.source-{attempts,window}` остаются за окном неверных предъявлений
  пароля при входе, предмет которого NTF-2 не меняет. Держатель — NTF2-60 (а): все `H` запросов,
  пропущенных краем с одного источника, доходят до kaname и получают `200 {}`.
- Консоль решает вызов прозрачно на экранах восстановления и регистрации (NTF2-72).
- **Консоль на `503` и на исчерпанный бюджет решателя (решение автора).** Консоль показывает
  `message` отказа дословно (канон консоли: своего текста отказа у экрана нет). На `503` звена
  решатель не запускается и запрос не повторяется: экран показывает `request limiter is unavailable`,
  форма остаётся редактируемой. У решателя свой бюджет поиска `Bs` — константа консоли, меньше срока
  вызова; бюджет исчерпан — исход `expired`: запрос с доказательством не отправляется, решатель
  остановлен, экран показывает `message` последнего ответа края (`proof of work required`), форма
  редактируема, следующая отправка идёт без доказательства и получает новый вызов (NTF2-58).
- **Основание:** В-спам (первый рубеж против серии запросов с одного источника), В-без (своя PoW —
  никакого стороннего сервиса на пути входа). Закрывает предмет `kacho#2700` (Р17).

### Р6. kaname: точный рубеж на адресата, повтор того же кода и «пол» (Д11)

- Ключ окна — пара (адрес, назначение); что считается адресом, решает назначение:

  | назначение | адрес ключа | строка счётчика для адреса без учётной записи |
  |---|---|---|
  | `recovery` | хранимый адрес учётки (свёртка ключом службы) | **не заводится**: письма некуда и незачем слать (NTF2-64) |
  | `verification` | хранимый адрес учётки; вызывающий — сессия её владельца | не бывает: адрес есть по построению |
  | `registration` | нормализованный ввод: нижний регистр, локальная часть без `+метки`, домен в A-label нижнего регистра | **заводится** для любого введённого адреса, свободного или занятого: одна строка считает письма `registration` и `registration-existing`, и прогрессия писем для свободного и занятого адреса одинакова (NTF2-75) |

  Приглашение считает адресата в потолках Р7 по тому же нормализованному вводу.
- Счётчик ведётся CAS в транзакции постановки письма (Д6: точный счётчик ленты).
- **Пока код жив, повторный запрос шлёт тот же код** — новое письмо с тем же значением; живой код
  владельца чужой запрос не гасит. Новый код чеканится только после истечения прежнего. Для
  `registration` «тот же» значит «той же ожидающей записи»: повтор с **тем же** паролем шлёт код этой
  записи; повтор с **другим** паролем заводит вторую ожидающую запись со своим кодом, прежняя живёт
  дальше (Р9, NTF2-86). Оба письма идут в одном окне адреса: запись заводится только вместе с
  письмом, которое окно пропустило, поэтому число живых записей адреса не больше числа писем окна.
- Прогрессия: номер письма прогрессии — число писем прогрессии в часовом окне к приходу запроса плюс
  один. Первое (часовое окно пусто) — сразу; второе — не раньше `first-pause` от прошлого письма
  прогрессии; третье и каждое следующее — не раньше `second-pause` от прошлого письма прогрессии; затем
  часовой и суточный потолки. Паузы отсчитываются только от писем прогрессии: письма пола, запаса
  доверенного устройства и о торможении паузы не открывают. Лимит никогда не отрезает владельца
  полностью: после суточного потолка действует **пол**.
- **Пол при скользящих окнах — одно правило (решение автора, редакция 11).** Суточное окно
  **исчерпано** в момент `t`, когда в `(t − 1 сут, t]` окно пропустило `per-day` писем прогрессии.
  - `Tc` — момент письма прогрессии, которым окно исчерпано в **текущий** раз, то есть последнего
    письма прогрессии перед этим исчерпанием. Каждое новое исчерпание задаёт свой `Tc`.
  - `Tw` — момент, когда окно отпускает строку: самое раннее письмо прогрессии в `(Tc − 1 сут, Tc]`
    плюс 1 сут. Исчерпание длится `[Tc, Tw)`.
  - Пока окно исчерпано (`Tc ≤ t < Tw`), письмо ставит только пол. Первое письмо пола — в
    `Tc + floor-interval` и позже, каждое следующее — не раньше `floor-interval` от прошлого письма пола
    того же исчерпания; письмо пола ставится, только если его момент раньше `Tw`. Прочие запросы без
    метки устройства — `capped`. При `Tc + floor-interval ≥ Tw` пола в этом исчерпании нет.
  - С `Tw` прогрессия **возобновляется**: исход считается по номеру, паузам и часовому окну, как выше.
    Письмо, снова исчерпавшее суточное окно, задаёт новый `Tc` и новый `Tw`.
  - Письма пола разнесены не меньше чем на `floor-interval` и поперёк исчерпаний: письмо пола раньше
    `Tw`, а следующий `Tc` не раньше `Tw`. Отсюда за любые сутки писем пола не больше
    ⌈24 ч / `floor-interval`⌉, а писем окна — не больше `per-day` + ⌈24 ч / `floor-interval`⌉.
  - Базовый профиль (ориентиры Р8): ряд NTF2-64 с началом `t0` ставит письма прогрессии в `t0`,
    `t0 + 60 с`, `t0 + 6 мин`, `t0 + 1 ч`, `t0 + 1 ч 5 мин`; `Tc = t0 + 1 ч 5 мин`, `Tw = t0 + 1 сут`;
    письма пола — в `t0 + 7 ч 5 мин`, `t0 + 13 ч 5 мин`, `t0 + 19 ч 5 мин`; в `t0 + 1 сут` прогрессия
    возобновляется. На копии с `floor-interval` = 24 ч `Tc + 24 ч ≥ Tw`: пола в исчерпании нет, в
    `t0 + 1 сут − 1 с` исход `capped`, в `t0 + 1 сут` — письмо прогрессии.
- **Длительности — полуоткрытые интервалы (решение автора).** Каждый срок и каждое окно Р5–Р8
  отсчитывается от своего начала `t` и длится `[t, t + D)`: в `t + D − 1 с` — прежнее состояние, в
  `t + D` — уже новое. Часовой и суточный потолки считают письма, пропущенные прогрессией (исходы
  `queued`, `resent_same`), в скользящих окнах `(t − 1 ч, t]` и `(t − 1 сут, t]`; письма пола, запаса
  доверенного устройства и о торможении в эти окна не входят. Срок кода отсчитывается от постановки
  строки, которой код отчеканен; повтор того же кода срок не продлевает. Обе стороны каждой
  длительности утверждает её держатель (§6б, «длительность → обе стороны»).
- **Один исход на запрос, старшинство задано.** Если окно письмо не пропускает, исход — `capped`,
  когда исчерпан часовой или суточный потолок, и `cooldown` — только когда потолки не исчерпаны, а
  пауза от прошлого письма прогрессии не прошла. Пока суточное окно исчерпано (`[Tc, Tw)`), исход
  запроса без метки устройства — `capped`, кроме письма пола (NTF2-65). Письмо, пропущенное полом, имеет исход `floor` — несёт ли оно
  живой код (тот же) или новый (прежний истёк); исходы `queued` и `resent_same` — только для писем,
  пропущенных прогрессией вне исчерпания суточного окна.
- Сверх предела ответ **тот же** (`200 {}` побайтово), письма нет, исход виден метрикой
  `kaname_mail_intents_total{verb,outcome}` с закрытым набором исходов
  `queued|resent_same|cooldown|capped|floor|trusted_device|dropped_overload`: `trusted_device` —
  письмо восстановления, пропущенное запасом доверенного устройства сверх исчерпанного окна адреса
  (Р12, NTF2-70).
- **Запас доверенного устройства** — отдельный счёт по паре (адрес, метка): до
  `trusted-device.recovery-per-day` писем восстановления за сутки, без пауз окна адреса; письма запаса
  в окно адреса не входят. Сверх запаса исход считается по окну адреса (NTF2-70).
- Неверные предъявления код не гасят. Перебор кода держат оси kaname, одинаковые на всех путях
  предъявления: `recovery/complete`, `register/confirm` (анонимные) и `verify-email/confirm` (сессией
  владельца):
  - ось «адрес + источник»: сверх `address-source-per-window` неудач за `window` — отказ по частоте
    полосы формы, одинаковый для любого адреса;
  - потолок неудач по одному адресу `address-failure-ceiling`, действующий только для устройств без
    метки (Р12). Потолок считается в окне длиной `window`, отсчитанном от первой неудачи, и
    **истекает** с ним: по истечении окна устройство без метки снова предъявляет код (NTF2-66).

  Успешный вход, восстановление или подтверждение сбрасывает счёт.
- Ответ и **время ответа** одинаковы: чтение адреса и постановка идут вне пути ответа (NTF2-67).
- **Письмо «мы притормозили запросы» (`mail-throttled`) — один исход.** Повод — исход `capped` запроса
  окна `recovery` для адреса с учётной записью (часовой или суточный потолок — всё равно). Письмо
  ставится, если с прошлой строки `mail-throttled` на этот адрес прошло не меньше
  `mail-throttled-interval`, и не ставится иначе. Оно идёт **сверх** исчерпанного окна адреса: в окно
  адреса не входит, окна не расходует и окном не отсекается; его предел — только интервал. Исход
  запроса остаётся `capped`; строка `mail-throttled` в метрике исходов запроса не считается. В письме
  нет ссылок-действий. Для адреса, которого нет, писем нет (строки окна у него нет, Р6). Окна
  `verification` (вызывающий — сам владелец, отказ явный) и `registration` (адрес — ввод) письма о
  торможении не порождают (NTF2-68).
- **Письмо о торможении входит в инвариант сетки** `notify` (Р8, NTF2-73) слагаемым
  ⌈1 сут / `mail-throttled-interval`⌉ — одно письмо в сутки при границе интервала ≥ 1 сут.
- Для глагола `verify-email` (вызывающий — сессия самого владельца адреса) отказ по паузе и по
  потолкам остаётся явным — `429` `TOO_MANY_ATTEMPTS` с `Retry-After` (Ф6 EV-23, EV-24): он ничего не
  раскрывает о чужом адресе. Пол действует и здесь по тому же правилу: в исчерпании `[Tc, Tw)` запрос
  в момент пола проходит, с `Tw` прогрессия возобновляется (NTF2-76).
- **Основание:** В-спам (кейс владельца: чужой логин на восстановление — жертва получает ограниченное
  число писем, и в каждом рабочий код), В-без.

### Р7. Приглашения: потолки и содержимое (Д9, Д11)

- Приглашает только вошедший с подтверждённым адресом (рубеж Ф6).
- Потолок на аккаунт в сутки; у аккаунта моложе порога возраста — ниже. Превышение — явный
  синхронный отказ `429`, `code` `8`, текст `invitation limit of the account is exhausted`,
  `ErrorInfo{reason: INVITATION_RATE_LIMITED}`, `Retry-After`.
- Потолок на адресата: в час и в сутки от одного аккаунта и в сутки поперёк аккаунтов. Сверх него —
  молча: `Operation` успешна, строка приглашения заведена, письма нет, исход `capped` в метрике.
- Число висящих приглашений аккаунта ограничено `invite.pending-max`. Приглашение сверх него —
  явный синхронный отказ `400`, `code` `9`, текст `pending invitations limit of the account is
  reached`, `ErrorInfo{reason: INVITATION_PENDING_LIMIT}`; `Operation` не заводится. Отказ говорит о
  состоянии аккаунта вызывающего, а не об адресате, поэтому он явный.
- Срок приглашения — `invite.ttl`. Истёкшее приглашение не считается висящим: место в
  `pending-max` освобождается с истечением, без уборщика на пути запроса (NTF2-77).
- Потолки на адресата «в час» и «в сутки» считаются по паре (аккаунт, нормализованный адрес);
  «в сутки поперёк аккаунтов» — по адресу (NTF2-69, NTF2-77).
- Письмо приглашения без свободного текста: `display_name`, имя аккаунта и имя приглашающего в него
  не попадают (Р3).
- **Основание:** В-спам, В-без.

### Р8. Лимиты — поставляемые значения с границами (Д11)

Числа живут в поставляемых values установки; умолчаний в бинаре нет; страж старта проверяет
наличие и границы (NTF2-71). Ориентиры — значения базового профиля. Ключ таблицы — имя ручки
целиком; фигурные скобки раскрываются в отдельные ключи, и других ключей нет: край — 19
(источник 6, сложность 2, подсеть 8, общий поток 2, доверенные прыжки 1), kaname — 32 (окна адресата
15, сроки кода 3, перебор 3, письмо о торможении 1, приглашения 8, доверенное устройство 2); всего 51.

| ось | ручка | ориентир | граница, которую судит страж |
|---|---|---|---|
| край · источник | `KACHO_API_GATEWAY_ANON_MAIL_IP_{FREE,POW,HARD}_LIMIT` — счёт; `KACHO_API_GATEWAY_ANON_MAIL_IP_{FREE,POW,HARD}_WINDOW` — окна `W_F`, `W_P`, `W_H` (Р5) | без проверки 3 за 15 мин; базовая сложность вызова до 10 за 1 ч, выше — повышенная; `429` с 100 за 1 ч | 1 ≤ FREE ≤ POW ≤ HARD (счёт); 1 мин ≤ `W_F` ≤ `W_P` ≤ `W_H` ≤ 24 ч; HARD / `W_H` ≤ 1000/ч |
| край · сложность вызова | `KACHO_API_GATEWAY_ANON_MAIL_POW_BITS_{BASE,HIGH}` | 16 · 20 бит | 8 ≤ BASE < HIGH ≤ 24 |
| край · подсеть | `KACHO_API_GATEWAY_ANON_MAIL_SUBNET_{V4_24,V6_56,V6_48}_{POW,HARD}_LIMIT` — счёт по длине префикса; `KACHO_API_GATEWAY_ANON_MAIL_SUBNET_{POW,HARD}_WINDOW` — окна `W_Ps`, `W_Hs`, общие для длин префикса (Р5) | PoW с 50 за 1 ч у каждой длины; `429` с 500 за 1 ч (`/24`, `/56`), 1000 за 1 ч (`/48`); окна 1 ч | POW ≤ HARD у каждой длины; 1 мин ≤ `W_Ps` ≤ `W_Hs` ≤ 24 ч; HARD / `W_Hs` ≤ 10000/ч у каждой длины |
| край · общий поток | `KACHO_API_GATEWAY_ANON_MAIL_GLOBAL_{RATE_PER_SECOND,BURST}` | 20 rps, всплеск 100 — выше PoW для всех | RATE > 0; BURST ≥ RATE |
| край · доверенные прыжки | `KACHO_API_GATEWAY_TRUSTED_HOPS` | по профилю | задано явно в каждом профиле |
| kaname · адресат (`recovery`, `verification`, `registration` — по назначению) | `authn.login.mail-window.<назначение>.{first-pause,second-pause,per-hour,per-day,floor-interval}` | 60 с · 5 мин · 3/ч · 5/сут · пол 1 раз в 6 ч | 30 с ≤ first-pause ≤ second-pause ≤ 1 ч; 1 ≤ per-hour ≤ per-day ≤ 20; 1 ч ≤ floor-interval ≤ 24 ч |
| kaname · срок кода | `authn.login.recovery-code-ttl`, `authn.login.verification-code-ttl`, `authn.login.registration-code-ttl` | 15 мин · 60 мин · 60 мин | 5 мин ≤ ttl ≤ 24 ч; ttl ≥ first-pause |
| kaname · перебор | `authn.login.attempts.{address-source-per-window,window,address-failure-ceiling}` | 5 за 15 мин; потолок 100 неудач за то же окно | ≥ 1; окно ≤ 1 ч |
| kaname · письмо о торможении | `authn.login.mail-throttled-interval` | 7 сут | 1 сут ≤ x ≤ 30 сут |
| kaname · приглашения | `invite.{account-per-day,young-account-per-day,young-account-age,pending-max,recipient-per-hour,recipient-per-day,recipient-per-day-all,ttl}` | 200 · 50 · 30 сут · 200 · 3 · 5 · 10 · 7 сут | young ≤ account; recipient-per-hour ≤ recipient-per-day ≤ recipient-per-day-all ≤ 50; pending-max ≥ 1; 1 сут ≤ ttl ≤ 30 сут |
| kaname · доверенное устройство | `authn.login.trusted-device.{ttl,recovery-per-day}` | 90 сут · 2 | 1 сут ≤ ttl ≤ 365 сут; 1 ≤ recovery-per-day ≤ 5 |

- Инвариант пары «kaname ↔ notify»: сетка `notify` на адрес для класса `security` не меньше
  1,25 × суммы суточных пределов kaname на один адрес, включая пол и письмо о торможении (Р6). Иначе сетка `notify` отрезала бы
  письмо пола, и лимит отрезал бы владельца. Инвариант судит рендер зонтика (NTF2-73).
- У каждой длительности таблицы — и у окон «в час», «в сутки», заданных именем ручки, — держатель
  утверждает обе стороны границы: `начало + срок − 1 с` и `начало + срок` (Р6, «длительности —
  полуоткрытые интервалы»); перепись — §6б, «длительность → обе стороны».
- **Верхняя граница `invite.recipient-per-day-all ≤ 50` — лимит шаблона `invite`.** Раздел `limits`
  шаблона `invite` (`notifications/invite/notification.yaml`, Р3) задаёт не больше 50 писем на адресата
  в сутки. Лимит шаблона — данные сборки (NTF-1 Р7), значением установки не меняется, и строка сверх
  него в ленту не ставится (NTF-1 Р10). Значение ручки выше 50 было бы принятым и проигнорированным
  (`.claude/rules/api-conventions.md` §«Принято-и-проигнорировано — ЗАПРЕЩЕНО»): установка обещала бы
  приглашения, которых система не отправит. Поэтому страж kaname отвергает такое значение при старте
  (NTF2-71 (щ)). Граница — число шаблона, а не второе место о нём: страж читает её из
  сгенерированного описания шаблона `invite`.
- **Лимит шаблона не режет письмо, пропущенное окном.** Лимит `limits` шаблонов `recovery`,
  `verification`, `registration`, `registration-existing` не ниже наибольшего числа писем адресату в
  сутки, которое допускают верхние границы таблицы (окно, пол, запас устройства). Держатель — проба
  замысла З19 (`docs/changes/issue-2917/design.md`, инвариант И14: модульная проба констант
  генератора против таблицы границ); §6б называет её.
- Ручки `invite.mail-rate-limit.*`, `authn.login.verification-resend-{interval,limit,window}` и
  `authn.login.verification-code-attempts` снимаются вместе с их предметом (ban #11): их место заняли
  ручки таблицы; оставленные, они стали бы вторым местом об одном пределе.
- **Основание:** В-спам, `.claude/rules/security.md` `sec-no-silent-default-for-guarded-knob`.

### Р9. Регистрация «сначала письмо, потом сессия» (Д11)

- `POST /iam/v1/auth/register` (`email`, `password`, `csrfToken`) отвечает `200 {}` **без печений** —
  побайтово одинаково для свободного и занятого адреса. Пароль проверяется правилами полосы до
  всего остального; негодный — `400`, `code` `3`, текст называет поле `password` и правило — отказ о
  пароле, не об адресе.
- Свободный адрес: заводится ожидающая регистрация (свёртка пароля, свёртка кода, срок), письмо
  `registration` с кодом. Занятый адрес: письмо `registration-existing` («на этот адрес уже есть
  учётная запись; если вы забыли пароль — восстановите доступ» и путь восстановления), учётная
  запись не меняется. Оба письма идут в одном окне адреса назначения `registration` (Р6).
- **Код привязан к паролю того запроса, в ответ на который выпущен.** Повтор `register` на свободный
  адрес, пока ожидающая запись жива:
  - с **тем же** паролем — новой записи нет; письмо несёт код той же записи (исход `resent_same`,
    Р6);
  - с **другим** паролем — заводится **вторая** ожидающая запись со своим кодом и своим паролем;
    прежняя запись и её код живут дальше.

  Замена прежней записи отвергнута: она позволила бы любому, кто знает адрес, подменить пароль
  чужой ожидающей регистрации, и владелец адреса, предъявив код из своего письма, получил бы учётную
  запись с чужим паролем. Отдельные записи этого не допускают, а их число держит окно адреса (Р6).
  Если окно письма не пропускает (пауза или потолок), запись не заводится.
- **Запись с истёкшим кодом не жива.** Повтор `register` после истечения кода записи — как первый
  запрос: новая запись с новым кодом (исход `queued`, а в момент пола — `floor`, Р6), если окно письмо
  пропускает; тот же ли пароль,
  не важно. Истёкшая запись предъявлением не принимается (NTF2-83).
- `POST /iam/v1/auth/register/confirm` (`email`, `code`, `password`, `csrfToken` формы
  `register-confirm`) ищет среди живых ожидающих записей адреса ту, чей код и пароль совпали **оба**.
  С такой записью в срок он даёт все следствия Ф4 одним исходом: зеркало пользователя,
  **подтверждённый** адрес, личный аккаунт, сессия; пароль учётной записи — пароль этой записи; ответ
  и печенья — как у входа. Неверный или истёкший код, как и код с паролем другой записи, —
  `401`, `code` `16`, `authentication failed`, побайтово одинаково; ожидающие записи и их коды не
  гасятся неверным предъявлением. После заведения учётной записи прочие ожидающие записи адреса
  предъявлением не принимаются (адрес занят).
- Ожидающая регистрация адрес не занимает: уникальность адреса судит база при заведении учётной
  записи; из двух одновременных подтверждений одного адреса проходит ровно одно (NTF2-84).
- Край ретранслирует `register/confirm` (правка перечня путей полосы формы); ограничитель края его не
  трогает, перебор кода держат оси kaname (Р5, Р6).
- При флаге почты `false` порядок тот же: сначала правила пароля, затем отказ
  `NOTIFICATION_DELIVERY_NOT_CONFIGURED` (NTF2-51 (е)).
- **Основание:** В-спам и В-без (регистрация не отвечает на вопрос «занят ли адрес»),
  `.claude/rules/data-integrity.md` §«Within-service инварианты — ТОЛЬКО на DB-уровне».

### Р10. Класс S из аудита kaname (Д9)

- Источник — аудит kaname: строка ленты ставится в той же транзакции, что строка `audit_outbox` для
  вида события из перечня Р3. Ключ идемпотентности строки ленты — (событие аудита, шаблон,
  адресат): повтор глагола или повторная доставка аудита второй строки не дают (NTF2-97).
- Класс `security` не отключается (проверяет ядро; экран настроек — NTF-6, API настроек — NTF-3).
- Истечение ключей и токенов с напоминанием заранее — NTF-3 (Д9 «реализуется в notify»).
- **Основание:** В-без (письмо вне консоли, которую атакующий уже контролирует, — единственный
  сигнал о захвате), В-цель.

### Р11. Адресаты писем личности (Д8)

- Адресат — только ACTIVE пользователь с подтверждённым адресом. Сервисный аккаунт и группа
  адресатами не бывают; внешних адресов контактов нет. Исключения — письма, адресованные **вводу**
  до появления учётной записи: `invite`, `registration`, `registration-existing` (их адрес —
  нормализованный ввод, и именно его владение они проверяют).
- **Кому — решается в момент события, адрес — в момент отправки.** Множество адресатов строки таблицы
  Р3 kaname разрешает в транзакции события: владельцы аккаунта и администраторы облака берутся
  **снимком** на этот момент, и на каждого адресата ставится своя строка ленты с его идентификатором
  пользователя. Вид адресата в строке — `subject` (о самом субъекте) или `account_security_contact`
  (контакт безопасности области; строка несёт ещё идентификатор аккаунта). В момент отправки `notify`
  разрешает по идентификатору **только адрес** — внутренним методом справочника подтверждённых адресов
  (NTF2-96); не ACTIVE или не подтверждён — исход `DENIED(recipient)`, письма нет. Поэтому удаление
  аккаунта не оставляет строку без адресата: владельцы `account.deleted` уже названы в строке (NTF2-90).
- Событие о субъекте, который адресатом быть не может (сервисный аккаунт, группа, заблокированный
  пользователь), уходит **контакту безопасности области**: для аккаунта — его владельцам (контакты по
  категориям и переопределение проектом добавляет NTF-3, Д8), для облака — администраторам облака.
- Письмо безопасности о самом субъекте идёт ему лично без проверки права на объект.
- Справочник подтверждённых адресов и разрешение «владельцы аккаунта», «администраторы облака» —
  внутренние методы kaname на внутреннем слушателе; вызывать их может только `service:notify`
  (закрытый перечень методов, Д2): любой другой вызывающий, включая службу с проверенным
  сертификатом, получает `PERMISSION_DENIED` без адреса в ответе (NTF2-88). Письма NTF-2 зовут из них
  только справочник адресов (строка уже несёт адресата); разрешения адресатов нужны NTF-3.
- **Основание:** В-без (письма безопасности не уходят тем, кто не может их получить законно),
  В-цель (одно правило адресата на все каналы).

### Р12. Доверенное устройство и вход с нового устройства (Д9, Д11)

- После успешного входа kaname выдаёт подписанную метку устройства (печенье только HTTPS, срок —
  ручка); в базе хранится свёртка. Вход (`POST /iam/v1/auth/login`) без действующей метки порождает
  письмо `new-device-login` субъекту и выдаёт метку; вход с действующей меткой письма не порождает.
- Сессии, выданные `register/confirm` и `recovery/complete`, метку выдают, а письма
  `new-device-login` не порождают: о них уже извещают письмо с кодом, которое предъявитель прочёл, и
  письмо `recovery-completed`. Второе письмо об одном событии — лишний шум (NTF2-80, NTF2-43;
  близнец — вход, NTF2-94). Признак «новое устройство» у `session.issued` ставит только путь входа.
  Метка старше `trusted-device.ttl` не действует: вход с ней — вход нового устройства, а запаса
  восстановления у неё нет (NTF2-78). Срок метки считается от её выдачи; вход с действующей меткой
  срока не продлевает и новой метки не выдаёт (NTF2-78 (а), (б)).
- Устройство с меткой не попадает под потолок неудач «только адрес» и имеет свой запас писем
  восстановления в сутки — владелец восстанавливает доступ, даже когда чужие запросы исчерпали
  потолок адресата.
- **Основание:** В-спам (лимит не становится оружием против владельца), В-без.

### Р13. Смена адреса: письмо старому адресу — условие внесения глагола (решение автора, спор с Д9 — возврат)

- Глагола смены адреса в дереве kaname нет, и гейт `people_address_writers` держит, что его нет
  (§1.3). События для письма нет, и NTF-2 не вводит глагол ради письма.
- Требование Д9 выполняется там, где глагол единственно может появиться: находка гейта называет
  условием внесения глагола письмо класса `security` на **прежний** адрес в той же транзакции, что
  смена (NTF2-98). Появление глагола без письма — красный гейт.
- **Основание:** ban #11 (не заводить глагол «на будущее»), В-без.

### Р14. Отказ `notify` не меняет ответа глагола; исходы строк (Д2, Д4)

- Ответ глагола не зависит от доставки: несовпавшее удостоверение сервера ленты, простой `notify`,
  отсутствие шаблона в сборке наружу не раскрываются.
- Решение на письмо с тремя исходами (`ALLOW` · `NOT_YET_GRANTED` · `REVOKED`, NTF-1 Д4) пространство
  `kaname` не проходит: его авторизует сертификат сервера ленты (Р1, NTF-1 Р3). Сервер ленты kaname
  предъявил SAN, отличный от записи перечня `notify`, — подключение отвергнуто, `Claim` не вызван,
  тревога `source_identity_mismatch`; строки остаются `pending` (NTF2-06). Строка, которую `notify` не
  забрал, по какой бы причине, истекает по своему сроку — держатель истечения NTF2-07.
  Строка, истёкшая по вине платформы, закрывается `EXPIRED(platform_unavailable)` и возвращает лимит в
  той же транзакции (Д6, NTF2-07).
- Тревога — возраст старейшей непринятой строки класса `security` в ленте kaname; порог — половина
  наименьшего срока шаблонов класса в собранных шаблонах kaname (механизм — NTF-1).
- **Основание:** В-шлюз, В-без.

### Р15. Приёмник писем стенда читает только `notify` (решение автора; прежние Р8, Р13)

- После NTF-2 объектов, чья почтовая полоса названа на приёмник стенда, в каждой цепочке не
  больше одного, и это отправитель `notify` (§0, S7). Приёмник без читателя законен: цепочка может
  поднимать приёмник и вести полосу отправителя `notify` к внешнему ретранслятору (NTF2-24).
- **Основание:** В-без (приёмник читает коды; лишний читатель — лишний путь к ним).

### Р16. Порядок и условие начала (Д13, Д40)

База NTF-2 — линия релиза identity-own (Д40): kacho — ветка эпика релиза `2564` с влитой волной-4
`2798`, kaname — `357` с влитой `367`, corelib — `26`. NTF-2 начинается, когда на этой базе выполнены
все условия:

1. NTF-1 влита: `git ls-tree <база kacho> services/notify` не пуст; в corelib-пине обоих деревьев
   есть `notify/feed` и `notify/spec`; модель kaname несёт типы `notification_namespace` и
   `notification_feed` (Д2–Д4). Замер: `git ls-tree -d origin/2798 services/notify | wc -l` → 0;
   `git ls-tree -d origin/26 notify | wc -l` в corelib → 0 — условие сегодня не выполнено.
2. Посадка `own` стоит во всех цепочках: в рендере **каждой** цепочки `deploy/stacks.txt` посадка
   края — `own`, ручка полосы формы — 1, рабочих объектов поставщика — 0 (команды §1.6). Замер
   @`96e2fa72b3a`: 7 из 7. Держит существующий гейт `TestOwnPostureRaisesNoForeignIdentityService`.
3. Край ретранслирует `verify-email` и `verify-email/confirm` (§1.4). Замер @`96e2fa72b3a`: да.
4. **Только для полосы, правящей страж почты** (DoD п.14): `kacho#1276` влит в ветку эпика релиза —
   подчартов поставщика в зонтике нет: `git ls-tree --name-only <база kacho> deploy/helm/umbrella/charts/ |
   grep -cE '/(kratos|hydra)-'` → 0. Замер @`96e2fa72b3a`: 2 — условие сегодня не выполнено.
   Основание — §1.7: шаблон стража называет шаг подстановки поставщика, который снимает `kacho#1276`;
   один файл двух задач правится в порядке вливания. Прочие полосы NTF-2
   этого условия не ждут; полосы, трогающие файлы, переименованные или снимаемые волной-4, называют их
   новыми именами и зависят от вливания этих задач (Д40, маршрут `docs/changes/issue-2917/tasks.md`).
5. **Узел полосы стенда объявлен на базе** — вход Given NTF2-34 (а), (б) и посева П1 (Р20). Узел
   лежит в `values.dev.yaml`, а этот файл отдан `kacho#1276` (§3а строка 3; DoD п.13): NTF-2 его не
   правит, и чем кончится чужая посадка для узла, этот документ не знает — поэтому узел проверяется, а
   не предполагается. Команда над значениями цепочки `dev` (база зонтика и её профиль):
   `yq eval-all -r '. as $i ireduce ({}; . * $i) | [.global.kacho.identity.smtp.connectionURI // "", .global.kacho.identity.smtp.trustAnchorSecret.name // "", .global.kacho.identity.smtp.trustAnchorSecret.key // "", .mailpit.tlsSecretName // ""] | join(" | ")' <(git show <B>:deploy/helm/umbrella/values.yaml) <(git show <B>:deploy/helm/umbrella/values.dev.yaml)`.
   Условие выполнено, когда первое поле — адрес, выведенный из `.Release.Name` к сервису приёмника,
   второе поле равно четвёртому, третье — `ca.crt`. Замер @`96e2fa72b3a`:
   `smtp://{{ .Release.Name }}-mailpit:1025/ | kacho-mailpit-tls | ca.crt | kacho-mailpit-tls` —
   выполнено; отрицательный контроль — та же команда над одним `values.yaml` даёт три пустых поля.
   Команда исполняется на базе старта `<B>` (в команде — её ревизия) и повторно на базе запроса волны перед вливанием: `kacho#1276` может
   сесть между ними. Исход «условие не выполнено» (узла нет, адрес не выведен из имени релиза, якорь
   не совпал с секретом приёмника) — **возврат в приёмку**: NTF-2 узел в `values.dev.yaml` не
   восстанавливает (DoD п.13), Given NTF2-34 (а), (б) и П1 пересобираются приёмкой. После посадки
   NTF-2 узел держит NTF2-34 (а) в CI kacho: посадка, снявшая узел, красит NTF2-34 (а) в своём
   прогоне (DoD п.19).

Раздвоения службы `notify` на `notify-sender` и `notify-api` (NTF-3 Р8, NTF3-127; замысел NTF-1,
Д20) NTF-2 не ждёт и условием начала его не ставит: предикат §0, NTF2-24 и NTF2-30 судят отправителя
`notify` по границе чарта `notify` и по ссылке на секрет, а не по имени развёртывания. При посаженной
NTF-1 без NTF-3 отправитель — развёртывание `notify` (NTF1-I01: «среди объектов служб kacho — ровно
notify»); после NTF-3 — `notify-sender`. Замер: в одобренной NTF-1 слов `notify-sender` и `notify-api`
0 (`grep -cE 'notify-(sender|api)' docs/specs/sub-phase-NTF-1-notification-gateway-core-acceptance.md`
→ 0), в NTF-3 — есть (NTF3-127).

Вывод команд прикладывается к задаче `kacho#2917` до первой строки реализации. NTF-2 входит в
первую волну вместе с NTF-1 (P1) и садится **до** закрытия `kaname#475` (Р18).

### Р17. Связь с `kacho#2700` и `kaname#246`

Предмет обеих задач — частота писем восстановления и отказ по частоте, не раскрывающий
существования адреса. NTF-2 закрывает его сценариями NTF2-60 (отказ по источнику — `429`,
одинаковый для адреса, который есть, и которого нет) и NTF2-64, NTF2-65 (предел на адресата молча,
с полом). После посадки NTF-2 обе задачи закрываются ссылкой на эти ID.

### Р18. `kaname#475` замещается флагом (Д7, Д13)

Предмет `kaname#475` — «почтовый узел — условие старта посадки `own`». После NTF-2 узла у kaname нет
(Р2). Условие старта — явный флаг почты (NTF2-50); при выключенном флаге действия, которым нужна
почта, отвечают явным отказом, а состояние видно метрикой (NTF2-51, NTF2-52). Тихой установки «стартует
здоровой, а подтвердить адрес нельзя» больше нет. `kaname#475` закрывается ссылкой на NTF2-50…52 и
Р4 после посадки NTF-2.

### Р19. Почта поставщика — не предмет NTF-2; секрет почты — у одного объекта, страж один (Д39)

- **Снятие почты поставщика личности принадлежит релизу identity-own** — `kacho#1276` в волне-4
  `kacho#2798` (решение диспетчера Д39): раздел `courier` нашей конфигурации поставщика и всё, что его
  питает, ссылки поставщика на секрет почты, почтовый процесс, потоки восстановления и подтверждения,
  метод `code`, хуки `show_verification_ui` и `require_verified_address`, нагрузка обратного вызова
  восстановления, якорь сертификата почтового узла у поставщика, подчарты `kratos` и `hydra`, их пробы
  и абзацы профилей. NTF-2 этих файлов не правит (§3а, исход «за `kacho#1276`»; DoD п.13). Прежние
  Р19 «снятие прямым переключением», ключ `kratos.courier.enabled` и страж листа под `courier` из NTF-2
  сняты вместе с предметом.
- **Секрет почты смонтирован ровно в одном объекте — отправителе `notify`.** Предикат §0 судится в рендере
  каждой цепочки `deploy/stacks.txt` и самостоятельной поставки kaname (NTF2-30…33). Поставщик в
  цепочках выключен (§1.6), поэтому его объекты в обход не попадают; рендер с поставщиком, поднятым
  заново, — вход `kacho#1276` (§1.7).
- **Страж рендера один** — существующий шаблон `deploy/helm/umbrella/templates/identity-mail-lane-guard.yaml`
  (место С1 ID-MAIL-1). Второго шаблона стража почты NTF-2 не заводит — ни под именем стража, ни под
  другим: шаблонов под `deploy/helm/`, чей вызов `fail` называет ключ удостоверения почты
  `credentialSecret`, после NTF-2 ровно 1, как на базе (§1.10; NTF2-31 (ж), DoD п.14).
- **Условие «секрет почты только у отправителя `notify`» судит гейт рендера, а не страж.** Страж видит
  только объявления; объявление удостоверения одно (`global.kacho.identity.smtp.credentialSecret`), и
  какой объект его смонтирует, решают шаблоны (§1.10). После NTF-2 и `kacho#1276` значения, отдающего
  ссылку объекту, отличному от отправителя, нет — отказ стража по такому значению судил бы вход,
  которого нет. Поэтому «довести страж до условия» (Д39) исполняется так: условие держит гейт над всем
  рендером (NTF2-30, NTF2-31 (а), (б), (д)); в страже NTF-2 правит только имя читателя полосы — шапку и
  тексты отказов, называющие читателем процесс службы доступа, — на отправителя `notify`; условий
  отказа не добавляет и не снимает. Полоса стража садится после `kacho#1276` (Р16 п.4).
- Правда о подтверждённости одна — отметка kaname; рубеж по ней стоит на единственной полосе входа,
  нашей (NTF2-19). Хук поставщика `require_verified_address` снимает `kacho#1276` вместе с потоками
  поставщика.
- **Основание:** В1 (единая точка у кого есть креды — отправитель `notify`), В-без (один страж — одно место
  правды о держателе), Д39.

### Р20. Чарт `notify` читает полосу и удостоверение почты из одного узла — чтение проводит NTF-2 (Д39, Д42)

- **Узел один.** В зонтике чарт `notify` берёт почтовую полосу отправителя и её удостоверение только
  из объявления `global.kacho.identity.smtp` — адрес узла (`connectionURI`), адрес и имя
  отправителя (`fromAddress`, `fromName`), источник удостоверения (`credentialSecret`) и якорь
  проверки узла (`trustAnchorSecret`). Своего ключа полосы у чарта `notify` в зонтике нет; второго узла
  значений NTF-2 не вводит (Д42). Самостоятельная поставка чарта `notify` (NTF1-I06) задаёт полосу
  тем же путём значений `global.kacho.identity.smtp.*` в собственных значениях чарта — без значений
  зонтика и без второго ключа.
- **Значение узла доезжает до отправителя тем, чем оно объявлено.** Адрес узла раскрывается над
  именем релиза так же, как его раскрывает страж (Р19; в профиле стенда адрес выведен из имени
  релиза): на стенде отправитель `notify` получает адрес приёмника **этого** релиза и якорь —
  ключ `ca.crt` секрета приёмника (`mailpit.tlsSecretName`); на цепочке с внешним узлом — адрес и
  якорь, объявленные этой цепочкой. Незаданное удостоверение (узел без имени пользователя в адресе,
  как у приёмника стенда) — законное положение: чарт `notify` рендерится без ссылки на секрет почты и
  своего отказа по узлу не несёт; отказы по узлу — только страж (Р19, DoD п.14).
- **Кто производит.** Чарт `notify` и его собственные значения заводит NTF-1; чтение узла
  `global.kacho.identity.smtp` чартом `notify` в зонтике и отображение самостоятельной поставки на тот
  же путь — **NTF-2** (`kacho#2917`), держатель NTF2-34. Полоса стенда объявлена в
  `values.dev.yaml` (адрес приёмника выражением над именем релиза и якорь его секрета — @`96e2fa72b3a`);
  файл отдан `kacho#1276` (§3а строка 3), NTF-2 его не правит (DoD п.13). Что узел переживёт посадку
  `kacho#1276`, документ не утверждает: узел проверяется условием Р16 п.5 на базе старта и на базе
  запроса волны, исход «узла нет» — возврат в приёмку; после посадки NTF-2 узел держит NTF2-34 (а).
- **Узел пуст при включённом `notify`** (Д44; цепочки `prod` и `fe3455`: `connectionURI` и
  `credentialSecret` пусты в значениях цепочки @`96e2fa72b3a` — команда Р16 п.5, у которой вместо
  `values.dev.yaml` стоят файлы цепочки из `deploy/stacks.txt`, даёт пустые поля в обеих). Исход один:
  **отправитель `notify` отказывается стартовать** (после NTF-3 Р8 — `notify-sender`) с текстом,
  называющим ключ адреса ретранслятора, — fail-closed, `.claude/rules/00-kacho-core.md` ban16-boot-guard.
  Производитель отказа — NTF-1: ключ адреса ретранслятора (с портом и режимом TLS) в конфигурации
  отправителя и страж старта на его пустоту при включённом флаге вносятся в замысел NTF-1 по Д44,
  держатель — проба NTF-1 с близнецом (ключ пуст → отказ старта; ключ задан → старт). Доля NTF-2 —
  чтение узла (абзацы выше): пустой `connectionURI` доезжает до ключа отправителя **пустым**, без
  подставленного адреса; подстановка умолчания сделала бы страж NTF-1 мёртвым
  (`.claude/rules/security.md` `sec-no-silent-default-for-guarded-knob`). Держатель — NTF2-34 (е), (е').
  Рендер при этом проходит: чарт `notify` и страж зонтика по пустому узлу не отказывают (Р19, Д42) —
  отказ стоит в старте процесса, а не в рендере.
- **Установка без почты выключает флаг** (Д7, Д44): `global.kacho.notifications.enabled: false`
  (либо флаг модуля). Тогда источники отвечают на действия, которым нужна почта, единым отказом
  `DeliveryNotConfigured`, одинаковым для любого адреса (Р4; у kaname — NTF2-51). Значений цепочек
  `prod` и `fe3455` NTF-2 не правит (§3а строки 4, 5 — за `kacho#1276`): в них почтовый узел — ручка
  установки (`values.prod.yaml`: «почтовый шлюз … — ручка кластера»), и установка на этих цепочках
  либо задаёт узел, либо выключает флаг; третьего исхода, где отправитель поднят без адреса, нет.
- **Пара «имя пользователя в адресе ⇔ источник удостоверения» при самостоятельной поставке `notify`
  (NTF1-I06) не проверяется никем.** Страж живёт в зонтике и в самостоятельный рендер чарта `notify`
  не входит; NTF-2 второго стража не заводит (Р19, Д42), а NTF2-34 (д) судит только, что значения
  узла доезжают до отправителя. Согласие пары в такой поставке — забота установки.
- **Основание:** В1 (один отправитель — одно объявление полосы), В-без (второй узел значений — второе
  место правды о полосе), Д39, Д42.

---

## §3 Что NTF-2 замещает — явно

| прежнее | где | исход |
|---|---|---|
| Р23 «у письма приглашения производитель — наш код; у двух других — почтовый процесс поставщика» | `sub-phase-ID-MAIL-1-mail-delivery-acceptance.md` | **замещено**: все письма личности kaname ставит в ленту, доставляет `notify` (Р1); почтовый процесс поставщика снимает `kacho#1276` (Д39) |
| MAIL-47 «один путь отправки на вид письма», перечень `OurMailKinds` | там же; kaname `internal/check/mail_send_paths.go` | **замещено**: «отправителей SMTP в kaname 0» (NTF2-44) и «виды писем = шаблоны kaname» (NTF2-45) |
| MAIL-25 и Р22 «ограничение частоты на наших глаголах, отправляющих письмо» | там же | **замещено** таблицей Р8 и сценариями S3 |
| Р26 «оба процесса службы личности читают нашу почтовую карту» | там же | **вне NTF-2**: почтовую настройку объектов поставщика снимает `kacho#1276` (Д39, Р19) |
| Р27 «почтовая полоса объявлена одним местом» в части раздела `courier` | там же | **вне NTF-2**: раздел `courier` снимает `kacho#1276`; NTF-2 не меняет, что полоса объявлена одним местом `global.kacho.identity.smtp.*`, и называет её читателем отправителя `notify` вместо kaname |
| Р21б «окно предъявителей поставщика» | там же | **истекает**: код — запись kaname (Р6) |
| Р4а, место С2 (проверка почтовой полосы в шаге подстановки поставщика) | там же; `deploy/tests/helm/identity-mail-lane-runtime-inject.sh` | **вне NTF-2**: снимается вместе с шагом подстановки удостоверения поставщика — `kacho#1276`. Место С1 (`identity-mail-lane-guard.yaml`) остаётся единственным стражем почты; условие «секрет только у отправителя `notify`» держит гейт рендера (Р19, NTF2-30, NTF2-31) |
| §1.10а «письма шлёт второй объект службы личности» | там же | **истекает** с почтовым процессом поставщика — `kacho#1276` |
| MAIL-01 (подтверждение доставлено и принято) | там же | **производитель заменён**: NTF2-01, NTF2-02 |
| MAIL-02 (Given «человек прошёл MAIL-01») | там же | **Given переопределено**: подтверждённый адрес — исход NTF2-80 или NTF2-02 |
| MAIL-03 (неподтверждённый адрес входа не даёт) | там же | **замещено**: отказ стоит дальше экрана подтверждения — NTF2-19 |
| MAIL-04 (восстановление доставлено) | там же | **производитель заменён**: NTF2-43 |
| MAIL-14, MAIL-15, MAIL-16, MAIL-17, MAIL-18, MAIL-49, MAIL-51, MAIL-52 | там же и их держатели в `deploy/` (§3а) | **вне NTF-2**: снимаются вместе с почтой поставщика — `kacho#1276` (§3а, исход «за `kacho#1276`»); рубеж подтверждённости на нашей полосе, заменяющий MAIL-52, утверждает NTF2-19 |
| MAIL-48 «оба отправителя читают одно объявление» | там же; `deploy/identity_mail_lane_feeds_both_senders{,_injection}_test.go` | **переписан**: держатель предиката §0 (NTF2-30…32) |
| MAIL-54 «полоса объявлена одним местом» | там же; `deploy/identity_mail_lane_single_declaration{,_injection}_test.go` | **вне NTF-2**: предмет — раздел `courier`; правка — `kacho#1276` (§3а, строки 21–22) |
| Р7 и Р18 ID-MAIL-1 (приёмник писем стенда) | там же | **сохранено**, читатель сужен до отправителя `notify` (Р15, NTF2-24) |
| Р7 «живёт только последний выданный код», EV-33, EV-34 | kaname `access-beyond-login-needs-a-verified-address.md` | **замещено**: пока код жив, повтор шлёт тот же код (Р6, NTF2-40, NTF2-41) |
| ручка `verification-code-attempts` (код гаснет после N неверных) | там же; kaname `config/login_lane.go` | **замещено**: неверные предъявления код не гасят, перебор держат оси Р6 (NTF2-66) |
| Р8 «третий вид в той же очереди» | там же | **замещено**: лента `notify` (Р1) |
| EV-23, EV-24 (пауза и суточный предел запроса подтверждения) | там же | **сохранено по форме отказа**, величины — ручки Р8 (NTF2-05) |
| окно обращений по источнику на регистрацию и запрос восстановления — отказ службы `429` `TOO_MANY_ATTEMPTS` по источнику этих двух путей (`kaname#456`, заведено его посадкой) | kaname `access-beyond-login-needs-a-verified-address.md`; ручки `authn.login.source-{attempts,window}` | **замещено**: ось источника анонимных почтовых глаголов — только у края (Р5, NTF2-60 (а)); на этих путях kaname по источнику не отказывает; ручки остаются за окном неверных предъявлений пароля при входе, которое NTF-2 не меняет |
| Ф4-01, Ф4-11, Ф4-12 (регистрация выдаёт сессию сразу; занятый адрес — отказ) | kaname `registration-and-its-three-consequences.md` | **замещено**: «сначала письмо, потом сессия» (Р9, NTF2-80…85); четыре следствия Ф4-01 наступают на `register/confirm` |
| Ф5-01 (код чеканится на каждый запрос) | kaname `recovery-of-access.md` | **замещено**: повтор того же живого кода (Р6, NTF2-64) |
| Ф5-09, Ф5-10, Ф5-11, Ф5-12 (письмо в НАШУ очередь, перепись видов и отправителей, узел недоступен) | там же | **замещено**: лента `notify` (NTF2-43, NTF2-45, NTF2-07) |
| Д5 «истекает вместе с поставщиком» | там же | **исполняет** `kacho#1276` (Д39) |
| ручки `invite.mail-rate-limit.*` | kaname конфигурация и поставка | **замещено** потолками приглашений Р7, Р8 (NTF2-69) |
| предмет `kaname#475` «узел почты — условие старта `own`» | трекер | **замещён** флагом (Р18) |

Пути предшественников при правке не редактируются. Замещение фиксируется этой таблицей, а после
одобрения — строкой-ссылкой из шапок ID-MAIL-1 и приёмок kaname (DoD п.23).

### §3а Перепись файлов дерева kacho, задевающих предмет

Перепись — объединение двух источников, у каждого найденного файла исход из закрытого словаря:

1. **слова предмета** — команда §1.9 (слова почты kaname `K`, слова почты поставщика `W` прежней
   редакции, меток ID-MAIL-1 и имён файлов), 49 файлов @`96e2fa72b3a`; пути — именами после
   `kacho#2759`;
2. **посев «после NTF-2»** — дерево по DoD п.14 и п.16 (снята почтовая полоса kaname в чарте, читатель
   полосы в тексте стража — отправитель `notify`), прогнанное всеми бегунами дерева `deploy`: `go test -count=1 ./deploy/...`
   без метки и с меткой `helmcharts`, `make -C deploy gate-self-test`, `make -C deploy injection-proofs`,
   `make -C deploy helm-manifest-test`. Файл, красный на посеве при зелёной базе, обязан стоять с
   исходом «правится» или «переписан».

**Посев перемеряется на базе старта** (DoD п.16). Посевы редакции 5 (`2267b405220`) мерили снятие
почты поставщика — предмет, ушедший в `kacho#1276` (Д39), — и к предмету NTF-2 не относятся; третий
источник прежней редакции (посев без ключа `kratos.courier.enabled`) снят вместе с ключом.

Словарь исходов: **правится** — из файла снимается предмет NTF-2 либо вносится её правка;
**переписан** — утверждение, якорь или настоящий вход меняются, новое утверждение названо;
**остаётся** — NTF-2 файл не меняет, его предмет переживает NTF-2, файл печатает непустой обход (кроме
комментария, ставшего ложным); **за `kacho#1276`** — предмет файла — почта поставщика личности (Д39):
NTF-2 файл не правит, правку или снятие делает `kacho#1276` (DoD п.13). Исхода «снят» у NTF-2 в
дереве kacho нет.

| # | файл (под `deploy/`) | исход | куда предмет / что гейт считает после NTF-2 |
|---|---|---|---|
| 1 | `helm/umbrella/charts/kaname/templates/_identity-provider.tpl` | за `kacho#1276` | раздел `courier`, шаг подстановки, потоки, хуки (Р19) |
| 2 | `helm/umbrella/values.yaml` | правится | `global.kacho.notifications.enabled` (Р4); абзац об `invite-mail.ca-bundle-file` снимается. Блок приёмника остаётся (Р15); `kratos.courier.enabled` NTF-2 не вносит |
| 3 | `helm/umbrella/values.dev.yaml` | за `kacho#1276` | блок `kratos.statefulSet`, якорь почтового узла поставщика, член `hookRecoveryPayload` отпечатка. Узел `global.kacho.identity.smtp` в этом файле читает чарт `notify` (Р20); его наличие — не исход этой строки, а условие Р16 п.5 |
| 4 | `helm/umbrella/values.prod.yaml` | за `kacho#1276` | то же для боевого профиля |
| 5 | `helm/umbrella/values.fe3455-identity-posture.yaml` | за `kacho#1276` | абзац о разделе `courier` |
| 6 | `helm/umbrella/charts/kaname/templates/configmap.yaml` | правится | блок `invite-mail` снимается; ручка флага почты добавляется (Р4) |
| 7 | `helm/umbrella/cutover-fe3455.sh` | за `kacho#1276` | абзац об объявленном разделе `courier` |
| 8 | `identity_courier_arg_premise_test.go` | за `kacho#1276` | MAIL-49 |
| 9 | `identity_courier_reads_what_it_mounts_test.go` | за `kacho#1276` | почтовый процесс поставщика |
| 10 | `identity_bearer_window_ceiling_test.go` | за `kacho#1276` | MAIL-51 |
| 11 | `identity_bearer_window_ceiling_injection_test.go` | за `kacho#1276` | то же |
| 12 | `identity_delivery_flows_declared_once_test.go` | за `kacho#1276` | MAIL-18 |
| 13 | `identity_delivery_flows_declared_once_injection_test.go` | за `kacho#1276` | то же |
| 14 | `identity_verification_mirrors_the_requirement_test.go` | за `kacho#1276` | MAIL-15…17 |
| 15 | `identity_verification_mirrors_the_requirement_injection_test.go` | за `kacho#1276` | то же |
| 16 | `identity_verified_address_required_on_both_lanes_test.go` | за `kacho#1276` | MAIL-52: хук поставщика снимается с потоками; рубеж нашей полосы — NTF2-19 |
| 17 | `identity_verified_address_required_on_both_lanes_injection_test.go` | за `kacho#1276` | то же |
| 18 | `tests/helm/identity-mail-lane-runtime-inject.sh` | за `kacho#1276` | место С2 шага подстановки поставщика |
| 19 | `identity_mail_lane_feeds_both_senders_test.go` | переписан | держатель NTF2-30: предикат §0; наш отправитель kaname снят, читатель полосы `global.kacho.identity.smtp.*` со стороны установки — отправитель `notify` |
| 20 | `identity_mail_lane_feeds_both_senders_injection_test.go` | переписан | инъекции NTF2-31 (а), (б), (в), (д), (ж) |
| 21 | `identity_mail_lane_single_declaration_test.go` | за `kacho#1276` | MAIL-54: единственность раздела `courier` |
| 22 | `identity_mail_lane_single_declaration_injection_test.go` | за `kacho#1276` | то же |
| 23 | `identity_mail_defaults_are_empty_test.go` | остаётся | умолчания ручки `global.kacho.identity.smtp.*`; её читатель в установке — отправитель `notify` |
| 24 | `identity_mail_defaults_are_empty_injection_test.go` | остаётся | то же |
| 25 | `helm/umbrella/templates/identity-mail-lane-guard.yaml` | правится | единственный страж почты (NTF2-31 (ж)); условий отказа NTF-2 не добавляет; шапка и тексты отказов, называющие читателем процесс службы доступа, называют отправителя `notify` (Р19) |
| 26 | `tests/helm/identity-mail-lane-guard-inject.sh` | правится | пробы места С1 остаются; ожидаемые тексты отказов — с читателем «отправитель `notify`» (Р19) |
| 27 | `helm/umbrella/templates/mail-receiver.yaml` | остаётся | приёмник — ядро стенда (Р15) |
| 28 | `mail_receiver_core_test.go` | остаётся | объекты приёмника по цепочкам |
| 29 | `mail_receiver_core_injection_test.go` | остаётся | то же |
| 30 | `scripts/newman-parallel.sh` | остаётся | приёмник на каждом шарде |
| 31 | `identity_callback_transport_test.go` | остаётся | совпадение — синтетический вход (`lane: "recovery"`) |
| 32 | `identity_flow_path_is_served_injection_test.go` | остаётся | совпадение — синтетический вход |
| 33 | `identity_replaced_lists_injection_test.go` | остаётся | совпадение — синтетический вход |
| 34 | `identity_step_declaration_parses_injection_test.go` | за `kacho#1276` | якорь инъекции — шаг подстановки поставщика |
| 35 | `identity_file_keys_survive_the_environment_test.go` | остаётся | ключи нашего файла настроек поставщика против переменных его чарта; NTF-2 их не меняет |
| 36 | `identity_file_keys_survive_the_environment_injection_test.go` | за `kacho#1276` | настоящий вход — ключ почтового раздела поставщика |
| 37 | `identity_substitution_judges_the_form_test.go` | остаётся | ссылки во владении шага подстановки; NTF-2 шаг не меняет |
| 38 | `helm/umbrella/charts/kaname/templates/deployment.yaml` | правится | переменные `KANAME_INVITE_MAIL_*`, том якоря почтового узла kaname и абзац о них снимаются |
| 39 | `helm/umbrella/charts/kaname/values.yaml` | правится | флаг почты добавляется; копия `global.kacho.identity.smtp` для одиночного рендера подчарта остаётся, пока её читает шаблон поставщика (`kacho#1276`) |
| 40 | `helm/umbrella/charts/kaname/templates/identity-provider-config-configmap.yaml` | за `kacho#1276` | абзац шапки о потоке восстановления |
| 41 | `helm/umbrella/charts/kaname/templates/identity-provider-hooks-configmap.yaml` | за `kacho#1276` | запись `recovery-payload.jsonnet` |
| 42 | `identity_method_comment_matches_declaration_test.go` | остаётся | отмеченный перечень методов совпадает с объявлением; NTF-2 методов поставщика не меняет |
| 43 | `identity_method_comment_matches_declaration_injection_test.go` | за `kacho#1276` | настоящий вход — перечень после снятия метода `code` |
| 44 | `chart_env_names_carry_their_own_product_prefix_test.go` | остаётся | совпадение: `COURIER_…` — пример чужого имени |
| 45 | `chart_env_names_carry_their_own_product_prefix_injection_test.go` | остаётся | совпадение — синтетический вход |
| 46 | `tests/helm/identity-substitution-output-inject.sh` | за `kacho#1276` | ось С — место С2 |
| 47 | `address_gate_stand_render_test.go` | переписан | F6b-56 (б): «у стенда почтовая полоса объявлена у отправителя `notify`» вместо блока `invite-mail` в настройках kaname |
| 48 | `helm/umbrella/charts/kaname/templates/_helpers.tpl` | правится | помощник каталога якоря почтового узла kaname и абзац о нём снимаются |
| 49 | `helm/umbrella/values.a8f60d.yaml` | правится | ссылка на секрет почты у kaname снимается; удостоверение объявляется для отправителя `notify` |

Итог: правится 8, переписан 3, остаётся 14, за `kacho#1276` 24 — всего 49. Файл, которого нет в
таблице, и файл с исходом «остаётся» или «за `kacho#1276`», красный на посеве на базе старта, —
возврат в приёмку. Отсутствие файла на базе старта судится не исходом его строки, а тем, кто файл
снял (DoD п.16): строки 31, 32, 33, 35, 37, 42 с исходом «остаётся» — пробы о конфигурации поставщика
личности (у 35, 37, 42 это названо колонкой «куда предмет», у 31–33 — именем файла), и `kacho#1276`
вправе снять их вместе с поставщиком; такое снятие — исход
`kacho#1276`, а не расхождение этой таблицы.

### §3б Перепись файлов дерева kaname, задевающих почту

Предикат — §1.1, 97 файлов @`caf1c95ca` (на `357` @`734f69fb4` — 94). Исход назначается группе; на
базе старта перепись перемеряется, и каждый файл получает исход своей группы (DoD п.17). Разбивка —
префиксом пути по выводу команды §1.1.

| группа | файлов | исход | куда предмет |
|---|---|---|---|
| `internal/clients/` (отправитель и его пробы) | 7 | снят | NTF2-44 |
| `cmd/kaname/` (проводка отправителя и очереди) | 7 | `invite_mail_wiring{,_test}.go` сняты; остальные правятся — подъём сервера ленты вместо дренажа очереди | NTF2-44, NTF2-46 |
| `internal/apps/kaname/config/` | 10 | `invite_mail*.go` сняты; `config.go`, `defaults.go`, `invite.go` правятся под ручки Р8 и флаг Р4 (вне предиката правится и `login_lane.go`); пробы переписаны | NTF2-48, NTF2-50, NTF2-71 |
| `internal/apps/kaname/api/` (пробы глаголов с письмом, включая `internal_iam`) | 5 | переписаны: утверждают строку ленты, а не строку очереди | NTF2-05, NTF2-42, NTF2-64 |
| `internal/check/` (MAIL-47 и соседние гейты) | 12 | `mail_send_paths*` и `mail_kind_sender_parity*` переписаны под NTF2-44, NTF2-45; прочие правятся в словаре видов | NTF2-44, NTF2-45 |
| `internal/repo/kaname/` (очередь и окна) | 10 | `invite_mail_outbox/outbox.go` снят; окна переписаны под счётчик ленты (Д6) | NTF2-64, NTF2-69 |
| `internal/migrations/` | 6 | применённые не правятся (ban #5); новая миграция снимает очередь и заводит ленту; `retired.json` дописывается | NTF2-44 |
| `internal/observability/metrics/` | 5 | метрики отправителя сняты; `kaname_mail_intents_total`, `kaname_notifications_enabled` заведены | NTF2-52, Р6 |
| `internal/outboxtypes/` | 1 | правится: тип окна письма уходит в описание лимита шаблона | NTF2-08 |
| `internal/handler/loginlanehttp/` (пробы) | 4 | переписаны | NTF2-01, NTF2-43, NTF2-80 |
| `internal/supplyhygiene/` | 2 | переписаны: страница поставки называет флаг, а не узел | NTF2-33 |
| `deploy/`, `deploy/templates/` | 10 | узел и креды сняты из значений (в том числе `values.prod.yaml`) и карты; пробы рендера переписаны; `mail_lane_names_every_letter_kind{,_injection}_test.go` (объявление узла на каждый вид письма, `kaname#259`) сняты вместе с узлом — объявление почты судят NTF2-33 и DoD п.22 | NTF2-33 |
| `docs/content/` | 6 | правятся: почта — через `notify`, флаг почты (в том числе `install/configuration.mdx`) | DoD п.22 |
| `docs/specs/reviews/` | 5 | остаются: записи ревью только дописываются | — |
| `.github/scripts/`, `tests/authz-fixtures/`, `tests/newman/` | 6 | переписаны: стенд читает письма из приёмника, куда пишет `notify`; посевы П3 и П10 (`verified-human`) | П3, П10, NTF2-01, NTF2-81 |
| `proto/kaname/` | 1 | правится комментарий об очереди | — |

Сумма по группам — 97.

---

## §4 Что НЕ входит — и где живёт

| предмет | где |
|---|---|
| служба `notify`, `corelib notify/feed` и `notify/spec`, `cmd/notifygen`, макет и блоки, `Claim`/`Ack`, звено идентичности служб, типы модели `notification_namespace` и `notification_feed`, решение на письмо с тремя исходами, исключение пространства `kaname` (запись перечня `authorization: certificate`, проверка SAN, тревога `source_identity_mismatch`, валидатор манифеста службы доступа), единый отказ флага `feed.DeliveryNotConfiguredStatus()`, сетка `notify` на адрес и тормоз, тревоги возраста строки, приёмник стенда с TLS | NTF-1 — `kacho#2915`, `corelib#77` |
| политика выпуска сертификатов служб | NS — `kacho#2916` |
| письма модулей kacho, сводки, истечение ключей и токенов с напоминанием, API настроек и контактов (включая неотключаемость класса S на запись), контакты по категориям и переопределение проектом, право получателя `v_get` на ресурс | NTF-3 — `kacho#2918` |
| возвраты, жалобы, подавление (включая security после hard bounce на 72 ч), DKIM/SPF/DMARC, ротация кредов | NTF-4 — `kacho#2919` |
| извещения оператора, класс OB | NTF-5 — `kacho#2924` |
| центр уведомлений консоли, экран настроек, контакты | NTF-6 — `kacho#2925` |
| глагол смены адреса | не вводится (Р13); условие его внесения — NTF2-98 |
| почта поставщика личности (прежний результат S6, Д39): раздел `courier` нашей конфигурации поставщика и всё, что его питает, ссылки поставщика на секрет почты, почтовый процесс и ключ его выключения, потоки восстановления и подтверждения, метод `code`, хуки `show_verification_ui` и `require_verified_address`, нагрузка обратного вызова восстановления, якорь почтового узла у поставщика, страж листа под `courier`; файлы §3а с исходом «за `kacho#1276`»; прежние сценарии NTF2-18, NTF2-20…NTF2-23 | `kacho#1276` — релиз identity-own, волна-4 `kacho#2798` (эпик `kacho#1266`, ветка эпика релиза `2564`) |
| физическое снятие поставщика: подчарты `kratos` и `hydra`, база, шаблоны, схема личности, маршрут обратного вызова восстановления в kaname | `kacho#1276` (эпик `kacho#1266`) |
| белая метка отправителя | вне эпика: один отправитель на установку |

**Порядок с `kacho#1276`.** Предмет NTF-2 не зависит от того, сел ли `kacho#1276` раньше или позже,
кроме полосы стража S7: она садится после него (Р16 п.4, §1.7). Файлы §3а с исходом «за `kacho#1276`»
NTF-2 не правит ни при каком порядке (DoD п.13).

---

## §5 Посевы — как конструируется каждое Given

| посев | что создаёт | чем |
|---|---|---|
| **П1** стенд | цепочка **`dev`** из `deploy/stacks.txt`, поднятая с базы, где выполнены условия Р16 и посажены обе стороны NTF-2 (пин kaname в kacho указывает на ветку эпика kaname с NTF-2). Флаг почты kaname — `true`; `notify`, приёмник писем и край с ограничителем есть | рецепт подъёма стенда; перед прогоном проба печатает признаки рендера цепочки `dev` (посадка `own`, ручка полосы 1, объектов поставщика 0; объектов чарта `notify`, чья почтовая полоса названа на приёмник этого релиза с якорем `ca.crt` его секрета, 1 — исход NTF2-34 (а); объектов со ссылкой на секрет почты и с адресом узла вне чарта `notify` 0; флаг `true`) и останавливается, если хоть один не совпал. Удостоверения почты цепочка `dev` не объявляет (приёмник стенда его не требует), поэтому ссылок на секрет почты у чарта `notify` в ней 0 — это не признак остановки |
| **П2** подтверждённый человек | человек с адресом `ntf2-<NN>-<runId>@<домен приёмника стенда>`, паролем, подтверждённым адресом, личным аккаунтом и живой сессией | исход NTF2-80 через край П1: `register` → код из API приёмника → `register/confirm`. У каждого кейса свой человек |
| **П3** неподтверждённый человек | человек с паролем и **неподтверждённым** адресом `ntf2-<NN>-<runId>@<домен приёмника стенда>`, затем вход — сессия в положении подтверждения | посев стенда в дереве kaname `tests/authz-fixtures/` (новый шаг `unverified-human`): строка человека пишется в базу kaname стенда посевом, не миграцией (`.claude/rules/data-integrity.md` `stand-data-by-seed`); вход — `POST /iam/v1/auth/login` через край П1 |
| **П4** чужое удостоверение сервера ленты kaname | сервер ленты kaname на стенде П6 предъявляет сертификат тестового удостоверяющего центра стенда, у которого **URI-SAN** (идентификатор из `kaname.spiffe`) отличается от записи `kaname` в перечне источников `notify` одним сегментом служебной учётной записи, а **DNS-SAN** тот же: его край сверяет с `ServerName` своего ребра к kaname, и путь край → kaname не меняется; `notify` сверяет запись равенством полного URI (NTF-1), поэтому отвергает; перечень `notify` не меняется — **только на стенде П6** | перезапуск сервера ленты kaname пробы с другим сертификатом; проба печатает URI-SAN и DNS-SAN записи, предъявленного сертификата и `ServerName` края; сертификат, не прошедший сверку края, — «не выполнилось», а не красный |
| **П5** администратор аккаунта | П2: зарегистрировавшийся — владелец своего личного аккаунта (Ф4 Р8) | исход NTF2-80 |
| **П6** integration-стенд | kaname, `notify`, край и тестовый SMTP-узел в процессе пробы, общие управляемые часы; ленту, окна, уборщика и ограничитель края судят часы пробы; адрес источника задаётся доверенным прыжком стенда | стенд уведомлений NTF-1 с kaname-источником (kacho тянет kaname пином, ребро kacho→kaname законно); подключение источника kaname — NTF-2 |
| **П6-off** стенд без почты | П6 с `notifications.enabled: false` у kaname | тот же стенд, одно значение |
| **П6-age** возраст аккаунта | два аккаунта: `mature` заведён в момент `T`, `young` — в `T + 1 с`, у каждого администратор; часы пробы переводятся на `T + Ya`, где `Ya` = `invite.young-account-age` печатается пробой (ориентир 30 сут). В `T + Ya` возраст `mature` — ровно `Ya` (не моложе порога), `young` — `Ya − 1 с` (моложе): обе стороны порога в одном моменте. Сценарий, двигающий часы, называет, какой аккаунт ему нужен и в каком положении он остаётся | П6, фикстура П11, часы пробы |
| **П7** инъекция рендера | копия одной цепочки с одной добавленной строкой значения | гейт рендера во временном каталоге; ствол не меняется |
| **П7-kratos**, **П7-doc** | сняты редакцией 14 (Д39): вход повторного включения поставщика служил сценариям снятия его почты, ушедшим в `kacho#1276` | — |
| **П7-tpl** копия шаблонов зонтика | копия `deploy/helm/` дерева kacho с одним добавленным шаблоном (NTF2-31 (ж)) | гейт переписи шаблонов во временном каталоге; ствол не меняется |
| **П8** копия дерева kaname | копия дерева kaname с одной правкой (файл, строка манифеста, шаблон) | гейт дерева во временном каталоге |
| **П10** подтверждённый человек посевом | человек с адресом `ntf2-<NN>-<runId>@<домен приёмника стенда>`, паролем и **подтверждённым** адресом, заведённый без единого глагола почты: ни регистрации, ни кода, ни письма; окон адресата на его адрес нет | на П1 — посев стенда в дереве kaname `tests/authz-fixtures/` (новый шаг `verified-human`, рядом с `unverified-human` П3; `.claude/rules/data-integrity.md` `stand-data-by-seed`); на П6 — фикстура integration-стенда той же формы |
| **П11** люди и объекты П6 | пользователи, аккаунты, проекты, группы, сервисные аккаунты и администраторы облака, названные в Given сценариев уровня I | фикстура П6 записью в базу kaname, как П10: без глаголов почты, окон адресата и строк ленты к началу сценария; вход с меткой устройства, где он назван в Given, — глаголом `login` |
| **П12** консоль с перехваченным краем | страница консоли из сборки стенда П1; перехват сети страницы (playwright `page.route`) отвечает на `POST /iam/v1/auth/recovery` телом, заданным сценарием, в форме собственных статусов края; прочие запросы страницы идут к краю П1; часы страницы установлены пробой (`page.clock`); проба подписана на создание и завершение `Worker` страницы | playwright-проба консоли; ответ края задаёт проба, а не край: общее состояние П1 не меняется |

**Состояние, общее для кейсов.** Сценарий уровня E меняет только состояние своего человека: его
регистрацию, сессию, код, окна на его адрес, метку его устройства. Право ленты, флаг, конфигурация,
доступность `notify`, часы и счётчики края по источнику — общее состояние стенда; такие Given
ставятся только на уровне I, на стенде П6, принадлежащем одной пробе.

**Окно адресата — состояние того, кто его построил.** Given, построенный глаголом почты (П2 —
исходом NTF2-80), оставляет в окне своего адреса письмо. Сценарий, чей When снова идёт в **то же**
окно того же адреса, строит своего человека посевом П10, где окна нет, либо ждёт названную паузу,
значение которой печатает проба (NTF2-40). Сценарий, чей When идёт в **другое** окно (назначение
`recovery` после регистрации), строится П2 без ожидания.

**Счётчики края на П1.** Все запросы прогона идут к краю П1 с одного источника — источника раннера.
Стенд П1 объявляет ручки края (в границах Р8) так, что объём `V` анонимных почтовых запросов одного
прогона меньше порога «без проверки» `FREE`, а `V + FREE` меньше жёсткого порога источника и
порогов подсети. Пороги проба берёт из рендера цепочки `dev`, а `V` — счётом по перечню кейсов прогона:
число запросов `POST /iam/v1/auth/recovery` и `POST /iam/v1/auth/register` во всех кейсах коллекций
newman прогона и в шагах NTF2-72, включая построение П2; печатает оба. Если условие не выполнено —
прогон «не выполнилось», а не красный. E-клиент решает вызов PoW так же, как консоль (Р5), и ни один
newman-кейс не утверждает ступень лестницы края. NTF2-72 — единственный E-кейс, утверждающий
ступень: он создаёт её сам и сам же строит близнеца (Given NTF2-72).

**Источник по умолчанию на П6.** Анонимный почтовый запрос пробы, чей сценарий источника не
называет, идёт через доверенный прыжок стенда со своего адреса из своей подсети `/24`, с темпом ниже
общего потока края: ни один ключ края порога «без проверки» не достигает, и сценарий судит только
kaname. Сценарии, судящие край (NTF2-60…63, 74, 79), и NTF2-66 задают источники сами.

**Множества цепочек выводятся из рендера.** G-сценарий не перечисляет цепочки, в которых
утверждение действует: множество выводится из рендера по названному признаку и печатается.

---

## §6 Сценарии

Уровни: **E** — сквозная проба на стенде П1 через край (newman; NTF2-72 — playwright); **I** —
integration на стенде П6; **G** — гейт рендера или дерева; **U** — проба консоли П12 (playwright над
страницей консоли, ответ края задан перехватом сети страницы, часы страницы управляемые): исходы края,
которые на общем стенде П1 создать нельзя, не трогая общего состояния (NTF2-58).

Форма запроса и ответа уровня E: `Accept: application/json`, у тела — `Content-Type:
application/json`; прогонщик не следует переадресации (`followRedirects: false`); каждый ответ
утверждается парой — точный HTTP-статус и `code` из тела, для отказов ещё текст и `reason`
(`.claude/rules/api-conventions.md` §«gRPC-код → HTTP-статус»); «бюджет доставки» — 60 с от ответа
глагола до письма в приёмнике. Состояние строк ленты утверждается только на уровне I.

**«Побайтово равны»** о двух ответах значит: равны HTTP-статус, тело и множество имён заголовков
`Set-Cookie`; значения заголовков времени и трассировки и `Retry-After` в сравнение не входят. Если
сценарий исключает из сравнения поле тела, он называет его (NTF2-60: `challenge` и `expiresAt` вызова
у каждого вызова свои).

**Счёт писем на уровне E** ведётся по шаблону и от ответа глагола When: письмо шаблона `X` в
приёмнике опознаётся темой, объявленной в `notifications/X/notification.yaml` для локали `ru`, и
считаются только письма, пришедшие на адрес после ответа. «Ровно одно письмо `X`» не утверждает
ничего о письмах других шаблонов на тот же адрес. **Счёт строк ленты на уровне I** ведётся по паре
(событие, адресат) и шаблону, названному сценарием: строки, порождённые другими событиями той же пробы,
в счёт не входят. Ряды окна `recovery` (NTF2-64, 65, 68, 70, 78) считают строки шаблона `recovery`;
строку `mail-throttled`, которую ставит исход `capped` (Р6), утверждает только NTF2-68.

### S1 — kaname на ленте: письма личности

#### Сценарий 01: письмо подтверждения адреса доставляет notify

**ID:** NTF2-01 · E · положительный

**Given** П1
**And** человек П3 в положении подтверждения, его адрес `A`

**When** клиент вызывает `POST /iam/v1/auth/verify-email` через край П1 с payload:
  - `csrfToken` = признак формы вида `verify-email`

**Then** `200 {}`
**And** в пределах бюджета доставки приёмник получает на `A` **ровно одно** письмо `verification`
**And** `From` — единый адрес отправителя установки, `Reply-To` нет
**And** письмо — `multipart/alternative` с частями `text/plain` и `text/html`
**And** в HTML нет внешних ресурсов: каждый `src` — `cid:`, каждый `href` начинается с origin
установки из конфигурации
**And** письмо несёт код подтверждения; ни один адрес ссылки кода не содержит

#### Сценарий 02: код из письма переводит в обычное положение

**ID:** NTF2-02 · E · положительный

**Given** NTF2-01 выполнен тем же человеком и той же сессией; код `K` прочитан из письма через API
приёмника

**When** `POST /iam/v1/auth/verify-email/confirm` с payload:
  - `code` = `K`
  - `csrfToken` = признак вида `verify-email-confirm`

**Then** `200`, тело несёт `session.emailVerified = true`
**And** `GET /iam/v1/auth/me` новым носителем — `200` и `emailVerified: true`

#### Сценарий 03: код с одним изменённым знаком не подтверждает и верного не гасит

**ID:** NTF2-03 · E · отрицательный · близнец — шаг 2 того же кейса (отличается только значением кода)

**Given** свой человек П3; письмо подтверждения доставлено, код `K` прочитан из приёмника

**When** шаг 1: `POST /iam/v1/auth/verify-email/confirm` с `code` = `K'` — `K` с последним знаком,
заменённым другим знаком того же алфавита
**And** шаг 2 (строго после шага 1, той же сессией): тот же запрос с `code` = `K`

**Then** шаг 1: `401`, `code` `16`, `authentication failed`; `GET /iam/v1/auth/me` — `emailVerified:
false`
**And** шаг 2: `200`, `session.emailVerified = true` — неверный код не истратил верный

#### Сценарий 40: повторный запрос в срок кода шлёт тот же код

**ID:** NTF2-40 · E · положительный (замещает прежний NTF2-04)

**Given** свой человек П3; письмо подтверждения с кодом `K1` доставлено
**And** с его постановки прошло больше первой паузы (ручка Р8, значение печатается пробой), срок `K1`
не истёк

**When** `POST /iam/v1/auth/verify-email` с признаком вида `verify-email`

**Then** `200 {}`
**And** в пределах бюджета приёмник получает на тот же адрес второе письмо с кодом **`K1`**; `Message-ID`
двух писем различны
**And** предъявление `K1` даёт исход NTF2-02

#### Сценарий 41: после истечения кода повтор чеканит новый

**ID:** NTF2-41 · I · положительный · близнец — NTF2-40 (тот же запрос в срок кода)

**Given** П6; человек в положении подтверждения; строка ленты с кодом `K1` закрыта `SENT`
**And** часы переведены на срок `K1` + 1 с

**When** `POST /iam/v1/auth/verify-email`

**Then** `200 {}`; в ленте одна новая строка шаблона `verification` с кодом `K2 ≠ K1`
**And** предъявление `K1` — `401`, `code` `16`; предъявление `K2` — `200`

#### Сценарий 05: пауза держится при постановке — строки не ставится

**ID:** NTF2-05 · I · отрицательный · близнец (б)

**Given** П6; человек в положении подтверждения; письмо подтверждения поставлено в момент `T`;
первая пауза `P` — ручка Р8

**When** (а) `POST /iam/v1/auth/verify-email` в `T + P − 1 с`; (б) близнец — в `T + P`

**Then** (а) `429`, `code` `8`, `TOO_MANY_ATTEMPTS`, `Retry-After: 1`; новой строки в ленте kaname нет;
`notify` не открывает ни одной сессии с тестовым узлом
**And** (б) `200 {}`; в ленте одна новая строка шаблона `verification` с тем же кодом; `notify`
доставляет её, строка закрыта `SENT`, секретный атрибут пуст

#### Сценарий 42: приглашение ставится в ленту и доставляется без свободного текста

**ID:** NTF2-42 · E · положительный

**Given** П1; администратор П5 со своим аккаунтом `acc`; адрес `B = ntf2-42-<runId>@<домен приёмника
стенда>` не зарегистрирован
**And** в имени аккаунта `acc` стоит строка-маркер `M1`

**When** П5 вызывает `POST /iam/v1/users:invite` с payload:
  - `accountId` = `acc`
  - `email` = `B`
  - `displayName` = строка-маркер `M2`

**Then** ответ — `Operation`; поллинг `GET /operations/{id}` доходит до `done = true` без ошибки
**And** в пределах бюджета приёмник получает на `B` ровно одно письмо
**And** письмо называет приглашающего его **подтверждённым адресом** и аккаунт — идентификатором
`acc`
**And** ни `M1`, ни `M2` в письме нет — ни в `text/plain`, ни в `text/html`, ни в заголовках
**And** ссылка письма начинается с origin установки и несёт путь и одноразовый признак приглашения

#### Сценарий 43: восстановление: письмо с кодом, «ничего не делайте», код завершает

**ID:** NTF2-43 · E · положительный

**Given** П1; свой человек П2 с адресом `A`

**When** шаг 1: `POST /iam/v1/auth/recovery` с payload `email` = `A`, `csrfToken` формы `recovery`
**And** шаг 2: `POST /iam/v1/auth/recovery/complete` с `email` = `A`, `code` = код из письма,
`newPassword` = пароль, проходящий правила полосы, `csrfToken` формы `recovery-complete`

**Then** шаг 1: `200 {}` без печений; в пределах бюджета приёмник получает на `A` ровно одно письмо
`recovery`
**And** текст письма содержит «Если это были не вы — ничего не делайте»; ссылки-действия «это не я» в
письме нет
**And** шаг 2: `200`, выдана сессия, выставлено печенье метки устройства; вход прежним паролем — отказ
полосы формы
**And** в пределах бюджета приёмник получает на `A` письмо `recovery-completed` (S5); писем
`new-device-login` от ответа шага 2 до конца бюджета — 0 (Р12; близнец — вход NTF2-94)

#### Сценарий 06: чужое удостоверение сервера ленты kaname — письма нет, ответ глагола неизменен

**ID:** NTF2-06 · I · отрицательный · близнец — тот же запрос без П4 (строка `SENT`, `ResolveSend` не зван)

**Given** П6; человек в положении подтверждения; первая пауза по часам пробы прошла
**And** П4 применён: сервер ленты kaname предъявляет URI-SAN, отличный от записи `kaname` перечня
`notify`, с тем же DNS-SAN, который край сверяет с `ServerName`

**When** `POST /iam/v1/auth/verify-email`

**Then** ответ — `200 {}`, побайтово тот же, что у близнеца
**And** `notify` отвергает подключение к серверу ленты kaname: вызовов `Claim` на сервере ленты kaname 0,
тревога `source_identity_mismatch` поднята и называет источник `kaname`
**And** строка ленты шаблона `verification` остаётся `pending`, аренда по ней не выдана; тестовый узел
не получает ни одной сессии
**And** вызовов `ResolveSend` у kaname по пространству `kaname` 0
**And** близнец: без П4 тот же запрос даёт `200 {}`, строка закрыта `SENT`, тревоги
`source_identity_mismatch` нет, вызовов `ResolveSend` по пространству `kaname` 0 — пространство
`kaname` авторизует сертификат, а не решение на письмо (Р1, NTF-1 Р3)

#### Сценарий 07: notify лежит дольше срока — письмо истекает, лимит возвращается

**ID:** NTF2-07 · I · отрицательный · близнец — тот же запрос при работающем `notify` (`SENT`)

**Given** П6; `notify` не забирает строки ленты kaname
**And** `T_alarm` — половина наименьшего срока шаблонов класса `security` в собранных шаблонах
kaname; проба вычисляет его из сборки и печатает

**When** `POST /iam/v1/auth/recovery` для подтверждённого адреса, затем часы переводятся на
`T_alarm − 1 с`, `T_alarm` и `expires_at + 1 с`

**Then** ответ — `200 {}`, как при работающем `notify`
**And** на `T_alarm − 1 с` тревоги возраста строки класса `security` по ленте kaname нет, на `T_alarm` —
есть
**And** на `expires_at + 1 с` строка закрыта `EXPIRED(platform_unavailable)`, секретный атрибут пуст,
счётчик окна адресата уменьшен на единицу той же транзакцией
**And** после подъёма `notify` новый запрос принимается и доставляется, истёкшая строка — нет
**And** близнец: строка `SENT`, счётчик не уменьшен

#### Сценарий 08: шаблон класса security без лимитов — сборка красная

**ID:** NTF2-08 · G · отрицательный · близнец — шаблоны в дереве как есть

**Given** П8: копия дерева kaname, в которой из `notifications/recovery/notification.yaml` удалён
раздел `limits`

**When** запускается проверка шаблонов (`notifygen -check`) над копией

**Then** проверка падает; сообщение называет файл, поле `limits` и класс `security`
**And** близнец: над деревом kaname проверка зелёная и печатает число проверенных шаблонов — 24,
число шаблонов перечня Р3 (пары через «·» — два шаблона)

#### Сценарий 09: шаблона нет в сборке notify — строка не теряется

**ID:** NTF2-09 · I · отрицательный · близнец — сборка с шаблоном (`SENT`)

**Given** П6; сборка `notify` без шаблона `verification`; в ленте kaname строка этого шаблона в сроке

**When** `notify` забирает строку

**Then** строка не закрывается терминально: исход `DEFER`, счётчик `template_skew` растёт, тревога
поднимается сразу
**And** после подъёма `notify` со сборкой, несущей шаблон, строка закрыта `SENT` в пределах срока

#### Сценарий 44: отправителей SMTP в kaname нет, очереди писем нет

**ID:** NTF2-44 · G + I · отрицательный · близнец — инъекция П8

**Given** дерево kaname после посадки NTF-2
**And** П8: копия, в которую добавлен не-тестовый файл с импортом `net/smtp`

**When** гейт kaname «отправителей SMTP нет» разбирает импорты всех не-тестовых пакетов и граф
зависимостей `./cmd/kaname`
**And** integration-проба применяет все миграции kaname к пустой базе

**Then** на дереве: пакетов с импортом `net/smtp` — 0; в зависимостях `./cmd/kaname` нет `net/smtp`;
гейт печатает число разобранных пакетов (> 0)
**And** на копии П8: красный, находка называет файл и импорт
**And** после миграций таблицы `kaname.invite_mail_outbox` нет, а таблица ленты kaname есть

#### Сценарий 45: виды писем kaname совпадают с её шаблонами

**ID:** NTF2-45 · G · отрицательный (замещает MAIL-47) · близнец — дерево как есть

**Given** П8 в двух вариантах: (а) в `notifications/` добавлен шаблон, которого не зовёт ни одна
функция постановки; (б) из `notifications/` удалён шаблон `invite` при сохранённом вызове

**When** гейт сверяет множество шаблонов `notifications/` с множеством вызовов сгенерированных
функций постановки в не-тестовом дереве kaname

**Then** на дереве множества равны; гейт печатает оба числа
**And** (а) красный, находка называет шаблон без вызова; (б) сборка красная (`notifygen -check` и
компиляция), находка называет шаблон

#### Сценарий 46: ленту kaname забирает только notify

**ID:** NTF2-46 · I · отрицательный · близнец — вызов с сертификатом `notify`

**Given** П6; в ленте kaname одна строка в сроке
**And** клиент с проверенным сертификатом службы, отличной от `notify`

**When** этот клиент вызывает `Claim` ленты kaname на внутреннем слушателе

**Then** `PERMISSION_DENIED` (`code` `7`); строка остаётся `pending`, её аренда не выдана
**And** близнец: `Claim` с сертификатом `notify` выдаёт эту строку

#### Сценарий 47: манифест kaname выдаёт только чтение ленты notify и не заводит субъекта kaname

**ID:** NTF2-47 · G · отрицательный · близнец — манифест kaname как есть

**Given** П8 в двух вариантах копии встроенного манифеста kaname: (а) раздел `notifications` несёт
`namespace: kaname` рядом с `readers: [notify]`; (б) `readers` называет службу, отличную от `notify`
(`readers: [vpc]`)

**When** валидатор и применитель манифеста (NTF-1, Д3, Р3) обрабатывают копию

**Then** (а) — находка «у службы доступа служебного принципала нет (MRW-1 Р1)», называет строку
манифеста; кортежей не заведено ни одного
**And** (б) — находка называет строку манифеста и службу: объявить чтение ленты может только `notify`;
кортежей не заведено ни одного
**And** близнец: манифест kaname как есть несёт в разделе `notifications` только `readers: [notify]`;
принят; заведён ровно один кортеж `service:notify reader notification_feed:kaname`; кортежей с
субъектом `service:kaname` 0, с объектом `notification_namespace:kaname` 0; `TestMRW07_GroupWithItsGrantIsAccepted`
зелёный

#### Сценарий 48: ключ снятого почтового узла в конфигурации kaname — отказ старта

**ID:** NTF2-48 · I · отрицательный · близнец — та же конфигурация без ключа

**Given** конфигурация kaname базового профиля плюс один из снятых ключей (Р2, Р8), по варианту:
(а) `invite-mail.relay` со строкой-маркером; (б) `invite.mail-rate-limit.max-per-window`;
(в) `authn.login.verification-code-attempts`; (г) `authn.login.verification-resend-interval`

**When** kaname стартует

**Then** в каждом варианте старт отвергнут; сообщение называет добавленный ключ как неизвестный
**And** близнец: без этого ключа kaname стартует и проходит готовность

#### Сценарий 19: неподтверждённый не проходит дальше экрана подтверждения — рубеж нашей полосы

**ID:** NTF2-19 · E · отрицательный (рубеж, заменяющий MAIL-52; перенесён из прежнего S6 редакцией 14) · близнецы — те же запросы подтверждённого

**Given** П1
**And** человек П3 — адрес не подтверждён; близнец — человек П3, прошедший NTF2-02 (единственное
различие — предъявлен код); фактор второго шага ни у одного не заведён

**When** (а) неподтверждённый и (б) подтверждённый своей сессией вызывают через край
`GET /iam/v1/auth/second-factor`
**And** (в) неподтверждённый и (г) подтверждённый своей сессией вызывают `GET /iam/v1/projects`

**Then** (а) `403`, `code` `7`, `email address is not verified`, `details[].reason =
EMAIL_NOT_VERIFIED`; `Set-Cookie` нет; `GET /iam/v1/auth/me` той же сессией — `200`, `emailVerified:
false`
**And** (б) `200`, тело `{"totp": {"enrolled": false}}`
**And** (в) `403`, `code` `7`, тот же текст и `reason`, что в (а); `Set-Cookie` и `WWW-Authenticate` нет
**And** (г) `200`; `EMAIL_NOT_VERIFIED` в ответе нет

### S2 — флаг почты kaname

#### Сценарий 50: флаг не задан — kaname не стартует

**ID:** NTF2-50 · I · отрицательный · близнецы — флаг `true` и флаг `false`

**Given** конфигурация kaname базового профиля без ключа `notifications.enabled`

**When** kaname стартует

**Then** старт отвергнут; сообщение называет ключ `notifications.enabled`
**And** близнецы: с `true` и с `false` kaname стартует и проходит готовность

#### Сценарий 51: флаг выключен — действия, которым нужна почта, получают явный отказ, одинаковый для любого адреса

**ID:** NTF2-51 · I · отрицательный · близнец — те же запросы на П6 (флаг `true`)

**Given** П6-off; подтверждённый человек с адресом `A` посевом П10 (фикстура П6: учётная запись есть,
глаголов почты не было); адрес `Z` не принадлежит никому; фикстурой П11 — человек в положении
подтверждения со своей сессией и аккаунт `acc` с администратором, от имени которого идут (г) и (з)

**When** (а) `POST /iam/v1/auth/recovery` с `email` = `A`; (б) то же с `email` = `Z`;
(в) `POST /iam/v1/auth/register` с `email` = `Z` и годным паролем; (г) `POST /iam/v1/users:invite` с
`accountId` = `acc`, `email` = `Z`; (д) `POST /iam/v1/auth/verify-email` сессией человека в положении
подтверждения; (е) `POST /iam/v1/auth/register` с `email` = `Z` и паролем короче правила полосы;
(ж) `POST /iam/v1/auth/register` с `email` = `A` и тем же годным паролем, что в (в); (з)
`POST /iam/v1/users:invite` с `accountId` = `acc`, `email` = `A`

**Then** (а)–(д), (ж), (з) — каждый `400` (отображение `FAILED_PRECONDITION` таблицей края); `code`,
`message` и `details` тела равны полям статуса, который возвращает `feed.DeliveryNotConfiguredStatus()`
corelib на пине `go.mod` kaname: `code` — его код, `message` — его текст, `details` — его `ErrorInfo`
(`reason`, `domain`, `metadata`) в том же порядке. Ожидаемое проба получает вызовом этой функции, а не
своим литералом, и печатает его вместе с версией пина; пин модуля пробы, отличный от пина kaname, —
«не выполнилось»
**And** ожидаемое совпадает с объявленным NTF-1: `code` `9`, текст `email delivery is not configured in
this installation`, `ErrorInfo{reason: NOTIFICATION_DELIVERY_NOT_CONFIGURED}`; расхождение — красный с
обоими значениями (текст corelib сменился мимо приёмки)
**And** что отказ производит только corelib, эта проба не утверждает: копия того же статуса в kaname
здесь зелёная. Это утверждает гейт NTF2-54
**And** ответы (а) и (б) побайтово равны; ответы (в) и (ж) побайтово равны; ответы (г) и (з) побайтово
равны: занятость адреса не меняет отказа ни у одного действия, принимающего адрес
**And** (г) и (з) отказывают синхронно: `Operation` не заведена, строки приглашения нет
**And** писем на `A` и `Z` 0; учётная запись `A` не изменилась
**And** (е) — `400`, `code` `3`, текст называет поле `password` и правило; `NOTIFICATION_DELIVERY_NOT_CONFIGURED` в
ответе нет: правила пароля идут первыми и при выключенном флаге (Р9)
**And** строк в ленте kaname 0
**And** близнец: на П6 (флаг `true`, тот же посев) (а), (б), (в), (ж) — `200 {}`, ответы (а) и (б) побайтово
равны, (в) и (ж) побайтово равны; (г), (з) — `Operation`; (д) — `200 {}`; (е) — тот же отказ о пароле

#### Сценарий 52: флаг выключен — ноль строк, сервер ленты не поднят, метрика 0

**ID:** NTF2-52 · I · отрицательный · близнец — П6 (флаг `true`)

**Given** П6-off; фикстурой П11: аккаунт `acc` с владельцем `O` и проектом; пользователь `U` в `acc`
(ACTIVE, адрес подтверждён) со своей сессией

**When** проба исполняет глаголы, порождающие события из перечня Р3: смена пароля `U` его сессией,
выдача роли на проект `acc` пользователю `U` (не группе) от имени `O`, выпуск токена пользователя `U`
**And** вызывает `Claim` ленты kaname сертификатом `notify`
**And** читает метрики kaname

**Then** глаголы исполнены: `200` или `Operation` с `done = true` без ошибки; строки аудита есть
**And** строк в ленте kaname 0
**And** `Claim` — `UNIMPLEMENTED` (`code` `12`): сервер ленты не зарегистрирован
**And** `kaname_notifications_enabled` = `0`
**And** близнец: на П6 (флаг `true`, та же фикстура) те же глаголы дают по одной строке ленты на
событие — адресат каждой строки `U` (Р3: `password-changed`, `role-granted`, `user-token-issued`), `Claim`
выдаёт строки, метрика = `1`

#### Сценарий 53: флаг в зонтике — одно объявление, из него выводится перечень источников notify

**ID:** NTF2-53 · G · отрицательный · близнец — рендер цепочки `dev` как есть

**Given** П7 в трёх вариантах цепочки `dev`: (а) `global.kacho.notifications.enabled` снят;
(б) `global.kacho.notifications.enabled: true` и `kaname.notifications.enabled: false`;
(в) `global.kacho.notifications.enabled: false`

**When** рендер и гейт рендера читают конфигурацию kaname и перечень источников `notify`

**Then** (а) рендер отказывает; сообщение называет ключ `global.kacho.notifications.enabled`
**And** (б) у kaname `notifications.enabled: false`; источника kaname в перечне `notify` нет
**And** (в) у kaname `false`; источника kaname в перечне `notify` нет
**And** близнец: в рендере `dev` у kaname `true`, и в перечне источников `notify` ровно одна запись
kaname — с `authorization: certificate` и SAN из `kaname.spiffe` (Р1); гейт печатает число источников
перечня и число модулей с флагом `true`, и они равны

#### Сценарий 54: отказ флага производит только corelib — своей копии у kaname нет

**ID:** NTF2-54 · G · отрицательный · близнец — дерево kaname как есть и копия (г)

**Given** П8 в четырёх вариантах копии дерева kaname: (а) в не-тестовый файл пакета
`internal/apps/kaname/api/humansession` добавлен строковый литерал `email delivery is not configured in
this installation`; (б) в не-тестовый файл пакета `internal/apps/kaname/api/registration` добавлен
литерал `NOTIFICATION_DELIVERY_NOT_CONFIGURED`; (в) у действия приглашения
(`InviteUserUseCase.Execute`, `internal/apps/kaname/api/user/invite.go`) путь выключенного флага
отвечает `FAILED_PRECONDITION` без ссылки на `feed.DeliveryNotConfiguredStatus`, литералов отказа в
копии нет; (г) литерал `NOTIFICATION_DELIVERY_NOT_CONFIGURED` добавлен в файл `_test.go` того же пакета,
что в (б)

**When** гейт kaname «единый отказ флага» (`internal/check`) разбирает не-тестовые Go-файлы дерева с
проверкой типов. Узлы: (1) строковый литерал, содержащий текст отказа или его `reason`; (2) ссылка на
объект `feed.DeliveryNotConfiguredStatus` пакета `corelib notify/feed` по идентичности из проверки
типов; (3) для каждого действия закрытого перечня гейта — запрос кода восстановления
(`RequestRecoveryUseCase.Execute`), регистрация (`RegisterUseCase.Execute`), приглашение
(`InviteUserUseCase.Execute`), запрос кода подтверждения (`RequestVerificationUseCase.Execute`) —
достижимость узла (2) из метода действия по статическому графу вызовов дерева kaname

**Then** (а), (б) — красные; находка называет файл, строку и литерал
**And** (в) — красный; находка называет действие `InviteUserUseCase.Execute`, до которого ссылка на
функцию не достигается
**And** действие перечня, которого в дереве нет, — красный с его именем, а не пропуск: перечень
правится тем же изменением, что переименование
**And** пустой обход — красный
**And** близнец: на дереве kaname находок 0; гейт печатает число осмотренных файлов (> 0), число
литералов узла (1) — 0, число ссылок узла (2) с координатой каждой (≥ 1) и для каждого из четырёх
действий путь до ссылки; на копии (г) находок тоже 0: пробы вправе утверждать литерал
**And** граница узла (1), названная гейтом: текст, собранный из фрагментов, узел не видит. Такой
текст держит NTF2-51 только при расхождении с corelib; копию, совпавшую побайтово, — узел (3): у
действия, собравшего отказ сам, пути до функции нет

### S3 — анонимные почтовые глаголы: лимиты и защита от спама

#### Сценарий 60: лестница края по источнику — три ступени, одинакова для любого адреса

**ID:** NTF2-60 · I · отрицательный · близнецы — (б) тот же ряд при `POW` = `HARD`; запросы с другого
источника в пределах порога «без проверки»; в (в) — запрос в момент окна, отличный на 1 с

**Given** П6; ручки края источника — без проверки `F`, повышенная ступень с `P`, жёсткий порог `H` и их
окна — и сложности `Db` = `POW_BITS_BASE`, `Dh` = `POW_BITS_HIGH` печатаются пробой; профиль П6 задаёт `F < P < H`
(ориентиры Р8), иначе исход «не выполнилось»; `Db < Dh` держит страж (Р8)
**And** источник `S1`; подтверждённый адрес `A` (П11), адрес `Z`, которого нет
**And** ряд идёт с темпом ниже общего потока края и укладывается в наименьшее из окон ручек источника
(часы пробы); проба печатает длительность ряда, и ряд, не уложившийся в окно, — исход «не выполнилось»
**And** для (в): окна ручек `FREE`, `POW`, `HARD` — `W_F`, `W_P`, `W_H` (Р5) печатаются пробой; запросы
построения (в) идут в один момент `t1` часов пробы (часы стоят); вызов общего потока, если он выдан при
построении, решается доказательством; в (в1) `F ≤ BURST` (печатается, иначе «не выполнилось»)

**When** (а) с `S1` идут запросы `POST /iam/v1/auth/recovery`, чередуя `A` и `Z`; каждый запрос сначала
идёт без доказательства, и получивший вызов повторяется с верным доказательством к этому вызову; ряд
идёт, пока звено не пропустило `H` запросов, затем ещё один запрос без доказательства
**And** (б) близнец, отдельный повтор пробы на копии П6, где `POW` = `H` (в границах Р8), остальное то же:
тот же ряд
**And** (в) окна ручек, три отдельных повтора пробы с источника `S3`, `email` = `Z`: (в1) звено пропустило
`F` запросов в `t1`; затем по одному запросу без доказательства в `t1 + W_F − 1 с` и в `t1 + W_F`;
(в2) звено пропустило `P` запросов в `t1`; затем запросы без доказательства в `t1 + W_P − 1 с` и в
`t1 + W_P`; (в3) звено пропустило `H` запросов в `t1`; затем запросы без доказательства в
`t1 + W_H − 1 с` и в `t1 + W_H`. Запрос, получивший вызов или отказ, в счёт не входит (Р5), поэтому оба
момента идут в одном повторе

**Then** (а) запросы, пропущенные звеном с номерами 1…`F`, — `200 {}` без вызова
**And** запрос с номером `n` при `F < n ≤ P` сначала получает `429`, `code` `8`, `proof of work required`,
`reason: PROOF_OF_WORK_REQUIRED`, в `metadata` — `challenge`, `difficultyBits` = `Db`, `expiresAt`;
повтор с доказательством — `200 {}`
**And** запрос с номером `n` при `P < n ≤ H` — тот же вызов, но `difficultyBits` = `Dh`; повтор с
доказательством — `200 {}`
**And** запрос сверх `H` — `429`, `code` `8`, `too many requests`, `reason: RATE_LIMITED`, `Retry-After` —
целое число секунд > 0
**And** проба печатает `difficultyBits` по номеру запроса: `Db` ровно у номеров `F + 1`…`P`, `Dh` ровно у
номеров `P + 1`…`H`
**And** каждый из `H` запросов, пропущенных звеном, дошёл до kaname и получил `200 {}`: отказа kaname по
источнику на этом пути нет — ось источника только у края (Р5, §3); проба печатает `H` и значение
`authn.login.source-attempts` профиля П6, и при `H ≤ source-attempts` исход ряда — «не выполнилось»:
ряд не различил бы снятое окно и оставшееся
**And** на каждой ступени ответы для `A` и `Z` равны в смысле §6, без значений `metadata.challenge` и
`metadata.expiresAt`, которые у каждого вызова свои
**And** (б) у всех вызовов ряда `difficultyBits` = `Db`, запрос сверх `H` — тот же `RATE_LIMITED`: ступень
повышенной сложности задаёт ручка `POW`, и только она
**And** (в1) в `t1 + W_F − 1 с` — вызов с `difficultyBits` = `Db`; в `t1 + W_F` — `200 {}` без вызова
**And** (в2) в `t1 + W_P − 1 с` — вызов с `difficultyBits` = `Dh`; в `t1 + W_P` — ответ без `Dh`: вызов с `Db`
или `200 {}` без вызова, по счёту окна `FREE` в этот момент, который проба печатает
**And** (в3) в `t1 + W_H − 1 с` — `RATE_LIMITED`; в `t1 + W_H` — не `RATE_LIMITED`
**And** близнец: `F` запросов с другого источника `S2` — `200 {}` без вызова

#### Сценарий 61: ось подсети

**ID:** NTF2-61 · I · отрицательный · близнец — те же адреса из разных подсетей

**Given** П6; ручки подсети: PoW с `Ps`, жёсткий `Hs` — для каждой длины префикса свои (Р8), печатаются
пробой
**And** (а) IPv4-источники из одной `/24`; (б) IPv6-источники из одной `/56`, каждый из своей `/64`;
(в) IPv6-источники из одной `/48`, каждый из своей `/56`

**When** из каждого набора идут запросы `POST /iam/v1/auth/register`, каждый источник — не больше
своего порога «без проверки»
**And** (г) окна подсети, два отдельных повтора для каждого набора (а)–(в): окна ручек подсети `W_Ps`,
`W_Hs` печатаются пробой; профиль П6 — `Ps < Hs` (печатается, иначе «не выполнилось»); в момент `t1`
(часы стоят) звено пропустило из подсети `Ps` запросов (первый повтор) или `Hs` (второй; получившие
вызов повторяются с доказательством, вызов общего потока решается так же); затем запрос с нового
источника той же подсети в `t1 + W_Ps − 1 с` и `t1 + W_Ps` (первый повтор) или в `t1 + W_Hs − 1 с` и
`t1 + W_Hs` (второй)

**Then** сверх `Ps` пропущенных на подсеть — вызов PoW с `difficultyBits` = `POW_BITS_BASE` (счёт
каждого источника ниже его `POW`, Р5); получивший вызов повторяется с доказательством и пропускается;
сверх `Hs` пропущенных — `429` `RATE_LIMITED` с `Retry-After`
**And** (г) в `t1 + W_Ps − 1 с` — вызов PoW; в `t1 + W_Ps` — `200 {}` без вызова; в `t1 + W_Hs − 1 с` —
`RATE_LIMITED`; в `t1 + W_Hs` — не `RATE_LIMITED`
**And** близнец: столько же запросов из разных `/24` (разных `/48` для IPv6) — `200 {}` без вызова

#### Сценарий 62: доказательство проверяется краем

**ID:** NTF2-62 · I · отрицательный · близнец — верное доказательство

**Given** П6; источник получил вызов `C`

**When** повтор запроса с (а) `nonce`, не дающим `difficultyBits` нулевых битов; (б) доказательством к
вызову с истёкшим `expiresAt`; (в) верным доказательством к `C`, уже использованным один раз;
(г) вызовом, изменённым в одном знаке

**Then** (а)–(г): `429`, `code` `8`, `reason: PROOF_OF_WORK_REQUIRED` с новым вызовом; запрос до kaname
не доходит (строк в ленте 0, счётчик kaname не изменён)
**And** близнец: верное доказательство к `C`, использованное впервые, — `200 {}`

#### Сценарий 63: ограничитель действует только на анонимные почтовые глаголы

**ID:** NTF2-63 · I · положительный · близнец — NTF2-60 (почтовый глагол с того же источника)

**Given** П6; источник `S1` исчерпал жёсткий порог (исход NTF2-60)
**And** подтверждённый человек `A` (П11) с живым кодом восстановления `K`, полученным с другого
источника; ожидающая регистрация свободного адреса `F` с паролем `P` и кодом `Kr`

**When** с `S1` идут `POST /iam/v1/auth/login` человека `A`, `GET /iam/v1/auth/csrf` и
`GET /iam/v1/projects` его сессией
**And** с `S1` — пути предъявления кода: `POST /iam/v1/auth/recovery/complete` с `email` = `A` и кодом,
отличным от `K`; `POST /iam/v1/auth/register/confirm` с `email` = `F`, `password` = `P` и кодом,
отличным от `Kr`

**Then** вход, `csrf` и `projects` — исходы этих путей без ограничителя: `200` у каждого
**And** оба предъявления доходят до kaname: `401`, `code` `16`, `authentication failed`
**And** ни в одном ответе нет вызова PoW и `RATE_LIMITED`
**And** близнец: `POST /iam/v1/auth/recovery` и `POST /iam/v1/auth/register` с `S1` — `429` `RATE_LIMITED`

#### Сценарий 59: хранилище ограничителя недоступно — `503`, до kaname запрос не доходит

**ID:** NTF2-59 · I · отрицательный · близнец — те же запросы при исправном хранилище (пропуск)

**Given** П6, своя копия стенда пробы; хранилище ограничителя края — база в контейнере пробы
(вид хранилища, допускающий флот из нескольких реплик); подтверждённый адрес `A` (П11), адрес `Z`,
которого нет; источник `S4` с пустым счётом, темп ниже общего потока; часы пробы стоят
**And** до остановки хранилища источник `S6` прошёл порог «без проверки» (NTF2-60 (а)) и получил вызов
`C`; проба нашла решение `C` и не предъявляла его
**And** хранилище ограничителя остановлено; проба печатает, что соединение с ним отвергнуто

**When** с `S4` без доказательства: (а) `POST /iam/v1/auth/recovery` с `email` = `A`; (б) то же с
`email` = `Z`; (в) `POST /iam/v1/auth/register` с `email` = `Z` и годным паролем
**And** (г) с `S6`: `POST /iam/v1/auth/recovery` с `email` = `Z` и заголовком `X-Kacho-Proof` с верным
решением `C`

**Then** (а)–(г) — каждый `503`, `code` `14`, текст `request limiter is unavailable`, `details` пуст
**And** ответы (а) и (б) побайтово равны; ответы (а) и (в) побайтово равны: ответ не зависит ни от
адреса, ни от пути
**And** kaname не получил ни одного из четырёх запросов: счётчик запросов полосы формы kaname по этим
путям не изменился, строк в ленте kaname 0, окна адресатов `A` и `Z` не изменились
**And** (г) — не пропуск: доказательство, одноразовость которого проверить нельзя, свежим не считается
**And** `kacho_api_gateway_anon_mail_store_unavailable_total` вырос ровно на 4
**And** (д) хранилище поднято в том же прогоне, часы стоят: `S6` предъявляет решение `C` к `POST
/iam/v1/auth/recovery` с `email` = `Z` — `200 {}`: `503` не истратил вызов
**And** близнец — отдельный прогон на своей копии П6 с тем же посевом, отличается ровно одним фактом:
хранилище исправно. Те же запросы (а)–(в) с того же `S4` — `200 {}` без вызова, ответы (а) и (б)
побайтово равны; (г) с `S6` с решением `C` — `200 {}`; метрика недоступности не изменилась

#### Сценарий 64: рубеж kaname на адресата — тот же код, паузы, потолки, ответ один

**ID:** NTF2-64 · I · отрицательный · близнец — тот же ряд для адреса `Z`, которого нет

**Given** П6; запросы ряда идут с разных источников из разных подсетей, каждый ниже порога «без
проверки» края — ряд судит только рубеж kaname; подтверждённый адрес `A`; ручки адресата `recovery` Р8 печатаются пробой; ряд моментов строится из ручек по Р6: `t0`,
`t0 + first-pause − 1 с`, `t0 + first-pause`, `+ second-pause − 1 с`, `+ second-pause`, далее до
часового потолка; затем **часовая граница** — `u + 1 ч − 1 с` и `u + 1 ч`, где `u` — момент самой ранней
строки часового окна при первом `capped` по часовому потолку; далее до суточного потолка
**And** проба печатает ряд и множество моментов, разрешённых прогрессией (Р6); условие часовой
границы — `per-hour < per-day` и в `u + 1 ч` вторая пауза от прошлой строки прошла; оно печатается,
иначе исход «не выполнилось» (в базовом профиле строки в `t0`, `t0 + 60 с`, `t0 + 6 мин`, `u = t0`)

**When** в каждый момент ряда идёт `POST /iam/v1/auth/recovery` с `email` = `A`

**Then** каждый ответ — `200 {}`, побайтово один и тот же
**And** в каждом моменте, разрешённом прогрессией, — ровно одна строка ленты `recovery`, в прочих — ни
одной; их число за час не больше `per-hour`, за сутки не больше `per-day` (строка `mail-throttled` первого
исхода `capped` — предмет NTF2-68, в этот счёт не входит)
**And** часовая граница: в `u + 1 ч − 1 с` строки нет, исход `capped`; в `u + 1 ч` — одна строка: часовое
окно отпустило строку `u`
**And** пока первый код жив, каждая строка `recovery` несёт **тот же** код
**And** `kaname_mail_intents_total{verb="recovery"}` увеличен ровно по одному исходу на запрос:
`queued`, `resent_same`, `cooldown`, `capped`
**And** близнец: для `Z` ответы побайтово равны ответам для `A`; строк ленты 0; строки счётчика для
`Z` не заведено

#### Сценарий 65: «пол» — лимит не отрезает владельца

**ID:** NTF2-65 · I · положительный · близнец — момент до истечения интервала пола

**Given** П6 после NTF2-64: `Tc` — момент письма прогрессии, которым ряд исчерпал суточное окно
адреса `A`, `Tw` — момент, когда окно отпускает строку (Р6, «пол при скользящих окнах»); самое раннее
письмо ряда — `t0`, ряд короче суток, поэтому `Tw = t0 + 1 сут`; интервал пола `Fl`
**And** условие (а, б): `Tc + Fl < Tw`, то есть `t0 + 1 сут > Tc + Fl`; `Tc`, `Tw` и условие печатаются,
иначе исход (а, б) «не выполнилось» (в базовом профиле `Tc + Fl = t0 + 7 ч 5 мин`); (в) лежит в
исчерпании при любом профиле: `Tc + 1 с < Tc + Fl` (`Fl ≥ 1 ч`, Р8) и `Tc + 1 с < Tw`
**And** `K1` — код строки, поставленной в `Tc`; `Tk1` — момент строки, которой `K1` отчеканен (Р6);
срок кода `Tr` = `authn.login.recovery-code-ttl`; `Fl`, `Tr`, `Tk1` печатаются пробой

**When** `POST /iam/v1/auth/recovery` с `email` = `A` в (в) `Tc + 1 с`, (а) `Tc + Fl − 1 с` и (б) `Tc + Fl`
**And** (г) граница суток, отдельный повтор пробы на копии П6, где `…recovery.floor-interval` = 24 ч
(граница Р8): ряд NTF2-64 с началом `t0`, затем запросы в `t0 + 1 сут − 1 с` и `t0 + 1 сут`; здесь
`Tw = t0 + 1 сут` и `Tc + 24 ч ≥ Tw` — пола в исчерпании нет (Р6); условие — в `t0 + 1 сут` часовое окно
пусто, то есть `Tc ≤ t0 + 23 ч`; `Tc` и условие печатаются, иначе «не выполнилось»

**Then** (в) `200 {}`, строки `recovery` нет, исход `capped`, а не `cooldown`: пауза от письма `Tc` не
прошла, но потолок старше паузы (Р6)
**And** (а) `200 {}`, строки `recovery` нет, исход `capped`
**And** (б) `200 {}`; одна строка `recovery`, исход `floor`; письмо доставлено, код в нём рабочий:
`recovery/complete` с ним — `200`
**And** код письма пола — новый `K2 ≠ K1`, если `Tk1 + Tr ≤ Tc + Fl` (в базовом профиле — 15 мин против
6 ч), и тогда `K1` в `recovery/complete` — `401`, `code` `16`; иначе — тот же `K1` (живой код не меняется,
Р6); проба печатает, какая ветвь выполнена
**And** за любые сутки строк восстановления для `A` не больше `per-day` + ⌈24 ч / `Fl`⌉
**And** (г) в `t0 + 1 сут − 1 с` — `200 {}`, строки нет, исход `capped`: окно исчерпано, а пола в этом
исчерпании нет (`Tc + 24 ч ≥ Tw`); в `t0 + 1 сут` — `200 {}`, одна строка `recovery`, исход `queued` или
`resent_same`, а не `floor`: в `Tw` окно отпустило строку `t0`, прогрессия возобновилась, часовое окно
пусто — письмо первое по номеру (Р6)

#### Сценарий 66: неверные предъявления код не гасят; перебор держат оси

**ID:** NTF2-66 · I · отрицательный · близнец — верный код после неверных

**Given** П6; подтверждённый адрес `A` (П11) с живым кодом восстановления `K`; ручки перебора Р8
печатаются пробой: `N` = `address-source-per-window`, `W` = `window`, `Cf` = `address-failure-ceiling`;
все запросы ряда — с устройств без метки, кроме названного
**And** для варианта регистрации — ожидающая регистрация свободного адреса `F` с паролем `P` и кодом
`Kr` (исход NTF2-80 шаг 1 на П6)

**When** (а) с источника `S1` `N` раз `POST /iam/v1/auth/recovery/complete` для `A` с неверным кодом;
затем запрос с `K` с того же `S1`; затем с `K` с источника `S2`
**And** (б) тот же ряд на `POST /iam/v1/auth/register/confirm` для `F` с паролем `P`: `N` неверных кодов
с `S1`, затем `Kr` с `S1`, затем `Kr` с `S2`
**And** (в) потолок адреса, отдельный повтор пробы: подтверждённый адрес `A'` (П11) с живым кодом
`K3`; начиная с момента `Tf` в пределах окна `W` идут `Cf` неверных предъявлений с разных источников
`S3…`, каждый ниже `N`; затем `K3` с нового источника без метки и `K3` с устройства с меткой владельца
(Р12)
**And** (г) истечение потолка, отдельный повтор пробы: ряд (в) до `Cf` неверных включительно, без
предъявлений с меткой; часы переводятся на `Tf + W − 2 с`, запрашивается код для `A'` — `K4` (равен `K3`, если `K3` ещё жив, Р6); `K4` предъявляется с нового источника без метки в
`Tf + W − 1 с` и, во втором повторе, в `Tf + W`
**And** (д) окно оси «адрес + источник», отдельный повтор пробы: подтверждённый адрес `A''` (П11);
`N` неверных предъявлений с `S1` в момент `Tf` (часы стоят; `N < Cf`, печатается); часы переводятся на
`Tf + W − 2 с`, запрашивается код для `A''` — `K5`; `K5` предъявляется с `S1` в `Tf + W − 1 с` и, во
втором повторе, в `Tf + W`

**Then** (а) и (б): первые `N` — `401`, `code` `16`, `authentication failed`; предъявление верного кода с
`S1` — отказ по частоте полосы формы (Ф5-08: тот же статус, `code` и текст для адреса, которого нет);
верный код с `S2` — `200`: в (а) сессия выдана, в (б) учётная запись заведена — код жив после `N`
неверных предъявлений
**And** (в) `K3` с нового источника без метки — тот же отказ по частоте; `K3` с устройства с меткой — `200`
**And** (г) в `Tf + W − 1 с` — тот же отказ по частоте; в `Tf + W` — `200`: потолок истёк вместе с
окном, отсчитанным от первой неудачи
**And** (д) в `Tf + W − 1 с` — тот же отказ по частоте; в `Tf + W` — `200`: окно оси истекло
**And** близнец: с `S2` сразу `K` — `200`

#### Сценарий 67: ответ не ждёт постановки — время ответа не раскрывает адрес

**ID:** NTF2-67 · I · отрицательный · близнец — тот же запрос без блокировки

**Given** П6; запись в таблицу ленты kaname заблокирована на 10 с посторонней транзакцией пробы
**And** подтверждённый адрес `A`, адрес `Z`, которого нет

**When** `POST /iam/v1/auth/recovery` с `A`, затем с `Z`

**Then** оба ответа — `200 {}` побайтово равны и получены раньше снятия блокировки, каждый в
пределах 1 с
**And** после снятия блокировки строка для `A` в ленте появилась, для `Z` — нет
**And** близнец: без блокировки ответы те же

#### Сценарий 68: письмо «мы притормозили» — раз в интервал, сверх окна, без ссылок, только существующему адресу

**ID:** NTF2-68 · I · положительный · близнецы — исходы `capped` того же ряда в пределах интервала;
(б): исход `capped` в `Ts + Ti − 1 с`

**Given** П6; подтверждённый адрес `A` (П11); адрес `Z`, которого нет; ручки окна `recovery` Р8 и
интервал письма о торможении `Ti` = `mail-throttled-interval` печатаются пробой
**And** источники ряда — как в NTF2-64: каждый запрос ниже порога «без проверки» края

**When** (а) ряд NTF2-64 для `A` до суточного потолка: `Tc` — момент письма прогрессии, которым окно
исчерпано, `Tw` — момент, когда окно отпускает строку (Р6), и затем запросы в `Tc + 1 с`, `Tc + 2 с` и
`Tc + Fl − 1 с`; условие — `Tc + Fl ≤ Tw`, все три момента в исчерпании `[Tc, Tw)` и раньше пола;
печатается, иначе «не выполнилось» (в базовом профиле `Tc + Fl = t0 + 7 ч 5 мин`, `Tw = t0 + 1 сут`);
`Ts` — момент первого запроса
ряда с исходом `capped` (печатается пробой; `Ts ≤ Tc + 1 с`, так как запрос в `Tc + 1 с` — `capped`,
NTF2-65 (в))
**And** условие (а): последний запрос (а) раньше `Ts + Ti`, то есть `Tc + Fl − 1 с < Ts + Ti`; оба момента
печатаются, иначе исход «не выполнилось» (в базовом профиле — около 7 ч против 7 сут)
**And** (б) граница интервала: часы переводятся на момент `s`; с `s` для `A` идут `per-hour` писем окна
`recovery` по паузам Р6 и затем запрос через 1 с после последнего из них; `s` выбран так, что этот
запрос — в `Ts + Ti − 1 с`; затем запрос в `Ts + Ti`. Условие (б): окна `A` в `s` пусты, а самая ранняя
строка ряда (б) позже `Ts + Ti − 1 ч` — часовое окно исчерпано в обоих моментах; `s` и условие
печатаются, иначе «не выполнилось»
**And** (в) тот же ряд (а) и (б) для `Z`

**Then** (а) строк `mail-throttled` для `A` — ровно одна, поставлена в `Ts` тем же запросом, чей исход
`capped`; в письме нет ни одной ссылки-действия; строк окна `recovery` после `Tc` не прибавилось: письмо
о торможении окна не расходует
**And** исходы всех запросов (а) после `Tc` — `capped`; метрика `kaname_mail_intents_total{verb="recovery"}`
прибавила `capped` по одному на запрос, а строк `mail-throttled` сверх первой нет (близнец: тот же исход
`capped`, но с прошлой строки прошло меньше `Ti`)
**And** (б) в `Ts + Ti − 1 с` — исход `capped`, новой строки `mail-throttled` нет: с прошлой прошло
`Ti − 1 с`; в `Ts + Ti` — исход `capped` и одна новая строка `mail-throttled` для `A`; всего за пробу их две
**And** (в) строк для `Z` 0 — ни `recovery`, ни `mail-throttled`

#### Сценарий 69: потолки приглашений

**ID:** NTF2-69 · I · отрицательный · близнец — приглашение в пределах потолков

**Given** П6-age: `mature` — возраст ровно `Ya` (не моложе порога), `young` — `Ya − 1 с` (моложе), у каждого
администратор; ручки приглашений Р8 печатаются пробой; на П6 `invite.pending-max` больше
`account-per-day` (в границах Р8; печатается, иначе «не выполнилось»)
**And** адрес `C`; аккаунты `B1…Bk` (П11) с администраторами, `k` = ⌊`recipient-per-day-all` /
`recipient-per-day`⌋ + 1 (печатается)
**And** (а), (б), (в) — отдельные повторы пробы; в (а) и (б) часы пробы стоят в `T + Ya`

**When** (а) `young` приглашает разные адреса сверх `young-account-per-day`; (б) `mature` — сверх
`account-per-day`
**And** (в) `B1…Bk` приглашают `C`, каждый не больше своего `recipient-per-day`, разнося приглашения
по часам так, что часовой потолок не срабатывает, пока строк `invite` для `C` не станет
`recipient-per-day-all`; `t1` — момент первой из них; затем аккаунт, чьи свои потолки на `C` не
исчерпаны, приглашает `C`; ряд укладывается в `[t1, t1 + 1 сут − 1 с)` (печатается)
**And** (г) граница суток потолка аккаунта: после (б) часы переводятся на `T + Ya + 1 сут − 1 с`, затем
на `T + Ya + 1 сут`; в каждый момент `mature` приглашает новый адрес. То же для `young'` — аккаунта
П11, заведённого в `T + Ya` и моложе порога во всё время (г) при `Ya > 1 сут` (печатается, иначе
«не выполнилось»): ряд (а) в `T + Ya`, затем те же два момента
**And** (д) граница суток по адресату поперёк аккаунтов: после (в) аккаунт с неисчерпанными своими
потолками на `C` приглашает `C` в `t1 + 1 сут − 1 с` и в `t1 + 1 сут`

**Then** (а) и (б): запрос сверх потолка — `429`, `code` `8`, `invitation limit of the account is
exhausted`, `reason: INVITATION_RATE_LIMITED`, `Retry-After` > 0; `Operation` не заведена
**And** в (а) отказ наступает на `young-account-per-day + 1`, в (б) — на `account-per-day + 1`
**And** (в): каждое приглашение — `Operation` с `done = true`; строк ленты `invite` для `C` —
`recipient-per-day-all`; последнее приглашение — строка приглашения заведена, письма нет, исход `capped`
в метрике
**And** (г) в `T + Ya + 1 сут − 1 с` — тот же отказ `INVITATION_RATE_LIMITED`; в `T + Ya + 1 сут` —
`Operation` с `done = true` и строка `invite`: суточное окно отпустило приглашения момента `T + Ya`; у
`young'` — то же
**And** (д) в `t1 + 1 сут − 1 с` — `Operation`, строки нет, исход `capped`; в `t1 + 1 сут` — строка `invite`
**And** близнец: приглашение в пределах всех потолков — `Operation` и строка `invite`

#### Сценарий 70: доверенное устройство — свой запас владельца

**ID:** NTF2-70 · I · положительный · близнец — устройство без метки

**Given** П6; подтверждённый человек `A` (П11) раньше вошёл с устройства `D1` и получил метку
**And** суточный потолок адресата `A` исчерпан чужими запросами без метки — ряд NTF2-64; `Tc` — момент
письма прогрессии, которым окно исчерпано, `Tw` — момент, когда окно отпускает строку (Р6); `Fl`, `Tw` и
`R` = `trusted-device.recovery-per-day` печатаются пробой

**When** в момент `Tc + 1 с` — в исчерпании `[Tc, Tw)` и раньше пола `Tc + Fl`: `Fl` ≥ 1 ч (Р8), а
`Tw = t0 + 1 сут` позже `Tc + 1 с`, так как ряд NTF2-64 короче суток:
(а) `R + 1` запросов `POST /iam/v1/auth/recovery` с `email` = `A` и меткой `D1`, один за другим;
(б) тот же запрос без метки
**And** (в) граница суток запаса: после (а) и (б), где `t1 = Tc + 1 с`, проба ведёт письма окна `recovery`
для `A` без метки так, что в обоих моментах `t1 + 1 сут − 1 с` и `t1 + 1 сут` исход запроса без метки по
Р6 — `capped`: часовое окно исчерпано, а суточное либо не исчерпано, либо исчерпано и момент лежит в
`[Tc', Tw')` раньше `Tc' + Fl`, где `Tc'`, `Tw'` — символы Р6 для этого исчерпания. Счёт писем прогрессии
в часовом и суточном окне в обоих моментах, а при исчерпании суточного — `Tc'`, `Tw'` и `Tc' + Fl`
печатаются, иначе «не выполнилось». Базовый профиль: письма в `t1 + 1 сут − 10 мин` (часовое окно пусто
— первое по номеру), `− 9 мин` (первая пауза), `− 4 мин` (вторая пауза); к обоим моментам все письма ряда
NTF2-64 из суточного окна вышли (последнее, `t0 + 1 ч 5 мин`, — ровно в `t1 + 1 сут − 1 с`); в обоих моментах
часовое окно — 3 = `per-hour`, суточное — 3 < `per-day`: исход `capped` по часовому потолку, пол не
действует. Затем запросы с меткой `D1` в `t1 + 1 сут − 1 с` и `t1 + 1 сут`

**Then** (а) первые `R` — `200 {}`, по одной строке `recovery`, исход `trusted_device`; запрос `R + 1` —
`200 {}` без строки `recovery`, исход `capped`
**And** (б) `200 {}` без строки `recovery`, исход `capped`
**And** (в) в `t1 + 1 сут − 1 с` — `200 {}` без строки, исход `capped`: запас суток израсходован в `t1`; в
`t1 + 1 сут` — одна строка `recovery`, исход `trusted_device`: окно запаса отпустило письма `t1`
**And** все ответы (а) и (б) побайтово равны

#### Сценарий 71: ручки лимитов — без умолчаний, в границах

**ID:** NTF2-71 · I · отрицательный · близнец — базовый профиль

**Given** конфигурации kaname и края базового профиля в вариантах: (а) снята ручка
`authn.login.mail-window.recovery.per-day`; (б) `per-hour` больше `per-day`; (в) `floor-interval` =
30 мин; (г) снята `KACHO_API_GATEWAY_ANON_MAIL_IP_HARD_LIMIT`; (д) `…IP_FREE_LIMIT` больше `…IP_POW_LIMIT`;
(е) не задано число доверенных прыжков края; (ж) снята `KACHO_API_GATEWAY_ANON_MAIL_GLOBAL_RATE_PER_SECOND`;
(з) `KACHO_API_GATEWAY_ANON_MAIL_GLOBAL_RATE_PER_SECOND` = 0; (и) `GLOBAL_BURST` меньше
`GLOBAL_RATE_PER_SECOND`; (к) `…SUBNET_V6_48_POW_LIMIT` больше `…SUBNET_V6_48_HARD_LIMIT`;
(л) `authn.login.mail-window.registration.per-hour` больше `…registration.per-day`;
(м) `authn.login.recovery-code-ttl` меньше `…recovery.first-pause`; (н) `invite.recipient-per-hour`
больше `invite.recipient-per-day`; (о) `invite.pending-max` = 0; (п) `authn.login.trusted-device.ttl`
= 0; (р) `KACHO_API_GATEWAY_ANON_MAIL_POW_BITS_BASE` = `…POW_BITS_HIGH`; (с) снята
`KACHO_API_GATEWAY_ANON_MAIL_POW_BITS_HIGH`; (т) перебор отсутствия: для каждого ключа таблицы Р8 —
вариант, где снят только он (перечень — раскрытие фигурных скобок таблицы Р8, 51 ключ; печатается с
числом); (у) `authn.login.attempts.window` = 2 ч; (ф) `authn.login.mail-throttled-interval` = 12 ч;
(х) `…IP_FREE_WINDOW` больше `…IP_POW_WINDOW`; (ц) `…SUBNET_HARD_WINDOW` = 25 ч;
(ч) `authn.login.verification-code-ttl` меньше `…verification.first-pause`;
(ш) `authn.login.registration-code-ttl` меньше `…registration.first-pause`; (щ) `invite.recipient-per-day-all`
= 51 — на единицу выше лимита шаблона `invite` (Р8). Граница `ttl ≥ first-pause`
проверяется для каждого из трёх назначений — (м), (ч), (ш); прочие границы — выборкой, не меньше одного
варианта на строку Р8

**When** служба стартует

**Then** в каждом варианте старт отвергнут; сообщение называет ключ и нарушенную границу (в (т) —
ключ и его отсутствие); вариантов (т) — 51, по одному на ключ таблицы Р8; ключи края судит страж края,
ключи kaname — страж kaname
**And** в (щ) сообщение называет ключ `invite.recipient-per-day-all`, значение 51 и границу 50 — лимит
шаблона `invite`
**And** близнец: базовый профиль — обе службы стартуют; в журнале старта напечатаны действующие
значения ручок
**And** близнец (щ): базовый профиль с `invite.recipient-per-day-all` = 50 — kaname стартует: граница
включительная

#### Сценарий 72: консоль решает вызов прозрачно

**ID:** NTF2-72 · E (playwright) · положительный · близнец — шаг 1 (тот же экран, источник ниже порога)

**Given** П1; все запросы прогона, включая браузер консоли, идут к краю с источника раннера (§5);
ручки края П1 — `FREE` = `F` за окно и общий поток `G` в секунду — печатаются пробой из рендера цепочки
`dev`, а объём `V` анонимных почтовых запросов прогона — счётом по перечню кейсов (§5); по объявлению П1 `V < F` (§5)
**And** адрес `Z = ntf2-72-<runId>@<домен приёмника стенда>` не зарегистрирован

**When** шаг 1 (близнец; первое действие кейса): человек открывает экран восстановления консоли,
вводит `Z` и отправляет форму
**And** шаг 2: проба с того же источника шлёт `POST /iam/v1/auth/recovery` для `Z` без доказательства,
по одному, не чаще `G / 2` в секунду, пока ответ не станет вызовом PoW; число запросов печатается и не
больше `F`
**And** шаг 3: человек снова отправляет форму с `Z`

**Then** шаг 1: экран показывает единый текст «Если адрес зарегистрирован, мы отправили письмо»;
сетевой журнал — ровно один запрос восстановления, без заголовка `X-Kacho-Proof`, ответ `200 {}`
**And** шаг 2: последний ответ — `429` `PROOF_OF_WORK_REQUIRED`, все прежние — `200 {}`
**And** шаг 3: экран показывает тот же текст, ошибки на экране нет; сетевой журнал — первый запрос без
заголовка, ответ `429` `PROOF_OF_WORK_REQUIRED`, и следом повтор с заголовком `X-Kacho-Proof`, ответ
`200 {}`
**And** если ответ шага 1 — вызов PoW, нарушено объявление П1 (`V < F`): исход кейса «не выполнилось» с
печатью `V` и `F`, а не красный и не зелёный
**And** что экран показывает на `503` ограничителя и на исчерпанный бюджет решателя, утверждает NTF2-58:
на общем стенде П1 эти исходы края не создаются

#### Сценарий 58: консоль на `503` ограничителя и на исчерпанный бюджет решателя

**ID:** NTF2-58 · U (playwright) · отрицательный · близнец — (в): вызов, решаемый в пределах бюджета

**Given** П12; экран восстановления консоли открыт; бюджет решателя `Bs` и срок вызова печатаются пробой,
и `Bs` меньше срока вызова; `Bs` отсчитывает таймер главного потока страницы, который останавливает
`Worker` решателя, — им управляют часы страницы (`page.clock`); часы внутри `Worker` пробой не
управляются и в отсчёт бюджета не входят
**And** перехват отвечает на `POST /iam/v1/auth/recovery` по варианту: (а) `503`, тело
`{"code": 14, "message": "request limiter is unavailable", "details": []}`; (г) `503`, тело той же
формы с `message` = `limiter probe <n>`, где `<n>` — число, выбранное пробой на прогон и напечатанное;
(б) `429`, тело вызова
`PROOF_OF_WORK_REQUIRED` с `difficultyBits` = 24 (верхняя граница Р8), часы страницы стоят; (в) то же с
`difficultyBits` = 8, а на повтор с заголовком `X-Kacho-Proof` — `200 {}`

**When** человек вводит адрес `Z` и отправляет форму
**And** в (б) проба переводит часы страницы на `Bs − 1 с`, затем на `Bs`; затем человек отправляет форму
ещё раз

**Then** (а) экран показывает `request limiter is unavailable`, форма редактируема; сетевой журнал — ровно
один запрос восстановления, без заголовка `X-Kacho-Proof`; ни одного `Worker` страница не создала
**And** (г) экран показывает `limiter probe <n>` дословно и не показывает `request limiter is unavailable`:
текст отказа берётся из ответа, своего текста у экрана нет — экран, печатающий свою копию текста края,
на (г) красный; остальное — как в (а)
**And** (б) в `Bs − 1 с` решатель работает (`Worker` не завершён), форма в положении отправки, запроса с
`X-Kacho-Proof` нет
**And** (б) в `Bs` по таймеру страницы: `Worker` завершён; запроса с `X-Kacho-Proof` нет ни тогда, ни после; экран показывает
`proof of work required`, форма редактируема
**And** (б) повторная отправка идёт без `X-Kacho-Proof` и получает новый вызов: прежний вызов не
переиспользуется
**And** (б) если решатель нашёл решение раньше `Bs` (запрос с `X-Kacho-Proof` ушёл до `Bs`), исход —
«не выполнилось» с печатью момента: вызов оказался решаемым в бюджете, и случай бюджета не построен
**And** близнец (в): один запрос без заголовка — ответ `429`, затем повтор с `X-Kacho-Proof` — `200 {}`;
экран показывает единый текст «Если адрес зарегистрирован, мы отправили письмо», ошибки на экране нет

#### Сценарий 73: сетка notify не ниже суммы пределов kaname

**ID:** NTF2-73 · G · отрицательный · близнец — рендер цепочки `dev` как есть

**Given** П7: копия цепочки `dev`, где суточная сетка `notify` на адрес для класса `security` меньше
1,25 × суммы суточных пределов kaname на один адрес (включая пол и письмо о торможении, Р6)

**When** рендер

**Then** рендер отказывает; сообщение называет обе величины и их отношение
**And** близнец: в рендере `dev` инвариант выполнен; гейт печатает сетку и сумму по слагаемым — окна по
назначениям, пол и письмо о торможении
**And** второй близнец: копия цепочки `dev`, где сетка равна 1,25 × сумме **без** слагаемого письма о
торможении, — рендер отказывает: слагаемое учтено

#### Сценарий 74: общий поток края — вызов получают все, включая источники ниже своего порога

**ID:** NTF2-74 · I · отрицательный · близнец — тот же набор источников со скоростью ниже общего потока

**Given** П6; ручки общего потока края `GLOBAL_RATE_PER_SECOND` = `G` и `GLOBAL_BURST` = `B` (печатаются
пробой); ручки источника и подсети — ориентиры Р8
**And** набор из `B + G + 1` источников, каждый из своей `/24` (IPv4), так что ни один источник и ни
одна подсеть не достигают своих порогов
**And** адрес `Z`, которого нет

**When** каждый источник шлёт по одному `POST /iam/v1/auth/recovery` с `email` = `Z` без
доказательства, все запросы — в пределах одной секунды часов пробы
**And** запрос, получивший вызов, повторяется с верным доказательством

**Then** ответов `200 {}` без вызова — не меньше `B` и не больше `B + G`; остальные (их не меньше
одного) — `429`, `code` `8`, `proof of work required`, `reason: PROOF_OF_WORK_REQUIRED`, `difficultyBits` =
`POW_BITS_BASE` (счёт каждого источника ниже его `POW`, Р5); проба печатает оба числа
**And** повтор с верным доказательством — `200 {}`
**And** ни один ответ не `RATE_LIMITED`: общий поток даёт вызов, а не жёсткий отказ
**And** близнец: те же `B + G + 1` источников шлют по запросу равномерно за `⌈(B + G + 1) / G⌉ + 1`
секунд — каждый ответ `200 {}` без вызова

#### Сценарий 75: окно адресата для регистрации — одно для свободного и занятого адреса

**ID:** NTF2-75 · I · отрицательный · близнец — тот же ряд для занятого адреса `A` (`registration-existing`)

**Given** П6; запросы ряда идут с разных источников из разных подсетей, каждый ниже порога «без
проверки» края — ряд судит только рубеж kaname
**And** свободный адрес `F`; занятый адрес `A` человека посевом П10 — регистраций и писем на `A` не
было, строки счётчика окна `registration` для `A` к началу ряда нет (проба печатает её отсутствие);
пароль `P`, проходящий правила полосы
**And** ручки `authn.login.mail-window.registration.*` и `authn.login.registration-code-ttl` печатаются
пробой; ряд моментов строится из ручек так же, как в NTF2-64

**When** в каждый момент ряда идёт `POST /iam/v1/auth/register` с `email` = `F` и паролем `P`
**And** ряд продолжается моментами пола: `Tc` — момент письма прогрессии, которым исчерпано суточное
окно `registration` адреса `F`, `Tw` — момент, когда окно отпускает строку (Р6; `Tw = t0 + 1 сут`, как в
NTF2-65), `Fl` = `…registration.floor-interval`; запросы в `Tc + 1 с`, `Tc + Fl − 1 с` и `Tc + Fl`; условие —
`Tc + Fl < Tw`, печатается, иначе исход моментов пола «не выполнилось»
**And** граница суток — отдельный повтор, как NTF2-65 (г), на копии П6 с `…registration.floor-interval`
= 24 ч: запросы в `t0 + 1 сут − 1 с` и `t0 + 1 сут`; пола в исчерпании нет (`Tc + 24 ч ≥ Tw`); условие —
часовое окно в `t0 + 1 сут` пусто (`Tc ≤ t0 + 23 ч`), печатается, иначе «не выполнилось»

**Then** каждый ответ — `200 {}` без печений, побайтово один и тот же
**And** в каждом моменте, разрешённом прогрессией и полом, — ровно одна строка ленты `registration`, в
прочих — ни одной; часовая граница (как NTF2-64): в `u + 1 ч − 1 с` строки нет, в `u + 1 ч` — одна; до `Tc`
включительно за час их не больше `per-hour`, за сутки не больше `per-day`; с письмами пола за любые
сутки — не больше `per-day` + ⌈24 ч / `Fl`⌉ (как NTF2-65)
**And** пока первый код жив, каждая строка несёт тот же код `K1`, а ожидающая запись `F` одна
**And** для `F` заведена строка счётчика окна (адрес без учётной записи — Р6)
**And** в `Tc + 1 с` и `Tc + Fl − 1 с` строки `registration` нет, исход `capped`; в `Tc + Fl` — одна строка
`registration`, исход `floor`
**And** граница суток: в `t0 + 1 сут − 1 с` строки нет, исход `capped`; в `t0 + 1 сут` — одна строка, исход
`queued` или `resent_same`, не `floor`: в `Tw` прогрессия возобновилась (Р6)
**And** близнец: тот же ряд с `email` = `A` — ответы побайтово равны ответам для `F`; строки ленты
`registration-existing` стоят в тех же моментах и в том же числе, что строки `registration` для `F`, в
моменте `Tc + Fl` для `A` — тоже с исходом `floor`; учётная запись `A` не изменилась

#### Сценарий 76: окно адресата для подтверждения адреса — явный отказ и пол

**ID:** NTF2-76 · I · отрицательный · близнец — запрос в момент, разрешённый прогрессией

**Given** П6; человек в положении подтверждения со своей сессией; ручки
`authn.login.mail-window.verification.*` печатаются пробой; ряд моментов — как в NTF2-64, до суточного
потолка, и далее момент пола `Tc + Fl` и `Tc + Fl − 1 с`, где `Tc` — момент письма прогрессии, которым
исчерпано суточное окно `verification`, `Tw` — момент, когда окно отпускает строку (Р6;
`Tw = t0 + 1 сут`, как в NTF2-65), `Fl` — `…verification.floor-interval`; условие — `Tc + Fl < Tw`,
печатается, иначе исход моментов пола «не выполнилось»

**When** в каждый момент ряда сессия человека вызывает `POST /iam/v1/auth/verify-email`
**And** граница суток — отдельный повтор, как NTF2-65 (г), на копии П6 с `…verification.floor-interval`
= 24 ч: вызовы в `t0 + 1 сут − 1 с` и `t0 + 1 сут`; пола в исчерпании нет (`Tc + 24 ч ≥ Tw`); условие —
часовое окно в `t0 + 1 сут` пусто (`Tc ≤ t0 + 23 ч`), печатается, иначе «не выполнилось»

**Then** в моментах, разрешённых прогрессией, — `200 {}` и одна строка ленты `verification`
**And** в прочих моментах — `429`, `code` `8`, `TOO_MANY_ATTEMPTS`, `Retry-After` — целое число секунд
> 0, строки нет
**And** до `Tc` включительно за час строк не больше `per-hour`, за сутки не больше `per-day`; с письмом
пола за любые сутки — не больше `per-day` + ⌈24 ч / `Fl`⌉
**And** в `Tc + Fl − 1 с` — `429`; в `Tc + Fl` — `200 {}` и одна строка, исход `floor`
**And** часовая граница (как NTF2-64): в `u + 1 ч − 1 с` — `429`; в `u + 1 ч` — `200 {}` и строка
**And** граница суток: в `t0 + 1 сут − 1 с` — `429`; в `t0 + 1 сут` — `200 {}` и строка, исход `queued` или
`resent_same`, не `floor`: в `Tw` прогрессия возобновилась (Р6)
**And** близнец: запрос в первый разрешённый момент ряда — `200 {}` и строка

#### Сценарий 77: потолки на адресата от одного аккаунта, висящие приглашения и их срок

**ID:** NTF2-77 · I · отрицательный · близнец — приглашение в пределах каждого потолка

**Given** П6-age; аккаунт `mature` (возраст не меньше `Ya` во всё время сценария) с администратором; ручки приглашений Р8 печатаются
пробой, `invite.pending-max` = `Pm`, `invite.ttl` = `Tv`
**And** адреса `C`, `D1…Dn` не зарегистрированы

**When** (а) `mature` приглашает `C` `recipient-per-hour + 1` раз за один час часов пробы;
(б) затем в те же сутки — до `recipient-per-day + 1` приглашений `C`, разнося их по часам так, чтобы
часовой потолок не срабатывал;
(в) `mature` заводит приглашения разным адресам `D1…` до `Pm` висящих и ещё одно;
(г) часы переводятся на момент истечения первого из висящих приглашений — его заведение плюс `Tv`;
`mature` приглашает новый адрес
**And** (д) граница часа по адресату, отдельный повтор: в момент `t1` (часы стоят) `mature` приглашает `C`
`recipient-per-hour` раз; затем приглашает `C` в `t1 + 1 ч − 1 с` и в `t1 + 1 ч`; условие —
`recipient-per-hour < recipient-per-day` (печатается, иначе «не выполнилось»)
**And** (е) граница суток по адресату, отдельный повтор на копии П6, где `recipient-per-hour` =
`recipient-per-day` (в границах Р8): в `t1` — `recipient-per-day` приглашений `C`; затем в
`t1 + 1 сут − 1 с` и в `t1 + 1 сут`

**Then** (а) каждое приглашение — `Operation` с `done = true`; строк ленты `invite` для `C` за час —
`recipient-per-hour`; сверх — строка приглашения заведена, письма нет, исход `capped`
**And** (б) строк ленты `invite` для `C` за сутки — `recipient-per-day`; сверх — исход `capped`
**And** (в) приглашение сверх `Pm` — `400`, `code` `9`, `pending invitations limit of the account is
reached`, `reason: INVITATION_PENDING_LIMIT`; `Operation` не заведена, строки приглашения нет
**And** (г) — `Operation` с `done = true` и строка `invite`: истёкшее приглашение место освободило
**And** (д) в `t1 + 1 ч − 1 с` — `Operation`, строки нет, исход `capped`; в `t1 + 1 ч` — строка `invite`
**And** (е) в `t1 + 1 сут − 1 с` — `Operation`, строки нет, исход `capped`; в `t1 + 1 сут` — строка `invite`
**And** близнец: в (а) приглашение номер `recipient-per-hour` — строка `invite`; в (в) приглашение
номер `Pm` — `Operation`; в (г) в `Tv − 1 с` от первого висящего — тот же отказ, что в (в)

#### Сценарий 78: метка устройства истекает по сроку

**ID:** NTF2-78 · I · отрицательный · близнец — вход с той же меткой в `Tt − 1 с`

**Given** П6; подтверждённый человек `A` (П11) вошёл с устройства `D1` в момент `T` и получил метку; срок
метки `authn.login.trusted-device.ttl` = `Tt` печатается пробой
**And** суточный потолок адресата `A` исчерпан чужими запросами без метки — ряд NTF2-64, построенный
так, что письмо прогрессии, которым окно исчерпано, стоит в `Tc = T + Tt − 10 мин` (Р6); `Tw` — момент,
когда окно отпускает строку, печатается; `Fl` ≥ 1 ч (Р8), а `Tw − Tc` больше 10 мин — ряд NTF2-64 короче
суток (в базовом профиле `Tw − Tc` = 22 ч 55 мин), поэтому `T + Tt − 1 с` и `T + Tt` лежат в исчерпании
`[Tc, Tw)` и раньше пола `Tc + Fl`

**When** (а) часы переводятся на `T + Tt − 1 с`; вход с меткой `D1`; (б) часы переводятся на `T + Tt`;
вход с меткой `D1`
**And** (в) в `T + Tt` — `POST /iam/v1/auth/recovery` с `email` = `A` и меткой `D1`

**Then** (а) `200`, строки `new-device-login` нет, новой метки не выдано
**And** (б) `200`; одна строка `new-device-login` для `A`; выставлена новая метка
**And** (в) `200 {}`, строки `recovery` нет, исход `capped`, а не `trusted_device`
**And** близнец: в отдельном повторе пробы с тем же рядом — восстановление с меткой `D1` в
`T + Tt − 1 с` даёт строку с исходом `trusted_device`

#### Сценарий 79: ключ источника — адрес на доверенной глубине

**ID:** NTF2-79 · I · отрицательный · близнец — (б): разные адреса на доверенной глубине

**Given** П6; число доверенных прыжков края `h` и порог «без проверки» `F` печатаются пробой; запросы
пробы приходят к краю через доверенные прыжки стенда, и проба задаёт всю цепочку пересланных адресов
**And** адрес `Z`, которого нет

**When** (а) `F + 1` запросов `POST /iam/v1/auth/recovery` с `email` = `Z` без доказательства: адрес на
доверенной глубине у всех один — `S1`; часть цепочки дальше доверенной глубины у каждого запроса своя,
из своей `/24`
**And** (б) близнец, отдельный повтор пробы: `F + 1` таких же запросов, у каждого свой адрес на
доверенной глубине, из своей `/24`, а часть цепочки дальше неё у всех одна
**And** запросы идут с темпом ниже общего потока края

**Then** (а) первые `F` — `200 {}`; запрос `F + 1` — `429`, `code` `8`, `proof of work required`,
`reason: PROOF_OF_WORK_REQUIRED`: край учёл все запросы одним источником `S1`
**And** (б) все `F + 1` — `200 {}` без вызова: край учёл их разными источниками

### S4 — регистрация «сначала письмо, потом сессия»

#### Сценарий 80: свободный адрес — письмо с кодом, учётная запись после кода

**ID:** NTF2-80 · E · положительный

**Given** П1; адрес `A = ntf2-80-<runId>@<домен приёмника стенда>` не зарегистрирован

**When** шаг 1: `POST /iam/v1/auth/register` с payload:
  - `email` = `A`
  - `password` = пароль, проходящий правила полосы
  - `csrfToken` = признак формы `register`
**And** шаг 2: `POST /iam/v1/auth/register/confirm` с `email` = `A`, `code` = код из письма
`registration`, `password` = пароль шага 1, `csrfToken` формы `register-confirm`

**Then** шаг 1: `200 {}`; в ответе нет `Set-Cookie` сессии
**And** в пределах бюджета приёмник получает на `A` ровно одно письмо `registration` с кодом
**And** шаг 2: `200`, тело несёт `user` и `session`, `session.emailVerified = true`; печенья сессии и
метки устройства выставлены
**And** `GET /iam/v1/auth/me` — `200`, `emailVerified: true`; у человека есть личный аккаунт, он его
владелец (Ф4 Р8)
**And** писем `new-device-login` на `A` от ответа шага 2 до конца бюджета — 0 (Р12; близнец — вход
NTF2-94)

#### Сценарий 81: занятый адрес — тот же ответ, письмо «учётная запись уже есть»

**ID:** NTF2-81 · E · отрицательный · близнец — NTF2-80 шаг 1

**Given** П1; свой человек **П10** с адресом `A` и паролем `P0`: учётная запись заведена посевом, окна
`registration` на `A` нет, поэтому первое письмо окна пропускается сразу (Р6) — ожидание паузы не
нужно

**When** `POST /iam/v1/auth/register` с `email` = `A` и другим годным паролем `P1`

**Then** `200 {}`, побайтово равно ответу шага 1 NTF2-80; `Set-Cookie` сессии нет
**And** в пределах бюджета приёмник получает на `A` ровно одно письмо `registration-existing`: кода в
нём нет, есть путь восстановления
**And** вход паролем `P0` — `200`; вход паролем `P1` — отказ полосы формы: учётная запись не
изменилась

#### Сценарий 82: неверный код подтверждения регистрации ничего не заводит и верного не гасит

**ID:** NTF2-82 · E · отрицательный · близнец — шаг 2 того же кейса

**Given** П1; свой адрес `A`, шаг 1 NTF2-80 выполнен с паролем `P`, код `K` прочитан

**When** шаг 1: `POST /iam/v1/auth/register/confirm` с `code` = `K'` (последний знак заменён) и
`password` = `P`
**And** шаг 2: тот же запрос с `code` = `K`

**Then** шаг 1: `401`, `code` `16`, `authentication failed`; `Set-Cookie` нет; вход с `A` — отказ полосы
формы (учётной записи нет)
**And** шаг 2: исход шага 2 NTF2-80

#### Сценарий 83: истёкший код регистрации

**ID:** NTF2-83 · I · отрицательный · близнец — тот же код в срок

**Given** П6; ожидающая регистрация `A` с паролем `P` и кодом `K`, срок
`authn.login.registration-code-ttl`

**When** часы переводятся на срок + 1 с; `POST /iam/v1/auth/register/confirm` с `K` и `P`
**And** затем `POST /iam/v1/auth/register` с `A` и тем же паролем `P`; затем `register/confirm` с кодом
`K2` из новой строки ленты и `P`, и ещё раз с `K` и `P`

**Then** `401`, `code` `16`, `authentication failed` — побайтово как у неверного кода; учётной записи
нет
**And** повтор `register` после истечения — `200 {}`; одна новая строка `registration` с кодом `K2 ≠ K`,
исход `queued`, а не `resent_same`: запись с истёкшим кодом не жива (Р9)
**And** `register/confirm` с `K2` и `P` — `200`, учётная запись заведена; с `K` и `P` после этого — `401`
**And** близнец: в срок — `200`, учётная запись заведена

#### Сценарий 84: два подтверждения одного адреса — учётная запись одна

**ID:** NTF2-84 · I · отрицательный (гонка) · близнец — одно подтверждение

**Given** П6; две ожидающие регистрации одного свободного адреса `A`, построенные по Р9: шаг 1
`register` с паролем `P1` (письмо с кодом `K1`), затем после первой паузы окна `registration` —
шаг 1 с другим паролем `P2` (вторая запись, письмо с кодом `K2`); обе записи в сроке (исход NTF2-86 (б))

**When** `register/confirm` с (`K1`, `P1`) и с (`K2`, `P2`) исполняются одновременно в параллельных
горутинах, 50 повторов пробы (в каждом повторе — свой адрес `A` и своя пара записей)

**Then** в каждом повторе ровно один ответ `200` и один `401` `authentication failed`; учётных
записей с `lower(email) = lower(A)` ровно 1
**And** вход паролем выигравшей пары — `200`; паролем проигравшей — отказ полосы формы
**And** близнец: одно подтверждение — `200`, одна учётная запись

#### Сценарий 85: негодный пароль — отказ о пароле, письма нет

**ID:** NTF2-85 · E · отрицательный · близнец — NTF2-80 шаг 1

**Given** П1; свободный адрес `A`

**When** `POST /iam/v1/auth/register` с `email` = `A` и паролем короче правила полосы

**Then** `400`, `code` `3`; текст называет поле `password` и правило
**And** за бюджет доставки на `A` писем 0
**And** тот же запрос с занятым адресом — адресом своего человека П10 — даёт побайтово тот же ответ, и
писем на него за бюджет 0

#### Сценарий 86: повтор регистрации в срок кода — код привязан к паролю своего запроса

**ID:** NTF2-86 · I · отрицательный · близнец — (а): повтор с тем же паролем

**Given** П6; свободный адрес `A`; шаг 1 `register` с паролем `P1` выполнен в `T`, письмо с кодом `K1`
в ленте; первая пауза окна `registration` — `p` (печатается пробой)

**When** в `T + p` в срок `K1`: (а) `register` с `A` и тем же `P1`; (б) вместо (а) — `register` с `A` и
другим годным паролем `P2`
**And** затем `register/confirm` по варианту: (в) после (б) — `K2` с паролем `P1`; (г) после (б) — `K1`
с `P2`; (д) после (б) — `K2` с `P2`; (е) после (б) в отдельном повторе пробы — `K1` с `P1`
**And** (ж) в отдельном повторе пробы, в `T + p − 1 с` (пауза не прошла) — `register` с `A` и
паролем `P3`, затем `register/confirm` с `K1` и `P3`

**Then** (а) `200 {}`; одна новая строка ленты `registration` с кодом **`K1`**, исход `resent_same`;
ожидающая запись `A` одна
**And** (б) `200 {}`, побайтово равен (а); одна новая строка `registration` с кодом `K2 ≠ K1`, исход
`queued`; ожидающих записей `A` две; запись с `K1` жива
**And** (в) и (г): `401`, `code` `16`, `authentication failed`, побайтово как у неверного кода; учётной
записи нет; обе записи живы
**And** (д) `200`, учётная запись с паролем `P2`; вход с `P1` — отказ полосы формы
**And** (е) `200`, учётная запись с паролем `P1`
**And** (ж) `200 {}` побайтово как (а); новой строки ленты нет, исход `cooldown`; третьей записи нет:
`register/confirm` с `P3` — `401`
**And** близнец: (а) — тот же пароль даёт тот же код и не заводит второй записи

#### Сценарий 87: срок кода — обе стороны границы для трёх назначений

**ID:** NTF2-87 · I · отрицательный · близнец — повтор (1): те же запросы в `Tk + ttl − 1 с`

**Given** П6; по назначению — своё построение без прошлых писем в его окне: (а) `recovery` —
подтверждённый адрес `A` (П11); (б) `verification` — человек в положении подтверждения со своей
сессией (П11); (в) `registration` — свободный адрес `F` и годный пароль `P`
**And** код `K` отчеканен первой строкой окна в момент `Tk`; `ttl` = `authn.login.<назначение>-code-ttl`,
`first-pause` = `…mail-window.<назначение>.first-pause`; `Tk`, `ttl`, `first-pause` печатаются пробой
**And** условие: `ttl − 1 с ≥ first-pause` — повтор в `Tk + ttl − 1 с` разрешён прогрессией; граница Р8
допускает `ttl` = `first-pause`, и тогда исход «не выполнилось», а не красный
**And** по каждому назначению — два отдельных повтора пробы: (1) момент `Tk + ttl − 1 с`, (2) момент
`Tk + ttl`; часы пробы стоят в названном моменте

**When** в названный момент — повтор запроса письма: (а) `POST /iam/v1/auth/recovery` с `A`;
(б) `POST /iam/v1/auth/verify-email` сессией человека; (в) `POST /iam/v1/auth/register` с `F` и `P`
**And** затем в тот же момент — предъявление `K`: (а) `recovery/complete` с `A`, `K` и годным
`newPassword`; (б) `verify-email/confirm` с `K`; (в) `register/confirm` с `F`, `K` и `P`
**And** в повторе (2) затем — предъявление кода `K2` из новой строки

**Then** (1) в `Tk + ttl − 1 с`: повтор — `200 {}`, одна новая строка своего шаблона с **тем же** кодом `K`,
исход `resent_same`; предъявление `K` — `200`: в (а) выдана сессия, в (б) `emailVerified = true`, в (в)
учётная запись заведена
**And** (2) в `Tk + ttl`: повтор — `200 {}`, одна новая строка с кодом `K2 ≠ K`, исход `queued`;
предъявление `K` — `401`, `code` `16`, `authentication failed`; предъявление `K2` — `200`
**And** ответы повтора в (1) и (2) побайтово равны

### S5 — класс S из аудита kaname

#### Сценарий 90: каждое событие перечня даёт ровно одно письмо своего шаблона своему адресату

**ID:** NTF2-90 · I · положительный · близнец — NTF2-52 (флаг выключен: строк 0)

**Given** П6; фикстурой П11: аккаунт `acc` с владельцем `O` (ACTIVE, адрес подтверждён); пользователь `U`
в `acc` (ACTIVE, адрес подтверждён); сервисный аккаунт `sa` в `acc`; группа `g` в `acc`; два
администратора облака `C1`, `C2`

**When** проба исполняет по одному глаголу на каждую строку таблицы. Порядок: строки в порядке
таблицы, кроме четырёх, меняющих годность адресатов, — `user.removed_from_account`, `user.blocked`,
`project.deleted`, `account.deleted` исполняются последними, в этом порядке, так что каждый адресат
строки в момент её события ACTIVE и подтверждён:

| событие аудита | глагол пробы | шаблон | адресаты строки |
|---|---|---|---|
| `access_binding.granted` на `U` | выдача роли `U` на проект `acc` | `role-granted` | `U` |
| `access_binding.revoked` на `U` | снятие той же роли | `role-revoked` | `U` |
| `access_binding.granted` на `g` | выдача роли группе | `role-granted` | `O` |
| `cluster_admin.granted` на `U` | выдача администратора облака | `cluster-admin-granted` | `C1`, `C2`, `U` |
| `cluster_admin.revoked` на `U` | снятие | `cluster-admin-revoked` | `C1`, `C2`, `U` |
| `user.removed_from_account` | исключение `U` из `acc` | `removed-from-account` | `U`, `O` |
| `sa_key.issued` | выпуск ключа `sa` | `sa-key-issued` | `O` |
| `user_token.issued` | выпуск токена `U` | `user-token-issued` | `U` |
| `user.blocked` | блокировка `U` | `user-blocked` | `C1`, `C2` |
| `service_account.disabled` | отключение `sa` | `service-account-disabled` | `O` |
| `session.all_revoked` | завершение всех сессий `U` | `sessions-revoked` | `U` |
| `session.force_logout` | `InternalIAMService.ForceLogout` на `U` администратором облака `C1` | `sessions-revoked` | `U` |
| `user.password_changed` | смена пароля `U` | `password-changed` | `U` |
| `user.second_factor_enrolled` | заведение фактора `U` | `second-factor-changed` | `U` |
| `user.second_factor_removed` | снятие фактора самим `U` | `second-factor-changed` | `U` |
| `user.second_factor_reset` | `UserService/ResetSecondFactor` на `U` администратором облака `C1` (фактор `U` перед этим заведён снова) | `second-factor-changed` | `U` |
| `user.backup_codes_regenerated` | перевыпуск резервных кодов `U` | `backup-codes-regenerated` | `U` |
| `access_key.registered` | регистрация ключа входа `U` | `access-key-changed` | `U` |
| `access_key.revoked` | снятие того же ключа входа | `access-key-changed` | `U` |
| `user.recovery_completed` | NTF2-43 шаг 2 для `U` | `recovery-completed` | `U` |
| `project.deleted` | удаление проекта `acc` | `project-deleted` | `O` |
| `account.deleted` | удаление аккаунта `acc` | `account-deleted` | `O` |

**Then** для каждой строки таблицы: строк ленты, порождённых **её событием** (идентификатор события
аудита), — ровно столько, сколько адресатов строки, по одной на адресата, с названным шаблоном и
классом `security`; каждая поставлена той же транзакцией, что строка `audit_outbox` события
**And** `notify` доставляет каждую такую строку на подтверждённый адрес названного адресата, исход `SENT`
**And** проба печатает по каждой строке таблицы событие, шаблон, число адресатов, число строк ленты и
число доставленных писем по этому событию; по каждой строке три числа равны. Строки ленты,
порождённые вспомогательными событиями пробы — повторным заведением фактора перед
`user.second_factor_reset`, входами `U` для собственных глаголов (`session.issued`), запросом кода
восстановления в строке `user.recovery_completed`, — в счёт строк таблицы не входят и этим сценарием не
утверждаются (их держатели — NTF2-94, NTF2-43)
**And** проба печатает множество видов аудита таблицы вместе с видом NTF2-89 и сверяет его с картой
«вид → шаблон → правило адресата» kaname (Р3): вид карты, которого нет ни в таблице, ни в NTF2-89, —
красный с именем вида; таблица и NTF2-89 вместе покрывают 22 из 23 видов карты, двадцать третий —
`session.issued` — держит NTF2-94

#### Сценарий 89: перенос ключа входа — письмо владельцу до и после события

**ID:** NTF2-89 · I · отрицательный · близнец — `access_key.revoked` той же пробой (один адресат)

**Given** П6 как в NTF2-90; второй пользователь `U2` в `acc` (ACTIVE, адрес подтверждён)
**And** глагола переноса ключа входа в дереве kaname нет (§1.2: вид объявлен, вызова нет), поэтому
событие производит проба: она пишет строку аудита `iam.access_key.transferred` тем же писателем
аудита kaname, которым пишут глаголы ключа, в одной транзакции, с полями «ключ», «прежний владелец»
= `U`, «новый владелец» = `U2`
**And** второй вариант: те же поля, но «новый владелец» пуст

**When** транзакция пробы фиксируется; `notify` забирает строки

**Then** в ленте kaname ровно две строки шаблона `access-key-changed` по этому событию — для `U` и для
`U2`; каждая доставлена, исход `SENT`
**And** вариант с пустым «новым владельцем»: транзакция отвергнута писателем, строки аудита и строк
ленты нет — правило адресата карты требует обоих владельцев
**And** откат транзакции пробы уносит и строку аудита, и обе строки ленты
**And** близнец: `access_key.revoked` на ключ `U` — одна строка ленты, для `U`

#### Сценарий 88: справочник адресов и разрешение адресатов — только notify

**ID:** NTF2-88 · I · отрицательный · близнец — те же вызовы сертификатом `notify`

**Given** П6 как в NTF2-90: аккаунт `acc` с владельцем `O`, пользователь `U`, администраторы облака
`C1`, `C2` (П11)
**And** клиент с проверенным сертификатом службы стенда, отличной от `notify`, выпущенным политикой
выпуска стенда

**When** этот клиент на внутреннем слушателе kaname вызывает (а) справочник подтверждённых адресов для
`U`; (б) разрешение «владельцы аккаунта» для `acc`; (в) разрешение «администраторы облака»

**Then** (а)–(в): `PERMISSION_DENIED` (`code` `7`); в ответе нет ни адреса, ни идентификатора человека
**And** близнец: те же вызовы сертификатом `notify` — (а) подтверждённый адрес `U`; (б) `O`; (в) `C1` и
`C2`

#### Сценарий 91: в письмах класса S нет пользовательского текста

**ID:** NTF2-91 · I · отрицательный · близнец — идентификаторы в тех же письмах есть

**Given** П6 как в NTF2-90; имя аккаунта `acc`, имя проекта, имя роли (пользовательская роль),
`displayName` пользователя `U` и имя сервисного аккаунта несут разные строки-маркеры

**When** исполняются строки NTF2-90 `role-granted` (пользовательская роль), `sa-key-issued`,
`project-deleted`

**Then** ни одного маркера нет ни в `text/plain`, ни в `text/html`, ни в заголовках писем
**And** близнец: письма несут идентификаторы роли, проекта, сервисного аккаунта и аккаунта и ссылку
с origin установки

#### Сценарий 92: сервисный аккаунт, группа, не ACTIVE и неподтверждённый — не адресаты

**ID:** NTF2-92 · I · отрицательный · близнец — выдача роли ACTIVE подтверждённому пользователю (`U`)

**Given** П6; пользователь `V` в `acc` с неподтверждённым адресом

**When** (а) роль выдана `sa`; (б) роль выдана `g`, в которой состоит `U`; (в) роль выдана `V`

**Then** (а) и (б): строка ленты по событию выдачи адресована владельцу `O`; строк по этому событию
для `sa` и для членов `g`, включая `U`, нет
**And** (в): строка ленты `role-granted` для `V` по этому событию закрыта `DENIED(recipient)`; писем `V`
по нему 0
**And** близнец: роль выдана `U` — письмо `U`

#### Сценарий 93: права администратора облака — все администраторы облака

**ID:** NTF2-93 · I · положительный · близнец — обычная роль

**Given** П6 как в NTF2-90

**When** (а) `U` получает администратора облака; (б) `U` получает роль на проект

**Then** (а) письма `cluster-admin-granted` получают `C1`, `C2` и `U` — по одному
**And** (б) письмо `role-granted` получает только `U`; `C1` и `C2` писем не получают

#### Сценарий 94: вход с нового устройства

**ID:** NTF2-94 · E · положительный · близнец — второй вход с меткой

**Given** П1; свой человек П2 с адресом `A`; в клиенте нет метки устройства

**When** шаг 1: `POST /iam/v1/auth/login` с `A` и паролем
**And** шаг 2: выход; вход снова тем же клиентом с печеньем метки из шага 1

**Then** шаг 1: `200`, сессия; выставлено печенье метки устройства (`Secure`, `HttpOnly`); от ответа
шага 1 в пределах бюджета на `A` ровно одно письмо `new-device-login` (построение П2 его не порождает:
сессия `register/confirm` письма не даёт, Р12)
**And** шаг 2 идёт после того, как письмо шага 1 получено; `200`; от ответа шага 2 за бюджет доставки
писем `new-device-login` на `A` 0

#### Сценарий 95: совершённое восстановление — на подтверждённые адреса субъекта

**ID:** NTF2-95 · I · положительный · близнец — запрос восстановления без завершения

**Given** П6; подтверждённый человек `A`

**When** (а) запрос и завершение восстановления; (б) только запрос

**Then** (а) одна строка `recovery-completed` на каждый подтверждённый адрес `A` (у пользователя их
множество; сегодня — один, §1.3); письмо доставлено
**And** (б) строк `recovery-completed` 0

#### Сценарий 96: адресат перестал быть ACTIVE до отправки — письма нет

**ID:** NTF2-96 · I · отрицательный · близнец — адресат остался ACTIVE

**Given** П6; `notify` приостановлен; роль выдана `U` — строка `role-granted` поставлена

**When** `U` заблокирован; затем `notify` возобновлён

**Then** строка `role-granted` для `U` закрыта `DENIED(recipient)`; писем `U` по этому событию 0
**And** строки `user-blocked` адресованы администраторам облака `C1`, `C2` и доставлены
**And** близнец: без блокировки строка `role-granted` доставлена `U`

#### Сценарий 97: одно событие — одна строка

**ID:** NTF2-97 · I · отрицательный · близнец — два разных события

**Given** П6

**When** (а) глагол смены пароля `U` повторяется клиентом с тем же ключом идемпотентности;
(б) строка `audit_outbox` события доставляется дренажом аудита дважды (проба сбрасывает её отметку
отправки)

**Then** (а) и (б): строк `password-changed` для `U` по этому событию — 1
**And** близнец: две разные смены пароля — две строки

#### Сценарий 98: глагол смены адреса вносится только с письмом прежнему адресу

**ID:** NTF2-98 · G · отрицательный · близнец — дерево kaname как есть

**Given** П8: копия дерева kaname с не-тестовым оператором, пишущим `email` в существующую строку
человека

**When** гейт `people_address_writers` судит копию

**Then** красный; текст находки называет условия внесения глагола, и среди них — письмо класса
`security` на **прежний** адрес в той же транзакции, что смена
**And** близнец: на дереве находок 0; гейт печатает число разобранных операторов записи (> 0)

#### Сценарий 99: шаблоны перечня Р3 — класс security, без отписки

**ID:** NTF2-99 · G · отрицательный · близнец — шаблоны в дереве как есть

**Given** П8 в четырёх вариантах копии дерева kaname: (а) у шаблона `role-granted` класс заменён на
отключаемый; (б) в тело `password-changed` добавлен блок ссылки отписки; (в) перечень
`notifications/required-security.yaml` пуст; (г) в перечень добавлено имя шаблона, которого в
`notifications/` нет

**When** (а), (в), (г) — гейт kaname «обязательный класс» (`internal/check`) читает перечень
`notifications/required-security.yaml` и `notifications/*/notification.yaml`; (б) — проверка шаблонов
`notifygen -check` (правило спецификации: у класса `security` отписки нет)

**Then** все четыре копии — красные; находка называет файл, шаблон и нарушенное: (а) класс
`role-granted` не `security`; (б) отписка в классе `security`; (в) «пустой перечень»; (г) имя без
шаблона
**And** близнец: на дереве kaname гейт печатает число имён перечня — 24 — и число прочитанных
шаблонов; все 24 объявлены классом `security`; `notifygen -check` зелёный, ссылок отписки 0

### S6 — снят редакцией 14 (Д39)

Сценарии снятия почты поставщика личности — NTF2-18, NTF2-20, NTF2-21, NTF2-22, NTF2-23 — ушли вместе с
предметом в `kacho#1276` (§4, Р19); их ID не переиспользуются. NTF2-19 (рубеж подтверждённости нашей
полосы) перенесён в S1, NTF2-24 (единственный читатель приёмника) — в S7: их предмет — почта личности
через `notify`, а не почта поставщика. Условие Р16 п.2 (посадка `own` во всех цепочках) остаётся
условием начала, измеренным командой §1.6; держит его существующий гейт
`TestOwnPostureRaisesNoForeignIdentityService`.

### S7 — секрет почты ровно в одном объекте — отправителе `notify`

#### Сценарий 30: перепись держателей по рендеру

**ID:** NTF2-30 · G · положительный (В1)

**Given** ствол kacho после посадки NTF-2

**When** гейт рендерит каждую цепочку `deploy/stacks.txt` и считает объекты со ссылкой на
удостоверение почты либо на ключ почтовой полосы в любом секрете — во всех трёх формах ссылки
(`secretKeyRef` · `envFrom.secretRef` · том `secret`) — и объекты, несущие адрес почтового узла

**Then** в каждой цепочке объектов со ссылкой вне чарта `notify` — **0**; объектов с адресом узла
вне чарта `notify` — **0**
**And** в цепочке, объявляющей удостоверение почты, объектов чарта `notify` со ссылкой — **ровно 1**
(отправитель `notify`: развёртывание `notify` при NTF-1 без NTF-3, `notify-sender` после NTF-3 Р8);
принадлежность чарту узнаётся идентичностью объявления (`# Source:` под чартом `notify`), а не
образцом имени
**And** гейт печатает число цепочек, объектов обхода по каждой и число ссылок

#### Сценарий 31: второй держатель секрета и пустой обход — красные

**ID:** NTF2-31 · G · отрицательный · близнец — NTF2-30

**Given** П7 в вариантах: (а) объект вне чарта `notify` получает ссылку на удостоверение
почты; (б) то же формой `envFrom.secretRef`; (в) пустой перечень цепочек; (д) цепочка `a8f60d` на
дереве до NTF-2 — Deployment `kaname` со ссылкой (замер §1.6 @`96e2fa72b3a`) — настоящий вход.
Вариант (г) прежних редакций — повторное включение поставщика — снят редакцией 14: этот вход —
предмет `kacho#1276` (Д39, §1.7); буква не переиспользуется
**And** (ж) П7-tpl: копия со вторым шаблоном под `deploy/helm/umbrella/templates/`, имя которого не
содержит `mail` и `guard`, с вызовом `fail`, называющим `global.kacho.identity.smtp.credentialSecret`;
близнец (ж') — дерево как есть: такой шаблон один — `identity-mail-lane-guard.yaml` (§1.10). Вариант
(е) редакции 14 — отказ стража места С1 по объявлению, отдающему ссылку объекту вне отправителя, —
снят редакцией 15: такого объявления после NTF-2 и `kacho#1276` нет (§1.10, Р19); буква не
переиспользуется

**When** тот же гейт; для (ж), (ж') — перепись шаблонов под `deploy/helm/`, чей вызов `fail` называет
ключ `credentialSecret` (разбор вызова, а не образец имени файла)

**Then** (а), (б), (д) — красный с именем цепочки, объекта и формы ссылки
**And** (в) — красный «пустой обход»
**And** (ж) — красный «второй страж секрета почты» с путями обоих шаблонов; (ж') — молчит и печатает
число прочитанных шаблонов и путь единственного стража

#### Сценарий 32: значение удостоверения не попадает в рендер

**ID:** NTF2-32 · G · отрицательный · близнец — ссылка по имени в NTF2-30

**Given** П7: цепочка, объявляющая удостоверение, с уникальной строкой-маркером в значении секрета
стенда

**When** гейт ищет маркер в рендере всех объектов

**Then** маркер встречается 0 раз

#### Сценарий 33: самостоятельная поставка kaname — без узла и кредов, флаг обязателен

**ID:** NTF2-33 · G · отрицательный · близнец — рендер поставки с флагом

**Given** рендер чарта `deploy/` дерева kaname после NTF-2 в вариантах: (а) базовые значения с
`notifications.enabled: true`; (б) базовые значения без ключа флага; (в) П7-аналог — значения с
ключом почтового узла kaname (`inviteMail.relay`)

**When** гейт рендера kaname

**Then** (а) рендерится; объектов со ссылкой на секрет почты 0; адресов почтового узла 0; в
конфигурации kaname `notifications.enabled: true`; гейт печатает число объектов обхода
**And** (б) рендер отказывает и называет ключ флага
**And** (в) рендер отказывает и называет ключ: почту шлёт только `notify`

#### Сценарий 24: приёмник писем стенда читает только notify

**ID:** NTF2-24 · G · отрицательный (перенесён из прежнего S6 редакцией 14) · близнец — ствол

**Given** рендер всех цепочек `deploy/stacks.txt`
**And** П7: копия цепочки из множества `L` (ниже) со строкой, называющей приёмник почтовой полосой
объекта вне чарта `notify`

**When** гейт выводит из рендера каждой цепочки адрес приёмника (имя и порт его сервиса), `R` —
цепочки, где приёмник отрендерен, и `L` ⊆ `R` — цепочки, где полоса отправителя `notify` названа на приёмник
**And** считает объекты, чья почтовая полоса названа на адрес приёмника; единица — объявление
почтовой полосы; собственные объекты приёмника читателями не считаются

**Then** в каждой цепочке объектов вне чарта `notify`, чья полоса названа на приёмник, — 0
**And** в каждой цепочке из `L` объявление полосы на приёмник ровно 1, и оно в чарте `notify`
(отправитель `notify`); в `R \ L` — 0 (Р15)
**And** гейт печатает число цепочек, `|R|`, `|L|` и счёт по цепочкам; `R` пусто — красный «пустой
обход»
**And** на копии П7 — красный с именем цепочки и объекта

#### Сценарий 34: чарт notify читает полосу и удостоверение из узла `global.kacho.identity.smtp`

**ID:** NTF2-34 · G · положительный (а), (б), (в), (д), (е'); отрицательный (г), (е) · близнецы — (а) ↔ (б) (одно
значение узла), (а) ↔ (в) (одна цепочка), (г) ↔ (г') (один шаблон), (е) ↔ (е') (одно значение узла) (Р20)

**Given** ствол kacho после посадки NTF-2 и рендер зонтика в вариантах: (а) цепочка `dev` под двумя
именами релиза — `ci` и вторым, выбранным пробой и напечатанным; (б) П7: копия цепочки `dev`, в
которой одно значение `global.kacho.identity.smtp.fromAddress` заменено другим адресом, выбранным
пробой (адрес узла, якорь и прочие значения — как в `dev`, поэтому страж Р19 рендер не отвергает); (в) цепочка `a8f60d`
**And** (д) рендер чарта `notify` без зонтика (NTF1-I06) с собственными значениями, в которых задан
`global.kacho.identity.smtp.{connectionURI, fromAddress, credentialSecret}` значениями, выбранными пробой
**And** (г) П7-tpl: копия `deploy/helm/`, где шаблон чарта `notify` берёт адрес почтовой полосы из
ключа значений вне узла `global.kacho.identity.smtp`, у которого своё непустое значение; близнец
(г') — дерево как есть. Оба рендерятся с контрольными значениями, выбранными пробой и напечатанными:
в узел `global.kacho.identity.smtp.connectionURI` записан контрольный адрес `X`, в
`fromAddress` — контрольный адрес `Y`
**And** (е) цепочка `prod` как есть (узел пуст, флаг `true` — Р20, Д44); близнец (е') — П7: копия
цепочки `prod` с одной добавленной строкой `global.kacho.identity.smtp.connectionURI` = контрольный
адрес `X`, выбранный пробой и напечатанный

**When** гейт рендера выводит из объектов чарта `notify` (принадлежность — `# Source:` под чартом
`notify`, как в NTF2-30) адрес почтовой полосы отправителя, адрес отправителя, ссылку на якорь проверки
узла и ссылку на удостоверение; для (г), (г') — сличает их с контрольными значениями подстановки, а не
ищет имена путей в тексте шаблонов

**Then** (а) для каждого имени релиза адрес полосы отправителя `notify` — имя и порт сервиса приёмника
**этого** релиза (как их выводит NTF2-24); якорь — ключ `ca.crt` секрета `mailpit.tlsSecretName`;
ссылок на секрет почты у чарта `notify` 0 (удостоверения цепочка не объявляет); рендер проходит
**And** (б) адрес отправителя — адрес, записанный пробой в узел; адрес полосы, якорь и ссылки — как
в (а): чарт `notify` читает значение узла, а не своё
**And** (в) адрес полосы — адрес узла, объявленный цепочкой `a8f60d`; ссылка на удостоверение —
`secretKeyRef` на секрет и ключ `global.kacho.identity.smtp.credentialSecret` этой цепочки, ровно одна
(тот же объект, что считает NTF2-30); якоря приёмника нет
**And** (д) рендер проходит без значений зонтика; адрес, отправитель и ссылка на удостоверение — значения,
записанные пробой в `global.kacho.identity.smtp.*` чарта `notify`
**And** (г) — красный «полоса не из узла»: адрес полосы отправителя `notify` в рендере не равен `X`;
находка называет шаблон (`# Source:` объекта) и напечатанный адрес; (г') — молчит: адрес полосы
равен `X`, адрес отправителя — `Y`; гейт печатает `X`, `Y` и число объектов чарта `notify`. Путь, из
которого шаблон берёт значение, различается подстановкой: значение, записанное в узел, доезжает до
объекта, а значение другого пути — нет; строковый поиск путей не отличил бы путь, из которого
значение читается, от пути, который шаблон лишь упоминает
**And** (е) — рендер проходит; ключ адреса ретранслятора отправителя `notify` присутствует и **пуст**,
ссылок на секрет почты у чарта `notify` 0; любой непустой адрес в этом ключе — красный «адрес полосы
подставлен», находка называет шаблон и адрес. Пустой ключ — вход стража старта NTF-1 (Д44): отказ
старта держит проба NTF-1, эта проба его не утверждает; (е') — тот же ключ равен `X`: пустота в (е)
вызвана узлом, а не тем, что ключ не читается
**And** гейт печатает имена релизов (а), адрес, записанный в (б) и (е'), и число объектов чарта `notify` в
каждом варианте; объектов чарта `notify` 0 в любом варианте (а)–(в), (д), (е), (е') — красный «пустой обход»

### §6а Сверка «Тогда» G-сценариев на посеве

Правило документа (класс CONSTRUCTIBILITY, редакции 1–5): каждое «Тогда» G-сценария сверяется на
посеянном рендере до подачи на ревью; итог — «сошлось», «разошлось» (тогда правится сценарий) или
«не выполнилось» с причиной. На базе старта таблица перемеряется вместе с §3а (DoD п.18).

| сценарий | «Тогда» | посев | база | исход |
|---|---|---|---|---|
| NTF2-24 | читатели приёмника вне чарта `notify` | — | 1 в dev, dev-prod, own, prorobotech (`kaname-config`: адрес узла в блоке `invite-mail` — сервис приёмника); a8f60d — 0 (узел внешний) @`96e2fa72b3a` (§1.6) | не выполнилось: читателя kaname снимает сама NTF-2 (Р2), чарта `notify` на базе нет (его заводит NTF-1) |
| NTF2-30, 31 (д) | держателей вне чарта `notify` — 0; адрес узла вне чарта `notify` — 0 | — | держатель — Deployment `kaname` в a8f60d; адрес узла — `kaname-config` в 5 цепочках @`96e2fa72b3a` (§1.6) | не выполнилось на посеве: полосу kaname снимает NTF-2, отправителя `notify` заводит NTF-1 (развёртывание `notify`; раздвоение на `notify-sender` — NTF-3 Р8, предикат от него не зависит); настоящий вход (д) измерен |
| NTF2-34 | полоса и удостоверение отправителя `notify` — из узла `global.kacho.identity.smtp` | — | узел полосы стенда объявлен в `values.dev.yaml`: `connectionURI` — выражение над `.Release.Name` к приёмнику, `trustAnchorSecret` — `ca.crt` секрета, равного `mailpit.tlsSecretName` в `values.yaml`; удостоверения `dev` не объявляет; `a8f60d` объявляет внешний узел, удостоверение и пустой якорь @`96e2fa72b3a` (`git show origin/2798:deploy/helm/umbrella/values.{dev,a8f60d,yaml}.yaml`); вход (е): `connectionURI` и `credentialSecret.name` пусты в цепочках `prod` и `fe3455` — `yq eval-all` Р16 п.5 над `values.yaml` и файлами цепочки → ` \| ` в обеих @`96e2fa72b3a` | не выполнилось: чарта `notify` на базе нет (NTF-1), чтение узла заводит NTF-2 (Р20); входы (а)–(в), (е) измерены; узел на базе старта — условие Р16 п.5 |
| NTF2-31 (ж') | шаблонов, чей `fail` называет `credentialSecret`, — 1 | — | `git grep -lE '\bfail\b.*credentialSecret' origin/2798 -- 'deploy/helm/**/templates/*' \| wc -l` → 1 (`identity-mail-lane-guard.yaml`); на `origin/2564` — 1 (§1.10) | сошлось; гейта переписи шаблонов на базе нет — его вносит NTF-2 |
| NTF2-33 | поставка kaname без узла, флаг обязателен | — | узел и креды в `deploy/values.yaml`, `deploy/values.prod.yaml`, `deploy/templates/configmap.yaml` kaname @`caf1c95ca` (§3б) | не выполнилось: производитель — NTF-2 |
| NTF2-53, NTF2-73 | флаг и инвариант сетки в рендере | — | ручек нет: `git grep -l 'notifications.enabled' origin/2798 -- deploy/helm \| wc -l` → 0 | не выполнилось: производитель — NTF-2 |
| NTF2-54 | литералов отказа 0; ссылка на `feed.DeliveryNotConfiguredStatus` достижима из четырёх действий | — | литералов текста и `reason` в kaname 0 (не-тестовые и тестовые): `git grep -l 'email delivery is not configured\|NOTIFICATION_DELIVERY_NOT_CONFIGURED' origin/367 \| wc -l` → 0; функции в corelib нет — `git grep -l DeliveryNotConfigured origin/26 \| wc -l` → 0 @`cfe49ef00fa`; четыре метода перечня существуют @`caf1c95ca` | не выполнилось: функцию заводит NTF-1 (`corelib#77`), гейт и вызовы — NTF-2 |
| NTF2-08, 45, 47, 98, 99 | гейты дерева kaname | — | шаблонов, перечня `required-security.yaml` и `notifygen` на базе нет (`git ls-tree -d origin/367 notifications \| wc -l` → 0); гейт `people_address_writers` есть | не выполнилось: производители — NTF-1 (`notifygen`, валидатор) и NTF-2 (гейт обязательного класса, перечень) |

Строки NTF2-18, NTF2-20…NTF2-23 прежних редакций сняты вместе со сценариями (Д39).

### §6б Правило → держатель

Правило документа (класс COVERAGE, редакции 1–10): каждое объявленное решением правило, ось лимита,
ручка и строка перечня имеет сценарий, который упадёт, если правила нет. Таблица — перепись по
решениям Р1, Р3–Р12; строка без держателя — возврат в приёмку.

Круг редакции 8 показал, что перепись по правилам пропускает два вида мест: ручку, у которой
названа граница, но не поведение (B-2 круга — ступень `POW`), и свойство «одинаково для любого
адреса», проверенное не на всех действиях, которые его объявляют (B-1 — регистрация). Поэтому к
таблице правил добавлены две переписи по **предмету**, а не по решению: каждая ручка Р8 (таблица
«ручка → поведение») и каждое действие, чей ответ объявлен независимым от адреса (таблица
«равенство для любого адреса»).

Круг редакции 9 показал третий вид пропуска: у ручки-длительности утверждалась одна сторона срока
(«после срока»), а другая проверялась далеко от границы, и реализация с другим сроком проходила оба
сценария (B-1 круга — `mail-throttled-interval` и сроки кода). Поэтому добавлена четвёртая перепись по
предмету — **«длительность → обе стороны»**: каждая длительность таблицы Р8 и каждое окно, заданное
именем ручки («в час», «в сутки»), и сценарий, утверждающий `начало + срок − 1 с` (прежнее состояние) и
`начало + срок` (новое). Перепись получена выборкой по таблице Р8: строки, у которых ориентир или имя
ручки несёт единицу времени.

Круг редакции 12 показал пятый вид пропуска: правило «производитель один, своей копии нет» имело
держателя, который утверждает только **значение** — литералы ответа — и потому зелёный на копии того же
значения (B-1 круга — отказ флага). Поэтому добавлена пятая перепись по предмету — **«единственный
производитель → держатель»**: каждое утверждение документа вида «только X производит / ставит / держит»,
«своего у Y нет», «ровно в одном», и держатель, который красен, если появилась **вторая** копия, а не
только если значение разошлось. Перепись получена выборкой по тексту документа: `единствен`, `только`,
`своего`, `ровно в одном`, `производитель один`.

| решение | правило / ось / ручка | держатель |
|---|---|---|
| Р1 | надзор администратора облака на тип `notification_feed` не распространяется (Д14) | NTF-1 (перечень типов и его держатель); ленту kaname забирает только `notify` — NTF2-46 |
| Р1 | пространство `kaname` авторизует сертификат сервера ленты: чужой SAN — `Claim` не вызван, тревога; `ResolveSend` по `kaname` не зовётся | NTF2-06 (близнец — `SENT` без `ResolveSend`) |
| Р1 | манифест kaname — только `readers: [notify]`; `namespace` и чужой читатель отвергаются; субъекта `service:kaname` нет | NTF2-47 (а, б), близнец — манифест как есть |
| Р1, Р4 | запись перечня `notify` для kaname — `authorization: certificate` с SAN из `kaname.spiffe` | NTF2-53 (близнец) |
| Р3 | 24 шаблона перечня, класс `security`, `limits`, без отписки | NTF2-08, NTF2-99, NTF2-45 |
| Р3 | 23 вида аудита карты «вид → шаблон → адресат» | NTF2-90 (21 вид, 22 строки), NTF2-89 (`access_key.transferred`), NTF2-94 (`session.issued`); сверка карты — NTF2-90 |
| Р3 | правило адресата `access-key-changed` «владелец до и после» | NTF2-89 |
| Р3 | правило адресата `role-granted` «иначе контакт безопасности» | NTF2-90 (строка группы), NTF2-92 |
| Р3 | письма `invite`, `recovery`, `verification`, `registration`, `registration-existing`, `mail-throttled` | NTF2-42, NTF2-43, NTF2-01, NTF2-80, NTF2-81, NTF2-68 |
| Р3 | нет пользовательского текста; «ничего не делайте», без «это не я» | NTF2-91, NTF2-42, NTF2-43 |
| Р4 | флаг без умолчания; выключен — отказ, ноль строк, сервер ленты не поднят, метрика; зонтик | NTF2-50, NTF2-51, NTF2-52, NTF2-53, NTF2-33 |
| Р4 | отказ флага производит только corelib `feed.DeliveryNotConfiguredStatus()`; своего текста и `reason` у kaname нет | NTF2-54 (гейт дерева, инъекции (а)–(в), близнец (г) и дерево как есть); ответ равен полям функции на пине — NTF2-51 |
| Р4 | отказ `NOTIFICATION_DELIVERY_NOT_CONFIGURED` одинаков для любого адреса — у каждого действия, принимающего адрес | NTF2-51: восстановление (а) = (б), регистрация (в) = (ж), приглашение (г) = (з); близнец — те же пары на П6 |
| Р4, Р9 | при выключенном флаге правила пароля идут первыми | NTF2-51 (е) |
| Р5 | счёт ключа — пропущенные запросы; ось источника: три ступени — без вызова, базовая сложность, повышенная сложность, `429` с `Retry-After` | NTF2-60 (а) — номера запросов по ступеням и `difficultyBits` по номеру; NTF2-60 (б) — ступень задаёт ручка `POW`; NTF2-71 (г, д, р, с) |
| Р5 | вызов по оси подсети и общему потоку при счёте источника ниже `POW` — базовая сложность | NTF2-61, NTF2-74 |
| Р5 | ось подсети (`/24`, `/56`, `/48`) | NTF2-61, NTF2-71 (к) |
| Р5 | общий поток (RATE, BURST) | NTF2-74, NTF2-71 (ж, з, и) |
| Р5 | доверенные прыжки: число задано; ключ — адрес на доверенной глубине, цепочка дальше неё на ключ не влияет | NTF2-71 (е), NTF2-79 |
| Р5 | окно ручки — скользящий интервал, запрос выходит из счёта в `t1 + W` | NTF2-60 (в), NTF2-61 (г) |
| Р5 | проверка доказательства краем | NTF2-62 |
| Р5 | область действия звена: `recovery`, `register`; пути предъявления кода, вход и прочие — вне | NTF2-63 |
| Р5 | консоль решает вызов | NTF2-72 |
| Р5 | консоль на `503` звена — отказ дословно, без решателя и повтора; исчерпанный бюджет решателя — `expired`, запроса нет, новый вызов при следующей отправке | NTF2-58 (а, б), близнец (в) |
| Р5 | хранилище ограничителя недоступно — `503`, одинаково для любого адреса и пути, до kaname не доходит; непроверенное доказательство не пропускается | NTF2-59, близнец — исправное хранилище; `503` не истрачивает вызов — NTF2-59 (д) |
| Р5 | третий повод `503` — ожидание блокировки ключа дольше предела звена | проба замысла З8 (`docs/changes/issue-2917/design.md`, инвариант И6, CX2-28 (б)); поводы «хранилище не отвечает» и «запрос не исполнен» — NTF2-59 |
| Р5 | консоль показывает `message` отказа дословно, своего текста у экрана нет | NTF2-58 (г): текст, выбранный пробой, показан дословно |
| Р8 | лимит шаблона `recovery`, `verification`, `registration`, `registration-existing` не ниже наибольшего числа писем, допускаемого верхними границами Р8 | проба замысла З19 (`docs/changes/issue-2917/design.md`, инвариант И14) |
| Р5 | ось источника только у края: kaname по источнику на `recovery` и `register` не отказывает (замещение `kaname#456`, §3) | NTF2-60 (а) — `H` пропущенных доходят до kaname, `H > source-attempts` |
| Р6 | окно `recovery`: паузы, потолки, тот же код, ответ один, строки для адреса без учётки нет | NTF2-64, NTF2-71 (а, б) |
| Р6 | номер письма прогрессии — по часовому окну; паузы — от прошлого письма прогрессии | NTF2-64 (ряд и `u + 1 ч`), NTF2-65 (г), NTF2-70 (в) — первое письмо при пустом часовом окне, второе — через `first-pause` |
| Р6 | пол при скользящих окнах: действует в исчерпании `[Tc, Tw)`, от `Tc`; при `Tc + Fl ≥ Tw` пола нет; с `Tw` прогрессия возобновляется | NTF2-65 (а, б) — пол при `Tc + Fl < Tw`; NTF2-65 (г), NTF2-75, NTF2-76 — `Tw` на копии с `Fl` = 24 ч; NTF2-71 (в) |
| Р6 | длительности — полуоткрытые; часовое и суточное окна скользящие и считают только письма прогрессии | таблица «длительность → обе стороны» ниже |
| Р6 | старшинство исходов: `capped` старше `cooldown` | NTF2-65 (в) |
| Р6 | запас доверенного устройства: по паре (адрес, метка), без пауз, сверх — окно адреса | NTF2-70 |
| Р6 | окно `registration`: ключ — нормализованный ввод, строка для свободного адреса, одна прогрессия для свободного и занятого | NTF2-75, NTF2-71 (л) |
| Р6 | окно `verification`: явный `429`, потолки, пол | NTF2-05, NTF2-40, NTF2-76 |
| Р6 | срок кода `recovery` / `verification` / `registration`: от постановки, повтор не продлевает; обе стороны | NTF2-87 (а, б, в); NTF2-65, NTF2-71 (м) / NTF2-41, NTF2-71 (ч) / NTF2-83, NTF2-71 (ш) |
| Р6 | неверные предъявления код не гасят | NTF2-03, NTF2-82, NTF2-66 (а, б) |
| Р6 | ось «адрес + источник» на обоих анонимных путях предъявления | NTF2-66 (а) `recovery/complete`, NTF2-66 (б) `register/confirm` |
| Р6 | потолок неудач адреса: только без метки; окно от первой неудачи; истечение | NTF2-66 (в, г) |
| Р6 | ответ вне пути постановки | NTF2-67 |
| Р6 | письмо о торможении: повод — исход `capped` окна `recovery` адреса с учётной записью; раз в интервал; сверх окна, окна не расходует; для адреса без учётной записи нет | NTF2-68 (а) — одна строка на первый `capped`, прочие `capped` строки не дают, строк окна не прибавилось; (б) — `capped` в `Ts + Ti − 1 с` строки не даёт, `capped` в `Ts + Ti` — даёт; (в) — `Z` |
| Р6, Р8 | письмо о торможении — слагаемое инварианта сетки | NTF2-73 (второй близнец) |
| Р6 | пол и исход `floor` для окон всех трёх назначений | `recovery` — NTF2-65; `verification` — NTF2-76; `registration` — NTF2-75 |
| Р6 | закрытый набор исходов метрики | NTF2-64 (`queued`, `resent_same`, `cooldown`, `capped`), NTF2-65 (`floor`), NTF2-70 (`trusted_device`); `dropped_overload` — диспетчер почтовых работ kaname при занятых местах (**NTF-2**, замысел З13, З14), держатель — модульные пробы замысла (`docs/changes/issue-2917/tasks.md`, S1, S2, S12; CX2-17, CX2-34) |
| Р7 | приглашает только подтверждённый | существует (рубеж Ф6), не меняется |
| Р7 | потолок аккаунта, моложе порога — ниже | NTF2-69 (а, б) — `young` в `Ya − 1 с`, `mature` в `Ya`; (г) — граница суток |
| Р7 | потолки адресата в час и в сутки от аккаунта; в сутки поперёк аккаунтов | NTF2-77 (а, б, д, е), NTF2-69 (в, д), NTF2-71 (н) |
| Р7 | висящие приглашения, срок приглашения | NTF2-77 (в, г), NTF2-71 (о) |
| Р8 | снятые ручки — неизвестный ключ | NTF2-48 |
| Р8 | инвариант сетки `notify` ≥ 1,25 × суммы | NTF2-73 |
| Р9 | ответ одинаков, пароль первым, письмо, confirm, истечение, гонка | NTF2-80…NTF2-85 |
| Р9 | код привязан к паролю своего запроса; повтор с тем же / другим паролем | NTF2-86, NTF2-84 |
| Р9 | запись с истёкшим кодом не жива: повтор — новая запись, `queued` | NTF2-83 |
| Р10 | идемпотентность строки класса S | NTF2-97 |
| Р11 | адресаты: ACTIVE и подтверждённый в момент отправки; SA и группа — не адресаты; администраторы облака | NTF2-92, NTF2-93, NTF2-96 |
| Р11 | справочник адресов и разрешение адресатов — только `service:notify` | NTF2-88 |
| Р11 | адресаты — снимком в транзакции события, строка на адресата; в отправке разрешается только адрес | NTF2-90 (строка `account.deleted`: строка на `O` поставлена транзакцией события и доставлена после удаления `acc`), NTF2-96 |
| Р12 | метка устройства, письмо нового устройства — только путь входа | NTF2-94 |
| Р12 | сессии `register/confirm` и `recovery/complete` метку выдают, письма нового устройства не дают | NTF2-80, NTF2-43 |
| Р12 | срок метки от выдачи, вход не продлевает | NTF2-78 (а, б) |
| Р12 | запас доверенного устройства (`recovery-per-day`), срок метки (`ttl`) | NTF2-70 (а, в), NTF2-78, NTF2-71 (п) |

**Ручка → наблюдаемое поведение.** Для каждой ручки Р8 — что меняется при её значении, и сценарий,
который красен, если ручку читает только страж старта (значение из профиля, поведение — нет).
Отсутствие **каждой** ручки судит NTF2-71 (т) — перебором по таблице Р8; границы — выборкой вариантов
NTF2-71 (б)–(с), (у), (ф) — не меньше одной на каждую строку таблицы Р8. У ручки-длительности обе стороны границы названы
в таблице «длительность → обе стороны». Граница `ttl ≥ first-pause` судится у всех трёх назначений —
NTF2-71 (м, ч, ш); окна края — NTF2-71 (х, ц).

| ручка | наблюдаемое поведение | держатель |
|---|---|---|
| `…ANON_MAIL_IP_FREE_{LIMIT,WINDOW}` | номер первого запроса с вызовом — `F + 1`; окно `W_F` | NTF2-60 (а, в1), NTF2-79 |
| `…ANON_MAIL_IP_POW_{LIMIT,WINDOW}` | номер первого вызова с `Dh` — `P + 1`; при `POW` = `HARD` вызовов с `Dh` нет; окно `W_P` | NTF2-60 (а, б, в2) |
| `…ANON_MAIL_IP_HARD_{LIMIT,WINDOW}` | номер первого `RATE_LIMITED` — `H + 1`; окно `W_H` | NTF2-60 (а, в3), NTF2-63 |
| `…ANON_MAIL_POW_BITS_BASE`, `…_HIGH` | `difficultyBits` вызова равен ручке своей ступени | NTF2-60 (а), NTF2-61, NTF2-74 |
| `…ANON_MAIL_SUBNET_{V4_24,V6_56,V6_48}_{POW,HARD}_LIMIT` · `…ANON_MAIL_SUBNET_{POW,HARD}_WINDOW` | вызов сверх `Ps`, `RATE_LIMITED` сверх `Hs` — для каждой длины префикса своей ручкой; окна `W_Ps`, `W_Hs` | NTF2-61 (а–г) |
| `…ANON_MAIL_GLOBAL_{RATE_PER_SECOND,BURST}` | число ответов без вызова в одной секунде — от `B` до `B + G` | NTF2-74 |
| `KACHO_API_GATEWAY_TRUSTED_HOPS` | ключ — адрес на глубине `h` | NTF2-79 |
| `…mail-window.recovery.{first-pause,second-pause,per-hour,per-day}` | моменты строк ряда (`−1 с` и в момент), часовая и суточная границы, число строк | NTF2-64, NTF2-65 (г) |
| `…mail-window.recovery.floor-interval` | при `Tc + Fl < Tw`: `Tc + Fl − 1 с` — `capped`, `Tc + Fl` — `floor`; при `Fl` = 24 ч пола в исчерпании нет, в `Tw` — прогрессия | NTF2-65 (а, б, г) |
| `…mail-window.verification.*` | первая пауза; ряд до суточного потолка, часовая и суточная границы, пол | NTF2-05, NTF2-76 |
| `…mail-window.registration.*` | первая пауза; ряд до суточного потолка, часовая и суточная границы, пол | NTF2-86 (ж), NTF2-75 |
| `authn.login.recovery-code-ttl` · `verification-code-ttl` · `registration-code-ttl` | в `Tk + ttl − 1 с` повтор шлёт тот же код и код принят; в `Tk + ttl` код отвергнут, повтор чеканит новый | NTF2-87 (а, б, в); NTF2-65 · NTF2-41 · NTF2-83 |
| `authn.login.attempts.{address-source-per-window,window}` | `N` неверных — затем отказ по частоте; окно истекает в `Tf + W` | NTF2-66 (а, б, г, д) |
| `authn.login.attempts.address-failure-ceiling` | после `Cf` неверных — отказ без метки, проход с меткой | NTF2-66 (в) |
| `authn.login.mail-throttled-interval` | `capped` в `Ts + Ti − 1 с` строки не даёт, `capped` в `Ts + Ti` — даёт | NTF2-68 (б) |
| `invite.{account-per-day,young-account-per-day,young-account-age}` | номер отказа `INVITATION_RATE_LIMITED`; порог возраста — `Ya − 1 с` моложе, `Ya` не моложе; граница суток | NTF2-69 (а, б, г) |
| `invite.{recipient-per-hour,recipient-per-day}` · `recipient-per-day-all` | число строк `invite` адресату; границы часа и суток; `recipient-per-day-all` не выше лимита шаблона `invite` (50 — старт, 51 — отказ) | NTF2-77 (а, б, д, е) · NTF2-69 (в, д), NTF2-71 (щ) |
| `invite.pending-max` · `invite.ttl` | номер отказа `INVITATION_PENDING_LIMIT`; место освобождается в `Tv`, в `Tv − 1 с` — нет | NTF2-77 (в, г) |
| `authn.login.trusted-device.{ttl,recovery-per-day}` | метка не действует с `T + Tt`, в `T + Tt − 1 с` действует; строк `trusted_device` — `R`, запас возвращается в `t1 + 1 сут` | NTF2-78, NTF2-70 (а, в) |
| `notifications.enabled` | см. строку Р4 | NTF2-50…53 |

**Длительность → обе стороны.** Каждая длительность Р8 — ручка со значением времени или окно, заданное
именем ручки, — по назначению, если ручка по назначению своя. Сторона «до» — `начало + срок − 1 с`,
прежнее состояние; сторона «в момент» — `начало + срок`, новое (Р6). Строка без обеих сторон —
возврат в приёмку. Строк 25.

| длительность | начало | в `− 1 с` | в момент | держатель |
|---|---|---|---|---|
| окно `FREE` источника `W_F` (`…IP_FREE_WINDOW`) | пропуск `F` запросов в `t1` | вызов `Db` | без вызова | NTF2-60 (в1) |
| окно `POW` источника `W_P` (`…IP_POW_WINDOW`) | пропуск `P` запросов в `t1` | вызов `Dh` | без `Dh` | NTF2-60 (в2) |
| окно `HARD` источника `W_H` (`…IP_HARD_WINDOW`) | пропуск `H` запросов в `t1` | `RATE_LIMITED` | не `RATE_LIMITED` | NTF2-60 (в3) |
| окно `POW` подсети `W_Ps` (`…SUBNET_POW_WINDOW`, каждая длина префикса) | пропуск `Ps` в `t1` | вызов | без вызова | NTF2-61 (г) |
| окно `HARD` подсети `W_Hs` (`…SUBNET_HARD_WINDOW`, каждая длина префикса) | пропуск `Hs` в `t1` | `RATE_LIMITED` | не `RATE_LIMITED` | NTF2-61 (г) |
| `recovery.first-pause` · `second-pause` | прошлое письмо | `cooldown`, строки нет | строка | NTF2-64 |
| `verification.first-pause` · `second-pause` | прошлое письмо | `429` `TOO_MANY_ATTEMPTS` | `200`, строка | NTF2-05, NTF2-76 |
| `registration.first-pause` · `second-pause` | прошлое письмо | `cooldown` | строка | NTF2-86 (ж, а), NTF2-75 |
| часовое окно `recovery` · `verification` · `registration` | строка `u` | `capped` / `429` | строка | NTF2-64 · NTF2-76 · NTF2-75 |
| суточное окно `recovery` · `verification` · `registration` | строка `t0`; момент — `Tw = t0 + 1 сут` | `capped` / `429` | строка `queued` или `resent_same`, не `floor` | NTF2-65 (г) · NTF2-76 · NTF2-75 |
| `recovery.floor-interval` | `Tc`, при `Tc + Fl < Tw` | `capped` | `floor` | NTF2-65 (а, б) |
| `verification.floor-interval` | `Tc`, при `Tc + Fl < Tw` | `429` | `floor` | NTF2-76 |
| `registration.floor-interval` | `Tc`, при `Tc + Fl < Tw` | `capped` | `floor` | NTF2-75 |
| `recovery-code-ttl` | строка `Tk` | тот же код, код принят | новый код, `K` — `401` | NTF2-87 (а) |
| `verification-code-ttl` | строка `Tk` | тот же код, код принят | новый код, `K` — `401` | NTF2-87 (б) |
| `registration-code-ttl` | строка `Tk` | тот же код, код принят | новый код, `K` — `401` | NTF2-87 (в) |
| `attempts.window`, ось «адрес + источник» | неудачи в `Tf` | отказ по частоте | `200` | NTF2-66 (д) |
| `attempts.window`, потолок неудач адреса | первая неудача `Tf` | отказ по частоте | `200` | NTF2-66 (г) |
| `mail-throttled-interval` | строка `mail-throttled` в `Ts` | `capped` без строки | `capped` и строка | NTF2-68 (б) |
| `invite.young-account-age` | заведение аккаунта | моложе порога | не моложе | NTF2-69 (а, б) через П6-age |
| суточное окно `account-per-day` · `young-account-per-day` | приглашения `T + Ya` | `INVITATION_RATE_LIMITED` | `Operation` и строка | NTF2-69 (г) |
| часовое окно `recipient-per-hour` | приглашения `C` в `t1` | `capped` | строка | NTF2-77 (д) |
| суточное окно `recipient-per-day` · `recipient-per-day-all` | приглашения `C` в `t1` | `capped` | строка | NTF2-77 (е) · NTF2-69 (д) |
| `invite.ttl` | заведение первого висящего | `INVITATION_PENDING_LIMIT` | `Operation` | NTF2-77 (г) и близнец |
| `trusted-device.ttl` · суточное окно `recovery-per-day` | выдача метки `T` · письма запаса `t1` | метка действует · `capped` | новая метка · `trusted_device` | NTF2-78 · NTF2-70 (в) |

`GLOBAL_RATE_PER_SECOND` — скорость, а не длительность: обе её стороны — нижняя `B` и верхняя `B + G`
граница числа ответов без вызова за секунду (NTF2-74). Срок вызова PoW и срок строки ленты — не ручки
Р8: первый держат NTF2-62 (б) с близнецом, второй — NTF-1 (NTF2-07 утверждает `T_alarm − 1 с` и `T_alarm`).
Бюджет решателя консоли `Bs` — тоже константа, а не ручка Р8; обе его стороны — `Bs − 1 с` и `Bs` —
утверждает NTF2-58 (б).

**Равенство для любого адреса.** Каждое действие, чей ответ объявлен независимым от того, есть ли у
адреса учётная запись, и сценарий, сравнивающий оба адреса на **каждом** исходе этого действия.

| действие | исходы, на которых сравнивается | держатель |
|---|---|---|
| `recovery` | флаг выключен · окно (прогрессия, потолки, пол) · ступени края · хранилище ограничителя недоступно · блокировка ленты | NTF2-51 (а, б) · NTF2-64 (близнец `Z`) · NTF2-60 · NTF2-59 (а, б) · NTF2-67 |
| `register` | флаг выключен · негодный пароль · окно · хранилище ограничителя недоступно · ответ шага 1 | NTF2-51 (в, ж) · NTF2-85 · NTF2-75 (близнец `A`) · NTF2-59 (в) = (а) · NTF2-81 |
| `users:invite` | флаг выключен | NTF2-51 (г, з); прочие исходы приглашения говорят о состоянии аккаунта вызывающего, а не об адресате (Р7) |
| `recovery/complete`, `register/confirm` | отказ по частоте · неверный код | равенство для адреса, которого нет, держит существующий Ф5-08; NTF2-66 (а, б) утверждает тот же отказ на обоих путях; NTF2-82, NTF2-86 (в, г) — `401` побайтово как у неверного кода |

**Единственный производитель → держатель.** Держатель красен на второй копии, а не только на
расхождении значения. Строк 11 (редакция 14 добавила «страж секрета почты один», Д39; редакция 16 —
«узел почтовой полосы один», Р20).

| правило | где объявлено | держатель, красный на второй копии |
|---|---|---|
| отказ флага производит только corelib; своего текста и `reason` у kaname нет | Р4 | NTF2-54 (а)–(в) |
| письмо ставится только сгенерированной функцией шаблона | Р2, DoD п.2 | NTF1-B28 (гейт `Put`: ссылка на `feed.Put` вне файлов генератора, дерево kaname в обходе); виды писем = шаблоны — NTF2-45 |
| отправителей SMTP в kaname нет | Р2 | NTF2-44 (копия П8 с импортом `net/smtp` — красный) |
| консоль: своего текста отказа у экрана нет | Р5 | NTF2-58 (г) |
| справочник адресов и разрешение адресатов отвечают только `notify` | Р11 | NTF2-88 (служба с проверенным сертификатом, не `notify`, — отказ) |
| глагол смены адреса вносится только с письмом прежнему адресу | Р13 | NTF2-98 |
| секрет почты смонтирован ровно в одном объекте — отправителе `notify` | Р19, S7 | NTF2-31 (а), (б), (д) — второй держатель в рендере красный |
| страж секрета почты один — `identity-mail-lane-guard.yaml` | Р19 (Д39) | NTF2-31 (ж) — второй шаблон с `fail` о `credentialSecret` под любым именем красен в CI; (ж') — молчит на дереве |
| пустой узел доезжает до ключа адреса ретранслятора отправителя `notify` пустым — умолчания нет | Р20 (Д44) | NTF2-34 (е) — непустой адрес в рендере `prod` красен; (е') — ключ равен `X`; отказ старта на пустом ключе — проба NTF-1 |
| узел почтовой полосы и удостоверения один — `global.kacho.identity.smtp`; чарт `notify` своего не несёт | Р20 (Д42) | NTF2-34 (г) — шаблон чарта `notify`, берущий полосу из ключа вне узла, красен в CI: адрес полосы в рендере не равен контрольному `X`, записанному в узел; (г') — молчит на дереве, адрес равен `X`; (б) — значение узла доезжает до отправителя |
| правда о подтверждённости одна — отметка kaname | Р19 | рубеж по отметке kaname — NTF2-19; второй источник — хук поставщика `require_verified_address` — снимает `kacho#1276` (Д39); в рендере цепочек его 0 (`grep -c require_verified_address chain-<n>.yaml` → 0 в 7 из 7 @`96e2fa72b3a`, поставщик выключен) |
| ось источника анонимных почтовых глаголов только у края | Р5, §3 | NTF2-60 (а) (`H > source-attempts` запросов доходят до kaname); предикат `ChargeSource` → пусто — DoD п.7 |

### §6в Given и счёт → построение

Правило документа (класс CONSTRUCTIBILITY, редакции 1–10): Given каждого сценария строится посевом
§5 или исходом названного сценария, а каждое «Тогда» верно на верной реализации при любой скорости
прогона. Круг 2 редакции 7 нашёл три нарушения одного рода (B2-1…B2-3) и одно смежное (B2-4), поэтому
перепись ниже проведена по всему §6 по четырём признакам: (1) Given оставляет в окне или счётчике
состояние, от которого зависит When; (2) счёт писем или строк захватывает побочные события
построения; (3) общий счётчик стенда делят кейсы; (4) исход зависит от момента, который Given не
фиксирует. Строка, найденная переписью без построения, — возврат в приёмку.

Круг редакции 8 нашёл место, которое перепись по признаку 4 пропустила (NTF2-68: символ момента без
ряда, который его строит, и символ, уже занятый Р6), поэтому редакция 9 добавила два признака и
провела их **механически** — по перечню символов времени в тексте §6, а не чтением: (5) каждый символ
момента в Given или When определён в своём сценарии рядом, который его строит, или ссылкой на
определение в решении; (6) «побайтово равны» не утверждается о полях, различных у каждого ответа.
Перечень символов редакции 12 (`T`, `T_alarm`, `t0`, `t1`, `u`, `s`, `Tc`, `Tw`, `Tc'`, `Tw'`, `Tk`, `Tk1`, `Tr`, `Tf`, `W`, `Ti`,
`Ts`, `Tt`, `Tv`, `Ya`, `W_F`, `W_P`, `W_H`, `W_Ps`, `W_Hs`, `Bs`) получен выборкой из текста §6 — символ в
обратных кавычках, отдельно или с `+`/`−`; сценариев с символом — 17: NTF2-05, 07, 58, 60, 61, 64, 65, 66, 68,
69, 70, 75, 76, 77, 78, 86, 87; и ещё два со сроком кода от постановки строки без символа — NTF2-41, 83.
Редакция 9 называла 13: выборка тогда не брала `T_alarm` (NTF2-07, I-2 круга); редакция 12 добавила `Bs`
(NTF2-58). Сценарий NTF2-59 символа момента не несёт: часы пробы в нём стоят.

| признак | сценарий | зависимость | построение |
|---|---|---|---|
| 1 | NTF2-81 | окно `registration` адреса, построенного регистрацией | человек посевом П10: окна нет, первое письмо пропускается сразу |
| 1 | NTF2-75 (близнец), NTF2-85 | занятый адрес и его окно | П10; отсутствие строки окна печатается (NTF2-75) |
| 1 | NTF2-40 | письмо `K1` из Given в том же окне `verification` | ожидание `first-pause`, значение печатается пробой |
| 1 | NTF2-43, NTF2-94 | человек П2, построенный регистрацией | When идёт в другое окно (`recovery`) или не в окно вовсе (§5) |
| 1 | NTF2-66 (в, г) | успешное предъявление сбрасывает счёт неудач | отдельные повторы пробы; в (г) предъявлений с меткой нет |
| 1 | NTF2-78 | вход с меткой в (а) мог бы продлить её срок | срок от выдачи, вход не продлевает (Р12) |
| 1 | люди и объекты уровня I | чем заведены, чисты ли окна | фикстура П11: без глаголов почты и окон |
| 2 | NTF2-01, 42, 43, 80, 81, 94 | письма других шаблонов на тот же адрес (вход, построение П2) | счёт по шаблону и от ответа When (§6); сессия `register/confirm` письма нового устройства не даёт (Р12) |
| 2 | NTF2-90, 92, 96 | вспомогательные события пробы (повторное заведение фактора, входы, запрос кода) | счёт по паре (событие, адресат) |
| 3 | NTF2-72 | счётчики края по источнику раннера П1 | близнец первым действием кейса; `V < F` объявлено П1 и печатается; ступень создаёт шаг 2; нарушение объявления — «не выполнилось» |
| 3 | прочие E-кейсы | те же счётчики | E-клиент решает вызов PoW, ступени не утверждаются (§5) |
| 3 | NTF2-07, 51, 65, 67, 68, 70, 78, 83, 84, 86, 87, 90, 95 | порог края по источнику на П6 | источник по умолчанию П6: свой адрес и `/24` на запрос (§5) |
| 3 | NTF2-63, 66 | запросы с `S1` после исчерпания порога | пути предъявления кода вне ограничителя края (Р5) |
| 3 | NTF2-59 | хранилище ограничителя — общее состояние стенда | своя копия П6 пробы (§5, «состояние, общее для кейсов»); источники `S4`, `S6` — свои; вызов `C` получен до остановки хранилища и не предъявлен; близнец — отдельная копия П6 с тем же посевом и исправным хранилищем |
| 3 | NTF2-58 | ответ края на `recovery` | задаёт перехват страницы П12; к краю П1 запрос восстановления не уходит, счётчики края П1 не меняются |
| 4 | NTF2-65 (в), NTF2-70, NTF2-78 (в) | момент относительно потолка и пола | `Tc` и `Tw` определены одним правилом Р6 («пол при скользящих окнах»); момент лежит в исчерпании `[Tc, Tw)` и раньше `Tc + Fl`: `Fl ≥ 1 ч`, `Tw − Tc` печатается (ряд NTF2-64 короче суток); старшинство `capped` над `cooldown` |
| 4 | NTF2-66 (г) | момент истечения потолка неудач | окно от первой неудачи `Tf`; моменты `Tf + W − 1 с` и `Tf + W` |
| 4 | NTF2-83 | повтор после истечения кода | запись с истёкшим кодом не жива, исход `queued` (Р9) |
| 4, 5 | NTF2-68 | момент срабатывания и повтора письма о торможении | `Ts` — первый `capped` ряда NTF2-64 (свой символ, не `Tc`); повторы — `Tc + 1 с`, `Tc + 2 с`, `Tc + Fl − 1 с` в исчерпании `[Tc, Tw)` раньше пола при условии `Tc + Fl ≤ Tw` (печатается), исход `capped` (Р6); граница `Ts + Ti` — строкой NTF2-68 (б) выше |
| 2 | NTF2-64, 65, 70, 78 | первый `capped` ряда ставит строку `mail-throttled` | счёт строк этих рядов — по шаблону `recovery` (§6); `mail-throttled` утверждает только NTF2-68 |
| 4 | NTF2-75, NTF2-76 | счёт «за сутки не больше `per-day`» при письме пола | до `Tc` включительно — `per-day`; с полом — `per-day` + ⌈24 ч / `Fl`⌉ |
| 5 | NTF2-76 | `Tc` окна `verification` | определён в Given сценария по Р6 |
| 5 | NTF2-75 | `Tc` окна `registration` | определён в When сценария по Р6 |
| 5 | NTF2-77, NTF2-78 | один символ `Tt` для двух разных сроков | срок приглашения — `Tv` (NTF2-77), срок метки — `Tt` (NTF2-78) |
| 5 | NTF2-69, NTF2-77 | возраст аккаунта задан числом, а порог — ручкой | возрасты `Ya − 1 с` и `Ya` от ручки `young-account-age` в одном моменте `T + Ya` (П6-age) |
| 5 | NTF2-05, 41, 66, 83, 86 | `T`, `Tf`, срок кода | момент постановки или первой неудачи — действием Given; сроки — ручками, печатаются пробой |
| 4, 5 | NTF2-58 (б) | момент исчерпания бюджета решателя | `Bs` отсчитывает таймер главного потока страницы, останавливающий `Worker`; часы страницы стоят и переводятся пробой на `Bs − 1 с` и `Bs`; решение, найденное раньше `Bs`, — «не выполнилось» с печатью момента, а не красный |
| 4, 5 | NTF2-60 (в), NTF2-61 (г) | момент выхода запросов из окна ручки края | построение в один момент `t1` при стоящих часах; ответы-вызовы и отказы в счёт не входят (Р5), поэтому `− 1 с` и момент — в одном повторе; `F ≤ BURST`, `Ps < Hs` печатаются |
| 4, 5 | NTF2-64, 75, 76 | часовая граница `u` | `u` — самая ранняя строка часового окна при первом `capped`; условие `per-hour < per-day` и вторая пауза в `u + 1 ч` печатаются |
| 4, 5 | NTF2-65 (г), 75, 76 | суточная граница `t0 + 1 сут` и пол | `Tw = t0 + 1 сут` (самое раннее письмо ряда — `t0`, ряд короче суток); копия П6 с `floor-interval` = 24 ч: `Tc + 24 ч ≥ Tw`, пола в исчерпании нет; в `Tw` прогрессия возобновляется; условие пустого часового окна `Tc ≤ t0 + 23 ч` печатается |
| 4 | NTF2-65 (а, б), 75, 76 | момент пола `Tc + Fl` | условие `Tc + Fl < Tw` печатается, иначе «не выполнилось»; в базовом профиле `t0 + 7 ч 5 мин` против `t0 + 1 сут` |
| 5 | NTF2-65 | `K1` не определён (I-3 круга) | `K1` — код строки в `Tc`, `Tk1` — её чеканка; ветвь «новый / тот же» выбирается `Tk1 + Tr ≤ Tc + Fl` и печатается |
| 4, 5 | NTF2-66 (д) | окно оси «адрес + источник» | `N` неудач в `Tf` при стоящих часах; код `K5` запрошен в `Tf + W − 2 с`; `N < Cf` печатается |
| 4 | NTF2-68 (а) | «ровно одна» строка при ряде длиннее `Ti` (I-1 круга) | условие `Tc + Fl − 1 с < Ts + Ti`; оба момента печатаются |
| 4, 5 | NTF2-68 (б) | `capped` в `Ts + Ti − 1 с` и в `Ts + Ti` | ряд из `per-hour` писем с началом `s`, окна `A` в `s` пусты; часовое окно исчерпано в обоих моментах; `s` печатается |
| 1, 5 | NTF2-69 | два аккаунта П6-age в одном моменте (I-5 круга); повторы (а)–(в) делили окно аккаунта | `mature` в `T`, `young` в `T + 1 с`, часы в `T + Ya`; (а), (б), (в) — отдельные повторы; `pending-max > account-per-day`; `k` аккаунтов для потолка поперёк аккаунтов; `young'` при `Ya > 1 сут` |
| 4 | NTF2-70 (в) | окно адреса и пол в `t1 + 1 сут − 1 с` и `t1 + 1 сут` | письма без метки перед отрезком исчерпывают часовое окно; суточное либо не исчерпано, либо исчерпано с `Tc'`, `Tw'` по Р6 и моменты раньше `Tc' + Fl`; счёт обоих окон печатается; в базовом профиле суточное — 3 < `per-day`, пол не действует |
| 4 | NTF2-77 (д, е) | границы часа и суток по адресату | построение в `t1` при стоящих часах; `recipient-per-hour < recipient-per-day` в (д); копия П6 с равными потолками в (е) |
| 1, 4 | NTF2-87 | повтор в `Tk + ttl − 1 с` разрешён прогрессией | построение без прошлых писем в окне; условие `ttl − 1 с ≥ first-pause` печатается; (1) и (2) — отдельные повторы |
| 6 | NTF2-60 | ответы-вызовы для `A` и `Z` | `challenge` и `expiresAt` из сравнения исключены (§6, «побайтово равны») |
| 6 | прочие «побайтово» (NTF2-06, 51, 59, 64, 67, 70, 75, 81–86) | заголовки времени и `Retry-After` | определение «побайтово равны» (§6): статус, тело, имена `Set-Cookie` |

---

## §7 Сценарий → производитель

Производитель — то, что делает «Тогда» истинным. Если его нет на базе, его заводит названная
посадка; условие Р16 не даёт NTF-2 начаться раньше NTF-1.

| ID сценария | что производит «Тогда» | координата в дереве | чем измерено / кто заводит |
|---|---|---|---|
| NTF2-01, 02, 03, 19 (а, б) | глагол и рубеж подтверждения, `emailVerified`, `401` | kaname `internal/handler/loginlanehttp/handler.go`, `internal/apps/kaname/api/humansession/verification.go` | существует: `git grep -c '/iam/v1/auth/verify-email' origin/367 -- internal/handler/loginlanehttp/handler.go` → 2 @`caf1c95ca` |
| NTF2-01, 40, 42, 43, 80, 81, 94 (доставка) | письмо, `From`, без `Reply-To`, multipart, `cid:`, origin, `Message-ID` | `kacho/services/notify` (отправитель `notify`: развёртывание `notify` в NTF-1; после NTF-3 Р8 — `notify-sender`) | NTF-1 (`kacho#2915`); раздвоение развёртывания — NTF-3 (`kacho#2918`, Р8, NTF3-127), NTF-2 его не ждёт (Р16); на базе нет — `git ls-tree -d origin/2798 services/notify \| wc -l` → 0 |
| NTF2-01, 05, 40, 41, 42, 43, 64, 75, 76, 80, 81, 86, 87, 89, 90 (постановка) | строка ленты kaname шаблоном Р3 в транзакции события | kaname: вызовы сгенерированных функций `corelib notify/feed`; `notifications/` | **NTF-2** (`kaname#484`); функции и лента — NTF-1 (`corelib#77`) |
| NTF2-40, 41, 64, 65, 75, 76, 86, 87 | повтор того же живого кода, прогрессия, пол, скользящие часовое и суточное окна, срок кода от чеканки; ключ окна по назначению; код, привязанный к паролю | kaname: окна адресата на счётчике ленты, хранилище ожидающих регистраций | **NTF-2** (`kaname#484`) |
| NTF2-05 | `429` `TOO_MANY_ATTEMPTS` и отсутствие строки | окно `verification` kaname | существует по форме (Ф6 EV-23); величины — **NTF-2** |
| NTF2-06 | отказ подключения при чужом SAN, `Claim` 0, тревога `source_identity_mismatch`, `ResolveSend` 0, неизменный ответ | запись перечня `notify` с `authorization: certificate` и проверка SAN (`notify`); сервер ленты kaname | проверка SAN, тревога и исключение — NTF-1 (Р3, NTF1-G22); подъём сервера ленты kaname с сертификатом из `kaname.spiffe` — **NTF-2** |
| NTF2-07, 09 | `EXPIRED(platform_unavailable)`, возврат лимита, тревога, `DEFER`/`template_skew` | уборщик `corelib notify/feed`, `notify` | NTF-1; шаблоны kaname — **NTF-2** |
| NTF2-08, 99 (б) | красная проверка шаблона | `cmd/notifygen -check` (`notify/spec`) | NTF-1 (`corelib#77`); шаблоны Р3 — **NTF-2** |
| NTF2-99 (а, в, г) | красный гейт обязательного класса | kaname `internal/check` (новый гейт) над `notifications/required-security.yaml` | **NTF-2** (`kaname#484`) |
| NTF2-44 | 0 импортов `net/smtp`, нет таблицы очереди | гейт kaname `internal/check/` (переписанный `mail_send_paths`), новая миграция | **NTF-2** (`kaname#484`); на базе 2 файла с импортом (§1.1) |
| NTF2-45 | шаблоны = вызовы | гейт kaname (переписанный `mail_kind_sender_parity`) | **NTF-2** |
| NTF2-46 | `PERMISSION_DENIED` у чужой службы | сервер ленты `corelib notify/feed` в kaname | NTF-1 (сервер); подъём в kaname — **NTF-2** |
| NTF2-47 | находка «у службы доступа служебного принципала нет», отказ чужого читателя, ровно один кортеж `reader` | валидатор и применитель манифеста kaname; встроенный манифест kaname (`internal/servicemanifest/manifest.embedded.yaml`) | валидатор и применитель — NTF-1 (NTF1-F21); раздел `notifications: {readers: [notify]}` манифеста — **NTF-2** |
| NTF2-48 (а–г), 50, 71 (kaname) | отказ старта на неизвестном ключе, без флага, вне границ | конфигурация kaname `internal/apps/kaname/config/` | **NTF-2** |
| NTF2-51 | `400`; `code`, `message`, `details` равны полям `feed.DeliveryNotConfiguredStatus()` на пине | глаголы kaname под флагом зовут единый отказ corelib `feed.DeliveryNotConfiguredStatus()` | статус и его текст — NTF-1 (`corelib#77`, NTF1-N06); вызов из глаголов kaname — **NTF-2** |
| NTF2-54 | находки гейта на копиях (а)–(в), молчание на дереве и (г), печать объёма и путей | kaname `internal/check` (новый гейт «единый отказ флага») | **NTF-2** (`kaname#484`); функция — NTF-1 (`corelib#77`); на базе литералов 0, функции нет (§6а) |
| NTF2-52 | 0 строк, `UNIMPLEMENTED`, метрика | композиционный корень kaname, `internal/observability/metrics/` | **NTF-2** |
| NTF2-53, 73 | вывод флага и перечня источников, инвариант сетки | зонтик kacho `deploy/helm/umbrella/` и чарт `notify` | **NTF-2** (`kacho#2917`); перечень источников `notify` — NTF-1 |
| NTF2-59 | `503` `request limiter is unavailable`, до kaname не дошло, одноразовость не засчитана, метрика | звено-ограничитель края и его хранилище | **NTF-2** (`kacho#2917`); собственный статус края вносится в ведомость края (DoD п.7) |
| NTF2-60 (а), kaname | `200 {}` на `H` пропущенных краем запросов с одного источника | снятие окна обращений по источнику на `register` и запросе восстановления в kaname (§3) | **NTF-2** (`kaname#484`); на базе окно есть: `git grep -ln 'ChargeSource' origin/367 -- ':!*_test.go'` → 4 файла @`caf1c95ca` (на `357` — те же 4): вызовы `humansession/recovery_request.go`, `registration/register.go`, порт `humansession/verification.go`, реализация `internal/repo/kaname/pg/verification_code_repo.go` |
| NTF2-60…63, 74, 79, 71 (край) | лестница, PoW, `429`, скользящие окна ручек, общий поток, область действия, ключ на доверенной глубине, страж ручек края | `kacho/gateway/internal/middleware/` (новое звено), композиционный корень края | **NTF-2** (`kacho#2917`) |
| NTF2-66 | отказ по частоте (Ф5-08) и жизнь кода; те же оси на `register/confirm`; окно потолка неудач от первой неудачи | страж попыток полосы формы kaname | существует (Ф5-08) для `recovery/complete`; «код не гаснет», оси на `register/confirm` и истечение потолка — **NTF-2** |
| NTF2-67 | ответ вне пути постановки | диспетчер полосы формы kaname (`humansession/dispatch.go`) | существует по устройству; блокировочная проба — **NTF-2** |
| NTF2-68, 69, 70, 77, 78 | письмо о торможении, потолки приглашений, висящие и их срок, `INVITATION_PENDING_LIMIT`, метка устройства и её срок, исход `trusted_device` | kaname | **NTF-2** |
| NTF2-72 | прозрачный PoW в консоли | `kacho/ui-future` экраны восстановления и регистрации | **NTF-2** (`kacho#2917`) |
| NTF2-58 | отказ `503` дословно без решателя, в том числе текст, выбранный пробой; бюджет `Bs` по таймеру страницы, исход `expired`, новый вызов | клиент полосы консоли `ui-future/shared/src/api/login-lane.ts` и решатель | **NTF-2** (`kacho#2917`); на базе решателя нет |
| NTF2-80…86 | `register` → письмо → `register/confirm` с паролем, единый ответ, одна учётная запись, отдельная запись на другой пароль | kaname полоса формы и хранилище ожидающих регистраций; край — путь `register/confirm` в `login_lane_paths.go` | **NTF-2**; на базе пути нет (§1.4) |
| NTF2-88…97 | строки класса S, адресаты, `DENIED(recipient)`, идемпотентность, карта «вид → шаблон → адресат», закрытый перечень вызывающих справочник (`PERMISSION_DENIED` не-`notify`) | kaname: карта видов, писатель аудита, транзакции аудита, справочник адресов и разрешение адресатов (внутренние методы); `notify` — разрешение адреса в момент отправки | **NTF-2** (`kaname#484`); события аудита, кроме `access_key.transferred`, имеют глагол на базе (§1.2, с командой); `transferred` производит проба писателем аудита (NTF2-89) |
| NTF2-94 | метка устройства и письмо | kaname полоса входа | **NTF-2** |
| NTF2-98 | текст находки гейта | kaname `internal/check/people_address_writers.go` | гейт существует (§1.3); условие о письме — **NTF-2** |
| NTF2-19 (в, г) | рубеж края на пути платформы | `gateway/internal/middleware/auth_own_session.go`, `address_refusal.go` | существует (`kacho#2900`, влито в `origin/2564`): `git grep -c EMAIL_NOT_VERIFIED origin/2798 -- gateway/internal/middleware/address_refusal.go` → 1 @`96e2fa72b3a`; сквозная проба — **NTF-2** |
| NTF2-24 | один читатель приёмника | отправитель `notify` (NTF-1 — развёртывание `notify`; имя `notify-sender` — NTF-3 Р8); его полоса на приёмник — чтение узла `global.kacho.identity.smtp` чартом `notify` (**NTF-2**, Р20, NTF2-34); снятие полосы kaname (**NTF-2**), гейт над рендером (**NTF-2**) | замер §6а |
| NTF2-30…32 | перепись держателей; перепись шаблонов стража (31 (ж)) | `deploy/identity_mail_lane_feeds_both_senders{,_injection}_test.go`, переписанный под предикат §0 и дополненный переписью шаблонов с `fail` о `credentialSecret`; отправитель `notify` — чарт `notify` | **NTF-2** (гейт); чарт `notify` — NTF-1; ссылка отправителя на удостоверение из узла `global.kacho.identity.smtp.credentialSecret` — **NTF-2** (Р20, NTF2-34); страж существует @`96e2fa72b3a`, условий отказа NTF-2 в него не вносит (Р19) |
| NTF2-33 | поставка kaname без узла | kaname `deploy/values.yaml`, `deploy/templates/configmap.yaml`, гейт рендера kaname | **NTF-2** (`kaname#484`) |
| NTF2-34 | адрес полосы, адрес отправителя, якорь и ссылка на удостоверение у отправителя `notify` — значения узла `global.kacho.identity.smtp`; второго пути значений полосы нет; пустой узел — пустой ключ адреса ретранслятора (е) | шаблоны чарта `notify` (`deploy/helm/notify/`) в зонтике и в самостоятельной поставке; гейт рендера, сличающий полосу отправителя `notify` с контрольными значениями, записанными в узел | **NTF-2** (`kacho#2917`): чтение узла и гейт; чарт `notify` и его собственные значения — NTF-1 (NTF1-I06); ключ адреса ретранслятора в конфигурации отправителя и отказ старта на его пустоте при включённом флаге — NTF-1 (Д44), вариант (е) их не утверждает; узел и полоса стенда существуют @`96e2fa72b3a` (§6а) |

Сценариев без производителя нет: каждый «Тогда» либо существует на базе (с командой), либо
заводится NTF-1 (условие Р16 п.1), либо — NTF-2 (DoD).

---

## §8 DoD

Каждый пункт имеет исход «пройдено / не пройдено».

**Условие начала** — Р16 пп. 1–3 и 5; вывод команд приложен к задаче `kacho#2917`. Р16 п.5
перемеряется на базе запроса волны перед вливанием; вывод приложен туда же.

**S1 — kaname на ленте**
1. Шаблоны перечня Р3 заведены в `notifications/` дерева kaname; `notifygen -check` зелёный в CI
   kaname; `make -C services/notify bundle` в kacho собирает их на пине kaname. Перечень
   `notifications/required-security.yaml` несёт ровно 24 имени таблицы Р3 (сверка поимённо); гейт
   обязательного класса идёт в CI kaname. NTF2-08, NTF2-99 зелёные с инъекциями.
2. Каждое письмо личности ставится сгенерированной функцией в транзакции события; очередь
   `kaname.invite_mail_outbox` снята новой миграцией; отправитель, его проводка и 10 ручек
   `invite-mail.*` сняты. NTF2-44, NTF2-45, NTF2-48 зелёные; их инъекции красные.
3. Сервер ленты kaname поднят с сертификатом из `kaname.spiffe`; раздел `notifications` манифеста
   kaname — только `readers: [notify]`, кортежей с субъектом `service:kaname` 0; запись перечня
   `notify` для kaname — `authorization: certificate`. NTF2-46, NTF2-47 зелёные; инъекции NTF2-47 (а, б)
   красные.
4. NTF2-01, NTF2-02, NTF2-03, NTF2-40, NTF2-42, NTF2-43 зелёные на П1 через край (newman-коллекция в
   `gateway/tests/newman/cases/`; имена кейсов несут ID; у каждого кейса свой человек; запись
   ведомости производителя для новой коллекции заведена).
5. NTF2-05, NTF2-06, NTF2-07, NTF2-09, NTF2-41 — integration-пробы на П6; имена несут ID.

**S2 — флаг**
6. Ручка `notifications.enabled` kaname без умолчания; в зонтике — `global.kacho.notifications.enabled`
   с переопределением модуля; перечень источников `notify` выводится из того же объявления.
   Отказ выключенного флага в kaname — только вызов `feed.DeliveryNotConfiguredStatus()`: гейт «единый
   отказ флага» идёт в CI kaname и печатает объём обхода, число литералов (0), ссылки на функцию и путь
   до неё у каждого из четырёх действий Р4. NTF2-50, NTF2-51, NTF2-52, NTF2-53, NTF2-54 зелёные;
   инъекции NTF2-54 (а)–(в) красные, (г) — молчит.

**S3 — лимиты и защита**
7. Звено-ограничитель края с PoW заведено; ручки Р8 края объявлены во всех профилях с доверенными
   прыжками; собственные статусы края (`429` с `PROOF_OF_WORK_REQUIRED` и `RATE_LIMITED`) имеют
   производителя в ведомости края; `503` `request limiter is unavailable` — тоже. Окно обращений kaname
   по источнику на `register` и запросе восстановления снято (§3), предикат
   `git grep -ln 'ChargeSource' -- ':!*_test.go'` в kaname после NTF-2 → пусто. NTF2-59, NTF2-60,
   NTF2-61, NTF2-62, NTF2-63, NTF2-79 зелёные.
8. Рубеж kaname на адресата, пол, письмо о торможении, потолки приглашений, метка устройства; ручки
   Р8 kaname объявлены в поставляемых values и в самостоятельной поставке; снятые ручки Р8
   отсутствуют. NTF2-64…NTF2-71, NTF2-74…NTF2-78 зелёные; NTF2-84 — 50 повторов из 50. Четыре таблицы §6б
   («правило → держатель», «ручка → поведение», «длительность → обе стороны», «равенство для любого
   адреса») перемерены: у каждой строки держатель назван и зелёный; ручка Р8 без строки и длительность
   без обеих сторон — возврат в приёмку. Таблица §6в перемерена на базе старта:
   у каждой строки построение исполнено; строка без построения — возврат в приёмку.
9. NTF2-72 зелёная в прогоне консоли; NTF2-58 зелёная в пробе консоли П12 (исход «не выполнилось»
   варианта (б) засчитывается только с печатью момента и повтором до зелёного); NTF2-73 зелёная с
   инъекцией.

**S4 — регистрация**
10. `register` и `register/confirm` по Р9 (код привязан к паролю своего запроса); край ретранслирует
    `register/confirm`. NTF2-80, NTF2-81, NTF2-82, NTF2-85 зелёные на П1; NTF2-83, NTF2-84, NTF2-86,
    NTF2-87 — на П6.

**S5 — класс S**
11. Строки класса S ставятся писателем аудита по карте «вид → шаблон → правило адресата» для
    **каждого** из 23 видов перечня Р3, а не только для строк таблицы NTF2-90: сверка карты с
    таблицей NTF2-90, NTF2-89 и NTF2-94 — часть NTF2-90. Справочник адресов и разрешение адресатов —
    внутренние методы kaname, вызываемые только `service:notify`: NTF2-88 зелёная вместе с близнецом
    (`notify`). NTF2-88…NTF2-93, NTF2-95…NTF2-97 зелёные на П6; NTF2-94 — на П1.
12. Текст находки гейта `people_address_writers` называет письмо прежнему адресу; NTF2-98 зелёная.

**S6 — вне NTF-2 (Д39); граница с `kacho#1276`**
13. Дельта NTF-2 в kacho не трогает ни одного файла §3а с исходом «за `kacho#1276`»: для базы
    старта `<B>` и головы NTF-2 `<H>` — `git diff --name-only <B> <H> -- $(перечень 24 путей §3а с этим
    исходом)` → пусто. Ключа `kratos.courier.enabled` и шаблона стража листа под `courier` NTF-2 не
    вносит: `git grep -l 'courier.enabled' <H> -- deploy/helm | wc -l` равно тому же числу на `<B>`
    (@`96e2fa72b3a` — 0). Полосу стенда чарт `notify` получает чтением узла `global.kacho.identity.smtp`
    (Р20) из `values.dev.yaml`; исключения для этого файла нет — узел NTF-2 не правит и не восстанавливает.
    Наличие узла — условие Р16 п.5 (на `<B>` и на базе запроса волны); не выполнено — возврат в
    приёмку, а не правка файла.
14. Страж секрета почты — один: шаблонов под `deploy/helm/`, чей вызов `fail` называет ключ
    удостоверения почты, — ровно один, `identity-mail-lane-guard.yaml`:
    `git grep -lE '\bfail\b.*credentialSecret' <H> -- 'deploy/helm/**/templates/*' | wc -l` → 1 (на базе
    @`96e2fa72b3a` — 1, §1.10); держит NTF2-31 (ж) красный, (ж') зелёный. Условий отказа NTF-2 в страж не
    вносит; тексты, называющие читателем процесс службы доступа, называют отправителя `notify` (Р19).
    Условие «секрет почты только у отправителя `notify`» — п.19. Полоса стража садится после вливания
    `kacho#1276` (Р16 п.4); вывод команды условия приложен к задаче `kacho#2917`.
15. NTF2-19 зелёная на П1 (newman, имя кейса несёт ID); NTF2-24 зелёная в CI kacho, печатает `|R|`,
    `|L|` и счёт по цепочкам.

**Перепись**
16. Перепись §3а исполнена: перемерена командой §1.9 на базе старта; посев «после NTF-2» прогнан
    всеми четырьмя бегунами дерева; каждый красный файл стоит с исходом «правится» или «переписан»;
    файл без строки или красный с исходом «остаётся» либо «за `kacho#1276`» — возврат в приёмку. Файлы
    «правится» не несут предмета почты kaname:
    `git grep -lE 'invite-mail|inviteMail|KANAME_INVITE_MAIL|kaname-mail-anchor|kaname-mail-credential' <H> -- deploy/helm` → пусто.
    Отсутствие файла §3а на базе старта судится фактом снятия, а не исходом строки: файл **любого**
    исхода, которого нет на `<B>`, снятый коммитом, **внесённым** вливанием `kacho#1276`, — исход
    `kacho#1276`, а не NTF-2: в перемеренной таблице он стоит со ссылкой на эту посадку и возвратом в
    приёмку не является. Проверка — три команды:
    (1) коммит снятия `D`: `git log --diff-filter=D --format=%H 96e2fa72b3a..<B> -- deploy/<путь>`;
    (2) голова ветки волны-4 внутри `<B>`: `W` — второй родитель вливания волны в ветку эпика,
    `git log --first-parent --merges --format='%P' --grep='^#2564 merge #2798' 96e2fa72b3a..<B> | awk '{print $2}'`;
    пусто — волна ещё не влита, и `W` = `<B>`;
    (3) вливания `kacho#1276` `M` — коммиты слияния с темой `#1276 merge #<полоса>` на первородительской
    линии приёмника: `git log --first-parent --merges --format=%H --grep='^#1276 merge ' 96e2fa72b3a..L`
    для `L` = `W` и `L` = `<B>` (задача может влиться и прямо в ветку эпика). Слияния, которыми ветка
    полосы догоняет волну, на первородительской линии приёмника не лежат и в множество не входят.
    `D` внесён вливанием `kacho#1276`, если для какого-то `M` `git rev-list M^1..M | grep -cx D` → 1.
    Достижимость `D` из `M` критерием **не** является: любой более ранний коммит тоже достижим.
    Контроль в обе стороны: `5f689f36438` достижим из `96e2fa72b3a`
    (`git merge-base --is-ancestor` → 0), но `git rev-list 96e2fa72b3a^1..96e2fa72b3a | grep -c 5f689f36438`
    → 0 — не внесён этим вливанием; коммит снятия `92097320166` лежит в диапазоне вливания
    `#1276 merge #2818` (`8f879ff7fbd`, коммит клона, на origin не отправлен) — счёт 1. Множество `M` пусто
    или `D` ни в одном диапазоне — файл судится как снятый другой посадкой. Так же
    судятся строки 31, 32, 33, 35, 37, 42 с исходом «остаётся» (§3а). Файл, снятый другой посадкой,
    либо присутствующий и красный на посеве с исходом «остаётся» или «за `kacho#1276`», — возврат в
    приёмку.
17. Перепись §3б исполнена: предикат §1.1 перемерен на базе старта; у каждого файла исход его
    группы исполнен; после NTF-2 предикат
    `git grep -lE 'invite-mail|inviteMail|KANAME_INVITE_MAIL|invite_mail|net/smtp|MailKind|OurMailKinds' -- ':!*.md' ':!*_test.go' ':!docs/specs/reviews/**' ':!internal/migrations/0001_initial.sql' ':!internal/migrations/2026091*' ':!internal/migrations/20260927190000_*'`
    в kaname даёт ровно: новую миграцию снятия очереди, `internal/migrations/retired.json` и файл
    гейта NTF2-44 (он называет запрещённый импорт).
18. Таблица §6а перемерена на базе старта; исход «разошлось» у любого «Тогда» — возврат в приёмку.

**S7 — единственный держатель**
19. Держатель NTF2-30…NTF2-32 идёт в CI kacho и зелёный на ветке эпика релиза; инъекции NTF2-31
    (а), (б), (в), (д), (ж) красные, (ж') зелёная. NTF2-33 зелёная в CI kaname. NTF2-34 зелёная в CI
    kacho по вариантам (а), (б), (в), (д), (е), (е') и (г'); инъекция (г) красная.
20. Предикат завершения §0 выполнен; вывод гейта — число цепочек, объектов и ссылок — приложен к
    задаче `kacho#2917`.

**Трекер, документы, записки**
21. `kacho#2700`, `kaname#246` закрыты ссылками на NTF2-60, NTF2-64, NTF2-65 (Р17); `kaname#475` —
    ссылками на NTF2-50…52 (Р18); предикат `kaname#484` указывает на этот файл.
22. Страницы поставки и настроек kaname (`docs/content/`) и сайт документации kacho называют флаг
    почты, ручки Р8 и то, что почту шлёт только `notify`; мест, называющих почтовый узел kaname, 0.
23. В шапки `sub-phase-ID-MAIL-1-mail-delivery-acceptance.md` и приёмок kaname
    `access-beyond-login-needs-a-verified-address.md`, `recovery-of-access.md`,
    `registration-and-its-three-consequences.md` дописана строка-ссылка на §3 этого документа с
    перечнем замещённых решений и ID; строка в шапке `access-beyond-login-needs-a-verified-address.md`
    называет и окно обращений по источнику `kaname#456` (§3). Прежний текст не правится.
24. Записки: `resources/`, `rpc/`, `edges/` о почтовой полосе kaname и поставщика помечены снятыми;
    ребро notify→kaname (справочник адресов, разрешение адресатов) записано; trail задач
    `kacho#2917` и `kaname#484` назван.
25. Предупреждений без предиката снятия и маркеров отложенной работы в дельте — 0 (ban #11).

**Покрытие ID.** Каждый ID §6 назван в пп. 1–20: NTF2-01, 02, 03, 40, 42, 43 — п.4; NTF2-05, 06, 07,
09, 41 — п.5; NTF2-08, 99 — п.1; NTF2-44, 45, 48 — п.2; NTF2-46, 47 — п.3; NTF2-50…53 — п.6;
NTF2-59…63, 79 — п.7; NTF2-64…71, 74…78, 84 — п.8; NTF2-58, 72, 73 — п.9; NTF2-80…87 — п.10; NTF2-88…97 — п.11;
NTF2-98 — п.12; NTF2-19, NTF2-24 — п.15; NTF2-31 (ж) — п.14; NTF2-30…34 — п.19. Снятые ID
(NTF2-18, NTF2-20…NTF2-23) в DoD не называются.

---

## §9 Признаки маршрута

| признак | да/нет | основание |
|---|---|---|
| proto | да | внутренние методы kaname (справочник адресов, разрешение адресатов); сообщения регистрации полосы формы — HTTP, без proto |
| схема БД | да | kaname: снятие очереди писем, лента, ожидающие регистрации, метки устройств, окна адресата |
| публичный RPC или край | да | `register/confirm`, ограничитель и PoW края, `503` недоступного хранилища ограничителя, новые отказы `NOTIFICATION_DELIVERY_NOT_CONFIGURED` (статус NTF-1), `INVITATION_RATE_LIMITED`, `INVITATION_PENDING_LIMIT`; поле `password` в `register/confirm` |
| UI | да | консоль: прозрачный PoW, отказ `503` и исход `expired` решателя, экран регистрации с кодом |
| новый домен или сервис | нет | `notify` заводит NTF-1 |
| новое межсервисное ребро | да | notify→kaname (справочник адресов, разрешение адресатов) — внутренний слушатель |
| поверхность безопасности | да | анонимные почтовые глаголы, регистрация, класс S, секрет почты у одного объекта (отправитель `notify`) и страж рендера; снятие почты поставщика — `kacho#1276` (Д39) |
| поток изменений ресурса | да | вид события «нотификация» подписки kaname (`notification_feed:kaname`) |

---

## §10 Публичность

- Документ называет требования, ручки, границы и отказы; текущих слабых мест и пошаговых описаний
  атаки в нём нет. Замещения названы идентификаторами прежних решений, без разбора причин.
- Значений удостоверений, адресов узлов и адресов стендов нет; цепочки названы именами из
  `deploy/stacks.txt`.
- Рабочие каталоги задач не упоминаются; пути — от корня репозитория.

---

## §11 Правки по кругам

### Круги 1–4 → редакции 2–5 (предмет «снятие почты поставщика»)

Записи кругов — в каталоге ревью шапки. Решения, пережившие смену предмета и перенесённые в
редакцию 6:

| что | откуда | где теперь |
|---|---|---|
| посадка `own` во всех цепочках как условие начала | B1-1, B1-2 | Р16 п.2, NTF2-18 |
| заменяющий контроль подтверждённости на нашей полосе | B1-3 | NTF2-19 |
| перепись файлов из трёх источников | B2-1, B3-1, B3-2 | §3а, §3б |
| состояние, общее для кейсов, — только на уровне I | B2-2 | §5 |
| множества цепочек выводятся из рендера; приёмник без читателя законен | B2-3 | §5, Р15, NTF2-24 |
| умолчание подчарта `courier: {smtp: {}}` остаётся; сверка «Тогда» на посеве | B4-1 | Р19, §6а, NTF2-21 |
| DoD называет всё, что подпирало снятое | I3-1, I4-1 | DoD п.13 |

### Редакция 5 → редакция 6 (смена предмета)

Редакцию 5 не рассматривал ни один круг. Последний блокирующий круга 4 — B4-1 (CONSTRUCTIBILITY:
«раздела `courier` в рендере 0» недостижимо из-за умолчания подчарта) — закрыт решением Д12:
предикат снятия — «нет ссылки на секрет, нет адреса узла, процесс не запущен, потоки выключены,
секрет в одном объекте» (Р19), и ни один сценарий не утверждает отсутствия раздела.

| что изменено | где |
|---|---|
| предмет расширен до почты личности: перевод kaname на ленту и снятие её почты (прежде — NTF-1) | S1, Р1–Р3, §3б |
| флаг почты | S2, Р4, Р18 |
| лимиты и защита от спама | S3, Р5–Р8, Р12 |
| регистрация «сначала письмо» | S4, Р9 |
| класс S из аудита kaname, адресаты | S5, Р10, Р11, Р13 |
| прежний NTF2-04 (второе письмо с новым кодом) снят: противоречит Д11 | заменён NTF2-40, NTF2-41 |
| NTF2-05, NTF2-07 переписаны под ручки Р8 и запрос восстановления | S1 |
| предикат завершения дополнен адресом узла и поставкой kaname | §0, NTF2-30, NTF2-33 |
| перепись kacho дополнена тремя файлами почты kaname (49 вместо 46); строки 6, 38, 39 — «правится» здесь, а не в NTF-1 | §3а |
| база замера — `origin/2564` @`6edea09c2ee`: ветка `2797` влита в неё, дерево `deploy` не менялось | §1.6, §1.7 |
| ссылки на внутренние ID приёмки NTF-1 сняты: соседняя под-фаза называется решениями Д и задачами | §4, §7 |

**Снятые ID:** NTF2-04 (и прежде снятые NTF2-10…NTF2-17); не переиспользуются.
**Новые ID:** NTF2-33, NTF2-40…48, NTF2-50…53, NTF2-60…73, NTF2-80…85, NTF2-90…99.

### Редакция 6 → редакция 7 (круг 1 после смены предмета)

Род COVERAGE повторился дважды в одном круге (B-2, B-3), поэтому закрыт **класс**: заведена перепись
«правило → держатель» по решениям Р3–Р12 (§6б), и каждое найденное ею правило без держателя получило
сценарий — не только названные рецензентом.

| замечание | что изменено | где |
|---|---|---|
| B-1 (CONSTRUCTIBILITY): повтор `register` в срок кода не определён; Given NTF2-84 не строится | выбран один исход: код привязан к паролю своего запроса; тот же пароль — тот же код той же записи, другой пароль — вторая запись со своим кодом, прежняя жива; замена записи отвергнута с основанием; `register/confirm` принимает `password` и ищет запись, где совпали код и пароль; запись заводится только с письмом, пропущенным окном | Р9, Р6, NTF2-80, NTF2-82, NTF2-83, NTF2-84 (Given построен исходом NTF2-86 (б)), **NTF2-86** (тот же пароль — близнец; другой пароль; чужой код с чужим паролем — `401`; пауза — записи нет) |
| B-2 (COVERAGE): пять видов перечня Р3 без держателя | в NTF2-90 добавлены строки `session.force_logout`, `user.second_factor_removed`, `user.second_factor_reset`, `access_key.revoked`; порядок исполнения строк, меняющих годность адресатов, задан; `access_key.transferred` — отдельный **NTF2-89**: глагола переноса в дереве нет (замер §1.2), событие пишет проба писателем аудита, адресатов два; карта «вид → шаблон → адресат» названа в Р3 и сверяется с таблицей в NTF2-90; DoD п.11 судит все 23 вида карты | §1.2, Р3, NTF2-89, NTF2-90, DoD п.11 |
| B-3 (а) (COVERAGE): общий поток края без держателя | **NTF2-74** (близнец — та же нагрузка ниже общего потока); ручки общего потока названы (`RATE_PER_SECOND`, `BURST`) с границами; варианты NTF2-71 (ж, з, и) | Р5, Р8, NTF2-71, NTF2-74 |
| B-3 (б) (COVERAGE): окно `registration` без держателя; противоречие ключа в Р6 | ключ окна задан таблицей по назначению: для `recovery` строки для адреса без учётки нет, для `registration` строка заводится для любого адреса и одна на `registration` и `registration-existing`; **NTF2-75** (близнец — занятый адрес); вариант NTF2-71 (л) | Р6, NTF2-71, NTF2-75 |
| класс COVERAGE, найдено переписью §6б сверх замечаний | окно `verification` (потолки и пол) — **NTF2-76**; срок кода восстановления — NTF2-65 и NTF2-71 (м); срок метки устройства — **NTF2-78** и NTF2-71 (п); снятые ручки Р8 — NTF2-48 (б–г) | NTF2-48, NTF2-65, NTF2-71, NTF2-76, NTF2-78 |
| I-1: толкование Д7 не помечено | строка «Толкование Д7 (решение автора)» с основанием | Р4 |
| I-2: исхода «по оси устройства» нет в наборе метрики | исход `trusted_device` внесён в закрытый набор и назван в NTF2-70, NTF2-78 | Р6, NTF2-70, NTF2-78 |
| I-3: нет координаты перечня Р3 для проверки обязательного класса | перечень — файл `notifications/required-security.yaml` дерева kaname, не производный от шаблонов; судит его гейт kaname; инъекции «пустой перечень» и «имя без шаблона» | Р3, NTF2-99, DoD п.1, §7 |
| I-4: `recipient-per-hour`, `recipient-per-day`, `pending-max` без держателя | отказ по `pending-max` назван (`INVITATION_PENDING_LIMIT`); срок приглашения освобождает место; **NTF2-77**; варианты NTF2-71 (н, о) | Р7, Р8, NTF2-71, NTF2-77 |

**Новые ID:** NTF2-74…78, NTF2-86, NTF2-89. Снятых нет.

### Редакция 7 → редакция 8 (круг 2 после смены предмета)

Род CONSTRUCTIBILITY повторился трижды в одном круге (B2-1…B2-3) при смежном FORMAT (B2-4), поэтому
закрыт **класс**: заведена перепись «Given и счёт → построение» по четырём признакам (§6в), и каждое
найденное ею место получило построение — не только названные рецензентом.

| замечание | что изменено | где |
|---|---|---|
| B2-1 (CONSTRUCTIBILITY): Given NTF2-81 и близнеца NTF2-75 оставляет письмо в окне `registration` | посев П10 «подтверждённый человек без глаголов почты» (шаг стенда `verified-human`); NTF2-81, близнец NTF2-75 и занятый адрес NTF2-85 строятся им; окно адресата — состояние того, кто его построил (§5) | §5, NTF2-75, NTF2-81, NTF2-85, §3б |
| B2-2 (CONSTRUCTIBILITY): счёт NTF2-90 захватывает побочные письма | счёт по строке таблицы и её событию: строк её шаблона по её событию — столько, сколько адресатов; вспомогательные события пробы названы и из счёта исключены; счёт на уровне I — по паре (событие, адресат), на уровне E — по шаблону и от ответа When | §6 (вводная), NTF2-90, NTF2-92, NTF2-96 |
| B2-3 (CONSTRUCTIBILITY): близнец NTF2-72 не строится на общем счётчике края | П1 объявляет `V < FREE` и печатает оба; близнец — первое действие кейса; ступень создаёт шаг 2 запросами до первого вызова; нарушение объявления — «не выполнилось»; кейс адресует несуществующий `Z` | §5, NTF2-72 |
| B2-4 (FORMAT): «`capped` либо `floor`» в NTF2-70 (б), NTF2-78 (в) | `Tc` определён как момент последнего пропущенного письма; моменты сценариев строго внутри `(Tc, Tc + Fl)`; старшинство исходов `capped` над `cooldown` объявлено и держится NTF2-65 (в); запас устройства — по паре (адрес, метка) без пауз | Р6, NTF2-65, NTF2-70, NTF2-78 |
| B2-5 (NEGATIVE): закрытый перечень вызывающих справочник без пробы | **NTF2-88**: служба с проверенным сертификатом, не `notify`, — `PERMISSION_DENIED` без адреса; близнец — `notify` | Р11, NTF2-88, §6б, §7, DoD п.11 |
| B2-6 (COVERAGE): ключ источника на доверенной глубине без держателя | правило сформулировано требованием; **NTF2-79**: один адрес на доверенной глубине при разной цепочке дальше — один источник; близнец — разные адреса на доверенной глубине | Р5, NTF2-79, §6б, §7, DoD п.7 |
| I2-1: `register/confirm` в ограничителе края, `recovery/complete` — нет | ограничитель края — только пути, ставящие письмо (`recovery`, `register`), по Д11; перебор кода на обоих путях предъявления держат оси kaname; NTF2-63 утверждает, что оба пути предъявления проходят край с исчерпанного источника; NTF2-66 (б) — оси на `register/confirm` | Р5, Р6, Р9, NTF2-63, NTF2-66 |
| I2-2: срок потолка неудач адреса не назван | окно длиной `window` от первой неудачи; по истечении устройство без метки предъявляет код; NTF2-66 (г) с близнецом `Tf + W − 1 с` | Р6, Р8, NTF2-66 |
| I2-3: повтор `register` после истечения кода не определён | запись с истёкшим кодом не жива: повтор — новая запись, исход `queued` | Р9, NTF2-83 |
| I2-4: порядок пароля и флага не назван | правила пароля первыми и при выключенном флаге; NTF2-51 (е) | Р9, NTF2-51 |
| I2-5: записи прежних кругов изменены в рабочей копии | этим документом не правится: записи ревью вне его предмета; правка внесена санитарным коммитом записей (не автором приёмки) | — |
| класс CONSTRUCTIBILITY, найдено переписью §6в сверх замечаний | люди и объекты уровня I — фикстурой П11; источник по умолчанию на П6; письмо нового устройства — только путь входа, сессии `register/confirm` и `recovery/complete` его не дают (иначе построение П2 давало бы побочное письмо в NTF2-94); срок метки не продлевается входом (NTF2-78 (а) иначе делал бы (б) недостижимым); потолок неудач в NTF2-66 (в, г) — отдельными повторами | §5, Р12, NTF2-43, NTF2-66, NTF2-78, NTF2-80, NTF2-94 |
| решение Д14 | надзор администратора облака на тип `notification_feed` не распространяется; держатель — NTF-1 | Р1, §6б |

**Новые ID:** NTF2-79, NTF2-88. Снятых нет.

### Редакция 8 → редакция 9 (круг 1 прохода Д14–Д16)

Род CONSTRUCTIBILITY вернулся четвёртым кругом подряд, COVERAGE — третьим; оба раза перепись по
чтению пропускала места. Поэтому редакция 9 закрывает классы переписями **по предмету**, полученными
выборкой из текста, а не по решениям: каждая ручка Р8 получила наблюдаемое поведение и держателя,
красного при чтении ручки только стражем; каждое действие с ответом, независимым от адреса, — сравнение
на каждом исходе; каждый символ момента в §6 — ряд, который его строит.

| замечание | что изменено | где |
|---|---|---|
| B-1 (COVERAGE): равенство отказа при выключенном флаге для регистрации на занятый адрес без держателя | NTF2-51 (ж): `register` на занятый адрес `A` (посев П10) побайтово равен (в); (з): приглашение `A` равно (г); писем 0; близнец — те же пары на П6 с флагом `true`; Р4 называет пары | Р4, NTF2-51, §6б |
| B-2 (COVERAGE): ступень `POW` без поведения | счёт ключа — пропущенные запросы; лестница источника — три ступени: базовая сложность `POW_BITS_BASE` с `FREE`, повышенная `POW_BITS_HIGH` с `POW`, `429` с `HARD`; ручки сложности с границей `BASE < HIGH`; NTF2-60 печатает `difficultyBits` по номеру запроса, близнец (б) — `POW` = `HARD` без повышенной ступени; вызовы подсети и общего потока — базовая сложность; варианты NTF2-71 (р, с) | Р5, Р8, NTF2-60, NTF2-61, NTF2-71, NTF2-74 |
| B-3 (CONSTRUCTIBILITY): NTF2-68 не построен; два прочтения Р6 | Р6 выбирает один исход: письмо `mail-throttled` ставит исход `capped` окна `recovery` адреса с учётной записью, раз в интервал, **сверх** окна (окна не расходует, окном не отсекается); оно — слагаемое инварианта сетки (Р8, NTF2-73, второй близнец). NTF2-68 построен от ряда NTF2-64: `Ts` — первый `capped` (свой символ); повторы `capped` строго внутри `(Tc, Tc + Fl)`; после `Ts + Ti` — новый ряд часами пробы | Р6, Р8, NTF2-68, NTF2-73, §6в |
| I-1: люди NTF2-52 не названы | фикстура П11: `acc`, владелец `O`, пользователь `U`; роль выдаётся `U`, не группе; близнец — адресат каждой строки `U` | NTF2-52 |
| I-2: владельцы удалённого аккаунта в момент отправки | адресаты разрешаются снимком в транзакции события, строка на адресата; в отправке — только адрес | Р11, §6б |
| I-3: источник `V` | `V` — счёт по перечню кейсов прогона; пороги — из рендера | §5, NTF2-72 |
| класс COVERAGE, найдено переписью «ручка → поведение» сверх замечаний | пол окна `registration` без держателя — NTF2-75 (моменты пола, исход `floor` для свободного и занятого адреса); исход письма пола — `floor`, какой бы код оно ни несло (Р6, Р9); порог возраста аккаунта задан ручкой `Ya`, а не числом (П6-age, NTF2-69, NTF2-77) | Р6, Р9, §5, NTF2-69, NTF2-75, NTF2-77 |
| класс CONSTRUCTIBILITY, найдено переписью §6в сверх замечаний | ответы-вызовы NTF2-60 не равны побайтово (`challenge`, `expiresAt`) — определение «побайтово равны» в §6; первый `capped` рядов `recovery` ставит строку `mail-throttled` — счёт строк рядов по шаблону `recovery` (NTF2-64, 65, 70); «за сутки не больше `per-day`» при письме пола — NTF2-75, NTF2-76; `Tc` окна `verification` определён в NTF2-76; символ `Tt` двух сроков разведён (`Tv` в NTF2-77) | §6, NTF2-60, 64, 65, 70, 75, 76, 77 |

**Новые ID:** нет. Снятых нет.

### Редакция 9 → редакция 10 (круг 2 прохода Д14–Д16)

Род COVERAGE вернулся четвёртым кругом подряд при убывающем числе блокирующих (6 → 3 → 1). Место
пропуска — третий вид: у длительности утверждалась одна сторона границы. Класс закрыт правилом,
предложенным рецензентом для формы задания: у ручки-длительности держатель утверждает `− 1 с` и сам
момент срока; правило проведено по всем длительностям Р8 и окнам, заданным именем ручки, — перепись
«длительность → обе стороны», 25 строк (§6б).

| замечание | что изменено | где |
|---|---|---|
| B-1 (COVERAGE): у `mail-throttled-interval` и сроков кода нижняя сторона без держателя | Р6: длительности — полуоткрытые интервалы, срок кода — от чеканки, повтор не продлевает; NTF2-68 (б) — `capped` в `Ts + Ti − 1 с` без строки, в `Ts + Ti` со строкой; **NTF2-87** — сроки кода трёх назначений в `Tk + ttl − 1 с` (тот же код, принят) и в `Tk + ttl` (новый, `K` — `401`) | Р6, NTF2-68, NTF2-87, §6б |
| B-1, «пройти правилом все длительности» | окна ручек края источника и подсети — скользящие (Р5), NTF2-60 (в), NTF2-61 (г); часовое и суточное окна kaname — скользящие и считают только письма прогрессии (Р6), часовая граница в NTF2-64, 75, 76, суточная — NTF2-65 (г), 75, 76; окно оси «адрес + источник» — NTF2-66 (д); порог возраста — `Ya − 1 с` / `Ya` (П6-age); суточные окна потолков аккаунта и адресата — NTF2-69 (г, д), NTF2-77 (д, е); запас доверенного устройства — NTF2-70 (в); срок приглашения — в момент `Tv`; в NTF2-64, 75 «строки только в разрешённых моментах» заменено на «в каждом разрешённом — ровно одна, в прочих — ни одной» | Р5, Р6, Р8, §5, NTF2-60, 61, 64, 65, 66, 69, 70, 75, 76, 77 |
| I-1: «ровно одна» строка в NTF2-68 (а) при ряде длиннее `Ti` | условие `Tc + Fl − 1 с < Ts + Ti` в Given, оба момента печатаются | NTF2-68, §6в |
| I-2: `T_alarm` вне переписи символов | перепись символов §6в перемерена выборкой, 16 сценариев с символом и 2 со сроком без символа | §6в |
| I-3: `K1` в NTF2-65 не определён | `K1` — код строки в `Tc`, `Tk1` — её чеканка; ветвь «новый код / тот же» по `Tk1 + Tr ≤ Tc + Fl` | NTF2-65 |
| I-4: «границы и отсутствие каждой ручки судит NTF2-71» | отсутствие каждой ручки — перебор NTF2-71 (т) по таблице Р8; границы — выборкой, добавлены (у) `attempts.window`, (ф) `mail-throttled-interval`, так что у каждой строки Р8 не меньше одного варианта | NTF2-71, §6б |
| I-5: П6-age описывает один аккаунт | П6-age — два аккаунта с разницей 1 с: в `T + Ya` `mature` ровно `Ya`, `young` `Ya − 1 с` | §5, NTF2-69, NTF2-77 |
| класс CONSTRUCTIBILITY, найдено при правке NTF2-69 | повторы (а)–(в) делили окно аккаунта `young`; `pending-max` = `account-per-day` делал отказ (б) неоднозначным; двух аккаунтов мало для потолка поперёк аккаунтов при `recipient-per-day-all` = 2 × `recipient-per-day` — отдельные повторы, условие `pending-max > account-per-day`, `k` аккаунтов П11 | NTF2-69, §6в |

**Новые ID:** NTF2-87 (номер был свободен). Снятых нет.

### Редакция 10 → редакция 11 (круг 3 прохода Д14–Д16)

Блокирующее внесла правка класса прошлого круга: окна стали скользящими, а правило пола осталось
написанным для неподвижных суток. Класс закрыт шагом, который рецензент предложил в форму задания:
при смене семантики окна переписано каждое правило Р5–Р8, которое на неё опирается, и ожидания всех
сценариев с `Tc` сверены по ориентирам Р8 и по обеим границам. Перепись сценариев с `Tc` — выборкой
символа по тексту §6: NTF2-65, 68, 70, 75, 76, 78; других нет.

| замечание | что изменено | где |
|---|---|---|
| B-1 (CONSTRUCTIBILITY): Р6 держал «между `Tc` и `Tc + floor-interval` — `capped`» при скользящем суточном окне; NTF2-65 (г), 75, 76 красны по Р6 | одно правило пола: окно исчерпано, пока в `(t − 1 сут, t]` `per-day` писем прогрессии; `Tc` — письмо текущего исчерпания, `Tw` — самое раннее письмо окна плюс 1 сут; пол действует в `[Tc, Tw)`, письмо пола только раньше `Tw`; с `Tw` прогрессия возобновляется, новое исчерпание — новый `Tc`; письма пола разнесены на `floor-interval` и поперёк исчерпаний; базовый профиль расписан по ориентирам | Р6 |
| B-1: `Tc` при повторном исчерпании не определён; прогрессия после возобновления не определена | номер письма прогрессии — по часовому окну, паузы — от прошлого письма прогрессии (письма пола, запаса, о торможении паузы не открывают); повторное исчерпание задаёт `Tc'`, `Tw'`; NTF2-70 (в) пересчитан: в базовом профиле суточное окно в обоих моментах — 3 < `per-day`, исход `capped` по часовому потолку | Р6, NTF2-70, §6в |
| B-1: условие NTF2-65 (а, б) ломается при `Fl` = 24 ч | условие `Tc + Fl < Tw` (`t0 + 1 сут > Tc + Fl`) печатается, иначе «не выполнилось»; то же в NTF2-75, 76; в NTF2-68 — `Tc + Fl ≤ Tw`; в NTF2-70, 78 — момент в `[Tc, Tw)` раньше `Tc + Fl`, `Tw − Tc` печатается | NTF2-65, 68, 70, 75, 76, 78, §6б, §6в |
| B-1: ожидания NTF2-65 (г), 75, 76 | выведены из правила: в `Tw − 1 с` — `capped` / `429` (пола в исчерпании нет, `Tc + 24 ч ≥ Tw`), в `Tw` — `queued` или `resent_same`; условие пустого часового окна `Tc ≤ t0 + 23 ч` | NTF2-65, 75, 76, §6б |
| I-1: ключи окон края спрятаны за `_*` | ключи названы: `…IP_{FREE,POW,HARD}_{LIMIT,WINDOW}`, `…SUBNET_{V4_24,V6_56,V6_48}_{POW,HARD}_LIMIT`, `…SUBNET_{POW,HARD}_WINDOW`; границы окон — `1 мин ≤ W_F ≤ W_P ≤ W_H ≤ 24 ч`, `1 мин ≤ W_Ps ≤ W_Hs ≤ 24 ч`; перечень ключей Р8 — раскрытие скобок, 51; NTF2-71 (т) — 51 вариант; границы окон — (х), (ц) | Р8, NTF2-71, §6б |
| I-2: NTF2-69 (в) — субъект и объект переставлены | «аккаунт с неисчерпанными потолками приглашает `C`» | NTF2-69 |
| I-3: `ttl ≥ first-pause` только для `recovery` | добавлены NTF2-71 (ч) `verification`, (ш) `registration` | NTF2-71, §6б |

**Новые ID:** нет. Снятых нет.

### Редакция 11 → редакция 12 (возврат разбора классов изменения `issue-2917`)

Редакция 11 одобрена (`9098d6ef…`). Разбор классов до кода и его пересверки на замысел вернули в неё
пять предметов: `docs/changes/issue-2917/reviews/class-exposure/revalidation/cc7bdad1c55489347978ba2414d471b2a9637088c946bedf9527798074349fda.yaml`,
раздел `return_to_acceptance`, и прежние пересверки того же каталога. Правка меняет отпечаток, поэтому
одобрение редакции 11 на редакцию 12 не переносится (История review).

| возврат | что изменено | где |
|---|---|---|
| К1, Е1: NTF-2 утверждала субъект `service:kaname` и строку `sender` для kaname, одобренная NTF-1 — обратное (Р3, NTF1-F21, NTF1-G22) | NTF-2 приведена к NTF-1 по запасному пути Д2: решение MRW-1 Р1 запрещает службе доступа свою служебную запись, и тип модели этого запрета не обходит; пространство `kaname` авторизует сертификат сервера ленты (`authorization: certificate`, SAN из `kaname.spiffe`), `ResolveSend` по нему не зовётся, отзыва нет — рычаг оператора флаг; манифест kaname — только `readers: [notify]`. NTF2-06 переписан: вместо надгробия выдачи — чужое удостоверение сервера ленты (П4 переопределён), близнец утверждает `ResolveSend` 0; NTF2-47 переписан: (а) `namespace` — находка MRW-1 Р1, (б) чужой читатель — отказ, близнец — ровно один кортеж `reader` и ноль кортежей субъекта kaname; NTF2-53 утверждает запись `certificate` | §1.5, Р1, Р14, §4, §5 (П4), NTF2-06, NTF2-47, NTF2-53, §6б, §7, DoD п.3 |
| К2, Е2: отказ флага в NTF-2 — `mail delivery is not configured…`, `MAIL_DELIVERY_DISABLED`; в NTF-1 — единый отказ corelib | текст и `reason` — `email delivery is not configured in this installation`, `NOTIFICATION_DELIVERY_NOT_CONFIGURED`; производитель — `feed.DeliveryNotConfiguredStatus()` (NTF-1 Р9, NTF1-N06); своего отказа у kaname нет | Р4, Р9, NTF2-51, §6б, §7, §9 |
| Е3: у `invite.recipient-per-day-all` нет верхней границы при статичном лимите шаблона `invite` | граница `≤ 50` — лимит шаблона `invite` на адресата в сутки; значение выше — отказ старта (принятое и проигнорированное запрещено); вариант NTF2-71 (щ) с близнецом «50 — старт» | Р8, NTF2-71, §6б |
| Е4: окно обращений kaname по источнику (`kaname#456`) снимается, а замещение не названо приёмкой | строка §3; правило «ось источника только у края» в Р5; держатель — NTF2-60 (а): `H` пропущенных краем запросов доходят до kaname, `H > source-attempts` печатается; строка-ссылка в шапке приёмки `kaname#456` — DoD п.23 | §3, Р5, NTF2-60, §6б, §7, DoD пп.7, 23 |
| Е9: исход «хранилище ограничителя недоступно» и поведение консоли на `503` и `expired` не были наблюдаемым контрактом | Р5 называет `503`, `code` `14`, `request limiter is unavailable`, одинаковость для адреса и пути, fail-closed для доказательства; **NTF2-59** (близнец — исправное хранилище); консоль показывает отказ дословно, бюджет решателя `Bs` меньше срока вызова, исход `expired` — **NTF2-58** уровня U на посеве П12 (перехват ответа края на странице), обе стороны `Bs` | Р5, §5 (П12), §6 (уровень U), NTF2-58, NTF2-59, NTF2-72, §6б, §6в, §7, §9, DoD пп.7, 9 |

Строка §4 NTF-1 о приёмнике `address.Domain` и его отказе на нулевом значении (Е10 замысла) этой
приёмкой не правится: по решению диспетчера Д19 это утверждает NTF-1 как владелец пакета `address`.

**Новые ID:** NTF2-58, NTF2-59 (номера были свободны). Снятых нет.

### Редакция 12 → редакция 13 (круг 1 редакции 12)

Запись круга —
`docs/specs/reviews/sub-phase-NTF-2-identity-provider-mail-removal-acceptance/f38dee0f359578c0eb23ea2f715072e7dd1dcce9c61c0b9dfd19d8c42fd00780.yaml`.
Блокирующее одно (COVERAGE): правило «отказ флага производит только corelib» держал сценарий, который
утверждал значение ответа и поэтому зеленел на копии. Класс закрыт по документу: пятая перепись §6б
«единственный производитель → держатель» нашла 9 утверждений этого вида; у 8 держатель уже красен на
второй копии, девятое — консоль без своего текста отказа (NTF2-58) — имело тот же пропуск, что B-1, и
получило вариант (г).

| возврат | что изменено | где |
|---|---|---|
| B-1 (COVERAGE): у Р4 «своего текста и `reason` у kaname нет» нет держателя, способного упасть; клауза «побайтово тот же отказ, что у NTF1-N06» неисполнима | **NTF2-54** — гейт дерева kaname: литералов текста и `reason` вне тестов 0; ссылка на `feed.DeliveryNotConfiguredStatus` по идентичности достижима из каждого из четырёх действий Р4; объём и пути печатаются; копия литерала (а, б) и действие без пути до функции (в) — красные, литерал в пробе (г) и дерево как есть — молчат. NTF2-51 сравнивает `code`, `message`, `details` с полями функции на пине corelib вместо сравнения с фикстурой NTF-1 и прямо говорит, что копию не ловит | Р4, NTF2-51, NTF2-54, §6а, §6б, §7, DoD п.6 |
| класс B-1 по документу | перепись «единственный производитель → держатель», 9 строк; консоль: **NTF2-58 (г)** — `503` с текстом, выбранным пробой, экран показывает его дословно | §6б, NTF2-58, §7 |
| N-1: какой SAN меняет П4 | меняется URI-SAN (идентификатор из `kaname.spiffe`, сегмент служебной учётной записи); DNS-SAN, который край сверяет с `ServerName`, тот же — путь край → kaname не меняется; печать обоих и `ServerName` | §5 (П4), NTF2-06 |
| N-2: Р14 ссылался на NTF2-06 за сроком строки | Р14: `pending` — NTF2-06, истечение — NTF2-07 | Р14 |
| N-3: третий повод `503` без ссылки | строка §6б: проба замысла З8 (И6, CX2-28 (б)) | §6б |
| N-4: близнец NTF2-59 менял два факта; `Bs` и часы `Worker` | близнец — отдельная копия П6 с тем же посевом и тем же `S4`, отличие одно — хранилище исправно; «`503` не истратил вызов» — (д) в основном прогоне; `Bs` отсчитывает таймер главного потока страницы, останавливающий `Worker` | NTF2-59, NTF2-58, §6в |
| N-5: отпечаток NTF-1 не закреплён | шапка называет одобренную редакцию 16 NTF-1 (`390b5a33…`, APPROVED) и команду, показывающую, что NTF1-F21, G22, N06 против редакции 13 (`05828e42…`) не менялись. Замысел `issue-2917` (З21) приёмкой не правится — строка возврата | шапка |
| N-6: лимит шаблона ≥ максимума окна без ссылки | правило в Р8; строка §6б — проба замысла З19 (И14) | Р8, §6б |

**Новые ID:** NTF2-54 (номер был свободен). Снятых нет.

### Редакция 13 → редакция 14 (решения диспетчера Д39, Д40)

Редакция 13 одобрена кругом 2 (`ef9c6801…`, APPROVED). Правка меняет отпечаток, поэтому одобрение на
редакцию 14 не переносится (История review). Основание правки — решения диспетчера, а не возврат
ревью: Д39 — снятие почты поставщика личности принадлежит релизу identity-own (`kacho#1276` в волне-4
`kacho#2798`), страж секрета почты один; Д40 — база эпиков notify — линия релиза, все утверждения о
дереве перемеряются на её ветках предикатом с командой (Д24).

| что изменено | основание | где |
|---|---|---|
| результат S6 снят; сценарии NTF2-18, NTF2-20, NTF2-21, NTF2-22, NTF2-23 ушли в `kacho#1276`; посевы П7-kratos, П7-doc сняты; строки §6а, §6б, §7 и DoD пп.13–15а о них сняты | Д39 | §0, §4, §5, §6 (S6), §6а, §6б, §7, §8 |
| NTF2-19 (рубеж подтверждённости нашей полосы) перенесён в S1, NTF2-24 (читатель приёмника) — в S7: их предмет — почта личности через `notify`, а не почта поставщика | Д39 | §6 |
| Р19 переписан: почта поставщика — вне NTF-2; секрет почты — у `notify-sender`; страж один — `identity-mail-lane-guard.yaml`, доведённый до условия; второго шаблона стража (прежний замысел — страж листа под `courier`) нет | Д39 | Р19, §0, NTF2-31 (е), DoD п.14 |
| NTF2-31 (г) — вход повторного включения поставщика — снят: после NTF-2 без снятия почты поставщика этот вход красен на верной реализации (§1.7: 2 держателя у поставщика в dev) | Д39, замер §1.7 | NTF2-31 |
| полоса стража садится после `kacho#1276`: до него законный вход дерева — пробы, поднимающие поставщика, — нарушает условие стража | Д39, Д40, замер §1.7 | Р16 п.4, DoD п.14 |
| §3а: 49 файлов перемерены на `2798`, пути — именами `kacho#2759`; исход «снят» у NTF-2 исчез; новый исход «за `kacho#1276`» — 24 файла (строки 1, 3–5, 7, 8–18, 21–22, 34, 36, 40, 41, 43, 46); правится 7, переписан 4, остаётся 14; посевы редакции 5 и третий источник (без ключа `kratos.courier.enabled`) сняты как мерившие чужой предмет | Д39, Д40 | §1.9, §3а, DoD пп.13, 16 |
| строки 16–18 §3а (MAIL-52 и место С2) и 21–22 (MAIL-54), 34, 36, 43, 46 отнесены к `kacho#1276`, хотя Д39 называет поимённо строки 1–5, 7 и 8–15: их красный на прежнем посеве давало снятие хуков, шага подстановки и раздела `courier` поставщика — предмета, ушедшего в `kacho#1276`; NTF-2 их не трогает | Д39 (толкование автора) | §3а |
| §3б: 97 файлов на `367` (94 на `357`); группы `cmd/kaname/` 7, `deploy/` 10, `docs/content/` 6 | Д40 | §1.1, §3б |
| шапка и §1: база — линия релиза (`2564`/`2798`, `357`/`367`, `26` = `v1.10.0-rc.5`); каждое утверждение — команда и число; `sed -n` по номерам строк заменён поиском по тексту там, где волна-4 сдвинула строки (`people_address_writers.go` :20 на `357` → :23 на `367`; редакция 14 писала обратно, исправлено редакцией 15) | Д40, Д24 | шапка, §1, Р16, §6а, §7 |
| §1.7 — почта поставщика в дереве остаётся (6 строк слов почты в `_identity-provider.tpl`; архивы подчартов 2); §1.8 снят | Д39, Д40 | §1.7, §1.8 |
| §3: замещения ID-MAIL-1, относящиеся к почте поставщика (Р26, Р27, Р4а С2, §1.10а, MAIL-14…18, 49, 51, 52, MAIL-54, Д5), помечены «вне NTF-2 — `kacho#1276`» | Д39 | §3 |

**Снятые ID:** NTF2-18, NTF2-20, NTF2-21, NTF2-22, NTF2-23; вариант NTF2-31 (г). Не переиспользуются.
**Новые ID:** нет; новый вариант NTF2-31 (е), (е').

### Редакция 14 → редакция 15 (круг 1 редакции 14)

| замечание | что изменено | где |
|---|---|---|
| B-1 (CONSTRUCTIBILITY): у входа NTF2-31 (е), (е') нет формы; отсылка к З22 ложна (З22 описывает второй страж, запрещённый Д39) | замер §1.10: объявление удостоверения почты одно (`global.kacho.identity.smtp.credentialSecret`), его читают 3 шаблона подчарта kaname и страж; страж видит только объявления и имя приёмника (`include`/`tpl` — 3, манифестов других объектов не читает). Значения, отдающего ссылку объекту вне отправителя, после NTF-2 и `kacho#1276` нет, поэтому (е), (е') сняты (буква не переиспользуется), отсылка к З22 снята; условие «секрет только у отправителя» держит гейт над рендером — NTF2-30, NTF2-31 (а), (б), (д). Д39 «страж один» держит новый вариант NTF2-31 (ж), (ж'): перепись шаблонов, чей `fail` называет `credentialSecret`, — второй страж под любым именем красен; на базе 1 (§1.10, §6а) | §1.10, Р19, §3 (Р4а), §3а (строки 25, 26), §5 (П7-tpl), NTF2-31, §6а, §6б, §7, DoD пп.14, 19 |
| B-2 (PRODUCER): производитель `notify-sender` назван NTF-1; раздвоение службы — NTF-3 Р8 (NTF3-127) | предикат §0, NTF2-24, NTF2-30, NTF2-31 и П1 судят **отправителя `notify`** — единственный объект чарта `notify` со ссылкой на секрет почты — по границе чарта, а не по имени: при NTF-1 без NTF-3 это развёртывание `notify` (NTF1-I01), после NTF-3 Р8 — `notify-sender`. Р16 условием начала раздвоения не ставит и называет замер (`notify-(sender|api)` в NTF-1 → 0); §7 называет NTF-1 производителем чарта и развёртывания `notify`, NTF-3 — раздвоения | §0, Р15, Р16, Р19, §3, §3а, §5 (П1), S7, §6а, §6б, §7, §9 |
| класс PRODUCER по документу | перепись производителей, названных другой под-фазой (§7 — 12 строк таблицы; §6б — 2 строки, называющие NTF-1), сверена со словами одобренной NTF-1: `notifygen` 36, `source_identity_mismatch` 1, `platform_unavailable` 26, `template_skew` 42, `NTF1-B28` 24, `NTF1-I03` 2, `DeliveryNotConfiguredStatus` 1, `authorization: certificate` 3, `NTF1-F21` 2, `NTF1-G22` 4, `Message-ID` 3, `cid:` 2, `Reply-To` 5, `multipart` 5; разошлось одно — `dropped_overload` (0 в NTF-1): исход метрики kaname производит диспетчер почтовых работ kaname (NTF-2, замысел З13, З14), строка §6б исправлена | §6б |
| N-1: номера строк `people_address_writers.go` перепутаны | §1.3: :23 на `367`, :20 на `357`; строка §11 редакции 14 исправлена | §1.3, §11 |
| N-2: «страж один» проверялся образцом имени `mail.*guard` | DoD п.14 считает шаблоны, чей вызов `fail` называет `credentialSecret`, — NTF2-31 (ж) | DoD п.14, NTF2-31 |
| N-3: NTF-1 (строки 1330–1331) и замысел `issue-2917` (З22, :2036) расходятся с Д39 | вне этого документа — строка возврата автору NTF-1 и автору замысла | — |

**Снятые ID:** вариант NTF2-31 (е), (е'). Не переиспользуется.
**Новые ID:** нет; новый вариант NTF2-31 (ж), (ж'); посев П7-tpl.

### Редакция 15 → редакция 16 (возврат первичного разбора классов `issue-2917` на `229a4379…`)

Разбор вернул в приёмку два пункта (`return_to_acceptance`: RA-1, RA-2). Закрыто только наблюдаемое;
условия к коду того же разбора (CX2-47…56) — предмет замысла `docs/changes/issue-2917/design.md`, не
этого документа.

| замечание | что изменено | где |
|---|---|---|
| RA-1: вывод §1.10 и Р19 «объявление удостоверения одно, после NTF-2 и `kacho#1276` ссылку получает только отправитель `notify`» держится только при названном чтении узла `global.kacho.identity.smtp` чартом `notify`; производитель чтения не назван (в одобренной NTF-1 и её замысле узел не упоминается — 0 и 0), NTF1-I06 даёт чарту свою форму значений, DoD п.13 запрещает править `values.dev.yaml` с полосой стенда | новое решение Р20: чарт `notify` в зонтике читает полосу и удостоверение только из узла `global.kacho.identity.smtp`; самостоятельная поставка (NTF1-I06) задаёт тот же путь в собственных значениях; второго узла и ключа нет (Д42); незаданное удостоверение законно, своего отказа у чарта `notify` нет (отказы по узлу — страж, Р19); производитель чтения — **NTF-2** (`kacho#2917`). Держатель — новый сценарий NTF2-34: рендер `dev` под двумя именами релиза → адрес полосы отправителя `notify` — приёмник этого релиза, якорь — `ca.crt` его секрета; близнецы — одно изменённое значение узла (б), цепочка `a8f60d` (в), самостоятельная поставка (д); перепись путей значений полосы в шаблонах `notify` — (г) красный, (г') молчит. П1 печатает исход NTF2-34 (а) вместо «ссылок на секрет у чарта `notify` 1»: цепочка `dev` удостоверения не объявляет, и прежний признак останавливал бы пробу на верной реализации. DoD п.13 называет, почему правка `values.dev.yaml` не нужна | §1.10, Р20, §5 (П1), S7 (NTF2-34), §6а, §6б, §7 (NTF2-24, NTF2-30…32, NTF2-34), DoD пп.13, 19, покрытие ID |
| RA-2: исключение DoD п.16 привязано к исходу строки «за `kacho#1276`»; шесть файлов с исходом «остаётся» (строки 31–33, 35, 37, 42) — пробы конфигурации поставщика, и их снятие `kacho#1276` вернуло бы приёмку на верной реализации | исключение привязано к **факту** снятия: файл любого исхода, отсутствующий на базе старта и снятый коммитом посадки `kacho#1276` (команда `git log --diff-filter=D` названа), — исход `kacho#1276`, возвратом не является; снятие другой посадкой — возврат. §3а называет шесть строк и отсылает к п.16; исходы строк не менялись | §3а (итог), DoD п.16 |

**Снятые ID:** нет.
**Новые ID:** NTF2-34 (варианты (а)–(д), (г')); решение Р20.

### Редакция 16 → редакция 17 (круг 1 редакции 16)

Класс обоих блокирующих один: **утверждение приёмки опиралось на исход чужой посадки, у которого не
было ни команды, ни держателя** — B-1 о содержимом файла, отданного `kacho#1276`, B-2 о том, какой
коммит внесён его вливанием. Исправлен класс: каждое такое утверждение заменено командой с исходом.
Перепись мест, где документ говорит об исходе `kacho#1276`: Р20 («узел остаётся» — снято, заменено
Р16 п.5), DoD п.13 (то же), DoD п.16 (достижимость → диапазон), §1.10 «читатели поставщика сняты»
(держит гейт над рендером NTF2-30 на ветке эпика, DoD п.19 — держатель есть, правки нет), Р16 п.4
(команда названа — правки нет).

| замечание | что изменено | где |
|---|---|---|
| B-1 (CONSTRUCTIBILITY): Given NTF2-34 (а) и П1 опираются на узел в `values.dev.yaml`, отданном `kacho#1276`; «узел останется» — исход чужой посадки без команды и держателя | новое условие Р16 п.5: команда над значениями цепочки `dev` на `<B>` и на базе запроса волны; замер @`96e2fa72b3a` и отрицательный контроль названы; исход «узла нет» — возврат в приёмку, NTF-2 файл не правит; после посадки узел держит NTF2-34 (а). Утверждение «после `kacho#1276` узел остаётся» снято. Выбран первый из двух путей рецензента: исключение в DoD п.13 развело бы один файл по двум задачам, чей порядок посадки не задан | Р16 п.5, Р20, §3а строка 3, §6а, DoD «Условие начала», п.13 |
| B-2 (DoD): «коммит, достижимый из вливания» пропускает снятие другой посадкой | коммит снятия `D` судится диапазоном `M^1..M`; `M` находится тремя командами (коммит снятия, голова волны внутри `<B>`, слияния `#1276 merge` на первородительской линии приёмника); контроль в обе стороны названы; пустое `M` — снятие другой посадкой | DoD п.16 |
| N-1: (г) не говорит, как отличить путь чтения от упоминания | (г), (г') судятся подстановкой контрольных `X`, `Y` в узел, строковый поиск путей снят | NTF2-34, §6б, §7 |
| N-2: исход «`notify` включён, узел пуст» не назван | назван: рендер без полосы, отказа NTF-2 не вводит (Д42), поведение отправителя без адреса ретранслятора — NTF-1; сценарием NTF-2 не держится | Р20 |
| N-3: пара «имя в адресе ⇔ удостоверение» при самостоятельной поставке не проверяется | сказано явно | Р20 |

**Снятые ID:** нет. **Новые ID:** нет (новое условие Р16 п.5).

### Редакция 17 → редакция 18 (решение диспетчера Д44)

Д44: при включённом `notify` (флаг Д7) и пустом почтовом узле отправитель `notify` (`notify-sender`)
отказывается стартовать с понятным текстом — fail-closed, ban #16; установка без почты выключает флаг,
и источники отвечают `DeliveryNotConfigured`, одинаково для любого адреса. Ключ адреса ретранслятора и
страж старта вносятся в замысел NTF-1. Исход редакции 17 «отправитель без адреса — предмет NTF-1,
ключа в замысле NTF-1 нет, сценарием NTF-2 не держится» снят.

| что изменено | основание | где |
|---|---|---|
| исход «`notify` включён, узел пуст» (`prod`, `fe3455`): отказ старта отправителя `notify`, производитель — NTF-1; рендер проходит; установка без почты выключает флаг, источники отвечают единым отказом `DeliveryNotConfigured` (у kaname — NTF2-51); значения `prod` и `fe3455` NTF-2 не правит | Д44, Д7 | Р20, Р4 |
| доля NTF-2 в исходе названа и держится: пустой узел доезжает до ключа адреса ретранслятора пустым, умолчания нет (иначе страж NTF-1 мёртв) — NTF2-34 (е) на цепочке `prod` как есть, близнец (е') — одна строка узла `X` | Д44, `sec-no-silent-default-for-guarded-knob` | NTF2-34, §6а, §6б, §7, DoD п.19 |
| вход (е) измерен: `connectionURI` и `credentialSecret.name` пусты в `prod` и `fe3455` @`96e2fa72b3a` | Д24 | §6а |

**Снятые ID:** нет. **Новые ID:** нет; новые варианты NTF2-34 (е), (е').
