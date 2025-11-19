# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pwnagotchi is a Raspberry Pi-based device that captures WiFi handshakes and PMKIDs using bettercap. This is the main fork supporting multiple Raspberry Pi models (Zero W, Zero 2W, 3, 4, 5). The AI functionality has been removed from this fork to improve stability and battery life.

**Important**: This codebase is designed for authorized security testing and educational purposes only. It's intended for pentesting engagements, CTF competitions, security research, and defensive security contexts.

## Development Commands

### Building and Installation
```bash
# Build and install the package
python -m pip install -e .

# Update language files (generate .po files from source)
make update_langs

# Compile language files (.po to .mo)
make compile_langs
```

### Running Pwnagotchi
```bash
# Start in auto mode (default - actively captures handshakes)
pwnagotchi

# Start in manual mode (passive monitoring only)
pwnagotchi --manual

# Interactive configuration wizard
pwnagotchi --wizard

# Check for updates
pwnagotchi --check-update

# Print current configuration
pwnagotchi --print-config

# Clear display and exit
pwnagotchi --clear

# Debug mode
pwnagotchi --debug
```

### Configuration Files
- Default config: `/etc/pwnagotchi/default.toml`
- User config: `/etc/pwnagotchi/config.toml` (overrides defaults)
- Plugin configs: `/etc/pwnagotchi/conf.d/`

### Plugin Management
```bash
# List available plugins
pwnagotchi plugins list

# Install plugins
pwnagotchi plugins install <plugin-name>

# Update plugins
pwnagotchi plugins update

# Search plugins
pwnagotchi plugins search <query>
```

### Testing & Development
Note: This project does not currently have a test suite. Testing is typically done on actual Raspberry Pi hardware.

## Architecture

### Core Components

**Agent (`pwnagotchi/agent.py`)**
- Main orchestrator that combines Client (bettercap), Automata (mood system), and AsyncAdvertiser (mesh networking)
- Manages the capture lifecycle: recon → channel hopping → association → deauthentication
- Coordinates between bettercap API, UI updates, and plugin events
- Entry point is instantiated in `cli.py` as `Agent(view=display, config=config, keypair=KeyPair(...))`

**Bettercap Client (`pwnagotchi/bettercap.py`)**
- REST API client for bettercap running on localhost:8081
- Sends commands like `wifi.recon on`, `wifi.deauth`, `wifi.assoc`
- Uses websockets for real-time event streaming
- Handles session management and module control

**Automata (`pwnagotchi/automata.py`)**
- Mood/state system (bored, lonely, excited, sad, etc.)
- Tracks epochs (complete cycles through all channels)
- Triggers mood changes based on activity levels and peer interactions
- Each mood state triggers corresponding plugin hooks

**CLI (`pwnagotchi/cli.py`)**
- Entry point with argument parsing
- Implements two main modes:
  - `do_auto_mode()`: Active hunting - deauth attacks, association attempts
  - `do_manual_mode()`: Passive monitoring only
- Loads config, initializes plugins, sets up display, creates Agent

**Plugins System (`pwnagotchi/plugins/__init__.py`)**
- Event-driven plugin architecture with threaded event queues
- Each plugin runs in its own thread with a work queue (`PluginEventQueue`)
- Plugins inherit from `plugins.Plugin` base class
- Default plugins in `pwnagotchi/plugins/default/`
- Custom plugins can be installed from repos defined in config

**UI/Display (`pwnagotchi/ui/`)**
- `view.py`: Main View class that manages display state and rendering
- `display.py`: Display abstraction layer
- `hw/`: Hardware-specific drivers for 50+ display types (e-paper, LCD, OLED)
- `components.py`: Reusable UI elements (LabeledValue, Line, Text)
- `faces.py`: ASCII/emoji faces representing mood states
- `web/`: Flask web UI for remote management

**Mesh Networking (`pwnagotchi/mesh/`)**
- Peer-to-peer communication between nearby Pwnagotchis
- Custom protocol using 802.11 information elements
- `peer.py`: Peer object tracking encounters and metadata
- `utils.py`: AsyncAdvertiser for broadcasting unit info
- Integration with pwngrid-peer service (port 8666)

**Grid Integration (`pwnagotchi/grid.py`)**
- API client for pwngrid-peer daemon
- Handles unit registration and peer synchronization
- API endpoint: http://127.0.0.1:8666/api/v1

### Key Data Flows

1. **Main Loop (Auto Mode)**:
   - `agent.recon()` → bettercap scans all channels
   - `agent.get_access_points_by_channel()` → groups APs by channel
   - For each channel: `agent.set_channel(ch)`
   - For each AP: `agent.associate(ap)` (PMKID capture)
   - For each client: `agent.deauth(ap, sta)` (handshake capture)
   - `agent.next_epoch()` → triggers epoch-based plugin events

2. **Plugin Event Flow**:
   - Core system triggers event: `plugins.on('event_name', agent, ...)`
   - Event added to plugin's work queue via `PluginEventQueue.AddWork()`
   - Plugin's event handler called: `on_<event_name>(agent, ...)`
   - Plugin can modify UI: `ui.set('element_name', value)`

