import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'bridge/even_app_bridge.dart';
import 'glasses/glasses_model.dart';
import 'glasses/glasses_screen.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final indexPath = _parseIndexArgument(args);
  runApp(EvenHubEmuApp(initialIndexPath: indexPath));
}

String? _parseIndexArgument(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--index' && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('--index=')) {
      return arg.substring('--index='.length);
    }
  }
  return null;
}

class EvenHubEmuApp extends StatelessWidget {
  const EvenHubEmuApp({
    super.key,
    this.initialIndexPath,
  });

  final String? initialIndexPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EvenHub Emulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: EmulatorHomePage(initialIndexPath: initialIndexPath),
    );
  }
}

class EmulatorHomePage extends StatefulWidget {
  const EmulatorHomePage({
    super.key,
    this.initialIndexPath,
  });

  final String? initialIndexPath;

  @override
  State<EmulatorHomePage> createState() => _EmulatorHomePageState();
}

class _EmulatorHomePageState extends State<EmulatorHomePage> with WidgetsBindingObserver {
  late final GlassesState _state;
  late final EvenAppBridgeHost _bridgeHost;
  late final DeviceStatus _baselineStatus;
  String? _currentIndexPath;
  String? _currentIndexUrl;
  _ServeMode _serveMode = _ServeMode.assets;
  int _webViewResetCounter = 0;
  final List<_ConsoleEntry> _consoleEntries = [];
  final ScrollController _consoleScrollController = ScrollController();
  final List<_WebErrorEntry> _webErrorEntries = [];
  final ScrollController _webErrorScrollController = ScrollController();
  Offset? _hoverPosition;
  String? _serveRoot;
  int? _servePort;
  HttpServer? _serveServer;

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

    _baselineStatus = DeviceStatus(
      sn: deviceStatus.sn,
      connectType: deviceStatus.connectType,
      isWearing: deviceStatus.isWearing,
      batteryLevel: deviceStatus.batteryLevel,
      isCharging: deviceStatus.isCharging,
      isInCase: deviceStatus.isInCase,
    );

