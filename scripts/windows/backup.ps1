# 저장 데이터 백업: server_data 를 backups\<날짜시각>\ 로 복사한다 (서버가 켜진 채로 해도 된다. 파일은 rename 으로 교체되므로 온전한 본이 남는다).
# 사용: powershell -ExecutionPolicy Bypass -File backup.ps1 [-DataDir ...] [-BackupRoot ...] [-Keep 14]
param([string]$DataDir = (Join-Path $PSScriptRoot "server_data"), [string]$BackupRoot = (Join-Path $PSScriptRoot "backups"), [int]$Keep = 14)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Get-ChildItem $DataDir -File | Where-Object { $_.Name -match '\.(json|bak)$' } | Copy-Item -Destination $dest
Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -Skip $Keep | Remove-Item -Recurse -Force
Write-Host "[backup] $dest"
