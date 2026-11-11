import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../data/social_repository.dart';
import '../domain/group_message.dart';

final _messagesProvider = StreamProvider.autoDispose
    .family<List<GroupMessage>, (ChatParent, String)>(
      (ref, key) => ref
          .watch(socialRepositoryProvider)
          .streamChatMessages(parent: key.$1, parentId: key.$2),
    );

class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.parent,
    required this.parentId,
    required this.title,
  });

  final ChatParent parent;
  final String parentId;
  final String title;

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    final profile = await ref
        .read(socialRepositoryProvider)
        .getProfile(user.uid);
    _controller.clear();

    await ref
        .read(socialRepositoryProvider)
        .sendChatMessage(
          parent: widget.parent,
          parentId: widget.parentId,
          message: GroupMessage(
            id: const Uuid().v4(),
            uid: user.uid,
            displayName:
                profile?.displayName ??
                user.email?.split('@').first ??
                'Explorer',
            text: text,
            timestamp: DateTime.now(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      _messagesProvider((widget.parent, widget.parentId)),
    );
    final myUid = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Padding(
                padding: AppSpacing.page,
                child: Shimmer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 200, height: 44, radius: 18),
                      SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SkeletonBox(width: 160, height: 44, radius: 18),
                      ),
                      SizedBox(height: 12),
                      SkeletonBox(width: 240, height: 44, radius: 18),
                    ],
                  ),
                ),
              ),
              error: (error, stack) => Padding(
                padding: AppSpacing.page,
                child: EmptyStateCard(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load chat',
                  message: '$error',
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Padding(
                    padding: AppSpacing.page,
                    child: EmptyStateCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      message: 'No messages yet. Say hi!',
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: AppSpacing.page,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.uid == myUid;
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          color: isMine
                              ? AppTheme.forest
                              : Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMine ? 20 : 6),
                            bottomRight: Radius.circular(isMine ? 6 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.forest.withValues(alpha: 0.10),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  message.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: AppTheme.primaryGreen,
                                  ),
                                ),
                              ),
                            Text(
                              message.text,
                              style: TextStyle(
                                color: isMine ? Colors.white : AppTheme.ink,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.forest.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Message the group...',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton.filled(
                        icon: const Icon(Icons.send_rounded, size: 20),
                        tooltip: 'Send',
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.forest,
                        ),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
