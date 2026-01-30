import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class UserInfo {
  UserInfo({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.country,
  });

  final int uid;
  final String name;
  final String avatar;
  final String country;

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'avatar': avatar,
      'country': country,
    };
  }
}

class DeviceStatus {
  DeviceStatus({
    required this.sn,
    required this.connectType,
    this.isWearing = false,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.isInCase = false,
  });

  final String sn;
  String connectType;
  bool isWearing;
  int batteryLevel;
  bool isCharging;
  bool isInCase;

  Map<String, dynamic> toJson() {
    return {
      'sn': sn,
      'connectType': connectType,
      'isWearing': isWearing,
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'isInCase': isInCase,
    };
  }
}

class DeviceInfo {
  DeviceInfo({
    required this.model,
    required this.sn,
    required this.status,
  });

  final String model;
  final String sn;
  DeviceStatus status;

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'sn': sn,
      'status': status.toJson(),
    };
  }
}

class GlassesState extends ChangeNotifier {
  GlassesState({
    required this.deviceInfo,
    required this.userInfo,
  });

  final DeviceInfo deviceInfo;
  final UserInfo userInfo;

  final List<ListContainerState> listContainers = [];
  final List<TextContainerState> textContainers = [];
  final List<ImageContainerState> imageContainers = [];

  bool startupCreated = false;
  int? eventCaptureContainerId;

  void resetPage() {
    listContainers.clear();
    textContainers.clear();
    imageContainers.clear();
    eventCaptureContainerId = null;
    notifyListeners();
  }

  void applyStartupContainer(PageContainerPayload payload, {required bool isRebuild}) {
    if (isRebuild) {
      resetPage();
    } else {
      startupCreated = true;
      resetPage();
    }

    listContainers.addAll(payload.listContainers);
    textContainers.addAll(payload.textContainers);
    imageContainers.addAll(payload.imageContainers);
    eventCaptureContainerId = payload.eventCaptureContainerId;
    notifyListeners();
  }

  void updateText(TextContainerUpgradePayload payload) {
    if (payload.containerID == null && payload.containerName == null) {
      return;
    }

    final target = textContainers.firstWhere(
      (container) {
        if (payload.containerID != null && container.containerID == payload.containerID) {
          return true;
        }
        if (payload.containerName != null && container.containerName == payload.containerName) {
          return true;
        }
        return false;
      },
      orElse: () => TextContainerState.empty(),
    );

    if (target.isEmpty) {
      return;
    }

    if (payload.content != null && payload.contentOffset != null && payload.contentLength != null) {
      final original = target.content ?? '';
      final start = payload.contentOffset!.clamp(0, original.length);
      final end = (payload.contentOffset! + payload.contentLength!).clamp(0, original.length);
      target.content = original.replaceRange(start, end, payload.content!);
    } else if (payload.content != null) {
      target.content = payload.content;
    }

    notifyListeners();
  }

  void updateImage(ImageRawDataUpdatePayload payload) {
    if (payload.containerID == null && payload.containerName == null) {
      return;
    }

    final target = imageContainers.firstWhere(
      (container) {
        if (payload.containerID != null && container.containerID == payload.containerID) {
          return true;
        }
        if (payload.containerName != null && container.containerName == payload.containerName) {
          return true;
        }
        return false;
      },
      orElse: () => ImageContainerState.empty(),
    );

    if (target.isEmpty) {
      return;
    }

    target.imageBytes = payload.imageBytes;
    notifyListeners();
  }

  void selectListItem(int containerId, int itemIndex) {
    final target = listContainers.firstWhere(
      (container) => container.containerID == containerId,
      orElse: () => ListContainerState.empty(),
    );
    if (target.isEmpty) {
      return;
    }
    target.selectedIndex = itemIndex;
    notifyListeners();
  }
}

class PageContainerPayload {
  PageContainerPayload({
    required this.listContainers,
    required this.textContainers,
    required this.imageContainers,
    required this.eventCaptureContainerId,
  });

  final List<ListContainerState> listContainers;
  final List<TextContainerState> textContainers;
  final List<ImageContainerState> imageContainers;
  final int? eventCaptureContainerId;

  factory PageContainerPayload.fromJson(Map<String, dynamic> data) {
    final listData = _readList(data, ['listObject', 'List_Object']);
    final textData = _readList(data, ['textObject', 'Text_Object']);
    final imageData = _readList(data, ['imageObject', 'Image_Object']);

    final listContainers = listData
        .map((entry) => ListContainerState.fromJson(entry))
        .where((container) => !container.isEmpty)
        .toList();
    final textContainers = textData
        .map((entry) => TextContainerState.fromJson(entry))
        .where((container) => !container.isEmpty)
        .toList();
    final imageContainers = imageData
        .map((entry) => ImageContainerState.fromJson(entry))
        .where((container) => !container.isEmpty)
        .toList();

    int? eventCapture;
    for (final container in [...listContainers, ...textContainers, ...imageContainers]) {
      if (container.isEventCapture) {
        eventCapture = container.containerID;
      }
    }

    return PageContainerPayload(
      listContainers: listContainers,
      textContainers: textContainers,
      imageContainers: imageContainers,
      eventCaptureContainerId: eventCapture,
    );
  }
}

