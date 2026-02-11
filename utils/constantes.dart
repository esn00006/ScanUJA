import 'package:flutter/material.dart';

// Tipos de actividades disponibles
const List<Map<String, dynamic>> infoActividad = [
  {
    'id': 'ejercicio-clase',
    'nombre': 'Ejercicio de pizarra',
    'icono': Icons.book,
    'color': Colors.blue,
  },
  {
    'id': 'pregunta-clase',
    'nombre': 'Preguntas en clase',
    'icono': Icons.question_answer,
    'color': Colors.green,
  },
  {
    'id': 'test-platea',
    'nombre': 'Test Platea',
    'icono': Icons.laptop,
    'color': Colors.orange,
  },
  {
    'id': 'ejercicio-evaluable',
    'nombre': 'Ejercicio evaluable',
    'icono': Icons.assignment,
    'color': Colors.purple,
  },
];

const colorInsignia = {
  'bronce': Color(0xFFCD7F32),
  'plata': Color(0xFFC0C0C0),
  'oro': Color(0xFFFFD700),
};

// Tipos de QR disponibles
const List<Map<String, dynamic>> tipoInsignia = [
  {
    'id': 'bronce',
    'nombre': 'Bronce',
    'icono': Icons.workspace_premium,
    'color': Color(0xFFCD7F32),
    'puntuacion': 5,
  },
  {
    'id': 'plata',
    'nombre': 'Plata',
    'icono': Icons.workspace_premium,
    'color': Color(0xFFC0C0C0),
    'puntuacion': 10,
  },
  {
    'id': 'oro',
    'nombre': 'Oro',
    'icono': Icons.workspace_premium,
    'color': Color(0xFFFFD700),
    'puntuacion': 20,
  },
];
