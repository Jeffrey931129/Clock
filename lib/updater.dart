import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _repo = 'Jeffrey931129/Clock';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.apkUrl,
  });

  final String version;
  final String notes;
  final String apkUrl;
}

class UpdateCheck {
  const UpdateCheck(this.currentVersion, this.update);

  final String currentVersion;
  final AppRelease? update;
}

Future<UpdateCheck> checkForUpdate() async {
  final current = (await PackageInfo.fromPlatform()).version;
  if (!Platform.isAndroid) return UpdateCheck(current, null);
  final res = await http
      .get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 10));
  if (res.statusCode == 404) return UpdateCheck(current, null);
  if (res.statusCode != 200) {
    throw HttpException('GitHub API returned ${res.statusCode}');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final latest = (json['tag_name'] as String? ?? '').replaceFirst(
    RegExp(r'^[vV]'),
    '',
  );
  final assets = (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
  final apk = assets.where(
    (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
  );
  if (latest.isEmpty || apk.isEmpty || compareVersions(latest, current) <= 0) {
    return UpdateCheck(current, null);
  }
  return UpdateCheck(
    current,
    AppRelease(
      version: latest,
      notes: json['body'] as String? ?? '',
      apkUrl: apk.first['browser_download_url'] as String,
    ),
  );
}

int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

Future<void> showUpdateDialog(BuildContext context, AppRelease release) async {
  final install = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update available: v${release.version}'),
      content: release.notes.trim().isEmpty
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(child: Text(release.notes.trim())),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  if (install != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(release: release),
  );
}

Future<void> checkForUpdateManually(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await checkForUpdate();
    if (!context.mounted) return;
    if (result.update == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'You are on the latest version (v${result.currentVersion})',
          ),
        ),
      );
    } else {
      await showUpdateDialog(context, result.update!);
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not check for updates')),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.release});

  final AppRelease release;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  OtaUpdate _ota = OtaUpdate();
  StreamSubscription<OtaEvent>? _sub;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sub?.cancel();
    _ota = OtaUpdate();
    setState(() {
      _progress = null;
      _error = null;
    });
    try {
      _sub = _ota
          .execute(widget.release.apkUrl, destinationFilename: 'clock.apk')
          .listen(_onEvent, onError: (e) => _fail('$e'));
    } catch (e) {
      _fail('$e');
    }
  }

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        setState(
          () => _progress = (double.tryParse(event.value ?? '') ?? 0) / 100,
        );
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
      case OtaStatus.CANCELED:
        Navigator.of(context).pop();
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Permission to install apps was not granted');
      default:
        _fail(event.value ?? event.status.name);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    return AlertDialog(
      title: Text(
        failed ? 'Update failed' : 'Downloading v${widget.release.version}',
      ),
      content: failed
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 12),
                Text(
                  _progress == null
                      ? 'Starting...'
                      : '${(_progress! * 100).round()}%',
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () {
            if (!failed) _ota.cancel();
            Navigator.of(context).pop();
          },
          child: Text(failed ? 'Close' : 'Cancel'),
        ),
        if (failed) FilledButton(onPressed: _start, child: const Text('Retry')),
      ],
    );
  }
}
