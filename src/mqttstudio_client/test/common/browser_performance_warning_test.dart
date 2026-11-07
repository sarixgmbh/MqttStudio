import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/common/browser_performance_warning.dart';
import 'package:srx_flutter/srx_flutter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import '../helpers/test_app.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late _FakeUrlLauncher launcher;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTranslations();
  });

  setUp(() {
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    GetIt.I.registerSingleton(SrxNavigationService(Container(), Container()));
  });
  tearDown(GetIt.I.reset);

  Future<void> tapDownload(WidgetTester tester) async {
    await ignoringOverflowErrors(() async {
      await tester.pumpWidget(testApp(BrowserPerformanceWarning()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOWNLOAD DESKTOP CLIENT'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('a Mac downloads the macOS app', (tester) async {
    await tapDownload(tester);
    expect(launcher.launched, [BrowserPerformanceWarning.macDownloadUrl]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('other systems open the Microsoft Store', (tester) async {
    await tapDownload(tester);
    expect(launcher.launched, [BrowserPerformanceWarning.microsoftStoreUrl]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
