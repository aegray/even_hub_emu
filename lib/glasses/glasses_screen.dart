import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge/even_app_bridge.dart';
import 'glasses_model.dart';

class GlassesScreen extends StatefulWidget {
  const GlassesScreen({
    super.key,
    required this.state,
    required this.bridgeHost,
    this.onHoverPositionChanged,
    this.pixelPerfect = false,
    this.onToggleWearing,
  });

  final GlassesState state;
  final EvenAppBridgeHost bridgeHost;
  final ValueChanged<Offset?>? onHoverPositionChanged;
  final bool pixelPerfect;
  final ValueChanged<bool>? onToggleWearing;

  @override
  State<GlassesScreen> createState() => _GlassesScreenState();
}

class _GlassesScreenState extends State<GlassesScreen> {
  static const double _listItemHeight = 22.0;
  static const double _listItemExtent = 26.0;
  static const double _textLineHeight = 14.0;

  final FocusNode _focusNode = FocusNode();
  final Map<String, ScrollController> _listControllers = {};
  final Map<String, int> _textScrollOffsets = {};
  List<ContainerBaseState> _orderedContainers = [];
  int _focusedIndex = 0;
  _ViewportSize? _lastViewport;
  bool _focusInitScheduled = false;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    for (final controller in _listControllers.values) {
      controller.dispose();
    }
    _listControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
            final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 300.0;
            final viewport = widget.pixelPerfect
                ? _ViewportSize.pixelPerfect()
                : _ViewportSize.fit(width, height);
            _lastViewport = viewport;

            _orderedContainers = _orderedContainerList();
            final captureIndex = _eventCaptureIndex();
            if (captureIndex != null) {
              _focusedIndex = captureIndex;
              _scheduleFocusInit(resetIndex: false);
            }

