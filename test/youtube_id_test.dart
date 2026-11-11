import 'package:flutter_test/flutter_test.dart';
import 'package:zaam_epos/core/display/youtube_id.dart';

void main() {
  test('parses watch, short, embed and raw ids', () {
    expect(parseYoutubeVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYoutubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYoutubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYoutubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(parseYoutubeVideoId(''), null);
    expect(parseYoutubeVideoId('not-a-video-id'), null);
    expect(parseYoutubeVideoId('https://example.com/watch?v=x'), null);
  });

  test('builds muted looping embed url', () {
    final url = youtubeEmbedUrl('https://youtu.be/dQw4w9WgXcQ');
    expect(url, contains('youtube-nocookie.com/embed/dQw4w9WgXcQ'));
    expect(url, contains('autoplay=1'));
    expect(url, contains('mute=1'));
    expect(url, contains('loop=1'));
  });
}
