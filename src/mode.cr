require "./buffer"
require "./supcurses"
require "./pipe"
require "file_utils"

class Object
  # Catches attempts to call `send` on `Mode` objects that haven't
  # defined `send`.
  def send(action : String | Symbol)
    STDERR.puts "Object can't send #{action}!"
  end
end

module Redwood

# This macro defines a `send` method for the enclosing class that, given a string containing the name
# of a method, calls that method.  It also defines `respond_to?` method that, given a string
# containing the name of a method, returns true if that method can be invoked by `send`.
# The arguments to the macro (*args*) are the names of the allowed methods.
macro actions(*names)
  # Invokes the method named *action*, passing it the arguments *args*.
  def send(action : String, *args)
    case action
    {% for name in names %}
    when {{ name.stringify }}
      {{ name.id }}(*args)
    {% end %}
    else
      #puts "send: unknown method for #{self.class.name}.#{action}, calling superclass"
      super(action, *args)
    end
  end

  # Returns true if a method named *action* can be invoked by `send`.
  def respond_to?(action)
    found = [
      {% for name in names %}
        {{ name.stringify }},
      {% end %}
    ].index(action.to_s)
    if found
      true
    else
      super(action)
    end
  end
end

# `Mode` is the base class for all Modes in the `src/modes` directory.
# Each Mode displays text in a `Buffer` and interacts with the user, with specific
# behaviors unique to that `Mode`.
class Mode
  # In each derived class, call the `mode_class` macro with the names of
  # all methods that are to be bound to keys.  It creates an `ancestors` method
  # that returns a list of the names of all the classes in the hierarchy
  # for this class. Then for each of the *names*, it defines:
  # - a `send` method that invokes the named method
  # - a `respond_to?` method that returns true if the named method can be invoked by `send`
  macro mode_class(*names)
    CLASSNAME = self.name
    def ancestors
      [CLASSNAME] + super
    end
    {% if names.size > 0 %}
    Redwood.actions({{names.splat}})
    {% end %}
  end

  # Defines a dummy `send` method.  Derived classes need to define their own `send`
  # by invoking the `mode_class` macro.
  def send(action : String | Symbol, *args)
    #puts "Mode.send: should never get here!"
  end

  # Defines a dummy `respond_to?` method.  Derived classes need to define their own
  # `respond_to?` by invoking the `mode_class` macro.
  def respond_to?(action)
    return false
  end

  @buffer : Buffer?
  @dummybuffer : Buffer?

  # Defines a getter for `@buffer` that always returns a non-nil value,
  # so that derived classes don't always have to check for nil.  It creates
  # a dummybuffer for those rare situations where `@buffer` might be nil.
  def buffer : Buffer
    if b = @buffer
      return b
    elsif b = @dummybuffer
      #STDERR.puts "Mode.buffer: reusing dummybuffer, caller #{caller[1]}"
      return b
    else
      #STDERR.puts "Mode.buffer: creating dummybuffer, caller #{caller[1]}"

      # Return a dummy buffer.  This should only happen if a mode's initialize method
      # tries to access its buffer before it has been assigned a buffer in spawn.
      b = Buffer.new(Ncurses.stdscr, self, Ncurses.cols, Ncurses.rows-1, Opts.new)
      @buffer = b
      @dummybuffer = b
      return b
    end
  end

  # Sets the buffer for this mode to *b*.
  def buffer=(b : Buffer)
    @buffer = b
  end

  # Creates a `Keymap` for this Mode and yields it to the block, which should
  # add bindings to the map.
  def self.register_keymap
    classname = self.name
    #STDERR.puts "register_keymap for class #{classname}, keymaps #{Redwood.keymaps.object_id}"
    if Redwood.keymaps.has_key?(classname)
      #puts "#{classname} already has a keymap"
      k = Redwood.keymaps[classname]
    else
      k = Keymap.new {}
      Redwood.keymaps[classname] = k
      #puts "Created keymap for #{classname}, map #{k.object_id}"
      yield k
    end
    k
  end

  # Returns an list of class names representing the class hierarchy for this Mode.
  # Each derived class should invoke the `mode_class` macro to create its own
  # `ancestors` method that adds its class name to the list.
  def ancestors
    [] of String
  end

  # Returns a modified form of class name *s*.  It removes all parent class names, then
  # converts the resulting camel-case name to a hyphenated name and lower-cases it.
  # For example, it converts "Redwood::InboxMode" to "inbox-mode"
  def self.make_name(s)
    s.gsub(/.*::/, "").camel_to_hyphy
  end

  # Returns the enclosing class's name altered using `make_name`.
  def name
    Mode.make_name(self.class.name)
  end

  # Sets the associated buffer to nil.
  def initialize
    @buffer = nil
    #puts "Mode.initialize"
  end

  # Returns the `KeyMap` for this mode.
  def keymap
    Redwood.keymaps[self.class.name]
  end

  # These methods must be implemened by derived Mode classes.

  # Returns true if the Mode's buffer is killable.
  def killable?; true; end

  # Returns true if the Mode's buffer has unsaved data (used only by `ResumeMode`).
  def unsaved?; false end

  # Writes the visible part of the Mode's buffer to the Ncurses window.
  def draw; end

  # Takes the appropriate action when the Mode's buffer receives the focus.
  def focus; end

  # Takes the appropriate action when the Mode's buffer loses the focus.
  def blur; end

  # Stops any in-progress search in the Mode's buffer.
  def cancel_search!; end

  # Returns true if the Mode's buffer is being searched.
  def in_search?; false end

  # Returns the string that should be written to the status line.
  def status; ""; end

  # Takes the appropriate action when the terminal window is resized.
  def resize(rows, cols); end

  # Performs any necessary cleanup duties when the Mode's buffer is deleted.
  def cleanup
    #STDERR.puts "Mode.cleanup"
    @buffer = nil
  end

  # Returns the name of an action (a method name) that is bound to the keyname *c*
  # for this Mode, or nil if there is no such action.
  def resolve_input (c : String) : String | Nil
    ancestors.each do |classname|
      #STDERR.puts "Checking if #{classname} has a keymap"
      next unless Redwood.keymaps.has_key?(classname)
      #STDERR.puts "Yes, #{classname} has a keymap"
      action = BufferManager.resolve_input_with_keymap(c, Redwood.keymaps[classname])
      return action.to_s if action
    end
    nil
  end

  # If there is a Mode method bound to the key *c*, calls that method and returns true;
  # otherwise returns false.
  def handle_input(c : String) : Bool
    if action = resolve_input(c)
      send action
      true
    else
      return false
    end
  end

  # Returns a string containing a set of lines describing all of the
  # key bindings for this mode and its ancestors.
  def help_text : String
    used_keys = Set(String).new
    ancestors.map do |classname|
      next unless km = Redwood.keymaps[classname]?
      title = "Keybindings from #{Mode.make_name classname}"
      s = <<-EOS
