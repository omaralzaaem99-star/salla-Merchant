part of sala_store;

const int sallaCashUnit = 250;
const String sallaCashRoundingLedgerVersion = 'salla_finance_v3_gross_cash';
const String directStoreSettlementMode = 'cash_pickup_net';
const String deferredStoreSettlementMode = 'deferred_company_settlement';

String normalizeStoreSettlementMode(dynamic value) {
  return value?.toString().trim() == deferredStoreSettlementMode
      ? deferredStoreSettlementMode
      : directStoreSettlementMode;
}

int roundCustomerCashTotal(int value) {
  if (value <= 0) return 0;
  final remainder = value % sallaCashUnit;
  return remainder == 0 ? value : value + sallaCashUnit - remainder;
}

int roundStoreCashPayout(int value) {
  if (value <= 0) return 0;
  return value - (value % sallaCashUnit);
}

bool storeOrderWasCancelledByCustomerBeforeAcceptance(
  Map<String, dynamic> data,
) {
  final status = data['status']?.toString().trim().toLowerCase() ?? '';
  final storeStage =
      data['storeStage']?.toString().trim() ?? 'awaitingAcceptance';
  final cancelledBy =
      data['cancelledBy']?.toString().trim().toLowerCase() ?? '';
  final cancelReason = data['cancelReason']?.toString().trim() ?? '';
  final hasCancelledStatus =
      const {
        'cancelled',
        'canceled',
        'customercancelled',
        'cancelledbycustomer',
      }.contains(status) ||
      data['isCancelled'] == true;
  final cancelledByCustomer =
      cancelledBy == 'customer' ||
      data['customerCancelled'] == true ||
      cancelReason.contains('الزبون');
  return hasCancelledStatus &&
      cancelledByCustomer &&
      (storeStage.isEmpty || storeStage == 'awaitingAcceptance');
}

bool storeOrderUsesCashRounding(Map<String, dynamic> data, String status) {
  if (data['orderSource']?.toString() == 'store_external') return false;
  final method = data['paymentMethod']?.toString() ?? 'الدفع عند الاستلام';
  final provider =
      data['paymentProvider']?.toString().trim().toLowerCase() ??
      (method.contains('عند الاستلام') ? 'cash' : '');
  final collectionMode = data['paymentCollectionMode']?.toString() ?? '';
  final isCashOrder =
      provider == 'cash' ||
      collectionMode == 'driver_cash_collection' ||
      method.contains('عند الاستلام');
  final driverStage = data['driverStage']?.toString() ?? '';
  final terminal =
      status == 'cancelled' ||
      status == 'delivered' ||
      driverStage == 'delivered';
  return isCashOrder &&
      (data['financialLedgerVersion']?.toString() ==
              sallaCashRoundingLedgerVersion ||
          !terminal);
}

class StoreOrderItem {
  final String name;
  final int quantity;
  final String unit;
  final int lineTotal;

  const StoreOrderItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.lineTotal,
  });
}

class StoreOrder {
  final String databaseKey;
  final String number;
  final String orderSource;
  final String customerId;
  final String driverId;
  final String provinceId;
  final String provinceName;
  final String branchId;
  final String branchName;
  final String serviceZoneId;
  final String serviceZoneName;
  final String deliveryZoneId;
  final String deliveryZoneName;
  final String deliveryAreaId;
  final String deliveryAreaName;
  final String storeExternalServiceType;
  final DateTime? scheduledDeliveryAt;
  final bool storeExternalLate;
  final String offeredDriverId;
  final String offeredDriverName;
  final String customerName;
  final String phone;
  final String address;
  final String note;
  final String paymentMethod;
  final String paymentProvider;
  final String paymentCollectionMode;
  final int total;
  final int storeGrossAmount;
  final int storeFundedDiscount;
  final int platformFundedDiscount;
  final int storeNetAmount;
  final String storeSettlementMode;
  final int driverPaysStoreAmount;
  final int customerTotalToCollect;
  final int deliveryFee;
  final int serviceFee;
  final int companyShareAmount;
  final int driverNetFare;
  final int driverCashCustodyAmount;
  final int driverCompanyDepositDue;
  final DateTime createdAt;
  final String updatedAt;
  final String status;
  final String storeStage;
  final String driverStage;
  final String dispatchStatus;
  final String driverName;
  final String driverPhone;
  final String cancelledDriverId;
  final String cancelledDriverName;
  final double? driverLat;
  final double? driverLng;
  final DateTime? driverLocationUpdatedAt;
  final String storePaymentConfirmedAt;
  final String storePaymentConfirmedBy;
  final String storeSettlementStatus;
  final String storeSettlementPaidAt;
  final String storeSettlementPaymentReference;
  final String cancellationStage;
  final String goodsDisposition;
  final int storeCancellationPayableAmount;
  final DateTime? estimatedReadyAt;
  final DateTime? driverDispatchScheduledAt;
  final DateTime? offerExpiresAt;
  final bool autoDispatchEnabled;
  final int dispatchLeadMinutes;
  final Set<String> skippedDriverIds;
  final int customerRating;
  final String ratingComment;
  final List<StoreOrderItem> items;

