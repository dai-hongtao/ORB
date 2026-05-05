#pragma once

#include <Preferences.h>

#include "MCP4728Driver.h"
#include "Models.h"
#include "RegistryStore.h"

namespace orb {

class SmoothingEngine {
 public:
  void begin(MCP4728Driver& driver);
  bool load();
  bool save();

  const DeviceSmoothingProfiles& configs() const;
  SmoothingConfig configFor(ModuleType moduleType) const;
  void setConfig(ModuleType moduleType, const SmoothingConfig& config);
  void setTarget(uint8_t moduleId,
                 uint8_t channelIndex,
                 uint16_t targetCode,
                 bool previewMode = false,
                 bool suppressJitter = false);
  uint16_t currentCode(uint8_t moduleId, uint8_t channelIndex) const;
  void clearModule(uint8_t moduleId);
  void tick(const RegistryStore& registry);

 private:
  struct ChannelState {
    float currentCode = 0.0f;
    float startCode = 0.0f;
    float targetCode = 0.0f;
    uint32_t motionStartMs = 0;
    bool active = false;
    bool previewMode = false;
    bool suppressJitter = false;
    float jitterOffset = 0.0f;
    float jitterStartOffset = 0.0f;
    float jitterTargetOffset = 0.0f;
    uint32_t jitterStartMs = 0;
    uint32_t jitterDurationMs = 1;
    uint32_t nextJitterUpdateMs = 0;
  };

  static void smoothStepRadiance(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state);
  static void smoothStepBalance(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state);
  static void updateJitter(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state);

  MCP4728Driver* driver_ = nullptr;
  Preferences preferences_;
  DeviceSmoothingProfiles configs_{};
  ChannelState states_[kMaxModules][kChannelsPerModule]{};
  uint32_t lastTickMs_ = 0;
};

}  // namespace orb
