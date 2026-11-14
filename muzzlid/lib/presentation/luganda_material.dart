import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Draft Luganda for the Android Material controls used by this app.
class LugandaMaterial extends DefaultMaterialLocalizations {
  const LugandaMaterial();
  static const months = [
    'Janwali',
    'Febwali',
    'Maaki',
    'Apuli',
    'Maayi',
    'Juuni',
    'Julaayi',
    'Agusito',
    'Sebutemba',
    'Okitobba',
    'Novemba',
    'Desemba'
  ];
  static const weekdays = [
    'Bbalaza',
    'Lwakubiri',
    'Lwakusatu',
    'Lwakuna',
    'Lwakutaano',
    'Lwamukaaga',
    'Ssande'
  ];
  @override
  String get backButtonTooltip => 'Ddayo';
  @override
  String get closeButtonTooltip => 'Ggalawo';
  @override
  String get nextMonthTooltip => 'Omwezi oguddako';
  @override
  String get previousMonthTooltip => 'Omwezi oguwedde';
  @override
  String get showMenuTooltip => 'Laga olukalala';
  @override
  String get cancelButtonLabel => 'Sazaamu';
  @override
  String get closeButtonLabel => 'Ggalawo';
  @override
  String get continueButtonLabel => 'Genda mu maaso';
  @override
  String get okButtonLabel => 'Kale';
  @override
  String get saveButtonLabel => 'Tereka';
  @override
  String get copyButtonLabel => 'Koppa';
  @override
  String get cutButtonLabel => 'Salawo';
  @override
  String get pasteButtonLabel => 'Teekawo';
  @override
  String get selectAllButtonLabel => 'Londa byonna';
  @override
  String get searchFieldLabel => 'Noonya';
  @override
  String get currentDateLabel => 'Leero';
  @override
  String get selectedDateLabel => 'Olunaku olulondeddwa';
  @override
  String get dateHelpText => 'dd/mm/yyyy';
  @override
  String get dateInputLabel => 'Wandiika olunaku';
  @override
  String get datePickerHelpText => 'Londa olunaku';
  @override
  String get selectYearSemanticsLabel => 'Londa omwaka';
  @override
  String get invalidDateFormatLabel => 'Enkola y’olunaku si ntuufu.';
  @override
  String get dateOutOfRangeLabel => 'Olunaku luno terukkirizibwa.';
  @override
  String get inputDateModeButtonLabel => 'Wandiika olunaku';
  @override
  String get calendarModeButtonLabel => 'Laga kalenda';
  @override
  String get modalBarrierDismissLabel => 'Ggalawo';
  @override
  List<String> get narrowWeekdays => ['Ss', 'B', 'K', 'S', 'N', 'T', 'M'];
  @override
  String formatCompactDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  @override
  String formatShortDate(DateTime date) =>
      '${date.day} ${months[date.month - 1]} ${date.year}';
  @override
  String formatMediumDate(DateTime date) =>
      '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  @override
  String formatFullDate(DateTime date) =>
      '${weekdays[date.weekday - 1]}, ${formatShortDate(date)}';
  @override
  String formatMonthYear(DateTime date) =>
      '${months[date.month - 1]} ${date.year}';
  @override
  String formatShortMonthDay(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';
  @override
  DateTime? parseCompactDate(String? inputString) {
    if (inputString == null) return null;
    final parts = inputString.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]),
        month = int.tryParse(parts[1]),
        year = int.tryParse(parts[2]);
    if (day == null ||
        month == null ||
        year == null ||
        year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}

class LugandaMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const LugandaMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const LugandaMaterial());
  @override
  bool shouldReload(LugandaMaterialDelegate old) => false;
}

class LugandaWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const LugandaWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture(const DefaultWidgetsLocalizations());
  @override
  bool shouldReload(LugandaWidgetsDelegate old) => false;
}

// Android uses Material controls; keep the unused Cupertino delegate available
// for framework compatibility without claiming a separate iOS translation.
class LugandaCupertinoFallback
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const LugandaCupertinoFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture(const DefaultCupertinoLocalizations());
  @override
  bool shouldReload(LugandaCupertinoFallback old) => false;
}
