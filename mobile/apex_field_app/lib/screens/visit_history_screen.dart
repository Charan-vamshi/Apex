import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class VisitHistoryScreen extends StatefulWidget {
  const VisitHistoryScreen({super.key});

  @override
  State<VisitHistoryScreen> createState() => _VisitHistoryScreenState();
}

class _VisitHistoryScreenState extends State<VisitHistoryScreen> {
  List<Map<String, dynamic>> _visits = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final salesmanResponse = await Supabase.instance.client
          .from('salesmen')
          .select('id')
          .eq('user_id', user.id)
          .single();

      final salesmanId = salesmanResponse['id'];

      final visitsResponse = await Supabase.instance.client
          .from('visits')
          .select('*, shops(shop_name, address)')
          .eq('salesman_id', salesmanId)
          .order('verified_at', ascending: false);

      setState(() {
        _visits = List<Map<String, dynamic>>.from(visitsResponse);
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String timestamp) {
    final dateTime = DateTime.parse(timestamp);
    return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVisits,
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
                        onPressed: _loadVisits,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _visits.isEmpty
                  ? const Center(
                      child: Text('No visits yet. Start visiting shops!'),
                    )
                  : ListView.builder(
                      itemCount: _visits.length,
                      itemBuilder: (context, index) {
                        final visit = _visits[index];
                        final shopName = visit['shops']['shop_name'] ?? 'Unknown Shop';
                        final distance = visit['distance_from_shop']?.toStringAsFixed(1) ?? '0';
                        final timestamp = visit['verified_at'];

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green,
                              child: const Icon(Icons.check, color: Colors.white),
                            ),
                            title: Text(
                              shopName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Distance: ${distance}m'),
                                Text(_formatDateTime(timestamp)),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              // TODO: Show visit details
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}