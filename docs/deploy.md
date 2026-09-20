# 서버 운영 (Linux, systemd)

## 권장 구성
- 개발은 GitHub 에서, 서버에는 빌드 결과물만 올린다. 서버에 Godot 편집기나 개발 도구를 두지 않는다.
- 인스턴스 예: t3.small(2 vCPU, 2GB) 또는 t4g.small(arm64 빌드 필요 시 별도 export). 리전 ap-northeast-2. 보안 그룹에 **UDP 7777** 개방, SSH 는 내 IP 만.
- 경로: `/opt/tail-expedition/{current -> vX.Y.Z, server_data, server_config.json, backups}`

## 최초 설치
```bash
sudo apt-get update && sudo apt-get install -y curl tar
sudo curl -fsSL -o /usr/local/bin/tail-deploy https://raw.githubusercontent.com/oks9924/Beaver-RPG/main/scripts/deploy.sh
sudo chmod +x /usr/local/bin/tail-deploy
sudo tail-deploy v0.1.0          # GitHub Release 의 linux-server 묶음을 받아 설치·서비스 등록·시작
sudo nano /opt/tail-expedition/server_config.json   # 정원·월드 이름·가입 허용 등 수정 후
sudo systemctl restart tail-expedition-server
```

## 일상 운영
| 작업 | 명령 |
|---|---|
| 상태·로그 | `systemctl status tail-expedition-server`, `journalctl -u tail-expedition-server -f`, `/opt/tail-expedition/server_data/logs/server-<날짜>.log`, `server_status.json` |
| 업데이트 | `sudo tail-deploy v0.2.0` (배포 전에 자동 백업) |
| 롤백 | `sudo tail-deploy --rollback v0.1.0` |
| 정상 종료 | `sudo systemctl stop tail-expedition-server` (ExecStop 이 STOP 파일을 만들어 저장 플러시 후 종료) |
| 점검 모드 | `server_config.json` 의 `"maintenance": true` 후 재시작 → 신규 접속 거절 |
| 백업 | `bash /opt/tail-expedition/current/backup.sh /opt/tail-expedition/server_data /opt/tail-expedition/backups` (cron 권장) |
| 복구 | 서비스 정지 후 `bash /opt/tail-expedition/current/restore.sh <backup_dir> /opt/tail-expedition/server_data` |

## 설정 항목 (`server_config.json`)
`bind_address`, `port`, `world_id`(비우면 최초 기동 시 생성), `world_name`, `max_online_players`(기본 8), `max_active_expeditions`(기본 2), `allow_registration`, `reconnect_reserved_slots`, `data_dir`, `log_level`, `metrics_interval_sec`, `hello_timeout_sec`, `maintenance`, `login_fail_lockout_sec`, `login_fail_max`, `password_iterations`, `token_ttl_days`. `max_party_size` 는 4 로 고정된다.

테스트·연습용: `debug_route_layers`(N 층만 / -1 마지막 보스만), `debug_boss`(`ironclaw`/`lantern_toad`/`root_king` — 모든 원정이 그 보스방 하나). 명령줄 `--route-layers=`, `--boss=` 로도 준다. 실제 운영 설정에서는 비워 둔다.

## 저장 데이터
- `server_data/accounts.json`, `world.json` — 변경 시마다 임시 파일에 쓰고 rename 으로 교체, 이전본은 `.bak`.
- 손상 시 자동으로 `.bak` 을 읽는다. 별도 백업은 위 스크립트로.
- `expeditions.json` — 안전 지점 체크포인트와 중단(이어하기) 원정. 재시작 시 유예 안의 체크포인트를 복구하고 전투 중이던 방은 마지막 안전 지점부터 다시 한다. 콘텐츠 버전이 바뀌면 이전 체크포인트는 버린다.
- 메트릭 로그의 `snapshot_max` 는 4인 전투 스냅샷의 최대 바이트다. ENet MTU(1392B)를 넘으면 WARN 이 남는다.

## 인터넷 공개 전 확인
- DTLS 미적용: 현재 로그인 정보가 평문 UDP 로 전달된다. 친구끼리 LAN/VPN(예: Tailscale) 사용을 권장하며, 공개 운영 전 DTLS 또는 HTTPS 인증 경로를 추가해야 한다.
- 외부 IP:UDP 포트 접근 가능 여부를 실제 외부 PC 로 확인한다. LAN 성공을 인터넷 검증으로 보고하지 않는다.
