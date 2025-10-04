import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;


// 1. DATA MODELS


/// Represents the data sent to the backend API for prediction.
class UserProfile {
  final int age;
  final int tenureMonths;
  final int remoteFlag;
  final String education;
  final String location;
  final String title;
  final String industry;
  final double avgSleepHours;

  UserProfile({
    required this.age,
    required this.tenureMonths,
    required this.remoteFlag,
    required this.education,
    required this.location,
    required this.title,
    required this.industry,
    required this.avgSleepHours,
  });

  Map<String, dynamic> toJson() => {
    'age': age,
    'tenure_months': tenureMonths,
    'remote_flag': remoteFlag,
    'education': education,
    'location': location,
    'title': title,
    'industry': industry,
    'avg_sleep_hours': avgSleepHours,
  };
}

/// Represents the predicted results received from the backend API.
class PredictionResult {
  final int projectedAge;
  final double healthIncreasePercent;
  final dynamic predictedSalary; // Can be double or String "N/A"
  final List<String> recommendedJobs;
  final int timeProjectionMonths;
  final String? error;

  PredictionResult({
    this.projectedAge = 0,
    this.healthIncreasePercent = 0.0,
    this.predictedSalary = "N/A",
    this.recommendedJobs = const [],
    this.timeProjectionMonths = 0,
    this.error,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    // Handle error response from the server
    if (json.containsKey('error')) {
      return PredictionResult(error: json['error']);
    }

    return PredictionResult(
      projectedAge: json['projected_age'] as int,
      healthIncreasePercent: (json['health_increase_percent'] as num).toDouble(),
      predictedSalary: json['predicted_salary'],
      recommendedJobs: List<String>.from(json['recommended_jobs']),
      timeProjectionMonths: json['time_projection_months'] as int,
    );
  }

  factory PredictionResult.withError(String message) {
    return PredictionResult(error: message);
  }
}


// 2. API SERVICE


// Determine the correct IP based on the environment
String getApiUrl() {
  const String port = '5000';
  String ip;

  if (Platform.isAndroid) {
    // Android emulator access local host via 10.0.2.2
    ip = '192.168.137.94';
  } else if (Platform.isIOS) {
    ip = '127.0.0.1';
  } else {
    // Desktop/Web
    ip = '127.0.0.1';
  }

  return 'http://$ip:$port/predict_twin';
}

Future<PredictionResult> fetchPrediction(UserProfile userProfile, int projectionMonths) async {
  final url = Uri.parse(getApiUrl());

  final body = jsonEncode({
    'user_data': userProfile.toJson(),
    'projection_months': projectionMonths,
  });

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      // Success
      return PredictionResult.fromJson(jsonDecode(response.body));
    } else {
      // Server returned error status code (4xx or 5xx)
      final errorJson = jsonDecode(response.body);
      final errorMessage = errorJson['error'] ?? 'Unknown server error.';
      return PredictionResult.withError('Server error (${response.statusCode}): $errorMessage');
    }
  } catch (e) {
    // Network or decoding error
    return PredictionResult.withError('Network/Connection error: $e. Check if your Python server is running at ${getApiUrl()}');
  }
}

