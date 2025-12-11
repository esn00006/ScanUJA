// Implementación específica para exportar ficheros en Android/iOS
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistema_gamificacion/pantallas/widgets.dart';

Future<void> descargarCSV(
  BuildContext context,
  String csv,
  String nombreArchivo,
) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  try {
    Directory? directory;

    if (Platform.isAndroid) {
      // Para Android, usar el directorio de la aplicación que es accesible
      // sin permisos especiales (scoped storage)
      directory = await getExternalStorageDirectory();

      if (directory != null) {
        // Crear una carpeta "CSV_Exports" dentro del directorio de la app
        final exportDir = Directory('${directory.path}/CSV_Exports');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        directory = exportDir;
      }
    } else {
      // En iOS, usar el directorio de documentos
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) {
      throw 'No se pudo acceder al almacenamiento del dispositivo';
    }

    // Crear la ruta completa del archivo
    final filePath = '${directory.path}/$nombreArchivo';

    // Crear y escribir el archivo con codificación UTF-8
    final file = File(filePath);

    // Agregar BOM UTF-8 para mejor compatibilidad con Excel
    const utf8Bom = '\uFEFF';
    await file.writeAsString(utf8Bom + csv, encoding: utf8);

    // Mostrar mensaje de éxito con la ubicación
    if (context.mounted) {
      mostrarMensaje(
        scaffoldMessenger,
        'Archivo CSV guardado exitosamente:\n$nombreArchivo\n\nUbicación: ${directory.path}',
        Colors.green,
      );
    }
  } catch (e) {
    if (context.mounted) {
      mostrarMensaje(
        scaffoldMessenger,
        'Error al guardar el archivo CSV: $e',
        Colors.red,
      );
    }
  }
}
