# security-auditor · kacho PR #3071 · голова 2eba982e

- режим: пост-дифф ревью, один круг; `origin/2914-notify...2eba982e3221c7a1757cf7d2396510aaae670660`
  (база `4d5295f1ae96`); прошлая запись — `kacho-pr3071-8dd826d1.md`, новое в этой голове — полоса D1
  (`58e166acea`, `bb2751b33d`, `632cc5a4e9`, `113e45843d`) и слияние `origin/2914-notify`
- вердикт: **accept**; блокирующих 0; подтверждённых находок по безопасности 0

## Объём осмотренного

`git diff --stat` PR — 134 файла (+12162/−229); дельта к прошлой голове `8dd826d14d..113e45843d` —
47 файлов (+1128/−81). Прочитаны целиком: `gateway/deploy/templates/deployment.yaml` (дифф), `gateway/deploy/values.yaml`
(дифф), слои `values.{dev,fe3455,own-stand,a8f60d,prorobotech}.yaml` (дифф), `deploy/testdata/{mail-node,notify-standalone,stand-dns}`,
`deploy/scripts/{seed-notify-stand-secrets,stack-secrets}.sh` (дифф и помощники), `trivy.yaml`,
`config.ReadAnonMailPoWKey`, `deploy/stacks.txt`, сообщения четырёх коммитов D1. Звено ограничителя
(E1/E2) прочитано прошлым кругом и в этой голове не менялось.

## Поверхность

- Новых RPC, слушателей, записей каталога прав, отношений модели нет.
- Чарт края выводит 19 ручек стража через `required` без умолчаний; число прыжков в базе чарта не
  объявлено, `0` выводится как законное значение. Отказ рендера называет ручку — проверено
  `helm template g gateway/deploy` (отказ на `KACHO_API_GATEWAY_TRUSTED_HOPS`) и `--set anonMail.powKey.secretName=null`
  (отказ на имени объекта).
- Ключ подписи вызовов: в дереве только координата объекта Secret; том обязательный, `readOnly`; путь
  файла — `<mountPath>/<secretKey>`, абсолютный и канонический, загрузчик идёт `Stat` по ссылке тома и
  требует обычный файл ≥ 32 байт — совместимо с раскладкой смонтированного секрета. Посев порождает
  ключ один раз процессной подстановкой, значение не печатается; отказ сервера, отличный от NotFound, —
  отказ посева; пустой материал при сбое генератора даёт закрытый отказ старта, а не слабый ключ.
- Число прыжков `1` на стендах повторяет прежнее умолчание процесса (поведение адреса клиента не
  меняется); слоёв, доверяющих пересланным заголовкам сверх одного входа, нет.
- Публичные тексты (тело PR, сообщения коммитов D1, комментарии чарта) признак восстановимости
  проходят; атрибуции в сообщениях PR нет (`git log origin/2914-notify..HEAD | grep -ciE 'co-authored|generated with|claude.ai/code'` → 0).

## Проверки (исполнены на голове, TMPDIR — свой каталог)

- `go test -count=1 ./gateway/deploy/ ./gateway/internal/config/ ./gateway/internal/middleware/anonmail/ ./gateway/cmd/api-gateway/` — 4 пакета ok
- `go test -count=1 -tags helmcharts ./deploy/ ./deploy/helm/umbrella/` — 2 пакета ok (после `helm dependency build --skip-refresh`;
  без сборки зависимостей прогон — «не выполнилось», не красный)
- `shellcheck -S warning deploy/scripts/seed-notify-stand-secrets.sh deploy/scripts/stack-secrets.sh` — 0

## Небезопасностные замечания (не блокируют)

- Комментарий у тома ключа в `gateway/deploy/templates/deployment.yaml:589-590` называет производителем
  стенда `dev-prod-secrets.sh`; после `113e45843d` производитель — `seed-notify-stand-secrets.sh`
  (так пишут `values.yaml` и `stack-secrets.sh`). Правда документа, исполнитель D1.
- После `113e45843d` предполёт площадки (`cutover-fe3455.sh`) объект ключа не требует; на площадке
  без объекта под стоит до старта с именем секрета (закрыто, не открыто). Порядок выкатки — диспетчер.
- Тома секретов края без `defaultMode` (0644 в контейнере) — так у всех томов шаблона, не новое.