    _state = GlassesState(
      deviceInfo: DeviceInfo(
        model: 'g2',
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
    _currentIndexPath = widget.initialIndexPath;
    if (_currentIndexPath != null && _currentIndexPath!.isNotEmpty) {
      _serveMode = _ServeMode.directory;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bridgeHost.dispose();
    _consoleScrollController.dispose();
    _webErrorScrollController.dispose();
    _stopServeServer();
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
        title: Row(
          children: [
            const Text('EvenHub Emulator'),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Open Index',
              onPressed: _pickAndLoadIndex,
              icon: const Icon(Icons.folder_open),
            ),
            IconButton(
              tooltip: 'Reload Index',
              onPressed: _reloadCurrentIndex,
              icon: const Icon(Icons.refresh),
            ),
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
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
            const Divider(height: 1),
            _buildConsolePanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      key: ValueKey('webview_$_webViewResetCounter'),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _bridgeHost.attachWebViewController(controller);
        controller.addUserScript(
          userScript: UserScript(
            source: '''
              (function() {
                if (window._evenEmuConsoleInstalled) return;
                window._evenEmuConsoleInstalled = true;
                window._evenEmuQueuedLogs = [];

                function canSend() {
                  return window.flutter_inappwebview && window.flutter_inappwebview.callHandler;
                }

                function safeStringify(value) {
                  if (typeof value === 'string') return value;
                  try {
                    return JSON.stringify(value);
                  } catch (e) {
                    try {
                      return String(value);
                    } catch (err) {
                      return '[unserializable]';
                    }
                  }
                }

                function sendLog(level, args) {
                  var parts = [];
                  for (var i = 0; i < args.length; i++) {
                    parts.push(safeStringify(args[i]));
                  }
                  var payload = {
                    level: level,
                    message: parts.join(' ')
                  };
                  if (canSend()) {
                    window.flutter_inappwebview.callHandler('webConsole', payload);
                  } else {
                    window._evenEmuQueuedLogs.push(payload);
                  }
                }

                function wrapConsole(level) {
                  var original = console[level] ? console[level].bind(console) : function() {};
                  console[level] = function() {
                    sendLog(level, arguments);
                    return original.apply(console, arguments);
                  };
                }

                ['log', 'warn', 'error', 'debug', 'info'].forEach(wrapConsole);

                var originalFetch = window.fetch ? window.fetch.bind(window) : null;
                window.fetch = function(input, init) {
                  if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) {
                    return originalFetch ? originalFetch(input, init) : Promise.reject(new Error('fetch not available'));
                  }

                  var url = '';
                  var method = 'GET';
                  var headers = {};
                  var body = null;

                  if (typeof input === 'string') {
                    url = input;
                  } else if (input && input.url) {
                    url = input.url;
                    method = input.method || method;
                    if (input.headers) {
                      try {
                        input.headers.forEach(function(value, key) { headers[key] = value; });
                      } catch (e) {}
                    }
                  }

                  if (init) {
                    if (init.method) method = init.method;
                    if (init.headers) {
                      if (init.headers.forEach) {
                        init.headers.forEach(function(value, key) { headers[key] = value; });
                      } else {
                        headers = Object.assign(headers, init.headers);
                      }
                    }
                    if (init.body !== undefined) {
                      body = init.body;
                    }
                  }

                  return window.flutter_inappwebview.callHandler('fetch', {
                    url: url,
                    method: method,
                    headers: headers,
                    body: body
                  }).then(function(result) {
                    var status = (result && result.status) ? result.status : 0;
                    var resHeaders = new Headers(result && result.headers ? result.headers : {});
                    return new Response(result && result.body ? result.body : '', {
                      status: status,
                      headers: resHeaders
                    });
                  });
                };

                window._evenEmuFlushLogs = function() {
                  if (!canSend()) return;
                  var queue = window._evenEmuQueuedLogs || [];
                  while (queue.length) {
                    window.flutter_inappwebview.callHandler('webConsole', queue.shift());
                  }
                };

                window.addEventListener('error', function(event) {
                  if (event && event.target && event.target.tagName) {
                    var tag = event.target.tagName.toLowerCase();
                    if (tag === 'script' || tag === 'link' || tag === 'img') {
                      var url = event.target.src || event.target.href || '';
                      if (canSend()) {
                        window.flutter_inappwebview.callHandler('webError', {
                          label: 'Resource Error',
                          details: tag + ' failed to load: ' + url
                        });
                      } else {
                        window._evenEmuQueuedLogs.push({
                          level: 'error',
                          message: '[Resource Error] ' + tag + ' failed to load: ' + url
                        });
                      }
                      return;
                    }
                  }
                  var details = (event && event.error && event.error.stack)
                    ? event.error.stack
                    : (event && event.message ? event.message : 'Unknown error');
                  if (event && event.filename) {
                    details += ' (' + event.filename + ':' + event.lineno + ':' + event.colno + ')';
                  }
                  if (canSend()) {
                    window.flutter_inappwebview.callHandler('webError', {
                      label: 'JS Error',
                      details: details
                    });
                  } else {
                    window._evenEmuQueuedLogs.push({
                      level: 'error',
                      message: '[JS Error] ' + details
                    });
                  }
                }, true);

                window.addEventListener('unhandledrejection', function(event) {
                  var reason = event && event.reason ? event.reason : 'Unhandled rejection';
                  var details = typeof reason === 'string' ? reason : safeStringify(reason);
                  if (canSend()) {
                    window.flutter_inappwebview.callHandler('webError', {
                      label: 'Unhandled Promise',
                      details: details
                    });
                  }
                });
              })();
            ''',
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        );
        controller.addJavaScriptHandler(
          handlerName: 'evenAppMessage',
          callback: (args) async {
            final message = args.isNotEmpty ? args.first : null;
            return _bridgeHost.handleJsMessage(message);
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'webError',
          callback: (args) async {
            if (args.isEmpty || args.first is! Map) {
              return null;
            }
            final payload = (args.first as Map).map((key, value) => MapEntry('$key', value));
            _appendWebErrorEntry(_WebErrorEntry(
              timestamp: DateTime.now(),
              label: payload['label']?.toString() ?? 'JS Error',
              details: payload['details']?.toString() ?? 'Unknown error',
            ));
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'webConsole',
          callback: (args) async {
            if (args.isEmpty || args.first is! Map) {
              return null;
            }
            final payload = (args.first as Map).map((key, value) => MapEntry('$key', value));
            final level = _levelFromString(payload['level']?.toString());
            final message = payload['message']?.toString() ?? '';
            _appendConsoleEntry(_ConsoleEntry(
              timestamp: DateTime.now(),
              level: level,
              message: message,
            ));
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'fetch',
          callback: (args) async {
            if (args.isEmpty || args.first is! Map) {
              return null;
            }
            final payload = (args.first as Map).map((key, value) => MapEntry('$key', value));
            final urlRaw = payload['url']?.toString();
            if (urlRaw == null || urlRaw.isEmpty) {
              return {
                'status': 0,
                'headers': <String, String>{},
                'body': 'Missing url',
              };
            }
            final uri = Uri.parse(urlRaw);
            final method = (payload['method']?.toString() ?? 'GET').toUpperCase();
            final headers = <String, String>{};
            final rawHeaders = payload['headers'];
            if (rawHeaders is Map) {
              for (final entry in rawHeaders.entries) {
                headers[entry.key.toString()] = entry.value.toString();
              }
            }
            final bodyValue = payload['body'];
            final body = bodyValue == null
                ? null
                : (bodyValue is String ? bodyValue : jsonEncode(bodyValue));

            final client = HttpClient();
            try {
              final request = await client.openUrl(method, uri);
              headers.forEach((key, value) {
                request.headers.set(key, value);
              });
              if (body != null) {
                request.add(utf8.encode(body));
              }
              final response = await request.close();
              final responseBody = await response.transform(utf8.decoder).join();
              final responseHeaders = <String, String>{};
              response.headers.forEach((name, values) {
                responseHeaders[name] = values.join(',');
              });
              return {
                'status': response.statusCode,
                'headers': responseHeaders,
                'body': responseBody,
              };
            } catch (error) {
              return {
                'status': 0,
                'headers': <String, String>{},
                'body': error.toString(),
              };
            } finally {
              client.close(force: true);
            }
          },
        );
        _loadIndex(controller);
      },
      // Console output is captured via injected JS to avoid duplicate lines.
      onLoadError: (controller, url, code, message) {
        _appendWebErrorEntry(_WebErrorEntry(
          timestamp: DateTime.now(),
          label: 'Load Error',
          details: '[$code] $message (${url?.toString() ?? 'unknown url'})',
        ));
      },
      onLoadHttpError: (controller, url, statusCode, description) {
        _appendWebErrorEntry(_WebErrorEntry(
          timestamp: DateTime.now(),
          label: 'HTTP Error',
          details: '[$statusCode] $description (${url?.toString() ?? 'unknown url'})',
        ));
      },
      onLoadResource: (controller, resource) {
        _appendWebErrorEntry(_WebErrorEntry(
          timestamp: DateTime.now(),
          label: 'Resource Load',
          details: resource.url?.toString() ?? 'unknown url',
        ));
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: '''
          window._evenAppHandleMessage = window._evenAppHandleMessage || function(message) {
            //console.log('[EvenHubEmu] Received native push', message);
          };
          if (window._evenEmuFlushLogs) {
            window._evenEmuFlushLogs();
          }
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
            onHoverPositionChanged: (position) {
              setState(() {
                _hoverPosition = position;
              });
            },
          ),
        ),
        _buildStatusFooter(),
      ],
    );
  }

  Widget _buildStatusFooter() {
    final hoverPosition = _hoverPosition;
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
          if (hoverPosition != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'x: ${hoverPosition.dx.floor()}  y: ${hoverPosition.dy.floor()}',
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

  Widget _buildConsolePanel() {
    return SizedBox(
      height: 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border(
            top: BorderSide(color: Colors.greenAccent.withOpacity(0.35)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'WebView Console',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.greenAccent,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _consoleEntries.clear();
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _consoleScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _consoleScrollController,
                        itemCount: _consoleEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _consoleEntries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: SelectableText(
                              entry.formatLine(),
                              style: TextStyle(
                                color: entry.color,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'WebView Errors',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.redAccent,
                              ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _webErrorEntries.clear();
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _webErrorScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _webErrorScrollController,
                        itemCount: _webErrorEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _webErrorEntries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: SelectableText(
                              entry.formatLine(),
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _appendConsoleEntry(_ConsoleEntry entry) {
    final shouldStickToBottom = !_consoleScrollController.hasClients ||
        (_consoleScrollController.position.maxScrollExtent - _consoleScrollController.position.pixels) <= 4;

    setState(() {
      _consoleEntries.add(entry);
      if (_consoleEntries.length > 500) {
        _consoleEntries.removeRange(0, _consoleEntries.length - 500);
      }
    });

    if (shouldStickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_consoleScrollController.hasClients) {
          return;
        }
        _consoleScrollController.jumpTo(_consoleScrollController.position.maxScrollExtent);
      });
    }
  }

  void _appendWebErrorEntry(_WebErrorEntry entry) {
    final shouldStickToBottom = !_webErrorScrollController.hasClients ||
        (_webErrorScrollController.position.maxScrollExtent - _webErrorScrollController.position.pixels) <= 4;

    setState(() {
      _webErrorEntries.add(entry);
      if (_webErrorEntries.length > 250) {
        _webErrorEntries.removeRange(0, _webErrorEntries.length - 250);
      }
    });

    if (shouldStickToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_webErrorScrollController.hasClients) {
          return;
        }
        _webErrorScrollController.jumpTo(_webErrorScrollController.position.maxScrollExtent);
      });
    }
  }

  Future<void> _loadIndex(InAppWebViewController controller) async {
    if (_currentIndexUrl == null || _currentIndexUrl!.isEmpty) {
      await _ensureServerForCurrentSource();
    }
    if (_currentIndexUrl == null || _currentIndexUrl!.isEmpty) {
      return;
    }
    await controller.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(_currentIndexUrl!),
      ),
    );
  }

  Future<void> _pickAndLoadIndex() async {
    final htmlFile = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'HTML',
          extensions: ['html', 'htm'],
        ),
      ],
    );
    if (htmlFile == null) {
      return;
    }
    _serveMode = _ServeMode.directory;
    _currentIndexUrl = null;
    await _loadNewIndex(htmlFile.path);
  }

  Future<void> _serveAndLoadIndex() async {
    await _pickAndLoadIndex();
  }

  Future<void> _reloadCurrentIndex() async {
    await _loadNewIndex(_currentIndexPath);
  }

  Future<void> _loadNewIndex(String? path) async {
    _bridgeHost.resetForReload();
    _resetGlassesState();
    setState(() {
      _consoleEntries.clear();
      _webErrorEntries.clear();
    });
    _currentIndexUrl = null;
    if (path != null && path.isNotEmpty) {
      _currentIndexPath = path;
    }
    setState(() {
      _webViewResetCounter += 1;
    });
  }

  Future<void> _ensureServerForCurrentSource() async {
    final serveMode = _serveMode;
    final port = _servePort ?? await _reservePort();
    if (port == null) {
      _appendWebErrorEntry(_WebErrorEntry(
        timestamp: DateTime.now(),
        label: 'Serve Error',
        details: 'Unable to reserve a local port.',
      ));
      return;
    }

    if (serveMode == _ServeMode.directory) {
      final indexPath = _currentIndexPath;
      if (indexPath == null || indexPath.isEmpty) {
        _serveMode = _ServeMode.assets;
      } else {
        final indexFile = File(indexPath);
        if (await indexFile.exists()) {
          await _startServeServer(indexFile.parent.path, port, _ServeMode.directory);
          final fileName = indexFile.uri.pathSegments.last;
          _currentIndexUrl = 'http://localhost:$port/$fileName';
          return;
        }
        _appendWebErrorEntry(_WebErrorEntry(
          timestamp: DateTime.now(),
          label: 'Serve Error',
          details: 'Index file not found: $indexPath',
        ));
        _serveMode = _ServeMode.assets;
      }
    }

    await _startServeServer('', port, _ServeMode.assets);
    _currentIndexUrl = 'http://localhost:$port/index.html';
  }

  Future<int?> _reservePort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startServeServer(String rootPath, int port, _ServeMode mode) async {
    if (_serveServer != null && _serveRoot == rootPath && _servePort == port && _serveMode == mode) {
      return;
    }

    await _stopServeServer();

    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _serveServer = server;
      _serveRoot = rootPath;
      _servePort = port;
      _serveMode = mode;

      server.listen((HttpRequest request) async {
        if (_serveMode == _ServeMode.assets) {
          final requestPath = request.uri.path;
          if (requestPath.contains('..')) {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            return;
          }
          final trimmed = requestPath.startsWith('/') ? requestPath.substring(1) : requestPath;
          final assetPath = trimmed.isEmpty
              ? 'assets/index.html'
              : (trimmed.startsWith('assets/') ? trimmed : 'assets/$trimmed');
          try {
            final data = await rootBundle.load(assetPath);
            request.response.headers.contentType = _contentTypeForPath(assetPath);
            request.response.add(data.buffer.asUint8List());
            await request.response.close();
            return;
          } catch (_) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
        }

        final segments = request.uri.pathSegments;
        if (segments.any((segment) => segment == '..')) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }

        final normalizedRoot = rootPath.endsWith(Platform.pathSeparator)
            ? rootPath
            : '$rootPath${Platform.pathSeparator}';
        final relativePath = segments.isEmpty ? '' : segments.join(Platform.pathSeparator);
        final targetPath = '$normalizedRoot$relativePath';
        final targetFile = File(targetPath);

        if (await targetFile.exists()) {
          request.response.headers.contentType = _contentTypeForPath(targetPath);
          await request.response.addStream(targetFile.openRead());
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
    } catch (error) {
      _appendWebErrorEntry(_WebErrorEntry(
        timestamp: DateTime.now(),
        label: 'Serve Error',
        details: 'Unable to start local server: $error',
      ));
    }
  }

  Future<void> _stopServeServer() async {
    final server = _serveServer;
    if (server == null) {
      return;
    }
    _serveServer = null;
    _serveRoot = null;
    _servePort = null;
    await server.close(force: true);
  }

  void _resetGlassesState() {
    final status = _state.deviceInfo.status;
    status.connectType = _baselineStatus.connectType;
    status.isWearing = _baselineStatus.isWearing;
    status.batteryLevel = _baselineStatus.batteryLevel;
    status.isCharging = _baselineStatus.isCharging;
    status.isInCase = _baselineStatus.isInCase;
    _state.startupCreated = false;
    _state.resetPage();
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

class _ConsoleEntry {
  _ConsoleEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final ConsoleMessageLevel level;
  final String message;

  factory _ConsoleEntry.fromMessage(ConsoleMessage message) {
    return _ConsoleEntry(
      timestamp: DateTime.now(),
      level: message.messageLevel,
      message: message.message,
    );
  }

  String formatLine() {
    final time = timestamp.toIso8601String().substring(11, 19);
    return '[$time] ${_levelLabel(level)}: $message';
  }

  Color get color {
    switch (level) {
      case ConsoleMessageLevel.ERROR:
        return Colors.redAccent;
      case ConsoleMessageLevel.WARNING:
        return Colors.amberAccent;
      case ConsoleMessageLevel.DEBUG:
        return Colors.lightBlueAccent;
      case ConsoleMessageLevel.LOG:
        return Colors.greenAccent;
      default:
        return Colors.greenAccent;
    }
  }
}

String _levelLabel(ConsoleMessageLevel level) {
  final raw = level.toString();
  final dotIndex = raw.indexOf('.');
  final label = dotIndex == -1 ? raw : raw.substring(dotIndex + 1);
  return label.toUpperCase();
}

ConsoleMessageLevel _levelFromString(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'error':
      return ConsoleMessageLevel.ERROR;
    case 'warn':
    case 'warning':
      return ConsoleMessageLevel.WARNING;
    case 'debug':
      return ConsoleMessageLevel.DEBUG;
    default:
      return ConsoleMessageLevel.LOG;
  }
}

String _injectBaseHref(String html, String baseUrl) {
  final lower = html.toLowerCase();
  if (lower.contains('<base')) {
    return html;
  }
  final baseTag = '<base href="$baseUrl">';
  final headIndex = lower.indexOf('<head');
  if (headIndex == -1) {
    return '$baseTag\n$html';
  }
  final headClose = lower.indexOf('>', headIndex);
  if (headClose == -1) {
    return '$baseTag\n$html';
  }
  return html.substring(0, headClose + 1) + '\n  $baseTag' + html.substring(headClose + 1);
}

class _WebErrorEntry {
  _WebErrorEntry({
    required this.timestamp,
    required this.label,
    required this.details,
  });

  final DateTime timestamp;
  final String label;
  final String details;

  String formatLine() {
    final time = timestamp.toIso8601String().substring(11, 19);
    return '[$time] $label: $details';
  }
}

ContentType _contentTypeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return ContentType.html;
  }
  if (lower.endsWith('.js')) {
    return ContentType('application', 'javascript');
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) {
    return ContentType('application', 'json');
  }
  if (lower.endsWith('.png')) {
    return ContentType('image', 'png');
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }
  return ContentType.binary;
}

enum _ServeMode { assets, directory }
