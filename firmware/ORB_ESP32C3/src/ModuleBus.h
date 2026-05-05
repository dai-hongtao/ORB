#pragma once

#include <Wire.h>

#include "Models.h"
#include "RegistryStore.h"

namespace orb {

class ModuleBus {
 public:
  void begin(TwoWire& wire);
  void refreshPresence(RegistryStore& registry);
  bool unknownCandidatePresent(const RegistryStore& registry) const;
  bool isAddressPresent(uint8_t address) const;
  uint8_t detectedAddressMask() const;

 private:
  uint8_t scanDetectedAddressMask() const;
  bool probeAddress(uint8_t address) const;

  TwoWire* wire_ = nullptr;
  uint8_t detectedAddressMask_ = 0;
};

}  // namespace orb
