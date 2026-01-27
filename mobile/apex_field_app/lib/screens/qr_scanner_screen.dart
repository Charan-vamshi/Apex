import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  String? _statusMessage;

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Location services disabled');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Location permission denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'Location permission permanently denied');
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _validateVisit(String qrData, Position position) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Validating visit...';
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      // Get salesman record
      final salesmanResponse = await Supabase.instance.client
          .from('salesmen')
          .select('id')
          .eq('user_id', user.id)
          .single();

      final salesmanId = salesmanResponse['id'];

      // Get shop by QR code
      final shopResponse = await Supabase.instance.client
          .from('shops')
          .select('id, shop_name')
          .eq('qr_code_hash', qrData)
          .single();

      final shopId = shopResponse['id'];
      final shopName = shopResponse['shop_name'];

      // Call validation function
      final response = await Supabase.instance.client.functions.invoke(
        'validate-visit',
        body: {
          'salesmanId': salesmanId,
          'shopId': shopId,
          'qrData': qrData,
          'userLat': position.latitude,
          'userLng': position.longitude,
        },
      );

      if (response.data['success'] == true) {
        setState(() {
          _statusMessage = 'Visit to $shopName recorded successfully!\nDistance: ${response.data['distance']}m';
        });
      } else {
        setState(() {
          _statusMessage = 'Validation failed: ${response.data['errors'].join(', ')}';
        });
      }

      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      setState(() {
        _statusMessage = 'Error: ${error.toString()}';
      });
      await Future.delayed(const Duration(seconds: 3));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? qrData = barcodes.first.rawValue;
    if (qrData == null) return;

    setState(() => _isProcessing = true);

    final position = await _getCurrentLocation();
    if (position == null) {
      setState(() => _isProcessing = false);
      return;
    }

    await _validateVisit(qrData, position);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Shop QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),
          if (_statusMessage != null)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}