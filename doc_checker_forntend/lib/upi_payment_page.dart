import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class UpiPaymentPage extends StatefulWidget {
  final double amount;
  final String paymentMethod;
  final Function(double amount) onPaymentSuccess;

  UpiPaymentPage({
    required this.amount,
    required this.paymentMethod,
    required this.onPaymentSuccess,
  });

  @override
  _UpiPaymentPageState createState() => _UpiPaymentPageState();
}

class _UpiPaymentPageState extends State<UpiPaymentPage>
    with SingleTickerProviderStateMixin {
  final _upiController = TextEditingController();
  bool _isProcessing = false;
  bool _showScanner = false;
  bool _paymentCompleted = false;
  String _error = '';
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  // Generate a random transaction ID for simulation
  final String _transactionId = 'TXN${Random().nextInt(999999999)}';
  final String _merchantUpiId = 'merchant@paytm';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _upiController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleScanner() {
    setState(() {
      _showScanner = !_showScanner;
      _error = '';
    });
  }

  Future<void> _simulatePayment() async {
    if (!_showScanner && _upiController.text.trim().isEmpty) {
      setState(() {
        _error = 'Please enter your UPI ID';
      });
      return;
    }

    // Basic UPI ID validation (only when not using scanner)
    if (!_showScanner && !_isValidUpiId(_upiController.text.trim())) {
      setState(() {
        _error = 'Please enter a valid UPI ID (e.g., username@bank)';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = '';
    });

    // Simulate payment processing time
    await Future.delayed(Duration(seconds: 3));

    // Simulate payment success (you can add logic for random failures if needed)
    setState(() {
      _isProcessing = false;
      _paymentCompleted = true;
    });

    _animationController.forward();

    // Auto-close after success and call the callback
    Future.delayed(Duration(seconds: 2), () {
      widget.onPaymentSuccess(widget.amount);
      Navigator.of(context).pop();
      Navigator.of(context).pop(); // Go back to main page
    });
  }

  bool _isValidUpiId(String upiId) {
    final RegExp upiRegex = RegExp(r'^[\w.-]+@[\w.-]+$');
    return upiRegex.hasMatch(upiId);
  }

  Widget _buildPaymentMethod() {
    IconData icon;
    Color color;
    String description;

    switch (widget.paymentMethod.toLowerCase()) {
      case 'credit/debit card':
        icon = Icons.credit_card;
        color = Colors.blue;
        description = 'Pay securely using UPI for card payments';
        break;
      case 'paypal':
        icon = Icons.account_balance_wallet;
        color = Colors.orange;
        description = 'Complete PayPal payment via UPI gateway';
        break;
      case 'bank transfer':
        icon = Icons.account_balance;
        color = Colors.green;
        description = 'Direct bank transfer using UPI';
        break;
      default:
        icon = Icons.payment;
        color = Colors.purple;
        description = 'Complete payment using UPI';
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.paymentMethod,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Amount to Pay',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '₹${widget.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Transaction ID: $_transactionId',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpiInput() {
    if (_showScanner) {
      return _buildQRScanner();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter UPI ID',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 12),
        TextField(
          controller: _upiController,
          decoration: InputDecoration(
            hintText: 'e.g., yourname@paytm',
            prefixIcon: Icon(Icons.account_balance_wallet),
            suffixIcon: IconButton(
              icon: Icon(Icons.qr_code_scanner),
              onPressed: _toggleScanner,
              tooltip: 'Scan QR Code',
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 8),
        Text(
          'Enter your UPI ID or tap the QR icon to scan',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildQRScanner() {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'QR Code Scanner',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            Spacer(),
            TextButton.icon(
              onPressed: _toggleScanner,
              icon: Icon(Icons.keyboard),
              label: Text('Enter UPI ID'),
            ),
          ],
        ),
        SizedBox(height: 16),
        Container(
          height: 200,
          width: 200,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code,
                size: 80,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 12),
              Text(
                'QR Scanner Simulation',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Scan any QR code to proceed',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.blue.shade700, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This is a simulation. Click "Pay Now" to proceed with demo payment.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantInfo() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Merchant Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.business, size: 16, color: Colors.grey.shade600),
              SizedBox(width: 8),
              Text('Smart Doc Checker', style: TextStyle(fontSize: 12)),
            ],
          ),
          SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.account_balance_wallet, size: 16, color: Colors.grey.shade600),
              SizedBox(width: 8),
              Text(_merchantUpiId, style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessAnimation() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade200, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green.shade600,
                size: 64,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Payment Successful!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '₹${widget.amount.toStringAsFixed(2)} has been added to your account',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Transaction ID: $_transactionId',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentCompleted) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: _buildSuccessAnimation(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('UPI Payment'),
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAmountSection(),
            SizedBox(height: 20),
            _buildPaymentMethod(),
            SizedBox(height: 20),
            _buildMerchantInfo(),
            SizedBox(height: 24),
            _buildUpiInput(),
            SizedBox(height: 24),
            if (_error.isNotEmpty)
              Container(
                padding: EdgeInsets.all(12),
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ElevatedButton(
              onPressed: _isProcessing ? null : _simulatePayment,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isProcessing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Processing Payment...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payment),
                        SizedBox(width: 8),
                        Text(
                          'Pay Now',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.amber.shade700, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a demo payment for HackWithHyderabad. No real money will be transferred.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}