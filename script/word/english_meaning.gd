extends Resource
class_name  EnglishMeaning
enum Type{
	N,
	V,
	VI,
	VT,
	ADJ,
	ADV,
	PREP,
	ABBR,
	NONE
}
@export var type:Type
@export var meaning:String
