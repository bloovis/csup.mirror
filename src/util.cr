# Utility functions that lie outside the Redwood namespace,
# mostly extensions to standard classes.

require "./unicode"

# Exceptions

class NameError < Exception
end

class InputSequenceAborted < Exception
end

class StandardError < Exception
end

# Extensions to the `String` class
class String
  # Returns the size in characters (not bytes) of this String.
  def length
    size
  end

  # Returns the display width of the string; useful for strings
  # containing UTF-8 characters that require more than one space to display.
  def display_length
    Unicode.width(self)
  end

  # Returns this String truncated on the right to fit the display length *len*.
  def slice_by_display_length(len)
    # Chop it down to the maximum allowable size before attempting to
    # get the Unicode width.
    s = self[0, len]

    # Chop off characters on the right until the display length fits.
    while Unicode.width(s) > len
      s = s.rchop
    end
    return s
  end

  # Returns this String with camel-case names replaced with hyphenated names,
  # and then converted to lowercase.  For example, it converts "InboxMode" to
  # "inbox-mode".
  def camel_to_hyphy
    self.gsub(/([a-z])([A-Z0-9])/, "\\1-\\2").downcase
  end

  # Returns this String split into multiple strings, each of which has
  # a display length no greater than *len*.
  def wrap(len) : Array(String)
    ret = [] of String
    s = self
    while s.display_length > len
      slice = s.slice_by_display_length(len)
      cut = slice.rindex(/\s/)
      if cut
        ret << s[0 ... cut]
        s = s[(cut + 1) .. -1]
      else
        ret << slice
        s = s[slice.size .. -1]
      end
    end
    ret << s
  end

  # Returns this String padded on the left with spaces to make
  # the display length equal to *width*.
  def pad_left(width : Int32)
    pad = width - self.display_length
    " " * pad + self
  end

  # Returns this String padded on the right with spaces to make
  # the display length equal to *width*.
  def pad_right(width : Int32)
    pad = width - self.display_length
    self + " " * pad
  end

  def to_sym
    raise "Crystal doesn't support changing string '#{self}' to a symbol!"
  end

  # Returns this string with tabs replaced by sequences of four spaces,
  # and carriage returns removed entirely.
  def normalize_whitespace
    #fix_encoding!
    gsub(/\t/, "    ").gsub(/\r/, "")
  end

  # Splits this string on commas, unless they occur within double quotes.
  # This uses a very complicated regex found on teh internets.
  def split_on_commas
    normalize_whitespace.split(/,\s*(?=(?:[^"]*"[^"]*")*(?![^"]*"))/)
  end

  # Splits this string on commas, unless they occur within double quotes.
  # But unlike `split_on_commas`, here we do it the hard way, because we
  # need to return a remainder for purposes of tab-completing full email addresses.
  # Returns a tuple, the first element of which is the array of splits, and
  # the second element of which is the remainder (or nil if none).
  def split_on_commas_with_remainder : Tuple(Array(String), String?)
    ret = Array(String).new
    state = :outstring
    pos = 0
    region_start = 0
    while pos <= size
      newpos = case state
        when :escaped_instring, :escaped_outstring then pos
        else index(/[,"\\]/, pos)
      end

      if newpos
        char = self[newpos]
      else
        char = nil
        newpos = size
      end

      case char
      when '"'
        state = case state
          when :outstring then :instring
          when :instring then :outstring
          when :escaped_instring then :instring
          when :escaped_outstring then :outstring
        end
      when ',', nil
        state = case state
          when :outstring, :escaped_outstring then
            ret << self[region_start ... newpos].gsub(/^\s+|\s+$/, "")
            region_start = newpos + 1
            :outstring
          when :instring then :instring
          when :escaped_instring then :instring
        end
      when '\\'
        state = case state
          when :instring then :escaped_instring
          when :outstring then :escaped_outstring
          when :escaped_instring then :instring
          when :escaped_outstring then :outstring
        end
      end
      pos = newpos + 1
    end

    remainder = case state
      when :instring
        self[region_start .. -1].gsub(/^\s+/, "")
      else
        nil
      end

    {ret, remainder}
  end

  # Returns this string, which is a pathname, replacing a leading `~`
  # or `~user` with the actual full path of that user's home directory.
  def untwiddle
    s = self
    if s =~ /(~([^\s\/]*))/ # twiddle directory expansion
      full = $1
      name = $2
      if name.empty?
	dir = Path.home.to_s
      else
	if u = System::User.find_by?(name: name)
	  dir = u.home_directory
	else
	  dir = "~#{name}"        # probably doesn't exist!
	end
      end
      return s.sub(full, dir)
    else
      return s
    end
  end

end

# Extensions to the `Enumerable` class.
module Enumerable
  # Like `find`, except returns the value of the block rather than the
  # element itself.
  def argfind
    ret = nil
    find { |e| ret ||= yield(e) }
    ret || nil # force
  end

  # Same as `size`.
  def length
    size
  end

  # Returns true if `x` is a member of this `Enumerable`.
  def member?(x)
    !index(x).nil?
  end

  # Returns the largest value of this `Enumerable`.
  def max_of
    map { |e| yield e }.max
  end

  # Returns the largest shared prefix of this `Enumerable`,
  # which must be an array of Strings.
  def shared_prefix(caseless = false, exclude = "")
    return "" if size == 0
    prefix = ""
    (0 ... first.size).each do |i|
      c = (caseless ? first.downcase : first)[i]
      break unless all? { |s| (caseless ? s.downcase : s)[i]? == c }
      next if exclude[i]? == c
      prefix += first[i].to_s
    end
    prefix
  end

end

# Extensions to the `Int` class.
struct Int
  # Returns a string that represents large numbers in an
  # easy-to-understand format.
  def to_human_size : String
    if self < 1024
      to_s + "B"
    elsif self < (1024 * 1024)
      (self // 1024).to_s + "KiB"
    elsif self < (1024 * 1024 * 1024)
      (self // 1024 // 1024).to_s + "MiB"
    else
      (self // 1024 // 1024 // 1024).to_s + "GiB"
    end
  end

  # Returns the plural of a number.  Definitely cheesy, but it keeps
  # existing Sup code happy, even if if it's not always correct.
  def pluralize(s : String) : String
    if self != 1
      if s =~/(.*)y$/
	"#{self} #{$1}ies"
      else
	"#{self} #{s}s"
      end
    else
      "#{self} #{s}"
    end
  end

end

# `SavingHash` acts like a hash with an initialization block, but saves any
# newly-created value even upon lookup.
#
# For example:
#
# ```
# class C
#   property val
#   def initialize; @val = 0 end
# end
#
# h = Hash(Symbol, C).new { C.new }
# h[:a].val # => 0
# h[:a].val = 1
# h[:a].val # => 0
#
# h2 = SavingHash(Symbol, C).new { C.new }
# h2[:a].val # => 0
# h2[:a].val = 1
# h2[:a].val # => 1
# ```
#
# Important note: you REALLY want to use `has_key?` to test existence,
# because just checking `h[anything]` will always evaluate to true
# (except for degenerate constructor blocks that return nil or false).
class SavingHash(K,V) < Hash(K,V)
  # Saves the block as the value constructor for the hash.
  def initialize(&b : K -> V)
    super
    @constructor = b
    @hash = Hash(K,V).new
  end

  # If the key *k* exists, returns its corresponding value;
  # otherwise calls the constructor to create a new entry
  # for this key and returns its value.
  def [](k : K)
    if @hash.has_key?(k)
      @hash[k]
    else
      @hash[k] = @constructor.call(k)
    end
  end

  # Calls the block *b* with each key and value in the hash.
  def each(&b : K, V -> _)
    @hash.each(&b)
  end

  forward_missing_to @hash
end

# `SparseArray` implements an array that simulates a Ruby array.
# Sup expects Ruby arrays to be sparse, i.e., a value can be read or assigned
# with an index that is greater than the current array size.  But Crystal
# arrays don't work that way, so this class simulates that behavior for
# the `[i]` and `[i]=` operators.
class SparseArray(T) < Array(T?)
  # If the index *i* is less than the array size, returns the value thus indexed.
  # Otherwise it extends the array to encompass that index, filling in the new values
  # with nil, and returns nil.
  def [](i)
    if i >= size
      (size..i).each {|n| self.<<(nil)}
      nil
    else
      super
    end
  end

  # If the index *i* is less than the array size, sets the value thus indexed to *v*.
  # Otherwise it extends the array to encompass that index, filling in the new values
  # with nil, and sets the value indexed by *i* to *v*.
  def []=(i : Int32, v : T)
    #STDERR.puts "SparseArray [#{i}]= #{v.object_id} (#{v.class.name}), caller #{caller[1]}"
    if i >= size
      if i > 0
	(size..i-1).each {|n| self.<<(nil)}
      end
      self << v
    else
      super
    end
  end
end

# Extensions to the `File` class.
class File
  # Returns the modification time for the file *fname*.  Provided
  # for Ruby compatibility.
  def self.mtime(fname : String) : Time
    File.info(fname).modification_time
  end
end

# Extensions to the `URI` class.
class URI
  # Returns a regular expression that matches URIs.  This is 
  # a shameless copy of Ruby's `URI::regexp`.
  def self.regexp
/
        ([a-zA-Z][\-+.a-zA-Z\d]*):                           (?# 1: scheme)
        (?:
           ((?:[\-_.!~*'()a-zA-Z\d;?:@&=+$,]|%[a-fA-F\d]{2})(?:[\-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*)                    (?# 2: opaque)
        |
           (?:(?:
             \/\/(?:
                 (?:(?:((?:[\-_.!~*'()a-zA-Z\d;:&=+$,]|%[a-fA-F\d]{2})*)@)?        (?# 3: userinfo)
                   (?:((?:(?:[a-zA-Z0-9\-.]|%\h\h)+|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[(?:(?:[a-fA-F\d]{1,4}:)*(?:[a-fA-F\d]{1,4}|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})|(?:(?:[a-fA-F\d]{1,4}:)*[a-fA-F\d]{1,4})?::(?:(?:[a-fA-F\d]{1,4}:)*(?:[a-fA-F\d]{1,4}|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}))?)\]))(?::(\d*))?))? (?# 4: host, 5: port)
               |
                 ((?:[\-_.!~*'()a-zA-Z\d$,;:@&=+]|%[a-fA-F\d]{2})+)                 (?# 6: registry)
               )
             |
             (?!\/\/))                           (?# XXX: '\/\/' is the mark for hostport)
             (\/(?:[\-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*(?:;(?:[\-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*)*(?:\/(?:[\-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*(?:;(?:[\-_.!~*'()a-zA-Z\d:@&=+$,]|%[a-fA-F\d]{2})*)*)*)?                    (?# 7: path)
           )(?:\?((?:[\-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*))?                 (?# 8: query)
        )
        (?:\#((?:[\-_.!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]|%[a-fA-F\d]{2})*))?                  (?# 9: fragment)
      /x
  end
end

# Defines a getter for a boolean instance variable with the name
# of the variable followed by '?'.
macro bool_getter(*names)
  {% for name in names %}
    getter {{name.id}} : Bool
    def {{name.id}}?; {{name.id}}; end
  {% end %}
end

# Defines a property for a boolean instance variable with the name
# of the variable followed by '?'.
macro bool_property(*names)
  {% for name in names %}
    property {{name.id}} : Bool
    def {{name.id}}?; {{name.id}}; end
  {% end %}
end
