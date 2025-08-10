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
    final bool granted = await _ensurePermission();
    if (!granted) return null;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) return null;

    final List<Event> all = [];
    for (final cal in calendarsResult.data!) {
      final events = await _plugin.retrieveEvents(
        cal.id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (events.isSuccess && events.data != null) {
        all.addAll(events.data!);
      }
    }

    if (all.isEmpty) return null;

    all.sort((a, b) => (a.start?.compareTo(b.start ?? start) ?? 0));
    // Pick up to 2 key events
    final selected = all.take(2).toList();
    final parts = <String>[];
    for (final e in selected) {
      final title = (e.title ?? '이벤트').trim();
      final dt = e.start;
      final timeStr = dt != null ? _hhmm(dt) : '';
      if (timeStr.isNotEmpty) {
        parts.add('$timeStr $title');
      } else {
        parts.add(title);
      }
    }
    return parts.join(', ');
  }

  // Lightweight event model for matching photos around event times
  Future<List<CalendarEventLite>> fetchTodayEventsLite() async {
    final List<CalendarEventLite> out = [];
    final bool granted = await _ensurePermission();
    if (!granted) return out;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) return out;

    for (final cal in calendarsResult.data!) {
      final events = await _plugin.retrieveEvents(
        cal.id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (!events.isSuccess || events.data == null) continue;
      for (final e in events.data!) {
        if (e.start == null) continue;
        out.add(CalendarEventLite(title: (e.title ?? '').trim(), start: e.start!));
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
  const CalendarEventLite({required this.title, required this.start});
}


