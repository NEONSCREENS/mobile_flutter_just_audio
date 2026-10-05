import 'dart:async';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Stands in for the audio_service plugin and keeps the callbacks, so a test
/// can deliver a command the way the media session does.
class _FakeAudioService extends AudioServicePlatform {
  AudioHandlerCallbacks? callbacks;

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async {}

  @override
  Future<void> setQueue(SetQueueRequest request) async {}

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {}

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    this.callbacks = callbacks;
  }
}

class _FakeNativePlayer extends AudioPlayerPlatform {
  _FakeNativePlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;
}

class _FakeJustAudio extends JustAudioPlatform {
  final disposed = <String>[];

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      _FakeNativePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    disposed.add(request.id);
    return DisposePlayerResponse();
  }
}

/// The system UI sends a stop to the media session a moment after a source
/// error. It used to release the native player the app had just prepared
/// again, with no error, and the app stayed silent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioService audioService;
  late _FakeJustAudio native;

  setUpAll(() async {
    audioService = _FakeAudioService();
    native = _FakeJustAudio();
    AudioServicePlatform.instance = audioService;
    JustAudioPlatform.instance = native;

    // audio_service builds its artwork cache on init, which reaches for
    // path_provider. Nothing here loads artwork, so that failure is dropped.
    await runZonedGuarded(JustAudioBackground.init, (_, __) {});
  });

  setUp(() => native.disposed.clear());

  test('a stop from the media session leaves the native player alone',
      () async {
    await JustAudioPlatform.instance.init(InitRequest(id: 'player-1'));
    final stops = <void>[];
    final subscription = JustAudioBackground.mediaSessionStops.listen(
      (_) => stops.add(null),
    );

    await audioService.callbacks!.stop(const StopRequest());
    await Future<void>.delayed(Duration.zero);

    expect(native.disposed, isEmpty);
    expect(stops, hasLength(1), reason: 'the app is told and decides');

    await subscription.cancel();
    await JustAudioPlatform.instance
        .disposePlayer(DisposePlayerRequest(id: 'player-1'));
  });

  test('disposing the player still releases the native one', () async {
    await JustAudioPlatform.instance.init(InitRequest(id: 'player-2'));

    await JustAudioPlatform.instance
        .disposePlayer(DisposePlayerRequest(id: 'player-2'));

    expect(native.disposed, ['player-2']);
  });
}
