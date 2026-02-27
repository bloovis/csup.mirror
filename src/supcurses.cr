# This file contains an stripped-down version of the ncurses shard,
# restructured to resemble the Ruby ncurses gem, for sup compatibility.

require "./util"

# Interface to the C ncursesw library.
@[Link("ncursesw")]
lib LibNCurses
  alias Wint_t = Int32
  type Window = Void*

  # Background values
  A_NORMAL = 0x0
  A_REVERSE = 0x40000

  # Keys
  KEY_CANCEL = 0x163
  KEY_CODE_YES = 0x100
  KEY_MOUSE = 0x199
  KEY_ENTER = 0x157
  KEY_BACKSPACE = 0x107
  KEY_UP = 0x103
  KEY_DOWN = 0x102
  KEY_LEFT = 0x104
  KEY_RIGHT = 0x105
  KEY_PPAGE = 0x153
  KEY_NPAGE = 0x152
  KEY_HOME = 0x106
  KEY_END = 0x168
  KEY_IC = 0x14b
  KEY_DC = 0x14a
  KEY_F1 = 0x109
  KEY_F2 = 0x10a
  KEY_F3 = 0x10b
  KEY_F4 = 0x10c
  KEY_F5 = 0x10d
  KEY_F6 = 0x10e
  KEY_F7 = 0x10f
  KEY_F8 = 0x110
  KEY_F9 = 0x111
  KEY_F10 = 0x112
  KEY_F11 = 0x113
  KEY_F12 = 0x114
  KEY_F13 = 0x115
  KEY_F14 = 0x116
  KEY_F15 = 0x117
  KEY_F16 = 0x118
  KEY_F17 = 0x119
  KEY_F18 = 0x11a
  KEY_F19 = 0x11b
  KEY_F20 = 0x11c
  KEY_RESIZE = 0x19a

  @[Flags]
  enum Mouse : LibC::ULong
    Position = 0o2_000_000_000
    B1Clicked = 0o4
    B1DoubleClicked = 0o10
    AllEvents = 0o1_777_777_777
  end

  struct MEVENT
    id : LibC::Short     # ID for each device
    x, y, z : LibC::Int  # Coordinates
    bstate : Mouse       # State bits
  end

  # General functions
  fun initscr : Window
  fun endwin : LibC::Int

  # General window functions
  fun getmaxy(window : Window) : LibC::Int
  fun getmaxx(window : Window) : LibC::Int
  fun wmove(window : Window, row : LibC::Int, col : LibC::Int) : LibC::Int
  fun wrefresh(window : Window) : LibC::Int
  fun wclrtoeol(window : Window) : LibC::Int
  fun wclrtobot(window : Window) : LibC::Int
  fun getbegx(window : Window) : LibC::Int
  fun getbegy(window : Window) : LibC::Int

  # Input option functions
  fun nl : LibC::Int
  fun nonl : LibC::Int
  fun cbreak : LibC::Int
  fun nocbreak : LibC::Int
  fun echo : LibC::Int
  fun noecho : LibC::Int
  fun raw : LibC::Int

  # Window input option function
  fun keypad(window : Window, value : Bool)

  # Input functions
  fun wget_wch(window : Window, ch : Wint_t*) : LibC::Int
  fun get_wch(Wint_t*) : LibC::Int

  # Window background functions
  fun wbkgdset(window : Window, char : LibC::UInt)

  # Window output
  fun waddstr(window : Window, str : LibC::Char*) : LibC::Int
  fun waddch(window : Window, chr : LibC::Char)
  fun wattrset(window : Window, attr : LibC::Int) : LibC::Int
  fun wnoutrefresh(window : Window) : LibC::Int
  fun mvwaddstr(window : Window, y : LibC::Int, x : LibC::Int, str : LibC::Char*) : LibC::Int

  # Mouse functions
  fun mousemask(new_mask : LibC::ULong, old_mask : LibC::ULong*) : LibC::ULong
  fun getmouse(event : MEVENT*) : LibC::Int

  # Color functions
  fun COLOR_PAIR(LibC::Int) : LibC::Int
  fun start_color : LibC::Int
  fun use_default_colors : LibC::Int

  # Other functions
  fun doupdate : LibC::Int
  fun init_pair(slot : LibC::Short, foreground : LibC::Short, background : LibC::Short) : LibC::Int
  fun attrset(LibC::Int) : LibC::Int
  fun clrtoeol : LibC::Int
  fun timeout(LibC::Int) : LibC::Int
  fun curs_set(visibility : LibC::Int) : LibC::Int
end

