import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/pantallas/formRegistroProfesor.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  // CONTROLADORES: Sirven para acceder a lo que se escribe en los diferentes campos
  final TextEditingController _email =
      TextEditingController(); // Campo que guardará el correo
  final TextEditingController _password =
      TextEditingController(); // Campo que guardará la contraseña

  // VARIABLES DE ESTADO: Permiten actualizar la interfaz en función de su valor
  bool _ocultarPassword = true;
  bool _cargando = false;

  // FORM KEY: Analiza el contenido de los campos para verificar que tienen un formato válido
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ICONO
                  Icon(
                    Icons.lock_person,
                    size: 100,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),

                  // TÍTULO
                  Text(
                    'Iniciar sesión',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // SUBTÍTULO
                  Text(
                    'Introduce tus credenciales para continuar',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  /* CAMPOS RELLENABLES */
                  // EMAIL
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Introduce tu email (UJA)', // Título del campo
                      hintText: 'SIDUJA@red.ujaen.es', // Contenido por defecto
                      prefixIcon: const Icon(Icons.email_outlined), // Icono
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      // Comprobación de que es un correo válido (no nulo y perteneciente a la universidad)
                      if (value == null || !emailValido(value)) {
                        // TODO Quitar email de prueba
                        return 'Por favor, introduce tu email de la UJA';
                      }
                      return null; // Se devuelve nulo si es válido
                    },
                  ),
                  const SizedBox(height: 16),

                  // CONTRASEÑA
                  TextFormField(
                    controller: _password,
                    obscureText:
                        _ocultarPassword, // Permite ocultar/mostrar la contraseña introducida

                    decoration: InputDecoration(
                      labelText: 'Contraseña', // Título del campo
                      hintText: '******', // Contenido por defecto
                      prefixIcon: const Icon(Icons.lock_outlined), // Icono

                      suffixIcon: IconButton(
                        // Botón para ocultar/mostrar contraseña
                        onPressed: () {
                          // Si se hace click
                          setState(() {
                            _ocultarPassword =
                                !_ocultarPassword; // Se invierte el estado
                          });
                        },
                        icon: Icon(
                          // Icono con el que interactuar
                          _ocultarPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      // Comprobación de que la contraseña no es nula
                      if (value == null || value.isEmpty) {
                        return 'Por favor, introduce tu contraseña';
                      }
                      if (textoInvalido(value)) {
                        return 'Por favor, inserta texto plano';
                      }
                      return null; // Se devuelve nulo si es válido
                    },
                  ),
                  const SizedBox(height: 8),

                  /* BOTONES INFERIORES */
                  // OLVIDO DE CONTRASEÑA
                  Align(
                    alignment: AlignmentGeometry.centerRight,
                    child: TextButton(
                      onPressed: () => _mostrarDialogoRecuperacion(context),
                      child: const Text('Recuperar contraseña'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // CONFIRMAR LOGIN
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      // Botón de inicio de sesión
                      onPressed: _cargando ? null : signIn,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      // Mostrar spinner o texto según el estado
                      child: _cargando
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Iniciar Sesión',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // REGISTRARSE
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '¿Eres profesor y no tienes cuenta? ',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const FormularioRegistroProfesor(),
                          ),
                        ),
                        child: const Text(
                          'Regístrate',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Función de inicio de sesión (comprueba los datos introducidos con los de la base de datos)
  Future<void> signIn() async {
    setState(() {
      _cargando = true;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      String email = _email.text;
      String password = _password.text;
      String usuario = email.split('@')[0];

      // Primero, se comprueba si el usuario existe en la BDD y su rol es válido
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario)
          .get();

      if (!doc.exists) {
        // Si el usuario no existe en la BDD, cerrar sesión
        await FirebaseAuth.instance.signOut();
        throw 'El usuario $usuario no está registrado en el sistema';
      }

      final rol = doc.data()?['Rol'] as String?;

      if (rol == null || rol == 'ELIMINADO') {
        // Si el usuario está eliminado, cerrar sesión inmediatamente
        await FirebaseAuth.instance.signOut();
        throw 'El usuario $usuario ha sido eliminado';
      }

      // Si el usuario existe y su rol es válido, se intenta iniciar sesión
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          // Se intenta iniciar sesión con los datos introducidos
          email: email,
          password: password,
        );
      } catch (e) {
        throw 'Email o contraseña incorrectos';
      }
    } catch (e) {
      // Fallo al iniciar sesión
      mostrarMensaje(scaffoldMessenger, 'Error al iniciar sesión. $e', Colors.red);
    }
    setState(() {
      _cargando = false;
    });
  }

  // Función que permite evitar que el texto contenga etiquetas HTML
  bool textoInvalido(String texto) {
    final regex = RegExp(r'<[^>]*>');
    return regex.hasMatch(texto);
  }

  void _mostrarDialogoRecuperacion(BuildContext context) {
    final TextEditingController emailRecuperacionController =
        TextEditingController();
    final GlobalKey<FormState> formKeyRecuperacion = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Recuperar contraseña'),
          content: Form(
            key: formKeyRecuperacion,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Introduce tu email para recibir un enlace de recuperación:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailRecuperacionController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'SIDUJA@red.ujaen.es',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || !emailValido(value)) {
                      return 'Por favor, introduce tu email de la UJA';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKeyRecuperacion.currentState!.validate()) {
                  return;
                }

                final email = emailRecuperacionController.text.trim();
                Navigator.pop(context);
                await _enviarEmailRecuperacion(email);
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enviarEmailRecuperacion(String email) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      mostrarMensaje(
        scaffoldMessenger,
        'Se ha enviado un email de recuperación al correo $email. Revisa tu bandeja de entrada y spam.',
        Colors.green,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String mensaje;
      switch (e.code) {
        case 'user-not-found':
          mensaje = 'No existe ninguna cuenta con ese email';
          break;
        case 'invalid-email':
          mensaje = 'El formato del email no es válido';
          break;
        default:
          mensaje = 'Error al enviar el email de recuperación: ${e.message}';
      }
      mostrarMensaje(scaffoldMessenger, mensaje, Colors.red);
    } catch (e) {
      if (!mounted) return;
      mostrarMensaje(scaffoldMessenger, 'Error inesperado: $e', Colors.red);
    }
  }
}

bool emailValido(String email) {
  // todo quitar email de prueba
  final regex = RegExp(r'^[\w.-]+@[\w.-]+\.\w+$');
  if (email.isEmpty ||
      (!email.contains('@red.ujaen.es') &&
          !email.contains('@ujaen.es') &&
          !email.contains('fenmc03@gmail.com'))) {
    return false;
  }
  return regex.hasMatch(email);
}
