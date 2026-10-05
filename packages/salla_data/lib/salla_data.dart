library salla_data;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' as firebase;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const String sallaCourierServiceImmediate = 'immediate';
const String sallaCourierServiceFlexibleSixHours = 'scheduled_flexible_6h';
const String sallaCourierServiceNextDayTwelveHours = 'scheduled_next_day_12h';
const String sallaDriverShiftScheduleVersion = 'salla_driver_shift_schedule_v1';
const String sallaDriverShiftTimeZone = 'Asia/Baghdad';
const List<String> sallaDriverShiftDayIds = <String>[
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];
const Map<String, String> sallaDriverShiftDayNames = <String, String>{
  'sat': 'السبت',
  'sun': 'الأحد',
  'mon': 'الاثنين',
  'tue': 'الثلاثاء',
  'wed': 'الأربعاء',
  'thu': 'الخميس',
  'fri': 'الجمعة',
};

class SallaDriverShiftPreset {
  final String id;
  final String label;
  final int startMinute;
  final int endMinute;

  const SallaDriverShiftPreset({
    required this.id,
    required this.label,
    required this.startMinute,
    required this.endMinute,
  });
}

const List<SallaDriverShiftPreset> sallaDriverShiftPresets =
    <SallaDriverShiftPreset>[
  SallaDriverShiftPreset(
    id: 'morning',
    label: 'صباحي',
    startMinute: 8 * 60,
    endMinute: 16 * 60,
  ),
  SallaDriverShiftPreset(
    id: 'evening',
    label: 'مسائي',
    startMinute: 16 * 60,
    endMinute: 0,
  ),
  SallaDriverShiftPreset(
    id: 'night',
    label: 'ليلي',
    startMinute: 0,
    endMinute: 8 * 60,
  ),
];

class SallaDriverShiftEvaluation {
  final bool restricted;
  final bool active;
  final DateTime? nextStartBaghdad;

  const SallaDriverShiftEvaluation({
    required this.restricted,
    required this.active,
    this.nextStartBaghdad,
  });
}

class SallaDriverShiftSchedule {
  final bool enabled;
  final String templateId;
  final String label;
  final String timeZone;
  final Set<String> days;
  final int startMinute;
  final int endMinute;

  const SallaDriverShiftSchedule({
    this.enabled = false,
    this.templateId = 'custom',
    this.label = 'دوام مرن',
    this.timeZone = sallaDriverShiftTimeZone,
    this.days = const <String>{},
    this.startMinute = 8 * 60,
    this.endMinute = 16 * 60,
  });