            _syncListControllers();

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    onKeyEvent: _handleKeyEvent,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: (event) {
                        if (!_isHovering) {
                          return;
                        }
                        if (event is PointerScrollEvent) {
                          if (event.scrollDelta.dy > 0) {
                            _handleScroll(1);
                          } else if (event.scrollDelta.dy < 0) {
                            _handleScroll(-1);
                          }
                        }
                      },
                      child: GestureDetector(
                        onTapDown: (details) => _handleTap(details.localPosition, false),
                        onDoubleTapDown: (details) => _handleTap(details.localPosition, true),
                        child: MouseRegion(
                          onEnter: (_) {
                            _isHovering = true;
                            _focusNode.requestFocus();
                          },
                          onHover: widget.onHoverPositionChanged == null
                              ? null
                              : (event) {
                                  _isHovering = true;
                                  final dx = (event.localPosition.dx / viewport.width) * viewport.logicalWidth;
                                  final dy = (event.localPosition.dy / viewport.height) * viewport.logicalHeight;
                                  final clampedX = dx.clamp(0, viewport.logicalWidth - 1).toDouble();
                                  final clampedY = dy.clamp(0, viewport.logicalHeight - 1).toDouble();
                                  widget.onHoverPositionChanged!(Offset(clampedX, clampedY));
                                },
                          onExit: (_) {
                            _isHovering = false;
                            if (widget.onHoverPositionChanged != null) {
                              widget.onHoverPositionChanged!(null);
                            }
                          },
                          child: SizedBox(
                            width: viewport.width,
                            height: viewport.height,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.greenAccent, width: 1.5),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 20,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Container(
                                        color: const Color(0xFF0B0D0C),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        alignment: Alignment.topLeft,
                                        child: SizedBox(
                                          width: viewport.logicalWidth,
                                          height: viewport.logicalHeight,
                                          child: _GlassesCanvas(
                                            state: widget.state,
                                            listControllers: _listControllers,
                                            textScrollOffsets: _textScrollOffsets,
                                            containerKeyFor: _containerKey,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Battery/status pill hidden in viewport; keep footer status line.
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ControlBar(
                    isWearing: widget.state.deviceInfo.status.isWearing,
                    onScrollUp: () => _handleScroll(-1),
                    onScrollDown: () => _handleScroll(1),
                    onClick: () => _emitEventForFocused('CLICK_EVENT'),
                    onDoubleClick: () => _emitEventForFocused('DOUBLE_CLICK_EVENT'),
                    onToggleWearing: widget.onToggleWearing,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _handleScroll(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _handleScroll(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _emitEventForFocused('CLICK_EVENT');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backslash) {
      _emitEventForFocused('DOUBLE_CLICK_EVENT');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleScroll(int direction) {
    if (_orderedContainers.isEmpty) {
      return;
    }
    final container = _focusedContainer();
    if (container == null) {
      return;
    }
    _scrollWithinContainer(container, direction);
    _emitEvent(container, direction > 0 ? 'SCROLL_BOTTOM_EVENT' : 'SCROLL_TOP_EVENT');
  }

  void _handleTap(Offset localPosition, bool doubleClick) {
    _focusNode.requestFocus();
    final viewport = _lastViewport;
    if (viewport == null) {
      return;
    }
    final dx = (localPosition.dx / viewport.width) * viewport.logicalWidth;
    final dy = (localPosition.dy / viewport.height) * viewport.logicalHeight;
    final logical = Offset(
      dx.clamp(0, viewport.logicalWidth - 1).toDouble(),
      dy.clamp(0, viewport.logicalHeight - 1).toDouble(),
    );
    final container = _focusedContainer();
    if (container == null) {
      return;
    }
    if (container is ListContainerState) {
      final key = _containerKey(container);
      final controller = _listControllers[key];
      final padding = container.paddingLength ?? 6;
      final innerY = logical.dy - container.yPosition - padding;
      if (innerY >= 0 && innerY <= container.height - padding * 2) {
        final scrollOffset = controller?.hasClients == true ? controller!.offset : 0.0;
        final index = ((innerY + scrollOffset) / _listItemExtent).floor();
        final items = _listItems(container);
        if (index >= 0 && index < items.length) {
          widget.state.selectListItem(container.containerID ?? 0, index);
          _ensureListVisible(container, index);
        }
      }
    }

    _emitEvent(container, doubleClick ? 'DOUBLE_CLICK_EVENT' : 'CLICK_EVENT');
  }

  void _emitEventForFocused(String eventType) {
    final container = _focusedContainer();
    if (container == null) {
      debugPrint('target container was null');
      return;
    }
    _emitEvent(container, eventType);
  }

  void _emitEvent(ContainerBaseState container, String eventType) {
    debugPrint('[Emu] emit $eventType -> ${container.runtimeType} id=${container.containerID} name=${container.containerName}');
    if (container is ListContainerState) {
      widget.bridgeHost.emitListEvent(
        container: container,
        itemIndex: container.selectedIndex ?? 0,
        eventType: eventType,
      );
    } else if (container is TextContainerState) {
      widget.bridgeHost.emitTextEvent(container: container, eventType: eventType);
    } else if (container is ImageContainerState) {
      widget.bridgeHost.emitImageEvent(container: container, eventType: eventType);
    }
  }

  bool _scrollWithinContainer(ContainerBaseState container, int direction) {
    if (container is ListContainerState) {
      final items = _listItems(container);
      if (items.isEmpty) {
        return false;
      }
      final current = container.selectedIndex ?? 0;
      if (direction > 0 && current < items.length - 1) {
        final nextIndex = current + 1;
        widget.state.selectListItem(container.containerID ?? 0, nextIndex);
        _adjustListScroll(container, current, nextIndex, direction);
        return true;
      }
      if (direction < 0 && current > 0) {
        final nextIndex = current - 1;
        widget.state.selectListItem(container.containerID ?? 0, nextIndex);
        _adjustListScroll(container, current, nextIndex, direction);
        return true;
      }
      return false;
    }

    if (container is TextContainerState) {
      final key = _containerKey(container);
      final lines = _textLines(container);
      if (lines.isEmpty) {
        return false;
      }
      final current = _textScrollOffsets[key] ?? 0;
      if (direction > 0 && current < lines.length - 1) {
        setState(() {
          _textScrollOffsets[key] = current + 1;
        });
        return true;
      }
      if (direction < 0 && current > 0) {
        setState(() {
          _textScrollOffsets[key] = current - 1;
        });
        return true;
      }
    }

    return false;
  }

  void _scheduleFocusInit({required bool resetIndex}) {
    if (_focusInitScheduled) {
      return;
    }
    _focusInitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusInitScheduled = false;
      if (!mounted) {
        return;
      }
      if (_orderedContainers.isEmpty) {
        return;
      }
      if (resetIndex && _focusedIndex >= _orderedContainers.length) {
        setState(() {
          _focusedIndex = 0;
        });
      }
      final container = _orderedContainers[_focusedIndex];
      if (container is ListContainerState) {
        if (container.selectedIndex == null || container.selectedIndex! < 0) {
          widget.state.selectListItem(container.containerID ?? 0, 0);
          _ensureListVisible(container, 0);
        }
      } else if (container is TextContainerState) {
        final key = _containerKey(container);
        if (!_textScrollOffsets.containsKey(key)) {
          setState(() {
            _textScrollOffsets[key] = 0;
          });
        }
      }
    });
  }

  void _ensureListVisible(ListContainerState container, int index) {
    final key = _containerKey(container);
    final controller = _listControllers[key];
    if (controller == null) {
      return;
    }
    final target = (index * _listItemExtent).toDouble();
    if (controller.hasClients) {
      final maxExtent = controller.position.maxScrollExtent;
      controller.jumpTo(target.clamp(0, maxExtent));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final maxExtent = controller.position.maxScrollExtent;
        controller.jumpTo(target.clamp(0, maxExtent));
      });
    }
  }

  void _adjustListScroll(ListContainerState container, int previousIndex, int index, int direction) {
    final key = _containerKey(container);
    final controller = _listControllers[key];
    if (controller == null) {
      return;
    }
    final padding = container.paddingLength ?? 6;
    final innerHeight = max(container.height - padding * 2, _listItemExtent);
    final visibleCount = max(1, (innerHeight / _listItemExtent).floor());
    final currentOffset = controller.hasClients ? controller.offset : 0.0;
    final firstVisible = (currentOffset / _listItemExtent).floor();
    final lastVisible = firstVisible + visibleCount - 1;

    if (direction > 0) {
      if (previousIndex >= lastVisible && index > lastVisible) {
        _ensureListVisible(container, index);
      }
      return;
    }

    if (direction < 0) {
      if (previousIndex <= firstVisible && index < firstVisible) {
        _ensureListVisible(container, index);
      }
    }
  }

  int? _findContainerIndexAt(Offset logical) {
    for (var i = 0; i < _orderedContainers.length; i++) {
      final container = _orderedContainers[i];
      if (logical.dx >= container.xPosition &&
          logical.dx <= container.xPosition + container.width &&
          logical.dy >= container.yPosition &&
          logical.dy <= container.yPosition + container.height) {
        return i;
      }
    }
    return null;
  }

  List<String> _listItems(ListContainerState container) {
    if (container.itemContainer.itemNames.isNotEmpty) {
      return container.itemContainer.itemNames;
    }
    return List.generate(max(container.itemContainer.itemCount, 1), (index) => 'Item ${index + 1}');
  }

  List<String> _textLines(TextContainerState container) {
    final content = container.content ?? '';
    if (content.isEmpty) {
      return const [];
    }
    return content.split('\n');
  }

  String _containerKey(ContainerBaseState container) {
    if (container.containerID != null) {
      return 'id:${container.containerID}';
    }
    if (container.containerName != null && container.containerName!.isNotEmpty) {
      return 'name:${container.containerName}';
    }
    return 'hash:${container.hashCode}';
  }

  void _syncListControllers() {
    final activeKeys = <String>{};
    for (final container in widget.state.listContainers) {
      final key = _containerKey(container);
      activeKeys.add(key);
      _listControllers.putIfAbsent(key, () => ScrollController());
    }
    final toRemove = _listControllers.keys.where((key) => !activeKeys.contains(key)).toList();
    for (final key in toRemove) {
      _listControllers[key]?.dispose();
      _listControllers.remove(key);
    }
  }

  List<ContainerBaseState> _orderedContainerList() {
    final containers = <ContainerBaseState>[
      ...widget.state.listContainers,
      ...widget.state.textContainers,
      ...widget.state.imageContainers,
    ];
    containers.sort((a, b) {
      final byY = a.yPosition.compareTo(b.yPosition);
      if (byY != 0) return byY;
      return a.xPosition.compareTo(b.xPosition);
    });
    return containers;
  }

  ContainerBaseState? _focusedContainer() {
    final captureIndex = _eventCaptureIndex();
    if (captureIndex != null &&
        captureIndex >= 0 &&
        captureIndex < _orderedContainers.length) {
      return _orderedContainers[captureIndex];
    }
    final captureId = widget.state.eventCaptureContainerId;
    if (captureId != null) {
      for (final container in _orderedContainers) {
        if (container.containerID == captureId) {
          return container;
        }
      }
    }
    return null;
  }

  int? _eventCaptureIndex() {
    for (var i = 0; i < _orderedContainers.length; i++) {
      if (_orderedContainers[i].isEventCapture) {
        return i;
      }
    }
    return null;
  }
}

class _GlassesCanvas extends StatelessWidget {
  const _GlassesCanvas({
    required this.state,
    required this.listControllers,
    required this.textScrollOffsets,
    required this.containerKeyFor,
  });

  final GlassesState state;
  final Map<String, ScrollController> listControllers;
  final Map<String, int> textScrollOffsets;
  final String Function(ContainerBaseState) containerKeyFor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final container in state.listContainers) _buildListContainer(container),
        for (final container in state.textContainers) _buildTextContainer(container),
        for (final container in state.imageContainers) _buildImageContainer(container),
      ],
    );
  }

