# Media Monitor Script for Windows
# Monitors movies and TV folders after Tdarr processing
# Waits 1 hour then moves files to Jellyfin folders

param(
    [string]$Action = "monitor",
    [switch]$Help,
    [switch]$Config,
    [switch]$Test,
    [switch]$Verbose
)

# Configuration - Edit these paths for your setup
$MOVIES_SOURCE = "C:\path\to\tdarr\movies"
$TV_SOURCE = "C:\path\to\tdarr\tv"
$MOVIES_DEST = "C:\path\to\jellyfin\movies"
$TV_DEST = "C:\path\to\jellyfin\tv"
$DELAY_HOURS = 1
$LOG_FILE = "C:\logs\media-monitor.log"

# Advanced Configuration
$DELAY_SECONDS = $DELAY_HOURS * 3600
$MAX_RETRIES = 3
$RETRY_DELAY = 30
$SUPPORTED_EXTENSIONS = @("mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v", "ts", "m2ts")

# Global variables
$script:jobs = @()
$script:watchers = @()

# Function to write log messages
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    if (!(Test-Path -Path (Split-Path $LOG_FILE -Parent))) {
        New-Item -Path (Split-Path $LOG_FILE -Parent) -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $LOG_FILE -Value $logEntry
    
    # Write to console with colors
    switch ($Level) {
        "INFO"  { Write-Host "[INFO] $Message" -ForegroundColor Green }
        "WARN"  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        "DEBUG" { Write-Host "[DEBUG] $Message" -ForegroundColor Blue }
        default { Write-Host "[$Level] $Message" }
    }
}

# Function to check if file extension is supported
function Test-SupportedFile {
    param([string]$FilePath)
    
    $extension = [System.IO.Path]::GetExtension($FilePath).TrimStart('.').ToLower()
    return $SUPPORTED_EXTENSIONS -contains $extension
}

# Function to extract movie name and year from filename
function Get-MovieInfo {
    param([string]$FileName)
    
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Remove common quality indicators and convert dots to spaces
    $cleanName = $baseName -replace '\.(bluray|web|dvd|hdtv|1080p|720p|480p|4k|hdr|x264|x265|h264|h265|remux|repack|proper|directors|cut|extended|unrated|theatrical).*', '' -replace '\.', ' '
    
    # Extract year (4 digits)
    $year = ""
    if ($cleanName -match '\b(19|20)\d{2}\b') {
        $year = $matches[0]
    }
    
    # Remove year from name and clean up
    $movieName = $cleanName -replace "\b$year\b", '' -replace '^\s+|\s+$', '' -replace '\s+', ' '
    
    # Capitalize first letter of each word
    $movieName = (Get-Culture).TextInfo.ToTitleCase($movieName.ToLower())
    
    if ($year -and $movieName) {
        return "$movieName ($year)"
    } else {
        return $baseName
    }
}

