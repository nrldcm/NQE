// Non-web stub: the web-only sqflite factory package is never imported into the
// mobile/desktop build (it pulls in browser libraries that break a native AOT
// compile). Selected by conditional import when dart.library.html is absent.
void configureWebDatabaseFactory() {
  // No-op off the web — the native databaseFactory is set elsewhere.
}