  factory SallaDriverShiftSchedule.fromValue(Object? rawValue) {
    if (rawValue is! Map) return const SallaDriverShiftSchedule();
    final value = rawValue.map(
      (key, item) => MapEntry(key.toString(), item),
    );
    if (value['enabled'] != true) return const SallaDriverShiftSchedule();
    final rawDays = value['days'];
    final days = <String>{};
    if (rawDays is Map) {
      for (final entry in rawDays.entries) {
        final dayId = entry.key.toString().trim();
        if (entry.value == true && sallaDriverShiftDayIds.contains(dayId)) {
          days.add(dayId);
        }
      }
    } else if (rawDays is List) {
      for (final item in rawDays) {
        final dayId = item?.toString().trim() ?? '';
        if (sallaDriverShiftDayIds.contains(dayId)) days.add(dayId);
      }
    }
    final startMinute = int.tryParse(
          value['startMinute']?.toString() ?? '',
        ) ??
        -1;
    final endMinute = int.tryParse(value['endMinute']?.toString() ?? '') ?? -1;
    final timeZone = value['timeZone']?.toString().trim() ?? '';
    final valid = days.isNotEmpty &&
        startMinute >= 0 &&
        startMinute < 1440 &&
        endMinute >= 0 &&
        endMinute < 1440 &&
        startMinute != endMinute &&
        (timeZone.isEmpty || timeZone == sallaDriverShiftTimeZone);
    if (!valid) {
      return const SallaDriverShiftSchedule(
        enabled: true,
        label: 'شفت غير صالح',
      );
    }
    final templateId = value['templateId']?.toString().trim() ?? 'custom';
    final rawLabel = value['label']?.toString().trim() ?? '';
    return SallaDriverShiftSchedule(
      enabled: true,
      templateId:
          <String>{'morning', 'evening', 'night', 'custom'}.contains(templateId)
              ? templateId
              : 'custom',
      label: rawLabel.isEmpty ? 'شفت مخصص' : rawLabel,
      days: Set<String>.unmodifiable(days),
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  /// Administrative work-hour information. Driver consumers deliberately keep
  /// using fromValue, where enabled=false remains unrestricted on old builds.
  factory SallaDriverShiftSchedule.fromAdminValue(Object? rawValue) {
    if (rawValue is! Map) return const SallaDriverShiftSchedule();
    return SallaDriverShiftSchedule.fromValue(<Object?, Object?>{
      ...rawValue,
      'enabled': rawValue['configured'] == true || rawValue['enabled'] == true,
    });
  }

  bool get isValid =>
      !enabled ||
      (days.isNotEmpty &&
          startMinute >= 0 &&
          startMinute < 1440 &&
          endMinute >= 0 &&
          endMinute < 1440 &&
          startMinute != endMinute &&
          timeZone == sallaDriverShiftTimeZone);

  Map<String, dynamic> toFirebase() {
    if (!enabled) {
      return <String, dynamic>{
        'version': sallaDriverShiftScheduleVersion,
        'enabled': false,
        'configured': false,
        'timeZone': sallaDriverShiftTimeZone,
        'templateId': 'custom',
        'label': 'دوام مرن',
        'days': <String, bool>{},
        'startMinute': 8 * 60,
        'endMinute': 16 * 60,
      };
    }
    if (!isValid) {
      throw StateError('جدول شفت السائق غير صالح.');
    }
    return <String, dynamic>{
      'version': sallaDriverShiftScheduleVersion,
      'enabled': false,
      'configured': true,
      'timeZone': sallaDriverShiftTimeZone,
      'templateId': templateId,
      'label': label.trim().isEmpty ? 'شفت مخصص' : label.trim(),
      'days': <String, bool>{
        for (final dayId in sallaDriverShiftDayIds)
          if (days.contains(dayId)) dayId: true,
      },
      'startMinute': startMinute,
      'endMinute': endMinute,
    };
  }

  SallaDriverShiftEvaluation evaluate(DateTime now) {
    if (!enabled) {
      return const SallaDriverShiftEvaluation(
        restricted: false,
        active: true,
      );
    }
    if (!isValid) {
      return const SallaDriverShiftEvaluation(
        restricted: true,
        active: false,
      );
    }
    final baghdadNow = now.toUtc().add(const Duration(hours: 3));
    final currentDayId = _sallaDriverShiftDayId(baghdadNow.weekday);
    final previousDayId = _sallaDriverShiftDayId(
      baghdadNow.subtract(const Duration(days: 1)).weekday,
    );
    final minuteOfDay = baghdadNow.hour * 60 + baghdadNow.minute;
    final active = startMinute < endMinute
        ? days.contains(currentDayId) &&
            minuteOfDay >= startMinute &&
            minuteOfDay < endMinute
        : (days.contains(currentDayId) && minuteOfDay >= startMinute) ||
            (days.contains(previousDayId) && minuteOfDay < endMinute);
    return SallaDriverShiftEvaluation(
      restricted: true,
      active: active,
      nextStartBaghdad: active ? null : _nextStartFromBaghdad(baghdadNow),
    );
  }

  String get timeLabel => '${sallaDriverShiftMinuteLabel(startMinute)} – '
      '${sallaDriverShiftMinuteLabel(endMinute)}';

  String get daysLabel {
    if (!enabled) return 'كل الأيام حسب توفر السائق';
    const displayOrder = <String>[
      'sat',
      'sun',
      'mon',
      'tue',
      'wed',
      'thu',
      'fri'
    ];
    final selected = displayOrder.where(days.contains).toList(growable: false);
    if (selected.length == 7) return 'كل الأيام';
    return selected
        .map((dayId) => sallaDriverShiftDayNames[dayId] ?? dayId)
        .join('، ');
  }

  String get summary => enabled
      ? '$label • $timeLabel • $daysLabel'
      : 'دوام مرن • السائق يحدد توفره';

  DateTime? _nextStartFromBaghdad(DateTime baghdadNow) {
    final baseDate = DateTime.utc(
      baghdadNow.year,
      baghdadNow.month,
      baghdadNow.day,
    );
    for (var dayOffset = 0; dayOffset <= 7; dayOffset += 1) {
      final candidateDate = baseDate.add(Duration(days: dayOffset));
      final dayId = _sallaDriverShiftDayId(candidateDate.weekday);
      if (!days.contains(dayId)) continue;
      final candidate = candidateDate.add(Duration(minutes: startMinute));
      if (candidate.isAfter(baghdadNow)) return candidate;
    }
    return null;
  }
}

String _sallaDriverShiftDayId(int weekday) {
  const ids = <String>['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  return weekday >= DateTime.monday && weekday <= DateTime.sunday
      ? ids[weekday - 1]
      : '';
}

String sallaDriverShiftMinuteLabel(int minute) {
  final normalized = minute.clamp(0, 1439).toInt();
  final hour = normalized ~/ 60;
  final minutes = normalized % 60;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

class SallaCourierScheduleWindow {
  final DateTime dispatchStartsAt;
  final DateTime deliveryEndsAt;

  const SallaCourierScheduleWindow({
    required this.dispatchStartsAt,
    required this.deliveryEndsAt,
  });
}

/// يثبت نافذة اليوم التالي بتوقيت بغداد (UTC+3) بصرف النظر عن توقيت الجهاز.
SallaCourierScheduleWindow sallaNextBaghdadCourierWindow({
  required DateTime now,
  required int opensAtMinute,
  int durationHours = 12,
}) {
  if (opensAtMinute < 0 || opensAtMinute >= 1440) {
    throw ArgumentError.value(opensAtMinute, 'opensAtMinute');
  }
  if (durationHours < 1 || durationHours > 24) {
    throw ArgumentError.value(durationHours, 'durationHours');
  }
  final baghdadNow = now.toUtc().add(const Duration(hours: 3));
  final shiftedStart = DateTime.utc(
    baghdadNow.year,
    baghdadNow.month,
    baghdadNow.day + 1,
  ).add(Duration(minutes: opensAtMinute));
  final dispatchStartsAt = shiftedStart.subtract(const Duration(hours: 3));
  return SallaCourierScheduleWindow(
    dispatchStartsAt: dispatchStartsAt,
    deliveryEndsAt: dispatchStartsAt.add(Duration(hours: durationHours)),
  );
}

enum SallaDataMode {
  firebase,
  dual,
  api;

  static SallaDataMode parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'api':
      case 'lightnode':
        return SallaDataMode.api;
      case 'dual':
      case 'shadow':
        return SallaDataMode.dual;
      default:
        return SallaDataMode.firebase;
    }
  }
}

/// يضيف مهلة لأول حدث فقط من بث لحظي، من دون إغلاق المصدر عند انتهاء المهلة.
///
/// يبقى الاشتراك حياً بعد خطأ المهلة كي يستطيع المستهلك استقبال حدث متأخر،
/// كما يحافظ الغلاف على خصائص الإيقاف والاستئناف والإلغاء والبث المتعدد.
Stream<T> sallaRealtimeWithInitialTimeout<T>(
  Stream<T> source, {
  Duration initialTimeout = const Duration(seconds: 20),
}) {
  return Stream<T>.multi((controller) {
    final initialTimer = Timer(initialTimeout, () {
      if (controller.isClosed) return;
      controller.addError(
        TimeoutException(
          'لم تصل أول استجابة من قاعدة البيانات ضمن المهلة المحددة.',
          initialTimeout,
        ),
      );
    });
    final subscription = source.listen(
      (value) {
        initialTimer.cancel();
        controller.add(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        initialTimer.cancel();
        controller.addError(error, stackTrace);
      },
      onDone: () {
        initialTimer.cancel();
        controller.close();
      },
    );
    controller.onPause = subscription.pause;
    controller.onResume = subscription.resume;
    controller.onCancel = () async {
      initialTimer.cancel();
      await subscription.cancel();
    };
  }, isBroadcast: source.isBroadcast);
}

/// النسخة المرجعية لدفتر مستحقات السائق وعهدته النقدية.
const String sallaDriverFinanceLedgerVersion = 'salla_finance_v3_gross_cash';

/// حد العهدة الافتراضي. يمكن للخادم تغييره من إعدادات النظام المركزية.
const int sallaDriverFinanceDefaultDebtLimit = 125000;

/// يطبع نصوص البحث العربية بنفس العقد في تطبيقات سلة.
String sallaNormalizeArabicSearchText(Object? value) {
  return (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Ranks a place name or any of its aliases without combining separate aliases.
/// 0 = exact, 1 = partial/all words, 2 = one typo, null = unrelated.
/// Distance remains the caller's tie-breaker within the same score.
int? sallaArabicPlaceSearchScore(String query, Iterable<String> labels) {
  if (query.trim().isEmpty) return 0;
  if (query.length > 100) return null;
  final normalizedQuery = _sallaNormalizePlaceSearch(query);
  if (normalizedQuery.isEmpty) return 0;
  var queryWords = normalizedQuery.split(' ');
  if (queryWords.length > 16) return null;
  const genericWords = {'حي', 'شارع', 'مدينه', 'مجمع', 'السكني'};
  if (queryWords.length > 1 &&
      queryWords.any((word) => !genericWords.contains(word))) {
    queryWords = queryWords
        .where((word) => !genericWords.contains(word))
        .toList(growable: false);
  }
  int? best;
  for (final label in labels) {
    // Skip excessive labels, rather than truncate them into a false match.
    if (label.length > 256) continue;
    final normalizedLabel = _sallaNormalizePlaceSearch(label);
    if (normalizedLabel.isEmpty) continue;
    if (normalizedLabel == normalizedQuery) return 0;
    final labelWords = normalizedLabel.split(' ');
    if (labelWords.length > 16) continue;
    if (normalizedLabel.contains(normalizedQuery) ||
        queryWords.every(
          (word) => labelWords.any((candidate) => candidate.contains(word)),
        )) {
      best = 1;
      continue;
    }
    if (best == 1) continue;
    var typoCount = 0;
    var matches = true;
    for (final word in queryWords) {
      if (labelWords.any((candidate) => candidate.contains(word))) continue;
      final stem = _sallaPlaceSearchStem(word);
      if (++typoCount > 1 ||
          stem.length < 4 ||
          !labelWords.any(
            (candidate) {
              final candidateStem = _sallaPlaceSearchStem(candidate);
              return candidateStem.length >= 4 &&
                  _sallaPlaceWordWithinOneEdit(stem, candidateStem);
            },
          )) {
        matches = false;
        break;
      }
    }
    if (matches) best = 2;
  }
  return best;
}

String _sallaNormalizePlaceSearch(String value) => value
    .toLowerCase()
    .replaceAll(
        RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
    .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
    .replaceAll('ؤ', 'و')
    .replaceAll(RegExp(r'[ىیئ]'), 'ي')
    .replaceAll('ک', 'ك')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

String _sallaPlaceSearchStem(String word) =>
    word.length >= 5 && word.startsWith('ال') ? word.substring(2) : word;

bool _sallaPlaceWordWithinOneEdit(String left, String right) {
  if ((left.length - right.length).abs() > 1) return false;
  var index = 0;
  while (index < left.length &&
      index < right.length &&
      left.codeUnitAt(index) == right.codeUnitAt(index)) {
    index++;
  }
  if (index == left.length || index == right.length) return true;
  if (left.length != right.length) {
    return left.length > right.length
        ? left.substring(index + 1) == right.substring(index)
        : left.substring(index) == right.substring(index + 1);
  }
  if (left.substring(index + 1) == right.substring(index + 1)) return true;
  return index + 1 < left.length &&
      left.codeUnitAt(index) == right.codeUnitAt(index + 1) &&
      left.codeUnitAt(index + 1) == right.codeUnitAt(index) &&
      left.substring(index + 2) == right.substring(index + 2);
}

/// ملخص مالي خفيف يكتبه الخادم ويقرأه تطبيق السائق ولوحة الإدارة.
///
/// [cashBalance] موجب عند وجود رصيد مقدم للسائق، وسالب عند وجود عهدة
/// مطلوبة منه. أما [earningsBalance] فهو صافي أجور الطلبات القابل للتسوية.
class SallaDriverFinanceSummary {
  final String version;
  final int cashBalance;
  final int earningsBalance;
  final bool financeLocked;
  final String updatedAt;
  final String lastEntryId;

  const SallaDriverFinanceSummary({
    this.version = '',
    this.cashBalance = 0,
    this.earningsBalance = 0,
    this.financeLocked = false,
    this.updatedAt = '',
    this.lastEntryId = '',
  });

  factory SallaDriverFinanceSummary.fromFirebase(Object? value) {
    final data = _stringKeyedMap(value);
    return SallaDriverFinanceSummary(
      version: data['version']?.toString() ?? '',
      cashBalance: _intValue(data['cashBalance']),
      earningsBalance: _nonNegativeInt(data['earningsBalance']),
      financeLocked: data['financeLocked'] == true,
      updatedAt: data['updatedAt']?.toString() ?? '',
      lastEntryId: data['lastEntryId']?.toString() ?? '',
    );
  }

  bool get usesGrossCashLedger => version == sallaDriverFinanceLedgerVersion;
  int get cashDebt => cashBalance < 0 ? -cashBalance : 0;
  int get prepaidCredit => cashBalance > 0 ? cashBalance : 0;
}

/// قيد واحد غير قابل للحذف من دفتر السائق المالي.
class SallaDriverFinanceEntry {
  final String storeId;
  final String id;
  final String type;
  final String sourceType;
  final String sourceId;
  final int cashDelta;
  final int earningsDelta;
  final int customerCashCollected;
  final int storeCashPaidByDriver;
  final int driverFare;
  final int bonus;
  final int driverWage;
  final int companyFundedDriverFare;
  final int driverFareCollectedFromCustomer;
  final String storeDeliverySubscriptionId;
  final int companyProfit;
  final String storeSettlementMode;
  final String orderNumber;
  final String note;
  final String createdAt;
  final String actorName;
  final String reversalOf;
  final String reversedType;

  const SallaDriverFinanceEntry({
    this.storeId = '',
    required this.id,
    required this.type,
    this.sourceType = '',
    this.sourceId = '',
    this.cashDelta = 0,
    this.earningsDelta = 0,
    this.customerCashCollected = 0,
    this.storeCashPaidByDriver = 0,
    this.driverFare = 0,
    this.bonus = 0,
    this.driverWage = 0,
    this.companyFundedDriverFare = 0,
    this.driverFareCollectedFromCustomer = 0,
    this.storeDeliverySubscriptionId = '',
    this.companyProfit = 0,
    this.storeSettlementMode = '',
    this.orderNumber = '',
    this.note = '',
    this.createdAt = '',
    this.actorName = '',
    this.reversalOf = '',
    this.reversedType = '',
  });

  factory SallaDriverFinanceEntry.fromFirebase(
    String id,
    Object? value,
  ) {
    final data = _stringKeyedMap(value);
    return SallaDriverFinanceEntry(
      storeId: data['storeId']?.toString().trim() ?? '',
      id: data['id']?.toString().trim().isNotEmpty == true
          ? data['id'].toString()
          : id,
      type: data['type']?.toString() ?? '',
      sourceType: data['sourceType']?.toString() ?? '',
      sourceId: data['sourceId']?.toString() ?? '',
      cashDelta: _intValue(data['cashDelta']),
      earningsDelta: _intValue(data['earningsDelta']),
      customerCashCollected: _nonNegativeInt(data['customerCashCollected']),
      storeCashPaidByDriver: _nonNegativeInt(data['storeCashPaidByDriver']),
      driverFare: _nonNegativeInt(data['driverFare']),
      bonus: _nonNegativeInt(data['bonus']),
      driverWage: data.containsKey('driverWage')
          ? _nonNegativeInt(data['driverWage'])
          : _nonNegativeInt(data['driverFare']) +
              _nonNegativeInt(data['bonus']),
      companyProfit: _intValue(data['companyProfit']),
      companyFundedDriverFare: _nonNegativeInt(data['companyFundedDriverFare']),
      driverFareCollectedFromCustomer:
          _nonNegativeInt(data['driverFareCollectedFromCustomer']),
      storeDeliverySubscriptionId:
          data['storeDeliverySubscriptionId']?.toString() ?? '',
      storeSettlementMode: data['storeSettlementMode']?.toString() ?? '',
      orderNumber: data['orderNumber']?.toString() ?? '',
      note: (data['note'] ?? data['reason'])?.toString() ?? '',
      createdAt: data['createdAt']?.toString() ?? '',
      actorName:
          (data['actorName'] ?? data['createdByName'] ?? data['createdBy'])
                  ?.toString() ??
              '',
      reversalOf: data['reversalOf']?.toString() ?? '',
      reversedType: data['reversedType']?.toString() ?? '',
    );
  }

  DateTime? get createdAtValue => DateTime.tryParse(createdAt)?.toLocal();
  bool get affectsCash => cashDelta != 0;
  bool get affectsEarnings => earningsDelta != 0;
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return value.map(
    (key, item) => MapEntry(key.toString(), item),
  );
}

int _nonNegativeInt(Object? value) {
  final parsed = _intValue(value);
  return parsed < 0 ? 0 : parsed;
}

const int sallaMaxDeliveryZonePolygonPoints = 200;
const double _sallaGeoEpsilon = 0.0000000001;

class SallaGeoPoint {
  final double lat;
  final double lng;

  const SallaGeoPoint(this.lat, this.lng);
}

const String _sallaCoordinateNumberPattern =
    r'[-+]?(?:\d{1,3}(?:\.\d+)?|\.\d+)';

SallaGeoPoint? _sallaValidSharedGeoPoint(Object? rawLat, Object? rawLng) {
  final lat = double.tryParse(rawLat?.toString().trim() ?? '');
  final lng = double.tryParse(rawLng?.toString().trim() ?? '');
  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
    return null;
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat == 0 && lng == 0) return null;
  return SallaGeoPoint(
    double.parse(lat.toStringAsFixed(6)),
    double.parse(lng.toStringAsFixed(6)),
  );
}

SallaGeoPoint? _sallaCoordinatesFromText(String value) {
  String decoded;
  try {
    decoded = Uri.decodeComponent(value.replaceAll('+', ' '));
  } on ArgumentError {
    decoded = value.replaceAll('+', ' ');
  }
  final match = RegExp(
    '($_sallaCoordinateNumberPattern)\\s*[,،]\\s*'
    '($_sallaCoordinateNumberPattern)',
  ).firstMatch(decoded);
  if (match == null) return null;
  return _sallaValidSharedGeoPoint(match.group(1), match.group(2));
}

Uri? _sallaSafeUri(String value) {
  final trimmed = value
      .trim()
      .replaceFirst(RegExp(r'^[\(\[<{]+'), '')
      .replaceFirst(RegExp(r'[\)\]}>،,؛;.!]+$'), '');
  try {
    return Uri.tryParse(trimmed);
  } on FormatException {
    return null;
  }
}

Iterable<Uri> _sallaSharedLocationUris(String input) sync* {
  final navigationMatch = RegExp(
    r'google\.navigation:[^\s]+',
    caseSensitive: false,
  ).firstMatch(input);
  if (navigationMatch != null) {
    final uri = _sallaSafeUri(navigationMatch.group(0) ?? '');
    if (uri != null) yield uri;
  }
  final geoMatch =
      RegExp(r'geo:[^\s]+', caseSensitive: false).firstMatch(input);
  if (geoMatch != null) {
    final uri = _sallaSafeUri(geoMatch.group(0) ?? '');
    if (uri != null) yield uri;
  }
  for (final match
      in RegExp(r'https://[^\s]+', caseSensitive: false).allMatches(input)) {
    final uri = _sallaSafeUri(match.group(0) ?? '');
    if (uri != null) yield uri;
  }
}

bool _sallaTrustedGoogleMapsUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'maps.app.goo.gl' ||
      (host == 'goo.gl' &&
          (uri.path == '/maps' || uri.path.startsWith('/maps/'))) ||
      host == 'maps.google.com' ||
      host == 'www.google.com' ||
      host == 'google.com';
}

SallaGeoPoint? _sallaPointFromLocationUri(Uri uri) {
  if (uri.scheme.toLowerCase() == 'google.navigation') {
    final rawParameters =
        uri.path.startsWith('?') ? uri.path.substring(1) : uri.path;
    Map<String, String> parameters;
    try {
      parameters = Uri.splitQueryString(rawParameters);
    } on FormatException {
      return null;
    }
    return _sallaCoordinatesFromText(parameters['q'] ?? '');
  }
  if (uri.scheme.toLowerCase() == 'geo') {
    for (final key in const <String>['q', 'query', 'destination', 'll']) {
      final point = _sallaCoordinatesFromText(uri.queryParameters[key] ?? '');
      if (point != null) return point;
    }
    return _sallaCoordinatesFromText(uri.path);
  }
  if (!_sallaTrustedGoogleMapsUri(uri)) return null;
  for (final key in const <String>['q', 'query', 'destination', 'll']) {
    final point = _sallaCoordinatesFromText(uri.queryParameters[key] ?? '');
    if (point != null) return point;
  }
  final atPoint = RegExp(
    '@($_sallaCoordinateNumberPattern),($_sallaCoordinateNumberPattern)',
  ).firstMatch(uri.path);
  return atPoint == null
      ? null
      : _sallaValidSharedGeoPoint(atPoint.group(1), atPoint.group(2));
}

/// يستخرج نقطة موقع من `geo:` أو رابط Google Maps أو نص إحداثيات واضح.
///
/// لا يتبع روابط الاختصار ولا يجري أي اتصال شبكي. استخدم
/// [sallaResolveSharedLocationText] عند الحاجة إلى حل رابط Google المختصر.
SallaGeoPoint? sallaParseSharedLocationText(String input) {
  final normalized = input.trim();
  if (normalized.isEmpty) return null;
  final locationUris = _sallaSharedLocationUris(normalized).toList(
    growable: false,
  );
  for (final uri in locationUris) {
    final point = _sallaPointFromLocationUri(uri);
    if (point != null) return point;
  }
  // لا نستخرج أرقاماً من رابط رفضناه بسبب المضيف أو الصياغة؛ فالنص الخام
  // مقبول فقط عندما لا يحتوي أصلاً على رابط موقع.
  if (locationUris.isNotEmpty ||
      RegExp(
        r'(?:https://|geo:|google\.navigation:)',
        caseSensitive: false,
      ).hasMatch(normalized)) {
    return null;
  }
  return _sallaCoordinatesFromText(normalized);
}

/// يحل رابط Google Maps المختصر ضمن قائمة مضيفين مغلقة وبعدد تحويلات محدود.
///
/// لا يقرأ جسم الصفحة، ولا يقبل HTTP أو user-info أو منفذاً مخصصاً. يمكن حقن
/// [client] في الاختبارات؛ وإذا لم يمرر ينشئ هذا الاستدعاء عميله ويغلقه.
Future<SallaGeoPoint?> sallaResolveSharedLocationText(
  String input, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
  int maxRedirects = 5,
}) async {
  final direct = sallaParseSharedLocationText(input);
  if (direct != null) return direct;
  final candidates = _sallaSharedLocationUris(input)
      .where(_sallaTrustedGoogleMapsUri)
      .toList(growable: false);
  if (candidates.isEmpty) return null;
  final ownedClient = client == null;
  final activeClient = client ?? http.Client();
  try {
    for (final candidate in candidates) {
      var current = candidate;
      final visited = <String>{};
      for (var redirect = 0; redirect <= maxRedirects; redirect += 1) {
        if (!_sallaTrustedGoogleMapsUri(current) ||
            !visited.add(current.toString())) {
          break;
        }
        final embedded = _sallaPointFromLocationUri(current);
        if (embedded != null) return embedded;
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..maxRedirects = 0;
        final response = await activeClient.send(request).timeout(timeout);
        final streamSubscription = response.stream.listen((_) {});
        await streamSubscription.cancel();
        if (response.statusCode < 300 || response.statusCode >= 400) break;
        final location = response.headers['location']?.trim() ?? '';
        if (location.isEmpty) break;
        final next = current.resolve(location);
        if (!_sallaTrustedGoogleMapsUri(next)) break;
        current = next;
      }
    }
  } on TimeoutException {
    return null;
  } on http.ClientException {
    return null;
  } on Object {
    return null;
  } finally {
    if (ownedClient) activeClient.close();
  }
  return null;
}

enum SallaPolygonGeometryIssue {
  none,
  invalidCoordinate,
  tooFewPoints,
  tooManyPoints,
  duplicatePoint,
  zeroArea,
  selfIntersection,
}

class SallaPolygonGeometryValidation {
  final SallaPolygonGeometryIssue issue;
  final List<SallaGeoPoint> points;
  final List<int> conflictingSegmentIndexes;

  const SallaPolygonGeometryValidation({
    required this.issue,
    this.points = const <SallaGeoPoint>[],
    this.conflictingSegmentIndexes = const <int>[],
  });

  bool get isValid => issue == SallaPolygonGeometryIssue.none;

  List<SallaGeoPoint> get cleanedPoints => points;
}

double _roundedSallaCoordinate(double value) {
  return double.parse(value.toStringAsFixed(6));
}

bool _sameSallaGeoPoint(SallaGeoPoint left, SallaGeoPoint right) {
  return (left.lat - right.lat).abs() <= _sallaGeoEpsilon &&
      (left.lng - right.lng).abs() <= _sallaGeoEpsilon;
}

double _sallaPolygonCross(
  SallaGeoPoint first,
  SallaGeoPoint second,
  SallaGeoPoint third,
) {
  return (second.lng - first.lng) * (third.lat - first.lat) -
      (second.lat - first.lat) * (third.lng - first.lng);
}

bool _sallaPointOnSegment(
  SallaGeoPoint point,
  SallaGeoPoint first,
  SallaGeoPoint second,
) {
  if (_sallaPolygonCross(first, second, point).abs() > _sallaGeoEpsilon) {
    return false;
  }
  return point.lng >= min(first.lng, second.lng) - _sallaGeoEpsilon &&
      point.lng <= max(first.lng, second.lng) + _sallaGeoEpsilon &&
      point.lat >= min(first.lat, second.lat) - _sallaGeoEpsilon &&
      point.lat <= max(first.lat, second.lat) + _sallaGeoEpsilon;
}

bool _sallaOppositeSigns(double first, double second) {
  return (first > _sallaGeoEpsilon && second < -_sallaGeoEpsilon) ||
      (first < -_sallaGeoEpsilon && second > _sallaGeoEpsilon);
}

bool _sallaSegmentsIntersect(
  SallaGeoPoint firstStart,
  SallaGeoPoint firstEnd,
  SallaGeoPoint secondStart,
  SallaGeoPoint secondEnd,
) {
  final firstSideA = _sallaPolygonCross(firstStart, firstEnd, secondStart);
  final firstSideB = _sallaPolygonCross(firstStart, firstEnd, secondEnd);
  final secondSideA = _sallaPolygonCross(secondStart, secondEnd, firstStart);
  final secondSideB = _sallaPolygonCross(secondStart, secondEnd, firstEnd);
  if (_sallaOppositeSigns(firstSideA, firstSideB) &&
      _sallaOppositeSigns(secondSideA, secondSideB)) {
    return true;
  }
  return _sallaPointOnSegment(secondStart, firstStart, firstEnd) ||
      _sallaPointOnSegment(secondEnd, firstStart, firstEnd) ||
      _sallaPointOnSegment(firstStart, secondStart, secondEnd) ||
      _sallaPointOnSegment(firstEnd, secondStart, secondEnd);
}

bool _sallaSegmentsProperlyIntersect(
  SallaGeoPoint firstStart,
  SallaGeoPoint firstEnd,
  SallaGeoPoint secondStart,
  SallaGeoPoint secondEnd,
) {
  return _sallaOppositeSigns(
        _sallaPolygonCross(firstStart, firstEnd, secondStart),
        _sallaPolygonCross(firstStart, firstEnd, secondEnd),
      ) &&
      _sallaOppositeSigns(
        _sallaPolygonCross(secondStart, secondEnd, firstStart),
        _sallaPolygonCross(secondStart, secondEnd, firstEnd),
      );
}

double _sallaPolygonAreaTwice(List<SallaGeoPoint> points) {
  var area = 0.0;
  for (var index = 0; index < points.length; index += 1) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    area += current.lng * next.lat - next.lng * current.lat;
  }
  return area;
}

List<int> _sallaConflictingSegmentIndexes(List<SallaGeoPoint> points) {
  for (var firstIndex = 0; firstIndex < points.length; firstIndex += 1) {
    final firstNext = (firstIndex + 1) % points.length;
    for (var secondIndex = firstIndex + 1;
        secondIndex < points.length;
        secondIndex += 1) {
      final secondNext = (secondIndex + 1) % points.length;
      final adjacent = firstIndex == secondIndex ||
          firstNext == secondIndex ||
          secondNext == firstIndex;
      if (adjacent) continue;
      if (_sallaSegmentsIntersect(
        points[firstIndex],
        points[firstNext],
        points[secondIndex],
        points[secondNext],
      )) {
        return <int>[firstIndex, secondIndex];
      }
    }
  }
  return const <int>[];
}

List<Object?> _sallaRawPolygonPoints(Object? value) {
  if (value is Iterable && value is! String && value is! Map) {
    return value.cast<Object?>().toList();
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()));
    return entries.map((entry) => entry.value).toList();
  }
  return const [];
}

