import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

void main() => runApp(const UnnatiApp());

const navy = Color(0xFF17345F);
const orange = Color(0xFFE8891B);
const pageGrey = Color(0xFFF2F3F7);
const borderGrey = Color(0xFFD0D3D9);
const textGrey = Color(0xFF667085);
const apiBaseUrl = 'http://127.0.0.1:8000';

class UnnatiApp extends StatelessWidget {
  const UnnatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unnati Career Guidance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: pageGrey,
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
        fontFamily: 'Georgia',
      ),
      home: const AuthPage(),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();

  String activeTab = 'Register';
  String role = 'student';
  String language = 'English';
  bool consent = true;
  bool hidePassword = true;
  bool isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail']?.toString() : null;
      throw Exception(detail ?? 'Request failed (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the server.');
    }
    return decoded;
  }

  Future<void> _submit() async {
    final registering = activeTab == 'Register';
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text;

    if (!_formKey.currentState!.validate()) return;

    if (registering && role == 'student' && !consent) {
      _message(
        'Please agree to share the information required for counselling.',
      );
      return;
    }

    if (isSubmitting) return;

    setState(() => isSubmitting = true);

    try {
      if (registering) {
        late Map<String, dynamic> registration;

        if (role == 'admin') {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('$apiBaseUrl/auth/admin-application'),
          );

          request.fields.addAll({
            'name': _nameController.text.trim(),
            'phone': mobile,
            'password': password,
            'preferred_language': language,
          });

          final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );
          final response = await http.Response.fromStream(streamedResponse);

          dynamic decoded;
          try {
            decoded = jsonDecode(response.body);
          } catch (_) {
            decoded = <String, dynamic>{};
          }

          if (response.statusCode < 200 || response.statusCode >= 300) {
            final detail = decoded is Map
                ? decoded['detail']?.toString()
                : null;
            throw Exception(
              detail ?? 'Admin registration failed (${response.statusCode}).',
            );
          }

          if (decoded is! Map<String, dynamic>) {
            throw Exception('Unexpected response from the server.');
          }

          registration = decoded;
        } else {
          registration = await _postJson('/auth/register', {
            'name': _nameController.text.trim(),
            'phone': mobile,
            'password': password,
            'role': role,
            'preferred_language': language,
            'consent_given': role == 'student' ? consent : false,
          });
        }

        String? childCode = registration['child_code']?.toString();

        if (childCode == null || childCode.isEmpty) {
          final maybeUser = registration['user'];
          if (maybeUser is Map) {
            childCode = maybeUser['child_code']?.toString();
          }
        }

        final login = await _postJson('/auth/login', {
          'phone': mobile,
          'password': password,
        });

        final token = login['access_token']?.toString();
        final userValue = login['user'];
        final user = userValue is Map
            ? Map<String, dynamic>.from(userValue)
            : Map<String, dynamic>.from(login);

        if (token == null || token.isEmpty) {
          throw Exception(
            'Account created, but login token was not returned. Please sign in.',
          );
        }

        if (childCode != null && childCode.isNotEmpty && role == 'student') {
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Student Registered Successfully'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, ${_nameController.text.trim()}!'),
                  const SizedBox(height: 14),
                  const Text(
                    'Your Child Code',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    childCode!,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share this code with your parent so they can link your profile.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Continue to Profile'),
                ),
              ],
            ),
          );
        }

        if (!mounted) return;
        _openNextScreen(token, user, forceProfile: true);
      } else {
        final login = await _postJson('/auth/login', {
          'phone': mobile,
          'password': password,
        });

        final token = login['access_token']?.toString();
        final userValue = login['user'];
        final user = userValue is Map
            ? Map<String, dynamic>.from(userValue)
            : Map<String, dynamic>.from(login);

        if (token == null || token.isEmpty) {
          throw Exception('Login token was not returned.');
        }

        if (!mounted) return;
        _openNextScreen(token, user);
      }
    } catch (error) {
      final errorMessage = error.toString().replaceFirst('Exception: ', '');

      _message(
        errorMessage.contains('SocketException') ||
                errorMessage.contains('ClientException')
            ? 'Cannot connect to Unnati API at $apiBaseUrl. Check that FastAPI is running and CORS is configured.'
            : errorMessage,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _openNextScreen(
    String token,
    Map<String, dynamic> user, {
    bool forceProfile = false,
  }) {
    final completed = user['profile_completed'] == true;
    final userRole = (user['role'] ?? role).toString().toLowerCase();
    final name = (user['name'] ?? _nameController.text.trim()).toString();
    if (forceProfile || !completed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ProfileCreationPage(token: token, user: user, displayName: name),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardPage(
            token: token,
            user: user,
            role: userRole,
            displayName: name,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registering = activeTab == 'Register';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _languageBar(),
                    _portalHeader(),
                    const StepNavigation(activeStep: 0),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _authCard(registering),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  Widget _authCard(bool registering) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderGrey),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [_tabButton('Sign In'), _tabButton('Register')],
            ),
            const SizedBox(height: 26),
            Text(
              registering ? 'Create your Unnati account' : 'Sign in to Unnati',
              style: const TextStyle(
                color: navy,
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Container(height: 3, color: orange),
            const SizedBox(height: 25),
            if (registering) ...[
              _fieldLabel('Register As'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: _inputDecoration('Select account type'),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'parent', child: Text('Parent')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => role = value);
                },
              ),
              const SizedBox(height: 14),
              _fieldLabel('Full Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('Enter your full name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter your full name'
                    : null,
              ),
              const SizedBox(height: 14),
            ],
            _fieldLabel('Mobile Number'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: _inputDecoration(
                'Enter 10-digit mobile number',
              ).copyWith(counterText: ''),
              validator: (value) =>
                  value == null ||
                      !RegExp(r'^[6-9]\d{9}$').hasMatch(value.trim())
                  ? 'Enter a valid 10-digit mobile number'
                  : null,
            ),
            const SizedBox(height: 14),
            _fieldLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: hidePassword,
              decoration: _inputDecoration('Enter password').copyWith(
                suffixIcon: IconButton(
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                  icon: Icon(
                    hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => value == null || value.length < 8
                  ? 'Password must contain at least 8 characters'
                  : null,
            ),
            const SizedBox(height: 14),
            _fieldLabel('Preferred Language'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: language,
              decoration: _inputDecoration('Select preferred language'),
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'मराठी', child: Text('मराठी')),
                DropdownMenuItem(value: 'हिन्दी', child: Text('हिन्दी')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => language = value);
              },
            ),

            if (registering && role == 'student') ...[
              const SizedBox(height: 18),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: consent,
                activeColor: navy,
                onChanged: (value) => setState(() => consent = value ?? false),
                title: const Text(
                  'I agree to share information required for career counselling.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        registering ? 'Register' : 'Login & Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String title) {
    final selected = activeTab == title;
    return OutlinedButton(
      onPressed: () => setState(() => activeTab = title),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? navy : const Color(0xFFF0F2F6),
        foregroundColor: selected ? Colors.white : Colors.black87,
        side: BorderSide(color: selected ? navy : const Color(0xFFD9DDE5)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _languageBar() => Container(
    width: double.infinity,
    color: navy,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    child: Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _languageLink('English'),
        const Text('|', style: TextStyle(color: Colors.white70)),
        _languageLink('मराठी'),
        const Text('|', style: TextStyle(color: Colors.white70)),
        InkWell(
          onTap: () => _message('Accessibility options'),
          child: const Text(
            'Accessibility',
            style: TextStyle(
              color: Colors.white,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _languageLink(String value) => InkWell(
    onTap: () => setState(() => language = value),
    child: Text(
      value,
      style: TextStyle(
        color: Colors.white,
        fontWeight: language == value ? FontWeight.bold : FontWeight.normal,
        decoration: TextDecoration.underline,
      ),
    ),
  );

  Widget _portalHeader() => const PortalHeader();

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xFF262626),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: borderGrey),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: borderGrey),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: navy, width: 1.5),
    ),
  );
}

class ProfileCreationPage extends StatefulWidget {
  const ProfileCreationPage({
    super.key,
    required this.token,
    required this.user,
    required this.displayName,
  });

  final String token;
  final Map<String, dynamic> user;
  final String displayName;

  @override
  State<ProfileCreationPage> createState() => _ProfileCreationPageState();
}

class _ProfileCreationPageState extends State<ProfileCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final _education = TextEditingController();
  String _casteCategory = 'OBC';
  String _casteCertificateStatus = 'Not available';
  final _marks = TextEditingController();
  final _interests = TextEditingController();
  final _skills = TextEditingController();
  final _location = TextEditingController();
  final _aspirations = TextEditingController();
  final _family = TextEditingController();
  // Parent-only fields
  final _parentEducation = TextEditingController();
  final _parentOccupation = TextEditingController();
  final _childName = TextEditingController();
  final _educationBudget = TextEditingController();
  final _preferredEducationLocation = TextEditingController();
  final _parentConcerns = TextEditingController();
  final _preferredCareerPathways = TextEditingController();
  final _familyExpectations = TextEditingController();

  bool get isParent =>
      (widget.user['role'] ?? '').toString().toLowerCase() == 'parent';
  final _organizationController = TextEditingController();
  final _designationController = TextEditingController();
  final _departmentController = TextEditingController();

  PlatformFile? _idDocument;

  bool get isAdmin =>
      (widget.user['role'] ?? '').toString().toLowerCase() == 'admin';
  bool saving = false;

  Future<void> _pickIdDocument() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result.isEmpty) return;

      final file = result.first;
      final bytes = await file.xFile.readAsBytes();

      if (bytes.isEmpty) {
        _message('Could not read the selected file. Please try again.');
        return;
      }

      if (bytes.length > 5 * 1024 * 1024) {
        _message('ID document must not exceed 5 MB.');
        return;
      }

      if (!mounted) return;

      setState(() {
        _idDocument = file;
      });
    } catch (error) {
      _message('Could not select the document: $error');
    }
  }

  @override
  void dispose() {
    _education.dispose();
    _marks.dispose();
    _interests.dispose();
    _skills.dispose();
    _location.dispose();
    _aspirations.dispose();
    _family.dispose();
    _organizationController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _parentEducation.dispose();
    _parentOccupation.dispose();
    _childName.dispose();
    _educationBudget.dispose();
    _preferredEducationLocation.dispose();
    _parentConcerns.dispose();
    _preferredCareerPathways.dispose();
    _familyExpectations.dispose();
    super.dispose();
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (isAdmin && _idDocument == null) {
      _message('Please upload your ID document.');
      return;
    }

    if (saving) return;
    setState(() => saving = true);

    try {
      http.Response response;

      if (isAdmin) {
        final bytes = await _idDocument!.xFile.readAsBytes();

        if (bytes.isEmpty) {
          throw Exception('Please select your ID document again.');
        }

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$apiBaseUrl/auth/admin-profile'),
        );

        request.headers['Authorization'] = 'Bearer ${widget.token}';

        request.fields.addAll({
          'organization_name': _organizationController.text.trim(),
          'designation': _designationController.text.trim(),
          'department': _departmentController.text.trim(),
        });

        request.files.add(
          http.MultipartFile.fromBytes(
            'id_document',
            bytes,
            filename: _idDocument!.name,
          ),
        );

        final streamed = await request.send().timeout(
          const Duration(seconds: 30),
        );
        response = await http.Response.fromStream(streamed);
      } else {
        response = await http
            .put(
              Uri.parse('$apiBaseUrl/auth/profile'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${widget.token}',
              },

              body: jsonEncode(
                isParent
                    ? {
                        'parent_education': _parentEducation.text.trim(),
                        'parent_occupation': _parentOccupation.text.trim(),
                        'child_name': _childName.text.trim(),
                        'education_budget': _educationBudget.text.trim(),
                        'preferred_education_location':
                            _preferredEducationLocation.text.trim(),
                        'preferred_career_pathways': _preferredCareerPathways
                            .text
                            .trim(),
                        'parent_concerns': _parentConcerns.text.trim(),
                        'family_expectations': _familyExpectations.text.trim(),
                      }
                    : {
                        'education_qualification': _education.text.trim(),
                        'marks': _marks.text.trim(),
                        'interests': _interests.text.trim(),
                        'skills': _skills.text.trim(),
                        'location': _location.text.trim(),
                        'career_aspirations': _aspirations.text.trim(),
                        'family_considerations': _family.text.trim(),
                        'caste_category': _casteCategory,
                        'caste_certificate_status': _casteCertificateStatus,
                      },
              ),
            )
            .timeout(const Duration(seconds: 20));
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = <String, dynamic>{};
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map ? decoded['detail']?.toString() : null;
        throw Exception(
          detail ?? 'Could not save profile (${response.statusCode}).',
        );
      }

      final updatedUser = Map<String, dynamic>.from(widget.user);

      if (isAdmin && decoded is Map && decoded['user'] is Map) {
        updatedUser.addAll(Map<String, dynamic>.from(decoded['user'] as Map));
      } else if (!isAdmin && decoded is Map) {
        updatedUser.addAll(Map<String, dynamic>.from(decoded));
      }

      updatedUser['profile_completed'] = true;

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardPage(
            token: widget.token,
            user: updatedUser,
            role: (updatedUser['role'] ?? 'student').toString().toLowerCase(),
            displayName: (updatedUser['name'] ?? widget.displayName).toString(),
          ),
        ),
      );
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const PortalHeader(),
            const StepNavigation(activeStep: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: borderGrey),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create Your Profile',
                              style: const TextStyle(
                                fontSize: 27,
                                color: navy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isAdmin
                                  ? 'Welcome, ${widget.displayName}. Complete your organization profile to continue.'
                                  : 'Welcome, ${widget.displayName}. Tell us a little about yourself so Unnati can guide you better.',
                              style: const TextStyle(
                                color: textGrey,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(height: 3, color: orange),
                            const SizedBox(height: 22),

                            if (isAdmin) ...[
                              _field(
                                'Organization Name',
                                _organizationController,
                                hint: 'Enter organization name',
                              ),
                              _field(
                                'Designation',
                                _designationController,
                                hint: 'e.g. Administrator / Coordinator',
                              ),
                              _field(
                                'Department',
                                _departmentController,
                                hint: 'Enter department name',
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Upload ID Document',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF262626),
                                ),
                              ),
                              const SizedBox(height: 7),
                              OutlinedButton.icon(
                                onPressed: saving ? null : _pickIdDocument,
                                icon: const Icon(Icons.upload_file),
                                label: Text(
                                  _idDocument == null
                                      ? 'Choose PDF, JPG or PNG (max 5 MB)'
                                      : _idDocument!.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Your ID document will be stored privately.',
                                style: TextStyle(color: textGrey, fontSize: 13),
                              ),
                            ] else if (isParent) ...[
                              _field(
                                'Your Highest Education',
                                _parentEducation,
                                hint: 'e.g. 12th / Graduate / Postgraduate',
                              ),
                              _field(
                                'Your Occupation',
                                _parentOccupation,
                                hint: 'e.g. Teacher / Farmer / Business',
                              ),
                              _field(
                                'Child Name',
                                _childName,
                                hint: 'Enter your child’s name',
                              ),
                              _field(
                                'Education Budget',
                                _educationBudget,
                                hint: 'e.g. ₹50,000–₹1,00,000 per year',
                              ),
                              _field(
                                'Preferred Education Location',
                                _preferredEducationLocation,
                                hint:
                                    'e.g. Nashik / Pune / Anywhere in Maharashtra',
                              ),
                              _field(
                                'Preferred Career Pathways for Your Child',
                                _preferredCareerPathways,
                                hint:
                                    'e.g. Engineering / Medical / Commerce / Open to options',
                                maxLines: 2,
                              ),
                              _field(
                                'Career Concerns',
                                _parentConcerns,
                                hint:
                                    'Salary, job security, safety, growth, social acceptance...',
                                maxLines: 3,
                              ),
                              _field(
                                'Family Expectations',
                                _familyExpectations,
                                hint:
                                    'What do you expect from your child’s future career?',
                                maxLines: 3,
                              ),
                            ] else ...[
                              _field(
                                'Education Qualification',
                                _education,
                                hint: 'e.g. 12th / Diploma / B.Tech',
                              ),
                              _field(
                                'Marks / Percentage / CGPA',
                                _marks,
                                hint: 'e.g. 82% or 8.1 CGPA',
                              ),

                              DropdownButtonFormField<String>(
                                initialValue: _casteCategory,
                                decoration: _decoration('Caste Category'),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'OPEN',
                                    child: Text('Open / General'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'SC',
                                    child: Text('SC'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ST',
                                    child: Text('ST'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'OBC',
                                    child: Text('OBC'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'VJNT',
                                    child: Text('VJNT'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'SBC',
                                    child: Text('SBC'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'EWS',
                                    child: Text('EWS'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Other',
                                    child: Text('Other / Not listed'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Prefer not to say',
                                    child: Text('Prefer not to say'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _casteCategory = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _casteCertificateStatus,
                                decoration: _decoration(
                                  'Caste Certificate Status',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Available',
                                    child: Text('Available'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Applied',
                                    child: Text('Applied'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Not available',
                                    child: Text('Not available'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Not sure',
                                    child: Text('Not sure'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(
                                      () => _casteCertificateStatus = value,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 12),

                              _field(
                                'Interests',
                                _interests,
                                hint: 'Subjects, activities, fields you enjoy',
                                maxLines: 2,
                              ),
                              _field(
                                'Skills',
                                _skills,
                                hint: 'Your current skills and strengths',
                                maxLines: 2,
                              ),
                              _field(
                                'Location',
                                _location,
                                hint: 'City, district or village',
                              ),
                              _field(
                                'Career Aspirations',
                                _aspirations,
                                hint: 'What careers are you considering?',
                                maxLines: 2,
                              ),
                              _field(
                                'Family Considerations',
                                _family,
                                hint:
                                    'Budget, location, safety or family expectations',
                                maxLines: 2,
                                requiredField: false,
                              ),
                            ],

                            const SizedBox(height: 12),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: saving ? null : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: navy,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: saving
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        'Save Profile & Continue to Dashboard',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => _logout(context),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF262626),
            ),
          ),
          const SizedBox(height: 7),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: _decoration(hint ?? 'Enter $label'),
            validator: requiredField && controller == _education
                ? (value) => value == null || value.trim().isEmpty
                      ? 'Please enter your education qualification'
                      : null
                : null,
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: borderGrey),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: borderGrey),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: navy, width: 1.5),
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.token,
    required this.user,
    required this.role,
    required this.displayName,
  });

  final String token;
  final Map<String, dynamic> user;
  final String role;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final normalizedRole = role.toLowerCase();
    final title = normalizedRole == 'parent'
        ? 'Parent Dashboard'
        : normalizedRole == 'admin'
        ? 'Admin Dashboard'
        : normalizedRole == 'owner'
        ? 'Owner Dashboard'
        : 'Student Dashboard';
    final subtitle = normalizedRole == 'parent'
        ? 'Support your child with informed career decisions.'
        : normalizedRole == 'admin'
        ? 'Manage platform activity and review relevant information.'
        : normalizedRole == 'owner'
        ? 'Manage Unnati administration and platform oversight.'
        : 'Explore career paths that match your interests and strengths.';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const PortalHeader(),
            const StepNavigation(activeStep: 2),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            color: navy,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, $displayName',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Your Unnati workspace',
                          style: const TextStyle(
                            color: navy,
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth > 650 ? 3 : 1;
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: columns == 1 ? 2.8 : 1.15,
                              children: _dashboardCards(normalizedRole),
                            );
                          },
                        ),
                        if (normalizedRole == 'student' &&
                            user['child_code'] != null) ...[
                          const SizedBox(height: 14),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.key_outlined,
                                    color: navy,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Your Child Code',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  SelectableText(
                                    user['child_code'].toString(),
                                    style: const TextStyle(
                                      color: navy,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _logout(context),
                            icon: const Icon(Icons.logout),
                            label: const Text('Sign Out'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  List<Widget> _dashboardCards(String normalizedRole) {
    if (normalizedRole == 'parent') {
      return const [
        DashboardCard(
          icon: Icons.family_restroom,
          title: 'Link Child',
          description: 'Connect your child using their Child Code.',
        ),
        DashboardCard(
          icon: Icons.insights_outlined,
          title: 'Career Progress',
          description: 'Review your child’s career exploration and profile.',
        ),
        DashboardCard(
          icon: Icons.school_outlined,
          title: 'Education Options',
          description: 'Explore courses, institutions and possible pathways.',
        ),
      ];
    }
    if (normalizedRole == 'admin' || normalizedRole == 'owner') {
      return const [
        DashboardCard(
          icon: Icons.manage_accounts_outlined,
          title: 'User Management',
          description: 'View and manage platform users.',
        ),
        DashboardCard(
          icon: Icons.fact_check_outlined,
          title: 'Review Queue',
          description: 'Review pending requests and submissions.',
        ),
        DashboardCard(
          icon: Icons.analytics_outlined,
          title: 'Platform Overview',
          description: 'Monitor activity and platform information.',
        ),
      ];
    }
    return const [
      DashboardCard(
        icon: Icons.explore_outlined,
        title: 'Explore Careers',
        description: 'Discover career options with reasons and guidance.',
      ),
      DashboardCard(
        icon: Icons.school_outlined,
        title: 'Courses & Colleges',
        description: 'Explore courses, colleges and eligibility.',
      ),
      DashboardCard(
        icon: Icons.workspace_premium_outlined,
        title: 'Scholarships',
        description: 'Find scholarship and admission opportunities.',
      ),
    ];
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: borderGrey),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: orange, size: 31),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            color: navy,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        Text(description, style: const TextStyle(color: textGrey, height: 1.4)),
      ],
    ),
  );
}

class PortalHeader extends StatelessWidget {
  const PortalHeader({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 25),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: navy,
                border: Border.all(color: orange, width: 5),
              ),
              child: const Center(
                child: Text(
                  'U',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 17),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unnati Career Guidance',
                    style: TextStyle(
                      color: navy,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Informed career decisions for students and families',
                    style: TextStyle(
                      color: Color(0xFF626262),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class StepNavigation extends StatelessWidget {
  const StepNavigation({super.key, required this.activeStep});
  final int activeStep;

  @override
  Widget build(BuildContext context) {
    const steps = ['Registration', 'Profile Creation', 'Dashboard'];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: navy,
        border: Border(
          top: BorderSide(color: orange, width: 5),
          bottom: BorderSide(color: Color(0xFFDDDDDD), width: 1),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Row(
            children: List.generate(steps.length, (index) {
              final selected = index == activeStep;
              final complete = index < activeStep;
              return Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 68),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : navy,
                    border: Border(
                      bottom: BorderSide(
                        color: selected ? orange : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: selected || complete
                            ? orange
                            : const Color(0xFF284773),
                        child: Icon(
                          complete ? Icons.check : Icons.circle,
                          color: Colors.white,
                          size: complete ? 15 : 8,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          steps[index],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? navy : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class AiCounsellorBar extends StatelessWidget {
  const AiCounsellorBar({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: orange,
    child: InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Counsellor will be connected in the next step.'),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.smart_toy_outlined, color: Colors.white),
              SizedBox(width: 9),
              Text(
                'Ask the AI Counsellor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_up, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

void _logout(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthPage()),
    (route) => false,
  );
}
