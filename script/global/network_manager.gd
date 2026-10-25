extends Node
## 联机房间的网络层。
## 房主 = 服务器，负责保管玩家名单和分数；其他玩家把「我现在的分数」上报给房主，
## 房主再广播给所有人。题目生成、判定、计分都各自在本机跑，所以网络只传几个整数。

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 7 # 房间上限 8 人（含房主）
const DEFAULT_DURATION: float = 60.0

signal players_changed
signal match_started(game_type: int, duration: float)
signal connection_changed
signal network_error(message: String)

## peer_id -> {"name": String, "score": int, "finished": bool}
var players: Dictionary = {}
var my_name: String = ""
var is_online: bool = false
var is_host: bool = false
var in_match: bool = false
var match_game_type: int = 0
var match_duration: float = DEFAULT_DURATION
## 本局玩法设置（由房主决定并同步给所有人）
var match_level: int = Word.Level.PRIMARY
var last_error: String = ""
var connecting: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	if !is_online:
		return 0
	return multiplayer.get_unique_id()


func player_name(id: int) -> String:
	if players.has(id):
		return str(players[id].get("name", "玩家"))
	return "玩家"


func player_score(id: int) -> int:
	if players.has(id):
		return int(players[id].get("score", 0))
	return 0


func player_count() -> int:
	return players.size()


# ---------------------------------------------------------------- 房间


func host_game(port: int = DEFAULT_PORT, player_name: String = "房主") -> Error:
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		last_error = "创建房间失败：端口 %d 可能被占用（错误码 %d）" % [port, err]
		network_error.emit(last_error)
		return err
	multiplayer.multiplayer_peer = peer
	my_name = player_name
	is_online = true
	is_host = true
	in_match = false
	last_error = ""
	players.clear()
	players[1] = _make_player(player_name)
	connection_changed.emit()
	players_changed.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT, player_name: String = "玩家") -> Error:
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "连接 %s:%d 失败（错误码 %d）" % [address, port, err]
		network_error.emit(last_error)
		return err
	multiplayer.multiplayer_peer = peer
	my_name = player_name
	is_online = true
	is_host = false
	in_match = false
	connecting = true
	last_error = ""
	players.clear()
	connection_changed.emit()
	return OK


func leave_game() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	is_online = false
	is_host = false
	in_match = false
	connecting = false
	connection_changed.emit()
	players_changed.emit()


func _make_player(player_name: String) -> Dictionary:
	return {"name": player_name, "score": 0, "finished": false}


# ---------------------------------------------------------------- 连接事件


func _on_peer_connected(_id: int) -> void:
	# 等对方发来名字再入列表，避免列表里出现空名字
	pass


func _on_peer_disconnected(id: int) -> void:
	if !multiplayer.is_server():
		return
	players.erase(id)
	players_changed.emit()
	_broadcast()


func _on_connected_to_server() -> void:
	connecting = false
	is_online = true
	is_host = false
	register_player.rpc_id(1, my_name)
	connection_changed.emit()
	players_changed.emit()


func _on_connection_failed() -> void:
	connecting = false
	last_error = "连接失败：确认房主已创建房间，地址和端口没填错"
	_reset_peer_deferred()
	is_online = false
	is_host = false
	connection_changed.emit()
	network_error.emit(last_error)


func _on_server_disconnected() -> void:
	players.clear()
	is_online = false
	is_host = false
	in_match = false
	connecting = false
	last_error = "房主已离开房间"
	_reset_peer_deferred()
	players_changed.emit()
	connection_changed.emit()
	network_error.emit(last_error)


func _reset_peer_deferred() -> void:
	call_deferred("_reset_peer")


func _reset_peer() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# ---------------------------------------------------------------- 同步


@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if !multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 0:
		return
	players[id] = _make_player(player_name)
	players_changed.emit()
	_broadcast()


@rpc("authority", "call_remote", "reliable")
func sync_players(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	players = state
	players_changed.emit()


func _broadcast() -> void:
	if is_host and is_online and !players.is_empty():
		sync_players.rpc(players)


# ---------------------------------------------------------------- 比赛


func start_match(game_type: int, level: int = Word.Level.PRIMARY, duration: float = DEFAULT_DURATION) -> void:
	if !is_online or !is_host:
		return
	if players.is_empty():
		last_error = "房间里还没有玩家"
		network_error.emit(last_error)
		return
	for id in players.keys():
		players[id]["score"] = 0
		players[id]["finished"] = false
	_broadcast()
	_begin_match.rpc(game_type, duration, level)
	_begin_match(game_type, duration, level)


@rpc("authority", "call_remote", "reliable")
func _begin_match(game_type: int, duration: float, level: int) -> void:
	in_match = true
	match_game_type = game_type
	match_duration = duration
	match_level = level
	players_changed.emit()
	match_started.emit(game_type, duration)


func report_score(value: int) -> void:
	if !is_online or !in_match:
		return
	var clamped := maxi(value, 0)
	if is_host:
		_set_score(1, clamped)
	else:
		submit_score.rpc_id(1, clamped)


@rpc("any_peer", "call_remote", "reliable")
func submit_score(value: int) -> void:
	if !multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 0:
		return
	_set_score(id, value)


func _set_score(id: int, value: int) -> void:
	if !players.has(id):
		return
	if players[id].get("finished", false):
		return
	players[id]["score"] = value
	players_changed.emit()
	_broadcast()


func report_finished(final_score: int) -> void:
	if !is_online:
		return
	var clamped := maxi(final_score, 0)
	if is_host:
		_mark_finished(1, clamped)
	else:
		submit_finished.rpc_id(1, clamped)


@rpc("any_peer", "call_remote", "reliable")
func submit_finished(final_score: int) -> void:
	if !multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 0:
		return
	_mark_finished(id, final_score)


func _mark_finished(id: int, final_score: int) -> void:
	if !players.has(id):
		return
	players[id]["score"] = maxi(final_score, 0)
	players[id]["finished"] = true
	players_changed.emit()
	_broadcast()


## 结算界面点「返回」：退出比赛状态，但不断开连接
func end_match() -> void:
	in_match = false
	players_changed.emit()


## 按分数从高到低排好的名次：[[peer_id, name, score, finished], ...]
func ranking() -> Array:
	var ids := players.keys()
	ids.sort_custom(func(a, b):
		if int(players[a].get("score", 0)) != int(players[b].get("score", 0)):
			return int(players[a].get("score", 0)) > int(players[b].get("score", 0))
		return a < b)
	var result: Array = []
	for id in ids:
		result.append([id, player_name(id), player_score(id), bool(players[id].get("finished", false))])
	return result