/// يتحقق من هندسة مضلع بنفس عقد الخادم من دون تغيير ترتيب رؤوسه.
///
/// مؤشرات المقاطع المتعارضة صفرية؛ المقطع `i` يبدأ من النقطة `i` وينتهي عند
/// النقطة `(i + 1) % points.length`.
SallaPolygonGeometryValidation sallaValidatePolygonGeometry(Object? value) {
  final points = <SallaGeoPoint>[];
  for (final rawPoint in _sallaRawPolygonPoints(value)) {
    final data = rawPoint is SallaGeoPoint
        ? const <String, dynamic>{}
        : _stringKeyedMap(rawPoint);
    final lat =
        rawPoint is SallaGeoPoint ? rawPoint.lat : _doubleOrNull(data['lat']);
    final lng =
        rawPoint is SallaGeoPoint ? rawPoint.lng : _doubleOrNull(data['lng']);
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return SallaPolygonGeometryValidation(
        issue: SallaPolygonGeometryIssue.invalidCoordinate,
        points: List<SallaGeoPoint>.unmodifiable(points),
      );
    }
    final point = SallaGeoPoint(
      _roundedSallaCoordinate(lat),
      _roundedSallaCoordinate(lng),
    );
    if (points.isEmpty || !_sameSallaGeoPoint(points.last, point)) {
      points.add(point);
    }
  }
  if (points.length > 1 && _sameSallaGeoPoint(points.first, points.last)) {
    points.removeLast();
  }
  final cleanedPoints = List<SallaGeoPoint>.unmodifiable(points);
  if (points.length < 3) {
    return SallaPolygonGeometryValidation(
      issue: SallaPolygonGeometryIssue.tooFewPoints,
      points: cleanedPoints,
    );
  }
  if (points.length > sallaMaxDeliveryZonePolygonPoints) {
    return SallaPolygonGeometryValidation(
      issue: SallaPolygonGeometryIssue.tooManyPoints,
      points: cleanedPoints,
    );
  }
  final identities = points
      .map(
          (point) => '${(point.lat == 0 ? 0.0 : point.lat).toStringAsFixed(6)}|'
              '${(point.lng == 0 ? 0.0 : point.lng).toStringAsFixed(6)}')
      .toSet();
  if (identities.length != points.length) {
    return SallaPolygonGeometryValidation(
      issue: SallaPolygonGeometryIssue.duplicatePoint,
      points: cleanedPoints,
    );
  }
  final conflictingSegmentIndexes = _sallaConflictingSegmentIndexes(points);
  if (conflictingSegmentIndexes.isNotEmpty) {
    return SallaPolygonGeometryValidation(
      issue: SallaPolygonGeometryIssue.selfIntersection,
      points: cleanedPoints,
      conflictingSegmentIndexes:
          List<int>.unmodifiable(conflictingSegmentIndexes),
    );
  }
  if (_sallaPolygonAreaTwice(points).abs() <= _sallaGeoEpsilon) {
    return SallaPolygonGeometryValidation(
      issue: SallaPolygonGeometryIssue.zeroArea,
      points: cleanedPoints,
    );
  }
  return SallaPolygonGeometryValidation(
    issue: SallaPolygonGeometryIssue.none,
    points: cleanedPoints,
  );
}

