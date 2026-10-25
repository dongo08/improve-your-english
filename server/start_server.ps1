#requires -Version 5.1
<#
.SYNOPSIS
    一键启动 improve your English 的账号服务端（含只读网页面板）。

.DESCRIPTION
    读取 server\server.cfg，找不到会给出提示；命令行参数优先级最高。
    启动前会检查端口是否被占用，启动后在浏览器里打开面板。
    按 Ctrl+C 停止服务端。

.EXAMPLE
    .\start_server.ps1
    .\start_server.ps1 -Port 9000 -WebPort 8080 -AdminPassword 123456
    .\start_server.ps1 -NoBrowser
#>
[CmdletBinding()]
param(
    [int]$Port = 0,
    [int]$WebPort = 0,
    [string]$AdminPassword = "",
    [string]$Data = "",
    [string]$Godot = "",
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

# 控制台切到 UTF-8，Godot 的中文输出才正常。
# 放在这里而不是 .bat 里：cmd 在批处理中途 chcp 会打乱它自己的解析。
try { & chcp.com 65001 > $null } catch { }
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$root = Split-Path -Parent $scriptDir
$configPath = Join-Path $scriptDir "server.cfg"

function Write-Step($text) { Write-Host "[启动] $text" -ForegroundColor Cyan }
function Write-Warn($text) { Write-Host "[注意] $text" -ForegroundColor Yellow }
function Write-Fail($text) { Write-Host "[失败] $text" -ForegroundColor Red }


# ---------------------------------------------------------------- 读取配置

$config = @{
    port           = "9000"
    web_port       = "8080"
    admin_password = ""
    data           = ""
    godot          = ""
    open_panel     = "1"
}

if (Test-Path $configPath) {
    foreach ($rawLine in Get-Content -Path $configPath -Encoding UTF8) {
        $line = $rawLine.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        $index = $line.IndexOf("=")
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim().ToLowerInvariant()
        $value = $line.Substring($index + 1).Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($config.ContainsKey($key)) { $config[$key] = $value }
    }
} else {
    Write-Warn "没有找到 server.cfg，使用默认配置"
}

if ($Port -gt 0) { $config["port"] = "$Port" }
if ($WebPort -gt 0) { $config["web_port"] = "$WebPort" }
if ($PSBoundParameters.ContainsKey("AdminPassword")) { $config["admin_password"] = $AdminPassword }
if ($PSBoundParameters.ContainsKey("Data")) { $config["data"] = $Data }
if ($PSBoundParameters.ContainsKey("Godot")) { $config["godot"] = $Godot }

$serverPort = 0
$webPort = 0
if (-not [int]::TryParse($config["port"], [ref]$serverPort) -or $serverPort -lt 1 -or $serverPort -gt 65535) {
    Write-Fail "server.cfg 里的 port 不是合法端口：$($config['port'])"
    exit 1
}
if (-not [int]::TryParse($config["web_port"], [ref]$webPort) -or $webPort -lt 1 -or $webPort -gt 65535) {
    Write-Fail "server.cfg 里的 web_port 不是合法端口：$($config['web_port'])"
    exit 1
}
if ($serverPort -eq $webPort) {
    Write-Fail "账号端口和面板端口不能相同（都是 $serverPort）"
    exit 1
}

$adminPassword = $config["admin_password"]
$dataPath = $config["data"]
$openPanel = $config["open_panel"] -ne "0" -and -not $NoBrowser


# ---------------------------------------------------------------- 找 Godot

function Resolve-GodotPath {
    param([string]$Explicit, [string]$Configured)

    $candidates = @()
    if ($Explicit) { $candidates += $Explicit }
    if ($Configured) { $candidates += $Configured }
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -Path $candidate -PathType Leaf)) {
            return (Resolve-Path -Path $candidate).Path
        }
    }

    $command = Get-Command godot, godot4, Godot -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -like "*.exe" } | Select-Object -First 1
    if ($command) { return $command.Source }

    $searchRoots = @(
        (Split-Path -Parent $root),
        (Split-Path -Parent (Split-Path -Parent $root)),
        "C:\Program Files",
        "C:\Program Files (x86)",
        (Join-Path $env:LOCALAPPDATA "Programs")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($searchRoot in $searchRoots) {
        $found = @()
        $found += Get-ChildItem -Path $searchRoot -Filter "Godot_v4*-stable_win64*console*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
        if ($found.Count -eq 0) {
            $found += Get-ChildItem -Path $searchRoot -Filter "Godot_v4*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
        }
        if ($found.Count -eq 0) { continue }

        # 按版本号排序，优先用最新的 Godot
        $newest = $found |
            Sort-Object -Property @{ Expression = { Get-GodotVersionFromName $_.Name } } -Descending |
            Select-Object -First 1
        if ($newest) { return $newest.FullName }
    }
    return $null
}

function Get-GodotVersionFromName {
    param([string]$Name)
    $match = [regex]::Match($Name, "Godot_v([0-9]+(?:\.[0-9]+)*)")
    if ($match.Success) {
        try { return [version]$match.Groups[1].Value } catch { }
    }
    return [version]"0.0"
}

