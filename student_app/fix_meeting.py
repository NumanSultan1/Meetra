import re

with open('lib/features/meeting_screen.dart', 'r') as f:
    lines = f.readlines()

out = []
skip_until = -1
for i, line in enumerate(lines):
    if i < skip_until:
        continue
    
    # 187: final screenShareLock = data['screenShareDisabledAll'] == true;
    # 189: if (screenShareLock != _screenShareDisabledAll) {
    # 191:   if (screenShareLock && _isScreenSharing) {
    if "final screenShareLock =" in line or "screenShareDisabledAll" in line or "screenSharing" in line or "_setScreenSharing" in line or "_screenStream" in line or "_isScreenSharing" in line or "_toggleScreenSharing" in line:
        continue
    
    out.append(line)

with open('lib/features/meeting_screen.dart', 'w') as f:
    f.writelines(out)
