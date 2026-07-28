// Monologue sensor node — ESP32-S3, Arduino core.
//
// Phase 1/2 reference firmware: samples one contact-mic channel off the
// AFE output, gates on simple energy-based VAD, and streams 16-bit PCM
// frames over BLE GATT notify to the Pi Zero hub. Not phase-4/5 firmware
// (no multi-channel mixing, no ADPCM/Opus, no WiFi burst path yet) — see
// docs/prototype-plan.md for what each phase actually needs.
//
// Wiring: AFE output -> GPIO4 (ADC1_CH3). Adjust ADC_PIN if the PCB rev
// lands the AFE output on a different channel.

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define ADC_PIN 4
#define SAMPLE_RATE_HZ 8000        // tissue/bone rolloff is well under 4kHz; 8kHz sampling is headroom, not a target
#define FRAME_SAMPLES 160          // 20ms frames at 8kHz
#define VAD_ENERGY_THRESHOLD 1200  // tune against real recordings in phase 1, this is a placeholder

static const char* SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char* CHAR_UUID_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

BLECharacteristic* txChar;
bool deviceConnected = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override { deviceConnected = true; }
  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    server->getAdvertising()->start();  // keep advertising after disconnect
  }
};

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetPinAttenuation(ADC_PIN, ADC_11db);  // full 0-3.3V input range

  BLEDevice::init("Monologue-Node");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);
  txChar = service->createCharacteristic(
      CHAR_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  service->start();
  server->getAdvertising()->addServiceUUID(SERVICE_UUID);
  server->getAdvertising()->start();

  Serial.println("Monologue node advertising.");
}

int16_t frame[FRAME_SAMPLES];

// Cheap energy VAD: mean absolute deviation from the DC bias over the
// frame. Replace with something better once phase-1 recordings show what
// the noise floor actually looks like — this is a placeholder gate, not
// a tuned detector.
bool frameHasSpeech(const int16_t* samples, size_t n) {
  int64_t sum = 0;
  for (size_t i = 0; i < n; i++) sum += samples[i];
  int16_t mean = sum / n;

  int64_t energy = 0;
  for (size_t i = 0; i < n; i++) {
    int32_t d = samples[i] - mean;
    energy += (d < 0) ? -d : d;
  }
  return (energy / n) > VAD_ENERGY_THRESHOLD;
}

void loop() {
  static uint32_t nextSampleUs = 0;
  static size_t idx = 0;

  uint32_t nowUs = micros();
  if (nowUs >= nextSampleUs) {
    frame[idx++] = analogRead(ADC_PIN) - 2048;  // center a 12-bit reading around 0
    nextSampleUs = nowUs + (1000000UL / SAMPLE_RATE_HZ);

    if (idx >= FRAME_SAMPLES) {
      idx = 0;
      if (deviceConnected && frameHasSpeech(frame, FRAME_SAMPLES)) {
        txChar->setValue((uint8_t*)frame, sizeof(frame));
        txChar->notify();
      }
    }
  }
}
