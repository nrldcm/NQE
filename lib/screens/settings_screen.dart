// Settings: appearance (day/night, persisted), security (lock + biometric +
// PIN), encrypted backup/restore, and about.
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/crypto_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService.instance;
  bool _lock = false;
  bool _bio = false;
  bool _hasPin = false;
  bool _canBio = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSecurity();
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
              decoration: const InputDecoration(labelText: 'PIN (4–6 digits)'),
            ),
            TextField(
              controller: c2,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
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
    if (p1.length < 4 || p1.length > 6 || p1 != p2) {
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

  // ---- Backup ----
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportAndShare();
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
      final res = await BackupService.instance.pickAndImport();
      if (res == null) {
        _snack('Import cancelled');
      } else {
        await appState.load();
        _snack(
            'Restored ${res.accounts} books, ${res.trades} trades, ${res.cashflows} cashflows');
      }
    } on CryptoException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              ]),
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
