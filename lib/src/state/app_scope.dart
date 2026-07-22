import 'package:flutter/widgets.dart';

import 'session_controller.dart';
import 'trip_controller.dart';

/// Makes the two controllers reachable from any widget.
///
/// A plain [InheritedNotifier] pair rather than a state-management package:
/// there are exactly two long-lived objects here, and adding provider or riverpod
/// would be more concept than this app needs. If a third controller appears,
/// reconsider.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.trips,
    required super.child,
  });

  final SessionController session;
  final TripController trips;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!;
  }

  /// Controllers are created once and never swapped, so nothing downstream
  /// needs rebuilding when this widget is replaced. Pages listen to the
  /// notifiers directly instead.
  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

/// Rebuilds [builder] whenever [listenable] changes.
///
/// Saves every page from writing the same addListener/removeListener pair, and
/// from the leak that follows when the removeListener is forgotten.
class Watch extends StatelessWidget {
  const Watch({super.key, required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    builder: (context, _) => builder(context),
  );
}
