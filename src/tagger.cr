
#require 'sup/util/ncurses'
require "./mode"

module Redwood

# `Tagger` is a class that a Mode uses to tag objects, such as messages
# or contacts in a list. (A tag is a binary on/off state, not a label.)
# Then the Mode can perform mass operations on those tagged objects.
# In csup, the two Modes that use `Tagger` are `ThreadIndexMode`
# and `ContactListMode`.
#
# This implementation of `Tagger` differs from the one in Sup in these ways:
# * It is a generic type, and you have to specify the type of the object
#   being tagged when creating it, e.g., `Tagger(Message).new`, and `new`
#   takes no parameters.
# * It can only be used by Mode subclasses.
# * After the Mode creates the `Tagger` instance in `initialize`, it must
#   call `setmode` on that instance
# * Mode `multi_{action}` methods don't take parameters; instead, they
#   must call `all` to obtain an array of tagged objects.
#
# See `test/tagger_test.cr` for a simple example.
class Tagger(T)

  # Initializes a tagger where the objects being tagged are of type `T`.
  # *noun* is the name of the tagged object's type.  If non-nil,
  # *plural_noun" is the plural name of the tagged object's type;
  # otherwise *noun* + "s" is used as the plural noun.
  def initialize(noun="object", plural_noun=nil)
    @tagged = Set(T).new
    @noun = noun
    @plural_noun = plural_noun || (@noun + "s")
  end

  # Sets the Mode associated with this tagger.
  def setmode(mode : Mode)
    @mode = mode
  end

  # Returns true if the object *o* has been tagged.
  def tagged?(o : T) : Bool
    @tagged.includes?(o)
  end

  # Toggles the tagged-ness of the object *o*, i.e. tag it if is currently untagged,
  # otherwise untag it.
  # 
  def toggle_tag_for(o : T)
    if @tagged.includes?(o)
      @tagged.delete(o)
    else
      @tagged.add(o)
    end
  end

  # Adds the object *o* to the list of tagged objects.
  def tag(o : T)
    @tagged.add(o)
  end

  # Removes the object *o* from the list of tagged objects.
  def untag(o : T)
    @tagged.delete(o)
  end

  # Clears the list of tagged objects.
  def drop_all_tags
    @tagged.clear
  end

  # Identical to `untag`.
  def drop_tag_for(o : T)
    @tagged.delete(o)
  end

  # Returns the  number of tagged objects.
  def num_tagged
    @tagged.size
  end

  # Returns an array of all tagged objects.
  def all : Array(T)
    @tagged.to_a
  end

  # Calls `mode.multi_{action}` for each tagged object, where
  # *action* is the name of an action.   In Ruby
  # this works by constructing a method name at runtime and passing it
  # the list of tagged objects via `send`.  Crystal doesn't have `send`,
  # so this depends on the use of the `mode_class` macro in the relevant
  # Mode, which creates a fake `send` for a specified set of methods.
  # Also, the invoked `multi_{action}` method must call `Tagger(T).all`
  # to obtain the tagged objects.
  def apply_to_tagged(action=nil)
    #STDERR.puts "apply_to_tagged, mode = #{@mode.object_id}"
    mode = @mode
    return unless mode
    if num_tagged == 0
      #STDERR.puts "apply_to_tagged: no tagged threads"
      BufferManager.flash "No tagged threads!"
      return
    end

    noun = num_tagged == 1 ? @noun : @plural_noun

    unless action
      c = BufferManager.ask_getch "apply to #{num_tagged} tagged #{noun}:"
      return if c.empty? # user cancelled
      action = mode.resolve_input c
    end

    if action
      tagged_sym = "multi_" + action.to_s
      #STDERR.puts "checking if we can send #{tagged_sym} to #{mode.class.name}"
      if mode.respond_to? tagged_sym
	#STDERR.puts "sending #{tagged_sym} to #{mode.class.name}"
        mode.send tagged_sym	# method must fetch targets using Tagger.all
      else
        BufferManager.flash "That command cannot be applied to multiple #{@plural_noun}."
      end
    else
      BufferManager.flash "Unknown command #{c}."
    end
  end
  
end

end
