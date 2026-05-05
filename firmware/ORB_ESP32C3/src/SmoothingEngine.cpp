#include "SmoothingEngine.h"

#include <esp_system.h>

namespace orb {

namespace {
float clampf(float value, float lower, float upper) {
  if (value < lower) {
    return lower;
  }
  if (value > upper) {
    return upper;
  }
  return value;
}

uint16_t sanitizeSettleTimeMs(uint16_t settleTimeMs) {
  if (settleTimeMs < 50U) {
    return 50U;
  }
  if (settleTimeMs > 5000U) {
    return 5000U;
  }
  return settleTimeMs;
}

float randomUnit() {
  return static_cast<float>(esp_random()) / static_cast<float>(UINT32_MAX);
}

float randomSignedUnit() {
  return (randomUnit() * 2.0f) - 1.0f;
}

float piecewiseEase(float progress, float inPower, float outPower) {
  const float p = clampf(progress, 0.0f, 1.0f);
  if (p < 0.5f) {
    return 0.5f * powf(p * 2.0f, inPower);
  }
  return 1.0f - (0.5f * powf((1.0f - p) * 2.0f, outPower));
}

float cosineEase(float progress) {
  const float p = clampf(progress, 0.0f, 1.0f);
  return 0.5f - (0.5f * cosf(p * PI));
}

SmoothingConfig sanitizeConfig(const SmoothingConfig& input, ModuleType moduleType) {
  SmoothingConfig config = input;
  config.settleTimeMs = sanitizeSettleTimeMs(input.settleTimeMs);
  if (moduleType == ModuleType::Radiance) {
    config.aMax = clampf(input.aMax, 0.5f, 20.0f);
    config.vMax = clampf(input.vMax, 0.1f, 12.0f);
  } else {
    config.aMax = clampf(input.aMax, 0.5f, 20.0f);
    config.vMax = clampf(input.vMax, 0.1f, 12.0f);
  }
  config.jitterFrequencyHz = clampf(input.jitterFrequencyHz, 0.0f, 8.0f);
  config.jitterAmplitude = clampf(input.jitterAmplitude, 0.0f, 6.0f);
  config.jitterDispersion = clampf(input.jitterDispersion, 0.0f, 1.0f);
  return config;
}
}  // namespace

void SmoothingEngine::begin(MCP4728Driver& driver) {
  driver_ = &driver;
  preferences_.begin(kSmoothingNamespace, false);
  load();
  lastTickMs_ = millis();
}

bool SmoothingEngine::load() {
  const size_t expectedSize = sizeof(DeviceSmoothingProfiles);
  const size_t actualSize = preferences_.getBytesLength("profiles");
  if (actualSize != expectedSize) {
    configs_ = DeviceSmoothingProfiles{};
    return save();
  }

  preferences_.getBytes("profiles", &configs_, expectedSize);
  configs_.radiance = sanitizeConfig(configs_.radiance, ModuleType::Radiance);
  configs_.balance = sanitizeConfig(configs_.balance, ModuleType::Balance);
  return true;
}

bool SmoothingEngine::save() {
  DeviceSmoothingProfiles sanitized = configs_;
  sanitized.radiance = sanitizeConfig(sanitized.radiance, ModuleType::Radiance);
  sanitized.balance = sanitizeConfig(sanitized.balance, ModuleType::Balance);
  const size_t written = preferences_.putBytes("profiles", &sanitized, sizeof(DeviceSmoothingProfiles));
  return written == sizeof(DeviceSmoothingProfiles);
}

const DeviceSmoothingProfiles& SmoothingEngine::configs() const {
  return configs_;
}

SmoothingConfig SmoothingEngine::configFor(ModuleType moduleType) const {
  switch (moduleType) {
    case ModuleType::Radiance:
      return configs_.radiance;
    case ModuleType::Balance:
      return configs_.balance;
    case ModuleType::Unknown:
    default:
      return configs_.balance;
  }
}

void SmoothingEngine::setConfig(ModuleType moduleType, const SmoothingConfig& config) {
  const SmoothingConfig sanitized = sanitizeConfig(config, moduleType);

  switch (moduleType) {
    case ModuleType::Radiance:
      configs_.radiance = sanitized;
      break;
    case ModuleType::Balance:
    case ModuleType::Unknown:
    default:
      configs_.balance = sanitized;
      break;
  }

  save();
}

void SmoothingEngine::setTarget(uint8_t moduleId,
                                uint8_t channelIndex,
                                uint16_t targetCode,
                                bool previewMode,
                                bool suppressJitter) {
  if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule) {
    return;
  }

  ChannelState& state = states_[slotIndexForID(moduleId)][channelIndex];
  state.previewMode = previewMode;
  state.suppressJitter = previewMode && suppressJitter;
  state.startCode = state.currentCode;
  state.targetCode = static_cast<float>(targetCode);
  state.motionStartMs = millis();
  state.active = true;
}

uint16_t SmoothingEngine::currentCode(uint8_t moduleId, uint8_t channelIndex) const {
  if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule) {
    return 0;
  }
  return static_cast<uint16_t>(states_[slotIndexForID(moduleId)][channelIndex].currentCode);
}

