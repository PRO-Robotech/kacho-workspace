---
title: rm-cmd
category: package
repo: kacho-resource-manager
layer: cmd
status: deprecated
tags:
  - packages
  - kacho-rm
  - cmd
  - composition-root
  - deprecated
---

> [!warning] Пакет снят вместе со своим репозиторием (KAC-124)
> Репозитория resource-manager не существует; в монорепо продукта каталога этого
> сервиса нет. Ниже — след, а не описание действующего пакета.

# rm-cmd — снят (KAC-124)

Корень сборки снятого сервиса: единственное место, где связывались слои —
настройки, наблюдаемость, пул соединений, хранилище, сценарии, обработчики,
рабочий операций и порядок остановки.

## Что снято из этой записки

Путь к точке входа и имя схемы БД удалены как координаты: ни того, ни другого в
дереве нет. Пронумерованный порядок связывания сохранён по смыслу — он описывает
общий для платформы рисунок корня сборки, а не файл.

## See also

[[rm-config]] [[rm-handler]] [[rm-service]] [[rm-repo]] [[rm-bootstrap]]
[[../kacho-resource-manager/README]] [[../KAC/KAC-124]]

#packages #kacho-rm #cmd #composition-root #deprecated
