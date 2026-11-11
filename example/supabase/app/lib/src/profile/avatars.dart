import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';

/// The bucket `avatars` of the project. Both paths are the signed-in
/// user's own folder (`authentication.name` is their id, SpEL as in
/// `@PreAuthorize`), which is also all the policies of the bucket let
/// them read and write.
@StorageBucket('avatars')
abstract interface class Avatars {
  @Upload(
    '#{authentication.name}/avatar.png',
    contentType: 'image/png',
    upsert: true,
  )
  Future<void> put(Uint8List png);

  /// `null` while the user has none.
  @Download('#{authentication.name}/avatar.png')
  Future<Uint8List?> mine();
}

/// Draws an avatar: a disc of a colour with a letter on it. The example
/// has no file picker (a plugin of its own); it makes its pictures.
@Component()
class AvatarPainter {
  static const _size = 128.0;

  /// A PNG of [letter] on [color].
  Future<Uint8List> paint(String letter, ui.Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawCircle(
        const ui.Offset(_size / 2, _size / 2),
        _size / 2,
        ui.Paint()..color = color,
      );
    final text =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: ui.TextAlign.center,
                  fontSize: _size / 2,
                ),
              )
              ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
              ..addText(letter))
            .build()
          ..layout(const ui.ParagraphConstraints(width: _size));
    canvas.drawParagraph(text, ui.Offset(0, (_size - text.height) / 2));
    final image = await recorder.endRecording().toImage(
      _size.toInt(),
      _size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
