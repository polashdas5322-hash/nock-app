import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fast_contacts/fast_contacts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/user_model.dart';

/// 🔐 PRIVACY HARDENING: Global Application Pepper
/// 
/// This pepper is used to salt phone number hashes before querying Firestore.
/// This prevents rainbow table attacks on the low-entropy phone number space.
/// 
/// IMPORTANT: This must match the pepper used in:
/// 1. User registration (when storing phoneNumberHash in Firestore)
/// 2. Any Cloud Functions that process phone numbers
/// 
/// In production, this should be loaded from secure storage (--dart-define)
const String _kPhoneNumberPepper = 'nock_contact_discovery_2026_v1';

/// Provider for the ContactsSyncService
final contactsSyncServiceProvider = Provider<ContactsSyncService>((ref) {
  return ContactsSyncService();
});

/// Represents a synced contact - either matched to a Nock user or not.
class SyncedContact {
  final String displayName;
  final String phoneNumber;
  final UserModel? matchedUser; // null if not on Nock
  
  SyncedContact({
    required this.displayName,
    required this.phoneNumber,
    this.matchedUser,
  });
  
  bool get isOnNock => matchedUser != null;
}

/// Service to sync device contacts and find friends on Nock.
/// 
/// Uses [fast_contacts] for optimized contact fetching (~200ms for 1000+ contacts)
/// and matches phone numbers against Firestore users collection.
class ContactsSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch ALL device contacts and mark which ones are on Nock.
  /// 
  /// Returns a list of [SyncedContact] with:
  /// - matchedUser set if they have a Nock account
  /// - matchedUser null if they're not on Nock (invite them!)
  Future<List<SyncedContact>> syncContacts() async {
    // 1. Check permission
    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      final result = await Permission.contacts.request();
      if (!result.isGranted) {
        debugPrint('ContactsSyncService: Permission denied');
        return [];
      }
    }

    // 2. Fetch contacts using fast_contacts
    final contacts = await FastContacts.getAllContacts();
    debugPrint('ContactsSyncService: Fetched ${contacts.length} contacts');

    // 3. Build list of contacts with normalized phone numbers
    final contactsWithPhones = <_ContactWithPhone>[];
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final normalized = _normalizePhoneNumber(phone.number);
        if (normalized.isNotEmpty && normalized.length >= 10) {
          contactsWithPhones.add(_ContactWithPhone(
            displayName: contact.displayName,
            originalPhone: phone.number,
            normalizedPhone: normalized,
          ));
        }
      }
    }

    // Remove duplicates by phone number (keep first occurrence)
    final seenPhones = <String>{};
    final uniqueContacts = <_ContactWithPhone>[];
    for (final c in contactsWithPhones) {
      if (!seenPhones.contains(c.normalizedPhone)) {
        seenPhones.add(c.normalizedPhone);
        uniqueContacts.add(c);
      }
    }
    
    debugPrint('ContactsSyncService: ${uniqueContacts.length} unique contacts');

    if (uniqueContacts.isEmpty) {
      return [];
    }

    // 4. 🔐 PRIVACY FIX: Hash phone numbers before querying Firestore
    // Instead of sending raw phone numbers, we hash them with SHA256 + pepper.
    // Firestore users collection must store 'phoneNumberHash' field.
    final matchedUsers = <String, UserModel>{}; // hash -> user
    const batchSize = 30;
    
    // Create a map: hash -> normalizedPhone (for reverse lookup)
    final hashToPhone = <String, String>{};
    for (final contact in uniqueContacts) {
      final hash = _hashPhoneNumber(contact.normalizedPhone);
      hashToPhone[hash] = contact.normalizedPhone;
    }
    
    final allHashes = hashToPhone.keys.toList();

    for (var i = 0; i < allHashes.length; i += batchSize) {
      final batch = allHashes.skip(i).take(batchSize).toList();
      
      try {
        // 🔐 Query by phoneNumberHash, NOT raw phoneNumber
        final querySnapshot = await _firestore
            .collection('users')
            .where('phoneNumberHash', whereIn: batch)
            .get();

        for (final doc in querySnapshot.docs) {
          final user = UserModel.fromFirestore(doc);
          final userHash = doc.data()['phoneNumberHash'] as String?;
          if (userHash != null && hashToPhone.containsKey(userHash)) {
            // Map back to original normalized phone for result building
            matchedUsers[hashToPhone[userHash]!] = user;
          }
        }
      } catch (e) {
        debugPrint('ContactsSyncService: Batch query error: $e');
      }
    }

    debugPrint('ContactsSyncService: Found ${matchedUsers.length} matches');

    // 5. Build final list with match status
    final result = <SyncedContact>[];
    for (final contact in uniqueContacts) {
      result.add(SyncedContact(
        displayName: contact.displayName,
        phoneNumber: contact.originalPhone,
        matchedUser: matchedUsers[contact.normalizedPhone],
      ));
    }

    // Sort: matches first, then alphabetically
    result.sort((a, b) {
      if (a.isOnNock && !b.isOnNock) return -1;
      if (!a.isOnNock && b.isOnNock) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    return result;
  }

  /// Normalize phone number to a consistent format for matching.
  String _normalizePhoneNumber(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');

    if (!normalized.startsWith('+')) {
      normalized = normalized.replaceAll('+', '');
    }

    if (normalized.length == 10) {
      normalized = '+1$normalized';
    }
    
    if (normalized.length == 11 && normalized.startsWith('1')) {
      normalized = '+$normalized';
    }

    if (normalized.length > 11 && !normalized.startsWith('+')) {
      normalized = '+$normalized';
    }

    return normalized;
  }
  
  /// 🔐 Hash phone number with SHA256 + global pepper
  /// 
  /// This creates a one-way hash that can be used for matching without
  /// exposing raw phone numbers in network traffic or Firestore logs.
  String _hashPhoneNumber(String normalizedPhone) {
    final input = normalizedPhone + _kPhoneNumberPepper;
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

/// Internal helper class
class _ContactWithPhone {
  final String displayName;
  final String originalPhone;
  final String normalizedPhone;
  
  _ContactWithPhone({
    required this.displayName,
    required this.originalPhone,
    required this.normalizedPhone,
  });
}
