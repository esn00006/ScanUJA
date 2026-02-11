import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/constantes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'gestionCSV_mobile.dart'
    if (dart.library.html) 'gestionCSV_web.dart'
    as platform;

// Función para importar un listado de alumnos pertenecientes a una asignatura (listado general)
// Añade en la BDD tanto los datos de la asignatura como los de los alumnos
Future<void> importarCSVAsignatura(BuildContext context) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  bool cargando = false;
  List<String> nuevosAlumnosAsignatura =
      []; // Lista de control para deshacer en caso necesario
  String idAsignatura = '';

  try {
    // --------------- Procesamiento del fichero CSV ---------------
    final result = await FilePicker.platform.pickFiles(
      // Selección del fichero CSV
      type: FileType.custom,
      withData: true,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.first.bytes == null) {
      return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
    }

    String nombreFichero = result.files.first.name;

    if (!context.mounted) return;

    final confirmado = await mostrarDialogo(
      context,
      '¿Está seguro de que desea importar el fichero $nombreFichero?',
    );

    if (!confirmado) {
      return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
    }

    // Capturar navigator antes de mostrar diálogo de carga
    if (!context.mounted) return;
    inicioCarga(context);
    cargando = true;

    List<List<dynamic>> rows;

    try {
      final csvString = utf8.decode(result.files.first.bytes!);
      rows = const CsvToListConverter().convert(csvString);
    } catch (e) {
      throw 'Compruebe que el fichero tiene codificación CSV UTF-8';
    }

    if (rows.isEmpty) {
      throw 'Se ha importado un fichero vacío.';
    }

    // --------------- Procesamiento de la asignatura ---------------
    // Extraer los datos de la asignatura del csv: Curso, código, nombre
    final filaDatos = rows[0][0]
        .toString()
        .split(';')[0]
        .trim(); // Obtengo los datos de la asinatura
    final datosAsignatura = filaDatos.split('-').map((e) => e.trim()).toList();

    // Validar formato mínimo de datos de asignatura
    if (datosAsignatura.length < 3) {
      throw 'Revise el formato de datos de asignatura: "Curso - Código - Nombre"';
    }

    final curso = datosAsignatura[0];
    final codigoAsignatura = datosAsignatura[1];
    final nombreAsignatura = datosAsignatura[2];

    if (curso.isEmpty || codigoAsignatura.isEmpty || nombreAsignatura.isEmpty) {
      throw 'Los datos de la asignatura no pueden estar vacíos.';
    }
    if (curso.length != 4 || int.tryParse(curso) == null) {
      throw 'El año lectivo debe tener 4 dígitos numéricos.';
    }
    if (codigoAsignatura.length != 8 || int.tryParse(codigoAsignatura) == null) {
      throw 'El código de asignatura debe tener 8 dígitos numéricos.';
    }

    idAsignatura = '${curso}_$codigoAsignatura';

    // Preparsear las filas de alumnos para obtener la lista de futuros usuarios
    final List<List<String>> filasAlumnos = [];
    final List<String> usuariosDesdeCSV = [];
    for (int i = 2; i < rows.length; i++) {
      final rowsAux = rows[i].toString();
      List<String> fila = rows[i]
          .toString()
          .split(',')
          .map((e) => e.trim())
          .toList();
      if (fila.length == 1) {
        fila = rowsAux
            .toString()
            .split(';')
            .map((e) => e.trim())
            .toList();
      }
      fila = fila.sublist(1, fila.length);
      filasAlumnos.add(fila);

      try {
        final correoRaw = fila[4];
        final correo = correoRaw.isNotEmpty && correoRaw.length > 1
            ? correoRaw.substring(0, correoRaw.length - 1)
            : correoRaw;
        final usuario = correo.split('@')[0];
        usuariosDesdeCSV.add(usuario);
      } catch (_) {
        // ignore; se validará al procesar cada alumno
      }
    }

    // Si la asignatura ya existe, preguntar acción al usuario
    if (await asignaturaRegistrada(idAsignatura)) {
      if (!context.mounted) return;
      final opcion = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Asignatura ya existente'),
            content: Text(
              'La asignatura $curso - $nombreAsignatura ya está registrada. ¿Qué desea hacer?',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  side: const BorderSide(color: Colors.green, width: 1),
                ),
                onPressed: () => Navigator.of(ctx).pop('cancelar'),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  side: const BorderSide(color: Colors.orange, width: 1),
                ),
                onPressed: () => Navigator.of(ctx).pop('sobrescribir'),
                child: const Text('Sobrescribir (añadir alumnos)'),
              ),
            ],
          );
        },
      );

      if (opcion == null || opcion == 'cancelar') {
        if (cargando && context.mounted) {
          finCarga(context);
          cargando = false;
        }
        return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
      }

      // Si el usuario eligió 'sobrescribir' ahora interpretamos esa opción como
      // "mantener la asignatura y añadir los alumnos del CSV" (funcionalidad antigua de 'añadir')
      if (opcion == 'sobrescribir') {
        // Actualizar metadatos de la asignatura (por si han cambiado en el CSV),
        // pero no eliminar a los alumnos actuales: los nuevos se añadirán más abajo.
        await FirebaseFirestore.instance.collection('asignaturas').doc(idAsignatura).set({
          'Curso': curso,
          'Codigo': codigoAsignatura,
          'Nombre': nombreAsignatura,
        }, SetOptions(merge: true));
      }
    } else {
      // Si no existe, crearla usando la función existente
      idAsignatura = await procesarAsignatura(datosAsignatura);
    }

    // --------------- Registrar al profesor en la asignatura ---------------
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final usuarioProfesor = user.email!.split('@')[0];
      try {
        await registrarProfesorAsignatura(usuarioProfesor, idAsignatura);
      } catch (e) {
        // Si ya está registrado, no hacer nada
        if (!e.toString().contains('ya está registrado')) {
          // Si es otro error, re-lanzarlo
          rethrow;
        }
      }
    }

    // --------------- Procesamiento de alumnos ---------------
    // Procesar las filas parseadas previamente
    for (int idx = 0; idx < filasAlumnos.length; idx++) {
      final i = idx + 2; // índice original en CSV (para mensajes)
      final fila = filasAlumnos[idx];
      try {
        String usuario = await procesarAlumno(fila, idAsignatura, numFila: i);
        nuevosAlumnosAsignatura.add(usuario);
      } catch (e) {
        throw '[FILA ${i + 1}] - $e';
      }
    }
    mostrarMensaje(
      scaffoldMessenger,
      'Se ha realizado la importación del fichero $nombreFichero correctamente',
      Colors.green,
    );

    // --------------- Procesamiento de errores ---------------
  } catch (e) {
    mostrarMensaje(scaffoldMessenger, 'Error al importar el fichero CSV: $e', Colors.red);
    try {
      if (context.mounted) {
        rollback(context, nuevosAlumnosAsignatura, idAsignatura);
      }
    } catch (e) {
      mostrarMensaje(
        scaffoldMessenger,
        'Error al deshacer los cambios en la BDD: $e',
        Colors.red,
      );
    }
  }
  if (cargando && context.mounted) {
    finCarga(context);
    cargando = false;
  }
}