List<SallaGeoPoint> _sallaPolygonPoints(Object? value) {
  final validation = sallaValidatePolygonGeometry(value);
  return validation.isValid ? validation.points : const <SallaGeoPoint>[];
}

bool _sallaPointInPolygon(
  SallaGeoPoint point,
  List<SallaGeoPoint> polygon,
) {
  var inside = false;
  for (var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index, index += 1) {
    final currentPoint = polygon[index];
    final previousPoint = polygon[previous];
    if (_sallaPointOnSegment(point, previousPoint, currentPoint)) return true;
    final crossesLatitude =
        (currentPoint.lat > point.lat) != (previousPoint.lat > point.lat);
    if (!crossesLatitude) continue;
    final crossingLongitude = (previousPoint.lng - currentPoint.lng) *
            (point.lat - currentPoint.lat) /
            (previousPoint.lat - currentPoint.lat) +
        currentPoint.lng;
    if (point.lng < crossingLongitude + _sallaGeoEpsilon) {
      inside = !inside;
    }
  }
  return inside;
}

/// يتحقق من وجود نقطة داخل مضلع صالح أو على حافته بعقد مطابق للخادم.
///
/// يفشل مغلقاً عند إحداثية أو مضلع ناقص، ويُستخدم عندما تكون التغطية
/// الجغرافية اختيارية للمستهلك ولا يجوز له إعادة تنفيذ خوارزمية مستقلة.
bool sallaPointInsidePolygon({
  required Object? rawPolygonPoints,
  required double? lat,
  required double? lng,
}) {
  if (lat == null ||
      lng == null ||
      !lat.isFinite ||
      !lng.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lng < -180 ||
      lng > 180) {
    return false;
  }
  final polygon = _sallaPolygonPoints(rawPolygonPoints);
  if (polygon.length < 3) return false;
  return _sallaPointInPolygon(SallaGeoPoint(lat, lng), polygon);
}

/// يتحقق من احتواء مضلع كامل داخل مضلع آخر، لا من احتواء نقاط مختارة فقط.
///
/// يسمح بتلامس الحدود، لكنه يرفض أي رأس أو منتصف ضلع خارج المضلع الحاوي وأي
/// تقاطع حقيقي بين أضلاع المضلعين. يطابق بذلك تحقق الخادم عند إنشاء الطلب.
bool sallaPolygonContainsPolygon({
  required Object? rawContainerPoints,
  required Object? rawCandidatePoints,
}) {
  final container = _sallaPolygonPoints(rawContainerPoints);
  final candidate = _sallaPolygonPoints(rawCandidatePoints);
  if (container.length < 3 || candidate.length < 3) return false;
  if (!candidate.every((point) => _sallaPointInPolygon(point, container))) {
    return false;
  }
  for (var candidateIndex = 0;
      candidateIndex < candidate.length;
      candidateIndex += 1) {
    final candidateStart = candidate[candidateIndex];
    final candidateEnd = candidate[(candidateIndex + 1) % candidate.length];
    final midpoint = SallaGeoPoint(
      (candidateStart.lat + candidateEnd.lat) / 2,
      (candidateStart.lng + candidateEnd.lng) / 2,
    );
    if (!_sallaPointInPolygon(midpoint, container)) return false;
    for (var containerIndex = 0;
        containerIndex < container.length;
        containerIndex += 1) {
      final containerStart = container[containerIndex];
      final containerEnd = container[(containerIndex + 1) % container.length];
      if (_sallaSegmentsProperlyIntersect(
        candidateStart,
        candidateEnd,
        containerStart,
        containerEnd,
      )) {
        return false;
      }
    }
  }
  return true;
}

Map<String, double> _sallaCoverageBounds(Object? value) {
  final data = _stringKeyedMap(value);
  final minLat = _doubleOrNull(data['minLat']);
  final maxLat = _doubleOrNull(data['maxLat']);
  final minLng = _doubleOrNull(data['minLng']);
  final maxLng = _doubleOrNull(data['maxLng']);
  if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
    return const {};
  }
  return {
    'minLat': minLat,
    'maxLat': maxLat,
    'minLng': minLng,
    'maxLng': maxLng,
  };
}

int _sallaStoreZoneCompactRadiusKm(Object? value) {
  final parsed = value is num
      ? value.round()
      : int.tryParse(value?.toString().trim() ?? '');
  return (parsed ?? 8).clamp(1, 30).toInt();
}

/// زون توصيل جغرافي واحد تحت المسار التشغيلي الموجود للمتاجر.
///
/// يدعم الدائرة والمضلع تحت [coverageType] من دون تغيير عقدة البيانات أو
/// حقول المتاجر.
class SallaStoreServiceZone {
  final String id;
  final String name;
  final bool active;
  final String mode;
  final int compactRadiusKm;
  final int order;
  final String provinceId;
  final String provinceName;
  final String branchId;
  final String branchName;
  final String coverageType;
  final double? centerLat;
  final double? centerLng;
  final double? coverageRadiusKm;
  final List<SallaGeoPoint> polygonPoints;
  final List<SallaGeoPoint> branchBoundaryPoints;
  final Map<String, double> coverageBounds;
  final String coverageHash;
  final int coverageRevision;
  final bool networkActive;

  const SallaStoreServiceZone({
    required this.id,
    required this.name,
    required this.active,
    this.mode = 'normal',
    this.compactRadiusKm = 8,
    required this.order,
    required this.provinceId,
    required this.provinceName,
    required this.branchId,
    required this.branchName,
    required this.coverageType,
    required this.centerLat,
    required this.centerLng,
    required this.coverageRadiusKm,
    this.polygonPoints = const [],
    this.branchBoundaryPoints = const [],
    this.coverageBounds = const {},
    this.coverageHash = '',
    this.coverageRevision = 0,
    this.networkActive = true,
  });

  factory SallaStoreServiceZone.fromFirebase(
    String id,
    Object? value, {
    bool networkActive = true,
    List<SallaGeoPoint> branchBoundaryPoints = const [],
  }) {
    final data = _stringKeyedMap(value);
    return SallaStoreServiceZone(
      id: id.trim(),
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : id.trim(),
      // Explicitly assigned delivery zones fail closed unless the server has
      // activated them. Legacy stores without assignments bypass this model.
      active: data['active'] == true,
      mode: switch (data['mode']?.toString().trim().toLowerCase()) {
        'pressure' => 'pressure',
        'compact' => 'compact',
        'paused' => 'paused',
        _ => 'normal',
      },
      compactRadiusKm: _sallaStoreZoneCompactRadiusKm(
        data['compactRadiusKm'],
      ),
      order: _intValue(data['order']),
      provinceId: data['provinceId']?.toString().trim() ?? '',
      provinceName: data['provinceName']?.toString().trim() ?? '',
      branchId: data['branchId']?.toString().trim() ?? '',
      branchName: data['branchName']?.toString().trim() ?? '',
      coverageType: switch (
          data['coverageType']?.toString().trim().toLowerCase()) {
        'circle' => 'circle',
        'polygon' => 'polygon',
        _ => '',
      },
      centerLat: _doubleOrNull(data['centerLat']),
      centerLng: _doubleOrNull(data['centerLng']),
      coverageRadiusKm: _doubleOrNull(data['coverageRadiusKm']),
      polygonPoints: _sallaPolygonPoints(data['polygonPoints']),
      branchBoundaryPoints: branchBoundaryPoints,
      coverageBounds: _sallaCoverageBounds(data['coverageBounds']),
      coverageHash: data['coverageHash']?.toString().trim() ?? '',
      coverageRevision: _nonNegativeInt(data['coverageRevision']),
      networkActive: networkActive,
    );
  }

