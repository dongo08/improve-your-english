extends Resource
class_name ScoreHistory
@export var date: Dictionary
@export var total_score: float
@export var score: float
@export var pp: float

func is_new_day(new_date: Dictionary) -> bool:
	return DateHelper.is_newer_day(date, new_date)

func is_new_day_unix(unix: float) -> bool:
	return DateHelper.is_newer_day(date, DateHelper.date_dict_from_unix(unix))
