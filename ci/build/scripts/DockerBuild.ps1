if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        if ($_ -notmatch '^#' -and $_ -match '=') {
            $name, $value = $_ -split '=', 2
            # Strip surrounding quotes from value
            $value = $value -replace '^"|"$', ''
            [System.Environment]::SetEnvironmentVariable($name, $value)
        }
    }
} else {
    Write-Host "Warning: .env file not found. Using defaults."
}

$imageName = if ($args[0]) { $args[0] } else { "tankassist-ci" }
$dockerFilePath = "./ci/build/Dockerfile"

# Get project directory dynamically from current location (lowercase drive letter)
$currentPath = (Get-Location).Path -replace '\\', '/'
$driveLetter = $currentPath.Substring(0, 1).ToLower()
$pathWithoutDrive = $currentPath.Substring(2)
$projectDir = "/${driveLetter}${pathWithoutDrive}"

# Use WoW addon directories from .env file (loaded above)
$wowAddonsDirRetail = [System.Environment]::GetEnvironmentVariable("wow_addons_dir_retail")
$wowAddonsDirPtr = [System.Environment]::GetEnvironmentVariable("wow_addons_dir_ptr")

if (-not $wowAddonsDirRetail) {
    Write-Host "Warning: wow_addons_dir_retail not set in .env file"
}
if (-not $wowAddonsDirPtr) {
    Write-Host "Warning: wow_addons_dir_ptr not set in .env file"
}

Write-Host "Building Docker image: $imageName"
docker build -t $imageName -f $dockerFilePath .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build failed."
    exit 1
}

Write-Host "Running Docker container and mounting project directory.."
Write-Host "Project dir: ${projectDir}"
Write-Host "WoW Addons dir (Retail): ${wowAddonsDirRetail}"
Write-Host "WoW Addons dir (PTR): ${wowAddonsDirPtr}"

# Helper function to extract drive letter from path (handles quotes and case)
function Get-DriveLetter($path) {
    if ($path -match '^"?/([a-zA-Z])/') {
        # Use lowercase to match Git Bash paths (/c/ not /C/)
        return $matches[1].ToLower()
    }
    return $null
}

# Helper function to clean path (remove surrounding quotes)
function Clean-Path($path) {
    return $path -replace '^"|"$', ''
}

# Extract drive letters from all paths to determine unique drives needed
$drives = @{}
$projectDriveLetter = Get-DriveLetter $projectDir
if ($projectDriveLetter) { $drives[$projectDriveLetter] = $true }

if ($wowAddonsDirRetail) {
    $drive = Get-DriveLetter $wowAddonsDirRetail
    if ($drive) { $drives[$drive] = $true }
}
if ($wowAddonsDirPtr) {
    $drive = Get-DriveLetter $wowAddonsDirPtr
    if ($drive) { $drives[$drive] = $true }
}

# Build volume mount arguments - mount each unique drive once
$volumeArgs = @()
foreach ($drive in $drives.Keys) {
    $volumeArgs += @("-v", "/${drive}:/${drive}")
}

# Clean project dir for working directory
$cleanProjectDir = Clean-Path $projectDir

Write-Host "Mounting drives: $($drives.Keys -join ', ')"

# Pass credentials
$envArgs = @()
$claudeVolumeArgs = @()

# Claude Code: API key from environment
$anthropicKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY")
if ($anthropicKey) {
    $envArgs += @("-e", "ANTHROPIC_API_KEY=$anthropicKey")
    Write-Host "Claude Code API key detected."
}
# Claude Code: Mount existing Claude config (from OAuth login)
else {
    $claudeConfigPath = Join-Path $env:USERPROFILE ".claude"
    if (Test-Path $claudeConfigPath) {
        $claudeConfigUnix = $claudeConfigPath -replace '\\', '/'
        $driveLetter = $claudeConfigUnix.Substring(0, 1).ToLower()
        $pathWithoutDrive = $claudeConfigUnix.Substring(2)
        $claudeConfigDocker = "/${driveLetter}${pathWithoutDrive}"
        $claudeVolumeArgs += @("-v", "${claudeConfigDocker}:/root/.claude")
        Write-Host "Mounting Claude config from ~/.claude"
    }
}

# GitHub token for git push and gh CLI
$ghToken = [System.Environment]::GetEnvironmentVariable("GH_TOKEN")
if ($ghToken) {
    $envArgs += @("-e", "GH_TOKEN=$ghToken")
    Write-Host "GitHub token detected."
}

Write-Host "Docker command: docker run --rm -ti $($volumeArgs -join ' ') $($envArgs -join ' ') $($claudeVolumeArgs -join ' ') -w ${cleanProjectDir} $imageName bash"

docker run --rm -ti @volumeArgs @envArgs @claudeVolumeArgs -w $cleanProjectDir $imageName bash

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to start Docker container."
    exit 1
}
