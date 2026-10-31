import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/section.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeItem _ep(int cid) => EpisodeItem(cid: cid);

void main() {
  final season = PgcInfoModel(
    episodes: [_ep(1), _ep(2)],
    sections: [
      Section(title: '预告', episodes: [_ep(11), _ep(12)]),
      Section(title: '花絮', episodes: [_ep(21)]),
    ],
  );

  int order(int cid, int index) =>
      DownloadService.seasonOrder(season, _ep(cid), index);

  test('the episodes keep their places, as downloaded before', () {
    expect(order(1, 0), 0);
    expect(order(2, 1), 1);
  });

  test('a section\'s downloads sort after the episodes and the sections '
      'before it, not among them, picked from their own lists', () {
    // Each picked at 0 in its section's list.
    final orders = [
      order(1, 0),
      order(2, 1),
      order(11, 0),
      order(12, 1),
      order(21, 0),
    ];
    expect(orders, orderedEquals([...orders]..sort()));
    expect(order(11, 0), greaterThan(order(2, 1)));
  });

  test('more episodes, as a series airs on, still sort before a section\'s '
      'cached earlier', () {
    final trailer = order(11, 0);
    final aired = PgcInfoModel(
      episodes: [for (var cid = 1; cid <= 500; cid++) _ep(cid)],
      sections: season.sections,
    );
    expect(
      DownloadService.seasonOrder(aired, _ep(500), 499),
      lessThan(trailer),
    );
  });

  test('one in no list keeps where it was picked', () {
    expect(order(99, 7), 7);
  });

  test('a season of sections alone orders them from 0', () {
    final sections = PgcInfoModel(
      sections: [
        Section(episodes: [_ep(11)]),
        Section(episodes: [_ep(21)]),
      ],
    );
    expect(
      DownloadService.seasonOrder(sections, _ep(21), 0),
      greaterThan(DownloadService.seasonOrder(sections, _ep(11), 0)),
    );
  });
}
