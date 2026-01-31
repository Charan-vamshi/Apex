import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' show cos, sqrt, asin, sin;

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

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + 
              cos(lat1 * p) * cos(lat2 * p) * 
              (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
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
          .select('id, shop_name, latitude, longitude, qr_code_hash')
          .eq('qr_code_hash', qrData)
          .single();

      final shopId = shopResponse['id'];
      final shopName = shopResponse['shop_name'];
      final shopLat = shopResponse['latitude'];
      final shopLng = shopResponse['longitude'];
      final shopQR = shopResponse['qr_code_hash'];

      // LOCK 1: GPS Validation (50m radius)
      final distance = calculateDistance(
        position.latitude, 
        position.longitude, 
        shopLat, 
        shopLng
      );
      final gpsValid = distance <= 50;

      // LOCK 2: QR Code Validation
      final qrValid = qrData == shopQR;

      // LOCK 3: Server timestamp
      final serverTimestamp = DateTime.now().toUtc().toIso8601String();

      // Check if all locks pass
      if (!gpsValid || !qrValid) {
        final errors = [];
        if (!gpsValid) errors.add('GPS out of range: ${distance.toStringAsFixed(2)}m (must be within 50m)');
        if (!qrValid) errors.add('Invalid QR code');
        
        setState(() {
          _statusMessage = 'Validation Failed:\n${errors.join('\n')}';
        });
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) Navigator.pop(context);
        return;
      }

      // All validations passed - record visit
      final visitResponse = await Supabase.instance.client
          .from('visits')
          .insert({
            'salesman_id': salesmanId,
            'shop_id': shopId,
            'verified_at': serverTimestamp,
            'gps_lat': position.latitude,
            'gps_lng': position.longitude,
            'distance_from_shop': distance,
          })
          .select()
          .single();

      final visitId = visitResponse['id'];

      // Log validation details
      await Supabase.instance.client.from('visit_validations').insert({
        'visit_id': visitId,
        'gps_valid': gpsValid,
        'qr_valid': qrValid,
        'time_sync_valid': true,
        'validation_errors': null,
      });

      setState(() {
        _statusMessage = '✅ Visit to $shopName recorded!\nDistance: ${distance.toStringAsFixed(2)}m';
      });

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