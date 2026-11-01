#include "include/spring_boot_starter_flutter/spring_boot_starter_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "spring_boot_starter_flutter_plugin.h"

void SpringBootStarterFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  spring_boot_starter_flutter::SpringBootStarterFlutterPlugin::
      RegisterWithRegistrar(
          flutter::PluginRegistrarManager::GetInstance()
              ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
