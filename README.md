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
* ☁️ **Cloudflare WARP:** Управление официальным WARP-клиентом (SOCKS5), **Endpoint Manager / WARPSCOUT** с подбором endpoint, проверкой трафика и откатом, а также Advanced WARPSCOUT для AmneziaWG.
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

## 🎯 Endpoint Manager / WARPSCOUT

Откройте **Настройка и оптимизация сервера → Cloudflare WARP → 7) Endpoint Manager / WARPSCOUT**.
Основное WARP menu сохраняет установку клиента, порт, cron restart, start/stop, logs и удаление. Пункт **8) Проверить здоровье WARP** выполняет полную проверку; при обычном redraw читается только локальное состояние службы и JSON `warp-cli`.

### Official WARP: Find → Apply → Verify

Endpoint Manager позволяет подобрать совместимый endpoint через WARPSCOUT, задать `IPv4:PORT` / `[IPv6]:PORT` вручную, вернуть **Cloudflare AUTO**, выбрать совместимый с SOCKS5 протокол и проверить здоровье. Advanced WARPSCOUT открывается отдельным пунктом 6.

* **Проверенный официальный клиент:** `warp-cli 2026.8.2110.0`, Ubuntu 24.04 x86_64. В этой версии **proxy mode поддерживает только MASQUE/QUIC**. WireGuard присутствует в CLI, но daemon отклоняет его в proxy mode с `Proxy mode only supports MASQUE`. Меню позволяет выбрать MASQUE с возвратом endpoint на AUTO; не включает host full-tunnel routing.
* **HTTP/2:** CLI принимает `tunnel masque-options set h2-only`, однако после reconnect и restart в proxy mode `tunnel stats` продолжает показывать `MASQUE (HTTPS via UDP)`. Поэтому `masque-h2` для официального proxy здесь не используется. Меню не меняет MASQUE HTTP options. Другие версии требуют повторной проверки transport; неизвестная JSON-схема блокирует изменения.
* **Совместимый scan:** `scan -a ACCOUNT -p masque -P -best -plain -masque-sni consumer-masque-proxy.cloudflareclient.com -o REPORT`. Используется реальный UDP transport и SNI из JSON `tunnel stats`. Для отключённого туннеля fallback на известный MASQUE/QUIC профиль разрешён только для проверенной версии `2026.8.2110.0`; при неизвестном transport подбор отменяется. MASQUE имеет отдельные anycast pools и **не гарантирует смену Cloudflare node**; `-exclude-node DME` и другие node/country filters upstream для MASQUE запрещает. Результат `-best` валидируется целиком; AWG endpoint автоматически к stock WARP не применяется.
* **Транзакция:** перед изменением из JSON settings сохраняются protocol, forced endpoint/AUTO, connection intent и proxy port. Используются штатные `tunnel endpoint set/reset`, disconnect/connect; при сбое команды, health check, readback или Ctrl+C восстанавливаются прежние настройки и состояние подключения, затем проверяется результат rollback. Отсутствие override считается AUTO только в проверенной версии CLI; в остальных версиях без override показывается «не определён» и изменения блокируются. Неизвестное состояние не считается AUTO. Изменения сериализуются через `flock`; отдельный state-файл не нужен.
* **Health:** HEALTHY требует active `warp-svc`, Connected, mode proxy, loopback SOCKS listener и HTTPS Cloudflare trace через `socks5h://127.0.0.1:PORT` с `warp=on`. Показываются exit IP, colo и location. DOWN означает отключённую службу/туннель или отсутствие proxy; DEGRADED — неподтверждённый data path/неизвестное состояние. Curl использует ограниченные timeouts, DNS через proxy, игнорирует пользовательский curl config и `NO_PROXY`. Проверка после connect ограничена шестью попытками.
* **Установка official WARP:** официальный APT repository и пакет `cloudflare-warp`, `warp-svc`, proxy mode, registration, порт 40000, connect и cron restart в 03:00. Proxy mode задаётся до регистрации/подключения. Зелёный результат появляется только после real health check; при неудаче можно согласиться на подбор через WARPSCOUT. Установка WARPSCOUT и создание его account требуют отдельного подтверждения, если отсутствуют.
* **Persistence:** на проверенной версии custom endpoint, MASQUE, proxy mode и нестандартный SOCKS port сохраняются после `systemctl restart warp-svc`; клиент подключается снова. Дополнительные cron/systemd hooks не создаются.

Endpoint scan показывает доступность из сети VPS. Даже успешный MASQUE scan сам по себе не доказывает работоспособность официального proxy: окончательный критерий — trace после применения. При внешнем сетевом сбое rollback может также не пройти health check; меню явно сообщает, если восстановление не подтверждено.

### Advanced WARPSCOUT / AmneziaWG

Сохранены install/update, создание и проверка account, рекомендуемый AWG scan, AWG best endpoint и генерация native AmneziaWG config.

* **Установка/обновление:** официальный [installer WARPSCOUT](https://github.com/vernette/warpscout/blob/master/install.sh), `INSTALL_DIR=/usr/local/bin` и `--yes`. Бинарник: `/usr/local/bin/warpscout`. Повторный запуск устанавливает свежий release; актуальная версия остаётся на месте. Linux-сборки доступны для x86_64 и ARM64.
* **Данные:** `/root/.config/warpscout` (права `700`), account — `/root/.config/warpscout/warpscout-account.json` (права `600`). Все account-команды получают явный `-a`. Существующий account не перезаписывается при создании или обновлении. Регистрации официального WARP и WARPSCOUT независимы; secrets между ними не переносятся.
* **AWG scan:** `scan -p awg -P -exclude-node DME`; поиск лучшего добавляет `-best`, генерация — `-conf FILE`. AmneziaWG obfuscation отсутствует в stock WARP, поэтому эти результаты предназначены для standalone/AmneziaWG использования.
* **Результаты:** Advanced создаёт уникальный `scan-ДАТА-ВРЕМЯ-XXXXXX/` с `report.txt` и, при генерации, `warp.conf`. Official optimizer создаёт `official-ДАТА-ВРЕМЯ-XXXXXX/` с `report.txt` и `best.txt`. Меню показывает пути. Config содержит приватный ключ; импортируйте его в AmneziaWG-клиент самостоятельно.

Расширенные параметры (I1/junk, DNS, MTU, форматы config) доступны через `warpscout scan -h` и [документацию WARPSCOUT](https://github.com/vernette/warpscout). При ручном запуске указывайте `-a /root/.config/warpscout/warpscout-account.json`.

Для Endpoint Manager нужны `jq`, `python3`, `curl`, `ss`, `timeout` и `flock` (пакеты `iproute2`, `coreutils`, `util-linux` входят в обычную Ubuntu). Установка WARP добавляет jq/python3. Offline regression tests без обращения к настоящему WARP/сети: `bash tests/test_warp_endpoints.sh` (Bash, jq, Python 3, flock).

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
