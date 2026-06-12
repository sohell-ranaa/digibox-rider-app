import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/connectivity_provider.dart';
import '../providers/duty_provider.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

/// Main scaffold with bottom navigation
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  bool _wasOnline = false;

  // Navigation screens
  final List<Widget> _screens = [
    const DashboardScreen(),
    const MapScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    // Listen to connectivity changes and trigger sync when back online
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
      _wasOnline = connectivityProvider.isOnline;

      // Add listener to detect connectivity changes
      connectivityProvider.addListener(_onConnectivityChanged);
    });
  }

  void _onConnectivityChanged() {
    final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
    final isOnline = connectivityProvider.isOnline;

    // If we just came back online (was offline, now online)
    if (!_wasOnline && isOnline) {
      debugPrint('🔄 [MainScaffold] Connectivity restored, triggering sync...');
      _triggerSync();
    }

    _wasOnline = isOnline;
  }

  Future<void> _triggerSync() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final dutyProvider = Provider.of<DutyProvider>(context, listen: false);

      // Trigger sync of pending location data
      await dutyProvider.syncPendingData(authProvider.apiService);

      // Show success snackbar if there was pending data
      final pendingCount = await dutyProvider.getPendingSyncCount();
      if (pendingCount == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All location data synced successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('🔄 [MainScaffold] Error during auto-sync: $e');
    }
  }

  @override
  void dispose() {
    // Remove connectivity listener
    final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
    connectivityProvider.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
