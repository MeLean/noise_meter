import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ITIDO Noise Meter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF002554),
          secondary: const Color.fromARGB(255, 138, 71, 114),
          brightness: Brightness.light,
        ),
      ),
      home: const MyHomePage(title: 'ITIDO Noise Meter'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _NoiseMeterHomePageState();
}

class _NoiseMeterHomePageState extends State<MyHomePage> {
  final int _laudNoiseDB = 81;
  final int _mediumNoiseDB = 75;
  final int _lowNoiseDB = 68;
  bool _isRecording = false;
  String _noiseLevel = "";
  late StreamSubscription<NoiseReading> _noiseSubscription;
  late final NoiseMeter _noiseMeter;
  late AssetsAudioPlayer _audio;

  @override
  void initState() {
    super.initState();
    _noiseMeter = NoiseMeter(_onNoiseInitError);
    _startNoiseListening();

    _audio = AssetsAudioPlayer.newPlayer();
  }

  @override
  void dispose() {
    super.dispose();
    _stopNoiseListening();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Noise value:',
            ),
            Text(
              _noiseLevel,
              style: Theme.of(context).textTheme.headline4,
            ),
            TextButton(
              onPressed: () => {},
              child: const Text(
                'start service',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startNoiseListening() async {
    try {
      _noiseSubscription = _noiseMeter.noiseStream.listen(_onNoiseData);
    } catch (exception) {
      debugPrint(exception.toString());
    }
  }

  void _onNoiseData(NoiseReading noiseReading) {
    debugPrint(
        "onNoiseData: ${noiseReading.meanDecibel} is playing: ${_audio.isPlaying.value}");
    if (!_audio.isPlaying.value) {
      var data = noiseReading.meanDecibel;
      var intDB = data.isInfinite ? 0 : data.toInt();

      setState(() {
        if (!_isRecording) {
          _isRecording = true;
        }

        _noiseLevel = '$intDB';

        _checkShouldAllert(intDB);
      });
    }
  }

  void _stopNoiseListening() async {
    try {
      _noiseSubscription.cancel();
      setState(() => _isRecording = false);
    } catch (e) {
      debugPrint('stopRecorder error: $e');
    }
  }

  void _onNoiseInitError(Object error) {
    setState(() {
      _isRecording = false;
      _noiseLevel = "intialization Error";
    });
  }

  void _checkShouldAllert(int intDB) {
    if (intDB > _laudNoiseDB) {
      _play('assets/mp3/to_much_noise.mp3', 1.0);
    } else if (intDB > _mediumNoiseDB) {
      _play('assets/mp3/it_is_noisy.mp3', 1.0);
    } else if (intDB > _lowNoiseDB) {
      _play('assets/mp3/it_is_noisy.mp3', 0.5);
    }
  }

  void _play(String source, double volume) {
    _audio.open(
      Audio(source),
      volume: volume,
    );
  }
}
