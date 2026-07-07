import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inspired/core/api/api_client.dart';
import 'package:inspired/main.dart';

void main() {
  testWidgets('App boots and shows splash spinner', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const InspiredApp(),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
