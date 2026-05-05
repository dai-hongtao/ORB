#include "RegistryStore.h"

namespace orb {

void RegistryStore::begin() {
  preferences_.begin(kRegistryNamespace, false);
  load();
}

bool RegistryStore::load() {
  const size_t expectedSize = sizeof(RegistryEntry) * entries_.size();
  const size_t actualSize = preferences_.getBytesLength("registry");

  if (actualSize != expectedSize) {
    seedDefaults();
    return save();
  }

  preferences_.getBytes("registry", entries_.data(), expectedSize);
  return true;
}

bool RegistryStore::save() {
  const size_t written = preferences_.putBytes(
      "registry", entries_.data(), sizeof(RegistryEntry) * entries_.size());
  return written == sizeof(RegistryEntry) * entries_.size();
}

const std::array<RegistryEntry, kMaxModules>& RegistryStore::entries() const {
  return entries_;
}

RegistryEntry* RegistryStore::find(uint8_t id) {
  if (!isValidModuleID(id)) {
    return nullptr;
  }
  return &entries_[slotIndexForID(id)];
}

const RegistryEntry* RegistryStore::find(uint8_t id) const {
  if (!isValidModuleID(id)) {
    return nullptr;
  }
  return &entries_[slotIndexForID(id)];
}

uint8_t RegistryStore::allocateNextFreeID() const {
  for (const RegistryEntry& entry : entries_) {
    if (!entry.registered) {
      return entry.id;
    }
  }
  return 0;
}

void RegistryStore::setRegistered(uint8_t id, ModuleType type, bool registered) {
  RegistryEntry* entry = find(id);
  if (entry == nullptr) {
    return;
  }

  entry->registered = registered;
  entry->moduleType = registered ? type : ModuleType::Unknown;
  if (!registered) {
    entry->present = false;
  }
}

void RegistryStore::setPresent(uint8_t id, bool present) {
  RegistryEntry* entry = find(id);
  if (entry == nullptr) {
    return;
  }
  entry->present = present;
}

void RegistryStore::clearSlot(uint8_t id) {
  setRegistered(id, ModuleType::Unknown, false);
}

void RegistryStore::resetAllPresence() {
  for (RegistryEntry& entry : entries_) {
    entry.present = false;
  }
}

void RegistryStore::seedDefaults() {
  for (size_t index = 0; index < entries_.size(); ++index) {
    entries_[index].id = static_cast<uint8_t>(index + 1);
    entries_[index].registered = false;
    entries_[index].present = false;
    entries_[index].moduleType = ModuleType::Unknown;
  }
}

}  // namespace orb
