require "./singleton"
require "./modes/log_mode"

module Redwood

# `Logger` is a singleton class that implements a simple centralized logger.
# It allows for multiple "sinks", which can receive log messages, and which
# can be either `IO` objects or the csup-specific `LogMode` singleton class.
# 
# There are four logging levels, in order of lowest to highest priority:
# * debug
# * info
# * warn
# * error
#
# The default logging level is "info", but you can override it by setting
# the environment variable `CSUP_LOG_LEVEL`.
#
# There are four global methods with the same names as the logging levels,
# which send messages to all sinks if allowed by the current logging level.
# For example, if the logging level is set to "info", calls to `debug` will not
# produce log messages, because "debug" has a lower priority than "info".
#
# `Logger` also keeps a record of all messages, so that adding a new sink will send all
# previous messages to the new sink.
class Logger
  singleton_class

  # A logging sink is either an `IO` or a `LogMode`.
  alias Sink = IO | LogMode

  LEVELS = %w(debug info warn error) # in order!

  @level = 0

  # Sets the logging level to that defined by the environment variable
  # `CSUP_LOG_LEVEL`, if defined.  Otherwise sets it to "info".
  def initialize(level = "info")
    singleton_pre_init
    if ENV.has_key?("CSUP_LOG_LEVEL")
      level = ENV["CSUP_LOG_LEVEL"]
    end
    set_level(level)
    #@mutex = Mutex.new
    @buf = IO::Memory.new
    @sinks = [] of Sink
    singleton_post_init
  end

  # Returns the string for the current logging level ("info", "debug", etc.).
  def level : String
    LEVELS[@level]
  end
  singleton_method level

  # Sets the current logging level to the string specified by *level* ("info", "debug", etc.).
  def set_level(level : String)
    @level = LEVELS.index(level) ||
      raise ArgumentError.new("invalid log level #{level.inspect}: should be one of #{LEVELS.join(", ")}")
  end

  # Sets the current logging level to the string specified by *level* ("info", "debug", etc.).
  def Logger.level=(level)
    self.instance.set_level(level)
  end

  # Adds a sink to the list of objects that receive logging messages.
  def add_sink(s : Sink, copy_current=true)
    #@mutex.synchronize do
      @sinks << s
      #STDERR.puts "add_sink: adding sink #{s.class.name}"
      s << @buf.to_s if copy_current
    #end
  end
  singleton_method add_sink, s

  # Deletes a sink from the list of sinks that receive logging messages.
  def remove_sink(s : Sink)
    #@mutex.synchronize do
      @sinks.delete s
    #end
  end
  singleton_method remove_sink, s

  # Removes all sinks, so that logging will now have no effect.
  def remove_all_sinks!
    #@mutex.synchronize do
      @sinks.clear
    #end
  end
  singleton_method remove_all_sinks!

  # Clears the accumulated logging message record.
  def clear!
    #@mutex.synchronize do
      @buf = IO::Memory.new
    #end
  end
  singleton_method clear!

  # This macro defines the four methods for the four logging levels (`debug`, `info`, etc.).
  {% for level,index in LEVELS %}
    # Sends a logging message with the level "{{level.id}}".
    def {{level.id}}(s : String)
      if {{index}} >= @level
	send_message(format_message({{level}}, Time.local, s))
      end
    end
    singleton_method {{level.id}}, s
  {% end %}

# Ruby code from sup:
#  LEVELS.each_with_index do |l, method_level|
#    define_method(l) do |s|
#      if method_level >= @level
#        send_message format_message(l, Time.now, s)
#      end
#    end

  # Sends a logging message regardless of the current logging level.
  def force_message(m)
    send_message(format_message("", Time.now, m))
  end
  singleton_method force_message, m


  # Prettifies a log message *msg* based on the level of the message *level*.
  # The message is preceded by the current time, and the string "WARNING"
  # or "ERROR" if *level* is "warn" or "error", respectively.
  private def format_message(level, time, msg) : String
    prefix = case level
      when "warn"; "WARNING: "
      when "error"; "ERROR: "
      else ""
    end
    "[#{time.to_s}] #{prefix}#{msg.rstrip}\n"
  end

  # Distributes the message *m* to all sinks, and flushes the sink's output if the
  # current logging level is "debug".
  private def send_message(m)
    #@mutex.synchronize do
      @sinks.each do |sink|
        sink << m
        sink.flush if sink.responds_to?(:flush) && level == "debug"
      end
      @buf << m
    #end
  end

end	# class Logger

end	# module Redwood

# This macro defines the global "debug", "info", etc. methods, which
# in turn call the corresponding class methods of `Logger`.
{% for level in Redwood::Logger::LEVELS %}
  def {{level.id}}(s : String)
    Redwood::Logger.{{level.id}}(s)
  end
{% end %}
