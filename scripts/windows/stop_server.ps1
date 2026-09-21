# 전용 서버 정상 종료: 데이터 폴더에 STOP 파일을 만들면 서버가 1초 안에 접속자에게 알리고 저장을 플러시한 뒤 종료한다.
# 사용: powershell -ExecutionPolicy Bypass -File stop_server.ps1 [-DataDir D:\tail\server_data]
param([string]$DataDir = (Join-Path $PSScriptRoot "server_data"))
$stop = Join-Path $DataDir "STOP"
New-Item -ItemType File -Path $stop -Force | Out-Null
for ($i = 0; $i -lt 20; $i++) {
  if (-not (Test-Path $stop)) { Write-Host "[stop] server acknowledged stop"; exit 0 }
  Start-Sleep -Milliseconds 500
}
Write-Host "[stop] server did not pick up STOP within 10s (running? data_dir=$DataDir)"; exit 1
