"""Force CPU execution in Docker environment."""
import os

# Встановлюємо прапорець що CUDA недоступна
os.environ['CUDA_VISIBLE_DEVICES'] = ''

# Імпортуємо оригінальний sitecustomize
import sys
from pathlib import Path

original_file = Path(__file__).parent / 'sitecustomize.py'
if original_file.exists():
    with open(original_file) as f:
        exec(f.read())
