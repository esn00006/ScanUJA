// Web implementation
import 'package:web/web.dart' as web;

bool esDispositivoMovil() {
  try {
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    final platform = web.window.navigator.platform.toLowerCase();

    // Detectar dispositivos móviles por user agent
    bool esMobilePorUA = userAgent.contains('android') ||
           userAgent.contains('iphone') ||
           userAgent.contains('ipod') ||
           userAgent.contains('ipad') ||
           userAgent.contains('mobile') ||
           userAgent.contains('webos') ||
           userAgent.contains('blackberry') ||
           userAgent.contains('windows phone');

    // iPad moderno se identifica como "MacIntel" en desktop mode
    // Detectar por plataforma y capacidades táctiles
    bool esIPad = platform.contains('ipad') ||
                  (platform.contains('mac') && _tieneCapacidadesTactiles());

    return esMobilePorUA || esIPad;
  } catch (e) {
    // Si hay error, asumir que no es móvil
    return false;
  }
}

bool _tieneCapacidadesTactiles() {
  try {
    // Verificar si el dispositivo tiene capacidades táctiles
    // iPad en modo desktop se detecta así
    return web.window.navigator.maxTouchPoints > 0;
  } catch (e) {
    return false;
  }
}

