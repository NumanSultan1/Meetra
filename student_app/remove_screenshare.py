import re

with open('lib/features/meeting_screen.dart', 'r') as f:
    content = f.read()

# Remove variable declarations
content = re.sub(r'^\s*bool _isScreenSharing = false;\n?', '', content, flags=re.MULTILINE)
content = re.sub(r'^\s*bool _screenShareDisabledAll = false;\n?', '', content, flags=re.MULTILINE)
content = re.sub(r'^\s*MediaStream\? _screenStream;\n?', '', content, flags=re.MULTILINE)

# Remove map entries
content = re.sub(r"^\s*'screenShareDisabledAll': false,\n?", "", content, flags=re.MULTILINE)
content = re.sub(r"^\s*'screenSharing': _isScreenSharing,\n?", "", content, flags=re.MULTILINE)
content = re.sub(r"^\s*'screenSharing': false,\n?", "", content, flags=re.MULTILINE)

# Remove _setScreenSharing
content = re.sub(r'^\s*void _setScreenSharing\(bool value\) \{.*?\n\s*\}\n?', '', content, flags=re.MULTILINE | re.DOTALL)

# Remove the whole screen share logic block (_toggle, _start, _stop)
# We will match from Future<void> _toggleScreenSharing() down to the end of _stopScreenSharing()
content = re.sub(r'^\s*Future<void> _toggleScreenSharing\(\) async \{.*?(?=^\s*Future<void> _setupWebrtc|^\s*Future<void> _setupChat)', '', content, flags=re.MULTILINE | re.DOTALL)

# Remove _adminToggleScreenShareLock
content = re.sub(r'^\s*Future<void> _adminToggleScreenShareLock\(\) async \{.*?(?=^\s*void _disconnect)', '', content, flags=re.MULTILINE | re.DOTALL)

# Let's just do more targeted replacements
with open('lib/features/meeting_screen.dart', 'w') as f:
    f.write(content)
