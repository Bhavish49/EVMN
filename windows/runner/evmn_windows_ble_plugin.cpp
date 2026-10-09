#include <windows.h>
#include "evmn_windows_ble_plugin.h"
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cstdint>
#include <vector>

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Radios;
using namespace Windows::Storage::Streams;

namespace {
constexpr uint16_t kTestManufacturerId = 0xFFFF;
constexpr size_t kLegacyPacketSize = 10;
constexpr size_t kPacketSize = 24;

flutter::EncodableValue Event(std::string type, flutter::EncodableMap fields = {}) {
  fields[flutter::EncodableValue("type")] = flutter::EncodableValue(std::move(type));
  return flutter::EncodableValue(std::move(fields));
}
}  // namespace

void EvmnWindowsBlePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<EvmnWindowsBlePlugin>();
  auto* plugin_pointer = plugin.get();
  plugin->method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "evmn/ble", &flutter::StandardMethodCodec::GetInstance());
  plugin->method_channel_->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  plugin->event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "evmn/ble_events", &flutter::StandardMethodCodec::GetInstance());
  auto stream_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_pointer](const auto*, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) {
        plugin_pointer->event_sink_ = std::move(sink);
        return nullptr;
      },
      [plugin_pointer](const auto*) {
        plugin_pointer->event_sink_.reset();
        return nullptr;
      });
  plugin->event_channel_->SetStreamHandler(std::move(stream_handler));
  registrar->AddPlugin(std::move(plugin));
}

EvmnWindowsBlePlugin::EvmnWindowsBlePlugin() {
  InitializeRadioAsync();
}

winrt::fire_and_forget EvmnWindowsBlePlugin::InitializeRadioAsync() {
  try {
    const auto adapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (adapter) radio_ = co_await adapter.GetRadioAsync();
    if (radio_) co_return;
    const auto radios = co_await Radio::GetRadiosAsync();
    for (const auto& candidate : radios) {
      if (candidate.Kind() == RadioKind::Bluetooth) {
        radio_ = candidate;
        break;
      }
    }
  } catch (...) {
    radio_ = nullptr;
  }
}

EvmnWindowsBlePlugin::~EvmnWindowsBlePlugin() {
  if (voice_) {
    voice_->Release();
    voice_ = nullptr;
  }
  if (com_initialized_) CoUninitialize();
  try {
    if (watcher_ && watcher_.Status() == BluetoothLEAdvertisementWatcherStatus::Started) watcher_.Stop();
    if (publisher_ && publisher_.Status() == BluetoothLEAdvertisementPublisherStatus::Started) publisher_.Stop();
    if (watcher_ && received_token_.value) watcher_.Received(received_token_);
    if (publisher_ && publisher_status_token_.value) publisher_.StatusChanged(publisher_status_token_);
  } catch (...) {}
}

bool EvmnWindowsBlePlugin::HasBluetoothRadio() {
  try {
    return radio_ && radio_.State() != RadioState::Disabled;
  } catch (...) {}
  return false;
}

void EvmnWindowsBlePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();
  try {
    if (method == "isSupported") {
      result->Success(flutter::EncodableValue(HasBluetoothRadio()));
    } else if (method == "hasBlePermissions" || method == "requestPermissions") {
      result->Success(flutter::EncodableValue(HasBluetoothRadio()));
    } else if (method == "isBluetoothEnabled") {
      bool enabled = false;
      if (HasBluetoothRadio()) enabled = radio_.State() == RadioState::On;
      result->Success(flutter::EncodableValue(enabled));
    } else if (method == "startScan") {
      if (!HasBluetoothRadio() || radio_.State() != RadioState::On) {
        result->Error("BLUETOOTH_OFF", "Turn on Bluetooth in Windows Settings.");
        return;
      }
      if (!watcher_) {
        watcher_ = BluetoothLEAdvertisementWatcher();
        watcher_.ScanningMode(BluetoothLEScanningMode::Active);
        received_token_ = watcher_.Received({this, &EvmnWindowsBlePlugin::OnAdvertisementReceived});
      }
      seen_addresses_.clear();
      if (watcher_.Status() != BluetoothLEAdvertisementWatcherStatus::Started) watcher_.Start();
      result->Success();
    } else if (method == "stopScan") {
      if (watcher_ && watcher_.Status() == BluetoothLEAdvertisementWatcherStatus::Started) watcher_.Stop();
      seen_addresses_.clear();
      result->Success();
    } else if (method == "startAdvertising") {
      if (!HasBluetoothRadio() || radio_.State() != RadioState::On) {
        result->Error("BLUETOOTH_OFF", "Turn on Bluetooth in Windows Settings.");
        return;
      }
      const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
      const auto it = arguments ? arguments->find(flutter::EncodableValue("packet")) : flutter::EncodableMap::const_iterator{};
      if (!arguments || it == arguments->end()) {
        result->Error("BAD_PACKET", "Expected a 10-byte legacy or 24-byte EVMN packet.");
        return;
      }
      std::vector<uint8_t> bytes;
      if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& value : *list) {
          if (const auto* byte = std::get_if<int32_t>(&value)) bytes.push_back(static_cast<uint8_t>(*byte));
          else if (const auto* byte64 = std::get_if<int64_t>(&value)) bytes.push_back(static_cast<uint8_t>(*byte64));
          else { result->Error("BAD_PACKET", "Packet contains a non-integer value."); return; }
        }
      } else if (const auto* typed = std::get_if<std::vector<uint8_t>>(&it->second)) {
        bytes = *typed;
      }
      if (bytes.size() != kLegacyPacketSize && bytes.size() != kPacketSize) {
        result->Error("BAD_PACKET", "Expected a 10-byte legacy or 24-byte EVMN packet.");
        return;
      }
      if ((bytes.size() == kLegacyPacketSize && bytes[0] != 1) ||
          (bytes.size() == kPacketSize && bytes[0] != 2)) {
        result->Error("BAD_PACKET", "Unsupported EVMN packet version.");
        return;
      }
      if (!publisher_) {
        publisher_ = BluetoothLEAdvertisementPublisher();
        publisher_status_token_ = publisher_.StatusChanged(
            [this](const BluetoothLEAdvertisementPublisher&, const BluetoothLEAdvertisementPublisherStatusChangedEventArgs& args) {
              if (args.Status() == BluetoothLEAdvertisementPublisherStatus::Aborted && event_sink_) {
                flutter::EncodableMap fields{{
                    flutter::EncodableValue("message"),
                    flutter::EncodableValue("This Bluetooth adapter or driver could not start BLE advertising. Try another BLE adapter."),
                }};
                event_sink_->Success(Event("error", std::move(fields)));
              }
            });
      }
      auto data_writer = DataWriter();
      data_writer.WriteBytes(bytes);
      auto manufacturer_data = BluetoothLEManufacturerData();
      manufacturer_data.CompanyId(kTestManufacturerId);
      manufacturer_data.Data(data_writer.DetachBuffer());
      publisher_.Advertisement().ManufacturerData().Clear();
      publisher_.Advertisement().ManufacturerData().Append(manufacturer_data);
      publisher_.Start();
      result->Success();
    } else if (method == "stopAdvertising") {
      if (publisher_ && publisher_.Status() == BluetoothLEAdvertisementPublisherStatus::Started) publisher_.Stop();
      result->Success();
    } else if (method == "playAlertTone") {
      if (!Beep(660, 180) || !Beep(880, 300)) {
        result->Error("ALERT_TONE_FAILED", "Windows could not play the alert tone.");
      } else {
        result->Success();
      }
    } else if (method == "isTtsReady") {
      if (!com_initialized_) {
        const auto com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (SUCCEEDED(com_result)) com_initialized_ = true;
      }
      if (!voice_) {
        CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice,
                         reinterpret_cast<void**>(&voice_));
      }
      result->Success(flutter::EncodableValue(voice_ != nullptr));
    } else if (method == "speak") {
      const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
      const auto it = arguments ? arguments->find(flutter::EncodableValue("message")) : flutter::EncodableMap::const_iterator{};
      const auto* message = arguments && it != arguments->end() ? std::get_if<std::string>(&it->second) : nullptr;
      if (!message || message->empty()) {
        result->Error("TTS_UNAVAILABLE", "A speech message is required.");
        return;
      }
      if (!com_initialized_) {
        const auto com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (SUCCEEDED(com_result)) com_initialized_ = true;
      }
      if (!voice_) {
        CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice,
                         reinterpret_cast<void**>(&voice_));
      }
      if (!voice_) {
        result->Error("TTS_UNAVAILABLE", "No offline Windows speech voice is installed.");
        return;
      }
      const auto text = winrt::to_hstring(*message);
      const auto hr = voice_->Speak(reinterpret_cast<const wchar_t*>(text.c_str()), SPF_ASYNC, nullptr);
      if (FAILED(hr)) result->Error("TTS_FAILED", "Windows offline speech failed.");
      else result->Success();
    } else {
      result->NotImplemented();
    }
  } catch (const hresult_error& error) {
    result->Error("BLE_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("BLE_ERROR", "Windows Bluetooth operation failed.");
  }
}

void EvmnWindowsBlePlugin::OnAdvertisementReceived(
    BluetoothLEAdvertisementWatcher const&,
    BluetoothLEAdvertisementReceivedEventArgs const& args) {
  try {
    for (const auto& record : args.Advertisement().ManufacturerData()) {
      if (record.CompanyId() != kTestManufacturerId) continue;
      const auto reader = DataReader::FromBuffer(record.Data());
      const auto packet_size = reader.UnconsumedBufferLength();
      if (packet_size != kLegacyPacketSize && packet_size != kPacketSize) continue;
      std::vector<uint8_t> bytes(packet_size);
      reader.ReadBytes(bytes);
      if ((packet_size == kLegacyPacketSize && bytes[0] != 1) ||
          (packet_size == kPacketSize && bytes[0] != 2)) continue;

      if (event_sink_) {
        flutter::EncodableList packet;
        packet.reserve(bytes.size());
        for (const auto byte : bytes) packet.emplace_back(static_cast<int32_t>(byte));
        flutter::EncodableMap fields{
            {flutter::EncodableValue("packet"), flutter::EncodableValue(std::move(packet))},
            {flutter::EncodableValue("rssi"), flutter::EncodableValue(static_cast<int32_t>(args.RawSignalStrengthInDBm()))}};
        event_sink_->Success(Event("packet", std::move(fields)));
      }
      if (seen_addresses_.insert(args.BluetoothAddress()).second && event_sink_) {
        flutter::EncodableMap fields{{flutter::EncodableValue("count"), flutter::EncodableValue(static_cast<int32_t>(seen_addresses_.size()))}};
        event_sink_->Success(Event("peer", std::move(fields)));
      }
    }
  } catch (...) {}
}
