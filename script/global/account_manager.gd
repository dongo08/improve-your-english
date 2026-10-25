extends Node

## 玩家存档管理。新版用 user://players.json 保存，旧版 user://data.tres 会在第一次启动时自动迁移。

const SAVE_PATH := "user://players.json"
const LEGACY_SAVE_PATH := "user://data.tres"
const SCHEMA_VERSION := 2

signal account_changed()

var account_group: AccountSystem = AccountSystem.new()
var current_account: SingleAccount = SingleAccount.new()
## 在线模式下当前账号存在服务器上，本地不再重复保存
var is_online := false
var online_server := ""


func _ready() -> void:
	_load()
	for account in account_group.account_list:
		account.changed.connect(on_account_changed)
	all_account_init()


func _load() -> void:
	if FileAccess.file_exists(SAVE_PATH) and _load_json():
		return
	if ResourceLoader.exists(LEGACY_SAVE_PATH):
		_migrate_legacy()
		_write_json()
		return
	_write_json()


func _load_json() -> bool:
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text.strip_edges() == "":
		return false
	var data = JSON.parse_string(text)
	if data == null or !(data is Dictionary):
		push_error("[account] players.json 解析失败，将重新创建存档")
		return false
	account_group.account_list.clear()
	for entry in data.get("accounts", []):
		if entry is Dictionary:
			account_group.account_list.append(SingleAccount.from_dict(entry))
	return true


func _migrate_legacy() -> void:
	var legacy = ResourceLoader.load(LEGACY_SAVE_PATH)
	if legacy == null or !("account_list" in legacy):
		return
	for old in legacy.account_list:
		var account := SingleAccount.new()
		account.id = old.id
		account.is_formal = old.is_formal
		account.score = old.score
		account.total_score = old.total_score
		account.stamina = old.stamina
		account.max_stamina = old.max_stamina
		account.last_stamina_recovery_unix = old.last_stamina_recovery_unix
		for item in old.bag:
			account.bag.append(item)
		for history in old.playing_history_list:
			account.plays.append(PlayRecord.from_history(history))
		account.total_pp = PPSystem.total_pp(account.plays)
		account_group.account_list.append(account)
	print("[account] 已从旧存档迁移 %d 个账号到 players.json" % account_group.account_list.size())


func _write_json() -> void:
	var accounts: Array = []
	for account in account_group.account_list:
		accounts.append(account.to_dict())
	var payload := {
		"schema": SCHEMA_VERSION,
		"saved_unix": Time.get_unix_time_from_system(),
		"accounts": accounts,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[account] 无法写入 %s（错误码 %d）" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()


func save() -> void:
	var online := get_node_or_null("/root/Online")
	if is_online and online != null:
		online.upload_account(current_account)
	_write_json()


func on_account_changed():
	account_changed.emit()


func add_account(id: String, is_formal: bool = false) -> SingleAccount:
	if !id:
		return null
	# 选择了本地账号，就退出在线模式
	if is_online:
		leave_online()
	for account in account_group.account_list:
		if account.id == id:
			current_account = account
			return account
	var account = SingleAccount.new()
	account.id = id
	account.is_formal = is_formal
	account.changed.connect(on_account_changed)
	account_group.account_list.push_back(account)
	save()
	current_account = account
	return account


## 登录在线账号：数据来自服务器，本地不重复保存
func set_online_account(account: SingleAccount, server: String) -> void:
	current_account = account
	is_online = true
	online_server = server
	if !account.changed.is_connected(on_account_changed):
		account.changed.connect(on_account_changed)
	account_changed.emit()


func leave_online() -> void:
	is_online = false
	online_server = ""
	current_account = SingleAccount.new()
	var online := get_node_or_null("/root/Online")
	if online != null:
		online.close_connection()


func sort_account(from: String = "all"):
	if from == "all":
		account_group.account_list.sort_custom(func(a, b): return a.total_score > b.total_score)
	if from == "normal":
		account_group.account_list.sort_custom(func(a, b): return a.score > b.score)


func has_account_name(name: String) -> bool:
	for account in account_group.account_list:
		if account.id == name:
			return true
	return false


func find_account_from_name(name: String) -> SingleAccount:
	for account in account_group.account_list:
		if account.id == name:
			return account
	return null


func all_account_init():
	for account in account_group.account_list:
		if account.total_score < account.score:
			account.total_score = account.score
		account.total_pp = PPSystem.total_pp(account.plays)
