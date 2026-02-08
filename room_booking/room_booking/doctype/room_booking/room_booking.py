# Copyright (c) 2026, Abdul Mannan Shaikh and contributors
# For license information, please see license.txt

from datetime import datetime, timedelta

import frappe
from frappe.model.document import Document
from frappe.utils import add_to_date, get_time, get_time_str, getdate, time_diff_in_seconds


class RoomBooking(Document):
	def validate(self):
		if not self.booked_by:
			self.booked_by = frappe.session.user

		self.validate_room_and_capacity()
		self.validate_datetime()
		self.validate_working_hours()
		self.check_overlaps()

	def validate_room_and_capacity(self):
		if not self.meeting_room:
			return

		room_data = frappe.db.get_value(
			"Meeting Room", self.meeting_room, ["is_active", "capacity"], as_dict=True
		)

		if not room_data:
			frappe.throw("Meeting Room not found")

		if not room_data.is_active:
			frappe.throw("Selected meeting room is currently not available for booking")

		capacity = room_data.capacity or 0
		if self.attendees and self.attendees > capacity:
			frappe.msgprint(
				f"Number of attendees {self.attendees} exceeds room capacity {capacity}",
				title="Capacity Warning",
				indicator="orange",
			)

	def validate_working_hours(self):
		work_start = get_time("09:00:00")
		work_end = get_time("18:00:00")

		booking_start = get_time(self.start_time)
		booking_end = get_time(self.end_time)

		if booking_start < work_start or booking_end > work_end:
			frappe.msgprint(
				"Note: This booking is outside standard working hours (09:00 AM - 06:00 PM).",
				title="Work Hours Warning",
				indicator="orange",
			)

	def validate_datetime(self):
		if getdate(self.booking_date) < getdate():
			frappe.throw("Booking Date cannot be in the past")

		start_time = get_time(self.start_time)
		end_time = get_time(self.end_time)

		if start_time >= end_time:
			frappe.throw("End time must be after start time")

	def check_overlaps(self):
		if not (self.meeting_room and self.booking_date and self.start_time and self.end_time):
			frappe.throw(
				"Meeting Room, Booking Date, Start Time and End Time must be set to check for overlaps"
			)

		def get_dt(date_val, time_val):
			date_obj = getdate(date_val)
			time_obj = get_time(time_val)
			return datetime.combine(date_obj, time_obj)

		current_start_dt = get_dt(self.booking_date, self.start_time)
		current_end_dt = get_dt(self.booking_date, self.end_time)

		filters = {
			"meeting_room": self.meeting_room,
			"booking_date": self.booking_date,
			"status": ["!=", "Cancelled"],
			"name": ["!=", self.name],
		}

		existing = frappe.get_all(
			"Room Booking", filters=filters, fields=["name", "start_time", "end_time", "booked_by"]
		)

		for ex in existing:
			ex_start_dt = get_dt(self.booking_date, ex.start_time)
			ex_end_dt = get_dt(self.booking_date, ex.end_time)

			if current_start_dt < ex_end_dt and current_end_dt > ex_start_dt:
				formatted_start = ex_start_dt.strftime("%I:%M %p")
				formatted_end = ex_end_dt.strftime("%I:%M %p")

				frappe.throw(
					f"This room is already booked from <b>{formatted_start}</b> to <b>{formatted_end}</b> by {ex.booked_by}.<br>Please choose a different time.",  # noqa: RUF100
					title="Slot Unavailable",
				)


@frappe.whitelist()
def get_available_slots(meeting_room, booking_date):
	WORK_START_STR = "09:00:00"
	WORK_END_STR = "18:00:00"
	DURATION_MINUTES = 60

	booking_date = getdate(booking_date)

	work_start_dt = datetime.combine(booking_date, get_time(WORK_START_STR))
	work_end_dt = datetime.combine(booking_date, get_time(WORK_END_STR))

	bookings_data = frappe.get_all(
		"Room Booking",
		filters={"meeting_room": meeting_room, "booking_date": booking_date, "status": ["!=", "Cancelled"]},
		fields=["start_time", "end_time"],
		order_by="start_time asc",
	)

	existing_bookings = []
	for b in bookings_data:
		existing_bookings.append(
			{
				"start": datetime.combine(booking_date, get_time(b.start_time)),
				"end": datetime.combine(booking_date, get_time(b.end_time)),
			}
		)

	available_slots = []
	current_time = work_start_dt

	while current_time < work_end_dt:
		proposed_end = add_to_date(current_time, minutes=DURATION_MINUTES)

		if proposed_end > work_end_dt:
			break

		is_available = True
		earliest_blocking_end = None

		for booking in existing_bookings:
			if current_time < booking["end"] and proposed_end > booking["start"]:
				is_available = False
				if earliest_blocking_end is None or booking["end"] < earliest_blocking_end:
					earliest_blocking_end = booking["end"]

		if is_available:
			available_slots.append(
				{"start": current_time.strftime("%H:%M"), "end": proposed_end.strftime("%H:%M")}
			)
			current_time = proposed_end
		else:
			current_time = earliest_blocking_end

	return available_slots
