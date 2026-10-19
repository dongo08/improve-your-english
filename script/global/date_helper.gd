extends Node


func date_dict_from_unix(unix: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix)


func date_dict_from_system() -> Dictionary:
	return Time.get_datetime_dict_from_system()


func is_same_day(date1: Dictionary, date2: Dictionary) -> bool:
	return date1.get("year", 0) == date2.get("year", 0) \
		and date1.get("month", 0) == date2.get("month", 0) \
		and date1.get("day", 0) == date2.get("day", 0)


func is_same_day_unix(unix1: float, unix2: float) -> bool:
	return is_same_day(date_dict_from_unix(unix1), date_dict_from_unix(unix2))


func is_newer_day(old_date: Dictionary, new_date: Dictionary) -> bool:
	var y1 = old_date.get("year", 0)
	var m1 = old_date.get("month", 0)
	var d1 = old_date.get("day", 0)
	var y2 = new_date.get("year", 0)
	var m2 = new_date.get("month", 0)
	var d2 = new_date.get("day", 0)
	if y1 != y2:
		return y1 < y2
	if m1 != m2:
		return m1 < m2
	return d1 < d2


func is_today(date: Dictionary) -> bool:
	return is_same_day(date, date_dict_from_system())


func is_today_unix(unix: float) -> bool:
	return is_same_day(date_dict_from_unix(unix), date_dict_from_system())


func get_week_start_info(unix_timestamp: int, week_start_day_index: int = 1) -> Dictionary:
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_timestamp)
	var current_weekday: int = dt.weekday

	var days_to_subtract: int = (current_weekday - week_start_day_index + 7) % 7

	var start_of_week_candidate_dict = dt.duplicate()
	start_of_week_candidate_dict.day -= days_to_subtract
	start_of_week_candidate_dict.hour = 0
	start_of_week_candidate_dict.minute = 0
	start_of_week_candidate_dict.second = 0

	var start_of_week_ts: int = Time.get_unix_time_from_datetime_dict(start_of_week_candidate_dict)
	var normalized_start_dt: Dictionary = Time.get_datetime_dict_from_unix_time(start_of_week_ts)

	return {
		"year": normalized_start_dt.year,
		"month": normalized_start_dt.month,
		"day": normalized_start_dt.day
	}


func are_dates_in_same_week(unix_timestamp1: int, unix_timestamp2: int, week_starts_on_monday: bool = true) -> bool:
	var week_start_day_index: int = 1 if week_starts_on_monday else 0

	var start_info1: Dictionary = get_week_start_info(unix_timestamp1, week_start_day_index)
	var start_info2: Dictionary = get_week_start_info(unix_timestamp2, week_start_day_index)

	return start_info1.year == start_info2.year and \
		   start_info1.month == start_info2.month and \
		   start_info1.day == start_info2.day
