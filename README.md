# xlab-selfhosted

Docker Compose для лаборатории, которая держит свой API. В одном файле собраны стек xlabcombine (API, Redis, Kafka, SendService, SQL Server), веб-LIMS и SignalR.

Вход сотрудников открывается на самом сайте. Пароль хранится в рабочей базе, в `Org_Staff`, и в xlab-license не отправляется. Лицензия только из файла в `.env`. Этот стенд в xlab-license не ходит. Сервис входа xlab-auth он тоже не использует.

Образы API, сайта, SignalR, SendService и SQL Server тянутся из реестра `XLAB_REGISTRY`. По умолчанию это `artifactory.x-lab.pro/xlab-release`, тег `latest`. Compose их не собирает.

| Сервис | Образ | Порт внутри сети | Кто снаружи |
|---|---|---|---|
| `api` | `xlabapi:latest` | HTTP 8080 | браузер, рабочее место, SendService |
| `web` | `xlablimsweb:latest` | HTTP 80 | браузер |
| `signalr` | `xlabsignalrservice:latest` | HTTPS 443 | браузер (`/messageHub`), SendService (`/api/messages`, `/api/ClientCommands`) |
| `redis` | `redis:7-alpine` | 6379 | только API |
| `broker` | `apache/kafka` | 9092 | API и SendService |
| `sendservice` | `xlabsendservice:latest` | нет | почта и публичный адрес SignalR |
| `mssql` | `xlab-mssql:latest` | 1433, на хосте тоже 1433 | API |

Один и тот же `cert.pfx` API и SignalR при каждом старте заново записывают из `OPENIDDICT_PFX_BASE64`. Старый файл в контейнере не остаётся. В образ он не входит. Пароль один: `OPENIDDICT_PFX_PASSWORD`. HTTPS-сертификат SignalR по-прежнему выпускается при старте и к этому файлу не относится.

Сайт при старте записывает в `config/xl-env.js` признак своего входа, публичный адрес API и адрес хаба. Смена этих значений — новый запуск контейнера `web`, не новая сборка образа.

## Что остаётся снаружи

```text
браузер → web (своя страница входа: логин и пароль)
браузер → api  (password flow, проверка Org_Staff, дальше OData)
браузер и рабочее место → signalr /messageHub (токен API, сертификат)
api при старте читает файл лицензии и оставляет одну организацию
SendService → публичный HTTPS signalr
```

SQL Server биллинг не хранит. Сотрудники и хеши паролей в xlab-license не выгружаются.

## Лицензия

Файл лицензии выпускается кнопкой на лицензии организации. Кнопка видна, если у тарифа включён свой сервер. Каждое нажатие заменяет ключ установки и файл: в `.env` нужно положить обе новые строки и перезапустить `api`. Логин и пароль суперадмина кнопка не выдаёт — их задают отдельно, см. таблицу оффлайн-лицензии ниже.

Без этих четырёх строк compose не поднимает `api`. Адрес xlab-license, HMAC и секрет клиента compose обнуляет, даже если они остались в `.env`. `XLAB_AUTH_URL` оставьте пустым.

На хосте xlab-license для выпуска файла нужен ключ подписи продукта (`OFFLINE_LICENSE_SIGNING_KEY`). Закрытый ключ установки уходит только в `.env` этой лаборатории.

## Запуск

Рядом с `docker-compose.yml`:

```bash
cp .env.example .env
```

Заполните `.env`. Пароли и ключи с символом `$` в Coolify помечайте **Literal**. Файл `.env` не коммитится.

Каталог данных SQL Server на хосте, до первого старта:

```bash
sudo mkdir -p /data/xlab/mssql
sudo chown -R 10001:0 /data/xlab/mssql
sudo chmod -R 770 /data/xlab/mssql
```

`10001` — пользователь `mssql` внутри образа. Файлы баз лежат в `/data/xlab/mssql/data`, копии — в `/data/xlab/mssql/backup`. Рядом появятся системные базы, `log` и `secrets`. Каталог `secrets` не удалять. Сам каталог не класть в git: Coolify заново клонирует репозиторий при выкладке.

