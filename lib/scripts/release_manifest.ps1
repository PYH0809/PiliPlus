# Uploads <os>.json to a release, after that platform's packages: the app's
# update check reads it from releases/latest/download/<os>.json, so a present
# manifest means the packages are ready. Its SHA-256 values are what let the
# app download the packages through a mirror and still trust them.
#
#   pwsh lib/scripts/release_manifest.ps1 <os> <tag> <package>...
#   pwsh lib/scripts/release_manifest.ps1 -Withdraw <os> <tag>
#
# -Withdraw deletes <os>.json before a rerun replaces the packages, so it
# never points at packages half replaced. Only a release that doesn't exist
# yet (a manual tag) is skipped; any other failure stops the upload.
#
# <os> is Dart's Platform.operatingSystem. The build number comes from
# $env:version (<name>+<code>, set by build.ps1), so it is the one compiled
# into the packages; the note is the release's body.
param(
    [switch]$Withdraw,
    [Parameter(Mandatory)][string]$Os,
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(ValueFromRemainingArguments)][string[]]$Files
)

$ErrorActionPreference = 'Stop'
# gh prints UTF-8; Windows would read it in its ANSI code page
[Console]::OutputEncoding = [Text.Encoding]::UTF8

if ($Withdraw) {
    $names = gh release view $Tag --json assets --jq '.assets[].name' 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ("$names" -match 'release not found') {
            return
        }
        throw "can't read release ${Tag}: $names"
    }
    if ($names -contains "$Os.json") {
        gh release delete-asset $Tag "$Os.json" --yes
        if ($LASTEXITCODE -ne 0) {
            throw "can't delete $Os.json"
        }
    }
    return
}
if (-not $Files) {
    throw 'no packages'
}

if ($env:version -notmatch '\+(\d+)$') {
    throw "no build number in version '$env:version'"
}
$versionCode = [int]$matches[1]

$assets = foreach ($file in $Files) {
    $item = Get-Item -LiteralPath $file
    $asset = [ordered]@{
        name   = $item.Name
        size   = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($Os -eq 'android') {
        # The ABI itself has underscores (x86_64)
        if ($item.Name -notmatch '_(arm64-v8a|armeabi-v7a|x86_64|x86)\.apk$') {
            throw "no ABI in $($item.Name)"
        }
        $asset.abi = $matches[1]
    }
    else {
        $asset.format = if ($item.Name.EndsWith('.tar.gz')) { 'tar.gz' } else { $item.Extension.TrimStart('.') }
    }
    $asset
}

# gh finds a draft by its tag too
$body = gh release view $Tag --json body --jq .body
if ($LASTEXITCODE -ne 0) {
    throw "can't read release $Tag"
}

# The newest published release before this one, for the update dialog's link
# to this version's commits. Android's manifest goes up before publish, the
# others' after it, so "the latest" won't do: take the highest +N below this
# tag's own (a manual build may set a build number above it), never this tag.
$previousTag = $null
$tagCode = if ($Tag -match '\+(\d+)$') { [int]$matches[1] } else { $versionCode }
$tags = gh release list --exclude-drafts --limit 30 --json tagName --jq '.[].tagName'
if ($LASTEXITCODE -eq 0) {
    $previousTag = $tags |
        Where-Object { $_ -ne $Tag -and $_ -match '\+(\d+)$' -and [int]$matches[1] -lt $tagCode } |
        Sort-Object { [int]($_ -replace '^.*\+', '') } |
        Select-Object -Last 1
}

$manifest = [ordered]@{
    tag         = $Tag
    versionCode = $versionCode
    body        = ($body -join "`n")
    # When this platform's packages were ready, which the update dialog shows
    date        = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    previousTag = $previousTag
    assets      = @($assets)
}

$path = Join-Path ([IO.Path]::GetTempPath()) "$Os.json"
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
Get-Content -LiteralPath $path

gh release upload $Tag $path --clobber
if ($LASTEXITCODE -ne 0) {
    throw "can't upload $Os.json"
}
