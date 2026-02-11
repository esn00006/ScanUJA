import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/gestionCSV.dart';
import 'package:sistema_gamificacion/utils/rol_provider.dart';
import 'package:sistema_gamificacion/pantallas/perfilAlumno.dart';
import 'package:sistema_gamificacion/pantallas/formRegistroAlumno.dart';
import 'package:sistema_gamificacion/utils/constantes.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/device_detector_mobile.dart'
    if (dart.library.html) 'package:sistema_gamificacion/utils/device_detector_web.dart';

class AlumnosAsignatura extends StatefulWidget {
  final String idAsignatura;
  final String nombreAsignatura;
  final String curso;

  const AlumnosAsignatura({
    super.key,
    required this.idAsignatura,
    required this.nombreAsignatura,
    required this.curso,
  });

  @override
  State<AlumnosAsignatura> createState() => _AlumnosAsignaturaState();
}

class _AlumnosAsignaturaState extends State<AlumnosAsignatura> {
  final TextEditingController busquedaController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String busquedaAlumno = '';
  Timer? _debounceTimer;

  Future<void>? _cargaInicialFuture;

  List<String> _alumnosLista = [];
  final Map<String, Map<String, dynamic>> _alumnosData = {};
  List<Map<String, dynamic>> _top5Ranking = [];

  String filtroOrden = 'nombre';
  bool ordenAsc = true;
  bool _isSearchFocused = false;
  List<String> _insigniasAlumno = [];
  bool _menuExpandido = false;

