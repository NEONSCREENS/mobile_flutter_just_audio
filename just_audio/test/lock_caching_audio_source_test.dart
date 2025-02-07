import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import 'test_utils/fake_http.dart';

/// Helper function to create a temporary cache file in the [tempDir].
File buildCache(String fileName, Directory tempDir) {
  final cacheFilePath = p.join(tempDir.path, fileName);
  return File(cacheFilePath);
}

void mockHttpClient({
  List<int> responseData = const [],
  Map<int, Object> error = const {},
}) {
  final httpClient = FakeHttpClient(responseData: responseData, error: error);
  HttpOverrides.global = FakeHttpOverrides(httpClient);
}

void main() {
  late Directory cacheDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('lock_caching_test');

    // ignore: avoid_print
    print('Created cache dir: ${cacheDir.path}');
  });

  tearDown(() async {
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);

      // ignore: avoid_print
      print('Deleted cache dir: ${cacheDir.path}');
    }
  });

  group('LockCachingAudioSource - Good and edge cases', () {
    test('Already having a cached file just return it', () async {
      final responseData = List<int>.generate(1024, (i) => i % 256);
      mockHttpClient(responseData: responseData);
      final cacheFile = buildCache('test.mp3', cacheDir);
      await cacheFile.writeAsString("any content");

      final source = LockCachingAudioSource(
        Uri.parse('https://any.com/test.mp3'),
        cacheFile: cacheFile,
      );

      final response = await source.request();

      expect(
        response,
        isA<StreamAudioResponse>()
            .having((r) => r.contentLength, 'sourceLength', equals(11)),
      );
      expect(await cacheFile.exists(), isTrue);
    });

    test('Byte-range request returns correct content length and offset',
        () async {
      final responseData = List<int>.generate(1024, (i) => i % 256);
      mockHttpClient(responseData: responseData);

      final cacheFile = buildCache('range_test.mp3', cacheDir);
      final source = LockCachingAudioSource(
        Uri.parse('https://any.com/range_test.mp3'),
        cacheFile: cacheFile,
      );

      final response = await source.request(100, 300);
      expect(response.contentLength, equals(200));

      final collected = <int>[];
      await response.stream.forEach(collected.addAll);
      expect(
        collected,
        isA<List<int>>()
            .having((l) => l, 'length', hasLength(200))
            .having((l) => l.first, 'first', equals(responseData[100])),
      );
    });

    group('retry on error', (){
      test('Getting a timeout error retries to fetch the complete content', () async {
        final responseData = List<int>.generate(1024, (i) => i % 256);
        mockHttpClient(
          responseData: responseData,
          error: {
            0: const SocketException('any'),
          },
        );

        final cacheFile = buildCache('timeout_test.mp3', cacheDir);
        final source = LockCachingAudioSource(
          Uri.parse('https://any.com/timeout_test.mp3'),
          cacheFile: cacheFile,
          retryTimes: 1,
          retryDelayMillis: 0,
        );

        final response = await source.request();

        final collected = <int>[];
        await response.stream.forEach(collected.addAll);
        expect(collected.length, equals(responseData.length));

        expect(await cacheFile.length(), equals(responseData.length));
      });

      test('If it gets a timeout after the retry was done fail', () async {
        final responseData = List<int>.generate(1024, (i) => i % 256);
        mockHttpClient(
          responseData: responseData,
          error: {
            0: const SocketException('1'),
            1: const SocketException('2'),
          },
        );

        final cacheFile = buildCache('timeout_test.mp3', cacheDir);
        final source = LockCachingAudioSource(
          Uri.parse('https://any.com/timeout_test.mp3'),
          cacheFile: cacheFile,
          retryTimes: 1,
          retryDelayMillis: 0,
        );

        try {
          await source.request();
          fail('Should have thrown the exception!');
        } catch (e) {
          expect(e, isA<SocketException>());
          rethrow; // Let the test framework handle the error
        }
      });
    });

    test('Request returns data from partial file during download', () async {
      final responseData = List<int>.generate(1024, (i) => i % 256);
      mockHttpClient(responseData: responseData);

      final cacheFile = buildCache('partial.mp3', cacheDir);
      final source = LockCachingAudioSource(
        Uri.parse('https://any.com/partial.mp3'),
        cacheFile: cacheFile,
      );

      final downloadFuture = source.request();

      final middleLength = responseData.length / 2;
      final rangeResponse = await source.request(0, middleLength.toInt());
      final collected = <int>[];
      await rangeResponse.stream.forEach(collected.addAll);
      expect(collected.length, equals(middleLength));

      await downloadFuture;
      expect(await cacheFile.length(), equals(responseData.length));
    });
  });
}
