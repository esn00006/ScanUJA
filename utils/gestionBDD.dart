import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/constantes.dart';

// Comprobación de datos en la BDD
Future<bool> asignaturaRegistrada(String idAsignatura) async {
  final doc = await FirebaseFirestore.instance
      .collection('asignaturas')
      .doc(idAsignatura)
      .get();
  return doc.exists;
}

Future<bool> alumnoEnAsignatura(String usuario, String idAsignatura) async {
  final doc = await FirebaseFirestore.instance
      .collection('asignaturas')
      .doc(idAsignatura)
      .get();
  if (!doc.exists) return false;

  final alumnos = List<String>.from(doc.data()?['Alumnos'] ?? []);
  return alumnos.contains(usuario);
}

Future<bool> usuarioRegistrado(String usuario) async {
  final doc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(usuario)
      .get();
  return doc.exists && doc.data()?['Rol'] != 'ELIMINADO';
}

Future<bool> verificarCorreo(String correo) async {
  // Para registrar la autenticación automática de un usuario, debe estar registrado en la BDD, aunque se puede hacer manual desde la consola de Firebase
  final usuario = correo.split('@')[0];
  final doc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(usuario)
      .get(); // Se busca al usuario en función de su SIDUJA
  return doc.exists &&
      doc.data()?['Email'] ==
          correo; // Verificamos que el usuario está en la BDD y que el correo coincide con el registrado
}

Future<String?> obtenerRol(String usuario) async {
  // Obtener el rol del usuario actual [PROFESOR, ALUMNO, ELIMINADO]
  final doc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(usuario)
      .get(); // Se busca al usuario en función de su SIDUJA
  if (!doc.exists) return null;

  return doc.data()?['Rol'];
}

// Procesamiento de datos
Future<String> procesarAsignatura(List<String> datosAsignatura) async {
  // Verifica si hay suficientes datos
  if (datosAsignatura.length < 3) {
    throw 'Revise el formato de datos de asignatura: "Curso - Código - Nombre" (Todo en la misma fila y columna).';
  }

  // Se obtienen los datos de la fila
  final curso = datosAsignatura[0];
  final codigoAsignatura = datosAsignatura[1];
  final nombreAsignatura = datosAsignatura[2];

  // Se verifica su formato
  if (curso.isEmpty || codigoAsignatura.isEmpty || nombreAsignatura.isEmpty) {
    throw 'Los datos de la asignatura no pueden estar vacíos.';
  }

  if (curso.length != 4 || int.tryParse(curso) == null) {
    throw 'El año lectivo debe tener 4 dígitos numéricos.';
  }

  if (codigoAsignatura.length != 8 || int.tryParse(codigoAsignatura) == null) {
    throw 'El código de asignatura debe tener 8 dígitos numéricos.';
  }

  // Si los datos son correctos, se registra la asignatura
  final idAsignatura = '${curso}_$codigoAsignatura';

  await FirebaseFirestore.instance
      .collection('asignaturas')
      .doc(idAsignatura)
      .set({
        'Curso': curso,
        'Codigo': codigoAsignatura,
        'Nombre': nombreAsignatura,
      });

  return idAsignatura; // Devuelve el id de la asignatura para poder añadir alumnos en caso necesario
} // Procesa y registra una asignatura desde una lista de datos

