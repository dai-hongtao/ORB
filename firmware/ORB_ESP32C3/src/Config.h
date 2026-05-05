#pragma once

#include <Arduino.h>

namespace orb {

static constexpr uint8_t kPinI2CSDA = 8;
static constexpr uint8_t kPinI2CSCL = 9;
static constexpr uint8_t kPinMcpLdac = 10;

static constexpr uint32_t kI2CFrequencyHz = 100000;
static constexpr uint16_t kWebPort = 80;
static constexpr uint16_t kHeartbeatPort = 43981;
static constexpr size_t kMaxModules = 8;
static constexpr size_t kChannelsPerModule = 2;
static constexpr uint8_t kUnknownModuleAddress = 0x60;

static constexpr uint32_t kPresenceScanIntervalMs = 1000;
static constexpr uint32_t kSmoothingTickMs = 10;
static constexpr uint32_t kHeartbeatIntervalMs = 1500;
static constexpr char kFirmwareVersion[] = "0.1.0";
static constexpr uint16_t kDefaultSettleTimeMs = 250;
static constexpr float kDefaultRadianceAMax = 7.1f;
static constexpr float kDefaultRadianceVMax = 2.6f;
static constexpr float kDefaultBalanceAMax = 8.0f;
static constexpr float kDefaultBalanceVMax = 5.8f;
static constexpr float kDefaultRadianceJitterFrequencyHz = 2.5f;
static constexpr float kDefaultRadianceJitterAmplitude = 0.8f;
static constexpr float kDefaultRadianceJitterDispersion = 0.32f;
static constexpr float kDefaultBalanceJitterFrequencyHz = 0.0f;
static constexpr float kDefaultBalanceJitterAmplitude = 0.0f;
static constexpr float kDefaultBalanceJitterDispersion = 0.25f;
static constexpr uint32_t kWiFiConnectTimeoutMs = 15000;

static constexpr char kAccessPointSSID[] = "ORB-SETUP";
static constexpr uint8_t kAccessPointChannel = 1;
static constexpr char kRegistryNamespace[] = "orb-reg";
static constexpr char kWiFiNamespace[] = "orb-wifi";
static constexpr char kSmoothingNamespace[] = "orb-smooth";
static constexpr char kCalibrationNamespace[] = "orb-lut";

inline String makeDefaultDeviceName() {
  uint64_t mac = ESP.getEfuseMac();
  char buffer[16];
  snprintf(buffer, sizeof(buffer), "ORB-%04X", static_cast<unsigned>(mac & 0xFFFF));
  return String(buffer);
}

}  // namespace orb
