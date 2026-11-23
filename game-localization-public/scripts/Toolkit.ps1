[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('init', 'prepare', 'verify')]
    [string]$Action,
    [string]$ToolkitRoot,
    [string]$LockFile,
    [string]$PackageDirectory,
    [string]$ConfigPath,
    [switch]$Offline
)

$ErrorActionPreference = 'Stop'

function Get-LocalPath([string]$Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Read-JsonFile([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-RelativePath([string]$Path) {
    foreach ($part in $Path.Split('/')) {
        if ($part -match '^$|[\\:*?"<>|\x00-\x1F]|[ .]$|^(CON|PRN|AUX|NUL|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])([.]|$)') {
            throw "Invalid relative path: $Path"
        }
    }
}

function Get-ChildPath([string]$BasePath, [string]$RelativePath) {
    $path = $BasePath
    foreach ($part in $RelativePath.Split('/')) {
        $path = [IO.Path]::Combine($path, $part)
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Linked toolkit child path: $path"
        }
    }
    return $path
}

function Assert-Sha256([string]$Value) {
    if ($Value -notmatch '\A[0-9a-fA-F]{64}\z') {
        throw "Invalid SHA-256 in dependency lock: $Value"
    }
}

function Assert-FileHash([string]$Path, [string]$Expected) {
    if (-not [IO.File]::Exists($Path)) {
        throw "Required file is missing: $Path"
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "SHA-256 mismatch: $Path"
    }
}

function Assert-DependencyFiles($Dependency, [string]$Directory) {
    foreach ($file in $Dependency.files) {
        Assert-FileHash (Get-ChildPath $Directory $file.path) $file.sha256
    }
}

function Read-DependencyLock([string]$Path) {
    $manifest = Read-JsonFile $Path
    if ($manifest.schema -ne 1 -or $manifest.dependencies -isnot [array]) {
        throw 'Expected schema 1 and a dependencies array in the project lock.'
    }

    $directories = @()
    foreach ($dependency in $manifest.dependencies) {
        if ([string]::IsNullOrWhiteSpace($dependency.id) -or
            [string]::IsNullOrWhiteSpace($dependency.version) -or
            [string]::IsNullOrWhiteSpace($dependency.license) -or
            $dependency.directory -notmatch '^(tools|profiles|assets)/' -or
            $dependency.files -isnot [array] -or $dependency.files.Count -eq 0) {
            throw 'Each dependency requires id, version, license, directory and files.'
        }
        Assert-RelativePath $dependency.directory
        foreach ($other in $directories) {
            if ($other -eq $dependency.directory -or
                $other.StartsWith($dependency.directory + '/', [StringComparison]::OrdinalIgnoreCase) -or
                $dependency.directory.StartsWith($other + '/', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Overlapping dependency directories: $other and $($dependency.directory)"
            }
        }
        $directories += $dependency.directory

        $paths = @{}
        foreach ($file in $dependency.files) {
            Assert-RelativePath $file.path
            Assert-Sha256 $file.sha256
            if ($paths.ContainsKey($file.path)) {
                throw "Duplicate locked file: $($file.path)"
            }
            $paths[$file.path] = $true
        }

        $source = $dependency.source
        if ($null -ne $source) {
            Assert-RelativePath $source.filename
            Assert-Sha256 $source.sha256
            if ($source.filename.Contains('/') -or $source.format -cnotin @('zip', 'file') -or
                ($source.format -eq 'file' -and $dependency.files.Count -ne 1)) {
                throw "Invalid package source for $($dependency.id)."
            }
            if ($source.url) {
                $uri = [Uri]$source.url
                if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo) {
                    throw "Package URL must use HTTPS without embedded credentials: $($dependency.id)"
                }
            }
        }
    }
    return $manifest
}

function Save-ToolkitConfig([string]$Path, [string]$Root) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $tempPath = $Path + '.' + [Guid]::NewGuid() + '.tmp'
    try {
        $data = @{ schema = 1; toolkitRoot = $Root } | ConvertTo-Json
        [IO.File]::WriteAllText($tempPath, $data)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($tempPath, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($tempPath, $Path)
        }
    } finally {
        [IO.File]::Delete($tempPath)
    }
}

function Install-Dependency($Dependency, [string]$Root, [string]$LocalPackages) {
    $source = $Dependency.source
    if ($null -eq $source) {
        throw "Missing $($Dependency.id) $($Dependency.version). Follow the project's manual dependency steps."
    }

    $target = Get-ChildPath $Root $Dependency.directory
    $cache = Get-ChildPath $Root 'cache'
    $stage = [IO.Path]::Combine($cache, 'stage-' + [Guid]::NewGuid())
    $content = [IO.Path]::Combine($stage, 'content')
    [IO.Directory]::CreateDirectory($content) | Out-Null
    try {
        $archive = [IO.Path]::Combine($stage, 'package')
        $localFile = if ($LocalPackages) { [IO.Path]::Combine($LocalPackages, $source.filename) }
        if ($localFile -and [IO.File]::Exists($localFile)) {
            [IO.File]::Copy($localFile, $archive)
        } elseif ($source.url -and -not $Offline) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $source.url -OutFile $archive
            } catch {
                throw "Download failed for $($source.filename). Supply the package using -PackageDirectory -Offline. $($_.Exception.Message)"
            }
        } else {
            throw "Missing package $($source.filename) for $($Dependency.id) $($Dependency.version)."
        }
        Assert-FileHash $archive $source.sha256

        if ($source.format -eq 'zip') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::OpenRead($archive)
            try {
                foreach ($file in $Dependency.files) {
                    $entry = $zip.GetEntry($file.path)
                    if ($null -eq $entry) {
                        $entry = $zip.GetEntry($file.path.Replace('/', '\'))
                    }
                    if ($null -eq $entry) {
                        throw "Locked file is absent from ZIP: $($file.path)"
                    }
                    $output = Get-ChildPath $content $file.path
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $output)
                }
            } finally {
                $zip.Dispose()
            }
        } else {
            $output = Get-ChildPath $content $Dependency.files[0].path
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
            [IO.File]::Copy($archive, $output)
        }

        Assert-DependencyFiles $Dependency $content
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        try {
            [IO.Directory]::Move($content, $target)
        } catch [IO.IOException] {
            # A concurrent preparation can win the move. Verify its result.
            if (-not [IO.Directory]::Exists($target)) { throw }
            Assert-DependencyFiles $Dependency (Get-ChildPath $Root $Dependency.directory)
        }
    } finally {
        [IO.Directory]::Delete($stage, $true)
    }
}

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $env:LOCALAPPDATA 'game-localization/toolkit.json'
}
$configFile = Get-LocalPath $ConfigPath

