#pragma once

#include <Wire.h>

#include "Models.h"

namespace orb {

class MCP4728Driver {
 public:
  void begin(TwoWire& wire);
  bool probe(uint8_t address) const;
  bool writeChannelCode(uint8_t address, uint8_t channel, uint16_t code) const;
  bool rewriteAddress(uint8_t oldAddress, uint8_t newAddress) const;

 private:
  TwoWire* wire_ = nullptr;
};

}  // namespace orb
