// First-run onboarding. Security setup is REQUIRED on every install (it is not
// part of a backup and can't be restored). After that the user starts fresh or
// restores a backup file.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/crypto_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/nqe_logo.dart';
import 'home_shell.dart';
import 'splash_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _auth = AuthService.instance;
  int _step = 0;

  final _pin1 = TextEditingController();
  final _pin2 = TextEditingController();
  bool _enableBio = false;
  bool _canBio = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _auth.canUseBiometrics().then((v) {
      if (mounted) setState(() => _canBio = v);
    });
  }

  @override
  void dispose() {
    _pin1.dispose();
    _pin2.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _goto(int s) => setState(() => _step = s);

  Future<void> _saveSecurity() async {
    final p1 = _pin1.text.trim();
    final p2 = _pin2.text.trim();
    if (p1.length < 4 || p1.length > 6) {
      _snack('PIN must be 4–6 digits');
      return;
    }
    if (p1 != p2) {
      _snack('PINs do not match');
      return;
    }
    setState(() => _busy = true);
    await _auth.setPin(p1);
    await _auth.setLockEnabled(true);
    await _auth.setBiometricEnabled(_enableBio && _canBio);
    if (!mounted) return;
    setState(() => _busy = false);
    _goto(2);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardedKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c),
      ),
    );
  }

  Future<void> _startFresh() async {
    setState(() => _busy = true);
    try {
      // Truly empty ledger — the user adds their own books.
      await appState.load();
      await _finish();
    } catch (e) {
      setState(() => _busy = false);
      _snack('Could not start: $e');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final bytes = await BackupService.instance.pickFileBytes();
      if (bytes == null) {
        setState(() => _busy = false);
        return;
      }
      var pass = '';
      if (BackupService.instance.needsPassphrase(bytes)) {
        pass = await _promptPass() ?? '';
        if (pass.isEmpty) {
          setState(() => _busy = false);
          _snack('Passphrase required for this backup');
          return;
        }
      }
      final res = await BackupService.instance.importBytes(bytes, passphrase: pass);
      await appState.load();
      _snack('Restored ${res.accounts} books, ${res.trades} trades');
      await _finish();
    } on CryptoException catch (e) {
      setState(() => _busy = false);
      _snack(e.message);
    } catch (e) {
      setState(() => _busy = false);
      _snack('Restore failed: $e');
    }
  }

  Future<String?> _promptPass() async {
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

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStep(pal),
        ),
      ),
    );
  }

  Widget _buildStep(NqePalette pal) {
    switch (_step) {
      case 0:
        return _welcome(pal);
      case 1:
        return _security(pal);
      default:
        return _data(pal);
    }
  }

  Widget _welcome(NqePalette pal) {
    return Padding(
      key: const ValueKey('w'),
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          const NqeLogo(scale: 1.0),
          const SizedBox(height: 24),
          const WillongByline(),
          const SizedBox(height: 28),
          Text(
            'Your private, offline trading ledger.\nLet’s set it up in two quick steps.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, fontSize: 14, height: 1.5),
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _goto(1),
              child: const Text('Get started'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _security(NqePalette pal) {
    return SingleChildScrollView(
      key: const ValueKey('s'),
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_outline, size: 40, color: pal.textHi),
          const SizedBox(height: 16),
          Text('Secure your app',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: pal.textHi,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Set a PIN to protect your ledger. This is required each time you '
            'install the app and cannot be restored from a backup.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _pin1,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN (4–6 digits)'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _pin2,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Confirm PIN'),
          ),
          if (_canBio)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(Icons.fingerprint, color: pal.textHi),
              title: Text('Enable fingerprint / face unlock',
                  style: TextStyle(color: pal.textHi, fontSize: 14)),
              value: _enableBio,
              onChanged: (v) => setState(() => _enableBio = v),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _saveSecurity,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _data(NqePalette pal) {
    return Padding(
      key: const ValueKey('d'),
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.folder_outlined, size: 40, color: pal.textHi),
          const SizedBox(height: 16),
          Text('Your data',
              style: TextStyle(
                  color: pal.textHi,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Start with a fresh ledger, or restore from an encrypted backup file.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textLo, fontSize: 13, height: 1.5),
          ),
          const Spacer(),
          _choice(
            pal,
            icon: Icons.add_circle_outline,
            title: 'Start fresh',
            subtitle: 'Begin with example books you can edit',
            onTap: _busy ? null : _startFresh,
          ),
          const SizedBox(height: 12),
          _choice(
            pal,
            icon: Icons.download_outlined,
            title: 'Restore from backup',
            subtitle: 'Import a .nqe file (from Drive, Files, etc.)',
            onTap: _busy ? null : _restore,
          ),
          const Spacer(flex: 2),
          if (_busy) const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _choice(NqePalette pal,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap}) {
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.line),
          ),
          child: Row(
            children: [
              Icon(icon, color: pal.textHi),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: pal.textHi,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: pal.textLo, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: pal.textLo),
            ],
          ),
        ),
      ),
    );
  }
}
