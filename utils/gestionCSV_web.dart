// Implementación específica para exportar ficheros en Web
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';

Future<void> descargarCSV(
  BuildContext context,
  String csv,
  String nombreArchivo,
) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  try {
    // Agregar BOM UTF-8 para mejor compatibilidad con Excel
    const utf8Bom = '\uFEFF';
    final bytes = utf8.encode(utf8Bom + csv);

    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = nombreArchivo;
    anchor.click();
    web.URL.revokeObjectURL(url);

    mostrarMensaje(
      scaffoldMessenger,
      'Archivo CSV exportado correctamente: $nombreArchivo',
      Colors.green,
    );
  } catch (e) {
    mostrarMensaje(scaffoldMessenger, 'Error al descargar el archivo: $e', Colors.red);
  }
}
