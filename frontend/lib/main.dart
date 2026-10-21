import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const UnnatiApp());

const navy = Color(0xFF17345F);
const navyLight = Color(0xFF284773);
const orange = Color(0xFFE8891B);
const pageGrey = Color(0xFFF2F3F7);
const borderGrey = Color(0xFFD0D3D9);
const textGrey = Color(0xFF667085);

const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

String get apiBaseUrl {
  if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
  try {
    final host = Uri.base.host;
    if (host == 'localhost') {
      return 'http://localhost:8000';
    } else if (host == '127.0.0.1') {
      return 'http://127.0.0.1:8000';
    } else if (host.isNotEmpty && Uri.base.scheme.startsWith('http')) {
      return '${Uri.base.scheme}://$host:8000';
    }
  } catch (_) {}
  return 'http://127.0.0.1:8000';
}

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

// ==========================================
// 1. AUTHENTICATION (PRE-REGISTERED LOGIN, PARENT CODE LOGIN, & REGISTER)
// ==========================================

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginFormKey = GlobalKey<FormState>();
  final _parentCodeFormKey = GlobalKey<FormState>();

  // Register controllers
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();

  // Pre-registered Login controllers
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Parent Code Login controllers
  final _childCodeController = TextEditingController();
  final _parentPhoneController = TextEditingController();
  final _parentNameController = TextEditingController();

  String activeTab = 'Sign In'; // Default to Sign In for pre-registered users!
  String role = 'student';
  String language = 'English';
  bool consent = true;
  bool hidePassword = true;
  bool hideLoginPassword = true;
  String? authErrorMessage;
  bool isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    _childCodeController.dispose();
    _parentPhoneController.dispose();
    _parentNameController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      String? detail;
      if (decoded is Map) {
        final d = decoded['detail'];
        if (d is List) {
          detail = d.map((e) => e is Map ? (e['msg'] ?? e['message'])?.toString() : e.toString()).join('. ');
        } else if (d != null) {
          detail = d.toString();
        }
      }
      throw Exception(detail ?? 'Request failed (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from the server.');
    }
    return decoded;
  }

  // Submit Pre-Registered Login (Mobile/Email + Password)
  Future<void> _submitLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    if (isSubmitting) return;

    setState(() {
      isSubmitting = true;
      authErrorMessage = null;
    });

    try {
      final login = await _postJson('/auth/login', {
        'identifier': _loginIdentifierController.text.trim(),
        'password': _loginPasswordController.text,
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
    } catch (error) {
      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      final display = errorMessage.contains('SocketException') || errorMessage.contains('ClientException')
          ? 'Cannot connect to Unnati API at $apiBaseUrl. Check that FastAPI is running.'
          : errorMessage;
      if (mounted) setState(() => authErrorMessage = display);
      _message(display);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // Submit Parent Login using Child Code
  Future<void> _submitParentCodeLogin() async {
    if (!_parentCodeFormKey.currentState!.validate()) return;
    if (isSubmitting) return;

    setState(() {
      isSubmitting = true;
      authErrorMessage = null;
    });

    try {
      final code = _childCodeController.text.trim().toUpperCase();
      final phone = _parentPhoneController.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');
      final name = _parentNameController.text.trim();

      final login = await _postJson('/auth/parent-code-login', {
        'child_code': code,
        if (phone.isNotEmpty) 'parent_phone': phone,
        if (name.isNotEmpty) 'parent_name': name,
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
    } catch (error) {
      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      final display = errorMessage.contains('SocketException') || errorMessage.contains('ClientException')
          ? 'Cannot connect to Unnati API at $apiBaseUrl. Check that FastAPI is running.'
          : errorMessage;
      if (mounted) setState(() => authErrorMessage = display);
      _message(display);
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // Submit New Registration
  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (role == 'student' && !consent) {
      const msg = 'Please agree to share the information required for counselling.';
      setState(() => authErrorMessage = msg);
      _message(msg);
      return;
    }

    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
      authErrorMessage = null;
    });

    final mobile = _mobileController.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');
    final password = _passwordController.text;

    try {
      final registration = await _postJson('/auth/register', {
        'name': _nameController.text.trim(),
        'phone': mobile,
        'password': password,
        'role': role,
        'preferred_language': language,
        'consent_given': role == 'student' ? consent : false,
      });

      String? childCode = registration['child_code']?.toString();
      if (childCode == null || childCode.isEmpty) {
        final maybeUser = registration['user'];
        if (maybeUser is Map) {
          childCode = maybeUser['child_code']?.toString();
        }
      }

      final login = await _postJson('/auth/login', {
        'identifier': mobile,
        'password': password,
      });

      final token = login['access_token']?.toString();
      final userValue = login['user'];
      final user = userValue is Map
          ? Map<String, dynamic>.from(userValue)
          : Map<String, dynamic>.from(login);

      if (token == null || token.isEmpty) {
        throw Exception('Account created, but login token was not returned. Please sign in.');
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
                const Text('Your Child Code', style: TextStyle(fontWeight: FontWeight.bold)),
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
                const Text('Share this code with your parent so they can log in directly and follow your progress.'),
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
    } catch (error) {
      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      final display = errorMessage.contains('SocketException') || errorMessage.contains('ClientException')
          ? 'Cannot connect to Unnati API at $apiBaseUrl. Check that FastAPI is running.'
          : errorMessage;
      if (mounted) setState(() => authErrorMessage = display);
      _message(display);
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
          builder: (_) => ProfileCreationPage(token: token, user: user, displayName: name),
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
                          child: _authCard(),
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

  Widget _authCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: borderGrey),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Three main tabs
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tabButton('Sign In', 'Sign In (Pre-Registered)'),
                _tabButton('Parent Code Login', '👨‍👩‍👧 Parent Code Login'),
                _tabButton('Register', 'New Registration'),
              ],
            ),

            if (authErrorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8E8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF8B4B4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFC81E1E), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authErrorMessage!,
                            style: const TextStyle(
                              color: Color(0xFF9B1C1C),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (authErrorMessage!.toLowerCase().contains('already registered') ||
                              authErrorMessage!.toLowerCase().contains('already exists')) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  activeTab = 'Sign In';
                                  _loginIdentifierController.text = _mobileController.text.trim();
                                  authErrorMessage = null;
                                });
                              },
                              child: const Text(
                                '👉 This mobile/email is already registered. Click here to Sign In with your password →',
                                style: TextStyle(
                                  color: navy,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF9B1C1C)),
                      onPressed: () => setState(() => authErrorMessage = null),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            if (activeTab == 'Sign In') ...[
              _signInForm(),
            ] else if (activeTab == 'Parent Code Login') ...[
              _parentCodeLoginForm(),
            ] else ...[
              _registerForm(),
            ],
          ],
        ),
      ),
    );
  }

  // 1. Sign In Form for Pre-Registered Users
  Widget _signInForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign In to Unnati',
            style: TextStyle(color: navy, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Welcome back! Log in using your registered 10-digit mobile number or email address.',
            style: TextStyle(color: textGrey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(height: 3, color: orange),
          const SizedBox(height: 22),

          _fieldLabel('Mobile Number or Email'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _loginIdentifierController,
            decoration: _inputDecoration('Enter 10-digit mobile number or email'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Enter your mobile number or email' : null,
          ),
          const SizedBox(height: 16),

          _fieldLabel('Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _loginPasswordController,
            obscureText: hideLoginPassword,
            decoration: _inputDecoration('Enter password').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => hideLoginPassword = !hideLoginPassword),
                icon: Icon(hideLoginPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
            validator: (value) => value == null || value.isEmpty ? 'Enter your password' : null,
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : _submitLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Sign In & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 18),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => activeTab = 'Parent Code Login'),
              icon: const Icon(Icons.family_restroom, color: orange),
              label: const Text(
                'Are you a parent with a Child Code? Click here to Login with Code →',
                style: TextStyle(color: navy, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Parent Login with Child Code Form
  Widget _parentCodeLoginForm() {
    return Form(
      key: _parentCodeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.family_restroom, color: orange, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Parent Login with Child Code',
                  style: TextStyle(color: navy, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFC2D6FF)),
            ),
            child: const Text(
              'No password required! Parents can instantly enter the portal to track their child’s career progress, recommended vocational courses, and scholarship options using the student’s Child Code (e.g. CH-A1B2C3D4).',
              style: TextStyle(color: navy, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 3, color: orange),
          const SizedBox(height: 22),

          _fieldLabel('Student Child Code *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _childCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDecoration('e.g. CH-8A9F2B').copyWith(
              prefixIcon: const Icon(Icons.key, color: orange),
            ),
            validator: (value) =>
                value == null || value.trim().length < 5 ? 'Enter valid Child Code (e.g. CH-XXXX)' : null,
          ),
          const SizedBox(height: 14),

          _fieldLabel('Your Mobile Number (Optional)'),
          const SizedBox(height: 4),
          Text('Helps save your parent preferences and receive SMS updates.', style: TextStyle(color: textGrey, fontSize: 12)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _parentPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: _inputDecoration('10-digit mobile number').copyWith(counterText: ''),
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                final cleaned = value.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');
                if (cleaned.length != 10) {
                  return 'Enter a valid 10-digit mobile number';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          _fieldLabel('Your Name (Optional)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _parentNameController,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration('Enter your name (e.g. Ramesh Patil)'),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : _submitParentCodeLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enter Parent Dashboard with Child Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // 3. New Registration Form
  Widget _registerForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create New Account',
            style: TextStyle(color: navy, fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text('Register as Student, Parent, or Institutional Admin.', style: TextStyle(color: textGrey, fontSize: 14)),
          const SizedBox(height: 16),
          Container(height: 3, color: orange),
          const SizedBox(height: 22),

          _fieldLabel('Register As'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: _inputDecoration('Select account type'),
            items: const [
              DropdownMenuItem(value: 'student', child: Text('Student (Vocational Aspirant)')),
              DropdownMenuItem(value: 'parent', child: Text('Parent / Guardian')),
              DropdownMenuItem(value: 'admin', child: Text('Institutional Administrator')),
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
            validator: (value) => value == null || value.trim().length < 2 ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 14),

          _fieldLabel('Mobile Number'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: _inputDecoration('Enter 10-digit mobile number').copyWith(counterText: ''),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Enter 10-digit mobile number';
              final cleaned = value.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), '');
              if (cleaned.length != 10) return 'Enter a valid 10-digit mobile number';
              return null;
            },
          ),
          const SizedBox(height: 14),

          _fieldLabel('Password (min 8 characters)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: hidePassword,
            decoration: _inputDecoration('Enter password').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => hidePassword = !hidePassword),
                icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
            validator: (value) => value == null || value.length < 8 ? 'Password must contain at least 8 characters' : null,
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

          if (role == 'student') ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              activeColor: navy,
              onChanged: (value) => setState(() => consent = value ?? false),
              title: const Text(
                'I agree to share my education details for personalized vocational career guidance.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 18),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : _submitRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Register Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String key, String title) {
    final selected = activeTab == key;
    return OutlinedButton(
      onPressed: () => setState(() {
        activeTab = key;
        authErrorMessage = null;
      }),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? navy : const Color(0xFFF0F2F6),
        foregroundColor: selected ? Colors.white : Colors.black87,
        side: BorderSide(color: selected ? navy : const Color(0xFFD9DDE5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
            _languageLink('हिन्दी'),
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
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF262626)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
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

// ==========================================
// 2. PROFILE CREATION / EDITING (STAGE 2)
// ==========================================

class ProfileCreationPage extends StatefulWidget {
  const ProfileCreationPage({
    super.key,
    required this.token,
    required this.user,
    required this.displayName,
    this.isEditing = false,
  });

  final String token;
  final Map<String, dynamic> user;
  final String displayName;
  final bool isEditing;

  @override
  State<ProfileCreationPage> createState() => _ProfileCreationPageState();
}

class _ProfileCreationPageState extends State<ProfileCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final _education = TextEditingController();
  String _casteCategory = 'OBC';
  String _casteCertificateStatus = 'Available';
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

  // Admin-only fields
  final _organizationController = TextEditingController();
  final _designationController = TextEditingController();
  final _departmentController = TextEditingController();
  PlatformFile? _idDocument;

  bool get isParent => (widget.user['role'] ?? '').toString().toLowerCase() == 'parent';
  bool get isAdmin => (widget.user['role'] ?? '').toString().toLowerCase() == 'admin';

  bool saving = false;
  bool loadingExisting = false;

  @override
  void initState() {
    super.initState();
    _loadProfileIfAvailable();
  }

  Future<void> _loadProfileIfAvailable() async {
    setState(() => loadingExisting = true);
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/auth/profile'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['profile'] is Map) {
          final p = Map<String, dynamic>.from(decoded['profile']);
          setState(() {
            _education.text = p['education_qualification']?.toString() ?? '';
            _marks.text = p['marks']?.toString() ?? '';
            _interests.text = p['interests']?.toString() ?? '';
            _skills.text = p['skills']?.toString() ?? '';
            _location.text = p['location']?.toString() ?? '';
            _aspirations.text = p['career_aspirations']?.toString() ?? '';
            _family.text = p['family_considerations']?.toString() ?? '';
            if (p['caste_category'] != null) _casteCategory = p['caste_category'].toString();
            if (p['caste_certificate_status'] != null) {
              _casteCertificateStatus = p['caste_certificate_status'].toString();
            }

            _parentEducation.text = p['parent_education']?.toString() ?? '';
            _parentOccupation.text = p['parent_occupation']?.toString() ?? '';
            _childName.text = p['child_name']?.toString() ?? '';
            _educationBudget.text = p['education_budget']?.toString() ?? '';
            _preferredEducationLocation.text = p['preferred_education_location']?.toString() ?? '';
            _parentConcerns.text = p['parent_concerns']?.toString() ?? '';
            _preferredCareerPathways.text = p['preferred_career_pathways']?.toString() ?? '';
            _familyExpectations.text = p['family_expectations']?.toString() ?? '';
          });
        }
      }
    } catch (_) {
      // Clean fallback
    } finally {
      if (mounted) setState(() => loadingExisting = false);
    }
  }

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
      setState(() => _idDocument = file);
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

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (isAdmin && _idDocument == null && !widget.isEditing) {
      _message('Please upload your ID document.');
      return;
    }

    if (saving) return;
    setState(() => saving = true);

    try {
      http.Response response;

      if (isAdmin && !widget.isEditing) {
        final bytes = await _idDocument!.xFile.readAsBytes();
        if (bytes.isEmpty) throw Exception('Please select your ID document again.');

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
          http.MultipartFile.fromBytes('id_document', bytes, filename: _idDocument!.name),
        );

        final streamed = await request.send().timeout(const Duration(seconds: 30));
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
                        'preferred_education_location': _preferredEducationLocation.text.trim(),
                        'preferred_career_pathways': _preferredCareerPathways.text.trim(),
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
        throw Exception(detail ?? 'Could not save profile (${response.statusCode}).');
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
                              widget.isEditing ? 'Update Your Profile' : 'Stage 2: Create Your Guidance Profile',
                              style: const TextStyle(
                                fontSize: 26,
                                color: navy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isAdmin
                                  ? 'Welcome, ${widget.displayName}. Complete your organization profile to continue.'
                                  : 'Welcome, ${widget.displayName}. Tell us about your background, marks, interests, and family expectations so Unnati can generate personalized vocational recommendations with job security scores and fee assistance metrics on your dashboard.',
                              style: const TextStyle(color: textGrey, height: 1.5),
                            ),
                            const SizedBox(height: 18),
                            Container(height: 3, color: orange),
                            const SizedBox(height: 22),

                            if (loadingExisting) ...[
                              const Center(child: CircularProgressIndicator()),
                              const SizedBox(height: 20),
                            ],

                            if (isAdmin) ...[
                              _field('Organization Name', _organizationController, hint: 'Enter organization name'),
                              _field('Designation', _designationController, hint: 'e.g. Administrator / Coordinator'),
                              _field('Department', _departmentController, hint: 'Enter department name'),
                              const SizedBox(height: 4),
                              const Text('Upload ID Document', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 7),
                              OutlinedButton.icon(
                                onPressed: saving ? null : _pickIdDocument,
                                icon: const Icon(Icons.upload_file),
                                label: Text(
                                  _idDocument == null ? 'Choose PDF, JPG or PNG (max 5 MB)' : _idDocument!.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('Your ID document will be stored privately.', style: TextStyle(color: textGrey, fontSize: 13)),
                            ] else if (isParent) ...[
                              _field('Your Highest Education', _parentEducation, hint: 'e.g. 10th / 12th / Graduate'),
                              _field('Your Occupation', _parentOccupation, hint: 'e.g. Farmer / Business / Service / Homemaker'),
                              _field('Child Name', _childName, hint: 'Enter your child’s full name'),
                              _field('Education Budget', _educationBudget, hint: 'e.g. Up to ₹30,000 / year (or looking for free govt ITI)'),
                              _field('Preferred Education Location', _preferredEducationLocation, hint: 'e.g. Local taluka / Nashik / Pune / Anywhere in Maharashtra'),
                              _field('Preferred Career Pathways for Child', _preferredCareerPathways, hint: 'e.g. Electrical / IT / Mechanical / Healthcare / Open to suggestions', maxLines: 2),
                              _field('Your Primary Concerns as a Parent', _parentConcerns, hint: 'e.g. Permanent job security, early earning, safe campus, hostel facility...', maxLines: 3),
                              _field('Family Expectations', _familyExpectations, hint: 'What is most important for your family in your child’s future?', maxLines: 3),
                            ] else ...[
                              _field('Education Qualification', _education, hint: 'e.g. 10th Passed / 10th Appearing / 12th / ITI'),
                              _field('Marks / Percentage', _marks, hint: 'e.g. 74% in 10th Board Exam'),
                              DropdownButtonFormField<String>(
                                initialValue: _casteCategory,
                                decoration: _decoration('Caste Category (Used for Govt Fee Waivers & MahaDBT)'),
                                items: const [
                                  DropdownMenuItem(value: 'OPEN', child: Text('Open / General')),
                                  DropdownMenuItem(value: 'SC', child: Text('SC (Scheduled Caste - 100% Fee Waiver)')),
                                  DropdownMenuItem(value: 'ST', child: Text('ST (Scheduled Tribe - 100% Fee Waiver)')),
                                  DropdownMenuItem(value: 'OBC', child: Text('OBC (Other Backward Class - 50% Waiver)')),
                                  DropdownMenuItem(value: 'VJNT', child: Text('VJNT / NT (100% Fee Waiver)')),
                                  DropdownMenuItem(value: 'SBC', child: Text('SBC (Special Backward Class)')),
                                  DropdownMenuItem(value: 'EWS', child: Text('EWS (Economically Weaker Section)')),
                                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                                ],
                                onChanged: (value) {
                                  if (value != null) setState(() => _casteCategory = value);
                                },
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue: _casteCertificateStatus,
                                decoration: _decoration('Caste Certificate Status'),
                                items: const [
                                  DropdownMenuItem(value: 'Available', child: Text('Available in hand')),
                                  DropdownMenuItem(value: 'Applied', child: Text('Applied / Token available')),
                                  DropdownMenuItem(value: 'Not available', child: Text('Not available')),
                                  DropdownMenuItem(value: 'Not sure', child: Text('Not sure / Need guidance')),
                                ],
                                onChanged: (value) {
                                  if (value != null) setState(() => _casteCertificateStatus = value);
                                },
                              ),
                              const SizedBox(height: 14),
                              _field('Your Hands-on Interests', _interests, hint: 'e.g. Working with electrical tools, fixing machines, computers, medical care, solar tech', maxLines: 2),
                              _field('Skills & Strengths', _skills, hint: 'e.g. Mathematics, handcraft, mechanical repair, English, drawing', maxLines: 2),
                              _field('Current District / Village', _location, hint: 'e.g. Nashik, Taluka Dindori'),
                              _field('Career Aspirations', _aspirations, hint: 'e.g. Want to become an Electrician, CNC operator, or join Railway apprenticeship', maxLines: 2),
                              _field('Family & Financial Considerations', _family, hint: 'e.g. Need to start earning within 1-2 years to support family', maxLines: 2, requiredField: false),
                            ],

                            const SizedBox(height: 14),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: saving ? null : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: navy,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                child: saving
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        widget.isEditing ? 'Save Changes' : 'Save Profile & View Recommended Vocational Courses',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (widget.isEditing)
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              )
                            else
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
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF262626)),
          ),
          const SizedBox(height: 7),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: _decoration(hint ?? 'Enter $label'),
            validator: requiredField && (controller == _education || controller == _childName)
                ? (value) => value == null || value.trim().isEmpty ? 'Please enter this field' : null
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: borderGrey)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: borderGrey)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: navy, width: 1.5)),
      );
}

