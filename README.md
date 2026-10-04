# xlab-selfhosted

Docker Compose для лаборатории, которая держит свой API. В одном файле собраны стек xlabcombine (API, Redis, Kafka, SendService, SQL Server), веб-LIMS и SignalR.

Биллинг и вход сотрудников здесь не запускаются. Их держат отдельные сервисы **xlab-license** и **xlab-auth**. Эта лаборатория получает ключи с карточки партнёра, у которой включён свой API.

Образы API, сайта, SignalR, SendService и SQL Server тянутся из реестра `XLAB_REGISTRY`. По умолчанию это `artifactory.x-lab.pro/xlab-release`, тег `latest`. Compose их не собирает.

| Сервис | Образ | Порт внутри сети | Кто снаружи |
|---|---|---|---|
| `api` | `xlabapi:latest` | HTTP 8080 | браузер, рабочее место, xlab-license, SendService |
| `web` | `xlablimsweb:latest` | HTTP 80 | браузер |
| `signalr` | `xlabsignalrservice:latest` | HTTPS 443 | браузер (`/messageHub`), SendService (`/api/messages`, `/api/ClientCommands`) |
| `redis` | `redis:7-alpine` | 6379 | только API |
| `broker` | `apache/kafka` | 9092 | API и SendService |
| `sendservice` | `xlabsendservice:latest` | нет | почта, Firebase, публичный адрес SignalR |
| `mssql` | `xlab-mssql:latest` | 1433, на хосте тоже 1433 | API |

В образах API и SignalR лежит один и тот же `cert.pfx`. Пароль один: `XLabApiSettings__Security__CertificatePassword`.

Сайт читает адрес входа, `client_id` и адрес хаба при старте контейнера и записывает их в `config/xl-env.js`. Смена этих значений — новый запуск контейнера, не новая сборка образа.

## Что остаётся снаружи

```text
браузер → web → xlab-auth (вход, PKCE)
браузер → api  (OData, адрес из JWT api_url)
браузер → signalr /messageHub (токен xlab-auth, ES256)
рабочее место → api и signalr (токен OpenIddict, сертификат)
api → xlab-license (HMAC, лицензия лаборатории)
xlab-license → api (синхронизация организаций и сотрудников, секрет клиента)
SendService → публичный HTTPS signalr
```

База биллинга — Postgres xlab-license. SQL Server эту базу не хранит.

## Карточка партнёра в xlab-license

На карточке, которая обслуживает эту установку:

| Поле карточки | Значение |
|---|---|
| Свой API (`HostsOwnApi`) | включён |
| Адрес API (`ApiBaseUrl`) | `API_PUBLIC_URL` |
| Сайт LIMS (`LimsWebUrl`) | `WEB_PUBLIC_URL`, символ в символ, без слэша в конце |
| `OauthClientId` | публичный идентификатор. Его же писать в `XL_OAUTH_CLIENT_ID`. Это не AppGuid |

Кнопка подготовки файла окружения есть только у своего API и у карточки вендора. Она заново выпускает HMAC, ключ записи в xlab-auth, секрет клиента API и ключ подписи, затем отдаёт строки для этого API. Предыдущие ключи после этого перестают подходить: новый файл нужно положить в `.env` и перезапустить `api`.

В файл попадают шесть строк. Четыре копируются в `.env` как есть:

```text
XLabApiSettings__Security__LicenseServiceClientSecret=...
XLabApiSettings__LicenseService__BaseUrl=https://license.example.com
XLabApiSettings__LicenseService__HmacKey=...
XLabApiSettings__LicenseService__HmacKeyPrevious=
```

`XLabApiSettings__XlabAuth__BaseUrl` из того файла в контейнер API не попадает: compose ставит `XLAB_AUTH_URL`. Эти два адреса должны совпадать, без слэша в конце. `XLabApiSettings__XlabAuth__InternalKey` compose не подставляет. Если строка есть в подготовленном файле, допишите её в `.env` тем же именем. Пустое значение отключает запись организаций и сотрудников со стороны API.

`SigningPrivateKey` и `OauthClientId` в этот `.env` не кладутся. Приватный ключ остаётся в xlab-license. `OauthClientId` — это `XL_OAUTH_CLIENT_ID`.