  const StoreOrder({
    required this.databaseKey,
    required this.number,
    this.orderSource = '',
    required this.customerId,
    required this.driverId,
    this.provinceId = '',
    this.provinceName = '',
    this.branchId = '',
    this.branchName = '',
    this.serviceZoneId = '',
    this.serviceZoneName = '',
    this.deliveryZoneId = '',
    this.deliveryZoneName = '',
    this.deliveryAreaId = '',
    this.deliveryAreaName = '',
    this.storeExternalServiceType = '',
    this.scheduledDeliveryAt,
    this.storeExternalLate = false,
    required this.offeredDriverId,
    required this.offeredDriverName,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.note,
    required this.paymentMethod,
    required this.paymentProvider,
    required this.paymentCollectionMode,
    required this.total,
    required this.storeGrossAmount,
    required this.storeFundedDiscount,
    required this.platformFundedDiscount,
    required this.storeNetAmount,
    required this.storeSettlementMode,
    required this.driverPaysStoreAmount,
    required this.customerTotalToCollect,
    this.deliveryFee = 0,
    this.serviceFee = 0,
    this.companyShareAmount = 0,
    this.driverNetFare = 0,
    this.driverCashCustodyAmount = 0,
    this.driverCompanyDepositDue = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.storeStage,
    required this.driverStage,
    required this.dispatchStatus,
    required this.driverName,
    required this.driverPhone,
    this.cancelledDriverId = '',
    this.cancelledDriverName = '',
    this.driverLat,
    this.driverLng,
    this.driverLocationUpdatedAt,
    required this.storePaymentConfirmedAt,
    required this.storePaymentConfirmedBy,
    required this.storeSettlementStatus,
    required this.storeSettlementPaidAt,
    required this.storeSettlementPaymentReference,
    required this.cancellationStage,
    required this.goodsDisposition,
    required this.storeCancellationPayableAmount,
    required this.estimatedReadyAt,
    required this.driverDispatchScheduledAt,
    required this.offerExpiresAt,
    required this.autoDispatchEnabled,
    required this.dispatchLeadMinutes,
    required this.skippedDriverIds,
    required this.customerRating,
    required this.ratingComment,
    required this.items,
  });