Future<String> procesarAlumno(
  List<String> datosAlumno,
  String idAsignatura, {
  int numFila = -1,
}) async {
  // El numFila se inicializa a -1 porque no siempre será un valor que obtengamos
  String infoFila = '';
  if (numFila != -1) {
    // Si se obtiene número de fila (importación desde CSV), añadimos su información en una cadena que concatenaremos en los mensajes a mostrar
    infoFila = '(Fila $numFila) ';
  }
  // Verifica si hay suficientes datos
  if (datosAlumno.length != 5) {
    throw '${infoFila}Revise el formato de datos de alumno: "DNI - Primer apellido - Segundo apellido - Nombre - Correo".';
  }

  if (!await asignaturaRegistrada(idAsignatura)) {
    throw '${infoFila}La asignatura $idAsignatura no está registrada en la BDD.';
  }

  // Se obtienen los datos de la fila
  String correo = datosAlumno[4].substring(0, datosAlumno[4].length - 1);
  String usuario = correo.split('@')[0];

  if (await usuarioRegistrado(usuario)) {
    final rol = await obtenerRol(usuario);
    if (rol == 'ELIMINADOO') {
      await FirebaseFirestore.instance.collection('usuarios').doc(usuario).set({
        'Rol': 'ALUMNO',
      }, SetOptions(merge: true));
    }
  } else {
    String dni = datosAlumno[0].split('-')[1].trim();
    String apellido1 = datosAlumno[1];
    String apellido2 = datosAlumno[2];
    String nombre = datosAlumno[3];

    // Se verifica su formato
    if (dni.isEmpty) {
      throw '${infoFila}El DNI no puede estar vacío: Revise el formato del fichero "NIF - 11111111A".';
    }
    if (apellido1.isEmpty) {
      throw '${infoFila}El primer apellido no puede estar vacío.';
    }
    if (nombre.isEmpty) {
      throw '${infoFila}El nombre no puede estar vacío.';
    }
    if (correo.isEmpty) {
      throw '${infoFila}El correo no puede estar vacío.';
    }
    if ((!correo.contains('@red.ujaen.es') && !correo.contains('@ujaen.es')) &&
        correo != 'fenmc03@gmail.com') {
      throw '${infoFila}El correo debe ser institucional.';
    }

    // Registrar alumno en Firestore
    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).set({
      'Dni': dni,
      'Primer apellido': apellido1,
      'Segundo apellido': apellido2,
      'Nombre': nombre,
      'Email': correo,
      'Usuario': usuario,
      'Rol': 'ALUMNO',
    }, SetOptions(merge: true));

    try {
      await registrarUsuarioAuth(
        correo,
        dni,
      ); // Registrar al alumno en la autenticación
    } catch (e) {
      throw 'Se ha producido un error en el registro del usuario $usuario, por favor, verifique los datos del fichero: $e';
    }
  }

  await registrarAlumnoAsignatura(
    usuario,
    idAsignatura,
  ); // Registrar al alumno en la asignatura y viceversa

  return usuario; // Devuelvo el id del alumno
} // Procesa y registra a un alumno en una asignatura desde una lista de datos

Future<void> registrarUsuarioAuth(String correo, String password) async {
  if (!await verificarCorreo(correo)) {
    throw Exception(
      'El correo del alumno debe ser institucional o estar autorizado',
    );
  }

  // Crear instancia secundaria de FirebaseApp
  // Hay que hacerlo así porque FirebaseAuth no permite crear varios usuarios con la misma sesión activa
  // La única forma de hacerlo de otra manera es utilizando Cloud Functions, lo cual requiere un plan de pago en Firebase
  final FirebaseApp secondaryApp = await Firebase.initializeApp(
    name: 'SecondaryApp',
    options: Firebase.app().options,
  );

  String usuario = correo.split('@')[0];

  final docUsuario = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(usuario)
      .get();

  if (docUsuario.exists && docUsuario.data()?['uid'] != null) {
    return; // El usuario ya está registrado en la BDD
  }

  try {
    // Usar FirebaseAuth con la instancia secundaria
    final FirebaseAuth secondaryAuth = FirebaseAuth.instanceFor(
      app: secondaryApp,
    );

    final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
      email: correo,
      password: password,
    );

    final uid = userCredential.user!.uid;

    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).set({
      'uid': uid,
    }, SetOptions(merge: true));
  } finally {
    await secondaryApp
        .delete(); // Eliminar la instancia secundaria para liberar recursos
  }
} // Registra a un usuario en FirebaseAuth

