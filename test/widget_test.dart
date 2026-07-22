// Lightweight widget test — verifies the branding renders in both themes
// without touching the database (which needs a real device).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nqe/theme.dart';
import 'package:nqe/widgets/nqe_logo.dart';

void main() {
  testWidgets('NQE logo + Willong byline render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNqeTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [NqeLogo(), WillongByline()],
            ),
          ),
        ),
      ),
    );

    expect(find.text('NQE'), findsOneWidget);
    expect(find.text('FUND'), findsOneWidget);
    expect(find.textContaining('WILLONG'), findsOneWidget);
  });

  testWidgets('theme builds for light and dark', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildNqeTheme(b),
          home: const Scaffold(body: NqeLogo()),
        ),
      );
      expect(find.text('NQE'), findsOneWidget);
    }
  });
}
