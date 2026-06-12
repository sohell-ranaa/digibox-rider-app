import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/installation_location.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/loading/shimmer_loading.dart';

/// Installations screen - list of installation locations
class InstallationsScreen extends StatefulWidget {
  const InstallationsScreen({super.key});

  @override
  State<InstallationsScreen> createState() => _InstallationsScreenState();
}

class _InstallationsScreenState extends State<InstallationsScreen> {

  List<InstallationLocation> _installations = [];
  Position? _currentPosition;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get authenticated API service
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final apiService = authProvider.apiService;

      // Get current location
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
      } catch (e) {
        // Continue without location - will just not show distances
        debugPrint('Could not get location: $e');
      }

      // Get installations from API
      _installations = await apiService.getInstallations();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load installations: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<({InstallationLocation installation, double distance})> _getSortedInstallations() {
    if (_currentPosition == null) {
      return _installations
          .map((i) => (installation: i, distance: 0.0))
          .toList();
    }

    // Calculate distances and sort
    final List<({InstallationLocation installation, double distance})> installationsWithDistance =
        _installations.map((installation) {
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        installation.latitude,
        installation.longitude,
      );
      return (installation: installation, distance: distance);
    }).toList();

    // Sort by distance (nearest first)
    installationsWithDistance.sort((a, b) => a.distance.compareTo(b.distance));

    return installationsWithDistance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Installations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ShimmerList(itemCount: 5);
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.padding),
            Text(
              'Failed to load installations',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.paddingSmall),
            Text(
              _error!,
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.paddingLarge),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_installations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.padding),
            Text(
              'No installations found',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.paddingSmall),
            Text(
              'Installations will appear here once added',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final sortedInstallations = _getSortedInstallations();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.padding),
        itemCount: sortedInstallations.length,
        itemBuilder: (context, index) {
          final item = sortedInstallations[index];
          return _buildInstallationCard(
            item.installation,
            item.distance,
          );
        },
      ),
    );
  }

  Widget _buildInstallationCard(
    InstallationLocation installation,
    double distanceMeters,
  ) {
    final distanceKm = distanceMeters / 1000;
    final isNearby = distanceMeters <= installation.geofenceRadiusMeters;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.padding),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.padding),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isNearby
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                ),
                child: Icon(
                  Icons.location_on,
                  color: isNearby ? AppColors.success : AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: AppSpacing.padding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      installation.name,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      installation.address ?? 'No address',
                      style: AppTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          distanceKm < 1
                              ? '${distanceMeters.toStringAsFixed(0)} m away'
                              : '${distanceKm.toStringAsFixed(1)} km away',
                          style: AppTypography.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isNearby)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingSmall,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall),
                  ),
                  child: Text(
                    'NEARBY',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.paddingSmall),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