// Función para exportar las notas de los alumnos de una asignatura a CSV
// Las notas se calculan usando una distribución normal basada en las puntuaciones
Future<void> exportarCSVNotas(BuildContext context, String idAsignatura) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  try {
    // Mostrar diálogo de selección de formato (Excel / Google Sheets)
    final formato = await _mostrarDialogoFormato(context);

    if (formato == null) {
      return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
    }

    if (!context.mounted) return;
    inicioCarga(context);

    // Obtener los datos de la asignatura
    final asignaturaDoc = await FirebaseFirestore.instance
        .collection('asignaturas')
        .doc(idAsignatura)
        .get();

    if (!asignaturaDoc.exists) {
      throw 'La asignatura no existe';
    }

    final asignaturaData = asignaturaDoc.data() ?? {};
    final alumnosLista =
        (asignaturaData['Alumnos'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (alumnosLista.isEmpty) {
      if (context.mounted) finCarga(context);
      return mostrarMensaje(
        scaffoldMessenger,
        'No hay alumnos registrados en esta asignatura',
        Colors.orange,
      );
    }

    // Obtener las puntuaciones de todos los alumnos
    final Map<String, int> puntuacionesAlumnos = {};

    // Cargar datos de alumnos en lotes de 10
    for (int i = 0; i < alumnosLista.length; i += 10) {
      final end = (i + 10 < alumnosLista.length) ? i + 10 : alumnosLista.length;
      final chunk = alumnosLista.sublist(i, end);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (var doc in querySnapshot.docs) {
        final usuario = doc.id;
        final userData = doc.data();
        final puntuaciones = userData['Puntuacion'] as Map<String, dynamic>?;
        final puntuacion = (puntuaciones?[idAsignatura] ?? 0) as int;
        puntuacionesAlumnos[usuario] = puntuacion;
      }
    }

    // Obtener puntuación máxima
    final puntuaciones = puntuacionesAlumnos.values.toList();

    if (puntuaciones.isEmpty) {
      if (context.mounted) finCarga(context);
      return mostrarMensaje(
        scaffoldMessenger,
        'No hay datos de puntuación disponibles',
        Colors.orange,
      );
    }

    final puntuacionMaxima = puntuaciones.reduce((a, b) => a > b ? a : b);

    // Crear el CSV
    List<List<dynamic>> csvData = [
      ['Usuario', 'Puntuación', 'Nota (0-10)'], // Cabecera
    ];

    // Calcular notas usando escala lineal normalizada
    // Puntuación máxima -> 10, Puntuación 0 -> 0
    for (var entry in puntuacionesAlumnos.entries) {
      final usuario = entry.key;
      final puntuacion = entry.value;

      double nota;
      if (puntuacionMaxima == 0) {
        // Si nadie tiene puntos, todos tienen 0
        nota = 0.0;
      } else {
        // Escala lineal: nota = (puntuacion / puntuacionMaxima) * 10
        nota = (sqrt(puntuacion) / sqrt(puntuacionMaxima)) * 10.0;

        // Asegurar que está entre 0 y 10
        nota = nota.clamp(0.0, 10.0);
      }

      csvData.add([
        usuario,
        puntuacion,
        nota.toStringAsFixed(2), // Redondear a 2 decimales
      ]);
    }

    // Ordenar por nota descendente
    csvData.sublist(1).sort((a, b) {
      final notaA = double.parse(a[2].toString());
      final notaB = double.parse(b[2].toString());
      return notaB.compareTo(notaA);
    });

    // Determinar el separador según el formato seleccionado
    final separador = formato == 'excel' ? ';' : ',';

    // Convertir a CSV con el separador apropiado
    String csv = ListToCsvConverter(fieldDelimiter: separador).convert(csvData);

    // Descargar el archivo usando la implementación específica de la plataforma
    final nombreArchivo =
        'notas_${idAsignatura}_${DateTime.now().millisecondsSinceEpoch}.csv';

    if (context.mounted) {
      await platform.descargarCSV(context, csv, nombreArchivo);
    }

    if (context.mounted) finCarga(context);
  } catch (e) {
    if (context.mounted) finCarga(context);
    mostrarMensaje(scaffoldMessenger, 'Error al exportar el CSV: $e', Colors.red);
  }
}

// Función para importar notas desde CSV y asignar insignias automáticamente
// Formato primera fila: 'Tipo Actividad - Nombre Actividad' (ej: 'Test platea - Vectores')
// Formato resto: correo, nota (0-10)
// Insignias: Bronce (4-6), Plata (6-8), Oro (8-10)
Future<void> importarCSVNotas(BuildContext context, String idAsignatura) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  bool cargando = false;
  List<Map<String, dynamic>> alumnosActualizados =
      []; // Lista para rollback si es necesario
  List<String> insigniasCreadas =
      []; // Lista de IDs de insignias creadas para rollback

  try {
    // --------------- Selección del fichero CSV ---------------
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      withData: true,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.first.bytes == null) {
      return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
    }

    String nombreFichero = result.files.first.name;

    if (!context.mounted) return;

    final confirmado = await mostrarDialogo(
      context,
      '¿Está seguro de que desea importar las notas desde el fichero $nombreFichero?',
    );

    if (!confirmado) {
      return mostrarMensaje(scaffoldMessenger, 'Operación cancelada', Colors.green);
    }

    if (!context.mounted) return;
    inicioCarga(context);
    cargando = true;

    // --------------- Procesamiento del fichero CSV ---------------
    final csvString = utf8.decode(result.files.first.bytes!);
    final rows = const CsvToListConverter().convert(csvString);

    if (rows.isEmpty || rows.length < 2) {
      throw 'El fichero CSV está vacío o no tiene datos suficientes (debe tener al menos 2 filas)';
    }

    // Verificar que la asignatura existe
    if (!await asignaturaRegistrada(idAsignatura)) {
      throw 'La asignatura $idAsignatura no existe';
    }

    // --------------- Procesar primera fila: información de la actividad ---------------
    final primeraFilaString = rows[0].toString();
    List<String> primeraFila;

    if (primeraFilaString.contains(';')) {
      primeraFila = primeraFilaString
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(';')
          .map((e) => e.trim())
          .toList();
    } else {
      primeraFila = rows[0].map((e) => e.toString().trim()).toList();
    }

    if (primeraFila.isEmpty || primeraFila[0].isEmpty) {
      throw 'La primera fila debe contener la información de la actividad (Tipo Actividad - Nombre Actividad)';
    }

    // Extraer tipo y nombre de actividad
    final actividadInfo = primeraFila[0]
        .split('-')
        .map((e) => e.trim())
        .toList();
    if (actividadInfo.length < 2) {
      throw 'Formato incorrecto en primera fila. (Tipo Actividad - Nombre Actividad)';
    }

    final tipoActividad = actividadInfo[0].trim();
    final nombreActividad = actividadInfo[1].trim();

    // Extraer curso y código de la asignatura del idAsignatura (formato: curso_codigo)
    final partesAsignatura = idAsignatura.split('_');
    if (partesAsignatura.length < 2) {
      throw 'Formato de idAsignatura inválido';
    }
    final cursoAsignatura = partesAsignatura[0];
    final codigoAsignatura = partesAsignatura[1];

    List<String> errores = [];

    // PRIMERA FASE: Validar el CSV antes de hacer cambios
    List<Map<String, dynamic>> operacionesPendientes = [];

    // --------------- VALIDACIÓN de cada línea del CSV (desde fila 1, la 0 es la cabecera) ---------------
    for (int i = 1; i < rows.length; i++) {
      try {
        // Detectar el delimitador (Excel usa ';', Google Sheets usa ',')
        final rowString = rows[i].toString();
        List<String> fila;

        if (rowString.contains(';')) {
          // Formato Excel
          fila = rowString
              .replaceAll('[', '')
              .replaceAll(']', '')
              .split(';')
              .map((e) => e.trim())
              .toList();
        } else {
          // Formato Google Sheets
          fila = rows[i].map((e) => e.toString().trim()).toList();
        }

        // Validar que tenga al menos 2 columnas
        if (fila.length < 2) {
          throw 'Formato incorrecto (email - nota [0,10])';
        }

        // Extraer correo y nota
        final correo = fila[0].trim();
        final notaString = fila[1].trim();

        // Validar nota
        final nota = double.tryParse(notaString);
        if (nota == null || nota < 0 || nota > 10) {
          throw 'Nota inválida ($notaString). Debe estar entre 0 y 10';
        }

        // Obtener el usuario del correo
        final usuario = correo.split('@')[0];

        // Verificar que el alumno esté registrado en la asignatura
        if (!await alumnoEnAsignatura(usuario, idAsignatura)) {
          throw 'El alumno $usuario no está registrado en la asignatura';
        }

        // Determinar qué tipo de insignia asignar según la nota
        String? tipoInsigniaStr;
        int puntuacion = 0;

        if (nota >= 8.0 && nota <= 10.0) {
          tipoInsigniaStr = 'oro';
          puntuacion =
              tipoInsignia.firstWhere((t) => t['id'] == 'oro')['puntuacion']
                  as int;
        } else if (nota >= 6.0 && nota < 8.0) {
          tipoInsigniaStr = 'plata';
          puntuacion =
              tipoInsignia.firstWhere((t) => t['id'] == 'plata')['puntuacion']
                  as int;
        } else if (nota >= 4.0 && nota < 6.0) {
          tipoInsigniaStr = 'bronce';
          puntuacion =
              tipoInsignia.firstWhere((t) => t['id'] == 'bronce')['puntuacion']
                  as int;
        }

        // Si la nota es inferior a 4, no se asigna insignia
        if (tipoInsigniaStr == null) {
          continue;
        }

        // Crear ID de insignia único con formato igual a pantallaQR:
        // cursoAsignatura-codigoAsignatura_tipoActividad-nombreActividad_tipoInsignia_uuid
        // Ejemplo: 2425-12345678_Test-platea-Vectores_oro_abc123
        final uuid = const Uuid().v4();
        final tipoActividadNormalizado = tipoActividad.replaceAll(' ', '-');
        final nombreActividadNormalizado = nombreActividad.replaceAll(' ', '-');
        final idInsignia =
            '$cursoAsignatura-${codigoAsignatura}_$tipoActividadNormalizado-${nombreActividadNormalizado}_${tipoInsigniaStr}_$uuid';

        // Verificar si el alumno ya tiene una insignia con el mismo tipo y nombre de actividad
        final usuarioDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(usuario)
            .get();

        final usuarioData = usuarioDoc.data() ?? {};
        final insigniasUsuario =
            usuarioData['Insignias'] as Map<String, dynamic>? ?? {};
        final insigniasAsignatura =
            insigniasUsuario[idAsignatura] as List<dynamic>? ?? [];

        // Verificar si alguna insignia existente coincide con el tipo y nombre de actividad
        for (var insigniaExistente in insigniasAsignatura) {
          final insigniaStr = insigniaExistente.toString();
          // Formato: cursoAsignatura-codigoAsignatura_tipoActividad-nombreActividad_tipoInsignia_uuid
          // Comparamos solo la parte del tipo y nombre de actividad
          final patronBusqueda =
              '$tipoActividadNormalizado-${nombreActividadNormalizado}_$tipoInsigniaStr';

          if (insigniaStr.contains(patronBusqueda)) {
            throw 'El alumno $usuario ya tiene una insignia de tipo $tipoInsigniaStr para la actividad "$tipoActividad - $nombreActividad". Compruebe la actividad del fichero a importar.';
          }
        }

        // Guardar operación pendiente (validación exitosa)
        operacionesPendientes.add({
          'usuario': usuario,
          'idInsignia': idInsignia,
          'puntuacion': puntuacion,
          'nota': nota,
          'tipo': tipoInsigniaStr,
          'tipoActividad': tipoActividad,
          'nombreActividad': nombreActividad,
        });
      } catch (e) {
        throw 'Fila ${i + 1}: $e';
      }
    }

    // SEGUNDA FASE: Aplicar todas las operaciones solo si todas las validaciones pasaron
    if (operacionesPendientes.isEmpty) {
      if (context.mounted) {
        finCarga(context);
      }
      cargando = false;

      String mensaje = 'No se realizaron cambios:\n';
      if (errores.isNotEmpty && errores.length <= 5) {
        mensaje += '\nMotivos:\n${errores.join('\n')}';
      } else if (errores.length > 5) {
        mensaje +=
            '\nSe encontraron ${errores.length} problemas. Mostrando los primeros 5:\n';
        mensaje += errores.take(5).join('\n');
      }

      return mostrarMensaje(scaffoldMessenger, mensaje, Colors.orange);
    }

    // --------------- APLICAR cambios en Firestore ---------------
    for (var operacion in operacionesPendientes) {
      try {
        // Crear la insignia en la asignatura
        await FirebaseFirestore.instance
            .collection('asignaturas')
            .doc(idAsignatura)
            .update({
              'Insignias.${operacion['idInsignia']}': {
                'Tipo': operacion['tipo'],
                'Puntuacion': operacion['puntuacion'],
                'Actividad': operacion['tipoActividad'],
                'Nombre': operacion['nombreActividad'],
              },
            });

        insigniasCreadas.add(operacion['idInsignia']);

        // Asignar la insignia al alumno
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(operacion['usuario'])
            .update({
              'Insignias.$idAsignatura': FieldValue.arrayUnion([
                operacion['idInsignia'],
              ]),
              'Puntuacion.$idAsignatura': FieldValue.increment(
                operacion['puntuacion'],
              ),
            });

        alumnosActualizados.add(operacion);
      } catch (e) {
        throw 'Error al asignar insignia al alumno ${operacion['usuario']}: $e';
      }
    }

    // --------------- Mostrar resultados ---------------
    if (context.mounted) {
      finCarga(context);
    }
    cargando = false;

    String mensaje =
        'Se han asignado las insignias correctamente a los alumnos.';

    if (errores.isNotEmpty && errores.length <= 5) {
      mensaje += '\nNotas:\n${errores.join('\n')}';
    } else if (errores.length > 5) {
      mensaje +=
          '\nSe encontraron ${errores.length} notas. Mostrando las primeras 5:\n';
      mensaje += errores.take(5).join('\n');
    }

    mostrarMensaje(scaffoldMessenger, mensaje, Colors.green);
  } catch (e) {
    // --------------- ROLLBACK: Deshacer todos los cambios ---------------
    if (alumnosActualizados.isNotEmpty || insigniasCreadas.isNotEmpty) {
      try {
        // Revertir asignaciones de insignias a alumnos
        for (var alumno in alumnosActualizados) {
          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(alumno['usuario'])
              .update({
                'Insignias.$idAsignatura': FieldValue.arrayRemove([
                  alumno['idInsignia'],
                ]),
                'Puntuacion.$idAsignatura': FieldValue.increment(
                  -alumno['puntuacion'],
                ),
              });
        }

        // Eliminar insignias creadas de la asignatura
        for (var idInsignia in insigniasCreadas) {
          await FirebaseFirestore.instance
              .collection('asignaturas')
              .doc(idAsignatura)
              .update({'Insignias.$idInsignia': FieldValue.delete()});
        }
      } catch (rollbackError) {
        if (cargando && context.mounted) {
          finCarga(context);
        }
        return mostrarMensaje(
          scaffoldMessenger,
          'Error crítico: No se pudo revertir los cambios. Por favor, contacte al administrador.\nError original: $e\nError de rollback: $rollbackError',
          Colors.red,
        );
      }
    }

    if (cargando && context.mounted) {
      finCarga(context);
    }
    mostrarMensaje(
      scaffoldMessenger,
      'Error en la importación. No se guardó ningún cambio:\n$e',
      Colors.red,
    );
  }
}

// Función auxiliar para mostrar el diálogo de selección de formato
Future<String?> _mostrarDialogoFormato(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          'Seleccionar formato de archivo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccione la aplicación que utilizará para abrir el archivo',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('Microsoft Excel'),
              tileColor: Colors.green.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () => Navigator.pop(context, 'excel'),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blue),
              title: const Text('Hojas de cálculo de Google'),
              tileColor: Colors.blue.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () => Navigator.pop(context, 'google'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}
