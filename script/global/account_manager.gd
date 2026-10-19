extends Node

var account_group: AccountSystem = AccountSystem.new()
var current_account: SingleAccount = SingleAccount.new()
signal account_changed()


func _ready() -> void:
	if ResourceLoader.exists("user://data.tres"):
		account_group = ResourceLoader.load("user://data.tres")
	else:
		ResourceSaver.save(account_group, "user://data.tres")
	for i in account_group.account_list:
		i.changed.connect(on_account_changed)
	all_account_init()


func on_account_changed():
	account_changed.emit()


func add_account(id: String, is_formal: bool = false) -> SingleAccount:
	if !id:
		return null
	for i in account_group.account_list:
		if i.id == id:
			current_account = i
			return i
	var account = SingleAccount.new()
	account.id = id
	account.is_formal = is_formal
	account.changed.connect(on_account_changed)
	account_group.account_list.push_back(account)

	ResourceSaver.save(account_group, "user://data.tres")
	current_account = account
	return account


func save():
	ResourceSaver.save(account_group, "user://data.tres")


func sort_account(from: String = "all"):
	if from == "all":
		account_group.account_list.sort_custom(func(a, b): return a.total_score> b.total_score)
	if from == "normal":
		account_group.account_list.sort_custom(func(a, b): return a.score > b.score)


func has_account_name(name: String) -> bool:
	for i in account_group.account_list:
		if i.id == name:
			return true
	return false


func find_account_from_name(name: String) -> SingleAccount:
	for i in account_group.account_list:
		if i.id == name:
			return i
	return null


func all_account_init():
	for account in account_group.account_list:
		if account.total_score < account.score:
			account.total_score = account.score
