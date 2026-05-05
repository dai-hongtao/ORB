#include "BonjourService.h"

#include <Arduino.h>

namespace orb {

bool BonjourService::begin(const String& instanceName, uint16_t port) {
  Serial.printf("[mDNS] 启动 Bonjour，实例名=%s，端口=%u\n", instanceName.c_str(), port);
  MDNS.end();
  if (!MDNS.begin(instanceName.c_str())) {
    Serial.println("[mDNS] 启动失败");
    return false;
  }

  MDNS.setInstanceName(instanceName);
  MDNS.addService("orb", "tcp", port);
  MDNS.addServiceTxt("orb", "tcp", "device", instanceName.c_str());
  MDNS.addServiceTxt("orb", "tcp", "fw", "0.1.0");
  Serial.printf("[mDNS] 已广播 _orb._tcp.local，主机名=%s.local\n", instanceName.c_str());
  return true;
}

}  // namespace orb
