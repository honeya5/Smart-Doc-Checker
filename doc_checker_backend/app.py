import os
from flask import Flask, request, jsonify, send_file, session
from flask_cors import CORS
from docx import Document
import PyPDF2
import io
import re
import json
from datetime import datetime, timedelta
from difflib import SequenceMatcher
import threading
import time
import requests
from dataclasses import dataclass
from typing import List, Dict, Any
import uuid
import sqlite3
import hashlib
import jwt
from functools import wraps
import stripe

app = Flask(__name__)

# Use environment variables for production security
app.secret_key = os.environ.get('SECRET_KEY', 'your-secret-key-change-in-production')
CORS(app, supports_credentials=True)

# Stripe configuration using environment variables
stripe.api_key = os.environ.get('STRIPE_API_KEY', 'sk_test_your_stripe_secret_key_here')
STRIPE_PUBLISHABLE_KEY = os.environ.get('STRIPE_PUBLISHABLE_KEY', 'pk_test_your_stripe_publishable_key_here')

# Database configuration
DATABASE_PATH = os.environ.get('DATABASE_PATH', 'doc_checker.db')

# Database initialization
def init_database():
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    # Users table
    c.execute('''CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username TEXT UNIQUE NOT NULL,
                    email TEXT UNIQUE NOT NULL,
                    password_hash TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    account_balance REAL DEFAULT 0.0,
                    subscription_type TEXT DEFAULT 'free'
                )''')
    
    # Usage tracking table (per user session)
    c.execute('''CREATE TABLE IF NOT EXISTS user_sessions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    session_id TEXT UNIQUE NOT NULL,
                    documents_processed INTEGER DEFAULT 0,
                    reports_generated INTEGER DEFAULT 0,
                    total_billing REAL DEFAULT 0.0,
                    session_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    is_active BOOLEAN DEFAULT TRUE,
                    FOREIGN KEY (user_id) REFERENCES users (id)
                )''')
    
    # Transactions table
    c.execute('''CREATE TABLE IF NOT EXISTS transactions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    transaction_type TEXT NOT NULL,
                    amount REAL NOT NULL,
                    description TEXT,
                    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    payment_method TEXT,
                    stripe_payment_intent_id TEXT,
                    status TEXT DEFAULT 'completed',
                    FOREIGN KEY (user_id) REFERENCES users (id)
                )''')
    
    # Analysis history table
    c.execute('''CREATE TABLE IF NOT EXISTS analysis_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    session_id TEXT NOT NULL,
                    analysis_id TEXT UNIQUE NOT NULL,
                    documents_count INTEGER,
                    contradictions_found INTEGER,
                    cost REAL,
                    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    report_generated BOOLEAN DEFAULT FALSE,
                    FOREIGN KEY (user_id) REFERENCES users (id)
                )''')
    
    # Monitored documents table (per user)
    c.execute('''CREATE TABLE IF NOT EXISTS monitored_documents (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    url TEXT NOT NULL,
                    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    is_active BOOLEAN DEFAULT TRUE,
                    last_check TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES users (id)
                )''')
    
    conn.commit()
    conn.close()

# Initialize database on startup
init_database()

# Pricing configuration
PRICING = {
    'per_document': 2.50,
    'per_report': 5.00,
    'subscription_monthly': 29.99,
    'subscription_yearly': 299.99
}

# JWT token management
def generate_token(user_id):
    payload = {
        'user_id': user_id,
        'exp': datetime.utcnow() + timedelta(hours=24)
    }
    return jwt.encode(payload, app.secret_key, algorithm='HS256')

def verify_token(token):
    try:
        payload = jwt.decode(token, app.secret_key, algorithms=['HS256'])
        return payload['user_id']
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None

# Authentication decorator
def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'error': 'Authentication required'}), 401
        
        if token.startswith('Bearer '):
            token = token[7:]
        
        user_id = verify_token(token)
        if not user_id:
            return jsonify({'error': 'Invalid or expired token'}), 401
        
        request.current_user_id = user_id
        return f(*args, **kwargs)
    
    return decorated_function

