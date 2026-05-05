#include "CalibrationStore.h"

namespace orb {

void CalibrationStore::begin() {
  preferences_.begin(kCalibrationNamespace, false);
  load();
}

bool CalibrationStore::load() {
  const size_t expectedSize = sizeof(CalibrationLUTProfile) * entries_.size();
  const size_t actualSize = preferences_.getBytesLength("luts");

  if (actualSize != expectedSize) {
    seedDefaults();
    return save();
  }

  preferences_.getBytes("luts", entries_.data(), expectedSize);
  return true;
}

bool CalibrationStore::save() {
  const size_t written =
      preferences_.putBytes("luts", entries_.data(), sizeof(CalibrationLUTProfile) * entries_.size());
  return written == sizeof(CalibrationLUTProfile) * entries_.size();
}

CalibrationLUTProfile* CalibrationStore::find(uint8_t moduleId, uint8_t channelIndex) {
  const size_t index = indexFor(moduleId, channelIndex);
  if (index >= entries_.size()) {
    return nullptr;
  }
  CalibrationLUTProfile& entry = entries_[index];
  return entry.valid ? &entry : nullptr;
}

const CalibrationLUTProfile* CalibrationStore::find(uint8_t moduleId, uint8_t channelIndex) const {
  const size_t index = indexFor(moduleId, channelIndex);
  if (index >= entries_.size()) {
    return nullptr;
  }
  const CalibrationLUTProfile& entry = entries_[index];
  return entry.valid ? &entry : nullptr;
}

void CalibrationStore::upsert(uint8_t moduleId,
                              uint8_t channelIndex,
                              const std::array<CalibrationPoint, kMaxLUTPoints>& points,
                              uint8_t pointCount,
                              uint32_t updatedAtEpoch) {
  const size_t index = indexFor(moduleId, channelIndex);
  if (index >= entries_.size()) {
    return;
  }

  CalibrationLUTProfile& entry = entries_[index];
  entry.valid = true;
  entry.moduleId = moduleId;
  entry.channelIndex = channelIndex;
  entry.pointCount = min<uint8_t>(pointCount, kMaxLUTPoints);
  entry.updatedAtEpoch = updatedAtEpoch;
  entry.points = points;
}

void CalibrationStore::clear(uint8_t moduleId, uint8_t channelIndex) {
  const size_t index = indexFor(moduleId, channelIndex);
  if (index >= entries_.size()) {
    return;
  }
  entries_[index] = CalibrationLUTProfile{};
}

void CalibrationStore::clearModule(uint8_t moduleId) {
  for (uint8_t channelIndex = 0; channelIndex < kChannelsPerModule; ++channelIndex) {
    clear(moduleId, channelIndex);
  }
}

const std::array<CalibrationLUTProfile, kMaxCalibrationLUTEntries>& CalibrationStore::entries() const {
  return entries_;
}

void CalibrationStore::seedDefaults() {
  for (CalibrationLUTProfile& entry : entries_) {
    entry = CalibrationLUTProfile{};
  }
}

size_t CalibrationStore::indexFor(uint8_t moduleId, uint8_t channelIndex) const {
  if (!isValidModuleID(moduleId) || channelIndex >= kChannelsPerModule) {
    return entries_.size();
  }
  return (slotIndexForID(moduleId) * kChannelsPerModule) + channelIndex;
}

}  // namespace orb
