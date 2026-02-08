# 📅 Room Booking System

A custom Frappe application for managing office meeting room bookings efficiently. This system handles room management, booking transactions, automated conflict detection, and utilization reporting.

## 🌟 Features

* **Meeting Room Management**: Manage rooms with details like Capacity, Amenities, and Location.
* **Smart Booking Engine**:
* **Overlap Prevention**: Automatically detects and prevents conflicting bookings.
* **Capacity Checks**: Warns users if the number of attendees exceeds room capacity.
* **Work Hours Validation**: Ensures bookings are within office hours (09:00 AM - 06:00 PM).
* **Date Validation**: Prevents booking for past dates or invalid time ranges (End Time < Start Time).


* **Role-Based Access**:
* **Office User**: Can view all bookings but only edit/delete their own.
* **System Manager**: Full access to all bookings and reports.


* **Utilization Report**: A script report to analyze room usage, total hours booked, and unique users.
* **Public API**: Whitelisted endpoint to fetch available time slots for external integrations.

## 🛠️ Installation

1. **Get the App**:
```bash
bench get-app room_booking https://github.com/skabdulM/room_booking

```


2. **Install on Site**:
```bash
bench --site [your-site-name] install-app room_booking

```


3. **Migrate (to apply database changes)**:
```bash
bench --site [your-site-name] migrate

```

## 📦 Sample Data (Auto-Created)

To make testing easier, this app runs an `after_install` hook that populates the system with demo data:

* **Meeting Rooms**:
* `Conference Room A` (Capacity: 10, Floor 1)
* `Conference Room B` (Capacity: 5, Floor 1)
* `Board Room` (Capacity: 20, Floor 2)


* **Sample Bookings**:
* Several bookings are created for "Today" and "Tomorrow" to demonstrate the utilization report and overlap logic immediately.

*(Note: If you prefer a clean install, remove the hook in `hooks.py` before installing.)*

## 🚀 Setup & Usage

### 1. Create Meeting Rooms

Navigate to **Meeting Room List** and create your rooms:

* **Room Name**: e.g., "Conference Room A"
* **Capacity**: e.g., 10
* **Is Active**: Checked

### 2. Make a Booking

Navigate to **Room Booking** and create a new booking:

* Select a **Meeting Room** and **Booking Date**.
* Enter **Start Time** and **End Time**.
* The system will automatically validate availability and capacity upon saving.

### 3. Check Availability (Client Script)

On the Room Booking form, click the **"Check Available Slots"** button to see a popup table of all free 1-hour slots for the selected date.

## 📊 Reports

### Room Utilization Summary

* **Path**: `Desk > Reports > Room Utilization Summary`
* **Access**: System Manager only.
* **Filters**: From Date, To Date, Meeting Room (Optional).
* **Columns**: Room, Total Bookings, Total Hours, Unique Users.

## 🔌 API Documentation

The app exposes a whitelisted endpoint to fetch available time slots.

**Endpoint:**
`POST /api/method/room_booking.room_booking.doctype.room_booking.room_booking.get_available_slots`

**Request Parameters:**
| Parameter | Type | Description |
| :--- | :--- | :--- |
| `meeting_room` | String | Name/ID of the Meeting Room |
| `booking_date` | Date | Format: YYYY-MM-DD |

**Response Example:**

```json
{
    "message": [
        {
            "start": "09:00",
            "end": "10:00"
        },
        {
            "start": "13:00",
            "end": "14:00"
        },
        {
            "start": "14:00",
            "end": "15:00"
        }
    ]
}

```

## 🧪 Testing

### Manual Test Cases

1. **Overlap Check**: Try booking a slot that conflicts with an existing booking (e.g., 10:30 - 11:30 when 10:00 - 11:00 is booked). System should throw an error.
2. **Capacity Warning**: Book a room with capacity 5 for 8 attendees. System should show an orange warning.
3. **Permissions**: Log in as a standard user and try to delete a booking created by another user. System should block the action.

## 📜 License

MIT License.