  bool get hasValidCircle =>
      coverageType == 'circle' &&
      centerLat != null &&
      centerLng != null &&
      centerLat! >= -90 &&
      centerLat! <= 90 &&
      centerLng! >= -180 &&
      centerLng! <= 180 &&
      coverageRadiusKm != null &&
      coverageRadiusKm! > 0;

  bool get hasValidPolygon =>
      coverageType == 'polygon' &&
      polygonPoints.length >= 3 &&
      polygonPoints.length <= sallaMaxDeliveryZonePolygonPoints;

  bool get hasValidCoverage => hasValidCircle || hasValidPolygon;

  bool get hasValidBranchBoundary =>
      branchBoundaryPoints.length >= 3 &&
      branchBoundaryPoints.length <= sallaMaxDeliveryZonePolygonPoints;

  bool branchContains(double lat, double lng) {
    if (!networkActive ||
        !hasValidBranchBoundary ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return false;
    }
    return _sallaPointInPolygon(
      SallaGeoPoint(lat, lng),
      branchBoundaryPoints,
    );
  }

  bool contains(double lat, double lng) {
    if (!active ||
        !networkActive ||
        !hasValidCoverage ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return false;
    }
    if (branchBoundaryPoints.isNotEmpty && !branchContains(lat, lng)) {
      return false;
    }
    if (hasValidPolygon) {
      final minLat = coverageBounds['minLat'];
      final maxLat = coverageBounds['maxLat'];
      final minLng = coverageBounds['minLng'];
      final maxLng = coverageBounds['maxLng'];
      if (minLat != null &&
          maxLat != null &&
          minLng != null &&
          maxLng != null &&
          (lat < minLat - _sallaGeoEpsilon ||
              lat > maxLat + _sallaGeoEpsilon ||
              lng < minLng - _sallaGeoEpsilon ||
              lng > maxLng + _sallaGeoEpsilon)) {
        return false;
      }
      return _sallaPointInPolygon(SallaGeoPoint(lat, lng), polygonPoints);
    }
    return sallaGeoDistanceKm(
          centerLat!,
          centerLng!,
          lat,
          lng,
        ) <=
        coverageRadiusKm! + 0.000001;
  }
}

double? _doubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

double sallaGeoDistanceKm(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  const earthRadiusKm = 6371.0088;
  double radians(double degrees) => degrees * pi / 180;
  final latDelta = radians(toLat - fromLat);
  final lngDelta = radians(toLng - fromLng);
  final fromLatRadians = radians(fromLat);
  final toLatRadians = radians(toLat);
  final haversine = sin(latDelta / 2) * sin(latDelta / 2) +
      cos(fromLatRadians) *
          cos(toLatRadians) *
          sin(lngDelta / 2) *
          sin(lngDelta / 2);
  final safeHaversine = haversine.clamp(0.0, 1.0);
  return 2 * earthRadiusKm * asin(sqrt(safeHaversine));
}

List<SallaStoreServiceZone> sallaStoreServiceZonesFromFirebase(
  Object? value, {
  Object? rawProvinces,
  Object? rawBranches,
  bool requireActiveNetwork = false,
}) {
  final data = _stringKeyedMap(value);
  final provinces = _stringKeyedMap(rawProvinces);
  final branches = _stringKeyedMap(rawBranches);
  final zones = <SallaStoreServiceZone>[];
  for (final entry in data.entries) {
    if (entry.value is! Map) continue;
    final rawZone = _stringKeyedMap(entry.value);
    var networkActive = true;
    var branchBoundaryPoints = const <SallaGeoPoint>[];
    if (requireActiveNetwork) {
      final provinceId = rawZone['provinceId']?.toString().trim() ?? '';
      final branchId = rawZone['branchId']?.toString().trim() ?? '';
      final province = _stringKeyedMap(provinces[provinceId]);
      final branch = _stringKeyedMap(branches[branchId]);
      final branchBoundaryType =
          branch['boundaryType']?.toString().trim().toLowerCase() ?? '';
      branchBoundaryPoints = branchBoundaryType == 'polygon'
          ? _sallaPolygonPoints(branch['boundaryPoints'])
          : const <SallaGeoPoint>[];
      networkActive = provinceId.isNotEmpty &&
          branchId.isNotEmpty &&
          province['active'] == true &&
          branch['active'] == true &&
          branch['provinceId']?.toString().trim() == provinceId &&
          branchBoundaryPoints.length >= 3 &&
          branchBoundaryPoints.length <= sallaMaxDeliveryZonePolygonPoints;
    }
    final zone = SallaStoreServiceZone.fromFirebase(
      entry.key,
      entry.value,
      networkActive: networkActive,
      branchBoundaryPoints: branchBoundaryPoints,
    );
    if (zone.id.isNotEmpty) zones.add(zone);
  }
  zones.sort((left, right) {
    final byOrder = left.order.compareTo(right.order);
    return byOrder != 0 ? byOrder : left.name.compareTo(right.name);
  });
  return zones;
}

Set<String> sallaStoreCustomerServiceZoneIds(Object? value) {
  final ids = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final id = entry.key.toString().trim();
      if (id.isNotEmpty && entry.value == true) ids.add(id);
    }
  } else if (value is Iterable && value is! String) {
    for (final rawId in value) {
      final id = rawId?.toString().trim() ?? '';
      if (id.isNotEmpty) ids.add(id);
    }
  }
  return ids;
}

double _sallaStoreZoneReferenceDistanceKm(
  SallaStoreServiceZone zone,
  double customerLat,
  double customerLng,
) {
  final referenceLat = zone.hasValidCircle
      ? zone.centerLat!
      : zone.polygonPoints.fold<double>(
            0,
            (sum, point) => sum + point.lat,
          ) /
          zone.polygonPoints.length;
  final referenceLng = zone.hasValidCircle
      ? zone.centerLng!
      : zone.polygonPoints.fold<double>(
            0,
            (sum, point) => sum + point.lng,
          ) /
          zone.polygonPoints.length;
  return sallaGeoDistanceKm(
    customerLat,
    customerLng,
    referenceLat,
    referenceLng,
  );
}

/// يختار الزون الفعلي الذي يحتوي عنوان الزبون من قائمة المتجر الصريحة.
///
/// تطابق الأولوية الخادم: الزونات غير الموقوفة أولاً، ثم الأقرب إلى مرجع
/// التغطية، ثم المعرّف لضمان نتيجة حتمية. إذا كانت كل المطابقات موقوفة يفشل
/// الاختيار مغلقاً ولا يعيد زوناً موقوفاً صالحاً للطلب.
SallaStoreServiceZone? sallaMatchingAssignedCustomerZone({
  required Object? rawAssignedZoneIds,
  required Iterable<SallaStoreServiceZone> zones,
  required double? customerLat,
  required double? customerLng,
  String? requiredBranchId,
  double? storeLat,
  double? storeLng,
  bool requireStoreBranchBoundary = false,
}) {
  final assignedZoneIds = sallaStoreCustomerServiceZoneIds(rawAssignedZoneIds);
  if (assignedZoneIds.isEmpty ||
      customerLat == null ||
      customerLng == null ||
      !customerLat.isFinite ||
      !customerLng.isFinite) {
    return null;
  }
  final normalizedRequiredBranchId = requiredBranchId?.trim() ?? '';
  final matches = zones
      .where(
        (zone) =>
            assignedZoneIds.contains(zone.id) &&
            zone.contains(customerLat, customerLng) &&
            (!requireStoreBranchBoundary ||
                (normalizedRequiredBranchId.isNotEmpty &&
                    zone.branchId == normalizedRequiredBranchId &&
                    storeLat != null &&
                    storeLng != null &&
                    zone.branchContains(storeLat, storeLng))),
      )
      .toList(growable: false);
  matches.sort((left, right) {
    final byAvailability = (left.mode == 'paused' ? 1 : 0).compareTo(
      right.mode == 'paused' ? 1 : 0,
    );
    if (byAvailability != 0) return byAvailability;
    final byDistance = _sallaStoreZoneReferenceDistanceKm(
      left,
      customerLat,
      customerLng,
    ).compareTo(
      _sallaStoreZoneReferenceDistanceKm(
        right,
        customerLat,
        customerLng,
      ),
    );
    return byDistance != 0 ? byDistance : left.id.compareTo(right.id);
  });
  if (matches.isEmpty || matches.first.mode == 'paused') return null;
  return matches.first;
}

/// نقاط مضلع التوصيل المستقل للمتجر بعد التحقق الهندسي.
List<SallaGeoPoint> sallaStoreCustomerZonePolygonPoints(Object? value) {
  return _sallaPolygonPoints(value);
}

/// لا يظهر المتجر للزبون قبل وجود مضلع توصيل صالح. غياب المضلع أو وجود قيمة
/// غير صالحة يفشل مغلقاً؛ تبقى السجلات القديمة قابلة للإعداد وهي مغلقة.
bool sallaStoreInsideCustomerZonePolygon({
  required Object? rawPolygonPoints,
  required double? customerLat,
  required double? customerLng,
}) {
  return sallaPointInsidePolygon(
    rawPolygonPoints: rawPolygonPoints,
    lat: customerLat,
    lng: customerLng,
  );
}

/// يعيد `true` للمتجر القديم الذي لا يملك قائمة زونات حتى يبقى التوافق
/// التشغيلي قائماً. أما المتجر الذي يملك قائمة صريحة فيفشل مغلقاً عند غياب
/// موقع الزبون أو هندسة الزون، ويجب أن يحتوي أحد زوناته الفعالة غير الموقوفة
/// الموقع.
bool sallaStoreInsideAssignedCustomerZones({
  required Object? rawAssignedZoneIds,
  required Iterable<SallaStoreServiceZone> zones,
  required double? customerLat,
  required double? customerLng,
  String? requiredBranchId,
  double? storeLat,
  double? storeLng,
  bool requireStoreBranchBoundary = false,
}) {
  if (rawAssignedZoneIds == null) return true;
  final assignedZoneIds = sallaStoreCustomerServiceZoneIds(rawAssignedZoneIds);
  if (assignedZoneIds.isEmpty) return false;
  return sallaMatchingAssignedCustomerZone(
        rawAssignedZoneIds: assignedZoneIds,
        zones: zones,
        customerLat: customerLat,
        customerLng: customerLng,
        requiredBranchId: requiredBranchId,
        storeLat: storeLat,
        storeLng: storeLng,
        requireStoreBranchBoundary: requireStoreBranchBoundary,
      ) !=
      null;
}

