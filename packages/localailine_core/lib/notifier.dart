/// A small change notifier with the same shape as Flutter's `ChangeNotifier`
/// (`addListener`, `removeListener`, `notifyListeners`, `dispose`), so the
/// engine runs without Flutter: in the desktop app, on a server, or in tests.
/// A Flutter class can extend a [Notifier] and declare `implements Listenable`.
class Notifier {
  final List<void Function()> _listeners = [];
  bool _disposed = false;

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(void Function() listener) {
    if (!_disposed) _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void notifyListeners() {
    if (_disposed) return;
    for (final l in List.of(_listeners)) {
      if (_listeners.contains(l)) l();
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
