import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/rol_provider.dart';
import 'package:sistema_gamificacion/utils/asignaturas_notifier.dart';
import 'package:uuid/uuid.dart';
import 'package:sistema_gamificacion/utils/constantes.dart';

// Interfaz abstracta para acceder a métodos públicos del State
abstract class PantallaQRState {
  void resetearSeleccion();
}

class PantallaQR extends StatefulWidget {
  const PantallaQR({super.key});

  @override
  State<PantallaQR> createState() => _PantallaQRState();
}

class _PantallaQRState extends State<PantallaQR> with WidgetsBindingObserver implements PantallaQRState {
  late MobileScannerController _scannerController;
  List<Map<String, dynamic>> _asignaturas = [];
  String? _asignaturaSeleccionada;
  String? _nombreAsignaturaSeleccionada;
  String? _cursoAsignaturaSeleccionada;
  String? _actividadSeleccionada;
  String? _tipoQRSeleccionado;
  StreamSubscription<void>? _asignaturasSubscription;
  String usuario = '';
  bool _isInitializingScanner = true;
  String? _scannerError;

  // Nueva lista para almacenar actividades creadas por el profesor en runtime
  final List<Map<String, dynamic>> _customActividad = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScanner();
    _cargarAsignaturasDelUsuario();

    // Escuchar cambios en asignaturas ocultas
    _asignaturasSubscription = AsignaturasNotifier().stream.listen((_) {
      _cargarAsignaturasDelUsuario();
      if (_asignaturaSeleccionada != null) {
        _verificarAsignaturaSeleccionada();
      }
    });
  }

  Future<void> _initializeScanner() async {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

      if (mounted) {
        setState(() {
          _isInitializingScanner = false;
          _scannerError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializingScanner = false;
          _scannerError = e.toString();
        });
      }
    }
  }

  Future<void> _verificarAsignaturaSeleccionada() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null && _asignaturaSeleccionada != null) {
      usuario = user.email!.split('@')[0];
      final prefs = await SharedPreferences.getInstance();
      final asignaturasOcultas =
          prefs.getStringList('asignaturasOcultas_$usuario') ?? [];

      // Si la asignatura seleccionada está ahora oculta, resetear
      if (asignaturasOcultas.contains(_asignaturaSeleccionada)) {
        setState(() {
          _asignaturaSeleccionada = null;
          _nombreAsignaturaSeleccionada = null;
          _cursoAsignaturaSeleccionada = null;
          _actividadSeleccionada = null;
          _tipoQRSeleccionado = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recargar asignaturas cuando la app vuelve a estar activa
    if (state == AppLifecycleState.resumed) {
      _cargarAsignaturasDelUsuario();
    }
  }

  // Resetear todos los parámetros de selección sin recargar asignaturas
  @override
  void resetearSeleccion() {
    if (mounted) {
      setState(() {
        _asignaturaSeleccionada = null;
        _nombreAsignaturaSeleccionada = null;
        _cursoAsignaturaSeleccionada = null;
        _actividadSeleccionada = null;
        _tipoQRSeleccionado = null;
      });
    }
  }

  Future<void> _cargarAsignaturasDelUsuario() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      usuario = user.email!.split('@')[0];
      await _cargarAsignaturas(usuario);
    }
  }

  Future<void> _cargarAsignaturas(String usuario) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Obtener las asignaturas del profesor desde su documento
      final docProfesor = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario)
          .get();

      final asignaturasProfesor = List<String>.from(
        docProfesor.data()?['Asignaturas'] ?? [],
      );

      if (asignaturasProfesor.isEmpty) {
        setState(() {
          _asignaturas = [];
        });
        return;
      }

      // Obtener las asignaturas ocultas desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final asignaturasOcultas =
          prefs.getStringList('asignaturasOcultas_$usuario') ?? [];

      // Obtener los datos de cada asignatura (filtrando las ocultas)
      final asignaturasVisibles = <Map<String, dynamic>>[];

      for (final idAsignatura in asignaturasProfesor) {
        // Saltar las asignaturas ocultas
        if (asignaturasOcultas.contains(idAsignatura)) {
          continue;
        }

        final docAsignatura = await FirebaseFirestore.instance
            .collection('asignaturas')
            .doc(idAsignatura)
            .get();

        if (docAsignatura.exists) {
          final data = docAsignatura.data()!;
          asignaturasVisibles.add({
            'id': docAsignatura.id,
            'nombre': data['Nombre'] ?? 'Sin nombre',
            'codigo': data['Codigo'] ?? '',
            'curso': data['Curso'] ?? '',
          });
        }
      }

      setState(() {
        _asignaturas = asignaturasVisibles;
      });
    } catch (e) {
      if (mounted) {
        mostrarMensaje(scaffoldMessenger, 'Error al cargar asignaturas: $e', Colors.red);
      }
    }
  }

  void _onQRDetected(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null) {
        _scannerController.stop();
        _procesarQR(code);
      }
    }
  }

  Future<void> _procesarQR(String codigo) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await registrarInsigniaAlumno(scaffoldMessenger, usuario, codigo);
    } catch (e) {
      if (mounted) {
        mostrarMensaje(scaffoldMessenger, 'Error al procesar QR: $e', Colors.red);
      }
    } finally {
      // Reiniciar el scanner después de un breve delay
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        _scannerController.start();
      }
    }
  }

  @override
  void dispose() {
    _asignaturasSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RolProvider>(
      builder: (context, rolProvider, child) {
        final esProfesor = rolProvider.esProfesor || rolProvider.esTester;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            title: Text(
              esProfesor ? 'Generar QR' : 'Escanear QR',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  _cargarAsignaturasDelUsuario();
                },
                tooltip: 'Recargar datos',
              ),
            ],
          ),
          body: esProfesor
              ? _construirVistaProfesor()
              : _construirVistaAlumno(),
        );
      },
    );
  }

  Widget _buildCardWrapper({required Widget child}) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(padding: const EdgeInsets.all(24.0), child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundWrapper({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).primaryColor.withValues(alpha: 0.1),
            Colors.white,
          ],
        ),
      ),
      child: child,
    );
  }

  Widget _construirVistaProfesor() {
    if (_asignaturaSeleccionada == null) {
      return _buildBackgroundWrapper(child: _construirSelectorAsignatura());
    }

    if (_actividadSeleccionada == null) {
      return _buildBackgroundWrapper(child: _construirSelectorActividad());
    }

    if (_tipoQRSeleccionado == null) {
      return _buildBackgroundWrapper(child: _construirSelectorTipoQR());
    }

    return _buildBackgroundWrapper(child: _construirVistaGeneradorQR());
  }

  Widget _construirSelectorAsignatura() {
    return _buildCardWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school,
                size: 40,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Seleccionar asignatura',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Elige la asignatura para crear el QR',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          if (_asignaturas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay asignaturas para mostrar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Importa un CSV con datos de alumnos para crear una asignatura o comprueba la lista de asignaturas ocultas',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _cargarAsignaturasDelUsuario,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Recargar',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._asignaturas.map((asignatura) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _asignaturaSeleccionada = asignatura['id'];
                      _nombreAsignaturaSeleccionada = asignatura['nombre'];
                      _cursoAsignaturaSeleccionada = asignatura['curso'];
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey[200]!,
                          blurRadius: 4,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.book,
                          color: Theme.of(context).primaryColor,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                asignatura['nombre'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${asignatura['curso']} - ${asignatura['codigo']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Theme.of(context).primaryColor,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _construirSelectorActividad() {
    // Calcular número total de actividades (predefinidas + personalizadas)
    final totalActividades = ([...infoActividad, ..._customActividad]).length;
    final bool compacto = totalActividades <= 4;

    return _buildCardWrapper(
      child: ConstrainedBox(
        // Si hay pocas actividades, damos una altura mínima para centrar mejor
        constraints: compacto ? const BoxConstraints(minHeight: 420) : const BoxConstraints(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _asignaturaSeleccionada = null;
                      _nombreAsignaturaSeleccionada = null;
                      _cursoAsignaturaSeleccionada = null;
                      _actividadSeleccionada = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 24),
                  label: const Text('Cambiar Asignatura'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_cursoAsignaturaSeleccionada ?? ''} - ${_nombreAsignaturaSeleccionada ?? ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.category,
                      size: 24,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Seleccionar actividad',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Mostrar grid compacto (centrado) si hay pocas actividades,
              // o grid con scroll interno si hay muchas.
              if (compacto)
                GridView.count(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.95,
                    // Combinar actividades predefinidas + personalizadas
                    children: ([...infoActividad, ..._customActividad]).map((actividad) {
                      final Color cardColor = actividad['color'] as Color;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _actividadSeleccionada = actividad['id'];
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cardColor.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cardColor.withValues(alpha: 0.15),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cardColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  actividad['icono'],
                                  size: 32,
                                  color: cardColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Text(
                                  actividad['nombre'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cardColor,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList()
                )
              else
                SizedBox(
                  height: 360, // altura fija para permitir scroll dentro del grid
                  child: GridView.count(
                    padding: EdgeInsets.zero,
                    shrinkWrap: false,
                    physics: const AlwaysScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.95,
                    // Combinar actividades predefinidas + personalizadas
                    children: ([...infoActividad, ..._customActividad]).map((actividad) {
                      final Color cardColor = actividad['color'] as Color;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _actividadSeleccionada = actividad['id'];
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cardColor.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cardColor.withValues(alpha: 0.15),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cardColor.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  actividad['icono'],
                                  size: 32,
                                  color: cardColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Text(
                                  actividad['nombre'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cardColor,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 16),

              // Botón para crear una nueva actividad personalizada (ahora debajo de las actividades)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _mostrarDialogoCrearActividad,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Crear actividad temporal', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirSelectorTipoQR() {
    // Buscar info de actividad entre las predefinidas y las personalizadas
    final actividadInfo = ([...infoActividad, ..._customActividad]).firstWhere(
          (act) => act['id'] == _actividadSeleccionada,
      orElse: () => infoActividad[0],
    );

    return _buildCardWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _actividadSeleccionada = null;
                  _tipoQRSeleccionado = null;
                });
              },
              icon: const Icon(Icons.arrow_back, size: 24),
              label: const Text('Cambiar Actividad'),
              style: TextButton.styleFrom(
                foregroundColor: Theme
                    .of(context)
                    .primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme
                  .of(context)
                  .primaryColor
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_cursoAsignaturaSeleccionada ??
                  ''} - ${_nombreAsignaturaSeleccionada ?? ''}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: actividadInfo['color'],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              actividadInfo['nombre'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme
                      .of(context)
                      .primaryColor
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_events,
                  size: 24,
                  color: Theme
                      .of(context)
                      .primaryColor,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Seleccionar insignia',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme
                          .of(context)
                          .primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Reemplazo: uso la lista combinada (definidas) para renderizar (sin personalizables)
          Builder(
            builder: (context) {
              return Column(
                children: tipoInsignia.map((tipoQR) {
                  final Color cardColor = tipoQR['color'] as Color;

                  return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _tipoQRSeleccionado = tipoQR['id'];
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cardColor.withValues(alpha: 0.7),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cardColor.withValues(alpha: 0.2),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cardColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  tipoQR['icono'],
                                  size: 40,
                                  color: cardColor,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Text(
                                  tipoQR['nombre'],
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: cardColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _construirVistaGeneradorQR() {
    final qrData =
        '${_asignaturaSeleccionada?.replaceAll('_', '-')}_${_actividadSeleccionada}_${_tipoQRSeleccionado}_${const Uuid().v4()}';

    // Buscar info de actividad entre predefinidas y las personalizadas
    final actividadInfo = ([...infoActividad, ..._customActividad]).firstWhere(
          (act) => act['id'] == _actividadSeleccionada,
      orElse: () => infoActividad[0],
    );

    final tipoQRInfo = tipoInsignia.firstWhere(
          (tipo) => tipo['id'] == _tipoQRSeleccionado,
      orElse: () => tipoInsignia[0],
    );

    final Color actividadColor = actividadInfo['color'];
    final Color qrColor = tipoQRInfo['color'];

    return _buildCardWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _tipoQRSeleccionado = null;
                });
              },
              icon: const Icon(Icons.arrow_back, size: 24),
              label: const Text('Cambiar Insignia'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_cursoAsignaturaSeleccionada ?? ''} - ${_nombreAsignaturaSeleccionada ?? ''}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: actividadColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      actividadInfo['nombre'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: qrColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tipoQRInfo['icono'], size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  tipoQRInfo['nombre'],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: qrColor.withValues(alpha: 0.3),
                  blurRadius: 15,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 250.0,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: () {
              setState(() {});
            },
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text(
              'Generar Nuevo Código',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: qrColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirVistaAlumno() {
    return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[100]!, Colors.white],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme
                                .of(context)
                                .primaryColor,
                            Theme
                                .of(context)
                                .primaryColor
                                .withValues(alpha: 0.85),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Escanea el Código QR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Apunta tu cámara al código del profesor para obtener insignias',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 8.0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calcular el ancho disponible (mismo que la tarjeta superior)
                      final anchoDisponible = constraints.maxWidth;

                      return Card(
                        elevation: 10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: anchoDisponible,
                          height: anchoDisponible, // Mantener ratio 1:1
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme
                                  .of(context)
                                  .primaryColor,
                              width: 4,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _buildScannerWidget(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24), // Espaciado inferior para el scroll
              ],
            ),
          ),
        )
    );
  }

  Widget _buildScannerWidget() {
    // Si está inicializando, mostrar cargando
    if (_isInitializingScanner) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Iniciando cámara...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Si hay error, mostrar mensaje de error
    if (_scannerError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No se puede acceder a la cámara',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Por favor, permite el acceso a la cámara en la configuración de tu navegador.',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isInitializingScanner = true;
                        _scannerError = null;
                      });
                      _initializeScanner();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Reintentar',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Scanner funcionando correctamente
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onQRDetected,
          errorBuilder: (context, error) {
            return _buildScannerError(context, error);
          },
        ),
        CustomPaint(
          painter: _ScannerOverlayPainter(
            borderColor: Theme.of(context).primaryColor,
          ),
          child: Container(),
        ),
      ],
    );
  }

  // Widget de error del scanner compatible con todas las versiones
  Widget _buildScannerError(BuildContext context, MobileScannerException error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Error al acceder a la cámara',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Por favor, verifica los permisos de cámara en tu navegador.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    _scannerController.stop();
                    _scannerController.start();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text(
                    'Reintentar',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: ${error.errorCode}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Muestra un diálogo para crear una nueva actividad personalizada
  void _mostrarDialogoCrearActividad() {
    final formKey = GlobalKey<FormState>();
    String nombre = '';
    // Asignar color e icono por defecto (no mostrar opciones de selección)
    Color selectedColor = Theme.of(context).primaryColor;
    // Icono más adecuado para actividad temporal
    IconData selectedIcon = Icons.local_activity;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Crear actividad temporal'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Introduce un nombre'
                        : null,
                    onSaved: (v) => nombre = v!.trim(),
                  ),
                  const SizedBox(height: 12),

                  // Vista previa simple con color e icono por defecto
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(selectedIcon, color: selectedColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState != null && formKey.currentState!.validate()) {
                  formKey.currentState!.save();

                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  final id = 'custom_act_${const Uuid().v4()}';
                  final nueva = {
                    'id': id,
                    'nombre': nombre,
                    'icono': selectedIcon,
                    'color': selectedColor,
                  };

                  setState(() {
                    _customActividad.add(nueva);
                    _actividadSeleccionada = id;
                  });

                  mostrarMensaje(scaffoldMessenger, 'Actividad creada', Colors.green);
                  navigator.pop();
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;

  _ScannerOverlayPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cornerLength = 50.0;
    final margin = 40.0;

    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin + cornerLength, margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin, margin + cornerLength),
      paint,
    );

    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin - cornerLength, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + cornerLength),
      paint,
    );

    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin + cornerLength, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin, size.height - margin - cornerLength),
      paint,
    );

    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin - cornerLength, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin, size.height - margin - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}