```bash
docker compose up -d
```

Смена переменных читается при следующем старте контейнера. Для сайта это тоже старт, не пересборка образа.

## Параметры `.env`

Имена ниже — все, которые читает этот compose. Пустая ячейка в колонке «по умолчанию» значит, что значения в файле нет и его нужно задать, если строка обязательная.

### Адреса и образы

| Имя | Обязательно | По умолчанию | Куда попадает |
|---|---|---|---|
| `XLAB_REGISTRY` | нет | `artifactory.x-lab.pro/xlab-release` | префикс образов `xlabapi`, `xlablimsweb`, `xlabsignalrservice`, `xlabsendservice`, `xlab-mssql`. Тег всегда `latest` |
| `API_PUBLIC_URL` | да | | Сайт шлёт сюда вход и дальнейшие запросы. SendService ходит на API по этому адресу. SignalR сверяет издателя токена с этим адресом и слэшем на конце (`https://api.example.com/`) |
| `WEB_PUBLIC_URL` | да | | CORS API и SignalR. Источник браузера, без пути и без слэша |
| `SIGNALR_PUBLIC_URL` | да | | SendService вызывает `…/api/messages` и `…/api/ClientCommands`. Сайт пишет в конфиг `…/messageHub`. Имя хоста из этого адреса становится первым именем в сертификате HTTPS контейнера SignalR |
| `XLAB_AUTH_URL` | нет | пусто | Оставьте пустым. Сайт входит сам, API проверяет `Org_Staff`, SignalR принимает токен API |

SendService ходит на **публичный** адрес SignalR. Внутреннее имя `signalr` в сертификат тоже попадает, но сертификат самоподписанный, а SendService проверяет TLS. Публичный прокси должен предъявлять настоящий сертификат.

### Ключи этой установки

| Имя | Обязательно | По умолчанию | Куда попадает |
|---|---|---|---|
| `SIGNALR_API_KEY` | да | | SignalR `Security__ApiKey`. SendService шлёт его заголовком `API-Key` на три темы SignalR. Свой секрет, не ключ из чужого стенда |
| `OPENIDDICT_PFX_BASE64` | да | | `cert.pfx` одной строкой base64. При каждом старте API и SignalR заново записывают `/app/cert.pfx` |
| `OPENIDDICT_PFX_PASSWORD` | да | | пароль этого файла. Compose передаёт его в API и в SignalR |
| `XLabApiSettings__Security__SystemApiKey` | да | | API проверяет заголовок системного ключа. SendService кладёт сюда то же значение в `SendService__Api__SystemApiKey`. Отдельный секрет от `SIGNALR_API_KEY` |

Сгенерировать ключ:

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Сертификат токена — отдельный файл, не сертификат сайта и не самоподписанный HTTPS SignalR. В именах два хоста: из `API_PUBLIC_URL` и из `SIGNALR_PUBLIC_URL`. В примере это `api.example.com` и `push.example.com`. Пароль в команде — тот же, что `OPENIDDICT_PFX_PASSWORD`. В пароле нет `$`, кавычек и пробела. Последняя строка вывода python — значение `OPENIDDICT_PFX_BASE64`.

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout cert.key -out cert.crt \
  -subj "/CN=api.example.com" \
  -addext "subjectAltName=DNS:api.example.com,DNS:push.example.com"
openssl pkcs12 -export -out cert.pfx -inkey cert.key -in cert.crt -passout pass:CHANGE_ME
python -c "import base64,pathlib; print(base64.b64encode(pathlib.Path('cert.pfx').read_bytes()).decode())"
rm -f cert.key cert.crt cert.pfx
```

### SQL Server

Пароль: не короче 8 символов и три группы из набора «заглавные, строчные, цифры, символы». В пароле `xlab` нет символов `;` и `"`.

