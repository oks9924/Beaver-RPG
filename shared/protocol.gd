extends Node
## 클라이언트와 서버가 공유하는 프로토콜 상수. 버전이 맞지 않으면 게임 상태를 보내기 전에 접속을 끊는다.

const PROTOCOL_VERSION: int = 1
const CONTENT_VERSION: String = "0.4.0"
const BUILD_VERSION: String = "0.4.4-terrain"
const DEFAULT_PORT: int = 7777
const MAX_PARTY_SIZE: int = 4

## 연결 상태 (15절)
enum ConnState { DISCONNECTED, CONNECTING, AUTHENTICATING, SYNCING, ONLINE }

## 로그인 후 게임 위치 (15절)
enum Location {
	NONE, HUB, PREPARING_EXPEDITION, LOADING, IN_ROOM, REWARD, ROUTE_VOTE, RESULT,
	JOIN_PENDING, RECONNECTING, SUSPENDED,
}

## 클라이언트 → 서버 신뢰 메시지
enum C {
	HELLO, REGISTER, LOGIN, LOGIN_TOKEN, LOGOUT,
	BOARD_LIST, BOARD_CREATE, BOARD_JOIN, BOARD_LEAVE, READY, BOARD_START,
	ROOM_CHOICE, PING, CHAT,
	REWARD_PICK, ROUTE_VOTE, NODE_ACTION, HUB_UPGRADE,
	MASTERY_TRAIT, BUILD_SELECT, NPC_TALK, QUEST_ACTION, EXPEDITION_PAUSE, MARK,
	EQUIP, GEAR_ACTION,
}

## 서버 → 클라이언트 신뢰 메시지
enum S {
	HELLO_RESULT, AUTH_RESULT, ERROR, KICKED,
	ENTER_HUB, HUB_ROSTER, BOARD_STATE, PARTY_STATE,
	ENTER_EXPEDITION, ROOM_EVENTS, ROOM_RESULT, LEAVE_EXPEDITION,
	PONG, CHAT, ACCOUNT_UPDATE,
	RUN_STATE, REWARD_OFFER, ROUTE_OFFER, NODE_MENU, NOTICE, NPC_DIALOG,
}

## 입력 버튼 비트
const BTN_ATTACK: int = 1
const BTN_DODGE: int = 2
const BTN_Q: int = 4
const BTN_E: int = 8
const BTN_R: int = 16
const BTN_INTERACT: int = 32
const BTN_HEAL: int = 64
const BTN_BUILD: int = 128

## 오류 코드. 클라이언트는 코드별로 다른 안내를 표시한다 (18절).
const ERR_VERSION_MISMATCH := "VERSION_MISMATCH"
const ERR_SERVER_FULL := "SERVER_FULL"
const ERR_ALREADY_ONLINE := "ALREADY_ONLINE"
const ERR_BAD_CREDENTIALS := "BAD_CREDENTIALS"
const ERR_NICK_TAKEN := "NICK_TAKEN"
const ERR_INVALID_NICK := "INVALID_NICK"
const ERR_INVALID_PASSWORD := "INVALID_PASSWORD"
const ERR_REGISTRATION_DISABLED := "REGISTRATION_DISABLED"
const ERR_RATE_LIMITED := "RATE_LIMITED"
const ERR_NOT_AUTHED := "NOT_AUTHED"
const ERR_PARTY_FULL := "PARTY_FULL"
const ERR_EXPEDITION_LIMIT := "EXPEDITION_LIMIT"
const ERR_NO_EXPEDITION := "NO_EXPEDITION"
const ERR_ALREADY_IN_EXPEDITION := "ALREADY_IN_EXPEDITION"
const ERR_NOT_READY := "NOT_READY"
const ERR_BAD_STATE := "BAD_STATE"
const ERR_BAD_CONTENT_ID := "BAD_CONTENT_ID"
const ERR_SAVE_FAILED := "SAVE_FAILED"
const ERR_HELLO_TIMEOUT := "HELLO_TIMEOUT"
const ERR_TOKEN_EXPIRED := "TOKEN_EXPIRED"

