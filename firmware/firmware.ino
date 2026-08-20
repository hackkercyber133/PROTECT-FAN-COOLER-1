#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ===================================================================
// Board: ESP32-C3 Super Mini
// Pin layout papan (kiri atas -> bawah): 5V, G, 3.3, 4, 3, 2, 1, 0
// Pin layout papan (kanan atas -> bawah): 5, 6, 7, 8, 9, 10, 20, 21
// GPIO 2, 8, 9 SENGAJA TIDAK DIPAKAI:
//   - GPIO9 = tombol BOOT onboard (strapping pin, jangan dipakai)
//   - GPIO8 = LED onboard
//   - GPIO2 = strapping pin
// ===================================================================

// ===== KONFIGURASI =====
const char* ap_ssid = "ESP32-Config";
const char* ap_password = "12345678";
const char* mqtt_server = "broker.emqx.io";
const int mqtt_port = 1883;
const char* command_topic = "cooler/command";
const char* status_topic = "cooler/status";

// ===== PIN DECOY BOARD (PD3.1 QC3.0 Trigger, output "A") =====
// Pad "1" di board decoy -> pilih 9V saat dihubungkan ke GND
// Pad "2" di board decoy -> pilih 12V saat dihubungkan ke GND
// Tidak ada pad yang disolder = default 5V (jangan sambungkan pad 3 & 4)
#define PIN_SEL_9V  6
#define PIN_SEL_12V 7

Preferences preferences;
WebServer server(80);
WiFiClient espClient;
PubSubClient mqttClient(espClient);

float currentSetVoltage = 5.0;
unsigned long startMillis = 0;
unsigned long lastPublish = 0;

// ===== BLE =====
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
String bleCommand = "";

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) { deviceConnected = true; }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    // Lanjut advertise lagi supaya app bisa reconnect
    pServer->getAdvertising()->start();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue().c_str();
    if (value.length() > 0) bleCommand = value;
  }
};

// ===== FUNGSI SET VOLTASE (khusus board decoy 1-pad-select) =====
// Board ini BUKAN CH224K biner (CFG1/2/3 kombinasi). Board ini cuma
// boleh 1 pad aktif (LOW) dalam satu waktu, sisanya HARUS floating.
void applyVoltage(float volt) {
  // Snap ke nilai terdekat yang benar-benar disupport hardware: 5 / 9 / 12
  if (volt >= 10.5) volt = 12.0;
  else if (volt >= 7.0) volt = 9.0;
  else volt = 5.0;

  // Lepas semua pin dulu (floating = tidak menyolder pad apapun = default 5V)
  pinMode(PIN_SEL_9V, INPUT);
  pinMode(PIN_SEL_12V, INPUT);

  if (volt == 9.0) {
    pinMode(PIN_SEL_9V, OUTPUT);
    digitalWrite(PIN_SEL_9V, LOW);
  } else if (volt == 12.0) {
    pinMode(PIN_SEL_12V, OUTPUT);
    digitalWrite(PIN_SEL_12V, LOW);
  }
  // volt == 5.0 -> kedua pin dibiarkan floating (INPUT), tidak ada yang disolder

  currentSetVoltage = volt;
}

// ===== MQTT CALLBACK =====
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, msg)) return;
  if (doc.containsKey("voltage")) applyVoltage(doc["voltage"]);
}

// ===== REKONEKSI MQTT (non-blocking, tidak nge-freeze BLE/HTTP) =====
unsigned long lastMqttAttempt = 0;
void reconnectMQTTNonBlocking() {
  if (mqttClient.connected()) return;
  if (millis() - lastMqttAttempt < 5000) return;
  lastMqttAttempt = millis();
  if (mqttClient.connect("ESP32Cooler")) {
    mqttClient.subscribe(command_topic);
  }
}

// ===== PUBLISH STATUS =====
void publishStatus() {
  unsigned long runtime = millis() - startMillis;
  long s = runtime / 1000, m = s / 60, h = m / 60;
  String uptime = String(h) + ":" + String(m % 60) + ":" + String(s % 60);

  StaticJsonDocument<256> doc;
  doc["setVoltage"] = currentSetVoltage;
  doc["uptime"] = uptime;
  String jsonStr;
  serializeJson(doc, jsonStr);

  if (mqttClient.connected()) {
    mqttClient.publish(status_topic, jsonStr.c_str());
  }
  if (deviceConnected) {
    pCharacteristic->setValue(jsonStr.c_str());
    pCharacteristic->notify();
  }
}

// ===== API: SET WiFi =====
void handleSetWiFi() {
  if (server.hasArg("ssid") && server.hasArg("password")) {
    String ssid = server.arg("ssid");
    String pass = server.arg("password");
    preferences.begin("wifi", false);
    preferences.putString("ssid", ssid);
    preferences.putString("pass", pass);
    preferences.end();
    server.send(200, "text/plain", "OK");
    delay(1000);
    ESP.restart();
  } else {
    server.send(400, "text/plain", "Missing ssid or password");
  }
}

