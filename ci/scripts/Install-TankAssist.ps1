<#
.SYNOPSIS
    Installs a TankAssist branch, tag or commit straight into your WoW AddOns folder.

.DESCRIPTION
    Downloads the ref as a zip from GitHub and extracts the shipping files into
    <WoW>\<flavor>\Interface\AddOns\TankAssist, replacing whatever is there.

    Nothing needs to be installed on the machine running this -- no git, no
    clone, no GitHub account. Copy this one file to the gaming machine and run
    it. The repository is public, so no authentication is involved.

    SavedVariables live in WTF\ and are never touched, so settings and layouts
    survive every install and every switch between branches.

.PARAMETER Branch
    The ref to install: a branch (default "develop"), a tag such as "v0.4.6",
    or a commit SHA. Branch names containing "/" are fine.

.PARAMETER WowPath
    The World of Warcraft folder -- the one containing _retail_. Auto-detected
    from the registry and the usual install locations when omitted.

.PARAMETER Flavor
    Which client to install into. TankAssist targets retail, so the default is
    _retail_; the others are here for PTR builds.

.PARAMETER List
    List the branches available on GitHub and exit without installing.

.EXAMPLE
    .\Install-TankAssist.ps1
    Installs the tip of develop.

.EXAMPLE
    .\Install-TankAssist.ps1 -Branch claude/icon-zoom-fonts
    Installs a feature branch.

.EXAMPLE
    .\Install-TankAssist.ps1 -List
    Shows what branches are available.

.EXAMPLE
    .\Install-TankAssist.ps1 -Branch v0.4.6 -WowPath 'D:\Games\World of Warcraft'
    Installs a release tag into a WoW folder that is not where it is normally found.

.NOTES
    Written for Windows PowerShell 5.1, so it avoids &&, ternaries and
    null-coalescing -- it has to run on a stock gaming machine with nothing set up.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $Branch = 'develop',
    [string] $WowPath,
    [ValidateSet('_retail_', '_ptr_', '_xptr_')]
    [string] $Flavor = '_retail_',
    [switch] $List
)

$ErrorActionPreference = 'Stop'

$Repo = 'fooxytv/TankAssist'
$AddonName = 'TankAssist'

# Everything the shipped zip leaves out. Kept in step with the exclude list in
# ci/scripts/package.sh -- ci/tests/smoke_test.py fails if the two drift apart,
# because "works from the repo but not from CurseForge" is a miserable bug to
# chase. Matched against the top-level name only; nothing nested is excluded.
$ExcludeFromInstall = @(
    '.git', '.github', 'ci', '.vscode', '.claude', 'code',
    '.env', '.env.example',
    'CLAUDE.md', 'README.md', 'CHANGELOG.md', 'LICENSE',
    '.luacheckrc', '.gitignore', '.gitattributes'
)

#--------------------------------------------------------------------------------
# Output
#--------------------------------------------------------------------------------

function Write-Step {
    param([string] $Message)
    Write-Host "  $Message"
}

function Write-Ok {
    param([string] $Message)
    Write-Host "  $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string] $Message)
    Write-Host "  $Message" -ForegroundColor Yellow
}

#--------------------------------------------------------------------------------
# Locating WoW
#--------------------------------------------------------------------------------

