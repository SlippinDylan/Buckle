<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>Tus herramientas habituales de Mac, a un clic.</p>
  <p><a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <strong>Español</strong></p>
</div>

Buckle es una app nativa de macOS en la barra de menús que reúne herramientas del sistema, inicio de navegadores en otro idioma y acciones habituales del Finder. Funciona en segundo plano sin icono en el Dock.

> [!NOTE]
> Buckle 0.1.0 aún no tiene un instalador público. Sigue las instrucciones de compilación de abajo.

## Funciones

<table>
  <tr>
    <td width="36%"><strong>Herramientas del sistema en la barra de menús</strong><br><br>Abre la ventana de memoria del sistema, restablece utilidades del ratón con progreso y resultado, o reinicia la barra de menús del sistema. Cada acción del Finder se activa por separado; una marca indica que está activada.</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="Herramientas del sistema en la barra de menús"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Acciones directamente en el Finder</strong><br><br>Añade AirDrop, Abrir en Terminal, Copiar ruta y Trasladar ítems aquí al menú contextual del Finder. Abre Terminal en la carpeta seleccionada o actual y copia varias rutas en líneas separadas.</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="Acciones directamente en el Finder"></td>
  </tr>
  <tr>
    <td width="36%"><strong>Inicia navegadores en ocho idiomas</strong><br><br>Elige un navegador instalado y después un idioma. Buckle detecta los navegadores compatibles cada vez que abres el menú. La app los inicia directamente, sin scripts personales.</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="Inicia navegadores en ocho idiomas"></td>
  </tr>
</table>

### Ajustes

Configura el inicio de sesión y el idioma en **Ajustes → General**. La interfaz sigue macOS por defecto. Puedes elegir inglés, chino simplificado o tradicional, japonés, coreano, alemán, francés o español. Reinicia Buckle para aplicar el cambio de idioma.

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="Ajustes generales">
  <img src="images/readme/permissions-settings.png" width="340" alt="Estado de los permisos">
</p>

Las capturas muestran la interfaz en inglés. Los menús varían según los navegadores instalados, las acciones activadas y los archivos copiados.

## Instalación y primer uso

Requiere **macOS 15 o posterior**, en Apple Silicon o Intel. Las compilaciones de CI tienen como destino Universal 2.

1. Sigue los pasos de compilación e instalación de abajo y abre la app instalada desde `/Applications`.
2. Pulsa el icono de la barra de menús para usar una herramienta o activar una acción del Finder. Las cuatro acciones están desactivadas inicialmente; después se guardan tus elecciones.
3. Abre **Ajustes → Permisos** para activar la extensión del Finder o conceder los accesos solicitados. El estado se actualiza automáticamente; el texto verde y la marca indican acceso concedido o extensión activada.

Las compilaciones usan firma ad hoc y no están notarizadas. Una versión descargada puede necesitar autorización en Ajustes del Sistema; tras una actualización puede ser necesario volver a conceder permisos.

## Antes de usar las herramientas

- **Ventana de memoria:** abre manualmente LowMemoryPanel de macOS, incluso con un uso normal de memoria. Su mensaje integrado de falta de memoria de aplicaciones no es un diagnóstico. Utiliza una vía de depuración privada del sistema, por lo que la compatibilidad puede variar. Requiere Accesibilidad y Automatización de System Events. No supervisa la memoria en segundo plano.
- **Restablecer ratón:** actualiza los servicios relacionados y reinicia solo las utilidades compatibles que ya estaban ejecutándose: Moom, MonitorControl, BetterMouse e iShot Pro. macOS solicita autorización de administrador cuando hace falta.
- **Reiniciar la barra de menús:** reinicia el SystemUIServer del usuario actual sin sudo. Puede que no solucione los iconos gestionados por otras apps.
- **Perfiles del navegador:** los navegadores Chromium usan un perfil independiente por idioma, sin tus sesiones habituales. Cierra Safari antes de cambiar su idioma. No cambia la IP ni la zona horaria, ni garantiza el idioma de los sitios web.
- **Finder:** la extensión copia las rutas directamente; las demás acciones inician Buckle cuando hace falta. Para mover archivos, cópialos en el Finder y haz clic derecho en la carpeta de destino o en su fondo. El movimiento requiere confirmación, no reemplaza elementos existentes y no se integra con Deshacer del Finder. Si falla parcialmente, se conservan los movimientos completados; revisa ambas carpetas antes de reintentar. El Finder determina la posición del menú.
- **Actualizaciones:** Sparkle está integrado. La comprobación manual está en **Ajustes → Acerca de**, y la automática en **General**. Las compilaciones de desarrollo y prueba de CI desactivan las actualizaciones. La actualización en línea requiere un instalador publicado y un feed firmado.

## Compilar desde el código fuente

Requiere Xcode 26 o posterior, Node.js y Python 3. No se necesita una cuenta de desarrollador de Apple para Debug.

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

Después de compilar, elige uno de los dos procedimientos siguientes.

### Instalar para el uso diario

Cierra Buckle con **Salir** en su menú de la barra de menús y espera a que termine. En el Finder, mueve toda la app `Buckle.app` desde `build/DerivedData/Build/Products/Debug/` a `/Applications`. Si sustituyes una copia existente, ciérrala primero. Abre `/Applications/Buckle.app` y mantén una sola copia instalada.

### Ejecutar para desarrollo

Cierra cualquier Buckle en ejecución con **Salir** y espera a que termine antes de ejecutar el comando de abajo. También puedes abrir después `Buckle.xcodeproj` y ejecutar el scheme `Buckle` en Debug. Buckle solo permite una instancia en ejecución: el proceso nuevo se cierra si otra copia sigue activa. Durante el desarrollo, usa la compilación que quieras probar sin abrir a la vez la copia instalada.

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

## Documentación de desarrollo

La [guía de desarrollo](development.md) (chino simplificado) describe las comprobaciones, CI, empaquetado, publicación de actualizaciones, firma y validación en un Mac real. Los futuros instaladores públicos estarán en [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases).
