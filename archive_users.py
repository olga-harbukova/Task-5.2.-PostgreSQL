from pymongo import MongoClient
from datetime import datetime, timedelta
import json

# Подключение к MongoDB
client = MongoClient("mongodb://localhost:27017/")
db = client["my_database"]
users = db["user_events"]
archive = db["archived_users"]

today = datetime.now()
old_date = today - timedelta(days=30)
no_activity = today - timedelta(days=14)

old_users = users.find({
    "user_info.registration_date": {"$lt": old_date},
    "event_time": {"$lt": no_activity}
})

old_users_list = list(old_users)
count = len(old_users_list)

print("Старые пользователи:", count)

if count > 0:
    archive.insert_many(old_users_list)
    print("Скопировано в архив:", count)

    users.delete_many({
        "user_info.registration_date": {"$lt": old_date},
        "event_time": {"$lt": no_activity}
    })
    print("Удалено из основной коллекции:", count)

    report = {
        "date": today.strftime("%Y-%m-%d"),
        "archived_users_count": count,
        "archived_user_ids": []
    }

    for user in old_users_list:
        report["archived_user_ids"].append(user["user_id"])

    filename = today.strftime("%Y-%m-%d") + ".json"

    with open(filename, "w") as file:
        json.dump(report, file, indent=2)

    print("Отчёт сохранён в файл:", filename)

else:
    print("Старых пользователей нет")

remaining = users.count_documents({})
print("В основной коллекции осталось:", remaining)