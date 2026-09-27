import 'package:audioplayers/audioplayers.dart';

/// Plays the pop. An interface so tests can swap in a silent fake.
abstract class PopSound {
  Future<void> play();
}

class AssetPopSound implements PopSound {
  final AudioPlayer _player = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);

  @override
  Future<void> play() async {
    // Restart from the top so rapid clicks each get their own pop.
    await _player.stop();
    await _player.play(AssetSource('pop.wav'));
  }
}
