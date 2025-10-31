# ComfyUI + RIFE через Docker Compose

Цей репозиторій містить налаштування `docker-compose.yml` для швидкого запуску [ComfyUI](https://github.com/comfyanonymous/ComfyUI) з підтримкою NVIDIA GPU та додаткового контейнера з RIFE (інтерполяція відео). Конфігурація оптимізована під відеокарту **NVIDIA GeForce GTX 1050 Ti (4 GB)**, але підійде і для інших моделей за умови коректних налаштувань драйверів та CUDA.

## Попередні вимоги

1. **Операційна система** з підтримкою Docker (Linux, Windows WSL2 або macOS з Docker Desktop).
2. **Docker Engine** 20.10+ та **Docker Compose** (плагін `docker compose`).
3. **NVIDIA драйвери** та **NVIDIA Container Toolkit** для доступу до GPU всередині контейнера.
   - Перевірити видимість GPU для Docker: `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi`.
4. Достатньо місця на диску: моделі ComfyUI можуть займати десятки гігабайт.

## Швидкий старт (із логіном до GHCR)

1. Згенеруйте на GitHub персональний токен з правами **`read:packages`**.
2. Скопіюйте файл змінних середовища та, за потреби, відредагуйте образи:
   ```bash
   cp .env.example .env
   ```
3. (Опціонально) Якщо хочете використовувати офіційний образ з GHCR, змініть змінну
   `COMFYUI_IMAGE` в `.env` та авторизуйтеся, щоб уникнути помилки `denied` при
   завантаженні образу:
   ```bash
   ./scripts/login-ghcr.sh
   ```
   Скрипт попросить GitHub username і токен (вставляйте токен у прихованому режимі).
4. Запустіть сервіси (ComfyUI та RIFE стартують разом):
   ```bash
   docker compose up -d
   ```
   Якщо потрібен лише ComfyUI без RIFE, вкажіть імʼя сервісу: `docker compose up -d comfyui`.
5. Веб-інтерфейс стане доступним на [http://localhost:8188](http://localhost:8188).

## Структура каталогів

```
comfyui/
  models/        # моделі (checkpoints, VAE, LoRA, embeddings)
  input/         # завантаження вхідних зображень / відео
  output/        # результати з ComfyUI
  custom_nodes/  # додаткові кастомні ноди
  user/          # користувацькі налаштування, workflow'и та кеш
rife/
  output/        # результати роботи RIFE
```

Каталоги створюються автоматично під час першого запуску, але їх можна підготувати заздалегідь.

## Початкова конфігурація

1. Скопіюйте файл змінних середовища та за потреби змініть образи контейнерів:
   ```bash
   cp .env.example .env
   # Відредагуйте .env, щоб обрати потрібні образи або додати власні
   ```
   За замовчуванням використовується публічний образ `lscr.io/linuxserver/comfyui:latest`, який не потребує авторизації. Якщо бажаєте перейти на офіційний образ з GHCR (`ghcr.io/comfyanonymous/comfyui:latest`), змініть значення змінної `COMFYUI_IMAGE` та виконайте авторизацію через `./scripts/login-ghcr.sh`.

2. Якщо потрібен доступ до приватних або обмежених образів на GHCR чи якщо публічний образ вимагає авторизації, виконайте логін:
   ```bash
   GHCR_USERNAME=<your_github_username> \
   GHCR_TOKEN=<pat_with_read_packages> \
   ./scripts/login-ghcr.sh
   ```
   Скрипт можна запустити і без попереднього експорту змінних — він запитає дані інтерактивно.

## Запуск

```bash
docker compose up -d
```

Команда запускає ComfyUI та RIFE. Якщо хочете стартувати тільки ComfyUI, використайте
`docker compose up -d comfyui`.

Після успішного запуску веб-інтерфейс буде доступний за адресою: [http://localhost:8188](http://localhost:8188).

## Типова проблема: `denied` при завантаженні образу з GHCR

При запуску може з'являтися помилка на кшталт:

```
Error response from daemon: Head "https://ghcr.io/v2/comfyanonymous/comfyui/manifests/latest": denied
```

Це означає, що Docker не може завантажити образ з GitHub Container Registry (GHCR). Можливі причини та способи вирішення:

1. **Неавторизований доступ до GHCR**. Деякі образи вимагають авторизації навіть для публічних репозиторіїв.
   - Згенеруйте на GitHub токен з правами `read:packages`.
   - Запустіть `./scripts/login-ghcr.sh` (або вручну `echo <TOKEN> | docker login ghcr.io -u <USERNAME> --password-stdin`).
   - Після авторизації повторіть `docker compose pull` або `docker compose up -d`.
2. **Тимчасові збої GHCR або блокування мережі**.
   - Перевірте доступність: `curl -I https://ghcr.io/v2/`.
   - Спробуйте повторити завантаження пізніше або використайте VPN.
3. **Проксі/фаєрвол** блокує HTTPS-запити до GitHub.
   - Налаштуйте проксі в Docker (`/etc/systemd/system/docker.service.d/http-proxy.conf`) або додайте виключення у фаєрволі.
4. **Застарілий Docker**. Оновіть Docker Engine та Compose до останніх версій.

### Альтернативи, якщо доступ до GHCR неможливий

- **Побудова образу локально**:
  ```bash
  git clone https://github.com/comfyanonymous/ComfyUI.git
  cd ComfyUI
  docker build -t comfyui:local .
  ```
  Після цього у `.env` змініть `COMFYUI_IMAGE` на `comfyui:local`.
- **Використання дзеркала**. Шукайте альтернативні образи на Docker Hub або в інших реєстрах (наприклад, `lscr.io/linuxserver/comfyui:latest`). Саме цей образ використовується за замовчуванням у `docker-compose.yml`, тому `docker compose up -d` більше не падає з помилкою `pull access denied`.

## Налаштування під GPU з 4 ГБ

Файл `docker-compose.yml` уже містить такі ключові параметри:

- `CLI_ARGS: --lowvram --disable-smart-memory --force-fp16` — режим низького споживання памʼяті та 16-бітні обчислення.
- `PYTORCH_CUDA_ALLOC_CONF: max_split_size_mb:64` — оптимізація аллокатора для обмеженої памʼяті.
- `shm_size: 2gb` та ulimits для запобігання крешам при великих графах.

При появі Out Of Memory:

- Зменште розмір пакетів (batch size) у workflow.
- Використовуйте менші за розміром моделі (наприклад, `pruned` чекпоінти або `fp16`).
- Відключіть превʼю (`--preview-method none`) у `CLI_ARGS`.

## Оновлення образів

```bash
docker compose pull
docker compose up -d
```

## Зупинка та видалення контейнерів

```bash
docker compose down
```

Для повного очищення (включно з томами):

```bash
docker compose down -v
```

## Моніторинг GPU

Для перевірки завантаження GPU всередині контейнера скористайтесь:

```bash
docker exec -it comfyui nvidia-smi
```

## Поширені питання

- **Чи потрібно копіювати Dockerfile до папки `comfyui/`?** Ні, для запуску через `docker compose` достатньо базового образу, який уже вказаний у `docker-compose.yml`. Каталог `comfyui/` у цьому репозиторії використовується лише як точка монтування томів (моделі, вхідні/вихідні дані тощо). Якщо ж хочете зібрати власний образ із локального коду, додайте свій `Dockerfile` у потрібне місце та змініть налаштування Compose (наприклад, через `build:` або зміну `COMFYUI_IMAGE`).
- **Як додати нові моделі?** Скопіюйте їх у відповідні підкаталоги `comfyui/models`.
- **Де зберігаються workflow?** У каталозі `comfyui/user/default/`.
- **Як оновити ComfyUI до nightly?** Змініть тег образу на потрібний (`ghcr.io/comfyanonymous/comfyui:cu121` тощо) та виконайте `docker compose pull`.

## Корисні посилання

- [ComfyUI Wiki](https://comfyanonymous.github.io/ComfyUI_doc/)
- [Документація NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/)
- [GitHub Container Registry – аутентифікація](https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

Успішної творчості з ComfyUI! Якщо виникають питання — перевірте логи `docker compose logs -f comfyui` або зверніться до спільноти ComfyUI в Discord/Reddit.
