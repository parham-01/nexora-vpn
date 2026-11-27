import 'package:flutter/material.dart';

import 'nexora_logo.dart';
import 'store.dart';
import 'widgets.dart';

/// انتخاب نام قبل از ورود به برنامه (فقط وقتی هنوز نامی ذخیره نشده)
class NamePage extends StatefulWidget {
  final VoidCallback onDone;
  const NamePage({super.key, required this.onDone});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final TextEditingController _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _c.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    await Store.setUserName(t);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final ok = _c.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: p.bg,
      body: AppBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Brand(size: 78),
                      const SizedBox(width: 12),
                      NexoraWordmark(fontSize: 26, textColor: p.text),
                    ]),
                  ),
                  const SizedBox(height: 36),
                  Text('خوش اومدی 👋', style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('قبل از ورود، یه اسم برای خودت انتخاب کن', textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 14.5)),
                  const SizedBox(height: 26),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: TextField(
                      controller: _c,
                      autofocus: false,
                      maxLength: 24,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'نام شما',
                        hintStyle: TextStyle(color: p.sub.withOpacity(0.7)),
                        prefixIcon: Icon(Icons.person_rounded, color: p.accent2),
                        filled: true,
                        fillColor: p.card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: p.border.withOpacity(0.4))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: p.border.withOpacity(0.4))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: p.accent2, width: 1.6)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        disabledBackgroundColor: p.card,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: ok && !_busy ? _submit : null,
                      child: const Text('ورود به برنامه', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
