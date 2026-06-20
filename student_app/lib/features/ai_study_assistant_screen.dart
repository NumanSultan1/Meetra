import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/theme.dart';

class AIStudyAssistantScreen extends StatefulWidget {
  const AIStudyAssistantScreen({super.key});

  @override
  State<AIStudyAssistantScreen> createState() => _AIStudyAssistantScreenState();
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class _AIStudyAssistantScreenState extends State<AIStudyAssistantScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String _customApiKey = '';

  // Get active API key (from environment variable or user manual input)
  String get _apiKey {
    const envKey = String.fromEnvironment('CLAUDE_API_KEY');
    return envKey.isNotEmpty ? envKey : _customApiKey;
  }

  // Pre-defined study prompt suggestions
  final List<Map<String, String>> _suggestions = [
    {
      'title': 'Explain a Concept',
      'prompt': 'Can you explain the difference between synchronous and asynchronous programming in simple terms?'
    },
    {
      'title': 'Study Schedule',
      'prompt': 'Help me create a 4-week study schedule for an upcoming final exam in Data Structures.'
    },
    {
      'title': 'Generate Quiz',
      'prompt': 'Generate 5 multiple-choice questions with answers to test my knowledge on Flutter and Riverpod.'
    },
    {
      'title': 'Summarize Topic',
      'prompt': 'Provide a summary of key concepts in database normalization (1NF, 2NF, 3NF).'
    },
  ];

  @override
  void initState() {
    super.initState();
    // Add welcome message from Claude
    _messages.add(
      ChatMessage(
        text: "Hi! I am your AI Study Assistant powered by Claude. How can I help you study today?",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    if (_apiKey.isEmpty) {
      setState(() {
        _isLoading = false;
        _messages.add(
          ChatMessage(
            text: "Error: No API key found. Please input your Claude API key in the settings panel at the top of the screen to start chatting.",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    try {
      // Build Anthropic Claude request payload containing the conversation history
      final history = _messages.skip(1).map((msg) {
        return {
          'role': msg.isUser ? 'user' : 'assistant',
          'content': msg.text,
        };
      }).toList();

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-5-sonnet-20241022',
          'max_tokens': 1024,
          'system': 'You are an intelligent, friendly, and expert AI Study Assistant. Help the student understand academic topics, write study guides, explain code, and structure their study time efficiently.',
          'messages': history,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final replyText = data['content'][0]['text'] as String;

        setState(() {
          _messages.add(
            ChatMessage(
              text: replyText,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
      } else {
        final errData = jsonDecode(response.body);
        final errMsg = errData['error']?['message'] ?? 'Unknown API error';
        setState(() {
          _messages.add(
            ChatMessage(
              text: "API Error (${response.statusCode}): $errMsg",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: "Failed to connect to Claude. Please check your internet connection.",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _showApiKeyDialog() {
    _apiKeyController.text = _customApiKey;
    showDialog(
      context: context,
      builder: (context) => PremiumDialog(
        title: 'Claude API Key Settings',
        icon: Icons.key,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your personal Anthropic Claude API Key below. This key will be saved for this session.',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-ant-...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: You can also bake the key into your build permanently using:',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '--dart-define=CLAUDE_API_KEY=your_key',
                style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.amber),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _customApiKey = _apiKeyController.text.trim();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API Key updated successfully.')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyActive = _apiKey.isNotEmpty;

    return RadialBackground(
      child: Column(
        children: [
          // Banner for API Key status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: keyActive ? Colors.green.withOpacity(0.1) : Colors.amber.withOpacity(0.1),
            child: Row(
              children: [
                Icon(
                  keyActive ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  color: keyActive ? Colors.green : Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    keyActive
                        ? 'Claude API connection active'
                        : 'API Key missing. Click Settings to add it.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: keyActive ? Colors.green : Colors.amber,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showApiKeyDialog,
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Settings', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),

          // Messages View
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),

          // Suggestion Cards (only show if conversation is at initial welcome message)
          if (_messages.length == 1 && !_isLoading)
            SizedBox(
              height: 100,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: InkWell(
                      onTap: () => _sendMessage(suggestion['prompt']!),
                      borderRadius: BorderRadius.circular(16),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              suggestion['title']!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              suggestion['prompt']!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Typing Indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Claude is thinking',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryBlue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Input Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B).withOpacity(0.8) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                      decoration: const InputDecoration(
                        hintText: 'Ask a study question...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue,
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: () => _sendMessage(_messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: message.isUser
              ? const LinearGradient(
                  colors: [AppTheme.primaryBlue, Color(0xFF0EA5E9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: message.isUser
              ? null
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: message.isUser ? const Radius.circular(20) : Radius.zero,
            bottomRight: message.isUser ? Radius.zero : const Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                "${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}",
                style: TextStyle(
                  color: message.isUser ? Colors.white60 : Colors.grey.shade500,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
