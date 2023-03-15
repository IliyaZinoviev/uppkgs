# uppkgs

### Описание файлов:

_**uppkgs.sh** - скрипт автоматического обновления python пакетов через poetry в 
python бекендах с созданием MR'ов в gitlab._

_**.env.json** - конфигурационный файл для настройки поведения скрипта._

### Зависимости:
* [curl](https://curl.se/)
* [jq](https://stedolan.github.io/jq/)
* poetry
* pytest
* git
* docker

### Использование:
1. Перейти в директорию со скриптом `uppkgs.sh`
1. Создать конфиг `.env.json` по шаблону `example.env.json`;
1. Настроить конфиг `.env.json`.
1. Запустить скрипт `uppkgs.sh`
```zsh
zsh uppkgs.sh
```