#{title}
#{"-" * title.display_length}

#{km.help_text used_keys}

EOS
      used_keys = used_keys + km.keysyms
      s
    end.compact.join("\n")
  end

  # Helper functions

  # Saves the contents of this Mode's buffer to the file *fn*.  If *fn*
  # already exists, asks the user for confirmation before overwriting it.
  def save_to_file(fn : String, talk=true)
    if File.exists? fn
      unless BufferManager.ask_yes_or_no "File \"#{fn}\" exists. Overwrite?"
        #info "Not overwriting #{fn}"
        return
      end
    end
    FileUtils.mkdir_p File.dirname(fn)
    begin
      File.open(fn, "w") { |f| yield f }
      BufferManager.flash "Successfully wrote #{fn}." if talk
      true
    rescue e
      m = "Error writing file: #{e.message}"
      #info m
      BufferManager.flash m
      false
    end
  end

  # Passes this Mode's buffer contents in a pipe to the shell *command*, and returns
  # a tuple containing the output of the command and a Bool saying whether
  # the command's exit status was 0 (i.e., successful).
  def pipe_to_process(command : String) : Tuple(String?, Bool)
    pipe = Pipe.new(command, [] of String, shell: true)
    output = nil
    exit_status = pipe.start do |p|
      p.transmit do |f|
        yield f
      end
      p.receive do |f|
        output = f.gets_to_end
      end
    end
    return {output, exit_status == 0}
  end

end	# class Mode

end	# module Redwood
