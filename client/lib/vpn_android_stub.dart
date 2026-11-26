typedef AndroidStatusCb = void Function(String state, int up, int down, int upSpeed, int downSpeed, String duration);

class AndroidVpn {
  bool get supported => false;

  Future<void> init(AndroidStatusCb cb) async {}

  Future<bool> start(String link, String remark, Map<String, dynamic> outbound, {List<String> dns = const []}) async => false;

  Future<void> stop() async {}

  Future<int> delay(String link, Map<String, dynamic> outbound) async => -1;
}
