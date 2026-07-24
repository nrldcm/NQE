// Settings: appearance (day/night, persisted), security (lock + biometric +
// PIN), device sync, encrypted backup/restore, and about.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/crypto_service.dart';
import '../state/app_state.dart';
import '../sync/foreground.dart';
import '../sync/sync_client.dart';
import '../sync/sync_server.dart';
import '../theme.dart';
import '../widgets/connection_watcher.dart';
import 'about_screen.dart';
import 'desktop/pairing_screen.dart';
import 'developer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService.instance;
  static const _kExportPass = 'export_passphrase';
  bool _lock = false;
  bool _bio = false;
  bool _hasPin = false;
  bool _canBio = false;
  bool _busy = false;
  bool _syncBusy = false;
  bool _devMode = false;
  String _exportPass = '';
  static const _kDevMode = 'developer_mode';

  static final bool _isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _loadSecurity();
    _loadBackupPass();
    _loadDevMode();
  }

  Future<void> _loadDevMode() async {
    final prefs = await SharedPreferences.getInstance();
    _devMode = prefs.getBool(_kDevMode) ?? false;
    if (mounted) setState(() {});
  }

  Future<void> _setDevMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDevMode, v);
    _devMode = v;
    if (mounted) setState(() {});
  }

  Future<void> _loadBackupPass() async {
    final prefs = await SharedPreferences.getInstance();
    _exportPass = prefs.getString(_kExportPass) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveBackupPass(String v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v.isEmpty) {
      await prefs.remove(_kExportPass);
    } else {
      await prefs.setString(_kExportPass, v);
    }
    _exportPass = v;
    if (mounted) setState(() {});
  }

  Future<void> _loadSecurity() async {
    _lock = await _auth.lockEnabled();
    _bio = await _auth.biometricEnabled();
    _hasPin = await _auth.hasPin();
    _canBio = await _auth.canUseBiometrics();
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- Security ----
  Future<void> _toggleLock(bool on) async {
    if (on) {
      if (!_hasPin) {
        final set = await _showSetPinDialog();
        if (!set) return;
      }
      await _auth.setLockEnabled(true);
    } else {
      await _auth.setLockEnabled(false);
      await _auth.setBiometricEnabled(false);
    }
    await _loadSecurity();
  }

  Future<bool> _showSetPinDialog() async {
    final pal = context.nqe;
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Set a PIN', style: TextStyle(color: pal.textHi)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c1,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'PIN (4–6 digits)', counterText: ''),
            ),
            TextField(
              controller: c2,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Confirm PIN', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return false;
    final p1 = c1.text.trim();
    final p2 = c2.text.trim();
    final digitsOnly = RegExp(r'^\d+$').hasMatch(p1);
    if (p1.length < 4 || p1.length > 6 || p1 != p2 || !digitsOnly) {
      _snack('PINs must match and be 4–6 digits');
      return false;
    }
    await _auth.setPin(p1);
    _hasPin = true;
    _snack('PIN saved');
    return true;
  }

  Future<void> _toggleBio(bool on) async {
    if (on && !_canBio) {
      _snack('No biometric hardware enrolled on this device');
      return;
    }
    await _auth.setBiometricEnabled(on);
    await _loadSecurity();
  }

  // ---- Desktop Mode ----
  Future<void> _toggleServer(bool on) async {
    setState(() => _syncBusy = true);
    try {
      if (on) {
        await SyncServer.instance.start();
        if (SyncServer.instance.status == SyncStatus.error) {
          _snack(SyncServer.instance.lastError ?? 'Could not start sync server');
        }
      } else {
        await SyncServer.instance.stop();
      }
    } catch (e) {
      _snack('Sync error: $e');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _editSyncPort() async {
    final pal = context.nqe;
    final ctrl = TextEditingController(
        text: SyncServer.instance.preferredPort.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Sync port', style: TextStyle(color: pal.textHi)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Port the phone listens on for the desktop. It auto-scans for an '
              'open port if this one is busy, so you usually don\'t need to '
              'change it. The chosen port is embedded in the pairing QR.',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Port (1024–65535)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(ctrl.text.trim())),
              child: const Text('Apply')),
        ],
      ),
    );
    if (res == null) return;
    await SyncServer.instance.setPreferredPort(res);
    if (mounted) setState(() {});
  }

  Future<void> _rePairDesktop() async {
    final pal = context.nqe;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Re-pair this desktop?', style: TextStyle(color: pal.textHi)),
        content: Text(
          'This forgets the current phone pairing and shows the QR again so you '
          'can scan it from your phone. Your local data is kept.',
          style: TextStyle(color: pal.textLo),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Re-pair')),
        ],
      ),
    );
    if (ok != true) return;
    await SyncClient.instance.unpair();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DesktopPairingScreen(
        onPaired: () => Navigator.of(context).maybePop(),
      ),
    ));
    if (mounted) setState(() {});
  }

  // ---- Backup ----
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportAndShare(passphrase: _exportPass);
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final pal = context.nqe;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Restore backup?', style: TextStyle(color: pal.textHi)),
        content: Text(
          'This will REPLACE all current data with the contents of the backup file. This cannot be undone.',
          style: TextStyle(color: pal.textLo),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose file')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final Uint8List? bytes = await BackupService.instance.pickFileBytes();
      if (bytes == null) {
        _snack('Import cancelled');
        return;
      }
      // Decide passphrase: use the saved one; prompt if the file needs one
      // and the saved passphrase is missing/wrong.
      var pass = _exportPass;
      if (BackupService.instance.needsPassphrase(bytes) && pass.isEmpty) {
        pass = await _promptPassphrase() ?? '';
        if (pass.isEmpty) {
          _snack('Passphrase required to restore this backup');
          return;
        }
      }
      ImportResult res;
      try {
        res = await BackupService.instance.importBytes(bytes, passphrase: pass);
      } on CryptoException catch (e) {
        // Wrong/absent passphrase → offer one retry with a prompt.
        if (BackupService.instance.needsPassphrase(bytes)) {
          final retry = await _promptPassphrase();
          if (retry == null || retry.isEmpty) {
            _snack(e.message);
            return;
          }
          res = await BackupService.instance
              .importBytes(bytes, passphrase: retry);
        } else {
          rethrow;
        }
      }
      await appState.load();
      _snack(
          'Restored ${res.accounts} books, ${res.trades} trades, ${res.cashflows} cashflows');
    } on CryptoException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptPassphrase() async {
    final pal = context.nqe;
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Backup passphrase', style: TextStyle(color: pal.textHi)),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Restore')),
        ],
      ),
    );
  }

  Future<void> _setBackupPassphrase() async {
    final pal = context.nqe;
    final c = TextEditingController(text: _exportPass);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pal.surface,
        title: Text('Backup passphrase', style: TextStyle(color: pal.textHi)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Optional. If set, exported backups can ONLY be restored with this '
              'passphrase — real confidentiality even for files saved to Drive. '
              'Leave blank to use app-only encryption.',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Passphrase (blank = off)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (res == null) return;
    await _saveBackupPass(res);
    _snack(res.isEmpty ? 'Backup passphrase removed' : 'Backup passphrase set');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _sectionLabel('Appearance', pal),
              _card(pal, [
                _themeTile(ThemeMode.light, Icons.light_mode, 'Light', pal),
                _divider(pal),
                _themeTile(ThemeMode.dark, Icons.dark_mode, 'Dark', pal),
                _divider(pal),
                _themeTile(
                    ThemeMode.system, Icons.brightness_auto, 'System', pal),
              ]),
              // Security (lock / PIN / biometric) is managed on the phone; the
              // desktop just mirrors it, so hide the whole section there.
              if (!_isDesktop) ...[
              const SizedBox(height: 20),
              _sectionLabel('Security', pal),
              _card(pal, [
                SwitchListTile(
                  secondary: Icon(Icons.lock_outline, color: pal.textHi),
                  title: Text('App lock', style: TextStyle(color: pal.textHi)),
                  subtitle: Text('Require unlock on launch',
                      style: TextStyle(color: pal.textLo, fontSize: 12)),
                  value: _lock,
                  onChanged: _toggleLock,
                ),
                // Biometric unlock is a phone capability — hidden on desktop.
                if (!_isDesktop) ...[
                  _divider(pal),
                  SwitchListTile(
                    secondary: Icon(Icons.fingerprint, color: pal.textHi),
                    title: Text('Biometric unlock',
                        style: TextStyle(color: pal.textHi)),
                    subtitle: Text(
                        _canBio
                            ? 'Fingerprint / face / device PIN'
                            : 'Not available on this device',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    value: _bio && _canBio,
                    onChanged: (_lock && _canBio) ? _toggleBio : null,
                  ),
                ],
                _divider(pal),
                ListTile(
                  leading: Icon(Icons.pin_outlined, color: pal.textHi),
                  title: Text(_hasPin ? 'Change PIN' : 'Set PIN',
                      style: TextStyle(color: pal.textHi)),
                  trailing: Icon(Icons.chevron_right, color: pal.textLo),
                  onTap: () async {
                    await _showSetPinDialog();
                    await _loadSecurity();
                  },
                ),
              ]),
              ],
              const SizedBox(height: 20),
              _sectionLabel('Desktop Mode', pal),
              _deviceSyncSection(pal),
              // Backup lives on the phone (the source of truth); the desktop is
              // a stateless mirror, so hide the whole Backup section there.
              if (!_isDesktop) ...[
                const SizedBox(height: 20),
                _sectionLabel('Backup', pal),
                _card(pal, [
                  ListTile(
                    leading: Icon(Icons.ios_share, color: pal.textHi),
                    title: Text('Export encrypted backup',
                        style: TextStyle(color: pal.textHi)),
                    subtitle: Text('Share to Google Drive, Files, etc. (.nqe)',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    onTap: _busy ? null : _export,
                  ),
                  _divider(pal),
                  ListTile(
                    leading: Icon(Icons.download_outlined, color: pal.textHi),
                    title: Text('Restore from backup',
                        style: TextStyle(color: pal.textHi)),
                    subtitle: Text('Import a .nqe file (replaces data)',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    onTap: _busy ? null : _import,
                  ),
                  _divider(pal),
                  ListTile(
                    leading: Icon(Icons.password, color: pal.textHi),
                    title: Text('Backup passphrase',
                        style: TextStyle(color: pal.textHi)),
                    subtitle: Text(
                        _exportPass.isEmpty
                            ? 'Off — app-only encryption'
                            : 'On — backups require your passphrase',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    trailing: Icon(Icons.chevron_right, color: pal.textLo),
                    onTap: _setBackupPassphrase,
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              _sectionLabel('About', pal),
              _card(pal, [
                ListTile(
                  leading: Icon(Icons.info_outline, color: pal.textHi),
                  title: Text('About NQE', style: TextStyle(color: pal.textHi)),
                  trailing: Icon(Icons.chevron_right, color: pal.textLo),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
              ]),
              // Developer / API-key setup belongs on the phone, not the mirror.
              if (!_isDesktop) ...[
                const SizedBox(height: 20),
                _sectionLabel('Developer', pal),
                _card(pal, [
                  SwitchListTile(
                    secondary: Icon(Icons.code, color: pal.textHi),
                    title: Text('Developer Mode',
                        style: TextStyle(color: pal.textHi)),
                    subtitle: Text('Integrations & API keys',
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                    value: _devMode,
                    onChanged: _setDevMode,
                  ),
                  if (_devMode) ...[
                    _divider(pal),
                    ListTile(
                      leading: Icon(Icons.vpn_key_outlined, color: pal.textHi),
                      title: Text('Integrations & API keys',
                          style: TextStyle(color: pal.textHi)),
                      subtitle: Text(
                          'Enter API keys used by live data / trading',
                          style: TextStyle(color: pal.textLo, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right, color: pal.textLo),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const DeveloperScreen())),
                    ),
                  ],
                ]),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }

  // Mobile: run the LAN server + offer "Pair Desktop Device". Desktop: show the
  // sync connection and a re-pair action (the desktop is the client).
  Widget _deviceSyncSection(NqePalette pal) {
    if (_isDesktop) {
      return ListenableBuilder(
        listenable: SyncClient.instance,
        builder: (context, _) {
          final c = SyncClient.instance;
          return _card(pal, [
            ListTile(
              leading: Icon(Icons.sync, color: pal.textHi),
              title: Text('Sync status', style: TextStyle(color: pal.textHi)),
              subtitle: Text(c.statusMessage ?? 'Paired with your phone',
                  style: TextStyle(color: pal.textLo, fontSize: 12)),
              trailing: ConnectionWatcher(c.state, attempt: c.attempt),
            ),
            _divider(pal),
            ListTile(
              leading: Icon(Icons.sync_alt, color: pal.textHi),
              title: Text('Sync now', style: TextStyle(color: pal.textHi)),
              subtitle: Text('Force a fresh pull from your phone',
                  style: TextStyle(color: pal.textLo, fontSize: 12)),
              trailing: Icon(Icons.refresh, color: pal.textLo),
              onTap: () async {
                await SyncClient.instance.syncNow();
                _snack('Syncing with your phone…');
              },
            ),
            _divider(pal),
            ListTile(
              leading: Icon(Icons.qr_code_scanner, color: pal.textHi),
              title:
                  Text('Re-pair device', style: TextStyle(color: pal.textHi)),
              subtitle: Text('Show the QR again to scan from your phone',
                  style: TextStyle(color: pal.textLo, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: pal.textLo),
              onTap: _rePairDesktop,
            ),
          ]);
        },
      );
    }

    // Mobile.
    return ListenableBuilder(
      listenable: SyncServer.instance,
      builder: (context, _) {
        final s = SyncServer.instance;
        final running = s.isRunning;
        return _card(pal, [
          SwitchListTile(
            secondary: Icon(Icons.wifi_tethering, color: pal.textHi),
            title: Text('Desktop Mode', style: TextStyle(color: pal.textHi)),
            subtitle: Text(
              running
                  ? 'Running · ${s.host ?? '—'}:${s.port} · ${s.connectedPeers} connected'
                  : 'Off — turn on to let your desktop pair & sync',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
            value: running,
            onChanged: _syncBusy ? null : _toggleServer,
          ),
          _divider(pal),
          ListTile(
            leading: Icon(Icons.settings_ethernet, color: pal.textHi),
            title: Text('Sync port', style: TextStyle(color: pal.textHi)),
            subtitle: Text(
              running
                  ? 'Listening on ${s.port}${s.port != s.preferredPort ? ' (auto-picked)' : ''}'
                  : 'Preferred ${s.preferredPort} · auto-scans for an open port',
              style: TextStyle(color: pal.textLo, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: pal.textLo),
            onTap: _editSyncPort,
          ),
          _divider(pal),
          ListTile(
            leading: Icon(Icons.battery_saver_outlined, color: pal.textHi),
            title:
                Text('Background sync', style: TextStyle(color: pal.textHi)),
            subtitle: Text(
                'Keep syncing when locked — set power to “No restrictions”',
                style: TextStyle(color: pal.textLo, fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: pal.textLo),
            onTap: () async {
              // Fires the exemption dialog if not yet granted; if the user has
              // dismissed it before, take them to the settings page instead.
              final wasExempt = await isBatteryUnrestricted();
              await requestBackgroundPermissions();
              if (!wasExempt && !await isBatteryUnrestricted()) {
                await openBatterySettings();
              }
            },
          ),
          if (running) ...[
            _divider(pal),
            // Open the app in any browser on the same network — no install.
            ListTile(
              leading: Icon(Icons.public, color: pal.textHi),
              title: Text('Open in a browser',
                  style: TextStyle(color: pal.textHi)),
              subtitle: Text('http://${s.host ?? '—'}:${s.port}',
                  style: TextStyle(color: pal.textLo, fontSize: 12)),
              trailing: IconButton(
                icon: Icon(Icons.copy, size: 18, color: pal.textLo),
                tooltip: 'Copy URL',
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: 'http://${s.host ?? ''}:${s.port}'));
                  _snack('URL copied');
                },
              ),
            ),
            _divider(pal),
            // Access code the browser must enter to connect (session secret).
            ListTile(
              leading: Icon(Icons.vpn_key_outlined, color: pal.textHi),
              title: Text('Access code', style: TextStyle(color: pal.textHi)),
              subtitle: Text(s.pairingKey.isEmpty ? '—' : s.pairingKey,
                  style: TextStyle(color: pal.textLo, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: Icon(Icons.copy, size: 18, color: pal.textLo),
                tooltip: 'Copy code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: s.pairingKey));
                  _snack('Access code copied');
                },
              ),
            ),
          ],
        ]);
      },
    );
  }

  Widget _themeTile(
      ThemeMode mode, IconData icon, String label, NqePalette pal) {
    final selected = themeController.mode == mode;
    return ListTile(
      leading: Icon(icon, color: pal.textHi),
      title: Text(label, style: TextStyle(color: pal.textHi)),
      trailing: selected
          ? Icon(Icons.check_circle, color: pal.textHi)
          : Icon(Icons.circle_outlined, color: pal.textLo),
      onTap: () => themeController.setMode(mode),
    );
  }

  Widget _sectionLabel(String s, NqePalette pal) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(s.toUpperCase(),
            style: TextStyle(
                color: pal.textLo,
                fontSize: 12,
                letterSpacing: 1,
                fontWeight: FontWeight.w700)),
      );

  Widget _card(NqePalette pal, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.line),
        ),
        child: Column(children: children),
      );

  Widget _divider(NqePalette pal) =>
      Divider(height: 1, color: pal.line, indent: 16, endIndent: 16);
}
