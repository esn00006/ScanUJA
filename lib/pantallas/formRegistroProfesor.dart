import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/gestionBDD.dart';

class FormularioRegistroProfesor extends StatefulWidget {
  const FormularioRegistroProfesor({super.key});

  @override
  State<FormularioRegistroProfesor> createState() =>
      _FormularioRegistroProfesorState();
}

class _FormularioRegistroProfesorState
    extends State<FormularioRegistroProfesor> {
  final _formKey = GlobalKey<FormState>();

  final dniController = TextEditingController();
  final apellido1Controller = TextEditingController();
  final apellido2Controller = TextEditingController();
  final nombreController = TextEditingController();
  final correoController = TextEditingController();

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
        title: const Text(
          'Registro de profesor',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        elevation: 0,
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
                          titulo: 'Datos del profesor',
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
                          hint: 'SIDUJA@ujaen.es',
                          icon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'El correo electrónico no puede estar vacío';
                            }
                            if (!value.contains('@ujaen.es')) {
                              return 'El correo electrónico debe ser institucional (@ujaen.es)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              final scaffoldMessenger = ScaffoldMessenger.of(context);

                              String correo = correoController.text.trim();
                              String usuario = correo.split('@')[0];

                              String dni = dniController.text.trim();
                              String apellido1 = apellido1Controller.text
                                  .trim();
                              String apellido2 = apellido2Controller.text
                                  .trim();
                              String nombre = nombreController.text.trim();

                              if (!await usuarioRegistrado(usuario)) {
                                await FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(usuario)
                                    .set({
                                      'DNI': dni,
                                      'Primer apellido': apellido1,
                                      'Segundo apellido': apellido2,
                                      'Nombre': nombre,
                                      'Email': correo,
                                      'Usuario': usuario,
                                      'Rol': 'PROFESOR',
                                    }, SetOptions(merge: true));
                                registrarUsuarioAuth(correo, dni);
                              }

                              mostrarMensaje(
                                scaffoldMessenger,
                                'Se ha registrado al usuario $usuario correctamente',
                                Colors.green,
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.person_add,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Registrarse',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
