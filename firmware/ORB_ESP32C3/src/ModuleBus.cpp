#include "ModuleBus.h"

namespace orb {

namespace {
String detectedAddressesLabel(uint8_t mask) {
  String label;

  for (uint8_t bit = 0; bit < kMaxModules; ++bit) {
    if ((mask & (1 << bit)) == 0) {
      continue;
    }

    if (!label.isEmpty()) {
      label += F(", ");
    }

    char buffer[8];
    snprintf(buffer, sizeof(buffer), "0x%02X", kUnknownModuleAddress + bit);
    label += buffer;
  }

  return label.isEmpty() ? String(F("无")) : label;
}
}  // namespace

void ModuleBus::begin(TwoWire& wire) {
  wire_ = &wire;
}

void ModuleBus::refreshPresence(RegistryStore& registry) {
  detectedAddressMask_ = scanDetectedAddressMask();
  Serial.printf("[I2C] 当前探测结果：%s\n", detectedAddressesLabel(detectedAddressMask_).c_str());
  registry.resetAllPresence();

  for (const RegistryEntry& entry : registry.entries()) {
    if (!entry.registered) {
      continue;
    }
    registry.setPresent(entry.id, isAddressPresent(addressForID(entry.id)));
  }
}

bool ModuleBus::unknownCandidatePresent(const RegistryStore& registry) const {
  const RegistryEntry* slot8 = registry.find(8);
  if (slot8 != nullptr && slot8->registered) {
    return false;
  }
  return isAddressPresent(kUnknownModuleAddress);
}

bool ModuleBus::isAddressPresent(uint8_t address) const {
  if (!isValidModuleAddress(address)) {
    return false;
  }

  return (detectedAddressMask_ & (1 << (address - kUnknownModuleAddress))) != 0;
}

uint8_t ModuleBus::detectedAddressMask() const {
  return detectedAddressMask_;
}

uint8_t ModuleBus::scanDetectedAddressMask() const {
  uint8_t mask = 0;

  for (uint8_t bit = 0; bit < kMaxModules; ++bit) {
    const uint8_t address = static_cast<uint8_t>(kUnknownModuleAddress + bit);
    if (probeAddress(address)) {
      mask |= static_cast<uint8_t>(1 << bit);
    }
  }

  return mask;
}

bool ModuleBus::probeAddress(uint8_t address) const {
  if (wire_ == nullptr || address == 0) {
    return false;
  }

  wire_->beginTransmission(address);
  return wire_->endTransmission(true) == 0;
}

}  // namespace orb
