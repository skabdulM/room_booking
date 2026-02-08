// Copyright (c) 2026, Abdul Mannan Shaikh and contributors
// For license information, please see license.txt

frappe.ui.form.on("Room Booking", {
	onload: function (frm) {
		if (frm.is_new() && !frm.doc.booked_by) {
			frm.set_value("booked_by", frappe.session.user);
		}
	},

	setup: function (frm) {
		frm.set_query("meeting_room", function () {
			return {
				filters: { is_active: 1 },
			};
		});
	},

	refresh: function (frm) {
		frm.add_custom_button(__("Check Available Slots"), function () {
			if (!frm.doc.meeting_room) {
				frm.set_df_property("meeting_room", "reqd", true);
				frappe.msgprint(__("Please select a Meeting Room."));
				frm.scroll_to_field("meeting_room");
				return;
			}

			if (!frm.doc.booking_date) {
				frm.set_df_property("booking_date", "reqd", true);
				frappe.msgprint(__("Please select Booking Date first."));
				frm.scroll_to_field("booking_date");
				return;
			}

			frappe.call({
				method: "room_booking.room_booking.doctype.room_booking.room_booking.get_available_slots",
				args: {
					meeting_room: frm.doc.meeting_room,
					booking_date: frm.doc.booking_date,
				},
				freeze: true, // Blocks UI while loading
				freeze_message: __("Checking Availability..."),
				callback: function (r) {
					var slots = r.message || [];

					if (!slots.length) {
						frappe.msgprint(__("No available slots for this date."));
						return;
					}

					// 3. Render Table using Template Literals
					// We use standard Frappe classes: table, table-bordered, table-hover
					let table_html = `
                        <div class="table-responsive">
                            <table class="table table-bordered table-hover table-striped">
                                <thead>
                                    <tr>
                                        <th class="text-center">${__("Start Time")}</th>
                                        <th class="text-center">${__("End Time")}</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${slots
										.map(
											(slot) => `
                                        <tr>
                                            <td class="text-center">${slot.start}</td>
                                            <td class="text-center">${slot.end}</td>
                                        </tr>
                                    `
										)
										.join("")}
                                </tbody>
                            </table>
                        </div>
                    `;

					// 4. Show Dialog
					var d = new frappe.ui.Dialog({
						title: __("Available Slots"),
						fields: [
							{
								fieldtype: "HTML",
								fieldname: "slots_table",
								options: table_html, // Inject the table directly
							},
						],
						primary_action_label: __("Close"),
						primary_action: function () {
							d.hide();
						},
					});

					d.show();
				},
			});
		});
	},
});
