import 'package:flutter/material.dart';
import 'package:itido_noise_meter/mixins/app_closer.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:itido_noise_meter/mixins/noise_allerter.dart';
import 'package:itido_noise_meter/mixins/noise_listener.dart';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() => runApp(const NoiseMeterApp());

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler with NoiseListener {
  SendPort? _sendPort;
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;

    // // You can use the getData function to get the stored data.
    // final customData =
    //     await FlutterForegroundTask.getData<String>(key: 'customData');
    // debugPrint('customData: $customData');
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Itido Noise meter',
      notificationText: 'eventCount: $_eventCount',
    );

    // Send data to the main isolate.
    sendPort?.send(_eventCount);

    _eventCount++;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // You can use the clearAllData function to clear all the stored data.
    await FlutterForegroundTask.clearAllData();
  }

  @override
  void onButtonPressed(String id) {
    // Called when the notification button on the Android platform is pressed.
    debugPrint('onButtonPressed >> $id');
  }

  @override
  void onNotificationPressed() {
    // Called when the notification itself on the Android platform is pressed.
    //
    // "android.permission.SYSTEM_ALERT_WINDOW" permission must be granted for
    // this function to be called.

    // Note that the app will only route to "/resume-route" when it is exited so
    // it will usually be necessary to send a message through the send port to
    // signal it to restore state when the app is already started.
    FlutterForegroundTask.launchApp("/resume-route");
    _sendPort?.send('onNotificationPressed');
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
                    child: ElevatedButton(
                      onPressed: () async => {
                        if (await FlutterForegroundTask.isRunningService)
                          {_stopForegroundTask()}
                        else
                          {_startServiceAndCloseApp()}
                      },
                      child: FutureBuilder(
                          future: _getServiceText(),
                          builder: (
                            BuildContext context,
                            AsyncSnapshot<String> text,
                          ) {
                            return Text(text.data ?? "");
                          }),
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
    var data = noiseReading.meanDecibel;
    var intDB = data.isInfinite ? 0 : data.toInt();
    setState(() {
      _noiseLevel = '$intDB';
      checkShouldAllert(intDB);
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
          name: 'launcher',
          backgroundColor: Colors.orange,
        ),
        buttons: [
          const NotificationButton(id: 'sendButton', text: 'Send'),
          const NotificationButton(id: 'testButton', text: 'Test'),
        ],
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
    // "android.permission.SYSTEM_ALERT_WINDOW" permission must be granted for
    // onNotificationPressed function to be called.
    //
    // When the notification is pressed while permission is denied,
    // the onNotificationPressed function is not called and the app opens.
    //
    // If you do not use the onNotificationPressed or launchApp function,
    // you do not need to write this code.
    if (!await FlutterForegroundTask.canDrawOverlays) {
      final isGranted =
          await FlutterForegroundTask.openSystemAlertWindowSettings();
      if (!isGranted) {
        debugPrint('SYSTEM_ALERT_WINDOW permission denied!');
        return false;
      }
    }

    // You can save data using the saveData function.
    await FlutterForegroundTask.saveData(key: 'customData', value: 'hello');

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

  Future<bool> _stopForegroundTask() async {
    return await FlutterForegroundTask.stopService();
  }

  bool _registerReceivePort(ReceivePort? receivePort) {
    _closeReceivePort();

    if (receivePort != null) {
      _receivePort = receivePort;
      _receivePort?.listen((message) {
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

  Future<String> _getServiceText() async {
    return await FlutterForegroundTask.isRunningService
        ? 'Stop service'
        : 'Start service';
  }

  void _startServiceAndCloseApp() {
    _startForegroundTask();
    closeApp();
  }
}
