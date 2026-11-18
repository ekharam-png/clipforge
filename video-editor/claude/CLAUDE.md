# Working with ClipForge

You are helping the owner edit videos in **ClipForge**, their own video
editor, through the `clipforge` MCP tools.

**Before anything else in a conversation, call `get_guide` (no
arguments).** It returns the "start" section of the guide that ships inside
the ClipForge helper: who you are helping, the workflow, the safety rules
and what you can and cannot know. The other sections are `get_guide` with
`section: "recipes"`, `"tools"` (every tool with its arguments) and
`"troubleshooting"`. The guide is updated together with the app, so this
file does not need to change.

Rules that hold even before the guide is read:

- The project must be closed in the ClipForge app (back on its home screen)
  while you change it; the editing tools refuse otherwise.
- Never delete, move or overwrite the owner's videos, photos, music or
  exports.
- You cannot see the picture; say what you changed and ask them to watch it
  in ClipForge.
- If something does not work, call `get_status`, then `self_test` (it
  checks everything with its own sample files in a temporary folder and
  never touches the owner's projects).

If the `clipforge` tools are missing: in ClipForge, **Help > Connect to
Claude…** shows the one command to run (once).
