import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'main.dart';

class ServerService {
  static final ServerService _instance = ServerService._internal();
  factory ServerService() => _instance;
  ServerService._internal();

  HttpServer? _server;
  String? _localIp;
  bool _isRunning = false;
  bool _enabled = false;
  final _portNumber = 6841;
  String? _cachedHtml;

  bool get isRunning => _isRunning;
  bool get enabled => _enabled;
  String? get serverUrl => _localIp != null ? 'http://$_localIp:$_portNumber' : null;

  // Add CORS middleware
  shelf.Middleware _corsMiddleware() {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };

    return (shelf.Handler handler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: headers);
        }

        final response = await handler(request);
        return response.change(headers: {...response.headers, ...headers});
      };
    };
  }

  Future<String> _loadHtmlTemplate() async {
    if (_cachedHtml != null) return _cachedHtml!;
    _cachedHtml = await rootBundle.loadString('assets/web/index.html');
    return _cachedHtml!;
  }

  // Add the missing initializeBackgroundService method
  Future<void> initializeBackgroundService() async {
    try {
      await platform.invokeMethod('startService');
    } catch (e) {
      print('Failed to initialize background service: $e');
    }
  }
 
  Future<void> startServer(List<Todo> todos, String username) async {
    if (_isRunning) return;

    try {
      _localIp = await _findLocalIpAddress();
      if (_localIp == null) {
        throw Exception('Could not determine local IP address');
      }

      final app = Router();

      // API endpoints
      app.get('/api/data', (request) {
        print('API request received. Sending ${todos.length} todos');
        
        final now = DateTime.now().toLocal(); // Get local time
        final data = {
          'username': username,
          'todos': todos.map((t) => t.toJson()).toList(),
          'currentDateTime': now.toString(), // Include local time in response
          'timeZoneName': now.timeZoneName, // Include timezone name
        };
        
        print('Sending data: ${jsonEncode(data)}');

        return shelf.Response.ok(
          jsonEncode(data),
          headers: {
            'content-type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'no-cache',
          },
        );
      });

      // Serve the index.html file from assets
      app.get('/', (request) async {
        try {
          final htmlContent = await _loadHtmlTemplate();
          // Replace UTC placeholder with local time display
          final modifiedHtml = htmlContent.replaceAll(
            'Current Date and Time (UTC):',
            'Current Date and Time:'
          );
          return shelf.Response.ok(
            modifiedHtml,
            headers: {'content-type': 'text/html'},
          );
        } catch (e) {
          print('Error loading index.html: $e');
          return shelf.Response.internalServerError(
            body: 'Error loading index file: $e',
          );
        }
      });

      final handler = shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addMiddleware(_corsMiddleware())
          .addHandler(app);

      _server = await io.serve(handler, _localIp!, _portNumber);
      _isRunning = true;
      print('Server started at: http://$_localIp:$_portNumber');
    } catch (e, stackTrace) {
      print('Failed to start server: $e\n$stackTrace');
      await stopServer();
    }
  }

  Future<void> stopServer() async {
    if (!_isRunning) return;
    
    try {
      await _server?.close();
      _server = null;
      _isRunning = false;
      _localIp = null;
      print('Server stopped');
    } catch (e) {
      print('Error stopping server: $e');
    }
  }

  Future<String?> _findLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && 
              (addr.address.startsWith('192.168.') || 
               addr.address.startsWith('10.') || 
               addr.address.startsWith('172.'))) {
            print('Found local IP: ${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error finding local IP: $e');
    }
    return null;
  }

static final platform = const MethodChannel('com.cyber752.taskify/web_server');

Future<void> startBackgroundService() async {
  try {
    await platform.invokeMethod('startService');
  } catch (e) {
    print('Failed to start background service: $e');
  }
}

Future<void> stopBackgroundService() async {
  try {
    await platform.invokeMethod('stopService');
  } catch (e) {
    print('Failed to stop background service: $e');
  }
}

  // Update toggleServer method
  Future<void> toggleServer(bool value, List<Todo> todos, String username) async {
    _enabled = value;
    if (_enabled) {
      await startBackgroundService();
      await startServer(todos, username);
    } else {
      await stopBackgroundService();
      await stopServer();
    }
  }
}