  factory StoreOrder.fromFirebase(String key, Map<String, dynamic> data) {
    final items = <StoreOrderItem>[];
    final rawItems = data['items'];
    for (final item in firebaseOrderItemMaps(rawItems)) {
      final quantity = firebaseIntValue(item['quantity'], 1);
      final unitPrice = firebaseIntValue(
        item['unitPrice'],
        firebaseIntValue(item['price']),
      );
      items.add(
        StoreOrderItem(
          name: item['name']?.toString() ?? 'منتج',
          quantity: quantity,
          unit: item['unit']?.toString() ?? '',
          lineTotal: firebaseIntValue(item['lineTotal'], unitPrice * quantity),
        ),
      );
    }
    final skippedDriverIds = <String>{};
    final rawSkipped = data['skippedDriverIds'];
    if (rawSkipped is Map) {
      for (final entry in rawSkipped.entries) {
        if (entry.value == true) skippedDriverIds.add(entry.key.toString());
      }
    }
    final status = data['status']?.toString() ?? 'pending';
    final orderSource = data['orderSource']?.toString().trim() ?? '';
    final isStoreExternal = orderSource == 'store_external';
    final usesCashRounding = storeOrderUsesCashRounding(data, status);
    final subtotal = firebaseIntValue(
      data['subtotal'],
      items.fold<int>(0, (sum, item) => sum + item.lineTotal),
    );
    final exactCustomerTotal =
        firebaseIntValue(data['total']) +
        firebaseIntValue(data['customerExtraDeliveryFee']);
    final storedCustomerTotal = firebaseIntValue(
      data['customerTotalToCollect'],
      exactCustomerTotal,
    );
    final customerTotal = usesCashRounding
        ? roundCustomerCashTotal(storedCustomerTotal)
        : storedCustomerTotal;
    final storeCommissionPercent = isStoreExternal
        ? firebaseIntValue(data['storeCommissionPercent']).clamp(0, 100).toInt()
        : normalizedStoreCommissionPercent(
            firebaseIntValue(
              data['storeCommissionPercent'],
              defaultStoreCommissionPercent,
            ),
          );
    final storeGrossAmount = firebaseIntValue(
      data['storeGrossAmount'],
      subtotal,
    );
    final storeFundedDiscount = firebaseIntValue(data['storeFundedDiscount']);
    final platformFundedDiscount = firebaseIntValue(
      data['platformFundedDiscount'],
      firebaseIntValue(data['discount']),
    );
    final commissionBase = firebaseIntValue(
      data['commissionBaseAmount'],
      storeGrossAmount - storeFundedDiscount,
    );
    final safeCommissionBase = commissionBase < 0 ? 0 : commissionBase;
    final storeCommissionAmount = firebaseIntValue(
      data['storeCommissionAmount'],
      (safeCommissionBase * storeCommissionPercent / 100).round(),
    );
    final storedStoreNetAmount = firebaseIntValue(
      data['storeNetAmount'],
      safeCommissionBase - storeCommissionAmount,
    );
    final safeStoredStoreNetAmount = storedStoreNetAmount < 0
        ? 0
        : storedStoreNetAmount;
    final safeStoreNetAmount = usesCashRounding
        ? roundStoreCashPayout(safeStoredStoreNetAmount)
        : safeStoredStoreNetAmount;
    final storeSettlementMode = normalizeStoreSettlementMode(
      data['storeSettlementMode'],
    );
    final storedDriverPaysStoreAmount =
        storeSettlementMode == deferredStoreSettlementMode
        ? 0
        : firebaseIntValue(data['driverPaysStoreAmount'], safeStoreNetAmount);
    final driverPaysStoreAmount = usesCashRounding
        ? roundStoreCashPayout(storedDriverPaysStoreAmount)
        : storedDriverPaysStoreAmount;
    return StoreOrder(
      databaseKey: key,
      number: data['orderNumber']?.toString() ?? key,
      orderSource: orderSource,
      customerId: data['customerId']?.toString() ?? '',
      driverId: data['driverId']?.toString() ?? '',
      provinceId: data['provinceId']?.toString() ?? '',
      provinceName: data['provinceName']?.toString() ?? '',
      branchId: data['branchId']?.toString() ?? '',
      branchName: data['branchName']?.toString() ?? '',
      serviceZoneId: data['serviceZoneId']?.toString() ?? '',
      serviceZoneName: data['serviceZoneName']?.toString() ?? '',
      deliveryZoneId: data['deliveryZoneId']?.toString() ?? '',
      deliveryZoneName: data['deliveryZoneName']?.toString() ?? '',
      deliveryAreaId: data['deliveryAreaId']?.toString() ?? '',
      deliveryAreaName: data['deliveryAreaName']?.toString() ?? '',
      storeExternalServiceType:
          data['storeExternalServiceType']?.toString() ?? '',
      scheduledDeliveryAt: DateTime.tryParse(
        data['scheduledDeliveryAt']?.toString() ?? '',
      ),
      storeExternalLate: data['storeExternalLate'] == true,
      offeredDriverId: data['offeredDriverId']?.toString() ?? '',
      offeredDriverName: data['offeredDriverName']?.toString() ?? '',
      customerName: data['customerName']?.toString().trim().isNotEmpty == true
          ? data['customerName'].toString()
          : isStoreExternal
          ? 'مستلم خارجي'
          : 'زبون سلة',
      phone: data['phoneNumber']?.toString() ?? '-',
      address: data['deliveryAddressText']?.toString() ?? '-',
      note: data['note']?.toString() ?? '',
      paymentMethod: data['paymentMethod']?.toString() ?? 'الدفع عند الاستلام',
      paymentProvider: data['paymentProvider']?.toString() ?? 'cash',
      paymentCollectionMode:
          data['paymentCollectionMode']?.toString() ??
          (data['financialLedger'] is Map
              ? (data['financialLedger'] as Map)['collectionMode']
                        ?.toString() ??
                    ''
              : ''),
      total: customerTotal,
      storeGrossAmount: storeGrossAmount,
      storeFundedDiscount: storeFundedDiscount,
      platformFundedDiscount: platformFundedDiscount,
      storeNetAmount: safeStoreNetAmount,
      storeSettlementMode: storeSettlementMode,
      driverPaysStoreAmount: driverPaysStoreAmount,
      customerTotalToCollect: customerTotal,
      deliveryFee: firebaseIntValue(data['deliveryFee']),
      serviceFee: firebaseIntValue(data['serviceFee']),
      companyShareAmount: firebaseIntValue(data['companyShareAmount']),
      driverNetFare: firebaseIntValue(data['driverNetFare']),
      driverCashCustodyAmount: firebaseIntValue(
        data['driverCashCustodyAmount'],
      ),
      driverCompanyDepositDue: firebaseIntValue(
        data['driverCompanyDepositDue'],
      ),
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: data['updatedAt']?.toString().trim() ?? '',
      status: status,
      storeStage: data['storeStage']?.toString() ?? legacyStoreStage(status),
      driverStage: data['driverStage']?.toString() ?? 'waitingForStore',
      dispatchStatus: data['dispatchStatus']?.toString() ?? 'awaitingStore',
      driverName: data['driverName']?.toString() ?? '',
      driverPhone: data['driverPhone']?.toString() ?? '',
      cancelledDriverId: data['cancelledDriverId']?.toString() ?? '',
      cancelledDriverName: data['cancelledDriverName']?.toString() ?? '',
      driverLat: double.tryParse(data['driverLat']?.toString() ?? ''),
      driverLng: double.tryParse(data['driverLng']?.toString() ?? ''),
      driverLocationUpdatedAt: DateTime.tryParse(
        data['driverLocationUpdatedAt']?.toString() ?? '',
      ),
      storePaymentConfirmedAt:
          data['storePaymentConfirmedAt']?.toString() ?? '',
      storePaymentConfirmedBy:
          data['storePaymentConfirmedBy']?.toString() ?? '',
      storeSettlementStatus:
          data['storeSettlementStatus']?.toString() ?? 'unsettled',
      storeSettlementPaidAt: data['storeSettlementPaidAt']?.toString() ?? '',
      storeSettlementPaymentReference:
          data['storeSettlementPaymentReference']?.toString() ?? '',
      cancellationStage: data['cancellationStage']?.toString() ?? '',
      goodsDisposition: data['goodsDisposition']?.toString() ?? '',
      storeCancellationPayableAmount: firebaseIntValue(
        data['storeCancellationPayableAmount'],
      ),
      estimatedReadyAt: DateTime.tryParse(
        data['estimatedReadyAt']?.toString() ?? '',
      ),
      driverDispatchScheduledAt: DateTime.tryParse(
        data['driverDispatchScheduledAt']?.toString() ?? '',
      ),
      offerExpiresAt: DateTime.tryParse(
        data['offerExpiresAt']?.toString() ?? '',
      ),
      autoDispatchEnabled: data['autoDispatchEnabled'] != false,
      dispatchLeadMinutes: firebaseIntValue(
        data['dispatchLeadMinutes'],
        defaultDispatchLeadMinutes,
      ).clamp(minDispatchLeadMinutes, maxDispatchLeadMinutes).toInt(),
      skippedDriverIds: skippedDriverIds,
      customerRating: int.tryParse(data['storeRating']?.toString() ?? '0') ?? 0,
      ratingComment: data['ratingComment']?.toString() ?? '',
      items: items,
    );
  }

