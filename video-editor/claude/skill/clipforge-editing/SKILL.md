---
name: clipforge-editing
description: Edit videos in ClipForge (the owner's own video editor) through the clipforge MCP tools. Use whenever the user mentions ClipForge or asks to edit, cut, trim, shorten, clean up, caption, title, add music to, resize, make vertical, make shorts from, or export a video, podcast, family video or sport clip on their computer, even with typos ("clipforge", "clip forge", "edit my vidoe", "remove silnces", "make a short").
---

# Editing videos with ClipForge

ClipForge is the owner's video editor (Windows, Mac, Android). On a computer
the `clipforge` tools change the same project files the app opens.

**Before anything else in a conversation, call the `get_guide` tool of the
`clipforge` tools (no arguments).** It returns the "start" section of the
guide: who you are helping, the workflow, the safety rules and what you can
and cannot know. Follow it. The other sections are read only when needed:

- `get_guide` with `section: "recipes"`: step-by-step for the usual jobs
  (podcast clean-up, music, family montage, sport, upright version, shorts,
  captions, filler words, sound only).
- `get_guide` with `section: "tools"`: every tool with its arguments.
- `get_guide` with `section: "troubleshooting"`: when something does not
  work.

The guide lives inside the ClipForge helper and is updated together with
the app, so this skill never needs to be uploaded again.

If the `clipforge` tools are not there at all, ClipForge is not connected
to this Claude yet. Tell the owner: open ClipForge on the computer, then
**Help > Connect to Claude…** and follow the two steps there (it needs
doing only once). The tools work on a computer (Windows or Mac) with Claude
Desktop or Claude Code, not on the phone and not in claude.ai in a web
browser.

Three rules that hold even before the guide is read:

- The project must be closed in the ClipForge app (back on its home screen)
  while you change it.
- Never delete, move or overwrite the owner's videos, photos, music or
  exports.
- You cannot see the picture; say what you changed and ask them to watch it
  in ClipForge.
