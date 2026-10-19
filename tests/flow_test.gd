extends Node
## 端到端流程测试的入口：真正的断言放在 root 下的常驻节点里，
## 这样大厅切换场景时（它会替换 current_scene）不会被一起释放。

func _ready() -> void:
	var reporter: Node = preload("res://tests/flow_reporter.gd").new()
	get_tree().root.add_child.call_deferred(reporter)
