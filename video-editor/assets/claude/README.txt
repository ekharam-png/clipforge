The Claude extension file that the desktop app carries.

The build workflow puts ClipForge-claude.mcpb here before `flutter build`
(Windows and macOS): it is the Claude Desktop extension, a zip with the
Claude helper (clipforge-mcp), the title fonts and a manifest. The app

  - installs the helper from it into the per-user folder on every start
    (Windows: %LOCALAPPDATA%\ClipForge\claude, macOS:
    ~/Library/Application Support/ClipForge/claude), and
  - saves it as a file from Help > Connect to Claude.

The .mcpb itself is not kept in the repository (see .gitignore). To try it
on a development computer:

  dart run bin/build_mcp.dart
  python3 docs/tools/build_claude_bundles.py mcpb --binary build/mcp/clipforge-mcp \
      --platform linux --out build/mcpb --asset assets/claude
