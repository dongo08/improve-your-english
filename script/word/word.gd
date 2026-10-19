extends Resource
class_name Word
@export var English:String
@export var Chinese:String
@export var English_meaning_group:Array[EnglishMeaning]

func get_random_meaning(count:int=1)->String:
	if count>=English_meaning_group.size():
		var type:EnglishMeaning.Type=-1
		var a:String
		for j in English_meaning_group:
			if j.type!=type:
				type=j.type
				match type:
					EnglishMeaning.Type.N:
						a+="n."
					EnglishMeaning.Type.V:
						a+="v."
					EnglishMeaning.Type.VI:
						a+="vi."
					EnglishMeaning.Type.VT:
						a+="vt."
					EnglishMeaning.Type.ADJ:
						a+="adj."
					EnglishMeaning.Type.ADV:
						a+="adv."
					EnglishMeaning.Type.PREP:
						a+="prep."
			a+=j.meaning+"；"
		return a.trim_suffix("；")
	else:
		var emgroup:Array[EnglishMeaning]
		var emgdup:=English_meaning_group.duplicate()
		for i in range(count):
			var a=emgdup[randi_range(0,len(emgdup)-1)]
			while emgroup.has(a):
				a=emgdup[randi_range(0,len(emgdup)-1)]
			emgroup.append(a)
			emgdup.erase(a)
		var type:EnglishMeaning.Type=-1
		var a:String
		for j in emgroup:
			if j.type!=type:
				type=j.type
				match type:
					EnglishMeaning.Type.N:
						a+="n."
					EnglishMeaning.Type.V:
						a+="v."
					EnglishMeaning.Type.VI:
						a+="vi."
					EnglishMeaning.Type.VT:
						a+="vt."
					EnglishMeaning.Type.ADJ:
						a+="adj."
					EnglishMeaning.Type.ADV:
						a+="adv."
					EnglishMeaning.Type.PREP:
						a+="prep."
			a+=j.meaning+"；"
		return a.trim_suffix("；")
