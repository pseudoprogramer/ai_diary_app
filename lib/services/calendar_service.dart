import 'package:device_calendar/device_calendar.dart';

class CalendarService {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> _ensurePermission() async {
    final has = await _plugin.hasPermissions();
    if (has.isSuccess && (has.data ?? false)) return true;
    final req = await _plugin.requestPermissions();
    return req.isSuccess && (req.data ?? false);
  }

  Future<String?> buildTodaySummary() async {
    final events = await fetchTodayEventsLite();
    if (events.isEmpty) return null;

    final parts = <String>[];
    for (final event in events.take(4)) {
      final calendar = event.calendarName.trim().isEmpty ? '' : ' (${event.calendarName})';
      parts.add('${_hhmm(event.start)} ${event.title}$calendar');
    }
    return parts.join(', ');
  }

  Future<List<CalendarEventLite>> fetchTodayEventsLite() async {
    final List<CalendarEventLite> out = [];
    final bool granted = await _ensurePermission();
    if (!granted) return out;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) return out;

    for (final calendar in calendarsResult.data!) {
      final events = await _plugin.retrieveEvents(
        calendar.id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (!events.isSuccess || events.data == null) continue;
      for (final event in events.data!) {
        if (event.start == null) continue;
        final title = (event.title ?? '').trim();
        if (title.isEmpty) continue;
        out.add(
          CalendarEventLite(
            title: title,
            start: event.start!,
            end: event.end,
            calendarId: calendar.id ?? '',
            calendarName: calendar.name ?? '',
            location: event.location,
          ),
        );
      }
    }

    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  String _hhmm(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';
  String _two(int v) => v.toString().padLeft(2, '0');
}

class CalendarEventLite {
  final String title;
  final DateTime start;
  final DateTime? end;
  final String calendarId;
  final String calendarName;
  final String? location;

  const CalendarEventLite({
    required this.title,
    required this.start,
    this.end,
    this.calendarId = '',
    this.calendarName = '',
    this.location,
  });
}
