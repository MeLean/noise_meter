import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:itido_noise_meter/mixins/app_closer.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:itido_noise_meter/mixins/noise_allerter.dart';
import 'package:itido_noise_meter/mixins/noise_listener.dart';
import 'dart:isolate';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoiseMeterApp());
}

class MyTaskHandler extends TaskHandler with NoiseListener, NoiseAllerter {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    initListener((noiseReading) {
      int intDB = _extractMeanDecibelInt(noiseReading);
      _updateForgroundTask(intDB);
      checkShouldAllert(intDB);
      sendPort?.send(noiseReading);
    });

    startNoiseListening();
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // You can use the clearAllData function to clear all the stored data.
    stopAlerting();
    stopNoiseListening();
    await FlutterForegroundTask.clearAllData();
  }

  @override
  void onButtonPressed(String id) {
    // Called when the notification button on the Android platform is pressed.
    debugPrint('onButtonPressed >> $id');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}

class NoiseMeterApp extends StatelessWidget {
  const NoiseMeterApp({super.key});

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
      initialRoute: '/',
      routes: {'/': (context) => const HomePage(title: 'ITIDO Noise Meter')},
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _NoiseMeterHomePageState();
}

class _NoiseMeterHomePageState extends State<HomePage>
    with NoiseListener, NoiseAllerter, AppCloser {
  ReceivePort? _receivePort;
  String _noiseLevel = "";

  @override
  void initState() {
    super.initState();
    initListener(_onNoiseData);
    startNoiseListening();

    _initForegroundTask();
    _startForegroundTask();
    _ambiguate(WidgetsBinding.instance)?.addPostFrameCallback((_) async {
      // You can get the previous ReceivePort without restarting the service.
      if (await FlutterForegroundTask.isRunningService) {
        final newReceivePort = await FlutterForegroundTask.receivePort;
        _registerReceivePort(newReceivePort);
      }
    });
  }

  @override
  void dispose() {
    stopNoiseListening();
    stopAlerting();
    _closeReceivePort();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
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
                Expanded(
                  child: Align(
                    alignment: FractionalOffset.bottomCenter,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton(
                            onPressed: () => {_minimizeApp()},
                            child: const Text("Minimize")),
                        ElevatedButton(
                            onPressed: () => {_teminateApp()},
                            child: const Text("Terminate")),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onNoiseData(NoiseReading noiseReading) {
    var intDB = _extractMeanDecibelInt(noiseReading);
    setState(() {
      _noiseLevel = '$intDB';
      _updateForgroundTaskAndCheck(intDB);
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_channel_id',
        channelName: 'Foreground Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
            resType: ResourceType.mipmap,
            resPrefix: ResourcePrefix.ic,
            name: 'launcher'),
        // buttons: [
        //   const NotificationButton(id: 'sendButton', text: 'Send'),
        //   const NotificationButton(id: 'testButton', text: 'Test'),
        // ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> _startForegroundTask() async {
    if (!await FlutterForegroundTask.canDrawOverlays) {
      final isGranted =
          await FlutterForegroundTask.openSystemAlertWindowSettings();
      if (!isGranted) {
        debugPrint('SYSTEM_ALERT_WINDOW permission denied!');
        return false;
      }
    }

    // You can save data using the saveData function.
    //await FlutterForegroundTask.saveData(key: 'customData', value: 'hello');

    bool reqResult;
    if (await FlutterForegroundTask.isRunningService) {
      reqResult = await FlutterForegroundTask.restartService();
    } else {
      reqResult = await FlutterForegroundTask.startService(
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        callback: startCallback,
      );
    }

    ReceivePort? receivePort;
    if (reqResult) {
      receivePort = await FlutterForegroundTask.receivePort;
    }

    return _registerReceivePort(receivePort);
  }

  Future<bool> _updateForgroundTaskAndCheck(int intDB) {
    checkShouldAllert(intDB);
    return _updateForgroundTask(intDB);
  }

  Future<bool> _stopForegroundTask() async {
    return await FlutterForegroundTask.stopService();
  }

  bool _registerReceivePort(ReceivePort? receivePort) {
    _closeReceivePort();

    if (receivePort != null) {
      _receivePort = receivePort;
      _receivePort?.listen((message) {
        debugPrint('message: $message');
        if (message is int) {
          debugPrint('eventCount: $message');
        } else if (message is String) {
          if (message == 'onNotificationPressed') {
            Navigator.of(context).pushNamed('/');
          }
        } else if (message is DateTime) {
          debugPrint('timestamp: ${message.toString()}');
        }
      });

      return true;
    }

    return false;
  }

  void _closeReceivePort() {
    _receivePort?.close();
    _receivePort = null;
  }

  T? _ambiguate<T>(T? value) => value;

  void _teminateApp() {
    _stopForegroundTask();
    closeApp();
  }

  void _minimizeApp() async {
    if (!await FlutterForegroundTask.isRunningService) {
      _initForegroundTask();
      _startForegroundTask();
    }

    FlutterForegroundTask.minimizeApp();
  }
}

Future<bool> _updateForgroundTask(int intDB) {
  return FlutterForegroundTask.updateService(
    notificationTitle: 'Itido Noise listener',
    notificationText: 'noise: $intDB',
  );
}

int _extractMeanDecibelInt(NoiseReading noiseReading) {
  var data = noiseReading.meanDecibel;
  var intDB = data.isInfinite ? 0 : data.toInt();
  return intDB;
}
