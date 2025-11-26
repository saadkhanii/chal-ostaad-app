// lib/features/client/screens/post_job_screen.dart

import 'package:chal_ostaad/core/models/job_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:logger/Logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/sizes.dart';
import '../../../shared/widgets/Cbutton.dart';
import '../../../shared/widgets/CtextField.dart';

class Category {
  final String id;
  final String name;

  Category({required this.id, required this.name});
}

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedCategoryId;
  bool _isLoading = false;
  final Logger _logger = Logger();

  List<Category> _categories = [];
  bool _isFetchingCategories = true;
  String? _clientId;

  @override
  void initState() {
    super.initState();
    _loadClientId();
    _fetchCategories();
  }

  // FIXED: Load client ID from SharedPreferences to ensure consistency
  Future<void> _loadClientId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUid = prefs.getString('user_uid');

      if (userUid != null) {
        setState(() {
          _clientId = userUid;
        });
        _logger.i('Loaded client ID from SharedPreferences: $userUid');
      } else {
        _logger.w('No user UID found in SharedPreferences');
      }
    } catch (e) {
      _logger.e('Error loading client ID: $e');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('workCategories')
          .where('status', isEqualTo: 'active')
          .get();

      final categoriesData = snapshot.docs.map((doc) {
        return Category(
          id: doc.id,
          name: doc.data()['name'] ?? 'Unnamed Category',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _categories = categoriesData;
          _isFetchingCategories = false;
        });
      }
      _logger.i('Successfully fetched ${_categories.length} active categories.');
    } catch (e) {
      _logger.e('Error fetching categories: $e');
      if (mounted) {
        setState(() {
          _isFetchingCategories = false;
        });
        _showErrorMessage('Could not load categories. Please try again.');
      }
    }
  }

  // FIXED: Updated job posting with better error handling and client ID consistency
  Future<void> _handlePostJob() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedCategoryId == null) {
      _showErrorMessage('Please select a job category.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // FIXED: Use client ID from SharedPreferences OR try to get from auth as fallback
      String? clientIdToUse = _clientId;

      if (clientIdToUse == null) {
        _logger.w('No client ID from SharedPreferences, trying Firebase Auth...');
        final user = FirebaseAuth.instanceFor(app: Firebase.app('client')).currentUser;
        if (user == null) {
          throw Exception('You are not logged in. Please log in again.');
        }
        clientIdToUse = user.uid;
        _logger.i('Using client ID from Firebase Auth: $clientIdToUse');
      } else {
        _logger.i('Using client ID from SharedPreferences: $clientIdToUse');
      }

      // Find the category name from the selected ID
      final selectedCategory = _categories.firstWhere(
              (cat) => cat.id == _selectedCategoryId,
          orElse: () => Category(id: '', name: 'Unknown Category')
      );

      if (selectedCategory.id.isEmpty) {
        throw Exception('Selected category not found.');
      }

      final newJob = JobModel(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: selectedCategory.name,
        clientId: clientIdToUse!, // Use the consistent client ID
        createdAt: Timestamp.now(),
        status: 'open',
      );

      _logger.i('Posting job with data: ${newJob.toJson()}');

      // FIXED: Add to Firestore and wait for completion
      final docRef = await FirebaseFirestore.instance
          .collection('jobs')
          .add(newJob.toJson());

      _logger.i('Successfully posted job with ID: ${docRef.id} for client: $clientIdToUse');

      // FIXED: Verify the job was actually saved
      final savedJob = await docRef.get();
      if (savedJob.exists) {
        _logger.i('Job verified in Firestore: ${savedJob.id}');
        _showSuccessMessage('Job posted successfully!');

        if (mounted) {
          Navigator.pop(context); // Go back to the dashboard
        }
      } else {
        throw Exception('Job was not saved properly to Firestore.');
      }

    } on FirebaseException catch (e) {
      _logger.e('Firebase error posting job: ${e.code} - ${e.message}');
      _showErrorMessage('Firebase error: ${e.message ?? 'Failed to post job'}');
    } on Exception catch (e) {
      _logger.e('Error posting job: $e');
      _showErrorMessage('Failed to post job: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post a New Job'),
        centerTitle: true,
        backgroundColor: CColors.primary,
        foregroundColor: CColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(CSizes.defaultSpace),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Fill in the details below',
                  style: Theme.of(context).textTheme.titleLarge
              ),
              const SizedBox(height: CSizes.spaceBtwSections),

              // Job Title
              CTextField(
                label: 'Job Title',
                hintText: 'e.g., Fix leaky kitchen sink',
                controller: _titleController,
                validator: (value) => value == null || value.isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // Job Description
              CTextField(
                label: 'Job Description',
                hintText: 'Describe the task in detail...',
                controller: _descriptionController,
                maxLines: 5,
                validator: (value) => value == null || value.isEmpty ? 'Description is required' : null,
              ),
              const SizedBox(height: CSizes.spaceBtwItems),

              // Category Dropdown
              _buildCategoryDropdown(isDark),

              // FIXED: Added debug info for client ID
              if (_clientId != null) ...[
                const SizedBox(height: CSizes.spaceBtwItems),
                Text(
                  'Client ID: ${_clientId!.substring(0, 8)}...',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: CColors.darkGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: CSizes.spaceBtwSections),

              // Post Job Button
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CButton(
                text: 'Post Job',
                onPressed: _handlePostJob,
                width: double.infinity,
                backgroundColor: CColors.primary,
                foregroundColor: CColors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(bool isDark) {
    return DropdownButtonFormField<String>(
      value: _selectedCategoryId,
      hint: Text(_isFetchingCategories ? 'Loading categories...' : 'Select a category'),
      isExpanded: true,
      decoration: InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(CSizes.borderRadiusMd)),
          prefixIcon: const Icon(Icons.category_outlined),
          labelStyle: TextStyle(color: isDark ? CColors.light : CColors.dark)
      ),
      onChanged: _isFetchingCategories ? null : (newValue) {
        setState(() {
          _selectedCategoryId = newValue;
        });
      },
      items: _categories.map((Category category) {
        return DropdownMenuItem<String>(
          value: category.id,
          child: Text(category.name),
        );
      }).toList(),
      validator: (value) => value == null ? 'Category is required' : null,
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}