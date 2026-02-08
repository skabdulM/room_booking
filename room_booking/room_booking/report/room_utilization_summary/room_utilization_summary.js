// Copyright (c) 2026, Abdul Mannan Shaikh and contributors
// For license information, please see license.txt

frappe.query_reports["Room Utilization Summary"] = {
	filters: [
		{
			fieldname: "from_date",
			label: __("From Date"),
			fieldtype: "Date",
			default: frappe.datetime.month_start(),
			reqd: 1,
		},
		{
			fieldname: "to_date",
			label: __("To Date"),
			fieldtype: "Date",
			default: frappe.datetime.get_today(),
			reqd: 1,
		},
		{
			fieldname: "meeting_room",
			label: __("Meeting Room"),
			fieldtype: "Link",
			options: "Meeting Room",
		},
	],
};