// ==========================================
// 3. DASHBOARD PAGE (PERSONALIZED COURSE RECOMMENDATIONS + WORKSPACE)
// ==========================================

class DashboardPage extends StatefulWidget {
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
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<dynamic> recommendations = [];
  bool loadingRecommendations = true;
  String studentName = '';
  String qualification = '';
  String casteCategory = '';

  @override
  void initState() {
    super.initState();
    _fetchPersonalizedRecommendations();
  }

  Future<void> _fetchPersonalizedRecommendations() async {
    setState(() => loadingRecommendations = true);
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/guidance/personalized-recommendations'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          recommendations = data['recommendations'] ?? [];
          studentName = data['student_name']?.toString() ?? widget.displayName;
          qualification = data['qualification']?.toString() ?? '';
          casteCategory = data['caste_category']?.toString() ?? '';
        });
      }
    } catch (_) {
      // Clean fallback if offline
    } finally {
      if (mounted) setState(() => loadingRecommendations = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedRole = widget.role.toLowerCase();
    final title = normalizedRole == 'parent'
        ? 'Parent Dashboard'
        : normalizedRole == 'admin'
            ? 'Admin Dashboard'
            : normalizedRole == 'owner'
                ? 'Owner Dashboard'
                : 'Student Dashboard';
    final subtitle = normalizedRole == 'parent'
        ? 'Support your child with high-job-security vocational courses, budget transparency, and linked progress.'
        : normalizedRole == 'admin'
            ? 'Manage platform activity, review user requests, and oversee counsellings.'
            : normalizedRole == 'owner'
                ? 'Manage Unnati administration, approve admin applications, and review platform metrics.'
                : 'Explore high-demand vocational trades, early earning timelines, and government scholarships.';

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
                        // Welcome Banner
                        Container(
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            color: navy,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hello, ${widget.displayName}',
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
                                        color: orange,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      subtitle,
                                      style: const TextStyle(color: Colors.white70, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ProfileCreationPage(
                                            token: widget.token,
                                            user: widget.user,
                                            displayName: widget.displayName,
                                            isEditing: true,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_note, color: Colors.white, size: 28),
                                    tooltip: 'Edit Profile Inputs',
                                  ),
                                  const Text('Edit Profile', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Child Code Bar for Students
                        if (normalizedRole == 'student' && widget.user['child_code'] != null) ...[
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: const BorderSide(color: borderGrey),
                            ),
                            color: const Color(0xFFF9FAFC),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.key_outlined, color: orange, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Your Unique Child Code',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: navy),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Share with your parents so they can log in directly without a password!',
                                          style: TextStyle(color: textGrey, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: navy,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        SelectableText(
                                          widget.user['child_code'].toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(text: widget.user['child_code'].toString()));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Child Code copied to clipboard!')),
                                            );
                                          },
                                          child: const Icon(Icons.copy, color: Colors.white70, size: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        // ========================================================
                        // NEW FEATURE: PERSONALIZED VOCATIONAL RECOMMENDATIONS
                        // Highlighted with Job Security Score & Parent Metrics!
                        // ========================================================
                        if (normalizedRole == 'student' || normalizedRole == 'parent') ...[
                          _personalizedRecommendationsSection(),
                          const SizedBox(height: 28),
                        ],

                        // ========================================================
                        // EARLIER WORKSPACE OPTIONS (PRESERVED IN FULL)
                        // ========================================================
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Unnati Guidance Workspace & Tools',
                              style: const TextStyle(color: navy, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Full Directory',
                              style: TextStyle(color: textGrey, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Interactive Workspace Cards (Keeps all earlier options)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth > 650 ? 3 : 1;
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: columns == 1 ? 2.6 : 1.15,
                              children: _getInteractiveCards(context, normalizedRole),
                            );
                          },
                        ),

                        const SizedBox(height: 26),

                        // Sign out bar
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

  // Personalized Course Recommendations Section with Parent-Attracting Metrics
  Widget _personalizedRecommendationsSection() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.verified_user, color: orange, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🎯 Recommended Vocational Courses For You',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: navy),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Tailored from your Stage-2 profile inputs. Highlighted with Job Security Scores, early earning ages, and low-cost training metrics to give parents complete confidence.',
                      style: TextStyle(color: textGrey, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          if (loadingRecommendations)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (recommendations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('Complete your Stage-2 profile to see tailored recommendations.', style: TextStyle(color: textGrey)),
              ),
            )
          else
            ...recommendations.map((rec) => _recommendedCourseCard(rec)),
        ],
      ),
    );
  }

  Widget _recommendedCourseCard(Map<String, dynamic> rec) {
    final c = rec['career'] ?? {};
    final title = c['title']?.toString() ?? '';
    final stream = c['stream']?.toString() ?? '';
    final matchPct = rec['match_percentage'] ?? 90;
    final jobSecScore = rec['job_security_score'] ?? 95;
    final jobSecLabel = rec['job_security_label']?.toString() ?? 'High Stability';
    final earningAge = rec['earning_age']?.toString() ?? 'Age 18 - 19';
    final stipend = rec['apprenticeship_stipend']?.toString() ?? '₹8,500 - ₹12,000 / mo';
    final feeEstimate = rec['fee_estimate']?.toString() ?? 'Subsidized';
    final feeReason = rec['fee_reason']?.toString() ?? '100% Fee Waiver Eligible';
    final parentAppeal = rec['parent_appeal']?.toString() ?? '';
    final parentHighlights = rec['parent_highlights'] is List ? List<String>.from(rec['parent_highlights']) : <String>[];
    final reasons = rec['reasons'] is List ? List<String>.from(rec['reasons']) : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD6DBE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Match badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
                    const SizedBox(height: 4),
                    Text('$stream • Duration: ${c["duration"] ?? "1-2 Years"}', style: TextStyle(color: textGrey, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green)),
                child: Text('$matchPct% Profile Match', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Key Metrics Grid that Parents Look For!
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metricChip(
                icon: Icons.shield_outlined,
                label: 'Job Security Score',
                value: '$jobSecScore/100',
                subtext: jobSecLabel,
                color: const Color(0xFF0F5132),
                bg: const Color(0xFFD1E7DD),
              ),
              _metricChip(
                icon: Icons.access_time_filled,
                label: 'Starts Earning',
                value: earningAge,
                subtext: 'Stipend: $stipend',
                color: const Color(0xFF664D03),
                bg: const Color(0xFFFFF3CD),
              ),
              _metricChip(
                icon: Icons.savings_outlined,
                label: 'Course Cost & ROI',
                value: feeEstimate,
                subtext: feeReason,
                color: const Color(0xFF084298),
                bg: const Color(0xFFCFE2FF),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Parent Peace of Mind Highlight Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBDD2E6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.family_restroom, color: orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Why Parents Value This Trade:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 14),
                    ),
                  ],
                ),
                if (parentAppeal.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(parentAppeal, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF203550))),
                ],
                if (parentHighlights.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...parentHighlights.map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('✓ ', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          Expanded(child: Text(h, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Why it fits you: ${reasons.first}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: textGrey)),
          ],
        ],
      ),
    );
  }

  Widget _metricChip({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
              Text(subtext, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _getInteractiveCards(BuildContext context, String normalizedRole) {
    if (normalizedRole == 'parent') {
      return [
        DashboardCard(
          icon: Icons.family_restroom,
          title: 'Link Child',
          description: 'Connect your child using their Child Code and view linked records.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ParentLinkChildView(token: widget.token)),
            );
          },
        ),
        DashboardCard(
          icon: Icons.insights_outlined,
          title: 'Career Progress',
          description: 'Review your child’s vocational exploration, strengths, and goals.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ParentCareerProgressView(token: widget.token)),
            );
          },
        ),
        DashboardCard(
          icon: Icons.school_outlined,
          title: 'Education Options',
          description: 'Compare vocational vs academic routes, fees, and government aid.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ParentEducationOptionsView()),
            );
          },
        ),
      ];
    }

    if (normalizedRole == 'admin' || normalizedRole == 'owner') {
      return [
        DashboardCard(
          icon: Icons.manage_accounts_outlined,
          title: 'User Management',
          description: 'View registered students, parents, and admins with status controls.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AdminUsersView(token: widget.token)),
            );
          },
        ),
        DashboardCard(
          icon: Icons.fact_check_outlined,
          title: 'Review Queue',
          description: 'Review and approve/reject pending admin applications with verified IDs.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AdminReviewQueueView(token: widget.token)),
            );
          },
        ),
        DashboardCard(
          icon: Icons.analytics_outlined,
          title: 'Platform Overview',
          description: 'Monitor real-time user registrations, roles, and language metrics.',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AdminOverviewView(token: widget.token)),
            );
          },
        ),
      ];
    }

    // Default: Student
    return [
      DashboardCard(
        icon: Icons.explore_outlined,
        title: 'Explore Careers',
        description: 'Discover vocational careers with eligibility, salaries, pathways, and quiz match.',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CareerExplorationView(token: widget.token, user: widget.user)),
          );
        },
      ),
      DashboardCard(
        icon: Icons.school_outlined,
        title: 'Courses & Colleges',
        description: 'Explore ITI CTS trades, Polytechnic diplomas, B.Voc programs, and admissions.',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CoursesInstitutesView()),
          );
        },
      ),
      DashboardCard(
        icon: Icons.workspace_premium_outlined,
        title: 'Scholarships',
        description: 'Find MahaDBT, AICTE Pragati, NAPS stipends, and apply directly.',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScholarshipsView()),
          );
        },
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: orange.withValues(alpha: 0.05),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: borderGrey),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: orange, size: 31),
                  if (onTap != null)
                    const Icon(Icons.arrow_forward_ios, size: 14, color: navy),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(color: navy, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 7),
              Text(
                description,
                style: const TextStyle(color: textGrey, height: 1.4, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 4. STUDENT FEATURE 1: EXPLORE CAREERS
// ==========================================

class CareerExplorationView extends StatefulWidget {
  const CareerExplorationView({super.key, required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  @override
  State<CareerExplorationView> createState() => _CareerExplorationViewState();
}

class _CareerExplorationViewState extends State<CareerExplorationView> {
  List<dynamic> careers = [];
  List<String> sectors = ['All'];
  String selectedSector = 'All';
  String searchQuery = '';
  bool isLoading = true;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    _fetchCareers();
  }

  Future<void> _fetchCareers() async {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });

    try {
      final queryParam = searchQuery.isNotEmpty ? '&query=${Uri.encodeComponent(searchQuery)}' : '';
      final sectorParam = selectedSector != 'All' ? '&sector=${Uri.encodeComponent(selectedSector)}' : '';
      final url = '$apiBaseUrl/guidance/careers?$queryParam$sectorParam';

      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          careers = data['careers'] ?? [];
          if (data['sectors'] != null) {
            sectors = List<String>.from(data['sectors']);
          }
        });
      } else {
        throw Exception('Server error: ${res.statusCode}');
      }
    } catch (e) {
      setState(() => errorMsg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _openCareerMatcherModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => CareerMatcherQuizModal(token: widget.token, user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Vocational Careers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: _openCareerMatcherModal,
            icon: const Icon(Icons.psychology, color: Colors.white),
            label: const Text('Career Match Quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search & Filter header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search career by title, skill, or trade (e.g. Electrician, Solar, CNC)...',
                      prefixIcon: const Icon(Icons.search, color: navy),
                      filled: true,
                      fillColor: pageGrey,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      searchQuery = val;
                      _fetchCareers();
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: sectors.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final s = sectors[index];
                        final isSel = s == selectedSector;
                        return ChoiceChip(
                          label: Text(s),
                          selected: isSel,
                          selectedColor: navy,
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87, fontSize: 13),
                          onSelected: (val) {
                            setState(() => selectedSector = s);
                            _fetchCareers();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMsg != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Failed to load: $errorMsg'),
                              const SizedBox(height: 10),
                              ElevatedButton(onPressed: _fetchCareers, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : careers.isEmpty
                          ? const Center(child: Text('No careers match your search criteria.'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: careers.length,
                              itemBuilder: (context, idx) {
                                final c = careers[idx];
                                return _careerCard(c);
                              },
                            ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  Widget _careerCard(Map<String, dynamic> c) {
    final title = c['title']?.toString() ?? '';
    final stream = c['stream']?.toString() ?? '';
    final qual = c['qualification']?.toString() ?? '';
    final dur = c['duration']?.toString() ?? '';
    final sal = c['salary_range']?.toString() ?? '';
    final desc = c['description']?.toString() ?? '';
    final skills = c['skills'] is List ? List<String>.from(c['skills']) : <String>[];
    final pathway = c['pathway']?.toString() ?? '';
    final employers = c['top_employers'] is List ? List<String>.from(c['top_employers']) : <String>[];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: borderGrey),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: navy,
          child: Text(title.isNotEmpty ? title[0] : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                  child: Text(stream, style: const TextStyle(color: orange, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(dur, style: TextStyle(color: textGrey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Est. Starting: $sal', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Text(desc, style: const TextStyle(height: 1.4, fontSize: 14)),
                const SizedBox(height: 12),
                const Text('Eligibility:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
                Text(qual, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                const Text('Career Progression Pathway:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
                Text(pathway, style: const TextStyle(fontSize: 13, color: Color(0xFF2B548A))),
                const SizedBox(height: 10),
                const Text('Key Practical Skills:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skills
                      .map((s) => Chip(
                            label: Text(s, style: const TextStyle(fontSize: 11)),
                            backgroundColor: pageGrey,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                const Text('Top Employers / Industries:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
                Text(employers.join(', '), style: TextStyle(fontSize: 13, color: textGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CareerMatcherQuizModal extends StatefulWidget {
  const CareerMatcherQuizModal({super.key, required this.token, required this.user});

  final String token;
  final Map<String, dynamic> user;

  @override
  State<CareerMatcherQuizModal> createState() => _CareerMatcherQuizModalState();
}

class _CareerMatcherQuizModalState extends State<CareerMatcherQuizModal> {
  String qualification = '10th Pass';
  final List<String> selectedInterests = [];
  bool isMatching = false;
  List<dynamic> recommendations = [];

  final List<String> interestOptions = [
    'Electrical & Wiring',
    'Machines & Mechanical Tools',
    'Computers & Software',
    'Automobiles & EV',
    'Healthcare & Nursing',
    'Agriculture & Drones',
    'Solar & Clean Energy',
    'Electronics & Gadgets',
  ];

  Future<void> _runMatch() async {
    setState(() => isMatching = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/guidance/career-match'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'qualification': qualification,
          'interests': selectedInterests.join(', '),
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          recommendations = data['recommendations'] ?? [];
        });
      }
    } catch (_) {
      // Clean fallback
    } finally {
      if (mounted) setState(() => isMatching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Vocational Career Matcher Quiz',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Select what you enjoy doing most to find your top vocational match.',
              style: TextStyle(color: textGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Your Current Education:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: qualification,
              items: const [
                DropdownMenuItem(value: '10th Pass', child: Text('10th Pass / Appearing')),
                DropdownMenuItem(value: '12th Pass', child: Text('12th Pass (Arts/Commerce/Science)')),
                DropdownMenuItem(value: 'ITI Holder', child: Text('Completed ITI Trade')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => qualification = val);
              },
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            const SizedBox(height: 16),
            const Text('What do you like to work with?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: interestOptions.map((opt) {
                final selected = selectedInterests.contains(opt);
                return FilterChip(
                  label: Text(opt),
                  selected: selected,
                  selectedColor: navy,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        selectedInterests.add(opt);
                      } else {
                        selectedInterests.remove(opt);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: isMatching ? null : _runMatch,
              style: ElevatedButton.styleFrom(backgroundColor: orange, foregroundColor: Colors.white),
              child: isMatching
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Find Matching Careers', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Top Recommended Careers for You:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: navy)),
              const SizedBox(height: 10),
              ...recommendations.map((rec) {
                final c = rec['career'] ?? {};
                final matchPct = rec['match_percentage'] ?? 80;
                final reasons = rec['reasons'] is List ? List<String>.from(rec['reasons']) : <String>[];

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(c['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: navy)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(10)),
                              child: Text('$matchPct% Match', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Salary: ${c['salary_range']} • Duration: ${c['duration']}', style: TextStyle(color: textGrey, fontSize: 12)),
                        if (reasons.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Why: ${reasons.first}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. STUDENT FEATURE 2: COURSES & COLLEGES
// ==========================================

class CoursesInstitutesView extends StatefulWidget {
  const CoursesInstitutesView({super.key});

  @override
  State<CoursesInstitutesView> createState() => _CoursesInstitutesViewState();
}

class _CoursesInstitutesViewState extends State<CoursesInstitutesView> {
  List<dynamic> courses = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/guidance/courses')).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          courses = data['courses'] ?? [];
        });
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses, ITIs & Colleges', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: courses.length,
                      itemBuilder: (context, idx) {
                        final item = courses[idx];
                        return _courseCard(item);
                      },
                    ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  Widget _courseCard(Map<String, dynamic> c) {
    final title = c['title']?.toString() ?? '';
    final category = c['category']?.toString() ?? '';
    final elig = c['eligibility']?.toString() ?? '';
    final dur = c['duration']?.toString() ?? '';
    final fees = c['fees']?.toString() ?? '';
    final admission = c['admission_process']?.toString() ?? '';
    final cert = c['certification']?.toString() ?? '';
    final trades = c['popular_trades'] is List ? List<String>.from(c['popular_trades']) : <String>[];
    final benefits = c['benefits']?.toString() ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: borderGrey),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(4)),
                  child: Text(category, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(dur, style: const TextStyle(fontWeight: FontWeight.bold, color: orange)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
            const SizedBox(height: 8),
            Text('Eligibility: $elig', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('Typical Fees: $fees', style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Admission Process:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
            Text(admission, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text('Recognized Certification:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
            Text(cert, style: TextStyle(fontSize: 13, color: textGrey)),
            if (trades.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Popular Trades / Streams:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: trades
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 11)),
                          backgroundColor: pageGrey,
                          padding: EdgeInsets.zero,
                        ))
                    .toList(),
              ),
            ],
            if (benefits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.star, color: orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(benefits, style: const TextStyle(fontSize: 12, color: navy))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 6. STUDENT FEATURE 3: SCHOLARSHIPS
// ==========================================

class ScholarshipsView extends StatefulWidget {
  const ScholarshipsView({super.key});

  @override
  State<ScholarshipsView> createState() => _ScholarshipsViewState();
}

class _ScholarshipsViewState extends State<ScholarshipsView> {
  List<dynamic> scholarships = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchScholarships();
  }

  Future<void> _fetchScholarships() async {
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/guidance/scholarships')).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          scholarships = data['scholarships'] ?? [];
        });
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government & Vocational Scholarships', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: scholarships.length,
                      itemBuilder: (context, idx) {
                        final s = scholarships[idx];
                        return _scholarshipCard(s);
                      },
                    ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }

  Widget _scholarshipCard(Map<String, dynamic> s) {
    final title = s['title']?.toString() ?? '';
    final provider = s['provider']?.toString() ?? '';
    final target = s['target_group']?.toString() ?? '';
    final benefit = s['benefit']?.toString() ?? '';
    final elig = s['eligibility']?.toString() ?? '';
    final deadline = s['deadline']?.toString() ?? '';
    final portalUrl = s['portal_url']?.toString() ?? '';
    final docs = s['required_docs'] is List ? List<String>.from(s['required_docs']) : <String>[];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: borderGrey)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: navy),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green)),
                  child: Text(benefit, style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(provider, style: TextStyle(color: textGrey, fontSize: 13)),
            const SizedBox(height: 10),
            Text('Target: $target', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: orange)),
            const SizedBox(height: 6),
            Text('Eligibility: $elig', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('Deadline: $deadline', style: const TextStyle(fontSize: 12, color: textGrey)),
            if (docs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Required Documents:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: navy)),
              Text(docs.join(' • '), style: TextStyle(fontSize: 12, color: textGrey)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (portalUrl.isNotEmpty) {
                    final uri = Uri.parse(portalUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: navy, foregroundColor: Colors.white),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Apply on Official Portal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 7. PARENT FEATURE 1: LINK CHILD
// ==========================================

class ParentLinkChildView extends StatefulWidget {
  const ParentLinkChildView({super.key, required this.token});

  final String token;

  @override
  State<ParentLinkChildView> createState() => _ParentLinkChildViewState();
}

class _ParentLinkChildViewState extends State<ParentLinkChildView> {
  final _codeController = TextEditingController();
  bool isLinking = false;
  bool isLoading = true;
  List<dynamic> children = [];

  @override
  void initState() {
    super.initState();
    _fetchChildren();
  }

  Future<void> _fetchChildren() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/auth/my-children'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => children = data is List ? data : []);
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  Future<void> _linkChild() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => isLinking = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/auth/link-child'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({'child_code': code}),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        _codeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Child linked successfully!')),
        );
        _fetchChildren();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail']?.toString() ?? 'Failed to link child.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => isLinking = false);
    }
  }

  Future<void> _unlinkChild(int childId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Child'),
        content: const Text('Are you sure you want to unlink this child from your parent account?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Unlink', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await http.delete(
        Uri.parse('$apiBaseUrl/auth/unlink-child/$childId'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        _fetchChildren();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link & Manage Children', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderGrey),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Link a New Child', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
                              const SizedBox(height: 6),
                              Text(
                                'Ask your child for their Child Code (e.g. CH-A1B2C3D4) generated upon student registration.',
                                style: TextStyle(color: textGrey, fontSize: 13),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _codeController,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        hintText: 'Enter Child Code (e.g. CH-XXXX)',
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: isLinking ? null : _linkChild,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: navy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                    ),
                                    child: isLinking
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Link Child', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text('Your Linked Children', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
                        const SizedBox(height: 12),

                        if (isLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (children.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderGrey),
                            ),
                            child: const Center(
                              child: Text('No children linked yet. Enter their Child Code above to link.', style: TextStyle(color: textGrey)),
                            ),
                          )
                        else
                          ...children.map((c) {
                            final name = c['name']?.toString() ?? 'Child';
                            final code = c['child_code']?.toString() ?? '';
                            final childId = c['id'] as int;
                            final completed = c['profile_completed'] == true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: const BorderSide(color: borderGrey),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: navy,
                                  child: Text(name[0], style: const TextStyle(color: Colors.white)),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: navy)),
                                subtitle: Text('Code: $code • Profile: ${completed ? "Completed" : "Incomplete"}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.visibility, color: orange),
                                      tooltip: 'View Profile',
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChildProfileDetailView(token: widget.token, childId: childId, childName: name),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.link_off, color: Colors.red),
                                      tooltip: 'Unlink',
                                      onPressed: () => _unlinkChild(childId),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
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
}

// ==========================================
// 8. PARENT FEATURE 2: CHILD CAREER PROGRESS
// ==========================================

class ParentCareerProgressView extends StatefulWidget {
  const ParentCareerProgressView({super.key, required this.token});

  final String token;

  @override
  State<ParentCareerProgressView> createState() => _ParentCareerProgressViewState();
}

class _ParentCareerProgressViewState extends State<ParentCareerProgressView> {
  List<dynamic> children = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChildren();
  }

  Future<void> _fetchChildren() async {
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/auth/my-children'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => children = data is List ? data : []);
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Career Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : children.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.family_restroom, size: 64, color: navyLight),
                                const SizedBox(height: 14),
                                const Text('No Linked Children Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
                                const SizedBox(height: 8),
                                const Text('Please link your child first using their Child Code.', textAlign: TextAlign.center, style: TextStyle(color: textGrey)),
                                const SizedBox(height: 18),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (_) => ParentLinkChildView(token: widget.token)),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: navy, foregroundColor: Colors.white),
                                  child: const Text('Go to Link Child'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: children.length,
                          itemBuilder: (context, idx) {
                            final c = children[idx];
                            final name = c['name']?.toString() ?? 'Child';
                            final childId = c['id'] as int;
                            final code = c['child_code']?.toString() ?? '';

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: borderGrey)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: orange, child: Text(name[0], style: const TextStyle(color: Colors.white))),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 16)),
                                subtitle: Text('Child Code: $code\nTap to inspect career aspirations, qualification, and parent advice.'),
                                isThreeLine: true,
                                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: navy),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChildProfileDetailView(token: widget.token, childId: childId, childName: name),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }
}

class ChildProfileDetailView extends StatefulWidget {
  const ChildProfileDetailView({
    super.key,
    required this.token,
    required this.childId,
    required this.childName,
  });

  final String token;
  final int childId;
  final String childName;

  @override
  State<ChildProfileDetailView> createState() => _ChildProfileDetailViewState();
}

class _ChildProfileDetailViewState extends State<ChildProfileDetailView> {
  Map<String, dynamic>? childInfo;
  Map<String, dynamic>? childProfile;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChildDetails();
  }

  Future<void> _fetchChildDetails() async {
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/auth/child-profile/${widget.childId}'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          childInfo = data['child'];
          childProfile = data['profile'];
        });
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}’s Career Profile', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderGrey),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.childName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: navy)),
                              const SizedBox(height: 4),
                              Text('Child Code: ${childInfo?['child_code'] ?? "N/A"}', style: TextStyle(color: textGrey, fontSize: 13)),
                              const SizedBox(height: 14),
                              _infoRow('Education Level', childProfile?['education_qualification'] ?? 'Not specified'),
                              _infoRow('Marks / Performance', childProfile?['marks'] ?? 'Not specified'),
                              _infoRow('Caste Category', childProfile?['caste_category'] ?? 'Not specified'),
                              _infoRow('Certificate Status', childProfile?['caste_certificate_status'] ?? 'Not specified'),
                              _infoRow('Current Location', childProfile?['location'] ?? 'Not specified'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderGrey),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Aspirations & Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navy)),
                              const SizedBox(height: 12),
                              _infoRow('Career Aspirations', childProfile?['career_aspirations'] ?? 'Exploring options'),
                              _infoRow('Interests', childProfile?['interests'] ?? 'General technical / vocational'),
                              _infoRow('Skills & Strengths', childProfile?['skills'] ?? 'Practical skills'),
                              _infoRow('Family Considerations', childProfile?['family_considerations'] ?? 'None recorded'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F5FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFC2D6FF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.lightbulb_outline, color: orange),
                                  SizedBox(width: 8),
                                  Text('Counselling Tip for Parents', style: TextStyle(fontWeight: FontWeight.bold, color: navy, fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '• Vocational trades (ITI/Polytechnic) take 1-2 years and allow students to start earning through government-sponsored NAPS apprenticeships immediately.\n'
                                '• If your family qualifies for reservation (OBC/SC/ST/EWS), government ITIs and Polytechnics have 100% or 50% fee waivers through MahaDBT.\n'
                                '• Discuss with your child which trades match their hands-on passion rather than peer pressure.',
                                style: TextStyle(height: 1.5, fontSize: 13, color: navy),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textGrey))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: navy, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ==========================================
// 9. PARENT FEATURE 3: EDUCATION OPTIONS
// ==========================================

class ParentEducationOptionsView extends StatelessWidget {
  const ParentEducationOptionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Education Pathways & Budget Guide', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Vocational vs Traditional Route Comparison',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: navy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Understand the investment, duration, and career outcomes for your child.',
                          style: TextStyle(color: textGrey, fontSize: 13),
                        ),
                        const SizedBox(height: 18),
                        _comparisonCard(
                          title: 'Route A: ITI Trade (1-2 Years)',
                          cost: 'Almost FREE in Govt ITIs (₹1,500 - ₹3,000 / yr)',
                          earningAge: 'Age 18–19 years',
                          stipend: '₹8,500 – ₹12,000 / month during Apprenticeship (NAPS)',
                          advantages: '• Fast employment with industry giants (Tata, Mahindra, Railways, MSEDCL)\n• Lateral entry into 2nd year Polytechnic Diploma later\n• High demand for licensed electricians, welders, and CNC operators',
                        ),
                        const SizedBox(height: 14),
                        _comparisonCard(
                          title: 'Route B: Polytechnic Diploma (3 Years)',
                          cost: '₹6,000 – ₹25,000 / yr (Subsidized by MahaDBT)',
                          earningAge: 'Age 19–20 years',
                          stipend: 'Direct Junior Engineer (JE) roles (₹20,000 – ₹35,000 / mo)',
                          advantages: '• Highly respected technical qualification\n• Direct admission into B.Tech 2nd year if student wishes to study further\n• Eligible for government technical exams (Railway RRB JE, PWD, Mahatransco)',
                        ),
                        const SizedBox(height: 14),
                        _comparisonCard(
                          title: 'Route C: B.Voc UGC Degree (3 Years)',
                          cost: '₹15,000 – ₹35,000 / yr',
                          earningAge: 'Age 21 years with 18 months real-world experience',
                          stipend: 'Dual degree advantage: theoretical graduation + hands-on skill',
                          advantages: '• Complete Bachelor’s Degree (eligible for MPSC, UPSC, Banking)\n• 60% of curriculum is practical industry internship\n• Flexible exit points (Certificate at 6 mo, Diploma at 1 yr)',
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

  Widget _comparisonCard({
    required String title,
    required String cost,
    required String earningAge,
    required String stipend,
    required String advantages,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: borderGrey)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: navy)),
            const SizedBox(height: 8),
            Text('Estimated Total Fee: $cost', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Starts Earning: $earningAge ($stipend)', style: TextStyle(color: orange, fontWeight: FontWeight.bold, fontSize: 13)),
            const Divider(height: 20),
            Text(advantages, style: const TextStyle(height: 1.5, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 10. ADMIN & OWNER FEATURES (ALL 3 SCREENS)
// ==========================================

class AdminOverviewView extends StatefulWidget {
  const AdminOverviewView({super.key, required this.token});

  final String token;

  @override
  State<AdminOverviewView> createState() => _AdminOverviewViewState();
}

class _AdminOverviewViewState extends State<AdminOverviewView> {
  Map<String, dynamic>? stats;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/admin/dashboard'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        setState(() => stats = jsonDecode(res.body));
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Analytics & Overview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Platform Metrics Overview', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: navy)),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: _kpiCard('Total Users', '${stats?["total_users"] ?? 0}', Icons.people, navy)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _kpiCard('Students', '${stats?["students"] ?? 0}', Icons.school, orange)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _kpiCard('Parents', '${stats?["parents"] ?? 0}', Icons.family_restroom, Colors.teal)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _kpiCard('Pending Admins', '${stats?["pending_applications"] ?? 0}', Icons.pending_actions, Colors.red)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              const Text('Registered Users by Preferred Language', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: navy)),
                              const SizedBox(height: 10),
                              if (stats?['users_by_language'] is List)
                                ...((stats!['users_by_language'] as List).map((item) {
                                  final lang = item['language']?.toString() ?? '';
                                  final count = item['users'] ?? 0;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(lang, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      trailing: Text('$count users', style: const TextStyle(color: navy, fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  );
                                })),
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

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: textGrey, fontSize: 13)),
        ],
      ),
    );
  }
}

class AdminReviewQueueView extends StatefulWidget {
  const AdminReviewQueueView({super.key, required this.token});

  final String token;

  @override
  State<AdminReviewQueueView> createState() => _AdminReviewQueueViewState();
}

class _AdminReviewQueueViewState extends State<AdminReviewQueueView> {
  String currentStatus = 'pending';
  List<dynamic> applications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/admin/review/applications?status=$currentStatus'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => applications = data['applications'] ?? []);
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  Future<void> _approveApp(int id) async {
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/admin/review/applications/$id/approve'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application approved successfully!')));
        _fetchApplications();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail']?.toString() ?? 'Approval failed.')));
      }
    } catch (_) {}
  }

  Future<void> _rejectApp(int id) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Application'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(hintText: 'Enter reason for rejection...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reject', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true || reasonController.text.trim().isEmpty) return;

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/admin/review/applications/$id/reject'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
        body: jsonEncode({'reason': reasonController.text.trim()}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application rejected.')));
        _fetchApplications();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Application Review', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: ['pending', 'approved', 'rejected'].map((s) {
                  final isSel = s == currentStatus;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.toUpperCase()),
                      selected: isSel,
                      selectedColor: navy,
                      labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87),
                      onSelected: (val) {
                        setState(() => currentStatus = s);
                        _fetchApplications();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : applications.isEmpty
                      ? Center(child: Text('No $currentStatus applications.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: applications.length,
                          itemBuilder: (context, idx) {
                            final app = applications[idx];
                            final id = app['id'] as int;
                            final name = app['name']?.toString() ?? '';
                            final phone = app['phone']?.toString() ?? '';
                            final org = app['organization_name']?.toString() ?? 'N/A';
                            final desig = app['designation']?.toString() ?? 'N/A';
                            final dept = app['department']?.toString() ?? 'N/A';
                            final reason = app['rejection_reason']?.toString();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: borderGrey)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: navy)),
                                        Text(phone, style: TextStyle(color: textGrey, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Org: $org • $desig ($dept)', style: const TextStyle(fontSize: 13)),
                                    if (reason != null && reason.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Reason: $reason', style: const TextStyle(color: Colors.red, fontSize: 12)),
                                    ],
                                    if (currentStatus == 'pending') ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () => _rejectApp(id),
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                            child: const Text('Reject'),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _approveApp(id),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                            child: const Text('Approve'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }
}

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key, required this.token});

  final String token;

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  List<dynamic> users = [];
  String selectedRole = 'All';
  String searchQuery = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final roleParam = selectedRole != 'All' ? '&role=$selectedRole' : '';
      final searchParam = searchQuery.isNotEmpty ? '&search=${Uri.encodeComponent(searchQuery)}' : '';
      final res = await http.get(
        Uri.parse('$apiBaseUrl/admin/users?$roleParam$searchParam'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => users = data['users'] ?? []);
      }
    } catch (_) {}
    setState(() => isLoading = false);
  }

  Future<void> _toggleUserStatus(int userId, bool currentStatus) async {
    try {
      final res = await http.put(
        Uri.parse('$apiBaseUrl/admin/users/$userId/status'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.token}'},
        body: jsonEncode({'is_active': !currentStatus}),
      );
      if (res.statusCode == 200) {
        _fetchUsers();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform User Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search user by name, phone or email...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: pageGrey,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      searchQuery = val;
                      _fetchUsers();
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: ['All', 'student', 'parent', 'admin'].map((r) {
                      final isSel = r == selectedRole;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(r),
                          selected: isSel,
                          selectedColor: navy,
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87),
                          onSelected: (val) {
                            setState(() => selectedRole = r);
                            _fetchUsers();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : users.isEmpty
                      ? const Center(child: Text('No users found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: users.length,
                          itemBuilder: (context, idx) {
                            final u = users[idx];
                            final id = u['id'] as int;
                            final name = u['name']?.toString() ?? '';
                            final phone = u['phone']?.toString() ?? '';
                            final role = u['role']?.toString() ?? '';
                            final isActive = u['is_active'] == true;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: role == 'student' ? orange : navy,
                                  child: Text(name.isNotEmpty ? name[0] : 'U', style: const TextStyle(color: Colors.white)),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('$phone • Role: $role'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.green.shade900 : Colors.red, fontSize: 11)),
                                      backgroundColor: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(isActive ? Icons.toggle_on : Icons.toggle_off, color: isActive ? Colors.green : Colors.grey, size: 32),
                                      onPressed: () => _toggleUserStatus(id, isActive),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const AiCounsellorBar(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 11. COMMON HEADER & NAVIGATION COMPONENTS
// ==========================================

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
                        'Informed vocational decisions, ITI pathways, and scholarships for students & families',
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
    const steps = ['Registration / Sign In', 'Profile Creation', 'Dashboard'];
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
                        backgroundColor: selected || complete ? orange : const Color(0xFF284773),
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

  static const String _counsellorUrl = 'https://counselor-chatbot-two.vercel.app/';

  @override
  Widget build(BuildContext context) => Material(
        color: orange,
        child: InkWell(
          onTap: () async {
            final uri = Uri.parse(_counsellorUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening AI Counsellor...')),
                );
              }
            }
          },
          child: SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smart_toy_outlined, color: Colors.white),
                  SizedBox(width: 9),
                  Text(
                    'Ask the AI Vocational Counsellor (24/7 Guidance)',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.open_in_new, color: Colors.white, size: 16),
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
