extends Node
## 极简 HTTP 服务，只给服务端面板用：GET 页面 + JSON 接口，短连接。
## 账号数据的来源是 account_server（通过 data_source 调用它的三个 get_* 方法）。

const MAX_REQUEST_BYTES := 32 * 1024
const INDEX_PATH := "res://server/web/index.html"

const STATUS_TEXT := {
	200: "OK",
	204: "No Content",
	400: "Bad Request",
	401: "Unauthorized",
	404: "Not Found",
	405: "Method Not Allowed",
	413: "Payload Too Large",
}

var port := 8080
var bind_address := "127.0.0.1"
## 为空表示不需要密码（默认也只监听 127.0.0.1）
var admin_password := ""
var data_source: Node = null

var _tcp := TCPServer.new()
## peer -> {buffer: PackedByteArray, since: int}
var _clients: Dictionary = {}
var _index_html := ""
var _index_loaded := false

## 请求行迟迟不完整就丢掉，避免连接堆积
const CLIENT_TIMEOUT_MS := 10000


func start(listen_port: int, bind: String, password: String, source: Node) -> Error:
	port = listen_port
	bind_address = bind
	admin_password = password
	data_source = source
	var err := _tcp.listen(port, bind_address)
	if err != OK:
		push_error("[web] 端口 %d 监听失败：%s" % [port, error_string(err)])
	return err


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _tcp != null:
			_tcp.stop()


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		_clients[peer] = {"buffer": PackedByteArray(), "since": Time.get_ticks_msec()}
	var now := Time.get_ticks_msec()
	for peer in _clients.keys():
		if now - int(_clients[peer]["since"]) > CLIENT_TIMEOUT_MS:
			_close(peer)
			continue
		_poll(peer)


func _poll(peer: StreamPeerTCP) -> void:
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_ERROR:
		_close(peer)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return

	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var received := peer.get_partial_data(available)
	if received[0] != OK:
		_close(peer)
		return

	var buffer: PackedByteArray = _clients[peer]["buffer"]
	buffer.append_array(received[1])
	if buffer.size() > MAX_REQUEST_BYTES:
		_send(peer, 413, "text/plain; charset=utf-8", "请求过大")
		_close(peer)
		return

	var header_end := _find_header_end(buffer)
	if header_end < 0:
		_clients[peer]["buffer"] = buffer
		return

	_handle(peer, buffer.slice(0, header_end).get_string_from_utf8())
	_close(peer)


func _find_header_end(buffer: PackedByteArray) -> int:
	for i in range(buffer.size() - 3):
		if buffer[i] == 13 and buffer[i + 1] == 10 and buffer[i + 2] == 13 and buffer[i + 3] == 10:
			return i
	return -1


func _handle(peer: StreamPeerTCP, headers: String) -> void:
	var lines := headers.split("\r\n")
	if lines.is_empty():
		_send(peer, 400, "text/plain; charset=utf-8", "请求格式错误")
		return

	var request := lines[0].split(" ")
	if request.size() < 2:
		_send(peer, 400, "text/plain; charset=utf-8", "请求格式错误")
		return
	var method := request[0].to_upper()
	var raw_path := request[1]

	if !_authorized(lines):
		_send(peer, 401, "text/plain; charset=utf-8", "需要管理员密码",
			{"WWW-Authenticate": "Basic realm=\"server panel\", charset=\"UTF-8\""})
		return

	if method != "GET":
		_send(peer, 405, "text/plain; charset=utf-8", "只支持 GET")
		return

	var path := raw_path
	var query := ""
	var query_index := path.find("?")
	if query_index >= 0:
		query = path.substr(query_index + 1)
		path = path.substr(0, query_index)

	match path:
		"/", "/index.html":
			_send(peer, 200, "text/html; charset=utf-8", _load_index())
		"/api/summary":
			_send_json(peer, data_source.get_summary())
		"/api/accounts":
			_send_json(peer, data_source.get_accounts())
		"/api/account":
			var name := _query_param(query, "name")
			_send_json(peer, data_source.get_account(name))
		"/favicon.ico":
			_send(peer, 204, "text/plain", "")
		_:
			_send(peer, 404, "text/plain; charset=utf-8", "404")


func _authorized(lines: Array) -> bool:
	if admin_password == "":
		return true
	for line in lines:
		var lower := str(line).to_lower()
		if !lower.begins_with("authorization:"):
			continue
		var value := str(line).substr(14).strip_edges()
		if !value.to_lower().begins_with("basic "):
			continue
		var decoded := Marshalls.base64_to_raw(value.substr(6).strip_edges()).get_string_from_utf8()
		var separator := decoded.find(":")
		var password := decoded.substr(separator + 1) if separator >= 0 else decoded
		return password == admin_password
	return false


func _query_param(query: String, key: String) -> String:
	for pair in query.split("&"):
		var parts := pair.split("=")
		if parts.size() >= 2 and _url_decode(parts[0]) == key:
			return _url_decode(parts[1])
		if parts.size() == 1 and _url_decode(parts[0]) == key:
			return ""
	return ""


func _url_decode(text: String) -> String:
	return text.replace("+", " ").uri_decode()


func _load_index() -> String:
	if !_index_loaded:
		_index_loaded = true
		_index_html = FileAccess.get_file_as_string(INDEX_PATH)
		if _index_html.strip_edges() == "":
			_index_html = "<h1>面板文件缺失</h1><p>找不到 %s</p>" % INDEX_PATH
	return _index_html


func _send_json(peer: StreamPeerTCP, data: Dictionary) -> void:
	_send(peer, 200, "application/json; charset=utf-8", JSON.stringify(data))


func _send(peer: StreamPeerTCP, code: int, content_type: String, body: String, extra_headers: Dictionary = {}) -> void:
	var payload := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\n" % [code, STATUS_TEXT.get(code, "OK")]
	head += "Content-Type: %s\r\n" % content_type
	head += "Content-Length: %d\r\n" % payload.size()
	head += "Cache-Control: no-store\r\n"
	head += "Connection: close\r\n"
	for key in extra_headers:
		head += "%s: %s\r\n" % [key, extra_headers[key]]
	head += "\r\n"
	peer.put_data(head.to_utf8_buffer())
	if !payload.is_empty():
		peer.put_data(payload)


func _close(peer: StreamPeerTCP) -> void:
	_clients.erase(peer)
	peer.disconnect_from_host()
