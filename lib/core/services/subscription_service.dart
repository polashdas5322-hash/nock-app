import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';

/// Subscription Service
/// 
/// Manages RevenueCat integration for VIBE+ subscriptions.
class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Initialize RevenueCat
  Future<void> initialize() async {
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info);

    PurchasesConfiguration? configuration;

    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(AppConstants.rcGoogleApiKey);
    } else if (Platform.isIOS) {
      configuration = PurchasesConfiguration(AppConstants.rcAppleApiKey);
    }

    if (configuration != null) {
      // 🛡️ STABILITY FIX: Don't configure if API Key is empty (prevents Native crash/exception)
      if (configuration.apiKey.isEmpty) {
        debugPrint('⚠️ SubscriptionService: RevenueCat API Key is missing. Subscription features will be disabled.');
        return;
      }
      
      try {
        await Purchases.configure(configuration);
        _setupCustomerInfoListener();
      } catch (e) {
        debugPrint('❌ SubscriptionService: Failed to configure RevenueCat: $e');
      }
    }
  }

  /// Listen for customer info changes (e.g. successful purchase, expiration)
  void _setupCustomerInfoListener() {
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _syncEntitlementStatus(customerInfo);
    });
  }

  /// Restore purchases - Mandatory for App Store compliance
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      return await _syncEntitlementStatus(customerInfo);
    } on PlatformException catch (e) {
      debugPrint('SubscriptionService: Restore error: ${e.message}');
      rethrow;
    }
  }

  /// Purchase a specific VIBE+ package (Weekly, Monthly, or Annual)
  Future<bool> purchasePackage(String productId) async {
    try {
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        // Find the specific product requested
        final package = offerings.current!.availablePackages.firstWhere(
          (pkg) => pkg.storeProduct.identifier == productId,
          orElse: () => offerings.current!.availablePackages.first,
        );

        debugPrint('SubscriptionService: Attempting purchase of ${package.storeProduct.identifier}');
        
        // 1. Attempt the purchase
        final PurchaseResult result = await Purchases.purchase(
          PurchaseParams.package(package),
        );

        // 2. Sync and return
        return await _syncEntitlementStatus(result.customerInfo);
      } else {
        debugPrint('SubscriptionService: No offerings available');
        return false;
      }
    } on PlatformException catch (e) {
      // 3. Handle User Cancellation
      // In Flutter, cancellation throws a PlatformException
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('SubscriptionService: Purchase cancelled by user');
        return false; // Safe exit, no crash
      }
      
      // 4. Handle actual errors (network, invalid credentials, etc.)
      debugPrint('SubscriptionService: Purchase error: ${e.message}');
      rethrow;
    }
  }

  /// Sync entitlement status with Firestore Firestore
  Future<bool> _syncEntitlementStatus(CustomerInfo customerInfo) async {
    final isPremium = customerInfo.entitlements.all[AppConstants.premiumEntitlementId]?.isActive ?? false;
    
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection(AppConstants.usersCollection).doc(user.uid).update({
          'isPremium': isPremium,
        });
        debugPrint('SubscriptionService: Synced premium status ($isPremium) for user ${user.uid}');
      } catch (e) {
        debugPrint('SubscriptionService: Error syncing with Firestore: $e');
      }
    }
    
    return isPremium;
  }
}

/// Subscription Service Provider
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});