class SallaDataConfiguration {
  final SallaDataMode mode;
  final String apiBaseUrl;
  final Duration requestTimeout;
  final bool mirrorWrites;

  const SallaDataConfiguration({
    required this.mode,
    this.apiBaseUrl = '',
    this.requestTimeout = const Duration(seconds: 20),
    this.mirrorWrites = true,
  });

  factory SallaDataConfiguration.fromEnvironment() {
    const rawMode = String.fromEnvironment(
      'SALLA_DATA_BACKEND',
      defaultValue: 'firebase',
    );
    const rawApiBaseUrl = String.fromEnvironment(
      'SALLA_API_BASE_URL',
      defaultValue: '',
    );
    const rawTimeoutSeconds = int.fromEnvironment(
      'SALLA_API_TIMEOUT_SECONDS',
      defaultValue: 20,
    );
    const rawMirrorWrites = bool.fromEnvironment(
      'SALLA_API_MIRROR_WRITES',
      defaultValue: true,
    );
    return SallaDataConfiguration(
      mode: SallaDataMode.parse(rawMode),
      apiBaseUrl: rawApiBaseUrl,
      requestTimeout: Duration(
        seconds: rawTimeoutSeconds < 5 ? 5 : rawTimeoutSeconds,
      ),
      mirrorWrites: rawMirrorWrites,
    );
  }
}

/// Builds a lightweight, order-independent signature for one realtime record.
///
/// [ignoredKeys] applies only to the record itself. Nested fields with the same
/// name remain part of the signature, so callers can safely ignore volatile
/// transport fields without hiding meaningful nested changes.
String sallaRecordContentSignature(
  Object? value, {
  Set<String> ignoredKeys = const <String>{},
}) {
  final fingerprint = _stableContentFingerprint(
    value,
    ignoredKeysAtThisLevel: ignoredKeys,
  );
  return '${fingerprint.nodes}:${fingerprint.forward}:${fingerprint.reverse}';
}

/// Builds a signature for a realtime collection while ignoring selected keys
/// only inside each direct child record.
///
/// This is useful for bounded order lists: a high-frequency driver-location
/// update can keep its dedicated order listener live without rebuilding every
/// list that also observes the same order collection.
String sallaCollectionContentSignature(
  Object? value, {
  Set<String> ignoredRecordKeys = const <String>{},
}) {
  if (value is! Map) {
    return sallaRecordContentSignature(value);
  }

  final entries = value.entries.toList(growable: false)
    ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()));
  final forwardParts = <Object?>[0x53434f4c, entries.length];
  final reverseParts = <Object?>[0x4c4f4353, entries.length];
  var nodes = 1;
  for (final entry in entries) {
    final key = entry.key.toString();
    final child = _stableContentFingerprint(
      entry.value,
      ignoredKeysAtThisLevel: ignoredRecordKeys,
    );
    nodes += child.nodes + 1;
    forwardParts
      ..add(key)
      ..add(child.forward)
      ..add(child.reverse);
    reverseParts
      ..add(child.reverse)
      ..add(child.forward)
      ..add(key);
  }
  return '$nodes:${Object.hashAll(forwardParts)}:${Object.hashAll(reverseParts.reversed)}';
}

({int forward, int reverse, int nodes}) _stableContentFingerprint(
  Object? value, {
  Set<String> ignoredKeysAtThisLevel = const <String>{},
}) {
  if (value is Map) {
    final entries = value.entries
        .where(
          (entry) => !ignoredKeysAtThisLevel.contains(entry.key.toString()),
        )
        .toList(growable: false)
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    final forwardParts = <Object?>[0x4d4150, entries.length];
    final reverseParts = <Object?>[0x50414d, entries.length];
    var nodes = 1;
    for (final entry in entries) {
      final key = entry.key.toString();
      final child = _stableContentFingerprint(entry.value);
      nodes += child.nodes + 1;
      forwardParts
        ..add(key)
        ..add(child.forward)
        ..add(child.reverse);
      reverseParts
        ..add(child.reverse)
        ..add(child.forward)
        ..add(key);
    }
    return (
      forward: Object.hashAll(forwardParts),
      reverse: Object.hashAll(reverseParts.reversed),
      nodes: nodes,
    );
  }

  if (value is List) {
    final forwardParts = <Object?>[0x4c495354, value.length];
    final reverseParts = <Object?>[0x5453494c, value.length];
    var nodes = 1;
    for (final item in value) {
      final child = _stableContentFingerprint(item);
      nodes += child.nodes;
      forwardParts
        ..add(child.forward)
        ..add(child.reverse);
      reverseParts
        ..add(child.reverse)
        ..add(child.forward);
    }
    return (
      forward: Object.hashAll(forwardParts),
      reverse: Object.hashAll(reverseParts.reversed),
      nodes: nodes,
    );
  }

  final type = value.runtimeType.toString();
  return (
    forward: Object.hash(0x56414c, type, value),
    reverse: Object.hash(0x4c4156, value, type),
    nodes: 1,
  );
}

class SallaDatabase {
  static SallaDatabase? _instance;

  final firebase.FirebaseDatabase _firebaseDatabase;
  final FirebaseAuth _firebaseAuth;
  final SallaDataConfiguration configuration;
  late final _SallaApiClient _apiClient;
  late final _SallaRealtimeClient _realtimeClient;
  StreamSubscription<User?>? _authSubscription;

  SallaDatabase._({
    required firebase.FirebaseDatabase firebaseDatabase,
    required FirebaseAuth firebaseAuth,
    required this.configuration,
  })  : _firebaseDatabase = firebaseDatabase,
        _firebaseAuth = firebaseAuth {
    _apiClient = _SallaApiClient(
      baseUrl: configuration.apiBaseUrl,
      auth: _firebaseAuth,
      timeout: configuration.requestTimeout,
    );
    _realtimeClient = _SallaRealtimeClient(
      baseUrl: configuration.apiBaseUrl,
      auth: _firebaseAuth,
    );
    _authSubscription = _firebaseAuth.idTokenChanges().listen((_) {
      _realtimeClient.reconnectForAuthenticationChange();
    });
  }

  static SallaDatabase get instance {
    return _instance ??= SallaDatabase._(
      firebaseDatabase: firebase.FirebaseDatabase.instance,
      firebaseAuth: FirebaseAuth.instance,
      configuration: SallaDataConfiguration.fromEnvironment(),
    );
  }

  static void configure({
    firebase.FirebaseDatabase? firebaseDatabase,
    FirebaseAuth? firebaseAuth,
    SallaDataConfiguration? configuration,
  }) {
    _instance?._dispose();
    _instance = SallaDatabase._(
      firebaseDatabase: firebaseDatabase ?? firebase.FirebaseDatabase.instance,
      firebaseAuth: firebaseAuth ?? FirebaseAuth.instance,
      configuration: configuration ?? SallaDataConfiguration.fromEnvironment(),
    );
  }

  static void configureForFirebaseApp(
    FirebaseApp app, {
    SallaDataConfiguration? configuration,
  }) {
    configure(
      firebaseDatabase: firebase.FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: app.options.databaseURL,
      ),
      firebaseAuth: FirebaseAuth.instanceFor(app: app),
      configuration: configuration,
    );
  }

  DatabaseReference ref([String? path]) {
    final normalized = _normalizePath(path ?? '');
    return DatabaseReference._(
      database: this,
      path: normalized,
      firebaseReference: normalized.isEmpty
          ? _firebaseDatabase.ref()
          : _firebaseDatabase.ref(normalized),
    );
  }

  void reconnectRealtime() {
    if (configuration.mode != SallaDataMode.api) return;
    _realtimeClient.reconnectForAuthenticationChange();
  }

  void _dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _realtimeClient.dispose();
  }
}

class Query {
  final SallaDatabase _database;
  final String _path;
  final firebase.Query _firebaseQuery;
  final _QueryOptions _options;

  Query._({
    required SallaDatabase database,
    required String path,
    required firebase.Query firebaseQuery,
    _QueryOptions options = const _QueryOptions(),
  })  : _database = database,
        _path = path,
        _firebaseQuery = firebaseQuery,
        _options = options;

  Query orderByChild(String path) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.orderByChild(path),
      options: _options.copyWith(orderByChild: path),
    );
  }

  Query orderByKey() {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.orderByKey(),
      options: _options.copyWith(orderByKey: true),
    );
  }

  Query equalTo(Object? value, {String? key}) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.equalTo(value, key: key),
      options: _options.copyWith(
        equalTo: value,
        equalToKey: key,
        hasEqualTo: true,
      ),
    );
  }

  Query startAt(Object? value, {String? key}) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.startAt(value, key: key),
      options: _options.copyWith(
        startAt: value,
        startAtKey: key,
        hasStartAt: true,
      ),
    );
  }

  Query endAt(Object? value, {String? key}) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.endAt(value, key: key),
      options: _options.copyWith(
        endAt: value,
        endAtKey: key,
        hasEndAt: true,
      ),
    );
  }

  Query limitToLast(int limit) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.limitToLast(limit),
      options: _options.copyWith(limitToLast: limit),
    );
  }

  Query limitToFirst(int limit) {
    return Query._(
      database: _database,
      path: _path,
      firebaseQuery: _firebaseQuery.limitToFirst(limit),
      options: _options.copyWith(limitToFirst: limit),
    );
  }

  Future<DataSnapshot> get() async {
    final mode = _database.configuration.mode;
    if (mode != SallaDataMode.api) {
      return DataSnapshot._fromFirebase(
        await _firebaseQuery.get(),
        _database,
        path: _path,
      );
    }
    final response = await _database._apiClient.read(
      path: _path,
      query: _options,
    );
    return DataSnapshot._fromApi(
      database: _database,
      path: _path,
      value: response.value,
    );
  }

  Stream<DatabaseEvent> get onValue {
    final mode = _database.configuration.mode;
    if (mode != SallaDataMode.api) {
      return _firebaseQuery.onValue.map(
        (event) => DatabaseEvent._(
          DataSnapshot._fromFirebase(event.snapshot, _database, path: _path),
        ),
      );
    }
    return _database._realtimeClient
        .subscribe(path: _path, query: _options)
        .map(
          (value) => DatabaseEvent._(
            DataSnapshot._fromApi(
              database: _database,
              path: _path,
              value: value,
            ),
          ),
        );
  }
}

class DatabaseReference extends Query {
  final firebase.DatabaseReference _firebaseReference;

  DatabaseReference._({
    required super.database,
    required super.path,
    required firebase.DatabaseReference firebaseReference,
  })  : _firebaseReference = firebaseReference,
        super._(firebaseQuery: firebaseReference);

