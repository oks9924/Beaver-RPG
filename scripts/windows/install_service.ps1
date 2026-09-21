# 관리자 PowerShell 에서 실행. 방화벽에 UDP 포트를 열고, 부팅 시 자동 시작하는 예약 작업(TailExpeditionServer)을 등록한 뒤 바로 시작한다.
# 사용: powershell -ExecutionPolicy Bypass -File install_service.ps1 [-Port 7777] [-Uninstall]
param([int]$Port = 7777, [switch]$Uninstall)
$task = "TailExpeditionServer"
$bat = Join-Path $PSScriptRoot "start_server.bat"
if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  Remove-NetFirewallRule -DisplayName "Tail Expedition UDP $Port" -ErrorAction SilentlyContinue
  Write-Host "[install] removed task and firewall rule"; exit 0
}
if (-not (Get-NetFirewallRule -DisplayName "Tail Expedition UDP $Port" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "Tail Expedition UDP $Port" -Direction Inbound -Protocol UDP -LocalPort $Port -Action Allow | Out-Null
}
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$bat`"" -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Start-ScheduledTask -TaskName $task
Write-Host "[install] task '$task' registered (runs at boot as SYSTEM, restarts on failure) and started. Logs: server_data\logs\"