  bool get isDelivered => status == 'delivered' || driverStage == 'delivered';

  bool get isStoreExternal => orderSource == 'store_external';

  String get sourceLabel => isStoreExternal ? 'طلب مندوبك' : 'طلب من منصة سلة';

  String get responsibleDriverId {
    final cancelledId = cancelledDriverId.trim();
    if (isCancelled && cancelledId.isNotEmpty) return cancelledId;
    return driverId.trim();
  }

  String get responsibleDriverName {
    final cancelledName = cancelledDriverName.trim();
    if (isCancelled && cancelledName.isNotEmpty) return cancelledName;
    final assignedName = driverName.trim();
    if (assignedName.isNotEmpty) return assignedName;
    return responsibleDriverId;
  }

  String get responsibleDriverLabel {
    if (isCancelled) return 'السائق وقت الإلغاء';
    if (isDelivered) return 'السائق الذي سلّم الطلب';
    return 'السائق';
  }

  bool get hasTrustedLiveDriverLocation =>
      isStoreExternal &&
      driverId.trim().isNotEmpty &&
      driverLat != null &&
      driverLng != null &&
      driverLat! >= -90 &&
      driverLat! <= 90 &&
      driverLng! >= -180 &&
      driverLng! <= 180 &&
      const <String>{'accepted', 'arrivedStore'}.contains(driverStage);

  bool get isCancelled =>
      status == 'cancelled' ||
      storeStage == 'cancelled' ||
      driverStage == 'cancelled';

  bool get requiresDriverCashPayment {
    final cashOrder =
        paymentCollectionMode == 'driver_cash_collection' ||
        paymentProvider == 'cash' ||
        paymentMethod == 'الدفع عند الاستلام';
    return cashOrder && driverPaysStoreAmount > 0;
  }

