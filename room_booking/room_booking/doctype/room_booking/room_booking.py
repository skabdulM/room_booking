# Copyright (c) 2026, Abdul Mannan Shaikh and contributors
# For license information, please see license.txt

from datetime import datetime

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

		# Convert doc times to comparable objects
		booking_start = get_time(self.start_time)
		booking_end = get_time(self.end_time)

		# CHANGED: Use msgprint instead of throw to allow saving
		if booking_start < work_start or booking_end > work_end:
			frappe.msgprint(
				"Note: This booking is outside standard working hours (09:00 AM - 06:00 PM).",
				title="Work Hours Warning",
				indicator="orange",
			)

	def validate_datetime(self):
		if getdate(self.booking_date) < getdate():
			frappe.throw("Booking Date cannot be in the past")

		if self.start_time >= self.end_time:
			frappe.throw("End time must be after start time")

	def check_overlaps(self):
		if not (self.meeting_room and self.booking_date and self.start_time and self.end_time):
			frappe.throw(
				"Meeting Room, Booking Date, Start Time and End Time must be set to check for overlaps"
			)

		filters = {
			"meeting_room": self.meeting_room,
			"booking_date": self.booking_date,
			"status": ["!=", "Cancelled"],
			"name": ["!=", self.name],
		}

		existing = frappe.get_all("Room Booking", filters=filters, fields=["name", "start_time", "end_time"])

		for ex in existing:
			ex_start = get_time_str(ex.start_time)
			ex_end = get_time_str(ex.end_time)
			start_time_str = get_time_str(self.start_time)
			end_time_str = get_time_str(self.end_time)

			if start_time_str < ex_end and end_time_str > ex_start:
				frappe.throw(f"Time overlaps with existing booking {ex.name} ({ex_start} - {ex_end})")


@frappe.whitelist()
def get_available_slots(meeting_room, booking_date):
	WORK_START_STR = get_time("09:00:00")
	WORK_END_STR = get_time("18:00:00")
	SLOT_MINUTES = 60
	booking_date = getdate(booking_date)

	current_time = datetime.combine(booking_date, WORK_START_STR)
	work_end_dt = datetime.combine(booking_date, WORK_END_STR)

	existing_bookings = frappe.get_all(
		"Room Booking",
		filters={"meeting_room": meeting_room, "booking_date": booking_date, "status": ["!=", "Cancelled"]},
		fields=["start_time", "end_time"],
		order_by="start_time asc",
	)

	available_slots = []

	while time_diff_in_seconds(work_end_dt, current_time) >= (SLOT_MINUTES * 60):
		proposed_end = add_to_date(current_time, minutes=SLOT_MINUTES, as_datetime=True)

		overlap_found = False
		next_start_time = None

		for booking in existing_bookings:
			b_start_dt = add_to_date(
				booking_date, seconds=booking.start_time.total_seconds(), as_datetime=True
			)
			b_end_dt = add_to_date(booking_date, seconds=booking.end_time.total_seconds(), as_datetime=True)

			if current_time < b_end_dt and proposed_end > b_start_dt:
				overlap_found = True
				next_start_time = b_end_dt
				break

		if overlap_found:
			current_time = next_start_time
		else:
			available_slots.append(
				{"start": current_time.strftime("%H:%M"), "end": proposed_end.strftime("%H:%M")}
			)
			current_time = add_to_date(current_time, minutes=SLOT_MINUTES, as_datetime=True)

	return available_slots
