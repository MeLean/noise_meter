import 'dart:async';

import 'package:noise_meter/noise_meter.dart';

mixin NoiseListener {
  late StreamSubscription<NoiseReading> _noiseSubscription;
  late final NoiseMeter _noiseMeter;
  late void Function(NoiseReading noiseReading) _onNoiseData;

  void initListener(void Function(NoiseReading noiseReading) onNoiseData) {
    _onNoiseData = onNoiseData;
    _noiseMeter = NoiseMeter((e) => {throw e});
  }

  void startNoiseListening() {
    _noiseSubscription = _noiseMeter.noiseStream.listen(_onNoiseData);
  }

  void stopNoiseListening() async {
    _noiseSubscription.cancel();
  }
}
