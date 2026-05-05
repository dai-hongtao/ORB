#pragma once

#include <Preferences.h>

#include <array>

#include "Models.h"

namespace orb {

class CalibrationStore {
 public:
  void begin();
  bool load();
  bool save();

  CalibrationLUTProfile* find(uint8_t moduleId, uint8_t channelIndex);
  const CalibrationLUTProfile* find(uint8_t moduleId, uint8_t channelIndex) const;
  void upsert(uint8_t moduleId,
              uint8_t channelIndex,
              const std::array<CalibrationPoint, kMaxLUTPoints>& points,
              uint8_t pointCount,
              uint32_t updatedAtEpoch);
  void clear(uint8_t moduleId, uint8_t channelIndex);
  void clearModule(uint8_t moduleId);

  const std::array<CalibrationLUTProfile, kMaxCalibrationLUTEntries>& entries() const;

 private:
  void seedDefaults();
  size_t indexFor(uint8_t moduleId, uint8_t channelIndex) const;

  Preferences preferences_;
  std::array<CalibrationLUTProfile, kMaxCalibrationLUTEntries> entries_{};
};

}  // namespace orb
