import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

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
  final ImagePicker _imagePicker = ImagePicker();

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
            _injectFileInputHandler();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              hasError = true;
              errorMessage: 'Error ${error.errorCode}: ${error.description}';
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      );

    // Add JavaScript channel for file handling
    controller.addJavaScriptChannel(
      'FileUploadHandler',
      onMessageReceived: (JavaScriptMessage message) {
        _handleFileUpload();
      },
    );

    // Request all necessary permissions at app startup
    _requestAllPermissions();

    // Load URL with retry mechanism
    _loadWebsite();
  }

  Future<void> _injectFileInputHandler() async {
    const String jsCode = '''
      (function() {
        // Find all file input elements
        const fileInputs = document.querySelectorAll('input[type="file"]');
        
        fileInputs.forEach(function(input) {
          // Remove existing click handlers
          input.onclick = null;
          
          // Add our custom click handler
          input.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            
            // Call Flutter to handle file upload
            if (window.FileUploadHandler) {
              window.FileUploadHandler.postMessage('fileUploadRequested');
            }
          });
        });
        
        // Also handle dynamically added file inputs
        const observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              if (node.nodeType === 1) { // Element node
                const newFileInputs = node.querySelectorAll ? node.querySelectorAll('input[type="file"]') : [];
                newFileInputs.forEach(function(input) {
                  input.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    if (window.FileUploadHandler) {
                      window.FileUploadHandler.postMessage('fileUploadRequested');
                    }
                  });
                });
              }
            });
          });
        });
        
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    ''';

    await controller.runJavaScript(jsCode);
  }

  Future<void> _handleFileUpload() async {
    // Show dialog to choose between camera and gallery
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('तस्विर छान्नुहोस्'),
          content: const Text('तपाईं कहाँबाट तस्विर छान्न चाहनुहुन्छ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('camera'),
              child: const Text('क्यामेरा'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('gallery'),
              child: const Text('ग्यालेरी'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('रद्द गर्नुहोस्'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      String? filePath;

      switch (result) {
        case 'camera':
          filePath = await _pickFromCamera();
          break;
        case 'gallery':
          filePath = await _pickFromGallery();
          break;
      }

      if (filePath != null) {
        await _uploadFileToWebView(filePath);
      }
    }
  }

  Future<String?> _pickFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
      return image?.path;
    } catch (e) {
      _showErrorDialog('क्यामेराबाट तस्विर लिन सकिएन');
      return null;
    }
  }

  Future<String?> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      return image?.path;
    } catch (e) {
      _showErrorDialog('ग्यालेरीबाट तस्विर छान्न सकिएन');
      return null;
    }
  }

  Future<void> _uploadFileToWebView(String filePath) async {
    try {
      final File file = File(filePath);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final fileName = file.path.split('/').last;

      // Get file MIME type
      String mimeType = 'image/jpeg';
      if (fileName.toLowerCase().endsWith('.png')) {
        mimeType = 'image/png';
      } else if (fileName.toLowerCase().endsWith('.gif')) {
        mimeType = 'image/gif';
      } else if (fileName.toLowerCase().endsWith('.webp')) {
        mimeType = 'image/webp';
      }

      final String jsCode = '''
        (function() {
          const fileInput = document.querySelector('input[type="file"]');
          if (fileInput) {
            // Create a new File object from base64 data
            const byteCharacters = atob('$base64String');
            const byteNumbers = new Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
              byteNumbers[i] = byteCharacters.charCodeAt(i);
            }
            const byteArray = new Uint8Array(byteNumbers);
            const file = new File([byteArray], '$fileName', { type: '$mimeType' });
            
            // Create a FileList-like object
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            
            // Set the files property
            fileInput.files = dataTransfer.files;
            
            // Trigger change event
            const event = new Event('change', { bubbles: true });
            fileInput.dispatchEvent(event);
          }
        })();
      ''';

      await controller.runJavaScript(jsCode);

    } catch (e) {
      _showErrorDialog('फाइल अपलोड गर्न सकिएन');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('त्रुटि'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ठिक छ'),
            ),
          ],
        );
      },
    );
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
          title: const Text('अनुमति आवश्यक'),
          content: Text('यो एप्लिकेसनले $permissionName को अनुमति चाहिन्छ। कृपया सेटिङमा गएर अनुमति दिनुहोस्।'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('रद्द गर्नुहोस्'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('सेटिङ खोल्नुहोस्'),
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