if (-not $ToolkitRoot) {
    if ([IO.File]::Exists($configFile)) {
        $settings = Read-JsonFile $configFile
        if ($settings.schema -ne 1 -or [string]::IsNullOrWhiteSpace($settings.toolkitRoot) -or
            -not [IO.Path]::IsPathRooted($settings.toolkitRoot)) {
            throw "Invalid toolkit settings: $configFile"
        }
        $ToolkitRoot = $settings.toolkitRoot
    } elseif ($Action -eq 'init') {
        $ToolkitRoot = Join-Path $env:LOCALAPPDATA 'game-localization/toolkit'
    } else {
        throw 'Toolkit location is unset. Run init or supply -ToolkitRoot.'
    }
}
$root = Get-LocalPath $ToolkitRoot

if ($Action -eq 'init') {
    foreach ($folder in @('tools', 'profiles', 'assets', 'cache')) {
        [IO.Directory]::CreateDirectory((Get-ChildPath $root $folder)) | Out-Null
    }
    Save-ToolkitConfig $configFile $root
    return [pscustomobject]@{ ToolkitRoot = $root; ConfigPath = $configFile }
}

if (-not $LockFile) {
    throw 'Supply the project lock using -LockFile.'
}
if (-not [IO.Directory]::Exists($root)) {
    throw "Toolkit folder is missing. Run init: $root"
}
$manifest = Read-DependencyLock (Get-LocalPath $LockFile)
$localPackages = if ($PackageDirectory) { Get-LocalPath $PackageDirectory }
$missing = @()
foreach ($dependency in $manifest.dependencies) {
    $target = Get-ChildPath $root $dependency.directory
    if ([IO.Directory]::Exists($target)) {
        Assert-DependencyFiles $dependency $target
    } elseif (Test-Path -LiteralPath $target) {
        throw "Toolkit dependency path is not a directory: $target"
    } else {
        $missing += $dependency
    }
}

if ($Action -eq 'verify' -and $missing.Count) {
    $labels = $missing | ForEach-Object { "$($_.id) $($_.version)" }
    throw "Missing locked dependencies: $($labels -join ', ')"
}
foreach ($dependency in $missing) {
    Install-Dependency $dependency $root $localPackages
}
[pscustomobject]@{
    ToolkitRoot = $root
    Dependencies = $manifest.dependencies.Count
    Reused = $manifest.dependencies.Count - $missing.Count
    Prepared = $missing.Count
}