  bool get usesDeferredSettlement =>
      storeSettlementMode == deferredStoreSettlementMode;

  bool get driverArrivedAtStore => const {
    'arrivedStore',
    'pickedUp',
    'arrivedCustomer',
    'delivered',
  }.contains(driverStage);

  bool get storeSettlementPaid =>
      storeSettlementStatus == 'paid' ||
      storeSettlementStatus == 'paid_at_pickup' ||
      storeSettlementPaidAt.trim().isNotEmpty;

  bool get returnedCancellationPayable =>
      isCancelled &&
      cancellationStage == 'financial_resolved' &&
      goodsDisposition == 'returned_to_store' &&
      storeCancellationPayableAmount > 0;

  bool get isStoreSettlementRecord =>
      (isDelivered && !isCancelled) ||
      returnedCancellationPayable ||
      (!usesDeferredSettlement &&
          storePaymentConfirmedAt.trim().isNotEmpty &&
          driverPaysStoreAmount > 0);

  int get storeSettlementDisplayAmount => returnedCancellationPayable
      ? storeCancellationPayableAmount
      : (!usesDeferredSettlement && driverPaysStoreAmount > 0
            ? driverPaysStoreAmount
            : storeNetAmount);

  bool get canCancelStoreExternalDelivery =>
      isStoreExternal &&
      !isCancelled &&
      !isDelivered &&
      storePaymentConfirmedAt.trim().isEmpty &&
      !const <String>{
        'pickedUp',
        'arrivedCustomer',
        'returningToStore',
        'delivered',
      }.contains(driverStage);
}

Map<String, dynamic> storeExternalObject(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((key, nested) => MapEntry(key.toString(), nested));
}

Object? storeExternalCanonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        key: storeExternalCanonicalValue(
          value.entries
              .firstWhere((entry) => entry.key.toString() == key)
              .value,
        ),
    };
  }
  if (value is List) {
    return value.map(storeExternalCanonicalValue).toList(growable: false);
  }
  return value;
}

String storeExternalPayloadSignature(Map<String, dynamic> payload) =>
    jsonEncode(storeExternalCanonicalValue(payload));

class StoreExternalDeliveryArea {
  final String id;
  final String nameAr;
  final List<String> aliases;
  final int immediateFee;
  final int scheduledFee;
  final double distanceKm;
  final SallaGeoPoint? pricingAnchor;
  final bool requiresDeliveryPin;

  const StoreExternalDeliveryArea({
    required this.id,
    required this.nameAr,
    required this.aliases,
    required this.immediateFee,
    required this.scheduledFee,
    required this.distanceKm,
    this.pricingAnchor,
    this.requiresDeliveryPin = false,
  });

  factory StoreExternalDeliveryArea.fromMap(Map<String, dynamic> data) {
    final anchor = storeExternalObject(data['pricingAnchor']);
    final lat = double.tryParse(anchor['lat']?.toString() ?? '');
    final lng = double.tryParse(anchor['lng']?.toString() ?? '');
    final rawAliases = data['aliases'];
    final aliasValues = rawAliases is Map
        ? rawAliases.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key)
        : rawAliases is List
        ? rawAliases
        : const <Object?>[];
    return StoreExternalDeliveryArea(
      id: data['id']?.toString() ?? '',
      nameAr: data['nameAr']?.toString() ?? '',
      aliases: aliasValues
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      immediateFee: firebaseIntValue(data['immediateFee']),
      scheduledFee: firebaseIntValue(data['scheduledFee']),
      requiresDeliveryPin: data['requiresDeliveryPin'] == true,
      distanceKm:
          double.tryParse(data['distanceKm']?.toString() ?? '') ??
          double.infinity,
      pricingAnchor:
          lat != null &&
              lng != null &&
              lat.isFinite &&
              lng.isFinite &&
              lat.abs() <= 90 &&
              lng.abs() <= 180
          ? SallaGeoPoint(lat, lng)
          : null,
    );
  }

  bool matches(String query) {
    return searchScore(query) != null;
  }

  int? searchScore(String query) =>
      sallaArabicPlaceSearchScore(query, [nameAr, ...aliases]);
}

class StoreExternalDeliveryConfiguration {
  final bool enabled;
  final bool adminApproved;
  final bool approvalRequired;
  final bool globalEnabled;
  final bool storeEnabled;
  final String serviceAvailabilityMessage;
  final int serviceNextTransitionAtMs;
  final int serviceOpensAtMinute;
  final int serviceClosesAtMinute;
  final List<StoreExternalDeliveryArea> areas;
  final bool requiresDeliveryPin;
  final String subscriptionStatus;
  final DateTime? subscriptionStartsAt;
  final DateTime? subscriptionEndsAt;