# User management functions
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

def create_user_session(user_id):
    session_id = str(uuid.uuid4())
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    # Mark previous sessions as inactive
    c.execute('UPDATE user_sessions SET is_active = FALSE WHERE user_id = ?', (user_id,))
    
    # Create new active session
    c.execute('INSERT INTO user_sessions (user_id, session_id) VALUES (?, ?)', (user_id, session_id))
    conn.commit()
    conn.close()
    return session_id

def get_current_session(user_id):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute('''SELECT session_id, documents_processed, reports_generated, total_billing, 
                        session_start FROM user_sessions 
                 WHERE user_id = ? AND is_active = TRUE 
                 ORDER BY session_start DESC LIMIT 1''', (user_id,))
    result = c.fetchone()
    conn.close()
    return result

def get_user_usage(user_id):
    session_data = get_current_session(user_id)
    
    if session_data:
        return {
            'session_id': session_data[0],
            'documents_processed': session_data[1],
            'reports_generated': session_data[2],
            'total_billing': session_data[3],
            'session_start': session_data[4]
        }
    return {
        'session_id': None,
        'documents_processed': 0,
        'reports_generated': 0,
        'total_billing': 0.0,
        'session_start': datetime.now().isoformat()
    }

def update_user_billing(user_id, documents_count, generate_report_flag=False):
    doc_cost = documents_count * PRICING['per_document']
    report_cost = PRICING['per_report'] if generate_report_flag else 0
    total_cost = doc_cost + report_cost
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    # Get current session
    session_data = get_current_session(user_id)
    if not session_data:
        # Create new session if none exists
        session_id = create_user_session(user_id)
    else:
        session_id = session_data[0]
    
    # Update current session usage
    c.execute('''UPDATE user_sessions 
                 SET documents_processed = documents_processed + ?,
                     reports_generated = reports_generated + ?,
                     total_billing = total_billing + ?,
                     last_activity = CURRENT_TIMESTAMP
                 WHERE user_id = ? AND session_id = ?''', 
              (documents_count, 1 if generate_report_flag else 0, total_cost, user_id, session_id))
    
    # Add transaction records
    if documents_count > 0:
        c.execute('''INSERT INTO transactions 
                     (user_id, transaction_type, amount, description) 
                     VALUES (?, ?, ?, ?)''', 
                  (user_id, 'document_analysis', doc_cost, f'Analyzed {documents_count} documents'))
    
    if generate_report_flag:
        c.execute('''INSERT INTO transactions 
                     (user_id, transaction_type, amount, description) 
                     VALUES (?, ?, ?, ?)''', 
                  (user_id, 'report_generation', report_cost, 'Generated detailed report'))
    
    # Record analysis in history
    analysis_id = str(uuid.uuid4())
    c.execute('''INSERT INTO analysis_history 
                 (user_id, session_id, analysis_id, documents_count, cost, report_generated) 
                 VALUES (?, ?, ?, ?, ?, ?)''',
              (user_id, session_id, analysis_id, documents_count, total_cost, generate_report_flag))
    
    conn.commit()
    conn.close()
    
    return {
        'documents_cost': doc_cost,
        'report_cost': report_cost,
        'total_cost': total_cost,
        'session_id': session_id,
        'analysis_id': analysis_id
    }

def get_account_balance(user_id):
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute('SELECT account_balance FROM users WHERE id = ?', (user_id,))
    result = c.fetchone()
    conn.close()
    return result[0] if result else 0.0

# Health check endpoint for deployment
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/')
def home():
    return jsonify({'message': 'Welcome to the Smart Doc Checker API'})

