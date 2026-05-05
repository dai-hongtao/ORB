#pragma once

#include <Arduino.h>
#include <array>

#include "Config.h"

namespace orb {

enum class ModuleType : uint8_t {
  Unknown = 0,
  Radiance = 1,
  Balance = 2,
};

struct RegistryEntry {
  uint8_t id = 0;
  bool registered = false;
  bool present = false;
  ModuleType moduleType = ModuleType::Unknown;
};

struct SmoothingConfig {
  uint16_t settleTimeMs = kDefaultSettleTimeMs;
  float aMax = kDefaultRadianceAMax;
  float vMax = kDefaultRadianceVMax;
  float jitterFrequencyHz = kDefaultRadianceJitterFrequencyHz;
  float jitterAmplitude = kDefaultRadianceJitterAmplitude;
  float jitterDispersion = kDefaultRadianceJitterDispersion;
};

struct DeviceSmoothingProfiles {
  SmoothingConfig radiance{
      kDefaultSettleTimeMs,
      kDefaultRadianceAMax,
      kDefaultRadianceVMax,
      kDefaultRadianceJitterFrequencyHz,
      kDefaultRadianceJitterAmplitude,
      kDefaultRadianceJitterDispersion
  };
  SmoothingConfig balance{
      kDefaultSettleTimeMs,
      kDefaultBalanceAMax,
      kDefaultBalanceVMax,
      kDefaultBalanceJitterFrequencyHz,
      kDefaultBalanceJitterAmplitude,
      kDefaultBalanceJitterDispersion
  };
};

struct CalibrationPoint {
  float input = 0.0f;
  float output = 0.0f;
};

static constexpr uint8_t kMaxLUTPoints = 11;
static constexpr size_t kMaxCalibrationLUTEntries = kMaxModules * kChannelsPerModule;

struct CalibrationLUTProfile {
  bool valid = false;
  uint8_t moduleId = 0;
  uint8_t channelIndex = 0;
  uint8_t pointCount = 0;
  uint32_t updatedAtEpoch = 0;
  std::array<CalibrationPoint, kMaxLUTPoints> points{};
};

struct ChannelTarget {
  uint8_t moduleId = 0;
  uint8_t channelIndex = 0;
  uint16_t targetCode = 0;
};

inline bool isValidModuleID(uint8_t id) {
  return id >= 1 && id <= kMaxModules;
}

inline uint8_t slotIndexForID(uint8_t id) {
  return id - 1;
}

inline uint8_t addressForID(uint8_t id) {
  if (id >= 1 && id <= 7) {
    return static_cast<uint8_t>(kUnknownModuleAddress + id);
  }
  if (id == 8) {
    return kUnknownModuleAddress;
  }
  return 0;
}

inline uint8_t idForAddress(uint8_t address) {
  if (address >= static_cast<uint8_t>(kUnknownModuleAddress + 1) &&
      address <= static_cast<uint8_t>(kUnknownModuleAddress + 7)) {
    return static_cast<uint8_t>(address - kUnknownModuleAddress);
  }
  if (address == kUnknownModuleAddress) {
    return 8;
  }
  return 0;
}

inline bool isValidModuleAddress(uint8_t address) {
  return idForAddress(address) != 0;
}

inline const char* moduleTypeName(ModuleType type) {
  switch (type) {
    case ModuleType::Radiance:
      return "radiance";
    case ModuleType::Balance:
      return "balance";
    case ModuleType::Unknown:
    default:
      return "unknown";
  }
}

}  // namespace orb
