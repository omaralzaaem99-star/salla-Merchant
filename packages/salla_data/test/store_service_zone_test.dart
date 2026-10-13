import 'package:salla_data/salla_data.dart';
import 'package:test/test.dart';

void main() {
  SallaStoreServiceZone circle({
    String id = 'zone-a',
    bool active = true,
    String mode = 'normal',
    int compactRadiusKm = 8,
    double? lat = 33.3152,
    double? lng = 44.3661,
    double? radiusKm = 5,
  }) {
    return SallaStoreServiceZone(
      id: id,
      name: id,
      active: active,
      mode: mode,
      compactRadiusKm: compactRadiusKm,
      order: 0,
      provinceId: 'baghdad',
      provinceName: 'بغداد',
      branchId: 'baghdad-west',
      branchName: 'الكرخ',
      coverageType: 'circle',
      centerLat: lat,
      centerLng: lng,
      coverageRadiusKm: radiusKm,
    );
  }

  test('circle accepts inside and exact boundary and rejects outside', () {
    const centerLat = 33.3152;
    const centerLng = 44.3661;
    const boundaryLat = 33.3242;
    final boundaryKm = sallaGeoDistanceKm(
      centerLat,
      centerLng,
      boundaryLat,
      centerLng,
    );
    final zone = circle(radiusKm: boundaryKm);

    expect(zone.contains(centerLat, centerLng), isTrue);
    expect(zone.contains(boundaryLat, centerLng), isTrue);
    expect(zone.contains(33.35, centerLng), isFalse);
  });

  test('polygon accepts inside and boundary and rejects a concave gap', () {
    final zone = SallaStoreServiceZone.fromFirebase('polygon', {
      'name': 'مضلع',
      'active': true,
      'provinceId': 'baghdad',
      'branchId': 'karkh',
      'coverageType': 'polygon',
      'polygonPoints': {
        'p0000': {'lat': 33.3, 'lng': 44.4},
        'p0001': {'lat': 33.3, 'lng': 44.5},
        'p0002': {'lat': 33.35, 'lng': 44.5},
        'p0003': {'lat': 33.35, 'lng': 44.45},
        'p0004': {'lat': 33.4, 'lng': 44.45},
        'p0005': {'lat': 33.4, 'lng': 44.4},
      },
      'coverageBounds': {
        'minLat': 33.3,
        'maxLat': 33.4,
        'minLng': 44.4,
        'maxLng': 44.5,
      },
      'coverageHash': 'hash',
      'coverageRevision': 2,
    });

    expect(zone.hasValidPolygon, isTrue);
    expect(zone.hasValidCoverage, isTrue);
    expect(zone.polygonPoints, hasLength(6));
    expect(zone.coverageRevision, 2);
    expect(zone.contains(33.32, 44.48), isTrue);
    expect(zone.contains(33.35, 44.47), isTrue);
    expect(zone.contains(33.38, 44.48), isFalse);
    expect(zone.contains(33.2, 44.45), isFalse);
  });

  test('invalid or self-intersecting polygon fails closed', () {
    final zone = SallaStoreServiceZone.fromFirebase('invalid', {
      'active': true,
      'coverageType': 'polygon',
      'polygonPoints': [
        {'lat': 33.2, 'lng': 44.4},
        {'lat': 33.4, 'lng': 44.6},
        {'lat': 33.2, 'lng': 44.6},
        {'lat': 33.4, 'lng': 44.4},
      ],
    });

    expect(zone.hasValidPolygon, isFalse);
    expect(zone.contains(33.3, 44.5), isFalse);
  });

  test('live polygon validation reports the conflicting segment indexes', () {
    final validation = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.30, 44.30),
      SallaGeoPoint(33.34, 44.34),
      SallaGeoPoint(33.34, 44.30),
      SallaGeoPoint(33.30, 44.34),
      SallaGeoPoint(33.32, 44.35),
    ]);

    expect(validation.isValid, isFalse);
    expect(
      validation.issue,
      SallaPolygonGeometryIssue.selfIntersection,
    );
    expect(validation.conflictingSegmentIndexes, [0, 2]);
    expect(validation.points, hasLength(5));

    final symmetricBowTie = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.30, 44.30),
      SallaGeoPoint(33.40, 44.40),
      SallaGeoPoint(33.30, 44.40),
      SallaGeoPoint(33.40, 44.30),
    ]);
    expect(
      symmetricBowTie.issue,
      SallaPolygonGeometryIssue.selfIntersection,
    );
    expect(symmetricBowTie.conflictingSegmentIndexes, [0, 2]);
  });

  test('live polygon validation accepts a valid concave polygon', () {
    final validation = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.30, 44.40),
      SallaGeoPoint(33.30, 44.50),
      SallaGeoPoint(33.35, 44.50),
      SallaGeoPoint(33.35, 44.45),
      SallaGeoPoint(33.40, 44.45),
      SallaGeoPoint(33.40, 44.40),
    ]);

    expect(validation.isValid, isTrue);
    expect(validation.issue, SallaPolygonGeometryIssue.none);
    expect(validation.conflictingSegmentIndexes, isEmpty);
    expect(validation.points, hasLength(6));
  });

  test('live polygon validation cleans adjacent and closing duplicates', () {
    final validation = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.3000001, 44.3000001),
      SallaGeoPoint(33.3000004, 44.3000004),
      SallaGeoPoint(33.3000001, 44.4),
      SallaGeoPoint(33.4, 44.4),
      SallaGeoPoint(33.3000002, 44.3000002),
    ]);

    expect(validation.isValid, isTrue);
    expect(validation.points, hasLength(3));
    expect(validation.points.first.lat, 33.3);
    expect(validation.points.first.lng, 44.3);

    final duplicate = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.30, 44.30),
      SallaGeoPoint(33.30, 44.40),
      SallaGeoPoint(33.30, 44.30),
      SallaGeoPoint(33.40, 44.30),
    ]);
    expect(duplicate.isValid, isFalse);
    expect(duplicate.issue, SallaPolygonGeometryIssue.duplicatePoint);
  });

  test('live polygon validation rejects zero area and more than 200 points',
      () {
    final zeroArea = sallaValidatePolygonGeometry(const [
      SallaGeoPoint(33.30, 44.30),
      SallaGeoPoint(33.31, 44.31),
      SallaGeoPoint(33.32, 44.32),
    ]);
    expect(zeroArea.isValid, isFalse);
    expect(zeroArea.issue, SallaPolygonGeometryIssue.zeroArea);

    final tooMany = sallaValidatePolygonGeometry(
      List.generate(
        201,
        (index) => SallaGeoPoint(
          33.0 + index * 0.00001,
          44.0 + index * 0.00001,
        ),
      ),
    );
    expect(tooMany.isValid, isFalse);
    expect(tooMany.issue, SallaPolygonGeometryIssue.tooManyPoints);
    expect(tooMany.points, hasLength(201));
  });

  test('store may serve any one of several assigned active zones', () {
    final zones = [
      circle(id: 'west'),
      circle(id: 'east', lat: 33.33, lng: 44.45, radiusKm: 3),
    ];

    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'west': true, 'east': true},
        zones: zones,
        customerLat: 33.33,
        customerLng: 44.45,
      ),
      isTrue,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'west': true, 'east': true},
        zones: zones,
        customerLat: 34,
        customerLng: 45,
      ),
      isFalse,
    );
  });

  test('matching zone prefers non-paused then distance then id', () {
    final overlappingZones = [
      circle(
        id: 'paused-near',
        mode: 'paused',
        lat: 33.3152,
        lng: 44.3661,
        radiusKm: 5,
      ),
      circle(
        id: 'normal-farther',
        lat: 33.32,
        lng: 44.3661,
        radiusKm: 5,
      ),
    ];
    final selected = sallaMatchingAssignedCustomerZone(
      rawAssignedZoneIds: const {
        'paused-near': true,
        'normal-farther': true,
      },
      zones: overlappingZones,
      customerLat: 33.3152,
      customerLng: 44.3661,
    );

    expect(selected?.id, 'normal-farther');

    final tiedZones = [
      circle(id: 'zone-b'),
      circle(id: 'zone-a'),
    ];
    expect(
      sallaMatchingAssignedCustomerZone(
        rawAssignedZoneIds: const {'zone-a': true, 'zone-b': true},
        zones: tiedZones,
        customerLat: 33.3152,
        customerLng: 44.3661,
      )?.id,
      'zone-a',
    );
  });

  test('explicit assignment rejects paused-only matches and keeps compact', () {
    final pausedZone = circle(id: 'paused', mode: 'paused');
    expect(
      sallaMatchingAssignedCustomerZone(
        rawAssignedZoneIds: const {'paused': true},
        zones: [pausedZone],
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isNull,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'paused': true},
        zones: [pausedZone],
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isFalse,
    );

    final compactZone = circle(
      id: 'compact',
      mode: 'compact',
      compactRadiusKm: 3,
    );
    final selectedCompact = sallaMatchingAssignedCustomerZone(
      rawAssignedZoneIds: const {'compact': true},
      zones: [compactZone],
      customerLat: 33.3152,
      customerLng: 44.3661,
    );
    expect(selectedCompact?.mode, 'compact');
    expect(selectedCompact?.compactRadiusKm, 3);
  });

  test('explicit assignment fails closed without usable geometry or location',
      () {
    final unusableZones = [
      circle(id: 'inactive', active: false),
      circle(id: 'missing', lat: null),
    ];

    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'inactive': true},
        zones: unusableZones,
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isFalse,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'missing': true},
        zones: unusableZones,
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isFalse,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const {'inactive': true},
        zones: unusableZones,
        customerLat: null,
        customerLng: null,
      ),
      isFalse,
    );
  });

  test('only a missing legacy assignment stays visible; explicit empty fails',
      () {
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: null,
        zones: const [],
        customerLat: null,
        customerLng: null,
        requiredBranchId: '',
        requireStoreBranchBoundary: true,
      ),
      isTrue,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const <String, bool>{},
        zones: const [],
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isFalse,
    );
    expect(
      sallaStoreInsideAssignedCustomerZones(
        rawAssignedZoneIds: const <String>[],
        zones: const [],
        customerLat: 33.3152,
        customerLng: 44.3661,
      ),
      isFalse,
    );
  });

  test('independent store polygon narrows shared zones and fails closed', () {
    const polygon = {
      'p0000': {'lat': 33.30, 'lng': 44.36},
      'p0001': {'lat': 33.30, 'lng': 44.38},
      'p0002': {'lat': 33.32, 'lng': 44.38},
      'p0003': {'lat': 33.32, 'lng': 44.36},
    };

    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: null,
        customerLat: null,
        customerLng: null,
      ),
      isFalse,
    );
    expect(sallaStoreCustomerZonePolygonPoints(polygon), hasLength(4));
    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: polygon,
        customerLat: 33.31,
        customerLng: 44.37,
      ),
      isTrue,
    );
    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: polygon,
        customerLat: 33.30,
        customerLng: 44.37,
      ),
      isTrue,
    );
    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: polygon,
        customerLat: 33.34,
        customerLng: 44.37,
      ),
      isFalse,
    );
    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: const {
          'p0000': {'lat': 33.30, 'lng': 44.36},
          'p0001': {'lat': 33.32, 'lng': 44.38},
        },
        customerLat: 33.31,
        customerLng: 44.37,
      ),
      isFalse,
    );
  });

  test('generic polygon point check accepts edges and fails closed', () {
    const polygon = [
      {'lat': 32.8, 'lng': 43.8},
      {'lat': 32.8, 'lng': 45.0},
      {'lat': 33.8, 'lng': 45.0},
      {'lat': 33.8, 'lng': 43.8},
    ];
    expect(
      sallaPointInsidePolygon(
        rawPolygonPoints: polygon,
        lat: 33.3,
        lng: 44.3,
      ),
      isTrue,
    );
    expect(
      sallaPointInsidePolygon(
        rawPolygonPoints: polygon,
        lat: 32.8,
        lng: 44.3,
      ),
      isTrue,
    );
    expect(
      sallaPointInsidePolygon(
        rawPolygonPoints: polygon,
        lat: 34.0,
        lng: 44.3,
      ),
      isFalse,
    );
    expect(
      sallaPointInsidePolygon(
        rawPolygonPoints: const [],
        lat: 33.3,
        lng: 44.3,
      ),
      isFalse,
    );
  });

  test('firebase parser keeps branch metadata and deterministic order', () {
    final zones = sallaStoreServiceZonesFromFirebase({
      'zone-b': {
        'name': 'الرصافة',
        'active': true,
        'order': 2,
        'provinceId': 'baghdad',
        'branchId': 'east',
        'coverageType': 'circle',
        'centerLat': 33.33,
        'centerLng': 44.45,
        'coverageRadiusKm': 7,
      },
      'zone-a': {
        'name': 'الكرخ',
        'active': true,
        'mode': 'compact',
        'compactRadiusKm': 4,
        'order': 1,
        'provinceId': 'baghdad',
        'branchId': 'west',
        'coverageType': 'circle',
        'centerLat': 33.3152,
        'centerLng': 44.3661,
        'coverageRadiusKm': 8,
      },
    });

    expect(zones.map((zone) => zone.id), ['zone-a', 'zone-b']);
    expect(zones.first.branchId, 'west');
    expect(zones.first.hasValidCircle, isTrue);
    expect(zones.first.mode, 'compact');
    expect(zones.first.compactRadiusKm, 4);
  });

  test('firebase parser treats a missing active flag as inactive', () {
    final zones = sallaStoreServiceZonesFromFirebase({
      'not-yet-active': {
        'coverageType': 'circle',
        'centerLat': 33.3152,
        'centerLng': 44.3661,
        'coverageRadiusKm': 8,
      },
    });

    expect(zones.single.active, isFalse);
    expect(zones.single.contains(33.3152, 44.3661), isFalse);
  });

  test('explicit network mode rejects a zone in an inactive branch or province',
      () {
    final rawZones = {
      'west': {
        'active': true,
        'provinceId': 'baghdad',
        'branchId': 'karkh',
        'coverageType': 'circle',
        'centerLat': 33.3152,
        'centerLng': 44.3661,
        'coverageRadiusKm': 8,
      },
    };
    final zones = sallaStoreServiceZonesFromFirebase(
      rawZones,
      rawProvinces: const {
        'baghdad': {'active': true},
      },
      rawBranches: const {
        'karkh': {
          'active': false,
          'provinceId': 'baghdad',
          'boundaryType': 'polygon',
          'boundaryPoints': {
            'p0000': {'lat': 33.20, 'lng': 44.20},
            'p0001': {'lat': 33.20, 'lng': 44.50},
            'p0002': {'lat': 33.45, 'lng': 44.50},
            'p0003': {'lat': 33.45, 'lng': 44.20},
          },
        },
      },
      requireActiveNetwork: true,
    );

    expect(zones.single.active, isTrue);
    expect(zones.single.networkActive, isFalse);
    expect(zones.single.contains(33.3152, 44.3661), isFalse);

    final activeZones = sallaStoreServiceZonesFromFirebase(
      rawZones,
      rawProvinces: const {
        'baghdad': {'active': true},
      },
      rawBranches: const {
        'karkh': {
          'active': true,
          'provinceId': 'baghdad',
          'boundaryType': 'polygon',
          'boundaryPoints': {
            'p0000': {'lat': 33.20, 'lng': 44.20},
            'p0001': {'lat': 33.20, 'lng': 44.50},
            'p0002': {'lat': 33.45, 'lng': 44.50},
            'p0003': {'lat': 33.45, 'lng': 44.20},
          },
        },
      },
      requireActiveNetwork: true,
    );
    expect(activeZones.single.networkActive, isTrue);
    expect(activeZones.single.hasValidBranchBoundary, isTrue);
    expect(activeZones.single.contains(33.3152, 44.3661), isTrue);

    final missingBoundaryZones = sallaStoreServiceZonesFromFirebase(
      rawZones,
      rawProvinces: const {
        'baghdad': {'active': true},
      },
      rawBranches: const {
        'karkh': {'active': true, 'provinceId': 'baghdad'},
      },
      requireActiveNetwork: true,
    );
    expect(missingBoundaryZones.single.networkActive, isFalse);
    expect(missingBoundaryZones.single.contains(33.3152, 44.3661), isFalse);
  });

  test('active parser intersects a crossing circle with the branch polygon',
      () {
    final zones = sallaStoreServiceZonesFromFirebase(
      const {
        'crossing': {
          'active': true,
          'provinceId': 'baghdad',
          'branchId': 'karkh',
          'coverageType': 'circle',
          'centerLat': 33.30,
          'centerLng': 44.53,
          'coverageRadiusKm': 10,
        },
      },
      rawProvinces: const {
        'baghdad': {'active': true},
      },
      rawBranches: const {
        'karkh': {
          'active': true,
          'provinceId': 'baghdad',
          'boundaryType': 'polygon',
          'boundaryPoints': {
            'p0000': {'lat': 33.20, 'lng': 44.45},
            'p0001': {'lat': 33.20, 'lng': 44.55},
            'p0002': {'lat': 33.40, 'lng': 44.55},
            'p0003': {'lat': 33.40, 'lng': 44.45},
          },
        },
      },
      requireActiveNetwork: true,
    );
    final zone = zones.single;

    expect(zone.branchBoundaryPoints, hasLength(4));
    expect(zone.contains(33.30, 44.54), isTrue);
    expect(zone.contains(33.30, 44.56), isFalse);
  });

  test('explicit matching rejects store outside branch and branch mismatch',
      () {
    final zone = SallaStoreServiceZone.fromFirebase(
      'crossing',
      const {
        'active': true,
        'provinceId': 'baghdad',
        'branchId': 'karkh',
        'coverageType': 'circle',
        'centerLat': 33.30,
        'centerLng': 44.53,
        'coverageRadiusKm': 10,
      },
      branchBoundaryPoints: const [
        SallaGeoPoint(33.20, 44.45),
        SallaGeoPoint(33.20, 44.55),
        SallaGeoPoint(33.40, 44.55),
        SallaGeoPoint(33.40, 44.45),
      ],
    );

    SallaStoreServiceZone? match({
      String branchId = 'karkh',
      double? storeLat = 33.30,
      double? storeLng = 44.53,
    }) {
      return sallaMatchingAssignedCustomerZone(
        rawAssignedZoneIds: const {'crossing': true},
        zones: [zone],
        customerLat: 33.30,
        customerLng: 44.54,
        requiredBranchId: branchId,
        storeLat: storeLat,
        storeLng: storeLng,
        requireStoreBranchBoundary: true,
      );
    }

    expect(match(), same(zone));
    expect(match(storeLng: 44.56), isNull);
    expect(match(storeLat: null), isNull);
    expect(match(branchId: 'rusafa'), isNull);
  });

  test('store polygon remains an extra layer over zone and branch coverage',
      () {
    final zone = SallaStoreServiceZone.fromFirebase(
      'shared',
      const {
        'active': true,
        'provinceId': 'baghdad',
        'branchId': 'karkh',
        'coverageType': 'circle',
        'centerLat': 33.30,
        'centerLng': 44.53,
        'coverageRadiusKm': 10,
      },
      branchBoundaryPoints: const [
        SallaGeoPoint(33.20, 44.45),
        SallaGeoPoint(33.20, 44.55),
        SallaGeoPoint(33.40, 44.55),
        SallaGeoPoint(33.40, 44.45),
      ],
    );
    const storePolygon = {
      'p0000': {'lat': 33.28, 'lng': 44.50},
      'p0001': {'lat': 33.28, 'lng': 44.54},
      'p0002': {'lat': 33.32, 'lng': 44.54},
      'p0003': {'lat': 33.32, 'lng': 44.50},
    };

    bool visibleAt(double lng) {
      final assignedMatch = sallaMatchingAssignedCustomerZone(
        rawAssignedZoneIds: const {'shared': true},
        zones: [zone],
        customerLat: 33.30,
        customerLng: lng,
        requiredBranchId: 'karkh',
        storeLat: 33.30,
        storeLng: 44.53,
        requireStoreBranchBoundary: true,
      );
      return assignedMatch != null &&
          sallaPolygonContainsPolygon(
            rawContainerPoints: zone.branchBoundaryPoints,
            rawCandidatePoints: storePolygon,
          ) &&
          sallaStoreInsideCustomerZonePolygon(
            rawPolygonPoints: storePolygon,
            customerLat: 33.30,
            customerLng: lng,
          );
    }

    expect(visibleAt(44.53), isTrue);
    expect(visibleAt(44.545), isFalse);
    expect(visibleAt(44.56), isFalse);
  });

  test(
      'full store polygon outside branch fails even when store and customer points fit',
      () {
    const branchBoundary = [
      SallaGeoPoint(33.299, 44.399),
      SallaGeoPoint(33.299, 44.401),
      SallaGeoPoint(33.301, 44.401),
      SallaGeoPoint(33.301, 44.399),
    ];
    const oversizedStorePolygon = {
      'p0000': {'lat': 33.29, 'lng': 44.39},
      'p0001': {'lat': 33.29, 'lng': 44.41},
      'p0002': {'lat': 33.31, 'lng': 44.41},
      'p0003': {'lat': 33.31, 'lng': 44.39},
    };
    const containedStorePolygon = {
      'p0000': {'lat': 33.2992, 'lng': 44.3992},
      'p0001': {'lat': 33.2992, 'lng': 44.4008},
      'p0002': {'lat': 33.3008, 'lng': 44.4008},
      'p0003': {'lat': 33.3008, 'lng': 44.3992},
    };

    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: branchBoundary,
        customerLat: 33.3,
        customerLng: 44.4,
      ),
      isTrue,
    );
    expect(
      sallaStoreInsideCustomerZonePolygon(
        rawPolygonPoints: oversizedStorePolygon,
        customerLat: 33.3,
        customerLng: 44.4,
      ),
      isTrue,
    );
    expect(
      sallaPolygonContainsPolygon(
        rawContainerPoints: branchBoundary,
        rawCandidatePoints: oversizedStorePolygon,
      ),
      isFalse,
    );
    expect(
      sallaPolygonContainsPolygon(
        rawContainerPoints: branchBoundary,
        rawCandidatePoints: containedStorePolygon,
      ),
      isTrue,
    );
    expect(
      sallaPolygonContainsPolygon(
        rawContainerPoints: branchBoundary,
        rawCandidatePoints: branchBoundary,
      ),
      isTrue,
    );
  });
}
