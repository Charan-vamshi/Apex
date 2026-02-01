import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin, sin;

class ShopListScreen extends StatefulWidget {
  const ShopListScreen({super.key});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  List<Map<String, dynamic>> _shops = [];
  Position? _currentPosition;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadShopsAndLocation();
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + 
              cos(lat1 * p) * cos(lat2 * p) * 
              (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  Future<void> _loadShopsAndLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _currentPosition = await Geolocator.getCurrentPosition();

      final shopsResponse = await Supabase.instance.client
          .from('shops')
          .select('*')
          .eq('is_active', true)
          .order('shop_name');

      _shops = List<Map<String, dynamic>>.from(shopsResponse);

      for (var shop in _shops) {
        final distance = calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          shop['latitude'],
          shop['longitude'],
        );
        shop['distance'] = distance;
      }

      _shops.sort((a, b) => a['distance'].compareTo(b['distance']));

      setState(() => _isLoading = false);
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Shops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShopsAndLocation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadShopsAndLocation,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _shops.isEmpty
                  ? const Center(child: Text('No shops available'))
                  : ListView.builder(
                      itemCount: _shops.length,
                      itemBuilder: (context, index) {
                        final shop = _shops[index];
                        final distance = shop['distance'] ?? 0.0;
                        final isNearby = distance <= 50;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isNearby ? Colors.green : Colors.orange,
                              child: Icon(
                                isNearby ? Icons.location_on : Icons.location_off,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              shop['shop_name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (shop['address'] != null)
                                  Text(shop['address']),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDistance(distance),
                                  style: TextStyle(
                                    color: isNearby ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            trailing: isNearby
                                ? const Chip(
                                    label: Text('IN RANGE', style: TextStyle(fontSize: 10)),
                                    backgroundColor: Colors.green,
                                    labelStyle: TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
    );
  }
}