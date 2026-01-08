from datetime import datetime


def log_event(message) -> None :
	current_date_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
	with open("logs.txt", "a",encoding="utf-8") as file:
		file.write("TIME: " + current_date_time +" MESSAGE:" + message +"\n" )