// ===== HALAMAN KONFIGURASI WiFi =====
void handleRootConfig() {
  String html = "<html><head><meta name='viewport' content='width=device-width'><title>WiFi Setup</title>"
                "<style>body{background:#0b0e14;color:#fff;font-family:sans-serif;text-align:center;padding:40px 20px;}"
                "input,button{padding:14px;width:80%;margin:10px;border-radius:12px;border:none;font-size:16px;}"
                "button{background:#00e5ff;color:#000;font-weight:bold;}</style></head>"
                "<body><h2>⚙️ Set WiFi</h2><form action='/setwifi' method='GET'>"
                "<input name='ssid' placeholder='Nama WiFi' required><br>"
                "<input name='password' type='password' placeholder='Password' required><br>"
                "<button type='submit'>Simpan & Restart</button></form></body></html>";
  server.send(200, "text/html", html);
}

// ===== API: Scan WiFi =====
void handleScanWiFi() {
  String json = "[";
  int n = WiFi.scanComplete();
  if (n == -2) {
    WiFi.scanNetworks(true);
    json = "{\"status\":\"scanning\"}";
  } else if (n == -1) {
    json = "{\"status\":\"error\"}";
  } else if (n > 0) {
    for (int i = 0; i < n; ++i) {
      if (i) json += ",";
      json += "{\"ssid\":\"" + WiFi.SSID(i) + "\",\"rssi\":" + String(WiFi.RSSI(i)) + "}";
    }
    WiFi.scanDelete();
  }
  json += "]";
  server.send(200, "application/json", json);
}

// ===== API: SET VOLTAGE via HTTP (fallback saat AP mode) =====
void handleSetVoltageHttp() {
  if (server.hasArg("voltage")) {
    applyVoltage(server.arg("voltage").toFloat());
    server.send(200, "application/json", "{\"status\":\"ok\",\"setVoltage\":" + String(currentSetVoltage) + "}");
  } else {
    server.send(400, "text/plain", "Missing voltage");
  }
}

// ===== SETUP =====
void setup() {
  Serial.begin(115200);

  // Voltage select pins: default floating (5V), belum ada yang disolder ke GND
  pinMode(PIN_SEL_9V, INPUT);
  pinMode(PIN_SEL_12V, INPUT);
  applyVoltage(5.0);

  // ===== BACA WIFI TERSIMPAN =====
  preferences.begin("wifi", false);
  String savedSSID = preferences.getString("ssid", "");
  String savedPass = preferences.getString("pass", "");
  preferences.end();

  // ===== START BLE =====
  BLEDevice::init("ESP32-Cooler");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pService->start();
  pServer->getAdvertising()->start();
  Serial.println("BLE siap!");

  // ===== HTTP endpoints (dipakai baik di AP mode maupun WiFi mode) =====
  server.on("/", handleRootConfig);
  server.on("/setwifi", handleSetWiFi);
  server.on("/scanwifi", handleScanWiFi);
  server.on("/api/set", handleSetVoltageHttp);
  server.begin();

  // ===== COBA KONEK WIFI =====
  if (savedSSID != "") {
    WiFi.mode(WIFI_STA);
    WiFi.begin(savedSSID.c_str(), savedPass.c_str());
    int tries = 0;
    while (WiFi.status() != WL_CONNECTED && tries < 20) {
      delay(500);
      Serial.print(".");
      tries++;
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWiFi terhubung! IP: " + WiFi.localIP().toString());
      mqttClient.setServer(mqtt_server, mqtt_port);
      mqttClient.setCallback(mqttCallback);
      startMillis = millis();
      return;
    }
  }

  // ===== JIKA GAGAL -> AP MODE =====
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap_ssid, ap_password);
  Serial.println("AP Mode aktif: " + String(ap_ssid) + " IP: 192.168.4.1");
  startMillis = millis();
}

void loop() {
  // ===== Proses Perintah BLE =====
  if (bleCommand.length() > 0) {
    StaticJsonDocument<128> doc;
    if (!deserializeJson(doc, bleCommand)) {
      if (doc.containsKey("voltage")) applyVoltage(doc["voltage"]);
    }
    bleCommand = "";
  }

  server.handleClient();

  // ===== Mode WiFi: MQTT =====
  if (WiFi.status() == WL_CONNECTED) {
    reconnectMQTTNonBlocking();
    mqttClient.loop();
  }

  // ===== Publish status berkala (WiFi & BLE) =====
  if (millis() - lastPublish > 3000) {
    publishStatus();
    lastPublish = millis();
  }

  delay(10);
}