| Имя | Обязательно | По умолчанию | Куда попадает |
|---|---|---|---|
| `MSSQL_SA_PASSWORD` | да | | учётная запись `sa` |
| `MSSQL_XLAB_PASSWORD` | да | | учётная запись `xlab` и пароль API к рабочей базе и базе протоколов |
| `MSSQL_DATABASES` | да | | список баз. Формат ниже |
| `MSSQL_PID` | нет | `Developer` | ключ продукта. Пусто — редакция Developer |
| `MSSQL_MEMORY_LIMIT_MB` | нет | `2048` | потолок памяти SQL Server, МБ. Ниже потолка контейнера |
| `MSSQL_CONTAINER_MEMORY` | нет | `3g` | потолок памяти контейнера (`3g`, `4096m`) |
| `MSSQL_SHM_SIZE` | нет | `1gb` | `/dev/shm`. Берётся из памяти контейнера, сверху не прибавляется |
| `MSSQL_PUBLISH_PORT` | нет | `1433` | порт SQL Server на хосте. В файрволе оставьте его лабораторной сети |

Одна база: `Имя|ФайлДанных|ФайлЖурнала|Роль`. Несколько баз через `;`.

| Роль | Что делает API |
|---|---|
| `Working` | рабочая база. Задания Agent и таблицы OpenIddict смотрят сюда |
| `Report` | база протоколов |
| пустая | база подключена, `xlab` — `db_owner`, API к ней не ходит |

Обязательны `Working` и `Report`. Пустая роль повторяется. Пример одной строкой:

```text
XLab|XLab.mdf|XLab_log.ldf|Working;XLabReport|XLabReport.mdf|XLabReport_log.ldf|Report
```

Имена файлов — те, что уже лежат в `/data/xlab/mssql/data`. Compose собирает две строки подключения на `mssql,1433` от пользователя `xlab`. Строка подключения, записанная в Coolify вручную, не используется.

Часы контейнера — UTC. `ArchiveWork` в 21:00 UTC. `StopTrackingTime` смотрит на 08:00–18:00 UTC.

Без ключа продукта контейнер работает как Developer. Отключение телеметрии на этой редакции недоступно. `MSSQL_PID` с ключом включает платную редакцию, и точка входа выставляет `telemetry.customerfeedback=false`.

При каждом старте образ подключает базу из списка, если её ещё нет, заново ставит оба пароля и создаёт два задания Agent, если их ещё нет в `msdb`. Уровень совместимости файлов не меняется.

Порт 1433 наружу есть. Публичный домен на `mssql` не вешать.

### Оффлайн-лицензия

Файл обязателен. `GetMyLicense` читает только его и в xlab-license не ходит. Две строки приходят с кнопки на лицензии организации, у тарифа которой включён свой сервер. Каждое нажатие выпускает новый ключ установки и новый файл; старый файл перестаёт подходить. Логин и пароль суперадмина в файл не входят.

| Имя | Обязательно | Смысл |
|---|---|---|
| `XLabApiSettings__OfflineLicense__PrivateKey` | да | закрытый ключ установки, одна строка base64 |
| `XLabApiSettings__OfflineLicense__Document` | да | файл лицензии, одна строка base64 |
| `XLabApiSettings__OfflineLicense__AdminLogin` | да | логин суперадмина |
| `XLabApiSettings__OfflineLicense__AdminPassword` | да | пароль суперадмина |

При старте API проверяет подпись и расшифровку. Пустой логин, пустой пароль или битый файл не дают процессу подняться. В рабочей базе остаётся организация из файла: остальные организации и их сотрудники удаляются. Образцы и работы чужих организаций не стираются; если на них ещё есть ссылки, старт останавливается. Суперадмина создают, если его нет, и обновляют логин с паролем, если он уже есть. Пароль лежит только в `Org_Staff`. Сотрудники и их пароли в xlab-license не отправляются. Вход по паролю проверяет эта же таблица. Диск самохостинга не измеряется и не делает лицензию недействительной.