$godotPath = Resolve-GodotPath -Explicit $Godot -Configured $config["godot"]
if (-not $godotPath) {
    Write-Fail "找不到 Godot 可执行文件。"
    Write-Host "  办法一：在 server.cfg 里把 godot= 写成完整路径，例如" -ForegroundColor Gray
    Write-Host "          godot=E:/game_program/Godot/Godot_v4.7.2-stable_win64_console.exe" -ForegroundColor Gray
    Write-Host "  办法二：设置环境变量 GODOT_BIN 指向 Godot 可执行文件" -ForegroundColor Gray
    Write-Host "  下载地址：https://godotengine.org/download/windows/" -ForegroundColor Gray
    exit 1
}


# ---------------------------------------------------------------- 检查端口

function Test-PortFree {
    param([int]$TargetPort)
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $TargetPort)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

$busyPorts = @()
foreach ($pair in @(@{ Name = "账号端口"; Value = $serverPort }, @{ Name = "面板端口"; Value = $webPort })) {
    if (-not (Test-PortFree -TargetPort $pair.Value)) { $busyPorts += "$($pair.Name) $($pair.Value)" }
}
if ($busyPorts.Count -gt 0) {
    Write-Fail ("端口被占用：" + ($busyPorts -join "，"))
    Write-Host "  换一个端口：修改 server.cfg 里的 port / web_port，或运行 start_server.bat -Port 9100 -WebPort 8180" -ForegroundColor Gray
    exit 1
}


# ---------------------------------------------------------------- 局域网地址

function Get-AddressPriority {
    param([string]$Address)
    if ($Address.StartsWith("192.168.")) { return 0 }
    if ($Address.StartsWith("10.")) { return 1 }
    if ($Address.StartsWith("172.")) { return 2 }
    return 3
}

function Get-LanAddresses {
    $addresses = @()
    try {
        $addresses = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object {
                $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
                $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback
            } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object {
                $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                -not $_.Address.IPAddressToString.StartsWith("127.") -and
                -not $_.Address.IPAddressToString.StartsWith("169.254.")
            } |
            ForEach-Object { $_.Address.IPAddressToString } |
            Select-Object -Unique
    } catch { }
    # 真实局域网地址通常排在虚拟网卡（Docker/WSL）前面
    return @($addresses | Sort-Object -Property @{ Expression = { Get-AddressPriority $_ } })
}


# ---------------------------------------------------------------- 启动

$lanAddresses = @(Get-LanAddresses)
$lanAddress = if ($lanAddresses.Count -gt 0) { $lanAddresses[0] } else { $null }
$panelUrl = "http://127.0.0.1:$webPort/"
$displayData = if ($dataPath) { $dataPath } else { "user://server/accounts.json（%APPDATA%\Godot\app_userdata\improve your English\server\accounts.json）" }

Write-Host ""
Write-Host "  improve your English · 账号服务端" -ForegroundColor White
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host "  Godot      : $godotPath" -ForegroundColor Gray
Write-Host "  项目目录   : $root" -ForegroundColor Gray
Write-Host "  账号端口   : $serverPort" -ForegroundColor Gray
Write-Host "  面板       : $panelUrl" -ForegroundColor Green
if ($adminPassword) {
    Write-Host "  面板密码   : 已设置（浏览器会弹登录框，用户名随便填）" -ForegroundColor Gray
    if ($lanAddress) { Write-Host "  局域网面板 : http://${lanAddress}:$webPort/" -ForegroundColor Green }
} else {
    Write-Host "  面板密码   : 未设置（只有本机能打开；想对外看请在 server.cfg 填 admin_password）" -ForegroundColor Gray
}
if ($lanAddress) { Write-Host "  客户端填写 : ${lanAddress}:$serverPort" -ForegroundColor Green }
if ($lanAddresses.Count -gt 1) {
    $others = ($lanAddresses | Select-Object -Skip 1) -join "，"
    Write-Host "  其它网卡   : $others（如果上面那个连不上，可以试试这些）" -ForegroundColor DarkGray
}
Write-Host "  数据文件   : $displayData" -ForegroundColor Gray
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host "  按 Ctrl+C 停止服务端" -ForegroundColor DarkGray
Write-Host ""

$godotArgs = @(
    "--headless",
    "--path", $root,
    "res://server/server_main.tscn",
    "--",
    "--port=$serverPort",
    "--web-port=$webPort"
)
if ($adminPassword) { $godotArgs += "--admin-password=$adminPassword" }
if ($dataPath) { $godotArgs += "--data=$dataPath" }

if ($openPanel) {
    # 等服务器把端口监听起来再开浏览器，避免打开的是错误页
    Start-Job -ScriptBlock {
        param($target)
        Start-Sleep -Milliseconds 2200
        Start-Process $target
    } -ArgumentList $panelUrl | Out-Null
}

Push-Location $root
try {
    & $godotPath @godotArgs
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Fail "服务端退出，错误码 $exitCode。往上翻一翻 Godot 的输出。"
} else {
    Write-Host ""
    Write-Step "服务端已停止"
}
exit $exitCode
