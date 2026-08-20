import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';
import 'dart:async';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cooler Controller',
      theme: ThemeData.dark(),
      home: ControllerPage(),
    );
  }
}

class ControllerPage extends StatefulWidget {
  @override
  _ControllerPageState createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  // ===== MODE KONEKSI =====
  String connectionMode = "WiFi"; // "WiFi" atau "Bluetooth"
  
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
  
  // ===== DATA =====
  double setVolt = 5.0;
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
    try { await mqttClient!.connect(); } catch (e) { setState(() => status = "🔴 Offline"); }
  }

  void sendCommandMQTT(double volt) async {
    if (mqttClient == null || !mqttClient!.connectionStatus!.connected) {
      setState(() => status = "🔴 Offline");
      return;
    }
    var builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({"voltage": volt}));
    mqttClient!.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    setState(() => setVolt = volt);
  }

  // ===== BLUETOOTH =====
  void scanBLE() async {
    setState(() { isScanning = true; scanResults.clear(); });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 5));
    FlutterBluePlus.onScanResults.listen((results) {
      setState(() {
        scanResults = results.where((r) => r.device.name.contains("ESP32")).toList();
      });
    });
    await Future.delayed(Duration(seconds: 6));
    setState(() { isScanning = false; });
  }

  Future<void> connectBLE(ScanResult result) async {
    try {
      await result.device.connect();
      setState(() {
        bleDevice = result.device;
        bleConnected = true;
        status = "🟢 Online";
      });
      // Discover services
      List<BluetoothService> services = await result.device.discoverServices();
      // Find characteristic
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            // Subscribe to notifications
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
      return;
    }
    try {
      List<BluetoothService> services = await bleDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == "beb5483e-36e1-4688-b7f5-ea07361b26a8") {
            await characteristic.write(utf8.encode(jsonEncode({"voltage": volt})));
            setState(() => setVolt = volt);
            return;
          }
        }
      }
    } catch (e) {}
  }

  // ===== WIFI SETUP =====
  Future<void> scanWiFi() async {
    setState(() { isScanningWifi = true; wifiList.clear(); });
    try {
      // ESP32 dalam mode AP, IP: 192.168.4.1
      var response = await http.get(Uri.parse("http://192.168.4.1/scanwifi")).timeout(Duration(seconds: 5));
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
      setState(() { isScanningWifi = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Pastikan HP terhubung ke ESP32-Config"))
      );
    }
  }

  Future<void> connectWiFi(String ssid, String password) async {
    try {
      var url = Uri.parse("http://192.168.4.1/setwifi?ssid=$ssid&password=$password");
      var response = await http.get(url);
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ ESP32 berhasil terhubung ke $ssid"))
        );
        Navigator.pop(context);
        // Tunggu ESP32 restart
        await Future.delayed(Duration(seconds: 5));
        connectMQTT();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Gagal terhubung, coba lagi"))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("⚠️ Pastikan HP terhubung ke ESP32-Config"))
      );
    }
  }

  void showWiFiSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.wifi, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text("Hubungkan Internet ESP32"),
              ],
            ),
            content: Container(
              width: double.maxFinite,
              height: 350,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text("📶 WiFi di sekitar", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: Icon(isScanningWifi ? Icons.refresh : Icons.refresh),
                        onPressed: () => scanWiFi(),
                      ),
                    ],
                  ),
                  Expanded(
                    child: isScanningWifi
                        ? Center(child: CircularProgressIndicator())
                        : wifiList.isEmpty
                            ? Center(child: Text("Tidak ada WiFi ditemukan\nPastikan HP terhubung ke ESP32-Config", textAlign: TextAlign.center))
                            : ListView.builder(
                                itemCount: wifiList.length,
                                itemBuilder: (ctx, index) {
                                  var wifi = wifiList[index];
                                  bool isSelected = selectedSSID == wifi['ssid'];
                                  return Card(
                                    color: isSelected ? Colors.blue.shade900 : Colors.grey.shade900,
                                    child: ListTile(
                                      leading: Icon(Icons.wifi, color: Colors.cyanAccent),
                                      title: Text(wifi['ssid'], style: TextStyle(color: Colors.white)),
                                      trailing: Text("${wifi['rssi']}dBm", style: TextStyle(color: Colors.grey)),
                                      onTap: () {
                                        setStateDialog(() { selectedSSID = wifi['ssid']; });
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                  if (selectedSSID.isNotEmpty) ...[
                    Divider(),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: "Password WiFi",
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.visibility),
                          onPressed: () {},
                        ),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (passwordController.text.isNotEmpty) {
                          connectWiFi(selectedSSID, passwordController.text);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Masukkan password!"))
                          );
                        }
                      },
                      child: Text("🔗 Hubungkan"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Tutup"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF090d14),
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.gamepad, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text("COOLER CONTROLLER"),
        ]),
        backgroundColor: Colors.black54,
        actions: [
          // Mode Selection
          Container(
            margin: EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value: connectionMode,
              dropdownColor: Colors.grey.shade900,
              style: TextStyle(color: Colors.white),
              underline: Container(),
              onChanged: (mode) {
                setState(() {
                  connectionMode = mode!;
                  if (mode == "WiFi") {
                    connectMQTT();
                  } else {
                    scanBLE();
                  }
                });
              },
              items: ["WiFi", "Bluetooth"].map((mode) {
                return DropdownMenuItem(value: mode, child: Text(mode));
              }).toList(),
            ),
          ),
          // Setup WiFi Button
          IconButton(
            icon: Icon(Icons.settings_ethernet, color: Colors.cyanAccent),
            onPressed: showWiFiSetupDialog,
          ),
          // Status
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              border: Border.all(color: status == "🟢 Online" ? Colors.green.shade800 : Colors.red.shade800),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status, style: TextStyle(fontSize: 12, color: status == "🟢 Online" ? Colors.greenAccent : Colors.redAccent)),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Timer
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer, color: Colors.cyanAccent),
                  SizedBox(width: 10),
                  Text(uptime, style: TextStyle(fontSize: 28, fontFamily: 'monospace', color: Colors.white)),
                ],
              ),
            ),
            SizedBox(height: 20),
            // Target voltase (tanpa sensor, ini cuma nampilin voltase yang di-set)
            Container(
              padding: EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Text('${setVolt.toStringAsFixed(0)}V', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                  SizedBox(height: 4),
                  Text('VOLTASE DIPILIH', style: TextStyle(fontSize: 12, color: Colors.grey, letterSpacing: 1)),
                ],
              ),
            ),
            SizedBox(height: 20),
            // Preset
            // Board decoy yang dipakai cuma support 3 voltase tetap: 5V/9V/12V
            // (bukan voltase kontinu), jadi tombol preset ini SATU-SATUNYA
            // cara pilih voltase — tidak ada slider.
            Row(children: [
              _presetBtn(5, Colors.orange),
              _presetBtn(9, Colors.blue),
              _presetBtn(12, Colors.red),
            ]),
            SizedBox(height: 20),
            Row(children: [
              _actionBtn('Refresh', Icons.refresh, () {
                if (connectionMode == "WiFi") {
                  connectMQTT();
                } else {
                  scanBLE();
                }
              }),
              SizedBox(width: 10),
              _actionBtn('Setup WiFi', Icons.wifi, showWiFiSetupDialog),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _presetBtn(int volt, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (connectionMode == "WiFi") {
            sendCommandMQTT(volt.toDouble());
          } else {
            sendCommandBLE(volt.toDouble());
          }
        },
        child: Container(
          margin: EdgeInsets.all(4),
          padding: EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: setVolt == volt ? Colors.white : Colors.transparent),
          ),
          child: Center(child: Text('$volt V', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black38,
          padding: EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
