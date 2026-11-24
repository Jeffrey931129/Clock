import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'updater.dart';

const _fontFamily = 'StoryScript';
const _textColor = Color(0xFFBDBDBD);
const _tileColor = Color(0xFF111111);
const _dimColor = Color(0xFF444444);
const _batteryImagePixels = 150.0;
const _timeZoneKey = 'time_zone';
const _localTimeZone = 'local';
const _clockPage = 0;
const _micAddressKey = 'mic_address';
const _micDefaultPort = 7700;
const _micOff = 'off';
const _micStreaming = 'streaming';
const _micChannel = MethodChannel('com.jeffrey.clock/mic');
const _micStatusChannel = EventChannel('com.jeffrey.clock/mic_status');

TextStyle _textStyle(double fontSize, [Color color = _textColor]) {
  return TextStyle(
    inherit: false,
    color: color,
    fontFamily: _fontFamily,
    fontSize: fontSize,
    letterSpacing: 0.5,
    textBaseline: TextBaseline.alphabetic,
  );
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _two(int v) => v.toString().padLeft(2, '0');

String _formatOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return 'UTC$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

DateTime _timeIn(DateTime now, tz.Location? location) {
  return location == null ? now : tz.TZDateTime.from(now, location);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  try {
    await WakelockPlus.enable();
  } catch (_) {}
  runApp(const ClockApp());
}

class ClockApp extends StatelessWidget {
  const ClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.lightBlue,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _timeZonesLoaded = false;

  final PageController _pageController = PageController(
    initialPage: _clockPage,
  );
  DateTime _now = DateTime.now();
  int _page = _clockPage;
  tz.Location? _location;
  String _version = '';
  String _micAddress = '';
  String _micStatus = _micOff;
  Timer? _tickTimer;
  StreamSubscription<dynamic>? _micSub;

  @override
  void initState() {
    super.initState();
    if (!_timeZonesLoaded) {
      tzdata.initializeTimeZones();
      _timeZonesLoaded = true;
    }
    _scheduleTick();
    _loadTimeZone();
    _loadVersion();
    _initMic();
    _autoCheckUpdate();
  }

  Future<void> _autoCheckUpdate() async {
    try {
      final result = await checkForUpdate();
      if (result.update != null && mounted) {
        await showUpdateDialog(context, result.update!);
      }
    } catch (_) {}
  }

  Future<void> _initMic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString(_micAddressKey) ?? '';
      if (mounted) setState(() => _micAddress = address);
    } catch (_) {}
    try {
      await _micChannel.invokeMethod('stop');
      _micSub = _micStatusChannel.receiveBroadcastStream().listen((status) {
        if (mounted && status is String) setState(() => _micStatus = status);
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _setMicAddress(String address) async {
    setState(() => _micAddress = address);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_micAddressKey, address);
    } catch (_) {}
    if (_micStatus != _micOff) await _setMicEnabled(true);
  }

  Future<bool> _setMicEnabled(bool enabled) async {
    try {
      if (!enabled) {
        await _micChannel.invokeMethod('stop');
        return true;
      }
      final target = _parseAddress(_micAddress);
      if (target == null) return false;
      final ok = await _micChannel.invokeMethod<bool>('start', {
        'host': target.$1,
        'port': target.$2,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
      });
    } catch (_) {}
  }

  void _scheduleTick() {
    final remainder = DateTime.now().millisecondsSinceEpoch % 1000;
    final wait = remainder < 500 ? 500 - remainder : 1000 - remainder;
    _tickTimer = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  Future<void> _loadTimeZone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_timeZoneKey);
      if (name == null || !mounted) return;
      setState(() {
        _location = name == _localTimeZone ? null : tz.getLocation(name);
      });
    } catch (_) {}
  }

  Future<void> _selectTimeZone(tz.Location? location) async {
    setState(() => _location = location);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_timeZoneKey, location?.name ?? _localTimeZone);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _micSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              ClockScreen(time: _timeIn(_now, _location)),
              SettingsPage(
                now: _now,
                selected: _location,
                version: _version,
                onSelected: _selectTimeZone,
                micAddress: _micAddress,
                micStatus: _micStatus,
                onMicAddress: _setMicAddress,
                onMicEnabled: _setMicEnabled,
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: PageDots(count: 2, current: _page),
          ),
        ],
      ),
    );
  }
}

