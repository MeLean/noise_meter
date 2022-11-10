import 'dart:async';

import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:flutter/foundation.dart';

mixin NoiseAllerter {
  static const _laudNoiseDB = 81;
  static const _mediumNoiseDB = 75;
  static const _lowNoiseDB = 68;
  final List<int> _colectedDecibels = List.empty(growable: true);
  var _shouldCollect = false;
  Timer? _timer;
  final AssetsAudioPlayer _audio = AssetsAudioPlayer.newPlayer();

  void checkShouldAllert(int intDB) {
    //debugPrint("NOISE: $intDB, _shouldCollect: $_shouldCollect");

    if (_shouldCollect) {
      _colectedDecibels.add(intDB);
    } else if (_colectedDecibels.isNotEmpty) {
      _anonseNoising(_emptyColectedAndCalculatingAverage());
    } else if (intDB > _lowNoiseDB) {
      _shouldCollect = true;
      _timer = Timer(const Duration(milliseconds: 3000), () {
        _shouldCollect = false;
      });
    }
  }

  void stopAlerting() {
    _timer?.cancel();
    _audio.stop();
    _colectedDecibels.clear();
  }

  void _play(String source, double volume) {
    _audio.open(
      Audio(source),
      volume: volume,
    );
  }

  int _emptyColectedAndCalculatingAverage() {
    var result = (_colectedDecibels.fold(0, (prev, cur) => prev + cur)) /
        _colectedDecibels.length;

    _colectedDecibels.clear();

    return result.toInt();
  }

  void _anonseNoising(int intDB) {
    debugPrint("NOISE: $intDB collected");
    if (intDB > _laudNoiseDB) {
      _play('assets/mp3/to_much_noise.mp3', 1.0);
    } else if (intDB > _mediumNoiseDB) {
      _play('assets/mp3/it_is_noisy.mp3', 1.0);
    } else if (intDB > _lowNoiseDB) {
      _play('assets/mp3/it_is_noisy.mp3', 0.5);
    }
  }
}
