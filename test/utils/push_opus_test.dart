import 'dart:io';

import 'package:PiliPlus/models/common/dynamic/article_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-push-opus-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  tearDown(Get.reset);

  // The article page reads its id and type from the route's arguments, as
  // ArticlePage.toArticlePage passes them.
  testWidgets('an opus dynamic opens the article page with its arguments', (
    tester,
  ) async {
    Object? arguments;
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SizedBox.shrink(),
        getPages: [
          GetPage(
            name: '/articlePage',
            page: () {
              arguments = Get.arguments;
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );

    final item = DynamicItemModel.fromJson({
      'id_str': '1234',
      'basic': {'comment_type': 12, 'comment_id_str': '1234'},
    });
    PageUtils.pushDynDetail(item, isPush: true, viewComment: true);
    await tester.pumpAndSettle();

    expect(arguments, isA<Map>());
    final map = arguments! as Map;
    expect(map['id'], '1234');
    expect(map['type'], ArticleType.opus);
    expect(map['viewComment'], isTrue);
  });
}
