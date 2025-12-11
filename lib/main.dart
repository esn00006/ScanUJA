import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// BDD Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:sistema_gamificacion/pantallas/wrapper.dart';
import 'package:sistema_gamificacion/utils/rol_provider.dart';
import 'utils/firebase_options.dart';

// Función principal - punto de entrada de la aplicación
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    // Espera hasta que se realiza la conexión con la BDD
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// Widget raíz de la aplicación
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RolProvider(),
      child: MaterialApp(
        // Título de la app (aparece en multitarea)
        title: 'ScanUJA',

        // Quitar banner de debug
        debugShowCheckedModeBanner: false,

        // Tema visual de la app
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF20860C),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),

        // Pantalla inicial que se muestra al abrir la app
        home: Wrapper(),
      ),
    );
  }
}
