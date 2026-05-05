#pragma once

#include <DNSServer.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>

#include "Config.h"

namespace orb {

class WiFiProvisioning {
 public:
  void begin();
  void attachRoutes(WebServer& server);
  void handleDNS();
  bool handleCaptivePortalRequest(WebServer& server);
  bool promoteStationConnectionIfNeeded();

  bool isAccessPointMode() const;
  String currentIP() const;
  String deviceName() const;

 private:
  bool connectSavedStation();
  bool loadCredentials(String& ssid, String& password);
  void saveCredentials(const String& ssid, const String& password);
  void clearCredentials();
  bool startAccessPoint();
  String buildProvisioningPage() const;
  String scanNetworksJson();
  void sendCaptivePortalRedirect(WebServer& server);

  Preferences preferences_;
  DNSServer dnsServer_;
  bool accessPointMode_ = false;
  String deviceName_ = makeDefaultDeviceName();
  String cachedScanJson_;
  uint32_t lastScanMs_ = 0;
};

}  // namespace orb