# Function to create directory if it doesn't exist
function New-DirectoryIfNotExists {
    param([string]$Path)
    
    if (!(Test-Path -Path $Path)) {
        Write-Log "INFO" "Creating directory: $Path"
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Log "INFO" "Directory created successfully: $Path"
            return $true
        } catch {
            Write-Log "ERROR" "Failed to create directory: $Path - $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# Function to move file with retry logic
function Move-FileWithRetry {
    param(
        [string]$Source,
        [string]$Destination
    )
    
    $retries = 0
    
    while ($retries -lt $MAX_RETRIES) {
        Write-Log "INFO" "Attempting to move file: $Source -> $Destination"
        
        # Check if source file still exists
        if (!(Test-Path -Path $Source)) {
            Write-Log "ERROR" "Source file no longer exists: $Source"
            return $false
        }
        
        # Check if destination directory exists
        $destDir = Split-Path $Destination -Parent
        if (!(Test-Path -Path $destDir)) {
            Write-Log "ERROR" "Destination directory does not exist: $destDir"
            return $false
        }
        
        # Check if destination file already exists
        if (Test-Path -Path $Destination) {
            Write-Log "WARN" "Destination file already exists: $Destination"
            $backupDest = "$Destination.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Write-Log "INFO" "Moving existing file to backup: $backupDest"
            try {
                Move-Item -Path $Destination -Destination $backupDest -Force
            } catch {
                Write-Log "ERROR" "Failed to backup existing file: $($_.Exception.Message)"
            }
        }
        
        # Perform the move
        try {
            Move-Item -Path $Source -Destination $Destination -Force
            Write-Log "INFO" "File moved successfully: $Source -> $Destination"
            return $true
        } catch {
            $retries++
            Write-Log "WARN" "Move failed (attempt $retries/$MAX_RETRIES): $Source -> $Destination - $($_.Exception.Message)"
            
            if ($retries -lt $MAX_RETRIES) {
                Write-Log "INFO" "Retrying in $RETRY_DELAY seconds..."
                Start-Sleep -Seconds $RETRY_DELAY
            }
        }
    }
    
    Write-Log "ERROR" "Failed to move file after $MAX_RETRIES attempts: $Source -> $Destination"
    return $false
}

# Function to process a detected file
function Invoke-ProcessFile {
    param(
        [string]$FilePath,
        [string]$SourceType
    )
    
    Write-Log "INFO" "Processing $SourceType file: $FilePath"
    
    # Check if file is supported
    if (!(Test-SupportedFile -FilePath $FilePath)) {
        Write-Log "DEBUG" "Skipping unsupported file: $FilePath"
        return
    }
    
    # Wait for the delay period
    Write-Log "INFO" "Waiting $DELAY_HOURS hour(s) before processing: $FilePath"
    Start-Sleep -Seconds $DELAY_SECONDS
    
    # Check if file still exists after delay
    if (!(Test-Path -Path $FilePath)) {
        Write-Log "WARN" "File no longer exists after delay: $FilePath"
        return
    }
    
    $fileName = Split-Path $FilePath -Leaf
    $destinationDir = ""
    $destinationPath = ""
    
    if ($SourceType -eq "movies") {
        # Extract movie information and create subdirectory
        $movieFolder = Get-MovieInfo -FileName $fileName
        $destinationDir = Join-Path $MOVIES_DEST $movieFolder
        $destinationPath = Join-Path $destinationDir $fileName
        
        Write-Log "INFO" "Movie folder name: $movieFolder"
    } else {
        # TV shows go directly to TV destination
        $destinationDir = $TV_DEST
        $destinationPath = Join-Path $destinationDir $fileName
    }
    
    # Create destination directory
    if (!(New-DirectoryIfNotExists -Path $destinationDir)) {
        Write-Log "ERROR" "Failed to create destination directory: $destinationDir"
        return
    }
    
    # Move the file
    if (Move-FileWithRetry -Source $FilePath -Destination $destinationPath) {
        Write-Log "INFO" "Successfully processed $SourceType file: $fileName"
    } else {
        Write-Log "ERROR" "Failed to process $SourceType file: $fileName"
    }
}

# Function to validate configuration
function Test-Configuration {
    Write-Log "INFO" "Validating configuration..."
    
    # Check source directories
    if (!(Test-Path -Path $MOVIES_SOURCE)) {
        Write-Log "ERROR" "Movies source directory does not exist: $MOVIES_SOURCE"
        return $false
    }
    
    if (!(Test-Path -Path $TV_SOURCE)) {
        Write-Log "ERROR" "TV source directory does not exist: $TV_SOURCE"
        return $false
    }
    
    # Create destination directories if they don't exist
    if (!(New-DirectoryIfNotExists -Path $MOVIES_DEST)) {
        Write-Log "ERROR" "Failed to create movies destination directory: $MOVIES_DEST"
        return $false
    }
    
    if (!(New-DirectoryIfNotExists -Path $TV_DEST)) {
        Write-Log "ERROR" "Failed to create TV destination directory: $TV_DEST"
        return $false
    }
    
    Write-Log "INFO" "Configuration validation successful"
    return $true
}

# Function to show usage
function Show-Usage {
    Write-Host "Usage: .\media-monitor.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help              Show this help message"
    Write-Host "  -Config            Show current configuration"
    Write-Host "  -Test              Test configuration without monitoring"
    Write-Host "  -Verbose           Enable verbose logging"
    Write-Host ""
    Write-Host "Configuration (edit script to change):"
    Write-Host "  Movies Source: $MOVIES_SOURCE"
    Write-Host "  TV Source: $TV_SOURCE"
    Write-Host "  Movies Destination: $MOVIES_DEST"
    Write-Host "  TV Destination: $TV_DEST"
    Write-Host "  Delay: $DELAY_HOURS hour(s)"
    Write-Host "  Log File: $LOG_FILE"
}

# Function to show current configuration
function Show-Configuration {
    Write-Host "Current Configuration:"
    Write-Host "====================="
    Write-Host "Movies Source: $MOVIES_SOURCE"
    Write-Host "TV Source: $TV_SOURCE"
    Write-Host "Movies Destination: $MOVIES_DEST"
    Write-Host "TV Destination: $TV_DEST"
    Write-Host "Delay: $DELAY_HOURS hour(s) ($DELAY_SECONDS seconds)"
    Write-Host "Log File: $LOG_FILE"
    Write-Host "Max Retries: $MAX_RETRIES"
    Write-Host "Retry Delay: $RETRY_DELAY seconds"
    Write-Host "Supported Extensions: $($SUPPORTED_EXTENSIONS -join ', ')"
}

# Function to handle file system events
function Register-FileWatcher {
    param(
        [string]$Path,
        [string]$SourceType
    )
    
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $Path
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    $watcher.Filter = "*.*"
    
    # Register event handler
    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        $name = $Event.SourceEventArgs.Name
        
        if ($changeType -eq "Created") {
            Write-Log "INFO" "Detected new file: $path"
            
            # Process file in background job
            $scriptBlock = {
                param($FilePath, $SourceType, $ConfigVars)
                
                # Extract configuration variables
                $MOVIES_DEST = $ConfigVars.MOVIES_DEST
                $TV_DEST = $ConfigVars.TV_DEST
                $DELAY_HOURS = $ConfigVars.DELAY_HOURS
                $DELAY_SECONDS = $ConfigVars.DELAY_SECONDS
                $LOG_FILE = $ConfigVars.LOG_FILE
                $MAX_RETRIES = $ConfigVars.MAX_RETRIES
                $RETRY_DELAY = $ConfigVars.RETRY_DELAY
                $SUPPORTED_EXTENSIONS = $ConfigVars.SUPPORTED_EXTENSIONS
                
                # Re-import functions in job context
                function Write-Log {
                    param([string]$Level, [string]$Message)
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $logEntry = "[$timestamp] [$Level] $Message"
                    Add-Content -Path $LOG_FILE -Value $logEntry
                }
                
                function Test-SupportedFile {
                    param([string]$FilePath)
                    $extension = [System.IO.Path]::GetExtension($FilePath).TrimStart('.').ToLower()
                    return $SUPPORTED_EXTENSIONS -contains $extension
                }
                
                function Get-MovieInfo {
                    param([string]$FileName)
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
                    $cleanName = $baseName -replace '\.(bluray|web|dvd|hdtv|1080p|720p|480p|4k|hdr|x264|x265|h264|h265|remux|repack|proper|directors|cut|extended|unrated|theatrical).*', '' -replace '\.', ' '
                    $year = ""
                    if ($cleanName -match '\b(19|20)\d{2}\b') {
                        $year = $matches[0]
                    }
                    $movieName = $cleanName -replace "\b$year\b", '' -replace '^\s+|\s+$', '' -replace '\s+', ' '
                    $movieName = (Get-Culture).TextInfo.ToTitleCase($movieName.ToLower())
                    if ($year -and $movieName) {
                        return "$movieName ($year)"
                    } else {
                        return $baseName
                    }
                }
                
                function New-DirectoryIfNotExists {
                    param([string]$Path)
                    if (!(Test-Path -Path $Path)) {
                        Write-Log "INFO" "Creating directory: $Path"
                        try {
                            New-Item -Path $Path -ItemType Directory -Force | Out-Null
                            Write-Log "INFO" "Directory created successfully: $Path"
                            return $true
                        } catch {
                            Write-Log "ERROR" "Failed to create directory: $Path - $($_.Exception.Message)"
                            return $false
                        }
                    }
                    return $true
                }
                
                function Move-FileWithRetry {
                    param([string]$Source, [string]$Destination)
                    $retries = 0
                    while ($retries -lt $MAX_RETRIES) {
                        Write-Log "INFO" "Attempting to move file: $Source -> $Destination"
                        if (!(Test-Path -Path $Source)) {
                            Write-Log "ERROR" "Source file no longer exists: $Source"
                            return $false
                        }
                        $destDir = Split-Path $Destination -Parent
                        if (!(Test-Path -Path $destDir)) {
                            Write-Log "ERROR" "Destination directory does not exist: $destDir"
                            return $false
                        }
                        if (Test-Path -Path $Destination) {
                            Write-Log "WARN" "Destination file already exists: $Destination"
                            $backupDest = "$Destination.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
                            Write-Log "INFO" "Moving existing file to backup: $backupDest"
                            try {
                                Move-Item -Path $Destination -Destination $backupDest -Force
                            } catch {
                                Write-Log "ERROR" "Failed to backup existing file: $($_.Exception.Message)"
                            }
                        }
                        try {
                            Move-Item -Path $Source -Destination $Destination -Force
                            Write-Log "INFO" "File moved successfully: $Source -> $Destination"
                            return $true
                        } catch {
                            $retries++
                            Write-Log "WARN" "Move failed (attempt $retries/$MAX_RETRIES): $Source -> $Destination - $($_.Exception.Message)"
                            if ($retries -lt $MAX_RETRIES) {
                                Write-Log "INFO" "Retrying in $RETRY_DELAY seconds..."
                                Start-Sleep -Seconds $RETRY_DELAY
                            }
                        }
                    }
                    Write-Log "ERROR" "Failed to move file after $MAX_RETRIES attempts: $Source -> $Destination"
                    return $false
                }
                
                # Main processing logic
                Write-Log "INFO" "Processing $SourceType file: $FilePath"
                
                if (!(Test-SupportedFile -FilePath $FilePath)) {
                    Write-Log "DEBUG" "Skipping unsupported file: $FilePath"
                    return
                }
                
                Write-Log "INFO" "Waiting $DELAY_HOURS hour(s) before processing: $FilePath"
                Start-Sleep -Seconds $DELAY_SECONDS
                
                if (!(Test-Path -Path $FilePath)) {
                    Write-Log "WARN" "File no longer exists after delay: $FilePath"
                    return
                }
                
                $fileName = Split-Path $FilePath -Leaf
                $destinationDir = ""
                $destinationPath = ""
                
                if ($SourceType -eq "movies") {
                    $movieFolder = Get-MovieInfo -FileName $fileName
                    $destinationDir = Join-Path $MOVIES_DEST $movieFolder
                    $destinationPath = Join-Path $destinationDir $fileName
                    Write-Log "INFO" "Movie folder name: $movieFolder"
                } else {
                    $destinationDir = $TV_DEST
                    $destinationPath = Join-Path $destinationDir $fileName
                }
                
                if (!(New-DirectoryIfNotExists -Path $destinationDir)) {
                    Write-Log "ERROR" "Failed to create destination directory: $destinationDir"
                    return
                }
                
                if (Move-FileWithRetry -Source $FilePath -Destination $destinationPath) {
                    Write-Log "INFO" "Successfully processed $SourceType file: $fileName"
                } else {
                    Write-Log "ERROR" "Failed to process $SourceType file: $fileName"
                }
            }
            
            # Package configuration variables
            $configVars = @{
                MOVIES_DEST = $MOVIES_DEST
                TV_DEST = $TV_DEST
                DELAY_HOURS = $DELAY_HOURS
                DELAY_SECONDS = $DELAY_SECONDS
                LOG_FILE = $LOG_FILE
                MAX_RETRIES = $MAX_RETRIES
                RETRY_DELAY = $RETRY_DELAY
                SUPPORTED_EXTENSIONS = $SUPPORTED_EXTENSIONS
            }
            
            $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $path, $using:SourceType, $configVars
            $script:jobs += $job
        }
    }
    
    $created = Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $action
    
    $script:watchers += @{
        Watcher = $watcher
        Event = $created
        Path = $Path
        Type = $SourceType
    }
    
    Write-Log "INFO" "Started monitoring $SourceType folder: $Path"
}

# Function to cleanup resources
function Stop-Monitoring {
    Write-Log "INFO" "Stopping media monitoring..."
    
    # Unregister events and dispose watchers
    foreach ($item in $script:watchers) {
        if ($item.Event) {
            Unregister-Event -SourceIdentifier $item.Event.Name
        }
        if ($item.Watcher) {
            $item.Watcher.EnableRaisingEvents = $false
            $item.Watcher.Dispose()
        }
    }
    
    # Stop all background jobs
    $script:jobs | Stop-Job
    $script:jobs | Remove-Job
    
    Write-Log "INFO" "Media monitoring stopped"
}

# Function to start monitoring
function Start-Monitoring {
    Write-Log "INFO" "Starting media monitoring..."
    Write-Log "INFO" "Monitoring movies folder: $MOVIES_SOURCE"
    Write-Log "INFO" "Monitoring TV folder: $TV_SOURCE"
    Write-Log "INFO" "Delay before moving: $DELAY_HOURS hour(s)"
    
    # Register file watchers
    Register-FileWatcher -Path $MOVIES_SOURCE -SourceType "movies"
    Register-FileWatcher -Path $TV_SOURCE -SourceType "tv"
    
    # Set up console handler for graceful shutdown
    [Console]::TreatControlCAsInput = $true
    
    Write-Log "INFO" "Media monitoring started. Press Ctrl+C to stop."
    
    try {
        while ($true) {
            Start-Sleep -Seconds 1
            
            # Check for Ctrl+C
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "C" -and $key.Modifiers -eq "Control") {
                    break
                }
            }
            
            # Clean up completed jobs
            $script:jobs = $script:jobs | Where-Object { $_.State -ne "Completed" }
        }
    } finally {
        Stop-Monitoring
    }
}

# Main script execution
function Main {
    # Handle parameters
    if ($Help) {
        Show-Usage
        return
    }
    
    if ($Config) {
        Show-Configuration
        return
    }
    
    if ($Test) {
        $result = Test-Configuration
        if ($result) {
            Write-Host "Configuration test passed!" -ForegroundColor Green
        } else {
            Write-Host "Configuration test failed!" -ForegroundColor Red
        }
        return
    }
    
    if ($Verbose) {
        $VerbosePreference = "Continue"
    }
    
    # Start logging
    Write-Log "INFO" "Media Monitor started (PID: $PID)"
    
    # Validate configuration
    if (!(Test-Configuration)) {
        Write-Log "ERROR" "Configuration validation failed. Exiting."
        return
    }
    
    # Start monitoring
    Start-Monitoring
}

# Run main function
Main
