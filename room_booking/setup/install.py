import frappe
from frappe.utils import add_days, getdate


def after_install():
	create_meeting_rooms()
	create_sample_bookings()


def create_meeting_rooms():
	rooms = [
		{
			"room_name": "Conference Room A",
			"capacity": 10,
			"location": "Floor 1",
			"is_active": 1,
			"amenities": "Projector, Whiteboard",
		},
		{
			"room_name": "Conference Room B",
			"capacity": 5,
			"location": "Floor 1",
			"is_active": 1,
			"amenities": "TV Screen",
		},
		{
			"room_name": "Board Room",
			"capacity": 20,
			"location": "Floor 2",
			"is_active": 1,
			"amenities": "Projector, Video Conferencing",
		},
	]

	for room in rooms:
		if not frappe.db.exists("Meeting Room", room["room_name"]):
			doc = frappe.new_doc("Meeting Room")
			doc.update(room)
			doc.insert()
			frappe.db.commit()


def create_sample_bookings():
	if frappe.db.count("Room Booking") > 0:
		return

	today = getdate()
	bookings = [
		{
			"meeting_room": f"MR-{today.strftime('%m')}-{today.strftime('%y')}-001",
			"booking_date": today,
			"start_time": "10:00:00",
			"end_time": "11:00:00",
			"purpose": "Team Standup",
		},
		{
			"meeting_room": f"MR-{today.strftime('%m')}-{today.strftime('%y')}-001",
			"booking_date": today,
			"start_time": "11:00:00",
			"end_time": "12:00:00",
			"purpose": "Project Planning",
		},
		{
			"meeting_room": f"MR-{today.strftime('%m')}-{today.strftime('%y')}-002",
			"booking_date": add_days(today, 1),
			"start_time": "14:00:00",
			"end_time": "15:00:00",
			"purpose": "Client Call",
		},
		{
			"meeting_room": f"MR-{today.strftime('%m')}-{today.strftime('%y')}-002",
			"booking_date": add_days(today, 1),
			"start_time": "09:00:00",
			"end_time": "11:00:00",
			"purpose": "Workshop",
		},
		{
			"meeting_room": f"MR-{today.strftime('%m')}-{today.strftime('%y')}-003",
			"booking_date": add_days(today, 1),
			"start_time": "12:00:00",
			"end_time": "13:30:00",
			"purpose": "Team briefing",
		},
	]

	for booking in bookings:
		doc = frappe.new_doc("Room Booking")
		doc.update(booking)
		doc.insert()
		frappe.db.commit()
