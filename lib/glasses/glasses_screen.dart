import 'dart:math';

import 'package:flutter/material.dart';

import '../bridge/even_app_bridge.dart';
import 'glasses_model.dart';

class GlassesScreen extends StatelessWidget {
  const GlassesScreen({
    super.key,
    required this.state,
    required this.bridgeHost,
  });

  final GlassesState state;
  final EvenAppBridgeHost bridgeHost;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 400.0;
            final height = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 300.0;
            final viewport = _ViewportSize.fit(width, height);

            return Center(
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
                                state: state,
                                bridgeHost: bridgeHost,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 8,
                          child: _StatusPill(status: state.deviceInfo.status),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GlassesCanvas extends StatelessWidget {
  const _GlassesCanvas({
    required this.state,
    required this.bridgeHost,
  });

  final GlassesState state;
  final EvenAppBridgeHost bridgeHost;

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
    final isInteractive = container.isEventCapture || container.containerID == state.eventCaptureContainerId;

    return Positioned(
      left: container.xPosition,
      top: container.yPosition,
      width: container.width,
      height: container.height,
      child: Container(
        padding: EdgeInsets.all(container.paddingLength ?? 6),
        decoration: _containerDecoration(container),
        child: Column(
          children: [
            for (int index = 0; index < items.length; index++)
              Expanded(
                child: GestureDetector(
                  onTap: isInteractive
                      ? () {
                          state.selectListItem(container.containerID ?? 0, index);
                          bridgeHost.emitListEvent(container: container, itemIndex: index);
                        }
                      : null,
                  child: Container(
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
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContainer(TextContainerState container) {
    final isInteractive = container.isEventCapture || container.containerID == state.eventCaptureContainerId;

    return Positioned(
      left: container.xPosition,
      top: container.yPosition,
      width: container.width,
      height: container.height,
      child: GestureDetector(
        onTap: isInteractive
            ? () {
                bridgeHost.emitTextEvent(container: container);
              }
            : null,
        child: Container(
          padding: EdgeInsets.all(container.paddingLength ?? 6),
          decoration: _containerDecoration(container),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              container.content ?? '',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
              ),
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
    const logicalHeight = 360.0;
    final scale = min(width / logicalWidth, height / logicalHeight);
    return _ViewportSize(
      width: logicalWidth * scale,
      height: logicalHeight * scale,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
    );
  }
}
