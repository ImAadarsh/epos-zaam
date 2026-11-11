/// Extracts a YouTube video id from a watch/embed/short URL or raw id.
String? parseYoutubeVideoId(String? input) {
  if (input == null) return null;
  final s = input.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^[\w-]{11}$').hasMatch(s)) return s;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  if (host == 'youtu.be') {
    final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
  }
  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && RegExp(r'^[\w-]{11}$').hasMatch(v)) return v;
    final parts = uri.pathSegments;
    for (var i = 0; i < parts.length - 1; i++) {
      if (const {'embed', 'shorts', 'live', 'v'}.contains(parts[i])) {
        final id = parts[i + 1];
        if (RegExp(r'^[\w-]{11}$').hasMatch(id)) return id;
      }
    }
  }
  return null;
}

String? youtubeEmbedUrl(String? input) {
  final id = parseYoutubeVideoId(input);
  if (id == null) return null;
  // youtube-nocookie + mute required for autoplay in Chrome; playlist=id enables loop.
  return 'https://www.youtube-nocookie.com/embed/$id'
      '?autoplay=1&mute=1&loop=1&playlist=$id&controls=0&rel=0&modestbranding=1&playsinline=1&iv_load_policy=3';
}
