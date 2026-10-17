# 🚀 VPS Server Menu

**VPS Server Menu** — это мощный, удобный и полностью интерактивный Bash-скрипт для быстрого управления и настройки вашего VPS/VDS сервера. 

Забудьте о необходимости запоминать десятки длинных команд. Управляйте прокси, сетью, фаерволом и системными тестами прямо из красивого консольного меню!

---

## ✨ Главные возможности

* 📊 **Системный мониторинг:** Отображение нагрузки на процессор (LA), использования оперативной памяти и аптайма сервера прямо на главном экране.
* 🛡️ **Управление прокси:** Установка, настройка и управление современными протоколами обхода блокировок:
  * **Hysteria2** (с автоматической генерацией сертификатов и управления пользователями).
  * **X-UI** (VLESS, Reality, Trojan и др.).
* 🌐 **Управление сетью и IPv6:** Безопасное включение/отключение IPv6 на уровне ядра, проверка доступности и назначенных адресов.
* ☁️ **Cloudflare WARP:** Управление официальным WARP-клиентом (SOCKS5) и отдельное submenu **WARPSCOUT** для поиска endpoint'ов и генерации AmneziaWG config.
* 🔒 **Фаервол и порты:** Быстрое открытие портов (UFW) и управление SSL-сертификатами (Acme.sh).
* 🧪 **Инструменты тестирования (Menu Tests):** Встроенные скрипты для диагностики сети и обхода блокировок:
* 🔄 **Умное обновление:** Встроенная функция `git pull` для обновления меню до последней версии в один клик без перезагрузки сервера.
## 🛠 Установка / Обновление
Запустите команду в терминале вашего сервера:
```bash
bash <(curl -sL https://raw.githubusercontent.com/Diman6267/VPS-Server-Menu/main/install.sh)
```

## 🗑 Удаление
```bash
bash <(curl -sL https://raw.githubusercontent.com/Diman6267/VPS-Server-Menu/main/uninstall.sh)
```
---
## 📸 Скриншоты
![Main Menu](main_menu.png)


![Main Menu](menu_tests.png)


![Main Menu](menu_setup.png)


## ⚙️ Требования
ОС: Ubuntu 20.04+

Права: root

Установленные пакеты: git, curl (остальные зависимости, такие как Docker или Python, меню установит автоматически при запуске соответствующих тестов).

## 🛰️ WARPSCOUT в WARP menu

Откройте **Настройка и оптимизация сервера → Cloudflare WARP → 7) WARPSCOUT**.
Submenu показывает установленную версию и наличие account file, позволяет установить/обновить WARPSCOUT, создать account, выполнить рекомендуемый scan, найти лучший endpoint и сохранить готовый AmneziaWG config. Официальный `warp-cli` / `warp-svc` управляется прежними пунктами WARP menu независимо от WARPSCOUT.

* **Установка/обновление:** официальный [installer WARPSCOUT](https://github.com/vernette/warpscout/blob/master/install.sh), запускаемый с `INSTALL_DIR=/usr/local/bin` и `--yes`. Бинарник: `/usr/local/bin/warpscout`. Повторный запуск устанавливает свежий release; если версия уже актуальна, upstream installer оставляет её на месте. Linux-сборки installer доступны для x86_64 и ARM64.
* **Данные:** `/root/.config/warpscout` (права `700`), account — `/root/.config/warpscout/warpscout-account.json` (права `600`). Меню передаёт этот путь через `-a` во все команды регистрации/сканирования. Существующий account не перезаписывается при создании или обновлении; повторный `register` через CLI может изменить ключи.
* **Scan:** `scan -p awg -P -exclude-node DME` — AmneziaWG с проверкой ping/потерь внутри туннеля и исключением московского узла. Пункт поиска лучшего endpoint добавляет `-best`, генерация config — `-conf FILE`. Каждый пункт запускает новый scan; результаты отражают доступность из сети VPS, на которой он запущен.
* **Результаты:** каждый scan получает отдельный каталог `/root/.config/warpscout/scan-ДАТА-ВРЕМЯ-XXXXXX/`, содержащий `report.txt` и, при генерации, `warp.conf`. Меню показывает пути сохранённых файлов. Config содержит приватный ключ; импортируйте его в AmneziaWG-клиент. Меню не активирует туннель и не меняет маршрутизацию VPS.

Расширенные настройки (I1/junk, DNS, MTU, форматы config) доступны напрямую через `warpscout scan -h` и [документацию WARPSCOUT](https://github.com/vernette/warpscout). При ручном запуске также указывайте `-a /root/.config/warpscout/warpscout-account.json`.

---

## 🤝 Благодарности и используемые компоненты

Этот проект был бы невозможен без огромного количества замечательных инструментов от Open Source сообщества и поддержки профильных ресурсов. Выражаю огромную благодарность авторам следующих проектов, которые интегрированы в данное меню:

### 📢 Сообщество и идеи
* **[Комьюнити ITDog]** — за предоставленные скрипты проверки, ценные обсуждения, тесты и неоценимый вклад в развитие свободного интернета в РФ. Вы лучшие! 🐕

### 🛡️ Прокси и маршрутизация
* **[3x-ui](https://github.com/MHSanaei/3x-ui)** от *MHSanaei* — многофункциональная панель управления X-UI.
* **[Hysteria 2](https://github.com/apernet/hysteria)** от *AperNet* — мощный и невероятно быстрый протокол для обхода цензуры.

### 🕵️‍♂️ Анализ блокировок и сети
* **[WARPSCOUT](https://github.com/vernette/warpscout)** от *vernette* — поиск Cloudflare WARP endpoint'ов и генерация config; [лицензия MIT](https://github.com/vernette/warpscout/blob/master/LICENSE), Copyright (c) 2026 Nikita S. Меню вызывает отдельно установленный upstream-бинарник; исходники и бинарные файлы WARPSCOUT в этот репозиторий не включены.
* **[Censorcheck & IP Region](https://github.com/vernette)** от *vernette* — скрипты для проверки геоблоков и определения принадлежности IP.
* **[RealiTLScanner](https://github.com/XTLS/RealiTLScanner)** от *XTLS* и база **[GeoIP](https://github.com/Loyalsoldier/geoip)** от *Loyalsoldier* — продвинутый сканер для поиска SNI.
* **[DPI Detector](https://github.com/Runnin4ik/dpi-detector)** от *Runnin4ik* — утилита для глубокого анализа цензуры трафика в РФ.
* **[SNI Scan](https://github.com/dewil/sni-scan)** от *dewil* — удобный Python-скрипт для сканирования подсетей на доступность SNI.

### 📊 Бенчмарки и тесты сервера
* **[YABS (Yet Another Bench Script)](https://github.com/masonr/yet-another-bench-script)** от *masonr* — один из лучших комплексных тестов производительности (CPU, RAM, Disk, Network).
* **[bench.sh](https://bench.sh/)** от *teddysun* — классический скрипт для вывода характеристик сервера и проверки скорости сети.
* **[IPQuality](https://github.com/xykt/IPQuality)** от *xykt* — отличный инструмент для проверки IP сервера на блокировки и флаги со стороны зарубежных сервисов.

## 📝 Лицензия
Проект распространяется по лицензии MIT. Вы можете свободно использовать, изменять и распространять этот код.