### Сайт LIMS

Страница входа — логин и пароль. Браузер считает SHA-256 и отправляет password flow на `API_PUBLIC_URL`. Compose сам ставит признак своего входа и этот адрес; в `.env` их писать не нужно.

Адрес хаба compose собирает сам: `{SIGNALR_PUBLIC_URL}/messageHub`.

Сброс пароля через xlab-auth здесь не используется. Пароль сотрудника меняется в карточке и хранится в `Org_Staff`.

### Почта через SendService

Compose уже задаёт темы Kafka. Имена совпадают с темами API:

| Тема API | Тема SendService | Куда |
|---|---|---|
| `xlab-client-commands` | та же | `SIGNALR_PUBLIC_URL/api/ClientCommands` |
| `xlab-signalr-notifications` | та же | `SIGNALR_PUBLIC_URL/api/messages` |
| `email` | `email` | SMTP ниже |
| — | `signalr` | тот же `…/api/messages` |

Адреса SignalR, ключ `API-Key` и адрес API compose подставляет сам. В `.env` для доставки остаётся почта.

| Имя | Обязательно | По умолчанию | Смысл |
|---|---|---|---|
| `SMTP_HOST` | для писем | пусто | сервер SMTP |
| `SMTP_PORT` | нет | `587` | порт |
| `SMTP_PROTOCOL` | нет | `TLS` | `TLS` или `SSL` |
| `SMTP_USER` | для писем | пусто | логин |
| `SMTP_PASSWORD` | для писем | пусто | пароль |

Группа потребителя Kafka зафиксирована: `xlab-selfhosted`. Второй потребитель с той же группой на этом брокере заберёт часть сообщений.

Журналы и настройки, которые этот стенд может не использовать:

| Имя | Смысл |
|---|---|
| `XLabApiSettings__Logging__MinimumLevel` | `Information`, если не задано |
| `XLabApiSettings__Logging__LogstashUrl` | приёмник журнала |
| `XLabApiSettings__Logging__ElasticsearchUrl` | приёмник журнала |
| `XLabApiSettings__Logging__ElasticsearchApiKey` | ключ Elasticsearch |
| `XLabApiSettings__Security__AccessTokenLifetimeHours` | срок токена рабочего места, часы |
| `XLabApiSettings__Security__RefreshTokenLifetimeDays` | срок refresh, дни |
| `XLabApiSettings__Security__MinimumTokenLifespanHours` | нижняя граница срока |
| `XLabApiSettings__Security__StaffLockoutMaxFailedAttempts` | попытки пароля до блокировки |
| `XLabApiSettings__Security__StaffLockoutBlockDurationMinutes` | длительность блокировки, минуты |

Список дополнительных источников CORS API: `XLabApiSettings__Security__AllowedOrigins__1`, `__2` и далее. Индекс `__0` compose занимает значением `WEB_PUBLIC_URL`.

Второй источник SignalR: `Cors__Origins__1`. Индекс `__0` занят тем же `WEB_PUBLIC_URL`.

### Что compose задаёт сам

Повтор тех же имён в `.env` не меняет контейнер.