# The `Ncurses` module is an attempt to duplicate enough of the
# functionality of the Ruby ncurses gem, as used by sup and now by csup.
# It also contains methods specific to csup, especially the ones related to
# the key naming feature, which differs from sup.
module Ncurses
  # (w)get_wch error value.
  ERR = -1

  alias Wint_t = LibNCurses::Wint_t
  alias Window = LibNCurses::Window

  @@num_colors = 0
  @@max_pairs = 0
  @@mouse_y = 0
  @@stdscr
  @@current_mask : LibC::ULong = 0
  extend self

  # Wrapper for initscr
  def initscr
    @@stdscr = LibNCurses.initscr
  end

  # Start curses mode
  # Wrapper for `initscr()`
  def start
    initscr
  end

  # Returns stdscr.
  def stdscr
    scr = @@stdscr
    if scr.nil?
      raise "stdscr: initscr has not been called yet!"
    end
    return scr
  end

  # Disable buffering, key input is returned with no delay
  # Wrapper for `cbreak()`
  def cbreak
    LibNCurses.cbreak
  end

  # Wrapper for `echo()`
  def echo
    LibNCurses.echo
  end

  # Wrapper for `noecho()`
  def no_echo
    LibNCurses.noecho
  end

  # Wrapper for `keypad()`
  def keypad(value : Bool)
    LibNCurses.keypad(stdscr, value)
  end

  # Wrapper for `raw()`
  def raw
    LibNCurses.raw
  end

  # Wrapper for `nonl()`
  def nonl
    LibNCurses.nonl
  end

  # Returns the number of available colors for this terminal.
  def num_colors
    if @@num_colors = 0
      @@num_colors = `tput colors`.to_i
    end
    return @@num_colors
  end

  # Returns the maximum number of color pairs supported by Ncurses on this terminal.
  def max_pairs
    if @@max_pairs = 0
      @@max_pairs = `tput pairs`.to_i
    end
    return @@max_pairs
  end

  # Wrapper for `init_pair`
  def init_pair(slot : LibC::Short, foreground : LibC::Short, background : LibC::Short) : LibC::Int
    LibNCurses.init_pair(slot, foreground, background)
  end

  # Wrapper for `doupdate`
  def doupdate
    LibNCurses.doupdate
  end

  # Wrapper for `getmaxx`
  def cols
    LibNCurses.getmaxx(stdscr)
  end

  # Wrapper for `getmaxy`
  def rows
    LibNCurses.getmaxy(stdscr)
  end

  # Wrapper for `attrset`
  def attrset(attr : LibC::Int) : LibC::Int
    LibNCurses.attrset(attr)
  end

  # Wrapper for `attrset`
  def wattrset(window : Window, attr : LibC::Int) : LibC::Int
    LibNCurses.wattrset(window, attr)
  end

  # Wrapper for `mvaddstr`
  def mvaddstr(y : LibC::Int, x : LibC::Int, str : String) : LibC::Int
    LibNCurses.mvwaddstr(stdscr, y, x, str.to_unsafe)
  end

  # Wrapper for `mvwaddstr`
  def mvwaddstr(window : Window, y : LibC::Int, x : LibC::Int, str : String) : LibC::Int
    LibNCurses.mvwaddstr(window, y, x, str.to_unsafe)
  end

  # Wrapper for `curs_set`.  Sets the cursor state to *visibility*: 0
  # to hide the cursor, or 1 to show the cursor.
  def curs_set(visibility : LibC::Int) : LibC::Int
    LibNCurses.curs_set(visibility)
  end

  # Wrapper for `clrtoeol`
  def clrtoeol : LibC::Int
    LibNCurses.clrtoeol
  end

  # Wrapper for `endwin`
  def endwin : LibC::Int
    LibNCurses.endwin
  end

  # Wrapper for `timeout`
  def timeout(delay : LibC::Int) : LibC::Int
    LibNCurses.timeout(delay)
  end

  # Wrapper for `wnoutrefresh`
  def wnoutrefresh(window : Window) : LibC::Int
    LibNCurses.wnoutrefresh(window)
  end

  # Wrapper for `wrefresh(stdscr)`
  def refresh : LibC::Int
    LibNCurses.wrefresh(stdscr)
  end

  # Wrapper for `start_color()`
  def start_color
    LibNCurses.start_color
  end

  # Wrapper for `use_default_colors()`
  def use_default_colors
    LibNCurses.use_default_colors
  end

  # Sets the mouse events that should be returned
  # Should be given a `Mouse` enum
  def mouse_mask(new_mask : LibNCurses::Mouse)
    @@current_mask = LibNCurses.mousemask(new_mask, pointerof(@@current_mask))
  end

  # Wrapper for `getmouse()`
  def get_mouse : MEVENT?
    return nil if LibNCurses.getmouse(out event) == ERR
    return event
  end

  # Wrapper for `wmove(stdscr)`
  def move(row : LibC::Int, col : LibC::Int) : LibC::Int
    LibNCurses.wmove(stdscr, row, col)
  end

  # Wrapper for `endwin()`
  def end
    LibNCurses.endwin
  end

  # Constants for cell attributes, colors, keys, and mouse events.
  A_NORMAL = 0
  A_BOLD = 0x200000
  A_BLINK = 0x80000

  BUTTON1_CLICKED = 0x4
  BUTTON1_DOUBLE_CLICKED = 0x8

  COLOR_DEFAULT = -1
  COLOR_BLACK = 0x0
  COLOR_RED = 0x1
  COLOR_GREEN = 0x2
  COLOR_YELLOW = 0x3
  COLOR_BLUE = 0x4
  COLOR_MAGENTA = 0x5
  COLOR_CYAN = 0x6
  COLOR_WHITE = 0x7

