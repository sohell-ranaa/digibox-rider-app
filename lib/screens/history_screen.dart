import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/duty_session.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/simple_card.dart';

/// History screen - view past duty sessions
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {

  List<DutySession> _sessions = [];
  bool _isLoading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Get last 30 days by default, or filter by selected date
      final from = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final to = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);

      final sessions = await authProvider.apiService.getDutyHistory(from: from, to: to);

      // Group sessions by date and merge
      final mergedSessions = _mergeSessionsByDate(sessions);

      setState(() {
        _sessions = mergedSessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // Merge multiple duty sessions from same date into one
  List<DutySession> _mergeSessionsByDate(List<DutySession> sessions) {
    if (sessions.isEmpty) return sessions;

    // Group by date
    final Map<String, List<DutySession>> groupedByDate = {};

    for (final session in sessions) {
      final dateKey = DateFormat('yyyy-MM-dd').format(session.startedAt);
      groupedByDate.putIfAbsent(dateKey, () => []);
      groupedByDate[dateKey]!.add(session);
    }

    // Merge sessions for each date
    final List<DutySession> mergedSessions = [];

    for (final entry in groupedByDate.entries) {
      final dateSessions = entry.value;

      if (dateSessions.length == 1) {
        // Only one session for this date - keep as is
        mergedSessions.add(dateSessions[0]);
      } else {
        // Multiple sessions - merge them
        dateSessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));

        final earliestStart = dateSessions.first.startedAt;
        final latestEnd = dateSessions.last.endedAt ?? DateTime.now();

        final totalDuration = dateSessions.fold<int>(
          0,
          (sum, session) => sum + (session.totalDurationMinutes ?? 0),
        );

        final totalDistance = dateSessions.fold<double>(
          0.0,
          (sum, session) => sum + (session.totalDistanceKm ?? 0.0),
        );

        final totalStops = dateSessions.fold<int>(
          0,
          (sum, session) => sum + session.totalStops,
        );

        // Create merged session
        mergedSessions.add(DutySession(
          id: dateSessions.first.id,
          riderId: dateSessions.first.riderId,
          startedAt: earliestStart,
          endedAt: latestEnd,
          status: 'completed',
          totalDurationMinutes: totalDuration,
          totalDistanceKm: totalDistance,
          totalStops: totalStops,
        ));
      }
    }

    // Sort by date descending (newest first)
    mergedSessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return mergedSessions;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Duty History',
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildDateSelector(),
            Expanded(child: _buildSessionsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.padding),
      child: SimpleCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(_selectedDate),
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              onPressed: _selectDate,
              icon: const Icon(Icons.edit_calendar, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSessionsList() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.padding),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.padding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: AppSpacing.padding),
              Text(
                'Failed to load history',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.paddingSmall),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.paddingLarge),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.history,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.padding),
            Text(
              'No duty sessions found',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.paddingSmall),
            Text(
              'Your duty history will appear here',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.padding),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(_sessions[index]);
        },
      ),
    );
  }

  Widget _buildSessionCard(DutySession session) {
    // Format duration
    final totalMinutes = session.totalDurationMinutes ?? 0;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final durationText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    // Format distance
    final distance = session.totalDistanceKm?.toStringAsFixed(1) ?? '0.0';

    return SimpleCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  DateFormat('EEEE, MMMM d, y').format(session.startedAt),
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSessionStat(
                  Icons.access_time,
                  'Duration',
                  durationText,
                ),
              ),
              Expanded(
                child: _buildSessionStat(
                  Icons.route,
                  'Distance',
                  '$distance km',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStat(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
