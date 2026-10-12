import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/mesh_message.dart';
import '../core/state/app_controller.dart';

const _blue = Color(0xff1769aa);
const _red = Color(0xffc62828);

class EvmnScreen extends ConsumerWidget {
  const EvmnScreen({super.key, required this.section});
  final String section;

  static const _paths = ['/dashboard', '/network', '/profile'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final selected = _paths.indexOf('/$section');
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/evmn_logo.png',
              width: 38,
              height: 38,
              semanticLabel: 'EVMN Bluetooth road logo',
            ),
            const SizedBox(width: 10),
            const Text(
              'EVMN',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .3),
            ),
          ],
        ),
        actions: [
          if (section == 'network') IconButton(tooltip: 'History', onPressed: () => context.go('/history'), icon: const Icon(Icons.history_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(child: _page(context, ref, state, controller)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (index) => context.go(_paths[index]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching),
            selectedIcon: Icon(Icons.bluetooth),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _page(
    BuildContext context,
    WidgetRef ref,
    AppState state,
    AppController controller,
  ) {
    switch (section) {
      case 'network':
        return _networkPage(context, state, controller);
      case 'modes':
        return _modesPage(context, state, controller);
      case 'alerts':
        return _alertsPage(state);
      case 'history':
        return _historyPage(state);
      case 'settings':
        return _settingsPage(context, state, controller);
      case 'profile':
        return _profilePage(context, state, controller);
      default:
        return _dashboardPage(context, state, controller);
    }
  }

  Widget _dashboardPage(
    BuildContext context,
    AppState state,
    AppController controller,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
    children: [
      const Text(
        'Driving mode',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xff182230),
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Nearby alert handling for your vehicle.',
        style: TextStyle(color: Color(0xff667085)),
      ),
      const SizedBox(height: 24),
      Card(
        child: SwitchListTile(
          secondary: state.drivingModeStarting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(
                  Icons.directions_car_filled,
                  color: state.drivingMode ? _blue : const Color(0xff667085),
                ),
          title: const Text('Driving Mode', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(state.drivingModeStarting
              ? 'Starting Driving Mode…'
              : state.drivingMode
              ? state.vehicleType.toLowerCase() == 'ambulance' || state.role == 'Temporary Patient Transport'
                  ? 'Emergency alert is active for this vehicle'
                  : 'Listening for nearby emergency alerts'
              : state.status.startsWith('Driving Mode could not start') ||
                    state.status.startsWith('Nearby-device permission') ||
                    state.status.startsWith('Turn on Bluetooth')
                  ? state.status
                  : 'Turn on to connect to nearby vehicles'),
          value: state.drivingMode,
          onChanged: state.drivingModeStarting ? null : controller.setDrivingMode,
        ),
      ),
      const SizedBox(height: 10),
      if (state.vehicleType.toLowerCase() != 'ambulance')
        SizedBox(
          width: double.infinity,
          child: state.role == 'Temporary Patient Transport' && state.activeToken != null
              ? OutlinedButton.icon(
                  onPressed: controller.deactivateTemporaryEmergency,
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('End temporary emergency mode'),
                )
              : FilledButton.tonalIcon(
                  onPressed: state.plateNumber.isEmpty
                      ? () => context.go('/profile')
                      : controller.activateTemporaryEmergency,
                  icon: const Icon(Icons.emergency_outlined),
                  label: Text(state.plateNumber.isEmpty
                      ? 'Set up vehicle for temporary emergency'
                      : 'Temporary emergency mode'),
                ),
        ),
      const SizedBox(height: 12),
      _StatusLine(text: state.status),
    ],
  );

  Widget _networkPage(
    BuildContext context,
    AppState state,
    AppController controller,
  ) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle(
        'Bluetooth network',
        'Connect only to nearby EVMN beacons.',
      ),
      const SizedBox(height: 14),
      _readinessCard(state),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: controller.toggleScan,
              icon: Icon(state.scanning ? Icons.stop : Icons.radar),
              label: Text(state.scanning ? 'Stop scanning' : 'Start scanning'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: controller.requestPermissions,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Permissions'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _red),
        onPressed: () => controller.broadcast(EmergencyKind.ambulance),
        icon: const Icon(Icons.emergency),
        label: const Text('Send emergency alert'),
      ),
      const SizedBox(height: 9),
      OutlinedButton.icon(
        onPressed: controller.stopAdvertising,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Stop advertising'),
      ),
      const SizedBox(height: 16),
      _StatusLine(text: state.status),
      const SizedBox(height: 14),
      _SectionHeading('Network activity', onTap: () => context.go('/history')),
      const SizedBox(height: 8),
      if (state.alerts.isEmpty)
        const _EmptyCard(
          icon: Icons.bluetooth_disabled,
          text: 'No EVMN packets seen. Keep this screen open on both phones.',
        ),
      ...state.alerts.map((message) => _AlertCard(message: message)),
      const SizedBox(height: 14),
      const _PrototypeNotice(),
    ],
  );

  Widget _modesPage(
    BuildContext context,
    AppState state,
    AppController controller,
  ) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle(
        'Vehicle mode',
        'Choose how this prototype behaves on this phone.',
      ),
      const SizedBox(height: 14),
      ...[
        (
          'Normal Vehicle',
          Icons.directions_car_outlined,
          'Receive and relay nearby alerts.',
        ),
        (
          'Ambulance / Emergency Vehicle',
          Icons.emergency,
          'Simulated development role.',
        ),
        (
          'Temporary Patient Transport',
          Icons.airline_seat_flat,
          'Requires a short-lived simulator token.',
        ),
        (
          'Prototype Token Authority',
          Icons.key_outlined,
          'Local token issuer for demonstrations.',
        ),
      ].map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _ModeCard(
            title: entry.$1,
            subtitle: entry.$3,
            icon: entry.$2,
            selected: state.role == entry.$1,
            onTap: () {
              controller.setRole(entry.$1);
            },
          ),
        ),
      ),
      if (state.role == 'Temporary Patient Transport' &&
          state.activeToken != null)
        _TokenCard(
          tokenId: state.activeToken!.id,
          expiry: state.activeToken!.expiresAt.toLocal().toString(),
        ),
      if (state.role == 'Prototype Token Authority' ||
          (state.role == 'Temporary Patient Transport' &&
              state.activeToken == null))
        _TokenIssuerPanel(
          initialVehicleId: state.plateNumber,
          onIssue: controller.authorizePatientTransport,
        ),
      const SizedBox(height: 12),
      const _PrototypeNotice(),
    ],
  );

  Widget _alertsPage(AppState state) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle(
        'Emergency alerts',
        'Messages are advisory. Drive safely and follow traffic laws.',
      ),
      const SizedBox(height: 12),
      if (state.alerts.isEmpty)
        const _EmptyCard(
          icon: Icons.notifications_none,
          text: 'No alerts have arrived.',
        ),
      ...state.alerts.map(
        (message) => _AlertCard(message: message, expanded: true),
      ),
      const SizedBox(height: 14),
      const _PrototypeNotice(),
    ],
  );

  Widget _historyPage(AppState state) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle('Local history', 'Recent events saved on this phone.'),
      const SizedBox(height: 12),
      if (state.events.isEmpty)
        const _EmptyCard(
          icon: Icons.receipt_long,
          text: 'History will appear when BLE or simulator events occur.',
        ),
      ...state.events.map((event) {
        final time = DateTime.tryParse('${event['created_at']}')?.toLocal();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _blue.withValues(alpha: .08),
                child: Icon(
                  _eventIcon('${event['event_type']}'),
                  color: _blue,
                  size: 20,
                ),
              ),
              title: Text(
                '${event['event_type']}'.replaceAll('_', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
              subtitle: Text(
                '${event['details']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: time == null
                  ? null
                  : Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff667085),
                      ),
                    ),
            ),
          ),
        );
      }),
    ],
  );

  Widget _settingsPage(
    BuildContext context,
    AppState state,
    AppController controller,
  ) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle(
        'Settings',
        'Voice, permissions, and prototype details.',
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Bluetooth Low Energy'),
              subtitle: Text(
                state.bluetoothSupported
                    ? 'Supported on this device'
                    : 'Unavailable',
              ),
              trailing: Icon(
                state.bluetoothSupported
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: state.bluetoothSupported ? Colors.green : _red,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('Offline voice alerts'),
              subtitle: Text(
                state.ttsReady
                    ? 'Local Android TTS is ready'
                    : 'Install an offline voice in Android settings',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.announceTest,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Nearby-device permissions'),
              subtitle: const Text(
                'Scanning and advertising require Android permission',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.requestPermissions,
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('Local retention'),
              subtitle: Text(
                'Latest 100 history entries are shown. Database cleanup setting is not implemented yet.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const _PrototypeNotice(),
      const SizedBox(height: 12),
      _StatusLine(text: state.status),
    ],
  );

  Widget _profilePage(BuildContext context, AppState state, AppController controller) => _VehicleProfileForm(state: state, onSave: controller.saveVehicleProfile, onTemporarySetup: () => context.go('/modes'));

  IconData _eventIcon(String event) => switch (event) {
    'received' => Icons.call_received,
    'forwarded' => Icons.forward,
    'duplicate' => Icons.content_copy,
    'rejected' => Icons.block,
    'token_issued' => Icons.key,
    _ => Icons.info_outline,
  };

  Widget _readinessCard(AppState state) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: state.bluetoothSupported && state.bluetoothEnabled
          ? const Color(0xffeaf5ff)
          : const Color(0xfffff1f0),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            state.bluetoothSupported && state.bluetoothEnabled
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: state.bluetoothSupported && state.bluetoothEnabled
                ? _blue
                : _red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  !state.bleRuntime
                      ? 'Android or Windows required'
                    : !state.bluetoothSupported
                    ? 'Bluetooth unavailable'
                    : !state.bluetoothPermissionsGranted
                    ? 'Nearby permission needed'
                    : state.bluetoothEnabled
                    ? 'Bluetooth ready'
                    : 'Bluetooth is turned off',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                state.status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xff667085)),
              ),
            ],
          ),
        ),
        Icon(
          state.bluetoothSupported && state.bluetoothEnabled
              ? Icons.circle
              : Icons.error,
          color: state.bluetoothSupported && state.bluetoothEnabled
              ? const Color(0xff1b9a67)
              : _red,
          size: 10,
        ),
      ],
    ),
  );

  Widget _statCard(IconData icon, String label, String value, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(color: Color(0xff667085), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

class _VehicleProfileForm extends StatefulWidget {
  const _VehicleProfileForm({required this.state, required this.onSave, required this.onTemporarySetup});
  final AppState state;
  final Future<void> Function({required String type, required String color, required String plate}) onSave;
  final VoidCallback onTemporarySetup;

  @override
  State<_VehicleProfileForm> createState() => _VehicleProfileFormState();
}

class _VehicleProfileFormState extends State<_VehicleProfileForm> {
  static const _types = ['Sedan', 'Hatchback', 'SUV', 'Van', 'Truck', 'Bus', 'Motorcycle', 'Ambulance', 'Other'];
  late final TextEditingController _plate;
  late String _type;
  late String _color;

  @override
  void initState() {
    super.initState();
    _color = MeshMessage.vehicleColors.contains(widget.state.vehicleColor)
        ? widget.state.vehicleColor
        : 'Other';
    _plate = TextEditingController(text: widget.state.plateNumber);
    _type = _types.contains(widget.state.vehicleType) ? widget.state.vehicleType : 'Other';
  }

  @override
  void dispose() { _plate.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const _PageTitle('Vehicle profile', 'Add details so you can identify your vehicle.'),
      const SizedBox(height: 18),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Vehicle type', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car_outlined)), items: _types.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(), onChanged: (value) { if (value != null) setState(() => _type = value); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _color, decoration: const InputDecoration(labelText: 'Vehicle colour', border: OutlineInputBorder(), prefixIcon: Icon(Icons.palette_outlined)), items: MeshMessage.vehicleColors.map((color) => DropdownMenuItem(value: color, child: Text(color == 'Other' ? 'Not specified / Other' : color))).toList(), onChanged: (value) { if (value != null) setState(() => _color = value); }),
        const SizedBox(height: 12),
        TextField(controller: _plate, textCapitalization: TextCapitalization.characters, maxLength: 13, decoration: const InputDecoration(labelText: 'Number plate', hintText: 'e.g. KA 01 AB 1234', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_outlined))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () async { await widget.onSave(type: _type, color: _color, plate: _plate.text); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle profile saved.'))); }, icon: const Icon(Icons.save_outlined), label: const Text('Save vehicle profile'))),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: widget.onTemporarySetup, icon: const Icon(Icons.emergency_outlined), label: const Text('Use as emergency vehicle temporarily'))),
        ]))),
      const SizedBox(height: 14),
      const Text('Your profile stays on this device. Nearby alerts use the existing compact BLE message format.', style: TextStyle(color: Color(0xff667085), height: 1.4)),
    ],
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: Color(0xff182230),
        ),
      ),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(color: Color(0xff667085))),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.onTap});
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      if (onTap != null)
        TextButton(onPressed: onTap, child: const Text('View all')),
    ],
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = _blue,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 11),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xff667085), fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: selected
            ? _blue.withValues(alpha: .1)
            : const Color(0xfff2f4f7),
        child: Icon(icon, color: selected ? _blue : const Color(0xff667085)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_circle, color: _blue)
          : const Icon(Icons.chevron_right),
    ),
  );
}