#  ERR = 0xffffffffffffffff

  KEY_CANCEL = 0x163
  KEY_CODE_YES = 0x100
  KEY_MOUSE = 0x199
  KEY_ENTER = 0x157
  KEY_BACKSPACE = 0x107
  KEY_UP = 0x103
  KEY_DOWN = 0x102
  KEY_LEFT = 0x104
  KEY_RIGHT = 0x105
  KEY_PPAGE = 0x153
  KEY_NPAGE = 0x152
  KEY_HOME = 0x106
  KEY_END = 0x168
  KEY_IC = 0x14b
  KEY_DC = 0x14a
  KEY_F1 = 0x109
  KEY_F2 = 0x10a
  KEY_F3 = 0x10b
  KEY_F4 = 0x10c
  KEY_F5 = 0x10d
  KEY_F6 = 0x10e
  KEY_F7 = 0x10f
  KEY_F8 = 0x110
  KEY_F9 = 0x111
  KEY_F10 = 0x112
  KEY_F11 = 0x113
  KEY_F12 = 0x114
  KEY_F13 = 0x115
  KEY_F14 = 0x116
  KEY_F15 = 0x117
  KEY_F16 = 0x118
  KEY_F17 = 0x119
  KEY_F18 = 0x11a
  KEY_F19 = 0x11b
  KEY_F20 = 0x11c
  KEY_RESIZE = 0x19a