На уже работающем xlab-license:

| Параметр сервиса лицензий | Зачем этой установке |
|---|---|
| `XLAB_AUTH_URL` | тот же адрес, что `XLAB_AUTH_URL` здесь. Из него карточка собирает строку `XLabApiSettings__XlabAuth__BaseUrl` |
| `XLAB_API_URL` | запасной адрес API, когда у карточки вендора пустой `ApiBaseUrl`. Адрес этой лаборатории берётся с её карточки |
| `XLAB_API_URL_OVERRIDE` | оставьте пустым. Непустое значение подменяет адрес карточки вендора при исходящих вызовах |
| `CORS_ORIGINS` | сайт LIMS туда не нужен: браузер биллинг не вызывает |
| `LICENSE_OPS_JWT_SECRET`, `VENDOR_OPS_*`, `DATABASE_URL`, SMTP пробного доступа | остаются на хосте биллинга. В этот compose они не входят |

Сайт показывает свою страницу входа. Логин и пароль уходят на `API_PUBLIC_URL` и сверяются с `Org_Staff`. Адрес xlab-auth для этого входа не нужен: оставьте `XLAB_AUTH_URL` пустым.

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
| `API_PUBLIC_URL` | да | | SendService ходит на API по этому адресу. SignalR сверяет издателя токена рабочего места с этим адресом и слэшем на конце (`https://api.example.com/`). Карточка: `ApiBaseUrl` |
| `WEB_PUBLIC_URL` | да | | CORS API и SignalR. Карточка: `LimsWebUrl`. Источник браузера, без пути и без слэша |
| `SIGNALR_PUBLIC_URL` | да | | SendService вызывает `…/api/messages` и `…/api/ClientCommands`. Сайт пишет в конфиг `…/messageHub` |
| `SIGNALR_PUBLIC_HOST` | да | | только имя хоста, первая запись в сертификате HTTPS контейнера SignalR. Совпадает с хостом в `SIGNALR_PUBLIC_URL` |
| `XLAB_AUTH_URL` | нет | пусто | Если пусто, сайт входит сам, API проверяет `Org_Staff`, SignalR принимает токен API. Непустой адрес включает проверку токена ES256 на SignalR |
| `XL_OAUTH_CLIENT_ID` | нет | пусто | Сайт своего сервера его не читает |

SendService ходит на **публичный** адрес SignalR. Внутреннее имя `signalr` в сертификат тоже попадает, но сертификат самоподписанный, а SendService проверяет TLS. Публичный прокси должен предъявлять настоящий сертификат.

### Ключи этой установки

| Имя | Обязательно | По умолчанию | Куда попадает |
|---|---|---|---|
| `SIGNALR_API_KEY` | да | | SignalR `Security__ApiKey`. SendService шлёт его заголовком `API-Key` на три темы SignalR. Свой секрет, не ключ из чужого стенда |
| `XLabApiSettings__Security__CertificatePassword` | да | | пароль `cert.pfx` в API и в SignalR. Оба образа отказываются стартовать без него |
| `XLabApiSettings__Security__SystemApiKey` | да | | API проверяет заголовок системного ключа. SendService кладёт сюда то же значение в `SendService__Api__SystemApiKey`. Отдельный секрет от `SIGNALR_API_KEY` |

Сгенерировать ключ:

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
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

### Строки с карточки xlab-license

Их приносит подготовка файла на карточке. Compose их не выдумывает.

| Имя | Обязательно | По умолчанию | Смысл |
|---|---|---|---|
| `XLabApiSettings__Security__LicenseServiceClientSecret` | да | | секрет клиента OpenIddict, которым xlab-license ходит на этот API. Хранится на карточке своего API |
| `XLabApiSettings__LicenseService__BaseUrl` | да | | публичный адрес xlab-license, без требования слэша на конце |
| `XLabApiSettings__LicenseService__HmacKey` | да | | HMAC этой карточки. Тот же секрет, которым сервис лицензий подписывает ответ |
| `XLabApiSettings__LicenseService__HmacKeyPrevious` | да, может быть пустым | пусто | предыдущий HMAC на время смены ключа. Свежая подготовка оставляет пустым |
| `XLabApiSettings__XlabAuth__InternalKey` | когда API должен писать сотрудников в xlab-auth | | ключ заголовка записи. Та же строка, что на карточке. Compose её не затирает |

