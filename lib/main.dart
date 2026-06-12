import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/duty_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/location_status_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_scaffold.dart';
import 'services/background_service.dart';
import 'services/foreground_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service
  final backgroundService = BackgroundService();
  backgroundService.initialize();

  // Initialize foreground service
  await ForegroundLocationService.initialize();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // FCM service disabled (backend endpoint not implemented)
  // Initialize FCM service (optional - requires google-services.json)
  // try {
  //   final fcmService = FCMService();
  //   await fcmService.initialize();
  // } catch (e) {
  //   debugPrint('Firebase not configured: $e');
  //   // Continue without push notifications
  // }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DutyProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => LocationStatusProvider()),
      ],
      child: MaterialApp(
        title: 'Digibox Rider Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize auth provider
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();

    // Initialize duty provider if logged in
    if (authProvider.isLoggedIn) {
      final dutyProvider = Provider.of<DutyProvider>(context, listen: false);
      await dutyProvider.initialize(authProvider.apiService);

      // Set up connectivity provider for auto-sync (duty + locations)
      final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
      connectivityProvider.setDependencies(dutyProvider, authProvider.apiService, LocationService());
    }

    // Navigate to appropriate screen
    if (!mounted) return;

    if (authProvider.isLoggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.delivery_dining,
                size: 80,
                color: Colors.white,
              ),
              SizedBox(height: 16),
              Text(
                'Digibox Rider',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
