extends Node

## 在线模式客户端：负责和账号服务端通信（TCP + 一行一个 JSON）。
## 登录成功后，AccountManager 会把服务器返回的账号设为当前账号，每次保存都会上传。

signal connection_changed(is_connected: bool)
signal upload_finished(ok: bool, message: String)

const DEFAULT_PORT := 9000
const MIN_PASSWORD_LENGTH := 4
const CONNECT_TIMEOUT_MS := 8000
const REQUEST_TIMEOUT_MS := 12000
## 服务端 120 秒没收到数据会回收连接，这里定时 ping 一下保活
const HEARTBEAT_SEC := 45.0
const MAX_UPLOAD_RETRIES := 3

var host := ""
var port := DEFAULT_PORT
var token := ""
var user_name := ""
var connected := false

var _peer: StreamPeerTCP = null
var _buffer := PackedByteArray()
var _next_id := 0
## id -> {done: bool, response: Dictionary}
var _pending: Dictionary = {}
## 待上传的存档：[{"account": Dictionary, "attempts": int}]
var _upload_queue: Array = []
var _uploading := false
var _retry_at_ms := 0
var _heartbeat_accum := 0.0


func _process(delta: float) -> void:
	_poll()
	_pump_uploads()
	_heartbeat(delta)


func _heartbeat(delta: float) -> void:
	if !connected:
		_heartbeat_accum = 0.0
		return
	_heartbeat_accum += delta
	if _heartbeat_accum < HEARTBEAT_SEC:
		return
	_heartbeat_accum = 0.0
	_next_id += 1
	_peer.put_data((JSON.stringify({"op": "ping", "id": _next_id}) + "\n").to_utf8_buffer())


func is_logged_in() -> bool:
	return connected and token != ""


func server_address() -> String:
	return "%s:%d" % [host, port]


# ---------------------------------------------------------------- 连接


func connect_to(address: String, server_port: int) -> Dictionary:
	close_connection()
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(address, server_port)
	if err != OK:
		_peer = null
		return {"ok": false, "error": "无法连接 %s:%d（错误码 %d）" % [address, server_port, err]}

	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		_peer.poll()
		var status := _peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			host = address
			port = server_port
			connected = true
			connection_changed.emit(true)
			return {"ok": true}
		if status == StreamPeerTCP.STATUS_ERROR:
			close_connection()
			return {"ok": false, "error": "连接 %s:%d 失败" % [address, server_port]}
		await get_tree().process_frame

	close_connection()
	return {"ok": false, "error": "连接超时：服务器没响应"}


func close_connection() -> void:
	var was_connected := connected
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	connected = false
	token = ""
	user_name = ""
	_buffer = PackedByteArray()
	for id in _pending.keys():
		var box: Dictionary = _pending[id]
		box.response = {"ok": false, "error": "连接已断开"}
		box.done = true
	_pending.clear()
	# 换账号/断开后不能把上一个账号的存档发出去
	_upload_queue.clear()
	_retry_at_ms = 0
	_heartbeat_accum = 0.0
	if was_connected:
		connection_changed.emit(false)


# ---------------------------------------------------------------- 账号


func login(address: String, server_port: int, name: String, password: String) -> Dictionary:
	var conn := await connect_to(address, server_port)
	if !conn.get("ok", false):
		return conn
	return await _authenticate("login", name, password)


func register(address: String, server_port: int, name: String, password: String) -> Dictionary:
	var conn := await connect_to(address, server_port)
	if !conn.get("ok", false):
		return conn
	return await _authenticate("register", name, password)


func _authenticate(op: String, name: String, password: String) -> Dictionary:
	var response := await _request({"op": op, "name": name, "password": password})
	if response.get("ok", false):
		token = str(response.get("token", ""))
		user_name = str(response.get("account", {}).get("id", name))
	return response


