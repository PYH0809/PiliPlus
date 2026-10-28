import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/main.dart';
import 'package:PiliPlus/plugin/linux_webview.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, dynamic>?> geetest(String gt, String challenge) {
    return showDialog<Map<String, dynamic>>(
      context: Get.context!,
      builder: (context) => GeetestWebviewDialog(gt, challenge),
    );
  }

  /// Geetest v4, which the app's SMS login hands out when its `recaptcha_url`
  /// has `ct=geetest4`: [captchaId] is that url's `gee_gt`. It returns
  /// `lot_number`, `captcha_output`, `pass_token` and `gen_time`.
  static Future<Map<String, dynamic>?> geetest4(String captchaId) {
    return showDialog<Map<String, dynamic>>(
      context: Get.context!,
      builder: (context) => _Geetest4WebviewDialog(captchaId),
    );
  }
}

class _Geetest4WebviewDialog extends GeetestWebviewDialog {
  const _Geetest4WebviewDialog(String captchaId) : super(captchaId, '');
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _geetestConfigUri = 'https://api.geetest.com/gettype.php';
  static const _geetest4JsUri = 'https://static.geetest.com/v4/gt4.js';

  static String _buildHtml(String gt, String challenge, {bool v4 = false}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Says why the captcha did not come up, rather than leaving the page blank.
    const showError =
        'E=m=>{document.getElementById("E").textContent="验证码加载失败"+(m?"："+m:"");R("error",m||"geetest script load failed")}';
    final js = v4
        ? 'onerror=m=>E(m);'
              'G=()=>initGeetest4({captchaId:"$gt",product:"bind",language:"zho",https:true,protocol:"https://"},c=>c.onReady(()=>c.showCaptcha()).onSuccess(()=>R("success",c.getValidate())).onError(o=>E(o&&o.msg)).onClose(o=>R("close",o)));'
              '$showError'
        : 'var C,S,T,t;'
              'T=()=>{if(C&&S&&!t){t=Geetest(C).onSuccess(()=>R("success",t.getValidate())).onError(o=>E(o&&(o.user_error||o.msg))).onClose(o=>R("close",o));t.onReady(()=>t.verify())}};'
              'geetest_$ts=(d)=>{'
              'if(!d||d.status!="success"){E(d&&d.error);return};'
              'C=Object.assign({gt:"$gt",challenge:"$challenge",offline:false,new_captcha:true,product:"bind",width:"100%",https:true,protocol:"https://"},d.data);T()'
              '};'
              'G=()=>{S=1;T()};'
              '$showError';
    final scripts = v4
        ? '<script src="$_geetest4JsUri" onload="G()" onerror="E()"></script>'
        : '<script src="$_geetestJsUri" onload="G()" onerror="E()"></script>'
              '<script src="$_geetestConfigUri?gt=$gt&callback=geetest_$ts" onerror="E()"></script>';

    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width"></head>'
        '<style>#E{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:red}</style>'
        '<body><div id="E"></div>'
        '<script>'
        '${Platform.isLinux ? "R=(n,o)=>window.webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))" : "R=(n,o)=>window.flutter_inappwebview?.callHandler(n,o)"};$js'
        '</script>'
        '$scripts'
        '</body></html>';
  }

  @override
  Widget build(BuildContext context) {
    final html = _buildHtml(
      widget.gt,
      widget.challenge,
      v4: widget is _Geetest4WebviewDialog,
    );

    if (Platform.isLinux) {
      return AlertDialog(
        title: const Text('验证码'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: LinuxWebview(
            initialHtml: html,
            userAgent: BrowserUa.mob,
            incognito: true,
            onWebMessageReceived: (msg) {
              final msgStr = msg.toString();
              if (msgStr.startsWith("success:")) {
                final dataStr = msgStr.substring("success:".length);
                try {
                  final data = jsonDecode(dataStr);
                  Get.back(result: data);
                } catch (e) {
                  debugPrint('geetest decode error: $e');
                }
              } else if (msgStr.startsWith("error:")) {
                debugPrint('geetest error: $msgStr');
              } else if (msgStr.startsWith('close:')) {
                Get.back();
              }
            },
          ),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            clearCache: true,
            javaScriptEnabled: true,
            forceDark: ForceDark.AUTO,
            useHybridComposition: true,
            algorithmicDarkeningAllowed: true,
            useShouldOverrideUrlLoading: true,
            userAgent: BrowserUa.mob,
            mixedContentMode: .MIXED_CONTENT_ALWAYS_ALLOW,

            incognito: true,
            allowFileAccess: false,
            allowsLinkPreview: false,
            allowContentAccess: false,
            useOnDownloadStart: false,
            geolocationEnabled: false,
            thirdPartyCookiesEnabled: false,
            enterpriseAuthenticationAppLinkPolicyEnabled: false,
            saveFormData: false,
            safeBrowsingEnabled: false,
            isFraudulentWebsiteWarningEnabled: false,
            domStorageEnabled: false,
            databaseEnabled: false,
            cacheEnabled: false,
            cacheMode: .LOAD_NO_CACHE,

            horizontalScrollBarEnabled: false,
            verticalScrollBarEnabled: false,
            overScrollMode: .NEVER,

            pageZoom: Platform.isIOS ? 3 : 1,
          ),
          initialData: InAppWebViewInitialData(data: html),
          onWebViewCreated: (ctr) {
            ctr
              ..addJavaScriptHandler(
                handlerName: 'success',
                callback: (args) {
                  if (args.isNotEmpty) {
                    if (args[0] case Map<String, dynamic> data) {
                      Get.back(result: data);
                      return;
                    }
                  }
                  debugPrint('geetest invalid result: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'error',
                callback: (args) {
                  debugPrint('geetest error: $args');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'close',
                callback: (args) => Get.back(),
              );
          },
        ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: Get.back,
            tooltip: '关闭',
          ),
        ),
      ],
    );
  }
}
