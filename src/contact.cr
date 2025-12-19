require "./person"
require "./singleton"

module Redwood

# `ContactManager` is a singleton class that manages the list of
# contacts, which are saved in the file `~/.csup/contacts.txt`.
class ContactManager
  singleton_class

  # Filename containing the contacts list.
  @fn = ""

  # Maps a `Person` object to an alias name.
  @p2a = {} of Person => String

  # Maps an alias name to a `Person` object.
  @a2p = {} of String => Person		# alias to person

  # Maps an email address to a `Person` object.
  @e2p = {} of String => Person		# email to person

  # Reads the contact list from `~/.csup/contacts.txt` and initializes
  # the various hashes for it (Person => alias, alias => Person, and
  # email => Person).
  def initialize(fn : String)
    singleton_pre_init
    @fn = fn
    if File.exists?(fn)
      File.each_line(fn) do |l|
        if l =~ /^([^:]*):\s*(.*)$/
          aalias, addr = $1, $2
          update_alias(Person.from_address(addr), aalias)
	else
	  raise "can't parse #{fn} line #{l.inspect}"
	end
      end
    end
    @modified = false
    singleton_post_init
  end

  # Returns the contacts list as array of `Person` objects.
  def contacts : Array(Person)
    @p2a.keys
  end
  singleton_method contacts

  # Returns the list of contacts that have aliases as an array of `Person` objects.
  def contacts_with_aliases : Array(Person)
    @a2p.values.uniq
  end
  singleton_method contacts_with_aliases

  def update_alias(person : Person, aalias : (String | Nil) = nil)
    ## Deleting old data if it exists
    old_aalias = @p2a[person]?
    if old_aalias
      @a2p.delete old_aalias
      @e2p.delete person.email
    end
    ## Update with new data
    @p2a[person] = aalias
    unless aalias.nil? || aalias.empty?
      @a2p[aalias] = person
      @e2p[person.email] = person
    end
    @modified = true
  end
  singleton_method update_alias, person, aalias

  # Returns the `Person` for the given alias, or nil if not found.
  def contact_for(aalias : String) : Person?
    @a2p[aalias]?
  end
  singleton_method contact_for, aalias

  # Returns the alias for given `Person`, or nil if not found.
  def alias_for(person : Person) : String?
    @p2a[person]?
  end
  singleton_method alias_for, person

  # Return the email for given alias, or nil if not found.
  def email_for(aalias : String) : String?
    if p = @a2p[aalias]?
      return p.full_address
    else
      return nil
    end
  end
  singleton_method email_for, aalias

  # Returns the `Person` for the given email address, or nil if not found.
  def person_for(email : String) : Person?
    @e2p[email]?
  end
  singleton_method person_for, email

  # Returns true if the given `Person` has an alias.
  def is_aliased_contact?(person : Person) : Bool
    if p = @p2a[person]?
      # In Csup, we use an empty string instead of nil to mean "no alias".
      return !p.empty?
    else
      return false
    end
  end
  singleton_method is_aliased_contact?, person

  # If the contact list has been modified since it was read in,
  # writes the contact list back out to `~/.csup/contacts.txt`.
  def save
    return unless @modified
    File.open(@fn, "w") do |f|
      @p2a.to_a.sort_by { |t| {t[0].full_address, t[1]} }.each do |t|
        f.puts "#{t[1] || ""}: #{t[0].full_address}"
      end
    end
  end
  singleton_method save

end	# class ContactManager

end	# module Redwood

