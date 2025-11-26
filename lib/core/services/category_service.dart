// lib/core/services/category_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  // Cache for categories to avoid repeated Firestore calls
  Map<String, String> _categoryCache = {};

  /// Get category name from category ID
  Future<String> getCategoryName(String categoryId) async {
    if (_categoryCache.containsKey(categoryId)) {
      return _categoryCache[categoryId]!;
    }

    try {
      final doc = await _firestore.collection('workCategories').doc(categoryId).get();
      if (doc.exists) {
        final categoryName = doc.data()?['name'] ?? 'Unknown Category';
        _categoryCache[categoryId] = categoryName;
        return categoryName;
      }
      return 'Unknown Category';
    } catch (e) {
      debugPrint('Error fetching category name: $e');
      return 'Unknown Category';
    }
  }

  /// Get all categories for mapping
  Future<Map<String, String>> getAllCategories() async {
    try {
      final snapshot = await _firestore.collection('workCategories').get();
      final categories = <String, String>{};

      for (final doc in snapshot.docs) {
        categories[doc.id] = doc.data()['name'] ?? 'Unknown Category';
      }

      _categoryCache = categories;
      return categories;
    } catch (e) {
      debugPrint('Error fetching all categories: $e');
      return {};
    }
  }

  /// Clear cache (useful for testing or when categories change)
  void clearCache() {
    _categoryCache.clear();
  }
}