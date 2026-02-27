require "./keymap"
require "./config"
require "./buffer"
require "./colormap"
require "./search"
require "./undo"
require "./update"
require "./hook"
require "./account"
require "./label"
require "./contact"
require "./logger"
require "./modes/inbox_mode"
require "./modes/buffer_list_mode"
require "./modes/search_results_mode"
require "./modes/search_list_mode"
require "./modes/help_mode"
require "./modes/contact_list_mode"
require "./draft"
require "./modes/label_search_results_mode"
require "./modes/label_list_mode"
require "../version"

module Redwood
  BASE_DIR = File.join(ENV["HOME"], ".csup")

  extend self

  @@log_io : IO?
  @@poll_mode : PollMode?

  def init_managers
    basedir = BASE_DIR

    log_io = File.open(File.join(basedir, "log"), "a")
    if log_io
      logm = Logger.new
      Logger.add_sink(log_io)
      @@log_io = log_io
    end

    cf = Config.new(File.join(basedir, "config.yaml"))
    cm = ContactManager.new(File.join(basedir, "contacts.txt"))
    bm = BufferManager.new
    colormap = Colormap.new(File.join(basedir, "colors.yaml"))
    Colormap.reset
    Colormap.populate_colormap
    sm = SearchManager.new(File.join(basedir, "searches.txt"))
    unm = UndoManager.new
    upm = UpdateManager.new
    hm = HookManager.new(File.join(basedir, "hooks"))
    am = AccountManager.new(Config.accounts)
    lm = LabelManager.new
    sentm = SentManager.new(Config.str(:sent_folder) || "sent")
    dm = DraftManager.new(Config.str(:draft_folder) || "draft")
    tc = ThreadCache.new

  end

  def event_loop(keymap, &b)
    # The initial draw_screen won't draw the buffer status, because
    # the status is set as a result of calling draw_screen.  Hence,
    # we need to call it again at the beginning of the event loop.
    BufferManager.draw_screen

    # Get the poll interval in seconds, and convert it to milliseconds.
    poll_interval = Config.int(:poll_interval) * 1000
    while true
      BufferManager.draw_screen
      # Get a key with five minute timeout.  If the timeout occurs,
      # ch will equal "ERR" and the poll command will run.
      ch = Ncurses.getkey(poll_interval)
      BufferManager.erase_flash if ch != "ERR"
      begin
	unless BufferManager.handle_input(ch)
	  action = BufferManager.resolve_input_with_keymap(ch, keymap)
	  if action
	    send action
	  else
	    yield ch
	  end
	end
      rescue InputSequenceAborted
        # Do nothing.
      end
    end
  end

  # Returns the IO handle for the log file `~/.csup/log`.  This is used by `EditMessageMode` to
  # capture `EMail::Client` log messages.
  def log_io : IO?
    @@log_io
  end

  # `PollMode` is a dummy mode (i.e., one that does not have a `Buffer`), that exists only for
  # the ability to call `UpdateManager.relay` after polling.
  class PollMode < Mode
    def initialize
      @notmuch_lastmod = Notmuch.lastmod
    end

    def poll
      # Run the before-poll hook, and display a flash showing whether it
      # succeeded, along with whatever string it printed.
      result = ""
      success = HookManager.run("before-poll") do |pipe|
	pipe.receive do |f|
	  result = f.gets_to_end
	end
      end
      #STDERR.puts "before-poll: success #{success}, result #{result}"
      if success
	if result && (result.size > 0)
	  BufferManager.flash result
	end
      else
	if result.size > 0
	  BufferManager.flash "before-poll hook failed: #{result}"
	else
	  BufferManager.flash "before-pool hook failed"
	end
      end

      # Ask notmuch to poll for new messages.  Then create
      # a notmuch search term that will result in a list
      # of threads that are new/updated since the last poll.
      # Relay the search term to any waiting thread index modes.
      Notmuch.poll
      nowmod = Notmuch.lastmod
      #STDERR.puts "nowmod #{nowmod}, lastmod #{@notmuch_lastmod}"
      return if nowmod == @notmuch_lastmod
      search_terms = "lastmod:#{@notmuch_lastmod}..#{nowmod}"
      @notmuch_lastmod = nowmod
      UpdateManager.relay self, :poll, search_terms
    end
  end

  # Polls notmuch for new messages.  The first time it is called, it creates
  # a `PollMode` object, which in turn causes other Modes
  # to be notified that a poll has occurred.
  def poll
   unless poll_mode = @@poll_mode
     poll_mode = PollMode.new
     @@poll_mode = poll_mode
   end
   poll_mode.poll
  end

