import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sistema_gamificacion/pantallas/homepage.dart';
import 'package:sistema_gamificacion/pantallas/pantallaUsuario.dart';
import 'package:sistema_gamificacion/pantallas/pantallaQR.dart';
import 'package:sistema_gamificacion/utils/device_detector_mobile.dart'
    if (dart.library.html) 'package:sistema_gamificacion/utils/device_detector_web.dart';

// ValueNotifier global para comunicar cambios de pantalla desde cualquier lugar
final navegacionGlobalNotifier = ValueNotifier<int?>(null);

void mostrarMensaje(ScaffoldMessengerState scaffoldMessenger, String mensaje, Color color) {
  // Limpiar snackbars previos para evitar acumulación
  try {
    scaffoldMessenger.clearSnackBars();
  } catch (_) {}

  // Calcular la duración en segundos según la longitud del mensaje
  int segundos = (mensaje.length / 10 + 1).toInt();

  // Calcular margin inferior según safe area del scaffold
  double bottomSafeArea = 16.0;
  try {
    final mq = MediaQuery.of(scaffoldMessenger.context);
    bottomSafeArea = mq.padding.bottom + 16.0;
  } catch (_) {
    bottomSafeArea = 16.0;
  }

  // Mostrar SnackBar flotante en la parte inferior con margen suficiente
  scaffoldMessenger.showSnackBar(
    SnackBar(
      content: Text(mensaje, textAlign: TextAlign.center),
      backgroundColor: color,
      duration: Duration(seconds: segundos),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, bottomSafeArea),
    ),
  );
}

Future<bool> mostrarDialogo(BuildContext context, String mensaje) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Confirmación',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Text(mensaje, textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  side: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 1,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  side: BorderSide(color: Colors.orange, width: 1),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      ) ??
      false;
}

void inicioCarga(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      contentPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 180,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(width: 16),
            Expanded(child: Text('Cargando...')),
          ],
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

void finCarga(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pop();
}

// Menu bar
class MainScreen extends StatefulWidget {
  final int? indiceInicial;

  const MainScreen({super.key, this.indiceInicial});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _indiceActual;

  late final List<Widget> _pantallas;
  late final int _totalPantallas;
  final GlobalKey<State<PantallaQR>> _pantallaQRKey = GlobalKey<State<PantallaQR>>();

  @override
  void initState() {
    super.initState();

    // Usar el índice inicial si se proporciona, sino usar 0 (Homepage)
    _indiceActual = widget.indiceInicial ?? 0;

    // Construir lista de pantallas según si es dispositivo móvil
    final bool esMovil = esDispositivoMovil();

    if (kIsWeb && !esMovil) {
      // Web en ordenador: solo Homepage y PantallaUsuario (sin QR)
      _pantallas = [const Homepage(), const PantallaUsuario()];
      _totalPantallas = 2;

      // Si se intenta ir a QR (índice 1) en web escritorio, redirigir a Usuario (índice 1 en este caso)
      if (_indiceActual == 1) {
        _indiceActual = 1; // Usuario en web escritorio
      } else if (_indiceActual == 2) {
        _indiceActual = 1; // Usuario
      }
    } else {
      // Móvil (web o nativo): incluir PantallaQR
      _pantallas = [
        const Homepage(),
        PantallaQR(key: _pantallaQRKey),
        const PantallaUsuario(),
      ];
      _totalPantallas = 3;

      // Si el índice inicial es la pantalla QR, resetearla
      if (_indiceActual == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final state = _pantallaQRKey.currentState;
          if (state != null) {
            try {
              (state as dynamic).resetearSeleccion();
            } catch (_) {}
          }
        });
      }
    }

    // Escuchar cambios globales de navegación
    navegacionGlobalNotifier.addListener(_onNavegacionGlobalChanged);
  }

  @override
  void dispose() {
    navegacionGlobalNotifier.removeListener(_onNavegacionGlobalChanged);
    super.dispose();
  }

  void _onNavegacionGlobalChanged() {
    final indice = navegacionGlobalNotifier.value;
    if (indice != null && mounted) {
      // En web escritorio, convertir índices de 3 pantallas a 2 pantallas
      int indiceAjustado = indice;
      if (_totalPantallas == 2) {
        // Si se intenta ir a QR (índice 1) o Usuario (índice 2), ir a Usuario (índice 1)
        if (indice >= 1) {
          indiceAjustado = 1; // Usuario en web escritorio
        }
      }

      // Cambiar inmediatamente sin esperar al siguiente frame
      cambiarPantalla(indiceAjustado);
      // Resetear el notifier inmediatamente
      navegacionGlobalNotifier.value = null;
    }
  }

  // Cambiar de pantalla desde otras pantallas
  void cambiarPantalla(int indice) {
    if (indice >= 0 && indice < _totalPantallas) {
      setState(() {
        // Si se navega a la pantalla QR, resetear selecciones
        if (_totalPantallas == 3 && indice == 1) {
          final state = _pantallaQRKey.currentState;
          if (state != null) {
            try {
              (state as dynamic).resetearSeleccion();
            } catch (_) {}
          }
        }
        _indiceActual = indice;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indiceActual, children: _pantallas),
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: _indiceActual,
        onTap: (indice) {
          cambiarPantalla(indice);
        },
        totalPantallas: _totalPantallas,
      ),
    );
  }
}

// Widget reutilizable del BottomNavigationBar
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int)? onTap;
  final int totalPantallas;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    this.onTap,
    this.totalPantallas = 3,
  });

  @override
  Widget build(BuildContext context) {
    // Definir items según el total de pantallas
    final items = totalPantallas == 2
        ? [
            const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
            const BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: '',
            ),
          ]
        : [
            const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
            const BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner, size: 32),
              label: '',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: '',
            ),
          ];

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).primaryColor,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white.withValues(alpha: 0.6),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        enableFeedback: false,
        onTap: onTap,
        items: items,
      ),
    );
  }
}