  Widget _buildListContainer(ListContainerState container) {
    final items = container.itemContainer.itemNames.isNotEmpty
        ? container.itemContainer.itemNames
        : List.generate(max(container.itemContainer.itemCount, 1), (index) => 'Item ${index + 1}');
    final itemHeight = _GlassesScreenState._listItemHeight;
    final controller = listControllers[containerKeyFor(container)];

    return Positioned(
      left: container.xPosition,
      top: container.yPosition,
      width: container.width,
      height: container.height,
      child: Container(
        padding: EdgeInsets.all(container.paddingLength ?? 6),
        decoration: _containerDecoration(container),
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemExtent: itemHeight + 4,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: container.selectedIndex == index ? Colors.green.withOpacity(0.2) : Colors.transparent,
                border: container.itemContainer.isItemSelectBorderEn == true && container.selectedIndex == index
                    ? Border.all(color: Colors.greenAccent, width: 1)
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  items[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextContainer(TextContainerState container) {
    final key = containerKeyFor(container);
    final lines = (container.content ?? '').split('\n');
    final startIndex = textScrollOffsets[key] ?? 0;
    final padding = container.paddingLength ?? 6;
    final maxLines = ((container.height - padding * 2) / 14.0).floor().clamp(1, lines.length);
    final visibleLines = lines.isEmpty
        ? ''
        : lines.skip(startIndex).take(maxLines).join('\n');

    return Positioned(
      left: container.xPosition,
      top: container.yPosition,
      width: container.width,
      height: container.height,
      child: Container(
        padding: EdgeInsets.all(container.paddingLength ?? 6),
        decoration: _containerDecoration(container),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            visibleLines,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 12,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContainer(ImageContainerState container) {
    return Positioned(
      left: container.xPosition,
      top: container.yPosition,
      width: container.width,
      height: container.height,
      child: Container(
        decoration: _containerDecoration(container),
        child: container.imageBytes == null
            ? const Center(
                child: Text(
                  'Image Placeholder',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              )
            : Image.memory(
                container.imageBytes!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Center(
                    child: Text(
                      'Invalid image data',
                      style: TextStyle(color: Colors.redAccent, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
      ),
    );
  }

  BoxDecoration _containerDecoration(ContainerBaseState container) {
    final borderColor = _resolveColor(container.borderColor) ?? Colors.greenAccent;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(container.borderRadius ?? 6),
      border: Border.all(
        color: borderColor,
        width: container.borderWidth ?? 1,
      ),
    );
  }

  Color? _resolveColor(int? value) {
    if (value == null) return null;
    if (value <= 0xFFFFFF) {
      return Color(0xFF000000 | value);
    }
    if (value <= 0xFFFFFFFF) {
      return Color(value);
    }
    return null;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '${status.connectType} · ${status.batteryLevel}%',
          style: const TextStyle(color: Colors.greenAccent, fontSize: 10),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.isWearing,
    required this.onScrollUp,
    required this.onScrollDown,
    required this.onClick,
    required this.onDoubleClick,
    this.onToggleWearing,
  });

  final bool isWearing;
  final VoidCallback onScrollUp;
  final VoidCallback onScrollDown;
  final VoidCallback onClick;
  final VoidCallback onDoubleClick;
  final ValueChanged<bool>? onToggleWearing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1410),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ControlButton(label: 'Up', icon: Icons.arrow_upward, onPressed: onScrollUp),
            _ControlButton(label: 'Down', icon: Icons.arrow_downward, onPressed: onScrollDown),
            _ControlButton(label: 'Click', icon: Icons.touch_app, onPressed: onClick),
            _ControlButton(label: 'Double', icon: Icons.double_arrow, onPressed: onDoubleClick),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: isWearing,
                  onChanged: onToggleWearing == null ? null : (value) => onToggleWearing!(value ?? false),
                ),
                const Text(
                  'Wearing',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: Colors.greenAccent),
        label: Text(
          label,
          style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
        ),
      ),
    );
  }
}

class _ViewportSize {
  const _ViewportSize({
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
  });

  final double width;
  final double height;
  final double logicalWidth;
  final double logicalHeight;

  factory _ViewportSize.fit(double width, double height) {
    const logicalWidth = 640.0;
    const logicalHeight = 350.0;
    final scale = min(width / logicalWidth, height / logicalHeight);
    return _ViewportSize(
      width: logicalWidth * scale,
      height: logicalHeight * scale,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
    );
  }

  factory _ViewportSize.pixelPerfect() {
    const logicalWidth = 640.0;
    const logicalHeight = 350.0;
    return const _ViewportSize(
      width: logicalWidth,
      height: logicalHeight,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
    );
  }
}