Future<void> registrarAlumnoAsignatura(
  String usuario,
  String idAsignatura,
) async {
  if (!await usuarioRegistrado(usuario)) {
    throw 'El usuario $usuario no está registrado en la BDD.';
  }
  if (!await asignaturaRegistrada(idAsignatura)) {
    throw 'La asignatura $idAsignatura no está registrada en la BDD.';
  }

  await FirebaseFirestore.instance.collection('usuarios').doc(usuario).update({
    'Asignaturas': FieldValue.arrayUnion([
      idAsignatura,
    ]), // Se añade la asignatura al alumno
    'Insignias.$idAsignatura': [],
    'Puntuacion.$idAsignatura': 0,
  });

  await FirebaseFirestore.instance
      .collection('asignaturas')
      .doc(idAsignatura)
      .update({
        'Alumnos': FieldValue.arrayUnion([
          usuario,
        ]), // Se añade el alumno a la asignatura
      });
}

Future<void> registrarInsigniaAlumno(
  ScaffoldMessengerState scaffoldMessenger,
  String usuario,
  String idInsignia,
) async {
  try {
    final partes = idInsignia.split('_');

    if (partes.length != 4) {
      throw 'Código QR inválido';
    }

    String idAsignatura = partes[0].replaceAll('-', '_');
    String actividad = partes[1].replaceAll('-', '_');
    String tipoInsignia = partes[2];
    String uuidInsignia = partes[3];

    if (idAsignatura.isEmpty ||
        tipoInsignia.isEmpty ||
        actividad.isEmpty ||
        uuidInsignia.isEmpty) {
      throw 'Los datos de la insignia son incorrectos: "idAsignatura_actividad_tipoInsignia_uuid';
    }

    int puntuacion = obtenerPuntosPorInsignia(tipoInsignia);
    // Actualizar la insignia y la puntuación en una sola operación
    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).update(
      {
        'Insignias.$idAsignatura': FieldValue.arrayUnion([idInsignia]),
        'Puntuacion.$idAsignatura': FieldValue.increment(puntuacion),
      },
    );
    mostrarMensaje(scaffoldMessenger, 'Insignia registrada', Colors.green);
  } catch (e) {
    mostrarMensaje(scaffoldMessenger, 'Error al registrar la insignia: $e', Colors.red);
  }
}

Future<void> registrarProfesorAsignatura(
  String usuario,
  String idAsignatura,
) async {
  if (!await usuarioRegistrado(usuario)) {
    throw 'El profesor $usuario no está registrado en la BDD.';
  }
  if (!await asignaturaRegistrada(idAsignatura)) {
    throw 'La asignatura $idAsignatura no está registrada en la BDD.';
  }

  await FirebaseFirestore.instance.collection('usuarios').doc(usuario).set({
    'Asignaturas': FieldValue.arrayUnion([
      idAsignatura,
    ]), // Se añade la asignatura al profesor
  }, SetOptions(merge: true));

  await FirebaseFirestore.instance
      .collection('asignaturas')
      .doc(idAsignatura)
      .set({
        'Profesores': FieldValue.arrayUnion([
          usuario,
        ]), // Se añade el profesor a la asignatura
      }, SetOptions(merge: true));
}

Future<void> actualizarDatosAlumno(
  BuildContext context,
  String usuario,
  List<String> nuevosDatos,
) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  try {
    if (nuevosDatos.length != 3) {
      throw 'Introduzca todos los datos: "Nombre, Primer apellido, Segundo apellido';
    }
    for (String dato in nuevosDatos) {
      if (dato.isEmpty) {
        throw 'Debe introducir el nombre y primer apellido';
      }
    }

    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).set({
      'Nombre': nuevosDatos[0].toUpperCase(),
      'Primer apellido': nuevosDatos[1].toUpperCase(),
      'Segundo apellido': nuevosDatos[2].toUpperCase(),
    }, SetOptions(merge: true));
    mostrarMensaje(scaffoldMessenger, 'Datos actualizados correctamente', Colors.green);
  } catch (e) {
    mostrarMensaje(
      scaffoldMessenger,
      'No se han podido actualizar los datos: $e',
      Colors.red,
    );
  }
}

