import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/login.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';
import 'package:sistema_gamificacion/utils/device_detector_mobile.dart'
    if (dart.library.html) 'package:sistema_gamificacion/utils/device_detector_web.dart';

class FormularioRegistroAlumno extends StatefulWidget {
  final String idAsignatura;

  const FormularioRegistroAlumno({super.key, required this.idAsignatura});

  @override
  State<FormularioRegistroAlumno> createState() =>
      _FormularioRegistroAlumnoState();
}

class _FormularioRegistroAlumnoState extends State<FormularioRegistroAlumno> {
  final _formKey = GlobalKey<FormState>();

  final dniController = TextEditingController();
  final apellido1Controller = TextEditingController();
  final apellido2Controller = TextEditingController();
  final nombreController = TextEditingController();
  final correoController = TextEditingController();

  bool _cargando = false;

  @override
  void dispose() {
    dniController.dispose();
    apellido1Controller.dispose();
    apellido2Controller.dispose();
    nombreController.dispose();
    correoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Registro de alumno',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        currentIndex: 0,
        onTap: (indice) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          navegacionGlobalNotifier.value = indice;
        },
        totalPantallas: esDispositivoMovil() ? 3 : 2,
      ),
      body: Stack(
        children: [
          Container(
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSeccionHeader(
                              icon: Icons.person,
                              titulo: 'Datos del alumno',
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: dniController,
                              label: 'DNI *',
                              icon: Icons.badge,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El DNI no puede estar vacío';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: apellido1Controller,
                              label: 'Primer apellido *',
                              icon: Icons.person_outline,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El primer apellido no puede estar vacío';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: apellido2Controller,
                              label: 'Segundo apellido',
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: nombreController,
                              label: 'Nombre *',
                              icon: Icons.person_outlined,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El nombre no puede estar vacío';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: correoController,
                              label: 'Correo electrónico *',
                              hint: 'SIDUJA@red.ujaen.es',
                              icon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El correo electrónico no puede estar vacío';
                                }
                                if (!emailValido(value)) {
                                  return 'El correo electrónico debe ser institucional';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: _cargando
                                  ? null
                                  : () async {
                                      if (_formKey.currentState!.validate()) {
                                        setState(() {
                                          _cargando = true;
                                        });

                                        // Capturar ScaffoldMessenger y Navigator antes de operaciones async
                                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                                        final navigator = Navigator.of(context);

                                        try {
                                          String idAsignatura =
                                              widget.idAsignatura;

                                          if (!await asignaturaRegistrada(
                                            idAsignatura,
                                          )) {
                                            if (mounted) {
                                              setState(() {
                                                _cargando = false;
                                              });
                                              mostrarMensaje(
                                                scaffoldMessenger,
                                                'La asignatura con ID $idAsignatura no existe. Por favor, compruebe los datos introducidos',
                                                Colors.red,
                                              );
                                            }
                                            return;
                                          }

                                          String correo = correoController.text
                                              .trim();
                                          String usuario = correo.split('@')[0];

                                          if(await obtenerRol(usuario) == 'PROFESOR'){
                                            if (mounted) {
                                              setState(() {
                                                _cargando = false;
                                              });
                                              mostrarMensaje(
                                                scaffoldMessenger,
                                                'El usuario $usuario es un profesor y no se puede registrar como alumno',
                                                Colors.red,
                                              );
                                            }
                                            return;
                                          }

                                          if (await alumnoEnAsignatura(
                                            usuario,
                                            idAsignatura,
                                          )) {
                                            if (mounted) {
                                              setState(() {
                                                _cargando = false;
                                              });
                                              mostrarMensaje(
                                                scaffoldMessenger,
                                                'El alumno $usuario ya está registrado en la asignatura $idAsignatura',
                                                Colors.orange,
                                              );
                                            }
                                            return;
                                          }

                                          String dni = dniController.text
                                              .trim();
                                          String apellido1 = apellido1Controller
                                              .text
                                              .trim();
                                          String apellido2 = apellido2Controller
                                              .text
                                              .trim();
                                          String nombre = nombreController.text
                                              .trim();

                                          if (!await usuarioRegistrado(
                                            usuario,
                                          )) {
                                            await FirebaseFirestore.instance
                                                .collection('usuarios')
                                                .doc(usuario)
                                                .set({
                                                  'Dni': dni,
                                                  'Primer apellido': apellido1,
                                                  'Segundo apellido': apellido2,
                                                  'Nombre': nombre,
                                                  'Email': correo,
                                                  'Usuario': usuario,
                                                  'Rol': 'ALUMNO',
                                                }, SetOptions(merge: true));
                                            await registrarUsuarioAuth(
                                              correo,
                                              dni,
                                            );
                                          }

                                          await registrarAlumnoAsignatura(
                                            usuario,
                                            idAsignatura,
                                          );

                                          if (mounted) {
                                            setState(() {
                                              _cargando = false;
                                            });
                                            mostrarMensaje(
                                              scaffoldMessenger,
                                              'Se ha registrado al usuario $usuario correctamente',
                                              Colors.green,
                                            );
                                            navigator.pop(true);
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            setState(() {
                                              _cargando = false;
                                            });
                                            mostrarMensaje(
                                              scaffoldMessenger,
                                              'Error al registrar el alumno: $e',
                                              Colors.red,
                                            );
                                          }
                                        }
                                      }
                                    },
                              icon: const Icon(
                                Icons.person_add,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Registrar alumno',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Indicador de carga superpuesto
          if (_cargando)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Registrando alumno...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
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
    );
  }

  Widget _buildSeccionHeader({required IconData icon, required String titulo}) {
    return Row(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).primaryColor),
        const SizedBox(width: 12),
        Text(
          titulo,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      keyboardType: keyboardType,
      validator: validator,
    );
  }
}