3. **Configuration Loading**:
   - `utils.load_config()` reads default.toml and merges config.toml
   - Config uses TOML format with nested sections
   - Plugin configs: `[main.plugins.plugin-name]`

### Plugin Development

Plugins must inherit from `plugins.Plugin` and can implement these hooks:

**Lifecycle Events**:
- `on_loaded()` - plugin initialization
- `on_ready(agent)` - main loop about to start
- `on_unload(ui)` - cleanup before unload

**UI Events**:
- `on_ui_setup(ui)` - add custom UI elements
- `on_ui_update(ui)` - update UI element values
- `on_display_setup(display)` - hardware display is ready

**Agent State Events**:
- `on_bored(agent)`, `on_sad(agent)`, `on_excited(agent)`, `on_lonely(agent)`
- `on_wait(agent, t)`, `on_sleep(agent, t)`
- `on_rebooting(agent)`

**WiFi Events**:
- `on_wifi_update(agent, access_points)` - filtered AP list updated
- `on_unfiltered_ap_list(agent, access_points)` - raw AP list
- `on_association(agent, access_point)` - sending association frame
- `on_deauthentication(agent, access_point, client_station)` - sending deauth
- `on_handshake(agent, filename, access_point, client_station)` - captured handshake
- `on_channel_hop(agent, channel)` - changed channel
- `on_free_channel(agent, channel)` - found unused channel

**Network Events**:
- `on_internet_available(agent)` - internet connectivity detected
- `on_peer_detected(agent, peer)` - nearby Pwnagotchi found
- `on_peer_lost(agent, peer)` - peer went out of range

**Other Events**:
- `on_epoch(agent, epoch, epoch_data)` - completed full channel scan cycle
- `on_webhook(path, request)` - HTTP request to `/plugins/<plugin-name>/`

Example plugin structure:
```python
class MyPlugin(plugins.Plugin):
    __author__ = 'author@email.com'
    __version__ = '1.0.0'
    __license__ = 'GPL3'
    __description__ = 'Description'

    def on_loaded(self):
        logging.info("plugin loaded with options: %s" % self.options)

    def on_handshake(self, agent, filename, access_point, client_station):
        # Do something with captured handshake
        pass
```

### Display Driver Development

Display drivers live in `pwnagotchi/ui/hw/` and must:
1. Import from base: `from pwnagotchi.ui.hw.base import DisplayImpl`
2. Implement required methods: `layout()`, `initialize()`, `render()`, `clear()`
3. Define layout dict with element positions (x, y coordinates)
4. Handle hardware-specific initialization and rendering

Common display types: Waveshare e-paper, Pimoroni Inky, Adafruit LCD/OLED, DFRobot

### Configuration System

Config files use TOML format. User config (`config.toml`) merges with and overrides defaults (`default.toml`).

Key config sections:
- `[main]` - core settings (name, interface, whitelist)
- `[main.plugins.<name>]` - plugin-specific config
- `[ui]` - display settings
- `[ui.display]` - hardware display type and options
- `[ui.faces]` - face position and style
- `[bettercap]` - bettercap API connection settings
- `[personality]` - behavior tuning (TTLs, RSSI thresholds, mood factors)

### Important Gotchas

1. **No AI Mode**: This fork has removed the AI/reinforcement learning components. The agent operates on a simple channel-hopping algorithm.

2. **Bettercap Dependency**: Pwnagotchi requires a running bettercap instance with REST API enabled. It communicates via HTTP (port 8081) and WebSocket.

3. **Monitor Mode**: WiFi interface must be in monitor mode. The `mon_start_cmd` and `mon_stop_cmd` config options handle this, typically calling `/usr/bin/monstart` and `/usr/bin/monstop`.

4. **Plugin Threading**: Plugins run in separate threads. Use proper locking for shared resources. The `on_loaded` event runs in a dedicated thread and can block.

5. **UI Thread Safety**: UI updates must be thread-safe. Use the view's lock when modifying display state from plugins.

6. **Handshake Storage**: Captured handshakes are stored as PCAP files in the directory specified by `bettercap.handshakes` config (default: `/home/pi/handshakes`).

7. **Whitelist Format**: The whitelist accepts SSIDs (strings) and BSSIDs (MAC addresses). Partial MAC prefixes are supported (e.g., "fo:od:ba" matches "fo:od:ba:be:fo:od").

8. **Language Files**: Use `make update_langs` to extract translatable strings, then `make compile_langs` to generate binary .mo files from .po translations.

9. **Web UI**: Flask web UI runs on port 8080 by default, managed by `pwnagotchi/ui/web/server.py`.

10. **System Integration**: Pwnagotchi is typically run as a systemd service. It modifies system files like `/etc/hostname` and can trigger reboots.

## Contributing

- All commits must be signed: `git commit -s`
- Raise an issue before submitting PRs for new features
- Do not mix feature changes with refactoring
- Follow the Developer Certificate of Origin (DCO) 1.1
- License: GPL3

## Resources

- Documentation: https://github.com/jayofelony/pwnagotchi/wiki
- Website: https://pwnagotchi.org
- Discord: https://discord.gg/PGgnzFbz4M
- Subreddit: r/pwnagotchi
