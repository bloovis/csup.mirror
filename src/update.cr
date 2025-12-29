require "./singleton"

module Redwood

# `UpdateManager` is a singleton class that implements a classic listener/broadcaster paradigm.
# It handles communication between various parts of csup.
#
# The Crystal implementation differs from the Ruby version in these ways:
# - The registering class must be a Mode subclass.
# - The mode's update methods (named `handle_{type}_update`) must be listed
#   in the Mode's `mode_class` macro invocation.
class UpdateManager
  singleton_class

  @targets = Hash(Mode, Bool).new

  def initialize
    singleton_pre_init
    singleton_post_init
  end

  # Adds the Mode object *o* to the list of Modes that want to receive
  # update notifications.
  def register(o : Mode)
    #STDERR.puts "UpdateManager.register: classname #{o.class.name}"
    @targets[o] = true
  end
  singleton_method register, o

  # Removes the Mode object *o* from the list of Modes that want to receive
  # update notifications.
  def unregister(o : Mode)
    #STDERR.puts "UpdateManager.unregister: classname #{o.class.name}"
    @targets.delete(o)
  end
  singleton_method unregister, o

  # Sends a message of type *type* to all waiting modes that have a
  # `handle_{type}_update` method, by calling that method with the
  # arguments *args*.
  def relay(sender : Object, type : Symbol, *args)
    #STDERR.puts "relay: sender #{sender.class.name}, type #{type}"
    meth = "handle_#{type.to_s}_update"
    @targets.keys.each do |o|
      #STDERR.puts "relay: checking if #{o.class.name} responds to #{meth}"
      if o != sender && o.respond_to?(meth)
	#STDERR.puts "relay: sender #{sender.class.name} sending (#{args[0]?}) to #{o.class.name}.#{meth}"
        o.send meth, *args
      end
    end
  end
  singleton_method relay, type, msg

end	# UpdateManager

end	# Redwood