Future<bool> eliminarAlumnoIDAsignatura(
  BuildContext context,
  String usuario,
  String idAsignatura,
) {
  List<String> partes = idAsignatura.split('_');
  if (partes.length != 2) {
    throw 'El id de asignatura $idAsignatura no tiene el formato correcto (curso_codigo).';
  }
  return eliminarAlumnoAsignatura(context, usuario, partes[0], partes[1]);
}

Future<bool> eliminarAlumnoAsignatura(
  BuildContext context,
  String usuario,
  String curso,
  String codigo,
) async {
  String idAsignatura = '${curso}_$codigo'; // Obtener id de asignatura
  try {
    if (!await usuarioRegistrado(usuario)) {
      // Comprobar que el alumno existe
      throw 'El usuario $usuario no existe.';
    }

    if (!await asignaturaRegistrada(idAsignatura)) {
      // Comprobar que la asignatura existe
      throw 'La asignatura $idAsignatura no existe.';
    }
    await FirebaseFirestore
        .instance // Eliminar al alumno de la asignatura
        .collection('asignaturas')
        .doc(idAsignatura)
        .update({
          'Alumnos': FieldValue.arrayRemove([usuario]),
        });

    await eliminarTodasInsignias(usuario, idAsignatura);

    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).update(
      {
        'Asignaturas': FieldValue.arrayRemove([idAsignatura]),
      },
    );

    final alumno = await FirebaseFirestore
        .instance // Eliminar la asignatura del alumno
        .collection('usuarios')
        .doc(usuario)
        .get();

    List<String> asignaturas = List<String>.from(
      alumno.data()?['Asignaturas'] ?? [],
    );
    if (asignaturas.isEmpty) {
      // Si el alumno no está matriculado en ninguna asignatura, se elimina de la BDD
      eliminarAlumnoBDD(usuario);
    }
    return true;
  } catch (e) {
    /*mostrarMensaje(context,
        'El usuario $usuario no se ha podido eliminar de la asignatura $idAsignatura: $e',
        Colors.red);*/
    return false;
  }
}

Future<void> eliminarAlumnoBDD(String usuario) async {
  try {
    if (!await usuarioRegistrado(usuario)) {
      // Comprobar que el alumno existe
      throw 'El usuario $usuario no existe.';
    }

    String? rolUsuario = await obtenerRol(usuario);
    if (rolUsuario != 'ALUMNO') {
      throw 'ROL: $rolUsuario';
    }

    final alumno = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(usuario)
        .get(); // Obtener datos del alumno
    final asignaturas = List<String>.from(alumno.data()?['Asignaturas'] ?? []);
    if (asignaturas.isNotEmpty) {
      // Comprobar que no está matriculado en ninguna asignatura
      throw 'El usuario $usuario está matriculado en ${asignaturas.length} asignaturas. Por favor, elimínelo de las asignaturas antes de eliminarlo de la BDD.';
    }

    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(usuario)
        .update({
          'Rol': 'ELIMINADO',
          'Asignaturas': FieldValue.delete(),
          'Insignias': FieldValue.delete(),
          'Puntuacion': FieldValue.delete(),
        });
  } catch (e) {
    throw 'El usuario $usuario no se ha podido eliminar de la BDD: $e';
  }
}

