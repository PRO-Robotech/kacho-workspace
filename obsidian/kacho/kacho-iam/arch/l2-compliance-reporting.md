---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.ComplianceReportService/GenerateAccessReport
  - rpc: kacho.cloud.iam.v1.ComplianceReportService/GetComplianceReport
  - rpc: kacho.cloud.iam.v1.ComplianceReportService/GetReportDownloadUrl
  - rpc: kacho.cloud.iam.v1.ComplianceReportService/ListComplianceReports
status: implemented
source_sha: ""
---

# Compliance reporting

Генерация и выдача compliance-отчётов — снимков состояния доступов и identity
для аудиторов.

## Зачем

Аудит (SOC 2 / ISO 27001) требует периодических артефактов «кто к чему имел
доступ на дату X». Сервис материализует такие снимки в файл-отчёт и отдаёт его
по защищённой ссылке, чтобы аудитор не лазил по живому API.

## Контракт

- `GenerateAccessReport` — async (`Operation`); запускает генерацию access-report
  для scope (account); метаданные операции — `ComplianceReportMetadata`,
  результат — `ComplianceReport`.
- `GetComplianceReport` — sync read по `report_id`.
- `ListComplianceReports` — sync read со scope-фильтром.
- `GetReportDownloadUrl` — суффикс-action `:getDownloadUrl`; выдаёт
  ограниченную по времени ссылку на скачивание артефакта.

## Lifecycle

- `GenerateAccessReport` ставит async-операцию; worker собирает снимок
  (bindings + identity + group-membership) и складывает артефакт в object-store.
- Готовый `ComplianceReport` доступен через `Get` / `List`; сам файл — только
  через `GetReportDownloadUrl` (presigned-URL, не публичный путь).

## Gotchas

- Чтения требуют relation `viewer` на scope; генерация — повышенных прав.
- Download-URL краткоживущая — повторное скачивание требует нового вызова
  `GetReportDownloadUrl`.
- Артефакт — снимок на момент генерации, не live-вью: для актуального состояния
  нужен новый отчёт.
