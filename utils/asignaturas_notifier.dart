import 'dart:async';

/// Servicio singleton para notificar cambios en las asignaturas ocultas
class AsignaturasNotifier {
  static final AsignaturasNotifier _instance = AsignaturasNotifier._internal();

  factory AsignaturasNotifier() {
    return _instance;
  }

  AsignaturasNotifier._internal();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notificarCambio() {
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}