void SmoothingEngine::clearModule(uint8_t moduleId) {
  if (!isValidModuleID(moduleId)) {
    return;
  }

  for (size_t channelIndex = 0; channelIndex < kChannelsPerModule; ++channelIndex) {
    ChannelState& state = states_[slotIndexForID(moduleId)][channelIndex];
    state.currentCode = 0.0f;
    state.startCode = 0.0f;
    state.targetCode = 0.0f;
    state.motionStartMs = millis();
    state.active = false;
    state.previewMode = false;
    state.suppressJitter = false;
    state.jitterOffset = 0.0f;
    state.jitterStartOffset = 0.0f;
    state.jitterTargetOffset = 0.0f;
    state.jitterStartMs = millis();
    state.jitterDurationMs = 1U;
    state.nextJitterUpdateMs = 0U;
  }
}

void SmoothingEngine::tick(const RegistryStore& registry) {
  if (driver_ == nullptr) {
    return;
  }

  const uint32_t now = millis();
  if (now - lastTickMs_ < kSmoothingTickMs) {
    return;
  }

  lastTickMs_ = now;

  for (const RegistryEntry& entry : registry.entries()) {
    if (!entry.registered || !entry.present) {
      continue;
    }

    const uint8_t address = addressForID(entry.id);
    const SmoothingConfig config = sanitizeConfig(configFor(entry.moduleType), entry.moduleType);
    for (size_t channelIndex = 0; channelIndex < kChannelsPerModule; ++channelIndex) {
      ChannelState& state = states_[slotIndexForID(entry.id)][channelIndex];
      if (entry.moduleType == ModuleType::Radiance) {
        smoothStepRadiance(now, config, state);
      } else {
        smoothStepBalance(now, config, state);
      }
      if (state.previewMode && state.suppressJitter) {
        state.jitterOffset = 0.0f;
      } else {
        updateJitter(now, config, state);
      }
      const float outputCode = clampf(state.currentCode + state.jitterOffset, 0.0f, 4095.0f);
      driver_->writeChannelCode(address, static_cast<uint8_t>(channelIndex), static_cast<uint16_t>(outputCode));
    }
  }
}

void SmoothingEngine::smoothStepRadiance(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state) {
  if (!state.active) {
    state.currentCode = state.targetCode;
    return;
  }

  const float elapsed = static_cast<float>(nowMs - state.motionStartMs);
  const float progress = clampf(elapsed / static_cast<float>(config.settleTimeMs), 0.0f, 1.0f);
  const float inPower = clampf(3.6f - (config.aMax * 0.22f), 0.6f, 4.0f);
  const float outPower = clampf(3.4f - (config.vMax * 0.22f), 0.6f, 4.0f);
  const float eased = piecewiseEase(progress, inPower, outPower);
  state.currentCode = state.startCode + ((state.targetCode - state.startCode) * eased);

  if (progress >= 1.0f) {
    state.currentCode = state.targetCode;
    state.active = false;
  }
}

void SmoothingEngine::smoothStepBalance(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state) {
  if (!state.active) {
    state.currentCode = state.targetCode;
    return;
  }

  const float elapsed = static_cast<float>(nowMs - state.motionStartMs);
  const float progress = clampf(elapsed / static_cast<float>(config.settleTimeMs), 0.0f, 1.0f);
  const float inPower = clampf(4.0f - (config.aMax * 0.16f), 0.8f, 4.6f);
  const float outPower = clampf(4.6f - (config.vMax * 0.20f), 0.8f, 5.0f);
  const float shaped = piecewiseEase(progress, inPower, outPower);
  const float eased = (shaped * 0.55f) + (cosineEase(progress) * 0.45f);
  state.currentCode = state.startCode + ((state.targetCode - state.startCode) * eased);

  if (progress >= 1.0f) {
    state.currentCode = state.targetCode;
    state.active = false;
  }
}

void SmoothingEngine::updateJitter(uint32_t nowMs, const SmoothingConfig& config, ChannelState& state) {
  if (config.jitterFrequencyHz <= 0.01f || config.jitterAmplitude <= 0.001f) {
    state.jitterOffset = 0.0f;
    state.jitterStartOffset = 0.0f;
    state.jitterTargetOffset = 0.0f;
    state.nextJitterUpdateMs = 0U;
    return;
  }

  if (state.nextJitterUpdateMs == 0U || nowMs >= state.nextJitterUpdateMs) {
    const float meanIntervalMs = 1000.0f / config.jitterFrequencyHz;
    const float scatter = meanIntervalMs * config.jitterDispersion * 0.8f;
    const uint32_t intervalMs = static_cast<uint32_t>(clampf(
        meanIntervalMs + (randomSignedUnit() * scatter),
        40.0f,
        3000.0f));
    const float baseAmplitudeCodes = 4095.0f * (config.jitterAmplitude / 100.0f);
    const float amplitudeScatter = baseAmplitudeCodes * config.jitterDispersion;
    const float sampledAmplitude = clampf(
        baseAmplitudeCodes + (randomSignedUnit() * amplitudeScatter),
        0.0f,
        4095.0f);

    state.jitterStartOffset = state.jitterOffset;
    state.jitterTargetOffset = sampledAmplitude * randomSignedUnit();
    state.jitterStartMs = nowMs;
    state.jitterDurationMs = static_cast<uint32_t>(clampf(intervalMs * 0.7f, 30.0f, 2000.0f));
    state.nextJitterUpdateMs = nowMs + intervalMs;
  }

  const float progress = clampf(
      static_cast<float>(nowMs - state.jitterStartMs) / static_cast<float>(state.jitterDurationMs),
      0.0f,
      1.0f);
  const float eased = cosineEase(progress);
  state.jitterOffset = state.jitterStartOffset + ((state.jitterTargetOffset - state.jitterStartOffset) * eased);
}

}  // namespace orb