  // Subscriptions para actualización en tiempo real
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _asignaturaSub;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _usuariosSubs = {};

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
    _cargaInicialFuture = _cargarTodosLosDatos();
    // Configurar listeners para actualización en tiempo real
    _setupListeners();
  }

  Future<void> _cargarInsigniasAlumno() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final usuario = user.email!.split('@')[0];

      final docUsuario = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario)
          .get();

      if (docUsuario.exists) {
        final insignias =
            docUsuario.data()?['Insignias'] as Map<String, dynamic>?;
        final insigniasAsignatura =
            insignias?[widget.idAsignatura] as List<dynamic>?;
        if (mounted) {
          setState(() {
            _insigniasAlumno =
                insigniasAsignatura?.map((e) => e.toString()).toList() ?? [];
          });
        }
      }
    }
  }

  void _setupListeners() {
    // Listener del documento de la asignatura para detectar cambios en la lista de alumnos
    _asignaturaSub = FirebaseFirestore.instance
        .collection('asignaturas')
        .doc(widget.idAsignatura)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final alumnosRaw = data['Alumnos'] as List<dynamic>? ?? [];
      final nuevaListaAlumnos = alumnosRaw.map((e) => e.toString()).toList();

      // Detectar alumnos nuevos o eliminados
      final alumnosNuevos = nuevaListaAlumnos.where((a) => !_alumnosLista.contains(a)).toList();
      final alumnosEliminados = _alumnosLista.where((a) => !nuevaListaAlumnos.contains(a)).toList();

      // Actualizar lista de alumnos
      _alumnosLista = nuevaListaAlumnos;

      // Cancelar listeners de alumnos eliminados
      for (var alumno in alumnosEliminados) {
        _usuariosSubs[alumno]?.cancel();
        _usuariosSubs.remove(alumno);
        _alumnosData.remove(alumno);
      }

      // Cargar datos de alumnos nuevos y configurar listeners
      if (alumnosNuevos.isNotEmpty) {
        await _cargarDatosAlumnos(alumnosNuevos);
      }

      // Recalcular ranking y actualizar UI
      if (mounted) {
        _calcularRanking();
        setState(() {});
      }
    });
  }

  Future<void> _cargarDatosAlumnos(List<String> alumnos) async {
    if (alumnos.isEmpty) return;

    final List<Future<QuerySnapshot<Map<String, dynamic>>>> userFutures = [];

    for (int i = 0; i < alumnos.length; i += 10) {
      final end = (i + 10 < alumnos.length) ? i + 10 : alumnos.length;
      final chunk = alumnos.sublist(i, end);

      userFutures.add(
        FirebaseFirestore.instance
            .collection('usuarios')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      );
    }

    final List<QuerySnapshot<Map<String, dynamic>>> userResults =
        await Future.wait(userFutures);

    for (var result in userResults) {
      for (var userDoc in result.docs) {
        final usuario = userDoc.id;
        final userData = userDoc.data();
        final puntuaciones = userData['Puntuacion'] as Map<String, dynamic>?;
        final puntuacion = puntuaciones?[widget.idAsignatura] ?? 0;

        _alumnosData[usuario] = {
          'Nombre': userData['Nombre'] ?? '',
          'Primer apellido': userData['Primer apellido'] ?? '',
          'Segundo apellido': userData['Segundo apellido'] ?? '',
          'Email': userData['Email'] ?? '',
          'puntuacion': puntuacion,
        };

        // Configurar listener para este alumno
        _setupUsuarioListener(usuario);
      }
    }
  }

  void _setupUsuarioListener(String usuario) {
    // Evitar duplicar listeners
    if (_usuariosSubs.containsKey(usuario)) return;

    _usuariosSubs[usuario] = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(usuario)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (!doc.exists) return;

      final userData = doc.data() ?? {};
      final puntuaciones = userData['Puntuacion'] as Map<String, dynamic>?;
      final puntuacion = puntuaciones?[widget.idAsignatura] ?? 0;

      // Actualizar datos del alumno
      if (_alumnosData.containsKey(usuario)) {
        setState(() {
          _alumnosData[usuario] = {
            'Nombre': userData['Nombre'] ?? '',
            'Primer apellido': userData['Primer apellido'] ?? '',
            'Segundo apellido': userData['Segundo apellido'] ?? '',
            'Email': userData['Email'] ?? '',
            'puntuacion': puntuacion,
          };
          // Recalcular ranking con los nuevos datos
          _calcularRanking();
        });
      }
    });
  }

  Future<void> _cargarTodosLosDatos() async {
    final asignaturaFuture = FirebaseFirestore.instance
        .collection('asignaturas')
        .doc(widget.idAsignatura)
        .get();

    await Future.wait([_cargarInsigniasAlumno(), asignaturaFuture]);

    final docAsignatura = await asignaturaFuture;

    if (!docAsignatura.exists) {
      if (mounted) setState(() {});
      return;
    }

    final data = docAsignatura.data() ?? {};
    final alumnosRaw = data['Alumnos'] as List<dynamic>? ?? [];
    _alumnosLista = alumnosRaw.map((e) => e.toString()).toList();

    if (_alumnosLista.isEmpty) {
      if (mounted) {
        setState(() {
          _top5Ranking = [];
        });
      }
      return;
    }

    // Cargar datos de todos los alumnos y configurar listeners
    await _cargarDatosAlumnos(_alumnosLista);

    _calcularRanking();

    if (mounted) {
      setState(() {});
    }
  }

  void _calcularRanking() {
    List<Map<String, dynamic>> alumnosConPuntuacion = [];

    _alumnosData.forEach((usuario, datos) {
      String nombreCompleto = '';
      if (datos['Nombre'] != null && datos['Nombre'].toString().isNotEmpty) {
        nombreCompleto = '${datos['Nombre']} ${datos['Primer apellido'] ?? ''}';
      }

      alumnosConPuntuacion.add({
        'usuario': usuario,
        'nombre': nombreCompleto.trim(),
        'puntuacion': datos['puntuacion'],
      });
    });

    alumnosConPuntuacion.sort(
      (a, b) => b['puntuacion'].compareTo(a['puntuacion']),
    );
    _top5Ranking = alumnosConPuntuacion.take(5).toList();
  }

  void recargarDatos() {
    if (mounted) {
      setState(() {
        _cargaInicialFuture = _cargarTodosLosDatos();
      });
    }
  }

  @override
  void dispose() {
    busquedaController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    // Cancelar todas las suscripciones
    _asignaturaSub?.cancel();
    for (var sub in _usuariosSubs.values) {
      sub.cancel();
    }
    _usuariosSubs.clear();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          busquedaAlumno = value;
        });
      }
    });
  }

  Widget _buildRankingWidget() {
    if (_top5Ranking.isEmpty) {
      return const SizedBox.shrink();
    }

    final top5 = _top5Ranking;

    return Card(
      elevation: 8,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withValues(alpha: 0.1),
              Theme.of(context).primaryColor.withValues(alpha: 0.05),
              Colors.white,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Ranking Top 5',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Podio - Top 3
            Column(
              children: [
                if (top5.isNotEmpty)
                  _buildPodiumCircle(top5[0], 1, const Color(0xFFFFD700), 95),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (top5.length > 1)
                      Expanded(
                        child: _buildPodiumCircle(
                          top5[1],
                          2,
                          const Color(0xFFC0C0C0),
                          80,
                        ),
                      ),
                    const SizedBox(width: 12),
                    if (top5.length > 2)
                      Expanded(
                        child: _buildPodiumCircle(
                          top5[2],
                          3,
                          const Color(0xFFCD7F32),
                          80,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (top5.length > 3) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              ...top5.skip(3).take(2).map((alumno) {
                final posicion = top5.indexOf(alumno) + 1;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$posicion',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          alumno['usuario'].length > 15
                              ? '${alumno['usuario'].substring(0, 13)}..'
                              : alumno['usuario'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${alumno['puntuacion']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPodiumCircle(
    Map<String, dynamic> alumno,
    int posicion,
    Color medalColor,
    double size,
  ) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: size / 2,
                backgroundColor: medalColor,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      alumno['usuario'].length > 8
                          ? '${alumno['usuario'].substring(0, 6)}..'
                          : alumno['usuario'],
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: posicion == 1 ? 13 : 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            '${alumno['puntuacion']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: medalColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  '$posicion',
                  style: TextStyle(
                    color: medalColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> ordenarAlumnos(List<String> alumnos) {
    List<String> resultado = List.from(alumnos);

    if (busquedaAlumno.isNotEmpty) {
      if (filtroOrden == 'nombre') {
        final q = busquedaAlumno.toLowerCase();
        resultado = resultado.where((al) {
          if (al.toLowerCase().contains(q)) {
            return true;
          }

          final datos = _alumnosData[al];
          if (datos != null) {
            final nombre = (datos['Nombre'] ?? '').toString().toLowerCase();
            final apellido1 = (datos['Primer apellido'] ?? '')
                .toString()
                .toLowerCase();
            final apellido2 = (datos['Segundo apellido'] ?? '')
                .toString()
                .toLowerCase();
            final nombreCompleto = '$nombre $apellido1 $apellido2'.trim();

            return nombre.contains(q) ||
                apellido1.contains(q) ||
                apellido2.contains(q) ||
                nombreCompleto.contains(q);
          }

          return false;
        }).toList();
      } else {
        final puntuacionBuscada = int.tryParse(busquedaAlumno);
        if (puntuacionBuscada != null) {
          resultado = resultado.where((al) {
            final puntuacion = (_alumnosData[al]?['puntuacion'] ?? 0) as int;
            return puntuacion >= puntuacionBuscada;
          }).toList();
        }
      }
    }

    resultado.sort((a, b) {
      int comparacion = 0;

      if (filtroOrden == 'nombre') {
        comparacion = a.compareTo(b);
      } else {
        final puntuacionA = (_alumnosData[a]?['puntuacion'] ?? 0) as int;
        final puntuacionB = (_alumnosData[b]?['puntuacion'] ?? 0) as int;
        comparacion = puntuacionA.compareTo(puntuacionB);
      }

      return ordenAsc ? comparacion : -comparacion;
    });

    return resultado;
  }

  void _menuFiltros(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Filtrar y ordenar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: filtroOrden == 'nombre'
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.sort_by_alpha,
                  color: filtroOrden == 'nombre'
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
              ),
              title: const Text('Ordenar por nombre'),
              trailing: filtroOrden == 'nombre'
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                setState(() {
                  filtroOrden = 'nombre';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: filtroOrden == 'puntuacion'
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.star,
                  color: filtroOrden == 'puntuacion'
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
              ),
              title: const Text('Ordenar por puntuación'),
              trailing: filtroOrden == 'puntuacion'
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                setState(() {
                  filtroOrden = 'puntuacion';
                });
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ordenAsc
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_upward,
                  color: ordenAsc
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
              ),
              title: const Text('Ascendente'),
              trailing: ordenAsc
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                setState(() {
                  ordenAsc = true;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: !ordenAsc
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_downward,
                  color: !ordenAsc
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
              ),
              title: const Text('Descendente'),
              trailing: !ordenAsc
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                setState(() {
                  ordenAsc = false;
                });
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuFlotante() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Opciones expandibles
        if (_menuExpandido) ...[
          _buildOpcionMenu(
            icono: Icons.person_add,
            etiqueta: 'Añadir alumno',
            color: Colors.blue,
            onTap: () async {
              setState(() {
                _menuExpandido = false;
              });
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FormularioRegistroAlumno(
                    idAsignatura: widget.idAsignatura,
                  ),
                ),
              );
              if (resultado == true) {
                recargarDatos();
              }
            },
          ),
          const SizedBox(height: 12),

          // Opción: Añadir profesor por usuario
          _buildOpcionMenu(
            icono: Icons.person_add,
            etiqueta: 'Añadir profesor',
            color: Colors.orange,
            onTap: () async {
              setState(() {
                _menuExpandido = false;
              });
              await _mostrarDialogoAgregarProfesor();
            },
          ),
          const SizedBox(height: 12),

          // Opción 2: Importar CSV
          _buildOpcionMenu(
            icono: Icons.upload_file,
            etiqueta: 'Importar CSV',
            color: Colors.green,
            onTap: () async {
              setState(() {
                _menuExpandido = false;
              });
              await importarCSVNotas(context, widget.idAsignatura);
              recargarDatos();
            },
          ),
          const SizedBox(height: 12),

          // Opción 3: Exportar a CSV
          _buildOpcionMenu(
            icono: Icons.download,
            etiqueta: 'Exportar CSV',
            color: Colors.purple,
            onTap: () async {
              setState(() {
                _menuExpandido = false;
              });
              await exportarCSVNotas(context, widget.idAsignatura);
            },
          ),
          const SizedBox(height: 16),
        ],

        // Botón principal flotante
        FloatingActionButton(
          onPressed: () {
            setState(() {
              _menuExpandido = !_menuExpandido;
            });
          },
          backgroundColor: Theme.of(context).primaryColor,
          child: AnimatedRotation(
            turns: _menuExpandido ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _menuExpandido ? Icons.close : Icons.add,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpcionMenu({
    required IconData icono,
    required String etiqueta,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Etiqueta
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Botón circular
        Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icono, color: Colors.white, size: 28),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _mostrarDialogoAgregarProfesor() async {
    final TextEditingController usuarioController = TextEditingController();

    String? dialogError;
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Usamos StatefulBuilder para controlar estado local del diálogo
        return StatefulBuilder(builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Añadir profesor por usuario'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: usuarioController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      hintText: 'Ingrese el nombre de usuario (SIDUJA)',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Mostrar texto de error dentro del diálogo si existe
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 12),
                  ],

                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                      },
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final usuario = usuarioController.text.trim();

                        if (usuario.isEmpty) {
                          (dialogContext as Element).markNeedsBuild();
                          dialogError = 'Por favor, introduzca el nombre de usuario';
                          return;
                        }

                        setState(() {
                          isLoading = true;
                          dialogError = null;
                        });

                        try {
                          final registrado = await usuarioRegistrado(usuario);
                          if (!registrado) {
                            setState(() {
                              dialogError = 'El usuario $usuario no está registrado en el sistema';
                              isLoading = false;
                            });
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            mostrarMensaje(scaffoldMessenger, 'El usuario $usuario no está registrado en el sistema', Colors.red);
                            return;
                          }

                          final rol = await obtenerRol(usuario);
                          if (rol == null || rol.toUpperCase() != 'PROFESOR') {
                            setState(() {
                              dialogError = 'El usuario $usuario no tiene rol PROFESOR';
                              isLoading = false;
                            });
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            mostrarMensaje(scaffoldMessenger, 'El usuario $usuario no tiene rol PROFESOR', Colors.red);
                            return;
                          }

                          final asignaturaDoc = await FirebaseFirestore.instance.collection('asignaturas').doc(widget.idAsignatura).get();
                          final profesores = List<String>.from(asignaturaDoc.data()?['Profesores'] ?? []);
                          if (profesores.contains(usuario)) {
                            setState(() {
                              dialogError = 'El profesor $usuario ya está asignado a esta asignatura';
                              isLoading = false;
                            });
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            mostrarMensaje(scaffoldMessenger, 'El profesor $usuario ya está asignado a esta asignatura', Colors.orange);
                            return;
                          }

                          await registrarProfesorAsignatura(usuario, widget.idAsignatura);

                          Navigator.of(dialogContext).pop();
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          mostrarMensaje(scaffoldMessenger, 'Profesor $usuario añadido correctamente', Colors.green);
                          recargarDatos();
                        } catch (e) {
                          setState(() {
                            dialogError = 'Error al añadir profesor: $e';
                            isLoading = false;
                          });
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          mostrarMensaje(scaffoldMessenger, 'Error al añadir profesor: $e', Colors.red);
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Añadir profesor'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RolProvider>(
      builder: (context, rolProvider, child) {
        final rolUsuario = rolProvider.rol;

        return GestureDetector(
          onTap: () {
            if (_menuExpandido) {
              setState(() {
                _menuExpandido = false;
              });
            }
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              centerTitle: true,
              title: Text(
                widget.idAsignatura.replaceAll('_', ' - '),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () {
                    recargarDatos();
                  },
                  tooltip: 'Recargar datos',
                ),
              ],
            ),
            floatingActionButton:
                rolUsuario != null && rolUsuario.toUpperCase() == 'PROFESOR'
                ? _buildMenuFlotante()
                : null,
            bottomNavigationBar: AppBottomNavigationBar(
              currentIndex: 0, // Índice de Homepage
              onTap: (indice) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                navegacionGlobalNotifier.value = indice;
              },
              totalPantallas: esDispositivoMovil() ? 3 : 2,
            ),
            body: FutureBuilder<void>(
              future: _cargaInicialFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar datos: ${snapshot.error.toString()}',
                    ),
                  );
                }

                if (rolUsuario == null) {
                  return const Center(
                    child: Text('Rol de usuario no disponible.'),
                  );
                }

                return rolUsuario.toUpperCase() == 'ALUMNO'
                    ? _buildVistaAlumno()
                    : _buildVistaProfesor();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildVistaProfesor() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 8.0),
            child: Center(
              child: Text(
                widget.nombreAsignatura,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_alumnosLista.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildRankingWidget(),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.people,
                      size: 28,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Alumnos',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    _menuFiltros(context);
                  },
                  icon: Icon(
                    Icons.filter_list,
                    color: Theme.of(context).primaryColor,
                  ),
                  tooltip: 'Filtrar y ordenar',
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: busquedaController,
                focusNode: _searchFocusNode,
                keyboardType: filtroOrden == 'puntuacion'
                    ? TextInputType.number
                    : TextInputType.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: filtroOrden == 'nombre'
                      ? 'Buscar por nombre...'
                      : 'Puntuación mínima...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                  prefixIcon: Icon(
                    _isSearchFocused ? Icons.edit : Icons.search,
                    color: Colors.white,
                    size: 22,
                  ),
                  suffixIcon: busquedaAlumno.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              busquedaController.clear();
                              busquedaAlumno = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),

          _buildListaAlumnos(),

          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildVistaAlumno() {
    final user = FirebaseAuth.instance.currentUser;
    String usuarioActual = '';
    int puntuacionAlumno = 0;
    int posicionAlumno = 0;

    if (user != null && user.email != null) {
      usuarioActual = user.email!.split('@')[0];
      puntuacionAlumno =
          (_alumnosData[usuarioActual]?['puntuacion'] ?? 0) as int;

      // Cálculo de posición: ahora es rápido porque _alumnosData ya está cargado
      final alumnosOrdenados = List<String>.from(_alumnosLista);
      alumnosOrdenados.sort((a, b) {
        final puntosA = (_alumnosData[a]?['puntuacion'] ?? 0) as int;
        final puntosB = (_alumnosData[b]?['puntuacion'] ?? 0) as int;
        return puntosB.compareTo(puntosA);
      });
      posicionAlumno = alumnosOrdenados.indexOf(usuarioActual) + 1;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 8.0),
            child: Center(
              child: Text(
                widget.nombreAsignatura,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_alumnosLista.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildRankingWidget(),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            posicionAlumno > 0 ? '#$posicionAlumno' : 'N/A',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'Puesto',
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  usuarioActual,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$puntuacionAlumno puntos',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        posicionAlumno > 0 && posicionAlumno <= 3
                            ? Icons.emoji_events
                            : Icons.grade,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 0.0),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Mis Insignias',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_insigniasAlumno.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.emoji_events_outlined,
                          size: 100,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Aún no tienes insignias',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Escanea códigos QR para obtener insignias\ny aumentar tu puntuación',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      // Calcular número de columnas según el tamaño de la pantalla
                      final screenWidth = MediaQuery.of(context).size.width;
                      int crossAxisCount;
                      double childAspectRatio;

                      if (screenWidth > 1200) {
                        // Pantalla grande (desktop)
                        crossAxisCount = 4;
                        childAspectRatio = 0.90;
                      } else if (screenWidth > 800) {
                        // Pantalla mediana (tablet)
                        crossAxisCount = 3;
                        childAspectRatio = 0.85;
                      } else {
                        // Móvil
                        crossAxisCount = 2;
                        childAspectRatio = 0.85;
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: childAspectRatio,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _insigniasAlumno.length,
                        itemBuilder: (context, index) {
                      final insignia = _insigniasAlumno[index];
                      final partes = insignia.split('_');

                      String actividad = '';
                      String tipo = '';

                      if (partes.length >= 3) {
                        actividad = partes[1].replaceAll('-', ' ');
                        tipo = partes[2];
                      }

                      Color insigniaColor;
                      IconData insigniaIcon;

                      final found = tipoInsignia.firstWhere(
                        (e) => e['id'] == tipo,
                        orElse: () => {},
                      );

                      insigniaIcon =
                          (found.containsKey('icono') &&
                              found['icono'] is IconData)
                          ? found['icono'] as IconData
                          : Icons.workspace_premium;

                      insigniaColor =
                          (colorInsignia.containsKey(tipo) &&
                              colorInsignia[tipo] is Color)
                          ? colorInsignia[tipo] as Color
                          : (found.containsKey('color') &&
                                found['color'] is Color)
                          ? found['color'] as Color
                          : Theme.of(context).primaryColor;

                      return Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                insigniaColor.withValues(alpha: 0.15),
                                Colors.white,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: insigniaColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: insigniaColor.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  insigniaIcon,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                actividad.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: insigniaColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${obtenerPuntosPorInsignia(tipo)} PUNTOS',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaAlumnos() {
    final alumnosFiltrados = ordenarAlumnos(_alumnosLista);

    if (alumnosFiltrados.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No se encontraron usuarios con "$busquedaAlumno"',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      key: ValueKey(busquedaAlumno),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: alumnosFiltrados.length,
      itemBuilder: (context, index) {
        final usuarioId = alumnosFiltrados[index];
        final puntuacion = (_alumnosData[usuarioId]?['puntuacion'] ?? 0) as int;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () async {
              final resultado = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PerfilAlumno(
                    usuarioId: usuarioId,
                    idAsignatura: widget.idAsignatura,
                    nombreAsignatura: widget.nombreAsignatura,
                    curso: widget.curso,
                  ),
                ),
              );
              if (resultado == true) {
                recargarDatos();
              }
            },
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                usuarioId.isNotEmpty ? usuarioId[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              usuarioId,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Row(
              children: [
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '$puntuacion puntos',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
