<p align="center"><img src="../images/icon.png" width="128" alt="Sysmon icon"></p>

# Sysmon: una pantalla de estado del Mac en una ESP32-2432S024R

[English](../../README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português (Brasil)](README.pt-BR.md) | [Русский](README.ru.md)

Convierte una ESP32-2432S024R (una placa con pantalla ST7789 de 2,4", conocida como "Cheap Yellow Display") en una pequeña pantalla de estado junto a tu monitor. De un vistazo ves la CPU, la presión de memoria y la velocidad de red, cuánto te queda de los límites de tu suscripción a Claude y ChatGPT, y un temporizador pomodoro que te recuerda descansar, levantarte y beber agua.

La app de la barra de menús **Sysmon** mide tu Mac cada 2 segundos y envía los datos a la placa por USB serie; la placa dibuja los anillos y las gráficas. Sin Wi-Fi y sin abrir ningún puerto en tu Mac.

![Pantalla de Sysmon junto a un monitor](../images/sysmon-preview.jpg)

<sub>Las ilustraciones se dibujan a partir del diseño y los colores reales del firmware; los datos son inventados.</sub>

> **Nota sobre idiomas:** la app del Mac está disponible en 10 idiomas. La placa, por ahora, solo muestra texto en chino; las imágenes de este README muestran una versión en inglés de las mismas pantallas.

## Pantallas

Vertical de 240×320, fondo oscuro. Cuatro pantallas: Sistema, Pomodoro, uso de Claude y uso de ChatGPT. Un aviso de recordatorio puede cubrir cualquiera de ellas.

![Las cuatro pantallas](../images/screens.jpg)

### Sistema

- **Arriba:** anillos de CPU y de presión de memoria. La CPU se pone amarilla al 50 % y roja al 80 %. El anillo de memoria sigue el nivel de presión de memoria de macOS (normal / advertencia / crítico), igual que el Monitor de Actividad.
- **Abajo:** velocidad actual de descarga y de subida, más una gráfica de dos colores de los últimos 5 minutos. La gráfica se escala al pico de esos 5 minutos.

### Pomodoro

- Un anillo grande muestra cuánto queda de la sesión actual, con el tiempo restante, la fase y la hora de finalización. La concentración es rojo tomate, el descanso corto verde y el descanso largo azul; en pausa o sin empezar, gris.
- Debajo: puntos de la ronda actual (4 sesiones de concentración por defecto), p. ej. "#2 · 2 more until long break" (n.º 2 · 2 más hasta el descanso largo), y el recuento de hoy, p. ej. "5 done · 2h 05m" (5 hechas · 2 h 05 min).
- Valores por defecto: 25 min de concentración, 5 min de descanso corto, 15 min de descanso largo tras cada 4.ª sesión de concentración. Todo es ajustable; los cambios se aplican desde la siguiente sesión.
- Solo la concentración necesita un inicio manual: una concentración terminada pasa directamente a un descanso, y un descanso terminado te espera.
- Inicia, pausa y reanuda con un único atajo global o desde el menú; el menú también tiene Saltar y Reiniciar ronda. Saltar una concentración la abandona y no se cuenta.
- El temporizador funciona con tiempo real, así que sigue corriendo mientras estás fuera, la pantalla está bloqueada o el Mac está en reposo. El recuento de hoy se reinicia a medianoche y sobrevive a los reinicios.
- Mientras te concentras, las demás pantallas muestran una fina línea de progreso rojo tomate de 3 px en la parte superior (gris en pausa).

### Uso de Claude y ChatGPT

- Un anillo grande para el límite de 5 horas con el tiempo que falta para que se restablezca, y barras para el límite semanal ("This week · resets Thu 14:00", esta semana · se restablece el jue a las 14:00). Claude también muestra sus límites semanales por modelo cuando la API los informa.
- Los mismos umbrales de color que la CPU. El pie muestra el plan (Max, Plus…) y lo recientes que son los datos.
- Los datos obsoletos siempre se marcan: "Expired" (Caducado) cuando la sesión ha caducado, "Couldn't read" (No se pudo leer) cuando una petición ha fallado, y "--" cuando una ventana ya se ha restablecido.

### Avisos de recordatorio

![Los cuatro avisos de recordatorio](../images/banners.jpg)

Estés en la pantalla que estés, un aviso ocupa toda la pantalla y la luz RGB de la parte trasera de la placa respira del mismo color (puedes apagar la luz). Toca la placa o pulsa el atajo de cambio de pantalla para descartarlo.

| Aviso | Cuándo | Color | Desaparece solo |
|---|---|---|---|
| Concentración terminada | Termina una sesión de concentración y empieza el descanso; muestra la cuenta atrás del descanso y los recordatorios retenidos durante la concentración | verde | cuando termina el descanso |
| Fin del descanso | Termina el descanso | rojo | cuando empiezas la siguiente concentración |
| Levántate | 50 minutos de uso real del ordenador | naranja | tras 5 minutos de ausencia |
| Bebe agua | 60 minutos de uso del ordenador | azul | no, toca para descartarlo |

- "Uso del ordenador" significa actividad de teclado o ratón. El tiempo de inactividad y la pantalla bloqueada o en reposo se suman como tiempo de ausencia: 5 minutos fuera reinician el temporizador de levantarse y 30 minutos reinician el del agua.
- No hay avisos durante la concentración (ni en pausa): se retienen y se incorporan al aviso de "Concentración terminada".
- Un aviso a la vez, en el orden de la tabla.

### Cambiar de pantalla y apagar

- Orden: Sistema → Pomodoro → Claude → ChatGPT. Toca en cualquier parte de la placa o pulsa el atajo global. Mientras se muestra un aviso, la misma acción lo descarta.
- Las pantallas desactivadas en Ajustes se omiten. Los puntos de página de la esquina superior derecha indican dónde estás.
- La pantalla y la luz se apagan en cuanto la pantalla del Mac entra en reposo, se bloquea, cambias de usuario o el Mac se duerme, y vuelven solas. Unos 10 segundos después de que Sysmon se cierre o se desenchufe el cable, la pantalla se apaga.

## La app de la barra de menús

- El icono es un módulo ESP32; aparece tachado mientras no hay ninguna placa conectada.
- El menú tiene el estado de la conexión, las acciones del pomodoro que tienen sentido en ese momento, Ajustes…, Acerca de Sysmon y Salir.
- Ajustes tiene cuatro pestañas:
  - **General:** el atajo de cambiar de pantalla, la luz RGB, el idioma de la app (Igual que el sistema o uno de 10 idiomas) y Abrir al iniciar sesión.
  - **Pomodoro:** la pantalla Pomodoro, el atajo de iniciar / pausar, las duraciones y las sesiones por ronda.
  - **Recordatorios:** los recordatorios para levantarse y para beber agua y sus intervalos.
  - **Uso:** las pantallas de uso de Claude y ChatGPT con su estado, y de dónde salen los datos.
- Los atajos globales usan teclas rápidas de Carbon, así que no hace falta el permiso de Accesibilidad. Detectar si estás en el ordenador lee el tiempo de inactividad del sistema, lo que tampoco requiere ningún permiso.
- Encuentra la placa por el ID de fabricante USB de WCH (CH340) y se reconecta al volver a enchufarla. Abrir o cerrar el puerto nunca reinicia la placa.
- El uso de CPU se mantiene cerca del 0 %.

<p align="center">
  <img src="../images/macos-settings-general.png" width="49%" alt="Settings: General">
  <img src="../images/macos-settings-pomodoro.png" width="49%" alt="Settings: Pomodoro">
</p>
<p align="center">
  <img src="../images/macos-settings-reminders.png" width="49%" alt="Settings: Reminders">
  <img src="../images/macos-settings-usage.png" width="49%" alt="Settings: Usage">
</p>

### De dónde salen los datos de uso

Sysmon toma prestadas, en solo lectura, las sesiones que ya tienes en tu Mac:

- **Claude:** las credenciales de Claude Code del llavero de inicio de sesión (elemento `Claude Code-credentials`, leído mediante `/usr/bin/security`, así que no aparece ningún aviso de permiso), enviadas al endpoint de uso de Anthropic.
- **ChatGPT:** el `~/.codex/auth.json` de Codex, enviado al endpoint de uso de ChatGPT.

Sysmon nunca renueva estas sesiones ni escribe en el llavero ni en `auth.json`, así que no puede cerrarte la sesión. La contrapartida: si pasas un tiempo sin usar Claude Code o Codex, la sesión caduca y la pantalla conserva las últimas cifras, marcadas como "Caducado" ("Expired"). Para arreglarlo, ejecuta `claude` una vez en una terminal, o abre Codex una vez; las cifras nuevas aparecen en menos de 2 minutos. El uso se consulta cada 2 minutos, y no mientras la pantalla está apagada.

Ninguno de los dos endpoints está documentado y cualquiera puede cambiar. Si no se puede interpretar uno, solo esa pantalla muestra "No se pudo leer" ("Couldn't read").

## Requisitos

| Elemento | Requisito |
|---|---|
| Placa | ESP32-2432S024R (ESP32-D0WD-V3, 4 MB de flash, ST7789 240×320, serie CH340) |
| Mac | macOS 14 o posterior |
| Toolchain del firmware | [PlatformIO](https://platformio.org/) |
| Toolchain del Mac | Xcode Command Line Tools (Swift 6) |

## Inicio rápido

```bash
git clone git@github.com:pokoblin/esp32-2432S024r-macos.git
cd esp32-2432S024r-macos
```

### 1. Grabar el firmware

```bash
cd sysmon/firmware
pio run -e esp32dev -t upload
```

`platformio.ini` usa `/dev/cu.usbserial-114110`; cámbialo por tu puerto (`ls /dev/cu.usbserial-*`). Cierra Sysmon antes de grabar, o el puerto estará ocupado.

> A través de un hub USB, esta placa falla al grabar a 921600 y 460800, por eso `upload_speed` está fijado en 115200.

### 2. Instalar la app de la barra de menús

```bash
cd sysmon/macos
bash scripts/bundle.sh
open ~/Applications/Sysmon.app
```

`bundle.sh` compila una versión release, crea `Sysmon.app`, la firma ad hoc y la instala en `~/Applications`. Activa "Abrir al iniciar sesión" en Ajustes si quieres.

## Desarrollo

Ejecutar las pruebas:

```bash
cd sysmon/firmware && pio test -e native
cd sysmon/macos && swift test
```

Controlar la placa sin Sysmon (necesita pyserial; el Python de PlatformIO ya lo incluye):

```bash
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110                    # sys / pomo / cl / gpt con --page
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --cycle            # rota las pantallas automáticamente
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --page pomo --phase paused
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --banner done      # done / brk / sit / water
python sysmon/tools/fake_feed.py /dev/cu.usbserial-114110 --off
```

Los títulos de los avisos usan una fuente minúscula que contiene solo los caracteres que necesitan (el firmware ya usa más del 90 % de su flash). Tras cambiar los títulos en `lib/sysmon_core/banner_titles.h`, hay que regenerarla; la fuente es Source Han Sans CN Bold (SIL Open Font License 1.1) y debe estar instalada en local:

```bash
swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
```

Las imágenes del README se generan con `docs/images/make_preview.py` y `docs/images/make_screens.py`; los comandos están en la cabecera de cada script.

### Protocolo serie

115200 8N1, texto plano, un registro por línea:

```
S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640
OFF
```

| Campo | Significado |
|---|---|
| `cpu` | uso de CPU, 0–100 |
| `mem` | porcentaje de presión de memoria, 0–100 |
| `lvl` | nivel de presión de memoria: 1 normal, 2 advertencia, 4 crítico |
| `rx` / `tx` | velocidad de descarga / subida, en bytes por segundo |
| `OFF` | apaga la pantalla hasta la siguiente línea `S` |

El firmware ignora las líneas y los campos desconocidos. Las páginas, el uso, el pomodoro y los avisos usan las líneas `P`, `U`, `T` y `B`, y la placa envía `TAP` cuando se toca: consulta los comentarios de cabecera de `usage_protocol.h`, `timer_protocol.h` y `Protocol.swift`.

## Estructura del repositorio

```
sysmon/
  firmware/            ESP32 firmware (PlatformIO + Arduino + LovyanGFX)
    lib/sysmon_core/   pure logic: protocol parsing, screen-off state, chart history, copy, tap debounce, colors, breathing curve
    src/               display config, drawing, RGB light, generated banner font, main loop
    test/              unit tests that run on the computer
  macos/               menu bar app (SwiftPM)
    Sources/SysmonCore/  CPU/memory/network sampling, serial, device discovery, usage credentials and parsing,
                         page order, pomodoro and reminder rules, localization
    Sources/Sysmon/      SwiftUI menu bar UI, Settings, About, global shortcuts
    scripts/bundle.sh    build and install the .app
    scripts/make_icon.sh     compiles the app icon from AppIcon.icon (Icon Composer)
  tools/fake_feed.py   fake data for the board, no Mac app needed
  tools/make_banner_font.swift  generates the banner title font
hw_probe/              hardware probe firmware: display driver, touch chip and pins
touch_diag/            raw XPT2046 touch diagnostics
touch_test/            touch calibration and drawing test; board.h is the verified display config
docs/images/           README pictures and their generators
docs/readme/           translated READMEs
```

## Notas de hardware

- El controlador de pantalla es un **ST7789**, no un ILI9341. Con `Panel_ILI9341` la imagen sale transpuesta y en espejo.
- Ajustes de LovyanGFX: `rgb_order=false` (con true se intercambian el rojo y el azul), `invert=false`, rotación 0.
- Retroiluminación en GPIO27, activa en alto. El MISO de la pantalla no está conectado, así que no se puede leer su ID.
- El LED RGB de la parte trasera es de ánodo común, activo en bajo: GPIO4 rojo, GPIO16 azul, GPIO17 verde (el azul y el verde están al revés de lo que dicen la mayoría de las notas sobre la CYD).
- El CH340 controla EN y GPIO0 mediante DTR/RTS. Sysmon pone ambas a cero justo después de abrir el puerto y desactiva `HUPCL`, de modo que abrir o cerrar el puerto nunca reinicia la placa.
