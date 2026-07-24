// Web-only: wire sqflite to the WASM/IndexedDB factory. This file is imported
// ONLY on web (via a conditional import), so the browser-specific package never
// enters the mobile/desktop build.
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void configureWebDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
