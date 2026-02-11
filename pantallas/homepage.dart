import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_gamificacion/pantallas/asignatura.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/gestionCSV.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/rol_provider.dart';
import 'package:sistema_gamificacion/utils/asignaturas_notifier.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final user = FirebaseAuth.instance.currentUser;
  String filtroOrden = 'nombre';
  bool ordenAsc = true;
  Set<String> asignaturasOcultas = {};
  Key _refreshKey = UniqueKey(); // Para forzar la recarga del FutureBuilder

  @override
  void initState() {
    super.initState();
    _cargarAsignaturasOcultas();
  }

  Future<void> _cargarAsignaturasOcultas() async {
    if (user?.email != null) {
      final usuario = user!.email!.split('@')[0];
      final prefs = await SharedPreferences.getInstance();
      final ocultas = prefs.getStringList('asignaturasOcultas_$usuario') ?? [];
      setState(() {
        asignaturasOcultas = ocultas.toSet();
      });
    }
  }

  Future<void> _guardarAsignaturasOcultas() async {
    if (user?.email != null) {
      final usuario = user!.email!.split('@')[0];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'asignaturasOcultas_$usuario',
        asignaturasOcultas.toList(),
      );
    }
  }

  void _recargarDatos() {
    setState(() {
      _refreshKey = UniqueKey(); // Cambia la key para forzar rebuild del FutureBuilder
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RolProvider>(
      builder: (context, rolProvider, child) {
        final String? rolUsuario = rolProvider.rol;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            title: const Text(
              "Inicio",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _recargarDatos,
                tooltip: 'Recargar asignaturas',
              ),
            ],
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
            child: Column(
              children: [
                if (rolUsuario != null && rolUsuario.toLowerCase() != 'alumno')
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor,
                          Theme.of(context).primaryColor.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          try {
                            await importarCSVAsignatura(context);
                          } catch (e) {
                            if (context.mounted) {
                              finCarga(context);
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.upload_file,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Importar CSV',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 4.0, 24.0, 0.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.school,
                            size: 30,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            (rolUsuario != null &&
                                    rolUsuario.toLowerCase() == 'alumno')
                                ? 'Mis Asignaturas'
                                : 'Asignaturas',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),

                      // Filtro de orden
                      IconButton(
                        onPressed: () {
                          menuFiltros(context);
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
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: FutureBuilder<DocumentSnapshot>(
                      key: _refreshKey, // Key para forzar rebuild al recargar
                      // Obtener la lista de asignaturas del usuario y luego cargar solo esas asignaturas
                      future: () async {
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser == null || currentUser.email == null) {
                          throw 'Usuario no autenticado';
                        }
                        final usuario = currentUser.email!.split('@')[0];
                        return FirebaseFirestore.instance
                            .collection('usuarios')
                            .doc(usuario)
                            .get();
                      }(),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (userSnapshot.hasError) {
                          return Center(child: Text('Error: ${userSnapshot.error}'));
                        }

                        final userDoc = userSnapshot.data;
                        final userData = userDoc?.data() as Map<String, dynamic>?;
                        final asignaturasIds = List<String>.from(userData?['Asignaturas'] ?? []);

                        if (asignaturasIds.isEmpty) {
                          return const Center(child: Text('No hay asignaturas registradas'));
                        }

                        // Cargar documentos de asignaturas indicadas (en paralelo)
                        return FutureBuilder<List<DocumentSnapshot>>(
                          future: Future.wait(asignaturasIds.map((id) => FirebaseFirestore.instance.collection('asignaturas').doc(id).get())),
                          builder: (context, asignaturasSnapshot) {
                            if (asignaturasSnapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (asignaturasSnapshot.hasError) {
                              return Center(child: Text('Error: ${asignaturasSnapshot.error}'));
                            }

                            final docs = asignaturasSnapshot.data?.where((d) => d.exists).toList() ?? [];
                            if (docs.isEmpty) {
                              return const Center(child: Text('No hay asignaturas registradas'));
                            }

                            return construirListaAsignaturas(docs);
                          },
                        );
                      },
                    ),
                  ),
                ),
                if (asignaturasOcultas.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Material(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 4,
                      child: InkWell(
                        onTap: mostrarAsignaturasOcultas,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.visibility,
                                size: 20,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ver asignaturas ocultas (${asignaturasOcultas.length})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget construirListaAsignaturas(List<DocumentSnapshot> documentos) {
    var asignaturas = documentos.where((doc) {
      return !asignaturasOcultas.contains(doc.id);
    }).toList();

    asignaturas.sort((a, b) {
      var dataA = a.data() as Map<String, dynamic>;
      var dataB = b.data() as Map<String, dynamic>;

      int comparacion;
      if (filtroOrden == 'nombre') {
        String nombreA = dataA['Nombre'] ?? '';
        String nombreB = dataB['Nombre'] ?? '';
        comparacion = nombreA.compareTo(nombreB);
      } else {
        String cursoA = a.id.split('_')[0];
        String cursoB = b.id.split('_')[0];
        comparacion = cursoA.compareTo(cursoB);
      }

      return ordenAsc ? comparacion : -comparacion;
    });

    if (asignaturas.isEmpty) {
      return const Center(child: Text('No hay asignaturas visibles'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: asignaturas.length,
      itemBuilder: (context, index) {
        var asignatura = asignaturas[index];
        var data = asignatura.data() as Map<String, dynamic>;
        String idAsignatura = asignatura.id;
        String nombre = data['Nombre'] ?? 'Sin nombre';
        String curso = data['Curso'];
        String codigo = data['Codigo'] ?? '';

        return Card(
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AlumnosAsignatura(
                    idAsignatura: idAsignatura,
                    nombreAsignatura: nombre,
                    curso: curso,
                  ),
                ),
              );
            },
            onLongPress: () {
              opcionesAsignatura(idAsignatura, nombre, curso);
            },
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: Theme.of(context).primaryColor,
                          child: const Icon(
                            Icons.book,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    curso,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                                if (codigo.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    codigo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      size: 22,
                      color: Colors.grey[600],
                    ),
                    onPressed: () {
                      opcionesAsignatura(idAsignatura, nombre, curso);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void menuFiltros(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle visual
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
                  color: filtroOrden == 'curso'
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_month,
                  color: filtroOrden == 'curso'
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
              ),
              title: const Text('Ordenar por curso'),
              trailing: filtroOrden == 'curso'
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                setState(() {
                  filtroOrden = 'curso';
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

  void opcionesAsignatura(String idAsignatura, String nombre, String curso) {
    final rolProvider = Provider.of<RolProvider>(context, listen: false);
    final String? rolUsuario = rolProvider.rol;
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      // Proteger nombre largo para que no haga overflow
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          nombre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        curso,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.visibility_off,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  title: const Text('Ocultar asignatura'),
                  subtitle: const Text('La asignatura se ocultará temporalmente'),
                  onTap: () {
                    Navigator.pop(context);
                    verifOcultarAsignatura(idAsignatura, nombre, curso);
                  },
                ),
                if (rolUsuario != null && rolUsuario.toLowerCase() != 'alumno')
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.delete, color: Colors.red[700]),
                    ),
                    title: const Text(
                      'Eliminar asignatura',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: const Text(
                      'La asignatura se borrará permanentemente',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      verifEliminarAsignatura(idAsignatura, nombre, curso);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> verifEliminarAsignatura(
    String idAsignatura,
    String nombre,
    String curso,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!await mostrarDialogo(
      context,
      '¿Está seguro de que desea eliminar la siguiente asignatura?\n'
      '$curso - $nombre\n\n'
      '[!] Esta acción eliminará todos los datos de la asignatura, además de deshacer el vínculo con los alumnos registrados.',
    )) {
      mostrarMensaje(
        scaffoldMessenger,
        'Se ha cancelado la eliminación de la asignatura:\n"$curso - $nombre"',
        Colors.green,
      );
      return;
    }

    try {
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        await eliminarAsignaturaBDD(context, idAsignatura);
      }
    } catch (e) {
      mostrarMensaje(
        scaffoldMessenger,
        'Error al eliminar la asignatura "$curso - $nombre":\n'
        ' $e',
        Colors.red,
      );
    }
  }

  Future<void> verifOcultarAsignatura(
    String idAsignatura,
    String nombre,
    String curso,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!await mostrarDialogo(
      context,
      '¿Desea ocultar la asignatura?\n$curso - $nombre',
    )) {
      mostrarMensaje(
        scaffoldMessenger,
        'Se ha cancelado el ocultamiento de la asignatura\n$curso - $nombre',
        Colors.green,
      );
      return;
    }
    setState(() {
      asignaturasOcultas.add(idAsignatura);
    });
    await _guardarAsignaturasOcultas();
    AsignaturasNotifier().notificarCambio(); // Notificar el cambio
    mostrarMensaje(scaffoldMessenger, 'Asignatura ocultada correctamente', Colors.green);
  }

  void mostrarAsignaturasOcultas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.visibility_off, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            const Text('Asignaturas ocultas', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('asignaturas')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var asignaturasOcultas = snapshot.data!.docs
                  .where((doc) => this.asignaturasOcultas.contains(doc.id))
                  .toList();

              if (asignaturasOcultas.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'No hay asignaturas ocultas',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: asignaturasOcultas.length,
                itemBuilder: (context, index) {
                  var asignatura = asignaturasOcultas[index];
                  var data = asignatura.data() as Map<String, dynamic>;
                  String nombre = data['Nombre'] ?? 'Sin nombre';
                  String curso = data['Curso'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.book,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        curso,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.visibility,
                          color: Theme.of(context).primaryColor,
                        ),
                        tooltip: 'Mostrar asignatura',
                        onPressed: () async {
                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);

                          setState(() {
                            this.asignaturasOcultas.remove(asignatura.id);
                          });
                          await _guardarAsignaturasOcultas();
                          AsignaturasNotifier()
                              .notificarCambio(); // Notificar el cambio
                          navigator.pop();
                          mostrarMensaje(
                            scaffoldMessenger,
                            'Mostrando "$curso - $nombre" de nuevo',
                            Colors.green,
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asignaturasOcultas.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);

                        setState(() {
                          asignaturasOcultas.clear();
                        });
                        await _guardarAsignaturasOcultas();
                        AsignaturasNotifier().notificarCambio(); // Notificar el cambio
                        navigator.pop();
                        mostrarMensaje(
                          scaffoldMessenger,
                          'Mostrando todas las asignaturas ocultas',
                          Colors.green,
                        );
                      },
                      icon: const Icon(Icons.visibility),
                      label: const Text('Mostrar todas'),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.8)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