  String? get key {
    if (_path.isEmpty) return null;
    return _path.split('/').last;
  }

  DatabaseReference child(String path) {
    final cleanChild = _normalizePath(path);
    final nextPath = _joinPath(_path, cleanChild);
    return DatabaseReference._(
      database: _database,
      path: nextPath,
      firebaseReference: _firebaseReference.child(cleanChild),
    );
  }

  DatabaseReference push() {
    if (_database.configuration.mode != SallaDataMode.api) {
      final pushed = _firebaseReference.push();
      return DatabaseReference._(
        database: _database,
        path: _joinPath(_path, pushed.key ?? _generatePushKey()),
        firebaseReference: pushed,
      );
    }
    return child(_generatePushKey());
  }

  Future<void> set(Object? value) async {
    final mode = _database.configuration.mode;
    if (mode == SallaDataMode.api) {
      await _database._apiClient.set(path: _path, value: value);
      return;
    }
    await _firebaseReference.set(value);
    if (mode == SallaDataMode.dual && _database.configuration.mirrorWrites) {
      await _shadowWrite(
        () => _database._apiClient.set(path: _path, value: value),
        label: 'set $_path',
      );
    }
  }

  Future<void> update(Map<String, Object?> value) async {
    final mode = _database.configuration.mode;
    if (mode == SallaDataMode.api) {
      await _database._apiClient.update(path: _path, updates: value);
      return;
    }
    await _firebaseReference.update(value);
    if (mode == SallaDataMode.dual && _database.configuration.mirrorWrites) {
      await _shadowWrite(
        () => _database._apiClient.update(path: _path, updates: value),
        label: 'update $_path',
      );
    }
  }

  Future<void> remove() async {
    final mode = _database.configuration.mode;
    if (mode == SallaDataMode.api) {
      await _database._apiClient.remove(path: _path);
      return;
    }
    await _firebaseReference.remove();
    if (mode == SallaDataMode.dual && _database.configuration.mirrorWrites) {
      await _shadowWrite(
        () => _database._apiClient.remove(path: _path),
        label: 'remove $_path',
      );
    }
  }

  Future<TransactionResult> runTransaction(
    Transaction Function(Object? currentValue) transactionHandler, {
    bool applyLocally = true,
  }) async {
    final mode = _database.configuration.mode;
    if (mode != SallaDataMode.api) {
      final result = await _firebaseReference.runTransaction((currentValue) {
        final transaction = transactionHandler(currentValue);
        if (!transaction._committed) {
          return firebase.Transaction.abort();
        }
        return firebase.Transaction.success(transaction.value);
      }, applyLocally: applyLocally);
      final wrapped = TransactionResult._(
        committed: result.committed,
        snapshot: DataSnapshot._fromFirebase(
          result.snapshot,
          _database,
          path: _path,
        ),
      );
      if (mode == SallaDataMode.dual &&
          wrapped.committed &&
          _database.configuration.mirrorWrites) {
        await _shadowWrite(
          () => _database._apiClient.set(
            path: _path,
            value: wrapped.snapshot.value,
          ),
          label: 'transaction $_path',
        );
      }
      return wrapped;
    }

    const maxAttempts = 12;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final current = await _database._apiClient.read(
        path: _path,
        query: const _QueryOptions(),
        includeVersion: true,
      );
      final transaction = transactionHandler(current.value);
      if (!transaction._committed) {
        return TransactionResult._(
          committed: false,
          snapshot: DataSnapshot._fromApi(
            database: _database,
            path: _path,
            value: current.value,
          ),
        );
      }
      final result = await _database._apiClient.compareAndSet(
        path: _path,
        expectedVersion: current.version,
        value: transaction.value,
      );
      if (result.conflict) continue;
      return TransactionResult._(
        committed: true,
        snapshot: DataSnapshot._fromApi(
          database: _database,
          path: _path,
          value: result.value,
        ),
      );
    }
    throw StateError(
      'تعذر إكمال المعاملة بسبب تعديلات متزامنة متكررة. حاول مرة أخرى.',
    );
  }

  Future<void> _shadowWrite(
    Future<void> Function() operation, {
    required String label,
  }) async {
    try {
      await operation().timeout(const Duration(seconds: 8));
    } catch (error, stackTrace) {
      developer.log(
        'LightNode shadow write failed: $label',
        name: 'salla_data',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class DataSnapshot {
  final Object? value;
  final String? key;
  final DatabaseReference ref;

  const DataSnapshot._({
    required this.value,
    required this.key,
    required this.ref,
  });

  factory DataSnapshot._fromFirebase(
    firebase.DataSnapshot snapshot,
    SallaDatabase database, {
    required String path,
  }) {
    return DataSnapshot._(
      value: snapshot.value,
      key: snapshot.key,
      ref: database.ref(path),
    );
  }

  factory DataSnapshot._fromApi({
    required SallaDatabase database,
    required String path,
    required Object? value,
  }) {
    return DataSnapshot._(
      value: value,
      key: path.isEmpty ? null : path.split('/').last,
      ref: database.ref(path),
    );
  }

  bool get exists => value != null;

  DataSnapshot child(String path) {
    final cleanPath = _normalizePath(path);
    final childPath = _joinPath(ref._path, cleanPath);
    return DataSnapshot._fromApi(
      database: ref._database,
      path: childPath,
      value: _valueAtPath(value, cleanPath),
    );
  }

  Iterable<DataSnapshot> get children sync* {
    final current = value;
    if (current is! Map) return;
    for (final entry in current.entries) {
      yield child(entry.key.toString());
    }
  }

  bool hasChild(String path) => child(path).exists;

  bool get hasChildren => value is Map && (value as Map).isNotEmpty;
}

class DatabaseEvent {
  final DataSnapshot snapshot;

  const DatabaseEvent._(this.snapshot);
}

class Transaction {
  final bool _committed;
  final Object? value;

  const Transaction._(this._committed, this.value);

  static Transaction success(Object? value) => Transaction._(true, value);

  static Transaction abort() => const Transaction._(false, null);
}

class TransactionResult {
  final bool committed;
  final DataSnapshot snapshot;

  const TransactionResult._({required this.committed, required this.snapshot});
}

abstract final class ServerValue {
  static const Map<String, String> timestamp = <String, String>{
    '.sv': 'timestamp',
  };
}

class _QueryOptions {
  final String? orderByChild;
  final bool orderByKey;
  final Object? equalTo;
  final String? equalToKey;
  final bool hasEqualTo;
  final Object? startAt;
  final String? startAtKey;
  final bool hasStartAt;
  final Object? endAt;
  final String? endAtKey;
  final bool hasEndAt;
  final int? limitToLast;
  final int? limitToFirst;

  const _QueryOptions({
    this.orderByChild,
    this.orderByKey = false,
    this.equalTo,
    this.equalToKey,
    this.hasEqualTo = false,
    this.startAt,
    this.startAtKey,
    this.hasStartAt = false,
    this.endAt,
    this.endAtKey,
    this.hasEndAt = false,
    this.limitToLast,
    this.limitToFirst,
  });

  _QueryOptions copyWith({
    String? orderByChild,
    bool? orderByKey,
    Object? equalTo,
    String? equalToKey,
    bool? hasEqualTo,
    Object? startAt,
    String? startAtKey,
    bool? hasStartAt,
    Object? endAt,
    String? endAtKey,
    bool? hasEndAt,
    int? limitToLast,
    int? limitToFirst,
  }) {
    return _QueryOptions(
      orderByChild: orderByChild ?? this.orderByChild,
      orderByKey: orderByKey ?? this.orderByKey,
      equalTo: hasEqualTo == true ? equalTo : this.equalTo,
      equalToKey: hasEqualTo == true ? equalToKey : this.equalToKey,
      hasEqualTo: hasEqualTo ?? this.hasEqualTo,
      startAt: hasStartAt == true ? startAt : this.startAt,
      startAtKey: hasStartAt == true ? startAtKey : this.startAtKey,
      hasStartAt: hasStartAt ?? this.hasStartAt,
      endAt: hasEndAt == true ? endAt : this.endAt,
      endAtKey: hasEndAt == true ? endAtKey : this.endAtKey,
      hasEndAt: hasEndAt ?? this.hasEndAt,
      limitToLast: limitToLast ?? this.limitToLast,
      limitToFirst: limitToFirst ?? this.limitToFirst,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (orderByChild != null) 'orderByChild': orderByChild,
      if (orderByKey) 'orderByKey': true,
      if (hasEqualTo) 'equalTo': equalTo,
      if (hasEqualTo && equalToKey != null) 'equalToKey': equalToKey,
      if (hasStartAt) 'startAt': startAt,
      if (hasStartAt && startAtKey != null) 'startAtKey': startAtKey,
      if (hasEndAt) 'endAt': endAt,
      if (hasEndAt && endAtKey != null) 'endAtKey': endAtKey,
      if (limitToLast != null) 'limitToLast': limitToLast,
      if (limitToFirst != null) 'limitToFirst': limitToFirst,
    };
  }
}

class _ApiReadResult {
  final Object? value;
  final int version;

  const _ApiReadResult({required this.value, required this.version});
}

class _ApiCompareAndSetResult {
  final bool conflict;
  final Object? value;

  const _ApiCompareAndSetResult({required this.conflict, required this.value});
}

class _SallaApiClient {
  final String baseUrl;
  final FirebaseAuth auth;
  final Duration timeout;
  final http.Client _httpClient = http.Client();

  _SallaApiClient({
    required this.baseUrl,
    required this.auth,
    required this.timeout,
  });

  Future<_ApiReadResult> read({
    required String path,
    required _QueryOptions query,
    bool includeVersion = false,
  }) async {
    final response = await _request(
      method: 'POST',
      endpoint: '/v1/data/read',
      body: <String, Object?>{
        'path': path,
        'query': query.toJson(),
        'includeVersion': includeVersion,
      },
    );
    return _ApiReadResult(
      value: response['value'],
      version: _intValue(response['version']),
    );
  }

  Future<void> set({required String path, required Object? value}) async {
    await _request(
      method: 'PUT',
      endpoint: '/v1/data',
      body: <String, Object?>{'path': path, 'value': value},
    );
  }

  Future<void> update({
    required String path,
    required Map<String, Object?> updates,
  }) async {
    await _request(
      method: 'PATCH',
      endpoint: '/v1/data',
      body: <String, Object?>{'path': path, 'updates': updates},
    );
  }

  Future<void> remove({required String path}) async {
    await _request(
      method: 'DELETE',
      endpoint: '/v1/data',
      body: <String, Object?>{'path': path},
    );
  }

  Future<_ApiCompareAndSetResult> compareAndSet({
    required String path,
    required int expectedVersion,
    required Object? value,
  }) async {
    try {
      final response = await _request(
        method: 'POST',
        endpoint: '/v1/data/compare-and-set',
        body: <String, Object?>{
          'path': path,
          'expectedVersion': expectedVersion,
          'value': value,
        },
      );
      return _ApiCompareAndSetResult(conflict: false, value: response['value']);
    } on SallaApiException catch (error) {
      if (error.statusCode == 409) {
        return const _ApiCompareAndSetResult(conflict: true, value: null);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String endpoint,
    required Map<String, Object?> body,
  }) async {
    final uri = _endpointUri(baseUrl, endpoint);
    final token = await auth.currentUser?.getIdToken();
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'accept': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
    late final http.Response response;
    final encodedBody = jsonEncode(body);
    switch (method) {
      case 'PUT':
        response = await _httpClient
            .put(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      case 'PATCH':
        response = await _httpClient
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      case 'DELETE':
        response = await _httpClient
            .delete(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
      default:
        response = await _httpClient
            .post(uri, headers: headers, body: encodedBody)
            .timeout(timeout);
        break;
    }
    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    final payload = decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SallaApiException(
        statusCode: response.statusCode,
        code: payload['code']?.toString() ?? 'request_failed',
        message: payload['message']?.toString() ??
            'تعذر الاتصال بخدمة سلة. حاول مرة أخرى.',
      );
    }
    return payload;
  }
}

class SallaApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const SallaApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class _SallaRealtimeClient {
  static const Duration _readyTimeout = Duration(seconds: 12);

  final String baseUrl;
  final FirebaseAuth auth;
  final Map<String, _RealtimeSubscription> _subscriptions =
      <String, _RealtimeSubscription>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  Timer? _readyTimer;
  int _reconnectAttempt = 0;
  bool _connecting = false;
  bool _socketReady = false;
  bool _disposed = false;
  bool _reconnectRequested = false;

  _SallaRealtimeClient({required this.baseUrl, required this.auth});

  Stream<Object?> subscribe({
    required String path,
    required _QueryOptions query,
  }) {
    final id = _randomId();
    late final StreamController<Object?> controller;
    controller = StreamController<Object?>.broadcast(
      onListen: () {
        _subscriptions[id] = _RealtimeSubscription(
          id: id,
          path: path,
          query: query,
          controller: controller,
        );
        _ensureConnected();
        _sendSubscription(_subscriptions[id]!);
      },
      onCancel: () {
        _subscriptions.remove(id);
        _send(<String, Object?>{'type': 'unsubscribe', 'id': id});
        if (_subscriptions.isEmpty) {
          _closeChannel();
        }
      },
    );
    return controller.stream;
  }

  void reconnectForAuthenticationChange() {
    if (_subscriptions.isEmpty || _disposed) return;
    _reconnectRequested = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    if (!_connecting) {
      _reconnectRequested = false;
      unawaited(_ensureConnected());
    }
  }

  Future<void> _ensureConnected() async {
    if (_disposed ||
        _subscriptions.isEmpty ||
        _connecting ||
        _channel != null) {
      return;
    }
    if (baseUrl.trim().isEmpty) {
      _emitError(
        StateError('لم يتم ضبط عنوان خدمة سلة. عرّف SALLA_API_BASE_URL أولاً.'),
      );
      return;
    }
    _connecting = true;
    try {
      _socketReady = false;
      final channel = WebSocketChannel.connect(
        _webSocketUri(baseUrl, '/v1/realtime'),
      );
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        _handleMessage,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: true,
      );
      _startReadyTimer(channel);
      final token = await auth.currentUser?.getIdToken();
      _send(<String, Object?>{
        'type': 'hello',
        if (token != null && token.isNotEmpty) 'token': token,
      });
    } catch (error, stackTrace) {
      developer.log(
        'Realtime connection failed',
        name: 'salla_data',
        error: error,
        stackTrace: stackTrace,
      );
      _closeChannel();
      _scheduleReconnect();
    } finally {
      _connecting = false;
      if (_reconnectRequested && !_disposed && _subscriptions.isNotEmpty) {
        _reconnectRequested = false;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _closeChannel();
        unawaited(_ensureConnected());
      }
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage.toString());
      if (decoded is! Map) return;
      final message = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (message['type'] == 'ready') {
        _readyTimer?.cancel();
        _readyTimer = null;
        _socketReady = true;
        _reconnectAttempt = 0;
        for (final subscription in _subscriptions.values) {
          _sendSubscription(subscription);
        }
      } else if (message['type'] == 'snapshot') {
        final id = message['id']?.toString() ?? '';
        _subscriptions[id]?.controller.add(message['value']);
      } else if (message['type'] == 'error') {
        final id = message['id']?.toString() ?? '';
        final error = SallaApiException(
          statusCode: _intValue(message['statusCode']),
          code: message['code']?.toString() ?? 'realtime_error',
          message:
              message['message']?.toString() ?? 'تعذر تحديث البيانات اللحظية.',
        );
        if (id.isEmpty) {
          _emitError(error);
        } else {
          _subscriptions[id]?.controller.addError(error);
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'Invalid realtime message',
        name: 'salla_data',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _startReadyTimer(WebSocketChannel channel) {
    _readyTimer?.cancel();
    _readyTimer = Timer(_readyTimeout, () {
      if (_disposed || _socketReady || !identical(_channel, channel)) return;
      developer.log(
        'Realtime handshake timed out',
        name: 'salla_data',
      );
      _closeChannel();
      _scheduleReconnect();
    });
  }

  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    developer.log(
      'Realtime socket error',
      name: 'salla_data',
      error: error,
      stackTrace: stackTrace,
    );
    _closeChannel();
    _scheduleReconnect();
  }

  void _handleSocketDone() {
    _closeChannel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _subscriptions.isEmpty || _reconnectTimer != null) return;
    final seconds = min(30, pow(2, min(_reconnectAttempt, 5)).toInt());
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      _ensureConnected();
    });
  }

  void _sendSubscription(_RealtimeSubscription subscription) {
    if (!_socketReady) return;
    _send(<String, Object?>{
      'type': 'subscribe',
      'id': subscription.id,
      'path': subscription.path,
      'query': subscription.query.toJson(),
    });
  }

  void _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      _closeChannel();
      _scheduleReconnect();
    }
  }

  void _emitError(Object error) {
    for (final subscription in _subscriptions.values) {
      subscription.controller.addError(error);
    }
  }

  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    _socketReady = false;
    _readyTimer?.cancel();
    _readyTimer = null;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
  }

  void dispose() {
    _disposed = true;
    _reconnectRequested = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    for (final subscription in _subscriptions.values) {
      subscription.controller.close();
    }
    _subscriptions.clear();
  }
}

