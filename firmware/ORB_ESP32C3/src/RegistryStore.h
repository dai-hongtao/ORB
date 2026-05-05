#pragma once

#include <Preferences.h>

#include <array>

#include "Models.h"

namespace orb {

class RegistryStore {
 public:
  void begin();
  bool load();
  bool save();

  const std::array<RegistryEntry, kMaxModules>& entries() const;
  RegistryEntry* find(uint8_t id);
  const RegistryEntry* find(uint8_t id) const;

  uint8_t allocateNextFreeID() const;
  void setRegistered(uint8_t id, ModuleType type, bool registered);
  void setPresent(uint8_t id, bool present);
  void clearSlot(uint8_t id);
  void resetAllPresence();

 private:
  void seedDefaults();

  Preferences preferences_;
  std::array<RegistryEntry, kMaxModules> entries_{};
};

}  // namespace orb
