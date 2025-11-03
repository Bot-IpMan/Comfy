# ComfyUI + RIFE через Docker Compose

Цей репозиторій містить налаштування `docker-compose.yml` для швидкого запуску [ComfyUI](https://github.com/comfyanonymous/ComfyUI) з підтримкою NVIDIA GPU та додаткового контейнера з RIFE (інтерполяція відео). Конфігурація оптимізована під відеокарту **NVIDIA GeForce GTX 1050 Ti (4 GB)**, але підійде і для інших моделей за умови коректних налаштувань драйверів та CUDA.

## Попередні вимоги

1. **Операційна система** з підтримкою Docker (Linux, Windows WSL2 або macOS з Docker Desktop).
2. **Docker Engine** 20.10+ та **Docker Compose** (плагін `docker compose`).
3. **NVIDIA драйвери** та **NVIDIA Container Toolkit** для доступу до GPU всередині контейнера.
   - Перевірити видимість GPU для Docker: `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi`.
4. Достатньо місця на диску: моделі ComfyUI можуть займати десятки гігабайт.

## Швидкий старт

1. Скопіюйте файл змінних середовища та, за потреби, відредагуйте значення:
   ```bash
   cp .env.example .env
   ```
2. Запустіть локальну збірку та контейнер ComfyUI (перше виконання може тривати декілька
   хвилин, доки збирається образ та завантажуються залежності PyTorch):
   ```bash
   docker compose up -d
   ```
3. За бажанням додайте RIFE, увімкнувши профіль `rife`:
   ```bash
   docker compose --profile rife up -d
   ```
4. Веб-інтерфейс стане доступним на [http://localhost:8188](http://localhost:8188).

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

1. Скопіюйте `.env.example` у `.env` та, за потреби, відкоригуйте змінні:
   ```bash
   cp .env.example .env
   ```
   - `COMFYUI_IMAGE` — локальний тег для зібраного образу.
   - `COMFYUI_REPO` та `COMFYUI_REF` — звідки та яку гілку/тег/коміт клонувати під час збірки Dockerfile.
   - `TORCH_INDEX_URL` — індекс коліс PyTorch (наприклад, `https://download.pytorch.org/whl/cu121`).

2. Якщо плануєте використовувати образи з GitHub Container Registry (наприклад, увімкнути сервіс RIFE або підставити власний `COMFYUI_IMAGE` з GHCR), авторизуйтеся:
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

Команда запускає тільки ComfyUI. Щоб додати RIFE, активуйте профіль `rife`:

```bash
docker compose --profile rife up -d
```

Після успішного запуску веб-інтерфейс буде доступний за адресою: [http://localhost:8188](http://localhost:8188).

## Типова проблема: `denied` при завантаженні образу з GHCR

Завдяки локальній збірці ComfyUI ця помилка більше не виникає для основного сервісу, але її все ще можна побачити під час завантаження образів з GitHub Container Registry (наприклад, сервісу RIFE або стороннього `COMFYUI_IMAGE`). Приклад повідомлення:

```
Error response from daemon: Head "https://ghcr.io/v2/comfyanonymous/comfyui/manifests/latest": denied
```

Це означає, що Docker не може завантажити образ з GHCR. Можливі причини та способи вирішення:

1. **Неавторизований доступ до GHCR**. Більшість організацій вимагають токен навіть для публічних образів.
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

- **Вимкніть залежні сервіси**. Не активуйте профіль `rife`, якщо немає можливості автентифікуватися в GHCR.
- **Вкажіть інше джерело образу.** Можна знайти альтернативні збірки на Docker Hub чи в інших реєстрах і замінити `RIFE_IMAGE` або `COMFYUI_IMAGE` у `.env`.

## Помилка `no-cgroups вимкнено` в діагностиці GPU

Якщо при виконанні діагностичних скриптів бачите повідомлення `ERROR: no-cgroups вимкнено`, це означає, що NVIDIA Container Runtime
запускається без підтримки cgroups. Через це Docker не може коректно застосовувати ліміти до GPU-пристроїв усередині контейнерів, а
деякі утиліти (`nvidia-smi`, PyTorch) можуть працювати нестабільно.

Типові симптоми на хості з вимкненими cgroups:

```text
comfyui  | /opt/ComfyUI/venv/lib/python3.10/site-packages/torch/cuda/__init__.py:129: UserWarning: CUDA initialization: Unexpected error from cudaGetDeviceCount()... Error 304: OS call failed or operation not supported on this OS
comfyui  | Device: cpu
comfyui  | PermissionError: [Errno 13] Permission denied
```

PyTorch у такому випадку бачить лише CPU, а подальше створення asyncio-петлі може падати з `PermissionError: socketpair`, якщо контейнер працює з дефолтним seccomp-профілем.

Щоб виправити ситуацію:

1. Відкрийте файл `/etc/nvidia-container-runtime/config.toml` на хості та знайдіть параметр `no-cgroups`.
2. Змініть значення на `true`:
   ```toml
   no-cgroups = true
   ```
3. Перезапустіть Docker, щоб застосувати зміни:
   ```bash
   sudo systemctl restart docker
   ```
4. У типовій `docker-compose.yml` цього репозиторію сервіс `comfyui` вже запускається з `privileged: true`, `security_opt: ["seccomp=unconfined"]`
   та додатковими capabilities (`IPC_LOCK`, `SYS_NICE`). Це забезпечує коректну роботу на хостах Proxmox/LXC і прибирає `PermissionError`
   під час створення `socketpair`. Якщо ви запускаєте на звичайному Docker Engine без LXC, ці параметри можна прибрати для більш
   строгого режиму безпеки.

Після перезавантаження сервісу і (за потреби) оновлення Compose-конфігурації повторіть діагностику — попередження зникне, а GPU буде коректно доступним у контейнерах. Повідомлення виду `Skipping cache drop: /proc/sys/vm/drop_caches is not writable` можна ігнорувати: воно лише означає, що хост не дозволяє скидати сторінковий кеш із контейнера.

## Антикризовий план для Pascal (GTX 1050 Ti, 4 ГБ)

> **TL;DR:** Перезберіть образ із PyTorch 2.3.1, запустіть ComfyUI з агресивними прапорами економії памʼяті та слідкуйте за VRAM у реальному часі.

### Крок 1. Перезібрати образ з PyTorch 2.3.1

1. Оновіть `.env` до останньої версії (`cp .env.example .env`), або вручну переконайтесь, що у файлі є `TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121`.
2. Перезберіть образ, щоб отримати PyTorch 2.3.1+cu121 та відповідні версії torchvision/torchaudio:
   ```bash
   docker compose build --no-cache comfyui
   ```
3. Після збірки перевірте версії всередині контейнера:
   ```bash
   docker compose run --rm comfyui python -c "import torch, torchvision, torchaudio; print(torch.__version__, torchvision.__version__, torchaudio.__version__)"
   ```

> **Чому саме 2.3.1?** Ця гілка стабільніше працює з Pascal (SM 6.x) та cudaMalloc-аллокатором. Якщо вам потрібна збірка `+cu124`, змініть `TORCH_INDEX_URL` та версії у Dockerfile на доступні в обраному індексі (див. коментарі в Dockerfile).

### Крок 2. Актуальні прапори запуску

`docker-compose.yml` та `.env.example` встановлюють агресивний набір опцій за замовчуванням:

- `CLI_ARGS="--listen --port 8188 --lowvram --disable-smart-memory --preview-method none"` — вимикає попередній перегляд (звільняє VRAM), змушує ComfyUI тримати лише поточну модель у памʼяті та забороняє smart-memory, що інтенсивно використовує VRAM.
- `PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128` — змушує аллокатор ділити великі блоки памʼяті на дрібні, що зменшує фрагментацію та допомагає уникати `cudaMalloc` OOM.
- `shm_size: 8gb` — збільшує спільну памʼять у контейнері, щоб уникнути помилок під час великих графів VAE.

Разом із цим `scripts/docker-entrypoint.sh` продовжує автоматично підміняти аллокатор на `cudaMalloc`, якщо GPU має compute capability < 7.0.

### Крок 3. Правила побудови workflow

- Ставте **UnloadModel** після кожного великого кроку (наприклад, після рендера основного зображення перед апскейлом або Inpaint).
- Тримайте роздільну здатність **не вище 512×512** для базових чекпоінтів SD 1.5. Для апскейлу використовуйте окремий прохід із меншим batch.
- Обирайте **pruned FP16** моделі (`sd15-pruned-emaonly-fp16.safetensors`, `dreamshaper_8_pruned.safetensors`). Вони займають ~2.1–2.4 ГБ проти 3–4 ГБ у повних FP32 моделей.
- Якщо потрібна швидка генерація, розгляньте **LCM-LoRA** або інші light-weight LoRA/Checkpoint комбінації.

У каталозі `comfyui/workflows/` додано `low_vram_test_pascal.json` — це мінімальний workflow для перевірки, що нові налаштування не падають у OOM.

### Крок 4. Моніторинг VRAM та очищення кешу

Запустіть фоновий монітор перед довгими сесіями:

```bash
docker compose run --rm --service-ports \
  -e CUDA_VISIBLE_DEVICES=0 \
  comfyui python scripts/vram_monitor.py --threshold-mb 3400 --interval 2
```

Скрипт виконує `nvidia-smi` з інтервалом у 2 секунди та викликає `torch.cuda.empty_cache()` щойно вільної памʼяті менше за поріг. Параметри `--threshold-mb` і `--interval` можна змінювати.

Якщо потрібно просто подивитися на цифри без очищення, використайте `nvidia-smi -l 1` у окремому вікні або вимкніть автоочищення через `--no-empty-cache`.

### Крок 5. Альтернативні сценарії

- **Нативний запуск без Docker.** Встановіть системний Python 3.10+, PyTorch 2.3.1 (`pip install torch==2.3.1+cu121 --index-url ...`) та запустіть `python main.py --lowvram --disable-smart-memory --preview-method none`. На Debian 13 доведеться вручну встановити CUDA/cuDNN бібліотеки або скористатись `pip install nvidia-cudnn-cu12`.
- **Легші моделі.** Для ескізів та швидких ітерацій використовуйте LCM-LoRA (`LCM_LoRA_SDXL.safetensors`) або навіть `stable-diffusion-1.5-inpainting` у поєднанні з ControlNet Tile.

### Крок 6. Фінальний тест

1. Запустіть контейнер: `docker compose up -d`.
2. Імпортуйте `comfyui/workflows/low_vram_test_pascal.json` у ComfyUI (`Load > Load Workflow`).
3. Переконайтесь, що активні вузли `UnloadModel` після основного чекпоінта.
4. Натисніть **Queue Prompt**. Якщо зʼявився результат у `comfyui/output`, конфігурація працює без крашів.

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

Для швидкої перевірки завантаження GPU всередині контейнера скористайтесь:

```bash
docker exec -it comfyui nvidia-smi
```

Для довгих сесій з Pascal-картами краще запускати `python scripts/vram_monitor.py`, який є частиною цього репозиторію (див. розділ [Антикризовий план для Pascal](#антикризовий-план-для-pascal-gtx-1050-ti-4-гб)).

## Поширені питання

- **Чи потрібно копіювати Dockerfile до папки `comfyui/`?** Ні, для запуску через `docker compose` достатньо базового образу, який уже вказаний у `docker-compose.yml`. Каталог `comfyui/` у цьому репозиторії використовується лише як точка монтування томів (моделі, вхідні/вихідні дані тощо). Якщо ж хочете зібрати власний образ із локального коду, додайте свій `Dockerfile` у потрібне місце та змініть налаштування Compose (наприклад, через `build:` або зміну `COMFYUI_IMAGE`).
- **Як додати нові моделі?** Скопіюйте їх у відповідні підкаталоги `comfyui/models`.
- **Де зберігаються workflow?** У каталозі `comfyui/user/default/`.
- **Як оновити ComfyUI до nightly?** Змініть тег образу на потрібний (`ghcr.io/comfyanonymous/comfyui:cu118` тощо) та виконайте `docker compose pull`.

## Корисні посилання

- [ComfyUI Wiki](https://comfyanonymous.github.io/ComfyUI_doc/)
- [Документація NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/)
- [GitHub Container Registry – аутентифікація](https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

Успішної творчості з ComfyUI! Якщо виникають питання — перевірте логи `docker compose logs -f comfyui` або зверніться до спільноти ComfyUI в Discord/Reddit.