class _RealtimeSubscription {
  final String id;
  final String path;
  final _QueryOptions query;
  final StreamController<Object?> controller;

  const _RealtimeSubscription({
    required this.id,
    required this.path,
    required this.query,
    required this.controller,
  });
}

Uri _endpointUri(String baseUrl, String endpoint) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    throw StateError(
      'لم يتم ضبط عنوان خدمة سلة. عرّف SALLA_API_BASE_URL أولاً.',
    );
  }
  final base = Uri.parse(trimmed);
  final basePath = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(path: '$basePath$endpoint');
}

Uri _webSocketUri(String baseUrl, String endpoint) {
  final uri = _endpointUri(baseUrl, endpoint);
  return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
}

String _normalizePath(String path) {
  return path
      .trim()
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+$'), '')
      .replaceAll(RegExp(r'/+'), '/');
}

String _joinPath(String base, String child) {
  if (base.isEmpty) return child;
  if (child.isEmpty) return base;
  return '$base/$child';
}

String _generatePushKey() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final timePart = timestamp.toRadixString(36).padLeft(9, '0');
  final random = Random.secure();
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final randomPart = List<String>.generate(
    12,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  return '-$timePart$randomPart';
}

String _randomId() {
  final random = Random.secure();
  final firstPart = random.nextInt(1073741824).toRadixString(36);
  final secondPart = random.nextInt(1073741824).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '$firstPart$secondPart';
}

const Map<String, Set<String>> sallaImportantPushTypesByRole = {
  'driver': {
    'driver_offer',
    'driver_urgent_alert_resolved',
    'driver_support_reply',
    'driver_announcement',
  },
  'store': {
    'store_driver_arrived',
    'store_urgent_alert_resolved',
  },
  'customer': {
    'customer_driver_arrived',
  },
};

bool sallaPushTypeIsImportantForRole(String role, String type) {
  return sallaImportantPushTypesByRole[role.trim().toLowerCase()]?.contains(
        type.trim(),
      ) ==
      true;
}

bool sallaPushTargetsCurrentAccount(
  Map<String, dynamic> data, {
  required String role,
  required String entityId,
}) {
  final normalizedRole = role.trim().toLowerCase();
  final normalizedEntityId = entityId.trim();
  final type = data['type']?.toString().trim() ?? '';
  if (normalizedEntityId.isEmpty ||
      !sallaPushTypeIsImportantForRole(normalizedRole, type)) {
    return false;
  }
  final recipientRole =
      data['recipientRole']?.toString().trim().toLowerCase() ?? '';
  if (recipientRole != normalizedRole) return false;
  final recipientScope = data['recipientScope']?.toString().trim() ?? '';
  if (recipientScope == 'all_${normalizedRole}s') return true;
  final recipientEntityId = data['recipientEntityId']?.toString().trim() ?? '';
  return recipientEntityId.isNotEmpty &&
      recipientEntityId == normalizedEntityId;
}

String sallaPushEventKey(
  Map<String, dynamic> data, {
  String messageId = '',
}) {
  for (final field in const [
    'notificationId',
    'supportMessageId',
    'announcementId',
    'testId',
  ]) {
    final value = data[field]?.toString().trim() ?? '';
    if (value.isNotEmpty) return '$field:$value';
  }
  final type = data['type']?.toString().trim() ?? '';
  final orderId = data['orderId']?.toString().trim() ?? '';
  final expiresAt = data['expiresAt']?.toString().trim() ?? '';
  final normalizedMessageId = messageId.trim();
  return [type, orderId, expiresAt, normalizedMessageId]
      .where((value) => value.isNotEmpty)
      .join('|');
}

class SallaPushEventDeduplicator {
  final Duration window;
  final Map<String, DateTime> _acceptedAtByKey = {};

  SallaPushEventDeduplicator({this.window = const Duration(minutes: 5)});

  bool accept(
    Map<String, dynamic> data, {
    String messageId = '',
    DateTime? now,
  }) {
    final key = sallaPushEventKey(data, messageId: messageId);
    if (key.isEmpty) return false;
    final acceptedAt = now ?? DateTime.now();
    _acceptedAtByKey.removeWhere(
      (_, previousAt) => acceptedAt.difference(previousAt) >= window,
    );
    final previousAt = _acceptedAtByKey[key];
    if (previousAt != null && acceptedAt.difference(previousAt) < window) {
      return false;
    }
    _acceptedAtByKey[key] = acceptedAt;
    return true;
  }

  void clear() => _acceptedAtByKey.clear();
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Object? _valueAtPath(Object? value, String path) {
  if (path.isEmpty) return value;
  Object? current = value;
  for (final segment in path.split('/')) {
    if (current is! Map || !current.containsKey(segment)) return null;
    current = current[segment];
  }
  return current;
}
