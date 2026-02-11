import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/constantes.dart';
import 'package:sistema_gamificacion/utils/device_detector_mobile.dart'
    if (dart.library.html) 'package:sistema_gamificacion/utils/device_detector_web.dart';

class PerfilAlumno extends StatefulWidget {
  final String usuarioId;
  final String idAsignatura;
  final String nombreAsignatura;
  final String curso;

  const PerfilAlumno({
    super.key,
    required this.usuarioId,
    required this.idAsignatura,
    required this.nombreAsignatura,
    required this.curso,
  });

  @override
  State<PerfilAlumno> createState() => _PerfilAlumnoState();
}

class _PerfilAlumnoState extends State<PerfilAlumno> {
  Map<String, dynamic>? _datosAlumno;
  List<String> _insigniasAlumno = [];
  int _puntuacionAlumno = 0;
  int _posicionAlumno = 0;
  int _totalAlumnos = 0;
  Future<void>? _cargaFuture;
  // Subscriptions para actualizar en tiempo real
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _usuarioSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _asignaturaSub;

  @override
  void initState() {
    super.initState();
    _cargaFuture = _cargarDatosOptimizado();
    // Configurar listeners en segundo plano para actualizaciones en tiempo real
    _setupListeners();
  }

  void _setupListeners() {
    // Listener del documento del usuario: actualiza datos e insignias automáticamente
    _usuarioSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(widget.usuarioId)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final insignias = data['Insignias'] as Map<String, dynamic>?;
      final puntuaciones = data['Puntuacion'] as Map<String, dynamic>?;

      final insigniasAlumno =
          (insignias?[widget.idAsignatura] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];

      final puntuacionAlumno = puntuaciones?[widget.idAsignatura] ?? 0;

      setState(() {
        _datosAlumno = data;
        _insigniasAlumno = insigniasAlumno;
        _puntuacionAlumno = puntuacionAlumno;
      });
      // Recalcular ranking al cambiar la puntuación del usuario: obtener lista de alumnos y llamar al helper
      try {
        final docAsignatura = await FirebaseFirestore.instance
            .collection('asignaturas')
            .doc(widget.idAsignatura)
            .get();
        if (docAsignatura.exists) {
          final dataAsignatura = docAsignatura.data() ?? {};
          final alumnosRaw = dataAsignatura['Alumnos'] as List<dynamic>? ?? [];
          final alumnosLista = alumnosRaw.map((e) => e.toString()).toList();
          await _recalcularRanking(alumnosLista);
        }
      } catch (e) {
        // ignorar errores de recálculo
      }
    });

    // Listener de la asignatura: recalcula el ranking cuando cambian la lista de alumnos
    _asignaturaSub = FirebaseFirestore.instance
        .collection('asignaturas')
        .doc(widget.idAsignatura)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;
      if (!doc.exists) return;
      final dataAsignatura = doc.data() ?? {};
      final alumnosRaw = dataAsignatura['Alumnos'] as List<dynamic>? ?? [];
      final alumnosLista = alumnosRaw.map((e) => e.toString()).toList();

      await _recalcularRanking(alumnosLista);
    });
  }

  @override
  void dispose() {
    _usuarioSub?.cancel();
    _asignaturaSub?.cancel();
    super.dispose();
  }

  // Recalcula la posición del alumno dentro del ranking de la asignatura
  Future<void> _recalcularRanking(List<String> alumnosLista) async {
    if (alumnosLista.isEmpty) {
      if (mounted) {
        setState(() {
          _posicionAlumno = 0;
          _totalAlumnos = 0;
        });
      }
      return;
    }

    try {
      List<MapEntry<String, int>> alumnosConPuntuacion = [];
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> userFutures = [];

      for (int i = 0; i < alumnosLista.length; i += 10) {
        final end = (i + 10 < alumnosLista.length) ? i + 10 : alumnosLista.length;
        final chunk = alumnosLista.sublist(i, end);

        userFutures.add(
          FirebaseFirestore.instance
              .collection('usuarios')
              .where(FieldPath.documentId, whereIn: chunk)
              .get(),
        );
      }

      final List<QuerySnapshot<Map<String, dynamic>>> userResults = await Future.wait(userFutures);

      for (var result in userResults) {
        for (var userDoc in result.docs) {
          final usuario = userDoc.id;
          final userData = userDoc.data();
          final punts = userData['Puntuacion'] as Map<String, dynamic>?;
          final punt = punts?[widget.idAsignatura] ?? 0;
          alumnosConPuntuacion.add(MapEntry(usuario, punt));
        }
      }

      alumnosConPuntuacion.sort((a, b) => b.value.compareTo(a.value));

      int posicion = 0;
      for (int i = 0; i < alumnosConPuntuacion.length; i++) {
        if (alumnosConPuntuacion[i].key == widget.usuarioId) {
          posicion = i + 1;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _posicionAlumno = posicion;
          _totalAlumnos = alumnosLista.length;
        });
      }
    } catch (e) {
      // ignorar error de recálculo para no romper la UI
    }
  }

  Future<void> _cargarDatosOptimizado() async {
    try {
      final alumnoFuture = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.usuarioId)
          .get();

      final asignaturaFuture = FirebaseFirestore.instance
          .collection('asignaturas')
          .doc(widget.idAsignatura)
          .get();

      final results = await Future.wait([alumnoFuture, asignaturaFuture]);
      final doc = results[0];
      final docAsignatura = results[1];

      if (!doc.exists) throw Exception('Datos de alumno no encontrados');
      if (!docAsignatura.exists) {
        throw Exception('Datos de asignatura no encontrados');
      }

      final data = doc.data()!;
      final insignias = data['Insignias'] as Map<String, dynamic>?;
      final puntuaciones = data['Puntuacion'] as Map<String, dynamic>?;

      final insigniasAlumno =
          (insignias?[widget.idAsignatura] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final puntuacionAlumno = puntuaciones?[widget.idAsignatura] ?? 0;

      final dataAsignatura = docAsignatura.data() ?? {};
      final alumnosRaw = dataAsignatura['Alumnos'] as List<dynamic>? ?? [];
      final alumnosLista = alumnosRaw.map((e) => e.toString()).toList();

      if (alumnosLista.isEmpty) {
        if (mounted) {
          setState(() {
            _datosAlumno = data;
            _insigniasAlumno = insigniasAlumno;
            _puntuacionAlumno = puntuacionAlumno;
            _posicionAlumno = 0;
            _totalAlumnos = 0;
          });
        }
        return;
      }

      List<MapEntry<String, int>> alumnosConPuntuacion = [];
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> userFutures = [];

      for (int i = 0; i < alumnosLista.length; i += 10) {
        final end = (i + 10 < alumnosLista.length)
            ? i + 10
            : alumnosLista.length;
        final chunk = alumnosLista.sublist(i, end);

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
          if (userData.containsKey('Puntuacion')) {
            final punts = userData['Puntuacion'] as Map<String, dynamic>?;
            final punt = punts?[widget.idAsignatura] ?? 0;
            alumnosConPuntuacion.add(MapEntry(usuario, punt));
          }
        }
      }

      alumnosConPuntuacion.sort((a, b) => b.value.compareTo(a.value));

      int posicion = 0;
      for (int i = 0; i < alumnosConPuntuacion.length; i++) {
        if (alumnosConPuntuacion[i].key == widget.usuarioId) {
          posicion = i + 1;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _datosAlumno = data;
          _insigniasAlumno = insigniasAlumno;
          _puntuacionAlumno = puntuacionAlumno;
          _posicionAlumno = posicion;
          _totalAlumnos = alumnosLista.length;
        });
      }
    } catch (e) {
      if (mounted) rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _cargaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              title: const Text(
                'Perfil del alumno',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              actions: const [SizedBox(width: 56)],
            ),
            bottomNavigationBar: AppBottomNavigationBar(
              currentIndex: 0,
              onTap: (indice) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                navegacionGlobalNotifier.value = indice;
              },
              totalPantallas: esDispositivoMovil() ? 3 : 2,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || _datosAlumno == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              title: Text(
                snapshot.hasError ? 'Error de carga' : 'Perfil del alumno',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            bottomNavigationBar: AppBottomNavigationBar(
              currentIndex: 0,
              onTap: (indice) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                navegacionGlobalNotifier.value = indice;
              },
              totalPantallas: esDispositivoMovil() ? 3 : 2,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      snapshot.hasError
                          ? 'Error al cargar los datos: ${snapshot.error}'
                          : 'No se pudieron cargar los datos del alumno ${widget.usuarioId}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _cargaFuture = _cargarDatosOptimizado();
                        });
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Reintentar carga',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            centerTitle: true,
            title: Text(
              widget.usuarioId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _cargaFuture = _cargarDatosOptimizado();
                  });
                },
                tooltip: 'Recargar datos',
              ),
            ],
          ),
          bottomNavigationBar: AppBottomNavigationBar(
            currentIndex: 0,
            onTap: (indice) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              navegacionGlobalNotifier.value = indice;
            },
            totalPantallas: esDispositivoMovil() ? 3 : 2,
          ),
          body: Container(
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 16),
                      _buildEstadisticasCard(),
                      const SizedBox(height: 16),
                      _buildAccionesRapidas(),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.workspace_premium,
                                  size: 28,
                                  color: Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Insignias',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: _mostrarDialogoAgregarInsignia,
                              icon: Icon(
                                Icons.add_circle,
                                color: Theme.of(context).primaryColor,
                                size: 28,
                              ),
                              tooltip: 'Añadir insignia',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInsigniasGrid(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    return Center(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.3),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    widget.usuarioId.isNotEmpty
                        ? widget.usuarioId[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_datosAlumno!['Nombre'] ?? ''} ${_datosAlumno!['Primer apellido'] ?? ''} ${_datosAlumno!['Segundo apellido'] ?? ''}'
                    .trim(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _datosAlumno!['Email'] ?? '',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 400),
                  child: Text(
                    '${widget.curso} - ${widget.nombreAsignatura}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstadisticasCard() {
    Color colorPosicion;
    IconData iconoPosicion;

    if (_posicionAlumno == 1) {
      colorPosicion = colorInsignia['oro']!;
      iconoPosicion = Icons.emoji_events;
    } else if (_posicionAlumno == 2) {
      colorPosicion = colorInsignia['plata']!;
      iconoPosicion = Icons.emoji_events;
    } else if (_posicionAlumno == 3) {
      colorPosicion = colorInsignia['bronce']!;
      iconoPosicion = Icons.emoji_events;
    } else {
      colorPosicion = Colors.white;
      iconoPosicion = Icons.leaderboard;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(iconoPosicion, color: colorPosicion, size: 32),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Posición en Ranking',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Text(
                        '#${_posicionAlumno > 0 ? _posicionAlumno : 'N/A'} de $_totalAlumnos',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'Puntuación',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_puntuacionAlumno',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 2,
                  height: 80,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                Column(
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      color: Colors.white,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Insignias',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_insigniasAlumno.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccionesRapidas() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _mostrarDialogoEditarDatos,
            icon: Icon(Icons.edit, color: Theme.of(context).primaryColor),
            label: Text(
              'Editar datos',
              style: TextStyle(color: Theme.of(context).primaryColor),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _confirmarEliminarDeAsignatura,
            icon: const Icon(Icons.person_remove, color: Colors.white),
            label: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInsigniasGrid() {
    if (_insigniasAlumno.isEmpty) {
      return Center(
        child: Column(
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 80,
              color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin insignias',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Calcular número de columnas según el tamaño de la pantalla
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount;
    double childAspectRatio;

    if (screenWidth > 1200) {
      // Pantalla grande
      crossAxisCount = 4;
      childAspectRatio = 0.90;
    } else if (screenWidth > 800) {
      // Pantalla pequeña
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
            (found.containsKey('icono') && found['icono'] is IconData)
            ? found['icono'] as IconData
            : Icons.workspace_premium;

        insigniaColor =
            (colorInsignia.containsKey(tipo) && colorInsignia[tipo] is Color)
            ? colorInsignia[tipo] as Color
            : (found.containsKey('color') && found['color'] is Color)
            ? found['color'] as Color
            : Theme.of(context).primaryColor;

        return Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            onTap: () => _confirmarEliminarInsignia(insignia, actividad, tipo),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [insigniaColor.withValues(alpha: 0.15), Colors.white],
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
                          color: insigniaColor.withValues(alpha: 0.5),
                          blurRadius: 15,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Icon(insigniaIcon, size: 40, color: Colors.white),
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
          ),
        );
      },
    );
  }

  Future<void> _mostrarDialogoEditarDatos() async {
    final nombreController = TextEditingController(
      text: _datosAlumno!['Nombre'] ?? '',
    );
    final primerApellidoController = TextEditingController(
      text: _datosAlumno!['Primer apellido'] ?? '',
    );
    final segundoApellidoController = TextEditingController(
      text: _datosAlumno!['Segundo apellido'] ?? '',
    );

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.all(16.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSeccionHeader(
                      icon: Icons.person,
                      titulo: 'Editar datos del alumno',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: nombreController,
                      decoration: InputDecoration(
                        labelText: 'Nombre *',
                        prefixIcon: Icon(
                          Icons.person_outlined,
                          color: Theme.of(context).primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: primerApellidoController,
                      decoration: InputDecoration(
                        labelText: 'Primer apellido *',
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Theme.of(context).primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: segundoApellidoController,
                      decoration: InputDecoration(
                        labelText: 'Segundo apellido',
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Theme.of(context).primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 20,
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            List<String> nuevosDatos = [
                              nombreController.text.trim(),
                              primerApellidoController.text.trim(),
                              segundoApellidoController.text.trim(),
                            ];
                            await actualizarDatosAlumno(
                              context,
                              widget.usuarioId,
                              nuevosDatos,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            setState(() {
                              _cargaFuture = _cargarDatosOptimizado();
                            });
                          },
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text(
                            'Guardar',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmarEliminarDeAsignatura() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmar = await mostrarDialogo(
      context,
      '¿Desea eliminar al alumno ${widget.usuarioId} de la asignatura ${widget.curso} - ${widget.nombreAsignatura}?',
    );

    if (confirmar) {
      if (mounted) {
        await eliminarAlumnoIDAsignatura(
          context,
          widget.usuarioId,
          widget.idAsignatura,
        );
      }
      if (mounted) {
        mostrarMensaje(scaffoldMessenger, 'Alumno eliminado', Colors.green);
        navigator.pop(true);
      }
    }
  }

  Future<void> _mostrarDialogoAgregarInsignia() async {
    String? actividadSeleccionada;
    String? tipoSeleccionado;
    String? errorActividad;
    String? errorTipo;

    final actividades = [
      {'id': 'ejercicio-clase', 'nombre': 'Ejercicio de pizarra'},
      {'id': 'pregunta-clase', 'nombre': 'Preguntas en clase'},
      {'id': 'test-platea', 'nombre': 'Test Platea'},
      {'id': 'ejercicio-evaluable', 'nombre': 'Ejercicio evaluable'},
    ];

    final tipos = [
      {'id': 'bronce', 'nombre': 'Bronce'},
      {'id': 'plata', 'nombre': 'Plata'},
      {'id': 'oro', 'nombre': 'Oro'},
    ];

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                insetPadding: const EdgeInsets.all(16.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  decoration: BoxDecoration(
                    color: Theme
                        .of(context)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSeccionHeader(
                            icon: Icons.badge,
                            titulo: 'Añadir insignia',
                          ),
                          const SizedBox(height: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Actividad *',
                                  prefixIcon: Icon(
                                    Icons.assignment,
                                    color: Theme
                                        .of(context)
                                        .primaryColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                initialValue: actividadSeleccionada,
                                items: actividades.map((act) {
                                  return DropdownMenuItem(
                                    value: act['id'],
                                    child: Text(act['nombre']!),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setStateDialog(() {
                                    actividadSeleccionada = value;
                                    if (value != null) {
                                      errorActividad = null;
                                    }
                                  });
                                },
                              ),
                              if (errorActividad != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8.0,
                                    left: 12,
                                  ),
                                  child: Text(
                                    errorActividad!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Tipo *',
                                  prefixIcon: Icon(
                                    Icons.star,
                                    color: Theme
                                        .of(context)
                                        .primaryColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                initialValue: tipoSeleccionado,
                                items: tipos.map((tipo) {
                                  return DropdownMenuItem(
                                    value: tipo['id'],
                                    child: Text(tipo['nombre']!),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setStateDialog(() {
                                    tipoSeleccionado = value;
                                    if (value != null) {
                                      errorTipo = null;
                                    }
                                  });
                                },
                              ),
                              if (errorTipo != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8.0,
                                    left: 12,
                                  ),
                                  child: Text(
                                    errorTipo!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                style: TextButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 20,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme
                                      .of(context)
                                      .primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 20,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () async {
                                  bool hayError = false;

                                  if (actividadSeleccionada == null ||
                                      actividadSeleccionada!.isEmpty) {
                                    setStateDialog(() {
                                      errorActividad =
                                      'Debe seleccionar una actividad';
                                    });
                                    hayError = true;
                                  }

                                  if (tipoSeleccionado == null ||
                                      tipoSeleccionado!.isEmpty) {
                                    setStateDialog(() {
                                      errorTipo = 'Debe seleccionar un tipo';
                                    });
                                    hayError = true;
                                  }

                                  if (!hayError) {
                                    // Capturar ScaffoldMessenger antes de operaciones async
                                    final scaffoldMessenger = ScaffoldMessenger
                                        .of(context);

                                    final uuid = DateTime
                                        .now()
                                        .millisecondsSinceEpoch
                                        .toString();
                                    final idInsignia =
                                        '${widget.idAsignatura.replaceAll('_',
                                        '-')}_${actividadSeleccionada}_${tipoSeleccionado}_$uuid';

                                    await registrarInsigniaAlumno(
                                      scaffoldMessenger,
                                      widget.usuarioId,
                                      idInsignia,
                                    );

                                    // Cerrar el diálogo
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                    }

                                    // Mostrar mensaje de confirmación
                                    if (mounted) {
                                      mostrarMensaje(
                                        scaffoldMessenger,
                                        'Insignia añadida',
                                        Colors.green,
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(
                                    Icons.add, color: Colors.white),
                                label: const Text(
                                  'Añadir',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
            );
          },
        );
      },
    );
  }

  Widget _buildSeccionHeader({required IconData icon, required String titulo}) {
    return Row(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmarEliminarInsignia(
    String idInsignia,
    String actividad,
    String tipo,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmar = await mostrarDialogo(
      context,
      '¿Desea eliminar la insignia de $tipo de la actividad "$actividad"?',
    );

    if (confirmar) {
      await eliminarInsignia(scaffoldMessenger, widget.usuarioId, idInsignia);
      setState(() {
        _cargaFuture = _cargarDatosOptimizado();
      });
    }
  }
}