class ContainerBaseState {
  ContainerBaseState({
    required this.containerID,
    required this.containerName,
    required this.xPosition,
    required this.yPosition,
    required this.width,
    required this.height,
    this.borderWidth,
    this.borderColor,
    this.borderRadius,
    this.paddingLength,
    this.isEventCapture = false,
  });

  final int? containerID;
  final String? containerName;
  final double xPosition;
  final double yPosition;
  final double width;
  final double height;
  final double? borderWidth;
  final int? borderColor;
  final double? borderRadius;
  final double? paddingLength;
  final bool isEventCapture;

  bool get isEmpty => containerID == null && containerName == null;
}

class ListItemContainerState {
  ListItemContainerState({
    required this.itemCount,
    required this.itemNames,
    this.itemWidth,
    this.isItemSelectBorderEn,
  });

  final int itemCount;
  final List<String> itemNames;
  final double? itemWidth;
  final bool? isItemSelectBorderEn;

  factory ListItemContainerState.fromJson(Map<String, dynamic> data) {
    final itemCount = _readInt(data, ['itemCount', 'Item_Count']) ?? 0;
    final itemNames = _readStringList(data, ['itemName', 'Item_Name']);
    return ListItemContainerState(
      itemCount: itemCount,
      itemNames: itemNames,
      itemWidth: _readDouble(data, ['itemWidth', 'Item_Width']),
      isItemSelectBorderEn: _readBool(data, ['isItemSelectBorderEn', 'Is_Item_Select_Border_En']),
    );
  }
}

class ListContainerState extends ContainerBaseState {
  ListContainerState({
    required super.containerID,
    required super.containerName,
    required super.xPosition,
    required super.yPosition,
    required super.width,
    required super.height,
    super.borderWidth,
    super.borderColor,
    super.borderRadius,
    super.paddingLength,
    super.isEventCapture,
    required this.itemContainer,
    this.selectedIndex,
  });

  final ListItemContainerState itemContainer;
  int? selectedIndex;

  factory ListContainerState.fromJson(Map<String, dynamic> data) {
    final containerID = _readInt(data, ['containerID', 'Container_ID']);
    final containerName = _readString(data, ['containerName', 'Container_Name']);
    if (containerID == null && containerName == null) {
      return ListContainerState.empty();
    }

    final itemData = _readObject(data, ['itemContainer', 'Item_Container']);

    return ListContainerState(
      containerID: containerID,
      containerName: containerName,
      xPosition: _readDouble(data, ['xPosition', 'X_Position']) ?? 0,
      yPosition: _readDouble(data, ['yPosition', 'Y_Position']) ?? 0,
      width: _readDouble(data, ['width', 'Width']) ?? 0,
      height: _readDouble(data, ['height', 'Height']) ?? 0,
      borderWidth: _readDouble(data, ['borderWidth', 'Border_Width']),
      borderColor: _readInt(data, ['borderColor', 'Border_Color']),
      borderRadius: _readDouble(data, ['borderRdaius', 'Border_Rdaius', 'borderRadius']),
      paddingLength: _readDouble(data, ['paddingLength', 'Padding_Length']),
      isEventCapture: _readBool(data, ['isEventCapture', 'Is_event_capture']) ?? false,
      itemContainer: itemData.isEmpty
          ? ListItemContainerState(itemCount: 0, itemNames: const [])
          : ListItemContainerState.fromJson(itemData),
    );
  }

  factory ListContainerState.empty() {
    return ListContainerState(
      containerID: null,
      containerName: null,
      xPosition: 0,
      yPosition: 0,
      width: 0,
      height: 0,
      itemContainer: ListItemContainerState(itemCount: 0, itemNames: const []),
    );
  }
}

class TextContainerState extends ContainerBaseState {
  TextContainerState({
    required super.containerID,
    required super.containerName,
    required super.xPosition,
    required super.yPosition,
    required super.width,
    required super.height,
    super.borderWidth,
    super.borderColor,
    super.borderRadius,
    super.paddingLength,
    super.isEventCapture,
    this.content,
  });

  String? content;

  factory TextContainerState.fromJson(Map<String, dynamic> data) {
    final containerID = _readInt(data, ['containerID', 'Container_ID']);
    final containerName = _readString(data, ['containerName', 'Container_Name']);
    if (containerID == null && containerName == null) {
      return TextContainerState.empty();
    }
    return TextContainerState(
      containerID: containerID,
      containerName: containerName,
      xPosition: _readDouble(data, ['xPosition', 'X_Position']) ?? 0,
      yPosition: _readDouble(data, ['yPosition', 'Y_Position']) ?? 0,
      width: _readDouble(data, ['width', 'Width']) ?? 0,
      height: _readDouble(data, ['height', 'Height']) ?? 0,
      borderWidth: _readDouble(data, ['borderWidth', 'Border_Width']),
      borderColor: _readInt(data, ['borderColor', 'Border_Color']),
      borderRadius: _readDouble(data, ['borderRdaius', 'Border_Rdaius', 'borderRadius']),
      paddingLength: _readDouble(data, ['paddingLength', 'Padding_Length']),
      isEventCapture: _readBool(data, ['isEventCapture', 'Is_event_capture']) ?? false,
      content: _readString(data, ['content', 'Content']),
    );
  }