| Сервис | Имя | Значение |
|---|---|---|
| `api` | `XLabApiSettings__Database__RedisConnection` | `redis:6379` |
| `api` | `XLabApiSettings__Kafka__BootstrapServers` | `broker:9092` |
| `api` | `XLabApiSettings__Kafka__Enabled` | `true` |
| `api` | темы Kafka | `xlab-client-commands`, `xlab-signalr-notifications`, `email` |
| `api` | `XLabApiSettings__OfflineLicense__*` | четыре строки из `.env`; без них `api` не стартует |
| `api` | `XLabApiSettings__LicenseService__BaseUrl`, HMAC, секрет клиента | пусто. Значение из `.env` не используется |
| `api` | `XLabApiSettings__XlabAuth__BaseUrl` | `XLAB_AUTH_URL` |
| `api` | `XLabApiSettings__Security__AllowedOrigins__0` | `WEB_PUBLIC_URL` |
| `api` | две строки подключения | `mssql,1433`, пользователь `xlab`, базы из `MSSQL_DATABASES` |
| `signalr` | `JwtSettings__Issuer` | `API_PUBLIC_URL` со слэшем на конце |
| `signalr` | `JwtSettings__CertificatePath` | `/app/cert.pfx` |
| `signalr` | `XlabAuth__BaseUrl` | `XLAB_AUTH_URL` |
| `signalr` | `Cors__Origins__0` | `WEB_PUBLIC_URL` |
| `signalr` | `HTTPS_DOMAINS` | хост из `SIGNALR_PUBLIC_URL` |
| `sendservice` | `SendService__Kafka__BootstrapServers` | `broker:9092` |
| `sendservice` | `SendService__Api__ApiBaseUrl` | `API_PUBLIC_URL` |
| `web` | `XL_SELF_HOSTED` | `true` |
| `web` | `XL_API_URL`, `XL_MESSAGE_HUB_URL` | `API_PUBLIC_URL` и `{SIGNALR_PUBLIC_URL}/messageHub` |

Redis и Kafka наружу не публикуются. У SendService нет порта. Проверку живости HTTP для него не включать: слушать нечего. Журнал: том `send-logs`, файл `/logs/send-service.log`. Сообщения SignalR: том `signalr-data`, файл `/data/messages.db`.

## Прокси

Публичные имена вешаются на три сервиса.

| Сервис | Порт контейнера | Схема до контейнера |
|---|---|---|
| `api` | 8080 | HTTP. Сертификат только на прокси |
| `web` | 80 | HTTP. Прокси отдаёт файлы Angular сам не должен: POST на `index.html` отвечает 405 |
| `signalr` | 443 | HTTPS. Сертификат в контейнере самоподписанный |

Проверка живости: у `web` это `GET /health` с ответом 200. У `api` свой HTTP-порт 8080. У `signalr` образ проверяет TLS на `127.0.0.1:443`. У SendService HTTP-проверку не включать.

Для SignalR прокси должен идти на контейнер по HTTPS и не проверять самоподписанный сертификат. На приложении Coolify выключите **Readonly labels**, порт экспозиции поставьте `443` и допишите две метки. Имя службы — `https-0-` и UUID приложения, когда публичный адрес начинается с `https://`:

```text
traefik.http.services.https-0-<uuid>.loadbalancer.server.scheme=https
traefik.http.services.https-0-<uuid>.loadbalancer.serverstransport=https-insecure@file
```

Транспорт один на весь прокси (Proxy → Dynamic Configurations, файл `https-insecure.yaml`):

```yaml
http:
  serversTransports:
    https-insecure:
      insecureSkipVerify: true
```

Отдельные сети в этом файле не объявлены. Coolify сам подключает прокси к нужным сервисам.

Реестр образов — Artifactory (`XLAB_REGISTRY`). Учётная запись Docker на хосте должна иметь право тянуть `xlab-release`.

## Проверка

1. `api` слушает HTTP 8080 и дожидается healthy у Redis, Kafka и SQL Server.
2. Сайт открывается по `WEB_PUBLIC_URL` и показывает свой вход. После входа сессия живёт на `API_PUBLIC_URL`.
3. После входа запросы идут на `API_PUBLIC_URL`, а не на внутреннее имя `api`.
4. В консоли браузера нет отказа negotiate на `{SIGNALR_PUBLIC_URL}/messageHub`. Отказ 401 при пустом `XLAB_AUTH_URL` значит, что издатель токена не совпал с `API_PUBLIC_URL`.
5. `POST` на `{SIGNALR_PUBLIC_URL}/api/messages` с заголовком `API-Key: SIGNALR_API_KEY` отвечает 201.
6. В базе одна организация из файла лицензии. Суперадмин входит логином и паролем из `OfflineLicense`. Список сотрудников в xlab-license не уходит.
