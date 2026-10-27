import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

Future<String?> runN8nAnalysis({
  required String userName,
  required String userGoal,
  required int threshold,
  required int bestHour,
  required double totalHours,
  required List diaries,
  required String homeAddress,
  required String birthDate,
  required String birthTime,
  required List emotions,
  required List failReasons,
  required String bestFocusTime,
  required int analyzedSessions,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final url = Uri.parse(
    'https://tjddo2711.app.n8n.cloud/webhook-test/6e5b181b-f64e-4782-b5a0-9da76107b8f5',
  );

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uid': user?.uid,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'userName': userName,
        'userGoal': userGoal,
        'totalHours': totalHours,
        'bestHour': bestHour,
        'threshold': threshold,
        'diaries': diaries,
        'homeAddress': homeAddress,
        'birthDate': birthDate,
        'birthTime': birthTime,
        'emotions': emotions,
        'failReasons': failReasons,
        'bestFocusTime': bestFocusTime,
        'analyzedSessions': analyzedSessions,
      }),
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode == 200) {
      return response.body;
    }
    return null;
  } catch (e) {
    return null;
  }
}