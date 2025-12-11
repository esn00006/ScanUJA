import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Provider que gestiona el rol del usuario en tiempo real
/// Escucha cambios en Firestore y notifica a todos los widgets suscritos
class RolProvider extends ChangeNotifier {
  String? _rol;
  StreamSubscription<DocumentSnapshot>? _rolSubscription;

  String? get rol => _rol;

  bool get esAlumno => _rol?.toLowerCase() == 'alumno';
  bool get esProfesor => _rol?.toLowerCase() == 'profesor';
  bool get esTester => _rol?.toLowerCase() == 'tester';

  void inicializarListener() {
    final user = FirebaseAuth.instance.currentUser;

    if (user?.email != null) {
      final usuario = user!.email!.split('@')[0];

      _rolSubscription?.cancel();

      _rolSubscription = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario)
          .snapshots()
          .listen((doc) {
            if (doc.exists) {
              final nuevoRol = doc.data()?['Rol'] as String?;
              if (_rol != nuevoRol) {
                _rol = nuevoRol;
                notifyListeners();
              }
            }
          });
    }
  }

  void setRol(String? nuevoRol) {
    if (_rol != nuevoRol) {
      _rol = nuevoRol;
      notifyListeners();
    }
  }

  void limpiarRol() {
    _rolSubscription?.cancel();
    _rol = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _rolSubscription?.cancel();
    super.dispose();
  }
}