  const StoreExternalDeliveryConfiguration({
    required this.enabled,
    required this.adminApproved,
    required this.approvalRequired,
    required this.globalEnabled,
    required this.storeEnabled,
    required this.serviceAvailabilityMessage,
    required this.serviceNextTransitionAtMs,
    required this.serviceOpensAtMinute,
    required this.serviceClosesAtMinute,
    required this.areas,
    this.requiresDeliveryPin = false,
    this.subscriptionStatus = 'none',
    this.subscriptionStartsAt,
    this.subscriptionEndsAt,
  });

  factory StoreExternalDeliveryConfiguration.fromMap(
    Map<String, dynamic> data,
  ) {
    final rawAreas = data['areas'];
    final serviceAvailability = storeExternalObject(
      data['serviceAvailability'],
    );
    final areas = rawAreas is List
        ? rawAreas
              .whereType<Map>()
              .map(
                (value) => StoreExternalDeliveryArea.fromMap(
                  storeExternalObject(value),
                ),
              )
              .where((area) => area.id.isNotEmpty && area.nameAr.isNotEmpty)
              .toList(growable: false)
        : const <StoreExternalDeliveryArea>[];
    return StoreExternalDeliveryConfiguration(
      enabled: data['enabled'] == true,
      adminApproved: data['adminApproved'] == true,
      approvalRequired: data['approvalRequired'] == true,
      globalEnabled: data['globalEnabled'] == true,
      storeEnabled: data['storeEnabled'] == true,
      serviceAvailabilityMessage:
          serviceAvailability['messageAr']?.toString().trim() ?? '',
      serviceNextTransitionAtMs: firebaseIntValue(
        serviceAvailability['nextTransitionAtMs'],
      ),
      serviceOpensAtMinute: firebaseIntValue(
        serviceAvailability['opensAtMinute'],
        8 * 60,
      ).clamp(0, 1439).toInt(),
      serviceClosesAtMinute: firebaseIntValue(
        serviceAvailability['closesAtMinute'],
        23 * 60,
      ).clamp(0, 1439).toInt(),
      areas: areas,
      requiresDeliveryPin: data['requiresDeliveryPin'] == true,
      subscriptionStatus:
          storeExternalObject(data['subscription'])['status']?.toString() ??
          'none',
      subscriptionStartsAt: DateTime.tryParse(
        storeExternalObject(data['subscription'])['startsAt']?.toString() ?? '',
      ),
      subscriptionEndsAt: DateTime.tryParse(
        storeExternalObject(data['subscription'])['endsAt']?.toString() ?? '',
      ),
    );
  }
}

class StoreExternalDeliveryQuote {
  final String fingerprint;
  final String areaName;
  final String serviceType;
  final DateTime? scheduledDeliveryAt;
  final int goodsAmount;
  final int deliveryFee;
  final int serviceFee;
  final int customerTotalToCollect;
  final double? deliveryLat;
  final double? deliveryLng;
  final double distanceKm;

  const StoreExternalDeliveryQuote({
    required this.fingerprint,
    required this.areaName,
    required this.serviceType,
    required this.scheduledDeliveryAt,
    required this.goodsAmount,
    required this.deliveryFee,
    required this.serviceFee,
    required this.customerTotalToCollect,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.distanceKm,
  });

  factory StoreExternalDeliveryQuote.fromMap(Map<String, dynamic> data) {
    final area = storeExternalObject(data['area']);
    final pricing = storeExternalObject(data['pricing']);
    return StoreExternalDeliveryQuote(
      fingerprint: data['quoteFingerprint']?.toString() ?? '',
      areaName: area['nameAr']?.toString() ?? '',
      serviceType: data['serviceType']?.toString() ?? '',
      scheduledDeliveryAt: DateTime.tryParse(
        data['scheduledDeliveryAt']?.toString() ?? '',
      ),
      goodsAmount: firebaseIntValue(pricing['goodsAmount']),
      deliveryFee: firebaseIntValue(pricing['deliveryFee']),
      serviceFee: firebaseIntValue(pricing['serviceFee']),
      customerTotalToCollect: firebaseIntValue(
        pricing['customerTotalToCollect'],
      ),
      deliveryLat: double.tryParse(data['deliveryLat']?.toString() ?? ''),
      deliveryLng: double.tryParse(data['deliveryLng']?.toString() ?? ''),
      distanceKm: double.tryParse(data['distanceKm']?.toString() ?? '') ?? 0,
    );
  }
}

