import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:flutter_test/flutter_test.dart';

// As Bilibili signs its play links: a deadline in Unix seconds among others.
String _link(int deadline, {String host = 'upos-sz-mirrorcos.bilivideo.com'}) =>
    'https://$host/upgcxcode/1/2/3/3-1-30080.m4s'
    '?e=ig8euxZM2rNcNbdlhoNvNC8BqJIzNbfqXBvEqxTEto8BTrNvN0GvT90W5JZMkX_YN0MvXg8gNEV4NC8xNEV4N03eN0B5tZlqNxTEto8BTrNvNeZVuJ10Kj_g2UB02J0mN0B5tZlqNCNEto8BTrNvNC7MTX502C8f2jmMQJ6mqF2fka1mqx6gqj0eN0B599M='
    '&uipk=5&nbs=1&deadline=$deadline&gen=playurlv2&os=mcdn&oi=0'
    '&trid=0000a1b2c3d4&mid=0&platform=pc&upsig=0123456789abcdef'
    '&uparams=e,uipk,nbs,deadline,gen,os,oi,trid,mid,platform&bvc=vod&nettype=0';

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  const deadline = 1793350000;

  group('NetworkSource.expiresAt', () {
    test('is the deadline its link carries', () {
      final source = NetworkSource(
        videoSource: _link(deadline),
        audioSource: null,
      );
      expect(source.expiresAt, _at(deadline));
    });

    test('is the earlier of the video and audio links', () {
      final source = NetworkSource(
        videoSource: _link(deadline + 60),
        audioSource: _link(deadline),
      );
      expect(source.expiresAt, _at(deadline));
    });

    test('reads every link in an edl:// source', () {
      final a = _link(deadline + 30);
      final b = _link(deadline);
      final source = NetworkSource(
        videoSource:
            'edl://!no_chapters;%${a.length}%$a,length=60;%${b.length}%$b,length=60;',
        audioSource: '',
      );
      expect(source.expiresAt, _at(deadline));
    });

    test('is null for a link without a deadline', () {
      final source = NetworkSource(
        videoSource: 'https://example.com/v.m4s?e=1&uipk=5',
        audioSource: null,
      );
      expect(source.expiresAt, isNull);
    });

    test('does not take a deadline-like value of another key', () {
      final source = NetworkSource(
        videoSource: 'https://example.com/v.m4s?xdeadline=1&mydeadline=2',
        audioSource: null,
      );
      expect(source.expiresAt, isNull);
    });
  });

  group('SourceExpiry', () {
    final source = NetworkSource(
      videoSource: _link(deadline),
      audioSource: _link(deadline + 600),
    );
    final margin = SourceExpiry.margin.inSeconds;
    // Opened as Bilibili hands links out: two hours before they expire.
    final opened = SourceExpiry(source, _at(deadline - 7200));

    test('not while the links have more than the margin left', () {
      expect(opened.isExpiredAt(_at(deadline - margin - 1)), isFalse);
    });

    test('once within the margin of the earliest deadline', () {
      expect(opened.isExpiredAt(_at(deadline - margin)), isTrue);
    });

    test('after the deadline, as after a long pause', () {
      expect(opened.isExpiredAt(_at(deadline + 3 * 3600)), isTrue);
    });

    test('never for a link without a deadline', () {
      final open = SourceExpiry(
        NetworkSource(
          videoSource: 'https://example.com/v.m4s',
          audioSource: null,
        ),
        _at(deadline),
      );
      expect(open.isExpiredAt(_at(deadline * 2)), isFalse);
    });

    test('never when it looked expired as it opened, as on a clock running '
        'hours ahead, so it is not reopened over and over', () {
      final ahead = SourceExpiry(source, _at(deadline + 3600));
      expect(ahead.isExpiredAt(_at(deadline + 3600)), isFalse);
      expect(ahead.isExpiredAt(_at(deadline + 5 * 3600)), isFalse);
    });

    test('never for a file', () {
      final file = SourceExpiry(
        FileSource(
          dir: '/x',
          isMp4: true,
          hasDashAudio: false,
          typeTag: 't',
        ),
        _at(0),
      );
      expect(file.isExpiredAt(_at(deadline * 2)), isFalse);
    });
  });
}
