import 'package:flutter/material.dart';
import 'comic_list_page.dart';
import 'video_home_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _showSuggestions = true;

  static const String _password = '795531';
  static const String _videoPassword = '8012';

  void _onSend(String text) {
    final input = text.trim();
    if (input.isEmpty) return;

    // Password check first - don't show in chat
    if (input == _password) {
      _inputController.clear();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ComicListPage()),
        );
      });
      return;
    }
    if (input == _videoPassword) {
      _inputController.clear();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VideoHomePage()),
        );
      });
      return;
    }

    setState(() {
      _showSuggestions = false;
      _messages.add(_ChatMessage(text: input, isUser: true));
    });
    _inputController.clear();

    Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage(
            text: '⚠️ 网络连接失败，请检查网络后重试',
            isUser: false,
          ));
        });
      });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _messages.isEmpty && _showSuggestions
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _buildChatBubble(msg);
                      },
                    ),
            ),
            if (_messages.isEmpty && _showSuggestions) _buildSuggestions(),
            _buildBottomInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F0F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu, size: 20, color: Color(0xFF333333)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Color(0xFF7C3AED)),
                SizedBox(width: 4),
                Text('升级', style: TextStyle(fontSize: 13, color: Color(0xFF333333), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F0F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF333333)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      ('关注世界杯', Icons.sports_soccer_outlined),
      ('生成图片', Icons.image_outlined),
      ('查找资料', Icons.description_outlined),
      ('选择一个项目', Icons.folder_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: suggestions.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(item.$2, size: 18, color: const Color(0xFF999999)),
                const SizedBox(width: 12),
                Text(item.$1, style: const TextStyle(fontSize: 14, color: Color(0xFF666666))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: msg.isUser ? const Color(0xFFF0F0F0) : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12).copyWith(
                  bottomRight: msg.isUser ? const Radius.circular(4) : null,
                  bottomLeft: !msg.isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  color: msg.isUser ? const Color(0xFF333333) : const Color(0xFFE65100),
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (msg.isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBottomInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, size: 22, color: Color(0xFF333333)),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      decoration: const InputDecoration(
                        hintText: '询问 ChatGPT',
                        hintStyle: TextStyle(color: Color(0xFFBBBBBB), fontSize: 15),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _onSend,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.mic_none, size: 22, color: Color(0xFF333333)),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _onSend(_inputController.text),
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF3B82F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waves, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