class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == current ? _textColor : _dimColor,
            ),
          ),
      ],
    );
  }
}

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key, required this.time});

  final DateTime time;

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with AutomaticKeepAliveClientMixin {
  final Battery _battery = Battery();
  int _percent = 100;
  bool _charging = false;
  Timer? _batteryTimer;
  StreamSubscription<BatteryState>? _batterySub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initBattery();
  }

  Future<void> _initBattery() async {
    try {
      _batterySub = _battery.onBatteryStateChanged.listen(
        _updateBattery,
        onError: (_) {},
      );
      _batteryTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshBattery(),
      );
      await _refreshBattery();
    } catch (_) {}
  }

  Future<void> _refreshBattery() async {
    try {
      await _updateBattery(await _battery.batteryState);
    } catch (_) {}
  }

  Future<void> _updateBattery(BatteryState state) async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted) return;
      setState(() {
        _percent = level;
        _charging =
            state == BatteryState.charging || state == BatteryState.full;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _batterySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final time = widget.time;
    final hh = _two(time.hour);
    final mm = _two(time.minute);
    final ss = _two(time.second);
    final dateStr =
        '${time.year} / ${_two(time.month)} / ${_two(time.day)}    '
        '${_weekdays[time.weekday - 1]}';

    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Stack(
          children: [
            Positioned.fill(
              top: 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileHeight = constraints.maxHeight * 0.8;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: DigitTile(height: tileHeight, text: hh),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        child: DigitTile(
                          height: tileHeight,
                          text: mm,
                          bottomRight: ss,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Text(dateStr, style: _textStyle(40)),
            ),
            Positioned(
              top: 8,
              right: 0,
              child: BatteryBadge(percent: _percent, charging: _charging),
            ),
          ],
        ),
      ),
    );
  }
}

(String, int)? _parseAddress(String address) {
  final value = address.trim();
  if (value.isEmpty) return null;
  final index = value.lastIndexOf(':');
  if (index < 0) return (value, _micDefaultPort);
  final port = int.tryParse(value.substring(index + 1));
  final host = value.substring(0, index);
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return (host, port);
}

String _micStatusLabel(String status, String address) {
  final target = _parseAddress(address);
  final where = target == null ? '' : '${target.$1}:${target.$2}';
  return switch (status) {
    _micOff => 'Off',
    _micStreaming => 'Streaming to $where',
    _ => 'Connecting to $where',
  };
}

const _zoneNames = {
  'Asia/Taipei': 'Taiwan',
  'Asia/Tokyo': 'Japan',
  'Asia/Seoul': 'South Korea',
  'Asia/Shanghai': 'China',
  'Asia/Hong_Kong': 'Hong Kong',
  'Asia/Singapore': 'Singapore',
  'Asia/Bangkok': 'Thailand',
  'Asia/Kolkata': 'India',
  'Asia/Dubai': 'UAE',
  'Europe/London': 'United Kingdom',
  'Europe/Paris': 'France',
  'Europe/Berlin': 'Germany',
  'Europe/Moscow': 'Russia',
  'America/New_York': 'US Eastern',
  'America/Chicago': 'US Central',
  'America/Denver': 'US Mountain',
  'America/Los_Angeles': 'US Pacific',
  'America/Toronto': 'Canada',
  'America/Sao_Paulo': 'Brazil',
  'Australia/Sydney': 'Australia',
  'Pacific/Auckland': 'New Zealand',
};