{% unless flag?(:TEST) %}

# Functions required by main.  We have to use `extend self` to overcome
# namespace problems with the `actions` macro.

extend self

# Shuts down all managers and closes the log file.
def finish
  ContactManager.save if Redwood::ContactManager.instantiated?
  SearchManager.save if Redwood::SearchManager.instantiated?
  if log_io = @@log_io
    Logger.remove_sink log_io
  end

  # De-instantiate all managers.
  {% for name in [HookManager, ContactManager, LabelManager, AccountManager,
		  UpdateManager, UndoManager,
		  SearchManager, SentManager, DraftManager] %}
    {{name.id}}.deinstantiate! if {{name.id}}.instantiated?
  {% end %}

  if log_io = @@log_io
    log_io.close
    @@log_io = nil
  end
end

# This macro lists all global commands, i.e., commands that are not implemented
# by a `Mode`.

actions quit_now, quit_ask, kill_buffer, roll_buffers, roll_buffers_backwards,
        list_buffers, list_contacts, redraw, search, poll, compose, help,
	list_labels, version, display_keymap

# This command exits csup without asking the user if it's OK.
def quit_now
  #BufferManager.say "This is the global quit command."
  #puts "This is the global quit command."
  return unless BufferManager.kill_all_buffers_safely
  finish
  Ncurses.end
  Logger.remove_all_sinks!
  if log_io = @@log_io
    Logger.remove_sink(log_io)
    log_io.close
  end
  exit 0
end

# This command exits csup after asking if it's OK.
def quit_ask
  if BufferManager.ask_yes_or_no "Really quit?"
    quit_now
  end
end

# This command moves the current buffer to the end of the buffer list,
# and brings the next buffer to the front.
def roll_buffers
  BufferManager.roll_buffers
end

# This command moves the next-most-recent buffer to the head of the buffer list.
def roll_buffers_backwards
  BufferManager.roll_buffers_backwards
end

# This command kills the current buffer.
def kill_buffer
  BufferManager.kill_buffer_safely(BufferManager.focus_buf)
end

# This command opens a buffer showing the list of all buffers.
def list_buffers
  BufferManager.spawn_unless_exists("buffer list", Opts.new({:system => true})) { BufferListMode.new }
end

# This command opens a buffer showing the contacts list.
def list_contacts
  b, new = BufferManager.spawn_unless_exists("Contact List") { ContactListMode.new }
  #mode.load_in_background if new
end

# This command redraws the screen, which also happens automatically when the terminal
# is resized.
def redraw
  BufferManager.completely_redraw_screen
end

# This command prompts the user for a search string, and opens a buffer containing
# the list of messages that match that search.
def search
  completions = LabelManager.all_labels.map { |l| "label:#{LabelManager.string_for l}" }
  completions += Notmuch::COMPL_PREFIXES
  query = BufferManager.ask_many_with_completions :search, "Search all messages (enter for saved searches): ", completions
  unless query.nil?
    if query.empty?
      BufferManager.spawn_unless_exists("Saved searches") { SearchListMode.new }
    else
      SearchResultsMode.spawn_from_query query
    end
  end
end

# This command opens a buffer that allows the user to compose a new email message.
def compose
  ComposeMode.spawn_nicely