Future<void> eliminarAsignaturaBDD(
  BuildContext context,
  String idAsignatura,
) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  try {
    if (!await asignaturaRegistrada(idAsignatura)) {
      // Comprobar que la asignatura existe
      throw 'La asignatura $idAsignatura no existe.';
    }

    final firestore = FirebaseFirestore.instance;
    final asignatura = await firestore
        .collection('asignaturas')
        .doc(idAsignatura)
        .get();

    final alumnos = List<String>.from(asignatura.data()?['Alumnos'] ?? []);
    for (String usuario in alumnos) {
      // Eliminar la asignatura de todos los alumnos matriculados. Aunque ya hay una función de eliminar alumno de asignatura, lo hago aquí porque
      // solo es necesario recorrer la lista de asignaturas del alumno, mientras que la lista de alumnos en la asignatura se eliminará directamente.
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario)
          .update({
            'Asignaturas': FieldValue.arrayRemove([idAsignatura]),
          });

      final alumno = await firestore.collection('usuarios').doc(usuario).get();

      await eliminarTodasInsignias(usuario, idAsignatura);

      List<String> asignaturas = List<String>.from(
        alumno.data()?['Asignaturas'] ?? [],
      );
      if (asignaturas.isEmpty) {
        // Si al alumno no le quedan asignaturas, lo eliminamos de la BDD
        eliminarAlumnoBDD(usuario);
      }
    }

    // Eliminar la asignatura de todos los profesores asociados
    final profesores = List<String>.from(asignatura.data()?['Profesores'] ?? []);
    for (String profesor in profesores) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(profesor)
          .update({
            'Asignaturas': FieldValue.arrayRemove([idAsignatura]),
          });
    }

    await FirebaseFirestore.instance
        .collection('asignaturas')
        .doc(idAsignatura)
        .delete(); // Eliminar la asignatura

    mostrarMensaje(scaffoldMessenger, 'Asignatura eliminada', Colors.green);
  } catch (e) {
    mostrarMensaje(
      scaffoldMessenger,
      'La asignatura $idAsignatura no se ha podido eliminar de la BDD: $e',
      Colors.red,
    );
  }
}

Future<void> eliminarInsignia(
  ScaffoldMessengerState scaffoldMessenger,
  String usuario,
  String idInsignia,
) async {
  try {
    final partes = idInsignia.split('_');

    if (partes.length != 4) {
      throw 'Formato inválido';
    }
    final idAsignatura = partes[0].replaceAll('-', '_');
    final tipoInsignia = partes[2];

    int puntuacion = obtenerPuntosPorInsignia(tipoInsignia);

    await FirebaseFirestore.instance.collection('usuarios').doc(usuario).update(
      {
        'Insignias.$idAsignatura': FieldValue.arrayRemove([idInsignia]),
        'Puntuacion.$idAsignatura': FieldValue.increment(-puntuacion),
      },
    );

    mostrarMensaje(scaffoldMessenger, 'Insignia eliminada', Colors.green);
  } catch (e) {
    mostrarMensaje(scaffoldMessenger, 'Error al añadir la insignia $e', Colors.red);
  }
}

Future<void> eliminarTodasInsignias(
  String usuario,
  String idAsignatura,
) async {
  try {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(usuario)
        .update({
          'Insignias.$idAsignatura': FieldValue.delete(),
          'Puntuacion.$idAsignatura': FieldValue.delete(),
        });
  } catch (e) {
    throw 'No se han podido eliminar todas las insignias: $e';
  }
}

void rollback(
  BuildContext context,
  List<String> nuevosAlumnosAsignatura,
  String idAsignatura,
) async {
  for (String idAlumno in nuevosAlumnosAsignatura) {
    await eliminarAlumnoIDAsignatura(context, idAlumno, idAsignatura);
  }
  final firestore = FirebaseFirestore.instance;
  final asignatura = await firestore
      .collection('asignaturas')
      .doc(idAsignatura)
      .get();
  final alumnos = List<String>.from(asignatura.data()?['Alumnos'] ?? []);
  if (alumnos.isEmpty && context.mounted) {
    await eliminarAsignaturaBDD(context, idAsignatura);
  }
}

int obtenerPuntosPorInsignia(String tipoInsigniaStr) {
  try {
    final insignia = tipoInsignia.firstWhere(
      (t) => t['id'] == tipoInsigniaStr.toLowerCase(),
      orElse: () => {'puntuacion': 0},
    );
    return insignia['puntuacion'] as int;
  } catch (e) {
    return 0;
  }
}