String _zoneLabel(tz.Location? location) {
  if (location == null) return 'Local';
  return _zoneNames[location.name] ?? location.name.replaceAll('_', ' ');
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.now,
    required this.selected,
    required this.version,
    required this.onSelected,
    required this.micAddress,
    required this.micStatus,
    required this.onMicAddress,
    required this.onMicEnabled,
  });

  final DateTime now;
  final tz.Location? selected;
  final String version;
  final ValueChanged<tz.Location?> onSelected;
  final String micAddress;
  final String micStatus;
  final Future<void> Function(String) onMicAddress;
  final Future<bool> Function(bool) onMicEnabled;

  Future<String?> _editAddress(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => _AddressDialog(initial: micAddress),
    );
  }

  Future<void> _toggleMic(BuildContext context, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    if (enabled && _parseAddress(micAddress) == null) {
      final address = await _editAddress(context);
      if (address == null || _parseAddress(address) == null) return;
      await onMicAddress(address);
    }
    final ok = await onMicEnabled(enabled);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Microphone permission is required')),
      );
    }
  }

  Future<void> _changeAddress(BuildContext context) async {
    final address = await _editAddress(context);
    if (address != null) await onMicAddress(address);
  }

  Future<void> _pickTimeZone(BuildContext context) async {
    final result = await Navigator.of(context).push<_ZoneChoice>(
      MaterialPageRoute(builder: (_) => TimeZonePickerPage(selected: selected)),
    );
    if (result != null) onSelected(result.location);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme.apply(
      bodyColor: _textColor,
      displayColor: _textColor,
    );
    final offset = _formatOffset(_timeIn(now, selected).timeZoneOffset);
    return MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeRight: true,
      child: Theme(
        data: theme.copyWith(
          textTheme: text,
          cardTheme: const CardThemeData(color: _tileColor),
          listTileTheme: const ListTileThemeData(
            textColor: _textColor,
            iconColor: _textColor,
          ),
        ),
        child: ColoredBox(
          color: Colors.black,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 8, 48, 48),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('Settings', style: _textStyle(40)),
              ),
              const SizedBox(height: 16),
              Text('Time', style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Time zone'),
                  subtitle: Text('${_zoneLabel(selected)}  ·  $offset'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickTimeZone(context),
                ),
              ),
              const SizedBox(height: 32),
              Text('Microphone', style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(
                    micStatus == _micOff ? Icons.mic_off : Icons.mic,
                  ),
                  title: const Text('Stream to computer'),
                  subtitle: Text(_micStatusLabel(micStatus, micAddress)),
                  trailing: Switch(
                    value: micStatus != _micOff,
                    onChanged: (v) => _toggleMic(context, v),
                  ),
                  onTap: () => _toggleMic(context, micStatus == _micOff),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.computer),
                  title: const Text('Computer address'),
                  subtitle: Text(micAddress.isEmpty ? 'Not set' : micAddress),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeAddress(context),
                ),
              ),
              const SizedBox(height: 32),
              Text('About', style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('Version'),
                  subtitle: Text(version.isEmpty ? '' : 'v$version'),
                  onTap: () => checkForUpdateManually(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.initial});

  final String initial;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (_parseAddress(value) == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      title: const Text('Computer address'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: '192.168.1.10:$_micDefaultPort',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ZoneChoice {
  const _ZoneChoice(this.location);

  final tz.Location? location;
}

class TimeZonePickerPage extends StatefulWidget {
  const TimeZonePickerPage({super.key, required this.selected});

  final tz.Location? selected;

  @override
  State<TimeZonePickerPage> createState() => _TimeZonePickerPageState();
}

class _TimeZonePickerPageState extends State<TimeZonePickerPage> {
  static const _itemHeight = 72.0;
  static const _listPadding = 8.0;

  final DateTime _now = DateTime.now();
  late final List<tz.Location?> _locations = _loadLocations(_now);
  ScrollController? _controller;

  static List<tz.Location?> _loadLocations(DateTime now) {
    final names = _zoneNames.keys.toList();
    final list = names.map(tz.getLocation).toList();
    Duration offsetOf(tz.Location l) =>
        l.timeZone(now.millisecondsSinceEpoch).offset;
    list.sort((a, b) {
      final diff = offsetOf(a).compareTo(offsetOf(b));
      return diff != 0
          ? diff
          : names.indexOf(a.name).compareTo(names.indexOf(b.name));
    });
    return [null, ...list];
  }

  ScrollController _controllerFor(double viewportHeight) {
    return _controller ??= () {
      final index = _locations.indexWhere(
        (l) => l?.name == widget.selected?.name,
      );
      final contentHeight = _locations.length * _itemHeight + _listPadding * 2;
      final maxOffset = (contentHeight - viewportHeight).clamp(
        0.0,
        double.infinity,
      );
      final center =
          _listPadding +
          index.clamp(0, _locations.length - 1) * _itemHeight +
          _itemHeight / 2;
      final offset = (center - viewportHeight / 2).clamp(0.0, maxOffset);
      return ScrollController(initialScrollOffset: offset);
    }();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeLeft: true,
      removeRight: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: const Row(
            children: [
              SizedBox(width: 36),
              BackButton(),
              SizedBox(width: 20),
              Text('Time zone'),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => ListView.builder(
            controller: _controllerFor(constraints.maxHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: _listPadding,
            ),
            itemExtent: _itemHeight,
            itemCount: _locations.length,
            itemBuilder: (context, index) {
              final location = _locations[index];
              final isSelected = location?.name == widget.selected?.name;
              final time = _timeIn(_now, location);
              return ListTile(
                selected: isSelected,
                horizontalTitleGap: 32,
                leading: Icon(isSelected ? Icons.check : null),
                title: Text(_zoneLabel(location)),
                subtitle: Text(_formatOffset(time.timeZoneOffset)),
                trailing: Text(
                  '${_two(time.hour)}:${_two(time.minute)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () => Navigator.of(context).pop(_ZoneChoice(location)),
              );
            },
          ),
        ),
      ),
    );
  }
}

class DigitTile extends StatelessWidget {
  const DigitTile({
    super.key,
    required this.height,
    required this.text,
    this.bottomRight,
  });

  final double height;
  final String text;
  final String? bottomRight;

  Widget _char(String c, double width, double fontSize) {
    return SizedBox(
      width: width,
      child: Text(
        c,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: _textStyle(fontSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _tileColor,
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [_char(text[0], 125, 250), _char(text[1], 125, 250)],
            ),
          ),
          if (bottomRight != null)
            Positioned(
              right: 24,
              bottom: 8,
              child: Row(
                children: [
                  _char(bottomRight![0], 20, 40),
                  _char(bottomRight![1], 20, 40),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _batteryImagePixels);
    final paint = Paint()..color = _textColor;
    canvas.drawDRRect(
      RRect.fromLTRBR(6, 37.5, 131, 112.5, const Radius.circular(12)),
      RRect.fromLTRBR(16, 47, 121.5, 103, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        136,
        60,
        144,
        89.5,
        topRight: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) => false;
}

class BatteryBadge extends StatelessWidget {
  const BatteryBadge({
    super.key,
    required this.percent,
    required this.charging,
  });

  final int percent;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final color = charging
        ? const Color(0xFFFFFF00)
        : percent <= 30
        ? const Color(0xFFFF0000)
        : const Color(0xFF00FF00);
    final imageSize =
        _batteryImagePixels / MediaQuery.devicePixelRatioOf(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size.square(imageSize),
          painter: const _BatteryPainter(),
        ),
        SizedBox(
          width: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 36,
              child: Text(
                '$percent',
                textAlign: TextAlign.center,
                style: _textStyle(18, color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
