// Developer Mode → integration API keys. Keys are AES-GCM encrypted and stored
// in SQLite; only a masked hint is ever shown. Once saved a key can't be viewed
// again (delete + re-add to change) — the app decrypts it only to use it.
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../models.dart';
import '../services/crypto_service.dart';
import '../theme.dart';
import '../util.dart';
import 'editors/editor_scaffold.dart';

const List<String> kProviders = [
  'TradingView',
  'Finnhub',
  'Alpha Vantage',
  'Polygon',
  'Twelve Data',
  'Broker',
  'Custom',
];

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  List<ApiKey> _keys = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final keys = await LedgerDb.instance.apiKeys();
    if (!mounted) return;
    setState(() {
      _keys = keys;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddKeySheet(),
    );
    if (added == true) await _reload();
  }

  Future<void> _delete(ApiKey k) async {
    final ok = await confirmDelete(
        context, 'Delete “${k.label}” key?', 'This integration key will be removed.');
    if (!ok) return;
    await LedgerDb.instance.deleteApiKey(k.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: const Text('Developer')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: pal.textHi,
        foregroundColor: pal.bg,
        icon: const Icon(Icons.add),
        label: const Text('Add API key'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pal.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: pal.textLo),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Integration keys are encrypted and stored only on this '
                          'device. Once saved, a key can’t be viewed again — delete '
                          'and re-add to change it. No app rebuild needed.',
                          style: TextStyle(
                              color: pal.textLo, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('API KEYS',
                    style: TextStyle(
                        color: pal.textLo,
                        fontSize: 12,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_keys.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: pal.line),
                    ),
                    child: Text('No integration keys yet',
                        style: TextStyle(color: pal.textLo)),
                  )
                else
                  ..._keys.map((k) => _keyTile(pal, k)),
              ],
            ),
    );
  }

  Widget _keyTile(NqePalette pal, ApiKey k) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.line),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_key_outlined, size: 20, color: pal.textHi),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: pal.textHi,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(k.masked,
                    style: TextStyle(
                        color: pal.textLo, fontSize: 13, letterSpacing: 1)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: NqeColors.loss),
            onPressed: () => _delete(k),
          ),
        ],
      ),
    );
  }
}

class _AddKeySheet extends StatefulWidget {
  const _AddKeySheet();

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  final _label = TextEditingController();
  final _secret = TextEditingController();
  String _provider = kProviders.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _label.text = _provider;
  }

  @override
  void dispose() {
    _label.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API key is required')));
      return;
    }
    setState(() => _saving = true);
    final enc = await CryptoService.instance.encryptSecret(secret);
    final hint = secret.length <= 4 ? secret : secret.substring(secret.length - 4);
    final k = ApiKey(
      id: uid(),
      label: _label.text.trim().isEmpty ? _provider : _label.text.trim(),
      service: _provider.toLowerCase(),
      secretEnc: enc,
      hint: hint,
      createdAt: nowIso(),
    );
    await LedgerDb.instance.upsertApiKey(k);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return EditorScaffold(
      title: 'Add API key',
      onSave: _saving ? () async {} : _save,
      children: [
        EditorDropdown<String>(
          label: 'Provider',
          value: _provider,
          items: kProviders,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              if (_label.text.trim().isEmpty ||
                  kProviders.contains(_label.text.trim())) {
                _label.text = v;
              }
              _provider = v;
            });
          },
        ),
        EditorField(label: 'Label', controller: _label),
        EditorField(
          label: 'API key / secret',
          controller: _secret,
          obscure: true,
          hint: 'Stored encrypted, not shown again',
        ),
      ],
    );
  }
}
