# uppkgs

### Описание файлов:

_**uppkgs.sh** - скрипт автоматического обновления python пакетов через poetry
в python бекендах с созданием MR'ов в gitlab._

_**example.config.json** - пример структуры конфигурационного файла для 
настройки поведения скрипта._

### Зависимости:
* [curl](https://curl.se/)
* [jq](https://stedolan.github.io/jq/)
* poetry
* pytest
* git
* docker

### Использование:
1. Создать конфиг по шаблону `example.config.json`;
1. Запустить скрипт `uppkgs.sh` с указанием абсолютного пути к конфигу
```zsh
zsh uppkgs.sh /some_absolute_path_to/config_file.json
```
