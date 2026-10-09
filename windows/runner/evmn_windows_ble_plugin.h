#ifndef RUNNER_EVMN_WINDOWS_BLE_PLUGIN_H_
#define RUNNER_EVMN_WINDOWS_BLE_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <sapi.h>

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Radios.h>

#include <memory>
#include <set>
#include <string>

class EvmnWindowsBlePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  EvmnWindowsBlePlugin();
  ~EvmnWindowsBlePlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  winrt::fire_and_forget InitializeRadioAsync();
  void OnAdvertisementReceived(
      winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher const&,
      winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs const& args);
  bool HasBluetoothRadio();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementPublisher publisher_{nullptr};
  winrt::Windows::Devices::Radios::Radio radio_{nullptr};
  winrt::event_token received_token_{};
  winrt::event_token publisher_status_token_{};
  std::set<uint64_t> seen_addresses_;
  ISpVoice* voice_{nullptr};
  bool com_initialized_{false};
};

#endif