function Get-WowPathFromRegistry {
    # Blizzard's key points at the flavor folder on some installs and at the
    # parent on others, so normalise by looking for the flavor on the end.
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
        'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft'
    )
    foreach ($key in $keys) {
        try {
            $value = (Get-ItemProperty -Path $key -Name 'InstallPath' -ErrorAction Stop).InstallPath
        } catch {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }

        $candidate = $value.TrimEnd('\')
        if ((Split-Path $candidate -Leaf) -match '^_[a-z]+_$') {
            $candidate = Split-Path $candidate -Parent
        }
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Resolve-WowPath {
    param([string] $Explicit, [string] $Flavor)

    $candidates = New-Object System.Collections.ArrayList

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        [void]$candidates.Add($Explicit)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TANKASSIST_WOW_PATH)) {
        [void]$candidates.Add($env:TANKASSIST_WOW_PATH)
    }

    $fromRegistry = Get-WowPathFromRegistry
    if ($fromRegistry) { [void]$candidates.Add($fromRegistry) }

    foreach ($drive in @('C', 'D', 'E', 'F')) {
        [void]$candidates.Add("${drive}:\Program Files (x86)\World of Warcraft")
        [void]$candidates.Add("${drive}:\Program Files\World of Warcraft")
        [void]$candidates.Add("${drive}:\World of Warcraft")
        [void]$candidates.Add("${drive}:\Games\World of Warcraft")
    }

    foreach ($candidate in $candidates) {
        # [IO.Path]::Combine rather than Join-Path: Join-Path resolves the drive
        # and throws on a machine without an E:, which is most of them, and
        # $ErrorActionPreference = 'Stop' turns that into a dead script.
        try {
            # An explicit path pointing straight at the flavor folder is an easy
            # mistake to make and a pointless one to fail on.
            $root = $candidate.TrimEnd('\')
            if ((Split-Path $root -Leaf) -match '^_[a-z]+_$') {
                $root = Split-Path $root -Parent
            }
            if (Test-Path ([System.IO.Path]::Combine($root, $Flavor))) { return $root }
        } catch {
            Write-Verbose "Skipping ${candidate}: $($_.Exception.Message)"
        }
    }

    return $null
}

#--------------------------------------------------------------------------------
# GitHub
#--------------------------------------------------------------------------------

function Initialize-Tls {
    # PowerShell 5.1 on an un-patched Windows still negotiates TLS 1.0, which
    # github.com refuses outright. Nothing else in this script is the reason a
    # download fails, so get this out of the way first.
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Could not raise the TLS version: $($_.Exception.Message)"
    }
}

function Get-GitHubJson {
    param([string] $Url)
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers @{
        'Accept'     = 'application/vnd.github+json'
        'User-Agent' = 'install-TankAssist'
    }
    return $response.Content | ConvertFrom-Json
}

function Show-Branches {
    Write-Host ""
    Write-Host "Branches on $Repo" -ForegroundColor Cyan
    Write-Host ""

    $branches = Get-GitHubJson "https://api.github.com/repos/$Repo/branches?per_page=100"
    foreach ($branch in ($branches | Sort-Object name)) {
        $sha = $branch.commit.sha.Substring(0, 7)
        Write-Host ("  {0,-40} {1}" -f $branch.name, $sha)
    }

    Write-Host ""
    Write-Host "  Install one with: .\Install-TankAssist.ps1 -Branch <name>"
    Write-Host ""
}

function Get-RefCommit {
    # Best effort only: it is nice to print the SHA you ended up on, but the
    # unauthenticated API rate limit is 60/hour and running out of it must not
    # stop an install that would otherwise work.
    param([string] $Ref)
    try {
        $commit = Get-GitHubJson "https://api.github.com/repos/$Repo/commits/$Ref"
        return $commit.sha.Substring(0, 7)
    } catch {
        Write-Verbose "Could not resolve $Ref to a commit: $($_.Exception.Message)"
        return $null
    }
}

function Save-RefArchive {
    param([string] $Ref, [string] $Destination)

    # codeload serves branches, tags and raw SHAs, but each wants its own
    # spelling, and a name like claude/icon-zoom-fonts is ambiguous between
    # them. Try each in turn rather than guessing from the shape of the name.
    $urls = @(
        "https://codeload.github.com/$Repo/zip/refs/heads/$Ref",
        "https://codeload.github.com/$Repo/zip/refs/tags/$Ref",
        "https://codeload.github.com/$Repo/zip/$Ref"
    )

    foreach ($url in $urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -Headers @{
                'User-Agent' = 'install-TankAssist'
            }
            return $true
        } catch {
            Write-Verbose "No archive at ${url}: $($_.Exception.Message)"
        }
    }
    return $false
}

#--------------------------------------------------------------------------------
# Install
#--------------------------------------------------------------------------------

function Find-AddonRoot {
    param([string] $ExtractedPath)

    # GitHub names the top folder after the ref, mangling slashes into dashes,
    # so find the addon by its .toc rather than by reconstructing that name.
    $toc = Get-ChildItem -Path $ExtractedPath -Filter "$AddonName.toc" -Recurse -File |
        Sort-Object { $_.FullName.Length } |
        Select-Object -First 1

    if (-not $toc) { return $null }
    return $toc.DirectoryName
}

function Get-TocVersion {
    param([string] $TocPath)
    $line = Select-String -Path $TocPath -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
    if (-not $line) { return 'unknown' }
    return $line.Matches[0].Groups[1].Value.Trim()
}

function Test-WowRunning {
    $running = Get-Process -Name 'Wow', 'WowClassic' -ErrorAction SilentlyContinue
    return ($null -ne $running)
}

