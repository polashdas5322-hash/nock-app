/// Route names for navigation
class AppRoutes {
  AppRoutes._();

  // Auth Routes
  static const String splash = '/';
  static const String welcome = '/welcome';

  // Onboarding Routes (The 4-Stage Flow)
  // 1. Welcome (Hero)
  // 2. Squad (Contacts)
  static const String permissionContacts = '/permission/contacts';
  // 2. Identity (Aura)
  static const String identity = '/onboarding/identity';
  // 3. Magic (Widget)
  static const String widgetSetup = '/widget-setup';

  // Legacy routes removed:
  // - onboarding (Tutorial)
  // - permissionMic (Contextual)
  // - permissionCamera (Contextual)
  // - permissionNotification (Contextual)

  // Main Routes
  static const String home = '/home';
  static const String camera = '/camera';
  static const String squadManager = '/home/squad';
  static const String vault = '/home/vault';
  static const String settings = '/settings';

  // Feature Routes
  static const String player = '/home/player'; // Base path for player
  static const String gallery = '/gallery';
  static const String profile = '/profile';
  static const String addFriend = '/add-friend';
  static const String addFriends = '/home/add-friends';
  static const String subscription = '/home/subscription';
  static const String widgetConfig = '/widget-config';
}