class StoreExternalDeliveryRetryIntent {
  final String requestId;
  final Map<String, dynamic> payload;
  final bool diagnosedAbsent;

  StoreExternalDeliveryRetryIntent({
    required this.requestId,
    required Map<String, dynamic> payload,
    this.diagnosedAbsent = false,
  }) : payload = Map<String, dynamic>.unmodifiable(payload);

  factory StoreExternalDeliveryRetryIntent.fromLocal(
    Map<String, dynamic> data,
  ) {
    final payload = storeExternalObject(data['payload']);
    final storedSignature = data['payloadSignature']?.toString() ?? '';
    if (storedSignature.isNotEmpty &&
        storedSignature != storeExternalPayloadSignature(payload)) {
      throw const FormatException('Store external retry payload mismatch.');
    }
    return StoreExternalDeliveryRetryIntent(
      requestId: data['requestId']?.toString().trim() ?? '',
      payload: payload,
      diagnosedAbsent: data['diagnosedAbsent'] == true,
    );
  }

  Map<String, Object?> toLocal() => <String, Object?>{
    'requestId': requestId,
    'payload': payload,
    'payloadSignature': storeExternalPayloadSignature(payload),
    'diagnosedAbsent': diagnosedAbsent,
  };

  bool matchesPayload(Map<String, dynamic> candidate) =>
      storeExternalPayloadSignature(payload) ==
      storeExternalPayloadSignature(candidate);

  StoreExternalDeliveryRetryIntent markDiagnosedAbsent() =>
      StoreExternalDeliveryRetryIntent(
        requestId: requestId,
        payload: payload,
        diagnosedAbsent: true,
      );
}

String legacyStoreStage(String status) {
  switch (status) {
    case 'accepted':
      return 'accepted';
    case 'preparing':
      return 'preparing';
    case 'onTheWay':
    case 'delivered':
      return 'handedToDriver';
    case 'cancelled':
      return 'cancelled';
    default:
      return 'awaitingAcceptance';
  }
}

class StoreProduct {
  final String id;
  final String name;
  final String category;
  final String categoryId;
  final int categoryDisplayOrder;
  final bool categoryActive;
  final int displayOrder;
  final String description;
  final String unit;
  final String imagePath;
  final String thumbImagePath;
  final int price;
  final bool available;
  final int stockQuantity;
  final bool archived;
  final int revision;
  final bool offer;
  final int offerPrice;
  final String offerFunding;
  final int offerStartsAtMs;
  final int offerEndsAtMs;
  final int offerRevision;

  const StoreProduct({
    required this.id,
    required this.name,
    required this.category,
    this.categoryId = '',
    this.categoryDisplayOrder = 0,
    this.categoryActive = true,
    this.displayOrder = 0,
    this.description = '',
    this.unit = 'قطعة',
    this.imagePath = '',
    this.thumbImagePath = '',
    required this.price,
    required this.available,
    this.stockQuantity = -1,
    this.archived = false,
    this.revision = 0,
    this.offer = false,
    this.offerPrice = 0,
    this.offerFunding = '',
    this.offerStartsAtMs = 0,
    this.offerEndsAtMs = 0,
    this.offerRevision = 0,
  });

