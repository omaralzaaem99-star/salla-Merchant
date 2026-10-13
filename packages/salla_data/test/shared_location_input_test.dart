import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:salla_data/salla_data.dart';
import 'package:test/test.dart';

void expectPoint(SallaGeoPoint? point, double lat, double lng) {
  expect(point, isNotNull);
  expect(point!.lat, closeTo(lat, 0.000001));
  expect(point.lng, closeTo(lng, 0.000001));
}

void main() {
  group('shared location parsing', () {
    test('accepts geo, Google Maps, and plain coordinate forms', () {
      expectPoint(
        sallaParseSharedLocationText('geo:33.312500,44.361000?q=shop'),
        33.3125,
        44.361,
      );
      expectPoint(
        sallaParseSharedLocationText(
          'https://www.google.com/maps/@33.3201,44.3802,16z',
        ),
        33.3201,
        44.3802,
      );
      expectPoint(
        sallaParseSharedLocationText(
          'الموقع https://maps.google.com/?q=33.3102%2C44.4012',
        ),
        33.3102,
        44.4012,
      );
      expectPoint(
        sallaParseSharedLocationText('33.300001، 44.400002'),
        33.300001,
        44.400002,
      );
      expectPoint(
        sallaParseSharedLocationText(
          'google.navigation:q=33.3125,44.361&mode=d',
        ),
        33.3125,
        44.361,
      );
    });

    test('rejects unsafe hosts and invalid coordinate ranges', () {
      expect(
        sallaParseSharedLocationText(
          'https://example.com/maps/@33.3,44.4,16z',
        ),
        isNull,
      );
      expect(sallaParseSharedLocationText('geo:100,200'), isNull);
      expect(
        sallaParseSharedLocationText('google.navigation:q=100,200&mode=d'),
        isNull,
      );
      expect(
        sallaParseSharedLocationText(
          'google.navigation:q=شارع+الرشيد&mode=d',
        ),
        isNull,
      );
      expect(
          sallaParseSharedLocationText('https://maps.app.goo.gl/%ZZ'), isNull);
    });

    test('resolves only the Google goo.gl maps path', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        expect(request.url.host, 'goo.gl');
        expect(request.url.path, '/maps/abc123');
        return http.Response('', 302, headers: <String, String>{
          'location': 'https://www.google.com/maps/@33.3155,44.3655,17z',
        });
      });

      final point = await sallaResolveSharedLocationText(
        'https://goo.gl/maps/abc123',
        client: client,
      );
      expectPoint(point, 33.3155, 44.3655);
      expect(calls, 1);

      final rejected = await sallaResolveSharedLocationText(
        'https://goo.gl/not-maps/abc123',
        client: client,
      );
      expect(rejected, isNull);
      expect(calls, 1);
    });

    test('resolves a trusted Google short link without reading its body',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        expect(request.url.host, 'maps.app.goo.gl');
        return http.Response('', 302, headers: <String, String>{
          'location': 'https://www.google.com/maps/@33.3055,44.4055,17z',
        });
      });

      final point = await sallaResolveSharedLocationText(
        'https://maps.app.goo.gl/abc123',
        client: client,
      );

      expectPoint(point, 33.3055, 44.4055);
      expect(calls, 1);
    });

    test('does not follow a redirect outside the trusted host list', () async {
      final client = MockClient(
        (_) async => http.Response('', 302, headers: <String, String>{
          'location': 'https://attacker.example/@33.3,44.4',
        }),
      );

      final point = await sallaResolveSharedLocationText(
        'https://maps.app.goo.gl/unsafe',
        client: client,
      );

      expect(point, isNull);
    });

    test('bounds redirect loops and returns null', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        return http.Response('', 302, headers: <String, String>{
          'location': request.url.toString(),
        });
      });

      final point = await sallaResolveSharedLocationText(
        'https://maps.app.goo.gl/loop',
        client: client,
        maxRedirects: 2,
      );

      expect(point, isNull);
      expect(calls, 1);
    });
  });
}