#  OK = 0x0

  REPORT_MOUSE_POSITION = 0x10000000

  # Hash mapping values for Ncurses special function keys to user-friendly names.
  @@func_keynames = {
    KEY_BACKSPACE => "C-h",
    KEY_RESIZE => "C-l",
    KEY_IC => "Insert",
    KEY_DC => "Delete",
    KEY_UP => "Up",
    KEY_DOWN => "Down",
    KEY_LEFT => "Left",
    KEY_RIGHT => "Right",
    KEY_PPAGE => "PgUp",
    KEY_NPAGE => "PgDn",
    KEY_HOME => "Home",
    KEY_END => "End",
    KEY_F1 => "F1",
    KEY_F2 => "F2",
    KEY_F3 => "F3",
    KEY_F4 => "F4",
    KEY_F5 => "F5",
    KEY_F6 => "F6",
    KEY_F7 => "F7",
    KEY_F8 => "F8",
    KEY_F9 => "F9",
    KEY_F10 => "F10",
    KEY_F11 => "F11",
    KEY_F12 => "F12",
    KEY_F13 => "F13",
    KEY_F14 => "F14",
    KEY_F15 => "F15",
    KEY_F16 => "F16",
    KEY_F17 => "F17",
    KEY_F18 => "F18",
    KEY_F19 => "F19",
    KEY_F20 => "F20"
  }

  # This macro creates a hash `@@consts` that maps the names of Ncurses
  # attributes and colors to their integer values.
  macro consts(*names)
    @@consts = {
    {% for name in names %}
      {{name.stringify}} => {{name.id}},
    {% end %}
    }
  end
  consts A_BOLD, COLOR_DEFAULT, COLOR_BLACK, COLOR_RED, COLOR_GREEN,
         COLOR_YELLOW, COLOR_BLUE, COLOR_MAGENTA, COLOR_CYAN,
	 COLOR_WHITE

  # Returns the Ncurses integer value for the color or attribute specified
  # by *name*.  This is an ugly hack to make sup's colormap code happy.
  def const_get(name : String) : Int32
    if @@consts.has_key?(name)
      return @@consts[name]
    else
      raise NameError.new("no such Ncurses constant #{name}")
      return 0
    end
  end

  # Converts an Ncurses key value to a string representation for the key:
  #
  # * a single character string for simple unmodified keys
  # * C-x for Ctrl + x
  # * F-n for function key n
  # * name of key for other special keys ("Insert", "PgUp", etc.)
  def keyname(ch : Int32, function_key = false) : String
    # Ncurses.print("keyname: ch #{sprintf("0x%x", ch)}, function_key #{function_key}\n")
    if function_key
      if @@func_keynames.has_key?(ch)
	return @@func_keynames[ch]
      else
	return sprintf("F-%x", ch)
      end
    else
      if ch >= 0x00 && ch <= 0x1f
	return "C-#{(ch + 0x60).chr}"
      else
	return ch.chr.to_s
      end
    end
  end

  # :showdoc:
  #
  # This is the helper function for `getkey`.  It waits for a keystroke and
  # returns a string representation:
  # * printable key: one-character string containing the key
  # * ctrl-key:  C-lowercase-key
  # * alt-key;   M-lowercase-key
  # * ctrl-alt-key: C-M-lowercase-key
  # * function key: name of key ("F1", "End", "Insert", "PgDn", etc.)
  #
  # Simple left button mouse clicks are also handled, returning
  # either "click" or "doubleclick".  Use the `getmouse_y` method
  # to get the row number of the click.
  protected def do_getkey(prefix = "") : String
    if (result = LibNCurses.get_wch(out ch)) == ERR
      return "ERR"
    end
    if result == Ncurses::KEY_CODE_YES
      if ch == KEY_MOUSE
        if mouse = Ncurses.get_mouse
	  #STDERR.puts "mouse x #{mouse.x}, y #{mouse.y}, bstate #{mouse.bstate}"
          @@mouse_y = mouse.y
	  if mouse.bstate.includes?(LibNCurses::Mouse::B1DoubleClicked)
	    return "doubleclick"
	  elsif mouse.bstate.includes?(LibNCurses::Mouse::B1Clicked)
	    return "click"
	  end
	end
	return "click"
      else
	return prefix + keyname(ch, true)
      end
    else
      if ch == 0x1b
	return do_getkey("M-")
      elsif ch == 0x1c
        return do_getkey("C-M")
      elsif ch == 0x1e
        return do_getkey("C-")
      else
	return prefix + keyname(ch, false)
      end
    end
  end

  # Gets a key, and returns it as a string (see `do_getkey`) or returns "ERR"
  # if a timeout occurs. *delay* specifies the timeout value in milliseconds,
  # or -1 (default) to disable the timeout.
  def getkey(delay = -1)
    timeout(delay)
    s = do_getkey
    timeout(-1)
    return s
  end

  # Returns the row number of the most recent mouse click or doubleclick event.
  def getmouse_y
    @@mouse_y
  end

  # Returns a `MouseEvent` containing the mouse state and coordinates
  # Wrapper for `getmouse()`
  def get_mouse
    return nil if LibNCurses.getmouse(out event) == ERR
    return event
  end

end	# Ncurses

# We have to set the locale so that ncurses will work correctly
# with UTF-8 strings.
lib Locale
  # LC_CTYPE is probably 0 (at least in glibc)
  LC_CTYPE = 0
  fun setlocale(category : Int32, locale : LibC::Char*) : LibC::Char*
end

module Redwood

  @@cursing = false

  # Changes the terminal state to Ncurses mode.
  def self.start_cursing
    Locale.setlocale(Locale::LC_CTYPE, "")
    Ncurses.start
    Ncurses.cbreak
    Ncurses.no_echo
    #Ncurses.stdscr.keypad 1
    Ncurses.keypad(true)	# Handle function keys and arrows
    Ncurses.raw
    Ncurses.nonl		# don't translate Enter to C-J on input
    Ncurses.curs_set 0
    Ncurses.start_color
    Ncurses.use_default_colors
    if Config.bool(:mouse)
      Ncurses.mouse_mask(LibNCurses::Mouse::AllEvents | LibNCurses::Mouse::Position)
    end
    #Ncurses.prepare_form_driver
    @@cursing = true
  end

  # Ends Ncurses mode, restoring the terminal to its original state.
  def self.stop_cursing
    return unless @@cursing
    Ncurses.curs_set 1
    Ncurses.echo
    Ncurses.end
    @@cursing = false
  end

  # Returns true if the terminal is in Ncurses mode.
  def self.cursing
    @@cursing
  end

end	# Redwood