Пустой HMAC или пустой `BaseUrl` делают лицензию недействительной, если файл оффлайн-лицензии не задан: живой запрос не проходит проверку.

### Оффлайн-лицензия

Если задан файл лицензии, `GetMyLicense` не ходит в xlab-license. Две строки приходят с кнопки на лицензии организации, у тарифа которой включён свой сервер. Каждое нажатие выпускает новый ключ установки и новый файл; старый файл перестаёт подходить. Логин и пароль суперадмина в файл не входят.

| Имя | Обязательно | Смысл |
|---|---|---|
| `XLabApiSettings__OfflineLicense__PrivateKey` | вместе с файлом | закрытый ключ установки, одна строка base64 |
| `XLabApiSettings__OfflineLicense__Document` | вместе с ключом | файл лицензии, одна строка base64 |
| `XLabApiSettings__OfflineLicense__AdminLogin` | вместе с файлом | логин суперадмина |
| `XLabApiSettings__OfflineLicense__AdminPassword` | вместе с файлом | пароль суперадмина |

При старте API проверяет подпись и расшифровку. Пустой логин, пустой пароль или битый файл не дают процессу подняться. В рабочей базе остаётся организация из файла: остальные организации и их сотрудники удаляются. Образцы и работы чужих организаций не стираются; если на них ещё есть ссылки, старт останавливается. Суперадмина создают, если его нет, и обновляют логин с паролем, если он уже есть. Пароль лежит только в `Org_Staff`. Сотрудники и их пароли в xlab-license не отправляются. Вход по паролю проверяет эта же таблица. Диск самохостинга не измеряется и не делает лицензию недействительной.

### Сайт LIMS

Пишется в `config/xl-env.js` при старте. Пустое значение выключает возможность. После правки достаточно перезапустить контейнер `web`.

| Имя | Обязательно | По умолчанию | Смысл |
|---|---|---|---|
| `XL_RECAPTCHA_SITE_KEY` | нет | пусто | публичный ключ reCAPTCHA v3. Виджет входа рисует xlab-auth; ключ сайта нужен, только если виджет на этой странице |
| `XL_GTM_ID` | нет | пусто | контейнер Google Tag Manager, вид `GTM-XXXX`. Иное значение скрипт не вставляет |
| `XL_DIAGNOSTICS` | нет | пусто | `true` включает `diag()` в консоли браузера |

Адрес хаба compose собирает сам: `{SIGNALR_PUBLIC_URL}/messageHub`.

Процесс внутри образа (заявки разработчикам). Браузер эти значения не видит.

| Имя | Обязательно | По умолчанию | Смысл |
|---|---|---|---|
| `RECAPTCHA_SECRET_KEY` | нет | пусто | секрет того же сайта reCAPTCHA. Действие проверки: `write_developers` |
| `RECAPTCHA_ENABLED` | нет | `false` | `true` только вместе с ключом сайта |
| `RECAPTCHA_MIN_SCORE` | нет | `0.5` | порог оценки |
| `KANEO_BASE_URL` | нет | пусто | корень API Kaneo, обычно `https://хост/api` |
| `KANEO_API_KEY` | нет | пусто | токен Kaneo |
| `KANEO_PROJECT_ID` | нет | пусто | проект Kaneo |
| `KANEO_STATUS_SLUG` | нет | `backlog` | ярлык колонки, не заголовок на доске |
| `UPLOAD_TOKEN_SECRET` | нет | пусто | подпись короткого пропуска на загрузку файла. Пустое значение оставляет встроенный секрет разработки. Для рабочей установки сгенерируйте свой |

Почта входа и сброса пароля настраивается на xlab-auth (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USE_SSL`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`, `SMTP_FROM_NAME`). Это не переменные данного файла.

### Почта и push через SendService

Compose уже задаёт темы Kafka. Имена совпадают с темами API:

| Тема API | Тема SendService | Куда |
|---|---|---|
| `xlab-client-commands` | та же | `SIGNALR_PUBLIC_URL/api/ClientCommands` |
| `xlab-signalr-notifications` | та же | `SIGNALR_PUBLIC_URL/api/messages` |
| `email` | `email` | SMTP ниже |
| — | `signalr` | тот же `…/api/messages` |
| — | `push` | Firebase |

