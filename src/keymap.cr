module Redwood

# `keymaps` is a hash that maps a `Mode` subclass name to
# the `Keymap` object for that Mode.  In sup, `keymaps` was a class variable for `Mode`.
# But we can't do that in Crystal, because in Crystal, unlike in Ruby, `keymaps` would
# get a unique instance for each subclass of `Mode`.
@@keymaps = Hash(String, Keymap).new
def self.keymaps
  @@keymaps
end

# `global_keymap` is the global keymap, i.e. the map for key mappings that
# are defined at the top level and work in any Mode.
@@global_keymap : Keymap?
def self.global_keymap
  @@global_keymap
end
def self.global_keymap=(map)
  @@global_keymap = map
end

# The `Keymap` class represents bindings from key names to actions.  A key can
# map to an action, or it can map to another `Keymap` object, which allows
# for commands that require more than one keystroke.  Each Mode creates
# its own keymap for commands that are specific to that Mode.
class Keymap
  # An `Action` is either a method name or another `Keymap`.
  alias Action = String | Keymap

  # An `Entry` records an action, a help string, and one or more key names
  # that are bound to that action.
  alias Entry = NamedTuple(action: Action, help: String, keynames: Array(String))

  # `map` is a hash that maps a single key name to an `Entry` object.
  property map = Hash(String, Entry).new	# keyname => entry

  # `order` records `Entry` records in the order in which they were defined.
  # `helplines` uses this to display key binding help in a sensible order,
  # rather than a semi-random order imposed by the `map` hash table.
  property order = Array(Entry).new

  # The constructor yields `self` so that the passed-in block can add any
  # bindings it wishes.
  def initialize(&)
    yield self
  end

  # Returns true if the mapping is empty.
  def empty?
    return map.empty?
  end

  # Adds an action to the keymap: *action* is the name of a Mode method,
  # *help* is the help string for the action, and *keynames* is one or more
  # key names that are bound to this action.
  def add(action : String | Symbol | Keymap, help : String, *keynames)
    keys = [] of String
    keynames.each {|k| keys << k.to_s}
    if action.is_a?(Symbol)
      action = action.to_s
    end
    entry = Entry.new(action: action, help: help, keynames: keys)
    @order << entry
    keys.each do |k|
      raise ArgumentError.new("key '#{k}' already defined (as #{@map[k][:action]})") if @map.includes? k
      @map[k] = entry
    end
    if keys.size == 0
      raise "Key list for action #{action} is empty!"
    end
    #puts "Added keys #{keynames}, description #{description}, action #{action}, keymap #{self.object_id}, action map #{@map}"
  end

  # Returns true if the keyname *s* is bound to an action.
  def has_key?(s : String)
    @map.has_key?(s)
  end

  # Returns the `Entry` object that is bound to the keyname *s*.
  def [](s : String)
    @map[s]
  end

  # Adds the head entry for a multi-key binding table.  *prompt* is the help string,
  # and *k* is the keyname that binds to this entry.  `add_multi` calls the passed-in
  # block with the new `Keymap` object, so that the block can add more key bindings to it.
  def add_multi(prompt : String, k : String | Char)
    kc = k.to_s
    if @map.member? kc
      action = @map[kc][:action]
      raise "existing action is not a keymap" unless action.is_a?(Keymap)
      yield action
    else
      submap = Keymap.new {}
      add submap, prompt, kc
      yield submap
    end
  end

  # `dump` is a debug-only method that prints the mapping to stdout.
  def dump(int level = 1)
    puts "Keymap dump level #{level}:"
    @map.each do |k, entry|
      action = entry[:action]
      help = entry[:help]
      keys = entry[:keynames]
      if action.is_a?(Keymap)
	puts "-" * level + "#{k} (#{help}):"
	action.dump(level + 1)
      else
	puts "-" * level + "#{k} (#{help}): #{action}"
      end
    end
  end

  # Looks up the entry for the keyname *c*, and if found, returns
  # a tuple containing the action and the help string for that entry.
  def action_for(c : String) : Tuple(Action | Nil, String | Nil)
    #puts "action_for: c #{c}, keymap #{self.object_id}, action map #{@map}"
    if has_key?(c)
      entry = @map[c]
      {entry[:action], entry[:help]}	# action, help
    else
      {nil, nil}
    end
  end

  # Returns a set of strings containing all keynames that are
  # bound to actions in this `Keymap`.
  def keysyms : Set(String)
    s = Set(String).new
    @map.each do |k, entry|
      keys = entry[:keynames]
      keys.each {|k| s.add(k)}
    end
    return s
  end

  # `KeyHelp` is a tuple with two elements:
  # * a string that contining all keynames bound to a single action, 
  #   joined by a comma
  # * the help string for that action.
  alias KeyHelp = Tuple(String, String)	# {keynames, helpstring}

  # Changes an internal keyname to a more user-friendly name.
  def fix_name(k : String) : String
    case k
    when "C-m"
      "Enter"
    when "C-i"
      "Tab"
    when " "
      "Space"
    else
      k
    end
  end

  # Returns an array of KeyHelp tuples, each describing a single entry in the keymap.
  # *except_for* is a set of keynames whose entries must be excluded from the result.
  def help_lines(except_for = Set(String).new, prefix="") : Array(KeyHelp)
    lines = Array(KeyHelp).new
    @order.each do |entry|
      action = entry[:action]
      help = entry[:help]
      keys = entry[:keynames]
      valid_keys = keys.select { |k| !except_for.includes?(k) }
      next if valid_keys.size == 0
      case action
      when String
        keynames = valid_keys.map { |k| prefix + fix_name(k) }.join(", ")
        lines << {keynames, help}
      when Keymap
        lines += action.help_lines(Set(String).new, prefix + keys.first)
      end
    end		# .compact -- why was this here?
    return lines
  end

  # Returns a nicely formatted set of lines describing the key bindings for each
  # action in the keymap.  Each line is composed of two columns:
  # * The list of keynames, joined by commas, and padded with spaces so that the
  #   second column is aligned properly.
  # * The help string for the action.
  def help_text(except_for=Set(String).new) : String
    lines = help_lines except_for
    llen = lines.max_of { |kh| kh[0].size }
    lines.map { |a, b| sprintf " %#{llen}s : %s", a, b }.join("\n")
  end

  # Loads user-defined key bindings from `~/.csup/keymap.yaml`.
  # The file looks like this:
  # ```
  #  modename1:
  #     action1:
  #       - key1
  #       - key2
  #       [...]
  #     action2:
  #       [...]
  #  modename2:
  #    [...]
  # ```
  #
  # The actions must already be defined and have default key bindings,
  # but `keymap.yaml` can overwrite or add to those bindings.
  def self.load_keymap
    base_dir   = File.join(ENV["HOME"], ".csup")
    keymap_fn  = File.join(base_dir, "keymap.yaml")
    unless File.exists?(keymap_fn)
      return
    end
    yaml = File.open(keymap_fn) { |f| YAML.parse(f) }
    h = yaml.as_h
    h.each do |k, v|
      mode = k.as_s
      #STDERR.puts "keymap for #{mode}:"
      if mode == "global"
	keymap = Redwood.global_keymap
      else
	keymap = Redwood.keymaps["Redwood::#{mode}"]?
      end
      unless keymap
	BufferManager.flash "Error in keymap.yaml: invalid mode #{mode}"
	return
      end
      h1 = v.as_h
      h1.each do |k1, v1|
	action = k1.as_s
	#STDERR.puts "  action: #{action}"
	val1 = v1.as_a
	keys = [] of String
	val1.each {|s| keys << s.as_s}
	#STDERR.puts "  keys: #{keys}"

	# Search the keymap for the entry for the specified action.
	entry = keymap.order.find {|e| e[:action] == action}
	unless entry
	  BufferManager.flash "Error in keymap.yaml: #{mode} has no action #{action}"
	  return
	end

	# If the keys are currently bound to other entries, remove the keys
	# from those entries.
	keys.each do |k|
	  if keymap.has_key?(k)
	    old_entry = keymap[k]
	    old_entry[:keynames].delete(k)
	  end
	end

	# Add the keys to the entry if they're not already there.
	# Then map the keys to the entry.
	keys.each do |k|
	  unless entry[:keynames].includes?(k)
	    entry[:keynames] << k
	  end
	  keymap.map[k] = entry
	end

      end
    end
  end

  # Returns the yaml representation of this keymap.
  def yaml(mode : String) : String
    yaml = "#{mode}:\n"
    @order.each do |entry|
      action = entry[:action]
      if action.is_a?(String)
	yaml += "  #{action}:\n"
	entry[:keynames].each {|k| yaml += "    - \"#{k}\"\n"}
      end
    end
    return yaml
  end

  # Returns the yaml representation of all keymaps, including
  # the global keymap.
  def self.keymaps_to_yaml : String
    yaml = ""
    Redwood.keymaps.each do |mode, keymap|
      simple_mode = mode.sub("Redwood::", "")
      yaml += keymap.yaml(simple_mode)
    end
    if keymap = Redwood.global_keymap
      yaml += keymap.yaml("global")
    end
    return yaml
  end

end 	# class Keymap

end	# module Redwood
