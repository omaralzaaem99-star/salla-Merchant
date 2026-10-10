import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

bool sallaSessionReadCanRetry(Object error) =>
    error is TimeoutException ||
    (error is FirebaseException &&
        const {
          'network-request-failed',
          'network-error',
          'disconnected',
          'unavailable',
          'deadline-exceeded',
        }.contains(error.code.toLowerCase()));

/// Recover a verified session read, never a cached identity or a write.
/// A slow notice keeps the original read alive; only a definitive transport
/// failure or the hard deadline starts another read. Cancellation fences late
/// results from a previous account, retry, or disposed login screen.
Stream<T> sallaRecoveringSessionRead<T>(
  Future<T> Function() read, {
  Duration slowAfter = const Duration(seconds: 12),
  Duration hardTimeout = const Duration(seconds: 60),
  Duration retryBase = const Duration(seconds: 5),
}) =>
    Stream<T>.multi((out) {
      var closed = false;
      var generation = 0;
      var failures = 0;
      Timer? notice;
      Timer? retry;
      late void Function() start;
      start = () {
        final token = ++generation;
        notice?.cancel();
        notice = Timer(slowAfter, () {
          if (!closed && token == generation) {
            out.addError(TimeoutException(
              'التحقق من الحساب يستغرق وقتاً أطول. جارٍ استكماله تلقائياً.',
              slowAfter,
            ));
          }
        });
        Future.sync(read).timeout(hardTimeout).then((value) {
          if (closed || token != generation) return;
          notice?.cancel();
          out.add(value);
          out.close();
        }, onError: (Object error, StackTrace stack) {
          if (closed || token != generation) return;
          notice?.cancel();
          out.addError(error, stack);
          if (!sallaSessionReadCanRetry(error)) return;
          final multiplier = 1 << failures.clamp(0, 3);
          failures++;
          retry = Timer(retryBase * multiplier, start);
        });
      };
      out.onCancel = () {
        closed = true;
        generation++;
        notice?.cancel();
        retry?.cancel();
      };
      start();
    });