function Test-SafeToReplace {
    # Refuse to delete a folder that is not ours. A typo in -WowPath should cost
    # you an error message, not somebody else's addon.
    param([string] $TargetPath)
    if (-not (Test-Path $TargetPath)) { return $true }
    return (Test-Path (Join-Path $TargetPath "$AddonName.toc"))
}

function Install-Addon {
    param([string] $SourcePath, [string] $TargetPath)

    if (Test-Path $TargetPath) {
        Write-Step "Removing the existing install"
        Remove-Item -Path $TargetPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

    $copied = 0
    Get-ChildItem -Path $SourcePath -Force | ForEach-Object {
        if ($ExcludeFromInstall -contains $_.Name) { return }
        Copy-Item -Path $_.FullName -Destination $TargetPath -Recurse -Force
        $copied++
    }
    return $copied
}

#--------------------------------------------------------------------------------
# Main
#--------------------------------------------------------------------------------

Initialize-Tls

if ($List) {
    Show-Branches
    return
}

Write-Host ""
Write-Host "TankAssist installer" -ForegroundColor Cyan
Write-Host ""

$wowRoot = Resolve-WowPath -Explicit $WowPath -Flavor $Flavor
if (-not $wowRoot) {
    Write-Host "  Could not find a World of Warcraft install with a $Flavor folder." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Point at it explicitly:"
    Write-Host "    .\Install-TankAssist.ps1 -WowPath 'D:\Games\World of Warcraft'"
    Write-Host ""
    Write-Host "  Or set it once for this machine:"
    Write-Host "    setx TANKASSIST_WOW_PATH 'D:\Games\World of Warcraft'"
    Write-Host ""
    exit 1
}

$addonsPath = Join-Path (Join-Path $wowRoot $Flavor) 'Interface\AddOns'
if (-not (Test-Path $addonsPath)) {
    # A client that has never been launched has no AddOns folder yet, and
    # creating one is harmless and exactly what is wanted.
    New-Item -ItemType Directory -Path $addonsPath -Force | Out-Null
}
$targetPath = Join-Path $addonsPath $AddonName

# Checked before the download rather than after it: there is no point spending
# the bandwidth on an install that is going to refuse to write.
if (-not (Test-SafeToReplace -TargetPath $targetPath)) {
    Write-Host "  $targetPath already exists, but has no $AddonName.toc in it." -ForegroundColor Red
    Write-Host ""
    Write-Host "  That does not look like a TankAssist install, so this will not replace it."
    Write-Host "  Move or delete it by hand if that is really where you want this."
    Write-Host ""
    exit 1
}

Write-Step "WoW      $wowRoot ($Flavor)"
Write-Step "Ref      $Branch"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TankAssist-install-" + [Guid]::NewGuid().ToString('N'))
# -WhatIf:$false throughout the scratch directory: -WhatIf is about what lands
# in AddOns, and skipping the temp folder only makes the dry run fail to
# download, which tells you nothing useful.
New-Item -ItemType Directory -Path $tempRoot -Force -WhatIf:$false | Out-Null

try {
    $zipPath = Join-Path $tempRoot 'source.zip'

    Write-Step "Downloading ..."
    if (-not (Save-RefArchive -Ref $Branch -Destination $zipPath)) {
        Write-Host ""
        Write-Host "  No branch, tag or commit called '$Branch' on $Repo." -ForegroundColor Red
        Write-Host "  Run with -List to see what is available." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    $extractPath = Join-Path $tempRoot 'extracted'
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -WhatIf:$false

    $addonRoot = Find-AddonRoot -ExtractedPath $extractPath
    if (-not $addonRoot) {
        throw "The downloaded archive has no $AddonName.toc in it. That ref may predate the addon, or the download was truncated."
    }

    $version = Get-TocVersion -TocPath (Join-Path $addonRoot "$AddonName.toc")
    $sha = Get-RefCommit -Ref $Branch

    if (-not $PSCmdlet.ShouldProcess($targetPath, "Install TankAssist $version from $Branch")) {
        Write-Step "Nothing written."
        return
    }

    $copied = Install-Addon -SourcePath $addonRoot -TargetPath $targetPath

    Write-Host ""
    Write-Ok "Installed TankAssist $version"
    if ($sha) {
        Write-Step "from $Branch @ $sha"
    } else {
        Write-Step "from $Branch"
    }
    Write-Step "into $targetPath ($copied items)"
    Write-Host ""

    if (Test-WowRunning) {
        Write-Warn "WoW is running. Restart the client to pick this up --"
        Write-Warn "/reload alone will not, because the .toc is only read at launch."
        Write-Host ""
    }
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
    }
}
