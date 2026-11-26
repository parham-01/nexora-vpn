import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// حل خودکار و بی‌صدای کپچای Mozilla/Fastly.
///
/// هر پلتفرم از OCR خودش استفاده می‌کند:
///  - اندروید: ML Kit (روی دستگاه، بدون اینترنت)
///  - ویندوز: OCR داخلی ویندوز (Windows.Media.Ocr از طریق PowerShell)
///  - لینوکس/مک: برنامه‌ی tesseract اگر نصب باشد
///
/// [solve] هیچ‌وقت خطا پرت نمی‌کند: اگر چیزی درست پیش نرفت (پلتفرم پشتیبانی نمی‌شود،
/// OCR نبود، زمان تمام شد، متن نامعتبر بود) فقط null برمی‌گرداند و صفحه‌ی ورود
/// بدون هیچ پیام اضافه‌ای کپچا را به کاربر نشان می‌دهد.
abstract final class CaptchaAutoSolver {
  static const Duration _timeout = Duration(seconds: 12);

  /// [dataUrl]: همان `data:image/...;base64,` که هسته می‌دهد.
  static Future<String?> solve(String dataUrl) async {
    try {
      return await _solve(dataUrl).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _solve(String dataUrl) async {
    final head = dataUrl.length > 40 ? dataUrl.substring(0, 40).toLowerCase() : dataUrl.toLowerCase();
    if (head.contains('svg')) return null; // قابل دیکد نیست؛ دستی
    final i = dataUrl.indexOf('base64,');
    if (i < 0) return null;
    final raw = base64Decode(dataUrl.substring(i + 7));
    if (raw.isEmpty) return null;

    // عکس روی زمینه‌ی سفید، بزرگ‌تر و با حاشیه: OCR روی این حالت بهتر می‌خواند.
    final png = await _prepare(raw) ?? raw;

    String? text;
    if (Platform.isAndroid) {
      text = await _androidMlKit(png);
    } else if (Platform.isWindows) {
      text = await _windowsOcr(png);
    } else if (Platform.isLinux || Platform.isMacOS) {
      text = await _tesseract(png);
    }
    return _clean(text);
  }

  /// فقط حروف/ارقام؛ طول نامعقول یعنی خواندن شکست خورده.
  static String? _clean(String? text) {
    if (text == null) return null;
    final s = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (s.length < 3 || s.length > 10) return null;
    return s;
  }

  static Future<Uint8List?> _prepare(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      const scale = 2.5;
      const pad = 24.0;
      final w = img.width * scale + pad * 2;
      final h = img.height * scale + pad * 2;
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromLTWH(pad, pad, img.width * scale, img.height * scale),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final out = await rec.endRecording().toImage(w.round(), h.round());
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<File> _tmp(Uint8List png, String ext) async {
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}nx_cap_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await f.writeAsBytes(png, flush: true);
    return f;
  }

  static Future<void> _rm(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------------------------- اندروید ----------------------------
  static Future<String?> _androidMlKit(Uint8List png) async {
    final file = await _tmp(png, 'png');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return result.text;
    } finally {
      await recognizer.close();
      await _rm(file);
    }
  }

  // ---------------------------- ویندوز ----------------------------
  static const String _psScript = r'''
param([string]$ImagePath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, $type) {
  $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
  $null = $task.Wait(-1)
  $task.Result
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US'))
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($null -eq $engine) { exit 3 }
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
[Console]::Out.Write($result.Text)
''';

  static Future<String?> _windowsOcr(Uint8List png) async {
    final img = await _tmp(png, 'png');
    final script = File('${img.path}.ps1');
    try {
      await script.writeAsString(_psScript, flush: true);
      final p = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-ImagePath',
        img.path,
      ]);
      final out = p.stdout.transform(utf8.decoder).join();
      unawaited(p.stderr.drain<void>());
      final code = await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
        p.kill();
        return -1;
      });
      if (code != 0) return null;
      return await out;
    } finally {
      await _rm(img);
      await _rm(script);
    }
  }

  // ------------------------ لینوکس / مک (tesseract) ------------------------
  static Future<String?> _tesseract(Uint8List png) async {
    final img = await _tmp(png, 'png');
    try {
      final r = await Process.run('tesseract', [
        img.path,
        'stdout',
        '--psm',
        '7',
        '-c',
        'tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',
      ]).timeout(const Duration(seconds: 8));
      if (r.exitCode != 0) return null;
      return r.stdout.toString();
    } finally {
      await _rm(img);
    }
  }
}
