import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../glasses/glasses_model.dart';
import 'event_pump.dart';

class EvenAppMessage {
  EvenAppMessage({
    required this.type,
    required this.method,
    this.data,
    this.payload,
  });

  final String type;
  final String method;
  final dynamic data;
  final dynamic payload;

  factory EvenAppMessage.fromDynamic(dynamic raw) {
    if (raw is String) {
      return EvenAppMessage.fromDynamic(jsonDecode(raw));
    }
    if (raw is Map) {
      final map = raw.map((key, value) => MapEntry(key.toString(), value));
      return EvenAppMessage(
        type: map['type']?.toString() ?? '',
        method: map['method']?.toString() ?? '',
        data: map['data'],
        payload: map['payload'],
      );
    }
    return EvenAppMessage(type: '', method: '', data: null, payload: null);
  }
}

class EvenAppBridgeHost {
  EvenAppBridgeHost({
    required this.state,
    EventPumpPolicy? eventPump,
  }) : eventPump = eventPump ?? EventPumpPolicy();

  final GlassesState state;
  final EventPumpPolicy eventPump;

  final Map<String, String> _localStorage = {};
  final List<Map<String, dynamic>> _pendingMessages = [];

  InAppWebViewController? _webViewController;
  bool _webReady = false;

  void attachWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
  }

  void onWebReady() {
    _webReady = true;
    if (_pendingMessages.isNotEmpty) {
      for (final message in _pendingMessages) {
        _sendMessageToWeb(message);
      }
      _pendingMessages.clear();
    }
    eventPump.start(this);
  }

  void resetForReload() {
    eventPump.stop();
    _webReady = false;
    _pendingMessages.clear();
    _localStorage.clear();
  }

  void dispose() {
    eventPump.stop();
  }

  Future<dynamic> handleJsMessage(dynamic rawMessage) async {
    final message = EvenAppMessage.fromDynamic(rawMessage);
    if (message.type == 'call_even_app_method') {
      final payload = message.data ?? message.payload;
      return _handleCall(message.method, payload);
    }
    return null;
  }

  Future<dynamic> _handleCall(String method, dynamic payload) async {
    switch (method) {
      case 'getUserInfo':
        return state.userInfo.toJson();
      case 'getGlassesInfo':
      case 'getDeviceInfo':
        return state.deviceInfo.toJson();
      case 'setLocalStorage':
        return _setLocalStorage(payload);
      case 'getLocalStorage':
        return _getLocalStorage(payload);
      case 'createStartUpPageContainer':
        return _createStartupPage(payload);
      case 'rebuildPageContainer':
        return _rebuildPage(payload);
      case 'updateImageRawData':
        return _updateImage(payload);
      case 'textContainerUpgrade':
        return _updateText(payload);
      case 'shutDownPageContainer':
        return _shutdownPage(payload);
      default:
        return null;
    }
  }

  bool _setLocalStorage(dynamic payload) {
    final map = _asMap(payload);
    final key = map['key']?.toString();
    final value = map['value']?.toString();
    if (key == null) return false;
    _localStorage[key] = value ?? '';
    return true;
  }

  String _getLocalStorage(dynamic payload) {
    final map = _asMap(payload);
    final key = map['key']?.toString();
    if (key == null) return '';
    return _localStorage[key] ?? '';
  }

  int _createStartupPage(dynamic payload) {
    if (state.startupCreated) {
      return 1;
    }

    final map = _asMap(payload);
    final parsed = PageContainerPayload.fromJson(map);
    final totalContainers = parsed.listContainers.length +
        parsed.textContainers.length +
        parsed.imageContainers.length;
    final containerTotalNum = _readInt(map, ['containerTotalNum', 'ContainerTotalNum']) ?? totalContainers;

    if (containerTotalNum > 4 || totalContainers > 4) {
      return 2;
    }
    if (totalContainers == 0) {
      return 1;
    }

    final eventCaptureCount = _countEventCapture(parsed);
    if (eventCaptureCount != 1) {
      return 1;
    }

    state.applyStartupContainer(parsed, isRebuild: false);
    return 0;
  }

  bool _rebuildPage(dynamic payload) {
    final map = _asMap(payload);
    final parsed = PageContainerPayload.fromJson(map);
    final totalContainers = parsed.listContainers.length +
        parsed.textContainers.length +
        parsed.imageContainers.length;

    if (totalContainers == 0 || totalContainers > 4) {
      return false;
    }

    final eventCaptureCount = _countEventCapture(parsed);
    if (eventCaptureCount != 1) {
      return false;
    }

    state.applyStartupContainer(parsed, isRebuild: true);
    return true;
  }

  int _updateImage(dynamic payload) {
    final map = _asMap(payload);
    final update = ImageRawDataUpdatePayload.fromJson(map);
    final existed = _matchesImageContainer(update);
    if (!existed) {
      return 3;
    }
    state.updateImage(update);
    return 0;
  }

  bool _updateText(dynamic payload) {
    final map = _asMap(payload);
    final update = TextContainerUpgradePayload.fromJson(map);
    final existed = _matchesTextContainer(update);
    if (!existed) {
      return false;
    }
    state.updateText(update);
    return true;
  }

  bool _shutdownPage(dynamic payload) {
    state.resetPage();
    return true;
  }

  void pushDeviceStatusChanged() {
    pushListenEvent('deviceStatusChanged', state.deviceInfo.status.toJson());
  }

  void pushListenEvent(String method, Map<String, dynamic> data) {
    final message = {
      'type': 'listen_even_app_data',
      'method': method,
      'data': data,
    };
    _enqueueMessage(message);
  }

  void pushEvenHubEvent({
    required String type,
    required Map<String, dynamic> payload,
  }) {
    pushListenEvent('evenHubEvent', {
      'type': type,
      'jsonData': payload,
    });
  }

  void emitListEvent({
    required ListContainerState container,
    required int itemIndex,
    String eventType = 'CLICK_EVENT',
  }) {
    final itemName = container.itemContainer.itemNames.isNotEmpty &&
            itemIndex >= 0 &&
            itemIndex < container.itemContainer.itemNames.length
        ? container.itemContainer.itemNames[itemIndex]
        : null;
    pushEvenHubEvent(
      type: 'listEvent',
      payload: {
        'containerID': container.containerID,
        'containerName': container.containerName,
        'currentSelectItemName': itemName,
        'currentSelectItemIndex': itemIndex,
        'eventType': eventType,
      },
    );
  }

  void emitTextEvent({
    required TextContainerState container,
    String eventType = 'CLICK_EVENT',
  }) {
    pushEvenHubEvent(
      type: 'textEvent',
      payload: {
        'containerID': container.containerID,
        'containerName': container.containerName,
        'eventType': eventType,
      },
    );
  }

  void emitSysEvent({
    required String eventType,
  }) {
    pushEvenHubEvent(
      type: 'sysEvent',
      payload: {
        'eventType': eventType,
      },
    );
  }

  void _enqueueMessage(Map<String, dynamic> message) {
    if (_webReady) {
      _sendMessageToWeb(message);
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> _sendMessageToWeb(Map<String, dynamic> message) async {
    if (_webViewController == null) return;
    final jsonMessage = jsonEncode(message);
    final script = 'window._evenAppHandleMessage && window._evenAppHandleMessage($jsonMessage);';
    await _webViewController!.evaluateJavascript(source: script);
  }

  int _countEventCapture(PageContainerPayload payload) {
    final containers = <ContainerBaseState>[
      ...payload.listContainers,
      ...payload.textContainers,
      ...payload.imageContainers,
    ];
    return containers.where((container) => container.isEventCapture).length;
  }

  bool _matchesTextContainer(TextContainerUpgradePayload payload) {
    return state.textContainers.any((container) {
      if (payload.containerID != null && container.containerID == payload.containerID) return true;
      if (payload.containerName != null && container.containerName == payload.containerName) return true;
      return false;
    });
  }

  bool _matchesImageContainer(ImageRawDataUpdatePayload payload) {
    return state.imageContainers.any((container) {
      if (payload.containerID != null && container.containerID == payload.containerID) return true;
      if (payload.containerName != null && container.containerName == payload.containerName) return true;
      return false;
    });
  }
}

Map<String, dynamic> _asMap(dynamic payload) {
  if (payload is Map<String, dynamic>) return payload;
  if (payload is Map) {
    return payload.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

int? _readInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    }
  }
  return null;
}
