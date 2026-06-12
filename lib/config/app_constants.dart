class AppConstants {
  // App info
  static const String appName = 'Digibox Rider Tracker';
  static const String version = '1.0.6';

  // Location tracking settings - ADAPTIVE & SMART
  static const int trackingIntervalMovingSeconds = 30;   // Track every 30s when MOVING
  static const int trackingIntervalStoppedSeconds = 60;  // Track every 1min when STOPPED
  static const int batchUploadIntervalMinutes = 2;       // Upload batch every 2 minutes
  static const int backgroundIntervalMinutes = 5;        // Background tracking fallback

  // Movement detection thresholds
  static const double movementSpeedThreshold = 0.5;      // m/s (~1.8 km/h) - if speed > this, rider is MOVING
  static const double movementDistanceThreshold = 10.0;  // meters - if moved > this, rider is MOVING
  static const double stoppedDriftThreshold = 5.0;       // meters - ignore GPS drift when stopped

  // GPS quality thresholds - STRICT for accuracy
  static const double maxGpsAccuracyMeters = 20.0; // STRICT: Only accept GPS accuracy < 20m
  static const double maxJumpDistanceMeters = 700.0; // STRICT: Reject jumps > 700m (max 80km/h for 30s)
  static const double maxSpeedKmh = 100.0; // STRICT: Reject if speed > 100 km/h (unrealistic for delivery)

  // Online/Offline thresholds
  static const int onlineThresholdMinutes = 10; // Rider considered offline after 10 min no data
  static const int sessionTimeoutMinutes = 10; // Auto-close sessions after 10 min no data

  // Data retention
  static const int dataRetentionDays = 7; // Keep local data for 7 days

  // Storage keys
  static const String keyAuthToken = 'auth_token';
  static const String keyRiderId = 'rider_id';
  static const String keyRiderName = 'rider_name';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyActiveDutySessionId = 'active_duty_session_id';
  static const String keyActiveDutySession = 'active_duty_session'; // Full session data
  static const String keyDutyStartedAt = 'duty_started_at'; // ISO string

  // Pending sync keys (offline-first)
  static const String keyPendingStopSync = 'pending_stop_sync';
  static const String keyPendingStopSessionId = 'pending_stop_session_id';
  static const String keyPendingStopTime = 'pending_stop_time';
  static const String keyLastEndedSession = 'last_ended_session'; // For reference after offline stop

  // Database
  static const String dbName = 'rider_tracker.db';
  static const int dbVersion = 1; // Version 1 (geofence feature removed)

  // WorkManager task
  static const String locationTaskName = 'location_tracking_task';
}
