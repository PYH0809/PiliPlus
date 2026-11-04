// <os>.json，CI 在一个平台的安装包全部传完后上传到 Release，
// 见 lib/scripts/release_manifest.ps1
class UpdateManifest {
  final String tag;
  final int versionCode;
  final String body;
  final List<UpdateAsset> assets;
  // 发版时间；早先的清单没有
  final DateTime? date;
  // 上一个发布的版本的 tag，用来比较这一版的提交；早先的清单没有
  final String? previousTag;

  const UpdateManifest({
    required this.tag,
    required this.versionCode,
    required this.body,
    required this.assets,
    this.date,
    this.previousTag,
  });

  // 缺字段或类型不对时抛 FormatException
  factory UpdateManifest.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('not an object');
    final tag = json['tag'];
    final versionCode = json['versionCode'];
    final assets = json['assets'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('no tag');
    }
    if (versionCode is! int) throw const FormatException('no versionCode');
    if (assets is! List) throw const FormatException('no assets');
    return UpdateManifest(
      tag: tag,
      versionCode: versionCode,
      body: json['body'] as String? ?? '',
      assets: [for (final i in assets) UpdateAsset.fromJson(i)],
      date: switch (json['date']) {
        final String date => DateTime.tryParse(date)?.toLocal(),
        _ => null,
      },
      previousTag: switch (json['previousTag']) {
        final String tag when tag.isNotEmpty => tag,
        _ => null,
      },
    );
  }
}

class UpdateAsset {
  final String name;
  final int size;
  // 小写十六进制
  final String sha256;
  // 安卓的包有 abi，其他平台的有 format（zip、exe、tar.gz...）
  final String? abi;
  final String? format;

  const UpdateAsset({
    required this.name,
    required this.size,
    required this.sha256,
    this.abi,
    this.format,
  });

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  factory UpdateAsset.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('asset is not an object');
    final name = json['name'];
    final size = json['size'];
    final sha256 = json['sha256'];
    if (name is! String || name.isEmpty || name.contains('/')) {
      throw const FormatException('bad asset name');
    }
    if (size is! int || size <= 0) {
      throw FormatException('bad size of $name');
    }
    if (sha256 is! String || !_sha256.hasMatch(sha256.toLowerCase())) {
      throw FormatException('bad sha256 of $name');
    }
    return UpdateAsset(
      name: name,
      size: size,
      sha256: sha256.toLowerCase(),
      abi: switch (json['abi']) {
        final String abi => abi,
        _ => null,
      },
      format: switch (json['format']) {
        final String format => format,
        _ => null,
      },
    );
  }
}
