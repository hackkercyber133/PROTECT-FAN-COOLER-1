import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

const String kAppVersion = "1.2.1";

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cooler Controller',
      theme: ThemeData.dark(),
      home: SplashScreen(),
    );
  }
}

// =======================================================================
// ===== SPLASH SCREEN — ANIMASI PEMBUKA BERGAYA GAMING (MLBB/FF STYLE) ===
// =======================================================================
class _SplashParticle {
  final double x; // posisi horizontal awal (0..1)
  final double speed; // faktor kecepatan naik
  final double size; // ukuran partikel
  final double phase; // offset siklus awal (0..1)
  final double drift; // amplitudo goyangan horizontal

  _SplashParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.phase,
    required this.drift,
  });
}

class SplashScreen extends StatefulWidget {
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Controller utama: menjalankan urutan animasi satu-kali selama 5.2 detik.
  late final AnimationController _mainCtrl;
  // Controller loop: partikel, cincin energi, dan efek "shine" berjalan terus-menerus.
  late final AnimationController _loopCtrl;
  late final List<_SplashParticle> _particles;

  @override
  void initState() {
    super.initState();

    final rnd = Random(7);
    _particles = List.generate(42, (i) {
      return _SplashParticle(
        x: rnd.nextDouble(),
        speed: 0.35 + rnd.nextDouble() * 0.9,
        size: 1.2 + rnd.nextDouble() * 2.6,
        phase: rnd.nextDouble(),
        drift: rnd.nextDouble() * 18 - 9,
      );
    });

    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 9000));
    _loopCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();

    _mainCtrl.forward();
    _mainCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 400), _goToApp);
      }
    });
  }

  void _goToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, anim, __) => ControllerPage(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.06, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color neon = Color(0xFF33F0FF);

    return Scaffold(
      backgroundColor: const Color(0xFF03040A),
      body: AnimatedBuilder(
        animation: Listenable.merge([_mainCtrl, _loopCtrl]),
        builder: (context, _) {
          final t = _mainCtrl.value.clamp(0.0, 1.0);
          final loop = _loopCtrl.value;

          double stage(double begin, double end, {Curve curve = Curves.linear}) {
            return curve.transform(Interval(begin, end, curve: Curves.linear).transform(t)).clamp(0.0, 1.0);
          }

          final ringIntro = stage(0.0, 0.45, curve: Curves.easeOutExpo);
          final logoScale = stage(0.05, 0.55, curve: Curves.elasticOut);
          final logoFade = stage(0.0, 0.30);
          final titleT = stage(0.35, 0.70, curve: Curves.easeOutCubic);
          final subtitleT = stage(0.50, 0.80, curve: Curves.easeOutCubic);
          final barT = stage(0.55, 0.98, curve: Curves.easeInOutCubic);
          final flashT = stage(0.94, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // latar gradasi radial gelap ala HUD game
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.1),
                    radius: 1.15,
                    colors: [Color(0xFF0C1B2A), Color(0xFF03040A)],
                  ),
                ),
              ),
              // partikel energi melayang naik
              CustomPaint(
                painter: _ParticlePainter(particles: _particles, loop: loop, color: neon),
                size: Size.infinite,
              ),
              // cincin gelombang energi di belakang logo
              Center(
                child: CustomPaint(
                  painter: _RingPainter(loopValue: loop, intro: ringIntro, color: neon),
                  size: const Size(320, 320),
                ),
              ),
              // bingkai hexagon berputar (efek "circuit")
              Center(
                child: Transform.rotate(
                  angle: loop * 2 * pi,
                  child: Opacity(
                    opacity: (0.28 * ringIntro).clamp(0.0, 0.28),
                    child: CustomPaint(
                      painter: _HexPainter(color: neon),
                      size: const Size(210, 210),
                    ),
                  ),
                ),
              ),
              // konten utama: logo, judul, subjudul, progress bar
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: logoFade,
                      child: Transform.scale(
                        scale: 0.4 + 0.6 * logoScale,
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [neon.withOpacity(0.9), Colors.blueAccent.withOpacity(0.6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: neon.withOpacity(0.5 + 0.25 * sin(loop * 2 * pi).abs()),
                                blurRadius: 42,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.ac_unit, color: Colors.white, size: 56),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: titleT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - titleT) * 18),
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            final sweep = (loop * 2.4) % 2.4 - 0.7;
                            return LinearGradient(
                              colors: const [Colors.white, Color(0xFFBFF7FF), Colors.white],
                              stops: [
                                (sweep - 0.25).clamp(0.0, 1.0),
                                sweep.clamp(0.0, 1.0),
                                (sweep + 0.25).clamp(0.0, 1.0),
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'COOLER CONTROLLER',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: subtitleT,
                      child: Text(
                        'GAME-GRADE VOLTAGE ENGINE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 4,
                          color: neon.withOpacity(0.8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Opacity(
                      opacity: barT > 0 ? 1 : 0,
                      child: Column(
                        children: [
                          Container(
                            width: 190,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: barT,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: LinearGradient(colors: [neon, Colors.blueAccent]),
                                    boxShadow: [BoxShadow(color: neon.withOpacity(0.7), blurRadius: 8)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'LOADING ${(barT * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // versi aplikasi di bagian bawah
              Positioned(
                bottom: 26,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: subtitleT,
                  child: Center(
                    child: Text(
                      'v$kAppVersion',
                      style: const TextStyle(color: Colors.white30, fontSize: 12, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
              // kilatan putih halus saat transisi keluar dari splash
              if (flashT > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: (flashT * 0.85).clamp(0.0, 0.85),
                    child: Container(color: Colors.white),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_SplashParticle> particles;
  final double loop;
  final Color color;
  _ParticlePainter({required this.particles, required this.loop, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final progress = (loop + p.phase) % 1.0;
      final y = size.height * (1 - progress);
      final x = p.x * size.width + sin((progress + p.phase) * 2 * pi) * p.drift;
      final opacity = sin(progress * pi).clamp(0.0, 1.0);
      paint.color = color.withOpacity(0.55 * opacity);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

class _RingPainter extends CustomPainter {
  final double loopValue;
  final double intro;
  final Color color;
  _RingPainter({required this.loopValue, required this.intro, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final progress = (loopValue + i / 3) % 1.0;
      final radius = maxRadius * progress * intro;
      final opacity = ((1 - progress) * 0.5 * intro).clamp(0.0, 0.5);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withOpacity(opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => true;
}

class _HexPainter extends CustomPainter {
  final Color color;
  _HexPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (pi / 3) * i - pi / 2;
      final point = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) => false;
}

class ControllerPage extends StatefulWidget {
  @override
  _ControllerPageState createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  // ===== MODE KONEKSI =====
  String connectionMode = "WiFi"; // "WiFi" atau "Bluetooth"

  // ===== TEMA WARNA (custom) =====
  Color accentColor = Colors.cyanAccent;
  final List<Color> colorPalette = [
    Colors.cyanAccent,
    Colors.purpleAccent,
    Colors.greenAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.blueAccent,
    Colors.amberAccent,
    Colors.tealAccent,
    Colors.redAccent,
    Colors.lightGreenAccent,
  ];

  // ===== MQTT =====
  MqttServerClient? mqttClient;
  final String broker = "broker.emqx.io";
  final String cmdTopic = "cooler/command";
  final String statusTopic = "cooler/status";

  // ===== BLUETOOTH =====
  BluetoothDevice? bleDevice;
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  bool bleConnected = false;

  // ===== DATA VOLTASE =====
  // Hardware (board decoy PD3.1/QC3.0) cuma mendukung 3 level tegangan
  // tetap secara fisik: 5V / 9V / 12V. Tidak ada mode kontinu.
  double setVolt = 5.0; // voltase yang sedang aktif/terkirim
  String uptime = "00:00:00";
  String status = "🔴 Offline";

  // ===== WIFI SETUP =====
  List<Map<String, dynamic>> wifiList = [];
  bool isScanningWifi = false;
  String selectedSSID = "";
  TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (connectionMode == "WiFi") connectMQTT();
    scanBLE();
  }

  // ===== MQTT =====
  void connectMQTT() async {
    mqttClient = MqttServerClient(broker, 'flutter_client');
    mqttClient!.port = 1883;
    mqttClient!.keepAlivePeriod = 20;
    mqttClient!.onConnected = () {
      setState(() => status = "🟢 Online");
      mqttClient!.subscribe(statusTopic, MqttQos.atLeastOnce);
    };
    mqttClient!.onDisconnected = () => setState(() => status = "🔴 Offline");
    mqttClient!.updates!.listen((msgs) {
      final msg = msgs[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      try {
        var data = jsonDecode(payload);
        setState(() {
          setVolt = (data['setVoltage'] ?? setVolt).toDouble();
          uptime = data['uptime'] ?? "00:00:00";
        });
      } catch (e) {}
    });
    try {
      await mqttClient!.connect();
    } catch (e) {
      setState(() => status = "🔴 Offline");
    }
  }

  bool get _mqttConnected =>
      mqttClient != null &&
      mqttClient!.connectionStatus!.state == MqttConnectionState.connected;

  void sendCommandMQTT(double volt) async {
    if (!_mqttConnected) {
      setState(() => status = "🔴 Offline");
      _showSnack("⚠️ Tidak terhubung ke broker MQTT");
      return;
    }
    var builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({"voltage": volt}));
    mqttClient!.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    setState(() {
      setVolt = volt;
    });
  }

  // ===== BLUETOOTH =====
  void scanBLE() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));
    FlutterBluePlus.onScanResults.listen((results) {
      setState(() {
        scanResults = results.where((r) => r.device.name.contains("ESP32")).toList();
      });
    });
    await Future.delayed(Duration(seconds: 6));
    setState(() {
      isScanning = false;
    });
  }

  Future<void> connectBLE(ScanResult result) async {
    try {
      await result.device.connect();
      setState(() {
        bleDevice = result.device;
        bleConnected = true;
        status = "🟢 Online";
      });
      List<BluetoothService> services = await result.device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.setNotifyValue(true);
            characteristic.onValueReceived.listen((value) {
              String payload = utf8.decode(value);
              try {
                var data = jsonDecode(payload);
                setState(() {
                  setVolt = (data['setVoltage'] ?? setVolt).toDouble();
                  uptime = data['uptime'] ?? "00:00:00";
                });
              } catch (e) {}
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        bleConnected = false;
        status = "🔴 Offline";
      });
    }
  }

  void sendCommandBLE(double volt) async {
    if (!bleConnected || bleDevice == null) {
      setState(() => status = "🔴 Offline");
      _showSnack("⚠️ Belum terhubung ke perangkat Bluetooth");
      return;
    }
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode({"voltage": volt})));
            setState(() {
              setVolt = volt;
            });
            return;
          }
        }
      }
    } catch (e) {
      _showSnack("❌ Gagal mengirim perintah ke perangkat");
    }
  }

  void sendVoltage(double volt) {
    volt = double.parse(volt.toStringAsFixed(1));
    if (connectionMode == "WiFi") {
      sendCommandMQTT(volt);
    } else {
      sendCommandBLE(volt);
    }
  }

  // ===== WIFI SETUP =====
  Future<void> scanWiFi() async {
    setState(() {
      isScanningWifi = true;
      wifiList.clear();
    });
    try {
      var response =
          await http.get(Uri.parse("http://192.168.4.1/scanwifi")).timeout(Duration(seconds: 5));
      if (response.statusCode == 200) {
        if (response.body.contains("scanning")) {
          await Future.delayed(Duration(seconds: 3));
          await scanWiFi();
          return;
        }
        List<dynamic> data = jsonDecode(response.body);
        setState(() {
          wifiList = data.map((e) => {"ssid": e['ssid'], "rssi": e['rssi']}).toList();
          isScanningWifi = false;
        });
      }
    } catch (e) {
      setState(() {
        isScanningWifi = false;
      });
      _showSnack("⚠️ Pastikan HP terhubung ke ESP32-Config");
    }
  }

  Future<void> connectWiFi(String ssid, String password) async {
    try {
      var url = Uri.parse("http://192.168.4.1/setwifi?ssid=$ssid&password=$password");
      var response = await http.get(url);
      if (response.statusCode == 200) {
        _showSnack("✅ ESP32 berhasil terhubung ke $ssid");
        Navigator.pop(context);
        await Future.delayed(Duration(seconds: 5));
        connectMQTT();
      } else {
        _showSnack("❌ Gagal terhubung, coba lagi");
      }
    } catch (e) {
      _showSnack("⚠️ Pastikan HP terhubung ke ESP32-Config");
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ===== CACHE =====
  void clearAppCache() {
    setState(() {
      wifiList.clear();
      scanResults.clear();
      selectedSSID = "";
      passwordController.clear();
    });
    Navigator.of(context, rootNavigator: true).pop();
    _showSnack("🧹 Cache aplikasi berhasil dibersihkan");
  }

  void clearEsp32Cache() {
    if (connectionMode == "WiFi") {
      if (_mqttConnected) {
        var builder = MqttClientPayloadBuilder();
        builder.addString(jsonEncode({"action": "clear_cache"}));
        mqttClient!.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
        _showSnack("🧹 Perintah bersihkan cache modul ESP32 terkirim");
      } else {
        _showSnack("⚠️ Tidak terhubung ke ESP32, cache tidak bisa dibersihkan");
      }
    } else {
      if (bleConnected) {
        sendBLERaw({"action": "clear_cache"});
        _showSnack("🧹 Perintah bersihkan cache modul ESP32 terkirim");
      } else {
        _showSnack("⚠️ Tidak terhubung ke ESP32, cache tidak bisa dibersihkan");
      }
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> sendBLERaw(Map<String, dynamic> payload) async {
    if (!bleConnected || bleDevice == null) return;
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode(payload)));
            return;
          }
        }
      }
    } catch (e) {}
  }

  // ===== DIALOG: SETUP WIFI =====
  void showWiFiSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            backgroundColor: Color(0xFF11161f),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.wifi, color: accentColor),
                SizedBox(width: 8),
                Expanded(
                    child: Text("Hubungkan Internet ESP32",
                        style: TextStyle(color: Colors.white, fontSize: 16))),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text("📶 WiFi di sekitar",
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70)),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: accentColor),
                        onPressed: () => scanWiFi(),
                      ),
                    ],
                  ),
                  Expanded(
                    child: isScanningWifi
                        ? Center(child: CircularProgressIndicator(color: accentColor))
                        : wifiList.isEmpty
                            ? Center(
                                child: Text(
                                    "Tidak ada WiFi ditemukan\nPastikan HP terhubung ke ESP32-Config",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white54)))
                            : ListView.builder(
                                itemCount: wifiList.length,
                                itemBuilder: (ctx, index) {
                                  var wifi = wifiList[index];
                                  bool isSelected = selectedSSID == wifi['ssid'];
                                  return Card(
                                    color: isSelected ? accentColor.withOpacity(0.15) : Colors.grey.shade900,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                          color: isSelected ? accentColor : Colors.transparent, width: 1.4),
                                    ),
                                    child: ListTile(
                                      leading: Icon(Icons.wifi, color: accentColor),
                                      title: Text(wifi['ssid'], style: TextStyle(color: Colors.white)),
                                      trailing:
                                          Text("${wifi['rssi']}dBm", style: TextStyle(color: Colors.grey)),
                                      onTap: () {
                                        setStateDialog(() {
                                          selectedSSID = wifi['ssid'];
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                  if (selectedSSID.isNotEmpty) ...[
                    Divider(color: Colors.white24),
                    TextField(
                      controller: passwordController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Password WiFi",
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: accentColor)),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (passwordController.text.isNotEmpty) {
                            connectWiFi(selectedSSID, passwordController.text);
                          } else {
                            _showSnack("Masukkan password!");
                          }
                        },
                        child: Text("🔗 Hubungkan"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Tutup", style: TextStyle(color: accentColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== DIALOG: ABOUT / CHANGELOG =====
  void showAboutChangelogDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF11161f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: accentColor),
            SizedBox(width: 8),
            Text("About & Changelog", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: DefaultTextStyle(
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Cooler Controller App",
                    style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Version: $kAppVersion"),
                Divider(color: Colors.white24, height: 20),
                Text("Developer", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Nama: Apri Ansyah"),
                Text("Telegram Dev: t.me/bujanginm"),
                Text("Group Telegram:"),
                Text("https://t.me/forumdiskusitele/371474"),
                Divider(color: Colors.white24, height: 20),
                Text("Tujuan Aplikasi", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text(
                    "Aplikasi ini dibuat hanya untuk tujuan edukasi/pembelajaran, mengenai cara kerja fan cooler apabila dikontrol menggunakan aplikasi."),
                Divider(color: Colors.white24, height: 20),
                Text("Status", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Aplikasi ini FREE dan TIDAK untuk diperjualbelikan."),
                Divider(color: Colors.white24, height: 20),
                Text("Changelog", style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("v1.2.1"),
                Text("- Durasi animasi splash screen diperpanjang jadi 9 detik agar lebih terasa."),
                SizedBox(height: 6),
                Text("v1.2.0"),
                Text("- Tambah animasi splash screen bergaya gaming (partikel, cincin energi, logo bercahaya)."),
                Text("- Transisi halus dari splash ke halaman utama."),
                SizedBox(height: 6),
                Text("v1.1.0"),
                Text("- Desain ulang UI, rapi & responsif di semua resolusi."),
                Text("- Tambah menu navigasi (drawer) untuk mode koneksi."),
                Text("- Tambah pilihan warna tema kustom."),
                Text("- Tambah fitur bersihkan cache aplikasi & modul ESP32."),
                Text("- Kontrol voltase kontinu 5V - 12V + preset cepat."),
                SizedBox(height: 6),
                Text("v1.0.0"),
                Text("- Rilis awal aplikasi."),
                Text("- Kontrol fan cooler via WiFi (MQTT) & Bluetooth (BLE)."),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text("Tutup", style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  // ===== DIALOG: KONFIRMASI CACHE =====
  void _confirmClear(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF11161f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: Colors.white)),
        content: Text(message, style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Batal", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            child: Text("Ya, Bersihkan"),
          ),
        ],
      ),
    );
  }

  // ===== DRAWER (MENU GARIS 3) =====
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Color(0xFF0d1219),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 28, 20, 20),
              decoration: BoxDecoration(color: Colors.black26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ac_unit, color: accentColor, size: 34),
                  SizedBox(height: 10),
                  Text("Cooler Controller",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text(status,
                      style: TextStyle(
                          fontSize: 12,
                          color: status == "🟢 Online" ? Colors.greenAccent : Colors.redAccent)),
                ],
              ),
            ),
            _drawerSectionTitle("Mode Koneksi"),
            RadioListTile<String>(
              value: "WiFi",
              groupValue: connectionMode,
              activeColor: accentColor,
              title: Row(children: [
                Icon(Icons.wifi, color: Colors.white70, size: 20),
                SizedBox(width: 10),
                Text("WiFi (MQTT)", style: TextStyle(color: Colors.white)),
              ]),
              onChanged: (mode) {
                setState(() => connectionMode = mode!);
                connectMQTT();
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              value: "Bluetooth",
              groupValue: connectionMode,
              activeColor: accentColor,
              title: Row(children: [
                Icon(Icons.bluetooth, color: Colors.white70, size: 20),
                SizedBox(width: 10),
                Text("Bluetooth (BLE)", style: TextStyle(color: Colors.white)),
              ]),
              onChanged: (mode) {
                setState(() => connectionMode = mode!);
                scanBLE();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_ethernet, color: Colors.white70),
              title: Text("Setup WiFi ESP32", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                showWiFiSetupDialog();
              },
            ),
            Divider(color: Colors.white12),
            _drawerSectionTitle("Tampilan"),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: colorPalette.map((c) {
                  bool selected = accentColor.value == c.value;
                  return GestureDetector(
                    onTap: () => setState(() => accentColor = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 3),
                      ),
                      child: selected ? Icon(Icons.check, size: 16, color: Colors.black) : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 16),
            Divider(color: Colors.white12),
            _drawerSectionTitle("Perawatan"),
            ListTile(
              leading: Icon(Icons.cleaning_services, color: Colors.white70),
              title: Text("Bersihkan Cache Aplikasi", style: TextStyle(color: Colors.white)),
              subtitle: Text("Hapus data sementara di aplikasi", style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () => _confirmClear(
                  "Bersihkan Cache Aplikasi",
                  "Data pencarian WiFi/Bluetooth sementara akan dihapus. Lanjutkan?",
                  clearAppCache),
            ),
            ListTile(
              leading: Icon(Icons.memory, color: Colors.white70),
              title: Text("Bersihkan Cache Modul ESP32", style: TextStyle(color: Colors.white)),
              subtitle:
                  Text("Kirim perintah reset cache ke modul ESP32", style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () => _confirmClear(
                  "Bersihkan Cache Modul ESP32",
                  "Perintah pembersihan cache akan dikirim ke modul ESP32 melalui koneksi $connectionMode. Lanjutkan?",
                  clearEsp32Cache),
            ),
            Divider(color: Colors.white12),
            _drawerSectionTitle("Lainnya"),
            ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white70),
              title: Text("Tentang & Changelog", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                showAboutChangelogDialog(context);
              },
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(text.toUpperCase(),
          style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
    );
  }

  // ===== UI UTAMA =====
  @override
  Widget build(BuildContext context) {
    bool online = status == "🟢 Online";
    return Scaffold(
      backgroundColor: Color(0xFF090d14),
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        titleSpacing: 4,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ac_unit, color: accentColor, size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                "COOLER CONTROLLER",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: online ? Colors.green.shade800 : Colors.red.shade800),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online ? Colors.greenAccent : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(online ? "Online" : "Offline",
                        style: TextStyle(
                            fontSize: 12, color: online ? Colors.greenAccent : Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double maxWidth = constraints.maxWidth > 520 ? 480 : constraints.maxWidth;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _modeBanner(),
                      SizedBox(height: 16),
                      _timerCard(),
                      SizedBox(height: 16),
                      _voltageDisplayCard(),
                      SizedBox(height: 20),
                      _sectionLabel("Kontrol Voltase (5V - 12V)"),
                      SizedBox(height: 10),
                      _presetList(),
                      SizedBox(height: 10),
                      _hardwareInfoCard(),
                      SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: _actionBtn('Refresh', Icons.refresh, () {
                              if (connectionMode == "WiFi") {
                                connectMQTT();
                              } else {
                                scanBLE();
                              }
                            }),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _actionBtn('Setup WiFi', Icons.wifi, showWiFiSetupDialog),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }

  Widget _modeBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(connectionMode == "WiFi" ? Icons.wifi : Icons.bluetooth, color: accentColor, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text("Mode koneksi: $connectionMode",
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Icon(Icons.menu, color: Colors.white38, size: 16),
        ],
      ),
    );
  }

  Widget _timerCard() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer, color: accentColor),
          SizedBox(width: 10),
          Text(uptime, style: TextStyle(fontSize: 26, fontFamily: 'monospace', color: Colors.white)),
        ],
      ),
    );
  }

  Widget _voltageDisplayCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text('${setVolt.toStringAsFixed(1)}V',
              style: TextStyle(fontSize: 46, fontWeight: FontWeight.bold, color: accentColor)),
          SizedBox(height: 6),
          Text('VOLTASE AKTIF', style: TextStyle(fontSize: 12, color: Colors.grey, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _presetList() {
    final presets = [
      {"v": 5.0, "c": Colors.orangeAccent},
      {"v": 9.0, "c": Colors.blueAccent},
      {"v": 12.0, "c": Colors.redAccent},
    ];
    return Column(
      children: presets.map((p) {
        double v = p["v"] as double;
        Color c = p["c"] as Color;
        bool selected = setVolt == v;
        return Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c : Colors.transparent, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, color: c),
              SizedBox(width: 12),
              Expanded(
                child: Text('${v.toStringAsFixed(0)} Volt',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              if (selected)
                Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.check_circle, color: c, size: 20),
                ),
              ElevatedButton(
                onPressed: () => sendVoltage(v),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selected ? c : c.withOpacity(0.15),
                  foregroundColor: selected ? Colors.black : c,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(selected ? "Terpilih" : "Pilih"),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _hardwareInfoCard() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.white38, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Modul step-up yang dipakai hanya mendukung 3 level tegangan tetap (5V/9V/12V), jadi pemilihan voltase dilakukan lewat 3 tombol di atas.",
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black38,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
