import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../constants/app_constants.dart';

/// Global friends list provider
///
/// Merges Firestore chunks to stay within the 'whereIn' limit of 10.
final friendsProvider = StreamProvider<List<UserModel>>((ref) {
  final userAsync = ref.watch(currentUserProvider);

  return userAsync.when(
    data: (user) {
      if (user == null || user.friendIds.isEmpty) {
        return Stream.value([]);
      }

      final friendIds = user.friendIds;

      // Split into chunks of 10 for Firestore 'whereIn' limit
      final chunks = <List<String>>[];
      for (var i = 0; i < friendIds.length; i += 10) {
        chunks.add(
          friendIds.sublist(
            i,
            i + 10 > friendIds.length ? friendIds.length : i + 10,
          ),
        );
      }

      final streams = chunks.map((chunk) {
        return FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map((doc) => UserModel.fromFirestore(doc))
                  .toList(),
            );
      }).toList();

      if (streams.isEmpty) return Stream.value([]);
      if (streams.length == 1) return streams.first;

      return CombineLatestStream.list(streams)
          .map((listOfLists) => listOfLists.expand((batch) => batch).toList())
          .startWith([]);
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
