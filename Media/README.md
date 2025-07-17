# Media Monitoring Scripts

This folder contains scripts for monitoring media files after Tdarr processing and organizing them for Jellyfin.

## Purpose

These scripts monitor movies and TV folders for new files processed by Tdarr. When a new file is detected, the script waits 1 hour and then moves the content to a different folder monitored by Jellyfin.

## Features

- Cross-platform support (Linux/Windows)
- Automatic movie folder creation with proper naming
- 1-hour delay before moving files
- Jellyfin-compatible organization
- Comprehensive logging
- Configurable source and destination folders

## Files

- `media-monitor.sh` - Linux version using inotify-tools
- `media-monitor.ps1` - Windows PowerShell version
- `install.sh` - Installation script for Linux
- `install.ps1` - Installation script for Windows
- `README.md` - This documentation

## Movie Naming Convention

The script automatically creates subdirectories for movies based on their filenames:

**Examples:**
- `pokemon.2025.bluray.1080p.mkv` → `Pokemon (2025)/pokemon.2025.bluray.1080p.mkv`
- `avengers.endgame.2019.4k.hdr.mkv` → `Avengers Endgame (2019)/avengers.endgame.2019.4k.hdr.mkv`
- `the.matrix.1999.directors.cut.mkv` → `The Matrix (1999)/the.matrix.1999.directors.cut.mkv`

## Quick Start

### Linux
```bash
# Install dependencies
sudo apt update
sudo apt install inotify-tools

# Download and run
wget https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Media/media-monitor.sh
chmod +x media-monitor.sh
sudo ./media-monitor.sh
```

### Windows
```powershell
# Download and run
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Media/media-monitor.ps1" -OutFile "media-monitor.ps1"
powershell.exe -ExecutionPolicy Bypass -File "media-monitor.ps1"
```

## Configuration

Edit the configuration variables at the top of the script:

- `MOVIES_SOURCE` - Source folder for movies (Tdarr output)
- `TV_SOURCE` - Source folder for TV shows (Tdarr output)
- `MOVIES_DEST` - Destination folder for movies (Jellyfin watched)
- `TV_DEST` - Destination folder for TV shows (Jellyfin watched)
- `DELAY_HOURS` - Hours to wait before moving (default: 1)
- `LOG_FILE` - Log file location

## Usage

The script runs continuously, monitoring for new files. It will:

1. Detect new files in source folders
2. Wait the specified delay (1 hour by default)
3. Create appropriate subdirectories for movies
4. Move files to Jellyfin-monitored folders
5. Log all operations

## Requirements

### Linux
- `inotify-tools` package
- `bash` shell
- Write permissions to destination folders

### Windows
- PowerShell 5.0 or later
- Write permissions to destination folders

## Logging

All operations are logged with timestamps including:
- File detection events
- Delay periods
- Move operations
- Errors and warnings

## Safety Features

- Validates source and destination folders exist
- Checks file permissions before moving
- Creates backup of original file locations
- Handles duplicate files gracefully
- Comprehensive error handling
