import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/misc.dart';
import '../network/ws_client.dart';
import '../network/ws_events.dart';
import '../repositories/repositories.dart';
import '../services/upload_service.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import '../utils/time.dart';
import 'common.dart';

class ChatArgs {
  const ChatArgs({required this.jobId, required this.title, this.readOnly = false});
  final String jobId;
  final String title;

  /// Finished jobs: show history only.
  final bool readOnly;
}

/// Customer <-> rider chat for one job (REST history + `chat.message` events).
class ChatController extends GetxController {
  final ChatRepository repo = Get.find();
  final GoWsClient ws = Get.find();
  late final ChatArgs args;
  final messages = <ChatMessage>[].obs;
  final loading = true.obs;
  final sending = false.obs;
  final error = Rxn<Object>();
  final text = TextEditingController();
  final scroll = ScrollController();
  StreamSubscription<WsEvent>? _sub;
  StreamSubscription<void>? _reSub;

  PartyRole get me => AppConfig.current.app == GoApp.rider ? PartyRole.rider : PartyRole.customer;

  @override
  void onInit() {
    super.onInit();
    args = Get.arguments as ChatArgs;
    _sub = ws.events.listen((e) {
      if (e is ChatMessageEvent && e.message.jobId == args.jobId) _add(e.message);
    });
    _reSub = ws.reconnected.listen((_) => load());
    load();
  }

  Future<void> load() async {
    loading.value = messages.isEmpty;
    error.value = null;
    try {
      final all = <ChatMessage>[];
      String? cursor;
      do {
        final page = await repo.messages(args.jobId, cursor: cursor);
        all.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null && all.length < 500);
      all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messages.assignAll(all);
      _toBottom();
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  void _add(ChatMessage m) {
    if (messages.any((x) => x.id == m.id)) return;
    messages.add(m);
    _toBottom();
  }

  void _toBottom() => Future<void>.delayed(const Duration(milliseconds: 50), () {
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
  });

  Future<void> sendText() async {
    final t = text.text.trim();
    if (t.isEmpty || sending.value) return;
    sending.value = true;
    try {
      _add(await repo.send(args.jobId, text: t));
      text.clear();
    } catch (e) {
      GoErrors.show(e);
    } finally {
      sending.value = false;
    }
  }

  Future<void> sendPhoto() async {
    final uploads = Get.find<UploadService>();
    try {
      final f = await uploads.pick(camera: false);
      if (f == null) return;
      sending.value = true;
      final key = await uploads.upload(await uploads.compress(f), UploadPurpose.chatImage);
      _add(await repo.send(args.jobId, imageKey: key));
    } catch (e) {
      GoErrors.show(e);
    } finally {
      sending.value = false;
    }
  }

  @override
  void onClose() {
    _sub?.cancel();
    _reSub?.cancel();
    text.dispose();
    scroll.dispose();
    super.onClose();
  }
}

class ChatBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(ChatController.new);
}

class ChatView extends GetView<ChatController> {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text(c.args.title)),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              if (c.loading.value) return const LoadingState();
              if (c.error.value != null && c.messages.isEmpty) return ErrorState(error: c.error.value!, onRetry: c.load);
              if (c.messages.isEmpty) return EmptyState(icon: Icons.chat_bubble_outline, message: 'chat.empty'.tr);
              return ListView.builder(
                controller: c.scroll,
                padding: const EdgeInsets.all(12),
                itemCount: c.messages.length,
                itemBuilder: (_, i) => _Bubble(message: c.messages[i], mine: c.messages[i].sender == c.me),
              );
            }),
          ),
          if (!c.args.readOnly)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: c.sendPhoto, icon: const Icon(Icons.photo_outlined)),
                    Expanded(
                      child: TextField(
                        controller: c.text,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => c.sendText(),
                        decoration: InputDecoration(hintText: 'chat.hint'.tr),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Obx(
                      () => IconButton.filled(
                        onPressed: c.sending.value ? null : c.sendText,
                        icon: c.sending.value
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (message.sender == PartyRole.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            message.text ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: GoColors.muted, fontSize: 12),
          ),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(color: mine ? GoColors.primary : GoColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageUrl != null) GoImage(message.imageUrl, width: 200, height: 200, radius: 8),
            if (message.text != null) Text(message.text!, style: TextStyle(color: mine ? Colors.white : GoColors.ink)),
            const SizedBox(height: 2),
            Text(formatManilaTime(message.createdAt), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : GoColors.muted)),
          ],
        ),
      ),
    );
  }
}