# Authentication endpoints
@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username')
    email = data.get('email')
    password = data.get('password')
    
    if not all([username, email, password]):
        return jsonify({'error': 'All fields are required'}), 400
    
    if len(password) < 6:
        return jsonify({'error': 'Password must be at least 6 characters long'}), 400
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    try:
        password_hash = hash_password(password)
        c.execute('INSERT INTO users (username, email, password_hash, account_balance) VALUES (?, ?, ?, ?)',
                  (username, email, password_hash, 50.0))  # Give $50 signup bonus
        user_id = c.lastrowid
        conn.commit()
        
        # Create initial session
        session_id = create_user_session(user_id)
        
        token = generate_token(user_id)
        
        return jsonify({
            'message': 'User registered successfully',
            'token': token,
            'user': {
                'id': user_id,
                'username': username,
                'email': email,
                'account_balance': 50.0
            }
        }), 201
        
    except sqlite3.IntegrityError:
        return jsonify({'error': 'Username or email already exists'}), 400
    finally:
        conn.close()

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    
    if not all([username, password]):
        return jsonify({'error': 'Username and password are required'}), 400
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    password_hash = hash_password(password)
    c.execute('SELECT id, username, email, account_balance FROM users WHERE username = ? AND password_hash = ?',
              (username, password_hash))
    user = c.fetchone()
    conn.close()
    
    if user:
        user_id, username, email, balance = user
        # Create new session for this login
        session_id = create_user_session(user_id)
        
        token = generate_token(user_id)
        return jsonify({
            'message': 'Login successful',
            'token': token,
            'user': {
                'id': user_id,
                'username': username,
                'email': email,
                'account_balance': balance
            }
        })
    else:
        return jsonify({'error': 'Invalid credentials'}), 401

@app.route('/profile', methods=['GET'])
@require_auth
def get_profile():
    user_id = request.current_user_id
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    c.execute('SELECT username, email, account_balance, subscription_type, created_at FROM users WHERE id = ?',
              (user_id,))
    user_data = c.fetchone()
    
    # Get lifetime statistics
    c.execute('''SELECT COUNT(DISTINCT session_id) as total_sessions, 
                        SUM(documents_processed) as total_docs,
                        SUM(reports_generated) as total_reports,
                        SUM(total_billing) as total_spent
                 FROM user_sessions WHERE user_id = ?''', (user_id,))
    usage_stats = c.fetchone()
    
    conn.close()
    
    if user_data:
        return jsonify({
            'user': {
                'username': user_data[0],
                'email': user_data[1],
                'account_balance': user_data[2],
                'subscription_type': user_data[3],
                'member_since': user_data[4]
            },
            'lifetime_stats': {
                'total_sessions': usage_stats[0] or 0,
                'total_documents': usage_stats[1] or 0,
                'total_reports': usage_stats[2] or 0,
                'total_spent': usage_stats[3] or 0.0
            }
        })
    
    return jsonify({'error': 'User not found'}), 404

# Payment endpoints
@app.route('/stripe-config', methods=['GET'])
def get_stripe_config():
    return jsonify({'publishable_key': STRIPE_PUBLISHABLE_KEY})

