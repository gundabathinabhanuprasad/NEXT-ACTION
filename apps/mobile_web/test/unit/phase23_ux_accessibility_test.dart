import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/widgets/common_widgets.dart';

void main() {
  group('Phase 23 — UX, Accessibility & Design System Component Tests', () {
    testWidgets('1. StatusBadge renders dual visual cues (icon + text) and accessible semantics', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StatusBadge(status: 'completed'),
                StatusBadge(status: 'in_progress'),
                StatusBadge(status: 'cancelled'),
                StatusBadge(status: 'pending'),
              ],
            ),
          ),
        ),
      );

      // Verify text labels
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      // Verify dual visual cues (icons)
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.timelapse), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);

      // Verify Semantics labels
      expect(
        tester.getSemantics(find.byWidgetPredicate((w) => w is StatusBadge && w.status == 'completed')),
        matchesSemantics(label: 'Status: COMPLETED'),
      );
      expect(
        tester.getSemantics(find.byWidgetPredicate((w) => w is StatusBadge && w.status == 'in_progress')),
        matchesSemantics(label: 'Status: IN PROGRESS'),
      );
    });

    testWidgets('2. PriorityBadge renders dual visual cues and accessible semantics', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PriorityBadge(priority: 'urgent'),
                PriorityBadge(priority: 'high'),
                PriorityBadge(priority: 'medium'),
                PriorityBadge(priority: 'low'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('URGENT'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);

      expect(find.byIcon(Icons.priority_high), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      expect(
        tester.getSemantics(find.byWidgetPredicate((w) => w is PriorityBadge && w.priority == 'urgent')),
        matchesSemantics(label: 'Priority: URGENT'),
      );
    });

    testWidgets('3. DueDateBadge and AttemptBadge render accessible semantics', (WidgetTester tester) async {
      final dueDate = DateTime.now().add(const Duration(days: 3));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DueDateBadge(dueDate: dueDate),
                const AttemptBadge(attemptCount: 1, maxAttempts: 3),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Attempts: 1 / 3'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      expect(
        tester.getSemantics(find.byType(AttemptBadge)),
        matchesSemantics(label: 'Attempts: 1 of 3'),
      );
    });

    testWidgets('4. AppCard renders child with standard border radius and outline', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => tapped = true,
              child: const Text('Card Content Test'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content Test'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);

      await tester.tap(find.text('Card Content Test'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('5. SectionHeader renders title, subtitle, icon, and trailing action', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionHeader(
              title: 'Test Section Title',
              subtitle: 'Detailed description of this section',
              icon: Icons.settings,
              trailing: Text('Action Button'),
            ),
          ),
        ),
      );

      expect(find.text('Test Section Title'), findsOneWidget);
      expect(find.text('Detailed description of this section'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.text('Action Button'), findsOneWidget);
    });

    testWidgets('6. LoadingStateWidget renders circular indicator and status label', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingStateWidget(
              message: 'Custom Loading Status...',
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Custom Loading Status...'), findsOneWidget);
    });

    testWidgets('7. showAppConfirmationDialog displays destructive alert and returns result', (WidgetTester tester) async {
      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await showAppConfirmationDialog(
                    context,
                    title: 'Delete Workflow Item',
                    message: 'Are you sure you want to delete this workflow item?',
                    isDestructive: true,
                    permanentWarning: 'This action is irreversible.',
                    confirmLabel: 'Delete Forever',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Workflow Item'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this workflow item?'), findsOneWidget);
      expect(find.text('This action is irreversible.'), findsOneWidget);
      expect(find.text('Delete Forever'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(dialogResult, isFalse);

      // Open again and confirm
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Forever'));
      await tester.pumpAndSettle();
      expect(dialogResult, isTrue);
    });
  });
}
