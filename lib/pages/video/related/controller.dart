import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class RelatedController
    extends CommonListController<List<HotVideoItemModel>?, HotVideoItemModel> {
  RelatedController({this.autoQuery = true, this.showAfter});
  String bvid = Get.arguments['bvid'];
  final bool autoQuery;

  /// What the list waits for before it shows what it loaded, as the video
  /// page's opening.
  final ValueGetter<Future<void>?>? showAfter;

  @override
  void onInit() {
    super.onInit();
    if (autoQuery) {
      queryData();
    }
  }

  @override
  Future<LoadingState<List<HotVideoItemModel>?>> customGetData() async {
    final bvid = this.bvid;
    final res = await VideoHttp.relatedVideoList(bvid: bvid);
    await showAfter?.call();
    // A video switched to meanwhile has related videos of its own.
    if (bvid != this.bvid) {
      return customGetData();
    }
    return res;
  }
}
