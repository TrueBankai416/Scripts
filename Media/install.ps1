# Media Monitor Installation Script for Windows
# Installs and configures the media monitoring system

param(
    [string]$Action = "install",
    [switch]$Help
)

# Configuration
$INSTALL_DIR = "C:\Program Files\MediaMonitor"
$SERVICE_NAME = "MediaMonitor"
$LOG_DIR = "C:\logs"
$SCRIPT_NAME = "media-monitor.ps1"

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to print colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    Write-Host $Message -ForegroundColor $Color
}

# Function to download media monitor script
function Get-MediaMonitorScript {
    Write-ColorOutput "Downloading media monitor script..." "Blue"
    
    $scriptUrl = "https://raw.githubusercontent.com/TrueBankai416/Scripts/main/Media/media-monitor.ps1"
    $tempFile = "$env:TEMP\media-monitor.ps1"
    
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $tempFile
        Write-ColorOutput "Script downloaded successfully" "Green"
        
        # Create install directory and copy script
        New-Item -Path $INSTALL_DIR -ItemType Directory -Force | Out-Null
        Copy-Item -Path $tempFile -Destination "$INSTALL_DIR\$SCRIPT_NAME" -Force
        
        Write-ColorOutput "Script installed to $INSTALL_DIR\$SCRIPT_NAME" "Green"
        return $true
    } catch {
        Write-ColorOutput "Failed to download script: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to configure the script
function Set-MediaMonitorConfig {
    Write-ColorOutput "Configuring media monitor..." "Blue"
    
    Write-Host "Please provide the following paths:"
    
    # Get source directories
    $moviesSource = Read-Host "Movies source directory (Tdarr output)"
    $tvSource = Read-Host "TV source directory (Tdarr output)"
    
    # Get destination directories
    $moviesDest = Read-Host "Movies destination directory (Jellyfin)"
    $tvDest = Read-Host "TV destination directory (Jellyfin)"
    
    # Get delay
    $delayHours = Read-Host "Delay in hours before moving files [1]"
    if ([string]::IsNullOrEmpty($delayHours)) {
        $delayHours = 1
    }
    
    # Validate paths
    if (!(Test-Path -Path $moviesSource)) {
        Write-ColorOutput "Warning: Movies source directory does not exist: $moviesSource" "Yellow"
    }
    
    if (!(Test-Path -Path $tvSource)) {
        Write-ColorOutput "Warning: TV source directory does not exist: $tvSource" "Yellow"
    }
    
    # Create destination directories if they don't exist
    New-Item -Path $moviesDest -ItemType Directory -Force | Out-Null
    New-Item -Path $tvDest -ItemType Directory -Force | Out-Null
    
    # Update script configuration
    $scriptPath = "$INSTALL_DIR\$SCRIPT_NAME"
    $scriptContent = Get-Content -Path $scriptPath
    
    $scriptContent = $scriptContent -replace '\$MOVIES_SOURCE = ".*"', "`$MOVIES_SOURCE = `"$moviesSource`""
    $scriptContent = $scriptContent -replace '\$TV_SOURCE = ".*"', "`$TV_SOURCE = `"$tvSource`""
    $scriptContent = $scriptContent -replace '\$MOVIES_DEST = ".*"', "`$MOVIES_DEST = `"$moviesDest`""
    $scriptContent = $scriptContent -replace '\$TV_DEST = ".*"', "`$TV_DEST = `"$tvDest`""
    $scriptContent = $scriptContent -replace '\$DELAY_HOURS = \d+', "`$DELAY_HOURS = $delayHours"
    
    Set-Content -Path $scriptPath -Value $scriptContent
    
    Write-ColorOutput "Configuration updated successfully" "Green"
}

# Function to create Windows service
function New-MediaMonitorService {
    Write-ColorOutput "Creating Windows service..." "Blue"
    
    # Create service wrapper script
    $wrapperScript = @"
`$scriptPath = "$INSTALL_DIR\$SCRIPT_NAME"
`$logPath = "$LOG_DIR\service.log"

# Create log directory
New-Item -Path (Split-Path `$logPath -Parent) -ItemType Directory -Force | Out-Null

# Start the media monitor
try {
    & powershell.exe -ExecutionPolicy Bypass -File `$scriptPath *>&1 | Tee-Object -FilePath `$logPath
} catch {
    Add-Content -Path `$logPath -Value "Service error: `$(`$_.Exception.Message)"
}
"@
    
    $wrapperPath = "$INSTALL_DIR\service-wrapper.ps1"
    Set-Content -Path $wrapperPath -Value $wrapperScript
    
    # Create service using NSSM (Non-Sucking Service Manager) or PowerShell
    try {
        # Try using sc.exe to create service
        $serviceBinary = "powershell.exe"
        $serviceArgs = "-ExecutionPolicy Bypass -File `"$wrapperPath`""
        
        # Create the service
        & sc.exe create $SERVICE_NAME binpath= "`"$serviceBinary`" $serviceArgs" start= auto
        & sc.exe description $SERVICE_NAME "Media Monitor Service - Monitors and organizes media files"
        
        Write-ColorOutput "Windows service created successfully" "Green"
        return $true
    } catch {
        Write-ColorOutput "Failed to create Windows service: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to start service
function Start-MediaMonitorService {
    Write-ColorOutput "Starting media monitor service..." "Blue"
    
    try {
        Start-Service -Name $SERVICE_NAME
        Write-ColorOutput "Service started successfully" "Green"
        
        # Show service status
        Get-Service -Name $SERVICE_NAME | Format-Table -AutoSize
        return $true
    } catch {
        Write-ColorOutput "Failed to start service: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to uninstall
function Remove-MediaMonitorService {
    Write-ColorOutput "Uninstalling media monitor..." "Blue"
    
    try {
        # Stop service
        Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue
        
        # Remove service
        & sc.exe delete $SERVICE_NAME
        
        # Remove installation directory
        Remove-Item -Path $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-ColorOutput "Media monitor uninstalled successfully" "Green"
    } catch {
        Write-ColorOutput "Error during uninstall: $($_.Exception.Message)" "Red"
    }
}

# Function to show service status
function Show-ServiceStatus {
    try {
        Get-Service -Name $SERVICE_NAME | Format-Table -AutoSize
        
        # Show recent logs
        $logPath = "$LOG_DIR\service.log"
        if (Test-Path -Path $logPath) {
            Write-ColorOutput "`nRecent logs:" "Blue"
            Get-Content -Path $logPath -Tail 10
        }
    } catch {
        Write-ColorOutput "Service not found or error getting status: $($_.Exception.Message)" "Red"
    }
}

# Function to show service logs
function Show-ServiceLogs {
    $logPath = "$LOG_DIR\service.log"
    $appLogPath = "$LOG_DIR\media-monitor.log"
    
    if (Test-Path -Path $logPath) {
        Write-ColorOutput "Service logs:" "Blue"
        Get-Content -Path $logPath -Tail 20
    }
    
    if (Test-Path -Path $appLogPath) {
        Write-ColorOutput "`nApplication logs:" "Blue"
        Get-Content -Path $appLogPath -Tail 20
    }
}

# Function to restart service
function Restart-MediaMonitorService {
    Write-ColorOutput "Restarting media monitor service..." "Blue"
    
    try {
        Restart-Service -Name $SERVICE_NAME -Force
        Write-ColorOutput "Service restarted successfully" "Green"
        Show-ServiceStatus
    } catch {
        Write-ColorOutput "Failed to restart service: $($_.Exception.Message)" "Red"
    }
}

# Function to show usage
function Show-Usage {
    Write-Host "Usage: .\install.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  install     - Install media monitor"
    Write-Host "  uninstall   - Uninstall media monitor"
    Write-Host "  status      - Show service status"
    Write-Host "  logs        - Show service logs"
    Write-Host "  restart     - Restart service"
    Write-Host "  help        - Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\install.ps1 install"
    Write-Host "  .\install.ps1 uninstall"
    Write-Host "  .\install.ps1 status"
    Write-Host "  .\install.ps1 logs"
}

# Function to run interactive installation
function Start-InteractiveInstall {
    Write-ColorOutput "=== Media Monitor Installation ===" "Green"
    Write-ColorOutput "This script will install and configure the media monitor service." "Blue"
    Write-Host ""
    
    # Check for existing installation
    if (Test-Path -Path "$INSTALL_DIR\$SCRIPT_NAME") {
        Write-ColorOutput "Media monitor is already installed." "Yellow"
        $reinstall = Read-Host "Do you want to reinstall? (y/N)"
        if ($reinstall -notmatch '^[Yy]$') {
            Write-ColorOutput "Installation cancelled." "Blue"
            return
        }
        
        # Uninstall existing
        Remove-MediaMonitorService
    }
    
    # Run installation steps
    if (!(Get-MediaMonitorScript)) {
        return
    }
    
    Set-MediaMonitorConfig
    
    if (!(New-MediaMonitorService)) {
        return
    }
    
    if (!(Start-MediaMonitorService)) {
        return
    }
    
    Write-ColorOutput "=== Installation Complete ===" "Green"
    Write-Host ""
    Write-ColorOutput "The media monitor service is now running and will start automatically on boot." "Blue"
    Write-Host ""
    Write-ColorOutput "Useful commands:" "Blue"
    Write-Host "  Get-Service -Name $SERVICE_NAME                 - Check service status"
    Write-Host "  Stop-Service -Name $SERVICE_NAME                - Stop service"
    Write-Host "  Start-Service -Name $SERVICE_NAME               - Start service"
    Write-Host "  Restart-Service -Name $SERVICE_NAME             - Restart service"
    Write-Host "  Get-Content -Path $LOG_DIR\service.log -Tail 20 - View service logs"
    Write-Host "  Get-Content -Path $LOG_DIR\media-monitor.log -Tail 20 - View application logs"
}

# Main script execution
function Main {
    # Check if running as administrator
    if (!(Test-Administrator)) {
        Write-ColorOutput "This script must be run as Administrator" "Red"
        Write-ColorOutput "Please run PowerShell as Administrator and try again" "Yellow"
        return
    }
    
    # Handle parameters
    if ($Help) {
        Show-Usage
        return
    }
    
    switch ($Action.ToLower()) {
        "install" {
            Start-InteractiveInstall
        }
        "uninstall" {
            Remove-MediaMonitorService
        }
        "status" {
            Show-ServiceStatus
        }
        "logs" {
            Show-ServiceLogs
        }
        "restart" {
            Restart-MediaMonitorService
        }
        "help" {
            Show-Usage
        }
        default {
            Write-ColorOutput "Unknown action: $Action" "Red"
            Show-Usage
        }
    }
}

# Run main function
Main
