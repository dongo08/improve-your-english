extends Node
enum GameType{
	ECP,
	QQNA,
	QSPE
}
const GAME_STAMINA_COST = {
	GameType.ECP: 60,
	GameType.QQNA: 40,
	GameType.QSPE: 60,
}

var word_group: WordGroup = load("res://assets/gaozhong.tres")
var answer_area_type: Global.GameType
