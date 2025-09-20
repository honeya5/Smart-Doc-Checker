import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_page.dart';
import 'payment_page.dart';
import 'api_services.dart';
import 'token_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if user is already logged in
  final token = await getToken();

  runApp(MyApp(initialToken: token));
}

class MyApp extends StatelessWidget {
  final String? initialToken;

  MyApp({this.initialToken});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Doc Checker Agent',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: SplashScreen(initialToken: initialToken),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  final String? initialToken;

  SplashScreen({this.initialToken});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    try {
      await Future.delayed(
          Duration(seconds: 2)); // Show splash for minimum time

      final token = widget.initialToken ?? await getToken();

      if (token != null && token.isNotEmpty) {
        // Try to load user profile with the token
        try {
          final profileData = await getProfile(token);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DocCheckerApp(
                  token: token,
                  user: profileData,
                ),
              ),
            );
          }
        } catch (e) {
          print('Failed to load profile: $e');
          // Token might be invalid, clear it and go to auth
          await _clearTokenAndGoToAuth();
        }
      } else {
        _goToAuth();
      }
    } catch (e) {
      print('Error checking auth status: $e');
      _goToAuth();
    }
  }

  Future<void> _clearTokenAndGoToAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('user_data');
    } catch (e) {
      print('Error clearing auth data: $e');
    }
    _goToAuth();
  }

  void _goToAuth() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AuthPage(
            onAuthSuccess: (token, user) async {
              // Save token using the token storage
              await saveToken(token);

              // Save user data to SharedPreferences
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_data', jsonEncode(user));

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => DocCheckerApp(
                    token: token,
                    user: user,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade600,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.document_scanner,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 30),
              Text(
                'Smart Doc Checker',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Intelligent Document Analysis',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 50),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                'Loading...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DocCheckerApp extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  DocCheckerApp({required this.token, required this.user});

  @override
  _DocCheckerAppState createState() => _DocCheckerAppState();
}

class _DocCheckerAppState extends State<DocCheckerApp>
    with TickerProviderStateMixin {
  List<PlatformFile> selectedFiles = [];
  List<Map<String, dynamic>> extractedFilesText = [];
  List<dynamic> contradictions = [];
  Map<String, dynamic> analysisSummary = {};
  Map<String, dynamic> usageStats = {};
  Map<String, dynamic> billingInfo = {};
  String uploadStatus = "";
  bool isUploading = false;
  bool isGeneratingReport = false;
  String? lastReportFile;
  TextEditingController urlController = TextEditingController();
  bool isLoadingProfile = false;

  late Map<String, dynamic> currentUser;
  double accountBalance = 0.0;
  late AnimationController _uploadAnimationController;
  late Animation<double> _uploadAnimation;
  Map<String, dynamic>? lastGeneratedReport;

  @override
  void initState() {
    super.initState();
    currentUser = Map<String, dynamic>.from(widget.user);
    accountBalance = currentUser['account_balance']?.toDouble() ?? 50.0;
    _initializeDemoStats();
    _setupAnimations();
    _loadUserProfile(); // Load fresh profile data
  }

  void _setupAnimations() {
    _uploadAnimationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _uploadAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _uploadAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _uploadAnimationController.dispose();
    urlController.dispose();
    super.dispose();
  }

  // Load user profile using the API service
  Future<void> _loadUserProfile() async {
    setState(() {
      isLoadingProfile = true;
    });

    try {
      final token = await getToken();
      if (token != null) {
        final profile = await getProfile(token);

        setState(() {
          currentUser = Map<String, dynamic>.from(profile);
          accountBalance = currentUser['account_balance']?.toDouble() ?? 50.0;
        });

        // Save updated profile to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', jsonEncode(profile));

        print("User profile loaded: ${profile['username']}");
      } else {
        print("User not logged in");
        _logout();
      }
    } catch (e) {
      print("Failed to load profile: $e");
      // If profile loading fails, we can still continue with cached data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Using cached profile data. Check your connection.'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      setState(() {
        isLoadingProfile = false;
      });
    }
  }

  void _initializeDemoStats() {
    setState(() {
      usageStats = {
        'documents_processed': 0,
        'reports_generated': 0,
        'total_billing': 0.0,
        'session_start': DateTime.now().toIso8601String(),
      };
    });
  }

  Future<void> _logout() async {
    try {
      // Clear stored token and user data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('user_data');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => AuthPage(
              onAuthSuccess: (token, user) async {
                await saveToken(token);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_data', jsonEncode(user));

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DocCheckerApp(
                      token: token,
                      user: user,
                    ),
                  ),
                );
              },
            ),
          ),
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during logout. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        allowedExtensions: ['docx', 'pdf', 'txt'],
        type: FileType.custom,
      );

      if (result != null) {
        setState(() {
          extractedFilesText.clear();
          contradictions.clear();
          uploadStatus = "";

          for (var file in result.files) {
            if (!selectedFiles
                .any((existingFile) => existingFile.name == file.name)) {
              selectedFiles.add(file);
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.length} file(s) selected'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error picking files: $e');
      setState(() {
        uploadStatus = "Error selecting files: ${e.toString()}";
      });
    }
  }

  Future<void> uploadFiles() async {
    if (selectedFiles.isEmpty) {
      setState(() {
        uploadStatus = "No files selected";
      });
      return;
    }

    double costPerDocument = 2.50;
    double totalCost = selectedFiles.length * costPerDocument;

    if (accountBalance < totalCost) {
      setState(() {
        uploadStatus =
            "Insufficient funds: Need ₹${totalCost.toStringAsFixed(2)}, but only have ₹${accountBalance.toStringAsFixed(2)}";
      });
      _showInsufficientFundsDialog(totalCost);
      return;
    }

    setState(() {
      isUploading = true;
      uploadStatus = "Analyzing files...";
    });

    _uploadAnimationController.forward();

    try {
      // In a real implementation, you would call your backend API here
      // For demo purposes, we'll simulate the analysis
      await Future.delayed(Duration(seconds: 3));

      List<Map<String, dynamic>> processedFiles = [];
      List<Map<String, dynamic>> demoContradictions = [];

      for (var file in selectedFiles) {
        processedFiles.add({
          'filename': file.name,
          'text': 'Demo analyzed content from ${file.name}',
          'size': file.size,
          'type': file.extension ?? 'unknown',
        });
      }

      if (selectedFiles.length > 1) {
        demoContradictions = _generateDemoContradictions(selectedFiles);
      }

      setState(() {
        accountBalance -= totalCost;
        extractedFilesText = processedFiles;
        contradictions = demoContradictions;
        uploadStatus =
            "Analysis complete! Found ${demoContradictions.length} contradictions.";
        isUploading = false;

        usageStats['documents_processed'] =
            (usageStats['documents_processed'] ?? 0) + selectedFiles.length;
        usageStats['total_billing'] =
            (usageStats['total_billing'] ?? 0.0) + totalCost;

        analysisSummary = {
          'total_files': selectedFiles.length,
          'valid_files': selectedFiles.length,
          'contradictions_found': demoContradictions.length,
          'processing_time': DateTime.now().toIso8601String(),
          'accuracy_score': 95.8,
        };

        billingInfo = {
          'documents_cost': totalCost,
          'report_cost': 0.0,
          'total_cost': totalCost,
          'timestamp': DateTime.now().toIso8601String(),
        };
      });

      await _saveBalanceToPrefs();
      _uploadAnimationController.reverse();
    } catch (e) {
      print('Error during file analysis: $e');
      setState(() {
        isUploading = false;
        uploadStatus = "Error analyzing files: ${e.toString()}";
      });
      _uploadAnimationController.reverse();
    }
  }

  List<Map<String, dynamic>> _generateDemoContradictions(
      List<PlatformFile> files) {
    List<Map<String, dynamic>> contradictions = [];

    if (files.length >= 2) {
      contradictions.add({
        'id': 'demo1',
        'doc1_name': files[0].name,
        'doc2_name': files[1].name,
        'doc1_text': 'Attendance must be at least 75% for eligibility',
        'doc2_text': 'Minimum attendance requirement is 80% for all students',
        'type': 'Percentage Conflict',
        'explanation':
            'Two documents specify different attendance requirements: 75% vs 80%. This creates ambiguity about which standard to follow.',
        'suggestion':
            'Standardize the attendance requirement. Recommend using 80% for stricter compliance.',
        'severity': 'High',
        'confidence': 92.5,
      });

      if (files.length >= 3) {
        contradictions.add({
          'id': 'demo2',
          'doc1_name': files[0].name,
          'doc2_name': files[2].name,
          'doc1_text': 'Submit assignment within 7 days of deadline',
          'doc2_text': 'Late submissions allowed up to 3 days after due date',
          'type': 'Time Period Conflict',
          'explanation':
              'Conflicting time requirements found: 7 days vs 3 days. This could lead to confusion about actual deadlines.',
          'suggestion':
              'Establish a single, clear time requirement. Recommend using 3 days to ensure timely submissions.',
          'severity': 'Medium',
          'confidence': 87.3,
        });
      }

      if (files.length >= 4) {
        contradictions.add({
          'id': 'demo3',
          'doc1_name': files[1].name,
          'doc2_name': files[3].name,
          'doc1_text': 'Maximum file size allowed is 10MB',
          'doc2_text': 'File upload limit set to 5MB per document',
          'type': 'Size Limit Conflict',
          'explanation':
              'Different maximum file sizes specified: 10MB vs 5MB. This inconsistency may cause user confusion.',
          'suggestion':
              'Standardize file size limit across all documents. Consider using 10MB for better user experience.',
          'severity': 'Low',
          'confidence': 78.9,
        });
      }
    }

    return contradictions;
  }

  Future<void> _saveBalanceToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currentUser['account_balance'] = accountBalance;
      await prefs.setString('user_data', jsonEncode(currentUser));
    } catch (e) {
      print('Error saving balance: $e');
    }
  }

  void _showInsufficientFundsDialog(dynamic requiredAmount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.orange),
            SizedBox(width: 8),
            Text('Insufficient Funds'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Required: ₹${requiredAmount.toStringAsFixed(2)}'),
                  Text(
                      'Current Balance: ₹${accountBalance.toStringAsFixed(2)}'),
                  Text(
                    'Shortfall: ₹${(requiredAmount - accountBalance).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'You need to add funds to continue with document analysis.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openPaymentPage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
            child: Text('Add Funds'),
          ),
        ],
      ),
    );
  }

  void _openPaymentPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentPage(
          currentBalance: accountBalance,
          onPaymentSuccess: (newBalance) {
            setState(() {
              accountBalance = newBalance;
            });
            _saveBalanceToPrefs();
          },
        ),
      ),
    );
  }

  Future<void> generateReport() async {
    if (contradictions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('No contradictions to report. Analyze documents first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    double reportCost = 5.0;
    if (accountBalance < reportCost) {
      _showInsufficientFundsDialog(<String, dynamic>{
        'required': reportCost,
        'balance': accountBalance,
        'message': 'Not enough funds for report generation',
      });
      return;
    }

    setState(() {
      isGeneratingReport = true;
    });

    try {
      await Future.delayed(Duration(seconds: 2));

      // Generate demo report
      Map<String, dynamic> demoReport = {
        'metadata': {
          'generated_at': DateTime.now().toIso8601String(),
          'documents_analyzed': selectedFiles.length,
          'contradictions_found': contradictions.length,
          'report_id': 'RPT_${DateTime.now().millisecondsSinceEpoch}',
        },
        'executive_summary': {
          'total_issues': contradictions.length,
          'high_priority':
              contradictions.where((c) => c['severity'] == 'High').length,
          'medium_priority':
              contradictions.where((c) => c['severity'] == 'Medium').length,
          'low_priority':
              contradictions.where((c) => c['severity'] == 'Low').length,
          'average_confidence': contradictions.isNotEmpty
              ? (contradictions
                          .map((c) => c['confidence'] ?? 0.0)
                          .reduce((a, b) => a + b) /
                      contradictions.length)
                  .toStringAsFixed(1)
              : '0.0',
        },
        'contradictions': contradictions,
        'recommendations': {
          'high_priority': contradictions
              .where((c) => c['severity'] == 'High')
              .map((c) => c['suggestion'])
              .toList(),
          'medium_priority': contradictions
              .where((c) => c['severity'] == 'Medium')
              .map((c) => c['suggestion'])
              .toList(),
          'low_priority': contradictions
              .where((c) => c['severity'] == 'Low')
              .map((c) => c['suggestion'])
              .toList(),
        },
        'action_items': [
          'Review and standardize conflicting requirements across all documents',
          'Establish clear guidelines for document consistency',
          'Implement regular document review processes',
          'Create a centralized document management system',
        ],
      };

      setState(() {
        isGeneratingReport = false;
        accountBalance -= reportCost;
        lastGeneratedReport = demoReport;
        usageStats['reports_generated'] =
            (usageStats['reports_generated'] ?? 0) + 1;
        usageStats['total_billing'] =
            (usageStats['total_billing'] ?? 0.0) + reportCost;

        billingInfo['report_cost'] = reportCost;
        billingInfo['total_cost'] =
            (billingInfo['total_cost'] ?? 0.0) + reportCost;
      });

      await _saveBalanceToPrefs();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Report generated successfully! ₹${reportCost.toStringAsFixed(2)} deducted.')),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View Report',
            textColor: Colors.white,
            onPressed: () => _showReportDialog(demoReport),
          ),
        ),
      );
    } catch (e) {
      setState(() {
        isGeneratingReport = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating report: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showReportDialog(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.assessment, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Contradiction Analysis Report',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Generated: ${report['metadata']['generated_at']}'),
                      SizedBox(height: 10),
                      Text(
                          'Documents Analyzed: ${report['metadata']['documents_analyzed']}'),
                      Text(
                          'Contradictions Found: ${report['metadata']['contradictions_found']}'),
                      SizedBox(height: 15),
                      Text(
                          'High Priority Issues: ${report['recommendations']['high_priority'].length}'),
                      Text(
                          'Medium Priority Issues: ${report['recommendations']['medium_priority'].length}'),
                      Text(
                          'Low Priority Issues: ${report['recommendations']['low_priority'].length}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade600,
                  child: Text(
                    currentUser['username']
                            ?.toString()
                            .substring(0, 1)
                            .toUpperCase() ??
                        'U',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser['username'] ?? 'User',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        currentUser['email'] ?? 'No email',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '₹${accountBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),

                SizedBox(width: 8), // Add spacing before the button
                ElevatedButton(
                  onPressed: _openPaymentPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text('Add Funds', style: TextStyle(fontSize: 12)),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: _logout,
                  icon: Icon(Icons.logout, color: Colors.red),
                  tooltip: 'Logout',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageStats() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Statistics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Documents',
                    '${usageStats['documents_processed'] ?? 0}',
                    Icons.description,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Reports',
                    '${usageStats['reports_generated'] ?? 0}',
                    Icons.assessment,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Spent',
                    '₹${(usageStats['total_billing'] ?? 0.0).toStringAsFixed(2)}',
                    Icons.account_balance_wallet,
                    Colors.green,
                  ),
                ),
              ],
            ),
            if (analysisSummary.isNotEmpty) ...[
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Analysis Summary:',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${analysisSummary['valid_files']}/${analysisSummary['total_files']} docs",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (lastGeneratedReport != null) ...[
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.assessment, size: 16, color: Colors.blue.shade600),
                  SizedBox(width: 8),
                  Text(
                    'Latest Report Available',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  Spacer(),
                  TextButton(
                    onPressed: () => _showReportDialog(lastGeneratedReport!),
                    child: Text('View Report'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildContradictionsSection() {
    if (contradictions.isEmpty && extractedFilesText.isNotEmpty) {
      if (extractedFilesText.length < 2) {
        return Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.info_outline, color: Colors.blue, size: 48),
                ),
                SizedBox(height: 16),
                Text(
                  'Need More Documents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Upload at least 2 documents to detect contradictions between them.',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: pickFiles,
                  icon: Icon(Icons.add),
                  label: Text('Add More Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        return Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.check_circle, color: Colors.green, size: 48),
                ),
                SizedBox(height: 16),
                Text(
                  'No Contradictions Found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your ${extractedFilesText.length} documents appear to be consistent with each other.',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                if (analysisSummary['accuracy_score'] != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Accuracy Score: ${analysisSummary['accuracy_score']}%',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    if (contradictions.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Contradictions Found (${contradictions.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Spacer(),
            ElevatedButton.icon(
              onPressed: (contradictions.isNotEmpty && !isGeneratingReport)
                  ? generateReport
                  : null,
              icon: isGeneratingReport
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Icon(Icons.assessment),
              label: Text(
                  isGeneratingReport ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        ...contradictions
            .map((contradiction) => _buildContradictionCard(contradiction))
            .toList(),
      ],
    );
  }

  Widget _buildContradictionCard(Map<String, dynamic> contradiction) {
    Color severityColor = Colors.orange;
    IconData severityIcon = Icons.warning;

    switch (contradiction['severity']?.toLowerCase()) {
      case 'high':
        severityColor = Colors.red;
        severityIcon = Icons.error;
        break;
      case 'medium':
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      case 'low':
        severityColor = Colors.yellow.shade700;
        severityIcon = Icons.info;
        break;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(severityIcon, color: severityColor, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    contradiction['type'] ?? 'Contradiction',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: severityColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    contradiction['severity']?.toUpperCase() ?? 'UNKNOWN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
              ],
            ),
            if (contradiction['confidence'] != null) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Confidence: ${contradiction['confidence']}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contradiction['doc1_name'] ?? 'Document 1',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          contradiction['doc1_text'] ?? 'No text available',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Icon(Icons.compare_arrows, color: Colors.grey.shade400),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contradiction['doc2_name'] ?? 'Document 2',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          contradiction['doc2_text'] ?? 'No text available',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (contradiction['explanation'] != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explanation:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.amber.shade700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      contradiction['explanation'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (contradiction['suggestion'] != null) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggestion:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      contradiction['suggestion'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Doc Checker'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          if (isLoadingProfile)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _loadUserProfile,
              icon: Icon(Icons.refresh),
              tooltip: 'Refresh Profile',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUserProfileSection(),
            SizedBox(height: 16),
            _buildUsageStats(),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade50, Colors.indigo.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.indigo.shade600),
                      SizedBox(width: 8),
                      Text(
                        'Document Analysis Pricing',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Document Analysis: ₹2.50 per document\n• Report Generation: ₹5.00 per report\n• Minimum 2 documents required for contradiction detection',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo.shade600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (isUploading || isLoadingProfile) ? null : pickFiles,
                    icon: Icon(Icons.file_upload),
                    label: Text(selectedFiles.isEmpty
                        ? "Select Multiple Files"
                        : "Add More Files (${selectedFiles.length})"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (selectedFiles.isEmpty ||
                            isUploading ||
                            isLoadingProfile)
                        ? null
                        : uploadFiles,
                    icon: isUploading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.analytics),
                    label: Text(isUploading ? "Analyzing..." : "Analyze Files"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: (selectedFiles.length < 2)
                          ? Colors.grey.shade400
                          : Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (selectedFiles.isNotEmpty && selectedFiles.length < 2) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange.shade700, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Upload at least 2 documents to detect contradictions between them',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (selectedFiles.isNotEmpty) ...[
              SizedBox(height: 16),
              Card(
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open,
                                  size: 20, color: Colors.blue.shade600),
                              SizedBox(width: 8),
                              Text(
                                'Selected Files (${selectedFiles.length})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedFiles.clear();
                                extractedFilesText.clear();
                                contradictions.clear();
                                uploadStatus = "";
                                analysisSummary.clear();
                              });
                            },
                            icon: Icon(Icons.clear_all, size: 16),
                            label: Text('Clear All'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                      if (selectedFiles.length >= 2) ...[
                        SizedBox(height: 8),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            'Cost: ₹${(selectedFiles.length * 2.50).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 12),
                      ...selectedFiles.asMap().entries.map((entry) {
                        int index = entry.key;
                        PlatformFile file = entry.value;
                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  _getFileIcon(file.extension),
                                  size: 16,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      '${(file.size / 1024).toStringAsFixed(1)} KB • ${file.extension?.toUpperCase() ?? 'Unknown'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    selectedFiles.removeAt(index);
                                    if (selectedFiles.isEmpty) {
                                      extractedFilesText.clear();
                                      contradictions.clear();
                                      uploadStatus = "";
                                      analysisSummary.clear();
                                    }
                                  });
                                },
                                icon:
                                    Icon(Icons.remove_circle_outline, size: 18),
                                padding: EdgeInsets.zero,
                                constraints:
                                    BoxConstraints(minWidth: 32, minHeight: 32),
                                color: Colors.red.shade600,
                                tooltip: 'Remove file',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
            if (uploadStatus.isNotEmpty) ...[
              SizedBox(height: 16),
              AnimatedContainer(
                duration: Duration(milliseconds: 300),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: uploadStatus.contains("error") ||
                          uploadStatus.contains("Insufficient")
                      ? Colors.red.shade50
                      : uploadStatus.contains("complete")
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: uploadStatus.contains("error") ||
                            uploadStatus.contains("Insufficient")
                        ? Colors.red.shade200
                        : uploadStatus.contains("complete")
                            ? Colors.green.shade200
                            : Colors.blue.shade200,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: uploadStatus.contains("error") ||
                                uploadStatus.contains("Insufficient")
                            ? Colors.red.shade100
                            : uploadStatus.contains("complete")
                                ? Colors.green.shade100
                                : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        uploadStatus.contains("error") ||
                                uploadStatus.contains("Insufficient")
                            ? Icons.error
                            : uploadStatus.contains("complete")
                                ? Icons.check_circle
                                : Icons.info,
                        color: uploadStatus.contains("error") ||
                                uploadStatus.contains("Insufficient")
                            ? Colors.red.shade700
                            : uploadStatus.contains("complete")
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uploadStatus,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: uploadStatus.contains("error") ||
                                  uploadStatus.contains("Insufficient")
                              ? Colors.red.shade800
                              : uploadStatus.contains("complete")
                                  ? Colors.green.shade800
                                  : Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (extractedFilesText.isNotEmpty) ...[
              SizedBox(height: 16),
              _buildContradictionsSection(),
            ],
          ],
        ),
      ),
      floatingActionButton: selectedFiles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: (isUploading || selectedFiles.length < 2)
                  ? null
                  : uploadFiles,
              backgroundColor: selectedFiles.length < 2
                  ? Colors.grey
                  : Colors.green.shade600,
              foregroundColor: Colors.white,
              icon: isUploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.analytics),
              label: Text(isUploading ? 'Analyzing...' : 'Analyze Now'),
            )
          : null,
    );
  }
}
