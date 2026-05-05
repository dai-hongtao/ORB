#pragma once

#include <ESPmDNS.h>

namespace orb {

class BonjourService {
 public:
  bool begin(const String& instanceName, uint16_t port);
};

}  // namespace orb
