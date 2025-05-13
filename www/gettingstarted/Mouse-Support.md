# Mouse Support

Csup has very basic mouse support.  Enable it by setting `mouse` to `true`
in `~/.csup/config.yaml`:

    mouse: true

If mouse support is enabled, you can move the line cursor
by clicking on a line.  To open the object at a line, double-click on the line.

Enabling mouse support changes the way the windowing system treats the
mouse buttons for cut and paste operations.  To select, cut, or paste
text from/to the window where Csup is running, you will have to hold
down the Shift key while using the mouse buttons.
