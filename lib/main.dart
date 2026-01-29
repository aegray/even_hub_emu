import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'bridge/even_app_bridge.dart';
import 'glasses/glasses_model.dart';
import 'glasses/glasses_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EvenHubEmuApp());
}

class EvenHubEmuApp extends StatelessWidget {
  const EvenHubEmuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EvenHub Emulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const EmulatorHomePage(),
    );
  }
}

class EmulatorHomePage extends StatefulWidget {
  const EmulatorHomePage({super.key});

  @override
  State<EmulatorHomePage> createState() => _EmulatorHomePageState();
}

class _EmulatorHomePageState extends State<EmulatorHomePage> with WidgetsBindingObserver {
  late final GlassesState _state;
  late final EvenAppBridgeHost _bridgeHost;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final deviceStatus = DeviceStatus(
      sn: 'EMU-001',
      connectType: 'connected',
      isWearing: true,
      batteryLevel: 82,
      isCharging: false,
      isInCase: false,
    );

    _state = GlassesState(
      deviceInfo: DeviceInfo(
        model: 'g1',
        sn: 'EMU-001',
        status: deviceStatus,
      ),
      userInfo: UserInfo(
        uid: 42,
        name: 'Even Dev',
        avatar: 'local-avatar',
        country: 'US',
      ),
    );

    _bridgeHost = EvenAppBridgeHost(state: _state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridgeHost.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_bridgeHost.eventPump.sendForegroundEvents) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _bridgeHost.emitSysEvent(eventType: 'FOREGROUND_ENTER_EVENT');
    } else if (state == AppLifecycleState.paused) {
      _bridgeHost.emitSysEvent(eventType: 'FOREGROUND_EXIT_EVENT');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EvenHub Emulator'),
        actions: [
          IconButton(
            tooltip: 'Send Device Status',
            onPressed: _bridgeHost.pushDeviceStatusChanged,
            icon: const Icon(Icons.wifi),
          ),
          IconButton(
            tooltip: 'Toggle Wearing',
            onPressed: _toggleWearing,
            icon: const Icon(Icons.visibility),
          ),
          IconButton(
            tooltip: 'Battery -10%',
            onPressed: _drainBattery,
            icon: const Icon(Icons.battery_alert),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: _buildWebView()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildGlassesPanel()),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: _buildWebView()),
                const Divider(height: 1),
                Expanded(child: _buildGlassesPanel()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _bridgeHost.attachWebViewController(controller);
        controller.addJavaScriptHandler(
          handlerName: 'evenAppMessage',
          callback: (args) async {
            final message = args.isNotEmpty ? args.first : null;
            return _bridgeHost.handleJsMessage(message);
          },
        );
        _loadLocalIndex(controller);
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: '''
          window._evenAppHandleMessage = window._evenAppHandleMessage || function(message) {
            console.log('[EvenHubEmu] Received native push', message);
          };
        ''');
        _bridgeHost.onWebReady();
      },
    );
  }

  Widget _buildGlassesPanel() {
    return Column(
      children: [
        Expanded(
          child: GlassesScreen(
            state: _state,
            bridgeHost: _bridgeHost,
          ),
        ),
        _buildStatusFooter(),
      ],
    );
  }

  Widget _buildStatusFooter() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Device: ${_state.deviceInfo.model.toUpperCase()} · ${_state.deviceInfo.sn}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            'Battery ${_state.deviceInfo.status.batteryLevel}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _loadLocalIndex(InAppWebViewController controller) async {
    final documents = await getApplicationDocumentsDirectory();
    final localFile = File('${documents.path}/index.html');
    if (await localFile.exists()) {
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri.uri(Uri.file(localFile.path)),
        ),
        allowingReadAccessTo: WebUri.uri(Uri.file(documents.path)),
      );
      return;
    }
    await controller.loadFile(assetFilePath: 'assets/index.html');
  }

  void _toggleWearing() {
    setState(() {
      _state.deviceInfo.status.isWearing = !_state.deviceInfo.status.isWearing;
    });
    _bridgeHost.pushDeviceStatusChanged();
  }

  void _drainBattery() {
    setState(() {
      _state.deviceInfo.status.batteryLevel =
          (_state.deviceInfo.status.batteryLevel - 10).clamp(0, 100);
    });
    _bridgeHost.pushDeviceStatusChanged();
  }
}
