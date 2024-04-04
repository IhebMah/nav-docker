﻿$RootPath = $PSScriptRoot
$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$osVersion = [System.Version]'10.0.19042.1889'   # 20H2
$osVersion = [System.Version]'10.0.19041.1415'   # 2004

$isolation = "hyperv"
$filesOnly = $false
$only24 = $false
$image = "bcsql16"
$genericTag = (Get-Content -Raw -Path (Join-Path $RootPath 'tag.txt')).Trim(@(13,10,32))
$created = [DateTime]::Now.ToUniversalTime().ToString("yyyyMMddHHmm")

Write-Host "Using OS Version $osVersion"

if ($only24) {
    $baseimage = "mcr.microsoft.com/windows/servercore:$osVersion"
}
else {
    $baseImage = ""
    $webclient = New-Object System.Net.WebClient
    $basetags = (Get-NavContainerImageTags -imageName "mcr.microsoft.com/dotnet/framework/runtime").tags | Where-Object { $_.StartsWith('4.8-20') } | Sort-Object -Descending  | Where-Object { -not $_.endswith("-1803") }
    $basetags | ForEach-Object {
        if (!($baseImage)) {
            $manifest = (($webclient.DownloadString("https://mcr.microsoft.com/v2/dotnet/framework/runtime/manifests/$_") | ConvertFrom-Json).history[0].v1Compatibility | ConvertFrom-Json)
            Write-Host "$osVersion == $($manifest.'os.version')"
            if ($osVersion -eq $manifest.'os.version') {
                $baseImage = "mcr.microsoft.com/dotnet/framework/runtime:$_"
                Write-Host "$baseImage matches the host OS version"
            }
        }
    }
    if (!($baseImage)) {
        Write-Error "Unable to find a matching mcr.microsoft.com/dotnet/framework/runtime docker image"
    }
}

$dockerfile = Join-Path $RootPath "DOCKERFILE"
if ($only24) {
    $image += "-24"
}
if ($filesOnly) {
    $dockerfile += '-filesonly'
    $image += '-filesonly'
}
docker pull $baseimage
$osversion = docker inspect --format "{{.OsVersion}}" $baseImage

docker images --format "{{.Repository}}:{{.Tag}}" | % { 
    if ($_ -eq $image) 
    {
        docker rmi $image -f
    }
}

docker build --build-arg baseimage=$baseimage `
             --build-arg created=$created `
             --build-arg tag="$genericTag" `
             --build-arg osversion="$osversion" `
             --build-arg filesonly="$filesonly" `
             --build-arg only24="$only24" `
             --isolation=$isolation `
             --memory 64G `
             --tag $image `
             --file $dockerfile `
             $RootPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed with exit code $LastExitCode"
}
else {
    Write-Host "SUCCESS"
}
