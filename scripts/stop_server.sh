#!/usr/bin/env bash
# 전용 서버 정상 종료 요청: 데이터 디렉터리에 STOP 파일을 만들면 서버가 1초 안에 접속자에게 알리고 저장을 플러시한 뒤 종료한다.
# 사용: stop_server.sh [data_dir]
set -euo pipefail
DATA="${1:-$(dirname "$0")/server_data}"
touch "$DATA/STOP"
for i in $(seq 1 20); do
  [ -f "$DATA/STOP" ] || { echo "[stop] server acknowledged stop"; exit 0; }
  sleep 0.5
done
echo "[stop] server did not pick up STOP file within 10s (is it running with data_dir=$DATA?)"; exit 1
