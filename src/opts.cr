require "json"
require "./message"

module Redwood

# `HeaderHash` represents message headers, which can either be a single
# string or any array of strings.
alias HeaderHash = Hash(String, String | Array(String))

# `Opts` is a `Hash`-like class of key/value pairs, for passing options to methods
# in `Mode` and its subclasses.
#
# A key is a `Symbol`.
#
# A value can be any one of the following types:
# * `String`
# * `Int32`
# * `Bool`
# * `Symbol`
# * `Array(String)`
# * `HeaderHash`
# * `Message`
class Opts
  alias Value = String | Int32 | Bool | Symbol | Array(String) |
		HeaderHash | JSON::Any | Message

  # Creates a new `Opts` hash, copying values from `h` (if `h` is not nil).
  def initialize(h = nil)
    @entries = Hash(Symbol, Value).new
    if h
      #puts "Opts.initialize: h = " + h.inspect
      merge(h)
    end
  end

  # Stores a key/value pair in this `Opts`.
  def []=(key : Symbol, value)
    @entries[key] = value
  end

  # Merges the values from Hash `h` into this `Opts`.
  def merge(h)
    @entries.merge!(h)
  end

  # :nodoc:
  macro get(name, type)
    # `{{name}}` retrieves a value of type `{{type}}`, given the key `key`,
    # or `nil` if there was no such value.
    def {{name}}(key : Symbol) : {{type}}?
      if @entries.has_key?(key)
	return @entries[key].as({{type}})
      else
	return nil
      end
    end
    # `delete_{{name}}` deletes a value of type {{type}}, given the key `key`,
    # and returns the deleted value, or `nil` if there was no such value.
    def delete_{{name}}(key : Symbol | String) : {{type}}?
      if @entries.has_key?(key)
	return @entries.delete(key).as({{type}})
      else
	return nil
      end
    end
  end

  # Returns `true` if this `Opts` contains the key `s`.
  def member?(s : Symbol)
    @entries.has_key?(s)
  end

  get(str, String)
  get(int, Int32)
  get(bool, Bool)
  get(sym, Symbol)
  get(strarray, Array(String))
  get(hash, HeaderHash)
  get(message, Message)

end	# Opts

end	# Redwood

