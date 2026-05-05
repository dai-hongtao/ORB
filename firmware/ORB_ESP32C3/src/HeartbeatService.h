#pragma once

#include <WiFiUdp.h>

#include "Config.h"
#include "RegistryStore.h"
#include "WiFiProvisioning.h"

namespace orb {

class HeartbeatService {
 public:
  void begin();
  void handle(const WiFiProvisioning& provisioning, const RegistryStore& registry);
  void markStateChanged();
  void configureTargetPort(uint16_t port);

  uint32_t stateRevision() const;
  uint32_t intervalMs() const;
  uint16_t defaultPort() const;
  uint16_t targetPort() const;
  bool configuredPort() const;
  const char* delivery() const;

 private:
  String buildPayload(const WiFiProvisioning& provisioning, const RegistryStore& registry) const;
  static IPAddress broadcastAddress();

  WiFiUDP udp_;
  uint32_t lastHeartbeatMs_ = 0;
  uint32_t sequence_ = 0;
  uint32_t stateRevision_ = 1;
  uint16_t targetPort_ = kHeartbeatPort;
  bool configuredPort_ = false;
};

}  // namespace orb
