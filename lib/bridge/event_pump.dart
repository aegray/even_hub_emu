import 'dart:async';

import 'even_app_bridge.dart';

class EventPumpPolicy {
  EventPumpPolicy({
    this.sendDeviceStatusOnStart = true,
    this.sendPeriodicDeviceStatus = true,
    this.deviceStatusInterval = const Duration(seconds: 10),
    this.sendForegroundEvents = true,
  });

  final bool sendDeviceStatusOnStart;
  final bool sendPeriodicDeviceStatus;
  final Duration deviceStatusInterval;
  final bool sendForegroundEvents;

  Timer? _deviceStatusTimer;

  void start(EvenAppBridgeHost host) {
    stop();
    if (sendDeviceStatusOnStart) {
      host.pushDeviceStatusChanged();
    }
    if (sendPeriodicDeviceStatus) {
      _deviceStatusTimer = Timer.periodic(deviceStatusInterval, (_) {
        host.pushDeviceStatusChanged();
      });
    }
  }

  void stop() {
    _deviceStatusTimer?.cancel();
    _deviceStatusTimer = null;
  }
}