@app.route('/create-payment-intent', methods=['POST'])
@require_auth
def create_payment_intent():
    user_id = request.current_user_id
    data = request.get_json()
    amount = data.get('amount')  # Amount in dollars
    
    if not amount or amount < 5:  # Minimum $5
        return jsonify({'error': 'Minimum payment amount is $5'}), 400
    
    try:
        # Create Stripe PaymentIntent
        intent = stripe.PaymentIntent.create(
            amount=int(amount * 100),  # Stripe uses cents
            currency='usd',
            metadata={
                'user_id': user_id,
                'type': 'account_topup'
            }
        )
        
        return jsonify({
            'client_secret': intent.client_secret,
            'amount': amount
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/confirm-payment', methods=['POST'])
@require_auth
def confirm_payment():
    user_id = request.current_user_id
    data = request.get_json()
    payment_intent_id = data.get('payment_intent_id')
    
    try:
        # Verify payment with Stripe
        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        
        if intent.status == 'succeeded' and intent.metadata.get('user_id') == str(user_id):
            amount = intent.amount / 100  # Convert cents to dollars
            
            conn = sqlite3.connect(DATABASE_PATH)
            c = conn.cursor()
            
            # Update account balance
            c.execute('UPDATE users SET account_balance = account_balance + ? WHERE id = ?',
                      (amount, user_id))
            
            # Record transaction
            c.execute('''INSERT INTO transactions 
                         (user_id, transaction_type, amount, description, payment_method, stripe_payment_intent_id) 
                         VALUES (?, ?, ?, ?, ?, ?)''',
                      (user_id, 'payment', amount, f'Account top-up via Stripe', 'stripe', payment_intent_id))
            
            conn.commit()
            conn.close()
            
            new_balance = get_account_balance(user_id)
            
            return jsonify({
                'message': 'Payment successful',
                'amount': amount,
                'new_balance': new_balance
            })
        else:
            return jsonify({'error': 'Payment verification failed'}), 400
            
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/transaction-history', methods=['GET'])
@require_auth
def get_transaction_history():
    user_id = request.current_user_id
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    c.execute('''SELECT transaction_type, amount, description, timestamp, 
                        payment_method, stripe_payment_intent_id, status 
                 FROM transactions 
                 WHERE user_id = ? 
                 ORDER BY timestamp DESC LIMIT 50''', (user_id,))
    
    transactions = []
    for row in c.fetchall():
        transactions.append({
            'type': row[0],
            'amount': row[1],
            'description': row[2],
            'timestamp': row[3],
            'payment_method': row[4],
            'payment_intent_id': row[5],
            'status': row[6]
        })
    
    conn.close()
    return jsonify({'transactions': transactions})

@app.route('/usage-stats', methods=['GET'])
@require_auth
def get_usage_stats():
    user_id = request.current_user_id
    usage_stats = get_user_usage(user_id)
    usage_stats['account_balance'] = get_account_balance(user_id)
    return jsonify(usage_stats)

# Monitored documents endpoints
@app.route('/monitor-external', methods=['POST'])
@require_auth
def add_external_monitoring():
    user_id = request.current_user_id
    data = request.get_json()
    url = data.get('url')
    
    if not url:
        return jsonify({'error': 'URL is required'}), 400
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    # Check if already monitoring this URL for this user
    c.execute('SELECT id FROM monitored_documents WHERE user_id = ? AND url = ? AND is_active = TRUE',
              (user_id, url))
    if c.fetchone():
        conn.close()
        return jsonify({'error': 'URL is already being monitored'}), 400
    
    c.execute('INSERT INTO monitored_documents (user_id, url) VALUES (?, ?)', (user_id, url))
    conn.commit()
    conn.close()
    
    return jsonify({'message': 'External monitoring added successfully'})

@app.route('/monitored-docs', methods=['GET'])
@require_auth
def get_monitored_docs():
    user_id = request.current_user_id
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    
    c.execute('SELECT url, added_at, last_check FROM monitored_documents WHERE user_id = ? AND is_active = TRUE',
              (user_id,))
    docs = []
    for row in c.fetchall():
        docs.append({
            'url': row[0],
            'added_at': row[1],
            'last_check': row[2]
        })
    
    conn.close()
    return jsonify(docs)

# Document analysis code (existing code with user authentication)
@dataclass
class Contradiction:
    id: str
    doc1_name: str
    doc2_name: str
    doc1_text: str
    doc2_text: str
    conflict_type: str
    explanation: str
    suggestion: str
    severity: str

def extract_text_from_docx(file_stream):
    try:
        document = Document(file_stream)
        full_text = []
        for para in document.paragraphs:
            if para.text.strip():
                full_text.append(para.text.strip())
        return '\n'.join(full_text)
    except Exception as e:
        return f"Error reading DOCX: {str(e)}"

def extract_text_from_pdf(file_stream):
    try:
        pdf_reader = PyPDF2.PdfReader(file_stream)
        full_text = []
        for page in pdf_reader.pages:
            text = page.extract_text()
            if text.strip():
                full_text.append(text.strip())
        return '\n'.join(full_text)
    except Exception as e:
        return f"Error reading PDF: {str(e)}"

def extract_text_from_txt(file_stream):
    try:
        content = file_stream.read()
        if isinstance(content, bytes):
            content = content.decode('utf-8')
        return content
    except Exception as e:
        return f"Error reading TXT: {str(e)}"

def extract_text_from_file(file_stream, filename):
    filename_lower = filename.lower()
    
    if filename_lower.endswith('.docx'):
        return extract_text_from_docx(file_stream)
    elif filename_lower.endswith('.pdf'):
        return extract_text_from_pdf(file_stream)
    elif filename_lower.endswith('.txt'):
        return extract_text_from_txt(file_stream)
    else:
        return "Unsupported file type"

def extract_key_phrases(text):
    sentences = re.split(r'[.!?]+', text)
    
    important_patterns = [
        r'(?:must|should|shall|required?|mandatory|compulsory|obligatory|necessary)',
        r'(?:not allowed|prohibited|forbidden|banned|cannot|must not|shall not)',
        r'(?:deadline|due date|submit (?:by|before)|expires?)',
        r'(?:minimum|maximum|at least|no more than|up to)',
        r'(?:attendance|present|absent)',
        r'(?:notice period|advance notice|days? notice)',
        r'\d+\s*(?:days?|weeks?|months?|years?|hours?|minutes?|%|percent)',
        r'(?:before|after|by|until|no later than)\s+(?:\d+|\w+)',
    ]
    
    key_sentences = []
    for sentence in sentences:
        sentence = sentence.strip()
        if len(sentence) > 15:
            for pattern in important_patterns:
                if re.search(pattern, sentence, re.IGNORECASE):
                    key_sentences.append(sentence)
                    break
    
    return key_sentences

def detect_contradictions_advanced(docs_data):
    contradictions = []
    seen_contradictions = set()
    
    doc_phrases = []
    for doc in docs_data:
        phrases = extract_key_phrases(doc['text'])
        doc_phrases.append(phrases)
    
    for i in range(len(doc_phrases)):
        for j in range(i + 1, len(doc_phrases)):
            phrases_i = doc_phrases[i]
            phrases_j = doc_phrases[j]
            
            for phrase_i in phrases_i:
                for phrase_j in phrases_j:
                    if SequenceMatcher(None, phrase_i.lower(), phrase_j.lower()).ratio() > 0.7:
                        continue
                    
                    contradiction = analyze_contradiction(phrase_i, phrase_j)
                    if contradiction:
                        contradiction_key = tuple(sorted([phrase_i.lower(), phrase_j.lower()]))
                        
                        if contradiction_key not in seen_contradictions:
                            seen_contradictions.add(contradiction_key)
                            
                            contradiction_obj = Contradiction(
                                id=str(uuid.uuid4()),
                                doc1_name=docs_data[i]['filename'],
                                doc2_name=docs_data[j]['filename'],
                                doc1_text=phrase_i,
                                doc2_text=phrase_j,
                                conflict_type=contradiction['type'],
                                explanation=contradiction['explanation'],
                                suggestion=contradiction['suggestion'],
                                severity=contradiction['severity']
                            )
                            
                            contradictions.append(contradiction_obj)
    
    return contradictions[:15]

def analyze_contradiction(phrase1, phrase2):
    p1_lower = phrase1.lower()
    p2_lower = phrase2.lower()
    
    # Check for percentage conflicts
    perc1 = re.search(r'(\d+(?:\.\d+)?)\s*(?:%|percent)', phrase1)
    perc2 = re.search(r'(\d+(?:\.\d+)?)\s*(?:%|percent)', phrase2)
    
    if perc1 and perc2:
        val1, val2 = float(perc1.group(1)), float(perc2.group(1))
        if abs(val1 - val2) > 0:
            severity = "High" if abs(val1 - val2) >= 10 else "Medium"
            return {
                'type': 'Percentage Conflict',
                'explanation': f'Two documents specify different percentage requirements: {val1}% vs {val2}%. This creates ambiguity about which standard to follow.',
                'suggestion': f'Standardize the percentage requirement. Consider using the higher value ({max(val1, val2)}%) for stricter compliance or clarify which document takes precedence.',
                'severity': severity
            }
    
    # Check for time period conflicts
    time_keywords = ['days', 'weeks', 'months', 'notice', 'deadline', 'advance']
    if any(keyword in p1_lower for keyword in time_keywords) and any(keyword in p2_lower for keyword in time_keywords):
        time1 = re.search(r'(\d+)\s*(days?|weeks?|months?)', p1_lower)
        time2 = re.search(r'(\d+)\s*(days?|weeks?|months?)', p2_lower)
        
        if time1 and time2:
            val1, unit1 = int(time1.group(1)), time1.group(2)
            val2, unit2 = int(time2.group(1)), time2.group(2)
            
            if unit1 == unit2 and val1 != val2:
                severity = "High" if abs(val1 - val2) >= 7 else "Medium"
                return {
                    'type': 'Time Period Conflict',
                    'explanation': f'Conflicting time requirements found: {val1} {unit1} vs {val2} {unit2}. This could lead to confusion about actual deadlines.',
                    'suggestion': f'Establish a single, clear time requirement. Recommend using {max(val1, val2)} {unit1} to ensure adequate time for compliance.',
                    'severity': severity
                }
    
    return None

@app.route('/upload', methods=['POST'])
@require_auth
def upload_files():
    user_id = request.current_user_id
    files = request.files.getlist('files')
    
    if not files:
        return jsonify({'error': 'No files provided'}), 400
    
    # Check account balance
    account_balance = get_account_balance(user_id)
    required_cost = len(files) * PRICING['per_document']
    
    if account_balance < required_cost:
        return jsonify({
            'error': 'Insufficient funds',
            'required': required_cost,
            'balance': account_balance,
            'message': f'You need ${required_cost:.2f} but only have ${account_balance:.2f}. Please add funds to continue.'
        }), 402
    
    results = []
    valid_docs = []
    
    # Process each file
    for file in files:
        file_stream = io.BytesIO(file.read())
        text = extract_text_from_file(file_stream, file.filename)
        
        file_data = {'filename': file.filename, 'text': text}
        results.append(file_data)
        
        if not text.startswith('Error') and text != 'Unsupported file type':
            valid_docs.append(file_data)
    
    # Detect contradictions
    contradictions = []
    if len(valid_docs) > 1:
        contradictions = detect_contradictions_advanced(valid_docs)
    
    # Update billing and deduct from account balance
    billing_info = update_user_billing(user_id, len(valid_docs))
    
    # Deduct from account balance
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute('UPDATE users SET account_balance = account_balance - ? WHERE id = ?',
              (billing_info['documents_cost'], user_id))
    conn.commit()
    conn.close()
    
    # Get updated usage stats
    usage_stats = get_user_usage(user_id)
    
    analysis_summary = {
        'total_files': len(files),
        'valid_files': len(valid_docs),
        'contradictions_found': len(contradictions),
        'processing_time': datetime.now().isoformat()
    }
    
    response = {
        'files': results,
        'contradictions': [
            {
                'id': c.id,
                'doc1_name': c.doc1_name,
                'doc2_name': c.doc2_name,
                'doc1_text': c.doc1_text,
                'doc2_text': c.doc2_text,
                'type': c.conflict_type,
                'explanation': c.explanation,
                'suggestion': c.suggestion,
                'severity': c.severity
            } for c in contradictions
        ],
        'analysis_summary': analysis_summary,
        'billing': billing_info,
        'usage_stats': usage_stats,
        'account_balance': get_account_balance(user_id)
    }
    
    return jsonify(response)

@app.route('/generate-report', methods=['POST'])
@require_auth
def generate_detailed_report():
    user_id = request.current_user_id
    data = request.get_json()
    
    if not data or 'contradictions' not in data:
        return jsonify({'error': 'No contradiction data provided'}), 400
    
    # Check account balance
    account_balance = get_account_balance(user_id)
    if account_balance < PRICING['per_report']:
        return jsonify({
            'error': 'Insufficient funds for report generation',
            'required': PRICING['per_report'],
            'balance': account_balance
        }), 402
    
    # Update billing and deduct from account balance
    billing_info = update_user_billing(user_id, 0, generate_report_flag=True)
    
    conn = sqlite3.connect(DATABASE_PATH)
    c = conn.cursor()
    c.execute('UPDATE users SET account_balance = account_balance - ? WHERE id = ?',
              (PRICING['per_report'], user_id))
    conn.commit()
    conn.close()
    
    # Generate comprehensive report
    contradictions = data['contradictions']
    
    # Categorize contradictions by severity
    high_priority = [c for c in contradictions if c.get('severity', '').lower() == 'high']
    medium_priority = [c for c in contradictions if c.get('severity', '').lower() == 'medium']
    low_priority = [c for c in contradictions if c.get('severity', '').lower() == 'low']
    
    report = {
        'metadata': {
            'generated_at': datetime.now().isoformat(),
            'user_id': user_id,
            'documents_analyzed': len(data.get('docs_data', [])),
            'contradictions_found': len(contradictions),
            'analysis_id': billing_info['analysis_id'],
            'session_id': billing_info['session_id']
        },
        'summary': {
            'total_contradictions': len(contradictions),
            'high_priority_issues': len(high_priority),
            'medium_priority_issues': len(medium_priority),
            'low_priority_issues': len(low_priority),
            'most_common_conflict_types': _get_common_conflict_types(contradictions)
        },
        'contradictions': contradictions,
        'recommendations': {
            'high_priority': [_generate_recommendation(c, 'high') for c in high_priority],
            'medium_priority': [_generate_recommendation(c, 'medium') for c in medium_priority],
            'low_priority': [_generate_recommendation(c, 'low') for c in low_priority]
        },
        'billing_info': billing_info
    }
    
    # Save report to file
    os.makedirs('reports', exist_ok=True)
    report_filename = f"reports/report_{user_id}_{billing_info['session_id']}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(report_filename, 'w') as f:
        json.dump(report, f, indent=2)
    
    usage_stats = get_user_usage(user_id)
    
    return jsonify({
        'report': report,
        'report_file': report_filename,
        'billing': billing_info,
        'usage_stats': usage_stats,
        'account_balance': get_account_balance(user_id)
    })

def _get_common_conflict_types(contradictions):
    type_counts = {}
    for c in contradictions:
        conflict_type = c.get('type', 'Unknown')
        type_counts[conflict_type] = type_counts.get(conflict_type, 0) + 1
    
    return sorted(type_counts.items(), key=lambda x: x[1], reverse=True)[:5]

def _generate_recommendation(contradiction, priority):
    return {
        'issue': f"{contradiction.get('type', 'Conflict')} between {contradiction.get('doc1_name')} and {contradiction.get('doc2_name')}",
        'priority': priority,
        'action_required': contradiction.get('suggestion', 'No specific action provided'),
        'impact': _assess_impact(priority),
        'timeline': _suggest_timeline(priority)
    }

def _assess_impact(priority):
    impact_map = {
        'high': 'Critical - May cause legal compliance issues or operational confusion',
        'medium': 'Moderate - Could lead to inconsistent implementation',
        'low': 'Minor - May cause occasional confusion but unlikely to affect operations'
    }
    return impact_map.get(priority, 'Unknown impact')

def _suggest_timeline(priority):
    timeline_map = {
        'high': 'Immediate action required (within 24-48 hours)',
        'medium': 'Address within 1 week',
        'low': 'Address at next document review cycle'
    }
    return timeline_map.get(priority, 'No specific timeline')

# Production configuration
if __name__ == '__main__':
    # Use environment variables for port and host
    port = int(os.environ.get('PORT', 5000))
    debug_mode = os.environ.get('FLASK_ENV') != 'production'
    
    app.run(
        host='0.0.0.0',  # Required for Render.com
        port=port,
        debug=debug_mode
    )