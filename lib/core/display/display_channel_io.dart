import 'dart:async';

final _local = StreamController<Map<String, dynamic>>.broadcast();

const bool crossWindowDisplaySupported = false;

void postDisplayMessage(Map<String, dynamic> message) => _local.add(message);

Stream<Map<String, dynamic>> displayMessages() => _local.stream;

void openDisplayWindow() {}