## 保存账号时调用：排队上传，避免连续保存造成并发
func upload_account(account: SingleAccount) -> void:
	if !is_logged_in() or account == null:
		return
	_upload_queue.append({"account": account.to_dict(), "attempts": 0})


func _pump_uploads() -> void:
	if _uploading or _upload_queue.is_empty() or !is_logged_in():
		return
	if Time.get_ticks_msec() < _retry_at_ms:
		return
	_uploading = true
	var item: Dictionary = _upload_queue.pop_front()
	var response := await _request({"op": "upload", "token": token, "account": item["account"]})
	_uploading = false

	if response.get("ok", false):
		upload_finished.emit(true, "")
		return

	item["attempts"] = int(item.get("attempts", 0)) + 1
	var message := str(response.get("error", "上传失败"))
	if int(item["attempts"]) < MAX_UPLOAD_RETRIES:
		# 放回队首，等一会儿再试，避免这一局的成绩直接丢掉
		_upload_queue.push_front(item)
		_retry_at_ms = Time.get_ticks_msec() + 2000 * int(item["attempts"])
		push_warning("[online] 上传存档失败（第 %d 次），将重试：%s" % [item["attempts"], message])
	else:
		_retry_at_ms = 0
		upload_finished.emit(false, message)
		push_warning("[online] 上传存档失败，已重试 %d 次：%s" % [MAX_UPLOAD_RETRIES, message])


func fetch_leaderboard(limit: int = 20) -> Dictionary:
	if !is_logged_in():
		return {"ok": false, "error": "未登录"}
	return await _request({"op": "leaderboard", "token": token, "limit": limit})


func fetch_profile() -> Dictionary:
	if !is_logged_in():
		return {"ok": false, "error": "未登录"}
	return await _request({"op": "profile", "token": token})


## 立即上传一次（测试和手动同步用），返回服务器的响应
func push_account(account: SingleAccount) -> Dictionary:
	if !is_logged_in():
		return {"ok": false, "error": "未登录"}
	if account == null:
		return {"ok": false, "error": "账号为空"}
	return await _request({"op": "upload", "token": token, "account": account.to_dict()})


# ---------------------------------------------------------------- 协议


func _request(payload: Dictionary) -> Dictionary:
	if !connected or _peer == null:
		return {"ok": false, "error": "未连接服务器"}
	_next_id += 1
	var request_id := _next_id
	payload["id"] = request_id
	var err := _peer.put_data((JSON.stringify(payload) + "\n").to_utf8_buffer())
	if err != OK:
		return {"ok": false, "error": "发送失败（错误码 %d）" % err}

	var box := {"done": false, "response": {}, "deadline": Time.get_ticks_msec() + REQUEST_TIMEOUT_MS}
	_pending[request_id] = box
	while !box.done and Time.get_ticks_msec() < box.deadline:
		if !connected:
			break
		await get_tree().process_frame
	_pending.erase(request_id)
	if !box.done:
		if !connected:
			return {"ok": false, "error": "连接已断开"}
		return {"ok": false, "error": "服务器无响应"}
	return box.response


func _poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if connected:
			connected = false
			connection_changed.emit(false)
			for id in _pending.keys():
				var box: Dictionary = _pending[id]
				box.response = {"ok": false, "error": "连接已断开"}
				box.done = true
		return

	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var received := _peer.get_partial_data(available)
	if received[0] != OK:
		return
	_buffer.append_array(received[1])

	var start := 0
	for i in range(_buffer.size()):
		if _buffer[i] != 10: # '\n'
			continue
		var line := _buffer.slice(start, i).get_string_from_utf8()
		start = i + 1
		if line.strip_edges() != "":
			_handle_line(line)
	_buffer = _buffer.slice(start)


func _handle_line(line: String) -> void:
	var data = JSON.parse_string(line)
	if data == null or !(data is Dictionary):
		return
	var request_id := int(data.get("id", -1))
	if _pending.has(request_id):
		var box: Dictionary = _pending[request_id]
		box.response = data
		box.done = true
