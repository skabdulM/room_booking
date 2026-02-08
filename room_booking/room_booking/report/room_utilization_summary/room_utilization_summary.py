# Copyright (c) 2026, Abdul Mannan Shaikh and contributors
# For license information, please see license.txt


# room_utilization_summary.py

import frappe


def execute(filters=None):
	columns = get_columns()
	data = get_data(filters)

	chart = get_chart(data)

	return columns, data, None, chart


def get_columns():
	return [
		{
			"label": "Room",
			"fieldname": "meeting_room",
			"fieldtype": "Link",
			"options": "Meeting Room",
			"width": 180,
		},
		{
			"label": "Total Bookings",
			"fieldname": "total_bookings",
			"fieldtype": "Int",
			"width": 120,
		},
		{
			"label": "Total Hours",
			"fieldname": "total_hours",
			"fieldtype": "Float",
			"width": 120,
		},
		{
			"label": "Unique Users",
			"fieldname": "unique_users",
			"fieldtype": "Int",
			"width": 120,
		},
	]


def get_data(filters):
	conditions = get_conditions(filters)

	sql = f"""
        SELECT
            meeting_room,
            COUNT(name) as total_bookings,
            SUM(TIME_TO_SEC(end_time) - TIME_TO_SEC(start_time)) / 3600 as total_hours,
            COUNT(DISTINCT booked_by) as unique_users
        FROM
            `tabRoom Booking`
        WHERE
            status != 'Cancelled'
            {conditions}
        GROUP BY
            meeting_room
        ORDER BY
            total_hours DESC
    """

	return frappe.db.sql(sql, filters, as_dict=True)


def get_conditions(filters):
	conditions = []

	if filters.get("from_date") and filters.get("to_date"):
		conditions.append("AND booking_date BETWEEN %(from_date)s AND %(to_date)s")

	if filters.get("meeting_room"):
		conditions.append("AND meeting_room = %(meeting_room)s")

	return " ".join(conditions)


def get_chart(data):
	if not data:
		return None

	labels = [d.meeting_room for d in data]
	values = [d.total_hours for d in data]

	return {
		"data": {"labels": labels, "datasets": [{"name": "Total Hours", "values": values}]},
		"type": "bar",
	}
