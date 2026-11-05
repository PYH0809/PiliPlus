import 'package:PiliPlus/common/widgets/liquid_glass/static_frost.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('takes the page under a route, blurred, where it lies', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ColoredBox(key: Key('page'), color: Colors.blue),
        ),
      ),
    );
    final route = ModalRoute.of(tester.element(find.byKey(const Key('page'))))!;
    const screen = Size(800, 600);
    final picture = StaticFrostPicture.take(
      route,
      const ColorScheme.light(),
      screen,
    );
    expect(picture, isNotNull);
    expect(picture!.rect, Offset.zero & screen);
    expect(picture.screen, screen);
    expect(picture.brightness, Brightness.light);
    // A few texels a dp: the blur hides the rest.
    expect(picture.image!.width, 400);
    picture.drop();
    expect(picture.image, isNull);

    expect(
      StaticFrostPicture.take(null, const ColorScheme.light(), screen),
      isNull,
    );
  });

  testWidgets('a turned screen or another theme leaves only the tint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ColoredBox(key: Key('page'), color: Colors.blue),
        ),
      ),
    );
    final route = ModalRoute.of(tester.element(find.byKey(const Key('page'))))!;
    Future<StaticFrostPicture> frost(
      Brightness brightness, {
      StaticFrostPicture? picture,
    }) async {
      picture ??= StaticFrostPicture.take(
        route,
        const ColorScheme.light(),
        tester.view.physicalSize / tester.view.devicePixelRatio,
      )!;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: StaticFrost(
            picture: picture,
            radius: 24,
            child: const SizedBox(width: 80, height: 160),
          ),
        ),
      );
      // The theme eases from one to the other.
      await tester.pumpAndSettle();
      return picture;
    }

    final picture = await frost(Brightness.light);
    final image = picture.image!;
    expect(image.debugDisposed, isFalse);
    // The pane going, as it does as the screen turns, leaves the picture to
    // its route.
    await tester.pumpWidget(const SizedBox());
    expect(image.debugDisposed, isFalse);
    // Back in another theme, the picture shows the page no more.
    await frost(Brightness.dark, picture: picture);
    expect(image.debugDisposed, isTrue);
    expect(picture.image, isNull);
  });
}
