import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_gamificacion/pantallas/login.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';
import 'package:sistema_gamificacion/utils/rol_provider.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  bool _mensajeMostrado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!authSnapshot.hasData || authSnapshot.data == null) {
            _mensajeMostrado = false;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Provider.of<RolProvider>(context, listen: false).limpiarRol();
              }
            });

            return Login();
          }

          final usuario = authSnapshot.data!.email!.split('@')[0];

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(usuario)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (userSnapshot.hasError) {
                logOutMsg(
                  context,
                  'Error al verificar datos del usuario $usuario',
                );
                return Login();
              }

              if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                logOutMsg(
                  context,
                  'Usuario $usuario no encontrado en la base de datos',
                );
                return Login();
              }

              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>?;
              final rol = userData?['Rol'] as String?;

              if (rol == null || rol == 'ELIMINADO') {
                logOutMsg(
                  context,
                  'El usuario $usuario ha sido eliminado del sistema',
                );
                return const Login();
              }

              _mensajeMostrado = false;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                final rolProvider = Provider.of<RolProvider>(
                  context,
                  listen: false,
                );
                rolProvider.setRol(rol);
                rolProvider.inicializarListener();
              });

              return const MainScreen();
            },
          );
        },
      ),
    );
  }

  void logOutMsg(BuildContext context, String mensaje) {
    if (!_mensajeMostrado) {
      _mensajeMostrado = true;

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final rolProvider = Provider.of<RolProvider>(context, listen: false);
      rolProvider.limpiarRol();

      FirebaseAuth.instance.signOut();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          mostrarMensaje(scaffoldMessenger, mensaje, Colors.red);
        }
      });
    }
  }
}
