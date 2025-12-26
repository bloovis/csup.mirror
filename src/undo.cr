require "./singleton"
require "./supcurses"
require "./buffer"
require "./keymap"

module Redwood

# `UndoManager` is a singleton class that implements a single undo list.
#
# The basic idea is to keep a list of lambdas to undo
# things. When an action is called (such as `archive`),
# a lambda is registered with `UndoManager` that will
# undo the archival action.
class UndoManager
  singleton_class

  alias Action = Proc(Nil)
  alias UndoEntry = NamedTuple(desc: String, actions: Array(Action))

  @actionlist = [] of UndoEntry

  def initialize
    singleton_pre_init
    @actionlist = [] of UndoEntry
    singleton_post_init
  end

  # `do_register` is the underlying implementation for `register`.
  # It creates a set of actions comprising *actions* and `block`,
  # and forms an undo operation as a tuple consisting of the
  # the description *desc* and the set of actions. It then
  # pushs this undo operation onto the undo stack.
  protected def do_register(desc : String, *actions, &block : Action)
    a = Array(Action).new
    actions.map {|action| a << action}
    a << block
    @actionlist.push({desc: desc, actions: a})
  end

  # Registers a set of undo actions to be undone as a single operation.
  # An action is a `Proc(Nil)`, i.e. a method that takes
  # no parameters.  *actions* lists zero or more actions,
  # and the supplied block is another action to add to the set.
  # *desc* is a string describing the undo operation.
  def self.register(desc, *actions, &b)
    instance.do_register(desc, *actions, &b)
  end

  # Pops the most recent undo operation from the stack and calls
  # each action in the operation's action set.  It also displays
  # a message using the operation's description string.
  def undo
    unless @actionlist.empty?
      actionset = @actionlist.pop
      actions = actionset[:actions]
      actions.each do |action|
	action.call
      end
      if Redwood.cursing
	BufferManager.flash "undid #{actionset[:desc]}"
      else
	puts "undid #{actionset[:desc]}"
      end
    else
      if Redwood.cursing
	BufferManager.flash "nothing more to undo!"
      else
	puts "nothing more to undo!"
      end
    end
  end
  singleton_method undo

  def clear
    @actionlist = [] of UndoEntry
  end
  singleton_method clear
end	# UndoManager

end	# Redwood
