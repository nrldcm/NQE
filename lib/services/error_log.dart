// Lightweight on-device error logger. Writes one file PER DAY (rotated by
// date) so logs are easy to find and share, and prunes files older than
// [_keepDays]. Desktop → <Documents>/NQE/errors ; mobile → <app external
// storage>/Logs. Every method swallows its own errors — logging must never
// crash the app.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const int _keepDays = 14;

  Directory? _dir;
  bool _pruned = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<Directory> _logDir() async {
    if (_dir != null) return _dir!;
    try {
      if (_isDesktop) {
        final base = await getApplicationDocumentsDirectory();
        _dir = Directory(p.join(base.path, 'NQE', 'errors'));
      } else {
        // Android app-specific external storage — no runtime permission needed.
        final ext = await getExternalStorageDirectory();
        final base = ext ?? await getApplicationDocumentsDirectory();
        _dir = Directory(p.join(base.path, 'Logs'));
      }
      await _dir!.create(recursive: true);
    } catch (_) {
      _dir = Directory.systemTemp;
    }
    return _dir!;
  }

  String _dateStamp(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Append a timestamped entry to today's log file.
  Future<void> log(String message, {Object? error, StackTrace? stack}) async {
    // TODO(web): no on-device file logging on web (no dart:io). Fall back to the
    // console so uncaught errors are still surfaced in the browser dev tools.
    if (kIsWeb) {
      if (kDebugMode) {
        debugPrint('[ErrorLog] $message${error != null ? ' — $error' : ''}');
      }
      return;
    }
    try {
      final now = DateTime.now();
      final dir = await _logDir();
      final file = File(p.join(dir.path, 'nqe-${_dateStamp(now)}.log'));
      final buf = StringBuffer()
        ..write('[')
        ..write(now.toIso8601String())
        ..write('] ')
        ..write(message);
      if (error != null) buf..write('\n    error: ')..write(error);
      if (stack != null) {
        buf
          ..write('\n    stack: ')
          ..write(stack.toString().split('\n').take(12).join('\n           '));
      }
      buf.write('\n');
      await file.writeAsString(buf.toString(),
          mode: FileMode.append, flush: true);
      if (!_pruned) {
        _pruned = true;
        unawaited(_prune());
      }
    } catch (_) {
      // Never let logging throw into the app.
    }
  }

  Future<void> _prune() async {
    try {
      final dir = await _logDir();
      final cutoff = DateTime.now().subtract(const Duration(days: _keepDays));
      await for (final e in dir.list()) {
        if (e is File &&
            p.basename(e.path).startsWith('nqe-') &&
            e.path.endsWith('.log')) {
          try {
            if ((await e.stat()).modified.isBefore(cutoff)) await e.delete();
          } catch (_) {/* skip */}
        }
      }
    } catch (_) {/* best effort */}
  }

  /// Where the log files live (for showing the user in Settings).
  Future<String> dirPath() async {
    // TODO(web): no filesystem log directory on web.
    if (kIsWeb) return 'unavailable on web';
    return (await _logDir()).path;
  }

  /// Install global handlers so uncaught framework/platform errors are logged.
  void installGlobalHandlers() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(log('FlutterError: ${details.exceptionAsString()}',
          error: details.exception, stack: details.stack));
      prevFlutter?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(log('Uncaught', error: error, stack: stack));
      return false; // don't swallow — let the default handler run too
    };
  }
}
