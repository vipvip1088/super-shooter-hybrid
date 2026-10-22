# CLAUDE.md — SuperShooterHybrid

## Стек проекта

| Слой | Технология |
|------|-----------|
| Движок | Godot 4.2.2, Mobile renderer, Portrait 1080×1920 |
| Язык | GDScript (статическая типизация везде где возможно) |
| Тесты | Python 3 (unittest, без зависимостей) |
| CI/CD | GitHub Actions → Android APK (без Gradle, prebuilt template) |
| Сеть | Godot ENet (спроектирован, не активен — 3 канала: reliable/unreliable/sequenced) |
| Экспорт | `export_presets.cfg`: `use_gradle_build=false`, arm64-v8a |

## Как запускать и проверять в Termux

```bash
# Запуск всех юнит-тестов (64 теста, ~0.01s):
cd ~/super-shooter-hybrid
python tests/test_game_logic.py
python tests/test_network_simulation.py

# Синтаксическая проверка GDScript (если godot установлен):
godot --headless --check-only --script scripts/game_manager.gd

# Проверить что все файлы на месте:
find . -name "*.gd" | sort

# Пуш и запуск CI-сборки APK:
git add -A && git commit -m "feat: ..." && git push origin main
# Затем следить:
gh run list --repo vipvip1088/super-shooter-hybrid --limit 3
# Скачать артефакт после успеха:
gh run download <RUN_ID> --repo vipvip1088/super-shooter-hybrid \
  --name SuperShooterHybrid-debug-apk --dir ~/Downloads/
```

## Архитектурные правила

### Структура модулей (СТРОГО соблюдать)

```
scripts/
├── core/           # Чистая логика: никакого рендера, никакого UI
│   ├── player_state.gd       # Данные и поведение игрока
│   ├── zone_system.gd        # Зона: фазы, урон, радиус
│   ├── shop_system.gd        # Каталог, покупка, экономика раундов
│   ├── crafting_system.gd    # Рецепты, расход ресурсов
│   ├── enemy_ai.gd           # Базовый класс врага + стейт-машина
│   └── round_manager.gd      # Раунды, победа/поражение, награды
├── rendering/      # Только _draw() и визуальные эффекты
│   ├── world_renderer.gd     # Карта, зона, баррикады
│   ├── player_renderer.gd    # Игрок, враги, снаряды
│   └── fx_manager.gd         # Частицы, screen shake, hit-стопы
├── ui/             # Только CanvasLayer/Control — никакой логики
│   ├── hud.gd                # Статы, джойстик, кнопки
│   ├── shop_menu.gd          # Меню закупки
│   └── game_over_screen.gd   # Финальный экран
├── network/        # Уже реализовано
│   ├── network_manager.gd
│   ├── network_packets.gd
│   └── network_player.gd
└── game_manager.gd           # ТОЛЬКО оркестратор: создаёт узлы,
                              # соединяет сигналы, НЕ содержит логики
```

### Правила

1. **Один файл — одна ответственность.** `game_manager.gd` — оркестратор, не логика. Логика зоны — только в `zone_system.gd`. Рендер — только в `rendering/`.

2. **Связь через сигналы, не через `set_meta`.** Компоненты общаются только через `signal`/`connect`. `set_meta`/`get_meta` — запрещены для передачи игровых данных.

3. **Никаких монолитов.** Если файл превысил 300 строк — разбить. Если функция превысила 40 строк — разбить.

4. **Типизация везде.** Все переменные, аргументы и возвращаемые значения — с типами. `var x` → `var x: float`.

5. **Конфигурация — отдельно.** Все числовые константы баланса (HP, урон, цены, таймеры) выносить в `config/balance.gd` как `const`. Не хардкодить в логику.

## Железное правило: НИКАКИХ ЗАГЛУШЕК

- **Запрещено:** `TODO`, `pass` (кроме пустых виртуальных методов), `...`, `# FIXME`, `# временно`, неполные ветки `if/else`
- **Обязательно:** Любая фича пишется целиком до рабочего состояния. Если фича большая — делится на подзадачи, каждая из которых реализуется полностью.
- **Проверка перед каждым коммитом:**

```bash
# Найти заглушки:
grep -rn "TODO\|FIXME\|pass$\|\.\.\." scripts/ --include="*.gd"
# Если вывод не пустой — коммит запрещён.
```

## Обязательная проверка после каждого изменения

После написания/изменения любого `.gd` файла — ОБЯЗАТЕЛЬНО:

```bash
# 1. Проверка на заглушки
grep -rn "TODO\|FIXME" scripts/ --include="*.gd" && echo "ОШИБКА: есть заглушки" || echo "OK"

# 2. Запуск юнит-тестов
python tests/test_game_logic.py && python tests/test_network_simulation.py

# 3. Проверка структуры файла (не монолит)
wc -l scripts/**/*.gd | sort -n | tail -5
# Любой файл > 300 строк — сигнал к рефакторингу
```

## Текущее состояние игры (октябрь 2026)

### Что работает
- APK собирается и устанавливается на Android ✓
- Визуал: карта-сетка 3000×3000, игрок-круг, зона-круг, баррикады ✓
- Touch-джойстик + 3 кнопки (закупка, крафт, авто-тест) ✓
- Зона сужается в 5 фаз, наносит урон вне зоны ✓
- 64 Python unit-теста (game logic + network simulation) — 100% pass ✓
- GitHub Actions CI: push → APK в Artifacts ✓

### Архитектурный долг (приоритет исправления)
- `game_manager.gd` — монолит (логика + рендер + UI sync в одном файле)
- `hud.gd` использует `set_meta`/`get_meta` для передачи данных (хак)
- `player.gd` существует только для unit-тестов, не используется в игре
- `shop_system.gd` / `crafting.gd` — логика дублируется в `game_manager.gd`
- Сетевой слой (network_*.gd) полностью отключён от игры

### Чего нет (цели для evolve-game)
- Враги с ИИ
- Стрельба и хит-детекция
- Сбор ресурсов с карты
- Game-стейты (меню, игра, game over, прокачка)
- Система перков/улучшений
- Juice: screen shake, частицы, всплывающий урон, хит-стопы
- Звук
- Прогрессия между раундами
