# SuperShooterHybrid

Mobile shooter combining PUBG + CS:GO + Rust mechanics built with Godot 4.

## Mechanics
- **Battle Royale zone** (PUBG): shrinking damage zone with 5 phases
- **Round economy** (CS): buy weapons/ammo with round-earned money
- **Crafting** (Rust): collect wood/metal, craft barricades and walls

## Build Status
[![Build Android APK](../../actions/workflows/build-apk.yml/badge.svg)](../../actions/workflows/build-apk.yml)

## Download APK
Go to **Actions → Build Android APK → latest run → Artifacts** and download `SuperShooterHybrid-debug-apk`.

## Run tests locally
```bash
python tests/test_game_logic.py
```

## Project structure
```
super-shooter-hybrid/
├── scripts/
│   ├── player.gd          # Movement, health, inventory
│   ├── zone_manager.gd    # BR zone shrinking logic
│   ├── shop_system.gd     # CS-style buy menu
│   └── crafting.gd        # Rust-style crafting
├── scenes/
│   ├── main.tscn
│   └── player.tscn
├── tests/
│   └── test_game_logic.py  # 43 unit tests
└── .github/workflows/
    └── build-apk.yml       # Auto-builds APK on push to main
```
