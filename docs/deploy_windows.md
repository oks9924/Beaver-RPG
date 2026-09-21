# 서버 운영 (Windows, AWS EC2)

Linux 절차는 `docs/deploy.md`. 여기서는 **Windows Server EC2 인스턴스**에 전용 서버를 올리는 순서다. 서버 실행 파일은 화면 없이 도는 전용 빌드(`tail-expedition-server.exe`, 로그가 보이는 `tail-expedition-server.console.exe` 동봉)이고, 설정과 저장 데이터는 실행 파일 옆 `server_config.json`, `server_data\` 에 둔다.

## 1. EC2 인스턴스 만들기
- AMI: **Microsoft Windows Server 2022 Base** (또는 2025). 인스턴스 타입 `t3.small`(2 vCPU, 2GB)이면 4인 원정 2개까지 충분하다. `t3.micro`(1GB)는 Windows 자체가 무거워 권장하지 않는다.
- 리전: 친구들이 한국이면 `ap-northeast-2`(서울).
- 키 페어: 새로 만들어 `.pem` 을 보관한다(Windows 관리자 비밀번호 복호화에 쓴다).
- **보안 그룹** (여기서 대부분 막힌다):
  | 유형 | 프로토콜 | 포트 | 소스 |
  |---|---|---|---|
  | 사용자 지정 UDP | UDP | 7777 | 0.0.0.0/0 (친구 IP 만 열려면 그 IP/32) |
  | RDP | TCP | 3389 | 내 IP 만 |
  게임은 **UDP** 만 쓴다. TCP 7777 을 열어도 소용없다.
- 스토리지 30GB gp3 기본값이면 된다.
- 고정 주소가 필요하면 **탄력적 IP** 를 하나 만들어 인스턴스에 연결한다(재부팅해도 IP 유지). 없으면 인스턴스를 중지했다 켤 때마다 IP 가 바뀐다.

## 2. 접속 (RDP)
1. EC2 콘솔 → 인스턴스 선택 → **연결** → **RDP 클라이언트** 탭 → **암호 가져오기** → `.pem` 업로드 → 암호 복호화.
2. Windows 의 "원격 데스크톱 연결"에 퍼블릭 IP, 사용자 `Administrator`, 위 암호로 접속.

## 3. 서버 파일 올리기
1. GitHub Actions 의 최신 성공 빌드(또는 Release)에서 `tail-expedition-server-windows-<버전>.zip` 을 받는다. RDP 안에서 브라우저로 받아도 되고, 로컬 PC 의 파일을 RDP 클립보드로 복사해 붙여 넣어도 된다. (Windows Server 의 IE 보안 강화 구성 때문에 다운로드가 막히면 Server Manager → 로컬 서버 → "IE 보안 강화 구성" 끄기.)
2. `C:\tail-expedition\` 에 압축을 푼다. 폴더 안: `tail-expedition-server.exe`, `tail-expedition-server.console.exe`, `server_config.example.json`, `start_server.bat`, `stop_server.ps1`, `install_service.ps1`, `backup.ps1`, `VERSION`.

## 4. 설정
`server_config.example.json` 을 `server_config.json` 으로 복사해 수정한다(`start_server.bat` 이 없으면 자동 복사한다).
```json
{ "port": 7777, "world_name": "버들둑 마을", "max_online_players": 8, "max_active_expeditions": 2, "allow_registration": true }
```
항목 설명은 `docs/deploy.md` 의 설정 절. `debug_route_layers`, `debug_boss` 는 운영에서 비워 둔다.

## 5. 한 번 손으로 띄워 보기
탐색기에서 `start_server.bat` 더블클릭. 콘솔 창에 `listening on *:7777` 류의 시작 로그가 뜨면 된다. 처음 실행 시 Windows 방화벽 허용 창이 뜨면 **허용**(사설·공용 모두). 창을 닫으면 정상 종료(저장 플러시) 된다.

로컬 PC 클라이언트에서 `<퍼블릭 IP>:7777` 로 접속해 계정을 만들고 마을이 뜨는지 확인한다. 안 되면 순서대로: 보안 그룹 UDP 7777 → Windows 방화벽(아래 스크립트가 규칙을 만든다) → `server_data\logs\server-<날짜>.log`.

## 6. 자동 시작·자동 재시작 등록
관리자 PowerShell:
```powershell
cd C:\tail-expedition
powershell -ExecutionPolicy Bypass -File install_service.ps1 -Port 7777
```
- 방화벽 인바운드 UDP 7777 규칙을 만들고, 부팅 시 SYSTEM 계정으로 `start_server.bat` 을 실행하는 예약 작업 `TailExpeditionServer` 를 등록해 바로 시작한다. 서버가 죽으면 1분 뒤 다시 시작한다.
- 상태: `Get-ScheduledTask TailExpeditionServer | Get-ScheduledTaskInfo`, 로그: `server_data\logs\`, 지표: `server_data\server_status.json`.
- 해제: `install_service.ps1 -Uninstall`.

## 7. 일상 운영
| 작업 | 명령 (PowerShell, `C:\tail-expedition` 에서) |
|---|---|
| 정상 종료 | `powershell -ExecutionPolicy Bypass -File stop_server.ps1` (STOP 파일 → 접속자 알림 → 저장 → 종료. 예약 작업이 1분 뒤 다시 켜므로, 오래 내릴 때는 `Disable-ScheduledTask TailExpeditionServer` 먼저) |
| 시작 | `Start-ScheduledTask TailExpeditionServer` |
| 업데이트 | `stop_server.ps1` → 새 zip 의 exe 2개로 덮어쓰기(`server_config.json`, `server_data\` 는 그대로) → `Start-ScheduledTask TailExpeditionServer` |
| 백업 | `powershell -ExecutionPolicy Bypass -File backup.ps1` (`backups\<시각>\`, 14개 보관). 작업 스케줄러에 하루 1회 등록 권장 |
| 복구 | 서버 정지 → `backups\<시각>\*.json` 을 `server_data\` 에 복사 → 시작 |
| 점검 모드 | `server_config.json` 의 `"maintenance": true` 후 재시작 → 신규 접속 거절 |

## 8. 비용·주의
- t3.small 상시 가동은 월 약 2~3만 원(서울, 온디맨드 + Windows 라이선스). 안 쓸 때 **중지**하면 EBS 요금만 남는다(탄력적 IP 는 중지 중 소액 과금).
- 로그인 정보가 평문 UDP 로 간다(DTLS 미적용). 친구끼리 쓰는 동안은 보안 그룹 소스를 친구 IP 로 제한하는 편이 안전하다.
- Windows 자동 업데이트 재부팅 뒤에도 예약 작업이 서버를 다시 올리지만, 재부팅 시각은 "활성 시간" 밖으로 두는 것이 좋다.
