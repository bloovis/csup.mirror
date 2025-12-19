require "./contact"

module Redwood

# A `Person` object contains two pieces of information about a person:
# the name (optional), and the email address.
class Person
  property name : (String | Nil)
  property email : String

  # Save *name* (if non-nil) and *email*.
  #
  # If *name* is non-nil, condense strings of spaces to a single space,
  # strip leading and trailing quotes, and change two-backslash sequences
  # into a single backslash.
  #
  # Condense strings of spaces in *email* to a single space.
  # after condensing
  def initialize(name : (String | Nil), email : String)
    if name
      name = name.strip.gsub(/\s+/, " ")
      name =~ /^(['"]\s*)(.*?)(\s*["'])$/ ? $2 : name
      name.gsub("\\\\", "\\")
    end
    @name = name
    @email = email.strip.gsub(/\s+/, " ")
  end

  # Constructs a person's name suitable for an email header such as To:, by combining 
  # the name (if non-nil) and the email address.
  def to_s
    if @name
      "#{@name} <#{@email}>"
    else
      @email
    end
  end

  # Returns the shortened version of the person's name, typically
  # the first name.
  def shortname
    case @name
    when /\S+, (\S+)/
      $1
    when /(\S+) \S+/
      $1
    when nil
      @email
    else
      @name
    end
  end

  # Returns the person's full name if it is non-nil; otherwise returns the email address.
  def mediumname; @name || @email; end

  # Return the person's long-form name-plus-email, same as #to_s.
  def longname
    to_s
  end

  # Returns the person's long-form name-plus-email, same as #to_s except
  # that double quotes in the name are escaped with backslashes.
  def full_address
    Person.full_address @name, @email
  end

  # Returns the key to be used when when sorting Persons by addresses,
  # typically the last word of the name before a comma.
  def sort_by_me
    name = @name || ""
    case name
    when /^(\S+), \S+/
      $1
    when /^\S+ \S+ (\S+)/
      $1
    when /^\S+ (\S+)/
      $1
    when ""
      @email || ""
    else
      name
    end.downcase
  end

  # Class methods

  # Returns the `Person` in the contacts list associated with the email address *email*,
  # or a new `Person` if such a contact does not exist.
  def self.from_name_and_email(name : (String | Nil), email : String)
    if ContactManager.instantiated?
      p = ContactManager.person_for(email)
      return p if p
    end
    Person.new(name, email)
  end

  # Returns the combined name and email, same as `Person#to_s` except
  # that double quotes in the name are escaped with backslashes.
  def self.full_address(name : (String | Nil), email : (String | Nil))
    if name && email
      if name =~ /[",@]/
	"#{name.inspect} <#{email}>" # escape quotes
      else
	"#{name} <#{email}>"
      end
    else
      email
    end
  end

  # Parses the string *s* into a name and email address, then calls
  # `from_name_and_email` to return either that `Person` from the contacts
  # list or a new `Person`.
  def self.from_address(s : String)
    ## try and parse an email address and name
    name, email = case s
      when /(.+?) ((\S+?)@\S+) \3/
	# ok, this first match cause is insane, but bear with me.  email
	# addresses are stored in the to/from/etc fields of the index in a
	# weird format: "name address first-part-of-address", i.e.  spaces
	# separating those three bits, and no <>'s. this is the output of
	# #indexable_content. here, we reverse-engineer that format to extract
	# a valid address.
	#
	# we store things this way to allow searches on a to/from/etc field to
	# match any of those parts. a more robust solution would be to store a
	# separate, non-indexed field with the proper headers. but this way we
	# save precious bits, and it's backwards-compatible with older indexes.
	{$1, $2}
      when /["'](.*?)["'] <(.*?)>/, /([^,]+) <(.*?)>/
	a, b = $1, $2
	{a.gsub("\\\"", "\""), b}
      when /<((\S+?)@\S+?)>/
	{$2, $1}
      when /((\S+?)@\S+)/
	{$2, $1}
      else
	{nil, s}
      end

    self.from_name_and_email name, email
  end

  # Return an array of `Person` objects for a
  # string of comma-separated email address.  The `Person` objects
  # will either be ones found in the contacts list, or new ones
  # if they are not found in the contacts.
  def self.from_address_list(ss : String?) : Array(Person)
    return Array(Person).new if ss.nil?
    ss.split_on_commas.map { |s| self.from_address s }
  end


end	# class Person

end	# module Redwood
