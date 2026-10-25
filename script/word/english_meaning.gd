extends Resource
class_name EnglishMeaning

## 词性。新增词性只往后追加，保证旧存档 / 旧 .tres 里的数字仍然对应原来的类型。
enum Type {
	N,
	V,
	VI,
	VT,
	ADJ,
	ADV,
	PREP,
	ABBR,
	NONE,
	PRON,
	CONJ,
	NUM,
	ART,
	INT,
	AUX,
}

## 每种词性在界面上显示的缩写
const LABELS := {
	Type.N: "n.",
	Type.V: "v.",
	Type.VI: "vi.",
	Type.VT: "vt.",
	Type.ADJ: "adj.",
	Type.ADV: "adv.",
	Type.PREP: "prep.",
	Type.ABBR: "abbr.",
	Type.PRON: "pron.",
	Type.CONJ: "conj.",
	Type.NUM: "num.",
	Type.ART: "art.",
	Type.INT: "int.",
	Type.AUX: "aux.",
}

## 文本标记 -> 词性，供词库导入使用
const MARKERS := {
	"n": Type.N,
	"v": Type.V,
	"vi": Type.VI,
	"vt": Type.VT,
	"adj": Type.ADJ,
	"a": Type.ADJ,
	"adv": Type.ADV,
	"ad": Type.ADV,
	"prep": Type.PREP,
	"abbr": Type.ABBR,
	"pron": Type.PRON,
	"conj": Type.CONJ,
	"num": Type.NUM,
	"art": Type.ART,
	"int": Type.INT,
	"interj": Type.INT,
	"aux": Type.AUX,
}

## 枚举名 -> 词性，供导入工具使用
const NAME_TO_TYPE := {
	"N": Type.N,
	"V": Type.V,
	"VI": Type.VI,
	"VT": Type.VT,
	"ADJ": Type.ADJ,
	"ADV": Type.ADV,
	"PREP": Type.PREP,
	"ABBR": Type.ABBR,
	"NONE": Type.NONE,
	"PRON": Type.PRON,
	"CONJ": Type.CONJ,
	"NUM": Type.NUM,
	"ART": Type.ART,
	"INT": Type.INT,
	"AUX": Type.AUX,
}

@export var type: Type
@export var meaning: String


static func type_from_marker(marker: String) -> Type:
	return MARKERS.get(marker.to_lower().strip_edges(), Type.NONE)


static func type_from_name(type_name: String) -> Type:
	return NAME_TO_TYPE.get(type_name.strip_edges().to_upper(), Type.NONE)


func pos_label() -> String:
	return LABELS.get(type, "")


## "n.苹果"
func to_text() -> String:
	return pos_label() + meaning


func same_as(other: EnglishMeaning) -> bool:
	return type == other.type and meaning == other.meaning
