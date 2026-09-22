---
name: rule-security-disclosure
description: "Безопасность: что НЕ идёт в публичные артефакты"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/security-disclosure.md`

# Безопасность: что НЕ идёт в публичные артефакты

## Публичные артефакты — НЕ раскрывать operational security-internals (выведено 2026-07)

disc-no-consolidated-assembly · не собирать координату + условие + следствие для постороннего в одном публичном месте · ЗАВЕСТИ disc-no-consolidated-assembly · red: сборка из трёх элементов
disc-assembly-not-parts · имя порта/функции/отношения/код ошибки оставлять порознь; выхолащивать правило нельзя · ЗАВЕСТИ disc-assembly-not-parts · red: правило без причины (снимут как непонятное)
disc-three-places-not-subject · называть запрещаемое свойство прямо, не выхолащивать · ЗАВЕСТИ disc-three-places-not-subject · red: обезличенный текст в этих трёх местах
disc-workdir-is-draft · рабочую директорию задачи считать черновиком; не ссылаться на неё в коммите, vault или приёмке · ЗАВЕСТИ disc-workdir-is-draft · red: ссылка на эфемерный путь
disc-diff-is-the-address · разбор находки адресовать диффом фикса (номер PR/хеш), не пересказом · ЗАВЕСТИ disc-diff-is-the-address · red: пересказ разбора в записке
disc-artifacts-withstand-publication · acceptance/trail/docs/записки писать так, чтобы выдерживали публикацию; иначе не коммитить вовсе, ни в vault, ни в приёмку · ЗАВЕСТИ disc-artifacts-withstand-publication · red: разбор по шагам в приёмке
disc-self-apply-recoverability · признак восстановимости прогонять по собственному тексту до публикации; уже опубликованное — отредактировать и назвать факт и причину правки · ЗАВЕСТИ disc-self-apply-recoverability · red: правило цитируют другим и не применяют к себе

### Проверяемый признак для СООБЩЕНИЯ КОММИТА (выведено 2026-07-28, класс повторился дважды за день)

disc-recoverability-predicate · переписывать сообщение коммита, если читатель без доступа к коду восстановит по нему состояние до фикса настолько, чтобы воспользоваться · ЗАВЕСТИ disc-recoverability-predicate · red: «уровень контракта и поведения» как критерий
disc-preservation-proof · знаменатель — пути ВСЕЙ полосы: git diff --name-only $(git merge-base <база> <голова>)..<голова>; добавленное присутствует, снятое не уцелело, непустое расхождение не вердикт · scripts/preservation-proof.sh · red: знаменатель — файлы головного коммита, потеря вне их молчит
disc-preservation-predicted-first · дерево слияния предсказывать ДО необратимого шага, сверять после; факт годен для этой пары голов · scripts/preservation-proof.sh --predict · red: предсказания не было
disc-rewrite-history-needs-owner · переписывать историю публичной ветки принудительно — только с разрешения владельца; штатно — merge --squash + удаление ветки · ЗАВЕСТИ disc-rewrite-history-needs-owner · red: force-push по своему решению
disc-squash-says-it-is-squashed · тело squash-коммита обязано нести «схлопнуто из <ветка>, исходные коммиты <sha>; ветка удалена» — правило и для cherry-pick · ЗАВЕСТИ disc-squash-says-it-is-squashed · red: отсутствие хеша читается как потеря работы
disc-hash-exception-when-rewritten · исходные хеши не перечислять, если сообщения переписаны по дисциплине публичного репо; называть ветку и причину · ЗАВЕСТИ disc-hash-exception-when-rewritten · red: ссылка на объект со старым текстом
