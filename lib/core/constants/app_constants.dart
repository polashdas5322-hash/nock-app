/// App-wide constants for Vibe
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Nock';
  static const String appVersion = '1.0.0';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String squadsCollection = 'squads';
  static const String messagesCollection = 'messages';
  static const String vibesCollection = 'vibes';
  static const String friendshipsCollection = 'friendships';

  // Storage Paths
  static const String audioStoragePath = 'audio';
  static const String imagesStoragePath = 'images';
  static const String videosStoragePath = 'videos';
  static const String avatarsStoragePath = 'avatars';

  // Limits
  static const int maxVoiceNoteDuration = 15; // seconds
  static const int maxSquadMembers = 20;
  static const int freeHistoryHours = 24;
  static const int maxFriendsCount = 20;
  static const int reverseTrialDays = 7;

  // Audio Settings
  static const int audioSampleRate = 44100;
  static const int audioBitRate = 128000;

  // Widget
  static const String widgetId = 'vibe_widget';
  static const String iosAppGroupId = 'group.com.vibe.app';

  // Subscription Tiers
  static const String subscriptionMonthlyId = 'vibe_plus_monthly';
  static const String subscriptionWeeklyId = 'vibe_plus_weekly';
  static const String subscriptionAnnualId = 'vibe_plus_annual';

  static const String premiumEntitlementId = 'premium_entitlement';

  static const double priceMonthly = 4.99;
  static const double priceWeekly = 0.99;
  static const double priceAnnual = 29.99;

  // RevenueCat Keys (Provide via --dart-define or secure config)
  static const String rcAppleApiKey = String.fromEnvironment(
    'RC_APPLE_API_KEY',
    defaultValue: '',
  );
  static const String rcGoogleApiKey = String.fromEnvironment(
    'RC_GOOGLE_API_KEY',
    defaultValue: '',
  );

  // AI Keys (Provide via --dart-define or secure config)
  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  // Time Values
  static const int widgetUpdateIntervalMinutes = 15;

  // Animation Durations
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animVerySlow = Duration(milliseconds: 800);

  // UI Values
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXLarge = 24.0;
  static const double borderRadiusCircle = 100.0;

  // Glassmorphism
  static const double glassBlurAmount = 5.0;
  static const double glassOpacity = 0.1;
}
