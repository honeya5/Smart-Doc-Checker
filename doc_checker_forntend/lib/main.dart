import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_page.dart';
import 'payment_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Doc Checker Agent',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userDataString = prefs.getString('user_data');

    await Future.delayed(Duration(seconds: 2));

    if (token != null && userDataString != null) {
      try {
        final userData = jsonDecode(userDataString);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DocCheckerApp(
              token: token,
              user: userData,
            ),
          ),
        );
      } catch (e) {
        _goToAuth();
      }
    } else {
      _goToAuth();
    }
  }

  void _goToAuth() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AuthPage(
          onAuthSuccess: (token, user) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade600,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.document_scanner,
              size: 100,
              color: Colors.white,
            ),
            SizedBox(height: 20),
            Text(
              'Smart Doc Checker',
              style: TextStyle(
                fontSize: 24,
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
            SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
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

class _DocCheckerAppState extends State<DocCheckerApp> {
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
  
  late Map<String, dynamic> currentUser;
  double accountBalance = 0.0;

  @override
  void initState() {
    super.initState();
    currentUser = Map<String, dynamic>.from(widget.user);
    accountBalance = currentUser['account_balance']?.toDouble() ?? 50.0; // Default demo balance
    _initializeDemoStats();
  }

  // Initialize demo statistics for frontend-only simulation
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AuthPage(
          onAuthSuccess: (token, user) {
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

  Future<void> pickFiles() async {
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
          if (!selectedFiles.any((existingFile) => existingFile.name == file.name)) {
            selectedFiles.add(file);
          }
        }
      });
    }
  }

  // Demo function to simulate document analysis (frontend-only)
  Future<void> uploadFiles() async {
    if (selectedFiles.isEmpty) {
      setState(() {
        uploadStatus = "No files selected";
      });
      return;
    }

    // Check balance for demo (₹2.50 per document)
    double costPerDocument = 2.50;
    double totalCost = selectedFiles.length * costPerDocument;
    
    if (accountBalance < totalCost) {
      setState(() {
        uploadStatus = "Insufficient funds: Need ₹${totalCost.toStringAsFixed(2)}, but only have ₹${accountBalance.toStringAsFixed(2)}";
      });
      _showInsufficientFundsDialog(totalCost);
      return;
    }

    setState(() {
      isUploading = true;
      uploadStatus = "Analyzing files...";
    });

    // Simulate processing time
    await Future.delayed(Duration(seconds: 3));

    // Simulate file processing and contradiction detection
    List<Map<String, dynamic>> processedFiles = [];
    List<Map<String, dynamic>> demoContradictions = [];

    for (var file in selectedFiles) {
      processedFiles.add({
        'filename': file.name,
        'text': 'Demo text content from ${file.name}',
        'size': file.size,
      });
    }

    // Generate demo contradictions if we have multiple files
    if (selectedFiles.length > 1) {
      demoContradictions = _generateDemoContradictions(selectedFiles);
    }

    // Deduct cost from balance
    setState(() {
      accountBalance -= totalCost;
      extractedFilesText = processedFiles;
      contradictions = demoContradictions;
      uploadStatus = "Analysis complete!";
      isUploading = false;
      
      // Update usage stats
      usageStats['documents_processed'] = (usageStats['documents_processed'] ?? 0) + selectedFiles.length;
      usageStats['total_billing'] = (usageStats['total_billing'] ?? 0.0) + totalCost;
      
      analysisSummary = {
        'total_files': selectedFiles.length,
        'valid_files': selectedFiles.length,
        'contradictions_found': demoContradictions.length,
        'processing_time': DateTime.now().toIso8601String(),
      };
      
      billingInfo = {
        'documents_cost': totalCost,
        'report_cost': 0.0,
        'total_cost': totalCost,
      };
    });

    // Save updated balance to SharedPreferences
    _saveBalanceToPrefs();
  }

  // Generate demo contradictions for presentation
  List<Map<String, dynamic>> _generateDemoContradictions(List<PlatformFile> files) {
    List<Map<String, dynamic>> contradictions = [];
    
    if (files.length >= 2) {
      contradictions.add({
        'id': 'demo1',
        'doc1_name': files[0].name,
        'doc2_name': files[1].name,
        'doc1_text': 'Attendance must be at least 75% for eligibility',
        'doc2_text': 'Minimum attendance requirement is 80% for all students',
        'type': 'Percentage Conflict',
        'explanation': 'Two documents specify different attendance requirements: 75% vs 80%. This creates ambiguity about which standard to follow.',
        'suggestion': 'Standardize the attendance requirement. Recommend using 80% for stricter compliance.',
        'severity': 'High'
      });

      if (files.length >= 3) {
        contradictions.add({
          'id': 'demo2',
          'doc1_name': files[0].name,
          'doc2_name': files[2].name,
          'doc1_text': 'Submit assignment within 7 days of deadline',
          'doc2_text': 'Late submissions allowed up to 3 days after due date',
          'type': 'Time Period Conflict',
          'explanation': 'Conflicting time requirements found: 7 days vs 3 days. This could lead to confusion about actual deadlines.',
          'suggestion': 'Establish a single, clear time requirement. Recommend using 3 days to ensure timely submissions.',
          'severity': 'Medium'
        });
      }
    }
    
    return contradictions;
  }

  Future<void> _saveBalanceToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    currentUser['account_balance'] = accountBalance;
    await prefs.setString('user_data', jsonEncode(currentUser));
  }

  void _showInsufficientFundsDialog(double requiredAmount) {
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
            Text('Required: ₹${requiredAmount.toStringAsFixed(2)}'),
            Text('Current Balance: ₹${accountBalance.toStringAsFixed(2)}'),
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

  // Demo report generation
  Future<void> generateReport() async {
    if (contradictions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No contradictions to report')),
      );
      return;
    }

    double reportCost = 5.0;
    if (accountBalance < reportCost) {
      _showInsufficientFundsDialog(reportCost);
      return;
    }

    setState(() {
      isGeneratingReport = true;
    });

    await Future.delayed(Duration(seconds: 2));

    setState(() {
      isGeneratingReport = false;
      accountBalance -= reportCost;
      usageStats['reports_generated'] = (usageStats['reports_generated'] ?? 0) + 1;
      usageStats['total_billing'] = (usageStats['total_billing'] ?? 0.0) + reportCost;
    });

    _saveBalanceToPrefs();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Report generated successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildContradictionsSection() {
    if (contradictions.isEmpty && extractedFilesText.isNotEmpty) {
      if (extractedFilesText.length < 2) {
        return Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 48),
                SizedBox(height: 8),
                Text(
                  'Need More Documents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Upload at least 2 documents to detect contradictions between them.',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: pickFiles,
                  icon: Icon(Icons.add),
                  label: Text('Add More Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        return Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 8),
                Text(
                  'No Contradictions Found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your ${extractedFilesText.length} documents appear to be consistent with each other.',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
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
              onPressed: (contradictions.isNotEmpty && !isGeneratingReport) ? generateReport : null,
              icon: isGeneratingReport 
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Icon(Icons.assessment),
              label: Text(isGeneratingReport ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        ...contradictions.map((contradiction) => _buildContradictionCard(contradiction)).toList(),
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
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.orange.shade600),
                        SizedBox(width: 4),
                        Text(
                          'Explanation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.orange.shade600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      contradiction['explanation'],
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                    Row(
                      children: [
                        Icon(Icons.thumb_up_outlined, size: 16, color: Colors.green.shade600),
                        SizedBox(width: 4),
                        Text(
                          'Suggestion',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      contradiction['suggestion'],
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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

  Widget _buildUserProfileSection() {
    return Card(
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
                    currentUser['username'][0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser['username'],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        currentUser['email'],
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _logout,
                  icon: Icon(Icons.logout),
                  tooltip: 'Logout',
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Account Balance',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${accountBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _openPaymentPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: Text('Add Funds', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageStats() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Current Session Stats',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard(
                  'Documents Processed', 
                  usageStats['documents_processed']?.toString() ?? '0',
                  Icons.description,
                  Colors.blue
                ),
                _buildStatCard(
                  'Reports Generated', 
                  usageStats['reports_generated']?.toString() ?? '0',
                  Icons.assessment,
                  Colors.orange
                ),
                _buildStatCard(
                  'Session Billing', 
                  '₹${usageStats['total_billing']?.toStringAsFixed(2) ?? '0.00'}',
                  Icons.attach_money,
                  Colors.green
                ),
              ],
            ),
            if (billingInfo.isNotEmpty) ...[
              SizedBox(height: 12),
              Divider(),
              Text(
                'Last Transaction:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 4),
              Text('Documents Cost: ₹${billingInfo['documents_cost']?.toStringAsFixed(2) ?? '0.00'}'),
              Text('Report Cost: ₹${billingInfo['report_cost']?.toStringAsFixed(2) ?? '0.00'}'),
              Text('Transaction Total: ₹${billingInfo['total_cost']?.toStringAsFixed(2) ?? '0.00'}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Smart Doc Checker Agent"),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          if (analysisSummary.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  "${analysisSummary['valid_files']}/${analysisSummary['total_files']} docs",
                  style: TextStyle(fontSize: 12),
                ),
              ),
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isUploading ? null : pickFiles,
                    icon: Icon(Icons.file_upload),
                    label: Text(selectedFiles.isEmpty ? "Select Multiple Files" : "Add More Files"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (selectedFiles.isEmpty || isUploading) ? null : uploadFiles,
                    icon: isUploading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.analytics),
                    label: Text(isUploading ? "Analyzing..." : "Analyze Files"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: selectedFiles.length < 2 ? Colors.grey.shade400 : Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (selectedFiles.isNotEmpty && selectedFiles.length < 2) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange.shade700, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select at least 2 documents to detect contradictions',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
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
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Selected Files (${selectedFiles.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedFiles.clear();
                                extractedFilesText.clear();
                                contradictions.clear();
                                uploadStatus = "";
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
                      SizedBox(height: 8),
                      ...selectedFiles.asMap().entries.map((entry) {
                        int index = entry.key;
                        PlatformFile file = entry.value;
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.insert_drive_file, size: 16, color: Colors.grey),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                '${(file.size / 1024).toStringAsFixed(1)} KB',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    selectedFiles.removeAt(index);
                                    if (selectedFiles.isEmpty) {
                                      extractedFilesText.clear();
                                      contradictions.clear();
                                      uploadStatus = "";
                                    }
                                  });
                                },
                                icon: Icon(Icons.remove_circle_outline, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                                color: Colors.red.shade600,
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
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: uploadStatus.contains("error") || uploadStatus.contains("Insufficient")
                      ? Colors.red.shade50
                      : uploadStatus.contains("complete")
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: uploadStatus.contains("error") || uploadStatus.contains("Insufficient")
                        ? Colors.red.shade200
                        : uploadStatus.contains("complete")
                            ? Colors.green.shade200
                            : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      uploadStatus.contains("error") || uploadStatus.contains("Insufficient")
                          ? Icons.error
                          : uploadStatus.contains("complete")
                              ? Icons.check_circle
                              : Icons.info,
                      color: uploadStatus.contains("error") || uploadStatus.contains("Insufficient")
                          ? Colors.red.shade700
                          : uploadStatus.contains("complete")
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                    ),
                    SizedBox(width: 8),
                    Expanded(child: Text(uploadStatus)),
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
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }
}