/// Route names for navigation
class AppRoutes {
  AppRoutes._();

  // Auth Routes
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';

  // Permission Routes
  static const String permissionMic = '/permission/microphone';
  static const String permissionNotification = '/permission/notification';
  static const String permissionContacts = '/permission/contacts';
  static const String permissionCamera = '/permission/camera';
  static const String widgetSetup = '/widget-setup';

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