// --------------------------------------------------------------------------
// 3. FLUTTER UI
// --------------------------------------------------------------------------

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Twin Predictor',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const PredictionScreen(),
    );
  }
}

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  // State variables for user input
  final TextEditingController _ageController = TextEditingController(text: '30');
  final TextEditingController _tenureController = TextEditingController(text: '18');
  final TextEditingController _sleepController = TextEditingController(text: '7.5');
  String _education = 'bachelor';
  String _location = 'Delhi';
  String _title = 'engineer';
  String _industry = 'IT';
  bool _remoteFlag = true;

  // State variables for prediction process
  int _projectionMonths = 60; // Default to 5 years (60 months)
  PredictionResult? _predictionResult;
  bool _isLoading = false;

  // Mock data for dropdowns (MUST match values used in model training)
  final List<String> _educationOptions = ['bachelor', 'master', 'phd'];
  final List<String> _locationOptions = ['Delhi', 'Mumbai', 'Bangalore', 'Chennai', 'Pune', 'Remote'];
  final List<String> _titleOptions = ['engineer', 'analyst', 'manager', 'lead engineer', 'senior engineer', 'intern', 'associate'];
  final List<String> _industryOptions = ['IT', 'Healthcare', 'Finance', 'Retail', 'EdTech'];

  // Button labels for projection time
  final Map<int, String> _timeOptions = {
    6: '6 Months',
    24: '2 Years',
    60: '5 Years',
  };

  Future<void> _handlePredict() async {
    // 1. Validate and Parse Input
    final int? age = int.tryParse(_ageController.text);
    final int? tenure = int.tryParse(_tenureController.text);
    final double? sleep = double.tryParse(_sleepController.text);

    if (age == null || tenure == null || sleep == null) {
      setState(() {
        _predictionResult = PredictionResult.withError('Please enter valid numbers for Age, Tenure, and Sleep.');
      });
      return;
    }

    // 2. Prepare Data
    final userProfile = UserProfile(
      age: age,
      tenureMonths: tenure,
      remoteFlag: _remoteFlag ? 1 : 0,
      education: _education,
      location: _location,
      title: _title,
      industry: _industry,
      avgSleepHours: sleep,
    );

    // 3. Call API and Update State
    setState(() {
      _isLoading = true;
      _predictionResult = null;
    });

    final result = await fetchPrediction(userProfile, _projectionMonths);

    setState(() {
      _predictionResult = result;
      _isLoading = false;
    });
  }

  // Helper widget for a data input field
  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        ),
        value: value,
        items: items.map((String val) {
          return DropdownMenuItem<String>(
            value: val,
            child: Text(val, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // Helper widget for a numeric text field
  Widget _buildTextField(String label, TextEditingController controller, {TextInputType type = TextInputType.number}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Twin Predictor'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Current Profile Input',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            _buildTextField('Current Age', _ageController),
            _buildTextField('Current Tenure (Months)', _tenureController),
            _buildTextField('Avg. Sleep Hours (e.g., 7.5)', _sleepController, type: TextInputType.text),

            // Dropdowns for Categorical Data
            _buildDropdown('Education', _education, _educationOptions, (v) => setState(() => _education = v!)),
            _buildDropdown('Location', _location, _locationOptions, (v) => setState(() => _location = v!)),
            _buildDropdown('Job Title', _title, _titleOptions, (v) => setState(() => _title = v!)),
            _buildDropdown('Industry', _industry, _industryOptions, (v) => setState(() => _industry = v!)),

            // Remote Flag Toggle
            SwitchListTile(
              title: const Text('Remote Worker'),
              value: _remoteFlag,
              onChanged: (bool value) => setState(() => _remoteFlag = value),
              contentPadding: EdgeInsets.zero,
            ),

            const Divider(height: 30),

            const Text(
              'Select Projection Period',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Projection Period Selection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _timeOptions.entries.map((entry) {
                return ElevatedButton(
                  onPressed: () => setState(() => _projectionMonths = entry.key),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _projectionMonths == entry.key ? Theme.of(context).primaryColor : Colors.grey[200],
                    foregroundColor: _projectionMonths == entry.key ? Colors.white : Colors.black,
                  ),
                  child: Text(entry.value),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Predict Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _handlePredict,
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
                  : const Icon(Icons.psychology),
              label: Text(_isLoading ? 'Predicting...' : 'Predict Digital Twin Future'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const Divider(height: 40),

            // 4. Results Display
            if (_predictionResult != null)
              PredictionResultCard(result: _predictionResult!),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ageController.dispose();
    _tenureController.dispose();
    _sleepController.dispose();
    super.dispose();
  }
}

class PredictionResultCard extends StatelessWidget {
  final PredictionResult result;

  const PredictionResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.error != null) {
      return Card(
        color: Colors.red.shade100,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Prediction Failed! ❌', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              Text(result.error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Digital Twin Projection (${result.timeProjectionMonths} Months) 🚀',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const Divider(),
            _buildResultRow('Projected Age:', '${result.projectedAge} years'),
            _buildResultRow('Predicted Salary (Annual):', result.predictedSalary is String
                ? result.predictedSalary
                : '\$${(result.predictedSalary as double).toStringAsFixed(2)}'),
            _buildResultRow('Health Trajectory:', '+${result.healthIncreasePercent}% Improvement'),
            const SizedBox(height: 10),
            const Text(
              'Top Recommended Future Job Titles:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...result.recommendedJobs.map((job) => Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 4.0),
              child: Text('• $job'),
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// END OF FILE
// --------------------------------------------------------------------------