class _TokenIssuerPanel extends StatefulWidget {
  const _TokenIssuerPanel({required this.onIssue, this.initialVehicleId = ''});
  final Future<bool> Function(String) onIssue;
  final String initialVehicleId;
  @override
  State<_TokenIssuerPanel> createState() => _TokenIssuerPanelState();
}

class _TokenIssuerPanelState extends State<_TokenIssuerPanel> {
  late final TextEditingController _vehicle;
  @override
  void initState() {
    super.initState();
    _vehicle = TextEditingController(text: widget.initialVehicleId);
  }
  @override
  void dispose() {
    _vehicle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Issue a temporary development token',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vehicle,
            decoration: const InputDecoration(
              labelText: 'Vehicle identifier',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.directions_car_outlined),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              final ok = await widget.onIssue(_vehicle.text);
              if (context.mounted && ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Temporary signed simulator token issued and verified.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.key),
            label: const Text('Issue and verify 15-minute token'),
          ),
        ],
      ),
    ),
  );
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({required this.tokenId, required this.expiry});
  final String tokenId, expiry;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xffeffaf4),
    child: ListTile(
      leading: const Icon(Icons.verified_user, color: Color(0xff16805d)),
      title: const Text('Simulator token verified'),
      subtitle: Text('Token $tokenId\nExpires $expiry'),
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.message, this.expanded = false});
  final MeshMessage message;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final ambulance = message.kind == EmergencyKind.ambulance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: ListTile(
          isThreeLine: expanded,
          leading: CircleAvatar(
            backgroundColor: _red.withValues(alpha: .1),
            child: Icon(
              ambulance ? Icons.emergency : Icons.airline_seat_flat,
              color: _red,
            ),
          ),
          title: Text(
            ambulance
                ? 'Simulated emergency vehicle alert'
                : 'Patient transport alert',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              if (message.vehicleColor.isNotEmpty && message.vehicleColor != 'Other') message.vehicleColor,
              if (message.plateNumber.isNotEmpty) message.plateNumber,
              expanded
                  ? 'Message ${message.id}\nHop ${message.hopCount} · TTL ${message.ttl} · Expires ${message.expiresAt.toLocal()}'
                  : 'Hop ${message.hopCount} · TTL ${message.ttl} · ${message.id.substring(0, 8)}',
            ].join(' · '),
          ),
          trailing: const Icon(Icons.campaign_outlined, color: _blue),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff98a2b3)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Color(0xff667085))),
          ),
        ],
      ),
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: _blue, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xff475467)),
          ),
        ),
      ],
    ),
  );
}

class _PrototypeNotice extends StatelessWidget {
  const _PrototypeNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xfffff8e7),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xffffe7ab)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: Color(0xff9a6700)),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Academic prototype. Simulated roles do not provide legal traffic priority. Use alerts as advisory information and drive safely.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xff694d00),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