  factory StoreProduct.fromFirebase(String id, Map<String, dynamic> data) {
    final stockQuantity = firebaseIntValue(
      data['stockQuantity'] ?? data['stock'] ?? data['quantityAvailable'],
      -1,
    );
    final category = data['category']?.toString().trim();
    final safeCategory = category?.isNotEmpty == true ? category! : 'عام';
    final archived = data['archived'] == true;
    final categoryActive = data['categoryActive'] != false;
    return StoreProduct(
      id: id,
      name: data['name']?.toString() ?? id,
      category: safeCategory,
      categoryId: data['categoryId']?.toString().trim().isNotEmpty == true
          ? data['categoryId'].toString().trim()
          : safeCategory,
      categoryDisplayOrder: firebaseIntValue(data['categoryDisplayOrder']),
      categoryActive: categoryActive,
      displayOrder: firebaseIntValue(data['displayOrder']),
      description: data['description']?.toString().trim() ?? '',
      unit: data['unit']?.toString().trim().isNotEmpty == true
          ? data['unit'].toString().trim()
          : 'قطعة',
      imagePath: data['imagePath']?.toString().trim() ?? '',
      thumbImagePath: data['thumbImagePath']?.toString().trim() ?? '',
      price: int.tryParse(data['price']?.toString() ?? '0') ?? 0,
      available:
          data['available'] != false &&
          stockQuantity != 0 &&
          !archived &&
          categoryActive,
      stockQuantity: stockQuantity,
      archived: archived,
      revision: firebaseIntValue(data['revision']),
      offer: data.containsKey('offer')
          ? data['offer'] == true
          : data['onOffer'] == true,
      offerPrice: firebaseIntValue(data['offerPrice']),
      offerFunding: data['offerFunding']?.toString().trim() ?? '',
      offerStartsAtMs: firebaseIntValue(data['offerStartsAtMs']),
      offerEndsAtMs: firebaseIntValue(data['offerEndsAtMs']),
      offerRevision: firebaseIntValue(data['offerRevision']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'categoryId': categoryId,
    'categoryDisplayOrder': categoryDisplayOrder,
    'categoryActive': categoryActive,
    'displayOrder': displayOrder,
    'description': description,
    'unit': unit,
    'imagePath': imagePath,
    'thumbImagePath': thumbImagePath,
    'price': price,
    'available': available,
    'stockQuantity': stockQuantity,
    'archived': archived,
    'revision': revision,
    if (offer || offerRevision > 0) 'offer': offer,
    if (offerPrice > 0) 'offerPrice': offerPrice,
    if (offerFunding.isNotEmpty) 'offerFunding': offerFunding,
    if (offerStartsAtMs > 0) 'offerStartsAtMs': offerStartsAtMs,
    if (offerEndsAtMs > 0) 'offerEndsAtMs': offerEndsAtMs,
    if (offerRevision > 0) 'offerRevision': offerRevision,
  };

  bool get hasLimitedStock => stockQuantity >= 0;

  String get preferredThumbnailPath {
    final thumbnail = thumbImagePath.trim();
    return thumbnail.isNotEmpty ? thumbnail : imagePath.trim();
  }

  bool get canManageAvailability => !archived && categoryActive;

  bool get hasCompleteMenuMedia =>
      imagePath.trim().isNotEmpty && thumbImagePath.trim().isNotEmpty;

  String get stockText {
    if (stockQuantity < 0) return 'مخزون غير محدد';
    if (stockQuantity == 0) return 'نفد من المخزون';
    return 'المخزون: $stockQuantity';
  }

  bool get offerIsActiveNow {
    if (!offer || offerPrice <= 0 || offerPrice >= price) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (offerStartsAtMs > 0 && offerStartsAtMs > now) return false;
    if (offerEndsAtMs > 0 && offerEndsAtMs <= now) return false;
    return true;
  }
}

int compareStoreMenuProducts(StoreProduct left, StoreProduct right) {
  var compared = left.categoryDisplayOrder.compareTo(
    right.categoryDisplayOrder,
  );
  if (compared != 0) return compared;
  compared = left.category.compareTo(right.category);
  if (compared != 0) return compared;
  compared = left.categoryId.compareTo(right.categoryId);
  if (compared != 0) return compared;
  compared = left.displayOrder.compareTo(right.displayOrder);
  if (compared != 0) return compared;
  compared = left.name.compareTo(right.name);
  if (compared != 0) return compared;
  return left.id.compareTo(right.id);
}

const defaultProducts = <StoreProduct>[
  StoreProduct(
    id: 'p_001',
    name: 'طماطة',
    category: 'خضار',
    price: 1000,
    available: true,
  ),
  StoreProduct(
    id: 'p_002',
    name: 'بطاطا',
    category: 'خضار',
    price: 750,
    available: true,
  ),
  StoreProduct(
    id: 'p_003',
    name: 'خيار',
    category: 'خضار',
    price: 900,
    available: true,
  ),
  StoreProduct(
    id: 'p_004',
    name: 'رز عنبر',
    category: 'مواد غذائية',
    price: 28000,
    available: true,
  ),
  StoreProduct(
    id: 'p_005',
    name: 'زيت طبخ',
    category: 'مواد غذائية',
    price: 4500,
    available: true,
  ),
  StoreProduct(
    id: 'p_006',
    name: 'سكر',
    category: 'مواد غذائية',
    price: 1500,
    available: true,
  ),
  StoreProduct(
    id: 'p_007',
    name: 'دجاج',
    category: 'لحوم',
    price: 5000,
    available: true,
  ),
  StoreProduct(
    id: 'p_008',
    name: 'لحم غنم',
    category: 'لحوم',
    price: 16000,
    available: true,
  ),
  StoreProduct(
    id: 'p_009',
    name: 'بيبسي',
    category: 'مشروبات',
    price: 12000,
    available: true,
  ),
  StoreProduct(
    id: 'p_010',
    name: 'ماء',
    category: 'مشروبات',
    price: 3000,
    available: true,
  ),
];
