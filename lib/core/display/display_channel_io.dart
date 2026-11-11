import 'dart:async';

const bool crossWindowDisplaySupported = false;

void postDisplayMessage(Map<String, dynamic> message) {}

Map<String, dynamic>? readStoredDisplayMessage() => null;

Stream<Map<String, dynamic>> displayMessages() => const Stream.empty();

void openDisplayWindow({String youtubeUrl = ''}) {}