## 전투 스냅샷 배열 인덱스 (CombatRoom.snapshot 과 일치해야 한다)
enum SNAP_P { X, Y, FX, FY, HP, STATE, ACTION, DODGE, SHIELD, DOWN_T, CD_Q, CD_E, CD_R, INVULN, RESCUE_T, HEAL, CONNECTED, FRONT_GUARD, ACTION_KIND, RESOURCE, STATUS }
## SNAP_P.STATUS / SNAP_E.STATUS 비트: 1 둔화, 2 속박, 4 방어 약화, 8 가속, 16 회전 공격 중
const ST_SLOW := 1
const ST_ROOT := 2
const ST_VULN := 4
const ST_HASTE := 8
const ST_WHIRL := 16
const ST_ELITE := 32
const ST_BLEED := 64
const ACTION_KIND_CODES := {"": 0, "basic": 1, "q": 2, "e": 3, "r": 4, "heal": 5, "dodge": 6, "rescue": 7, "interact": 8, "grabbed": 9, "whirl": 10}
enum SNAP_E { X, Y, FX, FY, HP, MAX_HP, AI, STATUS }
enum SNAP_TG { TYPE, X, Y, R, REMAINING, TOTAL, DX, DY, W }   # TYPE 0=원 1=직선(길이 R, 폭 W)
enum SNAP_PR { X, Y, VX, VY, R, KIND }                      # KIND 0=적 투사체 1=아군 투사체
enum SNAP_OB { ID, KIND, X, Y, R, PROGRESS, STATE }          # 상호작용물. KIND 는 ObKind
enum ObKind { GNAW_TREE, DEVICE, SLUICE_LEVER, HOLD_ZONE, STRUCTURE, TRAP, VOLLEY, WATER_ZONE, PILLAR, GATE, CLAW_LINK, HUSK, CORRIDOR, ROPE, DEBRIS, ANCHOR, PLATFORM, HAZARD, TURRET, DAM, ROOT_ZONE, FLOOD_ZONE, RAFT,
	LANTERN, SEED, SPORE_NODE, RESONANCE_LOG, FIREFLY, VAT, CRACK, CHANNEL_PIECE, PARASITE, ECHO, VALVE, GAUGE, SECRET, DOOR }
## DOOR 오브젝트 STATE 비트: 0-1 방향(DOOR_DIRS 인덱스), 2-5 목표 방 유형(DOOR_TYPES 인덱스), 6 목표 방 클리어됨, 7 잠김(전투 중), 8-10 문 안에 있는 인원
const DOOR_DIRS := ["n", "e", "s", "w"]
const DOOR_TYPES := ["combat", "elite", "boss", "treasure", "shop", "rest", "event", "start"]

## 플레이어/적 상태
enum EntState { ALIVE, DOWNED, DEAD }
enum Action { IDLE, WINDUP, ACTIVE, RECOVERY, CAST, DODGE, RESCUING, INTERACTING, GRABBED }
enum EnemyAI { IDLE, SEEK, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD, ROOTED, RETREAT }

## 원정 상태
enum ExpState { PREPARING, LOADING, IN_ROOM, RESULT, SUSPENDED, CLOSED, REWARD, ROUTE_VOTE, NODE_MENU }
enum Outcome { NONE, VICTORY, WIPE, ABORTED, SERVER_ERROR }


## `--` 뒤의 사용자 인자를 {key: value} 로 파싱한다. `--server`, `--port=7777`, `--bot=join` 등.
static func parse_user_args() -> Dictionary:
	var out: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var body := a.substr(2)
			var eq := body.find("=")
			if eq >= 0:
				out[body.substr(0, eq)] = body.substr(eq + 1)
			else:
				out[body] = true
	return out


static func version_info() -> Dictionary:
	return {
		"protocol": PROTOCOL_VERSION,
		"content": CONTENT_VERSION,
		"build": BUILD_VERSION,
	}
