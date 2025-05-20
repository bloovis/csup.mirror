# Customizing Key Bindings

The default key bindings can be modified by adding entries to
`~/.csup/keymap.yaml`. This file does not exist and must be created by the
user.  Only overridden or new values need to be added to `keymap.yaml`.
Key bindings can only be set for existing commands in the various modes
in Csup; you cannot create new commands.  Also, it's not currently
possible to create bindings that require multiple keystrokes, such as
those used in thread view mode for the `,` and `]` prefixes.

Here is a sample `colors.yaml` that adds some key bindings for ScrollMode,
and one key binding for the global keymap.

```
ScrollMode:
  page_down:
    - "C-v"
  page_up:
    - "C-z"
  jump_to_start:
    - "M-<"
  jump_to_end:
    - "M->"
global:
  kill_buffer:
    - "C-w"
```

## Display Current Bindings

To display all the current bindings (except for the ones using
multiple keystrokes), use the `C-k` (Display keymaps) command
in Csup.  You can use the resulting text as a template for `keymap.yaml`.

## Key Names

Key names in Csup differ from key names in Sup in that they are always
strings:

* Ordinary alphanumeric keys: "a" through "z", "A" through "Z", "0" through "9"
* Control keys: "C-x" means holding down Ctrl while pressing x
* Meta keys: "M-x" means holding down Alt while pressing x
* Control Meta keys: "C-M-x" means holding down Ctrl and Alt while pressing x
* Function keys: "F1" through "F20"
* Timeout: "ERR"
* Single mouse click: "click"
* Double mouse click: "doubleclick"
* Special commonly used keys: "Enter", "Tab", "Space", "Down", "Left", "Right", "PgUp", "PgDn", "Home", "End",
"Insert", "Delete"
