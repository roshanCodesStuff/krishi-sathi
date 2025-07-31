import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'कृषि साथी',
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();

    // Initialize the WebViewController
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36')
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              hasError = true;
              errorMessage = 'Error ${error.errorCode}: ${error.description}';
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      );

    // Request all necessary permissions at app startup
    _requestAllPermissions();

    // Load URL with retry mechanism
    _loadWebsite();
  }

  Future<void> _requestAllPermissions() async {
    try {
      // Request camera permission
      await Permission.camera.request();

      // Request storage permissions based on Android version
      if (Platform.isAndroid) {
        final androidInfo = await _getAndroidVersion();

        if (androidInfo >= 33) {
          // Android 13+ (API 33+) - Request granular media permissions
          await Permission.photos.request();
          await Permission.videos.request();
        } else if (androidInfo >= 30) {
          // Android 11+ (API 30+) - Request manage external storage if needed
          await Permission.storage.request();

          // For accessing all files, you might need MANAGE_EXTERNAL_STORAGE
          await Permission.manageExternalStorage.request();
        } else {
          // Android 10 and below - Request traditional storage permissions
          await Permission.storage.request();
        }
      }

      // Request microphone permission (if your app needs it for video recording)
      await Permission.microphone.request();

    } catch (e) {
      // Handle permission request errors silently
    }
  }

  Future<int> _getAndroidVersion() async {
    // This is a simplified way to get Android version
    // In a real app, you might want to use device_info_plus package
    try {
      return 33; // Assume recent Android version for now
    } catch (e) {
      return 28; // Fallback to older version
    }
  }



  void _showPermissionDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('अनुमति आवश्यक'),
          content: Text('यो एप्लिकेसनले $permissionName को अनुमति चाहिन्छ। कृपया सेटिङमा गएर अनुमति दिनुहोस्।'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('रद्द गर्नुहोस्'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: Text('सेटिङ खोल्नुहोस्'),
            ),
          ],
        );
      },
    );
  }

  void _loadWebsite() {
    controller.loadRequest(Uri.parse('https://agro-connect-app.vercel.app'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: hasError
                ? _buildErrorWidget()
                : WebViewWidget(controller: controller),
          ),
          if (isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'कृषि साथी लोड हुँदैछ...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 20),
            const Text(
              'वेबसाइट लोड गर्न सकिएन',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage.isNotEmpty ? errorMessage : 'इन्टरनेट जडान जाँच गर्नुहोस्',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  hasError = false;
                  isLoading = true;
                });
                _loadWebsite();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('पुनः प्रयास गर्नुहोस्'),
            ),
          ],
        ),
      ),
    );
  }
}