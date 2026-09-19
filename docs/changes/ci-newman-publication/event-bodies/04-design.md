CI-NP-1 / kacho#1810 — независимое review-событие

Роль: `design-reviewer`. Вердикт: **APPROVED**.
Предмет: `PRO-Robotech/kacho-workspace:docs/specs/sub-phase-CI-NP-1-newman-publication-design.md`.
SHA-256 предмета: `d60f34f6a2458e011f46cbe460310ed0e5071ee0635ae0fb188a70c387bc9181`.
Источник анализа: `/root/hygiene_audit`; автор документов: `/root/e2e_audit`.
Полный независимый review: `docs/changes/ci-newman-publication/review-history/20260917-approved-review.md`, SHA-256 `1cf74cbc9cfeefe8935d543627786e25b1de2c997ebb70210a71ece8594bfd84`.

## Design-reviewer — APPROVED

DR1/DR2 закрыты: безопасность основывается на закрытом публичном формате и на
проверке фактически отправляемого private buffer. Минимальный SDK transport общий
для двух продуктов, его протокол не копируется. Старый path uploader не может
считаться эквивалентной реализацией принятого byte binding.

Достижимость exact SDK seam независимо повторена на Node 26.8.1 и Node 24.21.0.
На Node24 фактическая uploadToBlobStorage/WaterMarkedUploadStream получила 34 bytes;
checked/received/returned SHA256 равны, один recording transport call, сеть 0.
Версия @actions/artifact 6.2.1, dependency lock SHA256
fcb99bf7fb824e8ddb93269eca3f3537427fdbd13c2e556383d3bda2e39f422c.
Node24 proof SHA256 217d8dabcc4e79be32b5cd323ec57b0beb669ee5c277448eb12f57e007d9d7a5.
Это proof API seam, не реальный upload и не RED отсутствующего инструмента.

Runtime delivery конструктивна: runs.using=node24 получает Actions credentials
внутри JS action, чего bare shell publisher не гарантирует. Это сверено по
[официальному NodeScriptActionHandler](https://github.com/actions/runner/blob/main/src/Runner.Worker/Handlers/NodeScriptActionHandler.cs)
и [ScriptHandler](https://github.com/actions/runner/blob/main/src/Runner.Worker/Handlers/ScriptHandler.cs).
Свежая runtime копия dependency из того же Go module pin допустима: отсутствие
коммитной копии, совпадение содержимого и установка lock без изменения module cache
являются исполняемыми обязательствами, а не предположением о форме архива.

Это событие относится к точному содержимому документов. Оно не означает GREEN продукта, выполненный holder RED, разрешение implementation, landing или закрытие #1810. Следующий переход требует проверки остальных событий и независимого RED.