  factory TextContainerState.empty() {
    return TextContainerState(
      containerID: null,
      containerName: null,
      xPosition: 0,
      yPosition: 0,
      width: 0,
      height: 0,
    );
  }
}

class ImageContainerState extends ContainerBaseState {
  ImageContainerState({
    required super.containerID,
    required super.containerName,
    required super.xPosition,
    required super.yPosition,
    required super.width,
    required super.height,
    super.isEventCapture,
    this.imageBytes,
  });

  Uint8List? imageBytes;

  factory ImageContainerState.fromJson(Map<String, dynamic> data) {
    final containerID = _readInt(data, ['containerID', 'Container_ID']);
    final containerName = _readString(data, ['containerName', 'Container_Name']);
    if (containerID == null && containerName == null) {
      return ImageContainerState.empty();
    }
    return ImageContainerState(
      containerID: containerID,
      containerName: containerName,
      xPosition: _readDouble(data, ['xPosition', 'X_Position']) ?? 0,
      yPosition: _readDouble(data, ['yPosition', 'Y_Position']) ?? 0,
      width: _readDouble(data, ['width', 'Width']) ?? 0,
      height: _readDouble(data, ['height', 'Height']) ?? 0,
      isEventCapture: _readBool(data, ['isEventCapture', 'Is_event_capture']) ?? false,
    );
  }

  factory ImageContainerState.empty() {
    return ImageContainerState(
      containerID: null,
      containerName: null,
      xPosition: 0,
      yPosition: 0,
      width: 0,
      height: 0,
    );
  }
}

class TextContainerUpgradePayload {
  TextContainerUpgradePayload({
    this.containerID,
    this.containerName,
    this.contentOffset,
    this.contentLength,
    this.content,
  });

  final int? containerID;
  final String? containerName;
  final int? contentOffset;
  final int? contentLength;
  final String? content;

  factory TextContainerUpgradePayload.fromJson(Map<String, dynamic> data) {
    return TextContainerUpgradePayload(
      containerID: _readInt(data, ['containerID', 'Container_ID']),
      containerName: _readString(data, ['containerName', 'Container_Name']),
      contentOffset: _readInt(data, ['contentOffset', 'ContentOffset']),
      contentLength: _readInt(data, ['contentLength', 'ContentLength']),
      content: _readString(data, ['content', 'Content']),
    );
  }
}

class ImageRawDataUpdatePayload {
  ImageRawDataUpdatePayload({
    this.containerID,
    this.containerName,
    this.imageBytes,
  });

  final int? containerID;
  final String? containerName;
  final Uint8List? imageBytes;

  factory ImageRawDataUpdatePayload.fromJson(Map<String, dynamic> data) {
    final raw = data['imageData'] ?? data['mapRawData'] ?? data['Map_RawData'];
    return ImageRawDataUpdatePayload(
      containerID: _readInt(data, ['containerID', 'Container_ID']),
      containerName: _readString(data, ['containerName', 'Container_Name']),
      imageBytes: _decodeImageBytes(raw),
    );
  }
}

Uint8List? _decodeImageBytes(dynamic raw) {
  if (raw == null) return null;
  if (raw is Uint8List) return raw;
  if (raw is List) {
    final bytes = raw.map((value) => value is int ? value : int.tryParse(value.toString()) ?? 0).toList();
    return Uint8List.fromList(bytes);
  }
  if (raw is String) {
    final dataUrl = raw.split(',');
    final base64String = dataUrl.length > 1 ? dataUrl.last : raw;
    try {
      return base64.decode(base64String);
    } catch (_) {
      return null;
    }
  }
  return null;
}

Map<String, dynamic> _readObject(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry(key.toString(), value));
  return {};
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is List) {
    return value
        .whereType<Map>()
        .map((entry) => entry.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }
  return [];
}

List<String> _readStringList(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is List) {
    return value.map((entry) => entry.toString()).toList();
  }
  return [];
}

String? _readString(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value == null) return null;
  return value.toString();
}

int? _readInt(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _readBool(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return null;
}

double? _readDouble(Map<String, dynamic> data, List<String> keys) {
  final value = _pickLoose(data, keys);
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _normalizeKey(String key) {
  return key.replaceAll('_', '').toLowerCase();
}

dynamic _pickLoose(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key];
  }

  final normalizedTargets = keys.map(_normalizeKey).toSet();
  for (final entry in data.entries) {
    if (normalizedTargets.contains(_normalizeKey(entry.key))) {
      return entry.value;
    }
  }
  return null;
}