end

# This command opens a buffer containing a list of the key bindings for the Mode
# in which it was invoked.
def help
  #STDERR.puts "help command"
  return unless global_keymap = Redwood.global_keymap
  return unless focus_buf = BufferManager.focus_buf
  return unless curmode = focus_buf.mode
  BufferManager.spawn_unless_exists("<help for #{curmode.name}>") do
    HelpMode.new(curmode, global_keymap)
  end
end

# This command opens a buffer containing a list of all message labels, allowing the
# user to then open another buffer showing the messages that have that label.
def list_labels
  labels = LabelManager.all_labels.map { |l| LabelManager.string_for l }

  user_label = BufferManager.ask_with_completions :label, "Show threads with label (enter for listing): ", labels
  unless user_label.nil?
    if user_label.empty?
      BufferManager.spawn_unless_exists("Label list") { LabelListMode.new }
    else
      LabelSearchResultsMode.spawn_nicely user_label
    end
  end
end

# This command displays a message showing the csup version (date + source code commit hash).
def version
  BufferManager.flash "Csup version #{Redwood::VERSION}"
end

# This command opens a buffer containing the yaml representation of all key bindings.
# This text can be used as the basis for the user-configurable
# `~/.csup/keymap.yaml` file.
def display_keymap
  yaml = Keymap.keymaps_to_yaml
  #STDERR.puts "keymap: yaml = '#{yaml}'"
  BufferManager.spawn "Keymaps", TextMode.new(yaml)
end

# This is the main program of csup.
def main
  init_managers

  start_cursing

  @@poll_mode = PollMode.new
  lmode = Redwood::LogMode.new "system log"
  lmode.on_kill { Logger.clear! }
  Logger.add_sink lmode
  Logger.force_message "Welcome to Csup! Log level is set to #{Logger.level}."
  if (level = Logger::LEVELS.index(Logger.level)) && level > 0
    Logger.force_message "For more verbose logging, restart with CSUP_LOG_LEVEL=" +
			 "#{Logger::LEVELS[level-1]}."
  end

  mode = InboxMode.new
  buf = BufferManager.spawn("Inbox Mode", mode, Opts.new({:width => 80, :height => 25}))
  BufferManager.raise_to_front(buf)
  poll

  global_keymap = Keymap.new do |k|
    k.add :quit_ask, "Quit Sup, but ask first", 'q'
    k.add :quit_now, "Quit Sup immediately", 'Q'
    k.add :help, "Show help", '?'
    k.add :roll_buffers, "Switch to next buffer", 'b'
    k.add :roll_buffers_backwards, "Switch to previous buffer", 'B'
    k.add :kill_buffer, "Kill the current buffer", 'x'
    k.add :list_buffers, "List all buffers", ';'
    k.add :list_contacts, "List contacts", 'C'
    k.add :redraw, "Redraw screen", "C-l"
    k.add :search, "Search all messages", '\\', 'F'
    k.add :list_labels, "List labels", 'L'
    k.add :poll, "Poll for new messages", 'P', "ERR"
    k.add :compose, "Compose new message", 'm', 'c'
    k.add :version, "Display version number", 'v'
    k.add :display_keymap, "Display keymaps", "C-k"
  end
  Redwood.global_keymap = global_keymap
  Keymap.load_keymap

  # Interactive loop.
  event_loop(global_keymap) do |ch|
    if (b = BufferManager.focus_buf) && (m = b.mode)
      modename = m.name
    else
      modename = "unknown mode"
    end
    BufferManager.flash "Unknown keypress '#{ch}' for #{modename}."
  end
end

# Here we capture any unhandled exceptions caused by csup, and print
# the exception information along with a backtrace before exiting.
begin
  main
rescue ex
  Ncurses.end
  puts "Oh crap!  An exception occurred!"
  puts ex.inspect_with_backtrace
  exit 1
end

{% end %} # flag TEST

end	# Redwood
