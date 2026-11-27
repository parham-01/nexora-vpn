typedef AndroidStatusCb = void Function(String state, int up, int down, int upSpeed, int downSpeed, String duration);

// نسخه‌ی خالی برای دسکتاپ (ویندوز / لینوکس / مک)؛ API باید دقیقاً با vpn_android.dart یکی باشد.
class AndroidVpn {
  bool get supported => false;

  static String get packageName => '';
  static String? get nativeLibDir => null;
  static String? get singboxPath => null;

  Future<void> init(AndroidStatusCb cb) async {}

  Future<bool> start(String link, String remark, Map<String, dynamic> outbound, {List<String> dns = const [], int profile = 0}) async => false;

  Future<bool> startChain(String remark, int socksPort, {List<String> dns = const []}) async => false;

  Future<void> stop() async {}

  Future<int> delay(String link, Map<String, dynamic> outbound, {List<String> dns = const []}) async => -1;
}
