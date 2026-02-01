import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = '${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Apex'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          const Icon(
            Icons.verified_user,
            size: 80,
            color: Colors.blue,
          ),
          const SizedBox(height: 20),
          const Text(
            'Apex Field Force',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Version $_version',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Field force integrity system preventing ghost visits through GPS verification, QR scanning, and server-side timestamps.'),
          ),
          const SizedBox(height: 10),
          const ListTile(
            leading: Icon(Icons.security),
            title: Text('Security Features'),
            subtitle: Text('• GPS Geofencing (50m)\n• Physical QR Code Scan\n• Server-Side Timestamp\n• Photo Verification'),
          ),
          const SizedBox(height: 10),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Developer'),
            subtitle: Text('Charan Vamshi\nGitHub: @Charan-vamshi'),
          ),
          const SizedBox(height: 10),
          const ListTile(
            leading: Icon(Icons.calendar_today),
            title: Text('Released'),
            subtitle: Text('January 2026'),
          ),
          const SizedBox(height: 30),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Built with Flutter & Supabase',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '© 2026 Apex Systems',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}