Адреса SignalR, ключ `API-Key` и адрес API compose подставляет сам. В `.env` для доставки остаются почта и JSON Firebase.

| Имя | Обязательно | По умолчанию | Смысл |
|---|---|---|---|
| `SMTP_HOST` | для писем | пусто | сервер SMTP |
| `SMTP_PORT` | нет | `587` | порт |
| `SMTP_PROTOCOL` | нет | `TLS` | `TLS` или `SSL` |
| `SMTP_USER` | для писем | пусто | логин |
| `SMTP_PASSWORD` | для писем | пусто | пароль |
| `SendService__Kafka__Topics__0__ProviderSettings__ServiceAccountJson` | для push | пусто | JSON сервисного аккаунта Google одной строкой |

Группа потребителя Kafka зафиксирована: `xlab-selfhosted`. Второй потребитель с той же группой на этом брокере заберёт часть сообщений.

Письма сброса пароля рабочего места, если они ещё идут через API, задаются отдельно:

| Имя | По умолчанию в коде, если переменной нет |
|---|---|
| `XLabApiSettings__Security__Smtp__Host` | пусто, пока не задано |
| `XLabApiSettings__Security__Smtp__Port` | `587` в примере Coolify API |
| `XLabApiSettings__Security__Smtp__UseSsl` | `true` |
| `XLabApiSettings__Security__Smtp__UserName` | |
| `XLabApiSettings__Security__Smtp__Password` | |
| `XLabApiSettings__Security__Smtp__FromEmail` | |
| `XLabApiSettings__Security__Smtp__FromName` | `X-Lab Support` |
| `XLabApiSettings__Security__PasswordResetBaseUrl` | `https://account.x-labsystems.io` |
| `XLabApiSettings__Security__ExamPortalBaseUrl` | `https://exam.x-labsystems.io` |

Журналы и интеграции, которые этот стенд может не использовать:

| Имя | Смысл |
|---|---|
| `XLabApiSettings__Logging__MinimumLevel` | `Information`, если не задано |
| `XLabApiSettings__Logging__LogstashUrl` | приёмник журнала |
| `XLabApiSettings__Logging__ElasticsearchUrl` | приёмник журнала |
| `XLabApiSettings__Logging__ElasticsearchApiKey` | ключ Elasticsearch |
| `XLabApiSettings__ExternalServices__N8N__Url` | адрес n8n |
| `XLabApiSettings__ExternalServices__N8N__ApiKey` | ключ n8n |
| `XLabApiSettings__Security__EnableSwagger` | `true` открывает `/swagger`. Для рабочей установки оставьте выключенным |
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
| `api` | `XLabApiSettings__XlabAuth__BaseUrl` | `XLAB_AUTH_URL` |
| `api` | `XLabApiSettings__Security__AllowedOrigins__0` | `WEB_PUBLIC_URL` |
| `api` | две строки подключения | `mssql,1433`, пользователь `xlab`, базы из `MSSQL_DATABASES` |
| `signalr` | `JwtSettings__Issuer` | `API_PUBLIC_URL` со слэшем на конце |
| `signalr` | `JwtSettings__CertificatePath` | `/app/cert.pfx` |
| `signalr` | `XlabAuth__BaseUrl` | `XLAB_AUTH_URL` |
| `signalr` | `Cors__Origins__0` | `WEB_PUBLIC_URL` |
| `signalr` | `HTTPS_DOMAINS` | `SIGNALR_PUBLIC_HOST` |
| `sendservice` | `SendService__Kafka__BootstrapServers` | `broker:9092` |
| `sendservice` | `SendService__Api__ApiBaseUrl` | `API_PUBLIC_URL` |
| `web` | `XL_AUTH_URL`, `XL_MESSAGE_HUB_URL` | `XLAB_AUTH_URL` и `{SIGNALR_PUBLIC_URL}/messageHub` |

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
6. Карточка xlab-license с этим `ApiBaseUrl` синхронизирует организацию. Пустой HMAC или другой секрет клиента даёт отказ.
