# Publishes a KanePlay release on GitHub, for the update channel of the app.
#
# The installer built by generate-bundle.bat is attached to a new release along
# with update.json, the manifest the app reads at
# https://github.com/Kaynegiordano/KanePlay/releases/latest/download/update.json
# (see DEFAULT_UPDATE_CHANNEL_URL in app/backend/autoupdatechecker.cpp).
#
# Build first:  scripts\build-arch.bat release  then  scripts\generate-bundle.bat release x64
# Then:         powershell -File scripts\publish-release.ps1 -Notes "First line`nSecond line"
#
# -Draft creates the release as a draft, to check it on GitHub before publishing.

param(
    [Parameter(Mandatory = $true)][string]$Notes,
    [string]$Repo = "Kaynegiordano/KanePlay",
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$exe = Join-Path $root "build\deploy-x64-release\KanePlay.exe"
$bundle = Get-ChildItem (Join-Path $root "build\installer-release") -Filter "KanePlaySetup-*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Test-Path $exe) -or $null -eq $bundle) {
    throw "Build KanePlay and its installer first (build-arch.bat, then generate-bundle.bat release x64)"
}

# The full version, build number included, names the release and the installer
$version = (Get-Item $exe).VersionInfo.FileVersion
$staging = Join-Path $root "build\release-$version"
New-Item -ItemType Directory -Force $staging | Out-Null

$installerName = "KanePlaySetup-$version.exe"
$installer = Join-Path $staging $installerName
Copy-Item $bundle.FullName $installer -Force
$sha256 = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()

# Same format as the upstream manifest, plus the fields of the in-app installer.
# URLs are relative to the manifest, so they point at the assets of the same release.
$manifest = @(
    [ordered]@{
        platform = "windows"
        arch = "x86_64"
        version = $version
        browser_url = "https://github.com/$Repo/releases/tag/v$version"
        installer_url = $installerName
        sha256 = $sha256
        notes = $Notes.Replace('`n', "`n")
    }
)
$manifestPath = Join-Path $staging "update.json"
# UTF-8 without BOM
[IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 3), (New-Object Text.UTF8Encoding $false))

Write-Host "Release v$version"
Write-Host "  $installer"
Write-Host "  $manifestPath"

$ghArgs = @("release", "create", "v$version", $installer, $manifestPath, "--repo", $Repo, "--title", "KanePlay $version", "--notes", $manifest[0].notes)
if ($Draft) {
    $ghArgs += "--draft"
}
& gh @ghArgs
if ($LASTEXITCODE -ne 0) {
    throw "gh release create failed"
}
