@echo off
rem Tail Expedition 전용 서버 시작 (Windows). 실행 파일 옆의 server_config.json 을 읽고, 데이터는 server_data\ 에 저장한다.
rem 사용: start_server.bat [--port=7777] [--data-dir=D:\tail\server_data] [--log-level=debug]
cd /d "%~dp0"
if not exist server_config.json copy /y server_config.example.json server_config.json >nul
if exist tail-expedition-server.console.exe (
  tail-expedition-server.console.exe %*
) else (
  tail-expedition-server.exe %*
)
