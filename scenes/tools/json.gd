extends Node
var word_group:WordGroup=WordGroup.new()
func _ready() -> void:
	#var data_to_send = ["a", "b", "c"]
	var json_file = "res://assets/高中词汇.json"  # 或 "user://save_data.json"
	var file = FileAccess.open(json_file, FileAccess.READ)
	
	if file == null:
		print("Error opening file: ", FileAccess.get_open_error())
		return
	
	# 2. 读取内容并解析
	var json_text = file.get_as_text()
	file.close()  # 记得关闭文件
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		print("JSON 解析错误: ", json.get_error_message())
		return
	
	# 3. 获取解析后的数据（字典或数组）
	var data = json.get_data()
	print(json.data[1])
	for i in json.data:
		var word:Word=Word.new()
		word.English=i.word
		print(json.data.find(i))
		for j in i.translations:
			j=j as Dictionary
			print(j)
			var tran=j.translation.split("；")
			var type:EnglishMeaning.Type
			match j.get("type",""):
				"n":
					type=EnglishMeaning.Type.N
				"v":
					type=EnglishMeaning.Type.V
				"adj":
					type=EnglishMeaning.Type.ADJ
				"adv":
					type=EnglishMeaning.Type.ADV
				"vt":
					type=EnglishMeaning.Type.VT
				"vi":
					type=EnglishMeaning.Type.VI
				"prep":
					type=EnglishMeaning.Type.PREP
				"abbr":
					type=EnglishMeaning.Type.ABBR
				_:
					type=EnglishMeaning.Type.NONE
			for k in tran:
				var mean=EnglishMeaning.new()
				mean.meaning=k
				mean.type=type
				#print(type)
				word.English_meaning_group.push_back(mean)
		word_group.word_group.push_back(word)
	ResourceSaver.save(word_group,"res://assets/new.tres")
